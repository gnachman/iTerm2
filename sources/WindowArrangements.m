//
//  ArrangementsDataSource.m
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "WindowArrangements.h"
#import "iTermApplicationDelegate.h"
#import "NSAlert+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

static NSString* WINDOW_ARRANGEMENTS = @"Window Arrangements";
static NSString* DEFAULT_ARRANGEMENT_KEY = @"Default Arrangement Name";
static NSString *const kSavedArrangementWillChangeNotification = @"kSavedArrangementWillChangeNotification";

@interface WindowArrangements()<NSTextFieldDelegate>
@end

@implementation WindowArrangements {
    IBOutlet NSTableColumn *defaultColumn_;
    IBOutlet NSTableColumn *titleColumn_;
    IBOutlet NSTableView *tableView_;
    IBOutlet ArrangementPreviewView *previewView_;
    IBOutlet NSButton *deleteButton_;
    IBOutlet NSButton *defaultButton_;
}

+ (WindowArrangements *)sharedInstance {
    return [[PreferencePanel sharedInstance] arrangements];
}

- (void)updateActionsEnabled {
    [deleteButton_ setEnabled:([WindowArrangements count] > 0) && ([tableView_ numberOfSelectedRows] > 0)];
    [defaultButton_ setEnabled:([WindowArrangements count] > 0) && ([tableView_ numberOfSelectedRows] == 1)];
}

- (void)awakeFromNib {
    [self updateActionsEnabled];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateTableView:)
                                                 name:kSavedArrangementDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pushUndo)
                                                 name:kSavedArrangementWillChangeNotification
                                               object:nil];
}

+ (BOOL)hasWindowArrangement:(NSString *)name {
    NSDictionary *arrangements = [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
    return [arrangements objectForKey:name] != nil;
}

+ (int)count {
    NSDictionary *arrangements = [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
    return [arrangements count];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    int n = [WindowArrangements count];
    return n;
}

+ (NSDictionary *)arrangements {
    return [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
}

+ (void)postChangeNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kSavedArrangementDidChangeNotification
                                                        object:nil
                                                      userInfo:nil];
}

+ (void)setArrangement:(NSArray *)arrangement withName:(NSString *)name {
    [[NSNotificationCenter defaultCenter] postNotificationName:kSavedArrangementWillChangeNotification
                                                        object:nil
                                                      userInfo:nil];

    NSMutableDictionary *arrangements = [NSMutableDictionary dictionaryWithDictionary:[WindowArrangements arrangements]];
    [arrangements setObject:arrangement forKey:name];
    @try {
        [[NSUserDefaults standardUserDefaults] setObject:arrangements forKey:WINDOW_ARRANGEMENTS];
    }
    @catch (NSException *e) {
        NSString *oops = [arrangements it_invalidPathInPlist];
        ITCriticalError(NO,
                        @"Exception %@ while saving arrangement. Invalid path is %@\n%@", e, oops, [arrangement debugDescription]);
        return;
    }

    if ([WindowArrangements count] == 1) {
        [WindowArrangements makeDefaultArrangement:name];
    }

    [WindowArrangements postChangeNotification];
}

- (NSString *)nameAtIndex:(NSUInteger)rowIndex {
    NSArray *keys = [WindowArrangements allNames];
    return keys[rowIndex];
}

- (void)updatePreviewView {
    NSIndexSet *selection = tableView_.selectedRowIndexes;
    if (selection.count == 1) {
        const NSUInteger rowIndex = selection.firstIndex;
        [previewView_ setArrangement:[WindowArrangements arrangementWithName:[self nameAtIndex:rowIndex]]];
        [previewView_ setNeedsDisplay:YES];
        return;
    }
    [previewView_ setArrangement:nil];
    [previewView_ setNeedsDisplay:YES];
}

- (void)updateTableView:(id)sender {
    [tableView_ reloadData];
    [self updateActionsEnabled];
    [self updatePreviewView];
}

+ (void)makeDefaultArrangement:(NSString *)name {
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:DEFAULT_ARRANGEMENT_KEY];
    [WindowArrangements postChangeNotification];
}

