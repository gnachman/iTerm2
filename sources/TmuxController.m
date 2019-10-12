//
//  TmuxController.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxController.h"
#import "DebugLogging.h"
#import "EquivalenceClassSet.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermInitialDirectory.h"
#import "iTermInitialDirectory+Tmux.h"
#import "iTermLSOF.h"
#import "iTermNotificationController.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermShortcut.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "RegexKitLite.h"
#import "TmuxControllerRegistry.h"
#import "TmuxDashboardController.h"
#import "TmuxGateway.h"
#import "TmuxWindowOpener.h"
#import "TSVParser.h"

NSString *const kTmuxControllerSessionsDidChange = @"kTmuxControllerSessionsDidChange";
NSString *const kTmuxControllerDetachedNotification = @"kTmuxControllerDetachedNotification";
NSString *const kTmuxControllerWindowsChangeNotification = @"kTmuxControllerWindowsChangeNotification";
NSString *const kTmuxControllerWindowWasRenamed = @"kTmuxControllerWindowWasRenamed";
NSString *const kTmuxControllerWindowDidOpen = @"kTmuxControllerWindowDidOpen";
NSString *const kTmuxControllerAttachedSessionDidChange = @"kTmuxControllerAttachedSessionDidChange";
NSString *const kTmuxControllerWindowDidClose = @"kTmuxControllerWindowDidClose";
NSString *const kTmuxControllerSessionWasRenamed = @"kTmuxControllerSessionWasRenamed";
NSString *const kTmuxControllerDidFetchSetTitlesStringOption = @"kTmuxControllerDidFetchSetTitlesStringOption";

static NSString *const iTermTmuxControllerEncodingPrefixHotkeys = @"h_";
static NSString *const iTermTmuxControllerEncodingPrefixTabColors = @"t_";
static NSString *const iTermTmuxControllerEncodingPrefixAffinities = @"a_";
static NSString *const iTermTmuxControllerEncodingPrefixOrigins = @"o_";
static NSString *const iTermTmuxControllerEncodingPrefixHidden = @"i_";

// Unsupported global options:
static NSString *const kAggressiveResize = @"aggressive-resize";

static NSString *kListWindowsFormat = @"\"#{session_name}\t#{window_id}\t"
    "#{window_name}\t"
    "#{window_width}\t#{window_height}\t"
    "#{window_layout}\t"
    "#{window_flags}\t"
    "#{?window_active,1,0}\"";

@interface TmuxController ()

@property(nonatomic, copy) NSString *clientName;
@property(nonatomic, copy, readwrite) NSString *sessionGuid;

@end

@interface iTermTmuxWindowState : NSObject
@property (nonatomic, strong) PTYTab *tab;
@property (nonatomic) NSInteger refcount;
@property (nonatomic, strong) Profile *profile;
@property (nonatomic, strong) NSDictionary *fontOverrides;
@end

@implementation iTermTmuxWindowState

- (void)dealloc {
    [_tab release];
    [_profile release];
    [_fontOverrides release];
    [super dealloc];
}

@end

@implementation TmuxController {
    TmuxGateway *gateway_;
    NSMutableDictionary *windowPanes_;  // paneId -> PTYSession *
    NSMutableDictionary<NSNumber *, iTermTmuxWindowState *> *_windowStates;      // Key is window number
    NSArray<iTermTmuxSessionObject *> *sessionObjects_;
    int numOutstandingWindowResizes_;
    NSMutableDictionary *windowPositions_;
    NSSize lastSize_;  // last size for windowDidChange:
    NSString *lastOrigins_;
    BOOL detached_;
    NSString *sessionName_;
    int sessionId_;
    NSMutableSet *pendingWindowOpens_;
    NSString *lastSaveAffinityCommand_;
    // tmux windows that want to open as tabs in the same physical window
    // belong to the same equivalence class.
    EquivalenceClassSet *affinities_;
    BOOL windowOriginsDirty_;
    BOOL haveOutstandingSaveWindowOrigins_;
    NSMutableDictionary *origins_;  // window id -> NSValue(Point) window origin
    NSMutableSet<NSNumber *> *hiddenWindows_;
    NSTimer *listSessionsTimer_;  // Used to do a cancelable delayed perform of listSessions.
    NSTimer *listWindowsTimer_;  // Used to do a cancelable delayed perform of listWindows.
    BOOL ambiguousIsDoubleWidth_;
    NSMutableDictionary<NSNumber *, NSDictionary *> *_hotkeys;
    NSMutableSet<NSNumber *> *_paneIDs;  // existing pane IDs
    NSMutableDictionary<NSNumber *, NSString *> *_tabColors;

    // Maps a window id string to a dictionary of window flags defined by TmuxWindowOpener (see the
    // top of its header file)
    NSMutableDictionary *_windowOpenerOptions;
    BOOL _manualOpenRequested;
    BOOL _haveOpenedInitialWindows;
    ProfileModel *_profileModel;
    // Maps the window ID of an about to be opened window to a completion block to invoke when it opens.
    NSMutableDictionary<NSNumber *, void(^)(int)> *_pendingWindows;
    BOOL _hasStatusBar;
}

@synthesize gateway = gateway_;
@synthesize windowPositions = windowPositions_;
@synthesize sessionName = sessionName_;
@synthesize sessionObjects = sessionObjects_;
@synthesize ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
@synthesize sessionId = sessionId_;

static NSDictionary *iTermTmuxControllerDefaultFontOverridesFromProfile(Profile *profile) {
    return @{ KEY_NORMAL_FONT: [iTermProfilePreferences stringForKey:KEY_NORMAL_FONT inProfile:profile],
              KEY_NON_ASCII_FONT: [iTermProfilePreferences stringForKey:KEY_NON_ASCII_FONT inProfile:profile],
              KEY_HORIZONTAL_SPACING: [iTermProfilePreferences objectForKey:KEY_HORIZONTAL_SPACING inProfile:profile],
              KEY_VERTICAL_SPACING: [iTermProfilePreferences objectForKey:KEY_VERTICAL_SPACING inProfile:profile] };
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway
                     clientName:(NSString *)clientName
                        profile:(NSDictionary *)profile
                   profileModel:(ProfileModel *)profileModel {
    self = [super init];
    if (self) {
        _sharedProfile = [profile copy];
        _profileModel = [profileModel retain];
        _sharedFontOverrides = [iTermTmuxControllerDefaultFontOverridesFromProfile(profile) retain];

        gateway_ = [gateway retain];
        _paneIDs = [[NSMutableSet alloc] init];
        windowPanes_ = [[NSMutableDictionary alloc] init];
        _windowStates = [[NSMutableDictionary alloc] init];
        windowPositions_ = [[NSMutableDictionary alloc] init];
        origins_ = [[NSMutableDictionary alloc] init];
        pendingWindowOpens_ = [[NSMutableSet alloc] init];
        hiddenWindows_ = [[NSMutableSet alloc] init];
        _hotkeys = [[NSMutableDictionary alloc] init];
        _tabColors = [[NSMutableDictionary alloc] init];
        self.clientName = [[TmuxControllerRegistry sharedInstance] uniqueClientNameBasedOn:clientName];
        _windowOpenerOptions = [[NSMutableDictionary alloc] init];
        _pendingWindows = [[NSMutableDictionary alloc] init];
        [[TmuxControllerRegistry sharedInstance] setController:self forClient:_clientName];
    }
    return self;
}

- (void)dealloc {
    [_clientName release];
    [_paneIDs release];
    [gateway_ release];
    [windowPanes_ release];
    [_windowStates release];
    [windowPositions_ release];
    [origins_ release];
    [pendingWindowOpens_ release];
    [affinities_ release];
    [lastSaveAffinityCommand_ release];
    [hiddenWindows_ release];
    [lastOrigins_ release];
    [_sessionGuid release];
    [_windowOpenerOptions release];
    [_hotkeys release];
    [_tabColors release];
    [_sharedProfile release];
    [_profileModel release];
    [_sharedFontOverrides release];
    [_pendingWindows release];
    [sessionName_ release];
    [sessionObjects_ release];

    [super dealloc];
}

- (Profile *)profileForWindow:(int)window {
    if (!_variableWindowSize) {
        return [self sharedProfile];
    }
    Profile *original = _windowStates[@(window)].profile;
    if (!original) {
        return [self sharedProfile];
    }
    NSMutableDictionary *temp = [[original mutableCopy] autorelease];
    [temp it_mergeFrom:_windowStates[@(window)].fontOverrides];
    return temp;
}

- (NSDictionary *)fontOverridesForWindow:(int)window {
    if (!_variableWindowSize) {
        return [self sharedFontOverrides];
    }
    return _windowStates[@(window)].fontOverrides ?: self.sharedFontOverrides;
}

- (NSDictionary *)sharedProfile {
    Profile *profile = [_profileModel bookmarkWithGuid:_sharedProfile[KEY_GUID]] ?: _sharedProfile;
    NSMutableDictionary *temp = [profile mutableCopy];
    [_sharedFontOverrides enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        temp[key] = obj;
    }];
    return [temp autorelease];
}

