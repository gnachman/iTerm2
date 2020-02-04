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
+ (void)it_performBlockWithCurrentAppearanceSetToAppearanceForCurrentTheme:(void (^)(void))block;

typedef NS_OPTIONS(NSUInteger, iTermAppearanceOptions) {
    iTermAppearanceOptionsDark = 1 << 0,
    iTermAppearanceOptionsHighContrast = 1 << 1,
    iTermAppearanceOptionsMinimal = 1 << 2
};

+ (iTermAppearanceOptions)it_appearanceOptions;
+ (BOOL)it_decorationsAreDarkWithTerminalBackgroundColorIsDark:(BOOL)darkBackground;

@end

NS_ASSUME_NONNULL_END
