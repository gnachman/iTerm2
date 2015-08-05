#import "PTYSession.h"

#import "CommandHistory.h"
#import "CommandUse.h"
#import "Coprocess.h"
#import "CVector.h"
#import "FakeWindow.h"
#import "FileTransferManager.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermDirectoriesModel.h"
#import "iTermGrowlDelegate.h"
#import "iTermKeyBindingMgr.h"
#import "iTermMouseCursor.h"
#import "iTermPasteHelper.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermRestorableSession.h"
#import "iTermRule.h"
#import "iTermSavePanel.h"
#import "iTermSelection.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextExtractor.h"
#import "iTermWarning.h"
#import "MovePaneController.h"
#import "MovingAverage.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSData+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+PSM.h"
#import "PasteContext.h"
#import "PasteEvent.h"
#import "PreferencePanel.h"
#import "ProcessCache.h"
#import "ProfilePreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PTYScrollView.h"
#import "PTYTab.h"
#import "PTYTask.h"
#import "PTYTextView.h"
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

// The format for a user defaults key that recalls if the user has already been pestered about
// outdated key mappings for a give profile. The %@ is replaced with the profile's GUID.
static NSString *const kAskAboutOutdatedKeyMappingKeyFormat = @"AskAboutOutdatedKeyMappingForGuid%@";

NSString *const kPTYSessionTmuxFontDidChange = @"kPTYSessionTmuxFontDidChange";
NSString *const kPTYSessionCapturedOutputDidChange = @"kPTYSessionCapturedOutputDidChange";
static NSString *const kSuppressAnnoyingBellOffer = @"NoSyncSuppressAnnyoingBellOffer";
static NSString *const kSilenceAnnoyingBellAutomatically = @"NoSyncSilenceAnnoyingBellAutomatically";
static NSString *const kReopenSessionWarningIdentifier = @"ReopenSessionAfterBrokenPipe";

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
static NSString *const SESSION_ARRANGEMENT_BOOKMARK_NAME = @"Bookmark Name";
static NSString *const SESSION_ARRANGEMENT_WORKING_DIRECTORY = @"Working Directory";
static NSString *const SESSION_ARRANGEMENT_CONTENTS = @"Contents";
static NSString *const SESSION_ARRANGEMENT_TMUX_PANE = @"Tmux Pane";
static NSString *const SESSION_ARRANGEMENT_TMUX_HISTORY = @"Tmux History";
static NSString *const SESSION_ARRANGEMENT_TMUX_ALT_HISTORY = @"Tmux AltHistory";
static NSString *const SESSION_ARRANGEMENT_TMUX_STATE = @"Tmux State";
static NSString *const SESSION_ARRANGEMENT_IS_TMUX_GATEWAY = @"Is Tmux Gateway";
static NSString *const SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME = @"Tmux Gateway Session Name";
static NSString *const SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID = @"Tmux Gateway Session ID";
static NSString *const SESSION_ARRANGEMENT_DEFAULT_NAME = @"Session Default Name";  // manually set name
static NSString *const SESSION_ARRANGEMENT_WINDOW_TITLE = @"Session Window Title";  // server-set window name
static NSString *const SESSION_ARRANGEMENT_NAME = @"Session Name";  // server-set "icon" (tab) name
static NSString *const SESSION_ARRANGEMENT_GUID = @"Session GUID";  // A truly unique ID.
static NSString *const SESSION_ARRANGEMENT_LIVE_SESSION = @"Live Session";  // If zoomed, this gives the "live" session's arrangement.
static NSString *const SESSION_ARRANGEMENT_SUBSTITUTIONS = @"Substitutions";  // Dictionary for $$VAR$$ substitutions
static NSString *const SESSION_UNIQUE_ID = @"Session Unique ID";  // DEPRECATED. A string used for restoring soft-terminated sessions for arrangements that predate the introduction of the GUID.
static NSString *const SESSION_ARRANGEMENT_SERVER_PID = @"Server PID";  // PID for server process for restoration
static NSString *const SESSION_ARRANGEMENT_VARIABLES = @"Variables";  // _variables
static NSString *const SESSION_ARRANGEMENT_COMMAND_RANGE = @"Command Range";  // VT100GridCoordRange
static NSString *const SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED = @"Shell Integration Ever Used";  // BOOL
static NSString *const SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK = @"Alert on Next Mark";  // BOOL
static NSString *const SESSION_ARRANGEMENT_COMMANDS = @"Commands";  // Array of strings
static NSString *const SESSION_ARRANGEMENT_DIRECTORIES = @"Directories";  // Array of strings
static NSString *const SESSION_ARRANGEMENT_HOSTS = @"Hosts";  // Array of VT100RemoteHost
static NSString *const SESSION_ARRANGEMENT_CURSOR_GUIDE = @"Cursor Guide";  // BOOL
static NSString *const SESSION_ARRANGEMENT_LAST_DIRECTORY = @"Last Directory";  // NSString
static NSString *const SESSION_ARRANGEMENT_SELECTION = @"Selection";  // Dictionary for iTermSelection.

static NSString *const SESSION_ARRANGEMENT_PROGRAM = @"Program";  // Dictionary. See kProgram constants below.
static NSString *const SESSION_ARRANGEMENT_ENVIRONMENT = @"Environment";  // Dictionary of environment vars program was run in
static NSString *const SESSION_ARRANGEMENT_IS_UTF_8 = @"Is UTF-8";  // TTY is in utf-8 mode

// Keys for dictionary in SESSION_ARRANGEMENT_PROGRAM
static NSString *const kProgramType = @"Type";  // Value will be one of the kProgramTypeXxx constants.
static NSString *const kProgramCommand = @"Command";  // For kProgramTypeCommand: value is command to run.

// Values for kProgramType
static NSString *const kProgramTypeShellLauncher = @"Shell Launcher";  // Use iTerm2 --launch_shell
static NSString *const kProgramTypeCommand = @"Command";  // Use command in kProgramCommand

static NSString *kTmuxFontChanged = @"kTmuxFontChanged";

// Keys into _variables.
static NSString *const kVariableKeySessionName = @"session.name";
static NSString *const kVariableKeySessionColumns = @"session.columns";
static NSString *const kVariableKeySessionRows = @"session.rows";
static NSString *const kVariableKeySessionHostname = @"session.hostname";
static NSString *const kVariableKeySessionUsername = @"session.username";
static NSString *const kVariableKeySessionPath = @"session.path";
static NSString *const kVariableKeySessionLastCommand = @"session.lastCommand";
static NSString *const kVariableKeySessionTTY = @"session.tty";

// Maps Session GUID to saved contents. Only live between window restoration
// and the end of startup activities.
static NSMutableDictionary *gRegisteredSessionContents;

// Rate limit for checking instant (partial-line) triggers, in seconds.
static NSTimeInterval kMinimumPartialLineTriggerCheckInterval = 0.5;

@interface PTYSession () <iTermPasteHelperDelegate>
@property(nonatomic, retain) Interval *currentMarkOrNotePosition;
@property(nonatomic, retain) TerminalFile *download;
@property(nonatomic, readwrite) NSTimeInterval lastOutput;
@property(nonatomic, readwrite) BOOL isDivorced;
@property(atomic, assign) PTYSessionTmuxMode tmuxMode;
@property(nonatomic, copy) NSString *lastDirectory;
@property(nonatomic, retain) VT100RemoteHost *lastRemoteHost;  // last remote host at time of setting current directory
@property(nonatomic, retain) NSColor *cursorGuideColor;
@property(nonatomic, copy) NSString *badgeFormat;
@property(nonatomic, retain) NSMutableDictionary *variables;

// Info about what happens when the program is run so it can be restarted after
// a broken pipe if the user so chooses.
@property(nonatomic, copy) NSString *program;
@property(nonatomic, copy) NSDictionary *environment;
@property(nonatomic, assign) BOOL isUTF8;
@property(nonatomic, copy) NSDictionary *substitutions;
@property(nonatomic, copy) NSString *guid;
@property(nonatomic, retain) iTermPasteHelper *pasteHelper;
@property(nonatomic, copy) NSString *lastCommand;
@end

@implementation PTYSession {
    // PTYTask has started a job, and a call to -taskWasDeregistered will be
    // made when it dies. All access should be synchronized.
    BOOL _registered;

    // name can be changed by the host.
    NSString *_name;

    // defaultName cannot be changed by the host.
    NSString *_defaultName;

    NSString *_windowTitle;

    // The window title stack
    NSMutableArray *_windowTitleStack;

    // The icon title stack
    NSMutableArray *_iconTitleStack;

    // Terminal processes vt100 codes.
    VT100Terminal *_terminal;

    NSString *_termVariable;

    // Has the underlying connection been closed?
    BOOL _exited;

    // A view that wraps the textview. It is the scrollview's document. This exists to provide a
    // top margin above the textview.
    TextViewWrapper *_wrapper;

    // This timer fires periodically to redraw textview, update the scroll position, tab appearance,
    // etc.
    NSTimer *_updateTimer;

    // Anti-idle timer that sends a character every so often to the host.
    NSTimer *_antiIdleTimer;

    // The code to send in the anti idle timer.
    char _antiIdleCode;

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

    // The name of the foreground job at the moment as best we can tell.
    NSString *_jobName;

    // Time session was created
    NSDate *_creationDate;

    // After receiving new output, we keep running the updateDisplay timer for a few seconds to catch
    // changes in job name.
    NSTimeInterval _updateDisplayUntil;

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
    int _tmuxPane;
    BOOL _tmuxSecureLogging;
    // The tmux rename-window command is only sent when the name field resigns first responder.
    // This tracks if a tmux client's name has changed but the tmux server has not been informed yet.
    BOOL _tmuxTitleOutOfSync;

    NSInteger _requestAttentionId;  // Last request-attention identifier
    VT100ScreenMark *_lastMark;

    VT100GridCoordRange _commandRange;
    long long _lastPromptLine;  // Line where last prompt began

    NSTimeInterval _timeOfLastScheduling;

    dispatch_semaphore_t _executionSemaphore;

    // Previous updateDisplay timer's timeout period (not the actual duration,
    // but the kXXXTimerIntervalSec value).
    NSTimeInterval _lastTimeout;

    // In order to correctly draw a tiled background image, we must first draw
    // it into an image the size of the session view, and then blit from it
    // onto the background of whichever view needs a background. This ensures
    // the tesselation is consistent.
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

    // Number of bytes received since an echo probe was sent.
    int _bytesReceivedSinceSendingEchoProbe;

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

    NSMutableArray *_commandUses;
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

- (id)init {
    self = [super init];
    if (self) {
        _triggerLineNumber = -1;
        // The new session won't have the move-pane overlay, so just exit move pane
        // mode.
        [[MovePaneController sharedInstance] exitMovePaneMode];
        _lastInput = [NSDate timeIntervalSinceReferenceDate];

        // Experimentally, this is enough to keep the queue primed but not overwhelmed.
        // TODO: How do slower machines fare?
        static const int kMaxOutstandingExecuteCalls = 4;
        _executionSemaphore = dispatch_semaphore_create(kMaxOutstandingExecuteCalls);

        _lastOutput = _lastInput;
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
        _creationDate = [[NSDate date] retain];
        _tmuxSecureLogging = NO;
        _tailFindContext = [[FindContext alloc] init];
        _commandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
        _activityCounter = [@0 retain];
        _announcements = [[NSMutableDictionary alloc] init];
        _queuedTokens = [[NSMutableArray alloc] init];
        _variables = [[NSMutableDictionary alloc] init];
        _commands = [[NSMutableArray alloc] init];
        _directories = [[NSMutableArray alloc] init];
        _hosts = [[NSMutableArray alloc] init];
        // Allocate a guid. If we end up restoring from a session during startup this will be replaced.
        _guid = [[NSString uuid] retain];
        _commandUses = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowResized)
                                                     name:@"iTermWindowDidResize"
                                                   object:nil];
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
        [self updateVariables];
    }
    return self;
}

- (void)dealloc {
    [self stopTailFind];  // This frees the substring in the tail find context, if needed.
    _shell.delegate = nil;
    dispatch_release(_executionSemaphore);
    [_colorMap release];
    [_triggers release];
    [_pasteboard release];
    [_pbtext release];
    [_creationDate release];
    [_activityCounter release];
    [_bookmarkName release];
    [_termVariable release];
    [_colorFgBgVariable release];
    [_name release];
    [_windowTitle release];
    [_windowTitleStack release];
    [_iconTitleStack release];
    [_profile release];
    [_overriddenFields release];
    _pasteHelper.delegate = nil;
    [_pasteHelper release];
    [_backgroundImagePath release];
    [_backgroundImage release];
    [_antiIdleTimer invalidate];
    [_antiIdleTimer release];
    [_updateTimer invalidate];
    [_updateTimer release];
    [_originalProfile release];
    [_liveSession release];
    [_tmuxGateway release];
    [_tmuxController release];
    [_download stop];
    [_download endOfData];
    [_download release];
    [_shell release];
    [_screen release];
    [_terminal release];
    [_tailFindContext release];
    _currentMarkOrNotePosition = nil;
    [_lastMark release];
    [_patternedImage release];
    [_announcements release];
    [_queuedTokens release];
    [_badgeFormat release];
    [_variables release];
    [_program release];
    [_environment release];
    [_commands release];
    [_directories release];
    [_hosts release];
    [_bellRate release];
    [_guid release];
    [_lastCommand release];
    [_substitutions release];
    [_commandUses release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_dvrDecoder) {
        [_dvr releaseDecoder:_dvrDecoder];
        [_dvr release];
    }

    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p %dx%d>",
               [self class], self, [_screen width], [_screen height]];
}

- (void)cancelTimers {
    [_updateTimer invalidate];
    [_antiIdleTimer invalidate];
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

- (void)irAdvance:(int)dir
{
    if (!_dvr) {
        if (dir < 0) {
            [[[self tab] realParentWindow] replaySession:self];
            PTYSession* irSession = [[[self tab] realParentWindow] currentSession];
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
        [_dvrDecoder seek:[_dvr firstTimeStamp]];
    }
    [self setDvrFrame];
    return [_dvrDecoder timestamp];
}

- (void)appendLinesInRange:(NSRange)rangeOfLines fromSession:(PTYSession *)source {
    int width = source.screen.width;
    for (NSUInteger i = 0; i < rangeOfLines.length; i++) {
        int row = rangeOfLines.location + i;
        screen_char_t *theLine = [source.screen getLineAtIndex:row];
        [_screen appendScreenChars:theLine length:width continuation:theLine[width]];
    }
}

- (void)updateVariables {
    if (_name) {
        _variables[kVariableKeySessionName] = [[_name copy] autorelease];
    } else {
        [_variables removeObjectForKey:kVariableKeySessionName];
    }

    _variables[kVariableKeySessionColumns] = [NSString stringWithFormat:@"%d", _screen.width];
    _variables[kVariableKeySessionRows] = [NSString stringWithFormat:@"%d", _screen.height];
    VT100RemoteHost *remoteHost = [self currentHost];
    if (remoteHost.hostname) {
        _variables[kVariableKeySessionHostname] = remoteHost.hostname;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionHostname];
    }
    if (remoteHost.username) {
        _variables[kVariableKeySessionUsername] = remoteHost.username;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionUsername];
    }
    NSString *path = [_screen workingDirectoryOnLine:_screen.numberOfScrollbackLines + _screen.cursorY - 1];
    if (path) {
        _variables[kVariableKeySessionPath] = path;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionPath];
    }
    if (_lastCommand) {
        _variables[kVariableKeySessionLastCommand] = _lastCommand;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionLastCommand];
    }
    NSString *tty = [self tty];
    if (tty) {
        _variables[kVariableKeySessionTTY] = tty;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionTTY];
    }
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (void)coprocessChanged
{
    [_textview setNeedsDisplay:YES];
}

- (void)windowResized
{
    // When the window is resized the title is temporarily changed and it's our
    // timer that resets it.
    if (!_exited) {
        [self scheduleUpdateIn:kBackgroundSessionIntervalSec];
    }
}

+ (void)drawArrangementPreview:(NSDictionary *)arrangement frame:(NSRect)frame
{
    Profile* theBookmark =
        [[ProfileModel sharedInstance] bookmarkWithGuid:[[arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK]
                                                             objectForKey:KEY_GUID]];
    if (!theBookmark) {
        theBookmark = [arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK];
    }
    //    [self setForegroundColor:[ITAddressBookMgr decodeColor:[aDict objectForKey:KEY_FOREGROUND_COLOR]]];
    [[ITAddressBookMgr decodeColor:[theBookmark objectForKey:KEY_BACKGROUND_COLOR]] set];
    NSRectFill(frame);
}

- (void)setSizeFromArrangement:(NSDictionary*)arrangement
{
    [self setWidth:[[arrangement objectForKey:SESSION_ARRANGEMENT_COLUMNS] intValue]
            height:[[arrangement objectForKey:SESSION_ARRANGEMENT_ROWS] intValue]];
}

