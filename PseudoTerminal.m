#import "PseudoTerminal.h"

#import "ColorsMenuItemView.h"
#import "CommandHistory.h"
#import "CommandHistoryEntry.h"
#import "CommandHistoryPopup.h"
#import "Coprocess.h"
#import "FakeWindow.h"
#import "FindViewController.h"
#import "FutureMethods.h"
#import "FutureMethods.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "MovePaneController.h"
#import "NSStringITerm.h"
#import "PSMTabBarControl.h"
#import "PSMTabStyle.h"
#import "PTToolbarController.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTabView.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "PasteboardHistory.h"
#import "PopupModel.h"
#import "PopupWindow.h"
#import "PreferencePanel.h"
#import "ProcessCache.h"
#import "ProfilesWindow.h"
#import "PseudoTerminal.h"
#import "PseudoTerminalRestorer.h"
#import "SessionView.h"
#import "SplitPanel.h"
#import "TemporaryNumberAllocator.h"
#import "TmuxControllerRegistry.h"
#import "TmuxDashboardController.h"
#import "TmuxLayoutParser.h"
#import "ToolCommandHistoryView.h"
#import "ToolbeltView.h"
#import "VT100Screen.h"
#import "VT100Screen.h"
#import "VT100Terminal.h"
#import "iTerm.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermFontPanel.h"
#import "iTermGrowlDelegate.h"
#import "iTermInstantReplayWindowController.h"
#import "iTermSettingsModel.h"
#include <unistd.h>

static NSString *const kWindowNameFormat = @"iTerm Window %d";
static NSString *const kShowFullscreenTabBarKey = @"ShowFullScreenTabBar";

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
static NSString* TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX = @"Selected Tab Index";
static NSString* TERMINAL_ARRANGEMENT_SCREEN_INDEX = @"Screen";
static NSString* TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING = @"Hide After Opening";
static NSString* TERMINAL_ARRANGEMENT_DESIRED_COLUMNS = @"Desired Columns";
static NSString* TERMINAL_ARRANGEMENT_DESIRED_ROWS = @"Desired Rows";
static NSString* TERMINAL_GUID = @"TerminalGuid";

// In full screen, leave a bit of space at the top of the toolbar for aesthetics.
static const CGFloat kToolbeltMargin = 8;

@interface NSWindow (private)
- (void)setBottomCornerRounded:(BOOL)rounded;
@end

@interface PseudoTerminal ()
@property(nonatomic, retain) PTToolbarController *toolbarController;
@end

// keys for attributes:
NSString *kColumnsKVCKey = @"columns";
NSString *kRowsKVCKey = @"rows";
// keys for to-many relationships:
NSString *kSessionsKVCKey = @"sessions";

@implementation PseudoTerminal {
    NSPoint preferredOrigin_;

    SolidColorView* background_;
    ////////////////////////////////////////////////////////////////////////////
    // Parameter Panel
    // A bookmark may have metasyntactic variables like $$FOO$$ in the command.
    // When opening such a bookmark, pop up a sheet and ask the user to fill in
    // the value. These fields belong to that sheet.
    IBOutlet NSTextField *parameterName;
    IBOutlet NSPanel     *parameterPanel;
    IBOutlet NSTextField *parameterValue;
    IBOutlet NSTextField *parameterPrompt;

    ////////////////////////////////////////////////////////////////////////////
    // Instant Replay
    iTermInstantReplayWindowController *_instantReplayWindowController;

    ////////////////////////////////////////////////////////////////////////////
    // Tab View
    // The tabview occupies almost the entire window. Each tab has an identifier
    // which is a PTYTab.
    PTYTabView *TABVIEW;

    // Gray line dividing tab/title bar from content. Will be nil if a division
    // view isn't needed such as for fullscreen windows or windows without a
    // title bar (e.g., top-of-screen).
    NSView *_divisionView;

    // This is a sometimes-visible control that shows the tabs and lets the user
    // change which is visible.
    PSMTabBarControl *tabBarControl;
    NSView* tabBarBackground;

    // This is either 0 or 1. If 1, then a tab item is in the process of being
    // added and the tabBarControl will be shown if it is added successfully
    // if it's not currently shown.
    int tabViewItemsBeingAdded;

    // A text field into which you may type a command. When you press enter in it
    // then the text is sent to the terminal.
    IBOutlet id commandField;

    ////////////////////////////////////////////////////////////////////////////
    // Miscellaneous

    // Is the transparency setting respected?
    BOOL useTransparency_;

    // Is this a full screenw indow?
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

    // True if an [init...] method was called.
    BOOL windowInited;

    // How input should be broadcast (or not).
    BroadcastMode broadcastMode_;

    // True if the window title is showing transient information (such as the
    // size during resizing).
    BOOL tempTitle;

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
    AutocompleteView* autocompleteView;

    NSTimer* fullScreenTabviewTimer_;

    // This is a hack to support old applescript code that set the window size
    // before adding a session to it, which doesn't really make sense now that
    // textviews and windows are loosely coupled.
    int nextSessionRows_;
    int nextSessionColumns_;

    BOOL tempDisableProgressIndicators_;

    int windowType_;
    // Window type before entering fullscreen. Only relevant if in/entering fullscreen.
    int savedWindowType_;
    BOOL isHotKeyWindow_;
    BOOL haveScreenPreference_;
    int screenNumber_;

    // Window number, used for keyboard shortcut to select a window.
    // This value is 0-based while the UI is 1-based.
    int number_;

    // True if this window was created by dragging a tab from another window.
    // Affects how its size is set when the number of tabview items changes.
    BOOL wasDraggedFromAnotherWindow_;
    BOOL fullscreenTabs_;

    // In the process of zooming in Lion or later.
    BOOL zooming_;

    // Time since 1970 of last window resize
    double lastResizeTime_;

    BOOL temporarilyShowingTabs_;

    NSMutableSet *broadcastViewIds_;
    NSTimeInterval findCursorStartTime_;

    // Accumulated pinch magnification amount.
    double cumulativeMag_;

    // Time of last magnification change.
    NSTimeInterval lastMagChangeTime_;

    // In 10.7 style full screen mode
    BOOL lionFullScreen_;

    // Drawer view, which only exists for window_type normal.
    NSDrawer *drawer_;

    // Toolbelt view which goes in the drawer, or perhaps other places in the future.
    ToolbeltView *toolbelt_;

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

    // A unique string for this window. Used for tmux to remember which window
    // a tmux window should be opened in as a tab. A window restored from a
    // saved arrangement will also restore its guid.
    NSString *terminalGuid_;

    // Recalls if this was a hide-after-opening window.
    BOOL hideAfterOpening_;

    // After dealloc starts, the restorable state should not be updated
    // because the window's state is a shambles.
    BOOL doNotSetRestorableState_;

    // For top/left/bottom of screen windows, this is the size it really wants to be.
    // Initialized to -1 in -init and then set to the size of the first session
    // forever.
    int desiredRows_, desiredColumns_;
    
    // Session ID of session that currently has an auto-command history window open
    int _autoCommandHistorySessionId;
}

- (id)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
    if (self) {
        _autoCommandHistorySessionId = -1;
    }
    return self;
}

- (id)init {
    // This is invoked by Applescript's "make new terminal" and must be followed by a command like
    // launch session "Profile Name"
    // which invokes handleLaunchScriptCommand, which in turn calls initWithSmartLayotu:windowType:screen:isHotkey:
    // Alternatively, a script like this:
    //
    // tell application "iTerm"
    //   activate
    //   set myterm to (make new terminal)
    //   tell myterm
    //     set mysession to (make new session at the end of sessions)
    //
    // Causes insertInSessions:atIndex: to be called.
    // A followup call to finishInitializationWithSmartLayout:windowType:screen:isHotkey:
    // finishes intialization. -windowInited will return NO until that is done.
    return [self initWithWindowNibName:@"PseudoTerminal"];
}


- (id)initWithSmartLayout:(BOOL)smartLayout
               windowType:(int)windowType
                   screen:(int)screenNumber
{
    return [self initWithSmartLayout:smartLayout windowType:windowType screen:screenNumber isHotkey:NO];
}

- (id)initWithSmartLayout:(BOOL)smartLayout
               windowType:(int)windowType
                   screen:(int)screenNumber
                 isHotkey:(BOOL)isHotkey
{
    self = [self initWithWindowNibName:@"PseudoTerminal"];
    NSAssert(self, @"initWithWindowNibName returned nil");
    if (self) {
        [self finishInitializationWithSmartLayout:smartLayout
                                       windowType:windowType
                                           screen:screenNumber
                                         isHotkey:isHotkey];
    }
    return self;
}

- (void)finishInitializationWithSmartLayout:(BOOL)smartLayout
                                 windowType:(int)windowType
                                     screen:(int)screenNumber
                                   isHotkey:(BOOL)isHotkey
{
    DLog(@"-[%p finishInitializationWithSmartLayout:%@ windowType:%d screen:%d isHotkey:%@ ",
         self,
         smartLayout ? @"YES" : @"NO",
         windowType,
         screenNumber,
         isHotkey ? @"YES" : @"NO");

    // Force the nib to load
    [self window];
    [commandField retain];
    [commandField setDelegate:self];
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
    [commandField retain];
    [commandField setDelegate:self];
    windowType_ = windowType;
    broadcastViewIds_ = [[NSMutableSet alloc] init];
    pbHistoryView = [[PasteboardHistoryWindowController alloc] init];
    autocompleteView = [[AutocompleteView alloc] init];
    commandHistoryPopup = [[CommandHistoryPopupWindowController alloc] init];

    NSScreen* screen;
    if (screenNumber < 0 || screenNumber >= [[NSScreen screens] count])  {
        screen = [[self window] screen];
        DLog(@"Screen number %d is out of range [0,%d] so using 0",
             screenNumber, (int)[[NSScreen screens] count]);
        screenNumber_ = 0;
        haveScreenPreference_ = NO;
    } else {
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
            initialFrame = [screen visibleFrame];
            break;

        default:
            PtyLog(@"Unknown window type: %d", (int)windowType);
            NSLog(@"Unknown window type: %d", (int)windowType);
            // fall through
        case WINDOW_TYPE_NORMAL:
            haveScreenPreference_ = NO;
            // fall through
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
                oldFrame_ = [[self window] frame];
                // The size is just whatever was in the .xib file's window, which is silly.
                // By setting this flag, we'll use the window size necessary to hold the current
                // session's rows/columns setting when exiting fullscreen.
                oldFrameSizeIsBogus_ = YES;
                initialFrame = [self traditionalFullScreenFrameForScreen:screen];
            } else {
                // Use the system-supplied frame which has a reasonable origin. It may
                // be overridden by smart window placement or a saved window location.
                initialFrame = [[self window] frame];
            }
            if (screenNumber_ != 0) {
                DLog(@"Moving fullscreen window to screen %d", screenNumber_);
                // Move the frame to the desired screen
                NSScreen* baseScreen = [[self window] deepestScreen];
                NSPoint basePoint = [baseScreen visibleFrame].origin;
                double xoffset = initialFrame.origin.x - basePoint.x;
                double yoffset = initialFrame.origin.y - basePoint.y;
                NSPoint destPoint = [screen visibleFrame].origin;
                destPoint.x += xoffset;
                destPoint.y += yoffset;
                initialFrame.origin = destPoint;

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
                [[self window] setFrameOrigin:destPoint];
            }
            break;
    }
    preferredOrigin_ = initialFrame.origin;

    PtyLog(@"finishInitializationWithSmartLayout - initWithContentRect");
    // create the window programmatically with appropriate style mask
    NSUInteger styleMask = NSTitledWindowMask |
                           NSClosableWindowMask |
                           NSMiniaturizableWindowMask |
                           NSResizableWindowMask |
                           NSTexturedBackgroundWindowMask;
    switch (windowType) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            styleMask = NSBorderlessWindowMask | NSResizableWindowMask;
            break;
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            styleMask = NSBorderlessWindowMask;
            break;

        default:
            break;
    }

    DLog(@"initWithContentRect:%@ styleMask:%d", [NSValue valueWithRect:initialFrame], (int)styleMask);
    PTYWindow *myWindow;
    myWindow = [[PTYWindow alloc] initWithContentRect:initialFrame
                                            styleMask:styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    if (windowType == WINDOW_TYPE_TOP ||
        windowType == WINDOW_TYPE_BOTTOM ||
        windowType == WINDOW_TYPE_LEFT ||
        windowType == WINDOW_TYPE_RIGHT ||
        windowType == WINDOW_TYPE_TOP_PARTIAL ||
        windowType == WINDOW_TYPE_BOTTOM_PARTIAL ||
        windowType == WINDOW_TYPE_LEFT_PARTIAL ||
        windowType == WINDOW_TYPE_RIGHT_PARTIAL) {
        [myWindow setHasShadow:YES];
    }
    [self updateContentShadow];

    PtyLog(@"finishInitializationWithSmartLayout - new window is at %p", myWindow);
    [self setWindow:myWindow];
    [myWindow release];

    _fullScreen = (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN);
    background_ = [[SolidColorView alloc] initWithFrame:[[[self window] contentView] frame] color:[NSColor windowBackgroundColor]];
    [[self window] setAlphaValue:1];
    [[self window] setOpaque:NO];

    normalBackgroundColor = [background_ color];

    _resizeInProgressFlag = NO;

    if (!smartLayout || windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        PtyLog(@"no smart layout or is full screen, so set layout done");
        [(PTYWindow*)[self window] setLayoutDone];
    }

    if (styleMask & NSTitledWindowMask) {
        _toolbarController = [[PTToolbarController alloc] initWithPseudoTerminal:self];
        if ([[self window] respondsToSelector:@selector(setBottomCornerRounded:)])
            // TODO: Why is this here?
            [[self window] setBottomCornerRounded:NO];
    }

    // create the tab bar control
    [[self window] setContentView:background_];
    [background_ release];

    NSRect aRect = [[[self window] contentView] bounds];
    aRect.size.height = 22;
    tabBarControl = [[PSMTabBarControl alloc] initWithFrame:aRect];

    [tabBarControl retain];
    PreferencePanel* pp = [PreferencePanel sharedInstance];
    [tabBarControl setModifier:[pp modifierTagToMask:[pp switchTabModifier]]];
    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
        [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    } else {
        [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    }
    [[[self window] contentView] addSubview:tabBarControl];
    [tabBarControl release];

    // create the tabview
    aRect = [[[self window] contentView] bounds];

    TABVIEW = [[PTYTabView alloc] initWithFrame:aRect];
    [TABVIEW setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [TABVIEW setAutoresizesSubviews:YES];
    [TABVIEW setAllowsTruncatedLabels:NO];
    [TABVIEW setControlSize:NSSmallControlSize];
    [TABVIEW setTabViewType:NSNoTabsNoBorder];
    // Add to the window
    [[[self window] contentView] addSubview:TABVIEW];
    [TABVIEW release];

    // assign tabview and delegates
    [tabBarControl setTabView:TABVIEW];
    [TABVIEW setDelegate:tabBarControl];
    [tabBarControl setDelegate:self];
    [tabBarControl setHideForSingleTab:NO];

    // set the style of tabs to match window style
    [self setTabBarStyle];

    [[[self window] contentView] setAutoresizesSubviews: YES];
    [[self window] setDelegate: self];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTitle:)
                                                 name: @"iTermUpdateLabels"
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(_refreshTerminal:)
                                                 name: @"iTermRefreshTerminal"
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_scrollerStyleChanged:)
                                                 name:@"NSPreferredScrollerStyleDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_updateDrawerVisibility:)
                                                 name:@"iTermToolbeltVisibilityChanged"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tmuxFontDidChange:)
                                                 name:@"kPTYSessionTmuxFontDidChange"
                                               object:nil];
    PtyLog(@"set window inited");
    [self setWindowInited: YES];
    useTransparency_ = YES;
    fullscreenTabs_ = [[NSUserDefaults standardUserDefaults] boolForKey:kShowFullscreenTabBarKey];
    number_ = [[iTermController sharedInstance] allocateWindowNumber];
    if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        [self hideMenuBar];
    }

    [self updateDivisionView];

    if (isHotkey) {
        // This allows the hotkey window to be in the same space as a Lion fullscreen iTerm2 window.
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorFullScreenAuxiliary];
    } else {
        // This allows the window to enter Lion fullscreen.
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];
    }
    if (isHotkey) {
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorIgnoresCycle];
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] & ~NSWindowCollectionBehaviorParticipatesInCycle];
    }

    toolbelt_ = [[[ToolbeltView alloc] initWithFrame:NSMakeRect(0, 0, 200, self.window.frame.size.height - kToolbeltMargin)
                                                term:self] autorelease];
    [toolbelt_ setUseDarkDividers:windowType_ == WINDOW_TYPE_LION_FULL_SCREEN];
    [self _updateToolbeltParentage];

    wellFormed_ = YES;
    [[self window] setRestorable:YES];
    [[self window] setRestorationClass:[PseudoTerminalRestorer class]];
    terminalGuid_ = [[NSString stringWithFormat:@"pty-%@", [ProfileModel freshGuid]] retain];
}

- (void)dealloc
{
    [self closeInstantReplayWindow];
    doNotSetRestorableState_ = YES;
    wellFormed_ = NO;
    [toolbelt_ shutdown];
    [drawer_ release];
    
    // Do not assume that [self window] is valid here. It may have been freed.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Cancel any SessionView timers.
    for (PTYSession* aSession in [self sessions]) {
        [[aSession view] cancelTimers];
    }
    
    // Release all our sessions
    NSTabViewItem *aTabViewItem;
    for (; [TABVIEW numberOfTabViewItems]; )  {
        aTabViewItem = [TABVIEW tabViewItemAtIndex:0];
        [[aTabViewItem identifier] terminateAllSessions];
        PTYTab* theTab = [aTabViewItem identifier];
        [theTab setParentWindow:nil];
        [TABVIEW removeTabViewItem:aTabViewItem];
    }
    
    if ([[iTermController sharedInstance] currentTerminal] == self) {
        NSLog(@"Red alert! Current terminal is being freed!");
        [[iTermController sharedInstance] setCurrentTerminal:nil];
    }
    [broadcastViewIds_ release];
    [commandField release];
    [_toolbarController release];
    [autocompleteView shutdown];
    [commandHistoryPopup shutdown];
    [pbHistoryView shutdown];
    [pbHistoryView release];
    [commandHistoryPopup release];
    [autocompleteView release];
    [tabBarControl release];
    [terminalGuid_ release];
    if (fullScreenTabviewTimer_) {
        [fullScreenTabviewTimer_ invalidate];
    }
    [lastArrangement_ release];
    [_divisionView release];
    [super dealloc];
}

