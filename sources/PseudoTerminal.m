#import "PseudoTerminal.h"
#import "PseudoTerminal+Private.h"
#import "PseudoTerminal+TouchBar.h"
#import "PseudoTerminal+WindowStyle.h"

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
#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermController.h"
#import "iTermEncoderAdapter.h"
#import "iTermFindCursorView.h"
#import "iTermFindDriver.h"
#import "iTermFindPasteboard.h"
#import "iTermFontPanel.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermGraphEncoder.h"
#import "iTermImageView.h"
#import "iTermNotificationCenter.h"
#import "iTermNotificationController.h"
#import "iTermHotKeyController.h"
#import "iTermHotKeyMigrationHelper.h"
#import "iTermInstantReplayWindowController.h"
#import "iTermKeyMappings.h"
#import "iTermMenuBarObserver.h"
#import "iTermObject.h"
#import "iTermOpenQuicklyWindow.h"
#import "iTermOrderEnforcer.h"
#import "iTermPasswordManagerWindowController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermProfilesWindowController.h"
#import "iTermPromptOnCloseReason.h"
#import "iTermQuickLookController.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermRecordingCodec.h"
#import "iTermRestorableStateController.h"
#import "iTermRootTerminalView.h"
#import "iTermSavePanel.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermSelection.h"
#import "iTermSessionFactory.h"
#import "iTermSessionLauncher.h"
#import "iTermSessionTitleBuiltInFunction.h"
#import "iTermShellHistoryController.h"
#import "iTermSquash.h"
#import "iTermSwiftyString.h"
#import "iTermSwiftyStringGraph.h"
#import "iTermSystemVersion.h"
#import "iTermTabBarAccessoryViewController.h"
#import "iTermTabBarControlView.h"
#import "iTermTheme.h"
#import "iTermToolbeltView.h"
#import "iTermToolSnippets.h"
#import "iTermTouchBarButton.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Session.h"
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
#import "NSResponder+iTerm.h"
#import "NSScroller+iTerm.h"
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
#import "PTYTextView+ARC.h"
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
#import "ToolJobs.h"
#import "VT100RemoteHost.h"
#import "VT100Screen.h"
#import "VT100ScreenMutableState.h"
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

// This is used to adjust the window's size to preserve rows x cols when the scroller style changes.
// If the window was maximized to the screen's visible frame, it will be unset to disable this behavior.
static NSString *const TERMINAL_ARRANGEMENT_SCROLLER_WIDTH = @"Scroller Width";

// Only present in arrangements created by the window restoration system, not (for example) saved arrangements in the UI.
// Boolean NSNumber.
static NSString *const TERMINAL_ARRANGEMENT_MINIATURIZED = @"miniaturized";

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

typedef NS_OPTIONS(NSUInteger, iTermSuppressMakeCurrentTerminal) {
    // Allow adding a tab to make this window current, revealing it.
    iTermSuppressMakeCurrentTerminalNone = 0,

    // This is a hotkey window and restoration should not reveal it.
    iTermSuppressMakeCurrentTerminalHotkey = 1 << 0,

    // This window is being restored miniaturized and restoration should not reveal it.
    iTermSuppressMakeCurrentTerminalMiniaturized = 1 << 1
};

typedef NS_ENUM(int, iTermShouldHaveTitleSeparator) {
    iTermShouldHaveTitleSeparatorUninitialized = 0,
    iTermShouldHaveTitleSeparatorYes = 1,
    iTermShouldHaveTitleSeparatorNo = 2
};

@interface PseudoTerminal () <
    iTermBroadcastInputHelperDelegate,
    iTermGraphCodable,
    iTermObject,
    iTermRestorableWindowController,
    iTermTabBarControlViewDelegate,
    iTermPasswordManagerDelegate,
    iTermUniquelyIdentifiable,
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

    // When sending input to all sessions we temporarily change the background
    // color. This stores the normal background color so we can restore to it.
    NSColor *normalBackgroundColor;

    // This prevents recursive resizing.
    BOOL _resizeInProgressFlag;

    // There is a scheme for saving window positions. Each window is assigned
    // a number, and the positions are stored by window name. The window name
    // includes its unique number. This variable gives this window's number.
    int uniqueNumber_;

    PasteboardHistoryWindowController* pbHistoryView;
    CommandHistoryPopupWindowController *commandHistoryPopup;
    DirectoriesPopupWindowController *_directoriesPopupWindowController;
    AutocompleteView* autocompleteView;

    // This is a hack to support old applescript code that set the window size
    // before adding a session to it, which doesn't really make sense now that
    // textviews and windows are loosely coupled.
    int nextSessionRows_;
    int nextSessionColumns_;

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

    // Time since 1970 of last window resize
    double lastResizeTime_;

    iTermBroadcastInputHelper *_broadcastInputHelper;
    
    NSTimeInterval findCursorStartTime_;

    // Accumulated pinch magnification amount.
    double cumulativeMag_;

    // Time of last magnification change.
    NSTimeInterval lastMagChangeTime_;

    IBOutlet NSPanel *coprocesssPanel_;
    IBOutlet NSButton *coprocessOkButton_;
    IBOutlet NSComboBox *coprocessCommand_;
    IBOutlet NSButton *coprocessIgnoreErrors_;

    NSDictionary *lastArrangement_;

    // If positive, then any window resizing that happens is driven by tmux and
    // shouldn't be reported back to tmux as a user-originated resize.
    int tmuxOriginatedResizeInProgress_;

    BOOL liveResize_;
    enum {
        iTermPostponeTmuxTabLayoutChangeStateNone = 0,
        iTermPostponeTmuxTabLayoutChangeStateFixedSizeWindow = 1,
        iTermPostponeTmuxTabLayoutChangeStateVariableSizeWindow = 2
    } postponedTmuxTabLayoutChange_;

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

    iTermTabBarAccessoryViewController *_titleBarAccessoryTabBarViewController NS_AVAILABLE_MAC(10_14);

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

    // This is true if the user is dragging the window by the titlebar. It should not be set for
    // programmatic moves or moves because of disconnecting a display.
    BOOL _windowIsMoving;
    NSInteger _screenBeforeMoving;
    BOOL _constrainFrameAfterDeminiaturization;

    // Size of the last grid size shown in the transient window title, or 0,0 for never shown before.
    VT100GridSize _previousGridSize;
    // Have we started showing a transient title? If so, don't stop until time runs out.
    BOOL _lockTransientTitle;

    BOOL _windowNeedsInitialSize;

    iTermFunctionCallTextFieldDelegate *_currentTabTitleTextFieldDelegate;
    iTermVariables *_userVariables;
    iTermBuiltInFunctions *_methods;

    BOOL _anyPaneIsTransparent;
    BOOL _windowDidResize;
    iTermSuppressMakeCurrentTerminal _suppressMakeCurrentTerminal;
    BOOL _deallocing;
    iTermOrderEnforcer *_proxyIconOrderEnforcer;
    BOOL _restorableStateInvalid;
    BOOL _inWindowDidMove;
    NSView *_swipeContainerView;

    // Work around a macOS bug. If you set the window's appearance to light when creating a new
    // lion full screen window while a lion full screen window is key then a bogus black window
    // is created on the primary display. Issue 8842.
    BOOL _deferSetAppearance;
    BOOL _haveDesiredAppearance;
    NSAppearance *_desiredAppearance;
    CGFloat _backingScaleFactor;

    // When restoring an arrangement with lots of tabs, updating object counts is slow because it
    // adds and removes tracking rects for each tab, which its itself slow. This is an optimization
    // to only update object counts once when creating gobs of tabs at once.
    BOOL _needsUpdateTabObjectCounts;

    // A disgusting hack. This is used to twiddle the titlebar separator style to force
    // the private method _updateDividerLayoutForController:animated: to be called so that we can
    // hide the divider between the title bar and its accessory view controller.
    iTermShouldHaveTitleSeparator _previousTerminalWindowShouldHaveTitlebarSeparator;

    // When restoring a window, this keeps track of how the window's width needs to be adjusted in
    // case scrollbar style has changed since the state was saved. It can be postiive or negative.
    // The frame is modified by this amount when it is safe to do so.
    CGFloat _widthAdjustment;

    NSSize _previousScreenSize;
    CGFloat _previousScreenScaleFactor;

    NSTimeInterval _creationTime;

    // Issue 10551
    iTermTextView *_fieldEditor;
    BOOL _needsCanonicalize;
}

@synthesize scope = _scope;
@synthesize variables = _variables;
@synthesize windowTitleOverrideSwiftyString = _windowTitleOverrideSwiftyString;

+ (void)registerSessionsInArrangement:(NSDictionary *)arrangement {
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
        [PTYTab registerSessionsInArrangement:tabArrangement];
    }
}

