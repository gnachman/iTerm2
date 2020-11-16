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

// This is the world's worst HTML parser.
+ (instancetype)newAttributedStringWithHTML:(NSString *)html attributes:(NSDictionary *)attributes {
    typedef NS_OPTIONS(NSUInteger, PSMTextOption) {
        PSMTextOptionBold = 1 << 0,
        PSMTextOptionItalic = 1 << 1,
        PSMTextOptionUnderline = 1 << 2
    };
    BOOL isHTML = NO;
    NSArray<NSString *> *openTags = @[ @"<b>", @"<i>", @"<u>" ];
    NSArray<NSString *> *closeTags = @[ @"</b>", @"</i>", @"</u>" ];
    for (NSString *tag in openTags) {
        if ([html containsString:tag]) {
            isHTML = YES;
            break;
        }
    }
    if (!isHTML) {
        return [[NSAttributedString alloc] initWithString:html attributes:attributes];
    }
    NSFont *font = attributes[NSFontAttributeName] ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    __block PSMTextOption options = NO;
    __block NSInteger cursor = 0;
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
    void (^appendWithTagRange)(NSRange) = ^(NSRange tagRange) {
        NSString *string = [html substringWithRange:NSMakeRange(cursor, tagRange.location - cursor)];
        string = [string stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
        string = [string stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        NSAttributedString *part = [[NSAttributedString alloc] initWithString:string
                                                                   attributes:attributesForOptions(options)];
        [result appendAttributedString:part];
        cursor = NSMaxRange(tagRange);
        NSString *tag = [html substringWithRange:tagRange];
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

    NSString *regex = [[openTags arrayByAddingObjectsFromArray:closeTags] componentsJoinedByString:@"|"];
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
