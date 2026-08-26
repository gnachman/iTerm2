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
    return [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0.25];
}

- (NSColor *)tabBarColor {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    return [PSMDarkTabStyle tabBarColorWhenMainAndActive:keyMainAndActive];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected backgroundColor:(NSColor *)backgroundColor windowIsMainAndAppIsActive:(BOOL)windowIsMainAndAppIsActive {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    CGFloat value;
    if (keyMainAndActive) {
        value = selected ? 1.0 : 0.65;
    } else {
        value = selected ? 0.45 : 0.37;
    }
    return [NSColor colorWithCalibratedWhite:value alpha:1.00];
}

- (NSColor *)topLineColorSelected:(BOOL)selected {
    if (!selected) {
        return [NSColor blackColor];
    }
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (keyMainAndActive) {
        return [NSColor colorWithWhite:1 alpha:0.20];
    } else {
        return [NSColor colorWithWhite:1 alpha:0.16];
    }
}

- (NSColor *)bottomLineColorSelected:(BOOL)selected {
    const BOOL attachedToTitleBar = [[self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionAttachedToTitleBar] boolValue];
    if (!attachedToTitleBar || self.tabBar.tabLocation != PSMTab_TopTab) {
        NSColor *color = [self topLineColorSelected:NO];
        return [color colorWithAlphaComponent:color.alphaComponent * 0.3];
    }
    return [NSColor colorWithWhite:0 alpha:0.1];
}

- (NSColor *)verticalLineColorSelected:(BOOL)selected {
    const BOOL keyMainAndActive = self.windowIsMainAndAppIsActive;
    if (keyMainAndActive) {
        return [NSColor colorWithWhite:1 alpha:0.18];
    } else {
        return [NSColor colorWithWhite:1 alpha:0.15];
    }
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    return [self bigSurBackgroundColorSelected:selected highlightAmount:highlightAmount];
}

- (NSColor *)bigSurBackgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    if (selected) {
        return [NSColor clearColor];
    }
    CGFloat base = [[self.tabBar.delegate tabView:self.tabBar
                                    valueOfOption:PSMTabBarControlOptionDarkModeInactiveTabDarkness] doubleValue];
    return [NSColor colorWithWhite:0 alpha:base - (highlightAmount * 0.3)];
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
    if (!horizontal) {
        insets.left = 1;
        insets.top = 0;
        insets.right = 1;
    }
    return insets;
}

- (void)drawTabBar:(PSMTabBarControl *)bar
            inRect:(NSRect)rect
          clipRect:(NSRect)clipRect
        horizontal:(BOOL)horizontal
      withOverflow:(BOOL)withOverflow {
    [super drawTabBar:bar inRect:rect clipRect:clipRect horizontal:horizontal withOverflow:withOverflow];
    // Draw shadow at bottom of tabbar.
    NSGradient *gradient =
    [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0 alpha:1]
                                  endingColor:[NSColor colorWithWhite:0 alpha:0.75]];
    const CGFloat height = 1;
    [gradient drawInRect:NSMakeRect(0, bar.bounds.size.height - height, bar.bounds.size.width, height)
                   angle:90];
}

@end
