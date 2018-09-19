//
//  NSAppearance+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/18.
//

#import "NSAppearance+iTerm.h"
#import "DebugLogging.h"

@implementation NSAppearance (iTerm)

- (iTermPreferencesTabStyle)it_tabStyle:(iTermPreferencesTabStyle)tabStyle {
    if (tabStyle != TAB_STYLE_AUTOMATIC && tabStyle != TAB_STYLE_MINIMAL) {
        if (@available(macOS 10.14, *)) {
            return tabStyle;
        } else {
            const BOOL dark = [self.name isEqualToString:NSAppearanceNameVibrantDark];
            DLog(@"self.name=%@ dark=%@ tabStyle=%@", self.name, @(dark), @(tabStyle));
            switch (tabStyle) {
                case TAB_STYLE_LIGHT:
                    if (dark) {
                        return TAB_STYLE_DARK;
                    }
                    break;
                case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                    if (dark) {
                        return TAB_STYLE_DARK_HIGH_CONTRAST;
                    }
                    break;

                case TAB_STYLE_DARK:
                case TAB_STYLE_DARK_HIGH_CONTRAST:
                case TAB_STYLE_AUTOMATIC:
                case TAB_STYLE_MINIMAL:
                    break;
            }

            return tabStyle;
        }
    }
    if (@available(macOS 10.14, *)) {
        return [self it_mojaveTabStyle:tabStyle];
    }
    return TAB_STYLE_LIGHT;
}

- (iTermPreferencesTabStyle)it_mojaveTabStyle:(iTermPreferencesTabStyle)tabStyle NS_AVAILABLE_MAC(10_14) {
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
    
    DLog(@"Unexpected tab style %@", @(tabStyle));
    return TAB_STYLE_LIGHT;
}

@end
