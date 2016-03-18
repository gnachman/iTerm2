//
//  TmuxController.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxController.h"
#import "DebugLogging.h"
#import "EquivalenceClassSet.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermPreferences.h"
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
@property(nonatomic, copy) NSString *sessionGuid;

@end

@implementation TmuxController {
    TmuxGateway *gateway_;
    NSMutableDictionary *windowPanes_;  // paneId -> PTYSession *
    NSMutableDictionary *windows_;      // window -> [PTYTab *, refcount]
    NSArray *sessions_;
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
    NSMutableSet *hiddenWindows_;
    NSTimer *listSessionsTimer_;  // Used to do a cancelable delayed perform of listSessions.
    NSTimer *listWindowsTimer_;  // Used to do a cancelable delayed perform of listWindows.
    BOOL ambiguousIsDoubleWidth_;

    // Maps a window id string to a dictionary of window flags defined by TmuxWindowOpener (see the
    // top of its header file)
    NSMutableDictionary *_windowOpenerOptions;
}

@synthesize gateway = gateway_;
@synthesize windowPositions = windowPositions_;
@synthesize sessionName = sessionName_;
@synthesize sessions = sessions_;
@synthesize ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
@synthesize sessionId = sessionId_;

- (instancetype)initWithGateway:(TmuxGateway *)gateway clientName:(NSString *)clientName {
    self = [super init];
    if (self) {
        gateway_ = [gateway retain];
        windowPanes_ = [[NSMutableDictionary alloc] init];
        windows_ = [[NSMutableDictionary alloc] init];
        windowPositions_ = [[NSMutableDictionary alloc] init];
        origins_ = [[NSMutableDictionary alloc] init];
        pendingWindowOpens_ = [[NSMutableSet alloc] init];
        hiddenWindows_ = [[NSMutableSet alloc] init];
        self.clientName = [[TmuxControllerRegistry sharedInstance] uniqueClientNameBasedOn:clientName];
        _windowOpenerOptions = [[NSMutableDictionary alloc] init];
        [[TmuxControllerRegistry sharedInstance] setController:self forClient:_clientName];
    }
    return self;
}

- (void)dealloc {
    [_clientName release];
    [gateway_ release];
    [windowPanes_ release];
    [windows_ release];
    [windowPositions_ release];
    [origins_ release];
    [pendingWindowOpens_ release];
    [affinities_ release];
    [lastSaveAffinityCommand_ release];
    [hiddenWindows_ release];
    [lastOrigins_ release];
    [_sessionGuid release];
    [_windowOpenerOptions release];
    [super dealloc];
}

