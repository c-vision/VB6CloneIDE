#import "VBCodeEditor.h"
#import "VBTheme.h"

#include "core/vb_code.h"

#include <string.h>

@interface VBCompletionTextView : NSTextView
@end

@implementation VBCompletionTextView
- (void)keyDown:(NSEvent *)event
{
    BOOL ctrlSpace = (event.modifierFlags & NSEventModifierFlagControl) &&
                     [[event charactersIgnoringModifiers] isEqualToString:@" "];
    if (ctrlSpace) { [self complete:nil]; return; }
    [super keyDown:event];
}
@end

@interface VBLineNumberGutterView : NSView
@property (nonatomic, weak) NSTextView *textView;
@property (nonatomic, weak) VBCodeEditor *editor;
@property (nonatomic) NSInteger debugLine;
@property (nonatomic, copy) NSIndexSet *breakpoints;
@end

@implementation VBLineNumberGutterView

- (BOOL)isFlipped { return YES; }

- (NSUInteger)currentLineNumber
{
    NSString *text = self.textView.string ?: @"";
    NSUInteger location = MIN(self.textView.selectedRange.location, text.length);
    NSUInteger line = 1;
    for (NSUInteger i = 0; i < location; i++) {
        if ([text characterAtIndex:i] == '\n') line++;
    }
    return line;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [VBColorGutter() setFill];
    NSRectFill(self.bounds);
    [[VBColorPanelBorder() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(NSMaxX(self.bounds) - 1, 0, 1, NSHeight(self.bounds)));

    NSTextView *view = self.textView;
    if (!view || !view.layoutManager) return;

    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    NSRange glyphRange = [layout glyphRangeForBoundingRect:view.visibleRect inTextContainer:container];
    NSString *text = view.string;
    NSUInteger current = [self currentLineNumber];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: VBColorGutterText()
    };
    NSDictionary *currentAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: VBColorAccent()
    };

    [layout enumerateLineFragmentsForGlyphRange:glyphRange
                                     usingBlock:^(NSRect fragRect, NSRect usedRect, NSTextContainer *tc,
                                                  NSRange glyphs, BOOL *stop) {
        (void)usedRect;
        (void)tc;
        (void)stop;
        NSRange charRange = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
        NSUInteger line = 1;
        NSUInteger limit = MIN(charRange.location, text.length);
        for (NSUInteger i = 0; i < limit; i++) {
            if ([text characterAtIndex:i] == '\n') line++;
        }
        NSRect lineRect = [self convertRect:fragRect fromView:view];
        /* VB6 breakpoint: dark red dot in the margin. */
        if ([self.breakpoints containsIndex:line]) {
            NSRect dot = NSMakeRect(5, NSMidY(lineRect) - 4.0, 8.0, 8.0);
            [VBColorBreakpoint() setFill];
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
        BOOL breaking = (self.debugLine > 0 && line == (NSUInteger)self.debugLine);
        /* VB6 marks the paused statement with an arrow in the margin. */
        if (breaking) {
            NSBezierPath *arrow = [NSBezierPath bezierPath];
            CGFloat mid = NSMidY(lineRect);
            [arrow moveToPoint:NSMakePoint(3, mid - 5)];
            [arrow lineToPoint:NSMakePoint(11, mid)];
            [arrow lineToPoint:NSMakePoint(3, mid + 5)];
            [arrow closePath];
            [VBColorTitleBar() setFill];
            [arrow fill];
        }
        NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)line];
        NSDictionary *use = (breaking || line == current) ? currentAttrs : attrs;
        NSSize size = [number sizeWithAttributes:use];
        CGFloat y = lineRect.origin.y + (lineRect.size.height - size.height) / 2.0;
        [number drawAtPoint:NSMakePoint(NSWidth(self.bounds) - size.width - 9, y) withAttributes:use];
    }];
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.editor) return;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    [self.editor toggleBreakpointAtGutterPoint:[self convertPoint:local toView:self.editor]];
}

@end

static const CGFloat kHeaderHeight = 22.0;

