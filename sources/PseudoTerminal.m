#import "PseudoTerminal.h"

#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "ColorsMenuItemView.h"
#import "CommandHistoryPopup.h"
#import "Coprocess.h"
#import "DirectoriesPopup.h"
#import "FakeWindow.h"
#import "FindViewController.h"
#import "FutureMethods.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermAboutWindow.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermController.h"
#import "iTermFindCursorView.h"
#import "iTermFontPanel.h"
#import "iTermGrowlDelegate.h"
#import "iTermHotKeyController.h"
#import "iTermHotKeyMigrationHelper.h"
#import "iTermInstantReplayWindowController.h"
#import "iTermOpenQuicklyWindow.h"
#import "iTermPasswordManagerWindowController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermProfilesWindowController.h"
#import "iTermQuickLookController.h"
#import "iTermRootTerminalView.h"
#import "iTermSelection.h"
#import "iTermShellHistoryController.h"
#import "iTermSystemVersion.h"
#import "iTermTabBarControlView.h"
#import "iTermToolbeltView.h"
#import "iTermWarning.h"
#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "MovePaneController.h"
#import "NSArray+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+PSM.h"
#import "NSWorkspace+iTerm.h"
#import "PasteboardHistory.h"
#import "PopupModel.h"
#import "PopupWindow.h"
#import "PreferencePanel.h"
#import "ProcessCache.h"
#import "PseudoTerminalRestorer.h"
#import "PSMDarkTabStyle.h"
#import "PSMDarkHighContrastTabStyle.h"
#import "PSMLightHighContrastTabStyle.h"
#import "PSMTabStyle.h"
#import "PSMYosemiteTabStyle.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTabView.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "SessionView.h"
#import "SplitPanel.h"
#import "TemporaryNumberAllocator.h"
#import "TmuxControllerRegistry.h"
#import "TmuxDashboardController.h"
#import "TmuxLayoutParser.h"
#import "ToolCapturedOutputView.h"
#import "ToolCommandHistoryView.h"
#import "ToolDirectoriesView.h"
#import "VT100Screen.h"
#import "VT100Screen.h"
#import "VT100Terminal.h"
#include "iTermFileDescriptorClient.h"

#include <unistd.h>

@class QLPreviewPanel;

NSString *const kCurrentSessionDidChange = @"kCurrentSessionDidChange";
NSString *const kTerminalWindowControllerWasCreatedNotification = @"kTerminalWindowControllerWasCreatedNotification";

static NSString *const kWindowNameFormat = @"iTerm Window %d";

#define PtyLog DLog

// Constants for saved window arrangement key names.
static NSString* TERMINAL_ARRANGEMENT_OLD_X_ORIGIN = @"Old X Origin";
static NSString* TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN = @"Old Y Origin";
static NSString* TERMINAL_ARRANGEMENT_OLD_WIDTH = @"Old Width";
static NSString* TERMINAL_ARRANGEMENT_OLD_HEIGHT = @"Old Height";
static NSString* TERMINAL_ARRANGEMENT_X_ORIGIN = @"X Origin";
static NSString* TERMINAL_ARRANGEMENT_Y_ORIGIN = @"Y Origin";
static NSString* TERMINAL_ARRANGEMENT_WIDTH = @"Width";
static NSString* TERMINAL_ARRANGEMENT_HEIGHT = @"Height";
static NSString* TERMINAL_ARRANGEMENT_EDGE_SPANNING_OFF = @"Edge Spanning Off";  // Deprecated. Included in window type now.
static NSString* TERMINAL_ARRANGEMENT_TABS = @"Tabs";
static NSString* TERMINAL_ARRANGEMENT_FULLSCREEN = @"Fullscreen";
static NSString* TERMINAL_ARRANGEMENT_LION_FULLSCREEN = @"LionFullscreen";
static NSString* TERMINAL_ARRANGEMENT_WINDOW_TYPE = @"Window Type";
static NSString* TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE = @"Saved Window Type";  // Only relevant for fullscreen
static NSString* TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX = @"Selected Tab Index";
static NSString* TERMINAL_ARRANGEMENT_SCREEN_INDEX = @"Screen";
static NSString* TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING = @"Hide After Opening";
static NSString* TERMINAL_ARRANGEMENT_DESIRED_COLUMNS = @"Desired Columns";
static NSString* TERMINAL_ARRANGEMENT_DESIRED_ROWS = @"Desired Rows";
static NSString* TERMINAL_ARRANGEMENT_IS_HOTKEY_WINDOW = @"Is Hotkey Window";

static NSString* TERMINAL_GUID = @"TerminalGuid";
static NSString* TERMINAL_ARRANGEMENT_HAS_TOOLBELT = @"Has Toolbelt";
static NSString* TERMINAL_ARRANGEMENT_HIDING_TOOLBELT_SHOULD_RESIZE_WINDOW = @"Hiding Toolbelt Should Resize Window";

@interface NSWindow (private)
- (void)setBottomCornerRounded:(BOOL)rounded;
@end

@interface PseudoTerminal () <
    iTermTabBarControlViewDelegate,
    iTermPasswordManagerDelegate,
    PTYTabDelegate,
    iTermRootTerminalViewDelegate,
    iTermToolbeltViewDelegate>
@property(nonatomic, assign) BOOL windowInitialized;

// Session ID of session that currently has an auto-command history window open
@property(nonatomic, copy) NSString *autoCommandHistorySessionGuid;
@property(nonatomic, assign) NSTimeInterval timeOfLastResize;

// Used for delaying and coalescing title changes. After a title change request
// is received the new title is stored here and a .1 second delay begins. If a
// new request is made before the timer is up this property gets changed. It is
// reset to nil after the change is made in the window.
@property(nonatomic, copy) NSString *desiredTitle;
@end

@implementation PseudoTerminal {
    NSPoint preferredOrigin_;

    // This is a reference to the window's content view, here for convenience because it has
    // the right type.
    __unsafe_unretained iTermRootTerminalView *_contentView;

    ////////////////////////////////////////////////////////////////////////////
    // Parameter Panel
    // A bookmark may have metasyntactic variables like $$FOO$$ in the command.
    // When opening such a bookmark, pop up a sheet and ask the user to fill in
    // the value. These fields belong to that sheet.
    IBOutlet NSTextField *parameterName;
    IBOutlet NSPanel *parameterPanel;
    IBOutlet NSTextField *parameterValue;
    IBOutlet NSTextField *parameterPrompt;

    ////////////////////////////////////////////////////////////////////////////
    // Instant Replay
    iTermInstantReplayWindowController *_instantReplayWindowController;

    // This is either 0 or 1. If 1, then a tab item is in the process of being
    // added and the tabBarControl will be shown if it is added successfully
    // if it's not currently shown.
    int tabViewItemsBeingAdded;

    ////////////////////////////////////////////////////////////////////////////
    // Miscellaneous

    // Is the transparency setting respected?
    BOOL useTransparency_;

    // Is this a full screen window?
    BOOL _fullScreen;

    // When you enter full-screen mode the old frame size is saved here. When
    // full-screen mode is exited that frame is restored.
    NSRect oldFrame_;
    BOOL oldFrameSizeIsBogus_;  // If set, the size in oldFrame_ shouldn't be used.

    // When you enter fullscreen mode, the old use transparency setting is
    // saved, and then restored when you exit FS unless it was changed
    // by the user.
    BOOL oldUseTransparency_;
    BOOL restoreUseTransparency_;

    // How input should be broadcast (or not).
    BroadcastMode broadcastMode_;

    // When sending input to all sessions we temporarily change the background
    // color. This stores the normal background color so we can restore to it.
    NSColor *normalBackgroundColor;

    // This prevents recursive resizing.
    BOOL _resizeInProgressFlag;

    // There is a scheme for saving window positions. Each window is assigned
    // a number, and the positions are stored by window name. The window name
    // includes its unique number. This variable gives this window's number.
    int uniqueNumber_;

    // This is set while toggling full screen. It prevents windowDidResignMain
    // from trying to exit fullscreen mode in the midst of toggling it.
    BOOL togglingFullScreen_;

    // True while entering lion fullscreen (the animation is going on)
    BOOL togglingLionFullScreen_;

    PasteboardHistoryWindowController* pbHistoryView;
    CommandHistoryPopupWindowController *commandHistoryPopup;
    DirectoriesPopupWindowController *_directoriesPopupWindowController;
    AutocompleteView* autocompleteView;

    // This is a hack to support old applescript code that set the window size
    // before adding a session to it, which doesn't really make sense now that
    // textviews and windows are loosely coupled.
    int nextSessionRows_;
    int nextSessionColumns_;

    iTermWindowType windowType_;
    // Window type before entering fullscreen. Only relevant if in/entering fullscreen.
    iTermWindowType savedWindowType_;
    BOOL haveScreenPreference_;
    int screenNumber_;

    // Window number, used for keyboard shortcut to select a window.
    // This value is 0-based while the UI is 1-based.
    int number_;

    // True if this window was created by dragging a tab from another window.
    // Affects how its size is set when the number of tabview items changes.
    BOOL wasDraggedFromAnotherWindow_;

    // In the process of zooming in Lion or later.
    BOOL zooming_;

    // Time since 1970 of last window resize
    double lastResizeTime_;

    NSMutableSet *broadcastViewIds_;
    NSTimeInterval findCursorStartTime_;

    // Accumulated pinch magnification amount.
    double cumulativeMag_;

    // Time of last magnification change.
    NSTimeInterval lastMagChangeTime_;

    // In 10.7 style full screen mode
    BOOL lionFullScreen_;

    IBOutlet NSPanel *coprocesssPanel_;
    IBOutlet NSButton *coprocessOkButton_;
    IBOutlet NSComboBox *coprocessCommand_;

    NSDictionary *lastArrangement_;
    BOOL wellFormed_;

    BOOL exitingLionFullscreen_;

    // If positive, then any window resizing that happens is driven by tmux and
    // shoudn't be reported back to tmux as a user-originated resize.
    int tmuxOriginatedResizeInProgress_;

    BOOL liveResize_;
    BOOL postponedTmuxTabLayoutChange_;

    // Recalls if this was a hide-after-opening window.
    BOOL hideAfterOpening_;

    // After dealloc starts, the restorable state should not be updated
    // because the window's state is a shambles.
    BOOL doNotSetRestorableState_;

    // For top/left/bottom of screen windows, this is the size it really wants to be.
    // Initialized to -1 in -init and then set to the size of the first session
    // forever.
    int desiredRows_, desiredColumns_;

    // If set, then hiding the toolbelt should shrink the window by the toolbelt's width.
    BOOL hidingToolbeltShouldResizeWindow_;

    // If set, prevents hidingToolbeltShouldResizeWindow_ from getting its value inferred based on
    // the window's frame.
    BOOL hidingToolbeltShouldResizeWindowInitialized_;

#if ENABLE_SHORTCUT_ACCESSORY
    // This thing is a freaking horror show, and it's what people are talking about when they say
    // that software quality has declined in OS X.
    //
    // OS 10.10 added a barely documented API to add an accessory view to the title bar (it's
    // mentioned in the release notes and public header files and methods exist, but that's it).
    // It creates auto layout constraints in the title bar. For some reason, that causes EVERYTHING
    // to get auto layout. Autoresizing masks become constraints throughout the window. This does
    // not work well, in particular with the toolbelt. The toolbelt is designed to allow the window
    // to be too short to show all its contents, in which case some tools will get partially or
    // completely clipped. When auto layout is used, the window is prevented from being shorter than
    // the sum of the tools' minimum heights. This is especially bad when you create a tmux window,
    // because then you get a gray bar on the bottom where the window's height exceeds the content's
    // height, simply because you have a (possibly invisible!) toolbelt that can't shrink. But it
    // gets worse. I wrote a replacement NSSplitView that collapses tools when they don't fit. Auto
    // layout is so broken that it lags when the window or toolbelt is resized. Sometimes it catches
    // up when the drag is done, and sometimes it just leaves things in a broken state. I tried
    // removing auto layout from the toolbelt by setting translatesAutoresizingMaskIntoConstraints
    // to NO, but it's not enough to set that on ToolbeltView. In fact, it's not enough to set it on
    // every view that I create within the toolbelt. If any view anywhere in the view hierarchy in
    // the toolbelt has a constraint, the whole thing gets broken and laggy on resize. For example,
    // a table view will create various internal subviews. Those will end up with auto layout
    // constraints. There's no (sane) way for me to set translatesAutoresizingMaskIntoConstraints on
    // them to prevent the viral spread of auto layout garbage. So for now, the toolbelt hangs on to
    // life because it remains possible to have no auto-layout as long as you don't use title bar
    // accessories. To see the whole mess, check out the clusterfuck[123] branches.
    iTermWindowShortcutLabelTitlebarAccessoryViewController *_shortcutAccessoryViewController;
#endif

    // Is there a pending delayed-perform of enterFullScreen:? Used to figure
    // out if it's safe to toggle Lion full screen since only one can go at a time.
    BOOL _haveDelayedEnterFullScreenMode;

    BOOL _parameterPanelCanceled;

    // Number of tabs since last change.
    NSInteger _previousNumberOfTabs;
}

+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement {
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
        [PTYTab registerSessionsInArrangement:tabArrangement];
    }
}

+ (NSInteger)styleMaskForWindowType:(iTermWindowType)windowType
                   hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    NSInteger mask = 0;
    if (hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) {
        mask = NSNonactivatingPanelMask;
    }
    switch (windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            return mask | NSBorderlessWindowMask | NSResizableWindowMask;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return mask | NSBorderlessWindowMask;

        default:
            return (mask |
                    NSTitledWindowMask |
                    NSClosableWindowMask |
                    NSMiniaturizableWindowMask |
                    NSResizableWindowMask |
                    NSTexturedBackgroundWindowMask);
    }
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        self.autoCommandHistorySessionGuid = nil;
    }
    return self;
}

- (instancetype)initWithSmartLayout:(BOOL)smartLayout
                         windowType:(iTermWindowType)windowType
                    savedWindowType:(iTermWindowType)savedWindowType
                             screen:(int)screenNumber {
    return [self initWithSmartLayout:smartLayout
                          windowType:windowType
                     savedWindowType:savedWindowType
                              screen:screenNumber
                    hotkeyWindowType:iTermHotkeyWindowTypeNone];
}

- (instancetype)initWithSmartLayout:(BOOL)smartLayout
                         windowType:(iTermWindowType)windowType
                    savedWindowType:(iTermWindowType)savedWindowType
                             screen:(int)screenNumber
                   hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    self = [self initWithWindowNibName:@"PseudoTerminal"];
    NSAssert(self, @"initWithWindowNibName returned nil");
    if (self) {
        [self finishInitializationWithSmartLayout:smartLayout
                                       windowType:windowType
                                  savedWindowType:savedWindowType
                                           screen:screenNumber
                                 hotkeyWindowType:hotkeyWindowType];
    }
    return self;
}

- (void)finishInitializationWithSmartLayout:(BOOL)smartLayout
                                 windowType:(iTermWindowType)windowType
                            savedWindowType:(iTermWindowType)savedWindowType
                                     screen:(int)screenNumber
                           hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    DLog(@"-[%p finishInitializationWithSmartLayout:%@ windowType:%d screen:%d hotkeyWindowType:%@ ",
         self,
         smartLayout ? @"YES" : @"NO",
         windowType,
         screenNumber,
         @(hotkeyWindowType));

    // Force the nib to load
    [self window];
    if ((windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN ||
         windowType == WINDOW_TYPE_LION_FULL_SCREEN) &&
        screenNumber == -1) {
        NSUInteger n = [[NSScreen screens] indexOfObjectIdenticalTo:[[self window] screen]];
        if (n == NSNotFound) {
            DLog(@"Convert default screen to screen number: No screen matches the window's screen so using main screen");
            screenNumber = 0;
        } else {
            DLog(@"Convert default screen to screen number: System chose screen %lu", (unsigned long)n);
            screenNumber = n;
        }
    } else if (screenNumber == -2) {
        // Select screen with cursor.
        NSScreen *screenWithCursor = [NSScreen screenWithCursor];
        NSUInteger preference = [[NSScreen screens] indexOfObject:screenWithCursor];
        if (preference == NSNotFound) {
            preference = 0;
        }
        screenNumber = preference;
    }
    if (windowType == WINDOW_TYPE_TOP ||
        windowType == WINDOW_TYPE_TOP_PARTIAL ||
        windowType == WINDOW_TYPE_BOTTOM ||
        windowType == WINDOW_TYPE_BOTTOM_PARTIAL ||
        windowType == WINDOW_TYPE_LEFT ||
        windowType == WINDOW_TYPE_LEFT_PARTIAL ||
        windowType == WINDOW_TYPE_RIGHT ||
        windowType == WINDOW_TYPE_RIGHT_PARTIAL) {
        PtyLog(@"Window type is %d so disable smart layout", windowType);
        smartLayout = NO;
    }
    if (windowType == WINDOW_TYPE_NORMAL) {
        // If you create a window with a minimize button and the menu bar is hidden then the
        // minimize button is disabled. Currently the only window type with a miniaturize button
        // is NORMAL.
        [self showMenuBar];
    }
    // Force the nib to load
    [self window];
    windowType_ = windowType;
    broadcastViewIds_ = [[NSMutableSet alloc] init];

    NSScreen* screen = nil;
    if (screenNumber == -1 || screenNumber >= [[NSScreen screens] count])  {
        screen = [[self window] screen];
        DLog(@"Screen number %d is out of range [0,%d] so using 0",
             screenNumber, (int)[[NSScreen screens] count]);
        screenNumber_ = 0;
        haveScreenPreference_ = NO;
    } else if (screenNumber >= 0) {
        DLog(@"Selecting screen number %d", screenNumber);
        screen = [[NSScreen screens] objectAtIndex:screenNumber];
        screenNumber_ = screenNumber;
        haveScreenPreference_ = YES;
    }

    desiredRows_ = desiredColumns_ = -1;
    NSRect initialFrame;
    switch (windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            initialFrame = [screen visibleFrameIgnoringHiddenDock];
            break;

        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            oldFrame_ = [[self window] frame];
            // The size is just whatever was in the .xib file's window, which is silly.
            // By setting this flag, we'll use the window size necessary to hold the current
            // session's rows/columns setting when exiting fullscreen.
            oldFrameSizeIsBogus_ = YES;
            initialFrame = [self traditionalFullScreenFrameForScreen:screen];
            break;

        default:
            PtyLog(@"Unknown window type: %d", (int)windowType);
            NSLog(@"Unknown window type: %d", (int)windowType);
            // fall through
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            // Use the system-supplied frame which has a reasonable origin. It may
            // be overridden by smart window placement or a saved window location.
            initialFrame = [[self window] frame];
            if (haveScreenPreference_) {
                // Move the frame to the desired screen
                NSScreen* baseScreen = [[self window] screen];
                NSPoint basePoint = [baseScreen visibleFrame].origin;
                double xoffset = initialFrame.origin.x - basePoint.x;
                double yoffset = initialFrame.origin.y - basePoint.y;
                NSPoint destPoint = [screen visibleFrame].origin;

                DLog(@"Assigned screen has origin %@, destination screen has origin %@", NSStringFromPoint(baseScreen.visibleFrame.origin),
                     NSStringFromPoint(destPoint));
                destPoint.x += xoffset;
                destPoint.y += yoffset;
                initialFrame.origin = destPoint;
                DLog(@"New initial frame is %@", NSStringFromRect(initialFrame));
                // Make sure the top-right corner of the window is on the screen too
                NSRect destScreenFrame = [screen visibleFrame];
                double xover = destPoint.x + initialFrame.size.width - (destScreenFrame.origin.x + destScreenFrame.size.width);
                double yover = destPoint.y + initialFrame.size.height - (destScreenFrame.origin.y + destScreenFrame.size.height);
                if (xover > 0) {
                    destPoint.x -= xover;
                }
                if (yover > 0) {
                    destPoint.y -= yover;
                }
                DLog(@"after adjusting top right, initial origin is %@", NSStringFromPoint(destPoint));
                [[self window] setFrameOrigin:destPoint];
            }
            break;
    }
    preferredOrigin_ = initialFrame.origin;

    PtyLog(@"finishInitializationWithSmartLayout - initWithContentRect");
    // create the window programmatically with appropriate style mask
    NSUInteger styleMask;
    if (windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        // We want to set the style mask to the window's non-fullscreen appearance so we're prepared
        // to exit fullscreen with the right style.
        styleMask = [PseudoTerminal styleMaskForWindowType:savedWindowType hotkeyWindowType:hotkeyWindowType];
    } else {
        styleMask = [PseudoTerminal styleMaskForWindowType:windowType hotkeyWindowType:hotkeyWindowType];
    }
    savedWindowType_ = savedWindowType;

    DLog(@"initWithContentRect:%@ styleMask:%d", [NSValue valueWithRect:initialFrame], (int)styleMask);
    iTermTerminalWindow *myWindow;
    Class windowClass = (hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) ? [iTermPanel class] : [iTermWindow class];
    myWindow = [[windowClass alloc] initWithContentRect:initialFrame
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:(hotkeyWindowType != iTermHotkeyWindowTypeNone)];
    if (windowType != WINDOW_TYPE_LION_FULL_SCREEN) {
        // For some reason, you don't always get the frame you requested. I saw
        // this on OS 10.10 when creating normal windows on a 2-screen display. The
        // frames were within the visible frame of screen #2.
        // However, setting the frame at this point while restoring a Lion fullscreen window causes
        // it to appear with a title bar. TODO: Test if lion fullscreen windows restore on the right
        // monitor.
        [myWindow setFrame:initialFrame display:NO];
    }

    [myWindow setHasShadow:(windowType == WINDOW_TYPE_NORMAL)];

    DLog(@"Create window %@", myWindow);

    PtyLog(@"finishInitializationWithSmartLayout - new window is at %p", myWindow);
    [self setWindow:myWindow];
    [myWindow release];

    // This had been in iTerm2 for years and was removed, but I can't tell why. Issue 3833 reveals
    // that it is still needed, at least on OS 10.9.
    if ([myWindow respondsToSelector:@selector(_setContentHasShadow:)]) {
        [myWindow _setContentHasShadow:NO];
    }

    _fullScreen = (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN);
    _contentView =
        [[[iTermRootTerminalView alloc] initWithFrame:[self.window.contentView frame]
                                                color:[NSColor windowBackgroundColor]
                                       tabBarDelegate:self
                                             delegate:self] autorelease];
    self.window.contentView = _contentView;
    if (hotkeyWindowType == iTermHotkeyWindowTypeNone) {
        self.window.alphaValue = 1;
    } else {
        self.window.alphaValue = 0;
    }
    self.window.opaque = NO;

    normalBackgroundColor = [_contentView color];

    _resizeInProgressFlag = NO;

    hidingToolbeltShouldResizeWindow_ = NO;
    // hidingToolbeltShouldResizeWindow_ can only be set to the right value after the window's frame
    // has been established. The window is always fiddled with (e.g., adding tabs) after this call
    // returns, so we'll do it on the next spin of the runloop.
    [self performSelector:@selector(finishToolbeltInitialization) withObject:nil afterDelay:0];

    if (!smartLayout || windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        PtyLog(@"no smart layout or is full screen, so set layout done");
        [self.ptyWindow setLayoutDone];
    }

    if (styleMask & NSTitledWindowMask) {
        if ([[self window] respondsToSelector:@selector(setBottomCornerRounded:)]) {
            // TODO: Why is this here?
            self.window.bottomCornerRounded = NO;
        }
    }

    [self updateTabBarStyle];
    self.window.delegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateWindowNumberVisibility:)
                                                 name:kUpdateLabelsNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshTerminal:)
                                                 name:kRefreshTerminalNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_scrollerStyleChanged:)
                                                 name:@"NSPreferredScrollerStyleDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tmuxFontDidChange:)
                                                 name:@"kPTYSessionTmuxFontDidChange"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadBookmarks)
                                                 name:kReloadAllProfiles
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hideToolbelt)
                                                 name:kToolbeltShouldHide
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateFullScreenTabBar:)
                                                 name:kShowFullscreenTabsSettingDidChange
                                               object:nil];
    PtyLog(@"set window inited");
    self.windowInitialized = YES;
    useTransparency_ = YES;
    number_ = [[iTermController sharedInstance] allocateWindowNumber];
    if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [self hideMenuBar];
    }

    // Update the collection behavior.
    self.hotkeyWindowType = hotkeyWindowType;

    wellFormed_ = YES;
    [[self window] setRestorable:YES];
    [[self window] setRestorationClass:[PseudoTerminalRestorer class]];
    self.terminalGuid = [NSString stringWithFormat:@"pty-%@", [NSString uuid]];

#if ENABLE_SHORTCUT_ACCESSORY
    if ([self.window respondsToSelector:@selector(addTitlebarAccessoryViewController:)]) {
        _shortcutAccessoryViewController =
            [[iTermWindowShortcutLabelTitlebarAccessoryViewController alloc] initWithNibName:@"iTermWindowShortcutAccessoryView"
                                                                                      bundle:nil];
    }
    if ((self.window.styleMask & NSTitledWindowMask) && _shortcutAccessoryViewController) {
        [self.window addTitlebarAccessoryViewController:_shortcutAccessoryViewController];
        [self updateWindowNumberVisibility:nil];
    }
    _shortcutAccessoryViewController.ordinal = number_ + 1;
#endif
    [[NSNotificationCenter defaultCenter] postNotificationName:kTerminalWindowControllerWasCreatedNotification object:self];
    DLog(@"Done initializing PseudoTerminal %@", self);
}

- (BOOL)isHotKeyWindow {
    return self.hotkeyWindowType != iTermHotkeyWindowTypeNone;
}

- (BOOL)isFloatingHotKeyWindow {
    return self.isHotKeyWindow && [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] floats];
}

- (void)setHotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    _hotkeyWindowType = hotkeyWindowType;
    switch (hotkeyWindowType) {
        case iTermHotkeyWindowTypeNone:
            // This allows the window to enter Lion fullscreen.
            [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];
            break;
            
        case iTermHotkeyWindowTypeRegular:
        case iTermHotkeyWindowTypeFloatingPanel:
        case iTermHotkeyWindowTypeFloatingWindow:
            [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorFullScreenAuxiliary];
            [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorIgnoresCycle];
            [[self window] setCollectionBehavior:[[self window] collectionBehavior] & ~NSWindowCollectionBehaviorParticipatesInCycle];
            break;
    }
}

- (void)finishToolbeltInitialization {
    // If the right edge of the window is "near" the right edge of the screen, then hiding an
    // initially visible toolbelt should not resize the window, the theory being that the user
    // wanted the window to be near the right edge of the screen. This will probably sow confusion
    // but may cause more good than harm. We'll see how loud they yell.
    if (!hidingToolbeltShouldResizeWindowInitialized_) {
        BOOL rightEdgeOfWindowIsNearRightEdgeOfScreen;
        CGFloat distanceFromRightEdgeOfWindowToRightEdgeOfScreen = fabs(NSMaxX(self.window.frame) - NSMaxX(self.window.screen.visibleFrame));
        rightEdgeOfWindowIsNearRightEdgeOfScreen = (distanceFromRightEdgeOfWindowToRightEdgeOfScreen < 10);
        hidingToolbeltShouldResizeWindow_ = !rightEdgeOfWindowIsNearRightEdgeOfScreen;

        // This isn't really necessary since this method isn't called a second time, but just to be
        // safe we'll set it.
        hidingToolbeltShouldResizeWindowInitialized_ = YES;
    }
}

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    [_contentView shutdown];

    [self closeInstantReplayWindow];
    doNotSetRestorableState_ = YES;
    wellFormed_ = NO;

    // Do not assume that [self window] is valid here. It may have been freed.
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    // Release all our sessions
    NSTabViewItem *aTabViewItem;
    while ([_contentView.tabView numberOfTabViewItems])  {
        aTabViewItem = [_contentView.tabView tabViewItemAtIndex:0];
        [[aTabViewItem identifier] terminateAllSessions];
        PTYTab* theTab = [aTabViewItem identifier];
        [theTab setParentWindow:nil];
        theTab.delegate = nil;
        [_contentView.tabView removeTabViewItem:aTabViewItem];
    }

    if ([[iTermController sharedInstance] currentTerminal] == self) {
        NSLog(@"Red alert! Current terminal is being freed!");
        [[iTermController sharedInstance] setCurrentTerminal:nil];
    }
    [broadcastViewIds_ release];
    [autocompleteView shutdown];
    [commandHistoryPopup shutdown];
    [_directoriesPopupWindowController shutdown];
    [pbHistoryView shutdown];
    [pbHistoryView release];
    [commandHistoryPopup release];
    [_directoriesPopupWindowController release];
    [autocompleteView release];
    [_terminalGuid release];
    [lastArrangement_ release];
    [_autoCommandHistorySessionGuid release];
#if ENABLE_SHORTCUT_ACCESSORY
    [_shortcutAccessoryViewController release];
#endif
    [_didEnterLionFullscreen release];
    [_desiredTitle release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p tabs=%d window=%@>",
            [self class], self, (int)[self numberOfTabs], [self window]];
}

+ (BOOL)useElCapitanFullScreenLogic {
    return [NSWindow instancesRespondToSelector:@selector(maxFullScreenContentSize)];
}

- (BOOL)tabBarVisibleOnTop {
    return ([self tabBarShouldBeVisible] &&
            [iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab);
}

- (BOOL)divisionViewShouldBeVisible {
    // The division is only shown if there is a title bar and no tab bar on top. There
    // are cases in fullscreen (e.g., when entering Lion fullscreen) when the
    // window doesn't have a title bar but also isn't borderless we also check
    // if we're in fullscreen.
    return ([iTermPreferences boolForKey:kPreferenceKeyEnableDivisionView] &&
            !togglingFullScreen_ &&
            (self.window.styleMask & NSTitledWindowMask) &&
            ![self anyFullScreen] &&
            ![self tabBarVisibleOnTop]);
}

- (void)rootTerminalViewDidResizeContentArea {
    // Fixes an analog of issue 4323 that happens with left-side tabs. More
    // details in -toolbeltDidFinishGrowing.
    [self fitTabsToWindow];
}

- (CGFloat)tabviewWidth {
    return _contentView.tabviewWidth;
}

- (void)toggleBroadcastingToCurrentSession:(id)sender
{
    [self toggleBroadcastingInputToSession:[self currentSession]];
}

- (void)notifyTmuxOfWindowResize {
    DLog(@"notifyTmuxOfWindowResize from:\n%@", [NSThread callStackSymbols]);
    NSArray *tmuxControllers = [self uniqueTmuxControllers];
    if (tmuxControllers.count && !tmuxOriginatedResizeInProgress_) {
        for (TmuxController *controller in tmuxControllers) {
            [controller windowDidResize:self];
        }
    }
}

- (BOOL)shouldShowToolbelt {
    return _contentView.shouldShowToolbelt;
}

- (void)hideToolbelt {
    if (_contentView.shouldShowToolbelt) {
        [self toggleToolbeltVisibility:nil];
    }
}

- (IBAction)setDefaultToolbeltWidth:(id)sender {
    [iTermPreferences setFloat:_contentView.toolbelt.frame.size.width
                        forKey:kPreferenceKeyDefaultToolbeltWidth];
}

- (IBAction)toggleToolbeltVisibility:(id)sender {
    _contentView.shouldShowToolbelt = !_contentView.shouldShowToolbelt;
    BOOL didResizeWindow = NO;
    if (_contentView.shouldShowToolbelt) {
        if (![self anyFullScreen]) {
            // Tweak the window's frame to avoid shrinking content, if possible.
            NSRect windowFrame = self.window.frame;
            windowFrame.size.width += _contentView.toolbeltWidth;
            NSRect screenFrame = self.window.screen.visibleFrame;
            CGFloat rightLimit = NSMaxX(screenFrame);
            CGFloat overage = NSMaxX(windowFrame) - rightLimit;
            if (overage > 0) {
                // Compensate by making the toolbelt a little smaller, unless that would make it too
                // small.
                if (_contentView.toolbeltWidth - overage > 100) {
                    _contentView.toolbeltWidth = _contentView.toolbeltWidth - overage;
                    windowFrame.size.width -= overage;
                    overage = 0;
                }
            }
            if (overage <= 0 && !NSEqualRects(self.window.frame, windowFrame)) {
                didResizeWindow = YES;
                [self.window setFrame:windowFrame display:YES];
            }
            hidingToolbeltShouldResizeWindow_ = didResizeWindow;
        }

        [self refreshTools];
    } else {
        if (![self anyFullScreen] && hidingToolbeltShouldResizeWindow_) {
            NSRect windowFrame = self.window.frame;
            windowFrame.size.width -= _contentView.toolbeltWidth;
            didResizeWindow = YES;
            [self.window setFrame:windowFrame display:YES];
        }
    }

    if (!didResizeWindow) {
        [self repositionWidgets];
        [self notifyTmuxOfWindowResize];
    }
}

- (void)popupWillClose:(iTermPopupWindowController *)popup {
    if (popup == pbHistoryView) {
        [pbHistoryView autorelease];
        pbHistoryView = nil;
    } else if (popup == commandHistoryPopup) {
        [commandHistoryPopup autorelease];
        commandHistoryPopup = nil;
    } else if (popup == _directoriesPopupWindowController) {
        [_directoriesPopupWindowController autorelease];
        _directoriesPopupWindowController = nil;
    } else if (popup == autocompleteView) {
        [autocompleteView autorelease];
        autocompleteView = nil;
    }
    [self.window makeKeyWindow];
}

- (void)tmuxFontDidChange:(NSNotification *)notification
{
    if ([[self uniqueTmuxControllers] count]) {
        [self refreshTmuxLayoutsAndWindow];
    }
}

- (NSWindowController<iTermWindowController> *)terminalDraggedFromAnotherWindowAtPoint:(NSPoint)point
{
    PseudoTerminal *term;

    int screen;
    if (windowType_ != WINDOW_TYPE_NORMAL) {
        screen = [self _screenAtPoint:point];
    } else {
        screen = -1;
    }

    // create a new terminal window
    int newWindowType;
    switch (windowType_) {
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            newWindowType = windowType_;
            break;

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            newWindowType = WINDOW_TYPE_NORMAL;
            break;

        default:
            newWindowType = windowType_;
    }
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                             windowType:newWindowType
                                        savedWindowType:WINDOW_TYPE_NORMAL
                                                 screen:screen] autorelease];
    if (term == nil) {
        return nil;
    }
    term->wasDraggedFromAnotherWindow_ = YES;
    [term copySettingsFrom:self];

    [[iTermController sharedInstance] addTerminalWindow:term];

    if (newWindowType == WINDOW_TYPE_NORMAL ||
        newWindowType == WINDOW_TYPE_NO_TITLE_BAR) {
        [[term window] setFrameOrigin:point];
    } else if (newWindowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [[term window] makeKeyAndOrderFront:nil];
        [term hideMenuBar];
    }

    return term;
}

