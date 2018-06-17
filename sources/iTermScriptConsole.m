//
//  iTermScriptConsole.m
//  iTerm2
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermScriptConsole.h"

#import "iTermAPIServer.h"
#import "iTermScriptHistory.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermWebSocketConnection.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"

typedef NS_ENUM(NSInteger, iTermScriptFilterControlTag) {
    iTermScriptFilterControlTagAll = 0,
    iTermScriptFilterControlTagRunning = 1
};

@interface iTermScriptConsole ()<NSTabViewDelegate, NSTableViewDataSource, NSTableViewDelegate>

@end

@implementation iTermScriptConsole {
    __weak IBOutlet NSTableView *_tableView;
    __weak IBOutlet NSTabView *_tabView;
    IBOutlet NSTextView *_logsView;
    IBOutlet NSTextView *_callsView;

    __weak IBOutlet NSTableColumn *_nameColumn;
    __weak IBOutlet NSTableColumn *_dateColumn;

    __weak IBOutlet NSSegmentedControl *_scriptFilterControl;

    __weak IBOutlet NSButton *_scrollToBottomOnUpdate;

    NSDateFormatter *_dateFormatter;
    __weak IBOutlet NSTextField *_filter;
    __weak IBOutlet NSButton *_terminateButton;
    __weak IBOutlet NSButton *_startButton;

    id _token;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithWindowNibName:@"iTermScriptConsole"];
    });
    return instance;
}

- (void)makeTextViewHorizontallyScrollable:(NSTextView *)textView {
    [textView.enclosingScrollView setHasHorizontalScroller:YES];
    [textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [textView setHorizontallyResizable:YES];
    [[textView textContainer] setWidthTracksTextView:NO];
    [[textView textContainer] setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
}


- (void)findNext:(id)sender {
    NSControl *fakeSender = [[NSControl alloc] init];
    fakeSender.tag = NSTextFinderActionNextMatch;
    if (_tabView.selectedTabViewItem.view == _logsView.enclosingScrollView) {
        [_logsView performFindPanelAction:fakeSender];
    } else {
        [_callsView performFindPanelAction:fakeSender];
    }
}

- (void)findPrevious:(id)sender {
    NSControl *fakeSender = [[NSControl alloc] init];
    fakeSender.tag = NSTextFinderActionPreviousMatch;
    if (_tabView.selectedTabViewItem.view == _logsView.enclosingScrollView) {
        [_logsView performFindPanelAction:fakeSender];
    } else {
        [_callsView performFindPanelAction:fakeSender];
    }
}

- (void)findWithSelection:(id)sender {
    NSControl *fakeSender = [[NSControl alloc] init];
    fakeSender.tag = NSTextFinderActionSetSearchString;
    if (_tabView.selectedTabViewItem.view == _logsView.enclosingScrollView) {
        [_logsView performFindPanelAction:fakeSender];
    } else {
        [_callsView performFindPanelAction:fakeSender];
    }
}

- (void)showFindPanel:(id)sender {
    NSControl *fakeSender = [[NSControl alloc] init];
    fakeSender.tag = NSTextFinderActionShowFindInterface;
    if (_tabView.selectedTabViewItem.view == _logsView.enclosingScrollView) {
        [_logsView performFindPanelAction:fakeSender];
    } else {
        [_callsView performFindPanelAction:fakeSender];
    }
}

- (instancetype)initWithWindowNibName:(NSNibName)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"Ld jj:mm:ss"
                                                                    options:0
                                                                     locale:[NSLocale currentLocale]];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(numberOfScriptHistoryEntriesDidChange:)
                                                     name:iTermScriptHistoryNumberOfEntriesDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(historyEntryDidChange:)
                                                     name:iTermScriptHistoryEntryDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(connectionRejected:)
                                                     name:iTermAPIServerConnectionRejected
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(connectionAccepted:)
                                                     name:iTermAPIServerConnectionAccepted
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(connectionClosed:)
                                                     name:iTermAPIServerConnectionClosed
                                                   object:nil];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    _tabView.tabViewItems[0].view = _logsView.enclosingScrollView;
    _tabView.tabViewItems[1].view = _callsView.enclosingScrollView;

    [self makeTextViewHorizontallyScrollable:_logsView];
    [self makeTextViewHorizontallyScrollable:_callsView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeObserver];
}

- (IBAction)scriptFilterDidChange:(id)sender {
    [_tableView reloadData];
    _terminateButton.enabled = NO;
    _startButton.enabled = NO;
}

- (NSString *)stringForRow:(NSInteger)row column:(NSTableColumn *)column {
    iTermScriptHistoryEntry *entry = [[self filteredEntries] objectAtIndex:row];
    if (column == _nameColumn) {
        if (entry.isRunning) {
            return entry.name;
        } else {
            return [NSString stringWithFormat:@"(%@)", entry.name];
        }
    } else {
        return [_dateFormatter stringFromDate:entry.startDate];
    }
}

