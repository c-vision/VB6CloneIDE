# TODO — VB6CloneIDE

Backlog completo per completare il clone di Visual Basic 6.0 IDE.
Legenda: `P0` blocca la fedeltà/uso quotidiano · `P1` necessario per un clone credibile ·
`P2` completamento e rifinitura. `[x]` = fatto e verificato con build/snapshot.

Regola generale: un item è "fatto" solo se `make` è verde senza nuovi warning,
`make check` passa, e la UI è stata verificata con snapshot della finestra
(`--window-snapshot`) e, quando serve, con `rea capture-native-ui-scenario`.

---

## M0 — Shell IDE in stile VB6 (fedeltà visiva)

- [x] **P0** Tema classico Windows 98/VB6 in `VBTheme` (grigi di sistema, testi neri,
      titoli blu `#000080`, font Tahoma 11 / Courier New 12).
- [x] **P0** Helper di disegno 3D: bevel raised/pressed/sunken, etched, title bar con
      close/min/max, bottoni classici, checkbox/radio, icone toolbar.
- [x] **P0** Menu bar VB6 dentro la finestra (File, Edit, View, Project, Format, Debug,
      Run, Query, Diagram, Tools, Add-Ins, Window, Help) con popup funzionanti.
- [x] **P0** Toolbar classica con bottoni 24×24, separatori, icone disegnate, stati
      abilitato/disabilitato, hover e pressione.
- [x] **P0** Workspace MDI grigio `#808080` con finestre child (Designer, Code) proprî
      caption blu, bordo client incassato.
- [x] **P0** Toolbox a 2 colonne, solo icone, tooltip col nome del controllo, selezione
      con bevel premuto.
- [x] **P0** Project Explorer custom: caption "Project - <nome>", box +/−, linee dotted,
      icone form/modulo, tag FRM/BAS/CLS, selezione blu.
- [x] **P0** Properties: caption "Properties - <oggetto>", combo oggetti classica,
      tabella a griglia con nomi su faccia grigia e valori editabili bianchi.
- [x] **P0** Designer: caption del form blu con close box, griglia a punti 60 twip,
      selezione tratteggiata e handle neri, nessuna ombra/gradiente moderna.
- [x] **P0** Status bar a pannelli incassati (messaggio, modalità DESIGN/RUNNING,
      coordinate/dimensioni).
- [x] **P0** Titolo finestra in formato VB6:
      `<Progetto> - Microsoft Visual Basic [design|code|run] - [<Form> (Form)]`.
- [x] **P0** Code window con le due combo VB6 in alto: `(General)` / `(Declarations)`
      e elenco procedure ricavato da `vb_code_handlers`, con salto alla routine.
- [x] **P0** Runtime window in stile VB6: `BorderStyle` rispettato (borderless/fixed/sizable),
      controlli disegnati con bevel e font classici (label, textbox con caret, button,
      check/radio, combo, list, scrollbar), niente widget Aqua.
- [x] **P0** Controlli Data e DataGrid: tool nel toolbox con icone VB6, proprietà
      dedicate (Data: Connect/DatabaseName/RecordSource/RecordsetType/BOFAction/
      EOFAction/ReadOnly/Exclusive/Options; DataGrid: DataSource/ColumnHeaders/
      DefColWidth/RowHeight/Allow*), disegno classico in designer e runtime
      (navigatore record, griglia con intestazioni), round-trip `.frm` verificato da
      `--designer-test`.
- [x] **P2** DataGrid editabile a runtime: griglia in memoria (`VbGrid` in
      `src/core/vb_grid.c`, nessuna dipendenza Cocoa) con celle selezionabili, editing
      con F2/Invio o digitando, Esc/Invio, backspace e Canc, frecce e Tab/Shift+Tab
      (Ctrl+Tab esce), ridimensionamento delle colonne trascinando il bordo
      dell'intestazione. Coperto da `vbtool grid` (dentro `make check`, nessuna finestra).
- [ ] **P2** Data control e DataGrid con dati persistenti: recordset caricato da un file
      o da un servizio (niente ADO/Jet su macOS) alimentato da `RecordSource`, navigazione
      first/previous/next/last e binding dei campi; oggi il foglio è in memoria e si
      svuota alla chiusura della finestra.
- [x] **P0** `MsgBox` in stile Win98: finestra grigia con icona, testo e bottone classico.
- [x] **P0** `InputBox` e dialoghi con più bottoni/icone (Yes/No/Cancel, Critical, Question)
      in stile Win98, non `NSAlert` Aqua.
