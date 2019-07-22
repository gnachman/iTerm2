#import "PTYSession.h"
#import "PTYSession+ARC.h"

#import "Coprocess.h"
#import "CVector.h"
#import "FakeWindow.h"
#import "FileTransferManager.h"
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermAPIHelper.h"
#import "iTermActionsModel.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermAutomaticProfileSwitcher.h"
#import "iTermBackgroundDrawingHelper.h"
#import "iTermBadgeLabel.h"
#import "iTermBuriedSessions.h"
#import "iTermBuiltInFunctions.h"
#import "iTermCacheableImage.h"
#import "iTermCarbonHotKeyController.h"
#import "iTermCharacterSource.h"
#import "iTermColorMap.h"
#import "iTermColorPresets.h"
#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermController.h"
#import "iTermCopyModeHandler.h"
#import "iTermCopyModeState.h"
#import "iTermDisclosableView.h"
#import "iTermEchoProbe.h"
#import "iTermExpressionParser.h"
#import "iTermFindDriver.h"
#import "iTermGraphicSource.h"
#import "iTermNotificationController.h"
#import "iTermHapticActuator.h"
#import "iTermHistogram.h"
#import "iTermHotKeyController.h"
#import "iTermInitialDirectory.h"
#import "iTermKeyBindingMgr.h"
#import "iTermKeyLabels.h"
#import "iTermObject.h"
#import "iTermScriptConsole.h"
#import "iTermScriptHistory.h"
#import "iTermStandardKeyMapper.h"
#import "iTermSoundPlayer.h"
#import "iTermRawKeyMapper.h"
#import "iTermTermkeyKeyMapper.h"
#import "iTermLocalHostNameGuesser.h"
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
#import "iTermSelection.h"
#import "iTermSemanticHistoryController.h"
#import "iTermSessionFactory.h"
#import "iTermSessionHotkeyController.h"
#import "iTermSessionNameController.h"
#import "iTermSessionTitleBuiltInFunction.h"
#import "iTermSetFindStringNotification.h"
#import "iTermShellHistoryController.h"
#import "iTermShortcut.h"
#import "iTermShortcutInputView.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarLayout+tmux.h"
#import "iTermStatusBarViewController.h"
#import "iTermSwiftyString.h"
#import "iTermSwiftyStringGraph.h"
#import "iTermSystemVersion.h"
#import "iTermTextExtractor.h"
#import "iTermTheme.h"
#import "iTermThroughputEstimator.h"
#import "iTermTmuxStatusBarMonitor.h"
#import "iTermTmuxOptionMonitor.h"
#import "iTermUpdateCadenceController.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "iTermVariableScope+Session.h"
#import "iTermWarning.h"
#import "iTermWorkingDirectoryPoller.h"
#import "MovePaneController.h"
#import "MovingAverage.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSPasteboard+iTerm.h"
#import "NSStringITerm.h"
#import "NSThread+iTerm.h"
#import "NSURL+iTerm.h"
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
#import "PTYTask.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "SCPFile.h"
#import "SCPPath.h"
#import "SearchResult.h"
#import "SessionView.h"
#import "TerminalFile.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGateway.h"
#import "TmuxLayoutParser.h"
#import "TmuxStateParser.h"
#import "TmuxWindowOpener.h"
#import "Trigger.h"
#import "VT100RemoteHost.h"
#import "VT100Screen.h"
#import "VT100ScreenMark.h"
#import "VT100Terminal.h"
#import "VT100Token.h"
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

// The format for a user defaults key that recalls if the user has already been pestered about
// outdated key mappings for a give profile. The %@ is replaced with the profile's GUID.
static NSString *const kAskAboutOutdatedKeyMappingKeyFormat = @"AskAboutOutdatedKeyMappingForGuid%@";

NSString *const PTYSessionCreatedNotification = @"PTYSessionCreatedNotification";
NSString *const PTYSessionTerminatedNotification = @"PTYSessionTerminatedNotification";
NSString *const PTYSessionRevivedNotification = @"PTYSessionRevivedNotification";
NSString *const iTermSessionWillTerminateNotification = @"iTermSessionDidTerminate";

NSString *const kPTYSessionTmuxFontDidChange = @"kPTYSessionTmuxFontDidChange";
NSString *const kPTYSessionCapturedOutputDidChange = @"kPTYSessionCapturedOutputDidChange";
static NSString *const kSuppressAnnoyingBellOffer = @"NoSyncSuppressAnnyoingBellOffer";
static NSString *const kSilenceAnnoyingBellAutomatically = @"NoSyncSilenceAnnoyingBellAutomatically";
static NSString *const kReopenSessionWarningIdentifier = @"ReopenSessionAfterBrokenPipe";

static NSString *const kTurnOffMouseReportingOnHostChangeUserDefaultsKey = @"NoSyncTurnOffMouseReportingOnHostChange";
static NSString *const kTurnOffFocusReportingOnHostChangeUserDefaultsKey = @"NoSyncTurnOffFocusReportingOnHostChange";
static NSString *const kTurnOffBracketedPasteOnHostChangeUserDefaultsKey = @"NoSyncTurnOffBracketedPasteOnHostChange";

static NSString *const kTurnOffMouseReportingOnHostChangeAnnouncementIdentifier = @"TurnOffMouseReportingOnHostChange";
static NSString *const kTurnOffFocusReportingOnHostChangeAnnouncementIdentifier = @"TurnOffFocusReportingOnHostChange";
static NSString *const kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier = @"TurnOffBracketedPasteOnHostChange";

static NSString *const kShellIntegrationOutOfDateAnnouncementIdentifier =
    @"kShellIntegrationOutOfDateAnnouncementIdentifier";

static NSString *TERM_ENVNAME = @"TERM";
static NSString *COLORFGBG_ENVNAME = @"COLORFGBG";
static NSString *PWD_ENVNAME = @"PWD";
static NSString *PWD_ENVVALUE = @"~";

// Constants for saved window arrangement keys.
static NSString *const SESSION_ARRANGEMENT_COLUMNS = @"Columns";
static NSString *const SESSION_ARRANGEMENT_ROWS = @"Rows";
static NSString *const SESSION_ARRANGEMENT_BOOKMARK = @"Bookmark";
static NSString *const __attribute__((unused)) SESSION_ARRANGEMENT_BOOKMARK_NAME_DEPRECATED = @"Bookmark Name";
static NSString *const SESSION_ARRANGEMENT_WORKING_DIRECTORY = @"Working Directory";
static NSString *const SESSION_ARRANGEMENT_CONTENTS = @"Contents";
static NSString *const SESSION_ARRANGEMENT_TMUX_PANE = @"Tmux Pane";
static NSString *const SESSION_ARRANGEMENT_TMUX_HISTORY = @"Tmux History";
static NSString *const SESSION_ARRANGEMENT_TMUX_ALT_HISTORY = @"Tmux AltHistory";
static NSString *const SESSION_ARRANGEMENT_TMUX_STATE = @"Tmux State";
static NSString *const SESSION_ARRANGEMENT_TMUX_TAB_COLOR = @"Tmux Tab Color";
static NSString *const SESSION_ARRANGEMENT_IS_TMUX_GATEWAY = @"Is Tmux Gateway";
static NSString *const SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME = @"Tmux Gateway Session Name";
static NSString *const SESSION_ARRANGEMENT_TMUX_DCS_ID = @"Tmux DCS ID";
static NSString *const SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID = @"Tmux Gateway Session ID";
static NSString *const SESSION_ARRANGEMENT_NAME_CONTROLLER_STATE = @"Name Controller State";
static NSString *const __attribute__((unused)) DEPRECATED_SESSION_ARRANGEMENT_DEFAULT_NAME_DEPRECATED = @"Session Default Name";  // manually set name
static NSString *const __attribute__((unused)) DEPRECATED_SESSION_ARRANGEMENT_WINDOW_TITLE_DEPRECATED = @"Session Window Title";  // server-set window name
static NSString *const __attribute__((unused)) DEPRECATED_SESSION_ARRANGEMENT_NAME_DEPRECATED = @"Session Name";  // server-set "icon" (tab) name
static NSString *const SESSION_ARRANGEMENT_GUID = @"Session GUID";  // A truly unique ID.
static NSString *const SESSION_ARRANGEMENT_LIVE_SESSION = @"Live Session";  // If zoomed, this gives the "live" session's arrangement.
static NSString *const SESSION_ARRANGEMENT_SUBSTITUTIONS = @"Substitutions";  // Dictionary for $$VAR$$ substitutions
static NSString *const SESSION_UNIQUE_ID = @"Session Unique ID";  // DEPRECATED. A string used for restoring soft-terminated sessions for arrangements that predate the introduction of the GUID.
static NSString *const SESSION_ARRANGEMENT_SERVER_PID = @"Server PID";  // PID for server process for restoration
// TODO: Make server report the TTY to us since orphans will end up with a nil tty.
static NSString *const SESSION_ARRANGEMENT_TTY = @"TTY";  // TTY name. Used when using restoration to connect to a restored server.
static NSString *const SESSION_ARRANGEMENT_VARIABLES = @"Variables";  // _variables
static NSString *const SESSION_ARRANGEMENT_COMMAND_RANGE = @"Command Range";  // VT100GridCoordRange
static NSString *const SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED = @"Shell Integration Ever Used";  // BOOL
static NSString *const SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK = @"Alert on Next Mark";  // BOOL
static NSString *const SESSION_ARRANGEMENT_COMMANDS = @"Commands";  // Array of strings
static NSString *const SESSION_ARRANGEMENT_DIRECTORIES = @"Directories";  // Array of strings
static NSString *const SESSION_ARRANGEMENT_HOSTS = @"Hosts";  // Array of VT100RemoteHost
static NSString *const SESSION_ARRANGEMENT_CURSOR_GUIDE = @"Cursor Guide";  // BOOL
static NSString *const SESSION_ARRANGEMENT_LAST_DIRECTORY = @"Last Directory";  // NSString
static NSString *const SESSION_ARRANGEMENT_LAST_DIRECTORY_IS_UNSUITABLE_FOR_OLD_PWD = @"Last Directory Is Remote";  // BOOL
static NSString *const SESSION_ARRANGEMENT_SELECTION = @"Selection";  // Dictionary for iTermSelection.
static NSString *const SESSION_ARRANGEMENT_APS = @"Automatic Profile Switching";  // Dictionary of APS state.

static NSString *const SESSION_ARRANGEMENT_PROGRAM = @"Program";  // Dictionary. See kProgram constants below.
static NSString *const SESSION_ARRANGEMENT_ENVIRONMENT = @"Environment";  // Dictionary of environment vars program was run in
static NSString *const SESSION_ARRANGEMENT_IS_UTF_8 = @"Is UTF-8";  // TTY is in utf-8 mode
static NSString *const SESSION_ARRANGEMENT_HOTKEY = @"Session Hotkey";  // NSDictionary iTermShortcut dictionaryValue
static NSString *const SESSION_ARRANGEMENT_FONT_OVERRIDES = @"Font Overrides";  // Not saved; just used internally when creating a new tmux session.
static NSString *const SESSION_ARRANGEMENT_SHORT_LIVED_SINGLE_USE = @"Short Lived Single Use";  // BOOL

// Keys for dictionary in SESSION_ARRANGEMENT_PROGRAM
static NSString *const kProgramType = @"Type";  // Value will be one of the kProgramTypeXxx constants.
static NSString *const kProgramCommand = @"Command";  // For kProgramTypeCommand: value is command to run.

// Values for kProgramType
static NSString *const kProgramTypeShellLauncher = @"Shell Launcher";  // Use iTerm2 --launch_shell
static NSString *const kProgramTypeCommand = @"Command";  // Use command in kProgramCommand

static NSString *kTmuxFontChanged = @"kTmuxFontChanged";

// Value for SESSION_ARRANGEMENT_TMUX_TAB_COLOR that means "don't use the
// default color from the tmux profile; this tab should have no color."
static NSString *const iTermTmuxTabColorNone = @"none";

// Maps Session GUID to saved contents. Only live between window restoration
// and the end of startup activities.
static NSMutableDictionary *gRegisteredSessionContents;

// Rate limit for checking instant (partial-line) triggers, in seconds.
static NSTimeInterval kMinimumPartialLineTriggerCheckInterval = 0.5;

// Grace period to avoid failing to write anti-idle code when timer runs just before when the code
// should be sent.
static const NSTimeInterval kAntiIdleGracePeriod = 0.1;

// Limit for number of entries in self.directories, self.commands, self.hosts.
// Keeps saved state from exploding like in issue 5029.
static const NSUInteger kMaxDirectories = 100;
static const NSUInteger kMaxCommands = 100;
static const NSUInteger kMaxHosts = 100;

@interface PTYSession () <
    iTermAutomaticProfileSwitcherDelegate,
    iTermBackgroundDrawingHelperDelegate,
    iTermBadgeLabelDelegate,
    iTermCoprocessDelegate,
    iTermCopyModeHandlerDelegate,
    iTermHotKeyNavigableSession,
    iTermMetaFrustrationDetector,
    iTermMetalGlueDelegate,
    iTermObject,
    iTermPasteHelperDelegate,
    iTermSessionNameControllerDelegate,
    iTermSessionViewDelegate,
    iTermStandardKeyMapperDelegate,
    iTermStatusBarViewControllerDelegate,
    iTermTermkeyKeyMapperDelegate,
    iTermUpdateCadenceControllerDelegate,
    iTermWorkingDirectoryPollerDelegate>
@property(nonatomic, retain) Interval *currentMarkOrNotePosition;
@property(nonatomic, retain) TerminalFileDownload *download;
@property(nonatomic, retain) TerminalFileUpload *upload;

// Time since reference date when last output was received. New output in a brief period after the
// session is resized is ignored to avoid making the spinner spin due to resizing.
@property(nonatomic) NSTimeInterval lastOutputIgnoringOutputAfterResizing;

// Time the window was last resized at.
@property(nonatomic) NSTimeInterval lastResize;
@property(atomic, assign) PTYSessionTmuxMode tmuxMode;
@property(nonatomic, copy) NSString *lastDirectory;
@property(nonatomic) BOOL lastDirectoryIsUnsuitableForOldPWD;
@property(nonatomic, retain) VT100RemoteHost *lastRemoteHost;  // last remote host at time of setting current directory
@property(nonatomic, retain) NSColor *cursorGuideColor;
@property(nonatomic, copy) NSString *badgeFormat;

// Info about what happens when the program is run so it can be restarted after
// a broken pipe if the user so chooses. Contains $$MACROS$$ pre-substitution.
@property(nonatomic, copy) NSString *program;
@property(nonatomic, copy) NSDictionary *environment;
@property(nonatomic, assign) BOOL isUTF8;
@property(nonatomic, copy) NSDictionary *substitutions;
@property(nonatomic, copy) NSString *guid;
@property(nonatomic, retain) iTermPasteHelper *pasteHelper;
@property(nonatomic, copy) NSString *lastCommand;
@property(nonatomic, retain) iTermAutomaticProfileSwitcher *automaticProfileSwitcher;
@property(nonatomic, retain) VT100RemoteHost *currentHost;
@end

@implementation PTYSession {
    // PTYTask has started a job, and a call to -taskWasDeregistered will be
    // made when it dies. All access should be synchronized.
    BOOL _registered;

    // Terminal processes vt100 codes.
    VT100Terminal *_terminal;

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

    // The absolute line number of the next line to apply triggers to.
    long long _triggerLineNumber;

    // The current triggers.
    NSMutableArray *_triggers;

    // Does the terminal think this session is focused?
    BOOL _focused;

    FindContext *_tailFindContext;
    NSTimer *_tailFindTimer;

    TmuxGateway *_tmuxGateway;
    BOOL _tmuxSecureLogging;
    // The tmux rename-window command is only sent when the name field resigns first responder.
    // This tracks if a tmux client's name has changed but the tmux server has not been informed yet.
    BOOL _tmuxTitleOutOfSync;
    PTYSessionTmuxMode _tmuxMode;

    NSInteger _requestAttentionId;  // Last request-attention identifier
    iTermMark *_lastMark;

    VT100GridCoordRange _commandRange;
    VT100GridAbsCoordRange _lastOrCurrentlyRunningCommandAbsRange;
    long long _lastPromptLine;  // Line where last prompt began

    // -2: Within command output (inferred)
    // -1: Uninitialized
    // >= 0: The line the prompt is at
    long long _fakePromptDetectedAbsLine;

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
    BOOL _reportingMouseDown;

    // Has a shell integration code ever been seen? A rough guess as to whether we can assume
    // shell integration is currently being used.
    BOOL _shellIntegrationEverUsed;

    // Has the user or an escape code change the cursor guide setting?
    // If so, then the profile setting will be disregarded.
    BOOL _cursorGuideSettingHasChanged;

    // The last time at which a partial-line trigger check occurred. This keeps us from wasting CPU
    // checking long lines over and over.
    NSTimeInterval _lastPartialLineTriggerCheck;

    // Maps announcement identifiers to view controllers.
    NSMutableDictionary *_announcements;

    // Tokens get queued when a shell enters the paused state. If it gets unpaused, then these are
    // executed before any others.
    NSMutableArray *_queuedTokens;

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

    // Estimates throughput for adaptive framerate.
    iTermThroughputEstimator *_throughputEstimator;

    // Current unicode version.
    NSInteger _unicodeVersion;

    // Touch bar labels for function keys.
    NSMutableDictionary<NSString *, NSString *> *_keyLabels;
    NSMutableArray<iTermKeyLabels *> *_keyLabelsStack;

    // If the session was created from a saved arrangement with a missing profile then this records
    // the GUID of the missing profile. If the saved arrangement gets repaired then a notification
    // is posted and all sessions with that bogus GUID can hide their profile and reload their
    // profile.
    NSString *_missingSavedArrangementProfileGUID;

    // The containing window is in the midst of a live resize. The update timer
    // runs in the common modes runloop in this case. That's not acceptable
    // for normal use for reasons that Apple leaves up to your imagination (it
    // doesn't fire while you hold down a key, for example), but it does fire
    // during live resize (unlike the default runloops).
    BOOL _inLiveResize;

    VT100RemoteHost *_currentHost;

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

    iTermCopyModeHandler *_copyModeHandler;

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

    iTermBackgroundDrawingHelper *_backgroundDrawingHelper;
    iTermMetaFrustrationDetector *_metaFrustrationDetector;

    iTermTmuxStatusBarMonitor *_tmuxStatusBarMonitor;
    iTermWorkingDirectoryPoller *_pwdPoller;
    iTermTmuxOptionMonitor *_tmuxTitleMonitor;

    iTermGraphicSource *_graphicSource;
    iTermVariableReference *_jobPidRef;
    iTermCacheableImage *_customIcon;
    CGContextRef _metalContext;
    BOOL _errorCreatingMetalContext;

    id<iTermKeyMapper> _keyMapper;
    BOOL _useLibTickit;
    NSString *_badgeFontName;
    iTermVariableScope *_variablesScope;
    
    BOOL _showingVisualIndicatorForEsc;

    iTermPrintGuard *_printGuard;
    iTermBuiltInFunctions *_methods;

    // When this is true, changing the font size does not cause the window size to change.
    BOOL _windowAdjustmentDisabled;
}

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
        _autoLogId = arc4random();
        _useAdaptiveFrameRate = [iTermAdvancedSettingsModel useAdaptiveFrameRate];
        _adaptiveFrameRateThroughputThreshold = [iTermAdvancedSettingsModel adaptiveFrameRateThroughputThreshold];
        _idleTime = [iTermAdvancedSettingsModel idleTimeSeconds];
        _triggerLineNumber = -1;
        _fakePromptDetectedAbsLine = -1;
        // The new session won't have the move-pane overlay, so just exit move pane
        // mode.
        [[MovePaneController sharedInstance] exitMovePaneMode];
        _lastInput = [NSDate timeIntervalSinceReferenceDate];
        _copyModeHandler = [[iTermCopyModeHandler alloc] init];
        _copyModeHandler.delegate = self;

        // Experimentally, this is enough to keep the queue primed but not overwhelmed.
        // TODO: How do slower machines fare?
        static const int kMaxOutstandingExecuteCalls = 4;
        _executionSemaphore = dispatch_semaphore_create(kMaxOutstandingExecuteCalls);

        _lastOutputIgnoringOutputAfterResizing = _lastInput;
        _lastUpdate = _lastInput;
        _pasteHelper = [[iTermPasteHelper alloc] init];
        _pasteHelper.delegate = self;
        _colorMap = [[iTermColorMap alloc] init];
        // Allocate screen, shell, and terminal objects
        _shell = [[PTYTask alloc] init];
        _terminal = [[VT100Terminal alloc] init];
        _terminal.output.optionIsMetaForSpecialKeys =
            [iTermAdvancedSettingsModel optionIsMetaForSpecialChars];
        _screen = [[VT100Screen alloc] initWithTerminal:_terminal];
        NSParameterAssert(_shell != nil && _terminal != nil && _screen != nil);

        _overriddenFields = [[NSMutableSet alloc] init];
        // Allocate a guid. If we end up restoring from a session during startup this will be replaced.
        _guid = [[NSString uuid] retain];
        [[PTYSession sessionMap] setObject:self forKey:_guid];

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
        _commandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
        _lastOrCurrentlyRunningCommandAbsRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _activityCounter = [@0 retain];
        _announcements = [[NSMutableDictionary alloc] init];
        _queuedTokens = [[NSMutableArray alloc] init];
        _commands = [[NSMutableArray alloc] init];
        _directories = [[NSMutableArray alloc] init];
        _hosts = [[NSMutableArray alloc] init];
        _automaticProfileSwitcher = [[iTermAutomaticProfileSwitcher alloc] initWithDelegate:self];
        _throughputEstimator = [[iTermThroughputEstimator alloc] initWithHistoryOfDuration:5.0 / 30.0 secondsPerBucket:1 / 30.0];
        _cadenceController = [[iTermUpdateCadenceController alloc] initWithThroughputEstimator:_throughputEstimator];
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
        if (@available(macOS 10.11, *)) {
            _metalGlue = [[iTermMetalGlue alloc] init];
            _metalGlue.delegate = self;
            _metalGlue.screen = _screen;
        }
        _echoProbe = [[iTermEchoProbe alloc] init];
        _echoProbe.delegate = self;
        _metaFrustrationDetector = [[iTermMetaFrustrationDetector alloc] init];
        _metaFrustrationDetector.delegate = self;
        _pwdPoller = [[iTermWorkingDirectoryPoller alloc] init];
        _pwdPoller.delegate = self;
        _graphicSource = [[iTermGraphicSource alloc] init];

        // This is a placeholder. When the profile is set it will get updated.
        iTermStandardKeyMapper *standardKeyMapper = [[iTermStandardKeyMapper alloc] init];
        standardKeyMapper.delegate = self;
        _keyMapper = standardKeyMapper;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(coprocessChanged)
                                                     name:@"kCoprocessStatusChangeNotification"
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
                                                 selector:@selector(annotationVisibilityDidChange:)
                                                     name:iTermAnnotationVisibilityDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(apiDidStop:)
                                                     name:iTermAPIHelperDidStopNotification
                                                   object:nil];
        [iTermSetFindStringNotification subscribe:self
                                            block:^(iTermSetFindStringNotification * _Nonnull notification) {
                                                [weakSelf useStringForFind:notification.string];
                                            }];

        [self.variablesScope setValue:[self.sessionId stringByReplacingOccurrencesOfString:@":" withString:@"."]
                     forVariableNamed:iTermVariableKeySessionTermID];

        if (!synthetic) {
            [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionCreatedNotification object:self];
        }
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    [_view release];
    if (@available(macOS 10.11, *)) {
        [_metalGlue release];
    }
    [_nameController release];
    [self stopTailFind];  // This frees the substring in the tail find context, if needed.
    _shell.delegate = nil;
    dispatch_release(_executionSemaphore);
    [_colorMap release];
    [_triggers release];
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
    [_terminal release];
    [_tailFindContext release];
    [_lastMark release];
    [_patternedImage release];
    [_announcements release];
    [self recycleQueuedTokens];
    [_queuedTokens release];
    [_variables release];
    [_userVariables release];
    [_program release];
    [_environment release];
    [_commands release];
    [_directories release];
    [_hosts release];
    [_bellRate release];
    [_guid release];
    [_lastCommand release];
    [_substitutions release];
    [_automaticProfileSwitcher release];
    [_throughputEstimator release];

    [_keyLabels release];
    [_keyLabelsStack release];
    [_missingSavedArrangementProfileGUID release];
    [_currentHost release];

    [_keystrokeSubscriptions release];
    [_keyboardFilterSubscriptions release];
    [_updateSubscriptions release];
    [_promptSubscriptions release];
    [_customEscapeSequenceNotifications release];

    [_copyModeHandler release];
    [_metalDisabledTokens release];
    [_badgeSwiftyString release];
    [_autoNameSwiftyString release];
    [_statusBarViewController release];
    [_echoProbe release];
    [_backgroundDrawingHelper release];
    [_metaFrustrationDetector release];
    [_tmuxStatusBarMonitor setActive:NO];
    [_tmuxStatusBarMonitor release];
    [_tmuxTitleMonitor release];
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

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p %dx%d metal=%@ id=%@>",
               [self class], self, [_screen width], [_screen height], @(self.useMetal), _guid];
}

- (void)didFinishInitialization:(BOOL)ok {
    [_pwdPoller poll];
    if ([self.variablesScope valueForVariableName:iTermVariableKeySessionUsername] == nil) {
        [self.variablesScope setValue:NSUserName() forVariableNamed:iTermVariableKeySessionUsername];
    }
    if ([self.variablesScope valueForVariableName:iTermVariableKeySessionHostname] == nil) {
        __weak __typeof(self) weakSelf = self;
        [[iTermLocalHostNameGuesser sharedInstance] callBlockWhenReady:^(NSString * _Nonnull name) {
            [weakSelf didGuessLocalHostName:name];
        }];
    }
}

- (void)didGuessLocalHostName:(NSString *)name {
    if ([self.variablesScope valueForVariableName:iTermVariableKeySessionHostname] == nil) {
        [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionHostname];
    }
}

- (void)setGuid:(NSString *)guid {
    if ([NSObject object:guid isEqualToObject:_guid]) {
        return;
    }
    if (_guid) {
        [[PTYSession sessionMap] removeObjectForKey:_guid];
    }
    [_guid autorelease];
    _guid = [guid copy];
    [[PTYSession sessionMap] setObject:self forKey:_guid];
    [self.variablesScope setValue:_guid forVariableNamed:iTermVariableKeySessionID];
}

- (void)setLiveSession:(PTYSession *)liveSession {
    assert(liveSession != self);
    if (liveSession) {
        assert(!_liveSession);
        _synthetic = YES;
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
            NSBeep();
            return;
        }

    }
    if (dir > 0) {
        if (![_dvrDecoder next]) {
            NSBeep();
        }
    } else {
        if (![_dvrDecoder prev]) {
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
    int width = source.screen.width;
    for (NSUInteger i = 0; i < rangeOfLines.length; i++) {
        int row = rangeOfLines.location + i;
        screen_char_t *theLine = [source.screen getLineAtIndex:row];
        if (i + 1 == rangeOfLines.length) {
            screen_char_t continuation = { 0 };
            continuation.code = EOL_SOFT;
            [_screen appendScreenChars:theLine length:width continuation:continuation];
        } else {
            [_screen appendScreenChars:theLine length:width continuation:theLine[width]];
        }
    }
}

- (void)setCopyMode:(BOOL)copyMode {
    _copyModeHandler.enabled = copyMode;
}

- (BOOL)copyMode {
    return _copyModeHandler.enabled;
}

- (BOOL)copyModeConsumesEvent:(NSEvent *)event {
    return [_copyModeHandler wouldHandleEvent:event];
}

- (void)coprocessChanged
{
    [_textview setNeedsDisplay:YES];
}

+ (void)drawArrangementPreview:(NSDictionary *)arrangement frame:(NSRect)frame
{
    Profile* theBookmark =
        [[ProfileModel sharedInstance] bookmarkWithGuid:arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_GUID]];
    if (!theBookmark) {
        theBookmark = [arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK];
    }
    //    [self setForegroundColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_FOREGROUND_COLOR]]];
    [[ITAddressBookMgr decodeColor:[theBookmark objectForKey:KEY_BACKGROUND_COLOR]] set];
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

- (iTermAnnouncementViewController *)announcementForMissingProfileInArrangement:(NSDictionary *)arrangement {
    iTermAnnouncementViewController *announcement = nil;
    NSString *missingProfileName = [[arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_NAME] copy] autorelease];
    DLog(@"Can't find profile %@ guid %@", missingProfileName, arrangement[SESSION_ARRANGEMENT_BOOKMARK][KEY_GUID]);
    if (![iTermAdvancedSettingsModel noSyncSuppressMissingProfileInArrangementWarning]) {
        NSString *notice;
        NSArray<NSString *> *actions = @[ @"Don't Warn Again" ];
        NSString *savedArrangementName = [[iTermController sharedInstance] savedArrangementNameBeingRestored];
        if ([[ProfileModel sharedInstance] bookmarkWithName:missingProfileName]) {
            notice = [NSString stringWithFormat:@"This session's profile, “%@”, no longer exists. A profile with that name happens to exist.", missingProfileName];
            if (savedArrangementName) {
                actions = [actions arrayByAddingObject:@"Repair Saved Arrangement"];
            }
        } else {
            notice = [NSString stringWithFormat:@"This session's profile, “%@”, no longer exists.", missingProfileName];
        }
        Profile *thisProfile = arrangement[SESSION_ARRANGEMENT_BOOKMARK];
        [_missingSavedArrangementProfileGUID autorelease];
        _missingSavedArrangementProfileGUID = [thisProfile[KEY_GUID] copy];
        announcement =
            [iTermAnnouncementViewController announcementWithTitle:notice
                                                             style:kiTermAnnouncementViewStyleWarning
                                                       withActions:actions
                                                        completion:^(int selection) {
                                                            if (selection == 0) {
                                                                [iTermAdvancedSettingsModel setNoSyncSuppressMissingProfileInArrangementWarning:YES];
                                                            } else if (selection == 1) {
                                                                // Repair
                                                                Profile *similarlyNamedProfile = [[ProfileModel sharedInstance] bookmarkWithName:missingProfileName];
                                                                [[iTermController sharedInstance] repairSavedArrangementNamed:savedArrangementName
                                                                                                         replacingMissingGUID:thisProfile[KEY_GUID]
                                                                                                                     withGUID:similarlyNamedProfile[KEY_GUID]];
                                                                [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionDidRepairSavedArrangement
                                                                                                                    object:thisProfile[KEY_GUID]
                                                                                                                  userInfo:@{ @"new profile": similarlyNamedProfile }];
                                                            }
                                                        }];
        announcement.dismissOnKeyDown = YES;
    }
    return announcement;
}

