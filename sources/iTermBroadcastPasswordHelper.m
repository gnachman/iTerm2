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

static const char iTermBroadcastPasswordHelperEchoProbeSessionAssociatedObjectKey;

@interface iTermBroadcastPasswordHelper()<iTermEchoProbeDelegate>
@end

@implementation iTermBroadcastPasswordHelper {
    NSString *_password;
    NSArray<PTYSession *> *_sessions;
    NSMutableArray<PTYSession *> *_failures;
    NSMutableArray<PTYSession *> *_successes;
    NSInteger _indeterminate;
    NSArray<iTermEchoProbe *> *_probes;
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
        _probes = [sessions mapWithBlock:^id(PTYSession *session) {
            if (session.backspaceData) {
                iTermEchoProbe *probe = session.echoProbe;
                probe.delegate = self;
                DLog(@"Use echo probe %@ from session %@", probe, session);
                [probe it_setAssociatedObject:session
                                       forKey:(void *)&iTermBroadcastPasswordHelperEchoProbeSessionAssociatedObjectKey];
                return probe;
            } else {
                return nil;
            }
        }];
        if (_probes.count == 0) {
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
    for (iTermEchoProbe *probe in _probes) {
        PTYSession *session = [self sessionForProbe:probe];
        DLog(@"Probe %@", session);
        if (session) {
            [probe beginProbeWithBackspace:session.backspaceData password:@""];
        }
    }
}

- (PTYSession *)sessionForProbe:(iTermEchoProbe *)probe {
    return [probe it_associatedObjectForKey:(void *)&iTermBroadcastPasswordHelperEchoProbeSessionAssociatedObjectKey];
}

- (void)cleanup {
    if (_cleaningUp) {
        return;
    }
    DLog(@"Clean up %@", self);
    _cleaningUp = YES;
    for (iTermEchoProbe *probe in _probes) {
        probe.delegate = [self sessionForProbe:probe];
    }
    _completion = nil;
    [sBroadcastPasswordHelpers removeObject:self];
}

- (void)checkIfFinished {
    if (_successes.count + _failures.count + _indeterminate < _probes.count) {
        return;
    }
    DLog(@"Finished with successes=%@ failures=%@ indeterminate=%@", _successes, _failures, @(_indeterminate));
    for (PTYSession *session in _completion(_successes, _failures)) {
        DLog(@"Send password to %@", session);
        [session writeTaskNoBroadcast:[_password stringByAppendingString:@"\n"]];
    }
    [self cleanup];
}

#pragma mark - iTermEchoProbeDelegate

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeString:(NSString *)string {
    PTYSession *session = [self sessionForProbe:echoProbe];
    [session writeTaskNoBroadcast:string];
}

- (void)echoProbe:(iTermEchoProbe *)echoProbe writeData:(NSData *)data {
    PTYSession *session = [self sessionForProbe:echoProbe];
    [session writeLatin1EncodedData:data broadcastAllowed:NO];
}

- (void)echoProbeDidSucceed:(iTermEchoProbe *)echoProbe {
    PTYSession *session = [self sessionForProbe:echoProbe];
    DLog(@"Echo probe %@ succeeded for %@", echoProbe, session);
    if (session) {
        [_successes addObject:session];
    } else {
        _indeterminate++;
    }
    [self checkIfFinished];
}

- (void)echoProbeDidFail:(iTermEchoProbe *)echoProbe {
    PTYSession *session = [self sessionForProbe:echoProbe];
    DLog(@"Echo probe %@ failed for session %@", echoProbe, session);
    if (session) {
        [_failures addObject:session];
    } else {
        _indeterminate++;
    }
    [self checkIfFinished];
}

- (BOOL)echoProbeShouldSendPassword:(iTermEchoProbe *)echoProbe {
    return NO;
}

- (void)echoProbeDelegateWillChange:(iTermEchoProbe *)echoProbe {
    DLog(@"Echo probe %@ delegate will change", echoProbe);
    [self cleanup];
}

@end
