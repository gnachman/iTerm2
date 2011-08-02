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

// Constants for converting RGB to luma.
#define RED_COEFFICIENT    0.30
#define GREEN_COEFFICIENT  0.59
#define BLUE_COEFFICIENT   0.11

@implementation FontSizeEstimator

@synthesize size;
@synthesize baseline;

static double Brightness(NSColor* c) {
    const double r = [c redComponent];
    const double g = [c greenComponent];
    const double b = [c blueComponent];

    return (RED_COEFFICIENT * r) + (GREEN_COEFFICIENT * g) + (BLUE_COEFFICIENT * b);
}

- (NSSize)osEstimate:(NSFont *)aFont
{
    if (!osBound.width) {
        osBound = NSZeroSize;
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        [dic setObject:aFont forKey:NSFontAttributeName];
        for (unichar i = 'A'; i <= 'Z'; i++) {
            NSString* s = [NSString stringWithCharacters:&i length:1];
            NSSize charSize = [s sizeWithAttributes:dic];
            osBound.width = MAX(size.width, charSize.width);
            osBound.height = MAX(size.height, charSize.height);
        }
    }

    return osBound;
}

- (NSImage *)imageForString:(NSString*)s withFont:(NSFont*)aFont
{
    NSSize osSize = [self osEstimate:aFont];
    NSSize estimate = osSize;
    estimate.width *= 4;
    estimate.height *= 4;
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(estimate.width, estimate.height)] autorelease];
    [image lockFocus];

    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    assert(ctx);
    CGContextSetShouldAntialias(ctx, YES);

    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, estimate.width, estimate.height));

    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           aFont, NSFontAttributeName,
                           [NSColor blackColor], NSForegroundColorAttributeName,
                           nil];

    for (int i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        NSAttributedString *str = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%C", c]
                                                                  attributes:attrs];
        [str drawWithRect:NSMakeRect(0,
                                     osSize.height * 2,
                                     osSize.width * 2,
                                     osSize.height * 2)
                  options:0];
        [str release];
    }
    [image unlockFocus];

    return image;
}

+ (double)xBoundOfImage:(NSImage *)i startingAt:(int)startAt dir:(int)dir threshold:(double)threshold cache:(double*)cache
{
    int maxX = [i size].width;
    int maxY = [i size].height;
    int x;
    for (x = startAt; x >= 0 && x < maxX; x += dir) {
        for (int y = 0; y < maxY; y++) {
            if (cache[x + (maxY - y - 1) * maxX] < threshold) {
                return x;
            }
        }
    }
    return x;
}

+ (double)yBoundOfImage:(NSImage *)i startingAt:(int)startAt dir:(int)dir threshold:(double)threshold cache:(double*)cache
{
    int maxX = [i size].width;
    int maxY = [i size].height;
    int y;
    for (y = startAt; y >= 0 && y < maxY; y += dir) {
        for (int x = 0; x < maxX; x++) {
            if (cache[x + (maxY - y - 1) * maxX] < threshold) {
                return y;
            }
        }
    }
    return y;
}

+ (void)dumpImage:(NSImage *)i
{
    [i lockFocus];
    for (int y = [i size].height - 1; y >= 0; y--) {
        unichar temp[1000];
        int x;
        for (x = 0; x < [i size].width; x++) {
            NSColor *c = NSReadPixel(NSMakePoint(x, y));
            //NSLog(@"%@ %lf", c, Brightness(c));
            if (Brightness(c) < 0.25) {
                temp[x] = ' ';
            } else if (Brightness(c) < 0.5) {
                temp[x] = '.';
            } else if (Brightness(c) < 0.75) {
                temp[x] = 'o';
            } else if (Brightness(c) < 0.99) {
                temp[x] = '%';
            } else {
                temp[x] = '#';
            }
        }
        int n = [i size].height - 1 - y;
        NSLog(@"%04d %@", n, [NSString stringWithCharacters:temp length:x]);
    }
    [i unlockFocus];
}

+ (void)dumpImage:(NSImage *)i cache:(double*)cache
{
    for (int y = [i size].height - 1; y >= 0; y--) {
        unichar temp[1000];
        int x;
        for (x = 0; x < [i size].width; x++) {
            double b = cache[x + y * (int)[i size].width];
            if (b < 0.25) {
                temp[x] = ' ';
            } else if (b < 0.5) {
                temp[x] = '.';
            } else if (b < 0.75) {
                temp[x] = 'o';
            } else if (b < 0.99) {
                temp[x] = '%';
            } else {
                temp[x] = '#';
            }
        }
        int n = [i size].height - 1 - y;
        NSLog(@"%04d %@", n, [NSString stringWithCharacters:temp length:x]);
    }
}

