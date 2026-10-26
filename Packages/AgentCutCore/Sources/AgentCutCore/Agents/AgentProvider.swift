import Foundation

public protocol AgentProvider: Sendable {
    var kind: AgentKind { get }
    /// Restituisce frammenti di testo della risposta; termina con `AgentError` in caso di problemi.
    func stream(_ request: AgentRequest) -> AsyncThrowingStream<String, Error>
}

/// Cosa fare con una riga di output della CLI.
enum LineOutcome {
    case text(String)
    case fail(String)
    case ignore
}

enum ProviderStreaming {
    static let authHints = ["not logged in", "/login", "codex login", "not authenticated"]

    static func looksUnauthenticated(_ text: String) -> Bool {
        let lower = text.lowercased()
        return authHints.contains { lower.contains($0) }
    }

    /// Converte le righe della CLI in frammenti di testo, mappando gli errori su `AgentError`.
    static func stream(
        kind: AgentKind,
        lines: AsyncThrowingStream<String, Error>,
        handle: @escaping @Sendable (String) -> LineOutcome
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var yielded = false
                do {
                    for try await line in lines {
                        switch handle(line) {
                        case .text(let text):
                            guard !text.isEmpty else { continue }
                            yielded = true
                            continuation.yield(text)
                        case .fail(let message):
                            throw looksUnauthenticated(message)
                                ? AgentError.notAuthenticated(kind)
                                : AgentError.processFailed(exitCode: 1, stderr: message)
                        case .ignore:
                            if looksUnauthenticated(line), !line.hasPrefix("{") {
                                throw AgentError.notAuthenticated(kind)
                            }
                        }
                    }
                    if Task.isCancelled { continuation.finish(); return }
                    continuation.finish(throwing: yielded ? nil : AgentError.emptyResponse)
                } catch AgentError.processFailed(let code, let stderr) where looksUnauthenticated(stderr) {
                    _ = code
                    continuation.finish(throwing: AgentError.notAuthenticated(kind))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

func jsonObject(_ line: String) -> [String: Any]? {
    guard line.hasPrefix("{"), let data = line.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}
