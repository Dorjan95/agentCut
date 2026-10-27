# agentCut

App per la barra dei menu di macOS: selezioni un testo (una query, un JSON, una frase), premi una scorciatoia e accanto al testo compare la soluzione già pronta, da incollare al posto dell'originale o da copiare. Usa le CLI di Claude Code e Codex con il tuo abbonamento, senza chiavi API.

## Requisiti

- macOS 14 o successivo
- `claude` (Claude Code) e/o `codex` installati e con login già fatto (lancia `claude` o `codex login` nel Terminale)
- Xcode 26 e [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) per compilare

## Compilare e installare

```bash
bash scripts/build.sh
```

Lo script genera il progetto Xcode, compila, installa in `/Applications/agentCut.app`, aggiorna il menu Servizi e avvia l'app.

Test della logica:

```bash
swift test --package-path Packages/AgentCutCore
```

Test con le CLI vere (circa 10 secondi):

```bash
AGENTCUT_INTEGRATION=1 swift test --package-path Packages/AgentCutCore --filter ProviderIntegrationTests
```

## Primo avvio

agentCut chiede il permesso **Accessibilità** (Impostazioni di Sistema → Privacy e sicurezza → Accessibilità). Serve per leggere il testo selezionato e per incollare la risposta con "Sostituisci".

## Uso

- **⌃⌥Space** (Ctrl+Option+Spazio) su un testo selezionato apre il fumetto. Se non c'è selezione, usa il testo negli appunti e ne mostra un'anteprima.
- **⏎** esegue l'azione principale: *Sostituisci* quando la risposta è un testo corretto, *Copia* quando è una spiegazione. **⌘⇧C** copia sempre tutta la risposta, mentre ⌘C copia solo la parte che hai selezionato nel fumetto.
- **Chiedi altro…** permette di scrivere una domanda su quel testo.
- **Esc** chiude il fumetto e interrompe la richiesta.
- **Tasto destro → Servizi → Chiedi ad agentCut** fa la stessa cosa dal menu contestuale. Se la voce non c'è, abilitala in Impostazioni di Sistema → Tastiera → Scorciatoie da tastiera → Servizi → Testo.

Dalla barra dei menu → **Impostazioni…** puoi scegliere l'agente predefinito e il modello, la lingua delle risposte, un system prompt personale, la scorciatoia, l'avvio al login e il percorso delle CLI.

## Limiti noti

- Tempo di risposta: con Claude circa 1–2 s, perché agentCut tiene un processo `claude` già avviato in background (circa 250 MB di memoria) e ne usa uno nuovo per ogni richiesta. Il primo uso dopo aver cambiato agente, modello o prompt può richiedere qualche secondo in più. Codex impiega circa 8 s e mostra la risposta tutta alla fine.
- Codex gira con sandbox in sola lettura: non può modificare nulla, ma la CLI non permette di disattivare del tutto i suoi strumenti.
- Se l'app in primo piano dice di non avere testo selezionato, agentCut usa gli appunti senza provare ⌘C: il fumetto lo segnala con "Dagli appunti: …".
- Le CLI vengono lanciate senza le tue impostazioni personali di Claude Code (`--setting-sources ""`): niente hook né plugin, così è più veloce.
- La voce nel menu Servizi può richiedere un logout/login la prima volta prima di comparire.
