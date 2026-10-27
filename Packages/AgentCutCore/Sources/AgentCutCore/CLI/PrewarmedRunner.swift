import Foundation

/// Tiene pronto un processo già avviato per il comando preparato con `prepare`, così la richiesta
/// non paga l'avvio della CLI. Ogni processo serve una sola richiesta: niente contesto che si accumula.
/// Le richieste con un comando diverso partono da zero come con `ProcessRunner`.
public final class PrewarmedRunner: LineRunning, @unchecked Sendable {
    private struct Key: Equatable {
        var executable: URL
        var arguments: [String]
        var workingDirectory: URL
    }

    private let launcher: ProcessLaunching
    private let maxAge: Duration
    private let lock = NSLock()
    private var key: Key?
    private var warm: LaunchedProcessing?
    private var recycleTask: Task<Void, Never>?

    /// `maxAge`: un processo fermo da più tempo viene sostituito, nel caso il sonno o un token scaduto l'abbiano reso inutilizzabile.
    public init(launcher: ProcessLaunching, maxAge: Duration = .seconds(30 * 60)) {
        self.launcher = launcher
        self.maxAge = maxAge
    }

    deinit {
        recycleTask?.cancel()
        warm?.discard()
    }

    /// Tiene pronto un processo per questo comando, sostituendo quello di un comando precedente.
    public func prepare(executable: URL, arguments: [String], workingDirectory: URL) {
        let newKey = Key(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        let stale: LaunchedProcessing? = lock.withLock {
            if key == newKey, warm?.isAlive == true { return nil }
            key = newKey
            defer { warm = nil }
            return warm
        }
        stale?.discard()
        refill()
    }

    /// Termina il processo pronto e smette di prepararne altri.
    public func stop() {
        let old: LaunchedProcessing? = lock.withLock {
            key = nil
            recycleTask?.cancel()
            recycleTask = nil
            defer { warm = nil }
            return warm
        }
        old?.discard()
    }

    public func lines(executable: URL, arguments: [String], stdin: String, workingDirectory: URL, timeout: Duration) -> AsyncThrowingStream<String, Error> {
        let requestKey = Key(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        let (taken, dead, matches): (LaunchedProcessing?, LaunchedProcessing?, Bool) = lock.withLock {
            guard requestKey == key else { return (nil, nil, false) }
            defer { warm = nil }
            guard let warm, warm.isAlive else { return (nil, warm, true) }
            return (warm, nil, true)
        }
        dead?.discard()
        let process = taken ?? launcher.launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        let lines = process.send(stdin, timeout: timeout)
        guard matches else { return lines }

        // Il rimpiazzo parte a risposta finita, per non rubare CPU alla richiesta in corso.
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                self?.refill()
            }
        }
    }

    /// Avvia un processo per il comando preparato, se non ce n'è già uno pronto.
    private func refill() {
        lock.withLock {
            guard let key, warm == nil else { return }
            let process = launcher.launch(executable: key.executable, arguments: key.arguments, workingDirectory: key.workingDirectory)
            warm = process
            scheduleRecycle(for: process)
        }
    }

    /// Da chiamare con il lock preso.
    private func scheduleRecycle(for process: LaunchedProcessing) {
        recycleTask?.cancel()
        let maxAge = self.maxAge
        recycleTask = Task { [weak self] in
            try? await Task.sleep(for: maxAge)
            guard !Task.isCancelled, let self else { return }
            let old: LaunchedProcessing? = self.lock.withLock {
                guard let warm = self.warm, warm === process else { return nil }
                self.warm = nil
                return warm
            }
            guard let old else { return }
            old.discard()
            self.refill()
        }
    }
}
