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

- (BOOL)isEqualToString:(NSString *)string
             threshold:(double)threshold {
    static NSNumberFormatter *sFormatter;
    if (!sFormatter) {
        sFormatter = [[NSNumberFormatter alloc] init];
        sFormatter.locale = [NSLocale currentLocale];
        sFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        sFormatter.generatesDecimalNumbers = YES;
        sFormatter.allowsFloats = YES;
        // make sure it recognizes “E” or “e” in strings:
        sFormatter.exponentSymbol = @"E";
    }

    // 1) try parsing with our formatter
    NSNumber *parsed = [sFormatter numberFromString:string];
    if (!parsed) {
        return NO;
    }

    // 2) compare via NSDecimalNumber for full precision
    NSDecimalNumber *selfDec = [NSDecimalNumber decimalNumberWithDecimal:self.decimalValue];
    NSDecimalNumber *other  = (id)parsed;
    NSDecimalNumber *diff   = [selfDec decimalNumberBySubtracting:other];
    NSDecimalNumber *absDiff;
    if ([diff compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        absDiff = [diff decimalNumberByMultiplyingByPowerOf10:0]; // make positive
        absDiff = [absDiff decimalNumberByMultiplyingByPowerOf10:0]; // or just abs
        absDiff = [absDiff decimalNumberByMultiplyingByPowerOf10:0]; // simpler: -diff
        absDiff = [diff decimalNumberByMultiplyingByPowerOf10:0];
        if (diff.decimalValue._isNegative) {
            absDiff = [diff decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
        }
    } else {
        absDiff = diff;
    }

    NSDecimalNumber *threshDec = [NSDecimalNumber
        decimalNumberWithDecimal:@(threshold).decimalValue];
    return [absDiff compare:threshDec] != NSOrderedDescending;
}

- (BOOL)it_hasFractionalPart {
    // Get full-precision decimal
    NSDecimal dec = [self decimalValue];

    // Round it down (truncate) to zero decimal places
    NSDecimal intPart;
    NSDecimalRound(&intPart,
                   &dec,
                   0,            // scale: number of digits after decimal
                   NSRoundDown); // always toward zero

    // If original ≠ truncated, there was a fractional part
    NSComparisonResult cmp = NSDecimalCompare(&dec,
                                             &intPart);
    if (cmp != NSOrderedSame) {
        return YES;
    } else {
        return NO;
    }
}

@end
