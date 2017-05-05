//
//  PTYFontInfo.m
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import "PTYFontInfo.h"

#import "DebugLogging.h"

@implementation NSFont(PTYFontInfo)

- (NSInteger)it_ligatureLevel {
    // Returns the proper ligature level for this font. Defaults to 1.
    static NSDictionary *fontNameToLigatureLevel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fontNameToLigatureLevel = @{ @"Iosevka": @2,
                                     @"Iosevka-Bold": @2,
                                     @"Iosevka-Bold-Italic": @2,
                                     @"Iosevka-Bold-Oblique": @2,
                                     @"Iosevka-Extralight": @2,
                                     @"Iosevka-Extralight-Italic": @2,
                                     @"Iosevka-Extralight-Oblique": @2,
                                     @"Iosevka-Heavy": @2,
                                     @"Iosevka-Heavy-Italic": @2,
                                     @"Iosevka-Heavy-Oblique": @2,
                                     @"Iosevka-Italic": @2,
                                     @"Iosevka-Light": @2,
                                     @"Iosevka-Light-Italic": @2,
                                     @"Iosevka-Light-Oblique": @2,
                                     @"Iosevka-Medium": @2,
                                     @"Iosevka-Medium-Italic": @2,
                                     @"Iosevka-Medium-Oblique": @2,
                                     @"Iosevka-Oblique": @2,
                                     @"Iosevka-Thin": @2,
                                     @"Iosevka-Thin-Italic": @2,
                                     @"Iosevka-Thin-Oblique": @2,
                                     @"Iosevka-Slab": @2,
                                     @"Iosevka-Slab-Bold": @2,
                                     @"Iosevka-Slab-Bold-Italic": @2,
                                     @"Iosevka-Slab-Bold-Oblique": @2,
                                     @"Iosevka-Slab-Extralight": @2,
                                     @"Iosevka-Slab-Extralight-Italic": @2,
                                     @"Iosevka-Slab-Extralight-Oblique": @2,
                                     @"Iosevka-Slab-Heavy": @2,
                                     @"Iosevka-Slab-Heavy-Italic": @2,
                                     @"Iosevka-Slab-Heavy-Oblique": @2,
                                     @"Iosevka-Slab-Italic": @2,
                                     @"Iosevka-Slab-Light": @2,
                                     @"Iosevka-Slab-Light-Italic": @2,
                                     @"Iosevka-Slab-Light-Oblique": @2,
                                     @"Iosevka-Slab-Medium": @2,
                                     @"Iosevka-Slab-Medium-Italic": @2,
                                     @"Iosevka-Slab-Medium-Oblique": @2,
                                     @"Iosevka-Slab-Oblique": @2,
                                     @"Iosevka-Slab-Thin": @2,
                                     @"Iosevka-Slab-Thin-Italic": @2,
                                     @"Iosevka-Slab-Thin-Oblique": @2,
                                     @"IosevkaCC": @2,
                                     @"IosevkaCC-Bold": @2,
                                     @"IosevkaCC-Bold-Italic": @2,
                                     @"IosevkaCC-Bold-Oblique": @2,
                                     @"IosevkaCC-Extralight": @2,
                                     @"IosevkaCC-Extralight-Italic": @2,
                                     @"IosevkaCC-Extralight-Oblique": @2,
                                     @"IosevkaCC-Heavy": @2,
                                     @"IosevkaCC-Heavy-Italic": @2,
                                     @"IosevkaCC-Heavy-Oblique": @2,
                                     @"IosevkaCC-Italic": @2,
                                     @"IosevkaCC-Light": @2,
                                     @"IosevkaCC-Light-Italic": @2,
                                     @"IosevkaCC-Light-Oblique": @2,
                                     @"IosevkaCC-Medium": @2,
                                     @"IosevkaCC-Medium-Italic": @2,
                                     @"IosevkaCC-Medium-Oblique": @2,
                                     @"IosevkaCC-Oblique": @2,
                                     @"IosevkaCC-Thin": @2,
                                     @"IosevkaCC-Thin-Italic": @2,
                                     @"IosevkaCC-Thin-Oblique": @2,
                                     @"IosevkaCC-Slab": @2,
                                     @"IosevkaCC-Slab-Bold": @2,
                                     @"IosevkaCC-Slab-Bold-Italic": @2,
                                     @"IosevkaCC-Slab-Bold-Oblique": @2,
                                     @"IosevkaCC-Slab-Extralight": @2,
                                     @"IosevkaCC-Slab-Extralight-Italic": @2,
                                     @"IosevkaCC-Slab-Extralight-Oblique": @2,
                                     @"IosevkaCC-Slab-Heavy": @2,
                                     @"IosevkaCC-Slab-Heavy-Italic": @2,
                                     @"IosevkaCC-Slab-Heavy-Oblique": @2,
                                     @"IosevkaCC-Slab-Italic": @2,
                                     @"IosevkaCC-Slab-Light": @2,
                                     @"IosevkaCC-Slab-Light-Italic": @2,
                                     @"IosevkaCC-Slab-Light-Oblique": @2,
                                     @"IosevkaCC-Slab-Medium": @2,
                                     @"IosevkaCC-Slab-Medium-Italic": @2,
                                     @"IosevkaCC-Slab-Medium-Oblique": @2,
                                     @"IosevkaCC-Slab-Oblique": @2,
                                     @"IosevkaCC-Slab-Thin": @2,
                                     @"IosevkaCC-Slab-Thin-Italic": @2,
                                     @"IosevkaCC-Slab-Thin-Oblique": @2, };
        [fontNameToLigatureLevel retain];
    });
    NSNumber *value = fontNameToLigatureLevel[self.fontName];
    return value ? value.integerValue : 1;
}