+ (Profile *)expurgatedInitialProfile:(Profile *)profile {
    // We don't care about almost all the keys in the profile, so don't waste space and privacy storing them.
    return [profile ?: @{} dictionaryKeepingOnlyKeys:@[ KEY_CUSTOM_WINDOW_TITLE,
                                                        KEY_USE_CUSTOM_WINDOW_TITLE,
                                                        KEY_DISABLE_AUTO_FRAME ]];
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
    ITAssertWithMessage(self, @"initWithWindowNibName returned nil");
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
    _creationTime = [NSDate it_timeSinceBoot];
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
    _proxyIconOrderEnforcer = [[iTermOrderEnforcer alloc] init];
    _toggleFullScreenModeCompletionBlocks = [[NSMutableArray alloc] init];
    _windowWasJustCreated = YES;
    _deferSetAppearance = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf disableDeferSetAppearance];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = [[weakSelf retain] autorelease];
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
        [[iTermPresentationController sharedInstance] forceShowMenuBarAndDock];
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
    DLog(@"Initialize saved window type to %@", @(savedWindowType));
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
    _backingScaleFactor = self.window.backingScaleFactor;
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
                                             selector:@selector(applicationDidResignActive:)
                                                 name:NSApplicationDidResignActiveNotification
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
    [iTermNamedMarksDidChangeNotification subscribeWithOwner:self block:^(iTermNamedMarksDidChangeNotification * _Nonnull notif) {
        if ([notif.sessionGuid isEqualToString:weakSelf.currentSession.guid]) {
            [weakSelf refreshNamedMarks];
        }
    }];
    PtyLog(@"set window inited");
    self.windowInitialized = YES;
    useTransparency_ = [iTermProfilePreferences boolForKey:KEY_INITIAL_USE_TRANSPARENCY inProfile:profile];
    number_ = [[iTermController sharedInstance] allocateWindowNumber];
    [_scope setValue:@(number_ + 1) forVariableNamed:iTermVariableKeyWindowNumber];

    // Update the collection behavior.
    self.hotkeyWindowType = hotkeyWindowType;

    _wellFormed = YES;
    [[self window] setRestorable:YES];
    [[self window] setRestorationClass:[PseudoTerminalRestorer class]];
    self.terminalGuid = [NSString stringWithFormat:@"pty-%@", [NSString uuid]];

    if ([self.window respondsToSelector:@selector(addTitlebarAccessoryViewController:)] &&
        [iTermAdvancedSettingsModel useShortcutAccessoryViewController]) {
        _shortcutAccessoryViewController =
            [[iTermWindowShortcutLabelTitlebarAccessoryViewController alloc] initWithNibName:@"iTermWindowShortcutAccessoryView"
                                                                                      bundle:[NSBundle bundleForClass:self.class]];
    }
    [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
    _shortcutAccessoryViewController.ordinal = number_ + 1;

    DLog(@"Creating window with profile:%@", profile);
    DLog(@"%@\n%@", self, [NSThread callStackSymbols]);
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
    [_scope setValue:@(hotkeyWindowType != iTermHotkeyWindowTypeNone)
    forVariableNamed:iTermVariableKeyWindowIsHotkeyWindow];
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

- (void)dealloc {
    _deallocing = YES;
    [_contentView shutdown];

    [self closeInstantReplayWindow];
    doNotSetRestorableState_ = YES;
    _wellFormed = NO;

    // Do not assume that [self window] is valid here. It may have been freed.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];

    // Release all our sessions.
    if (_contentView.tabBarControl.delegate == self) {
        _contentView.tabBarControl.delegate = nil;
    }
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
    [_shortcutAccessoryViewController release];
    [_titleBarAccessoryTabBarViewController release];
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
    [_proxyIconOrderEnforcer release];
    [_swipeIdentifier release];
    [_fieldEditor release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p tabs=%d window=%@>",
            [self class], self, (int)[self numberOfTabs], [self window]];
}

- (BOOL)tabBarVisibleOnTopEvenWhenOnLoan {
    return ([self tabBarShouldBeVisibleEvenWhenOnLoan] &&
            [iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab);
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
            ![self tabBarVisibleOnTopEvenWhenOnLoan]);
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
    const BOOL result = togglingFullScreen_ || liveResize_ || togglingLionFullScreen_ || exitingLionFullscreen_ || zooming_;
    DLog(@"togglingFullScreen=%@ liveResize=%@ togglingLionFullscreen=%@ exitingLionFullscreen=%@ zooming=%@ DISPOSITION=%@ self=%@",
         @(togglingFullScreen_), @(liveResize_), @(togglingLionFullScreen_), @(exitingLionFullscreen_), @(zooming_), @(result), self);
    return result;
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
    [self toggleToolbeltVisibilityWithSideEffects:YES];
}

- (void)toggleToolbeltVisibilityWithSideEffects:(BOOL)sideEffects {
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
    if (sideEffects) {
        [[self uniqueTmuxControllers] enumerateObjectsUsingBlock:^(TmuxController *controller, NSUInteger idx, BOOL * _Nonnull stop) {
            [controller savePerWindowSettings];
        }];
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
        TmuxController *first = self.uniqueTmuxControllers.firstObject;
        [first restoreWindowFrame:self];
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
            [[iTermPresentationController sharedInstance] update];
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

- (void)ensureSaneFrame {
    NSPoint recommendedOrigin = self.window.frame.origin;
    const double fractionOnScreen = [NSScreen fractionOfFrameOnAnyScreen:self.window.frame
                                                       recommendedOrigin:&recommendedOrigin];
    if (fractionOnScreen < 0.05) {
        DLog(@"Frame %@ is %@ percent onscreen. Move to %@",
             NSStringFromRect(self.window.frame),
             @(fractionOnScreen),
             NSStringFromPoint(recommendedOrigin));
        [self.window setFrameOrigin:recommendedOrigin];
    }
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
    if (tab == self.currentTab) {
        [self haveTransparentPaneDidChange];
    }
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
        return [self.currentSession.screen.colorMap colorForKey:kColorMapBackground];
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
        if ([iTermAdvancedSettingsModel minimalSplitPaneDividerProminence] == 0 &&
            ![iTermPreferences boolForKey:kPreferenceKeyDimOnlyText] &&
            [iTermPreferences boolForKey:kPreferenceKeyDimInactiveSplitPanes]) {
            // Use the dimmed background color to keep the divider invisible. Issue 9327.
            PTYSession *currentSession = [self currentSession];
            NSArray<NSColor *> *candidates = [[self.allSessions mapWithBlock:^NSColor *(PTYSession *session) {
                if (session == currentSession) {
                    return nil;
                }
                return [session processedBackgroundColor];
            }] uniq];
            if (candidates.count == 1) {
                return candidates[0];
            }
        }
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

- (BOOL)terminalWindowShouldHaveTitlebarSeparator {
    if (togglingLionFullScreen_ || [self lionFullScreen]) {
        return YES;
    }
    if (_contentView.tabBarControlOnLoan) {
        return NO;
    }
    if (!_contentView.tabBarShouldBeVisible) {
        return YES;
    }
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_TopTab:
            return NO;
        case PSMTab_LeftTab:
        case PSMTab_BottomTab:
            return YES;
    }
    // Shouldn't happen
    return YES;
}

- (void)terminalWindowWillMoveToScreen:(NSScreen *)screen {
    DLog(@"moving to screen with frame %@. self=%@", NSStringFromRect(screen.frame), self);
    if (!_isAnchoredToScreen) {
        DLog(@"Not anchored, do nothing");
        return;
    }
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (_anchoredScreenNumber >= screens.count) {
        DLog(@"Am anchored to screen %@ but there aren't that many screens. Unanchor", @(_anchoredScreenNumber));
        _isAnchoredToScreen = NO;
        return;
    }

    NSScreen *currentScreen = screens[_anchoredScreenNumber];
    if (NSEqualRects(currentScreen.frame, screen.frame)) {
        DLog(@"New screen has same frame. Doing nothing.");
        return;
    }
    DLog(@"Current screen has frame %@. Moving.", NSStringFromRect(currentScreen.frame));
    _isAnchoredToScreen = NO;
}

- (void)moveToScreen:(NSScreen *)screen {
    const NSRect originalFrame = self.window.frame;
    NSRect destinationFrame;
    const NSRect sourceScreenFrame = self.fullScreen ? self.window.screen.frame : self.window.screen.visibleFrame;
    const NSRect destinationScreenFrame = self.fullScreen ? screen.frame : screen.visibleFrame;
    const NSPoint originOffset = NSMakePoint(originalFrame.origin.x - sourceScreenFrame.origin.x,
                                             originalFrame.origin.y - sourceScreenFrame.origin.y);
    const NSPoint offsetFraction = NSMakePoint(originOffset.x / sourceScreenFrame.size.width,
                                               originOffset.y / sourceScreenFrame.size.height);
    const NSPoint destinationOrigin = NSMakePoint(destinationScreenFrame.origin.x + offsetFraction.x * destinationScreenFrame.size.width,
                                                  destinationScreenFrame.origin.y + offsetFraction.y * destinationScreenFrame.size.height);
    destinationFrame.origin = destinationOrigin;
    destinationFrame.size.height = MIN(originalFrame.size.height, destinationScreenFrame.size.height);
    destinationFrame.size.width = MIN(originalFrame.size.width, destinationScreenFrame.size.width);

    // Move towards origin to fit
    CGFloat overage;
    overage = MAX(0, NSMaxX(destinationFrame) - NSMaxX(destinationScreenFrame));
    destinationFrame.origin.x = MAX(destinationScreenFrame.origin.x, destinationFrame.origin.x - overage);
    overage = MAX(0, NSMaxY(destinationFrame) - NSMaxY(destinationScreenFrame));
    destinationFrame.origin.y = MAX(destinationScreenFrame.origin.y, destinationFrame.origin.y - overage);
    DLog(@"Failed to move window. Current screen is %@. Desired screen is %@. originalFrame=%@ destinationFrame=%@ sourceScreenFrame=%@ destinationScreenFrame=%@ originOffset=%@ offsetFraction=%@ destinationOrigin=%@",
         self.window.screen,
         screen,
         NSStringFromRect(originalFrame),
         NSStringFromRect(destinationFrame),
         NSStringFromRect(sourceScreenFrame),
         NSStringFromRect(destinationScreenFrame),
         NSStringFromPoint(originOffset),
         NSStringFromPoint(offsetFraction),
         NSStringFromPoint(destinationOrigin));
    [self.window setFrame:destinationFrame display:NO];
    [self canonicalizeWindowFrame];
}

- (void)terminalWindowDidMoveToScreen:(NSScreen *)screen {
    if (self.window &&
        ![self.window.screen.it_uniqueKey isEqualToString:screen.it_uniqueKey] &&
        !self.window.isFullScreen) {
        DLog(@"Hit the backstop");
        [self moveToScreen:screen];
    }
    if (_needsCanonicalize) {
        DLog(@"moveToScreen finished so do deferred frame canonicalization");
        [self canonicalizeWindowFrame];
    }
    _needsCanonicalize = NO;
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

- (void)ptyWindowDidMakeKeyAndOrderFront:(id<PTYWindow>)window {
    DLog(@"%@", self);
    [[self currentTab] recheckBlur];
}

- (BOOL)ptyWindowIsDraggable:(id<PTYWindow>)window {
    if (self.lionFullScreen || togglingLionFullScreen_) {
        return NO;
    }
    switch (_windowType) {
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return NO;

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
            return YES;
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

- (BOOL)confirmCloseForSessions:(NSArray *)sessions
                     identifier:(NSString*)identifier
                    genericName:(NSString *)genericName
{
    NSArray *names = @[];
    for (PTYSession *aSession in sessions) {
        if (![aSession exited]) {
            names = [aSession.childJobNameTuples mapWithBlock:^id(iTermTuple<NSString *,NSString *> *tuple) {
                if ([tuple.firstObject isEqualToString:@"login"]) {
                    return nil;
                }
                return tuple.secondObject.lastPathComponent;
            }];
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
    if ([self windowShouldClose:self.window]) {
        [self close];
    }
}

- (void)close {
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    [super close];
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
        if ([self numberOfTabsWithTmuxController:aTab.tmuxController] == 1) {
            [self killOrHideTmuxWindow];
        } else {
            [self killOrHideTmuxTab:aTab];
        }
        return;
    }
    [self removeTab:aTab];
}

- (void)tab:(PTYTab *)tab closeSession:(PTYSession *)session {
    [self closeSessionWithoutConfirmation:session];
}

- (void)tabProcessInfoProviderDidChange:(PTYTab *)tab {
    [self refreshTools];
}

- (BOOL)tabBelongsToHotkeyWindow:(PTYTab *)tab {
    return [self isHotKeyWindow];
}

- (NSUInteger)numberOfTabsWithTmuxController:(TmuxController *)tmuxController {
    return [[self.tabs filteredArrayUsingBlock:^BOOL(PTYTab *tab) {
        return tab.tmuxController == tmuxController;
    }] count];
}

- (void)killOrHideTmuxTab:(PTYTab *)aTab {
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
    restorableSession.windowTitle = [self.scope windowTitleOverrideFormat];
    [self storeWindowStateInRestorableSession:restorableSession];
    DLog(@"Create restorable session with terminal guid %@", restorableSession.terminalGuid);
    return restorableSession;
}

- (void)storeWindowStateInRestorableSession:(iTermRestorableSession *)restorableSession {
    restorableSession.windowType = self.lionFullScreen ? WINDOW_TYPE_LION_FULL_SCREEN : self.windowType;
    restorableSession.savedWindowType = self.savedWindowType;
    restorableSession.screen = _screenNumberFromFirstProfile;
    restorableSession.windowTitle = [self.scope windowTitleOverrideFormat];
}

- (iTermRestorableSession *)restorableSessionForTab:(PTYTab *)aTab {
    DLog(@"Create restorable session for tab %@", aTab);
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
    restorableSession.windowTitle = [self.scope windowTitleOverrideFormat];
    [self storeWindowStateInRestorableSession:restorableSession];
    return restorableSession;
}

// Just like closeTab but skips the tmux code. Terminates sessions, removes the
// tab, and closes the window if there are no tabs left.
- (void)removeTab:(PTYTab *)aTab {
    DLog(@"Remove tab %@", aTab);
    if (![aTab isTmuxTab]) {
        iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
        restorableSession.sessions = [aTab sessions];
        restorableSession.terminalGuid = self.terminalGuid;
        restorableSession.tabUniqueId = aTab.uniqueId;
        restorableSession.windowTitle = [self.scope windowTitleOverrideFormat];
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

- (IBAction)addNamedMark:(id)sender
{
    __weak PTYSession *session = self.currentSession;
    [iTermBookmarkDialogViewController showInWindow:self.window
                                     withCompletion:^(NSString * _Nonnull name) {
        [session saveScrollPositionWithName:name];
    }];
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
    DLog(@"%@", self);
    if ([self anyFullScreen]) {
        [self updateTabBarControlIsTitlebarAccessory];
        [_contentView.tabBarControl updateFlashing];
        [self repositionWidgets];
        [self fitTabsToWindow];
    } else {
        DLog(@"Not full screen");
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
        if ([aSession closeComposer]) {
            return;
        }
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
                                                    [[aSession name] removingHTMLFromTabTitleIfNeeded]]];
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
    DLog(@"restartSession");
    [self restartSessionWithConfirmation:self.currentSession];
}

- (IBAction)duplicateSession:(id)sender {
    DLog(@"duplicateSession");
    PTYSession *session = self.currentSession;
    MutableProfile *profile = [[session.profile mutableCopy] autorelease];
    NSArray<iTermSSHReconnectionInfo *> *pendingJumps = nil;
    if (session.sshIdentity) {
        NSArray<iTermSSHReconnectionInfo *> *sequence = session.sshCommandLineSequence;
        if ([profile[KEY_CUSTOM_COMMAND] isEqualToString:kProfilePreferenceCommandTypeSSHValue]) {
            // SSH command type
            if (sequence[0].initialDirectory) {
                profile[KEY_CUSTOM_DIRECTORY] = @"Yes";
                profile[KEY_WORKING_DIRECTORY] = sequence[0].initialDirectory;
            }
        } else {
            // Local session in which the user ran it2ssh. Change to ssh profile to first host.
            assert(sequence.count > 0);
            profile[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeSSHValue;
            profile[KEY_COMMAND_LINE] = sequence[0].sshargs;
            if (sequence[0].initialDirectory) {
                profile[KEY_CUSTOM_DIRECTORY] = @"Yes";
                profile[KEY_WORKING_DIRECTORY] = sequence[0].initialDirectory;
            }
        }
        pendingJumps = sequence;
        // TOOD: Should specify a pwd for each host along the way. This will do the wrong thing if
        // there are jump hosts.
        NSString *pwd = session.variablesScope.path;
        if (pwd) {
            profile[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue;
            profile[KEY_WORKING_DIRECTORY] = pwd;
        }
    } else if (session.currentLocalWorkingDirectory) {
        profile[KEY_CUSTOM_DIRECTORY] = @"Yes";
        profile[KEY_WORKING_DIRECTORY] = session.currentLocalWorkingDirectory;
    }
    DLog(@"Will use profile:\n%@", profile);
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    iTermMutableDictionaryEncoderAdapter *encoder =
        [[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:dict];
    [session encodeArrangementWithContents:YES encoder:encoder];

    NSDictionary *tabArrangement = [self.currentTab arrangementWithOnlySession:session
                                                                       profile:profile
                                                                   saveProgram:NO
                                                                  pendingJumps:pendingJumps];
    [self openTabWithArrangement:tabArrangement
                           named:@"Unnamed arrangement"
                 hasFlexibleView:NO
                         viewMap:nil
                      sessionMap:nil
              partialAttachments:nil];
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
    NSString *subtitle = (self.canShowSubtitleInTitlebar ? self.currentSession.subtitle : @"") ?: @"";
    if (self.isShowingTransientTitle) {
        DLog(@"showing transient title");
        PTYSession *session = self.currentSession;
        NSString *aTitle;
        VT100GridSize size = VT100GridSizeMake(session.columns, session.rows);
        if (!_lockTransientTitle) {
            if (VT100GridSizeEquals(_previousGridSize, VT100GridSizeMake(0, 0))) {
                _previousGridSize = size;
                DLog(@"NOT showing transient title because of no previous grid sizes");
                [self setWindowTitle:[self undecoratedWindowTitle]
                            subtitle:subtitle];
                return;
            }
            if (VT100GridSizeEquals(size, _previousGridSize)) {
                DLog(@"NOT showing transient title because of equal grid sizes");
                [self setWindowTitle:[self undecoratedWindowTitle]
                            subtitle:subtitle];
                return;
            }
            _lockTransientTitle = YES;
        }
        _previousGridSize = size;
        DLog(@"showing transient title %@", @(self.timeOfLastResize));
        if (self.window.frame.size.width < 250) {
            aTitle = [NSString stringWithFormat:@"%d✕%d", session.columns, session.rows];
        } else {
            NSString *detail = [self rootTerminalViewWindowSizeViewDetailString];
            NSString *sizeString = iTermColumnsByRowsString(session.columns, session.rows);
            NSString *undecoratedTitle = [self undecoratedWindowTitle];
            if ([undecoratedTitle containsString:sizeString]) {
                // If the session title already includes the size don't add it a second time.
                aTitle = [NSString stringWithFormat:@"%@%@",
                          undecoratedTitle,
                          detail ? [@" \u2014 " stringByAppendingString:detail] : @""];
            } else {
                aTitle = [NSString stringWithFormat:@"%@ \u2014 %@%@",
                          undecoratedTitle,
                          sizeString,
                          detail ? [@" \u2014 " stringByAppendingString:detail] : @""];
            }
        }
        [self setWindowTitle:aTitle
                    subtitle:subtitle];
    } else {
        _lockTransientTitle = NO;
        [self setWindowTitle:[self undecoratedWindowTitle]
                    subtitle:subtitle];
    }
}

- (BOOL)canShowSubtitleInTitlebar {
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
            return YES;

        case TAB_STYLE_COMPACT:
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return NO;
    }
}

- (NSString *)titleForWindowMenu {
    if (![iTermAdvancedSettingsModel includeShortcutInWindowsMenu]) {
        return self.window.title;
    }
    NSString *modifiers = [iTermWindowShortcutLabelTitlebarAccessoryViewController modifiersString];
    if (!modifiers) {
        return self.window.title;
    }
    if (number_ + 1 >= 10) {
        return [NSString stringWithFormat:@"%@ — %@", self.window.title, @(number_ + 1)];
    }
    NSString *formattedShortcut = [NSString stringWithFormat:@"%@%@",
                                   modifiers,
                                   @(number_ + 1)];
    return [NSString stringWithFormat:@"%@ — %@", _contentView.windowTitle, formattedShortcut];
}

- (void)setWindowTitle:(NSString *)title subtitle:(NSString *)subtitle {
    DLog(@"setWindowTitle:%@", title);
    if (_deallocing) {
        // This uses -weakSelf and can be called during dealloc. Doing so is a crash.
        return;
    }
    if (title == nil) {
        // title can be nil during loadWindowArrangement
        title = @"";
    }
    assert(subtitle != nil);

    NSString *titleExWindowNumber = title;

    if ([iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber]) {
        NSString *tmuxId = @"";
        if ([[self currentSession] isTmuxClient] &&
            [iTermAdvancedSettingsModel tmuxIncludeClientNameInWindowTitle]) {
            NSString *clientName = [[[self currentSession] tmuxController] clientName];
            if (clientName) {
                tmuxId = [NSString stringWithFormat:@" [%@]", clientName];
            }
        }
        NSString *windowNumber = @"";

        if (!_shortcutAccessoryViewController ||
            !(self.window.styleMask & NSWindowStyleMaskTitled)) {
            windowNumber = [NSString stringWithFormat:@"%d. ", number_ + 1];
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
        // Title is already up to date.
        [_contentView setSubtitle:subtitle];
        return;
    }

    [self.contentView windowTitleDidChangeTo:titleExWindowNumber];

    if (liveResize_) {
        // During a live resize this has to be done immediately because the runloop doesn't get
        // around to delayed performs until the live resize is done (bug 2812).
        self.window.title = title;
        [self updateWindowMenu];
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
            [self updateWindowMenu];
        }
        __weak __typeof(self) weakSelf = self;
        DLog(@"schedule timer to set window title");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(iTermWindowTitleChangeMinimumInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!(weakSelf.window.title == weakSelf.desiredTitle || [weakSelf.window.title isEqualToString:weakSelf.desiredTitle])) {
                DLog(@"timer fired. Set title to %@", weakSelf.desiredTitle);
                weakSelf.window.title = weakSelf.desiredTitle;
                [weakSelf updateWindowMenu];
            }
            weakSelf.desiredTitle = nil;
        });
    }
}

- (NSArray<PTYSession *> *)broadcastSessions {
    NSArray<PTYSession *> *allSessions = [self allSessions];
    return [[_broadcastInputHelper currentDomain].allObjects mapWithBlock:^id(NSString *guid) {
        PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:guid];
        if (![allSessions containsObject:session]) {
            return nil;
        }
        return session;
    }];
}

- (void)sendInputToAllSessions:(NSString *)string
                      encoding:(NSStringEncoding)optionalEncoding
                 forceEncoding:(BOOL)forceEncoding {
    for (PTYSession *aSession in [self broadcastSessions]) {
        if (![aSession isTmuxGateway]) {
            [aSession writeTaskNoBroadcast:string encoding:optionalEncoding forceEncoding:forceEncoding reporting:NO];
        }
    }
}

- (BOOL)broadcastInputToSession:(PTYSession *)session {
    return [_broadcastInputHelper shouldBroadcastToSessionWithID:session.guid];
}

- (BOOL)broadcastInputHelper:(iTermBroadcastInputHelper *)helper tabWithSessionIsBroadcasting:(NSString *)sessionID {
    PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:sessionID];
    if (!session) {
        DLog(@"NO: No session with id %@", sessionID);
        return NO;
    }
    PTYTab *tab = [self tabForSession:session];
    if (!tab) {
        DLog(@"NO: Session %@ belongs to no tab (wtf)", session);
        return NO;
    }
    DLog(@"Return %@", @(tab.isBroadcasting));
    return tab.isBroadcasting;
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
                          dark:(BOOL)dark {
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
            rect.origin.x = xOrigin + xScale * ([[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue] - screenFrame.origin.x);
            double h = [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            double y = [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue] - screenFrame.origin.y;
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
                             frame:contentRect
                              dark:dark];
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

+ (void)performWhenWindowCreationIsSafeForLionFullScreen:(BOOL)lionFullScreen
                                                   block:(void (^)(void))block {
    BOOL shouldDelay = NO;
    DLog(@"begin");
    if ([PseudoTerminal willAutoFullScreenNewWindow] &&
        [PseudoTerminal anyWindowIsEnteringLionFullScreen]) {
        DLog(@"Prevented by autofullscreen + a window entering.");
        shouldDelay = YES;
    }
    if (lionFullScreen &&
        [PseudoTerminal anyWindowIsEnteringLionFullScreen]) {
        DLog(@"Prevented by fs arrangement + a window entering.");
        shouldDelay = YES;
    }
    if (shouldDelay) {
        DLog(@"Trying again in .25 sec");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self performWhenWindowCreationIsSafeForLionFullScreen:lionFullScreen block:block];
        });
    } else {
        block();
    }
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
        if ([arrangement[TERMINAL_ARRANGEMENT_MINIATURIZED] boolValue]) {
            term->_suppressMakeCurrentTerminal |= iTermSuppressMakeCurrentTerminalMiniaturized;
            [term.window miniaturize:nil];
        }
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
                                  named:(NSString *)arrangementName
                               sessions:(NSArray *)sessions
               forceOpeningHotKeyWindow:(BOOL)force {
    PseudoTerminal *term = [PseudoTerminal bareTerminalWithArrangement:arrangement
                                              forceOpeningHotKeyWindow:force];
    for (PTYSession *session in sessions) {
        assert([session revive]);  // TODO(georgen): This isn't guaranteed
    }
    if ([term loadArrangement:arrangement
                        named:arrangementName
                     sessions:sessions
           partialAttachments:nil]) {
        return term;
    } else {
        return term;
    }
}

+ (PseudoTerminal *)terminalWithArrangement:(NSDictionary *)arrangement
                                      named:(NSString *)arrangementName
                   forceOpeningHotKeyWindow:(BOOL)force {
    return [self terminalWithArrangement:arrangement
                                   named:arrangementName
                                sessions:nil
                forceOpeningHotKeyWindow:force];
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
    alert.informativeText = @"If this is empty, the window takes the active session’s title. Variables and function calls enclosed in \\(…) will be replaced with their evaluation. This interpolated string is evaluated in the window’s context.";
    NSTextField *titleTextField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24 * 3)] autorelease];
    iTermFunctionCallTextFieldDelegate *delegate;
    delegate = [[[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextWindow]
                                                                   passthrough:nil
                                                                 functionsOnly:NO] autorelease];
    delegate.canWarnAboutContextMistake = YES;
    delegate.contextMistakeText = @"This interpolated string is evaluated in the window’s context, not the session’s context. To access variables in the current session, use currentTab.currentSession.sessionVariableNameHere";
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

- (IBAction)filter:(id)sender {
    DLog(@"begin");
    [self.currentSession showFilter];
}
- (IBAction)findUrls:(id)sender {
    DLog(@"begin");
    iTermFindDriver *findDriver = self.currentSession.view.findDriverCreatingIfNeeded;
    NSString *regex = [iTermAdvancedSettingsModel findUrlsRegex];
    DLog(@"findDriver=%@ regex=%@", findDriver, regex);
    __weak PTYSession *session = self.currentSession;
    __block BOOL done = NO;
    [findDriver closeViewAndDoTemporarySearchForString:regex
                                                  mode:iTermFindModeCaseSensitiveRegex
                                              progress:^(NSRange linesSearched) {
        if (!session.textview || done) {
            return;
        }
        const VT100GridRange visibleLines = [session.textview rangeOfVisibleLines];
        const NSRange visibleAbsLines = NSMakeRange(visibleLines.location + session.screen.totalScrollbackOverflow,
                                                    visibleLines.length);
        if (NSEqualRanges(visibleAbsLines, NSIntersectionRange(visibleAbsLines, linesSearched))) {
            [session.textview convertVisibleSearchResultsToContentNavigationShortcuts];
            done = YES;
            return;
        }
    }];
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
                                                  index:nil
                                                  scope:[iTermVariableScope globalsScope]
                                             completion:nil];
}

- (IBAction)newTmuxTab:(id)sender {
    [self newTmuxTabAtIndex:nil];
}

- (void)newTmuxTabAtIndex:(NSNumber *)index {
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
                                                  index:index
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
         visibleLayout:(NSMutableDictionary *)visibleParseTree
                window:(int)window
        tmuxController:(TmuxController *)tmuxController
                  name:(NSString *)name {
    DLog(@"begin loadTmuxLayout");
    [self beginTmuxOriginatedResize];
    PTYTab *tab = [PTYTab openTabWithTmuxLayout:parseTree
                                  visibleLayout:visibleParseTree
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

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
     replacingOldCWDOfSessionWithGUID:(NSString *)guid
                           withOldCWD:(NSString *)replacementOldCWD {
    NSMutableDictionary *result = [[arrangement mutableCopy] autorelease];
    NSArray *tabs = result[TERMINAL_ARRANGEMENT_TABS];
    result[TERMINAL_ARRANGEMENT_TABS] = [tabs mapWithBlock:^id(NSDictionary *tabArrangement) {
        return [PTYTab repairedArrangement:tabArrangement
          replacingOldCWDOfSessionWithGUID:guid
                                withOldCWD:replacementOldCWD];
    }];
    return result;
}

+ (NSDictionary *)arrangementForSessionWithGUID:(NSString *)sessionGUID
                            inWindowArrangement:(NSDictionary *)arrangement {
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
        NSDictionary *dict = [PTYTab arrangementForSessionWithGUID:sessionGUID
                                                     inArrangement:tabArrangement];
        if (dict) {
            return dict;
        }
    }
    return nil;
}

- (BOOL)loadArrangement:(NSDictionary *)arrangement named:(NSString *)arrangementName {
    return [self loadArrangement:arrangement
                           named:arrangementName
                        sessions:nil
              partialAttachments:nil];
}

- (BOOL)loadArrangement:(NSDictionary *)arrangement
                  named:(NSString *)arrangementName
               sessions:(NSArray *)sessions
     partialAttachments:(NSDictionary *)partialAttachments {
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
    if (self.hotkeyWindowType != iTermHotkeyWindowTypeNone) {
        _suppressMakeCurrentTerminal |= iTermSuppressMakeCurrentTerminalHotkey;
    }
    const BOOL restoreTabsOK = [self restoreTabsFromArrangement:arrangement
                                                          named:arrangementName
                                                       sessions:sessions
                                             partialAttachments:partialAttachments];
    _suppressMakeCurrentTerminal &= ~iTermSuppressMakeCurrentTerminalHotkey;
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

    if (arrangement[TERMINAL_ARRANGEMENT_SCROLLER_WIDTH]) {
        const CGFloat savedWidth = [arrangement[TERMINAL_ARRANGEMENT_SCROLLER_WIDTH] doubleValue];
        const CGFloat preferredWidth = iTermScrollbarWidth();
        // Set _widthAdjustment here because it will be used below in the call to
        // -rectByAdjustingWidth:.
        _widthAdjustment = preferredWidth - savedWidth;
        DLog(@"Computing scroller width adjustment. preferredWidth=%@ savedWidth=%@ adjustment=%@",
              @(preferredWidth), @(savedWidth), @(_widthAdjustment));
    }

    {
        NSRect frame = rect;
        switch (windowType) {
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            case WINDOW_TYPE_LION_FULL_SCREEN:
            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
                DLog(@"Neither width adjustment nor sanitization needed.");
                break;

            case WINDOW_TYPE_NORMAL:
            case WINDOW_TYPE_ACCESSORY:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_COMPACT:
                DLog(@"Needs width adjustment and sanitization.");
                frame = [PseudoTerminal sanitizedWindowFrame:[self rectByAdjustingWidth:rect]];
                DLog(@"Set width adjustment to 0 for %@", self);
                _widthAdjustment = 0;
                break;

            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_RIGHT_PARTIAL:
                DLog(@"No sanitization but width adjustment.");
                // There's a good chance that sanitization would make sense here but I'm afraid of
                // breaking things I don't understand by changing it.
                frame = [self rectByAdjustingWidth:rect];
                break;
        }
        if (!NSEqualRects(frame, rect)) {
            // Note: this has no effect when using system window restoration because the window's size
            // is set from the completion block passed to PseudoTerminalRestorer, which is controlled
            // by the system. However, it is still effective when restoring a saved arrangement.
            DLog(@"Set frame with adjustments %@ in %@", NSStringFromRect(frame), self);
            [[self window] setFrame:frame display:YES];
        } else {
            DLog(@"No change needed");
        }
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
        [session.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            [mutableState.currentGrid restorePreferredCursorPositionIfPossible];
        }];
    }
    [_contentView updateToolbeltForWindow:self.window];
    [self updateTouchBarFunctionKeyLabels];
    return YES;
}

- (BOOL)stringIsValidTerminalGuid:(NSString *)string {
    NSCharacterSet *characterSet = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    return [string rangeOfCharacterFromSet:characterSet.invertedSet].location == NSNotFound;
}

- (BOOL)restoreTabsFromArrangement:(NSDictionary *)arrangement
                             named:(NSString *)arrangementName
                          sessions:(NSArray<PTYSession *> *)sessions
                partialAttachments:(NSDictionary *)partialAttachments {
    BOOL openedAny = NO;
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
        NSDictionary<NSString *, PTYSession *> *sessionMap = nil;
        if (sessions) {
            sessionMap = [PTYTab sessionMapWithArrangement:tabArrangement sessions:sessions];
        }
        if (![self openTabWithArrangement:tabArrangement
                                    named:arrangementName
                            hasFlexibleView:NO
                                    viewMap:nil
                                 sessionMap:sessionMap
                       partialAttachments:partialAttachments]) {
            return NO;
        }
        openedAny = YES;
    }
    if (!openedAny) {
        return NO;
    }
    [self updateUseTransparency];
    return YES;
}

- (NSArray<PTYTab *> *)tabsToEncodeExcludingTmux:(BOOL)excludeTmux {
    return [self.tabs filteredArrayUsingBlock:^BOOL(PTYTab *theTab) {
        if (theTab.sessions.count == 0) {
            return NO;
        }
        if (excludeTmux && theTab.isTmuxTab) {
            return NO;
        }
        return YES;
    }];
}

- (NSDictionary *)arrangementExcludingTmuxTabs:(BOOL)excludeTmux
                             includingContents:(BOOL)includeContents {
    NSArray<PTYTab *> *tabs = [self tabsToEncodeExcludingTmux:excludeTmux];
    return [self arrangementWithTabs:tabs includingContents:includeContents];
}

- (Profile *)expurgatedInitialProfile {
    return [PseudoTerminal expurgatedInitialProfile:_initialProfile];
}

- (NSDictionary *)arrangementWithTabs:(NSArray<PTYTab *> *)tabs
                    includingContents:(BOOL)includeContents {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:7];
    iTermMutableDictionaryEncoderAdapter *adapter =
        [[[iTermMutableDictionaryEncoderAdapter alloc] initWithMutableDictionary:result] autorelease];
    const BOOL commit =
        [self populateArrangementWithTabs:tabs
                        includingContents:includeContents
                                  encoder:adapter];
    if (!commit) {
        return nil;
    }
    return result;
}

- (BOOL)populateArrangementWithTabs:(NSArray<PTYTab *> *)tabs
                  includingContents:(BOOL)includeContents
                            encoder:(id<iTermEncoderAdapter>)result {
    NSRect rect = [[self window] frame];

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
        return NO;
    }
    [result encodeArrayWithKey:TERMINAL_ARRANGEMENT_TABS
                   identifiers:[tabs mapWithBlock:^id(PTYTab *tab) { return tab.stringUniqueIdentifier; }]
                    generation:iTermGenerationAlwaysEncode
                         block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder,
                                     NSInteger index,
                                     NSString * _Nonnull identifier,
                                     BOOL *stop) {
        return [tabs[index] encodeWithContents:includeContents
                                       encoder:encoder];
    }];

    // Save index of selected tab.
    result[TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX] = @([_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]]);
    result[TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING] = @(hideAfterOpening_);
    result[TERMINAL_ARRANGEMENT_IS_HOTKEY_WINDOW] = @(self.isHotKeyWindow);
    NSString *profileGuid = [[[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] profile] objectForKey:KEY_GUID];
    if (profileGuid) {
        result[TERMINAL_ARRANGEMENT_PROFILE_GUID] = profileGuid;
    }

    const CGFloat scrollerWidth = iTermScrollbarWidth();
    if (![self isMaximized]) {
        result[TERMINAL_ARRANGEMENT_SCROLLER_WIDTH] = @(scrollerWidth);
        DLog(@"Save scroller width of %@", @(scrollerWidth));
    } else {
        DLog(@"Window is maximized so don't save scroller width.");
    }

    return YES;
}

- (BOOL)isMaximized {
    if (self.window.screen == nil) {
        return NO;
    }
    return iTermApproximatelyEqualRects(self.window.frame,
                                        self.window.screen.visibleFrame,
                                        0.5);
}

- (NSDictionary*)arrangement {
    return [self arrangementExcludingTmuxTabs:YES includingContents:NO];
}

// NSWindow delegate methods
- (void)windowDidDeminiaturize:(NSNotification *)aNotification {
    DLog(@"windowDidDeminiaturize: %@\n%@", self, [NSThread callStackSymbols]);
    DLog(@"Erase badge label");
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
    [[_contentView.toolbelt jobsView] updateJobs];
    [[_contentView.toolbelt snippetsView] currentSessionDidChange];
    [[_contentView.toolbelt codeciergeView] currentSessionDidChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSnippetsTagsDidChange object:nil];
    [self refreshNamedMarks];
}

- (void)refreshNamedMarks {
    [[_contentView.toolbelt namedMarksView] setNamedMarks:self.currentSession.screen.namedMarks];
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

- (BOOL)windowShouldClose:(NSNotification *)aNotification {
    DLog(@"windowShouldClose %@", self);
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
        [self killOrHideTmuxWindow];
    }

    DLog(@"Return %@", @(shouldClose));
    return shouldClose;
}

- (void)killOrHideTmuxWindow {
    int n = 0;
    for (PTYTab *aTab in [self tabs]) {
        if ([aTab isTmuxTab] && !aTab.tmuxController.detached) {
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
                                       actions:@[ @"Hide", @"Detach tmux Session", @"Kill", @"Cancel" ]
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
                switch (selection) {
                    case kiTermWarningSelection0:
                        [[aTab tmuxController] hideWindow:[aTab tmuxWindow]];
                        break;
                    case kiTermWarningSelection1:
                        doTmuxDetach = YES;
                        break;
                    case kiTermWarningSelection2:
                        [[aTab tmuxController] killWindow:[aTab tmuxWindow]];
                        break;
                    case kiTermWarningSelection3:
                        // Cancel
                        return;
                    case kItermWarningSelectionError:
                        return;
                }
            }
        }

        if (doTmuxDetach) {
             PTYSession *aSession = [[[_contentView.tabView selectedTabViewItem] identifier] activeSession];
             [[aSession tmuxController] requestDetach];
         }
    }
}

- (void)closeInstantReplayWindow {
    [_instantReplayWindowController close];
    _instantReplayWindowController.delegate = nil;
    [_instantReplayWindowController release];
    _instantReplayWindowController = nil;
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
    if (!_fieldEditor) {
        _fieldEditor = [[iTermTextView alloc] init];
        _fieldEditor.fieldEditor = YES;
    }
    return _fieldEditor;
}

- (void)windowWillClose:(NSNotification *)aNotification {
   DLog(@"windowWillClose %@", self);
    _closing = YES;
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
        [[iTermPresentationController sharedInstance] update];
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
        restorableSession.windowTitle = [self.scope windowTitleOverrideFormat];
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
    _shortcutAccessoryViewController.isMain = YES;
    if (!self.isHotKeyWindow) {
        [[iTermHotKeyController sharedInstance] nonHotKeyWindowDidBecomeKey];
    }
    [[iTermHotKeyController sharedInstance] autoHideHotKeyWindowsExcept:[[iTermHotKeyController sharedInstance] siblingWindowControllersOf:self]];
    DLog(@"Erase badge label");
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
            [[iTermPresentationController sharedInstance] update];
        }
    }

    // Note: there was a bug in the old iterm that setting fonts didn't work
    // properly if the font panel was left open in focus-follows-mouse mode.
    // There was code here to close the font panel. I couldn't reproduce the old
    // bug and it was reported as bug 51 in iTerm2 so it was removed. See the
    // svn history for the old impl.

    // update the cursor
    [[self currentSession] refresh];
    [[[self currentSession] textview] requestDelegateRedraw];
    [_contentView setNeedsDisplay:YES];
    [[iTermFindPasteboard sharedInstance] updateObservers:nil internallyGenerated:NO];

    // Start the timers back up
    for (PTYSession* aSession in [self allSessions]) {
        [aSession updateDisplayBecause:@"windowDidBecomeKey"];
        [[aSession view] setBackgroundDimmed:NO];
        [aSession setFocused:aSession == [self currentSession]];
        [aSession.view setNeedsDisplay:YES];
        [aSession useTransparencyDidChange];
    }
    // Some users report that the first responder isn't always set properly. Let's try to fix that.
    // This attempt (4/20/13) is to fix bug 2431.
    if (!self.window.firstResponder.it_preferredFirstResponder) {
        [self performSelector:@selector(makeCurrentSessionFirstResponder)
                   withObject:nil
                   afterDelay:0];
    }
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
    [_contentView updateTitleAndBorderViews];
    [[iTermSecureKeyboardEntryController sharedInstance] update];
}

