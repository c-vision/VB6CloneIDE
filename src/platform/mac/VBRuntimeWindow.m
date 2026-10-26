#import "VBRuntimeWindow.h"
#import "VBTheme.h"

#include "core/vb_code.h"
#include "core/vb_grid.h"
#include "core/vb_util.h"

#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

static NSString *DisplayProp(VbControl *control, const char *key)
{
    char *value;
    NSString *text;
    if (!control) return @"";
    value = vb_control_get_display(control, key);
    if (!value) return @"";
    text = [NSString stringWithUTF8String:value];
    free(value);
    return text ?: @"";
}

/* Design-time Enabled: VB6 writes -1/0 but also accepts True/False. */
static BOOL ControlEnabledAtLoad(VbControl *control)
{
    const char *value = control ? vb_control_get(control, "Enabled") : NULL;
    if (!value || !*value) return YES;
    if (vb_streq_ci(value, "False")) return NO;
    if (vb_streq_ci(value, "True")) return YES;
    return vb_parse_int(value, -1) != 0;
}

/* Repaint a container and everything inside it (disabled children change their colours). */
static void InvalidateSubtree(NSView *view)
{
    [view setNeedsDisplay:YES];
    for (NSView *child in view.subviews) InvalidateSubtree(child);
}

/* VB6 boolean property values arrive as -1/0 or True/False. */
static BOOL RuntimeBoolValue(NSString *value)
{
    if (!value.length) return NO;
    if ([value isEqualToString:@"0"] || [value caseInsensitiveCompare:@"False"] == NSOrderedSame) {
        return NO;
    }
    return YES;
}

static NSColor *RuntimeColor(VbControl *control, const char *key, NSColor *fallback)
{
    const char *value = vb_control_get(control, key);
    int r, g, b;
    if (!value || !vb_color_from_value(value, &r, &g, &b)) return fallback;
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

static NSFont *RuntimeFont(VbControl *control)
{
    int size = vb_control_get_int(control, "Font.Size", 0);
    NSString *name = DisplayProp(control, "Font.Name");
    NSFont *font;
    if (size <= 0) size = 9;
    CGFloat pointSize = size + 2.0;
    if ([name isEqualToString:@"MS Sans Serif"] || [name isEqualToString:@"MS Sans Serif "]) {
        font = VBFontUI();
    } else if (name.length) {
        font = [NSFont fontWithName:name size:pointSize];
    }
    if (!font) font = pointSize >= 12 ? [NSFont systemFontOfSize:pointSize] : VBFontUI();
    if (vb_control_get_int(control, "Font.Bold", 0)) {
        font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
    }
    if (vb_control_get_int(control, "Font.Italic", 0)) {
        font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask];
    }
    return font ?: VBFontUI();
}

static NSTextAlignment RuntimeAlignment(VbControl *control)
{
    int alignment = vb_control_get_int(control, "Alignment", 0);
    if (alignment == 1) return NSTextAlignmentRight;
    if (alignment == 2) return NSTextAlignmentCenter;
    return NSTextAlignmentLeft;
}

static void DrawClassicText(NSString *text, NSRect rect, NSFont *font, NSColor *color,
                            NSTextAlignment alignment)
{
    if (!text) return;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attrs = @{
        NSFontAttributeName: font ?: VBFontUI(),
        NSForegroundColorAttributeName: color ?: VBColorText(),
        NSParagraphStyleAttributeName: style
    };
    [text drawInRect:rect withAttributes:attrs];
}

/* VB6 access keys: a single "&" before a character underlines it and makes Alt+char
   activate the control; "&&" displays one literal ampersand. */
static NSString *VBCaptionParts(NSString *caption, NSInteger *mnemonicIndex, unichar *mnemonic)
{
    NSMutableString *display;
    if (mnemonicIndex) *mnemonicIndex = -1;
    if (mnemonic) *mnemonic = 0;
    if (!caption.length) return caption ?: @"";
    if ([caption rangeOfString:@"&"].location == NSNotFound) return caption;
    display = [NSMutableString stringWithCapacity:caption.length];
    for (NSUInteger i = 0; i < caption.length; i++) {
        unichar c = [caption characterAtIndex:i];
        if (c != '&') {
            [display appendString:[NSString stringWithCharacters:&c length:1]];
            continue;
        }
        if (i + 1 < caption.length && [caption characterAtIndex:i + 1] == '&') {
            [display appendString:@"&"];
            i++;
            continue;
        }
        if (i + 1 >= caption.length) continue; // a trailing "&" is not displayed
        {
            unichar key = [caption characterAtIndex:++i];
            if (mnemonicIndex && *mnemonicIndex < 0) {
                *mnemonicIndex = (NSInteger)display.length;
                if (mnemonic) *mnemonic = key;
            }
            [display appendString:[NSString stringWithCharacters:&key length:1]];
        }
    }
    return display;
}

/* Caption drawing with the Win98 access-key underline, centred or aligned like the text. */
static void DrawClassicCaption(NSString *caption, NSRect rect, NSFont *font, NSColor *color,
                               NSTextAlignment alignment, BOOL useMnemonic)
{
    NSInteger index = -1;
    NSString *display = useMnemonic ? VBCaptionParts(caption, &index, NULL)
                                    : (caption ?: @"");
    NSMutableParagraphStyle *style;
    NSMutableAttributedString *text;
    if (index < 0) {
        DrawClassicText(display, rect, font, color, alignment);
        return;
    }
    style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    text = [[NSMutableAttributedString alloc] initWithString:display attributes:@{
        NSFontAttributeName: font ?: VBFontUI(),
        NSForegroundColorAttributeName: color ?: VBColorText(),
        NSParagraphStyleAttributeName: style
    }];
    [text addAttribute:NSUnderlineStyleAttributeName
                 value:@(NSUnderlineStyleSingle)
                 range:NSMakeRange((NSUInteger)index, 1)];
    [text drawInRect:rect];
}

@class VBRuntimeWindow;
@class VBClassicControlView;

@protocol VBClassicControlHost <NSObject>
- (void)classicControl:(VBClassicControlView *)view fireEvent:(NSString *)event;
- (void)classicControl:(VBClassicControlView *)view requestsTabBackwards:(BOOL)backwards;
/* Alt+letter (an access key): YES when a control claimed the event. */
- (BOOL)activateAccessKeyForEvent:(NSEvent *)event;
/* GotFocus / LostFocus. Focus can change from inside a handler (SetFocus), so these
   are dispatched with a bounded nesting instead of being dropped as re-entrant. */
- (void)classicControl:(VBClassicControlView *)view fireFocusEvent:(NSString *)event;
@end

#pragma mark - Win98 dialogs

#define VB_DIALOG_WIDTH 400.0

@interface VBClassicDialogView : NSView <NSWindowDelegate, NSTextFieldDelegate>
@property (nonatomic, copy) NSString *message;
@property (nonatomic) NSInteger style;
@property (nonatomic) BOOL showsInput;
@property (nonatomic, copy) NSString *defaultText;
@property (nonatomic, strong) NSTextField *inputField;
@property (nonatomic) NSInteger result;
/* Explicit button titles (End/Debug and similar): value N is title N-1. */
@property (nonatomic, copy) NSArray<NSString *> *customTitles;
@property (nonatomic) CGFloat messageHeight;
- (NSInteger)runWithTitle:(NSString *)title;
@end

@implementation VBClassicDialogView {
    NSInteger _pressedButton;
    NSInteger _buttonCount;
    BOOL _modal;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (NSArray<NSNumber *> *)buttonValues
{
    if (self.customTitles.count) {
        NSMutableArray<NSNumber *> *values = [NSMutableArray array];
        for (NSUInteger i = 0; i < self.customTitles.count; i++) [values addObject:@(i + 1)];
        return values;
    }
    switch (self.style & 0x0F) {
        case 1: return @[@1, @2];
        case 2: return @[@3, @4, @5];
        case 3: return @[@6, @7, @2];
        case 4: return @[@6, @7];
        case 5: return @[@4, @2];
        default: return @[@1];
    }
}

- (NSString *)titleForButton:(NSInteger)value
{
    if (self.customTitles.count && value >= 1 && value <= (NSInteger)self.customTitles.count) {
        return self.customTitles[(NSUInteger)(value - 1)];
    }
    switch (value) {
        case 2: return @"Cancel";
        case 3: return @"Abort";
        case 4: return @"Retry";
        case 5: return @"Ignore";
        case 6: return @"Yes";
        case 7: return @"No";
        default: return @"OK";
    }
}

- (NSRect)rectForButtonAtIndex:(NSInteger)index
{
    NSArray<NSNumber *> *values = [self buttonValues];
    CGFloat width = 76;
    CGFloat gap = 8;
    CGFloat total = values.count * width + (values.count - 1) * gap;
    CGFloat x = floor((NSWidth(self.bounds) - total) / 2.0) + index * (width + gap);
    return NSMakeRect(x, NSHeight(self.bounds) - 34, width, 23);
}

- (NSInteger)buttonIndexAtPoint:(NSPoint)point
{
    NSArray<NSNumber *> *values = [self buttonValues];
    for (NSInteger i = 0; i < (NSInteger)values.count; i++) {
        if (NSPointInRect(point, [self rectForButtonAtIndex:i])) return i;
    }
    return -1;
}

- (void)drawIconInRect:(NSRect)rect
{
    NSInteger icon = self.style & 0xF0;
    if (icon == 0) return;
    if (icon == 48) {
        NSBezierPath *triangle = [NSBezierPath bezierPath];
        [triangle moveToPoint:NSMakePoint(NSMidX(rect), NSMinY(rect))];
        [triangle lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [triangle lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        [triangle closePath];
        [[NSColor colorWithSRGBRed:1.0 green:0.90 blue:0.35 alpha:1] setFill];
        [triangle fill];
        [VBColorText() setStroke];
        [triangle setLineWidth:1.2];
        [triangle stroke];
        [VBColorText() setFill];
        NSRectFill(NSMakeRect(NSMidX(rect) - 1, NSMinY(rect) + 8, 3, 10));
        NSRectFill(NSMakeRect(NSMidX(rect) - 1, NSMinY(rect) + 20, 3, 3));
        return;
    }
    NSColor *fill = icon == 16 ? [NSColor colorWithSRGBRed:0.85 green:0.10 blue:0.10 alpha:1]
                               : [NSColor colorWithSRGBRed:0.10 green:0.25 blue:0.75 alpha:1];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:rect];
    [fill setFill];
    [circle fill];
    [VBColorText() setStroke];
    [circle setLineWidth:1];
    [circle stroke];
    if (icon == 32) {
        NSDictionary *attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:20],
                                NSForegroundColorAttributeName: VBColorWindow()};
        NSSize size = [@"?" sizeWithAttributes:attrs];
        [@"?" drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2.0, NSMidY(rect) - size.height / 2.0)
            withAttributes:attrs];
    } else if (icon == 16) {
        [VBColorWindow() setStroke];
        [NSBezierPath setDefaultLineWidth:2.4];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(rect) + 10, NSMinY(rect) + 10)
                                  toPoint:NSMakePoint(NSMaxX(rect) - 10, NSMaxY(rect) - 10)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(rect) - 10, NSMinY(rect) + 10)
                                  toPoint:NSMakePoint(NSMinX(rect) + 10, NSMaxY(rect) - 10)];
    } else {
        NSDictionary *attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:20],
                                NSForegroundColorAttributeName: VBColorWindow()};
        NSSize size = [@"i" sizeWithAttributes:attrs];
        [@"i" drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2.0, NSMidY(rect) - size.height / 2.0)
            withAttributes:attrs];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);
    VBDrawPanelBorder(NSInsetRect(self.bounds, 1, 1));

    NSRect iconRect = NSMakeRect(20, 26, 32, 32);
    [self drawIconInRect:iconRect];
    CGFloat textX = (self.style & 0xF0) ? 66 : 20;
    CGFloat textWidth = NSWidth(self.bounds) - textX - 20;
    CGFloat messageHeight = self.messageHeight > 0 ? self.messageHeight : 40;
    DrawClassicText(self.message, NSMakeRect(textX, 18, textWidth, messageHeight), VBFontUI(),
                    VBColorText(), NSTextAlignmentLeft);

    if (self.showsInput) {
        NSRect field = NSMakeRect(textX, 72, textWidth, 22);
        VBDrawSunkenBevel(field);
    }

    NSArray<NSNumber *> *values = [self buttonValues];
    NSDictionary *attrs = @{NSFontAttributeName: VBFontUI(), NSForegroundColorAttributeName: VBColorText()};
    for (NSInteger i = 0; i < (NSInteger)values.count; i++) {
        NSRect rect = [self rectForButtonAtIndex:i];
        VBDrawClassicButton(rect, i == _pressedButton);
        if (i == 0) {
            [[VBColorText() colorWithAlphaComponent:0.85] setStroke];
            [NSBezierPath strokeRect:NSInsetRect(rect, 2.5, 2.5)];
        }
        NSString *title = [self titleForButton:values[(NSUInteger)i].integerValue];
        NSSize size = [title sizeWithAttributes:attrs];
        [title drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2.0,
                                       NSMidY(rect) - size.height / 2.0)
            withAttributes:attrs];
    }
}

