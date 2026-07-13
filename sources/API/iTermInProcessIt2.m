//
//  iTermInProcessIt2.m
//  iTerm2
//

#import "iTermInProcessIt2.h"

#import "Api.pbobjc.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermAPIHelper.h"
#import "iTermInProcessAPIConnection.h"
#import "it2core-Swift.h"  // IT2Runner, IT2Channel (generated from the it2core module)

// Bridges it2core's IT2Channel to iTermAPIServer's in-process dispatch. `send`
// dispatches a request; the synthetic connection's responseHandler parses each
// ITMServerOriginatedMessage (responses + subscription notifications) onto a
// blocking queue that `receiveMessage` drains. All queueing happens off the main
// thread; the actual request handlers still run on the main thread.
@interface iTermIt2APIChannel : NSObject <IT2Channel>
@end

@implementation iTermIt2APIChannel {
    iTermInProcessAPIConnection *_connection;
    NSCondition *_condition;
    NSMutableArray<ITMServerOriginatedMessage *> *_responses;  // @synchronized via _condition
    BOOL _disconnected;
}

- (instancetype)initWithKey:(id)key displayName:(NSString *)displayName {
    self = [super init];
    if (self) {
        _condition = [[NSCondition alloc] init];
        _responses = [NSMutableArray array];
        __weak __typeof(self) weakSelf = self;
        _connection = [[iTermInProcessAPIConnection alloc] initWithKey:key
                                                       responseHandler:^(NSData *responseData) {
            [weakSelf enqueueResponseData:responseData];
        }];
        // If the server tears the connection down mid-command (API disabled,
        // server stop), unblock a waiting receiver instead of deadlocking.
        _connection.onAbort = ^{ [weakSelf abortFromServer]; };
        [[iTermAPIHelper sharedInstance] registerInProcessAPIConnection:_connection displayName:displayName];
    }
    return self;
}

- (void)enqueueResponseData:(NSData *)responseData {
    ITMServerOriginatedMessage *message = [ITMServerOriginatedMessage parseFromData:responseData error:nil];
    if (!message) {
        // A malformed message means the stream can no longer be trusted; fail
        // closed so a blocked receiver returns an error rather than hanging.
        [self abortFromServer];
        return;
    }
    [_condition lock];
    [_responses addObject:message];
    [_condition signal];
    [_condition unlock];
}

// Called when the server aborts the connection or the stream is unusable. Wakes
// any thread blocked in -receiveMessageAndReturnError:, which then returns an error.
- (void)abortFromServer {
    [_condition lock];
    _disconnected = YES;
    [_condition broadcast];
    [_condition unlock];
}

#pragma mark - IT2Channel

- (BOOL)send:(ITMClientOriginatedMessage *)request error:(NSError **)error {
    [[iTermAPIHelper sharedInstance] dispatchInProcessAPIRequest:request connection:_connection];
    return YES;
}

- (ITMServerOriginatedMessage *)receiveMessageAndReturnError:(NSError **)error {
    [_condition lock];
    while (_responses.count == 0 && !_disconnected) {
        [_condition wait];
    }
    ITMServerOriginatedMessage *message = nil;
    if (_responses.count > 0) {
        message = _responses.firstObject;
        [_responses removeObjectAtIndex:0];
    }
    [_condition unlock];
    if (!message && error) {
        *error = [NSError errorWithDomain:@"com.googlecode.iterm2.it2"
                                     code:1
                                 userInfo:@{ NSLocalizedDescriptionKey: @"in-process it2 channel disconnected" }];
    }
    return message;
}

- (void)disconnect {
    [[iTermAPIHelper sharedInstance] unregisterInProcessAPIConnection:_connection];
    [_condition lock];
    _disconnected = YES;
    [_condition broadcast];
    [_condition unlock];
}

@end

@implementation iTermInProcessIt2

+ (void)runWithArguments:(NSArray<NSString *> *)arguments
        originIdentifier:(NSString *)originIdentifier
       originDisplayName:(NSString *)originDisplayName
                  stdout:(void (^)(NSString *))stdoutBlock
                  stderr:(void (^)(NSString *))stderrBlock
              completion:(void (^)(int32_t))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (![iTermAPIHelper isEnabled]) {
            stderrBlock(@"The iTerm2 Python API is not enabled (Settings > General > Magic).");
            completion(2);
            return;
        }
        // Option E: prompt once per ssh session for API access (main thread; blocks
        // this background thread until the user decides).
        __block BOOL authorized = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            authorized = [[iTermAPIHelper sharedInstance] authorizeInProcessOrigin:originIdentifier
                                                                       displayName:originDisplayName];
        });
        if (!authorized) {
            stderrBlock(@"Permission denied: iTerm2 API access was not granted for this session.");
            completion(1);
            return;
        }

        id key = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:originIdentifier];
        iTermIt2APIChannel *channel = [[iTermIt2APIChannel alloc] initWithKey:key displayName:originDisplayName];
        const int32_t exitCode = [IT2Runner runArguments:arguments
                                                  stdout:stdoutBlock
                                                  stderr:stderrBlock
                                                 channel:channel];
        // Unregister even if the command never opened a client (e.g. --version),
        // which would otherwise leave the synthetic connection registered.
        // Idempotent with the client's own disconnect on the command path.
        [channel disconnect];
        completion(exitCode);
    });
}

@end
