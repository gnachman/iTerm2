//
//  iTermBroadcastPasswordHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/23/18.
//

#import "iTermBroadcastPasswordHelper.h"

#import "DebugLogging.h"
#import "iTermEchoProbe.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "PTYSession.h"

@interface iTermEchoProbeDelegateProxy: NSObject<iTermEchoProbeDelegate>
@property (nonatomic, weak) iTermBroadcastPasswordHelper *passwordHelper;
@property (nonatomic, weak) PTYSession *session;
@end

@implementation iTermBroadcastPasswordHelper {
    NSString *_password;
    NSArray<PTYSession *> *_sessions;
    NSMutableArray<PTYSession *> *_failures;
    NSMutableArray<PTYSession *> *_successes;
    NSInteger _indeterminate;
    NSArray<iTermEchoProbeDelegateProxy *> *_proxies;
    NSArray<PTYSession *> *(^_completion)(NSArray<PTYSession *> *, NSArray<PTYSession *> *);
    BOOL _cleaningUp;
}

static NSMutableArray<iTermBroadcastPasswordHelper *> *sBroadcastPasswordHelpers;

+ (void)tryToSendPassword:(NSString *)password
               toSessions:(NSArray<PTYSession *> *)sessions
               completion:(NSArray<PTYSession *> * _Nonnull (^)(NSArray<PTYSession *> * _Nonnull, NSArray<PTYSession *> * _Nonnull))completion {
    static dispatch_once_t onceToken;
    iTermBroadcastPasswordHelper *helper = [[self alloc] initWithPassword:password
                                                                 sessions:sessions
                                                               completion:completion];
    if (helper) {
        dispatch_once(&onceToken, ^{
            sBroadcastPasswordHelpers = [NSMutableArray array];
        });
        [sBroadcastPasswordHelpers addObject:helper];
        [helper beginProbes];
    }
}

- (instancetype)initWithPassword:(NSString *)password
                        sessions:(NSArray<PTYSession *> *)sessions
                      completion:(NSArray<PTYSession *> *(^)(NSArray<PTYSession *> *, NSArray<PTYSession *> *))completion {
    if (sessions.count == 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        DLog(@"%p Broadcast password to sessions %@", self, sessions);
        _password = [password copy];
        _sessions = [sessions copy];
        _completion = [completion copy];
        _failures = [NSMutableArray array];
        _successes = [NSMutableArray array];
        _proxies = [sessions mapWithBlock:^id(PTYSession *session) {
            if (session.backspaceData) {
                iTermEchoProbeDelegateProxy *proxy = [[iTermEchoProbeDelegateProxy alloc] init];
                proxy.session = session;
                proxy.passwordHelper = self;
                [session.screen setEchoProbeDelegate:proxy];
                DLog(@"Use echo probe from session %@ with proxy %@", session, proxy);
                return proxy;
            } else {
                return nil;
            }
        }];
        if (_proxies.count == 0) {
            // No session can probe. Just send.
            for (PTYSession *session in sessions) {
                [session enterPassword:password];
            }
            return nil;
        }
    }
    return self;
}

- (void)beginProbes {
    for (iTermEchoProbeDelegateProxy *proxy in _proxies) {
        PTYSession *session = proxy.session;
        DLog(@"Probe %@", session);
        if (session) {
            [session.screen beginEchoProbeWithBackspace:session.backspaceData password:@"" delegate:proxy];
        }
    }
}

- (void)cleanup {
    if (_cleaningUp) {
        return;
    }
    DLog(@"Clean up %@", self);
    _cleaningUp = YES;
    [_proxies enumerateObjectsUsingBlock:^(iTermEchoProbeDelegateProxy * _Nonnull proxy, NSUInteger idx, BOOL * _Nonnull stop) {
        PTYSession *session = proxy.session;
        if (session) {
            [session.screen setEchoProbeDelegate:session];
        }
    }];
    _completion = nil;
    [sBroadcastPasswordHelpers removeObject:self];
}

- (void)checkIfFinished {
    if (_successes.count + _failures.count + _indeterminate < _proxies.count) {
        return;
    }
    DLog(@"Finished with successes=%@ failures=%@ indeterminate=%@", _successes, _failures, @(_indeterminate));
    for (PTYSession *session in _completion(_successes, _failures)) {
        DLog(@"Send password to %@", session);
        [session writeTaskNoBroadcast:[_password stringByAppendingString:@"\n"]];
    }
    [self cleanup];
}

- (void)addSuccess:(PTYSession *)session {
    [_successes addObject:session];
}

- (void)addFailure:(PTYSession *)session {
    [_failures addObject:session];
}

- (void)incrementIndeterminateCount {
    _indeterminate++;
}

@end

@implementation iTermEchoProbeDelegateProxy

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeString:(NSString *)string {
    // Dispatch because this will join threads.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.session writeTaskNoBroadcast:string];
    });
}

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeData:(NSData *)data {
    // Dispatch because this will join threads.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.session writeLatin1EncodedData:data broadcastAllowed:NO reporting:NO];
    });
}

- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe {
    PTYSession *session = self.session;
    DLog(@"Echo probe %@ succeeded for %@", echoProbe, session);
    if (session) {
        [self.passwordHelper addSuccess:session];
    } else {
        [self.passwordHelper incrementIndeterminateCount];
    }
    [self.passwordHelper checkIfFinished];
}

- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe {
    PTYSession *session = self.session;
    DLog(@"Echo probe %@ failed for session %@", echoProbe, session);
    if (session) {
        [self.passwordHelper addFailure:session];
    } else {
        [self.passwordHelper incrementIndeterminateCount];
        [session.screen resetEchoProbe];
    }
    [self.passwordHelper checkIfFinished];
}

- (BOOL)echoProbeShouldSendPassword:(iTermEchoProbe *)echoProbe {
    return NO;
}

- (void)echoProbeDelegateWillChange:(iTermEchoProbe *)echoProbe {
    DLog(@"Echo probe %@ delegate will change", echoProbe);
    [self.passwordHelper cleanup];
}

@end
