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
    void (^_update)(void);
}

- (instancetype)initWithCadence:(NSTimeInterval)cadence update:(void (^)(void))update {
    self = [super init];
    if (self) {
        _rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"Git poller"
                                                  minimumInterval:0.5];
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
        RLog(@"%@: Enabled set to false. Calling update to clear display.", self);
        _update();
    }
}

- (void)startTimer {
    [_timer invalidate];
    _timer = [NSTimer it_scheduledWeakTimerWithTimeInterval:_cadence
                                                     target:self
                                                   selector:@selector(poll)
                                                   userInfo:nil
                                                    repeats:YES];
    _timer.tolerance = _cadence * 0.1;
}

- (void)bump {
    DLog(@"%@: Bump", self);
    [self poll];
    // Restart the timer to avoid a double-tap
    if (_timer) {
        [self startTimer];
    }
}

- (void)clearTimeoutFlagAndRetry {
    RLog(@"%@: Clearing timeout flag and retrying", self);
    _lastPollTimedOut = NO;
    // Refresh the UI so any "timed out" display goes away now, rather than waiting for the
    // retry to complete.
    _update();
    [self bump];
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
    if (![self.delegate gitPollerShouldPoll:self after:_lastPollTime]) {
        DLog(@"%@: don't poll: delegate %@ declined", self, self.delegate);
        return;
    }
    _lastPollTime = [NSDate date];
    __weak __typeof(self) weakSelf = self;
    NSString *polledPath = self.currentDirectory;
    DLog(@"%@: POLL: request path %@", self, polledPath);
    iTermGitPollWorker *worker = [iTermGitPollWorker sharedInstance];
    DLog(@"%@: Using worker %@", self, worker);
    [worker requestPath:polledPath
                gitBase:self.gitBase
       includeDiffStats:self.includeDiffStats
             completion:^(iTermGitState *state, BOOL timedOut) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (![strongSelf.currentDirectory isEqualToString:polledPath]) {
            // Directory changed while the poll was in flight; the result is for a stale path
            // and must not update our per-directory flags or state.
            RLog(@"%@: Discarding stale poll result for %@ (current is %@)",
                 strongSelf, polledPath, strongSelf.currentDirectory);
            return;
        }
        [strongSelf didPollWithUpdatedState:state timedOut:timedOut];
    }];
}

- (void)didPollWithUpdatedState:(iTermGitState *)state timedOut:(BOOL)timedOut {
    DLog(@"%@ timedOut=%@ (%@)", state, @(timedOut), self.delegate);
    if (!timedOut) {
        // A non-timeout reply is "successful" even if state is nil (e.g., the cwd isn't a git repo).
        // That's a conclusive answer from the service, not a failure to get one.
        _hasSuccessfullyFetched = YES;
    }
    _lastPollTimedOut = timedOut;
    self.state = state;
}

- (void)setState:(iTermGitState *)state {
    DLog(@"%@: Update state of git poller to %@", self, state);
    _state = state;
    _update();
}

- (void)setGitBase:(NSString * _Nullable)gitBase {
    RLog(@"%@: Set gitBase to %@", self, gitBase);
    NSString *normalizedNew = gitBase.length > 0 ? gitBase : nil;
    NSString *normalizedOld = _gitBase.length > 0 ? _gitBase : nil;
    if (normalizedNew == normalizedOld ||
        [normalizedNew isEqualToString:normalizedOld]) {
        return;
    }
    _gitBase = [gitBase copy];
    // Invalidate any in-flight pending requests against the old
    // base so a stale reply doesn't land back in the cache. Cached
    // entries are keyed by base, so they simply stop being read.
    if (self.currentDirectory.length) {
        [[iTermGitPollWorker sharedInstance]
            invalidateCacheForPath:self.currentDirectory];
    }
    // Clear any "we have stale info" flags so the picker doesn't
    // briefly render with the old-base file list while the new
    // base is being fetched.
    _hasSuccessfullyFetched = NO;
    _lastPollTimedOut = NO;
    [self bump];
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
            DLog(@"Called");
            DLog(@"%@: Invalidate cache", self);
            iTermGitPollWorker *worker = [iTermGitPollWorker sharedInstance];
            DLog(@"%@: Worker for %@ is %@", self, currentDirectory, worker);
            [worker invalidateCacheForPath:currentDirectory];
        }];
    }
    _currentDirectory = [currentDirectory copy];
    // These flags are per-directory: a fast repo that polls cleanly shouldn't mask a subsequent
    // slow repo that only times out.
    _hasSuccessfullyFetched = NO;
    _lastPollTimedOut = NO;
    DLog(@"%@: Request poll", self);
    [self poll];
}

@end

NS_ASSUME_NONNULL_END
