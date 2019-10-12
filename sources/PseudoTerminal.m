#import "PseudoTerminal.h"
#import "PseudoTerminal+Private.h"
#import "PseudoTerminal+TouchBar.h"

#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "ColorsMenuItemView.h"
#import "CommandHistoryPopup.h"
#import "Coprocess.h"
#import "DirectoriesPopup.h"
#import "FakeWindow.h"
#import "FutureMethods.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermAPIHelper.h"
#import "iTermAboutWindow.h"
#import "iTermAdjustFontSizeHelper.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementView.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermBroadcastInputHelper.h"
#import "iTermBroadcastPasswordHelper.h"
#import "iTermBuiltInFunctions.h"
#import "iTermColorPresets.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermController.h"
#import "iTermFindCursorView.h"
#import "iTermFindDriver.h"
#import "iTermFontPanel.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermNotificationCenter.h"
#import "iTermNotificationController.h"
#import "iTermHotKeyController.h"
#import "iTermHotKeyMigrationHelper.h"
#import "iTermInstantReplayWindowController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermLionFullScreenTabBarViewController.h"
#import "iTermMenuBarObserver.h"
#import "iTermObject.h"
#import "iTermOpenQuicklyWindow.h"
#import "iTermPasswordManagerWindowController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermProfilesWindowController.h"
#import "iTermPromptOnCloseReason.h"
#import "iTermQuickLookController.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermRecordingCodec.h"
#import "iTermRootTerminalView.h"
#import "iTermSavePanel.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSelection.h"
#import "iTermSessionFactory.h"
#import "iTermShellHistoryController.h"
#import "iTermSwiftyString.h"
#import "iTermSwiftyStringGraph.h"
#import "iTermSystemVersion.h"
#import "iTermTabBarControlView.h"
#import "iTermTheme.h"
#import "iTermToolbeltView.h"
#import "iTermTouchBarButton.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Tab.h"
#import "iTermVariableScope+Window.h"
#import "iTermWarning.h"
#import "iTermWindowOcclusionChangeMonitor.h"
#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "MovePaneController.h"
#import "NSAlert+iTerm.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+iTerm.h"
#import "NSWindow+PSM.h"
#import "NSWorkspace+iTerm.h"
#import "PasteboardHistory.h"
#import "PopupModel.h"
#import "PopupWindow.h"
#import "PreferencePanel.h"
#import "PseudoTerminalRestorer.h"
#import "PSMDarkTabStyle.h"
#import "PSMDarkHighContrastTabStyle.h"
#import "PSMLightHighContrastTabStyle.h"
#import "PSMMinimalTabStyle.h"
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
#import <QuartzCore/QuartzCore.h>
#include <unistd.h>

@class QLPreviewPanel;

NSString *const kCurrentSessionDidChange = @"kCurrentSessionDidChange";
NSString *const kTerminalWindowControllerWasCreatedNotification = @"kTerminalWindowControllerWasCreatedNotification";
NSString *const iTermDidDecodeWindowRestorableStateNotification = @"iTermDidDecodeWindowRestorableStateNotification";
NSString *const iTermTabDidChangePositionInWindowNotification = @"iTermTabDidChangePositionInWindowNotification";
NSString *const iTermSelectedTabDidChange = @"iTermSelectedTabDidChange";
NSString *const iTermWindowDidCloseNotification = @"iTermWindowDidClose";
NSString *const iTermTabDidCloseNotification = @"iTermTabDidClose";
NSString *const iTermDidCreateTerminalWindowNotification = @"iTermDidCreateTerminalWindowNotification";

static NSString *const kWindowNameFormat = @"iTerm Window %d";

#define PtyLog DLog

// Constants for saved window arrangement key names.
static NSString *const TERMINAL_ARRANGEMENT_OLD_X_ORIGIN = @"Old X Origin";
static NSString *const TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN = @"Old Y Origin";
static NSString *const TERMINAL_ARRANGEMENT_OLD_WIDTH = @"Old Width";
static NSString *const TERMINAL_ARRANGEMENT_OLD_HEIGHT = @"Old Height";
static NSString *const TERMINAL_ARRANGEMENT_X_ORIGIN = @"X Origin";
static NSString *const TERMINAL_ARRANGEMENT_Y_ORIGIN = @"Y Origin";
static NSString *const TERMINAL_ARRANGEMENT_WIDTH = @"Width";
static NSString *const TERMINAL_ARRANGEMENT_HEIGHT = @"Height";
static NSString *const TERMINAL_ARRANGEMENT_EDGE_SPANNING_OFF = @"Edge Spanning Off";  // Deprecated. Included in window type now.
static NSString *const TERMINAL_ARRANGEMENT_TABS = @"Tabs";
static NSString *const TERMINAL_ARRANGEMENT_FULLSCREEN = @"Fullscreen";
static NSString *const TERMINAL_ARRANGEMENT_LION_FULLSCREEN = @"LionFullscreen";
static NSString *const TERMINAL_ARRANGEMENT_WINDOW_TYPE = @"Window Type";
static NSString *const TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE = @"Saved Window Type";  // Only relevant for fullscreen
static NSString *const TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX = @"Selected Tab Index";
static NSString *const TERMINAL_ARRANGEMENT_SCREEN_INDEX = @"Screen";
static NSString *const TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING = @"Hide After Opening";
static NSString *const TERMINAL_ARRANGEMENT_DESIRED_COLUMNS = @"Desired Columns";
static NSString *const TERMINAL_ARRANGEMENT_DESIRED_ROWS = @"Desired Rows";
static NSString *const TERMINAL_ARRANGEMENT_IS_HOTKEY_WINDOW = @"Is Hotkey Window";
static NSString *const TERMINAL_ARRANGEMENT_INITIAL_PROFILE = @"Initial Profile";  // Optional

static NSString *const TERMINAL_GUID = @"TerminalGuid";
static NSString *const TERMINAL_ARRANGEMENT_HAS_TOOLBELT = @"Has Toolbelt";
static NSString *const TERMINAL_ARRANGEMENT_HIDING_TOOLBELT_SHOULD_RESIZE_WINDOW = @"Hiding Toolbelt Should Resize Window";
static NSString *const TERMINAL_ARRANGEMENT_USE_TRANSPARENCY = @"Use Transparency";
static NSString *const TERMINAL_ARRANGEMENT_TOOLBELT_PROPORTIONS = @"Toolbelt Proportions";
static NSString *const TERMINAL_ARRANGEMENT_TITLE_OVERRIDE = @"Title Override";
static NSString *const TERMINAL_ARRANGEMENT_TOOLBELT = @"Toolbelt";

static NSRect iTermRectCenteredHorizontallyWithinRect(NSRect frameToCenter, NSRect container) {
    CGFloat centerOfContainer = NSMidX(container);
    CGFloat centerOfFrame = NSMidX(frameToCenter);
    CGFloat diff = centerOfContainer - centerOfFrame;
    frameToCenter.origin.x += diff;
    return frameToCenter;
}

static NSRect iTermRectCenteredVerticallyWithinRect(NSRect frameToCenter, NSRect container) {
    CGFloat centerOfContainer = NSMidY(container);
    CGFloat centerOfFrame = NSMidY(frameToCenter);
    CGFloat diff = centerOfContainer - centerOfFrame;
    frameToCenter.origin.y += diff;
    return frameToCenter;
}

static BOOL iTermWindowTypeIsCompact(iTermWindowType windowType) {
    return windowType == WINDOW_TYPE_COMPACT || windowType == WINDOW_TYPE_COMPACT_MAXIMIZED;
}

@interface PseudoTerminal () <
    iTermBroadcastInputHelperDelegate,
    iTermObject,
    iTermTabBarControlViewDelegate,
    iTermPasswordManagerDelegate,
    PTYTabDelegate,
    iTermRootTerminalViewDelegate,
    iTermToolbeltViewDelegate,
    NSComboBoxDelegate,
    PSMMinimalTabStyleDelegate>

@property(nonatomic, assign) BOOL windowInitialized;

// Session ID of session that currently has an auto-command history window open
@property(nonatomic, copy) NSString *autoCommandHistorySessionGuid;
@property(nonatomic, assign) NSTimeInterval timeOfLastResize;

// Used for delaying and coalescing title changes. After a title change request
// is received the new title is stored here and a .1 second delay begins. If a
// new request is made before the timer is up this property gets changed. It is
// reset to nil after the change is made in the window.
@property(nonatomic, copy) NSString *desiredTitle;

@property(nonatomic, readonly) iTermVariables *variables;
@property(nonatomic, readonly) iTermSwiftyString *windowTitleOverrideSwiftyString;
@end

@implementation PseudoTerminal {
    NSTimer *_shadowTimer;
    NSPoint preferredOrigin_;

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

    // DO NOT ACCESS DIRECTLY - USE ACCESSORS INSTEAD
    iTermWindowType _windowType;

    // DO NOT ACCESS DIRECTLY - USE ACCESSORS INSTEAD
    // Window type before entering fullscreen. Only relevant if in/entering fullscreen.
    iTermWindowType _savedWindowType;

    // Indicates if _anchoredScreenNumber is to be used.
    BOOL _isAnchoredToScreen;

    // The initial screen used for the window. Always >= 0.
    int _anchoredScreenNumber;

    // // The KEY_SCREEN from the profile the window was created with.
    // -2 = follow cursor, -1 = no preference, >= 0 screen number
    int _screenNumberFromFirstProfile;

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

    iTermBroadcastInputHelper *_broadcastInputHelper;
    
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
    IBOutlet NSButton *coprocessIgnoreErrors_;

    NSDictionary *lastArrangement_;

    BOOL exitingLionFullscreen_;

    // If positive, then any window resizing that happens is driven by tmux and
    // shouldn't be reported back to tmux as a user-originated resize.
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
    //
    // Update: This seems to work properly on Mojave. Hurray!
    iTermWindowShortcutLabelTitlebarAccessoryViewController *_shortcutAccessoryViewController NS_AVAILABLE_MAC(10_14);
    iTermLionFullScreenTabBarViewController *_lionFullScreenTabBarViewController NS_AVAILABLE_MAC(10_14);
    
    // Is there a pending delayed-perform of enterFullScreen:? Used to figure
    // out if it's safe to toggle Lion full screen since only one can go at a time.
    BOOL _haveDelayedEnterFullScreenMode;

    // Number of tabs since last change.
    NSInteger _previousNumberOfTabs;

    // The window restoration completion block was called but windowDidDecodeRestorableState:
    // has not yet been called.
    BOOL _expectingDecodeOfRestorableState;

    // Used to prevent infinite reentrancy in windowDidChangeScreen:.
    BOOL _inWindowDidChangeScreen;

    iTermPasswordManagerWindowController *_passwordManagerWindowController;

    // Keeps the touch bar from updating on every keypress which is distracting.
    iTermRateLimitedIdleUpdate *_touchBarRateLimitedUpdate;
    NSString *_previousTouchBarWord;

    BOOL _windowWasJustCreated;

    iTermSessionFactory *_sessionFactory;
    BOOL _openingPopupWindow;

    NSInteger _fullScreenRetryCount;

    // This is true if the user is dragging the window by the titlebar. It should not be set for
    // programmatic moves or moves because of disconnecting a display.
    BOOL _windowIsMoving;
    NSInteger _screenBeforeMoving;
    BOOL _constrainFrameAfterDeminiaturization;

    // Size of the last grid size shown in the transient window title, or 0,0 for never shown before.
    VT100GridSize _previousGridSize;
    // Have we started showing a transient title? If so, don't stop until time runs out.
    BOOL _lockTransientTitle;

    NSMutableArray *_toggleFullScreenModeCompletionBlocks;

    BOOL _windowNeedsInitialSize;

    iTermFunctionCallTextFieldDelegate *_currentTabTitleTextFieldDelegate;
    iTermVariables *_userVariables;
    iTermBuiltInFunctions *_methods;

    BOOL _anyPaneIsTransparent;
    BOOL _windowDidResize;
    BOOL _willClose;
    BOOL _updatingWindowType;  // updateWindowType is not reentrant
    BOOL _suppressMakeCurrentTerminal;
    NSArray *_screenConfigurationAtTimeOfForceFrame;
    NSRect _forceFrame;
    NSTimeInterval _forceFrameUntil;
}

@synthesize scope = _scope;
@synthesize variables = _variables;
@synthesize windowTitleOverrideSwiftyString = _windowTitleOverrideSwiftyString;

+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement {
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
        [PTYTab registerSessionsInArrangement:tabArrangement];
    }
}

+ (BOOL)windowTypeHasFullSizeContentView:(iTermWindowType)windowType {
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            if (@available(macOS 10.14, *)) {
                return YES;
            } else {
                return NO;
            }

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return NO;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return YES;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_NORMAL:
            return NO;
    }
}

+ (NSInteger)styleMaskForWindowType:(iTermWindowType)windowType
                    savedWindowType:(iTermWindowType)savedWindowType
                   hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    NSInteger mask = 0;
    if (hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) {
        mask = NSWindowStyleMaskNonactivatingPanel;
    }
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            if (@available(macOS 10.14, *)) {
                return (mask |
                        NSWindowStyleMaskFullSizeContentView |
                        NSWindowStyleMaskTitled |
                        NSWindowStyleMaskClosable |
                        NSWindowStyleMaskMiniaturizable |
                        NSWindowStyleMaskResizable);
            } else {
                return mask | NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
            }

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            if (@available(macOS 10.13, *)) {
                return mask | NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable;
            } else {
                return mask | NSWindowStyleMaskBorderless;
            }

        case WINDOW_TYPE_COMPACT:
            return (mask |
                    NSWindowStyleMaskFullSizeContentView |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskResizable);

        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return (mask |
                    NSWindowStyleMaskFullSizeContentView |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskTexturedBackground);

        case WINDOW_TYPE_MAXIMIZED:
            return (mask |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskTexturedBackground);
 
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_NORMAL:
            if (@available(macOS 10.14, *)) {
                if ([self windowTypeHasFullSizeContentView:iTermThemedWindowType(savedWindowType)]) {
                    mask |= NSWindowStyleMaskFullSizeContentView;
                }
            }
            return (mask |
                    NSWindowStyleMaskTitled |
                    NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable |
                    NSWindowStyleMaskResizable |
                    NSWindowStyleMaskTexturedBackground);
    }
}

+ (Profile *)expurgatedInitialProfile:(Profile *)profile {
    // We don't care about almost all the keys in the profile, so don't waste space and privacy storing them.
    return [profile ?: @{} dictionaryKeepingOnlyKeys:@[ KEY_CUSTOM_WINDOW_TITLE, KEY_USE_CUSTOM_WINDOW_TITLE ]];
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
                             screen:(int)screenNumber
                            profile:(Profile *)profile {
    return [self initWithSmartLayout:smartLayout
                          windowType:windowType
                     savedWindowType:savedWindowType
                              screen:screenNumber
                    hotkeyWindowType:iTermHotkeyWindowTypeNone
                             profile:profile];
}

- (instancetype)initWithSmartLayout:(BOOL)smartLayout
                         windowType:(iTermWindowType)windowType
                    savedWindowType:(iTermWindowType)savedWindowType
                             screen:(int)screenNumber
                   hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                            profile:(Profile *)profile {
    self = [self initWithWindowNibName:@"PseudoTerminal"];
    NSAssert(self, @"initWithWindowNibName returned nil");
    if (self) {
        [self finishInitializationWithSmartLayout:smartLayout
                                       windowType:windowType
                                  savedWindowType:savedWindowType
                                           screen:screenNumber
                                 hotkeyWindowType:hotkeyWindowType
                                          profile:profile];
    }
    return self;
}

+ (int)screenNumberForPreferredScreenNumber:(int)screenNumber
                                 windowType:(iTermWindowType)windowType
                              defaultScreen:(NSScreen *)defaultScreen {
    if ((windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN ||
         windowType == WINDOW_TYPE_LION_FULL_SCREEN) &&
        screenNumber == -1) {
        NSUInteger n = [[NSScreen screens] indexOfObjectIdenticalTo:defaultScreen];
        if (n == NSNotFound) {
            DLog(@"Convert default screen to screen number: No screen matches the window's screen so using main screen");
            return 0;
        } else {
            DLog(@"Convert default screen to screen number: System chose screen %lu", (unsigned long)n);
            return n;
        }
    } else if (screenNumber == -2) {
        // Select screen with cursor.
        NSScreen *screenWithCursor = [NSScreen screenWithCursor];
        NSUInteger preference = [[NSScreen screens] indexOfObject:screenWithCursor];
        if (preference == NSNotFound) {
            preference = 0;
        }
        return preference;
    } else {
        return screenNumber;
    }
}

- (NSScreen *)anchorToScreenNumber:(int)screenNumber {
    NSScreen *screen = nil;
    if (screenNumber == -1 || screenNumber >= [[NSScreen screens] count])  {
        screen = [[self window] screen];
        DLog(@"Screen number %d is out of range [0,%d] so using 0",
             screenNumber, (int)[[NSScreen screens] count]);
        _anchoredScreenNumber = 0;
        _isAnchoredToScreen = NO;
    } else if (screenNumber >= 0) {
        DLog(@"Selecting screen number %d", screenNumber);
        screen = [[NSScreen screens] objectAtIndex:screenNumber];
        _anchoredScreenNumber = screenNumber;
        _isAnchoredToScreen = YES;
    }
    return screen;
}

- (void)finishInitializationWithSmartLayout:(BOOL)smartLayout
                                 windowType:(iTermWindowType)unsafeWindowType
                            savedWindowType:(iTermWindowType)unsafeSavedWindowType
                                     screen:(int)screenNumber
                           hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                                    profile:(Profile *)profile {
    const iTermWindowType windowType = iTermThemedWindowType(unsafeWindowType);
    iTermWindowType savedWindowType = iTermThemedWindowType(unsafeSavedWindowType);
    DLog(@"-[%p finishInitializationWithSmartLayout:%@ windowType:%d screen:%d hotkeyWindowType:%@ ",
         self,
         smartLayout ? @"YES" : @"NO",
         windowType,
         screenNumber,
         @(hotkeyWindowType));

    _variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextWindow
                                                   owner:self];
    _variables.primaryKey = iTermVariableKeyWindowID;
    _scope = [iTermVariableScope newWindowScopeWithVariables:self.variables
                                                tabVariables:[[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                                                               owner:self] autorelease]];
    _userVariables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                       owner:self];
    [_scope setValue:_userVariables forVariableNamed:@"user"];

    _toggleFullScreenModeCompletionBlocks = [[NSMutableArray alloc] init];
    _windowWasJustCreated = YES;
    PseudoTerminal<iTermWeakReference> *weakSelf = self.weakSelf;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PseudoTerminal *strongSelf = weakSelf.weaklyReferencedObject;
        if (strongSelf != nil) {
            strongSelf->_windowWasJustCreated = NO;
        }
    });

    // Force the nib to load
    [self window];
    _screenNumberFromFirstProfile = screenNumber;
    screenNumber = [PseudoTerminal screenNumberForPreferredScreenNumber:screenNumber
                                                             windowType:windowType
                                                          defaultScreen:[[self window] screen]];
    switch (windowType) {
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            PtyLog(@"Window type is %d so disable smart layout", windowType);
            smartLayout = NO;
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_NORMAL:
            break;
    }
    if (windowType == WINDOW_TYPE_NORMAL) {
        // If you create a window with a minimize button and the menu bar is hidden then the
        // minimize button is disabled. Currently the only window type with a miniaturize button
        // is NORMAL.
        [self showMenuBar];
    }
    // Force the nib to load
    [self window];
    self.windowType = windowType;
    _broadcastInputHelper = [[iTermBroadcastInputHelper alloc] init];
    _broadcastInputHelper.delegate = self;

    NSScreen *screen = [self anchorToScreenNumber:screenNumber];

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
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_MAXIMIZED:
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
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_ACCESSORY:
            // Use the system-supplied frame which has a reasonable origin. It may
            // be overridden by smart window placement or a saved window location.
            initialFrame = [[self window] frame];
            if (_isAnchoredToScreen) {
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

    if (savedWindowType == WINDOW_TYPE_LION_FULL_SCREEN ||
        savedWindowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        // This is not allowed.
        savedWindowType = windowType;
        if (savedWindowType == WINDOW_TYPE_LION_FULL_SCREEN ||
            savedWindowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
            savedWindowType = iTermWindowDefaultType();
        }
        PtyLog(@"Downgraded saved window type from fullscreen to %@", @(savedWindowType));
    }
    PtyLog(@"finishInitializationWithSmartLayout - initWithContentRect");
    // create the window programmatically with appropriate style mask
    NSUInteger styleMask;
    if (windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        // We want to set the style mask to the window's non-fullscreen appearance so we're prepared
        // to exit fullscreen with the right style.
        styleMask = [PseudoTerminal styleMaskForWindowType:savedWindowType
                                           savedWindowType:savedWindowType
                                          hotkeyWindowType:hotkeyWindowType];
    } else {
        styleMask = [PseudoTerminal styleMaskForWindowType:windowType
                                           savedWindowType:savedWindowType
                                          hotkeyWindowType:hotkeyWindowType];
    }
    _savedWindowType = savedWindowType;

    DLog(@"initWithContentRect:%@ styleMask:%d", [NSValue valueWithRect:initialFrame], (int)styleMask);
    // This is necessary to do here because the collection behavior is computed in setWindowWithWindowType,
    // and the window may become full screen thereafter. That's no good for a hotkey window.to
    _hotkeyWindowType = hotkeyWindowType;
    [self setWindowWithWindowType:windowType
                  savedWindowType:savedWindowType
           windowTypeForStyleMask:(windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) ? windowType : savedWindowType
                 hotkeyWindowType:hotkeyWindowType
                     initialFrame:initialFrame];

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
                                             selector:@selector(scrollerStyleDidChange:)
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(colorPresetsDidChange:)
                                                 name:kRebuildColorPresetsMenuNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyBindingsDidChange:)
                                                 name:kKeyBindingsChangedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowOcclusionDidChange:)
                                                 name:iTermWindowOcclusionDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(draggingDidBeginOrEnd:)
                                                 name:PSMTabDragDidEndNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(draggingDidBeginOrEnd:)
                                                 name:PSMTabDragDidBeginNotification
                                               object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(activeSpaceDidChange:)
                                                               name:NSWorkspaceActiveSpaceDidChangeNotification
                                                             object:nil];
    PtyLog(@"set window inited");
    self.windowInitialized = YES;
    useTransparency_ = [iTermProfilePreferences boolForKey:KEY_INITIAL_USE_TRANSPARENCY inProfile:profile];
    number_ = [[iTermController sharedInstance] allocateWindowNumber];
    [_scope setValue:@(number_ + 1) forVariableNamed:@"number"];
    if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [self hideMenuBar];
    }

    // Update the collection behavior.
    self.hotkeyWindowType = hotkeyWindowType;

    _wellFormed = YES;
    [[self window] setRestorable:YES];
    [[self window] setRestorationClass:[PseudoTerminalRestorer class]];
    self.terminalGuid = [NSString stringWithFormat:@"pty-%@", [NSString uuid]];

    if (@available(macOS 10.14, *)) {
        if ([self.window respondsToSelector:@selector(addTitlebarAccessoryViewController:)]) {
            _shortcutAccessoryViewController =
                [[iTermWindowShortcutLabelTitlebarAccessoryViewController alloc] initWithNibName:@"iTermWindowShortcutAccessoryView"
                                                                                          bundle:[NSBundle bundleForClass:self.class]];
        }
        [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
        _shortcutAccessoryViewController.ordinal = number_ + 1;
    }

    _initialProfile = [[PseudoTerminal expurgatedInitialProfile:profile] retain];
    if ([iTermProfilePreferences boolForKey:KEY_USE_CUSTOM_WINDOW_TITLE inProfile:profile]) {
        NSString *override = [iTermProfilePreferences stringForKey:KEY_CUSTOM_WINDOW_TITLE inProfile:profile];;
        [self.scope setValue:override.length ? override : @" " forVariableNamed:iTermVariableKeyWindowTitleOverrideFormat];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kTerminalWindowControllerWasCreatedNotification object:self];

    _windowTitleOverrideSwiftyString =
        [[iTermSwiftyString alloc] initWithScope:self.scope
                                      sourcePath:iTermVariableKeyWindowTitleOverrideFormat
                                 destinationPath:iTermVariableKeyWindowTitleOverride];
    _windowTitleOverrideSwiftyString.observer = ^NSString *(NSString * _Nonnull newValue, NSError *error) {
        if (error) {
            return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
        }
        [weakSelf setWindowTitle];
        return newValue;
    };
    [self updateVariables];
    _windowNeedsInitialSize = YES;
    DLog(@"Done initializing PseudoTerminal %@", self);
}

- (void)updateVariables {
    const NSRect rect = self.window.frame;
    [_scope setValue:@[ @(rect.origin.x),
                        @(rect.origin.y),
                        @(rect.size.width),
                        @(rect.size.height) ]
    forVariableNamed:iTermVariableKeyWindowFrame];

    NSString *style = @"unknown";
    switch (_windowType) {
        case WINDOW_TYPE_NORMAL:
            style = @"normal";
            break;
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            style = @"non-native full screen";
            break;
        case WINDOW_TYPE_LION_FULL_SCREEN:
            style = @"native full screen";
            break;
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            style = @"compact maximized";
            break;
        case WINDOW_TYPE_MAXIMIZED:
            style = @"maximized";
            break;
        case WINDOW_TYPE_TOP:
            style = @"full-width top";
            break;
        case WINDOW_TYPE_BOTTOM:
            style = @"full-width bottom";
            break;
        case WINDOW_TYPE_LEFT:
            style = @"full-height left";
            break;
        case WINDOW_TYPE_RIGHT:
            style = @"full-height right";
            break;
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            style = @"bottom";
            break;
        case WINDOW_TYPE_TOP_PARTIAL:
            style = @"top";
            break;
        case WINDOW_TYPE_LEFT_PARTIAL:
            style = @"left";
            break;
        case WINDOW_TYPE_RIGHT_PARTIAL:
            style = @"right";
            break;
        case WINDOW_TYPE_NO_TITLE_BAR:
            style = @"no-title-bar";
            break;
        case WINDOW_TYPE_COMPACT:
            style = @"compact";
            break;
        case WINDOW_TYPE_ACCESSORY:
            style = @"accessory";
            break;
    }
    [_scope setValue:style forVariableNamed:iTermVariableKeyWindowStyle];
}

- (void)setTerminalGuid:(NSString *)terminalGuid {
    assert(_scope);
    _scope.windowID = terminalGuid;
}

- (NSString *)terminalGuid {
    return _scope.windowID;
}

- (BOOL)isHotKeyWindow {
    return self.hotkeyWindowType != iTermHotkeyWindowTypeNone;
}

- (BOOL)isFloatingHotKeyWindow {
    return self.isHotKeyWindow && [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] floats];
}

- (NSWindowCollectionBehavior)desiredWindowCollectionBehavior {
    NSWindowCollectionBehavior result = self.window.collectionBehavior;
    if (self.windowType == WINDOW_TYPE_ACCESSORY) {
        return (NSWindowCollectionBehaviorFullScreenAuxiliary |
                NSWindowCollectionBehaviorManaged |
                NSWindowCollectionBehaviorParticipatesInCycle);
    }
    if (_spaceSetting == iTermProfileJoinsAllSpaces) {
        result |= NSWindowCollectionBehaviorCanJoinAllSpaces;
    }
    switch (_hotkeyWindowType) {
        case iTermHotkeyWindowTypeNone:
            // This allows the window to enter Lion fullscreen.
            result |= NSWindowCollectionBehaviorFullScreenPrimary;
            return result;

        case iTermHotkeyWindowTypeRegular:
        case iTermHotkeyWindowTypeFloatingPanel:
        case iTermHotkeyWindowTypeFloatingWindow: {
            result |= NSWindowCollectionBehaviorFullScreenAuxiliary;
            BOOL excludeFromCycling = [iTermAdvancedSettingsModel hotkeyWindowsExcludedFromCycling];
            if (!excludeFromCycling) {
                iTermProfileHotKey *profileHotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
                excludeFromCycling = !profileHotKey.isHotKeyWindowOpen;
            }
            if (excludeFromCycling) {
                result |= NSWindowCollectionBehaviorIgnoresCycle;
                result &= ~NSWindowCollectionBehaviorParticipatesInCycle;
            } else {
                result &= ~NSWindowCollectionBehaviorIgnoresCycle;
                result |= NSWindowCollectionBehaviorParticipatesInCycle;
            }
            break;
        }
    }
    return result;
}

- (void)setHotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType {
    _hotkeyWindowType = hotkeyWindowType;
    self.window.collectionBehavior = self.desiredWindowCollectionBehavior;
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
    _wellFormed = NO;

    // Do not assume that [self window] is valid here. It may have been freed.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

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
    [_broadcastInputHelper release];
    [autocompleteView shutdown];
    [commandHistoryPopup shutdown];
    [_directoriesPopupWindowController shutdown];
    [pbHistoryView shutdown];
    [pbHistoryView release];
    [commandHistoryPopup release];
    [_directoriesPopupWindowController release];
    [autocompleteView release];
    [lastArrangement_ release];
    [_autoCommandHistorySessionGuid release];
    if (@available(macOS 10.14, *)) {
        [_shortcutAccessoryViewController release];
        [_lionFullScreenTabBarViewController release];
    }
    [_didEnterLionFullscreen release];
    [_desiredTitle release];
    [_tabsTouchBarItem release];
    [_autocompleteCandidateListItem release];
    [_passwordManagerWindowController release];
    [_touchBarRateLimitedUpdate invalidate];
    [_touchBarRateLimitedUpdate release];
    [_previousTouchBarWord release];
    [_sessionFactory release];
    [_variables release];
    [_scope release];
    [_userVariables release];
    [_windowTitleOverrideSwiftyString release];
    [_initialProfile release];
    [_toggleFullScreenModeCompletionBlocks release];
    [_currentTabTitleTextFieldDelegate release];
    [_methods release];
    [_screenConfigurationAtTimeOfForceFrame release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p tabs=%d window=%@>",
            [self class], self, (int)[self numberOfTabs], [self window]];
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
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    return ([iTermPreferences boolForKey:kPreferenceKeyEnableDivisionView] &&
            preferredStyle != TAB_STYLE_MINIMAL &&
            !togglingFullScreen_ &&
            (self.window.styleMask & NSWindowStyleMaskTitled) &&
            ![self titleBarShouldAppearTransparent] &&
            ![self anyFullScreen] &&
            ![self tabBarVisibleOnTop]);
}

