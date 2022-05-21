// Implements the model class for a terminal session.

#import "Api.pbobjc.h"
#import "DVR.h"
#import "iTermAPIHelper.h"
#import "iTermEchoProbe.h"
#import "iTermEncoderAdapter.h"
#import "iTermFindDriver.h"
#import "iTermFileDescriptorClient.h"
#import "iTermMetalUnavailableReason.h"
#import "iTermWeakReference.h"
#import "ITAddressBookMgr.h"
#import "iTermPopupWindowController.h"
#import "iTermSessionNameController.h"

#import "GPBEnumArray+iTerm.h"
#import "LineBuffer.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "ProfileModel.h"
#import "TextViewWrapper.h"
#import "TmuxController.h"
#import "TmuxGateway.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"
#import "WindowControllerInterface.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <sys/time.h>

// Posted when the tmux font changes. Window layouts will need to be updated.
extern NSString *const kPTYSessionTmuxFontDidChange;

// Called when captured output for the current session changes.
extern NSString *const kPTYSessionCapturedOutputDidChange;

extern NSString *const PTYSessionCreatedNotification;
extern NSString *const PTYSessionTerminatedNotification;
extern NSString *const PTYSessionRevivedNotification;
extern NSString *const iTermSessionWillTerminateNotification;

@class CapturedOutput;
@protocol ExternalSearchResultsController;
@class FakeWindow;
@class iTermAction;
@class iTermAnnouncementViewController;
@protocol iTermContentSubscriber;
@class iTermEchoProbe;
@class iTermImageWrapper;
@class iTermKeyBindingAction;
@class iTermScriptHistoryEntry;
@class iTermStatusBarViewController;
@class iTermSwiftyStringGraph;
@class iTermVariables;
@class iTermVariableScope;
@class PTYSessionZoomState;
@class PTYTab;
@class PTYTask;
@class PTYTextView;
@class PasteContext;
@class PreferencePanel;
@protocol ProcessInfoProvider;
@class PTYSession;
@class SSHIdentity;
@protocol VT100RemoteHostReading;
@class VT100Screen;
@class VT100Terminal;
@class iTermColorMap;
@class iTermCommandHistoryCommandUseMO;
@class iTermController;
@class iTermNotificationController;
@class iTermPromptOnCloseReason;
@class iTermQuickLookController;
@protocol iTermSessionScope;
@class SessionView;

typedef NS_ENUM(NSInteger, SplitSelectionMode) {
    kSplitSelectionModeOn,
    kSplitSelectionModeOff,
    kSplitSelectionModeCancel,
    kSplitSelectionModeInspect
};

typedef enum {
    TMUX_NONE,
    TMUX_GATEWAY,  // Receiving tmux protocol messages
    TMUX_CLIENT  // Session mirrors a tmux virtual window
} PTYSessionTmuxMode;

// This is implemented by a view that contains a collection of sessions, nominally a tab.
@protocol PTYSessionDelegate<NSObject>

// Return the window controller for this session. This is the "real" one, not a
// possible proxy that gets subbed in during instant replay.
- (NSWindowController<iTermWindowController> *)realParentWindow;

// A window controller which may be a proxy during instant replay.
- (id<WindowControllerInterface>)parentWindow;

// When a surrogate view is replacing the real SessionView, a reference to the
// real (or "live") view must be held. Invoke this to add it to an array of
// live views so it will be kept alive. Use -showLiveSession:inPlaceOf: to
// remove a view from this list.
- (void)addHiddenLiveView:(SessionView *)hiddenLiveView;
- (void)session:(PTYSession *)synthetic setLiveSession:(PTYSession *)live;

// Provides a tab number for the ITERM_SESSION_ID environment variable. This
// may not correspond to the physical tab number because it's immutable for a
// given tab.
- (int)tabNumberForItermSessionId;

// Sibling sessions in this tab.
- (NSArray<PTYSession *> *)sessions;

// Remove aSession from the tab.
// Remove a dead session. This should be called from [session terminate] only.
- (void)removeSession:(PTYSession *)aSession;

// Is the tab this session belongs to currently visible?
- (BOOL)sessionBelongsToVisibleTab;

// The tab number as shown in the tab bar, starting at 1. May go into double digits.
- (int)tabNumber;

- (void)updateLabelAttributes;

// End the session (calling terminate normally or killing/hiding a tmux
// session), and closes the tab if needed.
- (void)closeSession:(PTYSession *)session;
- (void)softCloseSession:(PTYSession *)session;

// Sets whether the bell indicator should show.
- (void)setBell:(BOOL)flag;

// Something changed with the profile that might cause the window to be blurred.
- (void)recheckBlur;

// Indicates if this session is the active one in its tab, even if the tab
// isn't necessarily selected.
- (BOOL)sessionIsActiveInTab:(PTYSession *)session;

// Is this session active in a currently selected tab? This ignores whether the
// window is key.
- (BOOL)sessionIsActiveInSelectedTab:(PTYSession *)session;

// Session-initiated name change.
- (void)nameOfSession:(PTYSession *)session didChangeTo:(NSString *)newName;

