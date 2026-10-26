#import "VBProjectOutlineView.h"
#import "VBTheme.h"

#include "core/vb_util.h"

static const CGFloat kHeaderHeight = 20.0;
static const CGFloat kRowHeight = 18.0;
static const CGFloat kIndent = 16.0;

@implementation VBProjectOutlineView {
    NSMutableArray<NSValue *> *_items;
    VbProject *_project;
    VbItem *_selected;
    BOOL _expanded;
    int _hoverRow;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _items = [NSMutableArray array];
    _expanded = YES;
    _hoverRow = -1;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomesFirstResponderOnMouseDown { return YES; }

- (void)setProject:(VbProject *)project
{
    _project = project;
    _selected = NULL;
    [_items removeAllObjects];
    for (int i = 0; project && i < project->nitems; i++) {
        [_items addObject:[NSValue valueWithPointer:&project->items[i]]];
    }
    [self setNeedsDisplay:YES];
}

- (void)selectItem:(VbItem *)item
{
    _selected = item;
    [self setNeedsDisplay:YES];
}

- (NSRect)rootRowRect
{
    return NSMakeRect(0, kHeaderHeight, NSWidth(self.bounds), kRowHeight);
}

- (NSRect)rectForRow:(NSInteger)row
{
    return NSMakeRect(0, kHeaderHeight + row * kRowHeight, NSWidth(self.bounds), kRowHeight);
}

- (NSInteger)rowAtPoint:(NSPoint)point
{
    if (point.y < kHeaderHeight) return -1;
    NSInteger row = (NSInteger)((point.y - kHeaderHeight) / kRowHeight);
    NSInteger limit = _expanded ? (NSInteger)_items.count + 1 : 1;
    if (row < 0 || row >= limit) return -1;
    return row;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);

    NSString *title = _project && _project->name
        ? [NSString stringWithFormat:@"Project - %s", _project->name]
        : @"Project";
    VBDrawTitleBar(NSMakeRect(0, 0, NSWidth(self.bounds), kHeaderHeight), title, YES, NO, NO, NO);
    [[VBColorShadow() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, kHeaderHeight, NSWidth(self.bounds), 1));

    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:NSMakeRect(0, kHeaderHeight + 1, NSWidth(self.bounds),
                                      NSHeight(self.bounds) - kHeaderHeight - 1)];

    // Project row
    NSRect rootRow = [self rootRowRect];
    [self drawExpandBoxAt:NSMakePoint(6, NSMinY(rootRow) + 4) expanded:_expanded];
    NSRect folder = NSMakeRect(22, NSMinY(rootRow) + 1, 16, 15);
    [self drawFolderIconInRect:folder];
    NSString *name = _project && _project->name ? [NSString stringWithUTF8String:_project->name] : @"Project";
    NSDictionary *attrs = @{NSFontAttributeName: VBFontUI(), NSForegroundColorAttributeName: VBColorText()};
    [name drawInRect:NSMakeRect(42, NSMinY(rootRow) + 1, NSWidth(self.bounds) - 80, 15) withAttributes:attrs];
    [self drawTypeTag:@"VBP" atRow:rootRow];

    // Dotted guide under the project row
    if (_expanded) {
        [[VBColorShadow() colorWithAlphaComponent:0.6] setFill];
        for (CGFloat y = NSMaxY(rootRow); y < NSMaxY(rootRow) + 4; y += 2) {
            NSRectFill(NSMakeRect(26, y, 1, 1));
        }
    }

    NSInteger hoveredRow = _hoverRow;
    for (NSUInteger i = 0; _expanded && i < _items.count; i++) {
        VbItem *item = (VbItem *)_items[i].pointerValue;
        NSInteger row = (NSInteger)i + 1;
        NSRect rect = [self rectForRow:row];
        BOOL selected = (item == _selected);

        if (selected) {
            [VBColorSelection() setFill];
            NSRectFill(rect);
            [[VBColorText() colorWithAlphaComponent:0.7] setFill];
            NSRectFill(NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, NSWidth(rect), 1));
        } else if ((NSInteger)row == hoveredRow) {
            [[VBColorFace() colorWithAlphaComponent:0.0] setFill];
        }

        CGFloat x = 26 + kIndent;
        NSRect icon = NSMakeRect(x, NSMinY(rect) + 1, 16, 15);
        [self drawItemIcon:item inRect:icon];

        NSColor *ink = selected ? VBColorTitleText() : VBColorText();
        NSDictionary *textAttrs = @{NSFontAttributeName: VBFontUI(), NSForegroundColorAttributeName: ink};
        NSString *itemName = item->name ? [NSString stringWithUTF8String:item->name] : @"Item";
        [itemName drawInRect:NSMakeRect(x + 20, NSMinY(rect) + 1, NSWidth(self.bounds) - x - 66, 15)
              withAttributes:textAttrs];

        NSString *tag = nil;
        if (item->file) tag = [[[NSString stringWithUTF8String:item->file] pathExtension] uppercaseString];
        if (!tag.length) {
            switch (item->kind) {
                case VB_ITEM_FORM: tag = @"FRM"; break;
                case VB_ITEM_MODULE: tag = @"BAS"; break;
                case VB_ITEM_CLASS: tag = @"CLS"; break;
                default: tag = @"CTL"; break;
            }
        }
        NSDictionary *tagAttrs = @{NSFontAttributeName: VBFontUISmall(),
                                   NSForegroundColorAttributeName: selected ? VBColorTitleText() : VBColorShadow()};
        NSSize tagSize = [tag sizeWithAttributes:tagAttrs];
        [tag drawAtPoint:NSMakePoint(NSWidth(self.bounds) - tagSize.width - 8, NSMinY(rect) + 3)
          withAttributes:tagAttrs];
    }

    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawTypeTag:(NSString *)tag atRow:(NSRect)row
{
    NSDictionary *attrs = @{NSFontAttributeName: VBFontUISmall(),
                            NSForegroundColorAttributeName: VBColorShadow()};
    NSSize size = [tag sizeWithAttributes:attrs];
    [tag drawAtPoint:NSMakePoint(NSWidth(self.bounds) - size.width - 8, NSMinY(row) + 3) withAttributes:attrs];
}

