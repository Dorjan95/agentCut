import Foundation

public protocol LineRunning: Sendable {
    func lines(executable: URL, arguments: [String], stdin: String, workingDirectory: URL, timeout: Duration) -> AsyncThrowingStream<String, Error>
}

/// Lancia un processo e restituisce le righe di stdout man mano che arrivano.
/// Annullare lo stream termina il processo.
public struct ProcessRunner: LineRunning {
    private let extraPath: [URL]

    public init(extraPath: [URL] = []) {
        self.extraPath = extraPath
    }

    public func lines(executable: URL, arguments: [String], stdin: String, workingDirectory: URL, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            process.currentDirectoryURL = workingDirectory

            var environment = ProcessInfo.processInfo.environment
            if !extraPath.isEmpty {
                let current = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                environment["PATH"] = (extraPath.map(\.path) + [current]).joined(separator: ":")
            }
            process.environment = environment

            let stdoutPipe = Pipe(), stderrPipe = Pipe(), stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            let run = RunState(process: process)
            let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
            process.terminationHandler = { p in
                exitContinuation.yield(p.terminationStatus)
                exitContinuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: AgentError.processFailed(exitCode: -1, stderr: error.localizedDescription))
                return
            }

            let stdinHandle = stdinPipe.fileHandleForWriting
            let input = Data(stdin.utf8)
            DispatchQueue.global().async {
                try? stdinHandle.write(contentsOf: input)
                try? stdinHandle.close()
            }

            let stderrTask = Task.detached {
                stderrPipe.fileHandleForReading.readDataToEndOfFile()
            }

            let timeoutTask = Task.detached {
                try await Task.sleep(for: timeout)
                run.markTimedOut()
            }

            let readTask = Task.detached {
                do {
                    for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                        continuation.yield(line)
                    }
                } catch {
                    // EOF anomalo: l'esito lo decide il codice di uscita.
                }
                var status: Int32 = 0
                for await code in exitStream { status = code }
                timeoutTask.cancel()
                let stderrData = await stderrTask.value

                if run.timedOut {
                    continuation.finish(throwing: AgentError.timedOut)
                } else if run.cancelled {
                    continuation.finish()
                } else if status != 0 {
                    let stderr = String(decoding: stderrData, as: UTF8.self)
                    continuation.finish(throwing: AgentError.processFailed(exitCode: status, stderr: stderr))
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason {
                    run.cancel()
                    readTask.cancel()
                }
            }
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var _timedOut = false
    private var _cancelled = false

    init(process: Process) {
        self.process = process
    }

    var timedOut: Bool { lock.withLock { _timedOut } }
    var cancelled: Bool { lock.withLock { _cancelled } }

    func markTimedOut() {
        lock.withLock { _timedOut = true }
        terminate()
    }

    func cancel() {
        lock.withLock { _cancelled = true }
        terminate()
    }

    private func terminate() {
        if process.isRunning { process.terminate() }
    }
}
