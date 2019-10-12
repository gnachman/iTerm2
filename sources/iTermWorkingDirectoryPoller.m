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

@implementation iTermWorkingDirectoryPoller {
    iTermRateLimitedUpdate *_pwdPollRateLimit;
    BOOL _okToPollForWorkingDirectoryChange;
    BOOL _haveFoundInitialDirectory;
    BOOL _wantsPoll;
    NSInteger _generation;
}

- (instancetype)init {
    self = [super init];
    if (self) {
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
    [self pollForWorkingDirectory];
}

- (void)invalidateOutstandingRequests {
    _generation += 1;
}

#pragma mark - Private

- (void)pollIfNeeded {
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
    DLog(@"polling");
    _okToPollForWorkingDirectoryChange = NO;
    DLog(@"polling");
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
    [iTermLSOF asyncWorkingDirectoryOfProcess:pid block:^(NSString *pwd) {
        DLog(@"Got: %@", pwd);
        [weakSelf setDirectory:pwd generation:generation];
    }];
}

- (void)setDirectory:(NSString *)directory generation:(NSInteger)generation {
    [self didInferWorkingDirectory:directory valid:generation == _generation];
    [self pollIfNeeded];
}

- (void)didInferWorkingDirectory:(NSString *)pwd valid:(BOOL)valid {
    if (pwd) {
        _haveFoundInitialDirectory = YES;
    }
    [self.delegate workingDirectoryPollerDidFindWorkingDirectory:pwd
                                                     invalidated:!valid];
}

- (void)tmuxOptionMonitorDidProduceDirectory:(NSString *)directory {
    // These can't be invalidated because we don't have local lookups competing with remote.
    // Remote should always win.
    [self setDirectory:directory generation:_generation];
}

@end
