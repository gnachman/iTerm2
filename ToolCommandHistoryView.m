//
//  ToolCommandHistoryView.m
//  iTerm
//
//  Created by George Nachman on 1/15/14.
//
//

#import "ToolCommandHistoryView.h"
#import "CommandHistory.h"
#import "NSDateFormatterExtras.h"
#import "PTYSession.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@implementation ToolCommandHistoryView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    NSTimer *refreshTimer_;
    BOOL shutdown_;
    NSArray *entries_;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        [clear_ setButtonType:NSMomentaryPushInButton];
        [clear_ setTitle:@"Clear All"];
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setBezelStyle:NSSmallSquareBezelStyle];
        [clear_ sizeToFit];
        [clear_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:clear_];
        [clear_ release];
        
        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;
        col = [[[NSTableColumn alloc] initWithIdentifier:@"commands"] autorelease];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Commands"];
        NSFont *theFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        [[col dataCell] setFont:theFont];
        [tableView_ setRowHeight:[[[[NSLayoutManager alloc] init] autorelease] defaultLineHeightForFont:theFont]];
        
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        
        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        
        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];
        
        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(commandHistoryDidChange:)
                                                     name:kCommandHistoryDidChangeNotificationName
                                                   object:nil];
        refreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:10
                                                         target:self
                                                       selector:@selector(commandHistoryDidChange:)
                                                       userInfo:nil
                                                        repeats:YES];
        [self commandHistoryDidChange:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [refreshTimer_ invalidate];
    [tableView_ release];
    [scrollView_ release];
    [super dealloc];
}

- (void)shutdown
{
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [refreshTimer_ invalidate];
    refreshTimer_ = nil;
}

- (void)relayout
{
    NSRect frame = self.frame;
    [clear_ setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    [scrollView_ setFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
    NSSize contentSize = [scrollView_ contentSize];
    [tableView_ setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return entries_.count;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    CommandHistoryEntry *entry = entries_[rowIndex];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter compactDateDifferenceStringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:entry.lastUsed]];
    } else {
        // Contents
        NSString* value = [entry.command stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        return value;
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = [tableView_ selectedRow];
    if (row != -1) {
        CommandHistoryEntry *entry = entries_[row];
        if (entry.lastMark) {
            ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
            [[wrapper.term currentSession] scrollToMark:entry.lastMark];
        }
    }
}

- (void)commandHistoryDidChange:(id)sender
{
    [entries_ autorelease];
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    VT100RemoteHost *host = [[wrapper.term currentSession] currentHost];
    NSArray *temp = [[CommandHistory sharedInstance] autocompleteSuggestionsWithPartialCommand:@""
                                                                                        onHost:host];
    entries_ = [[[CommandHistory sharedInstance] entryArrayByExpandingAllUsesInEntryArray:temp] retain];
    [tableView_ reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (void)fixCursor
{
    if (shutdown_) {
        return;
    }
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
	[[[wrapper.term currentSession] TEXTVIEW] updateCursor:[[NSApplication sharedApplication] currentEvent]];
}

- (void)doubleClickOnTableView:(id)sender
{
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CommandHistoryEntry* entry = entries_[selectedIndex];
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    [[wrapper.term currentSession] insertText:entry.command];
}

- (void)clear:(id)sender
{
    [[CommandHistory sharedInstance] eraseHistory];
}

@end
