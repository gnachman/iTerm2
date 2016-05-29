//
//  TriggerController.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "TriggerController.h"

#import "AlertTrigger.h"
#import "BellTrigger.h"
#import "BounceTrigger.h"
#import "CaptureTrigger.h"
#import "CoprocessTrigger.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "GrowlTrigger.h"
#import "HighlightTrigger.h"
#import "ITAddressBookMgr.h"
#import "iTermNoColorAccessoryButton.h"
#import "MarkTrigger.h"
#import "NSColor+iTerm.h"
#import "PasswordTrigger.h"
#import "ProfileModel.h"
#import "ScriptTrigger.h"
#import "SendTextTrigger.h"
#import "SetDirectoryTrigger.h"
#import "SetHostnameTrigger.h"
#import "StopTrigger.h"
#import "Trigger.h"

#import <ColorPicker/ColorPicker.h>

static NSString *const kiTermTriggerControllerPasteboardType =
    @"kiTermTriggerControllerPasteboardType";

static NSString *const kRegexColumnIdentifier = @"kRegexColumnIdentifier";
static NSString *const kParameterColumnIdentifier = @"kParameterColumnIdentifier";
static NSString *const kTextColorWellIdentifier = @"kTextColorWellIdentifier";
static NSString *const kBackgroundColorWellIdentifier = @"kBackgroundColorWellIdentifier";

// This is a color well that continues to work after it's removed from the view
// hierarchy. NSTableView likes to randomly remove its views, so a regular
// CPKColorWell won't work properly. A popover gets angry if its presenting
// view is not in the view hierarchy while it's opening, and unfortunately
// merely opening a popover triggers the table view to reload some of its views
// (at least sometimes, on OS 10.10).
@interface iTermColorWell : CPKColorWell
@end

@implementation iTermColorWell

- (NSRect)presentationRect {
    NSScrollView *scrollView = [self enclosingScrollView];
    return [scrollView convertRect:self.bounds fromView:self];
}

- (NSView *)presentingView {
    return [self enclosingScrollView];
}

@end

@interface TriggerController() <NSTextFieldDelegate>
// Keeps the color well whose popover is currently open from getting
// deallocated. It may get removed from the view hierarchy but we need it to
// continue existing so we can get the color out of it.
@property(nonatomic, retain) iTermColorWell *activeWell;
@end

@implementation TriggerController {
    NSArray *_triggers;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_regexColumn;
    IBOutlet NSTableColumn *_partialLineColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSTableColumn *_parametersColumn;
    IBOutlet NSButton *_removeTriggerButton;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableArray *triggers = [NSMutableArray array];
        for (Class class in [self triggerClasses]) {
            [triggers addObject:[[[class alloc] init] autorelease]];
        }
        _triggers = [triggers retain];
    }
    return self;
}

- (void)dealloc {
    [_guid release];
    [_triggers release];
    [super dealloc];
}

- (NSArray *)triggerClasses {
    NSArray *allClasses = @[ [AlertTrigger class],
                             [BellTrigger class],
                             [BounceTrigger class],
                             [CaptureTrigger class],
                             [GrowlTrigger class],
                             [SendTextTrigger class],
                             [ScriptTrigger class],
                             [CoprocessTrigger class],
                             [MuteCoprocessTrigger class],
                             [HighlightTrigger class],
                             [MarkTrigger class],
                             [PasswordTrigger class],
                             [SetDirectoryTrigger class],
                             [SetHostnameTrigger class],
                             [StopTrigger class] ];

    return [allClasses sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                  return [[obj1 title] compare:[obj2 title]];
              }];
}

- (void)awakeFromNib {
    [_tableView registerForDraggedTypes:@[ kiTermTriggerControllerPasteboardType ]];
    _tableView.doubleAction = @selector(doubleClick:);
    _tableView.target = self;
}

- (void)windowWillOpen {
    for (Trigger *trigger in _triggers) {
        [trigger reloadData];
    }
}

- (int)numberOfTriggers {
    return [[self triggerClasses] count];
}

- (int)indexOfAction:(NSString *)action {
    int n = [self numberOfTriggers];
    NSArray *classes = [self triggerClasses];
    for (int i = 0; i < n; i++) {
        NSString *className = NSStringFromClass(classes[i]);
        if ([className isEqualToString:action]) {
            return i;
        }
    }
    return -1;
}

