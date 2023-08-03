//
//  TmuxController.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxController.h"
#import "DebugLogging.h"
#import "EquivalenceClassSet.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermInitialDirectory.h"
#import "iTermInitialDirectory+Tmux.h"
#import "iTermKeyMappings.h"
#import "iTermKeystroke.h"
#import "iTermLSOF.h"
#import "iTermNotificationController.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermPreferences.h"
#import "iTermProfilePreferences.h"
#import "iTermShortcut.h"
#import "iTermTmuxBufferSizeMonitor.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSData+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "RegexKitLite.h"
#import "TmuxControllerRegistry.h"
#import "TmuxDashboardController.h"
#import "TmuxGateway.h"
#import "TmuxWindowOpener.h"
#import "TSVParser.h"

NSString *const kTmuxControllerSessionsWillChange = @"kTmuxControllerSessionsWillChange";
NSString *const kTmuxControllerSessionsDidChange = @"kTmuxControllerSessionsDidChange";
NSString *const kTmuxControllerDetachedNotification = @"kTmuxControllerDetachedNotification";
NSString *const kTmuxControllerWindowsChangeNotification = @"kTmuxControllerWindowsChangeNotification";
NSString *const kTmuxControllerWindowWasRenamed = @"kTmuxControllerWindowWasRenamed";
NSString *const kTmuxControllerWindowDidOpen = @"kTmuxControllerWindowDidOpen";
NSString *const kTmuxControllerAttachedSessionDidChange = @"kTmuxControllerAttachedSessionDidChange";
NSString *const kTmuxControllerWindowDidClose = @"kTmuxControllerWindowDidClose";
NSString *const kTmuxControllerSessionWasRenamed = @"kTmuxControllerSessionWasRenamed";
NSString *const kTmuxControllerDidFetchSetTitlesStringOption = @"kTmuxControllerDidFetchSetTitlesStringOption";
NSString *const iTermTmuxControllerWillKillWindow = @"iTermTmuxControllerWillKillWindow";
NSString *const kTmuxControllerDidChangeHiddenWindows = @"kTmuxControllerDidChangeHiddenWindows";

static NSString *const iTermTmuxControllerEncodingPrefixHotkeys = @"h_";
static NSString *const iTermTmuxControllerEncodingPrefixTabColors = @"t_";
static NSString *const iTermTmuxControllerEncodingPrefixAffinities = @"a_";
static NSString *const iTermTmuxControllerEncodingPrefixBuriedIndexes = @"b_";
static NSString *const iTermTmuxControllerEncodingPrefixOrigins = @"o_";
static NSString *const iTermTmuxControllerEncodingPrefixHidden = @"i_";
static NSString *const iTermTmuxControllerEncodingPrefixUserVars = @"u_";
static NSString *const iTermTmuxControllerEncodingPrefixPerWindowSettings = @"w_";
static NSString *const iTermTmuxControllerEncodingPrefixPerTabSettings = @"T_";

static NSString *const iTermTmuxControllerSplitStateCompletion = @"completion";
static NSString *const iTermTmuxControllerSplitStateInitialPanes = @"initial panes";
static NSString *const iTermTmuxControllerPhonyAffinity = @"phony";

// Unsupported global options:
static NSString *const kAggressiveResize = @"aggressive-resize";

@interface TmuxController ()<iTermTmuxBufferSizeMonitorDelegate>

@property(nonatomic, copy) NSString *clientName;
@property(nonatomic, copy, readwrite) NSString *sessionGuid;

@end

@interface iTermTmuxWindowState : NSObject
@property (nonatomic, strong) PTYTab *tab;
@property (nonatomic) NSInteger refcount;
@property (nonatomic, strong) Profile *profile;
@property (nonatomic, strong) NSDictionary *fontOverrides;
@end

@interface iTermTmuxPendingWindow: NSObject
@property (nonatomic, copy) void (^completion)(int);
@property (nonatomic, strong) NSNumber *index;  // Tab index. Nullable.

+ (instancetype)trivialInstance;
+ (instancetype)withIndex:(NSNumber *)index completion:(void (^)(int))completion;
@end

@implementation iTermTmuxPendingWindow

+ (instancetype)trivialInstance {
    return [[self alloc] initWithIndex:nil completion:^(int i) { }];
}

+ (instancetype)withIndex:(NSNumber *)index completion:(void (^)(int))completion {
    return [[self alloc] initWithIndex:index completion:completion];
}

- (instancetype)initWithIndex:(NSNumber *)index completion:(void (^)(int))completion {
    if (!completion) {
        return [self initWithIndex:index completion:^(int i) { }];
    }
    self = [super init];
    if (self) {
        assert(index == nil || [NSNumber castFrom:index] != nil);
        _index = index;
        _completion = [completion copy];
    }
    return self;
}

@end

@implementation iTermTmuxWindowState
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
    BOOL ambiguousIsDoubleWidth_;
    NSMutableDictionary<NSNumber *, NSDictionary *> *_hotkeys;
    NSMutableSet<NSNumber *> *_paneIDs;  // existing pane IDs
    NSMutableDictionary<NSNumber *, NSString *> *_tabColors;

    // Have we guessed the server version? Don't try to open windows until this is true, because
    // window opening is version-dependent (to avoid triggering bugs in tmux 1.8).
    BOOL _versionKnown;
    BOOL _wantsOpenWindowsInitial;

    // Maps a window id string to a dictionary of window flags defined by TmuxWindowOpener (see the
    // top of its header file)
    NSMutableDictionary *_windowOpenerOptions;
    BOOL _manualOpenRequested;
    BOOL _allInitialWindowsAdded;
    BOOL _haveOpenedInitialWindows;
    ProfileModel *_profileModel;
    // Maps the window ID of an about to be opened window to a completion block to invoke when it opens.
    NSMutableDictionary<NSNumber *, iTermTmuxPendingWindow *> *_pendingWindows;
    BOOL _hasStatusBar;
    BOOL _focusEvents;
    int _currentWindowID;  // -1 if undefined
    // Pane -> (Key -> Value)
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, NSString *> *> *_userVars;
    NSMutableDictionary<NSNumber *, void (^)(PTYSession<iTermTmuxControllerSession> *)> *_when;
    NSMutableArray *_listWindowsQueue;
    // If nonnegative, make this pane active after it comes in to being. If negative, invalid.
    int _paneToActivateWhenCreated;
    iTermTmuxBufferSizeMonitor *_tmuxBufferMonitor;
    NSMutableDictionary<NSNumber *, NSValue *> *_windowSizes;  // window -> NSValue cell size
    BOOL _versionDetected;
    // terminal guid -> [(tmux window id, tab index), ...]
    NSMutableDictionary<NSString *, NSMutableArray<iTermTuple<NSNumber *, NSNumber *> *> *> *_buriedWindows;
    NSString *_lastSaveBuriedIndexesCommand;

    NSString *_lastSavePerWindowSettingsCommand;
    NSDictionary<NSString *, NSString *> *_perWindowSettings;

    NSString *_lastSavePerTabSettingsCommand;
    NSDictionary<NSString *, NSString *> *_perTabSettings;

    // When positive do not send select-pane or select-window commands when the selected pane
    // or window changes. This is to prevent getting into a loop like this:
    // 1. > select-window -t @2            // iTerm2-initiated
    // 2. > select-window -t @3            // iTerm2-initiated
    // 3. < %session-window-changed $1 @2  // Notification for (1)
    // 4. > select-window -t @2            // In response to (3)
    // 5. < %session-window-changed $1 @3  // Notification for (2)
    // 6. > select-window -t @3            // In response to (5)
    // 7. < %session-window-changed $1 @2  // Notification for (4)
    // 8. > select-window -t @2            // In response to (7)
    // 9. < %session-window-changed $1 @3  // Notification for (6)
    // GOTO 6
    // If we don't tell tmux to change the active window or pane in response to its notification
    // we'll eventually catch up to its current state and remain stable.
    NSInteger _suppressActivityChanges;
    BOOL _shouldWorkAroundTabBug;

    // Window frames before font size changes. Used to preserve window size in
    // the face of font sizes by just setting it back to the right size after
    // font size changes are finished happening.
    NSMutableDictionary<NSString *, NSValue *> *_savedFrames;
}

@synthesize gateway = gateway_;
@synthesize windowPositions = windowPositions_;
@synthesize sessionName = sessionName_;
@synthesize sessionObjects = sessionObjects_;
@synthesize ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
@synthesize sessionId = sessionId_;
@synthesize detached = detached_;

static NSDictionary *iTermTmuxControllerMakeFontOverrides(iTermFontTable *fontTable,
                                                          CGFloat hs,
                                                          CGFloat vs) {
    return @{ KEY_NORMAL_FONT: fontTable.asciiFont.font.stringValue,
              KEY_NON_ASCII_FONT: fontTable.defaultNonASCIIFont.font.stringValue,
              KEY_FONT_CONFIG: fontTable.configString ?: [NSNull null],
              KEY_HORIZONTAL_SPACING: @(hs),
              KEY_VERTICAL_SPACING: @(vs) };
}
static NSDictionary *iTermTmuxControllerDefaultFontOverridesFromProfile(Profile *profile) {
    return iTermTmuxControllerMakeFontOverrides([iTermFontTable fontTableForProfile:profile],
                                                [iTermProfilePreferences floatForKey:KEY_HORIZONTAL_SPACING inProfile:profile],
                                                [iTermProfilePreferences floatForKey:KEY_VERTICAL_SPACING inProfile:profile]);
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway
                     clientName:(NSString *)clientName
                        profile:(NSDictionary *)profile
                   profileModel:(ProfileModel *)profileModel {
    self = [super init];
    if (self) {
        _sharedProfile = [profile copy];
        _profileModel = profileModel;
        _sharedFontOverrides = iTermTmuxControllerDefaultFontOverridesFromProfile(profile);
        _sharedKeyMappingOverrides = [iTermKeyMappings keyMappingsForProfile:profile];

        gateway_ = gateway;
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
        _currentWindowID = -1;
        _userVars = [[NSMutableDictionary alloc] init];
        _when = [[NSMutableDictionary alloc] init];
        [[TmuxControllerRegistry sharedInstance] setController:self forClient:_clientName];
        _listWindowsQueue = [[NSMutableArray alloc] init];
        _paneToActivateWhenCreated = -1;
        _buriedWindows = [[NSMutableDictionary alloc] init];
        _savedFrames = [[NSMutableDictionary alloc] init];
        __weak __typeof(self) weakSelf = self;
        [iTermPreferenceDidChangeNotification subscribe:self
                                                  block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
            if ([notification.key isEqualToString:kPreferenceKeyTmuxPauseModeAgeLimit]) {
                [weakSelf enablePauseModeIfPossible];
            }
        }];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(textViewWillChangeFont:)
                                                     name:PTYTextViewWillChangeFontNotification
                                                   object:nil];

        _windowSizes = [[NSMutableDictionary alloc] init];
        DLog(@"Create %@ with gateway=%@", self, gateway_);
    }
    return self;
}

- (Profile *)profileForWindow:(int)window {
    if (!_variableWindowSize) {
        return [self sharedProfile];
    }
    Profile *original = _windowStates[@(window)].profile;
    if (!original) {
        return [self sharedProfile];
    }
    NSMutableDictionary *temp = [original mutableCopy];
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
    NSMutableDictionary *updatedKeyMappings = [temp[KEY_KEYBOARD_MAP] mutableCopy];
    [_sharedKeyMappingOverrides enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        updatedKeyMappings[key] = obj;
    }];
    temp[KEY_KEYBOARD_MAP] = updatedKeyMappings;
    return temp;
}