- (int)number
{
    return number_;
}

- (void)setFrameValue:(NSValue *)value
{
    [[self window] setFrame:[value rectValue] display:YES];
}

- (__kindof iTermTerminalWindow *)ptyWindow {
    return (iTermTerminalWindow *)[self window];
}

- (PTYTab *)tabWithUniqueId:(int)uniqueId {
    for (int i = 0; i < [self numberOfTabs]; i++) {
        PTYTab *tab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        if (tab.uniqueId == uniqueId) {
            return tab;
        }
    }
    return nil;
}

- (NSScreen*)screen {
    NSArray* screens = [NSScreen screens];
    if (!haveScreenPreference_) {
        DLog(@"No screen preference so using the window's current screen");
        return self.window.screen;
    }
    if ([screens count] > screenNumber_) {
        DLog(@"Screen preference %d respected", screenNumber_);
        return screens[screenNumber_];
    } else {
        DLog(@"Screen preference %d out of range so using main screen.", screenNumber_);
        return [NSScreen mainScreen];
    }
}

- (void)magnifyWithEvent:(NSEvent *)event
{
    if ([iTermAdvancedSettingsModel pinchToChangeFontSizeDisabled]) {
        return;
    }
    const double kMagTimeout = 0.2;
    if ([[NSDate date] timeIntervalSinceDate:[NSDate dateWithTimeIntervalSince1970:lastMagChangeTime_]] > kMagTimeout) {
        cumulativeMag_ = 0;
    }
    lastMagChangeTime_ = [[NSDate date] timeIntervalSince1970];

    double factor = [event magnification];
    cumulativeMag_ += factor;
    int dir;
    const double kMagnifyThreshold = 0.4 ;
    if (cumulativeMag_ > kMagnifyThreshold) {
        dir = 1;
    } else if (cumulativeMag_ < -kMagnifyThreshold) {
        dir = -1;
    } else {
        return;
    }
    cumulativeMag_ = 0;
    [[self currentSession] changeFontSizeDirection:dir];
}

- (void)swipeWithEvent:(NSEvent *)event
{
    [[[self currentSession] textview] swipeWithEvent:event];
}

- (void)selectSessionAtIndexAction:(id)sender
{
    [_contentView.tabView selectTabViewItemAtIndex:[sender tag]];
}

- (NSInteger)indexOfTab:(PTYTab*)aTab
{
    NSArray* items = [_contentView.tabView tabViewItems];
    for (int i = 0; i < [items count]; i++) {
        NSTabViewItem *tabViewItem = [items objectAtIndex:i];
        if ([tabViewItem identifier] == aTab) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)newSessionInTabAtIndex:(id)sender
{
    Profile* profile = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (profile) {
        [self createTabWithProfile:profile withCommand:nil];
    }
}

- (void)closeSession:(PTYSession *)aSession soft:(BOOL)soft {
    if (!soft &&
        [aSession isTmuxClient] &&
        [[aSession tmuxController] isAttached]) {
        [[aSession tmuxController] killWindowPane:[aSession tmuxPane]];
    } else {
        PTYTab *tab = [self tabForSession:aSession];
        if ([[tab sessions] count] == 1) {
            [self closeTab:tab soft:soft];
        } else {
            [aSession terminate];
        }
    }
}

- (PTYTab *)tabForSession:(PTYSession *)session {
    // This is kind of cheating; we shouldn't assume that a session's delegate
    // is a tab. But it always is, and it would be slow to search.
    return (PTYTab *)session.delegate;
}

// Allow frame to go off-screen while hotkey window is sliding in or out.
- (BOOL)terminalWindowShouldConstrainFrameToScreen {
    iTermProfileHotKey *profileHotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
    return !([profileHotKey rollingIn] || [profileHotKey rollingOut]);
}

- (void)closeSession:(PTYSession *)aSession {
    [self closeSession:aSession soft:NO];
}

- (void)softCloseSession:(PTYSession *)aSession
{
    [self closeSession:aSession soft:YES];
}

- (iTermWindowType)windowType {
    return windowType_;
}

// Convert a lexicographically sorted array like ["a", "b", "b", "c"] into
// ["a", "2 instances of \"b\"", "c"].
- (NSArray *)uniqWithCounts:(NSArray *)a
{
  NSMutableArray *result = [NSMutableArray array];

  for (int i = 0; i < [a count]; ) {
    int c = 0;
    NSString *thisValue = [a objectAtIndex:i];
    int j;
    for (j = i; j < [a count]; j++) {
      if (![[a objectAtIndex:j] isEqualToString:thisValue]) {
        break;
      }
      ++c;
    }
    if (c > 1) {
      [result addObject:[NSString stringWithFormat:@"%d instances of \"%@\"", c, thisValue]];
    } else {
      [result addObject:thisValue];
    }
    i = j;
  }

  return result;
}

// Convert an array ["x", "y", "z"] into a nicely formatted English string like
// "x, y, and z".
- (NSString *)prettyListOfStrings:(NSArray *)a
{
  if ([a count] < 2) {
    return [a componentsJoinedByString:@", "];
  }

  NSMutableString *result = [NSMutableString string];
  if ([a count] == 2) {
    [result appendFormat:@"%@ and %@", [a objectAtIndex:0], [a lastObject]];
  } else {
    [result appendString:[[a subarrayWithRange:NSMakeRange(0, [a count] - 1)] componentsJoinedByString:@", "]];
    [result appendFormat:@", and %@", [a lastObject]];
  }
  return result;
}

- (BOOL)confirmCloseForSessions:(NSArray *)sessions
                     identifier:(NSString*)identifier
                    genericName:(NSString *)genericName
{
    NSMutableArray *names = [NSMutableArray array];
    for (PTYSession *aSession in sessions) {
        if (![aSession exited]) {
            [names addObjectsFromArray:[aSession childJobNames]];
        }
    }
    NSString *message;
    NSArray *sortedNames = [names sortedArrayUsingSelector:@selector(compare:)];
    sortedNames = [self uniqWithCounts:sortedNames];
    if ([sortedNames count] == 1) {
        message = [NSString stringWithFormat:@"%@ is running %@.", identifier, [sortedNames objectAtIndex:0]];
    } else if ([sortedNames count] > 1 && [sortedNames count] <= 10) {
        message = [NSString stringWithFormat:@"%@ is running the following jobs: %@.", identifier, [self prettyListOfStrings:sortedNames]];
    } else if ([sortedNames count] > 10) {
        message = [NSString stringWithFormat:@"%@ is running the following jobs: %@, plus %ld %@.",
                   identifier,
                   [self prettyListOfStrings:sortedNames],
                   (long)[sortedNames count] - 10,
                   [sortedNames count] == 11 ? @"other" : @"others"];
    } else {
        message = [NSString stringWithFormat:@"%@ will be closed.", identifier];
    }
    // The PseudoTerminal might close while the dialog is open so keep it around for now.
    [[self retain] autorelease];
    return NSRunAlertPanel([NSString stringWithFormat:@"Close %@?", genericName],
                           @"%@",
                           @"OK",
                           @"Cancel",
                           nil,
                           message) == NSAlertDefaultReturn;
}

- (BOOL)confirmCloseTab:(PTYTab *)aTab
{
    if ([_contentView.tabView indexOfTabViewItemWithIdentifier:aTab] == NSNotFound) {
        return NO;
    }

    int numClosing = 0;
    for (PTYSession* session in [aTab sessions]) {
        if (![session exited]) {
            ++numClosing;
        }
    }

    BOOL mustAsk = NO;
    if (numClosing > 0 && [aTab promptOnClose]) {
        mustAsk = YES;
    }
    if (numClosing > 1 &&
        [iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs]) {
        mustAsk = YES;
    }

    if (mustAsk) {
        BOOL okToClose;
        if (numClosing == 1) {
            okToClose = [self confirmCloseForSessions:[aTab sessions]
                                           identifier:@"This tab"
                                          genericName:[NSString stringWithFormat:@"tab #%d",
                                                       [aTab tabNumber]]];
        } else {
            okToClose = [self confirmCloseForSessions:[aTab sessions]
                                           identifier:@"This multi-pane tab"
                                          genericName:[NSString stringWithFormat:@"tab #%d",
                                                       [aTab tabNumber]]];
        }
        return okToClose;
    }
    return YES;
}

- (void)performClose:(id)sender {
    [self close];
}

- (void)closeTab:(PTYTab *)aTab soft:(BOOL)soft
{
    if (!soft &&
        [aTab isTmuxTab] &&
        [[aTab sessions] count] > 0 &&
        [[aTab tmuxController] isAttached]) {
        iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:@"Kill tmux window, terminating its jobs, or hide it? "
                                               @"Hidden windows may be restored from the tmux dashboard."
                                       actions:@[ @"Hide", @"Cancel", @"Kill" ]
                                 actionMapping:@[ @(kiTermWarningSelection0), @(kiTermWarningSelection2), @(kiTermWarningSelection1)]
                                     accessory:nil
                                    identifier:@"ClosingTmuxTabKillsTmuxWindows"
                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                       heading:nil];
        if (selection == kiTermWarningSelection1) {
            [[aTab tmuxController] killWindow:[aTab tmuxWindow]];
        } else if (selection == kiTermWarningSelection0) {
            [[aTab tmuxController] hideWindow:[aTab tmuxWindow]];
        }
        return;
    }
    [self removeTab:aTab];
}

- (void)closeTab:(PTYTab*)aTab
{
    [self closeTab:aTab soft:NO];
}

// Just like closeTab but skips the tmux code. Terminates sessions, removes the
// tab, and closes the window if there are no tabs left.
- (void)removeTab:(PTYTab *)aTab {
    if (![aTab isTmuxTab]) {
        iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
        restorableSession.sessions = [aTab sessions];
        restorableSession.terminalGuid = self.terminalGuid;
        restorableSession.tabUniqueId = aTab.uniqueId;
        NSArray *tabs = [self tabs];
        NSUInteger index = [tabs indexOfObject:aTab];
        if (index != NSNotFound) {
            NSMutableArray *predecessors = [NSMutableArray array];
            for (NSUInteger i = 0; i < index; i++) {
                [predecessors addObject:@([tabs[i] uniqueId])];
            }
            restorableSession.predecessors = predecessors;
        }

        if (self.numberOfTabs == 1) {
            // Closing the last tab is equivalent to closing the window.
            restorableSession.arrangement = [self arrangement];
            restorableSession.group = kiTermRestorableSessionGroupWindow;
        } else {
            restorableSession.arrangement = [aTab arrangement];
            restorableSession.group = kiTermRestorableSessionGroupTab;
        }
        if (restorableSession.arrangement) {
            [[iTermController sharedInstance] pushCurrentRestorableSession:restorableSession];
        }
        for (PTYSession* session in [aTab sessions]) {
            [session terminate];
        }
        if (restorableSession.arrangement) {
            [[iTermController sharedInstance] commitAndPopCurrentRestorableSession];
        }
    } else {
        for (PTYSession* session in [aTab sessions]) {
            [session terminate];
        }
    }

    if ([_contentView.tabView numberOfTabViewItems] <= 1 && self.windowInitialized) {
        [[self window] close];
    } else {
        NSTabViewItem *aTabViewItem;
        // now get rid of this tab
        aTabViewItem = [aTab tabViewItem];
        [_contentView.tabView removeTabViewItem:aTabViewItem];
        PtyLog(@"closeSession - calling fitWindowToTabs");
        [self fitWindowToTabs];
    }
}

- (IBAction)openDashboard:(id)sender
{
    [[TmuxDashboardController sharedInstance] showWindow:nil];
}

- (IBAction)findCursor:(id)sender
{
    [[[self currentSession] textview] beginFindCursor:YES];
    if (!(GetCurrentKeyModifiers() & cmdKey)) {
        [[[self currentSession] textview] placeFindCursorOnAutoHide];
    }
    findCursorStartTime_ = [[NSDate date] timeIntervalSince1970];
}

- (IBAction)toggleCursorGuide:(id)sender {
  PTYSession *session = [self currentSession];
  session.highlightCursorLine = !session.highlightCursorLine;
}

- (IBAction)toggleSelectionRespectsSoftBoundaries:(id)sender {
    iTermController *controller = [iTermController sharedInstance];
    controller.selectionRespectsSoftBoundaries = !controller.selectionRespectsSoftBoundaries;
}

// Save the current scroll position
- (IBAction)saveScrollPosition:(id)sender
{
    [[self currentSession] screenSaveScrollPosition];
}

// Jump to the saved scroll position
- (IBAction)jumpToSavedScrollPosition:(id)sender
{
    [[self currentSession] jumpToSavedScrollPosition];
}

// Is there a saved scroll position?
- (BOOL)hasSavedScrollPosition
{
    return [[self currentSession] hasSavedScrollPosition];
}

- (void)updateFullScreenTabBar:(NSNotification *)notification {
    if ([self anyFullScreen]) {
        [_contentView.tabBarControl updateFlashing];
        [self repositionWidgets];
        [self fitTabsToWindow];
    }
}

- (IBAction)closeCurrentTab:(id)sender {
    if ([self tabView:_contentView.tabView shouldCloseTabViewItem:[_contentView.tabView selectedTabViewItem]]) {
        [self closeTab:[self currentTab]];
    }
}

- (IBAction)closeCurrentSession:(id)sender {
    iTermApplicationDelegate *appDelegate = [iTermApplication.sharedApplication delegate];
    [appDelegate userDidInteractWithASession];
    if ([[self window] isKeyWindow]) {
        PTYSession *aSession = [[[_contentView.tabView selectedTabViewItem] identifier] activeSession];
        [self closeSessionWithConfirmation:aSession];
    }
}

- (void)closeSessionWithConfirmation:(PTYSession *)aSession
{
    if ([[[self tabForSession:aSession] sessions] count] == 1) {
        [self closeCurrentTab:self];
        return;
    }
    BOOL okToClose = NO;
    if ([aSession exited]) {
        okToClose = YES;
    } else if (![aSession promptOnClose]) {
        okToClose = YES;
    } else {
      okToClose = [self confirmCloseForSessions:[NSArray arrayWithObject:aSession]
                                     identifier:@"This session"
                                    genericName:[NSString stringWithFormat:@"session \"%@\"",
                                                    [aSession name]]];
    }
    if (okToClose) {
        // Just in case IR is open, close it first.
        [self closeInstantReplay:self];
        [self closeSession:aSession];
    }
}

- (IBAction)restartSession:(id)sender {
    [self restartSessionWithConfirmation:self.currentSession];
}

- (void)restartSessionWithConfirmation:(PTYSession *)aSession {
    assert(aSession.isRestartable);
    [[self retain] autorelease];
    NSAlert *alert = [NSAlert alertWithMessageText:@"Restart session?"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Running jobs will be killed."];
    if (aSession.exited || [alert runModal] == NSAlertDefaultReturn) {
        [aSession restartSession];
    }
}

- (IBAction)previousTab:(id)sender {
    [_contentView.tabView previousTab:sender];
}

- (IBAction)nextTab:(id)sender {
    [_contentView.tabView nextTab:sender];
}

- (IBAction)previousPane:(id)sender {
    [[self currentTab] previousSession];
}

- (IBAction)nextPane:(id)sender {
    [[self currentTab] nextSession];
}

- (int)numberOfTabs
{
    return [_contentView.tabView numberOfTabViewItems];
}

- (PTYTab*)currentTab
{
    return [[_contentView.tabView selectedTabViewItem] identifier];
}

- (void)makeSessionActive:(PTYSession *)session {
    PTYTab *tab = [self tabForSession:session];
    if (tab.realParentWindow != self) {
        return;
    }
    if ([self isHotKeyWindow]) {
        iTermProfileHotKey *hotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
        [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:hotKey];
    } else {
        [self.window makeKeyAndOrderFront:nil];
    }
    [_contentView.tabView selectTabViewItem:tab.tabViewItem];
    if (tab.isMaximized) {
        [tab unmaximize];
    }
    [tab setActiveSession:session];
}

- (PTYSession *)currentSession {
    return [[[_contentView.tabView selectedTabViewItem] identifier] activeSession];
}

- (void)setWindowTitle {
    if (self.isShowingTransientTitle) {
        PTYSession *session = self.currentSession;
        NSString *aTitle = [NSString stringWithFormat:@"%@ \u2014 %d✕%d",
                            [self currentSessionName],
                            [session columns],
                            [session rows]];
        [self setWindowTitle:aTitle];
    } else {
        [self setWindowTitle:[self currentSessionName]];
    }
}

- (void)setWindowTitle:(NSString *)title {
    if (title == nil) {
        // title can be nil during loadWindowArrangement
        title = @"";
    }

    if ([iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber]) {
        NSString *tmuxId = @"";
        if ([[self currentSession] isTmuxClient]) {
            tmuxId = [NSString stringWithFormat:@" [%@]",
                      [[[self currentSession] tmuxController] clientName]];
        }
        NSString *windowNumber = @"";
#if ENABLE_SHORTCUT_ACCESSORY
        if (!_shortcutAccessoryViewController ||
            !(self.window.styleMask & NSTitledWindowMask)) {
            windowNumber = [NSString stringWithFormat:@"%d. ", number_ + 1];
        }
#else
        if (self.window.styleMask & NSTitledWindowMask) {
            windowNumber = [NSString stringWithFormat:@"%d. ", number_ + 1];
        }
#endif
        title = [NSString stringWithFormat:@"%@%@%@", windowNumber, title, tmuxId];
    }

    if (liveResize_) {
        // During a live resize this has to be done immediately because the runloop doesn't get
        // around to delayed performs until the live resize is done (bug 2812).
        self.window.title = title;
    } else {
        // In bug 2593, we see a crazy thing where setting the window title right
        // after a window is created causes it to have the wrong background color.
        // A delay of 0 doesn't fix it. I'm at wit's end here, so this will have to
        // do until a better explanation comes along.

        // In bug 3957, we see that GNU screen is buggy and sends a crazy number of title changes.
        // We want to coalesce them to avoid the title flickering like mad. Also, setting the title
        // seems to be relatively slow, so we don't want to spend too much time doing that if the
        // terminal goes nuts and sends lots of title-change sequences.
        BOOL hadTimer = (self.desiredTitle != nil);
        self.desiredTitle = title;
        if (!hadTimer) {
            PseudoTerminal<iTermWeakReference> *weakSelf = self.weakSelf;
            static const NSTimeInterval kSetTitleDelay = 0.1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSetTitleDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                weakSelf.window.title = weakSelf.desiredTitle;
                weakSelf.desiredTitle = nil;
            });
        }
    }
}

- (NSArray *)broadcastSessions
{
    NSMutableArray *sessions = [NSMutableArray array];
    int i;
    int n = [_contentView.tabView numberOfTabViewItems];
    switch ([self broadcastMode]) {
        case BROADCAST_OFF:
            break;

        case BROADCAST_TO_ALL_PANES:
            for (PTYSession* aSession in [[self currentTab] sessions]) {
                if (![aSession exited]) {
                    [sessions addObject:aSession];
                }
            }
            break;

        case BROADCAST_TO_ALL_TABS:
            for (i = 0; i < n; ++i) {
                for (PTYSession* aSession in [[[_contentView.tabView tabViewItemAtIndex:i] identifier] sessions]) {
                    if (![aSession exited]) {
                        [sessions addObject:aSession];
                    }
                }
            }
            break;

        case BROADCAST_CUSTOM: {
            for (PTYTab *aTab in [self tabs]) {
                for (PTYSession *aSession in [aTab sessions]) {
                    if ([broadcastViewIds_ containsObject:[NSNumber numberWithInt:[[aSession view] viewId]]]) {
                        if (![aSession exited]) {
                            [sessions addObject:aSession];
                        }
                    }
                }
            }
            break;
        }
    }
    return sessions;
}

- (void)sendInputToAllSessions:(NSString *)string
                      encoding:(NSStringEncoding)optionalEncoding
                 forceEncoding:(BOOL)forceEncoding {
    for (PTYSession *aSession in [self broadcastSessions]) {
        if (![aSession isTmuxGateway]) {
            [aSession writeTaskNoBroadcast:string encoding:optionalEncoding forceEncoding:forceEncoding];
        }
    }
}

- (BOOL)broadcastInputToSession:(PTYSession *)session
{
    switch ([self broadcastMode]) {
        case BROADCAST_OFF:
            return NO;

        case BROADCAST_TO_ALL_PANES:
            for (PTYSession* aSession in [[self currentTab] sessions]) {
                if (aSession == session) {
                    return YES;
                }
            }
            return NO;

        case BROADCAST_TO_ALL_TABS:
            for (PTYTab *aTab in [self tabs]) {
                for (PTYSession* aSession in [aTab sessions]) {
                    if (aSession == session) {
                        return YES;
                    }
                }
            }
            return NO;

        case BROADCAST_CUSTOM:
            return [broadcastViewIds_ containsObject:[NSNumber numberWithInt:[[session view] viewId]]];

        default:
            return NO;
    }
}

+ (int)_windowTypeForArrangement:(NSDictionary*)arrangement
{
    int windowType;
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE]) {
        windowType = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE] intValue];
    } else {
        if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_FULLSCREEN] &&
            [[arrangement objectForKey:TERMINAL_ARRANGEMENT_FULLSCREEN] boolValue]) {
            windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        } else if ([[arrangement objectForKey:TERMINAL_ARRANGEMENT_LION_FULLSCREEN] boolValue]) {
            windowType = WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            windowType = WINDOW_TYPE_NORMAL;
        }
    }
    return windowType;
}

+ (int)_screenIndexForArrangement:(NSDictionary*)arrangement
{
    int screenIndex;
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX]) {
        screenIndex = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX] intValue];
    } else {
        screenIndex = 0;
    }
    if (screenIndex < 0 || screenIndex >= [[NSScreen screens] count]) {
        screenIndex = 0;
    }
    return screenIndex;
}

+ (void)drawArrangementPreview:(NSDictionary*)terminalArrangement
                  screenFrames:(NSArray *)frames
{
    int windowType = [PseudoTerminal _windowTypeForArrangement:terminalArrangement];
    int screenIndex = [PseudoTerminal _screenIndexForArrangement:terminalArrangement];
    NSRect virtualScreenFrame = [[frames objectAtIndex:screenIndex] rectValue];
    NSRect screenFrame = [[[NSScreen screens] objectAtIndex:screenIndex] frame];
    double xScale = virtualScreenFrame.size.width / screenFrame.size.width;
    double yScale = virtualScreenFrame.size.height / screenFrame.size.height;
    double xOrigin = virtualScreenFrame.origin.x;
    double yOrigin = virtualScreenFrame.origin.y;

    NSRect rect = NSZeroRect;
    switch (windowType) {
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            rect = virtualScreenFrame;
            break;

        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_NORMAL:
            rect.origin.x = xOrigin + xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
            double h = [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            double y = [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
            // y is distance from bottom of screen to bottom of window
            y += h;
            // y is distance from bottom of screen to top of window
            y = screenFrame.size.height - y;
            // y is distance from top of screen to top of window
            rect.origin.y = yOrigin + yScale * y;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = yScale * h;
            break;

        case WINDOW_TYPE_TOP:
            rect.origin.x = xOrigin;
            rect.origin.y = yOrigin;
            rect.size.width = virtualScreenFrame.size.width;
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            break;

        case WINDOW_TYPE_TOP_PARTIAL:
            rect.origin.x = xOrigin;
            rect.origin.y = yOrigin;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            break;

        case WINDOW_TYPE_BOTTOM:
            rect.origin.x = xOrigin;
            rect.size.width = virtualScreenFrame.size.width;
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            rect.origin.y = virtualScreenFrame.size.height - rect.size.height;
            break;

        case WINDOW_TYPE_BOTTOM_PARTIAL:
            rect.origin.x = xOrigin;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            rect.origin.y = virtualScreenFrame.size.height - rect.size.height;
            break;

        case WINDOW_TYPE_LEFT:
            rect.origin.x = xOrigin;
            rect.origin.y = yOrigin;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = virtualScreenFrame.size.height;
            break;

        case WINDOW_TYPE_LEFT_PARTIAL:
            rect.origin.x = xOrigin;
            rect.origin.y = yOrigin;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            break;

        case WINDOW_TYPE_RIGHT:
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.origin.x = virtualScreenFrame.size.width - rect.size.width;
            rect.origin.y = yOrigin;
            rect.size.height = virtualScreenFrame.size.height;
            break;

        case WINDOW_TYPE_RIGHT_PARTIAL:
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.origin.x = virtualScreenFrame.size.width - rect.size.width;
            rect.origin.y = yOrigin;
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            break;
    }

    [[NSColor blackColor] set];
    NSRectFill(rect);
    [[NSColor windowFrameColor] set];
    NSFrameRect(rect);
    NSRect windowRect = rect;

    int N = [(NSDictionary *)[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_TABS] count];
    [[NSColor windowFrameColor] set];
    NSRect tabsRect = NSMakeRect(rect.origin.x + 1,
                                 rect.origin.y,
                                 rect.size.width - 2,
                                 10);
    NSSize step = NSMakeSize(MIN(20, floor((rect.size.width - 2) / N)), 6);
    NSSize tabSize = NSZeroSize;
    const CGFloat kLeftTabPreviewWidth = 20;
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_BottomTab:
            tabsRect.origin.y += rect.size.height - 10;
            step.height = 0;
            tabSize = NSMakeSize(step.width - 2, 8);
            break;
        case PSMTab_TopTab:
            step.height = 0;
            tabSize = NSMakeSize(step.width - 2, 8);
            break;
        case PSMTab_LeftTab:
            tabsRect.size.width = kLeftTabPreviewWidth;
            tabsRect.size.height = rect.size.height;
            step.width = 0;
            tabSize = NSMakeSize(kLeftTabPreviewWidth - 2, 4);
            break;
    }
    NSRectFill(tabsRect);

    [[NSColor darkGrayColor] set];
    NSRect tabRect = NSMakeRect(tabsRect.origin.x + 1,
                                tabsRect.origin.y + 1,
                                tabSize.width,
                                tabSize.height);
    for (int i = 0; i < N; i++) {
        if (NSMaxY(tabRect) > NSMaxY(rect) ||
            NSMaxX(tabRect) > NSMaxX(rect)) {
            break;
        }
        NSRectFill(tabRect);
        tabRect.origin.x += step.width;
        tabRect.origin.y += step.height;
    }

    NSDictionary* tabArrangement = terminalArrangement[TERMINAL_ARRANGEMENT_TABS][0];
    NSRect contentRect = NSMakeRect(rect.origin.x + 1,
                                    rect.origin.y,
                                    rect.size.width - 2,
                                    rect.size.height - 11);
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
          case PSMTab_BottomTab:
              break;
          case PSMTab_TopTab:
              contentRect.origin.y += 10;
              break;
          case PSMTab_LeftTab:
              contentRect.origin.x += kLeftTabPreviewWidth;
              contentRect.size.width -= kLeftTabPreviewWidth;
              contentRect.size.height += 10;
              break;
    }
    [PTYTab drawArrangementPreview:tabArrangement
                             frame:contentRect];
    if ([terminalArrangement[TERMINAL_ARRANGEMENT_HAS_TOOLBELT] boolValue]) {
        NSRect toolbeltRect = windowRect;
        int toolbeltWidth = toolbeltRect.size.width * 0.1;
        toolbeltRect.origin.x += toolbeltRect.size.width - toolbeltWidth;
        toolbeltRect.size.width = toolbeltWidth - 1;
        [[NSColor whiteColor] set];
        NSRectFill(toolbeltRect);

        [[NSColor blackColor] set];
        NSFrameRect(toolbeltRect);
    }
}

// Indicates if a newly created window will automatically enter Lion full screen.
+ (BOOL)willAutoFullScreenNewWindow {
    PseudoTerminal *keyWindow = [[iTermController sharedInstance] keyTerminalWindow];
    return [keyWindow lionFullScreen] || (keyWindow && keyWindow->togglingLionFullScreen_);
}

+ (BOOL)anyWindowIsEnteringLionFullScreen {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        if (term->togglingLionFullScreen_ || term->_haveDelayedEnterFullScreenMode) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)arrangementIsLionFullScreen:(NSDictionary *)arrangement {
    return [PseudoTerminal _windowTypeForArrangement:arrangement] == WINDOW_TYPE_LION_FULL_SCREEN;
}

+ (BOOL)shouldRestoreHotKeyWindowWithGUID:(NSString *)guid {
    if (!guid) {
        // Something went wrong and we don't know the GUID. Or you just upgraded and a GUID wasn't
        // saved because it's new.
        if ([[iTermHotKeyMigrationHelper sharedInstance] didMigration] && [[[iTermHotKeyController sharedInstance] profileHotKeys] count] == 1) {
            iTermProfileHotKey *profileHotKey = [[[iTermHotKeyController sharedInstance] profileHotKeys] firstObject];
            guid = profileHotKey.profile[KEY_GUID];
            DLog(@"Restoring an arrangement with a hotkey window but its profile's GUID is missing. Guessing that it's the profile named %@ because there is only one hotkey profile", profileHotKey.profile[KEY_NAME]);
        } else {
            DLog(@"Restoring an arrangement with a hotkey window but its profile's GUID is missing. There is more than one hotkey profile so I give up.");
            return NO;
        }
    }
    BOOL foundHotKey = NO;
    for (iTermProfileHotKey *hotKey in [[iTermHotKeyController sharedInstance] profileHotKeys]) {
        if ([[iTermProfilePreferences stringForKey:KEY_GUID inProfile:hotKey.profile] isEqualToString:guid]) {
            foundHotKey = YES;
            if (hotKey.windowController.weaklyReferencedObject) {
                // Already have a window for this profile hotkey
                return NO;
            }
        }
    }
    if (!foundHotKey) {
        // Do not have a hotkey defined for this profile
        return NO;
    }
    
    return YES;
}

