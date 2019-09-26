//
//  iTermTmuxStatusBarMonitor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/18.
//

#import "iTermTmuxStatusBarMonitor.h"

#import "DebugLogging.h"
#import "iTermVariableScope.h"
#import "NSStringITerm.h"
#import "NSTimer+iTerm.h"
#import "TmuxGateway.h"
#import "RegexKitLite.h"

@implementation iTermTmuxStatusBarMonitor {
    BOOL _accelerated;
    NSTimeInterval _acceleratedInterval;
    NSTimer *_timer;
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway scope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _gateway = gateway;
        _scope = scope;
        _acceleratedInterval = 0.01;
    }
    return self;
}

- (void)setActive:(BOOL)active {
    if (active == _active) {
        return;
    }
    _active = active;
    if (active) {
        [_gateway sendCommand:@"display-message -p \"#{status-interval}\"" responseTarget:self responseSelector:@selector(handleStatusIntervalResponse:)];
        [self requestUpdates];
    } else {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)timerDidFire:(NSTimer *)timer {
    [self requestUpdates];
}

- (void)requestUpdates {
    _accelerated = NO;
    [_gateway sendCommand:@"display-message -p \"#{T:status-left}\"" responseTarget:self responseSelector:@selector(handleStatusLeftValueExpansionResponse:)];
    [_gateway sendCommand:@"display-message -p \"#{T:status-right}\"" responseTarget:self responseSelector:@selector(handleStatusRightValueExpansionResponse:)];
}

- (void)handleStatusIntervalResponse:(NSString *)response {
    if (!response) {
        return;
    }
    const NSTimeInterval interval = MAX(1, [response integerValue]);
    _timer = [NSTimer scheduledWeakTimerWithTimeInterval:interval target:self selector:@selector(timerDidFire:) userInfo:nil repeats:YES];
}

- (void)handleStatusLeftValueExpansionResponse:(NSString *)string {
    DLog(@"Left status bar is: %@", string);
    [self.scope setValue:[self sanitizedString:string] ?: @"" forVariableNamed:iTermVariableKeySessionTmuxStatusLeft];
    [self accelerateUpdateIfStringContainsNotReady:string];
}

- (void)handleStatusRightValueExpansionResponse:(NSString *)string {
    DLog(@"Right status bar is: %@", string);
    [self.scope setValue:[self sanitizedString:string] ?: @"" forVariableNamed:iTermVariableKeySessionTmuxStatusRight];
    [self accelerateUpdateIfStringContainsNotReady:string];
}

- (void)accelerateUpdateIfStringContainsNotReady:(NSString *)string {
    if (_accelerated) {
        return;
    }
    if ([string containsString:@"' not ready>"]) {
        if (_timer.timeInterval > _acceleratedInterval) {
            _accelerated = YES;
            DLog(@"%@: Schedule accelerated upate with interval %@", self, @(_acceleratedInterval));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_acceleratedInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self->_accelerated) {
                    DLog(@"%@: Sending accelerated requestUpdates", self);
                    [self requestUpdates];
                }
            });
            // Back off in case it gets stuck as not reayd.
            _acceleratedInterval *= 2;
        }
    }
}
- (NSString *)sanitizedString:(NSString *)string {
    NSArray<NSString *> *regexes = @[ @"<'.*?' not ready>",
                                      @"#\\[.*?\\]" ];
    NSString *result = string;
    for (NSString *regex in regexes) {
        result = [result stringByReplacingOccurrencesOfRegex:regex withString:@""];
    }
    return result;
}

@end