- (void)openWindowWithIndex:(int)windowIndex
                       name:(NSString *)name
                       size:(NSSize)size
                     layout:(NSString *)layout
                 affinities:(NSSet *)affinities
                windowFlags:(NSString *)windowFlags {
    DLog(@"openWindowWithIndex:%d name:%@ affinities:%@ flags:%@",
         windowIndex, name, affinities, windowFlags);
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
    windowOpener.windowIndex = windowIndex;
    windowOpener.name = name;
    windowOpener.size = size;
    windowOpener.layout = layout;
    windowOpener.maxHistory =
        MAX([[gateway_ delegate] tmuxBookmarkSize].height,
            [[gateway_ delegate] tmuxNumHistoryLinesInBookmark]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    windowOpener.windowOptions = _windowOpenerOptions;
    windowOpener.zoomed = windowFlags ? @([windowFlags containsString:@"Z"]) : nil;
    [windowOpener openWindows:YES];
}

- (void)setLayoutInTab:(PTYTab *)tab
              toLayout:(NSString *)layout
                zoomed:(NSNumber *)zoomed {
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;
    windowOpener.layout = layout;
    windowOpener.maxHistory =
        MAX([[gateway_ delegate] tmuxBookmarkSize].height,
            [[gateway_ delegate] tmuxNumHistoryLinesInBookmark]);
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.windowIndex = [tab tmuxWindow];
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    windowOpener.windowOptions = _windowOpenerOptions;
    windowOpener.zoomed = zoomed;
    [windowOpener updateLayoutInTab:tab];
}

- (void)sessionChangedTo:(NSString *)newSessionName sessionId:(int)sessionid {
    self.sessionGuid = nil;
    self.sessionName = newSessionName;
    sessionId_ = sessionid;
    [self closeAllPanes];
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

- (NSSet<NSObject<NSCopying> *> *)savedAffinitiesForWindow:(int)wid {
    return [affinities_ valuesEqualTo:[NSString stringWithInt:wid]];
}

- (void)initialListWindowsResponse:(NSString *)response {
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for initial list windows request: %@", response]];
        return;
    }
    NSMutableArray *windowsToOpen = [NSMutableArray array];
    BOOL haveHidden = NO;
    NSNumber *newWindowAffinity = nil;
    BOOL newWindowsInTabs =
        [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn] == kOpenTmuxWindowsAsNativeTabsInNewWindow;
    for (NSArray *record in doc.records) {
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        if (hiddenWindows_ && [hiddenWindows_ containsObject:[NSNumber numberWithInt:wid]]) {
            NSLog(@"Don't open window %d because it was saved hidden.", wid);
            haveHidden = YES;
            // Let the user know something is up.
            continue;
        }
        NSNumber *n = [NSNumber numberWithInt:wid];
        if (![affinities_ valuesEqualTo:[n stringValue]] && newWindowsInTabs) {
            // Create an equivalence class of all unrecognied windows to each other.
            if (!newWindowAffinity) {
                newWindowAffinity = n;
            } else {
                [affinities_ setValue:[n stringValue]
                         equalToValue:[newWindowAffinity stringValue]];
            }
        }
        [windowsToOpen addObject:record];
    }
    if (windowsToOpen.count > [iTermPreferences intForKey:kPreferenceKeyTmuxDashboardLimit]) {
        haveHidden = YES;
        [windowsToOpen removeAllObjects];
    }
    if (haveHidden) {
        [[TmuxDashboardController sharedInstance] showWindow:nil];
        [[[TmuxDashboardController sharedInstance] window] makeKeyAndOrderFront:nil];
    }
    for (NSArray *record in windowsToOpen) {
        int wid = [self windowIdFromString:[doc valueInRecord:record forField:@"window_id"]];
        [self openWindowWithIndex:wid
                             name:[doc valueInRecord:record forField:@"window_name"]
                             size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                             [[doc valueInRecord:record forField:@"window_height"] intValue])
                           layout:[doc valueInRecord:record forField:@"window_layout"]
                       affinities:[self savedAffinitiesForWindow:wid]
                      windowFlags:[doc valueInRecord:record forField:@"window_flags"]];
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
        [self openWindowsOfSize:NSMakeSize(width, height)];
    } else {
        [self openWindowsOfSize:[[gateway_ delegate] tmuxBookmarkSize]];
    }
}

- (void)openWindowsOfSize:(NSSize)size {
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
             (int)size.width, (int)size.height];
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@", kListWindowsFormat];
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_name}\"";
    NSString *getAffinitiesCommand = [NSString stringWithFormat:@"show -v -q -t $%d @affinities", sessionId_];
    NSString *getOriginsCommand = [NSString stringWithFormat:@"show -v -q -t $%d @origins", sessionId_];
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
        [self.gateway abortWithErrorMessage:@"This instance of iTerm2 is already attached to this session."
                                      title:@"Could not attach to session."];
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
    [self retainWindow:window withTab:[aSession.delegate.realParentWindow tabForSession:aSession]];
    [windowPanes_ setObject:aSession forKey:[self _keyForWindowPane:windowPane]];
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane session:(id)session
{
    id key = [self _keyForWindowPane:windowPane];
    if (windowPanes_[key] == session) {
        [self releaseWindow:window];
        [windowPanes_ removeObjectForKey:key];
    }
}

