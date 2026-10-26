import AgentCutCore
import AppKit

/// Voce "Chiedi ad agentCut" nel menu Servizi (tasto destro sul testo selezionato).
final class ServiceProvider: NSObject {
    @objc func askAgent(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pboard.string(forType: .string) ?? ""
        MainActor.assumeIsolated {
            let capture = Capture(
                input: CapturedText(text: text, source: .selection),
                anchor: nil,
                sourceApp: NSWorkspace.shared.frontmostApplication
            )
            AppCoordinator.shared.trigger(with: capture)
        }
    }
}
