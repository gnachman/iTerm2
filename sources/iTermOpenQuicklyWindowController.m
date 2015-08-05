#import "iTermOpenQuicklyWindowController.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermOpenQuicklyItem.h"
#import "iTermOpenQuicklyModel.h"
#import "iTermOpenQuicklyTableCellView.h"
#import "iTermOpenQuicklyTableRowView.h"
#import "iTermOpenQuicklyTextField.h"
#import "NSColor+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "SolidColorView.h"
#import "VT100RemoteHost.h"

@interface iTermOpenQuicklyWindowController () <
    iTermOpenQuicklyTextFieldDelegate,
    iTermOpenQuicklyModelDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSWindowDelegate>

@property(nonatomic, retain) iTermOpenQuicklyModel *model;

@end

@implementation iTermOpenQuicklyWindowController {
    // Text field where quries are entered
    IBOutlet iTermOpenQuicklyTextField *_textField;

    // Table that shows search results
    IBOutlet NSTableView *_table;

    IBOutlet NSScrollView *_scrollView;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super initWithWindowNibName:@"iTermOpenQuicklyWindowController"];
    if (self) {
        _model = [[iTermOpenQuicklyModel alloc] init];
        _model.delegate = self;
    }
    return self;
}

- (void)dealloc {
    [_model release];
    [super dealloc];
}

- (void)awakeFromNib {
    // Initialize the table
    [_table setDoubleAction:@selector(doubleClick:)];
    _table.backgroundColor = [NSColor controlColor];

    // Initialize the window
    [self.window setOpaque:NO];
    self.window.alphaValue = 0.95;
    self.window.backgroundColor = [NSColor clearColor];

    // Initialize the window's contentView
    SolidColorView *contentView = [self.window contentView];
    contentView.color = [NSColor controlColor];

    // Rounded corners for contentView
    contentView.wantsLayer = YES;
    contentView.layer.cornerRadius = 6;
    contentView.layer.masksToBounds = YES;
    contentView.layer.borderColor = [[NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1] iterm_CGColor];
    contentView.layer.borderWidth = 1;
}

- (void)presentWindow {
    [_model removeAllItems];
    [_table reloadData];
    // Set the window's frame to be table-less initially.
    [self.window setFrame:[self frame] display:YES animate:NO];
    [_textField selectText:nil];
    [self.window makeKeyAndOrderFront:nil];

    // After the window is rendered, call update which will animate to the new frame.
    [self performSelector:@selector(update) withObject:nil afterDelay:0];
}

// Recompute the model and update the window frame.
- (void)update {
    [self.model updateWithQuery:_textField.stringValue];
    [_table reloadData];

    // We have to set the scrollview's size before animating the window or else
    // it happens only after the animation finishes. I couldn't get
    // autoresizing to do this automatically.
    NSRect frame = [self frame];
    NSRect contentViewFrame = [self.window frameRectForContentRect:frame];
    _scrollView.frame = NSMakeRect(_scrollView.frame.origin.x,
                                   _scrollView.frame.origin.y,
                                   contentViewFrame.size.width,
                                   contentViewFrame.size.height - 41);
    // Select the first item.
    if (self.model.items.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self tableViewSelectionDidChange:nil];
    }

    [self performSelector:@selector(resizeWindowAnimatedToFrame:)
               withObject:[NSValue valueWithRect:frame]
               afterDelay:0];
}

- (void)resizeWindowAnimatedToFrame:(NSValue *)frame {
    [self.window setFrame:frame.rectValue display:YES animate:YES];
}

// Returns the window frame. It's a fixed 170px below the top of the screen and
// its height is variable up to a limit of 170px above the bottom of the
// screen.
- (NSRect)frame {
    NSScreen *screen = [[NSApp keyWindow] screen];
    if (!screen) {
        screen = [NSScreen mainScreen];
    }
    static const CGFloat kMarginAboveField = 6;
    static const CGFloat kMarginBelowField = 6;
    static const CGFloat kMarginAboveWindow = 170;
    CGFloat maxHeight = screen.frame.size.height - kMarginAboveWindow * 2;
    CGFloat nonTableSpace = kMarginAboveField + _textField.frame.size.height + kMarginBelowField;
    int numberOfVisibleRowsDesired = MIN(self.model.items.count,
                                         (maxHeight - nonTableSpace) / (_table.rowHeight + _table.intercellSpacing.height));
    NSRect frame = self.window.frame;
    NSSize contentSize = frame.size;
    contentSize.height = nonTableSpace + (_table.rowHeight + _table.intercellSpacing.height) * numberOfVisibleRowsDesired;

    frame.size.height = contentSize.height;

    frame.origin.x = NSMinX(screen.frame) + floor((screen.frame.size.width - frame.size.width) / 2);
    frame.origin.y = NSMaxY(screen.frame) - kMarginAboveWindow - frame.size.height;
    return frame;
}

// Bound to the close button.
- (IBAction)close:(id)sender {
    [HotkeyWindowController closeWindowReturningToHotkeyWindowIfPossible:self.window];
}