+ (PseudoTerminal*)bareTerminalWithArrangement:(NSDictionary *)arrangement
                      forceOpeningHotKeyWindow:(BOOL)force {
    BOOL isHotkeyWindow = [arrangement[TERMINAL_ARRANGEMENT_IS_HOTKEY_WINDOW] boolValue];
    NSString *guid = arrangement[TERMINAL_ARRANGEMENT_PROFILE_GUID];
    if (isHotkeyWindow && !force) {
        if (![self shouldRestoreHotKeyWindowWithGUID:guid]) {
            return nil;
        }
    }

    PseudoTerminal* term;
    int windowType = [PseudoTerminal _windowTypeForArrangement:arrangement];
    int screenIndex = [PseudoTerminal _screenIndexForArrangement:arrangement];
    iTermProfileHotKey *profileHotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForGUID:guid];
    iTermHotkeyWindowType hotkeyWindowType = iTermHotkeyWindowTypeNone;
    if (isHotkeyWindow) {
        assert(profileHotKey);
        hotkeyWindowType = profileHotKey.hotkeyWindowType;
    }
    if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:WINDOW_TYPE_TRADITIONAL_FULL_SCREEN
                                            savedWindowType:[arrangement[TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE] intValue]
                                                     screen:screenIndex
                                           hotkeyWindowType:hotkeyWindowType] autorelease];

        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN] doubleValue];
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_HEIGHT] doubleValue];
        term->oldFrame_ = rect;
        term->useTransparency_ =
            ![iTermPreferences boolForKey:kPreferenceKeyDisableFullscreenTransparencyByDefault];
        term->oldUseTransparency_ = YES;
        term->restoreUseTransparency_ = YES;
    } else if (windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:WINDOW_TYPE_LION_FULL_SCREEN
                                            savedWindowType:[arrangement[TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE] intValue]
                                                     screen:screenIndex
                                           hotkeyWindowType:hotkeyWindowType] autorelease];
        [term delayedEnterFullscreen];
    } else {
        // Support legacy edge-spanning flag by adjusting the
        // window type.
        if ([arrangement[TERMINAL_ARRANGEMENT_EDGE_SPANNING_OFF] boolValue]) {
            switch (windowType) {
                case WINDOW_TYPE_TOP:
                    windowType = WINDOW_TYPE_TOP_PARTIAL;
                    break;

                case WINDOW_TYPE_BOTTOM:
                    windowType = WINDOW_TYPE_BOTTOM_PARTIAL;
                    break;

                case WINDOW_TYPE_LEFT:
                    windowType = WINDOW_TYPE_LEFT_PARTIAL;
                    break;

                case WINDOW_TYPE_RIGHT:
                    windowType = WINDOW_TYPE_RIGHT_PARTIAL;
                    break;
            }
        }
        // TODO: this looks like a bug - are X-of-screen windows not restored to the right screen?
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:windowType
                                            savedWindowType:WINDOW_TYPE_NORMAL
                                                     screen:-1
                                           hotkeyWindowType:hotkeyWindowType] autorelease];

        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
        // TODO: for window type top, set width to screen width.
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
        [[term window] setFrame:rect display:NO];
    }

    if ([[arrangement objectForKey:TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING] boolValue]) {
        [term hideAfterOpening];
    }
    if (isHotkeyWindow) {
        BOOL ok = YES;
        if (force) {
            ok = [[iTermHotKeyController sharedInstance] addRevivedHotkeyWindowController:term
                                                                       forProfileWithGUID:guid];
        }
        if (ok) {
            term.window.alphaValue = 0;
            [[term window] orderOut:nil];
        }
    }
    return term;
}

+ (instancetype)terminalWithArrangement:(NSDictionary *)arrangement
                               sessions:(NSArray *)sessions
               forceOpeningHotKeyWindow:(BOOL)force {
    PseudoTerminal *term = [PseudoTerminal bareTerminalWithArrangement:arrangement
                                              forceOpeningHotKeyWindow:force];
    for (PTYSession *session in sessions) {
        assert([session revive]);  // TODO(georgen): This isn't guaranteed
    }
    if ([term loadArrangement:arrangement sessions:sessions]) {
        return term;
    } else {
        return term;
    }
}

+ (PseudoTerminal*)terminalWithArrangement:(NSDictionary *)arrangement
                  forceOpeningHotKeyWindow:(BOOL)force {
    return [self terminalWithArrangement:arrangement sessions:nil forceOpeningHotKeyWindow:force];
}

- (IBAction)findUrls:(id)sender {
    FindViewController *findViewController = [[[self currentSession] view] findViewController];
    NSString *regex = [iTermAdvancedSettingsModel findUrlsRegex];
    [findViewController closeViewAndDoTemporarySearchForString:regex
                                                  ignoringCase:NO
                                                         regex:YES];
}

- (IBAction)detachTmux:(id)sender
{
    [[self currentTmuxController] requestDetach];
}

- (TmuxController *)currentTmuxController {
    TmuxController *controller = [[self currentSession] tmuxController];
    if (!controller) {
        controller = [[[iTermController sharedInstance] anyTmuxSession] tmuxController];
        DLog(@"No controller for current session %@, picking one at random: %@",
             [self currentSession], controller);
    }
    return controller;
}

- (IBAction)newTmuxWindow:(id)sender {
    [[self currentTmuxController] newWindowWithAffinity:nil
                                       initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:self.currentSession.profile
                                                                                                objectType:iTermWindowObject]];
}

- (IBAction)newTmuxTab:(id)sender {
    int tmuxWindow = [[self currentTab] tmuxWindow];
    if (tmuxWindow < 0) {
        tmuxWindow = -(number_ + 1);
    }
    [[self currentTmuxController] newWindowWithAffinity:[NSString stringWithFormat:@"%d", tmuxWindow]
                                       initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:self.currentSession.profile
                                                                                                objectType:iTermTabObject]];
}

- (NSSize)tmuxCompatibleSize {
    DLog(@"Computing the tmux-compatible size...");
    NSSize tmuxSize = NSMakeSize(INT_MAX, INT_MAX);
    for (PTYTab *aTab in [self tabs]) {
        if ([aTab isTmuxTab]) {
            NSSize tabSize = [aTab tmuxSize];
            DLog(@"tab %@ size is %@", aTab, NSStringFromSize(tabSize));
            
            tmuxSize.width = (int) MIN(tmuxSize.width, tabSize.width);
            tmuxSize.height = (int) MIN(tmuxSize.height, tabSize.height);
        }
    }
    DLog(@"tmux-compatible size is %@", NSStringFromSize(tmuxSize));
    return tmuxSize;
}

- (void)loadTmuxLayout:(NSMutableDictionary *)parseTree
                window:(int)window
        tmuxController:(TmuxController *)tmuxController
                  name:(NSString *)name {
    DLog(@"begin loadTmuxLayout");
    [self beginTmuxOriginatedResize];
    PTYTab *tab = [PTYTab openTabWithTmuxLayout:parseTree
                                     inTerminal:self
                                     tmuxWindow:window
                                 tmuxController:tmuxController];
    [self setWindowTitle:name];
    [tab setTmuxWindowName:name];
    [tab setReportIdealSizeAsCurrent:YES];
    DLog(@"loadTmuxLayout invoking fitWindowToTabs.");
    [self fitWindowToTabs];
    [tab setReportIdealSizeAsCurrent:NO];

    for (PTYSession *aSession in [tab sessions]) {
        [tmuxController registerSession:aSession withPane:[aSession tmuxPane] inWindow:window];
        [aSession setTmuxController:tmuxController];
        [self setDimmingForSession:aSession];
    }
    // Set the tab title from the active session's name, which (because it has
    // a tmux controller) will be based on the tmux window's name provided by
    // the tab. This must be done after setting the tmux controller.
    [tab loadTitleFromSession];
    [self endTmuxOriginatedResize];
    DLog(@"end loadTmuxLayout");
}

- (void)beginTmuxOriginatedResize
{
    ++tmuxOriginatedResizeInProgress_;
}

- (void)endTmuxOriginatedResize
{
    --tmuxOriginatedResizeInProgress_;
}

- (void)hideAfterOpening
{
    hideAfterOpening_ = YES;
    [[self window] performSelector:@selector(miniaturize:)
                                            withObject:nil
                                            afterDelay:0];
}

- (BOOL)loadArrangement:(NSDictionary *)arrangement {
    return [self loadArrangement:arrangement sessions:nil];
}

- (BOOL)loadArrangement:(NSDictionary *)arrangement sessions:(NSArray *)sessions {
    PtyLog(@"Restore arrangement: %@", arrangement);
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_ROWS]) {
        desiredRows_ = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_ROWS] intValue];
    }
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_COLUMNS]) {
        desiredColumns_ = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_COLUMNS] intValue];
    }
    int windowType = [PseudoTerminal _windowTypeForArrangement:arrangement];
    NSRect rect;
    rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
    rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
    rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
    rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];

    // 10.11 starts you off with a tiny little frame. I don't know why they do
    // that, but this fixes it.
    if ([[self class] useElCapitanFullScreenLogic] &&
        windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        [[self window] setFrame:rect display:YES];
    }

    for (NSDictionary* tabArrangement in [arrangement objectForKey:TERMINAL_ARRANGEMENT_TABS]) {
        NSDictionary<NSString *, PTYSession *> *sessionMap = nil;
        if (sessions) {
            sessionMap = [PTYTab sessionMapWithArrangement:tabArrangement sessions:sessions];
        }
        if (![PTYTab openTabWithArrangement:tabArrangement
                                 inTerminal:self
                            hasFlexibleView:NO
                                    viewMap:nil
                                 sessionMap:sessionMap]) {
            return NO;
        }
    }
    _contentView.shouldShowToolbelt = [arrangement[TERMINAL_ARRANGEMENT_HAS_TOOLBELT] boolValue];
    hidingToolbeltShouldResizeWindow_ = [arrangement[TERMINAL_ARRANGEMENT_HIDING_TOOLBELT_SHOULD_RESIZE_WINDOW] boolValue];
    hidingToolbeltShouldResizeWindowInitialized_ = YES;

    if (windowType == WINDOW_TYPE_NORMAL ||
        windowType == WINDOW_TYPE_NO_TITLE_BAR) {
        // The window may have changed size while adding tab bars, etc.
        // TODO: for window type top, set width to screen width.
        [[self window] setFrame:rect display:YES];
    }

    const int tabIndex = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX] intValue];
    if (tabIndex >= 0 && tabIndex < [_contentView.tabView numberOfTabViewItems]) {
        [_contentView.tabView selectTabViewItemAtIndex:tabIndex];
    }

    Profile* addressbookEntry = [[[[[self tabs] objectAtIndex:0] sessions] objectAtIndex:0] profile];
    if ([addressbookEntry objectForKey:KEY_SPACE] &&
        [[addressbookEntry objectForKey:KEY_SPACE] intValue] == iTermProfileJoinsAllSpaces) {
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorCanJoinAllSpaces];
    }
    if ([arrangement objectForKey:TERMINAL_GUID] &&
        [[arrangement objectForKey:TERMINAL_GUID] isKindOfClass:[NSString class]]) {
        self.terminalGuid = [arrangement objectForKey:TERMINAL_GUID];
    }

    [self fitTabsToWindow];
    [_contentView updateToolbelt];
    return YES;
}

- (NSDictionary *)arrangementExcludingTmuxTabs:(BOOL)excludeTmux
                             includingContents:(BOOL)includeContents {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:7];
    NSRect rect = [[self window] frame];
    int screenNumber = 0;
    for (NSScreen* screen in [NSScreen screens]) {
        if (screen == [[self window] screen]) {
            break;
        }
        ++screenNumber;
    }

    [result setObject:_terminalGuid forKey:TERMINAL_GUID];

    // Save window frame
    result[TERMINAL_ARRANGEMENT_X_ORIGIN] = @(rect.origin.x);
    result[TERMINAL_ARRANGEMENT_Y_ORIGIN] = @(rect.origin.y);
    result[TERMINAL_ARRANGEMENT_WIDTH] = @(rect.size.width);
    result[TERMINAL_ARRANGEMENT_HEIGHT] = @(rect.size.height);
    result[TERMINAL_ARRANGEMENT_HAS_TOOLBELT] = @(_contentView.shouldShowToolbelt);
    result[TERMINAL_ARRANGEMENT_HIDING_TOOLBELT_SHOULD_RESIZE_WINDOW] =
            @(hidingToolbeltShouldResizeWindow_);

    if ([self anyFullScreen]) {
        // Save old window frame
        result[TERMINAL_ARRANGEMENT_OLD_X_ORIGIN] = @(oldFrame_.origin.x);
        result[TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN] = @(oldFrame_.origin.y);
        result[TERMINAL_ARRANGEMENT_OLD_WIDTH] = @(oldFrame_.size.width);
        result[TERMINAL_ARRANGEMENT_OLD_HEIGHT] = @(oldFrame_.size.height);
    }

    result[TERMINAL_ARRANGEMENT_WINDOW_TYPE] = @([self lionFullScreen] ? WINDOW_TYPE_LION_FULL_SCREEN : windowType_);
    result[TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE] = @(savedWindowType_);
    result[TERMINAL_ARRANGEMENT_SCREEN_INDEX] = @([[NSScreen screens] indexOfObjectIdenticalTo:[[self window] screen]]);
    result[TERMINAL_ARRANGEMENT_DESIRED_ROWS] = @(desiredRows_);
    result[TERMINAL_ARRANGEMENT_DESIRED_COLUMNS] = @(desiredColumns_);

    // Save tabs.
    NSMutableArray* tabs = [NSMutableArray arrayWithCapacity:[self numberOfTabs]];
    for (NSTabViewItem* tabViewItem in [_contentView.tabView tabViewItems]) {
        PTYTab *theTab = [tabViewItem identifier];
        if ([[theTab sessions] count]) {
            if (!excludeTmux || ![theTab isTmuxTab]) {
                [tabs addObject:[theTab arrangementWithContents:includeContents]];
            }
        }
    }
    if ([tabs count] == 0) {
        return nil;
    }
    result[TERMINAL_ARRANGEMENT_TABS] = tabs;

    // Save index of selected tab.
    result[TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX] = @([_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]]);
    result[TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING] = @(hideAfterOpening_);
    result[TERMINAL_ARRANGEMENT_IS_HOTKEY_WINDOW] = @(self.isHotKeyWindow);
    NSString *profileGuid = [[[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] profile] objectForKey:KEY_GUID];
    if (profileGuid) {
        result[TERMINAL_ARRANGEMENT_PROFILE_GUID] = profileGuid;
    }

    return result;
}

- (NSDictionary*)arrangement {
    return [self arrangementExcludingTmuxTabs:YES includingContents:NO];
}

// NSWindow delegate methods
- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
    [self.window.dockTile setBadgeLabel:@""];
    [self.window.dockTile setShowsApplicationBadge:NO];
    if ([[self currentTab] blur]) {
        [self enableBlur:[[self currentTab] blurRadius]];
    } else {
        [self disableBlur];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidDeminiaturize"
                                                        object:self
                                                      userInfo:nil];
}

- (BOOL)promptOnClose
{
    for (PTYSession *aSession in [self allSessions]) {
        if ([aSession promptOnClose]) {
            return YES;
        }
    }
    return NO;
}

// TODO: Kill this
- (iTermToolbeltView *)toolbelt {
    return _contentView.toolbelt;
}

- (void)refreshTools {
    [[_contentView.toolbelt commandHistoryView] updateCommands];
    [[_contentView.toolbelt capturedOutputView] updateCapturedOutput];
    [[_contentView.toolbelt directoriesView] updateDirectories];
}

- (int)numRunningSessions
{
    int n = 0;
    for (PTYSession *aSession in [self allSessions]) {
        if (![aSession exited]) {
            ++n;
        }
    }
    return n;
}

- (BOOL)windowShouldClose:(NSNotification *)aNotification
{
    // This counts as an interaction beacuse it is only called when the user initiates the closing of the window (as opposed to a session dying on you).
    iTermApplicationDelegate *appDelegate = [iTermApplication.sharedApplication delegate];
    [appDelegate userDidInteractWithASession];

    BOOL needPrompt = NO;
    if ([self promptOnClose]) {
        needPrompt = YES;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs] &&
         [self numRunningSessions] > 1) {
        needPrompt = YES;
    }

    BOOL shouldClose;
    if (needPrompt) {
        shouldClose = [self showCloseWindow];
    } else {
        shouldClose = YES;
    }

    if (shouldClose) {
        int n = 0;
        for (PTYTab *aTab in [self tabs]) {
            if ([aTab isTmuxTab]) {
                n++;
            }
        }
        NSString *title = nil;
        if (n == 1) {
            title = @"Kill window and its jobs, hide window from view, or detach from tmux session?\n\n"
                    @"Hidden windows may be restored from the tmux dashboard.";
        } else if (n > 1) {
            title = @"Kill all tmux windows and their jobs, hide windows from view, or detach from tmux session?\n\n"
                    @"Hidden windows may be restored from the tmux dashboard.";
        }
        if (title) {
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:title
                                           actions:@[ @"Hide", @"Detach tmux Session", @"Kill" ]
                                        identifier:@"ClosingTmuxWindowKillsTmuxWindows"
                                       silenceable:kiTermWarningTypePermanentlySilenceable];
            // If there are tmux tabs, tell the tmux server to kill/hide the
            // window, but go ahead and close the window anyway because there
            // might be non-tmux tabs as well. This is a rare instance of
            // performing an action on a tmux object without waiting for the
            // server to tell us to do it.

            BOOL doTmuxDetach = NO;

            for (PTYTab *aTab in [self tabs]) {
                if ([aTab isTmuxTab]) {
                    if (selection == kiTermWarningSelection1) {
                        doTmuxDetach = YES;
                    } else if (selection == kiTermWarningSelection2) {
                        [[aTab tmuxController] killWindow:[aTab tmuxWindow]];
                    } else {
                        [[aTab tmuxController] hideWindow:[aTab tmuxWindow]];
                    }
                }
            }

            if (doTmuxDetach) {
                 PTYSession *aSession = [[[_contentView.tabView selectedTabViewItem] identifier] activeSession];
                 [[aSession tmuxController] requestDetach];
             }
        }
    }
    return shouldClose;
}

- (void)closeInstantReplayWindow {
    [_instantReplayWindowController close];
    _instantReplayWindowController.delegate = nil;
    [_instantReplayWindowController release];
    _instantReplayWindowController = nil;
}

- (void)windowWillClose:(NSNotification *)aNotification {
    if (self.isHotKeyWindow && [[self allSessions] count] == 0) {
        // Remove hotkey window restorable state when the last session closes.
        iTermProfileHotKey *hotKey =
            [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
        [hotKey windowWillClose];
        [[self window] invalidateRestorableState];
    }
    // Close popups.
    [pbHistoryView close];
    [autocompleteView close];
    [commandHistoryPopup close];
    [_directoriesPopupWindowController close];

    // _contentView.tabBarControl is holding on to us, so we have to tell it to let go
    [_contentView.tabBarControl setDelegate:nil];

    [self disableBlur];
    // If a fullscreen window is closing, hide the menu bar unless it's only fullscreen because it's
    // mid-toggle in which case it's really the window that's replacing us that is fullscreen.
    if (_fullScreen && !togglingFullScreen_) {
        [self showMenuBar];
    }

    // Save frame position for last window
    if ([[[iTermController sharedInstance] terminals] count] == 1) {
        if (_instantReplayWindowController) {
            // We don't want the IR window to survive us, nor be saved in the restorable state.
            [self closeInstantReplayWindow];
        }
        if ([iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement]) {
            [[self window] saveFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, 0]];
        } else {
            // Save frame position for window
            [[self window] saveFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, uniqueNumber_]];
            [[TemporaryNumberAllocator sharedInstance] deallocateNumber:uniqueNumber_];
        }
    } else {
        if (![iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement]) {
            // Save frame position for window
            [[self window] saveFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, uniqueNumber_]];
            [[TemporaryNumberAllocator sharedInstance] deallocateNumber:uniqueNumber_];
        }
    }

    if ([[self allSessions] count]) {
        // First close any tmux tabs because their closure is not undoable.
        for (PTYTab *tab in [self tabs]) {
            for (PTYSession *session in [tab sessions]) {
                if (session.isTmuxClient) {
                    [session terminate];
                }
            }
        }
    }
    if ([[self allSessions] count]) {
        // Save restorable sessions in controllers and make sessions terminate or prepare to terminate.
        iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
        restorableSession.sessions = [self allSessions];
        restorableSession.terminalGuid = self.terminalGuid;
        restorableSession.arrangement = [self arrangement];
        restorableSession.group = kiTermRestorableSessionGroupWindow;
        if (restorableSession.arrangement) {
            [[iTermController sharedInstance] pushCurrentRestorableSession:restorableSession];
        }
        for (PTYSession* session in [self allSessions]) {
            [session terminate];
        }
        if (restorableSession.arrangement) {
            [[iTermController sharedInstance] commitAndPopCurrentRestorableSession];
        }
    }

    [[self retain] autorelease];
    
    // This releases the last reference to self except for autorelease pools.
    [[iTermController sharedInstance] terminalWillClose:self];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidClose"
                                                        object:nil
                                                      userInfo:nil];
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
    [self disableBlur];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowWillMiniaturize"
                                                        object:self
                                                      userInfo:nil];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification {
    DLog(@"windowDidBecomeKey:%@ window=%@ stack:\n%@",
         aNotification, self.window, [NSThread callStackSymbols]);

    [iTermQuickLookController dismissSharedPanel];
#if ENABLE_SHORTCUT_ACCESSORY
    _shortcutAccessoryViewController.isMain = YES;
#endif
    if (!self.isHotKeyWindow) {
        [[iTermHotKeyController sharedInstance] nonHotKeyWindowDidBecomeKey];
    }
    [[iTermHotKeyController sharedInstance] autoHideHotKeyWindowsExcept:[[iTermHotKeyController sharedInstance] siblingWindowControllersOf:self]];

    [[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
    [[[NSApplication sharedApplication] dockTile] setShowsApplicationBadge:NO];

    [[iTermController sharedInstance] setCurrentTerminal:self];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateMaximizePaneMenuItem];
    [itad updateUseTransparencyMenuItem];
    [itad updateBroadcastMenuState];
    if (_fullScreen) {
        if (![self isHotKeyWindow] ||
            [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] rollingIn] ||
            [[self window] alphaValue] > 0) {
            // One of the following is true:
            // - This is a regular (non-hotkey) fullscreen window
            // - It's a fullscreen hotkey window that's getting rolled in (but its alpha is 0)
            // - It's a fullscreen hotkey window that's already visible (e.g., switching back from settings dialog)
            [self hideMenuBar];
        }
    }

    // Note: there was a bug in the old iterm that setting fonts didn't work
    // properly if the font panel was left open in focus-follows-mouse mode.
    // There was code here to close the font panel. I couldn't reproduce the old
    // bug and it was reported as bug 51 in iTerm2 so it was removed. See the
    // svn history for the old impl.

    // update the cursor
    [[self currentSession] refresh];
    [[[self currentSession] textview] setNeedsDisplay:YES];
    [self _loadFindStringFromSharedPasteboard];

    // Start the timers back up
    for (PTYSession* aSession in [self allSessions]) {
        [aSession updateDisplay];
        [[aSession view] setBackgroundDimmed:NO];
        [aSession setFocused:aSession == [self currentSession]];
    }
    // Some users report that the first responder isn't always set properly. Let's try to fix that.
    // This attempt (4/20/13) is to fix bug 2431.
    [self performSelector:@selector(makeCurrentSessionFirstResponder)
               withObject:nil
               afterDelay:0];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded]) {
        [self editSession:self.currentSession makeKey:NO];
    }
    [self notifyTmuxOfTabChange];

    [_contentView updateDivisionView];
}

- (void)makeCurrentSessionFirstResponder
{
    if ([self currentSession]) {
        PtyLog(@"makeCurrentSessionFirstResponder. New first responder will be %@. The current first responder is %@",
               [[self currentSession] textview], [[self window] firstResponder]);
        [[self window] makeFirstResponder:[[self currentSession] textview]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                            object:[self currentSession]
                                                          userInfo:nil];
    } else {
        PtyLog(@"There is no current session to make the first responder");
    }
}

// Forbid FFM from changing key window if is hotkey window.
- (BOOL)disableFocusFollowsMouse {
    return self.isHotKeyWindow;
}

- (CGFloat)growToolbeltBy:(CGFloat)diff {
    CGFloat before = _contentView.toolbeltWidth;
    _contentView.toolbeltWidth = _contentView.toolbeltWidth + diff;
    [_contentView constrainToolbeltWidth];
    [self repositionWidgets];
    return _contentView.toolbeltWidth - before;
}

- (void)toolbeltDidFinishGrowing {
    // Fixes issue 4323. During live dragging it's fine to just resize the
    // visible tab, but when you're done they all must be in sync.
    [self fitTabsToWindow];
}

- (void)canonicalizeWindowFrame {
    PtyLog(@"canonicalizeWindowFrame");
    PTYSession* session = [self currentSession];
    NSDictionary* abDict = [session profile];
    NSScreen* screen = [[self window] screen];
    if (!screen) {
        PtyLog(@"No window screen");
        // Try to use the screen of the current session. Fall back to the main
        // screen if that's not an option.
        NSArray* screens = [NSScreen screens];
        int screenNumber = [abDict objectForKey:KEY_SCREEN] ? [[abDict objectForKey:KEY_SCREEN] intValue] : 0;
        if (screenNumber == -1) { // No pref
            screenNumber = 0;
        } else if (screenNumber == -2) {  // Where cursor is; respect original preference
            if ([screens count] > screenNumber_) {
                screenNumber = screenNumber_;
            } else {
                screenNumber = 0;
            }
        }
        if ([screens count] == 0) {
            PtyLog(@"We are headless");
            // Nothing we can do if we're headless.
            return;
        }
        if ([screens count] <= screenNumber) {
            PtyLog(@"Using screen 0 because the preferred screen isn't around any more");
            screenNumber = 0;
        }
        screen = screens[screenNumber];
    }
    NSRect frame = [[self window] frame];
    NSRect screenVisibleFrame = [screen visibleFrame];
    NSRect screenVisibleFrameIgnoringHiddenDock = [screen visibleFrameIgnoringHiddenDock];
    PtyLog(@"The new screen visible frame is %@", [NSValue valueWithRect:screenVisibleFrame]);

    // NOTE: In bug 1347, we see that for some machines, [screen frame].size.width==0 at some point
    // during sleep/wake from sleep. That is why we check that width is positive before setting the
    // window's frame.
    NSSize decorationSize = [self windowDecorationSize];
    PtyLog(@"Decoration size is %@", [NSValue valueWithSize:decorationSize]);
    PtyLog(@"Line height is %f, char width is %f", (float) [[session textview] lineHeight], [[session textview] charWidth]);
    BOOL edgeSpanning = YES;
    switch (windowType_) {
        case WINDOW_TYPE_TOP_PARTIAL:
            edgeSpanning = NO;
        case WINDOW_TYPE_TOP:
            PtyLog(@"Window type = TOP, desired rows=%d", desiredRows_);
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            if (desiredRows_ > 0) {
                frame.size.height = MIN(screenVisibleFrame.size.height,
                                        ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * VMARGIN);
            } else {
                frame.size.height = MIN(screenVisibleFrame.size.height, frame.size.height);
            }
            if (!edgeSpanning) {
                frame.size.width = MIN(frame.size.width, screenVisibleFrameIgnoringHiddenDock.size.width);
                frame.origin.x = MAX(frame.origin.x, screenVisibleFrameIgnoringHiddenDock.origin.x);
                double freeSpaceOnLeft = MIN(0, screenVisibleFrameIgnoringHiddenDock.size.width - frame.size.width - (frame.origin.x - screenVisibleFrameIgnoringHiddenDock.origin.x));
                frame.origin.x += freeSpaceOnLeft;
            } else {
                frame.size.width = screenVisibleFrameIgnoringHiddenDock.size.width;
                frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;
            }
            frame.origin.y = screenVisibleFrame.origin.y + screenVisibleFrame.size.height - frame.size.height;

            if (frame.size.width > 0) {
                [[self window] setFrame:frame display:YES];
            }
            break;

        case WINDOW_TYPE_BOTTOM_PARTIAL:
            edgeSpanning = NO;
        case WINDOW_TYPE_BOTTOM:
            PtyLog(@"Window type = BOTTOM, desired rows=%d", desiredRows_);
            // If the screen grew and the window was smaller than the desired number of rows, grow it.
            if (desiredRows_ > 0) {
                frame.size.height = MIN(screenVisibleFrame.size.height,
                                        ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * VMARGIN);
            } else {
                frame.size.height = MIN(screenVisibleFrame.size.height, frame.size.height);
            }
            if (!edgeSpanning) {
                frame.size.width = MIN(frame.size.width, screenVisibleFrameIgnoringHiddenDock.size.width);
                frame.origin.x = MAX(frame.origin.x, screenVisibleFrameIgnoringHiddenDock.origin.x);
                double freeSpaceOnLeft = MIN(0, screenVisibleFrameIgnoringHiddenDock.size.width - frame.size.width - (frame.origin.x - screenVisibleFrameIgnoringHiddenDock.origin.x));
                frame.origin.x += freeSpaceOnLeft;
            } else {
                frame.size.width = screenVisibleFrameIgnoringHiddenDock.size.width;
                frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;
            }
            frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;

            if (frame.size.width > 0) {
                [[self window] setFrame:frame display:YES];
            }
            break;

        case WINDOW_TYPE_LEFT_PARTIAL:
            edgeSpanning = NO;
        case WINDOW_TYPE_LEFT:
            PtyLog(@"Window type = LEFT, desired cols=%d", desiredColumns_);
            // If the screen grew and the window was smaller than the desired number of columns, grow it.
            if (desiredColumns_ > 0) {
                frame.size.width = MIN(screenVisibleFrame.size.width,
                                       [[session textview] charWidth] * desiredColumns_ + 2 * MARGIN);
            } else {
                frame.size.width = MIN(screenVisibleFrame.size.width, frame.size.width);
            }
            if (!edgeSpanning) {
                frame.size.height = MIN(frame.size.height, screenVisibleFrameIgnoringHiddenDock.size.height);
                frame.origin.y = MAX(frame.origin.y, screenVisibleFrameIgnoringHiddenDock.origin.y);
                double freeSpaceOnBottom = MIN(0, screenVisibleFrameIgnoringHiddenDock.size.height - frame.size.height - (frame.origin.y - screenVisibleFrameIgnoringHiddenDock.origin.y));
                frame.origin.y += freeSpaceOnBottom;
            } else {
                frame.size.height = screenVisibleFrameIgnoringHiddenDock.size.height;
                frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;
            }
            frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;

            if (frame.size.width > 0) {
                [[self window] setFrame:frame display:YES];
            }
            break;

        case WINDOW_TYPE_RIGHT_PARTIAL:
            edgeSpanning = NO;
        case WINDOW_TYPE_RIGHT:
            PtyLog(@"Window type = RIGHT, desired cols=%d", desiredColumns_);
            // If the screen grew and the window was smaller than the desired number of columns, grow it.
            if (desiredColumns_ > 0) {
                frame.size.width = MIN(screenVisibleFrame.size.width,
                                       [[session textview] charWidth] * desiredColumns_ + 2 * MARGIN);
            } else {
                frame.size.width = MIN(screenVisibleFrame.size.width, frame.size.width);
            }
            if (!edgeSpanning) {
                frame.size.height = MIN(frame.size.height, screenVisibleFrameIgnoringHiddenDock.size.height);
                frame.origin.y = MAX(frame.origin.y, screenVisibleFrameIgnoringHiddenDock.origin.y);
                double freeSpaceOnBottom = MIN(0, screenVisibleFrameIgnoringHiddenDock.size.height - frame.size.height - (frame.origin.y - screenVisibleFrameIgnoringHiddenDock.origin.y));
                frame.origin.y += freeSpaceOnBottom;
            } else {
                frame.size.height = screenVisibleFrameIgnoringHiddenDock.size.height;
                frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;
            }
            frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x + screenVisibleFrameIgnoringHiddenDock.size.width - frame.size.width;

            if (frame.size.width > 0) {
                [[self window] setFrame:frame display:YES];
            }
            break;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            PtyLog(@"Window type = NORMAL, NO_TITLE_BAR, or LION_FULL_SCREEN");
            if ([self updateSessionScrollbars]) {
                PtyLog(@"Fitting tabs to window because scrollbars changed.");
                [self fitTabsToWindow];
            }
            break;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            PtyLog(@"Window type = FULL SCREEN");
            if ([screen frame].size.width > 0) {
                // This is necessary when restoring a traditional fullscreen window while scrollbars are
                // forced on systemwide.
                BOOL changedScrollBars = [self updateSessionScrollbars];
                NSRect originalFrame = self.window.frame;
                PtyLog(@"set window to screen's frame");
                if (windowType_ == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
                    [[self window] setFrame:[self traditionalFullScreenFrameForScreen:screen] display:YES];
                } else {
                    [[self window] setFrame:[screen frame] display:YES];
                }
                if (changedScrollBars && NSEqualSizes(self.window.frame.size, originalFrame.size)) {
                    DLog(@"Fitting tabs to window when canonicalizing fullscreen window because of scrollbar change");
                    [self fitTabsToWindow];
                }
            }
            break;

        default:
            break;
    }

    [_contentView updateToolbeltFrame];
}

