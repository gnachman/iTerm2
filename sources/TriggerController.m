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
#import "FutureMethods.h"
#import "GrowlTrigger.h"
#import "HighlightTrigger.h"
#import "ITAddressBookMgr.h"
#import "iTermNoColorAccessoryButton.h"
#import "iTermTwoColorWellsCell.h"
#import "iTermTriggerTableView.h"
#import "MarkTrigger.h"
#import "NSColor+iTerm.h"
#import "PasswordTrigger.h"
#import "ProfileModel.h"
#import "ScriptTrigger.h"
#import "SendTextTrigger.h"
#import "StopTrigger.h"
#import "Trigger.h"

static NSString *const kiTermTriggerControllerPasteboardType = @"kiTermTriggerControllerPasteboardType";

@implementation TriggerController {
    NSArray *_triggers;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_regexColumn;
    IBOutlet NSTableColumn *_partialLineColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSTableColumn *_parametersColumn;
    int _currentWellNumber;
}

- (id)init {
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
                             [StopTrigger class] ];

    return [allClasses sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                  return [[obj1 title] compare:[obj2 title]];
              }];
}

- (void)awakeFromNib {
    [_tableView registerForDraggedTypes:@[ kiTermTriggerControllerPasteboardType ]];
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

- (void)setTriggerDictionary:(NSDictionary *)triggerDictionary forRow:(NSInteger)rowIndex {
    // Stop editing. A reload while editing crashes.
    [_tableView reloadData];
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
    [_tableView reloadData];
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
    [self setTriggerDictionary:[self defaultTriggerDictionary] forRow:-1];
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_tableView.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeTrigger:(id)sender {
    assert(_tableView.selectedRow >= 0);
    [self setTriggerDictionary:nil forRow:[_tableView selectedRow]];
}

- (void)setGuid:(NSString *)guid {
    [_guid autorelease];
    _guid = [guid copy];
    [_tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return [[self triggerDictionariesForCurrentProfile] count];
}

- (id)tableView:(NSTableView *)aTableView
          objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    if (rowIndex >= [self numberOfRowsInTableView:aTableView]) {
        // Sanity check.
        return nil;
    }
    NSDictionary *triggerDictionary = [self triggerDictionariesForCurrentProfile][rowIndex];
    if (aTableColumn == _regexColumn) {
        return triggerDictionary[kTriggerRegexKey];
    } else if (aTableColumn == _partialLineColumn) {
        return triggerDictionary[kTriggerPartialLineKey];
    } else if (aTableColumn == _parametersColumn) {
        NSString *action = triggerDictionary[kTriggerActionKey];
        Trigger *triggerObj = [self triggerWithAction:action];
        if ([triggerObj takesParameter]) {
            id param = triggerDictionary[kTriggerParameterKey];
            if ([triggerObj paramIsPopupButton]) {
                if (!param) {
                    // Force popup buttons to have the first item selected by default
                    return @([triggerObj defaultIndex]);
                } else {
                    return @([triggerObj indexForObject:param]);
                }
            } else {
                return param;
            }
        } else {
            return @"";
        }
    } else {
        NSString *action = triggerDictionary[kTriggerActionKey];
        int theIndex = [self indexOfAction:action];
        return @(theIndex);
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    NSMutableDictionary *triggerDictionary = [[[self triggerDictionariesForCurrentProfile][rowIndex] mutableCopy] autorelease];

    if (aTableColumn == _regexColumn) {
        triggerDictionary[kTriggerRegexKey] = anObject;
    } else if (aTableColumn == _partialLineColumn) {
        triggerDictionary[kTriggerPartialLineKey] = anObject;
    } else if (aTableColumn == _parametersColumn) {
        Trigger *triggerObj = [self triggerWithAction:triggerDictionary[kTriggerActionKey]];
        if ([triggerObj paramIsPopupButton]) {
            id parameter = [triggerObj objectAtIndex:[anObject intValue]];
            if (parameter) {
                triggerDictionary[kTriggerParameterKey] = parameter;
            } else {
                [triggerDictionary removeObjectForKey:kTriggerParameterKey];
            }
        } else {
            triggerDictionary[kTriggerParameterKey] = anObject;
        }
    } else {
        // Action column
        int index = [anObject intValue];
        Trigger *theTrigger = _triggers[index];
        triggerDictionary[kTriggerActionKey] = [theTrigger action];
        [triggerDictionary removeObjectForKey:kTriggerParameterKey];
        Trigger *triggerObj = [self triggerWithAction:triggerDictionary[kTriggerActionKey]];
        if ([triggerObj paramIsPopupButton]) {
            triggerDictionary[kTriggerParameterKey] = [triggerObj defaultPopupParameterObject];
        }
    }
    [self setTriggerDictionary:triggerDictionary forRow:rowIndex];
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

- (NSCell *)tableView:(NSTableView *)tableView
      dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableColumn == _actionColumn) {
        NSPopUpButtonCell *cell =
            [[[NSPopUpButtonCell alloc] initTextCell:[[_triggers[0] class] title] pullsDown:NO] autorelease];
        for (int i = 0; i < [self numberOfTriggers]; i++) {
            [cell addItemWithTitle:[[_triggers[i] class] title]];
        }

        [cell setBordered:NO];

        return cell;
    } else if (tableColumn == _regexColumn) {
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"regex"] autorelease];
        [cell setEditable:YES];
        return cell;
    } else if (tableColumn == _partialLineColumn) {
        NSButtonCell *cell = [[[NSButtonCell alloc] init] autorelease];
        [cell setTitle:nil];
        [cell setButtonType:NSSwitchButton];
        return cell;
    } else if (tableColumn == _parametersColumn) {
        NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
        Trigger *trigger = [self triggerWithAction:triggerDicts[row][kTriggerActionKey]];
        trigger.param = triggerDicts[row][kTriggerParameterKey];
        if ([trigger takesParameter]) {
            if ([trigger paramIsTwoColorWells]) {
                iTermTwoColorWellsCell *cell = [[[iTermTwoColorWellsCell alloc] init] autorelease];
                cell.textColor = [trigger textColor];
                cell.backgroundColor = [trigger backgroundColor];
                [cell setBordered:NO];
                return cell;
            } else if ([trigger paramIsPopupButton]) {
                NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell:@""
                                                                         pullsDown:NO] autorelease];
                NSMenu *theMenu = [cell menu];
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
                [cell setBordered:NO];
                return cell;
            } else {
                // If not a popup button, then text by default.
                NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
                [cell setPlaceholderString:[trigger paramPlaceholder]];
                [cell setEditable:YES];
                return cell;
            }
        } else {
            NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
            [cell setPlaceholderString:@""];
            [cell setEditable:NO];
            return cell;
        }
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _currentWellNumber = -1;
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
}