@implementation VBCodeEditor {
    NSScrollView *_scroll;
    NSTextView *_textView;
    VBCompletionTextView *_completionView;
    VBLineNumberGutterView *_gutter;
    NSString *_code;
    BOOL _highlighting;
    NSRange _currentLineRange;
    NSString *_objectTitle;
    NSString *_procedureTitle;
    BOOL _objectComboPressed;
    BOOL _procedureComboPressed;
    NSInteger _debugLine;
    NSRange _debugLineRange;
    NSMutableIndexSet *_breakpoints;
    NSString *_lastText;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _currentLineRange = NSMakeRange(NSNotFound, 0);
    _debugLineRange = NSMakeRange(NSNotFound, 0);
    _breakpoints = [NSMutableIndexSet indexSet];

    _objectTitle = @"(General)";
    _procedureTitle = @"(Declarations)";

    _gutter = [[VBLineNumberGutterView alloc] initWithFrame:NSMakeRect(0, kHeaderHeight, 48,
                                                                     NSHeight(frameRect) - kHeaderHeight)];
    _gutter.autoresizingMask = NSViewHeightSizable;
    [self addSubview:_gutter];

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(48, kHeaderHeight,
                                                             NSWidth(frameRect) - 48,
                                                             NSHeight(frameRect) - kHeaderHeight)];
    _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scroll.hasVerticalScroller = YES;
    _scroll.hasHorizontalScroller = NO;
    _scroll.borderType = NSNoBorder;
    _scroll.drawsBackground = YES;
    _scroll.backgroundColor = VBColorCodeBackground();
    _scroll.contentView.drawsBackground = YES;
    _scroll.contentView.backgroundColor = VBColorCodeBackground();

    _textView = [[VBCompletionTextView alloc] initWithFrame:_scroll.bounds];
    _completionView = (VBCompletionTextView *)_textView;
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.minSize = NSMakeSize(0, 0);
    _textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _textView.verticallyResizable = YES;
    _textView.horizontallyResizable = NO;
    _textView.richText = YES;
    _textView.importsGraphics = NO;
    _textView.allowsUndo = YES;
    _textView.usesFindBar = YES;
    _textView.delegate = self;
    _textView.font = VBFontCode();
    _textView.textColor = VBColorCodeText();
    _textView.drawsBackground = YES;
    _textView.backgroundColor = VBColorCodeBackground();
    _textView.insertionPointColor = VBColorAccent();
    _textView.textContainerInset = NSMakeSize(12, 9);
    _textView.automaticQuoteSubstitutionEnabled = NO;
    _textView.automaticDashSubstitutionEnabled = NO;
    _textView.automaticTextReplacementEnabled = NO;
    _textView.automaticSpellingCorrectionEnabled = NO;
    _textView.continuousSpellCheckingEnabled = NO;
    _textView.textContainer.widthTracksTextView = YES;
    _textView.textContainer.containerSize = NSMakeSize(_scroll.contentSize.width, CGFLOAT_MAX);

    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.5;
    paragraph.defaultTabInterval = 28;
    paragraph.tabStops = @[];
    _textView.defaultParagraphStyle = paragraph;

    _scroll.documentView = _textView;
    [self addSubview:_scroll];
    _gutter.textView = _textView;
    _gutter.editor = self;

    [_scroll.contentView setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrollBoundsChanged:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_scroll.contentView];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped { return YES; }

- (void)layout
{
    [super layout];
    _gutter.frame = NSMakeRect(0, kHeaderHeight, 48, MAX(0, NSHeight(self.bounds) - kHeaderHeight));
    _scroll.frame = NSMakeRect(48, kHeaderHeight, MAX(0, NSWidth(self.bounds) - 48),
                               MAX(0, NSHeight(self.bounds) - kHeaderHeight));
}

#pragma mark - VB6 combo header

- (void)comboRects:(NSRect *)objectRect procedureRect:(NSRect *)procedureRect
{
    CGFloat total = MAX(0, NSWidth(self.bounds) - 8);
    CGFloat objectWidth = floor(total * 0.42);
    if (objectWidth < 90) objectWidth = MIN(90, total);
    *objectRect = NSMakeRect(4, 3, objectWidth, kHeaderHeight - 6);
    *procedureRect = NSMakeRect(NSMaxX(*objectRect) + 3, 3,
                                MAX(0, total - objectWidth - 3), kHeaderHeight - 6);
}

- (NSArray<NSDictionary *> *)handlerEntries
{
    NSMutableArray *entries = [NSMutableArray array];
    if (!_code.length) return entries;
    VbHandlerList list;
    vb_handler_list_init(&list);
    vb_code_handlers(_code.UTF8String, &list);
    for (int i = 0; i < list.count; i++) {
        NSString *name = list.items[i].name ? [NSString stringWithUTF8String:list.items[i].name] : @"";
        if (!name.length) continue;
        [entries addObject:@{@"name": name, @"line": @(MAX(1, list.items[i].body_line))}];
    }
    vb_handler_list_free(&list);
    return entries;
}

- (NSString *)objectForHandler:(NSString *)name
{
    NSRange underscore = [name rangeOfString:@"_" options:NSBackwardsSearch];
    if (underscore.location == NSNotFound || underscore.location == 0) return @"(General)";
    return [name substringToIndex:underscore.location];
}

- (NSDictionary *)currentHandlerEntry
{
    NSArray<NSDictionary *> *entries = [self handlerEntries];
    NSDictionary *best = nil;
    NSUInteger cursor = MIN(_textView.selectedRange.location, _code.length);
    NSUInteger line = 1;
    for (NSUInteger i = 0; i < cursor && i < _code.length; i++) {
        if ([_code characterAtIndex:i] == '\n') line++;
    }
    for (NSDictionary *entry in entries) {
        if ([entry[@"line"] integerValue] <= (NSInteger)line) best = entry;
        else break;
    }
    return best;
}

- (NSArray<NSString *> *)objectNames
{
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"(General)"];
    for (NSDictionary *entry in [self handlerEntries]) {
        NSString *object = [self objectForHandler:entry[@"name"]];
        if (![names containsObject:object]) [names addObject:object];
    }
    return names;
}