// Called when listing window finishes. Happens for all new windows/tabs, whether initiated by iTerm2 or not.
- (void)openWindowWithIndex:(int)windowIndex
                       name:(NSString *)name
                       size:(NSSize)size
                     layout:(NSString *)layout
                 affinities:(NSSet *)affinities
                windowFlags:(NSString *)windowFlags
                    profile:(Profile *)profile
                    initial:(BOOL)initial {
    DLog(@"openWindowWithIndex:%d name:%@ affinities:%@ flags:%@ initial:%@",
         windowIndex, name, affinities, windowFlags, @(initial));
    NSNumber *n = [NSNumber numberWithInt:windowIndex];
    if ([pendingWindowOpens_ containsObject:n]) {
        return;
    }
    for (NSString *a in affinities) {
        [affinities_ setValue:a
                 equalToValue:[NSString stringWithInt:windowIndex]];
    }
    [pendingWindowOpens_ addObject:n];
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
    windowOpener.unicodeVersion = self.unicodeVersion;
    windowOpener.windowIndex = windowIndex;
    windowOpener.name = name;
    windowOpener.size = size;
    windowOpener.layout = layout;
    windowOpener.maxHistory =
        MAX([[gateway_ delegate] tmuxClientSize].height,
            [[gateway_ delegate] tmuxNumberOfLinesOfScrollbackHistory]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    windowOpener.windowOptions = _windowOpenerOptions;
    windowOpener.zoomed = windowFlags ? @([windowFlags containsString:@"Z"]) : nil;
    windowOpener.manuallyOpened = _manualOpenRequested;
    windowOpener.tabColors = _tabColors;
    windowOpener.profile = profile;
    windowOpener.initial = initial || !_pendingWindows[@(windowIndex)];
    windowOpener.completion = _pendingWindows[@(windowIndex)];
    [_pendingWindows removeObjectForKey:@(windowIndex)];
    _manualOpenRequested = NO;
    if (![windowOpener openWindows:YES]) {
        [pendingWindowOpens_ removeObject:n];
    }
}

- (void)setLayoutInTab:(PTYTab *)tab
              toLayout:(NSString *)layout
                zoomed:(NSNumber *)zoomed {
    DLog(@"setLayoutInTab:%@ toLayout:%@ zoomed:%@", tab, layout, zoomed);
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
    windowOpener.unicodeVersion = self.unicodeVersion;
    windowOpener.layout = layout;
    windowOpener.maxHistory =
        MAX([[gateway_ delegate] tmuxClientSize].height,
            [[gateway_ delegate] tmuxNumberOfLinesOfScrollbackHistory]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.windowIndex = [tab tmuxWindow];
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    windowOpener.windowOptions = _windowOpenerOptions;
    windowOpener.zoomed = zoomed;
    windowOpener.tabColors = _tabColors;
    windowOpener.profile = [self profileForWindow:tab.tmuxWindow];
    [windowOpener updateLayoutInTab:tab];
}

- (void)sessionChangedTo:(NSString *)newSessionName sessionId:(int)sessionid {
    self.sessionGuid = nil;
    self.sessionName = newSessionName;
    sessionId_ = sessionid;
    _detaching = YES;
    [self closeAllPanes];
    _detaching = NO;
    [self openWindowsInitial];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerAttachedSessionDidChange
                                                        object:nil];
}

- (void)sessionsChanged
{
    if (detached_) {
        // Shouldn't happen, but better safe than sorry.
        return;
    }
    // Wait a few seconds. We always get a sessions-changed notification when the last window in
    // a session closes. To avoid spamming the command line with list-sessions, we wait a bit to see
    // if there is an exit notification coming down the pipe.
    const CGFloat kListSessionsDelay = 1.5;
    [listSessionsTimer_ invalidate];
    listSessionsTimer_ = [NSTimer scheduledTimerWithTimeInterval:kListSessionsDelay
                                                          target:self
                                                        selector:@selector(listSessions)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)session:(int)sessionId renamedTo:(NSString *)newName
{
    if (sessionId == sessionId_) {
        self.sessionName = newName;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionWasRenamed
                                                        object:[NSArray arrayWithObjects:
                                                                [NSNumber numberWithInt:sessionId],
                                                                newName,
                                                                nil]];
}

- (void)windowWasRenamedWithId:(int)wid to:(NSString *)newName
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowWasRenamed
                                                        object:[NSArray arrayWithObjects:
                                                                [NSNumber numberWithInt:wid],
                                                                newName,
                                                                nil]];
}

- (void)windowsChanged
{
    [[NSNotificationCenter defaultCenter]  postNotificationName:kTmuxControllerWindowsChangeNotification
                                                         object:self];
}

- (NSArray *)listWindowFields
{
    return [NSArray arrayWithObjects:@"session_name", @"window_id",
            @"window_name", @"window_width", @"window_height",
            @"window_layout", @"window_flags", @"window_active", nil];

}

- (NSSet<NSObject<NSCopying> *> *)savedAffinitiesForWindow:(NSString *)value {
    return [affinities_ valuesEqualTo:value];
}

- (void)initialListWindowsResponse:(NSString *)response {
    DLog(@"initialListWindowsResponse called");
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        DLog(@"Failed to parse %@", response);
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for initial list windows request: %@", response]];
        return;
    }
    NSMutableArray *windowsToOpen = [NSMutableArray array];
    BOOL haveHidden = NO;
    NSNumber *newWindowAffinity = nil;
    BOOL newWindowsInTabs =
        [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn] == kOpenTmuxWindowsAsNativeTabsInNewWindow;
    DLog(@"Iterating records...");
    for (NSArray *record in doc.records) {
        DLog(@"Consider record %@", record);
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        if (hiddenWindows_ && [hiddenWindows_ containsObject:[NSNumber numberWithInt:wid]]) {
            XLog(@"Don't open window %d because it was saved hidden.", wid);
            haveHidden = YES;
            // Let the user know something is up.
            continue;
        }
        NSNumber *n = [NSNumber numberWithInt:wid];
        if (![affinities_ valuesEqualTo:[n stringValue]] && newWindowsInTabs) {
            // Create an equivalence class of all unrecognied windows to each other.
            if (!newWindowAffinity) {
                DLog(@"Create new affinity class for %@", n);
                newWindowAffinity = n;
            } else {
                DLog(@"Add window id %@ to existing affinity class %@", n, [newWindowAffinity stringValue]);
                [affinities_ setValue:[n stringValue]
                         equalToValue:[newWindowAffinity stringValue]];
            }
        }
        [windowsToOpen addObject:record];
    }
    BOOL tooMany = NO;
    if (windowsToOpen.count > [iTermPreferences intForKey:kPreferenceKeyTmuxDashboardLimit]) {
        DLog(@"There are too many windows to open so just show the dashboard");
        haveHidden = YES;
        tooMany = YES;
        [windowsToOpen removeAllObjects];
    }
    if (haveHidden) {
        DLog(@"Hidden windows existing, showing dashboard");
        [[TmuxDashboardController sharedInstance] showWindow:nil];
        [[[TmuxDashboardController sharedInstance] window] makeKeyAndOrderFront:nil];
        if (tooMany) {
            [[iTermNotificationController sharedInstance] notify:@"Too many tmux windows!" withDescription:@"Use the tmux dashboard to select which to open."];
        } else {
            [[iTermNotificationController sharedInstance] notify:@"Some tmux windows were hidden." withDescription:@"Use the tmux dashboard to select which to open."];
        }
    }
    for (NSArray *record in windowsToOpen) {
        DLog(@"Open window %@", record);
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        [self openWindowWithIndex:wid
                             name:[[doc valueInRecord:record forField:@"window_name"] it_unescapedTmuxWindowName]
                             size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                             [[doc valueInRecord:record forField:@"window_height"] intValue])
                           layout:[doc valueInRecord:record forField:@"window_layout"]
                       affinities:[self savedAffinitiesForWindow:[NSString stringWithInt:wid]]
                      windowFlags:[doc valueInRecord:record forField:@"window_flags"]
#warning TODO: Save profiles in the tmux server
                          profile:[self sharedProfile]
                          initial:YES];
    }
    if (windowsToOpen.count == 0) {
        DLog(@"Did not open any windows so turn on accept notifications in tmux gateway");
        gateway_.acceptNotifications = YES;
        [self sendInitialWindowsOpenedNotificationIfNeeded];
    }
}

- (void)openWindowsInitial {
    NSString *command = [NSString stringWithFormat:@"show -v -q -t $%d @iterm2_size", sessionId_];
    [gateway_ sendCommand:command
           responseTarget:self
         responseSelector:@selector(handleShowSize:)];
}

- (void)handleShowSize:(NSString *)response {
    NSScanner *scanner = [NSScanner scannerWithString:response ?: @""];
    int width = 0;
    int height = 0;
    BOOL ok = ([scanner scanInt:&width] &&
               [scanner scanString:@"," intoString:nil] &&
               [scanner scanInt:&height]);
    if (ok) {
        [self openWindowsOfSize:VT100GridSizeMake(width, height)];
    } else {
        [self openWindowsOfSize:[[gateway_ delegate] tmuxClientSize]];
    }
}

