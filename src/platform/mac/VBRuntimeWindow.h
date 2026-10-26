#ifndef VB_RUNTIME_WINDOW_H
#define VB_RUNTIME_WINDOW_H

#import <Cocoa/Cocoa.h>

#include "core/vb_model.h"

@class VBRuntimeWindow;

/* Break mode actions, from the dialog Debug button and the VB6 keys: F8/F10 step,
   F5 continues, Shift+F5 stops (as Run > End does). */
typedef NS_ENUM(NSInteger, VBRuntimeBreakAction) {
    VBRuntimeBreakStep = 0,
    VBRuntimeBreakContinue = 1,
    VBRuntimeBreakStop = 2
};

@protocol VBRuntimeWindowDelegate <NSObject>
- (void)runtimeWindowDidClose:(VBRuntimeWindow *)window;
@optional
/* The user pressed Debug in the End/Debug run-time error dialog, with break mode
   unavailable (tests, automation): the code window shows the failing statement. */
- (void)runtimeWindow:(VBRuntimeWindow *)window didRequestDebugForHandler:(NSString *)handler
                 line:(NSInteger)line;
/* Break mode: execution is paused on the statement at handler/line, which the code
   window must highlight. Sent for every pause, so stepping moves the highlight. */
- (void)runtimeWindow:(VBRuntimeWindow *)window didBreakAtHandler:(NSString *)handler
                 line:(NSInteger)line;
/* Execution left break mode: it continues or the program stopped. */
- (void)runtimeWindowDidLeaveBreakMode:(VBRuntimeWindow *)window;
@end

@interface VBRuntimeWindow : NSWindowController <NSWindowDelegate>

@property (nonatomic, weak) id<VBRuntimeWindowDelegate> delegate;
/* Automation/test mode: no modal dialogs. MsgBox/InputBox print to stderr; the
   run-time error dialog returns suppressedErrorResult (1 = End, 2 = Debug). */
@property (nonatomic) BOOL suppressDialogs;
@property (nonatomic) NSInteger suppressedErrorResult;

@property (nonatomic, readonly) VbForm *form;
/* Last unhandled run-time error (VB6 numbering, handler and absolute code line). */
@property (nonatomic, readonly) NSInteger runtimeErrorCount;
@property (nonatomic, readonly) NSInteger lastRuntimeErrorNumber;
@property (nonatomic, readonly, copy) NSString *lastRuntimeErrorMessage;
@property (nonatomic, readonly, copy) NSString *lastRuntimeErrorHandler;
@property (nonatomic, readonly) NSInteger lastRuntimeErrorLine;

/* Break mode: the statement the interpreter is paused on (absolute code line).
   breakCount counts every pause, so a test can tell stepping apart from a plain run. */
@property (nonatomic, readonly, getter=isInBreakMode) BOOL inBreakMode;
@property (nonatomic, readonly, copy) NSString *breakHandler;
@property (nonatomic, readonly) NSInteger breakLine;
@property (nonatomic, readonly) NSInteger breakCount;
/* Breakpoints (1-based lines of the form's code): the interpreter pauses on them as if
   Break had been pressed there. */
@property (nonatomic, copy) NSIndexSet *breakpointLines;
/* Deterministic automation: replaces the interactive event loop at every pause and
   returns the action to take. The run stays synchronous, so the block can inspect the
   form mid-statement. */
@property (nonatomic, copy) VBRuntimeBreakAction (^breakAction)(VBRuntimeWindow *window,
                                                                NSString *handler,
                                                                NSInteger line);

- (instancetype)initWithForm:(VbForm *)form;
- (void)startRuntime;
- (void)runEventHandler:(NSString *)handler;

/* Run > Break: pause before the next statement (the next event's first statement when
   the program is idle), then drive it with the methods below (the same actions the
   F5/F8 keys produce while paused). */
- (void)requestBreak;
- (void)breakContinue;
- (void)breakStep;
- (void)breakStop;
/* Key map used while paused: F8/F10 step, F5 continues, Shift+F5 stops; -1 for keys
   that break mode does not handle. */
+ (NSInteger)breakActionForKeyCode:(unsigned short)keyCode shift:(BOOL)shift;

/* Tab navigation by TabIndex (VB6), also used by the runtime tab-order self test. */
- (NSArray<NSString *> *)tabOrderControlNames;
- (NSString *)focusedControlName;
- (BOOL)focusNextControlBackwards:(BOOL)backwards;
- (BOOL)sendTabKeyBackwards:(BOOL)backwards;
/* <Control>.SetFocus: YES when the control took the focus (fires LostFocus/GotFocus). */
- (BOOL)setFocusToControl:(NSString *)control;

/* Runtime property bridge (used by handlers and by the tab-order self test). */
- (void)setProperty:(NSString *)property forControl:(NSString *)control value:(NSString *)value;
- (NSString *)propertyValueForControl:(NSString *)control property:(NSString *)property;

/* VB6 access keys: a caption "&File" makes Alt+F activate the control. displayCaption:
   strips the marker ("&&" is a literal ampersand) and reports the underlined index. */
+ (NSString *)displayCaption:(NSString *)caption mnemonicIndex:(NSInteger *)index;
/* Sends a real key event to the first responder, as the access-key self test does.
   dispatchTestKeyEvent: goes through NSApplication (AppKit's own dispatch). */
- (void)sendTestKeyEvent:(NSString *)characters optionDown:(BOOL)optionDown;
- (void)dispatchTestKeyEvent:(NSString *)characters optionDown:(BOOL)optionDown;

@end

#endif
