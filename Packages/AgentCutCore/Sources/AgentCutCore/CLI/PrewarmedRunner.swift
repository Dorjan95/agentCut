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
    private let maxIdleRecycles: Int
    private let minLifetime: Duration
    private let lock = NSLock()
    private var key: Key?
    private var warm: LaunchedProcessing?
    private var warmSince = ContinuousClock.now
    private var launching = false
    private var inFlight = 0
    private var idleRecycles = 0
    private var recycleTask: Task<Void, Never>?

    /// `maxAge`: un processo fermo da più tempo viene sostituito, nel caso il sonno o un token scaduto l'abbiano reso inutilizzabile.
    /// `maxIdleRecycles`: dopo tante sostituzioni senza richieste si smette, e la prossima richiesta parte da zero.
    /// `minLifetime`: un processo morto prima di questo tempo non viene rimpiazzato da solo, probabilmente la CLI fallisce all'avvio.
    public init(launcher: ProcessLaunching, maxAge: Duration = .seconds(30 * 60), maxIdleRecycles: Int = 4, minLifetime: Duration = .seconds(5)) {
        self.launcher = launcher
        self.maxAge = maxAge
        self.maxIdleRecycles = maxIdleRecycles
        self.minLifetime = minLifetime
    }

    deinit {
        recycleTask?.cancel()
        warm?.discard()
    }

    /// Tiene pronto un processo per questo comando, sostituendo quello di un comando precedente.
    /// L'avvio avviene in background e, se c'è una richiesta in corso, solo quando finisce.
    public func prepare(executable: URL, arguments: [String], workingDirectory: URL) {
        let newKey = Key(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        let stale: LaunchedProcessing? = lock.withLock {
            if key == newKey, warm?.isAlive == true { return nil }
            key = newKey
            idleRecycles = 0
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
        let (taken, dead): (LaunchedProcessing?, LaunchedProcessing?) = lock.withLock {
            inFlight += 1
            guard requestKey == key else { return (nil, nil) }
            idleRecycles = 0
            defer { warm = nil }
            guard let warm, warm.isAlive else { return (nil, warm) }
            return (warm, nil)
        }
        dead?.discard()
        let process = taken ?? launcher.launch(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        let lines = process.send(stdin, timeout: timeout)

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
                guard let self else { return }
                self.lock.withLock { self.inFlight -= 1 }
                self.refill()
            }
        }
    }

    /// Avvia in background un processo per il comando preparato, se non ce n'è già uno pronto né una richiesta in corso.
    private func refill() {
        let target: Key? = lock.withLock {
            guard let key, warm == nil, !launching, inFlight == 0 else { return nil }
            launching = true
            return key
        }
        guard let target else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.launchWarm(target)
        }
    }

    private func launchWarm(_ target: Key) {
        let process = launcher.launch(executable: target.executable, arguments: target.arguments, workingDirectory: target.workingDirectory)
        let installed: Bool = lock.withLock {
            launching = false
            guard key == target, warm == nil else { return false }
            warm = process
            warmSince = .now
            scheduleRecycle(for: process)
            return true
        }
        guard installed else {
            // Il comando è cambiato durante l'avvio: si riparte con quello nuovo.
            process.discard()
            refill()
            return
        }
        process.onExit { [weak self, weak process] in
            guard let self, let process else { return }
            self.warmExited(process)
        }
    }

    /// Il processo pronto è uscito da solo: lo si rimpiazza, a meno che sia morto subito dopo l'avvio.
    private func warmExited(_ process: LaunchedProcessing) {
        let replace: Bool = lock.withLock {
            guard let warm, warm === process else { return false }
            self.warm = nil
            recycleTask?.cancel()
            recycleTask = nil
            return ContinuousClock.now - warmSince >= minLifetime
        }
        if replace { refill() }
    }

    /// Da chiamare con il lock preso.
    private func scheduleRecycle(for process: LaunchedProcessing) {
        recycleTask?.cancel()
        let maxAge = self.maxAge
        recycleTask = Task { [weak self] in
            try? await Task.sleep(for: maxAge)
            guard !Task.isCancelled, let self else { return }
            let (old, again): (LaunchedProcessing?, Bool) = self.lock.withLock {
                guard let warm = self.warm, warm === process else { return (nil, false) }
                self.warm = nil
                self.idleRecycles += 1
                return (warm, self.idleRecycles < self.maxIdleRecycles)
            }
            guard let old else { return }
            old.discard()
            if again { self.refill() }
        }
    }
}
