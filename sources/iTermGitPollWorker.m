//
//  iTermGitPollWorker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitPollWorker.h"

#import "DebugLogging.h"

#import "iTermAdvancedSettingsModel.h"
#import "iTermCommandRunner.h"
#import "iTermCommandRunnerPool.h"
#import "iTermGitCache.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

static const int gNumberOfGitPollWorkerBuckets = 4;

typedef void (^iTermGitCallback)(iTermGitState * _Nullable);

@implementation iTermGitPollWorker {
    iTermCommandRunner *_commandRunner;
    NSMutableData *_readData;
    NSMutableArray<NSString *> *_queue;
    iTermGitCache *_cache;
    NSMutableDictionary<NSString *, NSMutableArray<iTermGitCallback> *> *_outstanding;
    int _bucket;
}

+ (iTermCommandRunnerPool *)commandRunnerPool {
    static iTermCommandRunnerPool *pool;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        NSString *script = [bundle pathForResource:@"iterm2_git_poll" ofType:@"sh"];
        if (!script) {
            DLog(@"failed to get path to script from bundle %@", bundle);
            return;
        }
        NSString *sandboxConfig = [[[NSString stringWithContentsOfFile:[bundle pathForResource:@"git" ofType:@"sb"]
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil] componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "];
        pool = [[iTermCommandRunnerPool alloc] initWithCapacity:gNumberOfGitPollWorkerBuckets
                                                        command:@"/usr/bin/sandbox-exec"
                                                      arguments:@[ @"-p", sandboxConfig, script ]
                                               workingDirectory:@"/"
                                                    environment:@{}];
    });
    return pool;
}

+ (instancetype)instanceForPath:(NSString *)path {
    // If one of the gets hung because of a network file system then it won't affect most of the
    // others.
    static dispatch_once_t onceToken[gNumberOfGitPollWorkerBuckets];
    static id instances[gNumberOfGitPollWorkerBuckets];
    const int bucket = [path hash] % gNumberOfGitPollWorkerBuckets;
    dispatch_once(&onceToken[bucket], ^{
        instances[bucket] = [[self alloc] initWithBucket:bucket];
    });
    return instances[bucket];
}

