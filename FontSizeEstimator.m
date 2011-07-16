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

static const double kBrightnessThreshold = 0.95;

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
    // TODO: sometimes ctx is null but I haven't caught it yet.
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    assert(ctx);
    CGContextSetShouldAntialias(ctx, NO);
    
    NSSize osSize = [self osEstimate:aFont];
    NSSize estimate = osSize;
    estimate.width *= 4;
    estimate.height *= 4;
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(estimate.width, estimate.height)] autorelease];
    [image lockFocus];
    
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, estimate.width, estimate.height));
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           aFont, NSFontAttributeName,
                           [NSColor blackColor], NSForegroundColorAttributeName,
                           nil];
    
    NSAttributedString *str = [[NSAttributedString alloc] initWithString:s
                                                              attributes:attrs];
    [str drawWithRect:NSMakeRect(0,
                                 osSize.height * 2,
                                 osSize.width * 2,
                                 osSize.height * 2)
              options:0];
    [image unlockFocus];
        
    return image;
}

+ (double)xBoundOfImage:(NSImage *)i startingAt:(int)startAt dir:(int)dir
{
    int maxX = [i size].width;
    int maxY = [i size].height;
    int x;
    [i lockFocus];
    for (x = startAt; x >= 0 && x < maxX; x += dir) {
        for (int y = 0; y < maxY; y++) {
            NSColor *c = NSReadPixel(NSMakePoint(x, maxY - y - 1));
            if (Brightness(c) < kBrightnessThreshold) {
                [i unlockFocus];
                return x;
            }
        }
    }
    [i unlockFocus];
    return x;
}

+ (double)yBoundOfImage:(NSImage *)i startingAt:(int)startAt dir:(int)dir
{
    int maxX = [i size].width;
    int maxY = [i size].height;
    int y;
    [i lockFocus];
    for (y = startAt; y >= 0 && y < maxY; y += dir) {
        for (int x = 0; x < maxX; x++) {
            NSColor *c = NSReadPixel(NSMakePoint(x, maxY - y - 1));
            if (Brightness(c) < kBrightnessThreshold) {
                [i unlockFocus];
                return y;
            }
        }
    }
    [i unlockFocus];
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
            if (Brightness(c) < kBrightnessThreshold) {
                temp[x] = '#';
            } else {
                temp[x] = ' ';
            }
        }
        int n = [i size].height - 1 - y;
        NSLog(@"%04d %@", n, [NSString stringWithCharacters:temp length:x]);
    }
    [i unlockFocus];
}

- (NSRect)boundsOfImage:(NSImage *)i
{    
    // [FontSizeEstimator dumpImage:i];
    NSRect result = NSZeroRect;
    result.origin.x = [FontSizeEstimator xBoundOfImage:i startingAt:0 dir:1];
    result.size.width = [FontSizeEstimator xBoundOfImage:i startingAt:[i size].width-1 dir:-1] - result.origin.x + 1;
    result.origin.y = [FontSizeEstimator yBoundOfImage:i startingAt:0 dir:1];
    result.size.height = [FontSizeEstimator yBoundOfImage:i startingAt:[i size].height-1 dir:-1] - result.origin.y + 1;
    return result;
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
        NSRect capXBounds = [fse boundsOfImage:capXImage];
        
        NSImage *lowXImage = [fse imageForString:@"x" withFont:aFont];
        NSRect lowXBounds = [fse boundsOfImage:lowXImage];
        
        NSImage *lowYImage = [fse imageForString:@"y" withFont:aFont];
        NSRect lowYBounds = [fse boundsOfImage:lowYImage];
        
        NSSize s;
        double b;
        double capXMaxX = capXBounds.origin.x + capXBounds.size.width;
        double lowXMaxX = lowXBounds.origin.x + lowXBounds.size.width;
        s.width = MAX(capXMaxX, lowXMaxX);
        s.height = lowYBounds.origin.y + lowYBounds.size.height - capXBounds.origin.y;
        double lowYMaxY = lowYBounds.origin.y + lowYBounds.size.height;
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