- (void)setShowsInput:(BOOL)showsInput
{
    _showsInput = showsInput;
    if (!showsInput) return;
    if (!_inputField) {
        _inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 18)];
        _inputField.bezeled = NO;
        _inputField.bordered = NO;
        _inputField.drawsBackground = NO;
        _inputField.focusRingType = NSFocusRingTypeNone;
        _inputField.font = VBFontUI();
        _inputField.textColor = VBColorText();
        _inputField.target = self;
        _inputField.action = @selector(acceptDefaultButton:);
        _inputField.delegate = self;
        [self addSubview:_inputField];
    }
    CGFloat textX = (self.style & 0xF0) ? 66 : 20;
    _inputField.frame = NSMakeRect(textX + 3, 75, NSWidth(self.bounds) - textX - 29, 16);
    _inputField.stringValue = self.defaultText ?: @"";
}

- (void)acceptDefaultButton:(id)sender
{
    (void)sender;
    [self finishWithResult:[self buttonValues].firstObject.integerValue];
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification
{
    NSTextView *editor = notification.userInfo[@"NSFieldEditor"];
    if (![editor isKindOfClass:[NSTextView class]]) return;
    editor.selectedTextAttributes = @{
        NSBackgroundColorAttributeName: VBColorSelection(),
        NSForegroundColorAttributeName: VBColorTitleText()
    };
    editor.insertionPointColor = VBColorText();
}

- (void)finishWithResult:(NSInteger)result
{
    self.result = result;
    if (_modal) {
        [NSApp stopModal];
        _modal = NO;
    }
    [self.window orderOut:nil];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self buttonIndexAtPoint:point];
    _pressedButton = index;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self buttonIndexAtPoint:point];
    if (index >= 0 && index == _pressedButton) {
        NSArray<NSNumber *> *values = [self buttonValues];
        [self finishWithResult:values[(NSUInteger)index].integerValue];
        return;
    }
    _pressedButton = -1;
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 53) {
        NSArray<NSNumber *> *values = [self buttonValues];
        /* Esc picks Cancel for message boxes; for End/Debug it must never pick Debug. */
        NSInteger result = self.customTitles.count ? values.firstObject.integerValue
                          : (values.count > 1 ? 2 : values.firstObject.integerValue);
        [self finishWithResult:result];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        [self acceptDefaultButton:nil];
        return;
    }
    [super keyDown:event];
}

- (NSInteger)runWithTitle:(NSString *)title
{
    CGFloat height = self.showsInput ? 152 : (self.customTitles.count ? 162 : 146);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, VB_DIALOG_WIDTH, height)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = title.length ? title : @"VB6CloneIDE";
    window.releasedWhenClosed = NO;
    window.backgroundColor = VBColorFace();
    self.frame = NSMakeRect(0, 0, VB_DIALOG_WIDTH, height);
    window.contentView = self;
    window.delegate = self;
    [window center];
    self.result = 0;
    _pressedButton = -1;
    _modal = YES;
    [window makeKeyAndOrderFront:nil];
    if (self.showsInput) {
        [window makeFirstResponder:self.inputField];
        [self.inputField selectText:nil];
    } else {
        [window makeFirstResponder:self];
    }
    [NSApp runModalForWindow:window];
    [window orderOut:nil];
    [window close];
    return self.result;
}

- (void)windowWillClose:(NSNotification *)notification
{
    (void)notification;
    if (_modal) {
        [NSApp stopModal];
        _modal = NO;
    }
}

@end

/* VB6 run-time error dialog: error icon, "Run-time error 'N':" and the End/Debug
   buttons (Continue is not available because there is no active error handler). */
static NSInteger ShowRuntimeErrorDialog(NSString *title, NSString *message)
{
    VBClassicDialogView *content = [[VBClassicDialogView alloc]
        initWithFrame:NSMakeRect(0, 0, VB_DIALOG_WIDTH, 162)];
    content.message = message ?: @"";
    content.style = 0x10;
    content.customTitles = @[@"End", @"Debug"];
    content.messageHeight = 76;
    return [content runWithTitle:title.length ? title : @"VB6CloneIDE"];
}

static NSInteger ShowClassicDialog(NSString *title, NSString *message, NSInteger style,
                                   BOOL showsInput, NSString *defaultText, NSString **outText)
{
    VBClassicDialogView *content = [[VBClassicDialogView alloc] initWithFrame:NSMakeRect(0, 0, VB_DIALOG_WIDTH, 150)];
    content.message = message ?: @"";
    content.style = style;
    if (showsInput) {
        content.defaultText = defaultText ?: @"";
        content.showsInput = YES;
    }
    NSInteger result = [content runWithTitle:title];
    if (outText) *outText = content.inputField ? content.inputField.stringValue : @"";
    return result;
}

#pragma mark - Runtime canvas (form, frame, picture, line, shape)

@interface VBRuntimeCanvas : NSView
@property (nonatomic) VbControl *control;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic) BOOL isForm;
/* A disabled container disables every control inside it, as in VB6. */
@property (nonatomic) BOOL enabled;
@property (nonatomic, weak) id<VBClassicControlHost> host;
@end

@implementation VBRuntimeCanvas
- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _enabled = YES;
    return self;
}

- (BOOL)isFlipped { return YES; }

/* Access keys reach this view when the window searches key equivalents (the form does
   not take the focus itself: that would put it in the AppKit key-view loop). */
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if (self.host && [self.host activateAccessKeyForEvent:event]) return YES;
    return [super performKeyEquivalent:event];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    if (self.isForm) {
        [RuntimeColor(self.control, "BackColor", VBColorFace()) setFill];
        NSRectFill(self.bounds);
        return;
    }
    if ([self.kind isEqualToString:@"VB.Frame"] || [self.kind isEqualToString:@"VB.PictureBox"]) {
        [RuntimeColor(self.control, "BackColor", VBColorFace()) setFill];
        NSRectFill(self.bounds);
        if ([self.kind isEqualToString:@"VB.Frame"]) {
            VBDrawEtchedBorder(self.bounds);
        } else {
            [[VBColorShadow() colorWithAlphaComponent:0.95] setFill];
            NSRectFill(NSMakeRect(0, 0, NSWidth(self.bounds), 1));
            NSRectFill(NSMakeRect(0, 0, 1, NSHeight(self.bounds)));
        }
        if ([self.kind isEqualToString:@"VB.Frame"]) {
            NSString *caption = DisplayProp(self.control, "Caption");
            if (caption.length) {
                NSColor *captionColor = self.enabled ? RuntimeColor(self.control, "ForeColor", VBColorText())
                                                     : VBColorShadow();
                NSDictionary *attrs = @{NSFontAttributeName: RuntimeFont(self.control),
                                        NSForegroundColorAttributeName: captionColor};
                NSSize size = [caption sizeWithAttributes:attrs];
                NSRect bg = NSMakeRect(7, 0, size.width + 4, size.height);
                [RuntimeColor(self.control, "BackColor", VBColorFace()) setFill];
                NSRectFill(bg);
                [caption drawAtPoint:NSMakePoint(bg.origin.x + 2, 1) withAttributes:attrs];
            }
        }
        return;
    }
    if ([self.kind isEqualToString:@"VB.Line"]) {
        int x1 = vb_control_get_int(self.control, "X1", 0);
        int y1 = vb_control_get_int(self.control, "Y1", 0);
        int x2 = vb_control_get_int(self.control, "X2", vb_control_get_int(self.control, "Width", 0));
        int y2 = vb_control_get_int(self.control, "Y2", vb_control_get_int(self.control, "Height", 0));
        [[NSColor blackColor] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(VBTwipsToPoints(x1), VBTwipsToPoints(y1))
                                  toPoint:NSMakePoint(VBTwipsToPoints(x2), VBTwipsToPoints(y2))];
        return;
    }
    if ([self.kind isEqualToString:@"VB.Shape"]) {
        int shape = vb_control_get_int(self.control, "Shape", 0);
        NSColor *fill = RuntimeColor(self.control, "FillColor", nil);
        NSColor *line = RuntimeColor(self.control, "BackColor", [NSColor blackColor]);
        NSRect rect = NSInsetRect(self.bounds, 0.5, 0.5);
        NSBezierPath *path = (shape == 2 || shape == 3) ? [NSBezierPath bezierPathWithOvalInRect:rect]
                                                        : [NSBezierPath bezierPathWithRect:rect];
        if (fill && vb_control_get_int(self.control, "FillStyle", 1) != 0) {
            [fill setFill];
            [path fill];
        }
        [line setStroke];
        [path stroke];
        return;
    }
}
@end

/* The window holds the focus when no control can (empty form, every control disabled):
   it still answers access keys instead of beeping. */
@interface VBRuntimeNSWindow : NSWindow
@property (nonatomic, weak) id<VBClassicControlHost> host;
@end

@implementation VBRuntimeNSWindow
- (void)keyDown:(NSEvent *)event
{
    if (self.host && [self.host activateAccessKeyForEvent:event]) return;
    [super keyDown:event];
}
@end

#pragma mark - Classic control view