- (void)updateDivisionView {
    // The division is only shown if there is a title bar and no tab bar. There
    // are cases in fullscreen (e.g., when entering Lion fullscreen) when the
    // window doesn't have a title bar but also isn't borderless we also check
    // if we're in fullscreen.
    if (self.window.styleMask != NSBorderlessWindowMask &&
        ![self anyFullScreen] &&
        ![self tabBarShouldBeVisible]) {
        // A division is needed, but there might already be one.
        NSRect reducedTabviewFrame = TABVIEW.frame;
        if (!_divisionView) {
          reducedTabviewFrame.size.height -= 1;
        }
        NSRect divisionViewFrame = NSMakeRect(reducedTabviewFrame.origin.x,
                                              reducedTabviewFrame.size.height + reducedTabviewFrame.origin.y,
                                              reducedTabviewFrame.size.width,
                                              1);
        if (_divisionView) {
            // Simply update divisionView's frame.
            _divisionView.frame = divisionViewFrame;
        } else {
            // Shrink the tabview and add a division view.
            TABVIEW.frame = reducedTabviewFrame;
            _divisionView = [[SolidColorView alloc] initWithFrame:divisionViewFrame
                                                            color:[NSColor darkGrayColor]];
            _divisionView.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
            [self.window.contentView addSubview:_divisionView];
        }
    } else if (_divisionView) {
        // Remove existing division
        NSRect augmentedTabviewFrame = TABVIEW.frame;
        augmentedTabviewFrame.size.height += 1;
        [_divisionView removeFromSuperview];
        [_divisionView release];
        _divisionView = nil;
        TABVIEW.frame = augmentedTabviewFrame;
    }
}

- (CGFloat)tabviewWidth
{
    if ([self anyFullScreen] || [self isEdgeWindow]) {
        iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
        if ([itad showToolbelt] && !exitingLionFullscreen_) {
            const CGFloat width = [self fullscreenToolbeltWidth];
            return self.window.frame.size.width - width;
        } else {
            return self.window.frame.size.width;
        }
    } else {
        CGFloat width = self.window.frame.size.width;
        if ([self _haveLeftBorder]) {
            --width;
        }
        if ([self _haveRightBorder]) {
            --width;
        }
        return width;
    }
}

- (void)toggleBroadcastingToCurrentSession:(id)sender
{
    [self toggleBroadcastingInputToSession:[self currentSession]];
}

- (void)notifyTmuxOfWindowResize
{
    NSArray *tmuxControllers = [self uniqueTmuxControllers];
    if (tmuxControllers.count && !tmuxOriginatedResizeInProgress_) {
        for (TmuxController *controller in tmuxControllers) {
            [controller windowDidResize:self];
        }
    }
}

- (void)_updateDrawerVisibility:(id)sender
{
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    if (windowType_ != WINDOW_TYPE_NORMAL || [self anyFullScreen]) {
        if ([itad showToolbelt]) {
            [toolbelt_ setHidden:NO];
        } else {
            [toolbelt_ setHidden:YES];
        }
        [self repositionWidgets];
        [self notifyTmuxOfWindowResize];
    } else {
        if ([itad showToolbelt]) {
            [drawer_ open];
        } else {
            [drawer_ close];
        }
    }
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
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
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
        case WINDOW_TYPE_LION_FULL_SCREEN:
            newWindowType = WINDOW_TYPE_NORMAL;
            break;

        default:
            newWindowType = windowType_;
    }
    term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                             windowType:newWindowType
                                                 screen:screen] autorelease];
    if (term == nil) {
        return nil;
    }
    term->wasDraggedFromAnotherWindow_ = YES;
    [term copySettingsFrom:self];

    [[iTermController sharedInstance] addInTerminals:term];

    if (newWindowType == WINDOW_TYPE_NORMAL) {
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

- (PTYWindow*)ptyWindow
{
    return (PTYWindow*) [self window];
}

- (NSScreen*)screen
{
    NSArray* screens = [NSScreen screens];
    if ([screens count] > screenNumber_) {
        return [screens objectAtIndex:screenNumber_];
    } else {
        return [NSScreen mainScreen];
    }
}

- (void)magnifyWithEvent:(NSEvent *)event
{
    if ([iTermSettingsModel pinchToChangeFontSizeDisabled]) {
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

- (void)setTabBarStyle
{
    switch ([[PreferencePanel sharedInstance] windowStyle]) {
        case 0:
            [tabBarControl setStyleNamed:@"Metal"];
            break;
        case 1:
            [tabBarControl setStyleNamed:@"Aqua"];
            break;
        case 2:
            [tabBarControl setStyleNamed:@"Unified"];
            break;
        default:
            [tabBarControl setStyleNamed:@"Adium"];
            break;
    }
}

- (id)commandField
{
    return commandField;
}

- (void)selectSessionAtIndexAction:(id)sender
{
    [TABVIEW selectTabViewItemAtIndex:[sender tag]];
}

- (NSInteger)indexOfTab:(PTYTab*)aTab
{
    NSArray* items = [TABVIEW tabViewItems];
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
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:[sender representedObject]];
    if (bookmark) {
        [self addNewSession:bookmark];
    }
}

- (void)newSessionsInManyTabsAtIndex:(id)sender
{
    NSMenu* parent = [sender representedObject];
    for (NSMenuItem* item in [parent itemArray]) {
        if (![item isSeparatorItem] && ![item submenu]) {
            NSString* guid = [item representedObject];
            Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
            if (bookmark) {
                [self addNewSession:bookmark];
            }
        }
    }
}

- (void)closeSession:(PTYSession *)aSession soft:(BOOL)soft
{
    if (!soft &&
        [aSession isTmuxClient] &&
        [[aSession tmuxController] isAttached]) {
        [[aSession tmuxController] killWindowPane:[aSession tmuxPane]];
    } else if ([[[aSession tab] sessions] count] == 1) {
        [self closeTab:[aSession tab] soft:soft];
    } else {
        [aSession terminate];
    }
}

- (void)closeSession:(PTYSession *)aSession
{
    [self closeSession:aSession soft:NO];
}

- (void)softCloseSession:(PTYSession *)aSession
{
    [self closeSession:aSession soft:YES];
}

- (int)windowType
{
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
    if ([TABVIEW indexOfTabViewItemWithIdentifier:aTab] == NSNotFound) {
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
        [[PreferencePanel sharedInstance] onlyWhenMoreTabs]) {
        mustAsk = YES;
    }

    if (mustAsk) {
        BOOL okToClose;
        if (numClosing == 1) {
            okToClose = [self confirmCloseForSessions:[aTab sessions]
                                           identifier:@"This tab"
                                          genericName:[NSString stringWithFormat:@"tab #%d",
                                                       [aTab realObjectCount]]];
        } else {
            okToClose = [self confirmCloseForSessions:[aTab sessions]
                                           identifier:@"This multi-pane tab"
                                          genericName:[NSString stringWithFormat:@"tab #%d",
                                                       [aTab realObjectCount]]];
        }
        return okToClose;
    }
    return YES;
}

- (void)closeTab:(PTYTab *)aTab soft:(BOOL)soft
{
    if (!soft &&
        [aTab isTmuxTab] &&
        [[aTab sessions] count] > 0 &&
        [[aTab tmuxController] isAttached]) {
        [[aTab tmuxController] killWindow:[aTab tmuxWindow]];
        return;
    }
    [self removeTab:(PTYTab *)aTab];
}

- (void)closeTab:(PTYTab*)aTab
{
    [self closeTab:aTab soft:NO];
}

// Just like closeTab but skips the tmux code. Terminates sessions, removes the
// tab, and closes the window if there are no tabs left.
- (void)removeTab:(PTYTab *)aTab
{
    int numberOfTabs = [TABVIEW numberOfTabViewItems];
    for (PTYSession* session in [aTab sessions]) {
        [session terminate];
    }
    if (numberOfTabs == 1 && [self windowInited]) {
        [[self window] close];
    } else {
        NSTabViewItem *aTabViewItem;
        // now get rid of this tab
        aTabViewItem = [aTab tabViewItem];
        [TABVIEW removeTabViewItem:aTabViewItem];
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

- (void)toggleFullScreenTabBar
{
    fullscreenTabs_ = !fullscreenTabs_;
    if (!temporarilyShowingTabs_) {
        [[NSUserDefaults standardUserDefaults] setBool:fullscreenTabs_
                                                forKey:kShowFullscreenTabBarKey];
    }
    [self repositionWidgets];
    [self fitTabsToWindow];
}

- (IBAction)closeCurrentTab:(id)sender
{
    if ([self tabView:TABVIEW shouldCloseTabViewItem:[TABVIEW selectedTabViewItem]]) {
        [self closeTab:[self currentTab]];
    }
}

- (IBAction)closeCurrentSession:(id)sender
{
    iTermApplicationDelegate *appDelegate = (iTermApplicationDelegate *)[[NSApplication sharedApplication] delegate];
    [appDelegate userDidInteractWithASession];
    if ([[self window] isKeyWindow]) {
        PTYSession *aSession = [[[TABVIEW selectedTabViewItem] identifier] activeSession];
        [self closeSessionWithConfirmation:aSession];
    }
}

- (void)closeSessionWithConfirmation:(PTYSession *)aSession
{
    if ([[[aSession tab] sessions] count] == 1) {
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

- (IBAction)previousTab:(id)sender
{
    [TABVIEW previousTab:sender];
}

- (IBAction)nextTab:(id)sender
{
    [TABVIEW nextTab:sender];
}

- (IBAction)previousPane:(id)sender
{
    [[self currentTab] previousSession];
}

- (IBAction)nextPane:(id)sender
{
    [[self currentTab] nextSession];
}

- (int)numberOfTabs
{
    return [TABVIEW numberOfTabViewItems];
}

- (PTYTab*)currentTab
{
    return [[TABVIEW selectedTabViewItem] identifier];
}

- (PTYSession *)currentSession
{
    return [[[TABVIEW selectedTabViewItem] identifier] activeSession];
}


- (void)setWindowTitle
{
    [self setWindowTitle:[self currentSessionName]];
}

- (void)setWindowTitle:(NSString *)title
{
    if (title == nil) {
        // title can be nil during loadWindowArrangement
        title = @"";
    }

    if ([[PreferencePanel sharedInstance] windowNumber]) {
        NSString *tmuxId = @"";
        if ([[self currentSession] isTmuxClient]) {
            tmuxId = [NSString stringWithFormat:@" [%@]",
                      [[[self currentSession] tmuxController] clientName]];
        }
        title = [NSString stringWithFormat:@"%d. %@%@", number_+1, title, tmuxId];
    }
    
    // In bug 2593, we see a crazy thing where setting the window title right
    // after a window is created causes it to have the wrong background color.
    // A delay of 0 doesn't fix it. I'm at wit's end here, so this will have to
    // do until a better explanation comes along. But during a live resize it
    // has to be done immediately because the runloop doesn't get around to
    // delayed performs until the live resize is done (bug 2812).
    if (liveResize_) {
        [[self window] setTitle:title];
    } else {
        [[self window] performSelector:@selector(setTitle:) withObject:title afterDelay:0.1];
    }
}

- (BOOL)tempTitle
{
    return tempTitle;
}

- (void)resetTempTitle
{
    tempTitle = NO;
}

- (NSArray *)broadcastSessions
{
    NSMutableArray *sessions = [NSMutableArray array];
    int i;
    int n = [TABVIEW numberOfTabViewItems];
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
                for (PTYSession* aSession in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
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

- (void)sendInputToAllSessions:(NSData *)data
{
    for (PTYSession *aSession in [self broadcastSessions]) {
        if ([aSession isTmuxClient]) {
            [aSession writeTaskNoBroadcast:data];
        } else if (![aSession isTmuxGateway]) {
            [aSession.shell writeTask:data];
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
            rect.origin.x = virtualScreenFrame.size.width - rect.size.width;
            rect.origin.y = yOrigin;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = virtualScreenFrame.size.height;
            break;

        case WINDOW_TYPE_RIGHT_PARTIAL:
            rect.origin.x = virtualScreenFrame.size.width - rect.size.width;
            rect.origin.y = yOrigin;
            rect.size.width = xScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
            rect.size.height = yScale * [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];
            break;
    }

    [[NSColor blackColor] set];
    NSRectFill(rect);
    [[NSColor windowFrameColor] set];
    NSFrameRect(rect);

    int N = [(NSDictionary *)[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_TABS] count];
    [[NSColor windowFrameColor] set];
    double y;
    if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
        y = rect.origin.y + rect.size.height - 10;
    } else {
        y = rect.origin.y;
    }
    NSRectFill(NSMakeRect(rect.origin.x + 1, y, rect.size.width - 2, 10));

    double x = 1;
    [[NSColor darkGrayColor] set];
    double step = MIN(20, floor((rect.size.width - 2) / N));
    for (int i = 0; i < N; i++) {
        NSRectFill(NSMakeRect(rect.origin.x + x + 1, y + 1, step - 2, 8));
        x += step;
    }

    NSDictionary* tabArrangement = [[terminalArrangement objectForKey:TERMINAL_ARRANGEMENT_TABS] objectAtIndex:0];
    [PTYTab drawArrangementPreview:tabArrangement frame:NSMakeRect(rect.origin.x + 1,
                                                                   ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) ? rect.origin.y : rect.origin.y + 10,
                                                                   rect.size.width - 2,
                                                                   rect.size.height - 11)];
}

+ (PseudoTerminal*)bareTerminalWithArrangement:(NSDictionary*)arrangement
{
    PseudoTerminal* term;
    int windowType = [PseudoTerminal _windowTypeForArrangement:arrangement];
    int screenIndex = [PseudoTerminal _screenIndexForArrangement:arrangement];
    if (windowType == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:WINDOW_TYPE_TRADITIONAL_FULL_SCREEN
                                                     screen:screenIndex] autorelease];

        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN] doubleValue];
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_OLD_HEIGHT] doubleValue];
        term->oldFrame_ = rect;
        term->useTransparency_ = ![[PreferencePanel sharedInstance] disableFullscreenTransparency];
        term->oldUseTransparency_ = YES;
        term->restoreUseTransparency_ = YES;
    } else if (windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO
                                                 windowType:WINDOW_TYPE_LION_FULL_SCREEN
                                                     screen:screenIndex] autorelease];
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
        term = [[[PseudoTerminal alloc] initWithSmartLayout:NO windowType:windowType screen:-1] autorelease];

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
    return term;
}

+ (PseudoTerminal*)terminalWithArrangement:(NSDictionary*)arrangement
{
    PseudoTerminal* term = [PseudoTerminal bareTerminalWithArrangement:arrangement];
    [term loadArrangement:arrangement];
    return term;
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

- (IBAction)newTmuxWindow:(id)sender
{
    [[self currentTmuxController] newWindowWithAffinity:nil];
}

- (IBAction)newTmuxTab:(id)sender
{
    int tmuxWindow = [[self currentTab] tmuxWindow];
    if (tmuxWindow < 0) {
        tmuxWindow = -(number_ + 1);
    }
    [[self currentTmuxController] newWindowWithAffinity:[NSString stringWithFormat:@"%d", tmuxWindow]];
}

- (NSSize)tmuxCompatibleSize
{
    NSSize tmuxSize = NSMakeSize(INT_MAX, INT_MAX);
    for (PTYTab *aTab in [self tabs]) {
        if ([aTab isTmuxTab]) {
            NSSize tabSize = [aTab tmuxSize];
            tmuxSize.width = (int) MIN(tmuxSize.width, tabSize.width);
            tmuxSize.height = (int) MIN(tmuxSize.height, tabSize.height);
        }
    }
    return tmuxSize;
}

- (void)loadTmuxLayout:(NSMutableDictionary *)parseTree
                window:(int)window
        tmuxController:(TmuxController *)tmuxController
                  name:(NSString *)name
{
    [self beginTmuxOriginatedResize];
    PTYTab *tab = [PTYTab openTabWithTmuxLayout:parseTree
                                     inTerminal:self
                                     tmuxWindow:window
                                 tmuxController:tmuxController];
    [self setWindowTitle:name];
    [tab setTmuxWindowName:name];
    [tab setReportIdealSizeAsCurrent:YES];
    [self fitWindowToTabs];
    [tab setReportIdealSizeAsCurrent:NO];

    for (PTYSession *aSession in [tab sessions]) {
        [tmuxController registerSession:aSession withPane:[aSession tmuxPane] inWindow:window];
        [aSession setTmuxController:tmuxController];
    }
    [self endTmuxOriginatedResize];
}

- (void)beginTmuxOriginatedResize
{
    ++tmuxOriginatedResizeInProgress_;
}

- (void)endTmuxOriginatedResize
{
    --tmuxOriginatedResizeInProgress_;
}

- (NSString *)terminalGuid
{
    return terminalGuid_;
}

- (void)hideAfterOpening
{
    hideAfterOpening_ = YES;
    [[self window] performSelector:@selector(miniaturize:)
                                            withObject:nil
                                            afterDelay:0];
}

- (void)loadArrangement:(NSDictionary *)arrangement
{
    PtyLog(@"Restore arrangement: %@", arrangement);
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_ROWS]) {
        desiredRows_ = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_ROWS] intValue];
    }
    if ([arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_COLUMNS]) {
        desiredColumns_ = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_DESIRED_COLUMNS] intValue];
    }
    for (NSDictionary* tabArrangement in [arrangement objectForKey:TERMINAL_ARRANGEMENT_TABS]) {
        [PTYTab openTabWithArrangement:tabArrangement inTerminal:self hasFlexibleView:NO];
    }
    int windowType = [PseudoTerminal _windowTypeForArrangement:arrangement];
    if (windowType == WINDOW_TYPE_NORMAL) {
        // The window may have changed size while adding tab bars, etc.
        NSRect rect;
        rect.origin.x = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_X_ORIGIN] doubleValue];
        rect.origin.y = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_Y_ORIGIN] doubleValue];
        // TODO: for window type top, set width to screen width.
        rect.size.width = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_WIDTH] doubleValue];
        rect.size.height = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_HEIGHT] doubleValue];

        [[self window] setFrame:rect display:YES];
    }

    const int tabIndex = [[arrangement objectForKey:TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX] intValue];
    if (tabIndex >= 0 && tabIndex < [TABVIEW numberOfTabViewItems]) {
        [TABVIEW selectTabViewItemAtIndex:tabIndex];
    }

    Profile* addressbookEntry = [[[[[self tabs] objectAtIndex:0] sessions] objectAtIndex:0] profile];
    if ([addressbookEntry objectForKey:KEY_SPACE] &&
        [[addressbookEntry objectForKey:KEY_SPACE] intValue] == -1) {
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorCanJoinAllSpaces];
    }
    if ([arrangement objectForKey:TERMINAL_GUID] &&
        [[arrangement objectForKey:TERMINAL_GUID] isKindOfClass:[NSString class]]) {
        [terminalGuid_ autorelease];
        terminalGuid_ = [[arrangement objectForKey:TERMINAL_GUID] retain];
    }

    [self fitTabsToWindow];
}