- (NSArray<iTermScriptHistoryEntry *> *)filteredEntries {
    if (_scriptFilterControl.selectedSegment == iTermScriptFilterControlTagAll) {
        return [[iTermScriptHistory sharedInstance] entries];
    } else {
        return [[iTermScriptHistory sharedInstance] runningEntries];
    }
}

- (iTermScriptHistoryEntry *)terminateScriptOnRow:(NSInteger)row {
    iTermScriptHistoryEntry *entry = [[self filteredEntries] objectAtIndex:row];
    if (entry.isRunning && entry.pid) {
        [entry kill];
    }
    return entry;
}

- (IBAction)terminate:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < self.filteredEntries.count) {
        [self terminateScriptOnRow:row];
    }
}

- (IBAction)startOrRestart:(id)sender {
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && row < self.filteredEntries.count) {
        iTermScriptHistoryEntry *entry = [self terminateScriptOnRow:row];
        if (entry.relaunch) {
            entry.relaunch();
        }
    }
}

- (IBAction)closeCurrentSession:(id)sender {
    [self close];
}

- (void)closeWindow:(id)sender {
    [self close];
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

- (void)cancel:(id)sender {
    [self close];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [[self filteredEntries] count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    static NSString *const identifier = @"ScriptConsoleEntryIdentifier";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        result.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }

    id value = [self stringForRow:row column:tableColumn];
    if ([value isKindOfClass:[NSAttributedString class]]) {
        result.attributedStringValue = value;
        result.toolTip = [value string];
    } else {
        result.stringValue = value;
        result.toolTip = value;
    }

    return result;
}

#pragma mark - NSTabViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self removeObserver];
    if (!_tableView.numberOfSelectedRows) {
        _logsView.string = @"";
        _callsView.string = @"";
        _terminateButton.enabled = NO;
        _startButton.title = @"Start";
        _startButton.enabled = NO;
    } else {
        [self scrollLogsToBottomIfNeeded];
        [self scrollCallsToBottomIfNeeded];
        NSInteger row = _tableView.selectedRow;
        iTermScriptHistoryEntry *entry = [[self filteredEntries] objectAtIndex:row];
        _terminateButton.enabled = entry.isRunning && (entry.pid != 0);
        _startButton.enabled = entry.relaunch != nil;
        _logsView.font = [NSFont fontWithName:@"Menlo" size:12];
        _callsView.font = [NSFont fontWithName:@"Menlo" size:12];

        _logsView.string = [entry.logLines componentsJoinedByString:@"\n"];
        if (!entry.lastLogLineContinues) {
            _logsView.string = [_logsView.string stringByAppendingString:@"\n"];
        }
        _callsView.string = [entry.callEntries componentsJoinedByString:@"\n"];
        __weak __typeof(self) weakSelf = self;
        _token = [[NSNotificationCenter defaultCenter] addObserverForName:iTermScriptHistoryEntryDidChangeNotification
                                                                   object:entry
                                                                    queue:nil
                                                               usingBlock:^(NSNotification * _Nonnull note) {
                                                                   __typeof(self) strongSelf = weakSelf;
                                                                   if (!strongSelf) {
                                                                       return;
                                                                   }
                                                                   if (note.userInfo) {
                                                                       NSString *delta = note.userInfo[iTermScriptHistoryEntryDelta];
                                                                       NSString *property = note.userInfo[iTermScriptHistoryEntryFieldKey];
                                                                       if ([property isEqualToString:iTermScriptHistoryEntryFieldLogsValue]) {
                                                                           [strongSelf appendLogs:delta];
                                                                           [strongSelf scrollLogsToBottomIfNeeded];
                                                                       } else if ([property isEqualToString:iTermScriptHistoryEntryFieldRPCValue]) {
                                                                           [strongSelf appendCalls:delta];
                                                                           [strongSelf scrollCallsToBottomIfNeeded];
                                                                       }
                                                                   } else {
                                                                       [strongSelf->_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                                                                                                         columnIndexes:[NSIndexSet indexSetWithIndex:0]];
                                                                   }
                                                               }];
    }
}

- (void)appendLogs:(NSString *)delta {
    if (!_filter.stringValue.length) {
        [_logsView.textStorage.mutableString appendString:delta];
    } else {
        [self updateFilteredValue];
    }
}

- (void)appendCalls:(NSString *)delta {
    if (!_filter.stringValue.length) {
        [_callsView.textStorage.mutableString appendString:delta];
    } else {
        [self updateFilteredValue];
    }
}

