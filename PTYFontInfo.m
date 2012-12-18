//
//  PTYFontInfo.m
//  iTerm
//
//  Created by George Nachman on 12/17/12.
//
//

#import "PTYFontInfo.h"

@implementation PTYFontInfo

@synthesize font = font_;
@synthesize baselineOffset = baselineOffset_;
@synthesize boldVersion = boldVersion_;

+ (PTYFontInfo *)fontInfoWithFont:(NSFont *)font baseline:(double)baseline {
    PTYFontInfo *fontInfo = [[[PTYFontInfo alloc] init] autorelease];
    fontInfo.font = font;
    fontInfo.baselineOffset = baseline;
    return fontInfo;
}

- (void)dealloc {
    [font_ release];
    [boldVersion_ release];
    [super dealloc];
}

- (PTYFontInfo *)computedBoldVersion {
    NSFontManager* fontManager = [NSFontManager sharedFontManager];
    NSFont* boldFont = [fontManager convertFont:font_ toHaveTrait:NSBoldFontMask];
    if (boldFont && ([fontManager traitsOfFont:boldFont] & NSBoldFontMask)) {
        return [PTYFontInfo fontInfoWithFont:boldFont baseline:baselineOffset_];
    } else {
        return nil;
    }
}

- (BOOL)hasGlyphForCharacter:(unichar)theChar {
    CGGlyph tempGlyph;
    return CTFontGetGlyphsForCharacters((CTFontRef)font_, &theChar, &tempGlyph, 1);
}

@end
