//
//  iTermInProcessIt2.m
//  iTerm2
//

#import "iTermInProcessIt2.h"

#import "Api.pbobjc.h"
#import "DebugLogging.h"
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
// NO if the API was disabled between the caller's isEnabled check and registration; the
// caller must then not run the command (a receive would block forever).
@property (nonatomic, readonly) BOOL registered;
@end

@implementation iTermIt2APIChannel {
    iTermInProcessAPIConnection *_connection;
    NSCondition *_condition;
    NSMutableArray<ITMServerOriginatedMessage *> *_responses;  // @synchronized via _condition
    NSUInteger _readIndex;  // FIFO read cursor into _responses (amortized O(1) dequeue)
    BOOL _disconnected;
    BOOL _cancelledByClient;  // -disconnect (client cancel) vs -abortFromServer (failure)
    BOOL _didUnregister;  // guards double-unregister (cancel then normal cleanup)
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
        _registered = [[iTermAPIHelper sharedInstance] registerInProcessAPIConnection:_connection
                                                                          displayName:displayName];
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
    DLog(@"it2 channel abortFromServer");
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
    // Blocks this (background, per-command) thread until a response arrives or the connection
    // disconnects. There is deliberately NO timeout: a streaming command (monitor --follow)
    // idles here for arbitrarily long between notifications. Consequence/coupling: if the
    // server parked this connection's request behind another API client's open transaction
    // (see -[iTermAPIServer dispatchInProcessRequest:...]), this wait does not end until that
    // transaction does. Only a remote Ctrl-C / disconnect (-> -disconnect / -abortFromServer)
    // can unblock it early. Fixing that stall is part of the deferred event-driven redesign.
    [_condition lock];
    while (_readIndex >= _responses.count && !_disconnected) {
        [_condition wait];
    }
    ITMServerOriginatedMessage *message = nil;
    if (_readIndex < _responses.count) {
        // Amortized O(1) FIFO: advance a read cursor instead of removeObjectAtIndex:0, which
        // shifts the entire backlog on every pop -> O(n^2) under a firehose (`monitor
        // --follow`, a large `session read`). Compact the consumed prefix occasionally so the
        // array cannot grow without bound when a producer outruns the consumer.
        message = _responses[_readIndex];
        _readIndex++;
        if (_readIndex >= 256 && _readIndex * 2 >= _responses.count) {
            [_responses removeObjectsInRange:NSMakeRange(0, _readIndex)];
            _readIndex = 0;
        }
    }
    const BOOL cancelled = _cancelledByClient;
    [_condition unlock];
    if (!message && error) {
        // No message and disconnected. The domain/codes are the shared IT2ChannelDisconnect
        // contract (defined in it2core, consumed by ObjCChannelAdapter): cancelCode (client
        // cancel, e.g. remote Ctrl+C) unwinds to a clean exit 0; abortCode (server abort via
        // -abortFromServer: API disabled/stop, or a response frame that failed to parse) is a
        // genuine failure and must be surfaced as an error, not silently reported as success.
        if (cancelled) {
            *error = [NSError errorWithDomain:IT2ChannelDisconnect.domain
                                         code:IT2ChannelDisconnect.cancelCode
                                     userInfo:@{ NSLocalizedDescriptionKey: @"in-process it2 channel cancelled" }];
        } else {
            *error = [NSError errorWithDomain:IT2ChannelDisconnect.domain
                                         code:IT2ChannelDisconnect.abortCode
                                     userInfo:@{ NSLocalizedDescriptionKey: @"the iTerm2 API connection was closed" }];
        }
    }
    return message;
}

- (void)disconnect {
    DLog(@"it2 channel disconnect (alreadyUnregistered=%d)", _didUnregister);
    // Idempotent: -cancel and the normal post-run cleanup can both call this. Only
    // the first unregisters (which posts a single Script Console "closed" event).
    [_condition lock];
    const BOOL alreadyUnregistered = _didUnregister;
    _didUnregister = YES;
    _disconnected = YES;
    // Client-initiated (remote Ctrl+C cancel or post-run cleanup), as opposed to a server
    // abort/parse failure via -abortFromServer; the receiver uses this to report exit 0.
    _cancelledByClient = YES;
    [_condition broadcast];
    [_condition unlock];
    if (!alreadyUnregistered) {
        [[iTermAPIHelper sharedInstance] unregisterInProcessAPIConnection:_connection];
    }
}

@end

@implementation iTermInProcessIt2

+ (void)runWithArguments:(NSArray<NSString *> *)arguments
        originIdentifier:(NSString *)originIdentifier
       originDisplayName:(NSString *)originDisplayName
           stdoutHandler:(void (^)(NSString *))stdoutBlock
           stderrHandler:(void (^)(NSString *))stderrBlock
     cancellationHandler:(void (^)(dispatch_block_t))cancellationHandler
              completion:(void (^)(int32_t))completion {
    // A dedicated serial queue per command, not the shared global concurrent utility
    // queue: each command blocks its thread in -receiveMessage for its whole lifetime
    // (indefinitely for `monitor --follow`), so parking those on the shared global pool
    // could exhaust its width and starve other QOS_UTILITY dispatch_async work in the app.
    // GCD keeps the queue alive until this block finishes; ARC manages the local ref.
    dispatch_queue_t queue =
        dispatch_queue_create("com.iterm2.it2.command",
                              dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                      QOS_CLASS_UTILITY, 0));
    dispatch_async(queue, ^{
        // Policy (is the API enabled? is this remote origin authorized?) is enforced by
        // the caller, which owns the ssh session and can present an in-session prompt.
        // By the time we get here the command is cleared to run.
        DLog(@"iTermInProcessIt2 run %@ origin=%@", arguments, originDisplayName);
        id key = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:originIdentifier];
        iTermIt2APIChannel *channel = [[iTermIt2APIChannel alloc] initWithKey:key displayName:originDisplayName];
        if (!channel.registered) {
            // The API was disabled in the race window between the caller's isEnabled check
            // and registration. Fail fast rather than run a command whose first receive
            // would block forever (the connection was never registered).
            DLog(@"iTermInProcessIt2: channel not registered (API disabled); aborting");
            stderrBlock(@"The iTerm2 Python API is not enabled (Settings > General > Magic).");
            [channel disconnect];
            completion(2);
            return;
        }
        // Hand the caller a cancel hook before we block running the command:
        // disconnecting the channel unblocks a waiting receive so the command unwinds.
        if (cancellationHandler) {
            cancellationHandler(^{ [channel disconnect]; });
        }
        const int32_t exitCode = [IT2Runner runArguments:arguments
                                           stdoutHandler:stdoutBlock
                                           stderrHandler:stderrBlock
                                                 channel:channel];
        // Unregister even if the command never opened a client (e.g. --version),
        // which would otherwise leave the synthetic connection registered.
        // Idempotent with the client's own disconnect on the command path.
        DLog(@"iTermInProcessIt2 finished %@ exit=%d", arguments, exitCode);
        [channel disconnect];
        completion(exitCode);
    });
}

@end