@interface VBClassicControlView : NSView
@property (nonatomic) VbControl *control;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, weak) id<VBClassicControlHost> host;
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSInteger value;
@property (nonatomic) BOOL pressed;
@property (nonatomic) BOOL focused;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL tabStop;
@property (nonatomic, strong) NSMutableArray<NSString *> *items;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic) NSInteger caret;
@property (nonatomic) NSInteger scrollValue;
- (instancetype)initWithControl:(VbControl *)control kind:(NSString *)kind;
- (BOOL)isFocusableKind;
- (BOOL)isEffectivelyEnabled;
/* Focusable: kind, enabled, visible. TabStop only keeps it out of the Tab cycle. */
- (BOOL)canReceiveFocus;
- (BOOL)canTakeFocus;
/* Alt+letter activation: presses the button / toggles the check and fires Click. */
- (void)activateFromAccessKey;
- (void)ensureGridLayout;
@end

@implementation VBClassicControlView {
    /* Runtime DataGrid: in-memory sheet, selection and the cell being edited. */
    VbGrid _grid;
    BOOL _gridReady;
    NSInteger _resizingColumn;
    CGFloat _resizeStartX;
    double _resizeStartWidth;
}

static const CGFloat kDataGridHeaderHeight = 18.0;

- (void)dealloc
{
    vb_grid_free(&_grid);
}

- (instancetype)initWithControl:(VbControl *)control kind:(NSString *)kind
{
    self = [super initWithFrame:NSMakeRect(0, 0, 100, 20)];
    if (!self) return nil;
    _control = control;
    _kind = [kind copy];
    _items = [NSMutableArray array];
    _selectedIndex = -1;
    _caret = 0;
    _enabled = ControlEnabledAtLoad(control);
    _tabStop = !(control && vb_control_get_int(control, "TabStop", -1) == 0);
    _text = [DisplayProp(control, "Text") copy];
    if (!_text.length) _text = [DisplayProp(control, "Caption") copy] ?: @"";
    _value = vb_control_get_int(control, "Value", 0);
    self.focusRingType = NSFocusRingTypeNone;
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isFocusableKind
{
    static NSSet *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kinds = [NSSet setWithObjects:@"VB.TextBox", @"VB.CommandButton", @"VB.CheckBox",
                @"VB.OptionButton", @"VB.ComboBox", @"VB.ListBox", @"VB.HScrollBar",
                @"VB.VScrollBar", @"VB.DataGrid", nil];
    });
    return [kinds containsObject:self.kind];
}

/* Enabled = False on a Frame/PictureBox disables its children: walk the container chain. */
- (BOOL)isEffectivelyEnabled
{
    if (!self.enabled) return NO;
    for (NSView *view = self.superview; view; view = view.superview) {
        if ([view isKindOfClass:[VBRuntimeCanvas class]] && !((VBRuntimeCanvas *)view).enabled) return NO;
    }
    return YES;
}

- (BOOL)canReceiveFocus
{
    if (![self isFocusableKind] || ![self isEffectivelyEnabled]) return NO;
    if (self.hidden || self.isHiddenOrHasHiddenAncestor) return NO;
    return YES;
}

- (BOOL)canTakeFocus
{
    return [self canReceiveFocus] && self.tabStop;
}

- (BOOL)acceptsFirstResponder
{
    return [self canReceiveFocus];
}
- (BOOL)becomesFirstResponderOnMouseDown { return YES; }

- (BOOL)isButtonKind
{
    return [self.kind isEqualToString:@"VB.CommandButton"];
}

#pragma mark - DataGrid

/* Lays the sheet out from the VB6 properties: DefColWidth/RowHeight in twips become
   points, the column count fills the control once, and the rows always fill its height. */
- (void)ensureGridLayout
{
    double defaultWidth, rowHeight, headerHeight;
    double innerWidth, innerHeight;
    if (![self.kind isEqualToString:@"VB.DataGrid"]) return;
    defaultWidth = VBTwipsToPoints(vb_control_get_int(self.control, "DefColWidth", 1275));
    if (defaultWidth < 24) defaultWidth = 80;
    rowHeight = VBTwipsToPoints(vb_control_get_int(self.control, "RowHeight", 255));
    if (rowHeight < 12) rowHeight = 17;
    headerHeight = (vb_control_get_int(self.control, "ColumnHeaders", -1) != 0 &&
                    NSHeight(self.bounds) > 26) ? kDataGridHeaderHeight : 0;
    if (!_gridReady) {
        vb_grid_init(&_grid, 0, 0, defaultWidth, rowHeight);
        _gridReady = YES;
    }
    vb_grid_set_metrics(&_grid, defaultWidth, rowHeight, headerHeight);
    innerWidth = MAX(1.0, NSWidth(self.bounds) - 4);
    innerHeight = MAX(1.0, NSHeight(self.bounds) - 4);
    vb_grid_fit(&_grid, innerWidth, innerHeight);
}

- (void)commitGridEdit
{
    if (!_grid.editing) return;
    vb_grid_commit_edit(&_grid);
    [self fire:@"AfterColUpdate"];
    [self setNeedsDisplay:YES];
}

- (void)drawDataGrid
{
    NSFont *font = RuntimeFont(self.control);
    BOOL enabled = [self isEffectivelyEnabled];
    NSColor *back = enabled ? RuntimeColor(self.control, "BackColor", VBColorWindow()) : VBColorFace();
    NSColor *fore = enabled ? RuntimeColor(self.control, "ForeColor", VBColorText()) : VBColorShadow();
    NSColor *line = [VBColorShadow() colorWithAlphaComponent:0.35];
    NSRect inner;
    CGFloat headerHeight, rowHeight, x;
    int r, c;

    [self ensureGridLayout];
    [back setFill];
    NSRectFill(self.bounds);
    VBDrawSunkenBevel(self.bounds);
    inner = NSInsetRect(self.bounds, 2, 2);
    headerHeight = (CGFloat)_grid.header_height;
    rowHeight = (CGFloat)_grid.row_height;

    if (headerHeight > 0) {
        NSRect header = NSMakeRect(NSMinX(inner), NSMinY(inner), NSWidth(inner), headerHeight);
        [VBColorFace() setFill];
        NSRectFill(header);
        [VBColorShadow() setFill];
        NSRectFill(NSMakeRect(NSMinX(header), NSMaxY(header) - 1, NSWidth(header), 1));
        [VBColorLight() setFill];
        NSRectFill(NSMakeRect(NSMinX(header), NSMaxY(header) - 2, NSWidth(header), 1));
    }

    /* The grid lines are 1px on both scales, like the rest of the Win98 chrome. */
    [line setFill];
    x = NSMinX(inner);
    for (c = 0; c < _grid.columns; c++) {
        x += vb_grid_column_width(&_grid, c);
        if (x > NSMaxX(inner)) break;
        NSRectFill(NSMakeRect(floor(x), NSMinY(inner), 1, NSHeight(inner)));
    }
    for (r = 1; r <= _grid.rows; r++) {
        CGFloat y = NSMinY(inner) + headerHeight + r * rowHeight;
        if (y > NSMaxY(inner)) break;
        NSRectFill(NSMakeRect(NSMinX(inner), floor(y), NSWidth(inner), 1));
    }

    x = NSMinX(inner);
    for (c = 0; c < _grid.columns && x < NSMaxX(inner); c++) {
        CGFloat width = vb_grid_column_width(&_grid, c);
        for (r = 0; r < _grid.rows; r++) {
            NSRect cell = NSMakeRect(x, NSMinY(inner) + headerHeight + r * rowHeight, width, rowHeight);
            BOOL selected = (r == _grid.selected_row && c == _grid.selected_column);
            BOOL editing = selected && _grid.editing;
            NSString *text;
            NSColor *color = fore;
            NSDictionary *attrs;
            NSSize size;
            NSRect clip;
            if (NSMinY(cell) >= NSMaxY(inner)) break;
            if (selected && self.focused && enabled) {
                [VBColorSelection() setFill];
                NSRectFill(NSIntersectionRect(cell, inner));
                color = VBColorTitleText();
            }
            text = [NSString stringWithUTF8String:editing ? vb_grid_edit_text(&_grid)
                                                         : vb_grid_cell(&_grid, r, c)];
            if (text.length) {
                attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: color};
                size = [text sizeWithAttributes:attrs];
                clip = NSIntersectionRect(NSInsetRect(cell, 1, 1), inner);
                [[NSGraphicsContext currentContext] saveGraphicsState];
                NSRectClip(clip);
                [text drawAtPoint:NSMakePoint(NSMinX(cell) + 3, NSMidY(cell) - size.height / 2.0)
                   withAttributes:attrs];
                [[NSGraphicsContext currentContext] restoreGraphicsState];
            }
            if (editing) {
                CGFloat caretX = NSMinX(cell) + 3;
                if (text.length) {
                    caretX += [text sizeWithAttributes:@{NSFontAttributeName: font}].width;
                }
                [VBColorText() setFill];
                NSRectFill(NSMakeRect(MIN(caretX, NSMaxX(cell) - 2), NSMinY(cell) + 3, 1, rowHeight - 6));
            }
        }
        x += width;
    }
}

- (void)dataGridMouseDown:(NSPoint)point
{
    int row = -1, column = -1, border = -1;
    [self ensureGridLayout];
    if (!vb_grid_hit_test(&_grid, point.x, point.y, _grid.header_height > 0, &row, &column, &border)) return;
    [self.window makeFirstResponder:self];
    if (border >= 0) {
        /* Dragging the boundary in the header resizes that column. */
        _resizingColumn = border;
        _resizeStartX = point.x;
        _resizeStartWidth = vb_grid_column_width(&_grid, border);
        return;
    }
    if (row < 0 || column < 0) return;
    if (_grid.editing) [self commitGridEdit];
    {
        BOOL changed = (row != _grid.selected_row || column != _grid.selected_column);
        vb_grid_select(&_grid, row, column);
        [self fire:@"Click"];
        if (changed) [self fire:@"RowColChange"];
    }
    [self setNeedsDisplay:YES];
}

- (void)dataGridKeyDown:(NSEvent *)event
{
    int previousRow, previousColumn;
    if (!_gridReady) [self ensureGridLayout];
    /* Ctrl+Tab leaves the grid: plain Tab stays inside it, as in VB6. */
    if (event.keyCode == 48 && (event.modifierFlags & NSEventModifierFlagControl)) {
        [self commitGridEdit];
        [self.host classicControl:self
              requestsTabBackwards:(event.modifierFlags & NSEventModifierFlagShift) != 0];
        return;
    }
    previousRow = _grid.selected_row;
    previousColumn = _grid.selected_column;
    switch (event.keyCode) {
        case 123: vb_grid_move_selection(&_grid, 0, -1); break;  /* left */
        case 124: vb_grid_move_selection(&_grid, 0, 1); break;   /* right */
        case 125: vb_grid_move_selection(&_grid, 1, 0); break;   /* down */
        case 126: vb_grid_move_selection(&_grid, -1, 0); break;  /* up */
        case 48: {  /* Tab / Shift+Tab move to the next cell, as VB6 does */
            [self commitGridEdit];
            vb_grid_move_selection(&_grid, 0,
                                   (event.modifierFlags & NSEventModifierFlagShift) ? -1 : 1);
            break;
        }
        case 36: case 76:  /* Return: commit and go down, or start editing */
            if (_grid.editing) {
                [self commitGridEdit];
                vb_grid_move_selection(&_grid, 1, 0);
            } else {
                vb_grid_begin_edit(&_grid);
            }
            break;
        case 53: vb_grid_cancel_edit(&_grid); break;  /* Esc */
        case 51:  /* Backspace: edit the cell instead of leaving it */
            if (_grid.editing) vb_grid_edit_backspace(&_grid);
            else vb_grid_edit_reset(&_grid);
            break;
        case 117:  /* forward delete clears the cell */
            vb_grid_clear_cell(&_grid, _grid.selected_row, _grid.selected_column);
            [self fire:@"AfterColUpdate"];
            break;
        case 120: vb_grid_begin_edit(&_grid); break;  /* F2 */
        default: {
            NSString *characters = event.characters;
            if (characters.length && !(event.modifierFlags & NSEventModifierFlagCommand)) {
                NSString *insert = [characters stringByReplacingOccurrencesOfString:@"\n" withString:@""];
                if (insert.length) {
                    /* Typing over a selected cell starts empty, like VB6. */
                    if (!_grid.editing) vb_grid_edit_reset(&_grid);
                    vb_grid_edit_insert(&_grid, insert.UTF8String);
                }
            }
            break;
        }
    }
    if (_grid.selected_row != previousRow || _grid.selected_column != previousColumn) {
        [self fire:@"RowColChange"];
    }
    [self setNeedsDisplay:YES];
}