- (void)makeCurrentSessionFirstResponder {
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
    if (self.ptyWindow.it_isMovingScreen) {
        _needsCanonicalize = YES;
        DLog(@"Moving screens so don't canonicalize");
        return;
    }
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
    DLog(@"Begin");
    if ([[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] floats]) {
        DLog(@"It floats");
        const BOOL menuBarIsHidden = ![[iTermMenuBarObserver sharedInstance] menuBarVisibleOnScreen:screen];
        DLog(@"menuBarIsHidden=%@", @(menuBarIsHidden));
        if (menuBarIsHidden && ![screen it_hasAnotherAppsFullScreenWindow]) {
            DLog(@"Using screen frame %@", NSStringFromRect(screen.frame));
            // When the menu bar is hidden because it hides automatically, we should go all the way to the top of the screen (issue 7149).
            // But if we are on another app's full-screen space, the system won't allow us to do that (issue 9978).
            return screen.frame;
        }
        DLog(@"Using screen frame excluding menu bar %@", NSStringFromRect(screen.frameExceptMenuBar));
        return screen.frameExceptMenuBar;
    } else {
        DLog(@"non-floating hotkey window uses visible frame ignoring hidden dock %@",
             NSStringFromRect([screen visibleFrameIgnoringHiddenDock]));
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
                // There's a Lion fullscreen window on this display. The window can go at the very
                // top of the screen. If there's a notch, it must be below it. Either way, the
                // usable frame equals that of my window. Note that screen.visibleFrame includes
                // a 5-point margin that the top which is actually not visible! ❤️
                return term.window.frame;
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
                                            ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]);
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
                                            ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]);
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
                                           [[session textview] charWidth] * desiredColumns_ + 2 * [iTermPreferences intForKey:kPreferenceKeySideMargins] + iTermScrollbarWidth());
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
                                           [[session textview] charWidth] * desiredColumns_ + 2 * [iTermPreferences intForKey:kPreferenceKeySideMargins] + iTermScrollbarWidth());
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

- (void)screenParametersDidChange {
    PtyLog(@"Screen parameters changed.");
    [self canonicalizeWindowFrame];
    if (self.window.backingScaleFactor != _backingScaleFactor) {
        _backingScaleFactor = self.window.backingScaleFactor;
        [self.currentTab bounceMetal];
    }
}

- (void)windowOcclusionDidChange:(NSNotification *)notification {
    [self updateUseMetalInAllTabs];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    _hasBeenKeySinceActivation = [self.window isKeyWindow];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
}

- (void)windowDidResignKey:(NSNotification *)aNotification {
    PtyLog(@"PseudoTerminal windowDidResignKey");
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    if (_openingPopupWindow) {
        DLog(@"Ignoring it because we're opening a popup window now");
        return;
    }

    for (PTYSession *aSession in [self allSessions]) {
        if ([[aSession textview] isFindingCursor]) {
            [[aSession textview] endFindCursor];
        }
        [[aSession textview] removeUnderline];
        [aSession useTransparencyDidChange];
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
        [[iTermPresentationController sharedInstance] update];
    }
    // update the cursor
    [[[self currentSession] textview] refresh];
    [[[self currentSession] textview] requestDelegateRedraw];
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
    [_contentView updateTitleAndBorderViews];
    [[iTermSecureKeyboardEntryController sharedInstance] update];
}

- (void)windowDidBecomeMain:(NSNotification *)notification {
    _shortcutAccessoryViewController.isMain = YES;
    [_contentView updateDivisionViewAndWindowNumberLabel];
}

- (void)windowDidResignMain:(NSNotification *)aNotification {
    _shortcutAccessoryViewController.isMain = NO;
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
    [[[self currentSession] textview] requestDelegateRedraw];
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

- (NSEdgeInsets)tabBarInsetsForCompactWindow NS_AVAILABLE_MAC(10_14) {
    const CGFloat stoplightButtonsWidth = 75;
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_TopTab: {
            const CGFloat extraSpace = MAX(0, [iTermAdvancedSettingsModel extraSpaceBeforeCompactTopTabBar]);
            if ([self rootTerminalViewWindowNumberLabelShouldBeVisible]) {
                const CGFloat leftInset = (stoplightButtonsWidth +
                                           iTermRootTerminalViewWindowNumberLabelMargin * 2 +
                                           iTermRootTerminalViewWindowNumberLabelWidth +
                                           extraSpace);
                return NSEdgeInsetsMake(0,
                                        leftInset,
                                        0,
                                        0);
            } else {
                // Make room for stoplight buttons when there is no tab title.
                return NSEdgeInsetsMake(0, stoplightButtonsWidth + extraSpace, 0, 0);
            }
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

- (BOOL)anyFullScreen {
    return _fullScreen || lionFullScreen_;
}

- (BOOL)lionFullScreen {
    return lionFullScreen_;
}

- (void)ptyWindowMakeCurrentSessionFirstResponder {
    [self.window makeFirstResponder:self.currentSession.textview];
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

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize {
    DLog(@"windowWillResize: self=%@, proposedFrameSize=%@ screen=%@",
           self, NSStringFromSize(proposedFrameSize), self.window.screen);
    DLog(@"%@", [NSThread callStackSymbols]);
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    if (self.togglingLionFullScreen || self.lionFullScreen || self.window.screen == nil) {
        DLog(@"Accepting proposal");
        return proposedFrameSize;
    }
    if (self.ptyWindow.it_isMovingScreen) {
        DLog(@"Accepting proposal (2)");
        return proposedFrameSize;
    }
    if (self.windowType == WINDOW_TYPE_MAXIMIZED || self.windowType == WINDOW_TYPE_COMPACT_MAXIMIZED) {
        DLog( @"Blocking resize" );
        self.timeOfLastResize = [NSDate timeIntervalSinceReferenceDate];
        return self.window.screen.visibleFrameIgnoringHiddenDock.size;
    }
     NSSize originalProposal = proposedFrameSize;
    // Find the session for the current pane of the current tab.
    PTYTab* tab = [self currentTab];
    if (!tab) {
        return proposedFrameSize;
    }
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
        self.timeOfLastResize = [NSDate timeIntervalSinceReferenceDate];
        proposedFrameSize.height = self.window.frame.size.height;
        if (proposedFrameSize.height == self.window.frame.size.height) {
            snapHeight = NO;
        }
    }
    if (self.windowType == WINDOW_TYPE_TOP || self.windowType == WINDOW_TYPE_BOTTOM) {
        self.timeOfLastResize = [NSDate timeIntervalSinceReferenceDate];
        proposedFrameSize.width = self.window.frame.size.width;
        if (proposedFrameSize.width == self.window.frame.size.width) {
            snapWidth = NO;
        }
    }

    // There's an advanced preference to turn off snapping globally.
    if ([iTermAdvancedSettingsModel disableWindowSizeSnap]) {
        snapWidth = snapHeight = NO;
    }

    // Let accessibility resize windows as it pleases.
    if (self.ptyWindow.it_accessibilityResizing) {
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

    int screenWidth = (contentSize.width - [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2) / charWidth;
    int screenHeight = (contentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2) / charHeight;

    if (snapWidth) {
      contentSize.width = screenWidth * charWidth + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2;
    }
    if (snapHeight) {
      contentSize.height = screenHeight * charHeight + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2;
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

- (void)invalidateRestorableState {
    [[self window] invalidateRestorableState];
    _restorableStateInvalid = YES;
}

- (BOOL)getAndResetRestorableState {
    const BOOL result = _restorableStateInvalid;
    _restorableStateInvalid = NO;
    return result;
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
                           tab:(PTYTab *)tab
            variableWindowSize:(BOOL)variableWindowSize {
    DLog(@"%@", [NSThread callStackSymbols]);
    if (liveResize_) {
        DLog(@"During live resize");
        if (nontrivialChange) {
            postponedTmuxTabLayoutChange_ = variableWindowSize ? iTermPostponeTmuxTabLayoutChangeStateVariableSizeWindow : iTermPostponeTmuxTabLayoutChangeStateFixedSizeWindow;
        }
        return;
    }
    DLog(@"Check if any tmux controller has outstanding window resizes.");
    for (TmuxController *controller in [self uniqueTmuxControllers]) {
        if ([controller hasOutstandingWindowResize]) {
            DLog(@"Yes - %@ does", controller);
            return;
        }
    }
    DLog(@"No - proceeding");
    if (variableWindowSize) {
        if (![iTermAdvancedSettingsModel disableTmuxWindowResizing]) {
            DLog(@"Variable window size and tmux window resizing is not disabled. Fit window to tab.");
            if (tab) {
                [self fitWindowToTab:tab];
            } else {
                [self fitWindowToTabs];
            }
        }
    } else {
        DLog(@"tmuxTabLayoutDidChange. Fit window to tabs");
        [self beginTmuxOriginatedResize];
        // Make the window the right size for the tmux tabs. This prevents the
        // non-tmux tabs from causing a window resize, which could get us into
        // a resize loop. See issue 10249.
        [self fitWindowToTabsExcludingTmuxTabs:NO
                              preservingHeight:NO
                              sizeOfLargestTab:[self sizeOfLargestTabWithExclusion:PseudoTerminalTabSizeExclusionRegular]];
        // Ensure the non-tmux tabs fit ok.
        [self fitNonTmuxTabsToWindow];
        [self endTmuxOriginatedResize];
    }
}

- (NSString *)tmuxPerWindowSetting {
    if (_contentView.shouldShowToolbelt == [iTermProfilePreferences boolForKey:KEY_OPEN_TOOLBELT inProfile:self.currentSession.profile]) {
        return nil;
    }
    // key=value&key=value&...
    // Semicolon is reserved. Don't use it.
    return [NSString stringWithFormat:@"toolbelt=%@", @(_contentView.shouldShowToolbelt)];
}

- (void)setTmuxPerWindowSetting:(NSString *)setting {
    DLog(@"SET per-window settings %@ for %@", setting, self.terminalGuid);
    NSArray<NSString *> *parts = [setting componentsSeparatedByString:@"&"];
    for (NSString *part in parts) {
        iTermTuple<NSString *, NSString *> *kvp = [part it_stringBySplittingOnFirstSubstring:@"="];
        if (!kvp) {
            continue;
        }
        if ([kvp.firstObject isEqualToString:@"toolbelt"]) {
            const BOOL shouldShow = [kvp.secondObject boolValue];
            if (shouldShow != [self shouldShowToolbelt]) {
                DLog(@"TOGGLE toolbelt");
                [self toggleToolbeltVisibilityWithSideEffects:NO];
            }
        }
    }
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
    for (PTYSession *session in self.allSessions) {
        [session updateMetalDriver];
        [session.textview requestDelegateRedraw];
        [session didChangeScreen:self.window.backingScaleFactor];
    }
    const NSSize screenSize = self.window.screen.frame.size;
    const CGFloat scaleFactor = self.window.screen.backingScaleFactor;
    if (!NSEqualSizes(screenSize, _previousScreenSize) ||
        scaleFactor != _previousScreenScaleFactor) {
        DLog(@"Screen changed size %@->%@ scale %@->%@ so bounce metal",
             NSStringFromSize(_previousScreenSize),
             NSStringFromSize(screenSize),
             @(_previousScreenScaleFactor),
             @(scaleFactor));
        _previousScreenSize = screenSize;
        _previousScreenScaleFactor = scaleFactor;
        // Fixes gray screen after resolution change (issue 9515). But do it only if the resolution
        // changes because some poor souls have constant screen invalidations (issue 9685).
        for (PTYTab *tab in self.tabs) {
            [tab bounceMetal];
        }
    }
    [self.contentView enumerateHierarchy:^(NSView *view) {
        if ([view respondsToSelector:@selector(enclosingWindowDidMoveToScreen:)]) {
            [(id<iTermViewScreenNotificationHandling>)view enclosingWindowDidMoveToScreen:self.window.screen];
        }
    }];
    DLog(@"Returning from windowDidChangeScreen:.");
}

- (NSArray *)screenConfiguration {
    return [[NSScreen screens] mapWithBlock:^id(NSScreen *screen) {
        return @{ @"frame": NSStringFromRect(screen.frame),
                  @"visibleFrame": NSStringFromRect(screen.visibleFrame) };
    }];
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
    if (_inWindowDidMove) {
        DLog(@"WARNING! Reentrant call to windowDidMove. Return early.");
        return;
    }
    _inWindowDidMove = YES;
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
    _inWindowDidMove = NO;
}

- (void)windowDidResize:(NSNotification *)aNotification {
    PtyLog(@"windowDidResize to: %fx%f self=%@", [[self window] frame].size.width, [[self window] frame].size.height, self);
    PtyLog(@"%@", [NSThread callStackSymbols]);
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
    lastResizeTime_ = [[NSDate date] timeIntervalSince1970];
    if (zooming_) {
        DLog(@"zooming so pretend nothing happened for better performance");
        // Pretend nothing happened to avoid slowing down zooming.
        return;
    }

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
    return timeSinceLastResize < kTimeToPreserveTemporaryTitle && [self age] > 1;
}

- (NSTimeInterval)age {
    return [NSDate it_timeSinceBoot] - _creationTime;
}

// This takes care of updating the metal state
- (void)updateUseTransparency {
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [itad updateUseTransparencyMenuItem];
    for (PTYSession* aSession in [self allSessions]) {
        [aSession useTransparencyDidChange];
        [[aSession view] setNeedsDisplay:YES];
        [[aSession textview] requestDelegateRedraw];
    }
    [self haveTransparentPaneDidChange];
}

- (void)haveTransparentPaneDidChange {
    [[self currentTab] recheckBlur];
    [self updateTabColors];  // Updates the window's background color as a side-effect
    [self updateForTransparency:self.ptyWindow];
    [_contentView invalidateAutomaticTabBarBackingHiding];
    [_contentView setCurrentSessionAlpha:self.currentSession.textview.transparencyAlpha];
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

// This is a hack to fix the problem of exiting a fullscreen window that as never not-fullscreen.
// We need to have some size to go to. This method computes the size based on the current session's
// profile's rows and columns setting plus the window decoration size. It's sort of arbitrary
// because split panes will have to share that space, but there's no perfect solution to this issue.
- (NSSize)preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration {
    PTYSession *session = [self currentSession];
    PTYTextView *textView = session.textview;
    NSSize cellSize = NSMakeSize(textView.charWidth, textView.lineHeight);
    NSSize decorationSize = [self windowDecorationSize];
    VT100GridSize sessionSize =
    VT100GridSizeMake(MIN(iTermMaxInitialSessionSize,
                          [session.profile[KEY_COLUMNS] intValue]),
                      MIN(iTermMaxInitialSessionSize,
                          [session.profile[KEY_ROWS] intValue]));
    return NSMakeSize([iTermPreferences intForKey:kPreferenceKeySideMargins] * 2 + sessionSize.width * cellSize.width + decorationSize.width,
                      [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2 + sessionSize.height * cellSize.height + decorationSize.height);
}

- (void)addShortcutAccessorViewControllerToTitleBarIfNeeded {
    DLog(@"addShortcutAccessorViewControllerToTitleBarIfNeeded");
    if (!_shortcutAccessoryViewController) {
        DLog(@"Don't already have a shortcut accessory view controller");
        return;
    }
    if (self.shouldHaveShortcutAccessory &&
        [self.window.titlebarAccessoryViewControllers containsObject:_shortcutAccessoryViewController]) {
        DLog(@"Have one and should have one");
        return;
    }
    if ([self.window respondsToSelector:@selector(addTitlebarAccessoryViewController:)] &&
        [self shouldHaveShortcutAccessory]) {
        DLog(@"Need to add one");
        // Explicitly load the view before adding. Otherwise, for some reason, on WINDOW_TYPE_MAXIMIZED windows,
        // the NSWindow miscalculates the size, and ends up resizing the iTermRootTerminalView incorrectly.
        [_shortcutAccessoryViewController view];

        [self.window addTitlebarAccessoryViewController:_shortcutAccessoryViewController];
        [self updateWindowNumberVisibility:nil];
    }
}

- (BOOL)shouldHaveShortcutAccessory {
    DLog(@"windowType=%@", @(self.windowType));

    switch (iTermThemedWindowType(self.windowType)) {
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
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return NO;
            
        case WINDOW_TYPE_LION_FULL_SCREEN:
            return ![iTermAdvancedSettingsModel workAroundBigSurBug];

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_NORMAL:
            return YES;
    }
}

- (void)toggleTraditionalFullScreenMode {
    [self toggleTraditionalFullScreenModeImpl];
}

- (BOOL)togglingLionFullScreen {
    return [self togglingLionFullScreenImpl];
}

- (BOOL)fullScreen {
    return [self fullScreenImpl];
}

- (iTermWindowType)windowType {
    return [self windowTypeImpl];
}

- (IBAction)setWindowStyle:(id)sender {
    NSMenuItem *menuItem = [NSMenuItem castFrom:sender];
    if (!menuItem) {
        DLog(@"Bogus sender: %@", sender);
        return;
    }
    [self changeToWindowType:(iTermWindowType)menuItem.tag];
    [[self currentTab] recheckBlur];
}

- (IBAction)toggleFullScreenMode:(id)sender {
    [self toggleFullScreenModeImpl:sender];
}

- (void)toggleFullScreenMode:(id)sender
                  completion:(void (^)(BOOL))completion {
    [self toggleFullScreenModeImpl:sender completion:completion];
}

- (void)delayedEnterFullscreen {
    [self delayedEnterFullscreenImpl];
}

- (void)updateWindowMenu {
    if ([iTermAdvancedSettingsModel includeShortcutInWindowsMenu]) {
        DLog(@"Include shortcut");
        [NSApp changeWindowsItem:self.window title:[self titleForWindowMenu] filename:NO];
        return;
    }

    if (!self.fullScreen) {
        DLog(@"No - not fullscreen %@", self);
        return;
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
            DLog(@"No - not minimal/compact %@", self);
            return;
    }
    DLog(@"Yes - changeWindowsItem %@", self);
    [NSApp changeWindowsItem:self.window title:self.window.title filename:NO];
}

- (void)updateForTransparency:(NSWindow<PTYWindow> *)window {
    BOOL shouldEnableShadow = NO;
    switch (self.windowType) {
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            if (!exitingLionFullscreen_) {
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
    if (@available(macOS 10.16, *)) { }
    else {
        if ([iTermAdvancedSettingsModel disableWindowShadowWhenTransparencyOnMojave]) {
            [self updateWindowShadowForNonFullScreenWindowDisablingIfAnySessionHasTransparency:window];
            shouldEnableShadow = NO;
        }
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        self.contentView.backgroundImage.hidden = YES;
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.contentView.backgroundImage.hidden = !iTermTextIsMonochrome() || (self.contentView.backgroundImage.image == nil);
        const CGFloat transparency = 1 - self.currentSession.textview.transparencyAlpha;
        self.contentView.backgroundImage.transparency = transparency;
        self.contentView.backgroundImage.blend = self.currentSession.desiredBlend;
        [CATransaction commit];
    }
    if (shouldEnableShadow) {
        window.hasShadow = YES;
    }
}

- (void)updateWindowShadowForNonFullScreenWindowDisablingIfAnySessionHasTransparency:(NSWindow *)window {
    const BOOL haveTransparency = [self anyPaneIsTransparent];
    DLog(@"%@: have transparency = %@ for sessions %@ in tab %@", self, @(haveTransparency), self.currentTab.sessions, self.currentTab);
    // Let's try enabling window shadow on 10.16 when there is transparency. Now that I set the
    // background color to NSColor.clearColor.withAlphaComponent(0.01) maybe shadows will magically
    // start working again.
    if (@available(macOS 10.16, *)) {} else {
        window.hasShadow = !haveTransparency;
    }
}

- (BOOL)tabBarShouldBeVisibleEvenWhenOnLoan {
    if (togglingLionFullScreen_ || [self lionFullScreen]) {
        return YES;
    }
    return _contentView.tabBarShouldBeVisibleEvenWhenOnLoan;
}

- (BOOL)tabBarShouldBeVisible {
    if (togglingLionFullScreen_ || [self lionFullScreen]) {
        return YES;
    }
    if (_contentView.tabBarControlOnLoan) {
        return NO;
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
    DLog(@"self=%@", self);

    [self clearForceFrame];
    liveResize_ = YES;
    if ([self windowTitleIsVisible]) {
        switch (self.windowType) {
            case WINDOW_TYPE_LION_FULL_SCREEN:
            case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            case WINDOW_TYPE_TOP_PARTIAL:
            case WINDOW_TYPE_LEFT_PARTIAL:
            case WINDOW_TYPE_NO_TITLE_BAR:
            case WINDOW_TYPE_RIGHT_PARTIAL:
            case WINDOW_TYPE_BOTTOM_PARTIAL:
            case WINDOW_TYPE_COMPACT:
            case WINDOW_TYPE_ACCESSORY:
            case WINDOW_TYPE_NORMAL:
                break;

            case WINDOW_TYPE_TOP:
            case WINDOW_TYPE_LEFT:
            case WINDOW_TYPE_RIGHT:
            case WINDOW_TYPE_BOTTOM:
            case WINDOW_TYPE_MAXIMIZED:
            case WINDOW_TYPE_COMPACT_MAXIMIZED:
                // Force the note about the window not being resizable to be shown.
                self.timeOfLastResize = [NSDate timeIntervalSinceReferenceDate];
                _previousGridSize = VT100GridSizeMake(-1, -1);
                [self setWindowTitle];
                break;

        }
    }
    if (![self windowTitleIsVisible] && !self.anyFullScreen) {
        [_contentView setShowsWindowSize:YES];
    }
    [self updateUseMetalInAllTabs];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
    DLog(@"self=%@", self);
    NSScreen *screen = self.window.screen;
    [_contentView setShowsWindowSize:NO];
    if (@available(macOS 10.16, *)) {
        // Zoom/unzoom leaves wrong titlebar separator.
        [self forceUpdateTitlebarSeparator];
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
    DLog(@"set zooming=NO");
    zooming_ = NO;
    if (wasZooming) {
        // Reached zoom size. Update size.
        [self windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification
                                                            object:nil]];
    }
    if (postponedTmuxTabLayoutChange_) {
        [self tmuxTabLayoutDidChange:YES
                                 tab:nil
                  variableWindowSize:(postponedTmuxTabLayoutChange_ == iTermPostponeTmuxTabLayoutChangeStateVariableSizeWindow)];
        postponedTmuxTabLayoutChange_ = iTermPostponeTmuxTabLayoutChangeStateNone;
    }
    [self updateUseMetalInAllTabs];
}

- (NSTitlebarAccessoryViewController *)titleBarAccessoryTabBarViewController NS_AVAILABLE_MAC(10_14) {
    if (!_titleBarAccessoryTabBarViewController) {
        _titleBarAccessoryTabBarViewController = [[iTermTabBarAccessoryViewController alloc] initWithView:[_contentView borrowTabBarControl]];
        _titleBarAccessoryTabBarViewController.layoutAttribute = NSLayoutAttributeBottom;
    }
    return _titleBarAccessoryTabBarViewController;
}

- (BOOL)shouldMoveTabBarToTitlebarAccessoryInLionFullScreen {
    if ([iTermAdvancedSettingsModel workAroundBigSurBug]) {
        DLog(@"work around big sur bug - return NO");
        return NO;
    }
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
        case PSMTab_BottomTab:
            DLog(@"left or bottom tabbar - return NO");
            return NO;

        case PSMTab_TopTab:
            if ([iTermPreferences boolForKey:kPreferenceKeyFlashTabBarInFullscreen] &&
                ![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
                DLog(@"kPreferenceKeyFlashTabBarInFullscreen && !kPreferenceKeyShowFullscreenTabBar - return NO");
                return NO;
            }
            if (@available(macOS 13.0, *)) {
                // Starting in macOS 16 and ending at or before Ventura (macOS 13) there was an ugly
                // shadow under the full-screen titlebar if there was an accessory view. That does
                // not seem to be a problem in Ventura, so we'll move the tabbar into an accessory
                // once again! See issue 11038 for how we compare to Safari.
                // However, it's apparently broken for some users. I have no idea how common of a
                // problem this is and I don't know of a workaround, so there's an advanced setting
                // in case it's widespread. Issue 11058.
                if (![iTermAdvancedSettingsModel placeTabsInTitlebarAccessoryInFullScreen]) {
                    return NO;
                }
            } else {
                if ([iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
                    DLog(@"macOS 11 + kPreferenceKeyShowFullscreenTabBar - return NO");
                    // This prevents a shadow from being drawn between the tabbar and the rest of the window.
                    // When the tabbar is hidden, it must be a titlebar accessory vc or else you'd never see it.
                    // The only downside I see is that when you reveal the titlebar it overlaps the tabbar
                    // but that doesn't seem like a big problem. Issue 9639.
                    return NO;
                }
            }
            break;
    }
    DLog(@"return YES");
    return YES;
}

// Returns whether a permanent (i.e., not flashing) tabbar ought to be drawn while in full screen.
// It does not check if you're already in full screen.
- (BOOL)shouldShowPermanentFullScreenTabBar {
    DLog(@"%@", self);
    if (togglingLionFullScreen_) {
        DLog(@"togglingLionFullSCreen so return YES");
        return YES;
    }

    if (![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
        DLog(@"Not showing fullscreen tab bar so return NO");
        return NO;
    }

    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar] && self.tabs.count == 1) {
        DLog(@"Not hiding it because of there being only one tab so return NO");
        return NO;
    }

    DLog(@"Return YES");
    return YES;
}

- (BOOL)tabBarShouldBeAccessory {
    DLog(@"%@", self);
    if (!(self.window.styleMask & NSWindowStyleMaskTitled)) {
        // You get an assertion if you try to add an accessory to an untitled window.
        DLog(@"NO - window not titled");
        return NO;
    }
    if (!exitingLionFullscreen_) {
        DLog(@"!exitingLionFullscreen");
        const BOOL assumeFullScreen = (self.lionFullScreen || togglingLionFullScreen_);
        if (assumeFullScreen) {
            DLog(@"tabBarShouldBeAccessory - assuming full screen, should=%@", @([self shouldMoveTabBarToTitlebarAccessoryInLionFullScreen]));
            return [self shouldMoveTabBarToTitlebarAccessoryInLionFullScreen];
        }
    }
    if (!self.tabBarShouldBeVisibleEvenWhenOnLoan) {
        DLog(@"NO - tab bar should not be visible");
        return NO;
    }
    switch ((PSMTabPosition)[iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
        case PSMTab_BottomTab:
            DLog(@"NO - tabs not on top");
            return NO;

        case PSMTab_TopTab:
            break;
    }
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            DLog(@"NO - minimal or compact");
            return NO;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            break;
    }
    switch (exitingLionFullscreen_ ? self.savedWindowType : self.windowType) {
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
            DLog(@"NO - window type is %@", @(self.windowType));
            return NO;
            
        case WINDOW_TYPE_LION_FULL_SCREEN:
            DLog(@"lion full screen. return %@", @(!exitingLionFullscreen_));
            return !exitingLionFullscreen_;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
            if (![iTermAdvancedSettingsModel allowTabbarInTitlebarAccessoryBigSur]) {
                if (@available(macOS 10.16, *)) {
                    DLog(@"NO - big sur");
                    return NO;
                }
            }
            DLog(@"YES - normal, accessory, or maximized");
            return YES;
    }
    assert(NO);
    return YES;
}

- (void)updateTabBarControlIsTitlebarAccessory {
    DLog(@"updateTabBarControlIsTitlebarAccessory %@", self);
    const NSInteger index = [self.window.it_titlebarAccessoryViewControllers indexOfObject:_titleBarAccessoryTabBarViewController];
    if ([self tabBarShouldBeAccessory]) {
        DLog(@"tab bar should be accessory");
        NSRect frame = _titleBarAccessoryTabBarViewController.view.superview.bounds;
        NSTitlebarAccessoryViewController *viewController = [self titleBarAccessoryTabBarViewController];
        const CGFloat tabBarHeight = self.shouldShowPermanentFullScreenTabBar ? self.desiredTabBarHeight : 0;
        viewController.fullScreenMinHeight = tabBarHeight;
        DLog(@"Set tabbar's fullScreenMinHeight to %@", @(tabBarHeight));

        frame.size.height = self.desiredTabBarHeight;
        DLog(@"Set frame of tabbar as accessory to %@", NSStringFromRect(frame));
        viewController.view.frame = frame;

        if (index == NSNotFound) {
            DLog(@"Call addTitlebarAccessoryViewController for title bar accessory view controller %@ for %@", viewController, self);
            [self.window addTitlebarAccessoryViewController:viewController];
        } else {
            DLog(@"Already have tabbar as a titlebar accessory view controller so not calling addTitlebarAccessoryViewController");
        }
    } else if (_contentView.tabBarControlOnLoan) {
        DLog(@"tab bar should NOT be accessory, but is on loan.");
        [self returnTabBarToContentView];
    }
}

- (void)returnTabBarToContentView {
    DLog(@"returnTabBarToContentView %@", self);
    const NSInteger index = [self.window.it_titlebarAccessoryViewControllers indexOfObject:_titleBarAccessoryTabBarViewController];
    if (index == NSNotFound) {
        assert(!_contentView.tabBarControlOnLoan);
        return;
    }
    assert(_contentView.tabBarControlOnLoan);
    
    [self.window removeTitlebarAccessoryViewControllerAtIndex:index];
    [_contentView returnTabBarControlView:(iTermTabBarControlView *)_titleBarAccessoryTabBarViewController.realView];
    [_titleBarAccessoryTabBarViewController release];
    _titleBarAccessoryTabBarViewController = nil;
    [_contentView layoutSubviews];
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification {
    [self windowWillEnterFullScreenImpl:notification];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    [self windowDidEnterFullScreenImpl:notification];
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window {
    [self windowDidFailToEnterFullScreenImpl:window];
}

- (void)hideStandardWindowButtonsAndTitlebarAccessories {
    DLog(@"hideStandardWindowButtonsAndTitlebarAccessories %@", self);
    [[self.window standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[self.window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[self.window standardWindowButton:NSWindowZoomButton] setHidden:YES];
    [self returnTabBarToContentView];
    while (self.window.titlebarAccessoryViewControllers.count) {
        [self.window removeTitlebarAccessoryViewControllerAtIndex:0];
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification {
    [self windowWillExitFullScreenImpl:notification];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
    [self windowDidExitFullScreenImpl:notification];
}

- (void)windowWillBeginSheet:(NSNotification *)notification {
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame {
    DLog(@"windowWillUseStandardFrame. defaultFrame=%@ self=%@", NSStringFromRect(defaultFrame), self);
    // Disable redrawing during zoom-initiated live resize.
    DLog(@"Set zooming=YES");
    zooming_ = YES;
    [self updateUseMetalInAllTabs];
    if (togglingLionFullScreen_) {
        DLog(@"Currently toggling lion full screen so accept default frame");
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
        DLog(@"Going into lion fullscreen mode so disregard maximize vertically preference");
        verticalOnly = NO;
    } else {
        maxVerticallyPref = [iTermPreferences boolForKey:kPreferenceKeyMaximizeVerticallyOnly];
        if ([[NSApp currentEvent] type] == NSEventTypeKeyDown) {
            DLog(@"Is due to keydown");
            verticalOnly = maxVerticallyPref;
        } else if (maxVerticallyPref ^
                   (([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagShift) != 0)) {
            DLog(@"Not keydown, holding shift, pref is not for vertical only. maximize vertically only");
            verticalOnly = YES;
        }
    }

    if (verticalOnly) {
        DLog(@"verticalOnly=true");
        // Keep the width the same
        proposedFrame.size.width = [sender frame].size.width;
    } else {
        DLog(@"!verticalOnly");
        proposedFrame.size.width = defaultFrame.size.width;
        proposedFrame.origin.x = defaultFrame.origin.x;
    }
    proposedFrame.size.height = defaultFrame.size.height;
    proposedFrame.origin.y = defaultFrame.origin.y;
    DLog(@"Return frame %@", NSStringFromRect(proposedFrame));
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf resetZoomIfNotLiveResizing];
    });
    return proposedFrame;
}

- (void)resetZoomIfNotLiveResizing {
    if (liveResize_) {
        DLog(@"Not resetting zoom");
        return;
    }
    zooming_ = NO;
    [self updateUseMetalInAllTabs];
}

- (void)windowWillShowInitial {
    PtyLog(@"windowWillShowInitial");
    [self assignUniqueNumberToWindow];
    iTermTerminalWindow *window = [self ptyWindow];
    // If it's a full or top-of-screen window with a screen number preference, always honor that.
    if (_isAnchoredToScreen) {
        PtyLog(@"have screen preference is set");
        NSRect frame = [window frame];
        frame.origin = preferredOrigin_;
        [window setFrame:frame display:NO];
    }
    NSUInteger numberOfTerminalWindows = [[[iTermController sharedInstance] terminals] count];
    if (numberOfTerminalWindows != 1 &&
        [iTermPreferences boolForKey:kPreferenceKeySmartWindowPlacement]) {
        PtyLog(@"Invoking smartLayout");
        [window smartLayout];
        return;
    }

    if (![iTermAdvancedSettingsModel rememberWindowPositions]) {
        DLog(@"Not remembering window poasitions");
        return;
    }

    const int screenNumber = window.screenNumber;
    [self loadAutoSaveFrame];
    if (_isAnchoredToScreen && window.screenNumber != screenNumber) {
        DLog(@"Move window to preferred origin because it moved to another screen.");
        [window setFrameOrigin:preferredOrigin_];
    }
}

- (void)loadAutoSaveFrame {
    DLog(@"-[%p loadAutoSaveFrame]. Profile is\n%@", self, self.initialProfile);
    if ([_initialProfile[KEY_DISABLE_AUTO_FRAME] boolValue]) {
        DLog(@"Auto-frame disabled.");
        return;
    }
    DLog(@"Load auto-save frame");
    iTermTerminalWindow *window = [self ptyWindow];
    NSRect frame = [window frame];
    if ([window setFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, uniqueNumber_]]) {
        DLog(@"Had an auto save frame of %@", NSStringFromRect(window.frame));
        frame.origin = [window frame].origin;
        frame.origin.y += [window frame].size.height - frame.size.height;
    } else {
        frame.origin = preferredOrigin_;
    }
    DLog(@"Update frame to %@", NSStringFromRect(frame));
    [window setFrame:frame display:NO];
}

- (BOOL)sessionInitiatedResize:(PTYSession *)session width:(int)width height:(int)height {
    __block BOOL result;
    [session resetMode];
    [session.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        PtyLog(@"sessionInitiatedResize");
        // ignore resize request when we are in full screen mode.
        if ([self anyFullScreen]) {
            PtyLog(@"sessionInitiatedResize - in full screen mode");
            result = NO;
            return;
        }

        // Defer sending TIOCSWINSZ until things have settled. The call to -safelySetSessionSize:rows:columns: may provide a size that's too big for the display.
        // It's only after fitWindowToTab that the final size is known.
        NSArray<PTYSession *> *sessions = [self allSessions];
        [iTermWinSizeController batchDeferChanges:[sessions mapWithBlock:^id _Nullable(PTYSession * _Nonnull session) {
            return session.shell.winSizeController;
        }] closure:^{
            PTYTab *tab = [self tabForSession:session];
            [tab setLockedSession:session];
            [self safelySetSessionSize:session rows:height columns:width];
            PtyLog(@"sessionInitiatedResize - calling fitWindowToTab");
            [self fitWindowToTab:tab];
            PtyLog(@"sessionInitiatedResize - calling fitTabsToWindow");
            [self fitTabsToWindow];
            [tab setLockedSession:nil];
        }];
        result = YES;
    }];
    return result;
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
                                               supermenu:theMenu
                                            withSelector:@selector(newSessionInWindowAtIndex:)
                                         openAllSelector:@selector(newSessionsInNewWindow:)
                                              startingAt:0];

    [theMenu setSubmenu:aMenu forItem:[theMenu itemAtIndex:0]];

    aMenu = [[[NSMenu alloc] init] autorelease];
    [[iTermController sharedInstance] addBookmarksToMenu:aMenu
                                               supermenu:theMenu
                                            withSelector:@selector(newSessionInTabAtIndex:)
                                         openAllSelector:@selector(newSessionsInWindow:)
                                              startingAt:0];

    [theMenu setSubmenu:aMenu forItem:[theMenu itemAtIndex:1]];
}

// NSTabView
- (void)tabView:(NSTabView *)tabView closeTab:(id)identifier button:(int)button {
    if (button != 2 || [iTermAdvancedSettingsModel middleClickClosesTab]) {
        [self closeTab:identifier];
    }
}

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    if (![[self currentSession] exited]) {
        DLog(@"Clear new-output flag in %@", [self currentSession]);
        [[self currentSession] setNewOutput:NO];
    }
    // If the user is currently select-dragging the text view, stop it so it
    // doesn't keep going in the background.
    [[[self currentSession] textview] aboutToHide];
    [self.currentTab willDeselectTab];

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
    iTermTerminalWindow *window = [self ptyWindow];
    if (nil != window &&
        [window respondsToSelector:@selector(disableBlur)]) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf reallyDisableBlurIfNeeded];
        });
    }
}

- (void)reallyDisableBlurIfNeeded {
    if (!self.currentTab.blur) {
        [self.ptyWindow disableBlur];
    }
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    DLog(@"Did select tab view %@", tabViewItem);
    [_contentView.tabBarControl setFlashing:YES];

    if (self.autoCommandHistorySessionGuid) {
        [self hideAutoCommandHistory];
    }
    PTYTab *tab = [tabViewItem identifier];
    for (PTYSession *aSession in [tab sessions]) {
        DLog(@"Clear new-output flag in %@", aSession);
        [aSession setNewOutput:NO];

        // Background tabs' timers run infrequently so make sure the display is
        // up to date to avoid a jump when it's shown.
        [[aSession textview] requestDelegateRedraw];
        [aSession updateDisplayBecause:@"tabView:didSelectTabViewItem:"];
        aSession.active = YES;
        [self setDimmingForSession:aSession];
        [[aSession view] setBackgroundDimmed:![[self window] isKeyWindow]];
        [[aSession view] didBecomeVisible];
        [aSession.textview updateScrollerForBackgroundColor];
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
    [self updateToolbeltAppearance];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    [self notifyTmuxOfTabChange];
    if ([[PreferencePanel sessionsInstance] isWindowLoaded] && ![iTermAdvancedSettingsModel pinEditSession]) {
        [self editSession:self.currentSession makeKey:NO];
    }
    [self updateTouchBarIfNeeded:NO];

    NSInteger darkCount = 0;
    NSInteger lightCount = 0;
    for (PTYSession *session in tab.sessions) {
        if ([[session.screen.colorMap colorForKey:kColorMapBackground] perceivedBrightness] < 0.5) {
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
    [self updateDocumentEdited];
    [[iTermFindPasteboard sharedInstance] updateObservers:nil internallyGenerated:NO];
    [self updateBackgroundImage];
    [_contentView setCurrentSessionAlpha:self.currentSession.textview.transparencyAlpha];
    [tab didSelectTab];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSelectedTabDidChange object:tab];
    DLog(@"Finished");
}

- (void)updateUseMetalInAllTabs {
    for (PTYTab *aTab in self.tabs) {
        [aTab updateUseMetal];
    }
}

- (BOOL)proxyIconIsAllowed {
    return [iTermPreferences boolForKey:kPreferenceKeyEnableProxyIcon];
}

- (BOOL)proxyIconShouldBeVisible {
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
        [self updateProxyIconVisibility];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    PTYSession *session = self.currentSession;
    id<iTermOrderedToken> token = [[_proxyIconOrderEnforcer newToken] autorelease];
    DLog(@"Getting current location async for prixy icon");
    [session asyncGetCurrentLocationWithCompletion:^(NSURL *url) {
        DLog(@"Got updated local pwd for proxy icon for %@: %@", session, url);
        if (weakSelf.currentSession != session) {
            DLog(@"Current session changed, ignore it");
            return;
        }
        if (![token commit]) {
            DLog(@"Out of order result, ignore it");
            return;
        }
        DLog(@"Assign to representedURL");
        self.window.representedURL = url;
        [self updateProxyIconVisibility];
    }];
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
#if BETA
    [self sanityCheckTabGUIDs];
#endif
    if ([theTab isTmuxTab]) {
        [theTab recompact];
        [theTab notifyWindowChanged];
        DLog(@"Update client size");
        [[theTab tmuxController] setSize:theTab.tmuxSize window:theTab.tmuxWindow];
    }
    [self saveAffinitiesLater:[tabViewItem identifier]];
}

- (void)sanityCheckTabGUIDs {
    NSMutableSet<NSString *> *guids = [NSMutableSet set];
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        for (PTYTab *tab in term.tabs) {
            NSString *guid = tab.stringUniqueIdentifier;
            ITBetaAssert(![guids containsObject:guid], @"Duplicate tab guid found");
        }
    }
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

- (void)setNeedsUpdateTabObjectCounts:(BOOL)needsUpdate {
    if (_needsUpdateTabObjectCounts == needsUpdate) {
        return;
    }
    if (!needsUpdate) {
        _needsUpdateTabObjectCounts = NO;
        return;
    }
    _needsUpdateTabObjectCounts = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateTabObjectCounts];
    });
}

- (void)updateTabObjectCounts {
    if (!_needsUpdateTabObjectCounts) {
        return;
    }
    [self setNeedsUpdateTabObjectCounts:NO];
    [self.tabs enumerateObjectsUsingBlock:^(PTYTab * _Nonnull tab, NSUInteger i, BOOL * _Nonnull stop) {
        [tab setObjectCount:i + 1];
        [_contentView.tabBarControl setIsProcessing:tab.isProcessing forTabWithIdentifier:tab];
    }];
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
    [self setNeedsUpdateTabObjectCounts:YES];

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

    PTYTab *tab = tabViewItem.identifier;
    [tab bounceMetal];

    NSImage *tabViewImage = [tabRootView snapshot];

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
    if (self.swipeIdentifier) {
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermSwipeHandlerCancelSwipe
                                                            object:self.swipeIdentifier];
    }
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
        // May need to enter or exit being a titlebar accessory if its visibility changed.
        [self updateTabBarControlIsTitlebarAccessory];

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
    [self updateToolbeltAppearance];
    [self setNeedsUpdateTabObjectCounts:YES];
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
    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabBar] && (self.lionFullScreen || togglingLionFullScreen_)) {
        // Hiding tabbar in fullscreen on 10.14 is extra work because it's a titlebar accessory.
        [self updateTabBarStyle];
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
    item = [[[NSMenuItem alloc] initWithTitle:@"New Tab to the Right"
                                       action:@selector(newTabToTheRight:)
                                keyEquivalent:@""] autorelease];
    [item setRepresentedObject:tabViewItem];
    [rootMenu addItem:item];

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
    PTYTab *tab = [tabViewItem identifier];
    labelTrackView.currentColor = tab.activeSession.tabColor;
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
    NSString *guid = session.profile[KEY_GUID];
    NSString *profileName = session.profile[KEY_NAME];
    if (guid) {
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if (!profile) {
            guid = session.profile[KEY_ORIGINAL_GUID];
            profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        }
        if (profile[KEY_NAME]) {
            profileName = profile[KEY_NAME];
        }
    }
    return [NSString stringWithFormat:@"Name: %@\nProfile: %@\nCommand: %@",
            [aTabViewItem.label removingHTMLFromTabTitleIfNeeded],
            profileName,
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
    alert.informativeText = @"If this is empty, the tab takes the active session’s title. Variables and function calls enclosed in \\(…) will be replaced with their evaluation. This interpolated string is evaluated in the tab’s context.";
    NSTextField *titleTextField = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 24 * 3)] autorelease];
    _currentTabTitleTextFieldDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextTab]
                                                                                           passthrough:nil
                                                                                         functionsOnly:NO];
    titleTextField.delegate = _currentTabTitleTextFieldDelegate;
    _currentTabTitleTextFieldDelegate.canWarnAboutContextMistake = YES;
    _currentTabTitleTextFieldDelegate.contextMistakeText = @"This interpolated string is evaluated in the tab’s context, not the session’s context. To access variables in the current session, use currentSession.sessionVariableNameHere";
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
    [_contentView updateTitleAndBorderViews];
}

- (void)setBackgroundColor:(nullable NSColor *)backgroundColor {
    [self setMojaveBackgroundColor:backgroundColor];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermWindowAppearanceDidChange object:self.window];
}

- (BOOL)anyPaneIsTransparent {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage] || self.currentSession.backgroundImage == nil) {
        // Panes can have separate transparency settings
        return [self.currentTab.sessions anyWithBlock:^BOOL(PTYSession *session) {
            return session.textview.transparencyAlpha < 1;
        }];
    }

    // All panes share a transparency setting
    return self.currentSession.textview.transparencyAlpha < 1;
}

