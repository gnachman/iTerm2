#import "PTYSession.h"

#import "CVector.h"
#import "CommandHistory.h"
#import "Coprocess.h"
#import "FakeWindow.h"
#import "FileTransferManager.h"
#import "HotkeyWindowController.h"
#import "ITAddressBookMgr.h"
#import "MovePaneController.h"
#import "MovePaneController.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "PTYScrollView.h"
#import "PTYTab.h"
#import "PTYTask.h"
#import "PTYTextView.h"
#import "PasteContext.h"
#import "PasteEvent.h"
#import "PreferencePanel.h"
#import "ProcessCache.h"
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
#import "iTerm.h"
#import "iTermApplicationDelegate.h"
#import "iTermColorMap.h"
#import "iTermController.h"
#import "iTermGrowlDelegate.h"
#import "iTermKeyBindingMgr.h"
#import "iTermPasteHelper.h"
#import "iTermSelection.h"
#import "iTermSettingsModel.h"
#import "iTermTextExtractor.h"
#import "iTermWarning.h"
#import <apr-1/apr_base64.h>
#include <stdlib.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

// The format for a user defaults key that recalls if the user has already been pestered about
// outdated key mappings for a give profile. The %@ is replaced with the profile's GUID.
static NSString *const kAskAboutOutdatedKeyMappingKeyFormat = @"AskAboutOutdatedKeyMappingForGuid%@";

NSString *const kPTYSessionTmuxFontDidChange = @"kPTYSessionTmuxFontDidChange";

static NSString *TERM_ENVNAME = @"TERM";
static NSString *COLORFGBG_ENVNAME = @"COLORFGBG";
static NSString *PWD_ENVNAME = @"PWD";
static NSString *PWD_ENVVALUE = @"~";

// Constants for saved window arrangement keys.
static NSString* SESSION_ARRANGEMENT_COLUMNS = @"Columns";
static NSString* SESSION_ARRANGEMENT_ROWS = @"Rows";
static NSString* SESSION_ARRANGEMENT_BOOKMARK = @"Bookmark";
static NSString* SESSION_ARRANGEMENT_BOOKMARK_NAME = @"Bookmark Name";
static NSString* SESSION_ARRANGEMENT_WORKING_DIRECTORY = @"Working Directory";
static NSString* SESSION_ARRANGEMENT_TMUX_PANE = @"Tmux Pane";
static NSString* SESSION_ARRANGEMENT_TMUX_HISTORY = @"Tmux History";
static NSString* SESSION_ARRANGEMENT_TMUX_ALT_HISTORY = @"Tmux AltHistory";
static NSString* SESSION_ARRANGEMENT_TMUX_STATE = @"Tmux State";

static NSString *kTmuxFontChanged = @"kTmuxFontChanged";

static int gNextSessionID = 1;

typedef enum {
    TMUX_NONE,
    TMUX_GATEWAY,  // Receiving tmux protocol messages
    TMUX_CLIENT  // Session mirrors a tmux virtual window
} PTYSessionTmuxMode;

@interface PTYSession () <iTermPasteHelperDelegate>
@property(nonatomic, retain) Interval *currentMarkOrNotePosition;
@property(nonatomic, retain) TerminalFile *download;
@property(nonatomic, assign) int sessionID;
@property(nonatomic, readwrite) struct timeval lastOutput;
@property(nonatomic, readwrite) BOOL isDivorced;
@property(atomic, assign) PTYSessionTmuxMode tmuxMode;
@end

@implementation PTYSession {
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

    // Status reporting
    struct timeval _lastInput;

    // Time that the tab label was last updated.
    struct timeval _lastUpdate;

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

    // The current line of text, for checking against triggers if any.
    NSMutableString *_triggerLine;

    // The current triggers.
    NSMutableArray *_triggers;

    // Does the terminal think this session is focused?
    BOOL _focused;

    FindContext *_tailFindContext;
    NSTimer *_tailFindTimer;

    TmuxGateway *_tmuxGateway;
    int _tmuxPane;
    BOOL _tmuxSecureLogging;

    iTermPasteHelper *_pasteHelper;
    
    NSInteger _requestAttentionId;  // Last request-attention identifier
    VT100ScreenMark *_lastMark;

    VT100GridCoordRange _commandRange;
    
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
}

- (id)init {
    self = [super init];
    if (self) {
        _sessionID = gNextSessionID++;
        // The new session won't have the move-pane overlay, so just exit move pane
        // mode.
        [[MovePaneController sharedInstance] exitMovePaneMode];
        _triggerLine = [[NSMutableString alloc] init];
        gettimeofday(&_lastInput, NULL);
        
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
        _screen = [[VT100Screen alloc] initWithTerminal:_terminal];
        NSParameterAssert(_shell != nil && _terminal != nil && _screen != nil);

        _overriddenFields = [[NSMutableSet alloc] init];
        _creationDate = [[NSDate date] retain];
        _tmuxSecureLogging = NO;
        _tailFindContext = [[FindContext alloc] init];
        _commandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
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
    }
    return self;
}

