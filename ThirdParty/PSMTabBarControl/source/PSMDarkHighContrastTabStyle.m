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

- (NSColor *)textColorDefaultSelected:(BOOL)selected backgroundColor:(NSColor *)backgroundColor windowIsMainAndAppIsActive:(BOOL)mainAndActive {
    return [NSColor whiteColor];
}

- (NSColor *)accessoryTextColor {
  return [NSColor whiteColor];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
    BOOL shouldBeLight;
    if (@available(macOS 10.14, *)) {
        shouldBeLight = selected;
    } else {
        shouldBeLight = !selected;
    }
    CGFloat value = shouldBeLight ? 0.2 : 0.03;
    if (selected) {
        value += highlightAmount * 0.05;
    }
    return [NSColor colorWithCalibratedWhite:value alpha:1.00];
}

- (CGFloat)fontSize {
    return 12.0;
}

@end