- (BOOL)rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar {
    if (togglingLionFullScreen_) {
        return NO;
    }
    if (self.anyFullScreen) {
        return NO;
    }
    if (!iTermWindowTypeIsCompact(self.windowType)) {
        return NO;
    }
    if (self.tabBarShouldBeVisible) {
        return NO;
    }
    if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] != PSMTab_TopTab) {
        return NO;
    }
    return YES;
}

- (void)rootTerminalViewDidResizeContentArea {
    // Fixes an analog of issue 4323 that happens with left-side tabs. More
    // details in -toolbeltDidFinishGrowing.
    [self fitTabsToWindow];
}

- (CGFloat)tabviewWidth {
    return _contentView.tabviewWidth;
}

- (void)toggleBroadcastingToCurrentSession:(id)sender {
    [_broadcastInputHelper toggleSession:self.currentSession.guid];
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

- (BOOL)windowIsResizing {
    return togglingFullScreen_ || liveResize_ || togglingLionFullScreen_ || exitingLionFullscreen_ || zooming_;
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

- (BOOL)showToolbeltNotFullScreen {
    BOOL didResizeWindow = NO;
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
            windowFrame.size.width -= overage;
            const NSSize decorationSize = [self windowDecorationSize];
            const CGFloat viewWidth = windowFrame.size.width - decorationSize.width;
            const CGFloat proposedToolbeltWidth = _contentView.toolbeltWidth - overage;
            const CGFloat desiredNonToolbeltWidth = windowFrame.size.width - proposedToolbeltWidth;
            _contentView.toolbeltWidth = MIN([_contentView maximumToolbeltWidthForViewWidth:viewWidth],
                                             proposedToolbeltWidth);
            windowFrame.size.width = desiredNonToolbeltWidth + _contentView.toolbeltWidth;
            overage = 0;
        }
    }
    if (overage <= 0 && !NSEqualRects(self.window.frame, windowFrame)) {
        didResizeWindow = YES;
        [self.window setFrame:windowFrame display:YES];
    }
    hidingToolbeltShouldResizeWindow_ = didResizeWindow;
    return didResizeWindow;
}

- (IBAction)toggleToolbeltVisibility:(id)sender {
    _contentView.shouldShowToolbelt = !_contentView.shouldShowToolbelt;
    BOOL didResizeWindow = NO;
    if (_contentView.shouldShowToolbelt) {
        if (![self anyFullScreen]) {
            didResizeWindow = [self showToolbeltNotFullScreen];
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

- (void)draggingDidBeginOrEnd:(NSNotification *)notification {
    [self updateUseMetalInAllTabs];
}

- (void)tmuxFontDidChange:(NSNotification *)notification {
    DLog(@"tmuxFontDidChange");
    PTYSession *session = notification.object;
    if ([[self uniqueTmuxControllers] count]) {
        if ([self.tabs anyWithBlock:^BOOL(PTYTab *tab) {
            return [tab.sessions containsObject:session] || !tab.tmuxController.variableWindowSize;
        }]) {
            [self fitWindowToIdealizedTabsPreservingHeight:NO];
        }
    }
}

- (NSWindowController<iTermWindowController> *)terminalDraggedFromAnotherWindowAtPoint:(NSPoint)point {
    PseudoTerminal *term;

    int screen = -1;
    switch (self.windowType) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_COMPACT:
            screen = -1;
            break;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_ACCESSORY:
            screen = [self _screenAtPoint:point];
            break;
    }

    // create a new terminal window
    iTermWindowType newWindowType;
    iTermWindowType savedWindowType;
    
    iTermWindowType realWindowType;
    if (self.lionFullScreen) {
        realWindowType = WINDOW_TYPE_LION_FULL_SCREEN;
    } else {
        realWindowType = self.windowType;
    }
    switch (iTermThemedWindowType(realWindowType)) {
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            savedWindowType = self.savedWindowType;
            newWindowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
            break;
            
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            savedWindowType = newWindowType = iTermWindowDefaultType();
            break;
            
        case WINDOW_TYPE_LION_FULL_SCREEN:
            savedWindowType = newWindowType = self.savedWindowType;
            break;

        case WINDOW_TYPE_ACCESSORY:
            savedWindowType = newWindowType = WINDOW_TYPE_ACCESSORY;
            break;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_NO_TITLE_BAR:
            savedWindowType = newWindowType = self.windowType;
    }
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                             windowType:newWindowType
                                        savedWindowType:savedWindowType
                                                 screen:screen
                                                profile:self.initialProfile] autorelease];
    if (term == nil) {
        return nil;
    }
    term->wasDraggedFromAnotherWindow_ = YES;
    [term copySettingsFrom:self];

    [[iTermController sharedInstance] addTerminalWindow:term];

    switch (iTermThemedWindowType(newWindowType)) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            [[term window] setFrameOrigin:point];
            break;
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            [[term window] makeKeyAndOrderFront:nil];
            [term hideMenuBar];
            break;
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            break;
    }

    return term;
}

- (int)number {
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

- (NSScreen *)screen {
    NSArray *screens = [NSScreen screens];
    if (screens.count == 0) {
        DLog(@"We are headless");
        return nil;
    } else if (_isAnchoredToScreen && _anchoredScreenNumber < screens.count) {
        DLog(@"Anchor screen preference %d respected", _anchoredScreenNumber);
        return screens[_anchoredScreenNumber];
    } else if (self.window.screen) {
        DLog(@"Not anchored, or anchored screen does not exist. Using current screen.");
        return self.window.screen;
    } else if (_screenNumberFromFirstProfile >= 0 && _screenNumberFromFirstProfile < screens.count) {
        DLog(@"Using screen number from first profile %d", _screenNumberFromFirstProfile);
        return screens[_screenNumberFromFirstProfile];
    } else {
        // _screenNumberFromFirstProfile must be no preference (-1), where
        // cursor was at creation time (-2), or out of range. We'll use the
        // first screen for lack of any better option.
        DLog(@"Using first screen because screen number from first profile is %d", _screenNumberFromFirstProfile);
        return screens.firstObject;
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

- (void)newSessionInTabAtIndex:(id)sender {
    Profile* profile = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (profile) {
        [self createTabWithProfile:profile
                       withCommand:nil
                       environment:nil
                       synchronous:NO
                        completion:nil];
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

- (void)tabTitleDidChange:(PTYTab *)tab {
    [self updateTouchBarIfNeeded:NO];
}

- (void)tabAddSwiftyStringsToGraph:(iTermSwiftyStringGraph *)graph {
    [graph addSwiftyString:_windowTitleOverrideSwiftyString
            withFormatPath:iTermVariableKeyWindowTitleOverrideFormat
            evaluationPath:iTermVariableKeyWindowTitleOverride
                     scope:self.scope];
}

- (void)tabSessionDidChangeTransparency:(PTYTab *)tab {
    // In case the last pane just becamse opaque, we can drop the visual effect view in the fake window title bar.
    [_contentView invalidateAutomaticTabBarBackingHiding];
}

- (BOOL)miniaturizedWindowShouldPreserveFrameUntilDeminiaturized {
    if (self.window.isMiniaturized) {
        switch (self.windowType) {
            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_ACCESSORY:
                DLog(@"Returning YES");
                return YES;
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
            case WINDOW_TYPE_LION_FULL_SCREEN:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            case WINDOW_TYPE_COMPACT:
                break;
        }
    }

    DLog(@"Returning NO");
    return NO;
}

// Allow frame to go off-screen while hotkey window is sliding in or out.
- (BOOL)terminalWindowShouldConstrainFrameToScreen {
    if ([self miniaturizedWindowShouldPreserveFrameUntilDeminiaturized]) {
        _constrainFrameAfterDeminiaturization = YES;
        return NO;
    }
    iTermProfileHotKey *profileHotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
    return !([profileHotKey rollingIn] || [profileHotKey rollingOut]);
}

- (NSColor *)terminalWindowDecorationBackgroundColor {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (self.shouldUseMinimalStyle) {
        return [self.currentSession.colorMap colorForKey:kColorMapBackground];
    } else {
        CGFloat whiteLevel = 0;
        switch ([self.window.effectiveAppearance it_tabStyle:preferredStyle]) {
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_COMPACT:
            case TAB_STYLE_MINIMAL:
                assert(NO);
            case TAB_STYLE_LIGHT:
                whiteLevel = 0.70;
                break;
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                whiteLevel = 0.80;
                break;
            case TAB_STYLE_DARK:
                whiteLevel = 0.27;
                break;
            case TAB_STYLE_DARK_HIGH_CONTRAST:
                whiteLevel = 0.17;
                break;
        }

        return [NSColor colorWithCalibratedWhite:whiteLevel alpha:1];
    }
}

- (NSColor *)terminalWindowDecorationControlColor {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (self.shouldUseMinimalStyle) {
        NSColor *color = [self terminalWindowDecorationBackgroundColor];
        const CGFloat perceivedBrightness = [color perceivedBrightness];
        const CGFloat target = perceivedBrightness < 0.5 ? 1 : 0;
        return [color colorDimmedBy:[iTermAdvancedSettingsModel minimalSplitPaneDividerProminence]
                   towardsGrayLevel:target];
    }
    switch ([self.window.effectiveAppearance it_tabStyle:preferredStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
            
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSColor lightGrayColor];
            break;
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [NSColor darkGrayColor];
            break;
    }
}

- (id<PSMTabStyle>)terminalWindowTabStyle {
    return _contentView.tabBarControl.style;
}

- (NSColor *)terminalWindowDecorationTextColorForBackgroundColor:(NSColor *)backgroundColor {
    return [[iTermTheme sharedInstance] terminalWindowDecorationTextColorForBackgroundColor:backgroundColor
                                                                        effectiveAppearance:self.window.effectiveAppearance
                                                                                   tabStyle:_contentView.tabBarControl.style
                                                                              mainAndActive:(self.window.isMainWindow && NSApp.isActive)];
}

- (BOOL)shouldUseMinimalStyle {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    return (preferredStyle == TAB_STYLE_MINIMAL);
}

- (BOOL)terminalWindowUseMinimalStyle {
    return self.shouldUseMinimalStyle;
}

- (PTYWindowTitleBarFlavor)ptyWindowTitleBarFlavor {
    if (self.lionFullScreen || togglingLionFullScreen_) {
        return PTYWindowTitleBarFlavorDefault;
    }
    switch (_windowType) {
        case WINDOW_TYPE_LION_FULL_SCREEN:
            // This shouldn't happen.
            return PTYWindowTitleBarFlavorDefault;

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            return PTYWindowTitleBarFlavorZeroPoints;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return PTYWindowTitleBarFlavorOnePoint;
    }

    assert(NO);
}

- (void)closeSession:(PTYSession *)aSession {
    [self closeSession:aSession soft:NO];
}

- (void)softCloseSession:(PTYSession *)aSession
{
    [self closeSession:aSession soft:YES];
}

- (iTermWindowType)windowType {
    return iTermThemedWindowType(_windowType);
}

- (iTermWindowType)savedWindowType {
    return iTermThemedWindowType(_savedWindowType);
}

- (void)setWindowType:(iTermWindowType)windowType {
    if (@available(macOS 10.14, *)) {
        _windowType = iTermThemedWindowType(windowType);
    } else if (iTermWindowTypeIsCompact(iTermThemedWindowType(windowType))) {
        // Requires layer support
        _windowType = WINDOW_TYPE_NO_TITLE_BAR;
    } else {
        // Normal 10.12, 10.13 code path
        _windowType = iTermThemedWindowType(windowType);
    }
}

- (BOOL)confirmCloseForSessions:(NSArray *)sessions
                     identifier:(NSString*)identifier
                    genericName:(NSString *)genericName
{
    NSMutableArray *names = [NSMutableArray array];
    for (PTYSession *aSession in sessions) {
        if (![aSession exited]) {
            [names addObjectsFromArray:[[aSession childJobNames] arrayByRemovingObject:@"login"]];
        }
    }
    NSString *message;
    NSArray *sortedNames = [names countedInstancesStrings];
    if ([sortedNames count] == 1) {
        message = [NSString stringWithFormat:@"%@ is running %@.", identifier, [sortedNames objectAtIndex:0]];
    } else if ([sortedNames count] > 1 && [sortedNames count] <= 10) {
        message = [NSString stringWithFormat:@"%@ is running the following jobs: %@.", identifier, [sortedNames componentsJoinedWithOxfordComma]];
    } else if ([sortedNames count] > 10) {
        message = [NSString stringWithFormat:@"%@ is running the following jobs: %@, plus %ld %@.",
                   identifier,
                   [sortedNames componentsJoinedWithOxfordComma],
                   (long)[sortedNames count] - 10,
                   [sortedNames count] == 11 ? @"other" : @"others"];
    } else {
        message = [NSString stringWithFormat:@"%@ will be closed.", identifier];
    }
    // The PseudoTerminal might close while the dialog is open so keep it around for now.
    [[self retain] autorelease];

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = [NSString stringWithFormat:@"Close %@?", genericName];
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runSheetModalForWindow:self.window] == NSAlertFirstButtonReturn;
}

- (BOOL)confirmCloseTab:(PTYTab *)aTab suppressConfirmation:(BOOL)suppressConfirmation {
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
    if (numClosing > 0 && [aTab promptOnCloseReason].hasReason) {
        mustAsk = YES;
    }
    if (numClosing > 1 &&
        [iTermPreferences boolForKey:kPreferenceKeyConfirmClosingMultipleTabs]) {
        mustAsk = YES;
    }

    if (mustAsk && !suppressConfirmation) {
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

- (IBAction)closeTerminalWindow:(id)sender {
    [self close];
}

- (void)performClose:(id)sender {
    [self close];
}

- (BOOL)tabIsAttachedTmuxTabWithSessions:(PTYTab *)aTab {
    return ([aTab isTmuxTab] &&
            [[aTab sessions] count] > 0 &&
            [[aTab tmuxController] isAttached]);
}

- (BOOL)willShowTmuxWarningWhenClosingTab:(PTYTab *)aTab {
    return ([self tabIsAttachedTmuxTabWithSessions:aTab] &&
            ![iTermWarning identifierIsSilenced:@"ClosingTmuxTabKillsTmuxWindows"]);
}

- (void)closeTab:(PTYTab *)aTab soft:(BOOL)soft {
    if (!soft &&
        [self tabIsAttachedTmuxTabWithSessions:aTab]) {
        iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:@"Kill tmux window, terminating its jobs, or hide it? "
                                               @"Hidden windows may be restored from the tmux dashboard."
                                       actions:@[ @"Hide", @"Cancel", @"Kill" ]
                                 actionMapping:@[ @(kiTermWarningSelection0), @(kiTermWarningSelection2), @(kiTermWarningSelection1)]
                                     accessory:nil
                                    identifier:@"ClosingTmuxTabKillsTmuxWindows"
                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                       heading:nil
                                        window:self.window];
        if (selection == kiTermWarningSelection1) {
            [[aTab tmuxController] killWindow:[aTab tmuxWindow]];
        } else if (selection == kiTermWarningSelection0) {
            [[aTab tmuxController] hideWindow:[aTab tmuxWindow]];
        }
        return;
    }
    [self removeTab:aTab];
}

- (void)closeTab:(PTYTab *)aTab {
    [self closeTab:aTab soft:NO];
}

- (iTermRestorableSession *)restorableSessionForSession:(PTYSession *)session {
    if (session.isTmuxClient) {
        return nil;
    }
    if ([[[self tabForSession:session] sessions] count] > 1) {
        return [session restorableSession];
    }
    if (self.numberOfTabs > 1) {
        return [self restorableSessionForTab:[self tabForSession:session]];
    }
    iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
    restorableSession.sessions = [self allSessions];
    restorableSession.terminalGuid = self.terminalGuid;
    restorableSession.arrangement = [self arrangement];
    restorableSession.group = kiTermRestorableSessionGroupWindow;
    [self storeWindowStateInRestorableSession:restorableSession];
    return restorableSession;
}

- (void)storeWindowStateInRestorableSession:(iTermRestorableSession *)restorableSession {
    restorableSession.windowType = self.lionFullScreen ? WINDOW_TYPE_LION_FULL_SCREEN : self.windowType;
    restorableSession.savedWindowType = self.savedWindowType;
    restorableSession.screen = _screenNumberFromFirstProfile;
}

- (iTermRestorableSession *)restorableSessionForTab:(PTYTab *)aTab {
    if (!aTab) {
        return nil;
    }

    iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
    restorableSession.sessions = [aTab sessions];
    restorableSession.terminalGuid = self.terminalGuid;
    restorableSession.tabUniqueId = aTab.uniqueId;
    NSArray *tabs = [self tabs];
    NSUInteger index = [tabs indexOfObject:aTab];
    NSMutableArray *predecessors = [NSMutableArray array];
    for (NSUInteger i = 0; i < index; i++) {
        [predecessors addObject:@([tabs[i] uniqueId])];
    }
    restorableSession.predecessors = predecessors;
    restorableSession.arrangement = [aTab arrangement];
    restorableSession.group = kiTermRestorableSessionGroupTab;
    [self storeWindowStateInRestorableSession:restorableSession];
    return restorableSession;
}

// Just like closeTab but skips the tmux code. Terminates sessions, removes the
// tab, and closes the window if there are no tabs left.
- (void)removeTab:(PTYTab *)aTab {
    if (![aTab isTmuxTab]) {
        iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
        restorableSession.sessions = [aTab sessions];
        restorableSession.terminalGuid = self.terminalGuid;
        restorableSession.tabUniqueId = aTab.uniqueId;
        [self storeWindowStateInRestorableSession:restorableSession];
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
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermTabDidCloseNotification
                                                            object:aTab];
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
        if (@available(macOS 10.14, *)) {
            [self updateTabBarControlIsTitlebarAccessoryAssumingFullScreen:(self.lionFullScreen || togglingLionFullScreen_)];
        }
        [_contentView.tabBarControl updateFlashing];
        [self repositionWidgets];
        [self fitTabsToWindow];
    }
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    DLog(@"Active space did change. active=%@ self.window.isOnActiveSpace=%@", @(NSApp.isActive), @(self.window.isOnActiveSpace));
    if ([(iTermApplication *)NSApp isUIElement] && !NSApp.isActive && self.lionFullScreen && self.window.isOnActiveSpace) {
        DLog(@"Activating app because lion full screen window is on active space. %@", self);
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)keyBindingsDidChange:(NSNotification *)notification {
    [self updateTouchBarIfNeeded:NO];
}

- (void)colorPresetsDidChange:(NSNotification *)notification {
    [self updateColorPresets];
}

- (IBAction)closeCurrentTab:(id)sender {
    PTYTab *tab = self.currentTab;
    [self closeTabIfConfirmed:tab];
}

- (BOOL)closeTabIfConfirmed:(PTYTab *)tab {
    const BOOL shouldClose = [self tabView:_contentView.tabView
                    shouldCloseTabViewItem:tab.tabViewItem
                      suppressConfirmation:[self willShowTmuxWarningWhenClosingTab:tab]];
    if (shouldClose) {
        [self closeTab:tab];
        return YES;
    } else {
        return NO;
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

- (BOOL)closeSessionWithConfirmation:(PTYSession *)aSession {
    PTYTab *tab = [self tabForSession:aSession];
    if ([[tab sessions] count] == 1) {
        return [self closeTabIfConfirmed:tab];
    }
    BOOL okToClose = NO;
    if ([aSession exited]) {
        okToClose = YES;
    } else if (![aSession promptOnCloseReason].hasReason) {
        okToClose = YES;
    } else {
      okToClose = [self confirmCloseForSessions:[NSArray arrayWithObject:aSession]
                                     identifier:@"This session"
                                    genericName:[NSString stringWithFormat:@"session \"%@\"",
                                                    [aSession name]]];
    }
    if (okToClose) {
        [self closeSessionWithoutConfirmation:aSession];
        return YES;
    }

    return NO;
}

- (void)closeSessionWithoutConfirmation:(PTYSession *)aSession {
    // Just in case IR is open, close it first.
    [self closeInstantReplay:self orTerminateSession:NO];
    [self closeSession:aSession];
}

- (IBAction)restartSession:(id)sender {
    [self restartSessionWithConfirmation:self.currentSession];
}

- (void)restartSessionWithConfirmation:(PTYSession *)aSession {
    assert(aSession.isRestartable);
    [[self retain] autorelease];
    if (aSession.exited) {
        [aSession restartSession];
    } else {
        iTermWarningAction *cancel = [iTermWarningAction warningActionWithLabel:@"Cancel" block:nil];
        iTermWarningAction *ok =
            [iTermWarningAction warningActionWithLabel:@"OK"
                                                 block:^(iTermWarningSelection selection) {
                                                     if (selection == kiTermWarningSelection0) {
                                                         [aSession restartSession];
                                                     }
                                                 }];
        iTermWarning *warning = [[[iTermWarning alloc] init] autorelease];
        warning.heading = @"Restart session?";
        warning.title = @"Running jobs will be killed.";
        warning.warningActions = @[ ok, cancel ];
        warning.identifier = @"NoSyncSuppressRestartSessionConfirmationAlert";
        warning.warningType = kiTermWarningTypePermanentlySilenceable;
        warning.window = self.window;
        [warning runModal];
    }
}

// For a million years macOS did not have tabs. So I made my own half-assed tabs.
// Then they finally got around to adding tabs and, even though this app opts out of their
// tabs (because they can't do half of what I need), they still add garbage disabled menu items to
// the window menu that conflict with longstanding shortcuts.
// I can't seem to prevent "Show Next/Previous Tab" from being added to the menu, and I already have
// the previously-standard shortcuts to switch tabs in the menu (as cmd-shift [ and ]) which I cannot
// change. So rather than have dead menu items I implement these methods to do what the default shortcut
// has always done. Of course this is different than the standard for macOS apps but I can't very
// well remove the existing menu items since people are used to their shortcuts; I don't want to
// remove them from the menu because people may have "perform menu item" keyboard shortcuts; and
// I certainly don't want dead menu items in my window menu. (╯°□°)╯︵ ┻━┻
- (IBAction)selectNextTab:(nullable id)sender {
    [[self tabView] cycleForwards:YES];
}

- (IBAction)selectPreviousTab:(nullable id)sender {
    [[self tabView] cycleForwards:NO];
}

// More magic cocoa poop.
- (IBAction)moveTabToNewWindow:(nullable id)sender {
    PTYTab *tab = [self currentTab];
    if (tab) {
        [self it_moveTabToNewWindow:tab];
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
        [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:hotKey url:nil];
    } else {
        [self.window makeKeyAndOrderFront:nil];
    }
    [_contentView.tabView selectTabViewItem:tab.tabViewItem];
    if (tab.activeSession != session) {
        [tab setActiveSessionPreservingMaximization:session];
    }
}

- (PTYSession *)currentSession {
    return [[[_contentView.tabView selectedTabViewItem] identifier] activeSession];
}

- (void)setWindowTitle {
    if (self.isShowingTransientTitle) {
        DLog(@"showing transient title");
        PTYSession *session = self.currentSession;
        NSString *aTitle;
        VT100GridSize size = VT100GridSizeMake(session.columns, session.rows);
        if (!_lockTransientTitle) {
            if (VT100GridSizeEquals(_previousGridSize, VT100GridSizeMake(0, 0))) {
                _previousGridSize = size;
                DLog(@"NOT showing transient title because of no previous grid sizes");
                [self setWindowTitle:[self undecoratedWindowTitle]];
                return;
            }
            if (VT100GridSizeEquals(size, _previousGridSize)) {
                DLog(@"NOT showing transient title because of equal grid sizes");
                [self setWindowTitle:[self undecoratedWindowTitle]];
                return;
            }
            _lockTransientTitle = YES;
        }
        _previousGridSize = size;
        DLog(@"showing transient title %@", @(self.timeOfLastResize));
        if (self.window.frame.size.width < 250) {
            aTitle = [NSString stringWithFormat:@"%d✕%d", session.columns, session.rows];
        } else {
            aTitle = [NSString stringWithFormat:@"%@ \u2014 %d✕%d",
                      [self undecoratedWindowTitle],
                      [session columns],
                      [session rows]];
        }
        [self setWindowTitle:aTitle];
    } else {
        _lockTransientTitle = NO;
        [self setWindowTitle:[self undecoratedWindowTitle]];
    }
}

- (void)setWindowTitle:(NSString *)title {
    DLog(@"setWindowTitle:%@", title);
    if (title == nil) {
        // title can be nil during loadWindowArrangement
        title = @"";
    }

    NSString *titleExWindowNumber = title;

    if ([iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber]) {
        NSString *tmuxId = @"";
        if ([[self currentSession] isTmuxClient]) {
            NSString *clientName = [[[self currentSession] tmuxController] clientName];
            if (clientName) {
                tmuxId = [NSString stringWithFormat:@" [%@]", clientName];
            }
        }
        NSString *windowNumber = @"";

        if (@available(macOS 10.14, *)) {
            if (!_shortcutAccessoryViewController ||
                !(self.window.styleMask & NSWindowStyleMaskTitled)) {
                windowNumber = [NSString stringWithFormat:@"%d. ", number_ + 1];
            }
        } else {
            if (self.window.styleMask & NSWindowStyleMaskTitled) {
                windowNumber = [NSString stringWithFormat:@"%d. ", number_ + 1];
            }
        }
        title = [NSString stringWithFormat:@"%@%@%@", windowNumber, title, tmuxId];
        titleExWindowNumber = [NSString stringWithFormat:@"%@%@", titleExWindowNumber, tmuxId];
        [self.contentView windowNumberDidChangeTo:@(number_ + 1)];
    } else {
        [self.contentView windowNumberDidChangeTo:nil];
    }
    if ((self.numberOfTabs == 1) && (self.tabs.firstObject.state & kPTYTabBellState) && !self.tabBarShouldBeVisible) {
        title = [title stringByAppendingString:@" 🔔"];
        titleExWindowNumber = [titleExWindowNumber stringByAppendingString:@" 🔔"];
    }
    if ((self.desiredTitle && [title isEqualToString:self.desiredTitle]) ||
        [title isEqualToString:self.window.title]) {
        return; // Title is already up to date
    }

    [self.contentView windowTitleDidChangeTo:titleExWindowNumber];

    if (liveResize_) {
        // During a live resize this has to be done immediately because the runloop doesn't get
        // around to delayed performs until the live resize is done (bug 2812).
        self.window.title = title;
        DLog(@"in a live resize");
        return;
    }
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
    DLog(@"After adjusting title, setWindowTitle:%@", title);
    if (!hadTimer) {
        if (!_windowWasJustCreated && ![self.ptyWindow titleChangedRecently]) {
            // Unless the window was just created, set the title immediately. Issue 5876.
            DLog(@"set title immediately to %@", self.desiredTitle);
            self.window.title = self.desiredTitle;
        }
        PseudoTerminal<iTermWeakReference> *weakSelf = self.weakSelf;
        DLog(@"schedule timer to set window title");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(iTermWindowTitleChangeMinimumInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!(weakSelf.window.title == weakSelf.desiredTitle || [weakSelf.window.title isEqualToString:weakSelf.desiredTitle])) {
                DLog(@"timer fired. Set title to %@", weakSelf.desiredTitle);
                weakSelf.window.title = weakSelf.desiredTitle;
            }
            weakSelf.desiredTitle = nil;
        });
    }
}

- (NSArray<PTYSession *> *)broadcastSessions {
    NSSet<NSString *> *guids = _broadcastInputHelper.broadcastSessionIDs;
    return [self.allSessions filteredArrayUsingBlock:^BOOL(PTYSession *session) {
        return [guids containsObject:session.guid];
    }];
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

- (BOOL)broadcastInputToSession:(PTYSession *)session {
    return [_broadcastInputHelper.broadcastSessionIDs containsObject:session.guid];
}

+ (iTermWindowType)_windowTypeForArrangement:(NSDictionary*)arrangement {
    int windowType;
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE]) {
        windowType = iTermThemedWindowType([[arrangement objectForKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE] intValue]);
    } else {
        if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_FULLSCREEN] &&
            [[arrangement objectForKey:TERMINAL_ARRANGEMENT_FULLSCREEN] boolValue]) {
            windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        } else if ([[arrangement objectForKey:TERMINAL_ARRANGEMENT_LION_FULLSCREEN] boolValue]) {
            windowType = WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            windowType = iTermWindowDefaultType();
        }
    }
    return windowType;
}

+ (int)_screenIndexForArrangement:(NSDictionary*)arrangement {
    return [[arrangement objectForKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX] intValue];
}

+ (void)drawArrangementPreview:(NSDictionary*)terminalArrangement
                  screenFrames:(NSArray *)frames
{
    int windowType = [PseudoTerminal _windowTypeForArrangement:terminalArrangement];
    int screenIndex = [PseudoTerminal _screenIndexForArrangement:terminalArrangement];
    if (screenIndex < 0 || screenIndex >= [[NSScreen screens] count]) {
        screenIndex = 0;
    }
    NSRect virtualScreenFrame = [[frames objectAtIndex:screenIndex] rectValue];
    NSRect screenFrame = [[[NSScreen screens] objectAtIndex:screenIndex] frame];
    double xScale = virtualScreenFrame.size.width / screenFrame.size.width;
    double yScale = virtualScreenFrame.size.height / screenFrame.size.height;
    double xOrigin = virtualScreenFrame.origin.x;
    double yOrigin = virtualScreenFrame.origin.y;

    NSRect rect = NSZeroRect;
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_MAXIMIZED:
            rect = virtualScreenFrame;
            break;

        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_COMPACT:
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
    iTermWindowType windowType = iTermThemedWindowType([PseudoTerminal _windowTypeForArrangement:arrangement]);
    int screenIndex = [PseudoTerminal _screenIndexForArrangement:arrangement];
    iTermProfileHotKey *profileHotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForGUID:guid];
    iTermHotkeyWindowType hotkeyWindowType = iTermHotkeyWindowTypeNone;
    if (isHotkeyWindow) {
        if (!profileHotKey) {
            return nil;
        }
        hotkeyWindowType = profileHotKey.hotkeyWindowType;
    }
    if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:WINDOW_TYPE_TRADITIONAL_FULL_SCREEN
                                            savedWindowType:[arrangement[TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE] intValue]
                                                     screen:screenIndex
                                           hotkeyWindowType:hotkeyWindowType
                                                    profile:arrangement[TERMINAL_ARRANGEMENT_INITIAL_PROFILE]] autorelease];

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
                                           hotkeyWindowType:hotkeyWindowType
                                                    profile:arrangement[TERMINAL_ARRANGEMENT_INITIAL_PROFILE]] autorelease];
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

                case WINDOW_TYPE_MAXIMIZED:
                case WINDOW_TYPE_COMPACT_MAXIMIZED:
                case WINDOW_TYPE_NORMAL:
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                case WINDOW_TYPE_LION_FULL_SCREEN:
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_LEFT_PARTIAL:
                case WINDOW_TYPE_RIGHT_PARTIAL:
                case WINDOW_TYPE_NO_TITLE_BAR:
                case WINDOW_TYPE_COMPACT:
                case WINDOW_TYPE_ACCESSORY:
                    break;
            }
        }
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:windowType
                                            savedWindowType:windowType
                                                     screen:screenIndex
                                           hotkeyWindowType:hotkeyWindowType
                                                    profile:arrangement[TERMINAL_ARRANGEMENT_INITIAL_PROFILE]] autorelease];

        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
        // TODO: for window type top, set width to screen width.
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
        DLog(@"Initialize nonfullscreen window to saved frame %@", NSStringFromRect(rect));
        rect = [self sanitizedWindowFrame:rect];
        [[term window] setFrame:rect display:NO];
    }

    if ([[arrangement objectForKey:TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING] boolValue]) {
        [term hideAfterOpening];
    }
    if (isHotkeyWindow) {
        BOOL ok = [[iTermHotKeyController sharedInstance] addRevivedHotkeyWindowController:term
                                                                        forProfileWithGUID:guid];
        if (ok) {
            term.window.alphaValue = 0;
            [[term window] orderOut:nil];
        }
    }
    return term;
}

