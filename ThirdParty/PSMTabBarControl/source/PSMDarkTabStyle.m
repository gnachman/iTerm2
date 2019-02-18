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

+ (NSColor *)tabBarColorWhenMainAndActive:(BOOL)keyMainAndActive {
    if (@available(macOS 10.14, *)) {
        return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0.25];
    } else {
        return [NSColor colorWithCalibratedWhite:0.12 alpha:1.00];
    }
}

- (NSColor *)tabBarColor {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    return [PSMDarkTabStyle tabBarColorWhenMainAndActive:keyMainAndActive];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected backgroundColor:(NSColor *)backgroundColor windowIsMainAndAppIsActive:(BOOL)windowIsMainAndAppIsActive {
    CGFloat value = selected ? 0.80 : 0.60;
    if (@available(macOS 10.14, *)) {
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        if (keyMainAndActive) {
            value = selected ? 1.0 : 0.65;
        } else {
            value = selected ? 0.45 : 0.37;
        }
    }
    return [NSColor colorWithCalibratedWhite:value alpha:1.00];
}

- (NSColor *)topLineColorSelected:(BOOL)selected {
    if (@available(macOS 10.14, *)) {
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        if (keyMainAndActive) {
            return [NSColor colorWithWhite:1 alpha:0.20];
        } else {
            return [NSColor colorWithWhite:1 alpha:0.16];
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
        const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
        if (keyMainAndActive) {
            if (selected) {
                return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0];
            } else {
                NSColor *color = [self.class tabBarColorWhenMainAndActive:YES];
                colors[0] = color.redComponent;
                colors[1] = color.greenComponent;
                colors[2] = color.blueComponent;
            }
        } else {
            if (selected) {
                return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0];
            } else {
                NSColor *color = [self.class tabBarColorWhenMainAndActive:NO];
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
    const BOOL mainAndActive = self.windowIsMainAndAppIsActive;
    return [self textColorDefaultSelected:YES backgroundColor:nil windowIsMainAndAppIsActive:mainAndActive];
}

- (NSEdgeInsets)insetsForTabBarDividers {
    return NSEdgeInsetsMake(0, 1, 0, 1);
}

- (NSEdgeInsets)backgroundInsetsWithHorizontalOrientation:(BOOL)horizontal {
    NSEdgeInsets insets = NSEdgeInsetsZero;
    if (@available(macOS 10.14, *)) {
        insets.top = 1;
        insets.bottom = 0;
        insets.left = 1;
        insets.right = 0;
    }
    if (!horizontal) {
        insets.left = 1;
        insets.top = 0;
        insets.right = 1;
    }
    return insets;
}

@end