- (void)resetCursorRects
{
    CGFloat x;
    int c;
    [super resetCursorRects];
    if (![self.kind isEqualToString:@"VB.DataGrid"] || ![self isEffectivelyEnabled]) return;
    [self ensureGridLayout];
    if (_grid.header_height <= 0) return;
    x = 2;
    for (c = 0; c < _grid.columns; c++) {
        x += vb_grid_column_width(&_grid, c);
        [self addCursorRect:NSMakeRect(x - 3, 2, 6, _grid.header_height)
                     cursor:[NSCursor resizeLeftRightCursor]];
    }
}

- (void)drawFocusRing:(NSRect)rect
{
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 0.5, 0.5)];
    CGFloat pattern[2] = {1, 1};
    [path setLineDash:pattern count:2 phase:0];
    [path setLineWidth:1];
    [VBColorText() setStroke];
    [path stroke];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSFont *font = RuntimeFont(self.control);
    BOOL enabled = [self isEffectivelyEnabled];
    NSColor *fore = enabled ? RuntimeColor(self.control, "ForeColor", VBColorText()) : VBColorShadow();
    /* Disabled edits and lists get the grey 3D face, as on Win98. */
    NSColor *fieldBack = enabled ? RuntimeColor(self.control, "BackColor", VBColorWindow()) : VBColorFace();

    if ([self.kind isEqualToString:@"VB.Label"]) {
        /* Labels use access keys too, unless UseMnemonic = False. */
        BOOL useMnemonic = vb_control_get_int(self.control, "UseMnemonic", -1) != 0;
        DrawClassicCaption(self.text, NSMakeRect(0, 0, NSWidth(self.bounds), NSHeight(self.bounds)),
                           font, fore, RuntimeAlignment(self.control), useMnemonic);
        return;
    }
    if ([self.kind isEqualToString:@"VB.TextBox"]) {
        [fieldBack setFill];
        NSRectFill(self.bounds);
        VBDrawSunkenBevel(self.bounds);
        if (!enabled) {
            [VBColorFace() setFill];
            NSRectFill(NSInsetRect(self.bounds, 2, 2));
        }
        NSRect inner = NSInsetRect(self.bounds, 3, 2);
        DrawClassicText(self.text, inner, font, fore, NSTextAlignmentLeft);
        if (self.focused) {
            NSDictionary *attrs = @{NSFontAttributeName: font};
            CGFloat width = 0;
            NSInteger caret = MIN(MAX(0, self.caret), (NSInteger)self.text.length);
            if (caret > 0) {
                width = [[self.text substringToIndex:(NSUInteger)caret] sizeWithAttributes:attrs].width;
            }
            CGFloat x = MIN(NSMinX(inner) + width, NSMaxX(inner) - 1);
            [VBColorText() setFill];
            NSRectFill(NSMakeRect(x, NSMinY(inner) + 1, 1, NSHeight(inner) - 2));
        }
        return;
    }
    if ([self.kind isEqualToString:@"VB.CommandButton"]) {
        VBDrawClassicButton(self.bounds, self.pressed);
        NSRect textRect = NSInsetRect(self.bounds, 4, 2);
        if (self.pressed) textRect.origin.x += 1, textRect.origin.y += 1;
        DrawClassicCaption(self.text, textRect, font, fore, NSTextAlignmentCenter, YES);
        if (self.focused) [self drawFocusRing:NSInsetRect(self.bounds, 4, 3)];
        return;
    }
    if ([self.kind isEqualToString:@"VB.CheckBox"] || [self.kind isEqualToString:@"VB.OptionButton"]) {
        NSRect box = NSMakeRect(1, NSMidY(self.bounds) - 6, 12, 12);
        if ([self.kind isEqualToString:@"VB.OptionButton"]) VBDrawClassicRadio(box, self.value != 0);
        else VBDrawClassicCheck(box, self.value != 0);
        DrawClassicCaption(self.text, NSMakeRect(17, 0, NSWidth(self.bounds) - 18, NSHeight(self.bounds)),
                           font, fore, NSTextAlignmentLeft, YES);
        if (self.focused) [self drawFocusRing:NSMakeRect(15, 1, NSWidth(self.bounds) - 16, NSHeight(self.bounds) - 2)];
        return;
    }
    if ([self.kind isEqualToString:@"VB.ComboBox"]) {
        [fieldBack setFill];
        NSRectFill(self.bounds);
        VBDrawSunkenBevel(self.bounds);
        if (!enabled) {
            [VBColorFace() setFill];
            NSRectFill(NSInsetRect(self.bounds, 2, 2));
        }
        NSRect arrow = NSMakeRect(NSMaxX(self.bounds) - 17, 1, 16, NSHeight(self.bounds) - 2);
        VBDrawRaisedBevel(arrow);
        VBDrawClassicArrow(NSMakeRect(NSMidX(arrow) - 4, NSMidY(arrow) - 2, 8, 5), YES, VBColorText());
        DrawClassicText(self.text, NSMakeRect(3, 0, NSWidth(self.bounds) - 24, NSHeight(self.bounds)),
                        font, fore, NSTextAlignmentLeft);
        if (self.focused) [self drawFocusRing:NSMakeRect(2, 2, NSWidth(self.bounds) - 21, NSHeight(self.bounds) - 4)];
        return;
    }
    if ([self.kind isEqualToString:@"VB.ListBox"] ||
        [self.kind isEqualToString:@"VB.FileListBox"] ||
        [self.kind isEqualToString:@"VB.DirListBox"] ||
        [self.kind isEqualToString:@"VB.DriveListBox"]) {
        [fieldBack setFill];
        NSRectFill(self.bounds);
        VBDrawSunkenBevel(self.bounds);
        if (!enabled) {
            [VBColorFace() setFill];
            NSRectFill(NSInsetRect(self.bounds, 2, 2));
        }
        CGFloat y = 4;
        for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) {
            NSRect row = NSMakeRect(3, y, NSWidth(self.bounds) - 6, 16);
            if (i == self.selectedIndex) {
                [VBColorSelection() setFill];
                NSRectFill(row);
            }
            DrawClassicText(self.items[(NSUInteger)i], NSMakeRect(row.origin.x + 2, row.origin.y, row.size.width - 4, 16),
                            font, i == self.selectedIndex ? VBColorTitleText() : fore, NSTextAlignmentLeft);
            y += 16;
            if (y > NSHeight(self.bounds) - 4) break;
        }
        if (self.focused) [self drawFocusRing:NSInsetRect(self.bounds, 2, 2)];
        return;
    }
    if ([self.kind isEqualToString:@"VB.HScrollBar"] || [self.kind isEqualToString:@"VB.VScrollBar"]) {
        VBFillFace(self.bounds);
        VBDrawSunkenBevel(self.bounds);
        BOOL horizontal = [self.kind isEqualToString:@"VB.HScrollBar"];
        if (horizontal) {
            NSRect left = NSMakeRect(1, 1, MIN(16, NSWidth(self.bounds)), NSHeight(self.bounds) - 2);
            NSRect right = NSMakeRect(NSMaxX(self.bounds) - 17, 1, 16, NSHeight(self.bounds) - 2);
            VBDrawRaisedBevel(left);
            VBDrawRaisedBevel(right);
            VBDrawClassicArrow(NSMakeRect(NSMidX(left) - 4, NSMidY(left) - 3, 8, 6), NO, VBColorText());
            VBDrawClassicArrow(NSMakeRect(NSMidX(right) - 4, NSMidY(right) - 3, 8, 6), YES, VBColorText());
            CGFloat track = NSWidth(self.bounds) - 34;
            VBDrawRaisedBevel(NSMakeRect(18, 3, MAX(10, track / 3), NSHeight(self.bounds) - 6));
        } else {
            NSRect top = NSMakeRect(1, 1, NSWidth(self.bounds) - 2, MIN(16, NSHeight(self.bounds)));
            NSRect bottom = NSMakeRect(1, NSMaxY(self.bounds) - 17, NSWidth(self.bounds) - 2, 16);
            VBDrawRaisedBevel(top);
            VBDrawRaisedBevel(bottom);
            VBDrawClassicArrow(NSMakeRect(NSMidX(top) - 4, NSMidY(top) - 3, 8, 6), NO, VBColorText());
            VBDrawClassicArrow(NSMakeRect(NSMidX(bottom) - 4, NSMidY(bottom) - 3, 8, 6), YES, VBColorText());
            CGFloat track = NSHeight(self.bounds) - 34;
            VBDrawRaisedBevel(NSMakeRect(3, 18, NSWidth(self.bounds) - 6, MAX(10, track / 3)));
        }
        return;
    }
    if ([self.kind isEqualToString:@"VB.Image"]) {
        VBFillFace(self.bounds);
        [[VBColorShadow() colorWithAlphaComponent:0.95] setStroke];
        [NSBezierPath strokeRect:NSInsetRect(self.bounds, 0.5, 0.5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(self.bounds), NSMinY(self.bounds))
                                  toPoint:NSMakePoint(NSMaxX(self.bounds), NSMaxY(self.bounds))];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(self.bounds), NSMinY(self.bounds))
                                  toPoint:NSMakePoint(NSMinX(self.bounds), NSMaxY(self.bounds))];
        return;
    }
    if ([self.kind isEqualToString:@"VB.Data"]) {
        /* VB6 draws the Data control caption (the current record) left of its nav buttons. */
        VBDrawClassicDataControl(self.bounds, self.text);
        return;
    }
    if ([self.kind isEqualToString:@"VB.DataGrid"]) {
        [self drawDataGrid];
        return;
    }
    VBFillFace(self.bounds);
    [[VBColorShadow() colorWithAlphaComponent:0.9] setStroke];
    [NSBezierPath strokeRect:NSInsetRect(self.bounds, 0.5, 0.5)];
}

- (void)syncFromModel
{
    if ([self.kind isEqualToString:@"VB.TextBox"]) {
        self.text = DisplayProp(self.control, "Text");
        self.caret = (NSInteger)self.text.length;
    } else if ([self.kind isEqualToString:@"VB.CommandButton"] ||
               [self.kind isEqualToString:@"VB.CheckBox"] ||
               [self.kind isEqualToString:@"VB.OptionButton"] ||
               [self.kind isEqualToString:@"VB.Label"]) {
        self.text = DisplayProp(self.control, "Caption");
    }
    self.value = vb_control_get_int(self.control, "Value", 0);
    [self setNeedsDisplay:YES];
}

