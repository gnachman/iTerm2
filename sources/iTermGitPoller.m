//
//  iTermGitPoller.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitPoller.h"

#import "DebugLogging.h"
#import "iTermGitPollWorker.h"
#import "iTermGitState.h"
#import "iTermRateLimitedUpdate.h"
#import "NSTimer+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermGitPoller {
    iTermRateLimitedUpdate *_rateLimit;
    NSTimer *_timer;
    NSDate *_lastPollTime;
    void (^_update)(void);
}

- (instancetype)initWithCadence:(NSTimeInterval)cadence update:(void (^)(void))update {
    self = [super init];
    if (self) {
        _rateLimit = [[iTermRateLimitedUpdate alloc] init];
        _rateLimit.minimumInterval = 0.5;
        _cadence = cadence;
        _update = [update copy];
        [self startTimer];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

#pragma mark - Private

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) {
        return;
    }
    _enabled = enabled;
    if (!enabled) {
        _update();
    }
}

- (void)startTimer {
    [_timer invalidate];
    _timer = [NSTimer scheduledWeakTimerWithTimeInterval:_cadence
                                                  target:self
                                                selector:@selector(poll)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)bump {
    DLog(@"Bump");
    [self poll];
    // Restart the timer to avoid a double-tap
    if (_timer) {
        [self startTimer];
    }
}

- (NSTimeInterval)timeSinceLastPoll {
    return -[_lastPollTime timeIntervalSinceNow];
}

- (void)poll {
    DLog(@"poller running %@", self);
    if (!self.enabled) {
        return;
    }
    if (!self.currentDirectory.length) {
        return;
    }
    if (![self.delegate gitPollerShouldPoll:self]) {
        return;
    }
    _lastPollTime = [NSDate date];
    __weak __typeof(self) weakSelf = self;
    [[iTermGitPollWorker instanceForPath:self.currentDirectory] requestPath:self.currentDirectory completion:^(iTermGitState *state) {
        [weakSelf didPollWithUpdatedState:state];
    }];
}

- (void)didPollWithUpdatedState:(iTermGitState *)state {
    self.state = state;
}

- (void)setState:(iTermGitState *)state {
    _state = state;
    _update();
}

- (void)setCurrentDirectory:(NSString *)currentDirectory {
    if (currentDirectory == _currentDirectory ||
        [currentDirectory isEqualToString:_currentDirectory]) {
        return;
    }
    if (currentDirectory) {
        [_rateLimit performRateLimitedBlock:^{
            [[iTermGitPollWorker instanceForPath:currentDirectory] invalidateCacheForPath:currentDirectory];
        }];
    }
    _currentDirectory = [currentDirectory copy];
    [self poll];
}

@end

NS_ASSUME_NONNULL_END
