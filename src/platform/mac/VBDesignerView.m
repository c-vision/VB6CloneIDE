#import "VBDesignerView.h"
#import "VBTheme.h"
#include "core/vb_util.h"

#include <limits.h>
#include <math.h>
#include <stdlib.h>

static NSColor *workspaceColor(void)
{
    return [NSColor colorWithSRGBRed:0.50 green:0.50 blue:0.50 alpha:1.0];
}

static int snap15(int value)
{
    return (int)(floor((double)value / 15.0 + 0.5) * 15.0);
}

static int absolute_left(VbControl *control, VbControl *root)
{
    int total = 0;
    VbControl *cursor = control;
    while (cursor && cursor != root) {
        total += vb_control_get_int(cursor, "Left", 0);
        cursor = cursor->parent;
    }
    return total;
}

static int absolute_top(VbControl *control, VbControl *root)
{
    int total = 0;
    VbControl *cursor = control;
    while (cursor && cursor != root) {
        total += vb_control_get_int(cursor, "Top", 0);
        cursor = cursor->parent;
    }
    return total;
}

static void move_to_absolute_left(VbControl *control, VbControl *root, int target)
{
    int delta = target - absolute_left(control, root);
    if (delta == 0) return;
    vb_control_set_int(control, "Left", vb_control_get_int(control, "Left", 0) + delta);
}

static void move_to_absolute_top(VbControl *control, VbControl *root, int target)
{
    int delta = target - absolute_top(control, root);
    if (delta == 0) return;
    vb_control_set_int(control, "Top", vb_control_get_int(control, "Top", 0) + delta);
}

static void drawTextInRect(NSString *text, NSRect rect, NSColor *color, NSTextAlignment align,
                           NSFont *font, BOOL centeredVertically, BOOL wrap)
{
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = align;
    style.lineBreakMode = wrap ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{
        NSFontAttributeName: font ?: VBFontUI(),
        NSForegroundColorAttributeName: color ?: VBColorText(),
        NSParagraphStyleAttributeName: style
    };
    NSRect target = rect;
    if (centeredVertically) {
        NSSize size = [text sizeWithAttributes:attrs];
        CGFloat y = rect.origin.y + (rect.size.height - MIN(size.height, rect.size.height)) / 2.0;
        target.origin.y = y;
        target.size.height = MIN(size.height, rect.size.height);
    }
    [text drawInRect:target withAttributes:attrs];
}

static NSString *controlDisplay(VbControl *control, const char *key)
{
    char *display;
    NSString *text;
    if (!control) return @"";
    display = vb_control_get_display(control, key);
    if (!display) return @"";
    text = [NSString stringWithUTF8String:display];
    free(display);
    return text ?: @"";
}

static NSColor *controlBackColor(VbControl *control, NSColor *fallback)
{
    const char *value = vb_control_get(control, "BackColor");
    int r, g, b;
    if (!value) return fallback;
    if (!vb_color_from_value(value, &r, &g, &b)) return fallback;
    if (r > 0xF0 && g > 0xF0 && b > 0xF0) return VBColorWindow();
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

@interface VBDesignerView ()
@property (nonatomic) NSPoint dragMouse;
@end

@implementation VBDesignerView {
    int _mode; // 0 idle, 1 move, 2 resize, 3 create, 4 marquee, 5 multi-resize
    NSRect _createRect;
    NSMutableArray<NSValue *> *_selection;
    NSMutableArray<NSValue *> *_dragFrames;
    NSMutableArray<NSValue *> *_dragLeftTops;
    NSMutableArray<NSValue *> *_dragSizes;
    NSRect _dragRect;
    NSInteger _resizeHandle;
    NSRect _marqueeRect;
    NSPoint _marqueeStart;
    BOOL _marqueeAdditive;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.wantsLayer = NO;
    _selection = [NSMutableArray array];
    _dragFrames = [NSMutableArray array];
    _dragLeftTops = [NSMutableArray array];
    _dragSizes = [NSMutableArray array];
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomesFirstResponderOnMouseDown { return YES; }

- (void)setForm:(VbForm *)form
{
    _form = form;
    _selected = form ? form->root : NULL;
    [_selection removeAllObjects];
    [_dragFrames removeAllObjects];
    self.pendingTool = nil;
    [self setNeedsDisplay:YES];
}

- (void)refresh
{
    [self setNeedsDisplay:YES];
}

- (NSUInteger)selectionCount
{
    return _selection.count;
}

- (BOOL)isSelectedControl:(VbControl *)control
{
    if (!control) return NO;
    for (NSValue *value in _selection) {
        if (value.pointerValue == control) return YES;
    }
    return NO;
}

- (void)clearSelectionList
{
    [_selection removeAllObjects];
}

- (void)setSelectionToControl:(VbControl *)control notify:(BOOL)notify
{
    [_selection removeAllObjects];
    if (control && self.form && control != self.form->root) {
        [_selection addObject:[NSValue valueWithPointer:control]];
    }
    _selected = control ? control : (self.form ? self.form->root : NULL);
    if (notify && self.delegate) [self.delegate designerSelectionChanged:self];
    [self setNeedsDisplay:YES];
}

- (void)toggleControlInSelection:(VbControl *)control
{
    if (!control || !self.form || control == self.form->root) return;
    if ([self isSelectedControl:control]) {
        for (NSUInteger i = 0; i < _selection.count; i++) {
            if ((VbControl *)_selection[i].pointerValue == control) {
                [_selection removeObjectAtIndex:i];
                break;
            }
        }
        if (_selection.count > 0) _selected = (VbControl *)_selection.lastObject.pointerValue;
        else _selected = self.form->root;
    } else {
        [_selection addObject:[NSValue valueWithPointer:control]];
        _selected = control;
    }
    if (self.delegate) [self.delegate designerSelectionChanged:self];
    [self setNeedsDisplay:YES];
}

- (void)selectControl:(VbControl *)control
{
    [self setSelectionToControl:control notify:YES];
}

- (NSRect)selectionRect
{
    NSRect rect = NSZeroRect;
    BOOL first = YES;
    for (NSValue *value in _selection) {
        NSRect r = [self rectForControl:(VbControl *)value.pointerValue];
        if (first) { rect = r; first = NO; }
        else rect = NSUnionRect(rect, r);
    }
    return rect;
}

- (BOOL)selectionSharesParent
{
    VbControl *parent = NULL;
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        if (!parent) parent = control->parent;
        else if (control->parent != parent) return NO;
    }
    return _selection.count > 0;
}

- (NSInteger)handleAtPoint:(NSPoint)point rect:(NSRect)rect
{
    if (NSIsEmptyRect(rect)) return -1;
    CGFloat xs[3] = {NSMinX(rect), NSMidX(rect), NSMaxX(rect)};
    CGFloat ys[3] = {NSMinY(rect), NSMidY(rect), NSMaxY(rect)};
    for (int iy = 0; iy < 3; iy++) {
        for (int ix = 0; ix < 3; ix++) {
            if (ix == 1 && iy == 1) continue;
            NSRect handle = NSMakeRect(xs[ix] - 5, ys[iy] - 5, 10, 10);
            if (NSPointInRect(point, handle)) return iy * 3 + ix;
        }
    }
    return -1;
}

- (BOOL)isDescendant:(VbControl *)control of:(VbControl *)ancestor
{
    VbControl *parent = control ? control->parent : NULL;
    while (parent) {
        if (parent == ancestor) return YES;
        parent = parent->parent;
    }
    return NO;
}

- (void)captureDragState
{
    [_dragFrames removeAllObjects];
    [_dragLeftTops removeAllObjects];
    [_dragSizes removeAllObjects];
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        [_dragFrames addObject:[NSValue valueWithRect:[self rectForControl:control]]];
        NSPoint leftTop = NSMakePoint(vb_control_get_int(control, "Left", 0),
                                      vb_control_get_int(control, "Top", 0));
        [_dragLeftTops addObject:[NSValue valueWithPoint:leftTop]];
        NSSize size = NSMakeSize(vb_control_get_int(control, "Width", 0),
                                 vb_control_get_int(control, "Height", 0));
        [_dragSizes addObject:[NSValue valueWithSize:size]];
    }
}