+ (NSString *)defaultArrangementName {
    return [[NSUserDefaults standardUserDefaults] objectForKey:DEFAULT_ARRANGEMENT_KEY];
}

- (NSArray *)defaultArrangement {
    return [[WindowArrangements arrangements] objectForKey:[WindowArrangements defaultArrangementName]];
}

+ (NSArray *)arrangementWithName:(NSString *)name {
    if (!name) {
        name = [WindowArrangements defaultArrangementName];
    }
    return [[WindowArrangements arrangements] objectForKey:name];
}

+ (NSArray *)allNames {
    NSArray *keys = [[WindowArrangements arrangements] allKeys];
    return [keys sortedArrayUsingSelector:@selector(compare:)];
}

+ (void)refreshRestoreArrangementsMenu:(NSMenuItem *)menuItem
                          withSelector:(SEL)selector
                       defaultShortcut:(NSString *)defaultShortcut
                            identifier:(NSString *)identifier {
    while ([[menuItem submenu] numberOfItems]) {
        [[menuItem submenu] removeItemAtIndex:0];
    }

    NSString *defaultName = [self defaultArrangementName];

    for (NSString *theName in [self allNames]) {
        NSString *theShortcut;
        if ([theName isEqualToString:defaultName]) {
            theShortcut = defaultShortcut;
        } else {
            theShortcut = @"";
        }
        NSMenuItem *individualItem = [[menuItem submenu] addItemWithTitle:theName
                                                                   action:selector
                                                            keyEquivalent:theShortcut];
        individualItem.identifier = [NSString stringWithFormat:@"%@:%@", theName, identifier];
    }
}

+ (NSString *)showAlertWithText:(NSString *)prompt defaultInput:(NSString *)defaultValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = prompt;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setStringValue:defaultValue];
    [alert setAccessoryView:input];
    [alert layout];
    [[alert window] makeFirstResponder:input];
    NSInteger button = [alert runModal];
    if (button == NSAlertFirstButtonReturn) {
        [input validateEditing];
        return [[input stringValue] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    } else if (button == NSAlertSecondButtonReturn) {
        return nil;
    } else {
        NSAssert1(NO, @"Invalid input dialog button %d", (int) button);
        return nil;
    }
}

+ (NSString *)nameForNewArrangement {
    NSString *name = [self showAlertWithText:@"Name for saved window arrangement:"
                                defaultInput:[NSString stringWithFormat:@"Arrangement %d", 1 + [WindowArrangements count]]];
    if (!name) {
        return nil;
    }
    if ([WindowArrangements hasWindowArrangement:name]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Replace Existing Saved Window Arrangement?";
        alert.informativeText = @"There is an existing saved window arrangement with this name. Would you like to replace it with the current arrangement?";
        [alert addButtonWithTitle:@"Yes"];
        [alert addButtonWithTitle:@"No"];
        if ([alert runModal] == NSAlertSecondButtonReturn) {
            return nil;
        }
    }
    return name;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"default"]) {
        static NSString *const identifier = @"WindowArrangementDefaultIdentifier";
        NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
        if (result == nil) {
            result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
            result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        }
        NSString *key = [self nameAtIndex:row];
        if ([key isEqualToString:[WindowArrangements defaultArrangementName]]) {
            result.stringValue = @"★";
        } else {
            result.stringValue = @"";
        }
        result.editable = NO;
        return result;
    }

    static NSString *const identifier = @"WindowArrangementTitleIdentifier";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    NSString *value = [self nameAtIndex:row];
    result.stringValue = value;
    result.delegate = self;
    result.editable = YES;
    return result;
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    const NSInteger row = [tableView_ selectedRow];
    if (row < 0) {
        return;
    }
    NSTextField *textField = obj.object;
    NSString *newName = textField.stringValue;
    NSString *oldName = [self nameAtIndex:row];
    if ([oldName isEqual:newName]) {
        return;
    }
    const BOOL wasDefault = [oldName isEqualToString:[WindowArrangements defaultArrangementName]];
    NSMutableDictionary *dict = [[[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS] mutableCopy];
    NSDictionary *value = [dict[oldName] copy];
    if (dict[newName]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Replace Arrangement?";
        alert.informativeText = [NSString stringWithFormat:@"An arrangement named “%@” already exists. Would you like to replace it?", newName];
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runSheetModalForWindow:self.view.window] == NSAlertSecondButtonReturn) {
            textField.stringValue = oldName;
            return;
        }
        [dict removeObjectForKey:oldName];
    }
    [self pushUndo];
    [dict removeObjectForKey:oldName];
    dict[newName] = value;
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:WINDOW_ARRANGEMENTS];
    if (wasDefault) {
        [[NSUserDefaults standardUserDefaults] setObject:newName forKey:DEFAULT_ARRANGEMENT_KEY];
    }
    [tableView_ reloadData];
    [WindowArrangements postChangeNotification];

    // Select row again
    NSUInteger index = [self indexOfRowNamed:newName];
    if (index != NSNotFound) {
        [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                byExtendingSelection:NO];
    }
}

