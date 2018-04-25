//
//  CommandHistoryPopup.m
//  iTerm
//
//  Created by George Nachman on 1/14/14.
//
//

#import "CommandHistoryPopup.h"

#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermShellHistoryController.h"
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
    __weak IBOutlet NSTableView *_tableView;
    int _partialCommandLength;
}

- (instancetype)init {
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

- (NSArray *)commandsForHost:(VT100RemoteHost *)host
              partialCommand:(NSString *)partialCommand
                      expand:(BOOL)expand {
    iTermShellHistoryController *history = [iTermShellHistoryController sharedInstance];
    if (expand) {
        return [history autocompleteSuggestionsWithPartialCommand:partialCommand onHost:host];
    } else {
        return [history commandHistoryEntriesWithPrefix:partialCommand onHost:host];
    }
}

- (void)loadCommands:(NSArray *)commands partialCommand:(NSString *)partialCommand {
    [[self unfilteredModel] removeAllObjects];
    _partialCommandLength = partialCommand.length;
    for (id obj in commands) {
        CommandHistoryPopupEntry *popupEntry = [[[CommandHistoryPopupEntry alloc] init] autorelease];
        if ([obj isKindOfClass:[iTermCommandHistoryCommandUseMO class]]) {
            iTermCommandHistoryCommandUseMO *commandUse = obj;
            popupEntry.command = commandUse.command;
            popupEntry.date = [NSDate dateWithTimeIntervalSinceReferenceDate:commandUse.time.doubleValue];
        } else {
            iTermCommandHistoryEntryMO *entry = obj;
            popupEntry.command = entry.command;
            popupEntry.date = [NSDate dateWithTimeIntervalSinceReferenceDate:entry.timeOfLastUse.doubleValue];
        }
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

- (void)rowSelected:(id)sender
{
    if ([_tableView selectedRow] >= 0) {
        CommandHistoryPopupEntry* entry = [[self model] objectAtIndex:[self convertIndex:[_tableView selectedRow]]];
        [self.delegate popupInsertText:[entry.command substringFromIndex:_partialCommandLength]];
        [super rowSelected:sender];
    }
}

@end