- (NSPoint)formOrigin
{
    CGFloat fw;
    CGFloat fh;
    CGFloat totalH;
    CGFloat ox;
    CGFloat oy;
    if (!self.form) return NSMakePoint(20, 20);
    fw = VBTwipsToPoints(vb_form_client_width(self.form));
    fh = VBTwipsToPoints(vb_form_client_height(self.form));
    totalH = fh + VB_TITLE_HEIGHT;
    ox = floor((self.bounds.size.width - fw) / 2.0);
    oy = floor((self.bounds.size.height - totalH) / 2.0);
    if (ox < 20) ox = 20;
    if (oy < 20) oy = 20;
    return NSMakePoint(ox, oy);
}

- (NSRect)clientRect
{
    NSPoint origin = [self formOrigin];
    return NSMakeRect(origin.x, origin.y + VB_TITLE_HEIGHT,
                      VBTwipsToPoints(vb_form_client_width(self.form)),
                      VBTwipsToPoints(vb_form_client_height(self.form)));
}

- (NSRect)rectForControl:(VbControl *)control
{
    VbControl *chain[64];
    int count = 0;
    int x = 0;
    int y = 0;
    int i;
    NSRect client;
    if (!control || !self.form) return NSZeroRect;
    while (control && count < 64) {
        chain[count++] = control;
        if (control == self.form->root) break;
        control = control->parent;
    }
    client = [self clientRect];
    for (i = count - 1; i >= 0; i--) {
        if (chain[i] == self.form->root) continue;
        x += vb_control_get_int(chain[i], "Left", 0);
        y += vb_control_get_int(chain[i], "Top", 0);
    }
    control = chain[0];
    {
        int left = vb_control_get_int(control, "Left", 0);
        int top = vb_control_get_int(control, "Top", 0);
        int width = vb_control_get_int(control, "Width", 0);
        int height = vb_control_get_int(control, "Height", 0);
        (void)left; (void)top;
        return NSMakeRect(client.origin.x + VBTwipsToPoints(x),
                          client.origin.y + VBTwipsToPoints(y),
                          VBTwipsToPoints(width), VBTwipsToPoints(height));
    }
}