- (NSArray<NSString *> *)procedureNamesForObject:(NSString *)object
{
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"(Declarations)"];
    if ([object isEqualToString:@"(General)"]) return names;
    for (NSDictionary *entry in [self handlerEntries]) {
        NSString *name = entry[@"name"];
        if (![[self objectForHandler:name] isEqualToString:object]) continue;
        NSRange underscore = [name rangeOfString:@"_" options:NSBackwardsSearch];
        if (underscore.location == NSNotFound) continue;
        NSString *procedure = [name substringFromIndex:NSMaxRange(underscore)];
        if (procedure.length && ![names containsObject:procedure]) [names addObject:procedure];
    }
    return names;
}

- (void)refreshHeaderState
{
    NSDictionary *entry = [self currentHandlerEntry];
    if (entry) {
        _objectTitle = [self objectForHandler:entry[@"name"]];
        NSRange underscore = [entry[@"name"] rangeOfString:@"_" options:NSBackwardsSearch];
        _procedureTitle = underscore.location == NSNotFound ? @"(Declarations)"
            : [entry[@"name"] substringFromIndex:NSMaxRange(underscore)];
    } else {
        _objectTitle = @"(General)";
        _procedureTitle = @"(Declarations)";
    }
    [self setNeedsDisplay:YES];
}

- (void)drawComboInRect:(NSRect)rect title:(NSString *)title pressed:(BOOL)pressed
{
    VBDrawSunkenBevel(rect);
    NSRect arrow = NSMakeRect(NSMaxX(rect) - 16, NSMinY(rect) + 2, 15, NSHeight(rect) - 4);
    if (pressed) VBDrawPressedBevel(arrow);
    else VBDrawRaisedBevel(arrow);
    VBDrawClassicArrow(NSMakeRect(NSMidX(arrow) - 4, NSMidY(arrow) - 2, 8, 5), YES, VBColorText());

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attrs = @{NSFontAttributeName: VBFontUI(),
                            NSForegroundColorAttributeName: VBColorText(),
                            NSParagraphStyleAttributeName: style};
    [title ?: @"" drawInRect:NSMakeRect(NSMinX(rect) + 3, NSMidY(rect) - 7,
                                        NSWidth(rect) - 22, 14)
              withAttributes:attrs];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(NSMakeRect(0, 0, NSWidth(self.bounds), kHeaderHeight));
    [[VBColorShadow() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, kHeaderHeight - 1, NSWidth(self.bounds), 1));

    NSRect objectRect;
    NSRect procedureRect;
    [self comboRects:&objectRect procedureRect:&procedureRect];
    [self drawComboInRect:objectRect title:_objectTitle pressed:_objectComboPressed];
    [self drawComboInRect:procedureRect title:_procedureTitle pressed:_procedureComboPressed];
}

- (void)showComboMenuForObject:(BOOL)isObject rect:(NSRect)rect
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:isObject ? @"Objects" : @"Procedures"];
    NSArray<NSString *> *names = isObject ? [self objectNames]
                                          : [self procedureNamesForObject:_objectTitle];
    NSString *current = isObject ? _objectTitle : _procedureTitle;
    for (NSString *name in names) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:nil keyEquivalent:@""];
        item.target = self;
        item.action = isObject ? @selector(selectObjectItem:) : @selector(selectProcedureItem:);
        item.representedObject = name;
        item.state = [name isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    NSPoint screen = [self.window convertPointToScreen:
                      [self convertPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect)) toView:nil]];
    [menu popUpMenuPositioningItem:nil atLocation:screen inView:nil];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect objectRect;
    NSRect procedureRect;
    [self comboRects:&objectRect procedureRect:&procedureRect];
    if (NSPointInRect(point, objectRect)) {
        _objectComboPressed = YES;
        [self setNeedsDisplay:YES];
        [self showComboMenuForObject:YES rect:objectRect];
        _objectComboPressed = NO;
        [self setNeedsDisplay:YES];
    } else if (NSPointInRect(point, procedureRect)) {
        _procedureComboPressed = YES;
        [self setNeedsDisplay:YES];
        [self showComboMenuForObject:NO rect:procedureRect];
        _procedureComboPressed = NO;
        [self setNeedsDisplay:YES];
    }
}

- (NSUInteger)locationForLine:(NSInteger)line
{
    if (line <= 1) return 0;
    NSUInteger location = 0;
    NSInteger current = 1;
    while (current < line && location < _code.length) {
        NSRange range = [_code lineRangeForRange:NSMakeRange(location, 0)];
        location = NSMaxRange(range);
        current++;
    }
    return MIN(location, _code.length);
}

- (void)jumpToHandlerNamed:(NSString *)name
{
    for (NSDictionary *entry in [self handlerEntries]) {
        if (![entry[@"name"] isEqualToString:name]) continue;
        NSUInteger location = [self locationForLine:[entry[@"line"] integerValue]];
        [_textView setSelectedRange:NSMakeRange(location, 0)];
        [_textView scrollRangeToVisible:NSMakeRange(location, 0)];
        [self.window makeFirstResponder:_textView];
        [self refreshHeaderState];
        return;
    }
}

