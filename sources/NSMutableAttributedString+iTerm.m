//
//  NSMutableAttributedString+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import <Cocoa/Cocoa.h>
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

- (void)trimTrailingWhitespace {
    NSCharacterSet *nonWhitespaceSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    NSRange rangeOfLastWantedCharacter = [self.string rangeOfCharacterFromSet:nonWhitespaceSet
                                                                      options:NSBackwardsSearch];
    if (rangeOfLastWantedCharacter.location == NSNotFound) {
        [self deleteCharactersInRange:NSMakeRange(0, self.length)];
    } else if (NSMaxRange(rangeOfLastWantedCharacter) < self.length) {
        [self deleteCharactersInRange:NSMakeRange(NSMaxRange(rangeOfLastWantedCharacter),
                                                  self.length - NSMaxRange(rangeOfLastWantedCharacter))];
    }
}

@end

@implementation NSAttributedString (iTerm)

- (CGFloat)heightForWidth:(CGFloat)maxWidth {
    if (![self length]) {
        return 0;
    }

    NSSize size = NSMakeSize(maxWidth, FLT_MAX);
    NSTextContainer *textContainer =
        [[[NSTextContainer alloc] initWithContainerSize:size] autorelease];
    NSTextStorage *textStorage =
        [[[NSTextStorage alloc] initWithAttributedString:self] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];

    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];
    [layoutManager setHyphenationFactor:0.0];
    
    // Force layout.
    [layoutManager glyphRangeForTextContainer:textContainer];
    
    // Don't count space added for insertion point.
    CGFloat height =
        [layoutManager usedRectForTextContainer:textContainer].size.height;
    const CGFloat extraLineFragmentHeight =
        [layoutManager extraLineFragmentRect].size.height;
    height -= MAX(0, extraLineFragmentHeight);

    return height;
}

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
