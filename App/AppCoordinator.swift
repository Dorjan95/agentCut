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

    var onOpenSettings: () -> Void = {}
    var onNeedsOnboarding: () -> Void = {}

    func start() {
        KeyboardShortcuts.onKeyUp(for: .askAgent) { [weak self] in
            Task { await self?.trigger() }
        }
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()

        Task {
            let shellDirs = await LoginShellPath.directories()
            let home = FileManager.default.homeDirectoryForCurrentUser
            extraPath = CLILocator.defaultDirectories(home: home) + shellDirs
            locator = CLILocator(searchDirectories: extraPath)
        }
    }

    /// Scorciatoia: se il fumetto è aperto lo chiude, altrimenti legge la selezione e lo apre.
    func trigger() async {
        if panel != nil {
            closeBubble()
            return
        }
        guard Accessibility.isTrusted else {
            onNeedsOnboarding()
            return
        }
        trigger(with: await SelectionReader.capture())
    }

    func trigger(with capture: Capture) {
        closeBubble()
        let settings = settingsStore.load()
        let provider = AgentEnvironment.makeProvider(settings: settings, locator: locator, runner: ProcessRunner(extraPath: extraPath))
        let model = BubbleViewModel(input: capture.input, settings: settings, provider: provider)

        let view = BubbleView(
            model: model,
            onReplace: { [weak self] text in
                self?.closeBubble()
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
        panel.place(at: frame)
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
