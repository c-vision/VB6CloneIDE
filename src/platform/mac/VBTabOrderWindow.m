#import "VBTabOrderWindow.h"
#import "VBTheme.h"

static const CGFloat kDialogWidth = 340.0;
static const CGFloat kDialogHeight = 262.0;
static const CGFloat kRowHeight = 17.0;

@implementation VBTabOrderModel {
    NSMutableArray<NSValue *> *_ordered;
}

- (instancetype)initWithContainer:(VbControl *)container
{
    self = [super init];
    if (!self) return nil;
    _container = container;
    _ordered = [NSMutableArray array];
    _selectedIndex = -1;
    if (container && container->nchildren > 0) {
        for (int i = 0; i < container->nchildren; i++) {
            VbControl *child = container->children[i];
            const char *type = child->type ? child->type : "";
            /* VB6 lists the focusable controls; keep any control that already has a
               TabIndex (labels in real .frm files can carry one) so nothing is lost. */
            if (!vb_control_visible(child)) continue;
            if (vb_control_is_container(type)) continue;
            if (strcmp(type, "VB.Timer") == 0 || strcmp(type, "VB.Menu") == 0) continue;
            if (!vb_control_can_tab(child) && !vb_control_has(child, "TabIndex")) continue;
            [_ordered addObject:[NSValue valueWithPointer:child]];
        }
        /* Stable sort by TabIndex, keeping z-order for ties or missing indices. */
        for (NSUInteger i = 1; i < _ordered.count; i++) {
            NSValue *key = _ordered[i];
            NSInteger rank = [self rankOf:(VbControl *)key.pointerValue];
            NSUInteger j = i;
            while (j > 0 && [self rankOf:(VbControl *)_ordered[j - 1].pointerValue] > rank) {
                _ordered[j] = _ordered[j - 1];
                j--;
            }
            _ordered[j] = key;
        }
    }
    if (_ordered.count > 0) _selectedIndex = 0;
    return self;
}

- (NSInteger)rankOf:(VbControl *)control
{
    int index = vb_control_tab_index(control, -1);
    return index < 0 ? 0x3FFFFFFF : index;
}

- (NSUInteger)count
{
    return _ordered.count;
}

- (NSString *)titleAtIndex:(NSUInteger)index
{
    if (index >= _ordered.count) return @"";
    VbControl *control = (VbControl *)_ordered[index].pointerValue;
    if (!control || !control->name) return @"";
    return [NSString stringWithUTF8String:control->name];
}

- (VbControl *)controlAtIndex:(NSUInteger)index
{
    if (index >= _ordered.count) return NULL;
    return (VbControl *)_ordered[index].pointerValue;
}

- (BOOL)moveSelectionUp
{
    if (self.selectedIndex <= 0 || self.selectedIndex >= (NSInteger)_ordered.count) return NO;
    [_ordered exchangeObjectAtIndex:(NSUInteger)self.selectedIndex withObjectAtIndex:(NSUInteger)(self.selectedIndex - 1)];
    self.selectedIndex -= 1;
    return YES;
}

- (BOOL)moveSelectionDown
{
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)_ordered.count - 1) return NO;
    [_ordered exchangeObjectAtIndex:(NSUInteger)self.selectedIndex withObjectAtIndex:(NSUInteger)(self.selectedIndex + 1)];
    self.selectedIndex += 1;
    return YES;
}

- (void)apply
{
    int count = (int)_ordered.count;
    VbControl **list;
    if (!self.container || count == 0) return;
    list = (VbControl **)calloc((size_t)count, sizeof(VbControl *));
    if (!list) return;
    for (int i = 0; i < count; i++) list[i] = (VbControl *)_ordered[(NSUInteger)i].pointerValue;
    vb_control_apply_tab_order(self.container, list, count);
    free(list);
}

@end

#pragma mark - Dialog view

@interface VBTabOrderView : NSView <NSWindowDelegate>
@property (nonatomic, strong) VBTabOrderModel *model;
@property (nonatomic, readonly) BOOL applied;
- (instancetype)initWithFrame:(NSRect)frameRect model:(VBTabOrderModel *)model;
@end

@implementation VBTabOrderView {
    NSInteger _pressedButton; /* 0 none, 1 up, 2 down, 3 ok, 4 cancel */
    NSInteger _topRow;
    BOOL _modal;
}