- (void)fire:(NSString *)event
{
    [self.host classicControl:self fireEvent:event];
}

- (void)mouseDown:(NSEvent *)event
{
    BOOL inside = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    if (!inside || ![self isEffectivelyEnabled]) return;

    if ([self.kind isEqualToString:@"VB.DataGrid"]) {
        [self dataGridMouseDown:[self convertPoint:event.locationInWindow fromView:nil]];
        return;
    }
    if ([self.kind isEqualToString:@"VB.CommandButton"]) {
        [self.window makeFirstResponder:self];
        self.pressed = YES;
        [self setNeedsDisplay:YES];
        return;
    }
    if ([self.kind isEqualToString:@"VB.TextBox"]) {
        [self.window makeFirstResponder:self];
        self.focused = YES;
        self.caret = (NSInteger)self.text.length;
        [self setNeedsDisplay:YES];
        return;
    }
    if ([self.kind isEqualToString:@"VB.CheckBox"] || [self.kind isEqualToString:@"VB.OptionButton"]) {
        [self.window makeFirstResponder:self];
        self.value = self.value ? 0 : -1;
        [self setNeedsDisplay:YES];
        [self fire:@"Click"];
        return;
    }
    if ([self.kind isEqualToString:@"VB.ComboBox"]) {
        [self.window makeFirstResponder:self];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Items"];
        for (NSString *item in self.items) {
            NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:item action:nil keyEquivalent:@""];
            entry.target = self;
            entry.action = @selector(selectComboItem:);
            [menu addItem:entry];
        }
        if (!self.items.count) {
            NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:self.text ?: @"" action:nil keyEquivalent:@""];
            empty.enabled = NO;
            [menu addItem:empty];
        }
        NSPoint screen = [self.window convertPointToScreen:
                          [self convertPoint:NSMakePoint(NSMinX(self.bounds), NSMaxY(self.bounds)) toView:nil]];
        [menu popUpMenuPositioningItem:nil atLocation:screen inView:nil];
        return;
    }
    if ([self.kind isEqualToString:@"VB.ListBox"]) {
        [self.window makeFirstResponder:self];
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        NSInteger index = (NSInteger)floor((point.y - 4) / 16.0);
        if (index >= 0 && index < (NSInteger)self.items.count) {
            self.selectedIndex = index;
            [self setNeedsDisplay:YES];
            [self fire:@"Click"];
        }
        return;
    }
}

- (void)selectComboItem:(NSMenuItem *)sender
{
    self.text = sender.title;
    [self setNeedsDisplay:YES];
    [self fire:@"Click"];
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint point;
    if (_resizingColumn < 0) return;
    point = [self convertPoint:event.locationInWindow fromView:nil];
    if (vb_grid_resize_column(&_grid, (int)_resizingColumn,
                              _resizeStartWidth + (point.x - _resizeStartX))) {
        [self.window invalidateCursorRectsForView:self];
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    if (_resizingColumn >= 0) {
        _resizingColumn = -1;
        [self.window invalidateCursorRectsForView:self];
        [self setNeedsDisplay:YES];
        return;
    }
    if (![self.kind isEqualToString:@"VB.CommandButton"] || !self.pressed) return;
    self.pressed = NO;
    [self setNeedsDisplay:YES];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, self.bounds)) {
        [self.window makeFirstResponder:self];
        [self fire:@"Click"];
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (![self isEffectivelyEnabled]) {
        [super keyDown:event];
        return;
    }
    /* Alt+letter access keys are handled by the form before any text editing. */
    if ([self.host activateAccessKeyForEvent:event]) return;
    if ([self.kind isEqualToString:@"VB.DataGrid"]) {
        [self dataGridKeyDown:event];
        return;
    }
    if (event.keyCode == 48) { // tab / shift-tab follow TabIndex, not the AppKit key loop
        [self.host classicControl:self
              requestsTabBackwards:(event.modifierFlags & NSEventModifierFlagShift) != 0];
        return;
    }
    if (![self.kind isEqualToString:@"VB.TextBox"]) {
        [self keyDownForNonText:event];
        return;
    }
    NSString *characters = event.characters;
    NSUInteger length = characters.length;
    if (event.keyCode == 51 || event.keyCode == 117) { // delete / forward delete
        if (self.caret > 0 && self.text.length > 0) {
            NSUInteger index = (NSUInteger)(self.caret - 1);
            if (index < self.text.length) {
                self.text = [self.text stringByReplacingCharactersInRange:NSMakeRange(index, 1) withString:@""];
                self.caret--;
            }
        }
        [self setNeedsDisplay:YES];
        [self fire:@"Change"];
        return;
    }
    if (event.keyCode == 123) {
        self.caret = MAX(0, self.caret - 1);
        [self setNeedsDisplay:YES];
        return;
    }
    if (event.keyCode == 124) {
        self.caret = MIN((NSInteger)self.text.length, self.caret + 1);
        [self setNeedsDisplay:YES];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        [self fire:@"KeyPress"];
        return;
    }
    if (length == 0 || (event.modifierFlags & NSEventModifierFlagCommand)) {
        [super keyDown:event];
        return;
    }
    NSString *insert = [characters stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    NSInteger caret = MIN(MAX(0, self.caret), (NSInteger)self.text.length);
    self.text = [self.text stringByReplacingCharactersInRange:NSMakeRange((NSUInteger)caret, 0)
                                                  withString:insert];
    self.caret = caret + (NSInteger)insert.length;
    [self setNeedsDisplay:YES];
    [self fire:@"Change"];
}

- (void)activateFromAccessKey
{
    if ([self.kind isEqualToString:@"VB.CommandButton"]) {
        [self fire:@"Click"];
        return;
    }
    if ([self.kind isEqualToString:@"VB.CheckBox"] || [self.kind isEqualToString:@"VB.OptionButton"]) {
        self.value = self.value ? 0 : -1;
        [self setNeedsDisplay:YES];
        [self fire:@"Click"];
    }
}

- (void)keyDownForNonText:(NSEvent *)event
{
    /* VB6 activation keys for the controls that can take focus. */
    if (event.keyCode == 49) { // space
        if ([self.kind isEqualToString:@"VB.CommandButton"]) {
            [self fire:@"Click"];
            return;
        }
        if ([self.kind isEqualToString:@"VB.CheckBox"] || [self.kind isEqualToString:@"VB.OptionButton"]) {
            self.value = self.value ? 0 : -1;
            [self setNeedsDisplay:YES];
            [self fire:@"Click"];
            return;
        }
    }
    if ([self.kind isEqualToString:@"VB.ListBox"] && (event.keyCode == 125 || event.keyCode == 126)) {
        NSInteger count = (NSInteger)self.items.count;
        if (count > 0) {
            NSInteger next = self.selectedIndex + (event.keyCode == 125 ? 1 : -1);
            if (next < 0) next = 0;
            if (next >= count) next = count - 1;
            if (next != self.selectedIndex) {
                self.selectedIndex = next;
                [self setNeedsDisplay:YES];
                [self fire:@"Click"];
            }
        }
        return;
    }
    [super keyDown:event];
}

- (BOOL)becomeFirstResponder
{
    BOOL accepted = [super becomeFirstResponder];
    self.focused = YES;
    [self setNeedsDisplay:YES];
    if (accepted) [self.host classicControl:self fireFocusEvent:@"GotFocus"];
    return accepted;
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    if ([self.kind isEqualToString:@"VB.DataGrid"]) {
        [self.window invalidateCursorRectsForView:self];
    }
}

- (BOOL)resignFirstResponder
{
    BOOL resigned = [super resignFirstResponder];
    if ([self.kind isEqualToString:@"VB.DataGrid"] && _grid.editing) vb_grid_commit_edit(&_grid);
    self.focused = NO;
    [self setNeedsDisplay:YES];
    /* VB6 fires LostFocus before the next control's GotFocus. */
    if (resigned) [self.host classicControl:self fireFocusEvent:@"LostFocus"];
    return resigned;
}

- (void)keyUp:(NSEvent *)event
{
    (void)event;
}

@end

#pragma mark - Runtime window

@interface VBRuntimeWindow () <NSWindowDelegate, VBClassicControlHost>
- (const char *)propertyForControl:(NSString *)control property:(NSString *)property;
- (void)setProperty:(NSString *)property forControl:(NSString *)control value:(NSString *)value;
- (void)runHandler:(NSString *)handler;
- (int)presentRuntimeError:(NSInteger)number
                   message:(NSString *)message
                   handler:(NSString *)handler
                      line:(NSInteger)line;
- (void)stopTimers;
- (BOOL)breakModeAvailable;
- (BOOL)pauseForBreakWithHandler:(NSString *)handler line:(NSInteger)line;
- (VBRuntimeBreakAction)waitForBreakAction;
- (void)leaveBreakMode;
- (void)resolveBreakAction:(VBRuntimeBreakAction)action;
@end

static const char *RuntimeGetProp(void *ctx, const char *control, const char *prop)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    NSString *controlName = control ? [NSString stringWithUTF8String:control] : nil;
    NSString *property = prop ? [NSString stringWithUTF8String:prop] : nil;
    return [window propertyForControl:controlName property:property];
}

static void RuntimeSetProp(void *ctx, const char *control, const char *prop, const char *value)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    NSString *controlName = control ? [NSString stringWithUTF8String:control] : nil;
    NSString *property = prop ? [NSString stringWithUTF8String:prop] : nil;
    NSString *text = value ? [NSString stringWithUTF8String:value] : @"";
    [window setProperty:property forControl:controlName value:text];
}

static void RuntimeMsgBox(void *ctx, const char *text)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    if (window.suppressDialogs) {
        fprintf(stderr, "[runtime MsgBox] %s\n", text ? text : "");
        return;
    }
    ShowClassicDialog(window.window.title.length ? window.window.title : @"VB6CloneIDE",
                      text ? [NSString stringWithUTF8String:text] : @"", 0, NO, nil, NULL);
}

static int RuntimeConfirm(void *ctx, const char *text, const char *title, int style)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    if (window.suppressDialogs) {
        fprintf(stderr, "[runtime MsgBox style=%d] %s\n", style, text ? text : "");
        return 1;
    }
    NSString *heading = title && *title ? [NSString stringWithUTF8String:title]
                                        : (window.window.title ?: @"VB6CloneIDE");
    return ShowClassicDialog(heading, text ? [NSString stringWithUTF8String:text] : @"",
                             style, NO, nil, NULL);
}

static char *RuntimeInputBox(void *ctx, const char *prompt, const char *title, const char *defaultText)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    NSString *defaults = defaultText ? [NSString stringWithUTF8String:defaultText] : @"";
    if (window.suppressDialogs) {
        fprintf(stderr, "[runtime InputBox] %s\n", prompt ? prompt : "");
        return strdup(defaults.UTF8String);
    }
    NSString *heading = title && *title ? [NSString stringWithUTF8String:title]
                                        : (window.window.title ?: @"VB6CloneIDE");
    NSString *answer = nil;
    NSInteger result = ShowClassicDialog(heading, prompt ? [NSString stringWithUTF8String:prompt] : @"",
                                         1, YES, defaults, &answer);
    if (result == 2 || result == 0) return NULL;
    return strdup((answer ?: @"").UTF8String);
}