// Index in triggerClasses of an object of class "c"
- (NSInteger)indexOfTriggerClass:(Class)c {
    NSArray *classes = [self triggerClasses];
    for (int i = 0; i < classes.count; i++) {
        if (classes[i] == c) {
            return i;
        }
    }
    return -1;
}

- (Trigger *)triggerWithAction:(NSString *)action {
    int i = [self indexOfAction:action];
    if (i == -1) {
        return nil;
    }
    return _triggers[i];
}

- (Profile *)bookmark {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (NSArray *)triggerDictionariesForCurrentProfile {
    Profile *bookmark = [self bookmark];
    NSArray *triggers = [bookmark objectForKey:KEY_TRIGGERS];
    return triggers ? triggers : [NSArray array];
}

- (void)setTriggerDictionary:(NSDictionary *)triggerDictionary
                      forRow:(NSInteger)rowIndex
                  reloadData:(BOOL)shouldReload {
    if (shouldReload) {
        // Stop editing. A reload while editing crashes.
        [_tableView reloadData];
    }
    NSMutableArray *triggerDictionaries = [[[self triggerDictionariesForCurrentProfile] mutableCopy] autorelease];
    if (rowIndex < 0) {
        assert(triggerDictionary);
        [triggerDictionaries addObject:triggerDictionary];
    } else {
        if (triggerDictionary) {
            [triggerDictionaries replaceObjectAtIndex:rowIndex withObject:triggerDictionary];
        } else {
            [triggerDictionaries removeObjectAtIndex:rowIndex];
        }
    }
    [_delegate triggerChanged:self newValue:triggerDictionaries];
    if (shouldReload) {
        [_tableView reloadData];
    }
}

- (void)moveTriggerOnRow:(int)sourceRow toRow:(int)destinationRow {
    // Stop editing. A reload while editing crashes.
    [_tableView reloadData];
    NSMutableArray *triggerDictionaries = [[[self triggerDictionariesForCurrentProfile] mutableCopy] autorelease];
    if (destinationRow > sourceRow) {
        --destinationRow;
    }
    NSDictionary *temp = [[triggerDictionaries[sourceRow] retain] autorelease];
    [triggerDictionaries removeObjectAtIndex:sourceRow];
    [triggerDictionaries insertObject:temp atIndex:destinationRow];
    [_delegate triggerChanged:self newValue:triggerDictionaries];
    [_tableView reloadData];
}

- (BOOL)actionTakesParameter:(NSString *)action {
    return [[self triggerWithAction:action] takesParameter];
}

- (NSDictionary *)defaultTriggerDictionary {
    int index = [self indexOfTriggerClass:[BounceTrigger class]];
    Trigger *trigger = _triggers[index];
    return @{ kTriggerRegexKey: @"",
              kTriggerActionKey: [trigger action] };
}

- (IBAction)addTrigger:(id)sender {
    [self setTriggerDictionary:[self defaultTriggerDictionary] forRow:-1 reloadData:YES];
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_tableView.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeTrigger:(id)sender {
    if (_tableView.selectedRow < 0) {
        ELog(@"This shouldn't happen: you pressed the button to remove a trigger but no row is selected");
        return;
    }
    [self setTriggerDictionary:nil forRow:[_tableView selectedRow] reloadData:YES];
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
    _removeTriggerButton.enabled = self.hasSelection;
}

- (void)setGuid:(NSString *)guid {
    [_guid autorelease];
    _guid = [guid copy];
    [_tableView reloadData];
}

- (NSTextField *)labelWithString:(NSString *)string origin:(NSPoint)origin {
    NSTextField *textField = [[[NSTextField alloc] initWithFrame:NSMakeRect(origin.x,
                                                                            origin.y,
                                                                            0,
                                                                            0)] autorelease];
    [textField setBezeled:NO];
    [textField setDrawsBackground:NO];
    [textField setEditable:NO];
    [textField setSelectable:NO];
    textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    textField.textColor = [NSColor blackColor];
    textField.stringValue = string;
    [textField sizeToFit];

    return textField;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [[self triggerDictionariesForCurrentProfile] count];
}

#pragma mark Drag/Drop

- (BOOL)tableView:(NSTableView *)tableView
    writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard*)pasteboard {
    NSMutableArray *indexes = [NSMutableArray array];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [indexes addObject:@(idx)];
    }];

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:indexes];
    [pasteboard declareTypes:@[ kiTermTriggerControllerPasteboardType ] owner:self];
    [pasteboard setData:data forType:kiTermTriggerControllerPasteboardType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != aTableView) {
        return NSDragOperationNone;
    }

    // Add code here to validate the drop
    switch (operation) {
        case NSTableViewDropOn:
            return NSDragOperationNone;

        case NSTableViewDropAbove:
            return NSDragOperationMove;

        default:
            return NSDragOperationNone;
    }
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    NSData *rowData = [pasteboard dataForType:kiTermTriggerControllerPasteboardType];
    NSArray *indexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];

    // This code assumes you can only select one trigger at a time.
    int sourceRow = [indexes[0] intValue];
    [self moveTriggerOnRow:sourceRow toRow:row];

    return YES;
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
                      row:(NSInteger)rowIndex {
    if (aTableColumn == _regexColumn || aTableColumn == _partialLineColumn) {
        return YES;
    }
    if (aTableColumn == _parametersColumn) {
        NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][rowIndex];
        NSString *action = triggerDictionary[kTriggerActionKey];
        return [self actionTakesParameter:action];
    }
    return NO;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][row];
    if (tableColumn == _actionColumn) {
        NSPopUpButton *popUpButton = [[[NSPopUpButton alloc] init] autorelease];
        [popUpButton setTitle:[[_triggers[0] class] title]];
        popUpButton.bordered = NO;
        for (int i = 0; i < [self numberOfTriggers]; i++) {
            [popUpButton addItemWithTitle:[[_triggers[i] class] title]];
        }
        NSString *action = triggerDictionary[kTriggerActionKey];
        [popUpButton selectItemAtIndex:[self indexOfAction:action]];
        popUpButton.target = self;
        popUpButton.action = @selector(actionDidChange:);

        return popUpButton;
    } else if (tableColumn == _regexColumn) {
        NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][row];
        NSTextField *textField =
            [[[NSTextField alloc] initWithFrame:NSMakeRect(0,
                                                           0,
                                                           tableColumn.width,
                                                           self.tableView.rowHeight)] autorelease];
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        textField.stringValue = triggerDictionary[kTriggerRegexKey] ?: @"";
        textField.editable = YES;
        textField.selectable = YES;
        textField.bordered = NO;
        textField.drawsBackground = NO;
        textField.delegate = self;
        textField.identifier = kRegexColumnIdentifier;

        return textField;
    } else if (tableColumn == _partialLineColumn) {
        NSButton *checkbox = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
        [checkbox sizeToFit];
        [checkbox setButtonType:NSSwitchButton];
        checkbox.title = @"";
        checkbox.state = [triggerDictionary[kTriggerPartialLineKey] boolValue] ? NSOnState : NSOffState;
        checkbox.target = self;
        checkbox.action = @selector(instantDidChange:);
        return checkbox;
    } else if (tableColumn == _parametersColumn) {
        NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
        Trigger *trigger = [self triggerWithAction:triggerDicts[row][kTriggerActionKey]];
        trigger.param = triggerDicts[row][kTriggerParameterKey];
        if ([trigger takesParameter]) {
            if ([trigger paramIsTwoColorWells]) {
                NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0,
                                                                              0,
                                                                              tableColumn.width,
                                                                              _tableView.rowHeight)] autorelease];
                CGFloat x = 4;
                NSTextField *label = [self labelWithString:@"Text:" origin:NSMakePoint(x, 0)];
                [container addSubview:label];
                x += label.frame.size.width;
                const CGFloat kWellWidth = 30;
                iTermColorWell *well =
                    [[[iTermColorWell alloc] initWithFrame:NSMakeRect(x,
                                                                      0,
                                                                      kWellWidth,
                                                                      _tableView.rowHeight)] autorelease];
                well.noColorAllowed = YES;
                well.continuous = NO;
                well.tag = row;
                x += kWellWidth;
                well.color = trigger.textColor;
                [container addSubview:well];
                well.target = self;
                well.action = @selector(colorWellDidChange:);
                well.identifier = kTextColorWellIdentifier;
                well.willOpenPopover = ^() {
                    self.activeWell = well;
                };
                well.willClosePopover = ^() {
                    if (self.activeWell == well) {
                        self.activeWell = nil;
                    }
                };
                x += 10;
                label = [self labelWithString:@"Background:" origin:NSMakePoint(x, 0)];
                [container addSubview:label];
                x += label.frame.size.width;
                well = [[[iTermColorWell alloc] initWithFrame:NSMakeRect(x,
                                                                         0,
                                                                         kWellWidth,
                                                                         _tableView.rowHeight)] autorelease];
                well.noColorAllowed = YES;
                well.continuous = NO;
                well.color = trigger.backgroundColor;
                well.tag = row;
                [container addSubview:well];
                well.target = self;
                well.action = @selector(colorWellDidChange:);
                well.identifier = kBackgroundColorWellIdentifier;
                well.willOpenPopover = ^() {
                    self.activeWell = well;
                };
                well.willClosePopover = ^() {
                    if (self.activeWell == well) {
                        self.activeWell = nil;
                    }
                };

                return container;
            } else if ([trigger paramIsPopupButton]) {
                NSPopUpButton *popUpButton = [[[NSPopUpButton alloc] init] autorelease];
                [popUpButton setTitle:@""];
                popUpButton.bordered = NO;

                NSMenu *theMenu = popUpButton.menu;
                BOOL isFirst = YES;
                for (NSDictionary *items in [trigger groupedMenuItemsForPopupButton]) {
                    if (!isFirst) {
                        [theMenu addItem:[NSMenuItem separatorItem]];
                    }
                    isFirst = NO;
                    for (id object in [trigger objectsSortedByValueInDict:items]) {
                        NSString *theTitle = [items objectForKey:object];
                        if (theTitle) {
                            NSMenuItem *anItem = [[[NSMenuItem alloc] initWithTitle:theTitle
                                                                             action:nil
                                                                      keyEquivalent:@""] autorelease];
                            [theMenu addItem:anItem];
                        }
                    }
                }

                id param = triggerDictionary[kTriggerParameterKey];
                if (!param) {
                    // Force popup buttons to have the first item selected by default
                    [popUpButton selectItemAtIndex:trigger.defaultIndex];
                } else {
                    [popUpButton selectItemAtIndex:[trigger indexForObject:param]];
                }
                popUpButton.target = self;
                popUpButton.action = @selector(parameterPopUpButtonDidChange:);

                return popUpButton;
            } else {
                // If not a popup button, then text by default.
                NSTextField *textField =
                    [[[NSTextField alloc] initWithFrame:NSMakeRect(0,
                                                                   0,
                                                                   tableColumn.width,
                                                                   self.tableView.rowHeight)] autorelease];
                textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
                textField.stringValue = triggerDictionary[kTriggerParameterKey] ?: @"";
                textField.editable = YES;
                textField.selectable = YES;
                textField.bordered = NO;
                textField.drawsBackground = NO;
                textField.delegate = self;
                if ([textField respondsToSelector:@selector(setPlaceholderString:)]) {
                    textField.placeholderString = [trigger paramPlaceholder];
                }
                textField.identifier = kParameterColumnIdentifier;

                return textField;
            }
        } else {
            return [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
        }
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
    _removeTriggerButton.enabled = self.hasSelection;
}

