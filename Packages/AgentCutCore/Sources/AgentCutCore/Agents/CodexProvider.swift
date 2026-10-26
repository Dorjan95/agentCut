import Foundation

public enum CodexEvent: Equatable, Sendable {
    case message(String)
    case failed(String)
}

public struct CodexProvider: AgentProvider {
    public let kind = AgentKind.codex
    private let executable: URL
    private let workingDirectory: URL
    private let runner: LineRunning

    public init(executable: URL, workingDirectory: URL, runner: LineRunning) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.runner = runner
    }

    public static func arguments(for request: AgentRequest) -> [String] {
        var args = ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "--json", "-c", "model_reasoning_effort=low"]
        if let model = request.model { args += ["-m", model] }
        return args + ["-"]
    }

    /// Codex non ha un flag per il system prompt: va in testa allo stdin.
    public static func stdin(for request: AgentRequest) -> String {
        request.systemPrompt + "\n\n" + request.userPrompt
    }

    public static func decode(line: String) -> CodexEvent? {
        guard let json = jsonObject(line), let type = json["type"] as? String else { return nil }
        switch type {
        case "item.completed":
            guard let item = json["item"] as? [String: Any],
                  item["type"] as? String == "agent_message",
                  let text = item["text"] as? String
            else { return nil }
            return .message(text)
        case "turn.failed", "error":
            let error = json["error"] as? [String: Any]
            return .failed(error?["message"] as? String ?? json["message"] as? String ?? "Errore di Codex")
        default:
            return nil
        }
    }

    public func stream(_ request: AgentRequest) -> AsyncThrowingStream<String, Error> {
        let lines = runner.lines(
            executable: executable,
            arguments: Self.arguments(for: request),
            stdin: Self.stdin(for: request),
            workingDirectory: workingDirectory,
            timeout: .seconds(60)
        )
        return ProviderStreaming.stream(kind: kind, lines: lines) { line in
            switch Self.decode(line: line) {
            case .message(let text): .text(text)
            case .failed(let message): .fail(message)
            case nil: .ignore
            }
        }
    }
}
