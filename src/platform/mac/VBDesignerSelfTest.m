#import "VBDesignerSelfTest.h"
#import "VBTheme.h"
#import "VBTabOrderWindow.h"

#include "core/vb_parse.h"
#include "core/vb_util.h"

#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void report(NSString *format, ...)
{
    va_list args;
    NSString *line;
    va_start(args, format);
    line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    fprintf(stderr, "designer-selftest: %s\n", line.UTF8String);
}

static BOOL verify(BOOL condition, NSString *message)
{
    if (!condition) report(@"FAIL %@", message);
    return condition;
}

static VbControl *childNamed(VbControl *parent, const char *name)
{
    int i;
    for (i = 0; i < parent->nchildren; i++) {
        VbControl *child = parent->children[i];
        if (child->name && strcmp(child->name, name) == 0) return child;
    }
    return NULL;
}

static int ctlLeft(VbControl *control) { return vb_control_get_int(control, "Left", 0); }
static int ctlTop(VbControl *control) { return vb_control_get_int(control, "Top", 0); }
static int ctlWidth(VbControl *control) { return vb_control_get_int(control, "Width", 0); }
static int ctlHeight(VbControl *control) { return vb_control_get_int(control, "Height", 0); }

static NSString *ctlName(VbControl *control)
{
    if (!control) return @"(null)";
    return control->name ? [NSString stringWithUTF8String:control->name] : @"(unnamed)";
}

static NSEvent *designerEvent(VBDesignerView *designer, NSEventType type, NSPoint point,
                              NSUInteger clickCount, NSEventModifierFlags flags)
{
    NSPoint inWindow = [designer convertPoint:point toView:nil];
    return [NSEvent mouseEventWithType:type
                              location:inWindow
                         modifierFlags:flags
                             timestamp:0
                          windowNumber:designer.window.windowNumber
                               context:nil
                           eventNumber:0
                            clickCount:clickCount
                              pressure:1.0];
}

static void clickAt(VBDesignerView *designer, NSPoint point, NSEventModifierFlags flags)
{
    [designer mouseDown:designerEvent(designer, NSEventTypeLeftMouseDown, point, 1, flags)];
    [designer mouseUp:designerEvent(designer, NSEventTypeLeftMouseUp, point, 1, flags)];
}

static void dragFromTo(VBDesignerView *designer, NSPoint from, NSPoint to, NSEventModifierFlags flags)
{
    [designer mouseDown:designerEvent(designer, NSEventTypeLeftMouseDown, from, 1, flags)];
    [designer mouseDragged:designerEvent(designer, NSEventTypeLeftMouseDragged, to, 1, flags)];
    [designer mouseUp:designerEvent(designer, NSEventTypeLeftMouseUp, to, 1, flags)];
}

static NSRect unionOfControls(VBDesignerView *designer, VbControl *parent)
{
    NSRect rect = NSZeroRect;
    BOOL first = YES;
    int i;
    for (i = 0; i < parent->nchildren; i++) {
        NSRect r = [designer rectForControl:parent->children[i]];
        if (first) { rect = r; first = NO; }
        else rect = NSUnionRect(rect, r);
    }
    return rect;
}

static int absLeft(VbControl *control, VbControl *root)
{
    int total = 0;
    VbControl *cursor = control;
    while (cursor && cursor != root) {
        total += vb_control_get_int(cursor, "Left", 0);
        cursor = cursor->parent;
    }
    return total;
}

static int absTop(VbControl *control, VbControl *root)
{
    int total = 0;
    VbControl *cursor = control;
    while (cursor && cursor != root) {
        total += vb_control_get_int(cursor, "Top", 0);
        cursor = cursor->parent;
    }
    return total;
}

static NSMenu *formatMenuFromBar(VBMenuBarView *menuBar)
{
    if (!menuBar || menuBar.menus.count < 5) return nil;
    return menuBar.menus[4];
}

static NSMenuItem *itemTitled(NSMenu *menu, NSString *title)
{
    if (!menu) return nil;
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:title]) return item;
    }
    return nil;
}

static NSMenuItem *submenuItemTitled(NSMenu *menu, NSString *parent, NSString *title)
{
    NSMenuItem *parentItem = itemTitled(menu, parent);
    if (!parentItem || !parentItem.submenu) return nil;
    return itemTitled(parentItem.submenu, title);
}

static BOOL fireMenuItem(NSMenuItem *item)
{
    if (!item || !item.action || !item.target) return NO;
    return [NSApp sendAction:item.action to:item.target from:item];
}