- (NSInteger)currentLineNumber
{
    NSString *text = _textView.string ?: @"";
    NSUInteger location = MIN(_textView.selectedRange.location, text.length);
    NSInteger line = 1;
    for (NSUInteger i = 0; i < location; i++) {
        if ([text characterAtIndex:i] == '\n') line++;
    }
    return line;
}

/* Places the caret on a physical line, used by Debug when a run-time error stops the
   program (the runtime reports absolute line numbers in the same code text). */
- (void)jumpToLine:(NSInteger)line
{
    NSUInteger location;
    if (line <= 0) return;
    location = [self locationForLine:line];
    [_textView setSelectedRange:NSMakeRange(location, 0)];
    [_textView scrollRangeToVisible:NSMakeRange(location, 0)];
    [self.window makeFirstResponder:_textView];
    [self refreshHeaderState];
    [self updateCurrentLineHighlight];
}

- (NSInteger)debugLine { return _debugLine; }

/* Break mode highlight: a yellow bar on the paused statement (VB6 uses the same color
   for the current statement when the program is suspended). */
- (void)applyDebugLineBackground
{
    NSTextStorage *storage = _textView.textStorage;
    NSString *text = _textView.string ?: @"";
    if (!storage) return;
    if (_debugLineRange.location != NSNotFound && NSMaxRange(_debugLineRange) <= storage.length) {
        [storage removeAttribute:NSBackgroundColorAttributeName range:_debugLineRange];
    }
    _debugLineRange = NSMakeRange(NSNotFound, 0);
    if (_debugLine <= 0) return;
    NSUInteger location = [self locationForLine:_debugLine];
    if (location > text.length) return;
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    if (NSMaxRange(lineRange) > storage.length) return;
    [storage addAttribute:NSBackgroundColorAttributeName value:VBColorBreakLine() range:lineRange];
    _debugLineRange = lineRange;
}

- (void)showDebugLine:(NSInteger)line
{
    if (line <= 0) {
        [self clearDebugLine];
        return;
    }
    _debugLine = line;
    _gutter.debugLine = line;
    NSUInteger location = [self locationForLine:line];
    [_textView setSelectedRange:NSMakeRange(location, 0)];
    [_textView scrollRangeToVisible:NSMakeRange(location, 0)];
    [self.window makeFirstResponder:_textView];
    [self refreshHeaderState];
    [self updateCurrentLineHighlight];
    [_gutter setNeedsDisplay:YES];
}

- (void)clearDebugLine
{
    if (_debugLine == 0 && _debugLineRange.location == NSNotFound) return;
    _debugLine = 0;
    _gutter.debugLine = 0;
    [self applyDebugLineBackground];
    [self updateCurrentLineHighlight];
    [_gutter setNeedsDisplay:YES];
}

#pragma mark - Breakpoints

- (NSIndexSet *)breakpointLines { return [_breakpoints copy]; }

- (void)setBreakpointLines:(NSIndexSet *)lines
{
    _breakpoints = [NSMutableIndexSet indexSet];
    if (lines) [_breakpoints addIndexes:lines];
    _gutter.breakpoints = [self breakpointLines];
    [_gutter setNeedsDisplay:YES];
}

/* Character location where a line starts, or the end of the text past the last line. */
- (NSUInteger)lineStartLocation:(NSUInteger)line inText:(NSString *)text
{
    NSUInteger location = 0, current = 1;
    if (line <= 1) return 0;
    while (current < line && location < text.length) {
        location = NSMaxRange([text lineRangeForRange:NSMakeRange(location, 0)]);
        current++;
    }
    return MIN(location, text.length);
}

- (void)notifyBreakpointsChanged
{
    _gutter.breakpoints = [self breakpointLines];
    [_gutter setNeedsDisplay:YES];
    if ([self.delegate respondsToSelector:@selector(codeEditorDidChangeBreakpoints:)]) {
        [self.delegate codeEditorDidChangeBreakpoints:self];
    }
}

- (void)reconcileBreakpointsFrom:(NSString *)oldText to:(NSString *)newText
{
    int count = 0, mappedCount = 0;
    int *lines;
    int *mapped;
    NSMutableIndexSet *moved;
    if (!_breakpoints.count) {
        _lastText = [newText copy];
        return;
    }
    lines = (int *)malloc(sizeof(int) * _breakpoints.count);
    if (!lines) return;
    for (NSUInteger line = [_breakpoints firstIndex]; line != NSNotFound;
         line = [_breakpoints indexGreaterThanIndex:line]) {
        lines[count++] = (int)line;
    }
    /* The mapping lives in core/vb_code.c, so the CLI harness covers the same logic the
       editor runs here (no window needed to test that dots follow their statements). */
    mapped = vb_code_follow_breakpoints(oldText.UTF8String, newText.UTF8String,
                                        lines, count, &mappedCount);
    moved = [NSMutableIndexSet indexSet];
    for (int i = 0; i < mappedCount; i++) [moved addIndex:(NSUInteger)mapped[i]];
    free(mapped);
    free(lines);
    if (![moved isEqualToIndexSet:_breakpoints]) {
        _breakpoints = moved;
        [self notifyBreakpointsChanged];
    }
    _lastText = [newText copy];
}

