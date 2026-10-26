import CoreGraphics

/// ⌘C / ⌘V sintetici verso l'app in primo piano.
enum KeySynth {
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    static func copy() { press(keyC) }
    static func paste() { press(keyV) }

    /// Aspetta (max 300 ms) che l'utente rilasci ⌃⌥⇧⌘ della scorciatoia, così l'app non riceve ⌃⌥⌘C.
    static func waitForModifiersReleased() async {
        let held: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<30 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func press(_ key: CGKeyCode) {
        // Stato privato: i modificatori fisici ancora premuti non si sommano al ⌘ sintetico.
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
