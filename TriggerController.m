//
//  TriggerController.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "TriggerController.h"
#import "ProfileModel.h"
#import "ITAddressBookMgr.h"
#import "GrowlTrigger.h"
#import "BounceTrigger.h"
#import "BellTrigger.h"
#import "ScriptTrigger.h"
#import "AlertTrigger.h"
#import "HighlightTrigger.h"
#import "Trigger.h"
#import "CoprocessTrigger.h"
#import "SendTextTrigger.h"
#import "FutureMethods.h"

static NSMutableArray *gTriggerClasses;

@implementation TriggerController

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

+ (void)initialize
{
    // The analyzer flags this, but it's just a singleton.
    gTriggerClasses = [[NSMutableArray alloc] init];
    [gTriggerClasses addObject:[[[AlertTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[BellTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[BounceTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[GrowlTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[SendTextTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[ScriptTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[CoprocessTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[MuteCoprocessTrigger alloc] init] autorelease]];
    [gTriggerClasses addObject:[[[HighlightTrigger alloc] init] autorelease]];

    [gTriggerClasses sortUsingSelector:@selector(compareTitle:)];
}

- (void)dealloc
{
    [guid_ release];
    [super dealloc];
}

+ (int)numberOfTriggers
{
    return gTriggerClasses.count;
}

+ (int)indexOfAction:(NSString *)action
{
    int n = [TriggerController numberOfTriggers];
    for (int i = 0; i < n; i++) {
        NSString *className = NSStringFromClass([[gTriggerClasses objectAtIndex:i] class]);
        if ([className isEqualToString:action]) {
            return i;
        }
    }
    return -1;
}

// Index in gTriggerClasses of an object of class "c"
+ (NSInteger)indexOfTriggerClass:(Class)c
{
    for (int i = 0; i < gTriggerClasses.count; i++) {
        if ([[gTriggerClasses objectAtIndex:i] isKindOfClass:c]) {
            return i;
        }
    }
    return -1;
}

+ (Trigger *)triggerAtIndex:(int)i
{
    return [gTriggerClasses objectAtIndex:i];
}

+ (Trigger *)triggerWithAction:(NSString *)action
{
    int i = [TriggerController indexOfAction:action];
    if (i == -1) {
        return nil;
    }
    return [TriggerController triggerAtIndex:i];
}

- (Profile *)bookmark
{
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[ProfileModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (NSArray *)triggers
{
    Profile *bookmark = [self bookmark];
    NSArray *triggers = [bookmark objectForKey:KEY_TRIGGERS];
    return triggers ? triggers : [NSArray array];
}

- (ProfileModel *)modelForBookmark:(Profile *)bookmark
{
    if ([[ProfileModel sharedInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sharedInstance];
    } else if ([[ProfileModel sessionsInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [ProfileModel sessionsInstance];
    } else {
        return nil;
    }
}

- (void)setTrigger:(NSDictionary *)trigger forRow:(NSInteger)rowIndex
{
    // Stop editing. A reload while editing crashes.
    [tableView_ reloadData];
    NSMutableArray *triggers = [[[self triggers] mutableCopy] autorelease];
    if (rowIndex < 0) {
        assert(trigger);
        [triggers addObject:trigger];
    } else {
        if (trigger) {
            [triggers replaceObjectAtIndex:rowIndex withObject:trigger];
        } else {
            [triggers removeObjectAtIndex:rowIndex];
        }
    }
    Profile *bookmark = [self bookmark];
    [[self modelForBookmark:bookmark] setObject:triggers forKey:KEY_TRIGGERS inBookmark:bookmark];
    [tableView_ reloadData];
    [delegate_ triggerChanged:nil];
}

- (BOOL)actionTakesParameter:(NSString *)action
{
    return [[TriggerController triggerWithAction:action] takesParameter];
}

- (NSDictionary *)defaultTrigger
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"", kTriggerRegexKey,
            [[TriggerController triggerAtIndex:[TriggerController indexOfTriggerClass:[BounceTrigger class]]] action], kTriggerActionKey,
            nil];
}

- (IBAction)addTrigger:(id)sender
{
    [self setTrigger:[self defaultTrigger] forRow:-1];
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:tableView_.numberOfRows - 1]
            byExtendingSelection:NO];
}

- (IBAction)removeTrigger:(id)sender
{
    assert(tableView_.selectedRow >= 0);
    [self setTrigger:nil forRow:[tableView_ selectedRow]];
}

- (void)setGuid:(NSString *)guid
{
    [guid_ autorelease];
    guid_ = [guid copy];
    [tableView_ reloadData];
}

#pragma mark NSTableViewDataSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[self triggers] count];
}

- (id)tableView:(NSTableView *)aTableView
          objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    if (rowIndex >= [self numberOfRowsInTableView:aTableView]) {
        // Sanity check.
        return nil;
    }
    NSDictionary *trigger = [[self triggers] objectAtIndex:rowIndex];
    if (aTableColumn == regexColumn_) {
        return [trigger objectForKey:kTriggerRegexKey];
    } else if (aTableColumn == parametersColumn_) {
        NSString *action = [trigger objectForKey:kTriggerActionKey];
        Trigger *triggerObj = [TriggerController triggerWithAction:action];
        if ([triggerObj takesParameter]) {
            id param = [trigger objectForKey:kTriggerParameterKey];
            if ([triggerObj paramIsPopupButton]) {
                if (!param) {
                    // Force popup buttons to have the first item selected by default
                    return @([triggerObj defaultIndex]);
                } else {
                    return @([triggerObj indexOfTag:[param intValue]]);
                }
            } else {
                return param;
            }
        } else {
            return @"";
        }
    } else {
        NSString *action = [trigger objectForKey:kTriggerActionKey];
        return [NSNumber numberWithInt:[TriggerController indexOfAction:action]];
    }
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSMutableDictionary *trigger = [[[[self triggers] objectAtIndex:rowIndex] mutableCopy] autorelease];

    if (aTableColumn == regexColumn_) {
        [trigger setObject:anObject forKey:kTriggerRegexKey];
    } else if (aTableColumn == parametersColumn_) {
        Trigger *triggerObj = [TriggerController triggerWithAction:[trigger objectForKey:kTriggerActionKey]];
        if ([triggerObj paramIsPopupButton]) {
            int theTag = [triggerObj tagAtIndex:[anObject intValue]];
            [trigger setObject:[NSNumber numberWithInt:theTag] forKey:kTriggerParameterKey];
        } else {
            [trigger setObject:anObject forKey:kTriggerParameterKey];
        }
    } else {
        // Action column
        [trigger setObject:[[TriggerController triggerAtIndex:[anObject intValue]] action]
                    forKey:kTriggerActionKey];
        [trigger removeObjectForKey:kTriggerParameterKey];
        Trigger *triggerObj = [TriggerController triggerWithAction:[trigger objectForKey:kTriggerActionKey]];
        if ([triggerObj paramIsPopupButton]) {
            [trigger setObject:[NSNumber numberWithInt:0] forKey:kTriggerParameterKey];
        }
    }
    [self setTrigger:trigger forRow:rowIndex];
}

#pragma mark NSTableViewDelegate
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    if (aTableColumn == regexColumn_) {
        return YES;
    }
    if (aTableColumn == parametersColumn_) {
        NSDictionary *trigger = [[self triggers] objectAtIndex:rowIndex];
        NSString *action = [trigger objectForKey:kTriggerActionKey];
        return [self actionTakesParameter:action];
    }
    return NO;
}

- (NSCell *)tableView:(NSTableView *)tableView
      dataCellForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    if (tableColumn == actionColumn_) {
        NSPopUpButtonCell *cell =
            [[[NSPopUpButtonCell alloc] initTextCell:[[TriggerController triggerAtIndex:0] title] pullsDown:NO] autorelease];
        for (int i = 0; i < [TriggerController numberOfTriggers]; i++) {
            [cell addItemWithTitle:[[TriggerController triggerAtIndex:i] title]];
        }

        [cell setBordered:NO];

        return cell;
    } else if (tableColumn == regexColumn_) {
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"regex"] autorelease];
        [cell setEditable:YES];
        return cell;
    } else if (tableColumn == parametersColumn_) {
        Trigger *trigger = [TriggerController triggerWithAction:[[[self triggers] objectAtIndex:row] objectForKey:kTriggerActionKey]];
        if ([trigger takesParameter]) {
            if ([trigger paramIsPopupButton]) {
                NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease];
                NSMenu *theMenu = [cell menu];
                BOOL isFirst = YES;
                for (NSDictionary *items in [trigger groupedMenuItemsForPopupButton]) {
                    if (!isFirst) {
                        [theMenu addItem:[NSMenuItem separatorItem]];
                    }
                    isFirst = NO;
                    for (NSNumber *n in [trigger tagsSortedByValueInDict:items]) {
                        NSString *theTitle = [items objectForKey:n];
                        if (theTitle) {
                            NSMenuItem *anItem = [[[NSMenuItem alloc] initWithTitle:theTitle action:nil keyEquivalent:@""] autorelease];
                            [anItem setTag:[n intValue]];
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
}

- (IBAction)help:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.iterm2.com/triggers.html"]];
}

#pragma mark NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    [tableView_ reloadData];
}

@end

