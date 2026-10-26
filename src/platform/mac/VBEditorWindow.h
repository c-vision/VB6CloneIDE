#ifndef VB_EDITOR_WINDOW_H
#define VB_EDITOR_WINDOW_H

#import <Cocoa/Cocoa.h>

#include "core/vb_model.h"

@interface VBEditorWindowController : NSWindowController

@property (nonatomic) VbProject *project;
@property (nonatomic) VbItem *currentItem;

- (instancetype)init;
- (BOOL)loadProjectAtPath:(NSString *)path;
- (void)newProject;
- (BOOL)saveProject;
- (BOOL)saveProjectAs;
- (void)addForm;
- (void)runProject;
- (void)stopProject;
- (void)showDesigner;
- (void)showCode;
- (void)showTabOrder:(id)sender;
- (BOOL)isRunning;
- (BOOL)hasProject;
- (NSString *)diagnostics;
- (BOOL)writeCodeEditorSnapshot:(NSString *)path;
- (BOOL)runDesignerSelectionSelfTest;
- (BOOL)runFormatSelfTest;
- (BOOL)runRuntimeTabSelfTest;
@property (nonatomic, readonly) NSWindow *runtimeTabTestWindow;
- (BOOL)runRuntimeAccessKeySelfTest;
@property (nonatomic, readonly) NSWindow *runtimeAccessKeyTestWindow;
- (BOOL)runRuntimeFocusSelfTest;
@property (nonatomic, readonly) NSWindow *runtimeFocusTestWindow;
- (BOOL)runRuntimeErrorSelfTest;
@property (nonatomic, readonly) NSWindow *runtimeErrorTestWindow;
/* Run > Break / F8 / F5 / Debug-from-error stepping; when snapshotPath is set, the IDE
   is captured while paused on the first statement. */
- (BOOL)runRuntimeBreakSelfTest:(NSString *)snapshotPath;
/* Gutter breakpoints: dot on executable lines, persistence in the .frm, stop at the
   line. With snapshotPath the IDE is captured while the dot is set. */
- (BOOL)runBreakpointSelfTest:(NSString *)snapshotPath;
/* Headless autocomplete: candidate engine (keyword, tipi, routine, identificatori). */
- (BOOL)runCompletionSelfTest;
/* Runs a handler that fails SetFocus with the real End/Debug dialog on screen (blocks
   in the modal loop; the caller captures the dialog and aborts the modal). */
- (void)showRuntimeErrorDialogForSnapshot;
- (void)runDebugHandler:(NSString *)handler;

@end

#endif