- (PTYTab *)window:(int)window
{
    return [[windows_ objectForKey:[NSNumber numberWithInt:window]] objectAtIndex:0];
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

- (BOOL)windowDidResize:(NSWindowController<iTermWindowController> *)term
{
    NSSize size = [term tmuxCompatibleSize];
    if (size.width == 0 || size.height == 0) {
        // After the last session closes a size of 0 is reported.
        return YES;
    }
    if (NSEqualSizes(size, lastSize_)) {
        return NO;
    }
    [self setClientSize:size];
    return YES;
}

- (void)fitLayoutToWindows
{
    if (!windows_.count) {
        return;
    }
    NSSize minSize = NSMakeSize(INFINITY, INFINITY);
    for (id windowKey in windows_) {
        PTYTab *tab = [[windows_ objectForKey:windowKey] objectAtIndex:0];
        NSSize size = [tab maxTmuxSize];
        minSize.width = MIN(minSize.width, size.width);
        minSize.height = MIN(minSize.height, size.height);
    }
    if (minSize.width == 0 || minSize.height == 0) {
        // After the last session closes a size of 0 is reported.
        return;
    }
    if (NSEqualSizes(minSize, lastSize_)) {
        return;
    }
    [self setClientSize:minSize];
}

- (void)setClientSize:(NSSize)size {
    assert(size.width > 0 && size.height > 0);
    lastSize_ = size;
    NSString *listStr = [NSString stringWithFormat:@"list-windows -F \"#{window_id} #{window_layout}\""];
    NSString *setSizeCommand = [NSString stringWithFormat:@"set -t $%d @iterm2_size %d,%d",
                                sessionId_, (int)size.width, (int)size.height];
    NSArray *commands = [NSArray arrayWithObjects:
                         [gateway_ dictionaryForCommand:setSizeCommand
                                         responseTarget:nil
                                       responseSelector:nil
                                         responseObject:nil
                                                  flags:0],
                         [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"refresh-client -C %d,%d",
                                                         (int)size.width, (int)size.height]
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

// Make sure that current tmux options are compatible with iTerm.
- (void)validateOptions
{
    for (NSString *option in [self unsupportedGlobalOptions]) {
        [gateway_ sendCommand:[NSString stringWithFormat:@"show-window-options -g %@", option]
               responseTarget:self
             responseSelector:@selector(showWindowOptionsResponse:)];
    }
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
    NSString *resizeStr = [NSString stringWithFormat:@"resize-pane -%@ -t %%%d %d",
                           dir, wp, abs(amount)];
    NSString *listStr = [NSString stringWithFormat:@"list-windows -F \"#{window_id} #{window_layout}\""];
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
- (void)splitWindowPane:(int)wp vertically:(BOOL)splitVertically {
    // No need for a callback. We should get a layout-changed message and act on it.
    [gateway_ sendCommand:[NSString stringWithFormat:@"split-window -%@ -t %%%d", splitVertically ? @"h": @"v", wp]
           responseTarget:nil
         responseSelector:nil];
}

- (void)newWindowInSession:(NSString *)targetSession
       afterWindowWithName:(NSString *)predecessorWindow
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"new-window -a -t \"%@:+\" -PF '#{window_id}'",
                           [targetSession stringByEscapingQuotes]]
           responseTarget:nil
         responseSelector:nil];
}

- (void)newWindowWithAffinity:(NSString *)windowIdString
{
    [gateway_ sendCommand:@"new-window -PF '#{window_id}'"
           responseTarget:self
         responseSelector:@selector(newWindowWithAffinityCreated:affinityWindow:)
           responseObject:windowIdString
                    flags:0];
}

- (void)movePane:(int)srcPane
        intoPane:(int)destPane
      isVertical:(BOOL)splitVertical
          before:(BOOL)addBefore
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"move-pane -s %%%d -t %%%d %@%@",
                           srcPane, destPane, splitVertical ? @"-h" : @"-v",
                           addBefore ? @" -b" : @""]
           responseTarget:nil
         responseSelector:nil];
}

- (void)killWindowPane:(int)windowPane
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-pane -t %%%d", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)unlinkWindowWithId:(int)windowId inSession:(NSString *)sessionName
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"unlink-window -k -t @%d", windowId]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (void)renameWindowWithId:(int)windowId
                 inSession:(NSString *)sessionName
                    toName:(NSString *)newName {
    NSString *theCommand;
    if (sessionName) {
        theCommand = [NSString stringWithFormat:@"rename-window -t \"%@:@%d\" \"%@\"", sessionName, windowId, newName];
    } else {
        theCommand = [NSString stringWithFormat:@"rename-window -t @%d \"%@\"", windowId, newName];
    }
    [gateway_ sendCommand:theCommand
           responseTarget:nil
         responseSelector:nil];
}

- (void)killWindow:(int)window
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-window -t @%d", window]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil
                    flags:0];
}

- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint
{
    [windowPositions_ setObject:[NSValue valueWithPoint:screenPoint]
                         forKey:[NSNumber numberWithInt:windowPane]];
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane -t %%%d", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)breakOutWindowPane:(int)windowPane toTabAside:(NSString *)sibling
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane -P -F \"#{window_id}\" -t %%%d", windowPane]
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
{
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
           responseObject:[NSArray arrayWithObjects:[NSNumber numberWithInt:windowId],
                           affinities,
                           nil]
                    flags:0];
}

- (void)openWindowWithId:(int)windowId
             intentional:(BOOL)intentional
{
    [self openWindowWithId:windowId affinities:[NSArray array] intentional:intentional];
}

- (void)linkWindowId:(int)windowId
           inSession:(NSString *)sessionName
           toSession:(NSString *)targetSession
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"link-window -s \"%@:@%d\" -t \"%@:+\"",
                           sessionName, windowId, targetSession]
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

- (void)renameSession:(NSString *)oldName to:(NSString *)newName
{
    NSString *renameCommand = [NSString stringWithFormat:@"rename-session -t \"%@\" \"%@\"",
                               [oldName stringByEscapingQuotes],
                               [newName stringByEscapingQuotes]];
    [gateway_ sendCommand:renameCommand responseTarget:nil responseSelector:nil];
}

- (void)killSession:(NSString *)sessionName
{
    NSString *killCommand = [NSString stringWithFormat:@"kill-session -t \"%@\"",
                                [sessionName stringByEscapingQuotes]];
    [gateway_ sendCommand:killCommand responseTarget:nil responseSelector:nil];
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

- (void)attachToSession:(NSString *)sessionName
{
    NSString *attachCommand = [NSString stringWithFormat:@"attach-session -t \"%@\"",
                             [sessionName stringByEscapingQuotes]];
    [gateway_ sendCommand:attachCommand
           responseTarget:nil
         responseSelector:nil];
}

- (void)listWindowsInSession:(NSString *)sessionName
                      target:(id)target
                    selector:(SEL)selector
                      object:(id)object
{
    if (detached_) {
        // Shouldn't happen, but better safe than sorry.
        return;
    }
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@ -t \"%@\"",
                                    kListWindowsFormat, sessionName];
    // Wait a few seconds. We always get a windows-close notification when the last window in
    // a window closes. To avoid spamming the command line with list-windows, we wait a bit to see
    // if there is an exit notification coming down the pipe.
    const CGFloat kListWindowsDelay = 1.5;
    [listWindowsTimer_ invalidate];
    listWindowsTimer_ = [NSTimer scheduledTimerWithTimeInterval:kListWindowsDelay
                                                         target:self
                                                       selector:@selector(listWindowsTimerFired:)
                                                       userInfo:[NSArray arrayWithObjects:listWindowsCommand, object, target, NSStringFromSelector(selector), nil]
                                                        repeats:NO];
}

- (void)listWindowsTimerFired:(NSTimer *)timer
{
    NSArray *array = [timer userInfo];
    NSString *command = [array objectAtIndex:0];
    id object = [array objectAtIndex:1];
    id target = [array objectAtIndex:2];
    NSString *selector = [array objectAtIndex:3];

    [listWindowsTimer_ invalidate];
    listWindowsTimer_ = nil;

    [gateway_ sendCommand:command
           responseTarget:self
         responseSelector:@selector(didListWindows:userData:)
           responseObject:[NSArray arrayWithObjects:object,
                           selector,
                           target,
                           nil]
                    flags:kTmuxGatewayCommandShouldTolerateErrors];  // Tolerates errors because the session may have been detached by the time we get the notification or the timer fires.
}

- (void)saveHiddenWindows
{
    NSString *hidden = [[hiddenWindows_ allObjects] componentsJoinedByString:@","];
    NSString *command = [NSString stringWithFormat:
        @"set -t $%d @hidden \"%@\"",
        sessionId_, hidden];
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
             sessionId_, [enc stringByEscapingQuotes]];
    if (!lastOrigins_ || ![command isEqualToString:lastOrigins_]) {
        [lastOrigins_ release];
        lastOrigins_ = [command copy];
        haveOutstandingSaveWindowOrigins_ = YES;
        [gateway_ sendCommand:command
               responseTarget:self
             responseSelector:@selector(saveWindowOriginsResponse:)];
    }
  [self getOriginsResponse:enc];
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
                         sessionId_, [arg stringByEscapingQuotes]];
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