- [ ] **P1** Menu: separatori, scorciatoie visualizzate a destra, submenu (Align,
      Make Same Size, Order), checkmark per voci toggle, stati disabilitati corretti.
- [ ] **P1** Icone toolbar/toolbox rifinite a 16×16/24×24 con palette VB6 (sfumature
      assenti, nero + grigio + blu), niente glifi generici.
- [ ] **P1** Pixel snapping: tutte le linee a 1px netto su display 1x e 2x; verificare
      che i bevel non siano sfocati.
- [ ] **P1** Fallback font: se Tahoma manca usare Verdana/Geneva senza cambiare le
      metriche dei pannelli.
- [ ] **P1** Form Layout Window (anteprima posizione form sullo schermo) e
      Object Browser (elenco classi/membri del progetto).
- [ ] **P1** Menu Editor funzionante: crea/modifica `VB.Menu`, caption, nome,
      checked/enabled/visible, separatori, livelli di annidamento.
- [ ] **P2** Barra dei menu con acceleratori Windows-style evidenziati (File, Edit, ...).
- [ ] **P2** Localizzazione italiana dei menu e dei messaggi (opzionale, toggle).

---

## M1 — Form designer (editing completo)

- [ ] **P0** 8 handle di ridimensionamento (angoli + lati) con cursore corretto e
      ridimensionamento simmetrico.
- [ ] **P0** Creazione controllo: click sullo strumento + drag sul form; doppio click
      sullo strumento crea il controllo con dimensioni di default.
- [ ] **P0** Spostamento con snap alla griglia del form e `Alt` per muovere di 1 twip;
      frecce = 15 twip, Shift+frecce = 1 twip.
- [ ] **P0** Cancellazione con Delete, `Esc` annulla lo strumento attivo.
- [ ] **P0** Contenitori (`Frame`, `PictureBox`) con clipping dei figli e coordinate
      relative corrette durante drag/resize.
- [ ] **P0** Modifica proprietà che cambiano il canvas: `ClientWidth`, `ClientHeight`,
      `Caption`, `BorderStyle`, `BackColor` con refresh immediato.
- [x] **P1** Multi-selezione: Shift+click, rettangolo di selezione (anche additivo con
      Shift), handle comuni, spostamento e ridimensionamento proporzionale di gruppo,
      cancellazione multipla. Verificata da `--designer-test`.
- [ ] **P1** Vincoli di gruppo: bloccare il resize multiplo su controlli con parent
      diversi (oggi il drag ricade su marquee) con feedback visivo.
- [x] **P1** Allineamento e spaziatura: Align Left/Center/Right/Top/Middle/Bottom,
      Make Same Width/Height/Size, Horizontal/Vertical Spacing (Make Equal/Increase/
      Decrease/Remove), Center in Form. Riferimento per Make Same Size = controllo
      attivo; richiede parent condiviso. Coperto da `--designer-test`.
