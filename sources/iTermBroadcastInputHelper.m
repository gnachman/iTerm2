//
//  iTermBroadcastInputHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/18.
//

#import "iTermBroadcastInputHelper.h"

#import "iTermApplicationDelegate.h"
#import "iTermWarning.h"

#import "NSArray+iTerm.h"

NSString *const iTermBroadcastDomainsDidChangeNotification = @"iTermBroadcastDomainsDidChangeNotification";

@implementation iTermBroadcastInputHelper {
    BroadcastMode _broadcastMode;
    NSMutableSet<NSString *> *_broadcastSessionIDs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _broadcastSessionIDs = [NSMutableSet set];
    }
    return self;
}

- (BroadcastMode)broadcastMode {
    if ([self.delegate broadcastInputHelperCurrentTabIsBroadcasting:self]) {
        return BROADCAST_TO_ALL_PANES;
    } else {
        return _broadcastMode;
    }
}

- (void)toggleSession:(NSString *)sessionID {
    switch ([self broadcastMode]) {
        case BROADCAST_TO_ALL_PANES:
            [self.delegate broadcastInputHelper:self setCurrentTabBroadcasting:NO];
            [_broadcastSessionIDs removeAllObjects];
            [_broadcastSessionIDs addObjectsFromArray:[self.delegate broadcastInputHelperSessionsInCurrentTab:self
                                                                                                includeExited:YES]];
            break;
            
        case BROADCAST_TO_ALL_TABS:
            [_broadcastSessionIDs removeAllObjects];
            [_broadcastSessionIDs addObjectsFromArray:[self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                                                             includeExited:YES]];
            break;
            
        case BROADCAST_OFF:
            [_broadcastSessionIDs removeAllObjects];
            break;
            
        case BROADCAST_CUSTOM:
            break;
    }
    _broadcastMode = BROADCAST_CUSTOM;
    const NSInteger prevCount = [_broadcastSessionIDs count];
    if ([_broadcastSessionIDs containsObject:sessionID]) {
        [_broadcastSessionIDs removeObject:sessionID];
    } else {
        [_broadcastSessionIDs addObject:sessionID];
    }
    if (_broadcastSessionIDs.count == 0) {
        // Untoggled the last session.
        _broadcastMode = BROADCAST_OFF;
    } else if (_broadcastSessionIDs.count == 1 &&
               prevCount == 2) {
        // Untoggled a session and got down to 1. Disable broadcast because you can't broadcast with
        // fewer than 2 sessions.
        _broadcastMode = BROADCAST_OFF;
        [_broadcastSessionIDs removeAllObjects];
    } else if (_broadcastSessionIDs.count == 1) {
        // Turned on one session so add the current session.
        [_broadcastSessionIDs addObject:[self.delegate broadcastInputHelperCurrentSession:self]];
        // NOTE: There may still be only one session. This is of use to focus
        // follows mouse users who want to toggle particular panes.
    }
    [self.delegate broadcastInputHelperDidUpdate:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermBroadcastDomainsDidChangeNotification
                                                        object:nil];
}

- (NSSet<NSString *> *)broadcastSessionIDs {
    switch ([self broadcastMode]) {
        case BROADCAST_OFF:
            return [NSSet set];
            
        case BROADCAST_TO_ALL_PANES:
            return [NSSet setWithArray:[self.delegate broadcastInputHelperSessionsInCurrentTab:self
                                                                                 includeExited:NO]];
            
        case BROADCAST_TO_ALL_TABS:
            return [NSSet setWithArray:[self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                                              includeExited:NO]];
            break;
            
        case BROADCAST_CUSTOM: {
            NSArray<NSString *> *candidates = [self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                                                     includeExited:NO];
            return [NSSet setWithArray:[candidates filteredArrayUsingBlock:^BOOL(NSString *sessionID) {
                return [self->_broadcastSessionIDs containsObject:sessionID];
            }]];
        }
    }
    return [NSSet set];
}

- (void)setBroadcastSessionIDs:(NSSet<NSString *> *)sessionIDs {
    if (sessionIDs.count == 0 &&
        _broadcastMode == BROADCAST_OFF &&
        _broadcastSessionIDs.count == 0) {
        return;
    }
    [_broadcastSessionIDs removeAllObjects];
    [self.delegate broadcastInputHelperSetNoTabBroadcasting:self];
    if (sessionIDs.count > 0) {
        _broadcastMode = BROADCAST_CUSTOM;
        NSSet<NSString *> *validIDs = [NSSet setWithArray:[self.delegate broadcastInputHelperSessionsInAllTabs:self
                                                                                                 includeExited:YES]];
        [_broadcastSessionIDs unionSet:sessionIDs];
        [_broadcastSessionIDs intersectSet:validIDs];
    } else {
        _broadcastMode = BROADCAST_OFF;
    }
    [self.delegate broadcastInputHelperDidUpdate:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermBroadcastDomainsDidChangeNotification object:nil];
}

- (void)setBroadcastMode:(BroadcastMode)mode {
    if (mode != BROADCAST_CUSTOM && mode == self.broadcastMode) {
        mode = BROADCAST_OFF;
    }
    if (mode != BROADCAST_OFF && self.broadcastMode == BROADCAST_OFF) {
        NSWindow *window = [self.delegate broadcastInputHelperWindowForWarnings:self];
        if ([iTermWarning showWarningWithTitle:@"Keyboard input will be sent to multiple sessions."
                                       actions:@[ @"OK", @"Cancel" ]
                                    identifier:@"NoSyncSuppressBroadcastInputWarning"
                                   silenceable:kiTermWarningTypePermanentlySilenceable
                                        window:window] == kiTermWarningSelection1) {
            return;
        }
    }
    if (mode == BROADCAST_TO_ALL_PANES) {
        [self.delegate broadcastInputHelper:self setCurrentTabBroadcasting:YES];
        mode = BROADCAST_OFF;
    } else {
        [self.delegate broadcastInputHelper:self setCurrentTabBroadcasting:NO];
    }
    _broadcastMode = mode;
    [self.delegate broadcastInputHelperDidUpdate:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermBroadcastDomainsDidChangeNotification object:nil];
}

@end
