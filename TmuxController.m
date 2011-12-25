//
//  TmuxController.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxController.h"
#import "TmuxGateway.h"
#import "TSVParser.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "TmuxWindowOpener.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "RegexKitLite.h"
#import "TmuxDashboardController.h"
#import "NSStringITerm.h"

NSString *kTmuxControllerSessionsDidChange = @"kTmuxControllerSessionsDidChange";
NSString *kTmuxControllerDetachedNotification = @"kTmuxControllerDetachedNotification";
NSString *kTmuxControllerWindowsChangeNotification = @"kTmuxControllerWindowsChangeNotification";
static NSString *kListWindowsFormat = @"\"#{session_name}\t#{window_id}\t"
    "#{window_name}\t"
    "#{window_width}\t#{window_height}\t"
    "#{window_layout_ex}\t"
    "#{?window_active,1,0}\"";

@interface TmuxController (Private)

- (void)retainWindow:(int)window withTab:(PTYTab *)tab;
- (void)releaseWindow:(int)window;
- (void)closeAllPanes;
- (void)windowDidOpen:(NSNumber *)windowIndex;
- (void)listSessions;

@end

@implementation TmuxController

@synthesize gateway = gateway_;
@synthesize windowPositions = windowPositions_;
@synthesize sessionName = sessionName_;
@synthesize sessions = sessions_;

- (id)initWithGateway:(TmuxGateway *)gateway
{
    self = [super init];
    if (self) {
        gateway_ = [gateway retain];
        windowPanes_ = [[NSMutableDictionary alloc] init];
        windows_ = [[NSMutableDictionary alloc] init];
        windowPositions_ = [[NSMutableDictionary alloc] init];
        pendingWindowOpens_ = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [gateway_ release];
    [windowPanes_ release];
    [windows_ release];
    [windowPositions_ release];
    [pendingWindowOpens_ release];
    [super dealloc];
}

- (void)openWindowWithIndex:(int)windowIndex
                       name:(NSString *)name
                       size:(NSSize)size
                     layout:(NSString *)layout
{
    NSNumber *n = [NSNumber numberWithInt:windowIndex];
    if ([pendingWindowOpens_ containsObject:n]) {
        return;
    }
    [pendingWindowOpens_ addObject:n];
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.windowIndex = windowIndex;
    windowOpener.name = name;
    windowOpener.size = size;
    windowOpener.layout = layout;
    windowOpener.maxHistory = 1000;
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.target = self;
    windowOpener.selector = @selector(windowDidOpen:);
    [windowOpener openWindows:YES];
}

- (void)setLayoutInTab:(PTYTab *)tab
                toLayout:(NSString *)layout
{
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.layout = layout;
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    windowOpener.windowIndex = [tab tmuxWindow];
    [windowOpener updateLayoutInTab:tab];
}

- (void)sessionChangedTo:(NSString *)newSessionName {
    self.sessionName = newSessionName;
    [self closeAllPanes];
    if (dashboard_) {
        [dashboard_ close];
        [dashboard_ release];
        dashboard_ = nil;
    }
    [self openWindowsInitial];
}

- (void)sessionsChanged
{
    [self listSessions];
}

- (void)sessionRenamedTo:(NSString *)newName
{
    self.sessionName = newName;
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
            @"window_layout", @"window_active", nil];

}

- (void)initialListWindowsResponse:(NSString *)response
{
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for initial list windows request: %@", response]];
        return;
    }
    for (NSArray *record in doc.records) {
        [self openWindowWithIndex:[[doc valueInRecord:record forField:@"window_id"] intValue]
                             name:[doc valueInRecord:record forField:@"window_name"]
                             size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                             [[doc valueInRecord:record forField:@"window_height"] intValue])
                           layout:[doc valueInRecord:record forField:@"window_layout"]];
    }
}