- (void)twoColorWellsCellDidOpenPickerForWellNumber:(int)wellNumber {
    _currentWellNumber = wellNumber;
    NSColor *currentColor = self.currentColor;
    if (currentColor) {
        [[NSColorPanel sharedColorPanel] setColor:self.currentColor];
    }
    [_tableView setNeedsDisplay];
}

- (NSNumber *)currentWellForCell {
    return @(_currentWellNumber);
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.iterm2.com/triggers.html"]];
}

#pragma mark NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    [_tableView reloadData];
    if ([[[NSColorPanel sharedColorPanel] accessoryView] isKindOfClass:[iTermNoColorAccessoryButton class]]) {
        [[NSColorPanel sharedColorPanel] setAccessoryView:nil];
        [[NSColorPanel sharedColorPanel] close];
    }
}

#pragma mark - NSResponder

- (void)changeColor:(id)sender {
    [self setColor:[sender color]];
}

- (NSColor *)currentColor {
    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= triggerDicts.count) {
        return nil;
    }
    NSMutableDictionary *triggerDictionary = [[[self triggerDictionariesForCurrentProfile][row] mutableCopy] autorelease];
    HighlightTrigger *trigger = (HighlightTrigger *)[HighlightTrigger triggerFromDict:triggerDictionary];
    if (_currentWellNumber == 0) {
        return trigger.textColor;
    } else if (_currentWellNumber == 1) {
        return trigger.backgroundColor;
    }
    return nil;
}

- (void)setColor:(NSColor *)color {
    NSArray *triggerDicts = [self triggerDictionariesForCurrentProfile];
    NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= triggerDicts.count) {
        return;
    }
    NSMutableDictionary *triggerDictionary = [[[self triggerDictionariesForCurrentProfile][row] mutableCopy] autorelease];
    HighlightTrigger *trigger = (HighlightTrigger *)[HighlightTrigger triggerFromDict:triggerDictionary];
    if (_currentWellNumber == 0) {
        trigger.textColor = color;
    } else if (_currentWellNumber == 1) {
        trigger.backgroundColor = color;
    }
    if (trigger.param) {
        triggerDictionary[kTriggerParameterKey] = trigger.param;
    } else {
        [triggerDictionary removeObjectForKey:kTriggerParameterKey];
    }
    [self setTriggerDictionary:triggerDictionary forRow:row];

    [_tableView reloadData];
}

- (void)noColorChosen:(id)sender {
    [self setColor:nil];
}

@end