BOOL VBRunFormatMenuSelfTest(VBMenuBarView *menuBar, VBDesignerView *designer, VbForm *form)
{
    BOOL ok = YES;
    VbControl *root;
    VbControl *controls[3];
    int lefts[3];
    int tops[3];
    int widths[3];
    int heights[3];
    NSMenuItem *item;
    int i;

    if (!menuBar || !designer || !form || !form->root) {
        report(@"format test: no menu or form");
        return NO;
    }
    root = form->root;
    if (root->nchildren < 3) {
        report(@"format test: fixture needs at least 3 controls");
        return NO;
    }
    controls[0] = childNamed(root, "Text1");
    controls[1] = childNamed(root, "Command1");
    controls[2] = childNamed(root, "Label1");
    if (!controls[0] || !controls[1] || !controls[2]) {
        report(@"format test: fixture needs Text1, Command1 and Label1");
        return NO;
    }
    ok &= verify(designer.selectionCount == 3, @"format test needs three selected controls");

    /* Deterministic arrangement: uneven gaps so the spacing commands have work to do. */
    {
        int layout[3][4] = { {300, 300, 600, 300}, {900, 900, 600, 300}, {2100, 1500, 900, 450} };
        for (i = 0; i < 3; i++) {
            vb_control_set_int(controls[i], "Left", layout[i][0]);
            vb_control_set_int(controls[i], "Top", layout[i][1]);
            vb_control_set_int(controls[i], "Width", layout[i][2]);
            vb_control_set_int(controls[i], "Height", layout[i][3]);
        }
        [designer refresh];
        report(@"format fixture -> Text1 300,300 600x300 | Command1 900,900 600x300 | Label1 2100,1500 900x450");
    }

    /* Horizontal Spacing > Make Equal: gaps 0/600 become 300/300, span preserved */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Horizontal Spacing", @"Make Equal");
    ok &= verify(item != nil && item.enabled, @"Horizontal Spacing > Make Equal must be enabled");
    ok &= verify(fireMenuItem(item), @"Horizontal Spacing > Make Equal must dispatch");
    {
        int spanBefore = (2100 + 900) - 300;
        int gapA = absLeft(controls[1], root) - (absLeft(controls[0], root) + ctlWidth(controls[0]));
        int gapB = absLeft(controls[2], root) - (absLeft(controls[1], root) + ctlWidth(controls[1]));
        int spanAfter = (absLeft(controls[2], root) + ctlWidth(controls[2])) - absLeft(controls[0], root);
        report(@"menu H Spacing Make Equal -> lefts %d/%d/%d gaps %d/%d span %d (was %d)",
               absLeft(controls[0], root), absLeft(controls[1], root), absLeft(controls[2], root),
               gapA, gapB, spanAfter, spanBefore);
        ok &= verify(gapA == 300 && gapB == 300, @"horizontal gaps must become equal");
        ok &= verify(absLeft(controls[0], root) == 300 && absLeft(controls[1], root) == 1200 &&
                     absLeft(controls[2], root) == 2100, @"Make Equal must keep the outer edges fixed");
        ok &= verify(spanAfter == spanBefore, @"horizontal span must be preserved");
    }

    /* Horizontal Spacing > Increase, then Decrease: gap 300 -> 360 -> 300 */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Horizontal Spacing", @"Increase");
    ok &= verify(fireMenuItem(item), @"Horizontal Spacing > Increase must dispatch");
    report(@"menu H Spacing Increase -> lefts %d/%d/%d", absLeft(controls[0], root),
           absLeft(controls[1], root), absLeft(controls[2], root));
    ok &= verify(absLeft(controls[1], root) - (absLeft(controls[0], root) + ctlWidth(controls[0])) == 360,
                 @"Increase must add one grid step (60 twips) to the gap");
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Horizontal Spacing", @"Decrease");
    ok &= verify(fireMenuItem(item), @"Horizontal Spacing > Decrease must dispatch");
    ok &= verify(absLeft(controls[1], root) == 1200 && absLeft(controls[2], root) == 2100,
                 @"Decrease must restore the previous gaps");

    /* Horizontal Spacing > Remove: controls touch */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Horizontal Spacing", @"Remove");
    ok &= verify(item != nil && item.enabled, @"Horizontal Spacing > Remove must be enabled");
    ok &= verify(fireMenuItem(item), @"Horizontal Spacing > Remove must dispatch");
    report(@"menu H Spacing Remove -> lefts %d/%d/%d", absLeft(controls[0], root),
           absLeft(controls[1], root), absLeft(controls[2], root));
    ok &= verify(absLeft(controls[1], root) == absLeft(controls[0], root) + ctlWidth(controls[0]) &&
                 absLeft(controls[2], root) == absLeft(controls[1], root) + ctlWidth(controls[1]),
                 @"Remove must make horizontal neighbours touch");

    /* Vertical Spacing > Remove: tops 300/900/1500 become 300/600/900 */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Vertical Spacing", @"Remove");
    ok &= verify(item != nil && item.enabled, @"Vertical Spacing > Remove must be enabled");
    ok &= verify(fireMenuItem(item), @"Vertical Spacing > Remove must dispatch");
    report(@"menu V Spacing Remove -> tops %d/%d/%d", absTop(controls[0], root),
           absTop(controls[1], root), absTop(controls[2], root));
    ok &= verify(absTop(controls[1], root) == absTop(controls[0], root) + ctlHeight(controls[0]) &&
                 absTop(controls[2], root) == absTop(controls[1], root) + ctlHeight(controls[1]),
                 @"Remove must make vertical neighbours touch");

    /* Align > Lefts */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Align", @"Lefts");
    ok &= verify(item != nil && item.enabled, @"Align > Lefts must be enabled with 3 controls selected");
    ok &= verify(fireMenuItem(item), @"Align > Lefts must dispatch to the designer");
    lefts[0] = absLeft(controls[0], root);
    lefts[1] = absLeft(controls[1], root);
    lefts[2] = absLeft(controls[2], root);
    report(@"menu Align Lefts -> lefts %d/%d/%d", lefts[0], lefts[1], lefts[2]);
    ok &= verify(lefts[0] == lefts[1] && lefts[1] == lefts[2], @"Align Lefts must equalize left edges");

    /* Align > Rights (compute the expected edge before the action) */
    {
        int maxRight = 0;
        for (i = 0; i < 3; i++) {
            int right = absLeft(controls[i], root) + ctlWidth(controls[i]);
            if (right > maxRight) maxRight = right;
        }
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Align", @"Rights");
        ok &= verify(fireMenuItem(item), @"Align > Rights must dispatch to the designer");
        for (i = 0; i < 3; i++) {
            ok &= verify(absLeft(controls[i], root) + ctlWidth(controls[i]) == maxRight,
                         [NSString stringWithFormat:@"%@ right edge must align", ctlName(controls[i])]);
        }
        report(@"menu Align Rights -> right edge %d", maxRight);
    }

    /* Align > Tops then Align > Middles */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Align", @"Tops");
    ok &= verify(fireMenuItem(item), @"Align > Tops must dispatch to the designer");
    tops[0] = absTop(controls[0], root);
    tops[1] = absTop(controls[1], root);
    tops[2] = absTop(controls[2], root);
    report(@"menu Align Tops -> tops %d/%d/%d", tops[0], tops[1], tops[2]);
    ok &= verify(tops[0] == tops[1] && tops[1] == tops[2], @"Align Tops must equalize top edges");

    /* Align > Bottoms */
    {
        int maxBottom = 0;
        for (i = 0; i < 3; i++) {
            int bottom = absTop(controls[i], root) + ctlHeight(controls[i]);
            if (bottom > maxBottom) maxBottom = bottom;
        }
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Align", @"Bottoms");
        ok &= verify(item != nil && item.enabled, @"Align > Bottoms must be enabled");
        ok &= verify(fireMenuItem(item), @"Align > Bottoms must dispatch to the designer");
        for (i = 0; i < 3; i++) {
            ok &= verify(absTop(controls[i], root) + ctlHeight(controls[i]) == maxBottom,
                         [NSString stringWithFormat:@"%@ bottom edge must align", ctlName(controls[i])]);
        }
        report(@"menu Align Bottoms -> bottom edge %d", maxBottom);
    }

    /* Align > Middles: every control's vertical centre lands on the union centre */
    {
        int minTop = INT_MAX, maxBottom = INT_MIN;
        int expected;
        for (i = 0; i < 3; i++) {
            minTop = MIN(minTop, absTop(controls[i], root));
            maxBottom = MAX(maxBottom, absTop(controls[i], root) + ctlHeight(controls[i]));
        }
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Align", @"Middles");
        ok &= verify(item != nil && item.enabled, @"Align > Middles must be enabled");
        ok &= verify(fireMenuItem(item), @"Align > Middles must dispatch to the designer");
        expected = minTop + maxBottom;
        for (i = 0; i < 3; i++) {
            int centre = 2 * absTop(controls[i], root) + ctlHeight(controls[i]);
            ok &= verify(abs(centre - expected) <= 1,
                         [NSString stringWithFormat:@"%@ vertical centre must align", ctlName(controls[i])]);
        }
        report(@"menu Align Middles -> centre %d (2x)", expected);
    }

    /* Align > Centers: same test on the horizontal axis, with mixed widths */
    {
        int minLeft = INT_MAX, maxRight = INT_MIN;
        int expected;
        for (i = 0; i < 3; i++) {
            minLeft = MIN(minLeft, absLeft(controls[i], root));
            maxRight = MAX(maxRight, absLeft(controls[i], root) + ctlWidth(controls[i]));
        }
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Align", @"Centers");
        ok &= verify(item != nil && item.enabled, @"Align > Centers must be enabled");
        ok &= verify(fireMenuItem(item), @"Align > Centers must dispatch to the designer");
        expected = minLeft + maxRight;
        for (i = 0; i < 3; i++) {
            int centre = 2 * absLeft(controls[i], root) + ctlWidth(controls[i]);
            ok &= verify(abs(centre - expected) <= 1,
                         [NSString stringWithFormat:@"%@ horizontal centre must align", ctlName(controls[i])]);
        }
        report(@"menu Align Centers -> centre %d (2x), widths %d/%d/%d", expected,
               ctlWidth(controls[0]), ctlWidth(controls[1]), ctlWidth(controls[2]));
    }

    /* Vertical Spacing > Make Equal / Increase / Decrease on a known layout */
    {
        int layoutTop[3] = { 300, 900, 2100 };
        int layoutHeight[3] = { 300, 300, 450 };
        for (i = 0; i < 3; i++) {
            vb_control_set_int(controls[i], "Top", layoutTop[i]);
            vb_control_set_int(controls[i], "Height", layoutHeight[i]);
        }
        [designer refresh];
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Vertical Spacing", @"Make Equal");
        ok &= verify(item != nil && item.enabled, @"Vertical Spacing > Make Equal must be enabled");
        ok &= verify(fireMenuItem(item), @"Vertical Spacing > Make Equal must dispatch");
        report(@"menu V Spacing Make Equal -> tops %d/%d/%d", absTop(controls[0], root),
               absTop(controls[1], root), absTop(controls[2], root));
        ok &= verify(absTop(controls[0], root) == 300 && absTop(controls[1], root) == 1200 &&
                     absTop(controls[2], root) == 2100,
                     @"vertical Make Equal must keep the outer edges fixed");
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Vertical Spacing", @"Increase");
        ok &= verify(fireMenuItem(item), @"Vertical Spacing > Increase must dispatch");
        ok &= verify(absTop(controls[1], root) - (absTop(controls[0], root) + ctlHeight(controls[0])) == 660,
                     @"vertical Increase must add one grid step (60 twips)");
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Vertical Spacing", @"Decrease");
        ok &= verify(fireMenuItem(item), @"Vertical Spacing > Decrease must dispatch");
        ok &= verify(absTop(controls[0], root) == 300 && absTop(controls[1], root) == 1200 &&
                     absTop(controls[2], root) == 2100,
                     @"vertical Decrease must restore the previous gaps");
        report(@"menu V Spacing Increase/Decrease round-trip -> tops %d/%d/%d",
               absTop(controls[0], root), absTop(controls[1], root), absTop(controls[2], root));
    }

    /* Make Same Size > Width, using the active control as the reference */
    {
        VbControl *reference = designer.selected;
        int expectedWidth = reference ? ctlWidth(reference) : 0;
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Make Same Size", @"Width");
        ok &= verify(item != nil && item.enabled, @"Make Same Size > Width must be enabled");
        ok &= verify(fireMenuItem(item), @"Make Same Size > Width must dispatch");
        for (i = 0; i < 3; i++) {
            ok &= verify(ctlWidth(controls[i]) == expectedWidth,
                         [NSString stringWithFormat:@"%@ width must match the reference", ctlName(controls[i])]);
        }
        report(@"menu Same Width -> %d for all", expectedWidth);
    }

    /* Make Same Size > Height, using the active control as the reference */
    {
        VbControl *reference = designer.selected;
        int expectedHeight = reference ? ctlHeight(reference) : 0;
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Make Same Size", @"Height");
        ok &= verify(item != nil && item.enabled, @"Make Same Size > Height must be enabled");
        ok &= verify(fireMenuItem(item), @"Make Same Size > Height must dispatch");
        for (i = 0; i < 3; i++) {
            ok &= verify(ctlHeight(controls[i]) == expectedHeight,
                         [NSString stringWithFormat:@"%@ height must match the reference", ctlName(controls[i])]);
        }
        report(@"menu Same Height -> %d for all", expectedHeight);
    }

    /* Make Same Size > Both */
    {
        VbControl *reference = designer.selected;
        int expectedWidth = reference ? ctlWidth(reference) : 0;
        int expectedHeight = reference ? ctlHeight(reference) : 0;
        item = submenuItemTitled(formatMenuFromBar(menuBar), @"Make Same Size", @"Both");
        ok &= verify(fireMenuItem(item), @"Make Same Size > Both must dispatch");
        for (i = 0; i < 3; i++) {
            widths[i] = ctlWidth(controls[i]);
            heights[i] = ctlHeight(controls[i]);
            ok &= verify(widths[i] == expectedWidth && heights[i] == expectedHeight,
                         [NSString stringWithFormat:@"%@ size must match the reference", ctlName(controls[i])]);
        }
        report(@"menu Same Size -> %dx%d for all", expectedWidth, expectedHeight);
    }

    /* Center in Form moves the selection as a group, like VB6 */
    {
        int clientWidth = vb_form_client_width(form);
        int clientHeight = vb_form_client_height(form);
        int layout[3][4] = { {300, 300, 600, 300}, {900, 900, 600, 300}, {2100, 1500, 900, 450} };
        int original[3][2];
        int minLeft = INT_MAX, maxRight = INT_MIN, minTop = INT_MAX, maxBottom = INT_MIN;
        int expectedLeft, expectedTop;
        for (i = 0; i < 3; i++) {
            vb_control_set_int(controls[i], "Left", layout[i][0]);
            vb_control_set_int(controls[i], "Top", layout[i][1]);
            vb_control_set_int(controls[i], "Width", layout[i][2]);
            vb_control_set_int(controls[i], "Height", layout[i][3]);
        }
        [designer refresh];
        for (i = 0; i < 3; i++) {
            original[i][0] = absLeft(controls[i], root);
            original[i][1] = absTop(controls[i], root);
            minLeft = MIN(minLeft, original[i][0]);
            maxRight = MAX(maxRight, original[i][0] + ctlWidth(controls[i]));
            minTop = MIN(minTop, original[i][1]);
            maxBottom = MAX(maxBottom, original[i][1] + ctlHeight(controls[i]));
        }
        expectedLeft = (clientWidth - (maxRight - minLeft)) / 2;
        expectedTop = (clientHeight - (maxBottom - minTop)) / 2;
        item = itemTitled(formatMenuFromBar(menuBar), @"Center in Form");
        ok &= verify(item != nil && item.enabled, @"Center in Form must be enabled");
        ok &= verify(fireMenuItem(item), @"Center in Form must dispatch");
        for (i = 0; i < 3; i++) {
            int offsetLeft = original[i][0] - minLeft;
            int offsetTop = original[i][1] - minTop;
            ok &= verify(absLeft(controls[i], root) == expectedLeft + offsetLeft &&
                         absTop(controls[i], root) == expectedTop + offsetTop,
                         [NSString stringWithFormat:@"%@ must keep its offset inside the centred group",
                          ctlName(controls[i])]);
        }
        {
            int unionLeft = INT_MAX, unionRight = INT_MIN;
            for (i = 0; i < 3; i++) {
                unionLeft = MIN(unionLeft, absLeft(controls[i], root));
                unionRight = MAX(unionRight, absLeft(controls[i], root) + ctlWidth(controls[i]));
            }
            ok &= verify(abs((unionLeft + unionRight) - clientWidth) <= 2,
                         @"the selection bounding box must be centred horizontally");
        }
        report(@"menu Center in Form -> group %d,%d on %dx%d", expectedLeft, expectedTop,
               clientWidth, clientHeight);
    }

    report(@"format menu %@", ok ? @"PASS" : @"FAIL");
    return ok;
}

