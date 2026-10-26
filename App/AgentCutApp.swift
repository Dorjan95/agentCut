import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppCoordinator.shared.start()
        }
    }
}

@main
struct AgentCutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("agentCut", systemImage: "bolt.horizontal.circle") {
            Button("Chiedi ad agentCut") {
                Task { await AppCoordinator.shared.trigger() }
            }
            Divider()
            Button("Esci") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