- (NSRect)boundsOfImage:(NSImage *)i threshold:(double)threshold cache:(double*)cache
{
    // [FontSizeEstimator dumpImage:i];
    NSRect result = NSZeroRect;
    result.origin.x = [FontSizeEstimator xBoundOfImage:i startingAt:0 dir:1 threshold:threshold cache:cache];
    result.size.width = [FontSizeEstimator xBoundOfImage:i startingAt:[i size].width-1 dir:-1 threshold:threshold cache:cache] - result.origin.x + 1;
    result.origin.y = [FontSizeEstimator yBoundOfImage:i startingAt:0 dir:1 threshold:threshold cache:cache];
    result.size.height = [FontSizeEstimator yBoundOfImage:i startingAt:[i size].height-1 dir:-1 threshold:threshold cache:cache] - result.origin.y + 1;
    return result;
}

- (void)cacheBrightnessOfImage:(NSImage *)i inCache:(double *)cache
{
    [i lockFocus];
    NSSize s = [i size];
    int w = s.width;
    int h = s.height;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            cache[x + y * w] = Brightness(NSReadPixel(NSMakePoint(x, y)));
        }
    }
    [i unlockFocus];
}

- (id)initWithSize:(NSSize)s baseline:(double)b
{
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
        // We get the upper bound of a character from the top of X
        // We get the rightmost bound as the max of right(X) and right(x)
        // We get the descender's height from bottom(y) - bottom(X)
        NSImage *capXImage = [fse imageForString:@"X" withFont:aFont];
        const int w = [capXImage size].width;
        const int h = [capXImage size].height;
        double cache[w*h];
        [fse cacheBrightnessOfImage:capXImage inCache:cache];
        NSRect capXBounds = [fse boundsOfImage:capXImage threshold:0.5 cache:cache];
//        [FontSizeEstimator dumpImage:capXImage cache:cache];

        NSImage *lowXImage = [fse imageForString:@"x" withFont:aFont];
        [fse cacheBrightnessOfImage:lowXImage inCache:cache];
        NSRect lowXBounds = [fse boundsOfImage:lowXImage threshold:0.5 cache:cache];
//        [FontSizeEstimator dumpImage:lowXImage];

        double theMinX = INFINITY, theMinY = INFINITY, theMaxX = -INFINITY, theMaxY = -INFINITY;
        NSString *lowHangingChars[] = {
            @"g", @"j", @"p", @"q", @"y", @"[", @"]", @"{", @"}", @"_", nil
        };
        for (int i = 0; lowHangingChars[i]; i++) {
            NSString *s = lowHangingChars[i];
            NSImage *charImage = [fse imageForString:s withFont:aFont];
            [fse cacheBrightnessOfImage:charImage inCache:cache];
            NSRect bounds = [fse boundsOfImage:charImage threshold:0.99 cache:cache];
            theMinX = MIN(theMinX, bounds.origin.x);
            theMinY = MIN(theMinY, bounds.origin.y);
            theMaxX = MAX(theMaxX, bounds.origin.x + bounds.size.width);
            theMaxY = MAX(theMaxY, bounds.origin.y + bounds.size.height);
//            [FontSizeEstimator dumpImage:charImage];
        }
        NSRect descenderBounds = NSMakeRect(theMinX, theMinY, theMaxX - theMinX, theMaxY - theMinY);

        NSSize s;
        double b;
        double capXMaxX = capXBounds.origin.x + capXBounds.size.width;
        double lowXMaxX = lowXBounds.origin.x + lowXBounds.size.width;
        s.width = MAX(capXMaxX, lowXMaxX);
        s.height = descenderBounds.origin.y + descenderBounds.size.height - capXBounds.origin.y;
        double lowYMaxY = descenderBounds.origin.y + descenderBounds.size.height;
        double capXmaxY = capXBounds.origin.y + capXBounds.size.height;
        b = capXmaxY - lowYMaxY;

        // If the OS reports a larger size, use it.
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        [dic setObject:aFont forKey:NSFontAttributeName];
        s.height = MAX(s.height, ([aFont ascender] - [aFont descender]));
        s.width = MAX(s.width, [@"X" sizeWithAttributes:dic].width);

        [fse setSize:s];
        [fse setBaseline:b];
    }
    return fse;
}

@end
