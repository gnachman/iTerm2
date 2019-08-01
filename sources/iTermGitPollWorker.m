//
//  iTermGitPollWorker.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitPollWorker.h"

#import "DebugLogging.h"

#import "iTermCommandRunner.h"
#import "iTermGitCache.h"
#import "iTermTuple.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

static int gNumberOfCommandRunners;

typedef void (^iTermGitCallback)(iTermGitState * _Nullable);

@implementation iTermGitPollWorker {
    iTermCommandRunner *_commandRunner;
    NSMutableArray<iTermCommandRunner *> *_terminatingCommandRunners;
    NSMutableData *_readData;
    NSMutableArray<NSString *> *_queue;
    iTermGitCache *_cache;
    NSMutableDictionary<NSString *, NSMutableArray<iTermGitCallback> *> *_outstanding;
    int _bucket;
}

+ (instancetype)instanceForPath:(NSString *)path {
    // If one of the gets hung because of a network file system then it won't affect most of the
    // others.
    const int numberOfBuckets = 4;
    static dispatch_once_t onceToken[numberOfBuckets];
    static id instances[numberOfBuckets];
    const int bucket = [path hash] % numberOfBuckets;
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
        _terminatingCommandRunners = [NSMutableArray array];
    }
    return self;
}

- (void)invalidateCacheForPath:(NSString *)path {
    DLog(@"git poll worker for bucket %d: remove cache entry for path %@", _bucket, path);
    [_cache removeStateForPath:path];
}

- (void)requestPath:(NSString *)path completion:(iTermGitCallback)completion {
    DLog(@"git poll worker for bucket %d: got request for path %@", _bucket, path);
    iTermGitState *cached = [_cache stateForPath:path];
    if (cached) {
        DLog(@"git poll worker for bucket %d: return cached value %@ for path %@", _bucket, cached, path);
        completion(cached);
        return;
    }

    NSMutableArray<iTermGitCallback> *callbacks = _outstanding[path];
    if (callbacks) {
        DLog(@"git poll worker for bucket %d: Attach request for %@ to existing callback", _bucket, path);
        [callbacks addObject:[completion copy]];
        return;
    }
    DLog(@"git poll worker for bucket %d: enqueue request for %@", _bucket, path);
    callbacks = [NSMutableArray array];
    _outstanding[path] = callbacks;

    if (![self createCommandRunnerIfNeeded]) {
        DLog(@"git poll worker for bucket %d: Can't create command runner for %@", _bucket, path);
        [_outstanding removeObjectForKey:path];
        completion(nil);
        return;
    }
    DLog(@"git poll worker for bucket %d: Using command runner %@ for path %@", _bucket, _commandRunner, path);
    __block BOOL finished = NO;
    const int bucket = _bucket;
    void (^wrapper)(iTermGitState *) = ^(iTermGitState *state) {
        if (state) {
            [self->_cache setState:state forPath:path ttl:2];
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
    [callbacks addObject:[wrapper copy]];
    [_queue addObject:path];

    [_commandRunner write:[[path stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] completion:^(size_t written, int error) {
        DLog(@"git component for bucket %d: wrote %d bytes, got error code %d", bucket, (int)written, error);
    }];

    DLog(@"git poll worker for bucket %d: starting two second timer after requesting %@",
         bucket, path);
    const NSTimeInterval timeout = 2;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DLog(@"git poll worker for bucket %d: Two second timer for %@ fired. finished=%@", bucket, path, @(finished));
        if (!finished) {
            finished = YES;
            [self killScript];
        }
    });
}

- (BOOL)canCreateCommandRunner {
    static const NSInteger maximumNumberOfCommandRunners = 4;
    return gNumberOfCommandRunners < maximumNumberOfCommandRunners;
}

- (BOOL)createCommandRunnerIfNeeded {
    if (!_commandRunner) {
        if (![self canCreateCommandRunner]) {
            DLog(@"git poll worker for bucket %d: Can't create task runner - already have the maximum number of them", _bucket);
            return NO;
        }
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        NSString *script = [bundle pathForResource:@"iterm2_git_poll" ofType:@"sh"];
        if (!script) {
            DLog(@"git poll worker for bucket %d: failed to get path to script from bundle %@", _bucket, bundle);
            return NO;
        }
        DLog(@"git poll worker for bucket %d: Launch new git poller script from %@", _bucket, script);
        NSString *sandboxConfig = [[[NSString stringWithContentsOfFile:[bundle pathForResource:@"git" ofType:@"sb"]
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil] componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "];
        assert(sandboxConfig.length > 0);
        _commandRunner = [[iTermCommandRunner alloc] initWithCommand:@"/usr/bin/sandbox-exec" withArguments:@[ @"-p", sandboxConfig, script ] path:@"/"];
        [_commandRunner loadPathForGit];
        if (_commandRunner) {
            gNumberOfCommandRunners++;
            DLog(@"git poll worker for bucket %d: Incremented number of command runners to %@",
                 _bucket, @(gNumberOfCommandRunners));
        }
        __weak __typeof(self) weakSelf = self;
        _commandRunner.outputHandler = ^(NSData *data) {
            [weakSelf didRead:data];
        };
        __weak __typeof(_commandRunner) weakCommandRunner = _commandRunner;
        _commandRunner.completion = ^(int code) {
            [weakSelf commandRunnerDied:weakCommandRunner];
        };
        [_commandRunner run];
    }
    return YES;
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
        DLog(@"git poll worker for bucket %d: Invoking callbacks for path %@", _bucket, path);
        [_queue removeObjectAtIndex:0];
        NSArray<iTermGitCallback> *callbacks = _outstanding[path];
        [_outstanding removeObjectForKey:path];
        for (iTermGitCallback block in callbacks) {
            block(state);
        }
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
    DLog(@"git poll worker for bucket %d: killing wedged git poller script", _bucket);
    [_terminatingCommandRunners addObject:_commandRunner];
    [_commandRunner terminate];
    [self reset];
}

- (void)reset {
    [_readData setLength:0];
    _commandRunner = nil;
    [_queue removeAllObjects];

    // Report failure.
    NSArray<NSMutableArray<iTermGitCallback> *> *callbackArrays = _outstanding.allValues;
    [_outstanding removeAllObjects];
    for (NSArray<iTermGitCallback> *callbacks in callbackArrays) {
        for (iTermGitCallback callback in callbacks) {
            callback(nil);
        }
    }
}

- (void)commandRunnerDied:(iTermCommandRunner *)commandRunner {
    DLog(@"git poll worker for bucket %d: * command runner died: %@ *", _bucket, commandRunner);
    if (!commandRunner) {
        DLog(@"git poll worker for bucket %d: nil command runner", _bucket);
        return;
    }
    gNumberOfCommandRunners--;
    DLog(@"git poll worker for bucket %d: Decremented number of command runners to %@",
         _bucket, @(gNumberOfCommandRunners));
    if ([_terminatingCommandRunners containsObject:commandRunner]) {
        [_terminatingCommandRunners removeObject:commandRunner];
        return;
    }
    // This assertion is here in because calling reset when this precondition
    // is violated means you're going to nil out your current command runner even
    // though it's still running.
    assert(commandRunner == _commandRunner);
    [self reset];
}

@end

NS_ASSUME_NONNULL_END
