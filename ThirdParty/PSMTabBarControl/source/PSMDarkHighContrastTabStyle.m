//
//  PSMDarkHighContrastTabStyle.m
//  iTerm2
//
//  Created by George Nachman on 3/25/16.
//
//

#import "PSMDarkHighContrastTabStyle.h"

@implementation PSMDarkHighContrastTabStyle


- (NSString *)name {
  return @"Dark High Contrast";
}

- (BOOL)highVisibility {
    return [[self.tabBar.delegate tabView:self.tabBar valueOfOption:PSMTabBarControlOptionHighVisibility] boolValue];
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected backgroundColor:(NSColor *)backgroundColor windowIsMainAndAppIsActive:(BOOL)mainAndActive {
    if ([self highVisibility]) {
        return selected ? [NSColor blackColor] : [NSColor whiteColor];
    } else {
        return [NSColor whiteColor];
    }
}

- (NSColor *)accessoryTextColor {
  return [NSColor whiteColor];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    CGFloat value;
    if ([self highVisibility]) {
        value = selected ? 0.80 : 0.03;
    } else {
        BOOL shouldBeLight;
        shouldBeLight = selected;
        value = shouldBeLight ? 0.2 : 0.03;
    }
    if (selected) {
        value += highlightAmount * 0.05;
    }
    return [NSColor colorWithCalibratedWhite:value alpha:1.00];
}

- (CGFloat)fontSize {
    return 12.0;
}

@end
