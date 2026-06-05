#import "iTermOpenQuicklyWindowController.h"

#import "SFSymbolEnum/SFSymbolEnum.h"
#import "iTerm2SharedARC-Swift.h"
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
#import "DebugLogging.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
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

// Flipped NSView so the preview container can lay out subviews from the top.
@interface iTermOpenQuicklyPreviewView : NSView
@end

@implementation iTermOpenQuicklyPreviewView
- (BOOL)isFlipped { return YES; }
@end

// Width of the preview side panel when shown.
static const CGFloat kOpenQuicklyPreviewWidth = 400;
// Inset around the preview snapshot inside its container.
static const CGFloat kOpenQuicklyPreviewInset = 12;
// Layout metrics for the labels block above the preview image. Shared between
// previewWindowFrameForParentFrame: (which sizes the window) and
// layoutPreviewContent (which places the subviews) so they can't drift.
static const CGFloat kOpenQuicklyPreviewTitleHeight = 18;
static const CGFloat kOpenQuicklyPreviewDetailHeight = 14;
static const CGFloat kOpenQuicklyPreviewLabelGap = 2;
static const CGFloat kOpenQuicklyPreviewGapBelowLabels = 8;

static CGFloat iTermOpenQuicklyPreviewLabelsBlockHeight(void) {
    return kOpenQuicklyPreviewTitleHeight + kOpenQuicklyPreviewLabelGap +
           kOpenQuicklyPreviewDetailHeight + kOpenQuicklyPreviewGapBelowLabels;
}

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

    // Preview side panel (a child window) shown when the highlighted row maps to a session.
    NSPanel *_previewWindow;
    NSImageView *_previewImageView;
    NSTextField *_previewTitleLabel;
    NSTextField *_previewDetailLabel;
    BOOL _previewVisible;
    BOOL _previewWindowAttached;
    // Cache the most recently snapshotted session so we don't re-render the
    // grid on every keystroke when the selected row maps to the same session.
    // Cleared by -teardownPreviewWindow, which every dismissal path goes through,
    // so the cache cannot survive across Open Quickly invocations.
    NSString *_cachedPreviewSessionGuid;
    // Last row -refreshPreview was called for. Used to detect selection changes
    // that were dropped while _suppressSelectionPreviewUpdates was set.
    NSInteger _previewRefreshedForRow;
    // Suppresses tableViewSelectionDidChange:'s work while -update is already
    // refreshing the preview itself.
    BOOL _suppressSelectionPreviewUpdates;
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
        _previewRefreshedForRow = NSNotFound;
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
            NSImage *image = [NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolMagnifyingglass)
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
            NSImage *image = [NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolXmarkCircleFill)
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
    if (@available(macOS 26, *)) {} else {
        contentView.layer.borderColor = [[NSColor colorWithCalibratedRed:0.66 green:0.66 blue:0.66 alpha:1] CGColor];
        contentView.layer.borderWidth = 0.5;
    }

    if (@available(macOS 10.16, *)) {
        _divider.hidden = YES;
    } else {
        _divider.color = [NSColor colorWithCalibratedRed:0.66 green:0.66 blue:0.66 alpha:1];
    }
}

