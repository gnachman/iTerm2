//
//  ToolPasteHistory.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//

#import "ToolPasteHistory.h"

#import "iTermController.h"
#import "iTermToolWrapper.h"
#import "NSDateFormatterExtras.h"
#import "NSTableColumn+iTerm.h"
#import "PseudoTerminal.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@implementation ToolPasteHistory {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    PasteboardHistory *pasteHistory_;
    NSTimer *minuteRefreshTimer_;
    BOOL shutdown_;
}

- (instancetype)initWithFrame:(NSRect)frame {
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

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable];


        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
        
        pasteHistory_ = [PasteboardHistory sharedInstance];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardHistoryDidChange:)
                                                     name:kPasteboardHistoryDidChange
                                                   object:nil];
        minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                               target:self
                                                             selector:@selector(pasteboardHistoryDidChange:)
                                                             userInfo:nil
                                                              repeats:YES];
        [tableView_ performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [minuteRefreshTimer_ invalidate];
    [tableView_ release];
    [scrollView_ release];
    [super dealloc];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [minuteRefreshTimer_ invalidate];
    minuteRefreshTimer_ = nil;
}

- (NSSize)contentSize {
    NSSize size = [scrollView_ contentSize];
    size.height = [[tableView_ headerView] frame].size.height;
    size.height += [tableView_ numberOfRows] * ([tableView_ rowHeight] + [tableView_ intercellSpacing].height);
    return size;
}

- (void)relayout {
    NSRect frame = self.frame;
    [clear_ setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    [scrollView_ setFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - kButtonHeight - kMargin)];
    NSSize contentSize = [self contentSize];
    [tableView_ setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return pasteHistory_.entries.count;
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                          row:(NSInteger)rowIndex {
    PasteboardEntry* entry = pasteHistory_.entries[rowIndex];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter compactDateDifferenceStringFromDate:entry.timestamp];
    } else {
        // Contents
        NSString* value = [[entry mainValue] stringByReplacingOccurrencesOfString:@"\n"
                                                                       withString:@" "];
        // Don't return an insanely long value to avoid performance issues.
        const NSUInteger kMaxLength = 256;
        if (value.length > kMaxLength) {
            return [value substringToIndex:kMaxLength];
        } else {
            return value;
        }
    }
}

- (void)pasteboardHistoryDidChange:(id)sender {
    [self update];
}

- (void)update {
    [tableView_ reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[tableView_ window] firstResponder];
    if (firstResponder != tableView_) {
        [tableView_ scrollToEndOfDocument:nil];
    }
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
    PasteboardEntry* entry = pasteHistory_.entries[selectedIndex];
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [thePasteboard setString:[entry mainValue] forType:NSStringPboardType];
    PTYTextView *textView = [[iTermController sharedInstance] frontTextView];
    [textView paste:nil];
    [textView.window makeFirstResponder:textView];
}

- (void)clear:(id)sender {
    [pasteHistory_ eraseHistory];
    [pasteHistory_ clear];
    [tableView_ reloadData];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (CGFloat)minimumHeight {
    return 60;
}

@end
