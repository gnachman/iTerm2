//
//  ToolCapturedOutput.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "ToolCapturedOutputView.h"
#import "CaptureTrigger.h"
#import "CommandHistoryEntry.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "ToolbeltView.h"
#import "ToolCommandHistoryView.h"
#import "ToolWrapper.h"

static const CGFloat kMargin = 4;

@interface ToolCapturedOutputView() <ToolbeltTool, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation ToolCapturedOutputView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    BOOL shutdown_;
    NSArray *capturedOutput_;
    NSCell *spareCell_;
    VT100ScreenMark *mark_;  // Mark from which captured output came
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        spareCell_ = [[NSCell alloc] initTextCell:@""];
        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kMargin)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;
        col = [[[NSTableColumn alloc] initWithIdentifier:@"contents"] autorelease];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Contents"];
        NSFont *theFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        [[col dataCell] setFont:theFont];
        [tableView_ setRowHeight:[[[[NSLayoutManager alloc] init] autorelease] defaultLineHeightForFont:theFont]];
        [tableView_ setHeaderView:nil];
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        
        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        tableView_.menu = [[[NSMenu alloc] init] autorelease];
        tableView_.menu.delegate = self;
        NSMenuItem *item;
        item = [[NSMenuItem alloc] initWithTitle:@"Toggle Checkmark"
                                          action:@selector(toggleCheckmark:)
                                   keyEquivalent:@""];
        [tableView_.menu addItem:item];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];
        
        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(capturedOutputDidChange:)
                                                     name:kPTYSessionCapturedOutputDidChange
                                                   object:nil];
        [self updateCapturedOutput];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [tableView_ release];
    [scrollView_ release];
    [spareCell_ release];
    [super dealloc];
}

- (void)updateCapturedOutput {
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    ToolCommandHistoryView *commandHistoryView = [[wrapper.term toolbelt] commandHistoryView];
    CommandHistoryEntry *entry = [commandHistoryView selectedEntry];
    VT100ScreenMark *mark;
    NSArray *theArray;
    if (entry) {
        mark = entry.lastMark;
    } else {
        mark = wrapper.term.currentSession.screen.lastCommandMark;
    }
    theArray = mark.capturedOutput;
    if (mark != mark_) {
        [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        [mark_ autorelease];
        mark_ = [mark retain];
    }
    
    [capturedOutput_ release];
    capturedOutput_ = [theArray copy];
    [tableView_ reloadData];
    
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)relayout {
    NSRect frame = self.frame;
    [scrollView_ setFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kMargin)];
    NSSize contentSize = [scrollView_ contentSize];
    [tableView_ setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return capturedOutput_.count;
}

- (id)tableView:(NSTableView *)aTableView
        objectValueForTableColumn:(NSTableColumn *)aTableColumn
                              row:(NSInteger)rowIndex {
    CapturedOutput *capturedOutput = capturedOutput_[rowIndex];
    return [self labelForCapturedOutput:capturedOutput];
}

- (NSString *)labelForCapturedOutput:(CapturedOutput *)capturedOutput {
    NSString *label = capturedOutput.line;
    if (capturedOutput.state) {
        label = [@"✓ " stringByAppendingString:label];
    }
    return label;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex {
    CapturedOutput *capturedOutput = capturedOutput_[rowIndex];
    NSString *label = [self labelForCapturedOutput:capturedOutput];
    [spareCell_ setWraps:YES];
    [spareCell_ setLineBreakMode:NSLineBreakByCharWrapping];
    [spareCell_ setStringValue:label];
    
    NSTableColumn *column = tableView_.tableColumns[0];
    CGFloat columnWidth = [column width];
    NSRect constrainedBounds = NSMakeRect(0, 0, columnWidth, CGFLOAT_MAX);
    NSSize naturalSize = [spareCell_ cellSizeForBounds:constrainedBounds];
    return naturalSize.height;
}

- (NSCell *)tableView:(NSTableView *)tableView
        dataCellForTableColumn:(NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    NSCell *cell = [[[NSCell alloc] initTextCell:@""] autorelease];
    [cell setEditable:NO];
//    [cell setTruncatesLastVisibleLine:YES];
    [cell setLineBreakMode:NSLineBreakByCharWrapping];
    [cell setWraps:YES];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CapturedOutput *capturedOutput = capturedOutput_[selectedIndex];
    
    if (capturedOutput) {
        ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
        [[wrapper.term currentSession] highlightAbsoluteLineNumber:capturedOutput.absoluteLineNumber];
    }
}

- (void)capturedOutputDidChange:(NSNotification *)notification {
    [self updateCapturedOutput];
}

- (void)fixCursor {
    if (shutdown_) {
        return;
    }
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
	[[[wrapper.term currentSession] textview] updateCursor:[[NSApplication sharedApplication] currentEvent]];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CapturedOutput *capturedOutput = capturedOutput_[selectedIndex];
    PTYSession *session = [self session];
    if (session) {
        [capturedOutput.trigger activateOnOutput:capturedOutput inSession:session];
    }
}

- (CGFloat)minimumHeight {
    return 60;
}

- (PTYSession *)session {
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    return [wrapper.term currentSession];
}

- (void)toggleCheckmark:(id)sender {
    NSInteger index = [tableView_ clickedRow];
    if (index >= 0) {
        CapturedOutput *capturedOutput = capturedOutput_[index];
        capturedOutput.state = !capturedOutput.state;
    }
    [self updateCapturedOutput];
}

#pragma mark - NSMenuDelegate

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [self respondsToSelector:[item action]] && [tableView_ clickedRow] >= 0;
}

@end