// Session-initiated font size. May cause window size to adjust.
- (void)sessionDidChangeFontSize:(PTYSession *)session
                    adjustWindow:(BOOL)adjustWindow;

// Session-initiated resize.
- (BOOL)sessionInitiatedResize:(PTYSession*)session width:(int)width height:(int)height;

// Select the "next" session in this tab.
- (void)nextSession;

// Select the "previous" session in this tab.
- (void)previousSession;

// Does the tab have a maximized pane?
- (BOOL)hasMaximizedPane;

// Make session active in this tab. Assumes session belongs to thet ab.
- (void)setActiveSession:(PTYSession*)session;
- (void)setActiveSessionPreservingMaximization:(PTYSession *)session;

// Index of the tab. 0-based.
- (int)number;

// Make the containing tab selected in its window. The window may not be visible, though.
- (void)sessionSelectContainingTab;

// Add the session to the restorableSession.
- (void)addSession:(PTYSession *)self toRestorableSession:(iTermRestorableSession *)restorableSession;

// Unmaximize the maximized pane (if any) in the tab.
- (void)unmaximize;

// Tmux window number (a tmux window is like a tab).
- (void)setTmuxFont:(NSFont *)font
       nonAsciiFont:(NSFont *)nonAsciiFont
           hSpacing:(double)horizontalSpacing
           vSpacing:(double)verticalSpacing;

// The tmux window title changed.
- (void)sessionDidChangeTmuxWindowNameTo:(NSString *)newName;

// Returns the objectSpecifier of the tab (used to identify a tab for AppleScript).
- (NSScriptObjectSpecifier *)objectSpecifier;

// Returns the tmux window ID of the containing tab. -1 if not tmux.
- (int)tmuxWindow;

// If the tab is a tmux window, this gives its name.
- (NSString *)tmuxWindowName;

- (BOOL)session:(PTYSession *)session shouldAllowDrag:(id<NSDraggingInfo>)sender;
- (BOOL)session:(PTYSession *)session performDragOperation:(id<NSDraggingInfo>)sender;

// Indicates if the splits are currently being dragged. Affects how resizing works for tmux tabs.
- (BOOL)sessionBelongsToTabWhoseSplitsAreBeingDragged;

// User double clicked on title bar
- (void)sessionDoubleClickOnTitleBar:(PTYSession *)session;

// Returns the 0-based pane number to use in $ITERM_SESSION_ID.
- (NSUInteger)sessionPaneNumber:(PTYSession *)session;

// The background color changed.
- (void)sessionBackgroundColorDidChange:(PTYSession *)session;

- (void)sessionKeyLabelsDidChange:(PTYSession *)session;

- (void)sessionCurrentDirectoryDidChange:(PTYSession *)session;
- (void)sessionCurrentHostDidChange:(PTYSession *)session;
- (void)sessionProxyIconDidChange:(PTYSession *)session;
- (void)sessionDidRestart:(PTYSession *)session;

// Remove a session from the tab, even if it's the only one.
- (void)sessionRemoveSession:(PTYSession *)session;

// Returns the size of the tab in rows x cols. Initial tmux client size.
- (VT100GridSize)sessionTmuxSizeWithProfile:(Profile *)profile;

// Whether metal is allowed has changed
- (void)sessionUpdateMetalAllowed;
- (void)sessionDidChangeMetalViewAlphaValue:(PTYSession *)session to:(CGFloat)newValue;

// Amount of transparency changed (perhaps to none!)
- (void)sessionTransparencyDidChange;

// Scrollback buffer cleared.
- (void)sessionDidClearScrollbackBuffer:(PTYSession *)session;

- (iTermVariables *)sessionTabVariables;
- (void)sessionDuplicateTab;

- (BOOL)sessionShouldAutoClose:(PTYSession *)session;
- (void)sessionDidChangeGraphic:(PTYSession *)session
                     shouldShow:(BOOL)shouldShow
                          image:(NSImage *)image;
- (NSView *)sessionContainerView:(PTYSession *)session;


- (void)sessionDraggingEntered:(PTYSession *)session;
- (void)sessionDraggingExited:(PTYSession *)session;

- (BOOL)sessionShouldSendWindowSizeIOCTL:(PTYSession *)session;

- (void)sessionDidInvalidateStatusBar:(PTYSession *)session;
- (void)sessionAddSwiftyStringsToGraph:(iTermSwiftyStringGraph *)graph;
- (iTermVariableScope *)sessionTabScope;
- (void)sessionDidReportSelectedTmuxPane:(PTYSession *)session;
- (void)sessionDidUpdatePaneTitle:(PTYSession *)session;
- (void)sessionDidSetWindowTitle:(NSString *)title;
- (void)sessionJobDidChange:(PTYSession *)session;
- (void)sessionEditActions;
- (void)sessionEditSnippets;
- (void)session:(PTYSession *)session
setBackgroundImage:(iTermImageWrapper *)image
           mode:(iTermBackgroundImageMode)imageMode
