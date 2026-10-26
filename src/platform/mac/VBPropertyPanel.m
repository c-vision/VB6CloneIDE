#import "VBPropertyPanel.h"
#import "VBTheme.h"

#include "core/vb_util.h"

static const CGFloat kHeaderHeight = 20.0;
static const CGFloat kComboHeight = 18.0;
static const CGFloat kRowHeight = 18.0;

@interface VBPropertyRowView : NSTableRowView
@end

@implementation VBPropertyRowView
- (void)drawBackgroundInRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[VBColorFace() colorWithAlphaComponent:0.72] setFill];
    NSRectFill(self.bounds);
    [[VBColorShadow() colorWithAlphaComponent:0.35] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
    [[VBColorLight() colorWithAlphaComponent:0.5] setFill];
    NSRectFill(NSMakeRect(NSWidth(self.bounds) / 2, 0, 1, NSHeight(self.bounds)));
}
@end

@implementation VBPropertyPanel {
    NSTableView *_table;
    NSScrollView *_scroll;
    NSMutableArray<NSString *> *_keys;
    NSArray<NSDictionary *> *_objects;
    VbControl *_control;
    NSRect _comboRect;
    BOOL _comboPressed;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (!self) return nil;

    _keys = [NSMutableArray array];
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(1, kHeaderHeight + kComboHeight + 6,
                                                             NSWidth(frameRect) - 2,
                                                             NSHeight(frameRect) - kHeaderHeight - kComboHeight - 7)];
    _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scroll.hasVerticalScroller = YES;
    _scroll.borderType = NSNoBorder;
    _scroll.drawsBackground = YES;
    _scroll.backgroundColor = VBColorFace();
    _scroll.scrollerStyle = NSScrollerStyleLegacy;

    _table = [[NSTableView alloc] initWithFrame:_scroll.bounds];
    _table.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _table.headerView = nil;
    _table.rowHeight = kRowHeight;
    _table.intercellSpacing = NSMakeSize(0, 0);
    _table.gridStyleMask = NSTableViewGridNone;
    _table.backgroundColor = VBColorFace();
    _table.usesAlternatingRowBackgroundColors = NO;
    _table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _table.allowsMultipleSelection = NO;
    _table.dataSource = self;
    _table.delegate = self;

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"key"];
    nameColumn.width = 116;
    nameColumn.minWidth = 90;
    nameColumn.resizingMask = NSTableColumnUserResizingMask;
    [_table addTableColumn:nameColumn];

    NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
    valueColumn.width = 160;
    valueColumn.minWidth = 80;
    valueColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:valueColumn];

    _scroll.documentView = _table;
    [self addSubview:_scroll];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (VbControl *)control { return _control; }

- (void)setObjects:(NSArray<NSDictionary *> *)objects
{
    _objects = [objects copy] ?: @[];
    [self setNeedsDisplay:YES];
}

- (void)setControl:(VbControl *)control
{
    _control = control;
    [self reload];
}

- (void)addKeyIfMissing:(NSMutableArray *)all key:(NSString *)key
{
    if (![all containsObject:key]) [all addObject:key];
}