#pragma mark NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    [_tableView reloadData];
    if ([[[NSColorPanel sharedColorPanel] accessoryView] isKindOfClass:[iTermNoColorAccessoryButton class]]) {
        [[NSColorPanel sharedColorPanel] setAccessoryView:nil];
        [[NSColorPanel sharedColorPanel] close];
    }
}

#pragma mark - Actions

- (void)doubleClick:(id)sender {
    NSPoint screenLocation = [NSEvent mouseLocation];
    NSPoint windowLocation = [self.window convertRectFromScreen:NSMakeRect(screenLocation.x,
                                                                           screenLocation.y,
                                                                           0,
                                                                           0)].origin;
    NSPoint tableLocation = [_tableView convertPoint:windowLocation fromView:nil];
    NSInteger row = [_tableView rowAtPoint:tableLocation];
    NSInteger column = [_tableView columnAtPoint:tableLocation];
    if (row >= 0 && column >= 0) {
        NSView *view = [_tableView viewAtColumn:column row:row makeIfNecessary:NO];
        if (view && [view isKindOfClass:[NSTextField class]] && [(NSTextField *)view isEditable]) {
            [[view window] makeFirstResponder:view];
        }
    }
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.iterm2.com/triggers.html"]];
}

- (void)colorWellDidChange:(CPKColorWell *)colorWell {
    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    NSInteger row = colorWell.tag;
    if (row < 0 || row >= triggerDicts.count) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[[self triggerDictionariesForCurrentProfile][row] mutableCopy] autorelease];
    HighlightTrigger *trigger =
        (HighlightTrigger *)[HighlightTrigger triggerFromDict:triggerDictionary];
    if ([colorWell.identifier isEqual:kTextColorWellIdentifier]) {
        trigger.textColor = colorWell.color;
    } else {
        trigger.backgroundColor = colorWell.color;
    }
    if (trigger.param) {
        triggerDictionary[kTriggerParameterKey] = trigger.param;
    } else {
        [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    }
    // Don't reload data. If this was called because another color picker was opening, reloading the
    // table will cause the presenting view to disappear. That prevents the new popover from
    // appearing correctly.
    [self setTriggerDictionary:triggerDictionary forRow:row reloadData:NO];
}

