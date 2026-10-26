# agentCut — Design

Data: 2026-10-26
Stato: bozza, in attesa di approvazione

## 1. Intento e perché

Quando lavori ti capitano dubbi piccoli: una query SQL che non ricordi come si scrive, un testo da trasformare in JSON. Oggi per risolverli devi aprire ChatGPT o Claude, iniziare una nuova conversazione, incollare il testo, scrivere la richiesta e aspettare. Per una cosa da cinque secondi sono troppi passaggi.

agentCut è un'app per macOS che elimina questi passaggi. Selezioni (o copi) il testo, premi una scorciatoia oppure usi il tasto destro, e accanto al testo compare un fumetto con la soluzione già pronta. La puoi copiare oppure far incollare al posto del testo originale.

**Principio guida:** è uno strumento per cose lampo. Se una richiesta ha bisogno di botta e risposta, va fatta in una chat vera. agentCut non deve trasformarsi in una chat.

## 2. Obiettivi

- Dal testo selezionato alla soluzione con **un solo gesto** (scorciatoia o tasto destro), senza scrivere un prompt.
- L'agente **capisce da solo il problema** (errore di sintassi SQL, testo da formattare in JSON, ecc.) e propone direttamente la soluzione.
- Se non lo capisce, o se l'utente vuole altro, può **scrivere una domanda** su quel testo.
- Due azioni sulla risposta: **Copia** e **Sostituisci** (incolla al posto della selezione).
- Si appoggia alle **CLI già installate e autenticate con l'abbonamento**, cioè Claude Code (`claude`) e Codex (`codex`). Niente chiavi API e niente costi aggiuntivi.
- App **nativa e fatta bene per Mac**.

## 3. Non-obiettivi

- Cronologia delle conversazioni, thread, follow-up su più turni.
- Pannello che resta aperto mentre si lavora (opzione C dei mockup, scartata).
- Supporto ad agenti diversi da Claude Code e Codex nella prima versione. L'architettura però deve permettere di aggiungerne altri.
- Windows e Linux.
- Distribuzione su Mac App Store: la sandbox dello Store impedisce di lanciare CLI esterne e di usare l'Accessibilità come serve qui.

## 4. Anti-obiettivi (fallimento anche se tecnicamente funziona)

- Diventare una "chat in miniatura": finestre grandi, cronologia, conversazioni lunghe.
- Essere lenta o pesante da richiamare, al punto che aprire ChatGPT diventi più comodo.
- Rubare il focus o sporcare gli appunti dell'utente senza rimetterli a posto.
- Agire sui file o sul sistema: l'agente deve solo **rispondere con testo**, senza eseguire comandi né modificare file.

## 5. Esperienza utente (deciso con l'utente)

### 5.1 Attivazione
- **Scorciatoia globale da tastiera.** È il metodo principale e si può configurare.
- **Tasto destro → Servizi → "Chiedi ad agentCut".** macOS non permette a un'app di aggiungere voci al primo livello del menu contestuale di tutte le app, quindi il servizio è il massimo possibile. Questo vincolo è già stato spiegato all'utente.

### 5.2 Sorgente del testo
- Si usa il **testo selezionato**. Se non c'è selezione, si usano gli **appunti** (mia scelta: copre sia "seleziono" sia "copio").

