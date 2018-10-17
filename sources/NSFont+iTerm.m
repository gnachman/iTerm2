//
//  NSFont+iTerm.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "NSFont+iTerm.h"

@implementation NSFont (iTerm)

- (NSString *)stringValue {
    return [NSString stringWithFormat:@"%@ %g", [self fontName], [self pointSize]];
}

- (NSFont *)it_fontByAddingToPointSize:(CGFloat)delta {
    int newSize = [self pointSize] + delta;
    if (newSize < 2) {
        newSize = 2;
    }
    if (newSize > 200) {
        newSize = 200;
    }
    return [NSFont fontWithName:[self fontName] size:newSize];
}

@end