- (void)drawExpandBoxAt:(NSPoint)point expanded:(BOOL)expanded
{
    NSRect box = NSMakeRect(point.x, point.y, 9, 9);
    VBFillFace(box);
    [[VBColorShadow() colorWithAlphaComponent:0.95] setFill];
    NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box), 9, 1));
    NSRectFill(NSMakeRect(NSMinX(box), NSMinY(box), 1, 9));
    [[VBColorLight() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(NSMinX(box) + 1, NSMaxY(box) - 1, 8, 1));
    NSRectFill(NSMakeRect(NSMaxX(box) - 1, NSMinY(box) + 1, 1, 8));

    [VBColorText() setFill];
    NSRectFill(NSMakeRect(NSMinX(box) + 2, NSMidY(box), 5, 1));
    if (!expanded) NSRectFill(NSMakeRect(NSMidX(box), NSMinY(box) + 2, 1, 5));
}

- (void)drawFolderIconInRect:(NSRect)rect
{
    NSColor *yellow = [NSColor colorWithSRGBRed:1.0 green:0.86 blue:0.30 alpha:1];
    NSRect body = NSMakeRect(NSMinX(rect), NSMinY(rect) + 3, NSWidth(rect), NSHeight(rect) - 4);
    [yellow setFill];
    NSRectFill(body);
    NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect) + 1, 7, 3));
    [[VBColorText() colorWithAlphaComponent:0.8] setStroke];
    [NSBezierPath strokeRect:NSMakeRect(NSMinX(body) + 0.5, NSMinY(body) + 0.5,
                                        NSWidth(body) - 1, NSHeight(body) - 1)];
    [[VBColorText() colorWithAlphaComponent:0.8] setStroke];
    [NSBezierPath strokeRect:NSMakeRect(NSMinX(rect) + 0.5, NSMinY(rect) + 1.5, 6, 2)];
}

