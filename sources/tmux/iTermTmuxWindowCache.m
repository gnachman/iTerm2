//
//  iTermTmuxWindowCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/20.
//

#import "iTermTmuxWindowCache.h"

#import "NSArray+iTerm.h"
#import "TSVParser.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"

NSString *const iTermTmuxWindowCacheDidChange = @"iTermTmuxWindowCacheDidChange";

@interface iTermTmuxCacheWindow: NSObject
@property (nonatomic) int number;
@property (nonatomic, copy) NSString *name;
@end

@implementation iTermTmuxCacheWindow
@end

@interface iTermTmuxCacheSession: NSObject
@property (nonatomic, strong) iTermTmuxSessionObject *sessionObject;
@property (nonatomic, strong) NSMutableArray<iTermTmuxCacheWindow *> *mutableWindows;
@end

@implementation iTermTmuxCacheSession
- (void)setMutableWindows:(NSMutableArray<iTermTmuxCacheWindow *> *)mutableWindows {
    _mutableWindows = [mutableWindows mutableCopy];
}
@end

@interface iTermTmuxCacheClient: NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSArray<iTermTmuxCacheSession *> *sessions;
@end

@implementation iTermTmuxCacheClient
@end

@implementation iTermTmuxWindowCacheWindowInfo

- (instancetype)initWitCacheWindow:(iTermTmuxCacheWindow *)window
                           session:(iTermTmuxCacheSession *)session
                        clientName:(NSString *)clientName {
    self = [super init];
    if (self) {
        _name = [window.name copy];
        _windowNumber = window.number;
        _sessionNumber = session.sessionObject.number;
        _clientName = [clientName copy];
    }
    return self;
}

@end

@implementation iTermTmuxWindowCache {
    NSMutableArray<iTermTmuxCacheClient *> *_clients;
    BOOL _needsInvalidate;
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
        _clients = [NSMutableArray array];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerDetached:)
                                                     name:kTmuxControllerDetachedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerSessionsDidChange:)
                                                     name:kTmuxControllerSessionsDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowsDidChange:)
                                                     name:kTmuxControllerWindowsChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowWasRenamed:)
                                                     name:kTmuxControllerWindowWasRenamed
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowOpened:)
                                                     name:kTmuxControllerWindowDidOpen
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerWindowClosed:)
                                                     name:kTmuxControllerWindowDidClose
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerSessionWasRenamed:)
                                                     name:kTmuxControllerSessionWasRenamed
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerRegistryDidChange:)
                                                     name:kTmuxControllerRegistryDidChange
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tmuxControllerDidChangeHiddenWindows:)
                                                     name:kTmuxControllerDidChangeHiddenWindows
                                                   object:nil];
    }

    return self;
}

- (NSArray<iTermTmuxWindowCacheWindowInfo *> *)hiddenWindows {
    NSMutableArray<iTermTmuxWindowCacheWindowInfo *> *results = [NSMutableArray array];
    [_clients enumerateObjectsUsingBlock:^(iTermTmuxCacheClient * _Nonnull client, NSUInteger idx, BOOL * _Nonnull stop) {
        TmuxController *controller = [[TmuxControllerRegistry sharedInstance] controllerForClient:client.identifier];
        [client.sessions enumerateObjectsUsingBlock:^(iTermTmuxCacheSession * _Nonnull session, NSUInteger idx, BOOL * _Nonnull stop) {
            if (session.sessionObject.number != controller.sessionId) {
                return;
            }
            [session.mutableWindows enumerateObjectsUsingBlock:^(iTermTmuxCacheWindow * _Nonnull window, NSUInteger idx, BOOL * _Nonnull stop) {
                // Windows that haven't been opened because there were too many at attach time will
                // not be labeled as hidden. Instead, they simply won't have windows. Therefore we
                // don't use windowIsHidden:.
                if ([controller window:window.number] != nil) {
                    return;
                }
                [results addObject:[[iTermTmuxWindowCacheWindowInfo alloc] initWitCacheWindow:window
                                                                                      session:session
                                                                                   clientName:client.identifier]];
            }];
        }];
    }];
    return results;
}

