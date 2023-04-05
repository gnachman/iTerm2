//
//  NSMutableAttributedString+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import <Cocoa/Cocoa.h>

#include "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "NSMutableAttributedString+iTerm.h"

NSAttributedStringKey iTermReplacementBaseCharacterAttributeName = @"iTermReplacementBaseCharacterAttributeName";

@implementation NSMutableAttributedString (iTerm)

+ (CGFloat)kernForString:(NSString *)string
             toHaveWidth:(CGFloat)desiredWidth
                withFont:(NSFont *)font {
    const CGFloat actualWidth = [string sizeWithAttributes:@{NSFontAttributeName: font}].width;
    if (actualWidth <= 0 || desiredWidth <= 0) {
        return 0;
    }
    return desiredWidth - actualWidth;
}

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
    NSNumber *base = attributes[iTermReplacementBaseCharacterAttributeName];
    if (base) {
        string = [string stringByReplacingBaseCharacterWith:base.unsignedIntegerValue];
    }
    [self appendAttributedString:[[NSAttributedString alloc] initWithString:string
                                                                 attributes:attributes]];
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

- (void)replaceAttributesInRange:(NSRange)range withAttributes:(NSDictionary *)newAttributes {
    for (NSString *key in newAttributes) {
        [self removeAttribute:key range:range];
        [self addAttribute:key value:newAttributes[key] range:range];
    }
}

- (void)appendCharacter:(unichar)c withAttributes:(NSDictionary *)attributes {
    [self iterm_appendString:[NSString stringWithLongCharacter:c] withAttributes:attributes];
}

@end

@implementation NSAttributedString (iTerm)

+ (instancetype)attributedStringWithString:(NSString *)string attributes:(NSDictionary *)attributes {
    return [[NSAttributedString alloc] initWithString:string attributes:attributes];
}

+ (instancetype)attributedStringWithLinkToURL:(NSString *)urlString string:(NSString *)string {
    NSDictionary *linkAttributes = @{ NSLinkAttributeName: [NSURL URLWithString:urlString] };
    return [[NSAttributedString alloc] initWithString:string
                                           attributes:linkAttributes];
}

+ (instancetype)attributedStringWithAttributedStrings:(NSArray<NSAttributedString *> *)strings {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    for (NSAttributedString *attributedString in strings) {
        [result appendAttributedString:attributedString];
    }
    return result;
}

- (CGFloat)heightForWidth:(CGFloat)maxWidth {
    if (![self length]) {
        return 0;
    }

    NSSize size = NSMakeSize(maxWidth, FLT_MAX);
    NSTextContainer *textContainer =
        [[NSTextContainer alloc] initWithContainerSize:size];
    NSTextStorage *textStorage =
        [[NSTextStorage alloc] initWithAttributedString:self];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];

    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];
    layoutManager.usesDefaultHyphenation = NO;

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

- (NSAttributedString *)attributedStringByRemovingColor {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [self enumerateAttributesInRange:NSMakeRange(0, self.length)
                             options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey, id> * _Nonnull attrs,
                                       NSRange range,
                                       BOOL * _Nonnull stop) {
        if (attrs[NSAttachmentAttributeName]) {
            NSTextAttachment *attachment = attrs[NSAttachmentAttributeName];
            NSTextAttachment *replacement = [[NSTextAttachment alloc] init];
            replacement.image = [attachment.image grayscaleImage];
            [result appendAttributedString:[NSAttributedString attributedStringWithAttachment:replacement]];
            return;
        }
        
        NSString *string = [self.string substringWithRange:range];
        NSMutableDictionary *attributes = [attrs mutableCopy];
        [attributes removeObjectForKey:NSBackgroundColorAttributeName];
        [attributes removeObjectForKey:NSForegroundColorAttributeName];
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
        [result appendAttributedString:attributedString];
    }];
    return result;
}

@end
