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

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@>",
            self.class, self, self.entry.interval];
}

@end
