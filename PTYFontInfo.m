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

- (PTYFontInfo *)computedBoldVersion {
    NSFontManager* fontManager = [NSFontManager sharedFontManager];
    NSFont* boldFont = [fontManager convertFont:font_ toHaveTrait:NSBoldFontMask];
    if (boldFont && ([fontManager traitsOfFont:boldFont] & NSBoldFontMask)) {
        return [PTYFontInfo fontInfoWithFont:boldFont baseline:baselineOffset_];
    } else {
        return nil;
    }
}

- (PTYFontInfo *)computedItalicVersion {
    NSFontManager* fontManager = [NSFontManager sharedFontManager];
    NSFont* italicFont = [fontManager convertFont:font_ toHaveTrait:NSItalicFontMask];
    if (italicFont && ([fontManager traitsOfFont:italicFont] & NSItalicFontMask)) {
        return [PTYFontInfo fontInfoWithFont:italicFont baseline:baselineOffset_];
    } else {
        return nil;
    }
}

@end
