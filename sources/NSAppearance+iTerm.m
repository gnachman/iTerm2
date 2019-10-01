//
//  NSAppearance+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/18.
//

#import "NSAppearance+iTerm.h"
#import "DebugLogging.h"
#import "iTermPreferences.h"

@implementation NSAppearance (iTerm)

- (BOOL)it_isDark {
    if (@available(macOS 10.14, *)) {
        NSAppearanceName bestMatch = [self bestMatchFromAppearancesWithNames:@[ NSAppearanceNameDarkAqua,
                                                                                NSAppearanceNameVibrantDark,
                                                                                NSAppearanceNameAqua,
                                                                                NSAppearanceNameVibrantLight ]];
        if ([bestMatch isEqualToString:NSAppearanceNameDarkAqua] ||
            [bestMatch isEqualToString:NSAppearanceNameVibrantDark]) {
            return YES;
        }
        return NO;
    }

    // 10.13 or older
    return [self.name isEqualToString:NSAppearanceNameVibrantDark];
}

+ (instancetype)it_appearanceForCurrentTheme {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            return NSAppearance.currentAppearance;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSAppearance appearanceNamed:NSAppearanceNameAqua];

        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            if (@available(macOS 10.14, *)) {
                return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            } else {
                return [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
            }
    }
}

+ (void)it_performBlockWithCurrentAppearanceSetToAppearanceForCurrentTheme:(void (^)(void))block {
    NSAppearance *saved = [self currentAppearance];
    [NSAppearance setCurrentAppearance:[self it_appearanceForCurrentTheme]];
    block();
    [NSAppearance setCurrentAppearance:saved];
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
