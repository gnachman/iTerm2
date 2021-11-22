//
//  iTermTheme.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/18/19.
//

#import "iTermTheme.h"

#import "DebugLogging.h"
#import "iTermColorMap.h"
#import "iTermPreferences.h"
#import "NSAppearance+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSColor+iTerm.h"
#import "PSMMinimalTabStyle.h"
#import "PSMTabStyle.h"
#import "PSMDarkTabStyle.h"
#import "PSMLightHighContrastTabStyle.h"
#import "PSMDarkHighContrastTabStyle.h"
#import "PSMYosemiteTabStyle.h"

@implementation iTermTheme

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id<PSMTabStyle>)tabStyleWithDelegate:(id<PSMMinimalTabStyleDelegate>)delegate
                    effectiveAppearance:(NSAppearance *)effectiveAppearance {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle == TAB_STYLE_MINIMAL) {
        id<PSMTabStyle> style = [[PSMMinimalTabStyle alloc] init];
        [(PSMMinimalTabStyle *)style setDelegate:delegate];
        return style;
    }
    iTermPreferencesTabStyle tabStyle = preferredStyle;
    switch (preferredStyle) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            // 10.14 path
            tabStyle = [effectiveAppearance it_tabStyle:preferredStyle];
            break;

        case TAB_STYLE_LIGHT:
        case TAB_STYLE_DARK:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            // Use the stated style. it_tabStyle assumes you want a style based on the current
            // appearance but this is the one case where that is not true.
            // If there is only one tab and it has a dark tab color the style will be adjusted
            // later in the call to updateTabColors.
            break;
    }
    switch (tabStyle) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
        case TAB_STYLE_LIGHT:
            return [[PSMYosemiteTabStyle alloc] init];
        case TAB_STYLE_DARK:
            return [[PSMDarkTabStyle alloc] init];
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [[PSMLightHighContrastTabStyle alloc] init];
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [[PSMDarkHighContrastTabStyle alloc] init];
    }
    assert(NO);
    return nil;
}

- (BOOL)useMinimalStyle {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    return (preferredStyle == TAB_STYLE_MINIMAL);
}

- (NSColor *)backgroundColorForDecorativeSubviewsInSessionWithTabColor:(NSColor *)tabColor
                                                   effectiveAppearance:(NSAppearance *)effectiveAppearance
                                                sessionBackgroundColor:(NSColor *)sessionBackgroundColor
                                                      isFirstResponder:(BOOL)isFirstResponder
                                                           dimOnlyText:(BOOL)dimOnlyText
                                                 adjustedDimmingAmount:(CGFloat)adjustedDimmingAmount
                                                     transparencyAlpha:(CGFloat)transparencyAlpha {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (!tabColor) {
        return [self dimmedBackgroundColorWithAppearance:effectiveAppearance
                                  sessionBackgroundColor:sessionBackgroundColor
                                        isFirstResponder:isFirstResponder
                                             dimOnlyText:dimOnlyText
                                   adjustedDimmingAmount:adjustedDimmingAmount
                                       transparencyAlpha:transparencyAlpha];
    }
    NSColor *undimmedColor = tabColor;

    if (self.useMinimalStyle) {
        undimmedColor = sessionBackgroundColor;
    } else {
        undimmedColor = [self backgroundColorForDecorativeSubviewsForTabColor:undimmedColor
                                                                     tabStyle:[effectiveAppearance it_tabStyle:preferredStyle]
                                                       sessionBackgroundColor:sessionBackgroundColor];
    }
    if (isFirstResponder) {
        return undimmedColor;
    }
    return [undimmedColor it_colorByDimmingByAmount:0.3];
}

#pragma mark Status Bar Background Color

- (NSColor *)tabBarBackgroundColorForTabColor:(NSColor *)tabColor
                                        style:(id<PSMTabStyle>)tabStyle
                            transparencyAlpha:(CGFloat)transparencyAlpha {
    if (tabColor) {
        return tabColor;
    }
    if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
        // Note that here the alpha value is used regardless of whether a tab is selected because this is
        // used for the status bar's background color.
        return [[tabStyle backgroundColorSelected:YES highlightAmount:0] colorWithAlphaComponent:transparencyAlpha];
    } else {
        return [tabStyle backgroundColorSelected:YES highlightAmount:0];
    }
}

- (nullable NSColor *)statusBarContainerBackgroundColorForTabColor:(NSColor *)tabColor
                                               effectiveAppearance:(NSAppearance *)effectiveAppearance
                                                          tabStyle:(id<PSMTabStyle>)tabStyle
                                            sessionBackgroundColor:(NSColor *)sessionBackgroundColor
                                                  isFirstResponder:(BOOL)isFirstResponder
                                                       dimOnlyText:(BOOL)dimOnlyText
                                             adjustedDimmingAmount:(CGFloat)adjustedDimmingAmount
                                                 transparencyAlpha:(CGFloat)transparencyAlpha {
    if ([iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]) {
        return [self backgroundColorForDecorativeSubviewsInSessionWithTabColor:tabColor
                                                           effectiveAppearance:effectiveAppearance
                                                        sessionBackgroundColor:sessionBackgroundColor
                                                              isFirstResponder:isFirstResponder
                                                                   dimOnlyText:dimOnlyText
                                                         adjustedDimmingAmount:adjustedDimmingAmount
                                                             transparencyAlpha:transparencyAlpha];
    } else {
        return [self tabBarBackgroundColorForTabColor:tabColor
                                                style:tabStyle
                                    transparencyAlpha:transparencyAlpha];
    }
}

#pragma mark Status Bar Text Color