- (NSRect)absoluteRectForControl:(VbControl *)control
{
    return [self rectForControl:control];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [workspaceColor() setFill];
    NSRectFill(self.bounds);

    if (!self.form || !self.form->root) {
        NSDictionary *titleAttrs = @{
            NSFontAttributeName: VBFontUIBold(),
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.85]
        };
        NSDictionary *subAttrs = @{
            NSFontAttributeName: VBFontUISmall(),
            NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.6]
        };
        NSString *title = @"No form open";
        NSString *sub = @"Choose a form in the Project Explorer";
        NSSize titleSize = [title sizeWithAttributes:titleAttrs];
        NSSize subSize = [sub sizeWithAttributes:subAttrs];
        [title drawAtPoint:NSMakePoint(NSMidX(self.bounds) - titleSize.width / 2.0,
                                      NSMidY(self.bounds) - titleSize.height - 2)
            withAttributes:titleAttrs];
        [sub drawAtPoint:NSMakePoint(NSMidX(self.bounds) - subSize.width / 2.0,
                                    NSMidY(self.bounds) + 4)
          withAttributes:subAttrs];
        return;
    }

    NSRect client = [self clientRect];
    NSPoint origin = [self formOrigin];
    NSRect formRect = NSMakeRect(origin.x, origin.y, client.size.width, client.size.height + VB_TITLE_HEIGHT);

    [VBColorFace() setFill];
    NSRectFill(formRect);
    VBDrawTitleBar(NSMakeRect(formRect.origin.x, formRect.origin.y,
                              formRect.size.width, VB_TITLE_HEIGHT),
                   controlDisplay(self.form->root, "Caption"), YES, YES, NO, NO);
    [[VBColorDarkShadow() colorWithAlphaComponent:0.9] setStroke];
    {
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(formRect, 0.5, 0.5)];
        [border setLineWidth:1];
        [border stroke];
    }

    {
        NSColor *back = controlBackColor(self.form->root, VBColorFace());
        [back setFill];
        NSRectFill(client);
    }

    {
        [[VBColorGrid() colorWithAlphaComponent:0.75] setFill];
        int maxX = vb_form_client_width(self.form);
        int maxY = vb_form_client_height(self.form);
        for (int gy = 0; gy <= maxY; gy += 60) {
            for (int gx = 0; gx <= maxX; gx += 60) {
                NSRectFill(NSMakeRect(floor(client.origin.x + VBTwipsToPoints(gx)),
                                      floor(client.origin.y + VBTwipsToPoints(gy)), 1, 1));
            }
        }
    }

    /* VB6 clips controls at the form client edge while designing */
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:client];
    for (int i = 0; i < self.form->root->nchildren; i++) {
        [self drawControl:self.form->root->children[i] origin:client.origin];
    }
    [NSGraphicsContext restoreGraphicsState];

    if (_mode == 3 && _createRect.size.width > 0 && _createRect.size.height > 0) {
        NSBezierPath *dash = [NSBezierPath bezierPathWithRect:_createRect];
        CGFloat pattern[2] = {2, 2};
        [dash setLineDash:pattern count:2 phase:0];
        [VBColorText() setStroke];
        [dash setLineWidth:1];
        [dash stroke];
    }

    if (_selection.count > 1) {
        for (NSValue *value in _selection) {
            NSRect rect = [self rectForControl:(VbControl *)value.pointerValue];
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 0.5, 0.5)];
            CGFloat pattern[2] = {2, 2};
            [path setLineDash:pattern count:2 phase:0];
            [path setLineWidth:1];
            [VBColorText() setStroke];
            [path stroke];
        }
        [self drawHandlesForRect:[self selectionRect]];
    } else if (self.selected && self.selected != self.form->root) {
        NSRect selectedRect = [self rectForControl:self.selected];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(selectedRect, 0.5, 0.5)];
        CGFloat pattern[2] = {2, 2};
        [path setLineDash:pattern count:2 phase:0];
        [path setLineWidth:1];
        [VBColorText() setStroke];
        [path stroke];
        [self drawHandlesForRect:selectedRect];
    }

    if (_mode == 4 && _marqueeRect.size.width >= 1 && _marqueeRect.size.height >= 1) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:_marqueeRect];
        CGFloat pattern[2] = {2, 2};
        [path setLineDash:pattern count:2 phase:0];
        [path setLineWidth:1];
        [VBColorText() setStroke];
        [path stroke];
    }
}

- (void)drawHandlesForRect:(NSRect)rect
{
    if (NSIsEmptyRect(rect)) return;
    CGFloat xs[3] = {NSMinX(rect), NSMidX(rect), NSMaxX(rect)};
    CGFloat ys[3] = {NSMinY(rect), NSMidY(rect), NSMaxY(rect)};
    [VBColorText() setFill];
    for (int iy = 0; iy < 3; iy++) {
        for (int ix = 0; ix < 3; ix++) {
            if (ix == 1 && iy == 1) continue;
            NSRectFill(NSMakeRect(xs[ix] - 2.5, ys[iy] - 2.5, 5, 5));
        }
    }
}