- (instancetype)initWithBucket:(int)bucket {
    self = [super init];
    if (self) {
        _bucket = bucket;
        _readData = [NSMutableData data];
        _queue = [NSMutableArray array];
        _cache = [[iTermGitCache alloc] init];
        _outstanding = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)invalidateCacheForPath:(NSString *)path {
    DLog(@"git poll worker for bucket %d: remove cache entry for path %@", _bucket, path);
    [_cache removeStateForPath:path];
}

- (NSDictionary<NSString *, NSString *> *)environment {
    NSString *searchPath = [iTermAdvancedSettingsModel gitSearchPath];
    if (searchPath.length) {
        NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
        NSString *key = @"PATH";
        NSString *existingPath = environment[key] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
        environment[key] = [NSString stringWithFormat:@"%@:%@", searchPath, existingPath];
        return environment;
    } else {
        return [[NSProcessInfo processInfo] environment];
    }
}

- (void)requestPath:(NSString *)path completion:(iTermGitCallback)completion {
    DLog(@"git poll worker for bucket %d: got request for path %@", _bucket, path);
    // This age limits the polling rate. If an older cache entry is around it will still be used
    // until expiry when the poll command fails.
    iTermGitState *cached = [_cache stateForPath:path maximumAge:[iTermAdvancedSettingsModel gitTimeout]];
    if (cached) {
        DLog(@"git poll worker for bucket %d: return cached value %@ for path %@", _bucket, cached, path);
        completion(cached);
        return;
    }

    NSMutableArray<iTermGitCallback> *callbacks = _outstanding[path];
    if (callbacks) {
        [callbacks addObject:[completion copy]];
        DLog(@"git poll worker for bucket %d: Attach request for %@ to existing callback (totalling %@ callbacks)", _bucket, path, @(callbacks.count));
        return;
    }
    DLog(@"git poll worker for bucket %d: This is a new path. Enqueue request for %@", _bucket, path);
    callbacks = [NSMutableArray array];
    _outstanding[path] = callbacks;

    if (!_commandRunner) {
        const int bucket = _bucket;
        DLog(@"git poll worker for bucket %d: create a new command runner.", bucket);
        __weak __typeof(self) weakSelf = self;
        iTermCommandRunnerPool *pool = [iTermGitPollWorker commandRunnerPool];
        pool.environment = [self environment];
        _commandRunner = [pool requestCommandRunnerWithTerminationBlock:^(iTermCommandRunner *decedent, int status) {
            DLog(@"git poll worker for bucket %d: command runner terminated with status %@. Resetting it.", bucket, @(status));
            [weakSelf commandRunnerDied:decedent];
        }];
        if (!_commandRunner) {
            DLog(@"git poll worker for bucket %d: failed to allocate command runner", bucket);
            [self reset];
            return;
        }
        _commandRunner.outputHandler = ^(NSData *data) {
            [weakSelf didRead:data];
        };
        [_commandRunner run];
    }

    DLog(@"git poll worker for bucket %d: Using command runner %@ for path %@", _bucket, _commandRunner, path);
    __block BOOL finished = NO;
    const int bucket = _bucket;
    void (^callbackWrapper)(iTermGitState *) = ^(iTermGitState *state) {
        DLog(@"git poll worker for bucket %d: Callback wrapper invoked with state %@", bucket, state);
        if (state) {
            // This gives the maximum age to show a stale entry. It does not limit the polling rate.
            [self->_cache setState:state forPath:path ttl:10];
        }
        if (!finished) {
            DLog(@"git poll worker for bucket %d: Command runner %@ finished", bucket, self->_commandRunner);
            finished = YES;
            completion(state);
        } else {
            DLog(@"git poll worker for bucket %d: [already killed] - Command runner %@ finished",
                 bucket, self->_commandRunner);
        }
    };
    [callbacks addObject:[callbackWrapper copy]];
    [_queue addObject:path];

    [_commandRunner write:[[path stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] completion:^(size_t written, int error) {
        DLog(@"git component for bucket %d: wrote %d bytes, got error code %d", bucket, (int)written, error);
    }];

    const NSTimeInterval timeout = [iTermAdvancedSettingsModel gitTimeout];
    DLog(@"git poll worker for bucket %d: starting %f sec timer after requesting %@",
         bucket, (double)timeout, path);
    __weak __typeof(_commandRunner) weakCommandRunner = _commandRunner;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DLog(@"git poll worker for bucket %d: Timer for %@ fired. finished=%@", bucket, path, @(finished));
        if (finished) {
            DLog(@"git poll worker for bucket %d: was already finished", bucket);
            return;
        }
        finished = YES;
        DLog(@"git poll worker for bucket %d: Terminating %@", bucket, weakCommandRunner);
        [[iTermGitPollWorker commandRunnerPool] terminateCommandRunner:weakCommandRunner];
    });
}

- (void)didRead:(NSData *)data {
    DLog(@"git poll worker for bucket %d: Read %@ bytes from git poller script", _bucket, @(data.length));

    // If more than 100k gets queued up something has gone terribly wrong
    const size_t maxBytes = 100000;
    if (_readData.length + data.length > maxBytes) {
        DLog(@"git poll worker for bucket %d: wtf, have queued up more than 100k of output from the git poller script", _bucket);
        [self killScript];
        return;
    }

    [_readData appendData:data];
    [self handleBlocks];
}

- (void)handleBlocks {
    while ([self handleBlock]) {}
}

