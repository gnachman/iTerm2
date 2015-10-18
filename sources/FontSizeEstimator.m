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

@implementation FontSizeEstimator

@synthesize size;
@synthesize baseline;

- (instancetype)initWithSize:(NSSize)s baseline:(double)b {
    self = [super init];
    if (self) {
        size = s;
        baseline = b;
    }
    return self;
}

+ (id)fontSizeEstimatorForFont:(NSFont *)aFont
{
    FontSizeEstimator* fse = [[[FontSizeEstimator alloc] init] autorelease];
    if (fse) {
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        [dic setObject:aFont forKey:NSFontAttributeName];
        NSSize size = [@"W" sizeWithAttributes:dic];

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
        }
        CGFontRelease(cgfont);

        size.height = [aFont ascender] - [aFont descender];
        double baseline = -(floorf([aFont leading]) - floorf([aFont descender]));
        fse.size = size;
        fse.baseline = baseline;
    }
    return fse;
}

@end