### 5.3 Il fumetto (opzione A, scelta dall'utente)
Un pannello piccolo e fluttuante compare **sotto la selezione**, oppure vicino al cursore se non si riesce a sapere dove sia la selezione. Contiene:
- **Etichetta** con quello che l'agente ha riconosciuto, ad esempio "SQL · errore di sintassi" *(mia aggiunta)*.
- **La soluzione**, in un blocco monospaziato quando si tratta di codice o dati.
- **Una riga di spiegazione** delle modifiche, ad esempio "SELEC → SELECT · GROUP → GROUP BY" *(mia aggiunta)*.
- Pulsanti: **Sostituisci (⏎)**, che è l'azione primaria, **Copia (⌘C)** e **Chiedi altro…**.
- **Chiedi altro…** apre un campo di testo in cui l'utente scrive la domanda. La nuova richiesta contiene il testo originale più la domanda, e la risposta sostituisce quella precedente nel fumetto. Non c'è cronologia.
- Se l'agente non capisce l'intento, il fumetto mostra subito il campo domanda, già pronto per scrivere.
- **Risposta "da incollare" o "spiegazione"** *(mia scelta, dalla revisione)*: il formato della risposta indica se è testo sostitutivo o una spiegazione (es. dopo "cosa fa questa query?"). Nel secondo caso Sostituisci è nascosto e Copia diventa l'azione primaria (⏎), così ⏎ non incolla mai prosa dentro il codice.
- **Anteprima dell'input** *(mia scelta, dalla revisione)*: quando il testo arriva dagli appunti (nessuna selezione), il fumetto mostra in piccolo le prime righe di cosa è stato inviato, così è evidente se si è mandato qualcosa di inatteso. Nessuna conferma preventiva, per non rompere il gesto unico.
- **Esc** chiude il fumetto, che si chiude anche quando perde il focus.
- Durante l'attesa si vede uno stato di caricamento, e la risposta **compare man mano che viene scritta** (streaming), dove la CLI lo permette.

Riferimento visivo: `.superpowers/brainstorm/*/content/popup-layout.html`, card A.

### 5.4 Sostituisci
Incolla la soluzione al posto della selezione nell'app d'origine: si riporta il focus a quell'app, si mette la soluzione negli appunti, si simula ⌘V e poi si **ripristinano gli appunti precedenti**. Se il testo arrivava dagli appunti e non da una selezione, "Sostituisci" incolla nella posizione corrente del cursore.

### 5.5 App
- Vive nella **barra dei menu**, senza icona nel Dock.
- Dal menu: Impostazioni, Esci.
- Al primo avvio, onboarding guidato per il permesso di **Accessibilità**, necessario per leggere la selezione e simulare ⌘C e ⌘V.

## 6. Impostazioni (deciso con l'utente: "configurazioni base")

Richieste dall'utente:
- **Lingua** delle risposte.
- **System prompt** personale, aggiunto in testa a ogni richiesta.

Aggiunte da me (minime):
- **Agente predefinito:** Claude Code o Codex. Modello opzionale, se la CLI lo accetta.
- **Scorciatoia** globale.
- **Avvio al login.**
- **Percorso delle CLI**, rilevato da solo (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, la PATH della shell di login). Si modifica a mano solo se il rilevamento fallisce.

## 7. Come si costruisce (scelte mie, approvate in linea di principio: "fatto bene per Mac")

- **Swift + SwiftUI**, con AppKit dove serve: `NSPanel` non attivante per il fumetto, `NSStatusItem`, Services, eventi globali.
- Target: macOS 14+. Toolchain presente sulla macchina: Xcode 26.2, Swift 6.2.
- Distribuzione: per ora uso personale, app firmata localmente. In futuro un DMG notarizzato (fuori dallo Store, vedi §3).

### 7.1 Integrazione con le CLI (misurato sul Mac dell'utente, 2026-10-26)

| CLI | Comando base | Tempo totale | Primo token |
|---|---|---|---|
| Claude Code 2.1.306 | `claude -p … --model haiku` | ~6 s | ~4,5 s (stream-json) |
| Codex 0.163.0 | `codex exec --skip-git-repo-check --ephemeral -s read-only …` | ~8 s | — |

