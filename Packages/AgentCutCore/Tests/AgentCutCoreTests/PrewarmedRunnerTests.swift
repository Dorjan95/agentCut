import Foundation
import Testing
@testable import AgentCutCore

/// Processo finto: restituisce righe preimpostate quando riceve stdin.
final class FakeLaunched: LaunchedProcessing, @unchecked Sendable {
    let arguments: [String]
    private let lock = NSLock()
    private var _alive = true
    private var _discarded = false
    private(set) var sentStdin: String?

    init(arguments: [String]) { self.arguments = arguments }

    var isAlive: Bool { lock.withLock { _alive } }
    var discarded: Bool { lock.withLock { _discarded } }
    func kill() { lock.withLock { _alive = false } }

    func send(_ stdin: String, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        lock.withLock { sentStdin = stdin }
        return AsyncThrowingStream { c in
            c.yield("risposta")
            c.finish()
        }
    }

    func discard() {
        lock.withLock { _discarded = true; _alive = false }
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

    /// Il rimpiazzo parte in modo asincrono a fine risposta.
    func waitForLaunches(_ count: Int) async throws {
        for _ in 0..<100 where launcher.launched.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func prepareLaunchesOneWaitingProcess() {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        #expect(launcher.launched.count == 1)
        #expect(launcher.launched[0].sentStdin == nil)
    }

    @Test func matchingRequestUsesWarmProcessThenRefills() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        #expect(try await run(runner, args: ["A"]) == ["risposta"])
        #expect(launcher.launched[0].sentStdin == "IN")
        // Un processo nuovo per la prossima richiesta: ognuno ne serve una sola.
        try await waitForLaunches(2)
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched[1].sentStdin == nil)
    }

    @Test func otherRequestsLaunchFreshWithoutRefill() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        #expect(try await run(runner, args: ["B"]) == ["risposta"])
        try await Task.sleep(for: .milliseconds(100))
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched[1].arguments == ["B"])
        #expect(launcher.launched[0].sentStdin == nil)
        #expect(!launcher.launched[0].discarded)
    }

    @Test func prepareWithNewArgumentsDiscardsOldProcess() {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        runner.prepare(executable: exe, arguments: ["A2"], workingDirectory: dir)
        #expect(launcher.launched.count == 2)
        #expect(launcher.launched[0].discarded)
        #expect(launcher.launched[1].arguments == ["A2"])
    }

    @Test func deadWarmProcessIsReplacedByFreshLaunch() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
        launcher.launched[0].kill()
        #expect(try await run(runner, args: ["A"]) == ["risposta"])
        #expect(launcher.launched[0].sentStdin == nil)
        #expect(launcher.launched[1].sentStdin == "IN")
    }

    @Test func stopDiscardsAndDisablesRefill() async throws {
        let runner = PrewarmedRunner(launcher: launcher)
        runner.prepare(executable: exe, arguments: ["A"], workingDirectory: dir)
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
}
