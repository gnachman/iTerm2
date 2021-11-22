//
//  ToolDirectoriesView.m
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import "ToolDirectoriesView.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermCompetentTableRowView.h"
#import "iTermRecentDirectoryMO.h"
#import "iTermRecentDirectoryMO+Additions.h"
#import "iTermSearchField.h"
#import "iTermShellHistoryController.h"
#import "iTermToolWrapper.h"
#import "NSDateFormatterExtras.h"
#import "NSEvent+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 5;
static const CGFloat kHelpMargin = 5;

@interface ToolDirectoriesView() <NSSearchFieldDelegate>
@end

@implementation ToolDirectoriesView {
    NSScrollView *_scrollView;
    NSTableView *_tableView;
    NSButton *clear_;
    BOOL shutdown_;
    NSArray<iTermRecentDirectoryMO *> *entries_;
    NSArray<iTermRecentDirectoryMO *> *filteredEntries_;
    iTermSearchField *searchField_;
    NSFont *boldFont_;
    NSMenu *menu_;
    NSButton *help_;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        searchField_ = [[iTermSearchField alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 1)];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        [searchField_ setDelegate:self];
        [self addSubview:searchField_];

        help_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
        [help_ setBezelStyle:NSBezelStyleHelpButton];
        [help_ setButtonType:NSButtonTypeMomentaryPushIn];
        [help_ setBordered:YES];
        if (@available(macOS 10.16, *)) {
            help_.controlSize = NSControlSizeSmall;
        }
        [help_ sizeToFit];
        help_.target = self;
        help_.action = @selector(help:);
        help_.title = @"";
        [help_ setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
        [self addSubview:help_];

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
        if (@available(macOS 10.16, *)) {
            clear_.bezelStyle = NSBezelStyleRegularSquare;
            clear_.bordered = NO;
            clear_.image = [NSImage it_imageForSymbolName:@"trash" accessibilityDescription:@"Clear"];
            clear_.imagePosition = NSImageOnly;
            clear_.frame = NSMakeRect(0, 0, 22, 22);
        } else {
            [clear_ setButtonType:NSButtonTypeMomentaryPushIn];
            [clear_ setTitle:@"Clear All"];
            [clear_ setBezelStyle:NSBezelStyleSmallSquare];
            [clear_ sizeToFit];
        }
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
        [self addSubview:clear_];

        _scrollView = [NSScrollView scrollViewWithTableViewForToolbeltWithContainer:self
                                                                             insets:NSEdgeInsetsZero];
        _tableView = _scrollView.documentView;
        NSCell *dataCell = _tableView.tableColumns[0].dataCell;
        dataCell.font = [NSFont it_toolbeltFont];
        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
        [searchField_ setArrowHandler:_tableView];

        _tableView.menu = [[NSMenu alloc] init];
        _tableView.menu.delegate = self;
        NSMenuItem *item;
        item = [[NSMenuItem alloc] initWithTitle:@"Toggle Star"
                                          action:@selector(toggleStar:)
                                   keyEquivalent:@""];
        [_tableView.menu addItem:item];

        boldFont_ = [[NSFontManager sharedFontManager] convertFont:[NSFont it_toolbeltFont] toHaveTrait:NSFontBoldTrait];

        [self relayout];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(directoriesDidChange:)
                                                     name:kDirectoriesDidChangeNotificationName
                                                   object:nil];
        [self performSelector:@selector(updateDirectories) withObject:nil afterDelay:0];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowAppearanceDidChange:)
                                                     name:iTermWindowAppearanceDidChange
                                                   object:nil];
    }
    return self;
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSize)contentSize {
    NSSize size = [_scrollView contentSize];
    size.height = _tableView.intrinsicContentSize.height;
    return size;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self relayout];
}

- (void)relayout {
    if (@available(macOS 10.16, *)) {
        [self relayout_bigSur];
    } else {
        [self relayout_legacy];
    }
}

- (void)relayout_bigSur {
    NSRect frame = self.frame;

    // Search field
    NSRect searchFieldFrame = NSMakeRect(0,
                                         0,
                                         frame.size.width - help_.frame.size.width - clear_.frame.size.width - 2 * kMargin,
                                         searchField_.frame.size.height);
    searchField_.frame = searchFieldFrame;

    // Help button
    {
        CGFloat fudgeFactor = 1;
        if (@available(macOS 10.16, *)) {
            fudgeFactor = 2;
        }
        help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                                 fudgeFactor,
                                 help_.frame.size.width,
                                 help_.frame.size.height);
    }

    // Clear button
    {
        CGFloat fudgeFactor = 1;
        if (@available(macOS 10.16, *)) {
            fudgeFactor = 0;
        }
        clear_.frame = NSMakeRect(help_.frame.origin.x - clear_.frame.size.width - kMargin,
                                  fudgeFactor,
                                  clear_.frame.size.width,
                                  clear_.frame.size.height);
    }
    
    // Scroll view
    [_scrollView setFrame:NSMakeRect(0,
                                     searchFieldFrame.size.height + kMargin,
                                     frame.size.width,
                                     frame.size.height - searchFieldFrame.size.height - 2 * kMargin)];

    // Table view
    NSSize contentSize = [_scrollView contentSize];
    NSTableColumn *column = _tableView.tableColumns[0];
    CGFloat fudgeFactor = 0;
    if (@available(macOS 10.16, *)) {
        fudgeFactor = 32;
    }
    column.minWidth = contentSize.width - fudgeFactor;
    column.maxWidth = contentSize.width - fudgeFactor;
    [_tableView sizeToFit];
    [_tableView reloadData];
}

