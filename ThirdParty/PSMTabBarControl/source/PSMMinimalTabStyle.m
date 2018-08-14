//
//  PSMMinimalTabStyle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMMinimalTabStyle.h"

@implementation NSColor(PSMMinimalTabStyle)

- (NSColor *)psm_nonSelectedColor {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const CGFloat amount = 0.1;
    CGFloat delta = -amount;
    CGFloat proposed = color.it_hspBrightness + delta;
    if (proposed < 0 || proposed > 1) {
        delta = -delta;
    }
    return [NSColor colorWithSRGBRed:color.redComponent + delta
                               green:color.greenComponent + delta
                                blue:color.blueComponent + delta
                               alpha:1];
    
}

- (NSColor *)psm_highlightedColor:(double)weight {
    NSColor *color = [self colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    const CGFloat amount = 0.1;
    CGFloat delta = amount;
    CGFloat proposed = color.it_hspBrightness + delta;
    if (proposed < 0 || proposed > 1) {
        delta = -delta;
    }
    delta *= weight;
    return [NSColor colorWithSRGBRed:color.redComponent + delta
                               green:color.greenComponent + delta
                                blue:color.blueComponent + delta
                               alpha:1];
    
}

@end

@implementation PSMMinimalTabStyle

- (NSString *)name {
    return @"Minimal";
}

- (NSColor *)tabBarColor {
    return [self.delegate minimalTabStyleBackgroundColor] ?: [NSColor blackColor];
}

- (BOOL)backgroundIsDark {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    return (backgroundBrightness < 0.5);
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected {
    CGFloat backgroundBrightness = self.tabBarColor.it_hspBrightness;
    
    const CGFloat delta = selected ? 0.85 : 0.5;
    CGFloat value;
    if (backgroundBrightness < 0.5) {
        value = MIN(1, backgroundBrightness + delta);
    } else {
        value = MAX(0, backgroundBrightness - delta);
    }
    return [NSColor colorWithWhite:value alpha:1];
}

- (NSColor *)topLineColorSelected:(BOOL)selected {
    return self.tabBarColor;
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    return self.tabBarColor;
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    return [NSColor clearColor];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    NSColor *color;
    if (self.tabBar.cells.count > 1 && !selected) {
        color = [self.tabBarColor psm_nonSelectedColor];
    } else {
        color = self.tabBarColor;
    }
    if (selected || highlightAmount == 0) {
        return color;
    }
    color = [color psm_highlightedColor:highlightAmount];
    return color;
}

- (BOOL)useLightControls {
    return self.backgroundIsDark;
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

- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell {
}

@end