- (void)screenParametersDidChange
{
    PtyLog(@"Screen parameters changed.");
    [self canonicalizeWindowFrame];
}

- (void)windowDidResignKey:(NSNotification *)aNotification {
    for (PTYSession *aSession in [self allSessions]) {
        if ([[aSession textview] isFindingCursor]) {
            [[aSession textview] endFindCursor];
        }
        [[aSession textview] removeUnderline];
    }

    PtyLog(@"PseudoTerminal windowDidResignKey");
    if (togglingFullScreen_) {
        PtyLog(@"windowDidResignKey returning because togglingFullScreen.");
        return;
    }

    NSArray<NSWindowController *> *siblings = [[iTermHotKeyController sharedInstance] siblingWindowControllersOf:self];
    NSWindowController *newKeyWindowController = [[NSApp keyWindow] windowController];
    if (![siblings containsObject:newKeyWindowController]) {
        [[iTermHotKeyController sharedInstance] autoHideHotKeyWindows:siblings];
    }

    [_contentView.tabBarControl setFlashing:NO];
    _contentView.tabBarControl.cmdPressed = NO;

    if ([[pbHistoryView window] isVisible] ||
        [[autocompleteView window] isVisible] ||
        [[commandHistoryPopup window] isVisible] ||
        [[_directoriesPopupWindowController window] isVisible]) {
        return;
    }

    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignKey:%@]",
          __FILE__, __LINE__, aNotification);

    if (_fullScreen) {
        [_contentView.tabBarControl setFlashing:NO];
        [self showMenuBar];
    }
    // update the cursor
    [[[self currentSession] textview] refresh];
    [[[self currentSession] textview] setNeedsDisplay:YES];

    // Note that if you have multiple displays you can see a lion fullscreen window when it's
    // not key.
    for (PTYSession* aSession in [self allSessions]) {
        [[aSession view] setBackgroundDimmed:YES];
    }

    for (PTYSession* aSession in [self allSessions]) {
        [aSession setFocused:NO];
    }

    [_contentView updateDivisionView];
}

- (void)windowDidBecomeMain:(NSNotification *)notification {
#if ENABLE_SHORTCUT_ACCESSORY
    _shortcutAccessoryViewController.isMain = YES;
#endif
}

- (void)windowDidResignMain:(NSNotification *)aNotification {
#if ENABLE_SHORTCUT_ACCESSORY
    _shortcutAccessoryViewController.isMain = NO;
#endif
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignMain:%@]",
          __FILE__, __LINE__, aNotification);
    NSArray<NSWindowController *> *siblings = [[iTermHotKeyController sharedInstance] siblingWindowControllersOf:self];
    NSWindowController *newMainWindowController = [[NSApp mainWindow] windowController];
    if (![siblings containsObject:newMainWindowController]) {
        [[iTermHotKeyController sharedInstance] autoHideHotKeyWindows:siblings];
    }
    
    // update the cursor
    [[[self currentSession] textview] refresh];
    [[[self currentSession] textview] setNeedsDisplay:YES];
}

- (BOOL)isEdgeWindow
{
    switch (windowType_) {
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return YES;

        default:
            return NO;
    }
}

- (BOOL)anyFullScreen
{
    return _fullScreen || lionFullScreen_;
}

- (BOOL)lionFullScreen
{
    return lionFullScreen_;
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize {
    PtyLog(@"%s(%d):-[PseudoTerminal windowWillResize: obj=%p, proposedFrameSize width = %f; height = %f]",
           __FILE__, __LINE__, [self window], proposedFrameSize.width, proposedFrameSize.height);
    if (self.togglingLionFullScreen || self.lionFullScreen) {
        return proposedFrameSize;
    }
    // Find the session for the current pane of the current tab.
    PTYTab* tab = [self currentTab];
    PTYSession* session = [tab activeSession];

    // Get the width and height of characters in this session.
    float charWidth = [[session textview] charWidth];
    float charHeight = [[session textview] lineHeight];

    // Decide when to snap.  (We snap unless control, and only control, is held down.)
    const NSUInteger theMask =
        (NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask | NSShiftKeyMask);
    BOOL modifierDown =
        (([[NSApp currentEvent] modifierFlags] & theMask) == NSControlKeyMask);
    BOOL snapWidth = !modifierDown;
    BOOL snapHeight = !modifierDown;
    if (sender != [self window]) {
      snapWidth = snapHeight = NO;
    }

    // If resizing a full-width/height X-of-screen window in a direction perpendicular to the screen
    // edge it's attached to, turn off snapping in the direction parallel to the edge.
    if (windowType_ == WINDOW_TYPE_RIGHT || windowType_ == WINDOW_TYPE_LEFT) {
        if (proposedFrameSize.height == self.window.frame.size.height) {
            snapHeight = NO;
        }
    }
    if (windowType_ == WINDOW_TYPE_TOP || windowType_ == WINDOW_TYPE_BOTTOM) {
        if (proposedFrameSize.width == self.window.frame.size.width) {
            snapWidth = NO;
        }
    }

    // There's an advanced preference to turn off snapping globally.
    if ([iTermAdvancedSettingsModel disableWindowSizeSnap]) {
        snapWidth = snapHeight = NO;
    }

    // Compute proposed tab size (window minus decorations).
    NSSize decorationSize = [self windowDecorationSize];
    NSSize tabSize = NSMakeSize(proposedFrameSize.width - decorationSize.width,
                                proposedFrameSize.height - decorationSize.height);

    // Snap proposed tab size to grid.  The snapping uses a grid spaced to
    // match the current pane's character size and aligned so margins are
    // correct if all we have is a single pane.
    BOOL hasScrollbar = [self scrollbarShouldBeVisible];
    NSSize contentSize =
        [NSScrollView contentSizeForFrameSize:tabSize
                  horizontalScrollerClass:nil
                    verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                               borderType:NSNoBorder
                              controlSize:NSRegularControlSize
                            scrollerStyle:[self scrollerStyle]];

    int screenWidth = (contentSize.width - MARGIN * 2) / charWidth;
    int screenHeight = (contentSize.height - VMARGIN * 2) / charHeight;

    if (snapWidth) {
      contentSize.width = screenWidth * charWidth + MARGIN * 2;
    }
    if (snapHeight) {
      contentSize.height = screenHeight * charHeight + VMARGIN * 2;
    }
    tabSize =
        [PTYScrollView frameSizeForContentSize:contentSize
                       horizontalScrollerClass:nil
                         verticalScrollerClass:hasScrollbar ? [PTYScroller class] : nil
                                    borderType:NSNoBorder
                                   controlSize:NSRegularControlSize
                                 scrollerStyle:[self scrollerStyle]];
    // Respect minimum tab sizes.
    for (NSTabViewItem* tabViewItem in [_contentView.tabView tabViewItems]) {
        PTYTab* theTab = [tabViewItem identifier];
        NSSize minTabSize = [theTab minSize];
        tabSize.width = MAX(tabSize.width, minTabSize.width);
        tabSize.height = MAX(tabSize.height, minTabSize.height);
    }

    // Compute new window size from tab size.
    proposedFrameSize.width = tabSize.width + decorationSize.width;
    proposedFrameSize.height = tabSize.height + decorationSize.height;

    // Apply maximum window size.
    NSSize maxFrameSize = [self maxFrame].size;
    proposedFrameSize.height = MIN(maxFrameSize.height, proposedFrameSize.height);

    // If snapping, reject the new size if the mouse has not moved at least
    // half the current grid size in a given direction.  This is really
    // important to the feel of the snapping, especially when the window is
    // not aligned to the grid (e.g. after switching to a tab with a
    // different font size).
    NSSize senderSize = [sender frame].size;
    if (snapWidth) {
      CGFloat deltaX = floor(fabs(senderSize.width - proposedFrameSize.width));
      if (deltaX < floor(charWidth / 2)) {
        proposedFrameSize.width = senderSize.width;
      }
    }
    if (snapHeight) {
      int deltaY = floor(fabs(senderSize.height - proposedFrameSize.height));
      if (deltaY < floor(charHeight / 2)) {
        proposedFrameSize.height = senderSize.height;
      }
    }

    PtyLog(@"Accepted size: %fx%f", proposedFrameSize.width, proposedFrameSize.height);

    return proposedFrameSize;
}

- (void)invalidateRestorableState
{
    [[self window] invalidateRestorableState];
}

- (NSArray *)uniqueTmuxControllers
{
    NSMutableSet *controllers = [NSMutableSet set];
    for (PTYTab *tab in [self tabs]) {
        BOOL hasClient = NO;
        for (PTYSession *aSession in [tab sessions]) {
            if ([aSession isTmuxClient]) {
                hasClient = YES;
                break;
            }
        }
        if (hasClient) {
            TmuxController *c = [tab tmuxController];
            if (c) {
                [controllers addObject:c];
            }
        }
    }
    return [controllers allObjects];
}

- (void)tmuxTabLayoutDidChange:(BOOL)nontrivialChange
{
    if (liveResize_) {
        if (nontrivialChange) {
            postponedTmuxTabLayoutChange_ = YES;
        }
        return;
    }
    for (TmuxController *controller in [self uniqueTmuxControllers]) {
        if ([controller hasOutstandingWindowResize]) {
            return;
        }
    }

    [self beginTmuxOriginatedResize];
    [self fitWindowToTabs];
    [self endTmuxOriginatedResize];
}

- (void)saveTmuxWindowOrigins
{
    for (TmuxController *tc in [self uniqueTmuxControllers]) {
        [tc saveWindowOrigins];
    }
}

- (void)windowDidChangeScreen:(NSNotification *)notification {
    // This gets called when any part of the window enters or exits the screen and
    // appears to be spuriously called for nonnative fullscreen windows.
    DLog(@"windowDidChangeScreen called. This is known to happen when the screen didn't really change! screen=%@",
         self.window.screen);
    [self canonicalizeWindowFrame];
}

- (void)windowDidMove:(NSNotification *)notification
{
    DLog(@"%@: Window %@ moved. Called from %@", self, self.window, [NSThread callStackSymbols]);
    [self saveTmuxWindowOrigins];
}

- (void)windowDidResize:(NSNotification *)aNotification {
    lastResizeTime_ = [[NSDate date] timeIntervalSince1970];
    if (zooming_) {
        // Pretend nothing happened to avoid slowing down zooming.
        return;
    }

    PtyLog(@"windowDidResize to: %fx%f", [[self window] frame].size.width, [[self window] frame].size.height);
    PtyLog(@"%@", [NSThread callStackSymbols]);

    [SessionView windowDidResize];
    if (togglingFullScreen_) {
        PtyLog(@"windowDidResize returning because togglingFullScreen.");
        return;
    }

    // Adjust the size of all the sessions.
    PtyLog(@"windowDidResize - call repositionWidgets");
    [self repositionWidgets];

    [self notifyTmuxOfWindowResize];
    // windowDidMove does not get called if the origin changes because of a resize.
    [self saveTmuxWindowOrigins];

    for (PTYTab *aTab in [self tabs]) {
        if ([aTab isTmuxTab]) {
            [aTab updateFlexibleViewColors];
        }
    }

    self.timeOfLastResize = [NSDate timeIntervalSinceReferenceDate];
    [self setWindowTitle];
    [self fitTabsToWindow];

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidResize"
                                                        object:self
                                                      userInfo:nil];
    [self invalidateRestorableState];

    // If the toolbelt changed size by autoresizing, keep things in sync.
    _contentView.toolbeltWidth = _contentView.toolbelt.frame.size.width;
}

- (void)clearTransientTitle {
    self.timeOfLastResize = 0;
}

- (BOOL)isShowingTransientTitle {
    const NSTimeInterval timeSinceLastResize =
        [NSDate timeIntervalSinceReferenceDate] - self.timeOfLastResize;
    static const NSTimeInterval kTimeToPreserveTemporaryTitle = 0.7;
    return timeSinceLastResize < kTimeToPreserveTemporaryTitle;
}
- (void)updateUseTransparency {
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateUseTransparencyMenuItem];
    for (PTYSession* aSession in [self allSessions]) {
        [[aSession view] setNeedsDisplay:YES];
    }
    [[self currentTab] recheckBlur];
}

- (IBAction)toggleUseTransparency:(id)sender
{
    useTransparency_ = !useTransparency_;
    [self updateUseTransparency];
    restoreUseTransparency_ = NO;
}

- (BOOL)useTransparency
{
    if ([self lionFullScreen]) {
        return NO;
    }
    return useTransparency_;
}

// Like toggleFullScreenMode but does nothing if it's already fullscreen.
// Save to call from a timer.
- (void)enterFullScreenMode
{
    _haveDelayedEnterFullScreenMode = NO;
    if (!togglingFullScreen_ &&
        !togglingLionFullScreen_ &&
        ![self anyFullScreen]) {
        [self toggleFullScreenMode:nil];
    }
}

- (NSRect)traditionalFullScreenFrame {
    return [self traditionalFullScreenFrameForScreen:self.window.screen];
}

- (NSRect)traditionalFullScreenFrameForScreen:(NSScreen *)screen {
    NSRect screenFrame = [screen frame];
    NSRect frameMinusMenuBar = screenFrame;
    frameMinusMenuBar.size.height -= [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    BOOL menuBarIsVisible = NO;

    if (![iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen]) {
        // Menu bar can show in fullscreen...
        if (IsMavericksOrLater()) {
            // There is a menu bar on all screens.
            menuBarIsVisible = YES;
        } else if ([[NSScreen screens] objectAtIndex:0] == screen) {
            // There is a menu bar on the first screen and this window is on the first screen.
            menuBarIsVisible = YES;
        }
    }

    return menuBarIsVisible ? frameMinusMenuBar : screenFrame;
}

// Like toggleTraditionalFullScreenMode but does nothing if it's already
// fullscreen. Save to call from a timer.
- (void)enterTraditionalFullScreenMode
{
    if (!togglingFullScreen_ &&
        !togglingLionFullScreen_ &&
        ![self anyFullScreen]) {
        [self toggleTraditionalFullScreenMode];
    }
}

- (BOOL)togglingLionFullScreen {
    return togglingLionFullScreen_;
}

- (IBAction)toggleFullScreenMode:(id)sender
{
    DLog(@"toggleFullScreenMode:. window type is %d", windowType_);
    if ([self lionFullScreen] ||
        (windowType_ != WINDOW_TYPE_TRADITIONAL_FULL_SCREEN &&
         !self.isHotKeyWindow &&  // NSWindowCollectionBehaviorFullScreenAuxiliary window can't enter Lion fullscreen mode properly
         [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren])) {
        // Native fullscreen path
        [[self ptyWindow] performSelector:@selector(toggleFullScreen:) withObject:self];
        if (lionFullScreen_) {
            // will exit fullscreen
            DLog(@"Set window type to lion fs");
            windowType_ = WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            // Will enter fullscreen
            DLog(@"Set saved window type to %d before setting window type to normal in preparation for going fullscreen", savedWindowType_);
            savedWindowType_ = windowType_;
            windowType_ = WINDOW_TYPE_NORMAL;
        }
        // TODO(georgen): toggle enabled status of use transparency menu item
        return;
    }

    [self toggleTraditionalFullScreenMode];
}

- (void)delayedEnterFullscreen
{
    if (windowType_ == WINDOW_TYPE_LION_FULL_SCREEN &&
        [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren]) {
        if (![[[iTermController sharedInstance] keyTerminalWindow] lionFullScreen]) {
            // call enter(Traditional)FullScreenMode instead of toggle... because
            // when doing a lion resume, the window may be toggled immediately
            // after creation by the window restorer.
            _haveDelayedEnterFullScreenMode = YES;
            [self performSelector:@selector(enterFullScreenMode)
                       withObject:nil
                       afterDelay:0];
        }
    } else if (!_fullScreen) {
        [self performSelector:@selector(enterTraditionalFullScreenMode)
                   withObject:nil
                   afterDelay:0];
    }
}

// Returns YES if a change was made.
- (BOOL)updateSessionScrollbars {
    BOOL changed = NO;
    BOOL hasScrollbar = [self scrollbarShouldBeVisible];
    NSScrollerStyle style = [self scrollerStyle];
    for (PTYSession *aSession in [self allSessions]) {
        if ([aSession setScrollBarVisible:hasScrollbar style:style]) {
            changed = YES;
        }
    }

    return changed;
}

- (NSUInteger)styleMask {
    return [PseudoTerminal styleMaskForWindowType:windowType_ hotkeyWindowType:_hotkeyWindowType];
}

// This is a hack to fix the problem of exiting a fullscreen window that as never not-fullscreen.
// We need to have some size to go to. This method computes the size based on the current session's
// profile's rows and columns setting plus the window decoration size. It's sort of arbitrary
// because split panes will have to share that space, but there's no perfect solution to this issue.
- (NSSize)preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration {
    PTYSession *session = [self currentSession];
    PTYTextView *textView = session.textview;
    NSSize cellSize = NSMakeSize(textView.charWidth, textView.lineHeight);
    NSSize decorationSize = [self windowDecorationSize];
    VT100GridSize sessionSize = VT100GridSizeMake([session.profile[KEY_COLUMNS] intValue],
                                                  [session.profile[KEY_ROWS] intValue]);
    return NSMakeSize(MARGIN * 2 + sessionSize.width * cellSize.width + decorationSize.width,
                      VMARGIN * 2 + sessionSize.height * cellSize.height + decorationSize.height);
}

- (void)toggleTraditionalFullScreenMode
{
    [SessionView windowDidResize];
    PtyLog(@"toggleFullScreenMode called");
    CGFloat savedToolbeltWidth = _contentView.toolbeltWidth;
    if (!_fullScreen) {
        oldFrame_ = self.window.frame;
        oldFrameSizeIsBogus_ = NO;
        savedWindowType_ = windowType_;
#if ENABLE_SHORTCUT_ACCESSORY
        if ([_shortcutAccessoryViewController respondsToSelector:@selector(removeFromParentViewController)]) {
            [_shortcutAccessoryViewController removeFromParentViewController];
        }
#endif
        windowType_ = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        [self.window setOpaque:NO];
        self.window.alphaValue = 0;
        self.window.styleMask = [self styleMask];
        [self.window setFrame:[self traditionalFullScreenFrameForScreen:self.window.screen]
                      display:YES];
        self.window.alphaValue = 1;
    } else {
        [self showMenuBar];
        windowType_ = savedWindowType_;
        self.window.styleMask = [self styleMask];

        // This will be close but probably not quite right because tweaking to the decoration size
        // happens later.
        if (oldFrameSizeIsBogus_) {
            oldFrame_.size = [self preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration];
        }
        [self.window setFrame:oldFrame_ display:YES];
#if ENABLE_SHORTCUT_ACCESSORY
        if ([self.window respondsToSelector:@selector(addTitlebarAccessoryViewController:)] &&
            (self.window.styleMask & NSTitledWindowMask)) {
            [self.window addTitlebarAccessoryViewController:_shortcutAccessoryViewController];
            [self updateWindowNumberVisibility:nil];
        }
#endif
        PtyLog(@"toggleFullScreenMode - allocate new terminal");
    }
    [self.window setHasShadow:(windowType_ == WINDOW_TYPE_NORMAL)];

    if (!_fullScreen &&
        [iTermPreferences boolForKey:kPreferenceKeyDisableFullscreenTransparencyByDefault]) {
        oldUseTransparency_ = useTransparency_;
        useTransparency_ = NO;
        restoreUseTransparency_ = YES;
    } else {
        if (_fullScreen && restoreUseTransparency_) {
            useTransparency_ = oldUseTransparency_;
        } else {
            restoreUseTransparency_ = NO;
        }
    }
    _fullScreen = !_fullScreen;
    [_contentView.tabBarControl updateFlashing];
    togglingFullScreen_ = YES;
    _contentView.toolbeltWidth = savedToolbeltWidth;
    [_contentView constrainToolbeltWidth];
    [_contentView updateToolbelt];
    [self updateUseTransparency];

    if (_fullScreen) {
        PtyLog(@"toggleFullScreenMode - call adjustFullScreenWindowForBottomBarChange");
        [self fitTabsToWindow];
        [self hideMenuBar];
    }

    // The toolbelt may try to become the first responder.
    [[self window] makeFirstResponder:[[self currentSession] textview]];

    if (!_fullScreen) {
        // Find the largest possible session size for the existing window frame
        // and fit the window to an imaginary session of that size.
        NSSize contentSize = [[[self window] contentView] frame].size;
        if (_contentView.shouldShowToolbelt) {
            contentSize.width -= _contentView.toolbelt.frame.size.width;
        }
        if ([self tabBarShouldBeVisible]) {
            switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
                case PSMTab_LeftTab:
                    contentSize.width -= _contentView.leftTabBarWidth;
                    break;

                case PSMTab_TopTab:
                case PSMTab_BottomTab:
                    contentSize.height -= kHorizontalTabBarHeight;
                    break;
            }
        }
        if ([self haveLeftBorder]) {
            --contentSize.width;
        }
        if ([self haveRightBorder]) {
            --contentSize.width;
        }
        if ([self haveBottomBorder]) {
            --contentSize.height;
        }
        if ([self haveTopBorder]) {
            --contentSize.height;
        }

        [self fitWindowToTabSize:contentSize];
    }
    togglingFullScreen_ = NO;
    PtyLog(@"toggleFullScreenMode - calling updateSessionScrollbars");
    [self updateSessionScrollbars];
    PtyLog(@"toggleFullScreenMode - calling fitTabsToWindow");
    [self repositionWidgets];

    if (!_fullScreen && oldFrameSizeIsBogus_) {
        // The window frame can be established exactly, now.
        if (oldFrameSizeIsBogus_) {
            oldFrame_.size = [self preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration];
        }
        [self.window setFrame:oldFrame_ display:YES];
    }

    [self fitTabsToWindow];
    PtyLog(@"toggleFullScreenMode - calling fitWindowToTabs");
    [self fitWindowToTabsExcludingTmuxTabs:YES];
    for (TmuxController *c in [self uniqueTmuxControllers]) {
        [c windowDidResize:self];
    }

    PtyLog(@"toggleFullScreenMode - calling setWindowTitle");
    [self setWindowTitle];
    PtyLog(@"toggleFullScreenMode - calling window update");
    [[self window] update];
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    if (_fullScreen) {
        [self notifyTmuxOfWindowResize];
    }
    PtyLog(@"toggleFullScreenMode returning");
    togglingFullScreen_ = false;

    [self.window performSelector:@selector(makeKeyAndOrderFront:) withObject:nil afterDelay:0];
    [self.window makeFirstResponder:[[self currentSession] textview]];
    [self refreshTools];
    [self updateTabColors];
    [self saveTmuxWindowOrigins];
}

- (BOOL)fullScreen
{
    return _fullScreen;
}

- (BOOL)tabBarShouldBeVisible {
    return _contentView.tabBarShouldBeVisible;
}

- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)n {
    return [_contentView tabBarShouldBeVisibleWithAdditionalTabs:n];
}

- (NSScrollerStyle)scrollerStyle
{
    if ([self anyFullScreen]) {
        return NSScrollerStyleOverlay;
    } else {
        return [NSScroller preferredScrollerStyle];
    }
}

- (BOOL)scrollbarShouldBeVisible {
    return _contentView.scrollbarShouldBeVisible;
}

- (void)windowWillStartLiveResize:(NSNotification *)notification
{
    liveResize_ = YES;
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
    NSScreen *screen = self.window.screen;
    NSRect frame = self.window.frame;
    CGRect screenVisibleFrame = [screen visibleFrame];
    CGRect screenVisibleFrameIgnoringHiddenDock = [screen visibleFrameIgnoringHiddenDock];

    switch (windowType_) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            frame.origin.y = screenVisibleFrame.origin.y + screenVisibleFrame.size.height - frame.size.height;
            if ((frame.size.width < screenVisibleFrameIgnoringHiddenDock.size.width)) {
                windowType_ = WINDOW_TYPE_TOP_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_TOP;
            }
            // desiredRows/Columns get reset here to fix issue 4073. If you manually resize a window
            // then its desired size becomes irrelevant; we want it to preserve the size you set
            // and forget about the size in its profile. This way it will go back to the old size
            // when toggling out of fullscreen.
            desiredRows_ = -1;
            break;

        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;
            if (frame.size.width < screenVisibleFrameIgnoringHiddenDock.size.width) {
                windowType_ = WINDOW_TYPE_BOTTOM_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_BOTTOM;
            }
            desiredRows_ = -1;
            break;

        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;
            if (frame.size.height < screenVisibleFrameIgnoringHiddenDock.size.height) {
                windowType_ = WINDOW_TYPE_LEFT_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_LEFT;
            }
            desiredColumns_ = -1;
            break;

        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x + screenVisibleFrameIgnoringHiddenDock.size.width - frame.size.width;
            if (frame.size.height < screenVisibleFrameIgnoringHiddenDock.size.height) {
                windowType_ = WINDOW_TYPE_RIGHT_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_RIGHT;
            }
            desiredColumns_ = -1;
            break;

        default:
            break;
    }
    if (!NSEqualRects(frame, self.window.frame)) {
        [[self window] setFrame:frame display:NO];
    }

    liveResize_ = NO;
    BOOL wasZooming = zooming_;
    zooming_ = NO;
    if (wasZooming) {
        // Reached zoom size. Update size.
        [self windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification
                                                            object:nil]];
    }
    if (postponedTmuxTabLayoutChange_) {
        [self tmuxTabLayoutDidChange:YES];
        postponedTmuxTabLayoutChange_ = NO;
    }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    DLog(@"Window will enter lion fullscreen");
    togglingLionFullScreen_ = YES;
    [self repositionWidgets];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    DLog(@"Window did enter lion fullscreen");

    zooming_ = NO;
    togglingLionFullScreen_ = NO;
    lionFullScreen_ = YES;
    [_contentView.tabBarControl updateFlashing];
    [_contentView updateToolbelt];
    // Set scrollbars appropriately
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self invalidateRestorableState];
    [self notifyTmuxOfWindowResize];
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    [self saveTmuxWindowOrigins];
    [self.window makeFirstResponder:self.currentSession.textview];
    if (_didEnterLionFullscreen) {
        _didEnterLionFullscreen(self);
        [_didEnterLionFullscreen release];
        _didEnterLionFullscreen = nil;
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    DLog(@"Window will exit lion fullscreen");
    exitingLionFullscreen_ = YES;
    [_contentView.tabBarControl updateFlashing];
    [self fitTabsToWindow];
    [self repositionWidgets];
    self.window.hasShadow = YES;
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    DLog(@"Window did exit lion fullscreen");
    exitingLionFullscreen_ = NO;
    zooming_ = NO;
    lionFullScreen_ = NO;
    [_contentView.tabBarControl updateFlashing];
    // Set scrollbars appropriately
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self repositionWidgets];
    [self invalidateRestorableState];
    [_contentView updateToolbelt];

    DLog(@"Window did exit fullscreen. Set window type to %d", savedWindowType_);
    windowType_ = savedWindowType_;
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    [self.currentTab recheckBlur];
    [self notifyTmuxOfWindowResize];
    [self saveTmuxWindowOrigins];
    [self.window makeFirstResponder:self.currentSession.textview];
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame
{
    // Disable redrawing during zoom-initiated live resize.
    zooming_ = YES;
    if (togglingLionFullScreen_) {
        // Tell it to use the whole screen when entering Lion fullscreen.
        // This is actually called twice in a row when entering fullscreen.
        return defaultFrame;
    }

    // This function attempts to size the window to fit the screen with exactly
    // MARGIN/VMARGIN-sized margins for the current session. If there are split
    // panes then the margins probably won't turn out perfect. If other tabs have
    // a different char size, they will also have imperfect margins.
    float decorationHeight = [sender frame].size.height -
        [[[[self currentSession] view] scrollview] documentVisibleRect].size.height + VMARGIN * 2;
    float decorationWidth = [sender frame].size.width -
        [[[[self currentSession] view] scrollview] documentVisibleRect].size.width + MARGIN * 2;

    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];
    if (charHeight < 1 || charWidth < 1) {
        DLog(@"During windowWillUseStandardFrame:defaultFrame:, charWidth or charHeight are less "
             @"than 1 so using default frame. This is expected on 10.10 while restoring a "
             @"fullscreen window.");
        return defaultFrame;
    }
    NSRect proposedFrame;
    // Initially, set the proposed x-origin to remain unchanged in case we're
    // zooming vertically only. The y-origin always goes to the top of the screen
    // which is what the defaultFrame contains.
    proposedFrame.origin.x = [sender frame].origin.x;
    proposedFrame.origin.y = defaultFrame.origin.y;
    BOOL verticalOnly = NO;

    BOOL maxVerticallyPref;
    if (togglingLionFullScreen_ || [[self ptyWindow] isTogglingLionFullScreen] || [self lionFullScreen]) {
        // Going into lion fullscreen mode. Disregard the "maximize vertically"
        // preference.
        verticalOnly = NO;
    } else {
        maxVerticallyPref = [iTermPreferences boolForKey:kPreferenceKeyMaximizeVerticallyOnly];
        if (maxVerticallyPref ^
            (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0)) {
            verticalOnly = YES;
        }
    }

    if (verticalOnly) {
        // Keep the width the same
        proposedFrame.size.width = [sender frame].size.width;
    } else {
        // Set the width & origin to fill the screen horizontally to a character boundary
        if ([[NSApp currentEvent] modifierFlags] & NSControlKeyMask) {
            // Don't snap width to character size multiples.
            proposedFrame.size.width = defaultFrame.size.width;
            proposedFrame.origin.x = defaultFrame.origin.x;
        } else {
            proposedFrame.size.width = decorationWidth + floor((defaultFrame.size.width - decorationWidth) / charWidth) * charWidth;
        }
        proposedFrame.origin.x = defaultFrame.origin.x;
    }
    if ([[NSApp currentEvent] modifierFlags] & NSControlKeyMask) {
        // Don't snap width to character size multiples.
        proposedFrame.size.height = defaultFrame.size.height;
        proposedFrame.origin.y = defaultFrame.origin.y;
    } else {
        // Set the height to fill the screen to a character boundary.
        proposedFrame.size.height = floor((defaultFrame.size.height - decorationHeight) / charHeight) * charHeight + decorationHeight;
        proposedFrame.origin.y += defaultFrame.size.height - proposedFrame.size.height;
        PtyLog(@"For zoom, default frame is %fx%f, proposed frame is %f,%f %fx%f",
               defaultFrame.size.width, defaultFrame.size.height,
               proposedFrame.origin.x, proposedFrame.origin.y,
               proposedFrame.size.width, proposedFrame.size.height);
    }
    return proposedFrame;
}

