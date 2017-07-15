//
//  ArrangementsDataSource.m
//  iTerm
//
//  Created by George Nachman on 8/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "WindowArrangements.h"
#import "iTermApplicationDelegate.h"
#import "PreferencePanel.h"

static NSString* WINDOW_ARRANGEMENTS = @"Window Arrangements";
static NSString* DEFAULT_ARRANGEMENT_KEY = @"Default Arrangement Name";

@implementation WindowArrangements

+ (WindowArrangements *)sharedInstance
{
    return [[PreferencePanel sharedInstance] arrangements];
}

- (void)updateActionsEnabled
{
    [deleteButton_ setEnabled:([WindowArrangements count] > 0) && ([tableView_ selectedRow] >= 0)];
    [defaultButton_ setEnabled:([WindowArrangements count] > 0) && ([tableView_ selectedRow] >= 0)];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)awakeFromNib
{
    [self updateActionsEnabled];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateTableView:)
                                                 name:kSavedArrangementDidChangeNotification
                                               object:nil];
}

+ (BOOL)hasWindowArrangement:(NSString *)name
{
    NSDictionary *arrangements = [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
    return [arrangements objectForKey:name] != nil;
}

+ (int)count
{
    NSDictionary *arrangements = [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
    return [arrangements count];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    int n = [WindowArrangements count];
    return n;
}

+ (NSDictionary *)arrangements
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:WINDOW_ARRANGEMENTS];
}

+ (void)postChangeNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kSavedArrangementDidChangeNotification
                                                        object:nil
                                                      userInfo:nil];
}

+ (void)setArrangement:(NSArray *)arrangement withName:(NSString *)name
{
    NSMutableDictionary *arrangements = [NSMutableDictionary dictionaryWithDictionary:[WindowArrangements arrangements]];
    [arrangements setObject:arrangement forKey:name];
    [[NSUserDefaults standardUserDefaults] setObject:arrangements forKey:WINDOW_ARRANGEMENTS];
    
    if ([WindowArrangements count] == 1) {
        [WindowArrangements makeDefaultArrangement:name];
    }
    
    [WindowArrangements postChangeNotification];
}

- (NSString *)nameAtIndex:(int)rowIndex
{
    NSArray *keys = [WindowArrangements allNames];
    return [keys objectAtIndex:rowIndex];
}

- (void)updatePreviewView
{
    int rowIndex = [tableView_ selectedRow];
    if (rowIndex >= 0) {
        [previewView_ setArrangement:[WindowArrangements arrangementWithName:[self nameAtIndex:rowIndex]]];
    } else {
        [previewView_ setArrangement:nil];
    }
    
    [previewView_ setNeedsDisplay:YES];
}

- (void)updateTableView:(id)sender
{
    [tableView_ reloadData];
    [self updateActionsEnabled];
    [self updatePreviewView];
}

+ (void)makeDefaultArrangement:(NSString *)name
{
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:DEFAULT_ARRANGEMENT_KEY];
    [WindowArrangements postChangeNotification];
}

+ (NSString *)defaultArrangementName
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:DEFAULT_ARRANGEMENT_KEY];
}

- (NSArray *)defaultArrangement
{
    return [[WindowArrangements arrangements] objectForKey:[WindowArrangements defaultArrangementName]];
}

+ (NSArray *)arrangementWithName:(NSString *)name
{
    if (!name) {
        name = [WindowArrangements defaultArrangementName];
    }
    return [[WindowArrangements arrangements] objectForKey:name];
}

+ (NSArray *)allNames
{
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
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = prompt;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
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
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
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

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSString *key = [self nameAtIndex:rowIndex];
    if (aTableColumn == defaultColumn_) {
        if ([key isEqualToString:[WindowArrangements defaultArrangementName]]) {
            return @"✓";
        } else {
            return @"";
        }
    } else {
        return key;
    }
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

- (void)setDefaultIfNeededAtRow:(int)rowid
{
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

- (IBAction)deleteSelectedArrangement:(id)sender
{
    int rowid = [tableView_ selectedRow];
    if (rowid < 0) {
        return;
    }

    NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[WindowArrangements arrangements]];
    [temp removeObjectForKey:[self nameAtIndex:rowid]];
    [[NSUserDefaults standardUserDefaults] setObject:temp forKey:WINDOW_ARRANGEMENTS];

    [self setDefaultIfNeededAtRow:rowid];
    
    [tableView_ reloadData];
    [WindowArrangements postChangeNotification];
}

#pragma mark Delegate methods

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    [self updatePreviewView];
    [self updateActionsEnabled];
}

@end