- (void)buildPreviewWindow {
    if (_previewWindow) {
        return;
    }
    NSRect frame = NSMakeRect(0, 0, kOpenQuicklyPreviewWidth, 400);
    _previewWindow = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    _previewWindow.opaque = NO;
    _previewWindow.backgroundColor = [NSColor clearColor];
    _previewWindow.hasShadow = YES;
    _previewWindow.releasedWhenClosed = NO;
    _previewWindow.hidesOnDeactivate = YES;
    _previewWindow.movableByWindowBackground = NO;
    _previewWindow.becomesKeyOnlyIfNeeded = YES;

    iTermOpenQuicklyPreviewView *contentView = [[iTermOpenQuicklyPreviewView alloc] initWithFrame:frame];
    contentView.wantsLayer = YES;
    contentView.layer.cornerRadius = 10;
    contentView.layer.masksToBounds = YES;
    _previewWindow.contentView = contentView;

    NSVisualEffectView *visual = [[NSVisualEffectView alloc] initWithFrame:contentView.bounds];
    visual.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    if (@available(macOS 10.16, *)) {
        visual.material = NSVisualEffectMaterialMenu;
    } else {
        visual.material = NSVisualEffectMaterialSheet;
    }
    visual.state = NSVisualEffectStateActive;
    visual.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:visual];

    _previewTitleLabel = [NSTextField labelWithString:@""];
    _previewTitleLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _previewTitleLabel.font = [NSFont boldSystemFontOfSize:13];
    _previewTitleLabel.textColor = [NSColor labelColor];
    _previewTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewTitleLabel.backgroundColor = [NSColor clearColor];
    _previewTitleLabel.drawsBackground = NO;
    [contentView addSubview:_previewTitleLabel];

    _previewDetailLabel = [NSTextField labelWithString:@""];
    _previewDetailLabel.translatesAutoresizingMaskIntoConstraints = YES;
    _previewDetailLabel.font = [NSFont systemFontOfSize:11];
    _previewDetailLabel.textColor = [NSColor secondaryLabelColor];
    _previewDetailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _previewDetailLabel.backgroundColor = [NSColor clearColor];
    _previewDetailLabel.drawsBackground = NO;
    [contentView addSubview:_previewDetailLabel];

    _previewImageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _previewImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    // Align top so the image sits flush with the labels above and any vertical
    // slack lands at the bottom of the preview.
    _previewImageView.imageAlignment = NSImageAlignTop;
    _previewImageView.wantsLayer = YES;
    _previewImageView.layer.cornerRadius = 4;
    _previewImageView.layer.masksToBounds = YES;
    _previewImageView.layer.borderColor = [[NSColor separatorColor] CGColor];
    _previewImageView.layer.borderWidth = 0.5;
    [contentView addSubview:_previewImageView];
}

- (void)presentWindow {
    [self teardownPreviewWindow];
    [self buildPreviewWindow];
    [_model removeAllItems];
    [_table reloadData];
    self.window.appearance = [NSAppearance it_appearanceForCurrentTheme];
    // Mirror iTermProfileHotKey's floating-panel collection behavior. Notably:
    // (1) FullScreenAuxiliary lets the panel appear over fullscreen windows of
    // other apps, (2) Transient is omitted because transient windows "do not
    // contribute to the active state of the app", which appears to break
    // re-show as a non-activating panel on macOS 26.
    self.window.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                      NSWindowCollectionBehaviorFullScreenAuxiliary |
                                      NSWindowCollectionBehaviorIgnoresCycle);
    // Float just below the main menu, matching the level used by iTerm2's
    // floating profile hotkey window. Higher levels (e.g. NSPopUpMenuWindowLevel)
    // are not honored for non-activating panels on macOS 26 when the app is
    // in the background, so the panel ends up hidden behind other apps on
    // subsequent shows.
    if (@available(macOS 10.16, *)) {
        self.window.level = NSMainMenuWindowLevel - 2;
    } else {
        self.window.level = 17;
    }
    // Set the window's frame to be table-less initially.
    [self.window setFrame:[self frame] display:YES animate:NO];
    [_textField selectText:nil];
    // The alpha 0 -> 1 fade is only needed when iTerm2 is in the background:
    // on macOS 26 the alpha transition is what forces the window server to
    // actually paint a non-activating panel brought up from another app.
    // When iTerm2 is already active, skip it so it doesn't race with the
    // setFrame:display:animate:YES height animation in -resizeWindowAnimatedToFrame:.
    NSRunningApplication *frontmost = NSWorkspace.sharedWorkspace.frontmostApplication;
    const BOOL inBackground = (frontmost != nil &&
                               ![frontmost isEqual:NSRunningApplication.currentApplication]);
    if (inBackground) {
        self.window.alphaValue = 0;
        [self.window makeKeyAndOrderFront:nil];
        [self.window.animator setAlphaValue:1];
    } else {
        self.window.alphaValue = 1;
        [self.window makeKeyAndOrderFront:nil];
    }

    // After the window is rendered, call update which will animate to the new frame.
    [self performSelector:@selector(update) withObject:nil afterDelay:0];
}

