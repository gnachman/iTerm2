//
//  NSAttributedString+NSAttributedString_PSM.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/20.
//

#import <AppKit/AppKit.h>
#import "NSAttributedString+PSM.h"
#import "RegexKitLite.h"

@implementation NSAttributedString (PSM)

- (NSAttributedString *)attributedStringWithTextAlignment:(NSTextAlignment)textAlignment {
    if (self.length == 0) {
        return self;
    }
    NSInteger representativeIndex = self.length;
    representativeIndex = MAX(0, representativeIndex - 1);
    NSDictionary *immutableAttributes = [self attributesAtIndex:representativeIndex effectiveRange:nil];
    if (!immutableAttributes) {
        return self;
    }

    NSMutableAttributedString *mutableCopy = [self mutableCopy];
    [self enumerateAttributesInRange:NSMakeRange(0, self.length)
                             options:0
                          usingBlock:^(NSDictionary<NSAttributedStringKey,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {
        NSMutableParagraphStyle *paragraphStyle = [attrs[NSParagraphStyleAttributeName] mutableCopy];
        if (!paragraphStyle) {
            paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        }
        paragraphStyle.alignment = textAlignment;
        NSMutableDictionary *updatedAttrs = [attrs mutableCopy];
        updatedAttrs[NSParagraphStyleAttributeName] = paragraphStyle;
        [mutableCopy setAttributes:updatedAttrs range:range];
    }];
    return mutableCopy;
}

// This is the world's worst HTML parser. It knows <b>, <i>, <u>, and
// <font color="#rrggbb"> (or #rgb, in single, double, or no quotes), and decodes the
// entities iterm2.escape_html() produces. Anything else is text.

// #rgb or #rrggbb in sRGB, or nil.
static NSColor *PSMColorFromHTMLHexString(NSString *string) {
    NSString *hex = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![hex hasPrefix:@"#"]) {
        return nil;
    }
    hex = [hex substringFromIndex:1];
    if (hex.length == 3) {
        NSMutableString *expanded = [NSMutableString string];
        for (NSUInteger i = 0; i < 3; i++) {
            NSString *digit = [hex substringWithRange:NSMakeRange(i, 1)];
            [expanded appendFormat:@"%@%@", digit, digit];
        }
        hex = expanded;
    }
    if (hex.length != 6 ||
        [hex rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound) {
        return nil;
    }
    unsigned int value = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&value];
    return [NSColor colorWithSRGBRed:((value >> 16) & 0xff) / 255.0
                               green:((value >> 8) & 0xff) / 255.0
                                blue:(value & 0xff) / 255.0
                               alpha:1];
}