- (void)disableDeferSetAppearance {
    _deferSetAppearance = NO;
    if (_haveDesiredAppearance) {
        [self safeSetAppearance:_desiredAppearance];
    }
}

- (void)safeSetAppearance:(NSAppearance *)appearance {
    if (_deferSetAppearance) {
        DLog(@"Defer set appearance to %@ for %@", appearance.name, self);
        _haveDesiredAppearance = YES;
        [_desiredAppearance autorelease];
        _desiredAppearance = [appearance retain];
        return;
    }
    DLog(@"Immediately set appearance to %@ for %@", appearance.name, self);
    self.window.appearance = appearance;
}

- (void)setMojaveBackgroundColor:(nullable NSColor *)backgroundColor NS_AVAILABLE_MAC(10_14) {
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            [self safeSetAppearance:nil];
            break;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            [self safeSetAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
            break;

        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            [self safeSetAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
            break;
    }
    self.window.backgroundColor = self.anyPaneIsTransparent ? [[NSColor clearColor] colorWithAlphaComponent:0.01] : [NSColor windowBackgroundColor];
    self.window.titlebarAppearsTransparent = [self titleBarShouldAppearTransparent];  // Keep it from showing content from other windows behind it. Issue 7108.
}

- (BOOL)titleBarShouldAppearTransparent {
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

- (BOOL)shouldTweakMinimalTabOutlineAlpha {
    if (![iTermPreferences boolForKey:kPreferenceKeyDimInactiveSplitPanes]) {
        return NO;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows] && !self.window.isKeyWindow) {
        // Trickery isn't needed because this kind of dimming looks fine for the minimal tabbar outline.
        return NO;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyDimOnlyText]) {
        return NO;
    }
    // Does a dimmed pane abut the tabbar?
    NSArray<PTYSession *> *sessions = nil;
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_LeftTab:
            sessions = self.currentTab.sessionsAtLeft;
            break;
        case PSMTab_TopTab:
            sessions = self.currentTab.sessionsAtTop;
            break;
        case PSMTab_BottomTab:
            sessions = self.currentTab.sessionsAtBottom;
            break;
    }
    for (PTYSession *session in sessions) {
        if (session == self.currentTab.activeSession) {
            continue;
        }
        return YES;
    }
    return NO;
}

- (id)tabView:(PSMTabBarControl *)tabView valueOfOption:(PSMTabBarControlOptionKey)option {
    if ([option isEqualToString:PSMTabBarControlOptionColoredSelectedTabOutlineStrength]) {
        return @([iTermAdvancedSettingsModel coloredSelectedTabOutlineStrength]);
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalStyleBackgroundColorDifference]) {
        return @([iTermAdvancedSettingsModel minimalTabStyleBackgroundColorDifference]);
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalBackgroundAlphaValue]) {
        return @(self.currentSession.textview.transparencyAlpha);
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalTextLegibilityAdjustment]) {
        return @([iTermAdvancedSettingsModel minimalTextLegibilityAdjustment]);
    } else if ([option isEqualToString:PSMTabBarControlOptionColoredUnselectedTabTextProminence]) {
        return @([iTermAdvancedSettingsModel coloredUnselectedTabTextProminence]);
    } else if ([option isEqualToString:PSMTabBarControlOptionColoredMinimalOutlineStrength]) {
        const CGFloat alpha = [iTermAdvancedSettingsModel minimalTabStyleOutlineStrength];
        if ([self shouldTweakMinimalTabOutlineAlpha]) {
            const CGFloat a = [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount] * 0.375;
            return @(1 * a + alpha * (1 - a));
        } else {
            return @(alpha);
        }
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
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence]) {
        return @([iTermAdvancedSettingsModel minimalSelectedTabUnderlineProminence]);
    } else if ([option isEqualToString:PSMTabBarControlOptionFontSizeOverride]) {
        if (![iTermAdvancedSettingsModel useCustomTabBarFontSize]) {
            return nil;
        }
        return @([iTermAdvancedSettingsModel customTabBarFontSize]);
    } else if ([option isEqualToString:PSMTabBarControlOptionDragEdgeHeight]) {
        iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        if (![self ptyWindowIsDraggable:self.ptyWindow]) {
            return @0;
        }
        switch (preferredStyle) {
            case TAB_STYLE_MINIMAL:
                return @([iTermAdvancedSettingsModel minimalEdgeDragSize]);
            case TAB_STYLE_COMPACT:
                return @([iTermAdvancedSettingsModel compactEdgeDragSize]);
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_DARK:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
            case TAB_STYLE_AUTOMATIC:
                return @0;
        }
    } else if ([option isEqualToString:PSMTabBarControlOptionAttachedToTitleBar]) {
        if (@available(macOS 10.16, *)) {
            iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
            switch (preferredStyle) {
                case TAB_STYLE_COMPACT:
                    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
                        case PSMTab_TopTab:
                            return @NO;
                        case PSMTab_LeftTab:
                        case PSMTab_BottomTab:
                            return @YES;
                    }
                    assert(NO);
                    break;

                case TAB_STYLE_MINIMAL:
                    return @YES;

                case TAB_STYLE_LIGHT:
                case TAB_STYLE_DARK:
                case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                case TAB_STYLE_DARK_HIGH_CONTRAST:
                case TAB_STYLE_AUTOMATIC:
                    return @YES;
            }
        }
    } else if ([option isEqualToString:PSMTabBarControlOptionHTMLTabTitles]) {
        return @([iTermPreferences boolForKey:kPreferenceKeyHTMLTabTitles]);
    } else if ([option isEqualToString:PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha]) {
        return @([iTermAdvancedSettingsModel minimalDeslectedColoredTabAlpha]);
    } else if ([option isEqualToString:PSMTabBarControlOptionTextColor]) {
        return [self.currentSession.textview.colorMap colorForKey:kColorMapForeground];
    } else if ([option isEqualToString:PSMTabBarControlOptionLightModeInactiveTabDarkness]) {
        return @([iTermAdvancedSettingsModel lightModeInactiveTabDarkness]);
    } else if ([option isEqualToString:PSMTabBarControlOptionDarkModeInactiveTabDarkness]) {
        return @([iTermAdvancedSettingsModel darkModeInactiveTabDarkness]);
    }
    return nil;
}