// Recompute the model and update the window frame.
- (void)update {
    _suppressSelectionPreviewUpdates = YES;
    [self.model updateWithQuery:_textField.stringValue];
    _xButton.hidden = _textField.stringValue.length == 0;
    [_table reloadData];

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
                                   contentViewFrame.size.height - _scrollView.frame.origin.y - 10);
    if (self.model.items.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [_table scrollRowToVisible:0];
    }
    [self refreshPreview];

    [self performSelector:@selector(resizeWindowAnimatedToFrame:)
               withObject:[NSValue valueWithRect:frame]
               afterDelay:0];
    // _suppressSelectionPreviewUpdates is cleared at the end of
    // resizeWindowAnimatedToFrame: so the flag actually covers any
    // selection-change notifications dispatched between now and the resize.
    // If the controller is torn down before the deferred resize fires (window
    // closed), the perform still runs but is harmless because -refreshPreview
    // short-circuits on !self.window.isVisible.
}

- (void)resizeWindowAnimatedToFrame:(NSValue *)frame {
    NSRect parentFrame = frame.rectValue;
    [self.window setFrame:parentFrame display:YES animate:YES];
    if (_previewVisible) {
        // setFrame:display:animate:YES on the borderless NSPanel doesn't reliably
        // animate the resize, so snap directly to the new frame after the parent's
        // animation completes.
        NSRect previewFrame = [self previewWindowFrameForParentFrame:parentFrame];
        [_previewWindow setFrame:previewFrame display:YES];
        [self layoutPreviewContent];
    }
    _suppressSelectionPreviewUpdates = NO;
    // setFrame:display:animate:YES pumps the run loop while it blocks, so the
    // user can click a different row mid-animation. Catch up if the selection
    // changed while notifications were being suppressed.
    if (_table.selectedRow != _previewRefreshedForRow) {
        [self refreshPreview];
    }
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

#pragma mark - Preview

- (PTYSession *)previewSessionForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.model.items.count) {
        return nil;
    }
    id obj = [self.model objectAtIndex:row];
    if ([obj isKindOfClass:[PTYSession class]]) {
        return obj;
    }
    if ([obj isKindOfClass:[PseudoTerminal class]]) {
        return ((PseudoTerminal *)obj).currentSession;
    }
    if ([obj isKindOfClass:[iTermOpenQuicklyNamedMarkItem class]]) {
        return ((iTermOpenQuicklyNamedMarkItem *)obj).session;
    }
    return nil;
}

- (NSString *)previewDetailForSession:(PTYSession *)session {
    if (![session.delegate isKindOfClass:[PTYTab class]]) {
        return @"";
    }
    PTYTab *tab = (PTYTab *)session.delegate;
    NSString *windowTitle = tab.realParentWindow.window.title ?: @"";
    if (windowTitle.length == 0) {
        return [NSString stringWithFormat:@"Tab %d", tab.objectCount];
    }
    return [NSString stringWithFormat:@"Tab %d · %@", tab.objectCount, windowTitle];
}

