#import "VBToolboxView.h"
#import "VBTheme.h"

#include "core/vb_model.h"

static const CGFloat kHeaderHeight = 20.0;
static const CGFloat kCellWidth = 34.0;
static const CGFloat kCellHeight = 32.0;
static const CGFloat kMargin = 3.0;

@implementation VBToolboxView {
    const VbToolDef *_tools;
    int _count;
    int _hover;
    NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _tools = vb_tool_defs(&_count);
    _hover = -1;
    self.autoresizingMask = NSViewWidthSizable;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    self.window.acceptsMouseMovedEvents = YES;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                             options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                      NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                               owner:self
                                            userInfo:nil];
    [self addTrackingArea:_tracking];
    for (int i = 0; i < _count; i++) {
        [self addToolTipRect:[self rectForIndex:i] owner:self userData:(void *)(intptr_t)i];
    }
}

- (CGFloat)preferredHeight
{
    int rows = (_count + 1) / 2;
    return kHeaderHeight + 4 + rows * kCellHeight + 4;
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
    (void)view;
    (void)tag;
    (void)point;
    int index = (int)(intptr_t)data;
    if (index < 0 || index >= _count) return nil;
    NSString *type = [NSString stringWithUTF8String:_tools[index].type];
    return [type stringByReplacingOccurrencesOfString:@"VB." withString:@""];
}

- (NSRect)rectForIndex:(int)index
{
    int column = index % 2;
    int row = index / 2;
    return NSMakeRect(kMargin + column * (kCellWidth + 2),
                      kHeaderHeight + 3 + row * kCellHeight,
                      kCellWidth,
                      kCellHeight - 3);
}

