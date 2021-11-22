//
//  ToolJobs.m
//  iTerm
//
//  Created by George Nachman on 9/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolJobs.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermCompetentTableRowView.h"
#import "iTermProcessCache.h"
#import "iTermToolWrapper.h"
#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTask.h"

// For SignalPicker
static const int kDefaultSignal = 9;

static int gSignalsToList[] = {
     1, // SIGHUP
     2, // SIGINTR
     3, // SIGQUIT
     6, // SIGABRT
     9, // SIGKILL
    15, // SIGTERM
};


// For ToolJobs
static const int kMaxJobs = 20;
static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@implementation SignalPicker

+ (NSArray *)signalNames {
    return @[[NSNull null], @"HUP",  @"INT",  @"QUIT",
             @"ILL",   @"TRAP", @"ABRT",   @"EMT",
             @"FPE",   @"KILL", @"BUS",    @"SEGV",
             @"SYS",   @"PIPE", @"ALRM",   @"TERM",
             @"URG",   @"STOP", @"TSTP",   @"CONT",
             @"CHLD",  @"TTIN", @"TTOU",   @"IO",
             @"XCPU",  @"XFSZ", @"VTALRM", @"PROF",
             @"WINCH", @"INFO", @"USR1",   @"USR2"];
}

+ (int)signalForName:(NSString*)signalName {
    signalName = [[signalName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([signalName hasPrefix:@"SIG"]) {
        signalName = [signalName substringFromIndex:3];
    }
    int x = [signalName intValue];
    if (x > 0 && x < [[self signalNames] count]) {
        return x;
    }

    NSArray *signalNames = [self signalNames];
    NSUInteger index = [signalNames indexOfObject:signalName];
    if (index == NSNotFound) {
        return -1;
    } else {
        return index;
    }
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setIntValue:kDefaultSignal];
        [self setUsesDataSource:YES];
        [self setCompletes:YES];
        [self setDataSource:self];

        [[self cell] setControlSize:NSControlSizeSmall];
        [[self cell] setFont:[NSFont it_toolbeltFont]];
    }
    return self;
}

- (int)intValue {
    int x = [[self class] signalForName:[self stringValue]];
    return x == -1 ? kDefaultSignal : x;
}

- (void)setIntValue:(int)i {
    NSArray *signalNames = [[self class] signalNames];
    if (i <= 0 || i >= [signalNames count]) {
        i = kDefaultSignal;
    }
    [self setStringValue:signalNames[i]];
    [self setToolTip:[NSString stringWithFormat:@"SIG%@ (%d)", signalNames[i], i]];
}

- (BOOL)isValid {
    return [[self class] signalForName:[self stringValue]] != -1;
}

- (void)textDidEndEditing:(NSNotification *)aNotification {
    [self setIntValue:[self intValue]];
    id<NSComboBoxDelegate> comboBoxDelegate = (id<NSComboBoxDelegate>)[self delegate];
    [comboBoxDelegate comboBoxSelectionIsChanging:[NSNotification notificationWithName:NSComboBoxSelectionIsChangingNotification
                                                                                object:nil]];
}

- (void)textDidChange:(NSNotification *)notification {
    id<NSComboBoxDelegate> comboBoxDelegate = (id<NSComboBoxDelegate>)[self delegate];
    [comboBoxDelegate comboBoxSelectionIsChanging:[NSNotification notificationWithName:NSComboBoxSelectionIsChangingNotification
                                                                                object:nil]];
}