- (void)openWindowsOfSize:(VT100GridSize)size {
    // There's a (hopefully) minor race condition here. When we initially connect to
    // a session we get its @iterm2_id. If one doesn't exist, it is assigned. This
    // lets us know if a single instance of iTerm2 is trying to attach to the same
    // session twice. A really evil user could attach twice to the same session
    // simultaneously, and we'd get the value twice, see it's empty twice, and set
    // it twice, causing chaos. Or two separate instances of iTerm2 attaching
    // simultaneously could also hit this race. The consequence of this race
    // condition is easily recovered from by reattaching.
    NSString *getSessionGuidCommand = [NSString stringWithFormat:@"show -v -q -t $%d @iterm2_id",
                                       sessionId_];
    NSString *setSizeCommand = [NSString stringWithFormat:@"refresh-client -C %d,%d",
                                size.width, [self adjustHeightForStatusBar:size.height]];
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@", kListWindowsFormat];
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_id} #{session_name}\"";
    NSString *getAffinitiesCommand = [NSString stringWithFormat:@"show -v -q -t $%d @affinities", sessionId_];
    NSString *getOriginsCommand = [NSString stringWithFormat:@"show -v -q -t $%d @origins", sessionId_];
    NSString *getHotkeysCommand = [NSString stringWithFormat:@"show -v -q -t $%d @hotkeys", sessionId_];
    NSString *getTabColorsCommand = [NSString stringWithFormat:@"show -v -q -t $%d @tab_colors", sessionId_];
    NSString *getHiddenWindowsCommand = [NSString stringWithFormat:@"show -v -q -t $%d @hidden", sessionId_];
    NSArray *commands = @[ [gateway_ dictionaryForCommand:getSessionGuidCommand
                                           responseTarget:self
                                         responseSelector:@selector(getSessionGuidResponse:)
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:setSizeCommand
                                           responseTarget:nil
                                         responseSelector:nil
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:getHiddenWindowsCommand
                                           responseTarget:self
                                         responseSelector:@selector(getHiddenWindowsResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getAffinitiesCommand
                                           responseTarget:self
                                         responseSelector:@selector(getAffinitiesResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getOriginsCommand
                                           responseTarget:self
                                         responseSelector:@selector(getOriginsResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getHotkeysCommand
                                           responseTarget:self
                                         responseSelector:@selector(getHotkeysResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getTabColorsCommand
                                           responseTarget:self
                                         responseSelector:@selector(getTabColorsResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:listSessionsCommand
                                           responseTarget:self
                                         responseSelector:@selector(listSessionsResponse:)
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:listWindowsCommand
                                           responseTarget:self
                                         responseSelector:@selector(initialListWindowsResponse:)
                                           responseObject:nil
                                                    flags:0] ];
    [gateway_ sendCommandList:commands];
}

// Returns the mutable set of session GUIDs we're attached to.
- (NSMutableSet *)attachedSessionGuids {
    static NSMutableSet *gAttachedSessionGuids;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gAttachedSessionGuids = [[NSMutableSet alloc] init];
    });
    return gAttachedSessionGuids;
}

// Sets the current controller's session guid and updates the global set of attached session GUIDs.
// If guid is nil then it is removed from the global set.
- (void)setSessionGuid:(NSString *)guid {
    if (guid) {
        [self.attachedSessionGuids addObject:guid];
    } else if (_sessionGuid) {
        [self.attachedSessionGuids removeObject:_sessionGuid];
    }
    [_sessionGuid autorelease];
    _sessionGuid = [guid copy];
}

// This is where the race condition described in openWindowsInitial occurs.
- (void)getSessionGuidResponse:(NSString *)sessionGuid {
    if (!sessionGuid.length) {
        NSString *guid = [NSString uuid];
        NSString *command = [NSString stringWithFormat:@"set -t $%d @iterm2_id \"%@\"",
                             sessionId_, guid];
        [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
        self.sessionGuid = guid;
    } else if ([self.attachedSessionGuids containsObject:sessionGuid]) {
        [self.gateway doubleAttachDetectedForSessionGUID:sessionGuid];
    } else {
        self.sessionGuid = sessionGuid;
    }
}

- (NSNumber *)_keyForWindowPane:(int)windowPane
{
    return [NSNumber numberWithInt:windowPane];
}

- (PTYSession *)sessionForWindowPane:(int)windowPane
{
    return [windowPanes_ objectForKey:[self _keyForWindowPane:windowPane]];
}

- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window {
    PTYTab *tab = [aSession.delegate.realParentWindow tabForSession:aSession];
    ITCriticalError(tab != nil, @"nil tab for session %@ with delegate %@ with realparentwindow %@",
                    aSession, aSession.delegate, aSession.delegate.realParentWindow);
    if (tab) {
        [self retainWindow:window withTab:tab];
        [windowPanes_ setObject:aSession forKey:[self _keyForWindowPane:windowPane]];
    }
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane session:(id)session
{
    id key = [self _keyForWindowPane:windowPane];
    if (windowPanes_[key] == session) {
        [self releaseWindow:window];
        [windowPanes_ removeObjectForKey:key];
    }
}

- (PTYTab *)window:(int)window {
    return _windowStates[@(window)].tab;
}

- (NSArray<PTYSession *> *)sessionsInWindow:(int)window {
    return [[self window:window] sessions];
}

- (BOOL)isAttached
{
    return !detached_;
}

- (void)requestDetach
{
    [self.gateway detach];
}

- (void)detach {
    self.sessionGuid = nil;
    [listSessionsTimer_ invalidate];
    listSessionsTimer_ = nil;
    [listWindowsTimer_ invalidate];
    listWindowsTimer_ = nil;
    detached_ = YES;
    [self closeAllPanes];
    [gateway_ release];
    gateway_ = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDetachedNotification
                                                        object:self];
    [[TmuxControllerRegistry sharedInstance] setController:nil
                                                 forClient:self.clientName];
}

- (void)windowDidResize:(NSWindowController<iTermWindowController> *)term {
    if (_variableWindowSize) {
        [self variableSizeWindowDidResize:term];
        return;
    }
    NSSize size = [term tmuxCompatibleSize];
    DLog(@"The tmux-compatible size of the window is %@", NSStringFromSize(size));
    if (size.width <= 0 || size.height <= 0) {
        // After the last session closes a size of 0 is reported.
        return;
    }
    DLog(@"The last known size of tmux windows is %@", NSStringFromSize(lastSize_));
    if (NSEqualSizes(size, lastSize_)) {
        return;
    }

    DLog(@"Looks like the window resize is legit. Change client size to %@", NSStringFromSize(size));
    [self setClientSize:size];
}

- (void)variableSizeWindowDidResize:(NSWindowController<iTermWindowController> *)term {
    DLog(@"Window %@ did resize. Updating tmux tabs", term);
    [self setWindowSizes:[term.tabs mapWithBlock:^iTermTuple<NSString *, NSValue *> *(PTYTab *tab) {
        if (!tab.tmuxTab || tab.tmuxController != self) {
            return nil;
        }
        return [iTermTuple tupleWithObject:[NSString stringWithInt:tab.tmuxWindow]
                                 andObject:[NSValue valueWithSize:tab.tmuxSize]];
    }]];
}

- (NSSize)sizeOfSmallestWindowAmong:(NSSet<NSString *> *)siblings {
    NSSize minSize = NSMakeSize(INFINITY, INFINITY);
    for (NSString *windowKey in siblings) {
        if ([windowKey hasPrefix:@"pty"]) {
            continue;
        }
        PTYTab *tab = [self window:windowKey.intValue];
        NSSize size = [tab tmuxSize];
        minSize.width = MIN(minSize.width, size.width);
        minSize.height = MIN(minSize.height, size.height);
    }
    return minSize;
}

- (void)fitLayoutToWindows {
    if (!_windowStates.count) {
        return;
    }
    if (_variableWindowSize) {
        [self fitLayoutToVariableSizeWindows];
        return;
    }
    NSSize minSize = NSMakeSize(INFINITY, INFINITY);
    for (NSNumber *windowKey in _windowStates) {
        PTYTab *tab = _windowStates[windowKey].tab;
        NSSize size = [tab tmuxSize];
        minSize.width = MIN(minSize.width, size.width);
        minSize.height = MIN(minSize.height, size.height);
    }
    if (minSize.width <= 0 || minSize.height <= 0) {
        // After the last session closes a size of 0 is reported. Apparently unplugging a monitor
        // leads to a negative value here. That's inferred from crash report 1468853197.309853926.txt
        // (at the time of that crash, this tested only for zero values so it passed through and
        // asserted anyway).
        return;
    }
    if (NSEqualSizes(minSize, lastSize_)) {
        return;
    }
    DLog(@"fitLayoutToWindows setting client size to %@", NSStringFromSize(minSize));
    [self setClientSize:minSize];
}

- (void)fitLayoutToVariableSizeWindows {
    [self setWindowSizes:[_windowStates.allKeys mapWithBlock:^iTermTuple<NSString *, NSValue *> *(NSNumber *windowNumber) {
        iTermTmuxWindowState *state = _windowStates[windowNumber];
        PTYTab *tab = state.tab;
        return [iTermTuple tupleWithObject:[NSString stringWithInt:windowNumber.intValue]
                                 andObject:[NSValue valueWithSize:tab.tmuxSize]];
    }]];
}

- (void)setSize:(NSSize)size window:(int)window {
    if (!_variableWindowSize) {
        [self setClientSize:size];
        return;
    }
    [gateway_ sendCommandList:[self commandListToSetSize:size ofWindow:window]];
}

- (NSArray<NSDictionary *> *)commandListToSetSize:(NSSize)size ofWindow:(int)window {
    NSSet *siblings = [affinities_ valuesEqualTo:[@(window) stringValue]];
    if (!siblings.count) {
        return [self commandListToSetSize:size ofWindows:@[ [NSString stringWithInt:window] ]];
    } else {
        return [self commandListToSetSize:size ofWindows:siblings.allObjects];
    }
}

- (void)setWindowSizes:(NSArray<iTermTuple<NSString *, NSValue *> *> *)windowSizes {
    [gateway_ sendCommandList:[self commandListToSetWindowSizes:windowSizes]];
}

- (NSArray<NSDictionary *> *)commandListToSetWindowSizes:(NSArray<iTermTuple<NSString *, NSValue *> *> *)windowSizes {
    return [windowSizes mapWithBlock:^NSDictionary *(iTermTuple<NSString *,NSValue *> *tuple) {
        NSString *window = tuple.firstObject;
        NSSize size = tuple.secondObject.sizeValue;
        if ([window hasPrefix:@"pty"] || [window hasSuffix:@"_ph"]) {
            return nil;
        }
        // 10000 comes from WINDOW_MAXIMUM in tmux.h
        if (size.width < 1 || size.height < 1 || size.width >= 10000 || size.height >= 10000) {
            return nil;
        }
        NSString *command = [NSString stringWithFormat:@"resize-window -x %@ -y %@ -t @%d", @((int)size.width), @((int)size.height), window.intValue];
        NSDictionary *dict = [gateway_ dictionaryForCommand:command
                                             responseTarget:self
                                           responseSelector:@selector(handleResizeWindowResponse:)
                                             responseObject:nil
                                                      flags:0];
        return dict;
    }];
}

- (NSArray<NSDictionary *> *)commandListToSetSize:(NSSize)size ofWindows:(NSArray<NSString *> *)windows {
    return [self commandListToSetWindowSizes:[windows mapWithBlock:^iTermTuple<NSString *, NSValue *> *(NSString *window) {
        return [iTermTuple tupleWithObject:window andObject:[NSValue valueWithSize:size]];
    }]];
}

- (void)handleResizeWindowResponse:(NSString *)response {
}

- (int)adjustHeightForStatusBar:(int)height {
    // See here for the bug fix: https://github.com/tmux/tmux/pull/1731
    NSArray *buggyVersions = @[ [NSDecimalNumber decimalNumberWithString:@"2.9"],
                                [NSDecimalNumber decimalNumberWithString:@"2.91"] ];
    if (_hasStatusBar && [buggyVersions containsObject:gateway_.minimumServerVersion]) {
        return height + 1;
    }
    return height;
}

- (void)setClientSize:(NSSize)size {
    DLog(@"Set client size to %@", NSStringFromSize(size));
    DLog(@"%@", [NSThread callStackSymbols]);
    assert(size.width > 0 && size.height > 0);
    lastSize_ = size;
    NSString *listStr = [NSString stringWithFormat:@"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\""];
    NSString *setSizeCommand = [NSString stringWithFormat:@"set -t $%d @iterm2_size %d,%d",
                                sessionId_, (int)size.width, (int)size.height];
    NSArray *commands = [NSArray arrayWithObjects:
                         [gateway_ dictionaryForCommand:setSizeCommand
                                         responseTarget:nil
                                       responseSelector:nil
                                         responseObject:nil
                                                  flags:0],
                         [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"refresh-client -C %d,%d",
                                                         (int)size.width, [self adjustHeightForStatusBar:(int)size.height]]
                                         responseTarget:nil
                                       responseSelector:nil
                                         responseObject:nil
                                                  flags:0],
                         [gateway_ dictionaryForCommand:listStr
                                         responseTarget:self
                                       responseSelector:@selector(listWindowsResponse:)
                                         responseObject:nil
                                                  flags:0],
                         nil];
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommandList:commands];
}

- (void)ping {
    [gateway_ sendCommand:@"display-message -p -F ."
           responseTarget:self
         responseSelector:@selector(handlePingResponse:)
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)handlePingResponse:(NSString *)ignore {
}

// Make sure that current tmux options are compatible with iTerm.
- (void)validateOptions
{
    for (NSString *option in [self unsupportedGlobalOptions]) {
        [gateway_ sendCommand:[NSString stringWithFormat:@"show-window-options -g %@", option]
               responseTarget:self
             responseSelector:@selector(showWindowOptionsResponse:)];
    }
    [gateway_ sendCommand:@"show-option -g -v status"
           responseTarget:self
         responseSelector:@selector(handleStatusResponse:)];
}

- (void)handleStatusResponse:(NSString *)string {
    _hasStatusBar = [string isEqualToString:@"on"];
}

- (void)checkForUTF8 {
    // Issue 5359
    [gateway_ sendCommand:@"list-sessions -F \"\t\""
           responseTarget:self
         responseSelector:@selector(checkForUTF8Response:)
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)clearHistoryForWindowPane:(int)windowPane {
    [gateway_ sendCommand:[NSString stringWithFormat:@"clear-history -t \"%%%d\"", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)loadServerPID {
    if (gateway_.minimumServerVersion.doubleValue < 2.1) {
        return;
    }
    [gateway_ sendCommand:@"display-message -p \"#{pid}\""
           responseTarget:self
         responseSelector:@selector(didLoadServerPID:)];
}

- (void)didLoadServerPID:(NSString *)pidString {
    pid_t pid = [pidString integerValue];
    if (pid > 0) {
        NSString *name = [iTermLSOF nameOfProcessWithPid:pid isForeground:NULL];
        _serverIsLocal = [name isEqualToString:@"tmux"];
    }
}

- (void)loadTitleFormat {
    [gateway_ sendCommandList:@[ [gateway_ dictionaryForCommand:@"show-options -v -g set-titles"
                                                 responseTarget:self
                                               responseSelector:@selector(handleShowSetTitles:)
                                                 responseObject:nil
                                                          flags:0] ]];
}

- (void)handleShowSetTitles:(NSString *)result {
    _shouldSetTitles = [result isEqualToString:@"on"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDidFetchSetTitlesStringOption
                                                        object:self];
}

- (void)guessVersion {
    // Run commands that will fail in successively older versions.
    // show-window-options pane-border-format will succeed in 2.3 and later (presumably. 2.3 isn't out yet)
    // the socket_path format was added in 2.2.
    // the session_activity format was added in 2.1
    NSArray *commands = @[ [gateway_ dictionaryForCommand:@"display-message -p \"#{version}\""
                                           responseTarget:self
                                         responseSelector:@selector(handleDisplayMessageVersion:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],

                           [gateway_ dictionaryForCommand:@"show-window-options pane-border-format"
                                           responseTarget:self
                                         responseSelector:@selector(guessVersion23Response:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:@"list-windows -F \"#{socket_path}\""
                                           responseTarget:self
                                         responseSelector:@selector(guessVersion22Response:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:@"list-windows -F \"#{session_activity}\""
                                           responseTarget:self
                                         responseSelector:@selector(guessVersion21Response:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:@"list-clients -F \"#{client_cwd}\""  // client_cwd was deprecated in 1.9
                                           responseTarget:self
                                         responseSelector:@selector(guessVersion18Response:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors]
                           ];
    for (NSDictionary *command in commands) {
        [gateway_ sendCommandList:@[ command ]];
    }
}

- (void)decreaseMaximumServerVersionTo:(NSString *)string {
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:string];
    if (!gateway_.maximumServerVersion ||
        [gateway_.maximumServerVersion compare:number] == NSOrderedDescending) {
        gateway_.maximumServerVersion = number;
        DLog(@"Decreasing maximum server version to %@", number);
    }
}

- (void)increaseMinimumServerVersionTo:(NSString *)string {
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:string];
    if (!gateway_.minimumServerVersion ||
        [gateway_.minimumServerVersion compare:number] == NSOrderedAscending) {
        gateway_.minimumServerVersion = number;
        DLog(@"Increasing minimum server version to %@", number);
    }
}

- (void)checkForUTF8Response:(NSString *)response {
    if ([response containsString:@"_"]) {
        [gateway_ abortWithErrorMessage:@"tmux is not in UTF-8 mode. Please pass the -u command line argument to tmux or change your LANG environment variable to end with “.UTF-8”."
                                  title:@"UTF-8 Mode Not Detected"];
    }
}

- (void)handleDisplayMessageVersion:(NSString *)response {
    if (response.length == 0) {
        // The "version" format was first added in 2.4
        [self decreaseMaximumServerVersionTo:@"2.3"];
        return;
    }

    NSString *nextPrefix = @"next-";
    if ([response hasPrefix:nextPrefix]) {
        [self handleDisplayMessageVersion:[response substringFromIndex:nextPrefix.length]];
         return;
    }
    if ([response hasSuffix:@"-rc"]) {
        response = [response stringByDroppingLastCharacters:3];
    }
    // In case we get back something that's not a number, or a totally unreasonable number, just ignore this.
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:response];
    if (number.doubleValue != number.doubleValue ||
        number.doubleValue < 2.4 || number.doubleValue > 10) {
        return;
    }
    
    // Sadly tmux version numbers look like 2.9 or 2.9a instead of a proper decimal number.
    NSRange range = [response rangeOfCharacterFromSet:[NSCharacterSet lowercaseLetterCharacterSet]];
    if (range.location == NSNotFound) {
        [self increaseMinimumServerVersionTo:response];
    } else {
        // Convert 2.9a to 2.91
        // According to this issue it should be safe to do this:
        // https://github.com/tmux/tmux/issues/1712
        unichar c = [response characterAtIndex:range.location];
        NSInteger bug = c - 'a' + 1;
        NSString *prefix = [response substringToIndex:range.location];
        NSString *version = [NSString stringWithFormat:@"%@%@", prefix, @(bug)];
        [self increaseMinimumServerVersionTo:version];
    }

    if (gateway_.minimumServerVersion.doubleValue >= 2.9 && [iTermAdvancedSettingsModel tmuxVariableWindowSizesSupported]) {
        _variableWindowSize = YES;
    }
}

- (void)guessVersion23Response:(NSString *)response {
    if (response == nil) {
        [self decreaseMaximumServerVersionTo:@"2.2"];
    } else {
        [self increaseMinimumServerVersionTo:@"2.3"];
    }
}

- (void)guessVersion22Response:(NSString *)response {
    const NSInteger index = [response rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]].location;
    if (index == NSNotFound) {
        [self decreaseMaximumServerVersionTo:@"2.1"];
    } else {
        [self increaseMinimumServerVersionTo:@"2.2"];
    }
}

- (void)guessVersion21Response:(NSString *)response {
    if (response.length == 0) {
        [self decreaseMaximumServerVersionTo:@"2.0"];
    } else {
        [self increaseMinimumServerVersionTo:@"2.1"];
    }
}

- (void)guessVersion18Response:(NSString *)response {
    if (response.length == 0) {
        [self increaseMinimumServerVersionTo:@"1.9"];
    } else {
        [self decreaseMaximumServerVersionTo:@"1.8"];
    }

    // This is the oldest version supported. By the time you get here you know the version.
    [self didGuessVersion];
}

// Actions to perform after the version number is known.
- (void)didGuessVersion {
    [self loadServerPID];
    [self loadTitleFormat];
}

- (BOOL)versionAtLeastDecimalNumberWithString:(NSString *)string {
    NSDecimalNumber *version = [NSDecimalNumber decimalNumberWithString:string];
    if (gateway_.minimumServerVersion == nil) {
        return NO;
    }
    return ([gateway_.minimumServerVersion compare:version] != NSOrderedAscending);
}

- (BOOL)recyclingSupported {
    return [self versionAtLeastDecimalNumberWithString:@"1.9"];
}

// Show an error and terminate the connection because tmux has an unsupported option turned on.
- (void)optionValidationFailedForOption:(NSString *)option
{
    NSString *message = [NSString stringWithFormat:
                            @"The \"%@\" option is turned on in tmux. "
                             "It is not compatible with the iTerm2-tmux integration. "
                             "Please disable it and try again.",
                             option];
    [gateway_ abortWithErrorMessage:message
                              title:@"Unsupported tmux option"];
}

- (NSArray *)unsupportedGlobalOptions
{
    // The aggressive-resize option is not supported because it relies on the
    // concept of a current window in tmux, which doesn't exist in the
    // integration mode.
    return [NSArray arrayWithObjects:kAggressiveResize, nil];
}

// Parse the output of show-window-options sent in -validateOptions, possibly
// showing an error and terminating the connection.
- (void)showWindowOptionsResponse:(NSString *)response {
    NSArray *unsupportedGlobalOptions = [self unsupportedGlobalOptions];
    NSArray *lines = [response componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSArray *fields = [line componentsSeparatedByString:@" "];
        if ([fields count] == 2) {
            NSString *option = [fields objectAtIndex:0];
            NSString *value = [fields objectAtIndex:1];

            for (NSString *unsupportedOption in unsupportedGlobalOptions) {
                if ([option isEqualToString:unsupportedOption]) {
                    if ([value isEqualToString:@"on"]) {
                        [self optionValidationFailedForOption:unsupportedOption];
                        return;
                    }
                }
            }
        }
    }
}

- (BOOL)hasOutstandingWindowResize
{
    return numOutstandingWindowResizes_ > 0;
}

- (void)windowPane:(int)wp
         resizedBy:(int)amount
      horizontally:(BOOL)wasHorizontal
{
    NSString *dir;
    if (wasHorizontal) {
        if (amount > 0) {
            dir = @"R";
        } else {
            dir = @"L";
        }
    } else {
        if (amount > 0) {
            dir = @"D";
        } else {
            dir = @"U";
        }
    }
    NSString *resizeStr = [NSString stringWithFormat:@"resize-pane -%@ -t \"%%%d\" %d",
                           dir, wp, abs(amount)];
    NSString *listStr = [NSString stringWithFormat:@"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\""];
    NSArray *commands = [NSArray arrayWithObjects:
                         [gateway_ dictionaryForCommand:resizeStr
                                         responseTarget:nil
                                       responseSelector:nil
                                         responseObject:nil
                                                  flags:0],
                         [gateway_ dictionaryForCommand:listStr
                                         responseTarget:self
                                       responseSelector:@selector(listWindowsResponse:)
                                         responseObject:nil
                                                  flags:0],
                         nil];
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommandList:commands];
}

// The splitVertically parameter uses the iTerm2 conventions.
- (void)splitWindowPane:(int)wp
             vertically:(BOOL)splitVertically
                  scope:(iTermVariableScope *)scope
       initialDirectory:(iTermInitialDirectory *)initialDirectory {
    // No need for a callback. We should get a layout-changed message and act on it.
    [initialDirectory tmuxSplitWindowCommand:wp
                                  vertically:splitVertically
                          recyclingSupported:self.recyclingSupported
                                       scope:scope
                                  completion:
     ^(NSString *command) {
         [gateway_ sendCommand:command
                responseTarget:nil
              responseSelector:nil];
     }];
}

- (void)selectPane:(int)windowPane {
    NSDecimalNumber *version2_9 = [NSDecimalNumber decimalNumberWithString:@"2.9"];

    if ([gateway_.minimumServerVersion isEqual:version2_9]) {
        // I presume this will be fixed in whatever verson follows 2.9, so use an isEqual:. I need to remember to revisit this after the bug is fixed!
        return;
    }

    NSString *command = [NSString stringWithFormat:@"select-pane -t \"%%%d\"", windowPane];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil];
}

- (void)newWindowInSessionNumber:(NSNumber *)sessionNumber
                           scope:(iTermVariableScope *)scope
                initialDirectory:(iTermInitialDirectory *)initialDirectory {
    [initialDirectory tmuxNewWindowCommandInSessionNumber:sessionNumber
                                 recyclingSupported:self.recyclingSupported
                                              scope:scope
                                         completion:
     ^(NSString *command) {
         NSMutableArray *commands = [NSMutableArray array];
         if (_variableWindowSize) {
             Profile *profile = self.sharedProfile;
             NSSize size = NSMakeSize([profile[KEY_COLUMNS] intValue] ?: 80,
                                      [profile[KEY_ROWS] intValue] ?: 25);
             NSString *setSizeCommand = [NSString stringWithFormat:@"refresh-client -C %d,%d",
                                         (int)size.width, [self adjustHeightForStatusBar:size.height]];
             [commands addObject:[gateway_ dictionaryForCommand:setSizeCommand
                                                 responseTarget:nil
                                               responseSelector:nil
                                                 responseObject:nil
                                                          flags:0]];
         }
         [commands addObject:[gateway_ dictionaryForCommand:command
                                             responseTarget:nil
                                           responseSelector:nil
                                             responseObject:nil
                                                      flags:0]];
         [gateway_ sendCommandList:commands];
     }];
}

- (void)newWindowWithAffinity:(NSString *)windowIdString
                         size:(NSSize)size
             initialDirectory:(iTermInitialDirectory *)initialDirectory
                        scope:(iTermVariableScope *)scope
                   completion:(void (^)(int))completion {
    _manualOpenRequested = (windowIdString != nil);
    BOOL variableWindowSize = _variableWindowSize;
    [initialDirectory tmuxNewWindowCommandRecyclingSupported:self.recyclingSupported
                                                       scope:scope
                                                  completion:
     ^(NSString *command) {
         NSMutableArray *commands = [NSMutableArray array];
         if (variableWindowSize) {
             NSString *setSizeCommand = [NSString stringWithFormat:@"refresh-client -C %d,%d",
                                         (int)size.width, [self adjustHeightForStatusBar:size.height]];
             [commands addObject:[gateway_ dictionaryForCommand:setSizeCommand
                                                 responseTarget:nil
                                               responseSelector:nil
                                                 responseObject:nil
                                                          flags:0]];
         }
         [commands addObject:[gateway_ dictionaryForCommand:command
                                             responseTarget:self
                                           responseSelector:@selector(newWindowWithAffinityCreated:affinityWindowAndCompletion:)
                                             responseObject:[iTermTuple tupleWithObject:windowIdString andObject:[[completion copy] autorelease]]
                                                      flags:0]];
         [gateway_ sendCommandList:commands];
     }];
}

- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"move-pane -s \"%%%d\" -t \"%%%d\" %@%@",
                           srcPane, destPane, splitVertical ? @"-h" : @"-v",
                           addBefore ? @" -b" : @""]
           responseTarget:nil
         responseSelector:nil];
}

- (void)killWindowPane:(int)windowPane
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-pane -t \"%%%d\"", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)unlinkWindowWithId:(int)windowId {
    [gateway_ sendCommand:[NSString stringWithFormat:@"unlink-window -k -t @%d", windowId]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (NSString *)stringByEscapingBackslashesAndRemovingNewlines:(NSString *)name {
    return [[name stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
}

- (void)renameWindowWithId:(int)windowId
           inSessionNumber:(NSNumber *)sessionNumber
                    toName:(NSString *)newName {
    NSString *theCommand;
    if (sessionNumber) {
        theCommand = [NSString stringWithFormat:@"rename-window -t \"$%d:@%d\" \"%@\"",
                      sessionNumber.intValue,
                      windowId,
                      [self stringByEscapingBackslashesAndRemovingNewlines:newName]];
    } else {
        theCommand = [NSString stringWithFormat:@"rename-window -t @%d \"%@\"", windowId, [self stringByEscapingBackslashesAndRemovingNewlines:newName]];
    }
    [gateway_ sendCommand:theCommand
           responseTarget:nil
         responseSelector:nil];
}

- (BOOL)canRenamePane {
    NSDecimalNumber *version2_6 = [NSDecimalNumber decimalNumberWithString:@"2.6"];
    if ([gateway_.minimumServerVersion compare:version2_6] == NSOrderedAscending) {
        return NO;
    }
    return YES;
}

- (void)renamePane:(int)windowPane toTitle:(NSString *)newTitle {
    if (![self canRenamePane]) {
        return;
    }
    NSString *theCommand = [NSString stringWithFormat:@"select-pane -t %%'%d' -T \"%@\"",
                            windowPane, [self stringByEscapingBackslashesAndRemovingNewlines:newTitle]];
    [gateway_ sendCommand:theCommand
           responseTarget:nil
         responseSelector:nil];
}

- (void)setHotkeyForWindowPane:(int)windowPane to:(NSDictionary *)dict {
    _hotkeys[@(windowPane)] = dict;

    // First get a list of existing panes so we can avoid setting hotkeys for any nonexistent panes. Keeps the string from getting too long.
    NSString *getPaneIDsCommand = [NSString stringWithFormat:@"list-panes -s -t $%d -F \"#{pane_id}\"", sessionId_];
    [gateway_ sendCommand:getPaneIDsCommand
           responseTarget:self
         responseSelector:@selector(getPaneIDsResponseAndSetHotkeys:)
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)setTabColorString:(NSString *)colorString forWindowPane:(int)windowPane {
    if ([_tabColors[@(windowPane)] isEqualToString:colorString]) {
        return;
    }
    _tabColors[@(windowPane)] = colorString;

    // First get a list of existing panes so we can avoid setting tab colors for any nonexistent panes. Keeps the string from getting too long.
    NSString *getPaneIDsCommand = [NSString stringWithFormat:@"list-panes -s -t $%d -F \"#{pane_id}\"", sessionId_];
    [gateway_ sendCommand:getPaneIDsCommand
           responseTarget:self
         responseSelector:@selector(getPaneIDsResponseAndSetTabColors:)
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}


- (void)getPaneIDsResponseAndSetHotkeys:(NSString *)response {
    [_paneIDs removeAllObjects];
    for (NSString *pane in [response componentsSeparatedByString:@"\n"]) {
        if (pane.length) {
            [_paneIDs addObject:@([[pane substringFromIndex:1] intValue])];
        }
    }
    [self sendCommandToSetHotkeys];
}

- (void)getPaneIDsResponseAndSetTabColors:(NSString *)response {
    [_paneIDs removeAllObjects];
    for (NSString *pane in [response componentsSeparatedByString:@"\n"]) {
        if (pane.length) {
            [_paneIDs addObject:@([[pane substringFromIndex:1] intValue])];
        }
    }
    [self sendCommandToSetTabColors];
}

- (NSString *)encodedString:(NSString *)string prefix:(NSString *)prefix {
    return [prefix stringByAppendingString:[[string dataUsingEncoding:NSUTF8StringEncoding] it_hexEncoded]];
}

- (NSString *)decodedString:(NSString *)string optionalPrefix:(NSString *)prefix {
    if (![string hasPrefix:prefix]) {
        return string;
    }
    return [[[NSString alloc] initWithData:[[string substringFromIndex:prefix.length] dataFromHexValues]
                                  encoding:NSUTF8StringEncoding] autorelease];
}

- (void)sendCommandToSetHotkeys {
    NSString *hexEncoded = [self encodedString:[self.hotkeysString stringByEscapingQuotes]
                                        prefix:iTermTmuxControllerEncodingPrefixHotkeys];
    NSString *command = [NSString stringWithFormat:@"set -t $%d @hotkeys \"%@\"",
                         sessionId_, hexEncoded];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (void)sendCommandToSetTabColors {

    NSString *command = [NSString stringWithFormat:@"set -t $%d @tab_colors \"%@\"",
                         sessionId_, [self encodedString:[self.tabColorsString stringByEscapingQuotes]
                                                  prefix:iTermTmuxControllerEncodingPrefixTabColors]];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (NSDictionary *)hotkeyForWindowPane:(int)windowPane {
    return _hotkeys[@(windowPane)];
}

- (NSString *)tabColorStringForWindowPane:(int)windowPane {
    return _tabColors[@(windowPane)];
}

- (void)killWindow:(int)window
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-window -t @%d", window]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (NSString *)breakPaneWindowPaneFlag {
    NSDecimalNumber *version2_1 = [NSDecimalNumber decimalNumberWithString:@"2.1"];

    if ([gateway_.maximumServerVersion compare:version2_1] == NSOrderedAscending) {
        // 2.0 and earlier versions take -t for the window pane
        return @"-t";
    }
    if ([gateway_.minimumServerVersion compare:version2_1] != NSOrderedAscending) {
        // 2.1+ takes -s for the window pane
        return @"-s";
    }

    // You shouldn't get here.
    return @"-s";
}

- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint
{
    [windowPositions_ setObject:[NSValue valueWithPoint:screenPoint]
                         forKey:[NSNumber numberWithInt:windowPane]];
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane %@ \"%%%d\"", [self breakPaneWindowPaneFlag], windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane -P -F \"#{window_id}\" %@ \"%%%d\"",
                           [self breakPaneWindowPaneFlag], windowPane]
           responseTarget:self
         responseSelector:@selector(windowPaneBrokeOutWithWindowId:setAffinityTo:)
           responseObject:sibling
                    flags:0];
}

- (void)windowPaneBrokeOutWithWindowId:(NSString *)windowId
                         setAffinityTo:(NSString *)windowGuid
{
    if ([windowId hasPrefix:@"@"]) {
        windowId = [windowId substringFromIndex:1];
        [affinities_ setValue:windowGuid equalToValue:windowId];
    }
}

- (BOOL)windowIsHidden:(int)windowId {
    return [hiddenWindows_ containsObject:@(windowId)];
}

- (void)hideWindow:(int)windowId
{
    NSLog(@"hideWindow: Add these window IDS to hidden: %d", windowId);
    [hiddenWindows_ addObject:[NSNumber numberWithInt:windowId]];
    [self saveHiddenWindows];
    PTYTab *theTab = [self window:windowId];
    if (theTab) {
        [[theTab realParentWindow] closeTab:theTab soft:YES];
    }
}

- (void)openWindowWithId:(int)windowId
              affinities:(NSArray *)affinities
             intentional:(BOOL)intentional
                 profile:(Profile *)profile {
    if (intentional) {
        NSLog(@"open intentional: Remove these window IDS to hidden: %d", windowId);
        [hiddenWindows_ removeObject:[NSNumber numberWithInt:windowId]];
        [self saveHiddenWindows];
    }
    // Get the window's basic info to prep the creation of a TmuxWindowOpener.
    [gateway_ sendCommand:[NSString stringWithFormat:@"display -p -F %@ -t @%d",
                           kListWindowsFormat, windowId]
           responseTarget:self
         responseSelector:@selector(listedWindowsToOpenOne:forWindowIdAndAffinities:)
           responseObject:@[ @(windowId), affinities, profile ]
                    flags:0];
}

- (void)openWindowWithId:(int)windowId
             intentional:(BOOL)intentional
                 profile:(Profile *)profile {
    [self openWindowWithId:windowId
                affinities:@[]
               intentional:intentional
                   profile:profile];
}

- (void)linkWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSessionNumber {
    [gateway_ sendCommand:[NSString stringWithFormat:@"link-window -s \"$%d:@%d\" -t \"$%d:+\"",
                           sessionNumber, windowId, targetSessionNumber]
           responseTarget:nil
         responseSelector:nil];
}

- (void)moveWindowId:(int)windowId
     inSessionNumber:(int)sessionNumber
     toSessionNumber:(int)targetSessionNumber {
    [gateway_ sendCommand:[NSString stringWithFormat:@"move-window -s \"$%d:@%d\" -t \"$%d:+\"",
                           sessionNumber, windowId, targetSessionNumber]
           responseTarget:nil
         responseSelector:nil];
}

// Find a position for any key in panes and remove all entries with keys in panes.
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes
{
    NSValue *pos = nil;
    for (NSNumber *n in panes) {
        pos = [windowPositions_ objectForKey:n];
        if (pos) {
            [[pos retain] autorelease];
            break;
        }
    }
    [windowPositions_ removeObjectsForKeys:panes];
    return pos;
}

- (void)renameSessionNumber:(int)sessionNumber
                         to:(NSString *)newName {
    NSString *renameCommand = [NSString stringWithFormat:@"rename-session -t \"$%d\" \"%@\"",
                               sessionNumber,
                               [newName stringByEscapingQuotes]];
    [gateway_ sendCommand:renameCommand responseTarget:nil responseSelector:nil];
}

- (void)killSessionNumber:(int)sessionNumber {
    NSString *killCommand = [NSString stringWithFormat:@"kill-session -t \"$%d\"", sessionNumber];
    [gateway_ sendCommand:killCommand
              responseTarget:nil
            responseSelector:nil];
    [self listSessions];
}

- (void)addSessionWithName:(NSString *)sessionName
{
    NSString *attachCommand = [NSString stringWithFormat:@"new-session -s \"%@\"",
                               [sessionName stringByEscapingQuotes]];
    [gateway_ sendCommand:attachCommand
           responseTarget:nil
         responseSelector:nil];
    [self listSessions];
}

- (void)attachToSessionWithNumber:(int)sessionNumber {
    NSString *attachCommand = [NSString stringWithFormat:@"attach-session -t \"$%d\"", sessionNumber];
    [gateway_ sendCommand:attachCommand
           responseTarget:nil
         responseSelector:nil];
}

- (void)listWindowsInSessionNumber:(int)sessionNumber
                            target:(id)target
                          selector:(SEL)selector
                            object:(id)object {
    if (detached_ || !object) {
        // This can happen if you're not attached to a session.
        return;
    }
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@ -t \"$%d\"",
                                    kListWindowsFormat, sessionNumber];
    // Wait a few seconds. We always get a windows-close notification when the last window in
    // a window closes. To avoid spamming the command line with list-windows, we wait a bit to see
    // if there is an exit notification coming down the pipe.
    const CGFloat kListWindowsDelay = 1.5;
    [listWindowsTimer_ invalidate];
    listWindowsTimer_ =
    [NSTimer scheduledTimerWithTimeInterval:kListWindowsDelay
                                     target:self
                                   selector:@selector(listWindowsTimerFired:)
                                   userInfo:@[listWindowsCommand,
                                              object,
                                              target,
                                              NSStringFromSelector(selector) ]
                                    repeats:NO];
}

- (void)listWindowsTimerFired:(NSTimer *)timer
{
    NSArray *array = [timer userInfo];
    NSString *command = array[0];
    id object = array[1];
    id target = array[2];
    NSString *selector = array[3];

    [listWindowsTimer_ invalidate];
    listWindowsTimer_ = nil;

    [gateway_ sendCommand:command
           responseTarget:self
         responseSelector:@selector(didListWindows:userData:)
           responseObject:@[object, selector, target]
                    flags:kTmuxGatewayCommandShouldTolerateErrors];  // Tolerates errors because the session may have been detached by the time we get the notification or the timer fires.
}

- (void)saveHiddenWindows
{
    NSString *hidden = [[hiddenWindows_ allObjects] componentsJoinedByString:@","];
    NSString *command = [NSString stringWithFormat:
                         @"set -t $%d @hidden \"%@\"",
                         sessionId_,
                         [self encodedString:hidden
                                      prefix:iTermTmuxControllerEncodingPrefixHidden]];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (void)saveWindowOrigins
{
    if (haveOutstandingSaveWindowOrigins_) {
        windowOriginsDirty_ = YES;
        return;
    }
    windowOriginsDirty_ = NO;
    if (pendingWindowOpens_.count) {
        return;
    }
    [self saveAffinities];  // Make sure the equivalence classes are up to date.
    NSMutableArray *maps = [NSMutableArray array];
    for (NSSet *c in [affinities_ classes]) {
        // temp will hold an array of tmux window IDs as strings, excluding
        // placeholders and pty guids.
        NSMutableArray *temp = [NSMutableArray array];
        PTYTab *tab = nil;
        for (NSString *wid in c) {
            if (![wid hasPrefix:@"pty-"] && ![wid hasSuffix:@"_ph"]) {
                if (!tab) {
                    tab = [self window:[wid intValue]];
                }
                [temp addObject:wid];
            }
        }
        NSString *windowIds = [temp componentsJoinedByString:@","];
        if (tab) {
            NSWindowController<iTermWindowController> * term = [tab realParentWindow];
            NSPoint origin = [[term window] frame].origin;
            [maps addObject:[NSString stringWithFormat:@"%@:%d,%d", windowIds,
                (int)origin.x, (int)origin.y]];
        }
    }
    NSString *enc = [maps componentsJoinedByString:@" "];
    DLog(@"Save window origins to %@ called from %@", enc, [NSThread callStackSymbols]);
    NSString *command = [NSString stringWithFormat:@"set -t $%d @origins \"%@\"",
                         sessionId_,
                         [self encodedString:[enc stringByEscapingQuotes]
                                      prefix:iTermTmuxControllerEncodingPrefixOrigins]];
    if (!lastOrigins_ || ![command isEqualToString:lastOrigins_]) {
        [lastOrigins_ release];
        lastOrigins_ = [command copy];
        haveOutstandingSaveWindowOrigins_ = YES;
        [gateway_ sendCommand:command
               responseTarget:self
             responseSelector:@selector(saveWindowOriginsResponse:)];
    }
    [self getOriginsResponse:[self encodedString:[enc stringByEscapingQuotes]
                                          prefix:iTermTmuxControllerEncodingPrefixOrigins]];
}

- (void)saveWindowOriginsResponse:(NSString *)response
{
    haveOutstandingSaveWindowOrigins_ = NO;
    if (windowOriginsDirty_) {
        [self saveWindowOrigins];
    }
}

- (NSString *)windowOptionsForTerminal:(PseudoTerminal *)term {
    if (term.anyFullScreen) {
        return [NSString stringWithFormat:@"%@=%@",
                kTmuxWindowOpenerWindowOptionStyle, kTmuxWindowOpenerWindowOptionStyleValueFullScreen];
    } else {
        return @"";
    }
}

- (void)saveAffinities {
    if (pendingWindowOpens_.count) {
        return;
    }
    iTermController *cont = [iTermController sharedInstance];
    NSArray *terminals = [cont terminals];
    NSMutableArray *affinities = [NSMutableArray array];
    for (PseudoTerminal *term in terminals) {
        NSMutableArray *siblings = [NSMutableArray array];
        for (PTYTab *aTab in [term tabs]) {
            if ([aTab isTmuxTab] && [aTab tmuxController] == self) {
                NSString *n = [NSString stringWithFormat:@"%d", (int) [aTab tmuxWindow]];
                [siblings addObject:n];
            }
        }
        if ([term terminalGuid]) {
            [siblings addObject:[term terminalGuid]];
        }
        if (siblings.count > 0) {
            NSString *value = [NSString stringWithFormat:@"%@;%@",
                               [siblings componentsJoinedByString:@","],
                               [self windowOptionsForTerminal:term]];
            [affinities addObject:value];
        }
    }
    // Update affinities if any have changed.
    NSString *arg = [affinities componentsJoinedByString:@" "];
    NSString *command = [NSString stringWithFormat:@"set -t $%d @affinities \"%@\"",
                         sessionId_, [self encodedString:[arg stringByEscapingQuotes]
                                                  prefix:iTermTmuxControllerEncodingPrefixAffinities]];
    if ([command isEqualToString:lastSaveAffinityCommand_]) {
        return;
    }
    [self setAffinitiesFromString:arg];
    [lastSaveAffinityCommand_ release];
    lastSaveAffinityCommand_ = [command retain];
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
}

- (PseudoTerminal *)terminalWithGuid:(NSString *)guid
{
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        if ([[term terminalGuid] isEqualToString:guid]) {
            return term;
        }
    }
    return nil;
}

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid {
    for (NSString *n in [self savedAffinitiesForWindow:[NSString stringWithInt:wid]]) {
        if ([n hasPrefix:@"pty-"]) {
            PseudoTerminal *term = [self terminalWithGuid:n];
            if (term) {
                return term;
            }
        } else if ([n hasPrefix:@"-"]) {
            // Attach to window without a tmux tab; the window number is
            // -(n+1). It may not exist, which means to open a new window.
            int value = -[n intValue];
            value -= 1;  // Correct for -1 based index.
            return [[iTermController sharedInstance] terminalWithNumber:value];
        } else if (![n hasSuffix:@"_ph"]) {
            PTYTab *tab = [self window:[n intValue]];
            if (tab) {
                return [[iTermController sharedInstance] terminalWithTab:tab];
            }
        }
    }
    return nil;
}

- (void)changeWindow:(int)window tabTo:(PTYTab *)tab {
    _windowStates[@(window)].tab = tab;
}

- (void)listSessions
{
    [listSessionsTimer_ invalidate];
    listSessionsTimer_ = nil;
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_name}\"";
    [gateway_ sendCommand:listSessionsCommand
           responseTarget:self
         responseSelector:@selector(listSessionsResponse:)];
}

- (void)swapPane:(int)pane1 withPane:(int)pane2 {
    NSString *swapPaneCommand = [NSString stringWithFormat:@"swap-pane -s \"%%%d\" -t \"%%%d\"",
                                 pane1, pane2];

    NSArray *commands = @[ [gateway_ dictionaryForCommand:swapPaneCommand
                                           responseTarget:nil
                                         responseSelector:NULL
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:@"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\""
                                           responseTarget:self
                                         responseSelector:@selector(parseListWindowsResponseAndUpdateLayouts:)
                                           responseObject:nil
                                                    flags:0] ];
    [gateway_ sendCommandList:commands];
}

- (void)toggleZoomForPane:(int)pane {
    NSArray *commands = @[ [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"resize-pane -Z -t \"%%%d\"", pane]
                                           responseTarget:nil
                                         responseSelector:NULL
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:@"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\""
                                           responseTarget:self
                                         responseSelector:@selector(parseListWindowsResponseAndUpdateLayouts:)
                                           responseObject:nil
                                                    flags:0] ];
    [gateway_ sendCommandList:commands];
}

- (void)setTmuxFont:(NSFont *)font
       nonAsciiFont:(NSFont *)nonAsciiFont
           hSpacing:(double)hs
           vSpacing:(double)vs
             window:(int)window {
    NSDictionary *dict = @{ KEY_NORMAL_FONT: [font stringValue],
                            KEY_NON_ASCII_FONT: [nonAsciiFont stringValue],
                            KEY_HORIZONTAL_SPACING: @(hs),
                            KEY_VERTICAL_SPACING: @(vs) };
    if (_variableWindowSize) {
        _windowStates[@(window)].fontOverrides = dict;
        return;
    }
    [_sharedFontOverrides release];
    _sharedFontOverrides = [dict retain];
}

- (void)setLayoutInWindow:(int)window toLayout:(NSString *)layout {
    NSArray *commands = @[ [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"select-layout -t @%@ %@",
                                                           @(window), layout]
                                           responseTarget:self
                                         responseSelector:@selector(didSetLayout:)
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\" -t \"$%d\"", sessionId_]
                                           responseTarget:self
                                         responseSelector:@selector(didListWindowsSubsequentToSettingLayout:)
                                           responseObject:nil
                                                    flags:0] ];
    [gateway_ sendCommandList:commands];
}

