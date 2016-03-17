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

- (PTYFontInfo *)computedBoldVersion {
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFont *boldFont = [fontManager convertWeight:YES ofFont:font_];
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
