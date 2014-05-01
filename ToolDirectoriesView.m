//
//  ToolDirectoriesView.m
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import "ToolDirectoriesView.h"
#import "iTermDirectoriesModel.h"
#import "iTermSearchField.h"
#import "NSDateFormatterExtras.h"
#import "PTYSession.h"
#import "ToolWrapper.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 5;

@implementation ToolDirectoriesView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    BOOL shutdown_;
    NSArray *entries_;
    NSArray *filteredEntries_;
    iTermSearchField *searchField_;
    NSFont *boldFont_;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        searchField_ = [[iTermSearchField alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 1)];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        [searchField_ setDelegate:self];
        [self addSubview:searchField_];

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

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                     searchField_.frame.size.height + kMargin,
                                                                     frame.size.width,
                                                                     frame.size.height - kButtonHeight - 2 * kMargin - searchField_.frame.size.height)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        NSSize contentSize = [self contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;
        col = [[[NSTableColumn alloc] initWithIdentifier:@"directories"] autorelease];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Directories"];
        NSFont *theFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        [[col dataCell] setFont:theFont];
        [tableView_ setRowHeight:[[[[NSLayoutManager alloc] init] autorelease] defaultLineHeightForFont:theFont]];

        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        [searchField_ setArrowHandler:tableView_];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        // Save the bold version of the table's default font
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        NSFont *font = [[col dataCell] font];
        boldFont_ = [[fontManager fontWithFamily:font.familyName
                                          traits:NSBoldFontMask
                                          weight:0
                                            size:font.pointSize] retain];

        [self relayout];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(directoriesDidChange:)
                                                     name:kDirectoriesDidChangeNotificationName
                                                   object:nil];
        [self performSelector:@selector(updateDirectories) withObject:nil afterDelay:0];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [tableView_ release];
    [scrollView_ release];
    [boldFont_ release];
    [super dealloc];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSize)contentSize {
    NSSize size = [scrollView_ contentSize];
    size.height = [[tableView_ headerView] frame].size.height;
    size.height += [tableView_ numberOfRows] * ([tableView_ rowHeight] + [tableView_ intercellSpacing].height);
    return size;
}

- (void)relayout {
    NSRect frame = self.frame;
    searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
    [clear_ setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
    scrollView_.frame = NSMakeRect(0,
                                   searchField_.frame.size.height + kMargin,
                                   frame.size.width,
                                   frame.size.height - kButtonHeight - 2 * kMargin - searchField_.frame.size.height);
    NSSize contentSize = [self contentSize];
    [tableView_ setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return filteredEntries_.count;
}

- (NSString *)tableView:(NSTableView *)tableView
         toolTipForCell:(NSCell *)cell
                   rect:(NSRectPointer)rect
            tableColumn:(NSTableColumn *)tableColumn
                    row:(NSInteger)row
          mouseLocation:(NSPoint)mouseLocation {
    iTermDirectoryEntry *entry = filteredEntries_[row];
    return entry.path;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    iTermDirectoryEntry *entry = filteredEntries_[rowIndex];
    NSString *abbreviatedName = entry.path;
    NSFont *font = [[aTableColumn dataCell] font];
    NSMutableArray *components = [[[abbreviatedName componentsSeparatedByString:@"/"] mutableCopy] autorelease];
    NSUInteger index;
    index = [components indexOfObject:@""];
    while (index != NSNotFound) {
        [components removeObjectAtIndex:index];
        index = [components indexOfObject:@""];
    }
    NSDictionary *attributes = @{ NSFontAttributeName: font };
    for (int i = 0;
         i + 1 < components.count && [abbreviatedName sizeWithAttributes:attributes].width > aTableColumn.width;
         i++) {
        if (i < components.count && [components[i] length] > 0) {
            components[i] = [components[i] substringWithRange:NSMakeRange(0, 1)];
        }
        abbreviatedName = [@"/" stringByAppendingString:[components componentsJoinedByString:@"/"]];
    }
    if (entry.starred) {
        abbreviatedName = [NSString stringWithFormat:@"★ %@", abbreviatedName];
    }

    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    attributes = @{ NSParagraphStyleAttributeName: style };
    return [[[NSAttributedString alloc] initWithString:abbreviatedName
                                            attributes:attributes] autorelease];
}

- (void)directoriesDidChange:(id)sender {
    [self updateDirectories];
}

- (void)updateDirectories {
    [entries_ autorelease];
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    VT100RemoteHost *host = [[wrapper.term currentSession] currentHost];
    NSArray *entries = [[iTermDirectoriesModel sharedInstance] entriesSortedByScoreOnHost:host];
    NSArray *reversed = [[entries reverseObjectEnumerator] allObjects];
    entries_ = [reversed retain];
    [tableView_ reloadData];

    [self computeFilteredEntries];
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
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    [[[wrapper.term currentSession] textview] updateCursor:[[NSApplication sharedApplication] currentEvent]];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    iTermDirectoryEntry* entry = filteredEntries_[selectedIndex];
    ToolWrapper *wrapper = (ToolWrapper *)[[self superview] superview];
    NSString *text = [@"cd " stringByAppendingString:entry.path];
    [[wrapper.term currentSession] insertText:text];
}

- (void)clear:(id)sender {
    if (NSRunAlertPanel(@"Erase Saved Directories",
                        @"Saved directories for all hosts will be erased. Continue?",
                        @"OK",
                        @"Cancel",
                        nil) == NSAlertDefaultReturn) {
        [[iTermDirectoriesModel sharedInstance] eraseHistory];
    }
}

- (void)computeFilteredEntries {
    [filteredEntries_ release];
    if (searchField_.stringValue.length == 0) {
        filteredEntries_ = [entries_ retain];
    } else {
        NSMutableArray *array = [NSMutableArray array];
        for (iTermDirectoryEntry *entry in entries_) {
            if ([entry.path rangeOfString:searchField_.stringValue].location != NSNotFound) {
                [array addObject:entry];
            }
        }
        filteredEntries_ = [array retain];
    }
    [tableView_ reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self computeFilteredEntries];
}

- (CGFloat)minimumHeight {
    return 88;
}

@end
