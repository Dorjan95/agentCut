import AgentCutCore
import AppKit
import SwiftUI

/// Pannello fluttuante che non attiva agentCut: l'app d'origine resta in primo piano.
final class BubblePanel: NSPanel {
    private var anchorY: CGFloat?
    private var fixedEdge = BubblePlacement.Edge.top
    var onDismiss: (() -> Void)?

    init(rootView: BubbleView) {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = .preferredContentSize
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)

        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentViewController = controller

        NotificationCenter.default.addObserver(self, selector: #selector(didResize), name: NSWindow.didResizeNotification, object: self)
    }

    override var canBecomeKey: Bool { true }

    /// Posiziona il pannello; quando il contenuto cresce resta fermo il bordo vicino alla selezione.
    func place(at frame: CGRect, fixedEdge: BubblePlacement.Edge) {
        self.fixedEdge = fixedEdge
        anchorY = fixedEdge == .top ? frame.maxY : frame.minY
        setFrame(frame, display: true)
    }

    @objc private func didResize() {
        guard let anchorY else { return }
        var origin = frame.origin
        origin.y = fixedEdge == .top ? anchorY - frame.height : anchorY
        if let visible = screen?.visibleFrame {
            origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        }
        if origin != frame.origin { setFrameOrigin(origin) }
    }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}
