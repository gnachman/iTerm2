//
//  NSNumber+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/15/18.
//

#import "NSNumber+iTerm.h"

@implementation NSNumber (iTerm)

- (id)it_jsonSafeValue {
    const double d = self.doubleValue;
    if (d == INFINITY) {
        return @(DBL_MAX);
    } else if (d == -INFINITY) {
        return @(-DBL_MAX);
    } else if (d != d) {  // NaN
        return nil;
    } else {
        return self;
    }
}

@end
