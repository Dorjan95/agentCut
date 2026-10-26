import AppKit
import SwiftUI

@MainActor
final class OnboardingWindow {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "agentCut"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(onClose: { [weak self] in self?.close() }))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}

private struct OnboardingView: View {
    var onClose: () -> Void
    @State private var trusted = Accessibility.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Benvenuto in agentCut").font(.title2.bold())
            if trusted {
                Text("Fatto! Premi ⌃⌥Space su un testo selezionato.")
                Button("Chiudi", action: onClose).keyboardShortcut(.defaultAction)
            } else {
                Text("Per leggere il testo selezionato e incollare le risposte, agentCut ha bisogno del permesso Accessibilità.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Apri Impostazioni di Sistema") {
                    Accessibility.requestPrompt()
                    NSWorkspace.shared.open(Accessibility.settingsURL)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = Accessibility.isTrusted
        }
    }
}