+ (NSRect)sanitizedWindowFrame:(NSRect)frame {
    if (![iTermAdvancedSettingsModel restoreWindowsWithinScreens]) {
        return frame;
    }
    NSRect allowed = NSZeroRect;
    for (NSScreen *screen in [NSScreen screens]) {
        allowed = NSUnionRect(allowed, screen.frame);
    }

    NSRect intersected = NSIntersectionRect(frame, allowed);
    NSRect sanitized = frame;
    if (NSWidth(intersected) < NSWidth(frame)) {
        if (NSMinX(frame) < NSMinX(allowed)) {
            sanitized.origin.x = NSMinX(allowed);
        } else if (NSMaxX(frame) > NSMaxX(allowed)) {
            const CGFloat rightOverhang = NSMaxX(frame) - NSMaxX(allowed);
            const CGFloat leftSlop = NSMinX(frame) - NSMinX(allowed);
            sanitized.origin.x -= MIN(leftSlop, rightOverhang);
        }
    }

    if (NSHeight(intersected) < NSHeight(frame)) {
        if (NSMinY(frame) < NSMinY(allowed)) {
            sanitized.origin.y = NSMinY(allowed);
        } else if (NSMaxY(frame) > NSMaxY(allowed)) {
            const CGFloat topOverhang = NSMaxY(frame) - NSMaxY(allowed);
            const CGFloat bottomSlop = NSMinY(frame) - NSMinY(allowed);
            sanitized.origin.y -= MIN(topOverhang, bottomSlop);
        }
    }

    return sanitized;
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

- (iTermVariables *)variables {
    return _variables;
}

- (iTermVariableScope<iTermWindowScope> *)scope {
    return _scope;
}

- (IBAction)editWindowTitle:(id)sender {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Set Window Title";
    alert.informativeText = @"If this is empty, the window takes the active session’s title. Variables and function calls enclosed in \\(…) will be replaced with their evaluation.";
    NSTextField *titleTextField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24 * 3)] autorelease];
    iTermFunctionCallTextFieldDelegate *delegate;
    delegate = [[[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextWindow]
                                                                   passthrough:nil
                                                                 functionsOnly:NO] autorelease];
    titleTextField.delegate = delegate;
    titleTextField.editable = YES;
    titleTextField.selectable = YES;
    titleTextField.stringValue = [self.scope valueForVariableName:iTermVariableKeyWindowTitleOverrideFormat] ?: @"";
    alert.accessoryView = titleTextField;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [titleTextField.window makeFirstResponder:titleTextField];
    });
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self.scope setValue:titleTextField.stringValue.length ? titleTextField.stringValue : nil
            forVariableNamed:iTermVariableKeyWindowTitleOverrideFormat];
    }
}

- (IBAction)findUrls:(id)sender {
    iTermFindDriver *findDriver = self.currentSession.view.findDriver;
    NSString *regex = [iTermAdvancedSettingsModel findUrlsRegex];
    [findDriver closeViewAndDoTemporarySearchForString:regex
                                                  mode:iTermFindModeCaseSensitiveRegex];
}

- (IBAction)detachTmux:(id)sender {
    [[self currentTmuxController] requestDetach];
}

- (IBAction)forceDetachTmux:(id)sender {
    [self.currentSession forceTmuxDetach];
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
                                                   size:[PTYTab sizeForTmuxWindowWithAffinity:nil
                                                                                   controller:self.currentTmuxController]
                                       initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:self.currentSession.profile
                                                                                                objectType:iTermWindowObject]
                                                  scope:[iTermVariableScope globalsScope]
                                             completion:nil];
}

- (IBAction)newTmuxTab:(id)sender {
    int tmuxWindow = [[self currentTab] tmuxWindow];
    if (tmuxWindow < 0) {
        tmuxWindow = -(number_ + 1);
    }
    NSString *affinity = [NSString stringWithFormat:@"%d", tmuxWindow];
    [[self currentTmuxController] newWindowWithAffinity:affinity
                                                   size:[PTYTab sizeForTmuxWindowWithAffinity:affinity
                                                                                   controller:self.currentTmuxController]
                                       initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:self.currentSession.profile
                                                                                                objectType:iTermTabObject]
                                                  scope:[iTermVariableScope globalsScope]
                                             completion:nil];
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

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement replacingProfileWithGUID:(NSString *)badGuid withProfile:(Profile *)goodProfile {
    NSMutableDictionary *mutableArrangement = [[arrangement mutableCopy] autorelease];
    NSMutableArray *mutableTabs = [NSMutableArray array];

    for (NSDictionary* tabArrangement in [arrangement objectForKey:TERMINAL_ARRANGEMENT_TABS]) {
        [mutableTabs addObject:[PTYTab repairedArrangement:tabArrangement replacingProfileWithGUID:badGuid withProfile:(Profile *)goodProfile]];
    }
    mutableArrangement[TERMINAL_ARRANGEMENT_TABS] = mutableTabs;
    return mutableArrangement;
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
    iTermWindowType windowType = iTermThemedWindowType([PseudoTerminal _windowTypeForArrangement:arrangement]);
    NSRect rect;
    rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
    rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
    rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
    rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];

    // TODO: The anchored screen isn't always respected, e.g., if the screen's origin/size changes
    // then rect might not lie inside it.
    if (windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        NSArray *screens = [NSScreen screens];
        if (_anchoredScreenNumber >= 0 && _anchoredScreenNumber < screens.count) {
            NSScreen *screen = screens[_anchoredScreenNumber];
            rect = [self traditionalFullScreenFrameForScreen:screen];
        }
    }

    // 10.11 starts you off with a tiny little frame. I don't know why they do
    // that, but this fixes it.
    if (windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        [[self window] setFrame:rect display:YES];
    }

    const BOOL savedRestoringWindow = _restoringWindow;
    _restoringWindow = YES;
    _suppressMakeCurrentTerminal = (self.hotkeyWindowType != iTermHotkeyWindowTypeNone);
    const BOOL restoreTabsOK = [self restoreTabsFromArrangement:arrangement sessions:sessions];
    _suppressMakeCurrentTerminal = NO;
    _restoringWindow = savedRestoringWindow;
    if (!restoreTabsOK) {
        return NO;
    }
    if (arrangement[TERMINAL_ARRANGEMENT_USE_TRANSPARENCY]) {
        useTransparency_ = [arrangement[TERMINAL_ARRANGEMENT_USE_TRANSPARENCY] boolValue];
    }
    self.scope.windowTitleOverrideFormat = arrangement[TERMINAL_ARRANGEMENT_TITLE_OVERRIDE];

    _contentView.shouldShowToolbelt = [arrangement[TERMINAL_ARRANGEMENT_HAS_TOOLBELT] boolValue];
    [_contentView constrainToolbeltWidth];
    [_contentView setToolbeltProportions:arrangement[TERMINAL_ARRANGEMENT_TOOLBELT_PROPORTIONS]];
    [_contentView.toolbelt restoreFromState:arrangement[TERMINAL_ARRANGEMENT_TOOLBELT]];

    hidingToolbeltShouldResizeWindow_ = [arrangement[TERMINAL_ARRANGEMENT_HIDING_TOOLBELT_SHOULD_RESIZE_WINDOW] boolValue];
    hidingToolbeltShouldResizeWindowInitialized_ = YES;

    if (windowType == WINDOW_TYPE_NORMAL ||
        windowType == WINDOW_TYPE_ACCESSORY ||
        windowType == WINDOW_TYPE_NO_TITLE_BAR ||
        windowType == WINDOW_TYPE_COMPACT) {
        // The window may have changed size while adding tab bars, etc.
        // TODO: for window type top, set width to screen width.
        [[self window] setFrame:[PseudoTerminal sanitizedWindowFrame:rect]
                        display:YES];
    }

    const int tabIndex = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX] intValue];
    if (tabIndex >= 0 && tabIndex < [_contentView.tabView numberOfTabViewItems]) {
        [_contentView.tabView selectTabViewItemAtIndex:tabIndex];
    }

    Profile* addressbookEntry = [[[[[self tabs] objectAtIndex:0] sessions] objectAtIndex:0] profile];
    _spaceSetting = [addressbookEntry[KEY_SPACE] intValue];
    switch ([addressbookEntry[KEY_SPACE] intValue]) {
        case iTermProfileJoinsAllSpaces:
            self.window.collectionBehavior = [self desiredWindowCollectionBehavior];
        case iTermProfileOpenInCurrentSpace:
            break;
    }
    if ([arrangement objectForKey:TERMINAL_GUID] &&
        [[arrangement objectForKey:TERMINAL_GUID] isKindOfClass:[NSString class]]) {
        NSString *savedGUID = [arrangement objectForKey:TERMINAL_GUID];
        if ([[iTermController sharedInstance] terminalWithGuid:savedGUID] || ![self stringIsValidTerminalGuid:savedGUID]) {
            // Refuse to create a window with an already-used or invalid guid.
            self.terminalGuid = [NSString stringWithFormat:@"pty-%@", [NSString uuid]];
        } else {
            self.terminalGuid = savedGUID;
        }
    }

    [self fitTabsToWindow];

    // Sessions were created at the wrong size, which means they might not have been able to position
    // their cursors where they needed to be. Move the cursors to their rightful places. See the
    // comment where preferredCursorPosition is set for more details.
    for (PTYSession *session in self.allSessions) {
        DLog(@"restore preferred cursor position for %@", session);
        [session.screen.currentGrid restorePreferredCursorPositionIfPossible];
    }
    [_contentView updateToolbeltForWindow:self.window];
    return YES;
}

- (BOOL)stringIsValidTerminalGuid:(NSString *)string {
    NSCharacterSet *characterSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    return [string rangeOfCharacterFromSet:characterSet.invertedSet].location == NSNotFound;
}

- (BOOL)restoreTabsFromArrangement:(NSDictionary *)arrangement sessions:(NSArray<PTYSession *> *)sessions {
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
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
    [self updateUseTransparency];
    return YES;
}

- (NSDictionary *)arrangementExcludingTmuxTabs:(BOOL)excludeTmux
                             includingContents:(BOOL)includeContents {
    NSArray<PTYTab *> *tabs = [self.tabs filteredArrayUsingBlock:^BOOL(PTYTab *theTab) {
        if (theTab.sessions.count == 0) {
            return NO;
        }
        if (excludeTmux && theTab.isTmuxTab) {
            return NO;
        }
        return YES;
    }];

    return [self arrangementWithTabs:tabs includingContents:includeContents];
}

- (Profile *)expurgatedInitialProfile {
    return [PseudoTerminal expurgatedInitialProfile:_initialProfile];
}

- (NSDictionary *)arrangementWithTabs:(NSArray<PTYTab *> *)tabs
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

    [result setObject:self.terminalGuid forKey:TERMINAL_GUID];

    // Save window frame
    result[TERMINAL_ARRANGEMENT_X_ORIGIN] = @(rect.origin.x);
    result[TERMINAL_ARRANGEMENT_Y_ORIGIN] = @(rect.origin.y);
    result[TERMINAL_ARRANGEMENT_WIDTH] = @(rect.size.width);
    result[TERMINAL_ARRANGEMENT_HEIGHT] = @(rect.size.height);

    result[TERMINAL_ARRANGEMENT_USE_TRANSPARENCY] = @(useTransparency_);

    DLog(@"While creating arrangement for %@ save frame of %@", self, NSStringFromRect(rect));
    DLog(@"%@", [NSThread callStackSymbols]);
    result[TERMINAL_ARRANGEMENT_HAS_TOOLBELT] = @(_contentView.shouldShowToolbelt);
    NSDictionary *proportions = _contentView.toolbelt.proportions;
    if (proportions) {
        result[TERMINAL_ARRANGEMENT_TOOLBELT_PROPORTIONS] = proportions;
    }
    result[TERMINAL_ARRANGEMENT_TOOLBELT] = _contentView.toolbelt.restorableState;
    
    if (self.scope.windowTitleOverrideFormat) {
        result[TERMINAL_ARRANGEMENT_TITLE_OVERRIDE] = self.scope.windowTitleOverrideFormat;
    }
    result[TERMINAL_ARRANGEMENT_HIDING_TOOLBELT_SHOULD_RESIZE_WINDOW] =
            @(hidingToolbeltShouldResizeWindow_);

    if ([self anyFullScreen]) {
        // Save old window frame
        result[TERMINAL_ARRANGEMENT_OLD_X_ORIGIN] = @(oldFrame_.origin.x);
        result[TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN] = @(oldFrame_.origin.y);
        result[TERMINAL_ARRANGEMENT_OLD_WIDTH] = @(oldFrame_.size.width);
        result[TERMINAL_ARRANGEMENT_OLD_HEIGHT] = @(oldFrame_.size.height);
    }

    result[TERMINAL_ARRANGEMENT_WINDOW_TYPE] = @([self lionFullScreen] ? WINDOW_TYPE_LION_FULL_SCREEN : self.windowType);
    result[TERMINAL_ARRANGEMENT_SAVED_WINDOW_TYPE] = @(self.savedWindowType);
    result[TERMINAL_ARRANGEMENT_INITIAL_PROFILE] = [self expurgatedInitialProfile];
    if (_hotkeyWindowType == iTermHotkeyWindowTypeNone) {
        result[TERMINAL_ARRANGEMENT_SCREEN_INDEX] = @([[NSScreen screens] indexOfObjectIdenticalTo:[[self window] screen]]);
    } else {
        result[TERMINAL_ARRANGEMENT_SCREEN_INDEX] = @(_screenNumberFromFirstProfile);
    }
    result[TERMINAL_ARRANGEMENT_DESIRED_ROWS] = @(desiredRows_);
    result[TERMINAL_ARRANGEMENT_DESIRED_COLUMNS] = @(desiredColumns_);

    // Save tabs.
    if ([tabs count] == 0) {
        return nil;
    }
    result[TERMINAL_ARRANGEMENT_TABS] = [tabs mapWithBlock:^id(PTYTab *theTab) {
        return [theTab arrangementWithContents:includeContents];
    }];

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
- (void)windowDidDeminiaturize:(NSNotification *)aNotification {
    DLog(@"windowDidDeminiaturize: %@\n%@", self, [NSThread callStackSymbols]);
    [self.window.dockTile setBadgeLabel:@""];
    [self.window.dockTile setShowsApplicationBadge:NO];
    if ([[self currentTab] blur]) {
        [self enableBlur:[[self currentTab] blurRadius]];
    } else {
        [self disableBlur];
    }
    if (_constrainFrameAfterDeminiaturization) {
        _constrainFrameAfterDeminiaturization = NO;
        NSRect frame = [self.window constrainFrameRect:self.window.frame toScreen:self.window.screen];
        [self.window setFrame:frame display:YES animate:NO];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidDeminiaturize"
                                                        object:self
                                                      userInfo:nil];
}

- (iTermPromptOnCloseReason *)promptOnCloseReason {
    iTermPromptOnCloseReason *reason = [iTermPromptOnCloseReason noReason];
    for (PTYSession *aSession in [self allSessions]) {
        [reason addReason:[aSession promptOnCloseReason]];
    }
    return reason;
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
    // This counts as an interaction because it is only called when the user initiates the closing of the window (as opposed to a session dying on you).
    iTermApplicationDelegate *appDelegate = [iTermApplication.sharedApplication delegate];
    [appDelegate userDidInteractWithASession];

    BOOL needPrompt = NO;
    if ([self promptOnCloseReason].hasReason) {
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
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                            window:self.window];
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
        [self storeWindowStateInRestorableSession:restorableSession];
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

    [[NSNotificationCenter defaultCenter] postNotificationName:iTermWindowDidCloseNotification
                                                        object:nil
                                                      userInfo:nil];
    [self didFinishFullScreenTransitionSuccessfully:NO];
    _willClose = YES;
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification {
    DLog(@"windowWillMiniaturize: %@\n%@", self, [NSThread callStackSymbols]);
    [self disableBlur];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowWillMiniaturize"
                                                        object:self
                                                      userInfo:nil];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification {
    DLog(@"windowDidBecomeKey:%@ window=%@ stack:\n%@",
         aNotification, self.window, [NSThread callStackSymbols]);

    if ([NSApp isActive]) {
        _hasBeenKeySinceActivation = YES;
    }

    [iTermQuickLookController dismissSharedPanel];
    if (@available(macOS 10.14, *)) {
        _shortcutAccessoryViewController.isMain = YES;
    }
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
    [_contentView setNeedsDisplay:YES];
    [self _loadFindStringFromSharedPasteboard];

    // Start the timers back up
    for (PTYSession* aSession in [self allSessions]) {
        [aSession updateDisplayBecause:@"windowDidBecomeKey"];
        [[aSession view] setBackgroundDimmed:NO];
        [aSession setFocused:aSession == [self currentSession]];
        [aSession.view setNeedsDisplay:YES];
    }
    // Some users report that the first responder isn't always set properly. Let's try to fix that.
    // This attempt (4/20/13) is to fix bug 2431.
    [self performSelector:@selector(makeCurrentSessionFirstResponder)
               withObject:nil
               afterDelay:0];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded] && ![iTermAdvancedSettingsModel pinEditSession]) {
        [self editSession:self.currentSession makeKey:NO];
    }
    [self notifyTmuxOfTabChange];

    if ([iTermAdvancedSettingsModel clearBellIconAggressively]) {
        [self.currentSession setBell:NO];
    }
    [self updateUseMetalInAllTabs];
    [_contentView updateDivisionViewAndWindowNumberLabel];
    [self.currentSession.view.findDriver owningViewDidBecomeFirstResponder];
}

- (void)makeCurrentSessionFirstResponder
{
    if ([self currentSession]) {
        PtyLog(@"makeCurrentSessionFirstResponder. New first responder will be %@. The current first responder is %@",
               [[self currentSession] textview], [[self window] firstResponder]);
        [[self window] makeFirstResponder:[[self currentSession] textview]];
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionBecameKey
                                                            object:[self currentSession]
                                                          userInfo:nil];
    } else {
        PtyLog(@"There is no current session to make the first responder");
    }
}

// Forbid FFM from changing key window when the key window is an auto-hiding hotkey window.
- (BOOL)disableFocusFollowsMouse {
    if (!self.isHotKeyWindow) {
        return NO;
    }
    return [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] autoHides];
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
    PtyLog(@"canonicalizeWindowFrame %@\n%@", self, [NSThread callStackSymbols]);
    // It's important that this method respect the current screen if possible because
    // -windowDidChangeScreen calls it.

    NSScreen *screen = [[self window] screen];
    if (!screen) {
        screen = self.screen;
        if (!screen) {
            // Headless
            return;
        }
    }
    switch (self.windowType) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
            if ([self updateSessionScrollbars]) {
                PtyLog(@"Fitting tabs to window because scrollbars changed.");
                [self fitTabsToWindow];
            }
            break;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL: {
            NSRect desiredWindowFrame = [self canonicalFrameForScreen:screen];
            if (desiredWindowFrame.size.width > 0 && desiredWindowFrame.size.height > 0) {
                [[self window] setFrame:desiredWindowFrame display:YES];
            }
            break;
        }

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN: {
            if ([screen frame].size.width > 0) {
                // This is necessary when restoring a traditional fullscreen window while scrollbars are
                // forced on systemwide.
                BOOL changedScrollBars = [self updateSessionScrollbars];
                NSRect originalFrame = self.window.frame;
                PtyLog(@"set window to screen's frame");

                [[self window] setFrame:[self canonicalFrameForScreen:screen] display:YES];

                if (changedScrollBars && NSEqualSizes(self.window.frame.size, originalFrame.size)) {
                    DLog(@"Fitting tabs to window when canonicalizing fullscreen window because of scrollbar change");
                    [self fitTabsToWindow];
                    if (!tmuxOriginatedResizeInProgress_) {
                        // When opening a new tmux tab in a fullscreen window, it'll be initialized
                        // with legacy scrollers (if the system is configured to use them) and then
                        // it needs to update its size when the scrollers are forced to be inline.
                        for (TmuxController *controller in self.uniqueTmuxControllers) {
                            if (controller.variableWindowSize) {
                                NSArray<NSString *> *windows = [self.tabs mapWithBlock:^id(PTYTab *anObject) {
                                    if (!anObject.tmuxTab) {
                                        return nil;
                                    }
                                    if (anObject.tmuxController != controller) {
                                        return nil;
                                    }
                                    return [NSString stringWithInt:anObject.tmuxWindow];
                                }];
                                if (windows.count > 0) {
                                    DLog(@"Calling window did resize because canonicalizing a full screen window, scrollbar style changed, and variable size tmux windows is enabled");
                                    [controller windowDidResize:self];
                                }
                            } else {
                                [controller setClientSize:self.tmuxCompatibleSize];
                            }
                        }
                    }
                }
            }
        }
    }

    [_contentView updateToolbeltFrameForWindow:self.window];
}

- (NSRect)canonicalFrameForScreen:(NSScreen *)screen {
    return [self canonicalFrameForScreen:screen windowFrame:self.window.frame preserveSize:NO];
}

- (NSRect)screenFrameForEdgeSpanningWindows:(NSScreen *)screen {
    if ([[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] floats]) {
        const BOOL menuBarIsHidden = ![[iTermMenuBarObserver sharedInstance] menuBarVisibleOnScreen:screen];
        if (menuBarIsHidden) {
            return screen.frame;
        }
        return screen.frameExceptMenuBar;
    } else {
        return [screen visibleFrameIgnoringHiddenDock];
    }
}

- (NSRect)visibleFrameForScreen:(NSScreen *)screen {
    if ([[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] floats]) {
        DLog(@"visibleFrameForScreen: floating hotkey window gets frameExceptMenuBar");
        const BOOL menuBarIsHidden = ![[iTermMenuBarObserver sharedInstance] menuBarVisibleOnScreen:screen];
        if (menuBarIsHidden) {
            return screen.frame;
        }
        return screen.frameExceptMenuBar;
    }

    if (self.fullScreen) {
        DLog(@"visibleFrameForScreen: fullScreen gets visibleFrame %@", NSStringFromRect(screen.visibleFrame));
        return screen.visibleFrame;
    }

    BOOL otherScreenHasLionFullscreenTerminalWindow = NO;
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        if (term.lionFullScreen && term.window.isOnActiveSpace) {
            if (term.window.screen == screen) {
                return screen.frame;
            } else {
                otherScreenHasLionFullscreenTerminalWindow = YES;
            }
        }
    }
    if (otherScreenHasLionFullscreenTerminalWindow) {
        DLog(@"visibleFrameForScreen: otherScreenHasLionFullscreenTerminalWindow gets frameExceptMenuBar");
        return screen.frameExceptMenuBar;
    } else {
        DLog(@"visibleFrameForScreen: !otherScreenHasLionFullscreenTerminalWindow gets visibleFrame %@", NSStringFromRect(screen.visibleFrame));
        return screen.visibleFrame;
    }
}

- (NSRect)canonicalFrameForScreen:(NSScreen *)screen windowFrame:(NSRect)frame preserveSize:(BOOL)preserveSize {
    PTYSession* session = [self currentSession];
    NSRect screenVisibleFrame = [self visibleFrameForScreen:screen];
    DLog(@"screenVisibleFrame is %@", NSStringFromRect(screenVisibleFrame));
    NSRect screenVisibleFrameIgnoringHiddenDock = [self screenFrameForEdgeSpanningWindows:screen];

    PtyLog(@"The new screen visible frame is %@", [NSValue valueWithRect:screenVisibleFrame]);

    // NOTE: In bug 1347, we see that for some machines, [screen frame].size.width==0 at some point
    // during sleep/wake from sleep. That is why we check that width is positive before setting the
    // window's frame.
    NSSize decorationSize = [self windowDecorationSize];

    // Note: During window state restoration, this may be called before the tabs are created from
    // the arrangement, in which case the line height and char width will be 0.
    if (self.tabs.count == 0) {
        DLog(@"Window has no tabs. Returning early.");
        return self.window.frame;
    }
    PtyLog(@"Decoration size is %@", [NSValue valueWithSize:decorationSize]);
    PtyLog(@"Line height is %f, char width is %f", (float) [[session textview] lineHeight], [[session textview] charWidth]);
    if (session.textview.lineHeight == 0 || session.textview.charWidth == 0) {
        DLog(@"Line height or char width is 0. Returning existing frame. session=%@", session);
        return self.window.frame;
    }
    BOOL edgeSpanning = YES;
    switch (self.windowType) {
        case WINDOW_TYPE_TOP_PARTIAL:
            edgeSpanning = NO;
            // Fall through
        case WINDOW_TYPE_TOP:
            PtyLog(@"Window type = TOP, desired rows=%d", desiredRows_);
            if (!preserveSize) {
                // If the screen grew and the window was smaller than the desired number of rows, grow it.
                if (desiredRows_ > 0) {
                    frame.size.height = MIN(screenVisibleFrame.size.height,
                                            ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * [iTermAdvancedSettingsModel terminalVMargin]);
                } else {
                    frame.size.height = MIN(screenVisibleFrame.size.height, frame.size.height);
                }
            }
            if (!edgeSpanning) {
                if (!preserveSize) {
                    frame.size.width = MIN(frame.size.width, screenVisibleFrameIgnoringHiddenDock.size.width);
                }
                frame = iTermRectCenteredHorizontallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock);
            } else {
                frame.size.width = screenVisibleFrameIgnoringHiddenDock.size.width;
                frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;
            }
            frame.origin.y = screenVisibleFrame.origin.y + screenVisibleFrame.size.height - frame.size.height;
            DLog(@"Canonical frame for top of screen window is %@", NSStringFromRect(frame));
            return frame;
            break;

        case WINDOW_TYPE_BOTTOM_PARTIAL:
            edgeSpanning = NO;
        case WINDOW_TYPE_BOTTOM:
            PtyLog(@"Window type = BOTTOM, desired rows=%d", desiredRows_);
            if (!preserveSize) {
                // If the screen grew and the window was smaller than the desired number of rows, grow it.
                if (desiredRows_ > 0) {
                    frame.size.height = MIN(screenVisibleFrame.size.height,
                                            ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * [iTermAdvancedSettingsModel terminalVMargin]);
                } else {
                    frame.size.height = MIN(screenVisibleFrame.size.height, frame.size.height);
                }
            }
            if (!edgeSpanning) {
                if (!preserveSize) {
                    frame.size.width = MIN(frame.size.width, screenVisibleFrameIgnoringHiddenDock.size.width);
                }
                frame = iTermRectCenteredHorizontallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock);
            } else {
                frame.size.width = screenVisibleFrameIgnoringHiddenDock.size.width;
                frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;
            }
            frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;

            if (frame.size.width > 0) {
                return frame;
            }
            break;

        case WINDOW_TYPE_LEFT_PARTIAL:
            edgeSpanning = NO;
            // Fall through
        case WINDOW_TYPE_LEFT:
            PtyLog(@"Window type = LEFT, desired cols=%d", desiredColumns_);
            if (!preserveSize) {
                // If the screen grew and the window was smaller than the desired number of columns, grow it.
                if (desiredColumns_ > 0) {
                    frame.size.width = MIN(screenVisibleFrame.size.width,
                                           [[session textview] charWidth] * desiredColumns_ + 2 * [iTermAdvancedSettingsModel terminalMargin]);
                } else {
                    frame.size.width = MIN(screenVisibleFrame.size.width, frame.size.width);
                }
            }
            if (!edgeSpanning) {
                if (!preserveSize) {
                    frame.size.height = MIN(frame.size.height, screenVisibleFrameIgnoringHiddenDock.size.height);
                }
                frame = iTermRectCenteredVerticallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock);
            } else {
                frame.size.height = screenVisibleFrameIgnoringHiddenDock.size.height;
                frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;
            }
            frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x;

            return frame;

        case WINDOW_TYPE_RIGHT_PARTIAL:
            edgeSpanning = NO;
            // Fall through
        case WINDOW_TYPE_RIGHT:
            PtyLog(@"Window type = RIGHT, desired cols=%d", desiredColumns_);
            if (!preserveSize) {
                // If the screen grew and the window was smaller than the desired number of columns, grow it.
                if (desiredColumns_ > 0) {
                    frame.size.width = MIN(screenVisibleFrame.size.width,
                                           [[session textview] charWidth] * desiredColumns_ + 2 * [iTermAdvancedSettingsModel terminalMargin]);
                } else {
                    frame.size.width = MIN(screenVisibleFrame.size.width, frame.size.width);
                }
            }
            if (!edgeSpanning) {
                if (!preserveSize) {
                    frame.size.height = MIN(frame.size.height, screenVisibleFrameIgnoringHiddenDock.size.height);
                }
                frame = iTermRectCenteredVerticallyWithinRect(frame, screenVisibleFrameIgnoringHiddenDock);
            } else {
                frame.size.height = screenVisibleFrameIgnoringHiddenDock.size.height;
                frame.origin.y = screenVisibleFrameIgnoringHiddenDock.origin.y;
            }
            frame.origin.x = screenVisibleFrameIgnoringHiddenDock.origin.x + screenVisibleFrameIgnoringHiddenDock.size.width - frame.size.width;

            return frame;
            break;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            PtyLog(@"Window type = MAXIMIZED or COMPACT_MAXIMIZED");
            return [screen visibleFrameIgnoringHiddenDock];
 
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_ACCESSORY:
            PtyLog(@"Window type = NORMAL, NO_TITLE_BAR, WINDOW_TYPE_COMPACT, WINDOW_TYPE_ACCSSORY, or LION_FULL_SCREEN");
            return frame;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            PtyLog(@"Window type = FULL SCREEN");
            if ([screen frame].size.width > 0) {
                return [self traditionalFullScreenFrameForScreen:screen];
            } else {
                return NSZeroRect;
            }
    }
    return NSZeroRect;
}

