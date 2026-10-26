import Testing
@testable import AgentCutCore

struct PromptBuilderTests {
    @Test func systemPromptIncludesLanguageAndUserPrompt() {
        var s = AppSettings()
        s.language = "English"
        s.userSystemPrompt = "Usa MySQL"
        let r = PromptBuilder.build(input: "x", question: nil, agent: .claudeCode, settings: s)
        #expect(r.systemPrompt.contains("Lingua delle risposte: English."))
        #expect(r.systemPrompt.contains("Istruzioni dell'utente:\nUsa MySQL"))
        #expect(r.systemPrompt.hasPrefix("Sei agentCut"))
    }

    @Test func omitsUserSectionWhenEmpty() {
        let r = PromptBuilder.build(input: "x", question: nil, agent: .claudeCode, settings: AppSettings())
        #expect(!r.systemPrompt.contains("Istruzioni dell'utente"))
    }

    @Test func wrapsInputAndQuestion() {
        let r = PromptBuilder.build(input: "SELEC 1", question: "perché?", agent: .claudeCode, settings: AppSettings())
        #expect(r.userPrompt == "Testo selezionato:\n<<<\nSELEC 1\n>>>\n\nDomanda: perché?")
    }

    @Test func wrapsInputWithoutQuestion() {
        let r = PromptBuilder.build(input: "SELEC 1", question: nil, agent: .claudeCode, settings: AppSettings())
        #expect(r.userPrompt == "Testo selezionato:\n<<<\nSELEC 1\n>>>")
    }

    @Test func truncatesLongInput() {
        let r = PromptBuilder.build(input: String(repeating: "a", count: 25_000), question: nil, agent: .claudeCode, settings: AppSettings())
        #expect(r.userPrompt.contains(String(repeating: "a", count: 20_000)))
        #expect(!r.userPrompt.contains(String(repeating: "a", count: 20_001)))
        #expect(r.userPrompt.contains("testo troncato ai primi 20000 caratteri"))
    }

    @Test func modelComesFromAgent() {
        #expect(PromptBuilder.build(input: "x", question: nil, agent: .claudeCode, settings: AppSettings()).model == "haiku")
        #expect(PromptBuilder.build(input: "x", question: nil, agent: .codex, settings: AppSettings()).model == nil)
    }
}