- (void)tabViewDidClickAddTabButton:(PSMTabBarControl *)tabView {
    if (self.currentSession.isTmuxClient) {
        [self newTmuxTab:nil];
    } else {
        [iTermSessionLauncher launchBookmark:nil
                                  inTerminal:self
                          respectTabbingMode:NO
                                  completion:nil];
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

- (BOOL)tabViewShouldDragWindow:(NSTabView *)tabView event:(NSEvent *)event {
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) != 0) {
        // Pressing option converts drag to window drag.
        return YES;
    }

    // Consider automatic conversion.
    if (![self themeSupportsAlternateDragModes] && _windowType != WINDOW_TYPE_NO_TITLE_BAR) {
        // Never convert to window drag in traditional themes.
        return NO;
    }
    if (_contentView.tabBarControl.numberOfVisibleTabs > 1) {
        const NSPoint point = [_contentView.tabBarControl convertPoint:event.locationInWindow fromView:nil];
        const CGFloat height = _contentView.tabBarControl.style.edgeDragHeight;
        if (height == 0) {
            return NO;
        }
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_LeftTab:
                return NO;
            case PSMTab_TopTab:
                return (point.y < height);
            case PSMTab_BottomTab:
                return (_contentView.tabBarControl.height - point.y < height);
        }
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
    // It would be a shame to send a focus report to a password prompt.
    [(session ?: self.currentSession) performBlockWithoutFocusReporting:^{
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
    }];
}

- (BOOL)tabPasswordManagerWindowIsOpen {
    return [self.window.sheets anyWithBlock:^BOOL(__kindof NSWindow *anObject) {
        return [anObject isKindOfClass:[iTermPasswordManagerPanel class]];
    }];
}

// You can drag the window by the pane title bar if it's the only pane in the only tab and the
// window has no titlebar. Note that in this situation the only way the pane title bar would exist
// is if there's a status bar on top.
- (BOOL)tabCanDragByPaneTitleBar {
    if ([[self tabs] count] != 1) {
        return NO;
    }
    switch (self.windowType) {
        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return NO;

        case WINDOW_TYPE_NO_TITLE_BAR:
            return YES;
    }
}

- (void)tabDidClearScrollbackBufferInSession:(PTYSession *)session {
    [[_contentView.toolbelt capturedOutputView] removeSelection];
    [[_contentView.toolbelt commandHistoryView] removeSelection];
    [self refreshTools];
}

- (void)tab:(PTYTab *)tab sessionDidRestart:(PTYSession *)session {
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
    [popupWindowController popWithDelegate:[self currentSession] inWindow:self.window];
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
    [iTermRecordingCodec exportRecording:self.currentSession.liveSession from:start to:end window:self.window];
}

- (void)replaceSyntheticActiveSessionWithLiveSessionIfNeeded {
    [self replaceSyntheticSessionWithLiveSessionIfNeeded:self.currentSession];
}

- (void)replaceSyntheticSessionWithLiveSessionIfNeeded:(PTYSession *)syntheticSession {
    if (syntheticSession.liveSession.screen.dvr.readOnly) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self close];
        });
    }
    if ([syntheticSession liveSession]) {
        [self showLiveSession:[syntheticSession liveSession] inPlaceOf:syntheticSession];
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
            DLog(@"Beep: no time travel allowed");
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
    if (![iTermSessionLauncher profileIsWellFormed:profile]) {
        return nil;
    }
    newSession = [[[PTYSession alloc] initSynthetic:YES] autorelease];
    // NSLog(@"New session for IR view is at %p", newSession);

    // set our preferences
    newSession.profile = profile;

    [self setupSession:newSession withSize:nil];
    [newSession setSize:oldSession.screen.size];
    [[newSession view] setViewId:[[oldSession view] viewId]];
    [[newSession view] setShowTitle:[[oldSession view] showTitle] adjustScrollView:YES];
    [[newSession view] setShowBottomStatusBar:oldSession.view.showBottomStatusBar adjustScrollView:YES];
    [[newSession view] updateFindDriver];
    [newSession setSessionSpecificProfileValues:@{ KEY_SCROLLBACK_LINES: @0 }];

    // Add this session to our term and make it current
    PTYTab *theTab = [tabViewItem identifier];
    newSession.delegate = theTab;

    DLog(@"Live session: %@, synthetic session: %@", oldSession, newSession);
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

- (void)turnOnMetalCaptureInInfoPlist {
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"You must restart iTerm2 to turn on this feature."
                               actions:@[ @"Restart Now", @"Cancel"]
                            identifier:@"RestartAfterMetalCaptureEnabled"
                           silenceable:kiTermWarningTypePersistent
                                window:self.window];
    if (selection == kiTermWarningSelection0) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MetalCaptureEnabled"];
        [[NSUserDefaults standardUserDefaults] setDouble:[NSDate timeIntervalSinceReferenceDate] + 24 * 60 * 60
                                                  forKey:@"MetalCaptureEnabledDate"];
        [NSApp relaunch];
    }
}

- (IBAction)captureNextMetalFrame:(id)sender {
    NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSNumber *metalCaptureEnabled = infoPlist[@"MetalCaptureEnabled"];
    if (!metalCaptureEnabled.boolValue && ![[NSUserDefaults standardUserDefaults] boolForKey:@"MetalCaptureEnabled"]) {
        [self turnOnMetalCaptureInInfoPlist];
        return;
    }
    self.currentSession.overrideGlobalDisableMetalWhenIdleSetting = YES;
    [self.currentTab updateUseMetal];
    self.currentSession.view.driver.captureDebugInfoForNextFrame = YES;
    self.currentSession.overrideGlobalDisableMetalWhenIdleSetting = NO;
    [self.currentSession.view setNeedsDisplay:YES];
}

