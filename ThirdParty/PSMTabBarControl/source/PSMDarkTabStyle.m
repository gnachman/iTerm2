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
    return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected
{
    const CGFloat lightness = selected ? 1.00 : 0.80;
    return [NSColor colorWithCalibratedWhite:lightness alpha:1.00];
}

- (NSColor *)topLineColorSelected:(BOOL)selected
{
    return [NSColor colorWithCalibratedWhite:0.10 alpha:1.00];
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected
{
    return [NSColor colorWithCalibratedWhite:0.00 alpha:1.00];
}

- (NSColor *)verticalLineColor
{
    return [NSColor colorWithCalibratedWhite:0.08 alpha:1.00];
}

- (NSGradient *)backgroundGradientSelected:(BOOL)selected
{
    CGFloat lightness = selected ? 0.24 : 0.12;
    NSColor *bg = [NSColor colorWithCalibratedWhite:lightness alpha:1.00];
    return [[[NSGradient alloc] initWithStartingColor:bg endingColor:bg] autorelease];
}

@end