- (NSUInteger)indexOfRowNamed:(NSString *)name {
    return [WindowArrangements.allNames indexOfObject:name];
}


- (IBAction)setDefault:(id)sender
{
    int rowid = [tableView_ selectedRow];
    if (rowid < 0) {
        return;
    }
    [WindowArrangements makeDefaultArrangement:[self nameAtIndex:rowid]];

    [tableView_ reloadData];
}

- (void)setDefaultIfNeededAtRow:(int)rowid {
    if ([WindowArrangements count] > 0) {
        if ([WindowArrangements arrangementWithName:[WindowArrangements defaultArrangementName]] == nil) {
            int newDefault = rowid;
            if (newDefault >= [WindowArrangements count]) {
                newDefault = [WindowArrangements count] - 1;
            }
            [WindowArrangements makeDefaultArrangement:[[WindowArrangements allNames] objectAtIndex:newDefault]];
        }
    }
}

- (IBAction)deleteSelectedArrangement:(id)sender {
    NSIndexSet *rows = tableView_.selectedRowIndexes;
    if (rows.count == 0) {
        return;
    }
    [self pushUndo];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        [names addObject:[self nameAtIndex:idx]];
    }];
    NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[WindowArrangements arrangements]];
    [names enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [temp removeObjectForKey:obj];
    }];
    [[NSUserDefaults standardUserDefaults] setObject:temp forKey:WINDOW_ARRANGEMENTS];
    [self setDefaultIfNeededAtRow:rows.firstIndex];

    [tableView_ reloadData];
    [WindowArrangements postChangeNotification];
}

- (void)keyDown:(NSEvent *)event {
    const unichar key = [[event charactersIgnoringModifiers] characterAtIndex:0];
    if (key == NSDeleteCharacter) {
        [self deleteSelectedArrangement:nil];
    } else {
        [super keyDown:event];
    }
}

- (void)setArrangements:(NSDictionary *)saved {
    [self pushUndo];

    NSString *defaultArrangementName = [NSString castFrom:saved[@"default"]];
    NSDictionary *arrangements = [NSDictionary castFrom:saved[@"arrangements"]];
    [[NSUserDefaults standardUserDefaults] setObject:arrangements forKey:WINDOW_ARRANGEMENTS];
    [[NSUserDefaults standardUserDefaults] setObject:defaultArrangementName forKey:DEFAULT_ARRANGEMENT_KEY];
    [WindowArrangements postChangeNotification];
}

- (void)pushUndo {
    [[self undoManager] registerUndoWithTarget:self
                                      selector:@selector(setArrangements:)
                                        object:@{ @"default": [WindowArrangements defaultArrangementName] ?: [NSNull null],
                                                  @"arrangements": [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS] ?: @{} }];
}

#pragma mark Delegate methods

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updatePreviewView];
    [self updateActionsEnabled];
}

@end
