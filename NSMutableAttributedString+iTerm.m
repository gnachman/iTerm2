//
//  NSMutableAttributedString+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import "NSMutableAttributedString+iTerm.h"

@implementation NSMutableAttributedString (iTerm)

- (void)iterm_appendString:(NSString *)string {
    NSDictionary *attributes;
    if (self.length > 0) {
        attributes = [self attributesAtIndex:self.length - 1 effectiveRange:NULL];
    } else {
        attributes = [NSDictionary dictionary];
        NSLog(@"WARNING: iterm_appendString: to empty object %@ will have no attributes", self);
    }
    [self iterm_appendString:string withAttributes:attributes];
}

- (void)iterm_appendString:(NSString *)string withAttributes:(NSDictionary *)attributes {
    [self appendAttributedString:[[[NSAttributedString alloc] initWithString:string
                                                                  attributes:attributes] autorelease]];
}

@end

@implementation NSAttributedString (iTerm)

- (NSArray *)attributedComponentsSeparatedByString:(NSString *)separator {
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    NSString *string = self.string;
    NSRange range;
    NSRange nextRange = NSMakeRange(0, string.length);
    do {
        range = [string rangeOfString:separator
                              options:0
                                range:nextRange];
        if (range.location != NSNotFound) {
            [indices addIndex:range.location];
            nextRange.location = range.location + range.length;
            nextRange.length = string.length - nextRange.location;
        }
    } while (range.location != NSNotFound);

    NSMutableArray *result = [NSMutableArray array];
    __block NSUInteger startAt = 0;
    [indices enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [result addObject:[self attributedSubstringFromRange:NSMakeRange(startAt, idx - startAt)]];
        startAt = idx + separator.length;
    }];
    [result addObject:[self attributedSubstringFromRange:NSMakeRange(startAt, string.length - startAt)]];

    return result;
}

@end
