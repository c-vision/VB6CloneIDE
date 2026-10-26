#import "VBMenuBarView.h"
#import "VBTheme.h"

@implementation VBMenuBarView {
    NSInteger _openIndex;
    NSRect _openRect;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    _openIndex = -1;
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setTitles:(NSArray<NSString *> *)titles menus:(NSArray<NSMenu *> *)menus
{
    self.titles = titles ?: @[];
    self.menus = menus ?: @[];
    [self setNeedsDisplay:YES];
}

- (NSArray<NSNumber *> *)itemWidths
{
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    NSDictionary *attrs = @{NSFontAttributeName: VBFontUI()};
    for (NSString *title in self.titles) {
        CGFloat width = [title sizeWithAttributes:attrs].width + 16;
        [widths addObject:@(MAX(28, ceil(width)))];
    }
    return widths;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);

    NSDictionary *attrs = @{
        NSFontAttributeName: VBFontUI(),
        NSForegroundColorAttributeName: VBColorText()
    };
    CGFloat x = 2;
    NSArray<NSNumber *> *widths = [self itemWidths];
    for (NSUInteger i = 0; i < self.titles.count; i++) {
        CGFloat width = widths[i].doubleValue;
        NSRect item = NSMakeRect(x, 1, width, NSHeight(self.bounds) - 3);
        if ((NSInteger)i == _openIndex) {
            VBDrawPressedBevel(item);
        }
        NSString *title = self.titles[i];
        NSSize size = [title sizeWithAttributes:attrs];
        [title drawAtPoint:NSMakePoint(NSMidX(item) - size.width / 2.0,
                                       NSMidY(item) - size.height / 2.0)
            withAttributes:attrs];
        x += width;
    }

    [[VBColorShadow() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSArray<NSNumber *> *widths = [self itemWidths];
    CGFloat x = 2;
    for (NSUInteger i = 0; i < self.titles.count && i < self.menus.count; i++) {
        CGFloat width = widths[i].doubleValue;
        NSRect item = NSMakeRect(x, 1, width, NSHeight(self.bounds) - 3);
        if (NSPointInRect(point, item)) {
            _openIndex = (NSInteger)i;
            _openRect = item;
            [self setNeedsDisplay:YES];
            NSMenu *menu = self.menus[i];
            NSPoint screenPoint = [self.window convertPointToScreen:
                                   [self convertPoint:NSMakePoint(NSMinX(item), NSMaxY(item)) toView:nil]];
            [menu popUpMenuPositioningItem:nil atLocation:screenPoint inView:nil];
            _openIndex = -1;
            [self setNeedsDisplay:YES];
            return;
        }
        x += width;
    }
}

@end