- (void)screenParametersDidChange
{
    PtyLog(@"Screen parameters changed.");
    [self canonicalizeWindowFrame];
}

- (void)windowOcclusionDidChange:(NSNotification *)notification {
    [self updateUseMetalInAllTabs];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _hasBeenKeySinceActivation = [self.window isKeyWindow];
}

- (void)windowDidResignKey:(NSNotification *)aNotification {
    PtyLog(@"PseudoTerminal windowDidResignKey");
    if (_openingPopupWindow) {
        DLog(@"Ignoring it because we're opening a popup window now");
        return;
    }

    for (PTYSession *aSession in [self allSessions]) {
        if ([[aSession textview] isFindingCursor]) {
            [[aSession textview] endFindCursor];
        }
        [[aSession textview] removeUnderline];
        [aSession.view setNeedsDisplay:YES];
    }

    if (togglingFullScreen_) {
        PtyLog(@"windowDidResignKey returning because togglingFullScreen.");
        return;
    }

    BOOL shouldAutoHideHotkeyWindow = YES;
    if (self.ptyWindow.it_openingSheet) {
        shouldAutoHideHotkeyWindow = NO;
        DLog(@"windowDidResignKey not auto-hiding hotkey window because a sheet is being opened.");
    }
    if ([iTermApplication sharedApplication].it_characterPanelIsOpen) {
        shouldAutoHideHotkeyWindow = NO;
        DLog(@"windowDidResignKey not auto-hiding hotkey window because the character panel is open.");
    }

    NSWindow *newKeyWindow = [NSApp keyWindow] ?: [[iTermApplication sharedApplication] it_windowBecomingKey];
    DLog(@"Window %@ resiging key. New key window (or key-window-elect) is %@", self, newKeyWindow);
    if (shouldAutoHideHotkeyWindow) {
        NSArray<NSWindowController *> *siblings = [[iTermHotKeyController sharedInstance] siblingWindowControllersOf:self];
        NSWindowController *newKeyWindowController = [newKeyWindow windowController];
        if (![siblings containsObject:newKeyWindowController]) {
            [[iTermHotKeyController sharedInstance] autoHideHotKeyWindows:siblings];
        }
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
    [_contentView setNeedsDisplay:YES];

    // Note that if you have multiple displays you can see a lion fullscreen window when it's
    // not key.
    for (PTYSession* aSession in [self allSessions]) {
        [[aSession view] setBackgroundDimmed:YES];
    }

    for (PTYSession* aSession in [self allSessions]) {
        [aSession setFocused:NO];
    }

    [self updateUseMetalInAllTabs];
    [_contentView updateDivisionViewAndWindowNumberLabel];
}

- (void)windowDidBecomeMain:(NSNotification *)notification {
    if (@available(macOS 10.14, *)) {
        _shortcutAccessoryViewController.isMain = YES;
    }
    [_contentView updateDivisionViewAndWindowNumberLabel];
}

- (void)windowDidResignMain:(NSNotification *)aNotification {
    if (@available(macOS 10.14, *)) {
        _shortcutAccessoryViewController.isMain = NO;
    }
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignMain:%@]",
          __FILE__, __LINE__, aNotification);
    if (![iTermApplication sharedApplication].it_characterPanelIsOpen) {
        NSArray<NSWindowController *> *siblings = [[iTermHotKeyController sharedInstance] siblingWindowControllersOf:self];
        NSWindowController *newMainWindowController = [[NSApp mainWindow] windowController];
        if (![siblings containsObject:newMainWindowController]) {
            [[iTermHotKeyController sharedInstance] autoHideHotKeyWindows:siblings];
        }
    }

    // update the cursor
    [[[self currentSession] textview] refresh];
    [[[self currentSession] textview] setNeedsDisplay:YES];
    [_contentView updateDivisionViewAndWindowNumberLabel];
}

- (BOOL)isEdgeWindow
{
    switch (self.windowType) {
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return YES;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return NO;
    }
}

- (BOOL)movesWhenDraggedOntoSelf {
    switch (self.windowType) {
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return NO;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return YES;
    }

    return YES;
}

- (BOOL)enableStoplightHotbox {
    if (!iTermWindowTypeIsCompact(self.windowType)) {
        return NO;
    }
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_BottomTab:
            return YES;
        case PSMTab_TopTab:
            return NO;
        case PSMTab_LeftTab:
            return !self.tabBarShouldBeVisible;
    }

    return NO;
}

- (NSEdgeInsets)tabBarInsets {
    if (@available(macOS 10.14, *)) {
        iTermWindowType effectiveWindowType = self.windowType;
        if (exitingLionFullscreen_) {
            effectiveWindowType = self.savedWindowType;
        }
        if (!iTermWindowTypeIsCompact(effectiveWindowType)) {
            return NSEdgeInsetsZero;
        }
        if (!exitingLionFullscreen_) {
            if (self.anyFullScreen || togglingLionFullScreen_) {
                return NSEdgeInsetsZero;
            }
        }
        return [self tabBarInsetsForCompactWindow];
    }
    // 10.13 and earlier - no compact mode so this is always 0.
    return NSEdgeInsetsZero;
}

- (NSEdgeInsets)tabBarInsetsForCompactWindow NS_AVAILABLE_MAC(10_14) {
    const CGFloat stoplightButtonsWidth = 75;
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_TopTab:
            if ([self rootTerminalViewWindowNumberLabelShouldBeVisible]) {
                const CGFloat leftInset = (stoplightButtonsWidth +
                                           iTermRootTerminalViewWindowNumberLabelMargin * 2 +
                                           iTermRootTerminalViewWindowNumberLabelWidth +
                                           MAX(0, [iTermAdvancedSettingsModel extraSpaceBeforeCompactTopTabBar]));
                return NSEdgeInsetsMake(0,
                                        leftInset,
                                        0,
                                        0);
            } else {
                // Make room for stoplight buttons when there is no tab title.
                return NSEdgeInsetsMake(0, stoplightButtonsWidth, 0, 0);
            }

        case PSMTab_LeftTab:
            return NSEdgeInsetsMake(24, 0, 0, 0);

        case PSMTab_BottomTab:
            return NSEdgeInsetsZero;
    }
    assert(false);
    return NSEdgeInsetsZero;
}

