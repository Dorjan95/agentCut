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
}