static void RuntimeClose(void *ctx)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    [window.window close];
}

static int RuntimeSetFocus(void *ctx, const char *control)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    if (!control || !*control) return 0; // Form.SetFocus is not a VB6 statement
    return [window setFocusToControl:[NSString stringWithUTF8String:control]] ? 1 : 0;
}

static int RuntimeError(void *ctx, int number, const char *message,
                        const char *handler, int line)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    return [window presentRuntimeError:number
                               message:message ? [NSString stringWithUTF8String:message] : @""
                               handler:handler ? [NSString stringWithUTF8String:handler] : @""
                                  line:line];
}

static int RuntimeBreak(void *ctx, const char *handler, int line)
{
    VBRuntimeWindow *window = (__bridge VBRuntimeWindow *)ctx;
    return [window pauseForBreakWithHandler:handler ? [NSString stringWithUTF8String:handler] : @""
                                       line:line] ? 1 : 0;
}

@implementation VBRuntimeWindow {
    VbForm *_form;
    NSMutableDictionary<NSString *, VBClassicControlView *> *_views;
    NSMutableDictionary<NSString *, NSValue *> *_models;
    NSMutableDictionary<NSString *, VBRuntimeCanvas *> *_canvases;
    NSMutableArray<NSTimer *> *_timers;
    NSString *_propertyValue;
    BOOL _executing;
    NSInteger _focusEventDepth;
    NSInteger _runtimeErrorCount;
    NSInteger _lastRuntimeErrorNumber;
    NSString *_lastRuntimeErrorMessage;
    NSString *_lastRuntimeErrorHandler;
    NSInteger _lastRuntimeErrorLine;
    BOOL _breakRequested;      /* Run > Break: pause before the next statement */
    BOOL _breakStepping;       /* pause again after every statement */
    BOOL _inBreakMode;
    BOOL _breakStopped;
    NSInteger _breakCount;
    NSInteger _breakLine;
    NSString *_breakHandler;
    VBRuntimeBreakAction _breakPending;
    id _breakKeyMonitor;
}

+ (NSString *)displayCaption:(NSString *)caption mnemonicIndex:(NSInteger *)index
{
    return VBCaptionParts(caption, index, NULL);
}

