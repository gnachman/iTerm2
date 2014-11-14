//
//  PSMDarkTabStyle.m
//  iTerm
//
//  Created by Brian Mock on 10/28/14.
//
//

#import "PSMDarkTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"

@implementation PSMDarkTabStyle

- (NSString *)name {
    return @"Dark";
}

- (NSColor *)tabBarColor {
    return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected {
    const CGFloat lightness = selected ? 0.80 : 0.60;
    return [NSColor colorWithCalibratedWhite:lightness alpha:1.00];
}

- (NSColor *)topLineColorSelected:(BOOL)selected {
    return [NSColor colorWithCalibratedWhite:0.10 alpha:1.00];
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    return [NSColor colorWithCalibratedWhite:0.00 alpha:1.00];
}

- (NSColor *)verticalLineColor {
    return [NSColor colorWithCalibratedWhite:0.08 alpha:1.00];
}

- (NSGradient *)backgroundGradientSelected:(BOOL)selected {
    CGFloat startValue;
    CGFloat endValue;
    if (selected) {
        startValue = 0.27;
        endValue = 0.24;
    } else {
        startValue = 0.14;
        endValue = 0.12;
    }
    NSColor *startColor = [NSColor colorWithCalibratedWhite:startValue alpha:1.00];
    NSColor *endColor = [NSColor colorWithCalibratedWhite:endValue alpha:1.00];
    return [[[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor] autorelease];
}

@end
