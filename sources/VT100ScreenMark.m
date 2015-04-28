//
//  VT100ScreenMark.m
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import "VT100ScreenMark.h"

@implementation iTermMark {
    NSMutableArray *_capturedOutput;
}

@synthesize entry;
@synthesize code = _code;
@synthesize command = _command;
@synthesize sessionID = _sessionID;
@synthesize startDate = _startDate;
@synthesize endDate = _endDate;
@synthesize capturedOutput = _capturedOutput;
@synthesize delegate;

- (void)dealloc {
    [_command release];
    [_startDate release];
    [_endDate release];
    [_capturedOutput release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@ sessionID=%d>",
            self.class, self, self.entry.interval, self.sessionID];
}

- (void)setCommand:(NSString *)command {
    if (!_command) {
        [self.delegate markDidBecomeCommandMark:self];
    }
    [_command autorelease];
    _command = [command copy];
    self.startDate = [NSDate date];
}

- (void)addCapturedOutput:(CapturedOutput *)capturedOutput {
    if (!_capturedOutput) {
        _capturedOutput = [[NSMutableArray alloc] init];
    }
    [_capturedOutput addObject:capturedOutput];
}

- (BOOL)isVisible {
    return YES;
}

@end

@implementation VT100ScreenMark

- (void)dealloc {
    [_foldedText release];
    [super dealloc];
}

@end

@implementation iTermCapturedOutputMark

- (BOOL)isVisible {
    return NO;
}

@end