- (void)setLayoutInWindowPane:(int)windowPane toLayoutNamed:(NSString *)name {
    NSArray *commands = @[ [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"select-layout -t %%%@ %@", @(windowPane), name]
                                           responseTarget:self
                                         responseSelector:@selector(didSetLayout:)
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\" -t \"$%d\"", sessionId_]
                                           responseTarget:self
                                         responseSelector:@selector(didListWindowsSubsequentToSettingLayout:)
                                           responseObject:nil
                                                    flags:0] ];
    [gateway_ sendCommandList:commands];
}

- (void)didSetLayout:(NSString *)response {
}

- (void)didListWindowsSubsequentToSettingLayout:(NSString *)response {
    [self parseListWindowsResponseAndUpdateLayouts:response];
}

- (NSArray<PTYSession *> *)clientSessions {
    return windowPanes_.allValues;
}

#pragma mark - Private

- (void)getOriginsResponse:(NSString *)encodedResult {
    NSString *result = [self decodedString:encodedResult
                            optionalPrefix:iTermTmuxControllerEncodingPrefixOrigins];
    [origins_ removeAllObjects];
    if ([result length] > 0) {
        NSArray *windows = [result componentsSeparatedByString:@" "];
        for (NSString *wstr in windows) {
            NSArray *tuple = [wstr componentsSeparatedByString:@":"];
            if (tuple.count != 2) {
                continue;
            }
            NSString *windowsStr = [tuple objectAtIndex:0];
            NSString *coords = [tuple objectAtIndex:1];
            NSArray *windowIds = [windowsStr componentsSeparatedByString:@","];
            NSArray *xy = [coords componentsSeparatedByString:@","];
            if (xy.count != 2) {
                continue;
            }
            NSPoint origin = NSMakePoint([[xy objectAtIndex:0] intValue],
                                         [[xy objectAtIndex:1] intValue]);
            for (NSString *wid in windowIds) {
                [origins_ setObject:[NSValue valueWithPoint:origin]
                             forKey:[NSNumber numberWithInt:[wid intValue]]];
            }
        }
    }
}

