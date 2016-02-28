//
//  ToolCapturedOutput.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "ToolCapturedOutputView.h"

#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCommandHistoryCommandUseMO+Addtions.h"
#import "iTermSearchField.h"
#import "iTermToolbeltView.h"
#import "iTermToolWrapper.h"
#import "NSTableColumn+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "ToolCommandHistoryView.h"

static const CGFloat kMargin = 4;

@interface ToolCapturedOutputView() <
    ToolbeltTool,
    NSMenuDelegate,
    NSSearchFieldDelegate,
    NSTextFieldDelegate>
@end

@implementation ToolCapturedOutputView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    BOOL shutdown_;
    NSArray *allCapturedOutput_;
    NSCell *spareCell_;
    VT100ScreenMark *mark_;  // Mark from which captured output came
    iTermSearchField *searchField_;
    NSButton *help_;
    NSArray *filteredEntries_;
}

@synthesize tableView = tableView_;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        spareCell_ = [[self cell] retain];

        help_ = [[NSButton alloc] initWithFrame:CGRectZero];
        [help_ setBezelStyle:NSHelpButtonBezelStyle];
        [help_ setButtonType:NSMomentaryPushInButton];
        [help_ setBordered:YES];
        [help_ sizeToFit];
        help_.target = self;
        help_.action = @selector(help:);
        help_.title = @"";
        [help_ setAutoresizingMask:NSViewMinXMargin];
        [self addSubview:help_];

        searchField_ = [[iTermSearchField alloc] initWithFrame:CGRectZero];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        [searchField_ setDelegate:self];
        [self addSubview:searchField_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:CGRectZero];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        [scrollView_ setBorderType:NSBezelBorder];
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
        tableView_.rowHeight = col.suggestedRowHeight;
        [tableView_ setHeaderView:nil];
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        NSSize spacing = tableView_.intercellSpacing;
        spacing.height += 5;
        tableView_.intercellSpacing = spacing;

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        tableView_.menu = [[[NSMenu alloc] init] autorelease];
        tableView_.menu.delegate = self;
        NSMenuItem *item;
        item = [[NSMenuItem alloc] initWithTitle:@"Toggle Checkmark"
                                          action:@selector(toggleCheckmark:)
                                   keyEquivalent:@""];
        [tableView_.menu addItem:item];

        [searchField_ setArrowHandler:tableView_];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        [self relayout];

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
    iTermToolWrapper *wrapper = self.toolWrapper;
    ToolCommandHistoryView *commandHistoryView = [wrapper.delegate commandHistoryView];
    iTermCommandHistoryCommandUseMO *commandUse = [commandHistoryView selectedCommandUse];
    VT100ScreenMark *mark;
    NSArray *theArray;
    if (commandUse) {
        mark = commandUse.mark;
    } else {
        mark = [wrapper.delegate.delegate toolbeltLastCommandMark];
    }
    theArray = mark.capturedOutput;
    if (mark != mark_) {
        [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        [mark_ autorelease];
        mark_ = [mark retain];
    }

    [allCapturedOutput_ release];
    allCapturedOutput_ = [theArray copy];

    // Now update filtered entries based on search string.
    [filteredEntries_ release];
    NSMutableArray *temp = [NSMutableArray array];
    for (CapturedOutput *capturedOutput in allCapturedOutput_) {
        if (!searchField_.stringValue.length ||
            [[self labelForCapturedOutput:capturedOutput] rangeOfString:searchField_.stringValue
                                                                options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [temp addObject:capturedOutput];
        }
    }
    filteredEntries_ = [temp retain];

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

    // Search field
    NSRect searchFieldFrame = NSMakeRect(0,
                                         0,
                                         frame.size.width - help_.frame.size.width - kMargin,
                                         searchField_.frame.size.height);
    searchField_.frame = searchFieldFrame;

    // Help button
    help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                             1,
                             help_.frame.size.width,
                             help_.frame.size.height);

    // Scroll view
    [scrollView_ setFrame:NSMakeRect(0,
                                     searchFieldFrame.size.height + kMargin,
                                     frame.size.width,
                                     frame.size.height - 2 * kMargin)];

    // Table view
    NSSize contentSize = [scrollView_ contentSize];
    NSTableColumn *column = tableView_.tableColumns[0];
    column.minWidth = contentSize.width;
    column.maxWidth = contentSize.width;
    [tableView_ sizeToFit];
    [tableView_ reloadData];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return filteredEntries_.count;
}

- (id)tableView:(NSTableView *)aTableView
        objectValueForTableColumn:(NSTableColumn *)aTableColumn
                              row:(NSInteger)rowIndex {
    CapturedOutput *capturedOutput = filteredEntries_[rowIndex];
    return [self labelForCapturedOutput:capturedOutput];
}

- (NSString *)labelForCapturedOutput:(CapturedOutput *)capturedOutput {
    NSString *label = capturedOutput.line;
    if (capturedOutput.state) {
        label = [@"✔ " stringByAppendingString:label];
    } else {
        label = [@"🔹 " stringByAppendingString:label];
    }
    return label;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex {
    CapturedOutput *capturedOutput = filteredEntries_[rowIndex];
    NSString *label = [self labelForCapturedOutput:capturedOutput];
    [spareCell_ setStringValue:label];
    NSRect constrainedBounds = NSMakeRect(0, 0, tableView_.frame.size.width, CGFLOAT_MAX);
    NSSize naturalSize = [spareCell_ cellSizeForBounds:constrainedBounds];
    return naturalSize.height;
}

- (NSCell *)tableView:(NSTableView *)tableView
        dataCellForTableColumn:(NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    return [self cell];
}

- (NSCell *)cell {
    NSCell *cell = [[[NSTextFieldCell alloc] init] autorelease];
    [cell setEditable:NO];
    [cell setLineBreakMode:NSLineBreakByWordWrapping];
    [cell setWraps:YES];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CapturedOutput *capturedOutput = filteredEntries_[selectedIndex];

    if (capturedOutput) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        [wrapper.delegate.delegate toolbeltDidSelectMark:capturedOutput.mark];
    }
}

- (void)capturedOutputDidChange:(NSNotification *)notification {
    [self updateCapturedOutput];
}

- (void)fixCursor {
    if (shutdown_) {
        return;
    }
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    CapturedOutput *capturedOutput = filteredEntries_[selectedIndex];
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltActivateTriggerForCapturedOutputInCurrentSession:capturedOutput];
}

- (CGFloat)minimumHeight {
    return 60;
}

- (void)toggleCheckmark:(id)sender {
    NSInteger index = [tableView_ clickedRow];
    if (index >= 0) {
        CapturedOutput *capturedOutput = filteredEntries_[index];
        capturedOutput.state = !capturedOutput.state;
    }
    [tableView_ reloadData];
}

#pragma mark - NSMenuDelegate

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [self respondsToSelector:[item action]] && [tableView_ clickedRow] >= 0;
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self updateCapturedOutput];
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    return @[];
}

#pragma mark - Actions

- (void)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iterm2.com/captured_output.html"]];
}

@end
