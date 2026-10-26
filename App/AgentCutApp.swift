import os
import SwiftUI

@main
struct AgentCutApp: App {
    private let logger = Logger(subsystem: "com.dorjanrudaj.agentcut", category: "debug")

    var body: some Scene {
        MenuBarExtra("agentCut", systemImage: "bolt.horizontal.circle") {
            Button("Debug: leggi selezione") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    let capture = await SelectionReader.capture()
                    logger.notice("capture text=\(capture.input.text, privacy: .public) source=\(String(describing: capture.input.source), privacy: .public) anchor=\(String(describing: capture.anchor), privacy: .public) app=\(capture.sourceApp?.localizedName ?? "-", privacy: .public)")
                }
            }
            Button("Esci") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