+ (PTYSession*)sessionFromArrangement:(NSDictionary *)arrangement
                               inView:(SessionView *)sessionView
                                inTab:(PTYTab *)theTab
                        forObjectType:(iTermObjectType)objectType {
    DLog(@"Restoring session from arrangement");
    PTYSession* aSession = [[[PTYSession alloc] init] autorelease];
    aSession.view = sessionView;
    [sessionView setSession:aSession];

    [[sessionView findViewController] setDelegate:aSession];
    Profile* theBookmark =
        [[ProfileModel sharedInstance] bookmarkWithGuid:[[arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK]
                                                            objectForKey:KEY_GUID]];
    BOOL needDivorce = NO;
    if (!theBookmark) {
        NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[arrangement objectForKey:SESSION_ARRANGEMENT_BOOKMARK]];
        // Keep it from stepping on an existing sesion with the same guid.
        temp[KEY_GUID] = [ProfileModel freshGuid];
        theBookmark = temp;
        needDivorce = YES;
    }
    [[aSession screen] setUnlimitedScrollback:[[theBookmark objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[[theBookmark objectForKey:KEY_SCROLLBACK_LINES] intValue]];

     // set our preferences
    [aSession setProfile:theBookmark];

    [aSession setScreenSize:[sessionView frame] parent:[theTab realParentWindow]];
    NSDictionary *state = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_STATE];
    if (state) {
        // For tmux tabs, get the size from the arrangement instead of the containing view because
        // it helps things to line up correctly.
        [aSession setSizeFromArrangement:arrangement];
    }
    [aSession setPreferencesFromAddressBookEntry:theBookmark];
    [aSession loadInitialColorTable];
    [aSession setName:[theBookmark objectForKey:KEY_NAME]];
    NSString *arrangementBookmarkName = arrangement[SESSION_ARRANGEMENT_BOOKMARK_NAME];
    if (arrangementBookmarkName) {
        [aSession setBookmarkName:arrangementBookmarkName];
    } else {
        [aSession setBookmarkName:[theBookmark objectForKey:KEY_NAME]];
    }
    if ([[[[theTab realParentWindow] window] title] compare:@"Window"] == NSOrderedSame) {
        [[theTab realParentWindow] setWindowTitle];
    }
    [aSession setTab:theTab];

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

    if (arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS]) {
        aSession.substitutions = arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS];
    } else {
        haveSavedProgramData = NO;
    }


    NSNumber *tmuxPaneNumber = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_PANE];
    BOOL shouldEnterTmuxMode = NO;
    BOOL didRestoreContents = NO;
    BOOL attachedToServer = NO;
    if (!tmuxPaneNumber) {
        DLog(@"No tmux pane ID during session restoration");
        // |contents| will be non-nil when using system window restoration.
        NSDictionary *contents = arrangement[SESSION_ARRANGEMENT_CONTENTS];
        BOOL runCommand = YES;
        if ([iTermAdvancedSettingsModel runJobsInServers]) {
            DLog(@"Configured to run jobs in servers");
            // iTerm2 is currently configured to run jobs in servers, but we
            // have to check if the arrangement was saved with that setting on.
            if (arrangement[SESSION_ARRANGEMENT_SERVER_PID]) {
                DLog(@"Have a server PID in the arrangement");
                // The arrangement was save with a process ID so the server may still exist.
                if ([arrangement[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] boolValue]) {
                    DLog(@"Was a tmux gateway. Start recovery mode in parser.");
                    // Before attaching to the server we can put the parser into "tmux recovery mode".
                    [aSession.terminal.parser startTmuxRecoveryMode];
                }
                pid_t serverPid = [arrangement[SESSION_ARRANGEMENT_SERVER_PID] intValue];
                DLog(@"Try to attach to pid %d", (int)serverPid);
                // serverPid might be -1 if the user turned on session restoration and then quit.
                if (serverPid != -1 && [aSession tryToAttachToServerWithProcessId:serverPid]) {
                    DLog(@"Success!");
                    runCommand = NO;
                    attachedToServer = YES;
                    shouldEnterTmuxMode = ([arrangement[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] boolValue] &&
                                           arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME] != nil &&
                                           arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] != nil);
                }
            }
        }

        if (runCommand) {
            // This path is NOT taken when attaching to a running server.
            //
            // When restoring a window arrangement with contents and a nonempty saved directory, always
            // use the saved working directory, even if that contravenes the default setting for the
            // profile.
            NSString *oldCWD = arrangement[SESSION_ARRANGEMENT_WORKING_DIRECTORY];
            DLog(@"Running command...");
            if (haveSavedProgramData) {
                if (oldCWD) {
                    // Replace PWD with the working directory at the time the arrangement was saved
                    // so it will be properly restored.
                    NSMutableDictionary *temp = [[aSession.environment mutableCopy] autorelease];
                    temp[PWD_ENVNAME] = oldCWD;
                    aSession.environment = temp;

                    if ([aSession.program isEqualToString:[ITAddressBookMgr standardLoginCommand]]) {
                        // Create a login session that drops you in the old directory instead of
                        // using login -fp "$USER". This lets saved arrangements properly restore
                        // the working directory when the profile specifies the home directory.
                        aSession.program = [ITAddressBookMgr shellLauncherCommand];
                    }
                }
                [aSession startProgram:aSession.program
                           environment:aSession.environment
                                isUTF8:aSession.isUTF8
                         substitutions:aSession.substitutions];
            } else {
                [aSession runCommandWithOldCwd:oldCWD
                                 forObjectType:objectType
                                forceUseOldCWD:contents != nil && oldCWD.length
                                 substitutions:arrangement[SESSION_ARRANGEMENT_SUBSTITUTIONS]];
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
        if (contents && [iTermAdvancedSettingsModel restoreWindowContents]) {
            DLog(@"Loading content from line buffer dictionary");
            [aSession setContentsFromLineBufferDictionary:contents
                                 includeRestorationBanner:runCommand
                                               reattached:attachedToServer];
            didRestoreContents = YES;
        }
    } else {
        // Is a tmux pane
        NSString *title = [state objectForKey:@"title"];
        if (title) {
            [aSession setName:title];
            [aSession setWindowTitle:title];
        }
        if ([aSession.profile[KEY_AUTOLOG] boolValue]) {
            [aSession.shell startLoggingToFileWithPath:[aSession _autoLogFilenameForTermId:aSession.sessionId]
                                          shouldAppend:NO];
        }
    }
    if (needDivorce) {
        [aSession divorceAddressBookEntryFromPreferences];
        [aSession sessionProfileDidChange];
    }

    if (tmuxPaneNumber) {
        [aSession setTmuxPane:[tmuxPaneNumber intValue]];
    }
    NSArray *history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_HISTORY];
    if (history) {
        [[aSession screen] setHistory:history];
    }
    history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_ALT_HISTORY];
    if (history) {
        [[aSession screen] setAltScreen:history];
    }
    if (arrangement[SESSION_ARRANGEMENT_NAME]) {
        [aSession setName:arrangement[SESSION_ARRANGEMENT_NAME]];
    }
    if (arrangement[SESSION_ARRANGEMENT_DEFAULT_NAME]) {
        [aSession setDefaultName:arrangement[SESSION_ARRANGEMENT_DEFAULT_NAME]];
    }
    if (arrangement[SESSION_ARRANGEMENT_WINDOW_TITLE]) {
        [aSession setWindowTitle:arrangement[SESSION_ARRANGEMENT_WINDOW_TITLE]];
    }
    if (arrangement[SESSION_ARRANGEMENT_VARIABLES]) {
        NSDictionary *variables = arrangement[SESSION_ARRANGEMENT_VARIABLES];
        for (id key in variables) {
            aSession.variables[key] = variables[key];
        }
        aSession.textview.badgeLabel = aSession.badgeLabel;
    }
    if (arrangement[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED]) {
        aSession->_shellIntegrationEverUsed = [arrangement[SESSION_ARRANGEMENT_SHELL_INTEGRATION_EVER_USED] boolValue];
    }
    if (arrangement[SESSION_ARRANGEMENT_COMMANDS]) {
        [aSession.commands addObjectsFromArray:arrangement[SESSION_ARRANGEMENT_COMMANDS]];
    }
    if (arrangement[SESSION_ARRANGEMENT_DIRECTORIES]) {
        [aSession.directories addObjectsFromArray:arrangement[SESSION_ARRANGEMENT_DIRECTORIES]];
    }
    if (arrangement[SESSION_ARRANGEMENT_HOSTS]) {
        for (NSDictionary *host in arrangement[SESSION_ARRANGEMENT_HOSTS]) {
            VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] initWithDictionary:host] autorelease];
            if (remoteHost) {
                [aSession.hosts addObject:remoteHost];
            }
        }
    }

    if (arrangement[SESSION_ARRANGEMENT_SELECTION]) {
        [aSession.textview.selection setFromDictionaryValue:arrangement[SESSION_ARRANGEMENT_SELECTION]];
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
        aSession.lastRemoteHost = [aSession.screen.lastRemoteHost retain];
        if (arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY]) {
            [aSession->_lastDirectory autorelease];
            aSession->_lastDirectory = [arrangement[SESSION_ARRANGEMENT_LAST_DIRECTORY] copy];
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
        [theTab addHiddenLiveView:liveView];
        aSession.liveSession = [self sessionFromArrangement:liveArrangement
                                                     inView:liveView
                                                      inTab:theTab
                                              forObjectType:objectType];
    }
    if (shouldEnterTmuxMode) {
        // Restored a tmux gateway session.
        [aSession startTmuxMode];
        [aSession.tmuxController sessionChangedTo:arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME]
                                        sessionId:[arrangement[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] intValue]];
    }

    VT100RemoteHost *lastRemoteHost = aSession.screen.lastRemoteHost;
    if (lastRemoteHost) {
        [aSession screenCurrentHostDidChange:lastRemoteHost];
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
    [self queueAnnouncement:announcement identifier:kReopenSessionWarningIdentifier];
}

// Session specific methods
- (BOOL)setScreenSize:(NSRect)aRect parent:(id<WindowControllerInterface>)parent
{
    _screen.delegate = self;

    // Allocate a container to hold the scrollview
    if (!_view) {
        self.view = [[[SessionView alloc] initWithFrame:NSMakeRect(0, 0, aRect.size.width, aRect.size.height)
                                                session:self] autorelease];
        [[_view findViewController] setDelegate:self];
    }

    // Allocate a scrollview
    _scrollview = [[[PTYScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                   0,
                                                                   aRect.size.width,
                                                                   aRect.size.height)
                                    hasVerticalScroller:[parent scrollbarShouldBeVisible]] autorelease];
    NSParameterAssert(_scrollview != nil);
    [_scrollview setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable];

    // assign the main view
    [_view addSubview:_scrollview];
    if (![self isTmuxClient]) {
        [_view setAutoresizesSubviews:YES];
    }
    // TODO(georgen): I disabled setCopiesOnScroll because there is a vertical margin in the PTYTextView and
    // we would not want that copied. This is obviously bad for performance when scrolling, but it's unclear
    // whether the difference will ever be noticable. I believe it could be worked around (painfully) by
    // subclassing NSClipView and overriding viewBoundsChanged: and viewFrameChanged: so that it coipes on
    // scroll but it doesn't include the vertical marigns when doing so.
    // The vertical margins are indespensable because different PTYTextViews may use different fonts/font
    // sizes, but the window size does not change as you move from tab to tab. If the margin is outside the
    // NSScrollView's contentView it looks funny.
    [[_scrollview contentView] setCopiesOnScroll:NO];

    // Allocate a text view
    NSSize aSize = [_scrollview contentSize];
    _wrapper = [[TextViewWrapper alloc] initWithFrame:NSMakeRect(0, 0, aSize.width, aSize.height)];

    // In commit f6dabc53024d13ec1bd7be92bf505f72f87ea779, the max-y margin was
    // made flexible. The commit description there explains why. But then I
    // found that it was causing unsatisfiable constraints that were more
    // reproducible when maximizing a tmux window. It had a constraint like
    // this:
    //     "<NSAutoresizingMaskLayoutConstraint:0x60000068a230 h=-&- v=-&& TextViewWrapper:0x60800012b900.height == 3.0687*NSClipView:0x1009d6920.height - 6.1374>",
    // Which is obviously wrong. This is a less-wrong answer, but still pretty
    // obviously broken. Maybe I shouldn't use autoresizing masks for the
    // wrapper at all. This is a big complicated mess that I need to
    // disentangle.
    [_wrapper setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _textview = [[PTYTextView alloc] initWithFrame: NSMakeRect(0, VMARGIN, aSize.width, aSize.height)
                                          colorMap:_colorMap];
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

    [_wrapper addSubview:_textview];
    [_textview setFrame:NSMakeRect(0, VMARGIN, aSize.width, aSize.height - VMARGIN)];
    [_textview release];

    // assign terminal and task objects
    _terminal.delegate = _screen;
    [_shell setDelegate:self];

    // initialize the screen
    int width = (aSize.width - MARGIN*2) / [_textview charWidth];
    int height = (aSize.height - VMARGIN*2) / [_textview lineHeight];
    // NB: In the bad old days, this returned whether setup succeeded because it would allocate an
    // enormous amount of memory. That's no longer an issue.
    [_screen destructivelySetScreenWidth:width height:height];
    [self setName:@"Shell"];
    [self setDefaultName:@"Shell"];

    [_textview setDataSource:_screen];
    [_textview setDelegate:self];
    [_scrollview setDocumentView:_wrapper];
    [_wrapper release];
    [_scrollview setDocumentCursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeIBeam]];
    [_scrollview setLineScroll:[_textview lineHeight]];
    [_scrollview setPageScroll:2 * [_textview lineHeight]];
    [_scrollview setHasVerticalScroller:[parent scrollbarShouldBeVisible]];

    _antiIdleCode = 0;
    [_antiIdleTimer release];
    _antiIdleTimer = nil;
    _newOutput = NO;
    [_view updateScrollViewFrame];

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
        [_shell setWidth:_screen.width height:_screen.height];
        @synchronized(self) {
            _registered = YES;
        }
    } else {
        DLog(@"Can't attach to a server when runJobsInServers is off.");
    }
}

- (void)runCommandWithOldCwd:(NSString*)oldCWD
               forObjectType:(iTermObjectType)objectType
              forceUseOldCWD:(BOOL)forceUseOldCWD
               substitutions:(NSDictionary *)substitutions {
    NSString *pwd;
    BOOL isUTF8;

    // Grab the addressbook command
    Profile* profile = [self profile];
    Profile *profileForComputingCommand = profile;
    if (forceUseOldCWD) {
        NSMutableDictionary *temp = [[profile mutableCopy] autorelease];
        temp[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue;
        profileForComputingCommand = temp;
    }
    NSString *cmd = [ITAddressBookMgr bookmarkCommand:profileForComputingCommand
                                        forObjectType:objectType];
    NSString *theName = [profile[KEY_NAME] stringByPerformingSubstitutions:substitutions];

    if (forceUseOldCWD) {
        pwd = oldCWD;
    } else {
        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:profile
                                           forObjectType:objectType];
    }
    if ([pwd length] == 0) {
        if (oldCWD) {
            pwd = oldCWD;
        } else {
            pwd = NSHomeDirectory();
        }
    }
    isUTF8 = ([profile[KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

    [[[self tab] realParentWindow] setName:theName forSession:self];

    // Start the command
    [self startProgram:cmd
           environment:@{ @"PWD": pwd }
                isUTF8:isUTF8
         substitutions:substitutions];
}

- (void)setWidth:(int)width height:(int)height
{
    DLog(@"Set session %@ to %dx%d", self, width, height);
    [_screen resizeWidth:width height:height];
    [_shell setWidth:width height:height];
    [_textview clearHighlights];
    [[_tab realParentWindow] invalidateRestorableState];
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move {
    [[self view] setSplitSelectionMode:mode move:move];
}

- (int)overUnder:(int)proposedSize inVerticalDimension:(BOOL)vertically
{
    int x = proposedSize;
    if (vertically) {
        if ([_view showTitle]) {
            x -= [SessionView titleHeight];
        }
        x -= VMARGIN * 2;
        int iLineHeight = [_textview lineHeight];
        if (iLineHeight == 0) {
            return 0;
        }
        x %= iLineHeight;
        if (x > iLineHeight / 2) {
            x -= iLineHeight;
        }
        return x;
    } else {
        x -= MARGIN * 2;
        int iCharWidth = [_textview charWidth];
        if (iCharWidth == 0) {
            return 0;
        }
        x %= iCharWidth;
        if (x > iCharWidth / 2) {
            x -= iCharWidth;
        }
    }
    return x;
}

- (NSArray *)childJobNames
{
    int skip = 0;
    pid_t thePid = [_shell pid];
    if ([[[ProcessCache sharedInstance] getNameOfPid:thePid isForeground:nil] isEqualToString:@"login"]) {
        skip = 1;
    }
    NSMutableArray *names = [NSMutableArray array];
    for (NSNumber *n in [[ProcessCache sharedInstance] childrenOfPid:thePid levelsToSkip:skip]) {
        pid_t pid = [n intValue];
        NSDictionary *info = [[ProcessCache sharedInstance] dictionaryOfTaskInfoForPid:pid];
        [names addObject:[info objectForKey:PID_INFO_NAME]];
    }
    return names;
}

- (BOOL)promptOnClose
{
    if (_exited) {
        return NO;
    }
    switch ([[_profile objectForKey:KEY_PROMPT_CLOSE] intValue]) {
        case PROMPT_ALWAYS:
            return YES;

        case PROMPT_NEVER:
            return NO;

        case PROMPT_EX_JOBS: {
            NSArray *jobsThatDontRequirePrompting = [_profile objectForKey:KEY_JOBS];
            for (NSString *childName in [self childJobNames]) {
                if ([jobsThatDontRequirePrompting indexOfObject:childName] == NSNotFound) {
                    // This job is not in the ignore list.
                    return YES;
                }
            }
            // All jobs were in the ignore list.
            return NO;
        }
    }

    return YES;
}

- (NSString *)_autoLogFilenameForTermId:(NSString *)termid
{
    // $(LOGDIR)/YYYYMMDD_HHMMSS.$(NAME).wNtNpN.$(PID).$(RANDOM).log
    return [NSString stringWithFormat:@"%@/%@.%@.%@.%d.%0x.log",
            [_profile objectForKey:KEY_LOGDIR],
            [[NSDate date] descriptionWithCalendarFormat:@"%Y%m%d_%H%M%S"
                                                timeZone:nil
                                                  locale:nil],
            [_profile objectForKey:KEY_NAME],
            termid,
            (int)getpid(),
            (int)arc4random()];
}

- (BOOL)shouldSetCtype {
    return ![iTermAdvancedSettingsModel doNotSetCtype];
}

- (NSString *)sessionId {
    return [NSString stringWithFormat:@"w%dt%dp%lu",
            [[_tab realParentWindow] number],
            _tab.tabNumberForItermSessionId,
            (unsigned long)_tab.sessions.count];
}

- (void)startProgram:(NSString *)command
         environment:(NSDictionary *)environment
              isUTF8:(BOOL)isUTF8
       substitutions:(NSDictionary *)substitutions {
    self.program = command;
    self.environment = environment ?: @{};
    self.isUTF8 = isUTF8;
    self.substitutions = substitutions ?: @{};

    NSString *program = [command stringByPerformingSubstitutions:substitutions];
    NSArray *components = [program componentsInShellCommand];
    NSArray *arguments;
    if (components.count > 0) {
        program = components[0];
        arguments = [components subarrayWithRange:NSMakeRange(1, components.count - 1)];
    } else {
        arguments = @[];
    }

    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:environment];

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
        NSString *lang = [self _lang];
        if (lang) {
            DLog(@"set LANG=%@", lang);
            env[@"LANG"] = lang;
        } else if ([self shouldSetCtype]){
            DLog(@"should set ctype...");
            // Try just the encoding by itself, which might work.
            NSString *encName = [self encodingName];
            DLog(@"See if encoding %@ is supported...", encName);
            if (encName && [self _localeIsSupported:encName]) {
                DLog(@"Set LC_CTYPE=%@", encName);
                env[@"LC_CTYPE"] = encName;
            }
        }
    }

    if (env[PWD_ENVNAME] == nil) {
        // Set "PWD"
        env[PWD_ENVNAME] = [PWD_ENVVALUE stringByExpandingTildeInPath];
    }

    NSString *itermId = [self sessionId];
    env[@"ITERM_SESSION_ID"] = itermId;
    if (_profile[KEY_NAME]) {
        env[@"ITERM_PROFILE"] = [_profile[KEY_NAME] stringByPerformingSubstitutions:substitutions];
    }
    if ([_profile[KEY_AUTOLOG] boolValue]) {
        [_shell startLoggingToFileWithPath:[self _autoLogFilenameForTermId:itermId]
                              shouldAppend:NO];
    }
    @synchronized(self) {
      _registered = YES;
    }
    [_shell launchWithPath:program
                 arguments:arguments
               environment:env
                     width:[_screen width]
                    height:[_screen height]
                    isUTF8:isUTF8];
    NSString *initialText = _profile[KEY_INITIAL_TEXT];
    if ([initialText length]) {
        [_shell writeTask:[initialText dataUsingEncoding:[self encoding]]];
        [_shell writeTask:[@"\n" dataUsingEncoding:[self encoding]]];
    }
}

- (void)launchProfileInCurrentTerminal:(Profile *)profile
                               withURL:(NSString *)url
{
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    [[iTermController sharedInstance] launchBookmark:profile
                                          inTerminal:term
                                             withURL:url
                                            isHotkey:NO
                                             makeKey:NO
                                             command:nil
                                               block:nil];
}

- (void)selectPaneLeftInCurrentTerminal
{
    [[[iTermController sharedInstance] currentTerminal] selectPaneLeft:nil];
}

- (void)selectPaneRightInCurrentTerminal
{
    [[[iTermController sharedInstance] currentTerminal] selectPaneRight:nil];
}

- (void)selectPaneAboveInCurrentTerminal
{
    [[[iTermController sharedInstance] currentTerminal] selectPaneUp:nil];
}

- (void)selectPaneBelowInCurrentTerminal
{
    [[[iTermController sharedInstance] currentTerminal] selectPaneDown:nil];
}

- (void)_maybeWarnAboutShortLivedSessions
{
    if ([(iTermApplicationDelegate *)[NSApp delegate] isApplescriptTestApp]) {
        // The applescript test driver doesn't care about short-lived sessions.
        return;
    }
    if ([[NSDate date] timeIntervalSinceDate:_creationDate] < 3) {
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
                               silenceable:kiTermWarningTypePermanentlySilenceable];
    }
}

- (iTermRestorableSession *)restorableSession {
    iTermRestorableSession *restorableSession = [[[iTermRestorableSession alloc] init] autorelease];
    restorableSession.sessions = @[ self ];
    restorableSession.terminalGuid = self.tab.realParentWindow.terminalGuid;
    restorableSession.tabUniqueId = self.tab.uniqueId;
    restorableSession.arrangement = self.tab.arrangement;
    restorableSession.group = kiTermRestorableSessionGroupSession;

    return restorableSession;
}

- (void)restartSession {
    assert(self.isRestartable);
    [self dismissAnnouncementWithIdentifier:kReopenSessionWarningIdentifier];
    if (_exited) {
        [self replaceTerminatedShellWithNewInstance];
    } else {
        _shouldRestart = YES;
        [_shell sendSignal:SIGKILL];
    }
}

// Terminate a replay session but not the live session
- (void)softTerminate {
    _liveSession = nil;
    [self terminate];
}

- (void)terminate {
    DLog(@"terminate called from %@", [NSThread callStackSymbols]);

    if ([[self textview] isFindingCursor]) {
        [[self textview] endFindCursor];
    }
    if (_exited) {
        [self _maybeWarnAboutShortLivedSessions];
    }
    if (self.tmuxMode == TMUX_CLIENT) {
        assert([_tab tmuxWindow] >= 0);
        [_tmuxController deregisterWindow:[_tab tmuxWindow]
                               windowPane:_tmuxPane
                                  session:self];
        // This call to fitLayoutToWindows is necessary to handle the case where
        // a small window closes and leaves behind a larger (e.g., fullscreen)
        // window. We want to set the client size to that of the smallest
        // remaining window.
        int n = [[_tab sessions] count];
        if ([[_tab sessions] indexOfObjectIdenticalTo:self] != NSNotFound) {
            n--;
        }
        if (n == 0) {
            // The last session in this tab closed so check if the client has
            // changed size
            [_tmuxController fitLayoutToWindows];
        }
    } else if (self.tmuxMode == TMUX_GATEWAY) {
        [_tmuxController detach];
        [_tmuxGateway release];
        _tmuxGateway = nil;
    }
    BOOL undoable = (![self isTmuxClient] &&
                     !_shouldRestart &&
                     !_synthetic &&
                     ![[iTermController sharedInstance] applicationIsQuitting]);
    [_terminal.parser forceUnhookDCS];
    self.tmuxMode = TMUX_NONE;
    [_tmuxController release];
    _tmuxController = nil;

    // The source pane may have just exited. Dogs and cats living together!
    // Mass hysteria!
    [[MovePaneController sharedInstance] exitMovePaneMode];

    // deregister from the notification center
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_liveSession) {
        [_liveSession terminate];
    }

    _exited = YES;
    [_view retain];  // hardstop and revive will release this.
    if (undoable) {
        // TODO: executeTokens:bytesHandled: should queue up tokens to avoid a race condition.
        [self makeTerminationUndoable];
    } else {
        [self hardStop];
    }

    // final update of display
    [self updateDisplay];

    [_tab removeSession:self];

    _colorMap.delegate = nil;

    _screen.delegate = nil;
    [_screen setTerminal:nil];
    _terminal.delegate = nil;
    if ([[_view findViewController] delegate] == self) {
        [[_view findViewController] setDelegate:nil];
    }

    [_updateTimer invalidate];
    [_updateTimer release];
    _updateTimer = nil;

    [_pasteHelper abort];

    [[_tab realParentWindow] sessionDidTerminate:self];

    _tab = nil;
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
    _textview = nil;
}