- (BOOL)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
    if (!string || NSMaxRange(range) > _textView.string.length) return NO;
    if (![_textView shouldChangeTextInRange:range replacementString:string]) return NO;
    [_textView.textStorage replaceCharactersInRange:range withString:string];
    [_textView didChangeText];
    return YES;
}

- (NSRange)rangeForLine:(NSInteger)line
{
    NSString *text = _textView.string ?: @"";
    if (line <= 0) return NSMakeRange(NSNotFound, 0);
    NSUInteger start = [self lineStartLocation:(NSUInteger)line inText:text];
    if (start > text.length) return NSMakeRange(NSNotFound, 0);
    return [text lineRangeForRange:NSMakeRange(start, 0)];
}

- (void)toggleBreakpointAtLine:(NSInteger)line
{
    NSString *text = _code ?: @"";
    NSUInteger index;
    if (line <= 0 || !text.length) return;
    /* VB6 only marks executable statements; "Dim", "End Sub" and labels beep. */
    if (!vb_code_line_executable(text.UTF8String, (int)line)) {
        fprintf(stderr, "[breakpoint] line %ld is not an executable statement\n", (long)line);
        NSBeep();
        return;
    }
    index = (NSUInteger)line;
    if ([_breakpoints containsIndex:index]) [_breakpoints removeIndex:index];
    else [_breakpoints addIndex:index];
    _gutter.breakpoints = [self breakpointLines];
    [_gutter setNeedsDisplay:YES];
    fprintf(stderr, "[breakpoint] line %ld %s\n", (long)line,
            [_breakpoints containsIndex:index] ? "set" : "cleared");
    [self notifyBreakpointsChanged];
}

/* Walks the visible line fragments exactly as the gutter draws them (same coordinate
   conversion, so a click lands on the row whose dot and number are under the pointer)
   and reports the rect of a line, or the line at a point. */
- (BOOL)gutterRect:(NSRect *)outRect forLine:(NSInteger)line
{
    NSLayoutManager *layout = _textView.layoutManager;
    NSString *text = _textView.string ?: @"";
    NSRange glyphs;
    __block BOOL found = NO;
    if (!layout) return NO;
    [layout ensureLayoutForTextContainer:_textView.textContainer];
    glyphs = [layout glyphRangeForTextContainer:_textView.textContainer];
    [layout enumerateLineFragmentsForGlyphRange:glyphs
                                     usingBlock:^(NSRect fragRect, NSRect usedRect, NSTextContainer *tc,
                                                  NSRange lineGlyphs, BOOL *stop) {
        NSUInteger location = [layout characterIndexForGlyphAtIndex:lineGlyphs.location];
        NSInteger textLine = 1;
        NSUInteger limit = MIN(location, text.length);
        (void)usedRect;
        (void)tc;
        for (NSUInteger i = 0; i < limit; i++) {
            if ([text characterAtIndex:i] == '\n') textLine++;
        }
        if (textLine == line) {
            if (outRect) *outRect = [self->_gutter convertRect:fragRect fromView:self->_textView];
            found = YES;
            *stop = YES;
        }
    }];
    return found;
}

- (NSInteger)gutterLineAtPoint:(NSPoint)point
{
    NSLayoutManager *layout = _textView.layoutManager;
    NSString *text = _textView.string ?: @"";
    NSPoint inGutter = [_gutter convertPoint:point fromView:self];
    NSRange glyphs;
    __block NSInteger hit = 0;
    if (!layout || !NSPointInRect(inGutter, _gutter.bounds)) return 0;
    [layout ensureLayoutForTextContainer:_textView.textContainer];
    glyphs = [layout glyphRangeForTextContainer:_textView.textContainer];
    [layout enumerateLineFragmentsForGlyphRange:glyphs
                                     usingBlock:^(NSRect fragRect, NSRect usedRect, NSTextContainer *tc,
                                                  NSRange lineGlyphs, BOOL *stop) {
        NSRect rect = [self->_gutter convertRect:fragRect fromView:self->_textView];
        NSUInteger location = [layout characterIndexForGlyphAtIndex:lineGlyphs.location];
        NSInteger textLine = 1;
        NSUInteger limit = MIN(location, text.length);
        (void)usedRect;
        (void)tc;
        for (NSUInteger i = 0; i < limit; i++) {
            if ([text characterAtIndex:i] == '\n') textLine++;
        }
        if (inGutter.y >= NSMinY(rect) && inGutter.y < NSMaxY(rect)) {
            hit = textLine;
            *stop = YES;
        }
    }];
    return hit;
}