Note:
- `claude --bare` **non funziona con l'abbonamento** ("Not logged in"), quindi non si può usare.
- Disattivare MCP e strumenti (`--strict-mcp-config --tools "" --no-session-persistence`) non riduce i tempi in modo apprezzabile. Il costo è soprattutto l'avvio della CLI e la rete.
- Claude supporta lo streaming (`--output-format stream-json --include-partial-messages --verbose`), da usare per mostrare la risposta man mano.
- Per entrambe le CLI l'agente va **limitato a rispondere**: niente strumenti per Claude (`--tools ""`), sandbox in sola lettura ed `--ephemeral` per Codex. Per Codex non esiste un modo per spegnere del tutto gli strumenti: si accetta la sandbox `read-only` più l'istruzione nel prompt di non eseguire comandi, come garanzia sufficiente per la v1 *(mia scelta, dalla revisione)*. Il protocollo `AgentProvider` quindi non promette "zero strumenti", ma "nessuna scrittura". Si esegue in una directory di lavoro vuota e dedicata (es. `~/Library/Application Support/agentCut/work`) per non caricare `CLAUDE.md` o `AGENTS.md` di progetti.

**La latenza è il rischio principale del prodotto** (vedi anti-obiettivo sulla lentezza). **Obiettivo v1 (deciso con l'utente):** 5–6 secondi per la risposta completa sono accettabili, a patto che la risposta compaia man mano. Non serve una prova preliminare sulla velocità: si parte dall'app, e l'ottimizzazione viene dopo. Il builder deve:
1. usare lo streaming dove disponibile;
2. mostrare subito il fumetto con lo stato di caricamento, così il gesto dà un riscontro immediato;
3. valutare, con una misura, se tenere un processo `claude` "caldo" (modalità `--input-format stream-json` di lunga durata) riduce in modo significativo il tempo al primo token, e a quale prezzo (contesto che si accumula, gestione del riavvio). È un'ottimizzazione da verificare, non un requisito.

### 7.2 Prompt
Ogni richiesta è composta da:
1. un prompt di sistema fisso dell'app: "riconosci il tipo di testo e il problema, rispondi con la soluzione pronta da incollare, più etichetta e spiegazione breve, in formato strutturato";
2. il system prompt personale dell'utente;
3. la lingua scelta;
4. il testo selezionato (più l'eventuale domanda di "Chiedi altro…").

La risposta deve avere un formato che l'app sa leggere (ad esempio JSON con `label`, `solution`, `explanation`, `understood: bool`), in modo da separare la soluzione da incollare dal resto. Il formato esatto lo decide il builder, che deve anche tenere conto di streaming e risposte malformate (fallback: mostrare il testo grezzo).

### 7.3 Architettura (indicativa)
- `AgentProvider` (protocollo) con le implementazioni `ClaudeCodeProvider` e `CodexProvider`, per poter aggiungere altri agenti in seguito.
- `SelectionReader`: legge la selezione tramite Accessibility API, con fallback ⌘C simulato e appunti ripristinati.
- `Replacer`: incolla e ripristina gli appunti.
- `PopoverController`: posizionamento del pannello e stati (caricamento, risposta, domanda, errore).
- `Settings`, salvate in `UserDefaults`.

## 8. Errori da gestire
- CLI non trovata o non autenticata: messaggio nel fumetto con l'indicazione da seguire (es. "esegui `claude` nel terminale e fai login").
- Permesso di Accessibilità mancante: rimando alle Impostazioni di Sistema.
- Nessun testo selezionato e appunti vuoti: il fumetto mostra il campo domanda.
- Timeout (es. 60 s) e annullamento con Esc, che termina il processo figlio.

## 9. Lasciato al builder
- Formato strutturato preciso della risposta e prompt di sistema dell'app.
- Tecnica per posizionare il fumetto rispetto alla selezione (AX bounds, fallback al mouse).
- Libreria o API per la scorciatoia globale.
- Scelta del modello predefinito per velocità (ad esempio Haiku per Claude).
- Se e come tenere un processo caldo (§7.1, punto 3).
- Stile visivo del fumetto, nel rispetto delle convenzioni macOS (materiali, modalità chiara e scura).