- (void)reload
{
    [_keys removeAllObjects];
    if (_control) {
        NSString *type = _control->type ? [NSString stringWithUTF8String:_control->type] : @"";
        NSMutableArray *all = [NSMutableArray array];
        [all addObject:@"Name"];

        if ([type isEqualToString:@"VB.Form"]) {
            [all addObjectsFromArray:@[@"Caption", @"ClientWidth", @"ClientHeight", @"BackColor",
                                       @"BorderStyle", @"StartUpPosition", @"MinButton", @"MaxButton"]];
        } else {
            BOOL hasCaption = [type isEqualToString:@"VB.Label"] || [type isEqualToString:@"VB.CommandButton"] ||
                              [type isEqualToString:@"VB.CheckBox"] || [type isEqualToString:@"VB.OptionButton"] ||
                              [type isEqualToString:@"VB.Frame"] || [type isEqualToString:@"VB.Data"];
            if (hasCaption) [all addObject:@"Caption"];
            if ([type isEqualToString:@"VB.TextBox"] || [type isEqualToString:@"VB.ComboBox"] ||
                [type isEqualToString:@"VB.ListBox"]) {
                [all addObject:@"Text"];
            }
            if ([type isEqualToString:@"VB.TextBox"]) {
                [all addObjectsFromArray:@[@"MultiLine", @"PasswordChar"]];
            }
            if ([type isEqualToString:@"VB.Label"]) [all addObject:@"Alignment"];
            if ([type isEqualToString:@"VB.Timer"]) [all addObject:@"Interval"];
            if ([type isEqualToString:@"VB.CheckBox"] || [type isEqualToString:@"VB.OptionButton"]) [all addObject:@"Value"];
            if ([type isEqualToString:@"VB.HScrollBar"] || [type isEqualToString:@"VB.VScrollBar"]) {
                [all addObjectsFromArray:@[@"Min", @"Max", @"Value", @"LargeChange", @"SmallChange"]];
            }
            if ([type isEqualToString:@"VB.Data"]) {
                [all addObjectsFromArray:@[@"Connect", @"DatabaseName", @"RecordSource", @"RecordsetType",
                                           @"BOFAction", @"EOFAction", @"ReadOnly", @"Exclusive",
                                           @"Options"]];
            }
            if ([type isEqualToString:@"VB.DataGrid"]) {
                [all addObjectsFromArray:@[@"DataSource", @"AllowAddNew", @"AllowDelete", @"AllowUpdate",
                                           @"ColumnHeaders", @"DefColWidth", @"RowHeight",
                                           @"AllowRowSizing", @"AllowColSizing"]];
            }
            if ([type isEqualToString:@"VB.CommonDialog"]) {
                [all addObjectsFromArray:@[@"Action", @"DialogTitle", @"Filter", @"FilterIndex",
                                           @"FileName", @"Flags", @"Color", @"CancelError"]];
            }
            [all addObjectsFromArray:@[@"Left", @"Top", @"Width", @"Height", @"Visible", @"Enabled",
                                       @"TabIndex", @"TabStop", @"BackColor", @"ForeColor",
                                       @"Font.Name", @"Font.Size", @"ToolTipText", @"Tag"]];
        }
        for (int i = 0; i < _control->nprops; i++) {
            NSString *key = [NSString stringWithUTF8String:_control->props[i].key];
            if (key) [self addKeyIfMissing:all key:key];
        }
        [all removeObject:@"Name"];
        NSMutableArray *sorted = [[all sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] mutableCopy];
        [sorted insertObject:@"Name" atIndex:0];
        [_keys addObjectsFromArray:sorted];
    }
    [_table reloadData];
    [self setNeedsDisplay:YES];
}

- (NSString *)displayValueForKey:(NSString *)key
{
    if (!_control) return @"";
    if ([key isEqualToString:@"Name"]) {
        return _control->name ? [NSString stringWithUTF8String:_control->name] : @"";
    }
    if (vb_prop_is_boolean(key.UTF8String)) {
        /* Enabled/Visible/TabStop are on unless the form says otherwise; everything else
           (a check box, a read-only flag) defaults to False like in VB6. */
        /* ColumnHeaders and AllowUpdate are the DataGrid flags VB6 turns on by default. */
        int fallback = ([key isEqualToString:@"Visible"] || [key isEqualToString:@"Enabled"] ||
                        [key isEqualToString:@"TabStop"] || [key isEqualToString:@"ColumnHeaders"] ||
                        [key isEqualToString:@"AllowUpdate"]) ? -1 : 0;
        return vb_control_get_int(_control, key.UTF8String, fallback) ? @"True" : @"False";
    }
    if ([key isEqualToString:@"BackColor"]) {
        const char *value = vb_control_get(_control, "BackColor");
        return value ? [NSString stringWithUTF8String:value] : @"&H8000000F&";
    }
    if ([key isEqualToString:@"ForeColor"]) {
        const char *value = vb_control_get(_control, "ForeColor");
        return value ? [NSString stringWithUTF8String:value] : @"&H80000012&";
    }
    if ([key isEqualToString:@"Font.Name"]) {
        const char *value = vb_control_get(_control, "Font.Name");
        return value ? [NSString stringWithUTF8String:value] : @"MS Sans Serif";
    }
    if ([key isEqualToString:@"Font.Size"]) {
        const char *value = vb_control_get(_control, "Font.Size");
        return value ? [NSString stringWithUTF8String:value] : @"9";
    }
    char *value = vb_control_get_display(_control, key.UTF8String);
    NSString *text = value ? [NSString stringWithUTF8String:value] : @"";
    free(value);
    return text;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    VBFillFace(self.bounds);

    NSString *name = _control && _control->name ? [NSString stringWithUTF8String:_control->name] : @"";
    NSString *title = name.length ? [NSString stringWithFormat:@"Properties - %@", name] : @"Properties";
    VBDrawTitleBar(NSMakeRect(0, 0, NSWidth(self.bounds), kHeaderHeight), title, YES, NO, NO, NO);
    [[VBColorShadow() colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(0, kHeaderHeight, NSWidth(self.bounds), 1));

    // Object selector combo box
    _comboRect = NSMakeRect(5, kHeaderHeight + 3, NSWidth(self.bounds) - 10, kComboHeight);
    VBDrawSunkenBevel(_comboRect);
    NSRect arrow = NSMakeRect(NSMaxX(_comboRect) - 17, NSMinY(_comboRect) + 2, 15, NSHeight(_comboRect) - 4);
    if (_comboPressed) VBDrawPressedBevel(arrow);
    else VBDrawRaisedBevel(arrow);
    VBDrawClassicArrow(NSMakeRect(NSMidX(arrow) - 4, NSMidY(arrow) - 2, 8, 5), YES, VBColorText());

    NSString *comboTitle = name.length ? name : @"";
    NSDictionary *comboAttrs = @{NSFontAttributeName: VBFontUI(),
                                 NSForegroundColorAttributeName: VBColorText()};
    [comboTitle drawInRect:NSMakeRect(NSMinX(_comboRect) + 3, NSMidY(_comboRect) - 7,
                                      NSWidth(_comboRect) - 24, 14)
            withAttributes:comboAttrs];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, _comboRect)) return;
    _comboPressed = YES;
    [self setNeedsDisplay:YES];

    if (_objects.count) {
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Objects"];
        for (NSDictionary *entry in _objects) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[@"title"] action:nil keyEquivalent:@""];
            item.representedObject = entry[@"value"];
            item.target = self;
            item.action = @selector(selectObjectFromMenu:);
            [menu addItem:item];
        }
        NSPoint screen = [self.window convertPointToScreen:
                          [self convertPoint:NSMakePoint(NSMinX(_comboRect), NSMaxY(_comboRect)) toView:nil]];
        [menu popUpMenuPositioningItem:nil atLocation:screen inView:nil];
    }
    _comboPressed = NO;
    [self setNeedsDisplay:YES];
}

