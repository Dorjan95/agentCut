import AgentCutCore
import AppKit
import ApplicationServices

struct Capture {
    var input: CapturedText
    /// Coordinate AppKit (origine in basso a sinistra), se l'app espone i bounds della selezione.
    var anchor: CGRect?
    var sourceApp: NSRunningApplication?
}

@MainActor
enum SelectionReader {
    static func capture() async -> Capture {
        let sourceApp = NSWorkspace.shared.frontmostApplication

        if let (text, anchor) = readViaAccessibility() {
            if !text.isEmpty {
                return Capture(input: .init(text: text, source: .selection), anchor: anchor, sourceApp: sourceApp)
            }
            // L'app espone la selezione ed è vuota: niente ⌘C sintetico, che in alcuni editor
            // copierebbe la riga corrente spacciandola per selezione. Si usano gli appunti.
        } else if let text = await readViaSyntheticCopy(), !text.isEmpty {
            return Capture(input: .init(text: text, source: .selection), anchor: nil, sourceApp: sourceApp)
        }
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        return Capture(input: .init(text: clipboard, source: .clipboard), anchor: nil, sourceApp: sourceApp)
    }

    private static func readViaAccessibility() -> (String, CGRect?)? {
        let system = AXUIElementCreateSystemWide()
        // Un'app bloccata non deve congelare agentCut per i 6 s del timeout AX predefinito.
        AXUIElementSetMessagingTimeout(system, 0.3)
        guard let focused: AXUIElement = attribute(system, kAXFocusedUIElementAttribute),
              let text: String = attribute(focused, kAXSelectedTextAttribute)
        else { return nil }
        return (text, selectionBounds(focused))
    }

    private static func selectionBounds(_ element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue
        else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        // AX usa l'origine in alto a sinistra dello schermo principale.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Fallback per le app che non espongono la selezione via AX (browser, Electron, terminali).
    private static func readViaSyntheticCopy() async -> String? {
        await KeySynth.waitForModifiersReleased()
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        let before = pasteboard.changeCount
        KeySynth.copy()

        // Browser ed Electron sotto carico possono metterci centinaia di ms.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(10))
            if pasteboard.changeCount != before {
                let copied = pasteboard.string(forType: .string)
                snapshot.restore(to: pasteboard)
                return copied
            }
        }
        // Copia arrivata in ritardo: ripristina comunque gli appunti dell'utente.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if pasteboard.changeCount == before + 1 {
                snapshot.restore(to: pasteboard)
            }
        }
        return nil
    }
}