// Called when listing window finishes. Happens for all new windows/tabs, whether initiated by iTerm2 or not.
- (void)openWindowWithIndex:(int)windowIndex
                       name:(NSString *)name
                       size:(NSSize)size
                     layout:(NSString *)layout
              visibleLayout:(NSString *)visibleLayout
                 affinities:(NSSet *)affinities
                windowFlags:(NSString *)windowFlags
                    profile:(Profile *)profile
                    initial:(BOOL)initial
                   tabIndex:(NSNumber *)tabIndex {
    DLog(@"openWindowWithIndex:%d name:%@ affinities:%@ flags:%@ initial:%@",
         windowIndex, name, affinities, windowFlags, @(initial));
    if (!gateway_) {
        DLog(@"Deciding NOT to open window because gateway is nil");
        return;
    }
    NSNumber *n = [NSNumber numberWithInt:windowIndex];
    if ([pendingWindowOpens_ containsObject:n]) {
        return;
    }
    NSString *originalTerminalGUID = nil;
    DLog(@"Opening window with affinities: %@", [affinities.allObjects componentsJoinedByString:@" "]);
    DLog(@"Existing affinities:");
    [affinities_ log];
    for (NSString *a in affinities) {
        if ([a hasPrefix:@"pty-"]) {
            originalTerminalGUID = a;
        }
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
    windowOpener.visibleLayout = visibleLayout;
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
    windowOpener.allInitialWindowsAdded = _allInitialWindowsAdded;
    windowOpener.tabColors = _tabColors;
    windowOpener.focusReporting = _focusEvents && [iTermAdvancedSettingsModel focusReportingEnabled];
    windowOpener.profile = profile;
    windowOpener.initial = initial;
    windowOpener.anonymous = (_pendingWindows[@(windowIndex)] == nil);
    windowOpener.completion = _pendingWindows[@(windowIndex)].completion;
    windowOpener.minimumServerVersion = self.gateway.minimumServerVersion;
    windowOpener.tabIndex = tabIndex ?: _pendingWindows[@(windowIndex)].index;
    windowOpener.windowGUID = [self windowGUIDInAffinities:affinities];
    windowOpener.perWindowSettings = _perWindowSettings;
    windowOpener.perTabSettings = _perTabSettings;
    windowOpener.shouldWorkAroundTabBug = _shouldWorkAroundTabBug;
    DLog(@"windowGUID=%@ perWindowSettings=%@ perTabSettings=%@",
         windowOpener.windowGUID, windowOpener.perWindowSettings, windowOpener.perTabSettings);
    if (originalTerminalGUID) {
        __weak __typeof(self) weakSelf = self;
        windowOpener.newWindowBlock = ^(NSString *terminalGUID) {
            [weakSelf replaceOldTerminalGUID:originalTerminalGUID with:terminalGUID];
        };
    }
    [_pendingWindows removeObjectForKey:@(windowIndex)];
    _manualOpenRequested = NO;
    if (![windowOpener openWindows:YES]) {
        [pendingWindowOpens_ removeObject:n];
    }
}

- (NSString *)windowGUIDInAffinities:(NSSet<NSString *> *)affinities {
    return [affinities.allObjects objectPassingTest:^BOOL(NSString *string, NSUInteger index, BOOL *stop) {
        return [string hasPrefix:@"pty-"];
    }];
}

// When we attach we get affinities with terminal GUIDs that may no longer exist. The GUIDs get
// rewritten after creating the window for the first tab. For restored sessions it just works
// because 2nd through Nth tabs can find their comrades through their affinity with its window ID.
// For buried sessions, we must rewrite the terminal GUID since it has no affinity with other tabs
// by window ID.
- (void)replaceOldTerminalGUID:(NSString *)oldGUID with:(NSString *)newGUID {
    DLog(@"rename %@ to %@", oldGUID, newGUID);
    if (_buriedWindows[oldGUID] == nil) {
        DLog(@"no buried windows for that old guid");
        return;
    }
    if (_buriedWindows[newGUID] != nil) {
        DLog(@"already have buried windows for the new guid (wtf?)");
        return;
    }
    _buriedWindows[newGUID] = _buriedWindows[oldGUID];
    [_buriedWindows removeObjectForKey:oldGUID];
}

- (BOOL)setLayoutInTab:(PTYTab *)tab
              toLayout:(NSString *)layout
         visibleLayout:(NSString *)visibleLayout
                zoomed:(NSNumber *)zoomed {
    DLog(@"setLayoutInTab:%@ toLayout:%@ zoomed:%@", tab, layout, zoomed);
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
    windowOpener.unicodeVersion = self.unicodeVersion;
    windowOpener.layout = layout;
    windowOpener.visibleLayout = visibleLayout;
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
    windowOpener.focusReporting = _focusEvents && [iTermAdvancedSettingsModel focusReportingEnabled];
    windowOpener.profile = [self profileForWindow:tab.tmuxWindow];
    windowOpener.minimumServerVersion = self.gateway.minimumServerVersion;
    windowOpener.shouldWorkAroundTabBug = _shouldWorkAroundTabBug;
    return [windowOpener updateLayoutInTab:tab];
}

- (void)adjustWindowSizeIfNeededForTabs:(NSArray<PTYTab *> *)tabs {
    DLog(@"adjustWindowSizeIfNeededForTabs starting");
    if (![tabs anyWithBlock:^BOOL(PTYTab *tab) { return [tab updatedTmuxLayoutRequiresAdjustment]; }]) {
        DLog(@"adjustWindowSizeIfNeededForTabs: Layouts fit");
        return;
    }
    DLog(@"layout is too large among at least one of: %@", tabs);
    // The tab's root splitter is larger than the window's tabview.
    const BOOL outstandingResize =
    [tabs anyWithBlock:^BOOL(PTYTab *tab) {
        return [[[tab realParentWindow] uniqueTmuxControllers] anyWithBlock:^BOOL(TmuxController *controller) {
            return [controller hasOutstandingWindowResize];
        }];
    }];
    if (outstandingResize) {
        DLog(@"adjustWindowSizeIfNeededForTabs: One of the tabs has a tmux controller with an outstanding window resize. Don't update layouts.");
        return;
    }
    // If there are no outstanding window resizes then setTmuxLayout:tmuxController:
    // has called fitWindowToTabs:, and it's still too big, so shrink
    // the layout.

    DLog(@"adjustWindowSizeIfNeededForTabs: Tab's root splitter is oversize. Fit layout to windows");
    [self fitLayoutToWindows];
}

- (void)sessionChangedTo:(NSString *)newSessionName sessionId:(int)sessionid {
    self.sessionGuid = nil;
    self.sessionName = newSessionName;
    sessionId_ = sessionid;
    _paneToActivateWhenCreated = -1;
    _detaching = YES;
    [self closeAllPanes];
    _detaching = NO;
    [self openWindowsInitial];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerAttachedSessionDidChange
                                                        object:nil];
}

- (void)sessionsChanged {
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

- (void)session:(int)sessionId renamedTo:(NSString *)newName {
    if (sessionId == sessionId_) {
        self.sessionName = newName;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionWasRenamed
                                                        object:@[ @(sessionId), newName ?: @"", self ]];
}

- (void)windowWasRenamedWithId:(int)wid to:(NSString *)newName {
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowWasRenamed
                                                        object:@[ @(wid), newName ?: @"", self ]];
}

- (void)windowsChanged
{
    [[NSNotificationCenter defaultCenter]  postNotificationName:kTmuxControllerWindowsChangeNotification
                                                         object:self];
}

- (NSArray *)listWindowFields {
    NSArray<NSString *> *basic = @[@"session_name", @"window_id",
                                   @"window_name", @"window_width", @"window_height",
                                   @"window_layout", @"window_flags", @"window_active"];
    if (![self versionAtLeastDecimalNumberWithString:@"2.2"]) {
        return basic;
    }
    return [basic arrayByAddingObject:@"window_visible_layout"];
}

- (NSSet<NSObject<NSCopying> *> *)savedAffinitiesForWindow:(NSString *)value {
    return [affinities_ valuesEqualTo:value];
}

- (void)initialListWindowsResponse:(NSString *)response {
    DLog(@"initialListWindowsResponse called");
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields] workAroundTabBug:_shouldWorkAroundTabBug];
    if (!doc) {
        DLog(@"Failed to parse %@", response);
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for initial list windows request: %@", response]];
        return;
    }
    NSMutableArray<NSArray *> *windowsToOpen = [NSMutableArray array];
    BOOL haveHidden = NO;
    NSNumber *newWindowAffinity = nil;
    const iTermOpenTmuxWindowsMode openWindowsMode = [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn];
    const BOOL newWindowsInTabs = openWindowsMode == kOpenTmuxWindowsAsNativeTabsInNewWindow;
    DLog(@"Iterating records...");
    for (NSArray *record in doc.records) {
        DLog(@"Consider record %@", record);
        const int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        if (hiddenWindows_ && [hiddenWindows_ containsObject:[NSNumber numberWithInt:wid]]) {
            DLog(@"Don't open window %d because it was saved hidden.", wid);
            haveHidden = YES;
            // Let the user know something is up.
            continue;
        }
        DLog(@"Will open %d as it was not saved hidden", wid);
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
        tooMany = YES;
        // Save that these windows are hidden so the UI will be consistent next time you attach.
        NSArray<NSNumber *> *wids = [windowsToOpen mapWithBlock:^NSNumber *(NSArray *record) {
            const int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
            return @(wid);
        }];
        [self hideWindows:wids andCloseTabs:NO];
        [windowsToOpen removeAllObjects];
    }
    [[TmuxDashboardController sharedInstance] didAttachWithHiddenWindows:haveHidden tooManyWindows:tooMany];
    if (tooMany) {
        [[iTermNotificationController sharedInstance] notify:@"Too many tmux windows!" withDescription:@"Use the tmux dashboard to select which to open."];
    } else if (haveHidden) {
        [[iTermNotificationController sharedInstance] notify:@"Some tmux windows were hidden." withDescription:@"Use the tmux dashboard to select which to open."];
    }
    for (NSArray *record in windowsToOpen) {
        DLog(@"Open window %@", record);
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        [self openWindowWithIndex:wid
                             name:[[doc valueInRecord:record forField:@"window_name"] it_unescapedTmuxWindowName]
                             size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                             [[doc valueInRecord:record forField:@"window_height"] intValue])
                           layout:[doc valueInRecord:record forField:@"window_layout"]
                    visibleLayout:[doc valueInRecord:record forField:@"window_visible_layout"]
                       affinities:[self savedAffinitiesForWindow:[NSString stringWithInt:wid]]
                      windowFlags:[doc valueInRecord:record forField:@"window_flags"]
                          profile:[self sharedProfile]
                          initial:YES
                         tabIndex:nil];
    }
    if (windowsToOpen.count == 0) {
        DLog(@"Did not open any windows so turn on accept notifications in tmux gateway");
        gateway_.acceptNotifications = YES;
        [self sendInitialWindowsOpenedNotificationIfNeeded];
    }
    _allInitialWindowsAdded = YES;
}

- (void)openWindowsInitial {
    _allInitialWindowsAdded = NO;
    DLog(@"openWindowsInitial\n%@", [NSThread callStackSymbols]);
    if (!_versionKnown) {
        DLog(@"Don't know version yet");
        _wantsOpenWindowsInitial = YES;
        return;
    }
    NSString *command = [NSString stringWithFormat:@"show -v -q -t $%d @iterm2_size", sessionId_];
    [gateway_ sendCommand:command
           responseTarget:self
         responseSelector:@selector(handleShowSize:)];
}