- (void)sizeToFit {
    NSRect frame = self.frame;
    frame.size.width = 70;  // Just wide enough for the widest signal name.
    self.frame = frame;
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox {
    return sizeof(gSignalsToList) / sizeof(gSignalsToList[0]);
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    NSArray *signalNames = [[self class] signalNames];
    return signalNames[gSignalsToList[index]];
}
- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(NSString *)aString {
    if ([aString intValue] > 0) {
        return NSNotFound;  // Without this, "1", "2", and "3" get replaced immediately!
    }

    int sig = [[self class] signalForName:aString];
    for (int i = 0; i < sizeof(gSignalsToList) / sizeof(gSignalsToList[0]); i++) {
        if (gSignalsToList[i] == sig) {
            return i;
        }
    }
    return NSNotFound;
}

- (NSString *)comboBox:(NSComboBox *)aComboBox completedString:(NSString *)uncompletedString {
    uncompletedString =
        [[uncompletedString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([uncompletedString hasPrefix:@"SIG"]) {
        uncompletedString = [uncompletedString substringFromIndex:3];
    }

    if ([uncompletedString length] == 0) {
        return @"";
    }

    NSArray *signalNames = [[self class] signalNames];
    int x = [uncompletedString intValue];
    if (x > 0 && x < [signalNames count]) {
        return uncompletedString;
    }

    for (int i = 1; i < [signalNames count]; i++) {
        if ([signalNames[i] hasPrefix:uncompletedString]) {
            // Found a prefix match
            return signalNames[i];
        }
    }

    return nil;
}

@end


@interface ToolJobs ()
- (void)updateTimer:(id)sender;
@property(nonatomic, assign) BOOL killable;
@end

@implementation ToolJobs {
    NSScrollView *_scrollView;
    NSTableView *_tableView;
    NSButton *kill_;
    SignalPicker *signal_;
    NSTimer *timer_;
    NSArray<iTermProcessInfo *> *_processInfos;
    BOOL shutdown_;
    NSTimeInterval timerInterval_;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _processInfos = @[];

        signal_ = [[SignalPicker alloc] initWithFrame:NSMakeRect(0,
                                                                 frame.size.height - kButtonHeight + 1,
                                                                 frame.size.width - kill_.frame.size.width - 2*kMargin,
                                                                 kButtonHeight)];
        signal_.delegate = self;
        [signal_ setAutoresizingMask:NSViewMinYMargin | NSViewMaxXMargin];
        [signal_ sizeToFit];
        [self addSubview:signal_];

        kill_ = [[NSButton alloc] initWithFrame:NSMakeRect(0,
                                                           frame.size.height - kButtonHeight,
                                                           frame.size.width,
                                                           kButtonHeight)];
        if (@available(macOS 10.16, *)) {
            kill_.bezelStyle = NSBezelStyleRegularSquare;
            kill_.bordered = NO;
            kill_.image = [NSImage it_imageForSymbolName:@"play" accessibilityDescription:@"Clear"];
            kill_.imagePosition = NSImageOnly;
            kill_.frame = NSMakeRect(signal_.frame.size.width + kMargin, 0, 22, 22);
        } else {
            [kill_ setButtonType:NSButtonTypeMomentaryPushIn];
            [kill_ setTitle:@"Send Signal"];
            [kill_ setBezelStyle:NSBezelStyleSmallSquare];
            [kill_ sizeToFit];
            kill_.frame = NSMakeRect(signal_.frame.size.width + kMargin, 0, kill_.frame.size.width, kill_.frame.size.height);
        }
        [kill_ setTarget:self];
        [kill_ setAction:@selector(kill:)];
        [kill_ setAutoresizingMask:NSViewMinYMargin | NSViewMaxXMargin];
        [self addSubview:kill_];
        [kill_ bind:@"enabled" toObject:self withKeyPath:@"killable" options:nil];

        _scrollView = [NSScrollView scrollViewWithTableViewForToolbeltWithContainer:self
                                                                             insets:NSEdgeInsetsMake(0,
                                                                                                     0,
                                                                                                     kButtonHeight + kMargin,
                                                                                                     0)];
        _tableView = _scrollView.documentView;
        _tableView.tableColumns[0].identifier = @"name";

        {
            NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
            [col setEditable:NO];
            [col setWidth:75];
            [col setMinWidth:75];
            [col setMaxWidth:75];
            [_tableView addTableColumn:col];
            [[col headerCell] setStringValue:@"pid"];
        }

        [_tableView setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        timerInterval_ = 1;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setSlowTimer)
                                                     name:NSWindowDidResignMainNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setFastTimer)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];

        [self updateTimer:nil];
    }
    return self;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = self.frame;
    signal_.frame = NSMakeRect(0,
                               frame.size.height - kButtonHeight + 1,
                               signal_.frame.size.width,
                               kButtonHeight);
    [signal_ sizeToFit];

    if (@available(macOS 10.16, *)) {
        NSRect rect = kill_.frame;
        rect.origin.x = NSMaxX(signal_.frame);
        rect.origin.y = frame.size.height - kButtonHeight + (kButtonHeight - rect.size.height) / 2;
        kill_.frame = rect;
    } else {
        kill_.frame = NSMakeRect(NSMaxX(signal_.frame) + kMargin, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight);
        [kill_ sizeToFit];
    }
    _scrollView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin);
}

