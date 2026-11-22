//
//  NSAppearance+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermPreferences.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSAppearance (iTerm)

@property (nonatomic, readonly) BOOL it_isDark;
+ (BOOL)it_systemThemeIsDark;

// Converts a tab style if automatic.
- (iTermPreferencesTabStyle)it_tabStyle:(iTermPreferencesTabStyle)tabStyle;
+ (instancetype)it_appearanceForCurrentTheme;
// The appearance a window should be given so it matches a session with this
// background color. Returns nil when the window should inherit NSApp's
// appearance, which already follows the theme (see -[iTermApplication
// updateAppearance]); only the Minimal theme with a known background color
// needs an override.
+ (nullable instancetype)it_appearanceForSessionBackgroundColor:(nullable NSColor *)backgroundColor;
+ (void)it_performBlockWithCurrentAppearanceSetToAppearanceForCurrentTheme:(void (^)(void))block;
- (void)it_performAsCurrentDrawingAppearance:(void (^NS_NOESCAPE)(void))block;

typedef NS_OPTIONS(NSUInteger, iTermAppearanceOptions) {
    iTermAppearanceOptionsDark = 1 << 0,
    iTermAppearanceOptionsHighContrast = 1 << 1,
    iTermAppearanceOptionsMinimal = 1 << 2
};

+ (iTermAppearanceOptions)it_appearanceOptions;
+ (BOOL)it_decorationsAreDarkWithTerminalBackgroundColorIsDark:(BOOL)darkBackground;

@end

NS_ASSUME_NONNULL_END
