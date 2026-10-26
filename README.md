# VB6CloneIDE

Clone nativo macOS dell'IDE di **Visual Basic 6.0**: form designer, finestra Properties,
toolbox, Project Explorer, editor codice, breakpoint, debug e runtime del form con chrome
Windows 98/VB6.

L'obiettivo non è "un IDE ispirato a VB6": è la **fedeltà visiva e comportamentale** a
Visual Basic 6.0 su Windows 98. Nessuna estetica macOS moderna nel chrome dell'IDE.

## Funzionalità

- Form designer con griglia, selezione, drag/resize, multi-selezione, align/size/spacing,
  z-order e Tab Order.
- Project Explorer, toolbox a icone, finestra Properties con combo oggetti.
- Autocomplete nell’editor con `Ctrl+Space`: keyword VB6, tipi, proprietà, routine,
  controlli e identificatori dichiarati (`Dim`, `Sub`, `Function`, `Type`, `Class`, `Const`).
- Debug: breakpoint nel gutter, Toggle Breakpoint `F9`, Clear All Breakpoints,
  Break, Step Into `F8`, Step Over `F10`, Continue `F5`, Stop `Shift+F5`.
- Editor codice VB6 con gutter, syntax highlighting, combo `(General)`/procedure e
  breakpoint nel gutter che seguono le modifiche del codice.
- Runtime del form con controlli classici, Tab/Shift+Tab secondo `TabIndex`, access key
  VB6, focus Win98, `MsgBox`/`InputBox` e dialoghi classici.
- Controlli Data e DataGrid con rendering classico e griglia editabile in memoria.
- Round-trip `.vbp`/`.frm` compatibile VB6.

## Architettura

```text
src/core/           motore portabile C99, nessuna dipendenza Cocoa
  vb_util, vb_model, vb_parse, vb_code, vb_grid
src/platform/mac/   shell Cocoa/Objective-C (ARC)
  VBAppDelegate, VBEditorWindow, VBMenuBarView, VBToolbarView,
  VBToolboxView, VBProjectOutlineView, VBPropertyPanel,
  VBDesignerView, VBCodeEditor, VBRuntimeWindow, VBTheme
src/tools/vbtool.c  CLI headless: ids, dump, roundtrip, verify, run, save, scan, grid, check
samples/HelloWorld  progetto .vbp/.frm di riferimento
```

Tutta la logica testabile vive in C99; Cocoa gestisce solo I/O e UI.

## Build

Requisiti: macOS, Xcode Command Line Tools, `make`.

```bash
make
```

Output:

- `build/vbtool`
- `build/VB6CloneIDE.app`

## Verifica

```bash
make check
```

Esegue l'harness headless `vbtool check` senza aprire finestre:

```text
check: round-trip PASS
check: interpreter PASS
check: breakpoints PASS
check: controls PASS
check: breakpoint edits PASS
check: runtime errors PASS
check: break mode PASS
check: tab order PASS
check: datagrid PASS
check: PASS
```

I flag `--selftest`, `--designer-test`, `--runtime-*-test` e gli `--*-snapshot` servono
per l'ispezione visiva manuale.

Verifica autocomplete headless:

```bash
./build/VB6CloneIDE.app/Contents/MacOS/VB6CloneIDE --completion-test
# completion: PASS
```

## Stato

Funzionante e verificato: parsing/round-trip, designer, properties, toolbox, Project
Explorer, salvataggio, esecuzione form, breakpoint, break mode, tab order, DataGrid,
dialoghi Win98.

Ancora incompleti: Menu Editor, Object Browser, Form Layout Window, undo/redo, Step Out,
call stack, watch/immediate, persistenza Data/DataGrid.

## Autonomia

Progetto autonomo: non dipende da altri progetti o runtime esterni.
