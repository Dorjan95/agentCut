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
}
