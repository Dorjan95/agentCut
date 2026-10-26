import AgentCutCore
import AppKit

@MainActor
enum Replacer {
    /// Incolla `text` al posto della selezione nell'app d'origine, poi ripristina gli appunti.
    static func replace(with text: String, in app: NSRunningApplication?) async {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        app?.activate()
        // Aspetta (max 500 ms) che l'app d'origine sia davvero in primo piano, poi un margine per il focus.
        if let app {
            for _ in 0..<50 where NSWorkspace.shared.frontmostApplication != app {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        try? await Task.sleep(for: .milliseconds(150))
        await KeySynth.waitForModifiersReleased()
        KeySynth.paste()
        // Le app lente leggono gli appunti in ritardo: ripristino dopo 500 ms.
        try? await Task.sleep(for: .milliseconds(500))
        snapshot.restore(to: pasteboard)
    }
}

@MainActor
enum Clipboard {
    /// "Copia" cambia davvero gli appunti: niente ripristino.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
