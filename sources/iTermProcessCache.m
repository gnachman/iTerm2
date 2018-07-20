//
//  iTermProcessCache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import "iTermLSOF.h"
#import "iTermProcessCache.h"
#import "iTermRateLimitedUpdate.h"
#import "NSArray+iTerm.h"
#import <stdatomic.h>

@interface iTermProcessCache()
@property (atomic) BOOL needsUpdateFlag;
@end

@implementation iTermProcessCache {
    dispatch_queue_t _queue;
    iTermProcessCollection *_collection; // _queue
    _Atomic bool _needsUpdate;
    iTermRateLimitedUpdate *_rateLimit;  // keeps updateIfNeeded from eating all the CPU
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
        _queue = dispatch_queue_create("com.iterm2.process-cache", DISPATCH_QUEUE_SERIAL);
        _rateLimit = [[iTermRateLimitedUpdate alloc] init];
        _rateLimit.minimumInterval = 0.1;
        [self setNeedsUpdate:YES];
    }
    return self;
}

#pragma mark - APIs

- (void)setNeedsUpdate:(BOOL)needsUpdate {
    self.needsUpdateFlag = needsUpdate;
    if (needsUpdate) {
        [_rateLimit performRateLimitedSelector:@selector(updateIfNeeded) onTarget:self withObject:nil];
    }
}

- (iTermProcessInfo *)processInfoForPid:(pid_t)pid {
    __block iTermProcessInfo *info = nil;
    dispatch_sync(_queue, ^{
        info = [self->_collection infoForProcessID:pid];
    });
    return info;
}

#pragma mark - Private

- (void)updateIfNeeded {
    if (!self.needsUpdateFlag) {
        return;
    }

    NSArray<NSNumber *> *allPids = [iTermLSOF allPids];

    // pid -> ppid
    NSMutableDictionary<NSNumber *, NSNumber *> *parentmap = [NSMutableDictionary dictionary];
    iTermProcessCollection *collection = [[iTermProcessCollection alloc] init];
    for (NSNumber *pidNumber in allPids) {
        pid_t pid = pidNumber.intValue;

        pid_t ppid = [iTermLSOF ppidForPid:pid];
        if (!ppid) {
            continue;
        }

        parentmap[@(pid)] = @(ppid);
        [collection addProcessWithProcessID:pid parentProcessID:ppid];
    }

    [collection commit];
    _collection = collection;
    self.needsUpdateFlag = NO;
}

@end
