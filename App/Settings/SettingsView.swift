import AgentCutCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private let store = AppCoordinator.shared.settingsStore
    @State private var settings = AppCoordinator.shared.settingsStore.load()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var axTrusted = Accessibility.isTrusted

    private let languages = ["Italiano", "English", "Español", "Français", "Deutsch"]

    var body: some View {
        Form {
            Section("Agente") {
                Picker("Agente predefinito", selection: $settings.agent) {
                    ForEach(AgentKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("Modello Claude", text: $settings.claudeModel, prompt: Text("haiku"))
                TextField("Modello Codex", text: $settings.codexModel, prompt: Text("predefinito della CLI"))
            }

            Section {
                Picker("Lingua", selection: $settings.language) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("System prompt personale")
                    TextEditor(text: $settings.userSystemPrompt)
                        .font(.body)
                        .frame(minHeight: 80)
                }
            } header: {
                Text("Risposte")
            } footer: {
                Text("Aggiunto in testa a ogni richiesta.")
            }

            Section("Scorciatoia") {
                KeyboardShortcuts.Recorder("Chiedi ad agentCut", name: .askAgent)
            }

            Section("Generale") {
                Toggle("Avvia al login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("CLI") {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    cliRow(agent)
                }
            }

            Section("Permessi") {
                HStack {
                    Text("Accessibilità")
                    Spacer()
                    if axTrusted {
                        Label("Concesso", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("Non concesso").foregroundStyle(.red)
                    }
                }
                Button("Apri Impostazioni di Sistema") {
                    NSWorkspace.shared.open(Accessibility.settingsURL)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onChange(of: settings) { _, new in store.save(new) }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = Accessibility.isTrusted
        }
    }

    private func cliRow(_ agent: AgentKind) -> some View {
        let override = Binding(
            get: { settings.pathOverride(for: agent) },
            set: { value in
                switch agent {
                case .claudeCode: settings.claudePathOverride = value
                case .codex: settings.codexPathOverride = value
                }
            }
        )
        let found = AppCoordinator.shared.locator.locate(agent.executableName, override: override.wrappedValue)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(agent.displayName)
                Spacer()
                if let found {
                    Text(found.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                } else {
                    Text("Non trovata").foregroundStyle(.red)
                }
            }
            TextField("Percorso personalizzato", text: override, prompt: Text("rilevato automaticamente"))
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Impostazioni agentCut"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