- (BOOL)revive {
    if (_shell.paused) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(hardStop)
                                                   object:nil];
        if (!_shell.hasBrokenPipe) {
            _exited = NO;
        }
        _textview.dataSource = _screen;
        _textview.delegate = self;
        _colorMap.delegate = _textview;
        _screen.delegate = self;
        _screen.terminal = _terminal;
        _terminal.delegate = _screen;
        _shell.paused = NO;
        [_view autorelease];  // This balances a retain in -terminate prior to calling -makeTerminationUndoable
        return YES;
    } else {
        return NO;
    }
}

- (void)writeTaskImpl:(NSData *)data canBroadcast:(BOOL)canBroadcast {
    if (gDebugLogging) {
        NSArray *stack = [NSThread callStackSymbols];
        DLog(@"writeTaskImpl<%p> canBroadcast=%@: called from %@", self, @(canBroadcast), stack);
        const char *bytes = [data bytes];
        for (int i = 0; i < [data length]; i++) {
            DLog(@"writeTask keydown %d: %d (%c)", i, (int)bytes[i], bytes[i]);
        }
    }

    // check if we want to send this input to all the sessions
    if (canBroadcast && [[[self tab] realParentWindow] broadcastInputToSession:self]) {
        // Ask the parent window to write directly to the PTYTask of all
        // sessions being broadcasted to.
        [[[self tab] realParentWindow] sendInputToAllSessions:data];
    } else if (!_exited) {
        // Send to only this session
        if (canBroadcast) {
            // It happens that canBroadcast coincides with explicit user input. This is less than
            // beautiful here, but in that case we want to turn off the bell and scroll to the
            // bottom.
            [self setBell:NO];
            PTYScroller* ptys = (PTYScroller*)[_scrollview verticalScroller];
            [ptys setUserScroll:NO];
        }
        [_shell writeTask:data];
    }
}

- (void)writeTaskNoBroadcast:(NSData *)data
{
    if (self.tmuxMode == TMUX_CLIENT) {
        [[_tmuxController gateway] sendKeys:data
                               toWindowPane:_tmuxPane];
        return;
    }
    [self writeTaskImpl:data canBroadcast:NO];
}

- (void)handleKeypressInTmuxGateway:(unichar)unicode
{
    if (unicode == 27) {
        [self tmuxDetach];
    } else if (unicode == 'L') {
        _tmuxGateway.tmuxLogging = !_tmuxGateway.tmuxLogging;
        [self printTmuxMessage:[NSString stringWithFormat:@"tmux logging %@", (_tmuxGateway.tmuxLogging ? @"on" : @"off")]];
    } else if (unicode == 'C') {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Enter command to send tmux:"
                                         defaultButton:@"OK"
                                       alternateButton:@"Cancel"
                                           otherButton:nil
                             informativeTextWithFormat:@""];
        NSTextField *tmuxCommand = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease];
        [tmuxCommand setEditable:YES];
        [tmuxCommand setSelectable:YES];
        [alert setAccessoryView:tmuxCommand];
        if ([alert runModal] == NSAlertDefaultReturn && [[tmuxCommand stringValue] length]) {
            [self printTmuxMessage:[NSString stringWithFormat:@"Run command \"%@\"", [tmuxCommand stringValue]]];
            [_tmuxGateway sendCommand:[tmuxCommand stringValue]
                       responseTarget:self
                     responseSelector:@selector(printTmuxCommandOutputToScreen:)];
        }
    } else if (unicode == 'X') {
        [self printTmuxMessage:@"Exiting tmux mode, but tmux client may still be running."];
        [self tmuxHostDisconnected];
    }
}