- (void)drawItemIcon:(VbItem *)item inRect:(NSRect)rect
{
    if (item->kind == VB_ITEM_FORM) {
        [VBColorWindow() setFill];
        NSRectFill(rect);
        [[VBColorText() colorWithAlphaComponent:0.9] setStroke];
        [NSBezierPath strokeRect:NSMakeRect(NSMinX(rect) + 0.5, NSMinY(rect) + 0.5,
                                            NSWidth(rect) - 1, NSHeight(rect) - 1)];
        [VBColorTitleBar() setFill];
        NSRectFill(NSMakeRect(NSMinX(rect) + 2, NSMinY(rect) + 2, NSWidth(rect) - 4, 4));
        [[VBColorShadow() colorWithAlphaComponent:0.8] setStroke];
        [NSBezierPath strokeRect:NSMakeRect(NSMinX(rect) + 3.5, NSMinY(rect) + 8.5, 8, 4)];
        return;
    }
    if (item->kind == VB_ITEM_MODULE) {
        [VBColorWindow() setFill];
        NSRectFill(rect);
        [[VBColorText() colorWithAlphaComponent:0.9] setStroke];
        [NSBezierPath strokeRect:NSMakeRect(NSMinX(rect) + 1.5, NSMinY(rect) + 0.5,
                                            NSWidth(rect) - 3, NSHeight(rect) - 1)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(rect) + 4, NSMinY(rect) + 5)
                                  toPoint:NSMakePoint(NSMaxX(rect) - 4, NSMinY(rect) + 5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(rect) + 4, NSMinY(rect) + 8)
                                  toPoint:NSMakePoint(NSMaxX(rect) - 4, NSMinY(rect) + 8)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(rect) + 4, NSMinY(rect) + 11)
                                  toPoint:NSMakePoint(NSMaxX(rect) - 7, NSMinY(rect) + 11)];
        return;
    }
    [VBColorWindow() setFill];
    NSRectFill(rect);
    [[VBColorText() colorWithAlphaComponent:0.9] setStroke];
    [NSBezierPath strokeRect:NSInsetRect(rect, 1.5, 0.5)];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.window makeFirstResponder:self];

    NSRect rootRow = [self rootRowRect];
    if (NSPointInRect(point, NSMakeRect(2, NSMinY(rootRow), NSWidth(self.bounds), kRowHeight))) {
        _expanded = !_expanded;
        [self setNeedsDisplay:YES];
        return;
    }

    NSInteger row = [self rowAtPoint:point];
    if (row <= 0) return;
    NSUInteger index = (NSUInteger)(row - 1);
    if (index >= _items.count) return;
    VbItem *item = (VbItem *)_items[index].pointerValue;
    _selected = item;
    [self setNeedsDisplay:YES];
    if (event.clickCount >= 2) {
        if (self.delegate) [self.delegate projectOutline:self didActivateItem:item];
    } else if (self.delegate) {
        [self.delegate projectOutline:self didSelectItem:item];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row != _hoverRow) {
        _hoverRow = (int)row;
        [self setNeedsDisplay:YES];
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        if (area.owner == self) [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow |
                                                                 NSTrackingInVisibleRect)
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == 125 || event.keyCode == 126) {
        NSInteger index = 0;
        if (_selected) {
            for (NSUInteger i = 0; i < _items.count; i++) {
                if ((VbItem *)_items[i].pointerValue == _selected) { index = (NSInteger)i; break; }
            }
        }
        index += (event.keyCode == 125) ? 1 : -1;
        if (index >= 0 && index < (NSInteger)_items.count) {
            _selected = (VbItem *)_items[(NSUInteger)index].pointerValue;
            [self setNeedsDisplay:YES];
            if (self.delegate) [self.delegate projectOutline:self didSelectItem:_selected];
            return;
        }
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (_selected && self.delegate) {
            [self.delegate projectOutline:self didActivateItem:_selected];
            return;
        }
    }
    [super keyDown:event];
}

@end
