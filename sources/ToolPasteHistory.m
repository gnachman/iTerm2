//
//  ToolPasteHistory.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//

#import "ToolPasteHistory.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCompetentTableRowView.h"
#import "iTermController.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermToolWrapper.h"
#import "NSDateFormatterExtras.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"

static const CGFloat kButtonHeight = 23;
static const CGFloat kMargin = 4;

@implementation ToolPasteHistory {
    NSScrollView *_scrollView;
    NSTableView *_tableView;
    NSButton *clear_;
    NSTextField *_secureKeyboardEntryWarning;
    PasteboardHistory *pasteHistory_;
    NSTimer *minuteRefreshTimer_;
    BOOL shutdown_;
    NSMutableParagraphStyle *_paragraphStyle;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        _paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
        _paragraphStyle.allowsDefaultTighteningForTruncation = NO;

        clear_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, frame.size.height - kButtonHeight, frame.size.width, kButtonHeight)];
        if (@available(macOS 10.16, *)) {
            clear_.bezelStyle = NSBezelStyleRegularSquare;
            clear_.bordered = NO;
            clear_.image = [NSImage it_imageForSymbolName:@"trash" accessibilityDescription:@"Delete All"];
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

        _secureKeyboardEntryWarning = [NSTextField newLabelStyledTextField];
        _secureKeyboardEntryWarning.stringValue = @"⚠️ Secure keyboard entry disables paste history.";
        _secureKeyboardEntryWarning.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        _secureKeyboardEntryWarning.cell.truncatesLastVisibleLine = YES;
        _secureKeyboardEntryWarning.hidden = ![[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
        [self addSubview:_secureKeyboardEntryWarning];
        [_secureKeyboardEntryWarning sizeToFit];
        _secureKeyboardEntryWarning.frame = NSMakeRect(0, 0, frame.size.width, _secureKeyboardEntryWarning.frame.size.height);

        _scrollView = [NSScrollView scrollViewWithTableViewForToolbeltWithContainer:self
                                                                             insets:NSEdgeInsetsMake(0, 0, 0, kButtonHeight + kMargin)];
        _tableView = _scrollView.documentView;
        [_tableView setDoubleAction:@selector(doubleClickOnTableView:)];
        [self relayout];
        pasteHistory_ = [PasteboardHistory sharedInstance];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardHistoryDidChange:)
                                                     name:kPasteboardHistoryDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(secureKeyboardEntryDidChange:)
                                                     name:iTermDidToggleSecureInputNotification
                                                   object:nil];
        minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                               target:self
                                                             selector:@selector(pasteboardHistoryDidChange:)
                                                             userInfo:nil
                                                              repeats:YES];
        [_tableView performSelector:@selector(scrollToEndOfDocument:) withObject:nil afterDelay:0];
        [_tableView reloadData];
    }
    return self;
}

- (void)dealloc {
    [minuteRefreshTimer_ invalidate];
}

- (void)shutdown {
    shutdown_ = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [minuteRefreshTimer_ invalidate];
    minuteRefreshTimer_ = nil;
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
    if (@available(macOS 10.16, *)){
        clear_.frame = NSMakeRect(frame.size.width - clear_.frame.size.width,
                                  frame.size.height - clear_.frame.size.height,
                                  clear_.frame.size.width,
                                  clear_.frame.size.height);
    } else {
        [clear_ sizeToFit];
        [clear_ setFrame:NSMakeRect(frame.size.width - clear_.frame.size.width, frame.size.height - kButtonHeight, clear_.frame.size.width, kButtonHeight)];
    }

    _secureKeyboardEntryWarning.hidden = [iTermAdvancedSettingsModel saveToPasteHistoryWhenSecureInputEnabled] || ![[iTermSecureKeyboardEntryController sharedInstance] isEnabled];
    _secureKeyboardEntryWarning.frame = NSMakeRect(0, 0, frame.size.width, _secureKeyboardEntryWarning.frame.size.height);

    const CGFloat offset = _secureKeyboardEntryWarning.isHidden ? 0 : _secureKeyboardEntryWarning.frame.size.height + 4;
    [_scrollView setFrame:NSMakeRect(0, offset, frame.size.width, frame.size.height - kButtonHeight - kMargin - offset)];

    NSSize contentSize = [self contentSize];
    [_tableView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (@available(macOS 10.16, *)) {
        return [[iTermBigSurTableRowView alloc] initWithFrame:NSZeroRect];
    }
    return [[iTermCompetentTableRowView alloc] initWithFrame:NSZeroRect];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return pasteHistory_.entries.count;
}


- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    return [tableView newTableCellViewWithTextFieldUsingIdentifier:@"iTermToolPasteHistory"
                                                  attributedString:[self attributedStringForTableColumn:tableColumn row:row]];
}

- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    PasteboardEntry* entry = pasteHistory_.entries[row];
    [pbItem setString:entry.mainValue forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
}

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    return [[NSAttributedString alloc] initWithString:[self stringForTableColumn:aTableColumn row:rowIndex]
                                           attributes:@{NSFontAttributeName: [NSFont it_toolbeltFont],
                                                        NSParagraphStyleAttributeName: _paragraphStyle }];
}

- (NSString *)stringForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
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

- (void)secureKeyboardEntryDidChange:(NSNotification *)notification {
    [self relayout];
}

- (void)pasteboardHistoryDidChange:(id)sender {
    [self update];
}

- (void)update {
    [_tableView reloadData];
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
    PasteboardEntry* entry = pasteHistory_.entries[selectedIndex];
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
    [thePasteboard setString:[entry mainValue] forType:NSPasteboardTypeString];
    PTYTextView *textView = [[iTermController sharedInstance] frontTextView];
    [textView paste:nil];
    [textView.window makeFirstResponder:textView];
}

- (void)clear:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Erase Paste History";
    alert.informativeText = @"Paste history will be erased. Continue?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [pasteHistory_ eraseHistory];
        [pasteHistory_ clear];
        [_tableView reloadData];
    }
    // Updating the table data causes the cursor to change into an arrow!
    [self performSelector:@selector(fixCursor) withObject:nil afterDelay:0];
}

- (CGFloat)minimumHeight {
    return 60;
}

@end
