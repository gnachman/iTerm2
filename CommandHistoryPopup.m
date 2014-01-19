//
//  CommandHistoryPopup.m
//  iTerm
//
//  Created by George Nachman on 1/14/14.
//
//

#import "CommandHistoryPopup.h"
#import "CommandHistory.h"
#import "CommandHistoryEntry.h"
#import "NSDateFormatterExtras.h"
#import "PopupModel.h"

@implementation CommandHistoryPopupEntry

- (void)dealloc {
    [_command release];
    [_date release];
    [super dealloc];
}

@end

@implementation CommandHistoryPopupWindowController {
    IBOutlet NSTableView *_tableView;
    int _partialCommandLength;
}

- (id)init
{
    self = [super initWithWindowNibName:@"CommandHistoryPopup"
                               tablePtr:nil
                                  model:[[[PopupModel alloc] init] autorelease]];
    if (self) {
        [self setTableView:_tableView];
    }

    return self;
}

- (void)dealloc {
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [super dealloc];
}

- (void)loadCommandsForHost:(VT100RemoteHost *)host partialCommand:(NSString *)partialCommand {
    CommandHistory *history = [CommandHistory sharedInstance];
    [[self unfilteredModel] removeAllObjects];
    _partialCommandLength = partialCommand.length;
    NSArray *autocompleteEntries = [history autocompleteSuggestionsWithPartialCommand:partialCommand
                                                                               onHost:host];
    NSArray *expandedEntries = [history entryArrayByExpandingAllUsesInEntryArray:autocompleteEntries];
    for (CommandHistoryEntry *entry in expandedEntries) {
        CommandHistoryPopupEntry *popupEntry = [[[CommandHistoryPopupEntry alloc] init] autorelease];
        popupEntry.command = entry.command;
        popupEntry.date = [NSDate dateWithTimeIntervalSinceReferenceDate:entry.lastUsed];

        [popupEntry setMainValue:popupEntry.command];
        [[self unfilteredModel] addObject:popupEntry];
    }
    [self reloadData:YES];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex
{
    CommandHistoryPopupEntry* entry = [[self model] objectAtIndex:[self convertIndex:rowIndex]];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter dateDifferenceStringFromDate:entry.date];
    } else {
        // Contents
        return [super tableView:aTableView objectValueForTableColumn:aTableColumn row:rowIndex];
    }
}

- (void)rowSelected:(id)sender;
{
    if ([_tableView selectedRow] >= 0) {
        CommandHistoryPopupEntry* entry = [[self model] objectAtIndex:[self convertIndex:[_tableView selectedRow]]];
        [self.delegate popupInsertText:[entry.command substringFromIndex:_partialCommandLength]];
        [super rowSelected:sender];
    }
}

@end