- (BOOL)it_defaultLigatures {
    // Some fonts have great ligatures but unlike FiraCode you need to ask for them. FiraCode gives
    // you ligatures whether you like it or not.
    static NSSet *fontsWithDefaultLigatures;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fontsWithDefaultLigatures = [[NSSet setWithArray:@[ @"FiraCode-Bold",
                                                            @"FiraCode-Light",
                                                            @"FiraCode-Medium",
                                                            @"FiraCode-Regular",
                                                            @"FiraCode-Retina",
                                                            @"FuraCodeNerdFontCompleteMono---Bold",
                                                            @"FuraCodeNerdFontCompleteMono---Light",
                                                            @"FuraCodeNerdFontCompleteMono---Medium",
                                                            @"FuraCodeNerdFontCompleteMono---Regular",
                                                            @"FuraCodeNerdFontCompleteMono---Retina" ]] retain];
    });
    BOOL result = [fontsWithDefaultLigatures containsObject:self.fontName];
    DLog(@"Default ligatures for '%@' is %@", self.fontName, @(result));
    return result;
}

@end

@implementation PTYFontInfo {
    NSFont *font_;
    PTYFontInfo *boldVersion_;
    PTYFontInfo *italicVersion_;
}

@synthesize font = font_;
@synthesize boldVersion = boldVersion_;
@synthesize italicVersion = italicVersion_;

+ (PTYFontInfo *)fontInfoWithFont:(NSFont *)font {
    PTYFontInfo *fontInfo = [[[PTYFontInfo alloc] init] autorelease];
    fontInfo.font = font;
    return fontInfo;
}

- (void)dealloc {
    [font_ release];
    [boldVersion_ release];
    [italicVersion_ release];
    [super dealloc];
}

- (void)setFont:(NSFont *)font {
    [font_ autorelease];
    font_ = [font retain];
    
    _ligatureLevel = font.it_ligatureLevel;
    _hasDefaultLigatures = font.it_defaultLigatures;

    _baselineOffset = [self computedBaselineOffset];
    _underlineOffset = [self computedUnderlineOffset];
}

- (CGFloat)descender {
    // See issue 4957 for the Monaco hack.
    CGFloat extraDescender = 0;
    if (![font_.fontName isEqualToString:@"Monaco"]) {
        extraDescender = 0.5;
    }
    CGFloat descender = self.font.descender + extraDescender;
    return descender;
}

- (CGFloat)computedBaselineOffset {
    return -(floorf(font_.leading) - floorf(self.descender));
}

