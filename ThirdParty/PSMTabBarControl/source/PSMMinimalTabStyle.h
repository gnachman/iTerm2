//
//  PSMMinimalTabStyle.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/10/18.
//

#import "PSMYosemiteTabStyle.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSColor(PSMMinimalTabStyle)
- (NSColor *)psm_nonSelectedColorWithDifference:(double)difference;
@end

@protocol PSMMinimalTabStyleDelegate<NSObject>
// Nil when there is no color to use (PseudoTerminal has no current session
// while a window is set up); -tabBarColor then uses black.
- (nullable NSColor *)minimalTabStyleBackgroundColor;
@end

@interface PSMMinimalTabStyle : PSMYosemiteTabStyle
@property (nonatomic, weak) id<PSMMinimalTabStyleDelegate> delegate;

// The color used to stroke the outline around the selected tab.
- (NSColor *)outlineColor;

// The selected cell the bar shows, or nil when it's in the overflow menu or
// hidden (as by a tab bar search that it doesn't match).
- (nullable PSMTabBarCell *)selectedCellInTabBarControl:(PSMTabBarControl *)bar;

@end

NS_ASSUME_NONNULL_END