- (void)dealloc
{
    [self stopTailFind];  // This frees the substring in the tail find context, if needed.
    _shell.delegate = nil;
    dispatch_release(_executionSemaphore);
    [_colorMap release];
    [_triggerLine release];
    [_triggers release];
    [_pasteboard release];
    [_pbtext release];
    [_creationDate release];
    [_lastActiveAt release];
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
    [_sendModifiers release];
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

- (void)cancelTimers
{
    [_view cancelTimers];
    [_updateTimer invalidate];
    [_antiIdleTimer invalidate];
}

- (void)setDvr:(DVR*)dvr liveSession:(PTYSession*)liveSession
{
    assert(liveSession != self);

    _liveSession = liveSession;
    [_liveSession retain];
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

+ (PTYSession*)sessionFromArrangement:(NSDictionary*)arrangement
                               inView:(SessionView*)sessionView
                                inTab:(PTYTab*)theTab
                        forObjectType:(iTermObjectType)objectType
{
    PTYSession* aSession = [[[PTYSession alloc] init] autorelease];
    aSession.view = sessionView;
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
    NSNumber *n = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_PANE];
    if (!n) {
        [aSession runCommandWithOldCwd:[arrangement objectForKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY]
                         forObjectType:objectType];
    } else {
        NSString *title = [state objectForKey:@"title"];
        if (title) {
            [aSession setName:title];
            [aSession setWindowTitle:title];
        }
    }
    if (needDivorce) {
        [aSession divorceAddressBookEntryFromPreferences];
        [aSession sessionProfileDidChange];
    }

    if (n) {
        [aSession setTmuxPane:[n intValue]];
    }
    NSArray *history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_HISTORY];
    if (history) {
        [[aSession screen] setHistory:history];
    }
    history = [arrangement objectForKey:SESSION_ARRANGEMENT_TMUX_ALT_HISTORY];
    if (history) {
        [[aSession screen] setAltScreen:history];
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
    return aSession;
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
    _scrollview = [[PTYScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                  0,
                                                                  aRect.size.width,
                                                                  aRect.size.height)
                                   hasVerticalScroller:[parent scrollbarShouldBeVisible]];
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
    [_wrapper setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    _textview = [[PTYTextView alloc] initWithFrame: NSMakeRect(0, VMARGIN, aSize.width, aSize.height)
                                          colorMap:_colorMap];
    _colorMap.dimOnlyText = [[PreferencePanel sharedInstance] dimOnlyText];
    [_textview setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [_textview setFont:[ITAddressBookMgr fontWithDesc:[_profile objectForKey:KEY_NORMAL_FONT]]
          nonAsciiFont:[ITAddressBookMgr fontWithDesc:[_profile objectForKey:KEY_NON_ASCII_FONT]]
     horizontalSpacing:[[_profile objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
       verticalSpacing:[[_profile objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    [self setTransparency:[[_profile objectForKey:KEY_TRANSPARENCY] floatValue]];
        const float theBlend = [_profile objectForKey:KEY_BLEND] ?
                                   [[_profile objectForKey:KEY_BLEND] floatValue] : 0.5;
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
    [_scrollview setDocumentCursor:[PTYTextView textViewCursor]];
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

- (void)runCommandWithOldCwd:(NSString*)oldCWD
               forObjectType:(iTermObjectType)objectType
{
    NSMutableString *cmd;
    NSArray *arg;
    NSString *pwd;
    BOOL isUTF8;

    // Grab the addressbook command
    Profile* addressbookEntry = [self profile];
    cmd = [[[NSMutableString alloc] initWithString:[ITAddressBookMgr bookmarkCommand:addressbookEntry
                                                                       forObjectType:objectType]] autorelease];
    NSMutableString* theName = [[[NSMutableString alloc] initWithString:[addressbookEntry objectForKey:KEY_NAME]] autorelease];
    // Get session parameters
    [[[self tab] realParentWindow] getSessionParameters:cmd withName:theName];

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
    NSDictionary *env = [NSDictionary dictionaryWithObject:pwd forKey:@"PWD"];
    isUTF8 = ([[addressbookEntry objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue] == NSUTF8StringEncoding);

    [[[self tab] realParentWindow] setName:theName forSession:self];

    // Start the command
    [self startProgram:cmd arguments:arg environment:env isUTF8:isUTF8];
}

- (void)setWidth:(int)width height:(int)height
{
    DLog(@"Set session %@ to %dx%d", self, width, height);
    [_screen resizeWidth:width height:height];
    [_shell setWidth:width height:height];
    [_textview clearHighlights];
    [[_tab realParentWindow] invalidateRestorableState];
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode
{
    [[self view] setSplitSelectionMode:mode];
}

- (int)overUnder:(int)proposedSize inVerticalDimension:(BOOL)vertically
{
    int x = proposedSize;
    if (vertically) {
        if ([_view showTitle]) {
            // x = 50/53
            x -= [SessionView titleHeight];
        }
        // x = 28/31
        x -= VMARGIN * 2;
        // x = 18/21
        // iLineHeight = 10
        int iLineHeight = [_textview lineHeight];
        x %= iLineHeight;
        // x = 8/1
        if (x > iLineHeight / 2) {
            x -= iLineHeight;
        }
        // x = -2/1
        return x;
    } else {
        x -= MARGIN * 2;
        int iCharWidth = [_textview charWidth];
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

// This command installs the xterm-256color terminfo in the user's terminfo directory:
// tic -e xterm-256color $FILENAME
- (void)_maybeAskAboutInstallXtermTerminfo
{
    NSString* filename = [[NSBundle bundleForClass:[self class]] pathForResource:@"xterm-terminfo" ofType:@"txt"];
    if (!filename) {
        return;
    }
    NSString* cmd = [NSString stringWithFormat:@"tic -e xterm-256color %@", [filename stringWithEscapedShellCharacters]];
    if (system("infocmp xterm-256color > /dev/null")) {
        iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:@"The terminfo file for the terminal type you're using, \"xterm-256color\", is"
                                               @"not installed on your system. Would you like to install it now?"
                                       actions:@[ @"Install", @"Do not Install" ]
                                    identifier:@"NeverWarnAboutXterm256ColorTerminfo"
                                   silenceable:kiTermWarningTypePermanentlySilenceable];
        if (selection == kiTermWarningSelection0) {
            if (system([cmd UTF8String])) {
                NSRunAlertPanel(@"Error",
                                @"Sorry, an error occurred while running: %@",
                                @"OK", nil, nil, cmd);
            }
        }
    }
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
    return ![iTermSettingsModel doNotSetCtype];
}

- (void)startProgram:(NSString *)program
           arguments:(NSArray *)prog_argv
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
{
    NSString *path = program;
    NSMutableArray *argv = [NSMutableArray arrayWithArray:prog_argv];
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:prog_env];


    if ([env objectForKey:TERM_ENVNAME] == nil)
        [env setObject:_termVariable forKey:TERM_ENVNAME];
    if ([[env objectForKey:TERM_ENVNAME] isEqualToString:@"xterm-256color"]) {
        [self _maybeAskAboutInstallXtermTerminfo];
    }

    if ([env objectForKey:COLORFGBG_ENVNAME] == nil && _colorFgBgVariable != nil)
        [env setObject:_colorFgBgVariable forKey:COLORFGBG_ENVNAME];

    DLog(@"Begin locale logic");
    if (![_profile objectForKey:KEY_SET_LOCALE_VARS] ||
        [[_profile objectForKey:KEY_SET_LOCALE_VARS] boolValue]) {
        DLog(@"Setting locale vars...");
        NSString* lang = [self _lang];
        if (lang) {
            DLog(@"set LANG=%@", lang);
            [env setObject:lang forKey:@"LANG"];
        } else if ([self shouldSetCtype]){
            DLog(@"should set ctype...");
            // Try just the encoding by itself, which might work.
            NSString *encName = [self encodingName];
            DLog(@"See if encoding %@ is supported...", encName);
            if (encName && [self _localeIsSupported:encName]) {
                DLog(@"Set LC_CTYPE=%@", encName);
                [env setObject:encName forKey:@"LC_CTYPE"];
            }
        }
    }

    if ([env objectForKey:PWD_ENVNAME] == nil) {
        [env setObject:[PWD_ENVVALUE stringByExpandingTildeInPath] forKey:PWD_ENVNAME];
    }

    NSWindowController<iTermWindowController> *pty = [_tab realParentWindow];
    NSString *itermId = [NSString stringWithFormat:@"w%dt%dp%d",
                         [pty number],
                         [_tab realObjectCount] - 1,
                         [_tab indexOfSessionView:[self view]]];
    [env setObject:itermId forKey:@"ITERM_SESSION_ID"];
    if ([_profile objectForKey:KEY_NAME]) {
        [env setObject:[_profile objectForKey:KEY_NAME] forKey:@"ITERM_PROFILE"];
    }
    if ([[_profile objectForKey:KEY_AUTOLOG] boolValue]) {
        [_shell loggingStartWithPath:[self _autoLogFilenameForTermId:itermId]];
    }
    [_shell launchWithPath:path
                 arguments:argv
               environment:env
                     width:[_screen width]
                    height:[_screen height]
                    isUTF8:isUTF8];
    NSString *initialText = [_profile objectForKey:KEY_INITIAL_TEXT];
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
                                             makeKey:NO];
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
    if ([[NSDate date] timeIntervalSinceDate:_creationDate] < 3) {
        NSString* theName = [_profile objectForKey:KEY_NAME];
        NSString* theKey = [NSString stringWithFormat:@"NeverWarnAboutShortLivedSessions_%@", [_profile objectForKey:KEY_GUID]];
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

// Terminate a replay session but not the live session
- (void)softTerminate
{
    _liveSession = nil;
    [self terminate];
}

- (void)terminate
{
    if ([[self textview] isFindingCursor]) {
        [[self textview] endFindCursor];
    }
    if (_exited) {
        [self _maybeWarnAboutShortLivedSessions];
    }
    if (self.tmuxMode == TMUX_CLIENT) {
        assert([_tab tmuxWindow] >= 0);
        [_tmuxController deregisterWindow:[_tab tmuxWindow]
                               windowPane:_tmuxPane];
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
        
        // PTYTask will never call taskWasDeregistered since tmux clients are never registered in
        // the first place. There can be calls queued in this queue from previous tmuxReadTask:
        // calls, so queue up a fake call to taskWasDeregistered that will run after all of them,
        // serving the same purpose.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self taskWasDeregistered];
        });
    } else if (self.tmuxMode == TMUX_GATEWAY) {
        [_tmuxController detach];
        [_tmuxGateway release];
        _tmuxGateway = nil;
    }
    _terminal.parser.tmuxParser = nil;
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
    [_shell stop];
    [self retain];  // We must live until -taskWasDeregistered is called.

    // final update of display
    [self updateDisplay];

    [_tab removeSession:self];

    [_textview setDataSource:nil];
    [_textview setDelegate:nil];
    [_textview removeFromSuperview];
    _colorMap.delegate = nil;
    _textview = nil;

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

    [[_tab realParentWindow]  sessionDidTerminate:self];

    _tab = nil;
}

- (void)writeTaskImpl:(NSData *)data
{
    static BOOL checkedDebug;
    static BOOL debugKeyDown;
    if (!checkedDebug) {
        debugKeyDown = [iTermSettingsModel debugKeyDown];
        checkedDebug = YES;
    }
    if (debugKeyDown || gDebugLogging) {
        NSArray *stack = [NSThread callStackSymbols];
        if (debugKeyDown) {
            NSLog(@"writeTaskImpl %p: called from %@", self, stack);
        }
        if (gDebugLogging) {
            DebugLog([NSString stringWithFormat:@"writeTaskImpl %p: called from %@", self, stack]);
        }
        const char *bytes = [data bytes];
        for (int i = 0; i < [data length]; i++) {
            if (debugKeyDown) {
                NSLog(@"writeTask keydown %d: %d (%c)", i, (int) bytes[i], bytes[i]);
            }
            if (gDebugLogging) {
                DebugLog([NSString stringWithFormat:@"writeTask keydown %d: %d (%c)", i, (int) bytes[i], bytes[i]]);
            }
        }
    }

    // check if we want to send this input to all the sessions
    if (![[[self tab] realParentWindow] broadcastInputToSession:self]) {
        // Send to only this session
        if (!_exited) {
            [self setBell:NO];
            PTYScroller* ptys = (PTYScroller*)[_scrollview verticalScroller];
            [_shell writeTask:data];
            [ptys setUserScroll:NO];
        }
    } else {
        // send to all sessions
        [[[self tab] realParentWindow] sendInputToAllSessions:data];
    }
}

- (void)writeTaskNoBroadcast:(NSData *)data
{
    if (self.tmuxMode == TMUX_CLIENT) {
        [[_tmuxController gateway] sendKeys:data
                               toWindowPane:_tmuxPane];
        return;
    }
    [self writeTaskImpl:data];
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
    [self writeTaskImpl:data];
}

- (void)taskWasDeregistered {
    DLog(@"taskWasDeregistered");
    // This is called on the background thread. After this is called, we won't get any more calls
    // on the background thread and it is safe for us to be dealloc'ed.
    [self release];
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

- (void)executeTokens:(const CVector *)vector bytesHandled:(int)length {
    STOPWATCH_START(executing);
    int n = CVectorCount(vector);
    for (int i = 0; i < n; i++) {
        if (_exited || !_terminal || (self.tmuxMode != TMUX_GATEWAY && [_shell hasMuteCoprocess])) {
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
    gettimeofday(&_lastOutput, NULL);
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

- (void)checkTriggers
{
    for (Trigger *trigger in _triggers) {
        [trigger tryString:_triggerLine inSession:self];
    }
}

- (void)appendStringToTriggerLine:(NSString *)s
{
    const int kMaxTriggerLineLength = 1024;
    if ([_triggers count] && [_triggerLine length] + [s length] < kMaxTriggerLineLength) {
        [_triggerLine appendString:s];
    }
}

- (void)clearTriggerLine
{
    if ([_triggers count]) {
        [self checkTriggers];
        [_triggerLine setString:@""];
    }
}

- (void)brokenPipe
{
    if ([self shouldPostGrowlNotification]) {
        [[iTermGrowlDelegate sharedInstance] growlNotify:@"Session Ended"
                                         withDescription:[NSString stringWithFormat:@"Session \"%@\" in tab #%d just terminated.",
                                                          [self name],
                                                          [[self tab] realObjectCount]]
                                         andNotification:@"Broken Pipes"];
    }

    _exited = YES;
    [[self tab] updateLabelAttributes];

    if ([self autoClose]) {
        [[self tab] closeSession:self];
    } else {
        [self updateDisplay];
    }
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
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermKeyBindingsChanged"
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

+ (NSString*)pasteboardString
{
    NSPasteboard *board;

    board = [NSPasteboard generalPasteboard];
    assert(board != nil);

    NSArray *supportedTypes = [NSArray arrayWithObjects:NSFilenamesPboardType, NSStringPboardType, nil];
    NSString *bestType = [board availableTypeFromArray:supportedTypes];

    NSString* info = nil;
    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [board propertyListForType:NSFilenamesPboardType];
        NSMutableArray *escapedFilenames = [NSMutableArray array];
        for (NSString *filename in filenames) {
            [escapedFilenames addObject:[filename stringWithEscapedShellCharacters]];
        }
        if (escapedFilenames.count > 0) {
            info = [escapedFilenames componentsJoinedByString:@" "];
        }
        if ([info length] == 0) {
            info = nil;
        }
    } else {
        info = [board stringForType:NSStringPboardType];
    }
    return info;
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

- (void)setBell:(BOOL)flag
{
    if (flag != _bell) {
        _bell = flag;
        [[self tab] setBell:flag];
        if (_bell) {
            if ([_textview keyIsARepeat] == NO &&
                [self shouldPostGrowlNotification]) {
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
    }

    if (_isDivorced) {
        NSDictionary *sessionProfile = [[ProfileModel sessionsInstance] bookmarkWithGuid:_profile[KEY_GUID]];
        if (![sessionProfile isEqual:_profile]) {
            DLog(@"Session profile changed");
            [self sessionProfileDidChange];
            didChange = YES;
        }
    }
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

    NSDictionary *keyMap = @{ @(kColorMapForeground): KEY_FOREGROUND_COLOR,
                              @(kColorMapBackground): KEY_BACKGROUND_COLOR,
                              @(kColorMapSelection): KEY_SELECTION_COLOR,
                              @(kColorMapSelectedText): KEY_SELECTED_TEXT_COLOR,
                              @(kColorMapBold): KEY_BOLD_COLOR,
                              @(kColorMapCursor): KEY_CURSOR_COLOR,
                              @(kColorMapCursorText): KEY_CURSOR_TEXT_COLOR };
    for (NSNumber *colorKey in keyMap) {
        NSString *profileKey = keyMap[colorKey];
        NSColor *theColor = [ITAddressBookMgr decodeColor:aDict[profileKey]];
        [_colorMap setColor:theColor forKey:[colorKey intValue]];
    }

    for (i = 0; i < 16; i++) {
        NSString *profileKey = [NSString stringWithFormat:KEYTEMPLATE_ANSI_X_COLOR, i];
        NSColor *theColor = [ITAddressBookMgr decodeColor:aDict[profileKey]];
        [_colorMap setColor:theColor forKey:kColorMap8bitBase + i];
    }

    BOOL useSmartCursorColor;
    if ([aDict objectForKey:KEY_SMART_CURSOR_COLOR]) {
        useSmartCursorColor = [[aDict objectForKey:KEY_SMART_CURSOR_COLOR] boolValue];
    } else {
        useSmartCursorColor = [[PreferencePanel sharedInstance] legacySmartCursorColor];
    }
    [self setSmartCursorColor:useSmartCursorColor];

    float minimumContrast;
    if ([aDict objectForKey:KEY_MINIMUM_CONTRAST]) {
        minimumContrast = [[aDict objectForKey:KEY_MINIMUM_CONTRAST] floatValue];
    } else {
        minimumContrast = [[PreferencePanel sharedInstance] legacyMinimumContrast];
    }
    [self setMinimumContrast:minimumContrast];

    // background image
    [self setBackgroundImagePath:[aDict objectForKey:KEY_BACKGROUND_IMAGE_LOCATION]];
    [self setBackgroundImageTiled:[[aDict objectForKey:KEY_BACKGROUND_IMAGE_TILED] boolValue]];

    // colour scheme
    [self setColorFgBgVariable:[self ansiColorsMatchingForeground:[aDict objectForKey:KEY_FOREGROUND_COLOR]
                                                    andBackground:[aDict objectForKey:KEY_BACKGROUND_COLOR]
                                                       inBookmark:aDict]];

    // transparency
    [self setTransparency:[[aDict objectForKey:KEY_TRANSPARENCY] floatValue]];
    [self setBlend:[[aDict objectForKey:KEY_BLEND] floatValue]];

    // bold
    NSNumber* useBoldFontEntry = [aDict objectForKey:KEY_USE_BOLD_FONT];
    NSNumber* disableBoldEntry = [aDict objectForKey:KEY_DISABLE_BOLD];
    if (useBoldFontEntry) {
        [self setUseBoldFont:[useBoldFontEntry boolValue]];
    } else if (disableBoldEntry) {
        // Only deprecated option is set.
        [self setUseBoldFont:![disableBoldEntry boolValue]];
    } else {
        [self setUseBoldFont:YES];
    }
    [_textview setUseBrightBold:[aDict objectForKey:KEY_USE_BRIGHT_BOLD] ? [[aDict objectForKey:KEY_USE_BRIGHT_BOLD] boolValue] : YES];

    // italic
    [self setUseItalicFont:[[aDict objectForKey:KEY_USE_ITALIC_FONT] boolValue]];

    // set up the rest of the preferences
    [_screen setAudibleBell:![[aDict objectForKey:KEY_SILENCE_BELL] boolValue]];
    [_screen setShowBellIndicator:[[aDict objectForKey:KEY_VISUAL_BELL] boolValue]];
    [_screen setFlashBell:[[aDict objectForKey:KEY_FLASHING_BELL] boolValue]];
    [_screen setPostGrowlNotifications:[[aDict objectForKey:KEY_BOOKMARK_GROWL_NOTIFICATIONS] boolValue]];
    [_screen setCursorBlinks:[[aDict objectForKey:KEY_BLINKING_CURSOR] boolValue]];
    [_textview setBlinkAllowed:[[aDict objectForKey:KEY_BLINK_ALLOWED] boolValue]];
    [_textview setBlinkingCursor:[[aDict objectForKey:KEY_BLINKING_CURSOR] boolValue]];
    [_textview setCursorType:([aDict objectForKey:KEY_CURSOR_TYPE] ? [[aDict objectForKey:KEY_CURSOR_TYPE] intValue] : [[PreferencePanel sharedInstance] legacyCursorType])];

    PTYTab* currentTab = [[[self tab] parentWindow] currentTab];
    if (currentTab == nil || currentTab == [self tab]) {
        [[self tab] recheckBlur];
    }
    BOOL asciiAA;
    BOOL nonasciiAA;
    if ([aDict objectForKey:KEY_ASCII_ANTI_ALIASED]) {
        asciiAA = [[aDict objectForKey:KEY_ASCII_ANTI_ALIASED] boolValue];
    } else {
        asciiAA = [[aDict objectForKey:KEY_ANTI_ALIASING] boolValue];
    }
    if ([aDict objectForKey:KEY_NONASCII_ANTI_ALIASED]) {
        nonasciiAA = [[aDict objectForKey:KEY_NONASCII_ANTI_ALIASED] boolValue];
    } else {
        nonasciiAA = [[aDict objectForKey:KEY_ANTI_ALIASING] boolValue];
    }
    [_triggers release];
    _triggers = [[NSMutableArray alloc] init];
    for (NSDictionary *triggerDict in [aDict objectForKey:KEY_TRIGGERS]) {
        Trigger *trigger = [Trigger triggerFromDict:triggerDict];
        if (trigger) {
            [_triggers addObject:trigger];
        }
    }
    [_textview setSmartSelectionRules:[aDict objectForKey:KEY_SMART_SELECTION_RULES]];
    [_textview setTrouterPrefs:[aDict objectForKey:KEY_TROUTER]];
    [_textview setUseNonAsciiFont:[[aDict objectForKey:KEY_USE_NONASCII_FONT] boolValue]];
    [_textview setAntiAlias:asciiAA nonAscii:nonasciiAA];
    [self setEncoding:[[aDict objectForKey:KEY_CHARACTER_ENCODING] unsignedIntValue]];
    [self setTermVariable:[aDict objectForKey:KEY_TERMINAL_TYPE]];
    [self setAntiIdleCode:[[aDict objectForKey:KEY_IDLE_CODE] intValue]];
    [self setAntiIdle:[[aDict objectForKey:KEY_SEND_CODE_WHEN_IDLE] boolValue]];
    [self setAutoClose:[[aDict objectForKey:KEY_CLOSE_SESSIONS_ON_END] boolValue]];
    [self setTreatAmbiguousWidthAsDoubleWidth:[[aDict objectForKey:KEY_AMBIGUOUS_DOUBLE_WIDTH] boolValue]];
    [self setXtermMouseReporting:[[aDict objectForKey:KEY_XTERM_MOUSE_REPORTING] boolValue]];
    [_terminal setDisableSmcupRmcup:[[aDict objectForKey:KEY_DISABLE_SMCUP_RMCUP] boolValue]];
    [_screen setAllowTitleReporting:[[aDict objectForKey:KEY_ALLOW_TITLE_REPORTING] boolValue]];
    [_terminal setAllowKeypadMode:[aDict boolValueDefaultingToYesForKey:KEY_APPLICATION_KEYPAD_ALLOWED]];
    [_screen setUnlimitedScrollback:[[aDict objectForKey:KEY_UNLIMITED_SCROLLBACK] intValue]];
    [_screen setMaxScrollbackLines:[[aDict objectForKey:KEY_SCROLLBACK_LINES] intValue]];

    _screen.appendToScrollbackWithStatusBar = [[aDict objectForKey:KEY_SCROLLBACK_WITH_STATUS_BAR] boolValue];
    
    [self setFont:[ITAddressBookMgr fontWithDesc:[aDict objectForKey:KEY_NORMAL_FONT]]
        nonAsciiFont:[ITAddressBookMgr fontWithDesc:[aDict objectForKey:KEY_NON_ASCII_FONT]]
        horizontalSpacing:[[aDict objectForKey:KEY_HORIZONTAL_SPACING] floatValue]
        verticalSpacing:[[aDict objectForKey:KEY_VERTICAL_SPACING] floatValue]];
    [_screen setSaveToScrollbackInAlternateScreen:[aDict objectForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN] ? [[aDict objectForKey:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN] boolValue] : YES];
    [[_tab realParentWindow] invalidateRestorableState];
}

- (NSString *)uniqueID
{
    return [self tty];
}

- (NSString*)formattedName:(NSString*)base
{
    NSString *prefix = _tmuxController ? [NSString stringWithFormat:@"↣ %@: ", [[self tab] tmuxWindowName]] : @"";

    BOOL baseIsBookmarkName = [base isEqualToString:_bookmarkName];
    PreferencePanel* panel = [PreferencePanel sharedInstance];
    if ([panel jobName] && _jobName) {
        if (baseIsBookmarkName && ![panel showBookmarkName]) {
            return [NSString stringWithFormat:@"%@%@", prefix, [self jobName]];
        } else {
            return [NSString stringWithFormat:@"%@%@ (%@)", prefix, base, [self jobName]];
        }
    } else {
        if (baseIsBookmarkName && ![panel showBookmarkName]) {
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
                               windowPane:_tmuxPane];
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


- (NSString *)tty
{
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

- (void)setSmartCursorColor:(BOOL)value
{
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
    [[[self tab] realParentWindow] updateContentShadow];
}

- (float)blend
{
    return [_textview blend];
}

- (void)setBlend:(float)blendVal
{
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
        _antiIdleTimer = [[NSTimer scheduledTimerWithTimeInterval:[[PreferencePanel sharedInstance] antiIdleTimerPeriod]
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

- (void)logStart
{
    NSSavePanel *panel;
    int sts;

    panel = [NSSavePanel savePanel];
    // Session could end before panel is dismissed.
    [[self retain] autorelease];
    panel.directoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    panel.nameFieldStringValue = @"";
    sts = [panel runModal];
    if (sts == NSOKButton) {
        BOOL logsts = [_shell loggingStartWithPath:panel.URL.path];
        if (logsts == NO) {
            NSBeep();
        }
    }
}

- (void)logStop
{
    [_shell loggingStop];
}

- (void)clearBuffer
{
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

- (void)setProfile:(NSDictionary*)entry
{
    assert(entry);
    DLog(@"Set address book entry to one with guid %@", entry[KEY_GUID]);
    NSMutableDictionary *dict = [[entry mutableCopy] autorelease];
    // This is the most practical way to migrate the bopy of a
    // profile that's stored in a saved window arrangement. It doesn't get
    // saved back into the arrangement, unfortunately.
    [ProfileModel migratePromptOnCloseInMutableBookmark:dict];

    NSString *originalGuid = [entry objectForKey:KEY_ORIGINAL_GUID];
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
        _originalProfile = [NSDictionary dictionaryWithDictionary:dict];
        [_originalProfile retain];
    }
    [_profile release];
    _profile = [dict retain];
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

- (NSDictionary*)arrangement
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:3];
    [result setObject:[NSNumber numberWithInt:[_screen width]] forKey:SESSION_ARRANGEMENT_COLUMNS];
    [result setObject:[NSNumber numberWithInt:[_screen height]] forKey:SESSION_ARRANGEMENT_ROWS];
    [result setObject:_profile forKey:SESSION_ARRANGEMENT_BOOKMARK];
    result[SESSION_ARRANGEMENT_BOOKMARK_NAME] = _bookmarkName;
    NSString* pwd = [_shell getWorkingDirectory];
    [result setObject:pwd ? pwd : @"" forKey:SESSION_ARRANGEMENT_WORKING_DIRECTORY];
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

- (void)updateScroll
{
    if (![(PTYScroller*)([_scrollview verticalScroller]) userScroll]) {
        [_textview scrollEnd];
    }
}

static long long timeInTenthsOfSeconds(struct timeval t)
{
    return t.tv_sec * 10 + t.tv_usec / 100000;
}

- (void)updateDisplay
{
    _timerRunning = YES;
    BOOL anotherUpdateNeeded = [NSApp isActive];
    if (!anotherUpdateNeeded &&
        _updateDisplayUntil &&
        [NSDate timeIntervalSinceReferenceDate] < _updateDisplayUntil) {
        // We're still in the time window after the last output where updates are needed.
        anotherUpdateNeeded = YES;
    }

    // Set color, other attributes of a tab.
    anotherUpdateNeeded |= [[self tab] updateLabelAttributes];

    if ([[self tab] activeSession] == self) {
        // Update window info for the active tab.
        struct timeval now;
        gettimeofday(&now, NULL);
        if (!_jobName ||
            timeInTenthsOfSeconds(now) >= timeInTenthsOfSeconds(_lastUpdate) + 7) {
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
        } else if (timeInTenthsOfSeconds(now) < timeInTenthsOfSeconds(_lastUpdate) + 7) {
            // If it's been less than 700ms keep updating.
            anotherUpdateNeeded = YES;
        }
    }

    anotherUpdateNeeded |= [_textview refresh];
    anotherUpdateNeeded |= [[[self tab] parentWindow] tempTitle];

    if (anotherUpdateNeeded) {
        if ([[[self tab] parentWindow] currentTab] == [self tab]) {
            [self scheduleUpdateIn:[[PreferencePanel sharedInstance] timeBetweenBlinks]];
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
    _timerRunning = NO;
}

- (void)refreshAndStartTimerIfNeeded
{
    if ([_textview refresh]) {
        [self scheduleUpdateIn:[[PreferencePanel sharedInstance] timeBetweenBlinks]];
    }
}

- (void)scheduleUpdateIn:(NSTimeInterval)timeout
{
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
    
    _updateTimer = [[NSTimer scheduledTimerWithTimeInterval:MAX(0, timeout - timeSinceLastUpdate)
                                                     target:self
                                                   selector:@selector(updateDisplay)
                                                   userInfo:[NSNumber numberWithFloat:(float)timeout]
                                                    repeats:NO] retain];
}

- (void)doAntiIdle
{
    struct timeval now;
    gettimeofday(&now, NULL);

    if (now.tv_sec >= _lastInput.tv_sec + 60) {
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
    if ([[_textview font] isEqualTo:font] &&
        [[_textview nonAsciiFont] isEqualTo:nonAsciiFont] &&
        [_textview horizontalSpacing] == horizontalSpacing &&
        [_textview verticalSpacing] == verticalSpacing) {
        return;
    }
    DLog(@"Line height was %f", (float)[_textview lineHeight]);
    [_textview setFont:font
         nonAsciiFont:nonAsciiFont
        horizontalSpacing:horizontalSpacing
        verticalSpacing:verticalSpacing];
    DLog(@"Line height is now %f", (float)[_textview lineHeight]);
    if (![[[self tab] parentWindow] anyFullScreen]) {
        if ([[PreferencePanel sharedInstance] adjustWindowForFontSizeChange]) {
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
                                                            object:[NSArray arrayWithObjects:[_textview font],
                                                                    [_textview nonAsciiFont],
                                                                    [NSNumber numberWithDouble:[_textview horizontalSpacing]],
                                                                    [NSNumber numberWithDouble:[_textview verticalSpacing]],
                                                                    nil]];
        fontChangeNotificationInProgress = NO;
        [PTYTab setTmuxFont:[_textview font]
               nonAsciiFont:[_textview nonAsciiFont]
                   hSpacing:[_textview horizontalSpacing]
                   vSpacing:[_textview verticalSpacing]];
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
        font = [self fontWithRelativeSize:dir from:[_textview font]];
        nonAsciiFont = [self fontWithRelativeSize:dir from:[_textview nonAsciiFont]];
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
    [[ProfileModel sessionsInstance] removeBookmarkWithGuid:guid];
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
    [[_view findViewController] findString:string];
}

- (void)findWithSelection
{
    if ([_textview selectedText]) {
        [[_view findViewController] findString:[_textview selectedText]];
    }
}

- (void)toggleFind
{
    [[_view findViewController] toggleVisibility];
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

- (BOOL)continueFind
{
    return [_textview continueFind];
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

- (BOOL)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
      ignoringCase:(BOOL)ignoreCase
             regex:(BOOL)regex
        withOffset:(int)offset
{
    return [_textview findString:aString
                forwardDirection:direction
                    ignoringCase:ignoreCase
                           regex:regex
                      withOffset:offset];
}

- (NSString*)unpaddedSelectedText
{
    return [_textview selectedTextWithPad:NO];
}

- (void)copySelection
{
    return [_textview copySelectionAccordingToUserPreferences];
}

- (void)takeFocus
{
    [[[[self tab] realParentWindow] window] makeFirstResponder:_textview];
}

- (void)clearHighlights
{
    [_textview clearHighlights];
}

- (NSImage *)snapshot {
    [_textview refresh];
    return [_view snapshot];
}

- (NSImage *)dragImage
{
    NSImage *image = [self snapshot];
    // Dial the alpha down to 50%
    NSImage *dragImage = [[[NSImage alloc] initWithSize:[image size]] autorelease];
    [dragImage lockFocus];
    [image compositeToPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:0.5];
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

- (void)setFocused:(BOOL)focused
{
    if (focused != _focused) {
        _focused = focused;
        if ([_terminal reportFocus]) {
            char flag = focused ? 'I' : 'O';
            NSString *message = [NSString stringWithFormat:@"%c[%c", 27, flag];
            [self writeTask:[message dataUsingEncoding:[self encoding]]];
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

- (void)hideSession
{
    [[MovePaneController sharedInstance] moveSessionToNewWindow:self
                                                        atPoint:[[_view window] convertBaseToScreen:NSMakePoint(0, 0)]];
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
    [_tmuxController setClientSize:theSize];

    [self printTmuxMessage:@"** tmux mode started **"];
    [_screen crlf];
    [self printTmuxMessage:@"Command Menu"];
    [self printTmuxMessage:@"----------------------------"];
    [self printTmuxMessage:@"esc    Detach cleanly."];
    [self printTmuxMessage:@"  X    Force-quit tmux mode."];
    [self printTmuxMessage:@"  L    Toggle logging."];
    [self printTmuxMessage:@"  C    Run tmux command."];

    if ([[PreferencePanel sharedInstance] autoHideTmuxClientSession]) {
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

- (void)setTmuxPane:(int)windowPane
{
    _tmuxPane = windowPane;
    self.tmuxMode = TMUX_CLIENT;
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
              respectDividers:YES];
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
    if ([obj isKindOfClass:[VT100ScreenMark class]]) {
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
                [_textview beginFlash:FlashWrapToBottom];
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
                [_textview beginFlash:FlashWrapToTop];
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

- (void)scrollToMark:(VT100ScreenMark *)mark {
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
    _terminal.parser.tmuxParser = nil;
    self.tmuxMode = TMUX_NONE;

    if ([[PreferencePanel sharedInstance] autoHideTmuxClientSession] &&
        [[[_tab realParentWindow] window] isMiniaturized]) {
        [[[_tab realParentWindow] window] deminiaturize:self];
    }
}

- (void)tmuxSetSecureLogging:(BOOL)secureLogging {
    _tmuxSecureLogging = secureLogging;
}

- (void)tmuxWriteData:(NSData *)data
{
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
    [self writeTaskImpl:data];
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
- (void)keyDown:(NSEvent *)event
{
  BOOL debugKeyDown = [iTermSettingsModel debugKeyDown];
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
  if (debugKeyDown) {
    NSLog(@"PTYSession keyDown modflag=%d keystr=%@ unmodkeystr=%@ unicode=%d unmodunicode=%d", (int)modflag, keystr, unmodkeystr, (int)unicode, (int)unmodunicode);
  }
  gettimeofday(&_lastInput, NULL);

  if ([[[self tab] realParentWindow] inInstantReplay]) {
    if (debugKeyDown) {
      NSLog(@"PTYSession keyDown in IR");
    }
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
  if (debugKeyDown) {
    NSLog(@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask));
  }
  DebugLog([NSString stringWithFormat:@"event:%@ (%x+%x)[%@][%@]:%x(%c) <%d>", event,modflag,keycode,keystr,unmodkeystr,unicode,unicode,(modflag & NSNumericPadKeyMask)]);

  // Check if we have a custom key mapping for this event
  keyBindingAction = [iTermKeyBindingMgr actionForKeyCode:unmodunicode
                                                modifiers:modflag
                                                     text:&keyBindingText
                                              keyMappings:[[self profile] objectForKey:KEY_KEYBOARD_MAP]];

  if (keyBindingAction >= 0) {
    if (debugKeyDown) {
      NSLog(@"PTYSession keyDown action=%d", keyBindingAction);
    }
    DebugLog([NSString stringWithFormat:@"keyBindingAction=%d", keyBindingAction]);
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
        [[[[self tab] parentWindow] tabView] processMRUEvent:event];
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
    if (debugKeyDown) {
      NSLog(@"PTYSession keyDown no keybinding action");
    }
    DebugLog(@"No keybinding action");
    if (_exited) {
      DebugLog(@"Terminal already dead");
      return;
    }
    // No special binding for this key combination.
    if (modflag & NSFunctionKeyMask) {
      if (debugKeyDown) {
        NSLog(@"PTYSession keyDown is a function key");
      }
      DebugLog(@"Is a function key");
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
    } else if (((modflag & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask &&
                ([self optionKey] != OPT_NORMAL)) ||
               (modflag == NSAlternateKeyMask &&
                ([self optionKey] != OPT_NORMAL)) ||  /// synergy
               ((modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask &&
                ([self rightOptionKey] != OPT_NORMAL))) {
                 if (debugKeyDown) {
                   NSLog(@"PTYSession keyDown opt + key -> modkey");
                 }
                 DebugLog(@"Option + key -> modified key");
                 // A key was pressed while holding down option and the option key
                 // is not behaving normally. Apply the modified behavior.
                 int mode;  // The modified behavior based on which modifier is pressed.
                 if ((modflag == NSAlternateKeyMask) ||  // synergy
                     (modflag & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask) {
                   mode = [self optionKey];
                 } else {
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
                 if (debugKeyDown) {
                   NSLog(@"PTYSession keyDown regular path");
                 }
                 DebugLog(@"Regular path for keypress");
                 // Regular path for inserting a character from a keypress.
                 int max = [keystr length];
                 NSData *data=nil;

                 if (max != 1||[keystr characterAtIndex:0] > 0x7f) {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown non-ascii");
                   }
                   DebugLog(@"Non-ascii input");
                   data = [keystr dataUsingEncoding:[_terminal encoding]];
                 } else {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown ascii");
                   }
                   DebugLog(@"ASCII input");
                   data = [keystr dataUsingEncoding:NSUTF8StringEncoding];
                 }

                 // Enter key is on numeric keypad, but not marked as such
                 if (unicode == NSEnterCharacter && unmodunicode == NSEnterCharacter) {
                   modflag |= NSNumericPadKeyMask;
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown enter key");
                   }
                   DebugLog(@"Enter key");
                   keystr = @"\015";  // Enter key -> 0x0d
                 }
                 // Check if we are in keypad mode
                 if (modflag & NSNumericPadKeyMask) {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown numeric keyoad");
                   }
                   DebugLog(@"Numeric keypad mask");
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
                       DebugLog(@"Cmd + 0-9 or cmd + enter");
                       if (debugKeyDown) {
                         NSLog(@"PTYSession keyDown cmd+0-9 or cmd+enter");
                       }
                       data = nil;
                     }
                 if (data != nil) {
                   send_str = (unsigned char *)[data bytes];
                   send_strlen = [data length];
                   DebugLog([NSString stringWithFormat:@"modflag = 0x%x; send_strlen = %zd; send_str[0] = '%c (0x%x)'",
                             modflag, send_strlen, send_str[0], send_str[0]]);
                   if (debugKeyDown) {
                     DebugLog([NSString stringWithFormat:@"modflag = 0x%x; send_strlen = %zd; send_str[0] = '%c (0x%x)'",
                               modflag, send_strlen, send_str[0], send_str[0]]);
                   }
                 }

                 if ((modflag & NSControlKeyMask) &&
                     send_strlen == 1 &&
                     send_str[0] == '|') {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown c-|");
                   }
                   // Control-| is sent as Control-backslash
                   send_str = (unsigned char*)"\034";
                   send_strlen = 1;
                 } else if ((modflag & NSControlKeyMask) &&
                            (modflag & NSShiftKeyMask) &&
                            send_strlen == 1 &&
                            send_str[0] == '/') {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown c-?");
                   }
                   // Control-shift-/ is sent as Control-?
                   send_str = (unsigned char*)"\177";
                   send_strlen = 1;
                 } else if ((modflag & NSControlKeyMask) &&
                            send_strlen == 1 &&
                            send_str[0] == '/') {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown c-/");
                   }
                   // Control-/ is sent as Control-/, but needs some help to do so.
                   send_str = (unsigned char*)"\037"; // control-/
                   send_strlen = 1;
                 } else if ((modflag & NSShiftKeyMask) &&
                            send_strlen == 1 &&
                            send_str[0] == '\031') {
                   if (debugKeyDown) {
                     NSLog(@"PTYSession keyDown shift-tab -> esc[Z");
                   }
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

// Pastes a specific string. All pastes go through this method. Adds to the event queue if a paste
// is in progress.
- (void)pasteString:(NSString *)theString flags:(PTYSessionPasteFlags)flags
{
    [_pasteHelper pasteString:theString flags:flags];
}

// Pastes the current string in the clipboard. Uses the sender's tag to get flags.
- (void)paste:(id)sender
{
    [self pasteString:[PTYSession pasteboardString] flags:[sender tag]];
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
            [[_textview.dimmedDefaultBackgroundColor colorWithAlphaComponent:1 - _textview.blend] set];
            NSRectFillUsingOperation(rect, NSCompositeSourceOver);
        }
    } else if (blendDefaultBackground) {
        // No image, so just draw background color.
        [[_textview.dimmedDefaultBackgroundColor colorWithAlphaComponent:alpha] set];
        NSRectFill(rect);
    }
    
    [self drawMaximizedPaneDottedOutlineIndicatorInView:view];
}

- (void)drawMaximizedPaneDottedOutlineIndicatorInView:(NSView *)view {
    if ([self textViewTabHasMaximizedPanel]) {
        NSColor *color = [_colorMap colorForKey:kColorMapBackground];
        double grayLevel = [color isDark] ? 1 : 0;
        color = [color colorDimmedBy:0.2 towardsGrayLevel:grayLevel];
        NSRect frame = [_view convertRect:[_view contentRect] toView:view];

        NSBezierPath *path = [[[NSBezierPath alloc] init] autorelease];
        CGFloat left = frame.origin.x + 0.5;
        CGFloat right = frame.origin.x + frame.size.width - 0.5;
        CGFloat top = frame.origin.y + 0.5;
        CGFloat bottom = frame.origin.y + frame.size.height - 0.5;
        
        [path moveToPoint:NSMakePoint(left, top + VMARGIN)];
        [path lineToPoint:NSMakePoint(left, top)];
        [path lineToPoint:NSMakePoint(right, top)];
        [path lineToPoint:NSMakePoint(right, bottom)];
        [path lineToPoint:NSMakePoint(left, bottom)];
        [path lineToPoint:NSMakePoint(left, top + VMARGIN)];
        
        CGFloat dashPattern[2] = { 5, 5 };
        [path setLineDash:dashPattern count:2 phase:0];
        [color set];
        [path stroke];
    }
}

- (void)textViewPostTabContentsChangedNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermTabContentsChanged"
                                                        object:self
                                                      userInfo:nil];
}

- (void)textViewBeginDrag
{
    [[MovePaneController sharedInstance] beginDrag:self];
}

- (void)textViewMovePane
{
    [[MovePaneController sharedInstance] movePane:self];
}

- (NSStringEncoding)textViewEncoding
{
    return [self encoding];
}

- (NSString *)textViewCurrentWorkingDirectory {
    return [_shell getWorkingDirectory];
}

- (BOOL)textViewShouldPlaceCursor {
    // Only place cursor when not at the command line.
    return _commandRange.start.x < 0;
}

- (BOOL)textViewShouldDrawFilledInCursor {
    // If the auto-command history popup is open for this session, the filled-in cursor should be
    // drawn even though the textview isn't in the key window.
    return [self textViewIsActiveSession] && [[[self tab] realParentWindow] autoCommandHistoryIsOpenForSession:self];
}

- (void)textViewWillNeedUpdateForBlink
{
    [self scheduleUpdateIn:[[PreferencePanel sharedInstance] timeBetweenBlinks]];
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

- (void)textViewEditSession
{
    [[[self tab] realParentWindow] editSession:self];
}

- (void)textViewToggleBroadcastingInput
{
    [[[self tab] realParentWindow] toggleBroadcastingInputToSession:self];
}

- (void)textViewCloseWithConfirmation
{
    [[[self tab] realParentWindow] closeSessionWithConfirmation:self];
}

- (NSString *)textViewPasteboardString
{
    return [[self class] pasteboardString];
}

- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags
{
    PTYSession *session = [[iTermController sharedInstance] sessionWithMostRecentSelection];
    if (session) {
        PTYTextView *textview = [session textview];
        if ([textview isAnyCharSelected]) {
            [self pasteString:[textview selectedText] flags:flags];
        }
    }
}

- (void)textViewPasteWithEncoding:(TextViewPasteEncoding)encoding
{
    NSData *data = [[self class] pasteboardFile];
    if (data) {
        int length = apr_base64_encode_len(data.length);
        NSMutableData *buffer = [NSMutableData dataWithLength:length];
        if (buffer) {
            apr_base64_encode_binary(buffer.mutableBytes,
                                     data.bytes,
                                     data.length);
        }
        NSMutableString *string = [NSMutableString string];
        int remaining = length;
        int offset = 0;
        char *bytes = (char *)buffer.mutableBytes;
        while (remaining > 0) {
            @autoreleasepool {
                NSString *chunk = [[[NSString alloc] initWithBytes:bytes + offset
                                                            length:MIN(77, remaining)
                                                          encoding:NSUTF8StringEncoding] autorelease];
                [string appendString:chunk];
                [string appendString:@"\n"];
                remaining -= chunk.length;
                offset += chunk.length;
            }
        }
        [self pasteString:string flags:0];
    }
}

- (BOOL)textViewCanPasteFile
{
    return [[self class] pasteboardFile] != nil;
}

- (BOOL)textViewWindowUsesTransparency
{
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

- (BOOL)textViewDelegateHandlesAllKeystrokes
{
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
                    if ([[PreferencePanel sharedInstance] alternateMouseScroll] &&
                        [_screen showingAlternateScreen]) {
                        NSData *arrowKeyData = nil;
                        if (deltaY > 0) {
                            arrowKeyData = [_terminal.output keyArrowUp:modifiers];
                        } else if (deltaY < 0) {
                            arrowKeyData = [_terminal.output keyArrowDown:modifiers];
                        }
                        if (arrowKeyData) {
                            for (int i = 0; i < ceil(fabs(deltaY)); i++) {
                                [self writeTask:arrowKeyData];
                            }
                        }
                        return YES;
                    }
                    break;

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

- (void)sendHexCode:(NSString *)codes
{
    if (_exited) {
        return;
    }
    if ([codes length]) {
        NSArray* components = [codes componentsSeparatedByString:@" "];
        for (NSString* part in components) {
            const char* utf8 = [part UTF8String];
            char* endPtr;
            unsigned char c = strtol(utf8, &endPtr, 16);
            if (endPtr != utf8) {
                [self writeTask:[NSData dataWithBytes:&c length:sizeof(c)]];
            }
        }
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

- (void)sessionContentsChanged:(NSNotification *)notification
{
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

- (void)printTmuxMessage:(NSString *)message
{
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

- (int)screenSessionID {
    return self.sessionID;
}

- (void)screenNeedsRedraw {
    [self refreshAndStartTimerIfNeeded];
    [_textview updateNoteViewFrames];
    [_textview setNeedsDisplay:YES];
}

- (void)screenUpdateDisplay {
    [self updateDisplay];
}

- (void)screenSizeDidChange {
    [self updateScroll];
    [_textview updateNoteViewFrames];
}

- (void)screenTriggerableChangeDidOccur {
    [self clearTriggerLine];
}

- (void)screenDidReset {
    [self loadInitialColorTable];
    _textview.highlightCursorLine = NO;
    [_textview setNeedsDisplay:YES];
    _screen.trackCursorLineMovement = NO;
}

- (BOOL)screenShouldSyncTitle {
    if (![[PreferencePanel sharedInstance] showBookmarkName]) {
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
    [self writeTask:data];
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

- (void)screenModifiersDidChangeTo:(NSArray *)modifiers {
    [self setSendModifiers:modifiers];
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

- (void)screenFlashImage:(FlashImage)image {
    [_textview beginFlash:image];
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
    _textview.highlightCursorLine = highlight;
    [_textview setNeedsDisplay:YES];
    _screen.trackCursorLineMovement = highlight;
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

- (void)screenAddMarkOnLine:(int)line {
    [_textview refresh];  // In case text was appended
    [_lastMark release];
    _lastMark = [[_screen addMarkStartingAtAbsoluteLine:[_screen totalScrollbackOverflow] + line
                                                oneLine:YES] retain];
    self.currentMarkOrNotePosition = _lastMark.entry.interval;
    if (self.alertOnNextMark) {
        if (NSRunAlertPanel(@"Alert",
                            @"Mark set in session “%@.”",
                            @"Reveal",
                            @"OK",
                            nil,
                            [self name]) == NSAlertDefaultReturn) {
            [self reveal];
        }
        self.alertOnNextMark = NO;
    }
}

// Save the current scroll position
- (void)screenSaveScrollPosition
{
    [_textview refresh];  // In case text was appended
    [_lastMark release];
    _lastMark = [[_screen addMarkStartingAtAbsoluteLine:[_textview absoluteScrollPosition]
                                                oneLine:NO] retain];
    self.currentMarkOrNotePosition = _lastMark.entry.interval;
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
        NSString *theName = [[self profile] objectForKey:KEY_NAME];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:newProfile];
        [dict setObject:theName forKey:KEY_NAME];
        [self setProfile:dict];
        [self setPreferencesFromAddressBookEntry:dict];
        [self remarry];
    }
}

- (void)screenSetPasteboard:(NSString *)value {
    if ([[PreferencePanel sharedInstance] allowClipboardAccess]) {
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
    if ([[PreferencePanel sharedInstance] allowClipboardAccess]) {
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

- (iTermColorMap *)screenColorMap {
    return _colorMap;
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
    [[[self tab] realParentWindow] sessionHostDidChange:self to:host];
}

- (BOOL)screenShouldSendReport {
    return (_shell != nil) && (![self isTmuxClient]);
}

// FinalTerm
- (NSString *)commandInRange:(VT100GridCoordRange)range {
    if (range.start.x == -1) {
        return nil;
    }
    iTermTextExtractor *extractor = [iTermTextExtractor textExtractorWithDataSource:_screen];
    NSString *command = [extractor contentInRange:VT100GridWindowedRangeMake(range, 0, 0)
                                       nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                              pad:NO
                               includeLastNewline:NO
                           trimTrailingWhitespace:NO
                                     cappedAtSize:-1];
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
    return [[CommandHistory sharedInstance] autocompleteSuggestionsWithPartialCommand:trimmedCommand
                                                                               onHost:host];
}
- (void)screenCommandDidChangeWithRange:(VT100GridCoordRange)range {
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
        DLog(@"Update command to %@", command);
        [[[self tab] realParentWindow] updateAutoCommandHistoryForPrefix:command
                                                               inSession:self];
    }
}

- (void)screenCommandDidEndWithRange:(VT100GridCoordRange)range {
    NSString *command = [self commandInRange:range];
    if (command) {
        NSString *trimmedCommand =
            [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedCommand.length) {
            VT100ScreenMark *mark = [_screen markOnLine:range.start.y];
            mark.command = command;
            [[CommandHistory sharedInstance] addCommand:trimmedCommand
                                                 onHost:[_screen remoteHostOnLine:range.end.y]
                                            inDirectory:[_screen workingDirectoryOnLine:range.end.y]
                                               withMark:mark];
        }
    }
    _commandRange = VT100GridCoordRangeMake(-1, -1, -1, -1);
    DLog(@"Hide ACH because command ended");
    [[[self tab] realParentWindow] hideAutoCommandHistoryForSession:self];
}

- (BOOL)screenAllowTitleSetting {
    NSNumber *n = _profile[KEY_ALLOW_TITLE_SETTING];
    if (!n) {
        return YES;
    } else {
        return [n boolValue];
    }
}

#pragma mark - PopupDelegate

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

- (BOOL)popupKeyDown:(NSEvent *)event currentValue:(NSString *)value {
    if ([[[self tab] realParentWindow] autoCommandHistoryIsOpenForSession:self]) {
        unichar c = [[event characters] characterAtIndex:0];
        if (c == 27) {
            [[[self tab] realParentWindow] hideAutoCommandHistoryForSession:self];
            return YES;
        } else if (c == '\r') {
            if ([value isEqualToString:[self currentCommand]]) {
                // Send the enter key on.
                [_textview keyDown:event];
                return YES;
            } else {
                return NO;  // select the row
            }
        } else {
            [_textview keyDown:event];
            return YES;
        }
    } else {
        return NO;
    }
}

#pragma mark - Scripting Support

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSUInteger theIndex = 0;
    id classDescription = nil;

    NSScriptObjectSpecifier *containerRef = nil;
    if (![[self tab] realParentWindow]) {
        // TODO(georgen): scripting is broken while in instant replay.
        return nil;
    }
    // TODO: Test this with multiple panes per tab.
    theIndex = [[[[self tab] realParentWindow] tabView] indexOfTabViewItem:[[self tab] tabViewItem]];

    if (theIndex != NSNotFound) {
        containerRef = [[[self tab] realParentWindow] objectSpecifier];
        classDescription = [containerRef keyClassDescription];
        //create and return the specifier
        return [[[NSIndexSpecifier allocWithZone:[self zone]]
               initWithContainerClassDescription:classDescription
                              containerSpecifier:containerRef
                                             key:@ "sessions"
                                           index:theIndex] autorelease];
    } else {
        // NSLog(@"recipient not found!");
        return nil;
    }
}

// Handlers for supported commands:
- (void)handleExecScriptCommand:(NSScriptCommand *)aCommand
{
    // if we are already doing something, get out.
    if ([_shell pid] > 0) {
        NSBeep();
        return;
    }

    // Get the command's arguments:
    NSDictionary *args = [aCommand evaluatedArguments];
    NSString *command = [args objectForKey:@"command"];
    BOOL isUTF8 = [[args objectForKey:@"isUTF8"] boolValue];

    NSString *cmd;
    NSArray *arg;

    [command breakDownCommandToPath:&cmd cmdArgs:&arg];
    [self startProgram:cmd arguments:arg environment:[NSDictionary dictionary] isUTF8:isUTF8];

    return;
}

- (void)handleSelectScriptCommand:(NSScriptCommand *)command
{
    [[[[self tab] parentWindow] tabView] selectTabViewItemWithIdentifier:[self tab]];
}

- (void)handleClearScriptCommand:(NSScriptCommand *)command
{
    [self clearBuffer];
}

- (void)handleWriteScriptCommand:(NSScriptCommand *)command
{
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    // optional argument follows (might be nil):
    NSString *contentsOfFile = [args objectForKey:@"contentsOfFile"];
    // optional argument follows (might be nil):
    NSString *text = [args objectForKey:@"text"];
    NSData *data = nil;
    NSString *aString = nil;

    if (text != nil) {
        if ([text characterAtIndex:[text length]-1]==' ') {
            data = [text dataUsingEncoding:[_terminal encoding]];
        } else {
            aString = [NSString stringWithFormat:@"%@\n", text];
            data = [aString dataUsingEncoding:[_terminal encoding]];
        }
    }

    if (contentsOfFile != nil) {
        aString = [NSString stringWithContentsOfFile:contentsOfFile
                                            encoding:NSUTF8StringEncoding
                                               error:nil];
        data = [aString dataUsingEncoding:[_terminal encoding]];
    }

    if (self.tmuxMode == TMUX_CLIENT) {
        [self writeTask:data];
    } else if (data != nil && [_shell pid] > 0) {
        int i = 0;
        // wait here until we have had some output
        while ([_shell hasOutput] == NO && i < 1000000) {
            usleep(50000);
            i += 50000;
        }

        [self writeTask:data];
    }
}

- (void)handleTerminateScriptCommand:(NSScriptCommand *)command
{
    [[self tab] closeSession:self];
}

- (NSColor *)backgroundColor {
    return [_colorMap colorForKey:kColorMapBackground];
}

- (void)setBackgroundColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapBackground];
}

- (NSColor *)boldColor {
    return [_colorMap colorForKey:kColorMapBold];
}

- (void)setBoldColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapBold];
}

- (NSColor *)cursorColor {
    return [_colorMap colorForKey:kColorMapCursor];
}

- (void)setCursorColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapCursor];
}

- (NSColor *)cursorTextColor {
    return [_colorMap colorForKey:kColorMapCursorText];
}

- (void)setCursorTextColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapCursorText];
}

- (NSColor *)foregroundColor {
    return [_colorMap colorForKey:kColorMapForeground];
}

- (void)setForegroundColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapForeground];
}

- (NSColor *)selectedTextColor {
    return [_colorMap colorForKey:kColorMapSelectedText];
}

- (void)setSelectedTextColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapSelectedText];
}

- (NSColor *)selectionColor {
    return [_colorMap colorForKey:kColorMapSelection];
}

- (void)setSelectionColor:(NSColor *)color {
    [_colorMap setColor:color forKey:kColorMapSelection];
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

@end