- (BOOL)tabBarAlwaysVisible {
    return ![iTermPreferences boolForKey:kPreferenceKeyHideTabBar];
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
    DLog(@"windowWillResize: self=%@, proposedFrameSize=%@ screen=%@",
           self, NSStringFromSize(proposedFrameSize), self.window.screen);
    DLog(@"%@", [NSThread callStackSymbols]);
    if (self.togglingLionFullScreen || self.lionFullScreen || self.window.screen == nil) {
        DLog(@"Accepting proposal");
        return proposedFrameSize;
    }
    if (self.windowType == WINDOW_TYPE_MAXIMIZED || self.windowType == WINDOW_TYPE_COMPACT_MAXIMIZED) {
        DLog( @"Blocking resize" );
        return self.window.screen.visibleFrameIgnoringHiddenDock.size;
    }
    NSSize originalProposal = proposedFrameSize;
    // Find the session for the current pane of the current tab.
    PTYTab* tab = [self currentTab];
    PTYSession* session = [tab activeSession];

    // Get the width and height of characters in this session.
    float charWidth = [[session textview] charWidth];
    float charHeight = [[session textview] lineHeight];

    // Decide when to snap.  (We snap unless control, and only control, is held down.)
    const NSUInteger theMask =
        (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
    BOOL modifierDown =
        (([[NSApp currentEvent] it_modifierFlags] & theMask) == NSEventModifierFlagControl);
    BOOL snapWidth = !modifierDown;
    BOOL snapHeight = !modifierDown;
    if (sender != [self window]) {
      snapWidth = snapHeight = NO;
    }

    // If resizing a full-width/height X-of-screen window in a direction perpendicular to the screen
    // edge it's attached to, turn off snapping in the direction parallel to the edge.
    if (self.windowType == WINDOW_TYPE_RIGHT || self.windowType == WINDOW_TYPE_LEFT) {
        if (proposedFrameSize.height == self.window.frame.size.height) {
            snapHeight = NO;
        }
    }
    if (self.windowType == WINDOW_TYPE_TOP || self.windowType == WINDOW_TYPE_BOTTOM) {
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
    NSSize internalDecorationSize = self.currentSession.view.internalDecorationSize;
    NSSize tabSize = NSMakeSize(proposedFrameSize.width - decorationSize.width - internalDecorationSize.width,
                                proposedFrameSize.height - decorationSize.height - internalDecorationSize.height);

    // Snap proposed tab size to grid.  The snapping uses a grid spaced to
    // match the current pane's character size and aligned so margins are
    // correct if all we have is a single pane.
    BOOL hasScrollbar = [self scrollbarShouldBeVisible];
    NSSize contentSize =
        [NSScrollView contentSizeForFrameSize:tabSize
                  horizontalScrollerClass:nil
                    verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                               borderType:NSNoBorder
                              controlSize:NSControlSizeRegular
                            scrollerStyle:[self scrollerStyle]];

    int screenWidth = (contentSize.width - [iTermAdvancedSettingsModel terminalMargin] * 2) / charWidth;
    int screenHeight = (contentSize.height - [iTermAdvancedSettingsModel terminalVMargin] * 2) / charHeight;

    if (snapWidth) {
      contentSize.width = screenWidth * charWidth + [iTermAdvancedSettingsModel terminalMargin] * 2;
    }
    if (snapHeight) {
      contentSize.height = screenHeight * charHeight + [iTermAdvancedSettingsModel terminalVMargin] * 2;
    }
    tabSize =
        [PTYScrollView frameSizeForContentSize:contentSize
                       horizontalScrollerClass:nil
                         verticalScrollerClass:hasScrollbar ? [PTYScroller class] : nil
                                    borderType:NSNoBorder
                                   controlSize:NSControlSizeRegular
                                 scrollerStyle:[self scrollerStyle]];
    // Respect minimum tab sizes.
    for (NSTabViewItem* tabViewItem in [_contentView.tabView tabViewItems]) {
        PTYTab* theTab = [tabViewItem identifier];
        NSSize minTabSize = [theTab minSize];
        tabSize.width = MAX(tabSize.width, minTabSize.width);
        tabSize.height = MAX(tabSize.height, minTabSize.height);
    }

    // Compute new window size from tab size.
    proposedFrameSize.width = tabSize.width + decorationSize.width + internalDecorationSize.width;
    proposedFrameSize.height = tabSize.height + decorationSize.height + internalDecorationSize.height;

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

    // If the original proposal was to fill the screen then allow it
    NSRect screenFrame = self.window.screen.visibleFrame;
    DLog(@"screenFrame=%@ accepted=%@ originalProposal=%@ charSize=%@",
          NSStringFromSize(screenFrame.size),
          NSStringFromSize(proposedFrameSize),
          NSStringFromSize(originalProposal),
          NSStringFromSize(NSMakeSize(charWidth, charHeight)));
    if (snapWidth &&
        proposedFrameSize.width + charWidth > screenFrame.size.width &&
        proposedFrameSize.width < screenFrame.size.width) {
        CGFloat snappedMargin = screenFrame.size.width - proposedFrameSize.width;
        CGFloat desiredMargin = screenFrame.size.width - originalProposal.width;
        if (desiredMargin <= ceil(snappedMargin / 2.0)) {
            proposedFrameSize.width = screenFrame.size.width;
        }
    }
    if (snapHeight &&
        proposedFrameSize.height + charHeight > screenFrame.size.height &&
        proposedFrameSize.height < screenFrame.size.height) {
        CGFloat snappedMargin = screenFrame.size.height - proposedFrameSize.height;
        CGFloat desiredMargin = screenFrame.size.height - originalProposal.height;
        if (desiredMargin <= ceil(snappedMargin / 2.0)) {
            proposedFrameSize.height = screenFrame.size.height;
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
    // See comments on -forceFrame:
    DLog(@"windowDidChangeScreen frame=%@ forceFrame=%@ time left in forceFrameUntil=%@ screenConfig=%@\n%@",
         NSStringFromRect(self.window.frame),
         NSStringFromRect(_forceFrame),
         @([NSDate it_timeSinceBoot] - _forceFrameUntil),
         _screenConfigurationAtTimeOfForceFrame,
         [NSThread callStackSymbols]);
    if (!NSEqualRects(self.window.frame, _forceFrame) &&
        !NSEqualRects(NSZeroRect, _forceFrame) &&
        [NSDate it_timeSinceBoot] < _forceFrameUntil &&
        [[self screenConfiguration] isEqual:_screenConfigurationAtTimeOfForceFrame]) {
        DLog(@"Schedule a set frame");
        NSRect rect = _forceFrame;
        DLog(@"Setting frame due to force-frame to %@", NSStringFromRect(rect));
        [self.window setFrame:rect display:YES animate:NO];
        DLog(@"Returning early");
        return;
    } else {
        DLog(@"Allowing screen change to go on");
    }
    BOOL canonicalize = ![self miniaturizedWindowShouldPreserveFrameUntilDeminiaturized];
    // This gets called when any part of the window enters or exits the screen and
    // appears to be spuriously called for nonnative fullscreen windows.
    DLog(@"windowDidChangeScreen called. This is known to happen when the screen didn't really change! screen=%@",
         self.window.screen);
    if (canonicalize && !_inWindowDidChangeScreen) {
        // Nicolas reported a bug where canonicalizeWindowFrame moved the window causing this to
        // be called reentrantly, and eventually the stack overflowed. If we insist the window should
        // be on screen A and the OS insists it should be on screen B, we'll never agree, so just
        // try once.
        _inWindowDidChangeScreen = YES;
        [self canonicalizeWindowFrame];
        _inWindowDidChangeScreen = NO;
    } else {
        DLog(@"** Re-entrant call to windowDidChangeScreen:! Not canonicalizing. **");
    }
    if (@available(macOS 10.11, *)) {
        for (PTYSession *session in self.allSessions) {
            [session updateMetalDriver];
            [session.textview setNeedsDisplay:YES];
        }
    }
    DLog(@"Returning from windowDidChangeScreen:.");
}

- (NSArray *)screenConfiguration {
    return [[NSScreen screens] mapWithBlock:^id(NSScreen *screen) {
        return @{ @"frame": NSStringFromRect(screen.frame),
                  @"visibleFrame": NSStringFromRect(screen.visibleFrame) };
    }];
}

// When you replace the window with one of a different type and then order it
// front, the window gets moved to the first screen after a little while. It's
// not after one spin of the runloop, but just a little while later. I can't 
// tell why. But it's horrible and I can't find a better workaround than to
// just muscle it back to the frame we want if it changes for apparently no
// reason for some time.
- (void)forceFrame:(NSRect)frame {
    if (![iTermAdvancedSettingsModel workAroundMultiDisplayOSBug]) {
        return;
    }
    if (NSEqualRects(frame, NSIntersectionRect(frame, NSScreen.screens.firstObject.frame))) {
        DLog(@"Frame is entirely in the first screen. Not forcing.");
        return;
    }
    [self clearForceFrame];
    _forceFrame = frame;
    _screenConfigurationAtTimeOfForceFrame = [[self screenConfiguration] retain];
    _forceFrameUntil = [NSDate it_timeSinceBoot] + 2;
    DLog(@"Force frame to %@", NSStringFromRect(frame));
    [self.window setFrame:frame display:YES animate:NO];
}

- (void)clearForceFrame {
    [_screenConfigurationAtTimeOfForceFrame autorelease];
    _screenConfigurationAtTimeOfForceFrame = nil;
    _forceFrameUntil = 0;
    _forceFrame = NSZeroRect;
}

- (void)windowWillMove:(NSNotification *)notification {
    // AFAICT this is only called when you move the window by dragging it or double-click the title bar.
    DLog(@"Looks like the user started dragging the window.");
    [self clearForceFrame];
    _windowIsMoving = YES;
    _screenBeforeMoving = [[NSScreen screens] indexOfObject:self.window.screen];
}

- (void)windowDidMove:(NSNotification *)notification {
    DLog(@"%@: Window %@ moved. Called from %@", self, self.window, [NSThread callStackSymbols]);
    if (self.windowType == WINDOW_TYPE_MAXIMIZED || self.windowType == WINDOW_TYPE_COMPACT_MAXIMIZED) {
        [self canonicalizeWindowFrame];
    }
    [self saveTmuxWindowOrigins];
    if (_windowIsMoving && _isAnchoredToScreen) {
        NSInteger screenIndex = [[NSScreen screens] indexOfObject:self.window.screen];
        if (screenIndex != _screenBeforeMoving) {
            DLog(@"User appears to have dragged the window from screen %@ to screen %@. Removing screen anchor.", @(_screenBeforeMoving), @(screenIndex));
            _isAnchoredToScreen = NO;
        }
    }
    _windowIsMoving = NO;
    [self updateVariables];
}

- (void)windowDidResize:(NSNotification *)aNotification {
    lastResizeTime_ = [[NSDate date] timeIntervalSince1970];
    if (zooming_) {
        // Pretend nothing happened to avoid slowing down zooming.
        return;
    }

    PtyLog(@"windowDidResize to: %fx%f", [[self window] frame].size.width, [[self window] frame].size.height);
    PtyLog(@"%@", [NSThread callStackSymbols]);
    _windowDidResize = YES;

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
    [_contentView updateToolbeltProportionsIfNeeded];
    [self updateVariables];
    [_contentView windowDidResize];
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

// This takes care of updating the metal state
- (void)updateUseTransparency {
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateUseTransparencyMenuItem];
    for (PTYSession* aSession in [self allSessions]) {
        [aSession useTransparencyDidChange];
        [[aSession view] setNeedsDisplay:YES];
        [[aSession textview] setNeedsDisplay:YES];
    }
    [[self currentTab] recheckBlur];
    [self updateTabColors];  // Updates the window's background color as a side-effect
    [self updateForTransparency:self.ptyWindow];
    [_contentView invalidateAutomaticTabBarBackingHiding];
}

- (BOOL)anySessionInCurrentTabHasTransparency {
    return [self.currentTab.sessions anyWithBlock:^BOOL(PTYSession *session) {
        return session.textview.transparencyAlpha < 1;
    }];
}

- (IBAction)toggleUseTransparency:(id)sender
{
    useTransparency_ = !useTransparency_;
    [self updateUseTransparency];
    [_contentView setNeedsDisplay:YES];
    for (PTYSession *session in self.currentTab.sessions) {
        [session setNeedsDisplay:YES];
    }
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

- (BOOL)fullScreenWindowFrameShouldBeShiftedDownBelowMenuBarOnScreen:(NSScreen *)screen {
    const BOOL wantToHideMenuBar = [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen];
    const BOOL canHideMenuBar = ![iTermPreferences boolForKey:kPreferenceKeyUIElement];
    const BOOL menuBarIsHidden = ![[iTermMenuBarObserver sharedInstance] menuBarVisibleOnScreen:screen];
    const BOOL canOverlapMenuBar = [self.window isKindOfClass:[iTermPanel class]];

    DLog(@"Checking if the fullscreen window frame should be shifted down below the menu bar. "
         @"wantToHideMenuBar=%@, canHideMenuBar=%@, menuIsHidden=%@, canOverlapMenuBar=%@",
         @(wantToHideMenuBar), @(canHideMenuBar), @(menuBarIsHidden), @(canOverlapMenuBar));
    if (wantToHideMenuBar && canHideMenuBar) {
        DLog(@"Nope");
        return NO;
    }
    if (menuBarIsHidden) {
        DLog(@"Nope");
        return NO;
    }
    if (canOverlapMenuBar && wantToHideMenuBar) {
        DLog(@"Nope");
        return NO;
    }

    DLog(@"Yep");
    return YES;
}

- (NSRect)traditionalFullScreenFrameForScreen:(NSScreen *)screen {
    NSRect screenFrame = [screen frame];
    NSRect frameMinusMenuBar = screenFrame;
    frameMinusMenuBar.size.height -= [[[NSApplication sharedApplication] mainMenu] menuBarHeight];
    BOOL menuBarIsVisible = NO;

    if ([self fullScreenWindowFrameShouldBeShiftedDownBelowMenuBarOnScreen:screen]) {
        menuBarIsVisible = YES;
    }
    if (menuBarIsVisible) {
        PtyLog(@"Subtract menu bar from frame");
    } else {
        PtyLog(@"Do not subtract menu bar from frame");
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

- (IBAction)toggleFullScreenMode:(id)sender {
    [self toggleFullScreenMode:sender completion:nil];
}

- (BOOL)toggleFullScreenShouldUseLionFullScreen {
    if ([self lionFullScreen]) {
        return YES;
    }

    if (self.windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN ||
        self.windowType == WINDOW_TYPE_ACCESSORY) {
        return NO;
    }
    if (self.isHotKeyWindow) {
        // NSWindowCollectionBehaviorFullScreenAuxiliary window can't enter Lion fullscreen mode properly
        return NO;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscreen]) {
        return NO;
    }
    return YES;
}

- (void)toggleFullScreenMode:(id)sender
                  completion:(void (^)(BOOL))completion {
    DLog(@"toggleFullScreenMode:. window type is %d", self.windowType);
    if (self.toggleFullScreenShouldUseLionFullScreen) {
        [[self ptyWindow] toggleFullScreen:self];
        if (completion) {
            [_toggleFullScreenModeCompletionBlocks addObject:[[completion copy] autorelease]];
        }
        return;
    }

    [self toggleTraditionalFullScreenMode];
    if (completion) {
        completion(YES);
    }
}

- (void)delayedEnterFullscreen
{
    if (self.windowType == WINDOW_TYPE_LION_FULL_SCREEN &&
        [iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscreen]) {
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
    return [PseudoTerminal styleMaskForWindowType:self.windowType
                                  savedWindowType:self.savedWindowType
                                 hotkeyWindowType:_hotkeyWindowType];
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
    return NSMakeSize([iTermAdvancedSettingsModel terminalMargin] * 2 + sessionSize.width * cellSize.width + decorationSize.width,
                      [iTermAdvancedSettingsModel terminalVMargin] * 2 + sessionSize.height * cellSize.height + decorationSize.height);
}

+ (BOOL)windowType:(iTermWindowType)windowType shouldBeCompactWithSavedWindowType:(iTermWindowType)savedWindowType {
    switch (iTermThemedWindowType(windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
            if (@available(macOS 10.14, *)) {
                return YES;
            }
            return NO;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_ACCESSORY:
            return NO;
            break;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return YES;
            break;

        case WINDOW_TYPE_LION_FULL_SCREEN:
            return iTermWindowTypeIsCompact(iTermThemedWindowType(savedWindowType));
    }
    return NO;
}

- (NSWindow *)setWindowWithWindowType:(iTermWindowType)windowType
                      savedWindowType:(iTermWindowType)savedWindowType
               windowTypeForStyleMask:(iTermWindowType)windowTypeForStyleMask
                     hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
                         initialFrame:(NSRect)initialFrame {
    // For reasons that defy comprehension, you have to do this when switching to full-size content
    // view style mask. Otherwise, you are left with an unusable title bar.
    if (self.window.styleMask & NSWindowStyleMaskTitled) {
        while (self.window.titlebarAccessoryViewControllers.count > 0) {
            [self.window removeTitlebarAccessoryViewControllerAtIndex:0];
        }
    }

    const BOOL panel = (hotkeyWindowType == iTermHotkeyWindowTypeFloatingPanel) || (windowType == WINDOW_TYPE_ACCESSORY);
    const BOOL compact = [PseudoTerminal windowType:windowType shouldBeCompactWithSavedWindowType:savedWindowType];
    Class windowClass;
    if (panel) {
        if (compact) {
            windowClass = [iTermCompactPanel class];
        } else {
            windowClass = [iTermPanel class];
        }
    } else {
        if (compact) {
            windowClass = [iTermCompactWindow class];
        } else {
            windowClass = [iTermWindow class];
        }
    }
    NSWindowStyleMask styleMask = [PseudoTerminal styleMaskForWindowType:windowTypeForStyleMask
                                                         savedWindowType:savedWindowType
                                                        hotkeyWindowType:hotkeyWindowType];
    const BOOL defer = (hotkeyWindowType != iTermHotkeyWindowTypeNone);
    NSWindow<PTYWindow> *myWindow = [[[windowClass alloc] initWithContentRect:initialFrame
                                                                    styleMask:styleMask
                                                                      backing:NSBackingStoreBuffered
                                                                        defer:defer] autorelease];
    myWindow.collectionBehavior = [self desiredWindowCollectionBehavior];
    if (windowType != WINDOW_TYPE_LION_FULL_SCREEN) {
        // For some reason, you don't always get the frame you requested. I saw
        // this on OS 10.10 when creating normal windows on a 2-screen display. The
        // frames were within the visible frame of screen #2.
        // However, setting the frame at this point while restoring a Lion fullscreen window causes
        // it to appear with a title bar. TODO: Test if lion fullscreen windows restore on the right
        // monitor.
        [myWindow setFrame:initialFrame display:NO];
    }
    if (windowType == WINDOW_TYPE_MAXIMIZED || windowType == WINDOW_TYPE_COMPACT_MAXIMIZED) {
        myWindow.movable = NO;
    }
    [self updateForTransparency:(NSWindow<PTYWindow> *)myWindow];
    [self setWindow:myWindow];
    if (@available(macOS 10.14, *)) {
        // This doesn't work on 10.14. See it_setNeedsInvalidateShadow for a saner approach.
    } else {
        // This had been in iTerm2 for years and was removed, but I can't tell why. Issue 3833 reveals
        // that it is still needed, at least on OS 10.9.
        if ([myWindow respondsToSelector:@selector(_setContentHasShadow:)]) {
            [myWindow _setContentHasShadow:NO];
        }
    }

#if BETA
    if (@available(macOS 10.14, *)) {
        if (@available(macOS 10.15, *)) {
            // TODO
        } else {
            NSView *view = [myWindow it_titlebarViewOfClassWithName:@"_NSTitlebarDecorationView"];
            [view setHidden:YES];
        }
    }
#endif
    
    [self updateVariables];
    return myWindow;
}

- (BOOL)replaceWindowWithWindowOfType:(iTermWindowType)newWindowType {
    if (_willClose) {
        return NO;
    }
    iTermWindowType effectiveWindowType;
    if (_windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        effectiveWindowType = _savedWindowType;
    } else {
        effectiveWindowType = _windowType;
    }
    if (newWindowType == effectiveWindowType) {
        return NO;
    }
    NSWindow *oldWindow = [[self.window retain] autorelease];
    oldWindow.delegate = nil;
    [[_contentView retain] autorelease];
    [self setWindowWithWindowType:newWindowType
                  savedWindowType:self.savedWindowType
           windowTypeForStyleMask:newWindowType
                 hotkeyWindowType:_hotkeyWindowType
                     initialFrame:[self traditionalFullScreenFrameForScreen:self.window.screen]];
    [self.window.ptyWindow setLayoutDone];
    [[_contentView retain] autorelease];
    [_contentView removeFromSuperview];
    self.window.contentView = _contentView;
    self.window.opaque = NO;
    self.window.delegate = self;
    [oldWindow close];
    return YES;
}

- (void)willEnterTraditionalFullScreenMode {
    oldFrame_ = self.window.frame;
    oldFrameSizeIsBogus_ = NO;
    _savedWindowType = self.windowType;
    if (@available(macOS 10.14, *)) {
        if ([_shortcutAccessoryViewController respondsToSelector:@selector(removeFromParentViewController)]) {
            [_shortcutAccessoryViewController removeFromParentViewController];
        }
    }
    [self.window setOpaque:NO];
    self.window.alphaValue = 0;
    if (self.ptyWindow.isCompact) {
        [self replaceWindowWithWindowOfType:WINDOW_TYPE_TRADITIONAL_FULL_SCREEN];
        self.windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
    } else {
        self.windowType = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        self.window.styleMask = [self styleMask];
        [self.window setFrame:[self traditionalFullScreenFrameForScreen:self.window.screen]
                      display:YES];
    }
    self.window.alphaValue = 1;
}

- (void)willExitTraditionalFullScreenMode {
    BOOL shouldForce = NO;
    if ([PseudoTerminal windowType:self.savedWindowType shouldBeCompactWithSavedWindowType:self.savedWindowType]) {
        shouldForce = [self replaceWindowWithWindowOfType:self.savedWindowType];
        self.windowType = self.savedWindowType;
    } else {
        // NOTE: Setting the style mask causes the presentation options to be
        // changed (menu/dock hidden) because refreshTerminal gets called.
        self.windowType = self.savedWindowType;
        self.window.styleMask = [self styleMask];
    }
    [self showMenuBar];

    // This will be close but probably not quite right because tweaking to the decoration size
    // happens later.
    if (oldFrameSizeIsBogus_) {
        oldFrame_.size = [self preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration];
    }
    [self.window setFrame:oldFrame_ display:YES];
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            if (shouldForce) {
                [self forceFrame:oldFrame_];
            }
            break;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            break;
    }

    [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
    PtyLog(@"toggleFullScreenMode - allocate new terminal");
}

- (void)addShortcutAccessorViewControllerToTitleBarIfNeeded {
    if (@available(macOS 10.14, *)) {
        if (!_shortcutAccessoryViewController) {
            return;
        }
        if ((self.window.styleMask & NSWindowStyleMaskTitled) &&
            [self.window.titlebarAccessoryViewControllers containsObject:_shortcutAccessoryViewController]) {
            return;
        }
        if ([self.window respondsToSelector:@selector(addTitlebarAccessoryViewController:)] &&
            (self.window.styleMask & NSWindowStyleMaskTitled)) {
            // Explicitly load the view before adding. Otherwise, for some reason, on WINDOW_TYPE_MAXIMIZED windows,
            // the NSWindow miscalculates the size, and ends up resizing the iTermRootTerminalView incorrectly.
            [_shortcutAccessoryViewController view];

            [self.window addTitlebarAccessoryViewController:_shortcutAccessoryViewController];
            [self updateWindowNumberVisibility:nil];
        }
    }
}

- (void)updateTransparencyBeforeTogglingTraditionalFullScreenMode {
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
}

- (void)toggleTraditionalFullScreenMode {
    [SessionView windowDidResize];
    PtyLog(@"toggleFullScreenMode called");
    CGFloat savedToolbeltWidth = _contentView.toolbeltWidth;
    if (!_fullScreen) {
        [self willEnterTraditionalFullScreenMode];
    } else {
        [self willExitTraditionalFullScreenMode];
    }
    [self updateForTransparency:self.ptyWindow];

    [self updateTransparencyBeforeTogglingTraditionalFullScreenMode];
    _fullScreen = !_fullScreen;
    [self didToggleTraditionalFullScreenModeWithSavedToolbeltWidth:savedToolbeltWidth];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad didToggleTraditionalFullScreenMode];
}

- (void)didExitTraditionalFullScreenMode {
    NSSize contentSize = self.window.frame.size;
    NSSize decorationSize = self.windowDecorationSize;
    if (_contentView.shouldShowToolbelt) {
        decorationSize.width += _contentView.toolbelt.frame.size.width;
    }
    contentSize.width -= decorationSize.width;
    contentSize.height -= decorationSize.height;

    [self fitWindowToTabSize:contentSize];
}

- (void)didToggleTraditionalFullScreenModeWithSavedToolbeltWidth:(CGFloat)savedToolbeltWidth {
    [self didChangeAnyFullScreen];
    [_contentView.tabBarControl updateFlashing];
    togglingFullScreen_ = YES;
    _contentView.toolbeltWidth = savedToolbeltWidth;
    [_contentView constrainToolbeltWidth];
    [_contentView updateToolbeltForWindow:self.window];
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
        [self didExitTraditionalFullScreenMode];
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

    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            [self forceFrame:self.window.frame];
            break;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            break;
    }

    [self.window performSelector:@selector(makeKeyAndOrderFront:) withObject:nil afterDelay:0];
    [self.window makeFirstResponder:[[self currentSession] textview]];
    if (iTermWindowTypeIsCompact(self.savedWindowType) ||
        iTermWindowTypeIsCompact(self.windowType)) {
        [self didChangeCompactness];
    }
    [self refreshTools];
    [self updateTabColors];
    [self saveTmuxWindowOrigins];
    [self didChangeCompactness];
    [self updateTouchBarIfNeeded:NO];
    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
}

- (void)updateForTransparency:(NSWindow<PTYWindow> *)window {
    BOOL shouldEnableShadow = NO;
    switch (self.windowType) {
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            if (exitingLionFullscreen_) {
                shouldEnableShadow = YES;
            } else {
                window.hasShadow = NO;
            }
            return;

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            shouldEnableShadow = YES;
            break;
    }
    if ([self anyPaneIsTransparent] != _anyPaneIsTransparent) {
        _anyPaneIsTransparent = [self anyPaneIsTransparent];
        [self repositionWidgets];
    }
    if (@available(macOS 10.14, *)) {
        if ([iTermAdvancedSettingsModel disableWindowShadowWhenTransparencyOnMojave]) {
            [self updateWindowShadowForNonFullScreenWindowDisablingIfAnySessionHasTransparency:window];
            shouldEnableShadow = NO;
        }
    } else {
        if ([iTermAdvancedSettingsModel disableWindowShadowWhenTransparencyPreMojave]) {
            [self updateWindowShadowForNonFullScreenWindowDisablingIfAnySessionHasTransparency:window];
            shouldEnableShadow = NO;
        }
    }
    if (shouldEnableShadow) {
        window.hasShadow = YES;
    }
}

- (void)updateWindowShadowForNonFullScreenWindowDisablingIfAnySessionHasTransparency:(NSWindow *)window {
    const BOOL haveTransparency = [self anySessionInCurrentTabHasTransparency];
    DLog(@"%@: have transparency = %@ for sessions %@ in tab %@", self, @(haveTransparency), self.currentTab.sessions, self.currentTab);
    window.hasShadow = !haveTransparency;
}

- (void)didChangeCompactness {
    [self updateForTransparency:(NSWindow<PTYWindow> *)self.window];
    [_contentView didChangeCompactness];
}

- (BOOL)fullScreen
{
    return _fullScreen;
}

- (BOOL)tabBarShouldBeVisible {
    if (@available(macOS 10.14, *)) {
        if (togglingLionFullScreen_ || [self lionFullScreen]) {
            return YES;
        }
        if (_contentView.tabBarControlOnLoan) {
            return NO;
        }
    }
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

- (BOOL)windowTitleIsVisible {
    switch (iTermThemedWindowType(_windowType)) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
            return NO;

        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return [self rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar];

        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_MAXIMIZED:
            return YES;
    }
}
- (void)windowWillStartLiveResize:(NSNotification *)notification {
    [self clearForceFrame];
    liveResize_ = YES;
    if (@available(macOS 10.14, *)) {
        if (![self windowTitleIsVisible] && !self.anyFullScreen) {
            [_contentView setShowsWindowSize:YES];
        }
    }
    [self updateUseMetalInAllTabs];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
    NSScreen *screen = self.window.screen;
    if (@available(macOS 10.14, *)) {
        [_contentView setShowsWindowSize:NO];
    }

    // Canonicalize the frame so that centered windows stay centered, edge-attached windows stay edge
    // attached.
    NSRect frame = [self canonicalFrameForScreen:self.window.screen windowFrame:self.window.frame preserveSize:YES];
    NSRect screenFrameForEdgeSpanningWindow = [self screenFrameForEdgeSpanningWindows:screen];

    switch (self.windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            if ((frame.size.width < screenFrameForEdgeSpanningWindow.size.width)) {
                self.windowType = WINDOW_TYPE_TOP_PARTIAL;
            } else {
                self.windowType = WINDOW_TYPE_TOP;
            }
            // desiredRows/Columns get reset here to fix issue 4073. If you manually resize a window
            // then its desired size becomes irrelevant; we want it to preserve the size you set
            // and forget about the size in its profile. This way it will go back to the old size
            // when toggling out of fullscreen.
            desiredRows_ = -1;
            break;

        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            if (frame.size.width < screenFrameForEdgeSpanningWindow.size.width) {
                self.windowType = WINDOW_TYPE_BOTTOM_PARTIAL;
            } else {
                self.windowType = WINDOW_TYPE_BOTTOM;
            }
            desiredRows_ = -1;
            break;

        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            if (frame.size.height < screenFrameForEdgeSpanningWindow.size.height) {
                self.windowType = WINDOW_TYPE_LEFT_PARTIAL;
            } else {
                self.windowType = WINDOW_TYPE_LEFT;
            }
            desiredColumns_ = -1;
            break;

        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            if (frame.size.height < screenFrameForEdgeSpanningWindow.size.height) {
                self.windowType = WINDOW_TYPE_RIGHT_PARTIAL;
            } else {
                self.windowType = WINDOW_TYPE_RIGHT;
            }
            desiredColumns_ = -1;
            break;

        default:
            break;
    }
    if (!NSEqualRects(frame, self.window.frame) && frame.size.width > 0 && frame.size.height > 0) {
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
    [self updateUseMetalInAllTabs];
}

- (void)didChangeAnyFullScreen {
    for (PTYSession *session in self.allSessions) {
        [session updateStatusBarStyle];
    }
    if (@available(macOS 10.14, *)) {
        if (lionFullScreen_) {
            self.window.styleMask = self.styleMask | NSWindowStyleMaskFullScreen;
        } else {
            NSRect frameBefore = self.window.frame;
            self.window.styleMask = [self styleMask];
            if (!_fullScreen) {
                // Changing the style mask can cause the frame to change.
                [self.window setFrame:frameBefore display:YES];
            }
        }
        [self repositionWidgets];
    }
    [_contentView invalidateAutomaticTabBarBackingHiding];
}

- (NSTitlebarAccessoryViewController *)lionFullScreenTabBarViewController NS_AVAILABLE_MAC(10_14) {
    if (!_lionFullScreenTabBarViewController) {
        _lionFullScreenTabBarViewController = [[iTermLionFullScreenTabBarViewController alloc] initWithView:[_contentView borrowTabBarControl]];
        _lionFullScreenTabBarViewController.layoutAttribute = NSLayoutAttributeBottom;
    }
    return _lionFullScreenTabBarViewController;
}

- (BOOL)shouldMoveTabBarToTitlebarAccessoryInLionFullScreen {
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
        case PSMTab_BottomTab:
            return NO;

        case PSMTab_TopTab:
            if ([iTermPreferences boolForKey:kPreferenceKeyFlashTabBarInFullscreen] &&
                ![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
                return NO;
            }
            break;
    }

    return YES;
}

// Returns whether a permanent (i.e., not flashing) tabbar ought to be drawn while in full screen.
// It does not check if you're already in full screen.
- (BOOL)shouldShowPermanentFullScreenTabBar {
    if (![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
        return NO;
    }

    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar] && self.tabs.count == 1) {
        return NO;
    }

    return YES;
}

- (void)updateTabBarControlIsTitlebarAccessoryAssumingFullScreen:(BOOL)fullScreen NS_AVAILABLE_MAC(10_14) {
    const NSInteger index = [self.window.it_titlebarAccessoryViewControllers indexOfObject:_lionFullScreenTabBarViewController];
    if (fullScreen && [self shouldMoveTabBarToTitlebarAccessoryInLionFullScreen]) {
        NSTitlebarAccessoryViewController *viewController = [self lionFullScreenTabBarViewController];
        if ([self shouldShowPermanentFullScreenTabBar]) {
            [viewController setFullScreenMinHeight:_contentView.tabBarControl.frame.size.height];
        } else {
            [viewController setFullScreenMinHeight:0];
        }
        if (index == NSNotFound) {
            [self.window addTitlebarAccessoryViewController:viewController];
        }
    } else if (_contentView.tabBarControlOnLoan) {
        assert(index != NSNotFound);
        [self.window removeTitlebarAccessoryViewControllerAtIndex:index];
        [_contentView returnTabBarControlView:(iTermTabBarControlView *)_lionFullScreenTabBarViewController.view];
        [_lionFullScreenTabBarViewController release];
        _lionFullScreenTabBarViewController = nil;
        [_contentView layoutSubviews];
    }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    DLog(@"Window will enter lion fullscreen");
    togglingLionFullScreen_ = YES;
    [self didChangeAnyFullScreen];
    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    [self repositionWidgets];
    [_contentView didChangeCompactness];
    if (@available(macOS 10.14, *)) {
        if (self.window.styleMask & NSWindowStyleMaskTitled) {
            [self updateTabBarControlIsTitlebarAccessoryAssumingFullScreen:YES];
        }
    }
    if (self.windowType != WINDOW_TYPE_LION_FULL_SCREEN) {
        _savedWindowType = self.windowType;
        _windowType = WINDOW_TYPE_LION_FULL_SCREEN;
    }
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    DLog(@"Window did enter lion fullscreen");

    if (@available(macOS 10.14, *)) {
        [self updateTabBarControlIsTitlebarAccessoryAssumingFullScreen:YES];
    }
    zooming_ = NO;
    togglingLionFullScreen_ = NO;
    _fullScreenRetryCount = 0;
    lionFullScreen_ = YES;
    [self didChangeAnyFullScreen];
    [_contentView.tabBarControl setFlashing:YES];
    [_contentView updateToolbeltForWindow:self.window];
    [self repositionWidgets];
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
    [self updateTouchBarIfNeeded:NO];

    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    [self didFinishFullScreenTransitionSuccessfully:YES];
    [self updateVariables];
}

- (void)didFinishFullScreenTransitionSuccessfully:(BOOL)success {
    DLog(@"didFinishFullScreenTransitionSuccessfully:%@", @(success));
    NSArray *blocks = [[_toggleFullScreenModeCompletionBlocks copy] autorelease];
    [_toggleFullScreenModeCompletionBlocks removeAllObjects];
    for (void (^block)(BOOL) in blocks) {
        block(success);
    }
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window {
    DLog(@"windowDidFailToEnterFullScreen %@", self);
    [self didFinishFullScreenTransitionSuccessfully:NO];
    if (!togglingLionFullScreen_) {
        DLog(@"It's ok though because togglingLionFullScreen is off");
        return;
    }
    if (_fullScreenRetryCount < 3) {
        _fullScreenRetryCount++;
        DLog(@"Increment retry count to %@ and schedule an attempt after a delay %@", @(_fullScreenRetryCount), self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DLog(@"About to retry entering full screen with count %@: %@", @(_fullScreenRetryCount), self);
            [self.window toggleFullScreen:self];
        });
    } else {
        DLog(@"Giving up after three retries: %@", self);
        togglingLionFullScreen_ = NO;
        _fullScreenRetryCount = 0;
        [_contentView didChangeCompactness];
        [_contentView layoutSubviews];
    }
    [self updateVariables];
}

- (void)hideStandardWindowButtonsAndTitlebarAccessories {
    [[self.window standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[self.window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[self.window standardWindowButton:NSWindowZoomButton] setHidden:YES];
    while (self.window.titlebarAccessoryViewControllers.count) {
        [self.window removeTitlebarAccessoryViewControllerAtIndex:0];
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification {
    DLog(@"Window will exit lion fullscreen");
    exitingLionFullscreen_ = YES;

    if (@available(macOS 10.14, *)) {
        [self updateTabBarControlIsTitlebarAccessoryAssumingFullScreen:NO];
    } else {
        self.window.styleMask = [PseudoTerminal styleMaskForWindowType:self.savedWindowType
                                                       savedWindowType:self.savedWindowType
                                                      hotkeyWindowType:_hotkeyWindowType];
    }
    [self updateForTransparency:(NSWindow<PTYWindow> *)self.window];
    [_contentView.tabBarControl updateFlashing];
    [self fitTabsToWindow];
    if (@available(macOS 10.14, *)) {} else {
        [self repositionWidgets];
    }
    self.window.hasShadow = YES;
    [self updateUseMetalInAllTabs];
    [self updateForTransparency:self.ptyWindow];
    self.windowType = WINDOW_TYPE_LION_FULL_SCREEN;
    if (@available(macOS 10.14, *)) {
        if (![self rootTerminalViewShouldRevealStandardWindowButtons]) {
            [self hideStandardWindowButtonsAndTitlebarAccessories];
        }
        [_contentView didChangeCompactness];
        [self repositionWidgets];
    }
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    DLog(@"Window did exit lion fullscreen");
    exitingLionFullscreen_ = NO;
    zooming_ = NO;
    lionFullScreen_ = NO;

    DLog(@"Window did exit fullscreen. Set window type to %d", self.savedWindowType);
    if (@available(macOS 10.14, *)) {
        self.window.styleMask = [PseudoTerminal styleMaskForWindowType:self.savedWindowType
                                                       savedWindowType:self.savedWindowType
                                                      hotkeyWindowType:_hotkeyWindowType];
    }
    const iTermWindowType desiredWindowType = self.savedWindowType;
    [self updateWindowForWindowType:desiredWindowType];
    self.windowType = desiredWindowType;
    [self didChangeAnyFullScreen];

    [_contentView.tabBarControl updateFlashing];
    // Set scrollbars appropriately
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self repositionWidgets];
    [self invalidateRestorableState];
    [_contentView updateToolbeltForWindow:self.window];

    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    [self.currentTab recheckBlur];
    [self notifyTmuxOfWindowResize];
    [self saveTmuxWindowOrigins];
    [self.window makeFirstResponder:self.currentSession.textview];
    [self updateTouchBarIfNeeded:NO];
    [self updateUseMetalInAllTabs];
    [_contentView didChangeCompactness];
    [_contentView layoutSubviews];
    [self updateForTransparency:self.ptyWindow];
    [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
    [self didFinishFullScreenTransitionSuccessfully:YES];
    [self updateVariables];

    // Windows forget their collection behavior when exiting full screen when the app is a LSUIElement. Issue 8048.
    if ([[iTermApplication sharedApplication] isUIElement]) {
        self.window.collectionBehavior = self.desiredWindowCollectionBehavior;
    }
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame {
    // Disable redrawing during zoom-initiated live resize.
    zooming_ = YES;
    [self updateUseMetalInAllTabs];
    if (togglingLionFullScreen_) {
        // Tell it to use the whole screen when entering Lion fullscreen.
        // This is actually called twice in a row when entering fullscreen.
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
        if ([[NSApp currentEvent] type] == NSEventTypeKeyDown) {
            verticalOnly = maxVerticallyPref;
        } else if (maxVerticallyPref ^
                   (([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagShift) != 0)) {
            verticalOnly = YES;
        }
    }

    if (verticalOnly) {
        // Keep the width the same
        proposedFrame.size.width = [sender frame].size.width;
    } else {
        proposedFrame.size.width = defaultFrame.size.width;
        proposedFrame.origin.x = defaultFrame.origin.x;
    }
    proposedFrame.size.height = defaultFrame.size.height;
    proposedFrame.origin.y = defaultFrame.origin.y;
    return proposedFrame;
}

- (void)windowWillShowInitial {
    PtyLog(@"windowWillShowInitial");
    iTermTerminalWindow* window = [self ptyWindow];
    // If it's a full or top-of-screen window with a screen number preference, always honor that.
    if (_isAnchoredToScreen) {
        PtyLog(@"have screen preference is set");
        NSRect frame = [window frame];
        frame.origin = preferredOrigin_;
        [window setFrame:frame display:NO];
        return;
    }
    NSUInteger numberOfTerminalWindows = [[[iTermController sharedInstance] terminals] count];
    if (numberOfTerminalWindows == 1 ||
        ![iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement]) {
        if (!_isAnchoredToScreen &&
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

- (BOOL)sessionInitiatedResize:(PTYSession *)session width:(int)width height:(int)height {
    PtyLog(@"sessionInitiatedResize");
    // ignore resize request when we are in full screen mode.
    if ([self anyFullScreen]) {
        PtyLog(@"sessionInitiatedResize - in full screen mode");
        return NO;
    }

    PTYTab *tab = [self tabForSession:session];
    [tab setLockedSession:session];
    [self safelySetSessionSize:session rows:height columns:width];
    PtyLog(@"sessionInitiatedResize - calling fitWindowToTab");
    [self fitWindowToTab:tab];
    PtyLog(@"sessionInitiatedResize - calling fitTabsToWindow");
    [self fitTabsToWindow];
    [tab setLockedSession:nil];
    return YES;
}

// Contextual menu
- (void)editSession:(NSMenuItem *)item {
    NSTabViewItem *tabViewItem = item.representedObject;
    PTYTab *tab = tabViewItem.identifier;
    PTYSession *session = tab.activeSession;
    if (session) {
        [self editSession:session makeKey:NO];
    }
}

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
    [[PreferencePanel sessionsInstance] openToProfileWithGuid:newGuid
                                             selectGeneralTab:makeKey
                                                         tmux:session.isTmuxClient
                                                        scope:session.variablesScope];
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
- (void)tabView:(NSTabView *)tabView closeTab:(id)identifier {
    if ([iTermAdvancedSettingsModel middleClickClosesTab]) {
        [self closeTab:identifier];
    }
}

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
    PTYTab *tab = [tabViewItem identifier];
    for (PTYSession* aSession in [tab sessions]) {
        [aSession setNewOutput:NO];

        // Background tabs' timers run infrequently so make sure the display is
        // up to date to avoid a jump when it's shown.
        [[aSession textview] setNeedsDisplay:YES];
        [aSession updateDisplayBecause:@"tabView:didSelectTabViewItem:"];
        aSession.active = YES;
        [self setDimmingForSession:aSession];
        [[aSession view] setBackgroundDimmed:![[self window] isKeyWindow]];
        [[aSession view] didBecomeVisible];
    }

    for (PTYSession *session in [self allSessions]) {
        if ([[session textview] isFindingCursor]) {
            [[session textview] endFindCursor];
        }
    }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionBecameKey
                                                        object:[[tabViewItem identifier] activeSession]];

    PTYSession *activeSession = [self currentSession];
    for (PTYSession *s in [self allSessions]) {
        [s setFocused:(s == activeSession)];
    }
    [self showOrHideInstantReplayBar];
    [self refreshTools];
    [self updateTabColors];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    [self notifyTmuxOfTabChange];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded] && ![iTermAdvancedSettingsModel pinEditSession]) {
        [self editSession:self.currentSession makeKey:NO];
    }
    [self updateTouchBarIfNeeded:NO];

    NSInteger darkCount = 0;
    NSInteger lightCount = 0;
    for (PTYSession *session in tab.sessions) {
        if ([[session.colorMap colorForKey:kColorMapBackground] perceivedBrightness] < 0.5) {
            darkCount++;
        } else {
            lightCount++;
        }
    }
    if (lightCount > darkCount) {
        // Matches bottom line color for tab bar
        _contentView.color = [NSColor colorWithSRGBRed:170/255.0 green:167/255.0 blue:170/255.0 alpha:1];
    } else {
        _contentView.color = [NSColor windowBackgroundColor];
    }
    [self updateProxyIcon];
    [_contentView layoutIfStatusBarChanged];
    if ([iTermAdvancedSettingsModel clearBellIconAggressively]) {
        [self.currentSession setBell:NO];
    }
    [self updateUseMetalInAllTabs];
    [self.scope setValue:self.currentTab.variables forVariableNamed:iTermVariableKeyWindowCurrentTab];
    [self updateForTransparency:self.ptyWindow];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSelectedTabDidChange object:tab];
}

- (void)updateUseMetalInAllTabs {
    if (@available(macOS 10.11, *)) {
        for (PTYTab *aTab in self.tabs) {
            [aTab updateUseMetal];
        }
    }
}

- (BOOL)proxyIconIsAllowed {
    if (![iTermPreferences boolForKey:kPreferenceKeyEnableProxyIcon]) {
        return NO;
    }

    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
            return NO;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            break;
    }

    switch (self.windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return NO;

        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
            break;
    }

    return YES;
}

- (void)updateProxyIcon {
    if (![self proxyIconIsAllowed]) {
        self.window.representedURL = nil;
        return;
    }
    if (self.currentSession.preferredProxyIcon) {
        self.window.representedURL = self.currentSession.preferredProxyIcon;
        return;
    }
    self.window.representedURL = self.currentSession.textViewCurrentLocation;
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

- (void)saveAffinitiesLater:(PTYTab *)theTab {
    // Avoid saving affinities during detach because the windows will be gone by the time it saves them.
    //    if ([theTab isTmuxTab] && !theTab.tmuxController.detaching) {
    if ([theTab isTmuxTab]) {
        PtyLog(@"Queueing call to saveAffinitiesLater from %@", [NSThread callStackSymbols]);
        [self performSelector:@selector(saveAffinitiesAndOriginsForController:)
                   withObject:[theTab tmuxController]
                   afterDelay:0];
    }
}

- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem {
    [self saveAffinitiesLater:[tabViewItem identifier]];
}

- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem {

    [self tabView:tabView willInsertTabViewItem:tabViewItem atIndex:[tabView numberOfTabViewItems]];
    [self saveAffinitiesLater:[tabViewItem identifier]];
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
        [[theTab tmuxController] setSize:theTab.tmuxSize window:theTab.tmuxWindow];
    }
    [self saveAffinitiesLater:[tabViewItem identifier]];
}

- (BOOL)tabView:(NSTabView*)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem {
    return [self tabView:tabView shouldCloseTabViewItem:tabViewItem suppressConfirmation:NO];
}

// This isn't a delegate method, but I need the functionality with the added suppressConfirmation
// flag to avoid showing two warnings in tmux integration mode.
- (BOOL)tabView:(NSTabView*)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem suppressConfirmation:(BOOL)suppressConfirmation {
    PTYTab *aTab = [tabViewItem identifier];
    if (aTab == nil) {
        return NO;
    }

    return [self confirmCloseTab:aTab suppressConfirmation:suppressConfirmation];
}

- (BOOL)tabView:(NSTabView*)aTabView
    shouldDragTabViewItem:(NSTabViewItem *)tabViewItem
               fromTabBar:(PSMTabBarControl *)tabBarControl
{
    return YES;
}

- (BOOL)droppingTabOutsideWindowMovesWindow {
    if (self.numberOfTabs != 1) {
        return NO;
    }

    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            break;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return NO;
    }

    if (![iTermPreferences boolForKey:kPreferenceKeyStretchTabsToFillBar]) {
        return NO;
    }

    switch ((PSMTabPosition)[iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
            return NO;

        case PSMTab_BottomTab:
        case PSMTab_TopTab:
            break;
    }

    return YES;
}

- (BOOL)tabView:(NSTabView*)aTabView
    shouldDropTabViewItem:(NSTabViewItem *)tabViewItem
                 inTabBar:(PSMTabBarControl *)aTabBarControl
         moveSourceWindow:(BOOL *)moveSourceWindow {
    if (![aTabBarControl tabView]) {
        // Tab dropping outside any existing tabbar to create a new window.
        if (moveSourceWindow && [self droppingTabOutsideWindowMovesWindow]) {
            *moveSourceWindow = YES;
            return NO;
        }
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
              inTabBar:(PSMTabBarControl *)aTabBarControl {
    PTYTab *aTab = [tabViewItem identifier];
    PseudoTerminal *term = (PseudoTerminal *)[aTabBarControl delegate];
    [self didDonateTab:aTab toWindowController:term];
}

- (void)didDonateTab:(PTYTab *)aTab toWindowController:(PseudoTerminal *)term {
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

- (NSImage *)imageFromSelectedTabView:(NSTabView *)aTabView
                          tabViewItem:(NSTabViewItem *)tabViewItem {
    NSView *tabRootView = [tabViewItem view];

    NSRect contentFrame;
    NSRect viewRect;
    contentFrame = viewRect = [tabRootView frame];
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
            contentFrame.size.width += _contentView.leftTabBarWidth;
            break;

        case PSMTab_TopTab:
        case PSMTab_BottomTab:
            contentFrame.size.height += _contentView.tabBarControl.height;
            break;
    }

    // Grabs whole tabview image.
    NSImage *viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
    NSImage *tabViewImage = [[[NSImage alloc] init] autorelease];

    NSBitmapImageRep *tabviewRep;

    PTYTab *tab = tabViewItem.identifier;
    [tab bounceMetal];

    tabviewRep = [tabRootView bitmapImageRepForCachingDisplayInRect:viewRect];
    [tabRootView cacheDisplayInRect:viewRect toBitmapImageRep:tabviewRep];

    [tabViewImage addRepresentation:tabviewRep];


    [viewImage lockFocus];
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
            viewRect.origin.x += _contentView.leftTabBarWidth;
            viewRect.size.width -= _contentView.leftTabBarWidth;
            break;

        case PSMTab_TopTab:
            break;

        case PSMTab_BottomTab:
            viewRect.origin.y += _contentView.tabBarControl.height;
            break;
    }

    [tabViewImage drawAtPoint:viewRect.origin
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0];
    [viewImage unlockFocus];

    return viewImage;
}

- (NSImage *)imageFromNonSelectedTabViewItem:(NSTabViewItem *)tabViewItem {
    NSImage *viewImage = [[tabViewItem identifier] image:YES];
    return viewImage;
}

- (BOOL)tabViewDragShouldExitWindow:(NSTabView *)tabView {
    return [iTermAdvancedSettingsModel allowDragOfTabIntoNewWindow];
}

- (NSImage *)tabView:(NSTabView *)aTabView
 imageForTabViewItem:(NSTabViewItem *)tabViewItem
           styleMask:(NSWindowStyleMask *)styleMask {
    *styleMask = self.window.styleMask;

    NSImage *viewImage;
    if (tabViewItem == [aTabView selectedTabViewItem]) {
        viewImage = [self imageFromSelectedTabView:aTabView tabViewItem:tabViewItem];
    } else {
        viewImage = [self imageFromNonSelectedTabViewItem:tabViewItem];
    }

    return viewImage;
}

- (BOOL)useSeparateStatusbarsPerPane {
    if (![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]) {
        return NO;
    }
    if (self.currentTab.tmuxTab) {
        return NO;
    }
    return YES;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView {
    PtyLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);
    for (PTYSession* session in [self allSessions]) {
        [session setIgnoreResizeNotifications:NO];
    }

    const BOOL willShowTabBar = ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar] &&
                                 [_contentView.tabView numberOfTabViewItems] > 1 &&
                                 ([_contentView.tabBarControl isHidden] || [self rootTerminalViewShouldLeaveEmptyAreaAtTop]));
    // check window size in case tabs have to be hidden or shown
    if (([_contentView.tabView numberOfTabViewItems] == 1) ||  // just decreased to 1 or increased above 1 and is hidden
        willShowTabBar) {
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

            // Update visibility of title bars.
            const BOOL perPaneTitleBarEnabled = [iTermPreferences boolForKey:kPreferenceKeyShowPaneTitles];
            const BOOL statusBarsOnTop = ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition] == iTermStatusBarPositionTop);
            const BOOL perPaneStatusBars = [self useSeparateStatusbarsPerPane];
            const BOOL haveMultipleSessions = firstTab.sessions.count > 1;
            for (PTYSession *session in firstTab.sessions) {
                const BOOL sessionHasStatusBar = [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:session.profile];
                const BOOL showTitleBar = perPaneTitleBarEnabled && (firstTab.isMaximized || haveMultipleSessions);
                const BOOL showTopStatusBar = statusBarsOnTop && perPaneStatusBars && sessionHasStatusBar;
                [[session view] setShowTitle:showTitleBar || showTopStatusBar adjustScrollView:YES];
            }
        }
        // In case the tab bar will go away
        [_contentView invalidateAutomaticTabBarBackingHiding];

        if (willShowTabBar && [iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab) {
            [_contentView willShowTabBar];
        }
        if (_windowNeedsInitialSize || ![iTermPreferences boolForKey:kPreferenceKeyPreserveWindowSizeWhenTabBarVisibilityChanges]) {
            const BOOL neededInitialSize = _windowNeedsInitialSize;
            const NSRect frameBefore = self.window.frame;
            if (_windowNeedsInitialSize) {
                DLog(@"Perform initial fitWindowToTabs");
            }
            [self fitWindowToTabs];
            const NSRect frameAfter = self.window.frame;
            if (NSEqualRects(frameBefore, frameAfter) && neededInitialSize) {
                // If the initial window frame happened to exactly equal the fitWindowToTabs size
                // the session will remain at its initial size specified by its profile. It's
                // necessary to call fitTabsToWindow once during window creation, and this is where
                // it happens. This is easy to reproduce with the maximized window style in the
                // Minimal theme.
                [self fitTabsToWindow];
            }
        }
        [self repositionWidgets];
        if (wasDraggedFromAnotherWindow_) {
            wasDraggedFromAnotherWindow_ = NO;
            [firstTab setReportIdealSizeAsCurrent:NO];

            // fitWindowToTabs will detect the window changed sizes and do a bogus move of it in this case.
            switch (self.windowType) {
                case WINDOW_TYPE_NORMAL:
                case WINDOW_TYPE_COMPACT:
                case WINDOW_TYPE_NO_TITLE_BAR:
                case WINDOW_TYPE_ACCESSORY:
                    [[self window] setFrameOrigin:originalOrigin];
                    break;
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                case WINDOW_TYPE_RIGHT_PARTIAL:
                case WINDOW_TYPE_LEFT_PARTIAL:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_BOTTOM:
                case WINDOW_TYPE_RIGHT:
                case WINDOW_TYPE_LEFT:
                case WINDOW_TYPE_LION_FULL_SCREEN:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_MAXIMIZED:
                case WINDOW_TYPE_COMPACT_MAXIMIZED:
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                    break;
            }
        }
    }

    [self updateTabColors];
    [self _updateTabObjectCounts];
    [self updateTouchBarIfNeeded:NO];

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
    if (@available(macOS 10.14, *)) {
        if ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar] && (self.lionFullScreen || togglingLionFullScreen_)) {
            // Hiding tabbar in fullscreen on 10.14 is extra work because it's a titlebar accessory.
            [self updateTabBarStyle];
        }
    }
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
    item = [[[NSMenuItem alloc] initWithTitle:@"Edit Session…"
                                       action:@selector(editSession:)
                                keyEquivalent:@""] autorelease];
    [item setRepresentedObject:tabViewItem];
    [rootMenu addItem:item];

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

    item = [[[NSMenuItem alloc] initWithTitle:@"Save Tab as Window Arrangement"
                                       action:@selector(saveTabAsWindowArrangement:)
                                keyEquivalent:@""] autorelease];
    [item setRepresentedObject:tabViewItem];
    [rootMenu addItem:item];

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

    for (NSMenuItem *item in rootMenu.itemArray) {
        item.target = self;
    }

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
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_TopTab:
            switch ([term windowType]) {
                case WINDOW_TYPE_COMPACT:
                case WINDOW_TYPE_ACCESSORY:
                case WINDOW_TYPE_NORMAL: {
                    CGFloat contentHeight = [term.window contentRectForFrameRect:NSMakeRect(0, 0, 100, 100)].size.height;
                    CGFloat titleBarHeight = 100 - contentHeight;
                    point.y += titleBarHeight;

                    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar]) {
                        point.y -= self.tabBarControl.frame.size.height;
                    }
                    [[term window] setFrameTopLeftPoint:point];
                    break;
                }
                case WINDOW_TYPE_NO_TITLE_BAR:
                    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar]) {
                        point.y -= self.tabBarControl.frame.size.height;
                    }
                    [[term window] setFrameTopLeftPoint:point];
                    break;

                case WINDOW_TYPE_MAXIMIZED:
                case WINDOW_TYPE_COMPACT_MAXIMIZED:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_LEFT:
                case WINDOW_TYPE_RIGHT:
                case WINDOW_TYPE_BOTTOM:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_LEFT_PARTIAL:
                case WINDOW_TYPE_RIGHT_PARTIAL:
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                case WINDOW_TYPE_LION_FULL_SCREEN:
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                    break;
            }
            break;

        case PSMTab_BottomTab:
            switch ([term windowType]) {
                case WINDOW_TYPE_NORMAL:
                case WINDOW_TYPE_ACCESSORY:
                case WINDOW_TYPE_COMPACT:
                case WINDOW_TYPE_NO_TITLE_BAR:
                    if (![iTermPreferences boolForKey:kPreferenceKeyHideTabBar]) {
                        point.y -= self.tabBarControl.frame.size.height;
                        [[term window] setFrameTopLeftPoint:point];
                    }
                    break;
                case WINDOW_TYPE_MAXIMIZED:
                case WINDOW_TYPE_COMPACT_MAXIMIZED:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_LEFT:
                case WINDOW_TYPE_RIGHT:
                case WINDOW_TYPE_BOTTOM:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_LEFT_PARTIAL:
                case WINDOW_TYPE_RIGHT_PARTIAL:
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                case WINDOW_TYPE_LION_FULL_SCREEN:
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                    break;
            }
            break;

        case PSMTab_LeftTab:
            switch ([term windowType]) {
                case WINDOW_TYPE_COMPACT:
                case WINDOW_TYPE_NO_TITLE_BAR: {
                    [[term window] setFrameTopLeftPoint:point];
                    break;
                }

                case WINDOW_TYPE_ACCESSORY:
                case WINDOW_TYPE_NORMAL: {
                    CGFloat contentHeight = [term.window contentRectForFrameRect:NSMakeRect(0, 0, 100, 100)].size.height;
                    CGFloat titleBarHeight = 100 - contentHeight;
                    point.y += titleBarHeight;
                    [[term window] setFrameTopLeftPoint:point];
                    break;
                }
                case WINDOW_TYPE_MAXIMIZED:
                case WINDOW_TYPE_COMPACT_MAXIMIZED:
                case WINDOW_TYPE_TOP:
                case WINDOW_TYPE_LEFT:
                case WINDOW_TYPE_RIGHT:
                case WINDOW_TYPE_BOTTOM:
                case WINDOW_TYPE_TOP_PARTIAL:
                case WINDOW_TYPE_LEFT_PARTIAL:
                case WINDOW_TYPE_RIGHT_PARTIAL:
                case WINDOW_TYPE_BOTTOM_PARTIAL:
                case WINDOW_TYPE_LION_FULL_SCREEN:
                case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                    break;
            }
            break;
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
    PTYTab *theTab = [[[PTYTab alloc] initWithSession:session parentWindow:self] autorelease];
    [theTab setActiveSession:session];
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
    if ([iTermAdvancedSettingsModel disableTabBarTooltips]) {
        return nil;
    }
    PTYSession *session = [[aTabViewItem identifier] activeSession];
    return [NSString stringWithFormat:@"Name: %@\nProfile: %@\nCommand: %@",
            aTabViewItem.label,
            [[session profile] objectForKey:KEY_NAME],
            [session.shell originalCommand] ?: @"None"];
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem {
    if (!tabViewItem) {
        return;
    }
    [tabView selectTabViewItem:tabViewItem];
    if ([iTermAdvancedSettingsModel doubleClickTabToEdit]) {
        [self openEditTabTitleWindow];
    }
}

- (IBAction)editTabTitle:(id)sender {
    [self openEditTabTitleWindow];
}

- (void)openEditTabTitleWindow {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Set Tab Title";
    alert.informativeText = @"If this is empty, the tab takes the active session’s title. Variables and function calls enclosed in \\(…) will replaced with their evaluation.";
    NSTextField *titleTextField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24 * 3)] autorelease];
    _currentTabTitleTextFieldDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextTab]
                                                                                           passthrough:nil
                                                                                         functionsOnly:NO];
    titleTextField.delegate = _currentTabTitleTextFieldDelegate;
    titleTextField.editable = YES;
    titleTextField.selectable = YES;
    titleTextField.stringValue = self.currentTab.variablesScope.tabTitleOverrideFormat ?: @"";
    alert.accessoryView = titleTextField;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    __weak __typeof(self) weakSelf = self;
    [NSApp activateIgnoringOtherApps:YES];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        [weakSelf releaseTabTitleTextFieldDelegate];
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf setCurrentTabTitle:titleTextField.stringValue];
        }
    }];
    [titleTextField.window makeFirstResponder:titleTextField];
}

