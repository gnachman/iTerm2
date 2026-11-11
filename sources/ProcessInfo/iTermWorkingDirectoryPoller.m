//
//  iTermWorkingDirectoryPoller.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import "iTermWorkingDirectoryPoller.h"

#import "DebugLogging.h"
#import "iTermLSOF.h"
#import "iTermRateLimitedUpdate.h"
#import "iTermTmuxOptionMonitor.h"

typedef void (^iTermWorkingDirectoryPollerClosure)(NSString * _Nullable);

@implementation iTermWorkingDirectoryPoller {
    iTermRateLimitedUpdate *_pwdPollRateLimit;
    BOOL _okToPollForWorkingDirectoryChange;
    BOOL _haveFoundInitialDirectory;
    BOOL _wantsPoll;
    NSInteger _generation;
    NSMutableArray<iTermWorkingDirectoryPollerClosure> *_completions;
    // Parallel to _completions: the request stamp when each was added.
    NSMutableArray<NSNumber *> *_completionStamps;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _completions = [NSMutableArray array];
        _completionStamps = [NSMutableArray array];
        _pwdPollRateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"Working directory poller"
                                                         minimumInterval:1];
    }
    return self;
}

- (instancetype)initWithTmuxGateway:(TmuxGateway *)gateway
                              scope:(id<iTermVariableVendor>)scope
                         windowPane:(int)windowPane {
    self = [self init];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        _tmuxOptionMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:gateway
                                                                       scope:scope
                                                        fallbackVariableName:nil
                                                                      format:@"#{pane_current_path}"
                                                                      target:[NSString stringWithFormat:@"%%%@", @(windowPane)]
                                                                variableName:nil
                                                                       block:^(NSString * _Nonnull directory) {
                                                                           [weakSelf tmuxOptionMonitorDidProduceDirectory:directory];
                                                                       }];
    }
    return self;
}

#pragma mark - API

- (BOOL)isTmux {
    return _tmuxOptionMonitor != nil;
}

- (void)didReceiveLineFeed {
    DLog(@"didReceiveLineFeed");
    [_pwdPollRateLimit performRateLimitedSelector:@selector(maybePollForWorkingDirectory) onTarget:self withObject:nil];
    [self pollIfNeeded];
}

- (void)userDidPressKey {
    _okToPollForWorkingDirectoryChange = YES;
    [self pollIfNeeded];
}

- (void)poll {
    DLog(@"Poll");
    [self pollForWorkingDirectory];
}

- (void)invalidateOutstandingRequests {
    _generation += 1;
}

#pragma mark - Private

- (void)pollIfNeeded {
    DLog(@"pollIfNeeded. wantsPoll=%@", @(_wantsPoll));
    if (_wantsPoll) {
        _wantsPoll = NO;
        [self pollForWorkingDirectory];
    }
}

- (void)maybePollForWorkingDirectory {
    DLog(@"maybePollForWorkingDirectory called");
    if (![self.delegate workingDirectoryPollerShouldPoll]) {
        DLog(@"NO: delegate declined");
        return;
    }
    if (_haveFoundInitialDirectory && !_okToPollForWorkingDirectoryChange) {
        DLog(@"NO: Not OK to poll");
        _wantsPoll = YES;
        return;
    }
    [self pollForWorkingDirectory];
}

- (void)pollForWorkingDirectory {
    DLog(@"pollForWorkingDirectory");
    _okToPollForWorkingDirectoryChange = NO;
    if (_tmuxOptionMonitor) {
        [_tmuxOptionMonitor updateOnce];
        return;
    }
    pid_t pid = [self.delegate workingDirectoryPollerProcessID];
    if (pid == -1) {
        DLog(@"No pid!");
        return;
    }
    __weak __typeof(self) weakSelf = self;
    NSInteger generation = _generation;
    const NSInteger requestStamp = [self.delegate workingDirectoryPollerRequestStamp];
    [iTermLSOF asyncWorkingDirectoryOfForegroundShellWithRootPid:pid
                                          foregroundProcessGroup:[self.delegate workingDirectoryPollerForegroundProcessGroup]
                                                           queue:dispatch_get_main_queue()
                                                           block:^(NSString *pwd) {
        DLog(@"Got: %@", pwd);
        [weakSelf setDirectory:pwd generation:generation requestStamp:requestStamp];
    }];
}

- (void)addOneTimeCompletion:(void (^)(NSString * _Nullable))completion {
    [_completions addObject:completion];
    [_completionStamps addObject:@([self.delegate workingDirectoryPollerRequestStamp])];
}

- (void)fetchTmuxDirectoryNowWithCompletion:(void (^)(NSString * _Nullable))completion {
    if (!_tmuxOptionMonitor) {
        completion(nil);
        return;
    }
    // The monitor delivers the value through tmuxOptionMonitorDidProduceDirectory: before
    // calling this block, so the delegate has recorded it by then.
    [_tmuxOptionMonitor fetchNowWithCompletion:completion];
}

- (void)setDirectory:(NSString *)directory
          generation:(NSInteger)generation
        requestStamp:(NSInteger)requestStamp {
    DLog(@"setDirectory:%@ generation:%@ requestStamp:%@", directory, @(generation), @(requestStamp));
    [self didInferWorkingDirectory:directory valid:generation == _generation requestStamp:requestStamp];
    [self pollIfNeeded];
}

- (void)didInferWorkingDirectory:(NSString *)pwd valid:(BOOL)valid requestStamp:(NSInteger)requestStamp {
    DLog(@"didInferWorkingDirectory:%@ valid:%@ requestStamp:%@", pwd, @(valid), @(requestStamp));
    if (pwd) {
        _haveFoundInitialDirectory = YES;
    }
    // A request that began before a completion was added may describe the shell before
    // whatever prompted it, so leave that completion for a later result.
    NSMutableArray<iTermWorkingDirectoryPollerClosure> *ready = [NSMutableArray array];
    for (NSInteger i = _completions.count - 1; i >= 0; i--) {
        if (_completionStamps[i].integerValue <= requestStamp) {
            [ready insertObject:_completions[i] atIndex:0];
            [_completions removeObjectAtIndex:i];
            [_completionStamps removeObjectAtIndex:i];
        }
    }
    for (iTermWorkingDirectoryPollerClosure completion in ready) {
        completion(pwd);
    }
    [self.delegate workingDirectoryPollerDidFindWorkingDirectory:pwd
                                                     invalidated:!valid
                                                    requestStamp:requestStamp];
}

- (void)tmuxOptionMonitorDidProduceDirectory:(NSString *)directory {
    // These can't be invalidated because we don't have local lookups competing with remote.
    // Remote should always win.
    // Stamp with the current value, not the one from when updateOnce was sent. tmux evaluates
    // the path when it handles the command (or checks a subscription) and writes the result
    // into the same ordered stream as the pane's %output. A value from before the shell's cd
    // therefore precedes the prompt's OSC 7 in that stream and is handled before the push,
    // which only reaches the tracker later, by way of the mutation thread. A value handled
    // after the push was evaluated after it was emitted, so it's current.
    [self setDirectory:directory
            generation:_generation
          requestStamp:[self.delegate workingDirectoryPollerRequestStamp]];
}

@end
