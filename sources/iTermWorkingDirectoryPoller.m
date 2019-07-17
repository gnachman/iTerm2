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

@implementation iTermWorkingDirectoryPoller {
    iTermRateLimitedUpdate *_pwdPollRateLimit;
    BOOL _okToPollForWorkingDirectoryChange;
    BOOL _haveFoundInitialDirectory;
    BOOL _wantsPoll;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pwdPollRateLimit = [[iTermRateLimitedUpdate alloc] init];
        _pwdPollRateLimit.minimumInterval = 1;
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
    pid_t pid = [self.delegate workingDirectoryPollerProcessID];
    if (pid == -1) {
        DLog(@"No pid!");
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [iTermLSOF asyncWorkingDirectoryOfProcess:pid block:^(NSString *pwd) {
        DLog(@"Got: %@", pwd);
        [weakSelf didInferWorkingDirectory:pwd];
        [weakSelf pollIfNeeded];
    }];
}

- (void)didInferWorkingDirectory:(NSString *)pwd {
    if (pwd) {
        _haveFoundInitialDirectory = YES;
    }
    [self.delegate workingDirectoryPollerDidFindWorkingDirectory:pwd];
}

@end
