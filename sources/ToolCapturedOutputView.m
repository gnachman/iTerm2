//
//  ToolCapturedOutput.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "ToolCapturedOutputView.h"

#import "iTerm2SharedARC-Swift.h"
#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermSearchField.h"
#import "iTermToolbeltView.h"
#import "iTermToolWrapper.h"
#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "ToolCommandHistoryView.h"

static const CGFloat kMargin = 4;
static const CGFloat kButtonHeight = 23;
static NSString *const iTermCapturedOutputToolTableViewCellIdentifier = @"ToolCapturedOutputEntryIdentifier";

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
    NSTableCellView *_measuringCellView;
    id<VT100ScreenMarkReading> mark_;  // Mark from which captured output came
    NSInteger _clearCount;
    iTermSearchField *searchField_;
    NSButton *help_;
    NSButton *_clearButton;
    NSArray *filteredEntries_;
    BOOL _ignoreClick;
    NSString *_clearedMark;
    long long _clearedAbsLineNumber;
}

@synthesize tableView = tableView_;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        help_ = [[NSButton alloc] initWithFrame:CGRectZero];
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
        [help_ setAutoresizingMask:NSViewMinXMargin];
        [self addSubview:help_];

        _clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        [_clearButton setTarget:self];
        [_clearButton setAction:@selector(clear:)];
        [_clearButton setAutoresizingMask:NSViewMinYMargin];
        if (@available(macOS 10.16, *)) {
            _clearButton.bezelStyle = NSBezelStyleRegularSquare;
            _clearButton.bordered = NO;
            _clearButton.image = [NSImage it_imageForSymbolName:@"trash" accessibilityDescription:@"Clear"];
            _clearButton.imagePosition = NSImageOnly;
            _clearButton.frame = NSMakeRect(0, 0, 22, 22);
        } else {
            [_clearButton setTitle:@"Clear"];
            [_clearButton setButtonType:NSButtonTypeMomentaryPushIn];
            [_clearButton setBezelStyle:NSBezelStyleSmallSquare];
            [_clearButton sizeToFit];
        }
        [self addSubview:_clearButton];

        searchField_ = [[iTermSearchField alloc] initWithFrame:CGRectZero];
        [searchField_ sizeToFit];
        searchField_.autoresizingMask = NSViewWidthSizable;
        searchField_.frame = NSMakeRect(0, 0, frame.size.width, searchField_.frame.size.height);
        ITERM_IGNORE_PARTIAL_BEGIN
        [searchField_ setDelegate:self];
        ITERM_IGNORE_PARTIAL_END
        [self addSubview:searchField_];

        scrollView_ = [NSScrollView scrollViewWithTableViewForToolbeltWithContainer:self
                                                                             insets:NSEdgeInsetsZero];
        tableView_ = scrollView_.documentView;
        if (@available(macOS 10.16, *)) { } else {
            NSSize spacing = tableView_.intercellSpacing;
            spacing.height += 5;
            tableView_.intercellSpacing = spacing;
        }

        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        tableView_.target = self;
        tableView_.action = @selector(didClick:);

        tableView_.menu = [[NSMenu alloc] init];
        tableView_.menu.delegate = self;
        tableView_.intercellSpacing = NSMakeSize(0, 2);
        NSMenuItem *item;
        item = [[NSMenuItem alloc] initWithTitle:@"Toggle Checkmark"
                                          action:@selector(toggleCheckmark:)
                                   keyEquivalent:@""];
        [tableView_.menu addItem:item];

        [searchField_ setArrowHandler:tableView_];

        [self relayout];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(capturedOutputDidChange:)
                                                     name:kPTYSessionCapturedOutputDidChange
                                                   object:nil];
        [self updateCapturedOutput];
    }
    return self;
}

