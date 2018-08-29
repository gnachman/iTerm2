//
//  iTermTmuxStatusBarMonitor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/18.
//

#import "iTermTmuxStatusBarMonitor.h"

#import "iTermVariables.h"
#import "NSTimer+iTerm.h"
#import "TmuxGateway.h"

@implementation iTermTmuxStatusBarMonitor {
    NSTimer *_timer;
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway scope:(iTermVariableScope *)scope {
    self = [super init];
    if (self) {
        _gateway = gateway;
        _scope = scope;
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
    [_gateway sendCommand:@"display-message -p \"#{status-left}\"" responseTarget:self responseSelector:@selector(handleStatusLeftResponse:)];
    [_gateway sendCommand:@"display-message -p \"#{status-right}\"" responseTarget:self responseSelector:@selector(handleStatusRightResponse:)];
}

- (NSString *)escapedString:(NSString *)string {
    return [[string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                    stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

- (void)handleStatusIntervalResponse:(NSString *)response {
    if (!response) {
        return;
    }
    const NSTimeInterval interval = MAX(1, [response integerValue]);
    _timer = [NSTimer scheduledWeakTimerWithTimeInterval:interval target:self selector:@selector(timerDidFire:) userInfo:nil repeats:YES];
}

- (void)handleStatusLeftResponse:(NSString *)response {
    if (!response) {
        return;
    }
    NSString *command = [NSString stringWithFormat:@"display-message -p \"%@\"", [self escapedString:response]];
    [_gateway sendCommand:command responseTarget:self responseSelector:@selector(handleStatusLeftValueExpansionResponse:)];
}

- (void)handleStatusRightResponse:(NSString *)response {
    if (!response) {
        return;
    }
    NSString *command = [NSString stringWithFormat:@"display-message -p \"%@\"", [self escapedString:response]];
    [_gateway sendCommand:command responseTarget:self responseSelector:@selector(handleStatusRightValueExpansionResponse:)];
}

- (void)handleStatusLeftValueExpansionResponse:(NSString *)string {
    [self.scope setValue:string ?: @"" forVariableNamed:iTermVariableKeySessionTmuxStatusLeft];
}

- (void)handleStatusRightValueExpansionResponse:(NSString *)string {
    [self.scope setValue:string ?: @"" forVariableNamed:iTermVariableKeySessionTmuxStatusRight];
}

@end