/* Point on a line's row inside the gutter, in editor coordinates. */
- (NSPoint)gutterPointForLine:(NSInteger)line
{
    NSRect rect = NSZeroRect;
    if (![self gutterRect:&rect forLine:line]) {
        return NSMakePoint(7, NSMidY(_gutter.frame));
    }
    /* gutterRect: works in the gutter's coordinates; callers click in editor space. */
    return [_gutter convertPoint:NSMakePoint(7, NSMidY(rect)) toView:self];
}

- (BOOL)toggleBreakpointAtGutterPoint:(NSPoint)point
{
    NSInteger line = [self gutterLineAtPoint:point];
    if (line <= 0) return NO;
    [self toggleBreakpointAtLine:line];
    return YES;
}

- (void)selectObjectItem:(NSMenuItem *)sender
{
    NSString *object = sender.representedObject;
    _objectTitle = object ?: @"(General)";
    _procedureTitle = @"(Declarations)";
    [self setNeedsDisplay:YES];
    if ([_objectTitle isEqualToString:@"(General)"]) {
        [_textView setSelectedRange:NSMakeRange(0, 0)];
        [_textView scrollRangeToVisible:NSMakeRange(0, 0)];
        [self.window makeFirstResponder:_textView];
        return;
    }
    for (NSDictionary *entry in [self handlerEntries]) {
        if ([[self objectForHandler:entry[@"name"]] isEqualToString:_objectTitle]) {
            [self jumpToHandlerNamed:entry[@"name"]];
            return;
        }
    }
}

- (void)selectProcedureItem:(NSMenuItem *)sender
{
    NSString *procedure = sender.representedObject;
    _procedureTitle = procedure ?: @"(Declarations)";
    [self setNeedsDisplay:YES];
    if ([_procedureTitle isEqualToString:@"(Declarations)"]) {
        NSUInteger location = 0;
        for (NSDictionary *entry in [self handlerEntries]) {
            if ([[self objectForHandler:entry[@"name"]] isEqualToString:_objectTitle]) {
                location = [self locationForLine:[entry[@"line"] integerValue]];
                break;
            }
        }
        [_textView setSelectedRange:NSMakeRange(location, 0)];
        [_textView scrollRangeToVisible:NSMakeRange(location, 0)];
        [self.window makeFirstResponder:_textView];
        return;
    }
    NSString *handler = [NSString stringWithFormat:@"%@_%@", _objectTitle, _procedureTitle];
    [self jumpToHandlerNamed:handler];
}

- (NSString *)code { return _code ?: @""; }

- (void)scrollBoundsChanged:(NSNotification *)notification
{
    (void)notification;
    [_gutter setNeedsDisplay:YES];
}

- (void)setCode:(NSString *)code
{
    _code = [code copy] ?: @"";
    _highlighting = YES;
    _textView.string = _code;
    _highlighting = NO;
    _currentLineRange = NSMakeRange(NSNotFound, 0);
    _lastText = [_code copy];
    [self applyHighlighting];
    [_textView setSelectedRange:NSMakeRange(0, 0)];
    [_textView scrollRangeToVisible:NSMakeRange(0, 0)];
    _objectTitle = @"(General)";
    _procedureTitle = @"(Declarations)";
    [self refreshHeaderState];
    [self setNeedsDisplay:YES];
    [_gutter setNeedsDisplay:YES];
    /* A new text invalidates the old line numbers; the owner sets the form's set after
       this call when it wants them back. */
    [self setBreakpointLines:nil];
}

- (NSDictionary *)baseAttributes
{
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 2.5;
    paragraph.defaultTabInterval = 28;
    paragraph.tabStops = @[];
    return @{
        NSFontAttributeName: VBFontCode(),
        NSForegroundColorAttributeName: VBColorCodeText(),
        NSParagraphStyleAttributeName: paragraph
    };
}

- (void)updateCurrentLineHighlight
{
    if (_highlighting) return;
    NSTextStorage *storage = _textView.textStorage;
    NSString *text = _textView.string ?: @"";
    if (!storage) return;
    if (_currentLineRange.location != NSNotFound && NSMaxRange(_currentLineRange) <= storage.length) {
        [storage removeAttribute:NSBackgroundColorAttributeName range:_currentLineRange];
    }
    NSUInteger location = MIN(_textView.selectedRange.location, text.length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(location, 0)];
    if (NSMaxRange(lineRange) <= storage.length) {
        [storage addAttribute:NSBackgroundColorAttributeName value:VBColorCurrentLine() range:lineRange];
        _currentLineRange = lineRange;
    }
    /* The paused statement keeps the break color even when the caret is on it. */
    [self applyDebugLineBackground];
    [_gutter setNeedsDisplay:YES];
}

