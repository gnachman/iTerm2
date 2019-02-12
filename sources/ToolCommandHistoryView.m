//
//  ToolCommandHistoryView.m
//  iTerm
//
//  Created by George Nachman on 1/15/14.
//
//

#import "ToolCommandHistoryView.h"

#import "iTermShellHistoryController.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermCompetentTableRowView.h"
#import "iTermSearchField.h"
#import "NSDateFormatterExtras.h"
#import "NSDate+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PTYSession.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 5;
static const CGFloat kHelpMargin = 5;

@interface ToolCommandHistoryView() <NSSearchFieldDelegate>
@end

@implementation ToolCommandHistoryView {
    NSScrollView *scrollView_;
    NSTableView *tableView_;
    NSButton *clear_;
    BOOL shutdown_;
    NSArray<iTermCommandHistoryCommandUseMO *> *filteredEntries_;
    iTermSearchField *searchField_;
    NSFont *boldFont_;
    NSButton *help_;
    NSMutableParagraphStyle *_paragraphStyle;
}

@synthesize tableView = tableView_;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

        searchField_ = [[iTermSearchField alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 1)];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        ITERM_IGNORE_PARTIAL_BEGIN
        [searchField_ setDelegate:self];
        ITERM_IGNORE_PARTIAL_END
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

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        [clear_ setButtonType:NSMomentaryPushInButton];
        [clear_ setTitle:@"Clear All"];
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setBezelStyle:NSSmallSquareBezelStyle];
        [clear_ sizeToFit];
        [clear_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:clear_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                     searchField_.frame.size.height + kMargin,
                                                                     frame.size.width,
                                                                     frame.size.height - kButtonHeight - 2 * kMargin - searchField_.frame.size.height)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        [scrollView_ setBorderType:NSBezelBorder];
        NSSize contentSize = [self contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        if (@available(macOS 10.14, *)) { } else {
            scrollView_.drawsBackground = NO;
        }
        
        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"commands"];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Commands"];
        [tableView_ setHeaderView:nil];
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        tableView_.intercellSpacing = NSMakeSize(tableView_.intercellSpacing.width, 0);
        tableView_.rowHeight = 15;
        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        [searchField_ setArrowHandler:tableView_];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        // Save the bold version of the table's default font
        boldFont_ = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];

        [self relayout];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(commandHistoryDidChange:)
                                                     name:kCommandHistoryDidChangeNotificationName
                                                   object:nil];
        // It doesn't seem to scroll far enough unless you use a delayed perform.
        [tableView_ performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
    }
    return self;
}

- (void)shutdown
{
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSSize)contentSize
{
    NSSize size = [scrollView_ contentSize];
    size.height = [[tableView_ headerView] frame].size.height;
    size.height += [tableView_ numberOfRows] * ([tableView_ rowHeight] + [tableView_ intercellSpacing].height);
    return size;
}

- (void)relayout
{
    NSRect frame = self.frame;
    help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                             frame.size.height - help_.frame.size.height - ceil((clear_.frame.size.height - help_.frame.size.height) / 2) + 2,
                             help_.frame.size.width,
                             help_.frame.size.height);
    searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
    [clear_ setFrame:NSMakeRect(0,
                                frame.size.height - kButtonHeight,
                                frame.size.width - help_.frame.size.width - kHelpMargin,
                                kButtonHeight)];
    scrollView_.frame = NSMakeRect(0,
                                   searchField_.frame.size.height + kMargin,
                                   frame.size.width,
                                   frame.size.height - kButtonHeight - 2 * kMargin - searchField_.frame.size.height);
    NSSize contentSize = [self contentSize];
    [tableView_ setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return filteredEntries_.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolCommandHistoryViewEntry";
    NSTextField *result = [tableView makeViewWithIdentifier:identifier owner:self];
    if (result == nil) {
        result = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
    }

    id value = [self stringOrAttributedStringForColumn:tableColumn row:row];
    if ([value isKindOfClass:[NSAttributedString class]]) {
        result.attributedStringValue = value;
        result.toolTip = [value string];
    } else {
        result.stringValue = value;
        result.toolTip = value;
    }

    return result;
}