backgroundColor:(NSColor *)backgroundColor;
- (iTermImageWrapper *)sessionBackgroundImage;
- (iTermBackgroundImageMode)sessionBackgroundImageMode;
- (CGFloat)sessionBlend;
- (void)sessionDidUpdatePreferencesFromProfile:(PTYSession *)session;
- (id<iTermSwipeHandler>)sessionSwipeHandler;
- (BOOL)sessionIsInSelectedTab:(PTYSession *)session;
- (void)sessionDisableFocusFollowsMouseAtCurrentLocation;
- (void)sessionDidResize:(PTYSession *)session;
- (BOOL)sessionPasswordManagerWindowIsOpen;
- (BOOL)sessionShouldDragWindowByPaneTitleBar:(PTYSession *)session;
- (void)sessionSubtitleDidChange:(PTYSession *)session;
- (void)sessionActivate:(PTYSession *)session;

- (void)session:(PTYSession *)session setFilter:(NSString *)filter;
- (PTYSession *)sessionSyntheticSessionFor:(PTYSession *)live;
- (void)sessionClose:(PTYSession *)session;
- (void)sessionProcessInfoProviderDidChange:(PTYSession *)session;

@end

@class SessionView;
@interface PTYSession : NSResponder <
    iTermEchoProbeDelegate,
    iTermFindDriverDelegate,
    iTermSubscribable,
    iTermTmuxControllerSession,
    iTermUniquelyIdentifiable,
    iTermWeaklyReferenceable,
    PopupDelegate,
    PTYTaskDelegate,
    PTYTextViewDelegate,
    TmuxGatewayDelegate,
    VT100ScreenDelegate>
@property(nonatomic, assign) id<PTYSessionDelegate> delegate;

// A session is active when it's in a visible tab and it needs periodic redraws (something is
// blinking, it isn't idle, etc), or when a background tab is updating its tab label. This controls
// how often -updateDisplay gets called to check for dirty characters and invalidate dirty rects,
// update the tab and window titles, stop "tail find" (searching the live session repeatedly
// because the find window is open), and evaluating partial-line triggers.
@property(nonatomic, assign) BOOL active;

@property(nonatomic, assign) BOOL alertOnNextMark;
@property(nonatomic, copy) NSColor *tabColor;

@property(nonatomic, readonly) DVR *dvr;
@property(nonatomic, readonly) DVRDecoder *dvrDecoder;
// Returns the "real" session while in instant replay, else nil if not in IR.
@property(nonatomic, retain) PTYSession *liveSession;
@property(nonatomic, readonly) BOOL canInstantReplayPrev;
@property(nonatomic, readonly) BOOL canInstantReplayNext;

@property(nonatomic, readonly) BOOL isTmuxClient;
@property(nonatomic, readonly) BOOL isTmuxGateway;

// Does the session have new output? Used by -[PTYTab updateLabelAttributes] to color the tab's title
// appropriately.
@property(nonatomic, assign) BOOL newOutput;

// Do we need to prompt on close for this session?
@property(nonatomic, readonly) iTermPromptOnCloseReason *promptOnCloseReason;

// Array of subprocessess names. WARNING: This forces a synchronous update of the process cache.
// It is up-to-date but too slow to call frequently.
// The first value is the name and the second is the process title.
@property(nonatomic, readonly) NSArray<iTermTuple<NSString *, NSString *> *> *childJobNameTuples;

// Is the session idle? Used by updateLabelAttributes to send a user notification when processing ends.
@property(nonatomic, assign) BOOL havePostedIdleNotification;

// Is there new output for the purposes of user notifications? They run on a different schedule
// than tab colors.
@property(nonatomic, assign) BOOL havePostedNewOutputNotification;

@property(nonatomic, readonly) iTermSessionNameController *nameController;

// Returns the presentationName from the nameController. This is only here because
// it's nearly impossible to find all the call sites for it.
@property (nonatomic, readonly) NSString *name;

// The window title that should be used when this session is current. Otherwise defaultName
// should be used.
@property(nonatomic, copy) NSString *windowTitle;

// The path to the proxy icon that should be used when this session is current. If is nil the current directory icon
// is shown.
@property(nonatomic, retain) NSURL *preferredProxyIcon;

// Shell wraps the underlying file descriptor pair.
@property(nonatomic, retain) PTYTask *shell;

// The value of the $TERM environment var.
@property(nonatomic, copy) NSString *termVariable;

// The value of the $COLORFGBG environment var.
@property(nonatomic, copy) NSString *colorFgBgVariable;

// Screen contents, plus scrollback buffer.
@property(nonatomic, retain) VT100Screen *screen;

// The view in which this session's objects live.
@property(nonatomic, retain) SessionView *view;

// The view that contains all the visible text in this session and that does most input handling.
// This is the one and only subview of the document view of -scrollview.
@property(nonatomic, retain) PTYTextView *textview;

@property(nonatomic, readonly) NSStringEncoding encoding;

// Send a character periodically.
@property(nonatomic, assign) BOOL antiIdle;

// The code to send in the anti idle timer.
@property(nonatomic, assign) char antiIdleCode;

