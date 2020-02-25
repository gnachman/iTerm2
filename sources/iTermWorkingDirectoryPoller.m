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
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _completions = [NSMutableArray array];
        _pwdPollRateLimit = [[iTermRateLimitedUpdate alloc] init];
        _pwdPollRateLimit.minimumInterval = 1;
    }
    return self;
}

- (instancetype)initWithTmuxGateway:(TmuxGateway *)gateway
                              scope:(iTermVariableScope *)scope
                         windowPane:(int)windowPane {
    self = [self init];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        _completions = [NSMutableArray array];
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
    [iTermLSOF asyncWorkingDirectoryOfProcess:pid queue:dispatch_get_main_queue() block:^(NSString *pwd) {
        DLog(@"Got: %@", pwd);
        [weakSelf setDirectory:pwd generation:generation];
    }];
}

- (void)addOneTimeCompletion:(void (^)(NSString * _Nullable))completion {
    [_completions addObject:completion];
}

- (void)setDirectory:(NSString *)directory generation:(NSInteger)generation {
    DLog(@"setDirectory:%@ generation:%@", directory, @(generation));
    [self didInferWorkingDirectory:directory valid:generation == _generation];
    [self pollIfNeeded];
}

- (void)didInferWorkingDirectory:(NSString *)pwd valid:(BOOL)valid {
    DLog(@"didInferWorkingDirectory:%@ valid:%@", pwd, @(valid));
    if (pwd) {
        _haveFoundInitialDirectory = YES;
    }
    NSArray<iTermWorkingDirectoryPollerClosure> *completions = [_completions copy];
    [_completions removeAllObjects];
    [completions enumerateObjectsUsingBlock:^(iTermWorkingDirectoryPollerClosure  _Nonnull completion, NSUInteger idx, BOOL * _Nonnull stop) {
        completion(pwd);
    }];
    [self.delegate workingDirectoryPollerDidFindWorkingDirectory:pwd
                                                     invalidated:!valid];
}

- (void)tmuxOptionMonitorDidProduceDirectory:(NSString *)directory {
    // These can't be invalidated because we don't have local lookups competing with remote.
    // Remote should always win.
    [self setDirectory:directory generation:_generation];
}

@end
