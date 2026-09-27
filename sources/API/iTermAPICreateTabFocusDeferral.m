//
//  iTermAPICreateTabFocusDeferral.m
//  iTerm2
//
//  WORKAROUND (not a general design). Scope: iterm2 Python library < 2.23.
//
//  The problem it papers over lives in the client library, but is easiest to
//  neutralize on the server:
//
//  A Python script that does
//
//      window = await iterm2.Window.async_create(...)
//      tab = window.current_tab            // -> None
//      session = tab.current_session       // -> None
//
//  gets None for current_tab / current_session on library versions in
//  [2.21, 2.23). Those versions only learn a window's selected tab / active
//  session from FocusChanged notifications, and their recovery path
//  (async_refresh) is swallowed by a re-entrancy guard (first shipped in 2.21)
//  when a selected_tab / session notification arrives before the client knows the
//  new window exists. Because iTerm2 selects the new tab synchronously while
//  creating it, those notifications go out BEFORE the CreateTab response, so the
//  affected connection is guaranteed to be in exactly that state. Versions 2.20
//  and earlier predate the guard and reconcile correctly, so they are NOT
//  affected.
//
//  Fix in the library (>= 2.23): the selected tab id and per-tab active session
//  id are carried in ListSessionsResponse, so current_tab / current_session are
//  correct straight out of the refresh CreateTab already performs, with no
//  dependence on notification timing. For those clients this workaround does
//  nothing.
//
//  What this object does for older clients: it is scoped to the *connection*
//  doing the create, which is the unit the bug actually lives in. While an
//  affected connection has a create in flight, its selected_tab / active-session
//  FocusChanged notifications are held (the connection is "holding"); every other
//  connection keeps receiving focus notifications live. After the create's
//  response has been sent, it replays its OWN selection to that one connection
//  using the ids it just produced, so the value lands on a window the connection
//  now knows about. Replaying per-create by known id, to the originating
//  connection only, means concurrent creates -- across connections or within one
//  -- never interfere.
//
//  Concurrency note: the API server dispatches all handlers on the main thread, so
//  this object is only ever touched from there. It is not thread-safe and does not
//  need to be; it only has to survive asynchronously interleaved begin/end pairs
//  (a create's selection fires, and its response is sent, long after it begins).
//  Connections are tracked in a counted set so overlapping creates on the same
//  connection balance correctly.
//
//  When every supported client is >= 2.23 this whole file can be deleted.
//

#import "iTermAPICreateTabFocusDeferral.h"

#import "Api.pbobjc.h"
#import "DebugLogging.h"

// The affected iterm2 Python library range is [firstAffected, fixed):
//  - 2.21 first shipped the async_refresh re-entrancy guard that swallows the
//    recovery refresh; 2.20 and earlier have no guard and reconcile correctly,
//    so they are NOT affected.
//  - 2.23 carries the selected tab / active session in ListSessionsResponse, so
//    current_tab / current_session no longer depend on a focus notification.
// Only versions in between (2.21, 2.22) exhibit the bug and need the deferral.
static NSString *const iTermAPICreateTabFocusDeferralFirstAffectedPythonVersion = @"2.21";
static NSString *const iTermAPICreateTabFocusDeferralFixedPythonVersion = @"2.23";

@interface iTermAPICreateTabFocusDeferralToken ()
// The connection this create belongs to. Used to stop holding when it ends.
@property (nonatomic, copy) NSString *connectionGuid;
@end

@implementation iTermAPICreateTabFocusDeferralToken
@end

@implementation iTermAPICreateTabFocusDeferral {
    // Guids of connections with an affected create in flight. A notification is
    // held only if its destination connection is in here. Counted so overlapping
    // creates on one connection balance correctly.
    NSCountedSet<NSString *> *_holdingConnectionGuids;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _holdingConnectionGuids = [[NSCountedSet alloc] init];
    }
    return self;
}

// Whether a client advertising `libraryVersion` (the raw x-iterm2-library-version
// header, e.g. "python 2.22") falls in the affected range [2.21, 2.23) and needs
// the deferral.
+ (BOOL)libraryVersionIsAffected:(NSString *)libraryVersion {
    if (libraryVersion.length == 0) {
        // No header (e.g. the in-process runtime): that runtime ships the
        // current, fixed library, so treat it as unaffected.
        return NO;
    }
    NSArray<NSString *> *parts = [libraryVersion componentsSeparatedByString:@" "];
    if (parts.count != 2) {
        return NO;
    }
    if (![parts[0] isEqualToString:@"python"]) {
        return NO;
    }
    NSString *version = parts[1];
    // Only compare well-formed dotted-numeric versions; anything else is treated
    // as unaffected rather than risking a bogus comparison.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
    if (version.length == 0 ||
        [version rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        return NO;
    }
    // Affected iff firstAffected <= version < fixed. NSNumericSearch orders each
    // dotted component numerically, so "2.9" < "2.21" (a plain decimal or lexical
    // compare would get this backwards now that the minor exceeds 9).
    const BOOL atLeastFirstAffected =
        [version compare:iTermAPICreateTabFocusDeferralFirstAffectedPythonVersion
                 options:NSNumericSearch] != NSOrderedAscending;
    const BOOL beforeFixed =
        [version compare:iTermAPICreateTabFocusDeferralFixedPythonVersion
                 options:NSNumericSearch] == NSOrderedAscending;
    return atLeastFirstAffected && beforeFixed;
}

- (iTermAPICreateTabFocusDeferralToken *)beginCreateTabForConnectionGuid:(NSString *)connectionGuid
                                                         libraryVersion:(NSString *)libraryVersion {
    if (![[self class] libraryVersionIsAffected:libraryVersion]) {
        return nil;
    }
    if (connectionGuid.length == 0) {
        return nil;
    }
    iTermAPICreateTabFocusDeferralToken *token = [[iTermAPICreateTabFocusDeferralToken alloc] init];
    token.connectionGuid = connectionGuid;
    [_holdingConnectionGuids addObject:connectionGuid];
    DLog(@"Holding focus notifications for connection %@ (library “%@”)", connectionGuid, libraryVersion);
    return token;
}

- (BOOL)shouldHoldFocusNotificationForConnectionGuid:(NSString *)connectionGuid {
    if (connectionGuid.length == 0) {
        return NO;
    }
    return [_holdingConnectionGuids countForObject:connectionGuid] > 0;
}

- (void)endCreateTabWithToken:(iTermAPICreateTabFocusDeferralToken *)token
                selectedTabId:(NSString *)selectedTabId
              activeSessionId:(NSString *)activeSessionId
                       replay:(void (^)(ITMFocusChangedNotification *, NSString *))replay {
    if (!token) {
        return;
    }
    NSString *connectionGuid = token.connectionGuid;
    if (connectionGuid.length) {
        [_holdingConnectionGuids removeObject:connectionGuid];
    }

    if (selectedTabId) {
        DLog(@"Replaying selected_tab=%@ to connection %@ after CreateTab response",
             selectedTabId, connectionGuid);
        ITMFocusChangedNotification *notification = [[ITMFocusChangedNotification alloc] init];
        notification.selectedTab = selectedTabId;
        replay(notification, connectionGuid);
    }
    if (activeSessionId) {
        DLog(@"Replaying active session=%@ to connection %@ after CreateTab response",
             activeSessionId, connectionGuid);
        ITMFocusChangedNotification *notification = [[ITMFocusChangedNotification alloc] init];
        notification.session = activeSessionId;
        replay(notification, connectionGuid);
    }
}

@end