- (void)openWindowsInitial
{
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@", kListWindowsFormat];
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_name}\"";
    NSArray *commands = [NSArray arrayWithObjects:
                         [gateway_ dictionaryForCommand:listSessionsCommand
                                         responseTarget:self
                                       responseSelector:@selector(listSessionsResponse:)
                                         responseObject:nil],
                         [gateway_ dictionaryForCommand:listWindowsCommand
                                         responseTarget:self
                                       responseSelector:@selector(initialListWindowsResponse:)
                                         responseObject:nil],
                         nil];
    [gateway_ sendCommandList:commands];
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
               inWindow:(int)window
{
    [self retainWindow:window withTab:[aSession tab]];
    [windowPanes_ setObject:aSession forKey:[self _keyForWindowPane:windowPane]];
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane
{
    [self releaseWindow:window];
    [windowPanes_ removeObjectForKey:[self _keyForWindowPane:windowPane]];
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

- (void)detach
{
    detached_ = YES;
    [self closeAllPanes];
    [gateway_ release];
    gateway_ = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerDetachedNotification
                                                        object:self];
}

- (void)windowDidResize:(PseudoTerminal *)term
{
    NSSize size = [term tmuxCompatibleSize];
    if (size.width == 0 || size.height == 0) {
        // After the last session closes a size of 0 is reported.
        return;
    }
    if (NSEqualSizes(size, lastSize_)) {
        return;
    }
    lastSize_ = size;
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommand:[NSString stringWithFormat:@"set-control-client-attr client-size %d,%d", (int) size.width, (int)size.height]
           responseTarget:self
         responseSelector:@selector(clientSizeChangeResponse:)
           responseObject:nil];
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
    NSString *cmdStr = [NSString stringWithFormat:@"resize-pane -%@ -t %%%d %d",
                        dir, wp, abs(amount)];
    ++numOutstandingWindowResizes_;
    [gateway_ sendCommand:cmdStr
           responseTarget:self
         responseSelector:@selector(clientSizeChangeResponse:)
           responseObject:nil];
}

// The splitVertically parameter uses the iTerm2 conventions.
- (void)splitWindowPane:(int)wp vertically:(BOOL)splitVertically
{
    // No need for a callback. We should get a layout-changed message and act on it.
    [gateway_ sendCommand:[NSString stringWithFormat:@"split-window -%@ -t %%%d", splitVertically ? @"h": @"v", wp]
           responseTarget:nil
         responseSelector:nil];
}

- (void)newWindowWithAffinity:(int)paneNumber
{
    if (paneNumber >= 0) {
        [gateway_ sendCommand:@"new-window -I"
               responseTarget:self
             responseSelector:@selector(newWindowWithAffinityCreated:affinityPane:)
               responseObject:[NSNumber numberWithInt:paneNumber]];
    } else {
        [gateway_ sendCommand:@"new-window"
               responseTarget:nil
             responseSelector:nil];
    }
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

- (void)killWindow:(int)window
{
    [gateway_ sendCommand:[NSString stringWithFormat:@"kill-window -t @%d", window]
           responseTarget:nil
         responseSelector:nil];
}

- (void)breakOutWindowPane:(int)windowPane toPoint:(NSPoint)screenPoint
{
    [windowPositions_ setObject:[NSValue valueWithPoint:screenPoint]
                         forKey:[NSNumber numberWithInt:windowPane]];
    [gateway_ sendCommand:[NSString stringWithFormat:@"break-pane -t %%%d", windowPane]
           responseTarget:nil
         responseSelector:nil];
}

- (void)openWindowWithId:(int)windowId
{
    // Get the window's basic info to prep the creation of a TmuxWindowOpener.
    [gateway_ sendCommand:[NSString stringWithFormat:@"list-windows -F %@ -I %d", kListWindowsFormat, windowId]
           responseTarget:self
         responseSelector:@selector(listedWindowsToOpenOne:forWindowId:)
           responseObject:[NSNumber numberWithInt:windowId]];
}

- (PTYSession *)sessionWithAffinityForTmuxWindowId:(int)windowId
{
    NSNumber *n = [NSNumber numberWithInt:windowId];
    for (NSNumber *k in windowPanes_) {
        PTYSession *aSession = [windowPanes_ objectForKey:k];
        if ([aSession.futureWindowAffinities containsObject:n]) {
            return aSession;
        }
    }
    return nil;
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
}

- (void)listWindowsInSession:(NSString *)sessionName
                      target:(id)target
                    selector:(SEL)selector
                      object:(id)object
{
    NSString *listWindowsCommand = [NSString stringWithFormat:@"list-windows -F %@ -t \"%@\"",
                                    kListWindowsFormat, sessionName];
    [gateway_ sendCommand:listWindowsCommand
           responseTarget:self
         responseSelector:@selector(didListWindows:userData:)
           responseObject:[NSArray arrayWithObjects:object,
                           NSStringFromSelector(selector),
                           target,
                           nil]];
}

- (TmuxDashboardController *)dashboard
{
    if (!dashboard_) {
        dashboard_ = [[TmuxDashboardController alloc] initWithTmuxController:self];
        [dashboard_ showWindow:nil];
    }
    return dashboard_;
}

@end

@implementation TmuxController (Private)

- (void)didListWindows:(NSString *)response userData:(NSArray *)userData
{
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    id object = [userData objectAtIndex:0];
    SEL selector = NSSelectorFromString([userData objectAtIndex:1]);
    id target = [userData objectAtIndex:2];
    [target performSelector:selector withObject:doc withObject:object];
}

- (void)listSessionsResponse:(NSString *)result
{
    self.sessions = [result componentsSeparatedByRegex:@"\n"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerSessionsDidChange
                                                        object:self.sessions];
}

- (void)listedWindowsToOpenOne:(NSString *)response forWindowId:(NSNumber *)windowId
{
    TSVDocument *doc = [response tsvDocumentWithFields:[self listWindowFields]];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for list windows request: %@",
                                         response]];
        return;
    }
    for (NSArray *record in doc.records) {
        if ([[doc valueInRecord:record forField:@"window_id"] intValue] == [windowId intValue]) {
            [self openWindowWithIndex:[[doc valueInRecord:record forField:@"window_id"] intValue]
                                 name:[doc valueInRecord:record forField:@"window_name"]
                                 size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                                 [[doc valueInRecord:record forField:@"window_height"] intValue])
                               layout:[doc valueInRecord:record forField:@"window_layout"]];
        }
    }
}

