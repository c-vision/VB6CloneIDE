#import "VBTheme.h"

static NSColor *rgb(int r, int g, int b)
{
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

NSColor *VBColorFace(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorLight(void) { return rgb(0xFF, 0xFF, 0xFF); }
NSColor *VBColorShadow(void) { return rgb(0x80, 0x80, 0x80); }
NSColor *VBColorDarkShadow(void) { return rgb(0x00, 0x00, 0x00); }
NSColor *VBColorWindow(void) { return rgb(0xFF, 0xFF, 0xFF); }
NSColor *VBColorText(void) { return rgb(0x00, 0x00, 0x00); }
NSColor *VBColorTitleBar(void) { return rgb(0x00, 0x00, 0x80); }
NSColor *VBColorTitleInactive(void) { return rgb(0x80, 0x80, 0x80); }
NSColor *VBColorTitleText(void) { return rgb(0xFF, 0xFF, 0xFF); }
NSColor *VBColorSelection(void) { return rgb(0x00, 0x00, 0x80); }
NSColor *VBColorGrid(void) { return rgb(0x80, 0x80, 0x80); }
NSColor *VBColorCodeBackground(void) { return rgb(0xFF, 0xFF, 0xFF); }
NSColor *VBColorCodeText(void) { return rgb(0x00, 0x00, 0x00); }
NSColor *VBColorKeyword(void) { return rgb(0x00, 0x00, 0xFF); }
NSColor *VBColorComment(void) { return rgb(0x00, 0x80, 0x00); }
NSColor *VBColorString(void) { return rgb(0x00, 0x00, 0x00); }
NSColor *VBColorNumber(void) { return rgb(0x00, 0x00, 0x00); }
NSColor *VBColorBuiltin(void) { return rgb(0x00, 0x00, 0xFF); }
NSColor *VBColorConstant(void) { return rgb(0x00, 0x00, 0x80); }
NSColor *VBColorType(void) { return rgb(0x00, 0x00, 0xFF); }
NSColor *VBColorGutter(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorGutterText(void) { return rgb(0x80, 0x80, 0x80); }

NSColor *VBColorChromeTop(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorChromeBottom(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorPanel(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorPanelAlt(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorPanelBorder(void) { return rgb(0x80, 0x80, 0x80); }
NSColor *VBColorMutedText(void) { return rgb(0x40, 0x40, 0x40); }
NSColor *VBColorAccent(void) { return rgb(0x00, 0x00, 0x80); }
NSColor *VBColorAccentSoft(void) { return rgb(0xC0, 0xC0, 0xC0); }
NSColor *VBColorHover(void) { return rgb(0xD4, 0xD0, 0xC8); }
NSColor *VBColorRunning(void) { return rgb(0x00, 0x80, 0x00); }
NSColor *VBColorCurrentLine(void) { return rgb(0xFF, 0xFF, 0xFF); }
NSColor *VBColorBreakLine(void) { return rgb(0xFF, 0xFF, 0x80); }
NSColor *VBColorBreakpoint(void) { return rgb(0x80, 0x00, 0x00); }

NSGradient *VBChromeGradient(void)
{
    static NSGradient *gradient;
    if (!gradient) // Flat system face, kept for legacy call sites.
        gradient = [[NSGradient alloc] initWithStartingColor:VBColorFace() endingColor:VBColorFace()];
    return gradient;
}

NSGradient *VBPanelHeaderGradient(void)
{
    static NSGradient *gradient;
    if (!gradient)
        gradient = [[NSGradient alloc] initWithStartingColor:VBColorFace() endingColor:VBColorFace()];
    return gradient;
}

static NSFont *gUI;
static NSFont *gUIBold;
static NSFont *gUISmall;
static NSFont *gUIMedium;
static NSFont *gCode;
static NSFont *gCodeBold;

static NSFont *classicFont(CGFloat size, NSFontWeight weight)
{
    static NSArray<NSString *> *candidates;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        candidates = @[@"Tahoma", @"Verdana", @"Geneva", @"Helvetica"];
    });
    for (NSString *name in candidates) {
        NSFont *font = [NSFont fontWithName:name size:size];
        if (font) return font;
    }
    return [NSFont systemFontOfSize:size weight:weight];
}

NSFont *VBFontUI(void)
{
    if (!gUI) gUI = classicFont(11, NSFontWeightRegular);
    return gUI;
}

NSFont *VBFontUIBold(void)
{
    if (!gUIBold) {
        gUIBold = [NSFontManager.sharedFontManager convertFont:VBFontUI() toHaveTrait:NSBoldFontMask];
        if (!gUIBold) gUIBold = classicFont(11, NSFontWeightBold);
    }
    return gUIBold;
}

NSFont *VBFontUISmall(void)
{
    if (!gUISmall) gUISmall = classicFont(9, NSFontWeightRegular);
    return gUISmall;
}

NSFont *VBFontUIMedium(void)
{
    if (!gUIMedium) gUIMedium = classicFont(12, NSFontWeightBold);
    return gUIMedium;
}

NSFont *VBFontCode(void)
{
    if (!gCode) {
        gCode = [NSFont fontWithName:@"Courier New" size:12];
        if (!gCode) gCode = [NSFont userFixedPitchFontOfSize:12];
    }
    return gCode;
}

NSFont *VBFontCodeBold(void)
{
    if (!gCodeBold) {
        gCodeBold = [NSFont fontWithName:@"Courier New Bold" size:12];
        if (!gCodeBold) gCodeBold = [NSFontManager.sharedFontManager convertFont:VBFontCode() toHaveTrait:NSBoldFontMask];
        if (!gCodeBold) gCodeBold = VBFontCode();
    }
    return gCodeBold;
}

double VBTwipsToPoints(int twips)
{
    return (double)twips * VB_SCALE;
}

int VBPointsToTwips(double points)
{
    return (int)(points / VB_SCALE + (points < 0 ? -0.5 : 0.5));
}

static void fill(NSRect rect, NSColor *color)
{
    [color setFill];
    NSRectFill(rect);
}

static void edge(NSRect rect, NSColor *leftTop, NSColor *rightBottom, CGFloat inset)
{
    NSRect r = NSInsetRect(rect, inset, inset);
    if (r.size.width < 1 || r.size.height < 1) return;
    [leftTop setFill];
    NSRectFill(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), 1));
    NSRectFill(NSMakeRect(NSMinX(r), NSMinY(r), 1, NSHeight(r)));
    [rightBottom setFill];
    NSRectFill(NSMakeRect(NSMinX(r), NSMaxY(r) - 1, NSWidth(r), 1));
    NSRectFill(NSMakeRect(NSMaxX(r) - 1, NSMinY(r), 1, NSHeight(r)));
}

void VBFillFace(NSRect rect)
{
    fill(rect, VBColorFace());
}

void VBDrawRaisedBevel(NSRect rect)
{
    VBFillFace(rect);
    edge(rect, VBColorLight(), VBColorShadow(), 0);
    edge(rect, VBColorFace(), VBColorDarkShadow(), 1);
}

void VBDrawPressedBevel(NSRect rect)
{
    VBFillFace(rect);
    edge(rect, VBColorShadow(), VBColorLight(), 0);
    edge(rect, VBColorDarkShadow(), VBColorFace(), 1);
}

void VBDrawSunkenBevel(NSRect rect)
{
    fill(rect, VBColorWindow());
    edge(rect, VBColorShadow(), VBColorLight(), 0);
    edge(rect, VBColorDarkShadow(), VBColorFace(), 1);
}

void VBDrawEtchedBorder(NSRect rect)
{
    edge(rect, VBColorShadow(), VBColorLight(), 0);
    edge(rect, VBColorLight(), VBColorShadow(), 1);
}

void VBDrawPanelBorder(NSRect rect)
{
    edge(rect, VBColorShadow(), VBColorLight(), 0);
    edge(rect, VBColorLight(), VBColorShadow(), 1);
}

void VBDrawTitleBar(NSRect rect, NSString *title, BOOL active,
                    BOOL closeBox, BOOL minimizeBox, BOOL maximizeBox)
{
    fill(rect, active ? VBColorTitleBar() : VBColorTitleInactive());
    CGFloat right = NSMaxX(rect) - 2;
    CGFloat top = NSMidY(rect) - 7;
    if (closeBox) {
        NSRect box = NSMakeRect(right - 15, top, 15, 14);
        VBDrawClassicButton(box, NO);
        [VBColorText() setFill];
        NSRectFill(NSMakeRect(NSMinX(box) + 5, NSMinY(box) + 5, 5, 1));
        NSRectFill(NSMakeRect(NSMinX(box) + 5, NSMinY(box) + 8, 5, 1));
        NSRectFill(NSMakeRect(NSMinX(box) + 5, NSMinY(box) + 6, 1, 2));
        NSRectFill(NSMakeRect(NSMinX(box) + 9, NSMinY(box) + 6, 1, 2));
        right -= 17;
    }
    if (maximizeBox) {
        NSRect box = NSMakeRect(right - 15, top, 15, 14);
        VBDrawClassicButton(box, NO);
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(NSMinX(box) + 4.5, NSMinY(box) + 4.5, 6, 5)];
        [VBColorText() setFill];
        NSRectFill(NSMakeRect(NSMinX(box) + 4, NSMinY(box) + 4, 7, 1));
        right -= 17;
    }
    if (minimizeBox) {
        NSRect box = NSMakeRect(right - 15, top, 15, 14);
        VBDrawClassicButton(box, NO);
        [VBColorText() setFill];
        NSRectFill(NSMakeRect(NSMinX(box) + 4, NSMinY(box) + 9, 7, 2));
        right -= 17;
    }

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{
        NSFontAttributeName: VBFontUIBold(),
        NSForegroundColorAttributeName: active ? VBColorTitleText() : rgb(0xD0, 0xD0, 0xD0),
        NSParagraphStyleAttributeName: style
    };
    CGFloat maxWidth = right - NSMinX(rect) - 8;
    [title drawInRect:NSMakeRect(NSMinX(rect) + 3, NSMidY(rect) - 8, MAX(0, maxWidth), 16)
       withAttributes:attrs];
}

void VBDrawClassicButton(NSRect rect, BOOL pressed)
{
    if (pressed) VBDrawPressedBevel(rect);
    else VBDrawRaisedBevel(rect);
}

void VBDrawClassicCheck(NSRect box, int state)
{
    fill(box, VBColorWindow());
    edge(box, VBColorShadow(), VBColorLight(), 0);
    edge(box, VBColorDarkShadow(), VBColorFace(), 1);
    if (state) {
        [VBColorText() setStroke];
        NSBezierPath *check = [NSBezierPath bezierPath];
        [check moveToPoint:NSMakePoint(NSMinX(box) + 3, NSMidY(box))];
        [check lineToPoint:NSMakePoint(NSMinX(box) + 5, NSMaxY(box) - 4)];
        [check lineToPoint:NSMakePoint(NSMaxX(box) - 3, NSMinY(box) + 4)];
        [check setLineWidth:1.6];
        [check stroke];
    }
}

void VBDrawClassicRadio(NSRect box, int state)
{
    fill(box, VBColorWindow());
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 0.5, 0.5)];
    [[VBColorShadow() colorWithAlphaComponent:0.9] setStroke];
    [circle setLineWidth:1];
    [circle stroke];
    if (state) {
        fill(NSInsetRect(box, 3, 3), VBColorText());
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 3, 3)] fill];
    }
}

