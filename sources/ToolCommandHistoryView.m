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
#import "NSEvent+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
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
        _paragraphStyle.allowsDefaultTighteningForTruncation = NO;

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

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
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
        [clear_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:clear_];

        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                     searchField_.frame.size.height + kMargin,
                                                                     frame.size.width,
                                                                     frame.size.height - kButtonHeight - 2 * kMargin - searchField_.frame.size.height)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        if (@available(macOS 10.16, *)) {
            [scrollView_ setBorderType:NSLineBorder];
            scrollView_.scrollerStyle = NSScrollerStyleOverlay;
        } else {
            [scrollView_ setBorderType:NSBezelBorder];
        }
        NSSize contentSize = [self contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        scrollView_.drawsBackground = NO;

        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
#ifdef MAC_OS_X_VERSION_10_16
        if (@available(macOS 10.16, *)) {
            tableView_.style = NSTableViewStyleInset;
        }
#endif
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
        if (@available(macOS 10.14, *)) {
            tableView_.backgroundColor = [NSColor clearColor];
        }

        [searchField_ setArrowHandler:tableView_];

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];

        // Save the bold version of the table's default font
        boldFont_ = [[NSFontManager sharedFontManager] convertFont:[NSFont it_toolbeltFont] toHaveTrait:NSFontBoldTrait];

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
    const CGFloat searchFieldY = searchFieldFrame.size.height + kMargin;
    [scrollView_ setFrame:NSMakeRect(0,
                                     searchFieldY,
                                     frame.size.width,
                                     NSHeight(self.bounds) - searchFieldY - 2 * kMargin)];

    // Table view
    NSSize contentSize = [scrollView_ contentSize];
    NSTableColumn *column = tableView_.tableColumns[0];
    CGFloat fudgeFactor = 0;
    if (@available(macOS 10.16, *)) {
        fudgeFactor = 32;
    }
    column.minWidth = contentSize.width - fudgeFactor;
    column.maxWidth = contentSize.width - fudgeFactor;
    [tableView_ sizeToFit];
    [tableView_ reloadData];
}


- (void)relayout_legacy
{
    NSRect frame = self.frame;
    searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
    [clear_ setFrame:NSMakeRect(0,
                                frame.size.height - kButtonHeight,
                                frame.size.width - help_.frame.size.width - kHelpMargin,
                                kButtonHeight)];
    help_.frame = NSMakeRect(NSMaxX(clear_.frame) + kHelpMargin,
                             NSMinY(clear_.frame) + (NSHeight(clear_.frame) - NSHeight(help_.frame)) / 2.0 + 2,
                             NSWidth(help_.frame),
                             NSHeight(help_.frame)) ;
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
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
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
    result.font = [NSFont it_toolbeltFont];
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
                                                   attributes:@{NSFontAttributeName: [NSFont it_toolbeltFont],
                                                                NSParagraphStyleAttributeName: _paragraphStyle }];
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

- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    iTermCommandHistoryCommandUseMO *commandUse = filteredEntries_[row];
    [pbItem setString:commandUse.command forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
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
    if (([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagOption)) {
        if (commandUse.directory) {
            text = [@"cd " stringByAppendingString:commandUse.directory];
        } else {
            return;
        }
    }
    if (([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagShift)) {
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