- (void)drawControl:(VbControl *)control origin:(NSPoint)origin
{
    NSRect rect;
    NSString *type;
    if (!control) return;
    if (!vb_control_visible(control)) return;
    type = [NSString stringWithUTF8String:control->type ?: ""];
    rect = NSMakeRect(origin.x + VBTwipsToPoints(vb_control_get_int(control, "Left", 0)),
                      origin.y + VBTwipsToPoints(vb_control_get_int(control, "Top", 0)),
                      VBTwipsToPoints(vb_control_get_int(control, "Width", 0)),
                      VBTwipsToPoints(vb_control_get_int(control, "Height", 0)));

    if ([type isEqualToString:@"VB.Label"]) {
        NSTextAlignment align = NSTextAlignmentLeft;
        int a = vb_control_get_int(control, "Alignment", 0);
        if (a == 1) align = NSTextAlignmentRight;
        else if (a == 2) align = NSTextAlignmentCenter;
        drawTextInRect(controlDisplay(control, "Caption"), rect, VBColorText(), align,
                       VBFontUI(), NO, YES);
        return;
    }
    if ([type isEqualToString:@"VB.TextBox"]) {
        NSColor *back = controlBackColor(control, VBColorWindow());
        [back setFill];
        NSRectFill(rect);
        VBDrawSunkenBevel(rect);
        {
            NSString *text = controlDisplay(control, "Text");
            NSString *password = controlDisplay(control, "PasswordChar");
            if (password.length > 0) text = [@"" stringByPaddingToLength:text.length withString:password startingAtIndex:0];
            drawTextInRect(text, NSInsetRect(rect, 4, 2), VBColorText(), NSTextAlignmentLeft,
                           VBFontUI(), NO, NO);
        }
        return;
    }
    if ([type isEqualToString:@"VB.CommandButton"]) {
        VBDrawRaisedBevel(rect);
        drawTextInRect(controlDisplay(control, "Caption"), NSInsetRect(rect, 3, 2), VBColorText(),
                       NSTextAlignmentCenter, VBFontUI(), YES, NO);
        return;
    }
    if ([type isEqualToString:@"VB.CheckBox"] || [type isEqualToString:@"VB.OptionButton"]) {
        NSRect box = NSMakeRect(NSMinX(rect) + 2, NSMidY(rect) - 6, 12, 12);
        if ([type isEqualToString:@"VB.OptionButton"]) {
            VBDrawClassicRadio(box, vb_control_get_int(control, "Value", 0) != 0);
        } else {
            VBDrawClassicCheck(box, vb_control_get_int(control, "Value", 0) != 0);
        }
        drawTextInRect(controlDisplay(control, "Caption"),
                       NSMakeRect(NSMinX(rect) + 18, NSMinY(rect), NSWidth(rect) - 20, NSHeight(rect)),
                       VBColorText(), NSTextAlignmentLeft, VBFontUI(), YES, NO);
        return;
    }
    if ([type isEqualToString:@"VB.Frame"]) {
        VBDrawEtchedBorder(rect);
        {
            NSString *caption = controlDisplay(control, "Caption");
            NSDictionary *attrs = @{NSFontAttributeName: VBFontUI(), NSForegroundColorAttributeName: VBColorText()};
            NSSize size = caption.length ? [caption sizeWithAttributes:attrs] : NSZeroSize;
            if (size.width > 0) {
                NSRect bg = NSMakeRect(NSMinX(rect) + 6, NSMinY(rect) - size.height / 2.0,
                                       size.width + 4, size.height);
                [VBColorFace() setFill];
                NSRectFill(bg);
                [caption drawAtPoint:NSMakePoint(bg.origin.x + 2, bg.origin.y) withAttributes:attrs];
            }
        }
        [self drawChildrenOf:control origin:NSMakePoint(NSMinX(rect) + 1, NSMinY(rect) + 1)];
        return;
    }
    if ([type isEqualToString:@"VB.PictureBox"]) {
        [VBColorWindow() setFill];
        NSRectFill(rect);
        [VBColorDarkShadow() setStroke];
        [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
        [self drawChildrenOf:control origin:NSMakePoint(NSMinX(rect) + 1, NSMinY(rect) + 1)];
        return;
    }
    if ([type isEqualToString:@"VB.ListBox"] || [type isEqualToString:@"VB.ComboBox"] ||
        [type isEqualToString:@"VB.FileListBox"] || [type isEqualToString:@"VB.DirListBox"] ||
        [type isEqualToString:@"VB.DriveListBox"]) {
        [VBColorWindow() setFill];
        NSRectFill(rect);
        [VBColorDarkShadow() setStroke];
        [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
        if ([type isEqualToString:@"VB.ComboBox"]) {
            NSRect arrow = NSMakeRect(NSMaxX(rect) - 16, NSMinY(rect) + 1, 15, NSHeight(rect) - 2);
            [VBColorFace() setFill];
            NSRectFill(arrow);
            [VBColorDarkShadow() setStroke];
            [NSBezierPath strokeRect:NSInsetRect(arrow, 0.5, 0.5)];
        }
        drawTextInRect(type, NSInsetRect(rect, 3, 2), [NSColor grayColor], NSTextAlignmentLeft,
                       VBFontUI(), NO, NO);
        return;
    }
    if ([type isEqualToString:@"VB.Image"]) {
        [VBColorFace() setFill];
        NSRectFill(rect);
        [VBColorDarkShadow() setStroke];
        [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))
                                  toPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))
                                  toPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
        return;
    }
    if ([type isEqualToString:@"VB.Line"]) {
        int x1 = vb_control_get_int(control, "X1", vb_control_get_int(control, "Left", 0));
        int y1 = vb_control_get_int(control, "Y1", vb_control_get_int(control, "Top", 0));
        int x2 = vb_control_get_int(control, "X2", vb_control_get_int(control, "Left", 0) + vb_control_get_int(control, "Width", 0));
        int y2 = vb_control_get_int(control, "Y2", vb_control_get_int(control, "Top", 0) + vb_control_get_int(control, "Height", 0));
        [[NSColor blackColor] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(origin.x + VBTwipsToPoints(x1), origin.y + VBTwipsToPoints(y1))
                                  toPoint:NSMakePoint(origin.x + VBTwipsToPoints(x2), origin.y + VBTwipsToPoints(y2))];
        return;
    }
    if ([type isEqualToString:@"VB.Shape"]) {
        int shape = vb_control_get_int(control, "Shape", 1);
        [VBColorFace() setFill];
        [VBColorDarkShadow() setStroke];
        if (shape == 3 || shape == 4) {
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 0.5, 0.5)] fill];
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 0.5, 0.5)] stroke];
        } else {
            NSRectFill(rect);
            [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
        }
        return;
    }
    if ([type isEqualToString:@"VB.HScrollBar"] || [type isEqualToString:@"VB.VScrollBar"]) {
        [VBColorFace() setFill];
        NSRectFill(rect);
        [VBColorDarkShadow() setStroke];
        [NSBezierPath strokeRect:NSInsetRect(rect, 0.5, 0.5)];
        [VBColorShadow() setFill];
        if ([type isEqualToString:@"VB.HScrollBar"]) {
            NSRectFill(NSMakeRect(NSMinX(rect) + 4, NSMinY(rect) + 3, NSWidth(rect) / 3, NSHeight(rect) - 6));
        } else {
            NSRectFill(NSMakeRect(NSMinX(rect) + 3, NSMinY(rect) + 4, NSWidth(rect) - 6, NSHeight(rect) / 3));
        }
        return;
    }
    if ([type isEqualToString:@"VB.Data"]) {
        VBDrawClassicDataControl(rect, controlDisplay(control, "Caption"));
        return;
    }
    if ([type isEqualToString:@"VB.DataGrid"]) {
        VBDrawClassicDataGrid(rect,
                              vb_control_get_int(control, "ColumnHeaders", -1),
                              vb_control_get_int(control, "DefColWidth", 1275),
                              vb_control_get_int(control, "RowHeight", 255));
        return;
    }
    drawTextInRect(type, rect, VBColorText(), NSTextAlignmentLeft, VBFontUI(), NO, NO);
}

- (void)drawChildrenOf:(VbControl *)control origin:(NSPoint)origin
{
    int i;
    for (i = 0; i < control->nchildren; i++) {
        [self drawControl:control->children[i] origin:origin];
    }
}

