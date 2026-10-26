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
    /// Directory della PATH della shell di login dell'utente (timeout 2 s).
    public static func directories() async -> [URL] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let stream = ProcessRunner().lines(
            executable: URL(fileURLWithPath: shell),
            arguments: ["-l", "-c", "printf %s \"$PATH\""],
            stdin: "",
            workingDirectory: FileManager.default.temporaryDirectory,
            timeout: .seconds(2)
        )
        var output = ""
        do {
            for try await line in stream { output += line }
        } catch {
            return []
        }
        return output.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }
}