- (NSDictionary *)arrangementExcludingTmuxTabs:(BOOL)excludeTmux
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:7];
    NSRect rect = [[self window] frame];
    int screenNumber = 0;
    for (NSScreen* screen in [NSScreen screens]) {
        if (screen == [[self window] deepestScreen]) {
            break;
        }
        ++screenNumber;
    }

    [result setObject:terminalGuid_ forKey:TERMINAL_GUID];

    // Save window frame
    [result setObject:[NSNumber numberWithDouble:rect.origin.x]
               forKey:TERMINAL_ARRANGEMENT_X_ORIGIN];
    [result setObject:[NSNumber numberWithDouble:rect.origin.y]
               forKey:TERMINAL_ARRANGEMENT_Y_ORIGIN];
    [result setObject:[NSNumber numberWithDouble:rect.size.width]
               forKey:TERMINAL_ARRANGEMENT_WIDTH];
    [result setObject:[NSNumber numberWithDouble:rect.size.height]
               forKey:TERMINAL_ARRANGEMENT_HEIGHT];

    if ([self anyFullScreen]) {
        // Save old window frame
        [result setObject:[NSNumber numberWithDouble:oldFrame_.origin.x]
                   forKey:TERMINAL_ARRANGEMENT_OLD_X_ORIGIN];
        [result setObject:[NSNumber numberWithDouble:oldFrame_.origin.y]
                   forKey:TERMINAL_ARRANGEMENT_OLD_Y_ORIGIN];
        [result setObject:[NSNumber numberWithDouble:oldFrame_.size.width]
                   forKey:TERMINAL_ARRANGEMENT_OLD_WIDTH];
        [result setObject:[NSNumber numberWithDouble:oldFrame_.size.height]
                   forKey:TERMINAL_ARRANGEMENT_OLD_HEIGHT];
    }

    [result setObject:[NSNumber numberWithInt:([self lionFullScreen] ? WINDOW_TYPE_LION_FULL_SCREEN : windowType_)]
               forKey:TERMINAL_ARRANGEMENT_WINDOW_TYPE];
    [result setObject:[NSNumber numberWithInt:[[NSScreen screens] indexOfObjectIdenticalTo:[[self window] screen]]]
                                       forKey:TERMINAL_ARRANGEMENT_SCREEN_INDEX];
    [result setObject:[NSNumber numberWithInt:desiredRows_]
               forKey:TERMINAL_ARRANGEMENT_DESIRED_ROWS];
    [result setObject:[NSNumber numberWithInt:desiredColumns_]
               forKey:TERMINAL_ARRANGEMENT_DESIRED_COLUMNS];
    // Save tabs.
    NSMutableArray* tabs = [NSMutableArray arrayWithCapacity:[self numberOfTabs]];
    for (NSTabViewItem* tabViewItem in [TABVIEW tabViewItems]) {
        PTYTab *theTab = [tabViewItem identifier];
        if ([[theTab sessions] count]) {
            if (!excludeTmux || ![theTab isTmuxTab]) {
                [tabs addObject:[[tabViewItem identifier] arrangement]];
            }
        }
    }
    if ([tabs count] == 0) {
        return nil;
    }
    [result setObject:tabs forKey:TERMINAL_ARRANGEMENT_TABS];

    // Save index of selected tab.
    [result setObject:[NSNumber numberWithInt:[TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]]
               forKey:TERMINAL_ARRANGEMENT_SELECTED_TAB_INDEX];
    [result setObject:[NSNumber numberWithBool:hideAfterOpening_]
               forKey:TERMINAL_ARRANGEMENT_HIDE_AFTER_OPENING];

    return result;
}

- (NSDictionary*)arrangement
{
    return [self arrangementExcludingTmuxTabs:YES];
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
    for (PTYSession *aSession in [self sessions]) {
        if ([aSession promptOnClose]) {
            return YES;
        }
    }
    return NO;
}

- (ToolbeltView *)toolbelt
{
    return toolbelt_;
}

- (void)refreshTools {
    [[toolbelt_ commandHistoryView] updateCommands];
}

- (int)numRunningSessions
{
    int n = 0;
    for (PTYSession *aSession in [self sessions]) {
        if (![aSession exited]) {
            ++n;
        }
    }
    return n;
}

- (BOOL)windowShouldClose:(NSNotification *)aNotification
{
    // This counts as an interaction beacuse it is only called when the user initiates the closing of the window (as opposed to a session dying on you).
    iTermApplicationDelegate *appDelegate = (iTermApplicationDelegate *)[[NSApplication sharedApplication] delegate];
    [appDelegate userDidInteractWithASession];

    BOOL needPrompt = NO;
    if ([self promptOnClose]) {
        needPrompt = YES;
    }
    if ([[PreferencePanel sharedInstance] onlyWhenMoreTabs] &&
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
        // If there are tmux tabs, tell the tmux server to kill the window, but
        // go ahead and close the window anyway because there might be non-tmux
        // tabs as well. This is a rare instance of performing an action on a
        // tmux object without waiting for the server to tell us to do it.
        for (PTYTab *aTab in [self tabs]) {
            if ([aTab isTmuxTab]) {
                [[aTab tmuxController] killWindow:[aTab tmuxWindow]];
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

- (void)windowWillClose:(NSNotification *)aNotification
{
    // Close popups.
    [pbHistoryView close];
    [autocompleteView close];
    [commandHistoryPopup close];

    // tabBarControl is holding on to us, so we have to tell it to let go
    [tabBarControl setDelegate:nil];

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
        if ([[PreferencePanel sharedInstance] smartPlacement]) {
            [[self window] saveFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, 0]];
        } else {
            // Save frame position for window
            [[self window] saveFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, uniqueNumber_]];
            [[TemporaryNumberAllocator sharedInstance] deallocateNumber:uniqueNumber_];
        }
    } else {
        if (![[PreferencePanel sharedInstance] smartPlacement]) {
            // Save frame position for window
            [[self window] saveFrameUsingName:[NSString stringWithFormat:kWindowNameFormat, uniqueNumber_]];
            [[TemporaryNumberAllocator sharedInstance] deallocateNumber:uniqueNumber_];
        }
    }

    // Kill sessions so their timers stop and they are freed.
    for (PTYSession* session in [self sessions]) {
        [session terminate];
    }

    // This releases the last reference to self.
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

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    [self maybeHideHotkeyWindow];
    [[[NSApplication sharedApplication] dockTile] setBadgeLabel:@""];
    [[[NSApplication sharedApplication] dockTile] setShowsApplicationBadge:NO];
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidBecomeKey:%@]",
          __FILE__, __LINE__, aNotification);

    [[iTermController sharedInstance] setCurrentTerminal:self];
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    [itad updateMaximizePaneMenuItem];
    [itad updateUseTransparencyMenuItem];
    [itad updateBroadcastMenuState];
    if (_fullScreen) {
        if (![self isHotKeyWindow] ||
            [[HotkeyWindowController sharedInstance] rollingInHotkeyTerm] ||
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
    if ([[[self currentSession] textview] refresh]) {
        [[self currentSession] scheduleUpdateIn:[[PreferencePanel sharedInstance] timeBetweenBlinks]];
    }
    [[[self currentSession] textview] setNeedsDisplay:YES];
    [self _loadFindStringFromSharedPasteboard];

    // Start the timers back up
    for (PTYSession* aSession in [self sessions]) {
        [aSession updateDisplay];
        [[aSession view] setBackgroundDimmed:NO];
        [aSession setFocused:aSession == [self currentSession]];
    }
    // Some users report that the first responder isn't always set properly. Let's try to fix that.
    // This attempt (4/20/13) is to fix bug 2431.
    [self performSelector:@selector(makeCurrentSessionFirstResponder)
               withObject:nil
               afterDelay:0];
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
- (BOOL)disableFocusFollowsMouse
{
    return isHotKeyWindow_;
}

- (NSRect)fullscreenToolbeltFrame
{
    CGFloat width = [self fullscreenToolbeltWidth];
    NSRect toolbeltFrame = NSMakeRect(self.window.frame.size.width - width,
                                      0,
                                      width,
                                      self.window.frame.size.height);
    return toolbeltFrame;
}

- (void)canonicalizeWindowFrame {
    PtyLog(@"canonicalizeWindowFrame");
    PTYSession* session = [self currentSession];
    NSDictionary* abDict = [session profile];
    NSScreen* screen = [[self window] deepestScreen];
    if (!screen) {
        PtyLog(@"No deepest screen");
        // Try to use the screen of the current session. Fall back to the main
        // screen if that's not an option.
        int screenNumber = [abDict objectForKey:KEY_SCREEN] ? [[abDict objectForKey:KEY_SCREEN] intValue] : 0;
        NSArray* screens = [NSScreen screens];
        if ([screens count] == 0) {
            PtyLog(@"We are headless");
            // Nothing we can do if we're headless.
            return;
        }
        if ([screens count] < screenNumber) {
            PtyLog(@"Using screen 0 because the preferred screen isn't around any more");
            screenNumber = 0;
        }
        screen = [[NSScreen screens] objectAtIndex:screenNumber];
    }
    NSRect frame = [[self window] frame];

    PtyLog(@"The new screen visible frame is %@", [NSValue valueWithRect:[screen visibleFrame]]);

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
                frame.size.height = MIN([screen visibleFrame].size.height,
                                        ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * VMARGIN);
            } else {
                frame.size.height = MIN([screen visibleFrame].size.height, frame.size.height);
            }
            if (!edgeSpanning) {
                frame.size.width = MIN(frame.size.width, [screen visibleFrame].size.width);
                frame.origin.x = MAX(frame.origin.x, screen.visibleFrame.origin.x);
                double freeSpaceOnLeft = MIN(0, [screen visibleFrame].size.width - frame.size.width - (frame.origin.x - screen.visibleFrame.origin.x));
                frame.origin.x += freeSpaceOnLeft;
            } else {
                frame.size.width = [screen visibleFrame].size.width;
                frame.origin.x = [screen visibleFrame].origin.x;
            }
            if ([[self window] alphaValue] == 0) {
                // Is hidden hotkey window
                frame.origin.y = [screen visibleFrame].origin.y + [screen visibleFrame].size.height;
            } else {
                // Normal case
                frame.origin.y = [screen visibleFrame].origin.y + [screen visibleFrame].size.height - frame.size.height;
            }

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
                frame.size.height = MIN([screen visibleFrame].size.height,
                                        ceil([[session textview] lineHeight] * desiredRows_) + decorationSize.height + 2 * VMARGIN);
            } else {
                frame.size.height = MIN([screen visibleFrame].size.height, frame.size.height);
            }
            if (!edgeSpanning) {
                frame.size.width = MIN(frame.size.width, [screen visibleFrame].size.width);
                frame.origin.x = MAX(frame.origin.x, screen.visibleFrame.origin.x);
                double freeSpaceOnLeft = MIN(0, [screen visibleFrame].size.width - frame.size.width - (frame.origin.x - screen.visibleFrame.origin.x));
                frame.origin.x += freeSpaceOnLeft;
            } else {
                frame.size.width = [screen visibleFrame].size.width;
                frame.origin.x = [screen visibleFrame].origin.x;
            }
            if ([[self window] alphaValue] == 0) {
                // Is hidden hotkey window
                frame.origin.y = [screen visibleFrame].origin.y - frame.size.height;
            } else {
                // Normal case
                frame.origin.y = [screen visibleFrame].origin.y;
            }

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
                frame.size.width = MIN([screen visibleFrame].size.width,
                                       [[session textview] charWidth] * desiredColumns_ + 2 * MARGIN);
            } else {
                frame.size.width = MIN([screen visibleFrame].size.width, frame.size.width);
            }
            if (!edgeSpanning) {
                frame.size.height = MIN(frame.size.height, [screen visibleFrame].size.height);
                frame.origin.y = MAX(frame.origin.y, screen.visibleFrame.origin.y);
                double freeSpaceOnBottom = MIN(0, [screen visibleFrame].size.height - frame.size.height - (frame.origin.y - screen.visibleFrame.origin.y));
                frame.origin.y += freeSpaceOnBottom;
            } else {
                frame.size.height = [screen visibleFrame].size.height;
                frame.origin.y = [screen visibleFrame].origin.y;
            }
            if ([[self window] alphaValue] == 0) {
                // Is hidden hotkey window
                frame.origin.x = [screen visibleFrame].origin.x - frame.size.width;
            } else {
                // Normal case
                frame.origin.x = [screen visibleFrame].origin.x;
            }

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
                frame.size.width = MIN([screen visibleFrame].size.width,
                                       [[session textview] charWidth] * desiredColumns_ + 2 * MARGIN);
            } else {
                frame.size.width = MIN([screen visibleFrame].size.width, frame.size.width);
            }
            if (!edgeSpanning) {
                frame.size.height = MIN(frame.size.height, [screen visibleFrame].size.height);
                frame.origin.y = MAX(frame.origin.y, screen.visibleFrame.origin.y);
                double freeSpaceOnBottom = MIN(0, [screen visibleFrame].size.height - frame.size.height - (frame.origin.y - screen.visibleFrame.origin.y));
                frame.origin.y += freeSpaceOnBottom;
            } else {
                frame.size.height = [screen visibleFrame].size.height;
                frame.origin.y = [screen visibleFrame].origin.y;
            }
            if ([[self window] alphaValue] == 0) {
                // Is hidden hotkey window
                frame.origin.x = [screen visibleFrame].origin.x + [screen visibleFrame].size.width;
            } else {
                // Normal case
                frame.origin.x = [screen visibleFrame].origin.x + [screen visibleFrame].size.width - frame.size.width;
            }

            if (frame.size.width > 0) {
                [[self window] setFrame:frame display:YES];
            }
            break;

        case WINDOW_TYPE_NORMAL:
            PtyLog(@"Window type = NORMAL");
            if (![self lionFullScreen]) {
                PtyLog(@"Window type = NORMAL BUT it's not lion fullscreen");
                break;
            }
            // fall through
        case WINDOW_TYPE_LION_FULL_SCREEN:
            PtyLog(@"Window type = LION");
        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            PtyLog(@"Window type = FULL SCREEN");
            if ([screen frame].size.width > 0) {
                PtyLog(@"set window to screen's frame");
                if (windowType_ == WINDOW_TYPE_TRADITIONAL_FULL_SCREEN) {
                    [[self window] setFrame:[self traditionalFullScreenFrameForScreen:screen] display:YES];
                } else {
                    [[self window] setFrame:[screen frame] display:YES];
                }
            }
            break;

        default:
            break;
    }

    if ([self anyFullScreen] || [self isEdgeWindow]) {
        [toolbelt_ setFrame:[self fullscreenToolbeltFrame]];
    }
}

- (void)screenParametersDidChange
{
    PtyLog(@"Screen parameters changed.");
    [self canonicalizeWindowFrame];
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    for (PTYSession *aSession in [self sessions]) {
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

    [self maybeHideHotkeyWindow];

    if (fullScreenTabviewTimer_) {
        // If the window has been closed then it's possible that the
        // timer is the only object left that is holding a reference to
        // self. Retain and autorelease so that invalidating the timer
        // doesn't free self while there's still stuff going on in this
        // function.
        [self retain];
        [self autorelease];
        [fullScreenTabviewTimer_ invalidate];
        fullScreenTabviewTimer_ = nil;
    } else {
        [self hideFullScreenTabControl];
    }

    if ([[pbHistoryView window] isVisible] ||
        [[autocompleteView window] isVisible] ||
        [[commandHistoryPopup window] isVisible]) {
        return;
    }

    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignKey:%@]",
          __FILE__, __LINE__, aNotification);

    if (_fullScreen) {
        [self hideFullScreenTabControl];
        [self showMenuBar];
    }
    // update the cursor
    [[[self currentSession] textview] refresh];
    [[[self currentSession] textview] setNeedsDisplay:YES];
    if (![self lionFullScreen]) {
        // Don't dim Lion fullscreen because you can't see the window when it's not key.
        for (PTYSession* aSession in [self sessions]) {
            [[aSession view] setBackgroundDimmed:YES];
        }
    }
    for (PTYSession* aSession in [self sessions]) {
        [aSession setFocused:NO];
    }
}

// Returns the hotkey window that should be hidden or nil if the hotkey window
// shouldn't be hidden right now.
- (PseudoTerminal *)hotkeyWindowToHide {
    DLog(@"Checking if hotkey window should be hidden.");
    BOOL haveMain = NO;
    BOOL otherTerminalIsKey = NO;
    for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
        if ([window isMainWindow]) {
            haveMain = YES;
        }
    }
    PseudoTerminal *hotkeyTerminal = nil;
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        PTYWindow *window = [term ptyWindow];
        DLog(@"Window %@ key=%d", window, [window isKeyWindow]);
        if ([window isKeyWindow] && ![term isHotKeyWindow]) {
            DLog(@"Key window is %@", window);
            otherTerminalIsKey = YES;
        }
        if ([term isHotKeyWindow]) {
            hotkeyTerminal = term;
        }
    }

    DLog(@"%@ haveMain=%d otherTerminalIsKey=%d", self.window, haveMain, otherTerminalIsKey);
    if (hotkeyTerminal && (!haveMain || otherTerminalIsKey)) {
        return hotkeyTerminal;
    } else {
        DLog(@"No need to hide hotkey window");
        return nil;
    }
}