- (instancetype)initWithFrame:(NSRect)frameRect model:(VBTabOrderModel *)model
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _model = model;
    _pressedButton = 0;
    _topRow = 0;
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (NSRect)listRect
{
    return NSMakeRect(12, 32, 240, NSHeight(self.bounds) - 74);
}

- (NSInteger)visibleRows
{
    return (NSInteger)floor((NSHeight([self listRect]) - 4) / kRowHeight);
}

- (void)ensureSelectionVisible
{
    NSInteger visible = [self visibleRows];
    NSInteger selected = self.model.selectedIndex;
    if (visible <= 0 || selected < 0) return;
    if (selected < _topRow) _topRow = selected;
    if (selected >= _topRow + visible) _topRow = selected - visible + 1;
    if (_topRow < 0) _topRow = 0;
}

- (NSRect)rectForRow:(NSInteger)row
{
    NSRect list = [self listRect];
    return NSMakeRect(NSMinX(list) + 2, NSMinY(list) + 2 + (row - _topRow) * kRowHeight,
                      NSWidth(list) - 4, kRowHeight);
}

- (NSInteger)rowAtPoint:(NSPoint)point
{
    NSRect list = [self listRect];
    if (!NSPointInRect(point, list)) return -1;
    NSInteger row = _topRow + (NSInteger)floor((point.y - NSMinY(list) - 2) / kRowHeight);
    if (row < 0 || row >= (NSInteger)self.model.count) return -1;
    return row;
}

- (NSRect)rectForButton:(NSInteger)button
{
    switch (button) {
        case 1: return NSMakeRect(262, 32, 30, 26);
        case 2: return NSMakeRect(262, 62, 30, 26);
        case 3: return NSMakeRect(NSWidth(self.bounds) - 170, NSHeight(self.bounds) - 32, 75, 23);
        default: return NSMakeRect(NSWidth(self.bounds) - 87, NSHeight(self.bounds) - 32, 75, 23);
    }
}

- (NSInteger)buttonAtPoint:(NSPoint)point
{
    for (NSInteger button = 1; button <= 4; button++) {
        if (NSPointInRect(point, [self rectForButton:button])) return button;
    }
    return 0;
}

