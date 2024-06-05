#import "PTYSession.h"
#import "PTYSession+ARC.h"
#import "PTYSession+Private.h"

#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "Coprocess.h"
#import "CVector.h"
#import "FakeWindow.h"
#import "FileTransferManager.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTerm.h"
#import "iTermAPIHelper.h"
#import "iTermActionsModel.h"
#import "iTermAddTriggerViewController.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermAutomaticProfileSwitcher.h"
#import "iTermBackgroundCommandRunner.h"
#import "iTermBackgroundDrawingHelper.h"
#import "iTermBadgeLabel.h"
#import "iTermBuriedSessions.h"
#import "iTermBuiltInFunctions.h"
#import "iTermCacheableImage.h"
#import "iTermCapturedOutputMark.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermColorPresets.h"
#import "iTermColorSuggester.h"
#import "iTermCommandRunnerPool.h"
#import "iTermComposerManager.h"
#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermController.h"
#import "iTermCopyModeHandler.h"
#import "iTermCopyModeState.h"
#import "iTermDisclosableView.h"
#import "iTermEchoProbe.h"
#import "iTermExpect.h"
#import "iTermExpressionEvaluator.h"
#import "iTermExpressionParser.h"
#import "iTermFindDriver.h"
#import "iTermFindOnPageHelper.h"
#import "iTermFindPasteboard.h"
#import "iTermGCD.h"
#import "iTermGraphicSource.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermModifyOtherKeysMapper1.h"
#import "iTermModifyOtherKeysMapper.h"
#import "iTermNaggingController.h"
#import "iTermNotificationController.h"
#import "iTermHapticActuator.h"
#import "iTermHistogram.h"
#import "iTermHotKeyController.h"
#import "iTermInitialDirectory.h"
#import "iTermKeyLabels.h"
#import "iTermLoggingHelper.h"
#import "iTermMalloc.h"
#import "iTermMetalClipView.h"
#import "iTermMultiServerJobManager.h"
#import "iTermObject.h"
#import "iTermOpenDirectory.h"
#import "iTermPreferences.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermSharedImageStore.h"
#import "iTermSnippetsModel.h"
#import "iTermStandardKeyMapper.h"
#import "iTermStatusBarUnreadCountController.h"
#import "iTermSoundPlayer.h"
#import "iTermRawKeyMapper.h"
#import "iTermTermkeyKeyMapper.h"
#import "iTermMetaFrustrationDetector.h"
#import "iTermMetalGlue.h"
#import "iTermMetalDriver.h"
#import "iTermMouseCursor.h"
#import "iTermNotificationCenter.h"
#import "iTermPasteHelper.h"
#import "iTermPreferences.h"
#import "iTermPrintGuard.h"
#import "iTermProcessCache.h"
#import "iTermProfilePreferences.h"
#import "iTermPromptOnCloseReason.h"
#import "iTermRecentDirectoryMO.h"
#import "iTermRestorableSession.h"
#import "iTermRule.h"
#import "iTermSavePanel.h"
#import "iTermScriptFunctionCall.h"
#import "iTermSecureKeyboardEntryController.h"
#import "iTermSelection.h"
#import "iTermSemanticHistoryController.h"
#import "iTermSessionFactory.h"
#import "iTermSessionHotkeyController.h"
#import "iTermSessionLauncher.h"
#import "iTermSessionNameController.h"
#import "iTermSessionTitleBuiltInFunction.h"
#import "iTermSetFindStringNotification.h"
#import "iTermShellHistoryController.h"
#import "iTermShortcut.h"
#import "iTermShortcutInputView.h"
#import "iTermSlowOperationGateway.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarLayout+tmux.h"
#import "iTermStatusBarViewController.h"
#import "iTermSwiftyString.h"
#import "iTermSwiftyStringGraph.h"
#import "iTermSwipeTracker.h"
#import "iTermSystemVersion.h"
#import "iTermTextExtractor.h"
#import "iTermTheme.h"
#import "iTermThroughputEstimator.h"
#import "iTermTmuxStatusBarMonitor.h"
#import "iTermTmuxOptionMonitor.h"
#import "iTermUpdateCadenceController.h"
#import "iTermURLMark.h"
#import "iTermURLStore.h"
#import "iTermUserDefaultsObserver.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Session.h"
#import "iTermWarning.h"
#import "iTermWebSocketCookieJar.h"
#import "iTermWorkingDirectoryPoller.h"
#import "MovePaneController.h"
#import "MovingAverage.h"
#import "NSAlert+iTerm.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+Profile.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSHost+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSPasteboard+iTerm.h"
#import "NSScreen+iTerm.h"
#import "NSStringITerm.h"
#import "NSThread+iTerm.h"
#import "NSURL+iTerm.h"
#import "NSUserDefaults+iTerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+PSM.h"
#import "NSWorkspace+iTerm.h"
#import "PasteContext.h"
#import "PasteEvent.h"
#import "PreferencePanel.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "ProfilesGeneralPreferencesViewController.h"
#import "PSMMinimalTabStyle.h"
#import "PTYNoteViewController.h"
#import "PTYTask.h"
#import "PTYTask+ProcessInfo.h"
#import "PTYTextView.h"
#import "PTYTextView+ARC.h"
#import "PTYWindow.h"
#import "RegexKitLite.h"
#import "SCPFile.h"
#import "SCPPath.h"
#import "SearchResult.h"
#import "SessionView.h"
#import "TaskNotifier.h"
#import "TerminalFile.h"
#import "TriggerController.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGateway.h"
#import "TmuxLayoutParser.h"
#import "TmuxStateParser.h"
#import "TmuxWindowOpener.h"
#import "Trigger.h"
#import "VT100DCSParser.h"
#import "VT100RemoteHost.h"
#import "VT100Screen.h"
#import "VT100ScreenConfiguration.h"
#import "VT100ScreenMark.h"
#import "VT100ScreenMutableState.h"
#import "VT100ScreenMutableState+Resizing.h"
#import "VT100Terminal.h"
#import "VT100Token.h"
#import "WindowArrangements.h"
#import "WindowControllerInterface.h"
#import <apr-1/apr_base64.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
#import <CoreFoundation/CoreFoundation.h>

static const NSInteger kMinimumUnicodeVersion = 8;
static const NSInteger kMaximumUnicodeVersion = 9;

static NSString *const PTYSessionDidRepairSavedArrangement = @"PTYSessionDidRepairSavedArrangement";

NSString *const PTYSessionCreatedNotification = @"PTYSessionCreatedNotification";
NSString *const PTYSessionTerminatedNotification = @"PTYSessionTerminatedNotification";
NSString *const PTYSessionRevivedNotification = @"PTYSessionRevivedNotification";
NSString *const iTermSessionWillTerminateNotification = @"iTermSessionDidTerminate";
NSString *const PTYSessionDidResizeNotification = @"PTYSessionDidResizeNotification";
NSString *const PTYSessionDidDealloc = @"PTYSessionDidDealloc";
NSString *const PTYCommandDidExitNotification = @"PTYCommandDidExitNotification";

NSString *const kPTYSessionTmuxFontDidChange = @"kPTYSessionTmuxFontDidChange";
NSString *const kPTYSessionCapturedOutputDidChange = @"kPTYSessionCapturedOutputDidChange";
static NSString *const kSuppressAnnoyingBellOffer = @"NoSyncSuppressAnnyoingBellOffer";
static NSString *const kSilenceAnnoyingBellAutomatically = @"NoSyncSilenceAnnoyingBellAutomatically";

static NSString *const kTurnOffMouseReportingOnHostChangeUserDefaultsKey = @"NoSyncTurnOffMouseReportingOnHostChange";
static NSString *const kTurnOffFocusReportingOnHostChangeUserDefaultsKey = @"NoSyncTurnOffFocusReportingOnHostChange";

static NSString *const kTurnOffMouseReportingOnHostChangeAnnouncementIdentifier = @"TurnOffMouseReportingOnHostChange";
static NSString *const kTurnOffFocusReportingOnHostChangeAnnouncementIdentifier = @"TurnOffFocusReportingOnHostChange";

static NSString *const kShellIntegrationOutOfDateAnnouncementIdentifier =
    @"kShellIntegrationOutOfDateAnnouncementIdentifier";

static NSString *TERM_ENVNAME = @"TERM";
static NSString *COLORFGBG_ENVNAME = @"COLORFGBG";
static NSString *PWD_ENVNAME = @"PWD";
static NSString *PWD_ENVVALUE = @"~";
static NSString *PATH_ENVNAME = @"PATH";

// Constants for saved window arrangement keys.
static NSString *const SESSION_ARRANGEMENT_COLUMNS = @"Columns";
static NSString *const SESSION_ARRANGEMENT_ROWS = @"Rows";
static NSString *const SESSION_ARRANGEMENT_BOOKMARK = @"Bookmark";
static NSString *const __attribute__((unused)) SESSION_ARRANGEMENT_BOOKMARK_NAME_DEPRECATED = @"Bookmark Name";
static NSString *const SESSION_ARRANGEMENT_WORKING_DIRECTORY = @"Working Directory";
static NSString *const SESSION_ARRANGEMENT_CONTENTS = @"Contents";
// Not static because the ARC category uses it.
NSString *const SESSION_ARRANGEMENT_TMUX_PANE = @"Tmux Pane";
static NSString *const SESSION_ARRANGEMENT_TMUX_HISTORY = @"Tmux History";
static NSString *const SESSION_ARRANGEMENT_TMUX_ALT_HISTORY = @"Tmux AltHistory";
static NSString *const SESSION_ARRANGEMENT_TMUX_STATE = @"Tmux State";
static NSString *const SESSION_ARRANGEMENT_TMUX_TAB_COLOR = @"Tmux Tab Color";
static NSString *const SESSION_ARRANGEMENT_IS_TMUX_GATEWAY = @"Is Tmux Gateway";
static NSString *const SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME = @"Tmux Gateway Session Name";
static NSString *const SESSION_ARRANGEMENT_TMUX_DCS_ID = @"Tmux DCS ID";
static NSString *const SESSION_ARRANGEMENT_CONDUCTOR_DCS_ID = @"Conductor DCS ID";
static NSString *const SESSION_ARRANGEMENT_CONDUCTOR_TREE = @"Conductor Parser Tree";
static NSString *const SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID = @"Tmux Gateway Session ID";
static NSString *const SESSION_ARRANGEMENT_TMUX_FOCUS_REPORTING = @"Tmux Focus Reporting";
static NSString *const SESSION_ARRANGEMENT_NAME_CONTROLLER_STATE = @"Name Controller State";
static NSString *const __attribute__((unused)) DEPRECATED_SESSION_ARRANGEMENT_DEFAULT_NAME_DEPRECATED = @"Session Default Name";  // manually set name
static NSString *const __attribute__((unused)) DEPRECATED_SESSION_ARRANGEMENT_WINDOW_TITLE_DEPRECATED = @"Session Window Title";  // server-set window name
static NSString *const __attribute__((unused)) DEPRECATED_SESSION_ARRANGEMENT_NAME_DEPRECATED = @"Session Name";  // server-set "icon" (tab) name
static NSString *const SESSION_ARRANGEMENT_GUID = @"Session GUID";  // A truly unique ID.
static NSString *const SESSION_ARRANGEMENT_LIVE_SESSION = @"Live Session";  // If zoomed, this gives the "live" session's arrangement.
static NSString *const SESSION_ARRANGEMENT_SUBSTITUTIONS = @"Substitutions";  // Dictionary for $$VAR$$ substitutions
static NSString *const SESSION_UNIQUE_ID = @"Session Unique ID";  // DEPRECATED. A string used for restoring soft-terminated sessions for arrangements that predate the introduction of the GUID.
static NSString *const SESSION_ARRANGEMENT_SERVER_PID = @"Server PID";  // PID for server process for restoration. Only for monoserver.
// Not static because the ARC category uses it.
NSString *const SESSION_ARRANGEMENT_SERVER_DICT = @"Server Dict";  // NSDictionary. Describes server connection. Only for multiserver.
// TODO: Make server report the TTY to us since orphans will end up with a nil tty.
static NSString *const SESSION_ARRANGEMENT_TTY = @"TTY";  // TTY name. Used when using restoration to connect to a restored server.
static NSString *const SESSION_ARRANGEMENT_VARIABLES = @"Variables";  // _variables
// static NSString *const SESSION_ARRANGEMENT_COMMAND_RANGE_DEPRECATED = @"Command Range";  // VT100GridCoordRange
// Deprecated in favor of SESSION_ARRANGEMENT_SHOULD_EXPECT_PROMPT_MARKS and SESSION_ARRANGEMENT_SHOULD_EXPECT_CURRENT_DIR_UPDATES
static NSString *const SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED_DEPRECATED = @"Shell Integration Ever Used";  // BOOL

// This really belongs in VT100Screen but it's here for historical reasons.
static NSString *const SESSION_ARRANGEMENT_SHOULD_EXPECT_PROMPT_MARKS = @"Should Expect Prompt Marks";  // BOOL
static NSString *const SESSION_ARRANGEMENT_SHOULD_EXPECT_CURRENT_DIR_UPDATES = @"Should Expect Current Dir Updates";  // BOOL

static NSString *const SESSION_ARRANGEMENT_WORKING_DIRECTORY_POLLER_DISABLED = @"Working Directory Poller Disabled";  // BOOL
static NSString *const SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK = @"Alert on Next Mark";  // BOOL
static NSString *const SESSION_ARRANGEMENT_COMMANDS = @"Commands";  // Array of strings
static NSString *const SESSION_ARRANGEMENT_DIRECTORIES = @"Directories";  // Array of strings
static NSString *const SESSION_ARRANGEMENT_HOSTS = @"Hosts";  // Array of VT100RemoteHost
static NSString *const SESSION_ARRANGEMENT_CURSOR_GUIDE = @"Cursor Guide";  // BOOL
static NSString *const SESSION_ARRANGEMENT_LAST_DIRECTORY = @"Last Directory";  // NSString
static NSString *const SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY = @"Last Local Directory";  // NSString
static NSString *const SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY_WAS_PUSHED = @"Last Local Directory Was Pushed";  // BOOL
static NSString *const SESSION_ARRANGEMENT_LAST_DIRECTORY_IS_UNSUITABLE_FOR_OLD_PWD_DEPRECATED = @"Last Directory Is Remote";  // BOOL
static NSString *const SESSION_ARRANGEMENT_SELECTION = @"Selection";  // Dictionary for iTermSelection.
static NSString *const SESSION_ARRANGEMENT_APS = @"Automatic Profile Switching";  // Dictionary of APS state.

static NSString *const SESSION_ARRANGEMENT_PROGRAM = @"Program";  // Dictionary. See kProgram constants below.
static NSString *const SESSION_ARRANGEMENT_ENVIRONMENT = @"Environment";  // Dictionary of environment vars program was run in
static NSString *const SESSION_ARRANGEMENT_KEYLABELS = @"Key Labels";  // Dictionary string -> string
static NSString *const SESSION_ARRANGEMENT_KEYLABELS_STACK = @"Key Labels Stack";  // Array of encoded iTermKeyLables dicts
static NSString *const SESSION_ARRANGEMENT_IS_UTF_8 = @"Is UTF-8";  // TTY is in utf-8 mode
static NSString *const SESSION_ARRANGEMENT_HOTKEY = @"Session Hotkey";  // NSDictionary iTermShortcut dictionaryValue
static NSString *const SESSION_ARRANGEMENT_FONT_OVERRIDES = @"Font Overrides";  // Not saved; just used internally when creating a new tmux session.
static NSString *const SESSION_ARRANGEMENT_KEYBOARD_MAP_OVERRIDES = @"Keyboard Map Overrides";  // Not saved; just used internally when creating a new tmux session.
static NSString *const SESSION_ARRANGEMENT_SHORT_LIVED_SINGLE_USE = @"Short Lived Single Use";  // BOOL
static NSString *const SESSION_ARRANGEMENT_HOSTNAME_TO_SHELL = @"Hostname to Shell";  // NSString -> NSString (example: example.com -> fish)
static NSString *const SESSION_ARRANGEMENT_CURSOR_TYPE_OVERRIDE = @"Cursor Type Override";  // NSNumber wrapping ITermCursorType
static NSString *const SESSION_ARRANGEMENT_AUTOLOG_FILENAME = @"AutoLog File Name";  // NSString. New as of 12/4/19
static NSString *const SESSION_ARRANGEMENT_REUSABLE_COOKIE = @"Reusable Cookie";  // NSString.
static NSString *const SESSION_ARRANGEMENT_OVERRIDDEN_FIELDS = @"Overridden Fields";  // NSArray<NSString *>
static NSString *const SESSION_ARRANGEMENT_FILTER = @"Filter";  // NSString
static NSString *const SESSION_ARRANGEMENT_SSH_STATE = @"SSH State";  // NSNumber
static NSString *const SESSION_ARRANGEMENT_CONDUCTOR = @"Conductor";  // NSString (json)
static NSString *const SESSION_ARRANGEMENT_PENDING_JUMPS = @"Pending Jumps";  // NSArray<NSString *>, optional.

// Keys for dictionary in SESSION_ARRANGEMENT_PROGRAM
static NSString *const kProgramType = @"Type";  // Value will be one of the kProgramTypeXxx constants.
static NSString *const kProgramCommand = @"Command";  // For kProgramTypeCommand: value is command to run.
static NSString *const kCustomShell = @"Custom Shell";

// Values for kProgramType
static NSString *const kProgramTypeShellLauncher = @"Shell Launcher";  // Use ShellLauncher --launch_shell
static NSString *const kProgramTypeCommand = @"Command";  // Use command in kProgramCommand
static NSString *const kProgramTypeCustomShell = @"Custom Shell";

static NSString *kTmuxFontChanged = @"kTmuxFontChanged";

// Value for SESSION_ARRANGEMENT_TMUX_TAB_COLOR that means "don't use the
// default color from the tmux profile; this tab should have no color."
static NSString *const iTermTmuxTabColorNone = @"none";

static NSString *PTYSessionAnnouncementIdentifierTmuxPaused = @"tmuxPaused";

// Maps Session GUID to saved contents. Only live between window restoration
// and the end of startup activities.
static NSMutableDictionary *gRegisteredSessionContents;

// Grace period to avoid failing to write anti-idle code when timer runs just before when the code
// should be sent.
static const NSTimeInterval kAntiIdleGracePeriod = 0.1;

// Limit for number of entries in self.directories, self.commands, self.hosts.
// Keeps saved state from exploding like in issue 5029.
static const NSUInteger kMaxDirectories = 100;
static const NSUInteger kMaxCommands = 100;
static const NSUInteger kMaxHosts = 100;
static const CGFloat PTYSessionMaximumMetalViewSize = 16384;

static NSString *const kSuppressCaptureOutputRequiresShellIntegrationWarning =
    @"NoSyncSuppressCaptureOutputRequiresShellIntegrationWarning";
static NSString *const kSuppressCaptureOutputToolNotVisibleWarning =
    @"NoSyncSuppressCaptureOutputToolNotVisibleWarning";

// This one cannot be suppressed.
static NSString *const kTwoCoprocessesCanNotRunAtOnceAnnouncementIdentifier =
    @"NoSyncTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier";

static char iTermEffectiveAppearanceKey;

@interface NSWindow (SessionPrivate)
- (void)_moveToScreen:(NSScreen *)sender;
@end

typedef NS_ENUM(NSUInteger, iTermSSHState) {
    // Normal state.
    iTermSSHStateNone,

    // Waiting for conductor just after creating the session with ssh as the command.
    iTermSSHStateProfile,
};

@interface PTYSession(AppSwitching)<iTermAppSwitchingPreventionDetectorDelegate>
@end

@implementation PTYSession {
    NSString *_termVariable;

    // Has the underlying connection been closed?
    BOOL _exited;

    // A view that wraps the textview. It is the scrollview's document. This exists to provide a
    // top margin above the textview.
    TextViewWrapper *_wrapper;

    // Anti-idle timer that sends a character every so often to the host.
    NSTimer *_antiIdleTimer;

    // The bookmark the session was originally created with so those settings can be restored if
    // needed.
    Profile *_originalProfile;

    // Time since reference date when last keypress was received.
    NSTimeInterval _lastInput;

    // Time since reference date when the tab label was last updated.
    NSTimeInterval _lastUpdate;

    // This is used for divorced sessions. It contains the keys in profile
    // that have been customized. Changes in the original profile will be copied over
    // to profile except for these keys.
    NSMutableSet *_overriddenFields;

    // A digital video recorder for this session that implements the instant replay feature. These
    // are non-null while showing instant replay.
    DVR *_dvr;
    DVRDecoder *_dvrDecoder;

    // Set only if this is not a live session (we are showing instant replay). Is a pointer to the
    // hidden live session while looking at the past.
    PTYSession *_liveSession;

    // Is the update timer's callback currently running?
    BOOL _timerRunning;

    // Time session was created
    NSDate *_creationDate;

    // If not nil, we're aggregating text to append to a pasteboard. The pasteboard will be
    // updated when this is set to nil.
    NSString *_pasteboard;
    NSMutableData *_pbtext;

    // Does the terminal think this session is focused?
    BOOL _focused;

    FindContext *_tailFindContext;
    NSTimer *_tailFindTimer;
    // A one-shot tail find runs even though the find view is invisible. Once it's done searching,
    // it doesn't restart itself until the user does cmd-g again. See issue 9964.
    BOOL _performingOneShotTailFind;

    TmuxGateway *_tmuxGateway;
    BOOL _haveKickedOffTmux;
    BOOL _tmuxSecureLogging;
    // The tmux rename-window command is only sent when the name field resigns first responder.
    // This tracks if a tmux client's name has changed but the tmux server has not been informed yet.
    BOOL _tmuxTitleOutOfSync;
    PTYSessionTmuxMode _tmuxMode;
    BOOL _tmuxWindowClosingByClientRequest;
    // This is the write end of a pipe for tmux clients. The read end is in TaskNotifier.
    NSFileHandle *_tmuxClientWritePipe;
    NSInteger _requestAttentionId;  // Last request-attention identifier

    VT100GridAbsCoordRange _lastOrCurrentlyRunningCommandAbsRange;

    NSTimeInterval _timeOfLastScheduling;

    dispatch_semaphore_t _executionSemaphore;

    // Previous updateDisplay timer's timeout period (not the actual duration,
    // but the kXXXTimerIntervalSec value).
    NSTimeInterval _lastTimeout;

    // In order to correctly draw a tiled background image, we must first draw
    // it into an image the size of the session view, and then blit from it
    // onto the background of whichever view needs a background. This ensures
    // the tessellation is consistent.
    NSImage *_patternedImage;

    // Mouse reporting state
    VT100GridCoord _lastReportedCoord;
    NSPoint _lastReportedPoint;

    // Remembers if the mouse down was reported to decide if mouse up should also be reported.
    BOOL _reportingLeftMouseDown;
    BOOL _reportingMiddleMouseDown;
    BOOL _reportingRightMouseDown;

    // Did we get CurrentDir code?
    BOOL _shouldExpectCurrentDirUpdates;

    // Disable the working directory poller?
    BOOL _workingDirectoryPollerDisabled;

    // Has the user or an escape code change the cursor guide setting?
    // If so, then the profile setting will be disregarded.
    BOOL _cursorGuideSettingHasChanged;

    // Maps announcement identifiers to view controllers.
    NSMutableDictionary *_announcements;

    // Moving average of time between bell rings
    MovingAverage *_bellRate;
    NSTimeInterval _lastBell;
    NSTimeInterval _ignoreBellUntil;
    NSTimeInterval _annoyingBellOfferDeclinedAt;
    BOOL _suppressAllOutput;

    // Session should auto-restart after the pipe breaks.
    BOOL _shouldRestart;

    // Synthetic sessions are used for "zoom in" and DVR, and their closing cannot be undone.
    BOOL _synthetic;

    // Cached advanced setting
    NSTimeInterval _idleTime;

    // Current unicode version.
    NSInteger _unicodeVersion;

    // Touch bar labels for function keys.
    NSMutableDictionary<NSString *, NSString *> *_keyLabels;
    NSMutableArray<iTermKeyLabels *> *_keyLabelsStack;

    // The containing window is in the midst of a live resize. The update timer
    // runs in the common modes runloop in this case. That's not acceptable
    // for normal use for reasons that Apple leaves up to your imagination (it
    // doesn't fire while you hold down a key, for example), but it does fire
    // during live resize (unlike the default runloops).
    BOOL _inLiveResize;

    id<VT100RemoteHostReading> _currentHost;

    NSMutableDictionary<id, ITMNotificationRequest *> *_keystrokeSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_keyboardFilterSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_updateSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_promptSubscriptions;
    NSMutableDictionary<id, ITMNotificationRequest *> *_customEscapeSequenceNotifications;

    // Used by auto-hide. We can't auto hide the tmux gateway session until at least one window has been opened.
    BOOL _hideAfterTmuxWindowOpens;

    BOOL _useAdaptiveFrameRate;
    NSInteger _adaptiveFrameRateThroughputThreshold;

    uint32_t _autoLogId;

    iTermSessionModeHandler *_modeHandler;

    // Absolute line number where touchbar status changed.
    long long _statusChangedAbsLine;

    iTermUpdateCadenceController *_cadenceController;

    iTermMetalGlue *_metalGlue NS_AVAILABLE_MAC(10_11);

    int _updateCount;
    BOOL _metalFrameChangePending;
    int _nextMetalDisabledToken;
    NSMutableSet *_metalDisabledTokens;
    BOOL _metalDeviceChanging;

    iTermVariables *_userVariables;
    iTermSwiftyString *_badgeSwiftyString;
    iTermSwiftyString *_autoNameSwiftyString;
    iTermSwiftyString *_subtitleSwiftyString;

    iTermBackgroundDrawingHelper *_backgroundDrawingHelper;
    iTermMetaFrustrationDetector *_metaFrustrationDetector;

    iTermTmuxStatusBarMonitor *_tmuxStatusBarMonitor;
    iTermWorkingDirectoryPoller *_pwdPoller;
    iTermTmuxOptionMonitor *_tmuxTitleMonitor;
    iTermTmuxOptionMonitor *_tmuxForegroundJobMonitor;
    iTermTmuxOptionMonitor *_paneIndexMonitor;

    iTermGraphicSource *_graphicSource;
    iTermVariableReference *_jobPidRef;
    iTermCacheableImage *_customIcon;
    CGContextRef _metalContext;
    BOOL _errorCreatingMetalContext;

    id<iTermKeyMapper> _keyMapper;
    iTermKeyMappingMode _keyMappingMode;

    NSString *_badgeFontName;
    iTermVariableScope *_variablesScope;
    
    BOOL _showingVisualIndicatorForEsc;

    iTermPrintGuard *_printGuard;
    iTermBuiltInFunctions *_methods;

    // When this is true, changing the font size does not cause the window size to change.
    BOOL _windowAdjustmentDisabled;
    NSSize _badgeLabelSizeFraction;

    // To debug a problem where a session is divorced but its guid is not in the sessions instance profile model.
    NSString *_divorceDecree;

    BOOL _cursorTypeOverrideChanged;
    BOOL _titleDirty;
    // May be stale, but allows us to update titles fast after an OSC 0/1/2
    iTermProcessInfo *_lastProcessInfo;
    iTermLoggingHelper *_logging;
    iTermNaggingController *_naggingController;
    BOOL _tmuxTTLHasThresholds;
    NSTimeInterval _tmuxTTLLowerThreshold;
    NSTimeInterval _tmuxTTLUpperThreshold;
    // If nonnil, gives the GUID of the session from the arrangement that created it. Often this
    // will differ from its real GUID. It only serves to find the session in the arrangement to
    // make repairs.
    NSString *_arrangementGUID;

    VT100GridSize _savedGridSize;

    iTermActivityInfo _activityInfo;
    TriggerController *_triggerWindowController;

    // If positive focus reports will not be sent.
    NSInteger _disableFocusReporting;

    BOOL _initializationFinished;
    BOOL _needsJiggle;

    // Have we finished loading the address book and color map initially?
    BOOL _profileInitialized;
    iTermUserDefaultsObserver *_disableTransparencyInKeyWindowObserver;
    VT100MutableScreenConfiguration *_config;

    BOOL _profileDidChange;
    NSInteger _estimatedThroughput;
    iTermPasteboardReporter *_pasteboardReporter;
    iTermConductor *_conductor;
    iTermSSHState _sshState;
    // (unique ID, hostname)
    NSMutableData *_sshWriteQueue;
    BOOL _jiggleUponAttach;

    // Are we currently enqueuing the bytes to write a focus report?
    BOOL _reportingFocus;

    AITermControllerObjC *_aiterm;
    NSMutableArray<NSString *> *_commandQueue;
    NSMutableArray<iTermSSHReconnectionInfo *> *_pendingJumps;

    // If true the session was just created and an offscreen mark alert would be annoying.
    BOOL _temporarilySuspendOffscreenMarkAlerts;
    NSMutableArray<NSData *> *_dataQueue;

    BOOL _promptStateAllowsAutoComposer;
    NSArray<ScreenCharArray *> *_desiredComposerPrompt;

    iTermLocalFileChecker *_localFileChecker;
    BOOL _needsComposerColorUpdate;

    // Run this when the composer connects.
    void (^_pendingConductor)(PTYSession *);
    BOOL _connectingSSH;
    NSMutableData *_queuedConnectingSSH;

    __weak id<VT100ScreenMarkReading> _selectedCommandMark;
    NSMutableArray<PTYSessionHostState *> *_hostStack;
}

@synthesize isDivorced = _divorced;

+ (NSMapTable<NSString *, PTYSession *> *)sessionMap {
    static NSMapTable *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSPointerFunctionsOptions weakWeak = (NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality);
        map = [[NSMapTable alloc] initWithKeyOptions:weakWeak
                                        valueOptions:weakWeak
                                            capacity:1];
    });
    return map;
}

+ (void)registerBuiltInFunctions {
    [iTermSessionTitleBuiltInFunction registerBuiltInFunction];
}

+ (void)registerSessionInArrangement:(NSDictionary *)arrangement {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gRegisteredSessionContents = [[NSMutableDictionary alloc] init];
    });
    NSString *guid = arrangement[SESSION_ARRANGEMENT_GUID];
    NSDictionary *contents = arrangement[SESSION_ARRANGEMENT_CONTENTS];
    if (guid && contents) {
        DLog(@"Register arrangement for %@", arrangement[SESSION_ARRANGEMENT_GUID]);
        gRegisteredSessionContents[guid] = contents;
    }
}

+ (void)removeAllRegisteredSessions {
    DLog(@"Remove all registered sessions");
    [gRegisteredSessionContents removeAllObjects];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    assert(NO);
    return [self initSynthetic:NO];
}

- (instancetype)initSynthetic:(BOOL)synthetic {
    self = [super init];
    if (self) {
        DLog(@"Begin initialization of new PTYsession %p", self);
        _autoLogId = arc4random();
        _useAdaptiveFrameRate = [iTermAdvancedSettingsModel useAdaptiveFrameRate];
        _adaptiveFrameRateThroughputThreshold = [iTermAdvancedSettingsModel adaptiveFrameRateThroughputThreshold];
        _idleTime = [iTermAdvancedSettingsModel idleTimeSeconds];

        // The new session won't have the move-pane overlay, so just exit move pane
        // mode.
        [[MovePaneController sharedInstance] exitMovePaneMode];
        _lastInput = [NSDate timeIntervalSinceReferenceDate];
        _modeHandler = [[iTermSessionModeHandler alloc] init];
        _modeHandler.delegate = self;

        _lastOutputIgnoringOutputAfterResizing = _lastInput;
        _lastUpdate = _lastInput;
        _pasteHelper = [[iTermPasteHelper alloc] init];
        _pasteHelper.delegate = self;

        // Allocate screen, shell, and terminal objects
        _shell = [[PTYTask alloc] init];
        // Allocate a guid. If we end up restoring from a session during startup this will be replaced.
        _guid = [[NSString uuid] retain];
        [[PTYSession sessionMap] setObject:self forKey:_guid];

        _screen = [[VT100Screen alloc] init];
        NSParameterAssert(_shell != nil && _screen != nil);

        _overriddenFields = [[NSMutableSet alloc] init];

        _variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession
                                                       owner:self];
        // Alias for legacy paths
        [self.variablesScope setValue:_variables forVariableNamed:@"session" weak:YES];
        _userVariables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                           owner:self];
        [self.variablesScope setValue:_userVariables forVariableNamed:@"user"];

        _creationDate = [[NSDate date] retain];
        NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
        dateFormatter.dateFormat = @"yyyyMMdd_HHmmss";
        [self.variablesScope setValue:[dateFormatter stringFromDate:_creationDate]
                     forVariableNamed:iTermVariableKeySessionCreationTimeString];
        [self.variablesScope setValue:[@(_autoLogId) stringValue] forVariableNamed:iTermVariableKeySessionAutoLogID];
        [self.variablesScope setValue:_guid forVariableNamed:iTermVariableKeySessionID];
        [self.variablesScope setValue:@"" forVariableNamed:iTermVariableKeySessionSelection];
        [self.variablesScope setValue:@0 forVariableNamed:iTermVariableKeySessionSelectionLength];
        [self.variablesScope setValue:@NO forVariableNamed:iTermVariableKeySessionShowingAlternateScreen];
        [self.variablesScope setValue:NSHomeDirectory() forVariableNamed:iTermVariableKeySessionHomeDirectory];
        [self.variablesScope setValue:@0 forVariableNamed:iTermVariableKeySSHIntegrationLevel];
        self.variablesScope.shell = [self bestGuessAtUserShell];
        self.variablesScope.uname = [self bestGuessAtUName];

        _variables.primaryKey = iTermVariableKeySessionID;
        _jobPidRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionJobPid
                                                           vendor:self.variablesScope];
        __weak __typeof(self) weakSelf = self;
        _jobPidRef.onChangeBlock = ^{
            [weakSelf jobPidDidChange];
        };

        [_autoNameSwiftyString invalidate];
        [_autoNameSwiftyString autorelease];
        _autoNameSwiftyString = [[iTermSwiftyString alloc] initWithScope:self.variablesScope
                                                              sourcePath:iTermVariableKeySessionAutoNameFormat
                                                         destinationPath:iTermVariableKeySessionAutoName];
        _autoNameSwiftyString.observer = ^NSString *(NSString * _Nonnull newValue, NSError *error) {
            if ([weakSelf checkForCyclesInSwiftyStrings]) {
                weakSelf.variablesScope.autoNameFormat = @"[Cycle detected]";
            }
            return newValue;
        };

        _tmuxSecureLogging = NO;
        _tailFindContext = [[FindContext alloc] init];
        _lastOrCurrentlyRunningCommandAbsRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _activityCounter = [@0 retain];
        _announcements = [[NSMutableDictionary alloc] init];
        _commands = [[NSMutableArray alloc] init];
        _directories = [[NSMutableArray alloc] init];
        _hosts = [[NSMutableArray alloc] init];
        _hostnameToShell = [[NSMutableDictionary alloc] init];
        _automaticProfileSwitcher = [[iTermAutomaticProfileSwitcher alloc] initWithDelegate:self];
        _cadenceController = [[iTermUpdateCadenceController alloc] init];
        _cadenceController.delegate = self;

        _keystrokeSubscriptions = [[NSMutableDictionary alloc] init];
        _keyboardFilterSubscriptions = [[NSMutableDictionary alloc] init];
        _updateSubscriptions = [[NSMutableDictionary alloc] init];
        _promptSubscriptions = [[NSMutableDictionary alloc] init];
        _customEscapeSequenceNotifications = [[NSMutableDictionary alloc] init];
        _metalDisabledTokens = [[NSMutableSet alloc] init];
        _statusChangedAbsLine = -1;
        _nameController = [[iTermSessionNameController alloc] init];
        _nameController.delegate = self;
        _metalGlue = [[iTermMetalGlue alloc] init];
        _metalGlue.delegate = self;
        _metalGlue.screen = _screen;
        _metaFrustrationDetector = [[iTermMetaFrustrationDetector alloc] init];
        _metaFrustrationDetector.delegate = self;
        _pwdPoller = [[iTermWorkingDirectoryPoller alloc] init];
        _pwdPoller.delegate = self;
        _graphicSource = [[iTermGraphicSource alloc] init];
        _commandQueue = [[NSMutableArray alloc] init];
        _alertOnMarksinOffscreenSessions = [iTermPreferences boolForKey:kPreferenceKeyAlertOnMarksInOffscreenSessions];
        _pendingPublishRequests = [[NSMutableArray alloc] init];

        // This is a placeholder. When the profile is set it will get updated.
        iTermStandardKeyMapper *standardKeyMapper = [[iTermStandardKeyMapper alloc] init];
        standardKeyMapper.delegate = self;
        _keyMapper = standardKeyMapper;
        _disableTransparencyInKeyWindowObserver = [[iTermUserDefaultsObserver alloc] init];
        [_disableTransparencyInKeyWindowObserver observeKey:kPreferenceKeyDisableTransparencyForKeyWindow block:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf useTransparencyDidChange];
            });
        }];
        _expect = [[iTermExpect alloc] initDry:YES];
        _sshState = iTermSSHStateNone;
        _hostStack = [[NSMutableArray alloc] init];
        [iTermCPUUtilization instanceForSessionID:_guid];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(coprocessChanged)
                                                     name:kCoprocessStatusChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionContentsChanged:)
                                                     name:@"iTermTabContentsChanged"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(synchronizeTmuxFonts:)
                                                     name:kTmuxFontChanged
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(terminalFileShouldStop:)
                                                     name:kTerminalFileShouldStopNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(profileSessionNameDidEndEditing:)
                                                     name:kProfileSessionNameDidEndEditing
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionHotkeyDidChange:)
                                                     name:kProfileSessionHotkeyDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(apiServerUnsubscribe:)
                                                     name:iTermRemoveAPIServerSubscriptionsNotification
                                                   object:nil];
        // Detach before windows get closed. That's why we have to use the
        // iTermApplicationWillTerminate notification instead of
        // NSApplicationWillTerminate, since this gets run before the windows
        // are released.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminate:)
                                                     name:iTermApplicationWillTerminate
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedArrangementWasRepaired:)
                                                     name:PTYSessionDidRepairSavedArrangement
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowWillStartLiveResize:)
                                                     name:NSWindowWillStartLiveResizeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidEndLiveResize:)
                                                     name:NSWindowDidEndLiveResizeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(apiDidStop:)
                                                     name:iTermAPIHelperDidStopNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxWillKillWindow:)
                                                     name:iTermTmuxControllerWillKillWindow
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidResignActive:)
                                                     name:NSApplicationDidResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refreshTerminal:)
                                                     name:kRefreshTerminalNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(metalClipViewWillScroll:)
                                                     name:iTermMetalClipViewWillScroll
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(alertOnMarksinOffscreenSessionsDidChange:)
                                                     name:iTermDidToggleAlertOnMarksInOffscreenSessionsNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidMiniaturize:)
                                                     name:@"iTermWindowWillMiniaturize"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(autoComposerDidChange:)
                                                     name:iTermAutoComposerDidChangeNotification
                                                   object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(activeSpaceDidChange:)
                                                                   name:NSWorkspaceActiveSpaceDidChangeNotification
                                                                 object:nil];
        [[NSUserDefaults standardUserDefaults] it_addObserverForKey:kPreferenceKeyTabStyle
                                                              block:^(id _Nonnull newValue) {
                                                                  [weakSelf themeDidChange];
                                                              }];
        [NSApp addObserver:self
                forKeyPath:@"effectiveAppearance"
                   options:NSKeyValueObservingOptionNew
                   context:&iTermEffectiveAppearanceKey];

        [[iTermFindPasteboard sharedInstance] addObserver:self block:^(id sender, NSString * _Nonnull newValue, BOOL internallyGenerated) {
            if (!weakSelf.view.window.isKeyWindow) {
                return;
            }
            if (![iTermAdvancedSettingsModel synchronizeQueryWithFindPasteboard] && sender != weakSelf) {
                return;
            }
            if (internallyGenerated) {
                [weakSelf findPasteboardStringDidChangeTo:newValue];
            }
        }];

        if (!synthetic) {
            [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionCreatedNotification object:self];
        }
        _profileDidChange = YES;
        _config = [[VT100MutableScreenConfiguration alloc] init];
        [self sync];
        DLog(@"Done initializing new PTYSession %@", self);
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)dealloc {
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance"];
    NSString *guid = [_guid copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionDidDealloc object:[guid autorelease]];
    });
    if (_textview.delegate == self) {
        _textview.delegate = nil;
    }
    [_view release];
    [_logging stop];
    if (@available(macOS 10.11, *)) {
        [_metalGlue release];
    }
    [_nameController release];
    [self stopTailFind];  // This frees the substring in the tail find context, if needed.
    _shell.delegate = nil;
    [_pasteboard release];
    [_pbtext release];
    [_creationDate release];
    [_activityCounter release];
    [_termVariable release];
    [_colorFgBgVariable release];
    [_profile release];
    [_overriddenFields release];
    _pasteHelper.delegate = nil;
    [_pasteHelper release];
    [_backgroundImagePath release];
    [_backgroundImage release];
    [_antiIdleTimer invalidate];
    [_cadenceController release];
    [_originalProfile release];
    [_liveSession release];
    [_tmuxGateway release];
    [_tmuxController release];
    [_download stop];
    [_download endOfData];
    [_download release];
    [_upload stop];
    [_upload endOfData];
    [_upload release];
    [_shell release];
    [_screen release];
    [_tailFindContext release];
    [_patternedImage release];
    [_announcements release];
    [_variables release];
    [_userVariables release];
    [_program release];
    [_customShell release];
    [_environment release];
    [_commands release];
    [_directories release];
    [_hosts release];
    [_bellRate release];
    [iTermCPUUtilization setInstance:nil forSessionID:_guid];
    [_guid release];
    [_lastCommand release];
    [_substitutions release];
    [_automaticProfileSwitcher release];

    [_keyLabels release];
    [_keyLabelsStack release];
    [_currentHost release];
    [_hostnameToShell release];

    [_keystrokeSubscriptions release];
    [_keyboardFilterSubscriptions release];
    [_updateSubscriptions release];
    [_promptSubscriptions release];
    [_customEscapeSequenceNotifications release];

    [_modeHandler release];
    [_metalDisabledTokens release];
    [_badgeSwiftyString release];
    [_subtitleSwiftyString release];
    [_autoNameSwiftyString release];
    [_statusBarViewController release];
    [_backgroundDrawingHelper release];
    [_metaFrustrationDetector release];
    [_tmuxStatusBarMonitor setActive:NO];
    [_tmuxStatusBarMonitor release];
    [_tmuxTitleMonitor release];
    [_tmuxForegroundJobMonitor invalidate];
    [_tmuxForegroundJobMonitor release];
    [_paneIndexMonitor invalidate];
    [_paneIndexMonitor release];
    if (_metalContext) {
        CGContextRelease(_metalContext);
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_dvrDecoder) {
        [_dvr releaseDecoder:_dvrDecoder];
        [_dvr release];
    }

    [_cursorGuideColor release];
    [_lastDirectory release];
    [_lastLocalDirectory release];
    [_lastRemoteHost release];
    [_textview release];  // I'm not sure it's ever nonnil here
    [_currentMarkOrNotePosition release];
    [_pwdPoller release];
    [_graphicSource release];
    [_jobPidRef release];
    [_customIcon release];
    [_keyMapper release];
    [_badgeFontName release];
    [_variablesScope release];
    [_printGuard release];
    [_methods release];
    [_divorceDecree release];
    [_cursorTypeOverride release];
    [_lastProcessInfo release];
    _logging.rawLogger = nil;
    _logging.cookedLogger = nil;
    [_logging release];
    [_naggingController release];
    [_pasteBracketingOopsieExpectation release];
    if (_cookie) {
        [[iTermWebSocketCookieJar sharedInstance] removeCookie:_cookie];
        [_cookie release];
    }
    [_composerManager release];
    [_tmuxClientWritePipe release];
    [_arrangementGUID release];
    [_triggerWindowController release];
    [_filter release];
    [_asyncFilter cancel];
    [_asyncFilter release];
    [_contentSubscribers release];
    [_foundingArrangement release];
    [_disableTransparencyInKeyWindowObserver release];
    [_preferredProxyIcon release];
    [_savedStateForZoom release];
    [_config release];
    [_expect release];
    [_pasteboardReporter release];
    [_conductor release];
    [_sshWriteQueue release];
    [_lastNonFocusReportingWrite release];
    [_lastFocusReportDate release];
    [_aiterm release];
    [_commandQueue release];
    [_pendingJumps release];
    [_dataQueue release];
    [_pendingPublishRequests release];
    [_desiredComposerPrompt release];
    [_localFileChecker release];
    [_pendingConductor release];
    [_appSwitchingPreventionDetector release];
    [_queuedConnectingSSH release];
    [_hostStack release];
    [_defaultPointer release];

    [super dealloc];
}

- (NSString *)description {
    NSString *synthetic = _synthetic ? @" Synthetic" : @"";
    return [NSString stringWithFormat:@"<%@: %p %dx%d metal=%@ id=%@%@>",
            [self class], self, [_screen width], [_screen height], @(self.useMetal), _guid, synthetic];
}

- (void)didFinishInitialization {
    DLog(@"didFinishInitialization");
    [_pwdPoller poll];
    _initializationFinished = YES;
    if ([self.variablesScope valueForVariableName:iTermVariableKeySessionUsername] == nil) {
        [self.variablesScope setValue:NSUserName() forVariableNamed:iTermVariableKeySessionUsername];
    }
    if ([self.variablesScope valueForVariableName:iTermVariableKeySessionHostname] == nil) {
        NSString *const name = [NSHost fullyQualifiedDomainName];
        if ([self.variablesScope valueForVariableName:iTermVariableKeySessionHostname] == nil) {
            [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionHostname];
        }
    }
    if (_desiredComposerPrompt) {
        DLog(@"Delayed reveal of prompt");
        NSArray<ScreenCharArray *> *prompt = [_desiredComposerPrompt autorelease];
        _desiredComposerPrompt = nil;
        [self screenRevealComposerWithPrompt:prompt];
    }
}

- (void)setGuid:(NSString *)guid {
    if ([NSObject object:guid isEqualToObject:_guid]) {
        return;
    }
    if (_guid) {
        [[PTYSession sessionMap] removeObjectForKey:_guid];
    }
    iTermPublisher<NSNumber *> *previousPublisher = [[[[iTermCPUUtilization instanceForSessionID:_guid] publisher] retain] autorelease];
    [_guid autorelease];
    _guid = [guid copy];
    [[iTermCPUUtilization instanceForSessionID:_guid] setPublisher:previousPublisher];
    [self sync];
    [[PTYSession sessionMap] setObject:self forKey:_guid];
    [self.variablesScope setValue:_guid forVariableNamed:iTermVariableKeySessionID];
}

- (void)takeStatusBarViewControllerFrom:(PTYSession *)donorSession {
    [_view takeFindDriverFrom:donorSession.view delegate:self];

    _statusBarViewController.delegate = nil;
    [_statusBarViewController release];

    _statusBarViewController = donorSession->_statusBarViewController;
    _statusBarViewController.delegate = self;

    donorSession->_statusBarViewController = nil;
}

- (void)willRetireSyntheticSession:(PTYSession *)syntheticSession {
    [self takeStatusBarViewControllerFrom:syntheticSession];
}

- (void)setLiveSession:(PTYSession *)liveSession {
    assert(liveSession != self);
    if (liveSession) {
        assert(!_liveSession);
        _synthetic = YES;
        [self takeStatusBarViewControllerFrom:liveSession];
    } else {
        [_liveSession autorelease];
    }
    _liveSession = liveSession;
    [_liveSession retain];
}

- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession {
    _screen.dvr = nil;
    _dvr = dvr;
    [_dvr retain];
    _dvrDecoder = [dvr getDecoder];
    long long t = [_dvr lastTimeStamp];
    if (t) {
        [_dvrDecoder seek:t];
        [self setDvrFrame];
    }
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [_wrapper setNeedsDisplay:needsDisplay];
}

- (id<ExternalSearchResultsController>)externalSearchResultsController {
    return _textview;
}

- (void)clearInstantReplay {
    if (_dvrDecoder) {
        [_dvr releaseDecoder:_dvrDecoder];
        _dvrDecoder = nil;
    }
    [_screen.dvr clear];
}

- (void)irAdvance:(int)dir
{
    if (!_dvr) {
        if (dir < 0) {
            [[_delegate realParentWindow] replaySession:self];
            PTYSession* irSession = [[_delegate realParentWindow] currentSession];
            if (irSession != self) {
                // Failed to enter replay mode (perhaps nothing to replay?)
                [irSession irAdvance:dir];
            }
            return;
        } else {
            DLog(@"Beep: Can't go backward when no dvr");
            NSBeep();
            return;
        }

    }
    if (dir > 0) {
        if (![_dvrDecoder next]) {
            DLog(@"Beep: dvr reached end");
            NSBeep();
        }
    } else {
        if (![_dvrDecoder prev]) {
            DLog(@"Beep: dvr reached start");
            NSBeep();
        }
    }
    [self setDvrFrame];
}

- (long long)irSeekToAtLeast:(long long)timestamp
{
    assert(_dvr);
    if (![_dvrDecoder seek:timestamp]) {
        return [_dvrDecoder timestamp];
    }
    [self setDvrFrame];
    return [_dvrDecoder timestamp];
}

- (void)appendLinesInRange:(NSRange)rangeOfLines fromSession:(PTYSession *)source {
    assert(source != self);
    _modeHandler.mode = iTermSessionModeDefault;

    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [source.screen enumerateLinesInRange:rangeOfLines
                                       block:^(int i,
                                               ScreenCharArray *sca,
                                               iTermImmutableMetadata metadata,
                                               BOOL *stopPtr) {
            if (i + 1 == NSMaxRange(rangeOfLines)) {
                screen_char_t continuation = { 0 };
                continuation.code = EOL_SOFT;
                [mutableState appendScreenChars:sca.line
                                         length:sca.length
                         externalAttributeIndex:iTermImmutableMetadataGetExternalAttributesIndex(metadata)
                                   continuation:continuation];
            } else {
                [mutableState appendScreenChars:sca.line
                                         length:sca.length
                         externalAttributeIndex:iTermImmutableMetadataGetExternalAttributesIndex(metadata)
                                   continuation:sca.continuation];
            }
        }];
    }];
}

- (void)setCopyMode:(BOOL)copyMode {
    [_textview removePortholeSelections];
    _modeHandler.mode = copyMode ? iTermSessionModeCopy : iTermSessionModeDefault;
}

- (BOOL)copyMode {
    return _modeHandler.mode == iTermSessionModeCopy;
}

- (BOOL)sessionModeConsumesEvent:(NSEvent *)event {
    return [_modeHandler wouldHandleEvent:event];
}

- (void)coprocessChanged {
    [_textview requestDelegateRedraw];
}

+ (void)drawArrangementPreview:(NSDictionary *)arrangement frame:(NSRect)frame dark:(BOOL)dark {
    Profile *theBookmark =
    [[ProfileModel sharedInstance] bookmarkWithGuid:arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_GUID]];
    if (!theBookmark) {
        theBookmark = [arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK];
    }
    NSColor *color = [iTermProfilePreferences colorForKey:KEY_BACKGROUND_COLOR
                                                     dark:dark
                                                  profile:theBookmark];
    [color set];
    NSRectFill(frame);
}

- (void)setSizeFromArrangement:(NSDictionary*)arrangement {
    [self setSize:VT100GridSizeMake([[arrangement objectForKey:SESSION_ARRANGEMENT_COLUMNS] intValue],
                                    [[arrangement objectForKey:SESSION_ARRANGEMENT_ROWS] intValue])];
}

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
             replacingProfileWithGUID:(NSString *)badGuid
                          withProfile:(Profile *)goodProfile {
    if ([arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_GUID] isEqualToString:badGuid]) {
        NSMutableDictionary *result = [[arrangement mutableCopy] autorelease];
        result[SESSION_ARRANGEMENT_BOOKMARK] = goodProfile;
        return result;
    } else {
        return arrangement;
    }
}

+ (NSDictionary *)repairedArrangement:(NSDictionary *)arrangement
     replacingOldCWDOfSessionWithGUID:(NSString *)guid
                           withOldCWD:(NSString *)replacementOldCWD {
    if ([arrangement[SESSION_ARRANGEMENT_GUID] isEqualToString:guid]) {
        return [arrangement dictionaryBySettingObject:replacementOldCWD
                                               forKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY];
    }
    return arrangement;
}

+ (void)finishInitializingArrangementOriginatedSession:(PTYSession *)aSession
                                           arrangement:(NSDictionary *)arrangement
                                       arrangementName:(NSString *)arrangementName
                                      attachedToServer:(BOOL)attachedToServer
                                              delegate:(id<PTYSessionDelegate>)delegate
                                    didRestoreContents:(BOOL)didRestoreContents
                                           needDivorce:(BOOL)needDivorce
                                            objectType:(iTermObjectType)objectType
                                           sessionView:(SessionView *)sessionView
                                   shouldEnterTmuxMode:(BOOL)shouldEnterTmuxMode
                                                 state:(NSDictionary *)state
                                     tmuxDCSIdentifier:(NSString *)tmuxDCSIdentifier
                                        missingProfile:(BOOL)missingProfile {
    if (needDivorce) {
        [aSession divorceAddressBookEntryFromPreferences];
        [aSession sessionProfileDidChange];
    }

    // This is done after divorce out of paranoia, since it will modify the profile.
    NSDictionary *shortcutDictionary = arrangement[SESSION_ARRANGEMENT_HOTKEY];
    if (shortcutDictionary) {
        [[iTermSessionHotkeyController sharedInstance] setShortcut:[iTermShortcut shortcutWithDictionary:shortcutDictionary]
                                                        forSession:aSession];
        [aSession setSessionSpecificProfileValues:@{ KEY_SESSION_HOTKEY: shortcutDictionary }];
    }

    [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        NSArray *history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_HISTORY];
        if (history) {
            [mutableState setHistory:history];
        }
        history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_ALT_HISTORY];
        if (history) {
            [mutableState setAltScreen:history];
        }
    }];
    [aSession.nameController restoreNameFromStateDictionary:arrangement[SESSION_ARRANGEMENT_NAME_CONTROLLER_STATE]];
    if (arrangement[SESSION_ARRANGEMENT_VARIABLES]) {
        NSDictionary *variables = arrangement[SESSION_ARRANGEMENT_VARIABLES];
        for (id key in variables) {
            if ([key hasPrefix:@"iterm2."]) {
                // Legacy states had this
                continue;
            }
            if ([[aSession.variablesScope valueForVariableName:key] isKindOfClass:[iTermVariables class]]) {
                // Don't replace nonterminals.
                continue;
            }
            if (!attachedToServer && [key isEqualToString:iTermVariableKeySessionTTY]) {
                // When starting a new session, don't restore the tty. We *do* want to restore it
                // when attaching to a session restoration server, though. We have a reasonable
                // believe that it's the same process and therefore the same TTY.
                continue;
            }
            [aSession.variablesScope setValue:variables[key] forVariableNamed:key];
        }
        aSession.textview.badgeLabel = aSession.badgeLabel;
    }

    if (didRestoreContents && attachedToServer) {
        [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            if (arrangement[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED_DEPRECATED]) {
                // Legacy migration path
                const BOOL shellIntegrationEverUsed = [arrangement[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED_DEPRECATED] boolValue];
                mutableState.shouldExpectPromptMarks = shellIntegrationEverUsed;
            } else {
                mutableState.shouldExpectPromptMarks = [arrangement[SESSION_ARRANGEMENT_SHOULD_EXPECT_PROMPT_MARKS] boolValue];
                aSession->_shouldExpectCurrentDirUpdates = [arrangement[SESSION_ARRANGEMENT_SHOULD_EXPECT_CURRENT_DIR_UPDATES] boolValue];
            }
        }];
    }

    aSession->_workingDirectoryPollerDisabled = [arrangement[SESSION_ARRANGEMENT_WORKING_DIRECTORY_POLLER_DISABLED] boolValue] || aSession->_shouldExpectCurrentDirUpdates;
    if (arrangement[SESSION_ARRANGEMENT_COMMANDS]) {
        [aSession.commands addObjectsFromArray:arrangement[SESSION_ARRANGEMENT_COMMANDS]];
        [aSession trimCommandsIfNeeded];
    }
    if (arrangement[SESSION_ARRANGEMENT_DIRECTORIES]) {
        [aSession.directories addObjectsFromArray:arrangement[SESSION_ARRANGEMENT_DIRECTORIES]];
        [aSession trimDirectoriesIfNeeded];
    }
    if (arrangement[SESSION_ARRANGEMENT_HOSTS]) {
        for (NSDictionary *host in arrangement[SESSION_ARRANGEMENT_HOSTS]) {
            id<VT100RemoteHostReading> remoteHost = [[[VT100RemoteHost alloc] initWithDictionary:host] autorelease];
            if (remoteHost) {
                [aSession.hosts addObject:remoteHost];
                [aSession trimHostsIfNeeded];
            }
        }
    }

    if (arrangement[SESSION_ARRANGEMENT_APS]) {
        aSession.automaticProfileSwitcher =
        [[iTermAutomaticProfileSwitcher alloc] initWithDelegate:aSession
                                                     savedState:arrangement[SESSION_ARRANGEMENT_APS]];
    }
    if (didRestoreContents) {
        aSession->_sshState = [arrangement[SESSION_ARRANGEMENT_SSH_STATE] unsignedIntegerValue];
    }
    aSession.cursorTypeOverride = arrangement[SESSION_ARRANGEMENT_CURSOR_TYPE_OVERRIDE];
    if (didRestoreContents && attachedToServer) {
        if (arrangement[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK]) {
            aSession->_alertOnNextMark = [arrangement[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK] boolValue];
        }
        if (arrangement[SESSION_ARRANGEMENT_CURSOR_GUIDE]) {
            aSession.textview.highlightCursorLine = [arrangement[SESSION_ARRANGEMENT_CURSOR_GUIDE] boolValue];
        }
        aSession.lastRemoteHost = aSession.screen.lastRemoteHost;
        if (arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY]) {
            [aSession->_lastDirectory autorelease];
            aSession->_lastDirectory = [arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY] copy];
            const BOOL isRemote = [arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY_IS_UNSUITABLE_FOR_OLD_PWD_DEPRECATED] boolValue];
            if (!isRemote) {
                aSession.lastLocalDirectory = aSession.lastDirectory;
            }
        }
        if (arrangement[SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY]) {
            aSession.lastLocalDirectory = arrangement[SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY];
            aSession.lastLocalDirectoryWasPushed = [arrangement[SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY_WAS_PUSHED] boolValue];
        }
    }

    if (state) {
        [aSession setTmuxState:state];
    }
    NSDictionary *liveArrangement = arrangement[SESSION_ARRANGEMENT_LIVE_SESSION];
    if (liveArrangement) {
        SessionView *liveView = [[[SessionView alloc] initWithFrame:sessionView.frame] autorelease];
        liveView.driver.dataSource = aSession->_metalGlue;
        aSession.textview.cursorVisible = NO;
        [delegate session:aSession setLiveSession:[self sessionFromArrangement:liveArrangement
                                                                         named:nil
                                                                        inView:liveView
                                                                  withDelegate:delegate
                                                                 forObjectType:objectType
                                                            partialAttachments:nil]];
    }
    if (shouldEnterTmuxMode) {
        // Restored a tmux gateway session.
        [aSession startTmuxMode:tmuxDCSIdentifier];
        [aSession.tmuxController sessionChangedTo:arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME]
                                        sessionId:[arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] intValue]];
        [aSession kickOffTmux];
    }
    if (missingProfile) {
        NSDictionary *arrangementProfile = arrangement[SESSION_ARRANGEMENT_BOOKMARK];
        if (arrangementProfile) {
            [aSession.naggingController arrangementWithName:arrangementName
                                        missingProfileNamed:arrangementProfile[KEY_NAME]
                                                       guid:arrangementProfile[KEY_GUID]];
        }
    }
    if (!attachedToServer) {
        [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                         VT100ScreenMutableState *mutableState,
                                                         id<VT100ScreenDelegate> delegate) {
            [terminal resetSendModifiersWithSideEffects:YES];
        }];
    }
    NSString *path = [aSession.screen workingDirectoryOnLine:aSession.screen.numberOfScrollbackLines + aSession.screen.cursorY - 1];
    [aSession.variablesScope setValue:path forVariableNamed:iTermVariableKeySessionPath];

    [aSession.nameController setNeedsUpdate];
    [aSession.nameController updateIfNeeded];
}

- (void)didFinishRestoration {
    if ([_foundingArrangement[SESSION_ARRANGEMENT_FILTER] length] > 0) {
        [self.delegate session:self setFilter:_foundingArrangement[SESSION_ARRANGEMENT_FILTER]];
    }
}

+ (PTYSession *)sessionFromArrangement:(NSDictionary *)arrangement
                                 named:(NSString *)arrangementName
                                inView:(SessionView *)sessionView
                          withDelegate:(id<PTYSessionDelegate>)delegate
                         forObjectType:(iTermObjectType)objectType
                    partialAttachments:(NSDictionary *)partialAttachments {
    DLog(@"Restoring session from arrangement");

    Profile *theBookmark =
    [[ProfileModel sharedInstance] bookmarkWithGuid:arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_GUID]];
    BOOL needDivorce = NO;
    BOOL missingProfile = NO;
    if (!theBookmark) {
        NSString *originalGuid = arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_ORIGINAL_GUID];
        if (![[ProfileModel sharedInstance] bookmarkWithGuid:originalGuid]) {
            missingProfile = YES;
        }

        theBookmark = [arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK];
        if (theBookmark) {
            needDivorce = YES;
        } else {
            theBookmark = [[ProfileModel sharedInstance] defaultBookmark];
        }
    }
    PTYSession *aSession = [[[PTYSession alloc] initSynthetic:NO] autorelease];
    aSession.foundingArrangement = [arrangement dictionaryByRemovingObjectForKey:SESSION_ARRANGEMENT_CONTENTS];
    aSession.view = sessionView;
    aSession->_savedGridSize = VT100GridSizeMake(MAX(1, [arrangement[SESSION_ARRANGEMENT_COLUMNS] intValue]),
                                                 MAX(1, [arrangement[SESSION_ARRANGEMENT_ROWS] intValue]));
    [sessionView setFindDriverDelegate:aSession];
    NSMutableSet<NSString *> *keysToPreserveInCaseOfDivorce = [NSMutableSet setWithArray:@[ KEY_GUID, KEY_ORIGINAL_GUID ]];

    {
        NSDictionary<NSString *, NSString *> *overrides = arrangement[SESSION_ARRANGEMENT_FONT_OVERRIDES];
        if (overrides) {
            NSMutableDictionary *temp = [[theBookmark mutableCopy] autorelease];
            [overrides enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
                temp[key] = obj;
            }];
            theBookmark = [temp dictionaryByRemovingNullValues];
        }
    }

    {
        NSDictionary *overrides = arrangement[SESSION_ARRANGEMENT_KEYBOARD_MAP_OVERRIDES];
        if (overrides) {
            NSMutableDictionary *modifiedProfile = [[theBookmark mutableCopy] autorelease];
            modifiedProfile[KEY_KEYBOARD_MAP] = overrides;
            theBookmark = modifiedProfile;
        }
    }
    if ([arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_PANE]) {
        // This is a tmux arrangement.
        NSString *colorString = arrangement[SESSION_ARRANGEMENT_TMUX_TAB_COLOR];
        NSDictionary *tabColorDict = [ITAddressBookMgr encodeColor:[NSColor colorFromHexString:colorString]];
        const BOOL dark = [NSApp effectiveAppearance].it_isDark;
        NSString *useTabColorKey = iTermAmendedColorKey(KEY_USE_TAB_COLOR, theBookmark, dark);
        if (tabColorDict) {
            // We're restoring a tmux arrangement that specifies a tab color.
            NSColor *profileTabColorDict = [iTermProfilePreferences objectForColorKey:KEY_TAB_COLOR dark:dark profile:theBookmark];
            if (![iTermProfilePreferences boolForColorKey:KEY_USE_TAB_COLOR dark:dark profile:theBookmark] ||
                ![NSObject object:profileTabColorDict isApproximatelyEqualToObject:tabColorDict epsilon:1/255.0]) {
                // The tmux profile does not specify a tab color or it specifies a different one. Override it and divorce.
                NSString *tabColorKey = iTermAmendedColorKey(KEY_TAB_COLOR, theBookmark, dark);
                theBookmark = [theBookmark dictionaryBySettingObject:tabColorDict forKey:tabColorKey];
                theBookmark = [theBookmark dictionaryBySettingObject:@YES forKey:useTabColorKey];
                needDivorce = YES;
                [keysToPreserveInCaseOfDivorce addObjectsFromArray:@[ tabColorKey, useTabColorKey ]];
            }
        } else if ([colorString isEqualToString:iTermTmuxTabColorNone] &&
                   [iTermProfilePreferences boolForColorKey:KEY_USE_TAB_COLOR dark:dark profile:theBookmark]) {
            // There was no tab color but the tmux profile specifies one. Disable it and divorce.
            theBookmark = [theBookmark dictionaryBySettingObject:@NO forKey:useTabColorKey];
            [keysToPreserveInCaseOfDivorce addObjectsFromArray:@[ useTabColorKey ]];
            needDivorce = YES;
        }
    }
    if (needDivorce) {
        // Keep it from stepping on an existing session with the same guid. Assign a fresh GUID.
        // Set the ORIGINAL_GUID to an existing guid from which this profile originated if possible.
        NSString *originalGuid = nil;
        NSString *recordedGuid = arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_GUID];
        NSString *recordedOriginalGuid = arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_ORIGINAL_GUID];
        if ([[ProfileModel sharedInstance] bookmarkWithGuid:recordedGuid]) {
            originalGuid = recordedGuid;
        } else if ([[ProfileModel sharedInstance] bookmarkWithGuid:recordedOriginalGuid]) {
            originalGuid = recordedOriginalGuid;
        }
        if (originalGuid) {
            theBookmark = [theBookmark dictionaryBySettingObject:originalGuid forKey:KEY_ORIGINAL_GUID];
        }
        theBookmark = [theBookmark dictionaryBySettingObject:[ProfileModel freshGuid] forKey:KEY_GUID];
        if ([NSArray castFrom:arrangement[SESSION_ARRANGEMENT_OVERRIDDEN_FIELDS]]) {
            DLog(@"Have overridden fields %@", arrangement[SESSION_ARRANGEMENT_OVERRIDDEN_FIELDS]);
            // Use the original profile, but preserve keys that were overridden
            // at the time the arrangement was saved. Also preserve any keys
            // that were mutated since the profile was taken from the
            // arrangement.
            // This prevents an issue where you save a divorced session in an
            // arrangement and then modify a non-overridden field in the
            // underlying profile and that setting doesn't get reflected when
            // you next restore the arrangement.
            Profile *underlyingProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:originalGuid];
            NSArray<NSString *> *overriddenFields = arrangement[SESSION_ARRANGEMENT_OVERRIDDEN_FIELDS];

            if (underlyingProfile) {
                DLog(@"Underlying profile %@ exists", originalGuid);
                MutableProfile *replacement = [[underlyingProfile mutableCopy] autorelease];
                [keysToPreserveInCaseOfDivorce unionSet:[NSSet setWithArray:overriddenFields]];
                for (NSString *key in keysToPreserveInCaseOfDivorce) {
                    DLog(@"Preserve %@=%@ from arrangement", key, theBookmark[key]);
                    replacement[key] = theBookmark[key];
                }
                theBookmark = replacement;
            }
        }
    }

    // set our preferences
    [aSession setProfile:theBookmark];

    [aSession setScreenSize:[sessionView frame] parent:[delegate realParentWindow]];

    if ([arrangement[SESSION_ARRANGEMENT_TMUX_FOCUS_REPORTING] boolValue]) {
        // This has to be done after setScreenSize:parent: because it has a side-effect of enabling
        // the terminal.
        [aSession.screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            terminal.reportFocus = [iTermAdvancedSettingsModel focusReportingEnabled];
        }];
    }

    NSDictionary *state = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_STATE];
    if (state) {
        // For tmux tabs, get the size from the arrangement instead of the containing view because
        // it helps things to line up correctly.
        [aSession setSizeFromArrangement:arrangement];
    }
    [aSession setPreferencesFromAddressBookEntry:theBookmark];
    [aSession loadInitialColorTableAndResetCursorGuide];
    aSession.delegate = delegate;

    BOOL haveSavedProgramData = YES;
    if ([arrangement[SESSION_ARRANGEMENT_PROGRAM] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = arrangement[SESSION_ARRANGEMENT_PROGRAM];
        if ([dict[kProgramType] isEqualToString:kProgramTypeShellLauncher]) {
            aSession.program = [ITAddressBookMgr shellLauncherCommandWithCustomShell:nil];
        } else if ([dict[kProgramType] isEqualToString:kProgramTypeCommand]) {
            aSession.program = dict[kProgramCommand];
        } else if ([dict[kProgramType] isEqualToString:kProgramTypeCustomShell]) {
            aSession.program = [ITAddressBookMgr shellLauncherCommandWithCustomShell:dict[kCustomShell]];
            aSession.customShell = dict[kCustomShell];
        } else {
            haveSavedProgramData = NO;
        }
    } else {
        haveSavedProgramData = NO;
    }
    if (arrangement[SESSION_ARRANGEMENT_PENDING_JUMPS]) {
        aSession->_pendingJumps = [[[NSArray castFrom:arrangement[SESSION_ARRANGEMENT_PENDING_JUMPS]] mapWithBlock:^id _Nullable(id  _Nonnull data) {
            return [[[iTermSSHReconnectionInfo alloc] initWithData: data] autorelease];
        }] mutableCopy];
    }

    if (arrangement[SESSION_ARRANGEMENT_ENVIRONMENT]) {
        aSession.environment = arrangement[SESSION_ARRANGEMENT_ENVIRONMENT];
    } else {
        haveSavedProgramData = NO;
    }

    if (arrangement[SESSION_ARRANGEMENT_IS_UTF_8]) {
        aSession.isUTF8 = [arrangement[SESSION_ARRANGEMENT_IS_UTF_8] boolValue];
    } else {
        haveSavedProgramData = NO;
    }

    aSession.shortLivedSingleUse = [arrangement[SESSION_ARRANGEMENT_SHORT_LIVED_SINGLE_USE] boolValue];
    aSession.hostnameToShell = [[arrangement[SESSION_ARRANGEMENT_HOSTNAME_TO_SHELL] mutableCopy] autorelease];
    [aSession.variablesScope setValue:[aSession bestGuessAtUserShell] forVariableNamed:iTermVariableKeySSHIntegrationLevel];

    if (arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS]) {
        aSession.substitutions = arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS];
    } else {
        haveSavedProgramData = NO;
    }

    if (arrangement[SESSION_ARRANGEMENT_REUSABLE_COOKIE]) {
        [[iTermWebSocketCookieJar sharedInstance] addCookie:arrangement[SESSION_ARRANGEMENT_REUSABLE_COOKIE]];
    }
    NSNumber *tmuxPaneNumber = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_PANE];
    NSString *tmuxDCSIdentifier = nil;
    BOOL shouldEnterTmuxMode = NO;
    NSDictionary *contents = arrangement[SESSION_ARRANGEMENT_CONTENTS];
    BOOL restoreContents = !tmuxPaneNumber && contents && [iTermAdvancedSettingsModel restoreWindowContents];
    BOOL attachedToServer = NO;
    typedef void (^iTermSessionCreationCompletionBlock)(PTYSession *, BOOL ok);
    void (^runCommandBlock)(iTermSessionCreationCompletionBlock) =
    ^(iTermSessionCreationCompletionBlock innerCompletion) {
        innerCompletion(aSession, YES);
    };
    if (!tmuxPaneNumber) {
        DLog(@"No tmux pane ID during session restoration");
        // |contents| will be non-nil when using system window restoration.
        BOOL runCommand = YES;
        if (arrangement[SESSION_ARRANGEMENT_LIVE_SESSION]) {
            runCommand = NO;
        }
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            DLog(@"Configured to run jobs in servers");
            const BOOL isTmuxGateway = [arrangement[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] boolValue];
            if (isTmuxGateway) {
                DLog(@"Was a tmux gateway. Start recovery mode in parser.");
                // Optimistally enter tmux recovery mode. If we do attach, the parser will be in the
                // right state before any input arrives for it.
                // In the event that attaching to the server fails we'll first tmux recovery mode
                // and set runCommand=YES; later, a new program will run and input will be received
                //  but the parser is safely out of recovery mode by then.
                [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
                    [terminal.parser startTmuxRecoveryModeWithID:arrangement[SESSION_ARRANGEMENT_TMUX_DCS_ID]];
                }];
            }
            NSString *conductor = [NSString castFrom:arrangement[SESSION_ARRANGEMENT_CONDUCTOR]];
            if (conductor) {
                aSession->_conductor = [iTermConductor newConductorWithJSON:conductor delegate:aSession];
            }
            if (aSession->_conductor) {
                [aSession updateVariablesFromConductor];
                [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
                    NSData *data = [NSData castFrom:arrangement[SESSION_ARRANGEMENT_CONDUCTOR_TREE]];
                    NSDictionary *dict = [NSDictionary it_fromKeyValueCodedData:data];
                    if (dict) {
                        [terminal.parser startConductorRecoveryModeWithID:arrangement[SESSION_ARRANGEMENT_CONDUCTOR_DCS_ID]
                                                                     tree:dict];
                    }
                }];
            }
            // iTerm2 is currently configured to run jobs in servers, but we
            // have to check if the arrangement was saved with that setting on.
            BOOL didAttach = NO;
            if ([NSNumber castFrom:arrangement[SESSION_ARRANGEMENT_SERVER_PID]]) {
                DLog(@"Have a server PID in the arrangement");
                pid_t serverPid = [arrangement[SESSION_ARRANGEMENT_SERVER_PID] intValue];
                DLog(@"Try to attach to pid %d", (int)serverPid);
                // serverPid might be -1 if the user turned on session restoration and then quit.
                if (serverPid != -1 && [aSession tryToAttachToServerWithProcessId:serverPid
                                                                              tty:arrangement[SESSION_ARRANGEMENT_TTY]]) {
                    DLog(@"Success!");
                    didAttach = YES;
                }
            } else if ([iTermMultiServerJobManager available] &&
                       [NSDictionary castFrom:arrangement[SESSION_ARRANGEMENT_SERVER_DICT]]) {
                DLog(@"Have a server dict in the arrangement");
                NSDictionary *serverDict = arrangement[SESSION_ARRANGEMENT_SERVER_DICT];
                DLog(@"Try to attach to %@", serverDict);
                if (partialAttachments) {
                    id partial = partialAttachments[serverDict];
                    if (partial &&
                        [aSession tryToFinishAttachingToMultiserverWithPartialAttachment:partial] != 0) {
                        DLog(@"Finished attaching to multiserver!");
                        didAttach = YES;
                    }
                } else if ([aSession tryToAttachToMultiserverWithRestorationIdentifier:serverDict]) {
                    DLog(@"Attached to multiserver!");
                    didAttach = YES;
                }
            }
            if (didAttach) {
                runCommand = NO;
                attachedToServer = YES;
                shouldEnterTmuxMode = ([arrangement[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] boolValue] &&
                                       arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME] != nil &&
                                       arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] != nil);
                tmuxDCSIdentifier = arrangement[SESSION_ARRANGEMENT_TMUX_DCS_ID];
            } else {
                if (isTmuxGateway) {
                    [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
                        [terminal.parser cancelTmuxRecoveryMode];
                    }];
                }
                if (aSession->_conductor) {
                    [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
                        [terminal.parser cancelConductorRecoveryMode];
                    }];
                    aSession->_conductor.delegate = nil;
                    [aSession->_conductor release];
                    aSession->_conductor = nil;
                }
            }

        }

        // GUID will be set for new saved arrangements since late 2014.
        // Older versions won't be able to associate saved state with windows from a saved arrangement.
        if (arrangement[SESSION_ARRANGEMENT_GUID]) {
            DLog(@"The session arrangement has a GUID");
            NSString *guid = arrangement[SESSION_ARRANGEMENT_GUID];
            aSession->_arrangementGUID = [guid copy];
            if (guid && gRegisteredSessionContents[guid]) {
                DLog(@"The GUID is registered");
                // There was a registered session with this guid. This session was created by
                // restoring a saved arrangement and there is saved content registered.
                contents = gRegisteredSessionContents[guid];
                aSession.guid = guid;
                DLog(@"Assign guid %@ to session %@ which will have its contents restored from registered contents",
                     guid, aSession);
            } else if ([[iTermController sharedInstance] startingUp] ||
                       arrangement[SESSION_ARRANGEMENT_CONTENTS]) {
                // If startingUp is set, then the session is being restored from the default
                // arrangement, per user preference.
                // If contents are present, then system window restoration is bringing back a
                // session.
                aSession.guid = guid;
                DLog(@"iTerm2 is starting up or has contents. Assign guid %@ to session %@ (session is loaded from saved arrangement. No content registered.)", guid, aSession);
            }
        }

        DLog(@"Have contents=%@", @(contents != nil));
        DLog(@"Restore window contents=%@", @([iTermAdvancedSettingsModel restoreWindowContents]));
        if (restoreContents) {
            DLog(@"Loading content from line buffer dictionary");
            [aSession setContentsFromLineBufferDictionary:contents
                                 includeRestorationBanner:runCommand
                                               reattached:attachedToServer];
            // NOTE: THE SCREEN SIZE IS NOW OUT OF SYNC WITH THE VIEW SIZE. IT MUST BE FIXED!
        }
        if (arrangement[SESSION_ARRANGEMENT_KEYLABELS]) {
            // restoreKeyLabels wants the cursor position to be set so do it after restoring contents.
            [aSession restoreKeyLabels:[NSDictionary castFrom:arrangement[SESSION_ARRANGEMENT_KEYLABELS]]
               updateStatusChangedLine:restoreContents];
            NSArray *labels = arrangement[SESSION_ARRANGEMENT_KEYLABELS_STACK];
            if (labels) {
                [aSession->_keyLabelsStack release];
                aSession->_keyLabelsStack = [[labels mapWithBlock:^id(id anObject) {
                    return [[[iTermKeyLabels alloc] initWithDictionary:anObject] autorelease];
                }] mutableCopy];
            }
        }

        if (runCommand) {
            // This path is NOT taken when attaching to a running server.
            //
            // When restoring a window arrangement with contents and a nonempty saved directory, always
            // use the saved working directory, even if that contravenes the default setting for the
            // profile.
            [aSession resetForRelaunch];
            NSString *oldCWD = arrangement[SESSION_ARRANGEMENT_WORKING_DIRECTORY];
            DLog(@"Running command...");

            NSDictionary *environmentArg = @{};
            NSString *commandArg = nil;
            NSNumber *isUTF8Arg = nil;
            NSDictionary *substitutionsArg = nil;
            NSString *customShell = nil;
            if (haveSavedProgramData) {
                // This is the normal case; the else clause is for legacy saved arrangements.
                environmentArg = aSession.environment ?: @{};
                commandArg = aSession.program;
                if (oldCWD &&
                    [aSession.program isEqualToString:[ITAddressBookMgr standardLoginCommand]]) {
                    // Create a login session that drops you in the old directory instead of
                    // using login -fp "$USER". This lets saved arrangements properly restore
                    // the working directory when the profile specifies the home directory.
                    commandArg = [ITAddressBookMgr shellLauncherCommandWithCustomShell:aSession.customShell];
                }
                isUTF8Arg = @(aSession.isUTF8);
                substitutionsArg = aSession.substitutions;
                customShell = aSession.customShell;
            }
            runCommandBlock = ^(iTermSessionCreationCompletionBlock completion) {
                assert(completion);
                iTermSessionAttachOrLaunchRequest *launchRequest =
                [iTermSessionAttachOrLaunchRequest launchRequestWithSession:aSession
                                                                  canPrompt:NO
                                                                 objectType:objectType
                                                        hasServerConnection:NO
                                                           serverConnection:(iTermGeneralServerConnection){}
                                                                  urlString:nil
                                                               allowURLSubs:NO
                                                                environment:environmentArg
                                                                customShell:customShell
                                                                     oldCWD:oldCWD
                                                             forceUseOldCWD:contents != nil && oldCWD.length
                                                                    command:commandArg
                                                                     isUTF8:isUTF8Arg
                                                              substitutions:substitutionsArg
                                                           windowController:(PseudoTerminal *)aSession.delegate.realParentWindow
                                                                      ready:nil
                                                                 completion:completion];
                launchRequest.fromArrangement = YES;
                iTermSessionFactory *factory = [[[iTermSessionFactory alloc] init] autorelease];
                launchRequest.arrangementName = arrangementName;
                [factory attachOrLaunchWithRequest:launchRequest];
            };
        }
    } else {
        // Is a tmux pane
        // NOTE: There used to be code here that used state[@"title"] but AFAICT that didn't exist.
        [aSession setTmuxPane:[tmuxPaneNumber intValue]];
    }

    if (arrangement[SESSION_ARRANGEMENT_SELECTION]) {
        [aSession.textview.selection setFromDictionaryValue:arrangement[SESSION_ARRANGEMENT_SELECTION]
                                                      width:aSession.screen.width
                                    totalScrollbackOverflow:aSession.screen.totalScrollbackOverflow];
    }
    [aSession.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState restoreInitialSizeWithDelegate:delegate];
    }];
    [aSession updateMarksMinimapRangeOfVisibleLines];

    void (^finish)(PTYSession *, BOOL) = ^(PTYSession *newSession, BOOL ok) {
        if (!ok) {
            return;
        }
        [self finishInitializingArrangementOriginatedSession:aSession
                                                 arrangement:arrangement
                                             arrangementName:arrangementName
                                            attachedToServer:attachedToServer
                                                    delegate:delegate
                                          didRestoreContents:restoreContents
                                                 needDivorce:needDivorce
                                                  objectType:objectType
                                                 sessionView:sessionView
                                         shouldEnterTmuxMode:shouldEnterTmuxMode
                                                       state:state
                                           tmuxDCSIdentifier:tmuxDCSIdentifier
                                              missingProfile:missingProfile];
        [aSession didFinishInitialization];
    };
    if ([aSession.profile[KEY_AUTOLOG] boolValue]) {
        [aSession retain];
        void (^startLogging)(NSString *) = ^(NSString *filename) {
            if (filename) {
                const NSUInteger value = [iTermProfilePreferences boolForKey:KEY_LOGGING_STYLE
                                                                   inProfile:aSession.profile];
                iTermLoggingStyle loggingStyle = iTermLoggingStyleFromUserDefaultsValue(value);
                [[aSession loggingHelper] setPath:filename
                                          enabled:YES
                                            style:loggingStyle
                                asciicastMetadata:[aSession asciicastMetadata]
                                           append:@YES];
            }
            [aSession autorelease];
            runCommandBlock(finish);
        };
        if (arrangement[SESSION_ARRANGEMENT_AUTOLOG_FILENAME] && restoreContents) {
            startLogging(arrangement[SESSION_ARRANGEMENT_AUTOLOG_FILENAME]);
        } else {
            [aSession fetchAutoLogFilenameWithCompletion:startLogging];
        }
    } else {
        runCommandBlock(finish);
    }

    return aSession;
}

- (iTermAsciicastMetadata *)asciicastMetadata {
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;

    NSArray<NSColor *> *ansi = [[NSArray sequenceWithRange:NSMakeRange(0, 16)] mapWithBlock:^id _Nonnull(NSNumber * _Nonnull n) {
        NSString *key = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, n.intValue];
        return [iTermProfilePreferences colorForKey:key
                                               dark:dark
                                            profile:self.profile];
    }];
    NSString *term = [iTermProfilePreferences stringForKey:KEY_TERMINAL_TYPE inProfile:self.profile];
    NSDictionary *environment = @{ @"TERM": term ?: @"xterm",
                                   @"SHELL": [self userShell] };
    return [[[iTermAsciicastMetadata alloc] initWithWidth:_screen.width
                                                   height:_screen.height
                                                  command:_program ?: @""
                                                    title:[[self name] stringByTrimmingTrailingWhitespace] ?: @""
                                              environment:environment
                                                       fg:[iTermProfilePreferences colorForKey:KEY_FOREGROUND_COLOR
                                                                                          dark:dark
                                                                                       profile:self.profile]
                                                       bg:[iTermProfilePreferences colorForKey:KEY_BACKGROUND_COLOR
                                                                                          dark:dark
                                                                                       profile:self.profile]
                                                     ansi:ansi] autorelease];
}

- (iTermLoggingHelper *)loggingHelper {
    if (_logging) {
        return _logging;
    }
    _logging = [[iTermLoggingHelper alloc] initWithRawLogger:_shell
                                                cookedLogger:self
                                                 profileGUID:self.profile[KEY_GUID]
                                                       scope:self.variablesScope];
    return _logging;
}

// WARNING: This leaves the screen with the wrong size! Call -restoreInitialSize afterwards.
- (void)setContentsFromLineBufferDictionary:(NSDictionary *)dict
                   includeRestorationBanner:(BOOL)includeRestorationBanner
                                 reattached:(BOOL)reattached {
    [_screen restoreFromDictionary:dict
          includeRestorationBanner:includeRestorationBanner
                        reattached:reattached];
    [_screen enumeratePortholes:^(id<PortholeMarkReading> immutableMark) {
        [[PortholeRegistry instance] registerKey:immutableMark.uniqueIdentifier
                                         forMark:immutableMark];
        id<Porthole> porthole = [_textview hydratePorthole:immutableMark];
        if (!porthole) {
            [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
                [mutableState.mutableIntervalTree removeObject:immutableMark.progenitor];
            }];
        } else {
            [self.textview addPorthole:porthole];
        }
    }];
    id<VT100RemoteHostReading> lastRemoteHost = _screen.lastRemoteHost;
    if (lastRemoteHost) {
        NSString *pwd = [_screen workingDirectoryOnLine:_screen.numberOfLines];
        [self screenCurrentHostDidChange:lastRemoteHost
                                     pwd:pwd
                                     ssh:NO];
    }

    const BOOL enabled = _screen.terminalSoftAlternateScreenMode;
    const BOOL showing = _screen.showingAlternateScreen;
    [self screenSoftAlternateScreenModeDidChangeTo:enabled showingAltScreen:showing];
    // Do this to force the hostname variable to be updated.
    [self currentHost];
}

- (void)showOrphanAnnouncement {
    // Jiggle in case this is an ssh session that needs to be recovered, and also to force a redraw
    // if possible since there won't be any content. We aren't typically attached yet so set
    // jiggleUponAttach to force it to happen eventually.
    [self jiggle];
    _jiggleUponAttach = YES;
    [self.naggingController didRestoreOrphan];
}

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent {
    _modeHandler.mode = iTermSessionModeDefault;
    _screen.delegate = self;
    if ([iTermAdvancedSettingsModel showLocationsInScrollbar] && [iTermAdvancedSettingsModel showMarksInScrollbar]) {
        _screen.intervalTreeObserver = self;
    }

    // Allocate the root per-session view.
    if (!_view) {
        self.view = [[[SessionView alloc] initWithFrame:NSMakeRect(0, 0, aRect.size.width, aRect.size.height)] autorelease];
        self.view.driver.dataSource = _metalGlue;
        [self initializeMarksMinimap];
        [_view setFindDriverDelegate:self];
    }

    _view.scrollview.hasVerticalRuler = [parent scrollbarShouldBeVisible];

    // Allocate a text view
    NSSize aSize = [_view.scrollview contentSize];
    _wrapper = [[TextViewWrapper alloc] initWithFrame:NSMakeRect(0, 0, aSize.width, aSize.height)];

    _textview = [[PTYTextView alloc] initWithFrame:NSMakeRect(0,
                                                              [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins],
                                                              aSize.width,
                                                              aSize.height)];
    _textview.colorMap = _screen.colorMap;
    _textview.keyboardHandler.keyMapper = _keyMapper;
    _view.mainResponder = _textview;
    _view.searchResultsMinimapViewDelegate = _textview.findOnPageHelper;
    _metalGlue.textView = _textview;
    [_textview setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [_textview setFontTable:[iTermFontTable fontTableForProfile:_profile]
          horizontalSpacing:[iTermProfilePreferences doubleForKey:KEY_HORIZONTAL_SPACING inProfile:_profile]
            verticalSpacing:[iTermProfilePreferences doubleForKey:KEY_VERTICAL_SPACING inProfile:_profile]];
    [self setTransparency:[[_profile objectForKey:KEY_TRANSPARENCY] floatValue]];
    [self setTransparencyAffectsOnlyDefaultBackgroundColor:[[_profile objectForKey:KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR] boolValue]];

    [_wrapper addSubview:_textview];
    [_textview setFrame:NSMakeRect(0, [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins], aSize.width, aSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins])];

    // assign terminal and task objects
    // Pause token execution in case the caller needs to modify terminal state before it starts running.
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        iTermTokenExecutorUnpauser *unpauser = [mutableState pauseTokenExecution];
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"unpause %@", terminal);
            [unpauser unpause];
        });
        [_screen setTerminalEnabled:YES];
        [_shell setDelegate:self];
        [self.variablesScope setValue:_shell.tty forVariableNamed:iTermVariableKeySessionTTY];
        [self.variablesScope setValue:@(_screen.terminalMouseMode) forVariableNamed:iTermVariableKeySessionMouseReportingMode];

        // initialize the screen
        // TODO: Shouldn't this take the scrollbar into account?
        NSSize contentSize = [PTYScrollView contentSizeForFrameSize:aSize
                                            horizontalScrollerClass:nil
                                              verticalScrollerClass:parent.scrollbarShouldBeVisible ? [[_view.scrollview verticalScroller] class] : nil
                                                         borderType:_view.scrollview.borderType
                                                        controlSize:NSControlSizeRegular
                                                      scrollerStyle:_view.scrollview.scrollerStyle];

        int width = (contentSize.width - [iTermPreferences intForKey:kPreferenceKeySideMargins]*2) / [_textview charWidth];
        int height = (contentSize.height - [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins]*2) / [_textview lineHeight];
        [_screen destructivelySetScreenWidth:width
                                      height:height
                                mutableState:mutableState];
        [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionColumns: @(width),
                                                        iTermVariableKeySessionRows: @(height) }];
    }];

    [_textview setDataSource:_screen];
    [_textview setDelegate:self];
    // useTransparency may have just changed.
    [self invalidateBlend];
    [_view.scrollview setDocumentView:_wrapper];
    [_wrapper release];
    [_view.scrollview setDocumentCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeam]];
    [_view.scrollview setLineScroll:[_textview lineHeight]];
    [_view.scrollview setPageScroll:2 * [_textview lineHeight]];
    [_view.scrollview setHasVerticalScroller:[parent scrollbarShouldBeVisible]];

    _antiIdleCode = 0;
    [_antiIdleTimer invalidate];
    _antiIdleTimer = nil;
    _newOutput = NO;
    [_view updateScrollViewFrame];
    [self useTransparencyDidChange];

    [self updateMetalDriver];

    return YES;
}

- (BOOL)tryToAttachToServerWithProcessId:(pid_t)serverPid
                                     tty:(NSString *)tty {
    if (![iTermAdvancedSettingsModel runJobsInServers]) {
        DLog(@"Failing to attach because run jobs in servers is off");
        return NO;
    }
    DLog(@"Try to attach...");
    if ([_shell tryToAttachToServerWithProcessId:serverPid tty:tty]) {
        DLog(@"Success, attached.");
        return YES;
    } else {
        DLog(@"Failed to attach");
        return NO;
    }
}

- (BOOL)tryToAttachToMultiserverWithRestorationIdentifier:(NSDictionary *)restorationIdentifier {
    const iTermJobManagerAttachResults results = [_shell tryToAttachToMultiserverWithRestorationIdentifier:restorationIdentifier];
    if (results & iTermJobManagerAttachResultsRegistered) {
        DLog(@"Registered");
    } else {
        DLog(@"Attached to multiserver. Not registered.");
    }
    if (results & iTermJobManagerAttachResultsAttached) {
        DLog(@"Success, attached.");
        return YES;
    } else {
        DLog(@"Failed to attach");
        return NO;
    }
}

// Note: this async code path is taken by orphan adoption.
- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
            completion:(void (^)(void))completion {
    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        DLog(@"Attaching to a server...");
        [_shell attachToServer:serverConnection completion:^(iTermJobManagerAttachResults results) {
            if (!(results & iTermJobManagerAttachResultsAttached)) {
                [self brokenPipe];
            }
            [self->_shell.winSizeController setGridSize:_screen.size
                                               viewSize:_screen.viewSize
                                            scaleFactor:self.backingScaleFactor];
            if (_jiggleUponAttach) {
                [_shell.winSizeController forceJiggle];
            }
            completion();
        }];
    } else {
        DLog(@"Can't attach to a server when runJobsInServers is off.");
    }
}

- (void)didChangeScreen:(CGFloat)scaleFactor {
    [self->_shell.winSizeController setGridSize:_screen.currentGrid.size
                                       viewSize:_screen.viewSize
                                    scaleFactor:scaleFactor];
}

- (void)setSize:(VT100GridSize)size {
    ITBetaAssert(size.width > 0, @"Nonpositive width %d", size.width);
    ITBetaAssert(size.height > 0, @"Nonpositive height %d", size.height);
    if (size.width <= 0) {
        size.width = 1;
    }
    if (size.height <= 0) {
        size.height = 1;
    }
    _savedGridSize = size;
    self.lastResize = [NSDate timeIntervalSinceReferenceDate];
    DLog(@"Set session %@ to %@", self, VT100GridSizeDescription(size));
    DLog(@"Before, range of visible lines is %@", VT100GridRangeDescription(_textview.rangeOfVisibleLines));

    [_screen setSize:size];
    // Sync so that we'll have an updated model as we go forward so that, for example, tail find
    // will be sane.
    [self sync];
    if (!self.delegate || [self.delegate sessionShouldSendWindowSizeIOCTL:self]) {
        [_shell.winSizeController setGridSize:size
                                     viewSize:_screen.viewSize
                                  scaleFactor:self.backingScaleFactor];
    }
    [_textview clearHighlights:NO];
    [_textview updatePortholeFrames];
    [[_delegate realParentWindow] invalidateRestorableState];
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf startTailFindIfVisible];
    });
    [self updateMetalDriver];
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionColumns: @(_screen.width),
                                                    iTermVariableKeySessionRows: @(_screen.height) }];
}

- (void)startTailFindIfVisible {
    if (!_tailFindTimer &&
        [_delegate sessionBelongsToVisibleTab]) {
        [self beginContinuousTailFind];
    }
}

- (Profile *)profileForSplit {
    if ([iTermAdvancedSettingsModel useDivorcedProfileToSplit]) {
        if (self.isDivorced) {
            // NOTE: This counts on splitVertically:before:profile:targetSession: rewriting the GUID.
            return self.profile;
        }
    }

    // Get the profile this session was originally created with. But look it up from its GUID because
    // it might have changed since it was copied into originalProfile when the profile was
    // first created.
    Profile *result = nil;
    Profile *originalProfile = [self originalProfile];
    if (originalProfile && originalProfile[KEY_GUID]) {
        result = [[ProfileModel sharedInstance] bookmarkWithGuid:originalProfile[KEY_GUID]];
    }

    // If that fails, use the current profile.
    if (!result) {
        result = self.profile;
    }

    // I don't think that'll ever fail, but to be safe try using the original profile.
    if (!result) {
        result = originalProfile;
    }

    // I really don't think this'll ever happen, but there's always a default profile to fall back
    // on.
    if (!result) {
        result = [[ProfileModel sharedInstance] defaultBookmark];
    }

    if (_conductor) {
        result = [result dictionaryByMergingDictionary:@{
            KEY_SSH_CONFIG: @{},
            KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeSSHValue,
            KEY_COMMAND_LINE: _conductor.sshIdentity.commandLine }];
    }
    return result;
}

- (SSHIdentity *)sshIdentity {
    return _conductor.sshIdentity;
}

- (NSArray<iTermSSHReconnectionInfo *> *)sshCommandLineSequence {
    assert(_conductor);
    NSMutableArray<iTermSSHReconnectionInfo *> *sequence = [NSMutableArray array];
    iTermConductor *current = _conductor;
    [sequence insertObject:current.reconnectionInfo atIndex:0];
    while (current.parent) {
        current = current.parent;
        [sequence insertObject:current.reconnectionInfo atIndex:0];
    }
    return sequence;
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move {
    // TODO: It would be nice not to have to pass the session into the view. I
    // can (kind of) live with it because the view just passes it through
    // without knowing anything about it.
    [[self view] setSplitSelectionMode:mode move:move session:self];
}

- (int)overUnder:(int)proposedSize inVerticalDimension:(BOOL)vertically {
    int result = proposedSize;
    if (vertically) {
        if ([_view showTitle]) {
            result -= [SessionView titleHeight];
        }
        if (_view.showBottomStatusBar) {
            result -= iTermGetStatusBarHeight();
        }
        result -= [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2;
        int iLineHeight = [_textview lineHeight];
        if (iLineHeight == 0) {
            return 0;
        }
        result %= iLineHeight;
        if (result > iLineHeight / 2) {
            result -= iLineHeight;
        }
        return result;
    } else {
        result -= [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2;
        int iCharWidth = [_textview charWidth];
        if (iCharWidth == 0) {
            return 0;
        }
        result %= iCharWidth;
        if (result > iCharWidth / 2) {
            result -= iCharWidth;
        }
    }
    return result;
}

- (id<ProcessInfoProvider>)processInfoProvider {
    if (!_conductor.framing) {
        return [iTermProcessCache sharedInstance];
    }
    return _conductor.processInfoProvider;
}

- (id<SessionProcessInfoProvider>)sessionProcessInfoProvider {
    if (!_conductor.framing) {
        return _shell;
    }
    return _conductor.processInfoProvider;
}

- (NSArray<iTermProcessInfo *> *)processInfoForShellAndDescendants {
    NSMutableArray<iTermProcessInfo *> *result = [NSMutableArray array];
    if (_conductor) {
        [result addObjectsFromArray:_conductor.transitiveProcesses];
    }
    pid_t thePid = [_shell pid];

    [[iTermProcessCache sharedInstance] updateSynchronously];
    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] processInfoForPid:thePid];
    if (!info) {
        return result;
    }

    NSInteger levelsToSkip = 0;
    if ([info.name isEqualToString:@"login"]) {
        levelsToSkip++;
    }

    NSArray<iTermProcessInfo *> *allInfos = [info descendantsSkippingLevels:levelsToSkip];
    [result addObjectsFromArray:allInfos];
    return result;
}

- (NSArray<iTermTuple<NSString *, NSString *> *> *)childJobNameTuples {
    NSArray<iTermProcessInfo *> *allInfos = [self processInfoForShellAndDescendants];
    return [allInfos mapWithBlock:^id(iTermProcessInfo *info) {
        if (!info.name) {
            return nil;
        }
        return [iTermTuple tupleWithObject:info.name
                                 andObject:info.argv0 ?: info.name];
    }];
}

- (iTermPromptOnCloseReason *)promptOnCloseReason {
    DLog(@"entered");
    if (_exited) {
        return [iTermPromptOnCloseReason noReason];
    }
    switch ([[_profile objectForKey:KEY_PROMPT_CLOSE] intValue]) {
        case PROMPT_ALWAYS:
            DLog(@"prompt always");
            return [iTermPromptOnCloseReason profileAlwaysPrompts:_profile];

        case PROMPT_NEVER:
            DLog(@"prompt never");
            return [iTermPromptOnCloseReason noReason];

        case PROMPT_EX_JOBS: {
            DLog(@"Prompt ex jobs");
            if (self.isTmuxClient) {
                DLog(@"is tmux client");
                return [iTermPromptOnCloseReason tmuxClientsAlwaysPromptBecauseJobsAreNotExposed];
            }
            NSMutableArray<NSString *> *blockingJobs = [NSMutableArray array];
            NSArray *jobsThatDontRequirePrompting = [_profile objectForKey:KEY_JOBS];
            DLog(@"jobs that don't require prompting: %@", jobsThatDontRequirePrompting);
            for (iTermTuple<NSString *, NSString *> *childNameTuple in [self childJobNameTuples]) {
                DLog(@"Check child %@", childNameTuple);
                if ([jobsThatDontRequirePrompting indexOfObject:childNameTuple.firstObject] == NSNotFound &&
                    [jobsThatDontRequirePrompting indexOfObject:childNameTuple.secondObject] == NSNotFound) {
                    DLog(@"    not on the ignore list");
                    // This job is not in the ignore list.
                    [blockingJobs addObject:childNameTuple.secondObject.lastPathComponent];
                }
            }
            if (blockingJobs.count > 0) {
                DLog(@"Blocked by jobs: %@", blockingJobs);
                return [iTermPromptOnCloseReason profile:_profile blockedByJobs:blockingJobs];
            } else {
                // All jobs were in the ignore list.
                return [iTermPromptOnCloseReason noReason];
            }
        }
    }

    // This shouldn't happen
    return [iTermPromptOnCloseReason profileAlwaysPrompts:_profile];
}

- (NSSet<NSString *> *)jobsToIgnore {
    NSArray<NSString *> *builtInJobsToIgnore = @[ @"login", @"iTerm2", @"ShellLauncher" ];
    return [NSSet setWithArray:[[_profile objectForKey:KEY_JOBS] ?: @[] arrayByAddingObjectsFromArray:builtInJobsToIgnore]];
}

// A trivial process is one that's always running, like the user's shell. This
// is used to decide if there should be a "document edited" indicator in the
// window's close button.
- (BOOL)processIsTrivial:(iTermProcessInfo *)info {
    NSSet<NSString *> *ignoredNames = [self jobsToIgnore];
    if ([ignoredNames containsObject:info.name]) {
        return YES;
    }
    if ([info.commandLine hasPrefix:@"-"]) {
        return YES;
    }
    if (!self.program) {
        return NO;
    }
    NSString *const programType = [self programType];
    if ([programType isEqualToString:kProgramTypeShellLauncher] ||
        [programType isEqualToString:kProgramTypeCustomShell]) {
        return info.parentProcessID == _shell.pid;
    } else if ([programType isEqualToString:kProgramTypeCommand]) {
        return info.processID == _shell.pid;
    }
    return NO;
}

- (BOOL)hasNontrivialJob {
    DLog(@"Checking for a nontrivial job...");
    pid_t thePid = [_shell pid];
    iTermProcessInfo *rootInfo = [self.processInfoProvider processInfoForPid:thePid];
    if (!rootInfo) {
        return NO;
    }
    // ShellLauncher --launch_shell could be a child job temporarily.
    NSSet<NSString *> *jobToIgnore = [self jobsToIgnore];
    DLog(@"Ignoring %@", jobToIgnore);
    __block BOOL result = NO;
    [rootInfo enumerateTree:^(iTermProcessInfo *info, BOOL *stop) {
        if ([self processIsTrivial:info]) {
            return;
        }
        if ([jobToIgnore containsObject:info.name]) {
            return;
        }
        DLog(@"Process with name %@ and command line %@ is nontrivial", info.name, info.commandLine);
        result = YES;
        *stop = YES;
    }];
    DLog(@"Result is %@", @(result));
    return result;
}

- (BOOL)shouldSetCtype {
    return ![iTermAdvancedSettingsModel doNotSetCtype];
}

- (NSString *)sessionId {
    return [NSString stringWithFormat:@"w%dt%dp%lu:%@",
            [[_delegate realParentWindow] number],
            _delegate.tabNumberForItermSessionId,
            [_delegate sessionPaneNumber:self],
            self.guid];
}

- (void)didMoveSession {
    // TODO: Is it really desirable to update this? It'll get out of sync with the environment variable & autolog filename.
    [self setTermIDIfPossible];
}

- (void)didInitializeSessionWithName:(NSString *)name {
    [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionAutoNameFormat];
}

- (void)profileNameDidChangeTo:(NSString *)name {
    NSString *autoNameFormat = [self.variablesScope valueForVariableName:iTermVariableKeySessionAutoNameFormat] ?: name;
    const BOOL isChangeToLocalName = (self.isDivorced &&
                                      [_overriddenFields containsObject:KEY_NAME]);
    const BOOL haveAutoNameFormatOverride = ([self.variablesScope valueForVariableName:iTermVariableKeySessionIconName] != nil ||
                                             [self.variablesScope valueForVariableName:iTermVariableKeySessionTriggerName] != nil);
    if (isChangeToLocalName || !haveAutoNameFormatOverride) {
        // Profile name changed, local name not overridden, and no icon/trigger name to take precedence.
        autoNameFormat = name;
    }

    NSString *profileName = nil;
    if (![_overriddenFields containsObject:KEY_NAME]) {
        profileName = _originalProfile[KEY_NAME];
    } else {
        profileName = [[ProfileModel sharedInstance] bookmarkWithGuid:_profile[KEY_ORIGINAL_GUID]][KEY_NAME];
        if (!profileName) {
            // Not sure how this would happen
            profileName = [self.variablesScope valueForVariableName:iTermVariableKeySessionProfileName];
        }
    }
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionAutoNameFormat: autoNameFormat ?: [NSNull null],
                                                    iTermVariableKeySessionProfileName: profileName ?: [NSNull null] }];
}

- (void)profileDidChangeToProfileWithName:(NSString *)name {
    [self profileNameDidChangeTo:name];
}

- (void)computeArgvForCommand:(NSString *)command
                substitutions:(NSDictionary *)substitutions
                   completion:(void (^)(NSArray<NSString *> *))completion {
    NSString *program = [command stringByPerformingSubstitutions:substitutions];
    NSArray *components = [program componentsInShellCommand];
    NSArray *arguments;
    if (components.count > 0) {
        program = components[0];
        arguments = [components subarrayWithRange:NSMakeRange(1, components.count - 1)];
    } else {
        arguments = @[];
    }
    completion([@[ program ] arrayByAddingObjectsFromArray:arguments ]);
}

- (NSDictionary *)environmentForNewJobFromEnvironment:(NSDictionary *)environment
                                        substitutions:(NSDictionary *)substitutions {
    DLog(@"environmentForNewJobFromEnvironment:%@ substitutions:%@",
         environment, substitutions);
    NSMutableDictionary *env = environment ? [[environment mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    if (env[TERM_ENVNAME] == nil) {
        env[TERM_ENVNAME] = _termVariable;
    }
    if (env[COLORFGBG_ENVNAME] == nil && _colorFgBgVariable != nil) {
        env[COLORFGBG_ENVNAME] = _colorFgBgVariable;
    }
    if ([iTermAdvancedSettingsModel setCookie]) {
        self.cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
        env[@"ITERM2_COOKIE"] = self.cookie;
    }

    if ([iTermAdvancedSettingsModel addUtilitiesToPATH]) {
        NSString *path = env[PATH_ENVNAME] ?: [NSString stringWithUTF8String:_PATH_STDPATH];
        NSArray *pathComponents = [path componentsSeparatedByString:@":"] ?: @[];
        pathComponents = [pathComponents arrayByAddingObject:[iTermPathToSSH() stringByDeletingLastPathComponent]];
        path = [pathComponents componentsJoinedByString:@":"];
        env[PATH_ENVNAME] = path;
    }

    DLog(@"Begin locale logic");
    switch ([iTermProfilePreferences unsignedIntegerForKey:KEY_SET_LOCALE_VARS inProfile:_profile]) {
        case iTermSetLocalVarsModeDoNotSet:
            break;
        case iTermSetLocalVarsModeCustom: {
            NSString *lang = [iTermProfilePreferences stringForKey:KEY_CUSTOM_LOCALE inProfile:_profile];
            if (lang.length) {
                env[@"LANG"] = lang;
                break;
            }
            // FALL THROUGH INTENTIONALLY
        }
        case iTermSetLocalVarsModeSetAutomatically: {
            DLog(@"Setting locale vars...");

            iTermLocaleGuesser *localeGuesser = [[[iTermLocaleGuesser alloc] initWithEncoding:self.encoding] autorelease];
            NSDictionary *localeVars = [localeGuesser dictionaryWithLANG];
            DLog(@"localeVars=%@", localeVars);
            if (!localeVars) {
                // Failed to guess.
                iTermLocalePrompt *prompt = [[[iTermLocalePrompt alloc] init] autorelease];
                if (self.originalProfile.profileIsDynamic) {
                    DLog(@"Disable remember");
                    prompt.allowRemember = NO;
                }
                while (YES) {
                    localeVars = [prompt requestLocaleFromUserForProfile:self.originalProfile[KEY_NAME] ?: @"(Unnamed profile)"
                                                                inWindow:self.view.window];
                    NSString *lang = localeVars[@"LANG"];
                    if (lang && self.encoding == NSUTF8StringEncoding && ![lang containsString:@"UTF-8"]) {
                        const iTermWarningSelection selection =
                        [iTermWarning showWarningWithTitle:@"Warning! You chose a locale that doesn't use UTF-8, but your profile *is* using UTF-8. This can cause error messages and non-ASCII text to appear wrong. Reconsider your choice."
                                                   actions:@[ @"Try Again", @"Keep my Choice"]
                                                 accessory:nil
                                                identifier:@"NoSyncUTF8Mismatch"
                                               silenceable:kiTermWarningTypePersistent
                                                   heading:@"Sus Encoding Detected"
                                                    window:self.view.window];
                        if (selection == kiTermWarningSelection1) {
                            break;
                        }
                    } else {
                        break;
                    }
                }
                DLog(@"updated localeVars=%@", localeVars);
                NSString *lang = localeVars[@"LANG"];
                if (prompt.remember && localeVars != nil && lang != nil) {
                    DLog(@"Save");
                    // User chose a locale and wants us to keep using it.
                    [iTermProfilePreferences setObjectsFromDictionary:@{ KEY_CUSTOM_LOCALE: lang,
                                                                         KEY_SET_LOCALE_VARS: @(iTermSetLocalVarsModeCustom) } inProfile:self.originalProfile
                                                                model:self.profileModel];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kSessionProfileDidChange
                                                                        object:self.originalProfile[KEY_GUID]];
                }
            }
            if (!localeVars) {
                DLog(@"Using LC_CTYPE");
                localeVars = [localeGuesser dictionaryWithLC_CTYPE];
            }
            if (localeVars) {
                DLog(@"Merge %@", localeVars);
                [env it_mergeFrom:localeVars];
            }
        }
    }
    if ([iTermAdvancedSettingsModel shouldSetLCTerminal]) {
        env[@"LC_TERMINAL"] = @"iTerm2";
        env[@"LC_TERMINAL_VERSION"] = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    }
    if (env[PWD_ENVNAME] == nil && _sshState == iTermSSHStateNone) {
        // Set "PWD"
        env[PWD_ENVNAME] = [PWD_ENVVALUE stringByExpandingTildeInPath];
        DLog(@"env[%@] was nil. Set it to home directory: %@", PWD_ENVNAME, env[PWD_ENVNAME]);
    }

    // Remove trailing slashes, unless the path is just "/"
    NSString *trimmed = [env[PWD_ENVNAME] stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    DLog(@"Trimmed pwd %@ is %@", env[PWD_ENVNAME], trimmed);
    if (trimmed.length == 0 && _sshState == iTermSSHStateNone) {
        trimmed = @"/";
    }
    DLog(@"Set env[PWD] to trimmed value %@", trimmed);
    env[PWD_ENVNAME] = trimmed;

    NSString *itermId = [self sessionId];
    if (!self.isTmuxClient) {
        env[@"TERM_FEATURES"] = [VT100Output encodedTermFeaturesForCapabilities:[self capabilities]];
    }
    env[@"ITERM_SESSION_ID"] = itermId;
    env[@"TERM_PROGRAM_VERSION"] = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    env[@"TERM_SESSION_ID"] = itermId;
    env[@"TERM_PROGRAM"] = @"iTerm.app";
    env[@"COLORTERM"] = @"truecolor";
    if ([iTermAdvancedSettingsModel shouldSetTerminfoDirs]) {
        env[@"TERMINFO_DIRS"] = [@[self.customTerminfoDir, @"/usr/share/terminfo"] componentsJoinedByString:@":"];
    }
    if (_profile[KEY_NAME]) {
        env[@"ITERM_PROFILE"] = [_profile[KEY_NAME] stringByPerformingSubstitutions:substitutions];
    }
    return env;
}

- (NSString *)customTerminfoDir {
    return [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"terminfo"];
}

- (void)arrangementWithName:(NSString *)arrangementName hasBadPWD:(NSString *)pwd {
    if (![[iTermController sharedInstance] arrangementWithName:arrangementName
                                            hasSessionWithGUID:_arrangementGUID
                                                           pwd:pwd]) {
        return;
    }

    [self.naggingController arrangementWithName:arrangementName
                                  hasInvalidPWD:pwd
                             forSessionWithGuid:_arrangementGUID];
}

- (void)startProgram:(NSString *)command
                 ssh:(BOOL)ssh
         environment:(NSDictionary *)environment
         customShell:(NSString *)customShell
              isUTF8:(BOOL)isUTF8
       substitutions:(NSDictionary *)substitutions
         arrangement:(NSString *)arrangementName
     fromArrangement:(BOOL)fromArrangement
          completion:(void (^)(BOOL))completion {
    DLog(@"startProgram:%@ ssh:%@ environment:%@ customShell:%@ isUTF8:%@ substitutions:%@ arrangementName:%@ fromArrangement:%@, self=%@",
         command,
         @(ssh),
         environment,
         customShell,
         @(isUTF8),
         substitutions,
         arrangementName,
         @(fromArrangement),
         self);
    _temporarilySuspendOffscreenMarkAlerts = fromArrangement;
    self.program = command;
    self.customShell = customShell;
    self.environment = environment ?: @{};
    self.isUTF8 = isUTF8;
    self.substitutions = substitutions ?: @{};
    _sshState = ssh ? iTermSSHStateProfile : iTermSSHStateNone;
    [self computeArgvForCommand:command substitutions:substitutions completion:^(NSArray<NSString *> *argv) {
        DLog(@"argv=%@", argv);
        NSDictionary *env = [self environmentForNewJobFromEnvironment:environment ?: @{} substitutions:substitutions];
        [self fetchAutoLogFilenameWithCompletion:^(NSString * _Nonnull autoLogFilename) {
            [_logging stop];
            [_logging autorelease];
            _logging = nil;
            [[self loggingHelper] setPath:autoLogFilename
                                  enabled:autoLogFilename != nil
                                    style:iTermLoggingStyleFromUserDefaultsValue([iTermProfilePreferences unsignedIntegerForKey:KEY_LOGGING_STYLE
                                                                                                                      inProfile:self.profile])
                        asciicastMetadata:[self asciicastMetadata]
                                   append:nil];
            if (env[PWD_ENVNAME] && arrangementName && _arrangementGUID) {
                __weak __typeof(self) weakSelf = self;
                [[iTermSlowOperationGateway sharedInstance] checkIfDirectoryExists:env[PWD_ENVNAME]
                                                                        completion:^(BOOL exists) {
                    if (exists) {
                        return;
                    }
                    [weakSelf arrangementWithName:arrangementName
                                        hasBadPWD:env[PWD_ENVNAME]];
                }];
            }
            [self injectShellIntegrationWithEnvironment:env
                                                   args:argv
                                             completion:^(NSDictionary<NSString *, NSString *> *env,
                                                          NSArray<NSString *> *argv) {
                [_shell launchWithPath:argv[0]
                             arguments:[argv subarrayFromIndex:1]
                           environment:env
                           customShell:customShell
                              gridSize:_screen.size
                              viewSize:_screen.viewSize
                      maybeScaleFactor:_textview.window.backingScaleFactor
                                isUTF8:isUTF8
                            completion:^{
                    [self sendInitialText];
                    if (completion) {
                        completion(YES);
                    }
                }];
            }];
        }];
    }];
}

- (void)injectShellIntegrationWithEnvironment:(NSDictionary<NSString *, NSString *> *)env
                                         args:(NSArray<NSString *> *)argv
                                   completion:(void (^)(NSDictionary<NSString *, NSString *> *,
                                                        NSArray<NSString *> *))completion {
    if (![iTermProfilePreferences boolForKey:KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY inProfile:self.profile]) {
        completion(env, argv);
        return;
    }
    ShellIntegrationInjector *injector = [ShellIntegrationInjector instance];
    NSString *dir = NSBundle.shellIntegrationDirectory;
    if (!dir) {
        completion(env, argv);
        return;
    }
    [injector modifyShellEnvironmentWithShellIntegrationDir:dir
                                                        env:env
                                                       argv:argv
                                                 completion:completion];
}

- (void)setParentScope:(iTermVariableScope *)parentScope {
    iTermVariableScope *scope = self.variablesScope;
    assert(parentScope != scope);  // I'm almost sure this is impossible because how could you be your own parent?

    // Remove existing variable (this is just paranoia! it shouldn't do anything)
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionParent];

    // Remove existing frame
    [scope removeFrameWithName:iTermVariableKeySessionParent];
    __block iTermVariables *variables = nil;
    // Find root frame in parent and add it it as a frame to my scope
    [parentScope.frames enumerateObjectsUsingBlock:^(iTermTuple<NSString *,iTermVariables *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        if (tuple.firstObject) {
            return;
        }
        variables = tuple.secondObject;
        [scope addVariables:tuple.secondObject toScopeNamed:iTermVariableKeySessionParent];
        *stop = YES;
    }];

    // Find non-root frames (e.g., tab) and add their variables as nonterminals to parentSession (becoming, e.g., parentSession.tab)
    [parentScope.frames enumerateObjectsUsingBlock:^(iTermTuple<NSString *,iTermVariables *> * _Nonnull tuple, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!tuple.firstObject) {
            return;
        }
        [variables setValue:tuple.secondObject forVariableNamed:tuple.firstObject];
    }];
}

// This can be called twice when using ssh; once before the conductor is ready and then again after
// it has logged in.
- (void)sendInitialText {
    if ([_profile[KEY_CUSTOM_COMMAND] isEqual:kProfilePreferenceCommandTypeSSHValue] && !_conductor) {
        DLog(@"Not sending initial text because ssh");
        return;
    }
    NSString *initialText = _profile[KEY_INITIAL_TEXT];
    if (![initialText length]) {
        return;
    }
    DLog(@"Evaluate initial text %@", initialText);

    iTermExpressionEvaluator *evaluator =
    [[[iTermExpressionEvaluator alloc] initWithStrictInterpolatedString:initialText
                                                                  scope:self.variablesScope] autorelease];
    [evaluator evaluateWithTimeout:5 completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        NSString *string = [NSString castFrom:evaluator.value];
        if (!string) {
            DLog(@"Evaluation of %@ returned %@", initialText, evaluator.value);
            return;
        }
        DLog(@"Write initial text %@", string);
        [self writeTaskNoBroadcast:string];
        [self writeTaskNoBroadcast:@"\n"];
    }];
}

- (void)launchProfileInCurrentTerminal:(Profile *)profile
                               withURL:(NSString *)url {
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    [iTermSessionLauncher launchBookmark:profile
                              inTerminal:term
                                 withURL:url
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:NO
                             canActivate:NO
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:nil
                          didMakeSession:nil
                              completion:nil];
}

- (void)selectPaneLeftInCurrentTerminal {
    [[[iTermController sharedInstance] currentTerminal] selectPaneLeft:nil];
}

- (void)selectPaneRightInCurrentTerminal {
    [[[iTermController sharedInstance] currentTerminal] selectPaneRight:nil];
}

- (void)selectPaneAboveInCurrentTerminal {
    [[[iTermController sharedInstance] currentTerminal] selectPaneUp:nil];
}

- (void)selectPaneBelowInCurrentTerminal {
    [[[iTermController sharedInstance] currentTerminal] selectPaneDown:nil];
}

- (void)_maybeWarnAboutShortLivedSessions {
    if ([iTermApplication.sharedApplication delegate].isAppleScriptTestApp) {
        // The applescript test driver doesn't care about short-lived sessions.
        return;
    }
    if (self.isSingleUseSession) {
        return;
    }
    if (_tmuxMode == TMUX_CLIENT && (_tmuxController.detached || _tmuxController.detaching)) {
        return;
    }
    if ([[NSDate date] timeIntervalSinceDate:_creationDate] < [iTermAdvancedSettingsModel shortLivedSessionDuration]) {
        NSString* theName = [_profile objectForKey:KEY_NAME];
        NSString *guid = _profile[KEY_GUID];
        if (_originalProfile && [_originalProfile[KEY_GUID] length]) {
            // Divorced sessions should use the original session's GUID to determine
            // if a warning is appropriate.
            guid = _originalProfile[KEY_GUID];
        }
        if ([self.profile[KEY_CUSTOM_COMMAND] isEqual:kProfilePreferenceCommandTypeLoginShellValue]) {
            // Not a custom command. Does the user's shell not exist maybe?
            NSString *shell = [iTermOpenDirectory userShell];
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:self.profile[KEY_GUID]];
            if (!self.isDivorced &&
                shell &&
                profile != nil &&
                !profile.profileIsDynamic &&
                ![[NSFileManager defaultManager] fileExistsAtPath:shell]) {
                NSString *theKey = [NSString stringWithFormat:@"ShellDoesNotExist_%@", guid];
                NSString *theTitle = [NSString stringWithFormat:
                                      @"The shell for this account, “%@”, does not exist. Change the profile to use /bin/zsh instead?",
                                      shell];
                const iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:theTitle
                                           actions:@[ @"OK", @"Cancel" ]
                                        identifier:theKey
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                            window:self.view.window];
                if (selection == kiTermWarningSelection0) {
                    NSDictionary *change = @{
                        KEY_CUSTOM_COMMAND: kProfilePreferenceCommandTypeCustomShellValue,
                        KEY_COMMAND_LINE: @"/bin/zsh"
                    };
                    [[ProfileModel sharedInstance] setObjectsFromDictionary:change
                                                                  inProfile:profile];
                    [[ProfileModel sharedInstance] flush];
                    [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                                        object:nil];
                }
                return;
            }
        }
        NSString *theKey = [iTermPreferences warningIdentifierForNeverWarnAboutShortLivedSessions:guid];
        NSString *theTitle = [NSString stringWithFormat:
                              @"A session ended very soon after starting. Check that the command "
                              @"in profile \"%@\" is correct.",
                              theName];
        [iTermWarning showWarningWithTitle:theTitle
                                   actions:@[ @"OK" ]
                                identifier:theKey
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                    window:self.view.window];
    }
}

- (iTermRestorableSession *)restorableSession {
    iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
    [_delegate addSession:self toRestorableSession:restorableSession];
    return restorableSession;
}

- (void)restartSession {
    DLog(@"Restart session %@", self);
    assert(self.isRestartable);
    [_naggingController willRecycleSession];
    if (_exited) {
        [self replaceTerminatedShellWithNewInstance];
    } else {
        _shouldRestart = YES;
        // We don't use a regular (SIGHUP) kill here because we must ensure
        // servers get killed on user-initiated quit. If we just HUP the shell
        // then the server won't notice until it becomes attached as an orphan
        // on the next launch. See issue 6369.
        [_shell killWithMode:iTermJobManagerKillingModeForce];
    }
}

// Terminate a replay session but not the live session
- (void)softTerminate {
    _liveSession = nil;
    [self terminate];
}

- (void)close {
    [self.delegate sessionClose:self];
}

// Request that the session close. It may or may not be undoable. Only undoable terminations support
// "restart", which is done by first calling revive and then replaceTerminatedShellWithNewInstance.
- (void)terminate {
    DLog(@"terminate called from %@", [NSThread callStackSymbols]);
    if ([[self textview] isFindingCursor]) {
        [[self textview] endFindCursor];
    }
    if (_exited && !_shortLivedSingleUse) {
        [self _maybeWarnAboutShortLivedSessions];
    }
    if (self.tmuxMode == TMUX_CLIENT) {
        assert([_delegate tmuxWindow] >= 0);
        [_tmuxController deregisterWindow:[_delegate tmuxWindow]
                               windowPane:self.tmuxPane
                                  session:self];
        // This call to fitLayoutToWindows is necessary to handle the case where
        // a small window closes and leaves behind a larger (e.g., fullscreen)
        // window. We want to set the client size to that of the smallest
        // remaining window.
        int n = [[_delegate sessions] count];
        if ([[_delegate sessions] indexOfObjectIdenticalTo:self] != NSNotFound) {
            n--;
        }
        if (n == 0) {
            // The last session in this tab closed so check if the client has
            // changed size
            DLog(@"Last session in tab closed. Check if the client has changed size");
            [_tmuxController fitLayoutToWindows];
        }
        _tmuxStatusBarMonitor.active = NO;
        [_tmuxStatusBarMonitor release];
        _tmuxStatusBarMonitor = nil;

        [self uninstallTmuxTitleMonitor];
        [self uninstallTmuxForegroundJobMonitor];
    } else if (self.tmuxMode == TMUX_GATEWAY) {
        [_tmuxController detach];
        [_tmuxGateway release];
        _tmuxGateway = nil;
    }
    BOOL undoable = (![self isTmuxClient] &&
                     !_shouldRestart &&
                     !_synthetic &&
                     ![[iTermController sharedInstance] applicationIsQuitting]);
    self.tmuxMode = TMUX_NONE;
    [_tmuxController release];
    _hideAfterTmuxWindowOpens = NO;
    _tmuxController = nil;
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionTmuxClientName];
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionTmuxPaneTitle];

    // The source pane may have just exited. Dogs and cats living together!
    // Mass hysteria!
    [[MovePaneController sharedInstance] exitMovePaneMode];

    // deregister from the notification center
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_liveSession) {
        [_liveSession terminate];
    }

    DLog(@"  terminate: exited = YES");
    [self setExited:YES];
    [_view retain];  // hardstop and revive will release this.
    if (undoable) {
        [self makeTerminationUndoable];
    } else {
        [self hardStop];
    }
    [[iTermSessionHotkeyController sharedInstance] removeSession:self];

    // final update of display. Do it async to avoid a join from a side effect.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateDisplayBecause:@"terminate session"];
    });

    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionWillTerminateNotification
                                                        object:self];
    [_delegate removeSession:self];

    _screen.delegate = nil;
    _screen.intervalTreeObserver = nil;

    _screen.terminalEnabled = NO;
    if (_view.findDriverDelegate == self) {
        _view.findDriverDelegate = nil;
    }

    [_pasteHelper abort];

    [[_delegate realParentWindow] sessionDidTerminate:self];

    _delegate = nil;
}

- (void)setExited:(BOOL)exited {
    _exited = exited;
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.exited = exited;
    }];
}

- (void)makeTerminationUndoable {
    _shell.paused = YES;
    [_textview setDataSource:nil];
    [_textview setDelegate:nil];
    [self performSelector:@selector(hardStop)
               withObject:nil
               afterDelay:[iTermProfilePreferences intForKey:KEY_UNDO_TIMEOUT
                                                   inProfile:_profile]];
    // The analyzer complains that _view is leaked here, but the delayed perform to -hardStop above
    // releases it. If it is canceled by -revive, then -revive autoreleases the view.
    [[iTermController sharedInstance] addRestorableSession:[self restorableSession]];
}

// Not undoable. Kill the process. However, you can replace the terminated shell after this.
- (void)hardStop {
    [[iTermController sharedInstance] removeSessionFromRestorableSessions:self];
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [terminal.parser forceUnhookDCS:nil];
    }];
    [_view release];  // This balances a retain in -terminate.
    [[self retain] autorelease];
    [_shell stop];
    _shell.delegate = nil;
    [_textview setDataSource:nil];
    [_textview setDelegate:nil];
    [_textview removeFromSuperview];
    if (_view.searchResultsMinimapViewDelegate == _textview.findOnPageHelper) {
        _view.searchResultsMinimapViewDelegate = nil;
    }
    self.textview = nil;
    _metalGlue.textView = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionTerminatedNotification object:self];
}

- (void)jumpToLocationWhereCurrentStatusChanged {
    if (_statusChangedAbsLine >= _screen.totalScrollbackOverflow) {
        int line = _statusChangedAbsLine - _screen.totalScrollbackOverflow;
        [_textview scrollLineNumberRangeIntoView:VT100GridRangeMake(line, 1)];
        [_textview highlightMarkOnLine:line hasErrorCode:NO];
    }
}

- (void)disinter {
    _textview.dataSource = _screen;
    _textview.delegate = self;
}

- (BOOL)revive {
    if (_shell.paused) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(hardStop)
                                                   object:nil];
        if (_shell.hasBrokenPipe) {
            if (self.isRestartable) {
                [self queueRestartSessionAnnouncement];
            }
        } else {
            DLog(@"  revive: exited=NO");
            [self setExited:NO];
        }
        _textview.dataSource = _screen;
        _textview.delegate = self;
        _screen.terminalEnabled = YES;
        _screen.delegate = self;
        if ([iTermAdvancedSettingsModel showLocationsInScrollbar] && [iTermAdvancedSettingsModel showMarksInScrollbar]) {
            _screen.intervalTreeObserver = self;
        }
        _shell.paused = NO;
        [_view setFindDriverDelegate:self];

        NSDictionary *shortcutDictionary = [iTermProfilePreferences objectForKey:KEY_SESSION_HOTKEY inProfile:self.profile];
        iTermShortcut *shortcut = [iTermShortcut shortcutWithDictionary:shortcutDictionary];
        [[iTermSessionHotkeyController sharedInstance] setShortcut:shortcut forSession:self];

        [_view autorelease];  // This balances a retain in -terminate prior to calling -makeTerminationUndoable
        [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionRevivedNotification object:self];
        return YES;
    } else {
        return NO;
    }
}

// This does not handle tmux properly. Any writing to tmux should happen in a
// caller. It does handle broadcasting to other sessions.
- (void)writeTaskImpl:(NSString *)string
             encoding:(NSStringEncoding)optionalEncoding
        forceEncoding:(BOOL)forceEncoding
         canBroadcast:(BOOL)canBroadcast
            reporting:(BOOL)reporting {
    const NSStringEncoding encoding = forceEncoding ? optionalEncoding : _screen.terminalEncoding;
    if (gDebugLogging) {
        NSArray *stack = [NSThread callStackSymbols];
        DLog(@"writeTaskImpl session=%@ encoding=%@ forceEncoding=%@ canBroadcast=%@ reporting=%@: called from %@",
             self, @(encoding), @(forceEncoding), @(canBroadcast), @(reporting), stack);
        DLog(@"writeTaskImpl string=%@", string);
    }
    if (string.length == 0) {
        DLog(@"String length is 0");
        // Abort early so the surrogate hack works.
        return;
    }
    if (canBroadcast && _screen.terminalSendReceiveMode && !self.isTmuxClient && !self.isTmuxGateway) {
        // Local echo. Only for broadcastable text to avoid printing passwords from the password manager.
        [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            [mutableState appendStringAtCursor:[string stringByMakingControlCharactersToPrintable]];
        }];
    }
    // check if we want to send this input to all the sessions
    if (canBroadcast && [[_delegate realParentWindow] broadcastInputToSession:self]) {
        // Ask the parent window to write to the other tasks.
        DLog(@"Passing input to window to broadcast it. Won't send in this call.");
        [[_delegate realParentWindow] sendInputToAllSessions:string
                                                    encoding:optionalEncoding
                                               forceEncoding:forceEncoding];
    } else if (!_exited) {
        // Send to only this session
        if (canBroadcast) {
            // It happens that canBroadcast coincides with explicit user input. This is less than
            // beautiful here, but in that case we want to turn off the bell and scroll to the
            // bottom.
            [self setBell:NO];
            PTYScroller *verticalScroller = [_view.scrollview ptyVerticalScroller];
            [verticalScroller setUserScroll:NO];
        }
        NSData *data = [self dataForInputString:string usingEncoding:encoding];
        if (_conductor.queueWrites) {
            if (!_sshWriteQueue) {
                _sshWriteQueue = [[NSMutableData alloc] init];
            }
            [_sshWriteQueue appendData:data];
            return;
        }
        if (_screen.sendingIsBlocked && !reporting) {
            DLog(@"Defer write of %@", [data stringWithEncoding:NSUTF8StringEncoding]);
            if (!_dataQueue) {
                _dataQueue = [[NSMutableArray alloc] init];
            }
            [_dataQueue addObject:data];
        } else {
            DLog(@"Write immediately: %@", [data stringWithEncoding:NSUTF8StringEncoding]);
            [self writeData:data];
        }
    }
}

- (void)writeData:(NSData *)data {
    const char *bytes = data.bytes;
    BOOL newline = NO;
    for (NSUInteger i = 0; i < data.length; i++) {
        DLog(@"Write byte 0x%02x (%c)", (((int)bytes[i]) & 0xff), bytes[i]);
        if (bytes[i] == '\r' || bytes[i] == '\n') {
            newline = YES;
        }
    }
    if (newline) {
        _activityInfo.lastNewline = [NSDate it_timeSinceBoot];
    }
    if (!_reportingFocus) {
        self.lastNonFocusReportingWrite = [NSDate date];
    }
    [_shell writeTask:data];
}

// Convert the string to the requested encoding. If the string is a lone surrogate, deal with it by
// saving the high surrogate and then combining it with a subsequent low surrogate.
- (NSData *)dataForInputString:(NSString *)string usingEncoding:(NSStringEncoding)encoding {
    NSData *data = [string dataUsingEncoding:encoding allowLossyConversion:YES];
    if (data) {
        _shell.pendingHighSurrogate = 0;
        return data;
    }
    if (string.length != 1) {
        _shell.pendingHighSurrogate = 0;
        return nil;
    }

    const unichar c = [string characterAtIndex:0];
    if (IsHighSurrogate(c)) {
        _shell.pendingHighSurrogate = c;
        DLog(@"Detected high surrogate 0x%x", (int)c);
        return nil;
    } else if (IsLowSurrogate(c) && _shell.pendingHighSurrogate) {
        DLog(@"Detected low surrogate 0x%x with pending high surrogate 0x%x", (int)c, (int)_shell.pendingHighSurrogate);
        unichar chars[2] = { _shell.pendingHighSurrogate, c };
        _shell.pendingHighSurrogate = 0;
        NSString *composite = [NSString stringWithCharacters:chars length:2];
        return [composite dataUsingEncoding:encoding allowLossyConversion:YES];
    }

    _shell.pendingHighSurrogate = 0;
    return nil;
}

- (void)writeTaskNoBroadcast:(NSString *)string {
    [self writeTaskNoBroadcast:string encoding:_screen.terminalEncoding forceEncoding:NO reporting:NO];
}

- (void)writeTaskNoBroadcast:(NSString *)string
                    encoding:(NSStringEncoding)encoding
               forceEncoding:(BOOL)forceEncoding
                   reporting:(BOOL)reporting {
    if (_conductor.handlesKeystrokes) {
        [_conductor sendKeys:[string dataUsingEncoding:encoding]];
        return;
    } else if (self.tmuxMode == TMUX_CLIENT) {
        // tmux doesn't allow us to abuse the encoding, so this can cause the wrong thing to be
        // sent (e.g., in mouse reporting).
        [[_tmuxController gateway] sendKeys:string
                               toWindowPane:self.tmuxPane];
        return;
    }
    [self writeTaskImpl:string encoding:encoding forceEncoding:forceEncoding canBroadcast:NO reporting:reporting];
}

- (void)performTmuxCommand:(NSString *)command {
    [self.tmuxController.gateway sendCommand:command
                              responseTarget:nil
                            responseSelector:NULL];
}

- (void)setTmuxController:(TmuxController *)tmuxController {
    [_tmuxController autorelease];
    _tmuxController = [tmuxController retain];
    NSDictionary<NSString *, NSString *> *dict = [tmuxController userVarsForPane:self.tmuxPane];
    for (NSString *key in dict) {
        if (![key hasPrefix:@"user."]) {
            continue;
        }
        [self.variablesScope setValue:dict[key] forVariableNamed:key];
    }
}

- (void)handleKeypressInTmuxGateway:(NSEvent *)event {
    const unichar unicode = [event.characters length] > 0 ? [event.characters characterAtIndex:0] : 0;
    [self handleCharacterPressedInTmuxGateway:unicode];
}

- (void)handleCharacterPressedInTmuxGateway:(unichar)unicode {
    if (unicode == 27) {
        [self tmuxDetach];
    } else if (unicode == 'L') {
        _tmuxGateway.tmuxLogging = !_tmuxGateway.tmuxLogging;
        [self printTmuxMessage:[NSString stringWithFormat:@"tmux logging %@", (_tmuxGateway.tmuxLogging ? @"on" : @"off")]];
    } else if (unicode == 'C') {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = @"Enter command to send tmux:";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        NSTextField *tmuxCommand = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
        [tmuxCommand setEditable:YES];
        [tmuxCommand setSelectable:YES];
        [alert setAccessoryView:tmuxCommand];
        [alert layout];
        [[alert window] makeFirstResponder:tmuxCommand];
        if ([alert runModal] == NSAlertFirstButtonReturn && [[tmuxCommand stringValue] length]) {
            [self printTmuxMessage:[NSString stringWithFormat:@"Run command \"%@\"", [tmuxCommand stringValue]]];
            [_tmuxGateway sendCommand:[tmuxCommand stringValue]
                       responseTarget:self
                     responseSelector:@selector(printTmuxCommandOutputToScreen:)];
        }
    } else if (unicode == 'X') {
        [self forceTmuxDetach];
    }
}

- (void)forceTmuxDetach {
    switch (self.tmuxMode) {
        case TMUX_GATEWAY:
            [self printTmuxMessage:@"Exiting tmux mode, but tmux client may still be running."];
            [self tmuxHostDisconnected:[[_tmuxGateway.dcsID copy] autorelease]];
            return;
        case TMUX_NONE:
            return;
        case TMUX_CLIENT:
            [self.tmuxGatewaySession forceTmuxDetach];
            return;
    }
}

- (void)writeLatin1EncodedData:(NSData *)data broadcastAllowed:(BOOL)broadcast reporting:(BOOL)reporting {
    // `data` contains raw bytes we want to pass through. I believe Latin-1 is the only encoding that
    // won't perform any transformation when converting from data to string. This is needed because
    // sometimes the user wants to send particular bytes regardless of the encoding (e.g., the
    // "send hex codes" keybinding action, or certain mouse reporting modes that abuse encodings).
    // This won't work for non-UTF-8 data with tmux.
    NSString *string = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (broadcast) {
        [self writeTask:string encoding:NSISOLatin1StringEncoding forceEncoding:YES reporting:reporting];
    } else {
        [self writeTaskNoBroadcast:string encoding:NSISOLatin1StringEncoding forceEncoding:YES reporting:reporting];
    }
}

- (void)writeStringWithLatin1Encoding:(NSString *)string {
    [self writeTask:string encoding:NSISOLatin1StringEncoding forceEncoding:YES reporting:NO];
}

- (void)writeTask:(NSString *)string {
    [self writeTask:string encoding:_screen.terminalEncoding forceEncoding:NO reporting:NO];
}

// If forceEncoding is YES then optionalEncoding will be used regardless of the session's preferred
// encoding. If it is NO then the preferred encoding is used. This is necessary because this method
// might send the string off to the window to get broadcast to other sessions which might have
// different encodings.
- (void)writeTask:(NSString *)string
         encoding:(NSStringEncoding)optionalEncoding
    forceEncoding:(BOOL)forceEncoding
        reporting:(BOOL)reporting {
    NSStringEncoding encoding = forceEncoding ? optionalEncoding : _screen.terminalEncoding;
    if (self.tmuxMode == TMUX_CLIENT || _conductor.handlesKeystrokes || _connectingSSH) {
        [self setBell:NO];
        if ([[_delegate realParentWindow] broadcastInputToSession:self]) {
            [[_delegate realParentWindow] sendInputToAllSessions:string
                                                        encoding:optionalEncoding
                                                   forceEncoding:forceEncoding];
        } else if (_conductor.handlesKeystrokes) {
            [_conductor sendKeys:[string dataUsingEncoding:encoding]];
        } else if (_connectingSSH) {
            [_queuedConnectingSSH appendData:[string dataUsingEncoding:encoding]];
        } else {
            assert(self.tmuxMode == TMUX_CLIENT);
            [[_tmuxController gateway] sendKeys:string
                                   toWindowPane:self.tmuxPane];
        }
        PTYScroller* ptys = (PTYScroller*)[_view.scrollview verticalScroller];
        [ptys setUserScroll:NO];
        return;
    } else if (self.tmuxMode == TMUX_GATEWAY) {
        // Use keypresses for tmux gateway commands for development and debugging.
        for (int i = 0; i < string.length; i++) {
            unichar unicode = [string characterAtIndex:i];
            [self handleCharacterPressedInTmuxGateway:unicode];
        }
        return;
    }
    self.currentMarkOrNotePosition = nil;
    [self writeTaskImpl:string encoding:encoding forceEncoding:forceEncoding canBroadcast:YES reporting:reporting];
}

// This is run in PTYTask's thread. It parses the input here and then queues an async task to run
// in the main thread to execute the parsed tokens.
- (void)threadedReadTask:(char *)buffer length:(int)length {
    [_screen threadedReadTask:buffer length:length];
}

- (BOOL)haveResizedRecently {
    const NSTimeInterval kGracePeriodAfterResize = 0.25;
    return [NSDate timeIntervalSinceReferenceDate] < _lastResize + kGracePeriodAfterResize;
}

- (void)setAllTriggersEnabled:(BOOL)enabled {
    NSArray<NSDictionary *> *triggers = self.profile[KEY_TRIGGERS];
    triggers = [triggers mapWithBlock:^id(NSDictionary *dict) {
        return [dict dictionaryBySettingObject:@(!enabled) forKey:kTriggerDisabledKey];
    }];
    if (!triggers) {
        return;
    }
    [self setSessionSpecificProfileValues:@{ KEY_TRIGGERS: triggers }];
}

- (BOOL)anyTriggerCanBeEnabled {
    NSArray<NSDictionary *> *triggers = self.profile[KEY_TRIGGERS];
    return [triggers anyWithBlock:^BOOL(NSDictionary *dict) {
        return [dict[kTriggerDisabledKey] boolValue];
    }];
}

- (BOOL)anyTriggerCanBeDisabled {
    NSArray<NSDictionary *> *triggers = self.profile[KEY_TRIGGERS];
    return [triggers anyWithBlock:^BOOL(NSDictionary *dict) {
        return ![dict[kTriggerDisabledKey] boolValue];
    }];
}

- (NSArray<iTermTuple<NSString *, NSNumber *> *> *)triggerTuples {
    NSArray<NSDictionary *> *triggers = self.profile[KEY_TRIGGERS];
    return [triggers mapWithBlock:^id(NSDictionary *dict) {
        return [iTermTuple tupleWithObject:dict[kTriggerRegexKey]
                                 andObject:@(![dict[kTriggerDisabledKey] boolValue])];
    }];
}

- (void)toggleTriggerEnabledAtIndex:(NSInteger)index {
    NSMutableArray<NSDictionary *> *mutableTriggers = [[self.profile[KEY_TRIGGERS] mutableCopy] autorelease];
    NSDictionary *triggerDict = mutableTriggers[index];
    const BOOL disabled = [triggerDict[kTriggerDisabledKey] boolValue];
    mutableTriggers[index] = [triggerDict dictionaryBySettingObject:@(!disabled) forKey:kTriggerDisabledKey];
    [self setSessionSpecificProfileValues:@{ KEY_TRIGGERS: mutableTriggers }];
}

- (void)appendBrokenPipeMessage:(NSString *)unpaddedMessage {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        NSString *const message = [NSString stringWithFormat:@" %@ ", unpaddedMessage];
        if (mutableState.cursorX != 1) {
            [mutableState appendCarriageReturnLineFeed];
        }
        screen_char_t savedFgColor = [terminal foregroundColorCode];
        screen_char_t savedBgColor = [terminal backgroundColorCode];
        // This color matches the color used in BrokenPipeDivider.png.
        [terminal setForeground24BitColor:[NSColor colorWithCalibratedRed:70.0/255.0
                                                                    green:83.0/255.0
                                                                     blue:246.0/255.0
                                                                    alpha:1]];
        [terminal setBackgroundColor:ALTSEM_DEFAULT
                  alternateSemantics:YES];
        [terminal updateDefaultChar];
        mutableState.currentGrid.defaultChar = terminal.defaultChar;
        int width = (mutableState.width - message.length) / 2;
        if (width > 0) {
            [mutableState appendNativeImageAtCursorWithName:@"BrokenPipeDivider"
                                                      width:width];
        }
        [mutableState appendStringAtCursor:message];
        if (width > 0) {
            [mutableState appendNativeImageAtCursorWithName:@"BrokenPipeDivider"
                                                      width:(mutableState.width - mutableState.cursorX + 1)];
        }
        [mutableState appendCarriageReturnLineFeed];
        [terminal setForegroundColor:savedFgColor.foregroundColor
                  alternateSemantics:savedFgColor.foregroundColorMode == ColorModeAlternate];
        [terminal setBackgroundColor:savedBgColor.backgroundColor
                  alternateSemantics:savedBgColor.backgroundColorMode == ColorModeAlternate];
        [terminal updateDefaultChar];
        mutableState.currentGrid.defaultChar = terminal.defaultChar;
    }];
}

// This is called in the main thread when coprocesses write to a tmux client.
- (void)tmuxClientWrite:(NSData *)data {
    if (!self.isTmuxClient) {
        return;
    }
    NSString *string = [[[NSString alloc] initWithData:data encoding:self.encoding] autorelease];
    [self writeTask:string];
}

- (void)threadedTaskBrokenPipe {
    DLog(@"threaded task broken pipe");
    // Put the call to brokenPipe in the same queue as the token executor to avoid a race.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self brokenPipe];
    });
}

- (void)taskDidChangePaused:(PTYTask *)task paused:(BOOL)paused {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.taskPaused = paused;
    }];
}

- (void)taskMuteCoprocessDidChange:(PTYTask *)task hasMuteCoprocess:(BOOL)hasMuteCoprocess {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.hasMuteCoprocess = hasMuteCoprocess;
    }];
}

- (void)taskDiedImmediately {
    // Let initial creation finish, then report the broken pipe. This happens if the file descriptor
    // server dies immediately.
    [self performSelector:@selector(brokenPipe) withObject:nil afterDelay:0];
}

- (void)taskDidChangeTTY:(PTYTask *)task {
    [self.variablesScope setValue:task.tty forVariableNamed:iTermVariableKeySessionTTY];
}

// Main thread
- (void)taskDidRegister:(PTYTask *)task {
    [self updateTTYSize];
}

- (void)tmuxDidDisconnect {
    DLog(@"tmuxDidDisconnect");
    if (_exited) {
        return;
    }
    [self setExited:YES];
    [self cleanUpAfterBrokenPipe];
    [self appendBrokenPipeMessage:@"tmux detached"];
    switch (self.endAction) {
        case iTermSessionEndActionClose:
            if ([_delegate sessionShouldAutoClose:self]) {
                [_delegate softCloseSession:self];
                return;
            }
            break;

        case iTermSessionEndActionRestart:
        case iTermSessionEndActionDefault:
            if (_tmuxWindowClosingByClientRequest ||
                [self.naggingController tmuxWindowsShouldCloseAfterDetach]) {
                [_delegate softCloseSession:self];
                return;
            }
            break;
    }

    [self updateDisplayBecause:@"session ended"];
}

- (void)cleanUpAfterBrokenPipe {
    [self setExited:YES];
    [_logging stop];
    [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionTerminatedNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    [_delegate updateLabelAttributes];
}

// Called when the file descriptor closes. If -terminate was already called this does nothing.
// Otherwise, you can call replaceTerminatedShellWithNewInstance after this to restart the session.
- (void)brokenPipe {
    DLog(@"  brokenPipe %@ task=%@\n%@", self, self.shell, [NSThread callStackSymbols]);
    if (_exited) {
        DLog(@"  brokenPipe: Already exited");
        return;
    }
    // Ensure we don't leak the monoserver unix domain socket file descriptor.
    [_shell killWithMode:iTermJobManagerKillingModeBrokenPipe];
    if ([self shouldPostUserNotification] &&
        [iTermProfilePreferences boolForKey:KEY_SEND_SESSION_ENDED_ALERT inProfile:self.profile]) {
        [[iTermNotificationController sharedInstance] notify:@"Session Ended"
                                             withDescription:[NSString stringWithFormat:@"Session \"%@\" in tab #%d just terminated.",
                                                              [[self name] removingHTMLFromTabTitleIfNeeded],
                                                              [_delegate tabNumber]]];
    }

    DLog(@"  brokenPipe: set exited = YES");
    [self cleanUpAfterBrokenPipe];

    if (_shouldRestart) {
        _modeHandler.mode = iTermSessionModeDefault;
        [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                 VT100ScreenMutableState *mutableState,
                                                 id<VT100ScreenDelegate> delegate) {
            [terminal resetForReason:VT100TerminalResetReasonBrokenPipe];
            [self appendBrokenPipeMessage:@"Session Restarted"];
            [self replaceTerminatedShellWithNewInstance];
        }];
        return;
    }

    if (_shortLivedSingleUse) {
        [[iTermBuriedSessions sharedInstance] restoreSession:self];
        [self appendBrokenPipeMessage:@"Finished"];
        // restart is not respected here because it doesn't make sense and would make for an awful bug.
        if (self.endAction == iTermSessionEndActionClose) {
            [_delegate closeSession:self];
        }
        return;
    }
    if (self.tmuxMode == TMUX_GATEWAY) {
        [self forceTmuxDetach];
    }
    [self appendBrokenPipeMessage:@"Session Ended"];
    switch (self.endAction) {
        case iTermSessionEndActionClose:
            if ([_delegate sessionShouldAutoClose:self]) {
                [_delegate closeSession:self];
                return;
            }
            break;

        case iTermSessionEndActionRestart:
            if ([self isRestartable]) {
                [self performSelector:@selector(maybeReplaceTerminatedShellWithNewInstance) withObject:nil afterDelay:1];
                return;
            }
            break;

        case iTermSessionEndActionDefault:
            break;
    }

    // Offer to restart the session by rerunning its program.
    if ([self isRestartable]) {
        [self queueRestartSessionAnnouncement];
    }
    [self updateDisplayBecause:@"session ended"];
}

- (void)queueRestartSessionAnnouncement {
    if ([iTermAdvancedSettingsModel suppressRestartAnnouncement]) {
        return;
    }
    if (_shortLivedSingleUse) {
        return;
    }
    [self.naggingController brokenPipe];
}

- (BOOL)isRestartable {
    return _program != nil;
}

- (void)maybeReplaceTerminatedShellWithNewInstance {
    // The check for screen.terminalEnabled is because after -terminate is called, it is no longer safe
    // to replace the terminated shell with a new instance unless you first do -revive. When
    // the terminal is disabled you can't write text to the screen.
    // In other words: broken pipe -> close window -> timer calls this: nothing should happen
    //                 broken pipe -> close window -> undo close -> timer calls this: work normally
    if (_screen.terminalEnabled && self.isRestartable && _exited) {
        [self replaceTerminatedShellWithNewInstance];
    }
}

// NOTE: Not safe to call this after -terminate, unless you first call -revive. It *is* safe
// to call this after -brokenPipe, provided -terminate wasn't already called.
- (void)replaceTerminatedShellWithNewInstance {
    assert(self.isRestartable);
    assert(_exited);
    _shouldRestart = NO;
    DLog(@"  replaceTerminatedShellWithNewInstance: exited <- NO");
    [self setExited:NO];
    [_shell autorelease];
    _shell = nil;
    [_logging stop];

    self.guid = [NSString uuid];
    _shell = [[PTYTask alloc] init];
    [_shell setDelegate:self];
    [_shell.winSizeController setGridSize:_screen.size
                                 viewSize:_screen.viewSize
                              scaleFactor:self.backingScaleFactor];
    [self resetForRelaunch];
    __weak __typeof(self) weakSelf = self;
    [self startProgram:_program
                   ssh:_sshState == iTermSSHStateProfile
           environment:_environment
           customShell:_customShell
                isUTF8:_isUTF8
         substitutions:_substitutions
           arrangement:nil
       fromArrangement:NO
            completion:^(BOOL ok) {
        [weakSelf.delegate sessionDidRestart:self];
    }];
    [_naggingController willRecycleSession];
    DLog(@"  replaceTerminatedShellWithNewInstance: return with terminalEnabled=%@", @(_screen.terminalEnabled));
}

- (void)lockScroll {
    PTYScroller *scroller = [PTYScroller castFrom:self.view.scrollview.verticalScroller];
    scroller.userScroll = YES;
}

- (NSSize)idealScrollViewSizeWithStyle:(NSScrollerStyle)scrollerStyle {
    NSSize innerSize = NSMakeSize([_screen width] * [_textview charWidth] + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2,
                                  [_screen height] * [_textview lineHeight] + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2);
    BOOL hasScrollbar = [[_delegate realParentWindow] scrollbarShouldBeVisible];
    NSSize outerSize =
    [PTYScrollView frameSizeForContentSize:innerSize
                   horizontalScrollerClass:nil
                     verticalScrollerClass:hasScrollbar ? [PTYScroller class] : nil
                                borderType:NSNoBorder
                               controlSize:NSControlSizeRegular
                             scrollerStyle:scrollerStyle];
    return outerSize;
}

- (BOOL)setScrollBarVisible:(BOOL)visible style:(NSScrollerStyle)style {
    BOOL changed = NO;
    if (self.view.scrollview.hasVerticalScroller != visible) {
        changed = YES;
    }
    [[self.view scrollview] setHasVerticalScroller:visible];

    if (self.view.scrollview.scrollerStyle != style) {
        changed = YES;
    }
    [[self.view scrollview] setScrollerStyle:style];
    [[self textview] updateScrollerForBackgroundColor];

    if (changed) {
        [self.view updateLayout];
    }

    return changed;
}

- (iTermKeyBindingAction *)_keyBindingActionForEvent:(NSEvent *)event {
    // Check if we have a custom key mapping for this event
    iTermKeyBindingAction *action =
    [iTermKeyMappings actionForKeystroke:[iTermKeystroke withEvent:event]
                             keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];
    return action;
}

- (BOOL)hasTextSendingKeyMappingForEvent:(NSEvent *)event {
    iTermKeyBindingAction *action = [self _keyBindingActionForEvent:event];
    if (action.keyAction == KEY_ACTION_IGNORE) {
        return YES;
    }
    return [action sendsText];
}

+ (BOOL)_recursiveSelectMenuWithSelector:(SEL)selector inMenu:(NSMenu *)menu {
    for (NSMenuItem* item in [menu itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if ([item hasSubmenu]) {
            if ([PTYSession _recursiveSelectMenuWithSelector:selector inMenu:[item submenu]]) {
                return YES;
            }
        } else if ([item action] == selector) {
            [NSApp sendAction:[item action]
                           to:[item target]
                         from:item];
            return YES;
        }
    }
    return NO;
}

+ (BOOL)_recursiveSelectMenuItemWithTitle:(NSString*)title identifier:(NSString *)identifier inMenu:(NSMenu*)menu {
    [menu update];

    if (menu == [NSApp windowsMenu] &&
        [[NSApp keyWindow] respondsToSelector:@selector(_moveToScreen:)] &&
        [NSScreen it_stringLooksLikeUniqueKey:identifier]) {
        NSScreen *screen = [NSScreen it_screenWithUniqueKey:identifier];
        if (screen) {
            [NSApp sendAction:@selector(_moveToScreen:) to:nil from:screen];
            return YES;
        }
    }

    for (NSMenuItem* item in [menu itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if ([item hasSubmenu]) {
            if ([PTYSession _recursiveSelectMenuItemWithTitle:title identifier:identifier inMenu:[item submenu]]) {
                return YES;
            }
        }
        if ([ITAddressBookMgr shortcutIdentifier:identifier title:title matchesItem:item]) {
            if (item.hasSubmenu) {
                return YES;
            }
            [NSApp sendAction:[item action]
                           to:[item target]
                         from:item];
            return YES;
        }
    }
    return NO;
}

+ (BOOL)handleShortcutWithoutTerminal:(NSEvent *)event {
    // Check if we have a custom key mapping for this event
    iTermKeyBindingAction *action = [iTermKeyMappings actionForKeystroke:[iTermKeystroke withEvent:event]
                                                             keyMappings:[iTermKeyMappings globalKeyMap]];
    if (!action) {
        return NO;
    }
    return [PTYSession performKeyBindingAction:action event:event];
}

+ (void)selectMenuItemWithSelector:(SEL)theSelector {
    if (![self _recursiveSelectMenuWithSelector:theSelector inMenu:[NSApp mainMenu]]) {
        DLog(@"Beep: failed to find menu item with selector %@", NSStringFromSelector(theSelector));
        NSBeep();
    }
}

+ (void)selectMenuItem:(NSString*)theName {
    NSArray *parts = [theName componentsSeparatedByString:@"\n"];
    NSString *title = parts.firstObject;
    NSString *identifier = nil;
    if (parts.count > 1) {
        identifier = parts[1];
    }
    if (![self _recursiveSelectMenuItemWithTitle:title identifier:identifier inMenu:[NSApp mainMenu]]) {
        DLog(@"Beep: failed to find menu item with title %@ and identifier %@", title, identifier);
        NSBeep();
    }
}

- (BOOL)willHandleEvent:(NSEvent *) theEvent
{
    return NO;
}

- (void)handleEvent:(NSEvent *)theEvent
{
}

- (void)insertNewline:(id)sender {
    [self insertText:@"\n"];
}

- (void)insertTab:(id)sender {
    [self insertText:@"\t"];
}

- (void)moveUp:(id)sender {
    [self writeLatin1EncodedData:[_screen.terminalOutput keyArrowUp:0] broadcastAllowed:YES reporting:NO];
}

- (void)moveDown:(id)sender {
    [self writeLatin1EncodedData:[_screen.terminalOutput keyArrowDown:0] broadcastAllowed:YES reporting:NO];
}

- (void)moveLeft:(id)sender {
    [self writeLatin1EncodedData:[_screen.terminalOutput keyArrowLeft:0] broadcastAllowed:YES reporting:NO];
}

- (void)moveRight:(id)sender {
    [self writeLatin1EncodedData:[_screen.terminalOutput keyArrowRight:0] broadcastAllowed:YES reporting:NO];
}

- (void)pageUp:(id)sender {
    [self writeLatin1EncodedData:[_screen.terminalOutput keyPageUp:0] broadcastAllowed:YES reporting:NO];
}

- (void)pageDown:(id)sender {
    [self writeLatin1EncodedData:[_screen.terminalOutput keyPageDown:0] broadcastAllowed:YES reporting:NO];
}

+ (NSString*)pasteboardString {
    return [NSString stringFromPasteboard];
}

- (void)insertText:(NSString *)string {
    if (_exited) {
        return;
    }

    // Note: there used to be a weird special case where 0xa5 got converted to
    // backslash. I think it was based on a misunderstanding of how encodings
    // work and it should've been removed like 10 years ago.
    if (string != nil) {
        if (gDebugLogging) {
            DebugLog([NSString stringWithFormat:@"writeTask:%@", string]);
        }
        [self writeTask:string];
    }
}

- (NSData *)dataByRemovingControlCodes:(NSData *)data {
    NSMutableData *output = [NSMutableData dataWithCapacity:[data length]];
    const unsigned char *p = data.bytes;
    int start = 0;
    int i = 0;
    for (i = 0; i < data.length; i++) {
        if (p[i] < ' ' && p[i] != '\n' && p[i] != '\r' && p[i] != '\t' && p[i] != 12) {
            if (i > start) {
                [output appendBytes:p + start length:i - start];
            }
            start = i + 1;
        }
    }
    if (i > start) {
        [output appendBytes:p + start length:i - start];
    }
    return output;
}

- (void)pasteCommand:(NSString *)text {
    PasteEvent *event = [_pasteHelper pasteEventWithString:text
                                                    slowly:NO
                                          escapeShellChars:NO
                                                  isUpload:NO
                                           allowBracketing:YES
                                              tabTransform:NO
                                              spacesPerTab:0
                                                  progress:^(NSInteger progress) {}];
    event.defaultChunkSize = 80;
    event.defaultDelay = 0.02;
    event.chunkKey = @"";
    event.delayKey = @"";
    event.flags = kPasteFlagsDisableWarnings | kPasteFlagsCommands;
    [_pasteHelper tryToPasteEvent:event];
}

- (void)runCommand:(NSString *)command
       inDirectory:(NSString *)directory
            onHost:(NSString *)hostname
            asUser:(NSString *)username {
    if (hostname) {
        NSString *ssh;
        if (username) {
            ssh = [NSString stringWithFormat:@"it2ssh %@@%@\n", username, hostname];
        } else {
            ssh = [NSString stringWithFormat:@"it2ssh %@\n", hostname];
        }
        [self pasteCommand:ssh];
        [_pendingConductor autorelease];
        _pendingConductor = [^(PTYSession *session) {
            [session runCommand:command inDirectory:directory onHost:nil asUser:nil];
        } copy];
    } else {
        NSString *escapedDirectory = [directory stringWithEscapedShellCharactersIncludingNewlines:YES];
        NSString *text = [NSString stringWithFormat:@"cd %@ && %@\n", escapedDirectory, command];
        [self pasteCommand:text];
    }
}

- (void)pasteString:(NSString *)aString {
    [self pasteString:aString flags:0];
}

- (void)pasteStringWithoutBracketing:(NSString *)theString {
    [self pasteString:theString flags:kPTYSessionPasteBracketingDisabled];
}

- (void)deleteBackward:(id)sender {
    unsigned char p = 0x08; // Ctrl+H

    [self writeLatin1EncodedData:[NSData dataWithBytes:&p length:1] broadcastAllowed:YES reporting:NO];
}

- (void)deleteForward:(id)sender {
    unsigned char p = 0x7F; // DEL

    [self writeLatin1EncodedData:[NSData dataWithBytes:&p length:1] broadcastAllowed:YES reporting:NO];
}

- (PTYScroller *)textViewVerticalScroller {
    return (PTYScroller *)[_view.scrollview verticalScroller];
}

- (BOOL)textViewHasCoprocess {
    return [_shell hasCoprocess];
}

- (void)textViewStopCoprocess {
    [_shell stopCoprocess];
}

- (BOOL)shouldPostUserNotification {
    if (!_screen.postUserNotifications) {
        return NO;
    }
    if (_shortLivedSingleUse) {
        return NO;
    }
    if (![_delegate sessionBelongsToVisibleTab]) {
        return YES;
    }
    BOOL windowIsObscured =
    ([[iTermController sharedInstance] terminalIsObscured:_delegate.realParentWindow]);
    return (windowIsObscured);
}

- (BOOL)hasSelection {
    return [_textview.selection hasSelection];
}

- (void)openSelection {
    long long absLineNumber;
    NSArray *subSelections = _textview.selection.allSubSelections;
    if ([subSelections count]) {
        iTermSubSelection *firstSub = subSelections[0];
        absLineNumber = firstSub.absRange.coordRange.start.y;
    } else {
        absLineNumber = _textview.selection.liveRange.coordRange.start.y;
    }
    const long long overflow = _screen.totalScrollbackOverflow;
    if (absLineNumber < overflow || absLineNumber - overflow > INT_MAX) {
        return;
    }
    const int lineNumber = absLineNumber - overflow;

    // TODO: Figure out if this is a remote host and download/open if that's the case.
    NSString *workingDirectory = [_screen workingDirectoryOnLine:lineNumber];
    NSString *selection = [_textview selectedText];
    if (!selection.length) {
        DLog(@"Beep: no selection");
        NSBeep();
        return;
    }

    [self open:selection workingDirectory:workingDirectory];
}

- (void)open:(NSString *)selection workingDirectory:(NSString *)workingDirectory {
    iTermSemanticHistoryController *semanticHistoryController = _textview.semanticHistoryController;

    // NOTE: The synchronous API is used here because this is a user-initiated action. We don't want
    // things to change out from under us. It's ok to block the UI while waiting for disk access
    // to complete.
    NSString *rawFilename =
    [semanticHistoryController pathOfExistingFileFoundWithPrefix:selection
                                                          suffix:@""
                                                workingDirectory:workingDirectory
                                            charsTakenFromPrefix:nil
                                            charsTakenFromSuffix:nil
                                                  trimWhitespace:YES];
    if (rawFilename &&
        ![[rawFilename stringByReplacingOccurrencesOfString:@"//" withString:@"/"] isEqualToString:@"/"]) {
        NSString *lineNumber = nil;
        NSString *columnNumber = nil;
        NSString *cleanedup = [semanticHistoryController cleanedUpPathFromPath:rawFilename
                                                                        suffix:nil
                                                              workingDirectory:workingDirectory
                                                           extractedLineNumber:&lineNumber
                                                                  columnNumber:&columnNumber];
        __weak __typeof(self) weakSelf = self;
        [_textview openSemanticHistoryPath:cleanedup
                             orRawFilename:rawFilename
                                  fragment:nil
                          workingDirectory:workingDirectory
                                lineNumber:lineNumber
                              columnNumber:columnNumber
                                    prefix:selection
                                    suffix:@""
                                completion:^(BOOL ok) {
            if (!ok) {
                [weakSelf tryOpenStringAsURL:selection];
            }
        }];
        return;
    }

    [self tryOpenStringAsURL:selection];
}

- (void)textViewOpen:(NSString *)string
    workingDirectory:(NSString *)folder
          remoteHost:(id<VT100RemoteHostReading>)remoteHost {
    // TODO: Open files on remote hosts when using ssh integration
    if (remoteHost.isLocalhost) {
        [self open:string workingDirectory:folder];
    } else {
        [self tryOpenStringAsURL:string];
    }
}

- (void)tryOpenStringAsURL:(NSString *)selection {
    // Try to open it as a URL.
    NSURL *url =
    [NSURL URLWithUserSuppliedString:[selection stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    DLog(@"Beep: bad url %@", selection);
    NSBeep();
}

- (void)setBell:(BOOL)flag {
    if (flag != _bell) {
        _bell = flag;
        [_delegate setBell:flag];
        if (_bell) {
            if ([_textview keyIsARepeat] == NO &&
                [self shouldPostUserNotification] &&
                [iTermProfilePreferences boolForKey:KEY_SEND_BELL_ALERT inProfile:self.profile]) {
                [[iTermNotificationController sharedInstance] notify:@"Bell"
                                                     withDescription:[NSString stringWithFormat:@"Session %@ #%d just rang a bell!",
                                                                      [[self name] removingHTMLFromTabTitleIfNeeded],
                                                                      [_delegate tabNumber]]
                                                         windowIndex:[self screenWindowIndex]
                                                            tabIndex:[self screenTabIndex]
                                                           viewIndex:[self screenViewIndex]];
            }
        }
    }
}

- (NSString *)ansiColorsMatchingForeground:(NSDictionary *)fg
                             andBackground:(NSDictionary *)bg
                                inBookmark:(Profile *)aDict
{
    NSColor *fgColor;
    NSColor *bgColor;
    fgColor = [ITAddressBookMgr decodeColor:fg];
    bgColor = [ITAddressBookMgr decodeColor:bg];

    int bgNum = -1;
    int fgNum = -1;
    for(int i = 0; i < 16; ++i) {
        NSString* key = [self amendedColorKey:[NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i]];
        if ([fgColor isEqual:[ITAddressBookMgr decodeColor:[aDict objectForKey:key]]]) {
            fgNum = i;
        }
        if ([bgColor isEqual:[ITAddressBookMgr decodeColor:[aDict objectForKey:key]]]) {
            bgNum = i;
        }
    }

    if (bgNum < 0 || fgNum < 0) {
        if ([iTermAdvancedSettingsModel useColorfgbgFallback]) {
            if ([fgColor brightnessComponent] > [bgColor brightnessComponent]) {
                return @"15;0";
            } else {
                return @"0;15";
            }
        }
        return nil;
    }

    return ([[NSString alloc] initWithFormat:@"%d;%d", fgNum, bgNum]);
}

- (void)loadInitialColorTableAndResetCursorGuide {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState loadInitialColorTable];
    }];
    [self resetCursorGuide];
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf markProfileInitialized];
    });
}

- (void)resetCursorGuide {
    _textview.highlightCursorLine = [iTermProfilePreferences boolForColorKey:KEY_USE_CURSOR_GUIDE
                                                                        dark:[NSApp effectiveAppearance].it_isDark
                                                                     profile:_profile];
}

- (void)markProfileInitialized {
    DLog(@"Mark profile initialized %@", self);
    _profileInitialized = YES;
}

- (NSColor *)tabColorInProfile:(NSDictionary *)profile {
    const BOOL dark = _screen.colorMap.darkMode;
    if ([iTermProfilePreferences boolForColorKey:KEY_USE_TAB_COLOR dark:dark profile:profile]) {
        return [iTermProfilePreferences colorForKey:KEY_TAB_COLOR dark:dark profile:profile];
    }
    return nil;
}

- (void)setColorsFromPresetNamed:(NSString *)presetName {
    iTermColorPreset *settings = [iTermColorPresets presetWithName:presetName];
    if (!settings) {
        return;
    }
    const BOOL presetUsesModes = settings[KEY_FOREGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX] != nil;
    for (NSString *colorName in [ProfileModel colorKeysWithModes:presetUsesModes]) {
        iTermColorDictionary *colorDict = [settings iterm_presetColorWithName:colorName];
        if (colorDict) {
            [self setSessionSpecificProfileValues:@{ colorName: colorDict }];
        }
    }
    [self setSessionSpecificProfileValues:@{ KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE: @(presetUsesModes) }];
}

- (void)sharedProfileDidChange
{
    NSDictionary *updatedProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:_originalProfile[KEY_GUID]];
    if (!updatedProfile) {
        return;
    }
    if (!self.isDivorced) {
        [self setPreferencesFromAddressBookEntry:updatedProfile];
        [self setProfile:updatedProfile];
        return;
    }

    // Copy non-overridden fields over.
    NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:_profile];
    NSMutableArray *noLongerOverriddenFields = [NSMutableArray array];
    NSMutableSet *keys = [NSMutableSet setWithArray:[updatedProfile allKeys]];
    [keys addObjectsFromArray:[_profile allKeys]];
    for (NSString *key in keys) {
        NSObject *originalValue = updatedProfile[key];
        NSObject *currentValue = _profile[key];
        if ([_overriddenFields containsObject:key]) {
            if ([originalValue isEqual:currentValue]) {
                [noLongerOverriddenFields addObject:key];
            }
        } else {
            if (!originalValue) {
                DLog(@"Unset %@ in session because it was removed from shared profile", key);
                [temp removeObjectForKey:key];
            } else {
                if (![originalValue isEqual:temp[key]]) {
                    DLog(@"Update session for key %@ from %@ -> %@", key, temp[key], originalValue);
                }
                temp[key] = originalValue;
            }
        }
    }

    // For fields that are no longer overridden because the shared profile took on the same value
    // as the sessions profile, remove those keys from overriddenFields.
    for (NSString *key in noLongerOverriddenFields) {
        DLog(@"%p: %@ is no longer overridden because shared profile now matches session profile value of %@",
             self, key, temp[key]);
        [_overriddenFields removeObject:key];
    }
    DLog(@"After shared profile change overridden keys are: %@", _overriddenFields);

    // Update saved state.
    [[ProfileModel sessionsInstance] setBookmark:temp withGuid:temp[KEY_GUID]];
    [self setPreferencesFromAddressBookEntry:temp];
    [self setProfile:temp];
}

- (void)sessionProfileDidChange {
    if (!self.isDivorced) {
        return;
    }
    NSDictionary *updatedProfile =
    [[ProfileModel sessionsInstance] bookmarkWithGuid:_profile[KEY_GUID]];
    if (!updatedProfile) {
        // Can happen when replaying a recorded session.
        return;
    }

    NSMutableSet *keys = [NSMutableSet setWithArray:[updatedProfile allKeys]];
    [keys addObjectsFromArray:[_profile allKeys]];
    for (NSString *aKey in keys) {
        NSObject *sharedValue = _originalProfile[aKey];
        NSObject *newSessionValue = updatedProfile[aKey];
        BOOL isEqual = [newSessionValue isEqual:sharedValue];
        BOOL isOverridden = [_overriddenFields containsObject:aKey];
        if (!isEqual && !isOverridden) {
            DLog(@"%p: %@ is now overridden because %@ != %@", self, aKey, newSessionValue, sharedValue);
            [_overriddenFields addObject:aKey];
        } else if (isEqual && isOverridden) {
            DLog(@"%p: %@ is no longer overridden because %@ == %@", self, aKey, newSessionValue, sharedValue);
            [_overriddenFields removeObject:aKey];
        }
    }
    DLog(@"After session profile change overridden keys are: %@", _overriddenFields);
    [self setPreferencesFromAddressBookEntry:updatedProfile];
    [self setProfile:updatedProfile];
    [[NSNotificationCenter defaultCenter] postNotificationName:kSessionProfileDidChange
                                                        object:_profile[KEY_GUID]];
}

- (BOOL)reloadProfile {
    DLog(@"Reload profile for %@", self);
    BOOL didChange = NO;
    NSDictionary *sharedProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:_originalProfile[KEY_GUID]];
    if (sharedProfile && ![sharedProfile isEqual:_originalProfile]) {
        DLog(@"Shared profile changed");
        [self sharedProfileDidChange];
        didChange = YES;
        [_originalProfile autorelease];
        _originalProfile = [sharedProfile copy];
    }

    if (self.isDivorced) {
        NSDictionary *sessionProfile = [[ProfileModel sessionsInstance] bookmarkWithGuid:_profile[KEY_GUID]];
        if (![sessionProfile isEqual:_profile]) {
            DLog(@"Session profile changed");
            [self sessionProfileDidChange];
            didChange = YES;
        }
    }

    [self profileNameDidChangeTo:self.profile[KEY_NAME]];
    return didChange;
}

- (void)loadColorsFromProfile:(Profile *)aDict {
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;
    NSDictionary<NSNumber *, NSString *> *keyMap = [self colorTableForProfile:aDict darkMode:dark];

    NSMutableDictionary<NSNumber *, id> *colorTable =
    [[[keyMap mapValuesWithBlock:^id(NSNumber *colorKey, NSString *profileKey) {
        if ([profileKey isKindOfClass:[NSString class]]) {
            return [iTermProfilePreferences colorForKey:profileKey
                                                   dark:dark
                                                profile:aDict] ?: [NSNull null];
        } else {
            return [NSNull null];
        }
    }] mutableCopy] autorelease];
    [self load16ANSIColorsFromProfile:aDict darkMode:dark into:colorTable];
    const BOOL didUseSelectedTextColor = [iTermProfilePreferences boolForKey:iTermAmendedColorKey(KEY_USE_SELECTED_TEXT_COLOR, self.profile, dark) inProfile:self.profile];
    const BOOL willUseSelectedTextColor = [iTermProfilePreferences boolForKey:iTermAmendedColorKey(KEY_USE_SELECTED_TEXT_COLOR, aDict, dark) inProfile:aDict];

    [_screen setColorsFromDictionary:colorTable];

    if (didUseSelectedTextColor != willUseSelectedTextColor) {
        [_textview updatePortholeColorsWithUseSelectedTextColor:willUseSelectedTextColor];
    }
    self.cursorGuideColor = [[iTermProfilePreferences objectForKey:iTermAmendedColorKey(KEY_CURSOR_GUIDE_COLOR, aDict, dark)
                                                         inProfile:aDict] colorValueForKey:iTermAmendedColorKey(KEY_CURSOR_GUIDE_COLOR, aDict, dark)];
    if (!_cursorGuideSettingHasChanged) {
        _textview.highlightCursorLine = [iTermProfilePreferences boolForKey:iTermAmendedColorKey(KEY_USE_CURSOR_GUIDE, aDict, dark)
                                                                  inProfile:aDict];
    }

    [self setSmartCursorColor:[iTermProfilePreferences boolForKey:iTermAmendedColorKey(KEY_SMART_CURSOR_COLOR, aDict, dark)
                                                        inProfile:aDict]];

    DLog(@"set min contrast to %f using key %@", [iTermProfilePreferences floatForKey:iTermAmendedColorKey(KEY_MINIMUM_CONTRAST, aDict, dark)
                                                                            inProfile:aDict], iTermAmendedColorKey(KEY_MINIMUM_CONTRAST, aDict, dark));
    [self setMinimumContrast:[iTermProfilePreferences floatForKey:iTermAmendedColorKey(KEY_MINIMUM_CONTRAST, aDict, dark)
                                                        inProfile:aDict]];
}

- (NSDictionary<NSNumber *, NSString *> *)colorTableForProfile:(Profile *)profile darkMode:(BOOL)dark {
    NSString *(^k)(NSString *) = ^NSString *(NSString *baseKey) {
        return iTermAmendedColorKey(baseKey, profile, dark);
    };
    const BOOL useUnderline = [iTermProfilePreferences boolForKey:k(KEY_USE_UNDERLINE_COLOR) inProfile:profile];
    NSDictionary *keyMap = @{ @(kColorMapForeground): k(KEY_FOREGROUND_COLOR),
                              @(kColorMapBackground): k(KEY_BACKGROUND_COLOR),
                              @(kColorMapSelection): k(KEY_SELECTION_COLOR),
                              @(kColorMapSelectedText): k(KEY_SELECTED_TEXT_COLOR),
                              @(kColorMapBold): k(KEY_BOLD_COLOR),
                              @(kColorMapLink): k(KEY_LINK_COLOR),
                              @(kColorMapMatch): k(KEY_MATCH_COLOR),
                              @(kColorMapCursor): k(KEY_CURSOR_COLOR),
                              @(kColorMapCursorText): k(KEY_CURSOR_TEXT_COLOR),
                              @(kColorMapUnderline): (useUnderline ? k(KEY_UNDERLINE_COLOR) : [NSNull null])
    };
    return keyMap;
}

// Restore a color to the value in `profile`.
- (NSDictionary<NSNumber *, id> *)resetColorWithKey:(int)colorKey
                                        fromProfile:(Profile *)profile
                                         profileKey:(NSString *)profileKey
                                               dark:(BOOL)dark {
    DLog(@"resetColorWithKey:%d fromProfile:%@", colorKey, profile[KEY_GUID]);
    if (!profile) {
        DLog(@"No original profile");
        return @{};
    }

    NSColor *color = [iTermProfilePreferences colorForKey:profileKey
                                                     dark:dark
                                                  profile:profile];
    if (!color) {
        return @{};
    }
    if (profileKey) {
        [self setSessionSpecificProfileValues:@{ profileKey: [color dictionaryValue] }];
        return @{};
    }
    return @{ @(colorKey): color };
}

- (void)load16ANSIColorsFromProfile:(Profile *)aDict darkMode:(BOOL)dark into:(NSMutableDictionary<NSNumber *, id> *)dict {
    for (int i = 0; i < 16; i++) {
        [self loadANSIColor:i fromProfile:aDict darkMode:dark to:dict];
    }
}

- (void)loadANSIColor:(int)i fromProfile:(Profile *)aDict darkMode:(BOOL)dark to:(NSMutableDictionary<NSNumber *, id> *)dict {
    NSString *baseKey = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i];
    NSString *profileKey = iTermAmendedColorKey(baseKey, aDict, dark);
    NSColor *theColor = [ITAddressBookMgr decodeColor:aDict[profileKey]];
    dict[@(kColorMap8bitBase + i)] = theColor ?: [NSNull null];
}

- (void)setPreferencesFromAddressBookEntry:(NSDictionary *)aePrefs {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [self reallySetPreferencesFromAddressBookEntry:aePrefs terminal:terminal];
    }];
}

- (void)reallySetPreferencesFromAddressBookEntry:(NSDictionary *)aePrefs
                                        terminal:(VT100Terminal *)terminal {
    NSDictionary *aDict = aePrefs;

    if (aDict == nil) {
        DLog(@"nil dict, use default");
        aDict = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (aDict == nil) {
        DLog(@"uh oh! no default dict!");
        return;
    }
    DLog(@"%@: set prefs to address book entry:\n%@", self, aDict);

    if ([self isTmuxClient] && ![_profile[KEY_NAME] isEqualToString:aePrefs[KEY_NAME]]) {
        _tmuxTitleOutOfSync = YES;
    }

    [self loadColorsFromProfile:aDict];

    // background image
    [self setBackgroundImagePath:aDict[KEY_BACKGROUND_IMAGE_LOCATION]];
    [self setBackgroundImageMode:[iTermProfilePreferences unsignedIntegerForKey:KEY_BACKGROUND_IMAGE_MODE
                                                                      inProfile:aDict]];

    // Color scheme
    // ansiColorsMatchingForeground:andBackground:inBookmark does an equality comparison, so
    // iTermProfilePreferences is not used here.
    [self setColorFgBgVariable:[self ansiColorsMatchingForeground:aDict[[self amendedColorKey:KEY_FOREGROUND_COLOR]]
                                                    andBackground:aDict[[self amendedColorKey:KEY_BACKGROUND_COLOR]]
                                                       inBookmark:aDict]];

    // transparency
    [self setTransparency:[iTermProfilePreferences floatForKey:KEY_TRANSPARENCY inProfile:aDict]];
    [self setTransparencyAffectsOnlyDefaultBackgroundColor:[iTermProfilePreferences floatForKey:KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR inProfile:aDict]];

    // bold
    [self setUseBoldFont:[iTermProfilePreferences boolForKey:KEY_USE_BOLD_FONT
                                                   inProfile:aDict]];
    self.thinStrokes = [iTermProfilePreferences intForKey:KEY_THIN_STROKES inProfile:aDict];

    self.asciiLigatures = [iTermProfilePreferences boolForKey:KEY_ASCII_LIGATURES inProfile:aDict];
    self.nonAsciiLigatures = [iTermProfilePreferences boolForKey:KEY_NON_ASCII_LIGATURES inProfile:aDict];

    [_textview setUseBoldColor:[iTermProfilePreferences boolForColorKey:KEY_USE_BOLD_COLOR
                                                                   dark:_screen.colorMap.darkMode
                                                                profile:aDict]
                      brighten:[iTermProfilePreferences boolForColorKey:KEY_BRIGHTEN_BOLD_TEXT
                                                                   dark:_screen.colorMap.darkMode
                                                                profile:aDict]];

    // Italic - this default has changed from NO to YES as of 1/30/15
    [self setUseItalicFont:[iTermProfilePreferences boolForKey:KEY_USE_ITALIC_FONT inProfile:aDict]];

    // Set up the rest of the preferences
    [_screen setAudibleBell:![iTermProfilePreferences boolForKey:KEY_SILENCE_BELL inProfile:aDict]];
    [_screen setShowBellIndicator:[iTermProfilePreferences boolForKey:KEY_VISUAL_BELL inProfile:aDict]];
    [_screen setFlashBell:[iTermProfilePreferences boolForKey:KEY_FLASHING_BELL inProfile:aDict]];
    [_screen setPostUserNotifications:[iTermProfilePreferences boolForKey:KEY_BOOKMARK_USER_NOTIFICATIONS inProfile:aDict]];
    [_textview setBlinkAllowed:[iTermProfilePreferences boolForKey:KEY_BLINK_ALLOWED inProfile:aDict]];
    [_screen setCursorBlinks:[iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:aDict]];
    [_textview setCursorShadow:[iTermProfilePreferences boolForKey:KEY_CURSOR_SHADOW inProfile:aDict]];
    [_textview setBlinkingCursor:[iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:aDict]];
    [_textview setCursorType:_cursorTypeOverride ? _cursorTypeOverride.integerValue : [iTermProfilePreferences intForKey:KEY_CURSOR_TYPE inProfile:aDict]];

    PTYTab* currentTab = [[_delegate parentWindow] currentTab];
    if (currentTab == nil || [_delegate sessionBelongsToVisibleTab]) {
        [_delegate recheckBlur];
    }

    [_textview setSmartSelectionRules:aDict[KEY_SMART_SELECTION_RULES]];
    [_textview setSemanticHistoryPrefs:aDict[KEY_SEMANTIC_HISTORY]];
    [_textview setUseNonAsciiFont:[iTermProfilePreferences boolForKey:KEY_USE_NONASCII_FONT
                                                            inProfile:aDict]];
    [_textview setAntiAlias:[iTermProfilePreferences boolForKey:KEY_ASCII_ANTI_ALIASED
                                                      inProfile:aDict]
                   nonAscii:[iTermProfilePreferences boolForKey:KEY_NONASCII_ANTI_ALIASED
                                                      inProfile:aDict]];
    [_textview setUseNativePowerlineGlyphs:[iTermProfilePreferences boolForKey:KEY_POWERLINE inProfile:aDict]];
    [self setEncoding:[iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:aDict]
             terminal:terminal];
    [self setTermVariable:[iTermProfilePreferences stringForKey:KEY_TERMINAL_TYPE inProfile:aDict]
                 terminal:terminal];
    [terminal setAnswerBackString:[iTermProfilePreferences stringForKey:KEY_ANSWERBACK_STRING inProfile:aDict]];
    [self setAntiIdleCode:[iTermProfilePreferences intForKey:KEY_IDLE_CODE inProfile:aDict]];
    [self setAntiIdlePeriod:[iTermProfilePreferences doubleForKey:KEY_IDLE_PERIOD inProfile:aDict]];
    [self setAntiIdle:[iTermProfilePreferences boolForKey:KEY_SEND_CODE_WHEN_IDLE inProfile:aDict]];
    self.endAction = [iTermProfilePreferences unsignedIntegerForKey:KEY_SESSION_END_ACTION inProfile:aDict];
    [self setTreatAmbiguousWidthAsDoubleWidth:[iTermProfilePreferences boolForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH
                                                                        inProfile:aDict]];
    [self setXtermMouseReporting:[iTermProfilePreferences boolForKey:KEY_XTERM_MOUSE_REPORTING
                                                           inProfile:aDict]];
    [self setXtermMouseReportingAllowMouseWheel:[iTermProfilePreferences boolForKey:KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL
                                                                          inProfile:aDict]];
    [self setXtermMouseReportingAllowClicksAndDrags:[iTermProfilePreferences boolForKey:KEY_XTERM_MOUSE_REPORTING_ALLOW_CLICKS_AND_DRAGS
                                                                              inProfile:aDict]];
    [self setUnicodeVersion:[iTermProfilePreferences integerForKey:KEY_UNICODE_VERSION
                                                         inProfile:aDict]];
    [terminal setDisableSmcupRmcup:[iTermProfilePreferences boolForKey:KEY_DISABLE_SMCUP_RMCUP
                                                             inProfile:aDict]];
    [_screen setAllowTitleReporting:[iTermProfilePreferences boolForKey:KEY_ALLOW_TITLE_REPORTING
                                                              inProfile:aDict]];
    const BOOL didAllowPasteBracketing = _screen.terminalAllowPasteBracketing;
    [terminal setAllowPasteBracketing:[iTermProfilePreferences boolForKey:KEY_ALLOW_PASTE_BRACKETING
                                                                inProfile:aDict]];
    if (didAllowPasteBracketing && !_screen.terminalAllowPasteBracketing) {
        // If the user flips the setting off, disable bracketed paste.
        terminal.bracketedPasteMode = NO;
    }
    [terminal setAllowKeypadMode:[iTermProfilePreferences boolForKey:KEY_APPLICATION_KEYPAD_ALLOWED
                                                           inProfile:aDict]];
    if ([iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:aDict]) {
        NSDictionary *layout = [iTermProfilePreferences objectForKey:KEY_STATUS_BAR_LAYOUT inProfile:aDict];
        NSDictionary *existing = _statusBarViewController.layout.dictionaryValue;
        if (![NSObject object:existing isEqualToObject:layout]) {
            iTermStatusBarLayout *newLayout = [[[iTermStatusBarLayout alloc] initWithDictionary:layout
                                                                                          scope:self.variablesScope] autorelease];
            if (![NSObject object:existing isEqualToObject:newLayout.dictionaryValue]) {
                [_statusBarViewController release];
                if (newLayout) {
                    _statusBarViewController =
                    [[iTermStatusBarViewController alloc] initWithLayout:newLayout
                                                                   scope:self.variablesScope];
                    _statusBarViewController.delegate = self;
                } else {
                    _statusBarViewController.delegate = nil;
                    _statusBarViewController = nil;
                }
                [self invalidateStatusBar];
            }
        }
    } else {
        if (_statusBarViewController && _asyncFilter) {
            [self stopFiltering];
        }
        [_statusBarViewController release];
        _statusBarViewController = nil;
        [self invalidateStatusBar];
    }
    _tmuxStatusBarMonitor.active = [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:aDict];
    [_badgeFontName release];
    _badgeFontName = [[iTermProfilePreferences stringForKey:KEY_BADGE_FONT inProfile:aDict] copy];

    self.badgeFormat = [iTermProfilePreferences stringForKey:KEY_BADGE_FORMAT inProfile:aDict];
    _badgeLabelSizeFraction = NSMakeSize([iTermProfilePreferences floatForKey:KEY_BADGE_MAX_WIDTH inProfile:aDict],
                                         [iTermProfilePreferences floatForKey:KEY_BADGE_MAX_HEIGHT inProfile:aDict]);

    self.subtitleFormat = [iTermProfilePreferences stringForKey:KEY_SUBTITLE inProfile:aDict];

    // forces the badge to update
    _textview.badgeLabel = @"";
    [self updateBadgeLabel];
    [self setFontTable:[iTermFontTable fontTableForProfile:aDict]
     horizontalSpacing:[iTermProfilePreferences floatForKey:KEY_HORIZONTAL_SPACING inProfile:aDict]
       verticalSpacing:[iTermProfilePreferences floatForKey:KEY_VERTICAL_SPACING inProfile:aDict]];

    NSDictionary *shortcutDictionary = [iTermProfilePreferences objectForKey:KEY_SESSION_HOTKEY inProfile:aDict];
    iTermShortcut *shortcut = [iTermShortcut shortcutWithDictionary:shortcutDictionary];
    [[iTermSessionHotkeyController sharedInstance] setShortcut:shortcut
                                                    forSession:self];
    [[_delegate realParentWindow] invalidateRestorableState];

    const int modifyOtherKeysTerminalSetting = _screen.terminalSendModifiers[4].intValue;
    if (modifyOtherKeysTerminalSetting == -1) {
        const BOOL profileWantsTickit = [iTermProfilePreferences boolForKey:KEY_USE_LIBTICKIT_PROTOCOL
                                                                  inProfile:aDict];
        if (profileWantsTickit) {
            [self setKeyMappingMode:iTermKeyMappingModeCSIu];
        }
    }

    if (self.isTmuxClient) {
        NSDictionary *tabColorDict = [iTermProfilePreferences objectForColorKey:KEY_TAB_COLOR dark:_screen.colorMap.darkMode profile:aDict];
        if (![iTermProfilePreferences boolForColorKey:KEY_USE_TAB_COLOR dark:_screen.colorMap.darkMode profile:aDict]) {
            tabColorDict = nil;
        }
        NSColor *tabColor = [ITAddressBookMgr decodeColor:tabColorDict];
        [self.tmuxController setTabColorString:tabColor ? [tabColor hexString] : iTermTmuxTabColorNone
                                 forWindowPane:self.tmuxPane];
    }
    [self.delegate sessionDidChangeGraphic:self
                                shouldShow:[self shouldShowTabGraphicForProfile:aDict]
                                     image:[self tabGraphicForProfile:aDict]];
    [self.delegate sessionUpdateMetalAllowed];
    [self profileNameDidChangeTo:self.profile[KEY_NAME]];
}

- (void)setCursorTypeOverride:(NSNumber *)cursorTypeOverride {
    [_cursorTypeOverride autorelease];
    _cursorTypeOverride = [cursorTypeOverride retain];
    _cursorTypeOverrideChanged = YES;
    [self.textview setCursorType:self.cursorType];
}

- (ITermCursorType)cursorType {
    if (_cursorTypeOverride) {
        return _cursorTypeOverride.integerValue;
    }
    return [iTermProfilePreferences intForKey:KEY_CURSOR_TYPE inProfile:_profile];
}

- (void)invalidateStatusBar {
    [_view invalidateStatusBar];
    [_delegate sessionDidInvalidateStatusBar:self];
}

- (void)setSubtitleFormat:(NSString *)subtitleFormat {
    if ([subtitleFormat isEqualToString:_subtitleSwiftyString.swiftyString]) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    if (!_subtitleSwiftyString) {
        // Create it with an initially empty string because the delegate will
        // ask for our subtitle value and it won't be right before
        // _subtitleSwiftyString is assigned to.
        _subtitleSwiftyString = [[iTermSwiftyString alloc] initWithString:@""
                                                                    scope:self.variablesScope
                                                                 observer:^NSString *(NSString * _Nonnull newValue,
                                                                                      NSError *error) {
            if (error) {
                return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
            }
            __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf.delegate sessionSubtitleDidChange:strongSelf];
            }
            return newValue;
        }];
    }
    _subtitleSwiftyString.swiftyString = subtitleFormat;
}

- (void)setBadgeFormat:(NSString *)badgeFormat {
    if ([badgeFormat isEqualToString:_badgeSwiftyString.swiftyString]) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [_badgeSwiftyString invalidate];
    [_badgeSwiftyString autorelease];
    _badgeSwiftyString = [[iTermSwiftyString alloc] initWithString:badgeFormat
                                                             scope:self.variablesScope
                                                          observer:^NSString *(NSString * _Nonnull newValue, NSError *error) {
        if (error) {
            return [NSString stringWithFormat:@"🐞 %@", error.localizedDescription];
        }
        [weakSelf updateBadgeLabel:newValue];
        return newValue;
    }];
}

- (void)setKeyMappingMode:(iTermKeyMappingMode)mode {
    DLog(@"setKeyMappingMode:%@", @(mode));
    _keyMappingMode = mode;
    [self updateKeyMapper];
}

- (void)updateKeyMapper {
    Class mapperClass = [iTermStandardKeyMapper class];

    switch (_keyMappingMode) {
        case iTermKeyMappingModeStandard:
            mapperClass = [iTermStandardKeyMapper class];
            break;
        case iTermKeyMappingModeCSIu:
            mapperClass = [iTermTermkeyKeyMapper class];
            break;
        case iTermKeyMappingModeRaw:
            mapperClass = [iTermRawKeyMapper class];
            break;
        case iTermKeyMappingModeModifyOtherKeys1:
            mapperClass = [iTermModifyOtherKeysMapper1 class];
            break;
        case iTermKeyMappingModeModifyOtherKeys2:
            mapperClass = [iTermModifyOtherKeysMapper2 class];
            break;
    }

    if (![_keyMapper isKindOfClass:mapperClass]) {
        [_keyMapper release];
        _keyMapper = nil;

        id<iTermKeyMapper> keyMapper = [[mapperClass alloc] init];
        if ([keyMapper respondsToSelector:@selector(setDelegate:)]) {
            [keyMapper setDelegate:self];
        }
        _keyMapper = keyMapper;
        _textview.keyboardHandler.keyMapper = _keyMapper;
    }
    iTermTermkeyKeyMapper *termkey = [iTermTermkeyKeyMapper castFrom:_keyMapper];
    termkey.flags = _screen.terminalKeyReportingFlags;
}

- (NSString *)badgeFormat {
    return _badgeSwiftyString.swiftyString;
}

- (NSString *)subtitle {
    return [_subtitleSwiftyString.evaluatedString stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

- (BOOL)doesSwiftyString:(iTermSwiftyString *)swiftyString
          referencePaths:(NSArray<NSString *> *)paths {
    for (iTermVariableReference *ref in swiftyString.refs) {
        for (NSString *path in paths) {
            if ([self.variablesScope variableNamed:path isReferencedBy:ref]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)checkForCyclesInSwiftyStrings {
    iTermSwiftyStringGraph *graph = [[[iTermSwiftyStringGraph alloc] init] autorelease];
    [graph addSwiftyString:_autoNameSwiftyString
            withFormatPath:iTermVariableKeySessionAutoNameFormat
            evaluationPath:iTermVariableKeySessionAutoName
                     scope:self.variablesScope];
    if (_badgeSwiftyString) {
        [graph addSwiftyString:_badgeSwiftyString
                withFormatPath:nil
                evaluationPath:iTermVariableKeySessionBadge
                         scope:self.variablesScope];
    }
    [self.delegate sessionAddSwiftyStringsToGraph:graph];
    [graph addEdgeFromPath:iTermVariableKeySessionAutoNameFormat
                    toPath:iTermVariableKeySessionName
                     scope:self.variablesScope];
    return graph.containsCycle;
}

- (void)updateBadgeLabel {
    if ([self checkForCyclesInSwiftyStrings]) {
        [self setBadgeFormat:@"[Cycle detected]"];
        return;
    }
    [self updateBadgeLabel:[self badgeLabel]];
}

- (void)updateBadgeLabel:(NSString *)newValue {
    _textview.badgeLabel = newValue;
    [self.variablesScope setValue:newValue forVariableNamed:iTermVariableKeySessionBadge];
}

- (NSString *)badgeLabel {
    return _badgeSwiftyString.evaluatedString;
}

- (BOOL)isAtShellPrompt {
    return _screen.commandRange.start.x >= 0;
}

// You're processing if data was read off the socket in the last "idleTimeSeconds".
- (BOOL)isProcessing {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return (now - _lastOutputIgnoringOutputAfterResizing) < _idleTime;
}

// You're idle if it's been one second since isProcessing was true.
- (BOOL)isIdle {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return (now - _lastOutputIgnoringOutputAfterResizing) > (_idleTime + 1);
}

- (void)setDelegate:(id<PTYSessionDelegate>)delegate {
    if ([self isTmuxClient]) {
        [_tmuxController deregisterWindow:[_delegate tmuxWindow]
                               windowPane:self.tmuxPane
                                  session:self];
    }
    BOOL needsTermID = (_delegate == nil);
    _delegate = delegate;
    if ([self isTmuxClient]) {
        [_tmuxController registerSession:self
                                withPane:self.tmuxPane
                                inWindow:[_delegate tmuxWindow]];
    }
    DLog(@"Fit layout to window on session delegate change");
    [_tmuxController fitLayoutToWindows];
    [self useTransparencyDidChange];
    [self.variablesScope setValue:[delegate sessionTabVariables]
                 forVariableNamed:iTermVariableKeySessionTab
                             weak:YES];
    if (needsTermID) {
        [self setTermIDIfPossible];
    }
    // useTransparency may have just changed.
    [self invalidateBlend];
}

- (NSString *)name {
    return [self.variablesScope valueForVariableName:iTermVariableKeySessionName] ?: [self.variablesScope valueForVariableName:iTermVariableKeySessionProfileName] ?: @"Untitled";
}

- (void)setIconName:(NSString *)theName {
    DLog(@"Assign to autoNameFormat <- %@", theName);
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionAutoNameFormat: theName ?: [NSNull null],
                                                    iTermVariableKeySessionIconName: theName ?: [NSNull null] }];
    [_tmuxTitleMonitor updateOnce];
    [self.tmuxForegroundJobMonitor updateOnce];
    _titleDirty = YES;
}

- (void)resetIconName {
    DLog(@"Reset icon name");
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionIconName];
    [self profileNameDidChangeTo:self.profile[KEY_NAME]];
    [self resetSessionNameTitleComponents];
}

- (void)setWindowTitle:(NSString *)title {
    [self.variablesScope setValue:title forVariableNamed:iTermVariableKeySessionWindowName];
    _titleDirty = YES;
    [_tmuxTitleMonitor updateOnce];
    [self.tmuxForegroundJobMonitor updateOnce];
}

- (BOOL)shouldShowTabGraphic {
    return [self shouldShowTabGraphicForProfile:self.profile];
}

- (BOOL)shouldShowTabGraphicForProfile:(Profile *)profile {
    const iTermProfileIcon icon = [iTermProfilePreferences unsignedIntegerForKey:KEY_ICON inProfile:profile];
    return icon != iTermProfileIconNone;
}

- (NSImage *)tabGraphic {
    return [self tabGraphicForProfile:self.profile];
}

- (NSImage *)tabGraphicForProfile:(Profile *)profile {
    const iTermProfileIcon icon = [iTermProfilePreferences unsignedIntegerForKey:KEY_ICON inProfile:profile];
    switch (icon) {
        case iTermProfileIconNone:
            return nil;

        case iTermProfileIconAutomatic:
            if (self.isTmuxClient) {
                [_graphicSource updateImageForJobName:self.tmuxForegroundJobMonitor.lastValue
                                              enabled:[self shouldShowTabGraphicForProfile:profile]];
            } else {
                [_graphicSource updateImageForProcessID:[self.variablesScope.effectiveRootPid intValue]
                                                enabled:[self shouldShowTabGraphicForProfile:profile]
                                    processInfoProvider:self.processInfoProvider];
            }
            return _graphicSource.image;

        case iTermProfileIconCustom:
            return [self customIconImageForProfile:profile];
    }

    DLog(@"Unexpected icon setting %@", @(icon));
    return nil;
}

- (NSImage *)customIconImage {
    return [self customIconImageForProfile:self.profile];
}

- (NSImage *)customIconImageForProfile:(Profile *)profile {
    if (!_customIcon) {
        _customIcon = [[iTermCacheableImage alloc] init];
    }
    NSString *path = [iTermProfilePreferences stringForKey:KEY_ICON_PATH inProfile:profile];
    BOOL flipped = YES;
    if (@available(macOS 10.15, *)) {
        flipped = NO;
    }
    return [_customIcon imageAtPath:path ofSize:NSMakeSize(16, 16) flipped:flipped];
}

- (NSString *)windowTitle {
    return _nameController.presentationWindowTitle;
}

- (void)pushWindowTitle {
    [_nameController pushWindowTitle];
}

- (void)popWindowTitle {
    NSString *title = [_nameController popWindowTitle];
    [self setWindowTitle:title];
}

- (void)pushIconTitle {
    [_nameController pushIconTitle];
}

- (void)popIconTitle {
    NSString *theName = [_nameController popIconTitle];
    if (!theName) {
        [self resetIconName];
    } else {
        [self setIconName:theName];
    }
}

- (void)userInitiatedReset {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [terminal resetForReason:VT100TerminalResetReasonUserRequest];
    }];
    [self updateDisplayBecause:@"reset terminal"];
}

- (void)resetForRelaunch {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        [terminal resetForRelaunch];
    }];
}

- (void)setTermVariable:(NSString *)termVariable terminal:(VT100Terminal *)terminal {
    if (self.isTmuxClient) {
        return;
    }
    [_termVariable autorelease];
    _termVariable = [termVariable copy];
    [terminal setTermType:_termVariable];
}

- (void)setView:(SessionView *)newView {
    if (_view.searchResultsMinimapViewDelegate == _textview.findOnPageHelper) {
        _view.searchResultsMinimapViewDelegate = nil;
    }
    [_view autorelease];
    _view = [newView retain];
    newView.delegate = self;
    newView.searchResultsMinimapViewDelegate = _textview.findOnPageHelper;
    newView.driver.dataSource = _metalGlue;
    [newView updateTitleFrame];
    [_view setFindDriverDelegate:self];
    [self updateViewBackgroundImage];
}

- (NSStringEncoding)encoding {
    return _screen.terminalEncoding;
}

- (void)setEncoding:(NSStringEncoding)encoding terminal:(VT100Terminal *)terminal {
    [terminal setEncoding:encoding];
}

- (NSString *)tty {
    return [_shell tty];
}

- (void)setBackgroundImageMode:(iTermBackgroundImageMode)mode {
    _backgroundImageMode = mode;
    [_backgroundDrawingHelper invalidate];
    [self setBackgroundImagePath:_backgroundImagePath];
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        self.view.imageMode = mode;
    }
}

- (void)setBackgroundImagePath:(NSString *)imageFilePath {
    DLog(@"setBackgroundImagePath:%@", imageFilePath);
    if ([imageFilePath length]) {
        if ([imageFilePath isAbsolutePath] == NO) {
            NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
            imageFilePath = [myBundle pathForResource:imageFilePath ofType:@""];
            DLog(@"Not an absolute path. Use bundle-relative path of %@", imageFilePath);
        }
        if ([imageFilePath isEqualToString:_backgroundImagePath]) {
            DLog(@"New image path equals existing path, so do nothing.");
            return;
        }
        [_backgroundImagePath autorelease];
        _backgroundImagePath = [imageFilePath copy];
        self.backgroundImage = [[iTermSharedImageStore sharedInstance] imageWithContentsOfFile:_backgroundImagePath];
    } else {
        DLog(@"Clearing abackground image");
        self.backgroundImage = nil;
        [_backgroundImagePath release];
        _backgroundImagePath = nil;
    }

    [_patternedImage release];
    _patternedImage = nil;

    [_textview requestDelegateRedraw];
}

- (CGFloat)effectiveBlend {
    if (!self.effectiveBackgroundImage) {
        return 0;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return self.desiredBlend;
    } else {
        if (self.backgroundImage) {
            return self.desiredBlend;
        }
        // I don't have a background image so inherit the blend setting of the active session.
        return [self.delegate sessionBlend];
    }
}

- (CGFloat)desiredBlend {
    return [iTermProfilePreferences floatForKey:KEY_BLEND inProfile:self.profile];
}

- (iTermImageWrapper *)effectiveBackgroundImage {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return _backgroundImage;
    } else {
        return [self.delegate sessionBackgroundImage];
    }
}

- (iTermBackgroundImageMode)effectiveBackgroundImageMode {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return _backgroundImageMode;
    } else {
        return [self.delegate sessionBackgroundImageMode];
    }
}

- (BOOL)shouldDrawBackgroundImageManually {
    return !iTermTextIsMonochrome() || [NSView iterm_takingSnapshot];
}

- (void)updateViewBackgroundImage {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        DLog(@"Update per-pane background image");
        self.view.image = _backgroundImage;
        [self.view setImageMode:_backgroundImageMode];
        [self.view setTerminalBackgroundColor:[self processedBackgroundColor]];
        return;
    }
    self.view.image = nil;
    [self.view setTerminalBackgroundColor:[self processedBackgroundColor]];
    [self invalidateBlend];
    [self.delegate session:self
        setBackgroundImage:_backgroundImage
                      mode:_backgroundImageMode
           backgroundColor:[self processedBackgroundColor]];
}

- (void)setBackgroundImage:(iTermImageWrapper *)backgroundImage {
    DLog(@"setBackgroundImage:%@", backgroundImage);
    [_backgroundImage autorelease];
    _backgroundImage = [backgroundImage retain];
    [self updateViewBackgroundImage];
}

- (void)setSmartCursorColor:(BOOL)value {
    [[self textview] setUseSmartCursorColor:value];
}

- (void)setMinimumContrast:(float)value {
    [[self textview] setMinimumContrast:value];
}

- (BOOL)viewShouldWantLayer {
    return NO;
}

- (void)useTransparencyDidChange {
    if (_view.window && _delegate.realParentWindow && _textview) {
        if (_view.window && _delegate.realParentWindow && _textview) {
            [_delegate sessionTransparencyDidChange];
            [self invalidateBlend];
        }
    }
}

- (float)transparency
{
    return [_textview transparency];
}

- (void)setTransparency:(float)transparency {
    // Limit transparency because fully transparent windows can't be clicked on.
    if (transparency > 0.9) {
        transparency = 0.9;
    }
    [_textview setTransparency:transparency];
    [self useTransparencyDidChange];
    [self invalidateBlend];
}

- (void)invalidateBlend {
    [_textview requestDelegateRedraw];
    [self.view setNeedsDisplay:YES];
    [self.view setTransparencyAlpha:_textview.transparencyAlpha
                              blend:self.effectiveBlend];
}

- (void)setTransparencyAffectsOnlyDefaultBackgroundColor:(BOOL)value {
    [_textview setTransparencyAffectsOnlyDefaultBackgroundColor:value];
}

- (BOOL)antiIdle {
    return _antiIdleTimer ? YES : NO;
}

- (void)setAntiIdle:(BOOL)set {
    [_antiIdleTimer invalidate];
    _antiIdleTimer = nil;

    _antiIdlePeriod = MAX(_antiIdlePeriod, kMinimumAntiIdlePeriod);

    if (set) {
        _antiIdleTimer = [NSTimer scheduledTimerWithTimeInterval:_antiIdlePeriod
                                                          target:self.weakSelf
                                                        selector:@selector(doAntiIdle)
                                                        userInfo:nil
                                                         repeats:YES];
    }
}

- (BOOL)useBoldFont {
    return [_textview useBoldFont];
}

- (void)setUseBoldFont:(BOOL)boldFlag
{
    [_textview setUseBoldFont:boldFlag];
}

- (iTermThinStrokesSetting)thinStrokes {
    return _textview.thinStrokes;
}

- (void)setThinStrokes:(iTermThinStrokesSetting)thinStrokes {
    _textview.thinStrokes = thinStrokes;
}

- (void)setAsciiLigatures:(BOOL)asciiLigatures {
    _textview.asciiLigatures = asciiLigatures;
}

- (BOOL)asciiLigatures {
    return _textview.asciiLigatures;
}

- (void)setNonAsciiLigatures:(BOOL)nonAsciiLigatures {
    _textview.nonAsciiLigatures = nonAsciiLigatures;
}

- (BOOL)nonAsciiLigatures {
    return _textview.nonAsciiLigatures;
}

- (BOOL)useItalicFont
{
    return [_textview useItalicFont];
}

- (void)setUseItalicFont:(BOOL)italicFlag
{
    [_textview setUseItalicFont:italicFlag];
}

- (void)setTreatAmbiguousWidthAsDoubleWidth:(BOOL)set {
    _treatAmbiguousWidthAsDoubleWidth = set;
    _tmuxController.ambiguousIsDoubleWidth = set;
}

- (void)setUnicodeVersion:(NSInteger)version {
    _unicodeVersion = version;
    _tmuxController.unicodeVersion = version;
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermUnicodeVersionDidChangeNotification
                                                        object:nil];
}

- (void)setXtermMouseReporting:(BOOL)set
{
    _xtermMouseReporting = set;
    [_textview updateCursor:[NSApp currentEvent]];
}

- (BOOL)logging {
    return _logging.enabled;
}

- (void)logStart {
    __weak __typeof(self) weakSelf = self;
    [iTermSavePanel asyncShowWithOptions:kSavePanelOptionAppendOrReplace | kSavePanelOptionLogPlainTextAccessory
                              identifier:@"StartSessionLog"
                        initialDirectory:NSHomeDirectory()
                         defaultFilename:@""
                        allowedFileTypes:nil
                                  window:self.delegate.realParentWindow.window
                              completion:^(iTermSavePanel *panel) {
        NSString *path = panel.path;
        if (path) {
            BOOL shouldAppend = (panel.replaceOrAppend == kSavePanelReplaceOrAppendSelectionAppend);
            [weakSelf startLoggingAt:path append:shouldAppend style:panel.loggingStyle];
        }
    }];
}

- (void)startLoggingAt:(NSString *)path append:(BOOL)shouldAppend style:(iTermLoggingStyle)style {
    [[self loggingHelper] setPath:path
                          enabled:YES
                            style:style
                asciicastMetadata:[self asciicastMetadata]
                           append:@(shouldAppend)];
}

- (void)logStop {
    [_logging stop];
}

- (void)clearBuffer {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState clearBufferWithoutTriggersSavingPrompt:YES];
        if (self.isTmuxClient) {
            [_tmuxController clearHistoryForWindowPane:self.tmuxPane];
        }
        if ([iTermAdvancedSettingsModel jiggleTTYSizeOnClearBuffer]) {
            [self jiggle];
        }
        _view.scrollview.ptyVerticalScroller.userScroll = NO;
    }];
}

- (void)jiggle {
    DLog(@"%@", [NSThread callStackSymbols]);
    [self.shell.winSizeController jiggle];
}

- (void)clearScrollbackBuffer {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState clearScrollbackBuffer];
    }];
    if (self.isTmuxClient) {
        [_tmuxController clearHistoryForWindowPane:self.tmuxPane];
    }
}

- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask {
    if ([self optionKey] == OPT_ESC) {
        if ((modmask == NSEventModifierFlagOption) ||
            (modmask & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask) {
            return YES;
        }
    }
    if ([self rightOptionKey] == OPT_ESC) {
        if ((modmask & NSRightAlternateKeyMask) == NSRightAlternateKeyMask) {
            return YES;
        }
    }
    return NO;
}

- (void)setScrollViewDocumentView {
    const BOOL shouldUpdateLayout = (_view.scrollview.documentView == nil && _wrapper != nil);
    [_view.scrollview setDocumentView:_wrapper];
    NSRect rect = {
        .origin = NSZeroPoint,
        .size = _view.scrollview.contentSize
    };
    _wrapper.frame = rect;
    [_textview refresh];
    if (shouldUpdateLayout) {
        DLog(@"Document view went from nil to %@ so update layout", _wrapper);
        [_view updateLayout];
    }
}

- (void)setProfile:(Profile *)newProfile {
    assert(newProfile);
    DLog(@"Set profile to one with guid %@\n%@", newProfile[KEY_GUID], [NSThread callStackSymbols]);

    NSMutableDictionary *mutableProfile = [[newProfile mutableCopy] autorelease];
    // This is the most practical way to migrate the bopy of a
    // profile that's stored in a saved window arrangement. It doesn't get
    // saved back into the arrangement, unfortunately.
    [ProfileModel migratePromptOnCloseInMutableBookmark:mutableProfile];

    NSString *originalGuid = newProfile[KEY_ORIGINAL_GUID];
    if (originalGuid) {
        // This code path is taken when changing an existing session's profile.
        // See bug 2632.
        // It is also taken when you "new tab with same profile" and that profile is divorced.
        Profile *possibleOriginalProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:originalGuid];
        if (possibleOriginalProfile) {
            [_originalProfile autorelease];
            _originalProfile = [possibleOriginalProfile copy];
        }
    }
    if (!_originalProfile) {
        // This is normally taken when a new session is being created.
        _originalProfile = [NSDictionary dictionaryWithDictionary:mutableProfile];
        [_originalProfile retain];
    }

    [_profile release];
    _profile = [mutableProfile retain];
    [self profileNameDidChangeTo:self.profile[KEY_NAME]];
    [self invalidateBlend];
    [[_delegate realParentWindow] invalidateRestorableState];
    [[_delegate realParentWindow] updateTabColors];
    [_delegate sessionDidUpdatePreferencesFromProfile:self];
    [_nameController setNeedsUpdate];
    _profileDidChange = YES;
    [self sync];
}

- (NSString *)programType {
    if ([self.program isEqualToString:[ITAddressBookMgr shellLauncherCommandWithCustomShell:self.customShell]]) {
        if (self.customShell.length) {
            return kProgramTypeCustomShell;
        }
        return kProgramTypeShellLauncher;
    }
    return kProgramTypeCommand;
}

- (BOOL)encodeArrangementWithContents:(BOOL)includeContents
                              encoder:(id<iTermEncoderAdapter>)result {
    return [self encodeArrangementWithContents:includeContents
                                       encoder:result
                            replacementProfile:nil
                                   saveProgram:YES
                                  pendingJumps:nil];
}

- (BOOL)encodeArrangementWithContents:(BOOL)includeContents
                              encoder:(id<iTermEncoderAdapter>)result
                   replacementProfile:(Profile *)replacementProfile
                          saveProgram:(BOOL)saveProgram
                         pendingJumps:(NSArray<iTermSSHReconnectionInfo *> *)pendingJumps {
    DLog(@"Construct arrangement for session %@ with includeContents=%@", self, @(includeContents));
    if (_filter.length && _liveSession != nil) {
        DLog(@"Encode live session because this one is filtered.");
        const BOOL ok = [_liveSession encodeArrangementWithContents:includeContents encoder:result];
        if (ok) {
            result[SESSION_ARRANGEMENT_FILTER] = _filter;
        }
        return ok;
    }
    result[SESSION_ARRANGEMENT_COLUMNS] = @(_screen.width);
    result[SESSION_ARRANGEMENT_ROWS] = @(_screen.height);
    result[SESSION_ARRANGEMENT_BOOKMARK] = replacementProfile ?: _profile;

    if (_substitutions) {
        result[SESSION_ARRANGEMENT_SUBSTITUTIONS] = _substitutions;
    }

    if (saveProgram) {
        NSString *const programType = [self programType];
        if ([programType isEqualToString:kProgramTypeCustomShell]) {
            // The shell launcher command could change from run to run (e.g., if you move iTerm2).
            // I don't want to use a magic string, so setting program to an empty dict.
            assert(self.customShell.length);
            NSDictionary *dict = @{ kProgramType: kProgramTypeCustomShell };
            dict = [dict dictionaryBySettingObject:self.customShell forKey:kCustomShell];
            result[SESSION_ARRANGEMENT_PROGRAM] = dict;
        } else if ([programType isEqualToString:kProgramTypeShellLauncher]) {
            NSDictionary *dict = @{ kProgramType: kProgramTypeShellLauncher };
            result[SESSION_ARRANGEMENT_PROGRAM] = dict;
        } else if ([programType isEqualToString:kProgramTypeCommand] &&
                   self.program) {
            result[SESSION_ARRANGEMENT_PROGRAM] = @{ kProgramType: kProgramTypeCommand,
                                                     kProgramCommand: self.program };
        }
    }
    if (pendingJumps) {
        result[SESSION_ARRANGEMENT_PENDING_JUMPS] = [pendingJumps mapWithBlock:^id _Nullable(iTermSSHReconnectionInfo * _Nonnull info) {
            return [info serialized];
        }];
    }
    result[SESSION_ARRANGEMENT_KEYLABELS] = _keyLabels ?: @{};
    result[SESSION_ARRANGEMENT_KEYLABELS_STACK] = [_keyLabelsStack mapWithBlock:^id(iTermKeyLabels *anObject) {
        return anObject.dictionaryValue;
    }];
    result[SESSION_ARRANGEMENT_ENVIRONMENT] = self.environment ?: @{};
    result[SESSION_ARRANGEMENT_IS_UTF_8] = @(self.isUTF8);
    result[SESSION_ARRANGEMENT_SHORT_LIVED_SINGLE_USE] = @(self.shortLivedSingleUse);
    if (self.hostnameToShell) {
        result[SESSION_ARRANGEMENT_HOSTNAME_TO_SHELL] = [[self.hostnameToShell copy] autorelease];
    }

    NSDictionary *shortcutDictionary = [[[iTermSessionHotkeyController sharedInstance] shortcutForSession:self] dictionaryValue];
    if (shortcutDictionary) {
        result[SESSION_ARRANGEMENT_HOTKEY] = shortcutDictionary;
    }

    result[SESSION_ARRANGEMENT_NAME_CONTROLLER_STATE] = [_nameController stateDictionary];
    if (includeContents) {
        __block int numberOfLinesDropped = 0;
        [result encodeDictionaryWithKey:SESSION_ARRANGEMENT_CONTENTS
                             generation:iTermGenerationAlwaysEncode
                                  block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
            return [_screen encodeContents:encoder linesDropped:&numberOfLinesDropped];
        }];
        result[SESSION_ARRANGEMENT_VARIABLES] = _variables.encodableDictionaryValue;
        result[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK] = @(_alertOnNextMark);
        result[SESSION_ARRANGEMENT_CURSOR_GUIDE] = @(_textview.highlightCursorLine);
        result[SESSION_ARRANGEMENT_CURSOR_TYPE_OVERRIDE] = self.cursorTypeOverride;
        if (self.lastDirectory) {
            DLog(@"Saving arrangement for %@ with lastDirectory of %@", self, self.lastDirectory);
            result[SESSION_ARRANGEMENT_LAST_DIRECTORY] = self.lastDirectory;
        }
        if (self.lastLocalDirectory) {
            result[SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY] = self.lastLocalDirectory;
            result[SESSION_ARRANGEMENT_LAST_LOCAL_DIRECTORY_WAS_PUSHED] = @(self.lastLocalDirectoryWasPushed);
        }
        result[SESSION_ARRANGEMENT_SELECTION] =
        [self.textview.selection dictionaryValueWithYOffset:-numberOfLinesDropped
                                    totalScrollbackOverflow:_screen.totalScrollbackOverflow];
        result[SESSION_ARRANGEMENT_APS] = [_automaticProfileSwitcher savedState];
        result[SESSION_ARRANGEMENT_SSH_STATE] = @(_sshState);
        if (_conductor) {
            NSString *json = _conductor.jsonValue;
            if (json) {
                result[SESSION_ARRANGEMENT_CONDUCTOR] = json;
            }
        }
    } else {
        if (_conductor &&
            [self.profile[KEY_CUSTOM_COMMAND] isEqualTo:kProfilePreferenceCommandTypeSSHValue]) {
            result[SESSION_ARRANGEMENT_PENDING_JUMPS] = [self.sshCommandLineSequence mapWithBlock:^id _Nullable(iTermSSHReconnectionInfo * _Nonnull anObject) {
                return anObject.serialized;
            }];
        }
    }
    result[SESSION_ARRANGEMENT_GUID] = _guid;
    if (_liveSession && includeContents && !_dvr) {
        [result encodeDictionaryWithKey:SESSION_ARRANGEMENT_LIVE_SESSION
                             generation:iTermGenerationAlwaysEncode
                                  block:^BOOL(id<iTermEncoderAdapter>  _Nonnull encoder) {
            return [_liveSession encodeArrangementWithContents:includeContents
                                                       encoder:encoder];
        }];
    }
    DLog(@"self.isTmuxClient=%@", @(self.isTmuxClient));
    if (includeContents && !self.isTmuxClient) {
        DLog(@"Can include restoration info. runJobsInServers=%@ isSessionRestorationPossible=%@",
             @([iTermAdvancedSettingsModel runJobsInServers]),
             @(_shell.isSessionRestorationPossible));
        // These values are used for restoring sessions after a crash. It's only saved when contents
        // are included since saved window arrangements have no business knowing the process id.
        if ([iTermAdvancedSettingsModel runJobsInServers] && _shell.isSessionRestorationPossible) {
            NSObject *restorationIdentifier = _shell.sessionRestorationIdentifier;
            DLog(@"Can save restoration id. restorationIdentifier=%@", restorationIdentifier);
            if ([restorationIdentifier isKindOfClass:[NSNumber class]]) {
                result[SESSION_ARRANGEMENT_SERVER_PID] = restorationIdentifier;
            } else if ([restorationIdentifier isKindOfClass:[NSDictionary class]]) {
                result[SESSION_ARRANGEMENT_SERVER_DICT] = restorationIdentifier;
            }
            if (self.tty) {
                result[SESSION_ARRANGEMENT_TTY] = self.tty;
            }
        }
    }
    if (_logging.enabled) {
        result[SESSION_ARRANGEMENT_AUTOLOG_FILENAME] = _logging.path;
    }
    if (_cookie) {
        result[SESSION_ARRANGEMENT_REUSABLE_COOKIE] = _cookie;
    }
    if (_overriddenFields.count > 0) {
        if (replacementProfile) {
            NSMutableSet<NSString *> *combinedOverriddenFields = [[_overriddenFields mutableCopy] autorelease];
            for (NSString *key in [[NSSet setWithArray:[_profile allKeys]] setByAddingObjectsFromSet:[NSSet setWithArray:[replacementProfile allKeys]]]) {
                id mine = _profile[key];
                id theirs = replacementProfile[key];
                if (![NSObject object:mine isEqualToObject:theirs]) {
                    [combinedOverriddenFields addObject:key];
                }
            }
            result[SESSION_ARRANGEMENT_OVERRIDDEN_FIELDS] = combinedOverriddenFields;
            DLog(@"Combined overridden fields are: %@", combinedOverriddenFields);
        } else {
            result[SESSION_ARRANGEMENT_OVERRIDDEN_FIELDS] = _overriddenFields.allObjects;
        }
    }
    if (self.tmuxMode == TMUX_GATEWAY && self.tmuxController.sessionName) {
        result[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] = @YES;
        result[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] = @(self.tmuxController.sessionId);
        result[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME] = self.tmuxController.sessionName;
        NSString *dcsID = [[self.tmuxController.gateway.dcsID copy] autorelease];
        if (dcsID) {
            result[SESSION_ARRANGEMENT_TMUX_DCS_ID] = dcsID;
        }
    }
    if ( _conductor) {
        result[SESSION_ARRANGEMENT_CONDUCTOR_DCS_ID] = _conductor.dcsID;
        result[SESSION_ARRANGEMENT_CONDUCTOR_TREE] = _conductor.tree.it_keyValueCodedData;
    }

    result[SESSION_ARRANGEMENT_SHOULD_EXPECT_PROMPT_MARKS] = @(_screen.shouldExpectPromptMarks);
    result[SESSION_ARRANGEMENT_SHOULD_EXPECT_CURRENT_DIR_UPDATES] = @(_shouldExpectCurrentDirUpdates);
    result[SESSION_ARRANGEMENT_WORKING_DIRECTORY_POLLER_DISABLED] = @(_workingDirectoryPollerDisabled);
    result[SESSION_ARRANGEMENT_COMMANDS] = _commands;
    result[SESSION_ARRANGEMENT_DIRECTORIES] = _directories;
    // If this is slow, it could be encoded more efficiently by using encodeArrayWithKey:...
    // but that would require coming up with a good unique identifier.
    result[SESSION_ARRANGEMENT_HOSTS] = [_hosts mapWithBlock:^id(id anObject) {
        return [(id<VT100RemoteHostReading>)anObject dictionaryValue];
    }];

    NSString *pwd = [self currentLocalWorkingDirectory];
    result[SESSION_ARRANGEMENT_WORKING_DIRECTORY] = pwd ? pwd : @"";
    return YES;
}

+ (NSDictionary *)arrangementFromTmuxParsedLayout:(NSDictionary *)parseNode
                                         bookmark:(Profile *)bookmark
                                   tmuxController:(TmuxController *)tmuxController
                                           window:(int)window {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    [result setObject:[parseNode objectForKey:kLayoutDictWidthKey] forKey:SESSION_ARRANGEMENT_COLUMNS];
    [result setObject:[parseNode objectForKey:kLayoutDictHeightKey] forKey:SESSION_ARRANGEMENT_ROWS];
    [result setObject:bookmark forKey:SESSION_ARRANGEMENT_BOOKMARK];
    [result setObject:@"" forKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY];
    [result setObject:[parseNode objectForKey:kLayoutDictWindowPaneKey] forKey:SESSION_ARRANGEMENT_TMUX_PANE];
    result[SESSION_ARRANGEMENT_TMUX_FOCUS_REPORTING] = parseNode[kLayoutDictFocusReportingKey] ?: @NO;
    NSDictionary *hotkey = parseNode[kLayoutDictHotkeyKey];
    if (hotkey) {
        [result setObject:hotkey forKey:SESSION_ARRANGEMENT_HOTKEY];
    }
    NSObject *value = [parseNode objectForKey:kLayoutDictHistoryKey];
    if (value) {
        [result setObject:value forKey:SESSION_ARRANGEMENT_TMUX_HISTORY];
    }
    value = [parseNode objectForKey:kLayoutDictAltHistoryKey];
    if (value) {
        [result setObject:value forKey:SESSION_ARRANGEMENT_TMUX_ALT_HISTORY];
    }
    value = [parseNode objectForKey:kLayoutDictStateKey];
    if (value) {
        [result setObject:value forKey:SESSION_ARRANGEMENT_TMUX_STATE];
    }
    value = parseNode[kLayoutDictTabColorKey];
    if (value) {
        result[SESSION_ARRANGEMENT_TMUX_TAB_COLOR] = value;
    }
    NSDictionary *fontOverrides = [tmuxController fontOverridesForWindow:window];
    if (fontOverrides) {
        result[SESSION_ARRANGEMENT_FONT_OVERRIDES] = fontOverrides;
    }
    NSDictionary *keyboardMapOverrides = tmuxController.sharedKeyMappingOverrides;
    if (keyboardMapOverrides) {
        result[SESSION_ARRANGEMENT_KEYBOARD_MAP_OVERRIDES] = [[keyboardMapOverrides copy] autorelease];
    }
    return result;
}

+ (NSString *)guidInArrangement:(NSDictionary *)arrangement {
    NSString *guid = arrangement[SESSION_ARRANGEMENT_GUID];
    if (guid) {
        return guid;
    } else {
        return arrangement[SESSION_UNIQUE_ID];
    }
}

+ (NSString *)initialWorkingDirectoryFromArrangement:(NSDictionary *)arrangement {
    return arrangement[SESSION_ARRANGEMENT_WORKING_DIRECTORY];
}

- (BOOL)shouldUpdateTitles:(NSTimeInterval)now {
    // Update window info for the active tab.
    if (!self.jobName) {
        return YES;
    }
    if ([self.processInfoProvider processIsDirty:_shell.pid]) {
        DLog(@"Update title immediately because process %@ is dirty", @(_shell.pid));
        return YES;
    }

    static const NSTimeInterval dirtyTitlePeriod = 0.02;
    static const NSTimeInterval pollingTitlePeriod = 0.7;
    const NSTimeInterval elapsedTime = now - _lastUpdate;
    const NSTimeInterval deadline = _titleDirty ? dirtyTitlePeriod : pollingTitlePeriod;
    if (elapsedTime >= deadline) {
        return YES;
    }

    return NO;
}

- (void)maybeUpdateTitles {
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if ([self shouldUpdateTitles:now]) {
        [self updateTitles];
        _lastUpdate = now;
        _titleDirty = NO;
    }
}

- (void)updateDisplayBecause:(NSString *)reason {
    DLog(@"updateDisplayBecause:%@ %@", reason, _cadenceController);
    _updateCount++;
    if (_useMetal && _updateCount % 10 == 0) {
        iTermPreciseTimerSaveLog([NSString stringWithFormat:@"%@: updateDisplay interval", _view.driver.identifier],
                                 _cadenceController.histogram.stringValue);
    }
    _timerRunning = YES;

    // This syncs with the mutation thread.
    DLog(@"Session %@ calling refresh", self);
    const BOOL somethingIsBlinking = [_textview refresh];

    // Set attributes of tab to indicate idle, processing, etc.
    if (![self isTmuxGateway]) {
        [_delegate updateLabelAttributes];
    }

    if ([_delegate sessionIsActiveInTab:self]) {
        [self maybeUpdateTitles];
    } else {
        [self setCurrentForegroundJobProcessInfo:[self.sessionProcessInfoProvider cachedProcessInfoIfAvailable]];
        [self.view setTitle:_nameController.presentationSessionTitle];
    }

    const BOOL transientTitle = _delegate.realParentWindow.isShowingTransientTitle;
    const BOOL animationPlaying = _textview.getAndResetDrawingAnimatedImageFlag;

    // Even if "active" isn't changing we need the side effect of setActive: that updates the
    // cadence since we might have just become idle.
    self.active = (somethingIsBlinking || transientTitle || animationPlaying);

    if (_tailFindTimer && _view.findViewIsHidden && !_performingOneShotTailFind) {
        [self stopTailFind];
    }

    const BOOL passwordInput = _shell.passwordInput || _conductor.atPasswordPrompt;
    DLog(@"passwordInput=%@", @(passwordInput));
    if (passwordInput != _passwordInput) {
        _passwordInput = passwordInput;
        [[iTermSecureKeyboardEntryController sharedInstance] update];
        if (passwordInput) {
            [self didBeginPasswordInput];
        }
    }
    _timerRunning = NO;
}

- (BOOL)shouldShowPasswordManagerAutomatically {
    return [iTermProfilePreferences boolForKey:KEY_OPEN_PASSWORD_MANAGER_AUTOMATICALLY
                                     inProfile:self.profile];
}

- (void)didBeginPasswordInput {
    if ([self shouldShowPasswordManagerAutomatically]) {
        iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
        [itad openPasswordManagerToAccountName:nil inSession:self];

    }
}

// Update the tab, session view, and window title.
- (void)updateTitles {
    DLog(@"updateTitles");
    iTermProcessInfo *processInfo = [self.sessionProcessInfoProvider cachedProcessInfoIfAvailable];
    iTermProcessInfo *effectiveProcessInfo = processInfo;
    if (!processInfo && _titleDirty) {
        // It's an emergency. Use whatever is lying around.
        DLog(@"Performing emergency title update");
        effectiveProcessInfo = _lastProcessInfo;
    }
    if (effectiveProcessInfo) {
        [_lastProcessInfo autorelease];
        _lastProcessInfo = [effectiveProcessInfo retain];
        [self updateTitleWithProcessInfo:effectiveProcessInfo];

        if (processInfo) {
            return;
        }
    }
    __weak __typeof(self) weakSelf = self;
    [self.sessionProcessInfoProvider fetchProcessInfoForCurrentJobWithCompletion:^(iTermProcessInfo *processInfo) {
        [weakSelf updateTitleWithProcessInfo:processInfo];
    }];
}

- (void)updateTitleWithProcessInfo:(iTermProcessInfo *)processInfo {
    DLog(@"%@ Job for pid %@ is %@, pid=%@", self, @(_shell.pid), processInfo.name, @(processInfo.processID));
    [self setCurrentForegroundJobProcessInfo:processInfo];

    if ([_delegate sessionBelongsToVisibleTab]) {
        // Revert to the permanent tab title.
        DLog(@"Session asking to set window title. Parent window is %@", [_delegate parentWindow]);
        [[_delegate parentWindow] setWindowTitle];
    }
}

- (NSString *)jobName {
    return [self.variablesScope valueForVariableName:iTermVariableKeySessionJob];
}

- (void)setCurrentForegroundJobProcessInfo:(iTermProcessInfo *)processInfo {
    DLog(@"%p set job name to %@", self, processInfo.name);
    NSString *name = processInfo.name;
    NSString *processTitle = processInfo.argv0 ?: name;

    // This is a gross hack but I haven't found a nicer way to do it yet. When exec fails (or takes
    // enough time that we happen to poll it before exec finishes) then the job name is
    // "iTermServer" as inherited from the parent. This avoids showing it in the UI.
    if ([name isEqualToString:@"iTermServer"] && ![[self.program lastPathComponent] isEqualToString:name]) {
        name = self.program.lastPathComponent;
        processTitle = name;
    }
    [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionJob];
    [self.variablesScope setValue:processTitle forVariableNamed:iTermVariableKeySessionProcessTitle];
    [self.variablesScope setValue:processInfo.commandLine forVariableNamed:iTermVariableKeySessionCommandLine];
    [self.variablesScope setValue:@(processInfo.processID) forVariableNamed:iTermVariableKeySessionJobPid];

    NSNumber *effectiveShellPID = _shell.tmuxClientProcessID ?: @(_shell.pid);
    if (!_exited) {
        if (effectiveShellPID.intValue > 0) {
            [self.variablesScope setValue:effectiveShellPID
                         forVariableNamed:iTermVariableKeySessionChildPid];
        }
        id oldValue = [self.variablesScope valueForVariableName:iTermVariableKeySessionEffectiveSessionRootPid];
        if (_conductor.framing) {
            [self.variablesScope setValue:_conductor.framedPID
                         forVariableNamed:iTermVariableKeySessionEffectiveSessionRootPid];
        } else if (effectiveShellPID.intValue > 0) {
            [self.variablesScope setValue:effectiveShellPID
                         forVariableNamed:iTermVariableKeySessionEffectiveSessionRootPid];
        }
        id newValue = [self.variablesScope valueForVariableName:iTermVariableKeySessionEffectiveSessionRootPid];
        const BOOL changed = ![NSObject object:oldValue isEqualToObject:newValue];
        if (changed) {
            [self.delegate sessionProcessInfoProviderDidChange:self];
        }
    }
    // Avoid join from side-effect.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf tryAutoProfileSwitchWithHostname:weakSelf.variablesScope.hostname
                                          username:weakSelf.variablesScope.username
                                              path:weakSelf.variablesScope.path
                                               job:processInfo.name];
    });
}

- (void)refresh {
    DLog(@"Session %@ calling refresh", self);
    if ([_textview refresh]) {
        self.active = YES;
    }
}

- (void)setActive:(BOOL)active {
    DLog(@"setActive:%@ timerRunning=%@ updateTimer.isValue=%@ lastTimeout=%f session=%@",
         @(active), @(_timerRunning), @(_cadenceController.updateTimerIsValid), _lastTimeout, self);
    _active = active;
    _activityInfo.lastActivity = [NSDate it_timeSinceBoot];
    [_cadenceController changeCadenceIfNeeded];
}

- (void)doAntiIdle {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    if (![self isTmuxGateway] && now >= _lastInput + _antiIdlePeriod - kAntiIdleGracePeriod) {
        // This feature is hopeless for tmux gateways. Issue 5231.
        [self writeLatin1EncodedData:[NSData dataWithBytes:&_antiIdleCode length:1] broadcastAllowed:NO reporting:NO];
        _lastInput = now;
    }
}

- (BOOL)canInstantReplayPrev
{
    if (_dvrDecoder) {
        return [_dvrDecoder timestamp] != [_dvr firstTimeStamp];
    } else {
        return YES;
    }
}

- (BOOL)canInstantReplayNext
{
    if (_dvrDecoder) {
        return YES;
    } else {
        return NO;
    }
}

- (int)rows
{
    return [_screen height];
}

- (int)columns
{
    return [_screen width];
}

- (NSFont *)fontWithRelativeSize:(int)dir from:(NSFont*)font {
    return [font it_fontByAddingToPointSize:dir];
}

- (void)setFontTable:(iTermFontTable *)newFontTable
   horizontalSpacing:(CGFloat)horizontalSpacing
     verticalSpacing:(CGFloat)verticalSpacing {
    DLog(@"setFontTable:%@ horizontalSpacing:%@ verticalSpacing:%@",
         newFontTable, @(horizontalSpacing), @(verticalSpacing));
    NSWindow *window = [[_delegate realParentWindow] window];
    DLog(@"Before:\n%@", [window.contentView iterm_recursiveDescription]);
    DLog(@"Window frame: %@", window);
    if ([_textview.fontTable isEqual:newFontTable] &&
        [_textview horizontalSpacing] == horizontalSpacing &&
        [_textview verticalSpacing] == verticalSpacing) {
        // There's an unfortunate problem that this is a band-aid over.
        // If you change some attribute of a profile that causes sessions to reload their profiles
        // with the kReloadAllProfiles notification, then each profile will call this in turn,
        // and it may be a no-op for all of them. If each calls -[PseudoTerminal fitWindowToTab:_delegate]
        // and different tabs come up with slightly different ideal sizes (e.g., because they
        // have different split pane layouts) then the window may shrink by a few pixels for each
        // session.
        return;
    }
    DLog(@"Line height was %f", [_textview lineHeight]);
    [_textview setFontTable:newFontTable
          horizontalSpacing:horizontalSpacing
            verticalSpacing:verticalSpacing];
    DLog(@"Line height is now %f", [_textview lineHeight]);
    [_delegate sessionDidChangeFontSize:self adjustWindow:!_windowAdjustmentDisabled];
    [_composerManager updateFont];
    DLog(@"After:\n%@", [window.contentView iterm_recursiveDescription]);
    DLog(@"Window frame: %@", window);

    [_view updateTrackingAreas];
}

- (BOOL)shouldShowAutoComposer {
    if (![iTermPreferences boolForKey:kPreferenceAutoComposer]) {
        DLog(@"wantAutoComposer: Disabled by setting");
        return NO;
    }
    return _promptStateAllowsAutoComposer;
}

- (void)dismissComposerIfEmpty {
    DLog(@"dismissComposerIfEmpty called on %@", [NSThread currentThread]);
    if (self.composerManager.isEmpty) {
        DLog(@"dismissComposerifEmpty calling dismissAnimated");
        [self.composerManager dismissAnimated:NO];
    }
    DLog(@"dismissComposerIfEmpty returning");
}

- (void)autoComposerDidChange:(NSNotification *)notification {
    [self sync];
}

static NSString *const PTYSessionComposerPrefixUserDataKeyPrompt = @"prompt";
static NSString *const PTYSessionComposerPrefixUserDataKeyDetectedByTrigger = @"detected by trigger";

- (NSMutableAttributedString *)kernedAttributedStringForScreenChars:(NSArray<ScreenCharArray *> *)promptText
                                        elideDefaultBackgroundColor:(BOOL)elideDefaultBackgroundColor {
    NSMutableAttributedString *prompt = [self attributedStringForScreenChars:promptText
                                                 elideDefaultBackgroundColor:elideDefaultBackgroundColor];
    const CGFloat kern = [NSMutableAttributedString kernForString:@"W"
                                                      toHaveWidth:_textview.charWidth
                                                         withFont:_textview.fontTable.asciiFont.font];
    [prompt addAttributes:@{ NSKernAttributeName: @(kern) }
                    range:NSMakeRange(0, prompt.length)];
    return prompt;
}

- (void)revealAutoComposerWithPrompt:(NSArray<ScreenCharArray *> *)promptText {
    assert(_initializationFinished);
    DLog(@"Reveal auto composer. isAutoComposer <- YES");
    self.composerManager.isAutoComposer = YES;
    NSMutableAttributedString *prompt = [self kernedAttributedStringForScreenChars:promptText
                                                       elideDefaultBackgroundColor:YES];
    [self.composerManager revealMakingFirstResponder:[self textViewOrComposerIsFirstResponder]];
    NSDictionary *userData = nil;
    DLog(@"revealing auto composer");
    if (_screen.lastPromptMark.promptText) {
        DLog(@"Set prefix to %@", prompt.string);
        userData = @{
            PTYSessionComposerPrefixUserDataKeyPrompt: [[_screen.lastPromptMark.promptText copy] autorelease],
            PTYSessionComposerPrefixUserDataKeyDetectedByTrigger: @(_screen.lastPromptMark.promptDetectedByTrigger)
        };
    }
    [self.composerManager setPrefix:prompt
                           userData:userData];
}

- (NSMutableAttributedString *)attributedStringForScreenChars:(NSArray<ScreenCharArray *> *)promptText
                                  elideDefaultBackgroundColor:(BOOL)elideDefaultBackgroundColor {
    if (!_textview) {
        return nil;
    }
    NSDictionary *defaultAttributes = [_textview attributeProviderUsingProcessedColors:YES
                                                           elideDefaultBackgroundColor:elideDefaultBackgroundColor]((screen_char_t){}, nil);
    NSAttributedString *space = [NSAttributedString attributedStringWithString:@" "
                                                                      attributes:defaultAttributes];

    NSAttributedString *newline = [NSAttributedString attributedStringWithString:@"\n"
                                                                      attributes:defaultAttributes];

    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    NSAttributedString *body = [[promptText mapWithBlock:^id _Nullable(ScreenCharArray *sca) {
        return [sca attributedStringValueWithAttributeProvider:[_textview attributeProviderUsingProcessedColors:YES
                                                                                    elideDefaultBackgroundColor:elideDefaultBackgroundColor]];
    }] attributedComponentsJoinedByAttributedString:newline];
    [result appendAttributedString:body];
    [result trimTrailingWhitespace];
    [result appendAttributedString:space];
    return result;
}

- (void)terminalFileShouldStop:(NSNotification *)notification {
    if ([notification object] == _download) {
        [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                 VT100ScreenMutableState *mutableState,
                                                 id<VT100ScreenDelegate> delegate) {
            [terminal stopReceivingFile];
            [_download endOfData];
            self.download = nil;
        }];
    } else if ([notification object] == _upload) {
        [_pasteHelper abort];
        [_upload endOfData];
        self.upload = nil;
        char controlC[1] = { VT100CC_ETX };
        NSData *data = [NSData dataWithBytes:controlC length:sizeof(controlC)];
        [self writeLatin1EncodedData:data broadcastAllowed:NO reporting:NO];
    }
}

- (void)profileSessionNameDidEndEditing:(NSNotification *)notification {
    NSString *theGuid = [notification object];
    if (_tmuxTitleOutOfSync &&
        [self isTmuxClient] &&
        [theGuid isEqualToString:_profile[KEY_GUID]]) {
        Profile *profile = [[ProfileModel sessionsInstance] bookmarkWithGuid:theGuid];
        if (_tmuxController.canRenamePane) {
            [_tmuxController renamePane:self.tmuxPane toTitle:profile[KEY_NAME]];
            [_tmuxTitleMonitor updateOnce];
        } else {
            // Legacy code path for pre tmux 2.6
            [_tmuxController renameWindowWithId:_delegate.tmuxWindow
                                inSessionNumber:nil
                                         toName:profile[KEY_NAME]];
        }
        _tmuxTitleOutOfSync = NO;
    }
}

- (void)sessionHotkeyDidChange:(NSNotification *)notification {
    NSString *theGuid = [notification object];
    if ([self isTmuxClient] &&
        [theGuid isEqualToString:_profile[KEY_GUID]]) {
        Profile *profile = [[ProfileModel sessionsInstance] bookmarkWithGuid:theGuid];
        NSDictionary *dict = [iTermProfilePreferences objectForKey:KEY_SESSION_HOTKEY inProfile:profile];
        [_tmuxController setHotkeyForWindowPane:self.tmuxPane to:dict];
    }
}

- (void)apiDidStop:(NSNotification *)notification {
    [_promptSubscriptions removeAllObjects];
    [_keystrokeSubscriptions removeAllObjects];
    [_keyboardFilterSubscriptions removeAllObjects];
    [_updateSubscriptions removeAllObjects];
    [_customEscapeSequenceNotifications removeAllObjects];
}

- (void)apiServerUnsubscribe:(NSNotification *)notification {
    [_promptSubscriptions removeObjectForKey:notification.object];
    [_keystrokeSubscriptions removeObjectForKey:notification.object];
    [_keyboardFilterSubscriptions removeObjectForKey:notification.object];
    [_updateSubscriptions removeObjectForKey:notification.object];
    [_customEscapeSequenceNotifications removeObjectForKey:notification.object];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // See comment where we observe this notification for why this is done.
    [self tmuxDetach];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    DLog(@"%@", self);
    // Avoid posting a notification after switching to another app for output received just
    // before the switch. This is tricky! self.newOutput can't be reset unconditionally because
    // doing so breaks idle notifications when new output eventually stops being received.
    // If you have new output and you haven't already posted a new-output notification then
    // you can be confident that an idle notification is not forthcoming and then you can
    // safely reset newOutput.
    if (self.newOutput && [self.delegate sessionIsInSelectedTab:self] && !self.havePostedNewOutputNotification) {
        DLog(@"self.newOutput = NO");
        self.newOutput = NO;
    }
}

- (void)refreshTerminal:(NSNotification *)notification {
    [self sync];
}

- (void)metalClipViewWillScroll:(NSNotification *)notification {
    if (_useMetal && notification.object == _textview.enclosingScrollView.contentView) {
        [_textview shiftTrackingChildWindows];
    }
}

- (void)alertOnMarksinOffscreenSessionsDidChange:(NSNotification *)notification {
    DLog(@"alertOnMarksinOffscreenSessionsDidChange for %@", self);
    _alertOnMarksinOffscreenSessions = [iTermPreferences boolForKey:kPreferenceKeyAlertOnMarksInOffscreenSessions];
    [self sync];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
    DLog(@"windowDidMiniaturize for %@", self);
    if (_alertOnMarksinOffscreenSessions) {
        [self sync];
    }
}

- (void)activeSpaceDidChange:(NSNotification *)notification {
    DLog(@"activeSpaceDidChange for %@", self);
    if (_alertOnMarksinOffscreenSessions) {
        [self sync];
    }
}

- (void)savedArrangementWasRepaired:(NSNotification *)notification {
    if ([notification.object isEqual:_naggingController.missingSavedArrangementProfileGUID]) {
        Profile *newProfile = notification.userInfo[@"new profile"];
        [self setIsDivorced:NO withDecree:@"Saved arrangement was repaired. Set divorced to NO."];
        DLog(@"saved arrangement repaired, remove all overridden fields");
        [_overriddenFields removeAllObjects];
        [_originalProfile release];
        _originalProfile = nil;
        self.profile = newProfile;
        [self setPreferencesFromAddressBookEntry:newProfile];
        [_naggingController didRepairSavedArrangement];
    }
}

- (void)windowWillStartLiveResize:(NSNotification *)notification {
    if ([iTermAdvancedSettingsModel trackingRunloopForLiveResize]) {
        if (notification.object == self.textview.window) {
            _inLiveResize = YES;
            [_cadenceController willStartLiveResize];
        }
    }
}

- (void)windowDidEndLiveResize:(NSNotification *)notification {
    if ([iTermAdvancedSettingsModel trackingRunloopForLiveResize]) {
        if (notification.object == self.textview.window) {
            _inLiveResize = NO;
            [_cadenceController liveResizeDidEnd];
        }
    }
}

- (void)synchronizeTmuxFonts:(NSNotification *)notification {
    if (!_exited && [self isTmuxClient]) {
        NSArray *args = [notification object];
        iTermFontTable *fontTable = args[0];
        NSNumber *hSpacing = args[1];
        NSNumber *vSpacing = args[2];
        TmuxController *controller = args[3];
        NSNumber *tmuxWindow = args[4];
        if (controller == _tmuxController &&
            (!controller.variableWindowSize || tmuxWindow.intValue == self.delegate.tmuxWindow)) {
            [_textview setFontTable:fontTable
                  horizontalSpacing:[hSpacing doubleValue]
                    verticalSpacing:[vSpacing doubleValue]];
        }
    }
}

- (void)notifyTmuxFontChange
{
    static BOOL fontChangeNotificationInProgress;
    if (!fontChangeNotificationInProgress) {
        fontChangeNotificationInProgress = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxFontChanged
                                                            object:@[ _textview.fontTable,
                                                                      @(_textview.horizontalSpacing),
                                                                      @(_textview.verticalSpacing),
                                                                      _tmuxController ?: [NSNull null],
                                                                      @(self.delegate.tmuxWindow)]];
        fontChangeNotificationInProgress = NO;
        [_delegate setTmuxFontTable:_textview.fontTable
                      hSpacing:_textview.horizontalSpacing
                      vSpacing:_textview.verticalSpacing];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionTmuxFontDidChange
                                                            object:self];
    }
}

- (void)changeFontSizeDirection:(int)dir {
    DLog(@"changeFontSizeDirection:%d", dir);
    CGFloat hs;
    CGFloat vs;
    iTermFontTable *newFontTable;
    if (dir) {
        // Grow or shrink
        DLog(@"grow/shrink");
        newFontTable = [_textview.fontTable fontTableGrownBy:dir];
        hs = [_textview horizontalSpacing];
        vs = [_textview verticalSpacing];
    } else {
        // Restore original font size.
        NSDictionary *originalProfile = [self originalProfile];
        newFontTable = [iTermFontTable fontTableForProfile:originalProfile];
        hs = [iTermProfilePreferences doubleForKey:KEY_HORIZONTAL_SPACING inProfile:originalProfile];
        vs = [iTermProfilePreferences doubleForKey:KEY_VERTICAL_SPACING inProfile:originalProfile];
    }
    [self setFontTable:newFontTable horizontalSpacing:hs verticalSpacing:vs];

    if (dir || self.isDivorced) {
        // Move this bookmark into the sessions model.
        NSString* guid = [self divorceAddressBookEntryFromPreferences];

        // Set the font in the bookmark dictionary
        [self setSessionSpecificProfileValues:@{
                              KEY_NORMAL_FONT: [newFontTable.asciiFont.font stringValue],
                           KEY_NON_ASCII_FONT: [newFontTable.defaultNonASCIIFont.font stringValue] ?: [NSNull null],
                              KEY_FONT_CONFIG: newFontTable.configString ?: [NSNull null]
        }];

        // Update the model's copy of the bookmark.
        [[ProfileModel sessionsInstance] setBookmark:[self profile] withGuid:guid];

        // Update an existing one-bookmark prefs dialog, if open.
        if ([[[PreferencePanel sessionsInstance] windowIfLoaded] isVisible]) {
            [[PreferencePanel sessionsInstance] underlyingProfileDidChange];
        }
    }
}

- (BOOL)profileValuesDifferFromCurrentProfile:(NSDictionary *)newValues {
    for (NSString *key in newValues) {
        if ([key isEqualToString:KEY_GUID] || [key isEqualToString:KEY_ORIGINAL_GUID]) {
            continue;
        }
        NSObject *value = newValues[key];
        if (![NSObject object:_profile[key] isEqualToObject:value]) {
            return YES;
        }
    }
    return NO;
}

// Missing values are replaced with their defaults. If everything matches excluding deprecated keys
// then the profiles are equivalent.
- (BOOL)profile:(Profile *)profile1 isEffectivelyEqualToProfile:(Profile *)profile2 {
    for (NSString *key in [iTermProfilePreferences nonDeprecatedKeys]) {
        id value1 = [iTermProfilePreferences objectForKey:key inProfile:profile1];
        id value2 = [iTermProfilePreferences objectForKey:key inProfile:profile2];

        if ([NSObject object:value1 isEqualToObject:value2]) {
            continue;
        }
        return NO;
    }
    return YES;
}

- (NSString *)amendedColorKey:(NSString *)baseKey {
    return iTermAmendedColorKey(baseKey, self.profile, [NSApp effectiveAppearance].it_isDark);
}

- (void)setSessionSpecificProfileValues:(NSDictionary *)newValues {
    DLog(@"%@: setSessionSpecificProfilevalues:%@", self, newValues);
    if (![self profileValuesDifferFromCurrentProfile:newValues]) {
        DLog(@"No changes to be made");
        return;
    }

    // Consider the possibility that newValues exactly matches an existing shared profile or is
    // a modified copy of a shared profile.
    NSString *const newGuid = newValues[KEY_GUID];
    if (newGuid) {
        Profile *const existingProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:newGuid];
        if (existingProfile) {
            DLog(@"Switching to existing profile");
            // Switch to the existing profile. This will remarry if possible.
            [self setProfile:existingProfile preservingName:NO adjustWindow:YES];

            // Are we done?
            if ([self profile:existingProfile isEffectivelyEqualToProfile:newValues]) {
                DLog(@"Effectively equivalent to existing profile");
                // Since you switched to a shared profile that is an exact match, we're done.
                return;
            }

            // No. Divorce and modify. This takes care of making everything right, such as setting
            // the original profile guid.
            DLog(@"Divorce and modify");
        }
    }

    // Normal case: divorce and update a subset of properties.
    if (!self.isDivorced) {
        [self divorceAddressBookEntryFromPreferences];
    }

    // Build a copy of the current dictionary, replacing values with those provided in newValues.
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:_profile];
    for (NSString *key in newValues) {
        if ([key isEqualToString:KEY_GUID] || [key isEqualToString:KEY_ORIGINAL_GUID]) {
            continue;
        }
        NSObject *value = newValues[key];
        if ([value isKindOfClass:[NSNull class]]) {
            [temp removeObjectForKey:key];
        } else {
            temp[key] = value;
        }
    }
    if ([self profile:temp isEffectivelyEqualToProfile:_profile]) {
        DLog(@"Not doing anything because temp is equal to _profile");
        // This was a no-op, so there's no need to get a divorce. Happens most
        // commonly when setting tab color after a split.
        return;
    }
    DLog(@"Set bookmark and reload profile");
    [[ProfileModel sessionsInstance] setBookmark:temp withGuid:temp[KEY_GUID]];

    // Update this session's copy of the bookmark
    [self reloadProfile];
}

- (void)remarry {
    [self setIsDivorced:NO withDecree:[NSString stringWithFormat:@"Remarry"]];
}

// TBH I'm not 100% sure this is correct. Don't use it for anything critical until this whole mess
// has been burned to the ground and rebuilt.
- (NSString *)guidOfUnderlyingProfile {
    if (!self.isDivorced) {
        return self.profile[KEY_GUID];
    }

    NSString *guid = _originalProfile[KEY_GUID];
    if (guid && [[ProfileModel sharedInstance] bookmarkWithGuid:guid]) {
        return guid;
    }

    return nil;
}

- (BOOL)isDivorced {
    return _divorced;
}

- (void)inheritDivorceFrom:(PTYSession *)parent decree:(NSString *)decree {
    assert(parent);
    [self setIsDivorced:YES withDecree:decree];
    [_overriddenFields removeAllObjects];
    [_overriddenFields addObjectsFromArray:parent->_overriddenFields.allObjects];
    DLog(@"%@: Set overridden fields from %@: %@", self, parent, _overriddenFields);
}

- (void)setIsDivorced:(BOOL)isDivorced withDecree:(NSString *)decree {
    _divorced = isDivorced;
    NSString *guid = self.profile[KEY_GUID];
    if (guid) {
        [[ProfileModel sessionsInstance] addGuidToDebug:guid];
    }
    [self setDivorceDecree:[NSString stringWithFormat:@"isDivorced=%@ Decree=%@ guid=%@ Stack:\n%@", @(isDivorced), decree, guid, [NSThread callStackSymbols]]];
}

- (void)setDivorceDecree:(NSString *)decree {
    [_divorceDecree autorelease];
    _divorceDecree = [decree copy];
}

#define DIVORCE_LOG(args...) do { \
DLog(args); \
[logs addObject:[NSString stringWithFormat:args]]; \
} while (0)

- (NSString *)divorceAddressBookEntryFromPreferences {
    Profile *bookmark = [self profile];
    NSString *guid = [bookmark objectForKey:KEY_GUID];
    if (self.isDivorced) {
        ITAssertWithMessage([[ProfileModel sessionsInstance] bookmarkWithGuid:guid] != nil,
                            @"I am divorced with guid %@ but the sessions instance has no such guid. Log:\n%@\n\nModel log:\n%@\nEnd.",
                            guid,
                            _divorceDecree,
                            [[[[ProfileModel sessionsInstance] debugHistoryForGuid:guid] componentsJoinedByString:@"\n"] it_compressedString]);
        return guid;
    }
    [self setIsDivorced:YES withDecree:@"PLACEHOLDER DECREE"];
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    DIVORCE_LOG(@"Remove profile with guid %@ from sessions instance", guid);
    [[ProfileModel sessionsInstance] removeProfileWithGuid:guid];
    DIVORCE_LOG(@"Set profile %@ divorced, add to sessions instance", bookmark[KEY_GUID]);
    [[ProfileModel sessionsInstance] addBookmark:[[bookmark copy] autorelease]];

    NSString *existingOriginalGuid = bookmark[KEY_ORIGINAL_GUID];
    if (!existingOriginalGuid ||
        ![[ProfileModel sharedInstance] bookmarkWithGuid:existingOriginalGuid] ||
        ![existingOriginalGuid isEqualToString:_originalProfile[KEY_GUID]]) {
        // The bookmark doesn't already have a valid original GUID.
        bookmark = [[ProfileModel sessionsInstance] setObject:guid
                                                       forKey:KEY_ORIGINAL_GUID
                                                   inBookmark:bookmark];
    }

    // Allocate a new guid for this bookmark.
    guid = [ProfileModel freshGuid];
    DIVORCE_LOG(@"Allocating a new guid for this profile. The new guid is %@", guid);
    [[ProfileModel sessionsInstance] addGuidToDebug:guid];
    [[ProfileModel sessionsInstance] setObject:guid
                                        forKey:KEY_GUID
                                    inBookmark:bookmark];
    [_overriddenFields removeAllObjects];
    [_overriddenFields addObjectsFromArray:@[ KEY_GUID, KEY_ORIGINAL_GUID] ];
    [self setProfile:[[ProfileModel sessionsInstance] bookmarkWithGuid:guid]];
    [logs addObject:@"Stack trace:"];
    [logs addObject:[[NSThread callStackSymbols] componentsJoinedByString:@"\n"]];
    [self setDivorceDecree:[logs componentsJoinedByString:@"\n"]];
    DLog(@"%p: divorce. overridden fields are now %@", self, _overriddenFields);
    return guid;
}

- (void)refreshOverriddenFields {
    [self sessionProfileDidChange];
}

// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition {
    id<VT100ScreenMarkReading> mark = [_screen lastMark];
    Interval *interval = mark.entry.interval;
    if (!interval) {
        DLog(@"Beep: Can't jump to bad interval");
        NSBeep();
        return;
    }
    VT100GridRange range = [_screen lineNumberRangeOfInterval:interval];
    long long offset = range.location;
    if (offset < 0) {
        DLog(@"Beep: Can't jump to negative offset");
        NSBeep();  // This really shouldn't ever happen
    } else {
        self.currentMarkOrNotePosition = mark.entry.interval;
        offset += [_screen totalScrollbackOverflow];
        [_textview scrollToAbsoluteOffset:offset height:[_screen height]];
        [_textview highlightMarkOnLine:VT100GridRangeMax(range) hasErrorCode:NO];
    }
}

- (void)setCurrentMarkOrNotePosition:(Interval *)currentMarkOrNotePosition {
    [_currentMarkOrNotePosition autorelease];
    _currentMarkOrNotePosition = [currentMarkOrNotePosition retain];
    ITBetaAssert(currentMarkOrNotePosition.limit >= 0, @"Negative limit in current mark or note %@", currentMarkOrNotePosition);
}

- (BOOL)hasSavedScrollPosition
{
    return [_screen lastMark] != nil;
}

- (void)findPasteboardStringDidChangeTo:(NSString *)string {
    if (!_view.findDriver.shouldSearchAutomatically) {
        return;
    }
    [_view.findDriver highlightWithoutSelectingSearchResultsForQuery:string];
}

- (void)findWithSelection {
    if ([_textview selectedText]) {
        [_view.findDriver setFindStringUnconditionally:_textview.selectedText];
    }
}

- (void)showFindPanel {
    [_view showFindUI];
}

- (void)showFilter {
    [_view showFilter];
}

- (iTermComposerManager *)composerManager {
    if (!_composerManager) {
        _composerManager = [[iTermComposerManager alloc] init];
        _composerManager.delegate = self;
    }
    return _composerManager;
}

- (void)compose {
    self.composerManager.isAutoComposer = self.shouldShowAutoComposer;
    if (self.currentCommand.length > 0) {
        [self setComposerString:self.currentCommand];
    }
    [self.composerManager toggle];
}

- (void)setComposerString:(NSString *)string {
    [self sendHexCode:[iTermAdvancedSettingsModel composerClearSequence]];
    [self.composerManager setCommand:string];
}

- (BOOL)closeComposer {
    if (_composerManager.isAutoComposer) {
        // We don't want cmd-W to close the auto composer because it'll just open back up immediately.
        return NO;
    }
    return [_composerManager dismiss];
}

// Note that the caller is responsible for respecting swapFindNextPrevious
- (void)searchNext {
    [_view createFindDriverIfNeeded];
    [_view.findDriver searchNext];
    [self beginOneShotTailFind];
}

// Note that the caller is responsible for respecting swapFindNextPrevious
- (void)searchPrevious {
    [_view createFindDriverIfNeeded];
    [_view.findDriver searchPrevious];
    [self beginOneShotTailFind];
}

- (void)resetFindCursor {
    [_textview resetFindCursor];
}

- (BOOL)findInProgress {
    return [_textview findInProgress];
}

- (BOOL)continueFind:(double *)progress range:(NSRange *)rangePtr {
    return [_textview continueFind:progress range:rangePtr];
}

- (BOOL)growSelectionLeft {
    return [_textview growSelectionLeft];
}

- (void)growSelectionRight {
    [_textview growSelectionRight];
}

- (NSString *)selectedText {
    return [_textview selectedText];
}

- (BOOL)canSearch {
    return _textview != nil && _delegate && [_delegate realParentWindow];
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
scrollToFirstResult:(BOOL)scrollToFirstResult
             force:(BOOL)force {
    DLog(@"self=%@ aString=%@", self, aString);
    [_textview findString:aString
         forwardDirection:direction
                     mode:mode
               withOffset:offset
      scrollToFirstResult:scrollToFirstResult
                    force:force];
}

- (NSString *)unpaddedSelectedText {
    return [_textview selectedText];
}

- (void)copySelection {
    return [_textview copySelectionAccordingToUserPreferences];
}

- (void)takeFocus {
    [[[_delegate realParentWindow] window] makeFirstResponder:_textview];
}

- (void)findViewControllerMakeDocumentFirstResponder {
    [self takeFocus];
}

- (void)findViewControllerClearSearch {
    DLog(@"begin");
    [_textview clearHighlights:YES];
}

- (void)findViewControllerVisibilityDidChange:(id<iTermFindViewController>)sender {
    [_delegate sessionUpdateMetalAllowed];
    if (sender.driver.isVisible) {
        return;
    }
    if (_view.findViewHasKeyboardFocus) {
        [_view findViewDidHide];
    }
}

- (void)setFilter:(NSString *)filter {
    _modeHandler.mode = iTermSessionModeDefault;
    DLog(@"setFilter:%@", filter);
    if ([filter isEqualToString:_filter]) {
        return;
    }
    if (!filter) {
        if (_asyncFilter) {
            DLog(@"Nuke existing filter %@", _asyncFilter);
            [_asyncFilter cancel];
            [self.liveSession removeContentSubscriber:_asyncFilter];
            [_filter autorelease];
            _filter = nil;
            [_asyncFilter release];
            _asyncFilter = nil;
        }
        return;
    }

    PTYSession *sourceSession = self.liveSession;
    VT100Screen *source = sourceSession.screen;
    [_asyncFilter cancel];
    [self.liveSession removeContentSubscriber:_asyncFilter];
    const BOOL replacingFilter = (_filter != nil);
    assert(self.liveSession);

    [_filter autorelease];
    _filter = [filter copy];

    iTermAsyncFilter *refining = [[_asyncFilter retain] autorelease];
    [_asyncFilter release];

    DLog(@"Append lines from %@", self.liveSession);
    __weak __typeof(self) weakSelf = self;
    DLog(@"Will create new async filter for query %@ refining %@", filter, refining.it_addressString);
    _asyncFilter = [source newAsyncFilterWithDestination:self
                                                   query:filter
                                                refining:refining
                                            absLineRange:sourceSession.textview.findOnPageHelper.absLineRange
                                                progress:^(double progress) {
        [weakSelf setFilterProgress:progress];
    }];
    if (sourceSession.textview.findOnPageHelper.absLineRange.length == 0 ||
        (_selectedCommandMark == [_screen lastPromptMark] && sourceSession.selectedCommandMark.isRunning)) {
        [self.liveSession addContentSubscriber:_asyncFilter];
    }
    if (replacingFilter) {
        DLog(@"Clear buffer because there is a pre-existing filter");
        [self.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            [mutableState clearBufferWithoutTriggersSavingPrompt:NO];
        }];
    }
    [_asyncFilter start];
}

- (id<VT100ScreenMarkReading>)selectedCommandMark {
    return _selectedCommandMark;
}

- (void)setFilterProgress:(double)progress {
    _view.findDriver.filterProgress = progress;
    _statusBarViewController.filterViewController.filterProgress = progress;
}

- (void)findDriverFilterVisibilityDidChange:(BOOL)visible {
    if (!visible) {
        [_asyncFilter cancel];
        [self.liveSession removeContentSubscriber:_asyncFilter];
        [_asyncFilter autorelease];
        _asyncFilter = nil;
        PTYSession *liveSession = [[self.liveSession retain] autorelease];
        [self.delegate session:self setFilter:nil];
        [liveSession.view.findDriver close];
    }
}

- (void)findDriverSetFilter:(NSString *)filter withSideEffects:(BOOL)withSideEffects{
    if (withSideEffects) {
        [self.delegate session:self setFilter:filter];
    }
}

- (void)findViewControllerDidCeaseToBeMandatory:(id<iTermFindViewController>)sender {
    [_view findViewDidHide];
}

- (void)findDriverInvalidateFrame {
    [_view findDriverInvalidateFrame];
}

- (NSImage *)snapshot {
    DLog(@"Session %@ calling refresh", self);
    [_textview refresh];
    return [_view snapshot];
}

- (NSImage *)snapshotCenteredOn:(VT100GridAbsCoord)coord size:(NSSize)size {
    if (_screen.totalScrollbackOverflow > coord.y) {
        return nil;
    }
    VT100GridCoord relativeCoord = VT100GridCoordMake(coord.x,
                                                      coord.y - _screen.totalScrollbackOverflow);
    NSPoint centerPoint = [_textview pointForCoord:relativeCoord];
    NSRect rect = NSMakeRect(MIN(MAX(0, centerPoint.x - size.width / 2), NSWidth(_textview.bounds)),
                             MIN(MAX(0, centerPoint.y - size.height / 2), NSHeight(_textview.bounds)),
                             MIN(NSWidth(_textview.bounds), size.width),
                             MIN(NSHeight(_textview.bounds), size.height));
    CGFloat overage = NSMaxX(rect) - NSWidth(_textview.bounds);
    if (overage > 0) {
        rect.origin.x -= overage;
    }

    overage = NSMaxY(rect) - NSHeight(_textview.bounds);
    if (overage > 0) {
        rect.origin.y -= overage;
    }

    return [_textview snapshotOfRect:rect];
}

- (NSInteger)findDriverNumberOfSearchResults {
    return _textview.findOnPageHelper.numberOfSearchResults;
}

- (NSInteger)findDriverCurrentIndex {
    return _textview.findOnPageHelper.currentIndex;
}

- (void)copyTextFromBlockWithID:(NSString *)blockID {
    const long long absLine = [_screen startAbsLineForBlock:blockID];
    if (absLine < 0) {
        return;
    }
    [_textview copyBlock:blockID includingAbsLine:absLine];
}

#pragma mark - Metal Support

#pragma mark iTermMetalGlueDelegate

- (iTermImageWrapper *)metalGlueBackgroundImage {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return _backgroundImage;
    } else {
        return [self.delegate sessionBackgroundImage];
    }
}

- (iTermBackgroundImageMode)metalGlueBackgroundImageMode {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return _backgroundImageMode;
    } else {
        return [self.delegate sessionBackgroundImageMode];
    }
}

- (CGFloat)metalGlueBackgroundImageBlend {
    return [self effectiveBlend];
}

- (void)metalGlueDidDrawFrameAndNeedsRedraw:(BOOL)redrawAsap NS_AVAILABLE_MAC(10_11) {
    if (_view.useMetal) {
        if (redrawAsap) {
            [_textview requestDelegateRedraw];
        }
    }
}

- (CGContextRef)metalGlueContext {
    return _metalContext;
}

+ (CGColorSpaceRef)metalColorSpace {
    static dispatch_once_t onceToken;
    static CGColorSpaceRef colorSpace;
    dispatch_once(&onceToken, ^{
        colorSpace = CGColorSpaceCreateDeviceRGB();
        ITAssertWithMessage(colorSpace, @"Colorspace is %@", colorSpace);
    });
    return colorSpace;
}

+ (CGContextRef)onePixelContext {
    static CGContextRef context;
    if (context == NULL) {
        context = CGBitmapContextCreate(NULL,
                                        1,
                                        1,
                                        8,
                                        1 * 4,
                                        [self metalColorSpace],
                                        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    }
    return context;
}

- (void)setMetalContextSize:(CGSize)size {
    DLog(@"%@", self);
    if (!self.textview.window) {
        DLog(@"No window");
        CGContextRelease(_metalContext);
        _metalContext = NULL;
        return;
    }

    const CGFloat scale = self.textview.window.backingScaleFactor;
    const int radius = (iTermTextureMapMaxCharacterParts / 2) * 2 + 1;
    CGSize scaledSize = CGSizeMake(size.width * scale * radius, size.height * scale * radius);
    if (_metalContext) {
        if (CGSizeEqualToSize(scaledSize, CGSizeMake(CGBitmapContextGetWidth(_metalContext),
                                                     CGBitmapContextGetHeight(_metalContext)))) {
            DLog(@"No size change");
            return;
        }
        CGContextRelease(_metalContext);
        _metalContext = NULL;
    }
    DLog(@"allocate new metal context of size %@", NSStringFromSize(scaledSize));
    _metalContext = CGBitmapContextCreate(NULL,
                                          scaledSize.width,
                                          scaledSize.height,
                                          8,
                                          scaledSize.width * 4,  // bytes per row
                                          [PTYSession metalColorSpace],
                                          kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
}

- (BOOL)metalAllowed {
    return [self metalAllowed:nil];
}

- (BOOL)usingIntegratedGPU {
    if (_view.metalView.device != nil) {
        const BOOL result = _view.metalView.device.isLowPower;
        DLog(@"usingIntegratedGPU=%@", @(result));
        return result;
    }
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        for (PTYSession *session in term.allSessions) {
            if (session.view.metalView.device != nil) {
                const BOOL result = session.view.metalView.device.isLowPower;
                DLog(@"Found another session %p with a metal device, usingIntegratedGPU=%@", session, @(result));
                return result;
            }
        }
    }

    DLog(@"Check if the system has an integrated GPU");
    static BOOL haveIntegrated;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
        haveIntegrated = NO;
        for (id<MTLDevice> device in devices) {
            if (device.isLowPower) {
                haveIntegrated = YES;
                break;
            }
        }
        CFRelease(devices);
    });
    DLog(@"No sessions using GPU. Return %@.", @(haveIntegrated));
    return haveIntegrated;
}

- (BOOL)metalAllowed:(out iTermMetalUnavailableReason *)reason {
    static dispatch_once_t onceToken;
    static BOOL machineSupportsMetal;
    dispatch_once(&onceToken, ^{
        NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
        machineSupportsMetal = devices.count > 0;
        [devices release];
    });
    if (@available(macOS 12.0, *)) {
        if ([iTermPreferences boolForKey:kPreferenceKeyDisableInLowPowerMode] &&
            [[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonLowerPowerMode;
            }
            return NO;
        }
    }
    if (!machineSupportsMetal) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonNoGPU;
        }
        return NO;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyUseMetal]) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonDisabled;
        }
        return NO;
    }
    if (!self.view.window) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonSessionHasNoWindow;
        }
        return NO;
    }
    if ([PTYSession onePixelContext] == nil) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonContextAllocationFailure;
        }
        return NO;
    }
    if ([self ligaturesEnabledInEitherFont]) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonLigatures;
        }
        return NO;
    }
    if (_metalDeviceChanging) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonInitializing;
        }
        return NO;
    }
    if (![self metalViewSizeIsLegal]) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonInvalidSize;
        }
        return NO;
    }
    if (!_textview) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonSessionInitializing;
        }
        return NO;
    }
    if (_textview.drawingHelper.showDropTargets) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonDropTargetsVisible;
        }
        return NO;
    }
    // Use window occlusion because of issue 9174 but only for integrated GPUs because of issue 9044.
    if ([self usingIntegratedGPU] &&
        [_delegate.realParentWindow.ptyWindow approximateFractionOccluded] > 0.5) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonWindowObscured;
        }
        return NO;
    }
#if ENABLE_FORCE_LEGACY_RENDERER_WITH_PTYTEXTVIEW_SUBVIEWS
    if ([PTYNoteViewController anyNoteVisible] || _textview.contentNavigationShortcuts.count > 0) {
        // When metal is enabled the note's superview (PTYTextView) has alphaValue=0 so it will not be visible.
        if (reason) {
            *reason = iTermMetalUnavailableReasonAnnotations;
        }
        return NO;
    }
    if (_textview.hasPortholes) {
        // When metal is enabled the note's superview (PTYTextView) has alphaValue=0 so it will not be visible.
        if (reason) {
            *reason = iTermMetalUnavailableReasonPortholes;
        }
        return NO;
    }
#endif
    if (_textview.transparencyAlpha < 1) {
        BOOL transparencyAllowed = NO;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (iTermTextIsMonochrome()) {
            transparencyAllowed = YES;
        }
#endif
        if (!transparencyAllowed && _textview.transparencyAlpha < 1) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonTransparency;
            }
            return NO;
        }
    }
    return YES;
}

- (BOOL)canProduceMetalFramecap {
    return _useMetal && _view.metalView.alphaValue == 1 && _wrapper.useMetal && _textview.suppressDrawing;
}

- (BOOL)metalViewSizeIsLegal NS_AVAILABLE_MAC(10_11) {
    NSSize size = _view.frame.size;
    // See "Maximum 2D texture width and height" in "Implementation Limits". Pick the smallest value
    // among the "Mac" columns.
    // https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
    const CGFloat maxScale = 2;
    return size.width > 0 && size.width < (PTYSessionMaximumMetalViewSize / maxScale) && size.height > 0 && size.height < (PTYSessionMaximumMetalViewSize / maxScale);
}

- (BOOL)idleForMetal {
    return (!_cadenceController.isActive &&
            !_view.verticalScroller.userScroll &&
            !self.overrideGlobalDisableMetalWhenIdleSetting &&
            !_view.driver.captureDebugInfoForNextFrame);
}

- (BOOL)ligaturesEnabledInEitherFont {
    iTermTextDrawingHelper *helper = _textview.drawingHelper;
    [helper updateCachedMetrics];
    if (helper.asciiLigatures && helper.asciiLigaturesAvailable) {
        return YES;
    }
    if ([iTermProfilePreferences boolForKey:KEY_USE_NONASCII_FONT inProfile:self.profile] &&
        [iTermProfilePreferences boolForKey:KEY_NON_ASCII_LIGATURES inProfile:self.profile]) {
        return YES;
    }
    return NO;
}

- (BOOL)willEnableMetal {
    DLog(@"%@", self);
    [self updateMetalDriver];
    return _metalContext != nil;
}

- (void)setUseMetal:(BOOL)useMetal {
    if (useMetal == _useMetal) {
        return;
    }
    DLog(@"setUseMetal:%@ %@", @(useMetal), self);
    _useMetal = useMetal;
    // The metalview's alpha will initially be 0. Once it has drawn a frame we'll swap what is visible.
    [self setUseMetal:useMetal dataSource:_metalGlue];
    if (useMetal) {
        [self updateMetalDriver];
        // wrapper.useMetal becomes YES after the first frame is done drawing
    } else {
        _wrapper.useMetal = NO;
        [_metalDisabledTokens removeAllObjects];
        if (_metalContext) {
            // If metal is re-enabled later, it must not use the same context.
            // It's possible that a metal driver thread has survived this point
            // and will continue to use the context.
            CGContextRelease(_metalContext);
            _metalContext = NULL;
        }
    }
    [_textview requestDelegateRedraw];
    [_cadenceController changeCadenceIfNeeded];

    if (useMetal) {
        [self renderTwoMetalFramesAndShowMetalView];
    } else {
        _view.metalView.enableSetNeedsDisplay = NO;
    }
}

- (void)renderTwoMetalFramesAndShowMetalView NS_AVAILABLE_MAC(10_11) {
    // The first frame will be slow to draw. The second frame will be very
    // recent to minimize jitter. For reasons I haven't understood yet it seems
    // the first frame is sometimes transparent. I haven't seen that issue with
    // the second frame yet.
    [self renderMetalFramesAndShowMetalView:2];
}

- (void)renderMetalFramesAndShowMetalView:(NSInteger)count {
    if (_useMetal) {
        DLog(@"Begin async draw %@ for %@", @(count), self);
        [_view.driver drawAsynchronouslyInView:_view.metalView completion:^(BOOL ok) {
            if (!_useMetal || _exited) {
                DLog(@"Finished async draw but metal off/exited for %@", self);
                return;
            }

            if (!ok) {
                DLog(@"Finished async draw NOT OK for %@", self);
                // Wait 10ms to avoid burning CPU if it failed because it's slow to draw the first frame.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self renderMetalFramesAndShowMetalView:count];
                });
                return;
            }

            if (count <= 1) {
                DLog(@"Finished async draw ok for %@", self);
                [self showMetalViewImmediately];
            } else {
                [self renderMetalFramesAndShowMetalView:count - 1];
            }
        }];
    }
}

- (void)showMetalViewImmediately {
    if (!_useMetal) {
        DLog(@"Declining to show metal view immediately in %@ because useMetal is NO", self);
        return;
    }
    if (_view.metalView.bounds.size.width == 0 || _view.metalView.bounds.size.height == 0) {
        DLog(@"Declining to show metal view immediately in %@ because the view's size is %@", self, NSStringFromSize(_view.metalView.bounds.size));
        return;
    }
    if (_textview == nil) {
        DLog(@"Declining to show metal view immediately in %@ because the textview is nil", self);
        return;
    }
    if (_textview.dataSource == nil) {
        DLog(@"Declining to show metal view immediately in %@ because the textview's datasource is nil", self);
        return;
    }
    if (_screen.width == 0 || _screen.height == 0) {
        DLog(@"Declining to show metal view immediately in %@ because the screen's size is %@x%@. Screen is %@",
             self, _textview.dataSource, @(_screen.width), @(_screen.height));
        return;
    }
    [self reallyShowMetalViewImmediately];
}

- (void)reallyShowMetalViewImmediately {
    DLog(@"reallyShowMetalViewImmediately");
    [_view setNeedsDisplay:YES];
    [self showMetalAndStopDrawingTextView];
    _view.metalView.enableSetNeedsDisplay = YES;
}

- (void)showMetalAndStopDrawingTextView NS_AVAILABLE_MAC(10_11) {
    // If the legacy view had been visible, hide it. Hiding it before the
    // first frame is drawn causes a flash of gray.
    DLog(@"showMetalAndStopDrawingTextView");
    _wrapper.useMetal = YES;
    _textview.suppressDrawing = YES;
    [_view setSuppressLegacyDrawing:YES];
    if (PTYScrollView.shouldDismember) {
        _view.scrollview.alphaValue = 0;
    } else {
        [self updateWrapperAlphaForMetalEnabled:YES];
    }
    [self setMetalViewAlphaValue:1];
}

- (void)updateWrapperAlphaForMetalEnabled:(BOOL)useMetal {
    if (useMetal) {
        _view.scrollview.contentView.alphaValue = _textview.shouldBeAlphaedOut ? 0.0 : 1.0;
    } else {
        _view.scrollview.contentView.alphaValue = 1;
    }
}

- (void)setMetalViewAlphaValue:(CGFloat)alphaValue {
    _view.metalView.alphaValue = alphaValue;
    [_view didChangeMetalViewAlpha];
    [self.delegate sessionDidChangeMetalViewAlphaValue:self to:alphaValue];
}

- (void)setUseMetal:(BOOL)useMetal dataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    [_view setUseMetal:useMetal dataSource:dataSource];
    if (!useMetal) {
        _textview.suppressDrawing = NO;
        [_view setSuppressLegacyDrawing:NO];
        if (PTYScrollView.shouldDismember) {
            _view.scrollview.alphaValue = 1;
        } else {
            [self updateWrapperAlphaForMetalEnabled:NO];
        }
    }
}

- (void)updateMetalDriver NS_AVAILABLE_MAC(10_11) {
    DLog(@"%@", self);
    const CGSize cellSize = CGSizeMake(_textview.charWidth, _textview.lineHeight);
    CGSize glyphSize;
    const CGFloat scale = _view.window.backingScaleFactor ?: 1;
    NSRect rect = [iTermCharacterSource boundingRectForCharactersInRange:NSMakeRange(32, 127-32)
                                                               fontTable:_textview.fontTable
                                                                   scale:scale
                                                             useBoldFont:_textview.useBoldFont
                                                           useItalicFont:_textview.useItalicFont
                                                        usesNonAsciiFont:_textview.useNonAsciiFont
                                                                 context:[PTYSession onePixelContext]];
    DLog(@"Bounding rect for %@ is %@", _textview.fontTable.asciiFont, NSStringFromRect(rect));
    CGSize asciiOffset = CGSizeZero;
    if (rect.origin.y < 0) {
        // Iosevka Light and CommitMono Nerd Font Mono are the only fonts I've found that need this.
        // Each rides *very* low in its box. The lineheight that PTYFontInfo calculates is actually too small
        // to contain the glyphs (it uses a weird algorithm that was discovered "organically").
        // There are gobs of empty pixels at the top, so we shift all its ASCII glyphs a bit so they'll
        // fit. Non-ASCII characters may take multiple parts and so can properly extend beyond their
        // cell, so we only need to think about ASCII. In other words, this hack shifts the character up
        // *in the texture* to make better use of space without using a larger glyph size.
        //
        // In a monochrome world, this is still necessary because even though glyph size and cell
        // size are no longer required to be the same, part of the glyph will be drawn outside its
        // bounds and get clipped in the texture.
        asciiOffset.height = -floor(rect.origin.y * scale);
    }
    if (iTermTextIsMonochrome() && rect.origin.x < 0) {
        // AnonymousPro has a similar problem (issue 8185), e.g. with "W".
        // There is a subtle difference, though! The monochrome code path assumes that glyphs are
        // left-aligned in their glyphSize-sized chunk of the texture. Setting the asciiOffset here
        // causes them to all be rendered a few pixels to the right so that this assumption will be
        // true. The quad is then shifted left by a corresponding amount when rendering so it ends
        // up drawn in the right place.
        //
        // When doing subpixel antialiasing, this is not an issue because it deals with multipart
        // ASCII glyphs differently. It splits them into pieces and draws them as separate instances.
        //
        // Changing the assumption that glyphs are left-aligned would be very complex, and I can't
        // afford to add more risk right now. This is less than beautiful, but it's quite safe.
        asciiOffset.width = -floor(rect.origin.x * scale);
    }
    DLog(@"Ascii offset is %@", NSStringFromSize(asciiOffset));
    if (iTermTextIsMonochrome()) {
        DLog(@"Increase glyph size for monochrome");
        // Mojave can use a glyph size larger than cell size because compositing is trivial without subpixel AA.
        glyphSize.width = round(1 + MAX(cellSize.width, NSMaxX(rect)));
        glyphSize.height = round(1 + MAX(cellSize.height, NSMaxY(rect)));
        glyphSize.width += asciiOffset.width * 2;
        glyphSize.height += asciiOffset.height * 2;
    } else {
        glyphSize = cellSize;
    }
    DLog(@"cellSize=%@ glyphSize=%@", NSStringFromSize(cellSize), NSStringFromSize(glyphSize));
    [self setMetalContextSize:glyphSize];
    if (!_metalContext) {
        DLog(@"%p Failed to allocate metal context. Disable metal and try again in 1 second.", self);
        if (_errorCreatingMetalContext) {
            DLog(@"Already have a retry queued.");
            return;
        }
        _errorCreatingMetalContext = YES;
        [self.delegate sessionUpdateMetalAllowed];
        if (!_useMetal) {
            DLog(@"Failed to create context for %@ but metal is not allowed", self);
            return;
        }
        DLog(@"Failed to create context for %@. schedule retry", self);
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf retryMetalAfterContextAllocationFailure];
        });
        return;
    }
    [_view.driver setCellSize:cellSize
       cellSizeWithoutSpacing:CGSizeMake(_textview.charWidthWithoutSpacing, _textview.charHeightWithoutSpacing)
                    glyphSize:glyphSize
                     gridSize:_screen.currentGrid.size
                  asciiOffset:asciiOffset
                        scale:_view.window.screen.backingScaleFactor
                      context:_metalContext
         legacyScrollbarWidth:self.legacyScrollbarWidth];
}

- (CGFloat)legacyScrollbarWidth {
    if (_view.scrollview.scrollerStyle != NSScrollerStyleLegacy) {
        return 0;
    }
    return NSWidth(_view.scrollview.bounds) - NSWidth(_view.scrollview.contentView.bounds);
}

- (void)retryMetalAfterContextAllocationFailure {
    DLog(@"%p It's been one second since trying to allocate a metal context failed. Try again.", self);
    if (!_errorCreatingMetalContext) {
        DLog(@"Oddly, errorCreatingMetalContext is NO");
        return;
    }
    DLog(@"%p reset error state", self);
    _errorCreatingMetalContext = NO;
    [self updateMetalDriver];
    if (_metalContext) {
        DLog(@"A metal context was allocated. Try to turn metal on for this tab.");
        [self.delegate sessionUpdateMetalAllowed];
    } else {
        DLog(@"Failed to allocate context again. A retry should have been scheduled.");
    }
}

#pragma mark - Password Management

- (BOOL)canOpenPasswordManager {
    [self sync];
    return !_screen.echoProbeIsActive;
}

- (void)enterPassword:(NSString *)password {
    [self incrementDisableFocusReporting:1];
    [_screen beginEchoProbeWithBackspace:[self backspaceData] password:password delegate:self];
}

- (NSImage *)dragImage
{
    NSImage *image = [self snapshot];
    // Dial the alpha down to 50%
    NSImage *dragImage = [[[NSImage alloc] initWithSize:[image size]] autorelease];
    [dragImage lockFocus];
    [image drawAtPoint:NSZeroPoint
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:0.5];
    [dragImage unlockFocus];
    return dragImage;
}

- (void)setPasteboard:(NSString *)pbName {
    if (pbName) {
        [_pasteboard autorelease];
        _pasteboard = [pbName copy];
        [_pbtext release];
        _pbtext = [[NSMutableData alloc] init];
    } else {
        NSPasteboard *pboard = [NSPasteboard pasteboardWithName:_pasteboard];
        [pboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
        [pboard setData:_pbtext forType:NSPasteboardTypeString];

        const BOOL wasFindPasteboard = [_pasteboard isEqual:NSPasteboardNameFind];
        [_pasteboard release];
        _pasteboard = nil;
        [_pbtext release];
        _pbtext = nil;

        if (wasFindPasteboard) {
            [[iTermFindPasteboard sharedInstance] updateObservers:self internallyGenerated:YES];
        }
    }
}

- (void)stopCoprocess
{
    [_shell stopCoprocess];
}

- (BOOL)hasCoprocess
{
    return [_shell hasCoprocess];
}

- (void)launchCoprocessWithCommand:(NSString *)command mute:(BOOL)mute {
    DLog(@"Launch coprocess with command %@. Mute=%@", command, @(mute));
    Coprocess *coprocess = [Coprocess launchedCoprocessWithCommand:command
                                                       environment:[self environmentForNewJobFromEnvironment:self.environment
                                                                                               substitutions:self.substitutions]];
    coprocess.delegate = self.weakSelf;
    coprocess.mute = mute;
    [_shell setCoprocess:coprocess];
    [_textview requestDelegateRedraw];
}

- (void)launchSilentCoprocessWithCommand:(NSString *)command
{
    [self launchCoprocessWithCommand:command mute:YES];
}

- (void)performBlockWithoutFocusReporting:(void (^NS_NOESCAPE)(void))block {
    [self incrementDisableFocusReporting:1];
    block();
    [self incrementDisableFocusReporting:-1];
}

- (void)incrementDisableFocusReporting:(NSInteger)delta {
    DLog(@"delta=%@ count %@->%@\n%@", @(delta), @(_disableFocusReporting), @(_disableFocusReporting + delta), self);
    _disableFocusReporting += delta;
    if (_disableFocusReporting == 0) {
        [self setFocused:[self textViewOrComposerIsFirstResponder]];
    }
}

- (void)setFocused:(BOOL)focused {
    DLog(@"setFocused:%@ self=%@", @(focused), self);
    if (_disableFocusReporting) {
        DLog(@"Focus reporting disabled");
        return;
    }
    if ([self.delegate sessionPasswordManagerWindowIsOpen]) {
        DLog(@"Password manager window is open");
        return;
    }
    if (focused == _focused) {
        DLog(@"No change");
        return;
    }
    if (_alertOnMarksinOffscreenSessions && [self.delegate hasMaximizedPane]) {
        DLog(@"Sync because _alertOnMarksinOffscreenSessions and maximized");
        [self sync];
    }
    if (self.isTmuxGateway) {
        DLog(@"Is tmux gateway");
        return;
    }
    _focused = focused;
    if (_screen.terminalReportFocus) {
        DLog(@"Will report focus");
        _reportingFocus = YES;
        self.lastFocusReportDate = [NSDate date];
        // This is not considered reporting because it's not in response to a remote request.
        [self writeLatin1EncodedData:[_screen.terminalOutput reportFocusGained:focused] broadcastAllowed:NO reporting:NO];
        _reportingFocus = NO;
    }
    if (focused && [self isTmuxClient]) {
        DLog(@"Tell tmux about focus change");
        [_tmuxController selectPane:self.tmuxPane];
        [self.delegate sessionDidReportSelectedTmuxPane:self];
    }
    [self.textview requestDelegateRedraw];
}

- (BOOL)wantsContentChangedNotification
{
    // We want a content change notification if it's worth doing a tail find.
    // That means the find window is open, we're not already doing a tail find,
    // and a search was performed in the find window (vs select+cmd-e+cmd-f).
    return (!_tailFindTimer &&
            !_view.findViewIsHidden &&
            [_textview findContext].substring != nil);
}

- (void)hideSession {
    [self bury];
}

- (NSString *)preferredTmuxClientName {
    id<VT100RemoteHostReading> remoteHost = [self currentHost];
    if (remoteHost) {
        return [NSString stringWithFormat:@"%@@%@", remoteHost.username, remoteHost.hostname];
    } else {
        NSString *name = [_nameController.presentationSessionTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length) {
            return name;
        }
        return @"tmux";
    }
}

- (void)setTmuxMode:(PTYSessionTmuxMode)tmuxMode {
    @synchronized ([TmuxGateway class]) {
        _tmuxMode = tmuxMode;
    }
    if (tmuxMode == TMUX_GATEWAY) {
        [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            mutableState.isTmuxGateway = (tmuxMode == TMUX_GATEWAY);
        }];
    } else if (tmuxMode == TMUX_NONE) {
        // We got here through a paused side-effect so we cvan't join.
        [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            mutableState.isTmuxGateway = NO;
        }];
    } else if (tmuxMode == TMUX_CLIENT) {
        [self setUpTmuxPipe];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reallySetTmuxMode:tmuxMode];
    });
}

- (void)reallySetTmuxMode:(PTYSessionTmuxMode)tmuxMode {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        NSString *name;
        switch (tmuxMode) {
            case TMUX_NONE:
                name = nil;
                terminal.tmuxMode = NO;
                break;
            case TMUX_GATEWAY:
                name = @"gateway";
                terminal.tmuxMode = NO;
                break;
            case TMUX_CLIENT:
                name = @"client";
                terminal.tmuxMode = YES;
                terminal.termType = _tmuxController.defaultTerminal ?: @"screen";
                [self loadTmuxProcessID];
                [self installTmuxStatusBarMonitor];
                [self installTmuxTitleMonitor];
                [self installTmuxForegroundJobMonitor];
                [self installOtherTmuxMonitors];
                [self replaceWorkingDirectoryPollerWithTmuxWorkingDirectoryPoller];
                break;
        }
        [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionTmuxRole];
    }];
}

- (void)setUpTmuxPipe {
    assert(!_tmuxClientWritePipe);
    int fds[2];
    if (pipe(fds) < 0) {
        NSString *message = [NSString stringWithFormat:@"Failed to create pipe: %s", strerror(errno)];
        DLog(@"%@", message);
        [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            [mutableState appendStringAtCursor:message];
        }];
        _tmuxClientWritePipe = nil;
        return;
    }
    {
        // Make the TaskNotifier file descriptor nonblocking.
        const int fd = fds[0];
        const int flags = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
    {
        // Make the write pipe blocking so it can provide backpressure.
        const int fd = fds[1];
        const int flags = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, flags & (~O_NONBLOCK));
    }

    _shell.readOnlyFileDescriptor = fds[0];
    [_tmuxClientWritePipe release];
    _tmuxClientWritePipe = [[NSFileHandle alloc] initWithFileDescriptor:fds[1]
                                                         closeOnDealloc:YES];
}

- (void)loadTmuxProcessID {
    if (!_tmuxController.serverIsLocal) {
        return;
    }
    NSString *command = [NSString stringWithFormat:@"display-message -t '%%%@' -p '#{pane_pid}'", @(self.tmuxPane)];
    DLog(@"Request pane PID with command %@", command);
    [_tmuxController.gateway sendCommand:command
                          responseTarget:self
                        responseSelector:@selector(didFetchTmuxPid:)
                          responseObject:nil
                                   flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)didFetchTmuxPid:(NSString *)pidString {
    if (pidString && self.tmuxMode == TMUX_CLIENT && _tmuxController.serverIsLocal) {
        NSNumber *pid = @([pidString integerValue]);
        if (pid.intValue > 0) {
            _shell.tmuxClientProcessID = pid;
            [self updateTitles];
        }
    }
}

- (void)replaceWorkingDirectoryPollerWithTmuxWorkingDirectoryPoller {
    DLog(@"replaceWorkingDirectoryPollerWithTmuxWorkingDirectoryPoller");
    _pwdPoller.delegate = nil;
    [_pwdPoller release];

    _pwdPoller = [[iTermWorkingDirectoryPoller alloc] initWithTmuxGateway:_tmuxController.gateway
                                                                    scope:self.variablesScope
                                                               windowPane:self.tmuxPane];
    _pwdPoller.delegate = self;
    [_pwdPoller poll];
}

- (void)installTmuxStatusBarMonitor {
    assert(!_tmuxStatusBarMonitor);

    if (_tmuxController.gateway.minimumServerVersion.doubleValue >= 2.9) {
        // Just use the built-in status bar for older versions of tmux because they don't support ${T:xxx} or ${E:xxx}
        _tmuxStatusBarMonitor = [[iTermTmuxStatusBarMonitor alloc] initWithGateway:_tmuxController.gateway
                                                                             scope:self.variablesScope];
        _tmuxStatusBarMonitor.active = [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:self.profile];
        if ([iTermPreferences boolForKey:kPreferenceKeyUseTmuxStatusBar] ||
            [iTermStatusBarLayout shouldOverrideLayout:self.profile[KEY_STATUS_BAR_LAYOUT]]) {
            [self setSessionSpecificProfileValues:@{ KEY_STATUS_BAR_LAYOUT: [[iTermStatusBarLayout tmuxLayoutWithController:_tmuxController
                                                                                                                      scope:nil
                                                                                                                     window:self.delegate.tmuxWindow] dictionaryValue] }];
        }
    }
}

- (void)installTmuxForegroundJobMonitor {
    if (_tmuxForegroundJobMonitor) {
        return;
    }
    if (![self shouldShowTabGraphic]) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    _tmuxForegroundJobMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:_tmuxController.gateway
                                                                          scope:self.variablesScope
                                                           fallbackVariableName:nil
                                                                         format:@"#{pane_current_command}"
                                                                         target:[NSString stringWithFormat:@"%%%@", @(self.tmuxPane)]
                                                                   variableName:iTermVariableKeySessionJob
                                                                          block:^(NSString * _Nonnull command) {
        [weakSelf setCurrentForegroundJobNameForTmux:command];
    }];
    if ([iTermAdvancedSettingsModel pollForTmuxForegroundJob]) {
        [_tmuxForegroundJobMonitor startTimerIfSubscriptionsUnsupported];
    }
    [_tmuxForegroundJobMonitor updateOnce];
}

- (void)setCurrentForegroundJobNameForTmux:(NSString *)command {
    if ([_graphicSource updateImageForJobName:command enabled:[self shouldShowTabGraphic]]) {
        [self.delegate sessionDidChangeGraphic:self shouldShow:self.shouldShowTabGraphic image:self.tabGraphic];
    }
    [self.delegate sessionJobDidChange:self];
}

- (void)tmuxWindowTitleDidChange {
    [self.tmuxForegroundJobMonitor updateOnce];
}

- (void)uninstallTmuxForegroundJobMonitor {
    if (!_tmuxForegroundJobMonitor) {
        return;
    }
    [_tmuxForegroundJobMonitor invalidate];
    [_tmuxForegroundJobMonitor release];
    _tmuxForegroundJobMonitor = nil;
}

- (iTermTmuxOptionMonitor *)tmuxForegroundJobMonitor {
    if (!self.isTmuxClient || !_tmuxController) {
        return nil;
    }
    if (_tmuxForegroundJobMonitor) {
        return _tmuxForegroundJobMonitor;
    }
    if (![self shouldShowTabGraphic]) {
        return nil;
    }
    [self installTmuxForegroundJobMonitor];
    return _tmuxForegroundJobMonitor;
}

- (void)installOtherTmuxMonitors {
    if (![_tmuxController.gateway supportsSubscriptions]) {
        return;
    }
    if (_paneIndexMonitor) {
        return;
    }
    _paneIndexMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:_tmuxController.gateway
                                                                  scope:self.variablesScope
                                                   fallbackVariableName:nil
                                                                 format:@"#{pane_index}"
                                                                 target:[NSString stringWithFormat:@"%%%@", @(self.tmuxPane)]
                                                           variableName:iTermVariableKeySessionTmuxWindowPaneIndex
                                                                  block:nil];
    [_paneIndexMonitor updateOnce];
}

// NOTE: Despite the name, this doesn't continuously monitor because that is
// too expensive. Instead, we manually poll at times when a change is likely.
- (void)installTmuxTitleMonitor {
    if (_tmuxTitleMonitor) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    _tmuxTitleMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:_tmuxController.gateway
                                                                  scope:self.variablesScope
                                                   fallbackVariableName:nil
                                                                 format:@"#{pane_title}"
                                                                 target:[NSString stringWithFormat:@"%%%@", @(self.tmuxPane)]
                                                           variableName:iTermVariableKeySessionTmuxPaneTitle
                                                                  block:^(NSString * _Nonnull title) {
        [weakSelf setTitleFromTmuxTitleMonitor:title];
    }];
    [_tmuxTitleMonitor updateOnce];
}

- (void)setTitleFromTmuxTitleMonitor:(NSString *)title {
    if (title) {
        [self setSessionSpecificProfileValues:@{ KEY_TMUX_PANE_TITLE: title ?: @""}];
        [self.delegate sessionDidUpdatePaneTitle:self];
    }
}

- (void)uninstallTmuxTitleMonitor {
    if (!_tmuxTitleMonitor) {
        return;
    }
    [_tmuxTitleMonitor invalidate];
    [_tmuxTitleMonitor release];
    _tmuxTitleMonitor = nil;
}

- (PTYSessionTmuxMode)tmuxMode {
    @synchronized ([TmuxGateway class]) {
        return _tmuxMode;
    }
}

- (void)startTmuxMode:(NSString *)dcsID {
    if (self.tmuxMode != TMUX_NONE) {
        return;
    }
    NSString *preferredTmuxClientName = [self preferredTmuxClientName];
    self.tmuxMode = TMUX_GATEWAY;
    _tmuxGateway = [[TmuxGateway alloc] initWithDelegate:self dcsID:dcsID];
    ProfileModel *model;
    Profile *profile;
    if ([iTermPreferences useTmuxProfile]) {
        model = [ProfileModel sharedInstance];
        profile = [[ProfileModel sharedInstance] tmuxProfile];
    } else {
        if (self.isDivorced) {
            model = [ProfileModel sessionsInstance];
        } else {
            model = [ProfileModel sharedInstance];
        }
        profile = self.profile;
    }
    _haveKickedOffTmux = NO;
    _tmuxController = [[TmuxController alloc] initWithGateway:_tmuxGateway
                                                   clientName:preferredTmuxClientName
                                                      profile:profile
                                                 profileModel:model];

    [self.variablesScope setValue:_tmuxController.clientName forVariableNamed:iTermVariableKeySessionTmuxClientName];
    _tmuxController.ambiguousIsDoubleWidth = _treatAmbiguousWidthAsDoubleWidth;
    _tmuxController.unicodeVersion = _unicodeVersion;

    // We intentionally don't send anything to tmux yet. We wait to get a
    // begin-end pair from it to make sure everything is cool (we have a legit
    // session) and then we start going.

    // This is to fix issue 4429, where we used to send a command immediately
    // and tmux would terminate immediately and we would spam the user's
    // command line.
    //
    // Tmux always prints something when you first attach. It's a notification, a response, or an
    // error. The options I've considered are:
    //
    // tmux -CC with or without an existing session prints this unsolicited:
    //    %begin time 1 0
    //    %end time 1 0
    //    %window-add @id

    // tmux -CC attach with no existing session prints this unsolicited;
    // %begin time 1 0
    // no sessions
    // %error time

    // tmux -CC attach with an existing session prints this unsolicited:
    // %begin time 1 0
    // %end time 1 0

    // One of tmuxInitialCommandDidCompleteSuccessfully: or
    // tmuxInitialCommandDidFailWithError: will be called on the first %end or
    // %error, respectively.
    [self printTmuxMessage:@"** tmux mode started **"];
    [self printTmuxMessage:@""];
    [self printTmuxMessage:@"Command Menu"];
    [self printTmuxMessage:@"----------------------------"];
    [self printTmuxMessage:@"esc    Detach cleanly."];
    [self printTmuxMessage:@"  X    Force-quit tmux mode."];
    [self printTmuxMessage:@"  L    Toggle logging."];
    [self printTmuxMessage:@"  C    Run tmux command."];

    if ([iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession]) {
        _tmuxController.initialWindowHint = self.view.window.frame;
        _hideAfterTmuxWindowOpens = YES;
    }
}

- (BOOL)isTmuxClient {
    return self.tmuxMode == TMUX_CLIENT;
}

- (BOOL)isTmuxGateway {
    return self.tmuxMode == TMUX_GATEWAY;
}

- (void)tmuxDetach {
    if (self.tmuxMode != TMUX_GATEWAY) {
        return;
    }
    [self printTmuxMessage:@"Detaching..."];
    [_tmuxGateway detach];
}

- (void)setTmuxPane:(int)windowPane {
    [self.variablesScope setValue:@(windowPane) forVariableNamed:iTermVariableKeySessionTmuxWindowPane];
    self.tmuxMode = TMUX_CLIENT;
    [_shell registerTmuxTask];
}

- (int)tmuxPane {
    return [[self.variablesScope valueForVariableName:iTermVariableKeySessionTmuxWindowPane] intValue];
}

- (PTYSession *)tmuxGatewaySession {
    if (self.isTmuxGateway) {
        return self;
    }
    if (!self.isTmuxClient) {
        return nil;
    }
    return (PTYSession *)self.tmuxController.gateway.delegate;
}

- (void)toggleTmuxZoom {
    [_tmuxController toggleZoomForPane:self.tmuxPane];
}

- (void)resizeFromArrangement:(NSDictionary *)arrangement {
    [self setSize:VT100GridSizeMake([[arrangement objectForKey:SESSION_ARRANGEMENT_COLUMNS] intValue],
                                    [[arrangement objectForKey:SESSION_ARRANGEMENT_ROWS] intValue])];
}

- (BOOL)isCompatibleWith:(PTYSession *)otherSession
{
    if (self.tmuxMode != TMUX_CLIENT && otherSession.tmuxMode != TMUX_CLIENT) {
        // Non-clients are always compatible
        return YES;
    } else if (self.tmuxMode == TMUX_CLIENT && otherSession.tmuxMode == TMUX_CLIENT) {
        // Clients are compatible with other clients from the same controller.
        return (_tmuxController == otherSession.tmuxController);
    } else {
        // Clients are never compatible with non-clients.
        return NO;
    }
}

- (NSString *)regularExpressonForNonLowPrecisionSmartSelectionRulesCombined {
    NSArray<NSDictionary *> *rules = [iTermProfilePreferences objectForKey:KEY_SMART_SELECTION_RULES
                                                                 inProfile:self.profile];
    if (!rules) {
        rules = [SmartSelectionController defaultRules];
    }
    NSArray<NSString *> *regexes = [rules mapWithBlock:^id _Nullable(NSDictionary * _Nonnull rule) {
        const double precision = [SmartSelectionController precisionInRule:rule];
        if (precision < SmartSelectionNormalPrecision) {
            return  nil;
        }
        NSString *bare = [SmartSelectionController regexInRule:rule];
        NSError *error = nil;
        NSRegularExpression *expr = [[NSRegularExpression alloc] initWithPattern:bare options:0 error:&error];
        if (error || !expr) {
            return nil;
        }
        [expr release];
        return [NSString stringWithFormat:@"(?:%@)", bare];
    }];
    return [regexes componentsJoinedByString:@"|"];
}

- (VT100GridCoordRange)smartSelectionRangeAt:(VT100GridCoord)coord {
    if (coord.x < 0 || coord.y < 0 || coord.x >= _screen.width || coord.y >= _screen.height) {
        return VT100GridCoordRangeMake(0, 0, 0, 0);
    }
    VT100GridWindowedRange range;
    [_textview smartSelectAtX:coord.x
                            y:coord.y + [_screen numberOfScrollbackLines]
                           to:&range
             ignoringNewlines:NO
               actionRequired:NO
              respectDividers:NO];
    return [_textview rangeByTrimmingNullsFromRange:range.coordRange trimSpaces:YES];
}

- (void)addNoteAtCursor {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        PTYAnnotation *note = [[[PTYAnnotation alloc] init] autorelease];
        VT100GridCoordRange rangeAtCursor =
        [self smartSelectionRangeAt:VT100GridCoordMake(_screen.cursorX - 1,
                                                       _screen.cursorY - 1)];
        VT100GridCoordRange rangeBeforeCursor =
        [self smartSelectionRangeAt:VT100GridCoordMake(_screen.cursorX - 2,
                                                       _screen.cursorY - 1)];
        VT100GridCoordRange rangeAfterCursor =
        [self smartSelectionRangeAt:VT100GridCoordMake(_screen.cursorX,
                                                       _screen.cursorY - 1)];
        if (VT100GridCoordRangeLength(rangeAtCursor, _screen.width) > 0) {
            [_screen addNote:note inRange:rangeAtCursor focus:YES];
        } else if (VT100GridCoordRangeLength(rangeAfterCursor, _screen.width) > 0) {
            [_screen addNote:note inRange:rangeAfterCursor focus:YES];
        } else if (VT100GridCoordRangeLength(rangeBeforeCursor, _screen.width) > 0) {
            [_screen addNote:note inRange:rangeBeforeCursor focus:YES];
        } else {
            int y = _screen.cursorY - 1 + [_screen numberOfScrollbackLines];
            [_screen addNote:note
                     inRange:VT100GridCoordRangeMake(0, y, _screen.width, y)
                       focus:YES];
        }
    }];
}

- (void)textViewToggleAnnotations {
    VT100GridCoordRange range =
    VT100GridCoordRangeMake(0,
                            0,
                            _screen.width,
                            _screen.height + [_screen numberOfScrollbackLines]);
    NSArray<id<PTYAnnotationReading>> *annotations = [_screen annotationsInRange:range];
    BOOL anyNoteIsVisible = NO;
    for (id<PTYAnnotationReading> annotation in annotations) {
        PTYNoteViewController *note = (PTYNoteViewController *)annotation.delegate;
        if (!note.view.isHidden) {
            anyNoteIsVisible = YES;
            break;
        }
    }
    for (id<PTYAnnotationReading> annotation in annotations) {
        PTYNoteViewController *note = (PTYNoteViewController *)annotation.delegate;
        [note setNoteHidden:anyNoteIsVisible];
    }
    [self.delegate sessionUpdateMetalAllowed];
    [self updateWrapperAlphaForMetalEnabled:_view.useMetal];
}

- (void)textViewDidAddOrRemovePorthole {
    [self.delegate sessionUpdateMetalAllowed];
    [self updateWrapperAlphaForMetalEnabled:_view.useMetal];
}

- (NSString *)textViewCurrentSSHSessionName {
    if (!_conductor) {
        return nil;
    }
    return _conductor.sshIdentity.description;
}

- (void)textViewDisconnectSSH {
    if (!_conductor.framing) {
        NSString *title = [NSString stringWithFormat:@"Advanced SSH features are unavailable because Python %@ or later was not found on %@", [iTermConductor minimumPythonVersionForFramer], _conductor.sshIdentity.hostname ?: @"remote host"];
        [iTermWarning showWarningWithTitle:title
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Can’t Disconnect"
                                    window:self.view.window];
        return;
    }
    [_conductor quit];
}


- (void)highlightMarkOrNote:(id<IntervalTreeImmutableObject>)obj {
    if ([obj isKindOfClass:[iTermMark class]]) {
        BOOL hasErrorCode = NO;
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)obj;
            hasErrorCode = mark.code != 0;
            if (mark.command != nil) {
                [self selectCommandWithMarkIfSafe:mark];
            } else {
                [self selectCommandWithMark:nil];
            }
        }
        [_textview highlightMarkOnLine:VT100GridRangeMax([_screen lineNumberRangeOfInterval:obj.entry.interval])
                          hasErrorCode:hasErrorCode];
    } else {
        id<PTYAnnotationReading> annotation = [PTYAnnotation castFrom:obj];
        if (annotation) {
            id<PTYAnnotationDelegate> note = annotation.delegate;
            [note setNoteHidden:NO];
            [note highlight];
        }
    }
}

- (void)nextMark {
    if ([_modeHandler nextMark]) {
        return;
    }
    [self nextMarkOrNote:NO];
}

- (void)nextAnnotation {
    [self nextMarkOrNote:YES];
}

- (void)previousMark {
    if ([_modeHandler previousMark]) {
        return;
    }
    [self previousMarkOrNote:NO];
}

- (void)previousAnnotation {
    [self previousMarkOrNote:YES];
}

- (void)previousMarkOrNote:(BOOL)annotationsOnly {
    NSArray *objects = nil;
    if (self.currentMarkOrNotePosition == nil) {
        if (annotationsOnly) {
            objects = [_screen lastAnnotations];
        } else {
            objects = [_screen lastMarks];
        }
    } else {
        if (annotationsOnly) {
            objects = [_screen annotationsBefore:self.currentMarkOrNotePosition];
        } else {
            objects = [_screen marksBefore:self.currentMarkOrNotePosition];
        }
        if (!objects.count) {
            if (annotationsOnly) {
                objects = [_screen lastAnnotations];
            } else {
                objects = [_screen lastMarks];
            }
            if (objects.count) {
                [_textview beginFlash:kiTermIndicatorWrapToBottom];
            }
        }
    }
    if (objects.count) {
        id<IntervalTreeObject> obj = objects[0];
        self.currentMarkOrNotePosition = obj.entry.interval;
        VT100GridRange range = [_screen lineNumberRangeOfInterval:self.currentMarkOrNotePosition];
        [_textview scrollLineNumberRangeIntoView:range];
        for (obj in objects) {
            [self highlightMarkOrNote:obj];
        }
    }
}

- (BOOL)markIsNavigable:(id<iTermMark>)mark {
    return ([mark isKindOfClass:[VT100ScreenMark class]] ||
            [mark isKindOfClass:[PTYAnnotation class]]);
}

- (void)nextMarkOrNote:(BOOL)annotationsOnly {
    NSArray<id<IntervalTreeImmutableObject>> *objects = nil;
    if (self.currentMarkOrNotePosition == nil) {
        if (annotationsOnly) {
            objects = [_screen firstAnnotations];
        } else {
            objects = [_screen firstMarks];
        }
    } else {
        if (annotationsOnly) {
            objects = [_screen annotationsAfter:self.currentMarkOrNotePosition];
        } else {
            objects = [_screen marksAfter:self.currentMarkOrNotePosition];
        }
        if (!objects.count) {
            if (annotationsOnly) {
                objects = [_screen firstAnnotations];
            } else {
                objects = [_screen firstMarks];
            }
            if (objects.count) {
                [_textview beginFlash:kiTermIndicatorWrapToTop];
            }
        }
    }
    if (objects.count) {
        id<IntervalTreeImmutableObject> obj = objects[0];
        self.currentMarkOrNotePosition = obj.entry.interval;
        VT100GridRange range = [_screen lineNumberRangeOfInterval:self.currentMarkOrNotePosition];
        [_textview scrollLineNumberRangeIntoView:range];
        for (obj in objects) {
            [self highlightMarkOrNote:obj];
        }
    }
}

- (void)scrollToMark:(id<iTermMark>)mark {
    if ([_screen containsMark:mark]) {
        VT100GridRange range = [_screen lineNumberRangeOfInterval:mark.entry.interval];
        [_textview scrollLineNumberRangeIntoView:range];
        [self highlightMarkOrNote:mark];
    }
}

- (void)scrollToMarkWithGUID:(NSString *)guid {
    id<VT100ScreenMarkReading> mark = [_screen namedMarkWithGUID:guid];
    if (mark) {
        [self scrollToMark:mark];
    }
}

- (void)setCurrentHost:(id<VT100RemoteHostReading>)remoteHost {
    [_currentHost autorelease];
    _currentHost = [remoteHost retain];
    [self.variablesScope setValue:remoteHost.hostname forVariableNamed:iTermVariableKeySessionHostname];
    [self.variablesScope setValue:remoteHost.username forVariableNamed:iTermVariableKeySessionUsername];
    [_delegate sessionCurrentHostDidChange:self];
}

- (id<VT100RemoteHostReading>)currentHost {
    if (!_currentHost) {
        // This is used when a session gets restored since _currentHost doesn't get persisted (and
        // perhaps other edge cases I haven't found--it used to be done every time before the
        // _currentHost ivar existed).
        _currentHost = [[_screen remoteHostOnLine:[_screen numberOfLines]] retain];
        if (_currentHost) {
            [self.variablesScope setValue:_currentHost.hostname forVariableNamed:iTermVariableKeySessionHostname];
            [self.variablesScope setValue:_currentHost.username forVariableNamed:iTermVariableKeySessionUsername];
        }
    }
    return _currentHost;
}

#pragma mark tmux gateway delegate methods
// TODO (also, capture and throw away keyboard input)

- (NSString *)tmuxOwningSessionGUID {
    return self.guid;
}

- (void)tmuxDidOpenInitialWindows {
    if (_hideAfterTmuxWindowOpens) {
        _hideAfterTmuxWindowOpens = NO;
        [self hideSession];

        static NSString *const kAutoBurialKey = @"NoSyncAutoBurialReveal";
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kAutoBurialKey]) {
            [[iTermNotificationController sharedInstance] notify:@"Session Buried"
                                                 withDescription:@"It can be restored by detaching from tmux, or from the Sessions > Buried Sessions menu."];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAutoBurialKey];
        }
    }
}

- (BOOL)tmuxUpdateLayoutForWindow:(int)windowId
                           layout:(NSString *)layout
                    visibleLayout:(NSString *)visibleLayout
                           zoomed:(NSNumber *)zoomed
                             only:(BOOL)only {
    DLog(@"tmuxUpdateLayoutForWindow:%@ layout:%@ zoomed:%@ only:%@",
         @(windowId), layout, zoomed, @(only));
    PTYTab *tab = [_tmuxController window:windowId];
    if (!tab) {
        DLog(@"* NO TAB, DO NOTHING");
        return NO;
    }
    const BOOL result = [_tmuxController setLayoutInTab:tab
                                               toLayout:layout
                                          visibleLayout:visibleLayout
                                                 zoomed:zoomed];
    if (result && only) {
        [_tmuxController adjustWindowSizeIfNeededForTabs:@[ tab ]];
    }
    return result;
}

- (void)tmuxWindowAddedWithId:(int)windowId {
    if (![_tmuxController window:windowId]) {
        [_tmuxController openWindowWithId:windowId
                              intentional:NO
                                  profile:[_tmuxController profileForWindow:self.delegate.tmuxWindow]];
    }
    [_tmuxController windowsChanged];
}

- (void)tmuxWindowClosedWithId:(int)windowId
{
    PTYTab *tab = [_tmuxController window:windowId];
    if (tab) {
        [[tab realParentWindow] removeTab:tab];
    }
    [_tmuxController windowsChanged];
}

- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName {
    PTYSession *representativeSession = [[_tmuxController sessionsInWindow:windowId] firstObject];
    [representativeSession.delegate sessionDidChangeTmuxWindowNameTo:newName];
    [_tmuxController windowWasRenamedWithId:windowId to:newName];
}

- (void)tmuxInitialCommandDidCompleteSuccessfully {
    // This kicks off a chain reaction that leads to windows being opened.
    if (!_haveKickedOffTmux) {
        // In tmux 1.9+ this happens before `tmuxSessionsChanged`.
        [self kickOffTmux];
    }
}

// When guessVersion finishes, if you have called openWindowsInitial, then windows will actually get
// opened. Initial window opening is always blocked on establishing the server version.
- (void)kickOffTmux {
    _haveKickedOffTmux = YES;
    [_tmuxController sendControlC];
    [_tmuxController ping];
    [_tmuxController validateOptions];
    [_tmuxController checkForUTF8];
    [_tmuxController loadDefaultTerminal];
    [_tmuxController loadKeyBindings];
    [_tmuxController exitCopyMode];
    [_tmuxController guessVersion];  // NOTE: This kicks off more stuff that depends on knowing the version number.
}

- (void)tmuxInitialCommandDidFailWithError:(NSString *)error {
    // Let the user know what went wrong. Do it async because this runs as a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self printTmuxMessage:[NSString stringWithFormat:@"tmux failed with error: “%@”", error]];
    });
}

- (void)tmuxPrintLine:(NSString *)line {
    DLog(@"%@", line);
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState appendStringAtCursor:line];
        [mutableState appendCarriageReturnLineFeed];
    }];
}

- (void)tmuxGatewayDidTimeOut {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Force Detach?";
    alert.informativeText = @"Tmux is not responding. Would you like to force detach?";
    [alert addButtonWithTitle:@"Detach"];
    [alert addButtonWithTitle:@"Cancel"];
    NSWindow *window = self.view.window;
    NSInteger button;
    if (window) {
        button = [alert runSheetModalForWindow:window];
    } else {
        button = [alert runModal];
    }
    if (button == NSAlertFirstButtonReturn) {
        [_tmuxGateway forceDetach];
    }
}

- (void)tmuxActiveWindowPaneDidChangeInWindow:(int)windowID toWindowPane:(int)paneID {
    [_tmuxController activeWindowPaneDidChangeInWindow:windowID toWindowPane:paneID];
}

- (void)tmuxSessionWindowDidChangeTo:(int)windowID {
    [_tmuxController activeWindowDidChangeTo:windowID];
}

- (BOOL)tmuxGatewayShouldForceDetach {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Force Detach?";
    alert.informativeText = @"A previous detach request has not yet been honored. Force detach?";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSWindow *window = self.view.window;
    NSInteger button;
    if (window) {
        button = [alert runSheetModalForWindow:window];
    } else {
        button = [alert runModal];
    }
    return button == NSAlertFirstButtonReturn;
}

- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow {
    return _delegate.realParentWindow;
}

- (void)tmuxHostDisconnected:(NSString *)dcsID {
    _hideAfterTmuxWindowOpens = NO;

    if ([iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession] &&
        [[[iTermBuriedSessions sharedInstance] buriedSessions] containsObject:self]) {
        // Do this before detaching because it may be the only tab in a hotkey window. If all the
        // tabs close the window is destroyed and it breaks the reference from iTermProfileHotkey.
        // See issue 7384.
        [[iTermBuriedSessions sharedInstance] restoreSession:self];
    }

    [_tmuxController detach];
    // Autorelease the gateway because it called this function so we can't free
    // it immediately.
    [_tmuxGateway autorelease];
    _tmuxGateway = nil;
    [_tmuxController release];
    _tmuxController = nil;
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState appendStringAtCursor:@"Detached"];
        [mutableState appendCarriageReturnLineFeed];
        [terminal.parser forceUnhookDCS:dcsID];
    }];
    self.tmuxMode = TMUX_NONE;
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionTmuxClientName];
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionTmuxPaneTitle];
}

- (void)tmuxCannotSendCharactersInSupplementaryPlanes:(NSString *)string windowPane:(int)windowPane {
    PTYSession *session = [_tmuxController sessionForWindowPane:windowPane];
    [session.naggingController tmuxSupplementaryPlaneErrorForCharacter:string];
}

- (void)tmuxSetSecureLogging:(BOOL)secureLogging {
    _tmuxSecureLogging = secureLogging;
}

- (void)tmuxWriteString:(NSString *)string {
    if (_exited) {
        return;
    }
    if (_tmuxSecureLogging) {
        DLog(@"Write to tmux.");
    } else {
        DLog(@"Write to tmux: \"%@\"", string);
    }
    if (_tmuxGateway.tmuxLogging) {
        [self printTmuxMessage:[@"> " stringByAppendingString:string]];
    }
    if (_conductor && !_exited) {
        // Running tmux inside an ssh client takes this path
        [_conductor sendKeys:[string dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [self writeTaskImpl:string encoding:NSUTF8StringEncoding forceEncoding:YES canBroadcast:NO reporting:NO];
    }
}

+ (dispatch_queue_t)tmuxQueue {
    static dispatch_queue_t tmuxQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tmuxQueue = dispatch_queue_create("com.iterm2.tmuxReadTask", 0);
    });
    return tmuxQueue;
}

// This is called on the main thread when %output is parsed.
- (void)tmuxReadTask:(NSData *)data windowPane:(int)wp latency:(NSNumber *)latency {
    if (latency) {
        [_tmuxController setCurrentLatency:latency.doubleValue forPane:wp];
    }
    [[_tmuxController sessionForWindowPane:wp] handleTmuxData:data];
}

- (void)handleTmuxData:(NSData *)data {
    if (_exited) {
        return;
    }
    if (_logging.style == iTermLoggingStyleRaw) {
        [_logging logData:data];
    }

    // Send the bytes from %output in to the write end of a pipe. The data will come out
    // iTermTmuxJobManager.fd, which TaskRegister selects on. The purpose of this pipe is to
    // let tmux provide backpressure to the pty. In the old days, this would call -threadedReadTask:
    // on the tmux queue. threadedReadTask: is meant to be called on the TaskNotifier queue and it
    // will block if there are too many tokens outstanding. That is an effective mechanism to
    // provide backpressure. By dispatching onto the tmuxQueue, infinite data could be buffered by
    // GCD, breaking the backpressure mechanism. It is unfortunate that all tmux data must make
    // two passes through TaskNotifier (once as `%output blah blah` and a second time as `blah blah`)
    // but the alternative is unbounded latency. We still do the write on tmuxQueue because we
    // don't want to block the main queue. GCD can still buffer here, but it's OK because
    // TaskNotifier has a chance to get its queue blocked when it reads the data. That limits the
    // rate that this can write, since it can only write after a %output is read.
    __weak NSFileHandle *handle = _tmuxClientWritePipe;
    dispatch_async([[self class] tmuxQueue], ^{
        @try {
            [handle writeData:data];
        } @catch (NSException *exception) {
            DLog(@"%@ while writing to tmux pipe", exception);
        }
    });
}

- (void)tmuxSessionPasteDidChange:(NSString *)pasteBufferName {
    if ([iTermPreferences boolForKey:kPreferenceKeyTmuxSyncClipboard]) {
        [_tmuxController copyBufferToLocalPasteboard:pasteBufferName];
    } else {
        [[[[iTermController sharedInstance] currentTerminal] currentSession] askToMirrorTmuxPasteBuffer];
    }
}

- (void)askToMirrorTmuxPasteBuffer {
    [_naggingController tmuxDidUpdatePasteBuffer];



}

- (void)tmuxWindowPaneDidPause:(int)wp notification:(BOOL)notification {
    PTYSession *session = [_tmuxController sessionForWindowPane:wp];
    [session setTmuxPaused:YES allowAutomaticUnpause:notification];
}

- (void)setTmuxPaused:(BOOL)paused allowAutomaticUnpause:(BOOL)allowAutomaticUnpause {
    if (_tmuxPaused == paused) {
        return;
    }
    _tmuxPaused = paused;
    if (paused) {
        _tmuxTTLHasThresholds = NO;
        [self.tmuxController didPausePane:self.tmuxPane];
        if (allowAutomaticUnpause && [iTermPreferences boolForKey:kPreferenceKeyTmuxUnpauseAutomatically]) {
            __weak __typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf setTmuxPaused:NO allowAutomaticUnpause:YES];
            });
            return;
        }
        [self showTmuxPausedAnnouncement:allowAutomaticUnpause];
    } else {
        [self unpauseTmux];
    }
}

- (void)showTmuxPausedAnnouncement:(BOOL)notification {
    NSString *title;
    if (notification) {
        title = @"tmux paused this session because too much output was buffered.";
    } else {
        title = @"Session paused.";
    }

    [self dismissAnnouncementWithIdentifier:PTYSessionAnnouncementIdentifierTmuxPaused];
    __weak __typeof(self) weakSelf = self;
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"_Unpause", @"_Settings" ]
                                                completion:^(int selection) {
        switch (selection) {
            case 0:
                [weakSelf setTmuxPaused:NO allowAutomaticUnpause:YES];
                break;
            case 1:
                [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyTmuxPauseModeAgeLimit];
                [weakSelf showTmuxPausedAnnouncement:notification];
                break;
        }
    }];
    [self dismissAnnouncementWithIdentifier:PTYSessionAnnouncementIdentifierTmuxPaused];
    [self removeAnnouncementWithIdentifier:PTYSessionAnnouncementIdentifierTmuxPaused];
    [self queueAnnouncement:announcement identifier:PTYSessionAnnouncementIdentifierTmuxPaused];
}

- (void)setTmuxHistory:(NSArray<NSData *> *)history
            altHistory:(NSArray<NSData *> *)altHistory
                 state:(NSDictionary *)state {
    __weak __typeof(self) weakSelf = self;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [weakSelf reallySetTmuxHistory:history
                            altHistory:altHistory
                                 state:state
                              terminal:terminal
                          mutableState:mutableState];
    }];
}

- (void)reallySetTmuxHistory:(NSArray<NSData *> *)history
                  altHistory:(NSArray<NSData *> *)altHistory
                       state:(NSDictionary *)state
                    terminal:(VT100Terminal *)terminal
                mutableState:(VT100ScreenMutableState *)mutableState {
    [terminal resetForTmuxUnpause];
    [self clearScrollbackBuffer];
    [mutableState setHistory:history];
    [mutableState setAltScreen:altHistory];
    [self setTmuxState:state];
    _view.scrollview.ptyVerticalScroller.userScroll = NO;
}

- (void)toggleTmuxPausePane {
    if (_tmuxPaused) {
        [self setTmuxPaused:NO allowAutomaticUnpause:YES];
    } else {
        [_tmuxController pausePanes:@[ @(self.tmuxPane) ]];
    }
}

- (void)setTmuxState:(NSDictionary *)state {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        mutableState.tmuxState = state;
    }];
}

- (void)unpauseTmux {
    [self dismissAnnouncementWithIdentifier:PTYSessionAnnouncementIdentifierTmuxPaused];
    [self unzoomIfPossible];
    [_tmuxController unpausePanes:@[ @(self.tmuxPane) ]];
}

- (void)pauseTmux {
    [_tmuxController pausePanes:@[ @(self.tmuxPane) ]];
}

- (void)tmuxSessionChanged:(NSString *)sessionName sessionId:(int)sessionId {
    [_tmuxController sessionChangedTo:sessionName sessionId:sessionId];
    if (!_haveKickedOffTmux) {
        // Tell the tmux controller we want to open initial windows after version guessing finishes.
        [_tmuxController openWindowsInitial];
        // In tmux 1.8, this happens before `tmuxInitialCommandDidCompleteSuccessfully`.
        [self kickOffTmux];
    }
}

- (void)tmuxSessionsChanged {
    [_tmuxController sessionsChanged];
}

- (void)tmuxWindowsDidChange
{
    [_tmuxController windowsChanged];
}

- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName
{
    [_tmuxController session:sessionId renamedTo:newName];
}

- (VT100GridSize)tmuxClientSize {
    if (!_delegate) {
        DLog(@"No delegate so use saved grid size %@", VT100GridSizeDescription(_savedGridSize));
        return _savedGridSize;
    }
    DLog(@"Get size from delegate %@, controller tmuxController %@, window %@", _delegate,
         _tmuxController, @(self.delegate.tmuxWindow));
    return [_delegate sessionTmuxSizeWithProfile:[_tmuxController profileForWindow:self.delegate.tmuxWindow]];
}

- (NSInteger)tmuxNumberOfLinesOfScrollbackHistory {
    Profile *profile = [_tmuxController profileForWindow:self.delegate.tmuxWindow];
    if ([iTermPreferences useTmuxProfile]) {
        profile = [[ProfileModel sharedInstance] tmuxProfile];
    }
    if ([profile[KEY_UNLIMITED_SCROLLBACK] boolValue]) {
        // 10M is close enough to infinity to be indistinguishable.
        return 10 * 1000 * 1000;
    } else {
        return [profile[KEY_SCROLLBACK_LINES] integerValue];
    }
}

- (void)tmuxDoubleAttachForSessionGUID:(NSString *)sessionGUID {
    NSArray<NSString *> *actions = @[ @"OK", @"Reveal", @"Force Detach Other" ];
    TmuxController *controller = [[TmuxControllerRegistry sharedInstance] tmuxControllerWithSessionGUID:sessionGUID];
    if (!controller) {
        actions = @[ @"OK" ];
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"This instance of iTerm2 is already attached to this session"
                               actions:actions
                             accessory:nil
                            identifier:@"AlreadyAttachedToTmuxSession"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Cannot Attach"
                                window:self.view.window];
    switch (selection) {
        case kiTermWarningSelection0:
            return;
        case kiTermWarningSelection1:
            break;
        case kiTermWarningSelection2:
            [controller.gateway forceDetach];
            return;
        default:
            assert(NO);
    }

    PTYSession *aSession =
    [[controller.clientSessions sortedArrayUsingComparator:^NSComparisonResult(PTYSession *s1, PTYSession *s2) {
        return [s1.guid compare:s2.guid];
    }] firstObject];

    if (!aSession) {
        aSession = [PTYSession castFrom:controller.gateway.delegate];
    }
    if (!aSession) {
        iTermApplicationDelegate *delegate = [iTermApplication.sharedApplication delegate];
        [delegate openDashboard:nil];
        return;
    }
    [aSession reveal];
}

- (void)tmuxWillKillWindow:(NSNotification *)notification {
    if ([self.delegate tmuxWindow] == [notification.object intValue]) {
        _tmuxWindowClosingByClientRequest = YES;
    }
}

#pragma mark PTYTextViewDelegate

- (BOOL)isPasting {
    return _pasteHelper.isPasting;
}

- (void)queueKeyDown:(NSEvent *)event {
    [_pasteHelper enqueueEvent:event];
}

- (BOOL)event:(NSEvent *)event matchesPattern:(ITMKeystrokePattern *)pattern {
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }
    NSMutableArray *actualModifiers = [NSMutableArray array];
    if (event.it_modifierFlags & NSEventModifierFlagControl) {
        [actualModifiers addObject:@(ITMModifiers_Control)];
    }
    if (event.it_modifierFlags & NSEventModifierFlagOption) {
        [actualModifiers addObject:@(ITMModifiers_Option)];
    }
    if (event.it_modifierFlags & NSEventModifierFlagCommand) {
        [actualModifiers addObject:@(ITMModifiers_Command)];
    }
    if (event.it_modifierFlags & NSEventModifierFlagShift) {
        [actualModifiers addObject:@(ITMModifiers_Shift)];
    }
    if (event.it_modifierFlags & NSEventModifierFlagFunction) {
        [actualModifiers addObject:@(ITMModifiers_Function)];
    }
    if (event.it_modifierFlags & NSEventModifierFlagNumericPad) {
        [actualModifiers addObject:@(ITMModifiers_Numpad)];
    }
    for (NSInteger i = 0; i < pattern.requiredModifiersArray_Count; i++) {
        ITMModifiers modifier = [pattern.requiredModifiersArray valueAtIndex:i];
        if (![actualModifiers containsObject:@(modifier)]) {
            return NO;
        }
    }
    for (NSInteger i = 0; i < pattern.forbiddenModifiersArray_Count; i++) {
        ITMModifiers modifier = [pattern.forbiddenModifiersArray valueAtIndex:i];
        if ([actualModifiers containsObject:@(modifier)]) {
            return NO;
        }
    }

    // All necessary conditions are satisifed. Now find one that is sufficient.
    for (NSInteger i = 0; i < pattern.keycodesArray_Count; i++) {
        if (event.keyCode == [pattern.keycodesArray valueAtIndex:i]) {
            return YES;
        }
    }
    for (NSString *characters in pattern.charactersArray) {
        if ([event.characters isEqualToString:characters]) {
            return YES;
        }
    }
    for (NSString *charactersIgnoringModifiers in pattern.charactersIgnoringModifiersArray) {
        if ([event.charactersIgnoringModifiers isEqualToString:charactersIgnoringModifiers]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)keystrokeIsFilteredByMonitor:(NSEvent *)event {
    for (NSString *identifier in _keyboardFilterSubscriptions) {
        ITMNotificationRequest *request = _keyboardFilterSubscriptions[identifier];
        for (ITMKeystrokePattern *pattern in request.keystrokeFilterRequest.patternsToIgnoreArray) {
            if ([self event:event matchesPattern:pattern]) {
                return YES;
            }
        }
        // Prior to 1.17, the filter monitor used keystrokeMonitorRequest instead of keystrokeFilterRequest.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (ITMKeystrokePattern *pattern in request.keystrokeMonitorRequest.patternsToIgnoreArray) {
#pragma clang diagnostic pop
            if ([self event:event matchesPattern:pattern]) {
                return YES;
            }
        }
    }
    return NO;
}

- (VT100SyncResult)textViewWillRefresh {
    return [self syncCheckingTriggers:VT100ScreenTriggerCheckTypePartialLines
                        resetOverflow:YES];
}

- (VT100ScreenState *)screenSwitchToSharedState {
    return [_screen switchToSharedState];
}

- (void)screenRestoreState:(VT100ScreenState *)state {
    [_screen restoreState:state];
    _textview.colorMap = state.colorMap;
}

- (VT100MutableScreenConfiguration *)screenConfiguration {
    [self updateConfigurationFields];
    return _config;
}

- (void)screenSync:(VT100ScreenMutableState *)mutableState {
    const VT100SyncResult result = [self syncCheckingTriggers:VT100ScreenTriggerCheckTypeNone
                                                resetOverflow:NO
                                                 mutableState:mutableState];
    if (result.namedMarksChanged) {
        [[[[iTermNamedMarksDidChangeNotification alloc] initWithSessionGuid:self.guid] autorelease] post];
    }
}

- (void)screenSyncExpect:(VT100ScreenMutableState *)mutableState {
    const BOOL expectWasDirty = _expect.dirty;
    [_expect resetDirty];
    if (expectWasDirty) {
        [mutableState updateExpectFrom:_expect];
    }
}

- (void)sync {
    DLog(@"sync\n%@", [NSThread callStackSymbols]);
    [self syncCheckingTriggers:VT100ScreenTriggerCheckTypeNone
                 resetOverflow:NO];
}

- (void)syncCheckingTriggers:(VT100ScreenTriggerCheckType)checkTriggers {
    DLog(@"syncCheckingTriggers:%@", @(checkTriggers));
    [self syncCheckingTriggers:checkTriggers resetOverflow:NO];
}

// Only main-thread-initiated syncs take this route.
- (VT100SyncResult)syncCheckingTriggers:(VT100ScreenTriggerCheckType)checkTriggers
                          resetOverflow:(BOOL)resetOverflow {
    DLog(@"syncCheckingTriggers:%@ resetOverflow:%@ %@", @(checkTriggers), @(resetOverflow), self);
    __block VT100SyncResult result = { 0 };
    [_screen performLightweightBlockWithJoinedThreads:^(VT100ScreenMutableState *mutableState) {
        DLog(@"lightweight block running for %@", self);
        result = [self syncCheckingTriggers:checkTriggers
                              resetOverflow:resetOverflow
                               mutableState:mutableState];
    }];
    if (result.namedMarksChanged) {
        [[[[iTermNamedMarksDidChangeNotification alloc] initWithSessionGuid:self.guid] autorelease] post];
    }
    return result;
}

// This is a funnel that all syncs go through.
- (VT100SyncResult)syncCheckingTriggers:(VT100ScreenTriggerCheckType)checkTriggers
                          resetOverflow:(BOOL)resetOverflow
                           mutableState:(VT100ScreenMutableState *)mutableState {
    DLog(@"syncCheckingTriggers:%@ resetOverflow:%@ mutableState:%@ self:%@",
         @(checkTriggers), @(resetOverflow), mutableState, self);
    [self updateConfigurationFields];
    const BOOL expectWasDirty = _expect.dirty;
    [_expect resetDirty];
    const VT100SyncResult syncResult = [_screen synchronizeWithConfig:_config
                                                               expect:expectWasDirty ? _expect : nil
                                                        checkTriggers:checkTriggers
                                                        resetOverflow:resetOverflow
                                                         mutableState:mutableState];
    _textview.colorMap = _screen.colorMap;
    DLog(@"END syncCheckingTriggers");
    return syncResult;
}

- (void)enableOffscreenMarkAlertsIfNeeded {
    DLog(@"enableOffscreenMarkAlertsIfNeeded %@", self);
    if (_temporarilySuspendOffscreenMarkAlerts) {
        DLog(@"_temporarilySuspendOffscreenMarkAlerts = NO for %@", self);
        _temporarilySuspendOffscreenMarkAlerts = NO;
        [self sync];
    }
}

- (BOOL)textViewShouldAcceptKeyDownEvent:(NSEvent *)event {
    [self removeSelectedCommandRange];
    [self enableOffscreenMarkAlertsIfNeeded];
    const BOOL accept = [self shouldAcceptKeyDownEvent:event];
    if (accept) {
        [_cadenceController didHandleKeystroke];
    }
    return accept;
}

- (BOOL)shouldReportOrFilterKeystrokesForAPI {
    if (self.isTmuxClient && _tmuxPaused) {
        // This ignores the monitor filter and subscriptions because it might be the only way to
        // unpause.
        return NO;
    }
    return YES;
}

- (void)textViewDidReceiveFlagsChangedEvent:(NSEvent *)event {
    if ([self shouldReportOrFilterKeystrokesForAPI]) {
        [self sendKeystrokeNotificationForEvent:event advanced:YES];
    }
    // Change of cmd modifier means we need mouseMoved events to highlight/unhighlight URLs.
    [self.view updateTrackingAreas];
}

- (void)textViewHaveVisibleBlocksDidChange {
    [self.view updateTrackingAreas];
}

- (BOOL)shouldAcceptKeyDownEvent:(NSEvent *)event {
    const BOOL accept = ![self keystrokeIsFilteredByMonitor:event];

    if (accept) {
        if (_textview.selection.hasSelection &&
            !_textview.selection.live &&
            [_modeHandler.copyModeHandler shouldAutoEnterWithEvent:event]) {
            // Avoid handling the event twice (which is the cleverness)
            [_modeHandler enterCopyModeWithoutCleverness];
            [_modeHandler.copyModeHandler handleAutoEnteringEvent:event];
            return NO;
        }
        if (_modeHandler.mode != iTermSessionModeDefault) {
            [_modeHandler handleEvent:event];
            return NO;
        }
        if (event.keyCode == kVK_Return) {
            [_screen userDidPressReturn];
        }

        if ((event.it_modifierFlags & NSEventModifierFlagControl) && [event.charactersIgnoringModifiers isEqualToString:@"c"]) {
            if (_screen.terminalReceivingFile) {
                // Offer to abort download if you press ^c while downloading an inline file
                [self.naggingController askAboutAbortingDownload];
            } else if (self.upload) {
                [self.naggingController askAboutAbortingUpload];
            }
        }
        _lastInput = [NSDate timeIntervalSinceReferenceDate];
        [_pwdPoller userDidPressKey];
        if ([_view.currentAnnouncement handleKeyDown:event]) {
            return NO;
        }
    }
    if (![self shouldReportOrFilterKeystrokesForAPI]) {
        [self setTmuxPaused:NO allowAutomaticUnpause:YES];
        return NO;
    }
    if (_keystrokeSubscriptions.count && ![event it_eventGetsSpecialHandlingForAPINotifications]) {
        [self sendKeystrokeNotificationForEvent:event advanced:NO];
    }

    if (accept) {
        [_metaFrustrationDetector didSendKeyEvent:event];
    }
    if ([self eventAbortsPasteWaitingForPrompt:event]) {
        [_pasteHelper abort];
        return NO;
    }

    return accept;
}

- (NSArray<NSNumber *> *)apiModifiersForModifierFlags:(NSEventModifierFlags)flags {
    NSMutableArray<NSNumber *> *mods = [NSMutableArray array];
    if (flags & NSEventModifierFlagControl) {
        [mods addObject:@(ITMModifiers_Control)];
    }
    if (flags & NSEventModifierFlagOption) {
        [mods addObject:@(ITMModifiers_Option)];
    }
    if (flags & NSEventModifierFlagCommand) {
        [mods addObject:@(ITMModifiers_Command)];
    }
    if (flags & NSEventModifierFlagShift) {
        [mods addObject:@(ITMModifiers_Shift)];
    }
    if (flags & NSEventModifierFlagNumericPad) {
        [mods addObject:@(ITMModifiers_Numpad)];
    }
    if (flags & NSEventModifierFlagFunction) {
        [mods addObject:@(ITMModifiers_Function)];
    }
    return mods;
}

- (void)sendKeystrokeNotificationForEvent:(NSEvent *)event
                                 advanced:(BOOL)advanced {
    ITMKeystrokeNotification *keystrokeNotification = [[[ITMKeystrokeNotification alloc] init] autorelease];
    if (!advanced || event.type != NSEventTypeFlagsChanged) {
        keystrokeNotification.characters = event.characters;
        keystrokeNotification.charactersIgnoringModifiers = event.charactersIgnoringModifiers;
    }
    for (NSNumber *number in [self apiModifiersForModifierFlags:event.it_modifierFlags]) {
        [keystrokeNotification.modifiersArray addValue:number.intValue];
    }
    switch (event.type) {
        case NSEventTypeKeyDown:
            keystrokeNotification.action = ITMKeystrokeNotification_Action_KeyDown;
            break;
        case NSEventTypeKeyUp:
            keystrokeNotification.action = ITMKeystrokeNotification_Action_KeyUp;
            break;
        case NSEventTypeFlagsChanged:
            keystrokeNotification.action = ITMKeystrokeNotification_Action_FlagsChanged;
            break;
        default:
            break;
    }
    keystrokeNotification.keyCode = event.keyCode;
    keystrokeNotification.session = self.guid;
    ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
    notification.keystrokeNotification = keystrokeNotification;

    [_keystrokeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        if (advanced && !obj.keystrokeMonitorRequest.advanced) {
            return;
        }
        [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                             toConnectionKey:key];
    }];
}

- (BOOL)eventAbortsPasteWaitingForPrompt:(NSEvent *)event {
    if (!_pasteHelper.isWaitingForPrompt) {
        return NO;
    }
    if (event.keyCode == kVK_Escape) {
        return YES;
    }
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagCommand |
                                       NSEventModifierFlagControl);
    if ((event.modifierFlags & mask) == NSEventModifierFlagControl &&
        [event.characters isEqualToString:[NSString stringWithLongCharacter:3]]) {
        // ^C
        return YES;
    }
    return NO;
}

+ (void)reportFunctionCallError:(NSError *)error forInvocation:(NSString *)invocation origin:(NSString *)origin window:(NSWindow *)window {
    [iTermAPIHelper reportFunctionCallError:error forInvocation:invocation origin:origin window:window];
}

- (void)invokeFunctionCall:(NSString *)invocation
                     scope:(iTermVariableScope *)scope
                    origin:(NSString *)origin {
    [iTermScriptFunctionCall callFunction:invocation
                                  timeout:[[NSDate distantFuture] timeIntervalSinceNow]
                                    scope:scope
                               retainSelf:YES
                               completion:^(id value, NSError *error, NSSet<NSString *> *missing) {
        if (error) {
            [PTYSession reportFunctionCallError:error
                                  forInvocation:invocation
                                         origin:origin
                                         window:self.view.window];
        }
    }];
}

- (void)applyAction:(iTermAction *)action {
    [self.textview.window makeFirstResponder:self.textview];
    [self performKeyBindingAction:[iTermKeyBindingAction withAction:action.action
                                                          parameter:action.parameter
                                                           escaping:action.escaping
                                                          applyMode:action.applyMode]
                            event:nil];
}

// This is limited to the actions that don't need any existing session
+ (BOOL)performKeyBindingAction:(iTermKeyBindingAction *)action event:(NSEvent *)event {
    if (!action) {
        return NO;
    }
    NSArray<PTYSession *> *sessions = [PTYSession sessionsForActionApplyMode:action.applyMode focused:nil];
    if (action.applyMode != iTermActionApplyModeCurrentSession && sessions.count > 0) {
        for (PTYSession *session in sessions) {
            [session reallyPerformKeyBindingAction:action event:event];
        }
        return YES;
    }

    switch (action.keyAction) {
        case KEY_ACTION_INVALID:
            // No action
            return NO;

        case KEY_ACTION_IGNORE:
            return YES;

        case KEY_ACTION_MOVE_TAB_LEFT:
        case KEY_ACTION_MOVE_TAB_RIGHT:
        case KEY_ACTION_NEXT_MRU_TAB:
        case KEY_ACTION_PREVIOUS_MRU_TAB:
        case KEY_ACTION_NEXT_PANE:
        case KEY_ACTION_PREVIOUS_PANE:
        case KEY_ACTION_NEXT_SESSION:
        case KEY_ACTION_NEXT_WINDOW:
        case KEY_ACTION_PREVIOUS_SESSION:
        case KEY_ACTION_PREVIOUS_WINDOW:
        case KEY_ACTION_SCROLL_END:
        case KEY_ACTION_SCROLL_HOME:
        case KEY_ACTION_SCROLL_LINE_DOWN:
        case KEY_ACTION_SCROLL_LINE_UP:
        case KEY_ACTION_SCROLL_PAGE_DOWN:
        case KEY_ACTION_SCROLL_PAGE_UP:
        case KEY_ACTION_ESCAPE_SEQUENCE:
        case KEY_ACTION_HEX_CODE:
        case KEY_ACTION_TEXT:
        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_RUN_COPROCESS:
        case KEY_ACTION_SEND_C_H_BACKSPACE:
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
        case KEY_ACTION_IR_FORWARD:
        case KEY_ACTION_IR_BACKWARD:
        case KEY_ACTION_SELECT_PANE_LEFT:
        case KEY_ACTION_SELECT_PANE_RIGHT:
        case KEY_ACTION_SELECT_PANE_ABOVE:
        case KEY_ACTION_SELECT_PANE_BELOW:
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
        case KEY_ACTION_TOGGLE_FULLSCREEN:
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
        case KEY_ACTION_SET_PROFILE:
        case KEY_ACTION_LOAD_COLOR_PRESET:
        case KEY_ACTION_FIND_REGEX:
        case KEY_FIND_AGAIN_DOWN:
        case KEY_FIND_AGAIN_UP:
        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION:
        case KEY_ACTION_PASTE_SPECIAL:
        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING:
        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
        case KEY_ACTION_DECREASE_HEIGHT:
        case KEY_ACTION_INCREASE_HEIGHT:
        case KEY_ACTION_DECREASE_WIDTH:
        case KEY_ACTION_INCREASE_WIDTH:
        case KEY_ACTION_SWAP_PANE_LEFT:
        case KEY_ACTION_SWAP_PANE_RIGHT:
        case KEY_ACTION_SWAP_PANE_ABOVE:
        case KEY_ACTION_SWAP_PANE_BELOW:
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
        case KEY_ACTION_DUPLICATE_TAB:
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
        case KEY_ACTION_SEND_SNIPPET:
        case KEY_ACTION_COMPOSE:
        case KEY_ACTION_SEND_TMUX_COMMAND:
        case KEY_ACTION_SWAP_WITH_NEXT_PANE:
        case KEY_ACTION_SWAP_WITH_PREVIOUS_PANE:
        case KEY_ACTION_ALERT_ON_NEXT_MARK:
            return NO;

        case KEY_ACTION_COPY_OR_SEND:
            return [[NSApp mainMenu] performActionForItemWithSelector:@selector(copy:)];

        case KEY_ACTION_PASTE_OR_SEND:
            return [[NSApp mainMenu] performActionForItemWithSelector:@selector(paste:)];

        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            [iTermScriptFunctionCall callFunction:action.parameter
                                          timeout:[[NSDate distantFuture] timeIntervalSinceNow]
                                            scope:[iTermVariableScope globalsScope]
                                       retainSelf:YES
                                       completion:^(id value, NSError *error, NSSet<NSString *> *missing) {
                if (error) {
                    [PTYSession reportFunctionCallError:error
                                          forInvocation:action.parameter
                                                 origin:@"Key Binding"
                                                 window:nil];
                }
            }];
            return YES;

        case KEY_ACTION_SELECT_MENU_ITEM:
            [PTYSession selectMenuItem:action.parameter];
            return YES;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE: {
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:action.parameter];
            [iTermSessionLauncher launchBookmark:profile
                                      inTerminal:nil
                              respectTabbingMode:NO
                                      completion:nil];
            return YES;
        }
        case KEY_ACTION_UNDO:
            [PTYSession selectMenuItemWithSelector:@selector(undo:)];
            return YES;

        case KEY_ACTION_SEQUENCE: {
            NSArray<iTermKeyBindingAction *> *subactions = [action.parameter keyBindingActionsFromSequenceParameter];
            for (iTermKeyBindingAction *subaction in subactions) {
                [self performKeyBindingAction:subaction event:event];
            }
            return YES;
        }
    }
    assert(false);
    return NO;
}

+ (NSArray<PTYSession *> *)sessionsForActionApplyMode:(iTermActionApplyMode)mode focused:(PTYSession *)focused {
    switch (mode) {
        case iTermActionApplyModeCurrentSession:
            return focused ? @[ focused ] : @[];
        case iTermActionApplyModeAllSessions:
            return [[iTermController sharedInstance] allSessions];
        case iTermActionApplyModeUnfocusedSessions:
            return [[[iTermController sharedInstance] allSessions] arrayByRemovingObject:focused];
        case iTermActionApplyModeAllInWindow:
            return [focused.delegate.realParentWindow allSessions] ?: @[];
        case iTermActionApplyModeAllInTab:
            return [focused.delegate sessions] ?: @[];
        case iTermActionApplyModeBroadcasting:
            if (!focused) {
                return @[];
            }
            if (focused.delegate.realParentWindow.broadcastMode == BROADCAST_OFF) {
                return @[ focused ];
            }
            return focused.delegate.realParentWindow.broadcastSessions ?: @[ focused ];
    }
    return @[];
}

- (void)performKeyBindingAction:(iTermKeyBindingAction *)action event:(NSEvent *)event {
    if (!action) {
        return;
    }
    for (PTYSession *session in [PTYSession sessionsForActionApplyMode:action.applyMode focused:self]) {
        [session reallyPerformKeyBindingAction:action event:event];
    }
}

- (void)reallyPerformKeyBindingAction:(iTermKeyBindingAction *)action event:(NSEvent *)event {
    BOOL isTmuxGateway = (!_exited && self.tmuxMode == TMUX_GATEWAY);
    id<iTermWindowController> windowController = self.delegate.realParentWindow ?: [[iTermController sharedInstance] currentTerminal];

    switch (action.keyAction) {
        case KEY_ACTION_MOVE_TAB_LEFT:
            [[_delegate realParentWindow] moveTabLeft:nil];
            break;
        case KEY_ACTION_MOVE_TAB_RIGHT:
            [[_delegate realParentWindow] moveTabRight:nil];
            break;
        case KEY_ACTION_NEXT_MRU_TAB:
            [[[_delegate realParentWindow] tabView] cycleKeyDownWithModifiers:[event it_modifierFlags]
                                                                     forwards:YES];
            break;
        case KEY_ACTION_PREVIOUS_MRU_TAB:
            [[[_delegate realParentWindow] tabView] cycleKeyDownWithModifiers:[event it_modifierFlags]
                                                                     forwards:NO];
            break;
        case KEY_ACTION_NEXT_PANE:
            [_delegate nextSession];
            break;
        case KEY_ACTION_PREVIOUS_PANE:
            [_delegate previousSession];
            break;
        case KEY_ACTION_NEXT_SESSION:
            [[_delegate realParentWindow] nextTab:nil];
            break;
        case KEY_ACTION_NEXT_WINDOW:
            [[iTermController sharedInstance] nextTerminal];
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            [[_delegate realParentWindow] previousTab:nil];
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            [[iTermController sharedInstance] previousTerminal];
            break;
        case KEY_ACTION_SCROLL_END:
            [[_delegate realParentWindow] broadcastScrollToEnd:self];
            break;
        case KEY_ACTION_SCROLL_HOME:
            [_textview scrollHome];
            [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
            break;
        case KEY_ACTION_SCROLL_LINE_DOWN:
            [_textview scrollLineDown:self];
            [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
            break;
        case KEY_ACTION_SCROLL_LINE_UP:
            [_textview scrollLineUp:self];
            [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
            break;
        case KEY_ACTION_SCROLL_PAGE_DOWN:
            [_textview scrollPageDown:self];
            [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
            break;
        case KEY_ACTION_SCROLL_PAGE_UP:
            [_textview scrollPageUp:self];
            [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
            break;
        case KEY_ACTION_ESCAPE_SEQUENCE:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendEscapeSequence:action.parameter];
            break;
        case KEY_ACTION_HEX_CODE:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendHexCode:action.parameter];
            break;
        case KEY_ACTION_TEXT:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendText:action.parameter escaping:action.escaping];
            break;
        case KEY_ACTION_VIM_TEXT:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendText:action.parameter escaping:action.vimEscaping];
            break;
        case KEY_ACTION_SEND_SNIPPET:
            if (_exited || isTmuxGateway) {
                return;
            } else {
                DLog(@"Look up snippet with param %@", action.parameter);
                iTermSnippet *snippet = [[iTermSnippetsModel sharedInstance] snippetWithActionKey:action.parameter];
                if (snippet) {
                    [self sendText:snippet.value escaping:snippet.escaping];
                }
            }
            break;
        case KEY_ACTION_COMPOSE:
            if (_exited || isTmuxGateway) {
                return;
            } else {
                DLog(@"Open composer with%@", action.parameter);
                [self.composerManager showWithCommand:action.parameter];
            }
            break;
        case KEY_ACTION_SEND_TMUX_COMMAND:
            if (_exited || isTmuxGateway || !self.isTmuxClient) {
                return;
            }
            [self performTmuxCommand:action.parameter];
            break;
        case KEY_ACTION_RUN_COPROCESS:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self launchCoprocessWithCommand:action.parameter];
            break;
        case KEY_ACTION_SELECT_MENU_ITEM:
            [PTYSession selectMenuItem:action.parameter];
            break;

        case KEY_ACTION_SEND_C_H_BACKSPACE:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self writeStringWithLatin1Encoding:@"\010"];
            break;
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self writeStringWithLatin1Encoding:@"\177"]; // decimal 127
            break;
        case KEY_ACTION_IGNORE:
            break;
        case KEY_ACTION_IR_FORWARD:
            break;
        case KEY_ACTION_IR_BACKWARD:
            if (isTmuxGateway) {
                return;
            }
            [[iTermController sharedInstance] irAdvance:-1];
            break;
        case KEY_ACTION_SELECT_PANE_LEFT:
            [windowController selectPaneLeft:nil];
            break;
        case KEY_ACTION_SELECT_PANE_RIGHT:
            [windowController selectPaneRight:nil];
            break;
        case KEY_ACTION_SELECT_PANE_ABOVE:
            [windowController selectPaneUp:nil];
            break;
        case KEY_ACTION_SELECT_PANE_BELOW:
            [windowController selectPaneDown:nil];
            break;
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
            break;
        case KEY_ACTION_TOGGLE_FULLSCREEN:
            [windowController toggleFullScreenMode:nil];
            break;
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
            [[_delegate realParentWindow] newWindowWithBookmarkGuid:action.parameter];
            break;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            [[_delegate realParentWindow] newTabWithBookmarkGuid:action.parameter];
            break;
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE: {
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:action.parameter];
            if (!profile) {
                break;
            }
            [[_delegate realParentWindow] asyncSplitVertically:NO
                                                        before:NO
                                                       profile:profile
                                                 targetSession:[[_delegate realParentWindow] currentSession]
                                                    completion:nil
                                                         ready:nil];
            break;
        }
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE: {
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:action.parameter];
            if (!profile) {
                break;
            }
            [[_delegate realParentWindow] asyncSplitVertically:YES
                                                        before:NO
                                                       profile:profile
                                                 targetSession:[[_delegate realParentWindow] currentSession]
                                                    completion:nil
                                                         ready:nil];
            break;
        }
        case KEY_ACTION_SET_PROFILE: {
            Profile *newProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:action.parameter];
            if (newProfile) {
                [self setProfile:newProfile preservingName:YES];
            }
            break;
        }
        case KEY_ACTION_LOAD_COLOR_PRESET: {
            // Divorce & update self
            [self setColorsFromPresetNamed:action.parameter];

            // Try to update the backing profile if possible, which may undivorce you. The original
            // profile may not exist so this could do nothing.
            ProfileModel *model = [ProfileModel sharedInstance];
            Profile *profile;
            if (self.isDivorced) {
                profile = [[ProfileModel sharedInstance] bookmarkWithGuid:_profile[KEY_ORIGINAL_GUID]];
            } else {
                profile = self.profile;
            }
            if (profile) {
                [model addColorPresetNamed:action.parameter toProfile:profile];
            }
            break;
        }

        case KEY_ACTION_FIND_REGEX: {
            [_view createFindDriverIfNeeded];
            [_view.findDriver closeViewAndDoTemporarySearchForString:action.parameter
                                                                mode:iTermFindModeCaseSensitiveRegex
                                                            progress:nil];
            break;
        }
        case KEY_FIND_AGAIN_DOWN:
            // The UI exposes this as "find down" so it doesn't respect swapFindNextPrevious
            [self searchNext];
            break;

        case KEY_FIND_AGAIN_UP:
            // The UI exposes this as "find up" so it doesn't respect swapFindNextPrevious
            [self searchPrevious];
            break;

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION: {
            NSString *string = [[iTermController sharedInstance] lastSelectionPromise].wait.maybeFirst;
            if (string.length) {
                [_pasteHelper pasteString:string
                             stringConfig:action.parameter];
            }
            break;
        }

        case KEY_ACTION_PASTE_SPECIAL: {
            NSString *string = [NSString stringFromPasteboard];
            if (string.length) {
                [_pasteHelper pasteString:string
                             stringConfig:action.parameter];
            }
            break;
        }

        case KEY_ACTION_TOGGLE_HOTKEY_WINDOW_PINNING: {
            DLog(@"Toggle pinning");
            BOOL autoHid = [iTermProfilePreferences boolForKey:KEY_HOTKEY_AUTOHIDE inProfile:self.profile];
            DLog(@"Getting profile with guid %@ from originalProfile %p", self.originalProfile[KEY_GUID], self.originalProfile);
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:self.originalProfile[KEY_GUID]];
            if (profile) {
                DLog(@"Found a profile");
                [iTermProfilePreferences setBool:!autoHid forKey:KEY_HOTKEY_AUTOHIDE inProfile:profile model:[ProfileModel sharedInstance]];
            }
            break;
        }
        case KEY_ACTION_UNDO:
            [PTYSession selectMenuItemWithSelector:@selector(undo:)];
            break;

        case KEY_ACTION_MOVE_END_OF_SELECTION_LEFT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointEnd
                                 inDirection:kPTYTextViewSelectionExtensionDirectionLeft
                                          by:[action.parameter integerValue]];
            break;
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointEnd
                                 inDirection:kPTYTextViewSelectionExtensionDirectionRight
                                          by:[action.parameter integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointStart
                                 inDirection:kPTYTextViewSelectionExtensionDirectionLeft
                                          by:[action.parameter integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointStart
                                 inDirection:kPTYTextViewSelectionExtensionDirectionRight
                                          by:[action.parameter integerValue]];
            break;

        case KEY_ACTION_DECREASE_HEIGHT:
            [windowController decreaseHeightOfSession:self];
            break;
        case KEY_ACTION_INCREASE_HEIGHT:
            [windowController increaseHeightOfSession:self];
            break;

        case KEY_ACTION_DECREASE_WIDTH:
            [windowController decreaseWidthOfSession:self];
            break;
        case KEY_ACTION_INCREASE_WIDTH:
            [windowController increaseWidthOfSession:self];
            break;

        case KEY_ACTION_SWAP_PANE_LEFT:
            [windowController swapPaneLeft];
            break;
        case KEY_ACTION_SWAP_PANE_RIGHT:
            [windowController swapPaneRight];
            break;
        case KEY_ACTION_SWAP_PANE_ABOVE:
            [windowController swapPaneUp];
            break;
        case KEY_ACTION_SWAP_PANE_BELOW:
            [windowController swapPaneDown];
            break;
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            [self setXtermMouseReporting:![self xtermMouseReporting]];
            break;
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            [self invokeFunctionCall:action.parameter
                               scope:self.variablesScope
                              origin:@"Key Binding"];
            break;
        case KEY_ACTION_DUPLICATE_TAB:
            [self.delegate sessionDuplicateTab];
            break;
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            [self textViewMovePane];
            break;

        case KEY_ACTION_SEQUENCE: {
            PTYSession *session = self;
            for (iTermKeyBindingAction *subaction in [action.parameter keyBindingActionsFromSequenceParameter]) {
                [session performKeyBindingAction:subaction event:event];
                session = [[[iTermController sharedInstance] currentTerminal] currentSession] ?: self;
            }
            break;
        case KEY_ACTION_SWAP_WITH_NEXT_PANE:
            [self.delegate sessionSwapWithSessionInDirection:1];
            break;
        case KEY_ACTION_SWAP_WITH_PREVIOUS_PANE:
            [self.delegate sessionSwapWithSessionInDirection:-1];
            break;
        case KEY_ACTION_COPY_OR_SEND:
            if ([self hasSelection]) {
                [_textview copy:nil];
                break;
            }
            [self regularKeyDown:[NSApp currentEvent]];
            break;
        }
        case KEY_ACTION_PASTE_OR_SEND:
            if ([[PTYSession pasteboardString] length]) {
                [_textview paste:[[NSApp mainMenu] itemWithSelector:@selector(paste:) tag:0]];
                break;
            }
            [self regularKeyDown:[NSApp currentEvent]];
            break;

        case KEY_ACTION_ALERT_ON_NEXT_MARK:
            self.alertOnNextMark = YES;
            break;

        default:
            XLog(@"Unknown key action %@", action);
            break;
    }
}

#pragma mark - Key Handling

- (BOOL)eventNeedsMitigation:(NSEvent *)event {
    if (event.keyCode != kVK_Escape) {
        return NO;
    }
    // Credit to https://github.com/niw/HapticKey for the magic number.
    const int64_t keyboardType = CGEventGetIntegerValueField(event.CGEvent, kCGKeyboardEventKeyboardType);
    static const int64_t touchbarKeyboardType = 198;
    if (keyboardType != touchbarKeyboardType) {
        return NO;
    }
    if (event.isARepeat) {
        return NO;
    }

    return YES;
}

- (void)actuateHapticFeedbackForEvent:(NSEvent *)event {
    if (![iTermPreferences boolForKey:kPreferenceKeyEnableHapticFeedbackForEsc]) {
        return;
    }
    if (event.type == NSEventTypeKeyDown) {
        [[iTermHapticActuator sharedActuator] actuateTouchDownFeedback];
        return;
    }
    if (event.type == NSEventTypeKeyUp && event.keyCode == kVK_Escape) {
        [[iTermHapticActuator sharedActuator] actuateTouchUpFeedback];
        return;
    }
}

- (void)playSoundForEvent:(NSEvent *)event {
    if (![iTermPreferences boolForKey:kPreferenceKeyEnableSoundForEsc]) {
        return;
    }
    if (event.type == NSEventTypeKeyDown) {
        [[iTermSoundPlayer keyClick] play];
    }
}

- (void)showVisualIndicatorForEvent:(NSEvent *)event {
    if (_showingVisualIndicatorForEsc) {
        return;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyVisualIndicatorForEsc]) {
        return;
    }
    _showingVisualIndicatorForEsc = YES;

    NSNumber *savedCursorTypeOverride = _cursorTypeOverride;

    ITermCursorType temporaryType;
    if (self.cursorType == CURSOR_BOX) {
        temporaryType = CURSOR_UNDERLINE;
    } else {
        temporaryType = CURSOR_BOX;
    }

    self.cursorTypeOverride = @(temporaryType);
    [_textview setCursorNeedsDisplay];
    _cursorTypeOverrideChanged = NO;

    [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 / 15.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_cursorTypeOverrideChanged) {
            self.cursorTypeOverride = savedCursorTypeOverride;
        }
        self->_showingVisualIndicatorForEsc = NO;
        [self release];
    });
}

- (void)mitigateTouchBarStupidityForEvent:(NSEvent *)event {
    if (![self eventNeedsMitigation:event]) {
        return;
    }
    [self actuateHapticFeedbackForEvent:event];
    [self playSoundForEvent:event];
    [self showVisualIndicatorForEvent:event];
}

- (void)textViewSelectionDidChangeToTruncatedString:(NSString *)maybeSelection {
    // Assign a maximum of maximumBytesToProvideToPythonAPI characters to the "selection"
    // iTerm Variable
    //
    // The "selectionLength" iTerm variable contains the full length of the original
    // selection; not the restricted length assigned to the "selection" iTerm Variable
    DLog(@"textViewSelectionDidChangeToTruncatedString: %@", maybeSelection);

    NSString *selection = maybeSelection ?: @"";
    const int maxLength = [iTermAdvancedSettingsModel maximumBytesToProvideToPythonAPI];
    [self.variablesScope setValue:[selection substringToIndex:MIN(maxLength, selection.length)] forVariableNamed:iTermVariableKeySessionSelection];
    [self.variablesScope setValue:@(selection.length) forVariableNamed:iTermVariableKeySessionSelectionLength];
}

// Handle bookmark- and global-scope keybindings. If there is no keybinding then
// pass the keystroke as input.
- (void)keyDown:(NSEvent *)event {
    [self mitigateTouchBarStupidityForEvent:event];

    if (event.charactersIgnoringModifiers.length == 0) {
        return;
    }
    if (event.type == NSEventTypeKeyDown) {
        [self logKeystroke:event];
        [self resumeOutputIfNeeded];

        if ([self trySpecialKeyHandlersForEvent:event]) {
            return;
        }
    }
    [self regularKeyDown:event];
}

- (void)regularKeyDown:(NSEvent *)event {
    DLog(@"PTYSession keyDown not short-circuted by special handler");
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagControl);

    if (!_screen.terminalSoftAlternateScreenMode &&
        ([[iTermApplication sharedApplication] it_modifierFlags] & mask) == 0 &&
        [iTermProfilePreferences boolForKey:KEY_MOVEMENT_KEYS_SCROLL_OUTSIDE_INTERACTIVE_APPS inProfile:self.profile]) {
        switch (event.keyCode) {
            case kVK_PageUp:
                [_textview scrollPageUp:nil];
                [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
                return;

            case kVK_PageDown:
                [_textview scrollPageDown:nil];
                [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
                return;

            case kVK_Home:
                [_textview scrollHome];
                [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
                return;

            case kVK_End:
                [_textview scrollEnd];
                [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
                return;

            case kVK_UpArrow:
                if (!_exited) {
                    break;
                }
                [_textview scrollLineUp:nil];
                [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
                break;

            case kVK_DownArrow:
                if (!_exited) {
                    break;
                }
                [_textview scrollLineDown:nil];
                [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];

            default:
                break;
        }
    }

    if (_exited) {
        DLog(@"Terminal already dead");
        return;
    }

    NSData *const dataToSend = [_keyMapper keyMapperDataForPostCocoaEvent:event];
    DLog(@"dataToSend=%@", dataToSend);
    if (dataToSend) {
        [self writeLatin1EncodedData:dataToSend broadcastAllowed:YES reporting:NO];
    }
}

- (void)keyUp:(NSEvent *)event {
    if ([self shouldReportOrFilterKeystrokesForAPI]) {
        [self sendKeystrokeNotificationForEvent:event advanced:YES];
    }
    if (_screen.terminalReportKeyUp) {
        NSData *const dataToSend = [_keyMapper keyMapperDataForKeyUp:event];
        if (dataToSend) {
            [self writeLatin1EncodedData:dataToSend broadcastAllowed:YES reporting:NO];
        }
    }
}
- (void)logKeystroke:(NSEvent *)event {
    const unichar unicode = event.characters.length > 0 ? [event.characters characterAtIndex:0] : 0;
    DLog(@"event:%@ (%llx+%x)[%@][%@]:%x(%c) <%lu>",
         event, (unsigned long long)event.it_modifierFlags, event.keyCode, event.characters,
         event.charactersIgnoringModifiers, unicode, unicode,
         (event.it_modifierFlags & NSEventModifierFlagNumericPad));
}

- (BOOL)trySpecialKeyHandlersForEvent:(NSEvent *)event {
    if ([self maybeHandleZoomedKeyEvent:event]) {
        return YES;
    }
    if ([self maybeHandleInstantReplayKeyEvent:event]) {
        return YES;
    }
    if ([self maybeHandleKeyBindingActionForKeyEvent:event]) {
        return YES;
    }
    if ([self maybeHandleTmuxGatewayKeyEvent:event]) {
        return YES;
    }
    if ([self textViewIsZoomedIn]) {
        DLog(@"Swallow keyboard input while zoomed.");
        return YES;
    }
    return NO;
}

- (BOOL)maybeHandleTmuxGatewayKeyEvent:(NSEvent *)event {
    // Key is not bound to an action.
    if (_exited) {
        return NO;
    }
    if (self.tmuxMode != TMUX_GATEWAY) {
        return NO;
    }

    [self handleKeypressInTmuxGateway:event];
    DLog(@"Special handler: TMUX GATEWAY");
    return YES;
}

- (BOOL)maybeHandleZoomedKeyEvent:(NSEvent *)event {
    if (![self textViewIsZoomedIn]) {
        return NO;
    }

    const unichar character = event.characters.length > 0 ? [event.characters characterAtIndex:0] : 0;
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagControl |
                                       NSEventModifierFlagOption |
                                       NSEventModifierFlagShift);
    if ((event.modifierFlags & mask) != 0) {
        // Let it go to the key binding handler.
        return NO;
    }

    if (character != 27) {
        // Didn't press esc
        return NO;
    }

    // Escape exits zoom (pops out one level, since you can zoom repeatedly)
    // The zoomOut: IBAction doesn't get performed by shortcut, I guess because Esc is not a
    // valid shortcut. So we do it here.
    DLog(@"Special handler: ZOOM OUT - unmodified esc");
    return [self unzoomIfPossible];
}

- (BOOL)unzoomIfPossible {
    if (![self textViewIsZoomedIn]) {
        return NO;
    }

    if (self.filter.length) {
        DLog(@"stopFiltering");
        [self stopFiltering];
    } else {
        DLog(@"Unzooming");
        [[_delegate realParentWindow] replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
    }
    return YES;
}

- (PTYSessionZoomState *)stateToSaveForZoom {
    if (self.filter) {
        return nil;
    }
    const long long lineNumber = [_textview firstVisibleAbsoluteLineNumber];
    NSString *query = nil;
    if (_view.findDriver.findString.length) {
        query = _view.findDriver.findString;
    }
    return [[[PTYSessionZoomState alloc] initWithFirstVisibleAbsoluteLineNumber:lineNumber
                                                                    searchQuery:query] autorelease];
}

- (void)restoreStateForZoom:(PTYSessionZoomState *)state {
    if (!state) {
        return;
    }
    [_textview scrollToAbsoluteOffset:state.firstVisibleAbsoluteLineNumber
                               height:_screen.height];
    if (state.searchQuery.length) {
        [_view.findDriver setFindStringUnconditionally:state.searchQuery];
    }
}

- (BOOL)maybeHandleInstantReplayKeyEvent:(NSEvent *)event {
    if (![[_delegate realParentWindow] inInstantReplay]) {
        return NO;
    }

    [self handleKeypressInInstantReplay:event];
    DLog(@"Special handler: INSTANT REPLAY");
    return YES;
}

- (BOOL)maybeHandleKeyBindingActionForKeyEvent:(NSEvent *)event {
    // Check if we have a custom key mapping for this event
    iTermKeystroke *keystroke = [iTermKeystroke withEvent:event];
    iTermKeyBindingAction *action = [iTermKeyMappings actionForKeystroke:keystroke
                                                             keyMappings:self.profile[KEY_KEYBOARD_MAP]];

    if (!action) {
        return NO;
    }
    DLog(@"PTYSession keyDown action=%@", action);
    // A special action was bound to this key combination.
    [self performKeyBindingAction:action event:event];

    DLog(@"Special handler: KEY BINDING ACTION");
    return YES;
}

- (void)handleKeypressInInstantReplay:(NSEvent *)event {
    DLog(@"PTYSession keyDown in IR");

    // Special key handling in IR mode, and keys never get sent to the live
    // session, even though it might be displayed.
    const unichar character = event.characters.length > 0 ? [event.characters characterAtIndex:0] : 0;
    const unichar characterIgnoringModifiers = [event.charactersIgnoringModifiers length] > 0 ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    const NSEventModifierFlags modifiers = event.it_modifierFlags;

    if (character == 27) {
        // Escape exits IR
        [[_delegate realParentWindow] closeInstantReplay:self orTerminateSession:YES];
        return;
    } else if (characterIgnoringModifiers == NSLeftArrowFunctionKey) {
        // Left arrow moves to prev frame
        int n = 1;
        if (modifiers & NSEventModifierFlagShift) {
            n = 15;
        }
        for (int i = 0; i < n; i++) {
            [[_delegate realParentWindow] irPrev:self];
        }
    } else if (characterIgnoringModifiers == NSRightArrowFunctionKey) {
        // Right arrow moves to next frame
        int n = 1;
        if (modifiers & NSEventModifierFlagShift) {
            n = 15;
        }
        for (int i = 0; i < n; i++) {
            [[_delegate realParentWindow] irNext:self];
        }
    } else {
        DLog(@"Beep: Unrecongized keystroke in IR");
        NSBeep();
    }
}


- (NSData *)backspaceData {
    iTermKeyBindingAction *action = [iTermKeyMappings actionForKeystroke:[iTermKeystroke backspace]
                                                             keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];
    if (!action) {
        const char del = 0x7f;
        return [NSData dataWithBytes:&del length:1];
    }
    switch (action.keyAction) {
        case KEY_ACTION_HEX_CODE:
            return [self dataForHexCodes:action.parameter];

        case KEY_ACTION_TEXT:
            return [action.parameter dataUsingEncoding:self.encoding];

        case KEY_ACTION_VIM_TEXT:
            return [[action.parameter stringByExpandingVimSpecialCharacters] dataUsingEncoding:self.encoding];

        case KEY_ACTION_ESCAPE_SEQUENCE:
            return [[@"\e" stringByAppendingString:action.parameter] dataUsingEncoding:self.encoding];

        case KEY_ACTION_SEND_C_H_BACKSPACE:
            return [@"\010" dataUsingEncoding:self.encoding];

        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            return [@"\177" dataUsingEncoding:self.encoding];

        default:
            break;
    }

    return nil;
}

- (BOOL)hasActionableKeyMappingForEvent:(NSEvent *)event {
    if (_textview.selection.hasSelection && !_textview.selection.live) {
        if ([_modeHandler shouldAutoEnterWithEvent:event]) {
            return NO;
        }
    }
    return [[self _keyBindingActionForEvent:event] isActionable];
}

- (BOOL)shouldRespectTerminalMetaSendsEscape {
    if (![iTermAdvancedSettingsModel supportDecsetMetaSendsEscape]) {
        return NO;
    }
    if ([[[self profile] objectForKey:KEY_OPTION_KEY_SENDS] intValue] == OPT_ESC) {
        return NO;
    }
    if ([[[self profile] objectForKey:KEY_RIGHT_OPTION_KEY_SENDS] intValue] == OPT_ESC) {
        return NO;
    }
    return YES;
}

- (iTermOptionKeyBehavior)optionKey {
    if ([self shouldRespectTerminalMetaSendsEscape] &&
        _screen.terminalMetaSendsEscape &&
        [iTermProfilePreferences boolForKey:KEY_LEFT_OPTION_KEY_CHANGEABLE inProfile:self.profile]) {
        return OPT_ESC;
    }
    return [[[self profile] objectForKey:KEY_OPTION_KEY_SENDS] intValue];
}

- (iTermOptionKeyBehavior)rightOptionKey {
    if ([self shouldRespectTerminalMetaSendsEscape] &&
        _screen.terminalMetaSendsEscape &&
        [iTermProfilePreferences boolForKey:KEY_RIGHT_OPTION_KEY_CHANGEABLE inProfile:self.profile]) {
        return OPT_ESC;
    }
    NSNumber *rightOptPref = [[self profile] objectForKey:KEY_RIGHT_OPTION_KEY_SENDS];
    if (rightOptPref == nil) {
        return [self optionKey];
    }
    return [rightOptPref intValue];
}

- (BOOL)applicationKeypadAllowed
{
    return [[[self profile] objectForKey:KEY_APPLICATION_KEYPAD_ALLOWED] boolValue];
}

// Contextual menu
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu
{
    // Ask the parent if it has anything to add
    if ([_delegate realParentWindow] &&
        [[_delegate realParentWindow] respondsToSelector:@selector(menuForEvent:menu:)]) {
        [[_delegate realParentWindow] menuForEvent:theEvent menu:theMenu];
    }
}

// All pastes except "Advanced" go through this method.
- (void)pasteString:(NSString *)theString flags:(PTYSessionPasteFlags)flags {
    if (!theString.length) {
        return;
    }
    DLog(@"pasteString:flags: length=%@ flags=%@", @([theString length]), @(flags));
    iTermTabTransformTags tabTransform = kTabTransformNone;
    int spacesPerTab = -1;
    if (flags & kPTYSessionPasteWithShellEscapedTabs) {
        tabTransform = kTabTransformEscapeWithCtrlV;
    } else if (!_screen.terminalBracketedPasteMode) {
        spacesPerTab = [_pasteHelper numberOfSpacesToConvertTabsTo:theString];
        if (spacesPerTab >= 0) {
            tabTransform = kTabTransformConvertToSpaces;
        } else if (spacesPerTab == kNumberOfSpacesPerTabOpenAdvancedPaste) {
            [_pasteHelper showAdvancedPasteWithFlags:flags];
            return;
        } else if (spacesPerTab == kNumberOfSpacesPerTabCancel) {
            return;
        }
    }

    DLog(@"Calling pasteString:flags: on helper...");
    [_pasteHelper pasteString:theString
                       slowly:!!(flags & kPTYSessionPasteSlowly)
             escapeShellChars:!!(flags & kPTYSessionPasteEscapingSpecialCharacters)
                     isUpload:NO
              allowBracketing:!(flags & kPTYSessionPasteBracketingDisabled)
                 tabTransform:tabTransform
                 spacesPerTab:spacesPerTab];
}

// Pastes the current string in the clipboard. Uses the sender's tag to get flags.
- (void)paste:(id)sender {
    DLog(@"PTYSession paste:");

    if ([self haveAutoComposer]) {
        [self makeComposerFirstResponderIfAllowed];
        [_composerManager paste:sender];
        return;
    }
    // If this class is used in a non-iTerm2 app (as a library), we might not
    // be called from a menu item so just use no flags in this case.
    [self pasteString:[PTYSession pasteboardString] flags:[sender isKindOfClass:NSMenuItem.class] ? [sender tag] : 0];
}

// Show advanced paste window.
- (IBAction)pasteOptions:(id)sender {
    [_pasteHelper showPasteOptionsInWindow:_delegate.realParentWindow.window
                         bracketingEnabled:_screen.terminalBracketedPasteMode];
}

- (void)textViewFontDidChange
{
    if ([self isTmuxClient]) {
        [self notifyTmuxFontChange];
    }
    [_view updateScrollViewFrame];
    [self updateMetalDriver];
    [_view.driver expireNonASCIIGlyphs];
}

- (BOOL)textViewHasBackgroundImage {
    return self.effectiveBackgroundImage != nil;
}

// Lots of different views need to draw the background image.
// - Obviously, PTYTextView uses it for the area where text appears.
// - SessionView will draw it for an area below the scroll view when the cell size doesn't evenly
// divide its size.
// - TextViewWrapper will draw it for a few pixels above the scrollview in the VMARGIN.
// This combines drawing into these different views in a consistent way.
// It also draws the dotted border when there is a maximized pane.
//
// view: the view whose -drawRect is currently running and is being drawn into.
// rect: the rectangle in the coordinate system of |view|.
// blendDefaultBackground: If set, the default background color will be blended over the background
// image. If there is no image and this flag is set then the background color is drawn instead. This
// way SessionView and TextViewWrapper don't have to worry about whether a background image is
// present.
//
// The only reason this still exists is because when subpixel antialiasing is enabled we can't
// draw text on a clear background over a background image. The background image needs to be drawn
// to the same view and then the text can be properly composited over it.
- (BOOL)textViewDrawBackgroundImageInView:(NSView *)view
                                 viewRect:(NSRect)dirtyRect
                   blendDefaultBackground:(BOOL)blendDefaultBackground
                            virtualOffset:(CGFloat)virtualOffset NS_DEPRECATED_MAC(10_0, 10_16) {
    if (!!self.shouldDrawBackgroundImageManually) {
        return NO;
    }
    if (!_backgroundDrawingHelper) {
        _backgroundDrawingHelper = [[iTermBackgroundDrawingHelper alloc] init];
        _backgroundDrawingHelper.delegate = self;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        NSRect contentRect = self.view.contentRect;
        if (contentRect.size.width == 0 ||
            contentRect.size.height == 0) {
            return NO;
        }
        [_backgroundDrawingHelper drawBackgroundImageInView:view
                                                  container:self.view
                                                  dirtyRect:dirtyRect
                                     visibleRectInContainer:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)
                                     blendDefaultBackground:blendDefaultBackground
                                                       flip:NO
                                              virtualOffset:virtualOffset];
    } else {
        NSView *container = [self.delegate sessionContainerView:self];
        NSRect visibleRect = view.enclosingScrollView.documentVisibleRect;
        const CGFloat marginHeight = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
        visibleRect.origin.y -= marginHeight;
        NSRect clippedDirtyRect = NSIntersectionRect(dirtyRect, visibleRect);
        NSRect windowVisibleRect = [self.view insetRect:container.bounds
                                                flipped:YES
                                 includeBottomStatusBar:![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]];
        [_backgroundDrawingHelper drawBackgroundImageInView:view
                                                  container:container
                                                  dirtyRect:clippedDirtyRect
                                     visibleRectInContainer:windowVisibleRect
                                     blendDefaultBackground:blendDefaultBackground
                                                       flip:YES
                                              virtualOffset:virtualOffset];
    }
    return YES;
}

- (CGRect)textViewRelativeFrame {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return CGRectMake(0, 0, 1, 1);
    }
    NSRect viewRect;
    NSRect containerBounds;
    NSView *container = self.view.window.contentView;
    viewRect = [self.view.metalView.superview convertRect:self.view.metalView.frame
                                                   toView:container];
    containerBounds = container.bounds;
    // Flip it
    viewRect.origin.y = containerBounds.size.height - viewRect.origin.y - viewRect.size.height;
    return CGRectMake(viewRect.origin.x / containerBounds.size.width,
                      viewRect.origin.y / containerBounds.size.height,
                      viewRect.size.width / containerBounds.size.width,
                      viewRect.size.height / containerBounds.size.height);
}

- (CGRect)textViewContainerRect {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return self.view.frame;
    }
    NSView *container = [self.delegate sessionContainerView:self];
    return [self.view insetRect:container.bounds
                        flipped:YES
         includeBottomStatusBar:![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]];
}

// This includes the portion of the metal view that is obscured by the status bar or per-pane title bar.
- (NSEdgeInsets)textViewExtraMargins {
    NSEdgeInsets margins = self.view.extraMargins;
    // This is here because of tmux panes. They cause some extra bottom
    // margins, and the regular -extraMargins code only includes stuff like
    // the status bar on the bottom. The top margin it produces is still
    // useful, so we keep that.
    margins.bottom = _view.scrollview.frame.origin.y;
    return margins;
}

- (iTermImageWrapper *)textViewBackgroundImage {
    return _backgroundImage;
}

- (NSColor *)processedBackgroundColor {
    NSColor *unprocessedColor = [_screen.colorMap colorForKey:kColorMapBackground];
    return [_screen.colorMap processedBackgroundColorForBackgroundColor:unprocessedColor];
}

- (void)textViewPostTabContentsChangedNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermTabContentsChanged"
                                                        object:self
                                                      userInfo:nil];
}

- (void)textViewInvalidateRestorableState {
    if ([iTermAdvancedSettingsModel restoreWindowContents]) {
        [_delegate.realParentWindow invalidateRestorableState];
    }
}

- (void)textViewDidFindDirtyRects {
    if (_updateSubscriptions.count) {
        ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
        notification.screenUpdateNotification = [[[ITMScreenUpdateNotification alloc] init] autorelease];
        notification.screenUpdateNotification.session = self.guid;
        [_updateSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
            [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                                 toConnectionKey:key];
        }];
    }

    // Remove the tail-find timer so that a new tail find can begin. This is necessary so that
    // shouldSEndContentsChangedNotification will return YES.
    [_tailFindTimer invalidate];
    _tailFindTimer = nil;
}

- (void)textViewBeginDrag
{
    [[MovePaneController sharedInstance] beginDrag:self];
}

- (void)textViewMovePane {
    [[MovePaneController sharedInstance] movePane:self];
}

- (void)textViewSwapPane {
    [[MovePaneController sharedInstance] swapPane:self];
}

- (NSStringEncoding)textViewEncoding {
    return [self encoding];
}

// This uses the local directory because it is the last desperate gasp of URL action file finding.
- (void)textViewGetCurrentWorkingDirectoryWithCompletion:(void (^)(NSString *workingDirectory))completion {
    [self asyncCurrentLocalWorkingDirectory:completion];
}

// NOTE: This will not fetch the current directory if it's not already known to avoid blocking
// the main thread. Don't use this unless you have to be synchronous.
// Use asyncGetCurrentLocatioNWithCompletion instead.
- (NSURL *)textViewCurrentLocation {
    id<VT100RemoteHostReading>host = [self currentHost];
    NSString *path = _lastDirectory;
    NSURLComponents *components = [[[NSURLComponents alloc] init] autorelease];
    components.host = host.hostname;
    components.user = host.username;
    components.path = path;
    components.scheme = @"file";
    return [components URL];
}

- (void)asyncGetCurrentLocationWithCompletion:(void (^)(NSURL *url))completion {
    // NOTE: Use local directory here because this becomes the proxy icon, and it's basically
    // useless when given a remote directory.
    __weak __typeof(self) weakSelf = self;
    [self asyncCurrentLocalWorkingDirectory:^(NSString *pwd) {
        DLog(@"Finished with %@ for %@", pwd, weakSelf);
        completion([weakSelf urlForHost:weakSelf.currentHost path:pwd]);
    }];
}

- (void)updateLocalDirectoryWithCompletion:(void (^)(NSString *pwd))completion {
    DLog(@"Update local directory of %@", self);
    __weak __typeof(self) weakSelf = self;
    [_shell getWorkingDirectoryWithCompletion:^(NSString *pwd) {
        [[[weakSelf retain] autorelease] didGetWorkingDirectory:pwd completion:completion];
    }];
}

- (void)didGetWorkingDirectory:(NSString *)pwd completion:(void (^)(NSString *pwd))completion {
    // Don't call setLastDirectory:remote:pushed: because we don't want to update the
    // path variable if the session is ssh'ed somewhere.
    DLog(@"getWorkingDirectoryWithCompletion for %@ finished with %@", self, pwd);
    if (self.lastLocalDirectoryWasPushed && self.lastLocalDirectory != nil) {
        DLog(@"Looks like there was a race because there is now a last local directory of %@. Use it.",
             self.lastLocalDirectory);
        completion(self.lastLocalDirectory);
        return;
    }
    self.lastLocalDirectory = pwd;
    self.lastLocalDirectoryWasPushed = NO;
    completion(pwd);
}

- (NSURL *)urlForHost:(id<VT100RemoteHostReading>)host path:(NSString *)path {
    NSURLComponents *components = [[[NSURLComponents alloc] init] autorelease];
    components.host = host.hostname;
    components.user = host.username;
    components.path = path;
    components.scheme = @"file";
    return [components URL];
}

- (BOOL)textViewShouldPlaceCursorAt:(VT100GridCoord)coord verticalOk:(BOOL *)verticalOk {
    if (coord.y < _screen.numberOfLines - _screen.height ||
        coord.x < 0 ||
        coord.x >= _screen.width ||
        coord.y >= _screen.numberOfLines) {
        // Click must be in the live area and not in a margin.
        return NO;
    }
    if (_screen.commandRange.start.x < 0) {
        if (_screen.terminalSoftAlternateScreenMode) {
            // In an interactive app. No restrictions.
            *verticalOk = YES;
            return YES;
        } else {
            // Possibly at a command prompt without shell integration or in some other command line
            // app that may be using readline. No vertical movement.
            *verticalOk = NO;
            return YES;
        }
    } else {
        // At the command prompt. Ok to move to any char within current command, but no up or down
        // arrows please.
        NSComparisonResult order = VT100GridCoordOrder(VT100GridCoordRangeMin(_screen.commandRange),
                                                       coord);
        *verticalOk = NO;
        return (order != NSOrderedDescending);
    }
}

- (BOOL)textViewShouldDrawFilledInCursor {
    // If the auto-command history popup is open for this session, the filled-in cursor should be
    // drawn even though the textview isn't in the key window.
    return [self textViewIsActiveSession] && [[_delegate realParentWindow] autoCommandHistoryIsOpenForSession:self];
}

- (void)textViewWillNeedUpdateForBlink {
    self.active = YES;
}

- (void)textViewSplitVertically:(BOOL)vertically withProfileGuid:(NSString *)guid
{
    Profile *profile;
    if (guid) {
        profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    } else {
        profile = [self profileForSplit];
    }
    [[_delegate realParentWindow] asyncSplitVertically:vertically
                                                before:NO
                                               profile:profile
                                         targetSession:self
                                            completion:nil
                                                 ready:nil];
}

- (void)textViewSelectNextTab
{
    [[_delegate realParentWindow] nextTab:nil];
}

- (void)textViewSelectPreviousTab
{
    [[_delegate realParentWindow] previousTab:nil];
}

- (void)textViewSelectNextWindow {
    [[iTermController sharedInstance] nextTerminal];
}

- (void)textViewSelectPreviousWindow {
    [[iTermController sharedInstance] previousTerminal];
}

- (void)textViewSelectNextPane
{
    [_delegate nextSession];
}

- (void)textViewSelectPreviousPane
{
    [_delegate previousSession];
}

- (void)textViewSelectMenuItemWithIdentifier:(NSString *)identifier title:(NSString *)title {
    [PTYSession _recursiveSelectMenuItemWithTitle:title identifier:identifier inMenu:[NSApp mainMenu]];
}

- (void)textViewPasteSpecialWithStringConfiguration:(NSString *)configuration
                                      fromSelection:(BOOL)fromSelection {
    NSString *string = fromSelection ? [[iTermController sharedInstance] lastSelectionPromise].wait.maybeFirst : [NSString stringFromPasteboard];
    [_pasteHelper pasteString:string
                 stringConfig:configuration];
}

- (void)textViewInvokeScriptFunction:(NSString *)function {
    [self invokeFunctionCall:function scope:self.variablesScope origin:@"Pointer action"];
}

- (void)textViewEditSession {
    [[_delegate realParentWindow] editSession:self makeKey:YES];
}

- (void)textViewToggleBroadcastingInput
{
    [[_delegate realParentWindow] toggleBroadcastingInputToSession:self];
}

- (void)textViewCloseWithConfirmation {
    [[_delegate realParentWindow] closeSessionWithConfirmation:self];
}

- (void)textViewRestartWithConfirmation {
    [[_delegate realParentWindow] restartSessionWithConfirmation:self];
}

- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags {
    NSString *string = [[iTermController sharedInstance] lastSelectionPromise].wait.maybeFirst;
    if (string) {
        [self pasteString:string flags:flags];
    }
}

- (BOOL)textViewWindowUsesTransparency {
    return [[_delegate realParentWindow] useTransparency];
}

- (BOOL)textViewAmbiguousWidthCharsAreDoubleWidth
{
    return [self treatAmbiguousWidthAsDoubleWidth];
}

- (void)textViewCreateWindowWithProfileGuid:(NSString *)guid
{
    [[_delegate realParentWindow] newWindowWithBookmarkGuid:guid];
}

- (void)textViewCreateTabWithProfileGuid:(NSString *)guid
{
    [[_delegate realParentWindow] newTabWithBookmarkGuid:guid];
}

// Called when a key is pressed.
- (BOOL)textViewDelegateHandlesAllKeystrokes
{
    [self resumeOutputIfNeeded];
    return [[_delegate realParentWindow] inInstantReplay];
}

- (BOOL)textViewIsActiveSession {
    return [_delegate sessionIsActiveInTab:self];
}

- (BOOL)textViewSessionIsBroadcastingInput
{
    return [[_delegate realParentWindow] broadcastInputToSession:self];
}

- (BOOL)textViewIsMaximized {
    return [_delegate hasMaximizedPane];
}

- (BOOL)textViewTabHasMaximizedPanel
{
    return [_delegate hasMaximizedPane];
}

- (void)textViewDidBecomeFirstResponder {
    DLog(@"textViewDidBecomeFirstResponder for %@", self);
    [_delegate setActiveSession:self];
    [_view setNeedsDisplay:YES];
    [_view.findDriver owningViewDidBecomeFirstResponder];
    if (self.haveAutoComposer) {
        [self makeComposerFirstResponderIfAllowed];
    }
}

- (void)makeComposerFirstResponderIfAllowed {
    if (!self.copyMode) {
        [_composerManager makeDropDownComposerFirstResponder];
    }
}

- (void)textViewDidResignFirstResponder {
    [_view setNeedsDisplay:YES];
    self.copyMode = false;
}

- (void)setReportingMouseDownForEventType:(NSEventType)eventType {
    switch (eventType) {
        case NSEventTypeLeftMouseDown:
            _reportingLeftMouseDown = YES;
            return;
        case NSEventTypeRightMouseDown:
            _reportingRightMouseDown = YES;
            return;
        case NSEventTypeOtherMouseDown:
            _reportingMiddleMouseDown = YES;
            return;

        case NSEventTypeLeftMouseUp:
            _reportingLeftMouseDown = NO;
            return;
        case NSEventTypeRightMouseUp:
            _reportingRightMouseDown = NO;
            return;
        case NSEventTypeOtherMouseUp:
            _reportingMiddleMouseDown = NO;
            return;

        default:
            assert(NO);
    }
}

- (BOOL)reportingMouseDownForEventType:(NSEventType)eventType {
    switch (eventType) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeLeftMouseUp:
        case NSEventTypeLeftMouseDragged:
            DLog(@"_reportingLeftMouseDown=%@", @(_reportingLeftMouseDown));
            return _reportingLeftMouseDown;

        case NSEventTypeRightMouseDown:
        case NSEventTypeRightMouseUp:
        case NSEventTypeRightMouseDragged:
            DLog(@"_reportingRightMouseDown=%@", @(_reportingRightMouseDown));
            return _reportingRightMouseDown;

        case NSEventTypeOtherMouseDown:
        case NSEventTypeOtherMouseUp:
        case NSEventTypeOtherMouseDragged:
            DLog(@"_reportingMiddleMouseDown=%@", @(_reportingMiddleMouseDown));
            return _reportingMiddleMouseDown;

        default:
            assert(NO);
    }
}

- (BOOL)textViewAnyMouseReportingModeIsEnabled {
    return _screen.terminalMouseMode != MOUSE_REPORTING_NONE;
}

- (BOOL)textViewSmartSelectionActionsShouldUseInterpolatedStrings {
    return [iTermProfilePreferences boolForKey:KEY_SMART_SELECTION_ACTIONS_USE_INTERPOLATED_STRINGS
                                     inProfile:self.profile];
}

- (BOOL)textViewReportMouseEvent:(NSEventType)eventType
                       modifiers:(NSUInteger)modifiers
                          button:(MouseButtonNumber)button
                      coordinate:(VT100GridCoord)coord
                           point:(NSPoint)point
                           delta:(CGSize)delta
        allowDragBeforeMouseDown:(BOOL)allowDragBeforeMouseDown
                        testOnly:(BOOL)testOnly {
    DLog(@"Report event type %lu, modifiers=%lu, button=%d, coord=%@ testOnly=%@ terminalMouseMode=%@ allowDragBeforeMouseDown%@",
         (unsigned long)eventType, (unsigned long)modifiers, button,
         VT100GridCoordDescription(coord), @(testOnly), @(_screen.terminalMouseMode),
         @(allowDragBeforeMouseDown));
    // Ignore unknown buttons.
    if (button == MOUSE_BUTTON_UNKNOWN) {
        return NO;
    }

    switch (eventType) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown:
            switch (_screen.terminalMouseMode) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    DLog(@"normal/button/all - can report");
                    if (!testOnly) {
                        [self setReportingMouseDownForEventType:eventType];
                        _lastReportedCoord = coord;
                        _lastReportedPoint = point;
                        DLog(@"_lastReportedCoord <- %@, _lastReportedPoint <- %@",
                             VT100GridCoordDescription(_lastReportedCoord),
                             NSStringFromPoint(point));
                        [self writeLatin1EncodedData:[_screen.terminalOutput mousePress:button
                                                                          withModifiers:modifiers
                                                                                     at:coord
                                                                                  point:point]
                                    broadcastAllowed:NO
                                           reporting:NO];
                    }
                    return YES;

                case MOUSE_REPORTING_NONE:
                case MOUSE_REPORTING_HIGHLIGHT:
                    DLog(@"non/highlight - can't report");
                    break;
            }
            break;

        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseUp:
            if (testOnly) {
                switch (_screen.terminalMouseMode) {
                    case MOUSE_REPORTING_NORMAL:
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        DLog(@"normal/button/all - can report");
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HIGHLIGHT:
                        DLog(@"none/highlight - can't report");
                        break;
                }
                return NO;
            }
            if ([self reportingMouseDownForEventType:eventType]) {
                [self setReportingMouseDownForEventType:eventType];
                _lastReportedCoord = VT100GridCoordMake(-1, -1);
                _lastReportedPoint = NSMakePoint(-1, -1);
                DLog(@"_lastReportedCoord <- %@, _lastReportedPoint <- %@",
                     VT100GridCoordDescription(_lastReportedCoord),
                     NSStringFromPoint(point));

                switch (_screen.terminalMouseMode) {
                    case MOUSE_REPORTING_NORMAL:
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        DLog(@"normal/button/all - can report");
                        _lastReportedCoord = coord;
                        _lastReportedPoint = point;
                        DLog(@"_lastReportedCoord <- %@, _lastReportedPoint <- %@",
                             VT100GridCoordDescription(_lastReportedCoord),
                             NSStringFromPoint(point));
                        [self writeLatin1EncodedData:[_screen.terminalOutput mouseRelease:button
                                                                            withModifiers:modifiers
                                                                                       at:coord
                                                                                    point:point]
                                    broadcastAllowed:NO
                                           reporting:NO];
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HIGHLIGHT:
                        DLog(@"none/highlight - can't report");
                        break;
                }
            }
            break;


        case NSEventTypeMouseMoved:
            if (_screen.terminalMouseMode != MOUSE_REPORTING_ALL_MOTION) {
                DLog(@"not reporting all motion");
                return NO;
            }
            DLog(@"can report");
            if (testOnly) {
                return YES;
            }
            if ([_screen.terminalOutput shouldReportMouseMotionAtCoord:coord
                                                             lastCoord:_lastReportedCoord
                                                                 point:point
                                                             lastPoint:_lastReportedPoint]) {
                _lastReportedCoord = coord;
                _lastReportedPoint = point;
                DLog(@"_lastReportedCoord <- %@, _lastReportedPoint <- %@",
                     VT100GridCoordDescription(_lastReportedCoord),
                     NSStringFromPoint(point));
                [self writeLatin1EncodedData:[_screen.terminalOutput mouseMotion:MOUSE_BUTTON_NONE
                                                                   withModifiers:modifiers
                                                                              at:coord
                                                                           point:point]
                            broadcastAllowed:NO
                                   reporting:NO];
                return YES;
            }
            break;

        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDragged:
            if (testOnly) {
                switch (_screen.terminalMouseMode) {
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                    case MOUSE_REPORTING_NORMAL:
                        DLog(@"button/all/normal - can report");
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HIGHLIGHT:
                        DLog(@"none/highlight - can't report");
                        break;
                }
                return NO;
            }
            if (([self reportingMouseDownForEventType:eventType] || allowDragBeforeMouseDown) &&
                [_screen.terminalOutput shouldReportMouseMotionAtCoord:coord
                                                             lastCoord:_lastReportedCoord
                                                                 point:point
                                                             lastPoint:_lastReportedPoint]) {
                _lastReportedCoord = coord;
                _lastReportedPoint = point;
                DLog(@"_lastReportedCoord <- %@, _lastReportedPoint <- %@",
                     VT100GridCoordDescription(_lastReportedCoord),
                     NSStringFromPoint(point));
                switch (_screen.terminalMouseMode) {
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        DLog(@"motion/all-motion - will report drag");
                        [self writeLatin1EncodedData:[_screen.terminalOutput mouseMotion:button
                                                                           withModifiers:modifiers
                                                                                      at:coord
                                                                                   point:point]
                                    broadcastAllowed:NO
                                           reporting:NO];
                        // Fall through
                    case MOUSE_REPORTING_NORMAL:
                        DLog(@"normal - do not report drag");
                        // Don't do selection when mouse reporting during a drag, even if the drag
                        // is not reported (the clicks are).
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HIGHLIGHT:
                        DLog(@"none/highlight - do not report drag");
                        break;
                }
            }
            break;

        case NSEventTypeScrollWheel:
            switch (_screen.terminalMouseMode) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    DLog(@"normal/button/all - can report. delta=%@", NSStringFromSize(delta));
                    if (testOnly) {
                        return delta.height != 0;
                    }

                    const CGFloat chosenDelta = (fabs(delta.width) > fabs(delta.height)) ? delta.width : delta.height;
                    int steps;
                    if ([iTermAdvancedSettingsModel proportionalScrollWheelReporting]) {
                        // Cap number of reported scroll events at 32 to prevent runaway redraws.
                        // This is a mostly theoretical concern and the number can grow if it
                        // doesn't seem to be a problem.
                        DLog(@"Cap at 32");
                        steps = MIN(32, fabs(chosenDelta));
                    } else {
                        steps = 1;
                    }
                    if (steps == 1 && [iTermAdvancedSettingsModel doubleReportScrollWheel]) {
                        // This works around what I believe is a bug in tmux or a bug in
                        // how users use tmux. See the thread on tmux-users with subject
                        // "Mouse wheel events and server_client_assume_paste--the perfect storm of bugs?".
                        DLog(@"Double reporting");
                        steps = 2;
                    }
                    if (steps > 0 && (button == MOUSE_BUTTON_SCROLLLEFT || button == MOUSE_BUTTON_SCROLLRIGHT)) {
                        [self showHorizontalScrollInfo];
                    }
                    DLog(@"steps=%d", steps);
                    for (int i = 0; i < steps; i++) {
                        [self writeLatin1EncodedData:[_screen.terminalOutput mousePress:button
                                                                          withModifiers:modifiers
                                                                                     at:coord
                                                                                  point:point]
                                    broadcastAllowed:NO
                                           reporting:NO];
                    }
                    return YES;

                case MOUSE_REPORTING_NONE:
                case MOUSE_REPORTING_HIGHLIGHT:
                    DLog(@"none/highlight - can't report");
                    break;
            }
            break;

        default:
            assert(NO);
            break;
    }
    return NO;
}

- (VT100GridAbsCoordRange)textViewRangeOfLastCommandOutput {
    DLog(@"Fetching range of last command output...");
    if (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        DLog(@"Command history has never been used.");
        [iTermShellHistoryController showInformationalMessageInWindow:_view.window];
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    } else {
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_screen];
        long long absCursorY = _screen.cursorY - 1 + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow;

        if (self.isAtShellPrompt ||
            _screen.startOfRunningCommandOutput.x == -1 ||
            (absCursorY == _screen.startOfRunningCommandOutput.y && _screen.cursorX == 1)) {
            DLog(@"Returning cached range.");
            return [extractor rangeByTrimmingWhitespaceFromRange:_screen.lastCommandOutputRange
                                                         leading:NO
                                                        trailing:iTermTextExtractorTrimTrailingWhitespaceOneLine];
        } else {
            DLog(@"Returning range of current command.");
            VT100GridAbsCoordRange range = VT100GridAbsCoordRangeMake(_screen.startOfRunningCommandOutput.x,
                                                                      _screen.startOfRunningCommandOutput.y,
                                                                      _screen.cursorX - 1,
                                                                      absCursorY);
            return [extractor rangeByTrimmingWhitespaceFromRange:range
                                                         leading:NO
                                                        trailing:iTermTextExtractorTrimTrailingWhitespaceOneLine];
        }
    }
}

- (VT100GridAbsCoordRange)textViewRangeOfCurrentCommand {
    DLog(@"Fetching range of current command");
    if (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed]) {
        DLog(@"Command history has never been used.");
        [iTermShellHistoryController showInformationalMessageInWindow:_view.window];
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    } else {
        VT100GridAbsCoordRange range;
        iTermTextExtractorTrimTrailingWhitespace trailing;
        if (self.isAtShellPrompt) {
            range = VT100GridAbsCoordRangeFromCoordRange(_screen.extendedCommandRange,
                                                         _screen.totalScrollbackOverflow);
            trailing = iTermTextExtractorTrimTrailingWhitespaceAll;
        } else {
            range = _lastOrCurrentlyRunningCommandAbsRange;
            trailing = iTermTextExtractorTrimTrailingWhitespaceOneLine;
        }
        iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_screen];
        return [extractor rangeByTrimmingWhitespaceFromRange:range leading:YES trailing:trailing];
    }
}

- (BOOL)textViewCanSelectOutputOfLastCommand {
    // Return YES if command history has never been used so we can show the informational message.
    return (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed] ||
            _screen.lastCommandOutputRange.start.x >= 0);

}

- (BOOL)textViewCanSelectCurrentCommand {
    // Return YES if command history has never been used so we can show the informational message.
    return (![[iTermShellHistoryController sharedInstance] commandHistoryHasEverBeenUsed] ||
            self.isAtShellPrompt ||
            (_lastOrCurrentlyRunningCommandAbsRange.start.x >= 0 &&
             // It cannot select when the currently running command is lost due to scrollback overflow.
             _lastOrCurrentlyRunningCommandAbsRange.start.y >= _screen.totalScrollbackOverflow));
}

- (iTermUnicodeNormalization)textViewUnicodeNormalizationForm {
    return _screen.config.normalization;
}

- (NSColor *)textViewCursorGuideColor {
    return _cursorGuideColor;
}

- (NSColor *)textViewBadgeColor {
    return [iTermProfilePreferences colorForKey:KEY_BADGE_COLOR dark:_screen.colorMap.darkMode profile:_profile];
}

// Returns a dictionary with only string values by converting non-strings.
- (NSDictionary *)textViewVariables {
    return _variables.stringValuedDictionary;
}

- (iTermVariableScope<iTermSessionScope> *)variablesScope {
    if (_variablesScope == nil) {
        _variablesScope = [iTermVariableScope newSessionScopeWithVariables:self.variables];
    }
    return _variablesScope;
}

- (iTermVariableScope *)genericScope {
    return self.variablesScope;
}

- (BOOL)textViewSuppressingAllOutput {
    return _suppressAllOutput;
}

- (BOOL)textViewIsZoomedIn {
    return _liveSession && !_dvr && !_filter;
}

- (BOOL)textViewIsFiltered {
    return _liveSession && _filter;
}

- (BOOL)textViewInPinnedHotkeyWindow {
    if (![iTermAdvancedSettingsModel showPinnedIndicator]) {
        return NO;
    }
    iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:[PseudoTerminal castFrom:_delegate.realParentWindow]];
    if (!profileHotkey) {
        return NO;
    }
    return !profileHotkey.autoHides;
}

- (BOOL)textViewShouldShowMarkIndicators {
    return [iTermProfilePreferences boolForKey:KEY_SHOW_MARK_INDICATORS inProfile:_profile];
}

- (void)textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:(BOOL)isTrying {
    [self.naggingController tryingToSendArrowKeysWithScrollWheel:isTrying];
}

// Grow or shrink the height of the frame if the number of lines in the data
// source + IME has changed.
- (BOOL)textViewResizeFrameIfNeeded {
    // Check if the frame size needs to grow or shrink.
    NSRect frame = [_textview frame];
    const CGFloat desiredHeight = _textview.desiredHeight;
    if (fabs(desiredHeight - NSHeight(frame)) >= 0.5) {
        // Update the wrapper's size, which in turn updates textview's size.
        frame.size.height = desiredHeight + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];  // The wrapper is always larger by VMARGIN.
        _wrapper.frame = [self safeFrameForWrapperViewFrame:frame];

        NSAccessibilityPostNotification(_textview,
                                        NSAccessibilityRowCountChangedNotification);
        return YES;
    }
    return NO;
}

- (NSInteger)textViewUnicodeVersion {
    return _unicodeVersion;
}

- (void)textViewDidRefresh {
    if (_textview.window.firstResponder != _textview) {
        return;
    }
    iTermTextExtractor *textExtractor = [[[iTermTextExtractor alloc] initWithDataSource:_screen] autorelease];
    NSString *word = [textExtractor fastWordAt:VT100GridCoordMake(_screen.cursorX - 1, _screen.cursorY + _screen.numberOfScrollbackLines - 1)];
    [[_delegate realParentWindow] currentSessionWordAtCursorDidBecome:word];
}

- (void)textViewBackgroundColorDidChangeFrom:(NSColor *)before to:(NSColor *)after {
    DLog(@"%@", [NSThread callStackSymbols]);
    [self backgroundColorDidChangeJigglingIfNeeded:before.isDark != after.isDark];
    [self updateAutoComposerSeparatorVisibility];
    // Can't call this synchronously because we could get here from a side effect and
    // viewDidChangeEffectiveAppearance can cause performBlockWithJoinedThreads to be called.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateAppearanceForMinimalTheme];
    });
}

- (void)themeDidChange {
    [self updateAppearanceForMinimalTheme];
}

- (void)updateAppearanceForMinimalTheme {
    const BOOL minimal = [iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_MINIMAL;
    if (minimal) {
        NSAppearance *appearance = [_screen.colorMap colorForKey:kColorMapBackground].isDark ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        _view.appearance = appearance;
        self.statusBarViewController.view.appearance = appearance;
    } else {
        _view.appearance = nil;
        self.statusBarViewController.view.appearance = nil;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &iTermEffectiveAppearanceKey) {
        DLog(@"System appearance changed to %@", [NSApp effectiveAppearance]);
        const BOOL minimal = [iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_MINIMAL;
        if (minimal && _screen.colorMap.useSeparateColorsForLightAndDarkMode) {
            DLog(@"Manually update view appearance");
            // The view's appearance determines which colors should be used. In minimal, we manually
            // manage the appearance so that window chrome matches up with the background color. To
            // break that dependency cycle, we manually update the appearance for minimal when the
            // system theme changes.
            NSAppearance *desiredAppearance = [self colorMapShouldBeInDarkMode] ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            if ([desiredAppearance.name isEqual:self.view.effectiveAppearance.name]) {
                [self.view updateForAppearanceChange];
            } else {
                self.view.appearance = desiredAppearance;
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }
}

- (BOOL)colorMapShouldBeInDarkMode {
    const BOOL minimal = [iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_MINIMAL;
    if (minimal) {
        NSColor *backgroundColor = [iTermProfilePreferences colorForKey:KEY_BACKGROUND_COLOR
                                                              dark:[NSApp effectiveAppearance].it_isDark
                                                           profile:self.profile];
        DLog(@"dark=%@", @(backgroundColor.isDark));
        return backgroundColor.isDark;
    }
    DLog(@"Not minimal so fall back to view (%@)/app (%@) appearance", self.view.effectiveAppearance, [NSApp effectiveAppearance]);
    return (self.view.effectiveAppearance ?: [NSApp effectiveAppearance]).it_isDark;
}


- (void)textViewTransparencyDidChange {
    [self backgroundColorDidChangeJigglingIfNeeded:NO];
}

- (void)backgroundColorDidChangeJigglingIfNeeded:(BOOL)canJiggle {
    [_delegate sessionBackgroundColorDidChange:self];
    [_delegate sessionUpdateMetalAllowed];
    [_statusBarViewController updateColors];
    [_wrapper setNeedsDisplay:YES];
    [self.view setNeedsDisplay:YES];
    if (canJiggle && _profileInitialized) {
        // See issue 9855.
        self.needsJiggle = YES;
    }
}
- (void)textViewForegroundColorDidChangeFrom:(NSColor *)before to:(NSColor *)after {
    DLog(@"%@", [NSThread callStackSymbols]);
    if (_profileInitialized && before.isDark != after.isDark) {
        self.needsJiggle = YES;
    }
    [_composerManager updateFont];
}

- (void)textViewCursorColorDidChangeFrom:(NSColor *)before to:(NSColor *)after {
    [_composerManager updateFont];
}

- (void)setNeedsJiggle:(BOOL)needsJiggle {
    DLog(@"setNeedsJiggle:%@", @(needsJiggle));
    if (!_initializationFinished) {
        DLog(@"Uninitialized");
        return;
    }
    if (_needsJiggle == needsJiggle) {
        DLog(@"Unchanged");
        return;
    }
    DLog(@"%@", [NSThread callStackSymbols]);
    _needsJiggle = needsJiggle;
    if (!needsJiggle) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self jiggleIfNeeded];
    });
}

- (void)jiggleIfNeeded {
    DLog(@"jiggleIfNeeded");
    if (!_needsJiggle) {
        return;
    }
    _needsJiggle = NO;
    [self jiggle];
}

- (void)textViewProcessedBackgroundColorDidChange {
    [self updateViewBackgroundImage];
}

- (void)textViewBurySession {
    [self bury];
}

- (NSRect)boundingFrameForWindowedRange:(VT100GridWindowedRange)range {
    const NSRect visibleRect = _textview.enclosingScrollView.documentVisibleRect;
    const VT100GridRect gridRect = VT100GridWindowedRangeBoundingRect(range);
    const NSRect topLeft = [_textview rectForCoord:VT100GridRectTopLeft(gridRect)];
    const NSRect topRight = [_textview rectForCoord:VT100GridRectTopRight(gridRect)];
    const NSRect bottomLeft = [_textview rectForCoord:VT100GridRectBottomLeft(gridRect)];
    const NSRect bottomRight = [_textview rectForCoord:VT100GridRectBottomRight(gridRect)];
    const NSRect anchorRect = NSUnionRect(NSUnionRect(NSUnionRect(topLeft, topRight), bottomLeft), bottomRight);
    const NSRect visibleAnchorRect = NSIntersectionRect(anchorRect, visibleRect);
    return [_view convertRect:visibleAnchorRect fromView:_textview];
}

- (BOOL)textViewShowHoverURL:(NSString *)url anchor:(VT100GridWindowedRange)anchor {
    return [_view setHoverURL:url
                  anchorFrame:url ? [self boundingFrameForWindowedRange:anchor] : NSZeroRect];
}

- (BOOL)textViewCopyMode {
    return _modeHandler.mode == iTermSessionModeCopy;
}

- (BOOL)textViewCopyModeSelecting {
    return _modeHandler.copyModeHandler.state.selecting;
}

- (VT100GridCoord)textViewCopyModeCursorCoord {
    return _modeHandler.copyModeHandler.state.coord;
}

- (BOOL)textViewPasswordInput {
    return _passwordInput;
}

- (void)textViewDidSelectPasswordPrompt {
    iTermApplicationDelegate *delegate = [iTermApplication.sharedApplication delegate];
    [delegate openPasswordManagerToAccountName:nil
                                     inSession:self];
}

- (void)textViewDidSelectRangeForFindOnPage:(VT100GridCoordRange)range {
    if (_modeHandler.mode == iTermSessionModeCopy) {
        _modeHandler.copyModeHandler.state.coord = range.start;
        _modeHandler.copyModeHandler.state.start = range.end;
        [self.textview requestDelegateRedraw];
    }
}

- (void)textViewNeedsDisplayInRect:(NSRect)rect {
    DLog(@"text view needs display");
    NSRect visibleRect = NSIntersectionRect(rect, _textview.enclosingScrollView.documentVisibleRect);
    [_view setMetalViewNeedsDisplayInTextViewRect:visibleRect];
    [self updateWrapperAlphaForMetalEnabled:_view.useMetal];
}

- (BOOL)textViewShouldDrawRect {
    // In issue 8843 we see that sometimes the background color can get out of sync. I can't
    // figure it out. This patches the problem until I can collect more info.
    [_view setTerminalBackgroundColor:[self processedBackgroundColor]];
    return !_textview.suppressDrawing;
}

- (void)textViewDidHighlightMark {
    if (self.useMetal) {
        [_textview requestDelegateRedraw];
    }
}

- (NSEdgeInsets)textViewEdgeInsets {
    NSEdgeInsets insets;
    const NSRect innerFrame = _view.scrollview.frame;
    NSSize containerSize;
    containerSize = _view.frame.size;

    insets.bottom = NSMinY(innerFrame);
    insets.top = containerSize.height - NSMaxY(innerFrame);
    insets.left = NSMinX(innerFrame);
    insets.right = containerSize.width - NSMaxX(innerFrame);

    return insets;
}

- (BOOL)textViewInInteractiveApplication {
    return _screen.terminalSoftAlternateScreenMode;
}

// NOTE: Make sure to update both the context menu and the main menu when modifying these.
- (BOOL)textViewTerminalStateForMenuItem:(NSMenuItem *)menuItem {
    switch (menuItem.tag) {
        case 1:
            return _screen.showingAlternateScreen;

        case 2:
            return _screen.terminalReportFocus;

        case 3:
            return _screen.terminalMouseMode != MOUSE_REPORTING_NONE;

        case 4:
            return _screen.terminalBracketedPasteMode;

        case 5:
            return _screen.terminalCursorMode;

        case 6:
            return _screen.terminalKeypadMode;

        case 7:
            return _keyMappingMode == iTermKeyMappingModeStandard;

        case 8:
            return _keyMappingMode == iTermKeyMappingModeModifyOtherKeys1;

        case 9:
            return _keyMappingMode == iTermKeyMappingModeModifyOtherKeys2;

        case 10:
            return _keyMappingMode == iTermKeyMappingModeCSIu;

        case 11:
            return _keyMappingMode == iTermKeyMappingModeRaw;

        case 12:
            return !!(_screen.terminalKeyReportingFlags & VT100TerminalKeyReportingFlagsDisambiguateEscape);
    }

    return NO;
}

- (void)textViewToggleTerminalStateForMenuItem:(NSMenuItem *)menuItem {
    _modeHandler.mode = iTermSessionModeDefault;
    const NSInteger tag = menuItem.tag;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        switch (tag) {
            case 1:
                [terminal toggleAlternateScreen];
                break;

            case 2:
                terminal.reportFocus = !terminal.reportFocus;
                break;

            case 3:
                if (terminal.mouseMode == MOUSE_REPORTING_NONE) {
                    terminal.mouseMode = terminal.previousMouseMode;
                } else {
                    terminal.mouseMode = MOUSE_REPORTING_NONE;
                }
                [terminal.delegate terminalMouseModeDidChangeTo:terminal.mouseMode];
                break;

            case 4:
                terminal.bracketedPasteMode = !terminal.bracketedPasteMode;
                break;

            case 5:
                terminal.cursorMode = !terminal.cursorMode;
                break;

            case 6:
                [terminal forceSetKeypadMode:!terminal.keypadMode];
                break;

            case 7:
                terminal.sendModifiers[4] = @-1;
                self.keyMappingMode = iTermKeyMappingModeStandard;
                break;

            case 8:
                terminal.sendModifiers[4] = @1;
                self.keyMappingMode = iTermKeyMappingModeModifyOtherKeys1;
                break;

            case 9:
                terminal.sendModifiers[4] = @2;
                self.keyMappingMode = iTermKeyMappingModeModifyOtherKeys2;
                break;

            case 10:
                terminal.sendModifiers[4] = @-1;
                self.keyMappingMode = iTermKeyMappingModeCSIu;
                break;

            case 11:
                terminal.sendModifiers[4] = @-1;
                self.keyMappingMode = iTermKeyMappingModeRaw;
                break;

            case 12:
                [terminal toggleDisambiguateEscape];
                [self updateKeyMapper];
                break;
        }
    }];
}

- (void)textViewResetTerminal {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        [terminal gentleReset];
    }];
}

- (CGFloat)textViewBadgeTopMargin {
    return [iTermProfilePreferences floatForKey:KEY_BADGE_TOP_MARGIN inProfile:self.profile];
}

- (CGFloat)textViewBadgeRightMargin {
    return [iTermProfilePreferences floatForKey:KEY_BADGE_RIGHT_MARGIN inProfile:self.profile];
}

- (iTermVariableScope *)textViewVariablesScope {
    return self.variablesScope;
}

- (BOOL)textViewTerminalBackgroundColorDeterminesWindowDecorationColor {
    return self.view.window.ptyWindow.it_terminalWindowUseMinimalStyle;
}

- (void)textViewDidUpdateDropTargetVisibility {
    [self.delegate sessionUpdateMetalAllowed];
}

- (iTermExpect *)textViewExpect {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf sync];
    });
    return _expect;
}

- (void)textViewDidDetectMouseReportingFrustration {
    [self.naggingController didDetectMouseReportingFrustration];
}

- (BOOL)textViewCanBury {
    return !_synthetic;
}

- (void)textViewFindOnPageLocationsDidChange {
    [_view.searchResultsMinimap invalidate];
    [_view.marksMinimap invalidate];
}

- (void)textViewFindOnPageSelectedResultDidChange {
    [_view.findDriver.viewController countDidChange];
}

- (CGFloat)textViewBlend {
    return [self effectiveBlend];
}

- (id<iTermSwipeHandler>)textViewSwipeHandler {
    return [self.delegate sessionSwipeHandler];
}

- (void)textViewAddContextMenuItems:(NSMenu *)menu {
    if (!self.isTmuxClient) {
        return;
    }
    if (!_tmuxController.gateway.pauseModeEnabled) {
        return;
    }
    [menu addItem:[NSMenuItem separatorItem]];
    if (_tmuxPaused) {
        NSMenuItem *item = [menu addItemWithTitle:@"Unpause tmux Pane" action:@selector(toggleTmuxPaused) keyEquivalent:@""];
        item.target = self;
    } else {
        NSMenuItem *item = [menu addItemWithTitle:@"Pause tmux Pane" action:@selector(toggleTmuxPaused) keyEquivalent:@""];
        item.target = self;
    }
}

- (NSString *)textViewShell {
    return self.userShell;
}

- (void)textViewContextMenuInvocation:(NSString *)invocation
                      failedWithError:(NSError *)error
                          forMenuItem:(NSString *)title {
    [PTYSession reportFunctionCallError:error
                          forInvocation:invocation
                                 origin:[NSString stringWithFormat:@"Menu Item “%@”", title]
                                 window:self.view.window];
}

- (void)textViewEditTriggers {
    [self openTriggersViewController];
}

- (void)openTriggersViewController {
    [_triggerWindowController autorelease];
    _triggerWindowController = [[TriggerController alloc] init];
    _triggerWindowController.guid = self.profile[KEY_GUID];
    _triggerWindowController.delegate = self;
    [_triggerWindowController windowWillOpen];
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_triggerWindowController.window completionHandler:^(NSModalResponse returnCode) {
        [weakSelf closeTriggerWindowController];
    }];
}

- (void)textViewToggleEnableTriggersInInteractiveApps {
    const BOOL value = [iTermProfilePreferences boolForKey:KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS inProfile:self.profile];
    [self setSessionSpecificProfileValues:@{ KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS: @(!value) }];
}

- (BOOL)textViewTriggersAreEnabledInInteractiveApps {
    return [iTermProfilePreferences boolForKey:KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS inProfile:self.profile];
}

- (iTermTimestampsMode)textviewTimestampsMode {
    return (iTermTimestampsMode)[iTermProfilePreferences unsignedIntegerForKey:KEY_SHOW_TIMESTAMPS inProfile:self.profile];
}

- (void)textviewToggleTimestampsMode {
    iTermTimestampsMode mode = iTermTimestampsModeOff;
    switch ([self textviewTimestampsMode]) {
        case iTermTimestampsModeOff:
            mode = iTermTimestampsModeOn;
            break;
        case iTermTimestampsModeOn:
        case iTermTimestampsModeHover:
            mode = iTermTimestampsModeOff;
            break;
    }
    [self setSessionSpecificProfileValues:@{ KEY_SHOW_TIMESTAMPS: @(mode) }];
    [_textview requestDelegateRedraw];
}

- (void)textViewSetClickCoord:(VT100GridAbsCoord)coord
                       button:(NSInteger)button
                        count:(NSInteger)count
                    modifiers:(NSEventModifierFlags)modifiers
                  sideEffects:(iTermClickSideEffects)sideEffects
                        state:(iTermMouseState)state {
    self.variablesScope.mouseInfo = @[ @(coord.x), @(coord.y), @(button), @(count), [self apiModifiersForModifierFlags:modifiers], @(sideEffects), @(state) ];
}

- (void)closeTriggerWindowController {
    [_triggerWindowController close];
}

- (void)textViewAddTrigger:(NSString *)text {
    [self openAddTriggerViewControllerWithText:text];
}

- (void)openAddTriggerViewControllerWithText:(NSString *)text {
    __weak __typeof(self) weakSelf = self;
    iTermColorSuggester *cs =
    [[[iTermColorSuggester alloc] initWithDefaultTextColor:[_screen.colorMap colorForKey:kColorMapForeground]
                                    defaultBackgroundColor:[_screen.colorMap colorForKey:kColorMapBackground]
                                         minimumDifference:0.25
                                                      seed:[text hash]] autorelease];
    [iTermAddTriggerViewController addTriggerForText:text
                                              window:self.view.window
                                 interpolatedStrings:[self.profile[KEY_TRIGGERS_USE_INTERPOLATED_STRINGS] boolValue]
                                    defaultTextColor:cs.suggestedTextColor
                              defaultBackgroundColor:cs.suggestedBackgroundColor
                                          completion:^(NSDictionary * _Nonnull dict, BOOL updateProfile) {
        if (!dict) {
            return;
        }
        [weakSelf addTriggerDictionary:dict updateProfile:updateProfile];
    }];
}

- (void)textViewShowFindIndicator:(VT100GridCoordRange)range {
    DLog(@"begin %@", VT100GridCoordRangeDescription(range));
    VT100GridCoordRange visibleRange = range;
    VT100GridRange visibleLines = _textview.rangeOfVisibleLines;
    if (visibleRange.start.y > VT100GridRangeMax(visibleLines) ||
        visibleRange.end.y < visibleLines.location) {
        return;
    }
    if (visibleRange.start.y < visibleLines.location) {
        visibleRange.start.y = visibleLines.location;
        visibleRange.start.x = 0;
    }
    if (visibleRange.end.y > VT100GridRangeMax(visibleLines)) {
        visibleRange.end.y = VT100GridRangeMax(visibleLines);
        visibleRange.end.x = _screen.width;
    }
    int minX = visibleRange.start.x;
    int maxX = visibleRange.end.x;
    if (visibleRange.start.y != visibleRange.end.y) {
        minX = 0;
        maxX = _screen.width;
    }
    const int hmargin = [iTermPreferences intForKey:kPreferenceKeySideMargins];
    const int vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    const int rows = visibleRange.end.y - visibleRange.start.y + 1;
    const VT100GridSize gridSize = VT100GridSizeMake(maxX - minX, rows);
    const CGFloat cellWidth = [_textview charWidth];
    const CGFloat cellHeight = [_textview lineHeight];
    const NSSize padding = iTermTextClipDrawing.padding;
    const NSSize imageSize = NSMakeSize(_screen.width * cellWidth + padding.width * 2,
                                        gridSize.height * cellHeight + padding.height * 2);
    NSImage *image = [NSImage flippedImageOfSize:imageSize drawBlock:^{
        [NSGraphicsContext.currentContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:padding.width yBy:padding.height];
        [transform concat];
        [iTermTextClipDrawing drawClipWithDrawingHelper:_textview.drawingHelper
                                        numHistoryLines:_screen.numberOfScrollbackLines
                                                  range:visibleRange];
        [NSGraphicsContext.currentContext restoreGraphicsState];
    }];
    const NSRect subrect = NSMakeRect(hmargin + minX * cellWidth,
                                      0,
                                      (maxX - minX) * cellWidth + padding.width * 2,
                                      rows * cellHeight + padding.height * 2);
    NSImage *cropped = [image it_subimageWithRect:subrect];
    // The rect in legacyView that matches `subrect`.
    NSRect sourceRect =
    NSMakeRect(subrect.origin.x - padding.width,
               (visibleRange.start.y - visibleLines.location) * _textview.lineHeight + vmargin - padding.height,
               cropped.size.width,
               cropped.size.height);

    const NSEdgeInsets shadowInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    NSImage *shadowed = [NSImage flippedImageOfSize:NSMakeSize(subrect.size.width + shadowInsets.left + shadowInsets.right,
                                                               subrect.size.height + shadowInsets.top + shadowInsets.bottom)
                                          drawBlock:^{
        NSShadow *shadow = [[[NSShadow alloc] init] autorelease];

        shadow.shadowOffset = NSMakeSize(0, 0);
        shadow.shadowBlurRadius = 4;
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.4];
        [shadow set];

        [cropped drawInRect:NSMakeRect(shadowInsets.left,
                                       shadowInsets.top,
                                       cropped.size.width,
                                       cropped.size.height)];

        // Draw again with a smaller shadow to act as an outline.
        shadow = [[[NSShadow alloc] init] autorelease];

        shadow.shadowOffset = NSMakeSize(0, 0);
        shadow.shadowBlurRadius = 1;
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.6];
        [shadow set];

        [cropped drawInRect:NSMakeRect(shadowInsets.left,
                                       shadowInsets.top,
                                       cropped.size.width,
                                       cropped.size.height)];
    }];
    sourceRect.origin.x -= shadowInsets.left;
    sourceRect.origin.y -= shadowInsets.top;
    sourceRect.size.width += shadowInsets.left + shadowInsets.right;
    sourceRect.size.height += shadowInsets.top + shadowInsets.bottom;
    FindIndicatorWindow *window =
    [FindIndicatorWindow showWithImage:shadowed
                                  view:_view.legacyView
                                  rect:sourceRect
                      firstVisibleLine:visibleLines.location + _screen.totalScrollbackOverflow];
    if (window) {
        [_textview trackChildWindow:window];
    }
}

- (BOOL)textViewCanWriteToTTY {
    return !_exited;
}

- (void)addTriggerDictionary:(NSDictionary *)dict updateProfile:(BOOL)updateProfile {
    if (!updateProfile || !self.isDivorced || [_overriddenFields containsObject:KEY_TRIGGERS]) {
        NSMutableArray<NSDictionary *> *triggers = [[self.profile[KEY_TRIGGERS] ?: @[] mutableCopy] autorelease];
        [triggers addObject:dict];
        [self setSessionSpecificProfileValues:@{ KEY_TRIGGERS: triggers }];
    }

    if (!updateProfile) {
        return;
    }
    NSString *guid;
    if (self.isDivorced) {
        guid = self.profile[KEY_ORIGINAL_GUID];
    } else {
        guid = self.profile[KEY_GUID];
    }
    MutableProfile *profile = [[[[ProfileModel sharedInstance] bookmarkWithGuid:guid] mutableCopy] autorelease];
    if (!profile) {
        return;
    }
    profile[KEY_TRIGGERS] = [profile[KEY_TRIGGERS] ?: @[] arrayByAddingObject:dict];
    [[ProfileModel sharedInstance] setBookmark:profile withGuid:profile[KEY_GUID]];
}

- (void)textViewApplyAction:(iTermAction *)action {
    [self applyAction:action];
}

- (void)textViewhandleSpecialKeyDown:(NSEvent *)event {
    if (_keystrokeSubscriptions.count) {
        [self sendKeystrokeNotificationForEvent:event advanced:NO];
    }
}

- (NSString *)userShell {
    return [ITAddressBookMgr customShellForProfile:self.profile] ?: [iTermOpenDirectory userShell] ?: @"/bin/bash";
}

- (void)toggleTmuxPaused {
    if (_tmuxPaused) {
        [self setTmuxPaused:NO allowAutomaticUnpause:NO];
    } else {
        [self.tmuxController pausePanes:@[ @(self.tmuxPane) ]];
    }
}

- (void)bury {
    DLog(@"Bury %@", self);
    if (_synthetic) {
        DLog(@"Attempt to bury while synthetic");
        return;
    }
    if (self.isTmuxClient) {
        DLog(@"Is tmux");
        if (!self.delegate) {
            return;
        }
        [_tmuxController hideWindow:self.delegate.tmuxWindow];
        return;
    }
    [_textview setDataSource:nil];
    [_textview setDelegate:nil];
    [[iTermBuriedSessions sharedInstance] addBuriedSession:self];
    [_delegate sessionRemoveSession:self];

    _delegate = nil;
}

- (void)sendEscapeSequence:(NSString *)text
{
    if (_exited) {
        return;
    }
    if ([text length] > 0) {
        NSString *aString = [NSString stringWithFormat:@"\e%@", text];
        [self writeTask:aString];
    }
}

- (NSData *)dataForHexCodes:(NSString *)codes {
    NSMutableData *data = [NSMutableData data];
    NSArray* components = [codes componentsSeparatedByString:@" "];
    for (NSString* part in components) {
        const char* utf8 = [part UTF8String];
        char* endPtr;
        unsigned char c = strtol(utf8, &endPtr, 16);
        if (endPtr != utf8) {
            [data appendData:[NSData dataWithBytes:&c length:sizeof(c)]];
        }
    }
    return data;
}

- (void)sendHexCode:(NSString *)codes {
    if (_exited) {
        return;
    }
    if ([codes length]) {
        [self writeLatin1EncodedData:[self dataForHexCodes:codes]
                    broadcastAllowed:YES
                           reporting:NO];
    }
}

- (void)openAdvancedPasteWithText:(NSString *)text escaping:(iTermSendTextEscaping)escaping {
    NSString *escaped = [self escapedText:text mode:escaping];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:self];
    [pasteboard setString:escaped forType:NSPasteboardTypeString];
    [_pasteHelper showAdvancedPasteWithFlags:0];
}

- (void)openComposerWithString:(NSString *)text escaping:(iTermSendTextEscaping)escaping {
    NSString *escaped = [self escapedText:text mode:escaping];
    [self.composerManager showOrAppendToDropdownWithString:escaped];
}

- (void)sendText:(NSString *)text escaping:(iTermSendTextEscaping)escaping {
    DLog(@"sendText:%@ escaping:%@",
         text,
         @(escaping));
    if (_exited) {
        DLog(@"Already exited");
        return;
    }
    if (![text isKindOfClass:[NSString class]]) {
        DLog(@"Not a string: %@", text);
    }
    if ([text length] == 0) {
        return;
    }
    [self writeTask:[self escapedText:text mode:escaping]];
}

- (NSString *)escapedText:(NSString *)text mode:(iTermSendTextEscaping)escaping {
    NSString *temp = text;
    switch (escaping) {
        case iTermSendTextEscapingNone:
            return text;
        case iTermSendTextEscapingCommon:
            return [temp stringByReplacingCommonlyEscapedCharactersWithControls];
        case iTermSendTextEscapingCompatibility:
            temp = [temp stringByReplacingEscapedChar:'n' withString:@"\n"];
            temp = [temp stringByReplacingEscapedChar:'e' withString:@"\e"];
            temp = [temp stringByReplacingEscapedChar:'a' withString:@"\a"];
            temp = [temp stringByReplacingEscapedChar:'t' withString:@"\t"];
            return temp;
        case iTermSendTextEscapingVimAndCompatibility:
            temp = [temp stringByExpandingVimSpecialCharacters];
            temp = [temp stringByReplacingEscapedChar:'n' withString:@"\n"];
            temp = [temp stringByReplacingEscapedChar:'e' withString:@"\e"];
            temp = [temp stringByReplacingEscapedChar:'a' withString:@"\a"];
            temp = [temp stringByReplacingEscapedChar:'t' withString:@"\t"];
            return temp;
        case iTermSendTextEscapingVim:
            return [temp stringByExpandingVimSpecialCharacters];
    }
    assert(NO);
    return @"";
}

- (void)sendTextSlowly:(NSString *)text {
    PasteEvent *event = [_pasteHelper pasteEventWithString:text
                                                    slowly:NO
                                          escapeShellChars:NO
                                                  isUpload:NO
                                           allowBracketing:YES
                                              tabTransform:NO
                                              spacesPerTab:0
                                                  progress:^(NSInteger progress) {}];
    event.defaultChunkSize = 80;
    event.defaultDelay = 0.02;
    event.chunkKey = @"";
    event.delayKey = @"";
    event.flags = kPasteFlagsDisableWarnings;
    [_pasteHelper tryToPasteEvent:event];
}

- (void)launchCoprocessWithCommand:(NSString *)command
{
    [self launchCoprocessWithCommand:command mute:NO];
}

- (void)uploadFiles:(NSArray *)localFilenames toPath:(SCPPath *)destinationPath
{
    SCPFile *previous = nil;
    for (NSString *file in localFilenames) {
        SCPPath *path = [[[SCPPath alloc] init] autorelease];
        path.hostname = destinationPath.hostname;
        path.username = destinationPath.username;
        NSString *filename = [file lastPathComponent];
        path.path = [destinationPath.path stringByAppendingPathComponent:filename];

        if (@available(macOS 11, *)) {
            if ([_conductor canTransferFilesTo:path]) {
                [_conductor uploadFile:file to:path];
                break;
            }
        }
        SCPFile *scpFile = [[[SCPFile alloc] init] autorelease];
        scpFile.path = path;
        scpFile.localPath = file;

        if (previous) {
            previous.successor = scpFile;
        }
        previous = scpFile;
        [scpFile upload];
    }
}

- (BOOL)textViewCanUploadOverSSHIntegrationTo:(SCPPath *)path {
    if (@available(macOS 11, *)) {
        return [_conductor canTransferFilesTo:path];
    }
    return NO;
}

- (void)startDownloadOverSCP:(SCPPath *)path
{
    if (@available(macOS 11, *)) {
        if ([_conductor canTransferFilesTo:path]) {
            [_conductor download:path];
            return;
        }
    }
    SCPFile *file = [[[SCPFile alloc] init] autorelease];
    file.path = path;
    [file download];
}

- (void)setDvrFrame {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        const screen_char_t *s = (const screen_char_t *)[_dvrDecoder decodedFrame];
        const int len = [_dvrDecoder screenCharArrayLength];
        DVRFrameInfo info = [_dvrDecoder info];
        if (info.width != mutableState.width || info.height != mutableState.height) {
            if (![_liveSession isTmuxClient]) {
                [[_delegate realParentWindow] sessionInitiatedResize:self
                                                               width:info.width
                                                              height:info.height];
            }
        }
        NSData *data = [NSData dataWithBytes:s length:len];
        NSMutableArray<NSArray *> *metadataArrays = [NSMutableArray mapIntegersFrom:0 to:info.height block:^id(NSInteger i) {
            NSData *data = [_dvrDecoder metadataForLine:i];
            return iTermMetadataArrayFromData(data) ?: @[];
        }];

        if (_dvrDecoder.migrateFromVersion > 0) {
            const int lineCount = (info.width + 1);
            NSMutableData *replacement = [NSMutableData data];
            for (int y = 0; y < info.height; y++) {
                NSData *legacyData = [NSData dataWithBytes:s + lineCount * y
                                                    length:lineCount * sizeof(legacy_screen_char_t)];
                NSData *modernData;
                switch (_dvrDecoder.migrateFromVersion) {
                    case 1: {
                        iTermMetadata temp = { 0 };
                        iTermMetadataInitFromArray(&temp, metadataArrays[y]);
                        iTermMetadataAutorelease(temp);
                        iTermExternalAttributeIndex *originalIndex = iTermMetadataGetExternalAttributesIndex(temp);
                        iTermExternalAttributeIndex *eaIndex = originalIndex;
                        modernData = [legacyData migrateV1ToV3:&eaIndex];
                        if (!originalIndex && eaIndex) {
                            iTermMetadataSetExternalAttributes(&temp, eaIndex);
                            metadataArrays[y] = iTermMetadataEncodeToArray(temp);
                        }
                        break;
                    }
                    case 2:
                        modernData = [legacyData migrateV2ToV3];
                        break;
                    case 3:
                        modernData = legacyData;
                        break;
                    default:
                        DLog(@"Unexpected source version %@", @(_dvrDecoder.migrateFromVersion));
                        modernData = legacyData;
                        break;
                }
                [replacement appendData:modernData];
            }
            data = replacement;
        }
        [mutableState setFromFrame:(screen_char_t *)data.bytes
                               len:data.length
                          metadata:metadataArrays
                              info:info];
        [[_delegate realParentWindow] clearTransientTitle];
        [[_delegate realParentWindow] setWindowTitle];
    }];
}

- (void)continueTailFind {
    NSMutableArray<SearchResult *> *results = [NSMutableArray array];
    BOOL more;
    VT100GridAbsCoordRange rangeSearched = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    NSRange ignore;
    more = [_screen continueFindAllResults:results
                                  rangeOut:&ignore
                                 inContext:_tailFindContext
                              absLineRange:_textview.findOnPageHelper.absLineRange
                             rangeSearched:&rangeSearched];
    DLog(@"Continue tail find found %@ results, more=%@", @(results.count), @(more));
    if (VT100GridAbsCoordRangeIsValid(rangeSearched)) {
        [_textview removeSearchResultsInRange:rangeSearched];
    }
    for (SearchResult *r in results) {
        [_textview addSearchResult:r];
    }
    if ([results count]) {
        [_textview requestDelegateRedraw];
    }
    if (more) {
        DLog(@"Schedule continueTailFind in .01 sec");
        _tailFindTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                          target:self
                                                        selector:@selector(continueTailFind)
                                                        userInfo:nil
                                                         repeats:NO];
    } else {
        DLog(@"tailfind is all done");
        // Update the saved position to just before the screen.
        [_screen storeLastPositionInLineBufferAsFindContextSavedPosition];
        _tailFindTimer = nil;
        _performingOneShotTailFind = NO;
    }
}

- (void)beginContinuousTailFind {
    DLog(@"beginContinuousTailFind");
    _performingOneShotTailFind = NO;
    [self beginTailFindImpl];
}

- (void)beginOneShotTailFind {
    DLog(@"beginOneShotTailFind");
    if (_tailFindTimer || _performingOneShotTailFind) {
        return;
    }
    _performingOneShotTailFind = YES;
    if (![self beginTailFindImpl]) {
        _performingOneShotTailFind = NO;
    }
}

- (BOOL)beginTailFindImpl {
    DLog(@"beginTailFindImpl");
    FindContext *findContext = [_textview findContext];
    if (!findContext.substring) {
        return NO;
    }
    DLog(@"Begin tail find");
    [_screen setFindString:findContext.substring
          forwardDirection:YES
                      mode:findContext.mode
               startingAtX:0
               startingAtY:0
                withOffset:0
                 inContext:_tailFindContext
           multipleResults:YES
              absLineRange:_textview.findOnPageHelper.absLineRange];

    // Set the starting position to the block & offset that the backward search
    // began at. Do a forward search from that location.
    [_screen restoreSavedPositionToFindContext:_tailFindContext];
    [self continueTailFind];
    return YES;
}

- (void)sessionContentsChanged:(NSNotification *)notification {
    if (!_tailFindTimer &&
        [notification object] == self &&
        [_delegate sessionBelongsToVisibleTab]) {
        DLog(@"Session contents changed. Begin tail find.");
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf startTailFindIfVisible];
        });
    }
}

- (void)stopTailFind
{
    if (_tailFindTimer) {
        _tailFindContext.substring = nil;
        _tailFindContext.results = nil;
        [_tailFindTimer invalidate];
        _tailFindTimer = nil;
    }
}

- (void)printTmuxMessage:(NSString *)message {
    DLog(@"%@", message);
    if (_exited) {
        return;
    }
    // Use mutateAsync because you get here from a side-effect.
    [_screen mutateAsynchronously:^(VT100Terminal *terminal,
                                    VT100ScreenMutableState *mutableState,
                                    id<VT100ScreenDelegate> delegate) {
        screen_char_t savedFgColor = [terminal foregroundColorCode];
        screen_char_t savedBgColor = [terminal backgroundColorCode];
        [terminal setForegroundColor:ALTSEM_DEFAULT
                  alternateSemantics:YES];
        [terminal setBackgroundColor:ALTSEM_DEFAULT
                  alternateSemantics:YES];
        [terminal updateDefaultChar];
        mutableState.currentGrid.defaultChar = terminal.defaultChar;
        [mutableState appendStringAtCursor:message];
        [mutableState appendCarriageReturnLineFeed];
        [terminal setForegroundColor:savedFgColor.foregroundColor
                  alternateSemantics:savedFgColor.foregroundColorMode == ColorModeAlternate];
        [terminal setBackgroundColor:savedBgColor.backgroundColor
                  alternateSemantics:savedBgColor.backgroundColorMode == ColorModeAlternate];
        [terminal updateDefaultChar];
        mutableState.currentGrid.defaultChar = terminal.defaultChar;
    }];
}

- (void)printTmuxCommandOutputToScreen:(NSString *)response
{
    for (NSString *aLine in [response componentsSeparatedByString:@"\n"]) {
        aLine = [aLine stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        [self printTmuxMessage:aLine];
    }
}

#pragma mark - VT100ScreenDelegate

- (void)screenScheduleRedrawSoon {
    self.active = YES;
}

- (void)screenResetTailFind {
    _screen.savedFindContextAbsPos = 0;
}

- (void)screenNeedsRedraw {
    DLog(@"screenNeedsRedraw");
    [self refresh];
    [_textview updateSubviewFrames];
}

- (void)screenUpdateDisplay:(BOOL)redraw {
    [self updateDisplayBecause:[NSString stringWithFormat:@"screen requested update redraw=%@", @(redraw)]];
    if (redraw) {
        [_textview requestDelegateRedraw];
    }
}

- (void)screenRefreshFindOnPageView {
    [_view.findDriver.viewController countDidChange];
}

- (void)screenSizeDidChangeWithNewTopLineAt:(int)newTop {
    if ([(PTYScroller*)([_view.scrollview verticalScroller]) userScroll] && newTop >= 0) {
        const VT100GridRange range = VT100GridRangeMake(newTop,
                                                        _textview.rangeOfVisibleLines.length);
        [_textview scrollLineNumberRangeIntoView:range];
    } else {
        [_textview scrollEnd];
    }

    [_textview updateNoteViewFrames];
    [_textview updatePortholeFrames];
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionColumns: @(_screen.width),
                                                    iTermVariableKeySessionRows: @(_screen.height) }];
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (void)screenDidReset {
    _cursorGuideSettingHasChanged = NO;
    _textview.highlightCursorLine = [iTermProfilePreferences boolForColorKey:KEY_USE_CURSOR_GUIDE
                                                                        dark:_screen.colorMap.darkMode
                                                                     profile:_profile];
    self.cursorTypeOverride = nil;
    [_textview requestDelegateRedraw];
    [self restoreColorsFromProfile];
    _screen.trackCursorLineMovement = NO;
}

- (void)restoreColorsFromProfile {
    NSMutableDictionary<NSString *, id> *change = [NSMutableDictionary dictionary];
    for (NSString *key in [[_screen.colorMap colormapKeyToProfileKeyDictionary] allValues]) {
        if (![_overriddenFields containsObject:key]) {
            continue;
        }
        id profileValue = self.originalProfile[key] ?: [NSNull null];
        change[key] = profileValue;
    }
    if (change.count == 0) {
        return;
    }
    [self setSessionSpecificProfileValues:change];
}

// If plainText is false then it's a control code.
- (void)screenDidAppendStringToCurrentLine:(NSString * _Nonnull)string
                               isPlainText:(BOOL)plainText
                                foreground:(screen_char_t)fg
                                background:(screen_char_t)bg
                                  atPrompt:(BOOL)atPrompt {
    if (plainText) {
        [self logCooked:[string dataUsingEncoding:_screen.terminalEncoding]
             foreground:fg
             background:bg
               atPrompt:atPrompt];
    }
}

- (void)logCooked:(NSData *)data
       foreground:(screen_char_t)fg
       background:(screen_char_t)bg
         atPrompt:(BOOL)atPrompt {
    if (!_logging.enabled) {
        return;
    }
    if (self.isTmuxGateway) {
        return;
    }
    switch (_logging.style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStyleAsciicast:
            break;
        case iTermLoggingStylePlainText:
            if ([iTermAdvancedSettingsModel smartLoggingWithAutoComposer]) {
              if (!atPrompt || ![iTermPreferences boolForKey:kPreferenceAutoComposer]) {
                  [_logging logData:data];
              }
            } else {
                [_logging logData:data];
            }
            break;
        case iTermLoggingStyleHTML:
            if ([iTermAdvancedSettingsModel smartLoggingWithAutoComposer]) {
                if (!atPrompt || ![iTermPreferences boolForKey:kPreferenceAutoComposer]) {
                    [_logging logData:[data htmlDataWithForeground:fg
                                                        background:bg
                                                          colorMap:_screen.colorMap
                                                useCustomBoldColor:_textview.useCustomBoldColor
                                                      brightenBold:_textview.brightenBold]];
                }
            } else {
                [_logging logData:[data htmlDataWithForeground:fg
                                                    background:bg
                                                      colorMap:_screen.colorMap
                                            useCustomBoldColor:_textview.useCustomBoldColor
                                                  brightenBold:_textview.brightenBold]];
            }
            break;
    }
}

- (void)screenDidAppendAsciiDataToCurrentLine:(NSData *)asciiData
                                   foreground:(screen_char_t)fg
                                   background:(screen_char_t)bg
                                     atPrompt:(BOOL)atPrompt {
    if (_logging.enabled) {
        [self logCooked:asciiData
             foreground:fg
             background:bg
               atPrompt:atPrompt];
    }
}

- (void)screenRevealComposerWithPrompt:(NSArray<ScreenCharArray *> *)prompt {
    _promptStateAllowsAutoComposer = YES;
    if ([iTermPreferences boolForKey:kPreferenceAutoComposer]) {
        if (_initializationFinished) {
            if (![self haveAutoComposer]) {
                [_composerManager reset];
                [self revealAutoComposerWithPrompt:prompt];
            }
        } else {
            _desiredComposerPrompt = [prompt copy];
        }
    }
}

- (void)screenDismissComposer {
    _promptStateAllowsAutoComposer = NO;
    if (_initializationFinished) {
        [self.composerManager dismissAnimated:NO];
    } else {
        [_desiredComposerPrompt release];
        _desiredComposerPrompt = nil;
    }
    [_textview requestDelegateRedraw];
}

- (void)screenAppendStringToComposer:(NSString *)string {
    if (self.haveAutoComposer) {
        DLog(@"Append to composer: %@", string);
        [_composerManager insertText:string];
        _composerManager.haveShellProvidedText = YES;
    }
}

- (void)screenSetCursorType:(ITermCursorType)newType {
    ITermCursorType type = newType;
    if (type == CURSOR_DEFAULT) {
        self.cursorTypeOverride = nil;
    } else {
        self.cursorTypeOverride = [@(type) retain];
    }
}

- (void)screenSetCursorBlinking:(BOOL)blink {
    if (![iTermProfilePreferences boolForKey:KEY_ALLOW_CHANGE_CURSOR_BLINK inProfile:self.profile]) {
        return;
    }
    // This doesn't update the profile because we want reset to be able to restore it to the
    // profile's value. It does mean the session profile won't reflect that the cursor is blinking.
    self.textview.blinkingCursor = blink;
}

- (BOOL)screenCursorIsBlinking {
    return self.textview.blinkingCursor;
}

- (void)screenResetCursorTypeAndBlink {
    self.cursorTypeOverride = nil;
    self.textview.blinkingCursor = [iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:self.profile];
}

- (void)screenGetCursorType:(ITermCursorType *)cursorTypeOut
                   blinking:(BOOL *)blinking {
    *cursorTypeOut = self.cursorType;
    *blinking = self.textview.blinkingCursor;
}

- (BOOL)screenShouldInitiateWindowResize {
    return ![[[self profile] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue];
}

- (void)screenResizeToWidth:(int)width height:(int)height {
    [_delegate sessionInitiatedResize:self width:width height:height];
}

- (void)screenSetSize:(VT100GridSize)proposedSize {
    if (![self screenShouldInitiateWindowResize]) {
        return;
    }
    if ([[_delegate parentWindow] anyFullScreen]) {
        return;
    }
    int rows = proposedSize.width;
    const VT100GridSize windowSize = [self windowSizeInCells];
    if (rows == -1) {
        rows = _screen.height;
    } else if (rows == 0) {
        rows = windowSize.height;
    }

    int columns = proposedSize.height;
    if (columns == -1) {
        columns = _screen.width;
    } else if (columns == 0) {
        columns = windowSize.width;
    }
    [_delegate sessionInitiatedResize:self width:columns height:rows];
}

- (VT100GridSize)windowSizeInCells {
    VT100GridSize result;
    const NSRect screenFrame = [self screenWindowScreenFrame];
    const NSRect windowFrame = [self screenWindowFrame];
    const NSSize cellSize = [self screenCellSize];
    {
        const CGFloat roomToGrow = screenFrame.size.height - windowFrame.size.height;
        result.height = round(_screen.height + roomToGrow / cellSize.height);
    }
    {
        const CGFloat roomToGrow = screenFrame.size.width - windowFrame.size.width;
        result.width = round(_screen.width + roomToGrow / cellSize.width);
    }
    return result;
}

- (void)screenSetPointSize:(NSSize)proposedSize {
    if (![self screenShouldInitiateWindowResize]) {
        return;
    }
    if ([self screenWindowIsFullscreen]) {
        return;
    }
    // TODO: Only allow this if there is a single session in the tab.
    const NSRect frame = [self screenWindowFrame];
    const NSRect screenFrame = [self screenWindowScreenFrame];
    CGFloat width = proposedSize.width;
    if (width < 0) {
        width = frame.size.width;
    } else if (width == 0) {
        width = screenFrame.size.width;
    }

    CGFloat height = proposedSize.height;
    if (height < 0) {
        height = frame.size.height;
    } else if (height == 0) {
        height = screenFrame.size.height;
    }
    [[_delegate realParentWindow] setFrameSize:NSMakeSize(width, height)];
}

- (void)screenPrintStringIfAllowed:(NSString *)string
                        completion:(void (^)(void))completion {
    // Dispatch because this may show an alert and you can't have a runloop in a side effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reallyTryToPrintString:string];
        completion();
    });
}

- (void)reallyTryToPrintString:(NSString *)string {
    if (![self shouldBeginPrinting:YES]) {
        return;
    }
    if (string.length > 0) {
        [[self textview] printContent:string];
    }
}

- (BOOL)shouldBeginPrinting:(BOOL)willPrint {
    if (!_printGuard) {
        _printGuard = [[iTermPrintGuard alloc] init];
    }
    return [_printGuard shouldPrintWithProfile:self.profile
                                      inWindow:self.view.window
                                     willPrint:willPrint];
}

- (void)screenSetWindowTitle:(NSString *)title {
    // The window name doesn't normally serve as an interpolated string, but just to be extra safe
    // break up \(.
    title = [title stringByReplacingOccurrencesOfString:@"\\(" withString:@"\\\u200B("];
    [self setWindowTitle:title];
    [self.delegate sessionDidSetWindowTitle:title];
}

- (NSString *)screenWindowTitle {
    return [self windowTitle];
}

- (NSString *)screenIconTitle {
    return [self.variablesScope valueForVariableName:iTermVariableKeySessionIconName] ?: [self.variablesScope valueForVariableName:iTermVariableKeySessionName];
}

- (void)screenSetIconName:(NSString *)theName {
    DLog(@"screenSetIconName:%@", theName);
    // Put a zero-width space in between \ and ( to avoid interpolated strings coming from the server.
    theName = [theName stringByReplacingOccurrencesOfString:@"\\(" withString:@"\\\u200B("];
    [self setIconName:theName];
    __weak __typeof(self) weakSelf = self;
    // Avoid changing the profile in a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"Deferred enableSessionNameTitleComponentIfPossible");
        [weakSelf enableSessionNameTitleComponentIfPossible];
    });
}

- (void)screenSetSubtitle:(NSString *)subtitle {
    DLog(@"screenSetSubtitle:%@", subtitle);
    // Put a zero-width space in between \ and ( to avoid interpolated strings coming from the server.
    NSString *safeSubtitle = [subtitle stringByReplacingOccurrencesOfString:@"\\(" withString:@"\\\u200B("];
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"Really set subtitle of %@ to %@", weakSelf, safeSubtitle);
        [weakSelf setSessionSpecificProfileValues:@{ KEY_SUBTITLE: safeSubtitle }];
    });
}

- (void)enableSessionNameTitleComponentIfPossible {
    // Turn on the session name component so the icon/trigger name will be visible.
    iTermTitleComponents components = [iTermProfilePreferences unsignedIntegerForKey:KEY_TITLE_COMPONENTS
                                                                           inProfile:self.profile];
    if (components & iTermTitleComponentsCustom) {
        return;
    }
    if (components & (iTermTitleComponentsSessionName | iTermTitleComponentsProfileAndSessionName | iTermTitleComponentsTemporarySessionName)) {
        return;
    }
    components |= iTermTitleComponentsTemporarySessionName;
    [self setSessionSpecificProfileValues:@{ KEY_TITLE_COMPONENTS: @(components) }];

}

- (void)resetSessionNameTitleComponents {
    iTermTitleComponents components = [iTermProfilePreferences unsignedIntegerForKey:KEY_TITLE_COMPONENTS
                                                                           inProfile:self.profile];
    components &= ~iTermTitleComponentsTemporarySessionName;
    [self setSessionSpecificProfileValues:@{ KEY_TITLE_COMPONENTS: @(components) }];
}

- (BOOL)screenWindowIsFullscreen {
    return [[_delegate parentWindow] anyFullScreen];
}

- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point {
    NSRect screenFrame = [self screenWindowScreenFrame];
    point.x += screenFrame.origin.x;
    point.y = screenFrame.origin.y + screenFrame.size.height - point.y;
    [[_delegate parentWindow] windowSetFrameTopLeftPoint:point];
}

- (NSRect)screenWindowScreenFrame {
    return [[[_delegate parentWindow] windowScreen] visibleFrame];
}

- (NSRect)windowFrame {
    NSRect frame = [self screenWindowFrame];
    NSRect screenFrame = [self screenWindowScreenFrame];
    return NSMakeRect(frame.origin.x - screenFrame.origin.x,
                      (screenFrame.origin.y + screenFrame.size.height) - (frame.origin.y + frame.size.height),
                      frame.size.width,
                      frame.size.height);
}

- (VT100GridSize)theoreticalGridSize {
    //  TODO: WTF do we do with panes here?
    VT100GridSize result;
    NSRect screenFrame = [self screenWindowScreenFrame];
    NSRect windowFrame = [self screenWindowFrame];
    NSSize cellSize = [self screenCellSize];
    {
        const CGFloat roomToGrow = screenFrame.size.height - windowFrame.size.height;
        result.height = _screen.height + roomToGrow / cellSize.height;
    }
    {
        const CGFloat roomToGrow = screenFrame.size.width - windowFrame.size.width;
        result.width = _screen.width + roomToGrow / cellSize.width;
    }
    return result;
}

// If flag is set, miniaturize; otherwise, deminiaturize.
- (void)screenMiniaturizeWindow:(BOOL)flag {
    if (flag) {
        [[_delegate parentWindow] windowPerformMiniaturize:nil];
    } else {
        [[_delegate parentWindow] windowDeminiaturize:nil];
    }
}

// If flag is set, bring to front; if not, move to back.
- (void)screenRaise:(BOOL)flag {
    if (flag) {
        [[_delegate parentWindow] windowOrderFront:nil];
    } else {
        [[_delegate parentWindow] windowOrderBack:nil];
    }
}

// Sets current session proxy icon.
- (void)screenSetPreferredProxyIcon:(NSString *)value {
    NSURL *url = nil;
    if (value) {
        url = [NSURL URLWithString:value];
    }
    self.preferredProxyIcon = url;
    [_delegate sessionProxyIconDidChange:self];
}

- (BOOL)screenWindowIsMiniaturized {
    return [[_delegate parentWindow] windowIsMiniaturized];
}

- (void)screenSendReportData:(NSData *)data {
    if (_shell == nil) {
        return;
    }
    if (self.tmuxMode == TMUX_GATEWAY) {
        // Prevent joining threads when writing the tmux message. Also, this doesn't make sense to do.
        return;
    }
    [self writeLatin1EncodedData:data broadcastAllowed:NO reporting:YES];
}

- (void)screenDidSendAllPendingReports {
    [self sendDataQueue];
}

- (void)sendDataQueue {
    for (NSData *data in _dataQueue) {
        DLog(@"Send deferred write of %@", [data stringWithEncoding:NSUTF8StringEncoding]);
        [self writeData:data];
    }
    [_dataQueue removeAllObjects];
}

- (NSRect)screenWindowFrame {
    return [[_delegate parentWindow] windowFrame];
}

- (NSSize)screenSize {
    return [[[[[_delegate parentWindow] currentSession] view] scrollview] documentVisibleRect].size;
}

// If the flag is set, push the window title; otherwise push the icon title.
- (void)screenPushCurrentTitleForWindow:(BOOL)flag {
    if (flag) {
        [self pushWindowTitle];
    } else {
        [self pushIconTitle];
    }
}

// If the flag is set, pop the window title; otherwise pop the icon title.
- (void)screenPopCurrentTitleForWindow:(BOOL)flag completion:(void (^)(void))completion {
    // This is called from a side-effect and it'll modify the profile so do a spin of the runloop
    // to avoid reentrant joined threads.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (flag) {
            [self popWindowTitle];
        } else {
            [self popIconTitle];
        }
        completion();
    });
}

- (NSString *)screenName {
    return [self name];
}

- (int)screenNumber {
    return [_delegate tabNumber];
}

- (int)screenWindowIndex {
    return [[iTermController sharedInstance] indexOfTerminal:(PseudoTerminal *)[_delegate realParentWindow]];
}

- (int)screenTabIndex {
    return [_delegate number];
}

- (int)screenViewIndex {
    return [[self view] viewId];
}

- (void)screenStartTmuxModeWithDCSIdentifier:(NSString *)dcsID {
    [self startTmuxMode:dcsID];
}

- (void)screenHandleTmuxInput:(VT100Token *)token {
    [_tmuxGateway executeToken:token];
}

- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth {
    return [self treatAmbiguousWidthAsDoubleWidth];
}

- (void)screenPrintVisibleAreaIfAllowed {
    if (![self shouldBeginPrinting:YES]) {
        return;
    }
    // Cause mutableState to be copied to state so we print what the app thinks it's printing.
    [_textview refresh];
    [_textview print:nil];
}

- (BOOL)screenShouldSendContentsChangedNotification {
    return [self wantsContentChangedNotification];
}

- (void)screenRemoveSelection {
    [_textview deselect];
}

- (iTermSelection *)screenSelection {
    return _textview.selection;
}

- (NSSize)screenCellSize {
    return NSMakeSize([_textview charWidth], [_textview lineHeight]);
}

- (void)screenDidClearScrollbackBuffer {
    [_delegate sessionDidClearScrollbackBuffer:self];
}

- (void)screenClearHighlights {
    [_textview clearHighlights:NO];
}

- (void)screenMouseModeDidChange {
    [_textview updateCursor:nil];
    [self.view updateTrackingAreas];
    [self.variablesScope setValue:@(_screen.terminalMouseMode)
                 forVariableNamed:iTermVariableKeySessionMouseReportingMode];
}

- (void)screenFlashImage:(NSString *)identifier {
    [_textview beginFlash:identifier];
}

- (void)incrementBadge {
    [[_delegate realParentWindow] incrementBadge];
}

- (void)screenGetWorkingDirectoryWithCompletion:(void (^)(NSString *))completion {
    DLog(@"screenGetWorkingDirectoryWithCompletion");
    [_pwdPoller addOneTimeCompletion:completion];
    [_pwdPoller poll];
}

- (void)screenSetCursorVisible:(BOOL)visible {
    [_textview setCursorVisible:visible];
}

- (void)screenCursorDidMoveToLine:(int)line {
    if (_textview.cursorVisible) {
        [_textview setNeedsDisplayOnLine:line];
    }
}

- (void)screenSetHighlightCursorLine:(BOOL)highlight {
    [self internalSetHighlightCursorLine:highlight];
}

- (void)screenClearCapturedOutput {
    [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionCapturedOutputDidChange
                                                        object:nil];
}

- (void)setHighlightCursorLine:(BOOL)highlight {
    [self internalSetHighlightCursorLine:highlight];
    _screen.trackCursorLineMovement = highlight;
}

- (void)internalSetHighlightCursorLine:(BOOL)highlight {
    _cursorGuideSettingHasChanged = YES;
    _textview.highlightCursorLine = highlight;
    [_textview requestDelegateRedraw];
}

- (BOOL)highlightCursorLine {
    return _textview.highlightCursorLine;
}

- (BOOL)screenHasView {
    return _textview != nil;
}

- (void)revealIfTabSelected {
    if (![self.delegate sessionIsInSelectedTab:self]) {
        return;
    }
    [_delegate setActiveSession:self];
    [self.delegate sessionDisableFocusFollowsMouseAtCurrentLocation];
}

- (void)reveal {
    DLog(@"Reveal session %@", self);
    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] containsObject:self]) {
        DLog(@"disinter");
        [[iTermBuriedSessions sharedInstance] restoreSession:self];
    }
    NSWindowController<iTermWindowController> *terminal = [_delegate realParentWindow];
    iTermController *controller = [iTermController sharedInstance];
    BOOL okToActivateApp = YES;
    if ([terminal isHotKeyWindow]) {
        DLog(@"Showing hotkey window");
        iTermProfileHotKey *hotKey = [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:(PseudoTerminal *)terminal];
        [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:hotKey url:nil];
        okToActivateApp = (hotKey.hotkeyWindowType != iTermHotkeyWindowTypeFloatingPanel);
    } else {
        DLog(@"Making window current");
        [controller setCurrentTerminal:(PseudoTerminal *)terminal];
        DLog(@"Making window key and ordering front");
        [[terminal window] makeKeyAndOrderFront:self];
        DLog(@"Selecting tab from delegate %@", _delegate);
        [_delegate sessionSelectContainingTab];
    }
    if (okToActivateApp) {
        DLog(@"Activate the app");
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    }

    DLog(@"Make this session active in delegate %@", _delegate);
    [_delegate setActiveSessionPreservingMaximization:self];
}

- (void)makeActive {
    [self.delegate sessionActivate:self];
}

- (void)screenDidAddMark:(id<iTermMark>)newMark alert:(BOOL)alert completion:(void (^)(void))completion {
    if ([self markIsNavigable:newMark]) {
        // currentMarkOrNotePosition is used for navigating next/previous
        self.currentMarkOrNotePosition = newMark.entry.interval;
    }
    if (_commandQueue.count) {
        NSString *command = [[[_commandQueue firstObject] retain] autorelease];
        [_commandQueue removeObjectAtIndex:0];
        [self sendCommand:command];
    }
    BOOL shouldAlert = alert;
    if (!alert &&
        [iTermPreferences boolForKey:kPreferenceKeyAlertOnMarksInOffscreenSessions] &&
        !_temporarilySuspendOffscreenMarkAlerts) {
        shouldAlert = ![self.delegate sessionIsInSelectedTab:self];
    }
    if (!shouldAlert) {
        DLog(@"Will enable offscreen mark alerts for %@", self);
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"Actually enable offscreen mark alerts for %@", weakSelf);
            [weakSelf enableOffscreenMarkAlertsIfNeeded];
        });
        completion();
        return;
    }
    DLog(@"Alert for %@", self);
    self.alertOnNextMark = NO;
    NSString *action = [iTermApplication.sharedApplication delegate].markAlertAction;
    if ([action isEqualToString:kMarkAlertActionPostNotification]) {
        [[iTermNotificationController sharedInstance] notify:@"Mark Set"
                                             withDescription:[NSString stringWithFormat:@"Session %@ #%d had a mark set.",
                                                              [[self name] removingHTMLFromTabTitleIfNeeded],
                                                              [_delegate tabNumber]]
                                                 windowIndex:[self screenWindowIndex]
                                                    tabIndex:[self screenTabIndex]
                                                   viewIndex:[self screenViewIndex]
                                                      sticky:YES];
        completion();
        return;
    }
    // Dispatch so that we don't get a runloop in a side-effect, which can do weird re-entrant things.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf showMarkSetAlert];
        completion();
    });
}

- (void)showMarkSetAlert {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = @"Alert";
    alert.informativeText = [NSString stringWithFormat:@"Mark set in session “%@.”", [self name]];
    [alert addButtonWithTitle:@"Reveal"];
    [alert addButtonWithTitle:@"OK"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self reveal];
    }
}

- (void)screenPromptDidStartAtLine:(int)line {
    [_pasteHelper unblock];
}

- (void)screenPromptDidEndWithMark:(id<VT100ScreenMarkReading>)mark {
    _composerManager.haveShellProvidedText = NO;
    [_promptSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        if (obj.argumentsOneOfCase == ITMNotificationRequest_Arguments_OneOfCase_GPBUnsetOneOfCase ||
            [obj.promptMonitorRequest.modesArray it_contains:ITMPromptMonitorMode_Prompt]) {
            ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
            notification.promptNotification = [[[ITMPromptNotification alloc] init] autorelease];
            notification.promptNotification.session = self.guid;
            notification.promptNotification.prompt.placeholder = @"";
            notification.promptNotification.prompt.prompt = [self getPromptResponseForMark:mark];
            if (mark) {
                notification.promptNotification.uniquePromptId = mark.guid;
            }
            [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                                 toConnectionKey:key];
        }
    }];
    if ([iTermAdvancedSettingsModel smartLoggingWithAutoComposer]) {
        if ([iTermPreferences boolForKey:kPreferenceAutoComposer]) {
            NSArray<ScreenCharArray *> *lines = mark.promptText;
            for (ScreenCharArray *line in lines) {
                NSString *string = (line == lines.lastObject) ? line.stringValue : line.stringValueIncludingNewline;
                string = [string stringByAppendingString:@" "];
                [self logCooked:[string dataUsingEncoding:_screen.terminalEncoding]
                     foreground:(screen_char_t){0}
                     background:(screen_char_t){0}
                       atPrompt:NO];
            }
        }
    }
    __weak __typeof(self) weakSelf = self;
    // Can't just do it here because it may trigger a resize and this runs as a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateAutoComposerFrame];
    });
}

- (void)updateAutoComposerFrame {
    if (_composerManager.dropDownComposerViewIsVisible && _composerManager.isAutoComposer) {
        [_composerManager updateFrame];
    }
}

// Save the current scroll position
- (void)screenSaveScrollPosition {
    [self saveScrollPositionWithName:nil];
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [_textview refresh];  // Handle scrollback overflow so we have the most recent scroll position
        id<iTermMark> mark = [mutableState addMarkStartingAtAbsoluteLine:[_textview absoluteScrollPosition]
                                                                 oneLine:NO
                                                                 ofClass:[VT100ScreenMark class]];
        self.currentMarkOrNotePosition = mark.doppelganger.entry.interval;
    }];
}

- (void)saveScrollPositionWithName:(NSString *)name {
    DLog(@"saveScrollPositionWithName:%@", name);
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [_textview refresh];  // Handle scrollback overflow so we have the most recent scroll position
        id<iTermMark> mark = [mutableState addMarkStartingAtAbsoluteLine:[_textview absoluteScrollPosition]
                                                                 oneLine:NO
                                                                 ofClass:[VT100ScreenMark class]
                                                                modifier:^(id<iTermMark> mark) {
            VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:mark];
            screenMark.name = name;
        }];
        self.currentMarkOrNotePosition = mark.doppelganger.entry.interval;
    }];
}

- (void)renameMark:(id<VT100ScreenMarkReading>)mark to:(NSString *)newName {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        VT100ScreenMark *screenMark = (VT100ScreenMark *)[mark progenitor];
        if (!screenMark.entry.interval || !screenMark.name) {
            return;
        }
        const VT100GridAbsCoordRange range = [mutableState absCoordRangeForInterval:screenMark.entry.interval];
        [mutableState removeNamedMark:screenMark];
        [mutableState addMarkStartingAtAbsoluteLine:range.start.y
                                            oneLine:NO
                                            ofClass:[VT100ScreenMark class]
                                           modifier:^(id<iTermMark> mark) {
            VT100ScreenMark *screenMark = [VT100ScreenMark castFrom:mark];
            screenMark.name = newName;
        }];
    }];
}
- (void)screenStealFocus {
    // Dispatch because you can't have a runloop in a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self maybeStealFocus];
    });
}

- (void)maybeStealFocus {
    NSString *const identifier = @"NoSyncAllowDenyStealFocus";
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:@"A control sequence attempted to activate a session. Allow it?"
                               actions:@[ @"Allow", @"Deny" ]
                             accessory:nil
                            identifier:identifier
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:@"Permission Required"
                                window:nil];
    if (selection == kiTermWarningSelection0) {
        [self reveal];
    }
}

- (void)screenSetProfileToProfileNamed:(NSString *)value {
    if (![self.naggingController terminalCanChangeProfile]) {
        return;
    }
    Profile *newProfile;
    if ([value length]) {
        newProfile = [[ProfileModel sharedInstance] bookmarkWithName:value];
    } else {
        newProfile = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (newProfile) {
        [self setProfile:newProfile preservingName:YES];
    }
}

- (void)setProfile:(NSDictionary *)newProfile
    preservingName:(BOOL)preservingName {
    [self setProfile:newProfile preservingName:preservingName adjustWindow:YES];
}

- (void)setProfile:(NSDictionary *)newProfile
    preservingName:(BOOL)preserveName
      adjustWindow:(BOOL)adjustWindow {
    DLog(@"Set profile to\n%@", newProfile);
    // Force triggers to be checked. We may be switching to a profile without triggers
    // and we don't want them to run on the lines of text above _triggerLine later on
    // when switching to a profile that does have triggers. See issue 7832.
    [self syncCheckingTriggers:VT100ScreenTriggerCheckTypeFullLines];

    NSString *theName = [[self profile] objectForKey:KEY_NAME];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:newProfile];
    if (preserveName) {
        [dict setObject:theName forKey:KEY_NAME];
    }

    _windowAdjustmentDisabled = !adjustWindow;
    [self setProfile:dict];
    [self setPreferencesFromAddressBookEntry:dict];
    _windowAdjustmentDisabled = NO;
    [_originalProfile autorelease];
    _originalProfile = [newProfile copy];
    [self remarry];
    if (preserveName) {
        [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionProfileName: newProfile[KEY_NAME] ?: [NSNull null] }];
        return;
    }
    [self profileDidChangeToProfileWithName:newProfile[KEY_NAME]];
    DLog(@"Done setting profile of %@", self);
}

- (void)screenSetPasteboard:(NSString *)value {
    if ([iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        if ([value isEqualToString:@"ruler"]) {
            [self setPasteboard:NSPasteboardNameGeneral];
        } else if ([value isEqualToString:@"find"]) {
            [self setPasteboard:NSPasteboardNameFind];
        } else if ([value isEqualToString:@"font"]) {
            [self setPasteboard:NSPasteboardNameFont];
        } else {
            [self setPasteboard:NSPasteboardNameGeneral];
        }
    } else {
        XLog(@"Clipboard access denied for CopyToClipboard");
    }
}

- (void)screenDidAddNote:(id<PTYAnnotationReading>)note
                   focus:(BOOL)focus
                 visible:(BOOL)visible {
    [_textview addViewForNote:note focus:focus visible:visible];
    [self.delegate sessionUpdateMetalAllowed];
}

- (void)screenDidAddPorthole:(id<Porthole>)porthole {
    [_textview addPorthole:porthole];
}

// Stop pasting (despite the name)
- (void)screenCopyBufferToPasteboard {
    if ([iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        [self setPasteboard:nil];
    } else {
        [_pasteboard release];
        _pasteboard = nil;
        [_pbtext release];
        _pbtext = nil;
    }
}

- (void)screenAppendDataToPasteboard:(NSData *)data {
    if (_pasteboard == nil) {
        return;
    }
    // Don't allow more than 100MB to be added to the pasteboard queue in case someone
    // forgets to send the EndCopy command.
    const int kMaxPasteboardBytes = 100 * 1024 * 1024;
    if ([_pbtext length] + data.length > kMaxPasteboardBytes) {
        [self setPasteboard:nil];
    }

    [_pbtext appendData:data];
}

- (void)screenWillReceiveFileNamed:(NSString *)filename ofSize:(NSInteger)size preconfirmed:(BOOL)preconfirmed {
    [self.download stop];
    [self.download endOfData];
    self.download = [[[TerminalFileDownload alloc] initWithName:filename size:size] autorelease];
    self.download.preconfirmed = preconfirmed;
    [self.download download];
}

- (void)screenDidFinishReceivingFile {
    [_naggingController didFinishDownload];
    [self.download endOfData];
    self.download = nil;
}

- (void)screenDidFinishReceivingInlineFile {
    [_naggingController didFinishDownload];
}

- (void)screenDidReceiveBase64FileData:(NSString * _Nonnull)data
                               confirm:(void (^ NS_NOESCAPE)(NSString *name,
                                                             NSInteger lengthBefore,
                                                             NSInteger lengthAfter))confirm {
    const NSInteger lengthBefore = self.download.length;
    if (self.download && ![self.download appendData:data]) {
        iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:@"A file transfer was aborted for exceeding its declared size."
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ ]
                                                    completion:^(int selection) {}];
        [self queueAnnouncement:announcement identifier:@"FileTransferAbortedOversize"];

        [self.download stop];
        [self.download endOfData];
        self.download = nil;
        return;
    }
    if (!self.download.preconfirmed) {
        const NSInteger lengthAfter = self.download.length;
        confirm(self.download.shortName, lengthBefore, lengthAfter);
    }
}

- (void)screenFileReceiptEndedUnexpectedly {
    [self.download stop];
    [self.download endOfData];
    self.download = nil;
}

- (void)screenRequestUpload:(NSString *)args completion:(void (^)(void))completion {
    // Dispatch out of fear that NSOpenPanel might do something funky with ruloops even though it doesn't seem to currently.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *parts = [args componentsSeparatedByString:@";"];
        NSDictionary<NSString *, NSString *> *dict = [parts keyValuePairsWithBlock:^iTermTuple *(NSString *object) {
            return [object keyValuePair];
        }];
        [self requestUploadWithFormat:dict[@"format"] version:dict[@"version"]];
        completion();
    });
}

- (void)requestUploadWithFormat:(NSString *)format version:(NSString *)version {
    if (format && ![format isEqualToString:@"tgz"]) {
        NSString *identifier = @"UploadInUnsupportedFormatRequested";
        if (![self announcementWithIdentifier:identifier]) {
            iTermAnnouncementViewController *announcement =
            [iTermAnnouncementViewController announcementWithTitle:@"An upload with an unsupported archive format was requested. You may need a newer version of iTerm2."
                                                             style:kiTermAnnouncementViewStyleWarning
                                                       withActions:@[]
                                                        completion:^(int selection) {}];
            [self queueAnnouncement:announcement identifier:identifier];
        }
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;

    [NSApp activateIgnoringOtherApps:YES];
    [panel beginSheetModalForWindow:_textview.window completionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            [self writeTaskNoBroadcast:@"ok\n" encoding:NSISOLatin1StringEncoding forceEncoding:YES reporting:NO];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            // Get the directories for all the URLs. If a URL was a file, convert it to the containing directory, otherwise leave it alone.
            __block BOOL anyFiles = NO;
            NSArray<NSURL *> *directories = [panel.URLs mapWithBlock:^id(NSURL *anObject) {
                BOOL isDirectory = NO;
                if ([fileManager fileExistsAtPath:anObject.path isDirectory:&isDirectory]) {
                    if (isDirectory) {
                        return anObject;
                    } else {
                        anyFiles = YES;
                        return [NSURL fileURLWithPath:[anObject.path stringByDeletingLastPathComponent]];
                    }
                } else {
                    XLog(@"Could not find %@", anObject.path);
                    return nil;
                }
            }];
            NSString *base = [directories lowestCommonAncestorOfURLs].path;
            if (!anyFiles && directories.count == 1) {
                base = [base stringByDeletingLastPathComponent];
            }
            NSArray *baseComponents = [base pathComponents];
            NSArray<NSString *> *relativePaths = [panel.URLs mapWithBlock:^id(NSURL *anObject) {
                NSString *path = anObject.path;
                NSArray<NSString *> *pathComponents = [path pathComponents];
                NSArray<NSString *> *relativePathComponents = [pathComponents subarrayWithRange:NSMakeRange(baseComponents.count, pathComponents.count - baseComponents.count)];
                NSString *relativePath = [relativePathComponents componentsJoinedByString:@"/"];
                // Start every path with "./" to deal with filenames beginning with -.
                return [@"." stringByAppendingPathComponent:relativePath];
            }];
            NSError *error = nil;
            BOOL includeExtendedAttrs = YES;
            if (version) {
                NSString *versionString = [version stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
                if ([versionString containsString:@"tar (GNU tar)"]) {
                    includeExtendedAttrs = NO;
                }
            }
            NSData *data = [NSData dataWithTGZContainingFiles:relativePaths
                                               relativeToPath:base
                                         includeExtendedAttrs:includeExtendedAttrs
                                                        error:&error];
            if (!data && error) {
                NSString *message = error.userInfo[@"errorMessage"];
                if (message) {
                    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                    alert.messageText = @"Error Preparing Upload";
                    alert.informativeText = [NSString stringWithFormat:@"tar failed with this message: %@", message];
                    [alert runModal];
                    return;
                }
            }
            NSString *base64String = [data base64EncodedStringWithOptions:(NSDataBase64Encoding76CharacterLineLength |
                                                                           NSDataBase64EncodingEndLineWithCarriageReturn)];
            base64String = [base64String stringByAppendingString:@"\n\n"];
            NSString *label;
            if (relativePaths.count == 1) {
                label = relativePaths.firstObject.lastPathComponent;
            } else {
                label = [NSString stringWithFormat:@"%@ plus %ld more", relativePaths.firstObject.lastPathComponent, relativePaths.count - 1];
            }
            const NSUInteger size = base64String.length;
            self.upload = [[[TerminalFileUpload alloc] initWithName:label size:size] autorelease];
            [self.upload upload];
            [_pasteHelper pasteString:base64String
                               slowly:NO
                     escapeShellChars:NO
                             isUpload:YES
                      allowBracketing:YES
                         tabTransform:kTabTransformNone
                         spacesPerTab:0
                             progress:^(NSInteger progress) {
                DLog(@"upload progress %@/%@", @(progress), @(size));
                [self.upload didUploadBytes:progress];
                if (progress == size) {
                    DLog(@"Finished");
                    self.upload = nil;
                }
            }];
        } else {
            // Send a Control-C to cancel the command. The protocol calls to send "abort\n" but this
            // introduces a security risk because reports must not contain newlines.
            [self writeTaskNoBroadcast:[NSString stringWithLongCharacter:3]
                              encoding:NSISOLatin1StringEncoding
                         forceEncoding:YES
                             reporting:NO];
        }
    }];
}

- (void)setAlertOnNextMark:(BOOL)alertOnNextMark {
    _alertOnNextMark = alertOnNextMark;
    [_textview requestDelegateRedraw];
    [self sync];
}

- (void)screenRequestAttention:(VT100AttentionRequestType)request {
    switch (request) {
        case VT100AttentionRequestTypeFireworks:
            [_textview showFireworks];
            break;
        case VT100AttentionRequestTypeStopBouncingDockIcon:
            [NSApp cancelUserAttentionRequest:_requestAttentionId];
            break;
        case VT100AttentionRequestTypeStartBouncingDockIcon:
            _requestAttentionId =
            [NSApp requestUserAttention:NSCriticalRequest];
            break;
        case VT100AttentionRequestTypeBounceOnceDockIcon:
            [NSApp requestUserAttention:NSInformationalRequest];
            break;
        case VT100AttentionRequestTypeFlash:
            [_textview.indicatorsHelper beginFlashingFullScreen];
            break;
    }
}

- (void)screenDidTryToUseDECRQCRA {
    NSString *const userDefaultsKey = @"NoSyncDisableDECRQCRA";
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSNumber *obj = [NSNumber castFrom:[ud objectForKey:userDefaultsKey]];
    if (obj) {
        return;
    }

    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:@"An app tried to read screen contents with DECRQCRA. Enable this feature?"
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"Yes", @"No" ]
                                                completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // Closed
                break;

            case 0: // Enable
                [iTermAdvancedSettingsModel setNoSyncDisableDECRQCRA:NO];
                break;

            case 1: // Disable
                [iTermAdvancedSettingsModel setNoSyncDisableDECRQCRA:YES];
                break;
        }
    }];
    [self queueAnnouncement:announcement identifier:userDefaultsKey];
}

- (void)screenDisinterSession {
    [[iTermBuriedSessions sharedInstance] restoreSession:self];
}

- (void)screenSetBackgroundImageFile:(NSString *)originalFilename {
    NSString *const filename = [[originalFilename stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding] stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (filename.length && ![[NSFileManager defaultManager] fileExistsAtPath:filename]) {
        DLog(@"file %@ does not exist", filename);
        return;
    }
    [self.naggingController setBackgroundImageToFileWithName:filename];
}

- (void)screenSetBadgeFormat:(NSString *)base64Format {
    NSString *theFormat = [base64Format stringByBase64DecodingStringWithEncoding:self.encoding];
    iTermParsedExpression *parsedExpression = [iTermExpressionParser parsedExpressionWithInterpolatedString:theFormat scope:self.variablesScope];
    if ([parsedExpression containsAnyFunctionCall]) {
        XLog(@"Rejected control-sequence provided badge format containing function calls: %@", theFormat);
        [self showSimpleWarningAnnouncment:@"The application attempted to set the badge to a value that would invoke a function call. For security reasons, this is not allowed and the badge was not updated."
                                identifier:@"UnsaveBadgeFormatRejected"];
        return;
    }
    if (theFormat) {
        [self setSessionSpecificProfileValues:@{ KEY_BADGE_FORMAT: theFormat }];
        _textview.badgeLabel = [self badgeLabel];
    } else {
        XLog(@"Badge is not properly base64 encoded: %@", base64Format);
    }
}

- (void)screenSetUserVar:(NSString *)kvpString {
    iTermTuple<NSString *, NSString *> *kvp = [kvpString keyValuePair];
    if (kvp) {
        if ([kvp.firstObject rangeOfString:@"."].location != NSNotFound) {
            DLog(@"key contains a ., which is not allowed. kvpString=%@", kvpString);
            return;
        }
        NSString *key = [NSString stringWithFormat:@"user.%@", kvp.firstObject];
        NSString *value = [kvp.secondObject stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
        [self.variablesScope setValue:value
                     forVariableNamed:key];
        if (self.isTmuxClient) {
            [self.tmuxController setUserVariableWithKey:key
                                                  value:value
                                                   pane:self.tmuxPane];
        }
    } else {
        if ([kvpString rangeOfString:@"."].location != NSNotFound) {
            DLog(@"key contains a ., which is not allowed. key=%@", kvpString);
            return;
        }
        NSString *key = [NSString stringWithFormat:@"user.%@", kvpString];
        [self.variablesScope setValue:nil forVariableNamed:[NSString stringWithFormat:@"user.%@", kvpString]];
        if (self.isTmuxClient) {
            [self.tmuxController setUserVariableWithKey:key
                                                  value:nil
                                                   pane:self.tmuxPane];
        }
    }
}

- (void)setVariableNamed:(NSString *)name toValue:(id)newValue {
    [self.variablesScope setValue:newValue forVariableNamed:name];
}

- (void)injectData:(NSData *)data {
    [self.screen injectData:data];
}

// indexes will be in [0,255].
// 0-7 are ansi colors,
// 8-15 are ansi bright colors,
// 16-255 are 256 color-mode colors.
// If empty, reset all.
- (NSDictionary<NSNumber *, id> *)screenResetColorWithColorMapKey:(int)key
                                                       profileKey:(NSString *)profileKey
                                                             dark:(BOOL)dark {
    DLog(@"key=%d profileKey=%@ dark=%d", key, profileKey, dark);
    return [self resetColorWithKey:key
                       fromProfile:_originalProfile
                        profileKey:profileKey
                              dark:dark];
}

- (BOOL)screenSetColor:(NSColor *)color profileKey:(NSString *)profileKey {
    if (!color) {
        return NO;
    }

    if (profileKey) {
        [self setSessionSpecificProfileValues:@{ profileKey: [color dictionaryValue] }];
        return NO;
    }
    return YES;
}

- (void)screenSelectColorPresetNamed:(NSString *)name {
    [self setColorsFromPresetNamed:name];
}

- (void)screenSetCurrentTabColor:(NSColor *)color {
    [self setTabColor:color];
    id<WindowControllerInterface> term = [_delegate parentWindow];
    [term updateTabColors];
}

- (NSColor *)tabColor {
    return [self tabColorInProfile:_profile];
}

- (void)setTabColor:(NSColor *)color {
    NSDictionary *dict;
    if (color) {
        dict = @{ [self amendedColorKey:KEY_USE_TAB_COLOR]: @YES,
                  [self amendedColorKey:KEY_TAB_COLOR]: [ITAddressBookMgr encodeColor:color] };
    } else {
        dict = @{ [self amendedColorKey:KEY_USE_TAB_COLOR]: @NO };
    }

    [self setSessionSpecificProfileValues:dict];
}

- (void)screenSetTabColorRedComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor] ?: [NSColor it_colorInDefaultColorSpaceWithRed:0 green:0 blue:0 alpha:0];
    [self setTabColor:[curColor it_colorWithRed:color
                                          green:curColor.greenComponent
                                           blue:curColor.blueComponent
                                          alpha:1]];
    [[_delegate parentWindow] updateTabColors];
}

- (void)screenSetTabColorGreenComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor] ?: [NSColor it_colorInDefaultColorSpaceWithRed:0 green:0 blue:0 alpha:0];
    [self setTabColor:[curColor it_colorWithRed:curColor.redComponent
                                          green:color
                                           blue:curColor.blueComponent
                                          alpha:1]];
    [[_delegate parentWindow] updateTabColors];
}

- (void)screenSetTabColorBlueComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor] ?: [NSColor it_colorInDefaultColorSpaceWithRed:0 green:0 blue:0 alpha:0];
    [self setTabColor:[curColor it_colorWithRed:curColor.redComponent
                                          green:curColor.greenComponent
                                           blue:color
                                          alpha:1]];
    [[_delegate parentWindow] updateTabColors];
}

- (void)screenCurrentHostDidChange:(id<VT100RemoteHostReading>)host
                               pwd:(NSString *)workingDirectory
                               ssh:(BOOL)ssh {
    DLog(@"Current host did change to %@, pwd=%@, ssh=%@. %@", host, workingDirectory, @(ssh), self);
    NSString *previousHostName = _currentHost.hostname;

    NSNull *null = [NSNull null];
    NSDictionary *variablesUpdate = @{ iTermVariableKeySessionHostname: host.hostname ?: null,
                                       iTermVariableKeySessionUsername: host.username ?: null };
    [self.variablesScope setValuesFromDictionary:variablesUpdate];

    [_textview setBadgeLabel:[self badgeLabel]];
    [self dismissAnnouncementWithIdentifier:kShellIntegrationOutOfDateAnnouncementIdentifier];

    [[_delegate realParentWindow] sessionHostDidChange:self to:host];

    [self tryAutoProfileSwitchWithHostname:host.hostname
                                  username:host.username
                                      path:workingDirectory
                                       job:self.variablesScope.jobName];

    // Ignore changes to username; only update on hostname changes. See issue 8030.
    if (previousHostName && ![previousHostName isEqualToString:host.hostname] && !ssh) {
        [self maybeResetTerminalStateOnHostChange:host];
        if ([iTermAdvancedSettingsModel restoreKeyModeAutomaticallyOnHostChange]) {
            [self pushOrPopHostState:host];
        }
    }
    self.currentHost = host;
    [self updateVariablesFromConductor];
}

- (BOOL)shellIsFishForHost:(id<VT100RemoteHostReading>)host {
    NSString *name = host.usernameAndHostname;
    if (!name) {
        return NO;
    }
    return [self.hostnameToShell[name] isEqualToString:@"fish"];
}

- (void)maybeResetTerminalStateOnHostChange:(id<VT100RemoteHostReading>)newRemoteHost {
    _modeHandler.mode = iTermSessionModeDefault;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        if (_xtermMouseReporting && terminal.mouseMode != MOUSE_REPORTING_NONE) {
            NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:kTurnOffMouseReportingOnHostChangeUserDefaultsKey];
            if ([number boolValue]) {
                terminal.mouseMode = MOUSE_REPORTING_NONE;
            } else if (!number) {
                [self offerToTurnOffMouseReportingOnHostChange];
            }
        }
        if (terminal.reportFocus) {
            NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
            if ([number boolValue]) {
                terminal.reportFocus = NO;
            } else if (!number) {
                [self offerToTurnOffFocusReporting];
            }
        }
        if (terminal.bracketedPasteMode && ![self shellIsFishForHost:newRemoteHost]) {
            [self maybeTurnOffPasteBracketing];
        }
    }];
}

- (void)pushOrPopHostState:(id<VT100RemoteHostReading>)host {
    DLog(@"Search host stack %@ for %@", _hostStack, host);
    const NSInteger i = [_hostStack indexOfObjectPassingTest:^BOOL(PTYSessionHostState * _Nonnull state, NSUInteger idx, BOOL * _Nonnull stop) {
        return state.remoteHost == host || [state.remoteHost isEqualToRemoteHost:host];
    }];
    if (i == NSNotFound) {
        DLog(@"Not found. Save current key mapping mode %@", @(_keyMappingMode));
        PTYSessionHostState *state = [[[PTYSessionHostState alloc] init] autorelease];
        state.keyMappingMode = _keyMappingMode;
        state.remoteHost = self.currentHost;
        [_hostStack addObject:state];
        return;
    }
    PTYSessionHostState *state = [[_hostStack[i] retain] autorelease];
    DLog(@"Found at %@: %@. Restore mode and pop", @(i), state);
    [_hostStack removeObjectsInRange:NSMakeRange(i, _hostStack.count - i)];
    if (_keyMappingMode != state.keyMappingMode) {
        [self setKeyMappingMode:state.keyMappingMode];
    }
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)commandUses {
    return [[iTermShellHistoryController sharedInstance] commandUsesForHost:self.currentHost];
}

- (iTermQuickLookController *)quickLookController {
    return _textview.quickLookController;
}

- (void)showSimpleWarningAnnouncment:(NSString *)message
                          identifier:(NSString *)identifier {
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:message
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"OK" ]
                                                completion:^(int selection) {}];
    [self queueAnnouncement:announcement identifier:identifier];
}

- (void)offerToTurnOffMouseReportingOnHostChange {
    if ([self hasAnnouncementWithIdentifier:kTurnOffMouseReportingOnHostChangeAnnouncementIdentifier]) {
        return;
    }
    NSString *title =
    @"Looks like mouse reporting was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"_Yes", @"Always", @"Never" ]
                                                completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                         VT100ScreenMutableState *mutableState,
                                                         id<VT100ScreenDelegate> delegate) {
                    terminal.mouseMode = MOUSE_REPORTING_NONE;
                }];
                break;

            case 1: // Always
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kTurnOffMouseReportingOnHostChangeUserDefaultsKey];
                [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                         VT100ScreenMutableState *mutableState,
                                                         id<VT100ScreenDelegate> delegate) {
                    terminal.mouseMode = MOUSE_REPORTING_NONE;
                }];
                break;

            case 2: // Never
                [[NSUserDefaults standardUserDefaults] setBool:NO
                                                        forKey:kTurnOffMouseReportingOnHostChangeUserDefaultsKey];
        }
    }];
    [self queueAnnouncement:announcement identifier:kTurnOffMouseReportingOnHostChangeAnnouncementIdentifier];
}

- (void)offerToTurnOffFocusReporting {
    NSString *title =
    @"Looks like focus reporting was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"_Yes", @"Always", @"Never" ]
                                                completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                         VT100ScreenMutableState *mutableState,
                                                         id<VT100ScreenDelegate> delegate) {
                    terminal.reportFocus = NO;
                }];
                break;

            case 1: // Always
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
                [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                         VT100ScreenMutableState *mutableState,
                                                         id<VT100ScreenDelegate> delegate) {
                    terminal.reportFocus = NO;
                }];
                break;

            case 2: // Never
                [[NSUserDefaults standardUserDefaults] setBool:NO
                                                        forKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
        }
    }];
    [self queueAnnouncement:announcement identifier:kTurnOffFocusReportingOnHostChangeAnnouncementIdentifier];
}

- (void)offerToTurnOffBracketedPasteOnHostChange {
    [self.naggingController offerToTurnOffBracketedPasteOnHostChange];
}

- (void)tryAutoProfileSwitchWithHostname:(NSString *)hostname
                                username:(NSString *)username
                                    path:(NSString *)path
                                     job:(NSString *)job {
    if ([iTermProfilePreferences boolForKey:KEY_PREVENT_APS inProfile:self.profile]) {
        return;
    }
    [_automaticProfileSwitcher setHostname:hostname username:username path:path job:job];
}

// This is called when we get a high-confidence working directory (e.g., CurrentDir=).
- (void)screenCurrentDirectoryDidChangeTo:(NSString *)newPath
                               remoteHost:(id<VT100RemoteHostReading> _Nullable)remoteHost {
    DLog(@"%@\n%@", newPath, [NSThread callStackSymbols]);
    [self didUpdateCurrentDirectory:newPath];
    [self.variablesScope setValue:newPath forVariableNamed:iTermVariableKeySessionPath];

    [self tryAutoProfileSwitchWithHostname:remoteHost.hostname
                                  username:remoteHost.username
                                      path:newPath
                                       job:self.variablesScope.jobName];
    [self.variablesScope setValue:newPath forVariableNamed:iTermVariableKeySessionPath];
    [_pwdPoller invalidateOutstandingRequests];
    _workingDirectoryPollerDisabled = YES;
}

- (void)screenDidReceiveCustomEscapeSequenceWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                                                   payload:(NSString *)payload {
    ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
    notification.customEscapeSequenceNotification = [[[ITMCustomEscapeSequenceNotification alloc] init] autorelease];
    notification.customEscapeSequenceNotification.session = self.guid;
    notification.customEscapeSequenceNotification.senderIdentity = parameters[@"id"];
    notification.customEscapeSequenceNotification.payload = payload;
    [_customEscapeSequenceNotifications enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                             toConnectionKey:key];
    }];
}

- (iTermNaggingController *)naggingController {
    if (!_naggingController) {
        _naggingController = [[iTermNaggingController alloc] init];
        _naggingController.delegate = self;
    }
    return _naggingController;
}

- (void)screenReportVariableNamed:(NSString *)name {
    if (self.isTmuxClient) {
        return;
    }
    NSString *value = nil;
    if ([self.naggingController permissionToReportVariableNamed:name]) {
        value = [self stringValueOfVariable:name];
    }
    NSData *data = [_screen.terminalOutput reportVariableNamed:name
                                                         value:value];
    [self screenSendReportData:data];
}

// Convert a title into a string that is safe to transmit in a report.
// The goal is to make it hard for an attacker to issue a report that could be part of a command.
- (NSString *)reportSafeTitle:(NSString *)unsafeTitle {
    NSCharacterSet *unsafeSet = [NSCharacterSet characterSetWithCharactersInString:@"|;\r\n\e"];
    NSString *result = unsafeTitle;
    NSRange range;
    range = [result rangeOfCharacterFromSet:unsafeSet];
    while (range.location != NSNotFound) {
        result = [result stringByReplacingCharactersInRange:range withString:@" "];
        range = [result rangeOfCharacterFromSet:unsafeSet];
    }
    return result;
}

- (BOOL)allowTitleReporting {
    return [iTermProfilePreferences boolForKey:KEY_ALLOW_TITLE_REPORTING
                                     inProfile:self.profile];
}

- (BOOL)terminalIsTrusted {
    const BOOL result = ![iTermAdvancedSettingsModel disablePotentiallyInsecureEscapeSequences];
    DLog(@"terminalIsTrusted returning %@", @(result));
    return result;
}

- (void)screenReportIconTitle {
    if (self.isTmuxClient) {
        return;
    }
    if (!self.screenAllowTitleSetting || !self.terminalIsTrusted) {
        return;
    }
    NSString *title = [self screenIconTitle] ?: @"";
    NSString *s = [NSString stringWithFormat:@"\033]L%@\033\\",
                   [self reportSafeTitle:title]];
    [self screenSendReportData:[s dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)screenReportWindowTitle {
    if (self.isTmuxClient) {
        return;
    }
    if (!self.screenAllowTitleSetting || !self.terminalIsTrusted) {
        return;
    }
    NSString *s = [NSString stringWithFormat:@"\033]l%@\033\\",
                   [self reportSafeTitle:[self windowTitle]]];
    [self screenSendReportData:[s dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)screenReportCapabilities {
    if (self.isTmuxClient) {
        return;
    }
    NSData *data = [_screen.terminalOutput reportCapabilities:[self capabilities]];
    [self screenSendReportData:data];
}

- (VT100Capabilities)capabilities {
    const BOOL clipboardAccessAllowed = [iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal];
    return VT100OutputMakeCapabilities(YES,                                // compatibility24Bit
                                YES,                                // full24Bit
                                clipboardAccessAllowed,             // clipboardWritable
                                YES,                                // decslrm
                                YES,                                // mouse
                                YES,                                // DECSCUSR14
                                YES,                                // DECSCUSR56
                                YES,                                // DECSCUSR0
                                YES,                                // unicode
                                _treatAmbiguousWidthAsDoubleWidth,  // ambiguousWide
                                _unicodeVersion,                    // unicodeVersion
                                YES,                                // titleStacks
                                YES,                                // titleSetting
                                YES,                                // bracketedPaste
                                YES,                                // focusReporting
                                YES,                                // strikethrough
                                NO,                                 // overline
                                YES,                                // sync
                                YES,                                // hyperlinks
                                YES,                                // notifications
                                YES,                                // sixel
                                YES);                               // file
}

- (VT100GridRange)screenRangeOfVisibleLines {
    return [_textview rangeOfVisibleLines];
}

- (void)screenSetPointerShape:(NSString *)pointerShape {
    NSDictionary *cursors = @{
        @"X_cursor": ^{ return [NSCursor arrowCursor]; },
        @"arrow": ^{ return[NSCursor arrowCursor]; },
        @"based_arrow_down": ^{ return[NSCursor resizeDownCursor]; },
        @"based_arrow_up": ^{ return[NSCursor resizeUpCursor]; },
        @"cross": ^{ return[NSCursor crosshairCursor]; },
        @"cross_reverse": ^{ return[NSCursor crosshairCursor]; },
        @"crosshair": ^{ return[NSCursor crosshairCursor]; },
        @"hand1": ^{ return[NSCursor pointingHandCursor]; },
        @"hand2": ^{ return[NSCursor pointingHandCursor]; },
        @"left_ptr": ^{ return[NSCursor arrowCursor]; },
        @"left_side": ^{ return[NSCursor resizeLeftCursor]; },
        @"right_side": ^{ return[NSCursor resizeRightCursor]; },
        @"sb_h_double_arrow": ^{ return[NSCursor resizeLeftRightCursor]; },
        @"sb_left_arrow": ^{ return[NSCursor resizeLeftCursor]; },
        @"sb_right_arrow": ^{ return[NSCursor resizeRightCursor]; },
        @"sb_up_arrow": ^{ return[NSCursor resizeUpCursor]; },
        @"sb_v_double_arrow": ^{ return[NSCursor resizeUpDownCursor]; },
        @"tcross": ^{ return[NSCursor crosshairCursor]; },
        @"xterm": ^{ return [iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeam]; },
    };
    NSCursor *(^f)(void) = cursors[pointerShape];
    if (!f) {
        self.defaultPointer = nil;
    } else {
        self.defaultPointer = f();
    }
    NSLog(@"invalidateCursorRectsForView");
    [_textview.window invalidateCursorRectsForView:_textview];
    [_textview updateCursor:[NSApp currentEvent]];
}

#pragma mark - FinalTerm

- (NSString *)commandInRange:(VT100GridCoordRange)range {
    return [_screen commandInRange:range];
}

- (NSString *)currentCommand {
    if (_screen.commandRange.start.x < 0) {
        return nil;
    } else {
        return [_screen commandInRange:_screen.commandRange];
    }
}

- (BOOL)eligibleForAutoCommandHistory {
    if (!_textview.cursorVisible) {
        return NO;
    }
    VT100GridCoord coord = _screen.commandRange.end;
    coord.y -= _screen.numberOfScrollbackLines;
    if (!VT100GridCoordEquals(_screen.currentGrid.cursor, coord)) {
        return NO;
    }

    const screen_char_t c = [_screen.currentGrid characterAt:coord];
    return c.code == 0;
}

- (NSArray *)autocompleteSuggestionsForCurrentCommand {
    DLog(@"begin");
    NSString *command;
    if (_screen.commandRange.start.x < 0) {
        DLog(@"no command range");
        return nil;
    }
    command = [_screen commandInRange:_screen.commandRange];
    id<VT100RemoteHostReading> host = [_screen remoteHostOnLine:[_screen numberOfLines]];
    DLog(@"command=%@ host=%@", command, host);

    NSString *trimmedCommand =
    [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [[iTermShellHistoryController sharedInstance] commandHistoryEntriesWithPrefix:trimmedCommand
                                                                                  onHost:host];
}

- (void)screenCommandDidChangeTo:(NSString *)command
                        atPrompt:(BOOL)atPrompt
                      hadCommand:(BOOL)hadCommand
                     haveCommand:(BOOL)haveCommand {
    DLog(@"FinalTerm: command=%@ atPropt=%@ hadCommand=%@ haveCommand=%@",
         command, @(atPrompt), @(hadCommand), @(haveCommand));
    if (!haveCommand && hadCommand) {
        DLog(@"ACH Hide because don't have a command, but just had one");
        [[_delegate realParentWindow] hideAutoCommandHistoryForSession:self];
        return;
    }
    if (!hadCommand && atPrompt) {
        DLog(@"ACH Show because I have a range but didn't have a command");
        [[_delegate realParentWindow] showAutoCommandHistoryForSession:self];
    }
    if ([[_delegate realParentWindow] wantsCommandHistoryUpdatesFromSession:self]) {
        DLog(@"ACH Update command to %@", command);
        if (haveCommand && self.eligibleForAutoCommandHistory) {
            [[_delegate realParentWindow] updateAutoCommandHistoryForPrefix:command
                                                                  inSession:self
                                                                popIfNeeded:NO];
        }
    }
}

- (iTermAppSwitchingPreventionDetector *)appSwitchingPreventionDetector {
    if (!_appSwitchingPreventionDetector) {
        _appSwitchingPreventionDetector = [[iTermAppSwitchingPreventionDetector alloc] init];
        _appSwitchingPreventionDetector.delegate = self;
    }
    return _appSwitchingPreventionDetector;
}

- (void)screenDidExecuteCommand:(NSString *)command
                          range:(VT100GridCoordRange)range
                         onHost:(id<VT100RemoteHostReading>)host
                    inDirectory:(NSString *)directory
                           mark:(id<VT100ScreenMarkReading>)mark {
    if (IsSecureEventInputEnabled()) {
        [[self appSwitchingPreventionDetector] didExecuteCommand:command];
    }
    NSString *trimmedCommand =
    [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmedCommand.length) {
        [[iTermShellHistoryController sharedInstance] addCommand:trimmedCommand
                                                          onHost:host
                                                     inDirectory:directory
                                                        withMark:mark];
        [_commands addObject:trimmedCommand];
        [self trimCommandsIfNeeded];
    }
    self.lastCommand = command;
    [self.variablesScope setValue:command forVariableNamed:iTermVariableKeySessionLastCommand];

    // `_screen.commandRange` is from the beginning of command, to the cursor, not necessarily the end of the command.
    // `range` here includes the entire command and a new line.
    _lastOrCurrentlyRunningCommandAbsRange = VT100GridAbsCoordRangeFromCoordRange(range, _screen.totalScrollbackOverflow);
    DLog(@"Hide ACH because command ended");
    [[_delegate realParentWindow] hideAutoCommandHistoryForSession:self];
    [_promptSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        if ([obj.promptMonitorRequest.modesArray it_contains:ITMPromptMonitorMode_CommandStart]) {
            ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
            notification.promptNotification = [[[ITMPromptNotification alloc] init] autorelease];
            notification.promptNotification.session = self.guid;
            notification.promptNotification.commandStart.command = command;
            if (mark) {
                notification.promptNotification.uniquePromptId = mark.guid;
            }
            [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                                 toConnectionKey:key];
        }
    }];
    if ([iTermPreferences boolForKey:kPreferenceAutoComposer]) {
        [_composerManager reset];
    }
}

- (void)screenCommandDidAbortOnLine:(int)line
                        outputRange:(VT100GridCoordRange)outputRange
                            command:(NSString *)command {
    [_appSwitchingPreventionDetector commandDidFinishWithStatus:-1];
    NSDictionary *userInfo = @{ @"remoteHost": (id)[_screen remoteHostOnLine:line] ?: (id)[NSNull null],
                                @"directory": (id)[_screen workingDirectoryOnLine:line] ?: (id)[NSNull null],
                                @"snapshot": [self contentSnapshot],
                                @"startLine": @(outputRange.start.y),
                                @"lineCount": @(outputRange.end.y - outputRange.start.y + 1),
                                @"command": (id)command ?: (id)[NSNull null]};
    userInfo = [userInfo dictionaryByRemovingNullValues];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PTYCommandDidExitNotification"
                                                        object:_guid
                                                      userInfo:userInfo];
}

- (void)screenCommandDidExitWithCode:(int)code mark:(id<VT100ScreenMarkReading>)maybeMark {
    [_appSwitchingPreventionDetector commandDidFinishWithStatus:code];
    [_promptSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        if ([obj.promptMonitorRequest.modesArray it_contains:ITMPromptMonitorMode_CommandEnd]) {
            ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
            notification.promptNotification = [[[ITMPromptNotification alloc] init] autorelease];
            notification.promptNotification.session = self.guid;
            notification.promptNotification.commandEnd.status = code;
            if (maybeMark) {
                notification.promptNotification.uniquePromptId = maybeMark.guid;
            }
            [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                                 toConnectionKey:key];
        }
    }];

    if (maybeMark) {
        const VT100GridRange lineRange = [_screen lineNumberRangeOfInterval:maybeMark.entry.interval];
        const int line = lineRange.location;
        const VT100GridCoordRange outputRange = [_screen rangeOfOutputForCommandMark:maybeMark];
        NSDictionary *userInfo = @{ @"command": maybeMark.command ?: (id)[NSNull null],
                                    @"exitCode": @(maybeMark.code),
                                    @"remoteHost": (id)[_screen remoteHostOnLine:line] ?: (id)[NSNull null],
                                    @"directory": (id)[_screen workingDirectoryOnLine:line] ?: (id)[NSNull null],
                                    @"snapshot": [self contentSnapshot],
                                    @"startLine": @(outputRange.start.y),
                                    @"lineCount": @(outputRange.end.y - outputRange.start.y + 1) };
        userInfo = [userInfo dictionaryByRemovingNullValues];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PTYCommandDidExitNotification"
                                                            object:_guid
                                                          userInfo:userInfo];
    }
}

- (iTermTerminalContentSnapshot *)contentSnapshot {
    return [_screen snapshotDataSource];
}

- (void)updateConfigurationFields {
    BOOL dirty = NO;
    if (![NSObject object:_config.sessionGuid isEqualToObject:_guid]) {
        _config.sessionGuid = _guid;
        dirty = YES;
    }

    const BOOL treatAmbiguousCharsAsDoubleWidth = [self treatAmbiguousWidthAsDoubleWidth];
    if (_config.treatAmbiguousCharsAsDoubleWidth != treatAmbiguousCharsAsDoubleWidth) {
        _config.treatAmbiguousCharsAsDoubleWidth = treatAmbiguousCharsAsDoubleWidth;
        dirty = YES;
    }

    if (_config.unicodeVersion != _unicodeVersion) {
        _config.unicodeVersion = _unicodeVersion;
        dirty = YES;
    }
    if (_config.isTmuxClient != self.isTmuxClient) {
        _config.isTmuxClient = self.isTmuxClient;
        dirty = YES;
    }
    const BOOL printingAllowed = [self shouldBeginPrinting:NO];
    if (printingAllowed != _config.printingAllowed) {
        _config.printingAllowed = printingAllowed;
        dirty = YES;
    }
    const BOOL clipboardAccessAllowed = [iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal];
    if (clipboardAccessAllowed != _config.clipboardAccessAllowed) {
        _config.clipboardAccessAllowed = clipboardAccessAllowed;
        dirty = YES;
    }
    const BOOL miniaturized = [[_delegate parentWindow] windowIsMiniaturized];
    if (miniaturized != _config.miniaturized) {
        _config.miniaturized = miniaturized;
        dirty = YES;
    }
    const NSRect windowFrame = [self windowFrame];
    if (!NSEqualRects(windowFrame, _config.windowFrame)) {
        _config.windowFrame = windowFrame;
        dirty = YES;
    }
    const VT100GridSize theoreticalGridSize = [self theoreticalGridSize];
    if (!VT100GridSizeEquals(theoreticalGridSize, _config.theoreticalGridSize)) {
        _config.theoreticalGridSize = theoreticalGridSize;
        dirty = YES;
    }
    NSString *iconTitle = [self screenIconTitle];
    if (![NSObject object:iconTitle isEqualToObject:_config.iconTitle]) {
        _config.iconTitle = iconTitle;
        dirty = YES;
    }
    NSString *windowTitle = [self screenWindowTitle];
    if (![NSObject object:windowTitle isEqualToObject:_config.windowTitle]) {
        _config.windowTitle = windowTitle;
        dirty = YES;
    }
    const BOOL clearScrollbackAllowed = [self clearScrollbackAllowed];
    if (clearScrollbackAllowed != _config.clearScrollbackAllowed) {
        _config.clearScrollbackAllowed = clearScrollbackAllowed;
        dirty = YES;
    }
    const NSSize cellSize = NSMakeSize([_textview charWidth], [_textview lineHeight]);
    if (!NSEqualSizes(cellSize, _config.cellSize)) {
        _config.cellSize = cellSize;
        dirty = YES;
    }
    const CGFloat backingScaleFactor = _view.window.screen.backingScaleFactor;
    if (backingScaleFactor != _config.backingScaleFactor) {
        _config.backingScaleFactor = backingScaleFactor;
        dirty = YES;
    }
    if (!_config.maximumTheoreticalImageDimension) {
        _config.maximumTheoreticalImageDimension = PTYSessionMaximumMetalViewSize;
        dirty = YES;
    }
    const BOOL dimOnlyText = [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
    if (_config.dimOnlyText != dimOnlyText) {
        _config.dimOnlyText = dimOnlyText;
        dirty = YES;
    }
    const BOOL darkMode = [NSApp effectiveAppearance].it_isDark;
    const BOOL darkModeDidChange = (_config.darkMode != darkMode);
    if (darkModeDidChange) {
        _config.darkMode = darkMode;
        dirty = YES;
    }
    const BOOL loggingEnabled = _logging.enabled;
    if (_config.loggingEnabled != loggingEnabled) {
        _config.loggingEnabled = loggingEnabled;
        dirty = YES;
    }
    NSDictionary *stringForKeypressConfig = [self stringForKeypressConfig];
    if (![_config.stringForKeypressConfig isEqual:stringForKeypressConfig]) {
        _config.stringForKeypressConfig = stringForKeypressConfig;
        _config.stringForKeypress = [self stringForKeypress];
        dirty = YES;
    }
    const BOOL compoundAlertOnNextMark = [self shouldAlert];
    if (compoundAlertOnNextMark != _config.alertOnNextMark) {
        _config.alertOnNextMark = compoundAlertOnNextMark;
        dirty = YES;
    }
    const double dimmingAmount = _view.adjustedDimmingAmount;
    if (_config.dimmingAmount != dimmingAmount) {
        _config.dimmingAmount = dimmingAmount;
        dirty = YES;
    }

    const BOOL publishing = (self.contentSubscribers.count > 0);
    if (_config.publishing != publishing) {
        _config.publishing = publishing;
        dirty = YES;
    }
    if (_profileDidChange || darkModeDidChange) {
        _config.shouldPlacePromptAtFirstColumn = [iTermProfilePreferences boolForKey:KEY_PLACE_PROMPT_AT_FIRST_COLUMN
                                                                           inProfile:_profile];
        _config.enableTriggersInInteractiveApps = [iTermProfilePreferences boolForKey:KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS
                                                                            inProfile:self.profile];
        _config.triggerParametersUseInterpolatedStrings = [iTermProfilePreferences boolForKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS
                                                                                    inProfile:self.profile];
        _config.triggerProfileDicts = [iTermProfilePreferences objectForKey:KEY_TRIGGERS inProfile:self.profile];
        _config.useSeparateColorsForLightAndDarkMode = [iTermProfilePreferences boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
                                                                                 inProfile:self.profile];
        DLog(@"Set min contrast in config to %f using key %@",
             [iTermProfilePreferences floatForKey:iTermAmendedColorKey(KEY_MINIMUM_CONTRAST, self.profile, darkMode)
                                        inProfile:self.profile],
             iTermAmendedColorKey(KEY_MINIMUM_CONTRAST, self.profile, darkMode));
        _config.minimumContrast = [iTermProfilePreferences floatForKey:iTermAmendedColorKey(KEY_MINIMUM_CONTRAST, self.profile, darkMode)
                                                             inProfile:self.profile];
        _config.faintTextAlpha = [iTermProfilePreferences floatForKey:iTermAmendedColorKey(KEY_FAINT_TEXT_ALPHA, self.profile, darkMode)
                                                            inProfile:self.profile];
        _config.mutingAmount = [iTermProfilePreferences floatForKey:iTermAmendedColorKey(KEY_CURSOR_BOOST, self.profile, darkMode)
                                                          inProfile:self.profile];
        _config.normalization = [iTermProfilePreferences integerForKey:KEY_UNICODE_NORMALIZATION
                                                             inProfile:self.profile];
        _config.appendToScrollbackWithStatusBar = [iTermProfilePreferences boolForKey:KEY_SCROLLBACK_WITH_STATUS_BAR
                                                                            inProfile:self.profile];
        _config.saveToScrollbackInAlternateScreen = [iTermProfilePreferences boolForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN
                                                                              inProfile:self.profile];
        _config.unlimitedScrollback = [iTermProfilePreferences boolForKey:KEY_UNLIMITED_SCROLLBACK
                                                                inProfile:_profile];
        _config.reduceFlicker = [iTermProfilePreferences boolForKey:KEY_REDUCE_FLICKER inProfile:self.profile];
        _config.maxScrollbackLines = [iTermProfilePreferences intForKey:KEY_SCROLLBACK_LINES
                                                              inProfile:self.profile];
        _config.profileName = [self profileName];
        _config.terminalCanChangeBlink = [iTermProfilePreferences boolForKey:KEY_ALLOW_CHANGE_CURSOR_BLINK inProfile:self.profile];

        dirty = YES;
        _profileDidChange = NO;
    }

    NSNumber *desiredComposerRows = nil;
    if ([iTermPreferences boolForKey:kPreferenceAutoComposer] && _promptStateAllowsAutoComposer) {
        const int desiredRows = MAX(1, _composerManager.desiredHeight / _textview.lineHeight);
        desiredComposerRows = @(desiredRows);
    }
    if (![NSObject object:desiredComposerRows isEqualToObject:_config.desiredComposerRows]) {
        _config.desiredComposerRows = desiredComposerRows;
        dirty = YES;
    }
    const BOOL useLineStyleMarks = [iTermPreferences boolForKey:kPreferenceAutoComposer];
    if (useLineStyleMarks != _config.useLineStyleMarks) {
        _config.useLineStyleMarks = useLineStyleMarks;
        dirty = YES;
    }

    const BOOL autoComposerEnabled = [iTermPreferences boolForKey:kPreferenceAutoComposer];
    if (_config.autoComposerEnabled != autoComposerEnabled) {
        _config.autoComposerEnabled = autoComposerEnabled;
        dirty = YES;
    }

    if (dirty) {
        _config.isDirty = dirty;
    }
}

- (BOOL)shouldAlert {
    if (self.alertOnNextMark) {
        DLog(@"self.alertOnNextMark -> YES");
        return YES;
    }
    if (!_alertOnMarksinOffscreenSessions) {
        DLog(@"!_alertOnMarksinOffscreenSessions -> NO");
        return NO;
    }
    if (_temporarilySuspendOffscreenMarkAlerts) {
        DLog(@"_temporarilySuspendOffscreenMarkAlerts -> NO");
        return NO;
    }
    if ([self.delegate hasMaximizedPane] && ![self.delegate sessionIsActiveInTab:self]) {
        DLog(@"hasMaximizedPane && !sessionIsActiveInTab -> YES");
        return YES;
    }
    if (!self.view.window.isVisible ||
        self.view.window.isMiniaturized ||
        ![self.view.window isOnActiveSpace] ||
        ![self.delegate sessionIsInSelectedTab:self]) {
        DLog(@"offscreen -> YES");
        return YES;
    }
    DLog(@"Otherwise -> NO");
    return NO;
}

// As long as this is constant, stringForKeypress will return the same value.
- (NSDictionary *)stringForKeypressConfig {
    return _textview.keyboardHandler.dictionaryValue ?: @{};
}

- (NSDictionary *)stringForKeypress {
    id (^stringForKeypress)(unsigned short, NSEventModifierFlags, NSString *, NSString *) =
    ^id(unsigned short keyCode,
        NSEventModifierFlags flags,
        NSString *characters,
        NSString *charactersIgnoringModifiers) {
        return [self stringForKeyCode:keyCode
                                flags:flags
                           characters:characters
          charactersIgnoringModifiers:charactersIgnoringModifiers] ?: [NSNull null];
    };
    NSString *(^c)(UTF32Char c) = ^NSString *(UTF32Char c) {
        return [NSString stringWithLongCharacter:c];
    };
    return @{
        @(kDcsTermcapTerminfoRequestKey_kb):  stringForKeypress(kVK_Delete, 0, @"\x7f", @"\x7f"),
        @(kDcsTermcapTerminfoRequestKey_kD):  stringForKeypress(kVK_ForwardDelete, NSEventModifierFlagFunction, c(NSDeleteFunctionKey), c(NSDeleteFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_kd):  stringForKeypress(kVK_DownArrow, NSEventModifierFlagFunction, c(NSDownArrowFunctionKey), c(NSDownArrowFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_at_7):  stringForKeypress(kVK_End, NSEventModifierFlagFunction, c(NSEndFunctionKey), c(NSEndFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_at_8):  stringForKeypress(kVK_Return, NSEventModifierFlagFunction, @"\r", @"\r"),
        @(kDcsTermcapTerminfoRequestKey_k1):  stringForKeypress(kVK_F1, NSEventModifierFlagFunction, c(NSF1FunctionKey), c(NSF1FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k2):  stringForKeypress(kVK_F2, NSEventModifierFlagFunction, c(NSF2FunctionKey), c(NSF2FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k3):  stringForKeypress(kVK_F3, NSEventModifierFlagFunction, c(NSF3FunctionKey), c(NSF3FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k4):  stringForKeypress(kVK_F4, NSEventModifierFlagFunction, c(NSF4FunctionKey), c(NSF4FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k5):  stringForKeypress(kVK_F5, NSEventModifierFlagFunction, c(NSF5FunctionKey), c(NSF5FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k6):  stringForKeypress(kVK_F6, NSEventModifierFlagFunction, c(NSF6FunctionKey), c(NSF6FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k7):  stringForKeypress(kVK_F7, NSEventModifierFlagFunction, c(NSF7FunctionKey), c(NSF7FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k8):  stringForKeypress(kVK_F8, NSEventModifierFlagFunction, c(NSF8FunctionKey), c(NSF8FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k9):  stringForKeypress(kVK_F9, NSEventModifierFlagFunction, c(NSF9FunctionKey), c(NSF9FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_k_semi):  stringForKeypress(kVK_F10, NSEventModifierFlagFunction, c(NSF10FunctionKey), c(NSF10FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F1):  stringForKeypress(kVK_F11, NSEventModifierFlagFunction, c(NSF11FunctionKey), c(NSF11FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F2):  stringForKeypress(kVK_F12, NSEventModifierFlagFunction, c(NSF12FunctionKey), c(NSF12FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F3):  stringForKeypress(kVK_F13, NSEventModifierFlagFunction, c(NSF13FunctionKey), c(NSF13FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F4):  stringForKeypress(kVK_F14, NSEventModifierFlagFunction, c(NSF14FunctionKey), c(NSF14FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F5):  stringForKeypress(kVK_F15, NSEventModifierFlagFunction, c(NSF15FunctionKey), c(NSF15FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F6):  stringForKeypress(kVK_F16, NSEventModifierFlagFunction, c(NSF16FunctionKey), c(NSF16FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F7):  stringForKeypress(kVK_F17, NSEventModifierFlagFunction, c(NSF17FunctionKey), c(NSF17FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F8):  stringForKeypress(kVK_F18, NSEventModifierFlagFunction, c(NSF18FunctionKey), c(NSF18FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_F9):  stringForKeypress(kVK_F19, NSEventModifierFlagFunction, c(NSF19FunctionKey), c(NSF19FunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_kh):  stringForKeypress(kVK_Home, NSEventModifierFlagFunction, c(NSHomeFunctionKey), c(NSHomeFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_kl):  stringForKeypress(kVK_LeftArrow, NSEventModifierFlagFunction, c(NSLeftArrowFunctionKey), c(NSLeftArrowFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_kN):  stringForKeypress(kVK_PageDown, NSEventModifierFlagFunction, c(NSPageDownFunctionKey), c(NSPageDownFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_kP):  stringForKeypress(kVK_PageUp, NSEventModifierFlagFunction, c(NSPageUpFunctionKey), c(NSPageUpFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_kr):  stringForKeypress(kVK_RightArrow, NSEventModifierFlagFunction, c(NSRightArrowFunctionKey), c(NSRightArrowFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_star_4):  stringForKeypress(kVK_ForwardDelete,NSEventModifierFlagFunction |  NSEventModifierFlagShift, c(NSDeleteFunctionKey), c(NSDeleteFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_star_7):  stringForKeypress(kVK_End, NSEventModifierFlagFunction | NSEventModifierFlagShift, c(NSEndFunctionKey), c(NSEndFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_pound_2):  stringForKeypress(kVK_Home, NSEventModifierFlagFunction | NSEventModifierFlagShift, c(NSHomeFunctionKey), c(NSHomeFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_pound_4):  stringForKeypress(kVK_LeftArrow, NSEventModifierFlagFunction | NSEventModifierFlagNumericPad | NSEventModifierFlagShift, c(NSLeftArrowFunctionKey), c(NSLeftArrowFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_pct_i):  stringForKeypress(kVK_RightArrow, NSEventModifierFlagFunction | NSEventModifierFlagNumericPad | NSEventModifierFlagShift, c(NSRightArrowFunctionKey), c(NSRightArrowFunctionKey)),
        @(kDcsTermcapTerminfoRequestKey_ku):  stringForKeypress(kVK_UpArrow, NSEventModifierFlagFunction, c(NSUpArrowFunctionKey), c(NSUpArrowFunctionKey)),
    };
}

- (BOOL)shouldPostTerminalGeneratedAlert {
    return [iTermProfilePreferences boolForKey:KEY_SEND_TERMINAL_GENERATED_ALERT
                                     inProfile:_profile];
}

- (void)setSuppressAllOutput:(BOOL)suppressAllOutput {
    _suppressAllOutput = suppressAllOutput;
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.suppressAllOutput = suppressAllOutput;
    }];
}

- (void)resumeOutputIfNeeded {
    if (_suppressAllOutput) {
        // If all output was being suppressed and you hit a key, stop it but ignore bells for a few
        // seconds until we can process any that are in the pipeline.
        self.suppressAllOutput = NO;
        _ignoreBellUntil = [NSDate timeIntervalSinceReferenceDate] + 5;
    }
}

// Called when a bell is to be run. Applies rate limiting and kicks off the bell indicators
// (notifications, flashing lights, sounds) per user preference.
- (void)screenActivateBellAudibly:(BOOL)audibleBell
                          visibly:(BOOL)flashBell
                    showIndicator:(BOOL)showBellIndicator
                            quell:(BOOL)quell {
    if ([self shouldIgnoreBellWhichIsAudible:audibleBell
                                     visible:flashBell]) {
        return;
    }
    BOOL notified = NO;
    if (quell) {
        DLog(@"Quell bell");
    } else {
        if (audibleBell) {
            notified = YES;
            DLog(@"Beep: ring audible bell");
            NSBeep();
        }
        if (showBellIndicator) {
            notified = YES;
            [self setBell:YES];
        }
        if (flashBell) {
            notified = YES;
            [self screenFlashImage:kiTermIndicatorBell];
        }
    }
    if ([[_delegate realParentWindow] incrementBadge]) {
        notified = YES;
    }
    if (notified && !NSApp.isActive && [iTermAdvancedSettingsModel bounceOnInactiveBell]) {
        DLog(@"request user attention");
        [NSApp requestUserAttention:NSCriticalRequest];
    }
}

- (BOOL)shouldIgnoreBellWhichIsAudible:(BOOL)audible visible:(BOOL)visible {
    self.variablesScope.bellCount = @(self.variablesScope.bellCount.integerValue + 1);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < _ignoreBellUntil) {
        return YES;
    }

    // Only sample every X seconds.
    static const NSTimeInterval kMaximumTimeBetweenSamples = 0.01;
    if (now < _lastBell + kMaximumTimeBetweenSamples) {
        return NO;
    }
    _lastBell = now;

    // If the bell rings more often than once every X seconds, you will eventually get an offer to
    // silence it.
    static const NSTimeInterval kThresholdForBellMovingAverageToInferAnnoyance = 0.02;

    // Initial value that will require a reasonable amount of bell-ringing to overcome. This value
    // was chosen so that one bell per second will cause the moving average's value to fall below 4
    // after 3 seconds.
    const NSTimeInterval kMaxDuration = 20;

    if (!_bellRate) {
        _bellRate = [[MovingAverage alloc] init];
        _bellRate.alpha = 0.95;
    }
    // Keep a moving average of the time between bells
    static const NSTimeInterval kTimeBeforeReset = 1;
    if (_bellRate.timerStarted && _bellRate.timeSinceTimerStarted > kTimeBeforeReset) {
        _bellRate.value = kMaxDuration * _bellRate.alpha;
    } else {
        [_bellRate addValue:MIN(kMaxDuration, [_bellRate timeSinceTimerStarted])];
    }
    DLog(@"Bell. dt=%@ rate=%@", @(_bellRate.timeSinceTimerStarted), @(_bellRate.value));
    [_bellRate startTimer];
    // If you decline the offer to silence the bell, we'll stop asking for this many seconds.
    static const NSTimeInterval kTimeToWaitAfterDecline = 10;
    NSString *const identifier = @"Annoying Bell Announcement Identifier";
    iTermAnnouncementViewController *existingAnnouncement = _announcements[identifier];
    if (existingAnnouncement) {
        // Reset the auto-dismiss time each time the bell rings.
        existingAnnouncement.timeout = 10;
    }
    if ([_bellRate value] < kThresholdForBellMovingAverageToInferAnnoyance &&
        [[NSUserDefaults standardUserDefaults] boolForKey:kSilenceAnnoyingBellAutomatically]) {
        // Silence automatically
        _ignoreBellUntil = now + 60;
        return YES;
    }

    if ([_bellRate value] < kThresholdForBellMovingAverageToInferAnnoyance &&
        !existingAnnouncement &&
        (now - _annoyingBellOfferDeclinedAt > kTimeToWaitAfterDecline) &&
        ![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressAnnoyingBellOffer]) {
        iTermAnnouncementViewController *announcement = nil;
        if (audible) {
            DLog(@"Want to show a bell announcement. The bell is audible.");
            announcement =
            [iTermAnnouncementViewController announcementWithTitle:@"The bell is ringing a lot. Silence it?"
                                                             style:kiTermAnnouncementViewStyleQuestion
                                                       withActions:@[ @"_Silence Bell Temporarily",
                                                                      @"Suppress _All Output",
                                                                      @"Don't Offer Again",
                                                                      @"Silence Automatically" ]
                                                        completion:^(int selection) {
                // Release the moving average so the count will restart after the announcement goes away.
                [_bellRate release];
                _bellRate = nil;
                switch (selection) {
                    case -2:  // Dismiss programmatically
                        DLog(@"Dismiss programmatically");
                        break;

                    case -1: // No
                        DLog(@"Dismiss temporarily");
                        _annoyingBellOfferDeclinedAt = [NSDate timeIntervalSinceReferenceDate];
                        break;

                    case 0: // Suppress bell temporarily
                        DLog(@"Suppress bell temporarily");
                        _ignoreBellUntil = now + 60;
                        break;

                    case 1: // Suppress all output
                        DLog(@"Suppress all output");
                        self.suppressAllOutput = YES;
                        break;

                    case 2: // Never offer again
                        DLog(@"Never offer again");
                        [[NSUserDefaults standardUserDefaults] setBool:YES
                                                                forKey:kSuppressAnnoyingBellOffer];
                        break;

                    case 3:  // Silence automatically
                        DLog(@"Silence automatically");
                        [[NSUserDefaults standardUserDefaults] setBool:YES
                                                                forKey:kSilenceAnnoyingBellAutomatically];
                        break;
                }
            }];
        } else if (visible) {
            DLog(@"Want to show a bell announcement. The bell is visible but inaudible.");
            // Neither audible nor visible.
            announcement =
            [iTermAnnouncementViewController announcementWithTitle:@"The bell is ringing a lot. Want to suppress all output until things calm down?"
                                                             style:kiTermAnnouncementViewStyleQuestion
                                                       withActions:@[ @"Suppress _All Output",
                                                                      @"Don't Offer Again" ]
                                                        completion:^(int selection) {
                // Release the moving average so the count will restart after the announcement goes away.
                [_bellRate release];
                _bellRate = nil;
                switch (selection) {
                    case -2:  // Dismiss programmatically
                        DLog(@"Dismiss programmatically");
                        break;

                    case -1: // No
                        DLog(@"Dismiss temporarily");
                        _annoyingBellOfferDeclinedAt = [NSDate timeIntervalSinceReferenceDate];
                        break;

                    case 0: // Suppress all output
                        DLog(@"Suppress all output");
                        self.suppressAllOutput = YES;
                        break;

                    case 1: // Never offer again
                        DLog(@"Don't offer again");
                        [[NSUserDefaults standardUserDefaults] setBool:YES
                                                                forKey:kSuppressAnnoyingBellOffer];
                        break;
                }
            }];
        }

        if (announcement) {
            // Set the auto-dismiss timeout.
            announcement.timeout = 10;
            [self queueAnnouncement:announcement identifier:identifier];
        }
    }
    if ([self wasFocusReportedVeryRecently] && ![self haveWrittenAnythingBesidesFocusReportVeryRecently]) {
        [self offerToTurnOffFocusReporting];
        return NO;
    }
    return NO;
}

static const NSTimeInterval PTYSessionFocusReportBellSquelchTimeIntervalThreshold = 0.1;

- (BOOL)wasFocusReportedVeryRecently {
    NSDate *date = self.lastFocusReportDate;
    if (!date) {
        return NO;
    }
    return -[date timeIntervalSinceNow] < PTYSessionFocusReportBellSquelchTimeIntervalThreshold;
}

- (BOOL)haveWrittenAnythingBesidesFocusReportVeryRecently {
    return -[self.lastNonFocusReportingWrite timeIntervalSinceNow] < PTYSessionFocusReportBellSquelchTimeIntervalThreshold;
}

- (NSString *)profileName {
    NSString *guid = _profile[KEY_ORIGINAL_GUID] ?: _profile[KEY_GUID];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (profile) {
        return profile[KEY_NAME];
    }
    return _profile[KEY_NAME];
}

- (void)trimHostsIfNeeded {
    if (_hosts.count > kMaxHosts) {
        [_hosts removeObjectsInRange:NSMakeRange(0, _hosts.count - kMaxHosts)];
    }
}

- (void)trimCommandsIfNeeded {
    if (_commands.count > kMaxCommands) {
        [_commands removeObjectsInRange:NSMakeRange(0, _commands.count - kMaxCommands)];
    }
}

- (void)trimDirectoriesIfNeeded {
    if (_directories.count > kMaxDirectories) {
        [_directories removeObjectsInRange:NSMakeRange(0, _directories.count - kMaxDirectories)];
    }
}

- (void)setLastDirectory:(NSString *)lastDirectory remote:(BOOL)directoryIsRemote pushed:(BOOL)pushed {
    DLog(@"setLastDirectory:%@ remote:%@ pushed:%@\n%@", lastDirectory, @(directoryIsRemote), @(pushed), [NSThread callStackSymbols]);
    if (pushed && lastDirectory) {
        [_directories addObject:lastDirectory];
        [self trimDirectoriesIfNeeded];
    }
    self.lastDirectory = lastDirectory;
    if (!directoryIsRemote) {
        if (pushed || !self.lastLocalDirectoryWasPushed) {
            self.lastLocalDirectory = lastDirectory;
            self.lastLocalDirectoryWasPushed = pushed;
        }
    }
    if (lastDirectory) {
        DLog(@"Set path to %@", lastDirectory);
        self.variablesScope.path = lastDirectory;
    }
    // Update the proxy icon
    [_delegate sessionCurrentDirectoryDidChange:self];
}

- (void)setLastLocalDirectory:(NSString *)lastLocalDirectory {
    DLog(@"lastLocalDirectory goes %@ -> %@ for %@\n%@", _lastLocalDirectory, lastLocalDirectory, self, [NSThread callStackSymbols]);
    [_lastLocalDirectory autorelease];
    _lastLocalDirectory = [lastLocalDirectory copy];
    if (lastLocalDirectory) {
        _localFileChecker.workingDirectory = lastLocalDirectory;
    }
}

- (void)setLastLocalDirectoryWasPushed:(BOOL)lastLocalDirectoryWasPushed {
    DLog(@"lastLocalDirectoryWasPushed goes %@ -> %@ for %@\n%@", @(_lastLocalDirectoryWasPushed),
         @(lastLocalDirectoryWasPushed), self, [NSThread callStackSymbols]);
    _lastLocalDirectoryWasPushed = lastLocalDirectoryWasPushed;
}

- (void)asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory:(void (^)(NSString *pwd))completion {
    if (_conductor != nil && self.lastDirectory.length > 0) {
        completion(self.lastDirectory);
        return;
    }
    NSString *envPwd = self.environment[@"PWD"];
    DLog(@"asyncInitialDirectoryForNewSessionBasedOnCurrentDirectory environment[pwd]=%@", envPwd);
    [self asyncCurrentLocalWorkingDirectory:^(NSString *pwd) {
        DLog(@"asyncCurrentLocalWorkingDirectory finished with %@", pwd);
        if (!pwd) {
            completion(envPwd);
            return;
        }
        completion(pwd);
    }];
}

- (void)asyncCurrentLocalWorkingDirectory:(void (^)(NSString *pwd))completion {
    DLog(@"Current local working directory requestd for %@", self);
    if (_lastLocalDirectory) {
        DLog(@"Using cached value %@", _lastLocalDirectory);
        completion(_lastLocalDirectory);
        return;
    }
    DLog(@"No cached value");
    __weak __typeof(self) weakSelf = self;
    [self updateLocalDirectoryWithCompletion:^(NSString *pwd) {
        DLog(@"updateLocalDirectory for %@ finished with %@", weakSelf, pwd);
        completion(weakSelf.lastLocalDirectory);
    }];
}

// POTENTIALLY SLOW - AVOID CALLING!
- (NSString *)currentLocalWorkingDirectory {
    DLog(@"Warning! Slow currentLocalWorkingDirectory called");
    if (self.lastLocalDirectory != nil) {
        // If a shell integration-provided working directory is available, prefer to use it because
        // it has unresolved symlinks. The path provided by -getWorkingDirectory has expanded symlinks
        // and isn't what the user expects to see. This was raised in issue 3383. My first fix was
        // to expand symlinks on _lastDirectory and use it if it matches what the kernel reports.
        // That was a bad idea because expanding symlinks is slow on network file systems (Issue 4901).
        // Instead, we'll use _lastDirectory if we believe it's on localhost.
        // Furthermore, getWorkingDirectory is slow and blocking and it would be better never to call
        // it.
        DLog(@"Using last directory from shell integration: %@", _lastDirectory);
        return self.lastLocalDirectory;
    }
    DLog(@"Last directory is unsuitable or nil");
    // Ask the kernel what the child's process's working directory is.
    self.lastLocalDirectory = [_shell getWorkingDirectory];
    self.lastLocalDirectoryWasPushed = NO;
    return self.lastLocalDirectory;
}

- (void)setLastRemoteHost:(id<VT100RemoteHostReading>)lastRemoteHost {
    if (lastRemoteHost) {
        [_hosts addObject:lastRemoteHost];
        [self trimHostsIfNeeded];
    }
    [_lastRemoteHost autorelease];
    _lastRemoteHost = [lastRemoteHost retain];
}

- (void)screenLogWorkingDirectoryOnAbsoluteLine:(long long)absLine
                                     remoteHost:(id<VT100RemoteHostReading>)remoteHost
                                  withDirectory:(NSString *)directory
                                       pushType:(VT100ScreenWorkingDirectoryPushType)pushType
                                       accepted:(BOOL)accepted {
    DLog(@"screenLogWorkingDirectoryOnscreenLogWorkingDirectoryOnAbsoluteLine:%@ remoteHost:%@ withDirectory:%@ pushType:%@ accepted:%@",
         @(absLine), remoteHost, directory, @(pushType), @(accepted));

    DLog(@"Accepted=%@", @(accepted));

    const BOOL pushed = (pushType != VT100ScreenWorkingDirectoryPushTypePull);
    if (pushed && accepted) {
        // If we're currently polling for a working directory, do not create a
        // mark for the result when the poll completes because this mark is
        // from a higher-quality data source.
        DLog(@"Invalidate outstanding PWD poller requests.");
        [_pwdPoller invalidateOutstandingRequests];
    }

    // Update shell integration DB.
    DLog(@"remoteHost is %@, is local is %@", remoteHost, @(!remoteHost.isLocalhost));
    if (pushed) {
        BOOL isSame = ([directory isEqualToString:_lastDirectory] &&
                       [remoteHost isEqualToRemoteHost:_lastRemoteHost]);
        [[iTermShellHistoryController sharedInstance] recordUseOfPath:directory
                                                               onHost:remoteHost
                                                             isChange:!isSame];
    }
    if (accepted) {
        // This has been a big ugly hairball for a long time. Because of the
        // working directory poller I think it's safe to simplify it now. Before,
        // we'd track whether the update was trustworthy and likely to happen
        // again. These days, it should always be regular so that is not
        // interesting. Instead, we just want to make sure we know if the directory
        // is local or remote because we want to ignore local directories when we
        // know the user is ssh'ed somewhere.
        const BOOL directoryIsRemote = (pushType == VT100ScreenWorkingDirectoryPushTypeStrongPush) && remoteHost && !remoteHost.isLocalhost;

        // Update lastDirectory, lastLocalDirectory (maybe), proxy icon, "path" variable.
        [self setLastDirectory:directory remote:directoryIsRemote pushed:pushed];
        if (pushed) {
            self.lastRemoteHost = remoteHost;
        }
    }
}

- (BOOL)screenAllowTitleSetting {
    NSNumber *n = _profile[KEY_ALLOW_TITLE_SETTING];
    if (!n) {
        return YES;
    } else {
        return [n boolValue];
    }
}

- (void)didUpdateCurrentDirectory:(NSString *)newPath {
    _shouldExpectCurrentDirUpdates = YES;
    _conductor.currentDirectory = newPath;
}

- (NSString *)shellIntegrationUpgradeUserDefaultsKeyForHost:(id<VT100RemoteHostReading>)host {
    return [NSString stringWithFormat:@"SuppressShellIntegrationUpgradeAnnouncementForHost_%@@%@",
            host.username, host.hostname];
}

- (void)tryToRunShellIntegrationInstallerWithPromptCheck:(BOOL)promptCheck {
    if (_exited) {
        return;
    }
    NSString *currentCommand = [self currentCommand];
    if (!promptCheck || currentCommand != nil) {
        [_textview installShellIntegration:nil];
    } else {
        iTermWarningSelection selection =
        [iTermWarning showWarningWithTitle:@"It looks like you're not at a command prompt."
                                   actions:@[ @"Run Installer Anyway", @"Cancel" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:self.view.window];
        switch (selection) {
            case kiTermWarningSelection0:
                [_textview installShellIntegration:nil];
                break;

            default:
                break;
        }
    }
}

- (void)screenDidDetectShell:(NSString *)shell {
    NSString *name = self.currentHost.usernameAndHostname;
    if (name && shell) {
        self.hostnameToShell[name] = shell;
    }
    if (shell) {
        [self.variablesScope setValue:shell forVariableNamed:iTermVariableKeyShell];
    }
}

- (NSString *)bestGuessAtUserShell {
    return [[self.variablesScope valueForVariableName:iTermVariableKeyShell] lastPathComponent] ?: [[iTermOpenDirectory userShell] lastPathComponent] ?: @"zsh";
}

- (NSString *)bestGuessAtUName {
    NSString *name = self.currentHost.usernameAndHostname;
    NSString *unameString = nil;
    if (name) {
        unameString = _conductor.uname;
    }
    if (!unameString) {
        struct utsname utsname = { 0 };
        if (uname(&utsname)) {
            return @"Darwin";
        }
        unameString = [NSString stringWithFormat:@"%s %s %s %s %s",
                       utsname.sysname,
                       utsname.nodename,
                       utsname.release,
                       utsname.version,
                       utsname.machine];
    }
    return unameString;
}

- (void)screenSuggestShellIntegrationUpgrade {
    id<VT100RemoteHostReading> currentRemoteHost = [self currentHost];

    NSString *theKey = [self shellIntegrationUpgradeUserDefaultsKeyForHost:currentRemoteHost];
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if ([userDefaults boolForKey:theKey]) {
        return;
    }
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:@"This account’s Shell Integration scripts are out of date."
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"Upgrade", @"Silence Warning" ]
                                                completion:^(int selection) {
        switch (selection) {
            case -2:  // Dismiss programmatically
                break;

            case -1: // No
                break;

            case 0: // Yes
                [self tryToRunShellIntegrationInstallerWithPromptCheck:YES];
                break;

            case 1: // Never for this account
                [userDefaults setBool:YES forKey:theKey];
                break;
        }
    }];
    [self queueAnnouncement:announcement identifier:kShellIntegrationOutOfDateAnnouncementIdentifier];
}

- (BOOL)screenShouldReduceFlicker {
    return [iTermProfilePreferences boolForKey:KEY_REDUCE_FLICKER inProfile:self.profile];
}

- (NSInteger)screenUnicodeVersion {
    return _unicodeVersion;
}

- (void)screenSetUnicodeVersion:(NSInteger)unicodeVersion {
    if (unicodeVersion == 0) {
        // Set to default value
        unicodeVersion = [[iTermProfilePreferences defaultObjectForKey:KEY_UNICODE_VERSION] integerValue];
    }
    if (unicodeVersion >= kMinimumUnicodeVersion &&
        unicodeVersion <= kMaximumUnicodeVersion &&
        unicodeVersion != [iTermProfilePreferences integerForKey:KEY_UNICODE_VERSION inProfile:self.profile]) {
        [self setSessionSpecificProfileValues:@{ KEY_UNICODE_VERSION: @(unicodeVersion) }];
    }
}

- (void)updateStatusChangedLine {
    _statusChangedAbsLine = _screen.cursorY - 1 + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow;
}

- (void)restoreKeyLabels:(NSDictionary *)labels updateStatusChangedLine:(BOOL)updateStatusChangedLine {
    if (labels.count == 0) {
        return;
    }
    if (!_keyLabels) {
        _keyLabels = [[NSMutableDictionary alloc] init];
    }
    [labels enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull name, NSString *_Nonnull value, BOOL * _Nonnull stop) {
        if (value.length == 0) {
            return;
        }
        _keyLabels[name] = [[value copy] autorelease];
        if ([name isEqualToString:@"status"] && updateStatusChangedLine) {
            [self updateStatusChangedLine];
        }
    }];
}

- (void)screenSetLabel:(NSString *)label forKey:(NSString *)keyName {
    if (!_keyLabels) {
        _keyLabels = [[NSMutableDictionary alloc] init];
    }
    const BOOL changed = ![_keyLabels[keyName] isEqualToString:label];
    if (label.length == 0) {
        [_keyLabels removeObjectForKey:keyName];
    } else {
        _keyLabels[keyName] = [[label copy] autorelease];
    }
    if ([keyName isEqualToString:@"status"] && changed) {
        [self updateStatusChangedLine];
    }
    [_delegate sessionKeyLabelsDidChange:self];
}

- (void)screenPushKeyLabels:(NSString *)value {
    if (!_keyLabels) {
        return;
    }
    if (!_keyLabelsStack) {
        _keyLabelsStack = [[NSMutableArray alloc] init];
    }
    iTermKeyLabels *labels = [[[iTermKeyLabels alloc] init] autorelease];
    labels.name = value;
    labels.map = [_keyLabels.mutableCopy autorelease];
    [_keyLabelsStack addObject:labels];

    if (![value hasPrefix:@"."]) {
        [_keyLabels removeAllObjects];
    }
    [_delegate sessionKeyLabelsDidChange:self];
}

- (iTermKeyLabels *)popKeyLabels {
    iTermKeyLabels *labels = [[_keyLabelsStack.lastObject retain] autorelease];
    [_keyLabelsStack removeLastObject];
    return labels;
}

- (void)screenPopKeyLabels:(NSString *)value {
    [_keyLabels release];
    _keyLabels = nil;
    iTermKeyLabels *labels = [self popKeyLabels];
    while (labels && value.length > 0 && ![labels.name isEqualToString:value]) {
        labels = [self popKeyLabels];
    }
    _keyLabels = [labels.map mutableCopy];
    [_delegate sessionKeyLabelsDidChange:self];
}

- (void)screenSendModifiersDidChange {
    const BOOL allowed = [iTermProfilePreferences boolForKey:KEY_ALLOW_MODIFY_OTHER_KEYS
                                                   inProfile:self.profile];
    if (!allowed) {
        return;
    }
    const int modifyOtherKeysMode = _screen.terminalSendModifiers[4].intValue;
    if (modifyOtherKeysMode == 1) {
        self.keyMappingMode = iTermKeyMappingModeModifyOtherKeys1;
    } else if (modifyOtherKeysMode == 2) {
        self.keyMappingMode = iTermKeyMappingModeModifyOtherKeys2;
    } else {
        self.keyMappingMode = iTermKeyMappingModeStandard;
    }
}

- (void)screenKeyReportingFlagsDidChange {
    const BOOL profileWantsTickit = [iTermProfilePreferences boolForKey:KEY_USE_LIBTICKIT_PROTOCOL
                                                              inProfile:self.profile];
    if ((_screen.terminalKeyReportingFlags & VT100TerminalKeyReportingFlagsDisambiguateEscape) || profileWantsTickit) {
        self.keyMappingMode = iTermKeyMappingModeCSIu;
    } else {
        self.keyMappingMode = iTermKeyMappingModeStandard;
    }
}

- (void)screenTerminalAttemptedPasteboardAccess {
    [self.textview didCopyToPasteboardWithControlSequence];
    if ([iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        return;
    }
    if ([iTermAdvancedSettingsModel noSyncSuppressClipboardAccessDeniedWarning]) {
        return;
    }
    NSString *identifier = @"ClipboardAccessDenied";
    if ([self hasAnnouncementWithIdentifier:identifier]) {
        return;
    }
    NSString *notice = @"The terminal attempted to access the clipboard but it was denied. Enable clipboard access in “Prefs > General > Selection > Applications in terminal may access clipboard”.";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:notice
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"_Open Prefs", @"Don't Show This Again" ]
                                                completion:^(int selection) {
        if (selection == 0) {
            [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyAllowClipboardAccessFromTerminal];
        } else if (selection == 1) {
            [iTermAdvancedSettingsModel setNoSyncSuppressClipboardAccessDeniedWarning:YES];
        }
    }];
    [self queueAnnouncement:announcement identifier:identifier];
}

- (NSString *)stringValueOfVariable:(NSString *)name {
    if (!name) {
        return nil;
    }
    id value = [self.variablesScope valueForVariableName:name];
    if ([NSString castFrom:value]) {
        return value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    } else {
        return nil;
    }
}

- (void)screenReportFocusWillChangeTo:(BOOL)reportFocus {
    [self dismissAnnouncementWithIdentifier:kTurnOffFocusReportingOnHostChangeAnnouncementIdentifier];
}

- (void)screenReportPasteBracketingWillChangeTo:(BOOL)bracket {
    [self dismissAnnouncementWithIdentifier:kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier];
}

// BE CAREFUL! If you change this you MUST change -[VT100ScreenMutableState appendLineFeed].
// When this would be idempotent then it's called via a flag change.
// When this is not idempotent it is called as a side effect, which is slower.
// -appendLineFeed contains an idempotency test that must match the implementation of this method.
- (void)screenDidReceiveLineFeedAtLineBufferGeneration:(long long)lineBufferGeneration {
    [self publishNewlineWithLineBufferGeneration:lineBufferGeneration];  // Idempotent exactly when not publishing
    [_pwdPoller didReceiveLineFeed];  // Idempotent
    if (_logging.enabled && !self.isTmuxGateway) {  // Idempotent if condition is false
        switch (_logging.style) {
            case iTermLoggingStyleRaw:
            case iTermLoggingStyleAsciicast:
                break;
            case iTermLoggingStyleHTML:
                [_logging logNewline:[@"<br/>\n" dataUsingEncoding:_screen.terminalEncoding]];
                break;
            case iTermLoggingStylePlainText:
                [_logging logNewline:nil];
                break;
        }
    }
}

- (void)screenSoftAlternateScreenModeDidChangeTo:(BOOL)enabled
                                showingAltScreen:(BOOL)showing {
    [self.processInfoProvider setNeedsUpdate:YES];
    [self.tmuxForegroundJobMonitor updateOnce];
    [self.variablesScope setValue:@(showing)
                 forVariableNamed:iTermVariableKeySessionShowingAlternateScreen];
    [self removeSelectedCommandRange];
}

- (void)screenReportKeyUpDidChange:(BOOL)reportKeyUp {
    if (reportKeyUp) {
        self.keyMappingMode = iTermKeyMappingModeRaw;
    } else {
        self.keyMappingMode = iTermKeyMappingModeStandard;
    }
}

#pragma mark - Announcements

- (BOOL)hasAnnouncementWithIdentifier:(NSString *)identifier {
    return _announcements[identifier] != nil;
}

- (void)dismissAnnouncementWithIdentifier:(NSString *)identifier {
    iTermAnnouncementViewController *announcement = _announcements[identifier];
    [announcement dismiss];
}

- (void)queueAnnouncement:(iTermAnnouncementViewController *)announcement
               identifier:(NSString *)identifier {
    DLog(@"Enqueue announcement with identifier %@", identifier);
    [self dismissAnnouncementWithIdentifier:identifier];

    _announcements[identifier] = announcement;

    void (^originalCompletion)(int) = [announcement.completion copy];
    NSString *identifierCopy = [identifier copy];
    __weak __typeof(self) weakSelf = self;
    announcement.completion = ^(int selection) {
        originalCompletion(selection);
        if (selection == -2) {
            [weakSelf removeAnnouncementWithIdentifier:identifierCopy];
            [identifierCopy release];
            [originalCompletion release];
        }
    };
    [_view addAnnouncement:announcement];
}

- (void)removeAnnouncementWithIdentifier:(NSString *)identifier {
    [_announcements removeObjectForKey:identifier];
}

- (iTermAnnouncementViewController *)announcementWithIdentifier:(NSString *)identifier {
    return _announcements[identifier];
}

#pragma mark - PopupDelegate

- (BOOL)popupShouldTakePrefixFromScreen {
    return _textview.window.firstResponder == _textview;
}

// If the cursor is preceded by whitespace the last word will be empty. Words go in reverse order.
- (NSArray<NSString *> *)popupWordsBeforeInsertionPoint:(int)count {
    id<iTermPopupWindowHosting> host = [self popupHost];
    return [host wordsBeforeInsertionPoint:count] ?: @[@""];
}

- (void)popupIsSearching:(BOOL)searching {
    _textview.showSearchingCursor = searching;
    [_textview requestDelegateRedraw];
}

- (void)popupWillClose:(iTermPopupWindowController *)popup {
    [[_delegate realParentWindow] popupWillClose:popup];
}

- (NSRect)popupScreenVisibleFrame {
    return [[[[_delegate realParentWindow] window] screen] visibleFrame];
}

- (BOOL)popupWindowIsInFloatingHotkeyWindow {
    return _delegate.realParentWindow.isFloatingHotKeyWindow;
}

- (BOOL)screenConfirmDownloadNamed:(NSString *)name canExceedSize:(NSInteger)limit {
    NSString *identifier = @"NoSyncAllowBigDownload";
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"The download “%@” is larger than %@. Continue?", name, [NSString it_formatBytes:limit]]
                               actions:@[ @"Allow", @"Deny" ]
                             accessory:nil
                            identifier:identifier
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:@"Allow Large File Download?"
                                window:_view.window];
    return selection == kiTermWarningSelection0;
}

- (BOOL)screenConfirmDownloadAllowed:(NSString *)name
                                size:(NSInteger)size
                       displayInline:(BOOL)displayInline
                         promptIfBig:(BOOL *)promptIfBig {
    NSString *identifier = @"NoSyncSuppressDownloadConfirmation";
    *promptIfBig = YES;
    const BOOL wasSilenced = [iTermWarning identifierIsSilenced:identifier];
    NSString *title;
    NSString *heading;
    if (displayInline) {
        title = [NSString stringWithFormat:@"The terminal has initiated display of a file named “%@” of size %@. Allow it?",
                 name, [NSString it_formatBytes:size]];
        heading = @"Allow Terminal-Initiated Display?";
    } else {
        title = [NSString stringWithFormat:@"The terminal has initiated transfer of a file named “%@” of size %@. Download it?",
                 name, [NSString it_formatBytes:size]];
        heading = @"Allow Terminal-Initiated Download?";
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:title
                               actions:@[ @"Yes", @"No" ]
                             accessory:nil
                            identifier:identifier
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:heading
                                window:_view.window];
    const BOOL allow = (selection == kiTermWarningSelection0);
    DLog(@"allow=%@", @(allow));
    if (allow && wasSilenced) {
        if (size > VT100ScreenBigFileDownloadThreshold) {
            *promptIfBig = NO;
            return [self screenConfirmDownloadNamed:name canExceedSize:VT100ScreenBigFileDownloadThreshold];
        }
    }
    return allow;
}

- (BOOL)clearScrollbackAllowed {
    if (self.naggingController.shouldAskAboutClearingScrollbackHistory) {
        return NO;
    }
    const BOOL *boolPtr = iTermAdvancedSettingsModel.preventEscapeSequenceFromClearingHistory;
    if (!boolPtr) {
        return NO;
    }
    return !*boolPtr;
}

- (void)screenAskAboutClearingScrollback {
    if (self.naggingController.shouldAskAboutClearingScrollbackHistory) {
        [self.naggingController askAboutClearingScrollbackHistory];
    }
}

- (void)screenDidResize {
    DLog(@"screenDidResize");
    [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionDidResizeNotification
                                                        object:self];
    [self.delegate sessionDidResize:self];
}

- (void)screenDidAppendImageData:(NSData *)data {
    if (!_logging.enabled) {
        return;
    }
    if (self.isTmuxGateway) {
        return;
    }
    switch (_logging.style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStylePlainText:
        case iTermLoggingStyleAsciicast:
            break;
        case iTermLoggingStyleHTML:
            [_logging logData:[data inlineHTMLData]];
            break;
    }
}

- (void)screenAppendScreenCharArray:(ScreenCharArray *)sca
                           metadata:(iTermImmutableMetadata)metadata
               lineBufferGeneration:(long long)lineBufferGeneration {
    [self publishScreenCharArray:sca
                        metadata:metadata
            lineBufferGeneration:lineBufferGeneration];
}

- (NSString *)screenStringForKeypressWithCode:(unsigned short)keycode
                                        flags:(NSEventModifierFlags)flags
                                   characters:(NSString *)characters
                  charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    return [self stringForKeyCode:keycode flags:flags characters:characters charactersIgnoringModifiers:charactersIgnoringModifiers];
}

- (NSString *)stringForKeyCode:(unsigned short)keycode
                         flags:(NSEventModifierFlags)flags
                    characters:(NSString *)characters
   charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:flags
                                     timestamp:0
                                  windowNumber:self.view.window.windowNumber
                                       context:nil
                                    characters:characters
                   charactersIgnoringModifiers:charactersIgnoringModifiers
                                     isARepeat:NO
                                       keyCode:keycode];
    return [_textview.keyboardHandler stringForEventWithoutSideEffects:event
                                                              encoding:_screen.terminalEncoding ?: NSUTF8StringEncoding];
}

- (void)screenApplicationKeypadModeDidChange:(BOOL)mode {
    self.variablesScope.applicationKeypad = mode;
}

- (void)screenRestoreColorsFromSlot:(VT100SavedColorsSlot *)slot {
    const BOOL dark = _screen.colorMap.darkMode;
    NSMutableDictionary *dict = [[@{ iTermAmendedColorKey(KEY_FOREGROUND_COLOR, _profile, dark): slot.text.dictionaryValue,
                                     iTermAmendedColorKey(KEY_BACKGROUND_COLOR, _profile, dark): slot.background.dictionaryValue,
                                     iTermAmendedColorKey(KEY_SELECTED_TEXT_COLOR, _profile, dark): slot.selectionText.dictionaryValue,
                                     iTermAmendedColorKey(KEY_SELECTION_COLOR, _profile, dark): slot.selectionBackground.dictionaryValue } mutableCopy] autorelease];
    for (int i = 0; i < MIN(kColorMapNumberOf8BitColors, slot.indexedColors.count); i++) {
        if (i < 16) {
            NSString *baseKey = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i];
            NSString *profileKey = iTermAmendedColorKey(baseKey, _profile, dark);
            dict[profileKey] = [slot.indexedColors[i] dictionaryValue];
        }
    }
    [self setSessionSpecificProfileValues:dict];
}

- (void)screenCopyStringToPasteboard:(NSString *)string {
    [self screenTerminalAttemptedPasteboardAccess];
    // check the configuration
    if (![iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        return;
    }

    // set the result to paste board.
    NSPasteboard *thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard clearContents];
    [thePasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [thePasteboard setString:string forType:NSPasteboardTypeString];
}

- (void)screenReportPasteboard:(NSString *)pasteboard completion:(void (^)(void))completion {
    if (!_pasteboardReporter) {
        _pasteboardReporter = [[iTermPasteboardReporter alloc] init];
        _pasteboardReporter.delegate = self;
    }
    [_pasteboardReporter handleRequestWithPasteboard:pasteboard completion:completion];
}

- (void)screenOfferToDisableTriggersInInteractiveApps {
    [self.naggingController offerToDisableTriggersInInteractiveApps];
}

- (void)screenDidUpdateReturnCodeForMark:(id<VT100ScreenMarkReading>)mark
                              remoteHost:(id<VT100RemoteHostReading>)remoteHost {
    [[iTermShellHistoryController sharedInstance] setStatusOfCommandAtMark:mark
                                                                    onHost:remoteHost
                                                                        to:mark.code];
    [self screenNeedsRedraw];
}

- (void)screenPostUserNotification:(NSString * _Nonnull)message rich:(BOOL)rich {
    if (![self shouldPostTerminalGeneratedAlert]) {
        DLog(@"Declining to allow terminal to post user notification %@", message);
        return;
    }
    DLog(@"Terminal posting user notification %@", message);
    [self incrementBadge];

    iTermNotificationController* controller = [iTermNotificationController sharedInstance];

    if (rich) {
        NSDictionary<NSString *, NSString *> *dict = [[message it_keyValuePairsSeparatedBy:@";"] mapValuesWithBlock:^id(NSString *key, NSString *encoded) {
            return [encoded stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
        }];
        NSString *description = dict[@"message"] ?: @"";
        NSString *title = dict[@"title"];
        NSString *subtitle = dict[@"subtitle"];
        NSString *image = [dict[@"image"] stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        [controller notifyRich:title
                  withSubtitle:subtitle
               withDescription:description
                     withImage:image
                   windowIndex:[self screenWindowIndex]
                      tabIndex:[self screenTabIndex]
                     viewIndex:[self screenViewIndex]];
    } else {
        NSString *description = [NSString stringWithFormat:@"Session %@ #%d: %@",
                                 [[self name] removingHTMLFromTabTitleIfNeeded],
                                 [_delegate tabNumber],
                                 message];
        [controller notify:@"Alert"
           withDescription:description
               windowIndex:[self screenWindowIndex]
                  tabIndex:[self screenTabIndex]
                 viewIndex:[self screenViewIndex]];
    }
}

- (void)screenUpdateCommandUseWithGuid:(NSString *)screenmarkGuid
                                onHost:(id<VT100RemoteHostReading>)lastRemoteHost
                         toReferToMark:(id<VT100ScreenMarkReading>)screenMark {
    iTermCommandHistoryCommandUseMO *commandUse =
    [[iTermShellHistoryController sharedInstance] commandUseWithMarkGuid:screenMark.guid
                                                                  onHost:lastRemoteHost];
    commandUse.mark = screenMark;
}

- (void)screenExecutorDidUpdate:(VT100ScreenTokenExecutorUpdate *)update {
    _estimatedThroughput = update.estimatedThroughput;
    DLog(@"estimated throughput: %@", @(_estimatedThroughput));

    if (update.numberOfBytesExecuted > 0) {
        DLog(@"Session %@ (%@) is processing", self, _nameController.presentationSessionTitle);
        if (![self haveResizedRecently]) {
            _lastOutputIgnoringOutputAfterResizing = [NSDate timeIntervalSinceReferenceDate];
        }
        // If you're in an interactive app in another tab it'll draw itself on
        // jiggle but we shouldn't count that as activity.
        if (self.shell.winSizeController.timeSinceLastJiggle > 0.25) {
            _newOutput = YES;
        }
        
        // Make sure the screen gets redrawn soonish
        self.active = YES;

        if (self.shell.pid > 0 || [[[self variablesScope] valueForVariableName:@"jobName"] length] > 0) {
            [self.processInfoProvider setNeedsUpdate:YES];
        }
    }

    [_cadenceController didHandleInputWithThroughput:_estimatedThroughput];
}

- (void)screenConvertAbsoluteRange:(VT100GridAbsCoordRange)range
              toTextDocumentOfType:(NSString *)type
                          filename:(NSString *)filename
                         forceWide:(BOOL)forceWide {
    [_textview renderRange:range type:type filename:filename forceWide:forceWide];
}

- (void)screenDidHookSSHConductorWithToken:(NSString *)token
                                  uniqueID:(NSString *)uniqueID
                                  boolArgs:(NSString *)boolArgs
                                   sshargs:(NSString *)sshargs
                                     dcsID:(NSString * _Nonnull)dcsID
                                savedState:(NSDictionary *)savedState {
    BOOL localOrigin = NO;
    if ([[iTermSecretServer instance] check:token]) {
        localOrigin = YES;
    }

    NSString *directory = nil;
    if (_sshState == iTermSSHStateProfile && !_conductor) {
        // Currently launching the session that has ssh instead of login shell.
        directory = self.environment[@"PWD"];
    }
    if (_pendingJumps.count) {
        directory = _pendingJumps[0].initialDirectory;
        [_pendingJumps removeObjectAtIndex:0];
    }
    iTermConductor *previousConductor = [_conductor autorelease];
    NSDictionary *dict = [NSDictionary castFrom:[iTermProfilePreferences objectForKey:KEY_SSH_CONFIG inProfile:self.profile]];
    const BOOL shouldInjectShellIntegration = [iTermProfilePreferences boolForKey:KEY_LOAD_SHELL_INTEGRATION_AUTOMATICALLY inProfile:self.profile];
    iTermSSHConfiguration *config = [[[iTermSSHConfiguration alloc] initWithDictionary:dict] autorelease];
    _conductor = [[iTermConductor alloc] init:sshargs
                                     boolArgs:boolArgs
                                        dcsID:dcsID
                               clientUniqueID:uniqueID
                                   varsToSend:localOrigin ? [self.screen exfiltratedEnvironmentVariables:config.environmentVariablesToCopy] : @{}
                                   clientVars:[self.screen exfiltratedEnvironmentVariables:nil] ?: @{}
                             initialDirectory:directory
                 shouldInjectShellIntegration:shouldInjectShellIntegration
                                       parent:previousConductor];
    _conductor.terminalConfiguration = savedState;
    if (localOrigin) {
        for (iTermTuple<NSString *, NSString *> *tuple in config.filesToCopy) {
            [_conductor addPath:tuple.firstObject destination:tuple.secondObject];
        }
    }
    _sshState = iTermSSHStateNone;
    _conductor.delegate = self;
    NSArray<iTermSSHReconnectionInfo *> *jumps = _pendingJumps;
    if (!previousConductor && jumps.count) {
        [_conductor startJumpingTo:jumps];
    } else if (previousConductor.subsequentJumps.count) {
        [_conductor startJumpingTo:previousConductor.subsequentJumps];
        [previousConductor childDidBeginJumping];
    } else {
        [_conductor start];
    }
    [self updateVariablesFromConductor];
}

- (void)screenDidReadSSHConductorLine:(NSString *)string depth:(int)depth {
    [_conductor handleLine:string depth:depth];
}

- (void)screenDidUnhookSSHConductor {
    [_conductor handleUnhook];
    [self writeData:_sshWriteQueue];
    [_sshWriteQueue release];
    _sshWriteQueue = nil;
}

- (void)unhookSSHConductor {
    DLog(@"Unhook %@", _conductor);
    [self conductorWillDie];
    NSDictionary *config = _conductor.terminalConfiguration;
    if (config) {
        [_screen restoreSavedState:config];
    }
    _conductor.delegate = nil;
    [_conductor autorelease];
    _conductor = [_conductor.parent retain];
    _conductor.delegate = self;
    [self updateVariablesFromConductor];
}

- (void)screenDidBeginSSHConductorCommandWithIdentifier:(NSString *)identifier
                                                  depth:(int)depth {
    [_conductor handleCommandBeginWithIdentifier:identifier depth:depth];
}

- (void)screenDidEndSSHConductorCommandWithIdentifier:(NSString *)identifier
                                                 type:(NSString *)type
                                               status:(uint8_t)status
                                                depth:(int)depth {
    [_conductor handleCommandEndWithIdentifier:identifier
                                          type:type
                                        status:status
                                         depth:depth];
}

- (void)screenHandleSSHSideChannelOutput:(NSString *)string
                                     pid:(int32_t)pid
                                 channel:(uint8_t)channel
                                   depth:(int)depth {
    [_conductor handleSideChannelOutput:string pid:pid channel:channel depth:depth];
}

- (void)screenDidTerminateSSHProcess:(int)pid code:(int)code depth:(int)depth {
    [_conductor handleTerminatePID:pid withCode:code depth:depth];
}

- (NSInteger)screenEndSSH:(NSString *)uniqueID {
    DLog(@"%@", uniqueID);
    _connectingSSH = NO;
    if (![_conductor ancestryContainsClientUniqueID:uniqueID]) {
        DLog(@"Ancestry does not contain this unique ID");
        return 0;
    }
    BOOL found = NO;
    NSInteger count = 0;
    while (_conductor != nil && !found) {
        found = [_conductor.clientUniqueID isEqual:uniqueID];
        count += 1;
        [self unhookSSHConductor];
    }
    // it2ssh waits for a newline before exiting. This is in case ssh dies while iTerm2 is sending
    // conductor.sh.
    [self writeTaskNoBroadcast:@"\n"];
    if (_queuedConnectingSSH.length) {
        [_queuedConnectingSSH release];
        _queuedConnectingSSH = nil;
    }
    return count;
}

- (void)screenWillBeginSSHIntegration {
    _connectingSSH = YES;
    [_queuedConnectingSSH release];
    _queuedConnectingSSH = [[NSMutableData alloc] init];
}

- (void)screenBeginSSHIntegrationWithToken:(NSString *)token
                                  uniqueID:(NSString *)uniqueID
                                 encodedBA:(NSString *)encodedBA
                                   sshArgs:(NSString *)sshArgs {
    NSURL *path = [[NSBundle bundleForClass:[PTYSession class]] URLForResource:@"conductor" withExtension:@"sh"];
    NSString *conductorSH = [NSString stringWithContentsOfURL:path encoding:NSUTF8StringEncoding error:nil];
    // Ensure it doesn't contain empty lines.
    conductorSH = [conductorSH stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n \n"];

    NSString *message = [NSString stringWithFormat:@"%@main %@ %@ %@ %@",
                         conductorSH,
                         [token base64EncodedWithEncoding:NSUTF8StringEncoding],
                         [uniqueID base64EncodedWithEncoding:NSUTF8StringEncoding],
                         [encodedBA base64EncodedWithEncoding:NSUTF8StringEncoding],
                         [sshArgs base64EncodedWithEncoding:NSUTF8StringEncoding]];
    [self writeTaskNoBroadcast:[@"\n-- BEGIN CONDUCTOR --\n" stringByAppendingString:[[message base64EncodedWithEncoding:NSUTF8StringEncoding] chunkedWithLineLength:80 separator:@"\n"]]];
    // Terminate with an esc on its own line.
    [self writeTaskNoBroadcast:@"\n\e\n"];
}

- (NSString *)screenSSHLocation {
    return _conductor.sshIdentity.compactDescription;
}

- (void)screenBeginFramerRecovery:(int)parentDepth {
    if (parentDepth < 0) {
        while (_conductor) {
            [self unhookSSHConductor];
        }
    }
    iTermConductor *previousConductor = [_conductor autorelease];
    _conductor = [[iTermConductor alloc] init:@""
                                     boolArgs:@""
                                        dcsID:@""
                               clientUniqueID:@""
                                   varsToSend:@{}
                                   clientVars:@{}
                             initialDirectory:nil
                 shouldInjectShellIntegration:NO
                                       parent:previousConductor];
    [self updateVariablesFromConductor];
    _conductor.delegate = self;
    [_conductor startRecovery];
}

- (iTermConductorRecovery *)screenHandleFramerRecoveryString:(NSString * _Nonnull)string {
    iTermConductorRecovery *recovery = [_conductor handleRecoveryLine:string];
    if (!recovery) {
        return nil;
    }
    _conductor.delegate = nil;
    [_conductor autorelease];
    _conductor = [[iTermConductor alloc] initWithRecovery:recovery];
    _conductor.delegate = self;
    [self updateVariablesFromConductor];
    return recovery;
}

// This is the final step of recovery. We need to reset the internal state of the conductors since
// some tokens may have been dropped during recovery.
- (void)screenDidResynchronizeSSH {
    [_conductor didResynchronize];
}

- (void)screenFramerRecoveryDidFinish {
    [_conductor recoveryDidFinish];
}

- (void)screenEnsureDefaultMode {
    [self resetMode];
}

- (void)resetMode {
    _modeHandler.mode = iTermSessionModeDefault;
}

- (void)screenOpenURL:(NSURL *)url completion:(void (^)(void))completion {
    DLog(@"url=%@", url);
    [self.naggingController openURL:url];
    completion();
}

- (void)enclosingTabWillBeDeselected {
    DLog(@"enclosingTabWillBeDeselected %@", self);
    if (_alertOnMarksinOffscreenSessions) {
        [self sync];
    }
}

- (void)enclosingTabDidBecomeSelected {
    DLog(@"enclosingTabDidBecomeSelected %@", self);
    if (_alertOnMarksinOffscreenSessions) {
        [self sync];
    }
}

- (BOOL)popupWindowShouldAvoidChangingWindowOrderOnClose {
    return [iTermPreferences boolForKey:kPreferenceKeyFocusFollowsMouse] && ![self.delegate sessionBelongsToHotkeyWindow:self];
}

- (VT100Screen *)popupVT100Screen {
    return _screen;
}

- (id<iTermPopupWindowPresenter>)popupPresenter {
    return self;
}

- (void)popupInsertText:(NSString *)string {
    id<iTermPopupWindowHosting> host = [self popupHost];
    if (host) {
        [host popupWindowHostingInsertText:string];
        return;
    }
    if (_composerManager.dropDownComposerViewIsVisible) {
        [_composerManager insertText:string];
        return;
    }
    [self insertText:string];
}

- (void)popupPreview:(NSString *)text {
    id<iTermPopupWindowHosting> host = [self popupHost];
    if (host) {
        [host popupWindowHostSetPreview:[[text firstNonEmptyLine] truncatedToLength:_screen.width ellipsis:@"…"]];
        return;
    }
}

- (void)popupKeyDown:(NSEvent *)event {
    [_textview keyDown:event];
}

- (BOOL)composerCommandHistoryIsOpen {
    if (!_composerManager.dropDownComposerViewIsVisible) {
        return NO;
    }
    return [[_delegate realParentWindow] commandHistoryIsOpenForSession:self];
}

- (BOOL)popupHandleSelector:(SEL)selector
                     string:(NSString *)string
               currentValue:(NSString *)currentValue {
    if ([self composerCommandHistoryIsOpen]) {
        if (selector == @selector(deleteBackward:)) {
            [[_delegate realParentWindow] closeCommandHistory];
            [_composerManager deleteLastCharacter];
            return YES;
        }
        return NO;
    }
    if (![[_delegate realParentWindow] autoCommandHistoryIsOpenForSession:self]) {
        return NO;
    }
    if (selector == @selector(cancel:)) {
        [[_delegate realParentWindow] hideAutoCommandHistoryForSession:self];
        return YES;
    }
    if (selector == @selector(insertNewline:)) {
        if ([currentValue isEqualToString:[self currentCommand]]) {
            // Send the enter key on.
            [self insertText:@"\n"];
            return YES;
        } else {
            return NO;  // select the row
        }
    }
    if (selector == @selector(deleteBackward:)) {
        [_textview keyDown:[NSEvent keyEventWithType:NSEventTypeKeyDown
                                            location:NSZeroPoint
                                       modifierFlags:[NSEvent modifierFlags]
                                           timestamp:0
                                        windowNumber:_textview.window.windowNumber
                                             context:nil
                                          characters:@"\x7f"
                         charactersIgnoringModifiers:@"\x7f"
                                           isARepeat:NO
                                             keyCode:51]];  // 51 is the keycode for delete; not in any header file :(
        return YES;
    }
    if (selector == @selector(insertText:) || selector == @selector(insertTab:)) {
        [self insertText:string];
        return YES;
    }
    return NO;
}

#pragma mark - iTermPasteHelperDelegate

- (void)pasteHelperWriteString:(NSString *)string {
    [self writeTask:string];
    if (_pasteHelper.pasteContext.bytesWritten == 0 &&
        (_pasteHelper.pasteContext.pasteEvent.flags & kPasteFlagsBracket) &&
        _screen.terminalBracketedPasteMode) {
        [self watchForPasteBracketingOopsieWithPrefix:[_pasteHelper.pasteContext.pasteEvent.originalString it_substringToIndex:4]];
    }
}

- (void)pasteHelperKeyDown:(NSEvent *)event {
    [_textview keyDown:event];
}

- (BOOL)pasteHelperShouldBracket {
    return _screen.terminalBracketedPasteMode;
}

- (NSStringEncoding)pasteHelperEncoding {
    return _screen.terminalEncoding;
}

- (NSView *)pasteHelperViewForIndicator {
    return _view;
}

- (iTermStatusBarViewController *)pasteHelperStatusBarViewController {
    return _statusBarViewController;
}

- (BOOL)pasteHelperShouldWaitForPrompt {
    if (!_screen.shouldExpectPromptMarks) {
        return NO;
    }

    return self.currentCommand == nil;
}

- (BOOL)pasteHelperIsAtShellPrompt {
    return [self currentCommand] != nil;
}

- (BOOL)pasteHelperCanWaitForPrompt {
    return _screen.shouldExpectPromptMarks;
}

- (void)pasteHelperPasteViewVisibilityDidChange {
    [self.delegate sessionUpdateMetalAllowed];
}

- (iTermVariableScope *)pasteHelperScope {
    return self.variablesScope;
}

#pragma mark - iTermAutomaticProfileSwitcherDelegate

- (NSString *)automaticProfileSwitcherSessionName {
    return [NSString stringWithFormat:@"%@ — %@", [_nameController presentationSessionTitle], self.tty];
}

- (iTermSavedProfile *)automaticProfileSwitcherCurrentSavedProfile {
    iTermSavedProfile *savedProfile = [[[iTermSavedProfile alloc] init] autorelease];
    savedProfile.profile = _profile;
    savedProfile.originalProfile = _originalProfile;
    savedProfile.isDivorced = self.isDivorced;
    savedProfile.overriddenFields = [[_overriddenFields mutableCopy] autorelease];
    return savedProfile;
}

- (NSDictionary *)automaticProfileSwitcherCurrentProfile {
    return _originalProfile;
}

- (void)automaticProfileSwitcherLoadProfile:(iTermSavedProfile *)savedProfile {
    Profile *underlyingProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:savedProfile.originalProfile[KEY_GUID]];
    Profile *replacementProfile = underlyingProfile ?: savedProfile.originalProfile;
    [self setProfile:replacementProfile preservingName:NO adjustWindow:NO];
    if (savedProfile.isDivorced) {
        NSMutableDictionary *overrides = [NSMutableDictionary dictionary];
        for (NSString *key in savedProfile.overriddenFields) {
            if ([key isEqualToString:KEY_GUID] || [key isEqualToString:KEY_ORIGINAL_GUID]) {
                continue;
            }
            overrides[key] = savedProfile.profile[key];
        }
        [self setSessionSpecificProfileValues:overrides];
    }
    if ([iTermAdvancedSettingsModel showAutomaticProfileSwitchingBanner]) {
        [_view showUnobtrusiveMessage:[NSString stringWithFormat:@"Switched to profile “%@”.", underlyingProfile[KEY_NAME]]];
    }
}

- (NSArray<NSDictionary *> *)automaticProfileSwitcherAllProfiles {
    return [[ProfileModel sharedInstance] bookmarks];
}

#pragma mark - iTermSessionViewDelegate

- (NSRect)sessionViewFrameForLegacyView {
    const CGFloat bottomMarginHeight = [_textview excess];
    return NSMakeRect(0,
                      bottomMarginHeight,
                      NSWidth(_textview.bounds),
                      _textview.lineHeight * _screen.height);
}

- (CGFloat)sessionViewBottomMarginHeight {
    return [_textview excess];
}
- (CGFloat)sessionViewTransparencyAlpha {
    return _textview.transparencyAlpha;
}

- (void)sessionViewMouseEntered:(NSEvent *)event {
    DLog(@"sessionViewMouseEntered");
    [_textview mouseEntered:event];
    [_textview requestDelegateRedraw];
    [_textview updateCursor:event];
}

- (void)sessionViewMouseExited:(NSEvent *)event {
    [_textview mouseExited:event];
    [_textview requestDelegateRedraw];
    [_textview updateCursor:event];
}

- (void)sessionViewMouseMoved:(NSEvent *)event {
    [_textview mouseMoved:event];
}

- (void)sessionViewRightMouseDown:(NSEvent *)event {
    [_textview rightMouseDown:event];
}

- (BOOL)sessionViewShouldForwardMouseDownToSuper:(NSEvent *)event {
    return [_textview mouseDownImpl:event];
}

- (void)sessionViewDimmingAmountDidChange:(CGFloat)newDimmingAmount {
    [self sync];
    [_textview requestDelegateRedraw];
}

- (BOOL)sessionViewIsVisible {
    return YES;
}

- (void)sessionViewDraggingExited:(id<NSDraggingInfo>)sender {
    [self.delegate sessionDraggingExited:self];
    [_textview requestDelegateRedraw];
}

- (NSDragOperation)sessionViewDraggingEntered:(id<NSDraggingInfo>)sender {
    [self.delegate sessionDraggingEntered:self];

    PTYSession *movingSession = [[MovePaneController sharedInstance] session];
    if (![_delegate session:self shouldAllowDrag:sender]) {
        return NSDragOperationNone;
    }

    if (!([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound)) {
        if ([[MovePaneController sharedInstance] isMovingSession:self]) {
            // Moving me onto myself
            return NSDragOperationMove;
        } else if (![movingSession isCompatibleWith:self]) {
            // We must both be non-tmux or belong to the same session.
            return NSDragOperationNone;
        }
    }

    [self.view createSplitSelectionView];
    return NSDragOperationMove;
}

- (BOOL)sessionViewShouldSplitSelectionAfterDragUpdate:(id<NSDraggingInfo>)sender {
    if ([[[sender draggingPasteboard] types] indexOfObject:iTermMovePaneDragType] != NSNotFound &&
        [[MovePaneController sharedInstance] isMovingSession:self]) {
        return NO;
    }
    return YES;
}

- (BOOL)sessionViewPerformDragOperation:(id<NSDraggingInfo>)sender {
    return [_delegate session:self performDragOperation:sender];
}

- (NSString *)sessionViewTitle {
    return _nameController.presentationSessionTitle;
}

- (NSSize)sessionViewCellSize {
    return NSMakeSize([_textview charWidth], [_textview lineHeight]);
}

- (VT100GridSize)sessionViewGridSize {
    return VT100GridSizeMake(_screen.width, _screen.height);
}

- (NSColor *)sessionViewBackgroundColor {
    return [_screen.colorMap colorForKey:kColorMapBackground];
}

- (BOOL)textViewOrComposerIsFirstResponder {
    return ((_textview.window.firstResponder == _textview ||
             [_composerManager dropDownComposerIsFirstResponder]) &&
            [NSApp isActive] &&
            _textview.window.isKeyWindow);
}

- (void)textViewShowFindPanel {
    const BOOL findPanelWasOpen = self.view.findDriver.viewController.searchIsVisible;
    [self showFindPanel];
    if (!findPanelWasOpen) {
        [self.view.findDriver setFilterHidden:YES];
    }
    [[iTermFindPasteboard sharedInstance] updateObservers:nil internallyGenerated:YES];
}

- (void)textViewEnterShortcutNavigationMode {
    _modeHandler.mode = iTermSessionModeShortcutNavigation;
}

- (void)textViewExitShortcutNavigationMode {
    if (_modeHandler.mode == iTermSessionModeShortcutNavigation) {
        _modeHandler.mode = iTermSessionModeDefault;
    }
}

- (void)textViewWillHandleMouseDown:(NSEvent *)event {
    if (_modeHandler.mode == iTermSessionModeShortcutNavigation) {
        _modeHandler.mode = iTermSessionModeDefault;
    }
}

- (BOOL)textViewPasteFiles:(NSArray<NSString *> *)filenames {
    NSString *swifty = [iTermAdvancedSettingsModel fileDropCoprocess];
    if (swifty.length == 0) {
        return NO;
    }
    iTermVariableScope *scope = [[[self variablesScope] copy] autorelease];
    iTermVariables *frame = [[[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self] autorelease];
    [scope addVariables:frame toScopeNamed:nil];
    NSString *joinedFilenames = [filenames componentsJoinedByString:@" "];
    [scope setValue:joinedFilenames forVariableNamed:@"filenames"];

    iTermExpressionEvaluator *eval = [[[iTermExpressionEvaluator alloc] initWithInterpolatedString:swifty
                                                                                             scope:scope] autorelease];
    __weak __typeof(self) weakSelf = self;
    [eval evaluateWithTimeout:5 completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        if (![NSString castFrom:evaluator.value]) {
            return;
        }
        [weakSelf runCoprocessWithCompletion:^(id output, NSError *error){}
                                 commandLine:evaluator.value
                                        mute:@YES];
    }];
    return YES;
}

- (NSString *)textViewNaturalLanguageQuery {
    return [self naturalLanguageQuery];
}

- (NSString *)naturalLanguageQuery {
    NSString *query = nil;
    if (_textview.selection.hasSelection) {
        query = _textview.selectedText;
    } else {
        query = self.currentCommand;
    }
    if (query.length == 0) {
        return [self requestNaturalLanguageQuery];
    }
    if (query.length >= [iTermAdvancedSettingsModel aiResponseMaxTokens] / 8) {
        return nil;
    }
    return query;
}

- (NSString *)requestNaturalLanguageQuery {
    if (![iTermAITermGatekeeper check]) {
        return nil;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Describe the command you want to run in plain English. Press ⇧⏎ to send."];
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    ShiftEnterTextView *input = [[[ShiftEnterTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    input.richText = NO;
    [input setVerticallyResizable:YES];
    [input setHorizontallyResizable:NO];
    [input setAutoresizingMask:NSViewWidthSizable];
    [[input textContainer] setContainerSize:NSMakeSize(200, FLT_MAX)];
    [[input textContainer] setWidthTracksTextView:YES];
    [input setTextContainerInset:NSMakeSize(4, 4)];
    __weak __typeof(alert) weakAlert = alert;
    input.shiftEnterPressed = ^{
        [weakAlert.buttons.firstObject performClick:nil];
    };
    NSScrollView *scrollview = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    [scrollview setHasVerticalScroller:YES];
    [scrollview setDocumentView:input];
    scrollview.borderType = NSLineBorder;

    [alert setAccessoryView:scrollview];
    alert.window.initialFirstResponder = input;
    dispatch_async(dispatch_get_main_queue(), ^{
        [input.window makeFirstResponder:input];
    });
    const NSInteger button = [alert runSheetModalForWindow:self.view.window];

    if (button == NSAlertFirstButtonReturn) {
        return [[input string] copy];
    } else if (button == NSAlertSecondButtonReturn) {
        return nil;
    }

    return nil;
}

- (void)textViewPerformNaturalLanguageQuery {
    NSString *query = [self naturalLanguageQuery];
    if (!query) {
        return;
    }
    [_aiterm release];
    __weak __typeof(self) weakSelf = self;
    _aiterm = [[AITermControllerObjC alloc] initWithQuery:query
                                                    scope:self.variablesScope
                                                 inWindow:self.view.window
                                               completion:^(NSArray<NSString *> * _Nullable choices, NSString * _Nullable error) {
        [weakSelf handleAIChoices:choices error:error];
    }];
}

- (void)textViewUpdateTrackingAreas {
    [self.view updateTrackingAreas];
}

- (BOOL)textViewShouldShowOffscreenCommandLine {
    if (_screen.height < 5) {
        return NO;
    }
    if (_modeHandler.mode == iTermSessionModeCopy) {
        return NO;
    }
    return [iTermProfilePreferences boolForKey:KEY_SHOW_OFFSCREEN_COMMANDLINE inProfile:self.profile];
}

- (BOOL)textViewShouldUseSelectedTextColor {
    const BOOL dark = [NSApp effectiveAppearance].it_isDark;
    NSString *key = iTermAmendedColorKey(KEY_USE_SELECTED_TEXT_COLOR, self.profile, dark);
    return [iTermProfilePreferences boolForKey:key inProfile:self.profile];
}

- (void)handleAIChoices:(NSArray<NSString *> *)choices error:(NSString *)error {
    if (error) {
        [iTermWarning showWarningWithTitle:error
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"AI Error"
                                    window:self.view.window];
        return;
    }
    if (choices.count == 0) {
        return;
    }
    [self setComposerString:choices[0]];
    [self.composerManager toggle];
    DLog(@"handleAIChoices -> makeComposerFirstResponder");
    [self makeComposerFirstResponderIfAllowed];
}

- (BOOL)sessionViewTerminalIsFirstResponder {
    return [self textViewOrComposerIsFirstResponder];
}

- (BOOL)sessionViewShouldDimOnlyText {
    return [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
}

- (NSColor *)sessionViewTabColor {
    return self.tabColor;
}

- (NSMenu *)sessionViewContextMenu {
    return [_textview titleBarMenu];
}

- (void)sessionViewConfirmAndClose {
    [[_delegate realParentWindow] closeSessionWithConfirmation:self];
}

- (void)sessionViewBeginDrag {
    if (![[MovePaneController sharedInstance] session]) {
        [[MovePaneController sharedInstance] beginDrag:self];
    }
}

- (CGFloat)sessionViewDesiredHeightOfDocumentView {
    return _textview.desiredHeight + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
}

- (BOOL)sessionViewShouldUpdateSubviewsFramesAutomatically {
    [_composerManager layout];
    
    // We won't automatically layout the session view's descendents for tmux
    // tabs. Instead the change gets reported to the tmux server and it will
    // send us a new layout.
    if (self.isTmuxClient) {
        // This makes dragging a split pane in a tmux tab look way better.
        return ![_delegate sessionBelongsToTmuxTabWhoseSplitsAreBeingDragged];
    } else {
        return YES;
    }
}

- (NSSize)sessionViewScrollViewWillResize:(NSSize)proposedSize {
    if ([self isTmuxClient] && ![_delegate sessionBelongsToTmuxTabWhoseSplitsAreBeingDragged]) {
        NSSize idealSize = [self idealScrollViewSizeWithStyle:_view.scrollview.scrollerStyle];
        NSSize maximumSize = NSMakeSize(idealSize.width + _textview.charWidth - 1,
                                        idealSize.height + _textview.lineHeight - 1);
        DLog(@"is a tmux client, so tweaking the proposed size. idealSize=%@ maximumSize=%@",
             NSStringFromSize(idealSize), NSStringFromSize(maximumSize));
        return NSMakeSize(MIN(proposedSize.width, maximumSize.width),
                          MIN(proposedSize.height, maximumSize.height));
    } else {
        return proposedSize;
    }
}

- (CGFloat)backingScaleFactor {
    return self.delegate.realParentWindow.window.backingScaleFactor ?: self.view.window.backingScaleFactor;
}

// Ensure the wrapper is at least as tall as its enclosing scroll view. Mostly this goes unnoticed
// except in Monterey betas (see issue 9799) but it's the right thing to do regardless.
- (NSRect)safeFrameForWrapperViewFrame:(NSRect)proposed {
    const CGFloat minimumHeight = _view.scrollview.contentSize.height;
    if (NSHeight(proposed) >= minimumHeight) {
        return proposed;
    }
    NSRect frame = proposed;
    frame.size.height = minimumHeight;
    DLog(@"Convert proposed wrapper frame %@ to %@", NSStringFromRect(proposed), NSStringFromRect(frame));
    return frame;
}

- (void)sessionViewScrollViewDidResize {
    DLog(@"sessionViewScrollViewDidResize to %@", NSStringFromRect(_view.scrollview.frame));
    [self updateTTYSize];
    _wrapper.frame = [self safeFrameForWrapperViewFrame:_wrapper.frame];
}

- (BOOL)updateTTYSize {
    DLog(@"%@\n%@", self, [NSThread callStackSymbols]);
    return [_shell.winSizeController setGridSize:_screen.size
                                        viewSize:_screen.viewSize
                                     scaleFactor:self.backingScaleFactor];
}

- (iTermStatusBarViewController *)sessionViewStatusBarViewController {
    return _statusBarViewController;
}

- (void)textViewOpenComposer:(NSString *)string {
    [self setComposerString:string];
    [self.composerManager toggle];
}

- (BOOL)textViewIsAutoComposerOpen {
    return [_composerManager dropDownComposerViewIsVisible] && _composerManager.isAutoComposer && !_composerManager.temporarilyHidden;
}

- (CGFloat)textViewPointsOnBottomToSuppressDrawing {
    if ([_composerManager dropDownComposerViewIsVisible] && _composerManager.isAutoComposer && !_composerManager.temporarilyHidden) {
        const NSRect rect = _composerManager.dropDownFrame;
        return NSMaxY(rect);
    }
    return 0;
}

- (VT100GridRange)textViewLinesToSuppressDrawing {
    if ([_composerManager dropDownComposerViewIsVisible] && _composerManager.isAutoComposer && !_composerManager.temporarilyHidden) {
        const NSRect rect = _composerManager.dropDownFrame;
        const NSRect textViewRect = [_textview convertRect:rect fromView:_view];
        const VT100GridCoord topLeft = [_textview coordForPoint:textViewRect.origin allowRightMarginOverflow:NO];
        const VT100GridCoord bottomRight = [_textview coordForPoint:NSMakePoint(NSMaxX(textViewRect) - 1,
                                                                                NSMaxY(textViewRect) - 1)
                                           allowRightMarginOverflow:NO];
        return VT100GridRangeMake(topLeft.y, bottomRight.y - topLeft.y + 1);
    }
    return VT100GridRangeMake(0, 0);
}

- (NSRect)textViewCursorFrameInScreenCoords {
    const int cx = [self.screen cursorX] - 1;
    const int cy = [self.screen cursorY];
    const CGFloat charWidth = [self.textview charWidth];
    const CGFloat lineHeight = [self.textview lineHeight];
    NSPoint p = NSMakePoint([iTermPreferences doubleForKey:kPreferenceKeySideMargins] + cx * charWidth,
                            ([self.screen numberOfLines] - [self.screen height] + cy) * lineHeight);
    const NSPoint origin = [self.textview.window pointToScreenCoords:[self.textview convertPoint:p toView:nil]];
    return NSMakeRect(origin.x,
                      origin.y,
                      charWidth,
                      lineHeight);
}

- (void)textViewDidReceiveSingleClick {
    DLog(@"textViewDidReceiveSingleClick");
}

- (void)textViewDisableOffscreenCommandLine {
    if (self.isDivorced) {
        [self setSessionSpecificProfileValues:@{
            KEY_SHOW_OFFSCREEN_COMMANDLINE: @NO
        }];
        return;
    }
    [iTermProfilePreferences setBool:NO
                              forKey:KEY_SHOW_OFFSCREEN_COMMANDLINE
                           inProfile:self.profile
                               model:[ProfileModel sharedInstance]];
}

- (void)textViewSaveScrollPositionForMark:(id<VT100ScreenMarkReading>)mark withName:(NSString *)name {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setName:name forMark:(VT100ScreenMark *)mark.progenitor];
    }];
}

- (void)textViewRemoveBookmarkForMark:(id<VT100ScreenMarkReading>)mark {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setName:nil forMark:(VT100ScreenMark *)mark.progenitor];
    }];
}

- (BOOL)textViewEnclosingTabHasMultipleSessions {
    return [[self.delegate sessions] count] > 1;
}

- (BOOL)textViewSelectionScrollAllowed {
    if (![iTermProfilePreferences boolForKey:KEY_DRAG_TO_SCROLL_IN_ALTERNATE_SCREEN_MODE_DISABLED
                                   inProfile:self.profile]) {
        return YES;
    }
    const BOOL alt = [self.screen terminalSoftAlternateScreenMode];
    const BOOL bottom = _textview.scrolledToBottom;
    DLog(@"alt=%@ bottom=%@", @(alt), @(bottom));
    return !(alt && bottom);    
}

- (id<VT100ScreenMarkReading>)textViewSelectedCommandMark {
    return _selectedCommandMark;
}

- (id<VT100ScreenMarkReading>)textViewMarkForCommandAt:(VT100GridCoord)coord {
    return [_screen commandMarkAtOrBeforeLine:coord.y];
}

- (void)textViewSelectCommandRegionAtCoord:(VT100GridCoord)coord {
    id<VT100ScreenMarkReading> mark = [_screen commandMarkAtOrBeforeLine:coord.y];
    if (mark == _selectedCommandMark) {
        mark = nil;
    }
    const BOOL allowed = [iTermPreferences boolForKey:kPreferenceKeyClickToSelectCommand];
    if (!allowed) {
        mark = nil;
    }
    [self selectCommandWithMarkIfSafe:mark];
    if (allowed && mark != nil) {
        NSString *const warningKey = @"NoSyncUserHasSelectedCommand";
        if (mark != nil && ![[NSUserDefaults standardUserDefaults] boolForKey:warningKey]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:warningKey];
            [self showCommandSelectionInfo];
        }
    }
}

// Does nothing if the selected command would include the mutable part of the alternate screen.
- (void)selectCommandWithMarkIfSafe:(id<VT100ScreenMarkReading>)mark {
    if (mark && _screen.terminalSoftAlternateScreenMode) {
        const VT100GridAbsCoordRange absRange = [self rangeOfCommandAndOutputForMark:mark];
        const NSRange markRange = NSMakeRange(absRange.start.y, MAX(0, absRange.end.y - absRange.start.y + 1));
        const NSRange screenRange = NSMakeRange(_screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow,
                                                _screen.height);
        if (NSIntersectionRange(markRange, screenRange).length > 0) {
            DLog(@"Not allowing selection that includes screen in alternate screen mode. markRange=%@ screenRange=%@", NSStringFromRange(markRange), NSStringFromRange(screenRange));
            return;
        }
    }
    [self selectCommandWithMark:mark];
}

- (void)selectCommandWithMark:(id<VT100ScreenMarkReading>)mark {
    id<VT100ScreenMarkReading> previous = _selectedCommandMark;
    _selectedCommandMark = mark;
    [self updateSearchRange];
    _screen.savedFindContextAbsPos = 0;
    if (previous != _selectedCommandMark) {
        [_textview requestDelegateRedraw];
    }
}

- (VT100GridAbsCoordRange)textViewCoordRangeForCommandAndOutputAtMark:(id<iTermMark>)mark {
    if ([mark conformsToProtocol:@protocol(VT100ScreenMarkReading)]) {
        return [self rangeOfCommandAndOutputForMark:(id<VT100ScreenMarkReading>)mark];
    }
    return [_screen absCoordRangeForInterval:mark.entry.interval];
}

- (void)showCommandSelectionInfo {
    const NSPoint point = [_view convertPoint:NSApp.currentEvent.locationInWindow
                                     fromView:nil];
    NSString *html = @"You’ve selected a command by clicking on it. This restricts Find, Filter, and Select All to the content of the command. You can turn this feature off in Settings > General > Selection. <a href=\"iterm2:disable-command-selection\">Click here to disable this feature.</a>";
    NSAttributedString *attributedString = [NSAttributedString attributedStringWithHTML:html
                                                                                   font:[NSFont systemFontOfSize:[NSFont systemFontSize]]
                                                                         paragraphStyle:[NSParagraphStyle defaultParagraphStyle]];
    [_view it_showWarningWithAttributedString:attributedString
                                         rect:NSMakeRect(point.x, point.y, 1, 1)];
}

- (void)showHorizontalScrollInfo {
    if ([iTermSwipeTracker isSwipeTrackingDisabled]) {
        return;
    }
    if ([[[_delegate realParentWindow] tabs] count] < 2) {
        return;
    }
    NSString *const warningKey = @"NoSyncScrollingHorizontally";
    if ([[NSUserDefaults standardUserDefaults] boolForKey:warningKey]) {
        return;
    }
    NSString *identifier = @"HorizontalScrollWarning";
    if (_announcements[identifier]) {
        // Already showing it
        return;
    }
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:@"When mouse reporting is on, horizontal scrolling does not switch tabs.\nHold option while swiping or disable horizontal scroll reporting to switch tabs."
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"Settings…" ]
                                                completion:^(int selection) {
        switch (selection) {
            case -2: // Dismiss programmatically
            case -1:  // Closed
                break;
            case 0:
                // Disable reporting
                [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyReportHorizontalScrollEvents];
                break;
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:warningKey];
    }];
    [self queueAnnouncement:announcement identifier:identifier];

}

- (void)textViewRemoveSelectedCommand {
    if (!_selectedCommandMark) {
        return;
    }
    [self removeSelectedCommandRange];
}

- (NSCursor *)textViewDefaultPointer {
    return self.defaultPointer;
}

- (void)removeSelectedCommandRange {
    if (!_selectedCommandMark) {
        return;
    }
    _selectedCommandMark = nil;
    [self updateSearchRange];
    _screen.savedFindContextAbsPos = 0;
    [_textview requestDelegateRedraw];
}

- (void)updateSearchRange {
    if (!_selectedCommandMark) {
        _textview.findOnPageHelper.absLineRange = NSMakeRange(0, 0);
        return;
    }
    VT100GridAbsCoordRange range = [self rangeOfCommandAndOutputForMark:_selectedCommandMark];
    if (_selectedCommandMark.lineStyle) {
        _textview.findOnPageHelper.absLineRange = NSMakeRange(MAX(0, range.start.y - 1),
                                                              range.end.y - range.start.y + 1);
    } else {
        _textview.findOnPageHelper.absLineRange = NSMakeRange(range.start.y, range.end.y - range.start.y + 1);
    }
}

- (VT100GridAbsCoordRange)rangeOfCommandAndOutputForMark:(id<VT100ScreenMarkReading>)mark {
    VT100GridAbsCoordRange range;
    range.start = [_screen absCoordRangeForInterval:mark.entry.interval].start;

    id<VT100ScreenMarkReading> successor = [_screen promptMarkAfterPromptMark:mark];
    if (successor) {
        range.end = [_screen absCoordRangeForInterval:successor.entry.interval].start;
        range.end.y -= 1;
    } else {
        range.end = VT100GridAbsCoordMake(_screen.width - 1, _screen.numberOfLines + _screen.totalScrollbackOverflow);
    }
    return range;
}

#pragma mark - iTermHotkeyNavigableSession

- (void)sessionHotkeyDidNavigateToSession:(iTermShortcut *)shortcut {
    [self reveal];
}

- (BOOL)sessionHotkeyIsAlreadyFirstResponder {
    return ([NSApp isActive] &&
            [NSApp keyWindow] == self.textview.window &&
            self.textview.window.firstResponder == self.textview);
}

- (BOOL)sessionHotkeyIsAlreadyActiveInNonkeyWindow {
    if ([NSApp isActive] &&
        [NSApp keyWindow] == self.textview.window) {
        return NO;
    }
    return [self.delegate sessionIsActiveInSelectedTab:self];
}

- (void)sessionViewDoubleClickOnTitleBar {
    [self.delegate sessionDoubleClickOnTitleBar:self];
}

- (void)sessionViewBecomeFirstResponder {
    [self.textview.window makeFirstResponder:self.textview];
}

- (void)sessionViewDidChangeWindow {
    [self invalidateBlend];
    [self updateMetalDriver];
    if (!_shell.ttySizeInitialized) {
        if ([self updateTTYSize]) {
            _shell.ttySizeInitialized = YES;
        }
    }
}

- (void)sessionViewAnnouncementDidChange:(SessionView *)sessionView {
    [self.delegate sessionUpdateMetalAllowed];
}

- (id)temporarilyDisableMetal NS_AVAILABLE_MAC(10_11) {
    assert(_useMetal);
    _wrapper.useMetal = NO;
    _textview.suppressDrawing = NO;
    [_view setSuppressLegacyDrawing:NO];
    if (PTYScrollView.shouldDismember) {
        _view.scrollview.alphaValue = 1;
    } else {
        [self updateWrapperAlphaForMetalEnabled:NO];
    }
    [self setMetalViewAlphaValue:0];
    id token = @(_nextMetalDisabledToken++);
    [_metalDisabledTokens addObject:token];
    DLog(@"temporarilyDisableMetal return new token=%@ %@", token, self);
    return token;
}

- (void)drawFrameAndRemoveTemporarilyDisablementOfMetalForToken:(id)token NS_AVAILABLE_MAC(10_11) {
    DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal %@", token);
    if (!_useMetal) {
        DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal returning early because useMetal is off");
        return;
    }
    if ([_metalDisabledTokens containsObject:token]) {
        DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Found token %@", token);
        if (_metalDisabledTokens.count > 1) {
            [_metalDisabledTokens removeObject:token];
            DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: There are still other tokens remaining: %@", _metalDisabledTokens);
            return;
        }
    } else {
        DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Bogus token %@", token);
        return;
    }

    DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal beginning async draw");
    [_view.driver drawAsynchronouslyInView:_view.metalView completion:^(BOOL ok) {
        DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal drawAsynchronouslyInView finished wtih ok=%@", @(ok));
        if (![_metalDisabledTokens containsObject:token]) {
            DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Token %@ is gone, not proceeding.", token);
            return;
        }
        if (!_view.window) {
            DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Returning because the view has no window");
            return;
        }
        if (!_useMetal) {
            DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Returning because useMetal is off");
            return;
        }
        if (!ok) {
            DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Schedule drawFrameAndRemoveTemporarilyDisablementOfMetal to run after a spin of the mainloop");
            if (!_delegate) {
                [self setUseMetal:NO];
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![_metalDisabledTokens containsObject:token]) {
                    DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: [after a spin of the runloop] Token %@ is gone, not proceeding.", token);
                    return;
                }
                [self drawFrameAndRemoveTemporarilyDisablementOfMetalForToken:token];
            });
            return;
        }

        assert([_metalDisabledTokens containsObject:token]);
        [_metalDisabledTokens removeObject:token];
        DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Remove temporarily disablement. Tokens are now %@", _metalDisabledTokens);
        if (_metalDisabledTokens.count == 0 && _useMetal) {
            [self reallyShowMetalViewImmediately];
        }
    }];
}


- (void)sessionViewNeedsMetalFrameUpdate {
    DLog(@"sessionViewNeedsMetalFrameUpdate %@", self);
    if (_metalFrameChangePending) {
        DLog(@"sessionViewNeedsMetalFrameUpdate frame change pending, return");
        return;
    }

    _metalFrameChangePending = YES;
    id token = [self temporarilyDisableMetal];
    [self.textview requestDelegateRedraw];
    dispatch_async(dispatch_get_main_queue(), ^{
        DLog(@"sessionViewNeedsMetalFrameUpdate %@ in dispatch_async", self);
        _metalFrameChangePending = NO;
        [_view reallyUpdateMetalViewFrame];
        DLog(@"sessionViewNeedsMetalFrameUpdate will draw farme and remove disablement");
        [self drawFrameAndRemoveTemporarilyDisablementOfMetalForToken:token];
    });
}

- (void)sessionViewRecreateMetalView {
    if (_metalDeviceChanging) {
        return;
    }
    DLog(@"sessionViewRecreateMetalView metalDeviceChanging<-YES");
    _metalDeviceChanging = YES;
    [self.textview requestDelegateRedraw];
    [_delegate sessionUpdateMetalAllowed];
    dispatch_async(dispatch_get_main_queue(), ^{
        _metalDeviceChanging = NO;
        DLog(@"sessionViewRecreateMetalView metalDeviceChanging<-NO");
        [_delegate sessionUpdateMetalAllowed];
    });
}

- (void)sessionViewUserScrollDidChange:(BOOL)userScroll {
    [self.delegate sessionUpdateMetalAllowed];
    [self updateAutoComposerSeparatorVisibility];
}

- (void)sessionViewDidChangeHoverURLVisible:(BOOL)visible {
    [self.delegate sessionUpdateMetalAllowed];
}

- (iTermVariableScope *)sessionViewScope {
    return self.variablesScope;
}

- (BOOL)sessionViewUseSeparateStatusBarsPerPane {
    if (![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]) {
        return NO;
    }
    if (self.isTmuxClient) {
        return NO;
    }
    return YES;
}

- (void)sessionViewDidChangeEffectiveAppearance {
    [self sync];
    if ([iTermProfilePreferences boolForKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE inProfile:self.profile]) {
        [self loadColorsFromProfile:self.profile];
    }
}

- (BOOL)sessionViewCaresAboutMouseMovement {
    return [_textview wantsMouseMovementEvents];
}

- (NSRect)sessionViewOffscreenCommandLineFrameForView:(NSView *)view {
    return [_textview offscreenCommandLineFrameForView:view];
}

- (void)sessionViewUpdateComposerFrame {
    [[self composerManager] layout];
}
#pragma mark - iTermCoprocessDelegate

- (void)coprocess:(Coprocess *)coprocess didTerminateWithErrorOutput:(NSString *)errors {
    if ([Coprocess shouldIgnoreErrorsFromCommand:coprocess.command]) {
        return;
    }
    NSString *command = [[coprocess.command copy] autorelease];
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:[NSString stringWithFormat:@"Coprocess “%@” terminated with output on stderr.", coprocess.command]
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"_View Errors", @"Ignore Errors from This Command" ]
                                                completion:^(int selection) {
                                                    if (selection == 0) {
                                                        NSString *filename = [[NSWorkspace sharedWorkspace] temporaryFileNameWithPrefix:@"coprocess-stderr." suffix:@".txt"];
                                                        [errors writeToFile:filename atomically:NO encoding:NSUTF8StringEncoding error:nil];
                                                        [[NSWorkspace sharedWorkspace] openFile:filename];
                                                    } else if (selection == 1) {
                                                        [Coprocess setSilentlyIgnoreErrors:YES fromCommand:command];
                                                    }
                                                }];
    [self queueAnnouncement:announcement identifier:[[NSUUID UUID] UUIDString]];
}

#pragma mark - iTermUpdateCadenceController

- (void)updateCadenceControllerUpdateDisplay:(iTermUpdateCadenceController *)controller {
    DLog(@"Cadence controller requests display");
    [self updateDisplayBecause:@"Cadence controller update"];
}

- (iTermUpdateCadenceState)updateCadenceControllerState {
    iTermUpdateCadenceState state;
    state.active = _active;
    state.idle = self.isIdle;
    state.visible = [_delegate sessionBelongsToVisibleTab] && !self.view.window.isMiniaturized;

    if (self.useMetal) {
        if ([iTermPreferences maximizeThroughput] &&
            !_screen.terminalSoftAlternateScreenMode) {
            state.useAdaptiveFrameRate = YES;
        } else {
            state.useAdaptiveFrameRate = NO;
        }
    } else {
        if ([iTermAdvancedSettingsModel disableAdaptiveFrameRateInInteractiveApps] &&
            _screen.terminalSoftAlternateScreenMode) {
            state.useAdaptiveFrameRate = NO;
        } else {
            state.useAdaptiveFrameRate = _useAdaptiveFrameRate;
        }
    }
    state.adaptiveFrameRateThroughputThreshold = _adaptiveFrameRateThroughputThreshold;
    state.slowFrameRate = self.useMetal ? [iTermAdvancedSettingsModel metalSlowFrameRate] : [iTermAdvancedSettingsModel slowFrameRate];
    state.liveResizing = _inLiveResize;
    state.proMotion = [NSProcessInfo it_hasARMProcessor] && [_textview.window.screen it_supportsHighFrameRates];
    state.estimatedThroughput = _estimatedThroughput;
    return state;
}

- (void)cadenceControllerActiveStateDidChange:(BOOL)active {
    [self.delegate sessionUpdateMetalAllowed];
}

- (BOOL)updateCadenceControllerWindowHasSheet {
    return self.view.window.sheets.count > 0;
}

#pragma mark - API

- (void)addContentSubscriber:(id<iTermContentSubscriber>)contentSubscriber {
    if (!_contentSubscribers) {
        _contentSubscribers = [[NSMutableArray alloc] init];
    }
    DLog(@"Add content subscriber %@\n%@", contentSubscriber, [NSThread callStackSymbols]);
    [_contentSubscribers addObject:contentSubscriber];
    [self sync];
}

- (void)removeContentSubscriber:(id<iTermContentSubscriber>)contentSubscriber {
    DLog(@"Remove content subscriber %@\n%@", contentSubscriber, [NSThread callStackSymbols]);
    [_contentSubscribers removeObject:contentSubscriber];
    [self sync];
}

- (NSString *)stringForLine:(const screen_char_t *)screenChars
                     length:(int)length
                  cppsArray:(NSMutableArray<ITMCodePointsPerCell *> *)cppsArray {
    unichar *characters = iTermMalloc(sizeof(unichar) * length * kMaxParts + 1);
    ITMCodePointsPerCell *cpps = [[[ITMCodePointsPerCell alloc] init] autorelease];
    cpps.numCodePoints = 1;
    cpps.repeats = 0;
    int o = 0;
    for (int i = 0; i < length; ++i) {
        int numCodePoints;

        unichar c = screenChars[i].code;
        if (!screenChars[i].complexChar && c >= ITERM2_PRIVATE_BEGIN && c <= ITERM2_PRIVATE_END) {
            numCodePoints = 0;
        } else if (screenChars[i].image) {
            numCodePoints = 0;
        } else {
            const int len = ExpandScreenChar(&screenChars[i], characters + o);
            o += len;
            numCodePoints = len;
        }

        if (numCodePoints != cpps.numCodePoints && cpps.repeats > 0) {
            [cppsArray addObject:cpps];
            cpps = [[[ITMCodePointsPerCell alloc] init] autorelease];
            cpps.repeats = 0;
        }
        cpps.numCodePoints = numCodePoints;
        cpps.repeats = cpps.repeats + 1;
    }
    if (cpps.repeats > 0) {
        [cppsArray addObject:cpps];
    }
    NSString *string = [[[NSString alloc] initWithCharacters:characters length:o] autorelease];
    free(characters);
    return string;
}

- (VT100GridAbsWindowedRange)absoluteWindowedCoordRangeFromLineRange:(ITMLineRange *)lineRange {
    if (lineRange.hasWindowedCoordRange) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(lineRange.windowedCoordRange.coordRange.start.x,
                                                                        lineRange.windowedCoordRange.coordRange.start.y,
                                                                        lineRange.windowedCoordRange.coordRange.end.x,
                                                                        lineRange.windowedCoordRange.coordRange.end.y),
                                             lineRange.windowedCoordRange.columns.location,
                                             lineRange.windowedCoordRange.columns.length);
    }
    int n = 0;
    if (lineRange.hasScreenContentsOnly) {
        n++;
    }
    if (lineRange.hasTrailingLines) {
        n++;
    }
    if (n != 1) {
        return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(-1, -1, -1, -1), -1, -1);
    }

    NSRange range;
    if (lineRange.hasScreenContentsOnly) {
        range.location = [_screen numberOfScrollbackLines] + _screen.totalScrollbackOverflow;
        range.length = _screen.height;
    } else if (lineRange.hasTrailingLines) {
        // Requests are capped at 1M lines to avoid doing too much work.
        int64_t length = MIN(1000000, MIN(lineRange.trailingLines, _screen.numberOfLines));
        range.location = _screen.numberOfLines + _screen.totalScrollbackOverflow - length;
        range.length = length;
    } else {
        range = NSMakeRange(NSNotFound, 0);
    }
    return VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(0, range.location, 0, NSMaxRange(range)), 0, 0);
}

- (ITMGetBufferResponse *)handleGetBufferRequest:(ITMGetBufferRequest *)request {
    ITMGetBufferResponse *response = [[[ITMGetBufferResponse alloc] init] autorelease];

    const VT100GridAbsWindowedRange windowedRange = [self absoluteWindowedCoordRangeFromLineRange:request.lineRange];
    if (windowedRange.coordRange.start.x < 0) {
        response.status = ITMGetBufferResponse_Status_InvalidLineRange;
        return nil;
    }

    const VT100GridWindowedRange range = VT100GridWindowedRangeFromVT100GridAbsWindowedRange(windowedRange, _screen.totalScrollbackOverflow);
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_screen];
    __block int firstIndex = -1;
    __block int lastIndex = -1;
    __block const screen_char_t *line = nil;
    BOOL (^handleEol)(unichar, int, int) = ^BOOL(unichar code, int numPreceedingNulls, int linenumber) {
        ITMLineContents *lineContents = [[[ITMLineContents alloc] init] autorelease];
        lineContents.text = [self stringForLine:line + firstIndex
                                         length:lastIndex - firstIndex
                                      cppsArray:lineContents.codePointsPerCellArray];
        switch (code) {
            case EOL_HARD:
                lineContents.continuation = ITMLineContents_Continuation_ContinuationHardEol;
                break;

            case EOL_SOFT:
            case EOL_DWC:
                lineContents.continuation = ITMLineContents_Continuation_ContinuationSoftEol;
                break;
        }
        [response.contentsArray addObject:lineContents];
        firstIndex = lastIndex = -1;
        line = nil;
        return NO;
    };
    [extractor enumerateCharsInRange:range
                           charBlock:^BOOL(const screen_char_t *currentLine, screen_char_t theChar, iTermExternalAttribute *ea, VT100GridCoord coord) {
                               line = currentLine;
                               if (firstIndex < 0) {
                                   firstIndex = coord.x;
                               }
                               lastIndex = coord.x + 1;
                               line = currentLine;
                               return NO;
                           }
                            eolBlock:^BOOL(unichar code, int numPreceedingNulls, int line) {
                                return handleEol(code, numPreceedingNulls, line);
                            }];
    if (line) {
        handleEol(EOL_SOFT, 0, 0);
    }
    response.cursor = [[[ITMCoord alloc] init] autorelease];
    response.cursor.x = _screen.currentGrid.cursor.x;
    response.cursor.y = _screen.currentGrid.cursor.y + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow;

    response.status = ITMGetBufferResponse_Status_Ok;
    response.windowedCoordRange.coordRange.start.x = windowedRange.coordRange.start.x;
    response.windowedCoordRange.coordRange.start.y = windowedRange.coordRange.start.y;
    response.windowedCoordRange.coordRange.end.x = windowedRange.coordRange.end.x;
    response.windowedCoordRange.coordRange.end.y = windowedRange.coordRange.end.y;
    response.windowedCoordRange.columns.location = windowedRange.columnWindow.location;
    response.windowedCoordRange.columns.length = windowedRange.columnWindow.length;

    return response;
}

- (void)handleListPromptsRequest:(ITMListPromptsRequest *)request completion:(void (^)(ITMListPromptsResponse *))completion {
    ITMListPromptsResponse *response = [[[ITMListPromptsResponse alloc] init] autorelease];
    [_screen enumeratePromptsFrom:request.hasFirstUniqueId ? request.firstUniqueId : nil
                               to:request.hasLastUniqueId ? request.lastUniqueId : nil
                            block:^(id<VT100ScreenMarkReading> mark) {
        [response.uniquePromptIdArray addObject:mark.guid];
    }];
    completion(response);
}

- (void)handleGetPromptRequest:(ITMGetPromptRequest *)request completion:(void (^)(ITMGetPromptResponse *response))completion {
    id<VT100ScreenMarkReading> mark;
    if (request.hasUniquePromptId) {
        mark = [_screen promptMarkWithGUID:request.uniquePromptId];
    } else {
        mark = [_screen lastPromptMark];
    }
    ITMGetPromptResponse *response = [self getPromptResponseForMark:mark];
    completion(response);
}

- (ITMGetPromptResponse *)getPromptResponseForMark:(id<VT100ScreenMarkReading>)mark {
    ITMGetPromptResponse *response = [[[ITMGetPromptResponse alloc] init] autorelease];
    if (!mark) {
        response.status = ITMGetPromptResponse_Status_PromptUnavailable;
        return response;
    }

    if (mark.promptRange.start.x >= 0) {
        response.promptRange = [[[ITMCoordRange alloc] init] autorelease];
        response.promptRange.start.x = mark.promptRange.start.x;
        response.promptRange.start.y = mark.promptRange.start.y;
        response.promptRange.end.x = mark.promptRange.end.x;
        response.promptRange.end.y = mark.promptRange.end.y;
    }
    if (mark.commandRange.start.x >= 0) {
        response.commandRange = [[[ITMCoordRange alloc] init] autorelease];
        response.commandRange.start.x = mark.commandRange.start.x;
        response.commandRange.start.y = mark.commandRange.start.y;
        response.commandRange.end.x = mark.commandRange.end.x;
        response.commandRange.end.y = mark.commandRange.end.y;
    }
    if (mark.outputStart.x >= 0) {
        response.outputRange = [[[ITMCoordRange alloc] init] autorelease];
        response.outputRange.start.x = mark.outputStart.x;
        response.outputRange.start.y = mark.outputStart.y;
        response.outputRange.end.x = _screen.currentGrid.cursor.x;
        response.outputRange.end.y = _screen.currentGrid.cursor.y + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow;
    }

    response.command = mark.command ?: self.currentCommand;
    response.status = ITMGetPromptResponse_Status_Ok;
    response.workingDirectory = [_screen workingDirectoryOnLine:mark.promptRange.end.y] ?: self.lastDirectory;
    if (mark.hasCode) {
        response.promptState = ITMGetPromptResponse_State_Finished;
        response.exitStatus = mark.code;
    } else if (mark.outputStart.x >= 0) {
        response.promptState = ITMGetPromptResponse_State_Running;
    } else {
        response.promptState = ITMGetPromptResponse_State_Editing;
    }
    response.uniquePromptId = mark.guid;
    return response;
}

- (ITMSetProfilePropertyResponse_Status)handleSetProfilePropertyForAssignments:(NSArray<iTermTuple<NSString *, id> *> *)tuples
                                                            scriptHistoryEntry:(iTermScriptHistoryEntry *)scriptHistoryEntry {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (iTermTuple<NSString *, id> *tuple in tuples) {
        NSString *key = tuple.firstObject;
        id value = tuple.secondObject;
        if (![iTermProfilePreferences valueIsLegal:value forKey:key]) {
            XLog(@"Value %@ is not legal for key %@", value, key);
            [scriptHistoryEntry addOutput:[NSString stringWithFormat:@"Value %@ is not legal type for key %@\n", value, key]
                               completion:^{}];
            return ITMSetProfilePropertyResponse_Status_RequestMalformed;
        }
        dict[key] = value;
    }

    [self setSessionSpecificProfileValues:dict];
    return ITMSetProfilePropertyResponse_Status_Ok;
}

- (ITMGetProfilePropertyResponse *)handleGetProfilePropertyForKeys:(NSArray<NSString *> *)keys {
    ITMGetProfilePropertyResponse *response = [[[ITMGetProfilePropertyResponse alloc] init] autorelease];
    if (!keys.count) {
        return [self handleGetProfilePropertyForKeys:[iTermProfilePreferences allKeys]];
    }

    for (NSString *key in keys) {
        id value = [iTermProfilePreferences objectForKey:key inProfile:self.profile];
        if (value) {
            NSString *jsonString = [iTermProfilePreferences jsonEncodedValueForKey:key inProfile:self.profile];
            if (jsonString) {
                ITMProfileProperty *property = [[[ITMProfileProperty alloc] init] autorelease];
                property.key = key;
                property.jsonValue = jsonString;
                [response.propertiesArray addObject:property];
            }
        }
    }
    response.status = ITMGetProfilePropertyResponse_Status_Ok;
    return response;
}

#pragma mark - iTermSessionNameControllerDelegate

- (NSString *)sessionNameControllerUniqueIdentifier {
    iTermTitleComponents components = [iTermProfilePreferences unsignedIntegerForKey:KEY_TITLE_COMPONENTS inProfile:_profile];
    if (components != iTermTitleComponentsCustom) {
        return iTermSessionNameControllerSystemTitleUniqueIdentifier;
    }
    
    iTermTuple<NSString *, NSString *> *tuple = [iTermTuple fromPlistValue:[iTermProfilePreferences stringForKey:KEY_TITLE_FUNC inProfile:_profile]];
    if (tuple.firstObject && tuple.secondObject) {
        return tuple.secondObject;
    } else {
        return nil;
    }
}

- (void)sessionNameControllerNameWillChangeTo:(NSString *)newName {
    [self.variablesScope setValue:newName forVariableNamed:iTermVariableKeySessionName];
}

- (void)sessionNameControllerPresentationNameDidChangeTo:(NSString *)presentationName {
    [_delegate nameOfSession:self didChangeTo:presentationName];
    [self.view setTitle:presentationName];

    // get the session submenu to be rebuilt
    if ([[iTermController sharedInstance] currentTerminal] == [_delegate parentWindow]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNameOfSessionDidChange"
                                                            object:[_delegate parentWindow]
                                                          userInfo:nil];
    }
    [self.variablesScope setValue:presentationName forVariableNamed:iTermVariableKeySessionPresentationName];
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (void)sessionNameControllerDidChangeWindowTitle {
    if ([_delegate sessionBelongsToVisibleTab]) {
        [[_delegate parentWindow] setWindowTitle];
    }
}

- (iTermSessionFormattingDescriptor *)sessionNameControllerFormattingDescriptor {
    iTermSessionFormattingDescriptor *descriptor = [[[iTermSessionFormattingDescriptor alloc] init] autorelease];
    descriptor.isTmuxGateway = self.isTmuxGateway;
    descriptor.tmuxClientName = _tmuxController.clientName;
    descriptor.haveTmuxController = (self.tmuxController != nil);
    descriptor.tmuxWindowName = [_delegate tmuxWindowName];
    return descriptor;
}

- (iTermVariableScope *)sessionNameControllerScope {
    return self.variablesScope;
}

#pragma mark - Variable Change Handlers

- (void)jobPidDidChange {
    // Avoid requesting an update before we know the name because doing so delays updating it when
    // we finally get the name since it's rate-limited.
    if (self.shell.pid > 0 || [[[self variablesScope] valueForVariableName:@"jobName"] length] > 0) {
        [self.processInfoProvider setNeedsUpdate:YES];
    }
    if ([_graphicSource updateImageForProcessID:self.shell.pid enabled:[self shouldShowTabGraphic] processInfoProvider:self.processInfoProvider]) {
        [self.delegate sessionDidChangeGraphic:self shouldShow:self.shouldShowTabGraphic image:self.tabGraphic];
    }
    [self.delegate sessionJobDidChange:self];
}

#pragma mark - iTermEchoProbeDelegate

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeString:(NSString *)string {
    if (self.tmuxMode == TMUX_GATEWAY) {
        return;
    }
    [self writeTaskNoBroadcast:string];
}

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeData:(NSData *)data {
    if (self.tmuxMode == TMUX_GATEWAY) {
        return;
    }
    [self writeLatin1EncodedData:data broadcastAllowed:NO reporting:NO];
}

- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe {
    // Not allowed to use a runloop in a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendPasswordAfterGettingPermission];
    });
}

- (void)sendPasswordAfterGettingPermission {
    BOOL ok = ([iTermWarning showWarningWithTitle:@"Are you really at a password prompt? It looks "
                @"like what you're typing is echoed to the screen."
                                          actions:@[ @"Cancel", @"Enter Password" ]
                                       identifier:nil
                                      silenceable:kiTermWarningTypePersistent
                                           window:self.view.window] == kiTermWarningSelection1);
    if (ok) {
        [_screen sendPasswordInEchoProbe];
    } else {
        [self incrementDisableFocusReporting:-1];
        [_screen resetEchoProbe];
    }
}

- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe {
    [self incrementDisableFocusReporting:-1];
}

- (BOOL)echoProbeShouldSendPassword:(iTermEchoProbe *)echoProbe {
    return YES;
}

- (void)echoProbeDelegateWillChange:(iTermEchoProbe *)echoProbe {
}

#pragma mark - iTermBackgroundDrawingHelperDelegate

- (SessionView *)backgroundDrawingHelperView {
    return _view;
}

- (iTermImageWrapper *)backgroundDrawingHelperImage {
    return [self effectiveBackgroundImage];
}

- (BOOL)backgroundDrawingHelperUseTransparency {
    return _textview.useTransparency;
}

- (CGFloat)backgroundDrawingHelperTransparency {
    return _textview.transparency;
}

- (iTermBackgroundImageMode)backgroundDrawingHelperBackgroundImageMode {
    return [self effectiveBackgroundImageMode];
}

- (NSColor *)backgroundDrawingHelperDefaultBackgroundColor {
    return [self processedBackgroundColor];
}

- (CGFloat)backgroundDrawingHelperBlending {
    return self.effectiveBlend;
}

#pragma mark - iTermStatusBarViewControllerDelegate

- (NSColor *)textColorForStatusBar {
    return [[iTermTheme sharedInstance] statusBarTextColorForEffectiveAppearance:_view.effectiveAppearance
                                                                        colorMap:_screen.colorMap
                                                                        tabStyle:[self.view.window.ptyWindow it_tabStyle]
                                                                   mainAndActive:(self.view.window.isMainWindow && NSApp.isActive)];
}

- (BOOL)statusBarHasDarkBackground {
    if (self.view.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
        NSColor *color = self.view.window.ptyWindow.it_terminalWindowDecorationControlColor;
        return [color isDark];
    }
    // This is called early in the appearance change process and subviews of the contentview aren't
    // up to date yet.
    return self.view.window.contentView.effectiveAppearance.it_isDark;
}

- (BOOL)statusBarRevealComposer {
    [self.composerManager revealMinimal];
    return NO;
}

- (NSColor *)statusBarDefaultTextColor {
    return [self textColorForStatusBar];
}

- (NSColor *)statusBarSeparatorColor {
    if (self.view.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
        return nil;
    }
    NSColor *color = _statusBarViewController.layout.advancedConfiguration.separatorColor;
    if (color) {
        return color;
    }

    const CGFloat alpha = 0.25;
    NSAppearance *appearance = nil;
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            break;
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            break;
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:  // shouldn't happen
            appearance = [NSApp effectiveAppearance];
            break;
    }
    return [[[self textColorForStatusBar] it_colorWithAppearance:appearance] colorWithAlphaComponent:alpha];
}

- (NSColor *)statusBarBackgroundColor {
    return _statusBarViewController.layout.advancedConfiguration.backgroundColor;
}

- (void)updateStatusBarStyle {
    [_statusBarViewController updateColors];
    [self invalidateStatusBar];
}

- (NSFont *)statusBarTerminalFont {
    return _textview.fontTable.asciiFont.font;
}

- (NSColor *)statusBarTerminalBackgroundColor {
    return [self processedBackgroundColor];
}

- (id<ProcessInfoProvider>)statusBarProcessInfoProvider {
    return self.processInfoProvider;
}

- (void)statusBarWriteString:(NSString *)string {
    [self writeTask:string];
}

- (void)statusBarDidUpdate {
    [_view updateFindDriver];
}

- (void)statusBarOpenPreferencesToComponent:(nullable id<iTermStatusBarComponent>)component {
    PreferencePanel *panel;
    NSString *guid;
    if (self.isDivorced && ([_overriddenFields containsObject:KEY_STATUS_BAR_LAYOUT] ||
                            [_overriddenFields containsObject:KEY_SHOW_STATUS_BAR])) {
        panel = [PreferencePanel sessionsInstance];
        guid = _profile[KEY_GUID];
    } else {
        panel = [PreferencePanel sharedInstance];
        guid = _originalProfile[KEY_GUID];
    }
    [panel openToProfileWithGuid:guid
  andEditComponentWithIdentifier:component.statusBarComponentIdentifier
                            tmux:self.isTmuxClient
                           scope:self.variablesScope];
    [panel.window makeKeyAndOrderFront:nil];
}

- (void)statusBarDisable {
    if (self.isDivorced) {
        [self setSessionSpecificProfileValues:@{ KEY_SHOW_STATUS_BAR: @NO }];
    } else {
        [iTermProfilePreferences setBool:NO
                                  forKey:KEY_SHOW_STATUS_BAR
                               inProfile:self.profile
                                   model:[ProfileModel sharedInstance]];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kSessionProfileDidChange
                                                        object:_profile[KEY_GUID]];
}

- (BOOL)statusBarCanDragWindow {
    const BOOL inTitleBar = self.view.statusBarIsInPaneTitleBar;
    if (inTitleBar) {
        return [self.delegate sessionShouldDragWindowByPaneTitleBar:self];
    }
    return YES;
}

- (iTermActivityInfo)statusBarActivityInfo {
    return _activityInfo;
}

- (void)statusBarSetFilter:(NSString *)query {
    PTYSession *synthetic = [self.delegate sessionSyntheticSessionFor:self];
    if (synthetic) {
        [synthetic statusBarSetFilter:query];
        return;
    }
    if (query) {
        [self.delegate session:self setFilter:query];
    } else {
        [self stopFiltering];
    }
}

// Called on the synthetic session.
- (void)stopFiltering {
    [self setFilterProgress:0];
    [self.liveSession removeContentSubscriber:_asyncFilter];
    [_asyncFilter cancel];
    [_asyncFilter autorelease];
    _asyncFilter = nil;
    if ([_statusBarViewController.temporaryRightComponent isKindOfClass:[iTermStatusBarFilterComponent class]]) {
        _statusBarViewController.temporaryRightComponent = nil;
    }
    [self.delegate session:self setFilter:nil];
    [_textview.window makeFirstResponder:_textview];
}

- (ProfileModel *)profileModel {
    if (self.isDivorced && [_overriddenFields containsObject:KEY_STATUS_BAR_LAYOUT]) {
        return [ProfileModel sessionsInstance];
    } else {
        return [ProfileModel sharedInstance];
    }
}

- (void)statusBarSetLayout:(nonnull iTermStatusBarLayout *)layout {
    [iTermProfilePreferences setObject:[layout dictionaryValue]
                                forKey:KEY_STATUS_BAR_LAYOUT
                             inProfile:self.originalProfile
                                 model:[self profileModel]];
}

- (void)statusBarPerformAction:(iTermAction *)action {
    [self applyAction:action];
}

- (void)statusBarEditActions {
    [self.delegate sessionEditActions];
}

- (void)statusBarEditSnippets {
    [self.delegate sessionEditSnippets];
}

- (void)statusBarResignFirstResponder {
    [_textview.window makeFirstResponder:_textview];
}

- (void)statusBarReportScriptingError:(NSError *)error
                        forInvocation:(NSString *)invocation
                               origin:(NSString *)origin {
    [PTYSession reportFunctionCallError:error
                          forInvocation:invocation
                                 origin:origin
                                 window:self.delegate.realParentWindow.window];
}

- (id<iTermTriggersDataSource>)statusBarTriggersDataSource {
    return self;
}

#pragma mark - iTermTriggersDataSource

- (NSInteger)numberOfTriggers {
    return _config.triggerProfileDicts.count;
}

- (NSArray<NSString *> *)triggerNames {
    return [_config.triggerProfileDicts mapWithBlock:^id(NSDictionary *dict) {
        Trigger *trigger = [Trigger triggerFromDict:dict];
        return [NSString stringWithFormat:@"%@ — %@", [[[trigger class] title] stringByRemovingSuffix:@"…"], trigger.regex];
    }];
}

- (NSIndexSet *)enabledTriggerIndexes {
    return [_config.triggerProfileDicts it_indexSetWithObjectsPassingTest:^BOOL(NSDictionary *triggerDict) {
        return ![triggerDict[kTriggerDisabledKey] boolValue];
    }];
}

- (void)addTrigger {
    [self openAddTriggerViewControllerWithText:_textview.selectedText ?: @""];
}

- (void)editTriggers {
    [self openTriggersViewController];
}

- (void)toggleTriggerAtIndex:(NSInteger)index {
    [self toggleTriggerEnabledAtIndex:index];
}

#pragma mark - iTermMetaFrustrationDetectorDelegate

- (void)metaFrustrationDetectorDidDetectFrustrationForLeftOption {
    [self maybeOfferToSetOptionAsEscForLeft:YES];
}

- (void)metaFrustrationDetectorDidDetectFrustrationForRightOption {
    [self maybeOfferToSetOptionAsEscForLeft:NO];
}

- (void)maybeOfferToSetOptionAsEscForLeft:(BOOL)left {
    if (self.isDivorced) {
        // This gets gnarly. Let's be conservative.
        return;
    }
    NSString *neverPromptUserDefaultsKey = @"NoSyncNeverPromptToChangeOption";
    if ([[NSUserDefaults standardUserDefaults] boolForKey:neverPromptUserDefaultsKey]) {
        // User said never to ask.
        return;
    }

    NSString *leftOrRight;
    NSString *profileKey;
    if (left) {
        leftOrRight = @"left";
        profileKey = KEY_OPTION_KEY_SENDS;
    } else {
        leftOrRight = @"right";
        profileKey = KEY_RIGHT_OPTION_KEY_SENDS;
    }

    if ([iTermProfilePreferences integerForKey:profileKey inProfile:self.profile] != OPT_NORMAL) {
        // There's already a non-default setting.
        return;
    }

    NSArray<NSString *> *actions;
    NSInteger thisProfile = 0;
    NSInteger allProfiles = -1;
    if ([[[ProfileModel sharedInstance] bookmarks] count] == 1) {
        actions = @[ @"Yes", @"Stop Asking" ];
    } else {
        actions = @[ @"Change This Profile", @"Change All Profiles", @"Stop Asking" ];
        allProfiles = 1;
    }

    Profile *profileToChange = [[ProfileModel sharedInstance] bookmarkWithGuid:self.profile[KEY_GUID]];
    if (!profileToChange) {
        return;
    }

    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:[NSString stringWithFormat:@"You seem frustrated. Would you like the %@ option key to send esc+keystroke?", leftOrRight]
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:actions
                                                completion:^(int selection) {
                                                    if (selection < 0) {
                                                        // Programmatic dismissal or clicked the x button.
                                                        return;
                                                    }
                                                    if (selection == thisProfile) {
                                                        [iTermProfilePreferences setInt:OPT_ESC forKey:profileKey inProfile:profileToChange model:[ProfileModel sharedInstance]];
                                                    } else if (selection == allProfiles) {
                                                        for (Profile *profile in [[[[ProfileModel sharedInstance] bookmarks] copy] autorelease]) {
                                                            [iTermProfilePreferences setInt:OPT_ESC forKey:profileKey inProfile:profile model:[ProfileModel sharedInstance]];
                                                        }
                                                    } else {
                                                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:neverPromptUserDefaultsKey];
                                                    }
                                                }];
    static NSString *const identifier = @"OfferToChangeOptionKeyToSendESC";
    [self queueAnnouncement:announcement identifier:identifier];
}

#pragma mark - iTermWorkingDirectoryPollerDelegate

- (BOOL)useLocalDirectoryPollerResult {
    if (_workingDirectoryPollerDisabled) {
        DLog(@"Working directory poller disabled");
        return NO;
    }
    if (_shouldExpectCurrentDirUpdates && ![iTermAdvancedSettingsModel disablePotentiallyInsecureEscapeSequences]) {
        DLog(@"Should not poll for working directory: shell integration used");
        return NO;
    }
    if (_screen.terminalSoftAlternateScreenMode) {
        DLog(@"Should not poll for working directory: soft alternate screen mode");
    }
    DLog(@"Should poll for working directory.");
    return YES;
}

- (BOOL)workingDirectoryPollerShouldPoll {
    return YES;
}

- (pid_t)workingDirectoryPollerProcessID {
    return _shell.pid;;
}

- (void)workingDirectoryPollerDidFindWorkingDirectory:(NSString *)pwd invalidated:(BOOL)invalidated {
    DLog(@"workingDirectoryPollerDidFindWorkingDirectory:%@ invalidated:%@ self=%@", pwd, @(invalidated), self);
    if (invalidated && _lastLocalDirectoryWasPushed && _lastLocalDirectory != nil) {
        DLog(@"Ignore local directory poller's invalidated result when we have a pushed last local directory. _lastLocalDirectory=%@ _lastLocalDirectoryWasPushed=%@",
             _lastLocalDirectory, @(_lastLocalDirectoryWasPushed));
        return;
    }
    if (invalidated || ![self useLocalDirectoryPollerResult]) {
        DLog(@"Not creating a mark. invalidated=%@", @(invalidated));
        if (self.lastLocalDirectory != nil && self.lastLocalDirectoryWasPushed) {
            DLog(@"Last local directory (%@) was pushed, not changing it.", self.lastLocalDirectory);
            return;
        }
        DLog(@"Since last local driectory was not pushed, update it.");
        // This is definitely a local directory. It may have been invalidated because we got a push
        // for a remote directory, but it's still useful to know the local directory for the purposes
        // of session restoration.
        self.lastLocalDirectory = pwd;
        self.lastLocalDirectoryWasPushed = NO;

        // Do not call setLastDirectory:remote:pushed: because there's no sense updating the path
        // variable for an invalidated update when we might have a better remote working directory.
        //
        // Update the proxy icon since it only cares about the local directory.
        [_delegate sessionCurrentDirectoryDidChange:self];
        return;
    }

    if (!pwd) {
        DLog(@"nil result. Don't create a mark");
        return;
    }

    // Updates the mark
    DLog(@"Will create a mark");
    const long absLine = _screen.lineNumberOfCursor + _screen.totalScrollbackOverflow;
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState setWorkingDirectory:pwd
                                onAbsLine:absLine
                                   pushed:NO
                                    token:[[mutableState.setWorkingDirectoryOrderEnforcer newToken] autorelease]];
    }];

}

#pragma mark - iTermStandardKeyMapperDelegate

- (void)standardKeyMapperWillMapKey:(iTermStandardKeyMapper *)standardKeyMapper {
    // Don't use terminalEncoding because it may not be initialized yet.
    iTermStandardKeyMapperConfiguration *configuration = [[[iTermStandardKeyMapperConfiguration alloc] init] autorelease];

    configuration.outputFactory = _screen.terminalOutput;
    configuration.encoding = [iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:self.profile];
    configuration.leftOptionKey = self.optionKey;
    configuration.rightOptionKey = self.rightOptionKey;
    configuration.screenlike = self.isTmuxClient;
    standardKeyMapper.configuration = configuration;
}

#pragma mark - iTermTermkeyKeyMapperDelegate

- (void)termkeyKeyMapperWillMapKey:(iTermTermkeyKeyMapper *)termkeyKeyMaper {
    // Don't use terminalEncoding because it may not be initialized yet.
    iTermTermkeyKeyMapperConfiguration configuration = {
        .encoding = [iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:self.profile],
        .leftOptionKey = self.optionKey,
        .rightOptionKey = self.rightOptionKey,
        .applicationCursorMode = _screen.terminalOutput.cursorMode,
        .applicationKeypadMode = _screen.terminalOutput.keypadMode
    };
    termkeyKeyMaper.configuration = configuration;
}

#pragma mark - iTermBadgeLabelDelegate

- (NSFont *)badgeLabelFontOfSize:(CGFloat)pointSize {
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFont *font = [NSFont fontWithName:_badgeFontName size:pointSize];
    if (!font) {
        font = [NSFont fontWithName:@"Helvetica" size:pointSize];
    }
    if ([iTermAdvancedSettingsModel badgeFontIsBold]) {
        font = [fontManager convertFont:font
                            toHaveTrait:NSBoldFontMask];
    }
    return font;
}

- (NSSize)badgeLabelSizeFraction {
    return _badgeLabelSizeFraction;
}

#pragma mark - iTermShortcutNavigationModeHandlerDelegate

- (void (^)(NSEvent *))shortcutNavigationActionForKeyEquivalent:(NSString *)characters {
    return [[_textview contentNavigationShortcuts] objectPassingTest:^BOOL(iTermContentNavigationShortcut *shortcut, NSUInteger index, BOOL *stop) {
        if (shortcut.view.terminating) {
            return NO;
        }
        return [shortcut.keyEquivalent caseInsensitiveCompare:characters] == NSOrderedSame;
    }].action;
}

- (void)shortcutNavigationDidComplete {
    [_textview removeContentNavigationShortcuts];
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.shortcutNavigationMode = NO;
    }];
}

- (void)shortcutNavigationDidBegin {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.shortcutNavigationMode = YES;
    }];
}

#pragma mark - iTermCopyModeHandlerDelegate

- (void)copyModeHandlerDidChangeEnabledState:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY {
    [_textview requestDelegateRedraw];
    const BOOL enabled = handler.enabled;
    if (enabled) {
        [_textview.window makeFirstResponder:_textview];
    } else {
        if (self.haveAutoComposer) {
            [_composerManager makeDropDownComposerFirstResponder];
        }

        if (_textview.selection.live) {
            [_textview.selection endLiveSelection];
        }
        [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            [mutableState scheduleTokenExecution];
        }];
    }
    [_composerManager setTemporarilyHidden:handler.enabled];
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        mutableState.copyMode = enabled;
    }];
}

- (iTermCopyModeState *)copyModeHandlerCreateState:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY {
    iTermCopyModeState *state = [[[iTermCopyModeState alloc] init] autorelease];
    state.coord = VT100GridCoordMake(_screen.cursorX - 1,
                                     _screen.cursorY - 1 + _screen.numberOfScrollbackLines);
    state.numberOfLines = _screen.numberOfLines;
    state.textView = _textview;

    if (_textview.selection.allSubSelections.count == 1) {
        iTermSubSelection *sub = _textview.selection.allSubSelections.firstObject;
        VT100GridAbsCoordRangeTryMakeRelative(sub.absRange.coordRange,
                                              _screen.totalScrollbackOverflow,
                                              ^(VT100GridCoordRange range) {
            [_textview.window makeFirstResponder:_textview];
            state.selecting = YES;
            state.start = range.start;
            state.coord = range.end;
        });
    }
    [_textview scrollLineNumberRangeIntoView:VT100GridRangeMake(state.coord.y, 1)];
    return state;
}

- (void)copyModeHandler:(iTermCopyModeHandler *)handler redrawLine:(int)line NOT_COPY_FAMILY {
    [self.textview setNeedsDisplayOnLine:line];
}

- (void)copyModeHandlerShowFindPanel:(iTermCopyModeHandler *)handler {
    [self showFindPanel];
}

- (void)copyModeHandler:(iTermCopyModeHandler *)handler revealLine:(int)line NOT_COPY_FAMILY {
    [_textview scrollLineNumberRangeIntoView:VT100GridRangeMake(line, 1)];
}

- (void)copyModeHandlerCopySelection:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY {
    [_textview copySelectionAccordingToUserPreferences];
}

#pragma mark - iTermObject

- (iTermBuiltInFunctions *)objectMethodRegistry {
    if (!_methods) {
        _methods = [[iTermBuiltInFunctions alloc] init];
        iTermBuiltInMethod *method;
        method = [[iTermBuiltInMethod alloc] initWithName:@"set_name"
                                            defaultValues:@{}
                                                    types:@{ @"name": [NSString class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(setNameWithCompletion:name:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"run_tmux_command"
                                            defaultValues:@{}
                                                    types:@{ @"command": [NSString class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(sendTmuxCommandWithCompletion:command:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"set_status_bar_component_unread_count"
                                            defaultValues:@{}
                                                    types:@{ @"identifier": [NSString class],
                                                             @"count": [NSNumber class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(setStatusBarComponentUnreadCountWithCompletion:identifier:count:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"stop_coprocess"
                                            defaultValues:@{}
                                                    types:@{}
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(stopCoprocessWithCompletion:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"get_coprocess"
                                            defaultValues:@{}
                                                    types:@{}
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(getCoprocessWithCompletion:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"run_coprocess"
                                            defaultValues:@{}
                                                    types:@{ @"commandLine": [NSString class],
                                                             @"mute": [NSNumber class] }
                                        optionalArguments:[NSSet setWithArray:@[ @"mute" ]]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(runCoprocessWithCompletion:commandLine:mute:)];
        [_methods registerFunction:method namespace:@"iterm2"];

        method = [[iTermBuiltInMethod alloc] initWithName:@"add_annotation"
                                            defaultValues:@{}
                                                    types:@{ @"startX": [NSNumber class],
                                                             @"startY": [NSNumber class],
                                                             @"endX": [NSNumber class],
                                                             @"endY": [NSNumber class],
                                                             @"text": [NSString class] }
                                        optionalArguments:[NSSet set]
                                                  context:iTermVariablesSuggestionContextSession
                                                   target:self
                                                   action:@selector(addAnnotationWithCompletion:startX:startY:endX:endY:text:)];
        [_methods registerFunction:method namespace:@"iterm2"];
    }
    return _methods;
}

- (void)stopCoprocessWithCompletion:(void (^)(id, NSError *))completion {
    if (![self hasCoprocess]) {
        completion(@NO, nil);
        return;
    }
    [self stopCoprocess];
    completion(@YES, nil);
}

- (void)getCoprocessWithCompletion:(void (^)(id, NSError *))completion {
    completion(_shell.coprocess.command, nil);
}

- (void)runCoprocessWithCompletion:(void (^)(id, NSError *))completion
                       commandLine:(NSString *)command
                            mute:(NSNumber *)muteNumber {
    const BOOL mute = muteNumber ? muteNumber.boolValue : NO;
    if (self.hasCoprocess) {
        completion(@NO, nil);
        return;
    }
    [self launchCoprocessWithCommand:command mute:mute];
    completion(@YES, nil);
}

- (void)addAnnotationWithCompletion:(void (^)(id, NSError *))completion
                             startX:(NSNumber *)startXNumber
                             startY:(NSNumber *)startYNumber
                               endX:(NSNumber *)endXNumber
                               endY:(NSNumber *)endYNumber
                               text:(NSString *)text {
    const VT100GridAbsCoordRange range = VT100GridAbsCoordRangeMake(startXNumber.intValue,
                                                                    startYNumber.longLongValue,
                                                                    endXNumber.intValue,
                                                                    endYNumber.longLongValue);
    const long long maxY = _screen.totalScrollbackOverflow + _screen.numberOfLines;
    if (startYNumber.integerValue > endYNumber.integerValue ||
        startYNumber.integerValue < 0 ||
        startYNumber.integerValue > maxY ||
        endYNumber.integerValue < 0 ||
        endYNumber.integerValue > maxY ||
        (startYNumber.integerValue == endYNumber.integerValue && startXNumber.integerValue > endXNumber.integerValue)) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.add-annotation-command"
                                             code:0
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Invalid range" }];
        completion(nil, error);
        return;
    }
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        [mutableState addNoteWithText:text inAbsoluteRange:range];
    }];
    completion(nil, nil);
}

- (void)setStatusBarComponentUnreadCountWithCompletion:(void (^)(id, NSError *))completion
                                            identifier:(NSString *)identifier
                                                 count:(NSNumber *)count {
    [[iTermStatusBarUnreadCountController sharedInstance] setUnreadCountForComponentWithIdentifier:identifier
                                                                                             count:count.integerValue
                                                                                         sessionID:self.guid];
    completion(nil, nil);
}

- (void)sendTmuxCommandWithCompletion:(void (^)(id, NSError *))completion
                              command:(NSString *)command {
    if (self.tmuxMode == TMUX_NONE || _tmuxController == nil) {
        NSError *error = [NSError errorWithDomain:@"com.iterm2.tmux-command"
                                             code:0
                                         userInfo:@{ NSLocalizedDescriptionKey: @"Not a tmux integration session" }];
        completion(nil, error);
    }

    [_tmuxController.gateway sendCommand:command
                          responseTarget:self
                        responseSelector:@selector(sendTmuxCommandMethodDidComplete:completion:)
                          responseObject:completion
                                   flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)sendTmuxCommandMethodDidComplete:(NSString *)result
                              completion:(void (^)(id, NSError *))completion {
    if (result) {
        completion(result, nil);
        return;
    }

    // Tmux responded with an error.
    NSError *error = [NSError errorWithDomain:@"com.iterm2.tmux-command"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"tmux error" }];
    completion(nil, error);
}

- (void)setNameWithCompletion:(void (^)(id, NSError *))completion
                         name:(NSString *)name  {
    [self setSessionSpecificProfileValues:@{ KEY_NAME: name ?: @""}];
    completion(nil, nil);
}

- (iTermVariableScope *)objectScope {
    return self.variablesScope;
}

#pragma mark - iTermSubscribable

- (NSString *)subscribableIdentifier {
    return self.guid;
}

- (ITMNotificationResponse *)handleAPINotificationRequest:(ITMNotificationRequest *)request
                                            connectionKey:(NSString *)connectionKey {
    ITMNotificationResponse *response = [[[ITMNotificationResponse alloc] init] autorelease];
    if (!request.hasSubscribe) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }

    NSMutableDictionary<id, ITMNotificationRequest *> *subscriptions = nil;
    switch (request.notificationType) {
        case ITMNotificationType_NotifyOnPrompt:
            subscriptions = _promptSubscriptions;
            break;
        case ITMNotificationType_NotifyOnKeystroke:
            subscriptions = _keystrokeSubscriptions;
            break;
        case ITMNotificationType_KeystrokeFilter:
            subscriptions = _keyboardFilterSubscriptions;
            break;
        case ITMNotificationType_NotifyOnScreenUpdate:
            subscriptions = _updateSubscriptions;
            break;
        case ITMNotificationType_NotifyOnCustomEscapeSequence:
            subscriptions = _customEscapeSequenceNotifications;
            break;

        case ITMNotificationType_NotifyOnVariableChange:  // Gets special handling before this method is called
        case ITMNotificationType_NotifyOnNewSession:
        case ITMNotificationType_NotifyOnTerminateSession:
        case ITMNotificationType_NotifyOnLayoutChange:
        case ITMNotificationType_NotifyOnFocusChange:
        case ITMNotificationType_NotifyOnServerOriginatedRpc:
        case ITMNotificationType_NotifyOnBroadcastChange:
        case ITMNotificationType_NotifyOnProfileChange:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        case ITMNotificationType_NotifyOnLocationChange:
#pragma clang diagnostic pop
            // We won't get called for this
            assert(NO);
            break;
    }
    if (!subscriptions) {
        response.status = ITMNotificationResponse_Status_RequestMalformed;
        return response;
    }
    if (request.subscribe) {
        if (subscriptions[connectionKey]) {
            response.status = ITMNotificationResponse_Status_AlreadySubscribed;
            return response;
        }
        subscriptions[connectionKey] = request;
    } else {
        if (!subscriptions[connectionKey]) {
            response.status = ITMNotificationResponse_Status_NotSubscribed;
            return response;
        }
        [subscriptions removeObjectForKey:connectionKey];
    }

    response.status = ITMNotificationResponse_Status_Ok;
    return response;
}

#pragma mark - iTermLogging

- (void)loggingHelperStart:(iTermLoggingHelper *)loggingHelper {
    if (loggingHelper.style != iTermLoggingStyleHTML) {
        return;
    }

    [loggingHelper logWithoutTimestamp:[NSData styleSheetWithFontFamily:self.textview.fontTable.asciiFont.font.familyName
                                                               fontSize:self.textview.fontTable.asciiFont.font.pointSize
                                                        backgroundColor:[_screen.colorMap colorForKey:kColorMapBackground]
                                                              textColor:[_screen.colorMap colorForKey:kColorMapForeground]]];
}

- (void)loggingHelperStop:(iTermLoggingHelper *)loggingHelper {
}

- (NSString *)loggingHelperTimestamp:(iTermLoggingHelper *)loggingHelper {
    if (![iTermAdvancedSettingsModel logTimestampsWithPlainText]) {
        return nil;
    }
    switch (loggingHelper.style) {
        case iTermLoggingStyleRaw:
        case iTermLoggingStyleAsciicast:
            return nil;

        case iTermLoggingStylePlainText: {
            static NSDateFormatter *dateFormatter;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                dateFormatter = [[NSDateFormatter alloc] init];
                dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"yyyy-MM-dd hh.mm.ss.SSS"
                                                                           options:0
                                                                            locale:[NSLocale currentLocale]];
            });
            return [[NSString stringWithFormat:@"[%@] ", [dateFormatter stringFromDate:[NSDate date]]] stringByReplacingUnicodeSpacesWithASCIISpace];
        }

        case iTermLoggingStyleHTML: {
            // This is done during encoding.
            return nil;
        }
    }
}


#pragma mark - iTermNaggingControllerDelegate

- (BOOL)naggingControllerCanShowMessageWithIdentifier:(NSString *)identifier {
    return ![self hasAnnouncementWithIdentifier:identifier];
}

- (void)naggingControllerShowMessage:(NSString *)message
                          isQuestion:(BOOL)isQuestion
                           important:(BOOL)important
                          identifier:(NSString *)identifier
                             options:(NSArray<NSString *> *)options
                          completion:(void (^)(int))completion {
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:message
                                                     style:isQuestion ? kiTermAnnouncementViewStyleQuestion : kiTermAnnouncementViewStyleWarning
                                               withActions:options
                                                completion:^(int selection) {
        completion(selection);
    }];
    if (!important) {
        announcement.dismissOnKeyDown = YES;
    }
    [self queueAnnouncement:announcement identifier:identifier];
}

- (void)naggingControllerRepairSavedArrangement:(NSString *)savedArrangementName
                            missingProfileNamed:(NSString *)missingProfileName
                                           guid:(NSString *)guid {
    Profile *similarlyNamedProfile = [[ProfileModel sharedInstance] bookmarkWithName:missingProfileName];
    [[iTermController sharedInstance] repairSavedArrangementNamed:savedArrangementName
                                             replacingMissingGUID:guid
                                                         withGUID:similarlyNamedProfile[KEY_GUID]];
    [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionDidRepairSavedArrangement
                                                        object:guid
                                                      userInfo:@{ @"new profile": similarlyNamedProfile }];
}

- (void)naggingControllerRemoveMessageWithIdentifier:(NSString *)identifier {
    [self dismissAnnouncementWithIdentifier:identifier];
    [self removeAnnouncementWithIdentifier:identifier];
}

- (void)naggingControllerRestart {
    [self replaceTerminatedShellWithNewInstance];
}

- (void)naggingControllerAbortDownload {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        [terminal stopReceivingFile];
    }];
}

- (void)naggingControllerAbortUpload {
    if (!self.upload) {
        return;
    }
    [_pasteHelper abort];
    [self.upload endOfData];
    self.upload = nil;
}

- (void)naggingControllerSetBackgroundImageToFileWithName:(NSString *)filename {
    [self setSessionSpecificProfileValues:@{ KEY_BACKGROUND_IMAGE_LOCATION: filename.length ? filename : [NSNull null] }];
}

- (void)naggingControllerDisableMouseReportingPermanently:(BOOL)permanently {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        if (permanently) {
            if (self.isDivorced) {
                [self setSessionSpecificProfileValues:@{ KEY_XTERM_MOUSE_REPORTING: @NO}];
            } else {
                [iTermProfilePreferences setBool:NO
                                          forKey:KEY_XTERM_MOUSE_REPORTING
                                       inProfile:self.profile
                                           model:[ProfileModel sharedInstance]];
                [[NSNotificationCenter defaultCenter] postNotificationName:kSessionProfileDidChange
                                                                    object:self.profile[KEY_GUID]];
            }
        }
        [terminal setMouseMode:MOUSE_REPORTING_NONE];
    }];
}

- (void)naggingControllerDisableBracketedPasteMode {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                             VT100ScreenMutableState *mutableState,
                                             id<VT100ScreenDelegate> delegate) {
        terminal.bracketedPasteMode = NO;
    }];
}

- (void)naggingControllerCloseSession {
    [_delegate closeSession:self];
}

- (void)naggingControllerRepairInitialWorkingDirectoryOfSessionWithGUID:(NSString *)guid
                                                  inArrangementWithName:(NSString *)arrangementName {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }
    if (!panel.directoryURL.path) {
        return;
    }
    [[iTermController sharedInstance] repairSavedArrangementNamed:arrangementName
                        replaceInitialDirectoryForSessionWithGUID:guid
                                                             with:panel.directoryURL.path];
}

- (void)naggingControllerDisableTriggersInInteractiveApps {
    NSDictionary *update = @{ KEY_ENABLE_TRIGGERS_IN_INTERACTIVE_APPS: @NO };
    if (self.isDivorced) {
        [self setSessionSpecificProfileValues:update];
        [[iTermNotificationController sharedInstance] notify:@"Session Updated"
                                             withDescription:@"Triggers disabled in interactive apps. You can change this in Edit Session > Advanced."];
        return;
    }

    [iTermProfilePreferences setObjectsFromDictionary:update inProfile:self.profile model:[ProfileModel sharedInstance]];
    [[iTermNotificationController sharedInstance] notify:@"Profile Updated"
                                         withDescription:@"Triggers disabled in interactive apps. You can change this in Prefs > Profiles > Advanced."];
}

#pragma mark - iTermComposerManagerDelegate

- (iTermStatusBarViewController *)composerManagerStatusBarViewController:(iTermComposerManager *)composerManager {
    return _statusBarViewController;
}

- (iTermVariableScope *)composerManagerScope:(iTermComposerManager *)composerManager {
    return self.variablesScope;
}

- (NSView *)composerManagerContainerView:(iTermComposerManager *)composerManager {
    return _view;
}

- (void)composerManager:(iTermComposerManager *)composerManager minimalFrameDidChangeTo:(NSRect)newFrame {
    [_textview requestDelegateRedraw];
    DLog(@"Composer frame changed to %@", NSStringFromRect(newFrame));
}

- (NSRect)composerManager:(iTermComposerManager *)composerManager
    frameForDesiredHeight:(CGFloat)desiredHeight
            previousFrame:(NSRect)previousFrame {
    NSRect newFrame = previousFrame;
    newFrame.origin.y = _view.frame.size.height;

    newFrame.origin.y += newFrame.size.height;
    const CGFloat maxWidth = _view.bounds.size.width - newFrame.origin.x * 2;
    const CGFloat vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
    const NSSize paneSize = self.view.frame.size;
    CGFloat y = 0;
    CGFloat width = 0;
    CGFloat height = 0;

    if (composerManager.isAutoComposer) {
        // Place at bottom, but leave excess space below it so it abuts the terminal view.
        width = maxWidth;
        int lineAbove = _screen.currentGrid.cursor.y + 1;
        id<VT100ScreenMarkReading> mark = _screen.lastPromptMark;
        if (mark.promptRange.start.y >= 0) {
            lineAbove = mark.promptRange.start.y - _screen.totalScrollbackOverflow - _screen.numberOfScrollbackLines;
            lineAbove = MAX(1, lineAbove);
        }
        const int actualLinesAboveComposer = MAX(1, _screen.height - lineAbove);
        const CGFloat lineHeight = _textview.lineHeight;
        const int desiredLines = ceil(desiredHeight / lineHeight);
        const int linesOfHeight = MIN(actualLinesAboveComposer, desiredLines);
        const int gridOffsetInRows = _screen.height - linesOfHeight;
        const CGFloat titleBarHeight = (_view.showTitle ? SessionView.titleHeight : 0);
        height = (linesOfHeight + 0.5) * lineHeight;
        const CGFloat gridOffsetInPoints = gridOffsetInRows * lineHeight;
        const CGFloat top = vmargin + titleBarHeight + gridOffsetInPoints;
        y = MAX(0, paneSize.height - top - height);

        DLog(@"width=%@ actualLinesFree=%@ gridOffsetInRows=%@ lineHeight=%@ titleBarHeight=%@ height=%@ gridOffsetInPoints=%@ top=%@ y=%@",
             @(width), @(actualLinesAboveComposer), @(gridOffsetInRows), @(lineHeight), @(titleBarHeight), @(height), @(gridOffsetInPoints), @(top), @(y));
    } else {
        // Place at top. Includes decoration so a minimum width must be enforced.

        y = paneSize.height - desiredHeight;
        width = MAX(217, maxWidth);
        height = desiredHeight;
    }
    newFrame = NSMakeRect(newFrame.origin.x,
                          y,
                          width,
                          height);
    return newFrame;
}

- (void)composerManagerAutoComposerTextDidChange:(iTermComposerManager *)composerManager {
    [self removeSelectedCommandRange];
}

- (void)composerManager:(iTermComposerManager *)composerManager desiredHeightDidChange:(CGFloat)desiredHeight {
    DLog(@"Desired height changed to %@", @(desiredHeight));
    [self sync];
}

- (BOOL)haveAutoComposer {
    return _composerManager.dropDownComposerViewIsVisible && _composerManager.isAutoComposer;
}

- (void)screenWillSynchronize {
}

- (void)screenDidSynchronize {
    [self updateAutoComposerFrame];
    [self updateSearchRange];
}

- (CGFloat)composerManagerLineHeight:(iTermComposerManager *)composerManager {
    return _textview.lineHeight;
}

- (void)composerManagerClear:(iTermComposerManager *)composerManager {
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState clearForComposer];
    }];
}

- (void)composerManagerOpenHistory:(iTermComposerManager *)composerManager
                            prefix:(nonnull NSString *)prefix
                         forSearch:(BOOL)forSearch {
    [[_delegate realParentWindow] openCommandHistoryWithPrefix:prefix
                                           sortChronologically:!forSearch
                                            currentSessionOnly:YES];
}

- (void)composerManagerShowCompletions:(NSArray<NSString *> *)completions {

}

- (void)composerManagerDidRemoveTemporaryStatusBarComponent:(iTermComposerManager *)composerManager {
    [_pasteHelper temporaryRightStatusBarComponentDidBecomeAvailable];
    [_textview.window makeFirstResponder:_textview];
}

- (void)composerManager:(iTermComposerManager *)composerManager enqueueCommand:(NSString *)command {
    if (self.currentCommand != nil && self.currentCommand.length == 0) {
        // At shell prompt
        [self sendCommand:command];
        return;
    }
    // Send when next mark is received.
    [_commandQueue addObject:[command copy]];
}

- (void)composerManager:(iTermComposerManager *)composerManager sendCommand:(NSString *)command {
    [self sendCommand:command];
}

- (BOOL)composerManagerHandleKeyDown:(NSEvent *)event {
    iTermKeystroke *keystroke = [iTermKeystroke withEvent:event];
    iTermKeyBindingAction *action = [iTermKeyMappings actionForKeystroke:keystroke
                                                             keyMappings:self.profile[KEY_KEYBOARD_MAP]];

    if (!action) {
        return NO;
    }
    if (action.sendsText || keystroke.isNavigation) {
        // Prevent natural text editing preset from interfering with composer navigation.
        return NO;
    }
    DLog(@"PTYSession keyDown action=%@", action);
    // A special action was bound to this key combination.
    [self performKeyBindingAction:action event:event];

    DLog(@"Special handler: KEY BINDING ACTION");
    return YES;
}

- (NSResponder *)composerManagerNextResponder {
    return _textview;
}

- (void)composerManager:(iTermComposerManager *)composerManager
        forwardMenuItem:(NSMenuItem *)menuItem {
    [_textview performSelector:menuItem.action withObject:menuItem];
}

- (BOOL)composerManagerShouldForwardCopy:(iTermComposerManager *)composerManager {
    if (![self haveAutoComposer]) {
        return NO;
    }
    return _textview.canCopy;
}

- (id<iTermSyntaxHighlighting>)composerManager:(iTermComposerManager *)composerManager
          syntaxHighlighterForAttributedString:(NSMutableAttributedString *)attributedString {
    return [[[iTermSyntaxHighlighter alloc] init:attributedString
                                        colorMap:_screen.colorMap
                                        fontTable:_textview.fontTable
                                     fileChecker:[self fileChecker]] autorelease];
}

- (void)composerManagerDidBecomeFirstResponder:(iTermComposerManager *)composerManager {
    DLog(@"composerManagerDidBecomeFirstResponder");
}

- (BOOL)composerManagerShouldFetchSuggestions:(iTermComposerManager *)composerManager
                                      forHost:(id<VT100RemoteHostReading>)remoteHost
                               tmuxController:(TmuxController *)tmuxController {
    if (remoteHost.isRemoteHost) {
        // Don't try to complete filenames if not on localhost unless we can ask the conductor.
        if (@available(macOS 11, *)) {
            return [_conductor framing];
        } else {
            return NO;
        }
    }
    if (tmuxController) {
        // I haven't implemented this on tmux because it's probably gonna be slow and knowing the
        // working directory is rare.
        return NO;
    }
    return YES;
}

- (void)composerManager:(iTermComposerManager *)composerManager
       fetchSuggestions:(iTermSuggestionRequest *)request {
    if (request.executable && ![request.prefix containsString:@"/"]) {
        // In the future it would be nice to search $PATH and shell builtins for command suggestions.
        dispatch_async(dispatch_get_main_queue(), ^{
            request.completion(@[]);
        });
        return;
    }
    if (@available(macOS 11, *)) {
        if ([_conductor framing]) {
            [_conductor fetchSuggestions:[request requestWithReducedLimitBy:8]];
            return;
        }
    }
    [[iTermSlowOperationGateway sharedInstance] findCompletionsWithPrefix:request.prefix
                                                            inDirectories:request.directories
                                                                      pwd:request.workingDirectory
                                                                 maxCount:request.limit
                                                               executable:request.executable
                                                               completion:^(NSArray<NSString *> * _Nonnull completions) {
        dispatch_async(dispatch_get_main_queue(), ^{
            request.completion(completions);
        });
    }];
}

- (iTermFileChecker *)fileChecker {
    if (@available(macOS 11, *)) {
        if (_conductor.canCheckFiles) {
            return _conductor.fileChecker;
        }
    }
    if (!_localFileChecker) {
        _localFileChecker = [[iTermLocalFileChecker alloc] init];
        if (self.lastLocalDirectory) {
            _localFileChecker.workingDirectory = self.lastLocalDirectory;
        }
    }
    return _localFileChecker;
}

- (void)sendCommand:(NSString *)command {
    if (_screen.commandRange.start.x < 0) {
        id<VT100RemoteHostReading> host = [self currentHost] ?: [VT100RemoteHost localhost];
        [[iTermShellHistoryController sharedInstance] addCommand:command
                                                          onHost:host
                                                     inDirectory:[_screen workingDirectoryOnLine:_screen.commandRange.start.y]
                                                        withMark:nil];
    }
    __weak __typeof(self) weakSelf = self;
    if ([self haveAutoComposer]) {
        if (_composerManager.haveShellProvidedText) {
            // Send ^U first to erase what's already there.
            // TODO: This may wreak havoc if the shell decides to redraw itself.
            command = [[NSString stringWithLongCharacter:'U' - '@'] stringByAppendingString:command];
        }
        if ([iTermAdvancedSettingsModel smartLoggingWithAutoComposer]) {
            NSString *trimmedCommand = [command stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet newlineCharacterSet]];
            [self logCooked:[trimmedCommand dataUsingEncoding:_screen.terminalEncoding]
                 foreground:(screen_char_t){0}
                 background:(screen_char_t){0} atPrompt:NO];
        }

        const BOOL detectedByTrigger = [_composerManager.prefixUserData[PTYSessionComposerPrefixUserDataKeyDetectedByTrigger] boolValue];
        [_composerManager setPrefix:nil userData:nil];
        [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
            DLog(@"willSendCommand:%@", command);
            const VT100GridAbsCoord start = 
            VT100GridAbsCoordMake(mutableState.currentGrid.cursor.x,
                                  mutableState.currentGrid.cursor.y + mutableState.numberOfScrollbackLines + mutableState.cumulativeScrollbackOverflow);
            [mutableState composerWillSendCommand:command
                                       startingAt:start];
            if (detectedByTrigger) {
                [mutableState didSendCommand];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf reallySendCommand:command];
            });
        }];
        DLog(@"Dismiss composer and request redraw");
        [_composerManager dismissAnimated:NO];
        [_textview requestDelegateRedraw];
        return;
    }
    [self reallySendCommand:command];
}

- (void)reallySendCommand:(NSString *)command {
    DLog(@"reallySendCommand: %@", command);
    [self writeTask:command];
    [_screen userDidPressReturn];
}

- (void)composerManager:(iTermComposerManager *)composerManager
    sendToAdvancedPaste:(NSString *)command {
    [self openAdvancedPasteWithText:command escaping:iTermSendTextEscapingNone];
}

- (void)composerManager:(iTermComposerManager *)composerManager
            sendControl:(NSString *)control {
    [self writeTask:control];
}

- (BOOL)composerManager:(iTermComposerManager *)composerManager wantsKeyEquivalent:(NSEvent *)event {
    const NSEventModifierFlags mask = (NSEventModifierFlagOption |
                                       NSEventModifierFlagCommand |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    const NSEventModifierFlags cmdShift = (NSEventModifierFlagCommand | NSEventModifierFlagShift);
    if ((event.modifierFlags & mask) == cmdShift) {
        // Shortcut for mark navigation.
        if (event.keyCode == kVK_UpArrow) {
            [[self.delegate realParentWindow] previousMark:nil];
            return YES;
        } else if (event.keyCode == kVK_DownArrow) {
            [[self.delegate realParentWindow] nextMark:nil];
            return YES;
        }
    }
    return NO;
}

- (void)composerManager:(iTermComposerManager *)composerManager performFindPanelAction:(id)sender {
    [_textview performFindPanelAction:sender];
}

- (void)composerManagerWillDismissMinimalView:(iTermComposerManager *)composerManager {
    [_textview.window makeFirstResponder:_textview];
    _composerManager.isSeparatorVisible = NO;
}

- (void)composerManagerDidDisplayMinimalView:(iTermComposerManager *)composerManager {
    [self updateAutoComposerSeparatorVisibility];
}

- (void)updateAutoComposerSeparatorVisibility {
    _composerManager.isSeparatorVisible = [self shouldShowAutoComposerSeparator];
    _composerManager.separatorColor = [iTermTextDrawingHelper colorForLineStyleMark:iTermMarkIndicatorTypeSuccess
                                                                    backgroundColor:[_screen.colorMap colorForKey:kColorMapBackground]];
}

- (BOOL)shouldShowAutoComposerSeparator {
    return self.haveAutoComposer;
}

- (void)composerManagerDidDismissMinimalView:(iTermComposerManager *)composerManager {
    _view.composerHeight = 0;
    [_localFileChecker reset];
    if (@available(macOS 11, *)) {
        [_conductor.fileChecker reset];
    }
}

- (NSAppearance *)composerManagerAppearance:(iTermComposerManager *)composerManager {
    NSColor *color = [_screen.colorMap colorForKey:kColorMapBackground];
    if ([color isDark]) {
        return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
    return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
}

- (id<VT100RemoteHostReading>)composerManagerRemoteHost:(iTermComposerManager *)composerManager {
    return [self currentHost];
}

- (NSString * _Nullable)composerManagerWorkingDirectory:(iTermComposerManager *)composerManager {
    return [self.variablesScope path];
}

- (NSString *)composerManagerShell:(iTermComposerManager *)composerManager {
    return [self bestGuessAtUserShell];
}

- (NSString *)composerManagerUName:(iTermComposerManager *)composerManager {
    return [self bestGuessAtUName];
}

- (TmuxController *)composerManagerTmuxController:(iTermComposerManager *)composerManager {
    if (!self.isTmuxClient) {
        return nil;
    }
    return self.tmuxController;
}

- (NSFont *)composerManagerFont:(iTermComposerManager *)composerManager {
    return self.textview.fontTable.asciiFont.font;
}

- (NSColor *)composerManagerTextColor:(iTermComposerManager *)composerManager {
    return [self.textview.colorMap colorForKey:kColorMapForeground];
}

- (NSColor *)composerManagerCursorColor:(iTermComposerManager *)composerManager {
    return [self.textview.colorMap colorForKey:kColorMapCursor];
}

#pragma mark - iTermIntervalTreeObserver

- (void)intervalTreeDidReset {
    [iTermGCD assertMainQueueSafe];
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    if (![iTermAdvancedSettingsModel showMarksInScrollbar]) {
        return;
    }
    [self initializeMarksMinimap];
}

- (void)initializeMarksMinimap {
    [_view.marksMinimap removeAllObjects];
    const NSInteger count = (NSInteger)iTermIntervalTreeObjectTypeUnknown;
    NSMutableDictionary<NSNumber *, NSMutableIndexSet *> *sets = [NSMutableDictionary dictionary];
    [_screen enumerateObservableMarks:^(iTermIntervalTreeObjectType type, NSInteger line) {
        NSMutableIndexSet *set = sets[@(type)];
        if (!set) {
            set = [NSMutableIndexSet indexSet];
            sets[@(type)] = set;
        }
        [set addIndex:line];
    }];
    for (NSInteger i = 0; i < count; i++) {
        [_view.marksMinimap setLines:sets[@(i)] ?: [NSMutableIndexSet indexSet]
                             forType:i];
    }
}

- (BOOL)minimapsTrackObjectsOfType:(iTermIntervalTreeObjectType)type {
    switch (type) {
        case iTermIntervalTreeObjectTypeSuccessMark:
        case iTermIntervalTreeObjectTypeOtherMark:
        case iTermIntervalTreeObjectTypeErrorMark:
        case iTermIntervalTreeObjectTypeManualMark:
        case iTermIntervalTreeObjectTypeAnnotation:
        case iTermIntervalTreeObjectTypeUnknown:
            return YES;
        case iTermIntervalTreeObjectTypePorthole:
            return NO;
    }
}
- (void)intervalTreeDidAddObjectOfType:(iTermIntervalTreeObjectType)type
                                onLine:(NSInteger)line {
    [self addMarkToMinimapOfType:type onLine:line];
}

- (void)addMarkToMinimapOfType:(iTermIntervalTreeObjectType)type
                                onLine:(NSInteger)line {
    DLog(@"Add at %@", @(line));
    [iTermGCD assertMainQueueSafe];
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    if (![iTermAdvancedSettingsModel showMarksInScrollbar]) {
        return;
    }
    if ([self minimapsTrackObjectsOfType:type]) {
        [_view.marksMinimap addObjectOfType:type onLine:line];
    }
}

- (void)intervalTreeDidHideObject:(id<IntervalTreeImmutableObject>)object
                           ofType:(iTermIntervalTreeObjectType)type
                           onLine:(NSInteger)line {
    DLog(@"Hide %@", object);
    PortholeMark *portholeMark = [PortholeMark castFrom:object];
    if (portholeMark) {
        id<Porthole> porthole = [[PortholeRegistry instance] objectForKeyedSubscript:portholeMark.uniqueIdentifier];
        if (porthole) {
            [_textview hidePorthole:porthole];
        }
    }
    [self removeMarkFromMinimapOfType:type onLine:line];
}

- (void)intervalTreeDidUnhideObject:(id<IntervalTreeImmutableObject>)object
                             ofType:(iTermIntervalTreeObjectType)type
                             onLine:(NSInteger)line {
    DLog(@"Unhide %@", object);
    PortholeMark *portholeMark = [PortholeMark castFrom:object];
    if (portholeMark) {
        id<Porthole> porthole = [[PortholeRegistry instance] objectForKeyedSubscript:portholeMark.uniqueIdentifier];
        if (porthole) {
            [_textview unhidePorthole:porthole];
        }
    }
    [self addMarkToMinimapOfType:type onLine:line];
}

- (void)intervalTreeDidRemoveObjectOfType:(iTermIntervalTreeObjectType)type
                                   onLine:(NSInteger)line {
    DLog(@"Remove at %@", @(line));
    if (type == iTermIntervalTreeObjectTypePorthole) {
        [_textview setNeedsPrunePortholes:YES];
    }
    [self removeMarkFromMinimapOfType:type onLine:line];
}

- (void)removeMarkFromMinimapOfType:(iTermIntervalTreeObjectType)type
                             onLine:(NSInteger)line {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    if (![iTermAdvancedSettingsModel showMarksInScrollbar]) {
        return;
    }
    if ([self minimapsTrackObjectsOfType:type]) {
        [_view.marksMinimap removeObjectOfType:type fromLine:line];
    }
}

- (void)intervalTreeVisibleRangeDidChange {
     [iTermGCD assertMainQueueSafe];
    [self updateMarksMinimapRangeOfVisibleLines];
}

- (void)intervalTreeDidMoveObjects:(NSArray<id<IntervalTreeImmutableObject>> *)objects {
    [self.textview updatePortholeFrames];
}

- (void)updateMarksMinimapRangeOfVisibleLines {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    [_view.marksMinimap setFirstVisibleLine:_screen.totalScrollbackOverflow
                       numberOfVisibleLines:_screen.numberOfLines];
}

#pragma mark - iTermTmuxControllerSession

- (void)tmuxControllerSessionSetTTL:(NSTimeInterval)ttl redzone:(BOOL)redzone {
    if (_tmuxPaused) {
        return;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyTmuxWarnBeforePausing]) {
        return;
    }
    if (_tmuxTTLHasThresholds) {
        if (ttl > _tmuxTTLLowerThreshold && ttl < _tmuxTTLUpperThreshold) {
            return;
        }
        if (ttl <= _tmuxTTLLowerThreshold) {
            _tmuxTTLLowerThreshold = ttl - 1;
            _tmuxTTLUpperThreshold = ttl + 1.5;
        } else {
            _tmuxTTLLowerThreshold = ttl - 1.5;
            _tmuxTTLUpperThreshold = ttl + 1;
        }
    } else {
        _tmuxTTLLowerThreshold = ttl - 1;
        _tmuxTTLUpperThreshold = ttl + 1;
        _tmuxTTLHasThresholds = YES;
    }

    NSTimeInterval rounded = round(ttl);
    NSInteger safeTTL = 0;
    if (rounded > NSIntegerMax || rounded != rounded) {
        safeTTL = NSIntegerMax;
    } else {
        safeTTL = MAX(1, rounded);
    }

    if (!redzone) {
        [self dismissAnnouncementWithIdentifier:PTYSessionAnnouncementIdentifierTmuxPaused];
        return;
    }
    NSString *title = [NSString stringWithFormat:@"This session will pause in about %@ second%@ because it is buffering too much data.", @(safeTTL), safeTTL == 1 ? @"" : @"s"];
    iTermAnnouncementViewController *announcement = [self announcementWithIdentifier:PTYSessionAnnouncementIdentifierTmuxPaused];
    if (announcement) {
        announcement.title = title;
        [announcement.view setNeedsDisplay:YES];
        [_view updateAnnouncementFrame];
        return;
    }
    announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"_Pause Settings" ]
                                                completion:^(int selection) {
        switch (selection) {
            case 0:
                [[PreferencePanel sharedInstance] openToPreferenceWithKey:kPreferenceKeyTmuxPauseModeAgeLimit];
                break;
        }
    }];
    announcement.dismissOnKeyDown = YES;
    [self queueAnnouncement:announcement identifier:PTYSessionAnnouncementIdentifierTmuxPaused];
}

#pragma mark - iTermUniquelyIdentifiable

- (NSString *)stringUniqueIdentifier {
    return self.guid;
}

#pragma mark - iTermModifyOtherKeysMapperDelegate

- (NSStringEncoding)modifiyOtherKeysDelegateEncoding:(iTermModifyOtherKeysMapper *)sender {
    DLog(@"encoding=%@", @(_screen.terminalEncoding));
    return _screen.terminalEncoding;
}

- (void)modifyOtherKeys:(iTermModifyOtherKeysMapper *)sender
getOptionKeyBehaviorLeft:(iTermOptionKeyBehavior *)left
                  right:(iTermOptionKeyBehavior *)right {
    *left = self.optionKey;
    *right = self.rightOptionKey;
    DLog(@"left=%@ right=%@", @(*left), @(*right));
}

- (VT100Output *)modifyOtherKeysOutputFactory:(iTermModifyOtherKeysMapper *)sender {
    return _screen.terminalOutput;
}

- (BOOL)modifyOtherKeysTerminalIsScreenlike:(iTermModifyOtherKeysMapper *)sender {
    DLog(@"screenlike=%@", @(self.isTmuxClient));
    return self.isTmuxClient;
}

#pragma mark - iTermLegacyViewDelegate

- (void)legacyView:(iTermLegacyView *)legacyView drawRect:(NSRect)dirtyRect {
    [_textview drawRect:dirtyRect inView:legacyView];
}

#pragma mark - TriggerDelegate

- (void)triggerChanged:(TriggerController *)triggerController newValue:(NSArray *)value {
    [[triggerController.window undoManager] registerUndoWithTarget:self
                                                          selector:@selector(setTriggersValue:)
                                                            object:self.profile[KEY_TRIGGERS]];
    [[triggerController.window undoManager] setActionName:@"Edit Triggers"];
    [self setSessionSpecificProfileValues:@{ KEY_TRIGGERS: value }];
    triggerController.guid = self.profile[KEY_GUID];
}

- (void)setTriggersValue:(NSArray *)value {
    [self setSessionSpecificProfileValues:@{ KEY_TRIGGERS: value }];
    _triggerWindowController.guid = self.profile[KEY_GUID];
    [_triggerWindowController profileDidChange];
}

- (void)triggerSetUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    [self setSessionSpecificProfileValues:@{ KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: @(useInterpolatedStrings) }];
    _triggerWindowController.guid = self.profile[KEY_GUID];
}

- (void)triggersCloseSheet {
    [self closeTriggerWindowController];
}

- (void)triggersCopyToProfile {
    [ProfileModel updateSharedProfileWithGUID:self.profile[KEY_ORIGINAL_GUID]
                                    newValues:@{ KEY_TRIGGERS: self.profile[KEY_TRIGGERS] ?: @[],
                                                 KEY_TRIGGERS_USE_INTERPOLATED_STRINGS: self.profile[KEY_TRIGGERS_USE_INTERPOLATED_STRINGS] ?: @NO }];
}

#pragma mark - iTermFilterDestination

- (void)filterDestinationAppendCharacters:(const screen_char_t *)line
                                    count:(int)count
                   externalAttributeIndex:(iTermExternalAttributeIndex *)externalAttributeIndex
                             continuation:(screen_char_t)continuation {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState appendScreenChars:line
                                 length:count
                 externalAttributeIndex:externalAttributeIndex
                           continuation:continuation];
    }];
}

- (void)filterDestinationRemoveLastLine {
    [_screen performBlockWithJoinedThreads:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState removeLastLine];
    }];
}

#pragma mark - iTermImmutableColorMapDelegate

- (void)immutableColorMap:(id<iTermColorMapReading>)colorMap didChangeColorForKey:(iTermColorMapKey)theKey from:(NSColor *)before to:(NSColor *)after {
    [_textview immutableColorMap:colorMap didChangeColorForKey:theKey from:before to:after];
    [self setNeedsComposerColorUpdate:YES];
}

- (void)immutableColorMap:(id<iTermColorMapReading>)colorMap dimmingAmountDidChangeTo:(double)dimmingAmount {
    [_textview immutableColorMap:colorMap dimmingAmountDidChangeTo:dimmingAmount];
    [self setNeedsComposerColorUpdate:YES];

}
- (void)immutableColorMap:(id<iTermColorMapReading>)colorMap mutingAmountDidChangeTo:(double)mutingAmount {
    [_textview immutableColorMap:colorMap mutingAmountDidChangeTo:mutingAmount];
    [self setNeedsComposerColorUpdate:YES];
}

- (void)setNeedsComposerColorUpdate:(BOOL)needed {
    if (_needsComposerColorUpdate && needed) {
        return;
    }
    _needsComposerColorUpdate = needed;
    if (needed) {
        __weak __typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateComposerColors];
        });
    }
}

- (void)updateComposerColors {
    if (!_textview) {
        return;
    }
    [self setNeedsComposerColorUpdate:NO];
    if (![self haveAutoComposer]) {
        return;
    }
    NSDictionary *userData = [NSDictionary castFrom:[_composerManager prefixUserData]];
    if (!userData) {
        return;
    }
    NSArray<ScreenCharArray *> *promptText = [NSArray castFrom:userData[PTYSessionComposerPrefixUserDataKeyPrompt]];
    if (!promptText) {
        return;
    }
    NSMutableAttributedString *prompt = [self kernedAttributedStringForScreenChars:promptText
                                                       elideDefaultBackgroundColor:YES];
    [_composerManager setPrefix:prompt userData:[_composerManager prefixUserData]];
}

// This can be completely async
- (BOOL)toolbeltIsVisibleWithCapturedOutput {
    if (!self.delegate.realParentWindow.shouldShowToolbelt) {
        return NO;
    }
    return [iTermToolbeltView shouldShowTool:kCapturedOutputToolName];
}

- (void)showCapturedOutputTool {
    if (!self.delegate.realParentWindow.shouldShowToolbelt) {
        [self.delegate.realParentWindow toggleToolbeltVisibility:nil];
    }
    if (![iTermToolbeltView shouldShowTool:kCapturedOutputToolName]) {
        [iTermToolbeltView toggleShouldShowTool:kCapturedOutputToolName];
    }
}

- (void)performActionForCapturedOutput:(CapturedOutput *)capturedOutput {
    __weak __typeof(self) weakSelf = self;
    [capturedOutput.promisedCommand onQueue:dispatch_get_main_queue() then:^(NSString * _Nonnull command) {
        [weakSelf reallyPerformActionForCapturedOutput:capturedOutput command:command];
    }];
}

- (void)reallyPerformActionForCapturedOutput:(CapturedOutput *)capturedOutput
                                     command:(NSString *)command {
    [self launchCoprocessWithCommand:command
                          identifier:nil
                              silent:NO
                        triggerTitle:@"Captured Output trigger"];
    [self takeFocus];
}

#pragma mark - iTermTriggerSideEffectExecutor

- (void)triggerSideEffectShowAlertWithMessage:(NSString *)message
                                    rateLimit:(iTermRateLimitedUpdate *)rateLimit
                                      disable:(void (^)(void))disable {
    [iTermGCD assertMainQueueSafe];
    __weak __typeof(self) weakSelf = self;
    // Dispatch because it's not safe to start a runloop in a side-effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf reallyShowTriggerAlertWithMessage:message
                                          rateLimit:rateLimit
                                            disable:disable];
    });
}

- (void)reallyShowTriggerAlertWithMessage:(NSString *)message
                                rateLimit:(iTermRateLimitedUpdate *)rateLimit
                                  disable:(void (^)(void))disable {
    __weak __typeof(self) weakSelf = self;
    [rateLimit performRateLimitedBlock:^{
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = message ?: @"";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Show Session"];
        [alert addButtonWithTitle:@"Disable This Alert"];
        switch ([alert runModal]) {
            case NSAlertFirstButtonReturn:
                break;

            case NSAlertSecondButtonReturn: {
                [weakSelf reveal];
                break;
            }

            case NSAlertThirdButtonReturn:
                disable();
                break;

            default:
                break;
        }
    }];
}

- (void)triggerSideEffectShowCapturedOutputTool {
    [iTermGCD assertMainQueueSafe];
    [self showCapturedOutputTool];
}

- (void)triggerSideEffectShowCapturedOutputToolNotVisibleAnnouncementIfNeeded {
    [iTermGCD assertMainQueueSafe];
    if ([self toolbeltIsVisibleWithCapturedOutput]) {
        return;
    }

    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputToolNotVisibleWarning]) {
        return;
    }

    if ([self hasAnnouncementWithIdentifier:kSuppressCaptureOutputToolNotVisibleWarning]) {
        return;
    }
    NSString *theTitle = @"A Capture Output trigger fired, but the Captured Output tool is not visible.";
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case -2:
                break;

            case 0:
                [self showCapturedOutputTool];
                break;

            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputToolNotVisibleWarning];
                break;
        }
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:theTitle
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ @"Show It", @"Silence Warning" ]
                                                    completion:completion];
    announcement.dismissOnKeyDown = YES;
    [self queueAnnouncement:announcement
                 identifier:kSuppressCaptureOutputToolNotVisibleWarning];
}

- (void)triggerSideEffectShowShellIntegrationRequiredAnnouncement {
    [iTermGCD assertMainQueueSafe];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputRequiresShellIntegrationWarning]) {
        return;
    }
    NSString *theTitle = @"A Capture Output trigger fired, but Shell Integration is not installed.";
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case -2:
                break;

            case 0:
                [self tryToRunShellIntegrationInstallerWithPromptCheck:NO];
                break;

            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputRequiresShellIntegrationWarning];
                break;
        }
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:theTitle
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ @"Install", @"Silence Warning" ]
                                                    completion:completion];
    [self queueAnnouncement:announcement
                 identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncementIdentifier];
}

- (void)triggerSideEffectDidCaptureOutput {
    [iTermGCD assertMainQueueSafe];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionCapturedOutputDidChange
                                                        object:nil];

}

- (void)triggerSideEffectLaunchCoprocessWithCommand:(NSString * _Nonnull)command
                                         identifier:(NSString * _Nullable)identifier
                                             silent:(BOOL)silent
                                       triggerTitle:(NSString * _Nonnull)triggerName {
    [iTermGCD assertMainQueueSafe];
    [self launchCoprocessWithCommand:command identifier:identifier silent:silent triggerTitle:triggerName];
}

- (void)launchCoprocessWithCommand:(NSString * _Nonnull)command
                        identifier:(NSString * _Nullable)identifier
                            silent:(BOOL)silent
                      triggerTitle:(NSString * _Nonnull)triggerName {
    if (self.hasCoprocess) {
        if (identifier && [[NSUserDefaults standardUserDefaults] boolForKey:identifier]) {
            return;
        }
        NSString *message = [NSString stringWithFormat:@"%@: Can't run two coprocesses at once.", triggerName];
        NSArray<NSString *> *actions = identifier ? @[ @"Silence Warning" ] : @[];
        iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:message
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:actions
                                                    completion:^(int selection) {
            if (!identifier) {
                return;
            }
            switch (selection) {
                case 0:
                    [[NSUserDefaults standardUserDefaults] setBool:YES
                                                            forKey:identifier];
                    break;
            }
        }];
        [self queueAnnouncement:announcement
                     identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncementIdentifier];
    } else if (command) {
        if (silent) {
            [self launchSilentCoprocessWithCommand:command];
        } else {
            [self launchCoprocessWithCommand:command];
        }
    }
}

- (void)triggerSideEffectPostUserNotificationWithMessage:(NSString * _Nonnull)message {
    [iTermGCD assertMainQueueSafe];
    iTermNotificationController *notificationController = [iTermNotificationController sharedInstance];
    [notificationController notify:message
                   withDescription:[NSString stringWithFormat:@"A trigger fired in session \"%@\" in tab #%d.",
                                    [[self name] removingHTMLFromTabTitleIfNeeded],
                                    self.delegate.tabNumber]
                       windowIndex:[self screenWindowIndex]
                          tabIndex:[self screenTabIndex]
                         viewIndex:[self screenViewIndex]];
}

// Scroll so that `absLine` is the last visible onscreen.
- (void)triggerSideEffectStopScrollingAtLine:(long long)absLine {
    [iTermGCD assertMainQueueSafe];
    const long long line = absLine - _screen.totalScrollbackOverflow;
    if (line < 0) {
        return;
    }
    const int height = MAX(1, _screen.height);
    const int top = MAX(0, line - height + 1);
    if (_screen.numberOfLines < line) {
        return;
    }
    [_textview scrollLineNumberRangeIntoView:VT100GridRangeMake(top, height)];
    [[self.view.scrollview ptyVerticalScroller] setUserScroll:YES];
}

- (void)triggerSideEffectOpenPasswordManagerToAccountName:(NSString * _Nullable)accountName {
    [iTermGCD assertMainQueueSafe];
    // Dispatch because you can't have a runloop in a side-effect and the password manager is a bunch of modal UI - why take chances?
    dispatch_async(dispatch_get_main_queue(), ^{
        iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
        [itad openPasswordManagerToAccountName:accountName
                                         inSession:self];
    });
}

- (void)triggerSideEffectRunBackgroundCommand:(NSString *)command pool:(iTermBackgroundCommandRunnerPool *)pool {
    [iTermGCD assertMainQueueSafe];
    iTermBackgroundCommandRunner *runner = [pool requestBackgroundCommandRunnerWithTerminationBlock:nil];
    runner.command = command;
    runner.title = @"Run Command Trigger";
    runner.notificationTitle = @"Run Command Trigger Failed";
    runner.shell = self.userShell;
    [runner run];
}

- (void)triggerWriteTextWithoutBroadcasting:(NSString * _Nonnull)text {
    [self writeTaskNoBroadcast:text];
}

- (iTermVariableScope *)triggerSideEffectVariableScope {
    [iTermGCD assertMainQueueSafe];
    return self.variablesScope;
}

- (void)triggerSideEffectSetTitle:(NSString * _Nonnull)newName {
    [iTermGCD assertMainQueueSafe];
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionTriggerName: newName,
                                                    iTermVariableKeySessionAutoNameFormat: newName }];
    if (newName.length > 0) {
        [self enableSessionNameTitleComponentIfPossible];
    }
}

- (void)triggerSideEffectInvokeFunctionCall:(NSString * _Nonnull)invocation
                              withVariables:(NSDictionary * _Nonnull)temporaryVariables
                                   captures:(NSArray<NSString *> * _Nonnull)captureStringArray
                                    trigger:(Trigger * _Nonnull)trigger {
    [iTermGCD assertMainQueueSafe];
    iTermVariableScope *scope =
    [self.variablesScope variableScopeByAddingBackreferences:captureStringArray
                                                       owner:trigger];
    [scope setValuesFromDictionary:temporaryVariables];
    [self invokeFunctionCall:invocation scope:scope origin:@"Trigger"];
}

- (void)triggerSideEffectSetValue:(id _Nullable)value
                 forVariableNamed:(NSString * _Nonnull)name {
    [iTermGCD assertMainQueueSafe];
    [self.genericScope setValue:value forVariableNamed:name];
}

- (void)triggerSideEffectCurrentDirectoryDidChange:(NSString *)newPath {
    [iTermGCD assertMainQueueSafe];
    [self didUpdateCurrentDirectory:newPath];
}

#pragma mark - iTermPasteboardReporterDelegate

- (void)pasteboardReporter:(iTermPasteboardReporter *)sender reportPasteboard:(NSString *)pasteboard {
    NSData *data = [_screen.terminalOutput reportPasteboard:pasteboard
                                                   contents:[NSString stringFromPasteboard]];
    [self screenSendReportData:data];
    [_view showUnobtrusiveMessage:[NSString stringWithFormat:@"Clipboard contents reported"]
                         duration:3];
}

- (void)pasteboardReporterRequestPermission:(iTermPasteboardReporter *)sender
                                 completion:(void (^)(BOOL, BOOL))completion {
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:@"Share clipboard contents with app in terminal?"
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"Just Once", @"Always", @"Never" ]
                                                completion:^(int selection) {
        switch (selection) {
            case 0:
                completion(YES, NO);
                break;

            case 1:
                completion(YES, YES);
                break;

            case 2:
                // Never
                completion(NO, YES);
                break;

            default:
                // Cancel
                completion(NO, NO);
                break;
        }
    }];
    [self queueAnnouncement:announcement identifier:[[NSUUID UUID] UUIDString]];
}

#pragma mark - iTermConductorDelegate

- (void)conductorWriteString:(NSString *)string {
    DLog(@"Conductor write: %@", string);
    [self writeTaskNoBroadcast:string];
}

- (void)conductorSendInitialText {
    [self sendInitialText];
    if (_pendingConductor) {
        void (^pendingComposer)(PTYSession *) = [[_pendingConductor retain] autorelease];
        [_pendingConductor autorelease];
        _pendingConductor = nil;
        pendingComposer(self);
    }
}

- (void)conductorWillDie {
    DLog(@"conductorWillDie");
    iTermPublisher<NSNumber *> *replacement = _conductor.parent.cpuUtilizationPublisher;
    if (!replacement) {
        replacement = [iTermLocalCPUUtilizationPublisher sharedInstance];
    }
    [[iTermCPUUtilization instanceForSessionID:_guid] setPublisher:replacement];
}

- (void)conductorDidUnhook {
    [self conductorWillDie];
}

- (void)conductorAbortWithReason:(NSString *)reason {
    XLog(@"conductor aborted: %@", reason);
    [self conductorWillDie];

    NSString *location = _conductor.parent.sshIdentity.compactDescription;
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState appendStringAtCursor:@"An error occurred while setting up the SSH environment:"];
        [mutableState appendCarriageReturnLineFeed];
        [mutableState appendStringAtCursor:reason];
        [mutableState appendCarriageReturnLineFeed];
        NSString *message = [mutableState sshEndBannerTerminatingCount:1 newLocation:location];
        [mutableState appendBannerMessage:message];
    }];
    [self unhookSSHConductor];
}

- (void)conductorQuit {
    DLog(@"conductorQuit");
    [self conductorWillDie];
    NSString *identity = _conductor.sshIdentity.description;
    [_screen mutateAsynchronously:^(VT100Terminal *terminal, VT100ScreenMutableState *mutableState, id<VT100ScreenDelegate> delegate) {
        [mutableState appendBannerMessage:[NSString stringWithFormat:@"Disconnected from %@", identity]];
    }];
    [self unhookSSHConductor];
    [_sshWriteQueue setLength:0];
}

- (void)conductorStopQueueingInput {
    _connectingSSH = NO;
    [_conductor sendKeys:_queuedConnectingSSH];
}

- (void)conductorStateDidChange {
    DLog(@"conductorDidExfiltrateState");
    [self updateVariablesFromConductor];
}

- (void)updateVariablesFromConductor {
    if (!_conductor) {
        self.variablesScope.homeDirectory = NSHomeDirectory();
        self.variablesScope.sshIntegrationLevel = 0;
        self.variablesScope.shell = [self bestGuessAtUserShell];
        self.variablesScope.uname = [self bestGuessAtUName];
        return;
    }
    const NSInteger level = _conductor.framing ? 2 : 1;
    self.variablesScope.sshIntegrationLevel = level;
    switch (level) {
        case 0: {
            const BOOL onLocalhost = (self.currentHost == nil || self.currentHost.isLocalhost);
            if (onLocalhost) {
                self.variablesScope.homeDirectory = NSHomeDirectory();
                break;
            }
            // SSHed without integration
            self.variablesScope.homeDirectory = nil;
            self.variablesScope.shell = nil;
            self.variablesScope.uname = nil;
            break;
        }
        case 1:
            // Definitely ssh'ed, but no way to get this info.
            self.variablesScope.homeDirectory = nil;
            self.variablesScope.shell = nil;
            self.variablesScope.uname = nil;
            break;
        case 2:
            self.variablesScope.homeDirectory = _conductor.homeDirectory;
            self.variablesScope.shell = _conductor.shell;
            self.variablesScope.uname = _conductor.uname;
            break;
    }
}

@end

@implementation PTYSession(AppSwitching)

- (void)appSwitchingPreventionDetectorDidDetectFailure {
    [_naggingController openCommandDidFailWithSecureInputEnabled];
}

@end
