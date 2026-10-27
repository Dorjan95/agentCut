import AgentCutCore
import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let settingsStore = SettingsStore()
    private(set) var locator = CLILocator(searchDirectories: CLILocator.defaultDirectories(home: FileManager.default.homeDirectoryForCurrentUser))
    private var extraPath: [URL] = []
    private var panel: BubblePanel?
    private var model: BubbleViewModel?
    private var isCapturing = false
    private var pathResolution: Task<Void, Never>?
    /// Tiene pronto un processo Claude, così la richiesta non paga l'avvio della CLI.
    private var runner: PrewarmedRunner?

    var onOpenSettings: () -> Void = {}
    var onNeedsOnboarding: () -> Void = {}

    func start() {
        KeyboardShortcuts.onKeyUp(for: .askAgent) { [weak self] in
            Task { await self?.trigger() }
        }
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()

        pathResolution = Task {
            let shellDirs = await LoginShellPath.directories()
            let home = FileManager.default.homeDirectoryForCurrentUser
            extraPath = CLILocator.defaultDirectories(home: home) + shellDirs
            locator = CLILocator(searchDirectories: extraPath)
            runner = PrewarmedRunner(launcher: ProcessRunner(extraPath: extraPath))
            prewarm()
        }
    }

    /// Prepara un processo per le impostazioni attuali; se sono cambiate sostituisce quello vecchio.
    /// Si chiama all'avvio e alla chiusura delle impostazioni.
    func prewarm() {
        guard let runner else { return }
        if let target = AgentEnvironment.prewarmTarget(settings: settingsStore.load(), locator: locator) {
            runner.prepare(executable: target.executable, arguments: target.arguments, workingDirectory: AgentEnvironment.workingDirectory)
        } else {
            runner.stop()
        }
    }

    func shutdown() {
        closeBubble()
        runner?.stop()
    }

    /// Aspetta la PATH della shell (max ~3 s, solo subito dopo l'avvio) prima di lanciare una CLI.
    func waitUntilReady() async {
        await pathResolution?.value
    }

    /// Scorciatoia: se il fumetto è aperto lo chiude, altrimenti legge la selezione e lo apre.
    func trigger() async {
        if panel != nil {
            closeBubble()
            return
        }
        guard !isCapturing else { return }
        guard Accessibility.isTrusted else {
            onNeedsOnboarding()
            return
        }
        // Una seconda pressione durante la lettura farebbe un secondo snapshot sporco degli appunti.
        isCapturing = true
        let capture = await SelectionReader.capture()
        await waitUntilReady()
        isCapturing = false
        trigger(with: capture)
    }

    func trigger(with capture: Capture) {
        closeBubble()
        let settings = settingsStore.load()
        // Niente prewarm qui: le impostazioni si applicano alla chiusura della finestra, e una richiesta
        // con un comando diverso parte comunque da zero senza avviare un secondo processo in parallelo.
        let provider = AgentEnvironment.makeProvider(settings: settings, locator: locator, runner: runner ?? ProcessRunner(extraPath: extraPath))
        let model = BubbleViewModel(input: capture.input, settings: settings, provider: provider)

        let view = BubbleView(
            model: model,
            onReplace: { [weak self] text in
                self?.closeBubble()
                guard Accessibility.isTrusted else {
                    // Senza Accessibilità non si può incollare: copia e spiega come abilitarla.
                    Clipboard.copy(text)
                    self?.onNeedsOnboarding()
                    return
                }
                Task { await Replacer.replace(with: text, in: capture.sourceApp) }
            },
            onCopy: { [weak self] text in
                Clipboard.copy(text)
                self?.closeBubble()
            },
            onClose: { [weak self] in self?.closeBubble() },
            onOpenSettings: { [weak self] in
                self?.closeBubble()
                self?.onOpenSettings()
            }
        )
        let panel = BubblePanel(rootView: view)
        panel.onDismiss = { [weak self] in self?.closeBubble() }

        let mouse = NSEvent.mouseLocation
        let point = capture.anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? mouse
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let size = panel.contentViewController?.view.fittingSize ?? CGSize(width: 360, height: 80)
        let frame = BubblePlacement.frame(size: size, anchor: capture.anchor, mouse: mouse, visibleFrame: screen?.visibleFrame ?? .zero)
        panel.place(at: frame, fixedEdge: BubblePlacement.fixedEdge(frame: frame, anchor: capture.anchor, mouse: mouse))
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.model = model
        model.start()
    }

    func closeBubble() {
        guard let panel else { return }
        self.panel = nil
        model?.cancel()
        model = nil
        panel.onDismiss = nil
        panel.orderOut(nil)
    }
}