- (NSColor *)statusBarTextColorForEffectiveAppearance:(NSAppearance *)effectiveAppearance
                                             colorMap:(iTermColorMap *)colorMap
                                             tabStyle:(id<PSMTabStyle>)tabStyle
                                        mainAndActive:(BOOL)mainAndActive {
    if (self.useMinimalStyle) {
        NSColor *color = [self terminalWindowDecorationTextColorForBackgroundColor:nil
                                                               effectiveAppearance:effectiveAppearance
                                                                          tabStyle:tabStyle
                                                                     mainAndActive:mainAndActive];
        if (!color) {
            return nil;
        }
        return [colorMap colorByDimmingTextColor:[color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]];
    } else {
        return [NSColor labelColor];
    }
}

- (NSColor *)terminalWindowDecorationTextColorForBackgroundColor:(NSColor *)backgroundColor
                                             effectiveAppearance:(NSAppearance *)effectiveAppearance
                                                        tabStyle:(id<PSMTabStyle>)tabStyle
                                                   mainAndActive:(BOOL)mainAndActive {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (self.useMinimalStyle) {
        PSMMinimalTabStyle *minimalStyle = [PSMMinimalTabStyle castFrom:tabStyle];
        DLog(@"> begin Computing decoration color");
        return [minimalStyle textColorDefaultSelected:YES
                                      backgroundColor:backgroundColor
                           windowIsMainAndAppIsActive:mainAndActive];
        DLog(@"< end Computing decoration color");
    } else {
        CGFloat whiteLevel;
        switch ([effectiveAppearance it_tabStyle:preferredStyle]) {
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_COMPACT:
            case TAB_STYLE_MINIMAL:
                assert(NO);

            case TAB_STYLE_LIGHT:
                whiteLevel = 0.2;
                break;

            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                whiteLevel = 0;
                break;

            case TAB_STYLE_DARK:
                whiteLevel = 0.8;
                break;

            case TAB_STYLE_DARK_HIGH_CONTRAST:
                whiteLevel = 1;
                break;
        }
        return [NSColor colorWithCalibratedWhite:whiteLevel alpha:1];
    }
}

#pragma mark - Private

#pragma mark Session Decoration Background Color

- (NSColor *)backgroundColorForDecorativeSubviewsForTabColor:(NSColor *)tabColor
                                                    tabStyle:(iTermPreferencesTabStyle)tabStyle
                                      sessionBackgroundColor:(NSColor *)sessionBackgroundColor {
    if (self.useMinimalStyle) {
        return sessionBackgroundColor;
    }

    CGFloat hue = tabColor.hueComponent;
    CGFloat saturation = tabColor.saturationComponent;
    CGFloat brightness = tabColor.brightnessComponent;
    switch (tabStyle) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            break;

        case TAB_STYLE_LIGHT:
            return [NSColor colorWithCalibratedHue:hue
                                        saturation:saturation * .5
                                        brightness:MAX(0.7, brightness)
                                             alpha:1];
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSColor colorWithCalibratedHue:hue
                                        saturation:saturation * .25
                                        brightness:MAX(0.85, brightness)
                                             alpha:1];
        case TAB_STYLE_DARK:
            return [NSColor colorWithCalibratedHue:hue
                                        saturation:saturation * .75
                                        brightness:MIN(0.3, brightness)
                                             alpha:1];
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [NSColor colorWithCalibratedHue:hue
                                        saturation:saturation * .95
                                        brightness:MIN(0.15, brightness)
                                             alpha:1];
    }
    assert(NO);
    return tabColor;
}

- (NSColor *)dimmedBackgroundColorWithAppearance:(NSAppearance *)appearance
                          sessionBackgroundColor:(NSColor *)sessionBackgroundColor
                                isFirstResponder:(BOOL)isFirstResponder
                                     dimOnlyText:(BOOL)dimOnlyText
                           adjustedDimmingAmount:(CGFloat)adjustedDimmingAmount
                               transparencyAlpha:(CGFloat)transparencyAlpha {
    const BOOL inactive = !isFirstResponder;
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (self.useMinimalStyle) {
        NSColor *color = sessionBackgroundColor;
        if ([iTermPreferences boolForKey:kPreferenceKeyDimOnlyText]) {
            if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
                return [color colorWithAlphaComponent:transparencyAlpha];
            } else {
                return color;
            }
        }
        if (inactive && !dimOnlyText) {
            if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
                return [[color colorDimmedBy:adjustedDimmingAmount
                            towardsGrayLevel:0.5] colorWithAlphaComponent:transparencyAlpha];
            } else {
                return [color colorDimmedBy:adjustedDimmingAmount
                           towardsGrayLevel:0.5];
            }
        } else {
            if (PSMShouldExtendTransparencyIntoMinimalTabBar()) {
                return [color colorWithAlphaComponent:transparencyAlpha];
            } else {
                return color;
            }
        }
    }
    CGFloat whiteLevel = 0;
    switch ([appearance it_tabStyle:preferredStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
        case TAB_STYLE_LIGHT:
            if (inactive) {
                // Not selected
                whiteLevel = 0.58;
            } else {
                // selected
                whiteLevel = 0.70;
            }
            break;
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            if (inactive) {
                // Not selected
                whiteLevel = 0.68;
            } else {
                // selected
                whiteLevel = 0.80;
            }
            break;
        case TAB_STYLE_DARK:
            if (inactive) {
                // Not selected
                whiteLevel = 0.18;
            } else {
                // selected
                whiteLevel = 0.27;
            }
            break;
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            if (inactive) {
                // Not selected
                whiteLevel = 0.08;
            } else {
                // selected
                whiteLevel = 0.17;
            }
            break;
    }

    return [NSColor colorWithCalibratedWhite:whiteLevel alpha:1];
}


@end