// The interval between sending anti-idle codes.
@property(nonatomic, assign) NSTimeInterval antiIdlePeriod;

// If true, close the tab when the session ends.
@property(nonatomic, assign) iTermSessionEndAction endAction;

// Should ambiguous-width characters (e.g., Greek) be treated as double-width? Usually a bad idea.
@property(nonatomic, assign) BOOL treatAmbiguousWidthAsDoubleWidth;

// True if mouse movements are sent to the host.
@property(nonatomic, assign) BOOL xtermMouseReporting;

// True if the mouse wheel movements are sent to the host.
@property(nonatomic, assign) BOOL xtermMouseReportingAllowMouseWheel;
@property(nonatomic, assign) BOOL xtermMouseReportingAllowClicksAndDrags;

// Profile for this session
@property(nonatomic, copy) Profile *profile;

// Return the address book that the session was originally created with.
@property(nonatomic, readonly) Profile *originalProfile;

// tty device
@property(nonatomic, readonly) NSString *tty;

@property(nonatomic, assign) iTermBackgroundImageMode backgroundImageMode;

// Blend level as specified in this session's profile.
@property(nonatomic, readonly) CGFloat desiredBlend;

// Filename of background image.
@property(nonatomic, copy) NSString *backgroundImagePath;  // Used by scripting
@property(nonatomic, retain) iTermImageWrapper *backgroundImage;

@property(nonatomic, assign) float transparency;
@property(nonatomic, assign) BOOL useBoldFont;
@property(nonatomic, assign) iTermThinStrokesSetting thinStrokes;
@property(nonatomic, assign) BOOL asciiLigatures;
@property(nonatomic, assign) BOOL nonAsciiLigatures;
@property(nonatomic, assign) BOOL useItalicFont;

@property(nonatomic, readonly) BOOL logging;
@property(nonatomic, readonly) BOOL exited;

// Is bell currently in ringing state?
@property(nonatomic, assign) BOOL bell;

@property(nonatomic, readonly) int columns;
@property(nonatomic, readonly) int rows;

// Returns whether this session considers itself eligible to use the Metal renderer.
@property(nonatomic, readonly) BOOL metalAllowed;
@property(nonatomic, readonly) BOOL idleForMetal;

// Controls whether this session uses the Metal renderer.
@property(nonatomic) BOOL useMetal;

// Has this session's bookmark been divorced from the profile in the ProfileModel? Changes
// in this bookmark may happen independently of the persistent bookmark.
// You should usually not assign to this; instead use divorceAddressBookEntryFromPreferences.
@property(nonatomic, assign, readonly) BOOL isDivorced;

// Ignore resize notifications. This would be set because the session's size mustn't be changed
// due to temporary changes in the window size, as code later on may need to know the session's
// size to set the window size properly.
@property(nonatomic, assign) BOOL ignoreResizeNotifications;

// This number (int) imposes an ordering on session activity time.
@property(nonatomic, retain) NSNumber *activityCounter;

// Is there a saved scroll position?
@property(nonatomic, readonly) BOOL hasSavedScrollPosition;

// Image for dragging one session.
@property(nonatomic, readonly) NSImage *dragImage;

@property(nonatomic, readonly) BOOL hasCoprocess;

@property(nonatomic, retain) TmuxController *tmuxController;

// Call this on tmux clients to get the session with the tmux gateway.
@property(nonatomic, readonly) PTYSession *tmuxGatewaySession;

@property(nonatomic, readonly) id<VT100RemoteHostReading> currentHost;

@property(nonatomic, readonly) int tmuxPane;

// FinalTerm
@property(nonatomic, readonly) NSArray *autocompleteSuggestionsForCurrentCommand;
@property(nonatomic, readonly) NSString *currentCommand;

// Session is not in foreground and notifications are enabled on the screen.
@property(nonatomic, readonly) BOOL shouldPostUserNotification;

@property(nonatomic, readonly) BOOL hasSelection;

@property(nonatomic, assign) BOOL highlightCursorLine;

// Used to help remember total ordering on views while one is maximized
@property(nonatomic, assign) NSPoint savedRootRelativeOrigin;

// The computed label
@property(nonatomic, readonly) NSString *badgeLabel;
@property(nonatomic, readonly) NSString *subtitle;

// Commands issued, directories entered, and hosts connected to during this session.
// Requires shell integration.
@property(nonatomic, readonly) NSMutableArray<NSString *> *commands;  // of NSString
@property(nonatomic, readonly) NSMutableArray<NSString *> *directories;  // of NSString
@property(nonatomic, readonly) NSMutableArray<id<VT100RemoteHostReading>> *hosts;  // of VT100RemoteHost

@property (nonatomic, readonly) iTermVariables *variables;
@property (nonatomic, readonly) iTermVariableScope<iTermSessionScope> *variablesScope;
@property (nonatomic, readonly) iTermVariableScope *genericScope;  // Just like `variablesScope` but usable from Swift.

@property(atomic, readonly) PTYSessionTmuxMode tmuxMode;