- (VbControl *)hitControlAt:(NSPoint)point parent:(VbControl *)parent origin:(NSPoint)origin
{
    int i;
    if (!parent) return NULL;
    for (i = parent->nchildren - 1; i >= 0; i--) {
        VbControl *child = parent->children[i];
        NSRect rect;
        NSPoint childOrigin;
        if (!vb_control_visible(child)) continue;
        rect = NSMakeRect(origin.x + VBTwipsToPoints(vb_control_get_int(child, "Left", 0)),
                          origin.y + VBTwipsToPoints(vb_control_get_int(child, "Top", 0)),
                          VBTwipsToPoints(vb_control_get_int(child, "Width", 0)),
                          VBTwipsToPoints(vb_control_get_int(child, "Height", 0)));
        childOrigin = rect.origin;
        if (vb_control_is_container(child->type)) {
            VbControl *inner = [self hitControlAt:point parent:child origin:NSMakePoint(childOrigin.x + 1, childOrigin.y + 1)];
            if (inner) return inner;
        }
        if (NSPointInRect(point, rect)) return child;
    }
    return NULL;
}

- (VbControl *)containerAt:(NSPoint)point parent:(VbControl *)parent origin:(NSPoint)origin depth:(int)depth
{
    VbControl *best = parent;
    int i;
    if (!parent || depth > 32) return best;
    for (i = 0; i < parent->nchildren; i++) {
        VbControl *child = parent->children[i];
        NSRect rect;
        if (!vb_control_is_container(child->type)) continue;
        rect = NSMakeRect(origin.x + VBTwipsToPoints(vb_control_get_int(child, "Left", 0)),
                          origin.y + VBTwipsToPoints(vb_control_get_int(child, "Top", 0)),
                          VBTwipsToPoints(vb_control_get_int(child, "Width", 0)),
                          VBTwipsToPoints(vb_control_get_int(child, "Height", 0)));
        if (NSPointInRect(point, rect)) {
            best = [self containerAt:point parent:child origin:NSMakePoint(rect.origin.x + 1, rect.origin.y + 1) depth:depth + 1];
        }
    }
    return best;
}

