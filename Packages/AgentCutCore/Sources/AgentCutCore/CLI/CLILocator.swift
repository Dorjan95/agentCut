import Foundation

/// Trova gli eseguibili delle CLI: le app avviate dal Finder non ereditano la PATH della shell.
public struct CLILocator: Sendable {
    public let searchDirectories: [URL]
    private let isExecutable: @Sendable (URL) -> Bool

    public static func defaultDirectories(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".npm-global/bin"),
            home.appendingPathComponent(".bun/bin"),
        ]
    }

    public init(
        searchDirectories: [URL],
        isExecutable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) {
        self.searchDirectories = searchDirectories
        self.isExecutable = isExecutable
    }

    /// Un override non vuoto vince sempre: se non è eseguibile restituisce `nil`, senza ripiegare sulla ricerca.
    public func locate(_ name: String, override: String) -> URL? {
        let override = override.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return isExecutable(url) ? url : nil
        }
        return searchDirectories
            .map { $0.appendingPathComponent(name) }
            .first(where: isExecutable)
    }
}

public enum LoginShellPath {
    static let startMarker = "__AGENTCUT_PATH__"
    static let endMarker = "__END__"

    /// Directory della PATH della shell dell'utente, letta in modalità login + interattiva
    /// (così include anche ciò che aggiunge `.zshrc`, ad esempio nvm). Timeout 3 s.
    public static func directories() async -> [URL] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let stream = ProcessRunner().lines(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-l", "-i", "-c", "printf '\(startMarker)%s\(endMarker)' \"$PATH\""],
            stdin: "",
            workingDirectory: FileManager.default.temporaryDirectory,
            timeout: .seconds(3)
        )
        var output = ""
        do {
            for try await line in stream { output += line + "\n" }
        } catch {
            // Anche se la shell esce con errore, la PATH potrebbe essere già stata stampata.
        }
        return parse(output)
    }

    /// Estrae la PATH tra i marcatori, ignorando ciò che la shell interattiva stampa intorno.
    static func parse(_ output: String) -> [URL] {
        guard let start = output.range(of: startMarker),
              let end = output.range(of: endMarker, range: start.upperBound..<output.endIndex)
        else { return [] }
        return output[start.upperBound..<end.lowerBound]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }
    }
}