// Has output been received recently?
@property(nonatomic, readonly) BOOL isProcessing;

// Indicates if you're at the shell prompt and not running a command. Returns
// NO if shell integration is not in use.
@property(nonatomic, readonly) BOOL isAtShellPrompt;

// Has it been at least a second since isProcessing became false?
@property(nonatomic, readonly) BOOL isIdle;

// Tries to return the current local working directory without resolving symlinks (possible if
// shell integration is on). If that can't be done then the current local working directory with
// symlinks resolved is returned.
@property(nonatomic, readonly) NSString *currentLocalWorkingDirectory;

// Async version of currentLocalWorkingDirectory.
- (void)asyncCurrentLocalWorkingDirectory:(void (^)(NSString *pwd))completion;

- (void)asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory:(void (^)(NSString *pwd))completion;

// Gets the local directory as URL. Weirdly, combines the remote hostname and the local path because this is really only used for the proxy icon.
- (void)asyncGetCurrentLocationWithCompletion:(void (^)(NSURL *url))completion;

// A UUID that uniquely identifies this session.
// Used to link serialized data back to a restored session (e.g., which session
// a command in command history belongs to). Also to link content from an
// arrangement provided to us by the OS during system window restoration with a
// session in a saved arrangement when we're opening a saved arrangement at
// startup instead of respecting the wishes of system window restoration.
// Also used by the websocket API to reference a session.
@property(nonatomic, readonly) NSString *guid;

// Indicates if this session predates a tmux split pane. Used to figure out which pane is new when
// layout changes due to a user-initiated pane split.
@property(nonatomic, assign) BOOL sessionIsSeniorToTmuxSplitPane;

@property(nonatomic, readonly) NSArray<iTermCommandHistoryCommandUseMO *> *commandUses;
@property(nonatomic, readonly) BOOL eligibleForAutoCommandHistory;

// If we want to show quicklook this will not be nil.
@property(nonatomic, readonly) iTermQuickLookController *quickLookController;

@property(nonatomic, readonly) NSDictionary<NSString *, NSString *> *keyLabels;
@property(nonatomic, readonly) iTermRestorableSession *restorableSession;
@property(nonatomic) BOOL copyMode;

// Is the user currently typing at a password prompt?
@property(nonatomic, readonly) BOOL passwordInput;

@property(nonatomic) BOOL isSingleUseSession;
@property(nonatomic) BOOL overrideGlobalDisableMetalWhenIdleSetting;
@property(nonatomic, readonly) BOOL canProduceMetalFramecap;
@property(nonatomic, readonly) NSColor *textColorForStatusBar;
@property(nonatomic, readonly) NSColor *processedBackgroundColor;
@property(nonatomic, readonly) NSImage *tabGraphic;
@property(nonatomic, readonly) iTermStatusBarViewController *statusBarViewController;
@property(nonatomic, readonly) BOOL shouldShowTabGraphic;
@property(nonatomic, readonly) NSData *backspaceData;
@property(nonatomic, readonly) iTermEchoProbe *echoProbe;
@property(nonatomic, readonly) BOOL canOpenPasswordManager;
@property(nonatomic) BOOL shortLivedSingleUse;
@property(nonatomic, retain) NSMutableDictionary<NSString *, NSString *> *hostnameToShell;  // example.com -> fish
@property(nonatomic, readonly) NSString *sessionId;
@property(nonatomic, retain) NSNumber *cursorTypeOverride;
@property(nonatomic, readonly) NSDictionary *environment;
@property(nonatomic, readonly) BOOL hasNontrivialJob;
@property(nonatomic, readonly) BOOL tmuxPaused;
@property(nonatomic, readonly) NSString *userShell;  // Something like "/bin/bash".
@property(nonatomic, copy) NSString *filter;
@property(nonatomic, readonly, strong) iTermAsyncFilter *asyncFilter;
@property(nonatomic, readonly) NSMutableArray<id<iTermContentSubscriber>> *contentSubscribers;
@property(nonatomic, readonly) PTYSessionZoomState *stateToSaveForZoom;  // current state to restore after exiting zoom in the future
@property(nonatomic, strong) PTYSessionZoomState *savedStateForZoom;  // set in synthetic sessions, not in live sessions.

// Excludes SESSION_ARRANGEMENT_CONTENTS. Nil if session not created from arrangement.
@property(nonatomic, copy) NSDictionary *foundingArrangement;
@property(nonatomic, readonly) id<ExternalSearchResultsController> externalSearchResultsController;
@property(nonatomic, readonly) SSHIdentity *sshIdentity;
@property(nonatomic, readonly) id<ProcessInfoProvider> processInfoProvider;

#pragma mark - methods

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
             replacingProfileWithGUID:(NSString *)badGuid
                          withProfile:(Profile *)goodProfile;
+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
     replacingOldCWDOfSessionWithGUID:(NSString *)guid
                           withOldCWD:(NSString *)replacementOldCWD;