void VBDrawClassicArrow(NSRect rect, BOOL down, NSColor *color)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    if (down) {
        [path moveToPoint:NSMakePoint(NSMinX(rect) + 2, NSMinY(rect) + 4)];
        [path lineToPoint:NSMakePoint(NSMaxX(rect) - 2, NSMinY(rect) + 4)];
        [path lineToPoint:NSMakePoint(NSMidX(rect), NSMaxY(rect) - 4)];
    } else {
        [path moveToPoint:NSMakePoint(NSMinX(rect) + 2, NSMaxY(rect) - 4)];
        [path lineToPoint:NSMakePoint(NSMaxX(rect) - 2, NSMaxY(rect) - 4)];
        [path lineToPoint:NSMakePoint(NSMidX(rect), NSMinY(rect) + 4)];
    }
    [path closePath];
    [color setFill];
    [path fill];
}

void VBDrawToolbarButton(NSRect rect, BOOL pressed, BOOL hovered)
{
    if (pressed) {
        VBDrawPressedBevel(rect);
    } else if (hovered) {
        VBFillFace(rect);
        edge(rect, VBColorLight(), VBColorShadow(), 0);
    } else {
        VBFillFace(rect);
    }
}

void VBDrawClassicIcon(NSRect rect, NSString *kind)
{
    CGFloat x = NSMinX(rect);
    CGFloat y = NSMinY(rect);
    CGFloat w = NSWidth(rect);
    CGFloat h = NSHeight(rect);
    [VBColorText() setStroke];
    [NSBezierPath setDefaultLineWidth:1.2];

    if ([kind isEqualToString:@"new"]) {
        [VBColorWindow() setFill];
        NSRect page = NSMakeRect(x + 5, y + 2, w - 10, h - 5);
        NSRectFill(page);
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSInsetRect(page, 0.5, 0.5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(page) - 4, NSMinY(page))
                                  toPoint:NSMakePoint(NSMaxX(page) - 4, NSMinY(page) + 4)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(page) - 4, NSMinY(page) + 4)
                                  toPoint:NSMakePoint(NSMaxX(page), NSMinY(page) + 4)];
        return;
    }
    if ([kind isEqualToString:@"open"]) {
        NSColor *folder = rgb(0xFF, 0xD7, 0x4A);
        fill(NSMakeRect(x + 2, y + 4, w - 5, h - 7), folder);
        [[VBColorText() colorWithAlphaComponent:0.65] setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 2.5, y + 4.5, w - 6, h - 8)];
        fill(NSMakeRect(x + 2, y + 3, 5, 2), folder);
        return;
    }
    if ([kind isEqualToString:@"save"]) {
        [VBColorText() setStroke];
        fill(NSMakeRect(x + 3, y + 3, w - 6, h - 6), rgb(0x20, 0x20, 0x20));
        fill(NSMakeRect(x + 6, y + 3, w - 12, 5), VBColorWindow());
        fill(NSMakeRect(x + 5, y + h - 8, w - 10, 5), rgb(0xA0, 0xA0, 0xA0));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 3.5, w - 7, h - 7)];
        return;
    }
    if ([kind isEqualToString:@"cut"] || [kind isEqualToString:@"copy"] || [kind isEqualToString:@"paste"]) {
        if ([kind isEqualToString:@"paste"]) {
            [VBColorWindow() setFill];
            NSRectFill(NSMakeRect(x + 4, y + 4, w - 8, h - 7));
            [VBColorShadow() setStroke];
            [NSBezierPath strokeRect:NSMakeRect(x + 4.5, y + 4.5, w - 9, h - 8)];
            fill(NSMakeRect(x + 6, y + 2, w - 12, 3), rgb(0xA0, 0x60, 0x20));
            [VBColorText() setStroke];
            [NSBezierPath strokeRect:NSMakeRect(x + 6.5, y + 2.5, w - 13, 2)];
            return;
        }
        [VBColorText() setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 4, y + 3)
                                  toPoint:NSMakePoint(x + w - 5, y + h - 7)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + w - 5, y + 3)
                                  toPoint:NSMakePoint(x + 4, y + h - 7)];
        fill(NSMakeRect(x + 2, y + 1, 3, 3), rgb(0xE0, 0xE0, 0xE0));
        fill(NSMakeRect(x + w - 6, y + 1, 3, 3), rgb(0xE0, 0xE0, 0xE0));
        [[VBColorText() colorWithAlphaComponent:0.7] setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 2.5, y + 1.5, 2, 2)];
        [NSBezierPath strokeRect:NSMakeRect(x + w - 5.5, y + 1.5, 2, 2)];
        if ([kind isEqualToString:@"cut"]) {
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + w - 6, y + h - 10)
                                      toPoint:NSMakePoint(x + w - 3, y + h - 6)];
        }
        [VBColorText() setFill];
        fill(NSMakeRect(x + 6, y + h - 6, w - 11, 1), VBColorText());
        return;
    }
    if ([kind isEqualToString:@"start"]) {
        NSBezierPath *tri = [NSBezierPath bezierPath];
        [tri moveToPoint:NSMakePoint(x + 4, y + 2)];
        [tri lineToPoint:NSMakePoint(x + 4, y + h - 2)];
        [tri lineToPoint:NSMakePoint(x + w - 3, y + h / 2)];
        [tri closePath];
        [rgb(0x00, 0x60, 0x00) setFill];
        [tri fill];
        [VBColorText() setStroke];
        [tri setLineWidth:1];
        [tri stroke];
        return;
    }
    if ([kind isEqualToString:@"break"]) {
        fill(NSMakeRect(x + 4, y + 3, 3, h - 6), rgb(0x00, 0x00, 0x80));
        fill(NSMakeRect(x + w - 7, y + 3, 3, h - 6), rgb(0x00, 0x00, 0x80));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 4.5, y + 3.5, 2, h - 7)];
        [NSBezierPath strokeRect:NSMakeRect(x + w - 6.5, y + 3.5, 2, h - 7)];
        return;
    }
    if ([kind isEqualToString:@"end"]) {
        fill(NSMakeRect(x + 4, y + 4, w - 8, h - 8), rgb(0x80, 0x00, 0x00));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 4.5, y + 4.5, w - 9, h - 9)];
        return;
    }
    if ([kind isEqualToString:@"explorer"]) {
        fill(NSMakeRect(x + 2, y + 2, 6, 5), rgb(0xFF, 0xD7, 0x4A));
        fill(NSMakeRect(x + 2, y + 6, w - 4, h - 8), rgb(0xFF, 0xD7, 0x4A));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 2.5, y + 6.5, w - 5, h - 9)];
        [NSBezierPath strokeRect:NSMakeRect(x + 2.5, y + 2.5, 5, 4)];
        return;
    }
    if ([kind isEqualToString:@"properties"]) {
        [VBColorWindow() setFill];
        NSRectFill(NSMakeRect(x + 3, y + 2, w - 6, h - 4));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 2.5, w - 7, h - 5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 3, y + 6)
                                  toPoint:NSMakePoint(x + w - 3, y + 6)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6, y + 9)
                                  toPoint:NSMakePoint(x + w - 5, y + 9)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6, y + 11)
                                  toPoint:NSMakePoint(x + w - 5, y + 11)];
        return;
    }
    if ([kind isEqualToString:@"toolbox"]) {
        [VBColorText() setStroke];
        [NSBezierPath setDefaultLineWidth:1.4];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 3, y + h - 4)
                                  toPoint:NSMakePoint(x + w - 5, y + 4)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 2, y + h - 6)
                                  toPoint:NSMakePoint(x + 6, y + h - 2)];
        fill(NSMakeRect(x + w - 6, y + 2, 4, 4), rgb(0x80, 0x80, 0x80));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + w - 6.5, y + 1.5, 4, 4)];
        return;
    }
    if ([kind isEqualToString:@"browser"]) {
        [VBColorWindow() setFill];
        NSRectFill(NSMakeRect(x + 2, y + 2, w - 5, h - 4));
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 2.5, y + 2.5, w - 6, h - 5)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6, y + 2)
                                  toPoint:NSMakePoint(x + 6, y + h - 2)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 2, y + 6)
                                  toPoint:NSMakePoint(x + w - 2, y + 6)];
        return;
    }
    if ([kind isEqualToString:@"menu"]) {
        fill(NSMakeRect(x + 3, y + 3, w - 6, h - 6), VBColorWindow());
        [VBColorText() setStroke];
        [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 3.5, w - 7, h - 7)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 3, y + 6)
                                  toPoint:NSMakePoint(x + w - 3, y + 6)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 5, y + 9)
                                  toPoint:NSMakePoint(x + w - 5, y + 9)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 5, y + 12)
                                  toPoint:NSMakePoint(x + w - 5, y + 12)];
        return;
    }
    if ([kind isEqualToString:@"undo"]) {
        [VBColorText() setStroke];
        [NSBezierPath setDefaultLineWidth:1.6];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path appendBezierPathWithArcWithCenter:NSMakePoint(x + w / 2, y + h / 2) radius:5
                                         startAngle:30 endAngle:200];
        [path stroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 3, y + 5)
                                  toPoint:NSMakePoint(x + 3, y + 9)];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 3, y + 5)
                                  toPoint:NSMakePoint(x + 7, y + 5)];
        return;
    }
    if ([kind hasPrefix:@"align-"] || [kind hasPrefix:@"same-"] || [kind hasPrefix:@"space-"]) {
        /* Form Editor pictograms: a 1px guide plus two solid bars in the system face color. */
        NSColor *ink = VBColorText();
        [NSBezierPath setDefaultLineWidth:1];
        if ([kind hasPrefix:@"align-"]) {
            BOOL verticalGuide = [kind isEqualToString:@"align-left"] || [kind isEqualToString:@"align-center"] ||
                                 [kind isEqualToString:@"align-right"];
            int guide = 2;
            int lengths[2] = {6, 9};
            if ([kind isEqualToString:@"align-right"] || [kind isEqualToString:@"align-bottom"]) guide = 14;
            if ([kind isEqualToString:@"align-center"] || [kind isEqualToString:@"align-middle"]) guide = 8;
            [ink setStroke];
            if (verticalGuide) {
                [NSBezierPath strokeLineFromPoint:NSMakePoint(x + guide, y + 2)
                                          toPoint:NSMakePoint(x + guide, y + h - 2)];
            } else {
                [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 2, y + guide)
                                          toPoint:NSMakePoint(x + w - 2, y + guide)];
            }
            for (int bar = 0; bar < 2; bar++) {
                int length = lengths[bar];
                int offset = 3 + bar * 5;
                int start = guide + 2;
                if ([kind isEqualToString:@"align-right"] || [kind isEqualToString:@"align-bottom"]) {
                    start = guide - length - 2;
                } else if ([kind isEqualToString:@"align-center"] || [kind isEqualToString:@"align-middle"]) {
                    start = guide - length / 2;
                }
                if (verticalGuide) {
                    fill(NSMakeRect(x + start, y + offset, length, 2), ink);
                } else {
                    fill(NSMakeRect(x + offset, y + start, 2, length), ink);
                }
            }
            return;
        }
        [ink setStroke];
        if ([kind isEqualToString:@"same-width"]) {
            [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 3.5, 9, 4)];
            [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 9.5, 9, 4)];
            return;
        }
        if ([kind isEqualToString:@"same-height"]) {
            [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 3.5, 4, 9)];
            [NSBezierPath strokeRect:NSMakeRect(x + 9.5, y + 3.5, 4, 9)];
            return;
        }
        if ([kind isEqualToString:@"same-size"]) {
            [NSBezierPath strokeRect:NSMakeRect(x + 3.5, y + 3.5, 7, 7)];
            [NSBezierPath strokeRect:NSMakeRect(x + 6.5, y + 6.5, 7, 7)];
            return;
        }
        /* space-h-equal / space-v-equal: two blocks and a double arrow between them */
        if ([kind isEqualToString:@"space-h-equal"]) {
            fill(NSMakeRect(x + 2, y + 3, 3, 10), ink);
            fill(NSMakeRect(x + 12, y + 3, 3, 10), ink);
            CGFloat midY = y + NSHeight(rect) / 2.0;
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6, midY) toPoint:NSMakePoint(x + 11, midY)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6, midY) toPoint:NSMakePoint(x + 8, midY - 2)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6, midY) toPoint:NSMakePoint(x + 8, midY + 2)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 11, midY) toPoint:NSMakePoint(x + 9, midY - 2)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 11, midY) toPoint:NSMakePoint(x + 9, midY + 2)];
            return;
        }
        fill(NSMakeRect(x + 3, y + 2, 10, 3), ink);
        fill(NSMakeRect(x + 3, y + 12, 10, 3), ink);
        {
            CGFloat midX = x + NSWidth(rect) / 2.0;
            [NSBezierPath strokeLineFromPoint:NSMakePoint(midX, y + 5) toPoint:NSMakePoint(midX, y + 11)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(midX, y + 5) toPoint:NSMakePoint(midX - 2, y + 7)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(midX, y + 5) toPoint:NSMakePoint(midX + 2, y + 7)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(midX, y + 11) toPoint:NSMakePoint(midX - 2, y + 9)];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(midX, y + 11) toPoint:NSMakePoint(midX + 2, y + 9)];
        }
        return;
    }
    [VBColorText() setStroke];
    [NSBezierPath strokeRect:NSMakeRect(x + 2.5, y + 2.5, w - 5, h - 5)];
}

