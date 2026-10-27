import Foundation
import Testing
@testable import AgentCutCore

/// Processo finto: restituisce righe preimpostate quando riceve stdin.
final class FakeLaunched: LaunchedProcessing, @unchecked Sendable {
    let arguments: [String]
    private let lock = NSLock()
    private var _alive = true
    private var _discarded = false
    private var exitHandlers: [@Sendable () -> Void] = []
    private(set) var sentStdin: String?
    /// Se impostato, la risposta resta aperta finché il test non la chiude.
    var hold: AsyncThrowingStream<String, Error>?

    init(arguments: [String]) { self.arguments = arguments }

    var isAlive: Bool { lock.withLock { _alive } }
    var discarded: Bool { lock.withLock { _discarded } }

    /// Il processo esce da solo.
    func kill() {
        let handlers: [@Sendable () -> Void] = lock.withLock {
            _alive = false
            defer { exitHandlers = [] }
            return exitHandlers
        }
        handlers.forEach { $0() }
    }

    func send(_ stdin: String, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        lock.withLock { sentStdin = stdin }
        if let hold { return hold }
        return AsyncThrowingStream { c in
            c.yield("risposta")
            c.finish()
        }
    }

    func discard() {
        lock.withLock { _discarded = true }
        kill()
    }

    func onExit(_ handler: @escaping @Sendable () -> Void) {
        let exited: Bool = lock.withLock {
            if _alive { exitHandlers.append(handler) }
            return !_alive
        }
        if exited { handler() }
    }
}

final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var _launched: [FakeLaunched] = []
    var launched: [FakeLaunched] { lock.withLock { _launched } }

    func launch(executable: URL, arguments: [String], workingDirectory: URL) -> LaunchedProcessing {
        let process = FakeLaunched(arguments: arguments)
        lock.withLock { _launched.append(process) }
        return process
    }
}

struct PrewarmedRunnerTests {
    let launcher = FakeLauncher()
    let exe = URL(fileURLWithPath: "/fake/claude")
    let dir = URL(fileURLWithPath: "/fake/work")

    func run(_ runner: PrewarmedRunner, args: [String]) async throws -> [String] {
        try await collect(runner.lines(executable: exe, arguments: args, stdin: "IN", workingDirectory: dir, timeout: .seconds(5)))
    }

    /// Gli avvii in background sono asincroni.
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitForLaunches(_ count: Int) async throws {
        try await waitUntil { launcher.launched.count >= count }
    }

    @Test func prepareLaunchesOneWaitingProcess() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.launched.count == 1)
        #expect(launcher.launched[0].sentStdin == nil)
    }

    @Test func matchingRequestUsesWarmProcessThenRefills() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await run(runner, args: ["A"]) == ["risposta"])
        #expect(launcher.launched[0].sentStdin == "IN")
        // Un processo nuovo per la prossima richiesta: ognuno ne serve una sola.
        try await waitForLaunches(2)
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched[1].sentStdin == nil)
    }

    @Test func otherRequestsLaunchFreshAndKeepWarm() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await run(runner, args: ["B"]) == ["risposta"])
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched[1].arguments == ["B"])
        #expect(launcher.launched[0].sentStdin == nil)
        #expect(!launcher.launched[0].discarded)
    }

    @Test func prepareWithNewArgumentsDiscardsOldProcess() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(50))
        runner.prepare(executable: exe, arguments: ["A2"], workingDirectory: dir)
        try await waitForLaunches(2)
        #expect(launcher.launched[0].discarded)
        #expect(launcher.launched[1].arguments == ["A2"])
    }

    @Test func argumentsChangedDuringLaunchRestartWithNewOnes() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        runner.prepare(executable: exe, arguments: ["A2"], workingDirectory: dir)
        try await waitUntil { launcher.launched.last?.arguments == ["A2"] }
        try await Task.sleep(for: .milliseconds(50))
        #expect(launcher.launched.last?.arguments == ["A2"])
        #expect(launcher.launched.dropLast().allSatisfy { $0.discarded })
        #expect(launcher.launched.last?.discarded == false)
    }

    @Test func deadWarmProcessIsReplacedByFreshLaunch() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(50))
        // Morto subito dopo l'avvio: non si rimpiazza da solo, la richiesta parte da zero.
        launcher.launched[0].kill()
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.launched.count == 1)
        #expect(try await run(runner, args: ["A"]) == ["risposta"])
        #expect(launcher.launched[0].sentStdin == nil)
        #expect(launcher.launched[1].sentStdin == "IN")
    }

    @Test func warmProcessExitingLaterIsReplaced() async throws {
        let runner = PrewarmedRunner(launcher: launcher, minLifetime: .milliseconds(50))
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(100))
        launcher.launched[0].kill()
        try await waitForLaunches(2)
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched[1].sentStdin == nil)
        runner.stop()
    }

    @Test func noRefillWhileRequestInFlight() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(50))
        let (hold, holdContinuation) = AsyncThrowingStream<String, Error>.makeStream()
        launcher.launched[0].hold = hold
        let request = Task { try await run(runner, args: ["A"]) }
        try await waitUntil { launcher.launched[0].sentStdin != nil }
        // Le impostazioni cambiano mentre la risposta arriva: il nuovo processo aspetta la fine.
        runner.prepare(executable: exe, arguments: ["A2"], workingDirectory: dir)
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.launched.count == 1)
        holdContinuation.yield("fine")
        holdContinuation.finish()
        #expect(try await request.value == ["fine"])
        try await waitForLaunches(2)
        #expect(launcher.launched[1].arguments == ["A2"])
    }

    @Test func stopDiscardsAndDisablesRefill() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(1)
        try await Task.sleep(for: .milliseconds(50))
        runner.stop()
        #expect(launcher.launched[0].discarded)
        _ = try await run(runner, args: ["A"])
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.launched.count == 2)
    }

    @Test func oldWarmProcessIsRecycled() async throws {
        // Un processo fermo da troppo tempo (sonno, token scaduti) viene sostituito prima che serva.
        let runner = PrewarmedRunner(launcher: launcher, maxAge: .milliseconds(100))
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await waitForLaunches(2)
        #expect(launcher.launched.count >= 2)
        #expect(launcher.launched[0].discarded)
        runner.stop()
    }

    @Test func idleRecyclingStopsAfterLimit() async throws {
        // Senza richieste non si riavvia la CLI all'infinito.
        let runner = PrewarmedRunner(launcher: launcher, maxAge: .milliseconds(30), maxIdleRecycles: 2)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        try await Task.sleep(for: .milliseconds(400))
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched.allSatisfy { $0.discarded })
    }
}