- (void)releaseTabTitleTextFieldDelegate {
    [_currentTabTitleTextFieldDelegate release];
    _currentTabTitleTextFieldDelegate = nil;
}

- (void)setCurrentTabTitle:(NSString *)title {
    [self.currentTab setTitleOverride:title];
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

// This updates the window's background color and title text color as well as the tab bar's color.
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
                [self setBackgroundColor:newTabColor];

                [_contentView setColor:newTabColor];
            } else {
                [self setBackgroundColor:nil];
                [_contentView setColor:normalBackgroundColor];
            }
            for (PTYSession *session in aTab.sessions) {
                [session.view tabColorDidChange];
            }
        }
    }
}

- (void)setBackgroundColor:(nullable NSColor *)backgroundColor {
    if (@available(macOS 10.14, *)) {
        [self setMojaveBackgroundColor:backgroundColor];
    } else {
        [self setLegacyBackgroundColor:backgroundColor];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermWindowAppearanceDidChange object:self.window];
}

- (BOOL)anyPaneIsTransparent {
    return [self.currentTab.sessions anyWithBlock:^BOOL(PTYSession *session) {
        return session.textview.transparencyAlpha < 1;
    }];
}

- (void)setMojaveBackgroundColor:(nullable NSColor *)backgroundColor NS_AVAILABLE_MAC(10_14) {
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            self.window.appearance = nil;
            break;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            break;

        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            break;
    }
    self.window.backgroundColor = self.anyPaneIsTransparent ? [NSColor clearColor] : [NSColor windowBackgroundColor];
    self.window.titlebarAppearsTransparent = [self titleBarShouldAppearTransparent];  // Keep it from showing content from other windows behind it. Issue 7108.
}

- (BOOL)titleBarShouldAppearTransparent {
    if (@available(macOS 10.14, *)) { } else {
        return [PseudoTerminal titleBarShouldAppearTransparentForWindowType:self.windowType];
    }

    switch (self.windowType) {
        case WINDOW_TYPE_LION_FULL_SCREEN:
            return [PseudoTerminal titleBarShouldAppearTransparentForWindowType:self.savedWindowType];
            break;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
            return [PseudoTerminal titleBarShouldAppearTransparentForWindowType:self.windowType];
    }
}

+ (BOOL)titleBarShouldAppearTransparentForWindowType:(iTermWindowType)windowType {
    if (@available(macOS 10.14, *)) {
        switch (iTermThemedWindowType(windowType)) {
            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_ACCESSORY:
            case WINDOW_TYPE_LION_FULL_SCREEN:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                break;

            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_COMPACT:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
                return YES;
        }
        return NO;
    } else {
        switch (iTermThemedWindowType(windowType)) {
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_ACCESSORY:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
            case WINDOW_TYPE_LION_FULL_SCREEN:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                break;

            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_COMPACT:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
                return YES;
        }
        return NO;
    }
}

- (void)setLegacyBackgroundColor:(nullable NSColor *)backgroundColor {
    BOOL darkAppearance = NO;
    if (@available(macOS 10.13, *)) {
        switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:  // fall through
                darkAppearance = NO;
                break;

            case TAB_STYLE_DARK:
            case TAB_STYLE_DARK_HIGH_CONTRAST:  // fall through
                darkAppearance = YES;
                break;

            case TAB_STYLE_COMPACT:
            case TAB_STYLE_MINIMAL:
            case TAB_STYLE_AUTOMATIC:
                break;
        }
    } else {  // 10.12 branch
        // Preserve 10.12 behavior. It can change the window title bar color so the appearance
        // is important to keep the title legible. This adds the weird behavior of making the
        // toolbar look buggy when there's a single tab with no visible tabbar and a dark tab
        // color. It's likely 10.12 support will be dropped before I have time to fix this, alas.
        if (backgroundColor == nil && [iTermAdvancedSettingsModel darkThemeHasBlackTitlebar]) {
            switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
                case TAB_STYLE_LIGHT:
                case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                case TAB_STYLE_COMPACT:
                case TAB_STYLE_MINIMAL:
                case TAB_STYLE_AUTOMATIC:
                    break;

                case TAB_STYLE_DARK:  // fall through
                case TAB_STYLE_DARK_HIGH_CONTRAST:
                    // the key/active status is ignored on 10.12
                    backgroundColor = [PSMDarkTabStyle tabBarColorWhenMainAndActive:NO];
                    break;
            }
        }
        darkAppearance = (backgroundColor != nil && backgroundColor.perceivedBrightness < 0.5);
    }
    [self.window setBackgroundColor:backgroundColor];
    if (darkAppearance) {
        self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    } else {
        self.window.appearance = nil;
    }
    [_contentView.toolbelt windowBackgroundColorDidChange];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermTabDidChangePositionInWindowNotification object:nil];
    for (PTYSession *session in self.allSessions) {
        [session didMoveSession];
    }
}

- (PTYTabView *)tabView
{
    return _contentView.tabView;
}

static CGFloat iTermDimmingAmount(PSMTabBarControl *tabView) {
    if (tabView.window.isKeyWindow) {
        return 0;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows]) {
        return 0;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyDimOnlyText]) {
        return 0;
    }
    CGFloat value = [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount];
    CGFloat clamped = MAX(MIN(0.9, value), 0);
    return clamped;
}

- (id)tabView:(PSMTabBarControl *)tabView valueOfOption:(PSMTabBarControlOptionKey)option {
    if ([option isEqualToString:PSMTabBarControlOptionColoredSelectedTabOutlineStrength]) {
        return @([iTermAdvancedSettingsModel coloredSelectedTabOutlineStrength]);
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalStyleBackgroundColorDifference]) {
        return @([iTermAdvancedSettingsModel minimalTabStyleBackgroundColorDifference]);
    } else if ([option isEqualToString:PSMTabBarControlOptionColoredUnselectedTabTextProminence]) {
        return @([iTermAdvancedSettingsModel coloredUnselectedTabTextProminence]);
    } else if ([option isEqualToString:PSMTabBarControlOptionColoredMinimalOutlineStrength]) {
        return @([iTermAdvancedSettingsModel minimalTabStyleOutlineStrength]);
    } else if ([option isEqualToString:PSMTabBarControlOptionDimmingAmount]) {
        return @(iTermDimmingAmount(tabView));
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab]) {
        return @([iTermAdvancedSettingsModel minimalTabStyleTreatLeftInsetAsPartOfFirstTab]);
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimumSpaceForLabel]) {
        return @([iTermAdvancedSettingsModel minimumTabLabelWidth]);
    } else if ([option isEqualToString:PSMTabBarControlOptionHighVisibility]) {
        return @([iTermAdvancedSettingsModel highVisibility]);
    } else if ([option isEqualToString:PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar]) {
        return @([iTermAdvancedSettingsModel drawBottomLineForHorizontalTabBar]);
    }
    return nil;
}

- (void)tabViewDidClickAddTabButton:(PSMTabBarControl *)tabView {
    if (self.currentSession.isTmuxClient) {
        [self newTmuxTab:nil];
    } else {
        [[iTermController sharedInstance] launchBookmark:nil
                                              inTerminal:self
                                      respectTabbingMode:NO];
    }
}

- (BOOL)themeSupportsAlternateDragModes {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            return YES;
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_DARK:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
        case TAB_STYLE_AUTOMATIC:
            return NO;
    }
    assert(NO);
}

- (BOOL)tabViewShouldDragWindow:(NSTabView *)tabView {
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0) {
        // Pressing option converts drag to window drag.
        return YES;
    }

    // Consider automatic conversion.
    if (![self themeSupportsAlternateDragModes]) {
        // Never convert to window drag in traditional themes.
        return NO;
    }
    if (_contentView.tabBarControl.numberOfVisibleTabs > 1) {
        // Otherwise we won't consider doing it automatically with multiple tabs.
        return NO;
    }
    if (![iTermAdvancedSettingsModel convertTabDragToWindowDragForSolitaryTabInCompactOrMinimalTheme]) {
        // And if the user has disabled it, then we don't do it automatically.
        return NO;
    }
    // Convert drag of a solitary tab into a window drag.
    return YES;
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

- (NSColor *)accessoryTextColorForMini:(BOOL)mini {
    if (mini) {
        return [self.currentSession textColorForStatusBar];
    }
    if ([_contentView.tabBarControl isHidden] && ![self anyFullScreen]) {
        return [NSColor controlTextColor];
    } else {
        return [_contentView.tabBarControl accessoryTextColor];
    }
}

- (void)openPasswordManagerToAccountName:(NSString *)name
                               inSession:(PTYSession *)session {
    DLog(@"openPasswordManagerToAccountName:%@ inSession:%@", name, session);
    if (session && !session.canOpenPasswordManager) {
        DLog(@"Can't open password manager right now");
        return;
    }
    if (_passwordManagerWindowController != nil) {
        DLog(@"Password manager sheet already open");
        return;
    }
    [session reveal];
    DLog(@"Show the password manager as a sheet");
    _passwordManagerWindowController.delegate = nil;
    [_passwordManagerWindowController autorelease];
    _passwordManagerWindowController = [[iTermPasswordManagerWindowController alloc] init];
    _passwordManagerWindowController.delegate = self;

    [self.window beginSheet:[_passwordManagerWindowController window] completionHandler:^(NSModalResponse returnCode) {
        [[_passwordManagerWindowController window] close];
        [_passwordManagerWindowController autorelease];
        _passwordManagerWindowController = nil;
    }];

    [_passwordManagerWindowController selectAccountName:name];
}

- (void)tabDidClearScrollbackBufferInSession:(PTYSession *)session {
    [[_contentView.toolbelt capturedOutputView] removeSelection];
    [[_contentView.toolbelt commandHistoryView] removeSelection];
    [self refreshTools];
}

- (void)genericCloseSheet:(NSWindow *)sheet
               returnCode:(int)returnCode
              contextInfo:(id)contextInfo {
    [sheet close];
    [sheet release];
}

- (void)openPopupWindow:(iTermPopupWindowController *)popupWindowController {
    _openingPopupWindow = YES;
    [popupWindowController popWithDelegate:[self currentSession]];
    _openingPopupWindow = NO;
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

- (long long)instantReplayTimestampAfter:(long long)timestamp {
    DVR* dvr = [[self currentSession] dvr];
    return [dvr firstTimestampAfter:timestamp];
}

- (void)instantReplayExportFrom:(long long)start to:(long long)end {
    [iTermRecordingCodec exportRecording:self.currentSession.liveSession from:start to:end];
}

- (void)replaceSyntheticActiveSessionWithLiveSessionIfNeeded {
    if (self.currentSession.liveSession.screen.dvr.readOnly) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self close];
        });
    }
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

- (BOOL)closeInstantReplay:(id)sender orTerminateSession:(BOOL)orTerminateSession {
    if (!self.currentSession.liveSession.screen.dvr.readOnly) {
        [self closeInstantReplayWindow];
        return YES;
    } else if (orTerminateSession) {
        [self closeInstantReplay:self orTerminateSession:NO];
        [self closeSession:sender];
        return YES;
    } else {
        return NO;
    }
}

- (void)fitWindowToTab:(PTYTab*)tab
{
    [self fitWindowToTabSize:[tab size]];
}

- (PTYSession *)syntheticSessionForSession:(PTYSession *)oldSession {
    NSTabViewItem *tabViewItem = [_contentView.tabView selectedTabViewItem];
    if (!tabViewItem) {
        return nil;
    }
    PTYSession *newSession;

    // Initialize a new session
    Profile *profile = [self profileForNewSessionPreferringProfile:oldSession.profile];
    newSession = [[[PTYSession alloc] initSynthetic:YES] autorelease];
    // NSLog(@"New session for IR view is at %p", newSession);

    // set our preferences
    newSession.profile = profile;

    [[newSession screen] setMaxScrollbackLines:0];
    [self setupSession:newSession withSize:nil];
    [[newSession view] setViewId:[[oldSession view] viewId]];
    [[newSession view] setShowTitle:[[oldSession view] showTitle] adjustScrollView:YES];
    [[newSession view] setShowBottomStatusBar:oldSession.view.showBottomStatusBar adjustScrollView:YES];

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

- (IBAction)captureNextMetalFrame:(id)sender {
    if (@available(macOS 10.11, *)) {
        self.currentSession.overrideGlobalDisableMetalWhenIdleSetting = YES;
        [self.currentTab updateUseMetal];
        self.currentSession.view.driver.captureDebugInfoForNextFrame = YES;
        self.currentSession.overrideGlobalDisableMetalWhenIdleSetting = NO;
        [self.currentSession.view setNeedsDisplay:YES];
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
                                           sub.range.coordRange.end.y - sub.range.coordRange.start.y + 1)
                     inSession:session];
    }
}


- (IBAction)toggleCopyMode:(id)sender {
    PTYSession *session = self.currentSession;
    session.copyMode = !session.copyMode;
}

- (IBAction)copyModeShortcuts:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/documentation-copymode.html"]];
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

- (void)windowPerformMiniaturize:(id)sender {
    DLog(@"windowPerformMiniaturize: %@\n%@", self, [NSThread callStackSymbols]);
    [[self window] performMiniaturize:sender];
}

- (void)windowDeminiaturize:(id)sender {
    DLog(@"windowDeminiaturize: %@\n%@", self, [NSThread callStackSymbols]);
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

- (BOOL)windowIsMiniaturized {
    const BOOL result = [[self window] isMiniaturized];
    DLog(@"windowIsMiniaturized returning %@", @(result));
    return result;
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
        [self splitVertically:vertical withBookmarkGuid:guid synchronous:NO];
    }
}

- (IBAction)stopCoprocess:(id)sender
{
    [[self currentSession] stopCoprocess];
}

- (IBAction)runCoprocess:(id)sender {
    [self.window beginSheet:coprocesssPanel_ completionHandler:nil];

    NSArray *mru = [Coprocess mostRecentlyUsedCommands];
    [coprocessCommand_ removeAllItems];
    if (mru.count) {
        [coprocessCommand_ addItemsWithObjectValues:mru];
    }
    [coprocessIgnoreErrors_ setState:[Coprocess shouldIgnoreErrorsFromCommand:coprocessCommand_.stringValue] ? NSOnState : NSOffState];
    [NSApp runModalForWindow:coprocesssPanel_];

    [self.window endSheet:coprocesssPanel_];
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
        [Coprocess setSilentlyIgnoreErrors:[coprocessIgnoreErrors_ state] == NSOnState fromCommand:[coprocessCommand_ stringValue]];
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
    [self openPopupWindow:pbHistoryView];
}

- (IBAction)openCommandHistory:(id)sender
{
    if (!commandHistoryPopup) {
        commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] init];
    }
    if ([[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        [self openPopupWindow:commandHistoryPopup];
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
        [self openPopupWindow:_directoriesPopupWindowController];
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

- (BOOL)wantsCommandHistoryUpdatesFromSession:(PTYSession *)session {
    if ([session.guid isEqualToString:self.autoCommandHistorySessionGuid]) {
        return YES;
    }
    if (_autocompleteCandidateListItem && session == self.currentSession) {
        return YES;
    }
    return NO;
}

// NOTE: If you change the conditions under which action is taken here also
// update wantsCommandHistoryUpdatesFromSession:
- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix inSession:(PTYSession *)session popIfNeeded:(BOOL)popIfNeeded {
    if ([session.guid isEqualToString:self.autoCommandHistorySessionGuid]) {
        if (!commandHistoryPopup) {
            commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] init];
        }
        NSArray<iTermCommandHistoryCommandUseMO *> *commands = [commandHistoryPopup commandsForHost:[session currentHost]
                                                                                     partialCommand:prefix
                                                                                             expand:NO];
        if (commands.count) {
            if (popIfNeeded) {
                [commandHistoryPopup popWithDelegate:session];
            }
        } else {
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
    if (_autocompleteCandidateListItem && session == self.currentSession) {
        iTermShellHistoryController *history = [iTermShellHistoryController sharedInstance];
        NSArray<NSString *> *commands = [[history commandHistoryEntriesWithPrefix:prefix onHost:[session currentHost]] mapWithBlock:^id(iTermCommandHistoryEntryMO *anObject) {
            return anObject.command;
        }];
        [_autocompleteCandidateListItem setCandidates:commands ?: @[]
                                     forSelectedRange:NSMakeRange(0, prefix.length)
                                             inString:prefix];
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
        [self updateAutoCommandHistoryForPrefix:[session currentCommand] inSession:session popIfNeeded:YES];
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
        [self openPopupWindow:autocompleteView];
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
    NSSize newSessionSize = NSMakeSize(charSize.width * kVT100ScreenMinColumns + [iTermAdvancedSettingsModel terminalMargin] * 2,
                                       charSize.height * kVT100ScreenMinRows + [iTermAdvancedSettingsModel terminalVMargin] * 2);

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
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:nil
                                      respectTabbingMode:NO];
    }
}

- (void)newTabWithBookmarkGuid:(NSString *)guid {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [[iTermController sharedInstance] launchBookmark:bookmark
                                              inTerminal:self
                                      respectTabbingMode:NO];
    }
}


- (void)recreateTab:(PTYTab *)tab
    withArrangement:(NSDictionary *)arrangement
           sessions:(NSArray *)sessions
             revive:(BOOL)revive {
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
            if (revive) {
                [session revive];
            }
            [self addRevivedSession:session];
        }
        return;
    }
    if (revive) {
        for (PTYSession *session in sessions) {
            assert([session revive]);
        }
    }

    PTYSession *originalActiveSession = [tab activeSession];
    PTYTab *temporaryTab = [PTYTab tabWithArrangement:arrangement
                                           inTerminal:nil
                                      hasFlexibleView:NO
                                              viewMap:nil
                                           sessionMap:theMap
                                       tmuxController:nil];
    [tab replaceWithContentsOfTab:temporaryTab];
    [tab updatePaneTitles];
    [tab setActiveSession:nil];
    [tab setActiveSession:originalActiveSession];
}

