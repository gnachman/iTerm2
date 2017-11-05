// -*- mode:objc -*-
/*
 **  FontSizeEstimator.h
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Attempts to measure font metrics because the OS's metrics
 **    are sometimes unreliable.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "FontSizeEstimator.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

@implementation FontSizeEstimator

@synthesize size;

- (instancetype)initWithSize:(NSSize)s baseline:(double)b {
    self = [super init];
    if (self) {
        size = s;
        baseline = b;
    }
    return self;
}

+ (NSLayoutManager *)newLayoutManagerForFont:(NSFont *)aFont textContainer:(NSTextContainer *)textContainer {
    NSString *myString = @"W";

    NSTextStorage *textStorage = [[[NSTextStorage alloc] initWithString:myString] autorelease];
    NSLayoutManager *layoutManager = [[[NSLayoutManager alloc] init] autorelease];
    [layoutManager addTextContainer:textContainer];
    [textStorage addLayoutManager:layoutManager];
    [textStorage addAttribute:NSFontAttributeName
                        value:aFont
                        range:NSMakeRange(0, [textStorage length])];
    [textContainer setLineFragmentPadding:0.0];
    [layoutManager glyphRangeForTextContainer:textContainer];
    return layoutManager;
}

+ (NSTextContainer *)newTextContainer {
    return [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)] autorelease];
}

+ (id)fontSizeEstimatorForFont:(NSFont *)aFont
{
    FontSizeEstimator* fse = [[[FontSizeEstimator alloc] init] autorelease];
    if (fse) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        [dic setObject:aFont forKey:NSFontAttributeName];
        NSSize size = [@"W" sizeWithAttributes:dic];
        DLog(@"Initial guess at a size for %@ is %@", aFont, NSStringFromSize(size));
        CGGlyph glyphs[1];
        int advances[1];
        UniChar characters[1];
        characters[0] = 'W';
        CTFontRef ctfont = (CTFontRef)aFont;  // Toll-free bridged
        CGFontRef cgfont = CTFontCopyGraphicsFont(ctfont, NULL);
        CTFontGetGlyphsForCharacters(ctfont, characters, glyphs, 1);
        if (CGFontGetGlyphAdvances(cgfont,
                                   glyphs,
                                   1,
                                   advances)) {
            size.width = advances[0];
            size.width *= [aFont pointSize];
            size.width /= CGFontGetUnitsPerEm(cgfont);
            size.width = round(size.width);
            DLog(@"Improving my guess for width using formula round(%d * %f / %d) giving %f",
                 advances[0],
                 [aFont pointSize],
                 CGFontGetUnitsPerEm(cgfont),
                 size.width);
        }

        CGFontRelease(cgfont);

        size.height = [aFont ascender] - [aFont descender];

        // Things go very badly indeed if the size is 0.
        size.width = MAX(1, size.width);
        size.height = MAX(1, size.height);

        if ([iTermAdvancedSettingsModel useExperimentalFontMetrics]) {
            NSTextContainer *textContainer = [self newTextContainer];
            NSLayoutManager *layoutManager = [self newLayoutManagerForFont:aFont
                                                             textContainer:textContainer];
            NSRect usedRect = [layoutManager usedRectForTextContainer:textContainer];

            fse.size = usedRect.size;
        } else {
            fse.size = size;
        }
    }
    return fse;
}

@end
