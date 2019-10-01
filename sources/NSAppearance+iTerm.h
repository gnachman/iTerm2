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

// Converts a tab style if automatic.
- (iTermPreferencesTabStyle)it_tabStyle:(iTermPreferencesTabStyle)tabStyle;
+ (instancetype)it_appearanceForCurrentTheme;
+ (void)it_performBlockWithCurrentAppearanceSetToAppearanceForCurrentTheme:(void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
