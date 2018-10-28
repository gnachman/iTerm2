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

NS_ASSUME_NONNULL_BEGIN

typedef void (^iTermGitCallback)(iTermGitState *);

@implementation iTermGitPollWorker {
    iTermCommandRunner *_commandRunner;
    NSMutableData *_readData;
    NSInteger _generation;
    NSMutableArray<NSString *> *_queue;
    iTermGitCache *_cache;
    NSMutableDictionary<NSString *, NSMutableArray<iTermGitCallback> *> *_outstanding;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _readData = [NSMutableData data];
        _queue = [NSMutableArray array];
        _cache = [[iTermGitCache alloc] init];
        _outstanding = [NSMutableDictionary dictionary];
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

    NSMutableArray<iTermGitCallback> *callbacks = _outstanding[path];
    if (callbacks) {
        DLog(@"Attach request for %@ to existing callback", path);
        [callbacks addObject:[completion copy]];
        return;
    }
    DLog(@"enqueue request for %@", path);
    callbacks = [NSMutableArray array];
    _outstanding[path] = callbacks;

    [self createCommandRunnerIfNeeded];
    DLog(@"git component requesting poll of %@", path);
    __block BOOL finished = NO;
    void (^wrapper)(iTermGitState *) = ^(iTermGitState *state) {
        if (state) {
            [self->_cache setState:state forPath:path ttl:2];
        }
        if (!finished) {
            finished = YES;
            completion(state);
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

- (void)createCommandRunnerIfNeeded {
    if (!_commandRunner) {
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        NSString *script = [bundle pathForResource:@"iterm2_git_poll" ofType:@"sh"];
        if (!script) {
            DLog(@"failed to get path to script from bundle %@", bundle);
            return;
        }
        DLog(@"Launch new git poller script from %@", script);
        _commandRunner = [[iTermCommandRunner alloc] initWithCommand:script withArguments:@[] path:@"/"];
        __weak __typeof(self) weakSelf = self;
        _commandRunner.outputHandler = ^(NSData *data) {
            [weakSelf didRead:data];
        };
        NSInteger generation = _generation++;
        _commandRunner.completion = ^(int code) {
            [weakSelf scriptDied:generation];
        };
        [_commandRunner run];
    }
}

- (void)didRead:(NSData *)data {
    DLog(@"Read %@ bytes from git poller script", @(data.length));

    // If more than 100k gets queued up something has gone terribly wrong
    const size_t maxBytes = 100000;
    if (_readData.length + data.length > maxBytes) {
        DLog(@"wtf, have queued up more than 100k of output from the git poller script");
        [_commandRunner terminate];
        _commandRunner = nil;
        [_readData setLength:0];
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
    state.dirty = [dict[@"DIRTY"] isEqualToString:@"dirty"];
    state.pushArrow = dict[@"PUSH"];
    state.pullArrow = dict[@"PULL"];
    state.branch = dict[@"BRANCH"];

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
    DLog(@"killing wedged git poller script");
    [_commandRunner terminate];
    [self reset];
}

- (void)reset {
    [_readData setLength:0];
    _commandRunner = nil;
    [_queue removeAllObjects];
}

- (void)scriptDied:(NSInteger)generation {
    DLog(@"* script died *");
    if (generation != _generation) {
        return;
    }
    [self reset];
}

@end

NS_ASSUME_NONNULL_END
