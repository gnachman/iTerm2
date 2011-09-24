//
//  TriggerController.m
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import "TriggerController.h"
#import "BookmarkModel.h"
#import "ITAddressBookMgr.h"

static NSString * const kTriggerRegexKey = @"regex";
static NSString * const kTriggerActionKey = @"action";
static NSString * const kTriggerParameterKey = @"parameter";
static NSString * const kGrowlAction = @"growl";
static NSString * const kBounceAction = @"bounce";
static NSString * const kBellAction = @"bell";
static NSString * const kScriptAction = @"script";

static NSString * const kGrowlTitle = @"Growl Message…";
static NSString * const kBounceTitle = @"Bounce Dock Icon";
static NSString * const kBellTitle = @"Ring Bell";
static NSString * const kScriptTitle = @"Run Script…";

@implementation TriggerController

@synthesize guid = guid_;
@synthesize hasSelection = hasSelection_;
@synthesize delegate = delegate_;

- (void)dealloc
{
  [guid_ release];
  [super dealloc];
}

- (NSArray *)triggers
{
  Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:self.guid];
  NSDictionary *triggers = [bookmark objectForKey:KEY_TRIGGERS];
  return triggers ? triggers : [NSArray array];
}

- (void)setTrigger:(NSDictionary *)trigger forRow:(NSInteger)rowIndex
{
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
  Bookmark* bookmark = [[BookmarkModel sharedInstance] bookmarkWithGuid:self.guid];
  [[BookmarkModel sharedInstance] setObject:triggers forKey:KEY_TRIGGERS inBookmark:bookmark];
  [tableView_ reloadData];
  [delegate_ triggerChanged:nil];
}

- (BOOL)actionTakesParameter:(NSString *)action
{
    if ([action isEqualToString:kGrowlAction] ||
        [action isEqualToString:kScriptAction]) {
        return YES;
    } else {
      return NO;
    }
}

- (NSDictionary *)defaultTrigger
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
      @"regex", kTriggerRegexKey,
      kBounceAction, kTriggerActionKey,
      nil];
}

- (IBAction)addTrigger:(id)sender
{
  [self setTrigger:[self defaultTrigger] forRow:-1];
  [tableView_ selectRow:tableView_.numberOfRows - 1 byExtendingSelection:NO];
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
  NSDictionary *trigger = [[self triggers] objectAtIndex:rowIndex];
  if (aTableColumn == regexColumn_) {
    return [trigger objectForKey:kTriggerRegexKey];
  } else if (aTableColumn == parametersColumn_) {
    NSString *action = [trigger objectForKey:kTriggerActionKey];
    if ([action isEqualToString:kGrowlAction] ||
        [action isEqualToString:kScriptAction]) {
      return [trigger objectForKey:kTriggerParameterKey];
    } else {
      return @"";
    }
  } else {
    NSString *action = [trigger objectForKey:kTriggerActionKey];
    if ([action isEqualToString:kGrowlAction]) {
      return [NSNumber numberWithInt:0];
    } else if ([action isEqualToString:kBounceAction]) {
      return [NSNumber numberWithInt:1];
    } else if ([action isEqualToString:kBellAction]) {
      return [NSNumber numberWithInt:2];
    } else if ([action isEqualToString:kScriptAction]) {
      return [NSNumber numberWithInt:3];
    } else {
      return nil;
    }
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
    switch ([anObject intValue]) {
      case 0:
        [trigger setObject:kGrowlAction forKey:kTriggerActionKey];
        break;
      case 1:
        [trigger setObject:kBounceAction forKey:kTriggerActionKey];
        break;
      case 2:
        [trigger setObject:kBellAction forKey:kTriggerActionKey];
        break;
      case 3:
        [trigger setObject:kScriptAction forKey:kTriggerActionKey];
        break;
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
}

@end

@implementation TriggerActionColumn

- (id)dataCellForRow:(NSInteger)row
{
  NSPopUpButtonCell *cell =
      [[[NSPopUpButtonCell alloc] initTextCell:kGrowlTitle pullsDown:NO] autorelease];
  [cell addItemWithTitle:kBounceTitle];
  [cell addItemWithTitle:kBellTitle];
  [cell addItemWithTitle:kScriptTitle];

  [cell setBordered:NO];

  return cell;
}


@end

