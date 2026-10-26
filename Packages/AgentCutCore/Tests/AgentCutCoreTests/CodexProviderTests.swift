import Foundation
import Testing
@testable import AgentCutCore

struct CodexProviderTests {
    let request = AgentRequest(systemPrompt: "SYS", userPrompt: "USER", model: nil)
    let message = #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"ciao"}}"#

    @Test func codexArgumentsEndWithDash() {
        #expect(CodexProvider.arguments(for: request) == ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "--json", "-c", "model_reasoning_effort=low", "-"])
        var withModel = request
        withModel.model = "gpt-5"
        #expect(CodexProvider.arguments(for: withModel).suffix(3) == ["-m", "gpt-5", "-"])
    }

    @Test func codexStdinConcatenatesPrompts() {
        #expect(CodexProvider.stdin(for: request) == "SYS\n\nUSER")
    }

    @Test func codexDecodesAgentMessage() {
        #expect(CodexProvider.decode(line: message) == .message("ciao"))
        #expect(CodexProvider.decode(line: #"{"type":"turn.started"}"#) == nil)
        #expect(CodexProvider.decode(line: #"{"type":"item.completed","item":{"type":"reasoning","text":"x"}}"#) == nil)
    }

    @Test func codexStreamYieldsMessage() async throws {
        let runner = FakeRunner(lines: [#"{"type":"thread.started"}"#, message, #"{"type":"turn.completed"}"#])
        let provider = CodexProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        #expect(try await collect(provider.stream(request)) == ["ciao"])
        #expect(runner.lastStdin == "SYS\n\nUSER")
    }

    @Test func codexFailedThrows() async {
        let runner = FakeRunner(lines: [#"{"type":"turn.failed","error":{"message":"boom"}}"#])
        let provider = CodexProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        #expect(CodexProvider.decode(line: #"{"type":"error","message":"bad"}"#) == .failed("bad"))
        await #expect(throws: AgentError.processFailed(exitCode: 1, stderr: "boom")) {
            _ = try await collect(provider.stream(request))
        }
    }

    @Test func codexLoginFailureMapsToNotAuthenticated() async {
        let runner = FakeRunner(lines: [], error: AgentError.processFailed(exitCode: 1, stderr: "Error: not authenticated, run codex login"))
        let provider = CodexProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        await #expect(throws: AgentError.notAuthenticated(.codex)) {
            _ = try await collect(provider.stream(request))
        }
    }
}