// Switch to the session associated with the currently selected row, closing
// this window.
- (void)openSelectedRow {
    NSInteger row = [_table selectedRow];

    if (row >= 0) {
        id object = [self.model objectAtIndex:row];
        if ([object isKindOfClass:[PTYSession class]]) {
            PTYSession *session = object;
            if (session) {
                NSWindowController<iTermWindowController> *term = session.tab.realParentWindow;
                [term makeSessionActive:session];
            }
        } else if ([object isKindOfClass:[Profile class]]) {
            Profile *profile = object;
            iTermController *controller = [iTermController sharedInstance];
            [controller launchBookmark:profile
                            inTerminal:[controller currentTerminal]
                               withURL:nil
                              isHotkey:NO
                               makeKey:YES
                               command:nil
                                 block:nil];
        } else if ([object isKindOfClass:[NSString class]]) {
            [[iTermController sharedInstance] loadWindowArrangementWithName:object];
        }
    }

    [self close:nil];
}

// Returns an almost-black color. NSTableView treats actual black specially,
// and will actually draw white text if the background is not white. It won't
// mess with very, very dark gray though.
- (NSColor *)blackColor {
    return [NSColor colorWithCalibratedWhite:0.01 alpha:1];
}

#pragma mark - NSTableViewDataSource and NSTableViewDelegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _model.items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    iTermOpenQuicklyTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    iTermOpenQuicklyItem *item = _model.items[row];
    item.view = result;
    result.imageView.image = item.icon;

    result.textField.attributedStringValue =
        item.title ?: [[[NSAttributedString alloc] initWithString:@"Untitled" attributes:@{}] autorelease];
    [result.textField.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    if (item.detail) {
        result.detailTextField.attributedStringValue = item.detail;
        [result.detailTextField.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    } else {
        result.detailTextField.stringValue = @"";
    }
    NSColor *color;
    if (row == tableView.selectedRow) {
        color = [NSColor whiteColor];
    } else {
        color = [self blackColor];
    }
    result.textField.textColor = color;
    result.detailTextField.textColor = color;
    return result;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[[iTermOpenQuicklyTableRowView alloc] init] autorelease];
}

- (void)updateTextColorForAllRows {
    NSInteger row = [_table selectedRow];
    // Fix up text color for all items
    for (int i = 0; i < _model.items.count; i++) {
        iTermOpenQuicklyItem *item = _model.items[i];
        if (i == row) {
            item.view.textField.textColor = [NSColor whiteColor];
            item.view.detailTextField.textColor = [NSColor whiteColor];
        } else {
            item.view.textField.textColor = [self blackColor];
            item.view.detailTextField.textColor = [self blackColor];
        }
    }
}

- (void)tableViewSelectionIsChanging:(NSNotification *)notification {
    [self updateTextColorForAllRows];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateTextColorForAllRows];
}

- (void)doubleClick:(id)sender {
    [self openSelectedRow];
}

#pragma mark - NSWindowDelegate

- (void)windowDidResignKey:(NSNotification *)notification {
    [self.window close];
}

#pragma mark - NSControlDelegate

// User changed query.
- (void)controlTextDidChange:(NSNotification *)notification {
    [self update];
}

// User pressed enter (or something else we don't care about).
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    int move = [[[notification userInfo] objectForKey:@"NSTextMovement"] intValue];

    switch (move) {
        case NSReturnTextMovement:  // Enter key
            [self openSelectedRow];
            break;
        default:
            break;
    }
}

#pragma mark - iTermOpenQuicklyTextFieldDelegate

// Handle arrow keys while text field is key.
- (void)keyDown:(NSEvent *)theEvent {
    static BOOL running;
    if (!running) {
        running = YES;
        [_table keyDown:theEvent];
        running = NO;
    }
}

#pragma mark - iTermOpenQuicklyModelDelegate

- (id)openQuicklyModelDisplayStringForFeatureNamed:(NSString *)name
                                             value:(NSString *)value
                                highlightedIndexes:(NSIndexSet *)highlight {
    NSString *prefix;
    if (name) {
        prefix = [NSString stringWithFormat:@"%@: ", name];
    } else {
        prefix = @"";
    }
    NSMutableAttributedString *theString =
        [[[NSMutableAttributedString alloc] initWithString:prefix
                                                attributes:[self attributes]] autorelease];
    [theString appendAttributedString:[self attributedStringFromString:value
                                                 byHighlightingIndices:highlight]];
    return theString;
}

#pragma mark - String Formatting

// Highlight and underline characters in |source| at indices in |indexSet|.
// This isn't really appropriate for the model to do but it's much simpler and
// more efficient this way.
- (NSAttributedString *)attributedStringFromString:(NSString *)source
                             byHighlightingIndices:(NSIndexSet *)indexSet {
    NSMutableAttributedString *attributedString =
        [[[NSMutableAttributedString alloc] initWithString:source attributes:[self attributes]] autorelease];
    NSDictionary *highlight = @{ NSBackgroundColorAttributeName: [[NSColor yellowColor] colorWithAlphaComponent:0.4],
                                 NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                 NSUnderlineColorAttributeName: [NSColor yellowColor],
                                 NSParagraphStyleAttributeName: [[self attributes] objectForKey:NSParagraphStyleAttributeName] };
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [attributedString setAttributes:highlight range:NSMakeRange(idx, 1)];
    }];
    return attributedString;
}

- (NSDictionary *)attributes {
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{ NSParagraphStyleAttributeName: style };
}

@end