- (BOOL)canMoveUp { return self.model.selectedIndex > 0; }
- (BOOL)canMoveDown { return self.model.selectedIndex >= 0 &&
                             self.model.selectedIndex < (NSInteger)self.model.count - 1; }

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);

    NSString *container = self.model.container && self.model.container->name
                              ? [NSString stringWithUTF8String:self.model.container->name]
                              : @"";
    NSString *caption = [NSString stringWithFormat:@"Tab order for %@", container];
    [caption drawInRect:NSMakeRect(12, 10, NSWidth(self.bounds) - 24, 16)
         withAttributes:@{NSFontAttributeName: VBFontUI(),
                          NSForegroundColorAttributeName: VBColorText()}];

    NSRect list = [self listRect];
    [VBColorWindow() setFill];
    NSRectFill(list);
    VBDrawSunkenBevel(list);
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:NSInsetRect(list, 2, 2)];
    NSDictionary *attrs = @{NSFontAttributeName: VBFontUI(),
                            NSForegroundColorAttributeName: VBColorText()};
    NSDictionary *selectedAttrs = @{NSFontAttributeName: VBFontUI(),
                                    NSForegroundColorAttributeName: VBColorTitleText()};
    NSInteger rows = (NSInteger)self.model.count;
    for (NSInteger row = _topRow; row < rows; row++) {
        NSRect rowRect = [self rectForRow:row];
        if (NSMinY(rowRect) > NSMaxY(list)) break;
        NSString *title = [self.model titleAtIndex:(NSUInteger)row];
        if (row == self.model.selectedIndex) {
            [VBColorSelection() setFill];
            NSRectFill(rowRect);
            [title drawInRect:NSInsetRect(rowRect, 2, 1) withAttributes:selectedAttrs];
        } else {
            [title drawInRect:NSInsetRect(rowRect, 2, 1) withAttributes:attrs];
        }
    }
    [NSGraphicsContext restoreGraphicsState];

    /* Up / down arrow buttons, disabled at the ends of the list. */
    NSRect up = [self rectForButton:1];
    NSRect down = [self rectForButton:2];
    VBDrawClassicButton(up, _pressedButton == 1);
    VBDrawClassicButton(down, _pressedButton == 2);
    NSColor *upColor = [self canMoveUp] ? VBColorText() : [VBColorText() colorWithAlphaComponent:0.3];
    NSColor *downColor = [self canMoveDown] ? VBColorText() : [VBColorText() colorWithAlphaComponent:0.3];
    VBDrawClassicArrow(NSMakeRect(NSMidX(up) - 4, NSMidY(up) - 3, 8, 6), YES, upColor);
    VBDrawClassicArrow(NSMakeRect(NSMidX(down) - 4, NSMidY(down) - 3, 8, 6), NO, downColor);

    /* OK / Cancel. */
    NSRect ok = [self rectForButton:3];
    NSRect cancel = [self rectForButton:4];
    VBDrawClassicButton(ok, _pressedButton == 3);
    VBDrawClassicButton(cancel, _pressedButton == 4);
    [[VBColorText() colorWithAlphaComponent:0.85] setStroke];
    [NSBezierPath strokeRect:NSInsetRect(ok, 2.5, 2.5)];
    NSDictionary *buttonAttrs = @{NSFontAttributeName: VBFontUI(),
                                  NSForegroundColorAttributeName: VBColorText()};
    {
        NSString *title = @"OK";
        NSSize size = [title sizeWithAttributes:buttonAttrs];
        [title drawAtPoint:NSMakePoint(NSMidX(ok) - size.width / 2.0, NSMidY(ok) - size.height / 2.0)
            withAttributes:buttonAttrs];
        title = @"Cancel";
        size = [title sizeWithAttributes:buttonAttrs];
        [title drawAtPoint:NSMakePoint(NSMidX(cancel) - size.width / 2.0, NSMidY(cancel) - size.height / 2.0)
            withAttributes:buttonAttrs];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger button = [self buttonAtPoint:point];
    _pressedButton = button;
    if (button == 0) {
        NSInteger row = [self rowAtPoint:point];
        if (row >= 0) self.model.selectedIndex = row;
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger button = [self buttonAtPoint:point];
    if (button != 0 && button == _pressedButton) {
        _pressedButton = 0;
        switch (button) {
            case 1:
                if ([self.model moveSelectionUp]) [self ensureSelectionVisible];
                break;
            case 2:
                if ([self.model moveSelectionDown]) [self ensureSelectionVisible];
                break;
            case 3:
                [self.model apply];
                _applied = YES;
                [self finish];
                return;
            default:
                [self finish];
                return;
        }
        [self setNeedsDisplay:YES];
        return;
    }
    _pressedButton = 0;
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
    switch (event.keyCode) {
        case 126: /* up */
            if ([self.model moveSelectionUp]) [self ensureSelectionVisible];
            break;
        case 125: /* down */
            if ([self.model moveSelectionDown]) [self ensureSelectionVisible];
            break;
        case 36:
        case 76:
            [self.model apply];
            _applied = YES;
            [self finish];
            return;
        case 53:
            [self finish];
            return;
        default:
            [super keyDown:event];
            return;
    }
    [self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent *)event
{
    NSInteger rows = (NSInteger)self.model.count;
    NSInteger visible = [self visibleRows];
    NSInteger top = _topRow - (NSInteger)event.scrollingDeltaY / 17;
    if (top < 0) top = 0;
    if (visible > 0 && top > MAX(0, rows - visible)) top = MAX(0, rows - visible);
    if (top != _topRow) {
        _topRow = top;
        [self setNeedsDisplay:YES];
    }
}

- (void)finish
{
    if (_modal) {
        _modal = NO;
        [NSApp stopModal];
    }
    [self.window orderOut:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
    (void)notification;
    if (_modal) {
        _modal = NO;
        [NSApp stopModal];
    }
}

- (BOOL)runModal
{
    NSWindow *window = self.window;
    window.delegate = self;
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:self];
    _modal = YES;
    [NSApp runModalForWindow:window];
    [window orderOut:nil];
    [window close];
    return _applied;
}

@end

@implementation VBTabOrderWindow

+ (BOOL)runForContainer:(VbControl *)container
{
    VBTabOrderModel *model = [[VBTabOrderModel alloc] initWithContainer:container];
    if (!container || model.count < 1) {
        NSBeep();
        return NO;
    }
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kDialogWidth, kDialogHeight)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Tab Order";
    window.releasedWhenClosed = NO;
    window.backgroundColor = VBColorFace();
    VBTabOrderView *view = [[VBTabOrderView alloc] initWithFrame:NSMakeRect(0, 0, kDialogWidth, kDialogHeight)
                                                           model:model];
    window.contentView = view;
    BOOL applied = [view runModal];
    return applied;
}

@end