BOOL VBCheckFormatMenuState(VBMenuBarView *menuBar, BOOL alignEnabled, BOOL spaceEnabled,
                            BOOL centerEnabled)
{
    NSMenu *menu = formatMenuFromBar(menuBar);
    BOOL ok = YES;
    NSArray<NSString *> *alignTitles = @[@"Lefts", @"Centers", @"Rights", @"Tops", @"Middles", @"Bottoms"];
    NSArray<NSString *> *sizeTitles = @[@"Width", @"Height", @"Both"];
    NSArray<NSString *> *spacingTitles = @[@"Make Equal", @"Increase", @"Decrease", @"Remove"];
    if (!menu) {
        report(@"format menu state: no Format menu");
        return NO;
    }
    for (NSString *title in alignTitles) {
        NSMenuItem *item = submenuItemTitled(menu, @"Align", title);
        ok &= verify(item != nil && item.enabled == alignEnabled,
                     [NSString stringWithFormat:@"Align > %@ enabled=%@", title, alignEnabled ? @"YES" : @"NO"]);
    }
    for (NSString *title in sizeTitles) {
        NSMenuItem *item = submenuItemTitled(menu, @"Make Same Size", title);
        ok &= verify(item != nil && item.enabled == alignEnabled,
                     [NSString stringWithFormat:@"Make Same Size > %@ enabled=%@", title,
                      alignEnabled ? @"YES" : @"NO"]);
    }
    for (NSString *title in spacingTitles) {
        NSMenuItem *item = submenuItemTitled(menu, @"Horizontal Spacing", title);
        ok &= verify(item != nil && item.enabled == spaceEnabled,
                     [NSString stringWithFormat:@"Horizontal Spacing > %@ enabled=%@", title,
                      spaceEnabled ? @"YES" : @"NO"]);
        NSMenuItem *other = submenuItemTitled(menu, @"Vertical Spacing", title);
        ok &= verify(other != nil && other.enabled == spaceEnabled,
                     [NSString stringWithFormat:@"Vertical Spacing > %@ enabled=%@", title,
                      spaceEnabled ? @"YES" : @"NO"]);
    }
    {
        NSMenuItem *item = itemTitled(menu, @"Center in Form");
        ok &= verify(item != nil && item.enabled == centerEnabled,
                     [NSString stringWithFormat:@"Center in Form enabled=%@", centerEnabled ? @"YES" : @"NO"]);
    }
    for (NSString *title in @[@"Bring to Front", @"Send to Back"]) {
        NSMenuItem *item = submenuItemTitled(menu, @"Order", title);
        ok &= verify(item != nil && item.enabled == centerEnabled,
                     [NSString stringWithFormat:@"Order > %@ enabled=%@", title,
                      centerEnabled ? @"YES" : @"NO"]);
    }
    return ok;
}

