import Foundation

public protocol LineRunning: Sendable {
    func lines(executable: URL, arguments: [String], stdin: String, workingDirectory: URL, timeout: Duration) -> AsyncThrowingStream<String, Error>
}

public protocol ProcessLaunching: Sendable {
    /// Avvia il processo subito; stdin resta aperto finché non arriva la richiesta.
    func launch(executable: URL, arguments: [String], workingDirectory: URL) -> LaunchedProcessing
}

public protocol LaunchedProcessing: AnyObject, Sendable {
    var isAlive: Bool { get }
    /// Scrive stdin, lo chiude e restituisce le righe di stdout. Si può chiamare una sola volta.
    func send(_ stdin: String, timeout: Duration) -> AsyncThrowingStream<String, Error>
    /// Termina un processo che non servirà più.
    func discard()
    /// Chiamato una volta all'uscita del processo, subito se è già uscito.
    func onExit(_ handler: @escaping @Sendable () -> Void)
}

/// Lancia un processo e restituisce le righe di stdout man mano che arrivano.
/// Annullare lo stream termina il processo.
public struct ProcessRunner: LineRunning, ProcessLaunching {
    private let extraPath: [URL]

    public init(extraPath: [URL] = []) {
        self.extraPath = extraPath
    }

    public func lines(executable: URL, arguments: [String], stdin: String, workingDirectory: URL, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory).send(stdin, timeout: timeout)
    }

    public func launch(executable: URL, arguments: [String], workingDirectory: URL) -> LaunchedProcessing {
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
        // Le righe emesse prima della richiesta restano nel buffer dello stream.
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { p in
            exitContinuation.yield(p.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            continuation.finish(throwing: AgentError.processFailed(exitCode: -1, stderr: error.localizedDescription))
            run.markExited()
            return LaunchedProcess(run: run, stdin: nil, stream: stream, continuation: continuation)
        }

        let stdinHandle = stdinPipe.fileHandleForWriting
        // Se il figlio esce prima di leggere stdin, la write deve fallire con EPIPE invece di uccidere l'app.
        _ = fcntl(stdinHandle.fileDescriptor, F_SETNOSIGPIPE, 1)

        // stderr letto in modo non bloccante: un nipote che eredita la pipe non deve bloccare nulla.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                run.appendStderr(data)
            }
        }

        // Ogni pipe ha il suo handler: FileHandle.bytes usa una coda condivisa e un lettore bloccato fermerebbe gli altri.
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                for line in run.flushStdout() { continuation.yield(line) }
                run.markReadDone()
                return
            }
            let lines = run.appendStdout(data)
            if !lines.isEmpty { run.touch() }
            for line in lines { continuation.yield(line) }
        }

        // L'esito si decide all'uscita del processo; l'EOF di stdout si aspetta al massimo 500 ms.
        Task.detached {
            var status: Int32 = 0
            for await code in exitStream { status = code }
            run.markExited()
            for _ in 0..<50 where !run.readDone {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if !run.readDone {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                for line in run.flushStdout() { continuation.yield(line) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            if run.timedOut {
                continuation.finish(throwing: AgentError.timedOut)
            } else if run.cancelled {
                continuation.finish()
            } else if status != 0 {
                let stderr = String(decoding: run.stderr, as: UTF8.self)
                continuation.finish(throwing: AgentError.processFailed(exitCode: status, stderr: stderr))
            } else {
                continuation.finish()
            }
        }

        continuation.onTermination = { reason in
            if case .cancelled = reason {
                run.cancel()
            }
        }

        return LaunchedProcess(run: run, stdin: stdinHandle, stream: stream, continuation: continuation)
    }
}

private final class LaunchedProcess: LaunchedProcessing, @unchecked Sendable {
    private let run: RunState
    private let stdin: FileHandle?
    private let stream: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation

    init(run: RunState, stdin: FileHandle?, stream: AsyncThrowingStream<String, Error>, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.run = run
        self.stdin = stdin
        self.stream = stream
        self.continuation = continuation
    }

    var isAlive: Bool { run.isRunning }

    func send(_ input: String, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        guard let stdin else { return stream }
        // Il tempo passato in attesa non conta come inattività.
        run.touch()
        let data = Data(input.utf8)
        DispatchQueue.global().async {
            try? stdin.write(contentsOf: data)
            try? stdin.close()
        }

        // Timeout di inattività: si azzera a ogni riga ricevuta.
        let run = self.run, continuation = self.continuation
        let timeoutTask = Task.detached {
            while true {
                let idle = run.idleTime
                if idle >= timeout {
                    run.markTimedOut()
                    continuation.finish(throwing: AgentError.timedOut)
                    return
                }
                try await Task.sleep(for: timeout - idle)
            }
        }
        run.onExit { timeoutTask.cancel() }
        return stream
    }

    func onExit(_ handler: @escaping @Sendable () -> Void) {
        run.onExit(handler)
    }

    func discard() {
        run.cancel()
        try? stdin?.close()
        continuation.finish()
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var _timedOut = false
    private var _cancelled = false
    private var lastActivity = ContinuousClock.now
    private var _readDone = false
    private var _exited = false
    private var exitHandlers: [@Sendable () -> Void] = []
    private var stderrData = Data()
    private var stdoutBuffer = Data()

    init(process: Process) {
        self.process = process
    }

    var timedOut: Bool { lock.withLock { _timedOut } }
    var idleTime: Duration { lock.withLock { ContinuousClock.now - lastActivity } }

    var readDone: Bool { lock.withLock { _readDone } }
    var stderr: Data { lock.withLock { stderrData } }

    var isRunning: Bool { process.isRunning && !lock.withLock { _exited } }

    func markExited() {
        let handlers: [@Sendable () -> Void] = lock.withLock {
            _exited = true
            defer { exitHandlers = [] }
            return exitHandlers
        }
        handlers.forEach { $0() }
    }

    /// Chiamato all'uscita del processo, subito se è già uscito.
    func onExit(_ handler: @escaping @Sendable () -> Void) {
        let alreadyExited: Bool = lock.withLock {
            if !_exited { exitHandlers.append(handler) }
            return _exited
        }
        if alreadyExited { handler() }
    }

    func markReadDone() {
        lock.withLock { _readDone = true }
    }

    /// Aggiunge dati a stdout e restituisce le righe complete (separate solo da "\n").
    func appendStdout(_ data: Data) -> [String] {
        lock.withLock {
            stdoutBuffer.append(data)
            var lines: [String] = []
            while let newline = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                var lineData = stdoutBuffer[stdoutBuffer.startIndex..<newline]
                if lineData.last == UInt8(ascii: "\r") { lineData = lineData.dropLast() }
                lines.append(String(decoding: lineData, as: UTF8.self))
                stdoutBuffer = Data(stdoutBuffer[stdoutBuffer.index(after: newline)...])
            }
            return lines
        }
    }

    /// Restituisce l'ultima riga senza "\n" finale, se c'è.
    func flushStdout() -> [String] {
        lock.withLock {
            guard !stdoutBuffer.isEmpty else { return [] }
            let line = String(decoding: stdoutBuffer, as: UTF8.self)
            stdoutBuffer = Data()
            return [line]
        }
    }

    func appendStderr(_ data: Data) {
        lock.withLock { stderrData.append(data) }
    }

    func touch() {
        lock.withLock { lastActivity = .now }
    }
    var cancelled: Bool { lock.withLock { _cancelled } }

    func markTimedOut() {
        lock.withLock { _timedOut = true }
        terminate()
    }

    func cancel() {
        lock.withLock { _cancelled = true }
        terminate()
    }

    /// SIGTERM, poi SIGKILL dopo 2 s se il processo è ancora vivo.
    private func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
