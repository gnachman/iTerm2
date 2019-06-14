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
    [_cache removeStateForPath:path];
}

- (void)requestPath:(NSString *)path completion:(iTermGitCallback)completion {
    iTermGitState *cached = [_cache stateForPath:path];
    if (cached) {
        completion(cached);
        return;
    }

    DLog(@"git poll worker %d got request for path %@", _bucket, path);

    NSMutableArray<iTermGitCallback> *callbacks = _outstanding[path];
    if (callbacks) {
        DLog(@"Attach request for %@ to existing callback", path);
        [callbacks addObject:[completion copy]];
        return;
    }
    DLog(@"enqueue request for %@", path);
    callbacks = [NSMutableArray array];
    _outstanding[path] = callbacks;

    if (![self createCommandRunnerIfNeeded]) {
        DLog(@"Can't create command runner for %@", path);
        [_outstanding removeObjectForKey:path];
        completion(nil);
        return;
    }
    DLog(@"Using command runner %@ for path %@", _commandRunner, path);
    __block BOOL finished = NO;
    void (^wrapper)(iTermGitState *) = ^(iTermGitState *state) {
        if (state) {
            [self->_cache setState:state forPath:path ttl:2];
        }
        if (!finished) {
            DLog(@"Command runner %@ finished", self->_commandRunner);
            finished = YES;
            completion(state);
        } else {
            DLog(@"[already killed] - Command runner %@ finished", self->_commandRunner);
        }
    };
    [callbacks addObject:[wrapper copy]];
    [_queue addObject:path];

    [_commandRunner write:[[path stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] completion:^(size_t written, int error) {
        DLog(@"git component wrote %d bytes, got error code %d", (int)written, error);
    }];

    const NSTimeInterval timeout = 2;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
            DLog(@"Can't create task runner");
            return NO;
        }
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        NSString *script = [bundle pathForResource:@"iterm2_git_poll" ofType:@"sh"];
        if (!script) {
            DLog(@"failed to get path to script from bundle %@", bundle);
            return NO;
        }
        DLog(@"Launch new git poller script from %@", script);
        NSString *sandboxConfig = [[[NSString stringWithContentsOfFile:[bundle pathForResource:@"git" ofType:@"sb"]
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil] componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "];
        assert(sandboxConfig.length > 0);
        _commandRunner = [[iTermCommandRunner alloc] initWithCommand:@"/usr/bin/sandbox-exec" withArguments:@[ @"-p", sandboxConfig, script ] path:@"/"];
        if (_commandRunner) {
            gNumberOfCommandRunners++;
            DLog(@"Incremented number of command runners to %@", @(gNumberOfCommandRunners));
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
    DLog(@"Read %@ bytes from git poller script", @(data.length));

    // If more than 100k gets queued up something has gone terribly wrong
    const size_t maxBytes = 100000;
    if (_readData.length + data.length > maxBytes) {
        DLog(@"wtf, have queued up more than 100k of output from the git poller script");
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
    DLog(@"Read this string from git poller script:\n%@", string);
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

    DLog(@"Parsed dict:\n%@", dict);
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
        DLog(@"Invoking callbacks for path %@", path);
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
    if (!_commandRunner) {
        DLog(@"Command runner is already nil, doing nothing.");
        return;
    }
    DLog(@"KILL command runner %@", _commandRunner);
    DLog(@"killing wedged git poller script");
    [_terminatingCommandRunners addObject:_commandRunner];
    [_commandRunner terminate];
    [self reset];
}

- (void)reset {
    [_readData setLength:0];
    _commandRunner = nil;
    [_queue removeAllObjects];
    [_outstanding removeAllObjects];
}

- (void)commandRunnerDied:(iTermCommandRunner *)commandRunner {
    DLog(@"* command runner died: %@ *", commandRunner);
    if (!commandRunner) {
        DLog(@"nil command runner");
        return;
    }
    gNumberOfCommandRunners--;
    DLog(@"Decremented number of command runners to %@", @(gNumberOfCommandRunners));
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
