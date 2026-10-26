import Foundation

public enum AgentError: Error, Equatable, Sendable {
    case cliNotFound(AgentKind)
    case notAuthenticated(AgentKind)
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut
    case emptyResponse

    public var userMessage: String {
        switch self {
        case .cliNotFound(let kind):
            "Non trovo la CLI \(kind.executableName). Installala o indica il percorso nelle Impostazioni."
        case .notAuthenticated(let kind):
            "\(kind.displayName) non è autenticato. Apri il Terminale, esegui \(kind.executableName) e fai login."
        case .processFailed(let code, let stderr):
            "L'agente si è interrotto (codice \(code)). \(stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))"
        case .timedOut:
            "Nessuna risposta entro 60 secondi."
        case .emptyResponse:
            "L'agente non ha restituito nulla."
        }
    }
}