- (void)addTabWithArrangement:(NSDictionary *)arrangement
                     uniqueId:(int)tabUniqueId
                     sessions:(NSArray *)sessions
                 predecessors:(NSArray *)predecessors {
    DLog(@"construct session map with sessions: %@\nArrangement:\n%@", sessions, arrangement);
    NSDictionary<NSString *, PTYSession *> *sessionMap = [PTYTab sessionMapWithArrangement:arrangement
                                                                                  sessions:sessions];
    if (!sessionMap) {
        DLog(@"Failed to create a session map");
        // Can't do it. Just add each session as its own tab.
        for (PTYSession *session in sessions) {
            DLog(@"Revive %@", session);
            if ([session revive]) {
                DLog(@"Succeeded. Add revived session as a tab");
                [self addRevivedSession:session];
            }
        }
        return;
    }

    DLog(@"Creating a tab to receive the arrangement");
    PTYTab *tab = [PTYTab tabWithArrangement:arrangement
                                  inTerminal:self
                             hasFlexibleView:NO
                                     viewMap:nil
                                  sessionMap:sessionMap
                              tmuxController:nil];
    tab.uniqueId = tabUniqueId;
    for (NSString *theKey in sessionMap) {
        PTYSession *session = sessionMap[theKey];
        DLog(@"Revive %@", session);
        assert([session revive]);  // TODO: This isn't guaranteed
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

- (PTYSession *)splitVertically:(BOOL)isVertical
                    withProfile:(Profile *)profile
                    synchronous:(BOOL)synchronous {
    return [self splitVertically:isVertical
                    withBookmark:profile
                   targetSession:[self currentSession]
                     synchronous:synchronous];
}

- (PTYSession *)splitVertically:(BOOL)isVertical
               withBookmarkGuid:(NSString *)guid
                    synchronous:(BOOL)synchronous {
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (profile) {
        return [self splitVertically:isVertical
                         withProfile:profile
                         synchronous:synchronous];
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
    PTYTab *tab = [self tabForSession:targetSession] ?: [self currentTab];
    [tab splitVertically:isVertical
              newSession:newSession
                  before:before
           targetSession:targetSession];
    SessionView *sessionView = newSession.view;
    scrollView = sessionView.scrollview;
    NSSize size = [sessionView frame].size;
    if (performSetup) {
        [self setupSession:newSession withSize:&size];
        scrollView = [[[newSession view] subviews] objectAtIndex:0];
    } else {
        [newSession setScrollViewDocumentView];
    }
    // Move the scrollView created by PTYSession into sessionView.
    [scrollView retain];
    [scrollView removeFromSuperview];
    [sessionView addSubviewBelowFindView:scrollView];
    [scrollView release];
    if (!performSetup) {
        [scrollView setFrameSize:[sessionView frame].size];
    }
    [self fitTabsToWindow];

    if (targetSession == [[self currentTab] activeSession]) {
        if (![iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse] ||
            [iTermAdvancedSettingsModel focusNewSplitPaneWithFocusFollowsMouse]) {
            [[self currentTab] setActiveSession:newSession];
        }
    }
    [[self currentTab] recheckBlur];
    [[self currentTab] numberOfSessionsDidChange];
    [self setDimmingForSessions];
    for (PTYSession *session in self.currentTab.sessions) {
        [session.view updateDim];
    }
    if ([[ProfileModel sessionsInstance] bookmarkWithGuid:newSession.profile[KEY_GUID]]) {
        // We assign directly to isDivorced because we know the GUID is unique and in sessions
        // instance and the original guid is already set. This might be possible to do earlier,
        // but I'm afraid of introducing bugs.
        // NOTE: I'm pretty sure there's a bug where the guid somehow ceases to
        // be in the sessions instance and we assert later.
        [newSession setIsDivorced:YES
                       withDecree:[NSString stringWithFormat:@"Split vertically with guid %@",
                                   newSession.profile[KEY_GUID]]];
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

- (iTermSessionFactory *)sessionFactory {
    if (!_sessionFactory) {
        _sessionFactory = [[iTermSessionFactory alloc] init];
    }
    return _sessionFactory;
}

- (PTYSession *)splitVertically:(BOOL)isVertical
                   withBookmark:(Profile*)theBookmark
                  targetSession:(PTYSession*)targetSession
                    synchronous:(BOOL)synchronous {
    return [self splitVertically:isVertical
                          before:NO
                         profile:theBookmark
                   targetSession:targetSession
                     synchronous:synchronous
                      completion:nil];
}

- (PTYSession *)splitVertically:(BOOL)isVertical
                         before:(BOOL)before
                        profile:(Profile *)theBookmark
                  targetSession:(PTYSession *)targetSession
                    synchronous:(BOOL)synchronous
                     completion:(void (^)(BOOL))completion{
    if ([targetSession isTmuxClient]) {
        [self willSplitTmuxPane];
        [[targetSession tmuxController] selectPane:targetSession.tmuxPane];
        [[targetSession tmuxController] splitWindowPane:[targetSession tmuxPane]
                                             vertically:isVertical
                                                  scope:[[self tabForSession:targetSession] variablesScope]
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
        oldCWD = self.currentSession.currentLocalWorkingDirectoryOrInitialDirectory;
    }

    if ([[ProfileModel sessionsInstance] bookmarkWithGuid:theBookmark[KEY_GUID]]) {
        // We were given a profile that belongs to an existing divorced session.
        //
        // Don't want to have two divorced sessions with the same guid. Allocate a new sessions
        // instance bookmark with a unique GUID. The isDivorced flag gets set later,
        // by splitVertically:before:...
        NSMutableDictionary *temp = [[theBookmark mutableCopy] autorelease];
        temp[KEY_GUID] = [ProfileModel freshGuid];
        Profile *originalBookmark = targetSession.originalProfile;
        temp[KEY_ORIGINAL_GUID] = [[originalBookmark[KEY_GUID] copy] autorelease];
        [[ProfileModel sessionsInstance] addBookmark:temp];
        theBookmark = temp;
    }
    PTYSession* newSession = [[self.sessionFactory newSessionWithProfile:theBookmark] autorelease];
    [self splitVertically:isVertical
                   before:before
            addingSession:newSession
            targetSession:targetSession
             performSetup:YES];

    if (![self.sessionFactory attachOrLaunchCommandInSession:newSession
                                                   canPrompt:YES
                                                  objectType:iTermPaneObject
                                            serverConnection:nil
                                                   urlString:nil
                                                allowURLSubs:NO
                                                 environment:@{}
                                                      oldCWD:oldCWD
                                              forceUseOldCWD:NO
                                                     command:nil
                                                      isUTF8:nil
                                               substitutions:nil
                                            windowController:self
                                                 synchronous:synchronous
                                                  completion:completion]) {
        [newSession terminate];
        [[self tabForSession:newSession] removeSession:newSession];
    }
    return newSession;
}

- (Profile *)profileForSplittingCurrentSession {
    return [self.currentSession profileForSplit] ?: [[ProfileModel sharedInstance] defaultBookmark];
}

- (IBAction)splitVertically:(id)sender {
    [self splitVertically:YES
             withBookmark:[self profileForSplittingCurrentSession]
            targetSession:[[self currentTab] activeSession]
              synchronous:NO];
}

- (IBAction)splitHorizontally:(id)sender {
    [self splitVertically:NO
             withBookmark:[self profileForSplittingCurrentSession]
            targetSession:[[self currentTab] activeSession]
              synchronous:NO];
}

- (void)tabActiveSessionDidChange {
    if (self.autoCommandHistorySessionGuid) {
        [self hideAutoCommandHistory];
    }
    [[_contentView.toolbelt commandHistoryView] updateCommands];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded] && ![iTermAdvancedSettingsModel pinEditSession]) {
        [self editSession:self.currentSession makeKey:NO];
    }
    if ([iTermAdvancedSettingsModel clearBellIconAggressively]) {
        [self.currentSession setBell:NO];
    }
    [self updateTouchBarIfNeeded:NO];
    [self updateProxyIcon];
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle == TAB_STYLE_MINIMAL) {
        [self.contentView setNeedsDisplay:YES];
        [self.tabBarControl setNeedsDisplay:YES];
    }
    [self updateForTransparency:self.ptyWindow];
    [_contentView layoutIfStatusBarChanged];
}

- (void)fitWindowToTabs {
    [self fitWindowToTabsExcludingTmuxTabs:NO preservingHeight:NO];
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux {
    [self fitWindowToTabsExcludingTmuxTabs:excludeTmux preservingHeight:NO];
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux preservingHeight:(BOOL)preserveHeight {
    _windowNeedsInitialSize = NO;
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
    NSNumber *preferredHeight = preserveHeight ? @(self.window.frame.size.height) : nil;
    if (![self fitWindowToTabSize:maxTabSize preferredHeight:preferredHeight]) {
        // Sometimes the window doesn't resize but widgets need to be moved. For example, when toggling
        // the scrollbar.
        [self repositionWidgets];
    }
}

- (BOOL)fitWindowToTabSize:(NSSize)tabSize {
    return [self fitWindowToTabSize:tabSize preferredHeight:nil];
}

// NOTE: The preferred height is respected only if it would be larger than the height the window would
// otherwise be set to and is less than the max height (self.maxFrame.size.height).
- (BOOL)fitWindowToTabSize:(NSSize)tabSize preferredHeight:(NSNumber *)preferredHeight {
    PtyLog(@"fitWindowToTabSize:%@ preferredHeight:%@", NSStringFromSize(tabSize), preferredHeight);
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

    if (preferredHeight && preferredHeight.doubleValue > winSize.height) {
        DLog(@"Respecting preferred height %@", preferredHeight);
        winSize.height = preferredHeight.doubleValue;
    } else {
        DLog(@"Ignoring preferred height %@ with winSize.height %@", preferredHeight, @(winSize.height));
    }

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
    BOOL workAroundBugFix = YES;
    if (@available(macOS 10.14, *)) {
        if (_shortcutAccessoryViewController) {
            workAroundBugFix = NO;
        }
    }
    if (workAroundBugFix) {
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
    }

    // Set the frame for X-of-screen windows. The size doesn't change
    // for _PARTIAL window types.
    DLog(@"fitWindowToTabSize using screen number %@ with frame %@", @([[NSScreen screens] indexOfObject:self.screen]),
         NSStringFromRect(self.screen.frame));

    // Update the frame for the window style, but don't mess with the size we've computed except
    // as needed (e.g., for edge-spanning x-of-screen windows).
    frame = [self canonicalFrameForScreen:self.screen windowFrame:frame preserveSize:YES];

    BOOL didResize = NSEqualRects([[self window] frame], frame);
    DLog(@"Set window frame to %@", NSStringFromRect(frame));

    self.contentView.autoresizesSubviews = NO;
    _windowDidResize = NO;
    DLog(@"Call self.window.setFrame:%@", NSStringFromRect(frame));
    [[self window] setFrame:frame display:YES];
    self.contentView.autoresizesSubviews = YES;
    if (_windowDidResize) {
        // This is mostly paranoia. Showing or hiding the tabbar causes this
        // method to be called. When the window is resized, the tabbar hasn't
        // been added yet so everything grows because of autoresizing. Then,
        // windowDidResize: gets called and it does layoutSubviews. That causes
        // everything to return to the proper size. In order to avoid this
        // problem, I want the layout to be updated explicitly via
        // layoutSubviews only. That *ought* to happen in windowDidResize:. But
        // I do not trust Cocoa, so this is a backstop to ensure we don't end
        // up with a screwy layout in case it doesn't get called in som edge
        // case.
        DLog(@"Using backstop - windowDidResize DID NOT RUN");
        [self repositionWidgets];
    }

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

- (IBAction)movePaneDividerRight:(id)sender {
    [[self currentTab] moveCurrentSessionDividerBy:1
                                      horizontally:YES];
}

- (IBAction)movePaneDividerLeft:(id)sender {
    [[self currentTab] moveCurrentSessionDividerBy:-1
                                      horizontally:YES];
}

- (IBAction)movePaneDividerDown:(id)sender {
    [[self currentTab] moveCurrentSessionDividerBy:1
                                      horizontally:NO];
}

- (IBAction)movePaneDividerUp:(id)sender {
    [[self currentTab] moveCurrentSessionDividerBy:-1
                                      horizontally:NO];
}

- (void)swapPaneLeft
{
    PTYSession* session = [[self currentTab] sessionLeftOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (void)swapPaneRight
{
    PTYSession* session = [[self currentTab] sessionRightOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (void)swapPaneUp
{
    PTYSession* session = [[self currentTab] sessionAbove:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (void)swapPaneDown
{
    PTYSession* session = [[self currentTab] sessionBelow:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
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

- (void)addTabAtAutomaticallyDeterminedLocation:(PTYTab *)tab {
    if ([iTermAdvancedSettingsModel addNewTabAtEndOfTabs] || ![self currentTab]) {
        [self insertTab:tab atIndex:self.numberOfTabs];
    } else {
        [self insertTab:tab atIndex:[self indexOfTab:self.currentTab] + 1];
        if (tab.isTmuxTab) {
            [self tabsDidReorder];
        }
    }
}

- (NSArray<PTYTab *> *)tabs {
    int n = [_contentView.tabView numberOfTabViewItems];
    NSMutableArray<PTYTab *> *tabs = [NSMutableArray arrayWithCapacity:n];
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

- (BroadcastMode)broadcastMode {
    return _broadcastInputHelper.broadcastMode;
}

- (void)setBroadcastingSessions:(NSArray<PTYSession *> *)sessions {
    _broadcastInputHelper.broadcastSessionIDs = [NSSet setWithArray:[sessions mapWithBlock:^id(PTYSession *session) {
        return session.guid;
    }]];
}

- (void)setBroadcastMode:(BroadcastMode)mode {
    _broadcastInputHelper.broadcastMode = mode;
}

- (void)toggleBroadcastingInputToSession:(PTYSession *)session {
    [_broadcastInputHelper toggleSession:session.guid];
}

- (void)setSplitSelectionMode:(BOOL)mode excludingSession:(PTYSession *)session move:(BOOL)move {
    // Things would get really complicated if you could do this in IR, so just
    // close it.
    [self closeInstantReplay:nil orTerminateSession:NO];
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

- (IBAction)moveTabLeft:(id)sender {
    NSInteger selectedIndex = [_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]];
    NSInteger destinationIndex = selectedIndex - 1;
    [self moveTabAtIndex:selectedIndex toIndex:destinationIndex];
}

- (void)moveTabAtIndex:(NSInteger)selectedIndex toIndex:(NSInteger)destinationIndex {
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

- (IBAction)moveTabRight:(id)sender {
    NSInteger selectedIndex = [_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]];
    NSInteger destinationIndex = (selectedIndex + 1) % [_contentView.tabView numberOfTabViewItems];
    [self moveTabAtIndex:selectedIndex toIndex:destinationIndex];
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

// This adjusts the window size to fit tabs by requesting tabs to compute their "ideal" size. The
// ideal size is the smallest size that fits all panes without requiring any to shrink, although some
// may need to grow. For tmux tabs, their existing sizes are preserved exactly and the window grows
// as needed (probably leaving "holes" if there are split panes present).
- (void)fitWindowToIdealizedTabsPreservingHeight:(BOOL)preserveHeight {
    for (PTYTab *aTab in [self tabs]) {
        [aTab setReportIdealSizeAsCurrent:YES];
        if ([aTab isTmuxTab]) {
            [aTab reloadTmuxLayout];
        }
    }
    [self fitWindowToTabsExcludingTmuxTabs:NO preservingHeight:preserveHeight];
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

- (void)updateWindowNumberVisibility:(NSNotification *)aNotification {
    // This is if displaying of window number was toggled in prefs.
    if (@available(macOS 10.14, *)) {
        if (_shortcutAccessoryViewController) {
            _shortcutAccessoryViewController.view.hidden = ![iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber];
        } else {
            [self setWindowTitle];
        }
    } else {
        [self setWindowTitle];
        [_contentView layoutSubviews];
    }
}

- (void)scrollerStyleDidChange:(NSNotification *)notification {
    DLog(@"scrollerStyleDidChange");
    [self updateSessionScrollbars];
    if ([self anyFullScreen]) {
        [self fitTabsToWindow];
    } else {
        // The scrollbar has already been added so tabs' current sizes are wrong.
        // Use ideal sizes instead, to fit to the session dimensions instead of
        // the existing pixel dimensions of the tabs.
        [self fitWindowToTabsExcludingTmuxTabs:NO preservingHeight:YES];
    }
}

- (void)updateWindowType {
    if (self.windowType == _windowType) {
        return;
    }
    // -updateWindowForWindowType: assigns a new contentView which causes
    // -viewDidChangeEffectiveAppearance to be called, which eventually calls back into this method.
    // Then cocoa 💩s when you try to change the content view from within setContentView:.
    if (_updatingWindowType) {
        return;
    }
    assert(_windowType == WINDOW_TYPE_NORMAL ||
           _windowType == WINDOW_TYPE_COMPACT ||
           _windowType == WINDOW_TYPE_MAXIMIZED ||
           _windowType == WINDOW_TYPE_COMPACT_MAXIMIZED);
    assert(self.windowType == WINDOW_TYPE_NORMAL ||
           self.windowType == WINDOW_TYPE_COMPACT ||
           self.windowType == WINDOW_TYPE_MAXIMIZED ||
           self.windowType == WINDOW_TYPE_COMPACT_MAXIMIZED);

    _updatingWindowType = YES;
    [self updateWindowForWindowType:self.windowType];
    _updatingWindowType = NO;

    _windowType = self.windowType;
}

- (void)updateWindowForWindowType:(iTermWindowType)windowType {
    if (_willClose) {
        return;
    }
    NSRect frame = self.window.frame;
    NSString *title = [[self.window.title copy] autorelease];
    const BOOL changed = [self replaceWindowWithWindowOfType:windowType];
    [self.window setFrame:frame display:YES];
    [self.window orderFront:nil];
    [self repositionWidgets];
    self.window.title = title;

    if (changed) {
        [self forceFrame:frame];
    }
}

- (void)refreshTerminal:(NSNotification *)aNotification {
    PtyLog(@"refreshTerminal - calling fitWindowToTabs");

    if (self.windowType != _windowType) {
        [self updateWindowType];
    }
    [self updateTabBarStyle];
    [self updateProxyIcon];

    // If hiding of menu bar changed.
    if ([self fullScreen] && ![self lionFullScreen]) {
        if ([[self window] isKeyWindow]) {
            // This is only used when changing broadcast mode; otherwise, the kRefreshTerminalNotification
            // notif is never posted when this window is key.
            if (![iTermPreferences boolForKey:kPreferenceKeyUIElement] &&
                [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen]) {
                [self hideMenuBar];
            } else {
                [self showMenuBarHideDock];
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
            // Theme change affects scrollbar color.
            [aSession.textview updateScrollerForBackgroundColor];
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
            [aSession updateStatusBarStyle];
        }
    }

    // If updatePaneTitles caused any session to change dimensions, then tell tmux
    // controllers that our capacity has changed.
    if (needResize) {
        DLog(@"refreshTerminal needs resize");
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
    // Update whether the backing view is visible
    [_contentView invalidateAutomaticTabBarBackingHiding];
    // If the theme changed from light to dark make sure split pane dividers redraw.
    [_contentView.tabView setNeedsDisplay:YES];
}

- (BOOL)rootTerminalViewWindowNumberLabelShouldBeVisible {
    if (@available(macOS 10.14, *)) { } else {
        return NO;
    }
    iTermWindowType effectiveWindowType = self.windowType;
    if (exitingLionFullscreen_) {
        effectiveWindowType = self.savedWindowType;
    } else {
        if (self.lionFullScreen || togglingLionFullScreen_) {
            return NO;
        }
    }
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
        case PSMTab_TopTab:
            break;
        case PSMTab_BottomTab:
            return NO;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber]) {
        return NO;
    }
    if (iTermWindowTypeIsCompact(effectiveWindowType)) {
        return YES;
    }

    return NO;
}

- (NSColor *)rootTerminalViewTabBarBackgroundColorIgnoringTabColor:(BOOL)ignoreTabColor {
    // This is for the fake title bar and for the status bar background color.
    return [[iTermTheme sharedInstance] tabBarBackgroundColorForTabColor:ignoreTabColor ? nil : self.currentSession.tabColor
                                                                   style:_contentView.tabBarControl.style];
}

- (NSColor *)windowDecorationColor {
    if (self.currentSession.tabColor &&
        [self.tabView indexOfTabViewItem:self.tabView.selectedTabViewItem] == 0 &&
        [iTermAdvancedSettingsModel minimalTabStyleTreatLeftInsetAsPartOfFirstTab]) {
        // The window number will be displayed over the tab color.
        // Use text color of first tab when the first tab is selected.
        return [_contentView.tabBarControl.style textColorForCell:_contentView.tabBarControl.cells.firstObject];
    }
    
    // The window number will be displayed over the tabbar color. For non-key windows, use the
    // non-selected tab text color because that more closely matches the titlebar color.
    const BOOL mainAndActive = (self.window.isMainWindow && NSApp.isActive);
    NSColor *color = [_contentView.tabBarControl.style textColorDefaultSelected:mainAndActive
                                                                backgroundColor:nil
                                                     windowIsMainAndAppIsActive:mainAndActive];
    if (mainAndActive) {
        return [color colorWithAlphaComponent:0.65];
    }
    return color;
}

- (NSColor *)rootTerminalViewTabBarTextColorForWindowNumber {
    return [self windowDecorationColor];
}

- (NSColor *)rootTerminalViewTabBarTextColorForTitle {
    return [self windowDecorationColor];
}

- (void)rootTerminalViewDidChangeEffectiveAppearance {
    [self refreshTerminal:nil];
}

- (BOOL)shouldHaveTallTabBar {
    if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab) {
        return NO;
    }
    if (!iTermWindowTypeIsCompact(self.windowType) &&
        !iTermWindowTypeIsCompact(self.savedWindowType)) {
        return NO;
    }

    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle != TAB_STYLE_MINIMAL) {
        return NO;
    }
    return YES;
}

- (CGFloat)rootTerminalViewHeightOfTabBar:(iTermRootTerminalView *)sender {
    if ([self shouldHaveTallTabBar]) {
        return [iTermAdvancedSettingsModel compactMinimalTabBarHeight];
    } else {
        return [iTermAdvancedSettingsModel defaultTabBarHeight];
    }
}

- (CGFloat)rootTerminalViewStoplightButtonsOffset:(iTermRootTerminalView *)sender {
    if ([self shouldHaveTallTabBar]) {
        return ([iTermAdvancedSettingsModel compactMinimalTabBarHeight] - 25) / 2.0;
    } else {
        return 0;
    }
}

- (NSImage *)rootTerminalViewCurrentTabIcon {
    return self.currentSession.shouldShowTabGraphic ? self.currentSession.tabGraphic : nil;
}

- (BOOL)rootTerminalViewShouldRevealStandardWindowButtons {
    const iTermWindowType windowType = exitingLionFullscreen_ ? _savedWindowType : _windowType;
    switch (windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return NO;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return YES;
    }
}

- (BOOL)rootTerminalViewShouldDrawStoplightButtons {
    if (self.enteringLionFullscreen) {
        return NO;
    }
    if (self.exitingLionFullscreen) {
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_TopTab:
            case PSMTab_LeftTab:
                switch (_savedWindowType) {
                    case WINDOW_TYPE_TOP:
                    case WINDOW_TYPE_LEFT:
                    case WINDOW_TYPE_RIGHT:
                    case WINDOW_TYPE_BOTTOM:
                    case WINDOW_TYPE_TOP_PARTIAL:
                    case WINDOW_TYPE_LEFT_PARTIAL:
                    case WINDOW_TYPE_NO_TITLE_BAR:
                    case WINDOW_TYPE_RIGHT_PARTIAL:
                    case WINDOW_TYPE_BOTTOM_PARTIAL:
                    case WINDOW_TYPE_LION_FULL_SCREEN:
                    case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
                    case WINDOW_TYPE_NORMAL:
                    case WINDOW_TYPE_MAXIMIZED:
                    case WINDOW_TYPE_ACCESSORY:
                        return NO;
                    case WINDOW_TYPE_COMPACT:
                    case WINDOW_TYPE_COMPACT_MAXIMIZED:
                        return YES;
                }
            case PSMTab_BottomTab:
                return NO;
        }
        return NO;
    }
    if (self.anyFullScreen) {
        return NO;
    }
    return iTermWindowTypeIsCompact(self.windowType);
}

- (iTermStatusBarViewController *)rootTerminalViewSharedStatusBarViewController {
    if ([self useSeparateStatusbarsPerPane]) {
        return nil;
    }
    return self.currentSession.statusBarViewController;
}

- (BOOL)rootTerminalViewWindowHasFullSizeContentView {
    return [PseudoTerminal windowTypeHasFullSizeContentView:self.windowType];
}

- (BOOL)rootTerminalViewShouldLeaveEmptyAreaAtTop {
    if ([PseudoTerminal windowTypeHasFullSizeContentView:self.windowType]) {
        return YES;
    }
    if (!self.anyFullScreen) {
        return NO;
    }
    BOOL topTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab);
    if (!topTabBar) {
        return NO;
    }
    if ([PseudoTerminal windowTypeHasFullSizeContentView:self.savedWindowType]) {
        // The tab bar is not a titlebar accessory
        return YES;
    }
    return NO;
}

// Generally yes, but not when a fake titlebar is shown *and* the window has transparency.
// Fake titlebars need a background because transparent windows won't give you one for free.
- (BOOL)rootTerminalViewShouldHideTabBarBackingWhenTabBarIsHidden {
    if (@available(macOS 10.14, *)) { } else {
        // Doesn't matter but let's not think about 10.13 and earlier since it won't happen
        return YES;
    }
    if (![PseudoTerminal windowTypeHasFullSizeContentView:self.windowType]) {
        // No full size content view? Then there won't be a fake title bar that needs backing.
        return YES;
    }
    if (![self rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        // There is no fake title bar, so it doesn't need backing.
        return YES;
    }
    if ([self anyFullScreen]) {
        // Full screen is special w/r/t the tab bar.
        return YES;
    }
    if (![self useTransparency]) {
        // Opaque windows have a window background behind the fake title bar.
        return YES;
    }
    if (![self anyPaneIsTransparent]) {
        // Opaque windows have a window background behind the fake title bar.
        return YES;
    }
    if ([iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_MINIMAL) {
        return YES;
    }
    return NO;
}

- (VT100GridSize)rootTerminalViewCurrentSessionSize {
    PTYSession *session = self.currentSession;
    VT100GridSize size = VT100GridSizeMake(session.columns, session.rows);
    return size;
}

- (void)updateTabBarStyle {
    id<PSMTabStyle> style = [[iTermTheme sharedInstance] tabStyleWithDelegate:self
                                                          effectiveAppearance:self.window.effectiveAppearance];
    [_contentView.tabBarControl setStyle:style];
    [_contentView.tabBarControl setTabsHaveCloseButtons:[iTermPreferences boolForKey:kPreferenceKeyTabsHaveCloseButton]];

    [self updateTabColors];
    if (@available(macOS 10.14, *)) {
        [self updateTabBarControlIsTitlebarAccessoryAssumingFullScreen:(self.lionFullScreen || togglingLionFullScreen_)];
        self.tabBarControl.insets = [self tabBarInsets];

        [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
    }
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

    // If screens have separate spaces then all screens have a menu bar.
    if (currentScreen == menubarScreen || [NSScreen screensHaveSeparateSpaces]) {
        NSApplicationPresentationOptions flags = 0;
        if (currentScreen == menubarScreen) {
            DLog(@"Set flag to auto-hide dock");
            flags = NSApplicationPresentationAutoHideDock;
        }
        if (![iTermPreferences boolForKey:kPreferenceKeyUIElement] &&
            [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen]) {
            DLog(@"Set flag to auto-hide menu bar");
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

- (BOOL)enteringLionFullscreen {
    return togglingLionFullScreen_;
}

- (BOOL)exitingLionFullscreen {
    return exitingLionFullscreen_;
}

- (BOOL)isDark {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch ([self.window.effectiveAppearance it_tabStyle:preferredStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return NO;
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return YES;
    }
}

- (BOOL)shouldShowBorder {
    if (![iTermPreferences boolForKey:kPreferenceKeyShowWindowBorder]) {
        return NO;
    }
    if (@available(macOS 10.14, *)) {
        if (self.anyPaneIsTransparent) {
            return YES;
        }
        return !self.isDark;
    }
    return YES;
}

- (BOOL)haveLeftBorder {
    BOOL leftTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab);
    if (!self.shouldShowBorder) {
        return NO;
    } else if ([self anyFullScreen] ||
               self.windowType == WINDOW_TYPE_LEFT ||
               (leftTabBar && [self tabBarShouldBeVisible])) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)haveBottomBorder {
    BOOL tabBarVisible = [self tabBarShouldBeVisible];
    BOOL bottomTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_BottomTab);
    if (!self.shouldShowBorder) {
        return NO;
    }
    if ([self anyFullScreen] ||
        self.windowType == WINDOW_TYPE_BOTTOM) {
        return NO;
    }
    if (!bottomTabBar) {
        // Nothing on the bottom, so need a border.
        return YES;
    }
    if (!tabBarVisible) {
        // Invisible bottom tab bar
        return YES;
    }
    if (@available(macOS 10.14, *)) {} else {
        if (self.isDark) {
            // Dark tab style needs a border on 10.13 and earlier
            return YES;
        }
    }
    // Visible bottom tab bar with light style. It's light enough so it doesn't need a border.
    return NO;
}

- (BOOL)haveTopBorder {
    if (!self.shouldShowBorder) {
        return NO;
    }
    if (iTermWindowTypeIsCompact(self.windowType)) {
        return YES;
    }
    BOOL tabBarVisible = [self tabBarShouldBeVisible];
    BOOL topTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab);
    BOOL visibleTopTabBar = (tabBarVisible && topTabBar);
    BOOL windowTypeCompatibleWithTopBorder = (self.windowType == WINDOW_TYPE_BOTTOM ||
                                              self.windowType == WINDOW_TYPE_NO_TITLE_BAR ||
                                              self.windowType == WINDOW_TYPE_BOTTOM_PARTIAL);
    return (!visibleTopTabBar &&
            windowTypeCompatibleWithTopBorder);
}

- (BOOL)haveRightBorderRegardlessOfScrollBar {
    if (!self.shouldShowBorder) {
        return NO;
    } else if ([self anyFullScreen] ||
               self.windowType == WINDOW_TYPE_RIGHT ) {
        return NO;
    }
    return YES;
}

- (BOOL)haveRightBorder {
    if (![self haveRightBorderRegardlessOfScrollBar]) {
        return NO;
    }
    if (![[[[self currentSession] view] scrollview] isLegacyScroller] ||
        ![self scrollbarShouldBeVisible]) {
        // hidden scrollbar
        return YES;
    } else {
        // visible scrollbar
        return NO;
    }
}

- (BOOL)shouldPlaceStatusBarOutsideTabview {
    return (![self useSeparateStatusbarsPerPane] &&
            self.currentSession.statusBarViewController != nil);
}

// Returns the size of the stuff outside the tabview.
- (NSSize)windowDecorationSize {
    NSSize decorationSize = NSZeroSize;

    if (!_contentView.tabBarControl.flashing &&
        [self tabBarShouldBeVisibleWithAdditionalTabs:tabViewItemsBeingAdded]) {
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_TopTab:
            case PSMTab_BottomTab:
                decorationSize.height += _contentView.tabBarControl.height;
                break;
            case PSMTab_LeftTab:
                if (self.tabs.count == 1 && self.tabs.firstObject.reportIdeal) {
                    // Initial setup. Do this so we can get the initial session's desired number of columns. Issue 8365.
                    decorationSize.width += _contentView.leftTabBarPreferredWidth;
                } else {
                    decorationSize.width += _contentView.leftTabBarWidth;
                }
                break;
        }
    } else if ([self rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        decorationSize.height += [self rootTerminalViewHeightOfTabBar:_contentView];
    }

    // Add 1px border
    if ([self haveLeftBorder]) {
        ++decorationSize.width;
    }
    if ([self haveRightBorder]) {
        ++decorationSize.width;
    }
    if ([self haveBottomBorder]) {
        ++decorationSize.height;
    }
    if ([self haveTopBorder] && ![self rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        ++decorationSize.height;
    }
    if (self.divisionViewShouldBeVisible) {
        ++decorationSize.height;
    }
    if ([self shouldPlaceStatusBarOutsideTabview]) {
        decorationSize.height += iTermStatusBarHeight;
    }
    return [[self window] frameRectForContentRect:NSMakeRect(0, 0, decorationSize.width, decorationSize.height)].size;
}

- (void)flagsChanged:(NSEvent *)theEvent
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermFlagsChanged"
                                                        object:theEvent
                                                      userInfo:nil];


    [_contentView.tabView cycleFlagsChanged:[theEvent it_modifierFlags]];

    NSUInteger modifierFlags = [theEvent it_modifierFlags];
    if (!(modifierFlags & NSEventModifierFlagCommand) &&
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

    _contentView.tabBarControl.cmdPressed = ((modifierFlags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand);
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
        PTYTab *tab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        for (PTYSession* session in [tab sessions]) {
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
        PTYTab *tab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        for (PTYSession* session in [tab sessions]) {
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
        PTYTab *tab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        for (PTYSession* session in [tab sessions]) {
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
        PTYTab *tab = [[_contentView.tabView tabViewItemAtIndex:i] identifier];
        for (PTYSession* session in [tab sessions]) {
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

- (Profile *)profileForNewSessionPreferringProfile:(Profile *)preferred {
    // set some default parameters
    if (preferred == nil) {
        Profile *tempPrefs = [[ProfileModel sharedInstance] defaultBookmark];
        if (tempPrefs != nil) {
            // Use the default bookmark. This path is taken with applescript's
            // "make new session at the end of sessions" command.
            return tempPrefs;
        } else {
            // get the hardcoded defaults
            NSMutableDictionary* dict = [[[NSMutableDictionary alloc] init] autorelease];
            [ITAddressBookMgr setDefaultsInBookmark:dict];
            [dict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
            return dict;
        }
    } else {
        return preferred;
    }
}

// Set the session's profile dictionary and initialize its screen and name. Sets the
// window title to the session's name. If size is not nil then the session is initialized to fit
// a view of that size; otherwise the size is derived from the existing window if there is already
// an open tab, or its bookmark's preference if it's the first session in the window.
- (void)setupSession:(PTYSession *)aSession
            withSize:(NSSize*)size {
    NSDictionary *profile;
    NSParameterAssert(aSession != nil);

    profile = aSession.profile;
    PtyLog(@"Open session with prefs: %@", profile);
    int rows = [[profile objectForKey:KEY_ROWS] intValue];
    int columns = [[profile objectForKey:KEY_COLUMNS] intValue];
    if (self.tabs.count == 0 && desiredRows_ < 0) {
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

    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[profile objectForKey:KEY_NORMAL_FONT]]
                                 horizontalSpacing:[[profile objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
                                   verticalSpacing:[[profile objectForKey:KEY_VERTICAL_SPACING] floatValue]];

    if (size == nil && [_contentView.tabView numberOfTabViewItems] != 0) {
        NSSize contentSize = [[[[self currentSession] view] scrollview] documentVisibleRect].size;
        rows = (contentSize.height - [iTermAdvancedSettingsModel terminalVMargin]*2) / charSize.height;
        columns = (contentSize.width - [iTermAdvancedSettingsModel terminalMargin]*2) / charSize.width;
    }
    NSRect sessionRect;
    if (size != nil) {
        BOOL hasScrollbar = [self scrollbarShouldBeVisible];
        NSSize contentSize =
            [NSScrollView contentSizeForFrameSize:*size
                      horizontalScrollerClass:nil
                        verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                                   borderType:NSNoBorder
                                  controlSize:NSControlSizeRegular
                                scrollerStyle:[self scrollerStyle]];
        rows = (contentSize.height - [iTermAdvancedSettingsModel terminalVMargin]*2) / charSize.height;
        columns = (contentSize.width - [iTermAdvancedSettingsModel terminalMargin]*2) / charSize.width;
        sessionRect.origin = NSZeroPoint;
        sessionRect.size = *size;
    } else {
        sessionRect = NSMakeRect(0, 0, columns * charSize.width + [iTermAdvancedSettingsModel terminalMargin] * 2, rows * charSize.height + [iTermAdvancedSettingsModel terminalVMargin] * 2);
    }

    if ([aSession setScreenSize:sessionRect parent:self]) {
        PtyLog(@"setupSession - call safelySetSessionSize");
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        PtyLog(@"setupSession - call setPreferencesFromAddressBookEntry");
        [aSession setPreferencesFromAddressBookEntry:profile];
        [aSession loadInitialColorTable];
        [aSession.screen resetTimestamps];
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
- (void)insertTab:(PTYTab*)aTab atIndex:(int)anIndex {
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
        if (self.windowInitialized && !_restoringWindow) {
            if (self.tabs.count == 1) {
                // It's important to do this before makeKeyAndOrderFront because API clients need
                // to know the window exists before learning that it has focus.
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermDidCreateTerminalWindowNotification object:self];
            }
        }
        if (self.windowInitialized && !_fullScreen && !_restoringWindow) {
            [[self window] makeKeyAndOrderFront:self];
        } else {
            PtyLog(@"window not initialized, is fullscreen, or is being restored. Stack:\n%@", [NSThread callStackSymbols]);
        }
        if (!_suppressMakeCurrentTerminal) {
            [[iTermController sharedInstance] setCurrentTerminal:self];
        }
    }
}

- (void)setRestoringWindow:(BOOL)restoringWindow {
    if (_restoringWindow != restoringWindow) {
        _restoringWindow = restoringWindow;
        if (restoringWindow) {
            self.restorableStateDecodePending = YES;
        }
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
        PTYTab *aTab = [[PTYTab alloc] initWithSession:aSession
                                          parentWindow:self];
        [aSession setIgnoreResizeNotifications:YES];
        if ([self numberOfTabs] == 0) {
            [aTab setReportIdealSizeAsCurrent:YES];
        }
        [self insertTab:aTab atIndex:anIndex];
        [aTab setReportIdealSizeAsCurrent:NO];
        [aTab release];
    }
}

- (NSString *)undecoratedWindowTitle {
    if ([self.scope valueForVariableName:iTermVariableKeyWindowTitleOverrideFormat] &&
        self.scope.windowTitleOverrideFormat.length > 0) {
        return self.scope.windowTitleOverride;
    }
    return self.currentSession.nameController.presentationWindowTitle ?: @"Untitled";
}

- (void)setName:(NSString *)theSessionName forSession:(PTYSession *)aSession {
    [aSession didInitializeSessionWithName:theSessionName];
    [aSession setSessionSpecificProfileValues:@{ KEY_NAME: theSessionName }];
}

// Assign a value to the 'uniqueNumber_' member variable which is used for storing
// window frame positions between invocations of iTerm.
- (void)assignUniqueNumberToWindow
{
    uniqueNumber_ = [[TemporaryNumberAllocator sharedInstance] allocateNumber];
}

// Reset all state associated with the terminal.
- (void)reset:(id)sender {
    [[[self currentSession] terminal] resetByUserRequest:YES];
    [[self currentSession] updateDisplayBecause:@"reset terminal"];
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

- (IBAction)saveContents:(id)sender {
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyyMMMd"
                                                               options:0
                                                                locale:[NSLocale currentLocale]];
    NSDateFormatter *timeFormatter = [[[NSDateFormatter alloc] init] autorelease];
    timeFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"hh.mm.ss"
                                                               options:0
                                                                locale:[NSLocale currentLocale]];

    NSDate *now = [NSDate date];
    NSString *suggestedFilename = [NSString stringWithFormat:@"iTerm2 Session %@ at %@.txt",
                                   [dateFormatter stringFromDate:now],
                                   [timeFormatter stringFromDate:now]];
    iTermSavePanel *savePanel = [iTermSavePanel showWithOptions:kSavePanelOptionFileFormatAccessory
                                                     identifier:@"SaveContents"
                                               initialDirectory:NSHomeDirectory()
                                                defaultFilename:suggestedFilename
                                               allowedFileTypes:@[ @"txt", @"rtf" ]];
    if (savePanel.path) {
        NSURL *url = [NSURL fileURLWithPath:savePanel.path];
        if (url) {
            if ([[url pathExtension] isEqualToString:@"rtf"]) {
                NSAttributedString *attributedString = [self.currentSession.textview contentWithAttributes:YES];
                NSData *data = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                            documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType}
                                                         error:NULL];
                [data writeToFile:url.path atomically:YES];
            } else {
                [[self.currentSession.textview content] writeToFile:url.path atomically:NO encoding:NSUTF8StringEncoding error:nil];
            }
        }
    }
}

- (IBAction)exportRecording:(id)sender {
    [iTermRecordingCodec exportRecording:self.currentSession];
}

// Turn on session logging in the current session.
- (IBAction)logStart:(id)sender
{
    if (![[self currentSession] logging]) {
        [[self retain] autorelease];  // Prevent self from getting dealloc'ed during modal panel.
        [[self currentSession] logStart];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionBecameKey
                                                        object:[self currentSession]];
}

// Turn off session logging in the current session.
- (IBAction)logStop:(id)sender {
    if ([[self currentSession] logging]) {
        [[self currentSession] logStop];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionBecameKey
                                                        object:[self currentSession]];
}

- (void)addRevivedSession:(PTYSession *)session {
    [self insertSession:session atIndex:[self numberOfTabs]];
    [[self currentTab] numberOfSessionsDidChange];
}


// Returns true if the given menu item is selectable.
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    BOOL logging = [[self currentSession] logging];
    BOOL result = YES;

    if ([item action] == @selector(detachTmux:) ||
        [item action] == @selector(newTmuxWindow:) ||
        [item action] == @selector(newTmuxTab:) ||
        [item action] == @selector(forceDetachTmux:)) {
        return [[iTermController sharedInstance] haveTmuxConnection];
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
    } else if ([item action] == @selector(editTabTitle:)) {
        return self.numberOfTabs > 0;
    } else if ([item action] == @selector(moveTabLeft:)) {
        result = [_contentView.tabView numberOfTabViewItems] > 1;
    } else if ([item action] == @selector(moveTabRight:)) {
        result = [_contentView.tabView numberOfTabViewItems] > 1;
    } else if ([item action] == @selector(toggleBroadcastingToCurrentSession:)) {
        result = ![[self currentSession] exited];
    } else if (item.action == @selector(enableSendInputToAllTabs:)) {
        item.state = (_broadcastInputHelper.broadcastMode == BROADCAST_TO_ALL_TABS) ? NSOnState : NSOffState;
    } else if (item.action == @selector(enableSendInputToAllPanes:)) {
        item.state = (_broadcastInputHelper.broadcastMode == BROADCAST_TO_ALL_PANES) ? NSOnState : NSOffState;
    } else if (item.action == @selector(disableBroadcasting:)) {
        item.state = (_broadcastInputHelper.broadcastMode == BROADCAST_OFF) ? NSOnState : NSOffState;
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
        return [[self currentTab] canMoveCurrentSessionDividerBy:1
                                                    horizontally:NO];
    } else if ([item action] == @selector(movePaneDividerUp:)) {
        return [[self currentTab] canMoveCurrentSessionDividerBy:-1
                                                    horizontally:NO];
    } else if ([item action] == @selector(movePaneDividerRight:)) {
        return [[self currentTab] canMoveCurrentSessionDividerBy:1
                                                    horizontally:YES];
    } else if ([item action] == @selector(movePaneDividerLeft:)) {
        return [[self currentTab] canMoveCurrentSessionDividerBy:-1
                                                    horizontally:YES];
    } else if ([item action] == @selector(duplicateTab:)) {
        return ![[self currentTab] isTmuxTab];
    } else if ([item action] == @selector(saveTabAsWindowArrangement:)) {
        return YES;
    } else if ([item action] == @selector(zoomOnSelection:)) {
        return ![self inInstantReplay] && [[self currentSession] hasSelection];
    } else if ([item action] == @selector(showFindPanel:) ||
               [item action] == @selector(findPrevious:) ||
               [item action] == @selector(findNext:) ||
               [item action] == @selector(jumpToSelection:) ||
               [item action] == @selector(findUrls:)) {
        result = ([self currentSession] != nil);
    } else if ([item action] == @selector(openSelection:)) {
        result = [[self currentSession] hasSelection];
    } else if ([item action] == @selector(zoomOut:)) {
        return self.currentSession.textViewIsZoomedIn;
    } else if (item.action == @selector(captureNextMetalFrame:)) {
        return self.currentSession.canProduceMetalFramecap;
    } else if (item.action == @selector(exportRecording:)) {
        return !self.currentSession.screen.dvr.empty;
    } else if (item.action == @selector(toggleSizeChangesAffectProfile:)) {
        item.state = [iTermPreferences boolForKey:kPreferenceKeySizeChangesAffectProfile] ? NSOnState : NSOffState;
        return YES;
    } else if (item.action == @selector(performClose:)) {
        return YES;
    }

    return result;
}

- (IBAction)mergeAllWindows:(id)sender {
    for (PseudoTerminal *term in [[[[iTermController sharedInstance] terminals] copy] autorelease]) {
        if (term == self) {
            continue;
        }

        while (term.tabs.count) {
            [MovePaneController moveTab:term.tabs.firstObject toWindow:self atIndex:self.tabs.count];
        }
    }
}

- (IBAction)toggleSizeChangesAffectProfile:(id)sender {
    [iTermAdjustFontSizeHelper toggleSizeChangesAffectProfile];
}
- (IBAction)biggerFont:(id)sender {
    [iTermAdjustFontSizeHelper biggerFont:self.currentSession];
}
- (IBAction)smallerFont:(id)sender {
    [iTermAdjustFontSizeHelper smallerFont:self.currentSession];
}
- (IBAction)returnToDefaultSize:(id)sender {
    [iTermAdjustFontSizeHelper returnToDefaultSize:self.currentSession
                                     resetRowsCols:[sender isAlternate]];
}

- (IBAction)toggleAutoCommandHistory:(id)sender
{
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceAutoCommandHistory]
                       forKey:kPreferenceAutoCommandHistory];
}

// Turn on/off sending of input to all sessions. This causes a bunch of UI
// to update in addition to flipping the flag.
- (IBAction)enableSendInputToAllPanes:(id)sender {
    [self setBroadcastMode:BROADCAST_TO_ALL_PANES];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

- (IBAction)disableBroadcasting:(id)sender {
    [self setBroadcastMode:BROADCAST_OFF];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

// Turn on/off sending of input to all sessions. This causes a bunch of UI
// to update in addition to flipping the flag.
- (IBAction)enableSendInputToAllTabs:(id)sender {
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
    [self createDuplicateOfTab:(PTYTab *)[[sender representedObject] identifier]];
}

- (void)createDuplicateOfTab:(PTYTab *)theTab {
    if (!theTab) {
        theTab = [self currentTab];
    }
    PseudoTerminal *destinationTerminal = [[iTermController sharedInstance] windowControllerForNewTabWithProfile:self.currentSession.profile
                                                                                                       candidate:self
                                                                                              respectTabbingMode:NO];
    if (destinationTerminal == nil) {
        PTYTab *copyOfTab = [[theTab copy] autorelease];
        [copyOfTab updatePaneTitles];
        [[iTermController sharedInstance] launchBookmark:self.currentSession.profile
                                              inTerminal:nil
                                                 withURL:nil
                                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                 makeKey:YES
                                             canActivate:YES
                                      respectTabbingMode:NO
                                                 command:nil
                                                   block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
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
                                                   }
                                             synchronous:NO
                                              completion:nil];
    } else {
        [PTYTab openTabWithArrangement:self.currentTab.arrangement
                            inTerminal:self
                       hasFlexibleView:self.currentTab.isTmuxTab
                               viewMap:nil
                            sessionMap:nil];
    }
}

- (void)saveTabAsWindowArrangement:(id)sender {
    PTYTab *theTab = (PTYTab *)[[sender representedObject] identifier];
    if (!theTab) {
        theTab = [self currentTab];
    }
    NSDictionary *arrangement = [self arrangementWithTabs:@[ theTab ] includingContents:NO];
    NSString *name = [WindowArrangements nameForNewArrangement];
    if (name) {
        [WindowArrangements setArrangement:@[ arrangement ] withName:name];
    }
}

// These two methods are delicate because -closeTab: won't remove the tab from
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
- (void)moveTabToNewWindowContextualMenuAction:(id)sender {
    NSTabViewItem *aTabViewItem = [sender representedObject];
    PTYTab *aTab = [aTabViewItem identifier];
    [self it_moveTabToNewWindow:aTab];
}

- (PseudoTerminal *)it_moveTabToNewWindow:(PTYTab *)aTab {
    if (aTab == nil) {
        return nil;
    }
    if (self.tabs.count < 2) {
        return nil;
    }
    NSAssert([self.tabs containsObject:aTab], @"Called on wrong window");
    NSTabViewItem *aTabViewItem = aTab.tabViewItem;
    NSPoint point = [[self window] frame].origin;
    point.x += 10;
    point.y += 10;
    NSWindowController<iTermWindowController> *term = [self terminalDraggedFromAnotherWindowAtPoint:point];
    if (term == nil) {
        return nil;
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

    return [PseudoTerminal castFrom:term];
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
    for (PTYTab *tab in self.tabs) {
        [tab setDeferFontChanges:YES];
    }
    for (PTYSession* session in [self allSessions]) {
        Profile *oldBookmark = [session profile];
        NSString* oldName = [[[oldBookmark objectForKey:KEY_NAME] copy] autorelease];
        NSString* guid = [oldBookmark objectForKey:KEY_GUID];
        if ([session reloadProfile]) {
            [[self tabForSession:session] recheckBlur];
            NSDictionary *profile = [session profile];
            if (![[profile objectForKey:KEY_NAME] isEqualToString:oldName]) {
                [session profileNameDidChangeTo:profile[KEY_NAME]];
            }
            if ([session isDivorced] &&
                [[[PreferencePanel sessionsInstance] currentProfileGuid] isEqualToString:guid] &&
                [[PreferencePanel sessionsInstance] isWindowLoaded]) {
                [[PreferencePanel sessionsInstance] underlyingBookmarkDidChange];
            }
        }
        [session updateStatusBarStyle];
    }
    for (PTYTab *tab in self.tabs) {
        [tab setDeferFontChanges:NO];
        [tab updatePaneTitles];
    }
    if (self.isHotKeyWindow) {
        iTermProfileHotKey *profileHotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
        Profile *profile = profileHotKey.profile;
        if (profile) {
            int screenNumber = [iTermProfilePreferences intForKey:KEY_SCREEN inProfile:profile];
            _screenNumberFromFirstProfile = screenNumber;
            screenNumber = [PseudoTerminal screenNumberForPreferredScreenNumber:screenNumber
                                                                     windowType:self.windowType
                                                                  defaultScreen:[[self window] screen]];
            [self anchorToScreenNumber:screenNumber];
            DLog(@"Change hotkey window's anchored screen to %@ (isAnchored=%@) for %@",
                 @(_anchoredScreenNumber), @(_isAnchoredToScreen), self);
        }
    }
    [self updateTouchBarIfNeeded:NO];
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
        PTYTab *tab = [item identifier];
        [result addObjectsFromArray:[tab sessions]];
    }
    return result;
}

- (void)_loadFindStringFromSharedPasteboard
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                        object:nil
                                                      userInfo:nil];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}
#pragma clang diagnostic pop

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
    [_contentView.tabBarControl setAlphaValue:0 animated:NO];
    _contentView.tabBarControl.hidden = NO;
    [self repositionWidgets];
    [self updateUseMetalInAllTabs];
}

- (void)iTermTabBarDidFinishFlash {
    [_contentView.tabBarControl setAlphaValue:1 animated:NO];
    _contentView.tabBarControl.hidden = YES;
    [self repositionWidgets];
    [self updateUseMetalInAllTabs];
}

- (BOOL)iTermTabBarWindowIsFullScreen {
    return self.anyFullScreen;
}

- (BOOL)iTermTabBarCanDragWindow {
    return iTermWindowTypeIsCompact(self.windowType);
}

- (BOOL)iTermTabBarShouldHideBacking {
    if (@available(macOS 10.14, *)) {
        iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        return (preferredStyle != TAB_STYLE_MINIMAL);
    }
    return YES;
}

- (PTYSession *)createTabWithProfile:(Profile *)profile
                         withCommand:(NSString *)command
                         environment:(NSDictionary *)environment
                         synchronous:(BOOL)synchronous
                          completion:(void (^)(BOOL ok))completion {
    assert(profile);

    // Get active session's directory
    NSString *previousDirectory = nil;
    PTYSession* currentSession = [[[iTermController sharedInstance] currentTerminal] currentSession];
    if (currentSession.isTmuxClient) {
        currentSession = currentSession.tmuxGatewaySession;
    }
    if (currentSession) {
        DLog(@"Getting current local working directory");
        previousDirectory = currentSession.currentLocalWorkingDirectoryOrInitialDirectory;
    }

    iTermObjectType objectType;
    if ([_contentView.tabView numberOfTabViewItems] == 0) {
        objectType = iTermWindowObject;
    } else {
        objectType = iTermTabObject;
    }
    if (command) {
        profile = [[profile
                    dictionaryBySettingObject:@"Yes" forKey:KEY_CUSTOM_COMMAND]
                   dictionaryBySettingObject:command forKey:KEY_COMMAND_LINE];

    }

    // Initialize a new session
    PTYSession *aSession = [[self.sessionFactory newSessionWithProfile:profile] autorelease];

    // Add this session to our term and make it current
    [self addSessionInNewTab:aSession];

    [self.sessionFactory attachOrLaunchCommandInSession:aSession
                                              canPrompt:YES
                                             objectType:objectType
                                       serverConnection:nil
                                              urlString:nil
                                           allowURLSubs:NO
                                            environment:environment
                                                 oldCWD:previousDirectory
                                         forceUseOldCWD:NO
                                                command:nil
                                                 isUTF8:nil
                                          substitutions:nil
                                       windowController:self
                                            synchronous:synchronous
                                             completion:completion];

    // On Lion, a window that can join all spaces can't go fullscreen.
    if ([self numberOfTabs] == 1) {
        _spaceSetting = [profile[KEY_SPACE] intValue];
        switch (_spaceSetting) {
            case iTermProfileJoinsAllSpaces:
                self.window.collectionBehavior = [self desiredWindowCollectionBehavior];
            case iTermProfileOpenInCurrentSpace:
            default:
                break;
        }
    }

    return aSession;
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state {
    NSDictionary *arrangement = [state decodeObjectForKey:kTerminalWindowStateRestorationWindowArrangementKey];
    if ([iTermAdvancedSettingsModel logRestorableStateSize]) {
        NSString *log = [arrangement sizeInfo];
        [log writeToFile:[NSString stringWithFormat:@"/tmp/statesize.window-%p.txt", self] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
    [self loadArrangement:arrangement
                 sessions:nil];
    self.restorableStateDecodePending = NO;
}

- (void)setRestorableStateDecodePending:(BOOL)restorableStateDecodePending {
    if (_restorableStateDecodePending != restorableStateDecodePending) {
        _restorableStateDecodePending = restorableStateDecodePending;
        if (!restorableStateDecodePending) {
            [[NSNotificationCenter defaultCenter] postNotificationName:iTermDidDecodeWindowRestorableStateNotification object:self];
        }
    }
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
    if (_wellFormed) {
        [lastArrangement_ release];
        NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
        BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
        DLog(@"Encoding restorable state for %@", self);
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
    if (@available(macOS 10.14, *)) {
        return proposedOptions;
    } else {
        return proposedOptions | NSApplicationPresentationAutoHideToolbar;
    }
}

- (void)addSessionInNewTab:(PTYSession *)object {
    PtyLog(@"PseudoTerminal: -addSessionInNewTab: %p", object);
    // Increment tabViewItemsBeingAdded so that the maximum content size will
    // be calculated with the tab bar if it's about to open.
    ++tabViewItemsBeingAdded;
    [self setupSession:object withSize:nil];
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
        if ([iTermAdvancedSettingsModel pinEditSession] &&
            ![NSObject object:session.profile[KEY_GUID] isEqualToObject:[[PreferencePanel sessionsInstance] currentProfileGuid]]) {
            // Some other session closed while pinned
            return;
        }
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

- (void)moveToPreferredScreen {
    if (_screenNumberFromFirstProfile == -2) {
        // Return screen with cursor
        NSPoint cursor = [NSEvent mouseLocation];
        [[NSScreen screens] enumerateObjectsUsingBlock:^(NSScreen * _Nonnull screen, NSUInteger i, BOOL * _Nonnull stop) {
            if (NSPointInRect(cursor, screen.frame)) {
                _isAnchoredToScreen = YES;
                _anchoredScreenNumber = i;
                DLog(@"Move window to screen %d %@", (int)i, NSStringFromRect(screen.frame));
                *stop = YES;
            }
        }];
    }
}

#pragma mark - Find

- (IBAction)showFindPanel:(id)sender {
    [[self currentSession] showFindPanel];
}

// findNext and findPrevious are reversed here because in the search UI next
// goes backwards and previous goes forwards.
// Internally, next=forward and prev=backwards.
- (IBAction)findPrevious:(id)sender {
    if ([iTermAdvancedSettingsModel swapFindNextPrevious]) {
        [[self currentSession] searchNext];
    } else {
        [[self currentSession] searchPrevious];
    }
}

- (IBAction)findNext:(id)sender {
    if ([iTermAdvancedSettingsModel swapFindNextPrevious]) {
        [[self currentSession] searchPrevious];
    } else {
        [[self currentSession] searchNext];
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

- (BOOL)iTermPasswordManagerCanBroadcast {
    return self.broadcastSessions.count > 1;
}

- (void)broadcastPassword:(NSString *)password {
    [iTermBroadcastPasswordHelper tryToSendPassword:password
                                         toSessions:self.broadcastSessions
                                         completion:
     ^NSArray<PTYSession *> * _Nonnull(NSArray<PTYSession *> * _Nonnull okSessions,
                                       NSArray<PTYSession *> * _Nonnull problemSessions) {
         if (problemSessions.count == 0) {
             return okSessions;
         }
         NSArray<NSString *> *names = [problemSessions mapWithBlock:^id(PTYSession *session) {
             return session.nameController.presentationSessionTitle;
         }];
         NSString *message;
         if (names.count < 2) {
             message = [NSString stringWithFormat:@"The session named “%@” does not appear to be at a password prompt.", names.firstObject];
         } else {
             message = [NSString stringWithFormat:@"The following sessions to which input is broadcast do not appear to be at a password prompt: %@", [names componentsJoinedWithOxfordComma]];
         }
         NSArray *actions;
         if (okSessions.count > 0) {
             actions = @[ @"Cancel", @"Enter Password in Sessions at Prompt" ];
         } else {
             actions = @[ @"OK" ];
         }
         iTermWarningSelection selection = [iTermWarning showWarningWithTitle:message
                                                                      actions:actions
                                                                    accessory:nil
                                                                   identifier:nil
                                                                  silenceable:kiTermWarningTypePersistent
                                                                      heading:@"Not all sessions at password prompt"
                                                                       window:self.window];
         switch (selection) {
             case kiTermWarningSelection0:
                 return @[];
             case kiTermWarningSelection1:
                 return okSessions;
             default:
                 break;  // shouldn't happen
         }
         return @[];
     }];
}

- (void)iTermPasswordManagerEnterPassword:(NSString *)password broadcast:(BOOL)broadcast {
    if (broadcast) {
        [self broadcastPassword:password];
    } else {
        [[self currentSession] enterPassword:password];
    }
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

- (void)tab:(PTYTab *)tab proxyIconDidChange:(NSURL *)location {
    if (tab == self.currentTab) {
        [self updateProxyIcon];
    }
}

- (void)tabDidChangeGraphic:(PTYTab *)tab shouldShow:(BOOL)shouldShow image:(NSImage *)image {
    [_contentView.tabBarControl graphicDidChangeForTabWithIdentifier:tab];
    [_contentView setWindowTitleIcon:shouldShow ? image : nil];
}

- (void)tabDidChangeTmuxLayout:(PTYTab *)tab {
    [self setWindowTitle];
}

- (void)tabRemoveTab:(PTYTab *)tab {
    if ([_contentView.tabView numberOfTabViewItems] <= 1 && self.windowInitialized) {
        [[self window] close];
    } else {
        NSTabViewItem *tabViewItem = [tab tabViewItem];
        [_contentView.tabView removeTabViewItem:tabViewItem];
        PtyLog(@"tabRemoveTab - calling fitWindowToTabs");
        [self fitWindowToTabs];
    }
}

- (void)tabKeyLabelsDidChangeForSession:(PTYSession *)session {
    [self updateTouchBarFunctionKeyLabels];
}

- (void)tabSessionDidChangeBackgroundColor:(PTYTab *)tab {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle == TAB_STYLE_MINIMAL) {
        [self.contentView setNeedsDisplay:YES];
        [_contentView.tabBarControl backgroundColorWillChange];
    }
    [self updateForTransparency:self.ptyWindow];
}

- (void)tab:(PTYTab *)tab didChangeToState:(PTYTabState)newState {
    if (self.numberOfTabs == 1) {
        [self setWindowTitle];
    }
}

- (void)tab:(PTYTab *)tab didSetMetalEnabled:(BOOL)useMetal {
    _contentView.useMetal = useMetal;
}

- (BOOL)tabCanUseMetal:(PTYTab *)tab reason:(out iTermMetalUnavailableReason *)reason {
    if (_contentView.tabBarControl.flashing) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonTabBarTemporarilyVisible;
            return NO;
        }
    }
    return YES;
}

- (BOOL)tabShouldUseTransparency:(PTYTab *)tab {
    return self.useTransparency;
}

- (BOOL)tabAnyDragInProgress:(PTYTab *)tab {
    return [PSMTabBarControl isAnyDragInProgress];
}

- (void)currentSessionWordAtCursorDidBecome:(NSString *)word {
    if (word == _previousTouchBarWord || [word isEqualToString:_previousTouchBarWord]) {
        return;
    }
    [_previousTouchBarWord release];
    _previousTouchBarWord = [word copy];
    if (_touchBarRateLimitedUpdate == nil) {
        _touchBarRateLimitedUpdate = [[iTermRateLimitedIdleUpdate alloc] init];
        _touchBarRateLimitedUpdate.minimumInterval = 0.5;
    }
    [_touchBarRateLimitedUpdate performRateLimitedBlock:^{
        [self updateTouchBarWithWordAtCursor:word];
    }];
}

- (void)numberOfSessionsDidChangeInTab:(PTYTab *)tab {
    if (tab == self.currentTab) {
        [self updateUseTransparency];
    }
}

- (void)tabDidInvalidateStatusBar:(PTYTab *)tab {
    [_contentView layoutSubviews];
}

- (iTermVariables *)tabWindowVariables:(PTYTab *)tab {
    return self.variables;
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

- (void)toolbeltApplyActionToCurrentSession:(iTermAction *)action {
    [self.currentSession applyAction:action];
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

#pragma mark - NSComboBoxDelegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if ([aNotification object] == coprocessCommand_) {
        [coprocessIgnoreErrors_ setState:[Coprocess shouldIgnoreErrorsFromCommand:coprocessCommand_.stringValue] ? NSOnState : NSOffState];
    }
    if ([[self superclass] instancesRespondToSelector:_cmd]) {
        [super controlTextDidChange:aNotification];
    }
}

#pragma mark - PSMMinimalTabStyleDelegate

- (NSColor *)minimalTabStyleBackgroundColor {
    DLog(@"Getting bg color for session %@, colormap %@", self.currentSession, self.currentSession.colorMap);
    return [self.currentSession.colorMap colorForKey:kColorMapBackground];
}

#pragma mark - iTermBroadcastInputHelperDelegate

- (NSArray<NSString *> *)broadcastInputHelperSessionsInCurrentTab:(iTermBroadcastInputHelper *)helper
                                                    includeExited:(BOOL)includeExited {
    return [self.currentTab.sessions mapWithBlock:^id(PTYSession *session) {
        if (!includeExited && session.exited) {
            return nil;
        }
        return session.guid;
    }];
}

- (NSArray<NSString *> *)broadcastInputHelperSessionsInAllTabs:(iTermBroadcastInputHelper *)helper
                                                 includeExited:(BOOL)includeExited {
    return [self.allSessions mapWithBlock:^id(PTYSession *session) {
        if (!includeExited && session.exited) {
            return nil;
        }
        return session.guid;
    }];
}

- (NSString *)broadcastInputHelperCurrentSession:(iTermBroadcastInputHelper *)helper {
    return self.currentSession.guid;
}

- (void)broadcastInputHelperDidUpdate:(iTermBroadcastInputHelper *)helper {
    for (PTYTab *tab in [self tabs]) {
        for (PTYSession *session in tab.sessions) {
            [session.view setNeedsDisplay:YES];
        }
    }
    // Update dimming of panes.
    [self refreshTerminal:nil];
    [self setDimmingForSessions];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

- (BOOL)broadcastInputHelperCurrentTabIsBroadcasting:(iTermBroadcastInputHelper *)helper {
    return self.currentTab.isBroadcasting;
}

- (void)broadcastInputHelperSetNoTabBroadcasting:(iTermBroadcastInputHelper *)helper {
    for (PTYTab *tab in self.tabs) {
        tab.broadcasting = NO;
    }
}

- (void)broadcastInputHelper:(iTermBroadcastInputHelper *)helper setCurrentTabBroadcasting:(BOOL)broadcasting {
    self.currentTab.broadcasting = broadcasting;
}

- (NSWindow *)broadcastInputHelperWindowForWarnings:(iTermBroadcastInputHelper *)helper {
    return self.window;
}

#pragma mark - iTermObject

- (iTermBuiltInFunctions *)objectMethodRegistry {
    if (!_methods) {
        _methods = [[iTermBuiltInFunctions alloc] init];
        iTermBuiltInMethod *method;
        method = [[iTermBuiltInMethod alloc] initWithName:@"set_title"
                                            defaultValues:@{}
                                                    types:@{ @"title": [NSString class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(setTitleWithCompletion:title:)];
        [_methods registerFunction:method namespace:@"iterm2"];
    }
    return _methods;
}

- (void)setTitleWithCompletion:(void (^)(id, NSError *))completion
                         title:(NSString *)title {
    [self.scope setValue:title.length ? title : nil
        forVariableNamed:iTermVariableKeyWindowTitleOverrideFormat];
    completion(nil, nil);
}

- (iTermVariableScope *)objectScope {
    return self.scope;
}

#pragma mark - iTermSubscribable

- (NSString *)subscribableIdentifier {
    return self.terminalGuid;
}

// Only variable-changed notifications are relevant for windows. Everything else is just for sessions.
// Variable-changed notifs are handled before this is called.
- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request
                                            connectionKey:(NSString *)connectionKey {
    ITMNotificationResponse *response = [[[ITMNotificationResponse alloc] init] autorelease];
    response.status = ITMNotificationResponse_Status_RequestMalformed;
    return response;
}


@end
