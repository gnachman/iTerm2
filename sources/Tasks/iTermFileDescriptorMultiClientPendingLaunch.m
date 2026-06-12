//
//  iTermFileDescriptorMultiClientPendingLaunch.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import "iTermFileDescriptorMultiClientPendingLaunch.h"

@implementation iTermFileDescriptorMultiClientPendingLaunch {
    BOOL _invalid;
    iTermMultiServerRequestLaunch _launchRequest;
    iTermThreadChecker *_checker;
}

- (instancetype)initWithRequest:(iTermMultiServerRequestLaunch)request
                     callback:(iTermMultiClientLaunchCallback *)callback
                         thread:(iTermThread *)thread {
    self = [super init];
    if (self) {
        _launchRequest = request;
        _launchCallback = callback;
        _checker = [[iTermThreadChecker alloc] initWithThread:thread];
    }
    return self;
}

- (void)invalidate {
    [_checker check];
    _invalid = YES;
    memset(&_launchRequest, 0, sizeof(_launchRequest));
}

- (void)cancelWithError:(NSError *)error {
    [_checker check];
    [_launchCallback invokeWithObject:[iTermResult withError:error]];
    [self invalidate];
}

- (iTermMultiServerRequestLaunch)launchRequest {
    [_checker check];
    assert(!_invalid);
    return _launchRequest;
}

@end
