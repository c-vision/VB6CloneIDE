#import "VBToolbarView.h"
#import "VBTheme.h"

static const CGFloat kButtonSize = 24.0;
static const CGFloat kGap = 2.0;
static const CGFloat kSeparatorWidth = 7.0;

@implementation VBToolbarView {
    NSArray<NSDictionary *> *_buttons;
    NSMutableDictionary<NSString *, NSNumber *> *_enabled;
    NSInteger _hover;
    NSInteger _pressed;
    NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _enabled = [NSMutableDictionary dictionary];
    _hover = -1;
    _pressed = -1;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setButtons:(NSArray<NSDictionary *> *)buttons
{
    _buttons = [buttons copy];
    [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled forIdentifier:(NSString *)identifier
{
    _enabled[identifier] = @(enabled);
    [self setNeedsDisplay:YES];
}

- (BOOL)isEnabledForIdentifier:(NSString *)identifier
{
    NSNumber *value = _enabled[identifier];
    return value ? value.boolValue : YES;
}

- (NSRect)rectForIdentifier:(NSString *)identifier
{
    for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
        NSDictionary *button = _buttons[(NSUInteger)i];
        if ([button[@"separator"] boolValue]) continue;
        if ([button[@"identifier"] isEqualToString:identifier]) return [self rectForIndex:i];
    }
    return NSZeroRect;
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
}

- (NSRect)rectForIndex:(NSInteger)index
{
    CGFloat x = 4;
    for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
        NSDictionary *button = _buttons[(NSUInteger)i];
        if ([button[@"separator"] boolValue]) {
            if (i == index) return NSMakeRect(x + kSeparatorWidth / 2.0 - 1, 3, 2, NSHeight(self.bounds) - 6);
            x += kSeparatorWidth;
            continue;
        }
        if (i == index) return NSMakeRect(x, 2, kButtonSize, kButtonSize);
        x += kButtonSize + kGap;
    }
    return NSZeroRect;
}

- (NSInteger)indexAtPoint:(NSPoint)point
{
    for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
        if ([_buttons[(NSUInteger)i][@"separator"] boolValue]) continue;
        if (NSPointInRect(point, [self rectForIndex:i])) return i;
    }
    return -1;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);

    for (NSInteger i = 0; i < (NSInteger)_buttons.count; i++) {
        NSDictionary *button = _buttons[(NSUInteger)i];
        if ([button[@"separator"] boolValue]) {
            NSRect line = [self rectForIndex:i];
            [[VBColorShadow() colorWithAlphaComponent:0.85] setFill];
            NSRectFill(NSMakeRect(NSMinX(line), NSMinY(line), 1, NSHeight(line)));
            [[VBColorLight() colorWithAlphaComponent:0.9] setFill];
            NSRectFill(NSMakeRect(NSMinX(line) + 1, NSMinY(line), 1, NSHeight(line)));
            continue;
        }
        NSRect rect = [self rectForIndex:i];
        NSString *identifier = button[@"identifier"];
        BOOL enabled = _enabled[identifier] ? _enabled[identifier].boolValue : YES;
        BOOL hovered = (i == _hover) && enabled;
        BOOL pressed = (i == _pressed) && enabled;
        VBDrawToolbarButton(rect, pressed, hovered);

        NSRect iconRect = NSMakeRect(NSMidX(rect) - 8, NSMidY(rect) - 8, 16, 16);
        if (enabled) {
            VBDrawClassicIcon(iconRect, button[@"icon"] ?: identifier);
        } else {
            /* Disabled toolbar buttons draw their icon faded, like the Win9x toolbar. */
            NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
            [icon lockFocus];
            VBDrawClassicIcon(NSMakeRect(0, 0, 16, 16), button[@"icon"] ?: identifier);
            [icon unlockFocus];
            [icon drawInRect:iconRect
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationSourceOver
                    fraction:0.35
              respectFlipped:YES
                       hints:nil];
        }
    }

    [[VBColorLight() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 2, NSWidth(self.bounds), 1));
    [[VBColorShadow() colorWithAlphaComponent:0.85] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexAtPoint:point];
    if (index < 0) return;
    NSString *identifier = _buttons[(NSUInteger)index][@"identifier"];
    BOOL enabled = _enabled[identifier] ? _enabled[identifier].boolValue : YES;
    if (!enabled) return;
    _pressed = index;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_pressed < 0) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexAtPoint:point];
    if (index != _pressed) {
        _pressed = index;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    NSInteger pressed = _pressed;
    _pressed = -1;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexAtPoint:point];
    [self setNeedsDisplay:YES];
    if (pressed >= 0 && pressed == index) {
        NSString *identifier = _buttons[(NSUInteger)index][@"identifier"];
        [self.delegate toolbarView:self didSelectIdentifier:identifier];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexAtPoint:point];
    if (index != _hover) {
        _hover = index;
        [self setNeedsDisplay:YES];
    }
    NSString *tooltip = index >= 0 ? _buttons[(NSUInteger)index][@"tooltip"] : nil;
    self.toolTip = tooltip;
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    if (_hover != -1) {
        _hover = -1;
        [self setNeedsDisplay:YES];
    }
}

@end
