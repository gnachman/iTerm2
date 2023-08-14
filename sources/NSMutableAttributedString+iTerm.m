//
//  NSMutableAttributedString+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import <Cocoa/Cocoa.h>

#include "NSImage+iTerm.h"
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

// The HTML parser built in to NSAttributedString is unusable because it sets an sRGB color for
// the default text color, breaking light/dark mode. I <3 AppKit
+ (NSAttributedString *)attributedStringWithHTML:(NSString *)htmlString font:(NSFont *)font paragraphStyle:(NSParagraphStyle *)paragraphStyle {
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
    [attributedString addAttributes:@{ NSFontAttributeName: font,
                                       NSParagraphStyleAttributeName: paragraphStyle
                                    }
                              range:NSMakeRange(0, 0)];
    NSInteger currentIndex = 0;
    
    while (currentIndex < htmlString.length) {
        if ([htmlString characterAtIndex:currentIndex] == '<') {
            NSRange endRange = [htmlString rangeOfString:@">"];
            if (endRange.location != NSNotFound) {
                NSRange tagRange = [htmlString rangeOfString:@"<a href=\"" options:0 range:NSMakeRange(currentIndex, htmlString.length - currentIndex)];
                if (tagRange.location == currentIndex) {
                    const NSInteger urlStart = NSMaxRange(tagRange);
                    const NSRange endQuoteRange = [htmlString rangeOfString:@"\"" options:0 range:NSMakeRange(urlStart, htmlString.length - urlStart)];
                    NSInteger urlEnd;
                    if (endQuoteRange.location == NSNotFound) {
                        urlEnd = htmlString.length;
                    } else {
                        urlEnd = endQuoteRange.location;
                    }
                    NSString *url = [htmlString substringWithRange:NSMakeRange(urlStart, urlEnd - urlStart)];
                    const NSInteger textStart = urlEnd + 2;
                    const NSRange endAnchorRange = [htmlString rangeOfString:@"</a>" options:0 range:NSMakeRange(textStart, htmlString.length - textStart)];
                    NSInteger textEnd;
                    if (endAnchorRange.location != NSNotFound) {
                        textEnd = endAnchorRange.location;
                    } else {
                        textEnd = htmlString.length;
                    }
                    NSString *text = [htmlString substringWithRange:NSMakeRange(textStart, textEnd - textStart)];
                    NSDictionary *linkAttributes = @{
                        NSFontAttributeName: font,
                        NSParagraphStyleAttributeName: paragraphStyle,
                        NSLinkAttributeName: url,
                        NSCursorAttributeName: NSCursor.pointingHandCursor
                    };
                    [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:linkAttributes]];
                    currentIndex = textEnd + 4;
                    continue;
                }
            }
        }
        
        NSInteger nextIndex;
        const NSRange lessThanRange = [htmlString rangeOfString:@"<" options:0 range:NSMakeRange(currentIndex, htmlString.length - currentIndex)];
        if (lessThanRange.location == NSNotFound) {
            nextIndex = htmlString.length;
        } else {
            nextIndex = lessThanRange.location;
        }
        NSString *text = [htmlString substringWithRange:NSMakeRange(currentIndex, nextIndex - currentIndex)];
        [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName: font,
                                                                                                               NSParagraphStyleAttributeName: paragraphStyle,
                                                                                                               NSForegroundColorAttributeName: [NSColor textColor] }]];
        currentIndex = nextIndex;
    }
    
    return attributedString;
}

@end