+ (BOOL)handleShortcutWithoutTerminal:(NSEvent*)event;
+ (void)selectMenuItem:(NSString*)theName;
+ (void)registerBuiltInFunctions;
+ (NSMapTable<NSString *, PTYSession *> *)sessionMap;

// Register the contents in the arrangement so that if the session is later
// restored from an arrangement with the same guid as |arrangement|, the
// contents will be copied over.
+ (void)registerSessionInArrangement:(NSDictionary *)arrangement;

// Forget all sessions registered with registerSessionInArrangement. Normally
// called after startup activities are done.
+ (void)removeAllRegisteredSessions;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initSynthetic:(BOOL)synthetic NS_DESIGNATED_INITIALIZER;

- (void)didFinishInitialization;

// Jump to a particular point in time.
- (long long)irSeekToAtLeast:(long long)timestamp;

// Begin showing DVR frames from some live session.
- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession;

- (void)willRetireSyntheticSession:(PTYSession *)syntheticSession;

// Append a bunch of lines from this (presumably synthetic) session from another (presumably live)
// session.
- (void)appendLinesInRange:(NSRange)rangeOfLines fromSession:(PTYSession *)source;

// Go forward/back in time. Must call setDvr:liveSession: first.
- (void)irAdvance:(int)dir;

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent;

// triggers
- (void)setAllTriggersEnabled:(BOOL)enabled;
- (BOOL)anyTriggerCanBeEnabled;
- (BOOL)anyTriggerCanBeDisabled;
// (regex, enabled)
- (NSArray<iTermTuple<NSString *, NSNumber *> *> *)triggerTuples;
- (void)toggleTriggerEnabledAtIndex:(NSInteger)index;

+ (void)drawArrangementPreview:(NSDictionary *)arrangement frame:(NSRect)frame dark:(BOOL)dark;
- (void)setSizeFromArrangement:(NSDictionary*)arrangement;
+ (PTYSession*)sessionFromArrangement:(NSDictionary *)arrangement
                                named:(NSString *)arrangementName
                               inView:(SessionView *)sessionView
                         withDelegate:(id<PTYSessionDelegate>)delegate
                        forObjectType:(iTermObjectType)objectType
                   partialAttachments:(NSDictionary *)partialAttachments;

+ (NSDictionary *)arrangementFromTmuxParsedLayout:(NSDictionary *)parseNode
                                         bookmark:(Profile *)bookmark
                                   tmuxController:(TmuxController *)tmuxController
                                           window:(int)window;
+ (NSString *)guidInArrangement:(NSDictionary *)arrangement;
+ (NSString *)initialWorkingDirectoryFromArrangement:(NSDictionary *)arrangement;

- (void)textViewFontDidChange;

// Set rows, columns from arrangement.
- (void)resizeFromArrangement:(NSDictionary *)arrangement;

- (void)startProgram:(NSString *)program
                 ssh:(BOOL)ssh
         environment:(NSDictionary *)prog_env
         customShell:(NSString *)customShell
              isUTF8:(BOOL)isUTF8
       substitutions:(NSDictionary *)substitutions
         arrangement:(NSString *)arrangement
          completion:(void (^)(BOOL))completion;

// This is an alternative to runCommandWithOldCwd and startProgram. It attaches
// to an existing server. Use only if [iTermAdvancedSettingsModel runJobsInServers]
// is YES.
- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
            completion:(void (^)(void))completion;

// Acts like the user pressing cmd-W but without confirmation.
- (void)close;

- (void)softTerminate;
- (void)terminate;

// Tries to revive a terminated session. Returns YES on success. It should be re-added to a tab if
// after reviving.
- (BOOL)revive;

// Preferences
- (void)setPreferencesFromAddressBookEntry: (NSDictionary *)aePrefs;
- (void)loadInitialColorTableAndResetCursorGuide;

// Call this after the profile changed. If not divorced, the profile and
// settings are updated. If divorced, changes are found in the session and
// shared profiles and merged, updating this object's addressBookEntry and
// overriddenFields.
- (BOOL)reloadProfile;

- (void)inheritDivorceFrom:(PTYSession *)parent decree:(NSString *)decree;

- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask;

// Writes output as though a key was pressed. Broadcast allowed. Supports tmux integration properly.
- (void)writeTask:(NSString *)string;

// Writes output as though a key was pressed. Does not broadcast. Supports tmux integration properly.
- (void)writeTaskNoBroadcast:(NSString *)string;

// Write with a particular encoding. If the encoding is just session.terminal.encoding then pass
// NO for `forceEncoding` and the terminal's encoding will be used instead of `optionalEncoding`.
- (void)writeTaskNoBroadcast:(NSString *)string
                    encoding:(NSStringEncoding)optionalEncoding
               forceEncoding:(BOOL)forceEncoding;

- (void)writeLatin1EncodedData:(NSData *)data broadcastAllowed:(BOOL)broadcast;

- (void)updateViewBackgroundImage;
- (void)invalidateBlend;