- (void)handleShowSize:(NSString *)response {
    DLog(@"handleShowSize: %@", response);
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
    DLog(@"openWindowsOfSize: %@", VT100GridSizeDescription(size));

    // There's a (hopefully) minor race condition here. When we initially connect to
    // a session we get its @iterm2_id. If one doesn't exist, it is assigned. This
    // lets us know if a single instance of iTerm2 is trying to attach to the same
    // session twice. A really evil user could attach twice to the same session
    // simultaneously, and we'd get the value twice, see it's empty twice, and set
    // it twice, causing chaos. Or two separate instances of iTerm2 attaching
    // simultaneously could also hit this race. The consequence of this race
    // condition is easily recovered from by reattaching.
    [_windowSizes removeAllObjects];
    NSString *getSessionGuidCommand = [NSString stringWithFormat:@"show -v -q -t $%d @iterm2_id",
                                       sessionId_];
    size.height = [self adjustHeightForStatusBar:size.height];
    if (size.width < 2) {
        size.width = 2;
    }
    if (size.height < 2) {
        size.height = 2;
    }
    // NOTE: setSizeCommand only set when variable window sizes are not in use.
    NSString *setSizeCommand = [NSString stringWithFormat:@"refresh-client -C %d,%d",
                                size.width, size.height];
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@", [self listWindowsDetailedFormat]];
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_id} #{session_name}\"";
    NSString *getAffinitiesCommand = [NSString stringWithFormat:@"show -v -q -t $%d @affinities", sessionId_];
    NSString *getPerWindowSettingsCommand = [NSString stringWithFormat:@"show -v -q -t $%d @per_window_settings", sessionId_];
    NSString *getPerTabSettingsCommand = [NSString stringWithFormat:@"show -v -q -t $%d @per_tab_settings", sessionId_];
    NSString *getBuriedIndexesCommand = [NSString stringWithFormat:@"show -v -q -t $%d @buried_indexes", sessionId_];
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
                                        flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getHiddenWindowsCommand
                                           responseTarget:self
                                         responseSelector:@selector(getHiddenWindowsResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getBuriedIndexesCommand
                                           responseTarget:self
                                         responseSelector:@selector(getBuriedIndexesResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getAffinitiesCommand
                                           responseTarget:self
                                         responseSelector:@selector(getAffinitiesResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getPerWindowSettingsCommand
                                           responseTarget:self
                                         responseSelector:@selector(getPerWindowSettingsResponse:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:getPerTabSettingsCommand
                                           responseTarget:self
                                         responseSelector:@selector(getPerTabSettingsResponse:)
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
    [gateway_ sendCommandList:[commands filteredArrayUsingBlock:^BOOL(id anObject) {
        return ![anObject isKindOfClass:[NSNull class]];
    }]];
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
        return;
    }
    if ([self.attachedSessionGuids containsObject:sessionGuid]) {
        [self.gateway doubleAttachDetectedForSessionGUID:sessionGuid];
        if ([self.attachedSessionGuids containsObject:sessionGuid]) {
            // Delegate did not choose to force disconnect other, so we say goodbye.
            TmuxGateway *gateway = gateway_;
            [self detach];
            [gateway forceDetach];
            return;
        }
    }
    // This is the only one.
    self.sessionGuid = sessionGuid;
}

- (NSNumber *)_keyForWindowPane:(int)windowPane
{
    return [NSNumber numberWithInt:windowPane];
}

- (PTYSession<iTermTmuxControllerSession> *)sessionForWindowPane:(int)windowPane
{
    return [windowPanes_ objectForKey:[self _keyForWindowPane:windowPane]];
}

- (void)registerSession:(PTYSession<iTermTmuxControllerSession> *)aSession
               withPane:(int)windowPane
               inWindow:(int)window {
    PTYTab *tab = [aSession.delegate.realParentWindow tabForSession:aSession];
    ITCriticalError(tab != nil, @"nil tab for session %@ with delegate %@ with realparentwindow %@",
                    aSession, aSession.delegate, aSession.delegate.realParentWindow);
    if (tab) {
        [self retainWindow:window withTab:tab];
        [windowPanes_ setObject:aSession forKey:[self _keyForWindowPane:windowPane]];
        void (^call)(PTYSession<iTermTmuxControllerSession> *) = _when[@(windowPane)];
        if (call) {
            dispatch_async(dispatch_get_main_queue(), ^{
                call(aSession);
            });
            [_when removeObjectForKey:@(windowPane)];
        }
        if (_paneToActivateWhenCreated == windowPane) {
            [aSession revealIfTabSelected];
            _paneToActivateWhenCreated = -1;
        }
    }
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane session:(id)session
{
    id key = [self _keyForWindowPane:windowPane];
    if (windowPanes_[key] == session) {
        [self releaseWindow:window];
        [windowPanes_ removeObjectForKey:key];
        [_when removeObjectForKey:@(windowPane)];
    }
}

- (void)whenPaneRegistered:(int)wp call:(void (^)(PTYSession<iTermTmuxControllerSession> *))block {
    PTYSession<iTermTmuxControllerSession> *already = [self sessionForWindowPane:wp];
    if (already) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(already);
        });
        return;
    }

    _when[@(wp)] = [block copy];
}

- (PTYTab *)window:(int)window {
    return _windowStates[@(window)].tab;
}

- (NSArray<PTYSession<iTermTmuxControllerSession> *> *)sessionsInWindow:(int)window {
    return [[self window:window] sessions];
}

- (BOOL)isAttached
{
    return !detached_;
}

- (void)requestDetach {
    if (self.gateway.detachSent) {
        if ([self.gateway.delegate tmuxGatewayShouldForceDetach]) {
            [self.gateway forceDetach];
        }
    } else {
        [self.gateway detach];
    }
}

- (void)detach {
    DLog(@"%@: detach", self);
    self.sessionGuid = nil;
    [listSessionsTimer_ invalidate];
    listSessionsTimer_ = nil;
    detached_ = YES;
    [self closeAllPanes];
    gateway_ = nil;
    [_when enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, void (^ _Nonnull obj)(PTYSession<iTermTmuxControllerSession> *), BOOL * _Nonnull stop) {
        obj(nil);
    }];
    [_when removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDetachedNotification
                                                        object:self];
    [[TmuxControllerRegistry sharedInstance] setController:nil
                                                 forClient:self.clientName];
}

- (void)windowDidResize:(NSWindowController<iTermWindowController> *)term {
    if (term.closing) {
        return;
    }
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
        if (size.width > 0 && size.height > 0) {
            minSize.width = MIN(minSize.width, size.width);
            DLog(@"Ignore tab %@ with size of 0", tab);
            minSize.height = MIN(minSize.height, size.height);
        }
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
        DLog(@"Set client size to %@", NSStringFromSize(size));
        NSValue *sizeValue = [NSValue valueWithSize:size];
        if ([_windowSizes[@(window.intValue)] isEqual:sizeValue]) {
            DLog(@"It's already that size. Do nothing.");
            return nil;
        }
        _windowSizes[@(window.intValue)] = sizeValue;
        NSString *command;
        if ([self refreshClientSupportsWindowArgument]) {
            command = [NSString stringWithFormat:@"refresh-client -C @%d:%dx%d", window.intValue, (int)size.width, (int)size.height];
        } else {
            command = [NSString stringWithFormat:@"resize-window -x %@ -y %@ -t @%d", @((int)size.width), @((int)size.height), window.intValue];
        }
        NSDictionary *dict = [gateway_ dictionaryForCommand:command
                                             responseTarget:self
                                           responseSelector:@selector(handleResizeWindowResponse:)
                                             responseObject:nil
                                                      flags:kTmuxGatewayCommandShouldTolerateErrors];
        return dict;
    }];
}

- (BOOL)refreshClientSupportsWindowArgument {
    // https://github.com/tmux/tmux/issues/2594
    return [self versionAtLeastDecimalNumberWithString:@"3.4"];
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
    DLog(@"TmuxController setClientSize: Set client size to %@ from\n%@", NSStringFromSize(size), [NSThread callStackSymbols]);
    DLog(@"%@", [NSThread callStackSymbols]);
    assert(size.width > 0 && size.height > 0);
    lastSize_ = size;
    NSString *listStr = [self commandToListWindows];
    NSString *setSizeCommand = [NSString stringWithFormat:@"set -t $%d @iterm2_size %d,%d",
                                sessionId_, (int)size.width, (int)size.height];
    const int height = [self adjustHeightForStatusBar:(int)size.height];
    ITBetaAssert(height > 0, @"Invalid size");
    [_windowSizes removeAllObjects];
    NSArray *commands = [NSArray arrayWithObjects:
                         [gateway_ dictionaryForCommand:setSizeCommand
                                         responseTarget:nil
                                       responseSelector:nil
                                         responseObject:nil
                                                  flags:0],
                         [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"refresh-client -C %d,%d",
                                                         (int)size.width, height]
                                         responseTarget:nil
                                       responseSelector:nil
                                         responseObject:nil
                                                  flags:kTmuxGatewayCommandShouldTolerateErrors],
                         [gateway_ dictionaryForCommand:listStr
                                         responseTarget:self
                                       responseSelector:@selector(listWindowsResponse:)
                                         responseObject:nil
                                                  flags:0],
                         nil];
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommandList:commands];
}

