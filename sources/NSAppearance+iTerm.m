//
//  NSAppearance+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/18.
//

#import "NSAppearance+iTerm.h"
#import "DebugLogging.h"

@implementation NSAppearance (iTerm)

- (BOOL)it_isDark {
    return [self.name isEqualToString:NSAppearanceNameVibrantDark];
}

- (iTermPreferencesTabStyle)it_tabStyle:(iTermPreferencesTabStyle)tabStyle {
    switch (tabStyle) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            if (@available(macOS 10.14, *)) {
                return [self it_mojaveTabStyle];
            }
            return TAB_STYLE_LIGHT;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            if (@available(macOS 10.14, *)) {
                return tabStyle;
            }
            if (self.it_isDark) {
                return TAB_STYLE_DARK;
            }
            return tabStyle;

        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return tabStyle;
    }
}

- (iTermPreferencesTabStyle)it_mojaveTabStyle NS_AVAILABLE_MAC(10_14) {
    NSString *name = [self bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua,
                                                                NSAppearanceNameDarkAqua,
                                                                NSAppearanceNameAccessibilityHighContrastAqua,
                                                                NSAppearanceNameAccessibilityHighContrastDarkAqua ] ];
    if ([name isEqualToString:NSAppearanceNameDarkAqua]) {
        return TAB_STYLE_DARK;
    }
    if ([name isEqualToString:NSAppearanceNameAqua]) {
        return TAB_STYLE_LIGHT;
    }
    if ([name isEqualToString:NSAppearanceNameAccessibilityHighContrastDarkAqua]) {
        return TAB_STYLE_DARK_HIGH_CONTRAST;
    }
    if ([name isEqualToString:NSAppearanceNameAccessibilityHighContrastAqua]) {
        return TAB_STYLE_LIGHT_HIGH_CONTRAST;
    }
    
    DLog(@"Unexpected tab style %@", name);
    return TAB_STYLE_LIGHT;
}

@end