- (void)maybeHideHotkeyWindow {
    if (togglingFullScreen_) {
        return;
    }
    PseudoTerminal *hotkeyTerminal = [self hotkeyWindowToHide];
    if (hotkeyTerminal) {
        DLog(@"Want to hide hotkey window");
        if ([[hotkeyTerminal window] alphaValue] > 0 &&
            [[PreferencePanel sharedInstance] hotkeyAutoHides] &&
            ![[HotkeyWindowController sharedInstance] rollingInHotkeyTerm]) {
            DLog(@"windowDidResignKey: is hotkey and hotkey window auto-hides");
            // We want to dismiss the hotkey window when some other window
            // becomes key. Note that if a popup closes this function shouldn't
            // be called at all because it makes us key before closing itself.
            // If a popup is opening, though, we shouldn't close ourselves.
            if (![[NSApp keyWindow] isKindOfClass:[PopupWindow class]] &&
                ![[[NSApp keyWindow] windowController] isKindOfClass:[ProfilesWindow class]] &&
                ![[[NSApp keyWindow] windowController] isKindOfClass:[PreferencePanel class]]) {
                PtyLog(@"windowDidResignKey: new key window isn't popup so hide myself");
                if ([[[NSApp keyWindow] windowController] isKindOfClass:[PseudoTerminal class]]) {
                    [[HotkeyWindowController sharedInstance] doNotOrderOutWhenHidingHotkeyWindow];
                }
                [[HotkeyWindowController sharedInstance] hideHotKeyWindow:hotkeyTerminal];
            }
        }
    }
}