- (void)instantDidChange:(NSButton *)checkbox {
    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    NSInteger row = [_tableView rowForView:checkbox];
    if (row < 0 || row >= triggerDicts.count) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[[self triggerDictionariesForCurrentProfile][row] mutableCopy] autorelease];
    triggerDictionary[kTriggerPartialLineKey] =
        checkbox.state == NSOnState ? @(YES) : @(NO);
    [self setTriggerDictionary:triggerDictionary forRow:row reloadData:YES];
}

- (void)actionDidChange:(NSPopUpButton *)sender {
    NSInteger rowIndex = [_tableView rowForView:sender];
    if (rowIndex < 0) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[[self triggerDictionariesForCurrentProfile][rowIndex] mutableCopy] autorelease];
    NSInteger index = [sender indexOfSelectedItem];
    Trigger *theTrigger = _triggers[index];
    triggerDictionary[kTriggerActionKey] = [theTrigger action];
    [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    Trigger *triggerObj = [self triggerWithAction:triggerDictionary[kTriggerActionKey]];
    if ([triggerObj paramIsPopupButton]) {
        triggerDictionary[kTriggerParameterKey] = [triggerObj defaultPopupParameterObject];
    }
    [self setTriggerDictionary:triggerDictionary forRow:rowIndex reloadData:YES];
}