// PTYTextView
- (BOOL)hasTextSendingKeyMappingForEvent:(NSEvent*)event;
- (BOOL)willHandleEvent: (NSEvent *)theEvent;
- (void)handleEvent: (NSEvent *)theEvent;
- (void)insertNewline:(id)sender;
- (void)insertTab:(id)sender;
- (void)moveUp:(id)sender;
- (void)moveDown:(id)sender;
- (void)moveLeft:(id)sender;
- (void)moveRight:(id)sender;
- (void)pageUp:(id)sender;
- (void)pageDown:(id)sender;
- (void)paste:(id)sender;
- (void)pasteString:(NSString *)str flags:(PTYSessionPasteFlags)flags;
- (void)deleteBackward:(id)sender;
- (void)deleteForward:(id)sender;
- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move;
- (void)setSmartCursorColor:(BOOL)value;

// Returns the frame size for a scrollview that perfectly contains the contents
// of this session based on rows/cols, and taking into account the presence of
// a scrollbar.
- (NSSize)idealScrollViewSizeWithStyle:(NSScrollerStyle)scrollerStyle;

// Update the scrollbar's visibility and style. Returns YES if a change was made.
// This is the one and only way that scrollbars should be changed after initialization. It ensures
// the content view's frame is updated.
- (BOOL)setScrollBarVisible:(BOOL)visible style:(NSScrollerStyle)style;

// Change the size of the session and its tty.
- (void)setSize:(VT100GridSize)size;

// Adjusts the defer count. We postpone TIOCSWINSZ sending until count becomes 0.
- (void)incrementDeferResizeCount:(NSInteger)delta;

// Returns the number of pixels over or under the an ideal size.
// Will never exceed +/- cell size/2.
// If vertically is true, proposedSize is a height, else it's a width.
// Example: If the line height is 10 (no margin) and you give a proposed size of 101,
// 1 is returned. If you give a proposed size of 99, -1 is returned.
- (int)overUnder:(int)proposedSize inVerticalDimension:(BOOL)vertically;

- (void)pushWindowTitle;
- (void)popWindowTitle;
- (void)pushIconTitle;
- (void)popIconTitle;


- (void)clearBuffer;
- (void)clearScrollbackBuffer;
- (void)logStart;
- (void)logStop;

// Display timer stuff
- (void)updateDisplayBecause:(NSString *)reason;
- (void)doAntiIdle;
- (NSString*)ansiColorsMatchingForeground:(NSDictionary*)fg andBackground:(NSDictionary*)bg inBookmark:(Profile*)aDict;

- (void)changeFontSizeDirection:(int)dir;
- (void)setFont:(NSFont*)font
    nonAsciiFont:(NSFont*)nonAsciiFont
    horizontalSpacing:(CGFloat)horizontalSpacing
    verticalSpacing:(CGFloat)verticalSpacing;

// Assigns a new GUID to the session so that changes to the bookmark will not
// affect it. Returns the GUID of a divorced bookmark. Does nothing if already
// divorced, but still returns the divorced GUID.
- (NSString*)divorceAddressBookEntryFromPreferences;
- (void)remarry;

// After divorcing, if there are already profile values that differ from underlying, call this to
// set overridden fields.
- (void)refreshOverriddenFields;

// Call refresh on the textview and schedule a timer if anything is blinking.
- (void)refresh;

// Open the current selection with semantic history.
- (void)openSelection;

// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition;

// Search for the selected text.
- (void)findWithSelection;

// Show the find view
- (void)showFindPanel;
- (void)showFilter;
- (void)stopFiltering;

// Find next/previous occurrence of find string.
- (void)searchNext;
- (void)searchPrevious;

- (void)setPasteboard:(NSString *)pbName;
- (void)stopCoprocess;
- (void)launchSilentCoprocessWithCommand:(NSString *)command;

- (void)setFocused:(BOOL)focused;
- (void)performBlockWithoutFocusReporting:(void (^NS_NOESCAPE)(void))block;
- (void)incrementDisableFocusReporting:(NSInteger)delta;
- (BOOL)wantsContentChangedNotification;

// The dcsID identifies the parser associated with this session. Parsers run in
// a different thread and communication between the main thread and the parser
// thread use the dcsID to ensure that the current parser is still the one that
// the main thread is expecting.
- (void)startTmuxMode:(NSString *)dcsID;

- (void)tmuxDetach;
// Two sessions are compatible if they may share the same tab. Tmux clients
// impose this restriction because they must belong to the same controller.
- (BOOL)isCompatibleWith:(PTYSession *)otherSession;
- (void)setTmuxPane:(int)windowPane;
- (void)setTmuxHistory:(NSArray<NSData *> *)history
            altHistory:(NSArray<NSData *> *)altHistory
                 state:(NSDictionary *)state;
- (void)toggleTmuxPausePane;

- (void)addNoteAtCursor;
- (void)previousMark;
- (void)nextMark;
- (void)previousAnnotation;
- (void)nextAnnotation;
- (void)scrollToMark:(id<iTermMark>)mark;

// Select this session and tab and bring window to foreground.
- (void)reveal;

// Make this session active in its tab but don't reveal the tab or window if not already active.
- (void)makeActive;