BOOL VBCheckToolbarState(VBToolbarView *toolbar, BOOL alignEnabled, BOOL spaceEnabled)
{
    BOOL ok = YES;
    NSArray<NSString *> *alignIdentifiers = @[@"align-left", @"align-center", @"align-right",
                                              @"align-top", @"align-middle", @"align-bottom",
                                              @"same-width", @"same-height", @"same-size"];
    if (!toolbar) {
        report(@"format toolbar state: no toolbar");
        return NO;
    }
    for (NSString *identifier in alignIdentifiers) {
        BOOL actual = [toolbar isEnabledForIdentifier:identifier];
        ok &= verify(actual == alignEnabled,
                     [NSString stringWithFormat:@"format toolbar %@ enabled=%@", identifier,
                      alignEnabled ? @"YES" : @"NO"]);
    }
    for (NSString *identifier in @[@"space-h-equal", @"space-v-equal"]) {
        BOOL actual = [toolbar isEnabledForIdentifier:identifier];
        ok &= verify(actual == spaceEnabled,
                     [NSString stringWithFormat:@"format toolbar %@ enabled=%@", identifier,
                      spaceEnabled ? @"YES" : @"NO"]);
    }
    return ok;
}

static NSEvent *toolbarEvent(VBToolbarView *toolbar, NSEventType type, NSPoint point)
{
    NSPoint inWindow = [toolbar convertPoint:point toView:nil];
    return [NSEvent mouseEventWithType:type
                              location:inWindow
                         modifierFlags:0
                             timestamp:0
                          windowNumber:toolbar.window.windowNumber
                               context:nil
                           eventNumber:0
                            clickCount:1
                              pressure:1.0];
}

