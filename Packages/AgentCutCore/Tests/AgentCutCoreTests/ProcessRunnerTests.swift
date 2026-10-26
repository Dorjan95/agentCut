import Foundation
import Testing
@testable import AgentCutCore

struct ProcessRunnerTests {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("agentcut-runner-\(UUID())")
    let runner = ProcessRunner()

    func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var out: [String] = []
        for try await line in stream { out.append(line) }
        return out
    }

    @Test func streamsLinesFromStdin() async throws {
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], stdin: "a\nb\n", workingDirectory: tmp, timeout: .seconds(5))
        #expect(try await collect(s) == ["a", "b"])
    }

    @Test func nonZeroExitThrows() async {
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo err >&2; exit 3"], stdin: "", workingDirectory: tmp, timeout: .seconds(5))
        await #expect(throws: AgentError.processFailed(exitCode: 3, stderr: "err\n")) {
            _ = try await collect(s)
        }
    }

    @Test func timesOut() async {
        let start = ContinuousClock.now
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], stdin: "", workingDirectory: tmp, timeout: .milliseconds(200))
        await #expect(throws: AgentError.timedOut) {
            _ = try await collect(s)
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func cancellationTerminatesProcess() async throws {
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo $$; exec sleep 30"], stdin: "", workingDirectory: tmp, timeout: .seconds(60))
        let (pidStream, pidCont) = AsyncStream<Int32>.makeStream()
        let task = Task {
            for try await line in s {
                pidCont.yield(Int32(line)!)
            }
        }
        var iterator = pidStream.makeAsyncIterator()
        let pid = try #require(await iterator.next())
        task.cancel()
        try await Task.sleep(for: .milliseconds(300))
        #expect(kill(pid, 0) == -1)
    }

    @Test func extraPathIsPrepended() async throws {
        let s = ProcessRunner(extraPath: [URL(fileURLWithPath: "/custom/bin")]).lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo $PATH"], stdin: "", workingDirectory: tmp, timeout: .seconds(5))
        let out = try await collect(s)
        #expect(out.first?.hasPrefix("/custom/bin:") == true)
    }

    @Test func childExitingBeforeReadingStdinDoesNotCrash() async {
        // 1 MB su stdin verso un processo che esce subito: senza protezione SIGPIPE l'intero processo muore.
        let big = String(repeating: "x", count: 1_000_000)
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 2"], stdin: big, workingDirectory: tmp, timeout: .seconds(5))
        await #expect(throws: AgentError.self) {
            _ = try await collect(s)
        }
    }

    @Test func timeoutFinishesEvenIfChildIgnoresSIGTERM() async {
        let start = ContinuousClock.now
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; sleep 30"], stdin: "", workingDirectory: tmp, timeout: .milliseconds(200))
        await #expect(throws: AgentError.timedOut) {
            _ = try await collect(s)
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func timeoutIsIdleTimeNotTotalTime() async throws {
        // Emette una riga ogni 100 ms per ~600 ms: con timeout di inattività 300 ms deve completare.
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "for i in 1 2 3 4 5 6; do echo $i; sleep 0.1; done"], stdin: "", workingDirectory: tmp, timeout: .milliseconds(300))
        #expect(try await collect(s) == ["1", "2", "3", "4", "5", "6"])
    }

    @Test func splitsOnlyOnNewline() async throws {
        let s = runner.lines(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], stdin: "a\u{2028}b\nc", workingDirectory: tmp, timeout: .seconds(5))
        #expect(try await collect(s) == ["a\u{2028}b", "c"])
    }
}
