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

- (NSString *)name
{
    return @"Dark";
}

- (NSColor *)tabBarColor
{
    return [NSColor colorWithCalibratedWhite:0.20 alpha:1.00];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected
{
    const CGFloat lightness = selected ? 1.00 : 0.80;
    return [NSColor colorWithCalibratedWhite:lightness alpha:1.00];
}

- (NSColor *)topLineColorSelected:(BOOL)selected
{
    const CGFloat lightness = selected ? 0.00 : 0.20;
    return [NSColor colorWithCalibratedWhite:lightness alpha:1.00];
}

- (NSColor *)verticalLineColor
{
    return [NSColor colorWithCalibratedWhite:0.20 alpha:1.00];
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected
{
    const CGFloat lightness = selected ? 0.00 : 0.20;
    return [NSColor colorWithCalibratedWhite:lightness alpha:1.00];
}

- (NSGradient *)backgroundGradientSelected:(BOOL)selected
{
    CGFloat lightness = selected ? 0.30 : 0.20;
    NSColor *bg = [NSColor colorWithCalibratedWhite:lightness alpha:1];
    return [[[NSGradient alloc] initWithStartingColor:bg endingColor:bg] autorelease];
}

@end
