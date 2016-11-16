//
//  PTYFontInfo.m
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import "PTYFontInfo.h"

#import "DebugLogging.h"

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
    
    // Some fonts have great ligatures but unlike FiraCode you need to ask for them. FiraCode gives
    // you ligatures whether you like it or not.
    static NSDictionary *fontNameToLigatureLevel;
    static NSSet *fontsWithDefaultLigatures;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fontNameToLigatureLevel = @{ @"PragmataPro": @1,
                                     @"Hasklig-Black": @1,
                                     @"Hasklig-BlackIt": @1,
                                     @"Hasklig-Bold": @1,
                                     @"Hasklig-BoldIt": @1,
                                     @"Hasklig-ExtraLight": @1,
                                     @"Hasklig-ExtraLightIt": @1,
                                     @"Hasklig-It": @1,
                                     @"Hasklig-Light": @1,
                                     @"Hasklig-LightIt": @1,
                                     @"Hasklig-Medium": @1,
                                     @"Hasklig-MediumIt": @1,
                                     @"Hasklig-Regular": @1,
                                     @"Hasklig-Semibold": @1,
                                     @"Hasklig-SemiboldIt": @1,
                                     @"OperatorMono-XLight": @1,
                                     @"OperatorMono-XLightItalic": @1,
                                     @"OperatorMono-Light": @1,
                                     @"OperatorMono-LightItalic": @1,
                                     @"OperatorMono-Book": @1,
                                     @"OperatorMono-BookItalic": @1,
                                     @"OperatorMono-Medium": @1,
                                     @"OperatorMono-MediumItalic": @1,
                                     @"OperatorMono-Bold": @1,
                                     @"OperatorMono-BoldItalic": @1 };
        fontsWithDefaultLigatures = [[NSSet setWithArray:@[ @"FiraCode-Bold",
                                                            @"FiraCode-Light",
                                                            @"FiraCode-Medium",
                                                            @"FiraCode-Regular",
                                                            @"FiraCode-Retina" ]] retain];
        [fontNameToLigatureLevel retain];
    });
    _ligatureLevel = [fontNameToLigatureLevel[font.fontName] integerValue];
    _hasDefaultLigatures = [fontsWithDefaultLigatures containsObject:font.fontName];

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
