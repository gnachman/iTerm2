//
//  NSColor+PSM.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/24/19.
//

#import "NSColor+PSM.h"

@implementation NSColor (PSM)

// http://www.nbdtech.com/Blog/archive/2008/04/27/Calculating-the-Perceived-Brightness-of-a-Color.aspx
// http://alienryderflex.com/hsp.html
- (NSColor *)it_srgbForColorInWindow:(NSWindow *)window {
    if ([self isEqual:window.backgroundColor]) {
        if ([window.effectiveAppearance.name isEqualToString:NSAppearanceNameVibrantDark]) {
            return [NSColor colorWithSRGBRed:0.25 green:0.25 blue:0.25 alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:0.75 green:0.75 blue:0.75 alpha:1];
        }
    } else {
        return [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    }
}

- (CGFloat)it_hspBrightness {
    NSColor *safeColor = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const CGFloat r = safeColor.redComponent;
    const CGFloat g = safeColor.greenComponent;
    const CGFloat b = safeColor.blueComponent;
    return sqrt(r * r * .241 +
                g * g * .691 +
                b * b * .068);
}

@end