#pragma mark - Notifications

- (void)tmuxControllerDetached:(NSNotification *)notification {
    TmuxController *controller = notification.object;
    iTermTmuxCacheClient *client = [self clientNamed:controller.clientName];
    if (!client) {
        return;
    }
    [_clients removeObject:client];
    [self invalidate];
}

- (void)tmuxControllerSessionsDidChange:(NSNotification *)notification {
    TmuxController *controller = notification.object;
    iTermTmuxCacheClient *client = [self clientNamed:controller.clientName];
    if (!client) {
        client = [[iTermTmuxCacheClient alloc] init];
        client.identifier = controller.clientName;
        [_clients addObject:client];
    }
    client.sessions = [[controller.sessionObjects mapWithBlock:^id(iTermTmuxSessionObject *sessionObject) {
        iTermTmuxCacheSession *session = [[iTermTmuxCacheSession alloc] init];
        session.sessionObject = sessionObject;
        session.mutableWindows = [NSMutableArray array];
        [controller listWindowsInSessionNumber:sessionObject.number
                                        target:self
                                      selector:@selector(setWindows:forSession:)
                                        object:session];
        return session;
    }] mutableCopy];
    [self invalidate];
}

- (void)tmuxControllerWindowsDidChange:(NSNotification *)notification {
    TmuxController *controller = notification.object;
    iTermTmuxCacheSession *session = [self sessionInClient:[self clientNamed:controller.clientName]
                                                    number:controller.sessionId];
    [controller listWindowsInSessionNumber:controller.sessionId
                                    target:self
                                  selector:@selector(setWindows:forSession:)
                                    object:session];
}

- (void)tmuxControllerWindowOpened:(NSNotification *)notification {
    NSArray *params = notification.object;
    const int wid = [params[0] intValue];
    TmuxController *controller = params[1];
    iTermTmuxCacheWindow *window = [self windowInClient:[self clientNamed:controller.clientName]
                                                 number:wid];
    if (!window) {
        return;
    }
    [self invalidate];
}

- (void)tmuxControllerWindowClosed:(NSNotification *)notification {
    NSArray *params = notification.object;
    const int wid = [params[0] intValue];
    TmuxController *controller = params[1];
    iTermTmuxCacheWindow *window = [self windowInClient:[self clientNamed:controller.clientName]
                                                 number:wid];
    iTermTmuxCacheSession *session = [self sessionInClient:[self clientNamed:controller.clientName]
                                                withWindow:window];
    if (![controller windowIsHidden:wid]) {
        [session.mutableWindows removeObject:window];
    }
    [self invalidate];
}

- (void)tmuxControllerWindowWasRenamed:(NSNotification *)notification {
    NSArray *params = notification.object;
    int wid = [params[0] intValue];
    NSString *newName = params[1];
    TmuxController *controller = params[2];
    iTermTmuxCacheWindow *window = [self windowInClient:[self clientNamed:controller.clientName]
                                                 number:wid];
    window.name = newName;
    [self invalidate];
}

- (void)tmuxControllerSessionWasRenamed:(NSNotification *)notification {
    NSArray *params = notification.object;
    NSNumber *sessionID = params[0];
    NSString *newName = params[1];
    TmuxController *controller = params[2];
    iTermTmuxCacheSession *session = [self sessionWithNumber:sessionID.intValue
                                                    inClient:[self clientNamed:controller.clientName]];
    session.sessionObject = [session.sessionObject copyWithName:newName];
    [self invalidate];
}