- (void)applyHighlighting
{
    NSString *text = _textView.string ?: @"";
    NSTextStorage *storage = _textView.textStorage;
    if (!storage) return;

    _highlighting = YES;
    NSRange selection = _textView.selectedRange;
    NSDictionary *base = [self baseAttributes];

    [storage beginEditing];
    [storage setAttributes:base range:NSMakeRange(0, storage.length)];

    const char *utf8 = text.UTF8String;
    NSUInteger byteLength = utf8 ? strlen(utf8) : 0;
    BOOL ascii = (text.length == byteLength);
    NSData *data = ascii ? nil : [text dataUsingEncoding:NSUTF8StringEncoding];
    VbSpanList spans;
    vb_spanlist_init(&spans);
    vb_code_highlight(utf8 ? utf8 : "", byteLength, &spans);

    for (size_t i = 0; i < spans.count; i++) {
        VbSpan span = spans.items[i];
        NSRange range;
        if (ascii) {
            range = NSMakeRange(span.start, span.len);
        } else {
            NSString *prefix = [[NSString alloc] initWithBytes:data.bytes length:span.start encoding:NSUTF8StringEncoding];
            NSString *token = [[NSString alloc] initWithBytes:(const uint8_t *)data.bytes + span.start
                                                       length:span.len
                                                     encoding:NSUTF8StringEncoding];
            if (!prefix || !token) continue;
            range = NSMakeRange(prefix.length, token.length);
        }
        if (range.location > storage.length || range.location + range.length > storage.length) continue;

        NSColor *color = nil;
        BOOL bold = NO;
        switch (span.cls) {
            case VB_TOK_KEYWORD: color = VBColorKeyword(); bold = YES; break;
            case VB_TOK_TYPE: color = VBColorType(); break;
            case VB_TOK_FUNCTION: color = VBColorBuiltin(); break;
            case VB_TOK_CONSTANT: color = VBColorConstant(); break;
            case VB_TOK_STRING: color = VBColorString(); break;
            case VB_TOK_COMMENT: color = VBColorComment(); break;
            case VB_TOK_NUMBER: color = VBColorNumber(); break;
            case VB_TOK_OPERATOR: color = VBColorCodeText(); break;
            default: break;
        }
        if (color) [storage addAttribute:NSForegroundColorAttributeName value:color range:range];
        if (bold) [storage addAttribute:NSFontAttributeName value:VBFontCodeBold() range:range];
    }
    vb_spanlist_free(&spans);
    [storage endEditing];

    if (selection.location <= text.length) {
        _textView.selectedRange = selection;
    }
    _highlighting = NO;
    _currentLineRange = NSMakeRange(NSNotFound, 0);
    /* setAttributes: above dropped every background, including the break bar. */
    _debugLineRange = NSMakeRange(NSNotFound, 0);
    [self updateCurrentLineHighlight];
    [_gutter setNeedsDisplay:YES];
}

- (void)textDidChange:(NSNotification *)notification
{
    (void)notification;
    if (_highlighting) return;
    NSString *previous = _lastText;
    _code = [_textView.string copy] ?: @"";
    if (previous) [self reconcileBreakpointsFrom:previous to:_code];
    else _lastText = [_code copy];
    [self applyHighlighting];
    [self refreshHeaderState];
    if (self.delegate) [self.delegate codeEditorDidChange:self];
}

- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    (void)notification;
    [self updateCurrentLineHighlight];
    [self refreshHeaderState];
}

- (BOOL)writeTextViewSnapshot:(NSString *)path
{
    [_textView layoutSubtreeIfNeeded];
    [_textView displayIfNeeded];
    NSBitmapImageRep *rep = [_textView bitmapImageRepForCachingDisplayInRect:_textView.bounds];
    if (!rep) return NO;
    [_textView cacheDisplayInRect:_textView.bounds toBitmapImageRep:rep];
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [data writeToFile:path atomically:YES];
}

- (BOOL)writeScrollViewSnapshot:(NSString *)path
{
    [_scroll layoutSubtreeIfNeeded];
    [_scroll displayIfNeeded];
    NSBitmapImageRep *rep = [_scroll bitmapImageRepForCachingDisplayInRect:_scroll.bounds];
    if (!rep) return NO;
    [_scroll cacheDisplayInRect:_scroll.bounds toBitmapImageRep:rep];
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [data writeToFile:path atomically:YES];
}

- (void)focusEditor
{
    [self.window makeFirstResponder:_textView];
}

- (void)insertHandlerForControl:(NSString *)control event:(NSString *)event
{
    NSString *name = [NSString stringWithFormat:@"%@_%@", control, event];
    NSString *current = _textView.string ?: @"";
    char *body = vb_code_handler_body(current.UTF8String, name.UTF8String);
    BOOL exists = body != NULL;
    free(body);

    if (exists) {
        NSRange range = [current rangeOfString:[NSString stringWithFormat:@"Sub %@", name]
                                       options:NSCaseInsensitiveSearch];
        if (range.location != NSNotFound) {
            NSRange lineRange = [current lineRangeForRange:range];
            [_textView setSelectedRange:NSMakeRange(lineRange.location, 0)];
            [_textView scrollRangeToVisible:NSMakeRange(lineRange.location, 0)];
            [self.window makeFirstResponder:_textView];
            return;
        }
    }

    NSMutableString *updated = [current mutableCopy];
    if (![updated hasSuffix:@"\n"]) [updated appendString:@"\n"];
    [updated appendFormat:@"\nPrivate Sub %@()\n\nEnd Sub\n", name];
    _code = [updated copy];
    _highlighting = YES;
    _textView.string = _code;
    _highlighting = NO;
    _lastText = [_code copy];
    [self applyHighlighting];

    NSRange marker = [_code rangeOfString:[NSString stringWithFormat:@"Private Sub %@()", name]
                                  options:NSBackwardsSearch];
    NSUInteger cursor = marker.location + marker.length;
    cursor = MIN(cursor, _code.length);
    [_textView setSelectedRange:NSMakeRange(cursor, 0)];
    [_textView scrollRangeToVisible:NSMakeRange(cursor, 0)];
    [self.window makeFirstResponder:_textView];
    if (self.delegate) [self.delegate codeEditorDidChange:self];
}

