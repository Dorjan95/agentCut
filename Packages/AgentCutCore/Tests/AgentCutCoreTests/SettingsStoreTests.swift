import Foundation
import Testing
@testable import AgentCutCore

struct SettingsStoreTests {
    let defaults = UserDefaults(suiteName: "agentcut.test.\(UUID())")!

    @Test func defaultsWhenEmpty() {
        let s = SettingsStore(defaults: defaults).load()
        #expect(s == AppSettings())
        #expect(s.agent == .claudeCode)
        #expect(s.claudeModel == "haiku")
        #expect(s.language == "Italiano")
    }

    @Test func roundTrip() {
        let store = SettingsStore(defaults: defaults)
        var s = AppSettings()
        s.agent = .codex
        s.userSystemPrompt = "Usa MySQL"
        s.codexPathOverride = "/x/codex"
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func corruptDataFallsBackToDefaults() {
        defaults.set(Data("x".utf8), forKey: "agentcut.settings")
        #expect(SettingsStore(defaults: defaults).load() == AppSettings())
    }

    @Test func emptyModelIsNil() {
        #expect(AppSettings().model(for: .codex) == nil)
        #expect(AppSettings().model(for: .claudeCode) == "haiku")
    }
}