- (NSPoint)twipsForPoint:(NSPoint)point origin:(NSPoint)origin
{
    return NSMakePoint((point.x - origin.x) * 15.0 / 1.5,
                       (point.y - origin.y) * 15.0 / 1.5);
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect client = [self clientRect];
    [self.window makeFirstResponder:self];
    if (!self.form) return;

    if (self.pendingTool.length > 0 && NSPointInRect(point, client)) {
        _mode = 3;
        _createRect = NSMakeRect(point.x, point.y, 0, 0);
        [self setNeedsDisplay:YES];
        return;
    }

    VbControl *hit = [self hitControlAt:point parent:self.form->root origin:client.origin];
    if (event.clickCount >= 2) {
        if (hit) {
            [self setSelectionToControl:hit notify:YES];
            [self.delegate designer:self requestCodeForControl:hit];
        } else if (NSPointInRect(point, client)) {
            [self setSelectionToControl:self.form->root notify:YES];
            [self.delegate designer:self requestCodeForControl:self.form->root];
        }
        return;
    }

    if (_selection.count > 0) {
        NSRect target = [self selectionRect];
        NSInteger handle = [self handleAtPoint:point rect:target];
        if (handle >= 0 && (_selection.count == 1 || [self selectionSharesParent])) {
            _resizeHandle = handle;
            _mode = _selection.count > 1 ? 5 : 2;
            self.dragMouse = point;
            _dragRect = target;
            [self captureDragState];
            return;
        }
    }

    BOOL extend = (event.modifierFlags & (NSEventModifierFlagShift |
                                          NSEventModifierFlagCommand)) != 0;
    if (hit) {
        if (extend) {
            [self toggleControlInSelection:hit];
            _mode = 0;
            return;
        }
        if (![self isSelectedControl:hit]) {
            [self setSelectionToControl:hit notify:YES];
        } else {
            _selected = hit;
            if (self.delegate) [self.delegate designerSelectionChanged:self];
            [self setNeedsDisplay:YES];
        }
        _mode = 1;
        self.dragMouse = point;
        [self captureDragState];
        return;
    }

    if (NSPointInRect(point, client)) {
        _marqueeAdditive = extend;
        if (!extend) {
            [self clearSelectionList];
            _selected = self.form->root;
            if (self.delegate) [self.delegate designerSelectionChanged:self];
        }
        _mode = 4;
        _marqueeStart = point;
        _marqueeRect = NSMakeRect(point.x, point.y, 0, 0);
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (_mode == 3) {
        _createRect.size.width = point.x - _createRect.origin.x;
        _createRect.size.height = point.y - _createRect.origin.y;
        if (_createRect.size.width < 0) {
            _createRect.origin.x = point.x;
            _createRect.size.width = -_createRect.size.width;
        }
        if (_createRect.size.height < 0) {
            _createRect.origin.y = point.y;
            _createRect.size.height = -_createRect.size.height;
        }
        [self setNeedsDisplay:YES];
        return;
    }
    if (_mode == 4) {
        CGFloat minX = MIN(_marqueeStart.x, point.x);
        CGFloat minY = MIN(_marqueeStart.y, point.y);
        _marqueeRect = NSMakeRect(minX, minY, fabs(point.x - _marqueeStart.x),
                                  fabs(point.y - _marqueeStart.y));
        [self setNeedsDisplay:YES];
        return;
    }
    if (_mode == 1) {
        int dx = (int)lround((point.x - self.dragMouse.x) * 10.0);
        int dy = (int)lround((point.y - self.dragMouse.y) * 10.0);
        for (NSUInteger i = 0; i < _selection.count && i < _dragLeftTops.count; i++) {
            VbControl *control = (VbControl *)_selection[i].pointerValue;
            NSPoint origin = _dragLeftTops[i].pointValue;
            vb_control_set_int(control, "Left", snap15((int)origin.x + dx));
            vb_control_set_int(control, "Top", snap15((int)origin.y + dy));
        }
        [self setNeedsDisplay:YES];
        return;
    }
    if (_mode == 2 || _mode == 5) {
        NSRect rect = _dragRect;
        CGFloat dx = point.x - self.dragMouse.x;
        CGFloat dy = point.y - self.dragMouse.y;
        int ix = (int)(_resizeHandle % 3);
        int iy = (int)(_resizeHandle / 3);
        const CGFloat minWidth = 10;
        const CGFloat minHeight = 10;
        if (ix == 0) {
            rect.origin.x += dx;
            rect.size.width -= dx;
        } else if (ix == 2) {
            rect.size.width += dx;
        }
        if (iy == 0) {
            rect.origin.y += dy;
            rect.size.height -= dy;
        } else if (iy == 2) {
            rect.size.height += dy;
        }
        if (rect.size.width < minWidth) {
            if (ix == 0) rect.origin.x = NSMaxX(_dragRect) - minWidth;
            rect.size.width = minWidth;
        }
        if (rect.size.height < minHeight) {
            if (iy == 0) rect.origin.y = NSMaxY(_dragRect) - minHeight;
            rect.size.height = minHeight;
        }

        if (_mode == 2 && _selection.count > 0) {
            VbControl *control = (VbControl *)_selection[0].pointerValue;
            NSPoint origin = _dragLeftTops[0].pointValue;
            NSSize size = _dragSizes[0].sizeValue;
            int left = (int)lround(origin.x + (rect.origin.x - _dragRect.origin.x) * 10.0);
            int top = (int)lround(origin.y + (rect.origin.y - _dragRect.origin.y) * 10.0);
            int width = (int)lround(rect.size.width * 10.0);
            int height = (int)lround(rect.size.height * 10.0);
            if (width < 120) width = 120;
            if (height < 60) height = 60;
            (void)size;
            vb_control_set_int(control, "Left", snap15(left));
            vb_control_set_int(control, "Top", snap15(top));
            vb_control_set_int(control, "Width", snap15(width));
            vb_control_set_int(control, "Height", snap15(height));
        } else if (_mode == 5) {
            CGFloat sx = _dragRect.size.width > 0 ? rect.size.width / _dragRect.size.width : 1;
            CGFloat sy = _dragRect.size.height > 0 ? rect.size.height / _dragRect.size.height : 1;
            for (NSUInteger i = 0; i < _selection.count; i++) {
                VbControl *control = (VbControl *)_selection[i].pointerValue;
                NSRect start = _dragFrames[i].rectValue;
                NSPoint origin = _dragLeftTops[i].pointValue;
                NSSize size = _dragSizes[i].sizeValue;
                CGFloat x = rect.origin.x + (start.origin.x - _dragRect.origin.x) * sx;
                CGFloat y = rect.origin.y + (start.origin.y - _dragRect.origin.y) * sy;
                int left = (int)lround(origin.x + (x - start.origin.x) * 10.0);
                int top = (int)lround(origin.y + (y - start.origin.y) * 10.0);
                int width = (int)lround(start.size.width * sx * 10.0);
                int height = (int)lround(start.size.height * sy * 10.0);
                if (width < 120) width = 120;
                if (height < 60) height = 60;
                (void)size;
                vb_control_set_int(control, "Left", snap15(left));
                vb_control_set_int(control, "Top", snap15(top));
                vb_control_set_int(control, "Width", snap15(width));
                vb_control_set_int(control, "Height", snap15(height));
            }
        }
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    if (_mode == 3 && self.form && self.pendingTool.length > 0) {
        NSRect client = [self clientRect];
        VbControl *parent = [self containerAt:NSMakePoint(_createRect.origin.x, _createRect.origin.y)
                                        parent:self.form->root origin:client.origin depth:0];
        NSPoint origin = client.origin;
        if (parent && parent != self.form->root) {
            NSRect parentRect = [self rectForControl:parent];
            origin = NSMakePoint(parentRect.origin.x + 1, parentRect.origin.y + 1);
        }
        {
            int left = (int)lround((_createRect.origin.x - origin.x) * 10.0);
            int top = (int)lround((_createRect.origin.y - origin.y) * 10.0);
            int width = (int)lround(_createRect.size.width * 10.0);
            int height = (int)lround(_createRect.size.height * 10.0);
            const VbToolDef *def = vb_tool_def(self.pendingTool.UTF8String);
            if (width < 120 || height < 60) {
                width = def ? def->width : 1200;
                height = def ? def->height : 255;
            }
            {
                VbControl *created = vb_form_add_control(self.form, parent, self.pendingTool.UTF8String,
                                                         snap15(left), snap15(top), snap15(width), snap15(height));
                if (created) {
                    [self setSelectionToControl:created notify:YES];
                    [self.delegate designerDidModifyForm:self];
                }
            }
        }
        self.pendingTool = nil;
        [self.delegate designerDidFinishCreate:self];
    } else if (_mode == 4) {
        if (!_marqueeAdditive) [_selection removeAllObjects];
        if (self.form) {
            for (int i = 0; i < self.form->root->nchildren; i++) {
                VbControl *child = self.form->root->children[i];
                if (!NSIntersectsRect([self rectForControl:child], _marqueeRect)) continue;
                if ([self isSelectedControl:child]) continue;
                [_selection addObject:[NSValue valueWithPointer:child]];
                _selected = child;
            }
            if (_selection.count == 0) _selected = self.form->root;
            else if (![self isSelectedControl:_selected]) {
                _selected = (VbControl *)_selection.lastObject.pointerValue;
            }
        }
        if (self.delegate) [self.delegate designerSelectionChanged:self];
    } else if (_mode == 1 || _mode == 2 || _mode == 5) {
        [self.delegate designerDidModifyForm:self];
        [self.delegate designerSelectionChanged:self];
    }
    _mode = 0;
    _marqueeRect = NSZeroRect;
    [_dragFrames removeAllObjects];
    [_dragLeftTops removeAllObjects];
    [_dragSizes removeAllObjects];
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 51 || event.keyCode == 117) {
        [self deleteSelected];
        return;
    }
    if (event.keyCode == 53) {
        self.pendingTool = nil;
        [_selection removeAllObjects];
        _selected = self.form ? self.form->root : NULL;
        [self.delegate designerDidFinishCreate:self];
        [self setNeedsDisplay:YES];
        return;
    }
    if (event.keyCode >= 123 && event.keyCode <= 126 && _selection.count > 0) {
        int step = (event.modifierFlags & NSEventModifierFlagShift) ? 1 : 15;
        int dx = 0;
        int dy = 0;
        if (event.keyCode == 123) dx = -step;
        else if (event.keyCode == 124) dx = step;
        else if (event.keyCode == 126) dy = -step;
        else if (event.keyCode == 125) dy = step;
        for (NSValue *value in _selection) {
            VbControl *control = (VbControl *)value.pointerValue;
            vb_control_set_int(control, "Left", vb_control_get_int(control, "Left", 0) + dx);
            vb_control_set_int(control, "Top", vb_control_get_int(control, "Top", 0) + dy);
        }
        [self setNeedsDisplay:YES];
        [self.delegate designerDidModifyForm:self];
        [self.delegate designerSelectionChanged:self];
        return;
    }
    [super keyDown:event];
}

#pragma mark - Format operations

- (BOOL)canAlignSelection
{
    return _selection.count >= 2 && [self selectionSharesParent];
}

- (BOOL)canSpaceSelection
{
    return _selection.count >= 3 && [self selectionSharesParent];
}

- (void)finishFormatOperation
{
    if (self.delegate) {
        [self.delegate designerDidModifyForm:self];
        [self.delegate designerSelectionChanged:self];
    }
    [self setNeedsDisplay:YES];
}

- (BOOL)alignSelection:(VBDesignerAlign)mode
{
    VbControl *root;
    int minLeft = INT_MAX;
    int maxRight = INT_MIN;
    int minTop = INT_MAX;
    int maxBottom = INT_MIN;
    if (!self.form || ![self canAlignSelection]) return NO;
    root = self.form->root;
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        int left = absolute_left(control, root);
        int top = absolute_top(control, root);
        int right = left + vb_control_get_int(control, "Width", 0);
        int bottom = top + vb_control_get_int(control, "Height", 0);
        minLeft = MIN(minLeft, left);
        maxRight = MAX(maxRight, right);
        minTop = MIN(minTop, top);
        maxBottom = MAX(maxBottom, bottom);
    }
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        int left = absolute_left(control, root);
        int top = absolute_top(control, root);
        int width = vb_control_get_int(control, "Width", 0);
        int height = vb_control_get_int(control, "Height", 0);
        switch (mode) {
            case VBDesignerAlignLeft: move_to_absolute_left(control, root, minLeft); break;
            case VBDesignerAlignRight: move_to_absolute_left(control, root, maxRight - width); break;
            case VBDesignerAlignCenter:
                move_to_absolute_left(control, root, (int)(((long long)minLeft + maxRight - width) / 2));
                break;
            case VBDesignerAlignTop: move_to_absolute_top(control, root, minTop); break;
            case VBDesignerAlignBottom: move_to_absolute_top(control, root, maxBottom - height); break;
            case VBDesignerAlignMiddle:
                move_to_absolute_top(control, root, (int)(((long long)minTop + maxBottom - height) / 2));
                break;
        }
        (void)left;
        (void)top;
    }
    [self finishFormatOperation];
    return YES;
}