- (void)windowWillShowInitial {
    PtyLog(@"windowWillShowInitial");
    iTermTerminalWindow* window = [self ptyWindow];
    // If it's a full or top-of-screen window with a screen number preference, always honor that.
    if (haveScreenPreference_) {
        PtyLog(@"have screen preference is set");
        NSRect frame = [window frame];
        frame.origin = preferredOrigin_;
        [window setFrame:frame display:NO];
        return;
    }
    NSUInteger numberOfTerminalWindows = [[[iTermController sharedInstance] terminals] count];
    if (numberOfTerminalWindows == 1 ||
        ![iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement]) {
        if (!haveScreenPreference_ &&
            [iTermAdvancedSettingsModel rememberWindowPositions]) {
            PtyLog(@"No smart layout");
            NSRect frame = [window frame];
            [self assignUniqueNumberToWindow];
            if ([window setFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, uniqueNumber_]]) {
                frame.origin = [window frame].origin;
                frame.origin.y += [window frame].size.height - frame.size.height;
            } else {
                frame.origin = preferredOrigin_;
            }
            [window setFrame:frame display:NO];
        }
    } else {
        PtyLog(@"Invoking smartLayout");
        [window smartLayout];
    }
}

- (void)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height
{
    PtyLog(@"sessionInitiatedResize");
    // ignore resize request when we are in full screen mode.
    if ([self anyFullScreen]) {
        PtyLog(@"sessionInitiatedResize - in full screen mode");
        return;
    }

    PTYTab *tab = [self tabForSession:session];
    [tab setLockedSession:session];
    [self safelySetSessionSize:session rows:height columns:width];
    PtyLog(@"sessionInitiatedResize - calling fitWindowToTab");
    [self fitWindowToTab:tab];
    PtyLog(@"sessionInitiatedResize - calling fitTabsToWindow");
    [self fitTabsToWindow];
    [tab setLockedSession:nil];
}

// Contextual menu
- (void)editCurrentSession:(id)sender
{
    PTYSession* session = [self currentSession];
    if (!session) {
        return;
    }
    [self editSession:session makeKey:YES];
}

- (void)editSession:(PTYSession *)session makeKey:(BOOL)makeKey {
    Profile* bookmark = [session profile];
    if (!bookmark) {
        return;
    }
    NSString *newGuid = [session divorceAddressBookEntryFromPreferences];
    [[PreferencePanel sessionsInstance] openToProfileWithGuid:newGuid selectGeneralTab:makeKey];
    if (makeKey) {
        [[[PreferencePanel sessionsInstance] window] makeKeyAndOrderFront:nil];
    }
}

- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // Constructs the context menu for right-clicking on a terminal when
    // right click does not paste.
    int nextIndex = 0;
    NSMenuItem *aMenuItem;

    if (theMenu == nil) {
        return;
    }

    // Bookmarks
    [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"New Window",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[self class]],
                                                                    @"Context menu")
                          action:nil
                   keyEquivalent:@""
                         atIndex:nextIndex++];
    [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"New Tab",
                                                                    @"iTerm",
                                                                    [NSBundle bundleForClass:[self class]],
                                                                    @"Context menu")
                          action:nil
                   keyEquivalent:@""
                         atIndex:nextIndex++];

    // Create a menu with a submenu to navigate between tabs if there are more than one
    if ([_contentView.tabView numberOfTabViewItems] > 1) {
        [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select",
                                                                        @"iTerm",
                                                                        [NSBundle bundleForClass:[self class]],
                                                                        @"Context menu")
                              action:nil
                       keyEquivalent:@""
                             atIndex:nextIndex];

        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@""];
        int i;

        for (i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
            aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ #%d",
                                                           [[_contentView.tabView tabViewItemAtIndex: i] label],
                                                           i+1]
                                                   action:@selector(selectTab:)
                                            keyEquivalent:@""];
            [aMenuItem setRepresentedObject:[[_contentView.tabView tabViewItemAtIndex:i] identifier]];
            [aMenuItem setTarget:_contentView.tabView];
            [tabMenu addItem:aMenuItem];
            [aMenuItem release];
        }
        [theMenu setSubmenu:tabMenu forItem:[theMenu itemAtIndex:nextIndex]];
        [tabMenu release];
        ++nextIndex;
    }

    // Separator
    [theMenu insertItem:[NSMenuItem separatorItem] atIndex: nextIndex];

    // Build the bookmarks menu
    NSMenu *aMenu = [[[NSMenu alloc] init] autorelease];

    [[iTermController sharedInstance] addBookmarksToMenu:aMenu
                                            withSelector:@selector(newSessionInWindowAtIndex:)
                                         openAllSelector:@selector(newSessionsInNewWindow:)
                                              startingAt:0];

    [theMenu setSubmenu:aMenu forItem:[theMenu itemAtIndex:0]];

    aMenu = [[[NSMenu alloc] init] autorelease];
    [[iTermController sharedInstance] addBookmarksToMenu:aMenu
                                            withSelector:@selector(newSessionInTabAtIndex:)
                                         openAllSelector:@selector(newSessionsInWindow:)
                                              startingAt:0];

    [theMenu setSubmenu:aMenu forItem:[theMenu itemAtIndex:1]];
}

// NSTabView
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    if (![[self currentSession] exited]) {
        [[self currentSession] setNewOutput:NO];
    }
    // If the user is currently select-dragging the text view, stop it so it
    // doesn't keep going in the background.
    [[[self currentSession] textview] aboutToHide];

    if ([[autocompleteView window] isVisible]) {
        [autocompleteView close];
    }
}

- (void)enableBlur:(double)radius
{
    id window = [self window];
    if (nil != window &&
        [window respondsToSelector:@selector(enableBlur:)]) {
        [window enableBlur:radius];
    }
}

- (void)disableBlur
{
    id window = [self window];
    if (nil != window &&
        [window respondsToSelector:@selector(disableBlur)]) {
        [window disableBlur];
    }
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    DLog(@"Did select tab view %@", tabViewItem);
    [_contentView.tabBarControl setFlashing:YES];

    if (self.autoCommandHistorySessionGuid) {
        [self hideAutoCommandHistory];
    }
    for (PTYSession* aSession in [[tabViewItem identifier] sessions]) {
        [aSession setNewOutput:NO];

        // Background tabs' timers run infrequently so make sure the display is
        // up to date to avoid a jump when it's shown.
        [[aSession textview] setNeedsDisplay:YES];
        [aSession updateDisplay];
        aSession.active = YES;
        [self setDimmingForSession:aSession];
        [[aSession view] setBackgroundDimmed:![[self window] isKeyWindow]];
    }

    for (PTYSession *session in [self allSessions]) {
        if ([[session textview] isFindingCursor]) {
            [[session textview] endFindCursor];
        }
    }
    PTYSession* aSession = [[tabViewItem identifier] activeSession];
    PTYTab *tab = [self tabForSession:aSession];
    if (!_fullScreen) {
        [tab updateLabelAttributes];
        [self setWindowTitle];
    }

    [[self window] makeFirstResponder:[[[tabViewItem identifier] activeSession] textview]];
    if ([tab blur]) {
        [self enableBlur:[tab blurRadius]];
    } else {
        [self disableBlur];
    }

    [_instantReplayWindowController updateInstantReplayView];
    // Post notifications
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[[tabViewItem identifier] activeSession]];

    PTYSession *activeSession = [self currentSession];
    for (PTYSession *s in [self allSessions]) {
      [aSession setFocused:(s == activeSession)];
    }
    [self showOrHideInstantReplayBar];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateBroadcastMenuState];
    [self refreshTools];
    [self updateTabColors];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    [self notifyTmuxOfTabChange];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded]) {
        [self editSession:self.currentSession makeKey:NO];
    }
}

- (void)notifyTmuxOfTabChange {
    if (self.currentTab.isTmuxTab) {
        [self.currentTab.tmuxController setCurrentWindow:self.currentTab.tmuxWindow];
    }
}

- (void)showOrHideInstantReplayBar
{
    PTYSession* aSession = [self currentSession];
    if ([aSession liveSession] && aSession.dvr) {
        [self setInstantReplayBarVisible:YES];
    } else {
        [self setInstantReplayBarVisible:NO];
    }
}

- (void)saveAffinitiesAndOriginsForController:(TmuxController *)tmuxController
{
    [tmuxController saveAffinities];
    [tmuxController saveWindowOrigins];
}

- (void)saveAffinitiesLater:(PTYTab *)theTab
{
    if ([theTab isTmuxTab]) {
        PtyLog(@"Queueing call to saveAffinitiesLater from %@", [NSThread callStackSymbols]);
        [self performSelector:@selector(saveAffinitiesAndOriginsForController:)
                   withObject:[theTab tmuxController]
                   afterDelay:0];
    }
}

- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem
{
    [self saveAffinitiesLater:[tabViewItem identifier]];
        iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
        [itad updateBroadcastMenuState];
}

- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem
{

    [self tabView:tabView willInsertTabViewItem:tabViewItem atIndex:[tabView numberOfTabViewItems]];
    [self saveAffinitiesLater:[tabViewItem identifier]];
        iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
        [itad updateBroadcastMenuState];
}

- (void)tabView:(NSTabView *)tabView
    willInsertTabViewItem:(NSTabViewItem *)tabViewItem
        atIndex:(int)anIndex {
    DLog(@"%@: tabView:%@ willInsertTabViewItem:%@ atIndex:%d", self, tabView, tabViewItem, anIndex);
    PTYTab* theTab = [tabViewItem identifier];
    [theTab setParentWindow:self];
    theTab.delegate = self;
    if ([theTab isTmuxTab]) {
        [theTab recompact];
        [theTab notifyWindowChanged];
        DLog(@"Update client size");
        [[theTab tmuxController] setClientSize:[theTab tmuxSize]];
    }
    [self saveAffinitiesLater:[tabViewItem identifier]];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateBroadcastMenuState];
}

- (BOOL)tabView:(NSTabView*)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem
{
    PTYTab *aTab = [tabViewItem identifier];
    if (aTab == nil) {
        return NO;
    }

    return [self confirmCloseTab:aTab];
}

- (BOOL)tabView:(NSTabView*)aTabView
    shouldDragTabViewItem:(NSTabViewItem *)tabViewItem
               fromTabBar:(PSMTabBarControl *)tabBarControl
{
    return YES;
}

- (BOOL)tabView:(NSTabView*)aTabView
    shouldDropTabViewItem:(NSTabViewItem *)tabViewItem
                 inTabBar:(PSMTabBarControl *)aTabBarControl {
    if (![aTabBarControl tabView]) {
        // Tab dropping outside any existing tabbar to create a new window.
        return [iTermAdvancedSettingsModel allowDragOfTabIntoNewWindow];
    } else if ([[aTabBarControl tabView] indexOfTabViewItem:tabViewItem] != NSNotFound) {
        // Dropping a tab in its own tabbar when it's the only tab causes the
        // window to disappear, so disallow that one case.
        return [[aTabBarControl tabView] numberOfTabViewItems] > 1;
    } else {
        // Drop in tab bar of another window.
        return YES;
    }
}

- (void)tabView:(NSTabView*)aTabView
    willDropTabViewItem:(NSTabViewItem *)tabViewItem
               inTabBar:(PSMTabBarControl *)aTabBarControl {
    PTYTab *aTab = [tabViewItem identifier];
    for (PTYSession* aSession in [aTab sessions]) {
        [aSession setIgnoreResizeNotifications:YES];
    }
}

- (void)_updateTabObjectCounts
{
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        PTYTab *theTab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        [theTab setObjectCount:i+1];
    }
}

- (void)tabView:(NSTabView*)aTabView
    didDropTabViewItem:(NSTabViewItem *)tabViewItem
              inTabBar:(PSMTabBarControl *)aTabBarControl
{
    PTYTab *aTab = [tabViewItem identifier];
    PseudoTerminal *term = (PseudoTerminal *)[aTabBarControl delegate];

    if ([term numberOfTabs] == 1) {
        [term fitWindowToTabs];
    } else {
        [term fitTabToWindow:aTab];
    }
    [self _updateTabObjectCounts];

    // In fullscreen mode reordering the tabs causes the tabview not to be displayed properly.
    // This seems to fix it.
    [_contentView.tabView display];

    for (PTYSession* aSession in [aTab sessions]) {
        [aSession setIgnoreResizeNotifications:NO];
    }
    [self tabsDidReorder];
}

- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem
{
    //NSLog(@"closeWindowForLastTabViewItem: %@", [tabViewItem label]);
    [[self window] close];
}

- (NSImage *)tabView:(NSTabView *)aTabView
    imageForTabViewItem:(NSTabViewItem *)tabViewItem
                 offset:(NSSize *)offset
              styleMask:(unsigned int *)styleMask
{
    NSImage *viewImage;

    if (tabViewItem == [aTabView selectedTabViewItem]) {
        NSView *textview = [tabViewItem view];
        NSRect tabFrame = [_contentView.tabBarControl frame];

        NSRect contentFrame, viewRect;
        contentFrame = viewRect = [textview frame];
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_LeftTab:
                contentFrame.size.width += _contentView.leftTabBarWidth;
                break;

            case PSMTab_TopTab:
            case PSMTab_BottomTab:
                contentFrame.size.height += kHorizontalTabBarHeight;
                break;
        }

        // Grabs whole tabview image.
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *tabViewImage = [[[NSImage alloc] init] autorelease];

        [textview lockFocus];
        NSBitmapImageRep *tabviewRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:viewRect] autorelease];
        [tabViewImage addRepresentation:tabviewRep];
        [textview unlockFocus];

        [viewImage lockFocus];
        BOOL isHorizontal = YES;
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_LeftTab:
                viewRect.origin.x += _contentView.leftTabBarWidth;
                viewRect.size.width -= _contentView.leftTabBarWidth;
                isHorizontal = NO;
                break;

            case PSMTab_TopTab:
                break;

            case PSMTab_BottomTab:
                viewRect.origin.y += kHorizontalTabBarHeight;
                break;
        }

        [tabViewImage drawAtPoint:viewRect.origin
                         fromRect:NSZeroRect
                        operation:NSCompositeSourceOver
                         fraction:1.0];
        [viewImage unlockFocus];

        // Draw over where the tab bar would usually be.
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        // Draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        PSMTabBarControl *control = (PSMTabBarControl *)[aTabView delegate];
        [(id <PSMTabStyle>)[control style] drawBackgroundInRect:tabFrame
                                                          color:nil
                                                     horizontal:isHorizontal];
        [transform invert];
        [transform concat];

        [viewImage unlockFocus];

        offset->width = [(id <PSMTabStyle>)[_contentView.tabBarControl style] leftMarginForTabBarControl];
        if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab) {
            offset->height = kHorizontalTabBarHeight;
        } else if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_BottomTab) {
            offset->height = viewRect.size.height + kHorizontalTabBarHeight;
        } else if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab) {
            offset->height = 0;
            offset->width = 0;
        }
        *styleMask = NSBorderlessWindowMask;
    } else {
        // grabs whole tabview image
        viewImage = [[tabViewItem identifier] image:YES];

        offset->width = [(id <PSMTabStyle>)[_contentView.tabBarControl style] leftMarginForTabBarControl];
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_LeftTab:
                offset->width = _contentView.leftTabBarWidth;
                offset->height = 0;
                break;

            case PSMTab_TopTab:
                offset->height = kHorizontalTabBarHeight;
                break;

            case PSMTab_BottomTab:
                offset->height = [viewImage size].height;
                break;
        }

        *styleMask = NSBorderlessWindowMask;
    }

    return viewImage;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView {
    PtyLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);
    for (PTYSession* session in [self allSessions]) {
        [session setIgnoreResizeNotifications:NO];
    }

    // check window size in case tabs have to be hidden or shown
    if (([_contentView.tabView numberOfTabViewItems] == 1) ||  // just decreased to 1 or increased above 1 and is hidden
        ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar] &&
         ([_contentView.tabView numberOfTabViewItems] > 1 && [_contentView.tabBarControl isHidden]))) {
        // Need to change the visibility status of the tab bar control.
        PtyLog(@"tabViewDidChangeNumberOfTabViewItems - calling fitWindowToTab");

        NSTabViewItem *tabViewItem = [[_contentView.tabView tabViewItems] objectAtIndex:0];
        PTYTab *firstTab = [tabViewItem identifier];

        NSPoint originalOrigin = self.window.frame.origin;
        if (wasDraggedFromAnotherWindow_) {
            // A tab was just dragged out of another window's tabbar into its own window.
            // When this happens, it loses its size. This is our only chance to resize it.
            // So we put it in a mode where it will resize to its "ideal" size instead of
            // its incorrect current size.
            [firstTab setReportIdealSizeAsCurrent:YES];

            // Remove the tab title bar.
            PTYSession *session = firstTab.sessions.firstObject;
            [[session view] setShowTitle:NO adjustScrollView:YES];
        }
        [self fitWindowToTabs];
        [self repositionWidgets];
        if (wasDraggedFromAnotherWindow_) {
            wasDraggedFromAnotherWindow_ = NO;
            [firstTab setReportIdealSizeAsCurrent:NO];
            
            // fitWindowToTabs will detect the window changed sizes and do a bogus move of it in this case.
            if (windowType_ == WINDOW_TYPE_NORMAL ||
                windowType_ == WINDOW_TYPE_NO_TITLE_BAR) {
                [[self window] setFrameOrigin:originalOrigin];
            }
        }
    }

    [self updateTabColors];
    [self _updateTabObjectCounts];

    if (_contentView.tabView.numberOfTabViewItems == 1 &&
        _previousNumberOfTabs == 0 &&
        [iTermProfilePreferences boolForKey:KEY_OPEN_TOOLBELT inProfile:self.currentSession.profile] &&
        !_contentView.shouldShowToolbelt) {
        // This is the first tab of a new window. Open the toolbelt if that's what the profile
        // wants. You can't open the toolbelt until there is at least one session, so that's why
        // it's done here instead of in finishInitializationWithSmartLayout.
        [self toggleToolbeltVisibility:self];
    }

    _previousNumberOfTabs = _contentView.tabView.numberOfTabViewItems;

    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
    [self invalidateRestorableState];
}

