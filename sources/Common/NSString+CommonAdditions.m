//
//  NSString+CommonAdditions.m
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import "NSString+CommonAdditions.h"

@implementation NSString (CommonAdditions)

- (NSString *)stringByRemovingEnclosingBrackets {
    if (self.length < 2) {
        return self;
    }
    NSString *trimmed = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *pairs = @[ @[ @"(", @")" ],
                        @[ @"<", @">" ],
                        @[ @"[", @"]" ],
                        @[ @"{", @"}", ],
                        @[ @"\'", @"\'" ],
                        @[ @"\"", @"\"" ] ];
    for (NSArray *pair in pairs) {
        if ([trimmed hasPrefix:pair[0]] && [trimmed hasSuffix:pair[1]]) {
            return [[self substringWithRange:NSMakeRange(1, self.length - 2)] stringByRemovingEnclosingBrackets];
        }
    }
    return self;
}

- (NSString *)stringByDroppingLastCharacters:(NSInteger)count {
    if (count >= self.length) {
        return @"";
    }
    if (count <= 0) {
        return self;
    }
    return [self substringWithRange:NSMakeRange(0, self.length - count)];
}

@end