- (void)relayout_legacy {
    NSRect frame = self.frame;
    searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
    help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                             frame.size.height - help_.frame.size.height - ceil((clear_.frame.size.height - help_.frame.size.height) / 2) + 2,
                             help_.frame.size.width,
                             help_.frame.size.height);
    [clear_ setFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width - help_.frame.size.width - kHelpMargin, kButtonHeight)];
    _scrollView.frame = NSMakeRect(0,
                                   searchField_.frame.size.height + kMargin,
                                   frame.size.width,
                                   frame.size.height - kButtonHeight - 2 * kMargin - searchField_.frame.size.height);
    NSSize contentSize = [self contentSize];
    [_tableView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return filteredEntries_.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolDirectoriesViewEntry";
    id value = [self stringOrAttributedStringForColumn:tableColumn row:row];
    iTermRecentDirectoryMO *entry = filteredEntries_[row];
    NSTableCellView *cell = [tableView newTableCellViewWithTextFieldUsingIdentifier:identifier
                                                                               font:[NSFont it_toolbeltFont]
                                                                              value:value];
    NSString *tooltip = entry.path;
    cell.toolTip = tooltip;

    return cell;
}

- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    iTermRecentDirectoryMO *entry = filteredEntries_[row];
    [pbItem setString:entry.path forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
}

- (id)stringOrAttributedStringForColumn:(NSTableColumn *)aTableColumn
                                    row:(NSInteger)rowIndex {
    iTermRecentDirectoryMO *entry = filteredEntries_[rowIndex];
    NSIndexSet *indexes =
        [[iTermShellHistoryController sharedInstance] abbreviationSafeIndexesInRecentDirectory:entry];
    return [entry attributedStringForTableColumn:aTableColumn
                      abbreviationSafeComponents:indexes];
}

- (void)directoriesDidChange:(id)sender {
    [self updateDirectories];
}

- (void)updateDirectories {
    entries_ = nil;
    iTermToolWrapper *wrapper = self.toolWrapper;
    VT100RemoteHost *host = [wrapper.delegate.delegate toolbeltCurrentHost];
    NSArray<iTermRecentDirectoryMO *> *entries =
        [[iTermShellHistoryController sharedInstance] directoriesSortedByScoreOnHost:host];
    NSArray<iTermRecentDirectoryMO *> *reversed = [[entries reverseObjectEnumerator] allObjects];
    entries_ = reversed;
    [_tableView reloadData];

    [self computeFilteredEntries];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[_tableView window] firstResponder];
    if (firstResponder != _tableView) {
        [_tableView scrollToEndOfDocument:nil];
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
    NSInteger selectedIndex = [_tableView selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    iTermRecentDirectoryMO *entry = filteredEntries_[selectedIndex];
    iTermToolWrapper *wrapper = self.toolWrapper;
    NSString *text;
    NSString *escapedPath = [entry.path stringWithEscapedShellCharactersIncludingNewlines:YES];
    if ([NSEvent modifierFlags] & NSEventModifierFlagOption) {
        text = [@"cd " stringByAppendingString:escapedPath];
    } else {
        text = escapedPath;
    }
    if (([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagShift)) {
        text = [text stringByAppendingString:@"\n"];
    }
    [wrapper.delegate.delegate toolbeltInsertText:text];
}

- (void)clear:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Erase Saved Directories?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[iTermShellHistoryController sharedInstance] eraseCommandHistory:NO directories:YES];
    }
}

- (void)computeFilteredEntries {
    filteredEntries_ = nil;
    if (searchField_.stringValue.length == 0) {
        filteredEntries_ = entries_;
    } else {
        NSMutableArray *array = [NSMutableArray array];
        for (iTermRecentDirectoryMO *entry in entries_) {
            if ([entry.path rangeOfString:searchField_.stringValue
                                  options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [array addObject:entry];
            }
        }
        filteredEntries_ = array;
    }
    [_tableView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self computeFilteredEntries];
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    return @[];
}

- (CGFloat)minimumHeight {
    return 88;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  return [self respondsToSelector:[item action]] && [_tableView clickedRow] >= 0;
}

- (void)toggleStar:(id)sender {
    NSInteger index = [_tableView clickedRow];
    if (index >= 0) {
        iTermRecentDirectoryMO *entry = filteredEntries_[index];
        [[iTermShellHistoryController sharedInstance] setDirectory:entry
                                                           starred:!entry.starred.boolValue];
    }
    [self updateDirectories];
}

- (void)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/shell_integration.html"]];
}

- (void)updateAppearance {
    if (!self.window) {
        return;
    }
    _tableView.appearance = self.window.appearance;
}

- (void)viewDidMoveToWindow {
    [self updateAppearance];
}

- (void)windowAppearanceDidChange:(NSNotification *)notification {
    [self updateAppearance];
}


@end