- (void)parameterPopUpButtonDidChange:(NSPopUpButton *)sender {
    NSInteger rowIndex = [_tableView rowForView:sender];
    if (rowIndex < 0) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[[self triggerDictionariesForCurrentProfile][rowIndex] mutableCopy] autorelease];
    Trigger *triggerObj = [self triggerWithAction:triggerDictionary[kTriggerActionKey]];
    id parameter = [triggerObj objectAtIndex:[sender indexOfSelectedItem]];
    if (parameter) {
        triggerDictionary[kTriggerParameterKey] = parameter;
    } else {
        [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    }
    [self setTriggerDictionary:triggerDictionary forRow:rowIndex reloadData:YES];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    NSTextField *textField = [obj object];
    NSInteger rowIndex = [_tableView rowForView:textField];
    if (rowIndex < 0) {
        return;
    }
    NSMutableDictionary *triggerDictionary =
        [[[self triggerDictionariesForCurrentProfile][rowIndex] mutableCopy] autorelease];
    if ([textField.identifier isEqual:kRegexColumnIdentifier]) {
        triggerDictionary[kTriggerRegexKey] = [textField stringValue];
        [self setTriggerDictionary:triggerDictionary forRow:rowIndex reloadData:YES];
    } else if ([textField.identifier isEqual:kParameterColumnIdentifier]) {
        triggerDictionary[kTriggerParameterKey] = [textField stringValue];
        [self setTriggerDictionary:triggerDictionary forRow:rowIndex reloadData:YES];
    }
}

@end