static NSString *PSMDecodeHTMLEntities(NSString *string) {
    if ([string rangeOfString:@"&"].location == NSNotFound) {
        return string;
    }
    string = [string stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    string = [string stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    string = [string stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    string = [string stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    // Last, so "&amp;lt;" becomes "&lt;" rather than "<".
    return [string stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

+ (instancetype)newAttributedStringWithHTML:(NSString *)html attributes:(NSDictionary *)attributes {
    typedef NS_OPTIONS(NSUInteger, PSMTextOption) {
        PSMTextOptionBold = 1 << 0,
        PSMTextOptionItalic = 1 << 1,
        PSMTextOptionUnderline = 1 << 2
    };
    NSArray<NSString *> *openTags = @[ @"<b>", @"<i>", @"<u>" ];
    NSArray<NSString *> *closeTags = @[ @"</b>", @"</i>", @"</u>" ];
    // A title with no tags may still escape characters, and those entities
    // must be decoded the same way as in a title that has tags.
    // Closing tags count too: a fragment may close a tag opened elsewhere.
    NSArray<NSString *> *markers = [[openTags arrayByAddingObjectsFromArray:closeTags] arrayByAddingObjectsFromArray:@[ @"<font", @"</font>", @"&lt;", @"&gt;", @"&quot;", @"&#39;", @"&amp;" ]];
    BOOL isHTML = NO;
    for (NSString *marker in markers) {
        if ([html rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) {
            isHTML = YES;
            break;
        }
    }
    if (!isHTML) {
        return [[NSAttributedString alloc] initWithString:html attributes:attributes];
    }
    NSFont *font = attributes[NSFontAttributeName] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    __block PSMTextOption options = 0;
    __block NSInteger cursor = 0;
    // Each <font> pushes its color, or NSNull when it has none to apply, so its
    // </font> restores the color outside it.
    NSMutableArray *colorStack = [NSMutableArray array];
    static NSMutableDictionary *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    NSDictionary *(^attributesForOptions)(PSMTextOption) = ^NSDictionary *(PSMTextOption options) {
        if (options == 0) {
            return attributes;
        }
        id key = @[ @(options), attributes ];
        if (cache[key]) {
            return cache[key];
        }
        NSMutableDictionary *modifiedAttributes = [attributes mutableCopy];
        NSFontDescriptorSymbolicTraits traits = 0;
        if (options & PSMTextOptionBold) {
            traits |= NSFontDescriptorTraitBold;
        }
        if (options & PSMTextOptionItalic) {
            traits |= NSFontDescriptorTraitItalic;
        }
        NSFont *modifiedFont = font;
        if (traits != 0) {
            modifiedFont = [NSFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:traits]
                                                 size:font.pointSize];
        }
        if (options & PSMTextOptionUnderline) {
            modifiedAttributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        modifiedAttributes[NSFontAttributeName] = modifiedFont;
        cache[key] = modifiedAttributes;
        return modifiedAttributes;
    };
    NSColor *(^currentColor)(void) = ^NSColor *{
        for (id color in colorStack.reverseObjectEnumerator) {
            if ([color isKindOfClass:[NSColor class]]) {
                return color;
            }
        }
        return nil;
    };
    void (^appendWithTagRange)(NSRange) = ^(NSRange tagRange) {
        NSString *string = PSMDecodeHTMLEntities([html substringWithRange:NSMakeRange(cursor, tagRange.location - cursor)]);
        if (string.length > 0) {
            NSDictionary *runAttributes = attributesForOptions(options);
            NSColor *color = currentColor();
            if (color) {
                NSMutableDictionary *colored = [runAttributes mutableCopy];
                colored[NSForegroundColorAttributeName] = color;
                runAttributes = colored;
            }
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:string
                                                                           attributes:runAttributes]];
        }
        cursor = NSMaxRange(tagRange);
        if (tagRange.length == 0) {
            return;
        }
        NSString *tag = [[html substringWithRange:tagRange] lowercaseString];
        if ([tag hasPrefix:@"<font"]) {
            NSString *value = [tag stringByMatching:@"=\\s*[\"']?\\s*([^\"'\\s>]*)" capture:1];
            NSColor *color = PSMColorFromHTMLHexString(value ?: @"");
            [colorStack addObject:color ?: [NSNull null]];
            return;
        }
        if ([tag isEqualToString:@"</font>"]) {
            if (colorStack.count > 0) {
                [colorStack removeLastObject];
            }
            return;
        }
        NSInteger i = [openTags indexOfObject:tag];
        if (i != NSNotFound) {
            options |= (1 << i);
        } else {
            i = [closeTags indexOfObject:tag];
            if (i != NSNotFound) {
                options &= ~(1 << i);
            }
        }
    };

    NSArray<NSString *> *tagPatterns = [[openTags arrayByAddingObjectsFromArray:closeTags] arrayByAddingObjectsFromArray:@[
        @"<font\\s+color\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s\"'>]*)\\s*>",
        @"</font>" ]];
    NSString *regex = [tagPatterns componentsJoinedByString:@"|"];
    [html enumerateStringsMatchedByRegex:regex
                                 options:RKLCaseless
                                 inRange:NSMakeRange(0, html.length)
                                   error:nil
                      enumerationOptions:RKLRegexEnumerationNoOptions
                              usingBlock:^(NSInteger captureCount,
                                           NSString *const __unsafe_unretained *capturedStrings,
                                           const NSRange *capturedRanges,
                                           volatile BOOL *const stop) {
        appendWithTagRange(capturedRanges[0]);
    }];

    if (cursor < html.length) {
        appendWithTagRange(NSMakeRange(html.length, 0));
    }
    return result;
}

@end
