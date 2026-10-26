#ifndef VB_CODE_EDITOR_H
#define VB_CODE_EDITOR_H

#import <Cocoa/Cocoa.h>

@class VBCodeEditor;

@protocol VBCodeEditorDelegate <NSObject>
- (void)codeEditorDidChange:(VBCodeEditor *)editor;
@optional
/* A gutter click added or removed a breakpoint (the owner persists it in the form). */
- (void)codeEditorDidChangeBreakpoints:(VBCodeEditor *)editor;
@end

@interface VBCodeEditor : NSView <NSTextViewDelegate>

@property (nonatomic, weak) id<VBCodeEditorDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *code;
/* VB6 breakpoints: 1-based lines of the code text. Setting the property replaces the
   whole set (used when another form is selected); gutter clicks edit it one line at a
   time and only executable statements can take a breakpoint. Editing the code moves the
   dots with their statements like VB6 (a line inserted above pushes them down) and a dot
   whose statement is deleted disappears. */
@property (nonatomic, copy) NSIndexSet *breakpointLines;
- (void)toggleBreakpointAtLine:(NSInteger)line;
/* Gutter click path, also used by the self test: point is in the editor's coordinates. */
- (BOOL)toggleBreakpointAtGutterPoint:(NSPoint)point;
- (NSPoint)gutterPointForLine:(NSInteger)line;
/* Character range of a 1-based line (newline included), or {NSNotFound, 0}. */
- (NSRange)rangeForLine:(NSInteger)line;
/* Replaces text the way typing does, so breakpoints follow the edit exactly as they do
   for the user. Used by the self test to prove inserted/removed lines move the dots. */
- (BOOL)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;

- (void)setCode:(NSString *)code;
/* Apre la lista di completamento sulla parola corrente (Ctrl+Space / menu Edit). */
- (void)completeWord;
/* Test headless: candidati filtrati per prefisso (case-insensitive). */
- (NSArray<NSString *> *)completionMatchesForPrefix:(NSString *)prefix;
- (void)focusEditor;
- (void)insertHandlerForControl:(NSString *)control event:(NSString *)event;
- (void)jumpToHandlerNamed:(NSString *)name;
- (void)jumpToLine:(NSInteger)line;
- (NSInteger)currentLineNumber;
/* Break mode: highlight the statement the interpreter is paused on (VB6 yellow bar
   plus the margin marker) and take it away when execution leaves break mode. */
- (void)showDebugLine:(NSInteger)line;
- (void)clearDebugLine;
@property (nonatomic, readonly) NSInteger debugLine;
- (BOOL)writeTextViewSnapshot:(NSString *)path;
- (BOOL)writeScrollViewSnapshot:(NSString *)path;

@end

#endif
