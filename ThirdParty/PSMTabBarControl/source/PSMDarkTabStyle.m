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

+ (NSColor *)tabBarColorWhenKeyAndActive:(BOOL)keyAndActive {
    if (@available(macOS 10.14, *)) {
        return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0.25];
    } else {
        return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
    }
}

- (NSColor *)tabBarColor {
    return [PSMDarkTabStyle tabBarColorWhenKeyAndActive:self.tabBar.window.isKeyWindow && [NSApp isActive]];
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
    if (@available(macOS 10.14, *)) {
        if (self.tabBar.window.isKeyWindow && [NSApp isActive]) {
            return [NSColor colorWithSRGBRed:97.0 / 255.0
                                       green:110.0 / 255.0
                                        blue:113 / 255.0
                                       alpha:1];
        } else {
            return [NSColor colorWithSRGBRed:74.0 / 255.0
                                       green:88.0 / 255.0
                                        blue:91.0 / 255.0
                                       alpha:1];
        }
    } else {
        return [NSColor colorWithCalibratedWhite:0.10 alpha:1.00];
    }
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    if (@available(macOS 10.14, *)) {
        return [NSColor colorWithWhite:0 alpha:0.1];
    } else {
        return [NSColor colorWithCalibratedWhite:0.00 alpha:1.00];
    }
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    if (@available(macOS 10.14, *)) {
        return [self topLineColorSelected:selected];
    } else {
        return [NSColor colorWithCalibratedWhite:0.08 alpha:1.00];
    }
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    if (@available(macOS 10.14, *)) {
        CGFloat colors[3];
        if (self.tabBar.window.isKeyWindow && [NSApp isActive]) {
            if (selected) {
                return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0];
            } else {
                NSColor *color = [self.class tabBarColorWhenKeyAndActive:YES];
                colors[0] = color.redComponent;
                colors[1] = color.greenComponent;
                colors[2] = color.blueComponent;
            }
        } else {
            if (selected) {
                return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0];
            } else {
                NSColor *color = [self.class tabBarColorWhenKeyAndActive:NO];
                colors[0] = color.redComponent;
                colors[1] = color.greenComponent;
                colors[2] = color.blueComponent;
            }
        }
        CGFloat highlightedColors[3] = { 1.0, 1.0, 1.0 };
        CGFloat a = 0;
        if (!selected) {
            a = highlightAmount * 0.05;
        }
        for (int i = 0; i < 3; i++) {
            colors[i] = colors[i] * (1.0 - a) + highlightedColors[i] * a;
        }

        return [NSColor colorWithSRGBRed:colors[0]
                                   green:colors[1]
                                    blue:colors[2]
                                   alpha:0.25];
    } else {
        CGFloat value = selected ? 0.25 : 0.13;
        if (!selected) {
            value += highlightAmount * 0.05;
        }
        return [NSColor colorWithCalibratedWhite:value alpha:1.00];
    }
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