- (void)sendControlC {
    [gateway_ sendCommand:[NSString stringWithFormat:@"%cphony-command", 3]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)ping {
    // This command requires tmux 3.2, but if it fails that's OK too.
    [gateway_ sendCommand:@"refresh-client -fpause-after=0,wait-exit"
           responseTarget:self
         responseSelector:@selector(handlePingResponse:)
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)handlePingResponse:(NSString *)ignore {
}

- (void)enablePauseModeIfPossible {
    DLog(@"enablePauseModeIfPossible min=%@ max=%@", gateway_.minimumServerVersion, gateway_.maximumServerVersion);
    if (gateway_.minimumServerVersion &&
        [gateway_.minimumServerVersion compare:[NSDecimalNumber decimalNumberWithString:@"3.2"]] == NSOrderedAscending) {
        DLog(@"min < 3.2");
        return;
    }
    if (!gateway_.minimumServerVersion) {
        DLog(@"have no min version");
        return;
    }
    NSUInteger catchUpTime = [iTermPreferences unsignedIntegerForKey:kPreferenceKeyTmuxPauseModeAgeLimit];
    gateway_.pauseModeEnabled = YES;
    const NSInteger age = MAX(1, round(catchUpTime));
    DLog(@"Enable pause-after=%@", @(age));
    [gateway_ sendCommand:[NSString stringWithFormat:@"refresh-client -fpause-after=%@", @(age)]
           responseTarget:nil
         responseSelector:nil];
    _tmuxBufferMonitor = [[iTermTmuxBufferSizeMonitor alloc] initWithController:self
                                                                       pauseAge:age];
    _tmuxBufferMonitor.delegate = self;
}

- (void)didPausePane:(int)wp {
    [_tmuxBufferMonitor resetPane:wp];
}

- (void)unpausePanes:(NSArray<NSNumber *> *)wps {
    if (!gateway_.pauseModeEnabled) {
        return;
    }
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
    windowOpener.unicodeVersion = self.unicodeVersion;
    windowOpener.maxHistory =
        MAX([[gateway_ delegate] tmuxClientSize].height,
            [[gateway_ delegate] tmuxNumberOfLinesOfScrollbackHistory]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.target = self;
    windowOpener.selector = @selector(panesDidUnpause:);
    windowOpener.shouldWorkAroundTabBug = _shouldWorkAroundTabBug;

    windowOpener.minimumServerVersion = self.gateway.minimumServerVersion;
    [windowOpener unpauseWindowPanes:wps];
}

- (void)panesDidUnpause:(TmuxWindowOpener *)opener {
    for (NSNumber *wp in opener.unpausingWindowPanes) {
        PTYSession<iTermTmuxControllerSession> *session = [self sessionForWindowPane:wp.intValue];
        [session setTmuxHistory:[opener historyLinesForWindowPane:wp.intValue alternateScreen:NO]
                     altHistory:[opener historyLinesForWindowPane:wp.intValue alternateScreen:YES]
                          state:[opener stateForWindowPane:wp.intValue]];
    }
}

- (void)pausePanes:(NSArray<NSNumber *> *)wps {
    if (!gateway_.pauseModeEnabled) {
        return;
    }
    NSString *adjustments = [[wps mapWithBlock:^id(NSNumber *anObject) {
        return [NSString stringWithFormat:@"%%%@:pause", anObject];
    }] componentsJoinedByString:@" "];
    NSString *command = [NSString stringWithFormat:@"refresh-client -A '%@'", adjustments];
    [self.gateway sendCommand:command responseTarget:self responseSelector:@selector(didPause:panes:) responseObject:wps flags:0];
}

- (void)didPause:(NSString *)result panes:(NSArray<NSNumber *> *)wps {
    for (NSNumber *wp in wps) {
        [self.gateway.delegate tmuxWindowPaneDidPause:wp.intValue
                                         notification:NO];
    }
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
    [gateway_ sendCommand:@"show-option -q -g -v focus-events"
           responseTarget:self
         responseSelector:@selector(handleFocusEventsResponse:)];
}

- (void)handleStatusResponse:(NSString *)string {
    _hasStatusBar = [string isEqualToString:@"on"];
}

- (void)handleFocusEventsResponse:(NSString *)string {
    _focusEvents = [string isEqualToString:@"on"];
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

- (void)loadDefaultTerminal {
    NSString *command = @"show-options -v -s default-terminal";
    [self.gateway sendCommand:command
               responseTarget:self
             responseSelector:@selector(didFetchDefaultTerminal:)
               responseObject:nil
                        flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)didFetchDefaultTerminal:(NSString *)defaultTerminal {
    if (defaultTerminal.length > 0)  {
        _defaultTerminal = [defaultTerminal copy];
    }
}

- (void)loadTitleFormat {
    NSDecimalNumber *v2_9 = [NSDecimalNumber decimalNumberWithString:@"2.9"];
    if ([gateway_.minimumServerVersion compare:v2_9] == NSOrderedAscending) {
        DLog(@"tmux not new enough to use set-titles");
        return;
    }

    [gateway_ sendCommandList:@[ [gateway_ dictionaryForCommand:@"show-options -v -g set-titles"
                                                 responseTarget:self
                                               responseSelector:@selector(handleShowSetTitles:)
                                                 responseObject:nil
                                                          flags:0] ]];
}

- (void)loadKeyBindings {
    [gateway_ sendCommand:@"list-keys" responseTarget:self responseSelector:@selector(handleListKeys:)];
}

// If there's an error in tmux.conf then tmux will put you in copy mode initially and that breaks
// handling keyboard input. This is harmless in the normal case.
// https://github.com/tmux/tmux/issues/3193
- (void)exitCopyMode {
    [gateway_ sendCommand:@"copy-mode -q"
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

// This is a little brittle because it depends on parsing bind-keys commands
// which could change in the future. It'd be nice for list-keys to have
// structured output.
- (void)handleListKeys:(NSString *)response {
    NSArray<NSString *> *lines = [response componentsSeparatedByString:@"\n"];
    NSArray<NSDictionary *> *dicts = [lines mapWithBlock:^id (NSString * _Nonnull line) {
        NSArray<NSString *> *args = [line componentsSeparatedByRegex:@"  *"];
        NSInteger skip = 0;
        NSString *key = nil;
        NSString *command = nil;
        NSString *flag = nil;
        NSMutableDictionary<NSString *, id> *flags = [NSMutableDictionary dictionary];
        for (NSInteger i = 1; i < args.count; i++) {
            if (skip > 0) {
                NSArray<NSString *> *flagArgs = flags[flag];
                flags[flag] = [flagArgs arrayByAddingObject:args[i]];
                skip -= 1;
                continue;
            }
            flag = nil;
            if ([args[i] hasPrefix:@"-"] && args[i].length > 1) {
                flag = [args[i] substringFromIndex:1];
                if ([args[i] isEqualToString:@"-N"]) {
                    skip = 1;
                } else if ([args[i] isEqualToString:@"-T"]) {
                    skip = 1;
                } else {
                    skip = 0;
                }
                if (skip == 0) {
                    flags[flag] = [NSNull null];
                } else {
                    flags[flag] = @[];
                }
                // Skip flag and any arguments.
                continue;
            }
            if (key == nil) {
                key = args[i];
                continue;
            }
            command = [[args subarrayFromIndex:i] componentsJoinedByString:@" "];
            break;
        }
        if (!key || !command || !flags) {
            DLog(@"Bad line: %@", line);
            return nil;
        }
        return @{ @"key": key,
                  @"command": command,
                  @"flags": flags };
    }];
    NSArray<NSString *> *forbiddenCommands = @[
        @"bind-key",
        @"choose-buffer",
        @"choose-client",
        @"choose-tree",
        @"clear-history",
        @"clock-mode",
        @"command-prompt",
        @"confirm-before",
        @"copy-mode",
        @"customize-mode",
        @"display-menu",
        @"display-message",
        @"display-panes",
        @"display-popup",
        @"find-window",
        @"list-buffers",
        @"list-clients",
        @"list-commands",
        @"list-keys",
        @"list-panes",
        @"list-sessions",
        @"list-windows",
        @"show-buffer",
        @"show-messages",
        @"unbind-key",
    ];
    dicts = [dicts filteredArrayUsingBlock:^BOOL(NSDictionary *dict) {
        NSString *command = [[dict[@"command"] componentsSeparatedByString:@" "] firstObject];
        return [dict[@"flags"][@"T"] isEqual:@[@"prefix"]] && ![forbiddenCommands containsObject:command];
    }];
    NSMutableDictionary *fakeProfile = [@{ KEY_KEYBOARD_MAP: _sharedKeyMappingOverrides } mutableCopy];

    for (NSDictionary *dict in dicts) {
        iTermKeystroke *keystroke = [iTermKeystroke withTmuxKey:dict[@"key"]];
        if (!keystroke) {
            DLog(@"Couldn't make keystroke for %@", dict);
            continue;
        }

        iTermKeyBindingAction *action = [iTermKeyBindingAction withAction:KEY_ACTION_SEND_TMUX_COMMAND
                                                                parameter:dict[@"command"]
                                                                 escaping:iTermSendTextEscapingNone
                                                                applyMode:iTermActionApplyModeCurrentSession];
        NSString *dictKey = [keystroke keyInBindingDictionary:fakeProfile[KEY_KEYBOARD_MAP]];
        NSInteger index = NSNotFound;
        if (dictKey) {
            index = [[iTermKeyMappings sortedKeystrokesForProfile:fakeProfile] indexOfObject:keystroke];
        }
        [iTermKeyMappings setMappingAtIndex:index
                               forKeystroke:keystroke
                                     action:action
                                  createNew:index == NSNotFound
                                  inProfile:fakeProfile];
    }

    _sharedKeyMappingOverrides = fakeProfile[KEY_KEYBOARD_MAP];
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
                           [gateway_ dictionaryForCommand:@"list-windows -F \"#{pid}\""
                                           responseTarget:self
                                         responseSelector:@selector(guessVersion21Response:)
                                           responseObject:nil
                                                    flags:kTmuxGatewayCommandShouldTolerateErrors],
                           [gateway_ dictionaryForCommand:@"show-options -g message-style"  // message-style added in 1.9
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
    DLog(@"handleDisplayMessageVersion: %@", response);
    if ([response isEqualToString:@"openbsd-7.1"]) {
        [self handleDisplayMessageVersion:@"3.4"];
        return;
    }
    if ([response isEqualToString:@"openbsd-6.8"]) {
        [self handleDisplayMessageVersion:@"3.2"];
        return;
    }
    if ([response isEqualToString:@"openbsd-6.7"]) {
        [self handleDisplayMessageVersion:@"3.0"];
        return;
    }
    NSString *openbsdPrefix = @"openbsd-";
    if ([response hasPrefix:openbsdPrefix]) {
        NSString *suffix = [response substringFromIndex:openbsdPrefix.length];
        NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:suffix];
        if (number) {
            if ([number compare:[NSDecimalNumber decimalNumberWithString:@"7.1"]] != NSOrderedAscending) {
                // version >= 7.1
                [self handleDisplayMessageVersion:@"3.4"];
            }
            // version < 7.1
            [self handleDisplayMessageVersion:@"3.2"];
        } else {
            // This should never happen (decimalNumberWithString returns a nonnil value)
            [self handleDisplayMessageVersion:@"3.2"];
        }
        return;
    }
    // openbsd-6.6 and earlier are never reported; you just get an empty string.
    if (response.length == 0) {
        // The "version" format was first added in 2.4
        [self decreaseMaximumServerVersionTo:@"2.3"];
        return;
    }

    if ([response isEqualToString:@"next-3.4"]) {
        // Work around a bug where tmux sends \t instead of tab in list-windows response.
        _shouldWorkAroundTabBug = YES;
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
    DLog(@"response=%@", response);
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:response];
    DLog(@"number=%@", number);
    if (number.doubleValue != number.doubleValue ||
        number.doubleValue < 2.4 || number.doubleValue > 10) {
        DLog(@"nan or out of bounds, do nothing.");
        return;
    }
    
    // Sadly tmux version numbers look like 2.9 or 2.9a instead of a proper decimal number.
    NSRange range = [response rangeOfCharacterFromSet:[NSCharacterSet lowercaseLetterCharacterSet]];
    DLog(@"Use range %@", NSStringFromRange(range));
    if (range.location == NSNotFound) {
        DLog(@"Normal case: increase min version to %@", response);
        [self increaseMinimumServerVersionTo:response];
    } else {
        // Convert 2.9a to 2.91
        // According to this issue it should be safe to do this:
        // https://github.com/tmux/tmux/issues/1712
        unichar c = [response characterAtIndex:range.location];
        NSInteger bug = c - 'a' + 1;
        NSString *prefix = [response substringToIndex:range.location];
        NSString *version = [NSString stringWithFormat:@"%@%@", prefix, @(bug)];
        DLog(@"dot-release. Increase min version to %@", version);
        [self increaseMinimumServerVersionTo:version];
    }

    if (gateway_.minimumServerVersion.doubleValue >= 2.9 && [iTermAdvancedSettingsModel tmuxVariableWindowSizesSupported]) {
        _variableWindowSize = YES;
    }

    _versionDetected = YES;
    [self didGuessVersion];
}

- (void)guessVersion23Response:(NSString *)response {
    if (_versionDetected) {
        DLog(@"Version already detected.");
        return;
    }
    DLog(@"guessVersion23Response");
    if (response == nil) {
        [self decreaseMaximumServerVersionTo:@"2.2"];
    } else {
        [self increaseMinimumServerVersionTo:@"2.3"];
    }
}

- (void)guessVersion22Response:(NSString *)response {
    if (_versionDetected) {
        DLog(@"Version already detected.");
        return;
    }
    DLog(@"guessVersion22Response");
    const NSInteger index = [response rangeOfCharacterFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]].location;
    if (index == NSNotFound) {
        [self decreaseMaximumServerVersionTo:@"2.1"];
    } else {
        [self increaseMinimumServerVersionTo:@"2.2"];
    }
}

- (void)guessVersion21Response:(NSString *)response {
    if (_versionDetected) {
        DLog(@"Version already detected.");
        return;
    }
    DLog(@"guessVersion21Response");
    if (response.length == 0) {
        [self decreaseMaximumServerVersionTo:@"2.0"];
    } else {
        [self increaseMinimumServerVersionTo:@"2.1"];
    }
}

- (void)guessVersion18Response:(NSString *)response {
    if (_versionDetected) {
        DLog(@"Version already detected.");
        return;
    }
    DLog(@"guessVersion18Response");
    if (response != nil) {
        [self increaseMinimumServerVersionTo:@"1.9"];
    } else {
        [self decreaseMaximumServerVersionTo:@"1.8"];
    }

    // This is the oldest version supported. By the time you get here you know the version.
    [self didGuessVersion];
}

// Actions to perform after the version number is known.
- (void)didGuessVersion {
    DLog(@"didGuessVersion");
    [self enablePauseModeIfPossible];
    [self loadServerPID];
    [self loadTitleFormat];
    _versionKnown = YES;
    if (_wantsOpenWindowsInitial) {
        _wantsOpenWindowsInitial = NO;
        [self openWindowsInitial];
    }
}

- (BOOL)versionAtLeastDecimalNumberWithString:(NSString *)string {
    return [gateway_ versionAtLeastDecimalNumberWithString:string];
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
    NSString *listStr = [self commandToListWindows];
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
       initialDirectory:(iTermInitialDirectory *)initialDirectory
             completion:(void (^)(int wp))completion {
    // No need for a callback. We should get a layout-changed message and act on it.
    __weak __typeof(self) weakSelf = self;
    [initialDirectory tmuxSplitWindowCommand:wp
                                  vertically:splitVertically
                          recyclingSupported:self.recyclingSupported
                                       scope:scope
                                  completion:
     ^(NSString *command) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        TmuxGateway *gateway = strongSelf->gateway_;
        if (!completion) {
            [gateway sendCommand:command responseTarget:nil responseSelector:nil];
            return;
        }

        // Get the list of panes, then split, then get the list of panes again.
        // This seems to be the only way to get the pane ID of the new pane.
        NSString *listPanesCommand = [NSString stringWithFormat:@"list-panes -t %%%d -F '#{pane_id}'", wp];
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        state[iTermTmuxControllerSplitStateCompletion] = [completion copy];
        NSDictionary *initialListPanes = [gateway dictionaryForCommand:listPanesCommand
                                                        responseTarget:self
                                                      responseSelector:@selector(recordPanes:state:)
                                                        responseObject:state
                                                                 flags:0];
        NSDictionary *split = [gateway dictionaryForCommand:command
                                             responseTarget:nil
                                           responseSelector:nil
                                             responseObject:nil
                                                      flags:kTmuxGatewayCommandShouldTolerateErrors];
        NSDictionary *followupListPanes = [gateway dictionaryForCommand:listPanesCommand
                                                         responseTarget:self
                                                       responseSelector:@selector(didSplit:state:)
                                                         responseObject:state
                                                                  flags:kTmuxGatewayCommandShouldTolerateErrors];
        [gateway sendCommandList:@[ initialListPanes, split, followupListPanes ]];
     }];
}

// Save pane list before splitting.
- (void)recordPanes:(NSString *)list state:(NSMutableDictionary *)state {
    state[iTermTmuxControllerSplitStateInitialPanes] = [NSSet setWithArray:[list componentsSeparatedByString:@"\n"]];
}

// Compute new window pane after splitting and run callback if any.
- (void)didSplit:(NSString *)list state:(NSMutableDictionary *)state {
    NSSet<NSString *> *after = [NSSet setWithArray:[list componentsSeparatedByString:@"\n"]];
    NSSet<NSString *> *before = state[iTermTmuxControllerSplitStateInitialPanes] ?: [NSSet set];
    NSMutableSet<NSString *> *additions = [after mutableCopy];
    [additions minusSet:before];
    void (^completion)(int) = state[iTermTmuxControllerSplitStateCompletion];
    if (additions.count == 0) {
        completion(-1);
        return;
    }
    if (additions.count > 1) {
        DLog(@"Multiple additions found! Picking one at random.");
    }
    NSString *string = [additions anyObject];
    if (![string hasPrefix:@"%"]) {
        completion(-1);
        return;
    }
    string = [string substringFromIndex:1];
    completion([string intValue]);
}

- (void)selectPane:(int)windowPane {
    if (_suppressActivityChanges) {
        DLog(@"Not sending select-pane -t %%%d because activity changes are suppressed", windowPane);
        return;
    }
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
    __weak __typeof(self) weakSelf = self;
    [initialDirectory tmuxNewWindowCommandInSessionNumber:sessionNumber
                                       recyclingSupported:self.recyclingSupported
                                                    scope:scope
                                               completion:
     ^(NSString *command) {
        [weakSelf didCreateWindowWithCommand:command];
    }];
}

- (void)didCreateWindowWithCommand:(NSString *)command {
    NSMutableArray *commands = [NSMutableArray array];
    if (_variableWindowSize) {
        Profile *profile = self.sharedProfile;
        NSSize size = NSMakeSize(MIN(iTermMaxInitialSessionSize,
                                     [profile[KEY_COLUMNS] intValue] ?: 80),
                                 MIN(iTermMaxInitialSessionSize,
                                     [profile[KEY_ROWS] intValue] ?: 25));
        ITBetaAssert((int)size.width > 0, @"Invalid size");
        const int height = [self adjustHeightForStatusBar:size.height];
        ITBetaAssert(height > 0, @"Invalid size");
        [_windowSizes removeAllObjects];
        NSString *setSizeCommand = [NSString stringWithFormat:@"refresh-client -C %d,%d",
                                    (int)size.width, height];
        [commands addObject:[gateway_ dictionaryForCommand:setSizeCommand
                                            responseTarget:nil
                                          responseSelector:nil
                                            responseObject:nil
                                                     flags:kTmuxGatewayCommandShouldTolerateErrors]];
    }
    [commands addObject:[gateway_ dictionaryForCommand:command
                                        responseTarget:nil
                                      responseSelector:nil
                                        responseObject:nil
                                                 flags:0]];
    [gateway_ sendCommandList:commands];
}

- (void)newWindowWithAffinity:(NSString *)windowIdString
                         size:(NSSize)size
             initialDirectory:(iTermInitialDirectory *)initialDirectory
                        index:(NSNumber *)index
                        scope:(iTermVariableScope *)scope
                   completion:(void (^)(int))completion {
    _manualOpenRequested = (windowIdString != nil);
    BOOL variableWindowSize = _variableWindowSize;
    __weak __typeof(self) weakSelf = self;
    [initialDirectory tmuxNewWindowCommandRecyclingSupported:self.recyclingSupported
                                                       scope:scope
                                                  completion:
     ^(NSString *command) {
        [weakSelf didCreateWindowWithAffinity:windowIdString
                                      command:command
                           variableWindowSize:variableWindowSize
                                         size:size
                                        index:index
                                   completion:completion];
    }];
}

- (void)didCreateWindowWithAffinity:(NSString *)windowIdString
                            command:(NSString *)command
                 variableWindowSize:(BOOL)variableWindowSize
                               size:(NSSize)size
                              index:(NSNumber *)index
                         completion:(void (^)(int))completion {
    if (detached_) {
        return;
    }
    NSMutableArray *commands = [NSMutableArray array];
    if (variableWindowSize) {
        ITBetaAssert((int)size.width > 0, @"Invalid size");
        const int height = [self adjustHeightForStatusBar:size.height];
        ITBetaAssert(height > 0, @"Invalid size");
        [_windowSizes removeAllObjects];
        NSString *setSizeCommand = [NSString stringWithFormat:@"refresh-client -C %d,%d",
                                    (int)size.width, height];
        [commands addObject:[gateway_ dictionaryForCommand:setSizeCommand
                                            responseTarget:nil
                                          responseSelector:nil
                                            responseObject:nil
                                                     flags:kTmuxGatewayCommandShouldTolerateErrors]];
    }
    [commands addObject:[gateway_ dictionaryForCommand:command
                                        responseTarget:self
                                      responseSelector:@selector(newWindowWithAffinityCreated:affinityWindowAndCompletion:)
                                        responseObject:[iTermTriple tripleWithObject:windowIdString
                                                                           andObject:[completion copy]
                                                                              object:index]
                                                 flags:0]];
    [gateway_ sendCommandList:commands];
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
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandOfferToDetachIfLaggyDuplicate | kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)unlinkWindowWithId:(int)windowId {
    [gateway_ sendCommand:[NSString stringWithFormat:@"unlink-window -k -t @%d", windowId]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSString *)stringByEscapingBackslashesAndRemovingNewlines:(NSString *)name {
    return [[name stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
}

- (void)setWindowTitleOverride:(NSString *)title
                        window:(int)windowId {
    [self renameWindowWithId:windowId inSessionNumber:nil toName:title];
    [self savePerTabSettings];
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
    NSString *theCommand = [NSString stringWithFormat:@"select-pane -t %%%d -T \"%@\"",
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
    return [[NSString alloc] initWithData:[[string substringFromIndex:prefix.length] dataFromHexValues]
                                 encoding:NSUTF8StringEncoding];
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
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)sendCommandToSetTabColors {

    NSString *command = [NSString stringWithFormat:@"set -t $%d @tab_colors \"%@\"",
                         sessionId_, [self encodedString:[self.tabColorsString stringByEscapingQuotes]
                                                  prefix:iTermTmuxControllerEncodingPrefixTabColors]];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSDictionary *)hotkeyForWindowPane:(int)windowPane {
    return _hotkeys[@(windowPane)];
}

- (NSString *)tabColorStringForWindowPane:(int)windowPane {
    return _tabColors[@(windowPane)];
}

- (void)killWindow:(int)window {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermTmuxControllerWillKillWindow object:@(window)];
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-window -t @%d", window]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandOfferToDetachIfLaggyDuplicate | kTmuxGatewayCommandShouldTolerateErrors];
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
    [self breakOutWindowPane:windowPane toTabAside:iTermTmuxControllerPhonyAffinity];
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
        if ([windowGuid isEqualToString:iTermTmuxControllerPhonyAffinity]) {
            _pendingWindows[@(windowId.intValue)] = [iTermTmuxPendingWindow trivialInstance];
        } else {
            [affinities_ setValue:windowGuid equalToValue:windowId];
        }
    }
}

- (BOOL)windowIsHidden:(int)windowId {
    return [hiddenWindows_ containsObject:@(windowId)];
}

- (void)hideWindow:(int)windowId {
    [self hideWindows:@[ @(windowId) ] andCloseTabs:YES];
}

- (NSString *)terminalGUIDForWindowID:(int)wid {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        for (PTYTab *tab in term.tabs) {
            if (tab.isTmuxTab && tab.tmuxController == self && tab.tmuxWindow == wid) {
                return term.terminalGuid;
            }
        }
    }
    return nil;
}

- (void)setWindowID:(int)wid buriedFromTerminalGUID:(NSString *)terminalGUID tabIndex:(int)tabIndex {
    DLog(@"set %@ = %@", @(wid), terminalGUID);
    NSMutableArray<iTermTuple<NSNumber *, NSNumber *> *> *wids = _buriedWindows[terminalGUID];
    if (!wids) {
        wids = [NSMutableArray array];
        _buriedWindows[terminalGUID] = wids;
    }
    if (![wids objectPassingTest:^BOOL(iTermTuple<NSNumber *,NSNumber *> *element, NSUInteger index, BOOL *stop) {
        return [element.firstObject isEqual:@(wid)];
    }]) {
        [wids addObject:[iTermTuple tupleWithObject:@(wid) andObject:@(tabIndex)]];
    }
}

- (int)tabIndexOfWindowID:(int)wid {
    for (PseudoTerminal *term in [[iTermController sharedInstance] terminals]) {
        int i = 0;
        for (PTYTab *tab in term.tabs) {
            if (tab.isTmuxTab && tab.tmuxController == self && tab.tmuxWindow == wid) {
                return i;
            }
            i += 1;
        }
    }
    return -1;
}

- (void)hideWindows:(NSArray<NSNumber *> *)windowIDs andCloseTabs:(BOOL)closeTabs {
    DLog(@"hideWindow: Add these window IDs to hidden: %@", windowIDs);
    if (closeTabs) {
        DLog(@"burying window IDs %@", [[windowIDs mapWithBlock:^id(NSNumber *anObject) {
            return [anObject description];
        }] componentsJoinedByString:@", "]);
        // Update _buriedWindows
        [windowIDs enumerateObjectsUsingBlock:^(NSNumber * _Nonnull wid, NSUInteger idx, BOOL * _Nonnull stop) {
            NSString *terminalGUID = [self terminalGUIDForWindowID:wid.intValue];
            if (!terminalGUID) {
                return;
            }
            [self setWindowID:wid.intValue buriedFromTerminalGUID:terminalGUID tabIndex:[self tabIndexOfWindowID:wid.intValue]];
        }];
    }
    [hiddenWindows_ addObjectsFromArray:windowIDs];
    [self saveHiddenWindows];
    if (closeTabs) {
        for (NSNumber *widNumber in windowIDs) {
            const int windowId = widNumber.intValue;
            PTYTab *theTab = [self window:windowId];
            if (theTab) {
                [[theTab realParentWindow] closeTab:theTab soft:YES];
            }
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDidChangeHiddenWindows object:self];
}

- (void)openWindowWithId:(int)windowId
              affinities:(NSArray *)affinities
             intentional:(BOOL)intentional
                 profile:(Profile *)profile {
    if (intentional) {
        DLog(@"open intentional: Remove this window ID from hidden: %d", windowId);
        if (!_pendingWindows[@(windowId)]) {
            // This indicates that the window's opening is originated by the app (it is not
            // "anonymous"), as opposed to running `tmux new-window` at the command line.
            DLog(@"Force intentional");
            _pendingWindows[@(windowId)] = [iTermTmuxPendingWindow trivialInstance];
        }
        [hiddenWindows_ removeObject:[NSNumber numberWithInt:windowId]];
        [self saveHiddenWindows];
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDidChangeHiddenWindows object:self];
    }
    __block NSNumber *tabIndex = _pendingWindows[@(windowId)].index;
    [_buriedWindows enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull terminalGUID, NSMutableArray<iTermTuple<NSNumber *, NSNumber *> *> * _Nonnull tuples, BOOL * _Nonnull stop) {
        const NSInteger i = [tuples indexOfObjectPassingTest:^BOOL(iTermTuple<NSNumber *,NSNumber *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.firstObject isEqual:@(windowId)];
        }];
        if (i != NSNotFound) {
            tabIndex = tuples[i].secondObject;
            [tuples removeObjectAtIndex:i];
            DLog(@"Add affinities for terminal %@: %@", terminalGUID, [[tuples mapWithBlock:^id(iTermTuple *anObject) {
                return anObject.description;
            }] componentsJoinedByString:@", "]);
            [affinities_ setValue:[@(windowId) stringValue] equalToValue:terminalGUID];
        }
    }];
    // Get the window's basic info to prep the creation of a TmuxWindowOpener.
    [gateway_ sendCommand:[NSString stringWithFormat:@"display -p -F %@ -t @%d",
                           [self listWindowsDetailedFormat], windowId]
           responseTarget:self
         responseSelector:@selector(listedWindowsToOpenOne:forWindowIdAndAffinities:)
           responseObject:@[ @(windowId), affinities, profile, tabIndex ?: @-1 ]
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
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
// windowPositions_ is used for setting the origin of a pane after moving it into a window, which
// is rarely done. This falls back to the recorded window origin if one is present.
- (NSValue *)positionForWindowWithPanes:(NSArray *)panes
                               windowID:(int)windowID {
    NSValue *pos = nil;
    for (NSNumber *n in panes) {
        pos = [windowPositions_ objectForKey:n];
        if (pos) {
            break;
        }
    }
    [windowPositions_ removeObjectsForKeys:panes];
    if ([iTermAdvancedSettingsModel disableTmuxWindowPositionRestoration]) {
        return nil;
    }
    return pos ?: origins_[@(windowID)];
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
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandOfferToDetachIfLaggyDuplicate | kTmuxGatewayCommandShouldTolerateErrors];
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
                                    [self listWindowsDetailedFormat], sessionNumber];
    NSArray *userInfo = @[listWindowsCommand,
                          object,
                          target,
                          NSStringFromSelector(selector) ];
    if ([_listWindowsQueue containsObject:userInfo]) {
        // Already have this queued up.
        return;
    }
    // Wait a few seconds. We always get a windows-close notification when the last window in
    // a window closes. To avoid spamming the command line with list-windows, we wait a bit to see
    // if there is an exit notification coming down the pipe.
    const CGFloat kListWindowsDelay = 1.5;
    [NSTimer scheduledTimerWithTimeInterval:kListWindowsDelay
                                     target:self
                                   selector:@selector(listWindowsTimerFired:)
                                   userInfo:userInfo
                                    repeats:NO];
}

- (void)listWindowsTimerFired:(NSTimer *)timer {
    if (detached_) {
        return;
    }
    NSArray *array = [timer userInfo];
    NSString *command = array[0];
    id object = array[1];
    id target = array[2];
    NSString *selector = array[3];

    [_listWindowsQueue removeObject:timer.userInfo];

    [gateway_ sendCommand:command
           responseTarget:self
         responseSelector:@selector(didListWindows:userData:)
           responseObject:@[object, selector, target]
                    flags:kTmuxGatewayCommandShouldTolerateErrors];  // Tolerates errors because the session may have been detached by the time we get the notification or the timer fires.
}

- (void)saveHiddenWindows
{
    NSString *hidden = [[hiddenWindows_ allObjects] componentsJoinedByString:@","];
    DLog(@"Save hidden windows: %@", hidden);
    NSString *command = [NSString stringWithFormat:
                         @"set -t $%d @hidden \"%@\"",
                         sessionId_,
                         [self encodedString:hidden
                                      prefix:iTermTmuxControllerEncodingPrefixHidden]];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:kTmuxGatewayCommandShouldTolerateErrors];
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
    [self savePerWindowSettings];
    [self savePerTabSettings];
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
        for (iTermTuple<NSNumber *, NSNumber *> *tuple in _buriedWindows[term.terminalGuid]) {
            DLog(@"add %@ as affinity sibling of %@", tuple, term.terminalGuid);
            [siblings addObject:[tuple.firstObject stringValue]];
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
    DLog(@"Save affinities: %@", arg);
    NSString *command = [NSString stringWithFormat:@"set -t $%d @affinities \"%@\"",
                         sessionId_, [self encodedString:[arg stringByEscapingQuotes]
                                                  prefix:iTermTmuxControllerEncodingPrefixAffinities]];
    if ([command isEqualToString:lastSaveAffinityCommand_]) {
        return;
    }
    [self setAffinitiesFromString:arg];
    lastSaveAffinityCommand_ = command;
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];

    [self saveBuriedIndexes];
}

- (void)saveBuriedIndexes {
    NSString *arg = [[_buriedWindows.allKeys mapWithBlock:^id(NSString *terminalGUID) {
        NSString *rhs = [[_buriedWindows[terminalGUID] mapWithBlock:^id(iTermTuple<NSNumber *,NSNumber *> *tuple) {
            return [NSString stringWithFormat:@"%@=%@", tuple.firstObject, tuple.secondObject];
        }] componentsJoinedByString:@","];
        return [NSString stringWithFormat:@"%@:%@", terminalGUID, rhs];
    }] componentsJoinedByString:@" "];
    DLog(@"save buried indexes: %@", arg);

    NSString *command = [NSString stringWithFormat:@"set -t $%d @buried_indexes \"%@\"",
                         sessionId_, [self encodedString:[arg stringByEscapingQuotes]
                                                  prefix:iTermTmuxControllerEncodingPrefixBuriedIndexes]];
    if ([command isEqualToString:_lastSaveBuriedIndexesCommand]) {
        return;
    }
    _lastSaveBuriedIndexesCommand = command;
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
}

- (void)savePerTabSettings {
    NSMutableArray<NSString *> *settings = [NSMutableArray array];
    iTermController *cont = [iTermController sharedInstance];
    NSArray *terminals = [cont terminals];
    for (PseudoTerminal *term in terminals) {
        for (PTYTab *tab in term.tabs) {
            if (!tab.isTmuxTab) {
                continue;
            }
            NSString *setting = [tab tmuxPerTabSetting];
            if (setting) {
                [settings addObject:[NSString stringWithFormat:@"%d:%@", tab.tmuxWindow, setting]];
            }
        }
    }
    NSString *arg = [settings componentsJoinedByString:@";"];
    DLog(@"Save per-tab settings: %@", arg);
    NSString *command = [NSString stringWithFormat:@"set -t $%d @per_tab_settings \"%@\"",
                         sessionId_,
                         [self encodedString:arg prefix:iTermTmuxControllerEncodingPrefixPerTabSettings]];
    if ([command isEqualToString:_lastSavePerTabSettingsCommand]) {
        return;
    }
    _lastSavePerTabSettingsCommand = command;
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
}

- (void)getPerTabSettingsResponse:(NSString *)result {
    [self setPerTabSettingsFromString:[self decodedString:result optionalPrefix:iTermTmuxControllerEncodingPrefixPerTabSettings]];
}

- (void)savePerWindowSettings {
    NSMutableArray<NSString *> *settings = [NSMutableArray array];
    iTermController *cont = [iTermController sharedInstance];
    NSArray *terminals = [cont terminals];
    for (PseudoTerminal *term in terminals) {
        NSString *setting = [term tmuxPerWindowSetting];
        if (setting) {
            [settings addObject:[NSString stringWithFormat:@"%@:%@", term.terminalGuid, setting]];
        }
    }
    NSString *arg = [settings componentsJoinedByString:@";"];
    DLog(@"Save per-window settings: %@", arg);
    NSString *command = [NSString stringWithFormat:@"set -t $%d @per_window_settings \"%@\"",
                         sessionId_,
                         [self encodedString:arg prefix:iTermTmuxControllerEncodingPrefixPerWindowSettings]];
    if ([command isEqualToString:_lastSavePerWindowSettingsCommand]) {
        return;
    }
    _lastSavePerWindowSettingsCommand = command;
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
}

- (void)getPerWindowSettingsResponse:(NSString *)result {
    [self setPerWindowSettingsFromString:[self decodedString:result optionalPrefix:iTermTmuxControllerEncodingPrefixPerWindowSettings]];
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
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_id} #{session_name}\"";
    [gateway_ sendCommand:listSessionsCommand
           responseTarget:self
         responseSelector:@selector(listSessionsResponse:)];
}

- (NSString *)listWindowsDetailedFormat {
    NSArray<NSString *> *parts = @[
        @"#{session_name}",
        @"#{window_id}",
        @"#{window_name}",
        @"#{window_width}",
        @"#{window_height}",
        @"#{window_layout}",
        @"#{window_flags}",
        @"#{?window_active,1,0}"
    ];
    if ([self versionAtLeastDecimalNumberWithString:@"2.2"]) {
        parts = [parts arrayByAddingObject:@"#{window_visible_layout}"];
    }
    return [NSString stringWithFormat:@"\"%@\"", [parts componentsJoinedByString:@"\t"]];
}

- (NSString *)commandToListWindows {
    if ([self versionAtLeastDecimalNumberWithString:@"2.2"]) {
        return @"list-windows -F \"#{window_id} #{window_layout} #{window_flags} #{window_visible_layout}\"";
    } else {
        return @"list-windows -F \"#{window_id} #{window_layout} #{window_flags}\"";
    }
}

- (NSString *)commandToListWindowsForSession:(int)session {
    return [[self commandToListWindows] stringByAppendingFormat:@" -t \"$%d\"", sessionId_];
}

- (void)swapPane:(int)pane1 withPane:(int)pane2 {
    NSString *swapPaneCommand = [NSString stringWithFormat:@"swap-pane -s \"%%%d\" -t \"%%%d\"",
                                 pane1, pane2];

    NSArray *commands = @[ [gateway_ dictionaryForCommand:swapPaneCommand
                                           responseTarget:nil
                                         responseSelector:NULL
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:[self commandToListWindows]
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
                           [gateway_ dictionaryForCommand:[self commandToListWindows]
                                           responseTarget:self
                                         responseSelector:@selector(parseListWindowsResponseAndUpdateLayouts:)
                                           responseObject:nil
                                                    flags:0] ];
    [gateway_ sendCommandList:commands];
}

- (void)setTmuxFontTable:(iTermFontTable *)fontTable
                hSpacing:(CGFloat)hs
                vSpacing:(CGFloat)vs
                  window:(int)window {
    NSDictionary *dict = iTermTmuxControllerMakeFontOverrides(fontTable, hs, vs);
    if (_variableWindowSize) {
        _windowStates[@(window)].fontOverrides = dict;
        return;
    }
    _sharedFontOverrides = dict;
}

- (void)setLayoutInWindow:(int)window toLayout:(NSString *)layout {
    NSArray *commands = @[ [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"select-layout -t @%@ %@",
                                                           @(window), layout]
                                           responseTarget:self
                                         responseSelector:@selector(didSetLayout:)
                                           responseObject:nil
                                                    flags:0],
                           [gateway_ dictionaryForCommand:[self commandToListWindowsForSession:sessionId_]
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
                           [gateway_ dictionaryForCommand:[self commandToListWindowsForSession:sessionId_]
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

- (NSArray<PTYSession<iTermTmuxControllerSession> *> *)clientSessions {
    return windowPanes_.allValues;
}

- (NSArray<NSNumber *> *)windowPaneIDs {
    return windowPanes_.allKeys;
}

- (void)activeWindowPaneDidChangeInWindow:(int)windowID toWindowPane:(int)paneID {
    PTYSession *session = [self sessionForWindowPane:paneID];
    if (session) {
        [self suppressActivityChanges:^{
            [session makeActive];
        }];
        return;
    }
    // This must be a newly created session.
    _paneToActivateWhenCreated = paneID;
}

- (BOOL)shouldMakeWindowKeyOnActiveWindowChange {
    PseudoTerminal *term = [[iTermController sharedInstance] currentTerminal];
    if (!term) {
        return NO;
    }
    if (!term.window.isVisible) {
        return NO;
    }
    return term.currentSession.isTmuxClient && term.currentSession.tmuxController == self;
}

- (void)activeWindowDidChangeTo:(int)windowID {
    [self suppressActivityChanges:^{
        const BOOL shouldMakeKeyAndOrderFront = [self shouldMakeWindowKeyOnActiveWindowChange];
        PTYTab *tab = [self window:windowID];
        [tab makeActive];
        if (shouldMakeKeyAndOrderFront) {
            [tab.realParentWindow.window makeKeyAndOrderFront:nil];
        }
    }];
}

- (void)suppressActivityChanges:(void (^ NS_NOESCAPE)(void))block {
    _suppressActivityChanges++;
    block();
    _suppressActivityChanges--;
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
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]
                                      workAroundTabBug:_shouldWorkAroundTabBug];
    id object = userData[0];
    SEL selector = NSSelectorFromString(userData[1]);
    id target = userData[2];
    [target it_performNonObjectReturningSelector:selector withObject:doc withObject:object];
}

- (void)getHiddenWindowsResponse:(NSString *)encodedResponse {
    NSString *response = [self decodedString:encodedResponse
                              optionalPrefix:iTermTmuxControllerEncodingPrefixHidden];
    [hiddenWindows_ removeAllObjects];
    if ([response length] > 0) {
        NSArray *windowIds = [response componentsSeparatedByString:@","];
        DLog(@"getHiddenWindowsResponse: Add these window IDs to hidden: %@", windowIds);
        for (NSString *wid in windowIds) {
            [hiddenWindows_ addObject:[NSNumber numberWithInt:[wid intValue]]];
        }
    }
    DLog(@"Got hidden windows from server. they are: %@", hiddenWindows_);
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDidChangeHiddenWindows object:self];
}

- (void)getAffinitiesResponse:(NSString *)result {
    [self setAffinitiesFromString:[self decodedString:result optionalPrefix:iTermTmuxControllerEncodingPrefixAffinities]];
}

- (void)getBuriedIndexesResponse:(NSString *)result {
    if (!result) {
        return;
    }
    NSString *decoded = [self decodedString:result optionalPrefix:iTermTmuxControllerEncodingPrefixBuriedIndexes];
    if (!decoded.length) {
        return;
    }
    NSArray<NSString *> *parts = [decoded componentsSeparatedByString:@" "];
    [_buriedWindows removeAllObjects];
    // guid:wid=index,wid=index,wid=index guid:wid=index,...
    [parts enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSArray<NSString *> *subparts = [obj componentsSeparatedByString:@":"];
        if (subparts.count < 2) {
            return;
        }
        NSString *terminalGUID = subparts[0];
        NSString *encodedPairs = subparts[1];
        NSArray<NSString *> *pairStrings = [encodedPairs componentsSeparatedByString:@","];
        NSArray<iTermTuple<NSNumber *, NSNumber *> *> *tuples = [pairStrings mapWithBlock:^id(NSString *string) {
            iTermTuple<NSString *, NSString *> *sstuple = [string keyValuePair];
            if (!sstuple) {
                return nil;
            }
            if (!sstuple.firstObject.isNumeric || !sstuple.secondObject.isNumeric) {
                return nil;
            }
            return [iTermTuple tupleWithObject:@([sstuple.firstObject intValue])
                                     andObject:@([sstuple.secondObject intValue])];
        }];
        _buriedWindows[terminalGUID] = [tuples mutableCopy];
    }];
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

- (void)setPerTabSettingsFromString:(NSString *)result {
    DLog(@"Set per-tab settings from string: %@", result);

    _perTabSettings = nil;
    NSMutableDictionary<NSString *, NSString *> *settings = [NSMutableDictionary dictionary];
    NSArray<NSString *> *parts = [result componentsSeparatedByString:@";"];
    for (NSString *part in parts) {
        iTermTuple<NSString *, NSString *> *kvp = [part it_stringBySplittingOnFirstSubstring:@":"];
        if (!kvp) {
            DLog(@"Bad part %@", part);
            continue;
        }
        settings[kvp.firstObject] = kvp.secondObject;
    }
    _perTabSettings = [settings copy];
}

- (NSString *)perTabSettingsForTabWithWindowID:(int)wid {
    NSString *widStr = [@(wid) stringValue];
    return _perTabSettings[widStr];
}

- (void)setPerWindowSettingsFromString:(NSString *)result {
    DLog(@"Set per-window settings from string: %@", result);

    _perWindowSettings = nil;
    NSMutableDictionary<NSString *, NSString *> *settings = [NSMutableDictionary dictionary];
    NSArray<NSString *> *parts = [result componentsSeparatedByString:@";"];
    for (NSString *part in parts) {
        iTermTuple<NSString *, NSString *> *kvp = [part it_stringBySplittingOnFirstSubstring:@":"];
        if (!kvp) {
            DLog(@"Bad part %@", part);
            continue;
        }
        settings[kvp.firstObject] = kvp.secondObject;
    }
    _perWindowSettings = [settings copy];
}

- (NSString *)perWindowSettingsForWindowWithGUID:(NSString *)terminalGUID {
    return _perWindowSettings[terminalGUID];
}

- (void)setAffinitiesFromString:(NSString *)result {
    // Replace the existing equivalence classes with those defined by the
    // affinity response.
    // For example "1,2,3 4,5,6" has two equivalence classes.
    // 1=2=3 and 4=5=6.
    DLog(@"Set affinities from string: %@", result);
    NSArray *affinities = [result componentsSeparatedByString:@" "];
    affinities_ = [[EquivalenceClassSet alloc] init];

    if (![result length]) {
        return;
    }

    for (NSString *theString in affinities) {
        NSArray *components = [self componentsOfAffinities:theString];
        NSString *affset = components[0];
        NSString *windowOptionsString = components[1];

        NSArray<NSString *> *siblings = [affset componentsSeparatedByString:@","];
        DLog(@"Siblings are: %@", [siblings componentsJoinedByString:@" "]);
        NSString *exemplar = [siblings lastObject];
        if (siblings.count == 1) {
            // This is a wee hack. If a tmux Window is in a native window with one tab
            // then create an equivalence class containing only (wid, wid+"_ph"). ph=placeholder
            // The equivalence class's existence signals not to apply the default mode for
            // unrecognized windows.
            exemplar = [exemplar stringByAppendingString:@"_ph"];
            DLog(@"Use placeholder exemplar");
        } else {
            DLog(@"Use arbitrary sibling as exemplar");
        }
        NSDictionary *flags = [self windowOptionsFromString:windowOptionsString];
        for (NSString *widString in siblings) {
            if (![widString isEqualToString:exemplar]) {
                DLog(@"Set wid %@ equal to examplar %@", widString, exemplar);
                [affinities_ setValue:widString
                         equalToValue:exemplar];
                _windowOpenerOptions[widString] = flags;
            }
            if (widString.isNumeric && [hiddenWindows_ containsObject:@(widString.intValue)]) {
                NSString *terminalGUID = [[siblings filteredArrayUsingBlock:^BOOL(NSString *candidate) {
                    return !candidate.isNumeric && ![candidate hasSuffix:@"_ph"];
                }] firstObject];
                if (terminalGUID) {
                    [self setWindowID:widString.intValue buriedFromTerminalGUID:terminalGUID tabIndex:-1];
                }
            }
        }
    }
}

- (void)listSessionsResponse:(NSString *)result
{
    DLog(@"%@ got list-session response:\n%@", self, result);
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionsWillChange
                                                        object:nil];
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
        iTermTmuxSessionObject *obj = [[iTermTmuxSessionObject alloc] init];
        obj.name = sessionName;
        obj.number = sessionNumber;
        return obj;
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionsDidChange
                                                        object:self];
}

- (void)listedWindowsToOpenOne:(NSString *)response
      forWindowIdAndAffinities:(NSArray *)values {
    if (response == nil) {
        DLog(@"Listing windows failed. Maybe the window died before we could get to it?");
        return;
    }
    NSNumber *windowId = values[0];
    NSSet *affinities = values[1];
    Profile *profile = values[2];
    NSNumber *tabIndex = values[3];
    if (tabIndex.intValue < 0) {
        tabIndex = nil;
    }
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]
                                      workAroundTabBug:_shouldWorkAroundTabBug];
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
                        visibleLayout:[doc valueInRecord:record forField:@"window_visible_layout"]
                           affinities:affinities
                          windowFlags:[doc valueInRecord:record forField:@"window_flags"]
                              profile:profile
                              initial:NO
                             tabIndex:tabIndex];
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
    BOOL windowMightNeedAdjustment = NO;
    NSMutableArray<PTYTab *> *tabs = [NSMutableArray array];
    DLog(@"Begin handling list-windows response\n%@", response);
    for (NSString *layoutString in layoutStrings) {
        // Capture groups are:
        // <entire match> <window number> [<layout> [<visible layout]]
        NSArray *components = [layoutString captureComponentsMatchedByRegex:@"^@([0-9]+) ([^ ]+)(?: ([^ ]+)(?: ([^ ]+))?)?"];
        if ([components count] < 3) {
            DLog(@"Bogus layout string: \"%@\"", layoutString);
        } else {
            int window = [[components objectAtIndex:1] intValue];
            NSString *layout = [components objectAtIndex:2];
            NSString *visibleLayout = components.count > 4 ? components[4] : nil;
            PTYTab *tab = [self window:window];
            if (tab) {
                [tabs addObject:tab];
                NSNumber *zoomed = components.count > 3 ? @([components[3] containsString:@"Z"]) : nil;
                const BOOL adjust =
                [[gateway_ delegate] tmuxUpdateLayoutForWindow:window
                                                        layout:layout
                                                 visibleLayout:visibleLayout
                                                        zoomed:zoomed
                                                          only:NO];
                if (adjust) {
                    windowMightNeedAdjustment = YES;
                }
            }
        }
    }
    DLog(@"End handling list-windows response");
    if (windowMightNeedAdjustment) {
        [self adjustWindowSizeIfNeededForTabs:tabs];
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
        state = [[iTermTmuxWindowState alloc] init];
        state.tab = tab;
        state.refcount = 1;
        state.profile = tab.sessions.firstObject.profile;
        _windowStates[k] = state;
        notify = YES;
    }
    if (notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                            object:@[ k, self ]];
    }
}

