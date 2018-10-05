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
    CGFloat value = selected ? 0.80 : 0.60;
    if (@available(macOS 10.14, *)) {
        if (self.tabBar.window.isKeyWindow && [NSApp isActive]) {
            value = selected ? 1.0 : 0.65;
        } else {
            value = selected ? 0.45 : 0.37;
        }
    }
    return [NSColor colorWithCalibratedWhite:value alpha:1.00];
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
