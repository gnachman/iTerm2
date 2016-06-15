//
//  ToolJobs.m
//  iTerm
//
//  Created by George Nachman on 9/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolJobs.h"

#import "iTermToolWrapper.h"
#import "NSTableColumn+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTask.h"
#import "ProcessCache.h"

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

        [[self cell] setControlSize:NSSmallControlSize];
        [[self cell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
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

@implementation ToolJobs

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        names_ = [[NSMutableArray alloc] init];
        pids_ = [[NSArray alloc] init];

        kill_ = [[[NSButton alloc] initWithFrame:NSMakeRect(0,
                                                            frame.size.height - kButtonHeight,
                                                            frame.size.width,
                                                            kButtonHeight)] autorelease];
        [kill_ setButtonType:NSMomentaryPushInButton];
        [kill_ setTitle:@"Send Signal"];
        [kill_ setTarget:self];
        [kill_ setAction:@selector(kill:)];
        [kill_ setBezelStyle:NSSmallSquareBezelStyle];
        [kill_ sizeToFit];
        [kill_ setAutoresizingMask:NSViewMinYMargin | NSViewMaxXMargin];
        [self addSubview:kill_];
        [kill_ bind:@"enabled" toObject:self withKeyPath:@"killable" options:nil];
        signal_ = [[SignalPicker alloc] initWithFrame:NSMakeRect(kill_.frame.size.width + kMargin,
                                                                 frame.size.height - kButtonHeight + 1,
                                                                 frame.size.width - kill_.frame.size.width - 2*kMargin,
                                                                 kButtonHeight)];
        signal_.delegate = self;
        [signal_ setAutoresizingMask:NSViewMinYMargin | NSViewMaxXMargin];
        [signal_ sizeToFit];
        [self addSubview:signal_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        [scrollView_ setBorderType:NSBezelBorder];
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;
        col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Name"];
        NSFont *theFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        [[col dataCell] setFont:theFont];
        tableView_.rowHeight = col.suggestedRowHeight;
        [col release];

        col = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
        [col setEditable:NO];
        [col setWidth:75];
        [col setMinWidth:75];
        [col setMaxWidth:75];
        [tableView_ addTableColumn:col];
        [[col dataCell] setFont:theFont];
        [[col headerCell] setStringValue:@"pid"];
        [col release];

        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];

        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];


        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

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

- (void)relayout
{
    NSRect frame = self.frame;
    kill_.frame = NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight);
    [kill_ sizeToFit];
    signal_.frame = NSMakeRect(kill_.frame.size.width + kMargin,
                               frame.size.height - kButtonHeight + 1,
                               signal_.frame.size.width,
                               kButtonHeight);
    [signal_ sizeToFit];
    scrollView_.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin);
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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [signal_ release];
    [tableView_ release];
    [scrollView_ release];
    [timer_ invalidate];
    timer_ = nil;
    [names_ release];
    [pids_ release];
    [super dealloc];
}

- (void)shutdown
{
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
    NSSet *pids = [[ProcessCache sharedInstance] childrenOfPid:rootPid levelsToSkip:0];
    if (![pids isEqualToSet:[NSSet setWithArray:pids_]]) {
        // Something changed. Get job names, which is expensive.
        [pids_ release];
        NSArray *sortedArray = [[pids allObjects] sortedArrayUsingSelector:@selector(compare:)];
        pids_ = [[NSMutableArray arrayWithArray:sortedArray] retain];
        [names_ removeAllObjects];
        int i = 0;
        for (NSNumber *pid in pids_) {
            BOOL fg;
            NSString *pidName;
            pidName = [[ProcessCache sharedInstance] getNameOfPid:[pid intValue]
                                                     isForeground:&fg];
            if (pidName) {
                [names_ addObject:pidName];
                i++;
                if (i > kMaxJobs) {
                    break;
                }
            }
        }
        [tableView_ reloadData];

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
    return [names_ count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    if ([[aTableColumn identifier] isEqualToString:@"name"]) {
        // name
        return [names_ objectAtIndex:rowIndex];
    } else {
        // pid
        return [[pids_ objectAtIndex:rowIndex] stringValue];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    self.killable = ([tableView_ selectedRow] >= 0 && [signal_ isValid]);
}

- (void)kill:(id)sender
{
    NSNumber *pid = [pids_ objectAtIndex:[tableView_ selectedRow]];
    pid_t p = [pid intValue];
    kill(p, [signal_ intValue]);
}

- (CGFloat)minimumHeight
{
    return 60;
}

#pragma mark - NSComboBoxDelegate

- (void)comboBoxSelectionIsChanging:(NSNotification *)notification {
    self.killable = ([tableView_ selectedRow] >= 0 && [signal_ isValid]);
}

@end