- (void)releaseWindow:(int)window {
    NSNumber *k = [NSNumber numberWithInt:window];
    iTermTmuxWindowState *state = _windowStates[k];
    state.refcount = state.refcount - 1;
    if (!state.refcount) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidClose
                                                            object:@[ k, self ]];
        [_windowStates removeObjectForKey:k];
    }
}

// Called only for iTerm2-initiated new windows/tabs.
- (void)newWindowWithAffinityCreated:(NSString *)responseStr
         affinityWindowAndCompletion:(iTermTriple *)tuple {  // Value passed in to -newWindowWithAffinity:, may be nil
    if ([responseStr hasPrefix:@"@"]) {
        int intWindowId = [[responseStr substringFromIndex:1] intValue];
        NSString  *windowId = [NSString stringWithInt:intWindowId];
        void (^completion)(int) = tuple.secondObject;
        _pendingWindows[@(intWindowId)] = [iTermTmuxPendingWindow withIndex:tuple.thirdObject
                                                                 completion:completion];
        NSString *affinityWindow = tuple.firstObject;
        if (affinityWindow) {
            [affinities_ setValue:windowId
                     equalToValue:affinityWindow];
        } else {
            [affinities_ removeValue:windowId];
        }
    } else {
        DLog(@"Response to new-window doesn't look like a window id: \"%@\"", responseStr);
    }
}