- (PseudoTerminal *)windowWithAffinityForWindowId:(int)wid
{
    for (NSString *n in [self savedAffinitiesForWindow:wid]) {
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

- (void)changeWindow:(int)window tabTo:(PTYTab *)tab
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    if (entry) {
        [entry replaceObjectAtIndex:0
                         withObject:tab];
    }
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
    NSString *swapPaneCommand = [NSString stringWithFormat:@"swap-pane -s %%%d -t %%%d",
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
    NSArray *commands = @[ [gateway_ dictionaryForCommand:[NSString stringWithFormat:@"resize-pane -Z -t %%%d", pane]
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

#pragma mark - Private

- (void)getOriginsResponse:(NSString *)result
{
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
    id object = [userData objectAtIndex:0];
    SEL selector = NSSelectorFromString([userData objectAtIndex:1]);
    id target = [userData objectAtIndex:2];
    [target performSelector:selector withObject:doc withObject:object];
}

- (void)getHiddenWindowsResponse:(NSString *)response
{
    [hiddenWindows_ removeAllObjects];
    if ([response length] > 0) {
        NSArray *windowIds = [response componentsSeparatedByString:@","];
        NSLog(@"getHiddneWindowsResponse: Add these window IDS to hidden: %@", windowIds);
        for (NSString *wid in windowIds) {
            [hiddenWindows_ addObject:[NSNumber numberWithInt:[wid intValue]]];
        }
    }
}

- (void)getAffinitiesResponse:(NSString *)result {
    [self setAffinitiesFromString:result];
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
            // The equivalence class's existance signals not to apply the default mode for
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
    self.sessions = [result componentsSeparatedByRegex:@"\n"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionsDidChange
                                                        object:self.sessions];
}

- (void)listedWindowsToOpenOne:(NSString *)response forWindowIdAndAffinities:(NSArray *)values {
    NSNumber *windowId = [values objectAtIndex:0];
    NSSet *affinities = [values objectAtIndex:1];
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
                                 name:[doc valueInRecord:record forField:@"window_name"]
                                 size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                                 [[doc valueInRecord:record forField:@"window_height"] intValue])
                               layout:[doc valueInRecord:record forField:@"window_layout"]
                           affinities:affinities
                          windowFlags:[doc valueInRecord:record forField:@"window_flags"]];
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

- (void)retainWindow:(int)window withTab:(PTYTab *)tab
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    BOOL notify = NO;
    if (entry) {
        NSNumber *refcount = [entry objectAtIndex:1];
        [entry replaceObjectAtIndex:1 withObject:[NSNumber numberWithInt:[refcount intValue] + 1]];
    } else {
        entry = [NSMutableArray arrayWithObjects:tab, [NSNumber numberWithInt:1], nil];
        notify = YES;
    }
    [windows_ setObject:entry forKey:k];
    if (notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                            object:nil];
    }
}

- (void)releaseWindow:(int)window
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    NSNumber *refcount = [entry objectAtIndex:1];
    refcount = [NSNumber numberWithInt:[refcount intValue] - 1];
    if ([refcount intValue]) {
        [entry replaceObjectAtIndex:1 withObject:refcount];
        [windows_ setObject:entry forKey:k];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidClose
                                                            object:nil];
        [windows_ removeObjectForKey:k];
    }
}

- (void)newWindowWithAffinityCreated:(NSString *)responseStr
                      affinityWindow:(NSString *)affinityWindow  // Value passed in to -newWindowWithAffinity:, may be nil
{
    if ([responseStr hasPrefix:@"@"]) {
        NSString  *windowId = [NSString stringWithInt:[[responseStr substringFromIndex:1] intValue]];
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

- (void)windowDidOpen:(NSNumber *)windowIndex
{
    DLog(@"TmuxController windowDidOpen for index %@", windowIndex);
    [pendingWindowOpens_ removeObject:windowIndex];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerWindowDidOpen
                                                        object:nil];
    PTYTab *tab = [self window:[windowIndex intValue]];
    NSWindowController<iTermWindowController> * term = [tab realParentWindow];
    NSValue *p = [origins_ objectForKey:windowIndex];
    if (term && p && ![term anyFullScreen]) {
        [[term window] setFrameOrigin:[p pointValue]];
    }
    [self saveAffinities];
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
