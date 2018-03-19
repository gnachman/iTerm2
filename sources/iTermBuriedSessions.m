//
//  iTermBuriedSessions.m
//  iTerm2
//
//  Created by George Nachman on 1/25/17.
//
//

#import "iTermBuriedSessions.h"

#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermProfilePreferences.h"
#import "iTermRestorableSession.h"
#import "NSArray+iTerm.h"
#import "PseudoTerminal.h"
#import "PTYSession.h"
#import "PTYTab.h"

@implementation iTermBuriedSessions {
    NSMutableArray<iTermRestorableSession *> *_array;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _array = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_array release];
    [super dealloc];
}

- (void)addBuriedSession:(PTYSession *)sessionToBury {
    id<iTermWindowController> windowController = (PseudoTerminal *)sessionToBury.delegate.parentWindow;
    iTermRestorableSession *restorableSession = [windowController restorableSessionForSession:sessionToBury];
    if (!restorableSession) {
        return;
    }
    [_array addObject:restorableSession];
    [[[iTermApplication sharedApplication] delegate] updateBuriedSessionsMenu];
    [NSApp invalidateRestorableState];
}

- (void)restoreSession:(PTYSession *)session {
    iTermRestorableSession *restorableSession = nil;
    for (iTermRestorableSession *candidate in _array) {
        if ([candidate.sessions containsObject:session]) {
            restorableSession = candidate;
            break;
        }
    }
    if (!restorableSession) {
        return;
    }
    [[restorableSession retain] autorelease];
    [_array removeObject:restorableSession];
    [session disinter];
    PseudoTerminal *term = [[iTermController sharedInstance] terminalWithGuid:restorableSession.terminalGuid];
    if (term) {
        // Reuse an existing window
        PTYTab *tab = [term tabWithUniqueId:restorableSession.tabUniqueId];
        if (tab) {
            // Add to existing tab by destroying and recreating it.
            [term recreateTab:tab
              withArrangement:restorableSession.arrangement
                     sessions:restorableSession.sessions
                       revive:NO];
        } else {
            // Create a new tab and add the session to it.
            [term addRevivedSession:restorableSession.sessions[0]];
        }
    } else {
        // Create a new term and add the session to it.
        term = [[[PseudoTerminal alloc] initWithSmartLayout:YES
                                                 windowType:restorableSession.windowType
                                            savedWindowType:restorableSession.savedWindowType
                                                     screen:restorableSession.screen] autorelease];
        if (term) {
            [[iTermController sharedInstance] addTerminalWindow:term];
            term.terminalGuid = restorableSession.terminalGuid;
            [term addRevivedSession:restorableSession.sessions[0]];
            [term fitWindowToTabs];

            if (restorableSession.windowType == WINDOW_TYPE_LION_FULL_SCREEN) {
                [term delayedEnterFullscreen];
            }
        }
    }
    [[[iTermApplication sharedApplication] delegate] updateBuriedSessionsMenu];
    [NSApp invalidateRestorableState];
}

- (NSArray<PTYSession *> *)buriedSessions {
    return [_array flatMapWithBlock:^NSArray *(iTermRestorableSession *anObject) {
        return anObject.sessions;
    }];
}

- (NSArray<NSDictionary *> *)restorableState {
    return [_array mapWithBlock:^id(iTermRestorableSession *anObject) {
        return [anObject restorableState];
    }];
}

- (void)restoreFromState:(NSArray<NSDictionary *> *)state {
    for (NSDictionary *dict in state) {
        iTermRestorableSession *restorable = [[[iTermRestorableSession alloc] initWithRestorableState:dict] autorelease];
        if (restorable) {
            [_array addObject:restorable];
        }
    }
    [[[iTermApplication sharedApplication] delegate] updateBuriedSessionsMenu];
}

@end
