//
//  ToolCommandHistoryView.m
//  iTerm
//
//  Created by George Nachman on 1/15/14.
//
//

#import "ToolCommandHistoryView.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

#import "iTermApplication.h"
#import "iTerm2SharedARC-Swift.h"
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
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PTYSession.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 5;

@interface ToolCommandHistoryView() <NSSearchFieldDelegate>
@end

@implementation ToolCommandHistoryView {
    NSScrollView *_scrollView;
    NSTableView *_tableView;
    NSButton *clear_;
    BOOL shutdown_;
    NSArray<iTermCommandHistoryCommandUseMO *> *filteredEntries_;
    iTermSearchField *searchField_;
    NSFont *boldFont_;
    NSButton *help_;
    NSMutableParagraphStyle *_paragraphStyle;
}

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
        help_.controlSize = NSControlSizeSmall;
        [help_ sizeToFit];
        help_.target = self;
        help_.action = @selector(help:);
        help_.title = @"";
        [help_ setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
        [self addSubview:help_];

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        clear_.bezelStyle = NSBezelStyleRegularSquare;
        clear_.bordered = NO;
        clear_.image = [NSImage it_imageForSymbolName:SFSymbolGetString(SFSymbolTrash) accessibilityDescription:ITLocalize(@"TOOL_COMMAND_HISTORY_CLEAR", @"Clear", @"Button that clears command history")];
        clear_.imagePosition = NSImageOnly;
        clear_.frame = NSMakeRect(0, 0, 22, 22);
        [clear_ setTarget:self];
        [clear_ setAction:@selector(clear:)];
        [clear_ setAutoresizingMask:NSViewMinYMargin];
        [self addSubview:clear_];

        _scrollView = [NSScrollView scrollViewWithTableViewForToolbeltWithContainer:self
                                                                             insets:NSEdgeInsetsMake(searchField_.frame.size.height + kMargin,
                                                                                                     0,
                                                                                                     kButtonHeight + 2 * kMargin + searchField_.frame.size.height,
                                                                                                     0)
                                                                          rowHeight:[NSTableView heightForTextCellUsingFont:[NSFont it_toolbeltFont]]
                                                                  keyboardNavigable:NO];
        _tableView = _scrollView.documentView;
        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
        [searchField_ setArrowHandler:_tableView];

        // Save the bold version of the table's default font
        boldFont_ = [[NSFontManager sharedFontManager] convertFont:[NSFont it_toolbeltFont] toHaveTrait:NSFontBoldTrait];

        [self relayout];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(commandHistoryDidChange:)
                                                     name:kCommandHistoryDidChangeNotificationName
                                                   object:nil];
        // It doesn't seem to scroll far enough unless you use a delayed perform.
        [_tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
    }
    return self;
}

+ (ProfileType)supportedProfileTypes {
    return ProfileTypeTerminal;
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
    NSRect frame = self.frame;

    // Search field
    NSRect searchFieldFrame = NSMakeRect(0,
                                         0,
                                         frame.size.width - help_.frame.size.width - clear_.frame.size.width - 2 * kMargin,
                                         searchField_.frame.size.height);
    searchField_.frame = searchFieldFrame;

    // Help button
    {
        CGFloat fudgeFactor = 2;
        help_.frame = NSMakeRect(frame.size.width - help_.frame.size.width,
                                 fudgeFactor,
                                 help_.frame.size.width,
                                 help_.frame.size.height);
    }

    // Clear button
    {
        CGFloat fudgeFactor = 0;
        clear_.frame = NSMakeRect(help_.frame.origin.x - clear_.frame.size.width - kMargin,
                                        fudgeFactor,
                                  clear_.frame.size.width,
                                  clear_.frame.size.height);
    }
    
    // Scroll view
    const CGFloat searchFieldY = searchFieldFrame.size.height + kMargin;
    [_scrollView setFrame:NSMakeRect(0,
                                     searchFieldY,
                                     frame.size.width,
                                     NSHeight(self.bounds) - searchFieldY - 2 * kMargin)];

    // Table view
    NSSize contentSize = [_scrollView contentSize];
    NSTableColumn *column = _tableView.tableColumns[0];
    CGFloat fudgeFactor = 32;
    // When the tool is first constructed during new-window creation the toolbelt can have zero
    // width, making contentSize.width - fudgeFactor negative. Pinning min/maxWidth to that poisons
    // the column (maxWidth clamps to 0), and later relayouts at the real width can't recover because
    // minWidth gets clamped back down to maxWidth. That leaves freshly reloaded cells at zero width
    // so their text is invisible until a manual resize. Only pin the column when the width is sane.
    const CGFloat targetWidth = contentSize.width - fudgeFactor;
    if (targetWidth > 0) {
        // Raise the ceiling before the floor so a previously-poisoned maxWidth can't clamp minWidth.
        column.maxWidth = targetWidth;
        column.minWidth = targetWidth;
        [_tableView sizeToFit];
    }
    [_tableView reloadData];
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return filteredEntries_.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    static NSString *const identifier = @"ToolCommandHistoryViewEntry";
    id value = [self stringOrAttributedStringForColumn:tableColumn row:row];
    return [tableView newTableCellViewWithTextFieldUsingIdentifier:identifier
                                                              font:[NSFont it_toolbeltFont]
                                                             value:value];
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
    NSInteger row = [_tableView selectedRow];
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
    [pbItem setString:commandUse.command forType:UTTypeUTF8PlainText.identifier];
    return pbItem;
}

- (void)commandHistoryDidChange:(id)sender {
    [self updateCommands];
}

- (void)removeSelection {
    [_tableView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
}

- (void)updateCommands {
    [self computeFilteredEntries];
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];

    NSResponder *firstResponder = [[_tableView window] firstResponder];
    if (firstResponder != _tableView) {
        [_tableView scrollToEndOfDocument:nil];
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
    NSInteger selectedIndex = [_tableView selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    iTermCommandHistoryCommandUseMO *commandUse = filteredEntries_[selectedIndex];
    iTermToolWrapper *wrapper = self.toolWrapper;
    NSString *text = commandUse.command;
    if (([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagOption)) {
        if (commandUse.directory) {
            text = [@"cd " stringByAppendingString:commandUse.directory];
        } else {
            return;
        }
    }
    if (([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagShift)) {
        text = [text stringByAppendingString:@"\n"];
    }
    [wrapper.delegate.delegate toolbeltInsertText:text];
}

- (void)clear:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = ITLocalize(@"ToolCommandHistoryView_EraseCommandHistory", @"Erase Command History", @"Alert title in clear:");
    alert.informativeText = ITLocalize(@"ToolCommandHistoryView_CommandHistoryForAllHostsWillBe", @"Command history for all hosts will be erased. Continue?", @"Alert explanatory text in clear:");
    [alert addButtonWithTitle:ITLocalize(@"COMMON_OK", @"OK", @"Button title in clear:")];
    [alert addButtonWithTitle:ITLocalize(@"COMMON_CANCEL", @"Cancel", @"Button title in clear:")];
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
    [_tableView reloadData];
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
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"http://iterm2.com/shell_integration.html"]
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.window];
}

@end
