import Foundation

public enum PromptBuilder {
    public static let maxInputCharacters = 20_000

    static let appSystemPrompt = """
    Sei agentCut, un assistente lampo dentro macOS. L'utente ti passa un testo che ha selezionato (codice, query, dati, prosa) ed eventualmente una domanda.
    Se non c'è una domanda: capisci da solo di che testo si tratta e qual è il problema più probabile (errore di sintassi, formato da sistemare, refuso...) e restituisci il testo corretto, pronto da incollare al posto dell'originale.
    Se c'è una domanda: rispondi alla domanda. Se la risposta è un testo che sostituisce l'originale usa KIND: replace, altrimenti KIND: answer.
    Se non riesci a capire cosa serve usa KIND: unclear e nel corpo scrivi una breve domanda per l'utente.
    Non eseguire comandi, non leggere né modificare file: rispondi solo con testo.
    Rispondi SEMPRE e SOLO in questo formato, senza testo prima dell'intestazione:
    KIND: replace|answer|unclear
    LABEL: <etichetta brevissima, es. "SQL · errore di sintassi">
    NOTE: <una riga su cosa hai cambiato o perché>
    ---
    <corpo: solo il testo risultante, senza blocchi ``` e senza commenti>
    """

    public static func build(input: String, question: String?, agent: AgentKind, settings: AppSettings) -> AgentRequest {
        var system = appSystemPrompt + "\n\nLingua delle risposte: \(settings.language)."
        let userInstructions = settings.userSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userInstructions.isEmpty {
            system += "\n\nIstruzioni dell'utente:\n\(userInstructions)"
        }

        let truncated = input.count > maxInputCharacters
        let text = truncated ? String(input.prefix(maxInputCharacters)) : input
        var user = "Testo selezionato:\n<<<\n\(text)\n>>>"
        if truncated {
            user += "\n(Nota: testo troncato ai primi \(maxInputCharacters) caratteri.)"
        }
        if let question = question?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty {
            user += "\n\nDomanda: \(question)"
        }

        return AgentRequest(systemPrompt: system, userPrompt: user, model: settings.model(for: agent))
    }
}