static BOOL clickToolbarButton(VBToolbarView *toolbar, NSString *identifier)
{
    NSRect rect = [toolbar rectForIdentifier:identifier];
    NSPoint point;
    if (NSIsEmptyRect(rect)) {
        report(@"format toolbar: no button %@", identifier);
        return NO;
    }
    point = NSMakePoint(NSMidX(rect), NSMidY(rect));
    [toolbar mouseDown:toolbarEvent(toolbar, NSEventTypeLeftMouseDown, point)];
    [toolbar mouseUp:toolbarEvent(toolbar, NSEventTypeLeftMouseUp, point)];
    return YES;
}

BOOL VBRunFormatToolbarSelfTest(VBToolbarView *toolbar, VBDesignerView *designer, VbForm *form)
{
    BOOL ok = YES;
    VbControl *root;
    VbControl *controls[3];
    VbControl *reference;
    int layout[3][4] = { {300, 300, 600, 300}, {1200, 900, 600, 300}, {2400, 1500, 900, 450} };
    int expectedWidth;
    int expectedHeight;
    int i;

    if (!toolbar || !designer || !form || !form->root) {
        report(@"format toolbar test: no toolbar or form");
        return NO;
    }
    root = form->root;
    controls[0] = childNamed(root, "Text1");
    controls[1] = childNamed(root, "Command1");
    controls[2] = childNamed(root, "Label1");
    if (!controls[0] || !controls[1] || !controls[2]) {
        report(@"format toolbar test: fixture needs Text1, Command1 and Label1");
        return NO;
    }
    if (designer.selectionCount != 3) {
        report(@"format toolbar test: the three controls must still be selected");
        return NO;
    }
    for (i = 0; i < 3; i++) {
        vb_control_set_int(controls[i], "Left", layout[i][0]);
        vb_control_set_int(controls[i], "Top", layout[i][1]);
        vb_control_set_int(controls[i], "Width", layout[i][2]);
        vb_control_set_int(controls[i], "Height", layout[i][3]);
    }
    [designer refresh];

    /* Align Lefts */
    ok &= verify([toolbar isEnabledForIdentifier:@"align-left"], @"toolbar align-left must be enabled");
    ok &= verify(clickToolbarButton(toolbar, @"align-left"), @"toolbar align-left must be clickable");
    report(@"toolbar align-left -> lefts %d/%d/%d", absLeft(controls[0], root),
           absLeft(controls[1], root), absLeft(controls[2], root));
    ok &= verify(absLeft(controls[0], root) == 300 && absLeft(controls[1], root) == 300 &&
                 absLeft(controls[2], root) == 300,
                 @"toolbar align-left must equalize left edges");

    /* Make Same Size (reference = active control) */
    reference = designer.selected;
    expectedWidth = reference ? ctlWidth(reference) : 0;
    expectedHeight = reference ? ctlHeight(reference) : 0;
    ok &= verify(clickToolbarButton(toolbar, @"same-size"), @"toolbar same-size must be clickable");
    for (i = 0; i < 3; i++) {
        ok &= verify(ctlWidth(controls[i]) == expectedWidth && ctlHeight(controls[i]) == expectedHeight,
                     [NSString stringWithFormat:@"%@ must take the reference size from the toolbar",
                      ctlName(controls[i])]);
    }
    report(@"toolbar same-size -> %dx%d for all", expectedWidth, expectedHeight);

    /* Horizontal Spacing: Make Equal (reset to unequal gaps first) */
    {
        int resetLeft[3] = { 300, 1200, 2400 };
        for (i = 0; i < 3; i++) vb_control_set_int(controls[i], "Left", resetLeft[i]);
        [designer refresh];
        ok &= verify(clickToolbarButton(toolbar, @"space-h-equal"), @"toolbar space-h-equal must be clickable");
    }
    {
        int gapA = absLeft(controls[1], root) - (absLeft(controls[0], root) + ctlWidth(controls[0]));
        int gapB = absLeft(controls[2], root) - (absLeft(controls[1], root) + ctlWidth(controls[1]));
        report(@"toolbar space-h-equal -> lefts %d/%d/%d gaps %d/%d", absLeft(controls[0], root),
               absLeft(controls[1], root), absLeft(controls[2], root), gapA, gapB);
        ok &= verify(gapA == 150 && gapB == 150,
                     @"toolbar spacing must equalize horizontal gaps to 150 twips");
        ok &= verify(absLeft(controls[0], root) == 300 && absLeft(controls[2], root) == 2400,
                     @"toolbar spacing must keep the outer edges fixed");
    }

    report(@"format toolbar %@", ok ? @"PASS" : @"FAIL");
    return ok;
}