- (void)scrollLogsToBottomIfNeeded {
    if (_scrollToBottomOnUpdate.state == NSOnState && _tabView.selectedTabViewItem.view == _logsView.enclosingScrollView) {
        [_logsView scrollRangeToVisible: NSMakeRange(_logsView.string.length, 0)];
    }
}

- (void)scrollCallsToBottomIfNeeded {
    if (_scrollToBottomOnUpdate.state == NSOnState && _tabView.selectedTabViewItem.view == _callsView.enclosingScrollView) {
        [_callsView scrollRangeToVisible: NSMakeRange(_callsView.string.length, 0)];
    }
}

- (IBAction)filterDidChange:(id)sender {
    [self updateFilteredValue];
}

- (BOOL)line:(NSString *)line containsString:(NSString *)filter caseSensitive:(BOOL)caseSensitive {
    if (caseSensitive) {
        return [line containsString:filter];
    } else {
        return [line localizedCaseInsensitiveContainsString:filter];
    }
}

- (void)updateFilteredValue {
    if (_tableView.selectedRow == -1) {
        _logsView.string = @"";
        _callsView.string = @"";
        return;
    }
    iTermScriptHistoryEntry *entry = [[self filteredEntries] objectAtIndex:_tableView.selectedRow];

    NSString *filter = _filter.stringValue;
    BOOL unfiltered = filter.length == 0;
    BOOL caseSensitive = [filter rangeOfCharacterFromSet:[NSCharacterSet uppercaseLetterCharacterSet]].location != NSNotFound;
    NSString *newValue = [[entry.logLines filteredArrayUsingBlock:^BOOL(NSString *line) {
        return unfiltered || [self line:line containsString:filter caseSensitive:caseSensitive];
    }] componentsJoinedByString:@"\n"];
    _logsView.string = newValue;

    newValue = [[entry.callEntries filteredArrayUsingBlock:^BOOL(NSString *line) {
        return unfiltered || [self line:line containsString:filter caseSensitive:caseSensitive];
    }] componentsJoinedByString:@"\n"];
    _callsView.string = newValue;
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self updateFilteredValue];
}

#pragma mark - Notifications

- (void)numberOfScriptHistoryEntriesDidChange:(NSNotification *)notification {
    [_tableView reloadData];
    _terminateButton.enabled = NO;
    _startButton.enabled = NO;
}

- (void)historyEntryDidChange:(NSNotification *)notification {
    if (!notification.userInfo) {
        [_tableView reloadData];
        _terminateButton.enabled = NO;
        _startButton.enabled = NO;
    }
}

- (void)connectionRejected:(NSNotification *)notification {
    NSString *key = notification.object;
    iTermScriptHistoryEntry *entry = nil;
    if (key) {
        entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:key];
    } else {
        key = [[NSUUID UUID] UUIDString];  // Just needs to be something unique to identify this now-immutable log
    }
    if (!entry) {
        NSString *name = [NSString castFrom:notification.userInfo[@"job"]];
        if (!name) {
            name = [NSString stringWithFormat:@"pid %@", notification.userInfo[@"pid"]];
        }
        if (!name) {
            // Shouldn't happen as there ought to always be a PID
            name = @"Unknown";
        }
        entry = [[iTermScriptHistoryEntry alloc] initWithName:name
                                                   identifier:key
                                                     relaunch:nil];
    }
    entry.pid = [notification.userInfo[@"pid"] intValue];
    [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
    [entry addOutput:notification.userInfo[@"reason"]];
    [entry stopRunning];
}

- (void)connectionAccepted:(NSNotification *)notification {
    NSString *key = notification.object;
    iTermScriptHistoryEntry *entry = nil;
    if (key) {
        entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:key];
    } else {
        assert(false);
    }
    if (!entry) {
        NSString *name = [NSString castFrom:notification.userInfo[@"job"]];
        if (!name) {
            name = [NSString stringWithFormat:@"pid %@", notification.userInfo[@"pid"]];
        }
        if (!name) {
            // Shouldn't happen as there ought to always be a PID
            name = @"Unknown";
        }
        entry = [[iTermScriptHistoryEntry alloc] initWithName:name
                                                   identifier:key
                                                     relaunch:nil];
        entry.pid = [notification.userInfo[@"pid"] intValue];
        [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
    }
    entry.websocketConnection = notification.userInfo[@"websocket"];
    [entry addOutput:[NSString stringWithFormat:@"Connection accepted: %@\n", notification.userInfo[@"reason"]]];
}

- (void)connectionClosed:(NSNotification *)notification {
    NSString *key = notification.object;
    assert(key);
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:key];
    if (!entry) {
        return;
    }
    [entry addOutput:@"\nConnection closed."];
    [entry stopRunning];
}

#pragma mark - Private

- (void)removeObserver {
    if (_token) {
        [[NSNotificationCenter defaultCenter] removeObserver:_token];
        _token = nil;
    }
}

@end