// When not key, check much less often to avoid burning the battery.
- (void)setSlowTimer
{
    timerInterval_ = 10;
}

- (void)setFastTimer
{
    timerInterval_ = 1;
    [timer_ invalidate];
    timer_ = nil;
    [self updateTimer:nil];
}

- (void)shutdown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    shutdown_ = YES;
    [timer_ invalidate];
    timer_ = nil;
    [kill_ unbind:@"enabled"];
}

- (void)updateTimer:(id)sender
{
    timer_ = nil;
    if (shutdown_) {
        return;
    }
    iTermToolWrapper *wrapper = self.toolWrapper;
    pid_t rootPid = [wrapper.delegate.delegate toolbeltCurrentShellProcessId];

    NSArray<iTermProcessInfo *> *infos = [[[iTermProcessCache sharedInstance] processInfoForPid:rootPid] flattenedTree];
    NSSet<NSNumber *> *oldPids = [NSSet setWithArray:[_processInfos mapWithBlock:^id(iTermProcessInfo *info) {
        return @(info.processID);
    }]];
    NSSet<NSNumber *> *newPids = [NSSet setWithArray:[infos mapWithBlock:^id(iTermProcessInfo *info) {
        return @(info.processID);
    }]];
    if (![oldPids isEqual:newPids]) {
        NSInteger selectedIndex = [_tableView selectedRow];
        NSNumber *previouslySelectedPID = nil;
        if (selectedIndex >= 0) {
            previouslySelectedPID = @(_processInfos[selectedIndex].processID);
        }

        NSArray<iTermProcessInfo *> *sortedInfos = [infos sortedArrayUsingComparator:^NSComparisonResult(iTermProcessInfo * _Nonnull obj1, iTermProcessInfo * _Nonnull obj2) {
            return [@(obj1.processID) compare:@(obj2.processID)];
        }];
        [sortedInfos enumerateObjectsUsingBlock:^(iTermProcessInfo * _Nonnull info, NSUInteger idx, BOOL * _Nonnull stop) {
            if (idx == kMaxJobs) {
                *stop = YES;
                return;
            }
            [info resolveAsynchronously];
        }];
        _processInfos = sortedInfos;

        [_tableView reloadData];

        if (previouslySelectedPID) {
            NSInteger indexToSelect = [_processInfos indexOfObjectPassingTest:^BOOL(iTermProcessInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                return obj.processID == previouslySelectedPID.integerValue;
            }];
            if (indexToSelect != NSNotFound) {
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:indexToSelect]
                        byExtendingSelection:NO];
            } else {
                self.killable = NO;
            }
        }

        // Updating the table data causes the cursor to change into an arrow!
        [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
    }
    timer_ = [NSTimer scheduledTimerWithTimeInterval:timerInterval_
                                              target:self
                                            selector:@selector(updateTimer:)
                                            userInfo:nil
                                             repeats:NO];
}

- (void)fixCursor {
    if (!shutdown_) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
    }
}

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return MIN(_processInfos.count, kMaxJobs);
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolJobsEntry";
    NSString *value = [self stringForTableColumn:tableColumn row:row];
    return [tableView newTableCellViewWithTextFieldUsingIdentifier:identifier
                                                              font:[NSFont it_toolbeltFont]
                                                            string:value ?: @""];
}

- (NSString *)stringForTableColumn:(NSTableColumn *)aTableColumn
                               row:(NSInteger)rowIndex {
    if ([[aTableColumn identifier] isEqualToString:@"name"]) {
        // name
        return _processInfos[rowIndex].argv0 ?: _processInfos[rowIndex].name;
    } else {
        // pid
        return [@(_processInfos[rowIndex].processID) stringValue];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    self.killable = ([_tableView selectedRow] >= 0 && [signal_ isValid]);
}

- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    NSString *aString = [@(_processInfos[row].processID) stringValue];
    [pbItem setString:aString forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
}

- (void)kill:(id)sender {
    pid_t p = _processInfos[_tableView.selectedRow].processID;
    if (p > 0) {
        DLog(@"Send signal %@ to %@", signal_, @(p));
        kill(p, [signal_ intValue]);
    }
}

- (CGFloat)minimumHeight
{
    return 60;
}

#pragma mark - NSComboBoxDelegate

- (void)comboBoxSelectionIsChanging:(NSNotification *)notification {
    self.killable = ([_tableView selectedRow] >= 0 && [signal_ isValid]);
}

@end