- (void)closeAllPanes {
    // Close all sessions. Iterate over a copy of windowPanes_ because the loop
    // body modifies it by closing sessions.
    for (NSString *key in [windowPanes_ copy]) {
        PTYSession<iTermTmuxControllerSession> *session = [windowPanes_ objectForKey:key];
        [session tmuxDidDisconnect];
    }

    // Clean up all state to avoid trying to reuse it.
    [windowPanes_ removeAllObjects];
}

- (void)windowDidOpen:(TmuxWindowOpener *)windowOpener {
    NSNumber *windowIndex = @(windowOpener.windowIndex);
    DLog(@"TmuxController windowDidOpen for index %@ with error count %@", windowIndex, @(windowOpener.errorCount));
    [pendingWindowOpens_ removeObject:windowIndex];
    if (windowOpener.errorCount != 0) {
        [affinities_ removeValue:[@(windowOpener.windowIndex) stringValue]];
        [[iTermNotificationController sharedInstance] notify:@"Error opening tmux tab"
                                             withDescription:@"A tmux pane terminated immediately after creation"];
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                        object:nil];
    PTYTab *tab = [self window:[windowIndex intValue]];
    NSWindowController<iTermWindowController> * term = [tab realParentWindow];
    NSValue *p = [origins_ objectForKey:windowIndex];
    if (term && ![term anyFullScreen] && term.tabs.count == 1) {
        if (p) {
            [[term window] setFrameOrigin:[p pointValue]];
        } else if (!NSEqualRects(NSZeroRect, _initialWindowHint)) {
            [[term window] setFrameOrigin:_initialWindowHint.origin];
        }
    }
    _initialWindowHint = NSZeroRect;
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
            NSNumber *temp = currentOrder[i];
            currentOrder[i] = currentOrder[swapIndex];
            currentOrder[swapIndex] = temp;
        }
    }

    [gateway_ sendCommandList:commands];
    if (_currentWindowID >= 0) {
        [self setCurrentWindow:_currentWindowID];
    }
}