// Refreshes the textview and takes a snapshot of the SessionView.
- (NSImage *)snapshot;
- (NSImage *)snapshotCenteredOn:(VT100GridAbsCoord)coord size:(NSSize)size;

- (void)enterPassword:(NSString *)password;

- (void)queueAnnouncement:(iTermAnnouncementViewController *)announcement
               identifier:(NSString *)identifier;

- (void)tryToRunShellIntegrationInstallerWithPromptCheck:(BOOL)promptCheck;

- (BOOL)encodeArrangementWithContents:(BOOL)includeContents
                              encoder:(id<iTermEncoderAdapter>)encoder;

- (void)toggleTmuxZoom;
- (void)forceTmuxDetach;
- (void)tmuxDidDisconnect;
- (void)tmuxWindowTitleDidChange;

- (void)restoreStateForZoom:(PTYSessionZoomState *)state;

// This is to work around a macOS bug where setNeedsDisplay: on the root view controller does not
// cause the TextViewWrapper to be redrawn in its entirety.
- (void)setNeedsDisplay:(BOOL)needsDisplay;

// Kill the running command (if possible), print a banner, and rerun the profile's command.
- (void)restartSession;

// Make this session's textview the first responder.
- (void)takeFocus;

// Show an announcement explaining why a restored session is an orphan.
- (void)showOrphanAnnouncement;

- (BOOL)hasAnnouncementWithIdentifier:(NSString *)identifier;

// Change the current profile but keep the name the same.
- (void)setProfile:(NSDictionary *)newProfile
    preservingName:(BOOL)preserveName;

// Make the scroll view's document view be this session's textViewWrapper.
- (void)setScrollViewDocumentView;

// Set a value in the session's dictionary without affecting the backing profile.
- (void)setSessionSpecificProfileValues:(NSDictionary *)newValues;
- (NSString *)amendedColorKey:(NSString *)baseKey;

- (void)useTransparencyDidChange;

- (void)performKeyBindingAction:(iTermKeyBindingAction *)action event:(NSEvent *)event;

- (void)setColorsFromPresetNamed:(NSString *)presetName;

// Burys a session
- (void)bury;

// Undoes burying of a session.
- (void)disinter;

- (void)jumpToLocationWhereCurrentStatusChanged;
- (void)updateMetalDriver;
- (id)temporarilyDisableMetal NS_AVAILABLE_MAC(10_11);
- (void)drawFrameAndRemoveTemporarilyDisablementOfMetalForToken:(id)token NS_AVAILABLE_MAC(10_11);

- (BOOL)willEnableMetal;
- (BOOL)metalAllowed:(out iTermMetalUnavailableReason *)reason;
- (void)injectData:(NSData *)data;

// Call this when a session moves to a different tab or window to update the session ID.
- (void)didMoveSession;
- (void)didInitializeSessionWithName:(NSString *)name;
- (void)profileNameDidChangeTo:(NSString *)name;
- (void)profileDidChangeToProfileWithName:(NSString *)name;
- (void)updateStatusBarStyle;
- (BOOL)checkForCyclesInSwiftyStrings;
- (void)applyAction:(iTermAction *)action;
- (void)didUpdateCurrentDirectory;
- (BOOL)copyModeConsumesEvent:(NSEvent *)event;
- (Profile *)profileForSplit;
- (void)compose;
- (void)openComposerWithString:(NSString *)text escaping:(iTermSendTextEscaping)escaping;
- (BOOL)closeComposer;
- (void)didChangeScreen:(CGFloat)scaleFactor;
- (void)addContentSubscriber:(id<iTermContentSubscriber>)contentSubscriber;
- (void)didFinishRestoration;
- (void)performActionForCapturedOutput:(CapturedOutput *)capturedOutput;
- (void)userInitiatedReset;
- (void)resetForRelaunch;

#pragma mark - API

- (ITMGetBufferResponse *)handleGetBufferRequest:(ITMGetBufferRequest *)request;
- (void)handleGetPromptRequest:(ITMGetPromptRequest *)request
                    completion:(void (^)(ITMGetPromptResponse *response))completion;
- (void)handleListPromptsRequest:(ITMListPromptsRequest *)request
                      completion:(void (^)(ITMListPromptsResponse *response))completion;
- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request
                                            connectionKey:(NSString *)connectionKey;

- (ITMSetProfilePropertyResponse_Status)handleSetProfilePropertyForAssignments:(NSArray<iTermTuple<NSString *, id> *> *)tuples
                                                            scriptHistoryEntry:(iTermScriptHistoryEntry *)scriptHistoryEntry;

- (ITMGetProfilePropertyResponse *)handleGetProfilePropertyForKeys:(NSArray<NSString *> *)keys;

// Run a script-side function. Can include composition, references to variables.
// origin is used to show why the function was called and goes in the error's title. e.g., "Trigger".
- (void)invokeFunctionCall:(NSString *)invocation
                     scope:(iTermVariableScope *)scope
                    origin:(NSString *)origin;
- (void)setParentScope:(iTermVariableScope *)parentScope;

@end