- (NSString *)shortStringForHotkeyDictionary:(NSDictionary *)dict paneID:(int)wp {
    return [NSString stringWithFormat:@"%d=%@", wp, [iTermShortcut shortStringForDictionary:dict]];
}

- (NSString *)hotkeysString {
    NSMutableArray *parts = [NSMutableArray array];
    [_hotkeys enumerateKeysAndObjectsUsingBlock:^(NSNumber *  _Nonnull key, NSDictionary *_Nonnull obj, BOOL * _Nonnull stop) {
        if ([_paneIDs containsObject:key]) {
            [parts addObject:[self shortStringForHotkeyDictionary:obj paneID:key.intValue]];
        }
    }];

    return [parts componentsJoinedByString:@" "];
}

- (NSString *)tabColorsString {
    NSMutableArray *parts = [NSMutableArray array];
    [_tabColors enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
        if ([_paneIDs containsObject:key]) {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", key, obj]];
        }
    }];

    return [parts componentsJoinedByString:@" "];
}

- (void)getHotkeysResponse:(NSString *)encodedResult {
    NSString *result = [self decodedString:encodedResult optionalPrefix:iTermTmuxControllerEncodingPrefixHotkeys];
    [_hotkeys removeAllObjects];
    if (result.length > 0) {
        [_hotkeys removeAllObjects];
        NSArray *parts = [result componentsSeparatedByString:@" "];
        for (NSString *part in parts) {
            NSInteger equals = [part rangeOfString:@"="].location;
            if (equals != NSNotFound && equals + 1 < part.length) {
                NSString *wp = [part substringToIndex:equals];
                NSString *shortString = [part substringFromIndex:equals + 1];
                NSDictionary *dict = [iTermShortcut dictionaryForShortString:shortString];
                if (dict) {
                    _hotkeys[@(wp.intValue)] = dict;
                }
            }
        }
    }
}

