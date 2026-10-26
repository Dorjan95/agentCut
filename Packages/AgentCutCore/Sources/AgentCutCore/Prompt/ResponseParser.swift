import Foundation

public enum ResponseKind: String, Sendable {
    case replace, answer, unclear
}

public struct ParsedResponse: Sendable, Equatable {
    public var kind: ResponseKind
    public var label: String?
    public var note: String?
    public var body: String
    public var headerComplete: Bool

    public init(kind: ResponseKind, label: String? = nil, note: String? = nil, body: String, headerComplete: Bool) {
        self.kind = kind
        self.label = label
        self.note = note
        self.body = body
        self.headerComplete = headerComplete
    }
}

/// Legge in streaming il formato `KIND/LABEL/NOTE` + `---` + corpo.
/// Se il modello non rispetta il formato, tutto il testo diventa una risposta `answer`.
public struct ResponseParser: Sendable {
    private var raw = ""

    public init() {}

    public mutating func feed(_ chunk: String) -> ParsedResponse {
        raw += chunk
        return Self.parse(raw, final: false)
    }

    public mutating func finish() -> ParsedResponse {
        Self.parse(raw, final: true)
    }

    static func parse(_ raw: String, final: Bool) -> ParsedResponse {
        let pending = ParsedResponse(kind: .answer, body: "", headerComplete: false)
        let fallback = ParsedResponse(kind: .answer, body: final ? trimTrailingNewlines(raw) : raw, headerComplete: true)

        let trimmedStart = raw.drop(while: { $0.isWhitespace })
        guard !trimmedStart.isEmpty else { return final ? fallback : pending }

        // La prima riga può essere ancora incompleta ("KIN"): aspettiamo prima di decidere.
        let firstLine = trimmedStart.prefix(while: { $0 != "\n" }).uppercased()
        let looksLikeHeader = firstLine.hasPrefix("KIND:") || (!final && "KIND:".hasPrefix(firstLine))
        guard looksLikeHeader else { return fallback }

        var kind = ResponseKind.answer
        var label: String?
        var note: String?
        var rest = Substring(trimmedStart)

        while let newline = rest.firstIndex(of: "\n") {
            let line = rest[..<newline].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: newline)...]
            if line == "---" {
                let body = final ? cleanBody(String(rest)) : String(rest)
                return ParsedResponse(kind: kind, label: label, note: note, body: body, headerComplete: true)
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "KIND": kind = ResponseKind(rawValue: value.lowercased()) ?? .answer
            case "LABEL": label = value.isEmpty ? nil : value
            case "NOTE": note = value.isEmpty ? nil : value
            default: break
            }
        }

        // Separatore come ultima riga senza "\n" finale.
        if final, rest.trimmingCharacters(in: .whitespaces) == "---" {
            return ParsedResponse(kind: kind, label: label, note: note, body: "", headerComplete: true)
        }
        return final ? fallback : pending
    }

    private static func cleanBody(_ body: String) -> String {
        let trimmed = trimTrailingNewlines(body)
        let lines = trimmed.components(separatedBy: "\n")
        if lines.count >= 2,
           lines.first!.trimmingCharacters(in: .whitespaces).hasPrefix("```"),
           lines.last!.trimmingCharacters(in: .whitespaces) == "```",
           !lines.dropFirst().dropLast().contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) {
            return lines.dropFirst().dropLast().joined(separator: "\n")
        }
        return trimmed
    }

    private static func trimTrailingNewlines(_ s: String) -> String {
        var s = Substring(s)
        while let last = s.last, last.isNewline || last == " " { s = s.dropLast() }
        return String(s)
    }
}