- (instancetype)initWithForm:(VbForm *)form
{
    if (!form || !form->root) return nil;

    CGFloat width = VBTwipsToPoints(vb_form_client_width(form));
    CGFloat height = VBTwipsToPoints(vb_form_client_height(form));
    if (width < 200) width = 320;
    if (height < 120) height = 200;

    int borderStyle = vb_control_get_int(form->root, "BorderStyle", 2);
    NSWindowStyleMask mask = 0;
    if (borderStyle != 0) {
        mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        if (borderStyle != 1 && borderStyle != 3) mask |= NSWindowStyleMaskResizable;
        if (vb_control_get_int(form->root, "MinButton", 1)) mask |= NSWindowStyleMaskMiniaturizable;
    } else {
        mask = NSWindowStyleMaskBorderless;
    }

    VBRuntimeNSWindow *window = [[VBRuntimeNSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                                                   styleMask:mask
                                                                     backing:NSBackingStoreBuffered
                                                                       defer:NO];
    window.title = DisplayProp(form->root, "Caption").length ? DisplayProp(form->root, "Caption")
                                                             : [NSString stringWithUTF8String:vb_form_name(form)];
    window.releasedWhenClosed = NO;
    window.backgroundColor = RuntimeColor(form->root, "BackColor", VBColorFace());

    self = [super initWithWindow:window];
    if (!self) return nil;
    window.host = self;
    _form = form;
    _views = [NSMutableDictionary dictionary];
    _models = [NSMutableDictionary dictionary];
    _canvases = [NSMutableDictionary dictionary];
    _timers = [NSMutableArray array];
    _breakPending = (VBRuntimeBreakAction)-1;
    window.delegate = self;

    VBRuntimeCanvas *canvas = [[VBRuntimeCanvas alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    canvas.control = form->root;
    canvas.isForm = YES;
    canvas.host = self;
    canvas.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = canvas;

    [self buildControls:form->root inView:canvas];
    return self;
}

- (VbControl *)modelForName:(NSString *)name
{
    NSValue *value = _models[name.lowercaseString];
    return value ? (VbControl *)value.pointerValue : NULL;
}

- (VBClassicControlView *)viewForName:(NSString *)name
{
    return _views[name.lowercaseString];
}

- (void)rememberControl:(VbControl *)control view:(VBClassicControlView *)view
{
    NSString *name = control->name ? [NSString stringWithUTF8String:control->name] : @"";
    if (!name.length) return;
    _models[name.lowercaseString] = [NSValue valueWithPointer:control];
    if (view) _views[name.lowercaseString] = view;
}

- (void)buildControls:(VbControl *)parent inView:(NSView *)parentView
{
    for (int i = 0; i < parent->nchildren; i++) {
        VbControl *control = parent->children[i];
        NSString *type = control->type ? [NSString stringWithUTF8String:control->type] : @"";
        if ([type isEqualToString:@"VB.Timer"]) {
            [self rememberControl:control view:nil];
            continue;
        }
        if (!vb_control_visible(control)) {
            [self rememberControl:control view:nil];
            continue;
        }

        CGFloat left = VBTwipsToPoints(vb_control_get_int(control, "Left", 0));
        CGFloat top = VBTwipsToPoints(vb_control_get_int(control, "Top", 0));
        CGFloat width = VBTwipsToPoints(vb_control_get_int(control, "Width", 0));
        CGFloat height = VBTwipsToPoints(vb_control_get_int(control, "Height", 0));
        if (width <= 0) width = 20;
        if (height <= 0) height = 20;
        NSRect frame = NSMakeRect(left, top, width, height);

        if ([type isEqualToString:@"VB.Frame"] || [type isEqualToString:@"VB.PictureBox"]) {
            VBRuntimeCanvas *container = [[VBRuntimeCanvas alloc] initWithFrame:frame];
            container.control = control;
            container.kind = type;
            container.host = self;
            container.enabled = ControlEnabledAtLoad(control);
            [parentView addSubview:container];
            if (control->name) _canvases[[NSString stringWithUTF8String:control->name].lowercaseString] = container;
            [self rememberControl:control view:nil];
            [self buildControls:control inView:container];
            continue;
        }
        if ([type isEqualToString:@"VB.Line"] || [type isEqualToString:@"VB.Shape"]) {
            VBRuntimeCanvas *drawing = [[VBRuntimeCanvas alloc] initWithFrame:frame];
            drawing.control = control;
            drawing.kind = type;
            [parentView addSubview:drawing];
            [self rememberControl:control view:nil];
            continue;
        }

        VBClassicControlView *view = [[VBClassicControlView alloc] initWithControl:control kind:type];
        view.host = self;
        view.frame = frame;
        view.autoresizingMask = NSViewNotSizable;
        [parentView addSubview:view];
        [self rememberControl:control view:view];
        NSString *tip = DisplayProp(control, "ToolTipText");
        if (tip.length) view.toolTip = tip;

        if ([type isEqualToString:@"VB.TextBox"] && vb_control_get_int(control, "PasswordChar", 0)) {
            NSString *password = DisplayProp(control, "PasswordChar");
            if (password.length) {
                view.text = [@"" stringByPaddingToLength:view.text.length withString:password startingAtIndex:0];
            }
        }
    }
}

- (void)appendTabOrderFrom:(VbControl *)parent to:(NSMutableArray<VBClassicControlView *> *)out
{
    VbControl **sorted;
    int count;
    if (!parent || parent->nchildren <= 0) return;
    sorted = (VbControl **)calloc((size_t)parent->nchildren, sizeof(VbControl *));
    if (!sorted) return;
    count = vb_control_sorted_children(parent, sorted, parent->nchildren);
    for (int i = 0; i < count; i++) {
        VbControl *child = sorted[i];
        /* Frames and PictureBoxes are not focusable: their children take their slot. */
        if (vb_control_is_container(child->type)) {
            [self appendTabOrderFrom:child to:out];
            continue;
        }
        {
            NSString *name = child->name ? [NSString stringWithUTF8String:child->name] : @"";
            VBClassicControlView *view = [self viewForName:name];
            if (view && [view canTakeFocus]) [out addObject:view];
        }
    }
    free(sorted);
}

/* Rebuilt on every navigation: Visible/Enabled/TabStop can change while the form runs. */
- (NSArray<VBClassicControlView *> *)currentTabOrder
{
    NSMutableArray<VBClassicControlView *> *views = [NSMutableArray array];
    if (_form && _form->root) [self appendTabOrderFrom:_form->root to:views];
    return views;
}

/* Access-key lookup walks the same TabIndex order, but Labels take part too: they can
   own a mnemonic even though they never receive the focus themselves. */
- (void)appendAccessKeyCandidatesFrom:(VbControl *)parent
                                   to:(NSMutableArray<VBClassicControlView *> *)out
{
    VbControl **sorted;
    int count;
    if (!parent || parent->nchildren <= 0) return;
    sorted = (VbControl **)calloc((size_t)parent->nchildren, sizeof(VbControl *));
    if (!sorted) return;
    count = vb_control_sorted_children(parent, sorted, parent->nchildren);
    for (int i = 0; i < count; i++) {
        VbControl *child = sorted[i];
        if (vb_control_is_container(child->type)) {
            [self appendAccessKeyCandidatesFrom:child to:out];
            continue;
        }
        {
            NSString *name = child->name ? [NSString stringWithUTF8String:child->name] : @"";
            VBClassicControlView *view = [self viewForName:name];
            if (view) [out addObject:view];
        }
    }
    free(sorted);
}

/* Alt+letter: the first control (in tab order) whose caption carries that mnemonic wins,
   exactly like VB6 when two controls share an access key. */
/* Only controls whose caption is user-visible carry an access key in VB6. */
static BOOL VBKindHasAccessKey(NSString *kind)
{
    return [kind isEqualToString:@"VB.Label"] || [kind isEqualToString:@"VB.CommandButton"] ||
           [kind isEqualToString:@"VB.CheckBox"] || [kind isEqualToString:@"VB.OptionButton"];
}

- (BOOL)activateAccessKey:(NSString *)character
{
    NSMutableArray<VBClassicControlView *> *candidates = [NSMutableArray array];
    if (!character.length) return NO;
    if (_form && _form->root) [self appendAccessKeyCandidatesFrom:_form->root to:candidates];
    for (NSUInteger i = 0; i < candidates.count; i++) {
        VBClassicControlView *view = candidates[i];
        NSInteger index = -1;
        unichar mnemonic = 0;
        NSString *mnemonicText;
        if (view.hidden || view.isHiddenOrHasHiddenAncestor) continue;
        if (![view isEffectivelyEnabled]) continue;
        if (!VBKindHasAccessKey(view.kind)) continue;
        if ([view.kind isEqualToString:@"VB.Label"] &&
            vb_control_get_int(view.control, "UseMnemonic", -1) == 0) continue;
        VBCaptionParts(view.text, &index, &mnemonic);
        if (index < 0) continue;
        mnemonicText = [NSString stringWithCharacters:&mnemonic length:1];
        if ([mnemonicText caseInsensitiveCompare:character] != NSOrderedSame) continue;
        if ([view.kind isEqualToString:@"VB.Label"]) {
            /* A Label cannot take the focus: VB6 hands it to the next control in tab order. */
            for (NSUInteger j = i + 1; j < candidates.count; j++) {
                if ([candidates[j] canTakeFocus] &&
                    [self.window makeFirstResponder:candidates[j]]) break;
            }
            return YES;
        }
        if (![view isFocusableKind]) continue;
        [self.window makeFirstResponder:view];
        [view activateFromAccessKey];
        return YES;
    }
    return NO;
}

- (BOOL)activateAccessKeyForEvent:(NSEvent *)event
{
    NSString *characters;
    if (!(event.modifierFlags & NSEventModifierFlagOption)) return NO;
    /* charactersIgnoringModifiers keeps the letter instead of the Option+key glyph. */
    characters = event.charactersIgnoringModifiers;
    if (!characters.length) return NO;
    return [self activateAccessKey:characters];
}

- (NSArray<NSString *> *)tabOrderControlNames
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (VBClassicControlView *view in [self currentTabOrder]) {
        if (view.control && view.control->name) {
            [names addObject:[NSString stringWithUTF8String:view.control->name]];
        }
    }
    return names;
}

- (NSString *)focusedControlName
{
    /* Reports the control that really has the focus, even when TabStop = False keeps it
       out of the Tab cycle (SetFocus can still target it). */
    NSResponder *responder = self.window.firstResponder;
    if (![responder isKindOfClass:[VBClassicControlView class]]) return @"";
    {
        VbControl *control = ((VBClassicControlView *)responder).control;
        return control && control->name ? [NSString stringWithUTF8String:control->name] : @"";
    }
}

- (BOOL)focusNextControlBackwards:(BOOL)backwards
{
    NSArray<VBClassicControlView *> *order = [self currentTabOrder];
    NSInteger count = (NSInteger)order.count;
    NSResponder *responder = self.window.firstResponder;
    NSInteger index = -1;
    if (count == 0) return NO;
    for (NSInteger i = 0; i < count; i++) {
        if ((NSResponder *)order[(NSUInteger)i] == responder) {
            index = i;
            break;
        }
    }
    for (NSInteger attempt = 0; attempt < count; attempt++) {
        NSInteger candidate;
        if (index < 0) {
            candidate = backwards ? count - 1 : 0;
        } else {
            candidate = (index + (backwards ? -1 : 1) + count) % count;
        }
        index = candidate;
        if ([self.window makeFirstResponder:order[(NSUInteger)candidate]]) return YES;
    }
    return NO;
}

- (BOOL)focusInitialControl
{
    for (VBClassicControlView *view in [self currentTabOrder]) {
        if ([self.window makeFirstResponder:view]) return YES;
    }
    return NO;
}

/* If the focused control (or a child of a hidden container) can no longer take
   focus, move on instead of trapping the keyboard there. */
- (void)moveFocusAwayFrom:(NSView *)view
{
    NSResponder *responder = self.window.firstResponder;
    if (!view || !responder) return;
    if (responder != view) {
        if (![responder isKindOfClass:[NSView class]]) return;
        if (![(NSView *)responder isDescendantOf:view]) return;
    }
    [self focusNextControlBackwards:NO];
}

- (BOOL)sendTabKeyBackwards:(BOOL)backwards
{
    NSResponder *responder = self.window.firstResponder;
    NSString *before = [self focusedControlName];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:(backwards ? NSEventModifierFlagShift : 0)
                                     timestamp:0
                                  windowNumber:self.window.windowNumber
                                       context:nil
                                    characters:@"\t"
                       charactersIgnoringModifiers:@"\t"
                                     isARepeat:NO
                                       keyCode:48];
    [responder keyDown:event];
    return ![[self focusedControlName] isEqualToString:before];
}

- (void)classicControl:(VBClassicControlView *)view requestsTabBackwards:(BOOL)backwards
{
    (void)view;
    [self focusNextControlBackwards:backwards];
}

- (void)classicControl:(VBClassicControlView *)view fireEvent:(NSString *)event
{
    if (!view.control || !event.length) return;
    NSString *name = view.control->name ? [NSString stringWithUTF8String:view.control->name] : @"";
    if (!name.length) return;
    [self runHandler:[NSString stringWithFormat:@"%@_%@", name, event]];
}

- (void)classicControl:(VBClassicControlView *)view fireFocusEvent:(NSString *)event
{
    if (!view.control || !event.length) return;
    NSString *name = view.control->name ? [NSString stringWithUTF8String:view.control->name] : @"";
    if (!name.length) return;
    [self runFocusHandler:[NSString stringWithFormat:@"%@_%@", name, event]];
}

/* <Control>.SetFocus: TabStop does not block it in VB6, only the Tab cycle does. */
- (BOOL)setFocusToControl:(NSString *)controlName
{
    VBClassicControlView *view = [self viewForName:controlName];
    if (!view) {
        fprintf(stderr, "[runtime SetFocus] no control named %s\n", controlName.UTF8String);
        return NO;
    }
    if (![view canReceiveFocus]) {
        fprintf(stderr, "[runtime SetFocus] %s cannot take the focus (%s)\n",
                controlName.UTF8String,
                [view isFocusableKind] ? "disabled or hidden" : "not a focusable control");
        return NO;
    }
    return [self.window makeFirstResponder:view];
}

- (VbForm *)form { return _form; }

- (NSInteger)runtimeErrorCount { return _runtimeErrorCount; }
- (NSInteger)lastRuntimeErrorNumber { return _lastRuntimeErrorNumber; }
- (NSString *)lastRuntimeErrorMessage { return _lastRuntimeErrorMessage ?: @""; }
- (NSString *)lastRuntimeErrorHandler { return _lastRuntimeErrorHandler ?: @""; }
- (NSInteger)lastRuntimeErrorLine { return _lastRuntimeErrorLine; }

/* VB6 unhandled run-time error: modal End/Debug dialog. End stops the program (the
   form closes). Debug enters break mode on the failing statement: the interpreter keeps
   the procedure alive and the user steps through the rest (F8) or continues (F5). When
   break mode is unavailable (tests, automation) execution stops at the error. */
- (int)presentRuntimeError:(NSInteger)number
                   message:(NSString *)message
                   handler:(NSString *)handler
                      line:(NSInteger)line
{
    NSString *text = [NSString stringWithFormat:@"Run-time error '%ld':\n\n%@",
                      (long)number, message ?: @""];
    NSInteger choice = VB_RUNTIME_ERROR_END;
    _runtimeErrorCount++;
    _lastRuntimeErrorNumber = number;
    _lastRuntimeErrorMessage = [text copy];
    _lastRuntimeErrorHandler = [handler copy];
    _lastRuntimeErrorLine = line;
    if (self.suppressDialogs) {
        choice = self.suppressedErrorResult != 0 ? self.suppressedErrorResult : VB_RUNTIME_ERROR_END;
        fprintf(stderr, "[runtime error %ld] %s (%s line %ld) -> %s\n",
                (long)number, message.UTF8String, handler.UTF8String, (long)line,
                choice == VB_RUNTIME_ERROR_DEBUG ? "Debug" : "End");
    } else {
        choice = ShowRuntimeErrorDialog(self.window.title, text) == 2
                     ? VB_RUNTIME_ERROR_DEBUG : VB_RUNTIME_ERROR_END;
    }
    if (choice == VB_RUNTIME_ERROR_DEBUG && [self breakModeAvailable]) {
        /* The interpreter calls the break hook on this same line, so the code window
           highlights the failing statement and the user decides what happens next. */
        fprintf(stderr, "[runtime] Debug at %s line %ld\n", handler.UTF8String, (long)line);
        _breakRequested = YES;
        _breakStepping = YES;
        return VB_RUNTIME_ERROR_DEBUG;
    }
    if (choice == VB_RUNTIME_ERROR_DEBUG) {
        fprintf(stderr, "[runtime] Debug at %s line %ld (break mode unavailable)\n",
                handler.UTF8String, (long)line);
        [self stopTimers];
        if ([self.delegate respondsToSelector:@selector(runtimeWindow:didRequestDebugForHandler:line:)]) {
            [self.delegate runtimeWindow:self didRequestDebugForHandler:handler line:line];
        }
        return VB_RUNTIME_ERROR_END;
    }
    /* End: the program stops, like the VB6 Run > End command. */
    dispatch_async(dispatch_get_main_queue(), ^{ [self.window close]; });
    return VB_RUNTIME_ERROR_END;
}

#pragma mark - Break mode

- (BOOL)isInBreakMode { return _inBreakMode; }
- (NSString *)breakHandler { return _breakHandler ?: @""; }
- (NSInteger)breakLine { return _breakLine; }
- (NSInteger)breakCount { return _breakCount; }

/* Break mode needs a UI loop to wait in: the interactive app always has one, tests and
   the CLI never do unless they provide a breakAction block. */
- (BOOL)breakModeAvailable { return self.breakAction != nil || !self.suppressDialogs; }

- (void)requestBreak
{
    if (!_form) return;
    _breakRequested = YES;
    _breakStopped = NO;
    fprintf(stderr, "[runtime] break requested\n");
}

- (void)breakContinue { [self resolveBreakAction:VBRuntimeBreakContinue]; }
- (void)breakStep { [self resolveBreakAction:VBRuntimeBreakStep]; }
- (void)breakStop { [self resolveBreakAction:VBRuntimeBreakStop]; }

+ (NSInteger)breakActionForKeyCode:(unsigned short)keyCode shift:(BOOL)shift
{
    switch (keyCode) {
        case 96: return shift ? VBRuntimeBreakStop : VBRuntimeBreakContinue; /* F5 */
        case 100: return VBRuntimeBreakStep;                                 /* F8 */
        case 109: return VBRuntimeBreakStep;                                 /* F10 */
        default: return -1;
    }
}

- (void)resolveBreakAction:(VBRuntimeBreakAction)action
{
    _breakPending = action;
    if (action == VBRuntimeBreakStop) _breakStopped = YES;
}

/* Called by the interpreter before every executable statement. Returns YES when the
   procedure must stop. A break requested from the IDE pauses here; in break mode every
   statement is offered again, so a step ends on the next one. */
- (BOOL)pauseForBreakWithHandler:(NSString *)handler line:(NSInteger)line
{
    BOOL atBreakpoint = self.breakpointLines != nil &&
                        [self.breakpointLines containsIndex:(NSUInteger)line];
    if (_breakStopped) return YES;
    if (!atBreakpoint && !_breakRequested && !_breakStepping && !_inBreakMode) return NO;

    _breakRequested = NO;
    _inBreakMode = YES;
    _breakLine = line;
    _breakHandler = [handler copy] ?: @"";
    _breakCount++;
    [self stopTimers];
    fprintf(stderr, "[runtime] %s at %s line %ld\n",
            atBreakpoint ? "breakpoint" : "break", handler.UTF8String, (long)line);
    if ([self.delegate respondsToSelector:@selector(runtimeWindow:didBreakAtHandler:line:)]) {
        [self.delegate runtimeWindow:self didBreakAtHandler:handler line:line];
    }

    VBRuntimeBreakAction action;
    if (self.breakAction) {
        action = self.breakAction(self, handler, line);
    } else {
        action = [self waitForBreakAction];
    }

    if (action == VBRuntimeBreakStop) {
        _breakStopped = YES;
        _breakStepping = NO;
        [self leaveBreakMode];
        return YES;
    }
    _breakStepping = (action == VBRuntimeBreakStep);
    if (!_breakStepping) [self leaveBreakMode];
    return NO;
}

/* Nested event loop while paused: the IDE and the code window stay live, and the F5/F8
   keys are swallowed here so the editor does not receive them. */
- (VBRuntimeBreakAction)waitForBreakAction
{
    __weak VBRuntimeWindow *weakSelf = self;
    _breakPending = (VBRuntimeBreakAction)-1;
    _breakKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                            handler:^NSEvent *(NSEvent *event) {
        VBRuntimeWindow *window = weakSelf;
        if (!window) return event;
        NSInteger action = [VBRuntimeWindow breakActionForKeyCode:event.keyCode
                                                            shift:(event.modifierFlags & NSEventModifierFlagShift) != 0];
        if (action < 0) return event;
        [window resolveBreakAction:(VBRuntimeBreakAction)action];
        return nil;
    }];
    while (_breakPending < 0 && self.window.isVisible) {
        @autoreleasepool {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
    }
    if (_breakKeyMonitor) {
        [NSEvent removeMonitor:_breakKeyMonitor];
        _breakKeyMonitor = nil;
    }
    /* The runtime window was closed while paused: stop the procedure. */
    if (_breakPending < 0) return VBRuntimeBreakStop;
    return _breakPending;
}

- (void)leaveBreakMode
{
    if (!_inBreakMode) return;
    _inBreakMode = NO;
    if ([self.delegate respondsToSelector:@selector(runtimeWindowDidLeaveBreakMode:)]) {
        [self.delegate runtimeWindowDidLeaveBreakMode:self];
    }
}

- (void)stopTimers
{
    for (NSTimer *timer in _timers) [timer invalidate];
    [_timers removeAllObjects];
}

- (void)startRuntime
{
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    /* VB6 runs Form_Load before the first control receives the focus (GotFocus). */
    [self runHandler:@"Form_Load"];
    [self focusInitialControl];
    [self scheduleTimers:_form->root];
}

- (void)scheduleTimers:(VbControl *)parent
{
    for (int i = 0; i < parent->nchildren; i++) {
        VbControl *control = parent->children[i];
        NSString *type = control->type ? [NSString stringWithUTF8String:control->type] : @"";
        if ([type isEqualToString:@"VB.Timer"]) {
            int interval = vb_control_get_int(control, "Interval", 0);
            if (interval > 0) {
                NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval / 1000.0
                                                                  target:self
                                                                selector:@selector(timerFired:)
                                                                userInfo:[NSString stringWithUTF8String:control->name]
                                                                 repeats:YES];
                [_timers addObject:timer];
            }
        }
        [self scheduleTimers:control];
    }
}