- (void)tmuxControllerRegistryDidChange:(NSNotification *)notification {
    NSMutableArray<iTermTmuxCacheClient *> *updated = [NSMutableArray array];
    for (NSString *clientName in [[TmuxControllerRegistry sharedInstance] clientNames]) {
        TmuxController *controller = [[TmuxControllerRegistry sharedInstance] controllerForClient:clientName];
        if (!controller) {
            continue;
        }
        iTermTmuxCacheClient *existing = [self clientNamed:clientName];
        if (existing) {
            [updated addObject:existing];
            continue;
        }
        iTermTmuxCacheClient *novel = [[iTermTmuxCacheClient alloc] init];
        novel.identifier = clientName;
        for (iTermTmuxSessionObject *sessionObject in controller.sessionObjects) {
            iTermTmuxCacheSession *session = [[iTermTmuxCacheSession alloc] init];
            session.sessionObject = sessionObject;
            [controller listWindowsInSessionNumber:sessionObject.number
                                            target:self
                                          selector:@selector(didListWindows:forSession:)
                                            object:session];
        }
        [updated addObject:novel];
    }
}

- (void)tmuxControllerDidChangeHiddenWindows:(NSNotification *)notification {
    [self invalidate];
}

#pragma mark - Private

- (iTermTmuxCacheSession *)sessionInClient:(iTermTmuxCacheClient *)client number:(int)number {
    for (iTermTmuxCacheSession *session in client.sessions) {
        if (session.sessionObject.number == number) {
            return session;
        }
    }
    return nil;
}

- (iTermTmuxCacheSession *)sessionInClient:(iTermTmuxCacheClient *)client withWindow:(iTermTmuxCacheWindow *)window {
    for (iTermTmuxCacheSession *session in client.sessions) {
        if ([session.mutableWindows containsObject:window]) {
            return session;
        }
    }
    return nil;
}

- (iTermTmuxCacheWindow *)windowInClient:(iTermTmuxCacheClient *)client number:(int)wid {
    for (iTermTmuxCacheSession *session in client.sessions) {
        for (iTermTmuxCacheWindow *window in session.mutableWindows) {
            if (window.number == wid) {
                return window;
            }
        }
    }
    return nil;
}

- (iTermTmuxCacheClient *)clientNamed:(NSString *)name {
    for (iTermTmuxCacheClient *client in _clients) {
        if ([client.identifier isEqualToString:name]) {
            return client;
        }
    }
    return nil;
}

- (BOOL)haveSession:(iTermTmuxCacheSession *)session {
    for (iTermTmuxCacheClient *client in _clients) {
        if ([client.sessions containsObject:session]) {
            return YES;
        }
    }
    return NO;
}

- (iTermTmuxCacheSession *)sessionWithNumber:(int)number inClient:(iTermTmuxCacheClient *)client {
    for (iTermTmuxCacheSession *session in client.sessions) {
        if (session.sessionObject.number == number) {
            return session;
        }
    }
    return nil;
}

- (void)invalidate {
    if (_needsInvalidate) {
        return;
    }
    _needsInvalidate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reallyInvalidate];
    });
}

- (void)reallyInvalidate {
    _needsInvalidate = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermTmuxWindowCacheDidChange
                                                        object:nil];
}

#pragma mark - Callbacks

- (void)didListWindows:(TSVDocument *)doc forSession:(iTermTmuxCacheSession *)session {
    if (![self haveSession:session]) {
        return;
    }
    NSMutableArray *windows = [NSMutableArray array];
    for (NSArray *record in doc.records) {
        iTermTmuxCacheWindow *window = [[iTermTmuxCacheWindow alloc] init];
        window.name = [doc valueInRecord:record forField:@"window_name"];
        window.number = [[[doc valueInRecord:record forField:@"window_id"] substringFromIndex:1] intValue];
        [windows addObject:window];
    }
    session.mutableWindows = windows;
    [self invalidate];
}

- (void)setWindows:(TSVDocument *)doc forSession:(iTermTmuxCacheSession *)session {
    if (![self haveSession:session]) {
        return;
    }
    [session.mutableWindows removeAllObjects];
    for (NSArray *record in doc.records) {
        iTermTmuxCacheWindow *window = [[iTermTmuxCacheWindow alloc] init];
        window.name = [doc valueInRecord:record forField:@"window_name"];
        window.number = [[[doc valueInRecord:record forField:@"window_id"] substringFromIndex:1] intValue];
        [session.mutableWindows addObject:window];
    }
    [self invalidate];
}

@end
