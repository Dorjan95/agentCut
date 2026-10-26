import CoreGraphics

/// ⌘C / ⌘V sintetici verso l'app in primo piano.
enum KeySynth {
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    static func copy() { press(keyC) }
    static func paste() { press(keyV) }

    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
