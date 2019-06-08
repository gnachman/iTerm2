//
//  iTermTmuxTitleMonitor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/2/19.
//

#import "iTermTmuxTitleMonitor.h"

#import "DebugLogging.h"
#import "iTermVariables.h"
#import "iTermVariableScope+Session.h"
#import "NSTimer+iTerm.h"
#import "TmuxGateway.h"

@implementation iTermTmuxTitleMonitor {
    NSTimer *_timer;
    NSString *_format;
    BOOL _haveOutstandingRequest;
    NSString *_target;
    NSString *_variableName;
}

- (instancetype)initWithGateway:(TmuxGateway *)gateway
                          scope:(iTermVariableScope *)scope
                         format:(NSString *)format
                         target:(NSString *)target
                   variableName:(NSString *)variableName {
    self = [super init];
    if (self) {
        _gateway = gateway;
        _scope = scope;
        _format = [format copy];
        _target = [target copy];
        _variableName = [_variableName copy];
        _timer = [NSTimer scheduledWeakTimerWithTimeInterval:1
                                                      target:self
                                                    selector:@selector(updateTitle:)
                                                    userInfo:nil
                                                     repeats:YES];
    }
    return self;
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

- (void)updateTitle:(NSTimer *)timer {
    if (_haveOutstandingRequest) {
        DLog(@"Not making a request because one is outstanding");
        return;
    }
    _haveOutstandingRequest = YES;
    // Window pane has a % prefix
    NSString *command = [NSString stringWithFormat:@"display-message -t '%@' -p '%@'", _target, self.escapedFormat];
    DLog(@"Request title with command %@", command);
    [self.gateway sendCommand:command
               responseTarget:self
             responseSelector:@selector(didFetchTitle:)
               responseObject:nil
                        flags:0];
}

- (void)didFetchTitle:(NSString *)title {
    DLog(@"Did fetch title %@", title);
    _haveOutstandingRequest = NO;
    [self.scope setValue:title forVariableNamed:_variableName];
}

@end