- (void)getTabColorsResponse:(NSString *)encodedResult {
    NSString *result = [self decodedString:encodedResult
                            optionalPrefix:iTermTmuxControllerEncodingPrefixTabColors];
    [_tabColors removeAllObjects];
    if (result.length > 0) {
        [_tabColors removeAllObjects];
        NSArray *parts = [result componentsSeparatedByString:@" "];
        for (NSString *part in parts) {
            NSInteger equals = [part rangeOfString:@"="].location;
            if (equals != NSNotFound && equals + 1 < part.length) {
                NSString *wp = [part substringToIndex:equals];
                NSString *colorString = [part substringFromIndex:equals + 1];
                if (colorString && wp.length) {
                    _tabColors[@(wp.intValue)] = colorString;
                }
            }
        }
    }
}

- (int)windowIdFromString:(NSString *)s
{
    if (s.length < 2 || [s characterAtIndex:0] != '@') {
        return -1;
    }
    return [[s substringFromIndex:1] intValue];
}

- (void)didListWindows:(NSString *)response userData:(NSArray *)userData
{
    if (!response) {
        // In case of error.
        response = @"";
    }
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    id object = userData[0];
    SEL selector = NSSelectorFromString(userData[1]);
    id target = userData[2];
    [target performSelector:selector withObject:doc withObject:object];
}

