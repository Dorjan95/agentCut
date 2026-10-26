import Foundation

public enum AgentEnvironment {
    /// Directory vuota dedicata: così le CLI non caricano CLAUDE.md o AGENTS.md di qualche progetto.
    public static var workingDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("agentCut/work", isDirectory: true)
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
