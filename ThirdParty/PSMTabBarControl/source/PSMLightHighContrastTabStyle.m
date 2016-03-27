//
//  PSMLightHighContrastTabStyle.m
//  iTerm2
//
//  Created by George Nachman on 3/25/16.
//
//

#import "PSMLightHighContrastTabStyle.h"
#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"

@implementation PSMLightHighContrastTabStyle

- (NSString *)name {
  return @"Light High Contrast";
}

- (NSColor *)textColorDefaultSelected:(BOOL)selected {
  return [NSColor blackColor];
}

- (NSColor *)accessoryTextColor {
  return [NSColor blackColor];
}

- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount {
  if (selected) {
    if (self.tabBar.window.backgroundColor) {
      return self.tabBar.window.backgroundColor;
    } else {
      return [NSColor windowBackgroundColor];
    }
  } else {
    if ([self isYosemiteOrLater]) {
      CGFloat value = 200 / 255.0 - highlightAmount * 0.1;
      return [NSColor colorWithSRGBRed:value green:value blue:value alpha:1];
    } else {
      // 10.9 and earlier needs a darker color to look good
      CGFloat value = 0.6 - highlightAmount * 0.1;
      return [NSColor colorWithSRGBRed:value green:value blue:value alpha:1];
    }
  }
}

- (CGFloat)fontSize {
  return 12.0;
}

@end