- (void)writeTask:(NSData*)data
{
    if (self.tmuxMode == TMUX_CLIENT) {
        [self setBell:NO];
        if ([[_tab realParentWindow] broadcastInputToSession:self]) {
            [[_tab realParentWindow] sendInputToAllSessions:data];
        } else {
            [[_tmuxController gateway] sendKeys:data
                                   toWindowPane:_tmuxPane];
        }
        PTYScroller* ptys = (PTYScroller*)[_scrollview verticalScroller];
        [ptys setUserScroll:NO];
        return;
    } else if (self.tmuxMode == TMUX_GATEWAY) {
        // Use keypresses for tmux gateway commands for development and debugging.
        NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        for (int i = 0; i < s.length; i++) {
            unichar unicode = [s characterAtIndex:i];
            [self handleKeypressInTmuxGateway:unicode];
        }
        return;
    }
    self.currentMarkOrNotePosition = nil;
    [self writeTaskImpl:data canBroadcast:YES];
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
    OSAtomicAdd32(length, &_bytesReceivedSinceSendingEchoProbe);

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

    // This limits the number of outstanding execution blocks to prevent the main thread from
    // getting bogged down.
    dispatch_semaphore_wait(_executionSemaphore, DISPATCH_TIME_FOREVER);

    [self retain];
    dispatch_retain(_executionSemaphore);
    dispatch_async(dispatch_get_main_queue(), ^{
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

- (void)executeTokens:(const CVector *)vector bytesHandled:(int)length {
    STOPWATCH_START(executing);
    int n = CVectorCount(vector);

    if (_shell.paused) {
        // Session was closed. The close may be undone, so queue up tokens.
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
        [_queuedTokens removeAllObjects];
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
            [token recycleObject];
        }
        CVectorDestroy(&temp);
    })
    STOPWATCH_LAP(executing);
}

- (void)finishedHandlingNewOutputOfLength:(int)length {
    _lastOutput = [NSDate timeIntervalSinceReferenceDate];
    _newOutput = YES;

    // Make sure the screen gets redrawn soonish
    _updateDisplayUntil = [NSDate timeIntervalSinceReferenceDate] + 10;
    if ([[[self tab] parentWindow] currentTab] == [self tab]) {
        if (length < 1024) {
            [self scheduleUpdateIn:kFastTimerIntervalSec];
        } else {
            [self scheduleUpdateIn:kSlowTimerIntervalSec];
        }
    } else {
        [self scheduleUpdateIn:kBackgroundSessionIntervalSec];
    }
    [[ProcessCache sharedInstance] notifyNewOutput];
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
    for (Trigger *trigger in _triggers) {
        BOOL stop = [trigger tryString:stringLine
                             inSession:self
                           partialLine:partial
                            lineNumber:startAbsLineNumber];
        if (stop) {
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
    if (width > 0) {
        [_screen appendImageAtCursorWithName:@"BrokenPipeDivider"
                                       width:width
                                       units:kVT100TerminalUnitsCells
                                      height:1
                                       units:kVT100TerminalUnitsCells
                         preserveAspectRatio:NO
                                       image:[NSImage imageNamed:@"BrokenPipeDivider"]
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
                                       image:[NSImage imageNamed:@"BrokenPipeDivider"]
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
        [self writeTask:data];
    }
}

- (void)threadedTaskBrokenPipe
{
    // Put the call to brokenPipe in the same queue as executeTokens:bytesHandled: to avoid a race.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self brokenPipe];
    });
}

- (void)brokenPipe {
    if (_exited) {
        return;
    }
    [_shell killServerIfRunning];
    if ([self shouldPostGrowlNotification] &&
        [iTermProfilePreferences boolForKey:KEY_SEND_SESSION_ENDED_ALERT inProfile:self.profile]) {
        [[iTermGrowlDelegate sharedInstance] growlNotify:@"Session Ended"
                                         withDescription:[NSString stringWithFormat:@"Session \"%@\" in tab #%d just terminated.",
                                                          [self name],
                                                          [[self tab] realObjectCount]]
                                         andNotification:@"Broken Pipes"];
    }

    _exited = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:kCurrentSessionDidChange object:nil];
    [[self tab] updateLabelAttributes];

    if (_shouldRestart) {
        [_terminal resetPreservingPrompt:NO];
        [self appendBrokenPipeMessage:@"Session Restarted"];
        [self replaceTerminatedShellWithNewInstance];
    } else if ([self autoClose]) {
        [[self tab] closeSession:self];
    } else {
        // Offer to restart the session by rerunning its program.
        [self appendBrokenPipeMessage:@"Broken Pipe"];
        if ([self isRestartable]) {
            iTermAnnouncementViewController *announcement =
                [iTermAnnouncementViewController announcementWithTitle:@"Session ended (broken pipe). Restart it?"
                                                                 style:kiTermAnnouncementViewStyleQuestion
                                                           withActions:@[ @"Restart" ]
                                                            completion:^(int selection) {
                                                                switch (selection) {
                                                                    case -2:  // Dismiss programmatically
                                                                        break;

                                                                    case -1: // No
                                                                        break;

                                                                    case 0: // Yes
                                                                        [self replaceTerminatedShellWithNewInstance];
                                                                        break;
                                                                }
                                                            }];
            [self queueAnnouncement:announcement identifier:kReopenSessionWarningIdentifier];
        }
        [self updateDisplay];
    }
}

- (BOOL)isRestartable {
    return _program != nil;
}

- (void)replaceTerminatedShellWithNewInstance {
    assert(self.isRestartable);
    assert(_exited);
    _shouldRestart = NO;
    _exited = NO;
    [_shell release];
    _shell = [[PTYTask alloc] init];
    [_shell setDelegate:self];
    [_shell setWidth:_screen.width
              height:_screen.height];
    [self startProgram:_program
           environment:_environment
                isUTF8:_isUTF8
         substitutions:_substitutions];
}

- (NSSize)idealScrollViewSizeWithStyle:(NSScrollerStyle)scrollerStyle
{
    NSSize innerSize = NSMakeSize([_screen width] * [_textview charWidth] + MARGIN * 2,
                                  [_screen height] * [_textview lineHeight] + VMARGIN * 2);
    BOOL hasScrollbar = [[_tab realParentWindow] scrollbarShouldBeVisible];
    NSSize outerSize =
        [PTYScrollView frameSizeForContentSize:innerSize
                       horizontalScrollerClass:nil
                         verticalScrollerClass:hasScrollbar ? [PTYScroller class] : nil
                                    borderType:NSNoBorder
                                   controlSize:NSRegularControlSize
                                 scrollerStyle:scrollerStyle];
        return outerSize;
}

- (int)_keyBindingActionForEvent:(NSEvent*)event
{
    unsigned int modflag;
    NSString *unmodkeystr;
    unichar unmodunicode;
    int keyBindingAction;
    NSString *keyBindingText;

    modflag = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    /*
    unsigned short keycode = [event keyCode];
    NSString *keystr = [event characters];
    unichar unicode = [keystr length] > 0 ? [keystr characterAtIndex:0] : 0;
    NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));
    */

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
                                    modifiers:NSCommandKeyMask | NSAlternateKeyMask | NSNumericPadKeyMask
                                   inBookmark:temp];
    [iTermKeyBindingMgr removeMappingWithCode:NSRightArrowFunctionKey
                                    modifiers:NSCommandKeyMask | NSAlternateKeyMask | NSNumericPadKeyMask
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

+ (BOOL)_recursiveSelectMenuItem:(NSString*)theName inMenu:(NSMenu*)menu
{
    for (NSMenuItem* item in [menu itemArray]) {
        if (![item isEnabled] || [item isHidden]) {
            continue;
        }
        if ([item hasSubmenu]) {
            if ([PTYSession _recursiveSelectMenuItem:theName inMenu:[item submenu]]) {
                return YES;
            }
        } else if ([theName isEqualToString:[item title]]) {
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

    modflag = [event modifierFlags];
    unmodkeystr = [event charactersIgnoringModifiers];
    unmodunicode = [unmodkeystr length]>0?[unmodkeystr characterAtIndex:0]:0;

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[iTermKeyBindingMgr globalKeyMap]];


    if (keyBindingAction == KEY_ACTION_SELECT_MENU_ITEM) {
        [PTYSession selectMenuItem:keyBindingText];
        return YES;
    } else {
        return NO;
    }
}


+ (void)selectMenuItem:(NSString*)theName
{
    if (![self _recursiveSelectMenuItem:theName inMenu:[NSApp mainMenu]]) {
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

- (void)insertNewline:(id)sender
{
    [self insertText:@"\n"];
}

- (void)insertTab:(id)sender
{
    [self insertText:@"\t"];
}

- (void)moveUp:(id)sender
{
    [self writeTask:[_terminal.output keyArrowUp:0]];
}

- (void)moveDown:(id)sender
{
    [self writeTask:[_terminal.output keyArrowDown:0]];
}

- (void)moveLeft:(id)sender
{
    [self writeTask:[_terminal.output keyArrowLeft:0]];
}

- (void)moveRight:(id)sender
{
    [self writeTask:[_terminal.output keyArrowRight:0]];
}

- (void)pageUp:(id)sender
{
    [self writeTask:[_terminal.output keyPageUp:0]];
}

- (void)pageDown:(id)sender
{
    [self writeTask:[_terminal.output keyPageDown:0]];
}

+ (NSData *)pasteboardFile
{
    NSPasteboard *board;

    board = [NSPasteboard generalPasteboard];
    assert(board != nil);

    NSArray *supportedTypes = [NSArray arrayWithObjects:NSFilenamesPboardType, nil];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [board propertyListForType:NSFilenamesPboardType];
        if (filenames.count > 0) {
            NSString *filename = filenames[0];
            return [NSData dataWithContentsOfFile:filename];
        }
    }
    return nil;
}

+ (NSString*)pasteboardString {
    return [NSString stringFromPasteboard];
}

- (void)insertText:(NSString *)string
{
    NSData *data;
    NSMutableString *mstring;
    int i;
    int max;

    if (_exited) {
        return;
    }

    //    NSLog(@"insertText:%@",string);
    mstring = [NSMutableString stringWithString:string];
    max = [string length];
    for (i = 0; i < max; i++) {
        // From http://lists.apple.com/archives/cocoa-dev/2001/Jul/msg00114.html
        // in MacJapanese, the backslash char (ASCII 0xdC) is mapped to Unicode 0xA5.
        // The following line gives you NSString containing an Unicode character Yen sign (0xA5) in Japanese localization.
        // string = [NSString stringWithCString:"\"];
        // TODO: Check the locale before doing this.
        if ([mstring characterAtIndex:i] == 0xa5) {
            [mstring replaceCharactersInRange:NSMakeRange(i, 1) withString:@"\\"];
        }
    }

    data = [mstring dataUsingEncoding:[_terminal encoding]
                 allowLossyConversion:YES];

    if (data != nil) {
        if (gDebugLogging) {
            DebugLog([NSString stringWithFormat:@"writeTask:%@", data]);
        }
        [self writeTask:data];
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

- (void)deleteBackward:(id)sender
{
    unsigned char p = 0x08; // Ctrl+H

    [self writeTask:[NSData dataWithBytes:&p length:1]];
}

- (void)deleteForward:(id)sender
{
    unsigned char p = 0x7F; // DEL

    [self writeTask:[NSData dataWithBytes:&p length:1]];
}

- (PTYScroller *)textViewVerticalScroller
{
    return (PTYScroller *)[_scrollview verticalScroller];
}

- (BOOL)textViewHasCoprocess {
    return [_shell hasCoprocess];
}

- (BOOL)shouldPostGrowlNotification {
    if (!_screen.postGrowlNotifications) {
        return NO;
    }
    if (![[self tab] isForegroundTab]) {
        return YES;
    }
    BOOL windowIsObscured =
        ([[iTermController sharedInstance] terminalIsObscured:self.tab.realParentWindow]);
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

    int charsTakenFromPrefix;
    NSString *filename =
        [semanticHistoryController pathOfExistingFileFoundWithPrefix:selection
                                                              suffix:@""
                                                    workingDirectory:workingDirectory
                                                charsTakenFromPrefix:&charsTakenFromPrefix];
    if (filename &&
        ![[filename stringByReplacingOccurrencesOfString:@"//" withString:@"/"] isEqualToString:@"/"]) {
        if ([_textview openSemanticHistoryPath:filename
                              workingDirectory:workingDirectory
                                        prefix:selection
                                        suffix:@""]) {
            return;
        }
    }

    // Try to open it as a URL.
    NSURL *url =
          [NSURL URLWithString:[selection stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    NSBeep();
}

- (void)setBell:(BOOL)flag
{
    if (flag != _bell) {
        _bell = flag;
        [[self tab] setBell:flag];
        if (_bell) {
            if ([_textview keyIsARepeat] == NO &&
                [self shouldPostGrowlNotification] &&
                [iTermProfilePreferences boolForKey:KEY_SEND_BELL_ALERT inProfile:self.profile]) {
                [[iTermGrowlDelegate sharedInstance] growlNotify:@"Bell"
                                                 withDescription:[NSString stringWithFormat:@"Session %@ #%d just rang a bell!",
                                                                  [self name],
                                                                  [[self tab] realObjectCount]]
                                                 andNotification:@"Bells"
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

- (BOOL)reloadProfile
{
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

    _textview.badgeLabel = [self badgeLabel];
    return didChange;
}

- (void)setPreferencesFromAddressBookEntry:(NSDictionary *)aePrefs
{
    int i;
    NSDictionary *aDict = aePrefs;

    if (aDict == nil) {
        aDict = [[ProfileModel sharedInstance] defaultBookmark];
    }
    if (aDict == nil) {
        return;
    }

    if ([self isTmuxClient] && ![_profile[KEY_NAME] isEqualToString:aePrefs[KEY_NAME]]) {
        _tmuxTitleOutOfSync = YES;
    }

    NSDictionary *keyMap = @{ @(kColorMapForeground): KEY_FOREGROUND_COLOR,
                              @(kColorMapBackground): KEY_BACKGROUND_COLOR,
                              @(kColorMapSelection): KEY_SELECTION_COLOR,
                              @(kColorMapSelectedText): KEY_SELECTED_TEXT_COLOR,
                              @(kColorMapBold): KEY_BOLD_COLOR,
                              @(kColorMapLink): KEY_LINK_COLOR,
                              @(kColorMapCursor): KEY_CURSOR_COLOR,
                              @(kColorMapCursorText): KEY_CURSOR_TEXT_COLOR };
    for (NSNumber *colorKey in keyMap) {
        NSString *profileKey = keyMap[colorKey];
        NSColor *theColor = [[iTermProfilePreferences objectForKey:profileKey
                                                         inProfile:aDict] colorValue];
        [_colorMap setColor:theColor forKey:[colorKey intValue]];
    }

    self.cursorGuideColor = [[iTermProfilePreferences objectForKey:KEY_CURSOR_GUIDE_COLOR
                                                         inProfile:aDict] colorValueWithDefaultAlpha:0.25];
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
    [self setBackgroundImageTiled:[iTermProfilePreferences boolForKey:KEY_BACKGROUND_IMAGE_TILED
                                                            inProfile:aDict]];

    // Color scheme
    // ansiColosMatchingForeground:andBackground:inBookmark does an equality comparison, so
    // iTermProfilePreferences is not used here.
    [self setColorFgBgVariable:[self ansiColorsMatchingForeground:aDict[KEY_FOREGROUND_COLOR]
                                                    andBackground:aDict[KEY_BACKGROUND_COLOR]
                                                       inBookmark:aDict]];

    // transparency
    [self setTransparency:[iTermProfilePreferences floatForKey:KEY_TRANSPARENCY inProfile:aDict]];
    [self setBlend:[iTermProfilePreferences floatForKey:KEY_BLEND inProfile:aDict]];

    // bold 
    [self setUseBoldFont:[iTermProfilePreferences boolForKey:KEY_USE_BOLD_FONT
                                                   inProfile:aDict]];
    [_textview setUseBrightBold:[iTermProfilePreferences boolForKey:KEY_USE_BRIGHT_BOLD
                                                          inProfile:aDict]];

    // Italic - this default has changed from NO to YES as of 1/30/15
    [self setUseItalicFont:[iTermProfilePreferences boolForKey:KEY_USE_ITALIC_FONT inProfile:aDict]];

    // Set up the rest of the preferences
    [_screen setAudibleBell:![iTermProfilePreferences boolForKey:KEY_SILENCE_BELL inProfile:aDict]];
    [_screen setShowBellIndicator:[iTermProfilePreferences boolForKey:KEY_VISUAL_BELL inProfile:aDict]];
    [_screen setFlashBell:[iTermProfilePreferences boolForKey:KEY_FLASHING_BELL inProfile:aDict]];
    [_screen setPostGrowlNotifications:[iTermProfilePreferences boolForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS inProfile:aDict]];
    [_textview setBlinkAllowed:[iTermProfilePreferences boolForKey:KEY_BLINK_ALLOWED inProfile:aDict]];
    [_screen setCursorBlinks:[iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:aDict]];
    [_textview setBlinkingCursor:[iTermProfilePreferences boolForKey:KEY_BLINKING_CURSOR inProfile:aDict]];
    [_textview setCursorType:[iTermProfilePreferences intForKey:KEY_CURSOR_TYPE inProfile:aDict]];

    PTYTab* currentTab = [[[self tab] parentWindow] currentTab];
    if (currentTab == nil || currentTab == [self tab]) {
        [[self tab] recheckBlur];
    }
    [_triggers release];
    _triggers = [[NSMutableArray alloc] init];
    for (NSDictionary *triggerDict in aDict[KEY_TRIGGERS]) {
        Trigger *trigger = [Trigger triggerFromDict:triggerDict];
        if (trigger) {
            [_triggers addObject:trigger];
        }
    }
    [_textview setSmartSelectionRules:aDict[KEY_SMART_SELECTION_RULES]];
    [_textview setSemanticHistoryPrefs:aDict[KEY_SEMANTIC_HISTORY]];
    [_textview setUseNonAsciiFont:[iTermProfilePreferences boolForKey:KEY_USE_NONASCII_FONT
                                                            inProfile:aDict]];
    [_textview setAntiAlias:[iTermProfilePreferences boolForKey:KEY_ASCII_ANTI_ALIASED
                                                      inProfile:aDict]
                   nonAscii:[iTermProfilePreferences boolForKey:KEY_NONASCII_ANTI_ALIASED
                                                      inProfile:aDict]];
    [self setEncoding:[iTermProfilePreferences intForKey:KEY_CHARACTER_ENCODING inProfile:aDict]];
    [self setTermVariable:[iTermProfilePreferences stringForKey:KEY_TERMINAL_TYPE inProfile:aDict]];
    [self setAntiIdleCode:[iTermProfilePreferences intForKey:KEY_IDLE_CODE inProfile:aDict]];
    [self setAntiIdle:[iTermProfilePreferences boolForKey:KEY_SEND_CODE_WHEN_IDLE inProfile:aDict]];
    [self setAutoClose:[iTermProfilePreferences boolForKey:KEY_CLOSE_SESSIONS_ON_END inProfile:aDict]];
    _screen.useHFSPlusMapping = [iTermProfilePreferences boolForKey:KEY_USE_HFS_PLUS_MAPPING
                                                          inProfile:aDict];
    [self setTreatAmbiguousWidthAsDoubleWidth:[iTermProfilePreferences boolForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH
                                                                        inProfile:aDict]];
    [self setXtermMouseReporting:[iTermProfilePreferences boolForKey:KEY_XTERM_MOUSE_REPORTING
                                                           inProfile:aDict]];
    [_terminal setDisableSmcupRmcup:[iTermProfilePreferences boolForKey:KEY_DISABLE_SMCUP_RMCUP
                                                              inProfile:aDict]];
    [_screen setAllowTitleReporting:[iTermProfilePreferences boolForKey:KEY_ALLOW_TITLE_REPORTING
                                                              inProfile:aDict]];
    [_terminal setAllowKeypadMode:[iTermProfilePreferences boolForKey:KEY_APPLICATION_KEYPAD_ALLOWED
                                                            inProfile:aDict]];
    [_screen setUnlimitedScrollback:[iTermProfilePreferences boolForKey:KEY_UNLIMITED_SCROLLBACK
                                                              inProfile:aDict]];
    [_screen setMaxScrollbackLines:[iTermProfilePreferences intForKey:KEY_SCROLLBACK_LINES
                                                            inProfile:aDict]];

    _screen.appendToScrollbackWithStatusBar = [iTermProfilePreferences boolForKey:KEY_SCROLLBACK_WITH_STATUS_BAR
                                                                        inProfile:aDict];
    self.badgeFormat = [iTermProfilePreferences stringForKey:KEY_BADGE_FORMAT inProfile:aDict];
    _textview.badgeLabel = [self badgeLabel];
    [self setFont:[ITAddressBookMgr fontWithDesc:aDict[KEY_NORMAL_FONT]]
        nonAsciiFont:[ITAddressBookMgr fontWithDesc:aDict[KEY_NON_ASCII_FONT]]
        horizontalSpacing:[iTermProfilePreferences floatForKey:KEY_HORIZONTAL_SPACING inProfile:aDict]
        verticalSpacing:[iTermProfilePreferences floatForKey:KEY_VERTICAL_SPACING inProfile:aDict]];
    [_screen setSaveToScrollbackInAlternateScreen:[iTermProfilePreferences boolForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN
                                                                            inProfile:aDict]];
    [[_tab realParentWindow] invalidateRestorableState];
}

- (NSString *)badgeLabel {
    return [_badgeFormat stringByReplacingVariableReferencesWithVariables:_variables];
}

- (BOOL)isAtShellPrompt {
    return _commandRange.start.x >= 0;
}

- (BOOL)isProcessing {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return (now - _lastOutput) < [iTermAdvancedSettingsModel idleTimeSeconds];
}

- (BOOL)isIdle {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return (now - _lastOutput) < ([iTermAdvancedSettingsModel idleTimeSeconds] + 1);
}

- (NSString*)formattedName:(NSString*)base
{
    NSString *prefix = _tmuxController ? [NSString stringWithFormat:@"↣ %@: ", [[self tab] tmuxWindowName]] : @"";

    BOOL baseIsBookmarkName = [base isEqualToString:_bookmarkName];
    if ([iTermPreferences boolForKey:kPreferenceKeyShowJobName] && _jobName) {
        if (baseIsBookmarkName && ![iTermPreferences boolForKey:kPreferenceKeyShowProfileName]) {
            return [NSString stringWithFormat:@"%@%@", prefix, [self jobName]];
        } else {
            return [NSString stringWithFormat:@"%@%@ (%@)", prefix, base, [self jobName]];
        }
    } else {
        if (baseIsBookmarkName && ![iTermPreferences boolForKey:kPreferenceKeyShowProfileName]) {
            return [NSString stringWithFormat:@"%@Shell", prefix];
        } else {
            return [NSString stringWithFormat:@"%@%@", prefix, base];
        }
    }
}

- (NSString*)defaultName
{
    return [self formattedName:_defaultName];
}

- (NSString*)joblessDefaultName
{
    return _defaultName;
}

- (void)setDefaultName:(NSString*)theName
{
    if ([_defaultName isEqualToString:theName]) {
        return;
    }

    if (_defaultName) {
        // clear the window title if it is not different
        if (_windowTitle == nil || [_name isEqualToString:_windowTitle]) {
            _windowTitle = nil;
        }
        [_defaultName release];
        _defaultName = nil;
    }
    if (!theName) {
        theName = NSLocalizedStringFromTableInBundle(@"Untitled",
                                                     @"iTerm",
                                                     [NSBundle bundleForClass:[self class]],
                                                     @"Profiles");
    }

    _defaultName = [theName copy];
}

- (void)setTab:(PTYTab*)tab
{
    if ([self isTmuxClient]) {
        [_tmuxController deregisterWindow:[_tab tmuxWindow]
                               windowPane:_tmuxPane
                                  session:self];
    }
    _tab = tab;
    if ([self isTmuxClient]) {
        [_tmuxController registerSession:self
                                withPane:_tmuxPane
                                inWindow:[_tab tmuxWindow]];
    }
    [_tmuxController fitLayoutToWindows];
}

- (NSString*)name
{
    return [self formattedName:_name];
}

- (NSString*)rawName
{
    return _name;
}

- (void)setName:(NSString*)theName
{
    [_view setTitle:theName];
    if (!_bookmarkName) {
        self.bookmarkName = theName;
    }
    if ([_name isEqualToString:theName]) {
        return;
    }

    if (_name) {
        // clear the window title if it is not different
        if ([_name isEqualToString:_windowTitle]) {
            _windowTitle = nil;
        }
        [_name release];
        _name = nil;
    }
    if (!theName) {
        theName = NSLocalizedStringFromTableInBundle(@"Untitled",
                                                     @"iTerm",
                                                     [NSBundle bundleForClass:[self class]],
                                                     @"Profiles");
    }

    _name = [theName retain];
    // sync the window title if it is not set to something else
    if (_windowTitle == nil) {
        [self setWindowTitle:theName];
    }

    [[self tab] nameOfSession:self didChangeTo:[self name]];
    [self setBell:NO];

    // get the session submenu to be rebuilt
    if ([[iTermController sharedInstance] currentTerminal] == [[self tab] parentWindow]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermNameOfSessionDidChange"
                                                            object:[[self tab] parentWindow]
                                                          userInfo:nil];
    }
    _variables[kVariableKeySessionName] = [self name];
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (NSString*)windowTitle
{
    if (!_windowTitle) {
        return nil;
    }
    return [self formattedName:_windowTitle];
}

- (void)setWindowTitle:(NSString*)theTitle
{
    if ([theTitle isEqualToString:_windowTitle]) {
        return;
    }

    [_windowTitle autorelease];
    _windowTitle = nil;

    if (theTitle != nil && [theTitle length] > 0) {
        _windowTitle = [theTitle copy];
    }

    if ([[[self tab] parentWindow] currentTab] == [self tab]) {
        [[[self tab] parentWindow] setWindowTitle];
    }
}

- (void)pushWindowTitle
{
    if (!_windowTitleStack) {
        // initialize lazily
        _windowTitleStack = [[NSMutableArray alloc] init];
    }
    NSString *title = _windowTitle;
    if (!title) {
        // if current title is nil, treat it as an empty string.
        title = @"";
    }
    // push it
    [_windowTitleStack addObject:title];
}

- (void)popWindowTitle
{
    // Ignore if title stack is nil or stack count == 0
    NSUInteger count = [_windowTitleStack count];
    if (count > 0) {
        // pop window title
        [self setWindowTitle:[_windowTitleStack objectAtIndex:count - 1]];
        [_windowTitleStack removeObjectAtIndex:count - 1];
    }
}

- (void)pushIconTitle
{
    if (!_iconTitleStack) {
        // initialize lazily
        _iconTitleStack = [[NSMutableArray alloc] init];
    }
    NSString *title = _name;
    if (!title) {
        // if current icon title is nil, treat it as an empty string.
        title = @"";
    }
    // push it
    [_iconTitleStack addObject:title];
}

- (void)popIconTitle
{
    // Ignore if icon title stack is nil or stack count == 0.
    NSUInteger count = [_iconTitleStack count];
    if (count > 0) {
        // pop icon title
        [self setName:[_iconTitleStack objectAtIndex:count - 1]];
        [_iconTitleStack removeObjectAtIndex:count - 1];
    }
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

- (void)setView:(SessionView*)newView
{
    // View holds a reference to us so we don't hold a reference to it.
    _view = newView;
    [[_view findViewController] setDelegate:self];
}

- (NSStringEncoding)encoding
{
    return [_terminal encoding];
}

- (void)setEncoding:(NSStringEncoding)encoding
{
    [_terminal setEncoding:encoding];
}


- (NSString *)tty {
    return [_shell tty];
}

- (void)setBackgroundImageTiled:(BOOL)set
{
    _backgroundImageTiled = set;
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

// Changes transparency

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
}

- (float)blend {
    return [_textview blend];
}

- (void)setBlend:(float)blendVal {
    [_textview setBlend:blendVal];
}

- (BOOL)antiIdle
{
    return _antiIdleTimer ? YES : NO;
}

- (void)setAntiIdle:(BOOL)set
{
    if (set == [self antiIdle]) {
        return;
    }

    if (set) {
        NSTimeInterval period = MIN(60, [iTermAdvancedSettingsModel antiIdleTimerPeriod]);

        _antiIdleTimer = [[NSTimer scheduledTimerWithTimeInterval:period
                                                           target:self
                                                         selector:@selector(doAntiIdle)
                                                         userInfo:nil
                repeats:YES] retain];
    } else {
        [_antiIdleTimer invalidate];
        [_antiIdleTimer release];
        _antiIdleTimer = nil;
    }
}

- (BOOL)useBoldFont
{
    return [_textview useBoldFont];
}

- (void)setUseBoldFont:(BOOL)boldFlag
{
    [_textview setUseBoldFont:boldFlag];
}

- (BOOL)useItalicFont
{
    return [_textview useItalicFont];
}

- (void)setUseItalicFont:(BOOL)italicFlag
{
    [_textview setUseItalicFont:italicFlag];
}

- (void)setTreatAmbiguousWidthAsDoubleWidth:(BOOL)set
{
    _treatAmbiguousWidthAsDoubleWidth = set;
    _tmuxController.ambiguousIsDoubleWidth = set;
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
}

- (void)clearScrollbackBuffer
{
    [_screen clearScrollbackBuffer];
}

- (BOOL)shouldSendEscPrefixForModifier:(unsigned int)modmask
{
    if ([self optionKey] == OPT_ESC) {
        if ((modmask == NSAlternateKeyMask) ||
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
    [[_tab realParentWindow] invalidateRestorableState];
    [[[self tab] realParentWindow] updateTabColors];
}

- (void)sendCommand:(NSString *)command
{
    NSData *data = nil;
    NSString *aString = nil;

    if (command != nil) {
        aString = [NSString stringWithFormat:@"%@\n", command];
        data = [aString dataUsingEncoding:[_terminal encoding]];
    }

    if (data != nil) {
        [self writeTask:data];
    }
}

- (NSDictionary *)arrangement {
    return [self arrangementWithContents:NO];
}

- (NSDictionary *)arrangementWithContents:(BOOL)includeContents {
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    result[SESSION_ARRANGEMENT_COLUMNS] = @(_screen.width);
    result[SESSION_ARRANGEMENT_ROWS] = @(_screen.height);
    result[SESSION_ARRANGEMENT_BOOKMARK] = _profile;
    result[SESSION_ARRANGEMENT_BOOKMARK_NAME] = _bookmarkName;

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

    if (_name) {
        result[SESSION_ARRANGEMENT_NAME] = _name;
    }
    if (_defaultName) {
        result[SESSION_ARRANGEMENT_DEFAULT_NAME] = _defaultName;
    }
    if (_windowTitle) {
        result[SESSION_ARRANGEMENT_WINDOW_TITLE] = _windowTitle;
    }
    if (includeContents) {
        NSDictionary *contentsDictionary = [_screen contentsDictionary];
        result[SESSION_ARRANGEMENT_CONTENTS] = contentsDictionary;
        int numberOfLinesDropped =
            [contentsDictionary[kScreenStateKey][kScreenStateNumberOfLinesDroppedKey] intValue];
        result[SESSION_ARRANGEMENT_VARIABLES] = _variables;
        VT100GridCoordRange range = _commandRange;
        range.start.y -= numberOfLinesDropped;
        range.end.y -= numberOfLinesDropped;
        result[SESSION_ARRANGEMENT_COMMAND_RANGE] =
            [NSDictionary dictionaryWithGridCoordRange:range];
        result[SESSION_ARRANGEMENT_ALERT_ON_NEXT_MARK] = @(_alertOnNextMark);
        result[SESSION_ARRANGEMENT_CURSOR_GUIDE] = @(_textview.highlightCursorLine);
        if (self.lastDirectory) {
            result[SESSION_ARRANGEMENT_LAST_DIRECTORY] = self.lastDirectory;
        }
        result[SESSION_ARRANGEMENT_SELECTION] =
            [self.textview.selection dictionaryValueWithYOffset:-numberOfLinesDropped];
    }
    result[SESSION_ARRANGEMENT_GUID] = _guid;
    if (_liveSession && includeContents && !_dvr) {
        result[SESSION_ARRANGEMENT_LIVE_SESSION] =
            [_liveSession arrangementWithContents:includeContents];
    }
    if (!self.isTmuxClient) {
        // These values are used for restoring sessions after a crash.
        if ([iTermAdvancedSettingsModel runJobsInServers] && !_shell.pidIsChild) {
            result[SESSION_ARRANGEMENT_SERVER_PID] = @(_shell.serverPid);
        }
    }
    if (self.tmuxMode == TMUX_GATEWAY && self.tmuxController.sessionName) {
        result[SESSION_ARRANGEMENT_IS_TMUX_GATEWAY] = @YES;
        result[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_ID] = @(self.tmuxController.sessionId);
        result[SESSION_ARRANGEMENT_TMUX_GATEWAY_SESSION_NAME] = self.tmuxController.sessionName;
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
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    [result setObject:[parseNode objectForKey:kLayoutDictWidthKey] forKey:SESSION_ARRANGEMENT_COLUMNS];
    [result setObject:[parseNode objectForKey:kLayoutDictHeightKey] forKey:SESSION_ARRANGEMENT_ROWS];
    [result setObject:bookmark forKey:SESSION_ARRANGEMENT_BOOKMARK];
    result[SESSION_ARRANGEMENT_BOOKMARK_NAME] = [bookmark objectForKey:KEY_NAME];
    [result setObject:@"" forKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY];
    [result setObject:[parseNode objectForKey:kLayoutDictWindowPaneKey] forKey:SESSION_ARRANGEMENT_TMUX_PANE];
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
    if (![(PTYScroller*)([_scrollview verticalScroller]) userScroll]) {
        [_textview scrollEnd];
    }
}

- (void)updateDisplay {
    _timerRunning = YES;
    BOOL anotherUpdateNeeded = [NSApp isActive];
    if (!anotherUpdateNeeded &&
        _updateDisplayUntil &&
        [NSDate timeIntervalSinceReferenceDate] < _updateDisplayUntil) {
        // We're still in the time window after the last output where updates are needed.
        anotherUpdateNeeded = YES;
    }

    // Set attributes of tab to indicate idle, processing, etc.
    if (![self isTmuxGateway]) {
        anotherUpdateNeeded |= [[self tab] updateLabelAttributes];
    }

    if ([[self tab] activeSession] == self) {
        // Update window info for the active tab.
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!_jobName ||
            now >= (_lastUpdate + 0.7)) {
            // It has been more than 700ms since the last time we were here or
            // the job doesn't have a name
            if ([[self tab] isForegroundTab] && [[[self tab] parentWindow] tempTitle]) {
                // Revert to the permanent tab title.
                [[[self tab] parentWindow] setWindowTitle];
                [[[self tab] parentWindow] resetTempTitle];
            } else {
                // Update the job name in the tab title.
                NSString* oldName = _jobName;
                _jobName = [[_shell currentJob:NO] copy];
                if (![oldName isEqualToString:_jobName]) {
                    [[self tab] nameOfSession:self didChangeTo:[self name]];
                    [[[self tab] parentWindow] setWindowTitle];
                }
                [oldName release];
            }
            _lastUpdate = now;
        } else if (now < _lastUpdate + 0.7) {
            // If it's been less than 700ms keep updating.
            anotherUpdateNeeded = YES;
        }
    }

    anotherUpdateNeeded |= [_textview refresh];
    anotherUpdateNeeded |= [[[self tab] parentWindow] tempTitle];
    BOOL animating = _textview.getAndResetDrawingAnimatedImageFlag;
    anotherUpdateNeeded |= animating;

    if (anotherUpdateNeeded) {
        if (animating) {
            // A cell of animated GIF has been drawn since the last call to updateDisplay.
            [self scheduleUpdateIn:kFastTimerIntervalSec];
        } else if ([[[self tab] parentWindow] currentTab] == [self tab]) {
            [self scheduleUpdateIn:[iTermAdvancedSettingsModel timeBetweenBlinks]];
        } else {
            [self scheduleUpdateIn:kBackgroundSessionIntervalSec];
        }
    } else {
        [_updateTimer release];
        _updateTimer = nil;
    }

    if (_tailFindTimer && [[[_view findViewController] view] isHidden]) {
        [self stopTailFind];
    }

    [self checkPartialLineTriggers];
    _timerRunning = NO;
}

- (void)refreshAndStartTimerIfNeeded
{
    if ([_textview refresh]) {
        [self scheduleUpdateIn:[iTermAdvancedSettingsModel timeBetweenBlinks]];
    }
}

- (void)scheduleUpdateIn:(NSTimeInterval)timeout {
    if (_exited) {
        return;
    }

    if (!_timerRunning && [_updateTimer isValid]) {
        if (_lastTimeout == kSlowTimerIntervalSec && timeout == kFastTimerIntervalSec) {
            // Don't go from slow to fast
            return;
        }
        if (_lastTimeout == timeout) {
            // No change? No point.
            return;
        }
        if (timeout > kSlowTimerIntervalSec && timeout > _lastTimeout) {
            // This is a longer timeout than the existing one, and is background/blink.
            return;
        }
    }

    [_updateTimer invalidate];
    [_updateTimer release];

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval timeSinceLastUpdate = now - _timeOfLastScheduling;
    _timeOfLastScheduling = now;
    _lastTimeout = timeout;

#if 0
    // TODO: Try this. It solves the bug where we don't redraw properly during live resize.
    // I'm worried about the possible side effects it might have since there's no way to 
    // know all the tracking event loops.
    _updateTimer = [[NSTimer timerWithTimeInterval:MAX(0, timeout - timeSinceLastUpdate)
                                            target:self
                                          selector:@selector(updateDisplay)
                                          userInfo:[NSNumber numberWithFloat:(float)timeout]
                                           repeats:NO] retain];
    [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
#else
    _updateTimer = [[NSTimer scheduledTimerWithTimeInterval:MAX(0, timeout - timeSinceLastUpdate)
                                                     target:self
                                                   selector:@selector(updateDisplay)
                                                   userInfo:[NSNumber numberWithFloat:(float)timeout]
                                                    repeats:NO] retain];
#endif
}

- (void)doAntiIdle {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now >= _lastInput + 60) {
        [_shell writeTask:[NSData dataWithBytes:&_antiIdleCode length:1]];
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

- (NSFont*)fontWithRelativeSize:(int)dir from:(NSFont*)font
{
    int newSize = [font pointSize] + dir;
    if (newSize < 2) {
        newSize = 2;
    }
    if (newSize > 200) {
        newSize = 200;
    }
    return [NSFont fontWithName:[font fontName] size:newSize];
}

- (void)setFont:(NSFont*)font
     nonAsciiFont:(NSFont*)nonAsciiFont
    horizontalSpacing:(float)horizontalSpacing
    verticalSpacing:(float)verticalSpacing
{
    DLog(@"setFont:%@ nonAsciiFont:%@", font, nonAsciiFont);
    NSWindow *window = [[[self tab] realParentWindow] window];
    DLog(@"Before:\n%@", [window.contentView iterm_recursiveDescription]);
    DLog(@"Window frame: %@", window);
    if ([_textview.font isEqualTo:font] &&
        [_textview.nonAsciiFontEvenIfNotUsed isEqualTo:nonAsciiFont] &&
        [_textview horizontalSpacing] == horizontalSpacing &&
        [_textview verticalSpacing] == verticalSpacing) {
        // There's an unfortunate problem that this is a band-aid over.
        // If you change some attribute of a profile that causes sessions to reload their profiles
        // with the kReloadAllProfiles notification, then each profile will call this in turn,
        // and it may be a no-op for all of them. If each calls -[PseudoTerminal fitWindowToTab:[self tab]]
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
    if (![[[self tab] parentWindow] anyFullScreen]) {
        if ([iTermPreferences boolForKey:kPreferenceKeyAdjustWindowForFontSizeChange]) {
            [[[self tab] parentWindow] fitWindowToTab:[self tab]];
        }
    }
    // If the window isn't able to adjust, or adjust enough, make the session
    // work with whatever size we ended up having.
    if ([self isTmuxClient]) {
        [_tmuxController windowDidResize:[[self tab] realParentWindow]];
    } else {
        [[self tab] fitSessionToCurrentViewSize:self];
    }
    DLog(@"After:\n%@", [window.contentView iterm_recursiveDescription]);
    DLog(@"Window frame: %@", window);
}

- (void)terminalFileShouldStop:(NSNotification *)notification
{
  if ([notification object] == _download) {
        [_screen.terminal stopReceivingFile];
        [_download endOfData];
        self.download = nil;
    }
}

- (void)profileSessionNameDidEndEditing:(NSNotification *)notification {
    NSString *theGuid = [notification object];
    if (_tmuxTitleOutOfSync &&
        [self isTmuxClient] &&
        [theGuid isEqualToString:_profile[KEY_GUID]]) {
        Profile *profile = [[ProfileModel sessionsInstance] bookmarkWithGuid:theGuid];
        [_tmuxController renameWindowWithId:self.tab.tmuxWindow
                                  inSession:nil
                                     toName:profile[KEY_NAME]];
        _tmuxTitleOutOfSync = NO;
    }
}

- (void)synchronizeTmuxFonts:(NSNotification *)notification
{
    if (!_exited && [self isTmuxClient]) {
        NSArray *fonts = [notification object];
        NSFont *font = [fonts objectAtIndex:0];
        NSFont *nonAsciiFont = [fonts objectAtIndex:1];
        NSNumber *hSpacing = [fonts objectAtIndex:2];
        NSNumber *vSpacing = [fonts objectAtIndex:3];
        [_textview setFont:font
              nonAsciiFont:nonAsciiFont
            horizontalSpacing:[hSpacing doubleValue]
            verticalSpacing:[vSpacing doubleValue]];
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
                                                                      @(_textview.verticalSpacing) ]];
        fontChangeNotificationInProgress = NO;
        [PTYTab setTmuxFont:_textview.font
               nonAsciiFont:_textview.nonAsciiFontEvenIfNotUsed
                   hSpacing:_textview.horizontalSpacing
                   vSpacing:_textview.verticalSpacing];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPTYSessionTmuxFontDidChange
                                                            object:nil];
    }
}

- (void)changeFontSizeDirection:(int)dir
{
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

        [self setSessionSpecificProfileValues:@{ KEY_NORMAL_FONT: [ITAddressBookMgr descFromFont:font],
                                                 KEY_NON_ASCII_FONT: [ITAddressBookMgr descFromFont:nonAsciiFont] }];
        // Set the font in the bookmark dictionary

        // Update the model's copy of the bookmark.
        [[ProfileModel sessionsInstance] setBookmark:[self profile] withGuid:guid];

        // Update an existing one-bookmark prefs dialog, if open.
        if ([[[PreferencePanel sessionsInstance] window] isVisible]) {
            [[PreferencePanel sessionsInstance] underlyingBookmarkDidChange];
        }
    }
}

- (void)setSessionSpecificProfileValues:(NSDictionary *)newValues
{
    if (!_isDivorced) {
        [self divorceAddressBookEntryFromPreferences];
    }
    NSMutableDictionary* temp = [NSMutableDictionary dictionaryWithDictionary:_profile];
    for (NSString *key in newValues) {
        NSObject *value = newValues[key];
        temp[key] = value;
    }
    if ([temp isEqualToDictionary:_profile]) {
        // This was a no-op, so there's no need to get a divorce. Happens most
        // commonly when setting tab color after a split.
        return;
    }
    [[ProfileModel sessionsInstance] setBookmark:temp withGuid:temp[KEY_GUID]];

    // Update this session's copy of the bookmark
    [self reloadProfile];
}

- (void)remarry
{
    _isDivorced = NO;
}

- (NSString*)divorceAddressBookEntryFromPreferences
{
    Profile* bookmark = [self profile];
    NSString* guid = [bookmark objectForKey:KEY_GUID];
    if (_isDivorced && [[ProfileModel sessionsInstance] bookmarkWithGuid:guid]) {
        // Once, I saw a case where an already-divorced bookmark's guid was missing from
        // sessionsInstance. I don't know why, but if that's the case, just create it there
        // again. :(
        return guid;
    }
    _isDivorced = YES;
    [[ProfileModel sessionsInstance] removeProfileWithGuid:guid];
    [[ProfileModel sessionsInstance] addBookmark:bookmark];

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
    VT100ScreenMark *mark = nil;
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
        [_textview highlightMarkOnLine:VT100GridRangeMax(range)];
    }
}

- (BOOL)hasSavedScrollPosition
{
    return [_screen lastMark] != nil;
}

- (void)useStringForFind:(NSString*)string
{
    [[_view findViewController] setFindString:string];
}

- (void)findWithSelection
{
    if ([_textview selectedText]) {
        [[_view findViewController] setFindString:[_textview selectedText]];
    }
}

- (void)showFindPanel
{
    [[_view findViewController] makeVisible];
}

- (void)searchNext
{
    [[_view findViewController] searchNext];
}

- (void)searchPrevious
{
    [[_view findViewController] searchPrevious];
}

- (void)resetFindCursor
{
    [_textview resetFindCursor];
}

- (BOOL)findInProgress
{
    return [_textview findInProgress];
}

- (BOOL)continueFind:(double *)progress
{
    return [_textview continueFind:progress];
}

- (BOOL)growSelectionLeft
{
    return [_textview growSelectionLeft];
}

- (void)growSelectionRight
{
    [_textview growSelectionRight];
}

- (NSString*)selectedText
{
    return [_textview selectedText];
}

- (BOOL)canSearch
{
    return _textview != nil && _tab && [_tab realParentWindow];
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
      ignoringCase:(BOOL)ignoreCase
             regex:(BOOL)regex
        withOffset:(int)offset
{
    [_textview findString:aString
         forwardDirection:direction
             ignoringCase:ignoreCase
                    regex:regex
               withOffset:offset];
}

- (NSString*)unpaddedSelectedText {
    return [_textview selectedText];
}

- (void)copySelection {
    return [_textview copySelectionAccordingToUserPreferences];
}

- (void)takeFocus {
    [[[[self tab] realParentWindow] window] makeFirstResponder:_textview];
}

- (void)findViewControllerMakeDocumentFirstResponder {
    [self takeFocus];
}

- (void)clearHighlights
{
    [_textview clearHighlights];
}

- (NSImage *)snapshot {
    [_textview refresh];
    return [_view snapshot];
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

- (void)enterPassword:(NSString *)password {
    NSData *backspace = [self backspaceData];
    if (backspace) {
        // Try to figure out if we're at a shell prompt. Send a space character and immediately
        // backspace over it. If no output is received within a specified timeout, then go ahead and
        // send the password. Otherwise, ask for confirmation.
        [self writeTask:[@" " dataUsingEncoding:self.encoding]];
        [self writeTask:backspace];
        _bytesReceivedSinceSendingEchoProbe = 0;
        [self performSelector:@selector(enterPasswordIfEchoProbeOk:)
                   withObject:password
                   afterDelay:[iTermAdvancedSettingsModel echoProbeDuration]];
    } else {
        // Rare case: we don't know how to send a backspace. Just enter the password.
        [self enterPasswordNoProbe:password];
    }
}

- (void)enterPasswordIfEchoProbeOk:(NSString *)password {
    if (_bytesReceivedSinceSendingEchoProbe == 0) {
        // It looks like we're at a password prompt. Send the password.
        [self enterPasswordNoProbe:password];
    } else {
        if ([iTermWarning showWarningWithTitle:@"Are you really at a password prompt? It looks "
                                               @"like what you're typing is echoed to the screen."
                                       actions:@[ @"Cancel", @"Enter Password" ]
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent] == kiTermWarningSelection1) {
            [self enterPasswordNoProbe:password];
        }
    }
}

- (void)enterPasswordNoProbe:(NSString *)password {
    [self writeTask:[password dataUsingEncoding:self.encoding]];
    [self writeTask:[@"\n" dataUsingEncoding:self.encoding]];
}

- (NSImage *)dragImage
{
    NSImage *image = [self snapshot];
    // Dial the alpha down to 50%
    NSImage *dragImage = [[[NSImage alloc] initWithSize:[image size]] autorelease];
    [dragImage lockFocus];
    [image drawAtPoint:NSZeroPoint
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
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

        // In case it was the find pasteboard that chagned
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

- (void)launchCoprocessWithCommand:(NSString *)command mute:(BOOL)mute
{
    Coprocess *coprocess = [Coprocess launchedCoprocessWithCommand:command];
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
            [self writeTask:[_terminal.output reportFocusGained:focused]];
        }
    }
}

- (BOOL)wantsContentChangedNotification
{
    // We want a content change notification if it's worth doing a tail find.
    // That means the find window is open, we're not already doing a tail find,
    // and a search was performed in the find window (vs select+cmd-e+cmd-f).
    return !_tailFindTimer &&
           ![[[_view findViewController] view] isHidden] &&
           [_textview findContext].substring != nil;
}

- (void)hideSession {
    [[MovePaneController sharedInstance] moveSessionToNewWindow:self
                                                        atPoint:[[_view window] pointToScreenCoords:NSMakePoint(0, 0)]];
    [[[_tab realParentWindow] window] miniaturize:self];
}

- (NSString *)preferredTmuxClientName {
    VT100RemoteHost *remoteHost = [self currentHost];
    if (remoteHost) {
        return [NSString stringWithFormat:@"%@@%@", remoteHost.username, remoteHost.hostname];
    } else {
        return _name;
    }
}

- (void)startTmuxMode
{
    if (self.tmuxMode != TMUX_NONE) {
        return;
    }
    self.tmuxMode = TMUX_GATEWAY;
    _tmuxGateway = [[TmuxGateway alloc] initWithDelegate:self];
    _tmuxController = [[TmuxController alloc] initWithGateway:_tmuxGateway
                                                   clientName:[self preferredTmuxClientName]];
    _tmuxController.ambiguousIsDoubleWidth = _treatAmbiguousWidthAsDoubleWidth;
    NSSize theSize;
    Profile *tmuxBookmark = [PTYTab tmuxBookmark];
    theSize.width = MAX(1, [[tmuxBookmark objectForKey:KEY_COLUMNS] intValue]);
    theSize.height = MAX(1, [[tmuxBookmark objectForKey:KEY_ROWS] intValue]);
    [_tmuxController validateOptions];

    [self printTmuxMessage:@"** tmux mode started **"];
    [_screen crlf];
    [self printTmuxMessage:@"Command Menu"];
    [self printTmuxMessage:@"----------------------------"];
    [self printTmuxMessage:@"esc    Detach cleanly."];
    [self printTmuxMessage:@"  X    Force-quit tmux mode."];
    [self printTmuxMessage:@"  L    Toggle logging."];
    [self printTmuxMessage:@"  C    Run tmux command."];

    if ([iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession]) {
        [self hideSession];
    }
}

- (BOOL)isTmuxClient
{
    return self.tmuxMode == TMUX_CLIENT;
}

- (BOOL)isTmuxGateway
{
    return self.tmuxMode == TMUX_GATEWAY;
}

- (void)tmuxDetach
{
    if (self.tmuxMode != TMUX_GATEWAY) {
        return;
    }
    [self printTmuxMessage:@"Detaching..."];
    [_tmuxGateway detach];
}

- (void)setTmuxPane:(int)windowPane {
    _tmuxPane = windowPane;
    self.tmuxMode = TMUX_CLIENT;
    [_shell registerAsCoprocessOnlyTask];
}

- (void)toggleTmuxZoom {
    [_tmuxController toggleZoomForPane:self.tmuxPane];
}

- (void)resizeFromArrangement:(NSDictionary *)arrangement
{
    [self setWidth:[[arrangement objectForKey:SESSION_ARRANGEMENT_COLUMNS] intValue]
            height:[[arrangement objectForKey:SESSION_ARRANGEMENT_ROWS] intValue]];
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

- (void)toggleShowTimestamps {
    [_textview toggleShowTimestamps];
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

- (void)showHideNotes {
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
}

- (void)highlightMarkOrNote:(id<IntervalTreeObject>)obj {
    if ([obj isKindOfClass:[iTermMark class]]) {
        [_textview highlightMarkOnLine:VT100GridRangeMax([_screen lineNumberRangeOfInterval:obj.entry.interval])];
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

- (VT100RemoteHost *)currentHost {
    return [_screen remoteHostOnLine:[_screen numberOfLines]];
}

#pragma mark tmux gateway delegate methods
// TODO (also, capture and throw away keyboard input)

- (void)tmuxUpdateLayoutForWindow:(int)windowId
                           layout:(NSString *)layout
{
    PTYTab *tab = [_tmuxController window:windowId];
    if (tab) {
        [_tmuxController setLayoutInTab:tab toLayout:layout];
    }
}

- (void)tmuxWindowAddedWithId:(int)windowId
{
    if (![_tmuxController window:windowId]) {
        [_tmuxController openWindowWithId:windowId
                              intentional:NO];
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

- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName
{
    PTYTab *tab = [_tmuxController window:windowId];
    if (tab) {
        [tab setTmuxWindowName:newName];
    }
    [_tmuxController windowWasRenamedWithId:windowId to:newName];
}

- (void)tmuxPrintLine:(NSString *)line
{
    [_screen appendStringAtCursor:line];
    [_screen crlf];
}

- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow {
    return self.tab.realParentWindow;
}

- (void)tmuxHostDisconnected
{
    [_tmuxController detach];

    // Autorelease the gateway because it called this function so we can't free
    // it immediately.
    [_tmuxGateway autorelease];
    _tmuxGateway = nil;
    [_tmuxController release];
    _tmuxController = nil;
    [_screen appendStringAtCursor:@"Detached"];
    [_screen crlf];
    // There's a not-so-bad race condition here. It's possible that tmux would exit and a new
    // session would start right away and we'd wack the wrong tmux parser. However, it would be
    // very unusual for that to happen so quickly.
    [_terminal.parser forceUnhookDCS];
    self.tmuxMode = TMUX_NONE;

    if ([iTermPreferences boolForKey:kPreferenceKeyAutoHideTmuxClientSession] &&
        [[[_tab realParentWindow] window] isMiniaturized]) {
        [[[_tab realParentWindow] window] deminiaturize:self];
    }
}

- (void)tmuxSetSecureLogging:(BOOL)secureLogging {
    _tmuxSecureLogging = secureLogging;
}

- (void)tmuxWriteData:(NSData *)data {
    if (_exited) {
        return;
    }
    if (_tmuxSecureLogging) {
        DLog(@"Write to tmux.");
    } else {
        DLog(@"Write to tmux: \"%@\"", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
    }
    if (_tmuxGateway.tmuxLogging) {
        [self printTmuxMessage:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];
    }
    [self writeTaskImpl:data canBroadcast:YES];
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

- (NSSize)tmuxBookmarkSize
{
        NSDictionary *dict = [PTYTab tmuxBookmark];
        return NSMakeSize([[dict objectForKey:KEY_COLUMNS] intValue],
                                          [[dict objectForKey:KEY_ROWS] intValue]);
}

- (int)tmuxNumHistoryLinesInBookmark
{
        NSDictionary *dict = [PTYTab tmuxBookmark];
    if ([[dict objectForKey:KEY_UNLIMITED_SCROLLBACK] boolValue]) {
                // 10M is close enough to infinity to be indistinguishable.
                return 10 * 1000 * 1000;
        } else {
                return [[dict objectForKey:KEY_SCROLLBACK_LINES] intValue];
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

// Handle bookmark- and global-scope keybindings. If there is no keybinding then
// pass the keystroke as input.
- (void)keyDown:(NSEvent *)event {
    unsigned char *send_str = NULL;
    unsigned char *dataPtr = NULL;
    int dataLength = 0;
    size_t send_strlen = 0;
    int send_pchr = -1;
    int keyBindingAction;
    NSString *keyBindingText;

    unsigned int modflag;
    NSString *keystr;
    NSString *unmodkeystr;
    unichar unicode, unmodunicode;

    modflag = [event modifierFlags];
    keystr  = [event characters];
    unmodkeystr = [event charactersIgnoringModifiers];
    if ([unmodkeystr length] == 0) {
        return;
    }
    unicode = [keystr length] > 0 ? [keystr characterAtIndex:0] : 0;
    unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    DLog(@"PTYSession keyDown modflag=%d keystr=%@ unmodkeystr=%@ unicode=%d unmodunicode=%d", (int)modflag, keystr, unmodkeystr, (int)unicode, (int)unmodunicode);
    _lastInput = [NSDate timeIntervalSinceReferenceDate];
    [self resumeOutputIfNeeded];
    if ([self textViewIsZoomedIn] && unicode == 27) {
        // Escape exits zoom (pops out one level, since you can zoom repeatedly)
        // The zoomOut: IBAction doesn't get performed by shortcut, I guess because Esc is not a
        // valid shortcut. So we do it here.
        [[[self tab] realParentWindow] replaceSyntheticActiveSessionWithLiveSessionIfNeeded];
    } else if ([[[self tab] realParentWindow] inInstantReplay]) {
        DLog(@"PTYSession keyDown in IR");

        // Special key handling in IR mode, and keys never get sent to the live
        // session, even though it might be displayed.
        if (unicode == 27) {
            // Escape exits IR
            [[[self tab] realParentWindow] closeInstantReplay:self];
            return;
        } else if (unmodunicode == NSLeftArrowFunctionKey) {
            // Left arrow moves to prev frame
            int n = 1;
            if (modflag & NSShiftKeyMask) {
                n = 15;
            }
            for (int i = 0; i < n; i++) {
                [[[self tab] realParentWindow] irPrev:self];
            }
        } else if (unmodunicode == NSRightArrowFunctionKey) {
            // Right arrow moves to next frame
            int n = 1;
            if (modflag & NSShiftKeyMask) {
                n = 15;
            }
            for (int i = 0; i < n; i++) {
                [[[self tab] realParentWindow] irNext:self];
            }
        } else {
            NSBeep();
        }
        return;
    }

    unsigned short keycode = [event keyCode];
    DLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%lu>",
         event, modflag, keycode, keystr, unmodkeystr, unicode, unicode,
         (modflag & NSNumericPadKeyMask));

    // Check if we have a custom key mapping for this event
    keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                  modifiers:modflag
                                                       text:&keyBindingText
                                                keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];

    if (keyBindingAction >= 0) {
        DLog(@"PTYSession keyDown action=%d", keyBindingAction);
        // A special action was bound to this key combination.
        NSString* temp;
        int profileAction = [iTermKeyBindingMgr localActionForKeyCode:unmodunicode
                                                            modifiers:modflag
                                                                 text:&temp
                                                          keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];
        if (profileAction == keyBindingAction &&  // Don't warn if it's a global mapping
            (keyBindingAction == KEY_ACTION_NEXT_SESSION ||
             keyBindingAction == KEY_ACTION_PREVIOUS_SESSION)) {
                // Warn users about outdated default key bindings.
                int tempMods = modflag & (NSAlternateKeyMask | NSControlKeyMask | NSShiftKeyMask | NSCommandKeyMask);
                int tempKeyCode = unmodunicode;
                if (tempMods == (NSCommandKeyMask | NSAlternateKeyMask) &&
                    (tempKeyCode == 0xf702 || tempKeyCode == 0xf703) &&
                    [[[self tab] sessions] count] > 1) {
                    if ([self _askAboutOutdatedKeyMappings]) {
                        int result = NSRunAlertPanel(@"Outdated Key Mapping Found",
                                                     @"It looks like you're trying to switch split panes but you have a key mapping from an old iTerm installation for ⌘⌥← or ⌘⌥→ that switches tabs instead. What would you like to do?",
                                                     @"Remove it",
                                                     @"Remind me later",
                                                     @"Keep it");
                        switch (result) {
                            case NSAlertDefaultReturn:
                                // Remove it
                                [self _removeOutdatedKeyMapping];
                                return;
                                break;
                            case NSAlertAlternateReturn:
                                // Remind me later
                                break;
                            case NSAlertOtherReturn:
                                // Keep it
                                [self _setKeepOutdatedKeyMapping];
                                break;
                            default:
                                break;
                        }
                    }
                }
            }

        BOOL isTmuxGateway = (!_exited && self.tmuxMode == TMUX_GATEWAY);

        switch (keyBindingAction) {
            case KEY_ACTION_MOVE_TAB_LEFT:
                [[[self tab] realParentWindow] moveTabLeft:nil];
                break;
            case KEY_ACTION_MOVE_TAB_RIGHT:
                [[[self tab] realParentWindow] moveTabRight:nil];
                break;
            case KEY_ACTION_NEXT_MRU_TAB:
                [[[[self tab] parentWindow] tabView] cycleKeyDownWithModifiers:[event modifierFlags]
                                                                      forwards:YES];
                break;
            case KEY_ACTION_PREVIOUS_MRU_TAB:
                [[[[self tab] parentWindow] tabView] cycleKeyDownWithModifiers:[event modifierFlags]
                                                                      forwards:NO];
                break;
            case KEY_ACTION_NEXT_PANE:
                [[self tab] nextSession];
                break;
            case KEY_ACTION_PREVIOUS_PANE:
                [[self tab] previousSession];
                break;
            case KEY_ACTION_NEXT_SESSION:
                [[[self tab] parentWindow] nextTab:nil];
                break;
            case KEY_ACTION_NEXT_WINDOW:
                [[iTermController sharedInstance] nextTerminal:nil];
                break;
            case KEY_ACTION_PREVIOUS_SESSION:
                [[[self tab] parentWindow] previousTab:nil];
                break;
            case KEY_ACTION_PREVIOUS_WINDOW:
                [[iTermController sharedInstance] previousTerminal:nil];
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
                [self writeTask:[@"\010" dataUsingEncoding:NSUTF8StringEncoding]];
                break;
            case KEY_ACTION_SEND_C_QM_BACKSPACE:
                if (_exited || isTmuxGateway) {
                    return;
                }
                [self writeTask:[@"\177" dataUsingEncoding:NSUTF8StringEncoding]]; // decimal 127
                break;
            case KEY_ACTION_IGNORE:
                break;
            case KEY_ACTION_IR_FORWARD:
                if (isTmuxGateway) {
                    return;
                }
                [[iTermController sharedInstance] irAdvance:1];
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
                [[[self tab] realParentWindow] newWindowWithBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_NEW_TAB_WITH_PROFILE:
                [[[self tab] realParentWindow] newTabWithBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_SPLIT_HORIZONTALLY_WITH_PROFILE:
                [[[self tab] realParentWindow] splitVertically:NO withBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_SPLIT_VERTICALLY_WITH_PROFILE:
                [[[self tab] realParentWindow] splitVertically:YES withBookmarkGuid:keyBindingText];
                break;
            case KEY_ACTION_SET_PROFILE: {
                Profile *newProfile = [[ProfileModel sharedInstance] bookmarkWithGuid:keyBindingText];
                if (newProfile) {
                    [self setProfile:newProfile preservingName:YES];
                }
                break;
            }
            case KEY_ACTION_LOAD_COLOR_PRESET: {
                ProfileModel *model = [ProfileModel sharedInstance];
                Profile *profile;
                if (_isDivorced) {
                    profile = [[ProfileModel sharedInstance] bookmarkWithGuid:_profile[KEY_ORIGINAL_GUID]];
                } else {
                    profile = self.profile;
                }
                BOOL ok =
                [ProfilesColorsPreferencesViewController loadColorPresetWithName:keyBindingText
                                                                       inProfile:profile
                                                                           model:model];
                if (!ok) {
                    NSLog(@"Color preset %@ not found", keyBindingText);
                    NSBeep();
                }
                break;
            }

            case KEY_ACTION_FIND_REGEX:
                [[_view findViewController] closeViewAndDoTemporarySearchForString:keyBindingText
                                                                      ignoringCase:NO
                                                                             regex:YES];
                break;

            case KEY_ACTION_PASTE_SPECIAL_FROM_SELECTION: {
                NSString *string = [self mostRecentlySelectedText];
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
                [iTermPreferences setBool:![iTermPreferences boolForKey:kPreferenceKeyHotkeyAutoHides]
                                   forKey:kPreferenceKeyHotkeyAutoHides];
                break;
            }

            default:
                NSLog(@"Unknown key action %d", keyBindingAction);
                break;
        }
    } else {
        // Key is not bound to an action.
        if (!_exited && self.tmuxMode == TMUX_GATEWAY) {
            [self handleKeypressInTmuxGateway:unicode];
            return;
        }
        DLog(@"PTYSession keyDown no keybinding action");
        if (_exited) {
            DebugLog(@"Terminal already dead");
            return;
        }

        BOOL rightAltPressed = (modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask;
        BOOL leftAltPressed = (modflag & NSAlternateKeyMask) == NSAlternateKeyMask && !rightAltPressed;

        // No special binding for this key combination.
        if (modflag & NSFunctionKeyMask) {
            DLog(@"PTYSession keyDown is a function key");
            // Handle all "special" keys (arrows, etc.)
            NSData *data = nil;

            switch (unicode) {
                case NSUpArrowFunctionKey:
                    data = [_terminal.output keyArrowUp:modflag];
                    break;
                case NSDownArrowFunctionKey:
                    data = [_terminal.output keyArrowDown:modflag];
                    break;
                case NSLeftArrowFunctionKey:
                    data = [_terminal.output keyArrowLeft:modflag];
                    break;
                case NSRightArrowFunctionKey:
                    data = [_terminal.output keyArrowRight:modflag];
                    break;
                case NSInsertFunctionKey:
                    data = [_terminal.output keyInsert];
                    break;
                case NSDeleteFunctionKey:
                    // This is forward delete, not backspace.
                    data = [_terminal.output keyDelete];
                    break;
                case NSHomeFunctionKey:
                    data = [_terminal.output keyHome:modflag];
                    break;
                case NSEndFunctionKey:
                    data = [_terminal.output keyEnd:modflag];
                    break;
                case NSPageUpFunctionKey:
                    data = [_terminal.output keyPageUp:modflag];
                    break;
                case NSPageDownFunctionKey:
                    data = [_terminal.output keyPageDown:modflag];
                    break;
                case NSClearLineFunctionKey:
                    data = [@"\e" dataUsingEncoding:NSUTF8StringEncoding];
                    break;
            }

            if (NSF1FunctionKey <= unicode && unicode <= NSF35FunctionKey) {
                data = [_terminal.output keyFunction:unicode - NSF1FunctionKey + 1];
            }

            if (data != nil) {
                send_str = (unsigned char *)[data bytes];
                send_strlen = [data length];
            } else if (keystr != nil) {
                NSData *keydat = ((modflag & NSControlKeyMask) && unicode > 0) ?
                [keystr dataUsingEncoding:NSUTF8StringEncoding] :
                [unmodkeystr dataUsingEncoding:NSUTF8StringEncoding];
                send_str = (unsigned char *)[keydat bytes];
                send_strlen = [keydat length];
            }
        } else if ((leftAltPressed && [self optionKey] != OPT_NORMAL) ||
                   (rightAltPressed && [self rightOptionKey] != OPT_NORMAL)) {
            DLog(@"PTYSession keyDown opt + key -> modkey");
            // A key was pressed while holding down option and the option key
            // is not behaving normally. Apply the modified behavior.
            int mode;  // The modified behavior based on which modifier is pressed.
            if (leftAltPressed) {
                mode = [self optionKey];
            } else {
                assert(rightAltPressed);
                mode = [self rightOptionKey];
            }

            NSData *keydat = ((modflag & NSControlKeyMask) && unicode > 0)?
            [keystr dataUsingEncoding:NSUTF8StringEncoding]:
            [unmodkeystr dataUsingEncoding:NSUTF8StringEncoding];
            if (keydat != nil) {
                send_str = (unsigned char *)[keydat bytes];
                send_strlen = [keydat length];
            }
            if (mode == OPT_ESC) {
                send_pchr = '\e';
            } else if (mode == OPT_META && send_str != NULL) {
                int i;
                for (i = 0; i < send_strlen; ++i) {
                    send_str[i] |= 0x80;
                }
            }
        } else {
            DLog(@"PTYSession keyDown regular path");
            // Regular path for inserting a character from a keypress.
            int max = [keystr length];
            NSData *data=nil;

            if (max != 1||[keystr characterAtIndex:0] > 0x7f) {
                DLog(@"PTYSession keyDown non-ascii");
                data = [keystr dataUsingEncoding:[_terminal encoding]];
            } else {
                DLog(@"PTYSession keyDown ascii");
                data = [keystr dataUsingEncoding:NSUTF8StringEncoding];
            }

            // Enter key is on numeric keypad, but not marked as such
            if (unicode == NSEnterCharacter && unmodunicode == NSEnterCharacter) {
                modflag |= NSNumericPadKeyMask;
                DLog(@"PTYSession keyDown enter key");
                keystr = @"\015";  // Enter key -> 0x0d
            }
            // Check if we are in keypad mode
            if (modflag & NSNumericPadKeyMask) {
                DLog(@"PTYSession keyDown numeric keyoad");
                data = [_terminal.output keypadData:unicode keystr:keystr];
            }

            int indMask = modflag & NSDeviceIndependentModifierFlagsMask;
            if ((indMask & NSCommandKeyMask) &&   // pressing cmd
                ([keystr isEqualToString:@"0"] ||  // pressed 0 key
                 ([keystr intValue] > 0 && [keystr intValue] <= 9) || // or any other digit key
                 [keystr isEqualToString:@"\r"])) {   // or enter
                    // Do not send anything for cmd+number because the user probably
                    // fat-fingered switching of tabs/windows.
                    // Do not send anything for cmd+[shift]+enter if it wasn't
                    // caught by the menu.
                    DLog(@"PTYSession keyDown cmd+0-9 or cmd+enter");
                    data = nil;
                }
            if (data != nil) {
                send_str = (unsigned char *)[data bytes];
                send_strlen = [data length];
                DLog(@"modflag = 0x%x; send_strlen = %zd; send_str[0] = '%c (0x%x)'",
                     modflag, send_strlen, send_str[0], send_str[0]);
            }
            
            if ((modflag & NSControlKeyMask) &&
                send_strlen == 1 &&
                send_str[0] == '|') {
                DLog(@"PTYSession keyDown c-|");
                // Control-| is sent as Control-backslash
                send_str = (unsigned char*)"\034";
                send_strlen = 1;
            } else if ((modflag & NSControlKeyMask) &&
                       (modflag & NSShiftKeyMask) &&
                       send_strlen == 1 &&
                       send_str[0] == '/') {
                DLog(@"PTYSession keyDown c-?");
                // Control-shift-/ is sent as Control-?
                send_str = (unsigned char*)"\177";
                send_strlen = 1;
            } else if ((modflag & NSControlKeyMask) &&
                       send_strlen == 1 &&
                       send_str[0] == '/') {
                DLog(@"PTYSession keyDown c-/");
                // Control-/ is sent as Control-/, but needs some help to do so.
                send_str = (unsigned char*)"\037"; // control-/
                send_strlen = 1;
            } else if ((modflag & NSShiftKeyMask) &&
                       send_strlen == 1 &&
                       send_str[0] == '\031') {
                DLog(@"PTYSession keyDown shift-tab -> esc[Z");
                // Shift-tab is sent as Esc-[Z (or "backtab")
                send_str = (unsigned char*)"\033[Z";
                send_strlen = 3;
            }
            
        }
        
        if (_exited == NO) {
            if (send_pchr >= 0) {
                // Send a prefix character (e.g., esc).
                char c = send_pchr;
                dataPtr = (unsigned char*)&c;
                dataLength = 1;
                [self writeTask:[NSData dataWithBytes:dataPtr length:dataLength]];
            }
            
            if (send_str != NULL) {
                dataPtr = send_str;
                dataLength = send_strlen;
                [self writeTask:[NSData dataWithBytes:dataPtr length:dataLength]];
            }
        }
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
    if ([[self tab] realParentWindow] &&
        [[[self tab] realParentWindow] respondsToSelector:@selector(menuForEvent:menu:)]) {
        [[[self tab] realParentWindow] menuForEvent:theEvent menu:theMenu];
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
        } else if (spacesPerTab == kNumberOfSpacesPerTabCancel) {
            return;
        }
    }

    DLog(@"Calling pasteString:flags: on helper...");
    [_pasteHelper pasteString:theString
                       slowly:!!(flags & kPTYSessionPasteSlowly)
             escapeShellChars:!!(flags & kPTYSessionPasteEscapingSpecialCharacters)
                     commands:NO
                 tabTransform:tabTransform
                 spacesPerTab:spacesPerTab];
}

// Pastes the current string in the clipboard. Uses the sender's tag to get flags.
- (void)paste:(id)sender {
    DLog(@"PTYSession paste:");
    [self pasteString:[PTYSession pasteboardString] flags:[sender tag]];
}

// Show advanced paste window.
- (IBAction)pasteOptions:(id)sender {
    [_pasteHelper showPasteOptionsInWindow:self.tab.realParentWindow.window
                         bracketingEnabled:_terminal.bracketedPasteMode];
}

- (void)textViewFontDidChange
{
    if ([self isTmuxClient]) {
        [self notifyTmuxFontChange];
    }
    [_view updateScrollViewFrame];
}

- (void)textViewSizeDidChange
{
    [_view updateScrollViewFrame];
}

- (BOOL)textViewHasBackgroundImage {
    return _backgroundImage != nil;
}

- (NSImage *)patternedImage {
    // If there is a tiled background image, tesselate _backgroundImage onto
    // _patternedImage, which will be the source for future background image
    // drawing operations.
    if (!_patternedImage || !NSEqualSizes(_patternedImage.size, _view.contentRect.size)) {
        [_patternedImage release];
        _patternedImage = [[NSImage alloc] initWithSize:_view.contentRect.size];
        [_patternedImage lockFocus];
        NSColor *pattern = [NSColor colorWithPatternImage:_backgroundImage];
        [pattern drawSwatchInRect:NSMakeRect(0,
                                             0,
                                             _patternedImage.size.width,
                                             _patternedImage.size.height)];
        [_patternedImage unlockFocus];
    }
    return _patternedImage;
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
                                 viewRect:(NSRect)rect
                   blendDefaultBackground:(BOOL)blendDefaultBackground {
    const float alpha = _textview.useTransparency ? (1.0 - _textview.transparency) : 1.0;
    if (_backgroundImage) {
        NSRect localRect = [_view convertRect:rect fromView:view];
        NSImage *image;
        if (_backgroundImageTiled) {
            image = [self patternedImage];
        } else {
            image = _backgroundImage;
        }
        double dx = image.size.width / _view.frame.size.width;
        double dy = image.size.height / _view.frame.size.height;

        NSRect sourceRect = NSMakeRect(localRect.origin.x * dx,
                                       localRect.origin.y * dy,
                                       localRect.size.width * dx,
                                       localRect.size.height * dy);
        [image drawInRect:rect
                 fromRect:sourceRect
                operation:NSCompositeCopy
                 fraction:alpha
           respectFlipped:YES
                    hints:nil];

        if (blendDefaultBackground) {
            // Blend default background color over background image.
            [[[self processedBackgroundColor] colorWithAlphaComponent:1 - _textview.blend] set];
            NSRectFillUsingOperation(rect, NSCompositeSourceOver);
        }
    } else if (blendDefaultBackground) {
        // No image, so just draw background color.
        [[[self processedBackgroundColor] colorWithAlphaComponent:alpha] set];
        NSRectFillUsingOperation(rect, NSCompositeCopy);
    }
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
        [self.tab.realParentWindow invalidateRestorableState];
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
    return [self textViewIsActiveSession] && [[[self tab] realParentWindow] autoCommandHistoryIsOpenForSession:self];
}

- (void)textViewWillNeedUpdateForBlink
{
    [self scheduleUpdateIn:[iTermAdvancedSettingsModel timeBetweenBlinks]];
}

- (void)textViewSplitVertically:(BOOL)vertically withProfileGuid:(NSString *)guid
{
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    if (guid) {
        profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
    }
    [[[self tab] realParentWindow] splitVertically:vertically
                                      withBookmark:profile
                                     targetSession:self];
}

- (void)textViewSelectNextTab
{
    [[[self tab] realParentWindow] nextTab:nil];
}

- (void)textViewSelectPreviousTab
{
    [[[self tab] realParentWindow] previousTab:nil];
}

- (void)textViewSelectNextWindow
{
    [[iTermController sharedInstance] nextTerminal:nil];
}

- (void)textViewSelectPreviousWindow
{
    [[iTermController sharedInstance] previousTerminal:nil];
}

- (void)textViewSelectNextPane
{
    [[self tab] nextSession];
}

- (void)textViewSelectPreviousPane
{
    [[self tab] previousSession];
}

- (void)textViewEditSession {
    [[[self tab] realParentWindow] editSession:self makeKey:YES];
}

- (void)textViewToggleBroadcastingInput
{
    [[[self tab] realParentWindow] toggleBroadcastingInputToSession:self];
}

- (void)textViewCloseWithConfirmation {
    [[[self tab] realParentWindow] closeSessionWithConfirmation:self];
}

- (void)textViewRestartWithConfirmation {
    [[[self tab] realParentWindow] restartSessionWithConfirmation:self];
}

- (NSString *)mostRecentlySelectedText {
    PTYSession *session = [[iTermController sharedInstance] sessionWithMostRecentSelection];
    if (session) {
        PTYTextView *textview = [session textview];
        if ([textview isAnyCharSelected]) {
            return [textview selectedText];
        }
    }
    return nil;
}

- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags {
    NSString *string = [self mostRecentlySelectedText];
    if (string) {
        [self pasteString:string flags:flags];
    }
}

- (void)textViewPasteFileWithBase64Encoding {
    NSData *data = [[self class] pasteboardFile];
    if (data) {
        [_pasteHelper pasteString:[data stringWithBase64EncodingWithLineBreak:@"\r"]
                           slowly:NO
                 escapeShellChars:NO
                         commands:NO
                     tabTransform:kTabTransformNone
                     spacesPerTab:0];
    }
}

- (BOOL)textViewCanPasteFile
{
    return [[self class] pasteboardFile] != nil;
}

- (BOOL)textViewWindowUsesTransparency {
    return [[[self tab] realParentWindow] useTransparency];
}

- (BOOL)textViewAmbiguousWidthCharsAreDoubleWidth
{
    return [self treatAmbiguousWidthAsDoubleWidth];
}

- (void)textViewCreateWindowWithProfileGuid:(NSString *)guid
{
    [[[self tab] realParentWindow] newWindowWithBookmarkGuid:guid];
}

- (void)textViewCreateTabWithProfileGuid:(NSString *)guid
{
    [[[self tab] realParentWindow] newTabWithBookmarkGuid:guid];
}

// Called when a key is pressed.
- (BOOL)textViewDelegateHandlesAllKeystrokes
{
    [self resumeOutputIfNeeded];
    return [[[self tab] realParentWindow] inInstantReplay];
}

- (BOOL)textViewInSameTabAsTextView:(PTYTextView *)other {
    PTYTab *myTab = [self tab];
    for (PTYSession *session in [myTab sessions]) {
        if ([session textview] == other) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)textViewIsActiveSession
{
    return [[self tab] activeSession] == self;
}

- (BOOL)textViewSessionIsBroadcastingInput
{
    return [[[self tab] realParentWindow] broadcastInputToSession:self];
}

- (BOOL)textViewIsMaximized {
    return [[self tab] hasMaximizedPane];
}

- (BOOL)textViewTabHasMaximizedPanel
{
    return [[self tab] hasMaximizedPane];
}

- (void)textViewDidBecomeFirstResponder
{
    [[self tab] setActiveSession:self];
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
        case NSLeftMouseDown:
        case NSRightMouseDown:
        case NSOtherMouseDown:
            switch ([_terminal mouseMode]) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    _reportingMouseDown = YES;
                    _lastReportedCoord = coord;
                    [self writeTask:[_terminal.output mousePress:button
                                                   withModifiers:modifiers
                                                              at:coord]];
                    return YES;

                case MOUSE_REPORTING_NONE:
                case MOUSE_REPORTING_HILITE:
                    break;
            }
            break;

        case NSLeftMouseUp:
        case NSRightMouseUp:
        case NSOtherMouseUp:
            if (_reportingMouseDown) {
                _reportingMouseDown = NO;
                _lastReportedCoord = VT100GridCoordMake(-1, -1);

                switch ([_terminal mouseMode]) {
                    case MOUSE_REPORTING_NORMAL:
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        _lastReportedCoord = coord;
                        [self writeTask:[_terminal.output mouseRelease:button
                                                         withModifiers:modifiers
                                                                    at:coord]];
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HILITE:
                        break;
                }
            }
            break;


        case NSMouseMoved:
            if ([_terminal mouseMode] == MOUSE_REPORTING_ALL_MOTION &&
                !VT100GridCoordEquals(coord, _lastReportedCoord)) {
                _lastReportedCoord = coord;
                [self writeTask:[_terminal.output mouseMotion:MOUSE_BUTTON_NONE
                                                withModifiers:modifiers
                                                           at:coord]];
                return YES;
            }
            break;

        case NSLeftMouseDragged:
        case NSRightMouseDragged:
        case NSOtherMouseDragged:
            if (_reportingMouseDown &&
                !VT100GridCoordEquals(coord, _lastReportedCoord)) {
                _lastReportedCoord = coord;

                switch ([_terminal mouseMode]) {
                    case MOUSE_REPORTING_BUTTON_MOTION:
                    case MOUSE_REPORTING_ALL_MOTION:
                        [self writeTask:[_terminal.output mouseMotion:button
                                                        withModifiers:modifiers
                                                                   at:coord]];
                        // Fall through
                    case MOUSE_REPORTING_NORMAL:
                        // Don't do selection when mouse reporting during a drag, even if the drag
                        // is not reported (the clicks are).
                        return YES;

                    case MOUSE_REPORTING_NONE:
                    case MOUSE_REPORTING_HILITE:
                        break;
                }
            }
            break;

        case NSScrollWheel:
            switch ([_terminal mouseMode]) {
                case MOUSE_REPORTING_NORMAL:
                case MOUSE_REPORTING_BUTTON_MOTION:
                case MOUSE_REPORTING_ALL_MOTION:
                    if (deltaY != 0) {
                        [self writeTask:[_terminal.output mousePress:button
                                                       withModifiers:modifiers
                                                                  at:coord]];
                        return YES;
                    }
                    break;

                case MOUSE_REPORTING_NONE:
                case MOUSE_REPORTING_HILITE:
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
    if (![[CommandHistory sharedInstance] commandHistoryHasEverBeenUsed]) {
        DLog(@"Command history has never been used.");
        [CommandHistory showInformationalMessage];
        return VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
    } else {
        DLog(@"Returning cached range.");
        return _screen.lastCommandOutputRange;
    }
}

- (BOOL)textViewCanSelectOutputOfLastCommand {
    // Return YES if command history has never been used so we can show the informational message.
    return (![[CommandHistory sharedInstance] commandHistoryHasEverBeenUsed] ||
            _screen.lastCommandOutputRange.start.x >= 0);

}

- (BOOL)textViewUseHFSPlusMapping {
    return _screen.useHFSPlusMapping;
}

- (NSColor *)textViewCursorGuideColor {
    return _cursorGuideColor;
}

- (NSColor *)textViewBadgeColor {
    return [[iTermProfilePreferences objectForKey:KEY_BADGE_COLOR inProfile:_profile] colorValue];
}

- (NSDictionary *)textViewVariables {
    return _variables;
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

- (void)sendEscapeSequence:(NSString *)text
{
    if (_exited) {
        return;
    }
    if ([text length] > 0) {
        NSString *aString = [NSString stringWithFormat:@"\e%@", text];
        [self writeTask:[aString dataUsingEncoding:NSUTF8StringEncoding]];
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

- (void)sendHexCode:(NSString *)codes
{
    if (_exited) {
        return;
    }
    if ([codes length]) {
        [self writeTask:[self dataForHexCodes:codes]];
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
        [self writeTask:[temp dataUsingEncoding:NSUTF8StringEncoding]];
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

- (NSString*)_getLocale
{
    NSString* theLocale = nil;
    NSString* languageCode = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
    NSString* countryCode = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    DLog(@"getLocale: languageCode=%@, countryCode=%@", languageCode, countryCode);
    if (languageCode && countryCode) {
        theLocale = [NSString stringWithFormat:@"%@_%@", languageCode, countryCode];
        DLog(@"Return combined language/country locale %@", theLocale);
    } else {
        NSString *localeId = [[NSLocale currentLocale] localeIdentifier];
        DLog(@"Return local identifier of %@", localeId);
        return localeId;
    }
    return theLocale;
}

- (NSString*)_lang
{
    NSString* theLocale = [self _getLocale];
    NSString* encoding = [self encodingName];
    DLog(@"locale=%@, encoding=%@", theLocale, encoding);
    if (encoding && theLocale) {
        NSString* result = [NSString stringWithFormat:@"%@.%@", theLocale, encoding];
        DLog(@"Tentative locale is %@", result);
        if ([self _localeIsSupported:result]) {
            DLog(@"Locale is supported");
            return result;
        } else {
            DLog(@"Locale is NOT supported");
            return nil;
        }
    } else {
        DLog(@"No locale or encoding, returning nil language");
        return nil;
    }
}

- (void)setDvrFrame
{
    screen_char_t* s = (screen_char_t*)[_dvrDecoder decodedFrame];
    int len = [_dvrDecoder length];
    DVRFrameInfo info = [_dvrDecoder info];
    if (info.width != [_screen width] || info.height != [_screen height]) {
        if (![_liveSession isTmuxClient]) {
            [[[self tab] realParentWindow] sessionInitiatedResize:self
                                                            width:info.width
                                                           height:info.height];
        }
    }
    [_screen setFromFrame:s len:len info:info];
    [[[self tab] realParentWindow] resetTempTitle];
    [[[self tab] realParentWindow] setWindowTitle];
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

- (void)beginTailFind
{
    FindContext *findContext = [_textview findContext];
    if (!findContext.substring) {
        return;
    }
    [_screen setFindString:findContext.substring
          forwardDirection:YES
              ignoringCase:!!(findContext.options & FindOptCaseInsensitive)
                     regex:!!(findContext.options & FindOptRegex)
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
        [[_tab realParentWindow] currentTab] == _tab) {
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

- (void)screenNeedsRedraw {
    [self refreshAndStartTimerIfNeeded];
    [_textview updateNoteViewFrames];
    [_textview setNeedsDisplay:YES];
}

- (void)screenUpdateDisplay:(BOOL)redraw {
    [self updateDisplay];
    if (redraw) {
        [_textview setNeedsDisplay:YES];
    }
}

- (void)screenSizeDidChange {
    [self updateScroll];
    [_textview updateNoteViewFrames];
    _variables[kVariableKeySessionColumns] = [NSString stringWithFormat:@"%d", _screen.width];
    _variables[kVariableKeySessionRows] = [NSString stringWithFormat:@"%d", _screen.height];
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (void)screenTriggerableChangeDidOccur {
    [self clearTriggerLine];
}

- (void)screenDidReset {
    [self loadInitialColorTable];
    _cursorGuideSettingHasChanged = NO;
    _textview.highlightCursorLine = NO;
    [_textview setNeedsDisplay:YES];
    _screen.trackCursorLineMovement = NO;
}

- (BOOL)screenShouldSyncTitle {
    if (![iTermPreferences boolForKey:kPreferenceKeyShowProfileName]) {
        return NO;
    }
    return [[[self profile] objectForKey:KEY_SYNC_TITLE] boolValue];
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
    [[self textview] setCursorType:type];
}

- (void)screenSetCursorBlinking:(BOOL)blink {
    [[self textview] setBlinkingCursor:blink];
}

- (BOOL)screenShouldInitiateWindowResize {
    return ![[[self profile] objectForKey:KEY_DISABLE_WINDOW_RESIZING] boolValue];
}

- (void)screenResizeToWidth:(int)width height:(int)height {
    [[self tab] sessionInitiatedResize:self width:width height:height];
}

- (void)screenResizeToPixelWidth:(int)width height:(int)height {
    [[[self tab] realParentWindow] setFrameSize:NSMakeSize(width, height)];
}

- (BOOL)screenShouldBeginPrinting {
    return ![[[self profile] objectForKey:KEY_DISABLE_PRINTING] boolValue];
}

- (NSString *)screenNameExcludingJob {
    return [self joblessDefaultName];
}

- (void)screenSetWindowTitle:(NSString *)title {
    [self setWindowTitle:title];
}

- (NSString *)screenWindowTitle {
    return [self windowTitle];
}

- (NSString *)screenDefaultName {
    return _defaultName;
}

- (void)screenSetName:(NSString *)theName {
    [self setName:theName];
}

- (BOOL)screenWindowIsFullscreen {
    return [[[self tab] parentWindow] anyFullScreen];
}

- (void)screenMoveWindowTopLeftPointTo:(NSPoint)point {
    NSRect screenFrame = [self screenWindowScreenFrame];
    point.x += screenFrame.origin.x;
    point.y = screenFrame.origin.y + screenFrame.size.height - point.y;
    [[[self tab] parentWindow] windowSetFrameTopLeftPoint:point];
}

- (NSRect)screenWindowScreenFrame {
    return [[[[self tab] parentWindow] windowScreen] visibleFrame];
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
        [[[self tab] parentWindow] windowPerformMiniaturize:nil];
    } else {
        [[[self tab] parentWindow] windowDeminiaturize:nil];
    }
}

// If flag is set, bring to front; if not, move to back.
- (void)screenRaise:(BOOL)flag {
    if (flag) {
        [[[self tab] parentWindow] windowOrderFront:nil];
    } else {
        [[[self tab] parentWindow] windowOrderBack:nil];
    }
}

- (BOOL)screenWindowIsMiniaturized {
    return [[[self tab] parentWindow] windowIsMiniaturized];
}

- (void)screenWriteDataToTask:(NSData *)data {
    [self writeTaskNoBroadcast:data];
}

- (NSRect)screenWindowFrame {
    return [[[self tab] parentWindow] windowFrame];
}

- (NSSize)screenSize {
    return [[[[[self tab] parentWindow] currentSession] scrollview] documentVisibleRect].size;
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
    return [[self tab] realObjectCount];
}

- (int)screenWindowIndex {
    return [[iTermController sharedInstance] indexOfTerminal:(PseudoTerminal *)[[self tab] realParentWindow]];
}

- (int)screenTabIndex {
    return [[self tab] number];
}

- (int)screenViewIndex {
    return [[self view] viewId];
}

- (void)screenStartTmuxMode {
    [self startTmuxMode];
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

- (void)screenClearHighlights {
    [_textview clearHighlights];
}

- (void)screenMouseModeDidChange {
    [_textview updateCursor:nil];
    [_textview updateTrackingAreas];
}

- (void)screenFlashImage:(NSString *)identifier {
    [_textview beginFlash:identifier];
}

- (void)screenIncrementBadge {
    [[_tab realParentWindow] incrementBadge];
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
    NSWindowController<iTermWindowController> *terminal = [[self tab] realParentWindow];
    iTermController *controller = [iTermController sharedInstance];
    if ([terminal isHotKeyWindow]) {
        [[HotkeyWindowController sharedInstance] showHotKeyWindow];
    } else {
        [controller setCurrentTerminal:(PseudoTerminal *)terminal];
        [[terminal window] makeKeyAndOrderFront:self];
        [[terminal tabView] selectTabViewItemWithIdentifier:[self tab]];
    }
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];

    [[self tab] setActiveSession:self];
}

- (id)markAddedAtLine:(int)line ofClass:(Class)markClass {
    [_textview refresh];  // In case text was appended
    if (_lastMark.command && !_lastMark.endDate) {
        _lastMark.endDate = [NSDate date];
    }
    [_lastMark release];
    _lastMark = [[_screen addMarkStartingAtAbsoluteLine:[_screen totalScrollbackOverflow] + line
                                                oneLine:YES
                                                ofClass:markClass] retain];
    self.currentMarkOrNotePosition = _lastMark.entry.interval;
    if (self.alertOnNextMark) {
        NSString *action = [(iTermApplicationDelegate *)[[iTermApplication sharedApplication] delegate] markAlertAction];
        if ([action isEqualToString:kMarkAlertActionPostNotification]) {
            [[iTermGrowlDelegate sharedInstance] growlNotify:@"Mark Set"
                                             withDescription:[NSString stringWithFormat:@"Session %@ #%d had a mark set.",
                                                              [self name],
                                                              [[self tab] realObjectCount]]
                                             andNotification:@"Mark Set"
                                                 windowIndex:[self screenWindowIndex]
                                                    tabIndex:[self screenTabIndex]
                                                   viewIndex:[self screenViewIndex]
                                                      sticky:YES];
        } else {
            if (NSRunAlertPanel(@"Alert",
                                @"Mark set in session “%@.”",
                                @"Reveal",
                                @"OK",
                                nil,
                                [self name]) == NSAlertDefaultReturn) {
                [self reveal];
            }
        }
        self.alertOnNextMark = NO;
    }
    return _lastMark;
}

- (void)screenPromptDidStartAtLine:(int)line {
    _lastPromptLine = (long long)line + [_screen totalScrollbackOverflow];
    DLog(@"FinalTerm: prompt started on line %d. Add a mark there. Save it as lastPromptLine.", line);
    [[self screenAddMarkOnLine:line] setIsPrompt:YES];
    [_pasteHelper unblock];
}

- (VT100ScreenMark *)screenAddMarkOnLine:(int)line {
    return (VT100ScreenMark *)[self markAddedAtLine:line ofClass:[VT100ScreenMark class]];
}

// Save the current scroll position
- (void)screenSaveScrollPosition
{
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

- (void)setProfile:(NSDictionary *)newProfile preservingName:(BOOL)preserveName {
    BOOL defaultNameMatchesProfileName = [_defaultName isEqualToString:_profile[KEY_NAME]];
    BOOL nameMatchesProfileName = [_name isEqualToString:_profile[KEY_NAME]];
    NSString *theName = [[self profile] objectForKey:KEY_NAME];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:newProfile];
    if (preserveName) {
        [dict setObject:theName forKey:KEY_NAME];
    }
    [self setProfile:dict];
    [self setPreferencesFromAddressBookEntry:dict];
    [_originalProfile autorelease];
    _originalProfile = [newProfile copy];
    [self remarry];
    if (!preserveName && defaultNameMatchesProfileName) {
        [self setDefaultName:newProfile[KEY_NAME]];
    }
    if (!preserveName && nameMatchesProfileName) {
        [self setName:newProfile[KEY_NAME]];
    }
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
        NSLog(@"Clipboard access denied for CopyToClipboard");
    }
}

- (void)screenDidAddNote:(PTYNoteViewController *)note {
    [_textview addViewForNote:note];
    [_textview setNeedsDisplay:YES];
}

- (void)screenDidEndEditingNote {
    [_textview.window makeFirstResponder:_textview];
}

// Stop pasting (despited the name)
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
    self.download = [[[TerminalFile alloc] initWithName:filename size:size] autorelease];
    [self.download download];
}

- (void)screenDidFinishReceivingFile {
    [self.download endOfData];
    self.download = nil;
}

- (void)screenDidReceiveBase64FileData:(NSString *)data {
    [self.download appendData:data];
}

- (void)screenFileReceiptEndedUnexpectedly {
    [self.download stop];
    [self.download endOfData];
    self.download = nil;
}

- (void)setAlertOnNextMark:(BOOL)alertOnNextMark {
    _alertOnNextMark = alertOnNextMark;
    [_textview setNeedsDisplay:YES];
}

- (void)screenRequestAttention:(BOOL)request isCritical:(BOOL)isCritical {
    if (request) {
        _requestAttentionId =
            [NSApp requestUserAttention:isCritical ? NSCriticalRequest : NSInformationalRequest];
    } else {
        [NSApp cancelUserAttentionRequest:_requestAttentionId];
    }
}

- (void)screenSetBackgroundImageFile:(NSString *)filename {
    filename = [filename stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
    if (!filename || ![[NSFileManager defaultManager] fileExistsAtPath:filename]) {
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

- (void)screenSetBadgeFormat:(NSString *)theFormat {
    theFormat = [theFormat stringByBase64DecodingStringWithEncoding:self.encoding];
    [self setSessionSpecificProfileValues:@{ KEY_BADGE_FORMAT: theFormat }];
    _textview.badgeLabel = [self badgeLabel];
}

- (void)screenSetUserVar:(NSString *)kvpString {
    NSArray *kvp = [kvpString keyValuePair];
    if (kvp) {
        NSString *key = [NSString stringWithFormat:@"user.%@", kvp[0]];
        if (![kvp[1] length]) {
            [_variables removeObjectForKey:key];
        } else {
            _variables[key] = [kvp[1] stringByBase64DecodingStringWithEncoding:NSUTF8StringEncoding];
        }
    }
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (iTermColorMap *)screenColorMap {
    return _colorMap;
}

- (void)screenSetColor:(NSColor *)color forKey:(int)key {
    NSString *profileKey = [_colorMap profileKeyForColorMapKey:key];
    if (profileKey) {
        [self setSessionSpecificProfileValues:@{ profileKey: [color dictionaryValue] }];
    } else {
        [_colorMap setColor:color forKey:key];
    }
}

- (void)screenSetCurrentTabColor:(NSColor *)color {
    [self setTabColor:color];
    id<WindowControllerInterface> term = [_tab parentWindow];
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
    [self setTabColor:[NSColor colorWithCalibratedRed:color
                                                green:[curColor greenComponent]
                                                 blue:[curColor blueComponent]
                                                alpha:1]];
    [[_tab parentWindow] updateTabColors];
}

- (void)screenSetTabColorGreenComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor];
    [self setTabColor:[NSColor colorWithCalibratedRed:[curColor redComponent]
                                                green:color
                                                 blue:[curColor blueComponent]
                                                alpha:1]];
    [[_tab parentWindow] updateTabColors];
}

- (void)screenSetTabColorBlueComponentTo:(CGFloat)color {
    NSColor *curColor = [self tabColor];
    [self setTabColor:[NSColor colorWithCalibratedRed:[curColor redComponent]
                                                green:[curColor greenComponent]
                                                 blue:color
                                                alpha:1]];
    [[_tab parentWindow] updateTabColors];
}

- (void)screenCurrentHostDidChange:(VT100RemoteHost *)host {
    if (host.hostname) {
        _variables[kVariableKeySessionHostname] = host.hostname;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionHostname];
    }
    if (host.username) {
        _variables[kVariableKeySessionUsername] = host.username;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionUsername];
    }
    [self dismissAnnouncementWithIdentifier:kShellIntegrationOutOfDateAnnouncementIdentifier];

    [_commandUses autorelease];
    _commandUses = [[[CommandHistory sharedInstance] commandUsesForHost:host] retain];

    [[[self tab] realParentWindow] sessionHostDidChange:self to:host];

    int line = [_screen numberOfScrollbackLines] + _screen.cursorY;
    NSString *path = [_screen workingDirectoryOnLine:line];
    [self tryAutoProfileSwitchWithHostname:host.hostname username:host.username path:path];
}

- (void)tryAutoProfileSwitchWithHostname:(NSString *)hostname
                                username:(NSString *)username
                                    path:(NSString *)path {
    // Construct a map from host binding to profile. This could be expensive with a lot of profiles
    // but it should be fairly rare for this code to run.
    NSMutableDictionary *stringToProfile = [NSMutableDictionary dictionary];
    for (Profile *profile in [[ProfileModel sharedInstance] bookmarks]) {
        NSArray *boundHosts = profile[KEY_BOUND_HOSTS];
        for (NSString *boundHost in boundHosts) {
            stringToProfile[boundHost] = profile;
        }
    }

    // Find the best-matching rule.
    int bestScore = 0;
    int longestHost = 0;
    Profile *bestProfile = nil;

    for (NSString *ruleString in stringToProfile) {
        iTermRule *rule = [iTermRule ruleWithString:ruleString];
        int score = [rule scoreForHostname:hostname username:username path:path];
        if ((score > bestScore) || (score > 0 && score == bestScore && [rule.hostname length] > longestHost)) {
            bestScore = score;
            longestHost = [rule.hostname length];
            bestProfile = stringToProfile[ruleString];
        }
    }
    if (bestProfile) {
        [self setProfile:bestProfile preservingName:NO];
    }

    // screenCurrentDirectoryDidChangeTo depends on us calling setBadgeLabel.
    // If you remove it here, add one there.
    [_textview setBadgeLabel:[self badgeLabel]];
}

- (void)screenCurrentDirectoryDidChangeTo:(NSString *)newPath {
    if (newPath) {
        _variables[kVariableKeySessionPath] = newPath;
    } else {
        [_variables removeObjectForKey:kVariableKeySessionPath];
    }

    int line = [_screen numberOfScrollbackLines] + _screen.cursorY;
    VT100RemoteHost *remoteHost = [_screen remoteHostOnLine:line];
    [self tryAutoProfileSwitchWithHostname:remoteHost.hostname
                                  username:remoteHost.username
                                      path:newPath];
}

- (BOOL)screenShouldSendReport {
    return (_shell != nil) && (![self isTmuxClient]);
}

// FinalTerm
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
                                continuationChars:nil];
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
    return [[CommandHistory sharedInstance] commandHistoryEntriesWithPrefix:trimmedCommand
                                                                     onHost:host];
}

- (void)screenCommandDidChangeWithRange:(VT100GridCoordRange)range {
    DLog(@"FinalTerm: command changed. New range is %@", VT100GridCoordRangeDescription(range));
    _shellIntegrationEverUsed = YES;
    BOOL hadCommand = _commandRange.start.x >= 0 && [[self commandInRange:_commandRange] length] > 0;
    _commandRange = range;
    BOOL haveCommand = _commandRange.start.x >= 0 && [[self commandInRange:_commandRange] length] > 0;
    if (!haveCommand && hadCommand) {
        DLog(@"Hide because don't have a command, but just had one");
        [[[self tab] realParentWindow] hideAutoCommandHistoryForSession:self];
    } else {
        if (!hadCommand && range.start.x >= 0) {
            DLog(@"Show because I have a range but didn't have a command");
            [[[self tab] realParentWindow] showAutoCommandHistoryForSession:self];
        }
        NSString *command = haveCommand ? [self commandInRange:_commandRange] : @"";
        DLog(@"Update command to %@, have=%d, range.start.x=%d", command, (int)haveCommand, range.start.x);
        if (haveCommand) {
            [[[self tab] realParentWindow] updateAutoCommandHistoryForPrefix:command
                                                                   inSession:self];
        }
    }
}

- (void)screenCommandDidEndWithRange:(VT100GridCoordRange)range {
    _shellIntegrationEverUsed = YES;
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
            [[CommandHistory sharedInstance] addCommand:trimmedCommand
                                                 onHost:[_screen remoteHostOnLine:range.end.y]
                                            inDirectory:[_screen workingDirectoryOnLine:range.end.y]
                                               withMark:mark];
            [_commands addObject:trimmedCommand];
        }
    }
    self.lastCommand = command;
    [self updateVariables];
    _commandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
    DLog(@"Hide ACH because command ended");
    [[[self tab] realParentWindow] hideAutoCommandHistoryForSession:self];
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

- (BOOL)screenShouldIgnoreBell {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < _ignoreBellUntil) {
        return YES;
    }
    if (now < _lastBell + 1) {
        // Don't sample bells more than once per second
        return NO;
    }
    _lastBell = now;

    // If the bell rings more often than once every 4 seconds, you will eventually get an offer to
    // silence it.
    static const NSTimeInterval kThresholdForBellMovingAverageToInferAnnoyance = 4;

    // Initial value that will require a reasonable amount of bell-ringing to overcome. This value
    // was chosen so that one bell per second will cause the moving average's value to fall below 4
    // after 3 seconds.
    const NSTimeInterval kMaxDuration = 48;

    if (!_bellRate) {
        _bellRate = [[MovingAverage alloc] init];
    }
    // Keep a moving average of the time between bells
    [_bellRate addValue:MIN(kMaxDuration, [_bellRate timeSinceTimerStarted])];
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
        iTermAnnouncementViewController *announcement =
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
                            break;

                        case -1: // No
                            _annoyingBellOfferDeclinedAt = [NSDate timeIntervalSinceReferenceDate];
                            break;

                        case 0: // Suppress bell temporarily
                            _ignoreBellUntil = now + 60;
                            break;

                        case 1: // Suppress all output
                            _suppressAllOutput = YES;
                            break;

                        case 2: // Never offer again
                            [[NSUserDefaults standardUserDefaults] setBool:YES
                                                                    forKey:kSuppressAnnoyingBellOffer];
                            break;

                        case 3:  // Silence automatically
                            [[NSUserDefaults standardUserDefaults] setBool:YES
                                                                    forKey:kSilenceAnnoyingBellAutomatically];
                            break;
                    }
                }];
        // Set the auto-dismiss timeout.
        announcement.timeout = 10;
        [self queueAnnouncement:announcement identifier:identifier];
    }
    return NO;
}

- (NSString *)screenProfileName {
    return _profile[KEY_NAME];
}

- (void)setLastDirectory:(NSString *)lastDirectory {
    if (lastDirectory) {
        [_directories addObject:lastDirectory];
    }
    [_lastDirectory autorelease];
    _lastDirectory = [lastDirectory copy];
}

- (NSString *)currentLocalWorkingDirectory {
    // Ask the kernel what the child's process's working directory is.
    NSString *localDirectoryWithResolvedSymlinks = [_shell getWorkingDirectory];

    if (_lastDirectory) {
        // See if the last directory from shell integration matches what the kernel reports.
        // Normally, _lastDirectory will contain unfollowed symlinks, which we'd prefer to use
        // (since it's what the user sees).  But there's no way to tell if _lastDirectory refers to
        // local path or one on a remote host. If it resolves to the same location as
        // localDirectoryWithResolvedSymlinks then it's very likely ok.
        NSString *resolvedLastDirectory = [_lastDirectory stringByResolvingSymlinksInPath];
        if ([resolvedLastDirectory isEqualToString:localDirectoryWithResolvedSymlinks]) {
            return _lastDirectory;
        }
    }

    return localDirectoryWithResolvedSymlinks;
}

- (void)setLastRemoteHost:(VT100RemoteHost *)lastRemoteHost {
    if (lastRemoteHost) {
        [_hosts addObject:lastRemoteHost];
    }
    [_lastRemoteHost autorelease];
    _lastRemoteHost = [lastRemoteHost retain];
}

- (void)screenLogWorkingDirectoryAtLine:(int)line withDirectory:(NSString *)directory {
    VT100RemoteHost *remoteHost = [_screen remoteHostOnLine:line];
    BOOL isSame = ([directory isEqualToString:_lastDirectory] &&
                   [remoteHost isEqualToRemoteHost:_lastRemoteHost]);
    [[iTermDirectoriesModel sharedInstance] recordUseOfPath:directory
                                                     onHost:[_screen remoteHostOnLine:line]
                                                   isChange:!isSame];
    self.lastDirectory = directory;
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

- (NSString *)shellIntegrationUpgradeUserDefaultsKeyForHost:(VT100RemoteHost *)host {
    return [NSString stringWithFormat:@"SuppressShellIntegrationUpgradeAnnouncementForHost_%@@%@",
            host.username, host.hostname];
}

- (void)tryToRunShellIntegrationInstaller {
    if (_exited) {
        return;
    }
    NSString *currentCommand = [self currentCommand];
    if (currentCommand != nil) {
        [_textview installShellIntegration:nil];
    } else {
        iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:@"It looks like you're not at a command prompt."
                                       actions:@[ @"Run Installer Anyway", @"Cancel" ]
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent];
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
        [iTermAnnouncementViewController announcementWithTitle:@"This account's Shell Integration scripts are out of date."
                                                         style:kiTermAnnouncementViewStyleWarning
                                                   withActions:@[ @"Upgrade", @"Silence Warning" ]
                                                    completion:^(int selection) {
                switch (selection) {
                    case -2:  // Dismiss programmatically
                        break;

                    case -1: // No
                        break;

                    case 0: // Yes
                        [self tryToRunShellIntegrationInstaller];
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

#pragma mark - Announcements

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
    announcement.completion = ^(int selection) {
        originalCompletion(selection);
        if (selection == -2) {
            [_announcements removeObjectForKey:identifierCopy];
            [identifierCopy release];
            [originalCompletion release];
        }
    };
    [_view addAnnouncement:announcement];
}

#pragma mark - PopupDelegate

- (void)popupWillClose:(Popup *)popup {
    [[[self tab] realParentWindow] popupWillClose:popup];
}

- (NSWindowController *)popupWindowController {
    return [[self tab] realParentWindow];
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
    if (![[[self tab] realParentWindow] autoCommandHistoryIsOpenForSession:self]) {
        return NO;
    }
    if (selector == @selector(cancel:)) {
        [[[self tab] realParentWindow] hideAutoCommandHistoryForSession:self];
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
        [_textview keyDown:[NSEvent keyEventWithType:NSKeyDown
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

- (void)pasteHelperWriteData:(NSData *)data {
    [self writeTask:data];
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

- (BOOL)pasteHelperIsAtShellPrompt {
    return !_shellIntegrationEverUsed || [self currentCommand] != nil;
}

- (BOOL)pasteHelperCanWaitForPrompt {
    return _shellIntegrationEverUsed;
}

@end
