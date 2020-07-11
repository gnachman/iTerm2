//
//  iTermGraphicsUtilities.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/10/20.
//

#import "iTermGraphicsUtilities.h"
#import "FutureMethods.h"

extern void CGContextSetFontSmoothingStyle(CGContextRef, int);
extern int CGContextGetFontSmoothingStyle(CGContextRef);

int iTermSetSmoothing(CGContextRef ctx,
                      int *savedFontSmoothingStyle,
                      BOOL useThinStrokes,
                      BOOL antialiased) {
    if (!antialiased) {
        // Issue 7394.
        CGContextSetShouldSmoothFonts(ctx, YES);
        return -1;
    }
    BOOL shouldSmooth = useThinStrokes;
    int style = -1;
    if (iTermTextIsMonochrome()) {
        if (useThinStrokes) {
            shouldSmooth = NO;
        } else {
            shouldSmooth = YES;
        }
    } else {
        // User enabled subpixel AA
        shouldSmooth = YES;
    }
    if (shouldSmooth) {
        if (useThinStrokes) {
            style = 16;
        } else {
            style = 0;
        }
    }
    CGContextSetShouldSmoothFonts(ctx, shouldSmooth);
    if (style >= 0) {
        // This seems to be available at least on 10.8 and later. The only reference to it is in
        // WebKit. This causes text to render just a little lighter, which looks nicer.
        // It does not work in Mojave without subpixel AA.
        if (savedFontSmoothingStyle) {
            *savedFontSmoothingStyle = CGContextGetFontSmoothingStyle(ctx);
        }
        CGContextSetFontSmoothingStyle(ctx, style);
    }
    return style;
}

