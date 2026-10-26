import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode, codex

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    public var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var agent: AgentKind = .claudeCode
    public var claudeModel = "haiku"
    /// Vuoto = modello predefinito della CLI.
    public var codexModel = ""
    public var language = "Italiano"
    public var userSystemPrompt = ""
    public var claudePathOverride = ""
    public var codexPathOverride = ""

    public init() {}

    /// Modello da passare alla CLI, `nil` se non impostato.
    public func model(for agent: AgentKind) -> String? {
        let value = switch agent {
        case .claudeCode: claudeModel
        case .codex: codexModel
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func pathOverride(for agent: AgentKind) -> String {
        switch agent {
        case .claudeCode: claudePathOverride
        case .codex: codexPathOverride
        }
    }
}