- [x] **P1** Z-order: Bring to Front / Send to Back dal sottomenu Format > Order,
      anche su selezione multipla (l'ordine interno del gruppo è preservato). L'ordine
      di disegno è l'ordine dei blocchi `Begin` nel `.frm`: round-trip e ricarica verificati
      da `--designer-test`, e il runtime costruisce i controlli nello stesso ordine.
- [x] **P1** Tab order: dialog `View > Tab Order...` in stile VB6 (lista, frecce Su/Giù,
      OK/Cancel) che elenca i controlli per `TabIndex` e lo rinumera 0..n-1; editare
      `TabIndex` dalle Properties scambia con il controllo che occupava l'indice; i
      nuovi controlli ricevono il prossimo indice libero. Coperto da `--designer-test`.
      Anche il runtime naviga con Tab/Shift+Tab secondo `TabIndex`, con focus
      rettangolare tratteggiato stile Win98 e attivazione Space per pulsanti/check.
      L'ordine è ricalcolato a ogni Tab e rispetta `Visible`/`Enabled`/`TabStop`
      cambiati durante l'esecuzione, inclusi i controlli dentro Frame annidati.
      `Enabled = False` su Frame/PictureBox disabilita davvero i figli (niente Tab, click
      o focus; caption e campi in grigio Win98) senza toccare il loro flag `Enabled`, che
      torna attivo quando il contenitore viene riabilitato. Coperto da `--runtime-tab-test`.
      Limite residuo: il focus che esce da un controllo rimosso viene ripiegato sul
      successivo dell'ordine ricostruito e non conserva memoria dell'ultimo visitato.
- [ ] **P1** Copy / Cut / Paste / Duplicate controlli, con offset e nomi unici.
- [ ] **P1** Undo/Redo per tutte le operazioni del designer (spostamento, resize,
      creazione, cancellazione, proprietà), con stack e scorciatoie ⌘Z/⇧⌘Z.
- [ ] **P1** Blocco controlli (`Locked`) e selezione con click destro → menu contestuale.
- [x] **P1** Toolbar Format (seconda riga, stile Form Editor VB6) con align/size/spacing;
      bottoni e voci del menu Format abilitati solo con selezione valida (icone
      disabilitate sbiadite come su Win9x).
- [ ] **P2** Griglia configurabile (mostra/nascondi, passo), guide di allineamento.
- [ ] **P2** Anteprima form a runtime dal designer (toggle "Start").
- [ ] **P2** Supporto controllo `VB.Menu` visibile solo nel Menu Editor, non sul form.

---

## M2 — Code editor

- [ ] **P0** Combo `(General)` e combo procedure nella code window (vedi M0).
- [ ] **P0** Inserimento stub handler per tutti gli eventi del controllo selezionato
      (Click, DblClick, Change, KeyPress, GotFocus, LostFocus, MouseDown/Up/Move,
      Load/Unload/Activate per il form, Timer per il timer).
- [ ] **P0** Evidenziazione sintassi VB6: keyword blu, commenti verdi, stringhe nere;
      nessun colore moderno.
- [ ] **P0** Preservare encoding e fine riga (CRLF) al salvataggio; nessuna perdita di
      righe vuote finali.
- [ ] **P1** Auto-indent dopo `If`, `For`, `Do`, `Select Case`, `Sub`, `Function`,
      `With`; dedent su `End ...`, `Else`, `Loop`, `Next`.
- [ ] **P1** Tab/Shift+Tab per indentare blocchi.
- [ ] **P1** Find & Replace (⌘F), Find Next, Go to Line (⌘L).
- [ ] **P1** Undo/redo nativo affidabile anche dopo il re-highlighting.
- [ ] **P1** Rilevamento handler correnti e sincronizzazione con il combo procedure.
- [ ] **P2** IntelliSense minimale: completamento keyword, nomi controlli e handler.
- [ ] **P2** Bookmark e lista attività (`TODO`).
- [ ] **P2** Numeri di riga opzionali e stampa.

---

## M3 — Runtime e interprete VB6

- [ ] **P0** Statement: `If/ElseIf/Else/End If`, `Select Case`, `For/Next`, `For Each`,
      `Do/Loop`, `While/Wend`, `With/End With`, `Exit`, `GoTo` con label.
- [ ] **P0** Dichiarazioni: `Dim`, `ReDim`, `Static`, `Const`, array monodimensionali,
      `Option Explicit`, `Sub`/`Function` con parametri `ByVal`/`ByRef`.
- [ ] **P0** Tipi e conversioni: Integer, Long, Single, Double, String, Boolean, Date,
      Variant, `CInt`, `CLng`, `CSng`, `CDbl`, `CStr`, `CBool`.
- [ ] **P0** Operatori e precedenza, concatenazione `&`, confronti, `And/Or/Not`,
      `Mod`, `Like`.
- [ ] **P0** Funzioni built-in: stringhe (`Left`, `Right`, `Mid`, `Len`, `Trim`,
      `UCase`, `LCase`, `InStr`, `Replace`, `Split`, `Join`), matematica (`Abs`, `Int`,
      `Rnd`, `Sqr`), data (`Now`, `Date`, `Time`, `Format`), `MsgBox`, `InputBox`.
- [ ] **P0** Controlli a runtime: proprietà get/set, `AddItem`, `Clear`,
      `Print`, `Visible`, `Enabled`, `Text`, `Caption`, `Value`.
- [x] **P1** Errori runtime: un `SetFocus` non valido solleva l'errore 5 di VB6 con
      dialog modale Win98 (icona errore, `Run-time error '5':` + messaggio) e bottoni
      `End`/`Debug`: `End` chiude la form, `Debug` entra in break mode sulla riga
      colpita (barra gialla + freccia nel gutter), così l'handler si può proseguire con
      F8/F5 invece di fermarsi all'errore. Senza break mode (CLI, test) resta il vecchio
      comportamento di stop. L'interprete riporta handler e riga assoluta. Coperto da
      `--runtime-error-test`, `--runtime-error-snapshot` e `--runtime-break-test`.
- [x] **P1** Focus runtime: `<Control>.SetFocus` (anche `Call ...`) e eventi
      `GotFocus`/`LostFocus` su ogni cambio di focus (mouse, Tab, access key,
      `SetFocus`), con `Form_Load` eseguito prima del primo `GotFocus`. `SetFocus` su
      un controllo disabilitato, nascosto o non focalizzabile è un no-op con diagnostica;
      `TabStop = False` non lo impedisce (esclude solo dal ciclo Tab). Coperto da
      `--runtime-focus-test`. Limite: durante `GotFocus` il primo responder della
      finestra non è ancora aggiornato.
- [x] **P1** Access key runtime (`&` nella caption): Alt+lettera attiva il controllo
      (pulsante → `Click`, CheckBox/OptionButton → toggle + `Click`), la lettera è
      sottolineata come su Win98 e `&&` mostra un `&` letterale. La Label sposta il focus
      al controllo successivo dell'ordine di tabulazione, `UseMnemonic = False` disattiva
      la mnemonica e i controlli disabilitati/nascosti (o dentro Frame disabilitati) non
      rispondono. Coperto da `--runtime-access-key-test`.
- [ ] **P0** Eventi: `Form_Load`, `Form_Unload`, `Click`, `DblClick`, `Change`,
      `KeyPress`, `GotFocus`, `LostFocus`, `MouseDown/Up/Move`, `Timer`.
- [ ] **P0** Rendering runtime identico al designer per tutti i controlli supportati.
- [ ] **P1** Control array (`Index`), `Load`/`Unload` di controlli.
- [x] **P1** Gestione errori VB6: `On Error Resume Next`, `On Error GoTo <label>`,
      `On Error GoTo 0`, `Resume` / `Resume Next` / `Resume <label>` ed `Err`
      (`Number`, `Description`, `Source`, `Clear`, `Raise`). Il dialog classico
      `End`/`Debug` compare **solo** per gli errori non gestiti (o sollevati dentro un
      handler già attivo). Ambito procedurale, quindi `Resume Next` funziona anche
      dentro `If`. Coperto senza finestra dalla sezione `runtime errors` di `vbtool check`.
      Limite: un `Resume` che torna
      su un'istruzione che fallisce di nuovo è fermato da una guardia dopo 10000 giri
      (VB6 andrebbe in loop), e `On Error GoTo -1` non è riconosciuto.
- [ ] **P1** `GoTo`/`GoSub` generici con label e `Select Case`: solo i salti degli
      handler di errore sono interpretati.
- [ ] **P1** Collezioni, `Type` definiti dall'utente, `Enum`.
- [ ] **P1** File I/O: `Open/Close`, `Print #`, `Input #`, `Line Input #`, `EOF`.
- [ ] **P1** Timer con intervallo reale, stop pulito alla chiusura, `DoEvents`.
- [ ] **P1** Chiusura form con `Unload Me`, `End`, e stop da toolbar coerente.
- [ ] **P2** Chiamate API dichiarate (`Declare`) con stub/errore esplicito, non crash.
- [ ] **P2** `App`, `Screen`, `Clipboard` minimali.

---

## M4 — Sistema progetto

- [ ] **P0** Aggiungi/Rimuovi form, modulo, classe, UserControl con creazione file e
      aggiornamento `.vbp`.
- [ ] **P0** Dirty tracking per progetto, form e moduli; prompt di salvataggio alla
      chiusura e al cambio progetto.
- [ ] **P0** `.vbp` round-trip fedele: ordine voci, `Module=`, `Class=`,
      `UserControl=`, `Startup=`, `Name=`, riferimenti.
- [ ] **P0** Gestione file mancanti: messaggio chiaro, voce disabilitata, nessun crash.
- [ ] **P1** Proprietà progetto: nome, startup object, titolo, icona, versione.
- [ ] **P1** Riferimenti/Componenti: dialog di sola metadati, persistenza nel `.vbp`.
- [ ] **P1** Più finestre MDI aperte (form e code) con attivazione e chiusura.
- [ ] **P1** Progetti recenti e riapertura all'avvio.
- [ ] **P2** Drag&drop di `.vbp`/`.frm` sulla finestra e sul Dock.

---

## M5 — Debug

- [ ] **P1** Toolbar Start/Break/End con stati coerenti e scorciatoie F5 / Shift+F5.
      (Break/End e lo stato BREAK ci sono; la toolbar non riflette ancora i tre stati.)
- [x] **P1** Break in esecuzione: `Debug > Break` / toolbar Break chiedono la pausa e
      l'interprete si ferma prima dell'istruzione successiva; il gioco di eventi annidato
      tiene viva l'IDE e la status bar dice `BREAK`. `Shift+F5` interrompe, chiudere la
      form durante la pausa termina la procedura. Coperto da `--runtime-break-test`
      (anche il percorso interattivo con F8/F5 reali).
- [x] **P1** Step Into (F8) e Step Over (F10) a livello di istruzione, con evidenziazione
      della riga corrente (barra gialla VB6 + freccia nel gutter) e nessuna pausa su
      `Dim`, `End If`, `Else` o label. Coperto da `--runtime-break-test`.
- [ ] **P1** Step Out (F11), call stack e variabili locali: l'interprete non ha uno stack
      di chiamate, quindi non si può ancora risalire al chiamante.
- [ ] **P1** I cambi di focus (`GotFocus`/`LostFocus` da `SetFocus`) non sono ancora
      steppabili: girano atomici dentro l'istruzione che li provoca.
- [ ] **P2** Watch window e Immediate window (`? espressione`).
- [x] **P2** Breakpoint nel gutter: clic sulla colonna → pallino rosso (solo su
      istruzioni eseguibili, altrimenti beep), persistenza nel `.frm` come commento
      `'@VB6CloneBreakpoints: ...` (VB6 lo ignora, round-trip byte-identico) e stop
      dell'interprete sulla riga colpita. Coperto da `--breakpoint-test`. I pallini
      seguono le modifiche del codice: ogni edit è confrontato con il testo precedente
      (diff prefisso/suffisso, regione allargata a righe intere), quindi linee inserite o
      rimosse sopra un breakpoint lo spostano con la sua istruzione, Invio a inizio riga
      lo fa scendere e cancellare l'istruzione lo elimina (come VB6). Resta legato al
      form aperto nel code editor: i moduli `.bas` non hanno breakpoint.
- [x] **P2** Dialog di errore runtime con "Debug" per aprire la riga colpevole.

---

## M6 — Test, qualità, documentazione

- [x] **P0** Harness headless `vbtool check` (dentro `make check`): round-trip del
      sample, esecuzione di un handler con host C, marker dei breakpoint e
      save/load/save byte-identico, mappatura dei breakpoint su insert/delete di righe,
      default di Data/DataGrid, suite del DataGrid. Linka solo il core C: nessuna
      finestra. Restano da coprire: util, valutatore espressioni e gli statement
      principali oltre a quelli del sample.
- [ ] **P0** Portare nell'harness CLI gli ultimi self-test ancora dentro l'app
      (`--designer-test`, `--runtime-*-test`): finché vivono nel Cocoa richiedono una
      finestra e non fanno parte di `make check`.
- [ ] **P0** Fixture progetti: `ControlsGallery`, `Events`, `Loops`, `MultiForm`,
      `MenuDemo`; ognuno con verify + run atteso.
- [ ] **P0** `vbtool lint` per validare `.frm`/`.vbp` e segnalare proprietà mancanti.
- [ ] **P1** Regressione visiva: `rea capture-native-ui-scenario` + confronto PNG
      con soglia, su Designer, Code, Runtime.
- [ ] **P1** Check accessibilità: menu bar, toolbox, explorer, properties raggiungibili
      dall'AX tree con ruoli e nomi corretti.
- [ ] **P1** Performance: form con 200 controlli < 16 ms per frame; digitazione senza
      lag > 50 ms; nessuna fuga di memoria nel ciclo apri/chiudi progetto.
- [ ] **P1** README con screenshot, istruzioni build, limiti noti, roadmap.
- [ ] **P2** Documentazione architettura in `docs/` e aggiornamento continuo di
      `AGENTS.md`.

---

## M7 — Packaging

- [ ] **P1** Icona app in stile VB6 e `Info.plist` con document types `.vbp`/`.frm`.
- [ ] **P1** Build universale arm64 + x86_64 (`-arch arm64 -arch x86_64`).
- [ ] **P2** Firma e notarizzazione (solo quando richiesto dall'utente).
- [ ] **P2** Log degli errori su file in `~/Library/Logs/VB6CloneIDE/`.

---

## Definizione di "fatto" per ogni item UI

1. `make` senza nuovi warning.
2. `make check` verde.
3. Snapshot della finestra allegato nella verifica, con controllo di colori e metriche.
4. Nessun elemento Aqua/arrotondato/gradiente nel chrome.
5. Aggiornati `AGENTS.md` (stato) e questo `TODO.md` (checkbox).
