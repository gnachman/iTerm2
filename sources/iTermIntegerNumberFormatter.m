//
//  iTermIntegerNumberFormatter.m
//  iTerm2
//
//  Created by George Nachman on 9/30/14.
//
//

#import "iTermIntegerNumberFormatter.h"

@implementation iTermIntegerNumberFormatter

- (BOOL)isPartialStringValid:(NSString *)partialString
            newEditingString:(NSString **)newString
            errorDescription:(NSString **)error {
    if([partialString length] == 0) {
        return YES;
    }

    NSScanner *scanner = [NSScanner scannerWithString:partialString];

    return [scanner scanInt:NULL] && [scanner isAtEnd];
}

@end
