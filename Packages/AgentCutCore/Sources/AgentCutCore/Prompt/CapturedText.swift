import Foundation

public enum InputSource: Sendable, Equatable {
    case selection, clipboard
}

/// Il testo su cui l'utente ha richiamato agentCut.
public struct CapturedText: Sendable, Equatable {
    public var text: String
    public var source: InputSource

    public init(text: String, source: InputSource) {
        self.text = text
        self.source = source
    }
}

/// Richiesta pronta da passare a una CLI.
public struct AgentRequest: Sendable, Equatable {
    public var systemPrompt: String
    public var userPrompt: String
    public var model: String?

    public init(systemPrompt: String, userPrompt: String, model: String?) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.model = model
    }
}