void VBDrawStatusPanel(NSRect rect)
{
    fill(rect, VBColorFace());
    edge(rect, VBColorShadow(), VBColorLight(), 0);
    edge(rect, VBColorShadow(), VBColorFace(), 1);
}

/* Small left/right triangle with an optional "jump to end" bar. */
static void drawDataNavArrow(NSRect box, BOOL right, BOOL bar)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat midY = NSMidY(box);
    CGFloat inset = 4;
    if (right) {
        [path moveToPoint:NSMakePoint(NSMinX(box) + inset, midY - 4)];
        [path lineToPoint:NSMakePoint(NSMaxX(box) - inset, midY)];
        [path lineToPoint:NSMakePoint(NSMinX(box) + inset, midY + 4)];
    } else {
        [path moveToPoint:NSMakePoint(NSMaxX(box) - inset, midY - 4)];
        [path lineToPoint:NSMakePoint(NSMinX(box) + inset, midY)];
        [path lineToPoint:NSMakePoint(NSMaxX(box) - inset, midY + 4)];
    }
    [path closePath];
    [VBColorText() setFill];
    [path fill];
    if (bar) {
        NSRectFill(NSMakeRect(right ? NSMaxX(box) - inset - 2 : NSMinX(box) + inset + 1,
                              midY - 4, 1, 8));
    }
}

