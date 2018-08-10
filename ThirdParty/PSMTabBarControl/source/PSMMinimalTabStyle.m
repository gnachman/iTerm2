//
//  PSMMinimalTabStyle.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMMinimalTabStyle.h"

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
    if (!selected) {
        return self.tabBarColor;
    }
    
    return [NSColor colorWithSRGBRed:0.5
                               green:0.5
                                blue:0.5
                               alpha:0.25];
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    return [NSColor clearColor];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    return self.tabBarColor;
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
