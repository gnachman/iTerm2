//
//  TriggerController.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "TriggerController.h"
#import "BookmarkModel.h"
#import "ITAddressBookMgr.h"
#import "GrowlTrigger.h"
#import "BounceTrigger.h"
#import "BellTrigger.h"
#import "ScriptTrigger.h"
#import "AlertTrigger.h"
#import "Trigger.h"
#import "CoprocessTrigger.h"
#import "SendTextTrigger.h"

enum {
    kGrowlAction,
    kBounceAction,
    kBellAction,
    kScriptAction,
    kAlertAction
};

static NSMutableArray *gTriggerClasses;

@implementation TriggerController

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

+ (void)initialize
{
    gTriggerClasses = [[NSMutableArray alloc] init];
    [gTriggerClasses addObject:[[AlertTrigger alloc] init]];
    [gTriggerClasses addObject:[[BellTrigger alloc] init]];
    [gTriggerClasses addObject:[[BounceTrigger alloc] init]];
    [gTriggerClasses addObject:[[GrowlTrigger alloc] init]];
    [gTriggerClasses addObject:[[SendTextTrigger alloc] init]];
    [gTriggerClasses addObject:[[ScriptTrigger alloc] init]];
    [gTriggerClasses addObject:[[CoprocessTrigger alloc] init]];
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

- (Bookmark *)bookmark
{
    Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:self.guid];
    if (!bookmark) {
        bookmark = [[BookmarkModel sessionsInstance] bookmarkWithGuid:self.guid];
    }
    return bookmark;
}

- (NSArray *)triggers
{
    Bookmark *bookmark = [self bookmark];
    NSDictionary *triggers = [bookmark objectForKey:KEY_TRIGGERS];
    return triggers ? triggers : [NSArray array];
}

- (BookmarkModel *)modelForBookmark:(Bookmark *)bookmark
{
    if ([[BookmarkModel sharedInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [BookmarkModel sharedInstance];
    } else if ([[BookmarkModel sessionsInstance] bookmarkWithGuid:[bookmark objectForKey:KEY_GUID]]) {
        return [BookmarkModel sessionsInstance];
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
    Bookmark *bookmark = [self bookmark];
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
            [[TriggerController triggerAtIndex:kBounceAction] action], kTriggerActionKey,
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
        if ([[TriggerController triggerWithAction:action] takesParameter]) {
            return [trigger objectForKey:kTriggerParameterKey];
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
        [trigger setObject:anObject forKey:kTriggerParameterKey];
    } else {
        [trigger setObject:[[TriggerController triggerAtIndex:[anObject intValue]] action]
                    forKey:kTriggerActionKey];
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
            NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
            [cell setPlaceholderString:[trigger paramPlaceholder]];
            [cell setEditable:YES];
            return cell;
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

@end

