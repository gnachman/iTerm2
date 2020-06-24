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
#import "iTermTmuxOptionMonitor.h"
#import "RegexKitLite.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"

@implementation iTermTmuxStatusBarMonitor {
    BOOL _accelerated;
    NSTimeInterval _acceleratedInterval;
    iTermTmuxOptionMonitor *_leftMonitor;
    iTermTmuxOptionMonitor *_rightMonitor;
    NSTimeInterval _interval;
    iTermVariableReference *_paneReference;
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway scope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _gateway = gateway;
        _scope = scope;
        _interval = 1;
        _acceleratedInterval = 0.01;
        [_gateway sendCommand:@"display-message -p \"#{status-interval}\""
               responseTarget:self
             responseSelector:@selector(handleStatusIntervalResponse:)];
        NSString *path = [NSString stringWithFormat:@"%@.%@",
                          iTermVariableKeySessionTab, iTermVariableKeyTabTmuxWindow];
        _paneReference = [[iTermVariableReference alloc] initWithPath:path
                                                               vendor:_scope];
        __weak __typeof(self) weakSelf = self;
        _paneReference.onChangeBlock = ^{
            [weakSelf windowPaneDidChange];
        };
    }
    return self;
}

- (void)setActive:(BOOL)active {
    if (active == _active) {
        return;
    }
    _active = active;
    if (active) {
        __weak __typeof(self) weakSelf = self;
        _leftMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:_gateway
                                                                 scope:_scope
                                                  fallbackVariableName:nil
                                                                format:@"#{T:status-left}"
                                                                target:[NSString stringWithFormat:@"@%@", _scope.tab.tmuxWindow]
                                                          variableName:nil
                                                                 block:^(NSString * _Nonnull left) {
            [weakSelf handleStatusLeftValueExpansionResponse:left];
        }];
        _rightMonitor = [[iTermTmuxOptionMonitor alloc] initWithGateway:_gateway
                                                                  scope:_scope
                                                   fallbackVariableName:nil
                                                                 format:@"#{T:status-right}"
                                                                 target:[NSString stringWithFormat:@"@%@", _scope.tab.tmuxWindow]
                                                           variableName:nil
                                                                  block:^(NSString * _Nonnull right) {
            [weakSelf handleStatusRightValueExpansionResponse:right];
        }];
        _leftMonitor.interval = _interval;
        _rightMonitor.interval = _interval;
    } else {
        [_leftMonitor invalidate];
        _leftMonitor = nil;
        [_rightMonitor invalidate];
        _rightMonitor = nil;
    }
}

- (void)windowPaneDidChange {
    if (_active) {
        [self setActive:NO];
        [self setActive:YES];
    }
}

- (void)handleStatusIntervalResponse:(NSString *)response {
    if (!response) {
        return;
    }
    _interval = MAX(1, [response integerValue]);

    _leftMonitor.interval = _interval;
    [_leftMonitor startTimer];

    _rightMonitor.interval = _interval;
    [_rightMonitor startTimer];
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
        if (_leftMonitor.interval > _acceleratedInterval) {
            _accelerated = YES;
            DLog(@"%@: Schedule accelerated upate with interval %@", self, @(_acceleratedInterval));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_acceleratedInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self->_accelerated) {
                    DLog(@"%@: Sending accelerated requestUpdates", self);
                    [self->_leftMonitor updateOnce];
                    [self->_rightMonitor updateOnce];
                }
            });
            // Back off in case it gets stuck as not ready.
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