// When an iTerm2 window is resized, a set-control-client-attr client-size w,h
// command is sent. It responds with new layouts for all the windows in the
// client's session. Update the layouts for the affected tabs.
- (void)clientSizeChangeResponse:(NSString *)response
{
    --numOutstandingWindowResizes_;
    NSArray *layoutStrings = [response componentsSeparatedByString:@"\n"];
    for (NSString *layoutString in layoutStrings) {
        NSArray *components = [layoutString captureComponentsMatchedByRegex:@"^([0-9]+) (.*)"];
        if ([components count] != 3) {
            NSLog(@"Bogus layout string: \"%@\"", layoutString);
        } else {
            int window = [[components objectAtIndex:1] intValue];
            NSString *layout = [components objectAtIndex:2];
            PTYTab *tab = [self window:window];
            if (tab) {
                [[gateway_ delegate] tmuxUpdateLayoutForWindow:window
                                                        layout:layout];
            }
        }
    }
}

- (void)retainWindow:(int)window withTab:(PTYTab *)tab
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    if (entry) {
        NSNumber *refcount = [entry objectAtIndex:1];
        [entry replaceObjectAtIndex:1 withObject:[NSNumber numberWithInt:[refcount intValue] + 1]];
    } else {
        entry = [NSMutableArray arrayWithObjects:tab, [NSNumber numberWithInt:1], nil];
    }
    [windows_ setObject:entry forKey:k];
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
        [windows_ removeObjectForKey:k];
        return;
    }
}

- (void)newWindowWithAffinityCreated:(NSString *)responseStr affinityPane:(NSNumber *)affinityPane
{
    PTYSession *theSession = [self sessionForWindowPane:[affinityPane intValue]];
    [theSession.futureWindowAffinities addObject:[NSNumber numberWithInt:[responseStr intValue]]];
}

- (void)closeAllPanes
{
    // Close all sessions. Iterate over a copy of windowPanes_ because the loop
    // body modifies it by closing sessions.
    for (NSString *key in [[windowPanes_ copy] autorelease]) {
        PTYSession *session = [windowPanes_ objectForKey:key];
        [[[session tab] realParentWindow] softCloseSession:session];
    }

    // Clean up all state to avoid trying to reuse it.
    [windowPanes_ removeAllObjects];
}

- (void)listSessions
{
    NSString *listSessionsCommand = @"list-sessions -F \"#{session_name}\"";
    [gateway_ sendCommand:listSessionsCommand
           responseTarget:self
         responseSelector:@selector(listSessionsResponse:)];
}

- (void)windowDidOpen:(NSNumber *)windowIndex
{
    [pendingWindowOpens_ removeObject:windowIndex];
}

@end
