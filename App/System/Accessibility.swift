import ApplicationServices
import Foundation

enum Accessibility {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Mostra il prompt di sistema che aggiunge agentCut alla lista Accessibilità.
    static func requestPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