- (NSMenu *)tabView:(NSTabView *)tabView menuForTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSMenuItem *item;
    NSMenu *rootMenu = [[[NSMenu alloc] init] autorelease];

    // Create a menu with a submenu to navigate between tabs if there are more than one
    if ([_contentView.tabView numberOfTabViewItems] > 1) {
        NSMenu *tabMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        NSUInteger count = 1;
        for (NSTabViewItem *aTabViewItem in [_contentView.tabView tabViewItems]) {
            NSString *title = [NSString stringWithFormat:@"%@ #%ld", [aTabViewItem label], (unsigned long)count++];
            item = [[[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(selectTab:)
                                        keyEquivalent:@""] autorelease];
            [item setRepresentedObject:[aTabViewItem identifier]];
            [item setTarget:_contentView.tabView];
            [tabMenu addItem:item];
        }

        [rootMenu addItemWithTitle:@"Select"
                            action:nil
                     keyEquivalent:@""];
        [rootMenu setSubmenu:tabMenu forItem:[rootMenu itemAtIndex:0]];
        [rootMenu addItem: [NSMenuItem separatorItem]];
   }

    // add tasks
    item = [[[NSMenuItem alloc] initWithTitle:@"Close Tab"
                                       action:@selector(closeTabContextualMenuAction:)
                                keyEquivalent:@""] autorelease];
    [item setRepresentedObject:tabViewItem];
    [rootMenu addItem:item];

    PTYTab *theTab = [tabViewItem identifier];
    if (![theTab isTmuxTab]) {
        item = [[[NSMenuItem alloc] initWithTitle:@"Duplicate Tab"
                                           action:@selector(duplicateTab:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }

    if ([_contentView.tabView numberOfTabViewItems] > 1) {
        item = [[[NSMenuItem alloc] initWithTitle:@"Move to New Window"
                                           action:@selector(moveTabToNewWindowContextualMenuAction:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }

    if ([_contentView.tabView numberOfTabViewItems] > 1) {
        item = [[[NSMenuItem alloc] initWithTitle:@"Close Other Tabs"
                                           action:@selector(closeOtherTabs:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }

    if ([_contentView.tabView numberOfTabViewItems] > 1) {
        NSString *title;
        if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab) {
            title = @"Close Tabs Below";
        } else {
            title = @"Close Tabs to the Right";
        }
        item = [[[NSMenuItem alloc] initWithTitle:title
                                           action:@selector(closeTabsToTheRight:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }

    // add label
    [rootMenu addItem: [NSMenuItem separatorItem]];
    ColorsMenuItemView *labelTrackView = [[[ColorsMenuItemView alloc]
                                              initWithFrame:NSMakeRect(0, 0, 180, 50)] autorelease];
    item = [[[NSMenuItem alloc] initWithTitle:@"Tab Color"
                                       action:@selector(changeTabColorToMenuAction:)
                                keyEquivalent:@""] autorelease];
    [item setView:labelTrackView];
    [item setRepresentedObject:tabViewItem];
    [rootMenu addItem:item];

    return rootMenu;
}

- (PSMTabBarControl *)tabView:(NSTabView *)aTabView
    newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem
                           atPoint:(NSPoint)point
{
    PTYTab *aTab = [tabViewItem identifier];
    if (aTab == nil) {
        return nil;
    }

    NSWindowController<iTermWindowController> * term =
        [self terminalDraggedFromAnotherWindowAtPoint:point];
    if (([term windowType] == WINDOW_TYPE_NORMAL ||
         [term windowType] == WINDOW_TYPE_NO_TITLE_BAR) &&
        [iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab) {
        [[term window] setFrameTopLeftPoint:point];
    }

    return [term tabBarControl];
}

- (NSArray *)allowedDraggedTypesForTabView:(NSTabView *)aTabView {
    return @[ iTermMovePaneDragType ];
}

- (NSDragOperation)tabView:(NSTabView *)destinationTabView
        draggingEnteredTabBarForSender:(id<NSDraggingInfo>)draggingInfo {
    return NSDragOperationMove;
}

- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id<NSDraggingInfo>)sender
{
    MovePaneController *movePaneController = [MovePaneController sharedInstance];
    PTYSession *session = [movePaneController session];
    PTYTab *tab = [self tabForSession:session];
    BOOL tabSurvives = [[tab sessions] count] > 1;
    if ([session isTmuxClient] && tabSurvives) {
        // Cause the "normal" drop handle to do nothing.
        [[MovePaneController sharedInstance] clearSession];
        // Tell the server to move the pane into its own window and sets
        // an affinity to the destination window.
        [[session tmuxController] breakOutWindowPane:[session tmuxPane]
                                          toTabAside:self.terminalGuid];
        return nil;
    }
    PTYTab *tabToRemove = nil;
    if (tab.realParentWindow == self && tab.sessions.count == 1) {
        // This is an edge case brought to light in issue 4189. If you have a window with a single
        // tab and a single session and you drag the session (by holding cmd+opt+shift and dragging)
        // onto the tab bar, the window disappears. The bug describes a crash, but as of 2.9.20160107
        // it closes the window without crashing.
        //
        // The issue is that calling -removeAndClearSession closes the tab. That has a knock-on
        // effect of closing the window. In this case we must very delicately keep the tab alive
        // until the new tab has been added.
        //
        // We can't just do nothing in this case because if there are multiple tabs this is a valid
        // way to reorder tabs.
        tabToRemove = [[tab retain] autorelease];
        movePaneController.session = nil;
    } else {
        [movePaneController removeAndClearSession];
    }
    PTYTab *theTab = [[[PTYTab alloc] initWithSession:session] autorelease];
    [theTab setActiveSession:session];
    [theTab setParentWindow:self];
    theTab.delegate = self;
    NSTabViewItem *tabViewItem = [[[NSTabViewItem alloc] initWithIdentifier:(id)theTab] autorelease];
    [theTab setTabViewItem:tabViewItem];
    [tabViewItem setLabel:[session name] ? [session name] : @""];

    [theTab numberOfSessionsDidChange];
    [self saveTmuxWindowOrigins];
    
    if (tabToRemove) {
        [self.tabView removeTabViewItem:tabToRemove.tabViewItem];
    }

    return tabViewItem;
}

- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender
{
    return YES;
}

- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)aTabViewItem {
        PTYSession *session = [[aTabViewItem identifier] activeSession];
        return  [NSString stringWithFormat:@"Profile: %@\nCommand: %@",
                                [[session profile] objectForKey:KEY_NAME],
                                [session.shell command] ?: @"None"];
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem
{
    [tabView selectTabViewItem:tabViewItem];
    [self editCurrentSession:self];
}

- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView {
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    // Note: this assume that self is the front window (it should be!). It is smart enough to create
    // a tmux tab if the user wants one (or ask if needed).
    [itad newSession:nil];
}

- (void)tabView:(NSTabView *)tabView updateStateForTabViewItem:(NSTabViewItem *)tabViewItem {
    PTYTab *tab = tabViewItem.identifier;
    [_contentView.tabBarControl setIsProcessing:tab.isProcessing forTabWithIdentifier:tab];
    [_contentView.tabBarControl setIcon:tab.icon forTabWithIdentifier:tab];
    [_contentView.tabBarControl setObjectCount:tab.objectCount forTabWithIdentifier:tab];
}

- (void)updateTabColors {
    for (PTYTab *aTab in [self tabs]) {
        NSTabViewItem *tabViewItem = [aTab tabViewItem];
        PTYSession *aSession = [aTab activeSession];
        NSColor *color = [aSession tabColor];
        [_contentView.tabBarControl setTabColor:color forTabViewItem:tabViewItem];
        if ([_contentView.tabView selectedTabViewItem] == tabViewItem) {
            NSColor* newTabColor = [_contentView.tabBarControl tabColorForTabViewItem:tabViewItem];
            if ([_contentView.tabView numberOfTabViewItems] == 1 &&
                [iTermPreferences boolForKey:kPreferenceKeyHideTabBar] &&
                newTabColor) {
                [[self window] setBackgroundColor:newTabColor];
                [_contentView setColor:newTabColor];
            } else {
                [[self window] setBackgroundColor:nil];
                [_contentView setColor:normalBackgroundColor];
            }
        }
    }
}

- (void)tabsDidReorder {
    TmuxController *controller = nil;
    NSMutableArray *windowIds = [NSMutableArray array];

    for (PTYTab *tab in [self tabs]) {
        TmuxController *tmuxController = tab.tmuxController;
        if (tmuxController) {
            controller = tmuxController;
            [windowIds addObject:@(tab.tmuxWindow)];
        }
    }
    [controller setPartialWindowIdOrder:windowIds];
}

- (PTYTabView *)tabView
{
    return _contentView.tabView;
}

- (BOOL)isInitialized
{
    return _contentView.tabView != nil;
}

- (void)fillPath:(NSBezierPath*)path {
    if ([_contentView.tabBarControl isHidden] && ![self anyFullScreen]) {
        [[NSColor windowBackgroundColor] set];
        [path fill];
        [[NSColor darkGrayColor] set];
        [path stroke];
    } else {
        [_contentView.tabBarControl fillPath:path];
    }
}

- (NSColor *)accessoryTextColor {
    if ([_contentView.tabBarControl isHidden] && ![self anyFullScreen]) {
        return [NSColor blackColor];
    } else {
        return [_contentView.tabBarControl accessoryTextColor];
    }
}

- (void)openPasswordManagerToAccountName:(NSString *)name
                               inSession:(PTYSession *)session {
    DLog(@"openPasswordManagerToAccountName:%@ inSession:%@", name, session);
    [session reveal];
    if (self.window.sheets.count > 0) {
        DLog(@"This window has sheets so not opening pw manager: %@", self.window.sheets);
        DLog(@"The last sheet's view hierarchy:\n%@", [[[self.window.sheets lastObject] contentView] iterm_recursiveDescription]);
        return;
    }
    DLog(@"Show the password manager as a sheet");
    iTermPasswordManagerWindowController *passwordManagerWindowController =
        [[iTermPasswordManagerWindowController alloc] init];
    passwordManagerWindowController.delegate = self;
    [[NSApplication sharedApplication] beginSheet:[passwordManagerWindowController window]
                                   modalForWindow:self.window
                                    modalDelegate:self
                                   didEndSelector:@selector(genericCloseSheet:returnCode:contextInfo:)
                                      contextInfo:passwordManagerWindowController];
    [passwordManagerWindowController selectAccountName:name];
}

- (void)genericCloseSheet:(NSWindow *)sheet
               returnCode:(int)returnCode
              contextInfo:(id)contextInfo {
    [sheet close];
    [sheet release];
}

#pragma mark - iTermInstantReplayDelegate

- (long long)instantReplayCurrentTimestamp {
    DVR* dvr = [[self currentSession] dvr];
    DVRDecoder* decoder = nil;

    if (dvr) {
        decoder = [[self currentSession] dvrDecoder];
        return [decoder timestamp];
    }
    return -1;
}

- (long long)instantReplayFirstTimestamp {
    DVR* dvr = [[self currentSession] dvr];

    if (dvr) {
        return [dvr firstTimeStamp];
    } else {
        return -1;
    }
}

- (long long)instantReplayLastTimestamp {
    DVR* dvr = [[self currentSession] dvr];

    if (dvr) {
        return [dvr lastTimeStamp];
    } else {
        return -1;
    }
}

- (void)replaceSyntheticActiveSessionWithLiveSessionIfNeeded {
    if ([[self currentSession] liveSession]) {
        [self showLiveSession:[[self currentSession] liveSession] inPlaceOf:[self currentSession]];
    }
}

- (void)instantReplaySeekTo:(float)position {
    if (![[self currentSession] liveSession]) {
        [self replaySession:[self currentSession]];
    }
    [[self currentSession] irSeekToAtLeast:[self timestampForFraction:position]];
}

- (void)instantReplayStep:(int)direction {
    [self irAdvance:direction];
    [[self window] makeFirstResponder:[[self currentSession] textview]];
}

- (void)irAdvance:(int)dir {
    if (![[self currentSession] liveSession]) {
        if (dir > 0) {
            // Can't go forward in time from live view (though that would be nice!)
            NSBeep();
            return;
        }
        [self replaySession:[self currentSession]];
    }
    [[self currentSession] irAdvance:dir];
}

- (BOOL)inInstantReplay
{
    return _instantReplayWindowController != nil;
}

- (NSPoint)originForAccessoryOfSize:(NSSize)size {
    NSPoint p;
    NSRect screenRect = self.window.screen.visibleFrame;
    NSRect windowRect = self.window.frame;

    p.x = windowRect.origin.x + round((windowRect.size.width - size.width) / 2);
    if (screenRect.origin.y + size.height < windowRect.origin.y) {
        // Is there space below?
        p.y = windowRect.origin.y - size.height;
    } else if (screenRect.origin.y + screenRect.size.height >
               windowRect.origin.y + windowRect.size.height + size.height) {
        // Is there space above?
        p.y = windowRect.origin.y + windowRect.size.height;
    } else {
        p.y = [_contentView.tabView convertRect:NSMakeRect(0, 0, 0, 0) toView:nil].origin.y - size.height;
    }
    return p;
}

// Toggle instant replay bar.
- (void)showHideInstantReplay
{
    BOOL hide = [self inInstantReplay];
    if (hide) {
        [self closeInstantReplayWindow];
    } else {
        _instantReplayWindowController = [[iTermInstantReplayWindowController alloc] init];
        NSPoint origin =
            [self originForAccessoryOfSize:_instantReplayWindowController.window.frame.size];
        [_instantReplayWindowController.window setFrameOrigin:origin];
        _instantReplayWindowController.delegate = self;
        [_instantReplayWindowController.window orderFront:nil];
        [_instantReplayWindowController updateInstantReplayView];
    }
    [[self window] makeFirstResponder:[[self currentSession] textview]];
}

- (void)closeInstantReplay:(id)sender {
    [self closeInstantReplayWindow];
}

- (void)fitWindowToTab:(PTYTab*)tab
{
    [self fitWindowToTabSize:[tab size]];
}

- (BOOL)sendInputToAllSessions
{
    return [self broadcastMode] != BROADCAST_OFF;
}

- (PTYSession *)syntheticSessionForSession:(PTYSession *)oldSession {
    NSTabViewItem *tabViewItem = [_contentView.tabView selectedTabViewItem];
    if (!tabViewItem) {
        return nil;
    }
    PTYSession *newSession;

    // Initialize a new session
    newSession = [[[PTYSession alloc] init] autorelease];
    // NSLog(@"New session for IR view is at %p", newSession);

    // set our preferences
    [newSession setProfile:[oldSession profile]];
    [[newSession screen] setMaxScrollbackLines:0];
    [self setupSession:newSession title:nil withSize:nil];
    [[newSession view] setViewId:[[oldSession view] viewId]];
    [[newSession view] setShowTitle:[[oldSession view] showTitle] adjustScrollView:YES];

    // Add this session to our term and make it current
    PTYTab *theTab = [tabViewItem identifier];
    newSession.delegate = theTab;

    return newSession;
}

- (void)replaySession:(PTYSession *)oldSession {
    if ([[[oldSession screen] dvr] lastTimeStamp] == 0) {
        // Nothing recorded (not enough memory for one frame, perhaps?).
        return;
    }

    PTYSession *newSession = [self syntheticSessionForSession:oldSession];

    [[self tabForSession:oldSession] setDvrInSession:newSession];
    if (![self inInstantReplay]) {
        [self showHideInstantReplay];
    }
}

- (IBAction)zoomOut:(id)sender {
    [self replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
}

- (IBAction)zoomOnSelection:(id)sender {
    PTYSession *session = [self currentSession];
    iTermSelection *selection = session.textview.selection;
    iTermSubSelection *sub = [selection.allSubSelections lastObject];
    if (sub) {
        [self showRangeOfLines:NSMakeRange(sub.range.coordRange.start.y,
                                           sub.range.coordRange.end.y - sub.range.coordRange.start.y)
                     inSession:session];
    }
}

- (void)showRangeOfLines:(NSRange)rangeOfLines inSession:(PTYSession *)oldSession {
    PTYSession *syntheticSession = [self syntheticSessionForSession:oldSession];
    syntheticSession.textview.cursorVisible = NO;
    [syntheticSession appendLinesInRange:rangeOfLines fromSession:oldSession];
    [[self tabForSession:oldSession] replaceActiveSessionWithSyntheticSession:syntheticSession];
}

- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession {
    PTYTab *theTab = [self tabForSession:replaySession];
    [_instantReplayWindowController updateInstantReplayView];

    [self sessionInitiatedResize:replaySession
                           width:[[liveSession screen] width]
                          height:[[liveSession screen] height]];

    [replaySession retain];
    [theTab showLiveSession:liveSession inPlaceOf:replaySession];
    [replaySession softTerminate];
    [replaySession release];
    [theTab setParentWindow:self];
    [[self window] makeFirstResponder:[[theTab activeSession] textview]];
}

- (void)windowSetFrameTopLeftPoint:(NSPoint)point
{
    [[self window] setFrameTopLeftPoint:point];
}

- (void)windowPerformMiniaturize:(id)sender
{
    [[self window] performMiniaturize:sender];
}

- (void)windowDeminiaturize:(id)sender
{
    [[self window] deminiaturize:sender];
}

- (void)windowOrderFront:(id)sender
{
    [[self window] orderFront:sender];
}

- (void)windowOrderBack:(id)sender
{
    [[self window] orderBack:sender];
}

- (BOOL)windowIsMiniaturized
{
    return [[self window] isMiniaturized];
}

- (NSRect)windowFrame
{
    return [[self window] frame];
}

- (NSScreen*)windowScreen
{
    return [[self window] screen];
}

- (IBAction)irPrev:(id)sender
{
    [self irAdvance:-1];
    [[self window] makeFirstResponder:[[self currentSession] textview]];
    [_instantReplayWindowController updateInstantReplayView];
}

- (IBAction)irNext:(id)sender
{
    [self irAdvance:1];
    [[self window] makeFirstResponder:[[self currentSession] textview]];
    [_instantReplayWindowController updateInstantReplayView];
}

- (void)_openSplitSheetForVertical:(BOOL)vertical
{
    NSString *guid = [SplitPanel showPanelWithParent:self isVertical:vertical];
    if (guid) {
        [self splitVertically:vertical withBookmarkGuid:guid];
    }
}

- (IBAction)stopCoprocess:(id)sender
{
    [[self currentSession] stopCoprocess];
}

- (IBAction)runCoprocess:(id)sender
{
    [NSApp beginSheet:coprocesssPanel_
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:nil
          contextInfo:nil];

    NSArray *mru = [Coprocess mostRecentlyUsedCommands];
    [coprocessCommand_ removeAllItems];
    if (mru.count) {
        [coprocessCommand_ addItemsWithObjectValues:mru];
    }
    [NSApp runModalForWindow:coprocesssPanel_];

    [NSApp endSheet:coprocesssPanel_];
    [coprocesssPanel_ orderOut:self];
}

- (IBAction)coprocessPanelEnd:(id)sender
{
    if (sender == coprocessOkButton_) {
        if ([[[coprocessCommand_ stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            NSBeep();
            return;
        }
        [[self currentSession] launchCoprocessWithCommand:[coprocessCommand_ stringValue]];
    }
    [NSApp stopModal];
}

- (IBAction)coprocessHelp:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.iterm2.com/coprocesses.html"]];
}

- (IBAction)openSplitHorizontallySheet:(id)sender
{
    [self _openSplitSheetForVertical:NO];
}

- (IBAction)openSplitVerticallySheet:(id)sender
{
    [self _openSplitSheetForVertical:YES];
}

- (IBAction)openPasteHistory:(id)sender
{
    if (!pbHistoryView) {
        pbHistoryView = [[PasteboardHistoryWindowController alloc] init];
    }
    [pbHistoryView popWithDelegate:[self currentSession]];
}

- (IBAction)openCommandHistory:(id)sender
{
    if (!commandHistoryPopup) {
        commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] init];
    }
    if ([[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        [commandHistoryPopup popWithDelegate:[self currentSession]];
        [commandHistoryPopup loadCommands:[commandHistoryPopup commandsForHost:[[self currentSession] currentHost]
                                                                partialCommand:[[self currentSession] currentCommand]
                                                                        expand:YES]
                           partialCommand:[[self currentSession] currentCommand]];
    } else {
        [iTermShellHistoryController showInformationalMessage];
    }
}

- (IBAction)openDirectories:(id)sender {
    if (!_directoriesPopupWindowController) {
        _directoriesPopupWindowController = [[DirectoriesPopupWindowController alloc] init];
    }
    if ([[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        [_directoriesPopupWindowController popWithDelegate:[self currentSession]];
        [_directoriesPopupWindowController loadDirectoriesForHost:[[self currentSession] currentHost]];
    } else {
        [iTermShellHistoryController showInformationalMessage];
    }
}

- (void)hideAutoCommandHistory {
    [commandHistoryPopup close];
    self.autoCommandHistorySessionGuid = nil;
}

- (void)hideAutoCommandHistoryForSession:(PTYSession *)session {
    if ([session.guid isEqualToString:self.autoCommandHistorySessionGuid]) {
        [self hideAutoCommandHistory];
        DLog(@"Cancel delayed perform of show ACH window");
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(reallyShowAutoCommandHistoryForSession:)
                                                   object:session];
    }
}

- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix inSession:(PTYSession *)session {
    if ([session.guid isEqualToString:self.autoCommandHistorySessionGuid]) {
        if (!commandHistoryPopup) {
            commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] init];
        }
        NSArray<iTermCommandHistoryCommandUseMO *> *commands = [commandHistoryPopup commandsForHost:[session currentHost]
                                                                                     partialCommand:prefix
                                                                                             expand:NO];
        if (![commands count]) {
            [commandHistoryPopup close];
            return;
        }
        if ([commands count] == 1) {
            iTermCommandHistoryCommandUseMO *commandUse = commands[0];
            if ([commandUse.command isEqualToString:prefix]) {
                [commandHistoryPopup close];
                return;
            }
        }
        if (![[commandHistoryPopup window] isVisible]) {
            [self showAutoCommandHistoryForSession:session];
        }
        [commandHistoryPopup loadCommands:commands
                           partialCommand:prefix];
    }
}

- (void)showAutoCommandHistoryForSession:(PTYSession *)session {
    if ([iTermPreferences boolForKey:kPreferenceAutoCommandHistory]) {
        // Use a delay so we don't get a flurry of windows appearing when restoring arrangements.
        [self performSelector:@selector(reallyShowAutoCommandHistoryForSession:)
                   withObject:session
                   afterDelay:0.2];
    }
}

- (void)reallyShowAutoCommandHistoryForSession:(PTYSession *)session {
    if ([self currentSession] == session && [[self window] isKeyWindow] && [[session currentCommand] length] > 0) {
        self.autoCommandHistorySessionGuid = session.guid;
        if (!commandHistoryPopup) {
            commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] init];
        }
        [commandHistoryPopup popWithDelegate:session];
        [self updateAutoCommandHistoryForPrefix:[session currentCommand] inSession:session];
    }
}

- (BOOL)autoCommandHistoryIsOpenForSession:(PTYSession *)session {
    return [[commandHistoryPopup window] isVisible] && [self.autoCommandHistorySessionGuid isEqualToString:session.guid];
}

- (IBAction)openAutocomplete:(id)sender {
    if (!autocompleteView) {
        autocompleteView = [[AutocompleteView alloc] init];
    }
    if ([[autocompleteView window] isVisible]) {
        [autocompleteView more];
    } else {
        [autocompleteView popWithDelegate:[self currentSession]];
        NSString *currentCommand = [[self currentSession] currentCommand];
        [autocompleteView addCommandEntries:[[self currentSession] autocompleteSuggestionsForCurrentCommand]
                                    context:currentCommand];
    }
}

- (BOOL)canSplitPaneVertically:(BOOL)isVertical withBookmark:(Profile*)theBookmark
{
    if ([self inInstantReplay]) {
    // Things get very complicated in this case. Just disallow it.
        return NO;
    }
    NSFont* asciiFont = [ITAddressBookMgr fontWithDesc:[theBookmark objectForKey:KEY_NORMAL_FONT]];
    NSFont* nonAsciiFont = [ITAddressBookMgr fontWithDesc:[theBookmark objectForKey:KEY_NON_ASCII_FONT]];
    NSSize asciiCharSize = [PTYTextView charSizeForFont:asciiFont
                                      horizontalSpacing:[[theBookmark objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                        verticalSpacing:[[theBookmark objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    NSSize nonAsciiCharSize = [PTYTextView charSizeForFont:nonAsciiFont
                                         horizontalSpacing:[[theBookmark objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                           verticalSpacing:[[theBookmark objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    NSSize charSize = NSMakeSize(MAX(asciiCharSize.width, nonAsciiCharSize.width),
                                 MAX(asciiCharSize.height, nonAsciiCharSize.height));
    NSSize newSessionSize = NSMakeSize(charSize.width * kVT100ScreenMinColumns + MARGIN * 2,
                                       charSize.height * kVT100ScreenMinRows + VMARGIN * 2);

    return [[self currentTab] canSplitVertically:isVertical withSize:newSessionSize];
}

- (void)toggleMaximizeActivePane
{
    if (self.currentTab.activeSession.isTmuxClient) {
        [self.currentTab.activeSession toggleTmuxZoom];
    } else if ([[self currentTab] hasMaximizedPane]) {
        [[self currentTab] unmaximize];
    } else {
        [[self currentTab] maximize];
    }
}

- (void)newWindowWithBookmarkGuid:(NSString*)guid
{
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [[iTermController sharedInstance] launchBookmark:bookmark inTerminal:nil];
    }
}

- (void)newTabWithBookmarkGuid:(NSString*)guid
{
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [[iTermController sharedInstance] launchBookmark:bookmark inTerminal:self];
    }
}


- (void)recreateTab:(PTYTab *)tab
    withArrangement:(NSDictionary *)arrangement
           sessions:(NSArray *)sessions {
    NSInteger tabIndex = [_contentView.tabView indexOfTabViewItemWithIdentifier:tab];
    if (tabIndex == NSNotFound) {
        return;
    }
    NSMutableArray *allSessions = [NSMutableArray array];
    [allSessions addObjectsFromArray:sessions];
    [allSessions addObjectsFromArray:[tab sessions]];
    NSDictionary<NSString *, PTYSession *> *theMap = [PTYTab sessionMapWithArrangement:arrangement
                                                                              sessions:allSessions];

    BOOL ok = (theMap != nil);
    if (ok) {
        // Make sure the proposed tab has at least all the sessions already in the current tab.
        for (PTYSession *sessionInExistingTab in [tab sessions]) {
            BOOL found = NO;
            for (PTYSession *sessionInProposedTab in [theMap allValues]) {
                if (sessionInProposedTab == sessionInExistingTab) {
                    found = YES;
                    break;
                }
            }
            if (!found) {
                ok = NO;
                break;
            }
        }
    }
    if (!ok) {
        // Can't do it. Just add each session as its own tab.
        for (PTYSession *session in sessions) {
            [session revive];
            [self addRevivedSession:session];
        }
        return;
    }
    for (PTYSession *session in sessions) {
        assert([session revive]);
    }

    PTYSession *originalActiveSession = [tab activeSession];
    PTYTab *temporaryTab = [PTYTab tabWithArrangement:arrangement
                                           inTerminal:nil
                                      hasFlexibleView:NO
                                              viewMap:nil
                                           sessionMap:theMap];
    [tab replaceWithContentsOfTab:temporaryTab];
    [tab updatePaneTitles];
    [tab setActiveSession:nil];
    [tab setActiveSession:originalActiveSession];
}

- (void)addTabWithArrangement:(NSDictionary *)arrangement
                     uniqueId:(int)tabUniqueId
                     sessions:(NSArray *)sessions
                 predecessors:(NSArray *)predecessors {
    NSDictionary<NSString *, PTYSession *> *sessionMap = [PTYTab sessionMapWithArrangement:arrangement
                                                                                  sessions:sessions];
    if (!sessionMap) {
        // Can't do it. Just add each session as its own tab.
        for (PTYSession *session in sessions) {
            if ([session revive]) {
                [self addRevivedSession:session];
            }
        }
        return;
    }

    PTYTab *tab = [PTYTab tabWithArrangement:arrangement
                                  inTerminal:self
                             hasFlexibleView:NO
                                     viewMap:nil
                                  sessionMap:sessionMap];
    tab.uniqueId = tabUniqueId;
    for (NSString *theKey in sessionMap) {
        PTYSession *session = sessionMap[theKey];
        assert([session revive]);  // TODO: This isn't guarantted
    }

    [self insertTab:tab atIndex:[self indexForTabWithPredecessors:predecessors]];
    [tab didAddToTerminal:self withArrangement:arrangement];
}

- (NSUInteger)indexOfTabWithUniqueId:(int)uniqueId {
    NSUInteger i = 0;
    for (PTYTab *tab in self.tabs) {
        if (tab.uniqueId == uniqueId) {
            return i;
        }
        i++;
    }
    return NSNotFound;
}

- (int)indexForTabWithPredecessors:(NSArray *)predecessors {
    int index = 0;
    for (NSNumber *uniqueIdNumber in predecessors) {
        int uniqueId = [uniqueIdNumber intValue];
        NSUInteger theIndex = [self indexOfTabWithUniqueId:uniqueId];
        if (theIndex != NSNotFound && theIndex + 1 > index) {
            index = theIndex + 1;
        }
    }
    return index;
}

- (PTYSession *)splitVertically:(BOOL)isVertical withProfile:(Profile *)profile {
    return [self splitVertically:isVertical
                    withBookmark:profile
                   targetSession:[self currentSession]];
}

- (PTYSession *)splitVertically:(BOOL)isVertical withBookmarkGuid:(NSString*)guid {
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (profile) {
        return [self splitVertically:isVertical withProfile:profile];
    } else {
        return nil;
    }
}

- (void)splitVertically:(BOOL)isVertical
                 before:(BOOL)before
          addingSession:(PTYSession *)newSession
          targetSession:(PTYSession *)targetSession
           performSetup:(BOOL)performSetup {
    [self.currentSession.textview refuseFirstResponderAtCurrentMouseLocation];
    NSView *scrollView;
    NSColor *tabColor;
    if (newSession.tabColor) {
        // The new session came with a tab color of its own so don't inherit.
        tabColor = newSession.tabColor;
    } else {
        // Inherit from tab.
        tabColor = [[[_contentView.tabBarControl tabColorForTabViewItem:[[self currentTab] tabViewItem]] retain] autorelease];
    }
    [[self currentTab] splitVertically:isVertical
                            newSession:newSession
                                before:before
                         targetSession:targetSession];
    SessionView *sessionView = newSession.view;
    scrollView = sessionView.scrollview;
    NSSize size = [sessionView frame].size;
    if (performSetup) {
        [self setupSession:newSession title:nil withSize:&size];
        scrollView = [[[newSession view] subviews] objectAtIndex:0];
    } else {
        [newSession setScrollViewDocumentView];
    }
    // Move the scrollView created by PTYSession into sessionView.
    [scrollView retain];
    [scrollView removeFromSuperview];
    [sessionView addSubview:scrollView];
    [scrollView release];
    if (!performSetup) {
        [scrollView setFrameSize:[sessionView frame].size];
    }
    [self fitTabsToWindow];

    if (targetSession == [[self currentTab] activeSession]) {
        [[self currentTab] setActiveSession:newSession];
    }
    [[self currentTab] recheckBlur];
    [[self currentTab] numberOfSessionsDidChange];
    [self setDimmingForSession:targetSession];
    for (PTYSession *session in self.currentTab.sessions) {
        [session.view updateDim];
    }
    if (targetSession.isDivorced) {
        // We assign directly to isDivorced because we know the GUID is unique and in sessions
        // instance and the original guid is already set. _bookmarkToSplit took care of that.
        newSession.isDivorced = YES;
    }
    if (![newSession.tabColor isEqual:tabColor] && newSession.tabColor != tabColor) {
        newSession.tabColor = tabColor;
        [self updateTabColors];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNumberOfSessionsDidChange"
                                                        object:self
                                                      userInfo:nil];
}

- (void)willSplitTmuxPane {
    for (PTYSession *session in self.allSessions) {
        session.sessionIsSeniorToTmuxSplitPane = YES;
    }
}

- (PTYSession *)splitVertically:(BOOL)isVertical
                   withBookmark:(Profile*)theBookmark
                  targetSession:(PTYSession*)targetSession {
    if ([targetSession isTmuxClient]) {
        [self willSplitTmuxPane];
        [[targetSession tmuxController] selectPane:targetSession.tmuxPane];
        [[targetSession tmuxController] splitWindowPane:[targetSession tmuxPane]
                                             vertically:isVertical
                                       initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:targetSession.profile objectType:iTermPaneObject]];
        return nil;
    }
    PtyLog(@"--------- splitVertically -----------");
    if (![self canSplitPaneVertically:isVertical withBookmark:theBookmark]) {
        NSBeep();
        return nil;
    }

    NSString *oldCWD = nil;
    /* Get currently selected tabviewitem */
    if ([self currentSession]) {
        oldCWD = [[[self currentSession] shell] getWorkingDirectory];
    }

    PTYSession* newSession = [[self newSessionWithBookmark:theBookmark] autorelease];
    [self splitVertically:isVertical
                   before:NO
            addingSession:newSession
            targetSession:targetSession
             performSetup:YES];

    if (![self runCommandInSession:newSession inCwd:oldCWD forObjectType:iTermPaneObject]) {
        [newSession terminate];
        [[self tabForSession:newSession] removeSession:newSession];
    }
    return newSession;
}

- (Profile*)_bookmarkToSplit
{
    Profile* theBookmark = nil;

    // Get the bookmark this session was originally created with. But look it up from its GUID because
    // it might have changed since it was copied into originalProfile when the bookmark was
    // first created.
    PTYSession *sourceSession = self.currentSession;
    Profile* originalBookmark = [sourceSession originalProfile];
    if (originalBookmark && [originalBookmark objectForKey:KEY_GUID]) {
        theBookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[originalBookmark objectForKey:KEY_GUID]];
    }

    // If that fails, use its current bookmark.
    if (!theBookmark) {
        theBookmark = [[self currentSession] profile];
    }

    // I don't think that'll ever fail, but to be safe try using the original bookmark.
    if (!theBookmark) {
        theBookmark = originalBookmark;
    }

    // I really don't think this'll ever happen, but there's always a default bookmark to fall back
    // on.
    if (!theBookmark) {
        theBookmark = [[ProfileModel sharedInstance] defaultBookmark];
    }

    if (sourceSession.isDivorced) {
        // Don't want to have two divorced sessions with the same guid. Allocate a new sessions
        // instance bookmark with a unique GUID.
        NSMutableDictionary *temp = [[theBookmark mutableCopy] autorelease];
        temp[KEY_GUID] = [ProfileModel freshGuid];
        temp[KEY_ORIGINAL_GUID] = [[originalBookmark[KEY_GUID] copy] autorelease];
        [[ProfileModel sessionsInstance] addBookmark:temp];
        theBookmark = temp;
    }

    return theBookmark;
}

- (IBAction)splitVertically:(id)sender
{
    [self splitVertically:YES
             withBookmark:[self _bookmarkToSplit]
            targetSession:[[self currentTab] activeSession]];
}

- (IBAction)splitHorizontally:(id)sender
{
    [self splitVertically:NO
             withBookmark:[self _bookmarkToSplit]
            targetSession:[[self currentTab] activeSession]];
}

- (void)tabActiveSessionDidChange {
    if (self.autoCommandHistorySessionGuid) {
        [self hideAutoCommandHistory];
    }
    [[_contentView.toolbelt commandHistoryView] updateCommands];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded]) {
        [self editSession:self.currentSession makeKey:NO];
    }
}


- (void)fitWindowToTabs {
    [self fitWindowToTabsExcludingTmuxTabs:NO];
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux {
    if (togglingFullScreen_) {
        return;
    }

    // Determine the size of the largest tab.
    NSSize maxTabSize = NSZeroSize;
    PtyLog(@"fitWindowToTabs.......");
    for (NSTabViewItem* item in [_contentView.tabView tabViewItems]) {
        PTYTab* tab = [item identifier];
        if ([tab isTmuxTab] && excludeTmux) {
            continue;
        }
        NSSize tabSize = [tab currentSize];
        PtyLog(@"The natural size of this tab is %@", NSStringFromSize(tabSize));
        if (tabSize.width > maxTabSize.width) {
            maxTabSize.width = tabSize.width;
        }
        if (tabSize.height > maxTabSize.height) {
            maxTabSize.height = tabSize.height;
        }

        tabSize = [tab minSize];
        PtyLog(@"The min size of this tab is %@", NSStringFromSize(tabSize));
        if (tabSize.width > maxTabSize.width) {
            maxTabSize.width = tabSize.width;
        }
        if (tabSize.height > maxTabSize.height) {
            maxTabSize.height = tabSize.height;
        }
    }
    if (NSEqualSizes(NSZeroSize, maxTabSize)) {
        // all tabs are tmux tabs.
        return;
    }
    PtyLog(@"fitWindowToTabs - calling fitWindowToTabSize");
    if (![self fitWindowToTabSize:maxTabSize]) {
        // Sometimes the window doesn't resize but widgets need to be moved. For example, when toggling
        // the scrollbar.
        [self repositionWidgets];
    }
}

- (BOOL)fitWindowToTabSize:(NSSize)tabSize {
    PtyLog(@"fitWindowToTabSize %@", NSStringFromSize(tabSize));
    if ([self anyFullScreen]) {
        [self fitTabsToWindow];
        return NO;
    }
    // Set the window size to be large enough to encompass that tab plus its decorations.
    NSSize decorationSize = [self windowDecorationSize];
    DLog(@"decorationSize=%@", NSStringFromSize(decorationSize));
    NSSize winSize = tabSize;
    winSize.width += decorationSize.width;
    winSize.height += decorationSize.height;
    NSRect frame = [[self window] frame];
    DLog(@"Pre-adjustment frame: %@", NSStringFromRect(frame));

    if (_contentView.shouldShowToolbelt) {
        winSize.width += floor(_contentView.toolbeltWidth);
    }

    BOOL mustResizeTabs = NO;
    NSSize maxFrameSize = [self maxFrame].size;
    PtyLog(@"maxFrameSize=%@, screens=%@", [NSValue valueWithSize:maxFrameSize], [NSScreen screens]);
    if (maxFrameSize.width <= 0 || maxFrameSize.height <= 0) {
        // This can happen when scrollers are changing while no monitors are
        // attached (e.g., plug in mouse+keyboard and external display into
        // clamshell simultaneously)
        NSLog(@"* max frame size was not positive; aborting fitWindowToTabSize");
        return NO;
    }
    if (winSize.width > maxFrameSize.width ||
        winSize.height > maxFrameSize.height) {
        mustResizeTabs = YES;
    }
    winSize.width = MIN(winSize.width, maxFrameSize.width);
    winSize.height = MIN(winSize.height, maxFrameSize.height);

    CGFloat heightChange = winSize.height - [[self window] frame].size.height;
    frame.size = winSize;
    frame.origin.y -= heightChange;

    NSView *bugFixView = nil;
    NSUInteger savedMask = 0;
    // The following code doesn't play nicely with the constraints that are
    // unfortunately added by the system in 10.10 when using title bar
    // accessories. The addition of title bar accessories forces a bunch of
    // constraints to exist. There was a bug where when creating a tmux window
    // we'd set the window frame to one value (e.g., 378pt tall);
    // windowDidResize would be called for 378pt. Then constraints would decide
    // that's not cool and windowDidResize would be called again (e.g., with
    // 399pt). No matter how many times you call setFrame:display:,
    // windowDidResize would get called twice, and you literally couldn't set
    // the window to certain heights. It was related to this bugfix view,
    // somehow. Better not to have it and live with screwed up title colors.
#if ENABLE_SHORTCUT_ACCESSORY
    if (!_shortcutAccessoryViewController) {
#endif
        // Ok, so some silly things are happening here. Issue 2096 reported that
        // when a session-initiated resize grows a window, the window's background
        // color becomes almost solid (it's actually a very gentle gradient between
        // two almost identical grays). For reasons that escape me, this happens if
        // the window's content view does not have a subview with an autoresizing
        // mask or autoresizing is off for the content view. I'm sure this isn't
        // the best fix, but it's all I could find: I turn off the autoresizing
        // mask for the _contentView.tabView (which I really don't want autoresized--it needs to
        // be done by hand in fitTabToWindow), and add a silly one pixel view
        // that lives just long enough to be resized in this function. I don't know
        // why it works but it does.
        bugFixView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)] autorelease];
        bugFixView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        [[[self window] contentView] addSubview:bugFixView];
        savedMask = _contentView.tabView.autoresizingMask;
        _contentView.tabView.autoresizingMask = 0;
#if ENABLE_SHORTCUT_ACCESSORY
    }
#endif
    // Set the frame for X-of-screen windows. The size doesn't change
    // for _PARTIAL window types.
    DLog(@"fitWindowToTabSize using screen number %@ with frame %@", @([[NSScreen screens] indexOfObject:self.screen]),
         NSStringFromRect(self.screen.frame));
    switch (windowType_) {
        case WINDOW_TYPE_BOTTOM:
            frame.origin.y = self.screen.visibleFrameIgnoringHiddenDock.origin.y;
            frame.size.width = [[self window] frame].size.width;
            frame.origin.x = [[self window] frame].origin.x;
            break;

        case WINDOW_TYPE_TOP:
            frame.origin.y = self.screen.visibleFrame.origin.y + self.screen.visibleFrame.size.height - frame.size.height;
            frame.size.width = [[self window] frame].size.width;
            frame.origin.x = [[self window] frame].origin.x;
            break;

        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
            frame.origin.y = self.screen.visibleFrameIgnoringHiddenDock.origin.y;
            frame.size.height = self.screen.visibleFrameIgnoringHiddenDock.size.height;

            PTYSession* session = [self currentSession];
            if (desiredColumns_ > 0) {
                frame.size.width = MIN(winSize.width,
                                       ceil([[session textview] charWidth] *
                                            desiredColumns_) + decorationSize.width + 2 * MARGIN);
            } else {
                frame.size.width = winSize.width;
            }
            if (windowType_ == WINDOW_TYPE_RIGHT) {
                frame.origin.x = [[self window] frame].origin.x + [[self window] frame].size.width - frame.size.width;
            } else {
                frame.origin.x = [[self window] frame].origin.x;
            }
            break;

        case WINDOW_TYPE_TOP_PARTIAL:
            frame.origin.y = self.screen.visibleFrame.origin.y + self.screen.visibleFrame.size.height - frame.size.height;
            break;

        case WINDOW_TYPE_BOTTOM_PARTIAL:
            frame.origin.y = self.screen.visibleFrameIgnoringHiddenDock.origin.y;
            break;

        case WINDOW_TYPE_LEFT_PARTIAL:
            frame.origin.x = self.screen.visibleFrameIgnoringHiddenDock.origin.x;
            break;

        case WINDOW_TYPE_RIGHT_PARTIAL:
            frame.origin.x = self.screen.visibleFrameIgnoringHiddenDock.origin.x + self.screen.visibleFrameIgnoringHiddenDock.size.width - frame.size.width;
            break;
            
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_NO_TITLE_BAR:
            break;
    }

    BOOL didResize = NSEqualRects([[self window] frame], frame);
    DLog(@"Set window frame to %@", NSStringFromRect(frame));
    [[self window] setFrame:frame display:YES];

    if (bugFixView) {
        // Restore _contentView.tabView's autoresizingMask and remove the stupid bugFixView.
        _contentView.tabView.autoresizingMask = savedMask;
        [bugFixView removeFromSuperview];
    }
    [[[self window] contentView] setAutoresizesSubviews:YES];

    PtyLog(@"fitWindowToTabs - refresh textview");
    for (PTYSession* session in [[self currentTab] sessions]) {
        [[session textview] setNeedsDisplay:YES];
    }
    PtyLog(@"fitWindowToTabs - update tab bar");
    [_contentView.tabBarControl updateFlashing];
    PtyLog(@"fitWindowToTabs - return.");

    if (mustResizeTabs) {
        [self fitTabsToWindow];
    }

    return didResize;
}

- (IBAction)selectPaneLeft:(id)sender
{
    PTYSession* session = [[self currentTab] sessionLeftOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (IBAction)selectPaneRight:(id)sender
{
    PTYSession* session = [[self currentTab] sessionRightOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (IBAction)selectPaneUp:(id)sender
{
    PTYSession* session = [[self currentTab] sessionAbove:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (IBAction)selectPaneDown:(id)sender
{
    PTYSession* session = [[self currentTab] sessionBelow:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] setActiveSession:session];
    }
}

- (IBAction)movePaneDividerRight:(id)sender
{
    int width = [[[self currentSession] textview] charWidth];
    [[self currentTab] moveCurrentSessionDividerBy:width
                                      horizontally:YES];
}

- (IBAction)movePaneDividerLeft:(id)sender
{
    int width = [[[self currentSession] textview] charWidth];
    [[self currentTab] moveCurrentSessionDividerBy:-width
                                      horizontally:YES];
}

- (IBAction)movePaneDividerDown:(id)sender
{
    int height = [[[self currentSession] textview] lineHeight];
    [[self currentTab] moveCurrentSessionDividerBy:height
                                      horizontally:NO];
}

- (IBAction)movePaneDividerUp:(id)sender
{
    int height = [[[self currentSession] textview] lineHeight];
    [[self currentTab] moveCurrentSessionDividerBy:-height
                                      horizontally:NO];
}

- (IBAction)addNoteAtCursor:(id)sender {
    [[self currentSession] addNoteAtCursor];
}

- (IBAction)nextMarkOrNote:(id)sender {
    [[self currentSession] nextMarkOrNote];
}

- (IBAction)previousMarkOrNote:(id)sender {
    [[self currentSession] previousMarkOrNote];
}

- (IBAction)toggleAlertOnNextMark:(id)sender {
    PTYSession *currentSession = [self currentSession];
    currentSession.alertOnNextMark = !currentSession.alertOnNextMark;
}

- (void)sessionWasRemoved
{
    // This works around an apparent bug in NSSplitView that causes dividers'
    // cursor rects to survive after the divider is gone.
    [[self window] resetCursorRects];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
}

- (float)minWidth
{
    // Pick 400 as an absolute minimum just to be safe. This is rather arbitrary and hacky.
    float minWidth = 400;
    for (NSTabViewItem* tabViewItem in [_contentView.tabView tabViewItems]) {
        PTYTab* theTab = [tabViewItem identifier];
        minWidth = MAX(minWidth, [theTab minSize].width);
    }
    return minWidth;
}

- (void)appendTab:(PTYTab*)aTab {
    [self insertTab:aTab atIndex:[_contentView.tabView numberOfTabViewItems]];
}

- (NSString *)promptForParameter:(NSString *)name {
    if (self.disablePromptForSubstitutions) {
        return @"";
    }
    // Make the name pretty.
    name = [name stringByReplacingOccurrencesOfString:@"$$" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    name = [name lowercaseString];
    if (name.length) {
        NSString *firstLetter = [name substringWithRange:NSMakeRange(0, 1)];
        NSString *lastLetters = [name substringFromIndex:1];
        name = [[firstLetter uppercaseString] stringByAppendingString:lastLetters];
    }
    [parameterName setStringValue:[NSString stringWithFormat:@"“%@”:", name]];
    [parameterValue setStringValue:@""];

    [NSApp beginSheet:parameterPanel
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:nil
          contextInfo:nil];

    [NSApp runModalForWindow:parameterPanel];

    [NSApp endSheet:parameterPanel];
    [parameterPanel orderOut:self];

    if (_parameterPanelCanceled) {
        return nil;
    } else {
        return [[parameterValue.stringValue copy] autorelease];
    }
}

// Returns nil if the user pressed cancel, otherwise returns a dictionary that's a supeset of |substitutions|.
- (NSDictionary *)substitutionsForCommand:(NSString *)command
                              sessionName:(NSString *)name
                        baseSubstitutions:(NSDictionary *)substitutions {
    NSSet *cmdVars = [command doubleDollarVariables];
    NSSet *nameVars = [name doubleDollarVariables];
    NSMutableSet *allVars = [[cmdVars mutableCopy] autorelease];
    [allVars unionSet:nameVars];
    NSMutableDictionary *allSubstitutions = [[substitutions mutableCopy] autorelease];
    for (NSString *var in allVars) {
        if (!substitutions[var]) {
            NSString *value = [self promptForParameter:var];
            if (!value) {
                return nil;
            }
            allSubstitutions[var] = value;
        }
    }
    return allSubstitutions;
}

- (NSArray*)tabs {
    int n = [_contentView.tabView numberOfTabViewItems];
    NSMutableArray *tabs = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; ++i) {
        NSTabViewItem* theItem = [_contentView.tabView tabViewItemAtIndex:i];
        [tabs addObject:[theItem identifier]];
    }
    return tabs;
}

- (NSDate *)lastResizeTime
{
    return [NSDate dateWithTimeIntervalSince1970:lastResizeTime_];
}

- (BroadcastMode)broadcastMode
{
    if ([[self currentTab] isBroadcasting]) {
                    return BROADCAST_TO_ALL_PANES;
        } else {
                    return broadcastMode_;
        }
}

- (void)setBroadcastMode:(BroadcastMode)mode
{
    if (mode != BROADCAST_CUSTOM && mode == [self broadcastMode]) {
        mode = BROADCAST_OFF;
    }
    if (mode != BROADCAST_OFF && [self broadcastMode] == BROADCAST_OFF) {
        if ([iTermWarning showWarningWithTitle:@"Keyboard input will be sent to multiple sessions."
                                       actions:@[ @"OK", @"Cancel" ]
                                    identifier:@"NoSyncSuppressBroadcastInputWarning"
                                   silenceable:kiTermWarningTypePermanentlySilenceable] == kiTermWarningSelection1) {
            return;
        }
    }
    if (mode == BROADCAST_TO_ALL_PANES) {
            [[self currentTab] setBroadcasting:YES];
            mode = BROADCAST_OFF;
    } else {
            [[self currentTab] setBroadcasting:NO];
    }
    broadcastMode_ = mode;
        [self setDimmingForSessions];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateBroadcastMenuState];
}

- (void)toggleBroadcastingInputToSession:(PTYSession *)session
{
    NSNumber *n = [NSNumber numberWithInt:[[session view] viewId]];
    switch ([self broadcastMode]) {
        case BROADCAST_TO_ALL_PANES:
            [[self currentTab] setBroadcasting:NO];
            [broadcastViewIds_ removeAllObjects];
            for (PTYSession *aSession in [[self currentTab] sessions]) {
                [broadcastViewIds_ addObject:[NSNumber numberWithInt:[[aSession view] viewId]]];
            }
            break;

        case BROADCAST_TO_ALL_TABS:
            [broadcastViewIds_ removeAllObjects];
            for (PTYTab *aTab in [self tabs]) {
                for (PTYSession *aSession in [aTab sessions]) {
                    [broadcastViewIds_ addObject:[NSNumber numberWithInt:[[aSession view] viewId]]];
                }
            }
            break;

        case BROADCAST_OFF:
            [broadcastViewIds_ removeAllObjects];
            break;

        case BROADCAST_CUSTOM:
            break;
    }
    broadcastMode_ = BROADCAST_CUSTOM;
    int prevCount = [broadcastViewIds_ count];
    if ([broadcastViewIds_ containsObject:n]) {
        [broadcastViewIds_ removeObject:n];
    } else {
        [broadcastViewIds_ addObject:n];
    }
    if ([broadcastViewIds_ count] == 0) {
        // Untoggled the last session.
        broadcastMode_ = BROADCAST_OFF;
    } else if ([broadcastViewIds_ count] == 1 &&
               prevCount == 2) {
        // Untoggled a session and got down to 1. Disable broadcast because you can't broadcast with
        // fewer than 2 sessions.
        broadcastMode_ = BROADCAST_OFF;
        [broadcastViewIds_ removeAllObjects];
    } else if ([broadcastViewIds_ count] == 1) {
        // Turned on one session so add the current session.
        [broadcastViewIds_ addObject:[NSNumber numberWithInt:[[[self currentSession] view] viewId]]];
        // NOTE: There may still be only one session. This is of use to focus
        // follows mouse users who want to toggle particular panes.
    }
    for (PTYTab *aTab in [self tabs]) {
        for (PTYSession *aSession in [aTab sessions]) {
            [[aSession view] setNeedsDisplay:YES];
        }
    }
    // Update dimming of panes.
    [self refreshTerminal:nil];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateBroadcastMenuState];
}

- (void)setSplitSelectionMode:(BOOL)mode excludingSession:(PTYSession *)session move:(BOOL)move {
    // Things would get really complicated if you could do this in IR, so just
    // close it.
    [self closeInstantReplay:nil];
    for (PTYSession *aSession in [self allSessions]) {
        if (mode) {
            [aSession setSplitSelectionMode:(aSession != session) ? kSplitSelectionModeOn : kSplitSelectionModeCancel
                                       move:move];
        } else {
            [aSession setSplitSelectionMode:kSplitSelectionModeOff
                                       move:move];
        }
    }
}

- (IBAction)moveTabLeft:(id)sender
{
    NSInteger selectedIndex = [_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]];
    NSInteger destinationIndex = selectedIndex - 1;
    if (destinationIndex < 0) {
        destinationIndex = [_contentView.tabView numberOfTabViewItems] - 1;
    }
    if (selectedIndex == destinationIndex) {
        return;
    }
    [_contentView.tabBarControl moveTabAtIndex:selectedIndex toIndex:destinationIndex];
    [self _updateTabObjectCounts];
    [self tabsDidReorder];
}

- (IBAction)moveTabRight:(id)sender
{
    NSInteger selectedIndex = [_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]];
    NSInteger destinationIndex = (selectedIndex + 1) % [_contentView.tabView numberOfTabViewItems];
    if (selectedIndex == destinationIndex) {
        return;
    }
    [_contentView.tabBarControl moveTabAtIndex:selectedIndex toIndex:destinationIndex];
    [self _updateTabObjectCounts];
    [self tabsDidReorder];
}

- (IBAction)increaseHeight:(id)sender {
    [self sessionInitiatedResize:self.currentSession
                           width:self.currentSession.columns
                          height:self.currentSession.rows+1];
}

- (IBAction)decreaseHeight:(id)sender {
    [self sessionInitiatedResize:self.currentSession
                           width:self.currentSession.columns
                          height:self.currentSession.rows-1];
}

- (IBAction)increaseWidth:(id)sender {
    [self sessionInitiatedResize:self.currentSession
                           width:self.currentSession.columns+1
                          height:self.currentSession.rows];
}

- (IBAction)decreaseWidth:(id)sender {
    [self sessionInitiatedResize:self.currentSession
                           width:self.currentSession.columns-1
                          height:self.currentSession.rows];

}

- (void)refreshTmuxLayoutsAndWindow
{
    for (PTYTab *aTab in [self tabs]) {
        [aTab setReportIdealSizeAsCurrent:YES];
        if ([aTab isTmuxTab]) {
            [aTab reloadTmuxLayout];
        }
    }
    [self fitWindowToTabs];
    for (PTYTab *aTab in [self tabs]) {
        [aTab setReportIdealSizeAsCurrent:NO];
    }
}

- (void)setDimmingForSession:(PTYSession *)aSession
{
    BOOL canDim = [iTermPreferences boolForKey:kPreferenceKeyDimInactiveSplitPanes];
    if (!canDim) {
        [[aSession view] setDimmed:NO];
    } else if (aSession == [[self tabForSession:aSession] activeSession]) {
        [[aSession view] setDimmed:NO];
    } else if (![self broadcastInputToSession:aSession]) {
        // Session is not the active session and we're not broadcasting to it.
        [[aSession view] setDimmed:YES];
    } else if ([self broadcastInputToSession:[self currentSession]]) {
        // Session is not active, we are broadcasting to it, and the current
        // session is also broadcasting.
        [[aSession view] setDimmed:NO];
    } else {
        // Session is is not active, we are broadcasting to it, but we are not
        // broadcasting to the current session.
        [[aSession view] setDimmed:YES];
    }
    [[aSession view] setNeedsDisplay:YES];
}

- (void)setDimmingForSessions
{
    for (PTYSession *aSession in [self allSessions]) {
        [self setDimmingForSession:aSession];
    }
}

- (int)_screenAtPoint:(NSPoint)p
{
    int i = 0;
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(p, [screen frame])) {
            return i;
        }
        i++;
    }

    NSLog(@"Point %lf,%lf not in any screen", p.x, p.y);
    return 0;
}

- (void)updateWindowNumberVisibility:(NSNotification*)aNotification {
    // This is if displaying of window number was toggled in prefs.
#if ENABLE_SHORTCUT_ACCESSORY
    if (_shortcutAccessoryViewController) {
        _shortcutAccessoryViewController.view.hidden = ![iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber];
    } else {
        // Pre-10.10 code path
        [self setWindowTitle];
    }
#else
    [self setWindowTitle];
#endif
}

- (void)_scrollerStyleChanged:(id)sender
{
    [self updateSessionScrollbars];
    if ([self anyFullScreen]) {
        [self fitTabsToWindow];
    } else {
        // The scrollbar has already been added so tabs' current sizes are wrong.
        // Use ideal sizes instead, to fit to the session dimensions instead of
        // the existing pixel dimensions of the tabs.
        [self refreshTmuxLayoutsAndWindow];
    }
}

- (void)refreshTerminal:(NSNotification *)aNotification {
    PtyLog(@"refreshTerminal - calling fitWindowToTabs");

    [self updateTabBarStyle];

    // If hiding of menu bar changed.
    if ([self fullScreen] && ![self lionFullScreen]) {
        if ([[self window] isKeyWindow]) {
            // In practice, this never happens because the prefs panel is
            // always key when this notification is posted.
            if ([iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen]) {
                [self showMenuBarHideDock];
            } else {
                [self hideMenuBar];
            }
        }
        [self.window setFrame:[self traditionalFullScreenFrame] display:YES];
    }

    [self fitWindowToTabs];

    // If tab style or position changed.
    [self repositionWidgets];

    // In case scrollbars came or went:
    for (PTYTab *aTab in [self tabs]) {
        for (PTYSession *aSession in [aTab sessions]) {
            [aTab fitSessionToCurrentViewSize:aSession];
        }
        // Theme change could affect tab icons
        [aTab updateIcon];
    }

    // Assign counts to each session. This causes tabs to show their tab number,
    // called an objectCount. When the "compact tab" pref is toggled, this makes
    // formerly countless tabs show their counts.
    BOOL needResize = NO;
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        PTYTab *aTab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        if ([aTab updatePaneTitles]) {
            needResize = YES;
        }
        [aTab setObjectCount:i+1];

        // Update activity indicator.
        [aTab setIsProcessing:[aTab realIsProcessing]];

        // Update dimmed status of inactive sessions in split panes in case the preference changed.
        for (PTYSession* aSession in [aTab sessions]) {
                        [self setDimmingForSession:aSession];
            [[aSession view] setBackgroundDimmed:![[self window] isKeyWindow]];

            // In case dimming amount slider moved update the dimming amount.
            [[aSession view] updateDim];
        }
    }

    // If updatePaneTitles caused any session to change dimensions, then tell tmux
    // controllers that our capacity has changed.
    if (needResize) {
        DLog(@"refrshTerminal needs resize");
        NSArray *tmuxControllers = [self uniqueTmuxControllers];
        for (TmuxController *c in tmuxControllers) {
            [c windowDidResize:self];
        }
        if (tmuxControllers.count) {
            for (PTYTab *aTab in [self tabs]) {
                [aTab recompact];
            }
            [self fitWindowToTabs];
        }
    }

    // If the theme changed from light to dark make sure split pane dividers redraw.
    [_contentView.tabView setNeedsDisplay:YES];
}

- (void)updateTabBarStyle {
    id<PSMTabStyle> style;
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_LIGHT:
            style = [[[PSMYosemiteTabStyle alloc] init] autorelease];
            break;
        case TAB_STYLE_DARK:
            style = [[[PSMDarkTabStyle alloc] init] autorelease];
            break;
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            style = [[[PSMLightHighContrastTabStyle alloc] init] autorelease];
            break;
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            style = [[[PSMDarkHighContrastTabStyle alloc] init] autorelease];
            break;
    }
    [_contentView.tabBarControl setStyle:style];
}

- (void)hideMenuBar {
    DLog(@"hideMenuBar called from\n%@", [NSThread callStackSymbols]);
    NSScreen* menubarScreen = nil;
    NSScreen* currentScreen = nil;

    if ([[NSScreen screens] count] == 0) {
        return;
    }

    menubarScreen = [[NSScreen screens] objectAtIndex:0];
    currentScreen = [[self window] screen];
    if (!currentScreen) {
        currentScreen = [NSScreen mainScreen];
    }

    // If screens have separate spaces (only applicable in Mavericks and later) then all screens have a menu bar.
    if (currentScreen == menubarScreen || (IsMavericksOrLater() && [NSScreen futureScreensHaveSeparateSpaces])) {
        DLog(@"set flags to auto-hide dock");
        int flags = NSApplicationPresentationAutoHideDock;
        if ([iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen]) {
            DLog(@"Set flags to auto-hide menu bar");
            flags |= NSApplicationPresentationAutoHideMenuBar;
        }
        NSApplicationPresentationOptions presentationOptions =
            [[NSApplication sharedApplication] presentationOptions];
        presentationOptions |= flags;
        [[NSApplication sharedApplication] setPresentationOptions:presentationOptions];

    }
}

- (void)showMenuBarHideDock {
    DLog(@"showMenuBarHideDock called from\n%@", [NSThread callStackSymbols]);
    NSApplicationPresentationOptions presentationOptions =
        [[NSApplication sharedApplication] presentationOptions];
    presentationOptions |= NSApplicationPresentationAutoHideDock;
    presentationOptions &= ~NSApplicationPresentationAutoHideMenuBar;
    [[NSApplication sharedApplication] setPresentationOptions:presentationOptions];
}

- (void)showMenuBar {
    DLog(@"showMenuBar called from\n%@", [NSThread callStackSymbols]);
    int flags = NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar;
    NSApplicationPresentationOptions presentationOptions =
        [[NSApplication sharedApplication] presentationOptions];
    presentationOptions &= ~flags;
    [[NSApplication sharedApplication] setPresentationOptions:presentationOptions];
}

- (void)setFrameSize:(NSSize)newSize
{
    NSSize size = [self windowWillResize:[self window] toSize:newSize];
    NSRect frame = [[self window] frame];
    [[self window] setFrame:NSMakeRect(frame.origin.x,
                                       frame.origin.y,
                                       size.width,
                                       size.height)
                    display:YES];
}

// Show or hide instant replay bar.
- (void)setInstantReplayBarVisible:(BOOL)visible
{
    if ([self inInstantReplay] != visible) {
        [self showHideInstantReplay];
    }
}

- (BOOL)exitingLionFullscreen {
    return exitingLionFullscreen_;
}

- (BOOL)haveLeftBorder {
    BOOL leftTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab);
    if (![iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder]) {
        return NO;
    } else if ([self anyFullScreen] ||
               windowType_ == WINDOW_TYPE_LEFT ||
               (leftTabBar && [self tabBarShouldBeVisible])) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)haveBottomBorder
{
    BOOL tabBarVisible = [self tabBarShouldBeVisible];
    BOOL bottomTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_BottomTab);
    if (![iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder]) {
        return NO;
    } else if ([self anyFullScreen] ||
               windowType_ == WINDOW_TYPE_BOTTOM) {
        return NO;
    } else if (!bottomTabBar) {
        // Nothing on the bottom, so need a border.
        return YES;
    } else if (!tabBarVisible) {
        // Invisible bottom tab bar
        return YES;
    } else if ([iTermPreferences boolForKey:kPreferenceKeyTabStyle] == TAB_STYLE_DARK) {
        // Dark tab style needs a border
        return YES;
    } else {
        // Visible bottom tab bar with light style. It's light enough so it doesn't need a border.
        return NO;
    }
}

- (BOOL)haveTopBorder {
    BOOL tabBarVisible = [self tabBarShouldBeVisible];
    BOOL topTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab);
    BOOL visibleTopTabBar = (tabBarVisible && topTabBar);
    BOOL windowTypeCompatibleWithTopBorder = (windowType_ == WINDOW_TYPE_BOTTOM ||
                                              windowType_ == WINDOW_TYPE_NO_TITLE_BAR ||
                                              windowType_ == WINDOW_TYPE_BOTTOM_PARTIAL);
    return ([iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder] &&
            !visibleTopTabBar &&
            windowTypeCompatibleWithTopBorder);
}

- (BOOL)haveRightBorder {
    if (![iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder]) {
        return NO;
    } else if ([self anyFullScreen] ||
               windowType_ == WINDOW_TYPE_RIGHT ) {
        return NO;
    } else if (![[[[self currentSession] view] scrollview] isLegacyScroller] ||
               ![self scrollbarShouldBeVisible]) {
        // hidden scrollbar
        return YES;
    } else {
        // visible scrollbar
        return NO;
    }
}

// Returns the size of the stuff outside the tabview.
- (NSSize)windowDecorationSize
{
    NSSize contentSize = NSZeroSize;

    if (!_contentView.tabBarControl.flashing &&
        [self tabBarShouldBeVisibleWithAdditionalTabs:tabViewItemsBeingAdded]) {
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_TopTab:
            case PSMTab_BottomTab:
                contentSize.height += kHorizontalTabBarHeight;
                break;
            case PSMTab_LeftTab:
                contentSize.width += [self tabviewWidth];
                break;
        }
    }

    // Add 1px border
    if ([self haveLeftBorder]) {
        ++contentSize.width;
    }
    if ([self haveRightBorder]) {
        ++contentSize.width;
    }
    if ([self haveBottomBorder]) {
        ++contentSize.height;
    }
    if ([self haveTopBorder]) {
        ++contentSize.height;
    }
    if (self.divisionViewShouldBeVisible) {
        ++contentSize.height;
    }

    return [[self window] frameRectForContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)].size;
}

- (void)flagsChanged:(NSEvent *)theEvent
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermFlagsChanged"
                                                        object:theEvent
                                                      userInfo:nil];


    [_contentView.tabView cycleFlagsChanged:[theEvent modifierFlags]];

    NSUInteger modifierFlags = [theEvent modifierFlags];
    if (!(modifierFlags & NSCommandKeyMask) &&
        [[[self currentSession] textview] isFindingCursor]) {
        // The cmd key was let up while finding the cursor

        if ([[NSDate date] timeIntervalSinceDate:[NSDate dateWithTimeIntervalSince1970:findCursorStartTime_]] > kFindCursorHoldTime) {
            // The time for it to hide automatically has passed, so just hide it
            [[[self currentSession] textview] endFindCursor];
        } else {
            // Hide it after the minimum time
            [[[self currentSession] textview] placeFindCursorOnAutoHide];
        }
    }

    _contentView.tabBarControl.cmdPressed = ((modifierFlags & NSCommandKeyMask) == NSCommandKeyMask);
}

// Change position of window widgets.
- (void)repositionWidgets {
    [_contentView layoutSubviews];
}

// Returns the width of characters in pixels in the session with the widest
// characters. Fills in *numChars with the number of columns in that session.
- (float)maxCharWidth:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[_contentView.tabView tabViewItemAtIndex:i] identifier] sessions]) {
            float w =[[session textview] charWidth];
            PtyLog(@"maxCharWidth - session %d has %dx%d, chars are %fx%f",
                   i, [session columns], [session rows], [[session textview] charWidth],
                   [[session textview] lineHeight]);
            if (w > max) {
                max = w;
                if (numChars) {
                    *numChars = [session columns];
                }
            }
        }
    }
    return max;
}