- (void)windowDidResignMain:(NSNotification *)aNotification
{
    PtyLog(@"%s(%d):-[PseudoTerminal windowDidResignMain:%@]",
          __FILE__, __LINE__, aNotification);
    [self maybeHideHotkeyWindow];

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

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
    PtyLog(@"%s(%d):-[PseudoTerminal windowWillResize: obj=%p, proposedFrameSize width = %f; height = %f]",
           __FILE__, __LINE__, [self window], proposedFrameSize.width, proposedFrameSize.height);

    // Find the session for the current pane of the current tab.
    PTYTab* tab = [self currentTab];
    PTYSession* session = [tab activeSession];

    // Get the width and height of characters in this session.
    float charWidth = [[session textview] charWidth];
    float charHeight = [[session textview] lineHeight];

    // Decide when to snap.  (We snap unless control is held down.)
    BOOL modifierDown = (([[NSApp currentEvent] modifierFlags] & NSControlKeyMask) != 0);
    BOOL snapWidth = !modifierDown;
    BOOL snapHeight = !modifierDown;
    if (sender != [self window]) {
      snapWidth = snapHeight = NO;
    }

    // If resizing a full-width/height X-of-screen window in a direction perpindicular to the screen
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
    for (NSTabViewItem* tabViewItem in [TABVIEW tabViewItems]) {
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
      int deltaX = abs(senderSize.width - proposedFrameSize.width);
      if (deltaX < (int)(charWidth / 2)) {
        proposedFrameSize.width = senderSize.width;
      }
    }
    if (snapHeight) {
      int deltaY = abs(senderSize.height - proposedFrameSize.height);
      if (deltaY < (int)(charHeight / 2)) {
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

- (void)windowDidMove:(NSNotification *)notification
{
    DLog(@"%@: Window %@ moved. Called from %@", self, self.window, [NSThread callStackSymbols]);
    [self saveTmuxWindowOrigins];
}

- (void)windowDidResize:(NSNotification *)aNotification
{
    lastResizeTime_ = [[NSDate date] timeIntervalSince1970];
    if (zooming_) {
        // Pretend nothing happened to avoid slowing down zooming.
        return;
    }

    PtyLog(@"windowDidResize to: %fx%f", [[self window] frame].size.width, [[self window] frame].size.height);
    [SessionView windowDidResize];
    if (togglingFullScreen_) {
        PtyLog(@"windowDidResize returning because togglingFullScreen.");
        return;
    }

    // Adjust the size of all the sessions.
    PtyLog(@"windowDidResize - call repositionWidgets");
    [self repositionWidgets];

    [self notifyTmuxOfWindowResize];

    for (PTYTab *aTab in [self tabs]) {
        if ([aTab isTmuxTab]) {
            [aTab updateFlexibleViewColors];
        }
    }

    PTYSession* session = [self currentSession];
    NSString *aTitle = [NSString stringWithFormat:@"%@ (%d,%d)",
                        [self currentSessionName],
                        [session columns],
                        [session rows]];
    tempTitle = YES;
    [self setWindowTitle:aTitle];
    [self fitTabsToWindow];

    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermWindowDidResize"
                                                        object:self
                                                      userInfo:nil];
    [self invalidateRestorableState];
}

// PTYWindowDelegateProtocol
- (void)windowWillToggleToolbarVisibility:(id)sender
{
}

- (void)windowDidToggleToolbarVisibility:(id)sender
{
    PtyLog(@"windowDidToggleToolbarVisibility - calling fitWindowToTabs");
    [self fitWindowToTabs];
}

// See issue 2925.
// tl;dr: Content shadow on with a transparent view produces ghosting.
//        Content shadow off causes artifacts in the corners of the window.
// So turn the shadow off only when there's a transparent view.
- (void)updateContentShadow {
    if (useTransparency_) {
        for (PTYSession *aSession in [self sessions]) {
            if (aSession.textview.transparency > 0) {
                [self.ptyWindow _setContentHasShadow:NO];
                return;
            }
        }
    }
    [self.ptyWindow _setContentHasShadow:YES];
}

- (void)updateUseTransparency {
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    [itad updateUseTransparencyMenuItem];
    for (PTYSession* aSession in [self sessions]) {
        [[aSession view] setNeedsDisplay:YES];
    }
    [self updateContentShadow];
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

    if (![[PreferencePanel sharedInstance] hideMenuBarInFullscreen]) {
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

- (IBAction)toggleFullScreenMode:(id)sender
{
    DLog(@"toggleFullScreenMode:. window type is %d", windowType_);
    if ([self lionFullScreen] ||
        (windowType_ != WINDOW_TYPE_TRADITIONAL_FULL_SCREEN &&
         !isHotKeyWindow_ &&  // NSWindowCollectionBehaviorFullScreenAuxiliary window can't enter Lion fullscreen mode properly
         [[PreferencePanel sharedInstance] lionStyleFullscreen])) {
        // Is 10.7 Lion or later.
        [[self ptyWindow] performSelector:@selector(toggleFullScreen:) withObject:self];
        if (lionFullScreen_) {
            DLog(@"Set window type to lion fs");
            windowType_ = WINDOW_TYPE_LION_FULL_SCREEN;
        } else {
            DLog(@"Set window type to normal");
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
        [[PreferencePanel sharedInstance] lionStyleFullscreen]) {
        if (![[[iTermController sharedInstance] keyTerminalWindow] lionFullScreen]) {
            // call enter(Traditional)FullScreenMode instead of toggle... because
            // when doing a lion resume, the window may be toggled immediately
            // after creation by the window restorer.
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

- (void)updateSessionScrollbars
{
    for (PTYSession *aSession in [self sessions]) {
        BOOL hasScrollbar = [self scrollbarShouldBeVisible];
        [[aSession scrollview] setHasVerticalScroller:hasScrollbar];
        [[aSession scrollview] setScrollerStyle:[self scrollerStyle]];
        [[aSession textview] updateScrollerForBackgroundColor];
    }
}

- (NSUInteger)styleMask {
    switch (windowType_) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_TOP_PARTIAL:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
        case WINDOW_TYPE_LEFT_PARTIAL:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            return NSBorderlessWindowMask | NSResizableWindowMask;

        case WINDOW_TYPE_TRADITIONAL_FULL_SCREEN:
            return NSBorderlessWindowMask;
            
        case WINDOW_TYPE_LION_FULL_SCREEN:
        case WINDOW_TYPE_NORMAL:
        default:
            return (NSTitledWindowMask |
                    NSClosableWindowMask |
                    NSMiniaturizableWindowMask |
                    NSResizableWindowMask |
                    NSTexturedBackgroundWindowMask);
    }
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

- (void)setWindowStyleMask:(NSUInteger)newStyleMask {
    if (!(newStyleMask & NSTitledWindowMask)) {
        [self.window setToolbar:nil];
        self.toolbarController = nil;
        [self.window setStyleMask:newStyleMask];
    } else if (!_toolbarController) {
        [self.window setStyleMask:newStyleMask];
        self.toolbarController =
            [[[PTToolbarController alloc] initWithPseudoTerminal:self] autorelease];
    }
}

- (void)toggleTraditionalFullScreenMode
{
    [SessionView windowDidResize];
    PtyLog(@"toggleFullScreenMode called");
    if (!_fullScreen) {
        oldFrame_ = self.window.frame;
        oldFrameSizeIsBogus_ = NO;
        savedWindowType_ = windowType_;
        windowType_ = WINDOW_TYPE_TRADITIONAL_FULL_SCREEN;
        [self.window setOpaque:NO];
        self.window.alphaValue = 0;
        // The toolbar goes away for traditional fullscreen windows because a
        // borderless window doesn't support a toolbar.
        [self setWindowStyleMask:[self styleMask]];
        [self.window setFrame:self.window.screen.frame display:YES];
        self.window.alphaValue = 1;
    } else {
        [self showMenuBar];
        windowType_ = savedWindowType_;
        [self setWindowStyleMask:[self styleMask]];

        // This will be close but probably not quite right because tweaking to the decoration size
        // happens later.
        if (oldFrameSizeIsBogus_) {
            oldFrame_.size = [self preferredWindowFrameToPerfectlyFitCurrentSessionInInitialConfiguration];
        }
        [self.window setFrame:oldFrame_ display:YES];
        PtyLog(@"toggleFullScreenMode - allocate new terminal");
    }

    if (!_fullScreen &&
        [[PreferencePanel sharedInstance] disableFullscreenTransparency]) {
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
    togglingFullScreen_ = YES;
    [self _updateToolbeltParentage];
    [self updateUseTransparency];
    
    if (_fullScreen) {
        PtyLog(@"toggleFullScreenMode - call adjustFullScreenWindowForBottomBarChange");
        [self fitTabsToWindow];
        [self hideMenuBar];

        iTermApplicationDelegate *itad =
            (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
        [toolbelt_ setHidden:![itad showToolbelt]];
        // The toolbelt may try to become the first responder.
        [[self window] makeFirstResponder:[[self currentSession] textview]];
    } else {
        // Find the largest possible session size for the existing window frame
        // and fit the window to an imaginary session of that size.
        NSSize contentSize = [[[self window] contentView] frame].size;
        if ([self tabBarShouldBeVisible]) {
            contentSize.height -= [tabBarControl frame].size.height;
        }
        if ([self _haveLeftBorder]) {
            --contentSize.width;
        }
        if ([self _haveRightBorder]) {
            --contentSize.width;
        }
        if ([self _haveBottomBorder]) {
            --contentSize.height;
        }
        if ([self _haveTopBorder]) {
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
}

- (BOOL)fullScreen
{
    return _fullScreen;
}

- (BOOL)tabBarShouldBeVisible
{
    return [self tabBarShouldBeVisibleWithAdditionalTabs:0];
}

- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)n
{
    if ([self anyFullScreen] && !fullscreenTabs_) {
        return NO;
    }
    return ([TABVIEW numberOfTabViewItems] + n > 1 ||
            ![[PreferencePanel sharedInstance] hideTab]);
}

- (NSScrollerStyle)scrollerStyle
{
    if ([self anyFullScreen]) {
        return NSScrollerStyleOverlay;
    } else {
        return [NSScroller preferredScrollerStyle];
    }
}

- (BOOL)scrollbarShouldBeVisible
{
    return ![[PreferencePanel sharedInstance] hideScrollbar];
}

- (void)windowWillStartLiveResize:(NSNotification *)notification
{
    liveResize_ = YES;
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
    NSScreen *screen = self.window.screen;
    NSRect frame = self.window.frame;
    switch (windowType_) {
        case WINDOW_TYPE_TOP:
        case WINDOW_TYPE_TOP_PARTIAL:
            frame.origin.y = [screen visibleFrame].origin.y + [screen visibleFrame].size.height - frame.size.height;
            if ((frame.size.width < [screen visibleFrame].size.width)) {
                windowType_ = WINDOW_TYPE_TOP_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_TOP;
            }
            break;
            
        case WINDOW_TYPE_BOTTOM:
        case WINDOW_TYPE_BOTTOM_PARTIAL:
            frame.origin.y = [screen visibleFrame].origin.y;
            if (frame.size.width < [screen visibleFrame].size.width) {
                windowType_ = WINDOW_TYPE_BOTTOM_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_BOTTOM;
            }
            break;
            
        case WINDOW_TYPE_LEFT:
        case WINDOW_TYPE_LEFT_PARTIAL:
            frame.origin.x = [screen visibleFrame].origin.x;
            if (frame.size.height < [screen visibleFrame].size.height) {
                windowType_ = WINDOW_TYPE_LEFT_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_LEFT;
            }
            break;
            
        case WINDOW_TYPE_RIGHT:
        case WINDOW_TYPE_RIGHT_PARTIAL:
            frame.origin.x = [screen visibleFrame].origin.x + [screen visibleFrame].size.width - frame.size.width;
            if (frame.size.height < [screen visibleFrame].size.height) {
                windowType_ = WINDOW_TYPE_RIGHT_PARTIAL;
            } else {
                windowType_ = WINDOW_TYPE_RIGHT;
            }
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
        [self windowDidResize:nil];
    }
    if (postponedTmuxTabLayoutChange_) {
        [self tmuxTabLayoutDidChange:YES];
        postponedTmuxTabLayoutChange_ = NO;
    }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    DLog(@"Window will enter lion fullscreen");
    [self repositionWidgets];
    togglingLionFullScreen_ = YES;
    [_divisionView removeFromSuperview];
    [_divisionView release];
    _divisionView = nil;
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    DLog(@"Window did enter lion fullscreen");
    [toolbelt_ setUseDarkDividers:YES];
    zooming_ = NO;
    togglingLionFullScreen_ = NO;
    lionFullScreen_ = YES;
    [self _updateToolbeltParentage];
    // Set scrollbars appropriately
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self invalidateRestorableState];
    [self notifyTmuxOfWindowResize];
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    DLog(@"Window will exit lion fullscreen");
    exitingLionFullscreen_ = YES;
    [fullScreenTabviewTimer_ invalidate];
    fullScreenTabviewTimer_ = nil;
    if (temporarilyShowingTabs_) {
        // If tabs were shown because you were holding cmd, reset that state.
        [self hideFullScreenTabControl];
        temporarilyShowingTabs_ = NO;
    }
    [self fitTabsToWindow];
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    if ([itad showToolbelt]) {
        [toolbelt_ setHidden:YES];
    }
    [self repositionWidgets];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    DLog(@"Window did exit lion fullscreen");
    [toolbelt_ setUseDarkDividers:NO];
    exitingLionFullscreen_ = NO;
    zooming_ = NO;
    lionFullScreen_ = NO;
    // Set scrollbars appropriately
    [self updateDivisionView];
    [self updateSessionScrollbars];
    [self fitTabsToWindow];
    [self repositionWidgets];
    [self invalidateRestorableState];
    [self _updateToolbeltParentage];
    // TODO this is only ok because top, bottom, and non-lion fullscreen windows
    // can't become lion fullscreen windows:
    windowType_ = WINDOW_TYPE_NORMAL;
    for (PTYTab *aTab in [self tabs]) {
        [aTab notifyWindowChanged];
    }
    [self notifyTmuxOfWindowResize];
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
        [[[self currentSession] scrollview] documentVisibleRect].size.height + VMARGIN * 2;
    float decorationWidth = [sender frame].size.width -
        [[[self currentSession] scrollview] documentVisibleRect].size.width + MARGIN * 2;

    float charHeight = [self maxCharHeight:nil];
    float charWidth = [self maxCharWidth:nil];

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
        maxVerticallyPref = [[PreferencePanel sharedInstance] maxVertically];
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

- (void)windowWillShowInitial
{
    PtyLog(@"windowWillShowInitial");
    PTYWindow* window = (PTYWindow*)[self window];
    // If it's a full or top-of-screen window with a screen number preference, always honor that.
    if (haveScreenPreference_) {
        PtyLog(@"have screen preference is set");
        NSRect frame = [window frame];
        frame.origin = preferredOrigin_;
        [window setFrame:frame display:NO];
        return;
    }
    if (([[[iTermController sharedInstance] terminals] count] == 1) ||
        (![[PreferencePanel sharedInstance] smartPlacement])) {
        if ([iTermSettingsModel rememberWindowPositions]) {
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

    [[session tab] setLockedSession:session];
    [self safelySetSessionSize:session rows:height columns:width];
    PtyLog(@"sessionInitiatedResize - calling fitWindowToTab");
    [self fitWindowToTab:[session tab]];
    PtyLog(@"sessionInitiatedResize - calling fitTabsToWindow");
    [self fitTabsToWindow];
    [[session tab] setLockedSession:nil];
}

// Contextual menu
- (void)editCurrentSession:(id)sender
{
    PTYSession* session = [self currentSession];
    if (!session) {
        return;
    }
    [self editSession:session];
}

- (void)editSession:(PTYSession*)session
{
    Profile* bookmark = [session profile];
    if (!bookmark) {
        return;
    }
    NSString* newGuid = [session divorceAddressBookEntryFromPreferences];
    [[PreferencePanel sessionsInstance] openToBookmark:newGuid];
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
    if ([TABVIEW numberOfTabViewItems] > 1) {
        [theMenu insertItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select",
                                                                        @"iTerm",
                                                                        [NSBundle bundleForClass:[self class]],
                                                                        @"Context menu")
                              action:nil
                       keyEquivalent:@""
                             atIndex:nextIndex];

        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@""];
        int i;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aMenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ #%d",
                                                           [[TABVIEW tabViewItemAtIndex: i] label],
                                                           i+1]
                                                   action:@selector(selectTab:)
                                            keyEquivalent:@""];
            [aMenuItem setRepresentedObject:[[TABVIEW tabViewItemAtIndex:i] identifier]];
            [aMenuItem setTarget:TABVIEW];
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

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    if (_autoCommandHistorySessionId != -1) {
        [self hideAutoCommandHistory];
    }
    for (PTYSession* aSession in [[tabViewItem identifier] sessions]) {
        [aSession setNewOutput:NO];

        // Background tabs' timers run infrequently so make sure the display is
        // up to date to avoid a jump when it's shown.
        [[aSession textview] setNeedsDisplay:YES];
        [aSession updateDisplay];
        [aSession scheduleUpdateIn:kFastTimerIntervalSec];
                [self setDimmingForSession:aSession];
                [[aSession view] setBackgroundDimmed:![[self window] isKeyWindow]];
    }

    for (PTYSession *session in [self sessions]) {
        if ([[session textview] isFindingCursor]) {
            [[session textview] endFindCursor];
        }
    }
    PTYSession* aSession = [[tabViewItem identifier] activeSession];
    if (!_fullScreen) {
        [[aSession tab] updateLabelAttributes];
        [self setWindowTitle];
    }

    [[self window] makeFirstResponder:[[[tabViewItem identifier] activeSession] textview]];
    if ([[aSession tab] blur]) {
        [self enableBlur:[[aSession tab] blurRadius]];
    } else {
        [self disableBlur];
    }

    [_instantReplayWindowController updateInstantReplayView];
    // Post notifications
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[[tabViewItem identifier] activeSession]];

    PTYSession *activeSession = [self currentSession];
    for (PTYSession *s in [self sessions]) {
      [aSession setFocused:(s == activeSession)];
    }
    [self showOrHideInstantReplayBar];
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    [itad updateBroadcastMenuState];
    [[toolbelt_ commandHistoryView] updateCommands];
    [self updateTabColors];
}

- (void)showOrHideInstantReplayBar
{
    PTYSession* aSession = [self currentSession];
    if ([aSession liveSession]) {
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
        iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
        [itad updateBroadcastMenuState];
}

- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem
{

    [self tabView:tabView willInsertTabViewItem:tabViewItem atIndex:[tabView numberOfTabViewItems]];
    [self saveAffinitiesLater:[tabViewItem identifier]];
        iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
        [itad updateBroadcastMenuState];
}

- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)anIndex
{
    PTYTab* theTab = [tabViewItem identifier];
    [theTab setParentWindow:self];
    if ([theTab isTmuxTab]) {
      [theTab recompact];
      [theTab notifyWindowChanged];
      [[theTab tmuxController] setClientSize:[theTab tmuxSize]];
    }
    [self saveAffinitiesLater:[tabViewItem identifier]];
        iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
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

- (BOOL)tabView:(NSTabView*)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl
{
    return YES;
}

- (BOOL)tabView:(NSTabView*)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
{
    if ([aTabBarControl tabView] &&  // nil -> tab dropping outside any existing tabbar to create a new window
        [[aTabBarControl tabView] indexOfTabViewItem:tabViewItem] != NSNotFound) {
        // Dropping a tab in its own tabbar when it's the only tab causes the
        // window to disappear, so disallow that one case.
        return [[aTabBarControl tabView] numberOfTabViewItems] > 1;
    } else {
        return YES;
    }
}

- (void)tabView:(NSTabView*)aTabView willDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
{
    PTYTab *aTab = [tabViewItem identifier];
    for (PTYSession* aSession in [aTab sessions]) {
        [aSession setIgnoreResizeNotifications:YES];
    }
}

- (void)_updateTabObjectCounts
{
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYTab *theTab = [[TABVIEW tabViewItemAtIndex:i] identifier];
        [theTab setObjectCount:i+1];
    }
}

- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)aTabBarControl
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
    [TABVIEW display];

    for (PTYSession* aSession in [aTab sessions]) {
        [aSession setIgnoreResizeNotifications:NO];
    }
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
        NSRect tabFrame = [tabBarControl frame];
        int tabHeight = tabFrame.size.height;

        NSRect contentFrame, viewRect;
        contentFrame = viewRect = [textview frame];
        contentFrame.size.height += tabHeight;

        // Grabs whole tabview image.
        viewImage = [[[NSImage alloc] initWithSize:contentFrame.size] autorelease];
        NSImage *tabViewImage = [[[NSImage alloc] init] autorelease];

        [textview lockFocus];
        NSBitmapImageRep *tabviewRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:viewRect] autorelease];
        [tabViewImage addRepresentation:tabviewRep];
        [textview unlockFocus];

        [viewImage lockFocus];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_BottomTab) {
            viewRect.origin.y += tabHeight;
        }
        [tabViewImage compositeToPoint:viewRect.origin operation:NSCompositeSourceOver];
        [viewImage unlockFocus];

        // Draw over where the tab bar would usually be.
        [viewImage lockFocus];
        [[NSColor windowBackgroundColor] set];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            tabFrame.origin.y += viewRect.size.height;
        }
        NSRectFill(tabFrame);
        // Draw the background flipped, which is actually the right way up
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
        tabFrame.origin.y = -tabFrame.origin.y - tabFrame.size.height;
        PSMTabBarControl *control = (PSMTabBarControl *)[aTabView delegate];
        [(id <PSMTabStyle>)[control style] drawBackgroundInRect:tabFrame color:nil];
        [transform invert];
        [transform concat];

        [viewImage unlockFocus];

        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        } else {
            offset->height = viewRect.size.height + 22;
        }
        *styleMask = NSBorderlessWindowMask;
    } else {
        // grabs whole tabview image
        viewImage = [[tabViewItem identifier] image:YES];

        offset->width = [(id <PSMTabStyle>)[tabBarControl style] leftMarginForTabBarControl];
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            offset->height = 22;
        }
        else {
            offset->height = [viewImage size].height;
        }
        *styleMask = NSBorderlessWindowMask;
    }

    return viewImage;
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView
{
    PtyLog(@"%s(%d):-[PseudoTerminal tabViewDidChangeNumberOfTabViewItems]", __FILE__, __LINE__);
    for (PTYSession* session in [self allSessions]) {
        [session setIgnoreResizeNotifications:NO];
    }

    // check window size in case tabs have to be hidden or shown
    if (([TABVIEW numberOfTabViewItems] == 1) ||  // just decreased to 1 or increased above 1 and is hidden
        ([[PreferencePanel sharedInstance] hideTab] && ([TABVIEW numberOfTabViewItems] > 1 && [tabBarControl isHidden]))) {
        // Need to change the visibility status of the tab bar control.
        PtyLog(@"tabViewDidChangeNumberOfTabViewItems - calling fitWindowToTab");

        NSTabViewItem *tabViewItem = [[TABVIEW tabViewItems] objectAtIndex:0];
        PTYTab *firstTab = [tabViewItem identifier];

        if (wasDraggedFromAnotherWindow_) {
            // A tab was just dragged out of another window's tabbar into its own window.
            // When this happens, it loses its size. This is our only chance to resize it.
            // So we put it in a mode where it will resize to its "ideal" size instead of
            // its incorrect current size.
            [firstTab setReportIdealSizeAsCurrent:YES];
        }
        [self fitWindowToTabs];
        [self repositionWidgets];
        if (wasDraggedFromAnotherWindow_) {
            wasDraggedFromAnotherWindow_ = NO;
            [firstTab setReportIdealSizeAsCurrent:NO];
        }
    }

    [self updateTabColors];
    [self _updateTabObjectCounts];

    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
    [self invalidateRestorableState];
}

- (NSMenu *)tabView:(NSTabView *)tabView menuForTabViewItem:(NSTabViewItem *)tabViewItem
{
    NSMenuItem *item;
    NSMenu *rootMenu = [[[NSMenu alloc] init] autorelease];

    // Create a menu with a submenu to navigate between tabs if there are more than one
    if ([TABVIEW numberOfTabViewItems] > 1) {
        NSMenu *tabMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
        NSUInteger count = 1;
        for (NSTabViewItem *aTabViewItem in [TABVIEW tabViewItems]) {
            NSString *title = [NSString stringWithFormat:@"%@ #%ld", [aTabViewItem label], (unsigned long)count++];
            item = [[[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(selectTab:)
                                        keyEquivalent:@""] autorelease];
            [item setRepresentedObject:[aTabViewItem identifier]];
            [item setTarget:TABVIEW];
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
    
    if ([TABVIEW numberOfTabViewItems] > 1) {
        item = [[[NSMenuItem alloc] initWithTitle:@"Move to New Window"
                                           action:@selector(moveTabToNewWindowContextualMenuAction:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }

    if ([TABVIEW numberOfTabViewItems] > 1) {
        item = [[[NSMenuItem alloc] initWithTitle:@"Close Other Tabs"
                                           action:@selector(closeOtherTabs:)
                                    keyEquivalent:@""] autorelease];
        [item setRepresentedObject:tabViewItem];
        [rootMenu addItem:item];
    }
    
    if ([TABVIEW numberOfTabViewItems] > 1) {
        item = [[[NSMenuItem alloc] initWithTitle:@"Close Tabs to the Right"
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

- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point
{
    PTYTab *aTab = [tabViewItem identifier];
    if (aTab == nil) {
        return nil;
    }

    NSWindowController<iTermWindowController> * term =
        [self terminalDraggedFromAnotherWindowAtPoint:point];
    if ([term windowType] == WINDOW_TYPE_NORMAL &&
        [[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            [[term window] setFrameTopLeftPoint:point];
    }

    return [term tabBarControl];
}

- (NSArray *)allowedDraggedTypesForTabView:(NSTabView *)aTabView
{
    return [NSArray arrayWithObject:@"iTermDragPanePBType"];
}

- (NSDragOperation)tabView:(NSTabView *)aTabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)tabView
{
    return NSDragOperationMove;
}

- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id<NSDraggingInfo>)sender
{
    PTYSession *session = [[MovePaneController sharedInstance] session];
    BOOL tabSurvives = [[[session tab] sessions] count] > 1;
    if ([session isTmuxClient] && tabSurvives) {
        // Cause the "normal" drop handle to do nothing.
        [[MovePaneController sharedInstance] clearSession];
        // Tell the server to move the pane into its own window and sets
        // an affinity to the destination window.
        [[session tmuxController] breakOutWindowPane:[session tmuxPane]
                                          toTabAside:[self terminalGuid]];
        return nil;
    }
    [[MovePaneController sharedInstance] removeAndClearSession];
    PTYTab *theTab = [[[PTYTab alloc] initWithSession:session] autorelease];
    [theTab setActiveSession:session];
    [theTab setParentWindow:self];
    NSTabViewItem *tabViewItem = [[[NSTabViewItem alloc] initWithIdentifier:(id)theTab] autorelease];
    [theTab setTabViewItem:tabViewItem];
    [tabViewItem setLabel:[session name] ? [session name] : @""];

    [theTab numberOfSessionsDidChange];
    [self saveTmuxWindowOrigins];
    return tabViewItem;
}

- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender
{
    return YES;
}

- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)aTabViewItem
{
        PTYSession *session = [[aTabViewItem identifier] activeSession];
        return  [NSString stringWithFormat:@"Profile: %@\nCommand: %@",
                                [[session profile] objectForKey:KEY_NAME],
                                [session.shell command]];
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem
{
    [tabView selectTabViewItem:tabViewItem];
    [self editCurrentSession:self];
}

- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView
{
    Profile* prototype = [[ProfileModel sharedInstance] defaultBookmark];
    if (!prototype) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        prototype = aDict;
    }
    [self addNewSession:prototype];
}

- (void)setLabelColor:(NSColor *)color forTabViewItem:tabViewItem
{
    if ([[PreferencePanel sharedInstance] highlightTabLabels]) {
        [tabBarControl setLabelColor:color forTabViewItem:tabViewItem];
    } else {
        [tabBarControl setLabelColor:[NSColor blackColor] forTabViewItem:tabViewItem];
    }
}

- (void)updateTabColors
{
    for (PTYTab *aTab in [self tabs]) {
        NSTabViewItem *tabViewItem = [aTab tabViewItem];
        PTYSession *aSession = [aTab activeSession];
        NSColor *color = [aSession tabColor];
        [tabBarControl setTabColor:color forTabViewItem:tabViewItem];
        if ([TABVIEW selectedTabViewItem] == tabViewItem) {
            NSColor* newTabColor = [tabBarControl tabColorForTabViewItem:tabViewItem];
            if ([TABVIEW numberOfTabViewItems] == 1 &&
                [[PreferencePanel sharedInstance] hideTab] &&
                newTabColor) {
                [[self window] setBackgroundColor:newTabColor];
                [background_ setColor:newTabColor];
            } else {
                [[self window] setBackgroundColor:nil];
                [background_ setColor:normalBackgroundColor];
            }
        }
    }
}

- (PTYTabView *)tabView
{
    return TABVIEW;
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];

    switch (move) {
        case NSReturnTextMovement:
            [self sendCommand: nil];
            break;
        case NSTabTextMovement:
        {
            Profile* prototype = [[ProfileModel sharedInstance] defaultBookmark];
            if (!prototype) {
                NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
                [ITAddressBookMgr setDefaultsInBookmark:aDict];
                [aDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
                prototype = aDict;
            }
            [self addNewSession:prototype
                    withCommand:[commandField stringValue]
                  forObjectType:iTermTabObject];
            break;
        }
        default:
            break;
    }
}

- (BOOL)isInitialized
{
    return TABVIEW != nil;
}

- (void)fillPath:(NSBezierPath*)path
{
    if ([tabBarControl isHidden]) {
        [[NSColor windowBackgroundColor] set];
        [path fill];
        [[NSColor darkGrayColor] set];
        [path stroke];
    } else {
      [tabBarControl fillPath:path];
    }
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

- (void)instantReplayClose {
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
        p.y = [TABVIEW convertRect:NSMakeRect(0, 0, 0, 0) toView:nil].origin.y - size.height;
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

-(void)replaySession:(PTYSession *)oldSession
{
    // NSLog(@"Enter instant replay. Live session is %@", oldSession);
    NSTabViewItem* oldTabViewItem = [TABVIEW selectedTabViewItem];
    if (!oldTabViewItem) {
        return;
    }
    if ([[[oldSession screen] dvr] lastTimeStamp] == 0) {
        // Nothing recorded (not enough memory for one frame, perhaps?).
        return;
    }
    PTYSession *newSession;

    // Initialize a new session
    newSession = [[PTYSession alloc] init];
    // NSLog(@"New session for IR view is at %p", newSession);

    // set our preferences
    [newSession setProfile:[oldSession profile]];
    [[newSession screen] setMaxScrollbackLines:0];
    [self setupSession:newSession title:nil withSize:nil];
    [[newSession view] setViewId:[[oldSession view] viewId]];

    // Add this session to our term and make it current
    PTYTab* theTab = [oldTabViewItem identifier];
    [newSession setTab:theTab];
    [theTab setDvrInSession:newSession];
    [newSession release];
    if (![self inInstantReplay]) {
        [self showHideInstantReplay];
    }
}

- (void)showLiveSession:(PTYSession*)liveSession inPlaceOf:(PTYSession*)replaySession
{
    PTYTab* theTab = [replaySession tab];
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
    if (![[PreferencePanel sharedInstance] instantReplay]) {
        NSRunAlertPanel(@"Feature Disabled",
                        @"Instant Replay is disabled. Please turn it on in Preferences under the General tab.",
                        @"OK",
                        nil,
                        nil);
        return;
    }
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
    [pbHistoryView popWithDelegate:[self currentSession]];
}

- (IBAction)openCommandHistory:(id)sender
{
    if ([[CommandHistory sharedInstance] commandHistoryHasEverBeenUsed]) {
        [commandHistoryPopup popWithDelegate:[self currentSession]];
        [commandHistoryPopup loadCommands:[commandHistoryPopup commandsForHost:[[self currentSession] currentHost]
                                                                partialCommand:[[self currentSession] currentCommand]
                                                                        expand:YES]
                           partialCommand:[[self currentSession] currentCommand]];
    } else {
        [CommandHistory showInformationalMessage];
    }
}

- (void)hideAutoCommandHistory {
    [commandHistoryPopup close];
    _autoCommandHistorySessionId = -1;
}

- (void)hideAutoCommandHistoryForSession:(PTYSession *)session {
    if ([session sessionID] == _autoCommandHistorySessionId) {
        [self hideAutoCommandHistory];
    }
}

- (void)updateAutoCommandHistoryForPrefix:(NSString *)prefix inSession:(PTYSession *)session {
    if ([session sessionID] == _autoCommandHistorySessionId) {
        NSArray *commands = [commandHistoryPopup commandsForHost:[session currentHost]
                                                  partialCommand:prefix
                                                          expand:NO];
        if (![commands count]) {
            [commandHistoryPopup close];
            return;
        }
        if ([commands count] == 1) {
            CommandHistoryEntry *entry = commands[0];
            if ([entry.command isEqualToString:prefix]) {
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
    if ([[PreferencePanel sharedInstance] autoCommandHistory]) {
        // Use a delay so we don't get a flurry of windows appearing when restoring arrangements.
        [self performSelector:@selector(reallyShowAutoCommandHistoryForSession:)
                   withObject:session
                   afterDelay:0.2];
    }
}

- (void)reallyShowAutoCommandHistoryForSession:(PTYSession *)session {
    if ([self currentSession] == session && [[self window] isKeyWindow]) {
        _autoCommandHistorySessionId = [session sessionID];
        [commandHistoryPopup popWithDelegate:session];
        [self updateAutoCommandHistoryForPrefix:[session currentCommand] inSession:session];
    }
}

- (BOOL)autoCommandHistoryIsOpenForSession:(PTYSession *)session {
    return [[commandHistoryPopup window] isVisible] && _autoCommandHistorySessionId == [session sessionID];
}

- (IBAction)openAutocomplete:(id)sender
{
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
    if ([[self currentTab] hasMaximizedPane]) {
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

- (void)splitVertically:(BOOL)isVertical withBookmarkGuid:(NSString*)guid
{
    if ([[self currentTab] isTmuxTab]) {
        [[[self currentSession] tmuxController] splitWindowPane:[[self currentSession] tmuxPane] vertically:isVertical];
        return;
    }
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (bookmark) {
        [self splitVertically:isVertical withBookmark:bookmark targetSession:[self currentSession]];
    }
}

- (void)splitVertically:(BOOL)isVertical
                 before:(BOOL)before
          addingSession:(PTYSession*)newSession
          targetSession:(PTYSession*)targetSession
           performSetup:(BOOL)performSetup
{
    NSView *scrollView;
    NSColor *tabColor = [[[tabBarControl tabColorForTabViewItem:[[self currentTab] tabViewItem]] retain] autorelease];
    SessionView* sessionView = [[self currentTab] splitVertically:isVertical
                                                           before:before
                                                    targetSession:targetSession];
    [sessionView setSession:newSession];
    [newSession setTab:[self currentTab]];
    scrollView = [[[newSession view] subviews] objectAtIndex:0];
    [newSession setView:sessionView];
    NSSize size = [sessionView frame].size;
    if (performSetup) {
        [self setupSession:newSession title:nil withSize:&size];
        scrollView = [[[newSession view] subviews] objectAtIndex:0];
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
        [[self currentTab] setActiveSessionPreservingViewOrder:newSession];
    }
    [[self currentTab] recheckBlur];
    [[self currentTab] numberOfSessionsDidChange];
    [self setDimmingForSession:targetSession];
    [sessionView updateDim];
    newSession.tabColor = tabColor;
    [self updateTabColors];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
}

- (void)splitVertically:(BOOL)isVertical
           withBookmark:(Profile*)theBookmark
          targetSession:(PTYSession*)targetSession
{
    if ([targetSession isTmuxClient]) {
        [[targetSession tmuxController] splitWindowPane:[targetSession tmuxPane] vertically:isVertical];
        return;
    }
    PtyLog(@"--------- splitVertically -----------");
    if (![self canSplitPaneVertically:isVertical withBookmark:theBookmark]) {
        NSBeep();
        return;
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

    [self runCommandInSession:newSession inCwd:oldCWD forObjectType:iTermPaneObject];
}

- (Profile*)_bookmarkToSplit
{
    Profile* theBookmark = nil;

    // Get the bookmark this session was originally created with. But look it up from its GUID because
    // it might have changed since it was copied into originalProfile when the bookmark was
    // first created.
    Profile* originalBookmark = [[self currentSession] originalProfile];
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
    if (_autoCommandHistorySessionId != -1) {
        [self hideAutoCommandHistory];
    }
    [[toolbelt_ commandHistoryView] updateCommands];
}

- (void)fitWindowToTabs
{
    [self fitWindowToTabsExcludingTmuxTabs:NO];
}

- (void)fitWindowToTabsExcludingTmuxTabs:(BOOL)excludeTmux
{
    if (togglingFullScreen_) {
        return;
    }

    // Determine the size of the largest tab.
    NSSize maxTabSize = NSZeroSize;
    PtyLog(@"fitWindowToTabs.......");
    for (NSTabViewItem* item in [TABVIEW tabViewItems]) {
        PTYTab* tab = [item identifier];
        if ([tab isTmuxTab] && excludeTmux) {
            continue;
        }
        NSSize tabSize = [tab currentSize];
        PtyLog(@"The natural size of this tab is %lf", tabSize.height);
        if (tabSize.width > maxTabSize.width) {
            maxTabSize.width = tabSize.width;
        }
        if (tabSize.height > maxTabSize.height) {
            maxTabSize.height = tabSize.height;
        }

        tabSize = [tab minSize];
        PtyLog(@"The min size of this tab is %lf", tabSize.height);
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

- (BOOL)fitWindowToTabSize:(NSSize)tabSize
{
    PtyLog(@"fitWindowToTabSize %@", [NSValue valueWithSize:tabSize]);
    if ([self anyFullScreen]) {
        [self fitTabsToWindow];
        return NO;
    }
    // Set the window size to be large enough to encompass that tab plus its decorations.
    NSSize decorationSize = [self windowDecorationSize];
    NSSize winSize = tabSize;
    winSize.width += decorationSize.width;
    winSize.height += decorationSize.height;
    NSRect frame = [[self window] frame];

    if ([self isEdgeWindow]) {
        iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
        if ([itad showToolbelt]) {
            winSize.width += [self fullscreenToolbeltWidthForContentWidth:winSize.width] - 2.5;
        }
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

    // Ok, so some silly things are happening here. Issue 2096 reported that
    // when a session-initiated resize grows a window, the window's background
    // color becomes almost solid (it's actually a very gentle gradient between
    // two almost identical grays). For reasons that escape me, this happens if
    // the window's content view does not have a subview with an autoresizing
    // mask or autoresizing is off for the content view. I'm sure this isn't
    // the best fix, but it's all I could find: I turn off the autoresizing
    // mask for the TABVIEW (which I really don't want autoresized--it needs to
    // be done by hand in fitTabToWindow), and add a silly one pixel view
    // that lives just long enough to be resized in this function. I don't know
    // why it works but it does.
    NSView *bugFixView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)] autorelease];
    bugFixView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [[[self window] contentView] addSubview:bugFixView];
    NSUInteger savedMask = TABVIEW.autoresizingMask;
    TABVIEW.autoresizingMask = 0;

    // Set the frame for X-of-scren windows. The size doesn't change
    // for _PARTIAL window types.
    switch (windowType_) {
        case WINDOW_TYPE_BOTTOM:
            frame.origin.y = self.screen.visibleFrame.origin.y;
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
            frame.origin.y = self.screen.visibleFrame.origin.y;
            frame.size.height = self.screen.visibleFrame.size.height;

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
            frame.origin.y = self.screen.visibleFrame.origin.y;
            break;

        case WINDOW_TYPE_LEFT_PARTIAL:
            frame.origin.x = self.screen.visibleFrame.origin.x;
            break;
            
        case WINDOW_TYPE_RIGHT_PARTIAL:
            frame.origin.x = self.screen.visibleFrame.origin.x + self.screen.visibleFrame.size.width - frame.size.width;
            break;
    }
    
    BOOL didResize = NSEqualRects([[self window] frame], frame);
    [[self window] setFrame:frame display:YES];

    // Restore TABVIEW's autoresizingMask and remove the stupid bugFixView.
    TABVIEW.autoresizingMask = savedMask;
    [bugFixView removeFromSuperview];
    [[[self window] contentView] setAutoresizesSubviews:YES];

    PtyLog(@"fitWindowToTabs - refresh textview");
    for (PTYSession* session in [[self currentTab] sessions]) {
        [[session textview] setNeedsDisplay:YES];
    }
    PtyLog(@"fitWindowToTabs - update tab bar");
    [tabBarControl update];
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

- (IBAction)showHideNotes:(id)sender {
    [[self currentSession] showHideNotes];
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
    [[NSNotificationCenter defaultCenter] postNotificationName: @"iTermNumberOfSessionsDidChange" object: self userInfo: nil];
}

- (float)minWidth
{
    // Pick 400 as an absolute minimum just to be safe. This is rather arbitrary and hacky.
    float minWidth = 400;
    for (NSTabViewItem* tabViewItem in [TABVIEW tabViewItems]) {
        PTYTab* theTab = [tabViewItem identifier];
        minWidth = MAX(minWidth, [theTab minSize].width);
    }
    return minWidth;
}

- (BOOL)disableProgressIndicators
{
    return tempDisableProgressIndicators_;
}

- (void)appendTab:(PTYTab*)aTab
{
    [self insertTab:aTab atIndex:[TABVIEW numberOfTabViewItems]];
}

- (void)getSessionParameters:(NSMutableString *)command withName:(NSMutableString *)name
{
    NSRange r1, r2, currentRange;

    while (1) {
        currentRange = NSMakeRange(0,[command length]);
        r1 = [command rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r1.location == NSNotFound) {
            break;
        }
        currentRange.location = r1.location + 2;
        currentRange.length -= r1.location + 2;
        r2 = [command rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r2.location == NSNotFound) {
            break;
        }

        [parameterName setStringValue:[command substringWithRange:NSMakeRange(r1.location+2,
                                                                              r2.location - r1.location-2)]];
        [parameterValue setStringValue:@""];
        [NSApp beginSheet:parameterPanel
           modalForWindow:[self window]
            modalDelegate:self
           didEndSelector:nil
              contextInfo:nil];

        [NSApp runModalForWindow:parameterPanel];

        [NSApp endSheet:parameterPanel];
        [parameterPanel orderOut:self];

        [name replaceOccurrencesOfString:[command substringWithRange:NSMakeRange(r1.location,
                                                                                 r2.location - r1.location+2)]
                              withString:[parameterValue stringValue]
                                 options:NSLiteralSearch
                                   range:NSMakeRange(0, [name length])];
        [command replaceOccurrencesOfString:[command substringWithRange:NSMakeRange(r1.location,
                                                                                    r2.location - r1.location+2)]
                                 withString:[parameterValue stringValue]
                                    options:NSLiteralSearch
                                      range:NSMakeRange(0,[command length])];
    }

    while (1) {
        currentRange = NSMakeRange(0,[name length]);
        r1 = [name rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r1.location == NSNotFound) {
            break;
        }
        currentRange.location = r1.location + 2;
        currentRange.length -= r1.location + 2;
        r2 = [name rangeOfString:@"$$" options:NSLiteralSearch range:currentRange];
        if (r2.location == NSNotFound) {
            break;
        }

        [parameterName setStringValue:[name substringWithRange:NSMakeRange(r1.location+2,
                                                                           r2.location - r1.location-2)]];
        [parameterValue setStringValue:@""];
        [NSApp beginSheet:parameterPanel
           modalForWindow:[self window]
            modalDelegate:self
           didEndSelector:nil
              contextInfo:nil];

        [NSApp runModalForWindow:parameterPanel];

        [NSApp endSheet:parameterPanel];
        [parameterPanel orderOut:self];

        [name replaceOccurrencesOfString:[name substringWithRange:NSMakeRange(r1.location,
                                                                              r2.location - r1.location+2)]
                              withString:[parameterValue stringValue]
                                 options:NSLiteralSearch
                                   range:NSMakeRange(0,[name length])];
    }

}

- (NSArray*)tabs
{
    int n = [TABVIEW numberOfTabViewItems];
    NSMutableArray *tabs = [NSMutableArray arrayWithCapacity:n];
    for (int i = 0; i < n; ++i) {
        NSTabViewItem* theItem = [TABVIEW tabViewItemAtIndex:i];
        [tabs addObject:[theItem identifier]];
    }
    return tabs;
}

- (BOOL)isHotKeyWindow
{
    return isHotKeyWindow_;
}

- (void)setIsHotKeyWindow:(BOOL)value
{
    isHotKeyWindow_ = value;
}

- (BOOL)fullScreenTabControl
{
    return fullscreenTabs_;
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
        if (NSRunAlertPanel(@"Warning!",
                            @"Keyboard input will be sent to multiple sessions.",
                            @"OK",
                            @"Cancel",
                            nil) != NSAlertDefaultReturn) {
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
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
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
    [self _refreshTerminal:nil];
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    [itad updateBroadcastMenuState];
}

- (void)setSplitSelectionMode:(BOOL)mode excludingSession:(PTYSession *)session
{
    // Things would get really complicated if you could do this in IR, so just
    // close it.
    [self closeInstantReplay:nil];
    for (PTYSession *aSession in [self sessions]) {
        if (mode) {
            [aSession setSplitSelectionMode:(aSession != session) ? kSplitSelectionModeOn : kSplitSelectionModeCancel];
        } else {
            [aSession setSplitSelectionMode:kSplitSelectionModeOff];
        }
    }
}

- (IBAction)moveTabLeft:(id)sender
{
    NSInteger selectedIndex = [TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]];
    NSInteger destinationIndex = selectedIndex - 1;
    if (destinationIndex < 0) {
        destinationIndex = [TABVIEW numberOfTabViewItems] - 1;
    }
    if (selectedIndex == destinationIndex) {
        return;
    }
    [tabBarControl moveTabAtIndex:selectedIndex toIndex:destinationIndex];
    [self _updateTabObjectCounts];
}

- (IBAction)moveTabRight:(id)sender
{
    NSInteger selectedIndex = [TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]];
    NSInteger destinationIndex = (selectedIndex + 1) % [TABVIEW numberOfTabViewItems];
    if (selectedIndex == destinationIndex) {
        return;
    }
    [tabBarControl moveTabAtIndex:selectedIndex toIndex:destinationIndex];
    [self _updateTabObjectCounts];
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
    BOOL canDim = [[PreferencePanel sharedInstance] dimInactiveSplitPanes];
    if (!canDim) {
        [[aSession view] setDimmed:NO];
    } else if (aSession == [[aSession tab] activeSession]) {
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
    for (PTYSession *aSession in [self sessions]) {
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

- (void)_refreshTitle:(NSNotification*)aNotification
{
    // This is if displaying of window number was toggled in prefs.
    [self setWindowTitle];
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

- (void)_refreshTerminal:(NSNotification *)aNotification
{
    PtyLog(@"_refreshTerminal - calling fitWindowToTabs");
    
    // If hiding of menu bar changed.
    if ([self fullScreen] && ![self lionFullScreen]) {
        if ([[self window] isKeyWindow]) {
            // In practice, this never happens because the prefs panel is
            // always key when this notification is posted.
            if ([[PreferencePanel sharedInstance] hideMenuBarInFullscreen]) {
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
    }

    // Assign counts to each session. This causes tabs to show their tab number,
    // called an objectCount. When the "compact tab" pref is toggled, this makes
    // formerly countless tabs show their counts.
    BOOL needResize = NO;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        PTYTab *aTab = [[TABVIEW tabViewItemAtIndex:i] identifier];
        if ([aTab updatePaneTitles]) {
            needResize = YES;
        }
        [aTab setObjectCount:i+1];

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
}

- (void)hideMenuBar
{
    NSScreen* menubarScreen = nil;
    NSScreen* currentScreen = nil;

    if ([[NSScreen screens] count] == 0) {
        return;
    }

    menubarScreen = [[NSScreen screens] objectAtIndex:0];
    currentScreen = [[self window] deepestScreen];
    if (!currentScreen) {
        currentScreen = [NSScreen mainScreen];
    }

    // If screens have separate spaces (only applicable in Mavericks and later) then all screens have a menu bar.
    if (currentScreen == menubarScreen || (IsMavericksOrLater() && [NSScreen futureScreensHaveSeparateSpaces])) {
        int flags = NSApplicationPresentationAutoHideDock;
        if ([[PreferencePanel sharedInstance] hideMenuBarInFullscreen]) {
            flags |= NSApplicationPresentationAutoHideMenuBar;
        }
        NSApplicationPresentationOptions presentationOptions =
            [[NSApplication sharedApplication] presentationOptions];
        presentationOptions |= flags;
        [[NSApplication sharedApplication] setPresentationOptions:presentationOptions];

    }
}

- (void)showMenuBarHideDock
{
    NSApplicationPresentationOptions presentationOptions =
        [[NSApplication sharedApplication] presentationOptions];
    presentationOptions |= NSApplicationPresentationAutoHideDock;
    presentationOptions &= ~NSApplicationPresentationAutoHideMenuBar;
    [[NSApplication sharedApplication] setPresentationOptions:presentationOptions];
}

- (void)showMenuBar
{
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

- (BOOL)_haveLeftBorder
{
    if (![[PreferencePanel sharedInstance] showWindowBorder]) {
        return NO;
    } else if ([self anyFullScreen] ||
               windowType_ == WINDOW_TYPE_LEFT) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)_haveBottomBorder
{
    BOOL tabBarVisible = [self tabBarShouldBeVisible];
    BOOL topTabBar = ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab);
    if (![[PreferencePanel sharedInstance] showWindowBorder]) {
        return NO;
    } else if ([self anyFullScreen] ||
               windowType_ == WINDOW_TYPE_BOTTOM) {
        return NO;
    } else if (topTabBar) {
        // Nothing on the bottom, so need a border.
        return YES;
    } else if (!tabBarVisible) {
        // Invisible bottom tab bar
        return YES;
    } else {
        // Visible bottom tab bar
        return NO;
    }
}

- (BOOL)_haveTopBorder
{
    BOOL tabBarVisible = [self tabBarShouldBeVisible];
    BOOL topTabBar = ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab);
    BOOL visibleTopTabBar = (tabBarVisible && topTabBar);
    return ([[PreferencePanel sharedInstance] showWindowBorder] &&
            !visibleTopTabBar
            && windowType_ == WINDOW_TYPE_BOTTOM);
}

- (BOOL)_haveRightBorder
{
    if (![[PreferencePanel sharedInstance] showWindowBorder]) {
        return NO;
    } else if ([self anyFullScreen] ||
               windowType_ == WINDOW_TYPE_RIGHT ) {
        return NO;
    } else if (![[[self currentSession] scrollview] isLegacyScroller] ||
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

    if ([self tabBarShouldBeVisibleWithAdditionalTabs:tabViewItemsBeingAdded]) {
        contentSize.height += [tabBarControl frame].size.height;
    }

    // Add 1px border
    if ([self _haveLeftBorder]) {
        ++contentSize.width;
    }
    if ([self _haveRightBorder]) {
        ++contentSize.width;
    }
    if ([self _haveBottomBorder]) {
        ++contentSize.height;
    }
    if ([self _haveTopBorder]) {
        ++contentSize.height;
    }
    if (_divisionView) {
        ++contentSize.height;
    }
    return [[self window] frameRectForContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)].size;
}

- (void)_setDisableProgressIndicators:(BOOL)value
{
    tempDisableProgressIndicators_ = value;
    for (NSTabViewItem* anItem in [TABVIEW tabViewItems]) {
        PTYTab* theTab = [anItem identifier];
        [theTab setIsProcessing:[theTab realIsProcessing]];
    }
}

- (void)showFullScreenTabControl
{
    temporarilyShowingTabs_ = YES;
    if (!fullscreenTabs_) {
        [self toggleFullScreenTabBar];
    }
}

- (void)hideFullScreenTabControl
{
    if (temporarilyShowingTabs_ && fullscreenTabs_) {
        [self toggleFullScreenTabBar];
    }
    temporarilyShowingTabs_ = NO;
}

- (void)flagsChanged:(NSEvent *)theEvent
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermFlagsChanged"
                                                        object:theEvent
                                                      userInfo:nil];

    [TABVIEW processMRUEvent:theEvent];

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

    if (![self anyFullScreen]) {
        return;
    }
    if (!temporarilyShowingTabs_ && fullscreenTabs_) {
        // Being shown non-temporarily
        return;
    }
    if ((modifierFlags & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask &&  // you pressed exactly cmd
        ([tabBarBackground isHidden] || [tabBarBackground alphaValue] == 0) &&  // the tab bar is not visible
        fullScreenTabviewTimer_ == nil) {  // not in the middle of doing this already
        fullScreenTabviewTimer_ = [[NSTimer scheduledTimerWithTimeInterval:[[PreferencePanel sharedInstance] fsTabDelay]
                                                                    target:self
                                                                  selector:@selector(cmdHeld:)
                                                                  userInfo:nil
                                                                   repeats:NO] retain];
    } else if ((modifierFlags & NSDeviceIndependentModifierFlagsMask) != NSCommandKeyMask &&
               fullScreenTabviewTimer_ != nil) {
        [fullScreenTabviewTimer_ invalidate];
        fullScreenTabviewTimer_ = nil;
    }

    // This hides the tabbar if you press any other key while it's already showing.
    // This breaks certain popular ways of switching tabs like cmd-shift-arrow or
    // cmd-shift-[ or ].
    // I can't remember why I added this. Let's take it out and if nobody complains
    // remove it for good. gn 2/12/2011.
    // if ((modifierFlags & NSDeviceIndependentModifierFlagsMask) != NSCommandKeyMask) {
    if (temporarilyShowingTabs_ && !(modifierFlags & NSCommandKeyMask)) {
        [self hideFullScreenTabControl];
        temporarilyShowingTabs_ = NO;
    }
}

- (void)cmdHeld:(id)sender
{
    [fullScreenTabviewTimer_ release];
    fullScreenTabviewTimer_ = nil;
    // Don't show the tabbar if you're holding cmd while doing find cursor
    if ([self anyFullScreen] && ![[[self currentSession] textview] isFindingCursor]) {
        [self showFullScreenTabControl];
    }
}

// Change position of window widgets.
- (void)repositionWidgets
{
    PtyLog(@"repositionWidgets");

    BOOL hasScrollbar = [self scrollbarShouldBeVisible];
    NSWindow *thisWindow = [self window];
    [thisWindow setShowsResizeIndicator:hasScrollbar];
    if (![self tabBarShouldBeVisible]) {
        // The tabBarControl should not be visible.
        [tabBarControl setHidden:YES];
        NSRect aRect;
        aRect.origin.x = [self _haveLeftBorder] ? 1 : 0;
        aRect.origin.y = [self _haveBottomBorder] ? 1 : 0;
        aRect.size = [[thisWindow contentView] frame].size;
        aRect.size.height -= aRect.origin.y;
        if ([self _haveTopBorder] || _divisionView) {
            aRect.size.height -= 1;
        }
        aRect.size.width = [self tabviewWidth];
        PtyLog(@"repositionWidgets - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
        [TABVIEW setFrame:aRect];
        [self updateDivisionView];
    } else {
        // The tabBar control is visible.
        PtyLog(@"repositionWidgets - tabs are visible. Adjusting window size...");
        [tabBarControl setHidden:NO];
        [tabBarControl setTabLocation:[[PreferencePanel sharedInstance] tabViewType]];
        NSRect aRect;
        if ([[PreferencePanel sharedInstance] tabViewType] == PSMTab_TopTab) {
            // Place tabs at the top.
            // Add 1px border
            aRect.origin.x = [self _haveLeftBorder] ? 1 : 0;
            aRect.origin.y = [self _haveBottomBorder] ? 1 : 0;
            aRect.size = [[thisWindow contentView] frame].size;
            aRect.size.height -= aRect.origin.y;
            aRect.size.height -= [tabBarControl frame].size.height;
            if ([self _haveTopBorder]) {
                aRect.size.height -= 1;
            }
            aRect.size.width = [self tabviewWidth];
            PtyLog(@"repositionWidgets - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
            [TABVIEW setFrame:aRect];
            [self updateDivisionView];
            aRect.origin.y += aRect.size.height;
            aRect.size.height = [tabBarControl frame].size.height;
            [tabBarControl setFrame:aRect];
            [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
        } else {
            PtyLog(@"repositionWidgets - putting tabs at bottom");
            // setup aRect to make room for the tabs at the bottom.
            aRect.origin.x = [self _haveLeftBorder] ? 1 : 0;
            aRect.origin.y = [self _haveBottomBorder] ? 1 : 0;
            aRect.size = [[thisWindow contentView] frame].size;
            aRect.size.height = [tabBarControl frame].size.height;
            aRect.size.width = [self tabviewWidth];
            [tabBarControl setFrame:aRect];
            [tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
            aRect.origin.y += [tabBarControl frame].size.height;
            aRect.size.height = [[thisWindow contentView] frame].size.height - aRect.origin.y;
            if ([self _haveTopBorder]) {
                aRect.size.height -= 1;
            }
            PtyLog(@"repositionWidgets - Set tab view size to %fx%f", aRect.size.width, aRect.size.height);
            [TABVIEW setFrame:aRect];
            [self updateDivisionView];
        }
    }

    if ([self isEdgeWindow] || (!exitingLionFullscreen_ && [self anyFullScreen])) {
        iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
        if ([itad showToolbelt]) {
            [toolbelt_ setFrame:[self fullscreenToolbeltFrame]];
        }
    }

    // Update the tab style.
    [self setTabBarStyle];

    [tabBarControl setDisableTabClose:[[PreferencePanel sharedInstance] hideTabCloseButton]];
    if ([[PreferencePanel sharedInstance] hideTabCloseButton] &&
        [[PreferencePanel sharedInstance] hideTabNumber]) {
        [tabBarControl setCellMinWidth:[[PreferencePanel sharedInstance] minCompactTabWidth]];
    } else {
        [tabBarControl setCellMinWidth:[[PreferencePanel sharedInstance] minTabWidth]];
    }
    [tabBarControl setSizeCellsToFit:[[PreferencePanel sharedInstance] useUnevenTabs]];
    [tabBarControl setCellOptimumWidth:[[PreferencePanel sharedInstance] optimumTabWidth]];

    PtyLog(@"repositionWidgets - refresh textviews in this tab");
    for (PTYSession* session in [[self currentTab] sessions]) {
        [[session textview] setNeedsDisplay:YES];
    }

    PtyLog(@"repositionWidgets - update tab bar");
    [tabBarControl update];
    PtyLog(@"repositionWidgets - return.");
}

// Returns the width of characters in pixels in the session with the widest
// characters. Fills in *numChars with the number of columns in that session.
- (float)maxCharWidth:(int*)numChars
{
    float max=0;
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
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
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
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
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
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
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        for (PTYSession* session in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
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

// Set the session's address book and initialize its screen and name. Sets the
// window title to the session's name. If size is not nil then the session is initialized to fit
// a view of that size; otherwise the size is derived from the existing window if there is already
// an open tab, or its bookmark's preference if it's the first session in the window.
- (void)setupSession:(PTYSession *)aSession
               title:(NSString *)title
            withSize:(NSSize*)size
{
    NSDictionary *tempPrefs;

    PtyLog(@"%s(%d):-[PseudoTerminal setupSession]",
          __FILE__, __LINE__);

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

    if (size == nil && [TABVIEW numberOfTabViewItems] != 0) {
        NSSize contentSize = [[[self currentSession] scrollview] documentVisibleRect].size;
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

        if (title) {
            [aSession setName:title];
            [aSession setDefaultName:title];
            [self setWindowTitle];
        }
    }
}

- (void)moveSessionToWindow:(id)sender
{
    [[MovePaneController sharedInstance] moveSessionToNewWindow:[self currentSession]
                                                        atPoint:[[self window] convertBaseToScreen:NSMakePoint(10, -10)]];

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
// Set the session to a size that fits on the screen.
// Push a size change to a session (and on to its shell) but clamps the size to
// reasonable minimum and maximum limits.
- (void)safelySetSessionSize:(PTYSession*)aSession rows:(int)rows columns:(int)columns
{
    if ([aSession exited]) {
        return;
    }
    PtyLog(@"safelySetSessionSize");
    BOOL hasScrollbar = [self scrollbarShouldBeVisible];
    if (windowType_ == WINDOW_TYPE_NORMAL) {
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
        NSSize currentSize = [TABVIEW frame].size;
        if ([TABVIEW numberOfTabViewItems] == 0) {
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
        [aSession setWidth:width height:height];
        [[aSession scrollview] setHasVerticalScroller:hasScrollbar];
        [[aSession scrollview] setLineScroll:[[aSession textview] lineHeight]];
        [[aSession scrollview] setPageScroll:2*[[aSession textview] lineHeight]];
        if ([aSession backgroundImagePath]) {
            [aSession setBackgroundImagePath:[aSession backgroundImagePath]];
        }
    }
}

// Adjust the tab's size for a new window size.
- (void)fitTabToWindow:(PTYTab*)aTab
{
    NSSize size = [TABVIEW contentRect].size;
    PtyLog(@"fitTabToWindow calling setSize for content size of %@", [NSValue valueWithSize:size]);
    [aTab setSize:size];
}

// Add a tab to the tabview.
- (void)insertTab:(PTYTab*)aTab atIndex:(int)anIndex
{
    PtyLog(@"insertTab:atIndex:%d", anIndex);
    assert(aTab);
    if ([TABVIEW indexOfTabViewItemWithIdentifier:aTab] == NSNotFound) {
        for (PTYSession* aSession in [aTab sessions]) {
            [aSession setIgnoreResizeNotifications:YES];
        }
        NSTabViewItem* aTabViewItem = [[NSTabViewItem alloc] initWithIdentifier:(id)aTab];
        [aTabViewItem setLabel:@""];
        assert(aTabViewItem);
        [aTab setTabViewItem:aTabViewItem];
        PtyLog(@"insertTab:atIndex - calling [TABVIEW insertTabViewItem:atIndex]");
        [TABVIEW insertTabViewItem:aTabViewItem atIndex:anIndex];
        [aTabViewItem release];
        [TABVIEW selectTabViewItemAtIndex:anIndex];
        if ([self windowInited] && !_fullScreen) {
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
        PTYTab* aTab = [[PTYTab alloc] initWithSession:aSession];
        [aSession setIgnoreResizeNotifications:YES];
        if ([self numberOfTabs] == 0) {
            [aTab setReportIdealSizeAsCurrent:YES];
        }
        [self insertTab:aTab atIndex:anIndex];
        [aTab setReportIdealSizeAsCurrent:NO];
        [aTab release];
    }
}

// Seamlessly change the session in a tab.
- (void)replaceSession:(PTYSession *)aSession atIndex:(int)anIndex
{
    PtyLog(@"-[PseudoTerminal insertSession: %p atIndex: %d]", aSession, anIndex);

    if (aSession == nil) {
        return;
    }

    assert([TABVIEW indexOfTabViewItemWithIdentifier:aSession] == NSNotFound);
    NSTabViewItem *aTabViewItem = [TABVIEW tabViewItemAtIndex:anIndex];
    assert(aTabViewItem);

    // Tell the session at this index that it is no longer associated with this tab.
    PTYTab* oldTab = [aTabViewItem identifier];
    [oldTab setTabViewItem:nil];  // TODO: This looks like a bug if there are multiple sessions in one tab

    // Replace the session for the tab view item.
    PTYTab* newTab = [[[PTYTab alloc] initWithSession:aSession] autorelease];
    [tabBarControl changeIdentifier:newTab atIndex:anIndex];
    [newTab setTabViewItem:aTabViewItem];

    // Set other tabviewitem attributes to match the new session.
    [TABVIEW selectTabViewItemAtIndex:anIndex];

    // Bring the window to the fore.
    [self fitWindowToTabs];
    if ([self windowInited] && !_fullScreen) {
        [[self window] makeKeyAndOrderFront:self];
    }
    [[iTermController sharedInstance] setCurrentTerminal:self];
    [newTab numberOfSessionsDidChange];
}

- (CGFloat)fullscreenToolbeltWidth
{
    return MIN(250, self.window.frame.size.width / 5);
}

- (CGFloat)fullscreenToolbeltWidthForContentWidth:(CGFloat)contentWidth {
    // Returns the toolbelt frame for a window whose frame has a content view of size frameWidth.
    // windowWidth = contentWidth + toolbeltWidth
    // toolbeltWidth = MIN(250, windowWidth / 5)
    // windowWidth = contentWidth + MIN(250, windowWidth / 5)
    // windowWidth - MIN(250, windowWidth / 5) = contentWidth
    // two cases:
    // 1. windowWidth - windowWidth / 5 = contentWidth
    //    0.8 * windowWidth = contentWidth
    //    windowWidth = contentWidth / 0.8
    //    toolbeltWidth = contentWidth / 4
    // 2. windowWidth - 250 = contentWidth
    //    toolbeltWidth = 250
    return MIN(250, contentWidth / 4);
}

- (NSString *)currentSessionName
{
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
                              (long)[TABVIEW indexOfTabViewItem:[TABVIEW selectedTabViewItem]]];

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
- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
           inSession:(PTYSession*)theSession
{
    [theSession startProgram:program
                   arguments:prog_argv
                 environment:prog_env
                      isUTF8:isUTF8];

    if ([[[self window] title] compare:@"Window"] == NSOrderedSame) {
        [self setWindowTitle];
    }
}

// Send a reset to the current session's terminal.
- (void)reset:(id)sender
{
    [[[self currentSession] terminal] resetPreservingPrompt:YES];
    [[self currentSession] updateDisplay];
}

- (IBAction)resetCharset:(id)sender
{
    [[[self currentSession] terminal] resetCharset];
}

// Clear the buffer of the current session.
- (void)clearBuffer:(id)sender
{
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
- (IBAction)logStop:(id)sender
{
    if ([[self currentSession] logging]) {
        [[self currentSession] logStop];
    }
    // send a notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermSessionBecameKey"
                                                        object:[self currentSession]];
}

- (IBAction)wrapToggleToolbarShown:(id)sender {
    [[self ptyWindow] toggleToolbarShown:sender];
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
    } else if ([item action] == @selector(wrapToggleToolbarShown:)) {
        result = ![iTermSettingsModel disableToolbar] && (self.window.styleMask & NSTitledWindowMask);
    } else if ([item action] == @selector(moveSessionToWindow:)) {
        result = ([[self sessions] count] > 1);
    } else if ([item action] == @selector(openSplitHorizontallySheet:) ||
        [item action] == @selector(openSplitVerticallySheet:)) {
        result = ![[self currentTab] isTmuxTab];
    } else if ([item action] == @selector(jumpToSavedScrollPosition:)) {
        result = [self hasSavedScrollPosition];
    } else if ([item action] == @selector(moveTabLeft:)) {
        result = [TABVIEW numberOfTabViewItems] > 1;
    } else if ([item action] == @selector(moveTabRight:)) {
        result = [TABVIEW numberOfTabViewItems] > 1;
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
        result = [[self currentSession] canInstantReplayPrev];
    } else if ([item action] == @selector(irNext:)) {
        result = [[self currentSession] canInstantReplayNext];
    } else if ([item action] == @selector(toggleShowTimestamps:)) {
        result = ([self currentSession] != nil);
    } else if ([item action] == @selector(toggleAutoCommandHistory:)) {
        result = [[CommandHistory sharedInstance] commandHistoryHasEverBeenUsed];
        if (result) {
            if ([item respondsToSelector:@selector(setState:)]) {
                [item setState:[[PreferencePanel sharedInstance] autoCommandHistory] ? NSOnState : NSOffState];
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
    } else if ([item action] == @selector(resetCharset:)) {
        result = ![[[self currentSession] screen] allCharacterSetPropertiesHaveDefaultValues];
    } else if ([item action] == @selector(openCommandHistory:)) {
        if (![[CommandHistory sharedInstance] commandHistoryHasEverBeenUsed]) {
            return YES;
        }
        return [[CommandHistory sharedInstance] haveCommandsForHost:[[self currentSession] currentHost]];
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
    }
    return result;
}

- (IBAction)toggleShowTimestamps:(id)sender
{
    [[self currentSession] toggleShowTimestamps];
}

- (IBAction)toggleAutoCommandHistory:(id)sender
{
    [[PreferencePanel sharedInstance] setAutoCommandHistory:![[PreferencePanel sharedInstance] autoCommandHistory]];
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
    for (int i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
        [self fitTabToWindow:[[TABVIEW tabViewItemAtIndex:i] identifier]];
    }
    PtyLog(@"fitTabsToWindow returns");
}

// Show a dialog confirming close. Returns YES if the window should be closed.
- (BOOL)showCloseWindow
{
    return ([self confirmCloseForSessions:[self sessions]
                               identifier:@"This window"
                              genericName:[NSString stringWithFormat:@"Window #%d", number_+1]]);
}

- (PSMTabBarControl*)tabBarControl
{
    return tabBarControl;
}

// Called when the "Close tab" contextual menu item is clicked.
- (void)closeTabContextualMenuAction:(id)sender
{
    [self closeTab:(id)[[sender representedObject] identifier]];
}

- (IBAction)duplicateTab:(id)sender
{
    PTYTab *theTab = (PTYTab *)[[sender representedObject] identifier];
    if (!theTab) {
        theTab = [self currentTab];
    }
    [self appendTab:[[theTab copy] autorelease]];
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
    [TABVIEW removeTabViewItem:aTabViewItem];

    // add the session to the new terminal
    [term insertTab:aTab atIndex:0];
    PtyLog(@"moveTabToNewWindowContextMenuAction - call fitWindowToTabs");
    [term fitWindowToTabs];

    // release the tabViewItem
    [aTabViewItem release];
}

// Change the tab color to the selected menu color
- (void)changeTabColorToMenuAction:(id)sender
{
    ColorsMenuItemView *menuItem = (ColorsMenuItemView *)[sender view];
    NSColor *color = menuItem.color;
    for (PTYSession *aSession in [[self currentTab] sessions]) {
        [aSession setTabColor:color];
    }
    [self updateTabColors];
}

// Close this window.
- (IBAction)closeWindow:(id)sender
{
    [[self window] performClose:sender];
}

// Sends text to the current session. Also interprets URLs and opens them.
- (IBAction)sendCommand:(id)sender
{
    NSString *command = [commandField stringValue];

    if (command == nil ||
        [[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@""]) {
        return;
    }

    NSRange range = [command rangeOfString:@"://"];
    if (range.location != NSNotFound) {
        range = [[command substringToIndex:range.location] rangeOfString:@" "];
        if (range.location == NSNotFound) {
            NSURL *url = [NSURL URLWithString: command];
            NSString *urlType = [url scheme];
            id bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:urlType];

            if (bm) {
                PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
                [[iTermController sharedInstance] launchBookmark:bm
                                                      inTerminal:term
                                                         withURL:command
                                                        isHotkey:NO
                                                         makeKey:NO];
            } else {
                [[NSWorkspace sharedWorkspace] openURL:url];
            }
            return;
        }
    }
    [[self currentSession] sendCommand: command];
    [commandField setStringValue:@""];
}

- (void)reloadBookmarks
{
    for (PTYSession* session in [self allSessions]) {
        Profile *oldBookmark = [session profile];
        NSString* oldName = [oldBookmark objectForKey:KEY_NAME];
        [oldName retain];
        NSString* guid = [oldBookmark objectForKey:KEY_GUID];
        if ([session reloadProfile]) {
            [[session tab] recheckBlur];
            NSDictionary *profile = [session profile];
            if (![[profile objectForKey:KEY_NAME] isEqualToString:oldName]) {
                // Set name, which overrides any session-set icon name.
                [session setName:[profile objectForKey:KEY_NAME]];
                // set default name, which will appear as a prefix if the session changes the name.
                [session setDefaultName:[profile objectForKey:KEY_NAME]];
            }
            if ([session isDivorced] &&
                [[[PreferencePanel sessionsInstance] currentProfileGuid] isEqualToString:guid] &&
                [[[PreferencePanel sessionsInstance] window] isVisible]) {
                [[PreferencePanel sessionsInstance] updateBookmarkFields:profile];
            }
        }
        [oldName release];
    }
}

// Called when the parameter panel should close.
- (IBAction)parameterPanelEnd:(id)sender
{
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
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:[TABVIEW numberOfTabViewItems]];
    for (NSTabViewItem* item in [TABVIEW tabViewItems]) {
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
- (void)runCommandInSession:(PTYSession*)aSession
                      inCwd:(NSString*)oldCWD
              forObjectType:(iTermObjectType)objectType
{
    if ([aSession screen]) {
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;
        // Grab the addressbook command
        Profile* addressbookEntry = [aSession profile];
        cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry
                                                                           forObjectType:objectType]] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey:KEY_NAME]] autorelease];
        // Get session parameters
        [self getSessionParameters:cmd withName:name];

        [cmd breakDownCommandToPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry
                                           forObjectType:objectType];
        if ([pwd length] == 0) {
            if (oldCWD) {
                pwd = oldCWD;
            } else {
                pwd = NSHomeDirectory();
            }
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);
        [self setName:name forSession:aSession];
        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 inSession:aSession];
    }
}

- (void)_loadFindStringFromSharedPasteboard
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                        object:nil
                                                      userInfo:nil];
}

- (void)_updateToolbeltParentage
{
    iTermApplicationDelegate *itad = (iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate];
    if ([self anyFullScreen] || [self isEdgeWindow]) {
        [toolbelt_ retain];
        [toolbelt_ removeFromSuperview];
        [toolbelt_ setFrame:[self fullscreenToolbeltFrame]];
        [toolbelt_ setHidden:![itad showToolbelt]];
        toolbelt_.topMargin = kToolbeltMargin;
        [[[self window] contentView] addSubview:toolbelt_
                                     positioned:NSWindowBelow
                                     relativeTo:TABVIEW];
        [toolbelt_ release];
        [self repositionWidgets];
        [drawer_ close];
    } else {
        if (!drawer_) {
            drawer_ = [[NSDrawer alloc] initWithContentSize:NSMakeSize(200, self.window.frame.size.height)
                                              preferredEdge:CGRectMaxXEdge];
            [drawer_ setParentWindow:self.window];
        }
        NSSize contentSize = [drawer_ contentSize];
        NSRect toolbeltFrame = NSMakeRect(0, 0, contentSize.width, contentSize.height);
        toolbelt_.topMargin = 0;
        [toolbelt_ retain];
        [toolbelt_ removeFromSuperview];
        [toolbelt_ setFrame:toolbeltFrame];
        [drawer_ setContentView:toolbelt_];
        [toolbelt_ release];
        [toolbelt_ setHidden:NO];
        if ([itad showToolbelt]) {
            [drawer_ open];
        }
    }
    [toolbelt_ relayoutAllTools];
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}

- (void)incrementBadge
{
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
    ++count;
    [dockTile setBadgeLabel:[NSString stringWithFormat:@"%d", count]];
    [self.window.dockTile setShowsApplicationBadge:YES];
}

- (void)sessionHostDidChange:(PTYSession *)session to:(VT100RemoteHost *)host {
    if ([self currentSession] == session) {
      [[toolbelt_ commandHistoryView] updateCommands];
    }
}

#pragma mark - KeyValueCoding

- (int)columns
{
    return [[self currentSession] columns];
}

- (void)setColumns:(int)columns
{
    if (![self currentSession]) {
        nextSessionColumns_ = columns;
    } else {
        [self sessionInitiatedResize:[self currentSession]
                               width:columns
                              height:[[self currentSession] rows]];
    }
}

- (int)rows
{
    return [[self currentSession] rows];
}

- (void)setRows:(int)rows
{
    if (![self currentSession]) {
        nextSessionRows_ = rows;
    } else {
        [self sessionInitiatedResize:[self currentSession]
                              width:[[self currentSession] columns]
                              height:rows];
    }
}

- (id)addNewSession:(NSDictionary *)addressbookEntry
{
    assert(addressbookEntry);
    PTYSession *aSession;
    NSString *oldCWD = nil;

    // Get active session's directory
    PTYSession* cwdSession = [[[iTermController sharedInstance] currentTerminal] currentSession];
    if (cwdSession) {
        oldCWD = [[cwdSession shell] getWorkingDirectory];
    }

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession screen] setUnlimitedScrollback:[[addressbookEntry objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setProfile:addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession:aSession];
    if ([aSession screen]) {
        iTermObjectType objectType;
        if ([TABVIEW numberOfTabViewItems] == 1) {
            objectType = iTermWindowObject;
        } else {
            objectType = iTermTabObject;
        }
        [aSession runCommandWithOldCwd:oldCWD forObjectType:objectType];
        if ([[[self window] title] compare:@"Window"] == NSOrderedSame) {
            [self setWindowTitle];
        }
    }

    // On Lion, a window that can join all spaces can't go fullscreen.
    if ([self numberOfTabs] == 1 &&
        [addressbookEntry objectForKey:KEY_SPACE] &&
        [[addressbookEntry objectForKey:KEY_SPACE] intValue] == -1) {
        [[self window] setCollectionBehavior:[[self window] collectionBehavior] | NSWindowCollectionBehaviorCanJoinAllSpaces];
    }

    [aSession release];
    return aSession;
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)state
{
    [self loadArrangement:[state decodeObjectForKey:@"ptyarrangement"]];
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

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)state
{
    if (doNotSetRestorableState_) {
        // The window has been destroyed beyond recognition at this point and
        // there is nothing to save.
        return;
    }
    if ([self isHotKeyWindow] || [self allTabsAreTmuxTabs]) {
        // Don't save and restore hotkey windows or tmux windows.
        [[self ptyWindow] setRestoreState:nil];
        return;
    }
    if (wellFormed_) {
        [lastArrangement_ release];
        lastArrangement_ = [[self arrangementExcludingTmuxTabs:YES] retain];
    }
    // For whatever reason, setting the value in the coder here doesn't work but
    // doing it in PTYWindow immediately after this method's caller returns does
    // work.
    [[self ptyWindow] setRestoreState:lastArrangement_];
}

- (NSApplicationPresentationOptions)window:(NSWindow *)window
      willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
    return proposedOptions | NSApplicationPresentationAutoHideToolbar;
}


// accessors for to-many relationships:
// (See NSScriptKeyValueCoding.h)
- (id)valueInSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -valueInSessionsAtIndex: %d", anIndex);
    return [[self sessions] objectAtIndex:anIndex];
}

- (NSArray*)sessions
{
    int n = [TABVIEW numberOfTabViewItems];
    NSMutableArray *sessions = [NSMutableArray arrayWithCapacity:n];
    int i;

    for (i = 0; i < n; ++i) {
        for (PTYSession* aSession in [[[TABVIEW tabViewItemAtIndex:i] identifier] sessions]) {
            [sessions addObject:aSession];
        }
    }

    return sessions;
}

- (void)setSessions:(NSArray*)sessions
{
}

- (id)valueWithName: (NSString *)uniqueName inPropertyWithKey: (NSString*)propertyKey
{
    id result = nil;
    int i;

    if ([propertyKey isEqualToString:kSessionsKVCKey]) {
        PTYSession *aSession;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aSession = [[[TABVIEW tabViewItemAtIndex:i] identifier] activeSession];
            if ([[aSession name] isEqualToString: uniqueName] == YES) {
                return (aSession);
            }
        }
    }

    return result;
}

// The 'uniqueID' argument might be an NSString or an NSNumber.
- (id)valueWithID:(NSString *)uniqueID inPropertyWithKey:(NSString*)propertyKey
{
    id result = nil;
    int i;

    if ([propertyKey isEqualToString:kSessionsKVCKey]) {
        PTYSession *aSession;

        for (i = 0; i < [TABVIEW numberOfTabViewItems]; ++i) {
            aSession = [[[TABVIEW tabViewItemAtIndex:i] identifier] activeSession];
            if ([[aSession tty] isEqualToString:uniqueID] == YES) {
                return (aSession);
            }
        }
    }

    return result;
}

- (id)addNewSession:(NSDictionary *)addressbookEntry
           withURL:(NSString *)url
     forObjectType:(iTermObjectType)objectType
{
    PtyLog(@"PseudoTerminal: -addNewSession");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession screen] setUnlimitedScrollback:[[addressbookEntry objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setProfile: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession screen]) {
        // We process the cmd to insert URL parts
        NSMutableString *cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry
                                                                                            forObjectType:objectType]] autorelease];
        NSMutableString *name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        NSURL *urlRep = [NSURL URLWithString: url];


        // Grab the addressbook command
        [cmd replaceOccurrencesOfString:@"$$URL$$" withString:url options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$HOST$$" withString:[urlRep host]?[urlRep host]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$USER$$" withString:[urlRep user]?[urlRep user]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PASSWORD$$" withString:[urlRep password]?[urlRep password]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PORT$$" withString:[urlRep port]?[[urlRep port] stringValue]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$PATH$$" withString:[urlRep path]?[urlRep path]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];
        [cmd replaceOccurrencesOfString:@"$$RES$$" withString:[urlRep resourceSpecifier]?[urlRep resourceSpecifier]:@"" options:NSLiteralSearch range:NSMakeRange(0, [cmd length])];

        // Update the addressbook title
        [name replaceOccurrencesOfString:@"$$URL$$" withString:url options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$HOST$$" withString:[urlRep host]?[urlRep host]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$USER$$" withString:[urlRep user]?[urlRep user]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PASSWORD$$" withString:[urlRep password]?[urlRep password]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PORT$$" withString:[urlRep port]?[[urlRep port] stringValue]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$PATH$$" withString:[urlRep path]?[urlRep path]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];
        [name replaceOccurrencesOfString:@"$$RES$$" withString:[urlRep resourceSpecifier]?[urlRep resourceSpecifier]:@"" options:NSLiteralSearch range:NSMakeRange(0, [name length])];

        // Get remaining session parameters
        [self getSessionParameters:cmd withName:name];

        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;
        [cmd breakDownCommandToPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry forObjectType:objectType];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

        [self setName:name forSession:aSession];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 inSession:aSession];
    }
    [aSession release];
    return aSession;
}

- (id)addNewSession:(NSDictionary *)addressbookEntry withURL:(NSString *)url
{
    return [self addNewSession:addressbookEntry withURL:url forObjectType:iTermWindowObject];
}


- (id)addNewSession:(NSDictionary *)addressbookEntry
        withCommand:(NSString *)command
      forObjectType:(iTermObjectType)objectType
{
    PtyLog(@"PseudoTerminal: addNewSession 2");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] init];
    [[aSession screen] setUnlimitedScrollback:[[addressbookEntry objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[addressbookEntry objectForKey:KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setProfile: addressbookEntry];
    // Add this session to our term and make it current
    [self appendSession: aSession];
    if ([aSession screen]) {
        NSMutableString *cmd, *name;
        NSArray *arg;
        NSString *pwd;
        BOOL isUTF8;

        // Grab the addressbook command
        cmd = [[[NSMutableString alloc] initWithString:command] autorelease];
        name = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey: KEY_NAME]] autorelease];
        // Get session parameters
        [self getSessionParameters:cmd withName:name];

        [cmd breakDownCommandToPath:&cmd cmdArgs:&arg];

        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:addressbookEntry
                                           forObjectType:objectType];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env =[NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

        [self setName:name forSession:aSession];

        // Start the command
        [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8 inSession:aSession];
    }

    [aSession release];
    return aSession;
}

-(void)appendSession:(PTYSession *)object
{
    PtyLog(@"PseudoTerminal: -appendSession: %p", object);
    // Increment tabViewItemsBeingAdded so that the maximum content size will
    // be calculated with the tab bar if it's about to open.
    ++tabViewItemsBeingAdded;
    [self setupSession:object title:nil withSize:nil];
    tabViewItemsBeingAdded--;
    if ([object screen]) {  // screen initialized ok
        if ([iTermSettingsModel addNewTabAtEndOfTabs] || ![self currentTab]) {
            [self insertSession:object atIndex:[TABVIEW numberOfTabViewItems]];
        } else {
            [self insertSession:object atIndex:[self indexOfTab:[self currentTab]] + 1];
        }
    }
    [[self currentTab] numberOfSessionsDidChange];
}

-(void)replaceInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    PtyLog(@"PseudoTerminal: -replaceInSessions: %p atIndex: %d", object, anIndex);
    // TODO: Test this
    [self setupSession:object title:nil withSize:nil];
    if ([object screen]) {  // screen initialized ok
        [self replaceSession:object atIndex:anIndex];
    }
}

-(void)addInSessions:(PTYSession *)object
{
    PtyLog(@"PseudoTerminal: -addInSessions: %p", object);
    [self insertInSessions: object];
}

-(void)insertInSessions:(PTYSession *)object
{
    PtyLog(@"PseudoTerminal: -insertInSessions: %p", object);
    [self insertInSessions: object atIndex:[TABVIEW numberOfTabViewItems]];
}

-(void)insertInSessions:(PTYSession *)object atIndex:(unsigned)anIndex
{
    PtyLog(@"PseudoTerminal: -insertInSessions: %p atIndex: %d", object, anIndex);
    BOOL toggle = NO;
    if (![self windowInited]) {
        // call initWithSmartLayout:YES, etc, like this:
        Profile *aDict = [object profile];
        [self finishInitializationWithSmartLayout:YES
                                       windowType:[[iTermController sharedInstance] windowTypeForBookmark:aDict]
                                           screen:aDict[KEY_SCREEN] ? [[aDict objectForKey:KEY_SCREEN] intValue] : -1
                                         isHotkey:NO];
        if ([[aDict objectForKey:KEY_HIDE_AFTER_OPENING] boolValue]) {
            [self hideAfterOpening];
        }
        [[iTermController sharedInstance] addInTerminals:self];
        toggle = ([self windowType] == WINDOW_TYPE_LION_FULL_SCREEN);
    }

    [self setupSession:object title:nil withSize:nil];
    if ([object screen]) {  // screen initialized ok
        [self insertSession:object atIndex:anIndex];
    }
    [[self currentTab] numberOfSessionsDidChange];
    if (toggle) {
        [self delayedEnterFullscreen];
    }
}

-(void)removeFromSessionsAtIndex:(unsigned)anIndex
{
    // NSLog(@"PseudoTerminal: -removeFromSessionsAtIndex: %d", anIndex);
    if (anIndex < [TABVIEW numberOfTabViewItems]) {
        PTYSession *aSession = [[[TABVIEW tabViewItemAtIndex:anIndex] identifier] activeSession];
        [self closeSession:aSession];
    }
}

- (BOOL)windowInited
{
    return (windowInited);
}

- (void) setWindowInited: (BOOL) flag
{
    windowInited = flag;
}

// TODO: What is KVC?
// a class method to provide the keys for KVC:
+ (NSArray*)kvcKeys
{
    static NSArray *_kvcKeys = nil;
    if (nil == _kvcKeys ){
        _kvcKeys = [[NSArray alloc] initWithObjects:
            kColumnsKVCKey, kRowsKVCKey, kSessionsKVCKey, nil ];
    }
    return _kvcKeys;
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
}

#pragma mark - Scripting Support

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSUInteger anIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef;

    NSArray *terminals = [[iTermController sharedInstance] terminals];
    anIndex = [terminals indexOfObjectIdenticalTo:self];
    if (anIndex != NSNotFound) {
        containerRef     = [NSApp objectSpecifier];
        classDescription = [NSClassDescription classDescriptionForClass:[NSApp class]];
        //create and return the specifier
        return [[[NSIndexSpecifier allocWithZone:[self zone]]
               initWithContainerClassDescription: classDescription
                              containerSpecifier: containerRef
                                             key: @ "terminals"
                                           index: anIndex] autorelease];
    } else {
        return nil;
    }
}

// Handlers for supported commands:

-(void)handleSelectScriptCommand: (NSScriptCommand *)command
{
    [[iTermController sharedInstance] setCurrentTerminal: self];
}

-(id)handleLaunchScriptCommand: (NSScriptCommand *)command
{
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    NSString *session = [args objectForKey:@"session"];
    NSDictionary *abEntry;

    abEntry = [[ProfileModel sharedInstance] bookmarkWithName:session];
    if (abEntry == nil) {
        abEntry = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (abEntry == nil) {
        NSMutableDictionary* aDict = [[[NSMutableDictionary alloc] init] autorelease];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        abEntry = aDict;
    }

    return [[iTermController sharedInstance] launchBookmark:abEntry inTerminal:self];
}

-(void)handleSplitScriptCommand: (NSScriptCommand *)command
{
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    NSString *direction = args[@"direction"];
    BOOL isVertical = [direction isEqualToString:@"vertical"];
    NSString *profileName = args[@"profile"];
    NSDictionary *abEntry;

    abEntry = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (abEntry == nil) {
        abEntry = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (abEntry == nil) {
        NSMutableDictionary* aDict = [NSMutableDictionary dictionary];
        [ITAddressBookMgr setDefaultsInBookmark:aDict];
        [aDict setObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        abEntry = aDict;
    }

    [self splitVertically:isVertical
             withBookmark:abEntry
            targetSession:[[self currentTab] activeSession]];

}

@end
