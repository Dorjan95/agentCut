import Foundation

public enum ClaudeEvent: Equatable, Sendable {
    case textDelta(String)
    case result(isError: Bool, text: String)
}

public struct ClaudeCodeProvider: AgentProvider {
    public let kind = AgentKind.claudeCode
    private let executable: URL
    private let workingDirectory: URL
    private let runner: LineRunning

    public init(executable: URL, workingDirectory: URL, runner: LineRunning) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.runner = runner
    }

    public static func arguments(for request: AgentRequest) -> [String] {
        var args = [
            "-p", "--output-format", "stream-json", "--include-partial-messages", "--verbose",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence", "--setting-sources", "",
            "--system-prompt", request.systemPrompt,
        ]
        if let model = request.model { args += ["--model", model] }
        return args
    }

    public static func decode(line: String) -> ClaudeEvent? {
        guard let json = jsonObject(line), let type = json["type"] as? String else { return nil }
        switch type {
        case "stream_event":
            guard let event = json["event"] as? [String: Any],
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return nil }
            return .textDelta(text)
        case "result":
            return .result(isError: json["is_error"] as? Bool ?? false, text: json["result"] as? String ?? "")
        default:
            return nil
        }
    }

    public func stream(_ request: AgentRequest) -> AsyncThrowingStream<String, Error> {
        let lines = runner.lines(
            executable: executable,
            arguments: Self.arguments(for: request),
            stdin: request.userPrompt,
            workingDirectory: workingDirectory,
            timeout: .seconds(60)
        )
        let sawDelta = Flag()
        return ProviderStreaming.stream(kind: kind, lines: lines) { line in
            switch Self.decode(line: line) {
            case .textDelta(let text):
                sawDelta.set()
                return .text(text)
            case .result(true, let text):
                return .fail(text)
            case .result(false, let text):
                // Se la CLI non ha emesso delta (versioni senza partial messages), usa il risultato finale.
                return sawDelta.isSet ? .ignore : .text(text)
            case nil:
                return .ignore
            }
        }
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
