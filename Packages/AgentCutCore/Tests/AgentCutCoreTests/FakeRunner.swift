import Foundation
@testable import AgentCutCore

/// Runner finto: restituisce righe preimpostate e registra l'ultima invocazione.
final class FakeRunner: LineRunning, @unchecked Sendable {
    let lines: [String]
    let error: Error?
    private(set) var lastArguments: [String] = []
    private(set) var lastStdin = ""

    init(lines: [String], error: Error? = nil) {
        self.lines = lines
        self.error = error
    }

    func lines(executable: URL, arguments: [String], stdin: String, workingDirectory: URL, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        lastArguments = arguments
        lastStdin = stdin
        let lines = self.lines, error = self.error
        return AsyncThrowingStream { c in
            for line in lines { c.yield(line) }
            c.finish(throwing: error)
        }
    }
}

func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var out: [String] = []
    for try await chunk in stream { out.append(chunk) }
    return out
}

let fakeURL = URL(fileURLWithPath: "/fake/cli")
let fakeWorkDir = FileManager.default.temporaryDirectory
