import SwiftUI

@main
struct AgentCutApp: App {
    var body: some Scene {
        MenuBarExtra("agentCut", systemImage: "bolt.horizontal.circle") {
            Button("Esci") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