- (void)timerFired:(NSTimer *)timer
{
    NSString *name = timer.userInfo;
    [self runHandler:[NSString stringWithFormat:@"%@_Timer", name]];
}

- (const char *)propertyForControl:(NSString *)controlName property:(NSString *)property
{
    if (!property.length) return NULL;
    BOOL isForm = controlName.length == 0 ||
                  [controlName caseInsensitiveCompare:@"Me"] == NSOrderedSame;
    VbControl *model = isForm ? _form->root : [self modelForName:controlName];
    VBClassicControlView *view = isForm ? nil : [self viewForName:controlName];

    if ([property isEqualToString:@"Name"]) {
        if (!model || !model->name) return "";
        _propertyValue = [NSString stringWithUTF8String:model->name];
        return _propertyValue.UTF8String;
    }
    if ([property isEqualToString:@"Caption"] || [property isEqualToString:@"Text"]) {
        if (isForm) {
            _propertyValue = self.window.title;
            return _propertyValue.UTF8String;
        }
        if (view) {
            _propertyValue = view.text;
            return _propertyValue.UTF8String;
        }
    }
    if ([property isEqualToString:@"Value"]) {
        if (view) return view.value ? "-1" : "0";
    }
    if ([property isEqualToString:@"Visible"]) {
        if (view) return view.hidden ? "0" : "-1";
        {
            VBRuntimeCanvas *canvas = _canvases[controlName.lowercaseString];
            if (canvas) return canvas.hidden ? "0" : "-1";
        }
    }
    if ([property isEqualToString:@"TabStop"]) {
        if (view) return view.tabStop ? "-1" : "0";
    }
    if ([property isEqualToString:@"Enabled"]) {
        if (view) return view.enabled ? "-1" : "0";
        {
            VBRuntimeCanvas *canvas = _canvases[controlName.lowercaseString];
            if (canvas) return canvas.enabled ? "-1" : "0";
        }
    }
    if (model) {
        char *value = vb_control_get_display(model, property.UTF8String);
        if (value) {
            /* Keep the string alive until the next read: the caller gets a borrowed
               pointer, and the temporary would otherwise be released here. */
            _propertyValue = [NSString stringWithUTF8String:value];
            free(value);
            return _propertyValue.UTF8String;
        }
    }
    return NULL;
}

- (NSString *)propertyValueForControl:(NSString *)controlName property:(NSString *)property
{
    const char *value = [self propertyForControl:controlName property:property];
    return value ? [NSString stringWithUTF8String:value] : @"";
}

/* Dispatches a key event to the current first responder, so the self test exercises
   the same path as a real Alt+letter (including the control-level interception). */
- (NSEvent *)testKeyEvent:(NSString *)characters optionDown:(BOOL)optionDown
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:(optionDown ? NSEventModifierFlagOption : 0)
                           timestamp:0
                        windowNumber:self.window.windowNumber
                             context:nil
                          characters:characters
             charactersIgnoringModifiers:characters
                           isARepeat:NO
                             keyCode:0];
}

/* Goes through NSApplication, so AppKit's own key-equivalent search and first-responder
   dispatch decide which path handles the event. */
- (void)dispatchTestKeyEvent:(NSString *)characters optionDown:(BOOL)optionDown
{
    [NSApp sendEvent:[self testKeyEvent:characters optionDown:optionDown]];
}

- (void)sendTestKeyEvent:(NSString *)characters optionDown:(BOOL)optionDown
{
    NSEvent *event = [self testKeyEvent:characters optionDown:optionDown];
    NSResponder *responder = self.window.firstResponder;
    if ([responder isKindOfClass:[NSView class]]) {
        [(NSView *)responder keyDown:event];
        return;
    }
    /* No view has the focus: the window itself is the first responder. */
    [self.window keyDown:event];
}

- (void)setProperty:(NSString *)property forControl:(NSString *)controlName value:(NSString *)value
{
    if (!property.length) return;
    BOOL isForm = controlName.length == 0 ||
                  [controlName caseInsensitiveCompare:@"Me"] == NSOrderedSame;
    if (isForm) {
        if ([property isEqualToString:@"Caption"]) {
            self.window.title = value.length ? value : self.window.title;
        }
        return;
    }
    VBClassicControlView *view = [self viewForName:controlName];
    if (!view) {
        VBRuntimeCanvas *canvas = _canvases[controlName.lowercaseString];
        if (!canvas) return;
        if ([property isEqualToString:@"Visible"]) {
            canvas.hidden = !RuntimeBoolValue(value);
            if (canvas.hidden) [self moveFocusAwayFrom:canvas];
        } else if ([property isEqualToString:@"Enabled"]) {
            /* Disables the whole subtree: children keep their own Enabled flag. */
            canvas.enabled = RuntimeBoolValue(value);
            InvalidateSubtree(canvas);
            if (!canvas.enabled) [self moveFocusAwayFrom:canvas];
        }
        return;
    }

    if ([property isEqualToString:@"Caption"] || [property isEqualToString:@"Text"]) {
        view.text = value ?: @"";
        view.caret = (NSInteger)view.text.length;
        [view setNeedsDisplay:YES];
        return;
    }
    if ([property isEqualToString:@"Value"]) {
        view.value = value.intValue != 0 ? -1 : 0;
        [view setNeedsDisplay:YES];
        return;
    }
    if ([property isEqualToString:@"Visible"]) {
        view.hidden = !RuntimeBoolValue(value);
        if (view.hidden) [self moveFocusAwayFrom:view];
        return;
    }
    if ([property isEqualToString:@"Enabled"]) {
        view.enabled = RuntimeBoolValue(value);
        [view setNeedsDisplay:YES];
        if (!view.enabled) [self moveFocusAwayFrom:view];
        return;
    }
    if ([property isEqualToString:@"TabStop"]) {
        view.tabStop = RuntimeBoolValue(value);
        if (!view.tabStop) [self moveFocusAwayFrom:view];
        return;
    }
}

- (void)runEventHandler:(NSString *)handler
{
    [self runHandler:handler];
}

- (void)runHandler:(NSString *)handler
{
    if (!_form || _executing) return;
    VbRuntimeHost host;
    memset(&host, 0, sizeof(host));
    host.ctx = (__bridge void *)self;
    host.get_prop = RuntimeGetProp;
    host.set_prop = RuntimeSetProp;
    host.msgbox = RuntimeMsgBox;
    host.close = RuntimeClose;
    host.inputbox = RuntimeInputBox;
    host.confirm = RuntimeConfirm;
    host.set_focus = RuntimeSetFocus;
    host.runtime_error = RuntimeError;
    /* Only a handler the user started can be stepped through: focus events fired by
       SetFocus run atomically, since there is no call stack to step in and out of. */
    host.break_hook = RuntimeBreak;
    _executing = YES;
    _focusEventDepth = 0;
    vb_form_run_event(_form, handler.UTF8String, &host);
    _executing = NO;
    _focusEventDepth = 0;
    _breakRequested = NO;
    _breakStepping = NO;
    _breakStopped = NO;
    _breakPending = (VBRuntimeBreakAction)-1;
    [self leaveBreakMode];
}

/* GotFocus / LostFocus can be triggered by SetFocus inside another handler. VB6 runs
   them at that point; a bounded nesting reproduces that without recursing forever when
   two handlers keep moving the focus back and forth. */
- (void)runFocusHandler:(NSString *)handler
{
    if (!_form || !handler.length) return;
    if (!_executing) {
        [self runHandler:handler];
        return;
    }
    if (_focusEventDepth >= 8) {
        fprintf(stderr, "[runtime] focus events nested too deeply at %s\n", handler.UTF8String);
        return;
    }
    _focusEventDepth++;
    {
        VbRuntimeHost host;
        memset(&host, 0, sizeof(host));
        host.ctx = (__bridge void *)self;
        host.get_prop = RuntimeGetProp;
        host.set_prop = RuntimeSetProp;
        host.msgbox = RuntimeMsgBox;
        host.close = RuntimeClose;
        host.inputbox = RuntimeInputBox;
        host.confirm = RuntimeConfirm;
        host.set_focus = RuntimeSetFocus;
        host.runtime_error = RuntimeError;
        vb_form_run_event(_form, handler.UTF8String, &host);
    }
    _focusEventDepth--;
}

- (void)windowWillClose:(NSNotification *)notification
{
    (void)notification;
    /* Closing the form while paused ends the procedure instead of leaving the
       interpreter blocked in the break loop. */
    _breakStopped = YES;
    if (_breakPending < 0) _breakPending = VBRuntimeBreakStop;
    [self stopTimers];
    if (self.delegate) [self.delegate runtimeWindowDidClose:self];
}

@end
