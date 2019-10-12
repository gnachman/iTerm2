//
//  iTermTmuxOptionMonitor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/2/19.
//

#import "iTermTmuxOptionMonitor.h"

#import "DebugLogging.h"
#import "iTermVariables.h"
#import "iTermVariableScope+Session.h"
#import "NSStringITerm.h"
#import "NSTimer+iTerm.h"
#import "TmuxGateway.h"

@implementation iTermTmuxOptionMonitor {
    NSTimer *_timer;
    NSString *_format;
    BOOL _haveOutstandingRequest;
    NSString *_target;
    NSString *_variableName;
    NSString *_fallbackVariableName;
    void (^_block)(NSString *);
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway
                          scope:(iTermVariableScope *)scope
           fallbackVariableName:(NSString *)fallbackVariableName
                         format:(NSString *)format
                         target:(NSString *)target
                   variableName:(NSString *)variableName
                          block:(void (^)(NSString *))block {
    self = [super init];
    if (self) {
        _gateway = gateway;
        _scope = scope;
        _format = [format copy];
        _target = [target copy];
        _variableName = [variableName copy];
        _block = [block copy];
        _fallbackVariableName = [fallbackVariableName copy];
    }
    return self;
}

- (void)startTimer {
    [_timer invalidate];
    _timer = [NSTimer scheduledWeakTimerWithTimeInterval:1
                                                  target:self
                                                selector:@selector(update:)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)invalidate {
    [_timer invalidate];
    _timer = nil;
    _scope = nil;
}

- (NSString *)escapedFormat {
    return [[_format stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
            stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
}

- (void)update:(NSTimer *)timer {
    [self updateOnce];
}

- (NSString *)command {
    return [NSString stringWithFormat:@"display-message -t '%@' -p '%@'", _target, self.escapedFormat];
}

- (void)updateOnce {
    if (_haveOutstandingRequest) {
        DLog(@"Not making a request because one is outstanding");
        return;
    }
    if (_fallbackVariableName && self.gateway.minimumServerVersion.doubleValue <= 2.9) {
        [self didFetch:[self.scope valueForVariableName:_fallbackVariableName]];
        return;
    }
    _haveOutstandingRequest = YES;
    NSString *command = [self command];
    DLog(@"Request option with command %@", command);
    [self.gateway sendCommand:command
               responseTarget:self
             responseSelector:@selector(didFetch:)
               responseObject:nil
                        flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)didFetch:(NSString *)value {
    DLog(@"%@ -> %@", self.command, value);
    if (!value) {
        // Probably the pane went away and we'll be dealloced soon.
        return;
    }
    _haveOutstandingRequest = NO;
    if (_variableName) {
        [self.scope setValue:value forVariableNamed:_variableName];
    }
    if (_block) {
        _block(value);
    }
}

@end