- (void)getHiddenWindowsResponse:(NSString *)encodedResponse {
    NSString *response = [self decodedString:encodedResponse
                              optionalPrefix:iTermTmuxControllerEncodingPrefixHidden];
    [hiddenWindows_ removeAllObjects];
    if ([response length] > 0) {
        NSArray *windowIds = [response componentsSeparatedByString:@","];
        NSLog(@"getHiddenWindowsResponse: Add these window IDS to hidden: %@", windowIds);
        for (NSString *wid in windowIds) {
            [hiddenWindows_ addObject:[NSNumber numberWithInt:[wid intValue]]];
        }
    }
}

- (void)getAffinitiesResponse:(NSString *)result {
    [self setAffinitiesFromString:[self decodedString:result optionalPrefix:iTermTmuxControllerEncodingPrefixAffinities]];
}

- (NSArray *)componentsOfAffinities:(NSString *)affinities {
    NSRange semicolonRange = [affinities rangeOfString:@";"];
    if (semicolonRange.location != NSNotFound) {
        NSString *siblings = [affinities substringToIndex:semicolonRange.location];
        NSString *windowOptions = [affinities substringFromIndex:NSMaxRange(semicolonRange)];
        return @[ siblings, windowOptions ];
    } else {
        return @[ affinities, @"" ];
    }
}

// Takes key1=value1,key2=value2 and returns @{ key1: value1, key2: value2 }
- (NSDictionary *)windowOptionsFromString:(NSString *)kvpString {
    NSMutableDictionary *flags = [NSMutableDictionary dictionary];
    NSArray *kvps = [kvpString componentsSeparatedByString:@","];
    for (NSString *flagString in kvps) {
        NSRange equalsRange = [flagString rangeOfString:@"="];
        if (equalsRange.location != NSNotFound) {
            NSString *key = [flagString substringToIndex:equalsRange.location];
            NSString *value = [flagString substringFromIndex:NSMaxRange(equalsRange)];
            flags[key] = value;
        }
    }
    return flags;
}