- (void)removeSelection {
    mark_ = nil;
    [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
    [self updateCapturedOutput];
}

- (void)updateCapturedOutput {
    iTermToolWrapper *wrapper = self.toolWrapper;
    ToolCommandHistoryView *commandHistoryView = [wrapper.delegate commandHistoryView];
    iTermCommandHistoryCommandUseMO *commandUse = [commandHistoryView selectedCommandUse];
    id<VT100ScreenMarkReading> mark;
    NSArray *theArray;
    if (commandUse) {
        mark = commandUse.mark;
    } else {
        mark = [wrapper.delegate.delegate toolbeltLastCommandMark];
    }
    theArray = mark.capturedOutput;
    if ([_clearedMark isEqualToString:mark.guid]) {
        theArray = [theArray filteredArrayUsingBlock:^BOOL(id<CapturedOutputReading> co) {
            return co.absoluteLineNumber > _clearedAbsLineNumber;
        }];
    } else {
        _clearedMark = nil;
        _clearedAbsLineNumber = 0;
    }
    if (mark != mark_) {
        [tableView_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        mark_ = mark;
        _clearCount = mark.clearCount;
    } else if (mark.clearCount > _clearCount) {
        _clearCount = mark.clearCount;
        theArray = @[];
    }

    allCapturedOutput_ = [theArray copy];

    // Now update filtered entries based on search string.
    NSMutableArray *temp = [NSMutableArray array];
    for (CapturedOutput *capturedOutput in allCapturedOutput_) {
        if (!searchField_.stringValue.length ||
            [[self labelForCapturedOutput:capturedOutput] rangeOfString:searchField_.stringValue
                                                                options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [temp addObject:capturedOutput];
        }
    }
    filteredEntries_ = temp;

    [tableView_ reloadData];

    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
                                         frame.size.width - help_.frame.size.width - _clearButton.frame.size.width - 2 * kMargin,
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
        if (@available(macOS 10.15, *)) {
            fudgeFactor = 0;
        }
        _clearButton.frame = NSMakeRect(help_.frame.origin.x - _clearButton.frame.size.width - kMargin,
                                        fudgeFactor,
                                        _clearButton.frame.size.width,
                                        _clearButton.frame.size.height);
    }
    
    // Scroll view
    [scrollView_ setFrame:NSMakeRect(0,
                                     searchFieldFrame.size.height + kMargin,
                                     frame.size.width,
                                     frame.size.height - kMargin - (searchFieldFrame.size.height + kMargin))];

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

- (BOOL)isFlipped {
    return YES;
}

- (void)clear:(id)sender {
    _clearedAbsLineNumber = mark_.capturedOutput.lastObject.absoluteLineNumber;
    _clearedMark = mark_.guid;
    allCapturedOutput_ = [[NSMutableArray alloc] init];
    filteredEntries_ = [[NSMutableArray alloc] init];

    [tableView_ reloadData];

    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    _clearButton.enabled = (filteredEntries_.count > 0);
    return filteredEntries_.count;
}

- (NSTableCellView *)newCellViewWithString:(NSString *)string {
    NSTableCellView *cell = [tableView_ newTableCellViewWithTextFieldUsingIdentifier:iTermCapturedOutputToolTableViewCellIdentifier
                                                                                font:[NSFont it_toolbeltFont]
                                                                              string:string];
    NSTextField *textField = cell.textField;
    textField.maximumNumberOfLines = 0;
    textField.lineBreakMode = NSLineBreakByCharWrapping;
    textField.usesSingleLineMode = NO;
    textField.font = [NSFont it_toolbeltFont];
    return cell;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    CapturedOutput *capturedOutput = filteredEntries_[row];
    NSString *value = [self labelForCapturedOutput:capturedOutput];
    NSTableCellView *result = [self newCellViewWithString:value];
    result.textField.maximumNumberOfLines = 0;
    result.textField.lineBreakMode = NSLineBreakByCharWrapping;
    result.textField.toolTip = value;
    return result;
}

- (NSString *)labelForCapturedOutput:(CapturedOutput *)capturedOutput {
    NSString *label = capturedOutput.line;
    if (capturedOutput.state) {
        label = [@"✔" stringByAppendingString:label];
    } else {
        label = [@"-" stringByAppendingString:label];
    }
    return label;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)rowIndex {
    CapturedOutput *capturedOutput = filteredEntries_[rowIndex];
    NSString *label = [self labelForCapturedOutput:capturedOutput];
    if (!_measuringCellView) {
        _measuringCellView = [self newCellViewWithString:label];
    }
    // https://stackoverflow.com/a/42853810/321984
    [_measuringCellView.textField setStringValue:label];
    _measuringCellView.frame = NSMakeRect(0, 0, tableView_.frame.size.width, 0);
    _measuringCellView.needsLayout = YES;
    [_measuringCellView layoutSubtreeIfNeeded];
    NSSize naturalSize = [_measuringCellView fittingSize];
    return naturalSize.height;
}

- (NSCell *)tableView:(NSTableView *)tableView
        dataCellForTableColumn:(NSTableColumn *)tableColumn
                           row:(NSInteger)row {
    return [self cell];
}

- (NSCell *)cell {
    NSCell *cell = [[NSTextFieldCell alloc] init];
    [cell setEditable:NO];
    [cell setLineBreakMode:NSLineBreakByWordWrapping];
    [cell setWraps:YES];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    _ignoreClick = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_ignoreClick = NO;
    });
    [self revealSelection];
}

- (void)revealSelection {
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

- (void)didClick:(id)sender {
    if (_ignoreClick) {
        return;
    }
    [self revealSelection];
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