- (id)stringOrAttributedStringForColumn:(NSTableColumn *)aTableColumn
                                    row:(NSInteger)rowIndex {
    iTermCommandHistoryCommandUseMO *commandUse = filteredEntries_[rowIndex];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter compactDateDifferenceStringFromDate:
                   [NSDate dateWithTimeIntervalSinceReferenceDate:commandUse.time.doubleValue]];
    } else {
        // Contents
        NSString *value = [commandUse.command stringByReplacingOccurrencesOfString:@"\n"
                                                                        withString:@" "];

        if (commandUse.code.integerValue) {
            if ([NSDate isAprilFools]) {
                value = [@"💩 " stringByAppendingString:value];
            } else {
                value = [@"🚫 " stringByAppendingString:value];
            }
        }

        iTermToolWrapper *wrapper = self.toolWrapper;
        if (commandUse.mark &&
            [wrapper.delegate.delegate toolbeltCurrentSessionHasGuid:commandUse.mark.sessionGuid]) {
            return [[NSAttributedString alloc] initWithString:value
                                                   attributes:@{ NSFontAttributeName: boldFont_,
                                                                 NSParagraphStyleAttributeName: _paragraphStyle }];
        } else {
            return [[NSAttributedString alloc] initWithString:value
                                                   attributes:@{ NSParagraphStyleAttributeName: _paragraphStyle }];
        }
    }
}

- (iTermCommandHistoryCommandUseMO *)selectedCommandUse {
    NSInteger row = [tableView_ selectedRow];
    if (row != -1) {
        return filteredEntries_[row];
    } else {
        return nil;
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    iTermCommandHistoryCommandUseMO *commandUse = [self selectedCommandUse];

    if (commandUse.mark) {
        iTermToolWrapper *wrapper = self.toolWrapper;
        // Post a notification in case the captured output tool is observing us.
        [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionCapturedOutputDidChange
                                                            object:nil];
        [wrapper.delegate.delegate toolbeltDidSelectMark:commandUse.mark];
    }
}

- (void)commandHistoryDidChange:(id)sender {
    [self updateCommands];
}

- (void)removeSelection {
    [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
}

- (void)updateCommands {
    [self computeFilteredEntries];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[tableView_ window] firstResponder];
    if (firstResponder != tableView_) {
        [tableView_ scrollToEndOfDocument:nil];
    }
}

- (void)fixCursor
{
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
    iTermCommandHistoryCommandUseMO *commandUse = filteredEntries_[selectedIndex];
    iTermToolWrapper *wrapper = self.toolWrapper;
    NSString *text = commandUse.command;
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption)) {
        if (commandUse.directory) {
            text = [@"cd " stringByAppendingString:commandUse.directory];
        } else {
            return;
        }
    }
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagShift)) {
        text = [text stringByAppendingString:@"\n"];
    }
    [wrapper.delegate.delegate toolbeltInsertText:text];
}

- (void)clear:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Erase Command History";
    alert.informativeText = @"Command history for all hosts will be erased. Continue?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[iTermShellHistoryController sharedInstance] eraseCommandHistory:YES directories:NO];
    }
}

- (void)computeFilteredEntries {
    NSArray<iTermCommandHistoryCommandUseMO *> *entries =
        [self.toolWrapper.delegate.delegate toolbeltCommandUsesForCurrentSession];
    if (searchField_.stringValue.length == 0) {
        filteredEntries_ = entries;
    } else {
        NSMutableArray<iTermCommandHistoryCommandUseMO *> *array = [NSMutableArray array];
        for (iTermCommandHistoryCommandUseMO *entry in entries) {
            if ([entry.command rangeOfString:searchField_.stringValue].location != NSNotFound) {
                [array addObject:entry];
            }
        }
        filteredEntries_ = array;
    }
    [tableView_ reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    [self computeFilteredEntries];
}

- (NSArray *)control:(NSControl *)control
            textView:(NSTextView *)textView
         completions:(NSArray *)words
 forPartialWordRange:(NSRange)charRange
 indexOfSelectedItem:(NSInteger *)index {
    return @[];
}

- (CGFloat)minimumHeight
{
    return 88;
}

- (void)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iterm2.com/shell_integration.html"]];
}

@end
