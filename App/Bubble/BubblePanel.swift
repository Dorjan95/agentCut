import AgentCutCore
import AppKit
import SwiftUI

/// Pannello fluttuante che non attiva agentCut: l'app d'origine resta in primo piano.
final class BubblePanel: NSPanel {
    private var topEdge: CGFloat = 0
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

    /// Posiziona il pannello mantenendo fisso il bordo superiore quando il contenuto cresce.
    func place(at frame: CGRect) {
        topEdge = frame.maxY
        setFrame(frame, display: true)
    }

    @objc private func didResize() {
        guard topEdge > 0 else { return }
        var origin = frame.origin
        origin.y = topEdge - frame.height
        if let visible = screen?.visibleFrame, origin.y < visible.minY {
            origin.y = visible.minY
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
