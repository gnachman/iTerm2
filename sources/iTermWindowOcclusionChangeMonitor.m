//
//  iTermWindowOcclusionChangeMonitor.m
//  iTerm2
//
//  Created by George Nachman on 7/6/16.
//
//

#import "iTermWindowOcclusionChangeMonitor.h"

#import "iTermRateLimitedUpdate.h"
#import "DebugLogging.h"

NSString *const iTermWindowOcclusionDidChange = @"iTermWindowOcclusionDidChange";

@implementation iTermWindowOcclusionChangeMonitor {
    iTermRateLimitedUpdate *_rateLimit;
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
        _rateLimit = [[iTermRateLimitedUpdate alloc] init];
        _rateLimit.minimumInterval = 1.0;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowDidMoveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowDidResizeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowDidMiniaturizeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowDidDeminiaturizeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowWillCloseNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWindowDidBecomeMainNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(invalidateCachedOcclusion:)
                                                     name:NSWorkspaceActiveSpaceDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)invalidateCachedOcclusion:(NSNotification *)notification {
    DLog(@"Invalidate occlusion cache because of notification %@", notification.name);
    [self invalidateCachedOcclusion];
}

- (void)invalidateCachedOcclusion {
    _timeOfLastOcclusionChange = [NSDate timeIntervalSinceReferenceDate];
    [_rateLimit performRateLimitedBlock:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermWindowOcclusionDidChange object:nil];
    }];
}


@end
