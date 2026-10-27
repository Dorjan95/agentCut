import Foundation
import Testing
@testable import AgentCutCore

/// Chiamate reali alle CLI: `AGENTCUT_INTEGRATION=1 swift test --filter ProviderIntegrationTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["AGENTCUT_INTEGRATION"] == "1"))
struct ProviderIntegrationTests {
    @Test(arguments: AgentKind.allCases)
    func fixesSQL(agent: AgentKind) async throws {
        var settings = AppSettings()
        settings.agent = agent
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locator = CLILocator(searchDirectories: CLILocator.defaultDirectories(home: home))
        let provider = try AgentEnvironment.makeProvider(settings: settings, locator: locator, runner: ProcessRunner()).get()
        let request = PromptBuilder.build(input: "SELEC name FROM users GROUP name", question: nil, agent: agent, settings: settings)

        var parser = ResponseParser()
        for try await chunk in provider.stream(request) { _ = parser.feed(chunk) }
        let response = parser.finish()

        #expect(response.kind == .replace)
        #expect(response.body.uppercased().contains("GROUP BY"))
    }

    @Test func prewarmedClaudeAnswersFast() async throws {
        let settings = AppSettings()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locator = CLILocator(searchDirectories: CLILocator.defaultDirectories(home: home))
        let runner = PrewarmedRunner(launcher: ProcessRunner())
        defer { runner.stop() }
        let target = try #require(AgentEnvironment.prewarmTarget(settings: settings, locator: locator))
        runner.prepare(executable: target.executable, arguments: target.arguments, workingDirectory: AgentEnvironment.workingDirectory)
        try await Task.sleep(for: .seconds(5))

        let provider = try AgentEnvironment.makeProvider(settings: settings, locator: locator, runner: runner).get()
        for input in ["SELEC name FROM users GROUP name", "{\"a\": 1,}"] {
            let request = PromptBuilder.build(input: input, question: nil, agent: .claudeCode, settings: settings)
            let start = ContinuousClock.now
            var first: Duration?
            var parser = ResponseParser()
            for try await chunk in provider.stream(request) {
                if first == nil { first = ContinuousClock.now - start }
                _ = parser.feed(chunk)
            }
            let total = ContinuousClock.now - start
            print("pre-avviato: primo testo \(first!), totale \(total)")
            #expect(parser.finish().kind == .replace)
            try await Task.sleep(for: .seconds(5))
        }
    }
}