BOOL VBRunDesignerSelectionSelfTest(VBDesignerView *designer, VbForm *form)
{
    VbControl *root;
    VbControl *text;
    VbControl *command;
    VbControl *label;
    VbControl *controls[3];
    BOOL ok = YES;
    int moveLeft[3], moveTop[3];
    int resizeLeft[3], resizeTop[3], resizeWidth[3], resizeHeight[3];
    int unionLeft = 0;
    NSRect rect;
    int i;

    if (!designer || !form || !form->root) {
        report(@"no form loaded");
        return NO;
    }
    root = form->root;
    if (root->nchildren < 3) {
        report(@"fixture needs at least 3 controls, found %d", root->nchildren);
        return NO;
    }
    text = childNamed(root, "Text1");
    command = childNamed(root, "Command1");
    label = childNamed(root, "Label1");
    if (!text || !command || !label) {
        report(@"fixture needs Text1, Command1 and Label1");
        return NO;
    }
    controls[0] = text;
    controls[1] = command;
    controls[2] = label;

    [designer selectControl:root];
    [designer refresh];
    ok &= verify(designer.selectionCount == 0, @"selection must start empty");

    /* 1. marquee around Text1 only */
    rect = [designer rectForControl:text];
    dragFromTo(designer, NSMakePoint(NSMinX(rect) - 8, NSMinY(rect) - 8),
                        NSMakePoint(NSMaxX(rect) + 8, NSMaxY(rect) + 8), 0);
    report(@"marquee single -> count=%lu selected=%@",
           (unsigned long)designer.selectionCount, ctlName(designer.selected));
    ok &= verify(designer.selectionCount == 1 && designer.selected == text,
                 @"marquee must select exactly Text1");

    /* 2. shift-click adds Command1 */
    rect = [designer rectForControl:command];
    clickAt(designer, NSMakePoint(NSMidX(rect), NSMidY(rect)), NSEventModifierFlagShift);
    report(@"shift-click -> count=%lu active=%@",
           (unsigned long)designer.selectionCount, ctlName(designer.selected));
    ok &= verify(designer.selectionCount == 2, @"shift-click must add Command1");

    /* 3. group move: both selected controls shift by 300x150 twips, Label1 stays */
    for (i = 0; i < 3; i++) {
        moveLeft[i] = ctlLeft(controls[i]);
        moveTop[i] = ctlTop(controls[i]);
    }
    rect = [designer rectForControl:text];
    dragFromTo(designer, NSMakePoint(NSMidX(rect), NSMidY(rect)),
                        NSMakePoint(NSMidX(rect) + 30, NSMidY(rect) + 15), 0);
    report(@"group move -> Text1 %d,%d => %d,%d | Command1 %d,%d => %d,%d | Label1 %d,%d => %d,%d",
           moveLeft[0], moveTop[0], ctlLeft(text), ctlTop(text),
           moveLeft[1], moveTop[1], ctlLeft(command), ctlTop(command),
           moveLeft[2], moveTop[2], ctlLeft(label), ctlTop(label));
    ok &= verify(ctlLeft(text) == moveLeft[0] + 300 && ctlTop(text) == moveTop[0] + 150,
                 @"Text1 must move 300x150 twips with the group");
    ok &= verify(ctlLeft(command) == moveLeft[1] + 300 && ctlTop(command) == moveTop[1] + 150,
                 @"Command1 must move 300x150 twips with the group");
    ok &= verify(ctlLeft(label) == moveLeft[2] && ctlTop(label) == moveTop[2],
                 @"Label1 must not move with the group");
    ok &= verify(designer.selectionCount == 2, @"group move must keep both controls selected");

    /* 4. marquee across the whole form selects every control */
    rect = unionOfControls(designer, root);
    dragFromTo(designer, NSMakePoint(NSMinX(rect) - 10, NSMinY(rect) - 10),
                        NSMakePoint(NSMaxX(rect) + 10, NSMaxY(rect) + 10), 0);
    report(@"marquee all -> count=%lu active=%@",
           (unsigned long)designer.selectionCount, ctlName(designer.selected));
    ok &= verify(designer.selectionCount == 3, @"marquee must select all three controls");

    /* 4b. shift-marquee over empty form area must keep the selection intact */
    {
        NSPoint clientOrigin = NSMakePoint(NSMinX([designer rectForControl:label]) -
                                               VBTwipsToPoints(ctlLeft(label)),
                                           NSMinY([designer rectForControl:label]) -
                                               VBTwipsToPoints(ctlTop(label)));
        dragFromTo(designer, NSMakePoint(clientOrigin.x + 4, clientOrigin.y + 4),
                            NSMakePoint(clientOrigin.x + 40, clientOrigin.y + 40),
                            NSEventModifierFlagShift);
        report(@"shift-marquee empty -> count=%lu", (unsigned long)designer.selectionCount);
        ok &= verify(designer.selectionCount == 3,
                     @"shift-marquee over empty area must not drop the selection");
    }

    /* 5. group resize from the bottom-right handle: both axes scale by 1.5 */
    rect = unionOfControls(designer, root);
    unionLeft = ctlLeft(text);
    for (i = 0; i < 3; i++) {
        resizeLeft[i] = ctlLeft(controls[i]);
        resizeTop[i] = ctlTop(controls[i]);
        resizeWidth[i] = ctlWidth(controls[i]);
        resizeHeight[i] = ctlHeight(controls[i]);
        if (resizeLeft[i] < unionLeft) unionLeft = resizeLeft[i];
    }
    dragFromTo(designer, NSMakePoint(NSMaxX(rect), NSMaxY(rect)),
                        NSMakePoint(NSMaxX(rect) + NSWidth(rect) / 2.0,
                                    NSMaxY(rect) + NSHeight(rect) / 2.0), 0);
    for (i = 0; i < 3; i++) {
        VbControl *control = controls[i];
        double expectedWidth = resizeWidth[i] * 1.5;
        double expectedHeight = resizeHeight[i] * 1.5;
        double expectedLeft = resizeLeft[i] + (resizeLeft[i] - unionLeft) * 0.5;
        report(@"resize %@ -> w %d=>%d (exp %.0f) h %d=>%d (exp %.0f) left %d=>%d (exp %.0f)",
               ctlName(control), resizeWidth[i], ctlWidth(control), expectedWidth,
               resizeHeight[i], ctlHeight(control), expectedHeight,
               resizeLeft[i], ctlLeft(control), expectedLeft);
        ok &= verify(fabs(ctlWidth(control) - expectedWidth) <= 10.0,
                     [NSString stringWithFormat:@"%@ width must scale by 1.5", ctlName(control)]);
        ok &= verify(fabs(ctlHeight(control) - expectedHeight) <= 10.0,
                     [NSString stringWithFormat:@"%@ height must scale by 1.5", ctlName(control)]);
        ok &= verify(fabs(ctlLeft(control) - expectedLeft) <= 10.0,
                     [NSString stringWithFormat:@"%@ keeps proportional spacing", ctlName(control)]);
    }
    /* the horizontal gap between two controls must scale with the group */
    {
        int gapBefore = resizeLeft[1] - resizeLeft[0];
        int gapAfter = ctlLeft(command) - ctlLeft(text);
        report(@"resize gap Text1->Command1 %d => %d (exp %.0f)", gapBefore, gapAfter, gapBefore * 1.5);
        ok &= verify(fabs(gapAfter - gapBefore * 1.5) <= 10.0,
                     @"horizontal spacing between selected controls must scale with the group");
    }
    ok &= verify(designer.selectionCount == 3, @"group resize must keep all three selected");

    report(@"%@ (marquee, shift-click, group move 300x150 twips, group resize 1.5x)",
           ok ? @"PASS" : @"FAIL");
    return ok;
}