- (void)selectObjectFromMenu:(NSMenuItem *)sender
{
    VbControl *control = (VbControl *)[sender.representedObject pointerValue];
    if (!control) return;
    _control = control;
    [self reload];
    if (self.delegate) [self.delegate propertyPanel:self didSelectControl:control];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)_keys.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    (void)tableView;
    (void)row;
    return [[VBPropertyRowView alloc] initWithFrame:NSMakeRect(0, 0, 260, kRowHeight)];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    (void)tableView;
    if (row < 0 || row >= (NSInteger)_keys.count) return nil;
    NSString *key = _keys[(NSUInteger)row];
    BOOL isValue = [tableColumn.identifier isEqualToString:@"value"];
    NSString *identifier = isValue ? @"value" : @"key";
    NSTableCellView *cell = (NSTableCellView *)[_table makeViewWithIdentifier:identifier owner:self];

    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 150, kRowHeight)];
        cell.identifier = identifier;
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(3, 2, 140, 14)];
        field.autoresizingMask = NSViewWidthSizable;
        field.bezeled = NO;
        field.bordered = NO;
        field.focusRingType = NSFocusRingTypeNone;
        field.font = VBFontUI();
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        if (isValue) {
            field.editable = YES;
            field.selectable = YES;
            field.drawsBackground = YES;
            field.backgroundColor = VBColorWindow();
            field.wantsLayer = YES;
            field.layer.borderWidth = 1;
            field.layer.borderColor = [[VBColorShadow() colorWithAlphaComponent:0.9] CGColor];
            field.delegate = self;
            field.textColor = VBColorText();
        } else {
            field.editable = NO;
            field.selectable = NO;
            field.drawsBackground = NO;
            field.textColor = VBColorText();
        }
        [cell addSubview:field];
        cell.textField = field;
    }

    cell.textField.stringValue = isValue ? [self displayValueForKey:key] : key;
    cell.textField.tag = row;
    cell.textField.enabled = isValue;
    return cell;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSInteger row = field.tag;
    if (row < 0 || row >= (NSInteger)_keys.count) return;
    NSString *key = _keys[(NSUInteger)row];
    NSString *value = field.stringValue;
    if (!self.delegate || ![self.delegate propertyPanel:self setValue:value forKey:key]) {
        [_table reloadData];
        return;
    }
    [self reload];
}

@end