- (BOOL)handleBlock {
    char *endMarker = "\n--END--\n";
    NSData *endMarkerData = [NSData dataWithBytesNoCopy:endMarker length:strlen(endMarker) freeWhenDone:NO];
    NSRange range = [_readData rangeOfData:endMarkerData options:0 range:NSMakeRange(0, _readData.length)];
    if (range.location == NSNotFound) {
        return NO;
    }

    NSRange thisRange = NSMakeRange(0, NSMaxRange(range));
    NSData *thisData = [_readData subdataWithRange:thisRange];
    [_readData replaceBytesInRange:thisRange withBytes:"" length:0];
    NSString *string = [[NSString alloc] initWithData:thisData
                                             encoding:NSUTF8StringEncoding];
    DLog(@"git poll worker for bucket %d: Read this string from git poller script:\n%@", _bucket, string);
    NSArray<NSString *> *lines = [string componentsSeparatedByString:@"\n"];
    NSDictionary<NSString *, NSString *> *dict = [lines keyValuePairsWithBlock:^iTermTuple *(NSString *line) {
        NSRange colon = [line rangeOfString:@": "];
        if (colon.location == NSNotFound) {
            return nil;
        }
        NSString *key = [line substringToIndex:colon.location];
        NSString *value = [line substringFromIndex:NSMaxRange(colon)];
        return [iTermTuple tupleWithObject:key andObject:value];
    }];

    DLog(@"git poll worker for bucket %d: Parsed dict:\n%@", _bucket, dict);
    iTermGitState *state = [[iTermGitState alloc] init];
    state.xcode = dict[@"XCODE"];
    state.dirty = [dict[@"DIRTY"] isEqualToString:@"dirty"];
    state.pushArrow = dict[@"PUSH"];
    state.pullArrow = dict[@"PULL"];
    state.branch = dict[@"BRANCH"];
    state.adds = [dict[@"ADDS"] integerValue];
    state.deletes = [dict[@"DELETES"] integerValue];

    NSString *path = _queue.firstObject;
    if (path) {
        DLog(@"git poll worker for bucket %d: Invoking callbacks for path %@ with state %@", _bucket, path, state);
        [_queue removeObjectAtIndex:0];
        NSArray<iTermGitCallback> *callbacks = _outstanding[path];
        [_outstanding removeObjectForKey:path];
        for (iTermGitCallback block in callbacks) {
            block(state);
        }
        DLog(@"git poll worker for bucket %d: Done nvoking callbacks", _bucket);
    }
    return YES;
}

- (void)killScript {
    DLog(@"git poll worker for bucket %d: killScript called", _bucket);
    if (!_commandRunner) {
        DLog(@"Command runner is already nil, doing nothing.");
        return;
    }
    DLog(@"git poll worker for bucket %d: KILL command runner %@", _bucket, _commandRunner);
    [[iTermGitPollWorker commandRunnerPool] terminateCommandRunner:_commandRunner];
    [self reset];
}

- (void)reset {
    DLog(@"git poll worker for bucket %d: RESET - erasing read data, nilling command runner, and invoking all callbacks with nil", _bucket);
    [_readData setLength:0];
    _commandRunner = nil;
    [_queue removeAllObjects];

    // Report failure.
    NSDictionary<NSString *, NSMutableArray<iTermGitCallback> *> *outstanding = _outstanding.copy;
    [_outstanding removeAllObjects];
    [outstanding enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull path, NSArray<iTermGitCallback> * _Nonnull callbacks, BOOL * _Nonnull stop) {
        iTermGitState *cached = [self->_cache stateForPath:path maximumAge:INFINITY];
        for (iTermGitCallback callback in callbacks) {
            DLog(@"git poll worker for bucket %d: RESET - run callback with %@ for %@", self->_bucket, cached, path);
            callback(cached);
        }
    }];
}

- (void)commandRunnerDied:(iTermCommandRunner *)commandRunner {
    DLog(@"git poll worker for bucket %d: * command runner died: %@ *", _bucket, commandRunner);
    if (commandRunner != _commandRunner) {
        DLog(@"git poll worker for bucket %d: The child is not my son (mine is %@)", _bucket, _commandRunner);
        return;
    }
    if (!commandRunner) {
        DLog(@"git poll worker for bucket %d: nil command runner", _bucket);
        return;
    }
    [self reset];
}

@end

NS_ASSUME_NONNULL_END