- (void)didSwapWindows:(NSString *)response {
}

- (void)setCurrentWindow:(int)windowId {
    _currentWindowID = windowId;
    if (_suppressActivityChanges) {
        DLog(@"Not sending select-window -t %%%d because activity changes are suppressed", windowId);
        return;
    }
    NSString *command = [NSString stringWithFormat:@"select-window -t @%d", windowId];
    [gateway_ sendCommand:command
           responseTarget:nil
         responseSelector:nil];
}

- (NSString *)userVarsString:(int)paneID {
    NSDictionary<NSString *, NSString *> *dict = _userVars[@(paneID)];
    return [[dict.allKeys mapWithBlock:^id(NSString *key) {
        NSString *value = dict[key];
        NSInteger index = [value rangeOfString:@"\0"].location;
        if (index != NSNotFound) {
            value = [value substringToIndex:index];
        }
        return [NSString stringWithFormat:@"%@=%@", key, value];
    }] componentsJoinedByString:@"\0"];
}

- (void)setEncodedUserVars:(NSString *)encodedUserVars forPane:(int)paneID {
    NSString *decoded = [self decodedString:encodedUserVars
                             optionalPrefix:iTermTmuxControllerEncodingPrefixUserVars] ?: @"";
    NSArray<NSString *> *kvps = [decoded componentsSeparatedByString:@"\0"];
    NSMutableDictionary<NSString *, NSString *> *dict = [self mutableUserVarsForPane:paneID];
    [dict removeAllObjects];
    for (NSString *kvp in kvps) {
        NSInteger index = [kvp rangeOfString:@"="].location;
        if (index == NSNotFound) {
            continue;
        }
        NSString *key = [kvp substringToIndex:index];
        NSString *value = [kvp substringFromIndex:index + 1];
        dict[key] = value;
    }
}

