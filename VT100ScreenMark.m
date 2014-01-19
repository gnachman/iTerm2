//
//  VT100ScreenMark.m
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import "VT100ScreenMark.h"

@implementation VT100ScreenMark
@synthesize entry;

- (void)dealloc {
    [_command release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@ sessionID=%d>",
            self.class, self, self.entry.interval, self.sessionID];
}

@end