- (void)setAffinitiesFromString:(NSString *)result {
    // Replace the existing equivalence classes with those defined by the
    // affinity response.
    // For example "1,2,3 4,5,6" has two equivalence classes.
    // 1=2=3 and 4=5=6.
    NSArray *affinities = [result componentsSeparatedByString:@" "];
    [affinities_ release];
    affinities_ = [[EquivalenceClassSet alloc] init];

    if (![result length]) {
        return;
    }

    for (NSString *theString in affinities) {
        NSArray *components = [self componentsOfAffinities:theString];
        NSString *affset = components[0];
        NSString *windowOptionsString = components[1];

        NSArray *siblings = [affset componentsSeparatedByString:@","];
        NSString *exemplar = [siblings lastObject];
        if (siblings.count == 1) {
            // This is a wee hack. If a tmux Window is in a native window with one tab
            // then create an equivalence class containing only (wid, wid+"_ph"). ph=placeholder
            // The equivalence class's existence signals not to apply the default mode for
            // unrecognized windows.
            exemplar = [exemplar stringByAppendingString:@"_ph"];
        }
        NSDictionary *flags = [self windowOptionsFromString:windowOptionsString];
        for (NSString *widString in siblings) {
            if (![widString isEqualToString:exemplar]) {
                [affinities_ setValue:widString
                         equalToValue:exemplar];
                _windowOpenerOptions[widString] = flags;
            }
        }
    }
}

- (void)listSessionsResponse:(NSString *)result
{
    self.sessionObjects = [[result componentsSeparatedByRegex:@"\n"] mapWithBlock:^iTermTmuxSessionObject *(NSString *line) {
        const NSInteger space = [line rangeOfString:@" "].location;
        if (space == NSNotFound) {
            return nil;
        }
        NSString *sessionID = [line substringToIndex:space];
        NSString *sessionName = [line substringFromIndex:space + 1];
        if (![sessionID hasPrefix:@"$"]) {
            return nil;
        }
        NSScanner *scanner = [NSScanner scannerWithString:[sessionID substringFromIndex:1]];
        int sessionNumber = -1;
        if (![scanner scanInt:&sessionNumber] || sessionNumber < 0) {
            return nil;
        }
        iTermTmuxSessionObject *obj = [[[iTermTmuxSessionObject alloc] init] autorelease];
        obj.name = sessionName;
        obj.number = sessionNumber;
        return obj;
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionsDidChange
                                                        object:nil];
}

- (void)listedWindowsToOpenOne:(NSString *)response
      forWindowIdAndAffinities:(NSArray *)values {
    NSNumber *windowId = values[0];
    NSSet *affinities = values[1];
    Profile *profile = values[2];
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for list windows request: %@",
                                         response]];
        return;
    }
    for (NSArray *record in doc.records) {
        NSString *recordWindowId = [doc valueInRecord:record forField:@"window_id"];
        if ([self windowIdFromString:recordWindowId] == [windowId intValue]) {
            [self openWindowWithIndex:[self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]]
                                 name:[[doc valueInRecord:record forField:@"window_name"] it_unescapedTmuxWindowName]
                                 size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                                 [[doc valueInRecord:record forField:@"window_height"] intValue])
                               layout:[doc valueInRecord:record forField:@"window_layout"]
                           affinities:affinities
                          windowFlags:[doc valueInRecord:record forField:@"window_flags"]
                              profile:profile
                              initial:NO];
        }
    }
}

// When an iTerm2 window is resized, a control -s client-size w,h
// command is sent. It responds with new layouts for all the windows in the
// client's session. Update the layouts for the affected tabs.
- (void)listWindowsResponse:(NSString *)response
{
    --numOutstandingWindowResizes_;
    if (numOutstandingWindowResizes_ > 0) {
        return;
    }

    [self parseListWindowsResponseAndUpdateLayouts:response];
}

- (void)parseListWindowsResponseAndUpdateLayouts:(NSString *)response {
    NSArray *layoutStrings = [response componentsSeparatedByString:@"\n"];
    for (NSString *layoutString in layoutStrings) {
        NSArray *components = [layoutString captureComponentsMatchedByRegex:@"^@([0-9]+) ([^ ]+)(?: ([^ ]+))?"];
        if ([components count] < 3) {
            NSLog(@"Bogus layout string: \"%@\"", layoutString);
        } else {
            int window = [[components objectAtIndex:1] intValue];
            NSString *layout = [components objectAtIndex:2];
            PTYTab *tab = [self window:window];
            if (tab) {
                NSNumber *zoomed = components.count > 3 ? @([components[3] containsString:@"Z"]) : nil;
                [[gateway_ delegate] tmuxUpdateLayoutForWindow:window
                                                        layout:layout
                                                        zoomed:zoomed];
            }
        }
    }
}

- (void)retainWindow:(int)window withTab:(PTYTab *)tab {
    assert(tab);
    NSNumber *k = [NSNumber numberWithInt:window];
    iTermTmuxWindowState *state = _windowStates[k];
    BOOL notify = NO;
    if (state) {
        state.refcount = state.refcount + 1;
    } else {
        state = [[[iTermTmuxWindowState alloc] init] autorelease];
        state.tab = tab;
        state.refcount = 1;
        state.profile = tab.sessions.firstObject.profile;
        _windowStates[k] = state;
        notify = YES;
    }
    if (notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                            object:nil];
    }
}

- (void)releaseWindow:(int)window
{
    NSNumber *k = [NSNumber numberWithInt:window];
    iTermTmuxWindowState *state = _windowStates[k];
    state.refcount = state.refcount - 1;
    if (!state.refcount) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidClose
                                                            object:nil];
        [_windowStates removeObjectForKey:k];
    }
}

// Called only for iTerm2-initiated new windows/tabs.
- (void)newWindowWithAffinityCreated:(NSString *)responseStr
         affinityWindowAndCompletion:(iTermTuple *)tuple {  // Value passed in to -newWindowWithAffinity:, may be nil
    if ([responseStr hasPrefix:@"@"]) {
        int intWindowId = [[responseStr substringFromIndex:1] intValue];
        NSString  *windowId = [NSString stringWithInt:intWindowId];
        void (^completion)(int) = tuple.secondObject;
        _pendingWindows[@(intWindowId)] = completion ?: ^(int i){};
        NSString *affinityWindow = tuple.firstObject;
        if (affinityWindow) {
            [affinities_ setValue:windowId
                     equalToValue:affinityWindow];
        } else {
            [affinities_ removeValue:windowId];
        }
    } else {
        NSLog(@"Response to new-window doesn't look like a window id: \"%@\"", responseStr);
    }
}

- (void)closeAllPanes
{
    // Close all sessions. Iterate over a copy of windowPanes_ because the loop
    // body modifies it by closing sessions.
    for (NSString *key in [[windowPanes_ copy] autorelease]) {
        PTYSession *session = [windowPanes_ objectForKey:key];
        [session.delegate.realParentWindow softCloseSession:session];
    }

    // Clean up all state to avoid trying to reuse it.
    [windowPanes_ removeAllObjects];
}

- (void)windowDidOpen:(TmuxWindowOpener *)windowOpener {
    NSNumber *windowIndex = @(windowOpener.windowIndex);
    DLog(@"TmuxController windowDidOpen for index %@", windowIndex);
    [pendingWindowOpens_ removeObject:windowIndex];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                        object:nil];
    PTYTab *tab = [self window:[windowIndex intValue]];
    NSWindowController<iTermWindowController> * term = [tab realParentWindow];
    NSValue *p = [origins_ objectForKey:windowIndex];
    if (term && p && ![term anyFullScreen] && term.tabs.count == 1) {
        [[term window] setFrameOrigin:[p pointValue]];
    }
    [self saveAffinities];
    if (pendingWindowOpens_.count == 0) {
        [self sendInitialWindowsOpenedNotificationIfNeeded];
    }
}

- (void)sendInitialWindowsOpenedNotificationIfNeeded {
    if (!_haveOpenedInitialWindows) {
        [gateway_.delegate tmuxDidOpenInitialWindows];
        _haveOpenedInitialWindows = YES;
    }
}

- (void)setPartialWindowIdOrder:(NSArray *)partialOrder {
    [gateway_ sendCommand:@"list-windows -F \"#{window_id}\""
           responseTarget:self
         responseSelector:@selector(responseForListWindows:toSetPartialOrder:)
           responseObject:partialOrder
                    flags:0];
}

- (void)responseForListWindows:(NSString *)response toSetPartialOrder:(NSArray *)partialOrder {
    NSArray *ids = [response componentsSeparatedByString:@"\n"];
    NSMutableArray *currentOrder = [NSMutableArray array];
    for (NSString *windowId in ids) {
        if ([windowId hasPrefix:@"@"]) {
            int i = [[windowId substringFromIndex:1] intValue];
            NSNumber *n = @(i);
            if ([partialOrder containsObject:n]) {
                [currentOrder addObject:n];
            }
        }
    }

    NSMutableArray *desiredOrder = [NSMutableArray array];
    for (NSNumber *n in partialOrder) {
        if ([currentOrder containsObject:n]) {
            [desiredOrder addObject:n];
        }
    }

    // We have two lists, desiredOrder and currentOrder, that contain the same objects but
    // in (possibly) a different order. For each out-of-place value, swap it with a later value,
    // placing the later value in its correct location.
    NSMutableArray *commands = [NSMutableArray array];
    for (int i = 0; i < currentOrder.count; i++) {
        if ([currentOrder[i] intValue] != [desiredOrder[i] intValue]) {
            NSInteger swapIndex = [currentOrder indexOfObject:desiredOrder[i]];
            assert(swapIndex != NSNotFound);

            NSString *command = [NSString stringWithFormat:@"swap-window -s @%@ -t @%@",
                                    currentOrder[i], currentOrder[swapIndex]];
            NSDictionary *dict = [gateway_ dictionaryForCommand:command
                                                 responseTarget:self
                                               responseSelector:@selector(didSwapWindows:)
                                                 responseObject:nil
                                                          flags:0];
            [commands addObject:dict];
            NSNumber *temp = [[currentOrder[i] retain] autorelease];
            currentOrder[i] = currentOrder[swapIndex];
            currentOrder[swapIndex] = temp;
        }
    }

    [gateway_ sendCommandList:commands];
}

- (void)didSwapWindows:(NSString *)response {
}

- (void)setCurrentWindow:(int)windowId {
    NSString *command = [NSString stringWithFormat:@"select-window -t @%d", windowId];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil];
}

@end