static BOOL zOrderIs(VbControl *parent, VbControl *first, VbControl *second, VbControl *third)
{
    return parent && parent->nchildren >= 3 && parent->children[0] == first &&
           parent->children[1] == second && parent->children[2] == third;
}

BOOL VBCheckTabOrderMenu(VBMenuBarView *menuBar)
{
    NSMenu *view = nil;
    NSMenuItem *item;
    for (NSMenu *menu in menuBar.menus) {
        if ([menu.title isEqualToString:@"View"]) {
            view = menu;
            break;
        }
    }
    item = itemTitled(view, @"Tab Order...");
    return verify(item != nil && item.enabled && item.action != NULL,
                  @"View > Tab Order... must be present and enabled");
}

BOOL VBRunZOrderSelfTest(VBMenuBarView *menuBar, VBDesignerView *designer, VbForm *form)
{
    BOOL ok = YES;
    NSMenuItem *item;
    VbControl *root;
    VbControl *text;
    VbControl *command;
    VbControl *label;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gmbaside-zorder-selftest.frm"];

    if (!designer || !form || !form->root) {
        report(@"z-order test: no designer or form");
        return NO;
    }
    root = form->root;
    text = childNamed(root, "Text1");
    command = childNamed(root, "Command1");
    label = childNamed(root, "Label1");
    if (!text || !command || !label) {
        report(@"z-order test: fixture needs Text1, Command1 and Label1");
        return NO;
    }
    ok &= verify(zOrderIs(root, text, command, label),
                 @"z-order fixture must start as Text1, Command1, Label1");

    /* Send to Back with a single control, through the Format > Order menu item. */
    [designer selectControl:label];
    ok &= verify([designer canReorderSelection], @"a selected control can be reordered");
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Order", @"Send to Back");
    ok &= verify(item != nil && item.enabled, @"Format > Order > Send to Back must be enabled");
    ok &= verify(fireMenuItem(item), @"Format > Order > Send to Back must dispatch");
    ok &= verify(zOrderIs(root, label, text, command),
                 @"Send to Back must put Label1 behind Text1 and Command1");
    report(@"z-order send to back -> %@, %@, %@", ctlName(root->children[0]),
           ctlName(root->children[1]), ctlName(root->children[2]));

    /* Bring to Front restores the original stacking. */
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Order", @"Bring to Front");
    ok &= verify(item != nil && item.enabled, @"Format > Order > Bring to Front must be enabled");
    ok &= verify(fireMenuItem(item), @"Format > Order > Bring to Front must dispatch");
    ok &= verify(zOrderIs(root, text, command, label),
                 @"Bring to Front must put Label1 above Text1 and Command1");

    /* Group Send to Back / Bring to Front preserve the group's relative order. */
    [designer selectControl:text];
    {
        NSRect rect = [designer rectForControl:label];
        clickAt(designer, NSMakePoint(NSMidX(rect), NSMidY(rect)), NSEventModifierFlagShift);
    }
    ok &= verify(designer.selectionCount == 2, @"shift-click must give a two-control z-order selection");
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Order", @"Send to Back");
    ok &= verify(item != nil && item.enabled, @"group Send to Back must stay enabled");
    ok &= verify(fireMenuItem(item), @"group Send to Back must dispatch");
    ok &= verify(zOrderIs(root, text, label, command),
                 @"group Send to Back must keep Text1 before Label1");
    report(@"z-order group send to back -> %@, %@, %@", ctlName(root->children[0]),
           ctlName(root->children[1]), ctlName(root->children[2]));
    item = submenuItemTitled(formatMenuFromBar(menuBar), @"Order", @"Bring to Front");
    ok &= verify(fireMenuItem(item), @"group Bring to Front must dispatch");
    ok &= verify(zOrderIs(root, command, text, label),
                 @"group Bring to Front must keep Text1 before Label1");
    report(@"z-order group bring to front -> %@, %@, %@", ctlName(root->children[0]),
           ctlName(root->children[1]), ctlName(root->children[2]));

    /* Z-order is the .frm block order: it must survive save and reload. */
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    ok &= verify(vb_form_save(form, path.UTF8String) != 0, @"the form must save for the z-order test");
    {
        VbForm *reloaded = vb_form_load(path.UTF8String);
        ok &= verify(reloaded != NULL, @"the saved form must reload");
        if (reloaded) {
            VbControl *r = reloaded->root;
            ok &= verify(zOrderIs(r, childNamed(r, "Command1"), childNamed(r, "Text1"),
                                  childNamed(r, "Label1")),
                         @"saved .frm must keep the new control order");
            ok &= verify(vb_control_tab_index(childNamed(r, "Text1"), -1) == 0 &&
                         vb_control_tab_index(childNamed(r, "Command1"), -1) == 1 &&
                         vb_control_tab_index(childNamed(r, "Label1"), -1) == 2,
                         @"TabIndex values must survive save and reload");
            report(@"z-order reload -> %@, %@, %@", ctlName(r->children[0]),
                   ctlName(r->children[1]), ctlName(r->children[2]));
            vb_form_free(reloaded);
        }
    }
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

    /* Tab Order model: list, reorder, apply. */
    {
        VBTabOrderModel *model = [[VBTabOrderModel alloc] initWithContainer:root];
        ok &= verify(model.count == 3, @"Tab Order must list all three controls");
        if (model.count == 3) {
            ok &= verify([[model titleAtIndex:0] isEqualToString:@"Text1"] &&
                         [[model titleAtIndex:1] isEqualToString:@"Command1"] &&
                         [[model titleAtIndex:2] isEqualToString:@"Label1"],
                         @"Tab Order must start in TabIndex order");
            model.selectedIndex = 2;
            ok &= verify([model moveSelectionUp], @"Tab Order must move the selected control up");
            ok &= verify([[model titleAtIndex:1] isEqualToString:@"Label1"],
                         @"Label1 must now be the second entry");
            [model apply];
            ok &= verify(vb_control_tab_index(text, -1) == 0 &&
                         vb_control_tab_index(label, -1) == 1 &&
                         vb_control_tab_index(command, -1) == 2,
                         @"Apply must renumber TabIndex to 0..n-1");
            report(@"tab order apply -> Text1=%d Command1=%d Label1=%d",
                   vb_control_tab_index(text, -1), vb_control_tab_index(command, -1),
                   vb_control_tab_index(label, -1));
        }
    }

    /* Setting TabIndex to an occupied slot swaps with the current owner. */
    vb_control_set_tab_index(command, 0);
    ok &= verify(vb_control_tab_index(command, -1) == 0 &&
                 vb_control_tab_index(label, -1) == 1 &&
                 vb_control_tab_index(text, -1) == 2,
                 @"setting TabIndex must swap with the control that owned it");
    report(@"tab index swap -> Text1=%d Command1=%d Label1=%d",
           vb_control_tab_index(text, -1), vb_control_tab_index(command, -1),
           vb_control_tab_index(label, -1));

    /* A newly created control lands in front with the next free TabIndex. */
    {
        VbControl *created = vb_form_add_control(form, root, "VB.CommandButton", 300, 2400, 1200, 300);
        ok &= verify(created != NULL, @"creating a control must succeed");
        if (created) {
            ok &= verify(vb_control_tab_index(created, -1) == 3,
                         @"a new control must take the next free TabIndex");
            ok &= verify(root->children[root->nchildren - 1] == created,
                         @"a new control must be in front of the existing ones");
            report(@"new control -> %@ TabIndex=%d", ctlName(created),
                   vb_control_tab_index(created, -1));
            vb_control_remove_child(root, created);
            vb_control_free(created);
        }
    }

    report(@"z-order and tab order %@", ok ? @"PASS" : @"FAIL");

    /* Data / DataGrid tools: toolbox entries, VB6 defaults and .frm round-trip. */
    {
        int toolCount = 0;
        const VbToolDef *tools = vb_tool_defs(&toolCount);
        BOOL hasData = NO, hasGrid = NO;
        for (int i = 0; i < toolCount; i++) {
            if (vb_streq(tools[i].type, "VB.Data")) hasData = YES;
            if (vb_streq(tools[i].type, "VB.DataGrid")) hasGrid = YES;
        }
        ok &= verify(hasData && hasGrid, @"the toolbox must offer the Data and DataGrid tools");

        VbControl *data = vb_form_add_control(form, root, "VB.Data", 120, 2520, 2415, 360);
        VbControl *grid = vb_form_add_control(form, root, "VB.DataGrid", 120, 360, 3015, 1815);
        ok &= verify(data != NULL && grid != NULL, @"Data and DataGrid must be creatable on a form");
        if (data && grid) {
            ok &= verify(vb_control_get_int(grid, "ColumnHeaders", 0) == -1,
                         @"DataGrid must default ColumnHeaders = True");
            ok &= verify(vb_control_get_int(grid, "DefColWidth", 0) == 1275 &&
                         vb_control_get_int(grid, "RowHeight", 0) == 255,
                         @"DataGrid must use VB6's default column width and row height");
            ok &= verify(vb_control_get(grid, "Caption") == NULL,
                         @"DataGrid has no Caption in VB6");
            ok &= verify(vb_control_get(data, "Caption") != NULL,
                         @"the Data control keeps its Caption (the current record)");
            report(@"data tools -> Data1 ColumnHeaders=%d DefColWidth=%d",
                   vb_control_get_int(grid, "ColumnHeaders", 0),
                   vb_control_get_int(grid, "DefColWidth", 0));

            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            ok &= verify(vb_form_save(form, path.UTF8String) != 0,
                         @"the form holding Data/DataGrid must save");
            {
                VbForm *reloaded = vb_form_load(path.UTF8String);
                ok &= verify(reloaded != NULL, @"the saved form with Data/DataGrid must reload");
                if (reloaded) {
                    VbControl *rdata = childNamed(reloaded->root, "Data1");
                    VbControl *rgrid = childNamed(reloaded->root, "DataGrid1");
                    ok &= verify(rdata != NULL && rgrid != NULL,
                                 @"Data and DataGrid must survive save and reload");
                    if (rgrid) {
                        ok &= verify(vb_control_get_int(rgrid, "ColumnHeaders", 0) == -1 &&
                                     vb_control_get_int(rgrid, "DefColWidth", 0) == 1275 &&
                                     vb_control_get_int(rgrid, "RowHeight", 0) == 255,
                                     @"DataGrid's ColumnHeaders/DefColWidth/RowHeight must round-trip");
                        ok &= verify(vb_control_get(rgrid, "Caption") == NULL,
                                     @"the saved DataGrid must stay captionless");
                    }
                    report(@"data tools reload -> Data1=%s DataGrid1=%s",
                           rdata ? "ok" : "missing", rgrid ? "ok" : "missing");
                    vb_form_free(reloaded);
                }
            }
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }
    }

    return ok;
}