// Returns the height of characters in pixels in the session with the tallest
// characters. Fills in *numChars with the number of rows in that session.
- (float)maxCharHeight:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[_contentView.tabView tabViewItemAtIndex:i] identifier] sessions]) {
            float h =[[session textview] lineHeight];
            PtyLog(@"maxCharHeight - session %d has %dx%d, chars are %fx%f", i, [session columns],
                   [session rows], [[session textview] charWidth], [[session textview] lineHeight]);
            if (h > max) {
                max = h;
                if (numChars) {
                    *numChars = [session rows];
                }
            }
        }
    }
    return max;
}

// Returns the width of characters in pixels in the overall widest session.
// Fills in *numChars with the number of columns in that session.
- (float)widestSessionWidth:(int*)numChars
{
    float max=0;
    float ch=0;
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[_contentView.tabView tabViewItemAtIndex:i] identifier] sessions]) {
            float w = [[session textview] charWidth];
            PtyLog(@"widestSessionWidth - session %d has %dx%d, chars are %fx%f", i,
                   [session columns], [session rows], [[session textview] charWidth],
                   [[session textview] lineHeight]);
            if (w * [session columns] > max) {
                max = w;
                ch = [[session textview] charWidth];
                *numChars = [session columns];
            }
        }
    }
    return ch;
}

// Returns the height of characters in pixels in the overall tallest session.
// Fills in *numChars with the number of rows in that session.
- (float)tallestSessionHeight:(int*)numChars
{
    float max=0;
    float ch=0;
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[_contentView.tabView tabViewItemAtIndex:i] identifier] sessions]) {
            float h = [[session textview] lineHeight];
            PtyLog(@"tallestSessionheight - session %d has %dx%d, chars are %fx%f", i, [session columns], [session rows], [[session textview] charWidth], [[session textview] lineHeight]);
            if (h * [session rows] > max) {
                max = h * [session rows];
                ch = [[session textview] lineHeight];
                *numChars = [session rows];
            }
        }
    }
    return ch;
}

// Copy state from 'other' to this terminal.
- (void)copySettingsFrom:(PseudoTerminal*)other
{
    if ([other inInstantReplay]) {
        [other closeInstantReplayWindow];
        [self showHideInstantReplay];
    }
}

// Set the session's profile dictionary and initialize its screen and name. Sets the
// window title to the session's name. If size is not nil then the session is initialized to fit
// a view of that size; otherwise the size is derived from the existing window if there is already
// an open tab, or its bookmark's preference if it's the first session in the window.
- (void)setupSession:(PTYSession *)aSession
               title:(NSString *)title
            withSize:(NSSize*)size {
    NSDictionary *tempPrefs;
    NSParameterAssert(aSession != nil);

    // set some default parameters
    if ([aSession profile] == nil) {
        tempPrefs = [[ProfileModel sharedInstance] defaultBookmark];
        if (tempPrefs != nil) {
            // Use the default bookmark. This path is taken with applescript's
            // "make new session at the end of sessions" command.
            [aSession setProfile:tempPrefs];
        } else {
            // get the hardcoded defaults
            NSMutableDictionary* dict = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:dict];
            [dict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
            [aSession setProfile:dict];
            tempPrefs = dict;
        }
    } else {
        tempPrefs = [aSession profile];
    }
    PtyLog(@"Open session with prefs: %@", tempPrefs);
    int rows = [[tempPrefs objectForKey:KEY_ROWS] intValue];
    int columns = [[tempPrefs objectForKey:KEY_COLUMNS] intValue];
    if (desiredRows_ < 0) {
        desiredRows_ = rows;
        desiredColumns_ = columns;
    }
    if (nextSessionRows_) {
        rows = nextSessionRows_;
        nextSessionRows_ = 0;
    }
    if (nextSessionColumns_) {
        columns = nextSessionColumns_;
        nextSessionColumns_ = 0;
    }
    // rows, columns are set to the bookmark defaults. Make sure they'll fit.

    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[tempPrefs objectForKey:KEY_NORMAL_FONT]]
                                 horizontalSpacing:[[tempPrefs objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                   verticalSpacing:[[tempPrefs objectForKey:KEY_VERTICAL_SPACING] floatValue]];

    if (size == nil && [_contentView.tabView numberOfTabViewItems] != 0) {
        NSSize contentSize = [[[[self currentSession] view] scrollview] documentVisibleRect].size;
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
    }
    NSRect sessionRect;
    if (size != nil) {
        BOOL hasScrollbar = [self scrollbarShouldBeVisible];
        NSSize contentSize =
            [NSScrollView contentSizeForFrameSize:*size
                      horizontalScrollerClass:nil
                        verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                                   borderType:NSNoBorder
                                  controlSize:NSRegularControlSize
                                scrollerStyle:[self scrollerStyle]];
        rows = (contentSize.height - VMARGIN*2) / charSize.height;
        columns = (contentSize.width - MARGIN*2) / charSize.width;
        sessionRect.origin = NSZeroPoint;
        sessionRect.size = *size;
    } else {
        sessionRect = NSMakeRect(0, 0, columns * charSize.width + MARGIN * 2, rows * charSize.height + VMARGIN * 2);
    }

    if ([aSession setScreenSize:sessionRect parent:self]) {
        PtyLog(@"setupSession - call safelySetSessionSize");
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        PtyLog(@"setupSession - call setPreferencesFromAddressBookEntry");
        [aSession setPreferencesFromAddressBookEntry:tempPrefs];
        [aSession loadInitialColorTable];
        [aSession setBookmarkName:[tempPrefs objectForKey:KEY_NAME]];
        [aSession.screen resetTimestamps];

        if (title) {
            [aSession setName:title];
            [aSession setDefaultName:title];
            [self setWindowTitle];
        }
    }
}

- (void)moveSessionToWindow:(id)sender {
    [[MovePaneController sharedInstance] moveSessionToNewWindow:[self currentSession]
                                                        atPoint:[[self window] pointToScreenCoords:NSMakePoint(10, -10)]];

}

// Max window frame size that fits on screens.
- (NSRect)maxFrame
{
    NSRect visibleFrame = NSZeroRect;
    for (NSScreen* screen in [NSScreen screens]) {
        visibleFrame = NSUnionRect(visibleFrame, [screen visibleFrame]);
    }
    return visibleFrame;
}

// Push a size change to a session (and on to its shell) but clamps the size to
// reasonable minimum and maximum limits.
- (void)safelySetSessionSize:(PTYSession*)aSession rows:(int)rows columns:(int)columns
{
    if ([aSession exited]) {
        return;
    }
    PtyLog(@"safelySetSessionSize");
    BOOL hasScrollbar = [self scrollbarShouldBeVisible];
    if (![self anyFullScreen]) {
        int width = columns;
        int height = rows;
        if (width < 20) {
            width = 20;
        }
        if (height < 2) {
            height = 2;
        }

        // With split panes it is very difficult to directly compute the maximum size of any
        // given pane. However, any growth in a pane can be taken up by the window as a whole.
        // We compute the maximum amount the window can grow and ensure that the rows and columns
        // won't cause the window to exceed the max size.

        // 1. Figure out how big the tabview can get assuming window decoration remains unchanged.
        NSSize maxFrame = [self maxFrame].size;
        NSSize decoration = [self windowDecorationSize];
        NSSize maxTabSize;
        maxTabSize.width = maxFrame.width - decoration.width;
        maxTabSize.height = maxFrame.height - decoration.height;

        // 2. Figure out how much the window could grow by in rows and columns.
        NSSize currentSize = [_contentView.tabView frame].size;
        if ([_contentView.tabView numberOfTabViewItems] == 0) {
            currentSize = NSZeroSize;
        }
        NSSize maxGrowth;
        maxGrowth.width = maxTabSize.width - currentSize.width;
        maxGrowth.height = maxTabSize.height - currentSize.height;
        int maxNewRows = maxGrowth.height / [[aSession textview] lineHeight];

        // 3. Compute the number of rows and columns we're trying to grow by.
        int newRows = rows - [aSession rows];
        // 4. Cap growth if it exceeds the maximum. Do nothing if it's shrinking.
        if (newRows > maxNewRows) {
            int error = newRows - maxNewRows;
            height -= error;
        }
        PtyLog(@"safelySetSessionSize - set to %dx%d", width, height);
        [aSession setSize:VT100GridSizeMake(width, height)];
        [[aSession.view scrollview] setHasVerticalScroller:hasScrollbar];
        [[aSession.view scrollview] setLineScroll:[[aSession textview] lineHeight]];
        [[aSession.view scrollview] setPageScroll:2*[[aSession textview] lineHeight]];
        if ([aSession backgroundImagePath]) {
            [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
        }
    }
}

// Adjust the tab's size for a new window size.
- (void)fitTabToWindow:(PTYTab *)aTab {
    NSSize size = [_contentView.tabView contentRect].size;
    PtyLog(@"fitTabToWindow calling setSize for content size of %@", [NSValue valueWithSize:size]);
    [aTab setSize:size];
}

// Add a tab to the tabview.
- (void)insertTab:(PTYTab*)aTab atIndex:(int)anIndex
{
    PtyLog(@"insertTab:atIndex:%d", anIndex);
    assert(aTab);
    if ([_contentView.tabView indexOfTabViewItemWithIdentifier:aTab] == NSNotFound) {
        for (PTYSession* aSession in [aTab sessions]) {
            [aSession setIgnoreResizeNotifications:YES];
        }
        NSTabViewItem* aTabViewItem = [[NSTabViewItem alloc] initWithIdentifier:(id)aTab];
        [aTabViewItem setLabel:@""];
        assert(aTabViewItem);
        [aTab setTabViewItem:aTabViewItem];
        PtyLog(@"insertTab:atIndex - calling [_contentView.tabView insertTabViewItem:atIndex]");
        [_contentView.tabView insertTabViewItem:aTabViewItem atIndex:anIndex];
        [aTabViewItem release];
        [_contentView.tabView selectTabViewItemAtIndex:anIndex];
        if (self.windowInitialized && !_fullScreen) {
            [[self window] makeKeyAndOrderFront:self];
        } else {
            PtyLog(@"window not initialized or is fullscreen %@", [NSThread callStackSymbols]);
        }
        [[iTermController sharedInstance] setCurrentTerminal:self];
    }
}

// Add a session to the tab view.
- (void)insertSession:(PTYSession *)aSession atIndex:(int)anIndex
{
    PtyLog(@"-[PseudoTerminal insertSession: %p atIndex: %d]", aSession, anIndex);

    if (aSession == nil) {
        return;
    }

    if ([[self allSessions] indexOfObject:aSession] == NSNotFound) {
        // create a new tab
        PTYTab *aTab = [[PTYTab alloc] initWithSession:aSession];
        [aSession setIgnoreResizeNotifications:YES];
        if ([self numberOfTabs] == 0) {
            [aTab setReportIdealSizeAsCurrent:YES];
        }
        [self insertTab:aTab atIndex:anIndex];
        [aTab setReportIdealSizeAsCurrent:NO];
        [aTab release];
    }
}

- (NSString *)currentSessionName {
    PTYSession* session = [self currentSession];
    return [session windowTitle] ? [session windowTitle] : [session defaultName];
}

- (void)setName:(NSString *)theSessionName forSession:(PTYSession*)aSession
{
    if (theSessionName != nil) {
        [aSession setDefaultName:theSessionName];
        [aSession setName:theSessionName];
    } else {
        NSMutableString *title = [NSMutableString string];
        NSString *progpath = [NSString stringWithFormat: @"%@ #%ld",
                              [[[[aSession shell] path] pathComponents] lastObject],
                              (long)[_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]]];

        if ([aSession exited]) {
            [title appendString:@"Finish"];
        } else {
            [title appendString:progpath];
        }

        [aSession setName:title];
        [aSession setDefaultName:title];
    }
}

