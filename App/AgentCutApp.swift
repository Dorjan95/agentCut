import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboarding = MainActor.assumeIsolated { OnboardingWindow() }
    private let settingsWindow = MainActor.assumeIsolated { SettingsWindow() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let coordinator = AppCoordinator.shared
            coordinator.onNeedsOnboarding = { [onboarding] in onboarding.show() }
            coordinator.onOpenSettings = { [settingsWindow] in settingsWindow.show() }
            coordinator.start()
            if !Accessibility.isTrusted {
                onboarding.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppCoordinator.shared.shutdown() }
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
            Button("Impostazioni…") { AppCoordinator.shared.onOpenSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Esci") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
