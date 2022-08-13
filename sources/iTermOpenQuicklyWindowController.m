#import "iTermOpenQuicklyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermHotKeyController.h"
#import "iTermProfileHotKey.h"
#import "iTermOpenQuicklyItem.h"
#import "iTermOpenQuicklyModel.h"
#import "iTermOpenQuicklyTableCellView.h"
#import "iTermOpenQuicklyTableRowView.h"
#import "iTermOpenQuicklyTextField.h"
#import "iTermScriptsMenuController.h"
#import "iTermSessionLauncher.h"
#import "iTermSnippetsMenuController.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"
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

@property(nonatomic, strong) iTermOpenQuicklyModel *model;

@end

@implementation iTermOpenQuicklyWindowController {
    // Text field where queries are entered
    IBOutlet iTermOpenQuicklyTextField *_textField;

    // Table that shows search results
    IBOutlet NSTableView *_table;

    IBOutlet NSScrollView *_scrollView;

    IBOutlet SolidColorView *_divider;
    IBOutlet NSButton *_xButton;
    IBOutlet NSImageView *_loupe;
    iTermOpenQuicklyTextView *_textView;  // custom field editor
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"iTermOpenQuicklyWindowController"];
    if (self) {
        _model = [[iTermOpenQuicklyModel alloc] init];
        _model.delegate = self;
    }
    return self;
}

- (void)awakeFromNib {
    // Initialize the table
#ifdef MAC_OS_X_VERSION_10_16
    if (@available(macOS 10.16, *)) {
        _table.style = NSTableViewStyleInset;
        // Possibly a 10.16 beta bug? Using intercell spacing clips the selection rect.
        _table.intercellSpacing = NSZeroSize;
    }
#endif
    [_table setDoubleAction:@selector(doubleClick:)];

    // Initialize the window's contentView
    SolidColorView *contentView = [self.window contentView];

    // Initialize the window
    [self.window setOpaque:NO];
    _table.backgroundColor = [NSColor clearColor];
    _table.enclosingScrollView.drawsBackground = NO;
    contentView.color = [NSColor clearColor];
    self.window.backgroundColor = [NSColor clearColor];

    if (@available(macOS 10.16, *)) {
        {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"magnifyingglass"
                                       accessibilityDescription:@"Search icon"];
            NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:21
                                                            weight:NSFontWeightRegular];
            [_loupe setImage:[image imageWithSymbolConfiguration:config]];
        }
        {
            NSImageSymbolConfiguration *config =
            [NSImageSymbolConfiguration configurationWithPointSize:14
                                                            weight:NSFontWeightRegular];
            NSImage *image = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
                                       accessibilityDescription:@"Clear search query"];
            [_xButton setImage:[image imageWithSymbolConfiguration:config]];
            NSRect frame = _xButton.frame;
            const CGFloat delta = 2;
            frame.size.width += delta;
            frame.size.height += delta;
            frame.origin.x -= delta / 2.0;
            frame.origin.y -= delta / 2.0;
            _xButton.frame = frame;
        }
    }

    // Rounded corners for contentView
    contentView.wantsLayer = YES;
    if (@available(macOS 10.16, *)) {
        contentView.layer.cornerRadius = 10;
    } else {
        contentView.layer.cornerRadius = 6;
    }
    contentView.layer.masksToBounds = YES;
    contentView.layer.borderColor = [[NSColor colorWithCalibratedRed:0.66 green:0.66 blue:0.66 alpha:1] CGColor];
    contentView.layer.borderWidth = 0.5;

    if (@available(macOS 10.16, *)) {
        _divider.hidden = YES;
    } else {
        _divider.color = [NSColor colorWithCalibratedRed:0.66 green:0.66 blue:0.66 alpha:1];
    }
}

- (void)presentWindow {
    [_model removeAllItems];
    [_table reloadData];
    // Set the window's frame to be table-less initially.
    [self.window setFrame:[self frame] display:YES animate:NO];
    [_textField selectText:nil];
    [self.window it_makeKeyAndOrderFront];

    // After the window is rendered, call update which will animate to the new frame.
    [self performSelector:@selector(update) withObject:nil afterDelay:0];
}

