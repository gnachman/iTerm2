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

+ (NSColor *)tabBarColor {
    return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
}

- (NSColor *)tabBarColor {
    return [PSMDarkTabStyle tabBarColor];
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

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    return [NSColor colorWithCalibratedWhite:0.08 alpha:1.00];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    CGFloat value = selected ? 0.25 : 0.13;
    if (!selected) {
        value += highlightAmount * 0.05;
    }
    return [NSColor colorWithCalibratedWhite:value alpha:1.00];
}

- (BOOL)useLightControls {
    return YES;
}

- (NSColor *)accessoryFillColor {
    return [NSColor colorWithCalibratedWhite:0.27 alpha:1.00];
}

- (NSColor *)accessoryStrokeColor {
    return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
}

- (NSColor *)accessoryTextColor {
    return [self textColorDefaultSelected:YES];
}

@end
