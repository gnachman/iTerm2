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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p dir=%@ last=%@>",
            self.class, self, _currentDirectory, _lastPollTime];
}

#pragma mark - Private

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) {
        return;
    }
    _enabled = enabled;
    if (!enabled) {
        DLog(@"%@: Enabled set to true. Calling update.", self);
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
    DLog(@"%@: Bump", self);
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
    DLog(@"%@: poller running", self);
    if (!self.enabled) {
        DLog(@"%@: don't poll: not enabled", self);
        return;
    }
    if (!self.currentDirectory.length) {
        DLog(@"%@: don't poll: current directory unknown", self);
        return;
    }
    if (![self.delegate gitPollerShouldPoll:self]) {
        DLog(@"%@: don't poll: delegate %@ declined", self, self.delegate);
        return;
    }
    _lastPollTime = [NSDate date];
    __weak __typeof(self) weakSelf = self;
    DLog(@"%@: POLL: request path %@", self, self.currentDirectory);
    iTermGitPollWorker *worker = [iTermGitPollWorker instanceForPath:self.currentDirectory];
    DLog(@"%@: Using worker %@", self, worker);
    [worker requestPath:self.currentDirectory completion:^(iTermGitState *state) {
        [weakSelf didPollWithUpdatedState:state];
    }];
}

- (void)didPollWithUpdatedState:(iTermGitState *)state {
    self.state = state;
}

- (void)setState:(iTermGitState *)state {
    DLog(@"%@: Update state of git poller to %@", self, state);
    _state = state;
    _update();
}

- (void)setCurrentDirectory:(NSString *)currentDirectory {
    DLog(@"%@: Set current directory to %@", self, currentDirectory);
    if (currentDirectory == _currentDirectory ||
        [currentDirectory isEqualToString:_currentDirectory]) {
        DLog(@"%@: Not changing", self);
        return;
    }
    if (currentDirectory) {
        DLog(@"%@: Attempt to invalidate cache", self);
        [_rateLimit performRateLimitedBlock:^{
            DLog(@"%@: Invalidate cache", self);
            iTermGitPollWorker *worker = [iTermGitPollWorker instanceForPath:currentDirectory];
            DLog(@"%@: Worker for %@ is %@", self, currentDirectory, worker);
            [worker invalidateCacheForPath:currentDirectory];
        }];
    }
    _currentDirectory = [currentDirectory copy];
    DLog(@"%@: Request poll", self);
    [self poll];
}

@end

NS_ASSUME_NONNULL_END
