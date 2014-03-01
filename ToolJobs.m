//
//  ToolJobs.m
//  iTerm
//
//  Created by George Nachman on 9/6/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolJobs.h"
#import "ToolWrapper.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTask.h"
#import "ProcessCache.h"

static const int kMaxJobs = 20;
static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@interface ToolJobs ()
- (void)updateTimer:(id)sender;
@end

@implementation ToolJobs

@synthesize hasSelection;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        names_ = [[NSMutableArray alloc] init];
        pids_ = [[NSArray alloc] init];

        kill_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        [kill_ setButtonType:NSMomentaryPushInButton];
        [kill_ setTitle:@"Send Signal"];
        [kill_ setTarget:self];
        [kill_ setAction:@selector(kill:)];
        [kill_ setBezelStyle:NSSmallSquareBezelStyle];
        [kill_ sizeToFit];
        [kill_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:kill_];
        [kill_ release];
        [kill_ bind:@"enabled" toObject:self withKeyPath:@"hasSelection" options:nil];
        signal_ = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(kill_.frame.size.width + kMargin, frame.size.height - kButtonHeight + 1,
                                                                  1, 22)];
        struct { int num; NSString *name; } signals[] = {
            { 1, @"HUP", },
            { 2, @"INTR", },
            { 3, @"QUIT", },
            { 6, @"ABRT", },
            { 9, @"KILL", },
            { 15, @"TERM" },
            { 0, nil }
        };
        for (int i = 0; signals[i].num; i++) {
            NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:signals[i].name action:nil keyEquivalent:@""] autorelease];
            [item setTarget:self];
            [item setTag:signals[i].num];
            [[signal_ menu] addItem:item];
            if (signals[i].num == 9) {
                [signal_ selectItem:item];
            }
        }
        [[signal_ cell] setControlSize:NSSmallControlSize];
        [[signal_ cell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [signal_ setPullsDown:NO];
        [signal_ setAutoresizingMask:NSViewMinYMargin];
        [signal_ sizeToFit];
        [self addSubview:signal_];
        
        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
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
        [tableView_ setRowHeight:[[[[NSLayoutManager alloc] init] autorelease] defaultLineHeightForFont:theFont]];
        
        col = [[NSTableColumn alloc] initWithIdentifier:@"pid"];
        [col setEditable:NO];
        [col setWidth:75];
        [col setMinWidth:75];
        [col setMaxWidth:75];
        [tableView_ addTableColumn:col];
        [[col dataCell] setFont:theFont];
        [[col headerCell] setStringValue:@"pid"];
        
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
    signal_.frame = NSMakeRect(kill_.frame.size.width + kMargin, frame.size.height - kButtonHeight + 1,
                               1, 22);
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
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    pid_t rootPid = [[[wrapper.term currentSession] shell] pid];
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

- (void)fixCursor
{
    if (!shutdown_) {
        ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
        [[[wrapper.term currentSession] textview] updateCursor:[[NSApplication sharedApplication] currentEvent]];
    }
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [names_ count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
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
    self.hasSelection = ([tableView_ selectedRow] >= 0);
}

- (void)kill:(id)sender
{
    NSNumber *pid = [pids_ objectAtIndex:[tableView_ selectedRow]];
    pid_t p = [pid intValue];
    kill(p, [[signal_ selectedItem] tag]);
}

- (CGFloat)minimumHeight
{
    return 60;
}

@end