- (void)refreshPreview {
    if (!self.window.isVisible) {
        // A stray selection-change notification can fire after the window
        // closes; don't re-attach or re-show the preview in that case.
        return;
    }
    NSInteger row = _table.selectedRow;
    _previewRefreshedForRow = row;
    PTYSession *session = [self previewSessionForRow:row];
    BOOL wasVisible = _previewVisible;
    if (session) {
        if (![session.guid isEqualToString:_cachedPreviewSessionGuid]) {
            // Re-render only when the highlighted session actually changes; the
            // grid render is non-trivial and -update fires on every keystroke.
            // Only cache the guid on a successful render so a transient nil
            // (e.g. textview not yet laid out) doesn't lock in a blank preview.
            NSImage *image = [session terminalContentSnapshot];
            _previewImageView.image = image;
            _cachedPreviewSessionGuid = image ? [session.guid copy] : nil;
        }
        _previewTitleLabel.stringValue = session.name ?: @"";
        _previewDetailLabel.stringValue = [self previewDetailForSession:session];
        _previewVisible = YES;
    } else {
        _previewImageView.image = nil;
        _previewTitleLabel.stringValue = @"";
        _previewDetailLabel.stringValue = @"";
        _cachedPreviewSessionGuid = nil;
        _previewVisible = NO;
    }
    if (_previewVisible) {
        [self attachPreviewWindowIfNeeded];
        [self repositionPreviewWindow];
        if (!wasVisible) {
            [_previewWindow orderFront:nil];
        }
    } else if (wasVisible) {
        [_previewWindow orderOut:nil];
    }
}

- (void)attachPreviewWindowIfNeeded {
    if (_previewWindowAttached || _previewWindow == nil) {
        return;
    }
    [self.window addChildWindow:_previewWindow ordered:NSWindowAbove];
    _previewWindowAttached = YES;
}

- (NSRect)previewWindowFrameForParentFrame:(NSRect)parentFrame {
    const CGFloat gap = 8;
    const CGFloat inset = kOpenQuicklyPreviewInset;
    const CGFloat labelsBlockHeight = iTermOpenQuicklyPreviewLabelsBlockHeight();
    const CGFloat innerWidth = kOpenQuicklyPreviewWidth - 2 * inset;

    // Size the image area to the snapshot's aspect ratio so a tall session
    // gets a tall preview and a short session gets a short preview.
    CGFloat imageHeight = 240;
    NSImage *image = _previewImageView.image;
    if (image && image.size.width > 0) {
        imageHeight = innerWidth * (image.size.height / image.size.width);
    }
    CGFloat windowHeight = inset + labelsBlockHeight + imageHeight + inset;
    NSScreen *screen = self.window.screen ?: [NSScreen mainScreen];
    const NSRect visibleFrame = screen.visibleFrame;
    const CGFloat maxHeight = MAX(visibleFrame.size.height - 24, 300);
    windowHeight = MIN(MAX(windowHeight, 200), maxHeight);

    // Prefer the right side of the parent; flip to the left if the right side
    // would extend off-screen, and clamp horizontally to the visible frame.
    CGFloat originX = NSMaxX(parentFrame) + gap;
    if (originX + kOpenQuicklyPreviewWidth > NSMaxX(visibleFrame)) {
        const CGFloat leftOriginX = NSMinX(parentFrame) - gap - kOpenQuicklyPreviewWidth;
        if (leftOriginX >= NSMinX(visibleFrame)) {
            originX = leftOriginX;
        } else {
            originX = NSMaxX(visibleFrame) - kOpenQuicklyPreviewWidth;
        }
    }
    originX = MAX(originX, NSMinX(visibleFrame));

    CGFloat originY = NSMaxY(parentFrame) - windowHeight;
    originY = MIN(MAX(originY, NSMinY(visibleFrame)), NSMaxY(visibleFrame) - windowHeight);

    return NSMakeRect(originX, originY, kOpenQuicklyPreviewWidth, windowHeight);
}

- (void)repositionPreviewWindow {
    if (_previewWindow == nil) {
        return;
    }
    [_previewWindow setFrame:[self previewWindowFrameForParentFrame:self.window.frame]
                     display:YES];
    [self layoutPreviewContent];
}