+ (void)finishInitializingArrangementOriginatedSession:(PTYSession *)aSession
                                           arrangement:(NSDictionary *)arrangement
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

    NSArray *history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_HISTORY];
    if (history) {
        [[aSession screen] setHistory:history];
    }
    history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_ALT_HISTORY];
    if (history) {
        [[aSession screen] setAltScreen:history];
    }
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
    if (arrangement[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED]) {
        aSession->_shellIntegrationEverUsed = [arrangement[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED] boolValue];
    }
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
            VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] initWithDictionary:host] autorelease];
            if (remoteHost) {
                [aSession.hosts addObject:remoteHost];
                [aSession trimHostsIfNeeded];
            }
        }
    }

    if (arrangement[SESSION_ARRANGEMENT_SELECTION]) {
        [aSession.textview.selection setFromDictionaryValue:arrangement[SESSION_ARRANGEMENT_SELECTION]
                                                      width:aSession.screen.width];
    }
    if (arrangement[SESSION_ARRANGEMENT_APS]) {
        aSession.automaticProfileSwitcher =
            [[iTermAutomaticProfileSwitcher alloc] initWithDelegate:aSession
                                                         savedState:arrangement[SESSION_ARRANGEMENT_APS]];
    }
    if (didRestoreContents && attachedToServer) {
        Interval *interval = aSession.screen.lastPromptMark.entry.interval;
        if (interval) {
            VT100GridRange gridRange = [aSession.screen lineNumberRangeOfInterval:interval];
            aSession->_lastPromptLine = gridRange.location + aSession.screen.totalScrollbackOverflow;
        }

        if (arrangement[SESSION_ARRANGEMENT_COMMAND_RANGE]) {
            aSession->_commandRange = [arrangement[SESSION_ARRANGEMENT_COMMAND_RANGE] gridCoordRange];
        }
        if (arrangement[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK]) {
            aSession->_alertOnNextMark = [arrangement[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK] boolValue];
        }
        if (arrangement[SESSION_ARRANGEMENT_CURSOR_GUIDE]) {
            aSession.textview.highlightCursorLine = [arrangement[SESSION_ARRANGEMENT_CURSOR_GUIDE] boolValue];
        }
        aSession->_lastMark = [aSession.screen.lastMark retain];
        aSession.lastRemoteHost = aSession.screen.lastRemoteHost;
        if (arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY]) {
            [aSession->_lastDirectory autorelease];
            aSession->_lastDirectory = [arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY] copy];
            aSession->_lastDirectoryIsUnsuitableForOldPWD = [arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY_IS_UNSUITABLE_FOR_OLD_PWD] boolValue];
        }
    }

    if (state) {
        [[aSession screen] setTmuxState:state];
        NSData *pendingOutput = [state objectForKey:kTmuxWindowOpenerStatePendingOutput];
        if (pendingOutput && [pendingOutput length]) {
            [aSession.terminal.parser putStreamData:pendingOutput.bytes
                                             length:pendingOutput.length];
        }
        [[aSession terminal] setInsertMode:[[state objectForKey:kStateDictInsertMode] boolValue]];
        [[aSession terminal] setCursorMode:[[state objectForKey:kStateDictKCursorMode] boolValue]];
        [[aSession terminal] setKeypadMode:[[state objectForKey:kStateDictKKeypadMode] boolValue]];
        if ([[state objectForKey:kStateDictMouseStandardMode] boolValue]) {
            [[aSession terminal] setMouseMode:MOUSE_REPORTING_NORMAL];
        } else if ([[state objectForKey:kStateDictMouseButtonMode] boolValue]) {
            [[aSession terminal] setMouseMode:MOUSE_REPORTING_BUTTON_MOTION];
        } else if ([[state objectForKey:kStateDictMouseAnyMode] boolValue]) {
            [[aSession terminal] setMouseMode:MOUSE_REPORTING_ALL_MOTION];
        } else {
            [[aSession terminal] setMouseMode:MOUSE_REPORTING_NONE];
        }
        [[aSession terminal] setMouseFormat:[[state objectForKey:kStateDictMouseUTF8Mode] boolValue] ? MOUSE_FORMAT_XTERM_EXT : MOUSE_FORMAT_XTERM];
    }
    NSDictionary *liveArrangement = arrangement[SESSION_ARRANGEMENT_LIVE_SESSION];
    if (liveArrangement) {
        SessionView *liveView = [[[SessionView alloc] initWithFrame:sessionView.frame] autorelease];
        if (@available(macOS 10.11, *)) {
            liveView.driver.dataSource = aSession->_metalGlue;
        }
        [delegate addHiddenLiveView:liveView];
        aSession.liveSession = [self sessionFromArrangement:liveArrangement
                                                     inView:liveView
                                               withDelegate:delegate
                                              forObjectType:objectType];
    }
    if (shouldEnterTmuxMode) {
        // Restored a tmux gateway session.
        [aSession startTmuxMode:tmuxDCSIdentifier];
        [aSession.tmuxController sessionChangedTo:arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME]
                                        sessionId:[arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] intValue]];
    }
    if (missingProfile) {
        iTermAnnouncementViewController *announcement = [aSession announcementForMissingProfileInArrangement:arrangement];
        if (announcement) {
            [aSession queueAnnouncement:announcement identifier:@"ThisProfileNoLongerExists"];
        }
    }

    NSString *path = [aSession.screen workingDirectoryOnLine:aSession.screen.numberOfScrollbackLines + aSession.screen.cursorY - 1];
    [aSession.variablesScope setValue:path forVariableNamed:iTermVariableKeySessionPath];

    [aSession.nameController setNeedsUpdate];
    [aSession.nameController updateIfNeeded];
}

+ (PTYSession *)sessionFromArrangement:(NSDictionary *)arrangement
                                inView:(SessionView *)sessionView
                          withDelegate:(id<PTYSessionDelegate>)delegate
                         forObjectType:(iTermObjectType)objectType {
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
    aSession.view = sessionView;

    [sessionView setFindDriverDelegate:aSession];
    NSDictionary<NSString *, NSString *> *overrides = arrangement[SESSION_ARRANGEMENT_FONT_OVERRIDES];
    if (overrides) {
        NSMutableDictionary *temp = [[theBookmark mutableCopy] autorelease];
        [overrides enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            temp[key] = obj;
        }];
        theBookmark = temp;
    }
    if ([arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_PANE]) {
        // This is a tmux arrangement.
        NSString *colorString = arrangement[SESSION_ARRANGEMENT_TMUX_TAB_COLOR];
        NSDictionary *tabColorDict = [ITAddressBookMgr encodeColor:[NSColor colorFromHexString:colorString]];
        if (tabColorDict) {
            // We're restoring a tmux arrangement that specifies a tab color.
            if (![iTermProfilePreferences boolForKey:KEY_USE_TAB_COLOR inProfile:theBookmark] ||
                ![[ITAddressBookMgr decodeColor:[iTermProfilePreferences objectForKey:KEY_TAB_COLOR inProfile:theBookmark]] isEqual:tabColorDict]) {
                // The tmux profile does not specify a tab color or it specifies a different one. Override it and divorce.
                theBookmark = [theBookmark dictionaryBySettingObject:tabColorDict forKey:KEY_TAB_COLOR];
                theBookmark = [theBookmark dictionaryBySettingObject:@YES forKey:KEY_USE_TAB_COLOR];
                needDivorce = YES;
            }
        } else if ([colorString isEqualToString:iTermTmuxTabColorNone] &&
                   [iTermProfilePreferences boolForKey:KEY_USE_TAB_COLOR inProfile:theBookmark]) {
            // There was no tab color but the tmux profile specifies one. Disable it and divorce.
            theBookmark = [theBookmark dictionaryBySettingObject:@NO forKey:KEY_USE_TAB_COLOR];
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
    }

    [[aSession screen] setUnlimitedScrollback:[[theBookmark objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[theBookmark objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setProfile:theBookmark];

    [aSession setScreenSize:[sessionView frame] parent:[delegate realParentWindow]];
    NSDictionary *state = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_STATE];
    if (state) {
        // For tmux tabs, get the size from the arrangement instead of the containing view because
        // it helps things to line up correctly.
        [aSession setSizeFromArrangement:arrangement];
    }
    [aSession setPreferencesFromAddressBookEntry:theBookmark];
    [aSession loadInitialColorTable];
    aSession.delegate = delegate;

    BOOL haveSavedProgramData = YES;
    if ([arrangement[SESSION_ARRANGEMENT_PROGRAM] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = arrangement[SESSION_ARRANGEMENT_PROGRAM];
        if ([dict[kProgramType] isEqualToString:kProgramTypeShellLauncher]) {
            aSession.program = [ITAddressBookMgr shellLauncherCommand];
        } else if ([dict[kProgramType] isEqualToString:kProgramTypeCommand]) {
            aSession.program = dict[kProgramCommand];
        } else {
            haveSavedProgramData = NO;
        }
    } else {
        haveSavedProgramData = NO;
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

    if (arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS]) {
        aSession.substitutions = arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS];
    } else {
        haveSavedProgramData = NO;
    }

    // This must be done before setContentsFromLineBufferDictionary:includeRestorationBanner:reattached:
    // because it will show an announcement if mouse reporting is on.
    VT100RemoteHost *lastRemoteHost = aSession.screen.lastRemoteHost;
    if (lastRemoteHost) {
        [aSession screenCurrentHostDidChange:lastRemoteHost];
    }

    NSNumber *tmuxPaneNumber = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_PANE];
    NSString *tmuxDCSIdentifier = nil;
    BOOL shouldEnterTmuxMode = NO;
    NSDictionary *contents = arrangement[SESSION_ARRANGEMENT_CONTENTS];
    BOOL restoreContents = !tmuxPaneNumber && contents && [iTermAdvancedSettingsModel restoreWindowContents];
    BOOL attachedToServer = NO;
    typedef void (^iTermBooleanCompletionBlock)(BOOL ok);
    void (^runCommandBlock)(iTermBooleanCompletionBlock) = ^(void (^completion)(BOOL)) { completion(YES); };
    BOOL startAutoLog = NO;
    if (!tmuxPaneNumber) {
        DLog(@"No tmux pane ID during session restoration");
        // |contents| will be non-nil when using system window restoration.
        BOOL runCommand = YES;
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            DLog(@"Configured to run jobs in servers");
            // iTerm2 is currently configured to run jobs in servers, but we
            // have to check if the arrangement was saved with that setting on.
            if (arrangement[SESSION_ARRANGEMENT_SERVER_PID]) {
                DLog(@"Have a server PID in the arrangement");
                pid_t serverPid = [arrangement[SESSION_ARRANGEMENT_SERVER_PID] intValue];
                DLog(@"Try to attach to pid %d", (int)serverPid);
                // serverPid might be -1 if the user turned on session restoration and then quit.
                if (serverPid != -1 && [aSession tryToAttachToServerWithProcessId:serverPid]) {
                    DLog(@"Success!");

                    if ([arrangement[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] boolValue]) {
                        DLog(@"Was a tmux gateway. Start recovery mode in parser.");
                        // Before attaching to the server we can put the parser into "tmux recovery mode".
                        [aSession.terminal.parser startTmuxRecoveryMode];
                    }

                    runCommand = NO;
                    attachedToServer = YES;
                    aSession.shell.tty = arrangement[SESSION_ARRANGEMENT_TTY];
                    shouldEnterTmuxMode = ([arrangement[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] boolValue] &&
                                           arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME] != nil &&
                                           arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] != nil);
                    tmuxDCSIdentifier = arrangement[SESSION_ARRANGEMENT_TMUX_DCS_ID];
                }
            }
        }

        // GUID will be set for new saved arrangements since late 2014.
        // Older versions won't be able to associate saved state with windows from a saved arrangement.
        if (arrangement[SESSION_ARRANGEMENT_GUID]) {
            DLog(@"The session arrangement has a GUID");
            NSString *guid = arrangement[SESSION_ARRANGEMENT_GUID];
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
        }

        if (runCommand) {
            // This path is NOT taken when attaching to a running server.
            //
            // When restoring a window arrangement with contents and a nonempty saved directory, always
            // use the saved working directory, even if that contravenes the default setting for the
            // profile.
            NSString *oldCWD = arrangement[SESSION_ARRANGEMENT_WORKING_DIRECTORY];
            DLog(@"Running command...");

            NSDictionary *environmentArg = @{};
            NSString *commandArg = nil;
            NSNumber *isUTF8Arg = nil;
            NSDictionary *substitutionsArg = nil;
            if (haveSavedProgramData) {
                // This is the normal case; the else clause is for legacy saved arrangements.
                environmentArg = aSession.environment ?: @{};
                commandArg = aSession.program;
                if (oldCWD &&
                    [aSession.program isEqualToString:[ITAddressBookMgr standardLoginCommand]]) {
                    // Create a login session that drops you in the old directory instead of
                    // using login -fp "$USER". This lets saved arrangements properly restore
                    // the working directory when the profile specifies the home directory.
                    commandArg = [ITAddressBookMgr shellLauncherCommand];
                }
                isUTF8Arg = @(aSession.isUTF8);
                substitutionsArg = aSession.substitutions;
            }
            runCommandBlock = ^(iTermBooleanCompletionBlock completion) {
                iTermSessionFactory *factory = [[[iTermSessionFactory alloc] init] autorelease];
                [factory attachOrLaunchCommandInSession:aSession
                                              canPrompt:NO
                                             objectType:objectType
                                       serverConnection:nil
                                              urlString:nil
                                           allowURLSubs:NO
                                            environment:environmentArg
                                                 oldCWD:oldCWD
                                         forceUseOldCWD:contents != nil && oldCWD.length
                                                command:commandArg
                                                 isUTF8:isUTF8Arg
                                          substitutions:substitutionsArg
                                       windowController:(PseudoTerminal *)aSession.delegate.realParentWindow
                                            synchronous:NO
                                             completion:completion];
            };
        }
    } else {
        // Is a tmux pane
        // NOTE: There used to be code here that used state[@"title"] but AFAICT that didn't exist.
        if ([aSession.profile[KEY_AUTOLOG] boolValue]) {
            startAutoLog = YES;
        }
        [aSession setTmuxPane:[tmuxPaneNumber intValue]];
    }
    void (^finish)(BOOL) = ^(BOOL ok) {
        if (!ok) {
            return;
        }
        [self finishInitializingArrangementOriginatedSession:aSession
                                                 arrangement:arrangement
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
        [aSession didFinishInitialization:YES];
    };
    if (startAutoLog) {
        [aSession retain];
        [aSession fetchAutoLogFilenameSynchronously:NO
                                         completion:
         ^(NSString * _Nonnull filename) {
             if (filename) {
                 [aSession.shell startLoggingToFileWithPath:filename
                                               shouldAppend:NO];
             }
             [aSession autorelease];
             runCommandBlock(finish);
         }];
    } else {
        runCommandBlock(finish);
    }

    return aSession;
}

- (void)setContentsFromLineBufferDictionary:(NSDictionary *)dict
                   includeRestorationBanner:(BOOL)includeRestorationBanner
                                 reattached:(BOOL)reattached {
    [_screen restoreFromDictionary:dict
          includeRestorationBanner:includeRestorationBanner
                     knownTriggers:_triggers
                        reattached:reattached];
    // Do this to force the hostname variable to be updated.
    [self currentHost];
}

