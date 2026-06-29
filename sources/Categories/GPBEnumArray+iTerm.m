//
//  GPBEnumArray+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/19.
//

#import "GPBEnumArray+iTerm.h"

@implementation GPBEnumArray (iTerm)

- (BOOL)it_contains:(int32_t)value {
    const NSInteger count = [self count];
    for (NSInteger i = 0; i < count; i++) {
        if ([self valueAtIndex:i] == value) {
            return YES;
        }
    }
    return NO;
}

@end