- (BOOL)makeSameSize:(VBDesignerSize)mode
{
    VbControl *root;
    VbControl *reference;
    int width;
    int height;
    if (!self.form || ![self canAlignSelection]) return NO;
    root = self.form->root;
    reference = self.selected;
    if (!reference || ![self isSelectedControl:reference]) reference = _selection.lastObject.pointerValue;
    width = vb_control_get_int(reference, "Width", 0);
    height = vb_control_get_int(reference, "Height", 0);
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        if (control == reference) continue;
        if (mode != VBDesignerSizeHeight) vb_control_set_int(control, "Width", width);
        if (mode != VBDesignerSizeWidth) vb_control_set_int(control, "Height", height);
    }
    (void)root;
    [self finishFormatOperation];
    return YES;
}

- (BOOL)spaceSelection:(VBDesignerSpacing)mode horizontal:(BOOL)horizontal
{
    VbControl *root;
    NSArray<NSValue *> *ordered;
    NSUInteger count;
    int *sizes = NULL;
    int *starts = NULL;
    int *gaps = NULL;
    int cursor;
    BOOL changed = NO;
    if (!self.form || ![self canSpaceSelection]) return NO;
    root = self.form->root;
    ordered = [_selection sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        VbControl *ca = (VbControl *)a.pointerValue;
        VbControl *cb = (VbControl *)b.pointerValue;
        int la = horizontal ? absolute_left(ca, self.form->root) : absolute_top(ca, self.form->root);
        int lb = horizontal ? absolute_left(cb, self.form->root) : absolute_top(cb, self.form->root);
        if (la != lb) return la < lb ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    count = ordered.count;
    if (count < 3) return NO;
    sizes = calloc(count, sizeof(int));
    starts = calloc(count, sizeof(int));
    gaps = calloc(count, sizeof(int));
    if (!sizes || !starts || !gaps) {
        free(sizes); free(starts); free(gaps);
        return NO;
    }
    for (NSUInteger i = 0; i < count; i++) {
        VbControl *control = (VbControl *)ordered[i].pointerValue;
        starts[i] = horizontal ? absolute_left(control, root) : absolute_top(control, root);
        sizes[i] = horizontal ? vb_control_get_int(control, "Width", 0)
                              : vb_control_get_int(control, "Height", 0);
    }
    for (NSUInteger i = 1; i < count; i++) gaps[i] = starts[i] - (starts[i - 1] + sizes[i - 1]);

    if (mode == VBDesignerSpacingMakeEqual) {
        long long span = (long long)starts[count - 1] + sizes[count - 1] - starts[0];
        long long occupied = 0;
        for (NSUInteger i = 0; i < count; i++) occupied += sizes[i];
        gaps[0] = (int)((span - occupied) / (long long)(count - 1));
        if (gaps[0] < 0) gaps[0] = 0;
        for (NSUInteger i = 1; i < count; i++) gaps[i] = gaps[0];
    } else if (mode == VBDesignerSpacingIncrease || mode == VBDesignerSpacingDecrease) {
        int delta = mode == VBDesignerSpacingIncrease ? 60 : -60;
        for (NSUInteger i = 1; i < count; i++) gaps[i] = MAX(0, gaps[i] + delta);
    } else {
        for (NSUInteger i = 1; i < count; i++) gaps[i] = 0;
    }

    cursor = starts[0];
    for (NSUInteger i = 0; i < count; i++) {
        VbControl *control = (VbControl *)ordered[i].pointerValue;
        int target = cursor;
        if (target != starts[i]) {
            if (horizontal) move_to_absolute_left(control, root, target);
            else move_to_absolute_top(control, root, target);
            changed = YES;
        }
        cursor += sizes[i] + (i + 1 < count ? gaps[i + 1] : 0);
    }
    free(sizes);
    free(starts);
    free(gaps);
    if (changed) [self finishFormatOperation];
    return changed;
}

- (BOOL)centerSelectionInForm
{
    VbControl *root;
    int clientWidth;
    int clientHeight;
    int minLeft = INT_MAX;
    int maxRight = INT_MIN;
    int minTop = INT_MAX;
    int maxBottom = INT_MIN;
    int deltaX;
    int deltaY;
    BOOL changed = NO;
    if (!self.form || _selection.count == 0) return NO;
    root = self.form->root;
    clientWidth = vb_form_client_width(self.form);
    clientHeight = vb_form_client_height(self.form);
    /* VB6 centres the selection as a group: relative positions are preserved. */
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        int left = absolute_left(control, root);
        int top = absolute_top(control, root);
        minLeft = MIN(minLeft, left);
        maxRight = MAX(maxRight, left + vb_control_get_int(control, "Width", 0));
        minTop = MIN(minTop, top);
        maxBottom = MAX(maxBottom, top + vb_control_get_int(control, "Height", 0));
    }
    deltaX = (clientWidth - (maxRight - minLeft)) / 2 - minLeft;
    deltaY = (clientHeight - (maxBottom - minTop)) / 2 - minTop;
    if (deltaX == 0 && deltaY == 0) return NO;
    for (NSValue *value in _selection) {
        VbControl *control = (VbControl *)value.pointerValue;
        move_to_absolute_left(control, root, absolute_left(control, root) + deltaX);
        move_to_absolute_top(control, root, absolute_top(control, root) + deltaY);
        changed = YES;
    }
    if (changed) [self finishFormatOperation];
    return changed;
}

