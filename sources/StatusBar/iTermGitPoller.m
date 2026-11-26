//
//  iTermGitPoller.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitPoller.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermGitPollWorker.h"
#import "iTermGitState.h"
#import "iTermRateLimitedUpdate.h"
#import "NSTimer+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

// A poll whose completion hasn't come in this long is presumed lost, so
// it can't stop polling for good. Comfortably longer than the git
// timeout, which is an advanced setting with no upper limit.
static NSTimeInterval iTermGitPollerAbandonInFlightPollAfter(void) {
    return MAX(60, [iTermAdvancedSettingsModel gitTimeout] * 2 + 15);
}

@implementation iTermGitPoller {
    iTermRateLimitedUpdate *_rateLimit;
    NSTimer *_timer;
    void (^_update)(void);
    // Identifies the latest poll. A completion for any other is ignored.
    NSUInteger _pollGeneration;
    BOOL _pollInFlight;
    // A bump came in while a poll was in flight.
    BOOL _pollAgainWhenDone;
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
    if ([self hasPollInFlight]) {
        DLog(@"%@: Poll in flight. Poll again when it finishes.", self);
        _pollAgainWhenDone = YES;
        return;
    }
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

- (id<iTermGitPollWorkerProtocol>)effectiveWorker {
    return _worker ?: [iTermGitPollWorker sharedInstance];
}

- (void)setWorker:(nullable id<iTermGitPollWorkerProtocol>)worker {
    if (worker == _worker) {
        return;
    }
    RLog(@"%@: worker changes from %@ to %@", self, _worker, worker);
    _worker = worker;
    [self forgetInFlightPoll];
    // The state described a repository the new worker cannot see (another host, or this Mac).
    _hasSuccessfullyFetched = NO;
    _lastPollTimedOut = NO;
    _state = nil;
    _update();
    [self bump];
}

- (NSTimeInterval)timeSinceLastPoll {
    return -[_lastPollTime timeIntervalSinceNow];
}

- (BOOL)hasPollInFlight {
    if (!_pollInFlight) {
        return NO;
    }
    if (self.timeSinceLastPoll > iTermGitPollerAbandonInFlightPollAfter()) {
        RLog(@"%@: Abandoning a poll that never finished", self);
        [self forgetInFlightPoll];
        return NO;
    }
    return YES;
}

// What the in-flight poll is for has changed, so its result will be
// discarded. Let the next poll start right away instead of waiting.
- (void)forgetInFlightPoll {
    _pollGeneration += 1;
    _pollInFlight = NO;
    _pollAgainWhenDone = NO;
}

- (void)poll {
    DLog(@"%@: poller running", self);
    if ([self hasPollInFlight]) {
        // Polls that overlap would join the same request, and the
        // result would belong to neither one in particular.
        DLog(@"%@: don't poll: a poll is in flight", self);
        return;
    }
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
    _pollGeneration += 1;
    const NSUInteger generation = _pollGeneration;
    _startedPollCount += 1;
    const NSUInteger pollNumber = _startedPollCount;
    _pollInFlight = YES;
    __weak __typeof(self) weakSelf = self;
    NSString *polledPath = self.currentDirectory;
    DLog(@"%@: POLL: request path %@", self, polledPath);
    id<iTermGitPollWorkerProtocol> worker = [self effectiveWorker];
    DLog(@"%@: Using worker %@", self, worker);
    [worker requestPath:polledPath
                gitBase:self.gitBase
       includeDiffStats:self.includeDiffStats
             completion:^(iTermGitState *state, BOOL timedOut) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (generation != strongSelf->_pollGeneration) {
            RLog(@"%@: Discarding the result of a poll that was superseded", strongSelf);
            return;
        }
        strongSelf->_pollInFlight = NO;
        if ([strongSelf effectiveWorker] != worker) {
            RLog(@"%@: Discarding a poll result from a worker no longer in use", strongSelf);
            return;
        }
        if (![strongSelf.currentDirectory isEqualToString:polledPath]) {
            // Directory changed while the poll was in flight; the result is for a stale path
            // and must not update our per-directory flags or state.
            RLog(@"%@: Discarding stale poll result for %@ (current is %@)",
                 strongSelf, polledPath, strongSelf.currentDirectory);
            return;
        }
        strongSelf->_deliveredPollNumber = pollNumber;
        [strongSelf didPollWithUpdatedState:state timedOut:timedOut];
        if (strongSelf->_pollAgainWhenDone) {
            strongSelf->_pollAgainWhenDone = NO;
            // The worker just cached this result, and would answer the
            // follow-up from that cache. The point of the follow-up is that
            // the tree may have changed after this poll read it.
            [[strongSelf effectiveWorker] invalidateCacheForPath:polledPath];
            [strongSelf poll];
        }
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
    _deliveryCount += 1;
    self.state = state;
}

- (void)setState:(iTermGitState * _Nullable)state {
    DLog(@"%@: Update state of git poller to %@", self, state);
    _state = state;
    _update();
}

- (void)setGitBase:(NSString * _Nullable)gitBase {
    RLog(@"%@: Set gitBase to %@", self, gitBase);
    NSString *normalizedNew = gitBase.length > 0 ? gitBase : nil;
    NSString *normalizedOld = _gitBase.length > 0 ? _gitBase : nil;
    // -isEqualToString: is declared nonnull. Exactly one nil base means the base changed.
    if (normalizedNew == normalizedOld ||
        (normalizedNew && normalizedOld && [normalizedNew isEqualToString:normalizedOld])) {
        return;
    }
    _gitBase = [gitBase copy];
    [self forgetInFlightPoll];
    // Invalidate any in-flight pending requests against the old
    // base so a stale reply doesn't land back in the cache. Cached
    // entries are keyed by base, so they simply stop being read.
    if (self.currentDirectory.length) {
        [[self effectiveWorker] invalidateCacheForPath:self.currentDirectory];
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
    // _currentDirectory is nil at first. -isEqualToString: is declared nonnull and returns NO
    // for nil.
    if (currentDirectory == _currentDirectory ||
        (_currentDirectory && [currentDirectory isEqualToString:_currentDirectory])) {
        DLog(@"%@: Not changing", self);
        return;
    }
    if (currentDirectory) {
        DLog(@"%@: Attempt to invalidate cache", self);
        [_rateLimit performRateLimitedBlock:^{
            DLog(@"Called");
            DLog(@"%@: Invalidate cache", self);
            id<iTermGitPollWorkerProtocol> worker = [self effectiveWorker];
            DLog(@"%@: Worker for %@ is %@", self, currentDirectory, worker);
            [worker invalidateCacheForPath:currentDirectory];
        }];
    }
    _currentDirectory = [currentDirectory copy];
    [self forgetInFlightPoll];
    // These flags are per-directory: a fast repo that polls cleanly shouldn't mask a subsequent
    // slow repo that only times out.
    _hasSuccessfullyFetched = NO;
    _lastPollTimedOut = NO;
    DLog(@"%@: Request poll", self);
    [self poll];
}

@end

NS_ASSUME_NONNULL_END