- (void)showOrphanAnnouncement {
    NSString *notice = @"This already-running session was restored but its contents were not saved.";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:notice
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"Why?" ]
                                                completion:^(int selection) {
                                                    if (selection == 0) {
                                                        // Why?
                                                        NSURL *whyUrl = [NSURL URLWithString:@"https://iterm2.com/why_no_content.html"];
                                                        [[NSWorkspace sharedWorkspace] openURL:whyUrl];
                                                    }
                                                }];
    announcement.dismissOnKeyDown = YES;
    [self queueAnnouncement:announcement identifier:kReopenSessionWarningIdentifier];
}

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent {
    _screen.delegate = self;

    // Allocate the root per-session view.
    if (!_view) {
        self.view = [[[SessionView alloc] initWithFrame:NSMakeRect(0, 0, aRect.size.width, aRect.size.height)] autorelease];
        if (@available(macOS 10.11, *)) {
            self.view.driver.dataSource = _metalGlue;
        }
        [_view setFindDriverDelegate:self];
    }

    _view.scrollview.hasVerticalRuler = [parent scrollbarShouldBeVisible];

    // Allocate a text view
    NSSize aSize = [_view.scrollview contentSize];
    _wrapper = [[TextViewWrapper alloc] initWithFrame:NSMakeRect(0, 0, aSize.width, aSize.height)];

    _textview = [[PTYTextView alloc] initWithFrame: NSMakeRect(0, [iTermAdvancedSettingsModel terminalVMargin], aSize.width, aSize.height)
                                          colorMap:_colorMap];
    _textview.keyboardHandler.keyMapper = _keyMapper;

    if (@available(macOS 10.11, *)) {
        _metalGlue.textView = _textview;
    }
    _colorMap.dimOnlyText = [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
    [_textview setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [_textview setFont:[ITAddressBookMgr fontWithDesc:[_profile objectForKey:KEY_NORMAL_FONT]]
          nonAsciiFont:[ITAddressBookMgr fontWithDesc:[_profile objectForKey:KEY_NON_ASCII_FONT]]
     horizontalSpacing:[[_profile objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
       verticalSpacing:[[_profile objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    [self setTransparency:[[_profile objectForKey:KEY_TRANSPARENCY] floatValue]];
    const float theBlend =
        [_profile objectForKey:KEY_BLEND] ? [[_profile objectForKey:KEY_BLEND] floatValue] : 0.5;
    [self setBlend:theBlend];
    [self setTransparencyAffectsOnlyDefaultBackgroundColor:[[_profile objectForKey:KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR] boolValue]];

    [_wrapper addSubview:_textview];
    [_textview setFrame:NSMakeRect(0, [iTermAdvancedSettingsModel terminalVMargin], aSize.width, aSize.height - [iTermAdvancedSettingsModel terminalVMargin])];

    // assign terminal and task objects
    _terminal.delegate = _screen;
    [_shell setDelegate:self];
    [self.variablesScope setValue:_shell.tty forVariableNamed:iTermVariableKeySessionTTY];
    [self.variablesScope setValue:@(_terminal.mouseMode) forVariableNamed:iTermVariableKeySessionMouseReportingMode];

    // initialize the screen
    // TODO: Shouldn't this take the scrollbar into account?
    NSSize contentSize = [PTYScrollView contentSizeForFrameSize:aSize
                                        horizontalScrollerClass:nil
                                          verticalScrollerClass:parent.scrollbarShouldBeVisible ? [[_view.scrollview verticalScroller] class] : nil
                                                     borderType:_view.scrollview.borderType
                                                    controlSize:NSControlSizeRegular
                                                  scrollerStyle:_view.scrollview.scrollerStyle];

    int width = (contentSize.width - [iTermAdvancedSettingsModel terminalMargin]*2) / [_textview charWidth];
    int height = (contentSize.height - [iTermAdvancedSettingsModel terminalVMargin]*2) / [_textview lineHeight];
    [_screen destructivelySetScreenWidth:width height:height];
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionColumns: @(width),
                                                    iTermVariableKeySessionRows: @(height) }];

    [_textview setDataSource:_screen];
    [_textview setDelegate:self];
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

    if (@available(macOS 10.11, *)) {
        [self updateMetalDriver];
    }

    return YES;
}

- (BOOL)tryToAttachToServerWithProcessId:(pid_t)serverPid {
    if (![iTermAdvancedSettingsModel runJobsInServers]) {
        DLog(@"Failing to attach because run jobs in servers is off");
        return NO;
    }
    DLog(@"Try to attach...");
    if ([_shell tryToAttachToServerWithProcessId:serverPid]) {
        @synchronized(self) {
            _registered = YES;
        }
        DLog(@"Success, attached.");
        return YES;
    } else {
        DLog(@"Failed to attach");
        return NO;
    }
}

- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection {
    if ([iTermAdvancedSettingsModel runJobsInServers]) {
        DLog(@"Attaching to a server...");
        [_shell attachToServer:serverConnection];
        [_shell setSize:_screen.size];
        @synchronized(self) {
            _registered = YES;
        }
    } else {
        DLog(@"Can't attach to a server when runJobsInServers is off.");
    }
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
    self.lastResize = [NSDate timeIntervalSinceReferenceDate];
    DLog(@"Set session %@ to %@", self, VT100GridSizeDescription(size));
    [_screen setSize:size];
    if (!self.delegate || [self.delegate sessionShouldSendWindowSizeIOCTL:self]) {
        [_shell setSize:size];
    }
    [_textview clearHighlights:NO];
    [[_delegate realParentWindow] invalidateRestorableState];
    if (!_tailFindTimer &&
        [_delegate sessionBelongsToVisibleTab]) {
        [self beginTailFind];
    }
    if (@available(macOS 10.11, *)) {
        [self updateMetalDriver];
    }
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionColumns: @(_screen.width),
                                                    iTermVariableKeySessionRows: @(_screen.height) }];
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
            result -= iTermStatusBarHeight;
        }
        result -= [iTermAdvancedSettingsModel terminalVMargin] * 2;
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
        result -= [iTermAdvancedSettingsModel terminalMargin] * 2;
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

- (NSArray<NSString *> *)childJobNames {
    pid_t thePid = [_shell pid];

    [[iTermProcessCache sharedInstance] updateSynchronously];

    iTermProcessInfo *info = [[iTermProcessCache sharedInstance] processInfoForPid:thePid];
    if (!info) {
        return @[];
    }

    NSInteger levelsToSkip = 0;
    if ([info.name isEqualToString:@"login"]) {
        levelsToSkip++;
    }

    NSArray<iTermProcessInfo *> *allInfos = [info descendantsSkippingLevels:levelsToSkip];
    return [allInfos mapWithBlock:^id(iTermProcessInfo *info) {
        return info.name;
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
            for (NSString *childName in [self childJobNames]) {
                DLog(@"Check child %@", childName);
                if ([jobsThatDontRequirePrompting indexOfObject:childName] == NSNotFound) {
                    DLog(@"    not on the ignore list");
                    // This job is not in the ignore list.
                    [blockingJobs addObject:childName];
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
    [self.variablesScope setValue:self.sessionId forVariableNamed:iTermVariableKeySessionTermID];
}

- (void)triggerDidChangeNameTo:(NSString *)newName {
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionTriggerName: newName,
                                                    iTermVariableKeySessionAutoNameFormat: newName }];
}

- (void)didInitializeSessionWithName:(NSString *)name {
    [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionAutoNameFormat];
}

- (void)profileNameDidChangeTo:(NSString *)name {
    NSString *autoName = [self.variablesScope valueForVariableName:iTermVariableKeySessionAutoName] ?: name;
    const BOOL isChangeToLocalName = (self.isDivorced &&
                                      [_overriddenFields containsObject:KEY_NAME]);
    const BOOL haveAutoNameOverride = ([self.variablesScope valueForVariableName:iTermVariableKeySessionIconName] != nil ||
                                       [self.variablesScope valueForVariableName:iTermVariableKeySessionTriggerName] != nil);
    if (isChangeToLocalName || !haveAutoNameOverride) {
        // Profile name changed, local name not overridden, and no icon/trigger name to take precedence.
        autoName = name;
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
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionAutoNameFormat: autoName ?: [NSNull null],
                                                    iTermVariableKeySessionProfileName: profileName ?: [NSNull null] }];
}

- (void)profileDidChangeToProfileWithName:(NSString *)name {
    [self profileNameDidChangeTo:name];
}

- (void)computeArgvForCommand:(NSString *)command
                substitutions:(NSDictionary *)substitutions
                  synchronous:(BOOL)synchronous
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

- (void)computeEnvironmentForNewJobFromEnvironment:(NSDictionary *)environment
                                     substitutions:(NSDictionary *)substitutions
                                       synchronous:(BOOL)synchronous
                                        completion:(void (^)(NSDictionary *env))completion {
    DLog(@"computeEnvironmentForNewJobFromEnvironment:%@ substitutions:%@ synchronous:%@",
         environment, substitutions, @(synchronous));
    NSMutableDictionary *env = [[environment mutableCopy] autorelease];
    if (env[TERM_ENVNAME] == nil) {
        env[TERM_ENVNAME] = _termVariable;
    }
    if (env[COLORFGBG_ENVNAME] == nil && _colorFgBgVariable != nil) {
        env[COLORFGBG_ENVNAME] = _colorFgBgVariable;
    }

    DLog(@"Begin locale logic");
    if (!_profile[KEY_SET_LOCALE_VARS] ||
        [_profile[KEY_SET_LOCALE_VARS] boolValue]) {
        DLog(@"Setting locale vars...");
        NSString *lang = [self valueForLanguageEnvironmentVariable];
        if (lang) {
            DLog(@"set LANG=%@", lang);
            env[@"LANG"] = lang;
        } else if ([self shouldSetCtype]){
            DLog(@"should set ctype...");
            NSString *fallback = [iTermAdvancedSettingsModel fallbackLCCType];
            if (fallback.length) {
                env[@"LC_CTYPE"] = fallback;
            } else {
                // Try just the encoding by itself, which might work.
                NSString *encName = [self encodingName];
                DLog(@"See if encoding %@ is supported...", encName);
                if (encName && [self _localeIsSupported:encName]) {
                    DLog(@"Set LC_CTYPE=%@", encName);
                    env[@"LC_CTYPE"] = encName;
                }
            }
        }
    }
    if ([iTermAdvancedSettingsModel shouldSetLCTerminal]) {
        env[@"LC_TERMINAL"] = @"iTerm2";
        env[@"LC_TERMINAL_VERSION"] = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    }
    if (env[PWD_ENVNAME] == nil) {
        // Set "PWD"
        env[PWD_ENVNAME] = [PWD_ENVVALUE stringByExpandingTildeInPath];
        DLog(@"env[%@] was nil. Set it to home directory: %@", PWD_ENVNAME, env[PWD_ENVNAME]);
    }

    // Remove trailing slashes, unless the path is just "/"
    NSString *trimmed = [env[PWD_ENVNAME] stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    DLog(@"Trimmed pwd %@ is %@", env[PWD_ENVNAME], trimmed);
    if (trimmed.length == 0) {
        trimmed = @"/";
    }
    DLog(@"Set env[PWD] to trimmed value %@", trimmed);
    env[PWD_ENVNAME] = trimmed;

    NSString *itermId = [self sessionId];
    env[@"ITERM_SESSION_ID"] = itermId;
    env[@"TERM_PROGRAM_VERSION"] = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    env[@"TERM_SESSION_ID"] = itermId;
    env[@"TERM_PROGRAM"] = @"iTerm.app";
    env[@"COLORTERM"] = @"truecolor";

    if (_profile[KEY_NAME]) {
        env[@"ITERM_PROFILE"] = [_profile[KEY_NAME] stringByPerformingSubstitutions:substitutions];
    }
    completion(env);
}

- (void)startProgram:(NSString *)command
         environment:(NSDictionary *)environment
              isUTF8:(BOOL)isUTF8
       substitutions:(NSDictionary *)substitutions
         synchronous:(BOOL)synchronous
          completion:(void (^)(BOOL))completion {
    DLog(@"startProgram:%@ environment:%@ isUTF8:%@ substitutions:%@",
         command, environment, @(isUTF8), substitutions);

    self.program = command;
    self.environment = environment ?: @{};
    self.isUTF8 = isUTF8;
    self.substitutions = substitutions ?: @{};

    [self computeArgvForCommand:command substitutions:substitutions synchronous:synchronous completion:^(NSArray<NSString *> *argv) {
        DLog(@"argv=%@", argv);
        [self computeEnvironmentForNewJobFromEnvironment:environment ?: @{} substitutions:substitutions synchronous:synchronous completion:^(NSDictionary *env) {
            @synchronized(self) {
                _registered = YES;
            }
            [self fetchAutoLogFilenameSynchronously:synchronous
                                         completion:^(NSString * _Nonnull autoLogFilename) {
                [_shell launchWithPath:argv[0]
                             arguments:[argv subarrayFromIndex:1]
                           environment:env
                                 width:[_screen width]
                                height:[_screen height]
                                isUTF8:isUTF8
                           autologPath:autoLogFilename
                           synchronous:synchronous
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

- (void)sendInitialText {
    NSString *initialText = _profile[KEY_INITIAL_TEXT];
    if ([initialText length]) {
        [self writeTaskNoBroadcast:initialText];
        [self writeTaskNoBroadcast:@"\n"];
    }
}

- (void)launchProfileInCurrentTerminal:(Profile *)profile
                               withURL:(NSString *)url {
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    [[iTermController sharedInstance] launchBookmark:profile
                                          inTerminal:term
                                             withURL:url
                                    hotkeyWindowType:iTermHotkeyWindowTypeNone
                                             makeKey:NO
                                         canActivate:NO
                                  respectTabbingMode:NO
                                             command:nil
                                               block:nil
                                         synchronous:NO
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
    if ([[NSDate date] timeIntervalSinceDate:_creationDate] < [iTermAdvancedSettingsModel shortLivedSessionDuration]) {
        NSString* theName = [_profile objectForKey:KEY_NAME];
        NSString *guid = _profile[KEY_GUID];
        if (_originalProfile && [_originalProfile[KEY_GUID] length]) {
            // Divorced sessions should use the original session's GUID to determine
            // if a warning is appropriate.
            guid = _originalProfile[KEY_GUID];
        }
        NSString* theKey = [NSString stringWithFormat:@"NeverWarnAboutShortLivedSessions_%@", guid];
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
    assert(self.isRestartable);
    [self dismissAnnouncementWithIdentifier:kReopenSessionWarningIdentifier];
    if (_exited) {
        [self replaceTerminatedShellWithNewInstance];
    } else {
        _shouldRestart = YES;
        [_shell sendSignal:SIGKILL toServer:NO];
    }
}

// Terminate a replay session but not the live session
- (void)softTerminate {
    _liveSession = nil;
    [self terminate];
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
    } else if (self.tmuxMode == TMUX_GATEWAY) {
        [_tmuxController detach];
        [_tmuxGateway release];
        _tmuxGateway = nil;
    }
    BOOL undoable = (![self isTmuxClient] &&
                     !_shouldRestart &&
                     !_synthetic &&
                     ![[iTermController sharedInstance] applicationIsQuitting]);
    [_terminal.parser forceUnhookDCS:nil];
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
    _exited = YES;
    [_view retain];  // hardstop and revive will release this.
    if (undoable) {
        // TODO: executeTokens:bytesHandled: should queue up tokens to avoid a race condition.
        [self makeTerminationUndoable];
    } else {
        [self hardStop];
    }
    [[iTermSessionHotkeyController sharedInstance] removeSession:self];

    // final update of display
    [self updateDisplayBecause:@"terminate session"];

    [[NSNotificationCenter defaultCenter] postNotificationName:iTermSessionWillTerminateNotification
                                                        object:self];
    [_delegate removeSession:self];

    _colorMap.delegate = nil;

    _screen.delegate = nil;
    [_screen setTerminal:nil];
    _terminal.delegate = nil;
    if (_view.findDriverDelegate == self) {
        _view.findDriverDelegate = nil;
    }

    [_pasteHelper abort];

    [[_delegate realParentWindow] sessionDidTerminate:self];

    _delegate = nil;
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
    [_view release];  // This balances a retain in -terminate.
    // -taskWasDeregistered or the autorelease below will balance this retain.
    [self retain];
    // If _registered, -stop will cause -taskWasDeregistered to be called on a background thread,
    // which will release this object. Otherwise we autorelease now.
    @synchronized(self) {
        if (!_registered) {
            [self autorelease];
        }
    }
    [_shell stop];
    [_textview setDataSource:nil];
    [_textview setDelegate:nil];
    [_textview removeFromSuperview];
    self.textview = nil;
    if (@available(macOS 10.11, *)) {
        _metalGlue.textView = nil;
    }
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
            _exited = NO;
        }
        _textview.dataSource = _screen;
        _textview.delegate = self;
        _colorMap.delegate = _textview;
        _screen.delegate = self;
        _screen.terminal = _terminal;
        _terminal.delegate = _screen;
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
         canBroadcast:(BOOL)canBroadcast {
    const NSStringEncoding encoding = forceEncoding ? optionalEncoding : _terminal.encoding;
    if (gDebugLogging) {
        NSArray *stack = [NSThread callStackSymbols];
        DLog(@"writeTaskImpl session=%@ encoding=%@ forceEncoding=%@ canBroadcast=%@: called from %@",
             self, @(encoding), @(forceEncoding), @(canBroadcast), stack);
        DLog(@"writeTaskImpl string=%@", string);
    }
    if (string.length == 0) {
        DLog(@"String length is 0");
        // Abort early so the surrogate hack works.
        return;
    }
    if (canBroadcast && _terminal.sendReceiveMode && !self.isTmuxClient && !self.isTmuxGateway) {
        // Local echo. Only for broadcastable text to avoid printing passwords from the password manager.
        [_screen appendStringAtCursor:[string stringByMakingControlCharactersToPrintable]];
    }
    // check if we want to send this input to all the sessions
    if (canBroadcast && [[_delegate realParentWindow] broadcastInputToSession:self]) {
        // Ask the parent window to write to the other tasks.
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
        const char *bytes = data.bytes;
        for (NSUInteger i = 0; i < data.length; i++) {
            DLog(@"Write byte 0x%02x (%c)", (((int)bytes[i]) & 0xff), bytes[i]);
        }
        [_shell writeTask:data];
    }
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
    [self writeTaskNoBroadcast:string encoding:_terminal.encoding forceEncoding:NO];
}

- (void)writeTaskNoBroadcast:(NSString *)string
                    encoding:(NSStringEncoding)encoding
               forceEncoding:(BOOL)forceEncoding {
    if (self.tmuxMode == TMUX_CLIENT) {
        // tmux doesn't allow us to abuse the encoding, so this can cause the wrong thing to be
        // sent (e.g., in mouse reporting).
        [[_tmuxController gateway] sendKeys:string
                               toWindowPane:self.tmuxPane];
        return;
    }
    [self writeTaskImpl:string encoding:encoding forceEncoding:forceEncoding canBroadcast:NO];
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

- (void)writeLatin1EncodedData:(NSData *)data broadcastAllowed:(BOOL)broadcast {
    // `data` contains raw bytes we want to pass through. I believe Latin-1 is the only encoding that
    // won't perform any transformation when converting from data to string. This is needed because
    // sometimes the user wants to send particular bytes regardless of the encoding (e.g., the
    // "send hex codes" keybinding action, or certain mouse reporting modes that abuse encodings).
    // This won't work for non-UTF-8 data with tmux.
    NSString *string = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (broadcast) {
        [self writeTask:string encoding:NSISOLatin1StringEncoding forceEncoding:YES];
    } else {
        [self writeTaskNoBroadcast:string encoding:NSISOLatin1StringEncoding forceEncoding:YES];
    }
}

- (void)writeStringWithLatin1Encoding:(NSString *)string {
    [self writeTask:string encoding:NSISOLatin1StringEncoding forceEncoding:YES];
}

- (void)writeTask:(NSString *)string {
    [self writeTask:string encoding:_terminal.encoding forceEncoding:NO];
}

// If forceEncoding is YES then optionalEncoding will be used regardless of the session's preferred
// encoding. If it is NO then the preferred encoding is used. This is necessary because this method
// might send the string off to the window to get broadcast to other sessions which might have
// different encodings.
- (void)writeTask:(NSString *)string
         encoding:(NSStringEncoding)optionalEncoding
    forceEncoding:(BOOL)forceEncoding {
    NSStringEncoding encoding = forceEncoding ? optionalEncoding : _terminal.encoding;
    if (self.tmuxMode == TMUX_CLIENT) {
        [self setBell:NO];
        if ([[_delegate realParentWindow] broadcastInputToSession:self]) {
            [[_delegate realParentWindow] sendInputToAllSessions:string
                                                        encoding:optionalEncoding
                                                   forceEncoding:forceEncoding];
        } else {
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
    [self writeTaskImpl:string encoding:encoding forceEncoding:forceEncoding canBroadcast:YES];
}

- (void)taskWasDeregistered {
    DLog(@"taskWasDeregistered");
    @synchronized(self) {
        _registered = NO;
    }
    // This is called on the background thread. After this is called, we won't get any more calls
    // on the background thread and it is safe for us to be dealloc'ed. This pairs with the retain
    // in -hardStop. For sanity's sake, ensure dealloc gets called on the main thread.
    [self performSelectorOnMainThread:@selector(release) withObject:nil waitUntilDone:NO];
}

// This is run in PTYTask's thread. It parses the input here and then queues an async task to run
// in the main thread to execute the parsed tokens.
- (void)threadedReadTask:(char *)buffer length:(int)length {
    // Pass the input stream to the parser.
    [_terminal.parser putStreamData:buffer length:length];

    // Parse the input stream into an array of tokens.
    CVector vector;
    CVectorCreate(&vector, 100);
    [_terminal.parser addParsedTokensToVector:&vector];

    if (CVectorCount(&vector) == 0) {
        CVectorDestroy(&vector);
        return;
    }

    @synchronized (self) {
        [_echoProbe updateEchoProbeStateWithTokenCVector:&vector];
    }

    // This limits the number of outstanding execution blocks to prevent the main thread from
    // getting bogged down.
    dispatch_semaphore_wait(_executionSemaphore, DISPATCH_TIME_FOREVER);

    [self retain];
    dispatch_retain(_executionSemaphore);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_useAdaptiveFrameRate) {
            [_throughputEstimator addByteCount:length];
        }
        [self executeTokens:&vector bytesHandled:length];

        // Unblock the background thread; if it's ready, it can send the main thread more tokens
        // now.
        dispatch_semaphore_signal(_executionSemaphore);
        dispatch_release(_executionSemaphore);
        [self release];
    });
}

- (void)synchronousReadTask:(NSString *)string {
    NSData *data = [string dataUsingEncoding:self.encoding];
    [_terminal.parser putStreamData:data.bytes length:data.length];
    CVector vector;
    CVectorCreate(&vector, 100);
    [_terminal.parser addParsedTokensToVector:&vector];
    if (CVectorCount(&vector) == 0) {
        CVectorDestroy(&vector);
        return;
    }
    [self executeTokens:&vector bytesHandled:data.length];
}

- (BOOL)shouldExecuteToken {
    return (!_exited &&
            _terminal &&
            (self.tmuxMode == TMUX_GATEWAY || ![_shell hasMuteCoprocess]) &&
            !_suppressAllOutput);
}

- (void)recycleQueuedTokens {
    NSArray<VT100Token *> *tokens = [_queuedTokens retain];
    [_queuedTokens autorelease];
    _queuedTokens = [[NSMutableArray alloc] init];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        for (VT100Token *token in tokens) {
            [token release];
        }
        [tokens release];
    });
}

- (void)executeTokens:(const CVector *)vector bytesHandled:(int)length {
    STOPWATCH_START(executing);
    DLog(@"Session %@ begins executing tokens", self);
    int n = CVectorCount(vector);

    if (_shell.paused || _copyModeHandler.enabled) {
        // Session was closed or is not accepting new tokens because it's in copy mode. These can
        // be handled later (unclose or exit copy mode), so queue them up.
        for (int i = 0; i < n; i++) {
            [_queuedTokens addObject:CVectorGetObject(vector, i)];
        }
        CVectorDestroy(vector);
        return;
    } else if (_queuedTokens.count) {
        // A closed session was just un-closed. Execute queued up tokens.
        for (VT100Token *token in _queuedTokens) {
            if (![self shouldExecuteToken]) {
                break;
            }
            [_terminal executeToken:token];
        }
        [self recycleQueuedTokens];
    }

    for (int i = 0; i < n; i++) {
        if (![self shouldExecuteToken]) {
            break;
        }

        VT100Token *token = CVectorGetObject(vector, i);
        DLog(@"Execute token %@ cursor=(%d, %d)", token, _screen.cursorX - 1, _screen.cursorY - 1);
        [_terminal executeToken:token];
    }

    [self finishedHandlingNewOutputOfLength:length];

    // When busy, we spend a lot of time performing recycleObject, so farm it
    // off to a background thread.
    CVector temp = *vector;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        for (int i = 0; i < n; i++) {
            VT100Token *token = CVectorGetObject(&temp, i);
            [token release];
        }
        CVectorDestroy(&temp);
    })
    STOPWATCH_LAP(executing);
}

- (BOOL)haveResizedRecently {
    const NSTimeInterval kGracePeriodAfterResize = 0.25;
    return [NSDate timeIntervalSinceReferenceDate] < _lastResize + kGracePeriodAfterResize;
}

- (void)finishedHandlingNewOutputOfLength:(int)length {
    DLog(@"Session %@ is processing", _nameController.presentationSessionTitle);
    if (![self haveResizedRecently]) {
        _lastOutputIgnoringOutputAfterResizing = [NSDate timeIntervalSinceReferenceDate];
    }
    _newOutput = YES;

    // Make sure the screen gets redrawn soonish
    self.active = YES;

    if (self.shell.pid > 0 || [[[self variablesScope] valueForVariableName:@"jobName"] length] > 0) {
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
    }
}

- (void)checkTriggers {
    if (_triggerLineNumber == -1) {
        return;
    }
    long long startAbsLineNumber;
    iTermStringLine *stringLine = [_screen stringLineAsStringAtAbsoluteLineNumber:_triggerLineNumber
                                                                         startPtr:&startAbsLineNumber];
    [self checkTriggersOnPartialLine:NO
                          stringLine:stringLine
                          lineNumber:startAbsLineNumber];
}

- (void)checkPartialLineTriggers {
    if (_triggerLineNumber == -1) {
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastPartialLineTriggerCheck < kMinimumPartialLineTriggerCheckInterval) {
        return;
    }
    _lastPartialLineTriggerCheck = now;
    long long startAbsLineNumber;
    iTermStringLine *stringLine = [_screen stringLineAsStringAtAbsoluteLineNumber:_triggerLineNumber
                                                                         startPtr:&startAbsLineNumber];
    [self checkTriggersOnPartialLine:YES
                          stringLine:stringLine
                          lineNumber:startAbsLineNumber];
}

- (void)checkTriggersOnPartialLine:(BOOL)partial
                        stringLine:(iTermStringLine *)stringLine
                        lineNumber:(long long)startAbsLineNumber {
    // If the trigger causes the session to get released, don't crash.
    [[self retain] autorelease];

    // If a trigger changes the current profile then _triggers gets released and we should stop
    // processing triggers. This can happen with automatic profile switching.
    NSArray<Trigger *> *triggers = [[_triggers retain] autorelease];

    for (Trigger *trigger in triggers) {
        BOOL stop = [trigger tryString:stringLine
                             inSession:self
                           partialLine:partial
                            lineNumber:startAbsLineNumber
                      useInterpolation:_triggerParametersUseInterpolatedStrings];
        if (stop || _exited || (_triggers != triggers)) {
            break;
        }
    }
}

- (void)appendStringToTriggerLine:(NSString *)s {
    if (_triggerLineNumber == -1) {
        _triggerLineNumber = _screen.numberOfScrollbackLines + _screen.cursorY - 1 + _screen.totalScrollbackOverflow;
    }

    // We used to build up the string so you could write triggers that included bells. That doesn't
    // really make sense, especially in the new model, but it's so useful to be able to customize
    // the bell that I'll add this special case.
    if ([s isEqualToString:@"\a"]) {
        iTermStringLine *stringLine = [iTermStringLine stringLineWithString:s];
        [self checkTriggersOnPartialLine:YES stringLine:stringLine lineNumber:_triggerLineNumber];
    }
}

- (void)clearTriggerLine {
    if ([_triggers count]) {
        [self checkTriggers];
        _triggerLineNumber = -1;
    }
}

- (void)appendBrokenPipeMessage:(NSString *)message {
    if (_screen.cursorX != 1) {
        [_screen crlf];
    }
    screen_char_t savedFgColor = [_terminal foregroundColorCode];
    screen_char_t savedBgColor = [_terminal backgroundColorCode];
    // This color matches the color used in BrokenPipeDivider.png.
    [_terminal setForeground24BitColor:[NSColor colorWithCalibratedRed:248.0/255.0
                                                                 green:79.0/255.0
                                                                  blue:27.0/255.0
                                                                 alpha:1]];
    [_terminal setBackgroundColor:ALTSEM_DEFAULT
               alternateSemantics:YES];
    int width = (_screen.width - message.length) / 2;
    const NSEdgeInsets zeroInset = { 0 };
    if (width > 0) {
        [_screen appendImageAtCursorWithName:@"BrokenPipeDivider"
                                       width:width
                                       units:kVT100TerminalUnitsCells
                                      height:1
                                       units:kVT100TerminalUnitsCells
                         preserveAspectRatio:NO
                                       inset:zeroInset
                                       image:[NSImage it_imageNamed:@"BrokenPipeDivider" forClass:self.class]
                                        data:nil];
    }
    [_screen appendStringAtCursor:message];
    [_screen appendStringAtCursor:@" "];
    if (width > 0) {
        [_screen appendImageAtCursorWithName:@"BrokenPipeDivider"
                                       width:(_screen.width - _screen.cursorX + 1)
                                       units:kVT100TerminalUnitsCells
                                      height:1
                                       units:kVT100TerminalUnitsCells
                         preserveAspectRatio:NO
                                       inset:zeroInset
                                       image:[NSImage it_imageNamed:@"BrokenPipeDivider" forClass:self.class]
                                        data:nil];
    }
    [_screen crlf];
    [_terminal setForegroundColor:savedFgColor.foregroundColor
               alternateSemantics:savedFgColor.foregroundColorMode == ColorModeAlternate];
    [_terminal setBackgroundColor:savedBgColor.backgroundColor
               alternateSemantics:savedBgColor.backgroundColorMode == ColorModeAlternate];
}

// This is called in the main thread when coprocesses write to a tmux client.
- (void)writeForCoprocessOnlyTask:(NSData *)data {
    // The if statement is just a sanity check.
    if (self.tmuxMode == TMUX_CLIENT) {
        NSString *string = [[[NSString alloc] initWithData:data encoding:self.encoding] autorelease];
        [self writeTask:string];
    }
}

- (void)threadedTaskBrokenPipe
{
    DLog(@"threaded task broken pipe");
    // Put the call to brokenPipe in the same queue as executeTokens:bytesHandled: to avoid a race.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self brokenPipe];
    });
}

- (void)taskDiedImmediately {
    // Let initial creation finish, then report the broken pipe. This happens if the file descriptor
    // server dies immediately.
    [self performSelector:@selector(brokenPipe) withObject:nil afterDelay:0];
}

- (void)taskDidChangeTTY:(PTYTask *)task {
    [self.variablesScope setValue:task.tty forVariableNamed:iTermVariableKeySessionTTY];
}

// Called when the file descriptor closes. If -terminate was already called this does nothing.
// Otherwise, you can call replaceTerminatedShellWithNewInstance after this to restart the session.
- (void)brokenPipe {
    DLog(@"  brokenPipe");
    if (_exited) {
        DLog(@"  brokenPipe: Already exited");
        return;
    }
    [_shell killServerIfRunning];
    if ([self shouldPostUserNotification] &&
        [iTermProfilePreferences boolForKey:KEY_SEND_SESSION_ENDED_ALERT inProfile:self.profile]) {
        [[iTermNotificationController sharedInstance] notify:@"Session Ended"
                                             withDescription:[NSString stringWithFormat:@"Session \"%@\" in tab #%d just terminated.",
                                                              [self name],
                                                              [_delegate tabNumber]]];
    }

    DLog(@"  brokenPipe: set exited = YES");
    _exited = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:PTYSessionTerminatedNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    [_delegate updateLabelAttributes];

    if (_shouldRestart) {
        [_terminal resetByUserRequest:NO];
        [self appendBrokenPipeMessage:@"Session Restarted"];
        [self replaceTerminatedShellWithNewInstance];
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
    [self appendBrokenPipeMessage:@"Broken Pipe"];
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
    [self updateDisplayBecause:@"broken pipe"];
}

- (void)queueRestartSessionAnnouncement {
    if ([iTermAdvancedSettingsModel suppressRestartAnnouncement]) {
        return;
    }
    if (_shortLivedSingleUse) {
        return;
    }
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:@"Session ended (broken pipe). Restart it?"
                                                         style:kiTermAnnouncementViewStyleQuestion
                                                   withActions:@[ @"Restart", @"Don’t Ask Again" ]
                                                    completion:^(int selection) {
                                                        switch (selection) {
                                                            case -2:  // Dismiss programmatically
                                                                break;

                                                            case -1: // No
                                                                break;

                                                            case 0: // Yes
                                                                [self replaceTerminatedShellWithNewInstance];
                                                                break;

                                                            case 1: // Don't ask again
                                                                [iTermAdvancedSettingsModel setSuppressRestartAnnouncement:YES];
                                                        }
                                                    }];
    [self queueAnnouncement:announcement identifier:kReopenSessionWarningIdentifier];
}

- (BOOL)isRestartable {
    return _program != nil;
}

- (void)maybeReplaceTerminatedShellWithNewInstance {
    // The check for screen.terminal is because after -terminate is called, it is no longer safe
    // to replace the terminated shell with a new instance unless you first do -revive. When
    // the terminal is nil you can't write text to the screen.
    if (_screen.terminal && self.isRestartable && _exited) {
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
    _exited = NO;
    [_shell release];
    _shell = [[PTYTask alloc] init];
    [_shell setDelegate:self];
    [_shell setSize:_screen.size];
    [self startProgram:_program
           environment:_environment
                isUTF8:_isUTF8
         substitutions:_substitutions
           synchronous:YES
            completion:nil];
    [self dismissAnnouncementWithIdentifier:kReopenSessionWarningIdentifier];
    [self removeAnnouncementWithIdentifier:kReopenSessionWarningIdentifier];
    DLog(@"  replaceTerminatedShellWithNewInstance: return with terminal=%@", _screen.terminal);
}

- (NSSize)idealScrollViewSizeWithStyle:(NSScrollerStyle)scrollerStyle {
    NSSize innerSize = NSMakeSize([_screen width] * [_textview charWidth] + [iTermAdvancedSettingsModel terminalMargin] * 2,
                                  [_screen height] * [_textview lineHeight] + [iTermAdvancedSettingsModel terminalVMargin] * 2);
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

- (int)_keyBindingActionForEvent:(NSEvent*)event
{
    unsigned int modflag;
    NSString *unmodkeystr;
    unichar unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;

    modflag = [event it_modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];
    return keyBindingAction;
}

- (BOOL)hasTextSendingKeyMappingForEvent:(NSEvent*)event
{
    int keyBindingAction = [self _keyBindingActionForEvent:event];
    switch (keyBindingAction) {
        case KEY_ACTION_ESCAPE_SEQUENCE:
        case KEY_ACTION_HEX_CODE:
        case KEY_ACTION_TEXT:
        case KEY_ACTION_VIM_TEXT:
        case KEY_ACTION_RUN_COPROCESS:
        case KEY_ACTION_IGNORE:
        case KEY_ACTION_SEND_C_H_BACKSPACE:
        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            return YES;
    }
    return NO;
}

- (BOOL)_askAboutOutdatedKeyMappings
{
    NSNumber* n = [_profile objectForKey:KEY_ASK_ABOUT_OUTDATED_KEYMAPS];
    if (!n) {
        n = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:kAskAboutOutdatedKeyMappingKeyFormat,
                                                                 [_profile objectForKey:KEY_GUID]]];
        if (!n && [_profile objectForKey:KEY_ORIGINAL_GUID]) {
            n = [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:kAskAboutOutdatedKeyMappingKeyFormat,
                                                                     [_profile objectForKey:KEY_ORIGINAL_GUID]]];
        }
    }
    return n ? [n boolValue] : YES;
}

- (void)_removeOutdatedKeyMapping
{
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:_profile];
    [iTermKeyBindingMgr removeMappingWithCode:NSLeftArrowFunctionKey
                                    modifiers:NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagNumericPad
                                   inBookmark:temp];
    [iTermKeyBindingMgr removeMappingWithCode:NSRightArrowFunctionKey
                                    modifiers:NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagNumericPad
                                   inBookmark:temp];

    ProfileModel* model;
    if (_isDivorced) {
        model = [ProfileModel sessionsInstance];
    } else {
        model = [ProfileModel sharedInstance];
    }
    [model setBookmark:temp withGuid:[temp objectForKey:KEY_GUID]];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
    [[iTermController sharedInstance] reloadAllBookmarks];
}

- (void)_setKeepOutdatedKeyMapping
{
    ProfileModel* model;
    if (_isDivorced) {
        model = [ProfileModel sessionsInstance];
    } else {
        model = [ProfileModel sharedInstance];
    }
    [model setObject:[NSNumber numberWithBool:NO]
              forKey:KEY_ASK_ABOUT_OUTDATED_KEYMAPS
          inBookmark:_profile];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO]
                                              forKey:[NSString stringWithFormat:kAskAboutOutdatedKeyMappingKeyFormat,
                                                      [_profile objectForKey:KEY_GUID]]];
    if ([_profile objectForKey:KEY_ORIGINAL_GUID]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO]
                                                  forKey:[NSString stringWithFormat:kAskAboutOutdatedKeyMappingKeyFormat,
                                                          [_profile objectForKey:KEY_ORIGINAL_GUID]]];
    }
    [[iTermController sharedInstance] reloadAllBookmarks];
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
    for (NSMenuItem* item in [menu itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if ([item hasSubmenu]) {
            if ([PTYSession _recursiveSelectMenuItemWithTitle:title identifier:identifier inMenu:[item submenu]]) {
                return YES;
            }
        } else if (item.identifier && [identifier isEqualToString:item.identifier]) {
            [NSApp sendAction:[item action]
                           to:[item target]
                         from:item];
            return YES;
        } else if (!identifier && [title isEqualToString:[item title]]) {
            [NSApp sendAction:[item action]
                           to:[item target]
                         from:item];
            return YES;
        }
    }
    return NO;
}

+ (BOOL)handleShortcutWithoutTerminal:(NSEvent*)event
{
    unsigned int modflag;
    NSString *unmodkeystr;
    unichar unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;

    modflag = [event it_modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[iTermKeyBindingMgr globalKeyMap]];

    return [PTYSession performKeyBindingAction:keyBindingAction
                                     parameter:keyBindingText
                                         event:event];
}

+ (void)selectMenuItemWithSelector:(SEL)theSelector {
    if (![self _recursiveSelectMenuWithSelector:theSelector inMenu:[NSApp mainMenu]]) {
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
    [self writeLatin1EncodedData:[_terminal.output keyArrowUp:0] broadcastAllowed:YES];
}

- (void)moveDown:(id)sender {
    [self writeLatin1EncodedData:[_terminal.output keyArrowDown:0] broadcastAllowed:YES];
}

- (void)moveLeft:(id)sender {
    [self writeLatin1EncodedData:[_terminal.output keyArrowLeft:0] broadcastAllowed:YES];
}

- (void)moveRight:(id)sender {
    [self writeLatin1EncodedData:[_terminal.output keyArrowRight:0] broadcastAllowed:YES];
}

- (void)pageUp:(id)sender {
    [self writeLatin1EncodedData:[_terminal.output keyPageUp:0] broadcastAllowed:YES];
}

- (void)pageDown:(id)sender {
    [self writeLatin1EncodedData:[_terminal.output keyPageDown:0] broadcastAllowed:YES];
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

- (void)pasteString:(NSString *)aString
{
    [self pasteString:aString flags:0];
}

- (void)deleteBackward:(id)sender {
    unsigned char p = 0x08; // Ctrl+H

    [self writeLatin1EncodedData:[NSData dataWithBytes:&p length:1] broadcastAllowed:YES];
}

- (void)deleteForward:(id)sender {
    unsigned char p = 0x7F; // DEL

    [self writeLatin1EncodedData:[NSData dataWithBytes:&p length:1] broadcastAllowed:YES];
}

- (PTYScroller *)textViewVerticalScroller {
    return (PTYScroller *)[_view.scrollview verticalScroller];
}

- (BOOL)textViewHasCoprocess {
    return [_shell hasCoprocess];
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
    iTermSemanticHistoryController *semanticHistoryController = _textview.semanticHistoryController;
    int lineNumber;
    NSArray *subSelections = _textview.selection.allSubSelections;
    if ([subSelections count]) {
        iTermSubSelection *firstSub = subSelections[0];
        lineNumber = firstSub.range.coordRange.start.y;
    } else {
        lineNumber = _textview.selection.liveRange.coordRange.start.y;
    }

    // TODO: Figure out if this is a remote host and download/open if that's the case.
    NSString *workingDirectory = [_screen workingDirectoryOnLine:lineNumber];
    NSString *selection = [_textview selectedText];
    if (!selection.length) {
        NSBeep();
        return;
    }

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

- (void)tryOpenStringAsURL:(NSString *)selection {
    // Try to open it as a URL.
    NSURL *url =
        [NSURL URLWithUserSuppliedString:[selection stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

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
                                                                  [self name],
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
        NSString* key = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i];
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

- (void)loadInitialColorTable
{
    int i;
    for (i = 16; i < 256; i++) {
        NSColor *theColor = [NSColor colorForAnsi256ColorIndex:i];
        [_colorMap setColor:theColor forKey:kColorMap8bitBase + i];
    }
    _textview.highlightCursorLine = [iTermProfilePreferences boolForKey:KEY_USE_CURSOR_GUIDE
                                                              inProfile:_profile];
}

- (NSColor *)tabColorInProfile:(NSDictionary *)profile
{
    NSColor *tabColor = nil;
    if ([profile[KEY_USE_TAB_COLOR] boolValue]) {
        tabColor = [ITAddressBookMgr decodeColor:profile[KEY_TAB_COLOR]];
    }
    return tabColor;
}

- (void)setColorsFromPresetNamed:(NSString *)presetName {
    iTermColorPreset *settings = [iTermColorPresets presetWithName:presetName];
    if (!settings) {
        return;
    }
    for (NSString *colorName in [ProfileModel colorKeys]) {
        iTermColorDictionary *colorDict = [settings iterm_presetColorWithName:colorName];
        if (colorDict) {
            [self setSessionSpecificProfileValues:@{ colorName: colorDict }];
        }
    }
}

- (void)sharedProfileDidChange
{
    NSDictionary *updatedProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:_originalProfile[KEY_GUID]];
    if (!updatedProfile) {
        return;
    }
    if (!_isDivorced) {
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
        DLog(@"%@ is no longer overridden because shared profile now matches session profile value of %@", key, temp[key]);
        [_overriddenFields removeObject:key];
    }
    DLog(@"After shared profile change overridden keys are: %@", _overriddenFields);

    // Update saved state.
    [[ProfileModel sessionsInstance] setBookmark:temp withGuid:temp[KEY_GUID]];
    [self setPreferencesFromAddressBookEntry:temp];
    [self setProfile:temp];
}

- (void)sessionProfileDidChange
{
    if (!_isDivorced) {
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
            DLog(@"%@ is now overridden because %@ != %@", aKey, newSessionValue, sharedValue);
            [_overriddenFields addObject:aKey];
        } else if (isEqual && isOverridden) {
            DLog(@"%@ is no longer overridden because %@ == %@", aKey, newSessionValue, sharedValue);
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

    if (_isDivorced) {
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

- (void)setPreferencesFromAddressBookEntry:(NSDictionary *)aePrefs {
    int i;
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

    BOOL useUnderline = [iTermProfilePreferences boolForKey:KEY_USE_UNDERLINE_COLOR inProfile:aDict];

    NSDictionary *keyMap = @{ @(kColorMapForeground): KEY_FOREGROUND_COLOR,
                              @(kColorMapBackground): KEY_BACKGROUND_COLOR,
                              @(kColorMapSelection): KEY_SELECTION_COLOR,
                              @(kColorMapSelectedText): KEY_SELECTED_TEXT_COLOR,
                              @(kColorMapBold): KEY_BOLD_COLOR,
                              @(kColorMapLink): KEY_LINK_COLOR,
                              @(kColorMapCursor): KEY_CURSOR_COLOR,
                              @(kColorMapCursorText): KEY_CURSOR_TEXT_COLOR,
                              @(kColorMapUnderline): (useUnderline ? KEY_UNDERLINE_COLOR : [NSNull null])
                              };

    for (NSNumber *colorKey in keyMap) {
        NSString *profileKey = keyMap[colorKey];

        NSColor *theColor = nil;
        if ([profileKey isKindOfClass:[NSString class]]) {
            theColor = [[iTermProfilePreferences objectForKey:profileKey
                                                    inProfile:aDict] colorValue];
        }

        [_colorMap setColor:theColor forKey:[colorKey intValue]];
    }

    self.cursorGuideColor = [[iTermProfilePreferences objectForKey:KEY_CURSOR_GUIDE_COLOR
                                                         inProfile:aDict] colorValueForKey:KEY_CURSOR_GUIDE_COLOR];
    if (!_cursorGuideSettingHasChanged) {
        _textview.highlightCursorLine = [iTermProfilePreferences boolForKey:KEY_USE_CURSOR_GUIDE
                                                                  inProfile:aDict];
    }

    for (i = 0; i < 16; i++) {
        NSString *profileKey = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i];
        NSColor *theColor = [ITAddressBookMgr decodeColor:aDict[profileKey]];
        [_colorMap setColor:theColor forKey:kColorMap8bitBase + i];
    }

    [self setSmartCursorColor:[iTermProfilePreferences boolForKey:KEY_SMART_CURSOR_COLOR
                                                        inProfile:aDict]];

    [self setMinimumContrast:[iTermProfilePreferences floatForKey:KEY_MINIMUM_CONTRAST
                                                        inProfile:aDict]];

    _colorMap.mutingAmount = [iTermProfilePreferences floatForKey:KEY_CURSOR_BOOST
                                                        inProfile:aDict];

    // background image
    [self setBackgroundImagePath:aDict[KEY_BACKGROUND_IMAGE_LOCATION]];
    [self setBackgroundImageMode:[iTermProfilePreferences unsignedIntegerForKey:KEY_BACKGROUND_IMAGE_MODE
                                                                      inProfile:aDict]];

    // Color scheme
    // ansiColorsMatchingForeground:andBackground:inBookmark does an equality comparison, so
    // iTermProfilePreferences is not used here.
    [self setColorFgBgVariable:[self ansiColorsMatchingForeground:aDict[KEY_FOREGROUND_COLOR]
                                                    andBackground:aDict[KEY_BACKGROUND_COLOR]
                                                       inBookmark:aDict]];

    // transparency
    [self setTransparency:[iTermProfilePreferences floatForKey:KEY_TRANSPARENCY inProfile:aDict]];
    [self setBlend:[iTermProfilePreferences floatForKey:KEY_BLEND inProfile:aDict]];
    [self setTransparencyAffectsOnlyDefaultBackgroundColor:[iTermProfilePreferences floatForKey:KEY_TRANSPARENCY_AFFECTS_ONLY_DEFAULT_BACKGROUND_COLOR inProfile:aDict]];

    // bold
    [self setUseBoldFont:[iTermProfilePreferences boolForKey:KEY_USE_BOLD_FONT
                                                   inProfile:aDict]];
    self.thinStrokes = [iTermProfilePreferences intForKey:KEY_THIN_STROKES inProfile:aDict];

    self.asciiLigatures = [iTermProfilePreferences boolForKey:KEY_ASCII_LIGATURES inProfile:aDict];
    self.nonAsciiLigatures = [iTermProfilePreferences boolForKey:KEY_NON_ASCII_LIGATURES inProfile:aDict];

    [_textview setUseBoldColor:[iTermProfilePreferences boolForKey:KEY_USE_BOLD_COLOR
                                                          inProfile:aDict]];

    // Italic - this default has changed from NO to YES as of 1/30/15
    [self setUseItalicFont:[iTermProfilePreferences boolForKey:KEY_USE_ITALIC_FONT inProfile:aDict]];

    // Set up the rest of the preferences
    [_screen setAudibleBell:![iTermProfilePreferences boolForKey:KEY_SILENCE_BELL inProfile:aDict]];
    [_screen setShowBellIndicator:[iTermProfilePreferences boolForKey:KEY_VISUAL_BELL inProfile:aDict]];
    [_screen setFlashBell:[iTermProfilePreferences boolForKey:KEY_FLASHING_BELL inProfile:aDict]];
    [_screen setPostUserNotifications:[iTermProfilePreferences boolForKey:KEY_BOOKMARK_USER_NOTIFICATIONS inProfile:aDict]];
    [_textview setBlinkAllowed:[iTermProfilePreferences boolForKey:KEY_BLINK_ALLOWED inProfile:aDict]];
    [_screen setCursorBlinks:[iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:aDict]];
    [_textview setBlinkingCursor:[iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:aDict]];
    [_textview setCursorType:[iTermProfilePreferences intForKey:KEY_CURSOR_TYPE inProfile:aDict]];

    PTYTab* currentTab = [[_delegate parentWindow] currentTab];
    if (currentTab == nil || [_delegate sessionBelongsToVisibleTab]) {
        [_delegate recheckBlur];
    }
    [_triggers release];
    _triggers = [[NSMutableArray alloc] init];
    for (NSDictionary *triggerDict in aDict[KEY_TRIGGERS]) {
        Trigger *trigger = [Trigger triggerFromDict:triggerDict];
        if (trigger) {
            [_triggers addObject:trigger];
        }
    }
    _triggerParametersUseInterpolatedStrings = [iTermProfilePreferences boolForKey:KEY_TRIGGERS_USE_INTERPOLATED_STRINGS
                                                                         inProfile:aDict];

    [_textview setSmartSelectionRules:aDict[KEY_SMART_SELECTION_RULES]];
    [_textview setSemanticHistoryPrefs:aDict[KEY_SEMANTIC_HISTORY]];
    [_textview setUseNonAsciiFont:[iTermProfilePreferences boolForKey:KEY_USE_NONASCII_FONT
                                                            inProfile:aDict]];
    [_textview setAntiAlias:[iTermProfilePreferences boolForKey:KEY_ASCII_ANTI_ALIASED
                                                      inProfile:aDict]
                   nonAscii:[iTermProfilePreferences boolForKey:KEY_NONASCII_ANTI_ALIASED
                                                      inProfile:aDict]];
    [_textview setUseNativePowerlineGlyphs:[iTermProfilePreferences boolForKey:KEY_POWERLINE inProfile:aDict]];
    [self setEncoding:[iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:aDict]];
    [self setTermVariable:[iTermProfilePreferences stringForKey:KEY_TERMINAL_TYPE inProfile:aDict]];
    [_terminal setAnswerBackString:[iTermProfilePreferences stringForKey:KEY_ANSWERBACK_STRING inProfile:aDict]];
    [self setAntiIdleCode:[iTermProfilePreferences intForKey:KEY_IDLE_CODE inProfile:aDict]];
    [self setAntiIdlePeriod:[iTermProfilePreferences doubleForKey:KEY_IDLE_PERIOD inProfile:aDict]];
    [self setAntiIdle:[iTermProfilePreferences boolForKey:KEY_SEND_CODE_WHEN_IDLE inProfile:aDict]];
    self.endAction = [iTermProfilePreferences unsignedIntegerForKey:KEY_SESSION_END_ACTION inProfile:aDict];
    _screen.normalization = [iTermProfilePreferences integerForKey:KEY_UNICODE_NORMALIZATION
                                                         inProfile:aDict];
    [self setTreatAmbiguousWidthAsDoubleWidth:[iTermProfilePreferences boolForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH
                                                                        inProfile:aDict]];
    [self setXtermMouseReporting:[iTermProfilePreferences boolForKey:KEY_XTERM_MOUSE_REPORTING
                                                           inProfile:aDict]];
    [self setXtermMouseReportingAllowMouseWheel:[iTermProfilePreferences boolForKey:KEY_XTERM_MOUSE_REPORTING_ALLOW_MOUSE_WHEEL
                                                                          inProfile:aDict]];
    [self setUnicodeVersion:[iTermProfilePreferences integerForKey:KEY_UNICODE_VERSION
                                                         inProfile:aDict]];
    [_terminal setDisableSmcupRmcup:[iTermProfilePreferences boolForKey:KEY_DISABLE_SMCUP_RMCUP
                                                              inProfile:aDict]];
    [_screen setAllowTitleReporting:[iTermProfilePreferences boolForKey:KEY_ALLOW_TITLE_REPORTING
                                                              inProfile:aDict]];
    const BOOL didAllowPasteBracketing = _terminal.allowPasteBracketing;
    [_terminal setAllowPasteBracketing:[iTermProfilePreferences boolForKey:KEY_ALLOW_PASTE_BRACKETING
                                                                 inProfile:aDict]];
    if (didAllowPasteBracketing && !_terminal.allowPasteBracketing) {
        // If the user flips the setting off, disable bracketed paste.
        _terminal.bracketedPasteMode = NO;
    }
    [_terminal setAllowKeypadMode:[iTermProfilePreferences boolForKey:KEY_APPLICATION_KEYPAD_ALLOWED
                                                            inProfile:aDict]];
    [_screen setUnlimitedScrollback:[iTermProfilePreferences boolForKey:KEY_UNLIMITED_SCROLLBACK
                                                              inProfile:aDict]];
    [_screen setMaxScrollbackLines:[iTermProfilePreferences intForKey:KEY_SCROLLBACK_LINES
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
        [_statusBarViewController release];
        _statusBarViewController = nil;
        [self invalidateStatusBar];
    }
    _tmuxStatusBarMonitor.active = [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:aDict];
    _screen.appendToScrollbackWithStatusBar = [iTermProfilePreferences boolForKey:KEY_SCROLLBACK_WITH_STATUS_BAR
                                                                        inProfile:aDict];
    [_badgeFontName release];
    _badgeFontName = [[iTermProfilePreferences stringForKey:KEY_BADGE_FONT inProfile:aDict] copy];

    self.badgeFormat = [iTermProfilePreferences stringForKey:KEY_BADGE_FORMAT inProfile:aDict];
    // forces the badge to update
    _textview.badgeLabel = @"";
    [self updateBadgeLabel];
    [self setFont:[ITAddressBookMgr fontWithDesc:aDict[KEY_NORMAL_FONT]]
        nonAsciiFont:[ITAddressBookMgr fontWithDesc:aDict[KEY_NON_ASCII_FONT]]
        horizontalSpacing:[iTermProfilePreferences floatForKey:KEY_HORIZONTAL_SPACING inProfile:aDict]
        verticalSpacing:[iTermProfilePreferences floatForKey:KEY_VERTICAL_SPACING inProfile:aDict]];
    [_screen setSaveToScrollbackInAlternateScreen:[iTermProfilePreferences boolForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN
                                                                            inProfile:aDict]];

    NSDictionary *shortcutDictionary = [iTermProfilePreferences objectForKey:KEY_SESSION_HOTKEY inProfile:aDict];
    iTermShortcut *shortcut = [iTermShortcut shortcutWithDictionary:shortcutDictionary];
    [[iTermSessionHotkeyController sharedInstance] setShortcut:shortcut
                                                    forSession:self];
    [[_delegate realParentWindow] invalidateRestorableState];

    [self setUseLibTickit:[iTermProfilePreferences boolForKey:KEY_USE_LIBTICKIT_PROTOCOL inProfile:aDict]];
    if (self.isTmuxClient) {
        NSDictionary *tabColorDict = [iTermProfilePreferences objectForKey:KEY_TAB_COLOR inProfile:aDict];
        if (![iTermProfilePreferences boolForKey:KEY_USE_TAB_COLOR inProfile:aDict]) {
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

- (void)invalidateStatusBar {
    [_view invalidateStatusBar];
    [_delegate sessionDidInvalidateStatusBar:self];
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

- (void)setUseLibTickit:(BOOL)value {
    if (value == _useLibTickit) {
        return;
    }
    _useLibTickit = value;
    [self updateKeyMapper];
}

- (void)updateKeyMapper {
    Class mapperClass = [iTermStandardKeyMapper class];
    if (_terminal.reportKeyUp) {
        mapperClass = [iTermRawKeyMapper class];
    } else if (_useLibTickit) {
        mapperClass = [iTermTermkeyKeyMapper class];
    }
    if ([_keyMapper isKindOfClass:mapperClass]) {
        return;
    }
    [_keyMapper release];
    _keyMapper = nil;

    id<iTermKeyMapper> keyMapper = [[mapperClass alloc] init];
    if ([keyMapper respondsToSelector:@selector(setDelegate:)]) {
        [keyMapper setDelegate:self];
    }
    _keyMapper = keyMapper;
    _textview.keyboardHandler.keyMapper = _keyMapper;
}

- (NSString *)badgeFormat {
    return _badgeSwiftyString.swiftyString;
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
    return _commandRange.start.x >= 0;
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
}

- (NSString *)name {
    return [self.variablesScope valueForVariableName:iTermVariableKeySessionName] ?: [self.variablesScope valueForVariableName:iTermVariableKeySessionProfileName] ?: @"Untitled";
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
            [_graphicSource updateImageForProcessID:self.shell.pid enabled:[self shouldShowTabGraphicForProfile:profile]];
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
    return [_customIcon imageAtPath:path ofSize:NSMakeSize(16, 16) flipped:YES];
}

- (NSString *)windowTitle {
    return _nameController.presentationWindowTitle;
}

- (void)pushWindowTitle {
    [_nameController pushWindowTitle];
}

- (void)popWindowTitle {
    [self.variablesScope setValue:[_nameController popWindowTitle]
                 forVariableNamed:iTermVariableKeySessionWindowName];
}

- (void)pushIconTitle {
    [_nameController pushIconTitle];
}

- (void)popIconTitle {
    [self.variablesScope setValue:[_nameController popIconTitle]
                 forVariableNamed:iTermVariableKeySessionIconName];
}

- (VT100Terminal *)terminal
{
    return _terminal;
}

- (void)setTermVariable:(NSString *)termVariable
{
    [_termVariable autorelease];
    _termVariable = [termVariable copy];
    [_terminal setTermType:_termVariable];
}

- (void)setView:(SessionView *)newView {
    [_view autorelease];
    _view = [newView retain];
    newView.delegate = self;
    if (@available(macOS 10.11, *)) {
        newView.driver.dataSource = _metalGlue;
    }
    [newView updateTitleFrame];
    [_view setFindDriverDelegate:self];
}

- (NSStringEncoding)encoding
{
    return [_terminal encoding];
}

- (void)setEncoding:(NSStringEncoding)encoding {
    [_terminal setEncoding:encoding];
}


- (NSString *)tty {
    return [_shell tty];
}

- (void)setBackgroundImageMode:(iTermBackgroundImageMode)mode {
    _backgroundImageMode = mode;
    [self setBackgroundImagePath:_backgroundImagePath];
}

- (void)setBackgroundImagePath:(NSString *)imageFilePath
{
    if ([imageFilePath length]) {
        if ([imageFilePath isAbsolutePath] == NO) {
            NSBundle *myBundle = [NSBundle bundleForClass:[self class]];
            imageFilePath = [myBundle pathForResource:imageFilePath ofType:@""];
        }
        [_backgroundImagePath autorelease];
        _backgroundImagePath = [imageFilePath copy];
        self.backgroundImage = [[[NSImage alloc] initWithContentsOfFile:_backgroundImagePath] autorelease];
    } else {
        self.backgroundImage = nil;
        [_backgroundImagePath release];
        _backgroundImagePath = nil;
    }

    [_patternedImage release];
    _patternedImage = nil;

    [_textview setNeedsDisplay:YES];
}

- (void)setSmartCursorColor:(BOOL)value {
    [[self textview] setUseSmartCursorColor:value];
}

- (void)setMinimumContrast:(float)value
{
    [[self textview] setMinimumContrast:value];
}

- (BOOL)viewShouldWantLayer {
    return NO;
}

- (void)useTransparencyDidChange {
    // The view does not like getting replaced during the spin of the runloop during which it is created.
    if (_view.window && _delegate.realParentWindow && _textview) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_view.window && _delegate.realParentWindow && _textview) {
                [_delegate sessionTransparencyDidChange];
            }
        });
    }
}

- (float)transparency
{
    return [_textview transparency];
}

- (void)setTransparency:(float)transparency
{
    // Limit transparency because fully transparent windows can't be clicked on.
    if (transparency > 0.9) {
        transparency = 0.9;
    }
    [_textview setTransparency:transparency];
    [self useTransparencyDidChange];
    [self.view setNeedsDisplay:YES];
}

- (float)blend {
    return [_textview blend];
}

- (void)setBlend:(float)blendVal {
    [_textview setBlend:blendVal];
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

- (BOOL)logging
{
    return [_shell logging];
}

- (void)logStart {
    iTermSavePanel *savePanel = [iTermSavePanel showWithOptions:kSavePanelOptionAppendOrReplace
                                                     identifier:@"StartSessionLog"
                                               initialDirectory:NSHomeDirectory()
                                                defaultFilename:@""];
    if (savePanel.path) {
        BOOL shouldAppend = (savePanel.replaceOrAppend == kSavePanelReplaceOrAppendSelectionAppend);
        BOOL ok = [_shell startLoggingToFileWithPath:savePanel.path
                                        shouldAppend:shouldAppend];
        if (!ok) {
            NSBeep();
        }
    }
}

- (void)logStop {
    [_shell stopLogging];
}

- (void)clearBuffer {
    [_screen clearBuffer];
    if (self.isTmuxClient) {
        [_tmuxController clearHistoryForWindowPane:self.tmuxPane];
    }
    if ([iTermAdvancedSettingsModel jiggleTTYSizeOnClearBuffer]) {
        VT100GridSize size = _screen.size;
        size.width++;
        _shell.size = size;
        _shell.size = _screen.size;
    }
    _view.scrollview.ptyVerticalScroller.userScroll = NO;
}

- (void)clearScrollbackBuffer {
    [_screen clearScrollbackBuffer];
    if (self.isTmuxClient) {
        [_tmuxController clearHistoryForWindowPane:self.tmuxPane];
    }
}

- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask
{
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
    [_view.scrollview setDocumentView:_wrapper];
    NSRect rect = {
        .origin = NSZeroPoint,
        .size = _view.scrollview.contentSize
    };
    _wrapper.frame = rect;
    [_textview refresh];
}

- (void)setProfile:(Profile *)newProfile {
    assert(newProfile);
    DLog(@"Set profile to one with guid %@", newProfile[KEY_GUID]);

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
    [[_delegate realParentWindow] invalidateRestorableState];
    [[_delegate realParentWindow] updateTabColors];
    [_nameController setNeedsUpdate];
}

- (NSDictionary *)arrangement {
    return [self arrangementWithContents:NO];
}

- (NSDictionary *)arrangementWithContents:(BOOL)includeContents {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    result[SESSION_ARRANGEMENT_COLUMNS] = @(_screen.width);
    result[SESSION_ARRANGEMENT_ROWS] = @(_screen.height);
    result[SESSION_ARRANGEMENT_BOOKMARK] = _profile;

    if (_substitutions) {
        result[SESSION_ARRANGEMENT_SUBSTITUTIONS] = _substitutions;
    }
    if ([self.program isEqualToString:[ITAddressBookMgr shellLauncherCommand]]) {
        // The shell launcher command could change from run to run (e.g., if you move iTerm2).
        // I don't want to use a magic string, so setting program to an empty dic
        result[SESSION_ARRANGEMENT_PROGRAM] = @{ kProgramType: kProgramTypeShellLauncher };
    } else if (self.program) {
        result[SESSION_ARRANGEMENT_PROGRAM] = @{ kProgramType: kProgramTypeCommand,
                                                 kProgramCommand: self.program };
    }
    result[SESSION_ARRANGEMENT_ENVIRONMENT] = self.environment ?: @{};
    result[SESSION_ARRANGEMENT_IS_UTF_8] = @(self.isUTF8);
    result[SESSION_ARRANGEMENT_SHORT_LIVED_SINGLE_USE] = @(self.shortLivedSingleUse);

    NSDictionary *shortcutDictionary = [[[iTermSessionHotkeyController sharedInstance] shortcutForSession:self] dictionaryValue];
    if (shortcutDictionary) {
        result[SESSION_ARRANGEMENT_HOTKEY] = shortcutDictionary;
    }

    result[SESSION_ARRANGEMENT_NAME_CONTROLLER_STATE] = [_nameController stateDictionary];
    if (includeContents) {
        NSDictionary *contentsDictionary = [_screen contentsDictionary];
        result[SESSION_ARRANGEMENT_CONTENTS] = contentsDictionary;
        int numberOfLinesDropped =
            [contentsDictionary[kScreenStateKey][kScreenStateNumberOfLinesDroppedKey] intValue];
        result[SESSION_ARRANGEMENT_VARIABLES] = _variables.dictionaryValue;
        VT100GridCoordRange range = _commandRange;
        range.start.y -= numberOfLinesDropped;
        range.end.y -= numberOfLinesDropped;
        result[SESSION_ARRANGEMENT_COMMAND_RANGE] =
            [NSDictionary dictionaryWithGridCoordRange:range];
        result[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK] = @(_alertOnNextMark);
        result[SESSION_ARRANGEMENT_CURSOR_GUIDE] = @(_textview.highlightCursorLine);
        if (self.lastDirectory) {
            result[SESSION_ARRANGEMENT_LAST_DIRECTORY] = self.lastDirectory;
            result[SESSION_ARRANGEMENT_LAST_DIRECTORY_IS_UNSUITABLE_FOR_OLD_PWD] = @(self.lastDirectoryIsUnsuitableForOldPWD);
        }
        result[SESSION_ARRANGEMENT_SELECTION] =
            [self.textview.selection dictionaryValueWithYOffset:-numberOfLinesDropped];
        result[SESSION_ARRANGEMENT_APS] = [_automaticProfileSwitcher savedState];
    }
    result[SESSION_ARRANGEMENT_GUID] = _guid;
    if (_liveSession && includeContents && !_dvr) {
        result[SESSION_ARRANGEMENT_LIVE_SESSION] =
            [_liveSession arrangementWithContents:includeContents];
    }
    if (includeContents && !self.isTmuxClient) {
        // These values are used for restoring sessions after a crash. It's only saved when contents
        // are included since saved window arrangements have no business knowing the process id.
        if ([iTermAdvancedSettingsModel runJobsInServers] && !_shell.pidIsChild) {
            result[SESSION_ARRANGEMENT_SERVER_PID] = @(_shell.serverPid);
            if (self.tty) {
                result[SESSION_ARRANGEMENT_TTY] = self.tty;
            }
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

    result[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED] = @(_shellIntegrationEverUsed);
    result[SESSION_ARRANGEMENT_COMMANDS] = _commands;
    result[SESSION_ARRANGEMENT_DIRECTORIES] = _directories;
    result[SESSION_ARRANGEMENT_HOSTS] = [_hosts mapWithBlock:^id(id anObject) {
        return [(VT100RemoteHost *)anObject dictionaryValue];
    }];

    NSString *pwd = [self currentLocalWorkingDirectory];
    result[SESSION_ARRANGEMENT_WORKING_DIRECTORY] = pwd ? pwd : @"";
    return result;
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

- (void)updateScroll {
    if (![(PTYScroller*)([_view.scrollview verticalScroller]) userScroll]) {
        [_textview scrollEnd];
    }
}

- (void)updateDisplayBecause:(NSString *)reason {
    DLog(@"updateDisplayBecause:%@ %@", reason, _cadenceController);
    _updateCount++;
    if (@available(macOS 10.11, *)) {
        if (_useMetal && _updateCount % 10 == 0) {
            iTermPreciseTimerSaveLog([NSString stringWithFormat:@"%@: updateDisplay interval", _view.driver.identifier],
                                     _cadenceController.histogram.stringValue);
        }
    }
    _timerRunning = YES;

    // Set attributes of tab to indicate idle, processing, etc.
    if (![self isTmuxGateway]) {
        [_delegate updateLabelAttributes];
    }

    static const NSTimeInterval kUpdateTitlePeriod = 0.7;
    if ([_delegate sessionIsActiveInTab:self]) {
        // Update window info for the active tab.
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!self.jobName ||
            now >= (_lastUpdate + kUpdateTitlePeriod)) {
            // It has been more than 700ms since the last time we were here or
            // the job doesn't have a name.
            [self updateTitles];
            _lastUpdate = now;
        }
    } else {
        [self setCurrentForegroundJobProcessInfo:[_shell cachedProcessInfoIfAvailable]];
        [self.view setTitle:_nameController.presentationSessionTitle];
    }

    DLog(@"Session %@ calling refresh", self);
    const BOOL somethingIsBlinking = [_textview refresh];
    const BOOL transientTitle = _delegate.realParentWindow.isShowingTransientTitle;
    const BOOL animationPlaying = _textview.getAndResetDrawingAnimatedImageFlag;

    // Even if "active" isn't changing we need the side effect of setActive: that updates the
    // cadence since we might have just become idle.
    self.active = (somethingIsBlinking || transientTitle || animationPlaying);

    if (_tailFindTimer && _view.findViewIsHidden) {
        [self stopTailFind];
    }

    [self checkPartialLineTriggers];
    _passwordInput = _shell.passwordInput;
    _timerRunning = NO;
}

// Update the tab, session view, and window title.
- (void)updateTitles {
    iTermProcessInfo *processInfo = [_shell cachedProcessInfoIfAvailable];
    if (processInfo) {
        [self updateTitleWithProcessInfo:processInfo];
        return;
    } else {
        [self updateTitleWithProcessInfo:nil];
    }
    __weak __typeof(self) weakSelf = self;
    [_shell fetchProcessInfoForCurrentJobWithCompletion:^(iTermProcessInfo *processInfo) {
        [weakSelf updateTitleWithProcessInfo:processInfo];
    }];
}

- (void)updateTitleWithProcessInfo:(iTermProcessInfo *)processInfo {
    DLog(@"Job for pid %@ is %@, pid=%@", @(_shell.pid), processInfo.name, @(processInfo.processID));
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
    [self.variablesScope setValue:processInfo.name forVariableNamed:iTermVariableKeySessionJob];
    [self.variablesScope setValue:processInfo.commandLine forVariableNamed:iTermVariableKeySessionCommandLine];
    [self.variablesScope setValue:@(processInfo.processID) forVariableNamed:iTermVariableKeySessionJobPid];
    if (!_exited && _shell.pid > 0) {
        [self.variablesScope setValue:@(_shell.pid) forVariableNamed:iTermVariableKeySessionChildPid];
    }

    [self tryAutoProfileSwitchWithHostname:self.variablesScope.hostname
                                  username:self.variablesScope.username
                                      path:self.variablesScope.path
                                       job:processInfo.name];
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
    [_cadenceController changeCadenceIfNeeded];
}

- (void)doAntiIdle {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    if (![self isTmuxGateway] && now >= _lastInput + _antiIdlePeriod - kAntiIdleGracePeriod) {
        // This feature is hopeless for tmux gateways. Issue 5231.
        [self writeLatin1EncodedData:[NSData dataWithBytes:&_antiIdleCode length:1]
                    broadcastAllowed:NO];
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

- (void)setFont:(NSFont*)font
    nonAsciiFont:(NSFont*)nonAsciiFont
    horizontalSpacing:(float)horizontalSpacing
    verticalSpacing:(float)verticalSpacing {
    DLog(@"setFont:%@ nonAsciiFont:%@", font, nonAsciiFont);
    NSWindow *window = [[_delegate realParentWindow] window];
    DLog(@"Before:\n%@", [window.contentView iterm_recursiveDescription]);
    DLog(@"Window frame: %@", window);
    if ([_textview.font isEqualTo:font] &&
        [_textview.nonAsciiFontEvenIfNotUsed isEqualTo:nonAsciiFont] &&
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
    DLog(@"Line height was %f", (float)[_textview lineHeight]);
    [_textview setFont:font
          nonAsciiFont:nonAsciiFont
     horizontalSpacing:horizontalSpacing
       verticalSpacing:verticalSpacing];
    DLog(@"Line height is now %f", (float)[_textview lineHeight]);
    [_delegate sessionDidChangeFontSize:self adjustWindow:!_windowAdjustmentDisabled];
    DLog(@"After:\n%@", [window.contentView iterm_recursiveDescription]);
    DLog(@"Window frame: %@", window);
}

- (void)terminalFileShouldStop:(NSNotification *)notification {
    if ([notification object] == _download) {
        [_screen.terminal stopReceivingFile];
        [_download endOfData];
        self.download = nil;
    } else if ([notification object] == _upload) {
        [_pasteHelper abort];
        [_upload endOfData];
        self.upload = nil;
        char controlC[1] = { VT100CC_ETX };
        NSData *data = [NSData dataWithBytes:controlC length:sizeof(controlC)];
        [self writeLatin1EncodedData:data broadcastAllowed:NO];
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
                                      inSession:nil
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

- (void)savedArrangementWasRepaired:(NSNotification *)notification {
    if ([notification.object isEqual:_missingSavedArrangementProfileGUID]) {
        Profile *newProfile = notification.userInfo[@"new profile"];
        _isDivorced = NO;
        [_overriddenFields removeAllObjects];
        [_originalProfile release];
        _originalProfile = nil;
        self.profile = newProfile;
        [self setPreferencesFromAddressBookEntry:newProfile];
        [self dismissAnnouncementWithIdentifier:@"ThisProfileNoLongerExists"];
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

// Metal is disabled when any note anywhere is visible because compositing NSViews over Metal
// is a horror and besides these are subviews of PTYTextView and I really don't
// want to invest any more in this little-used feature.
- (void)annotationVisibilityDidChange:(NSNotification *)notification {
    if ([iTermPreferences boolForKey:kPreferenceKeyUseMetal]) {
        [_delegate sessionUpdateMetalAllowed];
    }
}

- (void)synchronizeTmuxFonts:(NSNotification *)notification {
    if (!_exited && [self isTmuxClient]) {
        NSArray *args = [notification object];
        NSFont *font = args[0];
        NSFont *nonAsciiFont = args[1];
        NSNumber *hSpacing = args[2];
        NSNumber *vSpacing = args[3];
        TmuxController *controller = args[4];
        NSNumber *tmuxWindow = args[5];
        if (controller == _tmuxController &&
            (!controller.variableWindowSize || tmuxWindow.intValue == self.delegate.tmuxWindow)) {
            [_textview setFont:font
                  nonAsciiFont:nonAsciiFont
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
                                                            object:@[ _textview.font,
                                                                      _textview.nonAsciiFontEvenIfNotUsed,
                                                                      @(_textview.horizontalSpacing),
                                                                      @(_textview.verticalSpacing),
                                                                      _tmuxController ?: [NSNull null],
                                                                      @(self.delegate.tmuxWindow)]];
        fontChangeNotificationInProgress = NO;
        [_delegate setTmuxFont:_textview.font
                  nonAsciiFont:_textview.nonAsciiFontEvenIfNotUsed
                      hSpacing:_textview.horizontalSpacing
                      vSpacing:_textview.verticalSpacing];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionTmuxFontDidChange
                                                            object:self];
    }
}

- (void)changeFontSizeDirection:(int)dir {
    DLog(@"changeFontSizeDirection:%d", dir);
    NSFont* font;
    NSFont* nonAsciiFont;
    float hs, vs;
    if (dir) {
        // Grow or shrink
        DLog(@"grow/shrink");
        font = [self fontWithRelativeSize:dir from:_textview.font];
        nonAsciiFont = [self fontWithRelativeSize:dir from:_textview.nonAsciiFontEvenIfNotUsed];
        hs = [_textview horizontalSpacing];
        vs = [_textview verticalSpacing];
    } else {
        // Restore original font size.
        NSDictionary *abEntry = [self originalProfile];
        NSString* fontDesc = [abEntry objectForKey:KEY_NORMAL_FONT];
        font = [ITAddressBookMgr fontWithDesc:fontDesc];
        nonAsciiFont = [ITAddressBookMgr fontWithDesc:[abEntry objectForKey:KEY_NON_ASCII_FONT]];
        hs = [[abEntry objectForKey:KEY_HORIZONTAL_SPACING] floatValue];
        vs = [[abEntry objectForKey:KEY_VERTICAL_SPACING] floatValue];
    }
    [self setFont:font nonAsciiFont:nonAsciiFont horizontalSpacing:hs verticalSpacing:vs];

    if (dir || _isDivorced) {
        // Move this bookmark into the sessions model.
        NSString* guid = [self divorceAddressBookEntryFromPreferences];

        [self setSessionSpecificProfileValues:@{ KEY_NORMAL_FONT: [font stringValue],
                                                 KEY_NON_ASCII_FONT: [nonAsciiFont stringValue] }];
        // Set the font in the bookmark dictionary

        // Update the model's copy of the bookmark.
        [[ProfileModel sessionsInstance] setBookmark:[self profile] withGuid:guid];

        // Update an existing one-bookmark prefs dialog, if open.
        if ([[[PreferencePanel sessionsInstance] windowIfLoaded] isVisible]) {
            [[PreferencePanel sessionsInstance] underlyingBookmarkDidChange];
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

- (void)remarry
{
    _isDivorced = NO;
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

- (NSString*)divorceAddressBookEntryFromPreferences
{
    Profile* bookmark = [self profile];
    NSString* guid = [bookmark objectForKey:KEY_GUID];
    if (_isDivorced) {
        assert([[ProfileModel sessionsInstance] bookmarkWithGuid:guid]);
        return guid;
    }
    _isDivorced = YES;
    DLog(@"Remove profile with guid %@ from sessions instance", guid);
    [[ProfileModel sessionsInstance] removeProfileWithGuid:guid];
    DLog(@"Set profile %@ divorced, add to sessions instance", bookmark[KEY_GUID]);
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
    DLog(@"Allocating a new guid for this profile. The new guid is %@", guid);
    [[ProfileModel sessionsInstance] setObject:guid
                                        forKey:KEY_GUID
                                    inBookmark:bookmark];
    [_overriddenFields removeAllObjects];
    [_overriddenFields addObjectsFromArray:@[ KEY_GUID, KEY_ORIGINAL_GUID] ];
    [self setProfile:[[ProfileModel sessionsInstance] bookmarkWithGuid:guid]];
    return guid;
}

// Jump to the saved scroll position
- (void)jumpToSavedScrollPosition
{
    iTermMark *mark = nil;
    if (_lastMark && [_screen markIsValid:_lastMark]) {
        mark = _lastMark;
    } else {
        mark = [_screen lastMark];
    }
    Interval *interval = mark.entry.interval;
    if (!interval) {
        NSBeep();
        return;
    }
    VT100GridRange range = [_screen lineNumberRangeOfInterval:interval];
    long long offset = range.location;
    if (offset < 0) {
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

- (void)useStringForFind:(NSString *)string {
    _view.findDriver.findString = string;
}

- (void)findWithSelection {
    if ([_textview selectedText]) {
        _view.findDriver.findString = _textview.selectedText;
    }
}

- (void)showFindPanel {
    [_view showFindUI];
}

// Note that the caller is responsible for respecting swapFindNextPrevious
- (void)searchNext {
    [_view.findDriver searchNext];
}

// Note that the caller is responsible for respecting swapFindNextPrevious
- (void)searchPrevious {
    [_view.findDriver searchPrevious];
}

- (void)resetFindCursor {
    [_textview resetFindCursor];
}

- (BOOL)findInProgress {
    return [_textview findInProgress];
}

- (BOOL)continueFind:(double *)progress {
    return [_textview continueFind:progress];
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
scrollToFirstResult:(BOOL)scrollToFirstResult {
    [_textview findString:aString
         forwardDirection:direction
                     mode:mode
               withOffset:offset
      scrollToFirstResult:scrollToFirstResult];
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
    [_textview clearHighlights:YES];
}

- (void)findViewControllerVisibilityDidChange:(id<iTermFindViewController>)sender {
    if (@available(macOS 10.11, *)) {
        [_delegate sessionUpdateMetalAllowed];
    }
    if (sender.driver.isVisible) {
        return;
    }
    if (_view.findViewHasKeyboardFocus) {
        [_view findViewDidHide];
    }
}

- (void)findViewControllerDidCeaseToBeMandatory:(id<iTermFindViewController>)sender {
    [_view findViewDidHide];
}

- (NSImage *)snapshot {
    DLog(@"Session %@ calling refresh", self);
    [_textview refresh];
    return [_view snapshot];
}

- (void)askAboutAbortingDownload {
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:@"A file is being downloaded. Abort the download?"
                                                         style:kiTermAnnouncementViewStyleQuestion
                                                   withActions:@[ @"OK", @"Cancel" ]
                                                    completion:^(int selection) {
                                                        if (selection == 0) {
                                                            [self.terminal stopReceivingFile];
                                                        }
                                                    }];
    [self queueAnnouncement:announcement identifier:@"AbortDownloadOnKeyPressAnnouncement"];
}

- (void)askAboutAbortingUpload {
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:@"A file is being uploaded. Abort the uploaded?"
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"OK", @"Cancel" ]
                                                completion:^(int selection) {
                                                    if (selection == 0) {
                                                        if (self.upload) {
                                                            [_pasteHelper abort];
                                                            [self.upload endOfData];
                                                            self.upload = nil;
                                                        }
                                                    }
                                                }];
    [self queueAnnouncement:announcement identifier:@"AbortUploadOnKeyPressAnnouncement"];
}

#pragma mark - Metal Support

#pragma mark iTermMetalGlueDelegate

- (void)metalGlueDidDrawFrameAndNeedsRedraw:(BOOL)redrawAsap NS_AVAILABLE_MAC(10_11) {
    if (_view.useMetal) {
        if (redrawAsap) {
            [_textview setNeedsDisplay:YES];
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

- (BOOL)metalAllowed:(out iTermMetalUnavailableReason *)reason {
    static dispatch_once_t onceToken;
    static BOOL machineSupportsMetal;
    dispatch_once(&onceToken, ^{
        NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
        machineSupportsMetal = devices.count > 0;
        [devices release];
    });
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
    if ([[iTermController sharedInstance] terminalIsObscured:_delegate.realParentWindow threshold:0.5]) {
        if (reason) {
            *reason = iTermMetalUnavailableReasonWindowObscured;
        }
        return NO;
    }
    if ([PTYNoteViewController anyNoteVisible]) {
        // When metal is enabled the note's superview (PTYTextView) has alphaValue=0 so it will not be visible.
        if (reason) {
            *reason = iTermMetalUnavailableReasonAnnotations;
        }
        return NO;
    }

    if (_textview.transparencyAlpha < 1) {
        BOOL transparencyAllowed = NO;
#if ENABLE_TRANSPARENT_METAL_WINDOWS
        if (@available(macOS 10.14, *)) {
            if (iTermTextIsMonochrome()) {
                transparencyAllowed = YES;
            }
        }
#endif
        if (!transparencyAllowed && _textview.transparencyAlpha < 1) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonTransparency;
            }
            return NO;
        }
    }
    if (@available(macOS 10.14, *)) { } else {
        // The following conditions only apply before macOS 10.14.
        // Mojave fixed compositing of views over MTKView and removed subpixel antialiasing making blending of text easier.
        if ([_textview verticalSpacing] < 1) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonVerticalSpacing;
            }
            // Metal cuts off the tops of letters when line height reduced
            return NO;
        }
        // Metal's not allowed when other views are composited over the metal view because that just
        // doesn't seem to work, even if you use presentsWithTransaction (even if it did work, it
        // requires presenting the drawable on the main thread which defeats the purpose of the metal
        // renderer).
        //
        // Perhaps some day transparency and ligatures will be supported.
        const BOOL nativeFullScreen = !!(self.view.window.styleMask & NSWindowStyleMaskFullScreen);
        const BOOL untitled = self.view.window && !(self.view.window.styleMask & NSWindowStyleMaskTitled);
        const BOOL hasSquareCorners = untitled || nativeFullScreen;
        const BOOL marginsOk = ([iTermAdvancedSettingsModel terminalVMargin] >= 2 &&
                                [iTermAdvancedSettingsModel terminalMargin] >= 1);  // Smaller margins break rounded window corners
        const BOOL safeForWindowCorners = (hasSquareCorners || marginsOk);
        if (!safeForWindowCorners) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonMarginSize;
            }
            return NO;
        }
        
        if (_view.isDropDownSearchVisible) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonFindPanel;
            }
            return NO;
        }
        if (_pasteHelper.dropDownPasteViewIsVisible) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonPasteIndicator;
            }
            return NO;
        }
        if (_view.currentAnnouncement) {
            if (reason) {
            *reason = iTermMetalUnavailableReasonAnnouncement;
            }
            return NO;
        }
        if (_view.hasHoverURL) {
            if (reason) {
                *reason = iTermMetalUnavailableReasonURLPreview;
            }
            return NO;
        }
    }
    return YES;
}

- (BOOL)canProduceMetalFramecap {
    if (@available(macOS 10.11, *)) {
        return _useMetal && _view.metalView.alphaValue == 1 && _wrapper.useMetal && _textview.suppressDrawing;
    } else {
        return NO;
    }
}

- (BOOL)metalViewSizeIsLegal NS_AVAILABLE_MAC(10_11) {
    NSSize size = _view.frame.size;
    // When closing a session I once got an insane height that caused an assertion.
    const CGFloat maxScale = 2;
    return size.width > 0 && size.width < (8192 / maxScale) && size.height > 0 && size.height < (8192 / maxScale);
}

- (BOOL)idleForMetal {
    if (@available(macOS 10.11, *)) {
        return (!_cadenceController.isActive &&
                !_view.verticalScroller.userScroll &&
                !self.overrideGlobalDisableMetalWhenIdleSetting &&
                !_view.driver.captureDebugInfoForNextFrame);

    } else {
        return NO;
    }
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
    if (@available(macOS 10.11, *)) {
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
        [_textview setNeedsDisplay:YES];
        [_cadenceController changeCadenceIfNeeded];

        if (useMetal) {
            [self renderTwoMetalFramesAndShowMetalView];
        } else {
            _view.metalView.enableSetNeedsDisplay = NO;
        }
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
    // If the text view had been visible, hide it. Hiding it before the
    // first frame is drawn causes a flash of gray.
    DLog(@"showMetalAndStopDrawingTextView");
    _wrapper.useMetal = YES;
    _textview.suppressDrawing = YES;
    if (@available(macOS 10.14, *)) {
        _view.scrollview.alphaValue = 0;
    }
    _view.metalView.alphaValue = 1;
}

- (void)setUseMetal:(BOOL)useMetal dataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    [_view setUseMetal:useMetal dataSource:dataSource];
    if (!useMetal) {
        _textview.suppressDrawing = NO;
        if (@available(macOS 10.14, *)) {
            _view.scrollview.alphaValue = 1;
        }
    }
}

- (void)updateMetalDriver NS_AVAILABLE_MAC(10_11) {
    DLog(@"%@", self);
    const CGSize cellSize = CGSizeMake(_textview.charWidth, _textview.lineHeight);
    CGSize glyphSize;
    const CGFloat scale = _view.window.backingScaleFactor ?: 1;
    NSRect rect = [iTermCharacterSource boundingRectForCharactersInRange:NSMakeRange(32, 127-32)
                                                           asciiFontInfo:_textview.primaryFont
                                                        nonAsciiFontInfo:_textview.secondaryFont
                                                                   scale:scale
                                                             useBoldFont:_textview.useBoldFont
                                                           useItalicFont:_textview.useItalicFont
                                                        usesNonAsciiFont:_textview.useNonAsciiFont
                                                                 context:[PTYSession onePixelContext]];
    CGSize asciiOffset = CGSizeZero;
    if (rect.origin.y < 0) {
        // Iosevka Light is the only font I've found that needs this.
        // It rides *very* low in its box. The lineheight that PTYFontInfo calculates is actually too small
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
    if (iTermTextIsMonochrome()) {
        // Mojave can use a glyph size larger than cell size because compositing is trivial without subpixel AA.
        glyphSize.width = round(0.49 + MAX(cellSize.width, NSMaxX(rect)));
        glyphSize.height = round(0.49 + MAX(cellSize.height, NSMaxY(rect)));
    } else {
        glyphSize = cellSize;
    }
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
                      context:_metalContext];
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

#pragma mark - Captured Output

- (void)addCapturedOutput:(CapturedOutput *)capturedOutput {
    VT100ScreenMark *lastCommandMark = [_screen lastCommandMark];
    if (!lastCommandMark) {
        // TODO: Show an announcement
        return;
    }
    [lastCommandMark addCapturedOutput:capturedOutput];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionCapturedOutputDidChange
                                                        object:nil];
}

#pragma mark - Password Management

- (BOOL)canOpenPasswordManager {
    return !self.echoProbe.isActive;
}

- (void)enterPassword:(NSString *)password {
    _echoProbe.delegate = self;
    [_echoProbe beginProbeWithBackspace:[self backspaceData]
                               password:password];
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

- (void)setPasteboard:(NSString *)pbName
{
    if (pbName) {
        [_pasteboard autorelease];
        _pasteboard = [pbName copy];
        [_pbtext release];
        _pbtext = [[NSMutableData alloc] init];
    } else {
        NSPasteboard *pboard = [NSPasteboard pasteboardWithName:_pasteboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
        [pboard setData:_pbtext forType:NSStringPboardType];

        [_pasteboard release];
        _pasteboard = nil;
        [_pbtext release];
        _pbtext = nil;

        // In case it was the find pasteboard that changed
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                            object:nil
                                                          userInfo:nil];
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
    Coprocess *coprocess = [Coprocess launchedCoprocessWithCommand:command];
    coprocess.delegate = self.weakSelf;
    coprocess.mute = mute;
    [_shell setCoprocess:coprocess];
    [_textview setNeedsDisplay:YES];
}

- (void)launchSilentCoprocessWithCommand:(NSString *)command
{
    [self launchCoprocessWithCommand:command mute:YES];
}

- (void)setFocused:(BOOL)focused {
    if (focused != _focused) {
        _focused = focused;
        if ([_terminal reportFocus]) {
            [self writeLatin1EncodedData:[_terminal.output reportFocusGained:focused] broadcastAllowed:NO];
        }
        if (focused && [self isTmuxClient]) {
            [_tmuxController selectPane:self.tmuxPane];
            [self.delegate sessionDidReportSelectedTmuxPane:self];
        }
    }
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
    VT100RemoteHost *remoteHost = [self currentHost];
    if (remoteHost) {
        return [NSString stringWithFormat:@"%@@%@", remoteHost.username, remoteHost.hostname];
    } else {
        return _nameController.presentationSessionTitle;
    }
}

- (void)setTmuxMode:(PTYSessionTmuxMode)tmuxMode {
    @synchronized ([TmuxGateway class]) {
        _tmuxMode = tmuxMode;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *name;
        switch (tmuxMode) {
            case TMUX_NONE:
                name = nil;
                break;
            case TMUX_GATEWAY:
                name = @"gateway";
                break;
            case TMUX_CLIENT:
                name = @"client";
                [self installTmuxStatusBarMonitor];
                [self installTmuxTitleMonitor];
                break;
        }
        [self.variablesScope setValue:name forVariableNamed:iTermVariableKeySessionTmuxRole];
    });
}

- (void)installTmuxStatusBarMonitor {
    assert(!_tmuxStatusBarMonitor);
    _tmuxStatusBarMonitor = [[iTermTmuxStatusBarMonitor alloc] initWithGateway:_tmuxController.gateway
                                                                         scope:self.variablesScope];
    _tmuxStatusBarMonitor.active = [iTermProfilePreferences boolForKey:KEY_SHOW_STATUS_BAR inProfile:self.profile];
    if ([iTermAdvancedSettingsModel useTmuxStatusBar] ||
        [iTermStatusBarLayout shouldOverrideLayout:self.profile[KEY_STATUS_BAR_LAYOUT]]) {
        [self setSessionSpecificProfileValues:@{ KEY_STATUS_BAR_LAYOUT: [[iTermStatusBarLayout tmuxLayoutWithController:_tmuxController
                                                                                                                  scope:nil
                                                                                                                 window:self.delegate.tmuxWindow] dictionaryValue] }];
    }
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
                                                                format:@"#{pane_title}"
                                                                target:[NSString stringWithFormat:@"%%%@", @(self.tmuxPane)]
                                                          variableName:iTermVariableKeySessionTmuxPaneTitle
                                                                 block:^(NSString * _Nonnull title) {
                                                                     if (title) {
                                                                         [weakSelf setSessionSpecificProfileValues:@{ KEY_TMUX_PANE_TITLE: title ?: @""}];
                                                                     }
                                                                 }];
    [_tmuxTitleMonitor updateOnce];
}

- (void)uninstallTmuxTitleMonitor {
    if (!_tmuxTitleMonitor) {
        return;
    }
    [_tmuxTitleMonitor invalidate];
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
        if (_isDivorced) {
            model = [ProfileModel sessionsInstance];
        } else {
            model = [ProfileModel sharedInstance];
        }
        profile = self.profile;
    }
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
    [_screen crlf];
    [self printTmuxMessage:@"Command Menu"];
    [self printTmuxMessage:@"----------------------------"];
    [self printTmuxMessage:@"esc    Detach cleanly."];
    [self printTmuxMessage:@"  X    Force-quit tmux mode."];
    [self printTmuxMessage:@"  L    Toggle logging."];
    [self printTmuxMessage:@"  C    Run tmux command."];

    if ([iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession]) {
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
    [_shell registerAsCoprocessOnlyTask];
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
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
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
        [_screen addNote:note inRange:rangeAtCursor];
    } else if (VT100GridCoordRangeLength(rangeAfterCursor, _screen.width) > 0) {
        [_screen addNote:note inRange:rangeAfterCursor];
    } else if (VT100GridCoordRangeLength(rangeBeforeCursor, _screen.width) > 0) {
        [_screen addNote:note inRange:rangeBeforeCursor];
    } else {
        int y = _screen.cursorY - 1 + [_screen numberOfScrollbackLines];
        [_screen addNote:note inRange:VT100GridCoordRangeMake(0, y, _screen.width, y)];
    }
    [note makeFirstResponder];
}

- (void)addNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange {
    VT100GridCoordRange range = VT100GridCoordRangeFromAbsCoordRange(absRange,
                                                                     _screen.totalScrollbackOverflow);
    if (range.start.x < 0) {
        return;
    }
    PTYNoteViewController *note = [[[PTYNoteViewController alloc] init] autorelease];
    [note setString:text];
    [note sizeToFit];
    [_screen addNote:note inRange:range];
}

- (void)textViewToggleAnnotations {
    VT100GridCoordRange range =
        VT100GridCoordRangeMake(0,
                                0,
                                _screen.width,
                                _screen.height + [_screen numberOfScrollbackLines]);
    NSArray *notes = [_screen notesInRange:range];
    BOOL anyNoteIsVisible = NO;
    for (PTYNoteViewController *note in notes) {
        if (!note.view.isHidden) {
            anyNoteIsVisible = YES;
            break;
        }
    }
    for (PTYNoteViewController *note in notes) {
        [note setNoteHidden:anyNoteIsVisible];
    }
    [self.delegate sessionUpdateMetalAllowed];
}

- (void)highlightMarkOrNote:(id<IntervalTreeObject>)obj {
    if ([obj isKindOfClass:[iTermMark class]]) {
        BOOL hasErrorCode = NO;
        if ([obj isKindOfClass:[VT100ScreenMark class]]) {
            VT100ScreenMark *mark = (VT100ScreenMark *)obj;
            hasErrorCode = mark.code != 0;
        }
        [_textview highlightMarkOnLine:VT100GridRangeMax([_screen lineNumberRangeOfInterval:obj.entry.interval])
                          hasErrorCode:hasErrorCode];
    } else {
        PTYNoteViewController *note = (PTYNoteViewController *)obj;
        [note setNoteHidden:NO];
        [note highlight];
    }
}

- (void)previousMarkOrNote {
    NSArray *objects = nil;
    if (self.currentMarkOrNotePosition == nil) {
        objects = [_screen lastMarksOrNotes];
    } else {
        objects = [_screen marksOrNotesBefore:self.currentMarkOrNotePosition];
        if (!objects.count) {
            objects = [_screen lastMarksOrNotes];
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

- (void)nextMarkOrNote {
    NSArray *objects = nil;
    if (self.currentMarkOrNotePosition == nil) {
        objects = [_screen firstMarksOrNotes];
    } else {
        objects = [_screen marksOrNotesAfter:self.currentMarkOrNotePosition];
        if (!objects.count) {
            objects = [_screen firstMarksOrNotes];
            if (objects.count) {
                [_textview beginFlash:kiTermIndicatorWrapToTop];
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

- (void)scrollToMark:(id<iTermMark>)mark {
    if ([_screen containsMark:mark]) {
        VT100GridRange range = [_screen lineNumberRangeOfInterval:mark.entry.interval];
        [_textview scrollLineNumberRangeIntoView:range];
        [self highlightMarkOrNote:mark];
    }
}

- (void)setCurrentHost:(VT100RemoteHost *)remoteHost {
    [_currentHost autorelease];
    _currentHost = [remoteHost retain];
    [self.variablesScope setValue:remoteHost.hostname forVariableNamed:iTermVariableKeySessionHostname];
    [self.variablesScope setValue:remoteHost.username forVariableNamed:iTermVariableKeySessionUsername];
    [_delegate sessionCurrentHostDidChange:self];
}

- (VT100RemoteHost *)currentHost {
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

- (void)tmuxUpdateLayoutForWindow:(int)windowId
                           layout:(NSString *)layout
                           zoomed:(NSNumber *)zoomed {
    PTYTab *tab = [_tmuxController window:windowId];
    if (tab) {
        [_tmuxController setLayoutInTab:tab toLayout:layout zoomed:zoomed];
    }
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
    [_tmuxController ping];
    [_tmuxController validateOptions];
    [_tmuxController checkForUTF8];
    [_tmuxController guessVersion];
    [_tmuxController loadTitleFormat];
}

- (void)tmuxInitialCommandDidFailWithError:(NSString *)error {
    // Let the user know what went wrong.
    [self printTmuxMessage:[NSString stringWithFormat:@"tmux failed with error: “%@”", error]];
}

- (void)tmuxPrintLine:(NSString *)line
{
    [_screen appendStringAtCursor:line];
    [_screen crlf];
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
    [_screen appendStringAtCursor:@"Detached"];
    [_screen crlf];
    [dcsID retain];
    dispatch_async([[self class] tmuxQueue], ^{
        [_terminal.parser forceUnhookDCS:dcsID];
        [dcsID release];
    });
    self.tmuxMode = TMUX_NONE;
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionTmuxClientName];
    [self.variablesScope setValue:nil forVariableNamed:iTermVariableKeySessionTmuxPaneTitle];
}

- (void)tmuxCannotSendCharactersInSupplementaryPlanes:(NSString *)string windowPane:(int)windowPane {
    PTYSession *session = [_tmuxController sessionForWindowPane:windowPane];

    NSString *message = [NSString stringWithFormat:@"Because of a bug in tmux 2.2, the character “%@” cannot be sent.", string];
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:message
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ @"Why?" ]
                                                    completion:^(int selection) {
                                                        if (selection == 0) {
                                                            NSURL *whyUrl = [NSURL URLWithString:@"https://iterm2.com//tmux22bug.html"];
                                                            [[NSWorkspace sharedWorkspace] openURL:whyUrl];
                                                        }
                                                    }];
    announcement.dismissOnKeyDown = YES;
    [session queueAnnouncement:announcement identifier:@"Tmux2.2SupplementaryPlaneAnnouncement"];
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
        [self printTmuxMessage:string];
    }
    [self writeTaskImpl:string encoding:NSUTF8StringEncoding forceEncoding:YES canBroadcast:NO];
}

+ (dispatch_queue_t)tmuxQueue {
    static dispatch_queue_t tmuxQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tmuxQueue = dispatch_queue_create("com.iterm2.tmuxReadTask", 0);
    });
    return tmuxQueue;
}

// This is called on the main thread.
- (void)tmuxReadTask:(NSData *)data
{
    if (!_exited) {
        [_shell logData:(const char *)[data bytes] length:[data length]];
        // Dispatch this in a background thread to keep threadedReadTask:
        // simple. It always asynchronously dispatches to the main thread,
        // which would deadlock if it were called on the main thread.
        [data retain];
        [self retain];
        dispatch_async([[self class] tmuxQueue], ^{
            [self threadedReadTask:(char *)[data bytes] length:[data length]];
            [data release];
            [self release];
        });
        if (_shell.coprocess) {
            [_shell writeToCoprocessOnlyTask:data];
        }
    }
}

- (void)tmuxSessionChanged:(NSString *)sessionName sessionId:(int)sessionId
{
    [_tmuxController sessionChangedTo:sessionName sessionId:sessionId];
}

- (void)tmuxSessionsChanged
{
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
    NSArray<NSString *> *actions = @[ @"OK", @"Reveal" ];
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
    if (selection != kiTermWarningSelection1) {
        return;
    }
    NSArray<NSWindow *> *windows = [[[controller.clientSessions mapWithBlock:^id(PTYSession *anObject) {
        return anObject.view.window;
    }] sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        intptr_t p1 = (intptr_t)obj1;
        intptr_t p2 = (intptr_t)obj2;
        return [@(p1) compare:@(p2)];
    }] uniq];

    if (windows.count == 0) {
        iTermApplicationDelegate *delegate = [iTermApplication.sharedApplication delegate];
        [delegate openDashboard:nil];
        return;
    }

    for (NSWindow *window in windows) {
        if (window.miniaturized) {
            [window deminiaturize:nil];
        } else {
            [window orderFront:nil];
        }
    }
}

- (NSString*)encodingName
{
    // Get the encoding, perhaps as a fully written out name.
    CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding([self encoding]);
    // Convert it to the expected (IANA) format.
    NSString* ianaEncoding = (NSString*)CFStringConvertEncodingToIANACharSetName(cfEncoding);
    DLog(@"iana encoding is %@", ianaEncoding);
    // Fix up lowercase letters.
    static NSDictionary* lowerCaseEncodings;
    if (!lowerCaseEncodings) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"EncodingsWithLowerCase" ofType:@"plist"];
        lowerCaseEncodings = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        [lowerCaseEncodings retain];
    }
    if ([ianaEncoding rangeOfCharacterFromSet:[NSCharacterSet lowercaseLetterCharacterSet]].length) {
        // Some encodings are improperly returned as lower case. For instance,
        // "utf-8" instead of "UTF-8". If this isn't in the allowed list of
        // lower-case encodings, then uppercase it.
        if (lowerCaseEncodings) {
            if (![lowerCaseEncodings objectForKey:ianaEncoding]) {
                ianaEncoding = [ianaEncoding uppercaseString];
                DLog(@"Convert to uppser case. ianaEncoding is now %@", ianaEncoding);
            }
        }
    }

    if (ianaEncoding != nil) {
        // Mangle the names slightly
        NSMutableString* encoding = [[[NSMutableString alloc] initWithString:ianaEncoding] autorelease];
        [encoding replaceOccurrencesOfString:@"ISO-" withString:@"ISO" options:0 range:NSMakeRange(0, [encoding length])];
        [encoding replaceOccurrencesOfString:@"EUC-" withString:@"euc" options:0 range:NSMakeRange(0, [encoding length])];
        DLog(@"After mangling, encoding is now %@", encoding);
        return encoding;
    }

    DLog(@"Return nil encoding");

    return nil;
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
    }
    return NO;
}

- (BOOL)textViewShouldAcceptKeyDownEvent:(NSEvent *)event {
    const BOOL accept = ![self keystrokeIsFilteredByMonitor:event];

    if (accept) {
        if (_copyModeHandler.enabled) {
            if ([_copyModeHandler handleEvent:event]) {
                return NO;
            } else {
                if ([self hasActionableKeyMappingForEvent:event] &&
                    ![self hasTextSendingKeyMappingForEvent:event]) {
                    return YES;
                }
            }
        }
        if (event.keyCode == kVK_Return && _fakePromptDetectedAbsLine >= 0) {
            [self didInferEndOfCommand];
        }

        if ((event.it_modifierFlags & NSEventModifierFlagControl) && [event.charactersIgnoringModifiers isEqualToString:@"c"]) {
            if (self.terminal.receivingFile) {
                // Offer to abort download if you press ^c while downloading an inline file
                [self askAboutAbortingDownload];
            } else if (self.upload) {
                [self askAboutAbortingUpload];
            }
        }
        _lastInput = [NSDate timeIntervalSinceReferenceDate];
        [_pwdPoller userDidPressKey];
        if (_view.currentAnnouncement.dismissOnKeyDown) {
            [_view.currentAnnouncement dismiss];
            return NO;
        }
    }
    if (_keystrokeSubscriptions.count) {
        ITMKeystrokeNotification *keystrokeNotification = [[[ITMKeystrokeNotification alloc] init] autorelease];
        keystrokeNotification.characters = event.characters;
        keystrokeNotification.charactersIgnoringModifiers = event.charactersIgnoringModifiers;
        if (event.it_modifierFlags & NSEventModifierFlagControl) {
            [keystrokeNotification.modifiersArray addValue:ITMModifiers_Control];
        }
        if (event.it_modifierFlags & NSEventModifierFlagOption) {
            [keystrokeNotification.modifiersArray addValue:ITMModifiers_Option];
        }
        if (event.it_modifierFlags & NSEventModifierFlagCommand) {
            [keystrokeNotification.modifiersArray addValue:ITMModifiers_Command];
        }
        if (event.it_modifierFlags & NSEventModifierFlagShift) {
            [keystrokeNotification.modifiersArray addValue:ITMModifiers_Shift];
        }
        if (event.it_modifierFlags & NSEventModifierFlagNumericPad) {
            [keystrokeNotification.modifiersArray addValue:ITMModifiers_Numpad];
        }
        if (event.it_modifierFlags & NSEventModifierFlagFunction) {
            [keystrokeNotification.modifiersArray addValue:ITMModifiers_Function];
        }
        keystrokeNotification.keyCode = event.keyCode;
        keystrokeNotification.session = self.guid;
        ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
        notification.keystrokeNotification = keystrokeNotification;

        [_keystrokeSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
            [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                                 toConnectionKey:key];
        }];
    }

    if (accept) {
        [_metaFrustrationDetector didSendKeyEvent:event];
    }
    return accept;
}

+ (void)reportFunctionCallError:(NSError *)error forInvocation:(NSString *)invocation origin:(NSString *)origin window:(NSWindow *)window {
    NSString *message = [NSString stringWithFormat:@"Error running “%@”:\n%@",
                         invocation, error.localizedDescription];
    NSString *traceback = error.localizedFailureReason;
    NSArray *actions = @[ @"OK" ];
    if (traceback) {
        actions = [actions arrayByAddingObject:@"Reveal in Script Console"];
    }
    NSString *connectionKey = error.userInfo[iTermAPIHelperFunctionCallErrorUserInfoKeyConnection];
    iTermScriptHistoryEntry *entry = [[iTermScriptHistory sharedInstance] entryWithIdentifier:connectionKey];
    [entry addOutput:[NSString stringWithFormat:@"An error occurred while running the function invocation “%@”:\n%@\n\nTraceback:\n%@",
                      invocation,
                      error.localizedDescription,
                      traceback]];
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:message
                                                                 actions:actions
                                                               accessory:nil
                                                              identifier:@"NoSyncFunctionCallError"
                                                             silenceable:kiTermWarningTypeTemporarilySilenceable
                                                                 heading:[NSString stringWithFormat:@"%@ Function Call Failed", origin]
                                                                  window:window];
    if (selection == kiTermWarningSelection1) {
        [[iTermScriptConsole sharedInstance] revealTailOfHistoryEntry:entry];
    }
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
    [self performKeyBindingAction:action.action parameter:action.parameter event:nil];
}

// This is limited to the actions that don't need any existing session
+ (BOOL)performKeyBindingAction:(int)keyBindingAction parameter:(NSString *)keyBindingText event:(NSEvent *)event {
    switch (keyBindingAction) {
        case -1:
            // No action
            return NO;

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
        case KEY_ACTION_IGNORE:
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
            return NO;

        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            [iTermScriptFunctionCall callFunction:keyBindingText
                                          timeout:[[NSDate distantFuture] timeIntervalSinceNow]
                                            scope:[iTermVariableScope globalsScope]
                                       retainSelf:YES
                                       completion:^(id value, NSError *error, NSSet<NSString *> *missing) {
                                           if (error) {
                                               [PTYSession reportFunctionCallError:error
                                                                     forInvocation:keyBindingText
                                                                            origin:@"Key Binding"
                                                                            window:nil];
                                           }
                                       }];
            return YES;

        case KEY_ACTION_SELECT_MENU_ITEM:
            [PTYSession selectMenuItem:keyBindingText];
            return YES;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE: {
            Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:keyBindingText];
            [[iTermController sharedInstance] launchBookmark:profile
                                                  inTerminal:nil
                                          respectTabbingMode:NO];
            return YES;
        }
        case KEY_ACTION_UNDO:
            [PTYSession selectMenuItemWithSelector:@selector(undo:)];
            return YES;
    }
    assert(false);
    return NO;
}

- (void)performKeyBindingAction:(int)keyBindingAction parameter:(NSString *)keyBindingText event:(NSEvent *)event {
    BOOL isTmuxGateway = (!_exited && self.tmuxMode == TMUX_GATEWAY);

    switch (keyBindingAction) {
        case KEY_ACTION_MOVE_TAB_LEFT:
            [[_delegate realParentWindow] moveTabLeft:nil];
            break;
        case KEY_ACTION_MOVE_TAB_RIGHT:
            [[_delegate realParentWindow] moveTabRight:nil];
            break;
        case KEY_ACTION_NEXT_MRU_TAB:
            [[[_delegate parentWindow] tabView] cycleKeyDownWithModifiers:[event it_modifierFlags]
                                                                 forwards:YES];
            break;
        case KEY_ACTION_PREVIOUS_MRU_TAB:
            [[[_delegate parentWindow] tabView] cycleKeyDownWithModifiers:[event it_modifierFlags]
                                                                 forwards:NO];
            break;
        case KEY_ACTION_NEXT_PANE:
            [_delegate nextSession];
            break;
        case KEY_ACTION_PREVIOUS_PANE:
            [_delegate previousSession];
            break;
        case KEY_ACTION_NEXT_SESSION:
            [[_delegate parentWindow] nextTab:nil];
            break;
        case KEY_ACTION_NEXT_WINDOW:
            [[iTermController sharedInstance] nextTerminal];
            break;
        case KEY_ACTION_PREVIOUS_SESSION:
            [[_delegate parentWindow] previousTab:nil];
            break;
        case KEY_ACTION_PREVIOUS_WINDOW:
            [[iTermController sharedInstance] previousTerminal];
            break;
        case KEY_ACTION_SCROLL_END:
            [_textview scrollEnd];
            [(PTYScrollView *)[_textview enclosingScrollView] detectUserScroll];
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
            [self sendEscapeSequence:keyBindingText];
            break;
        case KEY_ACTION_HEX_CODE:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendHexCode:keyBindingText];
            break;
        case KEY_ACTION_TEXT:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendText:keyBindingText];
            break;
        case KEY_ACTION_VIM_TEXT:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self sendText:[keyBindingText stringByExpandingVimSpecialCharacters]];
            break;
        case KEY_ACTION_RUN_COPROCESS:
            if (_exited || isTmuxGateway) {
                return;
            }
            [self launchCoprocessWithCommand:keyBindingText];
            break;
        case KEY_ACTION_SELECT_MENU_ITEM:
            [PTYSession selectMenuItem:keyBindingText];
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
            [[[iTermController sharedInstance] currentTerminal] selectPaneLeft:nil];
            break;
        case KEY_ACTION_SELECT_PANE_RIGHT:
            [[[iTermController sharedInstance] currentTerminal] selectPaneRight:nil];
            break;
        case KEY_ACTION_SELECT_PANE_ABOVE:
            [[[iTermController sharedInstance] currentTerminal] selectPaneUp:nil];
            break;
        case KEY_ACTION_SELECT_PANE_BELOW:
            [[[iTermController sharedInstance] currentTerminal] selectPaneDown:nil];
            break;
        case KEY_ACTION_DO_NOT_REMAP_MODIFIERS:
        case KEY_ACTION_REMAP_LOCALLY:
            break;
        case KEY_ACTION_TOGGLE_FULLSCREEN:
            [[[iTermController sharedInstance] currentTerminal] toggleFullScreenMode:nil];
            break;
        case KEY_ACTION_NEW_WINDOW_WITH_PROFILE:
            [[_delegate realParentWindow] newWindowWithBookmarkGuid:keyBindingText];
            break;
        case KEY_ACTION_NEW_TAB_WITH_PROFILE:
            [[_delegate realParentWindow] newTabWithBookmarkGuid:keyBindingText];
            break;
        case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
            [[_delegate realParentWindow] splitVertically:NO
                                         withBookmarkGuid:keyBindingText
                                              synchronous:NO];
            break;
        case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
            [[_delegate realParentWindow] splitVertically:YES
                                         withBookmarkGuid:keyBindingText
                                              synchronous:NO];
            break;
        case KEY_ACTION_SET_PROFILE: {
            Profile *newProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:keyBindingText];
            if (newProfile) {
                [self setProfile:newProfile preservingName:YES];
            }
            break;
        }
        case KEY_ACTION_LOAD_COLOR_PRESET: {
            // Divorce & update self
            [self setColorsFromPresetNamed:keyBindingText];

            // Try to update the backing profile if possible, which may undivorce you. The original
            // profile may not exist so this could do nothing.
            ProfileModel *model = [ProfileModel sharedInstance];
            Profile *profile;
            if (_isDivorced) {
                profile = [[ProfileModel sharedInstance] bookmarkWithGuid:_profile[KEY_ORIGINAL_GUID]];
            } else {
                profile = self.profile;
            }
            if (profile) {
                [model addColorPresetNamed:keyBindingText toProfile:profile];
            }
            break;
        }

        case KEY_ACTION_FIND_REGEX:
            [_view.findDriver closeViewAndDoTemporarySearchForString:keyBindingText
                                                                mode:iTermFindModeCaseSensitiveRegex];
            break;

        case KEY_FIND_AGAIN_DOWN:
            // The UI exposes this as "find down" so it doesn't respect swapFindNextPrevious
            [self searchNext];
            break;

        case KEY_FIND_AGAIN_UP:
            // The UI exposes this as "find up" so it doesn't respect swapFindNextPrevious
            [self searchPrevious];
            break;

        case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION: {
            NSString *string = [[iTermController sharedInstance] lastSelection];
            if (string.length) {
                [_pasteHelper pasteString:string
                             stringConfig:keyBindingText];
            }
            break;
        }

        case KEY_ACTION_PASTE_SPECIAL: {
            NSString *string = [NSString stringFromPasteboard];
            if (string.length) {
                [_pasteHelper pasteString:string
                             stringConfig:keyBindingText];
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
                                          by:[keyBindingText integerValue]];
            break;
        case KEY_ACTION_MOVE_END_OF_SELECTION_RIGHT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointEnd
                                 inDirection:kPTYTextViewSelectionExtensionDirectionRight
                                          by:[keyBindingText integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_LEFT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointStart
                                 inDirection:kPTYTextViewSelectionExtensionDirectionLeft
                                          by:[keyBindingText integerValue]];
            break;
        case KEY_ACTION_MOVE_START_OF_SELECTION_RIGHT:
            [_textview moveSelectionEndpoint:kPTYTextViewSelectionEndpointStart
                                 inDirection:kPTYTextViewSelectionExtensionDirectionRight
                                          by:[keyBindingText integerValue]];
            break;

        case KEY_ACTION_DECREASE_HEIGHT:
            [[[iTermController sharedInstance] currentTerminal] decreaseHeight:nil];
            break;
        case KEY_ACTION_INCREASE_HEIGHT:
            [[[iTermController sharedInstance] currentTerminal] increaseHeight:nil];
            break;

        case KEY_ACTION_DECREASE_WIDTH:
            [[[iTermController sharedInstance] currentTerminal] decreaseWidth:nil];
            break;
        case KEY_ACTION_INCREASE_WIDTH:
            [[[iTermController sharedInstance] currentTerminal] increaseWidth:nil];
            break;

        case KEY_ACTION_SWAP_PANE_LEFT:
            [[[iTermController sharedInstance] currentTerminal] swapPaneLeft];
            break;
        case KEY_ACTION_SWAP_PANE_RIGHT:
            [[[iTermController sharedInstance] currentTerminal] swapPaneRight];
            break;
        case KEY_ACTION_SWAP_PANE_ABOVE:
            [[[iTermController sharedInstance] currentTerminal] swapPaneUp];
            break;
        case KEY_ACTION_SWAP_PANE_BELOW:
            [[[iTermController sharedInstance] currentTerminal] swapPaneDown];
            break;
        case KEY_ACTION_TOGGLE_MOUSE_REPORTING:
            [self setXtermMouseReporting:![self xtermMouseReporting]];
            break;
        case KEY_ACTION_INVOKE_SCRIPT_FUNCTION:
            [self invokeFunctionCall:keyBindingText scope:self.variablesScope origin:@"Key Binding"];
            break;
        case KEY_ACTION_DUPLICATE_TAB:
            [self.delegate sessionDuplicateTab];
            break;
        case KEY_ACTION_MOVE_TO_SPLIT_PANE:
            [self textViewMovePane];
            break;
        default:
            XLog(@"Unknown key action %d", keyBindingAction);
            break;
    }
}

#pragma mark - Key Handling

- (void)maybeWarnAboutOutdatedKeyBindingAction:(int)keyBindingAction modflag:(unsigned int)modflag profileAction:(int)profileAction unmodunicode:(unichar)unmodunicode {
    if (profileAction == keyBindingAction &&  // Don't warn if it's a global mapping
        (keyBindingAction == KEY_ACTION_NEXT_SESSION ||
         keyBindingAction == KEY_ACTION_PREVIOUS_SESSION)) {
            // Warn users about outdated default key bindings.
            int tempMods = modflag & (NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift | NSEventModifierFlagCommand);
            int tempKeyCode = unmodunicode;
            if (tempMods == (NSEventModifierFlagCommand | NSEventModifierFlagOption) &&
                (tempKeyCode == 0xf702 || tempKeyCode == 0xf703) &&
                [[_delegate sessions] count] > 1) {
                if ([self _askAboutOutdatedKeyMappings]) {
                    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
                    alert.messageText = @"Outdated Key Mapping Found";
                    alert.informativeText = @"It looks like you're trying to switch split panes but you have a key mapping from an old iTerm installation for ⌘⌥← or ⌘⌥→ that switches tabs instead. What would you like to do?";
                    [alert addButtonWithTitle:@"Remove it"];
                    [alert addButtonWithTitle:@"Remind me later"];
                    [alert addButtonWithTitle:@"Keep it"];
                    switch ([alert runModal]) {
                        case NSAlertFirstButtonReturn:
                            // Remove it
                            [self _removeOutdatedKeyMapping];
                            return;
                            break;
                        case NSAlertSecondButtonReturn:
                            // Remind me later
                            break;
                        case NSAlertThirdButtonReturn:
                            // Keep it
                            [self _setKeepOutdatedKeyMapping];
                            break;
                        default:
                            break;
                    }
                }
            }
        }
}

- (BOOL)eventNeedsMitigation:(NSEvent *)event {
    if (event.keyCode != kVK_Escape) {
        return NO;
    }
    // This isn't quite right because you might be using an external keyboard.
    // Looks like you have to use an event tap to detect touches on the bar,
    // which requires user consent.
    if (!IsTouchBarAvailable()) {
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
    
    NSNumber *savedCursorTypeSetting = [iTermProfilePreferences objectForKey:KEY_CURSOR_TYPE inProfile:self.profile];
    NSDictionary *dict = @{ KEY_CURSOR_TYPE: savedCursorTypeSetting };
    
    ITermCursorType temporaryType;
    if (savedCursorTypeSetting.integerValue == CURSOR_BOX) {
        temporaryType = CURSOR_UNDERLINE;
    } else {
        temporaryType = CURSOR_BOX;
    }

    [self setSessionSpecificProfileValues:@{ KEY_CURSOR_TYPE: @(temporaryType) }];
    [_textview setCursorNeedsDisplay];
    
    [self retain];
    [dict retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 / 15.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self setSessionSpecificProfileValues:dict];
        self->_showingVisualIndicatorForEsc = NO;
        [dict release];
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
    if (_exited) {
        DLog(@"Terminal already dead");
        return;
    }

    DLog(@"PTYSession keyDown not short-circuted by special handler");

    NSData *const dataToSend = [_keyMapper keyMapperDataForPostCocoaEvent:event];
    if (dataToSend) {
        [self writeLatin1EncodedData:dataToSend broadcastAllowed:YES];
    }
}

- (void)keyUp:(NSEvent *)event {
    if (_terminal.reportKeyUp) {
        NSData *const dataToSend = [_keyMapper keyMapperDataForKeyUp:event];
        if (dataToSend) {
            [self writeLatin1EncodedData:dataToSend broadcastAllowed:YES];
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
    if (character != 27) {
        return YES;
    }
    // Escape exits zoom (pops out one level, since you can zoom repeatedly)
    // The zoomOut: IBAction doesn't get performed by shortcut, I guess because Esc is not a
    // valid shortcut. So we do it here.
    [[_delegate realParentWindow] replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
    DLog(@"Special handler: ZOOM OUT");
    return YES;
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
    const unichar characterIgnoringModifiers = [event.charactersIgnoringModifiers length] > 0 ? [event.charactersIgnoringModifiers characterAtIndex:0] : 0;
    const NSEventModifierFlags modifiers = event.it_modifierFlags;

    // Check if we have a custom key mapping for this event
    NSString *keyBindingText;
    int keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:characterIgnoringModifiers
                                                  modifiers:modifiers
                                                       text:&keyBindingText
                                                keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];

    if (keyBindingAction < 0) {
        return NO;
    }
    DLog(@"PTYSession keyDown action=%d", keyBindingAction);
    // A special action was bound to this key combination.
    NSString *temp;
    int profileAction = [iTermKeyBindingMgr localActionForKeyCode:characterIgnoringModifiers
                                                        modifiers:modifiers
                                                             text:&temp
                                                      keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];
    [self maybeWarnAboutOutdatedKeyBindingAction:keyBindingAction
                                         modflag:modifiers
                                   profileAction:profileAction
                                    unmodunicode:characterIgnoringModifiers];
    [self performKeyBindingAction:keyBindingAction parameter:keyBindingText event:event];

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
        NSBeep();
    }
}


- (NSData *)backspaceData {
    NSString *keyBindingText;
    int keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:0x7f
                                                      modifiers:0
                                                           text:&keyBindingText
                                                    keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];
    char del = 0x7f;
    NSData *data = nil;
    switch (keyBindingAction) {
        case KEY_ACTION_HEX_CODE:
            data = [self dataForHexCodes:keyBindingText];
            break;

        case KEY_ACTION_TEXT:
            data = [keyBindingText dataUsingEncoding:self.encoding];
            break;

        case KEY_ACTION_VIM_TEXT:
            data = [[keyBindingText stringByExpandingVimSpecialCharacters] dataUsingEncoding:self.encoding];
            break;

        case KEY_ACTION_ESCAPE_SEQUENCE:
            data = [[@"\e" stringByAppendingString:keyBindingText] dataUsingEncoding:self.encoding];
            break;

        case KEY_ACTION_SEND_C_H_BACKSPACE:
            data = [@"\010" dataUsingEncoding:self.encoding];
            break;

        case KEY_ACTION_SEND_C_QM_BACKSPACE:
            data = [@"\177" dataUsingEncoding:self.encoding];
            break;

        case -1:
            data = [NSData dataWithBytes:&del length:1];
            break;

        default:
            data = nil;
            break;
    }

    return data;
}

- (BOOL)hasActionableKeyMappingForEvent:(NSEvent *)event
{
    int keyBindingAction = [self _keyBindingActionForEvent:event];
    return (keyBindingAction >= 0) && (keyBindingAction != KEY_ACTION_DO_NOT_REMAP_MODIFIERS) && (keyBindingAction != KEY_ACTION_REMAP_LOCALLY);
}

- (int)optionKey
{
    return [[[self profile] objectForKey:KEY_OPTION_KEY_SENDS] intValue];
}

- (int)rightOptionKey
{
    NSNumber* rightOptPref = [[self profile] objectForKey:KEY_RIGHT_OPTION_KEY_SENDS];
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
    } else if (!_terminal.bracketedPasteMode) {
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
                 tabTransform:tabTransform
                 spacesPerTab:spacesPerTab];
}

// Pastes the current string in the clipboard. Uses the sender's tag to get flags.
- (void)paste:(id)sender {
    DLog(@"PTYSession paste:");
    
    // If this class is used in a non-iTerm2 app (as a library), we might not
    // be called from a menu item so just use no flags in this case.
    [self pasteString:[PTYSession pasteboardString] flags:[sender isKindOfClass:NSMenuItem.class] ? [sender tag] : 0];
}

// Show advanced paste window.
- (IBAction)pasteOptions:(id)sender {
    [_pasteHelper showPasteOptionsInWindow:_delegate.realParentWindow.window
                         bracketingEnabled:_terminal.bracketedPasteMode];
}

- (void)textViewFontDidChange
{
    if ([self isTmuxClient]) {
        [self notifyTmuxFontChange];
    }
    [_view updateScrollViewFrame];
    if (@available(macOS 10.11, *)) {
        [self updateMetalDriver];
    }
}

- (BOOL)textViewHasBackgroundImage {
    return _backgroundImage != nil;
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
- (void)textViewDrawBackgroundImageInView:(NSView *)view
                                 viewRect:(NSRect)dirtyRect
                   blendDefaultBackground:(BOOL)blendDefaultBackground {
    if (!_backgroundDrawingHelper) {
        _backgroundDrawingHelper = [[iTermBackgroundDrawingHelper alloc] init];
        _backgroundDrawingHelper.delegate = self;
    }
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        NSRect contentRect = self.view.contentRect;
        [_backgroundDrawingHelper drawBackgroundImageInView:view
                                                  container:self.view
                                                  dirtyRect:dirtyRect
                                     visibleRectInContainer:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)
                                     blendDefaultBackground:blendDefaultBackground
                                                       flip:NO];
    } else {
        NSView *container = [self.delegate sessionContainerView:self];
        NSRect clippedDirtyRect = NSIntersectionRect(dirtyRect, view.enclosingScrollView.documentVisibleRect);;
        if (@available(macOS 10.14, *)) {} else {
            if (view == self.view) {
                clippedDirtyRect = dirtyRect;
            }
        }
        NSRect windowVisibleRect = [self.view insetRect:container.bounds
                                                flipped:YES
                                 includeBottomStatusBar:![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]];
        [_backgroundDrawingHelper drawBackgroundImageInView:view
                                                  container:container
                                                  dirtyRect:clippedDirtyRect
                                     visibleRectInContainer:windowVisibleRect
                                     blendDefaultBackground:blendDefaultBackground
                                                       flip:YES];
    }
}

- (CGRect)textViewRelativeFrame {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return CGRectMake(0, 0, 1, 1);
    }
    NSView *container = [self.delegate sessionContainerView:self];
    const NSRect sessionViewFrameInContainer = [container convertRect:self.view.bounds fromView:self.view];
    NSRect viewRect = [self.view insetRect:sessionViewFrameInContainer
                                   flipped:YES
                    includeBottomStatusBar:YES];
    BOOL includeBottomStatusBar = YES;
    if (@available(macOS 10.14, *)) {
        includeBottomStatusBar = ![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane];
    }
    NSRect containerBounds = [self.view insetRect:container.bounds
                                          flipped:YES
                           includeBottomStatusBar:includeBottomStatusBar];
    viewRect.origin.x -= containerBounds.origin.x;
    viewRect.origin.y -= containerBounds.origin.y;

    return CGRectMake(viewRect.origin.x / containerBounds.size.width,
                      viewRect.origin.y / containerBounds.size.height,
                      viewRect.size.width / containerBounds.size.width,
                      viewRect.size.height / containerBounds.size.height);
}

- (CGRect)textViewContainerRect {
    if ([iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        return self.view.scrollview.frame;
    }
    NSView *container = [self.delegate sessionContainerView:self];
    return [self.view insetRect:container.bounds
                        flipped:YES
         includeBottomStatusBar:![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]];
}

- (NSImage *)textViewBackgroundImage {
    return _backgroundImage;
}

- (NSColor *)processedBackgroundColor {
    NSColor *unprocessedColor = [_colorMap colorForKey:kColorMapBackground];
    return [_colorMap processedBackgroundColorForBackgroundColor:unprocessedColor];
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

- (NSStringEncoding)textViewEncoding
{
    return [self encoding];
}

- (NSString *)textViewCurrentWorkingDirectory {
    return [_shell getWorkingDirectory];
}

- (NSURL *)textViewCurrentLocation {
    VT100RemoteHost *host = [self currentHost];
    NSString *path = _lastDirectory ?: [_shell getWorkingDirectory];
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
    if (_commandRange.start.x < 0) {
        // Not at a command prompt; no restrictions.
        *verticalOk = YES;
        return YES;
    } else {
        // At the command prompt. Ok to move to any char within current command, but no up or down
        // arrows please.
        NSComparisonResult order = VT100GridCoordOrder(VT100GridCoordRangeMin(_commandRange),
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
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    if (guid) {
        profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    }
    [[_delegate realParentWindow] splitVertically:vertically
                                     withBookmark:profile
                                    targetSession:self
                                      synchronous:NO];
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

- (void)textViewPasteSpecialWithStringConfiguration:(NSString *)configuration
                                      fromSelection:(BOOL)fromSelection {
    NSString *string = fromSelection ? [[iTermController sharedInstance] lastSelection] : [NSString stringFromPasteboard];
    [_pasteHelper pasteString:string
                 stringConfig:configuration];
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
    NSString *string = [[iTermController sharedInstance] lastSelection];
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
    [_delegate setActiveSession:self];
    [_view setNeedsDisplay:YES];
    [_view.findDriver owningViewDidBecomeFirstResponder];
}

- (void)textViewDidResignFirstResponder {
    [_view setNeedsDisplay:YES];
}

- (BOOL)textViewReportMouseEvent:(NSEventType)eventType
                       modifiers:(NSUInteger)modifiers
                          button:(MouseButtonNumber)button
                      coordinate:(VT100GridCoord)coord
                          deltaY:(CGFloat)deltaY {
    DLog(@"Report event type %lu, modifiers=%lu, button=%d, coord=%@",
         (unsigned long)eventType, (unsigned long)modifiers, button,
         VT100GridCoordDescription(coord));

    switch (eventType) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown:
            switch ([_terminal mouseMode]) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    _reportingMouseDown = YES;
                    _lastReportedCoord = coord;
                    [self writeLatin1EncodedData:[_terminal.output mousePress:button
                                                                withModifiers:modifiers
                                                                           at:coord]
                                broadcastAllowed:NO];
                    return YES;

                case MOUSE_REPORTING_NONE:
                case MOUSE_REPORTING_HIGHLIGHT:
                    break;
            }
            break;

        case NSEventTypeLeftMouseUp:
        case NSEventTypeRightMouseUp:
        case NSEventTypeOtherMouseUp:
            if (_reportingMouseDown) {
                _reportingMouseDown = NO;
                _lastReportedCoord = VT100GridCoordMake(-1, -1);

                switch ([_terminal mouseMode]) {
                    case MOUSE_REPORTING_NORMAL:
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        _lastReportedCoord = coord;
                        [self writeLatin1EncodedData:[_terminal.output mouseRelease:button
                                                                      withModifiers:modifiers
                                                                                 at:coord]
                                    broadcastAllowed:NO];
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HIGHLIGHT:
                        break;
                }
            }
            break;


        case NSEventTypeMouseMoved:
            if ([_terminal mouseMode] == MOUSE_REPORTING_ALL_MOTION &&
                !VT100GridCoordEquals(coord, _lastReportedCoord)) {
                _lastReportedCoord = coord;
                [self writeLatin1EncodedData:[_terminal.output mouseMotion:MOUSE_BUTTON_NONE
                                                             withModifiers:modifiers
                                                                        at:coord]
                            broadcastAllowed:NO];
                return YES;
            }
            break;

        case NSEventTypeLeftMouseDragged:
        case NSEventTypeRightMouseDragged:
        case NSEventTypeOtherMouseDragged:
            if (_reportingMouseDown &&
                !VT100GridCoordEquals(coord, _lastReportedCoord)) {
                _lastReportedCoord = coord;

                switch ([_terminal mouseMode]) {
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        [self writeLatin1EncodedData:[_terminal.output mouseMotion:button
                                                                     withModifiers:modifiers
                                                                                at:coord]
                                    broadcastAllowed:NO];
                        // Fall through
                    case MOUSE_REPORTING_NORMAL:
                        // Don't do selection when mouse reporting during a drag, even if the drag
                        // is not reported (the clicks are).
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HIGHLIGHT:
                        break;
                }
            }
            break;

        case NSEventTypeScrollWheel:
            switch ([_terminal mouseMode]) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    if (deltaY != 0) {
                        int steps;
                        if ([iTermAdvancedSettingsModel proportionalScrollWheelReporting]) {
                            // Cap number of reported scroll events at 32 to prevent runaway redraws.
                            // This is a mostly theoretical concern and the number can grow if it
                            // doesn't seem to be a problem.
                            steps = MIN(32, fabs(deltaY));
                        } else {
                            steps = 1;
                        }
                        if (steps == 1 && [iTermAdvancedSettingsModel doubleReportScrollWheel]) {
                            // This works around what I believe is a bug in tmux or a bug in
                            // how users use tmux. See the thread on tmux-users with subject
                            // "Mouse wheel events and server_client_assume_paste--the perfect storm of bugs?".
                            steps = 2;
                        }
                        for (int i = 0; i < steps; i++) {
                            [self writeLatin1EncodedData:[_terminal.output mousePress:button
                                                                        withModifiers:modifiers
                                                                                   at:coord]
                                        broadcastAllowed:NO];
                        }
                    }
                    // If deltaY is 0 we still return YES because the
                    // scrollview moves anyway (likely because our caller is
                    // not using the high-precision wheel API).
                    return YES;

                case MOUSE_REPORTING_NONE:
                case MOUSE_REPORTING_HIGHLIGHT:
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
        [iTermShellHistoryController showInformationalMessage];
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
        [iTermShellHistoryController showInformationalMessage];
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    } else {
        VT100GridAbsCoordRange range;
        iTermTextExtractorTrimTrailingWhitespace trailing;
        if (self.isAtShellPrompt) {
            range = VT100GridAbsCoordRangeMake(_commandRange.start.x,
                                               _commandRange.start.y + _screen.totalScrollbackOverflow,
                                               _commandRange.end.x,
                                               _commandRange.end.y + _screen.totalScrollbackOverflow);
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
    return _screen.normalization;
}

- (NSColor *)textViewCursorGuideColor {
    return _cursorGuideColor;
}

- (NSColor *)textViewBadgeColor {
    return [[iTermProfilePreferences objectForKey:KEY_BADGE_COLOR inProfile:_profile] colorValue];
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

- (BOOL)textViewSuppressingAllOutput {
    return _suppressAllOutput;
}

- (BOOL)textViewIsZoomedIn {
    return _liveSession && !_dvr;
}

- (BOOL)textViewShouldShowMarkIndicators {
    return [iTermProfilePreferences boolForKey:KEY_SHOW_MARK_INDICATORS inProfile:_profile];
}

- (void)textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:(BOOL)isTrying {
    static NSString *const kIdentifier = @"AskAboutAlternateMouseScroll";
    if (!isTrying) {
        [self dismissAnnouncementWithIdentifier:kIdentifier];
        return;
    }
    static NSString *const kNeverAskAboutAltMouseScroll = @"NoSyncNeverAskAboutSettingAlternateMouseScroll";
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kNeverAskAboutAltMouseScroll]) {
        return;
    }
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:@"Do you want the scroll wheel to move the cursor in interactive programs like this?"
                                                         style:kiTermAnnouncementViewStyleQuestion
                                                   withActions:@[ @"Yes", @"Don‘t Ask Again" ]
                                                    completion:^(int selection) {
                                                        switch (selection) {
                                                            case -2:  // Dismiss programmatically
                                                                break;

                                                            case -1: // No
                                                                break;

                                                            case 0: // Yes
                                                                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"AlternateMouseScroll"];
                                                                break;

                                                            case 1: { // Never
                                                                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kNeverAskAboutAltMouseScroll];
                                                                break;
                                                            }
                                                        }
                                                    }];
    [self queueAnnouncement:announcement identifier:kIdentifier];
}

// Grow or shrink the height of the frame if the number of lines in the data
// source + IME has changed.
- (void)textViewResizeFrameIfNeeded {
    // Check if the frame size needs to grow or shrink.
    NSRect frame = [_textview frame];
    const CGFloat desiredHeight = _textview.desiredHeight;
    if (fabs(desiredHeight - NSHeight(frame)) >= 0.5) {
        // Update the wrapper's size, which in turn updates textview's size.
        frame.size.height = desiredHeight + [iTermAdvancedSettingsModel terminalVMargin];  // The wrapper is always larger by VMARGIN.
        _wrapper.frame = frame;

        NSAccessibilityPostNotification(_textview,
                                        NSAccessibilityRowCountChangedNotification);
    }
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

- (void)textViewBackgroundColorDidChange {
    [_delegate sessionBackgroundColorDidChange:self];
    [_delegate sessionUpdateMetalAllowed];
    [_statusBarViewController updateColors];
    [self.view setNeedsDisplay:YES];
}

- (void)textViewBurySession {
    [self bury];
}

- (void)textViewShowHoverURL:(NSString *)url {
    [_view setHoverURL:url];
}

- (BOOL)textViewCopyMode {
    return _copyModeHandler.enabled;
}

- (BOOL)textViewCopyModeSelecting {
    return _copyModeHandler.state.selecting;
}

- (VT100GridCoord)textViewCopyModeCursorCoord {
    return _copyModeHandler.state.coord;
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
    if (_copyModeHandler.enabled) {
        _copyModeHandler.state.coord = range.start;
        _copyModeHandler.state.start = range.end;
        [self.textview setNeedsDisplay:YES];
    }
}

- (void)textViewNeedsDisplayInRect:(NSRect)rect {
    if (@available(macOS 10.11, *)) {
        NSRect visibleRect = NSIntersectionRect(rect, _textview.enclosingScrollView.documentVisibleRect);
        [_view setMetalViewNeedsDisplayInTextViewRect:visibleRect];
    }
}

- (BOOL)textViewShouldDrawRect {
    if (@available(macOS 10.11, *)) {
        return !_textview.suppressDrawing;
    } else {
        return YES;
    }
}

- (void)textViewDidHighlightMark {
    if (self.useMetal) {
        [_textview setNeedsDisplay:YES];
    }
}

- (NSEdgeInsets)textViewEdgeInsets {
    NSEdgeInsets insets;
    const NSRect innerFrame = _view.scrollview.frame;
    const NSSize containerSize = _view.contentRect.size;

    insets.bottom = NSMinY(innerFrame);
    insets.top = containerSize.height - NSMaxY(innerFrame);
    insets.left = NSMinX(innerFrame);
    insets.right = containerSize.width - NSMaxX(innerFrame);

    return insets;
}

- (BOOL)textViewInInteractiveApplication {
    return _terminal.softAlternateScreenMode;
}

- (BOOL)textViewTerminalStateForMenuItem:(NSMenuItem *)menuItem {
    switch (menuItem.tag) {
        case 1:
            return _screen.showingAlternateScreen;

        case 2:
            return _terminal.reportFocus;
            break;

        case 3:
            return _terminal.mouseMode != MOUSE_REPORTING_NONE;

        case 4:
            return _terminal.bracketedPasteMode;

        case 5:
            return _terminal.cursorMode;

        case 6:
            return _terminal.keypadMode;
    }

    return NO;
}

- (void)textViewToggleTerminalStateForMenuItem:(NSMenuItem *)menuItem {
    switch (menuItem.tag) {
        case 1:
            [_screen toggleAlternateScreen];
            break;

        case 2:
            _terminal.reportFocus = !_terminal.reportFocus;
            break;

        case 3:
            if (_terminal.mouseMode == MOUSE_REPORTING_NONE) {
                _terminal.mouseMode = _terminal.previousMouseMode;
            } else {
                _terminal.mouseMode = MOUSE_REPORTING_NONE;
            }
            [_terminal.delegate terminalMouseModeDidChangeTo:_terminal.mouseMode];
            break;

        case 4:
            _terminal.bracketedPasteMode = !_terminal.bracketedPasteMode;
            break;

        case 5:
            _terminal.cursorMode = !_terminal.cursorMode;
            break;

        case 6:
            [_terminal forceSetKeypadMode:!_terminal.keypadMode];
            break;
            
    }
}

- (void)textViewResetTerminal {
    [_terminal gentleReset];
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

- (void)bury {
    if (self.isTmuxClient) {
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
                    broadcastAllowed:YES];
    }
}

- (void)sendText:(NSString *)text
{
    if (_exited) {
        return;
    }
    if ([text length] > 0) {
        NSString *temp = text;
        temp = [temp stringByReplacingEscapedChar:'n' withString:@"\n"];
        temp = [temp stringByReplacingEscapedChar:'e' withString:@"\e"];
        temp = [temp stringByReplacingEscapedChar:'a' withString:@"\a"];
        temp = [temp stringByReplacingEscapedChar:'t' withString:@"\t"];
        [self writeTask:temp];
    }
}

- (void)launchCoprocessWithCommand:(NSString *)command
{
    [self launchCoprocessWithCommand:command mute:NO];
}

- (void)uploadFiles:(NSArray *)localFilenames toPath:(SCPPath *)destinationPath
{
    SCPFile *previous = nil;
    for (NSString *file in localFilenames) {
        SCPFile *scpFile = [[[SCPFile alloc] init] autorelease];
        scpFile.path = [[[SCPPath alloc] init] autorelease];
        scpFile.path.hostname = destinationPath.hostname;
        scpFile.path.username = destinationPath.username;
        NSString *filename = [file lastPathComponent];
        scpFile.path.path = [destinationPath.path stringByAppendingPathComponent:filename];
        scpFile.localPath = file;

        if (previous) {
            previous.successor = scpFile;
        }
        previous = scpFile;
        [scpFile upload];
    }
}

- (void)startDownloadOverSCP:(SCPPath *)path
{
    SCPFile *file = [[[SCPFile alloc] init] autorelease];
    file.path = path;
    [file download];
}

- (NSString *)localeForLanguage:(NSString *)languageCode
                        country:(NSString *)countryCode {
    DLog(@"localeForLanguage:country: languageCode=%@, countryCode=%@", languageCode, countryCode);
    if (languageCode && countryCode) {
        return [NSString stringWithFormat:@"%@_%@", languageCode, countryCode];
    } else if (languageCode) {
        return languageCode;
    } else {
        return [[NSLocale currentLocale] localeIdentifier];
    }
}

- (NSArray<NSString *> *)preferredLanguageCodesByRemovingCountry {
    return [[NSLocale preferredLanguages] mapWithBlock:^id(NSString *language) {
        DLog(@"Found preferred language: %@", language);
        NSUInteger index = [language rangeOfString:@"-" options:0].location;
        if (index == NSNotFound) {
            return language;
        } else {
            return [language substringToIndex:index];
        }
    }];
}

- (NSArray<NSString *> *)languageCodesUpToAndIncludingFirstTwoLetterCode:(NSArray<NSString *> *)allCodes {
    NSInteger lastIndexToInclude = [allCodes indexOfObjectPassingTest:^BOOL(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.length <= 2;
    }];
    if (lastIndexToInclude == NSNotFound) {
        return allCodes;
    }
    return [allCodes subarrayToIndex:lastIndexToInclude + 1];
}

- (NSString *)valueForLanguageEnvironmentVariable {
    DLog(@"Looking for a locale...");
    DLog(@"Preferred languages are: %@", [NSLocale preferredLanguages]);
    NSArray<NSString *> *languageCodes = [self languageCodesUpToAndIncludingFirstTwoLetterCode:[self preferredLanguageCodesByRemovingCountry]];
    DLog(@"Considering these languages: %@", languageCodes);

    NSString *const countryCode = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    NSArray<NSString *> *languagePlusCountryCodes = @[];
    if (countryCode) {
        languagePlusCountryCodes = [languageCodes mapWithBlock:^id(NSString *language) {
            return [self localeForLanguage:language country:countryCode];
        }];
    }
    DLog(@"Country code is %@. Combos are %@", countryCode, languagePlusCountryCodes);

    NSString *encoding = [self encodingName];
    NSArray<NSString *> *languageCountryEncoding = @[];
    if (encoding) {
        languageCountryEncoding = [languagePlusCountryCodes mapWithBlock:^id(NSString *languageCountry) {
            return [NSString stringWithFormat:@"%@.%@", languageCountry, encoding];
        }];
    }
    DLog(@"Encoding is %@. Combos are %@", encoding, languageCountryEncoding);

    NSArray<NSString *> *candidates = [@[ languageCountryEncoding, languagePlusCountryCodes, languageCodes ] flattenedArray];
    DLog(@"Candidates are: %@", candidates);
    for (NSString *candidate in candidates) {
        DLog(@"Check if %@ is supported", candidate);
        if ([self _localeIsSupported:candidate]) {
            DLog(@"YES. Using %@", candidate);
            return candidate;
        }
        DLog(@"No");
    }
    return nil;
}

- (void)setDvrFrame {
    screen_char_t* s = (screen_char_t*)[_dvrDecoder decodedFrame];
    int len = [_dvrDecoder length];
    DVRFrameInfo info = [_dvrDecoder info];
    if (info.width != [_screen width] || info.height != [_screen height]) {
        if (![_liveSession isTmuxClient]) {
            [[_delegate realParentWindow] sessionInitiatedResize:self
                                                           width:info.width
                                                          height:info.height];
        }
    }
    [_screen setFromFrame:s len:len info:info];
    [[_delegate realParentWindow] clearTransientTitle];
    [[_delegate realParentWindow] setWindowTitle];
}

- (void)continueTailFind
{
    NSMutableArray *results = [NSMutableArray array];
    BOOL more;
    more = [_screen continueFindAllResults:results
                                 inContext:_tailFindContext];
    for (SearchResult *r in results) {
        [_textview addSearchResult:r];
    }
    if ([results count]) {
        [_textview setNeedsDisplay:YES];
    }
    if (more) {
        _tailFindTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                          target:self
                                                        selector:@selector(continueTailFind)
                                                        userInfo:nil
                                                         repeats:NO];
    } else {
        // Update the saved position to just before the screen.
        [_screen storeLastPositionInLineBufferAsFindContextSavedPosition];
        _tailFindTimer = nil;
    }
}

- (void)beginTailFind {
    FindContext *findContext = [_textview findContext];
    if (!findContext.substring) {
        return;
    }
    [_screen setFindString:findContext.substring
          forwardDirection:YES
                      mode:findContext.mode
               startingAtX:0
               startingAtY:0
                withOffset:0
                 inContext:_tailFindContext
           multipleResults:YES];

    // Set the starting position to the block & offset that the backward search
    // began at. Do a forward search from that location.
    [_screen restoreSavedPositionToFindContext:_tailFindContext];
    [self continueTailFind];
}

- (void)sessionContentsChanged:(NSNotification *)notification {
    if (!_tailFindTimer &&
        [notification object] == self &&
        [_delegate sessionBelongsToVisibleTab]) {
        [self beginTailFind];
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
    if (_exited) {
        return;
    }
    screen_char_t savedFgColor = [_terminal foregroundColorCode];
    screen_char_t savedBgColor = [_terminal backgroundColorCode];
    [_terminal setForegroundColor:ALTSEM_DEFAULT
               alternateSemantics:YES];
    [_terminal setBackgroundColor:ALTSEM_DEFAULT
               alternateSemantics:YES];
    [_screen appendStringAtCursor:message];
    [_screen crlf];
    [_terminal setForegroundColor:savedFgColor.foregroundColor
               alternateSemantics:savedFgColor.foregroundColorMode == ColorModeAlternate];
    [_terminal setBackgroundColor:savedBgColor.backgroundColor
               alternateSemantics:savedBgColor.backgroundColorMode == ColorModeAlternate];
}

- (void)printTmuxCommandOutputToScreen:(NSString *)response
{
    for (NSString *aLine in [response componentsSeparatedByString:@"\n"]) {
        aLine = [aLine stringByReplacingOccurrencesOfString:@"\r" withString:@""];
        [self printTmuxMessage:aLine];
    }
}

- (BOOL)_localeIsSupported:(NSString*)theLocale
{
    // Keep a copy of the current locale setting for this process
    char* backupLocale = setlocale(LC_CTYPE, NULL);

    // Try to set it to the proposed locale
    BOOL supported;
    if (setlocale(LC_CTYPE, [theLocale UTF8String])) {
        supported = YES;
    } else {
        supported = NO;
    }

    // Restore locale and return
    setlocale(LC_CTYPE, backupLocale);
    return supported;
}

#pragma mark - VT100ScreenDelegate

- (NSString *)screenSessionGuid {
    return self.guid;
}

- (void)screenScheduleRedrawSoon {
    self.active = YES;
}

- (void)screenNeedsRedraw {
    [self refresh];
    [_textview updateNoteViewFrames];
    [_textview setNeedsDisplay:YES];
}

- (void)screenUpdateDisplay:(BOOL)redraw {
    [self updateDisplayBecause:[NSString stringWithFormat:@"screen requested update redraw=%@", @(redraw)]];
    if (redraw) {
        [_textview setNeedsDisplay:YES];
    }
}

- (void)screenSizeDidChange {
    [self updateScroll];
    [_textview updateNoteViewFrames];
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionColumns: @(_screen.width),
                                                    iTermVariableKeySessionRows: @(_screen.height) }];
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (void)screenTriggerableChangeDidOccur {
    [self clearTriggerLine];
}

- (void)screenDidReset {
    [self loadInitialColorTable];
    _cursorGuideSettingHasChanged = NO;
    _textview.highlightCursorLine = [iTermProfilePreferences boolForKey:KEY_USE_CURSOR_GUIDE
                                                              inProfile:_profile];
    [_textview setNeedsDisplay:YES];
    _screen.trackCursorLineMovement = NO;
}

- (void)screenDidAppendStringToCurrentLine:(NSString *)string {
    [self appendStringToTriggerLine:string];
}

- (void)screenDidAppendAsciiDataToCurrentLine:(AsciiData *)asciiData {
    if ([_triggers count]) {
        NSString *string = [[[NSString alloc] initWithBytes:asciiData->buffer
                                                     length:asciiData->length
                                                   encoding:NSASCIIStringEncoding] autorelease];
        [self screenDidAppendStringToCurrentLine:string];
    }
}

- (void)screenSetCursorType:(ITermCursorType)type {
    if (type == CURSOR_DEFAULT) {
        type = [iTermProfilePreferences intForKey:KEY_CURSOR_TYPE inProfile:_profile];
    }
    [self setSessionSpecificProfileValues:@{ KEY_CURSOR_TYPE : @(type) }];
}

- (void)screenSetCursorBlinking:(BOOL)blink {
    [[self textview] setBlinkingCursor:blink];
}

- (BOOL)screenShouldInitiateWindowResize {
    return ![[[self profile] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue];
}

- (void)screenResizeToWidth:(int)width height:(int)height {
    [_delegate sessionInitiatedResize:self width:width height:height];
}

- (void)screenResizeToPixelWidth:(int)width height:(int)height {
    [[_delegate realParentWindow] setFrameSize:NSMakeSize(width, height)];
}

- (BOOL)screenShouldBeginPrinting {
    if (!_printGuard) {
        _printGuard = [[iTermPrintGuard alloc] init];
    }
    return [_printGuard shouldPrintWithProfile:self.profile inWindow:self.view.window];
}

- (void)screenSetWindowTitle:(NSString *)title {
    // The window name doesn't normally serve as an interpolated string, but just to be extra safe
    // break up \(.
    title = [title stringByReplacingOccurrencesOfString:@"\\(" withString:@"\\\u200B("];
    [self.variablesScope setValue:title forVariableNamed:iTermVariableKeySessionWindowName];
    [_tmuxTitleMonitor updateOnce];
}

- (NSString *)screenWindowTitle {
    return [self windowTitle];
}

- (NSString *)screenIconTitle {
    return [self.variablesScope valueForVariableName:iTermVariableKeySessionIconName] ?: [self.variablesScope valueForVariableName:iTermVariableKeySessionName];
}

- (void)screenSetIconName:(NSString *)theName {
    // Put a zero-width space in between \ and ( to avoid interpolated strings coming from the server.
    theName = [theName stringByReplacingOccurrencesOfString:@"\\(" withString:@"\\\u200B("];
    [self.variablesScope setValuesFromDictionary:@{ iTermVariableKeySessionAutoNameFormat: theName ?: [NSNull null],
                                                    iTermVariableKeySessionIconName: theName ?: [NSNull null] }];
    [_tmuxTitleMonitor updateOnce];
    
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

- (NSPoint)screenWindowTopLeftPixelCoordinate {
    NSRect frame = [self screenWindowFrame];
    NSRect screenFrame = [self screenWindowScreenFrame];
    return NSMakePoint(frame.origin.x - screenFrame.origin.x,
                       (screenFrame.origin.y + screenFrame.size.height) - (frame.origin.y + frame.size.height));
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

- (void)screenWriteDataToTask:(NSData *)data {
    [self writeLatin1EncodedData:data broadcastAllowed:NO];
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
- (void)screenPopCurrentTitleForWindow:(BOOL)flag {
    if (flag) {
        [self popWindowTitle];
    } else {
        [self popIconTitle];
    }
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

- (BOOL)screenInTmuxMode {
    return [self isTmuxClient];
}

- (BOOL)screenShouldTreatAmbiguousCharsAsDoubleWidth {
    return [self treatAmbiguousWidthAsDoubleWidth];
}

- (void)screenDidChangeNumberOfScrollbackLines {
    [_textview updateNoteViewFrames];
}

- (void)screenShowBellIndicator {
    [self setBell:YES];
}

- (void)screenPrintString:(NSString *)string {
    [[self textview] printContent:string];
}

- (void)screenPrintVisibleArea {
    [[self textview] print:nil];
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

- (void)screenDidClearScrollbackBuffer:(VT100Screen *)screen {
    [_delegate sessionDidClearScrollbackBuffer:self];
}

- (void)screenClearHighlights {
    [_textview clearHighlights:NO];
}

- (void)screenMouseModeDidChange {
    [_textview updateCursor:nil];
    [_textview updateTrackingAreas];
    [self.variablesScope setValue:@(_terminal.mouseMode)
                 forVariableNamed:iTermVariableKeySessionMouseReportingMode];
}

- (void)screenFlashImage:(NSString *)identifier {
    [_textview beginFlash:identifier];
}

- (void)screenIncrementBadge {
    [[_delegate realParentWindow] incrementBadge];
}

- (NSString *)screenCurrentWorkingDirectory {
    return [_shell getWorkingDirectory];
}

- (void)screenSetCursorVisible:(BOOL)visible {
    _textview.cursorVisible = visible;
}

- (void)screenCursorDidMoveToLine:(int)line {
    if (_textview.cursorVisible) {
        [_textview setNeedsDisplayOnLine:line];
    }
}

- (void)screenSetHighlightCursorLine:(BOOL)highlight {
    _cursorGuideSettingHasChanged = YES;
    self.highlightCursorLine = highlight;
}

- (void)setHighlightCursorLine:(BOOL)highlight {
    _cursorGuideSettingHasChanged = YES;
    _textview.highlightCursorLine = highlight;
    [_textview setNeedsDisplay:YES];
    _screen.trackCursorLineMovement = highlight;
}

- (BOOL)highlightCursorLine {
    return _textview.highlightCursorLine;
}

- (BOOL)screenHasView {
    return _textview != nil;
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
    [_delegate setActiveSession:self];
}

- (id)markAddedAtLine:(int)line ofClass:(Class)markClass {
    DLog(@"Session %@ calling refresh", self);
    [_textview refresh];  // In case text was appended
    if ([_lastMark isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *screenMark = (VT100ScreenMark *)_lastMark;
        if (screenMark.command && !screenMark.endDate) {
            screenMark.endDate = [NSDate date];
        }
    }
    [_lastMark release];
    _lastMark = [[_screen addMarkStartingAtAbsoluteLine:[_screen totalScrollbackOverflow] + line
                                                oneLine:YES
                                                ofClass:markClass] retain];
    self.currentMarkOrNotePosition = _lastMark.entry.interval;
    if (self.alertOnNextMark) {
        NSString *action = [iTermApplication.sharedApplication delegate].markAlertAction;
        if ([action isEqualToString:kMarkAlertActionPostNotification]) {
            [[iTermNotificationController sharedInstance] notify:@"Mark Set"
                                                 withDescription:[NSString stringWithFormat:@"Session %@ #%d had a mark set.",
                                                                  [self name],
                                                                  [_delegate tabNumber]]
                                                     windowIndex:[self screenWindowIndex]
                                                        tabIndex:[self screenTabIndex]
                                                       viewIndex:[self screenViewIndex]
                                                          sticky:YES];
        } else {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            alert.messageText = @"Alert";
            alert.informativeText = [NSString stringWithFormat:@"Mark set in session “%@.”", [self name]];
            [alert addButtonWithTitle:@"Reveal"];
            [alert addButtonWithTitle:@"OK"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                [self reveal];
            }
        }
        self.alertOnNextMark = NO;
    }
    return _lastMark;
}

- (void)screenPromptDidStartAtLine:(int)line {
    DLog(@"FinalTerm: prompt started on line %d. Add a mark there. Save it as lastPromptLine.", line);
    // Reset this in case it's taking the "real" shell integration path.
    _fakePromptDetectedAbsLine = -1;
    _lastPromptLine = (long long)line + [_screen totalScrollbackOverflow];
    VT100ScreenMark *mark = [self screenAddMarkOnLine:line];
    [mark setIsPrompt:YES];
    mark.promptRange = VT100GridAbsCoordRangeMake(0, _lastPromptLine, 0, _lastPromptLine);
    [_pasteHelper unblock];
}


- (void)triggerDidDetectStartOfPromptAt:(VT100GridAbsCoord)coord {
    DLog(@"Trigger detected start of prompt");
    if (_fakePromptDetectedAbsLine == -2) {
        // Infer the end of the preceding command. Set a return status of 0 since we don't know what it was.
        [_screen terminalReturnCodeOfLastCommandWas:0];
    }
    // Use 0 here to avoid the screen inserting a newline.
    coord.x = 0;
    [_screen promptDidStartAt:coord];
    _fakePromptDetectedAbsLine = coord.y;
}

- (void)triggerDidDetectEndOfPromptAt:(VT100GridAbsCoord)coord {
    DLog(@"Trigger detected end of prompt");
    [_screen commandDidStartAt:coord];
}

- (void)didInferEndOfCommand {
    DLog(@"Inferring end of command");
    VT100GridAbsCoord coord;
    coord.x = 0;
    coord.y = _screen.currentGrid.cursor.y + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow;
    if (_screen.cursorX > 1) {
        // End of command was detected before the newline came in. This is the normal case.
        coord.y += 1;
    }
    if ([_screen commandDidEndAtAbsCoord:coord]) {
        _fakePromptDetectedAbsLine = -2;
    } else {
        // Screen didn't think we were in a command.
        _fakePromptDetectedAbsLine = -1;
    }
}

- (void)screenPromptDidEndAtLine:(int)line {
    VT100ScreenMark *mark = [_screen lastPromptMark];
    const int x = _screen.cursorX - 1;
    const long long y = (long long)line + [_screen totalScrollbackOverflow];
    mark.promptRange = VT100GridAbsCoordRangeMake(mark.promptRange.start.x,
                                                  mark.promptRange.end.y,
                                                  x,
                                                  y);
    mark.commandRange = VT100GridAbsCoordRangeMake(x, y, x, y);
    [_promptSubscriptions enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, ITMNotificationRequest * _Nonnull obj, BOOL * _Nonnull stop) {
        ITMNotification *notification = [[[ITMNotification alloc] init] autorelease];
        notification.promptNotification = [[[ITMPromptNotification alloc] init] autorelease];
        notification.promptNotification.session = self.guid;
        [[iTermAPIHelper sharedInstance] postAPINotification:notification
                                             toConnectionKey:key];
    }];
}

- (VT100ScreenMark *)screenAddMarkOnLine:(int)line {
    return (VT100ScreenMark *)[self markAddedAtLine:line ofClass:[VT100ScreenMark class]];
}

// Save the current scroll position
- (void)screenSaveScrollPosition
{
    DLog(@"Session %@ calling refresh", self);
    [_textview refresh];  // In case text was appended
    [_lastMark release];
    _lastMark = [[_screen addMarkStartingAtAbsoluteLine:[_textview absoluteScrollPosition]
                                                oneLine:NO
                                                ofClass:[VT100ScreenMark class]] retain];
    self.currentMarkOrNotePosition = _lastMark.entry.interval;
}

- (VT100ScreenMark *)markAddedAtCursorOfClass:(Class)theClass {
    return [self markAddedAtLine:[_screen numberOfScrollbackLines] + _screen.cursorY - 1
                         ofClass:theClass];
}

- (void)screenActivateWindow {
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)screenSetProfileToProfileNamed:(NSString *)value {
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
    // when switching to a profile that does have triggers.
    _lastPartialLineTriggerCheck = 0;
    [self clearTriggerLine];

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
        return;
    }
    [self profileDidChangeToProfileWithName:newProfile[KEY_NAME]];
}

- (void)screenSetPasteboard:(NSString *)value {
    if ([iTermPreferences boolForKey:kPreferenceKeyAllowClipboardAccessFromTerminal]) {
        if ([value isEqualToString:@"ruler"]) {
            [self setPasteboard:NSGeneralPboard];
        } else if ([value isEqualToString:@"find"]) {
            [self setPasteboard:NSFindPboard];
        } else if ([value isEqualToString:@"font"]) {
            [self setPasteboard:NSFontPboard];
        } else {
            [self setPasteboard:NSGeneralPboard];
        }
    } else {
        XLog(@"Clipboard access denied for CopyToClipboard");
    }
}

- (void)screenDidAddNote:(PTYNoteViewController *)note {
    [_textview addViewForNote:note];
    [_textview setNeedsDisplay:YES];
}

- (void)screenDidEndEditingNote {
    [_textview.window makeFirstResponder:_textview];
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

- (BOOL)screenIsAppendingToPasteboard {
    return _pasteboard != nil;
}

- (void)screenAppendDataToPasteboard:(NSData *)data {
    // Don't allow more than 100MB to be added to the pasteboard queue in case someone
    // forgets to send the EndCopy command.
    const int kMaxPasteboardBytes = 100 * 1024 * 1024;
    if ([_pbtext length] + data.length > kMaxPasteboardBytes) {
        [self setPasteboard:nil];
    }

    [_pbtext appendData:data];
}

- (void)screenWillReceiveFileNamed:(NSString *)filename ofSize:(int)size {
    [self.download stop];
    [self.download endOfData];
    self.download = [[[TerminalFileDownload alloc] initWithName:filename size:size] autorelease];
    [self.download download];
}

- (void)screenDidFinishReceivingFile {
    [self.download endOfData];
    self.download = nil;
}

- (void)screenDidFinishReceivingInlineFile {
    [self dismissAnnouncementWithIdentifier:@"AbortDownloadOnKeyPressAnnouncement"];
}

- (void)screenDidReceiveBase64FileData:(NSString *)data {
    [self.download appendData:data];
}

- (void)screenFileReceiptEndedUnexpectedly {
    [self.download stop];
    [self.download endOfData];
    self.download = nil;
}

- (void)screenRequestUpload:(NSString *)args {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;

    [panel beginSheetModalForWindow:_textview.window completionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            [self writeTaskNoBroadcast:@"ok\n" encoding:NSISOLatin1StringEncoding forceEncoding:YES];
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
            NSData *data = [NSData dataWithTGZContainingFiles:relativePaths relativeToPath:base error:&error];
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
            self.upload = [[[TerminalFileUpload alloc] initWithName:label size:base64String.length] autorelease];
            [self.upload upload];
            [_pasteHelper pasteString:base64String
                               slowly:NO
                     escapeShellChars:NO
                             isUpload:YES
                         tabTransform:kTabTransformNone
                         spacesPerTab:0
                             progress:^(NSInteger progress) {
                                 [self.upload didUploadBytes:progress];
                             }];
        } else {
            [self writeTaskNoBroadcast:@"abort\n" encoding:NSISOLatin1StringEncoding forceEncoding:YES];
        }
    }];
}

- (void)setAlertOnNextMark:(BOOL)alertOnNextMark {
    _alertOnNextMark = alertOnNextMark;
    [_textview setNeedsDisplay:YES];
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

- (void)screenDisinterSession {
    [[iTermBuriedSessions sharedInstance] restoreSession:self];
}

- (void)screenSetBackgroundImageFile:(NSString *)filename {
    DLog(@"screenSetbackgroundImageFile:%@", filename);
    filename = [[filename stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding] stringByTrimmingTrailingCharactersFromCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!filename.length) {
        DLog(@"Filename is empty. Reset the background image.");
        [self setSessionSpecificProfileValues:@{ KEY_BACKGROUND_IMAGE_LOCATION: [NSNull null] }];
        return;
    }
    if (!filename || ![[NSFileManager defaultManager] fileExistsAtPath:filename]) {
        DLog(@"file %@ does not exist", filename);
        return;
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    static NSString *kIdentifier = @"SetBackgroundImageFile";
    static NSString *kAllowedFilesKey = @"AlwaysAllowBackgroundImage";
    static NSString *kDeniedFilesKey = @"AlwaysDenyBackgroundImage";
    NSArray *allowedFiles = [userDefaults objectForKey:kAllowedFilesKey];
    NSArray *deniedFiles = [userDefaults objectForKey:kDeniedFilesKey];
    if ([deniedFiles containsObject:filename]) {
        return;
    }
    if ([allowedFiles containsObject:filename]) {
        [self setSessionSpecificProfileValues:@{ KEY_BACKGROUND_IMAGE_LOCATION: filename }];
        return;
    }


    NSString *title = [NSString stringWithFormat:@"Set background image to “%@”?", filename];
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcementWithTitle:title
                                                         style:kiTermAnnouncementViewStyleQuestion
                                                   withActions:@[ @"Yes", @"Always", @"Never" ]
                                                    completion:^(int selection) {
            switch (selection) {
                case -2:  // Dismiss programmatically
                    break;

                case -1: // No
                    break;

                case 0: // Yes
                    [self setSessionSpecificProfileValues:@{ KEY_BACKGROUND_IMAGE_LOCATION: filename }];
                    break;

                case 1: { // Always
                    NSArray *allowed = [userDefaults objectForKey:kAllowedFilesKey];
                    if (!allowed) {
                        allowed = @[];
                    }
                    allowed = [allowed arrayByAddingObject:filename];
                    [userDefaults setObject:allowed forKey:kAllowedFilesKey];
                    [self setSessionSpecificProfileValues:@{ KEY_BACKGROUND_IMAGE_LOCATION: filename }];
                    break;
                }
                case 2: {  // Never
                    NSArray *denied = [userDefaults objectForKey:kDeniedFilesKey];
                    if (!denied) {
                        denied = @[];
                    }
                    denied = [denied arrayByAddingObject:filename];
                    [userDefaults setObject:denied forKey:kDeniedFilesKey];
                    break;
                }
            }
        }];
    [self queueAnnouncement:announcement identifier:kIdentifier];
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
    iTermTuple *kvp = [kvpString keyValuePair];
    if (kvp) {
        NSString *key = [NSString stringWithFormat:@"user.%@", kvp.firstObject];
        [self.variablesScope setValue:[kvp.secondObject stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding]
                     forVariableNamed:key];
    } else {
        [self.variablesScope setValue:nil forVariableNamed:[NSString stringWithFormat:@"user.%@", kvpString]];
    }
}

- (void)setVariableNamed:(NSString *)name toValue:(id)newValue {
    [self.variablesScope setValue:newValue forVariableNamed:name];
}

- (void)injectData:(NSData *)data {
    VT100Parser *parser = [[[VT100Parser alloc] init] autorelease];
    parser.encoding = self.terminal.encoding;
    [parser putStreamData:data.bytes length:data.length];
    CVector vector;
    CVectorCreate(&vector, 100);
    [parser addParsedTokensToVector:&vector];
    if (CVectorCount(&vector) == 0) {
        CVectorDestroy(&vector);
        return;
    }
    [self executeTokens:&vector bytesHandled:data.length];
}

- (iTermColorMap *)screenColorMap {
    return _colorMap;
}

- (void)screenSetColor:(NSColor *)color forKey:(int)key {
    if (!color) {
        return;
    }

    NSString *profileKey = [_colorMap profileKeyForColorMapKey:key];
    if (profileKey) {
        [self setSessionSpecificProfileValues:@{ profileKey: [color dictionaryValue] }];
    } else {
        [_colorMap setColor:color forKey:key];
    }
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
    if ([_profile[KEY_USE_TAB_COLOR] boolValue]) {
        NSDictionary *colorDict = _profile[KEY_TAB_COLOR];
        if (colorDict) {
            return [ITAddressBookMgr decodeColor:colorDict];
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setTabColor:(NSColor *)color {
    NSDictionary *dict;
    if (color) {
        dict = @{ KEY_USE_TAB_COLOR: @YES,
                  KEY_TAB_COLOR: [ITAddressBookMgr encodeColor:color] };
    } else {
        dict = @{ KEY_USE_TAB_COLOR: @NO };
    }

    [self setSessionSpecificProfileValues:dict];
}

- (void)screenSetTabColorRedComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor];
    [self setTabColor:[NSColor colorWithSRGBRed:color
                                          green:[curColor greenComponent]
                                           blue:[curColor blueComponent]
                                          alpha:1]];
    [[_delegate parentWindow] updateTabColors];
}

- (void)screenSetTabColorGreenComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor];
    [self setTabColor:[NSColor colorWithSRGBRed:[curColor redComponent]
                                          green:color
                                           blue:[curColor blueComponent]
                                          alpha:1]];
    [[_delegate parentWindow] updateTabColors];
}

- (void)screenSetTabColorBlueComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor];
    [self setTabColor:[NSColor colorWithSRGBRed:[curColor redComponent]
                                          green:[curColor greenComponent]
                                           blue:color
                                          alpha:1]];
    [[_delegate parentWindow] updateTabColors];
}

- (void)screenCurrentHostDidChange:(VT100RemoteHost *)host {
    DLog(@"Current host did change to %@ %@", host, self);
    const BOOL hadHost = (_currentHost != nil);

    NSNull *null = [NSNull null];
    NSDictionary *variablesUpdate = @{ iTermVariableKeySessionHostname: host.hostname ?: null,
                                       iTermVariableKeySessionUsername: host.username ?: null };
    [self.variablesScope setValuesFromDictionary:variablesUpdate];

    [_textview setBadgeLabel:[self badgeLabel]];
    [self dismissAnnouncementWithIdentifier:kShellIntegrationOutOfDateAnnouncementIdentifier];

    [[_delegate realParentWindow] sessionHostDidChange:self to:host];

    int line = [_screen numberOfScrollbackLines] + _screen.cursorY;
    NSString *path = [_screen workingDirectoryOnLine:line];
    [self tryAutoProfileSwitchWithHostname:host.hostname
                                  username:host.username
                                      path:path
                                       job:self.variablesScope.jobName];

    if (hadHost) {
        [self maybeResetTerminalStateOnHostChange];
    }
    self.currentHost = host;
}

- (void)maybeResetTerminalStateOnHostChange {
    if (_xtermMouseReporting && self.terminal.mouseMode != MOUSE_REPORTING_NONE) {
        NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:kTurnOffMouseReportingOnHostChangeUserDefaultsKey];
        if ([number boolValue]) {
            self.terminal.mouseMode = MOUSE_REPORTING_NONE;
        } else if (!number) {
            [self offerToTurnOffMouseReportingOnHostChange];
        }
    }
    if (self.terminal.reportFocus) {
        NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
        if ([number boolValue]) {
            self.terminal.reportFocus = NO;
        } else if (!number) {
            [self offerToTurnOffFocusReportingOnHostChange];
        }
    }
    if (self.terminal.reportFocus) {
        NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
        if ([number boolValue]) {
            self.terminal.reportFocus = NO;
        } else if (!number) {
            [self offerToTurnOffFocusReportingOnHostChange];
        }
    }
    if (self.terminal.bracketedPasteMode) {
        NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:kTurnOffBracketedPasteOnHostChangeUserDefaultsKey];
        if ([number boolValue]) {
            self.terminal.bracketedPasteMode = NO;
        } else if (!number) {
            [self offerToTurnOffBracketedPasteOnHostChange];
        }
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
    NSString *title =
        @"Looks like mouse reporting was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"Yes", @"Always", @"Never" ]
                                                completion:^(int selection) {
            switch (selection) {
                case -2:  // Dismiss programmatically
                    break;

                case -1: // No
                    break;

                case 0: // Yes
                    self.terminal.mouseMode = MOUSE_REPORTING_NONE;
                    break;

                case 1: // Always
                    [[NSUserDefaults standardUserDefaults] setBool:YES
                                                            forKey:kTurnOffMouseReportingOnHostChangeUserDefaultsKey];
                    self.terminal.mouseMode = MOUSE_REPORTING_NONE;
                    break;

                case 2: // Never
                    [[NSUserDefaults standardUserDefaults] setBool:NO
                                                            forKey:kTurnOffMouseReportingOnHostChangeUserDefaultsKey];
            }
        }];
    [self queueAnnouncement:announcement identifier:kTurnOffMouseReportingOnHostChangeAnnouncementIdentifier];
}

- (void)offerToTurnOffFocusReportingOnHostChange {
    NSString *title =
        @"Looks like focus reporting was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"Yes", @"Always", @"Never" ]
                                                completion:^(int selection) {
            switch (selection) {
                case -2:  // Dismiss programmatically
                    break;

                case -1: // No
                    break;

                case 0: // Yes
                    self.terminal.reportFocus = NO;
                    break;

                case 1: // Always
                    [[NSUserDefaults standardUserDefaults] setBool:YES
                                                            forKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
                    self.terminal.reportFocus = NO;
                    break;

                case 2: // Never
                    [[NSUserDefaults standardUserDefaults] setBool:NO
                                                            forKey:kTurnOffFocusReportingOnHostChangeUserDefaultsKey];
            }
        }];
    [self queueAnnouncement:announcement identifier:kTurnOffFocusReportingOnHostChangeAnnouncementIdentifier];
}

- (void)offerToTurnOffBracketedPasteOnHostChange {
    NSString *title =
        @"Looks like paste bracketing was left on when an ssh session ended unexpectedly or an app misbehaved. Turn it off?";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:title
                                                     style:kiTermAnnouncementViewStyleQuestion
                                               withActions:@[ @"Yes", @"Always", @"Never", @"Help" ]
                                                completion:^(int selection) {
            switch (selection) {
                case -2:  // Dismiss programmatically
                    break;

                case -1: // No
                    break;

                case 0: // Yes
                    self.terminal.bracketedPasteMode = NO;
                    break;

                case 1: // Always
                    [[NSUserDefaults standardUserDefaults] setBool:YES
                                                            forKey:kTurnOffBracketedPasteOnHostChangeUserDefaultsKey];
                    self.terminal.bracketedPasteMode = NO;
                    break;

                case 2: // Never
                    [[NSUserDefaults standardUserDefaults] setBool:NO
                                                            forKey:kTurnOffBracketedPasteOnHostChangeUserDefaultsKey];
                    break;

                case 3: // Help
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/paste_bracketing"]];
                    break;
            }
        }];
    [self queueAnnouncement:announcement identifier:kTurnOffBracketedPasteOnHostChangeAnnouncementIdentifier];
}

- (void)tryAutoProfileSwitchWithHostname:(NSString *)hostname
                                username:(NSString *)username
                                    path:(NSString *)path
                                     job:(NSString *)job {
    [_automaticProfileSwitcher setHostname:hostname username:username path:path job:job];
}

- (void)screenCurrentDirectoryDidChangeTo:(NSString *)newPath {
    [self.variablesScope setValue:newPath forVariableNamed:iTermVariableKeySessionPath];

    int line = [_screen numberOfScrollbackLines] + _screen.cursorY;
    VT100RemoteHost *remoteHost = [_screen remoteHostOnLine:line];
    [self tryAutoProfileSwitchWithHostname:remoteHost.hostname
                                  username:remoteHost.username
                                      path:newPath
                                       job:self.variablesScope.jobName];
    [self.variablesScope setValue:newPath forVariableNamed:iTermVariableKeySessionPath];
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

- (CGFloat)screenBackingScaleFactor {
    return _view.window.screen.backingScaleFactor;
}

- (BOOL)screenShouldSendReport {
    return (_shell != nil) && (![self isTmuxClient]);
}

- (BOOL)haveCommandInRange:(VT100GridCoordRange)range {
    if (range.start.x == -1) {
        return NO;
    }

    // If semantic history goes nuts and the end-of-command code isn't received (which seems to be a
    // common problem, probably because of buggy old versions of SH scripts) , the command can grow
    // without bound. We'll limit the length of a command to avoid performance problems.
    const int kMaxLines = 50;
    if (range.end.y - range.start.y > kMaxLines) {
        range.end.y = range.start.y + kMaxLines;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_screen];
    return [extractor haveNonWhitespaceInFirstLineOfRange:VT100GridWindowedRangeMake(range, 0, 0)];
}

#pragma mark - FinalTerm

// NOTE: If you change this you probably want to change -haveCommandInRange:, too.
- (NSString *)commandInRange:(VT100GridCoordRange)range {
    if (range.start.x == -1) {
        return nil;
    }
    // If semantic history goes nuts and the end-of-command code isn't received (which seems to be a
    // common problem, probably because of buggy old versions of SH scripts) , the command can grow
    // without bound. We'll limit the length of a command to avoid performance problems.
    const int kMaxLines = 50;
    if (range.end.y - range.start.y > kMaxLines) {
        range.end.y = range.start.y + kMaxLines;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_screen];
    NSString *command = [extractor contentInRange:VT100GridWindowedRangeMake(range, 0, 0)
                                attributeProvider:nil
                                       nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                              pad:NO
                               includeLastNewline:NO
                           trimTrailingWhitespace:NO
                                     cappedAtSize:-1
                                     truncateTail:YES
                                continuationChars:nil
                                           coords:nil];
    NSRange newline = [command rangeOfString:@"\n"];
    if (newline.location != NSNotFound) {
        command = [command substringToIndex:newline.location];
    }

    return [command stringByTrimmingLeadingWhitespace];
}

- (NSString *)currentCommand {
    if (_commandRange.start.x < 0) {
        return nil;
    } else {
        return [self commandInRange:_commandRange];
    }
}

- (NSArray *)autocompleteSuggestionsForCurrentCommand {
    NSString *command;
    if (_commandRange.start.x < 0) {
        return nil;
    } else {
        command = [self commandInRange:_commandRange];
    }
    VT100RemoteHost *host = [_screen remoteHostOnLine:[_screen numberOfLines]];
    NSString *trimmedCommand =
        [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [[iTermShellHistoryController sharedInstance] commandHistoryEntriesWithPrefix:trimmedCommand
                                                                                  onHost:host];
}

- (void)screenCommandDidChangeWithRange:(VT100GridCoordRange)range {
    DLog(@"FinalTerm: command changed. New range is %@", VT100GridCoordRangeDescription(range));
    [self didUseShellIntegration];
    BOOL hadCommand = _commandRange.start.x >= 0 && [self haveCommandInRange:_commandRange];
    _commandRange = range;
    BOOL haveCommand = _commandRange.start.x >= 0 && [self haveCommandInRange:_commandRange];

    if (haveCommand) {
        VT100ScreenMark *mark = [_screen markOnLine:_lastPromptLine - [_screen totalScrollbackOverflow]];
        mark.commandRange = VT100GridAbsCoordRangeFromCoordRange(range, _screen.totalScrollbackOverflow);
        if (!hadCommand) {
            mark.promptRange = VT100GridAbsCoordRangeMake(0, _lastPromptLine, range.start.x, mark.commandRange.end.y);
        }
    }
    if (!haveCommand && hadCommand) {
        DLog(@"Hide because don't have a command, but just had one");
        [[_delegate realParentWindow] hideAutoCommandHistoryForSession:self];
    } else {
        if (!hadCommand && range.start.x >= 0) {
            DLog(@"Show because I have a range but didn't have a command");
            [[_delegate realParentWindow] showAutoCommandHistoryForSession:self];
        }
        if ([[_delegate realParentWindow] wantsCommandHistoryUpdatesFromSession:self]) {
            NSString *command = haveCommand ? [self commandInRange:_commandRange] : @"";
            DLog(@"Update command to %@, have=%d, range.start.x=%d", command, (int)haveCommand, range.start.x);
            if (haveCommand) {
                [[_delegate realParentWindow] updateAutoCommandHistoryForPrefix:command
                                                                      inSession:self
                                                                    popIfNeeded:NO];
            }
        }
    }
}

- (void)screenCommandDidEndWithRange:(VT100GridCoordRange)range {
    [self didUseShellIntegration];
    NSString *command = [self commandInRange:range];
    DLog(@"FinalTerm: Command <<%@>> ended with range %@",
         command, VT100GridCoordRangeDescription(range));
    if (command) {
        NSString *trimmedCommand =
        [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedCommand.length) {
            VT100ScreenMark *mark = [_screen markOnLine:_lastPromptLine - [_screen totalScrollbackOverflow]];
            DLog(@"FinalTerm:  Make the mark on lastPromptLine %lld (%@) a command mark for command %@",
                 _lastPromptLine - [_screen totalScrollbackOverflow], mark, command);
            mark.command = command;
            mark.commandRange = VT100GridAbsCoordRangeFromCoordRange(range, _screen.totalScrollbackOverflow);
            mark.outputStart = VT100GridAbsCoordMake(_screen.currentGrid.cursor.x,
                                                     _screen.currentGrid.cursor.y + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow);
            [[iTermShellHistoryController sharedInstance] addCommand:trimmedCommand
                                                              onHost:[_screen remoteHostOnLine:range.end.y]
                                                         inDirectory:[_screen workingDirectoryOnLine:range.end.y]
                                                            withMark:mark];
            [_commands addObject:trimmedCommand];
            [self trimCommandsIfNeeded];
        }
    }
    self.lastCommand = command;
    [self.variablesScope setValue:command forVariableNamed:iTermVariableKeySessionLastCommand];

    // `_commandRange` is from the beginning of command, to the cursor, not necessarily the end of the command.
    // `range` here includes the entire command and a new line.
    _lastOrCurrentlyRunningCommandAbsRange = VT100GridAbsCoordRangeFromCoordRange(range, _screen.totalScrollbackOverflow);
    _commandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
    DLog(@"Hide ACH because command ended");
    [[_delegate realParentWindow] hideAutoCommandHistoryForSession:self];
}

- (BOOL)screenShouldPlacePromptAtFirstColumn {
    return [iTermProfilePreferences boolForKey:KEY_PLACE_PROMPT_AT_FIRST_COLUMN
                                     inProfile:_profile];
}

- (BOOL)screenShouldPostTerminalGeneratedAlert {
    return [iTermProfilePreferences boolForKey:KEY_SEND_TERMINAL_GENERATED_ALERT
                                     inProfile:_profile];
}

- (void)resumeOutputIfNeeded {
    if (_suppressAllOutput) {
        // If all output was being suppressed and you hit a key, stop it but ignore bells for a few
        // seconds until we can process any that are in the pipeline.
        _suppressAllOutput = NO;
        _ignoreBellUntil = [NSDate timeIntervalSinceReferenceDate] + 5;
    }
}

- (BOOL)screenShouldIgnoreBellWhichIsAudible:(BOOL)audible visible:(BOOL)visible {
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
                                                           withActions:@[ @"Silence Bell Temporarily",
                                                                          @"Suppress All Output",
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
                                _suppressAllOutput = YES;
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
                                                           withActions:@[ @"Suppress All Output",
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
                                _suppressAllOutput = YES;
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
    return NO;
}

- (NSString *)screenProfileName {
    NSString *guid = _profile[KEY_ORIGINAL_GUID] ?: _profile[KEY_GUID];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    if (profile) {
        return profile[KEY_NAME];
    }
    return _profile


    [KEY_NAME];
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

// isRemote is a misnomer. It's really "is unsuitable for old PWD", since it would be YES for
// when shell integration had never been used and the lastDirectory is not updated reliably.
- (void)setLastDirectory:(NSString *)lastDirectory isUnsuitableForOldPWD:(BOOL)isUnsuitableForOldPWD {
    DLog(@"Set last directory to %@", lastDirectory);
    if (lastDirectory) {
        [_directories addObject:lastDirectory];
        [self trimDirectoriesIfNeeded];
    }
    [_lastDirectory autorelease];
    _lastDirectory = [lastDirectory copy];
    _lastDirectoryIsUnsuitableForOldPWD = isUnsuitableForOldPWD;
    [_delegate sessionCurrentDirectoryDidChange:self];
}

- (NSString *)currentLocalWorkingDirectory {
    if (_lastDirectoryIsUnsuitableForOldPWD || _lastDirectory == nil) {
        DLog(@"Last directory is unsuitable or nil");
        // Ask the kernel what the child's process's working directory is.
        return [_shell getWorkingDirectory];
    } else {
        // If a shell integration-provided working directory is available, prefer to use it because
        // it has unresolved symlinks. The path provided by -getWorkingDirectory has expanded symlinks
        // and isn't what the user expects to see. This was raised in issue 3383. My first fix was
        // to expand symlinks on _lastDirectory and use it if it matches what the kernel reports.
        // That was a bad idea because expanding symlinks is slow on network file systems (Issue 4901).
        // Instead, we'll use _lastDirectory if we believe it's on localhost.
        DLog(@"Using last directory from shell integration: %@", _lastDirectory);
        return _lastDirectory;
    }
}

- (void)setLastRemoteHost:(VT100RemoteHost *)lastRemoteHost {
    if (lastRemoteHost) {
        [_hosts addObject:lastRemoteHost];
        [self trimHostsIfNeeded];
    }
    [_lastRemoteHost autorelease];
    _lastRemoteHost = [lastRemoteHost retain];
}

// isSuitableForOldPWD means that if we don't know what the hostname is then this should be used
// in place of asking the OS what the PWD is from now on. It's useful for users who set up a trigger
// to report the PWD but don't report the hostname, or for users who use the CurrentDir control
// sequence but not RemoteHost. Issue 5878, May 2019 comments.
- (void)screenLogWorkingDirectoryAtLine:(int)line
                          withDirectory:(NSString *)directory
                    isSuitableForOldPWD:(BOOL)isSuitableForOldPWD {
    VT100RemoteHost *remoteHost = [_screen remoteHostOnLine:line];
    BOOL isSame = ([directory isEqualToString:_lastDirectory] &&
                   [remoteHost isEqualToRemoteHost:_lastRemoteHost]);
    [[iTermShellHistoryController sharedInstance] recordUseOfPath:directory
                                                           onHost:[_screen remoteHostOnLine:line]
                                                         isChange:!isSame];
    BOOL unsuitable;
    if (remoteHost == nil && isSuitableForOldPWD) {
        // Special dispensation. Trust the caller that this working directory will be kept up to date.
        unsuitable = NO;
    } else {
        // In this case a nil remoteHost is considered unsuitable because we believe this is an
        // odd one-off (such as by setting the title) and we can't count on it being updated
        // reliably. We'll pull pwd from the child process via the kernel.
        unsuitable = !remoteHost.isLocalhost;
    }
    DLog(@"Calling setLastDirectory:%@ isUnsuitableForOldPWD:%@. remoteHost is %@\n%@",
         directory, @(unsuitable), remoteHost, [NSThread callStackSymbols]);
    [self setLastDirectory:directory isUnsuitableForOldPWD:unsuitable];
    self.lastRemoteHost = remoteHost;
}

- (BOOL)screenAllowTitleSetting {
    NSNumber *n = _profile[KEY_ALLOW_TITLE_SETTING];
    if (!n) {
        return YES;
    } else {
        return [n boolValue];
    }
}

- (void)didUseShellIntegration {
    _shellIntegrationEverUsed = YES;
}

- (NSString *)shellIntegrationUpgradeUserDefaultsKeyForHost:(VT100RemoteHost *)host {
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

- (void)screenSuggestShellIntegrationUpgrade {
    VT100RemoteHost *currentRemoteHost = [self currentHost];

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
        _statusChangedAbsLine = _screen.cursorY - 1 + _screen.numberOfScrollbackLines + _screen.totalScrollbackOverflow;
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

- (void)screenTerminalAttemptedPasteboardAccess {
    if ([iTermAdvancedSettingsModel noSyncSuppressClipboardAccessDeniedWarning]) {
        return;
    }
    NSString *identifier = @"ClipboardAccessDenied";
    if ([self hasAnnouncementWithIdentifier:identifier]) {
        return;
    }
    NSString *notice = @"The terminal attempted to access the clipboard but it was denied. Enable clipboard access in “Prefs > General > Applications in terminal may access clipboard”.";
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:notice
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"Open Prefs", @"Don't Show This Again" ]
                                                completion:^(int selection) {
                                                    if (selection == 0) {
                                                        [[[iTermApplication sharedApplication] delegate] showPrefWindow:nil];
                                                    } else if (selection == 1) {
                                                        [iTermAdvancedSettingsModel setNoSyncSuppressClipboardAccessDeniedWarning:YES];
                                                    }
                                                }];
    [self queueAnnouncement:announcement identifier:identifier];
}

- (NSString *)screenValueOfVariableNamed:(NSString *)name {
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

- (void)screenDidReceiveLineFeed {
    [_pwdPoller didReceiveLineFeed];
}

- (void)screenSoftAlternateScreenModeDidChange {
    [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
}

- (void)screenReportKeyUpDidChange:(BOOL)reportKeyUp {
    [self updateKeyMapper];
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

#pragma mark - PopupDelegate

- (void)popupIsSearching:(BOOL)searching {
    _textview.showSearchingCursor = searching;
    [_textview setNeedsDisplayInRect:_textview.cursorFrame];
}

- (void)popupWillClose:(iTermPopupWindowController *)popup {
    [[_delegate realParentWindow] popupWillClose:popup];
}

- (NSWindowController *)popupWindowController {
    return [_delegate realParentWindow];
}

- (BOOL)popupWindowIsInFloatingHotkeyWindow {
    return _delegate.realParentWindow.isFloatingHotKeyWindow;
}

- (VT100Screen *)popupVT100Screen {
    return _screen;
}

- (PTYTextView *)popupVT100TextView {
    return _textview;
}

- (void)popupInsertText:(NSString *)string {
    [self insertText:string];
}

- (BOOL)popupHandleSelector:(SEL)selector
                     string:(NSString *)string
               currentValue:(NSString *)currentValue {
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
    if (selector == @selector(insertText:)) {
        [self insertText:string];
        return YES;
    }
    return NO;
}

#pragma mark - iTermPasteHelperDelegate

- (void)pasteHelperWriteString:(NSString *)string {
    [self writeTask:string];
}

- (void)pasteHelperKeyDown:(NSEvent *)event {
    [_textview keyDown:event];
}

- (BOOL)pasteHelperShouldBracket {
    return [_terminal bracketedPasteMode];
}

- (NSStringEncoding)pasteHelperEncoding {
    return [_terminal encoding];
}

- (NSView *)pasteHelperViewForIndicator {
    return _view;
}

- (iTermStatusBarViewController *)pasteHelperStatusBarViewController {
    return _statusBarViewController;
}

- (BOOL)pasteHelperShouldWaitForPrompt {
    if (!_shellIntegrationEverUsed) {
        return NO;
    }

    return self.currentCommand == nil;
}

- (BOOL)pasteHelperIsAtShellPrompt {
    return [self currentCommand] != nil;
}

- (BOOL)pasteHelperCanWaitForPrompt {
    return _shellIntegrationEverUsed;
}

- (void)pasteHelperPasteViewVisibilityDidChange {
    if (@available(macOS 10.11, *)) {
        [self.delegate sessionUpdateMetalAllowed];
    }
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
    [self setProfile:savedProfile.originalProfile preservingName:NO adjustWindow:NO];
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
}

- (NSArray<NSDictionary *> *)automaticProfileSwitcherAllProfiles {
    return [[ProfileModel sharedInstance] bookmarks];
}

#pragma mark - iTermSessionViewDelegate

- (void)sessionViewMouseEntered:(NSEvent *)event {
    [_textview mouseEntered:event];
}

- (void)sessionViewMouseExited:(NSEvent *)event {
    [_textview mouseExited:event];
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
    self.colorMap.dimmingAmount = newDimmingAmount;
}

- (BOOL)sessionViewIsVisible {
    return YES;
}

- (void)sessionViewDrawBackgroundImageInView:(NSView *)view
                                    viewRect:(NSRect)rect
                      blendDefaultBackground:(BOOL)blendDefaultBackground {
    [self textViewDrawBackgroundImageInView:view
                                   viewRect:rect
                     blendDefaultBackground:blendDefaultBackground];

}

- (void)sessionViewDraggingExited:(id<NSDraggingInfo>)sender {
    [self.delegate sessionDraggingExited:self];
    [_textview setNeedsDisplay:YES];
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
    return [_colorMap colorForKey:kColorMapBackground];
}

- (BOOL)sessionViewTerminalIsFirstResponder {
    return (_textview.window.firstResponder == _textview &&
            [NSApp isActive] &&
            _textview.window.isKeyWindow);
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
    return _textview.desiredHeight + [iTermAdvancedSettingsModel terminalVMargin];
}

- (BOOL)sessionViewShouldUpdateSubviewsFramesAutomatically {
    // We won't automatically layout the session view's descendents for tmux
    // tabs. Instead the change gets reported to the tmux server and it will
    // send us a new layout.
    if (self.isTmuxClient) {
        // This makes dragging a split pane in a tmux tab look way better.
        return [_delegate sessionBelongsToTabWhoseSplitsAreBeingDragged];
    } else {
        return YES;
    }
}

- (NSSize)sessionViewScrollViewWillResize:(NSSize)proposedSize {
    if ([self isTmuxClient] && ![_delegate sessionBelongsToTabWhoseSplitsAreBeingDragged]) {
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

- (iTermStatusBarViewController *)sessionViewStatusBarViewController {
    return _statusBarViewController;
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
    if (@available(macOS 10.11, *)) {
        [self updateMetalDriver];
    }
}

- (void)sessionViewAnnouncementDidChange:(SessionView *)sessionView {
    [self.delegate sessionUpdateMetalAllowed];
}

- (id)temporarilyDisableMetal NS_AVAILABLE_MAC(10_11) {
    assert(_useMetal);
    _wrapper.useMetal = NO;
    _textview.suppressDrawing = NO;
    if (@available(macOS 10.14, *)) {
        _view.scrollview.alphaValue = 1;
    }
    _view.metalView.alphaValue = 0;
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
        if (_exited) {
            DLog(@"drawFrameAndRemoveTemporarilyDisablementOfMetal: Returning because the session is dead");
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
    if (@available(macOS 10.11, *)) {
        if (_metalFrameChangePending) {
            DLog(@"sessionViewNeedsMetalFrameUpdate frame change pending, return");
            return;
        }

        _metalFrameChangePending = YES;
        id token = [self temporarilyDisableMetal];
        [self.textview setNeedsDisplay:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            DLog(@"sessionViewNeedsMetalFrameUpdate %@ in dispatch_async", self);
            _metalFrameChangePending = NO;
            [_view reallyUpdateMetalViewFrame];
            DLog(@"sessionViewNeedsMetalFrameUpdate will draw farme and remove disablement");
            [self drawFrameAndRemoveTemporarilyDisablementOfMetalForToken:token];
        });
    }
}

- (void)sessionViewRecreateMetalView {
    if (@available(macOS 10.11, *)) {
        if (_metalDeviceChanging) {
            return;
        }
        DLog(@"sessionViewRecreateMetalView metalDeviceChanging<-YES");
        _metalDeviceChanging = YES;
        [self.textview setNeedsDisplay:YES];
        [_delegate sessionUpdateMetalAllowed];
        dispatch_async(dispatch_get_main_queue(), ^{
            _metalDeviceChanging = NO;
            DLog(@"sessionViewRecreateMetalView metalDeviceChanging<-NO");
            [_delegate sessionUpdateMetalAllowed];
        });
    }
}

- (void)sessionViewUserScrollDidChange:(BOOL)userScroll {
    [self.delegate sessionUpdateMetalAllowed];
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

#pragma mark - iTermCoprocessDelegate

- (void)coprocess:(Coprocess *)coprocess didTerminateWithErrorOutput:(NSString *)errors {
    if ([Coprocess shouldIgnoreErrorsFromCommand:coprocess.command]) {
        return;
    }
    NSString *command = [[coprocess.command copy] autorelease];
    iTermAnnouncementViewController *announcement =
    [iTermAnnouncementViewController announcementWithTitle:[NSString stringWithFormat:@"Coprocess “%@” terminated with output on stderr.", coprocess.command]
                                                     style:kiTermAnnouncementViewStyleWarning
                                               withActions:@[ @"View Errors", @"Ignore Errors from This Command" ]
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
    [self updateDisplayBecause:nil];
}

- (iTermUpdateCadenceState)updateCadenceControllerState {
    iTermUpdateCadenceState state;
    state.active = _active;
    state.idle = self.isIdle;
    state.visible = [_delegate sessionBelongsToVisibleTab];

    if (self.useMetal) {
        if ([iTermPreferences maximizeMetalThroughput] &&
            !_terminal.softAlternateScreenMode) {
            state.useAdaptiveFrameRate = YES;
        } else {
            state.useAdaptiveFrameRate = NO;
        }
    } else {
        if ([iTermAdvancedSettingsModel disableAdaptiveFrameRateInInteractiveApps] &&
            _terminal.softAlternateScreenMode) {
            state.useAdaptiveFrameRate = NO;
        } else {
            state.useAdaptiveFrameRate = _useAdaptiveFrameRate;
        }
    }
    state.adaptiveFrameRateThroughputThreshold = _adaptiveFrameRateThroughputThreshold;
    state.slowFrameRate = self.useMetal ? [iTermAdvancedSettingsModel metalSlowFrameRate] : [iTermAdvancedSettingsModel slowFrameRate];
    state.liveResizing = _inLiveResize;
    return state;
}

- (void)cadenceControllerActiveStateDidChange:(BOOL)active {
    if (@available(macOS 10.11, *)) {
        [self.delegate sessionUpdateMetalAllowed];
    }
}

#pragma mark - API

- (NSString *)stringForLine:(screen_char_t *)screenChars
                     length:(int)length
                  cppsArray:(NSMutableArray<ITMCodePointsPerCell *> *)cppsArray {
    unichar *characters = malloc(sizeof(unichar) * length * kMaxParts + 1);
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
    __block screen_char_t *line = nil;
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
                           charBlock:^BOOL(screen_char_t *currentLine, screen_char_t theChar, VT100GridCoord coord) {
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

- (ITMGetPromptResponse *)handleGetPromptRequest:(ITMGetPromptRequest *)request {
    VT100ScreenMark *mark = [_screen lastPromptMark];
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

    response.workingDirectory = self.currentLocalWorkingDirectory;
    response.command = mark.command ?: self.currentCommand;
    response.status = ITMGetPromptResponse_Status_Ok;
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
            [scriptHistoryEntry addOutput:[NSString stringWithFormat:@"Value %@ is not legal type for key %@\n", value, key]];
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
    response.status = ITMSetProfilePropertyResponse_Status_Ok;
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
        [[iTermProcessCache sharedInstance] setNeedsUpdate:YES];
    }
    if ([_graphicSource updateImageForProcessID:self.shell.pid enabled:[self shouldShowTabGraphic]]) {
        [self.delegate sessionDidChangeGraphic:self shouldShow:self.shouldShowTabGraphic image:self.tabGraphic];
    }
}

#pragma mark - iTermEchoProbeDelegate

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeString:(NSString *)string {
    [self writeTaskNoBroadcast:string];
}

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeData:(NSData *)data {
    [self writeLatin1EncodedData:data broadcastAllowed:NO];
}

- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe {
    BOOL ok = ([iTermWarning showWarningWithTitle:@"Are you really at a password prompt? It looks "
                @"like what you're typing is echoed to the screen."
                                          actions:@[ @"Cancel", @"Enter Password" ]
                                       identifier:nil
                                      silenceable:kiTermWarningTypePersistent
                                           window:self.view.window] == kiTermWarningSelection1);
    if (ok) {
        [_echoProbe enterPassword];
    }
}

- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe {
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

- (NSImage *)backgroundDrawingHelperImage {
    return _backgroundImage;
}

- (BOOL)backgroundDrawingHelperUseTransparency {
    return _textview.useTransparency;
}

- (CGFloat)backgroundDrawingHelperTransparency {
    return _textview.transparency;
}

- (iTermBackgroundImageMode)backgroundDrawingHelperBackgroundImageMode {
    return _backgroundImageMode;
}

- (NSColor *)backgroundDrawingHelperDefaultBackgroundColor {
    return [self processedBackgroundColor];
}

- (CGFloat)backgroundDrawingHelperBlending {
    return _textview.blend;
}

#pragma mark - iTermStatusBarViewControllerDelegate

- (NSColor *)textColorForStatusBar {
    return [[iTermTheme sharedInstance] statusBarTextColorForEffectiveAppearance:_view.effectiveAppearance
                                                                        colorMap:_colorMap
                                                                        tabStyle:[self.view.window.ptyWindow it_tabStyle]
                                                                   mainAndActive:(self.view.window.isMainWindow && NSApp.isActive)];
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
    if (@available(macOS 10.14, *)) {
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
    } else {
        return [[self textColorForStatusBar] colorWithAlphaComponent:alpha];
    }
}

- (NSColor *)statusBarBackgroundColor {
    return _statusBarViewController.layout.advancedConfiguration.backgroundColor;
}

- (void)updateStatusBarStyle {
    [_statusBarViewController updateColors];
    [self invalidateStatusBar];
}

- (NSFont *)statusBarTerminalFont {
    return _textview.font;
}

- (NSColor *)statusBarTerminalBackgroundColor {
    return [self processedBackgroundColor];
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


- (void)statusBarSetLayout:(nonnull iTermStatusBarLayout *)layout {
    ProfileModel *model;
    if (self.isDivorced && [_overriddenFields containsObject:KEY_STATUS_BAR_LAYOUT]) {
        model = [ProfileModel sessionsInstance];
    } else {
        model = [ProfileModel sharedInstance];
    }
    [iTermProfilePreferences setObject:[layout dictionaryValue]
                                forKey:KEY_STATUS_BAR_LAYOUT
                             inProfile:self.originalProfile
                                 model:model];
}

- (void)statusBarPerformAction:(iTermAction *)action {
    [self applyAction:action];
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
    [iTermAnnouncementViewController announcementWithTitle:[NSString stringWithFormat:@"You seem frustrated. Would you like the %@ option to key send esc+keystroke?", leftOrRight]
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

- (BOOL)workingDirectoryPollerShouldPoll {
    if (_shellIntegrationEverUsed) {
        DLog(@"Should not poll for working directory: shell integration used");
        return NO;
    }
    if (_terminal.softAlternateScreenMode) {
        DLog(@"Should not poll for working directory: soft alternate screen mode");
    }
    DLog(@"Should poll for working directory.");
    return YES;
}

- (pid_t)workingDirectoryPollerProcessID {
    return _shell.pid;;
}

- (void)workingDirectoryPollerDidFindWorkingDirectory:(NSString *)pwd {
    if (_shellIntegrationEverUsed) {
        return;
    }
    [self.variablesScope setValue:pwd forVariableNamed:iTermVariableKeySessionPath];
}

#pragma mark - iTermStandardKeyMapperDelegate

- (void)standardKeyMapperWillMapKey:(iTermStandardKeyMapper *)standardKeyMapper {
    iTermStandardKeyMapperConfiguration configuration = {
        .outputFactory = [_terminal.output retain],
        .encoding = _terminal.encoding,
        .leftOptionKey = self.optionKey,
        .rightOptionKey = self.rightOptionKey,
        .screenlike = self.isTmuxClient
    };
    standardKeyMapper.configuration = configuration;
}

#pragma mark - iTermTermkeyKeyMapperDelegate

- (void)termkeyKeyMapperWillMapKey:(iTermTermkeyKeyMapper *)termkeyKeyMaper {
    iTermTermkeyKeyMapperConfiguration configuration = {
        .encoding = _terminal.encoding,
        .leftOptionKey = self.optionKey,
        .rightOptionKey = self.rightOptionKey,
        .applicationCursorMode = _terminal.output.cursorMode,
        .applicationKeypadMode = _terminal.output.keypadMode
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
    const CGFloat width = [iTermProfilePreferences floatForKey:KEY_BADGE_MAX_WIDTH inProfile:self.profile];
    const CGFloat height = [iTermProfilePreferences floatForKey:KEY_BADGE_MAX_HEIGHT inProfile:self.profile];
    return NSMakeSize(width, height);
}

#pragma mark - iTermCopyModeHandlerDelegate

- (void)copyModeHandlerDidChangeEnabledState:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY {
    [_textview setNeedsDisplay:YES];
    if (!handler.enabled) {
        if (_textview.selection.live) {
            [_textview.selection endLiveSelection];
        }
        if (!_queuedTokens.count) {
            CVector vector;
            CVectorCreate(&vector, 100);
            [self executeTokens:&vector bytesHandled:0];
        }
    }
}

- (iTermCopyModeState *)copyModeHandlerCreateState:(iTermCopyModeHandler *)handler NOT_COPY_FAMILY {
    iTermCopyModeState *state = [[iTermCopyModeState alloc] init];
    state.coord = VT100GridCoordMake(_screen.cursorX - 1,
                                     _screen.cursorY - 1 + _screen.numberOfScrollbackLines);
    state.numberOfLines = _screen.numberOfLines;
    state.textView = _textview;

    if (_textview.selection.allSubSelections.count == 1) {
        [_textview.window makeFirstResponder:_textview];
        iTermSubSelection *sub = _textview.selection.allSubSelections.firstObject;
        state.start = sub.range.coordRange.start;
        state.coord = sub.range.coordRange.end;
        state.selecting = YES;
        state.start = sub.range.coordRange.start;
        state.coord = sub.range.coordRange.end;
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
    }
    return _methods;
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

@end