#pragma mark - Autocomplete

static NSArray<NSString *> *VBCompletionKeywords(void)
{
    static NSArray<NSString *> *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        words = [@[
            @"As", @"ByRef", @"ByVal", @"Boolean", @"Byte", @"Call", @"Case", @"Class",
            @"Close", @"Const", @"Currency", @"Date", @"Declare", @"Dim", @"Do", @"Double",
            @"Each", @"Else", @"ElseIf", @"End", @"Enum", @"Error", @"Exit", @"False",
            @"For", @"Function", @"Get", @"Global", @"GoSub", @"GoTo", @"If", @"Implements",
            @"Inherits", @"Input", @"Integer", @"Let", @"Line", @"Local", @"Long", @"Loop",
            @"Me", @"Mod", @"New", @"Next", @"Nothing", @"Null", @"Object", @"On", @"Open",
            @"Option", @"Optional", @"Or", @"Private", @"Property", @"Public", @"Randomize",
            @"ReDim", @"Resume", @"Return", @"Select", @"Set", @"Single", @"Static", @"Step",
            @"Stop", @"String", @"Sub", @"Then", @"To", @"True", @"Type", @"Until", @"Variant",
            @"Wend", @"While", @"With", @"Xor",
            @"MsgBox", @"InputBox", @"Len", @"Left", @"Right", @"Mid", @"InStr", @"UCase",
            @"LCase", @"Trim", @"LTrim", @"RTrim", @"CStr", @"CInt", @"CLng", @"CDbl",
            @"CSng", @"CBool", @"IsNull", @"IsEmpty", @"IsNumeric", @"Abs", @"Int", @"Fix",
            @"Sgn", @"Sqr", @"Rnd", @"Timer", @"Now", @"Date", @"Time", @"Format",
            @"Load", @"Unload", @"Print", @"Cls", @"Refresh", @"SetFocus",
            @"Caption", @"Name", @"Text", @"Visible", @"Enabled", @"TabIndex", @"TabStop",
            @"Top", @"Left", @"Width", @"Height", @"BackColor", @"ForeColor", @"Font",
            @"BorderStyle", @"Alignment", @"Value", @"Index", @"Tag", @"ToolTipText"
        ] copy];
    });
    return words;
}

- (NSArray<NSString *> *)completionCandidates
{
    NSMutableOrderedSet<NSString *> *set = [NSMutableOrderedSet orderedSet];
    [set addObjectsFromArray:VBCompletionKeywords()];

    for (NSDictionary *entry in [self handlerEntries]) {
        NSString *name = entry[@"name"];
        if (name.length) {
            [set addObject:name];
            NSRange underscore = [name rangeOfString:@"_" options:NSBackwardsSearch];
            if (underscore.location != NSNotFound)
                [set addObject:[name substringFromIndex:NSMaxRange(underscore)]];
        }
    }
    for (NSString *object in [self objectNames])
        if (object.length && ![object hasPrefix:@"("]) [set addObject:object];

    NSString *code = _code ?: @"";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"\\b(?:Dim|Private|Public|Global|Static|Const|Sub|Function|Property|Type|Class|Enum)\\s+([A-Za-z_][A-Za-z0-9_]*)"
        options:NSRegularExpressionCaseInsensitive error:nil];
    [re enumerateMatchesInString:code options:0 range:NSMakeRange(0, code.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        (void)flags; (void)stop;
        if (m.numberOfRanges > 1) {
            NSString *name = [code substringWithRange:[m rangeAtIndex:1]];
            if (name.length) [set addObject:name];
        }
    }];
    return [set.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray<NSString *> *)completionMatchesForPrefix:(NSString *)prefix
{
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *candidate in [self completionCandidates]) {
        if (prefix.length == 0 || [candidate rangeOfString:prefix
                                                   options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound)
            [matches addObject:candidate];
        if (matches.count >= 64) break;
    }
    return matches;
}

- (void)completeWord
{
    [self.window makeFirstResponder:_textView];
    [_textView complete:nil];
}

- (NSArray<NSString *> *)textView:(NSTextView *)textView
                       completions:(NSArray<NSString *> *)words
               forPartialWordRange:(NSRange)charRange
               indexOfSelectedItem:(NSInteger *)index
{
    (void)words;
    NSString *text = textView.string ?: @"";
    if (NSMaxRange(charRange) > text.length) return @[];
    if (index) *index = 0;
    return [self completionMatchesForPrefix:[text substringWithRange:charRange]];
}

@end