- (IBAction)zoomOut:(id)sender {
    if (self.currentSession.filter.length) {
        [self.currentSession stopFiltering];
    } else {
        [self replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
    }
}

- (IBAction)zoomOnSelection:(id)sender {
    PTYSession *session = [self currentSession];
    iTermSelection *selection = session.textview.selection;
    iTermSubSelection *sub = [selection.allSubSelections lastObject];
    if (sub) {
        VT100GridAbsCoordRangeTryMakeRelative(sub.absRange.coordRange,
                                              session.screen.totalScrollbackOverflow,
                                              ^(VT100GridCoordRange range) {
            [self showRangeOfLines:NSMakeRange(range.start.y,
                                               range.end.y - range.start.y + 1)
                         inSession:session];
        });
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
    PTYSessionZoomState *state = oldSession.stateToSaveForZoom;
    PTYSession *syntheticSession = [self syntheticSessionForSession:oldSession];
    [oldSession resetMode];
    [syntheticSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.cursorVisible = NO;
    }];
    [syntheticSession appendLinesInRange:rangeOfLines fromSession:oldSession];
    [[self tabForSession:oldSession] replaceActiveSessionWithSyntheticSession:syntheticSession];
    syntheticSession.savedStateForZoom = state;
}

- (void)showLiveSession:(PTYSession *)liveSession inPlaceOf:(PTYSession *)syntheticSession {
    PTYTab *theTab = [self tabForSession:syntheticSession];
    [_instantReplayWindowController updateInstantReplayView];

    [self sessionInitiatedResize:syntheticSession
                           width:[[liveSession screen] width]
                          height:[[liveSession screen] height]];

    [syntheticSession retain];
    [theTab showLiveSession:liveSession inPlaceOf:syntheticSession];
    [liveSession restoreStateForZoom:syntheticSession.savedStateForZoom];
    [syntheticSession softTerminate];
    [syntheticSession release];
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
        Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        if (!profile) {
            return;
        }
        [self asyncSplitVertically:vertical
                            before:NO
                           profile:profile
                     targetSession:[self currentSession]
                        completion:nil
                             ready:nil];
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
    [coprocessIgnoreErrors_ setState:[Coprocess shouldIgnoreErrorsFromCommand:coprocessCommand_.stringValue] ? NSControlStateValueOn : NSControlStateValueOff];
    [NSApp runModalForWindow:coprocesssPanel_];

    [self.window endSheet:coprocesssPanel_];
    [coprocesssPanel_ orderOut:self];
}

- (IBAction)coprocessPanelEnd:(id)sender
{
    if (sender == coprocessOkButton_) {
        if ([[[coprocessCommand_ stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            DLog(@"Beep: empty coprocess");
            NSBeep();
            return;
        }
        [[self currentSession] launchCoprocessWithCommand:[coprocessCommand_ stringValue]];
        [Coprocess setSilentlyIgnoreErrors:[coprocessIgnoreErrors_ state] == NSControlStateValueOn fromCommand:[coprocessCommand_ stringValue]];
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

- (IBAction)addTrigger:(id)sender {
    [self.currentSession textViewAddTrigger:self.currentSession.selectedText ?: @""];
}

- (IBAction)editTriggers:(id)sender {
    [self.currentSession textViewEditTriggers];
}

- (IBAction)enableAllTriggers:(id)sender {
    [self.currentSession setAllTriggersEnabled:YES];
}

- (IBAction)disableAllTriggers:(id)sender {
    [self.currentSession setAllTriggersEnabled:NO];
}

- (void)toggleTriggerEnabled:(id)sender {
    [self.currentSession toggleTriggerEnabledAtIndex:[[sender representedObject] integerValue]];
}

- (IBAction)openPasteHistory:(id)sender {
    if (!pbHistoryView) {
        pbHistoryView = [[PasteboardHistoryWindowController alloc] init];
    }
    [self openPopupWindow:pbHistoryView];
}

- (IBAction)openCommandHistory:(id)sender {
    if (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        [iTermShellHistoryController showInformationalMessage];
        return;
    }
    [self openCommandHistoryWithPrefix:[[self currentSession] currentCommand]
                   sortChronologically:NO
                    currentSessionOnly:NO];
}

- (void)openCommandHistoryWithPrefix:(NSString *)prefix
                 sortChronologically:(BOOL)sortChronologically
                  currentSessionOnly:(BOOL)currentSessionOnly {
    if (!commandHistoryPopup) {
        commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] initForAutoComplete:NO];
        commandHistoryPopup.forwardKeyDown = YES;
    }
    [self openPopupWindow:commandHistoryPopup];
    NSArray<iTermCommandHistoryCommandUseMO *> *candidates =
    [commandHistoryPopup commandsForHost:[[self currentSession] currentHost]
                                                            partialCommand:prefix
                                  expand:YES];
    NSString *currentSessionGUID = self.currentSession.guid;
    NSArray<iTermCommandHistoryCommandUseMO *> *filtered;
    if (currentSessionOnly) {
        filtered = [candidates filteredArrayUsingBlock:^BOOL(iTermCommandHistoryCommandUseMO *commandUse) {
            return [commandUse.mark.sessionGuid isEqual:currentSessionGUID];
        }];
    } else {
        filtered = candidates;
    }
    [commandHistoryPopup loadCommands:filtered
                       partialCommand:prefix
                  sortChronologically:sortChronologically];
}

- (BOOL)commandHistoryIsOpenForSession:(PTYSession *)session {
    return self.currentSession == session && [[commandHistoryPopup window] isVisible];
}

- (void)closeCommandHistory {
    [commandHistoryPopup close];
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
        DLog(@"ACH Cancel delayed perform of show ACH window");
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
- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix
                                inSession:(PTYSession *)session
                              popIfNeeded:(BOOL)popIfNeeded {
    DLog(@"ACH prefix=%@ session=%@ popIfNeeded=%@", prefix, session, @(popIfNeeded));
    if ([session.guid isEqualToString:self.autoCommandHistorySessionGuid]) {
        if (!commandHistoryPopup) {
            commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] initForAutoComplete:YES];
        }
        NSArray<iTermCommandHistoryCommandUseMO *> *commands = [commandHistoryPopup commandsForHost:[session currentHost]
                                                                                     partialCommand:prefix
                                                                                             expand:NO];
        DLog(@"ACH commands=%@", commands);
        if (commands.count) {
            if (popIfNeeded) {
                DLog(@"ACH Pop");
                [commandHistoryPopup popWithDelegate:session inWindow:self.window];
            }
        } else {
            DLog(@"ACH no commands");
            [commandHistoryPopup close];
            return;
        }
        if ([commands count] == 1) {
            iTermCommandHistoryCommandUseMO *commandUse = commands[0];
            if ([commandUse.command isEqualToString:prefix]) {
                DLog(@"ACH one command that equals prefix");
                [commandHistoryPopup close];
                return;
            }
        }
        if (![[commandHistoryPopup window] isVisible]) {
            DLog(@"ACH show");
            [self showAutoCommandHistoryForSession:session];
        }
        DLog(@"ACH load commands");
        [commandHistoryPopup loadCommands:commands
                           partialCommand:prefix
                      sortChronologically:NO];
    }
    if (_autocompleteCandidateListItem && session == self.currentSession) {
        iTermShellHistoryController *history = [iTermShellHistoryController sharedInstance];
        NSArray<NSString *> *commands = [[history commandHistoryEntriesWithPrefix:prefix onHost:[session currentHost]] mapWithBlock:^id(iTermCommandHistoryEntryMO *anObject) {
            return anObject.command;
        }];
        DLog(@"ACH Set candidates=%@", commands);
        [_autocompleteCandidateListItem setCandidates:commands ?: @[]
                                     forSelectedRange:NSMakeRange(0, prefix.length)
                                             inString:prefix];
    }

}

- (void)showAutoCommandHistoryForSession:(PTYSession *)session {
    if ([iTermPreferences boolForKey:kPreferenceAutoCommandHistory]) {
        // Use a delay so we don't get a flurry of windows appearing when restoring arrangements.
        DLog(@"ACH show after 0.2 second delay for session %@", session);
        [self performSelector:@selector(reallyShowAutoCommandHistoryForSession:)
                   withObject:session
                   afterDelay:0.2];
    }
}

- (void)reallyShowAutoCommandHistoryForSession:(PTYSession *)session {
    DLog(@"ACH session=%@ currentSession=%@ window.isKey=%@ currentCommand=%@ eligible=%@",
         session,
         self.currentSession,
         @(self.window.isKeyWindow),
         session.currentCommand,
         @(session.eligibleForAutoCommandHistory));
    if ([self currentSession] == session &&
        [[self window] isKeyWindow] &&
        [[session currentCommand] length] > 0 &&
        session.eligibleForAutoCommandHistory) {
        self.autoCommandHistorySessionGuid = session.guid;
        [self updateAutoCommandHistoryForPrefix:[session currentCommand]
                                      inSession:session
                                    popIfNeeded:YES];
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
        DLog(@"more");
        [autocompleteView more];
    } else {
        DLog(@"Will open popup");
        [self openPopupWindow:autocompleteView];
        NSString *currentCommand = [[self currentSession] currentCommand];
        [autocompleteView addCommandEntries:[[self currentSession] autocompleteSuggestionsForCurrentCommand]
                                    context:currentCommand];
    }
}

- (BOOL)canSplitPaneVertically:(BOOL)isVertical withBookmark:(Profile *)theBookmark {
    if ([self inInstantReplay]) {
        // Things get very complicated in this case. Just disallow it.
        DLog(@"In instant replay");
        return NO;
    }
    NSFont* asciiFont = [ITAddressBookMgr fontWithDesc:[theBookmark objectForKey:KEY_NORMAL_FONT]];
    NSFont* nonAsciiFont = [ITAddressBookMgr fontWithDesc:[theBookmark objectForKey:KEY_NON_ASCII_FONT]];
    NSSize asciiCharSize = [PTYTextView charSizeForFont:asciiFont
                                      horizontalSpacing:[iTermProfilePreferences doubleForKey:KEY_HORIZONTAL_SPACING inProfile:theBookmark]
                                        verticalSpacing:[iTermProfilePreferences doubleForKey:KEY_VERTICAL_SPACING inProfile:theBookmark]];
    NSSize nonAsciiCharSize = [PTYTextView charSizeForFont:nonAsciiFont
                                         horizontalSpacing:[iTermProfilePreferences doubleForKey:KEY_HORIZONTAL_SPACING inProfile:theBookmark]
                                           verticalSpacing:[iTermProfilePreferences doubleForKey:KEY_VERTICAL_SPACING inProfile:theBookmark]];
    NSSize charSize = NSMakeSize(MAX(asciiCharSize.width, nonAsciiCharSize.width),
                                 MAX(asciiCharSize.height, nonAsciiCharSize.height));
    NSSize newSessionSize = NSMakeSize(charSize.width * kVT100ScreenMinColumns + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2,
                                       charSize.height * kVT100ScreenMinRows + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2);

    return [[self currentTab] canSplitVertically:isVertical withSize:newSessionSize];
}

- (void)toggleMaximizeActivePane {
    [self.currentTab toggleMaximizeSession:self.currentTab.activeSession];
}

- (void)newWindowWithBookmarkGuid:(NSString*)guid
{
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [iTermSessionLauncher launchBookmark:bookmark
                                  inTerminal:nil
                          respectTabbingMode:NO
                                  completion:nil];
    }
}

- (void)newTabWithBookmarkGuid:(NSString *)guid {
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [iTermSessionLauncher launchBookmark:bookmark
                                  inTerminal:self
                          respectTabbingMode:NO
                                  completion:nil];
    }
}


- (void)recreateTab:(PTYTab *)tab
    withArrangement:(NSDictionary *)arrangement
           sessions:(NSArray *)sessions
             revive:(BOOL)revive {
    DLog(@"Re-create tab");
    NSInteger tabIndex = [_contentView.tabView indexOfTabViewItemWithIdentifier:tab];
    if (tabIndex == NSNotFound) {
        DLog(@"The requested tab does not exist any more");
        return;
    }
    DLog(@"OK");
    NSMutableArray *allSessions = [NSMutableArray array];
    [allSessions addObjectsFromArray:sessions];
    [allSessions addObjectsFromArray:[tab sessions]];
    NSDictionary<NSString *, PTYSession *> *theMap = [PTYTab sessionMapWithArrangement:arrangement
                                                                              sessions:allSessions];

    BOOL ok = (theMap != nil);
    if (ok) {
        DLog(@"Found session map");
        // Make sure the proposed tab has at least all the sessions already in the current tab.
        for (PTYSession *sessionInExistingTab in [tab sessions]) {
            BOOL found = NO;
            for (PTYSession *sessionInProposedTab in [theMap allValues]) {
                if (sessionInProposedTab == sessionInExistingTab) {
                    DLog(@"A session in the tab matches a session in the map");
                    found = YES;
                    break;
                }
            }
            if (!found) {
                DLog(@"No session in the tab matches any session in the map");
                ok = NO;
                break;
            }
        }
    }
    if (!ok) {
        DLog(@"Can't do it. Just add each session as its own tab.");
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

    DLog(@"Replace tab with temporary tab");
    PTYSession *originalActiveSession = [tab activeSession];
    PTYTab *temporaryTab = [PTYTab tabWithArrangement:arrangement
                                                named:nil
                                           inTerminal:nil
                                      hasFlexibleView:NO
                                              viewMap:nil
                                           sessionMap:theMap
                                       tmuxController:nil
                                   partialAttachments:nil
                                     reservedTabGUIDs:[self tabGUIDs]];
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
                                       named:nil
                                  inTerminal:self
                             hasFlexibleView:NO
                                     viewMap:nil
                                  sessionMap:sessionMap
                              tmuxController:nil
                          partialAttachments:nil
                            reservedTabGUIDs:[self tabGUIDs]];
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

- (void)splitVertically:(BOOL)isVertical
                 before:(BOOL)before
          addingSession:(PTYSession *)newSession
          targetSession:(PTYSession *)targetSession
           performSetup:(BOOL)performSetup {
    DLog(@"splitVertically:%@ before:%@ addingSession:%@ targetSession:%@ performSetup:%@ self=%@",
         @(isVertical), @(before), newSession, targetSession, @(performSetup), self);
    [self.currentSession.textview refuseFirstResponderAtCurrentMouseLocation];
    NSView *scrollView;
    NSColor *tabColor;
    PTYTab *tab = [self tabForSession:targetSession] ?: [self currentTab];
    if (newSession.tabColor) {
        // The new session came with a tab color of its own so don't inherit.
        tabColor = newSession.tabColor;
    } else {
        // Inherit from tab.
        tabColor = [[[_contentView.tabBarControl tabColorForTabViewItem:[tab tabViewItem]] retain] autorelease];
    }
    [tab splitVertically:isVertical
              newSession:newSession
                  before:before
           targetSession:targetSession];
    SessionView *sessionView = newSession.view;
    scrollView = sessionView.scrollview;
    NSSize size = [sessionView frame].size;
    if (performSetup) {
        [self setupSession:newSession withSize:&size];
        scrollView = newSession.view.scrollview;
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
    [tab recheckBlur];
    [tab numberOfSessionsDidChange];
    [self setDimmingForSessions];
    for (PTYSession *session in self.currentTab.sessions) {
        [session.view updateDim];
    }
    if ([[ProfileModel sessionsInstance] bookmarkWithGuid:newSession.profile[KEY_GUID]]) {
        // We know the GUID is unique and in sessions instance and the original guid is already set.
        // This might be possible to do earlier, but I'm afraid of introducing bugs.
        [newSession inheritDivorceFrom:targetSession
                                decree:[NSString stringWithFormat:@"Split vertically with guid %@",
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

- (void)didFailToSplitTmuxPane {
    for (PTYSession *session in self.allSessions) {
        session.sessionIsSeniorToTmuxSplitPane = NO;
    }
}

- (iTermSessionFactory *)sessionFactory {
    if (!_sessionFactory) {
        _sessionFactory = [[iTermSessionFactory alloc] init];
    }
    return _sessionFactory;
}

- (void)asyncSplitVertically:(BOOL)isVertical
                      before:(BOOL)before
                     profile:(Profile *)theBookmark
               targetSession:(PTYSession *)targetSession
                  completion:(void (^)(PTYSession *, BOOL ok))completion
                       ready:(void (^)(PTYSession *, BOOL ok))ready {
    if ([targetSession isTmuxClient]) {
        [self willSplitTmuxPane];
        TmuxController *controller = [targetSession tmuxController];
        [controller selectPane:targetSession.tmuxPane];
        [controller splitWindowPane:[targetSession tmuxPane]
                         vertically:isVertical
                              scope:[[self tabForSession:targetSession] variablesScope]
                   initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:targetSession.profile objectType:iTermPaneObject]
                         completion:^(int wp) {
            if (wp < 0) {
                [self didFailToSplitTmuxPane];
                if (completion) {
                    completion(nil, NO);
                }
                if (ready) {
                    ready(nil, NO);
                }
                return;
            }

            [controller whenPaneRegistered:wp call:^(PTYSession *newSession) {
                if (completion) {
                    completion(newSession, YES);
                }
                if (ready) {
                    ready(newSession, YES);
                }
            }];
        }];
        return;
    }

    if (![iTermSessionLauncher profileIsWellFormed:theBookmark]) {
        if (ready) {
            ready(nil, NO);
        }
        if (completion) {
            completion(nil, NO);
        }
        return;
    }
    PTYSession *currentSession = [self currentSession];
    if (currentSession) {
        [currentSession asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory:^(NSString *oldCWD) {
            DLog(@"Get local pwd so I can split: %@", oldCWD);
            if (theBookmark.sshIdentity != nil && ![currentSession.sshIdentity isEqualTo:theBookmark.sshIdentity]) {
                oldCWD = nil;
            }
            PTYSession *session = [self splitVertically:isVertical
                                                 before:before
                                                profile:theBookmark
                                          targetSession:targetSession
                                                 oldCWD:oldCWD
                                            parentScope:currentSession.variablesScope
                                             completion:ready];
            if (completion) {
                completion(session, YES);
            }
        }];
        return;
    }

    ITBetaAssert(NO, @"This should be impossible! Splitting without a current session.");
    PTYSession *session = [self splitVertically:isVertical
                                         before:before
                                        profile:theBookmark
                                  targetSession:targetSession
                                         oldCWD:nil
                                     parentScope:nil
                                     completion:ready];
    if (completion) {
        completion(session, YES);
    }
}

- (PTYSession *)splitVertically:(BOOL)isVertical
                         before:(BOOL)before
                        profile:(Profile *)theBookmark
                  targetSession:(PTYSession *)targetSession
                         oldCWD:(NSString *)oldCWD
                    parentScope:(iTermVariableScope *)parentScope
                     completion:(void (^)(PTYSession *, BOOL))completion {
    if ([targetSession isTmuxClient]) {
        [self willSplitTmuxPane];
        TmuxController *controller = [targetSession tmuxController];
        [controller selectPane:targetSession.tmuxPane];
        [controller splitWindowPane:[targetSession tmuxPane]
                         vertically:isVertical
                              scope:[[self tabForSession:targetSession] variablesScope]
                   initialDirectory:[iTermInitialDirectory initialDirectoryFromProfile:targetSession.profile objectType:iTermPaneObject]
                         completion:nil];
        if (completion) {
            completion(nil, NO);
        }
        return nil;
    }
    PtyLog(@"--------- splitVertically -----------");
    if (![self canSplitPaneVertically:isVertical withBookmark:theBookmark]) {
        DLog(@"Beep: can't split");
        NSBeep();
        return nil;
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
    PTYSession* newSession = [[self.sessionFactory newSessionWithProfile:theBookmark
                                                                  parent:targetSession] autorelease];
    [self splitVertically:isVertical
                   before:before
            addingSession:newSession
            targetSession:targetSession
             performSetup:YES];

    __weak __typeof(self) weakSelf = self;
    iTermSessionAttachOrLaunchRequest *launchRequest =
    [iTermSessionAttachOrLaunchRequest launchRequestWithSession:newSession
                                                      canPrompt:YES
                                                     objectType:iTermPaneObject
                                            hasServerConnection:NO
                                               serverConnection:(iTermGeneralServerConnection){}
                                                      urlString:nil
                                                   allowURLSubs:NO
                                                    environment:@{}
                                                    customShell:[ITAddressBookMgr customShellForProfile:theBookmark]
                                                         oldCWD:oldCWD
                                                 forceUseOldCWD:NO
                                                        command:nil
                                                         isUTF8:nil
                                                  substitutions:nil
                                               windowController:self
                                                          ready:^(BOOL ok) {
        if (!ok) {
            [newSession terminate];
            [[weakSelf tabForSession:newSession] removeSession:newSession];
        }
    }
                                                     completion:completion];
    [self.sessionFactory attachOrLaunchWithRequest:launchRequest];
    return newSession;
}

- (Profile *)profileForSplittingCurrentSession {
    return [self.currentSession profileForSplit] ?: [[ProfileModel sharedInstance] defaultBookmark];
}

- (IBAction)splitVertically:(id)sender {
    [self asyncSplitVertically:YES
                        before:NO
                       profile:[self profileForSplittingCurrentSession]
                 targetSession:[[self currentTab] activeSession]
                    completion:nil
                         ready:nil];
}

- (IBAction)splitHorizontally:(id)sender {
    [self asyncSplitVertically:NO
                        before:NO
                       profile:[self profileForSplittingCurrentSession]
                 targetSession:[[self currentTab] activeSession]
                    completion:nil
                         ready:nil];
}

- (void)tabActiveSessionDidChange {
    if (self.autoCommandHistorySessionGuid) {
        [self hideAutoCommandHistory];
    }
    [[_contentView.toolbelt commandHistoryView] updateCommands];
    [[_contentView.toolbelt snippetsView] currentSessionDidChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSnippetsTagsDidChange object:nil];
    [[_contentView.toolbelt jobsView] updateJobs];
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
    [self updateToolbeltAppearance];
    [[iTermFindPasteboard sharedInstance] updateObservers:nil internallyGenerated:NO];
    for (PTYSession *session in self.currentTab.sessions) {
        [session updateViewBackgroundImage];
    }
    [_contentView setCurrentSessionAlpha:self.currentSession.textview.transparencyAlpha];
}

- (void)fitWindowToTabs {
    [self fitWindowToTabsExcludingTmuxTabs:NO preservingHeight:NO];
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux {
    [self fitWindowToTabsExcludingTmuxTabs:excludeTmux preservingHeight:NO];
}

typedef NS_ENUM(NSUInteger, PseudoTerminalTabSizeExclusion) {
    PseudoTerminalTabSizeExclusionNone,
    PseudoTerminalTabSizeExclusionTmux,
    PseudoTerminalTabSizeExclusionRegular  // exclude non-tmux
};

- (NSSize)sizeOfLargestTabWithExclusion:(PseudoTerminalTabSizeExclusion)exclusion {
    // Determine the size of the largest tab.
    NSSize maxTabSize = NSZeroSize;
    PtyLog(@"fitWindowToTabs.......");
    DLog(@"Finding the biggest tab:");
    for (NSTabViewItem* item in [_contentView.tabView tabViewItems]) {
        PTYTab* tab = [item identifier];
        switch (exclusion) {
            case PseudoTerminalTabSizeExclusionTmux:
                if (tab.isTmuxTab) {
                    continue;
                }
                break;
            case PseudoTerminalTabSizeExclusionNone:
                break;
            case PseudoTerminalTabSizeExclusionRegular:
                if (!tab.isTmuxTab) {
                    continue;
                }
                break;
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
    DLog(@"Max tab size is %@", NSStringFromSize(maxTabSize));
    return maxTabSize;
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux preservingHeight:(BOOL)preserveHeight {
    [self fitWindowToTabsExcludingTmuxTabs:excludeTmux
                          preservingHeight:preserveHeight
                          sizeOfLargestTab:[self sizeOfLargestTabWithExclusion:excludeTmux ? PseudoTerminalTabSizeExclusionTmux : PseudoTerminalTabSizeExclusionNone]];
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux
                        preservingHeight:(BOOL)preserveHeight
                        sizeOfLargestTab:(NSSize)maxTabSize {
    DLog(@"fitWindowToTabsExcludingTmuxTabs:%@ preservingHeight:%@ sizeOfLargestTab:%@ from\n%@",
         @(excludeTmux), @(preserveHeight), NSStringFromSize(maxTabSize), [NSThread callStackSymbols]);

    _windowNeedsInitialSize = NO;
    if (togglingFullScreen_) {
        DLog(@"Toggling full screen, abort");
        return;
    }

    if (NSEqualSizes(NSZeroSize, maxTabSize)) {
        // all tabs are tmux tabs.
        DLog(@"max tab size is zero, abort");
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
    DLog(@"fitWindowToTabSize:%@ preferredHeight:%@", NSStringFromSize(tabSize), preferredHeight);
    if ([self anyFullScreen]) {
        DLog(@"Full screen - fit tabs to window instead.");
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
    DLog(@"Original frame: %@ maxy=%@", NSStringFromRect(frame), @(NSMaxY(frame)));

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
        XLog(@"* max frame size was not positive; aborting fitWindowToTabSize");
        return NO;
    }
    if (winSize.width > maxFrameSize.width ||
        winSize.height > maxFrameSize.height) {
        mustResizeTabs = YES;
    }
    winSize.width = MIN(winSize.width, maxFrameSize.width);
    winSize.height = MIN(winSize.height, maxFrameSize.height);

    CGFloat heightChange = winSize.height - [[self window] frame].size.height;
    DLog(@"Existing height is %@. heightChange is %@", @([[self window] frame].size.height), @(heightChange));
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
    if (_shortcutAccessoryViewController) {
        workAroundBugFix = NO;
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

    const BOOL didResize = !NSEqualRects([[self window] frame], frame);
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
        [[session textview] requestDelegateRedraw];
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

- (void)swapPaneLeft {
    PTYSession* session = [[self currentTab] sessionLeftOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (void)swapPaneRight {
    PTYSession* session = [[self currentTab] sessionRightOf:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (void)swapPaneUp {
    PTYSession* session = [[self currentTab] sessionAbove:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (void)swapPaneDown {
    PTYSession* session = [[self currentTab] sessionBelow:[[self currentTab] activeSession]];
    if (session) {
        [[self currentTab] swapSession:[[self currentTab] activeSession] withSession:session];
    }
}

- (IBAction)addNoteAtCursor:(id)sender {
    [[self currentSession] addNoteAtCursor];
}

- (IBAction)nextMark:(id)sender {
    [[self currentSession] nextMark];
}

- (IBAction)previousMark:(id)sender {
    [[self currentSession] previousMark];
}

- (IBAction)nextAnnotation:(id)sender {
    [[self currentSession] nextAnnotation];
}

- (IBAction)previousAnnotation:(id)sender {
    [[self currentSession] previousAnnotation];
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

- (PTYTab *)openTabWithArrangement:(NSDictionary *)arrangement
                             named:(NSString *)arrangementName
                   hasFlexibleView:(BOOL)hasFlexible
                           viewMap:(NSDictionary<NSNumber *, SessionView *> *)viewMap
                        sessionMap:(NSDictionary<NSString *, PTYSession *> *)sessionMap
                partialAttachments:(NSDictionary *)partialAttachments {
    PTYTab *theTab = [PTYTab tabWithArrangement:arrangement
                                          named:arrangementName
                                     inTerminal:self
                                hasFlexibleView:hasFlexible
                                        viewMap:viewMap
                                     sessionMap:sessionMap
                                 tmuxController:nil
                             partialAttachments:partialAttachments
                               reservedTabGUIDs:[self tabGUIDs]];
    if ([[theTab sessionViews] count] == 0) {
        return nil;
    }

    if (hasFlexible) {
        // Tmux tab
        [self appendTab:theTab];
    } else {
        [self addTabAtAutomaticallyDeterminedLocation:theTab];
    }
    [theTab didAddToTerminal:self
             withArrangement:arrangement];
    return theTab;
}

- (NSSet<NSString *> *)tabGUIDs {
    return [NSSet setWithArray:[self.tabs mapWithBlock:^id(PTYTab *tab) {
        return tab.stringUniqueIdentifier;
    }]];
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

- (void)setBroadcastingSessions:(NSArray<NSArray<PTYSession *> *> *)domains {
    NSSet<NSSet<NSString *> *> *stringDomains = [NSSet setWithArray:[domains mapWithBlock:^id(NSArray<PTYSession *> *sessions) {
        return [NSSet setWithArray:[sessions mapWithBlock:^id(PTYSession *session) {
            return session.guid;
        }]];
    }]];
    _broadcastInputHelper.broadcastDomains = stringDomains;
}

- (void)setBroadcastMode:(BroadcastMode)mode {
    DLog(@"setBroadcastMode:%@ self=%@", @(mode), self);
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
    [self setNeedsUpdateTabObjectCounts:YES];
    [self tabsDidReorder];
}

- (IBAction)moveTabRight:(id)sender {
    NSInteger selectedIndex = [_contentView.tabView indexOfTabViewItem:[_contentView.tabView selectedTabViewItem]];
    NSInteger destinationIndex = (selectedIndex + 1) % [_contentView.tabView numberOfTabViewItems];
    [self moveTabAtIndex:selectedIndex toIndex:destinationIndex];
}

- (IBAction)increaseHeight:(id)sender {
    [self increaseHeightOfSession:self.currentSession];
}

- (IBAction)decreaseHeight:(id)sender {
    [self decreaseHeightOfSession:self.currentSession];
}

- (IBAction)increaseWidth:(id)sender {
    [self increaseWidthOfSession:self.currentSession];
}

- (IBAction)decreaseWidth:(id)sender {
    [self decreaseWidthOfSession:self.currentSession];
}


- (IBAction)increaseHeightOfSession:(PTYSession *)session {
    [self sessionInitiatedResize:session
                           width:session.columns
                          height:session.rows+1];
}

- (IBAction)decreaseHeightOfSession:(PTYSession *)session {
    [self sessionInitiatedResize:session
                           width:session.columns
                          height:session.rows-1];
}

- (IBAction)increaseWidthOfSession:(PTYSession *)session {
    [self sessionInitiatedResize:session
                           width:session.columns+1
                          height:session.rows];
}

- (IBAction)decreaseWidthOfSession:(PTYSession *)session {
    [self sessionInitiatedResize:session
                           width:session.columns-1
                          height:session.rows];

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

    DLog(@"Point %lf,%lf not in any screen", p.x, p.y);
    return 0;
}

- (void)updateWindowNumberVisibility:(NSNotification *)aNotification {
    // This is if displaying of window number was toggled in prefs.
    if (_shortcutAccessoryViewController) {
        _shortcutAccessoryViewController.view.hidden = ![iTermPreferences boolForKey:kPreferenceKeyShowWindowNumber];
    } else {
        [self setWindowTitle];
    }
}

static BOOL iTermApproximatelyEqualRects(NSRect lhs, NSRect rhs, double epsilon) {
    if (fabs(NSMinX(lhs) - NSMinX(rhs)) > epsilon) {
        return NO;
    }
    if (fabs(NSMaxX(lhs) - NSMaxX(rhs)) > epsilon) {
        return NO;
    }
    if (fabs(NSMinY(lhs) - NSMinY(rhs)) > epsilon) {
        return NO;
    }
    if (fabs(NSMaxY(lhs) - NSMaxY(rhs)) > epsilon) {
        return NO;
    }
    return YES;
}

- (void)scrollerStyleDidChange:(NSNotification *)notification {
    DLog(@"scrollerStyleDidChange %@", @([NSScroller preferredScrollerStyle]));

    [self updateSessionScrollbars];
    if ([self anyFullScreen]) {
        [self fitTabsToWindow];
    } else {
        // The scrollbar has already been added so tabs' current sizes are wrong.
        // Use ideal sizes instead, to fit to the session dimensions instead of
        // the existing pixel dimensions of the tabs.

        // Resize the window only if doing so would not cause it to lose maximized state.
        DLog(@"screen visibleFrame is %@, window frame is %@",
             NSStringFromRect(self.window.screen.visibleFrame),
             NSStringFromRect(self.window.frame));
        if (fabs(NSMaxX(self.window.screen.visibleFrame) - NSMaxX(self.window.frame)) > 0.5) {
            DLog(@"Fit window to idealized tabs preserving height");
            [self fitWindowToIdealizedTabsPreservingHeight:YES];
        } else {
            DLog(@"Window's frame matches screen's visible frame so not adjusting window size due to scroller style change");
        }
        [self fitTabsToWindow];
        for (TmuxController *controller in [self uniqueTmuxControllers]) {
            [controller fitLayoutToWindows];
        }
    }
}

- (void)refreshTerminal:(NSNotification *)aNotification {
    PtyLog(@"refreshTerminal - calling fitWindowToTabs");
    if (_settingStyleMask) {
        DLog(@"Prevent re-entrant style mask setting");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshTerminal:nil];
        });
        return;
    }
    if (self.windowType != _windowType) {
        [self updateWindowType];
    }
    // Save the size of the largest tab before adding or removing tabbar accessories. We want to
    // preserve the tab size when we update the window size below. Modifying the title bar
    // accessories synchronously changes the tabs' sizes, causing the window not to resize when
    // the tab bar shows or hides.
    const NSSize tabSizeBeforeUpdatingTitleBarAccessories = [self sizeOfLargestTabWithExclusion:PseudoTerminalTabSizeExclusionNone];

    [self updateTabBarStyle];
    [self safelySetStyleMask:self.styleMask];
    [self updateProxyIcon];
    [self updateForTransparency:self.ptyWindow];
    [self updateWindowMenu];
    // If hiding of menu bar changed.
    if ([self fullScreen] && ![self lionFullScreen]) {
        if ([[self window] isKeyWindow]) {
            // This is only used when changing broadcast mode; otherwise, the kRefreshTerminalNotification
            // notif is never posted when this window is key.
            [[iTermPresentationController sharedInstance] update];
        }
        [self.window setFrame:[self traditionalFullScreenFrame] display:YES];
    }

    [self fitWindowToTabsExcludingTmuxTabs:NO
                          preservingHeight:NO
                          sizeOfLargestTab:tabSizeBeforeUpdatingTitleBarAccessories];

    // If tab style or position changed.
    [self repositionWidgets];

    // In case scrollbars came or went:
    for (PTYTab *aTab in [self tabs]) {
        for (PTYSession *aSession in [aTab sessions]) {
            [aTab fitSessionToCurrentViewSize:aSession];
            // Theme change affects scrollbar color.
            [aSession.textview updateScrollerForBackgroundColor];
            // In case separate separate bg images per pane changed.
            [aSession updateViewBackgroundImage];
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
    [_contentView setCurrentSessionAlpha:self.currentSession.textview.transparencyAlpha];
    // If the theme changed from light to dark make sure split pane dividers redraw.
    [_contentView.tabView setNeedsDisplay:YES];
}

- (BOOL)rootTerminalViewWindowNumberLabelShouldBeVisible {
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
                                                                   style:_contentView.tabBarControl.style
                                                       transparencyAlpha:self.currentSession.textview.transparencyAlpha];
}

- (NSColor *)windowDecorationColor {
    const BOOL fakeWindowTitleBar = ([self.tabView indexOfTabViewItem:self.tabView.selectedTabViewItem] == 0 &&
                            !self.tabBarAlwaysVisible);
    if (self.currentSession.tabColor &&
        fakeWindowTitleBar &&
        [iTermAdvancedSettingsModel minimalTabStyleTreatLeftInsetAsPartOfFirstTab]) {
        // The window number will be displayed over the tab color.
        // Use text color of first tab when the first tab is selected.
        return [_contentView.tabBarControl.style textColorForCell:_contentView.tabBarControl.cells.firstObject];
    }
    
    // The window number will be displayed over the tabbar color. For non-key windows, use the
    // non-selected tab text color because that more closely matches the titlebar color.
    const BOOL mainAndActive = (self.window.isMainWindow && NSApp.isActive);
    NSColor *color;
    color = [_contentView.tabBarControl.style textColorDefaultSelected:mainAndActive
                                                       backgroundColor:fakeWindowTitleBar ? self.currentSession.tabColor : nil
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

- (CGFloat)desiredTabBarHeight {
    if ([self shouldHaveTallTabBar]) {
        return [iTermAdvancedSettingsModel compactMinimalTabBarHeight];
    } else {
        return [iTermAdvancedSettingsModel defaultTabBarHeight];
    }
}

- (CGFloat)rootTerminalViewHeightOfTabBar:(iTermRootTerminalView *)sender {
    return [self desiredTabBarHeight];
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

- (NSString *)rootTerminalViewCurrentTabSubtitle {
    return self.currentSession.subtitle;
}

- (BOOL)rootTerminalViewShouldRevealStandardWindowButtons {
    return [self shouldRevealStandardWindowButtons];
}

- (BOOL)shouldRevealStandardWindowButtons {
    if (self.enteringLionFullscreen) {
        return YES;
    }
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

- (void)updateProxyIconVisibility {
    const BOOL hideProxy = ([self proxyIconIsAllowed] &&
                            ![self proxyIconShouldBeVisible]);
    [[self.window standardWindowButton:NSWindowDocumentIconButton] setHidden:hideProxy];
}

- (BOOL)rootTerminalViewShouldDrawStoplightButtons {
    [self updateProxyIconVisibility];

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
        DLog(@"YES because window type %@ has full size content view", @(self.windowType));
        return YES;
    }
    if (!self.anyFullScreen) {
        DLog(@"NO because not any full screen");
        return NO;
    }
    BOOL topTabBar = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab);
    if (!topTabBar) {
        DLog(@"NO because tabbar not on top");
        return NO;
    }
    if ([PseudoTerminal windowTypeHasFullSizeContentView:self.savedWindowType]) {
        DLog(@"YES because saved window type %@ has full size content view", @(self.savedWindowType));
        if (![iTermAdvancedSettingsModel allowTabbarInTitlebarAccessoryBigSur] &&
            !self.lionFullScreen &&
            !togglingLionFullScreen_) {
            if (@available(macOS 10.16, *)) {
                DLog(@"NO because big sur");
                return NO;
            }
        }
        // The tab bar is not a titlebar accessory
        return YES;
    }
    DLog(@"NO because saved window type %@ does not have full size content view", @(self.savedWindowType));
    return NO;
}

// Generally yes, but not when a fake titlebar is shown *and* the window has transparency.
// Fake titlebars need a background because transparent windows won't give you one for free.
- (BOOL)rootTerminalViewShouldHideTabBarBackingWhenTabBarIsHidden {
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
    if ([iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_MINIMAL) {
        return YES;
    }
    return NO;
}

- (void)rootTerminalViewWillLayoutSubviews {
    if (@available(macOS 10.16, *)) {
        const iTermShouldHaveTitleSeparator shouldHave =
        [self terminalWindowShouldHaveTitlebarSeparator] ?
            iTermShouldHaveTitleSeparatorYes : iTermShouldHaveTitleSeparatorNo;
        if (shouldHave != _previousTerminalWindowShouldHaveTitlebarSeparator) {
            [self forceUpdateTitlebarSeparator];
            _previousTerminalWindowShouldHaveTitlebarSeparator = shouldHave;
        }
    }
}
- (void)forceUpdateTitlebarSeparator NS_AVAILABLE_MAC(10_16) {
    NSTitlebarSeparatorStyle saved = self.window.titlebarSeparatorStyle;
    self.window.titlebarSeparatorStyle = (saved == NSTitlebarSeparatorStyleAutomatic) ? NSTitlebarSeparatorStyleNone : NSTitlebarSeparatorStyleAutomatic;
    self.window.titlebarSeparatorStyle = saved;
}

- (VT100GridSize)rootTerminalViewCurrentSessionSize {
    PTYSession *session = self.currentSession;
    VT100GridSize size = VT100GridSizeMake(session.columns, session.rows);
    return size;
}

- (NSString *)rootTerminalViewWindowSizeViewDetailString {
    switch (self.windowType) {
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

        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
            return @"Fixed-width window";

        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
            return @"Fixed-height window";

        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            return @"Fixed-size window";
    }
    return nil;
}
- (void)updateTabBarStyle {
    DLog(@"%@\n%@", self, [NSThread callStackSymbols]);
    id<PSMTabStyle> style = [[iTermTheme sharedInstance] tabStyleWithDelegate:self
                                                          effectiveAppearance:self.window.effectiveAppearance];
    [_contentView.tabBarControl setStyle:style];
    [_contentView.tabBarControl setTabsHaveCloseButtons:[iTermPreferences boolForKey:kPreferenceKeyTabsHaveCloseButton]];
    _contentView.tabBarControl.height = [self desiredTabBarHeight];

    [[self currentTab] recheckBlur];
    [self updateTabColors];
    [self updateToolbeltAppearance];
    [self updateTabBarControlIsTitlebarAccessory];
    self.tabBarControl.insets = [self tabBarInsets];

    [self addShortcutAccessorViewControllerToTitleBarIfNeeded];
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
    if (self.anyPaneIsTransparent) {
        return YES;
    }
    if ([iTermAdvancedSettingsModel bordersOnlyInLightMode]) {
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

- (BOOL)tabBarIsVisibleInTitleBarAccessory {
    return _contentView.tabBarControlOnLoan;
}

// See the note in windowDecorationSize about this hack.
- (BOOL)shouldCompensateForDisappearingTabBarAccessory {
    return (!self.tabBarShouldBeAccessory && _contentView.tabBarControlOnLoan);
}

// Returns the size of the stuff outside the tabview.
- (NSSize)windowDecorationSize {
    NSSize decorationSize = NSZeroSize;

    if (!_contentView.tabBarControl.flashing &&
        [self tabBarShouldBeVisibleWithAdditionalTabs:tabViewItemsBeingAdded]) {
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_TopTab:
            case PSMTab_BottomTab:
                if (![self tabBarIsVisibleInTitleBarAccessory]) {
                    decorationSize.height += _contentView.tabBarControl.height;
                }
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

    if (self.divisionViewShouldBeVisible) {
        ++decorationSize.height;
    }
    if ([self shouldPlaceStatusBarOutsideTabview]) {
        decorationSize.height += iTermGetStatusBarHeight();
    }
    NSSize result = [[self window] frameRectForContentRect:NSMakeRect(0, 0, decorationSize.width, decorationSize.height)].size;
    if (self.shouldCompensateForDisappearingTabBarAccessory) {
        // Tab bar is currently an accessory but is about to go away and should not be included.
        // We can't remove it before measuring in this case because then the tabview grows to fill
        // the space, causing -fitWindowToTabs to keep the window the same size instead of shrinking
        // it by the height of the tab bar. This code path should only be taken when the last tab
        // disappears and tabView:didChangeNumberOfTabViewItems: calls -fitWindowToSize.
        result.height -= _contentView.tabBarControl.frame.size.height;
    }
    return result;
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
    int rows = MIN(iTermMaxInitialSessionSize,
                   [[profile objectForKey:KEY_ROWS] intValue]);
    int columns = MIN(iTermMaxInitialSessionSize,
                      [[profile objectForKey:KEY_COLUMNS] intValue]);
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

    if (![iTermSessionLauncher profileIsWellFormed:profile]) {
        @throw [NSException exceptionWithName:@"MissingFonts"
                                       reason:@"No usable font could be found"
                                     userInfo:nil];
    }
    NSSize charSize = [PTYTextView charSizeForFont:[ITAddressBookMgr fontWithDesc:[profile objectForKey:KEY_NORMAL_FONT]]
                                 horizontalSpacing:[iTermProfilePreferences doubleForKey:KEY_HORIZONTAL_SPACING inProfile:profile]
                                   verticalSpacing:[iTermProfilePreferences doubleForKey:KEY_VERTICAL_SPACING inProfile:profile]];

    if (size == nil && [_contentView.tabView numberOfTabViewItems] != 0) {
        NSSize contentSize = [[[[self currentSession] view] scrollview] documentVisibleRect].size;
        rows = (contentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]*2) / charSize.height;
        columns = (contentSize.width - [iTermPreferences intForKey:kPreferenceKeySideMargins]*2) / charSize.width;
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
        rows = (contentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]*2) / charSize.height;
        columns = (contentSize.width - [iTermPreferences intForKey:kPreferenceKeySideMargins]*2) / charSize.width;
        sessionRect.origin = NSZeroPoint;
        sessionRect.size = *size;
    } else {
        sessionRect = NSMakeRect(0, 0, columns * charSize.width + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2, rows * charSize.height + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2);
    }

    if ([aSession setScreenSize:sessionRect parent:self]) {
        PtyLog(@"setupSession - call safelySetSessionSize");
        [self safelySetSessionSize:aSession rows:rows columns:columns];
        PtyLog(@"setupSession - call setPreferencesFromAddressBookEntry");
        [aSession setPreferencesFromAddressBookEntry:profile];
        [aSession loadInitialColorTableAndResetCursorGuide];
        [aSession.screen resetTimestamps];
    }
}

- (IBAction)moveSessionToWindow:(id)sender {
    [[MovePaneController sharedInstance] moveSessionToNewWindow:[self currentSession]
                                                        atPoint:[[self window] pointToScreenCoords:NSMakePoint(10, -10)]];

}

- (IBAction)moveSessionToTab:(id)sender {
    NSString *sessionID = [NSString castFrom:[[NSMenuItem castFrom:sender] representedObject]];
    PTYSession *session = [[iTermController sharedInstance] sessionWithGUID:sessionID] ?: self.currentSession;
    [[MovePaneController sharedInstance] moveSession:session
                                       toTabInWindow:self.window];

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
        // Note that this typically gets deferred. See the comment in sessionInitiatedResize:width:height:.
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
        const int safeIndex = MAX(0, MIN(_contentView.tabView.tabViewItems.count, anIndex));
        [_contentView.tabView insertTabViewItem:aTabViewItem atIndex:safeIndex];
        [aTabViewItem release];
        [_contentView.tabView selectTabViewItemAtIndex:safeIndex];
        if (self.windowInitialized && !_restoringWindow) {
            if (self.tabs.count == 1) {
                // It's important to do this before makeKeyAndOrderFront because API clients need
                // to know the window exists before learning that it has focus.
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermDidCreateTerminalWindowNotification object:self];
            }
        }
        if (self.windowInitialized && !_fullScreen && !_restoringWindow) {
            DLog(@"insertTab: window is initialized, not full screen, and we are not restoring windows.");
            if (self.isHotKeyWindow && self.window.alphaValue == 0) {
                DLog(@"This appears to be an invisible hotkey window %@", self);
                iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self];
                if (!profileHotkey.rollingIn && profileHotkey.windowController.weaklyReferencedObject == self) {
                    DLog(@"not already rolling in. show it");
                    [profileHotkey showHotKeyWindow];
                } else {
                    DLog(@"already rolling in or still being created - no need to do anything");
                }
            } else {
                DLog(@"not a hidden hotkey window. Just order front.");
                [[self window] makeKeyAndOrderFront:self];
            }
        } else {
            PtyLog(@"window not initialized, is fullscreen, or is being restored. Stack:\n%@", [NSThread callStackSymbols]);
        }
        if (_suppressMakeCurrentTerminal == iTermSuppressMakeCurrentTerminalNone) {
            [[iTermController sharedInstance] setCurrentTerminal:self];
        }
    }
}

- (void)setRestoringWindow:(BOOL)restoringWindow {
    DLog(@"%@ -> %@\n%@", @(_restoringWindow), @(restoringWindow), [NSThread callStackSymbols]);
    if (_restoringWindow != restoringWindow) {
        _restoringWindow = restoringWindow;
        if (restoringWindow) {
            self.restorableStateDecodePending = YES;
        }
    }
}
// Add a session to the tab view.
- (PTYTab *)insertSession:(PTYSession *)aSession atIndex:(int)anIndex {
    PtyLog(@"-[PseudoTerminal insertSession: %p atIndex: %d]", aSession, anIndex);

    if (aSession == nil) {
        return nil;
    }

    if ([[self allSessions] indexOfObject:aSession] != NSNotFound) {
        return [self tabForSession:aSession];
    }
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
    return aTab;
}

- (NSString *)undecoratedWindowTitle {
    if ([self.scope valueForVariableName:iTermVariableKeyWindowTitleOverrideFormat] &&
        self.scope.windowTitleOverrideFormat.length > 0) {
        return self.scope.windowTitleOverride;
    }
    if (![self tabBarShouldBeVisible] && ![iTermAdvancedSettingsModel showWindowTitleWhenTabBarInvisible]) {
        return self.currentSession.nameController.presentationSessionTitle ?: @"Untitled";
    }
    return self.currentSession.nameController.presentationWindowTitle ?: @"Untitled";
}

- (void)setName:(NSString *)theSessionName forSession:(PTYSession *)aSession {
    [aSession didInitializeSessionWithName:theSessionName];
    [aSession setSessionSpecificProfileValues:@{ KEY_NAME: theSessionName }];
}

// Assign a value to the 'uniqueNumber_' member variable which is used for storing
// window frame positions between invocations of iTerm.
- (void)assignUniqueNumberToWindow {
    uniqueNumber_ = [[TemporaryNumberAllocator sharedInstance] allocateNumber];
}

// Reset all state associated with the terminal.
- (void)reset:(id)sender {
    for (PTYSession *session in [self sessionsToSendCommand:iTermBroadcastCommandReset]) {
        [session userInitiatedReset];
    }
}

- (IBAction)resetCharset:(id)sender {
    [self.currentSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [terminal resetCharset];
    }];
}

typedef NS_ENUM(NSUInteger, iTermBroadcastCommand) {
    iTermBroadcastCommandClear,
    iTermBroadcastCommandReset
};

- (NSArray<PTYSession *> *)sessionsToSendCommand:(iTermBroadcastCommand)command {
    NSArray<PTYSession *> *broadcast = [self broadcastSessions];
    if (broadcast.count < 2) {
        return @[ self.currentSession ];
    }
    NSString *action;
    switch (command) {
    case iTermBroadcastCommandClear:
        action = @"Clear";
        break;
    case iTermBroadcastCommandReset:
            action = @"Reset";
        break;
    }
    NSString *title = [NSString stringWithFormat:@"%@ all sessions to which input is broadcast? This will affect %@ sessions.",
                       action,
                       @(broadcast.count)];
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:title
                               actions:@[ [NSString stringWithFormat:@"%@ All", action],
                                          [NSString stringWithFormat:@"%@ Current Session Only", action],
                                          @"Cancel" ]
                             accessory:nil
                            identifier:[NSString stringWithFormat:@"NoSync%@AllBroadcast", action]
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:[NSString stringWithFormat:@"%@ in All Broadcasted-to Sessions?", action]
                                window:self.window];
    if (selection == kiTermWarningSelection0) {
        return broadcast;
    }
    if (selection == kiTermWarningSelection1) {
        return @[ self.currentSession ];
    }
    return @[];
}

// Clear the buffer of the current session (Edit>Clear Buffer).
- (void)clearBuffer:(id)sender {
    for (PTYSession *session in [self sessionsToSendCommand:iTermBroadcastCommandClear]) {
        [session clearBuffer];
    }
}

// Erase the scrollback buffer of the current session.
- (void)clearScrollbackBuffer:(id)sender {
    [[self currentSession] clearScrollbackBuffer];
}

- (IBAction)clearToStartOfSelection:(id)sender {
    const long long line = self.currentSession.textview.selection.firstAbsRange.coordRange.start.y;
    [self.currentSession resetMode];
    [self.currentSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                                VT100ScreenMutableState *mutableState,
                                                                id<VT100ScreenDelegate> delegate) {
        [mutableState clearFromAbsoluteLineToEnd:line];
    }];
}

- (IBAction)clearInstantReplay:(id)sender {
    [self.currentSession clearInstantReplay];
}

- (IBAction)clearToLastMark:(id)sender {
    [self.currentSession.screen clearToLastMark];
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

    __weak __typeof(self) weakSelf = self;
    [iTermSavePanel asyncShowWithOptions:kSavePanelOptionFileFormatAccessory | kSavePanelOptionIncludeTimestampsAccessory
                              identifier:@"SaveContents"
                        initialDirectory:NSHomeDirectory()
                         defaultFilename:suggestedFilename
                        allowedFileTypes:@[ @"txt", @"rtf" ]
                                  window:self.window completion:^(iTermSavePanel *savePanel) {
        [weakSelf reallySaveContents:savePanel];
    }];
}

- (void)reallySaveContents:(iTermSavePanel *)savePanel {
    if (savePanel.path) {
        NSURL *url = [NSURL fileURLWithPath:savePanel.path];
        if (url) {
            if ([[url pathExtension] isEqualToString:@"rtf"]) {
                NSAttributedString *attributedString = [self.currentSession.textview contentWithAttributes:YES
                                                                                                timestamps:savePanel.timestamps];
                NSData *data = [attributedString dataFromRange:NSMakeRange(0, attributedString.length)
                                            documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType}
                                                         error:NULL];
                [data writeToFile:url.path atomically:YES];
            } else {
                id content = [self.currentSession.textview contentWithAttributes:NO timestamps:savePanel.timestamps];
                [content writeToFile:url.path
                          atomically:NO
                            encoding:NSUTF8StringEncoding
                               error:nil];
            }
        }
    }
}

- (IBAction)exportRecording:(id)sender {
    [iTermRecordingCodec exportRecording:self.currentSession window:self.window];
}

- (IBAction)startStopLogging:(id)sender {
    if (self.currentSession.logging) {
        [[self currentSession] logStop];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[self retain] autorelease];  // Prevent self from getting dealloc'ed during modal panel.
            [[self currentSession] logStart];
        });
    }
}

- (void)addRevivedSession:(PTYSession *)session {
    [self insertSession:session atIndex:[self numberOfTabs]];
    [[self currentTab] numberOfSessionsDidChange];
}


// Returns true if the given menu item is selectable.
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    BOOL result = YES;
    if ([item action] == @selector(detachTmux:) ||
        [item action] == @selector(newTmuxWindow:) ||
        [item action] == @selector(newTmuxTab:) ||
        [item action] == @selector(forceDetachTmux:)) {
        return [[iTermController sharedInstance] haveTmuxConnection];
    } else if (item.action == @selector(closeCurrentTab:)) {
        return YES;
    } else if (item.action == @selector(toggleTmuxPausePane:)) {
        const BOOL ok = (self.currentSession.isTmuxClient &&
                         self.currentSession.tmuxController.gateway.pauseModeEnabled);
        if (ok) {
            item.state = self.currentSession.tmuxPaused ? NSControlStateValueOn : NSControlStateValueOff;
        }
        return ok;
    } else if ([item action] == @selector(setDefaultToolbeltWidth:)) {
        return _contentView.shouldShowToolbelt;
    } else if ([item action] == @selector(toggleToolbeltVisibility:)) {
        [item setState:_contentView.shouldShowToolbelt ? NSControlStateValueOn : NSControlStateValueOff];
        return [[iTermToolbeltView configuredTools] count] > 0;
    } else if ([item action] == @selector(moveSessionToWindow:)) {
        result = ([[self allSessions] count] > 1);
    } else if ([item action] == @selector(moveSessionToTab:)) {
        result = [self tabForSession:self.currentSession].sessions.count > 1;
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
        item.state = (_broadcastInputHelper.broadcastMode == BROADCAST_TO_ALL_TABS) ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (item.action == @selector(enableSendInputToAllPanes:)) {
        item.state = (_broadcastInputHelper.broadcastMode == BROADCAST_TO_ALL_PANES) ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (item.action == @selector(disableBroadcasting:)) {
        item.state = (_broadcastInputHelper.broadcastMode == BROADCAST_OFF) ? NSControlStateValueOn : NSControlStateValueOff;
    } else if ([item action] == @selector(runCoprocess:)) {
        result = ![[self currentSession] hasCoprocess];
    } else if ([item action] == @selector(stopCoprocess:)) {
        result = [[self currentSession] hasCoprocess];
    } else if ([item action] == @selector(startStopLogging:)) {
        PTYSession *session = self.currentSession;
        if (!session || session.exited) {
            item.state = NSControlStateValueOff;
            return NO;
        }
        item.state = session.logging ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if ([item action] == @selector(irPrev:)) {
        result = ![[self currentSession] liveSession] && [[self currentSession] canInstantReplayPrev];
    } else if ([item action] == @selector(irNext:)) {
        result = [[self currentSession] canInstantReplayNext];
    } else if ([item action] == @selector(toggleCursorGuide:)) {
        PTYSession *session = [self currentSession];
        [item setState:session.highlightCursorLine ? NSControlStateValueOn : NSControlStateValueOff];
        result = YES;
    } else if ([item action] == @selector(toggleSelectionRespectsSoftBoundaries:)) {
        [item setState:[[iTermController sharedInstance] selectionRespectsSoftBoundaries] ? NSControlStateValueOn : NSControlStateValueOff];
        result = YES;
    } else if ([item action] == @selector(toggleAutoCommandHistory:)) {
        result = [[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed];
        if (result) {
            if ([item respondsToSelector:@selector(setState:)]) {
                [item setState:[iTermPreferences boolForKey:kPreferenceAutoCommandHistory] ? NSControlStateValueOn : NSControlStateValueOff];
            }
        } else {
            [item setState:NSControlStateValueOff];
        }
    } else if ([item action] == @selector(toggleAutoComposer:)) {
        result = [[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed];
        if (result) {
            if ([item respondsToSelector:@selector(setState:)]) {
                [item setState:[iTermPreferences boolForKey:kPreferenceAutoComposer] ? NSControlStateValueOn : NSControlStateValueOff];
            }
        } else {
            [item setState:NSControlStateValueOff];
        }
    } else if ([item action] == @selector(toggleAlertOnNextMark:)) {
        PTYSession *currentSession = [self currentSession];
        if ([item respondsToSelector:@selector(setState:)]) {
            [item setState:currentSession.alertOnNextMark ? NSControlStateValueOn : NSControlStateValueOff];
        }
        result = (currentSession != nil);
    } else if (item.action == @selector(nextMark:) || item.action == @selector(previousMark:)) {
        NSResponder *firstResponder = self.window.firstResponder;
        const BOOL isTextView = [firstResponder isKindOfClass:[NSTextView class]];
        result = !isTextView;
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
    } else if ([item action] == @selector(duplicateSession:)) {
        return [[self currentSession] tmuxMode] == TMUX_NONE;
    } else if ([item action] == @selector(resetCharset:)) {
        result = ![[[self currentSession] screen] allCharacterSetPropertiesHaveDefaultValues];
    } else if ([item action] == @selector(openCommandHistory:)) {
        if (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
            return YES;
        }
        id<VT100RemoteHostReading> host = [[self currentSession] currentHost] ?: [VT100RemoteHost localhost];
        return [[iTermShellHistoryController sharedInstance] haveCommandsForHost:host];
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
    } else if ([item action] == @selector(findPrevious:) ||
               [item action] == @selector(findNext:) ||
               [item action] == @selector(jumpToSelection:) ||
               [item action] == @selector(findUrls:)) {
        result = ([self currentSession] != nil);
    } else if ([item action] == @selector(openSelection:)) {
        result = [[self currentSession] hasSelection];
    } else if ([item action] == @selector(zoomOut:)) {
        return self.currentSession.textViewIsZoomedIn || self.currentSession.textViewIsFiltered;
    } else if (item.action == @selector(captureNextMetalFrame:)) {
        return self.currentSession.canProduceMetalFramecap;
    } else if (item.action == @selector(exportRecording:)) {
        return !self.currentSession.screen.dvr.empty;
    } else if (item.action == @selector(toggleSizeChangesAffectProfile:)) {
        item.state = [iTermPreferences boolForKey:kPreferenceKeySizeChangesAffectProfile] ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (item.action == @selector(performClose:)) {
        return YES;
    } else if (item.action == @selector(changeTabColorToMenuAction:)) {
        iTermTabColorMenuItem *colorMenuItem = [iTermTabColorMenuItem castFrom:item];
        colorMenuItem.colorsView.currentColor = self.currentSession.tabColor;
        return self.currentSession != nil;
    } else if (item.action == @selector(setWindowStyle:)) {
        item.state = (iTermWindowTypeNormalized(self.windowType) == item.tag) ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    } else if (item.action == @selector(enableAllTriggers:)) {
        return [[self currentSession] anyTriggerCanBeEnabled];
    } else if (item.action == @selector(disableAllTriggers:)) {
        return [[self currentSession] anyTriggerCanBeDisabled];
    } else if (item.action == @selector(toggleTriggerEnabled:)) {
        return YES;
    } else if (item.action == @selector(clearScrollbackBuffer:)) {
        return self.currentSession.screen.numberOfScrollbackLines > 0;
    } else if (item.action == @selector(clearToLastMark:)) {
        return self.currentSession.screen.lastMark != nil;
    } else if (item.action == @selector(clearToStartOfSelection:)) {
        return self.currentSession.hasSelection;
    } else if (item.action == @selector(clearInstantReplay:)) {
        return ![[self currentSession] liveSession] && self.currentSession.screen.dvr.canClear;
    } else if (item.action == @selector(compose:)) {
        return self.currentSession != nil && !self.currentSession.shouldShowAutoComposer;
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

- (IBAction)toggleAutoCommandHistory:(id)sender {
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceAutoCommandHistory]
                       forKey:kPreferenceAutoCommandHistory];
}

- (IBAction)toggleAutoComposer:(id)sender {
    [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceAutoComposer]
                       forKey:kPreferenceAutoComposer];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAutoComposerDidChangeNotification
                                                        object:nil];
}

// Turn on/off sending of input to all sessions. This causes a bunch of UI
// to update in addition to flipping the flag.
- (IBAction)enableSendInputToAllPanes:(id)sender {
    if (_broadcastInputHelper.broadcastMode == BROADCAST_TO_ALL_PANES) {
        [self setBroadcastMode:BROADCAST_OFF];
        return;
    }
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
    if (_broadcastInputHelper.broadcastMode == BROADCAST_TO_ALL_TABS) {
        [self setBroadcastMode:BROADCAST_OFF];
        return;
    }
    [self setBroadcastMode:BROADCAST_TO_ALL_TABS];

    // Post a notification to reload menus
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowBecameKey"
                                                        object:self
                                                      userInfo:nil];
    [self setWindowTitle];
}

// Push size changes to all sessions so they are all as large as possible while
// still fitting in the window.
- (void)fitTabsToWindow {
    PtyLog(@"fitTabsToWindow begins");
    for (int i = 0; i < [_contentView.tabView numberOfTabViewItems]; ++i) {
        [self fitTabToWindow:[[_contentView.tabView tabViewItemAtIndex:i] identifier]];
    }
    PtyLog(@"fitTabsToWindow returns");
}

- (void)fitNonTmuxTabsToWindow {
    DLog(@"fitNonTmuxTabsToWindow starting");
    for (PTYTab *tab in self.tabs) {
        if (tab.tmuxTab) {
            continue;
        }
        [self fitTabToWindow:tab];
    }
    DLog(@"fitNonTmuxTabsToWindow returning");
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

- (IBAction)newTabToTheRight:(id)sender {
    PTYTab *tab = [PTYTab castFrom:[[sender representedObject] identifier]];
    if (!tab) {
        return;
    }
    const NSUInteger index = [self.tabs indexOfObject:tab];
    if (index == NSNotFound) {
        return;
    }
    [[[iTermApplication sharedApplication] delegate] newTabAtIndex:@(index + 1)];
}

- (NSUInteger)indexForNewTab {
    if ([iTermAdvancedSettingsModel addNewTabAtEndOfTabs] || ![self currentTab]) {
        return [_contentView.tabView numberOfTabViewItems];
    }
    return [self indexOfTab:[self currentTab]] + 1;
}

- (IBAction)duplicateTab:(id)sender {
    [self createDuplicateOfTab:(PTYTab *)[[sender representedObject] identifier]];
}

- (IBAction)duplicateWindow:(id)sender {
    const BOOL lionFullScreen = self.lionFullScreen;
    __weak __typeof(self) weakSelf = self;
    [PseudoTerminal performWhenWindowCreationIsSafeForLionFullScreen:lionFullScreen
                                                               block:^{
        [weakSelf reallyDuplicateWindow];
    }];
}

- (void)reallyDuplicateWindow {
    NSDictionary *arrangement = [self arrangementExcludingTmuxTabs:NO includingContents:NO];
    [[iTermController sharedInstance] tryOpenArrangement:arrangement named:nil asTabsInWindow:nil];
}

- (void)createDuplicateOfTab:(PTYTab *)theTab {
    DLog(@"Duplicate tab %@", theTab);
    if (!theTab) {
        theTab = [self currentTab];
    }
    PseudoTerminal *destinationTerminal = 
    [[iTermController sharedInstance] windowControllerForNewTabWithProfile:self.currentSession.profile
                                                                 candidate:self
                                                        respectTabbingMode:NO];
    [self createDuplicateOfTab:theTab inTerminal:destinationTerminal];
}

- (void)createDuplicateOfTab:(PTYTab *)theTab inTerminal:(PseudoTerminal *)destinationTerminal {
    if (destinationTerminal == nil) {
        PTYTab *copyOfTab = [[theTab copy] autorelease];
        [copyOfTab updatePaneTitles];
        [iTermSessionLauncher launchBookmark:self.currentSession.profile
                                  inTerminal:nil
                                     withURL:nil
                            hotkeyWindowType:iTermHotkeyWindowTypeNone
                                     makeKey:YES
                                 canActivate:YES
                          respectTabbingMode:NO
                                       index:nil
                                     command:nil
                                 makeSession:^(Profile *profile, PseudoTerminal *term, void (^makeSessionCompletion)(PTYSession *)) {
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
            makeSessionCompletion(copyOfTab.activeSession);
        }
                              didMakeSession:nil
                                  completion:nil];
    } else {
        [destinationTerminal openTabWithArrangement:theTab.arrangementWithNewGUID
                                              named:nil
                                    hasFlexibleView:theTab.isTmuxTab
                                            viewMap:nil
                                         sessionMap:nil
                                 partialAttachments:nil];
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
    ITAssertWithMessage([self.tabs containsObject:aTab], @"Called on wrong window");
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
- (IBAction)changeTabColorToMenuAction:(id)sender {
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

- (IBAction)compose:(id)sender {
    [self.currentSession compose];
}

// Close this window.
- (IBAction)closeWindow:(id)sender {
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
                [[PreferencePanel sessionsInstance] underlyingProfileDidChange];
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
    [[_contentView.toolbelt snippetsView] currentSessionDidChange];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSnippetsTagsDidChange object:nil];
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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}
#pragma clang diagnostic pop

- (BOOL)incrementBadge {
    DLog(@"incrementBadge");
    if (![iTermAdvancedSettingsModel indicateBellsInDockBadgeLabel]) {
        DLog(@"Disabled by advanced pref");
        return NO;
    }

    NSDockTile *dockTile;
    if (self.window.isMiniaturized) {
        DLog(@"Use miniaturized window tile");
        dockTile = self.window.dockTile;
    } else {
        if ([[NSApplication sharedApplication] isActive]) {
            DLog(@"App is active so don't increment it");
            return NO;
        }
        DLog(@"Use main app dock tile");
        dockTile = [[NSApplication sharedApplication] dockTile];
    }
    int count = [[dockTile badgeLabel] intValue];
    DLog(@"Old count was %d", count);
    if (count == 999) {
        DLog(@"Won't go over 999, so stop early");
        return NO;
    }
    ++count;
    DLog(@"Set badge label to %@", @(count));
    [dockTile setBadgeLabel:[NSString stringWithFormat:@"%d", count]];
    [self.window.dockTile setShowsApplicationBadge:YES];
    return YES;
}

- (void)sessionHostDidChange:(PTYSession *)session to:(id<VT100RemoteHostReading>)host {
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
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle != TAB_STYLE_MINIMAL) {
        return YES;
    }
    if ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_TopTab &&
        self.anyFullScreen &&
        ![self tabBarShouldBeVisible] &&
        !_contentView.tabBarControlOnLoan) {
        // Code path taken big Big Sur workaround for issue #9199
        return YES;
    }
    return NO;
}

- (PTYSession *)sessionForDirectoryRecycling {
    // Get active session's directory
    PTYSession* currentSession = [[[iTermController sharedInstance] currentTerminal] currentSession];
    if (currentSession.isTmuxClient) {
        return currentSession.tmuxGatewaySession;
    }
    return currentSession;
}

- (void)asyncCreateTabWithProfile:(Profile *)profile
                      withCommand:(NSString *)command
                      environment:(NSDictionary *)environment
                         tabIndex:(NSNumber *)tabIndex
                   didMakeSession:(void (^)(PTYSession *session))didMakeSession
                       completion:(void (^)(PTYSession *, BOOL ok))completion {
    PTYSession *currentSession = [self sessionForDirectoryRecycling];
    if (!currentSession) {
        PTYSession *newSession = [self createTabWithProfile:profile
                                                withCommand:command
                                                environment:environment
                                                   tabIndex:tabIndex
                                          previousDirectory:nil
                                                     parent:nil
                                                 completion:completion];
        if (didMakeSession) {
            didMakeSession(newSession);
        }
        return;
    }

    __weak __typeof(self) weakSelf = self;
    [currentSession asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory:^(NSString *pwd) {
        DLog(@"Got local pwd so I can create a tab: %@", pwd);
        PseudoTerminal *strongSelf = [[weakSelf retain] autorelease];
        if (!strongSelf) {
            return;
        }
        if (profile.sshIdentity != nil && ![currentSession.sshIdentity isEqual:profile.sshIdentity]) {
            pwd = nil;
        }
        PTYSession *newSession = [strongSelf createTabWithProfile:profile
                                                      withCommand:command
                                                      environment:environment
                                                         tabIndex:tabIndex
                                                previousDirectory:pwd
                                                           parent:currentSession
                                                       completion:completion];
        if (didMakeSession) {
            didMakeSession(newSession);
        }
    }];
}

- (PTYSession *)createTabWithProfile:(Profile *)profile
                         withCommand:(NSString *)command
                         environment:(NSDictionary *)environment
                            tabIndex:(NSNumber *)tabIndex
                   previousDirectory:(NSString *)previousDirectory
                              parent:(PTYSession *)parent
                          completion:(void (^)(PTYSession *, BOOL ok))completion {
    iTermObjectType objectType;
    if ([_contentView.tabView numberOfTabViewItems] == 0) {
        objectType = iTermWindowObject;
    } else {
        objectType = iTermTabObject;
    }
    if (command) {
        profile = [[profile
                    dictionaryBySettingObject:kProfilePreferenceCommandTypeCustomValue forKey:KEY_CUSTOM_COMMAND]
                   dictionaryBySettingObject:command forKey:KEY_COMMAND_LINE];

    }

    // Initialize a new session
    PTYSession *aSession = [[self.sessionFactory newSessionWithProfile:profile
                                                                parent:parent] autorelease];

    // Add this session to our term and make it current
    [self addSession:aSession inTabAtIndex:tabIndex];

    iTermSessionAttachOrLaunchRequest *launchRequest =
    [iTermSessionAttachOrLaunchRequest launchRequestWithSession:aSession
                                                      canPrompt:YES
                                                     objectType:objectType
                                               hasServerConnection:NO
                                                  serverConnection:(iTermGeneralServerConnection){}
                                                      urlString:nil
                                                   allowURLSubs:NO
                                                    environment:environment
                                                    customShell:[ITAddressBookMgr customShellForProfile:profile]
                                                         oldCWD:previousDirectory
                                                 forceUseOldCWD:NO
                                                        command:nil
                                                         isUTF8:nil
                                                  substitutions:nil
                                               windowController:self
                                                          ready:nil
                                                     completion:^(PTYSession * _Nullable newSession, BOOL ok) {
        if (completion) {
            completion(newSession, ok);
        }
    }];
    [self.sessionFactory attachOrLaunchWithRequest:launchRequest];

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

- (void)restoreState:(PseudoTerminalState *)state {
    [self restoreArrangement:state.arrangement];
}

- (void)asyncRestoreState:(PseudoTerminalState *)state
                  timeout:(void (^)(NSArray *))timeout
               completion:(void (^)(void))completion {
    [self asyncRestoreArrangement:state.arrangement
                          timeout:timeout
                       completion:completion];
}

- (void)restoreArrangement:(NSDictionary *)arrangement {
    [self loadArrangement:arrangement
                    named:nil
                 sessions:nil
       partialAttachments:nil];
    self.restorableStateDecodePending = NO;
}

- (void)asyncRestoreArrangement:(NSDictionary *)arrangement
                        timeout:(void (^)(NSArray *))timeout
                     completion:(void (^)(void))completion {
    DLog(@"asyncRestoreArrangement: begin");
    [self openPartialAttachmentsForArrangement:arrangement
                                       timeout:timeout
                                    completion:^(NSDictionary *partialAttachments) {
        DLog(@"asyncRestoreArrangement: ready:\n%@", partialAttachments);
        [self loadArrangement:arrangement named:nil sessions:nil partialAttachments:partialAttachments];
        self.restorableStateDecodePending = NO;
        // No more tabs will be restored, and in doing so deminiaturize the window.
        _suppressMakeCurrentTerminal &= ~iTermSuppressMakeCurrentTerminalMiniaturized;
        completion();
    }];
}

// The timeout block is called when we get a response after having timed out and called completion.
// It can be called more than once: for each child we discover after the deadline.
- (void)openPartialAttachmentsForArrangement:(NSDictionary *)arrangement
                                     timeout:(void (^)(NSArray *))timeout
                                  completion:(void (^)(NSDictionary *))completion {
    DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement: begin");
    __block BOOL haveNotified = NO;
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    dispatch_group_t group = dispatch_group_create();
    for (NSDictionary *tabArrangement in arrangement[TERMINAL_ARRANGEMENT_TABS]) {
        dispatch_group_enter(group);
        DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement: request for tab");
        [PTYTab openPartialAttachmentsForArrangement:tabArrangement
                                          completion:^(NSDictionary *tabResult) {
            DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement: got result for tab");
            if (haveNotified) {
                // Timed out.
                timeout([tabResult allValues]);
            } else {
                [result it_mergeFrom:tabResult];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([iTermAdvancedSettingsModel timeoutForDaemonAttachment] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (haveNotified) {
            DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement: no timeout, already notified.");
            return;
        }
        haveNotified = YES;
        DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement: timeout");
        completion([result autorelease]);
    });
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement: got results for all tabs");
        if (haveNotified) {
            DLog(@"PseudoTerminal.openPartialAttachmentsForArrangement:timeout");
            // result gets freed by the timeout handler.
            return;
        }
        haveNotified = YES;
        completion([result autorelease]);
        dispatch_release(group);
    });
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state {
    NSDictionary *arrangement = [state decodeObjectForKey:kTerminalWindowStateRestorationWindowArrangementKey];
    if ([iTermAdvancedSettingsModel logRestorableStateSize]) {
        NSString *log = [arrangement sizeInfo];
        [log writeToFile:[NSString stringWithFormat:@"/tmp/statesize.window-%p.txt", self] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    }
    [self restoreArrangement:arrangement];
}

- (void)setRestorableStateDecodePending:(BOOL)restorableStateDecodePending {
    DLog(@"%@ -> %@\n%@", @(restorableStateDecodePending), @(restorableStateDecodePending), [NSThread callStackSymbols]);
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

- (BOOL)windowRestorationEnabled {
    if (self.isHotKeyWindow) {
        // Hotkey windows are restored unconditionally. See -application:didDecodeRestorableState:.
        // That's not necessarily a good idea, but I don't want to half-break it.
        return YES;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyOpenArrangementAtStartup] ||
        [iTermPreferences boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
        return NO;
    }
    return YES;
}

- (BOOL)shouldSaveRestorableStateLegacy:(BOOL)legacy {
    if (doNotSetRestorableState_) {
        // The window has been destroyed beyond recognition at this point and
        // there is nothing to save.
        return NO;
    }
    if (![self windowRestorationEnabled]) {
        [[self ptyWindow] setRestoreState:nil];
        return NO;
    }
    // Don't save and restore the hotkey window. The OS only restores windows that are in the window
    // order, and hotkey windows may be ordered in or out, depending on whether they were in use. So
    // they get a special path for restoration where the arrangement is saved in user defaults.
    if (legacy && [self isHotKeyWindow]) {
        return NO;
    }

    // Don't restore tmux windows since their canonical state is on the server.
    if ([self allTabsAreTmuxTabs]) {
        [[self ptyWindow] setRestoreState:nil];
        return NO;
    }

    return YES;
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state {
    if ([iTermAdvancedSettingsModel storeStateInSqlite]) {
        [state encodeObject:self.terminalGuid forKey:iTermWindowStateKeyGUID];
        return;
    }
    if (![self shouldSaveRestorableStateLegacy:YES]) {
        [[self ptyWindow] setRestoreState:nil];
        if ([self isHotKeyWindow]) {
            [[[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:self] saveHotKeyWindowState];
        }
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
    return proposedOptions;
}

- (void)addSessionInNewTab:(PTYSession *)session {
    [self addSession:session inTabAtIndex:nil];
}

- (void)addSession:(PTYSession *)session inTabAtIndex:(NSNumber *)tabIndex {
    if (![iTermSessionLauncher profileIsWellFormed:session.profile]) {
        return;
    }
    PtyLog(@"PseudoTerminal: -addSessionInNewTab: %p", session);
    // Increment tabViewItemsBeingAdded so that the maximum content size will
    // be calculated with the tab bar if it's about to open.
    ++tabViewItemsBeingAdded;
    [self setupSession:session withSize:nil];
    tabViewItemsBeingAdded--;
    if ([session screen]) {  // screen initialized ok
        PTYTab *tab = nil;
        tab = [self insertSession:session atIndex:tabIndex ? tabIndex.unsignedIntegerValue : [self indexForNewTab]];
        if (!tab.tmuxTab &&
            [iTermProfilePreferences boolForKey:KEY_USE_CUSTOM_TAB_TITLE inProfile:session.profile]) {
            [tab setTitleOverride:[iTermProfilePreferences stringForKey:KEY_CUSTOM_TAB_TITLE
                                                               inProfile:session.profile]];
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

- (IBAction)toggleTmuxPausePane:(id)sender {
    [self.currentSession toggleTmuxPausePane];
}

#pragma mark - Find

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
        DLog(@"Beep: no text view to jump in");
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

- (void)iTermPasswordManagerWillClose {
    [self.currentSession incrementDisableFocusReporting:1];
}

- (void)iTermPasswordManagerDidClose {
    [self.currentSession incrementDisableFocusReporting:-1];
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

- (BOOL)iTermPasswordManagerCanEnterUserName {
    return YES;
}

- (void)iTermPasswordManagerEnterUserName:(NSString *)username broadcast:(BOOL)broadcast {
    [[self currentSession] performBlockWithoutFocusReporting:^{
        [[self currentSession] writeTask:[username stringByAppendingString:@"\n"]];
    }];
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

- (void)tabInvalidateProxyIcon:(PTYTab *)tab {
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
    [self invalidateRestorableState];
}

- (void)tabSessionDidChangeBackgroundColor:(PTYTab *)tab {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle == TAB_STYLE_MINIMAL) {
        [self.contentView setNeedsDisplay:YES];
        [_contentView.tabBarControl backgroundColorWillChange];
    }
    [self updateToolbeltAppearance];
    [self updateForTransparency:self.ptyWindow];
}

- (void)tab:(PTYTab *)tab didChangeToState:(PTYTabState)newState {
    if (self.numberOfTabs == 1) {
        [self setWindowTitle];
    }
}

- (void)tab:(PTYTab *)tab didSetMetalEnabled:(BOOL)useMetal {
    [self updateContentViewExpectsMetal];
}

- (BOOL)tabCanUseMetal:(PTYTab *)tab reason:(out iTermMetalUnavailableReason *)reason {
    if (_contentView.tabBarControl.flashing) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonTabBarTemporarilyVisible;
        }
        return NO;
    }
    return YES;
}

- (void)tabDidChangeMetalViewVisibility:(PTYTab *)tab {
    [self updateContentViewExpectsMetal];
}

- (void)updateContentViewExpectsMetal {
    [_contentView setUseMetal:[self.currentTab.sessions allWithBlock:^BOOL(PTYSession *anObject) {
        MTKView *metalView = anObject.view.metalView;
        return !metalView.isHidden && metalView.alphaValue == 1;
    }]];
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
        _touchBarRateLimitedUpdate = [[iTermRateLimitedIdleUpdate alloc] initWithName:@"Touch bar update word"
                                                                      minimumInterval:0.5];
    }
    [_touchBarRateLimitedUpdate performRateLimitedBlock:^{
        DLog(@"Called");
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

- (void)tabDidSetWindowTitle:(PTYTab *)tab to:(NSString *)title {
    if (![iTermPreferences boolForKey:kPreferenceKeySeparateWindowTitlePerTab]) {
        for (PTYSession *session in self.allSessions) {
            [session setWindowTitle:title];
        }
    }
}

- (void)tabHasNontrivialJobDidChange:(PTYTab *)tab {
    if (tab == self.currentTab) {
        [self updateDocumentEdited];
    }
}

- (void)updateDocumentEdited {
    if ([iTermAdvancedSettingsModel disableDocumentedEditedIndicator]) {
        self.window.documentEdited = NO;
        return;
    }
    self.window.documentEdited = [self.currentTab.sessions anyWithBlock:^BOOL(PTYSession *session) {
        if ([[iTermProfilePreferences stringForKey:KEY_CUSTOM_COMMAND inProfile:session.profile] isEqualToString:kProfilePreferenceCommandTypeCustomValue] ||
            [[iTermProfilePreferences stringForKey:KEY_CUSTOM_COMMAND inProfile:session.profile] isEqualToString:kProfilePreferenceCommandTypeSSHValue]) {
            return NO;
        }
        return session.hasNontrivialJob;
    }];
}

- (NSSize)tabExpectedSize {
    NSSize size = _contentView.tabView.frame.size;
    if (self.shouldCompensateForDisappearingTabBarAccessory) {
        // See the note in windowDecorationSize about this hack.
        size.height += _contentView.tabBarControl.frame.size.height;
    }
    return size;
}

#pragma mark - Toolbelt

- (void)updateToolbeltAppearance {
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL: {
            NSAppearance *appearance;
            if (self.minimalTabStyleBackgroundColor.isDark) {
                appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            } else {
                appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            }
            _contentView.toolbelt.appearance = appearance;
            if (!self.useSeparateStatusbarsPerPane) {
                self.contentView.statusBarViewController.view.appearance = appearance;
            }
            break;
        }

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
        case TAB_STYLE_COMPACT:
            _contentView.toolbelt.appearance = nil;
            if (!self.useSeparateStatusbarsPerPane) {
                self.contentView.statusBarViewController.view.appearance = nil;
            }
            break;
    }
}

- (void)toolbeltUpdateMouseCursor {
    [[[self currentSession] textview] updateCursor:[[NSApplication sharedApplication] currentEvent]];
}

- (void)toolbeltInsertText:(NSString *)text {
    [[[self currentSession] textview] insertText:text];
    [[self currentSession] takeFocus];
}

- (id<VT100RemoteHostReading>)toolbeltCurrentHost {
    return [[self currentSession] currentHost];
}

- (NSString *)toolbeltCurrentSessionGUID {
    return self.currentSession.guid;
}

- (pid_t)toolbeltCurrentShellProcessId {
    return self.currentSession.variablesScope.effectiveRootPid.intValue;
}

- (id<ProcessInfoProvider>)toolbeltCurrentShellProcessInfoProvider {
    return self.currentSession.processInfoProvider;
}

- (id<VT100ScreenMarkReading>)toolbeltLastCommandMark {
    return self.currentSession.screen.lastCommandMark;
}

- (void)toolbeltDidSelectMark:(id<iTermMark>)mark {
    [self.currentSession scrollToMark:mark];
    [self.currentSession takeFocus];
}

- (void)toolbeltActivateTriggerForCapturedOutputInCurrentSession:(CapturedOutput *)capturedOutput {
    [self.currentSession performActionForCapturedOutput:capturedOutput];
}

- (BOOL)toolbeltCurrentSessionHasGuid:(NSString *)guid {
    return [self.currentSession.guid isEqualToString:guid];
}

- (void)toolbeltApplyActionToCurrentSession:(iTermAction *)action {
    [self.currentSession applyAction:action];
}

- (void)toolbeltOpenAdvancedPasteWithString:(NSString *)text escaping:(iTermSendTextEscaping)escaping {
    [self.currentSession openAdvancedPasteWithText:text escaping:escaping];
}

- (void)toolbeltOpenComposerWithString:(NSString *)text escaping:(iTermSendTextEscaping)escaping {
    [self.currentSession openComposerWithString:text escaping:escaping];
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)toolbeltCommandUsesForCurrentSession {
    return [self.currentSession commandUses];
}

- (void)toolbeltAddNamedMark {
    [self addNamedMark:nil];
}

- (void)toolbeltRemoveNamedMark:(id<VT100ScreenMarkReading>)mark {
    [self.currentSession.screen removeNamedMark:mark];
}

- (void)toolbeltRenameNamedMark:(id<VT100ScreenMarkReading>)mark to:(NSString *)newName {
    __weak PTYSession *session = self.currentSession;
    if (!newName) {
        [iTermBookmarkDialogViewController showInWindow:self.window
                                        withDefaultName:mark.name ?: @""
                                             completion:^(NSString * _Nonnull name) {
            [session renameMark:mark to:name];
        }];
    } else {
        [session renameMark:mark to:newName];
    }
}

- (NSArray<NSString *> *)toolbeltSnippetTags {
    return [self currentSnippetTags];
}

- (NSArray<NSString *> *)currentSnippetTags {
    return [iTermProfilePreferences objectForKey:KEY_SNIPPETS_FILTER inProfile:self.currentSession.profile];
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
        [coprocessIgnoreErrors_ setState:[Coprocess shouldIgnoreErrorsFromCommand:coprocessCommand_.stringValue] ? NSControlStateValueOn : NSControlStateValueOff];
    }
    if ([[self superclass] instancesRespondToSelector:_cmd]) {
        [super controlTextDidChange:aNotification];
    }
}

- (void)tabEditActions:(PTYTab *)tab {
    [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyActions];
}

- (void)tabEditSnippets:(PTYTab *)tab {
    [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeySnippets];
}

- (void)updateBackgroundImage {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return;
    }
    [self setSharedBackgroundImage:self.currentSession.backgroundImage
                              mode:self.currentSession.backgroundImageMode
                   backgroundColor:self.currentSession.processedBackgroundColor];
}

- (void)tab:(PTYTab *)tab
setBackgroundImage:(iTermImageWrapper *)image
       mode:(iTermBackgroundImageMode)imageMode
backgroundColor:(NSColor *)backgroundColor {
    if (tab != self.currentTab) {
        DLog(@"Inactive tab tried to set the background image. Ignore it.");
        return;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        DLog(@"Using per-pane backbround images. Ignore.");
        return;
    }
    [self setSharedBackgroundImage:image mode:imageMode backgroundColor:backgroundColor];
}

- (void)setSharedBackgroundImage:(iTermImageWrapper *)image
                            mode:(iTermBackgroundImageMode)imageMode
                 backgroundColor:(NSColor *)backgroundColor NS_AVAILABLE_MAC(10_14) {
    DLog(@"setSharedBackgroundImage:%@", image);
    _contentView.backgroundImage.image = image;
    _contentView.backgroundImage.contentMode = imageMode;
    _contentView.backgroundImage.backgroundColor = backgroundColor;
    _contentView.backgroundImage.hidden = !iTermTextIsMonochrome() || (image == nil);
    for (PTYSession *session in self.allSessions) {
        [session.view setNeedsDisplay:YES];
    }
}

- (iTermImageWrapper *)tabBackgroundImage {
    return self.currentSession.backgroundImage;
}

- (iTermBackgroundImageMode)tabBackgroundImageMode {
    return self.currentSession.backgroundImageMode;
}

- (CGFloat)tabBlend {
    return self.currentSession.desiredBlend;
}

- (void)tabActiveSessionDidUpdatePreferencesFromProfile:(PTYTab *)tab {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return;
    }
    if (!tab.activeSession.backgroundImage) {
        return;
    }
    if (tab == self.currentTab) {
        // Update background color views
        for (PTYSession *session in tab.sessions) {
            [session invalidateBlend];
        }
        // Update top-level image view
        [self updateForTransparency:self.ptyWindow];
    }
}

- (BOOL)tabIsSwiping {
    return _swipeContainerView != nil;
}

- (void)tabActiveSessionDidResize:(PTYTab *)tab {
    if (tab == self.currentTab) {
        [_contentView windowDidResize];
    }
}

- (void)tabEndSyntheticSession:(PTYSession *)syntheticSession {
    [self replaceSyntheticSessionWithLiveSessionIfNeeded:syntheticSession];
}

#pragma mark - PSMMinimalTabStyleDelegate

- (NSColor *)minimalTabStyleBackgroundColor {
    DLog(@"Getting bg color for session %@, colormap %@", self.currentSession, self.currentSession.screen.colorMap);
    return [self.currentSession.screen.colorMap colorForKey:kColorMapBackground];
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
    DLog(@"broadcastInputHelperDidUpdate");
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

- (BOOL)broadcastInputHelperAnyTabIsBroadcasting:(iTermBroadcastInputHelper *)helper {
    return [self.tabs anyWithBlock:^BOOL(PTYTab *anObject) {
        return anObject.isBroadcasting;
    }];
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

#pragma mark - iTermPresentationControllerManagedWindowController

- (BOOL)presentationControllerManagedWindowControllerIsFullScreen:(out BOOL *)lionFullScreen {
    if (![self anyFullScreen]) {
        *lionFullScreen = NO;
        return NO;
    }
    *lionFullScreen = [self lionFullScreen];
    return YES;
}

- (NSWindow *)presentationControllerManagedWindowControllerWindow {
    return self.window;
}

#pragma mark - iTermSwipeHandler

- (BOOL)swipeHandlerShouldBeginNewSwipe {
    return self.tabs.count > 1;
}

- (id)swipeHandlerBeginSessionAtOffset:(CGFloat)offset identifier:(nonnull id)identifier {
    assert(!_swipeContainerView);
    self.swipeIdentifier = identifier;

    NSRect frame = NSZeroRect;
    frame.origin.x = offset;
    frame.size.width = self.tabs.firstObject.realRootView.frame.size.width * self.tabs.count;
    frame.size.height = self.tabs.firstObject.realRootView.frame.size.height;
    _swipeContainerView = [[[NSView alloc] initWithFrame:frame] autorelease];
    [self updateUseMetalInAllTabs];
    const CGFloat width = self.swipeHandlerParameters.width;

    [self.tabs enumerateObjectsUsingBlock:^(PTYTab * _Nonnull tab, NSUInteger idx, BOOL * _Nonnull stop) {
        NSView *view = tab.realRootView;
        NSRect frame = view.frame;
        frame.origin.x = idx * width;
        frame.origin.y = 0;
        frame.size.width = width;
        NSView *clipView = [[[NSView alloc] initWithFrame:frame] autorelease];
        [clipView addSubview:view];
        view.frame = clipView.bounds;
        [_swipeContainerView addSubview:clipView];
    }];
    [self.contentView.tabView addSubview:_swipeContainerView];

    return @{};
}

- (iTermSwipeHandlerParameters)swipeHandlerParameters {
    return (iTermSwipeHandlerParameters){
        .count = self.tabs.count,
        .currentIndex = [self.tabs indexOfObject:self.currentTab],
        .width = NSWidth(_contentView.tabView.frame)
    };
}

- (CGFloat)truncatedSwipeOffset:(CGFloat)x {
    const iTermSwipeHandlerParameters params = self.swipeHandlerParameters;
    const CGFloat maxWiggle = params.width * 0.25;
    const CGFloat upperBound = MAX(0, ((NSInteger)params.count) - 1) * params.width;
    return iTermSquash(x, upperBound, maxWiggle);
}

- (void)swipeHandlerSetOffset:(CGFloat)rawOffset forSession:(id)session {
    NSRect frame = _swipeContainerView.frame;
    const CGFloat offset = -[self truncatedSwipeOffset:-rawOffset];
    frame.origin.x = offset;
    _swipeContainerView.frame = frame;
}

- (void)swipeHandlerEndSession:(id)session atIndex:(NSInteger)index {
    self.swipeIdentifier = nil;
    [_contentView.tabView addSubview:self.currentTab.realRootView];
    self.currentTab.realRootView.frame = _contentView.tabView.bounds;
    [_swipeContainerView removeFromSuperview];
    [self updateUseMetalInAllTabs];
    _swipeContainerView = nil;
    if (index == NSNotFound) {
        [self.tabView selectTabViewItem:self.currentTab.tabViewItem];
        return;
    }
    if (index >= 0 && index < self.tabs.count) {
        [self.tabView selectTabViewItemAtIndex:index];
    } else if (self.tabs.count) {
        [self.tabView selectLastTabViewItem:nil];
    }
    [[self window] makeFirstResponder:[[self currentSession] textview]];
    [[self currentTab] recheckBlur];
}

#pragma mark - iTermGraphCodable

- (BOOL)encodeGraphWithEncoder:(iTermGraphEncoder *)encoder {
    // NOTE: The well-formedness check is not in -shouldSaveRestorableState because I'm afraid of
    // breaking something in the legacy code. Once it is gone, it can move in.
    if (![self shouldSaveRestorableStateLegacy:NO] || !_wellFormed) {
        return NO;
    }
    NSArray<PTYTab *> *tabs = [self tabsToEncodeExcludingTmux:YES];
    const BOOL includeContents = [iTermAdvancedSettingsModel restoreWindowContents];
    iTermGraphEncoderAdapter *adapter = [[[iTermGraphEncoderAdapter alloc] initWithGraphEncoder:encoder] autorelease];
    const BOOL commit = [self populateArrangementWithTabs:tabs
                                        includingContents:includeContents
                                                  encoder:adapter];
    [encoder encodeNumber:@(self.window.miniaturized) forKey:TERMINAL_ARRANGEMENT_MINIATURIZED];
    return commit;
}

#pragma mark - iTermUniquelyIdentifiable

- (NSString *)stringUniqueIdentifier {
    return self.terminalGuid;
}

#pragma mark - iTermRestorableWindowController

- (void)didFinishRestoringWindow {
    DLog(@"%@ widthAdjustment=%@", self, @(_widthAdjustment));
    if (_widthAdjustment == 0) {
        return;
    }
    DLog(@"windowType=%@", @(self.windowType));
    NSRect rect = [self rectByAdjustingWidth:self.window.frame];
    if (!NSEqualRects(rect, self.window.frame)) {
        DLog(@"Change window frame for width adjustment");
        [self.window setFrame:rect display:YES];
        [self fitTabsToWindow];
    }

    DLog(@"Set width adjustment to 0 for %@", self);
    _widthAdjustment = 0;
}

- (NSRect)rectByAdjustingWidth:(NSRect)rect {
    DLog(@"%@: Computing width adjustment for window type %@ rect %@ widthAdjustment %@",
          self, @(self.windowType), NSStringFromRect(rect), @(_widthAdjustment));
    switch (self.windowType) {
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_MAXIMIZED:
        case WINDOW_TYPE_COMPACT_MAXIMIZED:
            DLog(@"No width adjustment because of window type");
            return rect;

        case WINDOW_TYPE_NORMAL:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
        case WINDOW_TYPE_NO_TITLE_BAR:
        case WINDOW_TYPE_COMPACT:
        case WINDOW_TYPE_ACCESSORY: {
            DLog(@"Will apply width adjustment of %@", @(_widthAdjustment));
            rect.size.width += _widthAdjustment;
            DLog(@"Return %@", NSStringFromRect(rect));
            return rect;
        }
    }
    assert(NO);
    return rect;
}

@end
