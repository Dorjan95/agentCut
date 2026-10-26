import Foundation
import Testing
@testable import AgentCutCore

struct ClaudeCodeProviderTests {
    let request = AgentRequest(systemPrompt: "SYS", userPrompt: "USER", model: "haiku")

    func delta(_ text: String) -> String {
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}}"#
    }

    @Test func claudeArgumentsIncludeModelAndNoTools() {
        let args = ClaudeCodeProvider.arguments(for: request)
        #expect(Array(args.prefix(5)) == ["-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose"])
        let tools = try! #require(args.firstIndex(of: "--tools"))
        #expect(args[tools + 1] == "")
        let sys = try! #require(args.firstIndex(of: "--system-prompt"))
        #expect(args[sys + 1] == "SYS")
        #expect(args.contains("--strict-mcp-config"))
        // Niente impostazioni, hook e plugin dell'utente: più veloce e nessun effetto collaterale.
        let sources = try! #require(args.firstIndex(of: "--setting-sources"))
        #expect(args[sources + 1] == "")
        #expect(args.contains("--no-session-persistence"))
        let model = try! #require(args.firstIndex(of: "--model"))
        #expect(args[model + 1] == "haiku")

        var noModel = request
        noModel.model = nil
        #expect(!ClaudeCodeProvider.arguments(for: noModel).contains("--model"))
    }

    @Test func claudeDecodesTextDelta() {
        #expect(ClaudeCodeProvider.decode(line: delta("ciao")) == .textDelta("ciao"))
        #expect(ClaudeCodeProvider.decode(line: #"{"type":"system","subtype":"init"}"#) == nil)
        #expect(ClaudeCodeProvider.decode(line: "not json") == nil)
        #expect(ClaudeCodeProvider.decode(line: #"{"type":"result","is_error":false,"result":"ok"}"#) == .result(isError: false, text: "ok"))
    }

    @Test func claudeStreamYieldsDeltas() async throws {
        let runner = FakeRunner(lines: [delta("KIND"), delta(": answer"), #"{"type":"result","is_error":false,"result":"KIND: answer"}"#])
        let provider = ClaudeCodeProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        #expect(try await collect(provider.stream(request)) == ["KIND", ": answer"])
        #expect(runner.lastStdin == "USER")
    }

    @Test func claudeNotLoggedInMapsToNotAuthenticated() async {
        let runner = FakeRunner(lines: [#"{"type":"result","is_error":true,"result":"Not logged in · Please run /login"}"#])
        let provider = ClaudeCodeProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        await #expect(throws: AgentError.notAuthenticated(.claudeCode)) {
            _ = try await collect(provider.stream(request))
        }
    }

    @Test func claudePlainNotLoggedInLineMapsToNotAuthenticated() async {
        // Con --bare o versioni diverse la CLI stampa testo semplice e non JSON.
        let runner = FakeRunner(lines: ["Not logged in · Please run /login"])
        let provider = ClaudeCodeProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        await #expect(throws: AgentError.notAuthenticated(.claudeCode)) {
            _ = try await collect(provider.stream(request))
        }
    }

    @Test func processFailureWithLoginHintMapsToNotAuthenticated() async {
        let runner = FakeRunner(lines: [], error: AgentError.processFailed(exitCode: 1, stderr: "Please run /login"))
        let provider = ClaudeCodeProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        await #expect(throws: AgentError.notAuthenticated(.claudeCode)) {
            _ = try await collect(provider.stream(request))
        }
    }

    @Test func claudeErrorResultThrowsProcessFailed() async {
        let runner = FakeRunner(lines: [#"{"type":"result","is_error":true,"result":"overloaded"}"#])
        let provider = ClaudeCodeProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: runner)
        await #expect(throws: AgentError.processFailed(exitCode: 1, stderr: "overloaded")) {
            _ = try await collect(provider.stream(request))
        }
    }

    @Test func emptyStreamThrowsEmptyResponse() async {
        let provider = ClaudeCodeProvider(executable: fakeURL, workingDirectory: fakeWorkDir, runner: FakeRunner(lines: []))
        await #expect(throws: AgentError.emptyResponse) {
            _ = try await collect(provider.stream(request))
        }
    }

    @Test func makeProviderReturnsCliNotFound() {
        var settings = AppSettings()
        settings.agent = .codex
        let locator = CLILocator(searchDirectories: [], isExecutable: { _ in false })
        let result = AgentEnvironment.makeProvider(settings: settings, locator: locator, runner: FakeRunner(lines: []))
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error == .cliNotFound(.codex))
    }

    @Test func makeProviderBuildsSelectedAgent() throws {
        let locator = CLILocator(searchDirectories: [URL(fileURLWithPath: "/x")], isExecutable: { _ in true })
        let provider = try AgentEnvironment.makeProvider(settings: AppSettings(), locator: locator, runner: FakeRunner(lines: [])).get()
        #expect(provider.kind == .claudeCode)
    }
}