// Recompute the model and update the window frame.
- (void)update {
    [self.model updateWithQuery:_textField.stringValue];
    _xButton.hidden = _textField.stringValue.length == 0;
    [_table reloadData];

    // We have to set the scrollview's size before animating the window or else
    // it happens only after the animation finishes. I couldn't get
    // autoresizing to do this automatically.
    NSRect frame = [self frame];
    NSRect contentViewFrame = [self.window frameRectForContentRect:frame];
    if (@available(macOS 10.16, *)) {
        _divider.hidden = YES;
    } else {
        _divider.hidden = (self.model.items.count == 0);
    }
    _scrollView.frame = NSMakeRect(_scrollView.frame.origin.x,
                                   _scrollView.frame.origin.y,
                                   contentViewFrame.size.width,
                                   contentViewFrame.size.height - 41);
    // Select the first item.
    if (self.model.items.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
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
    static const CGFloat kMarginAboveField = 12;
    static const CGFloat kMarginBelowField = 9;
    static const CGFloat kMarginAboveWindow = 170;
    CGFloat maxHeight = screen.frame.size.height - kMarginAboveWindow * 2;
    CGFloat nonTableSpace = kMarginAboveField + _textField.frame.size.height + kMarginBelowField;
    int numberOfVisibleRowsDesired = MIN(self.model.items.count,
                                         (maxHeight - nonTableSpace) / (_table.rowHeight + _table.intercellSpacing.height));
    NSRect frame = self.window.frame;
    NSSize contentSize = frame.size;

    contentSize.height = nonTableSpace;
    if (numberOfVisibleRowsDesired > 0) {
        // Use the bottom of the last visible cell's frame for the height of the table view portion
        // of the window. This is the most reliable way of getting its max-Y position.
        NSRect frameOfLastVisibleCell = [_table frameOfCellAtColumn:0
                                                                row:numberOfVisibleRowsDesired - 1];
        contentSize.height += NSMaxY(frameOfLastVisibleCell);
        if (@available(macOS 10.16, *)) {
            contentSize.height += 10;
        }
    }
    frame.size.height = contentSize.height;

    frame.origin.x = NSMinX(screen.frame) + floor((screen.frame.size.width - frame.size.width) / 2);
    frame.origin.y = NSMaxY(screen.frame) - kMarginAboveWindow - frame.size.height;
    return frame;
}

// Bound to the close button.
- (IBAction)close:(id)sender {
    [self.window close];
}

// Switch to the session associated with the currently selected row, closing
// this window.
- (void)openSelectedRow {
    NSInteger row = [_table selectedRow];

    if (row >= 0) {
        id object = [self.model objectAtIndex:row];
        if ([object isKindOfClass:[PTYSession class]]) {
            // Switch to session
            PTYSession *session = object;
            if (session) {
                NSWindowController<iTermWindowController> *term = session.delegate.realParentWindow;
                [term makeSessionActive:session];
            }
        } else if ([object isKindOfClass:[Profile class]]) {
            // Create a new tab/window
            Profile *profile = object;
            iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForGUID:profile[KEY_GUID]];
            if (!profileHotkey || profileHotkey.windowController.weaklyReferencedObject) {
                // Create a new non-hotkey window
                [iTermSessionLauncher launchBookmark:profile
                                          inTerminal:[[iTermController sharedInstance] currentTerminal]
                                             withURL:nil
                                    hotkeyWindowType:iTermHotkeyWindowTypeNone
                                             makeKey:YES
                                         canActivate:YES
                                  respectTabbingMode:NO
                                               index:nil
                                             command:nil
                                         makeSession:nil
                                      didMakeSession:nil
                                          completion:nil];
            } else {
                // Create the hotkey window for this profile
                [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:profileHotkey url:nil];
            }
        } else if ([object isKindOfClass:[PseudoTerminal class]]) {
            PseudoTerminal *term = object;
            if (term.isHotKeyWindow) {
                iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:term];
                [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:profileHotkey url:nil];
            } else {
                NSWindow *window = [object window];
                [window makeKeyAndOrderFront:nil];
            }
        } else if ([object isKindOfClass:[iTermOpenQuicklyArrangementItem class]]) {
            // Load window arrangement
            iTermOpenQuicklyArrangementItem *item = (iTermOpenQuicklyArrangementItem *)object;
            [[iTermController sharedInstance] loadWindowArrangementWithName:item.identifier asTabsInTerminal:item.inTabs ? [[iTermController sharedInstance] currentTerminal] : nil];
        } else if ([object isKindOfClass:[iTermOpenQuicklyChangeProfileItem class]]) {
            // Change profile
            iTermOpenQuicklyChangeProfileItem *item = object;
            PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
            PTYSession *session = term.currentSession;
            NSString *guid = [item identifier];
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
            if (profile) {
                [session setProfile:profile preservingName:YES];
                // Make sure the OS doesn't pick some random window to make key
                [term.window makeKeyAndOrderFront:nil];
            }
        } else if ([object isKindOfClass:[iTermOpenQuicklyHelpItem class]]) {
            iTermOpenQuicklyHelpItem *item = object;
            _textField.stringValue = [item identifier];
            [self update];
            return;
        } else if ([object isKindOfClass:[iTermOpenQuicklyScriptItem class]]) {
            iTermOpenQuicklyScriptItem *item = [iTermOpenQuicklyScriptItem castFrom:object];
            [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] launchScriptWithRelativePath:item.identifier
                                                                                                        arguments:@[]
                                                                                               explicitUserAction:YES];
        } else if ([object isKindOfClass:[iTermOpenQuicklyColorPresetItem class]]) {
            iTermOpenQuicklyColorPresetItem *item = [iTermOpenQuicklyColorPresetItem castFrom:object];
            PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
            PTYSession *session = term.currentSession;
            [session setColorsFromPresetNamed:item.presetName];
        } else if ([object isKindOfClass:[iTermOpenQuicklyActionItem class]]) {
            iTermOpenQuicklyActionItem *item = [iTermOpenQuicklyActionItem castFrom:object];
            PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
            PTYSession *session = term.currentSession;
            [session applyAction:item.action];
        } else if ([object isKindOfClass:[iTermOpenQuicklySnippetItem class]]) {
            iTermOpenQuicklySnippetItem *item = [iTermOpenQuicklySnippetItem castFrom:object];
            PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
            PTYSession *session = term.currentSession;
            [session.textview sendSnippet:item];
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
        item.title ?: [[NSAttributedString alloc] initWithString:@"Untitled" attributes:@{}];
    [result.textField.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    if (item.detail) {
        result.detailTextField.attributedStringValue = item.detail;
        [result.detailTextField.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    } else {
        result.detailTextField.stringValue = @"";
    }
    NSColor *color;
    NSColor *detailColor;
    color = [NSColor labelColor];
    detailColor = [NSColor secondaryLabelColor];
    result.textField.font = [NSFont systemFontOfSize:13];
    result.textField.textColor = color;
    result.detailTextField.textColor = detailColor;
    return result;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    if (@available(macOS 10.16, *)) {
        return [[iTermOpenQuicklyTableRowView_BigSur alloc] init];
    } else {
        return [[iTermOpenQuicklyTableRowView alloc] init];
    }
}

- (void)doubleClick:(id)sender {
    [self openSelectedRow];
}

#pragma mark - NSWindowDelegate

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
    if (![client isKindOfClass:[iTermOpenQuicklyTextField class]]) {
        return nil;
    }
    if (!_textView) {
        _textView = [[iTermOpenQuicklyTextView alloc] init];
        [_textView setFieldEditor:YES];
    }
    return _textView;
}

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

// This makes ^N and ^P work.
- (BOOL)control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector {
    BOOL result = NO;

    if (commandSelector == @selector(moveUp:) || commandSelector == @selector(moveDown:)) {
        NSInteger row = [_table selectedRow];
        if (row < 0) {
            row = 0;
        } else if (commandSelector == @selector(moveUp:)) {
            if (row > 0) {
                row--;
            } else {
                row = _table.numberOfRows - 1;
            }
        } else if (commandSelector == @selector(moveDown:)) {
            if (row + 1 < _table.numberOfRows) {
                row++;
            } else {
                row = 0;
            }
        }
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        result = YES;
    }
    return result;
}

#pragma mark - iTermOpenQuicklyTextFieldDelegate

// Handle arrow keys while text field is key.
- (void)keyDown:(NSEvent *)theEvent {
    static BOOL running;
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagCommand |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    if (theEvent.keyCode == kVK_Return && (theEvent.modifierFlags & mask) == NSEventModifierFlagOption) {
        [self openSelectedRow];
        return;
    }
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
        [[NSMutableAttributedString alloc] initWithString:prefix
                                               attributes:[self attributes]];
    [theString appendAttributedString:[self attributedStringFromString:value
                                                 byHighlightingIndices:highlight]];
    return theString;
}

- (NSAttributedString *)openQuicklyModelAttributedStringForDetail:(NSString *)detail
                                                      featureName:(NSString *)featureName {
    NSString *composite;
    if (featureName) {
        composite = [NSString stringWithFormat:@"%@: %@", featureName, detail];
    } else {
        composite = detail;
    }
    return [self attributedStringFromString:composite
                      byHighlightingIndices:nil];
}

#pragma mark - String Formatting

// Highlight and underline characters in |source| at indices in |indexSet|.
// This isn't really appropriate for the model to do but it's much simpler and
// more efficient this way.
- (NSAttributedString *)attributedStringFromString:(NSString *)source
                             byHighlightingIndices:(NSIndexSet *)indexSet {
    NSMutableAttributedString *attributedString =
        [[NSMutableAttributedString alloc] initWithString:source attributes:[self attributes]];
    NSDictionary *highlight = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:13],
                                 NSParagraphStyleAttributeName: [[self attributes] objectForKey:NSParagraphStyleAttributeName]
    };
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [attributedString setAttributes:highlight range:NSMakeRange(idx, 1)];
    }];
    return attributedString;
}

- (NSDictionary *)attributes {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{ NSParagraphStyleAttributeName: style };
}

@end
