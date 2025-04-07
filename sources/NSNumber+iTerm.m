//
//  NSNumber+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/15/18.
//

#import "NSNumber+iTerm.h"
#import "DebugLogging.h"

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

- (BOOL)it_hasZeroValue {
    return [self isEqualToNumber:@0];
}

// This mess is a hail mary attempt to not break code that worked by accident where it was cast to
// NSNumber but was actually an NSString. They have enough methods in common (boolValue, integerValue, etc.)
// that you can get pretty far with a string by treating it as a number.
+ (instancetype)coerceFrom:(id)obj {
    if (!obj) {
        return nil;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        return obj;
    }
    if ([obj isKindOfClass:[NSString class]]) {
        DLog(@"Coercing string %@ to number", obj);
        NSString *s = (NSString *)obj;

        // If (ignoring spaces and sign) the string contains any of y, n, t, or f (case insensitive),
        // treat it as a boolean. See comment in NSString.h about boolValue.
        NSCharacterSet *boolSet = [NSCharacterSet characterSetWithCharactersInString:@"yYnNtTfF"];
        if ([s rangeOfCharacterFromSet:boolSet].location != NSNotFound) {
            return @([s boolValue]);
        }

        const double d = [s doubleValue];
        if (d < LONG_LONG_MIN || d > LONG_LONG_MAX) {
            return @(d);
        }
        if (d != floor(d)) {
            return @(d);
        }
        return @((long long)d);
    }
    return nil;
}

@end