- (NSDictionary<NSString *, NSString *> *)userVarsForPane:(int)paneID {
    return _userVars[@(paneID)] ?: @{};
}

- (NSMutableDictionary<NSString *, NSString *> *)mutableUserVarsForPane:(int)paneID {
    NSMutableDictionary<NSString *, NSString *> *dict = _userVars[@(paneID)];
    if (dict) {
        return dict;
    }
    dict = [NSMutableDictionary dictionary];
    _userVars[@(paneID)] = dict;
    return dict;
}

- (void)setUserVariableWithKey:(NSString *)key
                         value:(NSString *)value
                          pane:(int)paneID {
    if (![self versionAtLeastDecimalNumberWithString:@"3.1"]) {
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *dict = [self mutableUserVarsForPane:paneID];
    if (!value) {
        if (!dict[key]) {
            return;
        }
        [dict removeObjectForKey:key];
    } else {
        if ([dict[key] isEqualToString:value]) {
            return;
        }
        dict[key] = value;
    }
    NSString *command = [NSString stringWithFormat:@"set -p -t %%%d @uservars \"%@\"",
                         paneID,
                         [self encodedString:[self userVarsString:paneID]
                                      prefix:iTermTmuxControllerEncodingPrefixUserVars]];
    [gateway_ sendCommand:command responseTarget:nil responseSelector:nil];
}

- (void)setCurrentLatency:(NSTimeInterval)latency forPane:(int)wp {
    [_tmuxBufferMonitor setCurrentLatency:latency forPane:wp];
}

- (void)copyBufferToLocalPasteboard:(NSString *)bufferName {
    [gateway_ sendCommand:[NSString stringWithFormat:@"show-buffer -b %@", bufferName]
           responseTarget:self
         responseSelector:@selector(handleShowBuffer:)];
}

- (void)handleShowBuffer:(NSString *)content {
    if ([content length]) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
        [pasteboard setString:content forType:NSPasteboardTypeString];
    }
}
#pragma mark - iTermTmuxBufferSizeMonitorDelegate

- (void)tmuxBufferSizeMonitor:(iTermTmuxBufferSizeMonitor *)sender
                   updatePane:(int)wp
                          ttl:(NSTimeInterval)ttl
                      redzone:(BOOL)redzone {
    PTYSession<iTermTmuxControllerSession> *session = [self sessionForWindowPane:wp];
    if (!session) {
        return;
    }
    [session tmuxControllerSessionSetTTL:ttl redzone:redzone];
}

#pragma mark - Notifications

- (void)textViewWillChangeFont:(NSNotification *)notification {
    if ([iTermPreferences boolForKey:kPreferenceKeyAdjustWindowForFontSizeChange]) {
        return;
    }
    if (_savedFrames.count) {
        return;
    }
    NSArray *terminals = [[iTermController sharedInstance] terminals];
    for (PseudoTerminal *term in terminals) {
        if ([self windowControllerHasTmuxTabOfMine:term]) {
            _savedFrames[term.terminalGuid] = [NSValue valueWithRect:term.window.frame];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_savedFrames removeAllObjects];
    });
}

- (BOOL)windowControllerHasTmuxTabOfMine:(PseudoTerminal *)term {
    return [term.tabs anyWithBlock:^BOOL(PTYTab *tab) {
        return tab.isTmuxTab && tab.tmuxController == self;
    }];
}

- (void)restoreWindowFrame:(PseudoTerminal *)term {
    if ([iTermPreferences boolForKey:kPreferenceKeyAdjustWindowForFontSizeChange]) {
        return;
    }
    NSRect savedFrame;
    if ([self getSavedFrameForWindowController:term frame:&savedFrame]) {
        [term.window setFrame:savedFrame display:YES];
    }
}

- (BOOL)getSavedFrameForWindowController:(PseudoTerminal *)term frame:(NSRect *)framePtr {
    NSValue *value = _savedFrames[term.terminalGuid];
    if (!value) {
        return NO;
    }
    *framePtr = value.rectValue;
    return YES;
}

@end