- (void)layoutPreviewContent {
    NSView *contentView = _previewWindow.contentView;
    if (contentView == nil) {
        return;
    }
    const CGFloat inset = kOpenQuicklyPreviewInset;
    const CGFloat innerWidth = contentView.bounds.size.width - 2 * inset;
    _previewTitleLabel.frame = NSMakeRect(inset, inset, innerWidth, kOpenQuicklyPreviewTitleHeight);
    _previewDetailLabel.frame = NSMakeRect(inset,
                                            inset + kOpenQuicklyPreviewTitleHeight + kOpenQuicklyPreviewLabelGap,
                                            innerWidth,
                                            kOpenQuicklyPreviewDetailHeight);
    const CGFloat imageY = inset + iTermOpenQuicklyPreviewLabelsBlockHeight();
    const CGFloat imageHeight = MAX(contentView.bounds.size.height - imageY - inset, 0);
    _previewImageView.frame = NSMakeRect(inset, imageY, innerWidth, imageHeight);
}

// Bound to the close button.
- (IBAction)close:(id)sender {
    [self teardownPreviewWindow];
    // Use orderOut, not close. -close on a non-activating panel can leave the
    // window in a state where the window-server refuses to re-elevate it on
    // subsequent shows from a background app (iTermProfileHotKey's floating
    // panel uses the same pattern).
    [self.window orderOut:nil];
}

- (void)teardownPreviewWindow {
    if (_previewWindowAttached) {
        [self.window removeChildWindow:_previewWindow];
        _previewWindowAttached = NO;
    }
    // Destroy the panel and rebuild it on the next presentation. orderOut alone
    // has proven unreliable for borderless NSPanels here; stale window state
    // can leave ghost panels on screen across opens.
    [_previewWindow close];
    _previewWindow = nil;
    _previewImageView = nil;
    _previewTitleLabel = nil;
    _previewDetailLabel = nil;
    _previewVisible = NO;
    _cachedPreviewSessionGuid = nil;
}

// Observes NSWorkspaceActiveSpaceDidChangeNotification once. When the Space
// switch animation completes, macOS may pick a different app's window as
// frontmost on the destination Space; re-activate iTerm2 over a couple of
// runloop spins to win the race. Modeled on iTermProfileHotKey's
// activeSpaceDidChange: handling.
- (void)reassertActivationAfterSpaceChange {
    __block id token = nil;
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    token = [center addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
                                object:nil
                                 queue:NSOperationQueue.mainQueue
                            usingBlock:^(NSNotification *note) {
        if (token) {
            [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:token];
            token = nil;
        }
        // Two spins of the runloop, then re-activate if some other app stole
        // the focus during the Space transition.
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                NSRunningApplication *current = NSRunningApplication.currentApplication;
                if (![NSWorkspace.sharedWorkspace.frontmostApplication isEqual:current]) {
                    [current activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                }
            });
        });
    }];
    // Bail out after a short timeout so we don't leak the observer if no Space
    // change actually happens.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (token) {
            [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:token];
            token = nil;
        }
    });
}

