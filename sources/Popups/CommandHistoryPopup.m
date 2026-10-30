//
//  CommandHistoryPopup.m
//  iTerm
//
//  Created by George Nachman on 1/14/14.
//
//

#import "CommandHistoryPopup.h"

#import "DebugLogging.h"
#import "iTermApplication.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermShellHistoryController.h"
#import "NSArray+iTerm.h"
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
    BOOL _autocomplete;
}

- (instancetype)initForAutoComplete:(BOOL)autocomplete {
    self = [super initWithWindowNibName:@"CommandHistoryPopup"
                               tablePtr:nil
                                  model:[[[PopupModel alloc] init] autorelease]];
    if (self) {
        _autocomplete = autocomplete;
        [self window];
        [self setTableView:_tableView];
    }

    return self;
}

- (void)dealloc {
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [super dealloc];
}

- (NSArray *)commandsForHost:(id<VT100RemoteHostReading>)host
              partialCommand:(NSString *)partialCommand
                      expand:(BOOL)expand {
    iTermShellHistoryController *history = [iTermShellHistoryController sharedInstance];
    if (expand) {
        return [history autocompleteSuggestionsWithPartialCommand:partialCommand onHost:host];
    } else {
        return [history commandHistoryEntriesWithPrefix:partialCommand onHost:host];
    }
}

- (void)loadCommands:(NSArray *)commands
      partialCommand:(NSString *)partialCommand
 sortChronologically:(BOOL)sortChronologically {
    [[self unfilteredModel] removeAllObjects];
    _partialCommandLength = partialCommand.length;
    NSArray<CommandHistoryPopupEntry *> *popupEntries = [commands mapWithBlock:^id _Nullable(id obj) {
        CommandHistoryPopupEntry *popupEntry = [[[CommandHistoryPopupEntry alloc] init] autorelease];
        if ([obj isKindOfClass:[iTermCommandHistoryCommandUseMO class]]) {
            iTermCommandHistoryCommandUseMO *commandUse = obj;
            popupEntry.command = commandUse.command;
            popupEntry.date = [NSDate dateWithTimeIntervalSinceReferenceDate:commandUse.time.doubleValue];
        } else if ([obj isKindOfClass:[NSString class]]) {
            popupEntry.command = obj;
            popupEntry.prefix = partialCommand;
            popupEntry.date = nil;
        } else {
            iTermCommandHistoryEntryMO *entry = obj;
            popupEntry.command = entry.command;
            popupEntry.date = [NSDate dateWithTimeIntervalSinceReferenceDate:entry.timeOfLastUse.doubleValue];
        }
        [popupEntry setMainValue:popupEntry.command];
        return popupEntry;
    }];
    if (sortChronologically) {
        popupEntries = [popupEntries sortedArrayUsingComparator:^NSComparisonResult(CommandHistoryPopupEntry *lhs, CommandHistoryPopupEntry *rhs) {
            return [rhs.date compare:lhs.date];
        }];
    }
    for (CommandHistoryPopupEntry *popupEntry in popupEntries) {
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
        if (!entry.date) {
            return @"";
        }
        return [NSDateFormatter dateDifferenceStringFromDate:entry.date];
    } else {
        // Contents
        return [super tableView:aTableView objectValueForTableColumn:aTableColumn row:rowIndex];
    }
}

// Returns nil if the selected command doesn't begin with what's been typed.
- (NSString *)insertableString {
    CommandHistoryPopupEntry *entry = [[self model] objectAtIndex:[self convertIndex:[_tableView selectedRow]]];
    if (entry.prefix.length > 0) {
        return entry.command;
    }
    // The popup may not have reloaded since the last keystroke (for example,
    // when an autosuggestion after the cursor makes the session ineligible for
    // updates), so measure what's typed now rather than trusting the length
    // from the last load. Issue 13168.
    NSString *typed = _autocomplete ? [self.delegate popupTypedCommand] : nil;
    DLog(@"command=%@ typed=%@ partialCommandLength=%@", entry.command, typed, @(_partialCommandLength));
    if (typed) {
        // History matches prefixes case-insensitively, so match the same way
        // here and cut at the matched length, which can differ from
        // typed.length when case folding changes the length.
        const NSRange match = [entry.command rangeOfString:typed
                                                   options:NSAnchoredSearch | NSCaseInsensitiveSearch];
        if (match.location == NSNotFound) {
            return nil;
        }
        return [entry.command substringFromIndex:NSMaxRange(match)];
    }
    if (entry.command.length < _partialCommandLength) {
        return nil;
    }
    return [entry.command substringFromIndex:_partialCommandLength];
}

- (void)rowSelected:(id)sender {
    if ([_tableView selectedRow] >= 0) {
        NSString *const string = [self insertableString];
        if (!string) {
            DLog(@"Nothing to insert");
            [super rowSelected:sender];
            return;
        }
        const NSEventModifierFlags flags = [[iTermApplication sharedApplication] it_modifierFlags];
        const NSEventModifierFlags mask = NSEventModifierFlagShift | NSEventModifierFlagOption;
        if (!_autocomplete || (flags & mask) == NSEventModifierFlagShift) {
            [self.delegate popupInsertText:string popup:self];
            [super rowSelected:sender];
            return;
        } else if (_autocomplete && (flags & mask) == NSEventModifierFlagOption) {
            [self.delegate popupInsertText:[string stringByAppendingString:@"\n"]
                                     popup:self];
            [super rowSelected:sender];
            return;
        }
    }
    [self.delegate popupInsertText:@"\n" popup:self];
    [super rowSelected:sender];
}

- (void)previewCurrentRow {
    if ([_tableView selectedRow] >= 0) {
        NSString *const string = [self insertableString];
        if (string) {
            [self.delegate popupPreview:string];
        }
    }
}

// Called for option+return
- (void)insertNewlineIgnoringFieldEditor:(id)sender {
    [self rowSelected:sender];
}

- (NSString *)footerString {
    if (!_autocomplete) {
        return nil;
    }
    return @"Press ⇧⏎ or ⌥⏎ to send command.";
}

- (void)moveLeft:(id)sender {
    if ((_autocomplete || self.forwardKeyDown) && NSApp.currentEvent.type == NSEventTypeKeyDown) {
        [self.delegate popupKeyDown:NSApp.currentEvent];
        [self closePopupWindow];
    }
}

- (void)moveRight:(id)sender {
    if ((_autocomplete || self.forwardKeyDown) && NSApp.currentEvent.type == NSEventTypeKeyDown) {
        [self.delegate popupKeyDown:NSApp.currentEvent];
        [self closePopupWindow];
    }
}

- (void)doCommandBySelector:(SEL)selector {
    if ((_autocomplete || self.forwardKeyDown) && NSApp.currentEvent.type == NSEventTypeKeyDown) {
        // Control-C and such should go to the session.
        [self.delegate popupKeyDown:NSApp.currentEvent];
        [self closePopupWindow];
    } else {
        [super doCommandBySelector:selector];
    }
}

- (void)insertTab:(nullable id)sender {
    if (!_autocomplete) {
        return;
    }
    // Don't steal tab.
    [self passKeyEventToDelegateForSelector:_cmd string:@"\t"];
}

@end
