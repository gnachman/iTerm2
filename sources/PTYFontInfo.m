//
//  PTYFontInfo.m
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import "PTYFontInfo.h"

#import "DebugLogging.h"

@implementation PTYFontInfo

@synthesize font = font_;
@synthesize baselineOffset = baselineOffset_;
@synthesize boldVersion = boldVersion_;
@synthesize italicVersion = italicVersion_;

+ (PTYFontInfo *)fontInfoWithFont:(NSFont *)font baseline:(double)baseline {
    PTYFontInfo *fontInfo = [[[PTYFontInfo alloc] init] autorelease];
    fontInfo.font = font;
    fontInfo.baselineOffset = baseline;
    return fontInfo;
}

- (void)dealloc {
    [font_ release];
    [boldVersion_ release];
    [italicVersion_ release];
    [super dealloc];
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
        return [PTYFontInfo fontInfoWithFont:boldFont baseline:baselineOffset_];
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
        return [PTYFontInfo fontInfoWithFont:italicFont baseline:baselineOffset_];
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