// Assign a value to the 'uniqueNumber_' member variable which is used for storing
// window frame positions between invocations of iTerm.
- (void)assignUniqueNumberToWindow
{
    uniqueNumber_ = [[TemporaryNumberAllocator sharedInstance] allocateNumber];
}

// Execute the given program and set the window title if it is uninitialized.
- (void)startProgram:(NSString *)command
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
           inSession:(PTYSession*)theSession
        substitutions:(NSDictionary *)substitutions {
    [theSession startProgram:command
                 environment:prog_env
                      isUTF8:isUTF8
               substitutions:substitutions];

    if ([[[self window] title] isEqualToString:@"Window"]) {
        [self setWindowTitle];
    }
}

// Reset all state associated with the terminal.
- (void)reset:(id)sender {
    [[[self currentSession] terminal] resetByUserRequest:YES];
    [[self currentSession] updateDisplay];
}

- (IBAction)resetCharset:(id)sender
{
    [[[self currentSession] terminal] resetCharset];
}

// Clear the buffer of the current session (Edit>Clear Buffer).
- (void)clearBuffer:(id)sender {
    [[self currentSession] clearBuffer];
}

// Erase the scrollback buffer of the current session.
- (void)clearScrollbackBuffer:(id)sender
{
    [[self currentSession] clearScrollbackBuffer];
}

// Turn on session logging in the current session.
- (IBAction)logStart:(id)sender
{
    if (![[self currentSession] logging]) {
        [[self retain] autorelease];  // Prevent self from getting dealloc'ed during modal panel.
        [[self currentSession] logStart];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[self currentSession]];
}

// Turn off session logging in the current session.
- (IBAction)logStop:(id)sender {
    if ([[self currentSession] logging]) {
        [[self currentSession] logStop];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[self currentSession]];
}

- (void)addRevivedSession:(PTYSession *)session {
    [self insertSession:session atIndex:[self numberOfTabs]];
    [[self currentTab] numberOfSessionsDidChange];
}


// Returns true if the given menu item is selectable.
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    BOOL logging = [[self currentSession] logging];
    BOOL result = YES;

    if ([item action] == @selector(detachTmux:) ||
        [item action] == @selector(newTmuxWindow:) ||
        [item action] == @selector(newTmuxTab:) ||
        [item action] == @selector(openDashboard:)) {
        result = [[iTermController sharedInstance] haveTmuxConnection];
    } else if ([item action] == @selector(setDefaultToolbeltWidth:)) {
        return _contentView.shouldShowToolbelt;
    } else if ([item action] == @selector(toggleToolbeltVisibility:)) {
        [item setState:_contentView.shouldShowToolbelt ? NSOnState : NSOffState];
        return [[iTermToolbeltView configuredTools] count] > 0;
    } else if ([item action] == @selector(moveSessionToWindow:)) {
        result = ([[self allSessions] count] > 1);
    } else if ([item action] == @selector(openSplitHorizontallySheet:) ||
        [item action] == @selector(openSplitVerticallySheet:)) {
        result = ![[self currentTab] isTmuxTab];
    } else if ([item action] == @selector(jumpToSavedScrollPosition:)) {
        result = [self hasSavedScrollPosition];
    } else if ([item action] == @selector(moveTabLeft:)) {
        result = [_contentView.tabView numberOfTabViewItems] > 1;
    } else if ([item action] == @selector(moveTabRight:)) {
        result = [_contentView.tabView numberOfTabViewItems] > 1;
    } else if ([item action] == @selector(toggleBroadcastingToCurrentSession:)) {
        result = ![[self currentSession] exited];
    } else if ([item action] == @selector(runCoprocess:)) {
        result = ![[self currentSession] hasCoprocess];
    } else if ([item action] == @selector(stopCoprocess:)) {
        result = [[self currentSession] hasCoprocess];
    } else if ([item action] == @selector(logStart:)) {
        result = logging == YES ? NO : YES;
    } else if ([item action] == @selector(logStop:)) {
        result = logging == NO ? NO : YES;
    } else if ([item action] == @selector(irPrev:)) {
        result = ![[self currentSession] liveSession] && [[self currentSession] canInstantReplayPrev];
    } else if ([item action] == @selector(irNext:)) {
        result = [[self currentSession] canInstantReplayNext];
    } else if ([item action] == @selector(toggleCursorGuide:)) {
      PTYSession *session = [self currentSession];
      [item setState:session.highlightCursorLine ? NSOnState : NSOffState];
      result = YES;
    } else if ([item action] == @selector(toggleSelectionRespectsSoftBoundaries:)) {
        [item setState:[[iTermController sharedInstance] selectionRespectsSoftBoundaries] ? NSOnState : NSOffState];
        result = YES;
    } else if ([item action] == @selector(toggleAutoCommandHistory:)) {
        result = [[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed];
        if (result) {
            if ([item respondsToSelector:@selector(setState:)]) {
                [item setState:[iTermPreferences boolForKey:kPreferenceAutoCommandHistory] ? NSOnState : NSOffState];
            }
        } else {
            [item setState:NSOffState];
        }
    } else if ([item action] == @selector(toggleAlertOnNextMark:)) {
        PTYSession *currentSession = [self currentSession];
        if ([item respondsToSelector:@selector(setState:)]) {
            [item setState:currentSession.alertOnNextMark ? NSOnState : NSOffState];
        }
        result = (currentSession != nil);
    } else if ([item action] == @selector(selectPaneUp:) ||
               [item action] == @selector(selectPaneDown:) ||
               [item action] == @selector(selectPaneLeft:) ||
               [item action] == @selector(selectPaneRight:)) {
        result = ([[[self currentTab] sessions] count] > 1);
    } else if ([item action] == @selector(closeCurrentSession:)) {
        NSWindowController* controller = [[NSApp keyWindow] windowController];
        if (controller) {
            // Any object whose window controller implements this selector is closed by
            // cmd-w: pseudoterminal (closes a pane), preferences, bookmarks
            // window. Notably, not expose, various modal windows, etc.
            result = [controller respondsToSelector:@selector(closeCurrentSession:)];
        } else {
            result = NO;
        }
    } else if ([item action] == @selector(restartSession:)) {
        return [[self currentSession] isRestartable];
    } else if ([item action] == @selector(resetCharset:)) {
        result = ![[[self currentSession] screen] allCharacterSetPropertiesHaveDefaultValues];
    } else if ([item action] == @selector(openCommandHistory:)) {
        if (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
            return YES;
        }
        return [[iTermShellHistoryController sharedInstance] haveCommandsForHost:[[self currentSession] currentHost]];
    } else if ([item action] == @selector(openDirectories:)) {
        if (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
            return YES;
        }
        return [[iTermShellHistoryController sharedInstance] haveDirectoriesForHost:[[self currentSession] currentHost]];
    } else if ([item action] == @selector(movePaneDividerDown:)) {
        int height = [[[self currentSession] textview] lineHeight];
        return [[self currentTab] canMoveCurrentSessionDividerBy:height
                                                    horizontally:NO];
    } else if ([item action] == @selector(movePaneDividerUp:)) {
        int height = [[[self currentSession] textview] lineHeight];
        return [[self currentTab] canMoveCurrentSessionDividerBy:-height
                                                    horizontally:NO];
    } else if ([item action] == @selector(movePaneDividerRight:)) {
        int width = [[[self currentSession] textview] charWidth];
        return [[self currentTab] canMoveCurrentSessionDividerBy:width
                                                    horizontally:YES];
    } else if ([item action] == @selector(movePaneDividerLeft:)) {
        int width = [[[self currentSession] textview] charWidth];
        return [[self currentTab] canMoveCurrentSessionDividerBy:-width
                                                    horizontally:YES];
    } else if ([item action] == @selector(duplicateTab:)) {
        return ![[self currentTab] isTmuxTab];
    } else if ([item action] == @selector(zoomOnSelection:)) {
        return ![self inInstantReplay] && [[self currentSession] hasSelection];
    } else if ([item action] == @selector(showFindPanel:) ||
               [item action] == @selector(findPrevious:) ||
               [item action] == @selector(findNext:) ||
               [item action] == @selector(findWithSelection:) ||
               [item action] == @selector(jumpToSelection:) ||
               [item action] == @selector(findUrls:)) {
        result = ([self currentSession] != nil);
    } else if ([item action] == @selector(openSelection:)) {
        result = [[self currentSession] hasSelection];
    } else if ([item action] == @selector(zoomOut:)) {
        return self.currentSession.textViewIsZoomedIn;
    }
    return result;
}

- (IBAction)toggleAutoCommandHistory:(id)sender
{
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceAutoCommandHistory]
                       forKey:kPreferenceAutoCommandHistory];
}

// Turn on/off sending of input to all sessions. This causes a bunch of UI
// to update in addition to flipping the flag.
- (IBAction)enableSendInputToAllPanes:(id)sender
{
    [self setBroadcastMode:BROADCAST_TO_ALL_PANES];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

- (IBAction)disableBroadcasting:(id)sender
{
    [self setBroadcastMode:BROADCAST_OFF];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

// Turn on/off sending of input to all sessions. This causes a bunch of UI
// to update in addition to flipping the flag.
- (IBAction)enableSendInputToAllTabs:(id)sender
{
    [self setBroadcastMode:BROADCAST_TO_ALL_TABS];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

// Push size changes to all sessions so they are all as large as possible while
// still fitting in the window.
- (void)fitTabsToWindow
{
    PtyLog(@"fitTabsToWindow begins");
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        [self fitTabToWindow:[[_contentView.tabView tabViewItemAtIndex:i] identifier]];
    }
    PtyLog(@"fitTabsToWindow returns");
}

// Show a dialog confirming close. Returns YES if the window should be closed.
- (BOOL)showCloseWindow
{
    return ([self confirmCloseForSessions:[self allSessions]
                               identifier:@"This window"
                              genericName:[NSString stringWithFormat:@"Window #%d", number_+1]]);
}

- (PSMTabBarControl*)tabBarControl
{
    return _contentView.tabBarControl;
}

// Called when the "Close tab" contextual menu item is clicked.
- (void)closeTabContextualMenuAction:(id)sender {
    PTYTab *tabToClose = (PTYTab *)[[sender representedObject] identifier];
    if ([self tabView:_contentView.tabView shouldCloseTabViewItem:tabToClose.tabViewItem]) {
        [self closeTab:tabToClose];
    }
}

- (IBAction)duplicateTab:(id)sender {
    PTYTab *theTab = (PTYTab *)[[sender representedObject] identifier];
    if (!theTab) {
        theTab = [self currentTab];
    }
    PTYTab *copyOfTab = [[theTab copy] autorelease];
    if ([iTermProfilePreferences boolForKey:KEY_PREVENT_TAB inProfile:self.currentSession.profile]) {
        [[iTermController sharedInstance] launchBookmark:self.currentSession.profile
                                              inTerminal:nil
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:YES
                                                 command:nil
                                                   block:^PTYSession *(PseudoTerminal *term) {
                                                       // Keep session size stable.
                                                       for (PTYSession* aSession in [copyOfTab sessions]) {
                                                           [aSession setIgnoreResizeNotifications:YES];
                                                       }

                                                       // This prevents the tab from getting resized to fit the window.
                                                       [copyOfTab setReportIdealSizeAsCurrent:YES];

                                                       // Add the tab to the empty window and resize the window.
                                                       [term appendTab:copyOfTab];
                                                       [term fitWindowToTabs];

                                                       // Undo the prep work we've done.
                                                       [copyOfTab setReportIdealSizeAsCurrent:NO];

                                                       for (PTYSession* aSession in [copyOfTab sessions]) {
                                                           [aSession setIgnoreResizeNotifications:NO];
                                                       }

                                                       return copyOfTab.activeSession;
                                                   }];
    } else {
        [self appendTab:copyOfTab];
    }
}

// These two methods are delecate because -closeTab: won't remove the tab from
// the -tabs array immediately for tmux tabs.
- (void)closeOtherTabs:(id)sender
{
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYTab *tabToKeep = [aTabViewItem identifier];
    NSMutableArray *tabsToRemove = [[[self tabs] mutableCopy] autorelease];
    [tabsToRemove removeObject:tabToKeep];
    for (PTYTab *tab in tabsToRemove) {
        [self closeTab:tab];
    }
}

- (void)closeTabsToTheRight:(id)sender
{
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYTab *tabToKeep = [aTabViewItem identifier];

    NSMutableArray *tabsToRemove = [[[self tabs] mutableCopy] autorelease];
    PTYTab *current;
    do {
        current = tabsToRemove[0];
        [tabsToRemove removeObjectAtIndex:0];
    } while (current != tabToKeep);

    for (PTYTab *tab in tabsToRemove) {
        [self closeTab:tab];
    }
}

// Move a tab to a new window due to a context menu selection.
- (void)moveTabToNewWindowContextualMenuAction:(id)sender
{
    NSWindowController<iTermWindowController> *term;
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYTab *aTab = [aTabViewItem identifier];

    if (aTab == nil) {
        return;
    }

    NSPoint point = [[self window] frame].origin;
    point.x += 10;
    point.y += 10;
    term = [self terminalDraggedFromAnotherWindowAtPoint:point];
    if (term == nil) {
        return;
    }

    // temporarily retain the tabViewItem
    [aTabViewItem retain];

    // remove from our window
    [_contentView.tabView removeTabViewItem:aTabViewItem];

    // add the session to the new terminal
    [term insertTab:aTab atIndex:0];
    PtyLog(@"moveTabToNewWindowContextMenuAction - call fitWindowToTabs");
    [term fitWindowToTabs];

    // release the tabViewItem
    [aTabViewItem release];
}

// Change the tab color to the selected menu color
- (void)changeTabColorToMenuAction:(id)sender {
    // If we got here because you right clicked on a tab, use the represented object.
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYTab *aTab = [aTabViewItem identifier];

    if (!aTab) {
        // Must have selected it from the view menu.
        aTab = [self currentTab];
    }

    ColorsMenuItemView *menuItem = (ColorsMenuItemView *)[sender view];
    NSColor *color = menuItem.color;
    for (PTYSession *aSession in [aTab sessions]) {
        [aSession setTabColor:color];
    }
    [self updateTabColors];
}

// Close this window.
- (IBAction)closeWindow:(id)sender
{
    [[self window] performClose:sender];
}

- (void)reloadBookmarks
{
    for (PTYSession* session in [self allSessions]) {
        Profile *oldBookmark = [session profile];
        NSString* oldName = [oldBookmark objectForKey:KEY_NAME];
        [oldName retain];
        NSString* guid = [oldBookmark objectForKey:KEY_GUID];
        if ([session reloadProfile]) {
            [[self tabForSession:session] recheckBlur];
            NSDictionary *profile = [session profile];
            if (![[profile objectForKey:KEY_NAME] isEqualToString:oldName]) {
                // Set name, which overrides any session-set icon name.
                [session setName:[profile objectForKey:KEY_NAME]];
                // set default name, which will appear as a prefix if the session changes the name.
                [session setDefaultName:[profile objectForKey:KEY_NAME]];
            }
            if ([session isDivorced] &&
                [[[PreferencePanel sessionsInstance] currentProfileGuid] isEqualToString:guid] &&
                [[PreferencePanel sessionsInstance] isWindowLoaded]) {
                [[PreferencePanel sessionsInstance] underlyingBookmarkDidChange];
            }
        }
        [oldName release];
    }
}

// Called when the parameter panel should close.
- (IBAction)parameterPanelEnd:(id)sender {
    _parameterPanelCanceled = ([sender tag] == 0);
    [NSApp stopModal];
}

// Return the timestamp for a slider position in [0, 1] for the current session.
- (long long)timestampForFraction:(float)f
{
    DVR* dvr = [[self currentSession] dvr];
    long long range = [dvr lastTimeStamp] - [dvr firstTimeStamp];
    long long offset = range * f;
    return [dvr firstTimeStamp] + offset;
}

- (NSArray*)allSessions
{
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[_contentView.tabView numberOfTabViewItems]];
    for (NSTabViewItem* item in [_contentView.tabView tabViewItems]) {
        [result addObjectsFromArray:[[item identifier] sessions]];
    }
    return result;
}

// Allocate a new session and assign it a bookmark. Returns a retained object.
- (PTYSession*)newSessionWithBookmark:(Profile*)bookmark
{
    assert(bookmark);
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];

    [[aSession screen] setUnlimitedScrollback:[[bookmark objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[bookmark objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setProfile:bookmark];
    return aSession;
}

// Execute the bookmark command in this session.
// Used when adding a split pane.
// Execute the bookmark command in this session.
- (BOOL)runCommandInSession:(PTYSession*)aSession
                      inCwd:(NSString*)oldCWD
              forObjectType:(iTermObjectType)objectType {
    if ([aSession screen]) {
        BOOL isUTF8;
        // Grab the addressbook command
        Profile *profile = [aSession profile];
        NSString *cmd = [ITAddressBookMgr bookmarkCommand:profile
                                            forObjectType:objectType];
        NSString *name = profile[KEY_NAME];

        // Get session parameters
        NSDictionary *substitutions = [self substitutionsForCommand:cmd
                                                        sessionName:name
                                                  baseSubstitutions:@{}];
        if (!substitutions) {
            return NO;
        }

        name = [name stringByPerformingSubstitutions:substitutions];
        NSString *pwd = [ITAddressBookMgr bookmarkWorkingDirectory:profile
                                                     forObjectType:objectType];
        if ([pwd length] == 0) {
            if (oldCWD) {
                pwd = oldCWD;
            } else {
                pwd = NSHomeDirectory();
            }
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:profile] == NSUTF8StringEncoding);
        [self setName:name forSession:aSession];
        // Start the command
        [self startProgram:cmd
               environment:env
                    isUTF8:isUTF8
                 inSession:aSession
             substitutions:substitutions];
        return YES;
    }
    return NO;
}

- (void)_loadFindStringFromSharedPasteboard
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                        object:nil
                                                      userInfo:nil];
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}

- (void)incrementBadge {
    if (![iTermAdvancedSettingsModel indicateBellsInDockBadgeLabel]) {
        return;
    }

    NSDockTile *dockTile;
    if (self.window.isMiniaturized) {
      dockTile = self.window.dockTile;
    } else {
      if ([[NSApplication sharedApplication] isActive]) {
        return;
      }
      dockTile = [[NSApplication sharedApplication] dockTile];
    }
    int count = [[dockTile badgeLabel] intValue];
    if (count == 999) {
        return;
    }
    ++count;
    [dockTile setBadgeLabel:[NSString stringWithFormat:@"%d", count]];
    [self.window.dockTile setShowsApplicationBadge:YES];
}

- (void)sessionHostDidChange:(PTYSession *)session to:(VT100RemoteHost *)host {
    if ([self currentSession] == session) {
        [self refreshTools];
    }
}

#pragma mark - iTermTabBarControlViewDelegate

- (BOOL)eligibleForFullScreenTabBarToFlash {
    return ([self anyFullScreen] &&
            !exitingLionFullscreen_ &&
            ![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar] &&
            ![[[self currentSession] textview] isFindingCursor]);
}

- (BOOL)iTermTabBarShouldFlashAutomatically {
    return ([iTermPreferences boolForKey:kPreferenceKeyFlashTabBarInFullscreen] &&
            [self eligibleForFullScreenTabBarToFlash]);
}

- (void)iTermTabBarWillBeginFlash {
    _contentView.tabBarControl.alphaValue = 0;
    _contentView.tabBarControl.hidden = NO;
    [self repositionWidgets];
}

- (void)iTermTabBarDidFinishFlash {
    _contentView.tabBarControl.alphaValue = 1;
    _contentView.tabBarControl.hidden = YES;
    [self repositionWidgets];
}

- (PTYSession *)createTabWithProfile:(Profile *)profile
                         withCommand:(NSString *)command {
    assert(profile);

    // Get active session's directory
    NSString *previousDirectory = nil;
    PTYSession* currentSession = [[[iTermController sharedInstance] currentTerminal] currentSession];
    if (currentSession) {
        previousDirectory = [currentSession currentLocalWorkingDirectory];
    }

    // Initialize a new session
    PTYSession *aSession = [[[PTYSession alloc] init] autorelease];
    [[aSession screen] setUnlimitedScrollback:[[profile objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[profile objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // If a command was provided, create a temporary copy of the profile dictionary that runs
    // the user-supplied command in lieu of the profile's command.
    NSString *preferredName = nil;

    iTermObjectType objectType;
    if ([_contentView.tabView numberOfTabViewItems] == 0) {
        objectType = iTermWindowObject;
    } else {
        objectType = iTermTabObject;
    }
    NSString *commandForSubs = command;
    if (!command) {
        commandForSubs = [ITAddressBookMgr bookmarkCommand:profile
                                             forObjectType:objectType];
    }
    NSDictionary *substitutions = [self substitutionsForCommand:commandForSubs ?: @""
                                                    sessionName:profile[KEY_NAME] ?: @""
                                              baseSubstitutions:@{}];
    if (!substitutions) {
        return nil;
    }
    if (command) {
        // Create a modified profile to run "command".
        NSMutableDictionary *temp = [[profile mutableCopy] autorelease];
        temp[KEY_CUSTOM_COMMAND] = @"Yes";
        temp[KEY_COMMAND_LINE] = command;
        profile = temp;

    } else if (substitutions.count && profile[KEY_NAME]) {
        preferredName = [profile[KEY_NAME] stringByPerformingSubstitutions:substitutions];
    }

    // set our preferences
    [aSession setProfile:profile];
    // Add this session to our term and make it current
    [self addSessionInNewTab:aSession];
    if ([aSession screen]) {
        [aSession runCommandWithOldCwd:previousDirectory
                         forObjectType:objectType
                        forceUseOldCWD:NO
                         substitutions:substitutions];
        if ([[[self window] title] compare:@"Window"] == NSOrderedSame) {
            [self setWindowTitle];
        }
        if (preferredName) {
            [self setName:preferredName forSession:aSession];
        }
    }

    // On Lion, a window that can join all spaces can't go fullscreen.
    if ([self numberOfTabs] == 1 &&
        profile[KEY_SPACE] &&
        [profile[KEY_SPACE] intValue] == iTermProfileJoinsAllSpaces) {
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorCanJoinAllSpaces];
    }

    return aSession;
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state
{
    [self loadArrangement:[state decodeObjectForKey:kTerminalWindowStateRestorationWindowArrangementKey]
                 sessions:nil];
}

- (BOOL)allTabsAreTmuxTabs
{
    for (PTYTab *aTab in [self tabs]) {
        if (![aTab isTmuxTab]) {
            return NO;
        }
    }
    return YES;
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state {
    if (doNotSetRestorableState_) {
        // The window has been destroyed beyond recognition at this point and
        // there is nothing to save.
        return;
    }
    // Don't save and restore the hotkey window. The OS only restores windows that are in the window
    // order, and hotkey windows may be ordered in or out, depending on whether they were in use. So
    // they get a special path for restoration where the arrangement is saved in user defaults.
    if ([self isHotKeyWindow]) {
        [[self ptyWindow] setRestoreState:nil];
        [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] saveHotKeyWindowState];
        return;
    }

    // Don't restore tmux windows since their canonical state is on the server.
    if ([self allTabsAreTmuxTabs]) {
        [[self ptyWindow] setRestoreState:nil];
        return;
    }
    if (wellFormed_) {
        [lastArrangement_ release];
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
        lastArrangement_ = [[self arrangementExcludingTmuxTabs:YES
                                             includingContents:includeContents] retain];
        NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
        DLog(@"Time to encode state for window %@: %@", self, @(end - start));
    }
    // For whatever reason, setting the value in the coder here doesn't work but
    // doing it in PTYWindow immediately after this method's caller returns does
    // work.
    [[self ptyWindow] setRestoreState:lastArrangement_];
}

- (NSApplicationPresentationOptions)window:(NSWindow *)window
      willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions {
    return proposedOptions | NSApplicationPresentationAutoHideToolbar;
}

- (PTYSession *)createSessionWithProfile:(NSDictionary *)profile
                                 withURL:(NSString *)urlString
                           forObjectType:(iTermObjectType)objectType
                        serverConnection:(iTermFileDescriptorServerConnection *)serverConnection {
    PtyLog(@"PseudoTerminal: -createSessionWithProfile:withURL:forObjectType:");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[[PTYSession alloc] init] autorelease];
    [[aSession screen] setUnlimitedScrollback:[profile[KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[profile[KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setProfile:profile];
    // Add this session to our term and make it current
    [self addSessionInNewTab: aSession];
    if ([aSession screen]) {
        // We process the cmd to insert URL parts
        NSString *cmd = [ITAddressBookMgr bookmarkCommand:profile
                                            forObjectType:objectType];
        NSString *name = profile[KEY_NAME];
        NSURL *url = [NSURL URLWithString:urlString];

        // Grab the addressbook command
        NSDictionary *substitutions = @{ @"$$URL$$": urlString ?: @"",
                                         @"$$HOST$$": [url host] ?: @"",
                                         @"$$USER$$": [url user] ?: @"",
                                         @"$$PASSWORD$$": [url password] ?: @"",
                                         @"$$PORT$$": [url port] ? [[url port] stringValue] : @"",
                                         @"$$PATH$$": [url path] ?: @"",
                                         @"$$RES$$": [url resourceSpecifier] ?: @"" };

        // If the command or name have any $$VARS$$ not accounted for above, prompt the user for
        // substitutions.
        substitutions = [self substitutionsForCommand:cmd
                                          sessionName:name
                                    baseSubstitutions:substitutions];
        if (!substitutions) {
            return nil;
        }

        NSString *pwd = [ITAddressBookMgr bookmarkWorkingDirectory:profile forObjectType:objectType];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        BOOL isUTF8 = ([iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:profile] == NSUTF8StringEncoding);

        [self setName:[name stringByPerformingSubstitutions:substitutions]
           forSession:aSession];

        // Start the command
        if (serverConnection) {
            assert([iTermAdvancedSettingsModel runJobsInServers]);
            [aSession attachToServer:*serverConnection];
        } else {
            [self startProgram:cmd
                   environment:env
                        isUTF8:isUTF8
                     inSession:aSession
                 substitutions:substitutions];
        }
    }
    return aSession;
}

- (void)addSessionInNewTab:(PTYSession *)object {
    PtyLog(@"PseudoTerminal: -addSessionInNewTab: %p", object);
    // Increment tabViewItemsBeingAdded so that the maximum content size will
    // be calculated with the tab bar if it's about to open.
    ++tabViewItemsBeingAdded;
    [self setupSession:object title:nil withSize:nil];
    tabViewItemsBeingAdded--;
    if ([object screen]) {  // screen initialized ok
        if ([iTermAdvancedSettingsModel addNewTabAtEndOfTabs] || ![self currentTab]) {
            [self insertSession:object atIndex:[_contentView.tabView numberOfTabViewItems]];
        } else {
            [self insertSession:object atIndex:[self indexOfTab:[self currentTab]] + 1];
        }
    }
    [[self currentTab] numberOfSessionsDidChange];
}

- (void)sessionDidTerminate:(PTYSession *)session {
    if (pbHistoryView.delegate == session) {
        pbHistoryView.delegate = nil;
    }
    if (autocompleteView.delegate == session) {
        autocompleteView.delegate = nil;
    }
    if (commandHistoryPopup.delegate == session) {
        commandHistoryPopup.delegate = nil;
    }
    if (_directoriesPopupWindowController.delegate == session) {
        _directoriesPopupWindowController.delegate = nil;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded]) {
        if (self.currentSession) {
            [self editSession:self.currentSession makeKey:NO];
        } else {
            [[[PreferencePanel sessionsInstance] window] close];
        }
    }
}

- (IBAction)openSelection:(id)sender {
    [[self currentSession] openSelection];
}

#pragma mark - Find

- (IBAction)showFindPanel:(id)sender {
    [[self currentSession] showFindPanel];
}

// findNext and findPrevious are reversed here because in the search UI next
// goes backwards and previous goes forwards.
// Internally, next=forward and prev=backwards.
- (IBAction)findPrevious:(id)sender {
    [[self currentSession] searchNext];
}

- (IBAction)findNext:(id)sender {
    [[self currentSession] searchPrevious];
}

- (IBAction)findWithSelection:(id)sender {
    NSString* selection = [[[self currentSession] textview] selectedText];
    if (selection) {
        for (PseudoTerminal* pty in [[iTermController sharedInstance] terminals]) {
            for (PTYSession* session in [pty allSessions]) {
                [session useStringForFind:selection];
            }
        }
    }
}

- (IBAction)jumpToSelection:(id)sender
{
    PTYTextView *textView = [[self currentSession] textview];
    if (textView) {
        [textView scrollToSelection];
    } else {
        NSBeep();
    }
}

#pragma mark - iTermPasswordManagerDelegate

- (BOOL)iTermPasswordManagerCanEnterPassword {
    PTYSession *session = [self currentSession];
    return session && ![session exited];
}

- (void)iTermPasswordManagerEnterPassword:(NSString *)password {
    [[self currentSession] enterPassword:password];
}

#pragma mark - PTYTabDelegate

- (void)tab:(PTYTab *)tab didChangeProcessingStatus:(BOOL)isProcessing {
    [_contentView.tabBarControl setIsProcessing:isProcessing forTabWithIdentifier:tab];
}

- (void)tab:(PTYTab *)tab didChangeIcon:(NSImage *)icon {
    [_contentView.tabBarControl setIcon:icon forTabWithIdentifier:tab];
}

- (void)tab:(PTYTab *)tab didChangeObjectCount:(NSInteger)objectCount {
    [_contentView.tabBarControl setObjectCount:objectCount forTabWithIdentifier:tab];
}

#pragma mark - Toolbelt

- (void)toolbeltUpdateMouseCursor {
    [[[self currentSession] textview] updateCursor:[[NSApplication sharedApplication] currentEvent]];
}

- (void)toolbeltInsertText:(NSString *)text {
    [[[self currentSession] textview] insertText:text];
    [[self currentSession] takeFocus];
}

- (VT100RemoteHost *)toolbeltCurrentHost {
    return [[self currentSession] currentHost];
}

- (pid_t)toolbeltCurrentShellProcessId {
    return [[[self currentSession] shell] pid];
}

- (VT100ScreenMark *)toolbeltLastCommandMark {
    return self.currentSession.screen.lastCommandMark;
}

- (void)toolbeltDidSelectMark:(iTermMark *)mark {
    [self.currentSession scrollToMark:mark];
    [self.currentSession takeFocus];
}

- (void)toolbeltActivateTriggerForCapturedOutputInCurrentSession:(CapturedOutput *)capturedOutput {
    if (self.currentSession) {
        CaptureTrigger *trigger = (CaptureTrigger *)capturedOutput.trigger;
        [trigger activateOnOutput:capturedOutput inSession:self.currentSession];
    }
}

- (BOOL)toolbeltCurrentSessionHasGuid:(NSString *)guid {
    return [self.currentSession.guid isEqualToString:guid];
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)toolbeltCommandUsesForCurrentSession {
    return [self.currentSession commandUses];
}

#pragma mark - Quick Look panel support

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel {
    return self.currentSession.quickLookController != nil;
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
    [self.currentSession.quickLookController beginPreviewPanelControl:panel];
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
    [self.currentSession.quickLookController endPreviewPanelControl:panel];
}

@end
