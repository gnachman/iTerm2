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
#import "iTermToolWrapper.h"
#import "NSDateFormatterExtras.h"
#import "NSTableColumn+iTerm.h"
#import "PTYSession.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 5;
static const CGFloat kHelpMargin = 5;

@interface ToolDirectoriesView() <NSSearchFieldDelegate>
@end

@implementation ToolDirectoriesView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    BOOL shutdown_;
    NSArray *entries_;
    NSArray *filteredEntries_;
    iTermSearchField *searchField_;
    NSFont *boldFont_;
    NSMenu *menu_;
    NSButton *help_;
}

@synthesize tableView = tableView_;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        searchField_ = [[iTermSearchField alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 1)];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        [searchField_ setDelegate:self];
        [self addSubview:searchField_];

        help_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
        [help_ setBezelStyle:NSHelpButtonBezelStyle];
        [help_ setButtonType:NSMomentaryPushInButton];
        [help_ setBordered:YES];
        [help_ sizeToFit];
        help_.target = self;
        help_.action = @selector(help:);
        help_.title = @"";
        [help_ setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
        [self addSubview:help_];

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
        [clear_ setButtonType:NSMomentaryPushInButton];
        [clear_ setTitle:@"Clear All"];
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setBezelStyle:NSSmallSquareBezelStyle];
        [clear_ sizeToFit];
        [clear_ setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
        [self addSubview:clear_];
        [clear_ release];

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [scrollView_ setBorderType:NSBezelBorder];

        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
        NSTableColumn *col;
        col = [[[NSTableColumn alloc] initWithIdentifier:@"directories"] autorelease];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Directories"];
        NSFont *theFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        [[col dataCell] setFont:theFont];
        tableView_.rowHeight = col.suggestedRowHeight;
        [tableView_ setHeaderView:nil];
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        [searchField_ setArrowHandler:tableView_];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        tableView_.menu = [[[NSMenu alloc] init] autorelease];
        tableView_.menu.delegate = self;
        NSMenuItem *item;
        item = [[NSMenuItem alloc] initWithTitle:@"Toggle Star"
                                          action:@selector(toggleStar:)
                                   keyEquivalent:@""];
        [tableView_.menu addItem:item];

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
    help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                             frame.size.height - help_.frame.size.height - ceil((clear_.frame.size.height - help_.frame.size.height) / 2) + 2,
                             help_.frame.size.width,
                             help_.frame.size.height);
    [clear_ setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width - help_.frame.size.width - kHelpMargin, kButtonHeight)];
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

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    iTermDirectoryEntry *entry = filteredEntries_[rowIndex];
    return [entry attributedStringForTableColumn:aTableColumn];
}

- (void)directoriesDidChange:(id)sender {
    [self updateDirectories];
}

- (void)updateDirectories {
    [entries_ autorelease];
    iTermToolWrapper *wrapper = self.toolWrapper;
    VT100RemoteHost *host = [wrapper.delegate.delegate toolbeltCurrentHost];
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
    iTermToolWrapper *wrapper = self.toolWrapper;
    [wrapper.delegate.delegate toolbeltUpdateMouseCursor];
}

- (void)doubleClickOnTableView:(id)sender {
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    iTermDirectoryEntry* entry = filteredEntries_[selectedIndex];
    iTermToolWrapper *wrapper = self.toolWrapper;
    NSString *text;
    if ([NSEvent modifierFlags] & NSAlternateKeyMask) {
        text = [@"cd " stringByAppendingString:entry.path];
    } else {
        text = entry.path;
    }
    [wrapper.delegate.delegate toolbeltInsertText:text];
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
            if ([entry.path rangeOfString:searchField_.stringValue
                                  options:NSCaseInsensitiveSearch].location != NSNotFound) {
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

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  return [self respondsToSelector:[item action]] && [tableView_ clickedRow] >= 0;
}

- (void)toggleStar:(id)sender {
    NSInteger index = [tableView_ clickedRow];
    if (index >= 0) {
        iTermDirectoryEntry *entry = filteredEntries_[index];
        entry.starred = !entry.starred;
        [[iTermDirectoriesModel sharedInstance] save];
    }
    [self updateDirectories];
}

- (void)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iterm2.com/shell_integration.html"]];
}

@end
