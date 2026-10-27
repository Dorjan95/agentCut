import Foundation

public enum AgentEnvironment {
    /// Directory vuota dedicata: così le CLI non caricano CLAUDE.md o AGENTS.md di qualche progetto.
    public static var workingDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agentCut/work", isDirectory: true)
    }

    /// Il comando Claude da tenere pronto con le impostazioni attuali; `nil` se l'agente non lo supporta.
    public static func prewarmTarget(settings: AppSettings, locator: CLILocator) -> (executable: URL, arguments: [String])? {
        guard settings.agent == .claudeCode,
              let executable = locator.locate(AgentKind.claudeCode.executableName, override: settings.claudePathOverride)
        else { return nil }
        let request = PromptBuilder.build(input: "", question: nil, agent: .claudeCode, settings: settings)
        return (executable, ClaudeCodeProvider.arguments(for: request))
    }

    public static func makeProvider(settings: AppSettings, locator: CLILocator, runner: LineRunning) -> Result<AgentProvider, AgentError> {
        let agent = settings.agent
        guard let executable = locator.locate(agent.executableName, override: settings.pathOverride(for: agent)) else {
            return .failure(.cliNotFound(agent))
        }
        switch agent {
        case .claudeCode:
            return .success(ClaudeCodeProvider(executable: executable, workingDirectory: workingDirectory, runner: runner))
        case .codex:
            return .success(CodexProvider(executable: executable, workingDirectory: workingDirectory, runner: runner))
        }
    }
}