// From https://github.com/DrawKit/DrawKit/blob/master/framework/Code/NSBezierPath%2BText.m#L648
- (CGFloat)computedUnderlineOffset {
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    NSTextContainer *textContainer = [[[NSTextContainer alloc] init] autorelease];
    [layoutManager addTextContainer:textContainer];
    NSDictionary *attributes = @{ NSFontNameAttribute: font_,
                                  NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle) };
    NSAttributedString *attributedString = [[[NSAttributedString alloc] initWithString:@"M" attributes:attributes] autorelease];
    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:attributedString];
    [textStorage addLayoutManager:layoutManager];
    
    NSUInteger glyphIndex = [layoutManager glyphIndexForCharacterAtIndex:0];
    return [[layoutManager typesetter] baselineOffsetInLayoutManager:layoutManager
                                                          glyphIndex:glyphIndex] / -2.0;
}

// Issue 4294 reveals that merely upconverting the weight of a font once is not sufficient because
// it might go from Regular to Medium. You need to keep trying until you find a font that is relatively
// bold. This is a nice way to do it because the user could, e.g., pick a "thin" font and get the
// "medium" version for "bold" text. We convertWeight: until the weight is at least 4 higher than
// the original font. See the table in the docs for convertWeight:ofFont: for what this means.
- (NSFont *)boldVersionOfFont:(NSFont *)font {
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSInteger weight = [fontManager weightOfFont:font];
    NSInteger minimumAcceptableWeight = weight + 4;
    DLog(@"Looking for a bold version of %@, whose weight is %@", font, @(weight));
    NSFont *lastFont = font;
    
    // Sometimes the heavier version of a font is oblique (issue 4442). So
    // check the traits to make sure nothing significant changes.
    const NSFontTraitMask kImmutableTraits = (NSItalicFontMask |
                                              NSNarrowFontMask |
                                              NSExpandedFontMask |
                                              NSCondensedFontMask |
                                              NSSmallCapsFontMask |
                                              NSPosterFontMask |
                                              NSCompressedFontMask |
                                              NSFixedPitchFontMask |
                                              NSUnitalicFontMask);
    NSFontTraitMask requiredTraits = ([fontManager traitsOfFont:font] & kImmutableTraits);
    DLog(@"Required traits: %x", (int)requiredTraits);
    while (lastFont) {
        NSFont *heavierFont = [fontManager convertWeight:YES ofFont:lastFont];
        if (heavierFont == lastFont) {
            // This is how fontManager is documented to fail.
            return nil;
        }
        NSInteger weight = [fontManager weightOfFont:heavierFont];
        DLog(@"  next bolder font is %@ with a weight of %@",  heavierFont, @(weight));
        NSFontTraitMask maskedTraits = ([fontManager traitsOfFont:heavierFont] & kImmutableTraits);
        DLog(@"  masked traits=%x", (int)maskedTraits);
        if (maskedTraits == requiredTraits && weight >= minimumAcceptableWeight) {
            DLog(@"  accepted!");
            return heavierFont;
        }
        lastFont = heavierFont;
    }
    DLog(@"Failed to find a bold version that's bold enough");
    return nil;
}

- (PTYFontInfo *)computedBoldVersion {
    NSFont *boldFont = [self boldVersionOfFont:font_];
    DLog(@"Bold version of %@ is %@", font_, boldFont);
    if (boldFont && boldFont != font_) {
        return [PTYFontInfo fontInfoWithFont:boldFont];
    } else {
        DLog(@"Failed to find a bold version of %@", font_);
        return nil;
    }
}

- (PTYFontInfo *)computedItalicVersion {
    NSFontManager* fontManager = [NSFontManager sharedFontManager];
    NSFont* italicFont = [fontManager convertFont:font_ toHaveTrait:NSItalicFontMask];
    DLog(@"Italic version of %@ is %@", font_, italicFont);
    if (italicFont && italicFont != font_) {
        return [PTYFontInfo fontInfoWithFont:italicFont];
    } else {
        DLog(@"Failed to find an italic version of %@", font_);
        return nil;
    }
}

- (PTYFontInfo *)computedBoldItalicVersion {
    PTYFontInfo *temp = [self computedBoldVersion];
    return [temp computedItalicVersion];
}

@end