void VBDrawClassicDataControl(NSRect rect, NSString *caption)
{
    NSRect body;
    NSRect nav;
    int i;
    if (NSIsEmptyRect(rect)) return;
    VBDrawRaisedBevel(rect);
    body = NSInsetRect(rect, 2, 2);
    [VBColorFace() setFill];
    NSRectFill(body);
    nav = NSMakeRect(NSMaxX(body) - 70, NSMinY(body), 68, NSHeight(body));
    for (i = 0; i < 4; i++) {
        NSRect button = NSMakeRect(NSMinX(nav) + i * 17, NSMinY(nav), 16, NSHeight(nav));
        if (NSHeight(button) < 8) continue;
        VBDrawRaisedBevel(button);
        drawDataNavArrow(button, i >= 2, i == 0 || i == 3);
    }
    if (caption.length) {
        NSDictionary *attrs = @{NSFontAttributeName: VBFontUI(),
                                NSForegroundColorAttributeName: VBColorText()};
        NSSize size = [caption sizeWithAttributes:attrs];
        CGFloat y = NSMidY(body) - size.height / 2.0;
        [caption drawAtPoint:NSMakePoint(NSMinX(body) + 5, y) withAttributes:attrs];
    }
}

void VBDrawClassicDataGrid(NSRect rect, int headers, int columnWidth, int rowHeight)
{
    NSRect inner;
    NSRect header = NSZeroRect;
    CGFloat colWidth;
    CGFloat rowHeightPoints;
    NSColor *line = [VBColorShadow() colorWithAlphaComponent:0.35];
    CGFloat x, y;
    if (NSIsEmptyRect(rect)) return;
    [VBColorWindow() setFill];
    NSRectFill(rect);
    VBDrawSunkenBevel(rect);
    inner = NSInsetRect(rect, 2, 2);
    colWidth = columnWidth > 0 ? VBTwipsToPoints(columnWidth) : 80.0;
    rowHeightPoints = rowHeight > 0 ? VBTwipsToPoints(rowHeight) : 17.0;
    if (colWidth < 16) colWidth = 16;
    if (rowHeightPoints < 10) rowHeightPoints = 10;
    if (headers && NSHeight(inner) > 20) {
        header = NSMakeRect(NSMinX(inner), NSMinY(inner), NSWidth(inner), 18);
        [VBColorFace() setFill];
        NSRectFill(header);
        [VBColorShadow() setFill];
        NSRectFill(NSMakeRect(NSMinX(header), NSMaxY(header) - 1, NSWidth(header), 1));
        [VBColorLight() setFill];
        NSRectFill(NSMakeRect(NSMinX(header), NSMaxY(header) - 2, NSWidth(header), 1));
    }
    [line setFill];
    for (x = NSMinX(inner) + colWidth; x < NSMaxX(inner); x += colWidth) {
        NSRectFill(NSMakeRect(floor(x), NSMinY(inner), 1, NSHeight(inner)));
    }
    for (y = NSMaxY(header) + rowHeightPoints; y < NSMaxY(inner); y += rowHeightPoints) {
        NSRectFill(NSMakeRect(NSMinX(inner), floor(y), NSWidth(inner), 1));
    }
}