- (int)indexAtPoint:(NSPoint)point
{
    for (int i = 0; i < _count; i++) {
        if (NSPointInRect(point, [self rectForIndex:i])) return i;
    }
    return -1;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);
    VBDrawTitleBar(NSMakeRect(0, 0, NSWidth(self.bounds), kHeaderHeight), @"Toolbox", YES, NO, NO, NO);
    [[VBColorShadow() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, kHeaderHeight, NSWidth(self.bounds), 1));

    for (int i = 0; i < _count; i++) {
        NSRect cell = [self rectForIndex:i];
        NSString *type = [NSString stringWithUTF8String:_tools[i].type];
        BOOL selected = self.selectedType && [type isEqualToString:self.selectedType];
        BOOL hovered = (i == _hover);

        if (selected) {
            VBDrawPressedBevel(cell);
        } else if (hovered) {
            VBFillFace(cell);
            [[VBColorLight() colorWithAlphaComponent:0.95] setFill];
            NSRectFill(NSMakeRect(NSMinX(cell), NSMinY(cell), NSWidth(cell), 1));
            NSRectFill(NSMakeRect(NSMinX(cell), NSMinY(cell), 1, NSHeight(cell)));
            [[VBColorShadow() colorWithAlphaComponent:0.55] setFill];
            NSRectFill(NSMakeRect(NSMinX(cell), NSMaxY(cell) - 1, NSWidth(cell), 1));
            NSRectFill(NSMakeRect(NSMaxX(cell) - 1, NSMinY(cell), 1, NSHeight(cell)));
        }

        NSRect iconRect = NSMakeRect(NSMidX(cell) - 12, NSMidY(cell) - 11, 24, 22);
        [self drawIconForType:type inRect:iconRect];
    }

    [[VBColorLight() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
}

- (void)drawIconForType:(NSString *)name inRect:(NSRect)rect
{
    NSColor *ink = [NSColor colorWithWhite:0.1 alpha:1];
    NSColor *paper = VBColorWindow();
    NSRect inner = NSInsetRect(rect, 1.5, 1.5);

    if ([name isEqualToString:@"VB.Label"]) {
        NSDictionary *attrs = @{NSFontAttributeName: VBFontUISmall(),
                                NSForegroundColorAttributeName: ink};
        [@"A" drawInRect:NSMakeRect(rect.origin.x + 4, rect.origin.y + 3, 14, 14)
          withAttributes:attrs];
        return;
    }
    if ([name isEqualToString:@"VB.TextBox"] || [name isEqualToString:@"VB.ComboBox"] ||
        [name isEqualToString:@"VB.ListBox"] || [name isEqualToString:@"VB.FileListBox"] ||
        [name isEqualToString:@"VB.DirListBox"] || [name isEqualToString:@"VB.DriveListBox"]) {
        NSRect box = NSMakeRect(NSMinX(inner), NSMinY(inner) + 3, NSWidth(inner), 10);
        [paper setFill];
        NSRectFill(box);
        [[VBColorShadow() colorWithAlphaComponent:0.95] setFill];
        NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box), NSWidth(box), 1));
        NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box), 1, NSHeight(box)));
        [ink setFill];
        NSRectFill(NSMakeRect(NSMinX(box), NSMaxY(box) - 1, NSWidth(box), 1));
        NSRectFill(NSMakeRect(NSMaxX(box) - 1, NSMinY(box), 1, NSHeight(box)));
        if (![name isEqualToString:@"VB.TextBox"]) {
            [ink setStroke];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(box) - 6, NSMidY(box))
                                      toPoint:NSMakePoint(NSMaxX(box) - 3, NSMidY(box))];
            VBDrawClassicArrow(NSMakeRect(NSMaxX(box) - 7, NSMidY(box) - 2, 6, 5), YES, ink);
        }
        return;
    }
    if ([name isEqualToString:@"VB.CommandButton"]) {
        VBDrawRaisedBevel(inner);
        [ink setStroke];
        [NSBezierPath strokeRect:NSInsetRect(inner, 3.5, 3.5)];
        return;
    }
    if ([name isEqualToString:@"VB.CheckBox"] || [name isEqualToString:@"VB.OptionButton"]) {
        NSRect box = NSMakeRect(NSMinX(rect) + 2, NSMidY(rect) - 5, 10, 10);
        if ([name isEqualToString:@"VB.OptionButton"]) {
            VBDrawClassicRadio(box, 1);
        } else {
            VBDrawClassicCheck(box, 1);
        }
        [ink setFill];
        NSRectFill(NSMakeRect(NSMaxX(box) + 3, NSMidY(rect) - 1, 6, 2));
        return;
    }
    if ([name isEqualToString:@"VB.Frame"] || [name isEqualToString:@"VB.PictureBox"]) {
        [paper setFill];
        NSRectFill(inner);
        [ink setStroke];
        [NSBezierPath strokeRect:NSInsetRect(inner, 0.5, 0.5)];
        [[VBColorShadow() colorWithAlphaComponent:0.8] setStroke];
        [NSBezierPath strokeRect:NSInsetRect(inner, 1.5, 1.5)];
        return;
    }
    if ([name isEqualToString:@"VB.Timer"]) {
        VBDrawClassicRadio(inner, 1);
        return;
    }
    if ([name isEqualToString:@"VB.Image"]) {
        [paper setFill];
        NSRectFill(inner);
        [ink setStroke];
        [NSBezierPath strokeRect:NSInsetRect(inner, 0.5, 0.5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner), NSMaxY(inner))
                                  toPoint:NSMakePoint(NSMaxX(inner), NSMinY(inner))];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner), NSMinY(inner))
                                  toPoint:NSMakePoint(NSMaxX(inner), NSMaxY(inner))];
        return;
    }
    if ([name isEqualToString:@"VB.Line"]) {
        [ink setStroke];
        [NSBezierPath setDefaultLineWidth:1.4];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner), NSMaxY(inner) - 3)
                                  toPoint:NSMakePoint(NSMaxX(inner), NSMinY(inner) + 3)];
        return;
    }
    if ([name isEqualToString:@"VB.Shape"]) {
        [paper setFill];
        NSBezierPath *oval = [NSBezierPath bezierPathWithOvalInRect:inner];
        [oval fill];
        [ink setStroke];
        [oval stroke];
        return;
    }
    if ([name isEqualToString:@"VB.HScrollBar"] || [name isEqualToString:@"VB.VScrollBar"]) {
        VBDrawRaisedBevel(inner);
        [ink setFill];
        if ([name isEqualToString:@"VB.HScrollBar"]) {
            NSRectFill(NSMakeRect(NSMinX(inner) + 3, NSMidY(inner) - 2, 7, 4));
        } else {
            NSRectFill(NSMakeRect(NSMidX(inner) - 2, NSMinY(inner) + 3, 4, 7));
        }
        return;
    }
    if ([name isEqualToString:@"VB.Data"]) {
        /* VB6 Data icon: the 3D record navigator strip with its four buttons. */
        VBDrawRaisedBevel(inner);
        [paper setFill];
        NSRectFill(NSInsetRect(inner, 2, 2));
        /* The four record navigator arrows, in VB6 order: first, previous, next, last. */
        for (int i = 0; i < 4; i++) {
            CGFloat x = NSMinX(inner) + 4 + i * 4;
            CGFloat mid = NSMidY(inner) + 2;
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            if (i >= 2) {
                [arrow moveToPoint:NSMakePoint(x, mid + 3)];
                [arrow lineToPoint:NSMakePoint(x + 3, mid)];
                [arrow lineToPoint:NSMakePoint(x, mid - 3)];
            } else {
                [arrow moveToPoint:NSMakePoint(x + 3, mid + 3)];
                [arrow lineToPoint:NSMakePoint(x, mid)];
                [arrow lineToPoint:NSMakePoint(x + 3, mid - 3)];
            }
            [arrow closePath];
            [ink setFill];
            [arrow fill];
        }
        return;
    }
    if ([name isEqualToString:@"VB.DataGrid"]) {
        [paper setFill];
        NSRectFill(inner);
        [ink setStroke];
        [NSBezierPath strokeRect:NSInsetRect(inner, 0.5, 0.5)];
        [ink setFill];
        NSRectFill(NSMakeRect(NSMinX(inner) + 1, NSMaxY(inner) - 5, NSWidth(inner) - 2, 4));
        for (int i = 1; i < 3; i++) {
            CGFloat x = floor(NSMinX(inner) + i * NSWidth(inner) / 3.0) + 0.5;
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x, NSMinY(inner))
                                      toPoint:NSMakePoint(x, NSMaxY(inner) - 5)];
        }
        for (int i = 1; i < 3; i++) {
            CGFloat y = floor(NSMaxY(inner) - 5 - i * 5) + 0.5;
            [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner), y)
                                      toPoint:NSMakePoint(NSMaxX(inner), y)];
        }
        return;
    }
    if ([name isEqualToString:@"VB.Menu"]) {
        [paper setFill];
        NSRectFill(inner);
        [ink setStroke];
        [NSBezierPath strokeRect:NSInsetRect(inner, 0.5, 0.5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner), NSMinY(inner) + 4)
                                  toPoint:NSMakePoint(NSMaxX(inner), NSMinY(inner) + 4)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner) + 4, NSMinY(inner) + 7)
                                  toPoint:NSMakePoint(NSMaxX(inner) - 3, NSMinY(inner) + 7)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(inner) + 4, NSMinY(inner) + 10)
                                  toPoint:NSMakePoint(NSMaxX(inner) - 3, NSMinY(inner) + 10)];
        return;
    }
    [ink setStroke];
    [NSBezierPath strokeRect:NSInsetRect(inner, 0.5, 0.5)];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    int index = [self indexAtPoint:point];
    if (index < 0 || index >= _count) return;
    self.selectedType = [NSString stringWithUTF8String:_tools[index].type];
    [self setNeedsDisplay:YES];
    if (self.delegate) [self.delegate toolboxView:self didSelectType:self.selectedType];
}

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    int index = [self indexAtPoint:point];
    if (index != _hover) {
        _hover = index;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    if (_hover != -1) {
        _hover = -1;
        [self setNeedsDisplay:YES];
    }
}

- (void)clearSelection
{
    if (!self.selectedType) return;
    self.selectedType = nil;
    [self setNeedsDisplay:YES];
}

@end
