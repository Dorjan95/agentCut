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
        try? await Task.sleep(for: .milliseconds(80))
        KeySynth.paste()
        try? await Task.sleep(for: .milliseconds(300))
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
