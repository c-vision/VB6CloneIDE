# VB6CloneIDE

A native macOS clone of the **Visual Basic 6.0 IDE**: form designer, Properties window,
toolbox, Project Explorer, code editor, breakpoints, debugging, and form runtime with
Windows 98/VB6 chrome.

The goal is not "an IDE inspired by VB6": it is **visual and behavioral fidelity** to
Visual Basic 6.0 on Windows 98. No modern macOS styling in the IDE chrome.

## Features

- Form designer with grid, selection, drag/resize, multi-selection, align/size/spacing,
  z-order, and Tab Order.
- Project Explorer, icon toolbox, and Properties window with the object combo.
- Editor autocomplete with `Ctrl+Space`: VB6 keywords, types, properties, routines,
  controls, and declared identifiers (`Dim`, `Sub`, `Function`, `Type`, `Class`, `Const`).
- Debug: gutter breakpoints, Toggle Breakpoint `F9`, Clear All Breakpoints, Break,
  Step Into `F8`, Step Over `F10`, Continue `F5`, Stop `Shift+F5`.
- VB6 code editor with gutter, syntax highlighting, `(General)`/procedure combos, and
  breakpoints that follow code edits.
- Form runtime with classic controls, Tab/Shift+Tab by `TabIndex`, VB6 access keys,
  Win98 focus, `MsgBox`/`InputBox`, and classic dialogs.
- Data and DataGrid controls with classic rendering and an in-memory editable grid.
- VB6-compatible `.vbp`/`.frm` round-trip.

## Architecture

```text
src/core/           portable C99 engine, no Cocoa dependency
  vb_util, vb_model, vb_parse, vb_code, vb_grid
src/platform/mac/   Cocoa/Objective-C shell (ARC)
  VBAppDelegate, VBEditorWindow, VBMenuBarView, VBToolbarView,
  VBToolboxView, VBProjectOutlineView, VBPropertyPanel,
  VBDesignerView, VBCodeEditor, VBRuntimeWindow, VBTheme
src/tools/vbtool.c  headless CLI: ids, dump, roundtrip, verify, run, save, scan, grid, check
samples/HelloWorld  reference .vbp/.frm project
```

All testable logic lives in C99; Cocoa handles I/O and UI only.

## Build

Requirements: macOS, Xcode Command Line Tools, `make`.

```bash
make
```

Output:

- `build/vbtool`
- `build/VB6CloneIDE.app`

## Verification

```bash
make check
```

Runs the headless `vbtool check` harness without opening windows:

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

The `--selftest`, `--designer-test`, `--runtime-*-test`, and `--*-snapshot` flags are for
manual visual inspection.

Headless autocomplete verification:

```bash
./build/VB6CloneIDE.app/Contents/MacOS/VB6CloneIDE --completion-test
# completion: PASS
```

## Status

Working and verified: parsing/round-trip, designer, properties, toolbox, Project
Explorer, saving, form execution, breakpoints, break mode, tab order, DataGrid, and Win98
dialogs.

## Limitations

- **No native Windows executable**: the IDE runs forms with its internal interpreter and
  does not produce a distributable `.exe`.
- **Partial VB6 language coverage**: the interpreter covers the subset used by the samples
  and the headless check suite, not all VB6.
- **No persistent ADO/Jet data**: Data and DataGrid use an in-memory sheet that is lost
  when the runtime closes.
- **No Menu Editor**: project menus cannot be created or edited yet.
- **No Object Browser**: classes, members, and constants are not browsable.
- **No Form Layout Window**: the screen-position preview is missing.
- **Incomplete Undo/Redo**: designer operations are not fully undoable.
- **No Step Out**: the debugger cannot return to the caller frame.
- **No Call Stack**: frames and callers are not shown.
- **No Watch/Immediate Window**: expressions cannot be watched or evaluated while paused.
- **Partial `.vbp`/`.frm` compatibility**: layout round-trip works, but complex properties,
  blocks, and real-world project references are not fully covered.
- **Limited test coverage**: mostly HelloWorld and the `vbtool check` sections; no
  automated visual regression suite.

## Independence

Standalone project: it does not depend on external compilers, runtimes, or other
repositories.