// Switch to the session associated with the currently selected row, closing
// this window.
- (void)openSelectedRow {
    // NSApp.isActive returns YES whenever our panel is key, even if iTerm2
    // isn't the frontmost app, so it's not a reliable check. Compare against
    // NSWorkspace.frontmostApplication to actually detect "we're in the
    // background".
    NSRunningApplication *frontmost = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!frontmost || ![frontmost isEqual:NSRunningApplication.currentApplication]) {
        [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        // If selecting a session triggers a Space switch (e.g. the user is in
        // another app's fullscreen Space and the chosen session lives on a
        // different Space), macOS often activates some other app once the
        // animation finishes. Re-assert iTerm2's frontmost status after the
        // active-Space change notification arrives.
        [self reassertActivationAfterSpaceChange];
    }
    NSInteger row = [_table selectedRow];

    if (row >= 0) {
        id object = [self.model objectAtIndex:row];
        DLog(@"%@", object);
        if ([object isKindOfClass:[PTYSession class]]) {
            // Switch to session
            PTYSession *session = object;
            [session reveal];
        } else if ([object isKindOfClass:[Profile class]]) {
            // Create a new tab/window
            Profile *profile = object;
            iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForGUID:profile[KEY_GUID]];
            if (!profileHotkey || profileHotkey.windowController.weaklyReferencedObject) {
                // Create a new non-hotkey window
                [iTermSessionLauncher launchBookmark:profile
                                          inTerminal:[[iTermController sharedInstance] currentTerminal]
                                               style:iTermOpenStyleTab
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
        } else if ([object isKindOfClass:[iTermOpenQuicklyNamedMarkItem class]]) {
            iTermOpenQuicklyNamedMarkItem *item = [iTermOpenQuicklyNamedMarkItem castFrom:object];
            if (item.session) {
                [item.session reveal];
                [item.session scrollToNamedMark:item.namedMark];
            }
        } else if ([object isKindOfClass:[iTermOpenQuicklyMenuItem class]]) {
            iTermOpenQuicklyMenuItem *item = [iTermOpenQuicklyMenuItem castFrom:object];
            if (item.valid) {
                // Do it after this window is no longer around.
                dispatch_async(dispatch_get_main_queue(), ^{
                    [NSApp sendAction:item.menuItem.action
                                   to:item.menuItem.target
                                 from:item.menuItem];
                });
            }
        } else {
            if (@available(macOS 11, *)) {
                if ([object isKindOfClass:[iTermOpenQuicklyInvocationItem class]]) {
                    iTermOpenQuicklyInvocationItem *item = [iTermOpenQuicklyInvocationItem castFrom:object];
                    [iTermScriptFunctionCall callFunction:item.identifier
                                                  timeout:[[NSDate distantFuture] timeIntervalSinceNow]
                                       sideEffectsAllowed:YES
                                                    scope:item.scope
                                               retainSelf:YES
                                               completion:^(id value, NSError *error, NSSet<NSString *> *missing) {
                        if (error) {
                            [iTermAPIHelper reportFunctionCallError:error
                                                      forInvocation:item.identifier
                                                             origin:@"Open Quickly"
                                                             window:nil];
                        } else {
                            NSAlert *alert = [[NSAlert alloc] init];
                            [alert setMessageText:@"Function Call Result"];
                            [alert setInformativeText:[NSString stringWithFormat:@"%@ returned:\n%@", item.identifier, [value description]]];
                            [alert addButtonWithTitle:@"OK"];
                            [alert runModal];
                        }
                    }];
                } else {
                    if ([iTermBrowserGateway browserAllowedCheckingIfNot:NO]) {
                        if ([object isKindOfClass:[iTermOpenQuicklyBookmarkItem class]]) {
                            iTermOpenQuicklyBookmarkItem *item = [iTermOpenQuicklyBookmarkItem castFrom:object];
                            PTYSession *session = iTermController.sharedInstance.currentTerminal.currentSession;
                            if (session.isBrowserSession) {
                                [session openURL:item.url];
                            } else {
                                [[iTermController sharedInstance] openURL:item.url
                                                                   target:nil
                                                                openStyle:iTermOpenStyleTab
                                                                select:YES];
                            }
                        } else if ([object isKindOfClass:[iTermOpenQuicklyURLItem class]]) {
                            iTermOpenQuicklyURLItem *item = [iTermOpenQuicklyURLItem castFrom:object];
                            PTYSession *session = iTermController.sharedInstance.currentTerminal.currentSession;
                            if (session.isBrowserSession) {
                                [session openURL:item.url];
                            } else {
                                [[iTermController sharedInstance] openURL:item.url
                                                                   target:nil
                                                                openStyle:iTermOpenStyleTab
                                                                   select:YES];
                            }
                        }
                    }
                }
            }
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (_suppressSelectionPreviewUpdates) {
        return;
    }
    [self refreshPreview];
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
    [self teardownPreviewWindow];
    [self.window orderOut:nil];
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
        [_table scrollRowToVisible:row];
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
    if (theEvent.keyCode == kVK_Escape) {
        [self close:nil];
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