- (BOOL)canReorderSelection
{
    return _selection.count > 0 && [self selectionSharesParent];
}

- (BOOL)reorderSelectionToFront:(BOOL)front
{
    VbControl *parent;
    NSMutableSet<NSValue *> *selected;
    VbControl **reordered;
    int count;
    int i;
    int next = 0;
    BOOL changed = NO;
    if (!self.form || ![self canReorderSelection]) return NO;
    parent = ((VbControl *)_selection.firstObject.pointerValue)->parent;
    if (!parent) return NO;
    count = parent->nchildren;
    if (count < 2) return NO;
    reordered = (VbControl **)calloc((size_t)count, sizeof(VbControl *));
    if (!reordered) return NO;
    selected = [NSMutableSet setWithArray:_selection];
    if (front) {
        for (i = 0; i < count; i++) {
            VbControl *child = parent->children[i];
            if (![selected containsObject:[NSValue valueWithPointer:child]]) reordered[next++] = child;
        }
        for (i = 0; i < count; i++) {
            VbControl *child = parent->children[i];
            if ([selected containsObject:[NSValue valueWithPointer:child]]) reordered[next++] = child;
        }
    } else {
        for (i = 0; i < count; i++) {
            VbControl *child = parent->children[i];
            if ([selected containsObject:[NSValue valueWithPointer:child]]) reordered[next++] = child;
        }
        for (i = 0; i < count; i++) {
            VbControl *child = parent->children[i];
            if (![selected containsObject:[NSValue valueWithPointer:child]]) reordered[next++] = child;
        }
    }
    for (i = 0; i < count; i++) {
        if (parent->children[i] != reordered[i]) {
            changed = YES;
            break;
        }
    }
    if (changed) {
        memcpy(parent->children, reordered, (size_t)count * sizeof(VbControl *));
        [self finishFormatOperation];
    }
    free(reordered);
    return changed;
}

- (BOOL)bringSelectionToFront
{
    return [self reorderSelectionToFront:YES];
}

- (BOOL)sendSelectionToBack
{
    return [self reorderSelectionToFront:NO];
}

- (void)deleteSelected
{
    if (!self.form) return;
    NSMutableArray<NSValue *> *targets = [_selection mutableCopy];
    if (targets.count == 0 && self.selected && self.selected != self.form->root) {
        [targets addObject:[NSValue valueWithPointer:self.selected]];
    }
    BOOL changed = NO;
    for (NSValue *value in targets) {
        VbControl *control = (VbControl *)value.pointerValue;
        if (!control || control == self.form->root) continue;
        BOOL skip = NO;
        for (NSValue *other in targets) {
            VbControl *candidate = (VbControl *)other.pointerValue;
            if (candidate != control && [self isDescendant:control of:candidate]) {
                skip = YES;
                break;
            }
        }
        if (skip || !control->parent) continue;
        vb_control_remove_child(control->parent, control);
        vb_control_free(control);
        changed = YES;
    }
    [_selection removeAllObjects];
    _selected = self.form->root;
    if (changed) {
        [self.delegate designerSelectionChanged:self];
        [self.delegate designerDidModifyForm:self];
    }
    [self setNeedsDisplay:YES];
}

@end
