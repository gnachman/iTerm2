//
//  iTermTheme.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/18/19.
//

#import <Cocoa/Cocoa.h>

#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermColorMap;
@protocol PSMMinimalTabStyleDelegate;
@protocol PSMTabStyle;

// Various colors are rather complex to calculate and are needed in distant
// places. This class provides a simple interface for computing colors and
// other theme-related values.
@interface iTermTheme : NSObject

+ (instancetype)sharedInstance;

// Creates a new tab style for the current global prefs.
- (id<PSMTabStyle>)tabStyleWithDelegate:(id<PSMMinimalTabStyleDelegate>)delegate
                    effectiveAppearance:(NSAppearance *)effectiveAppearance;

// Returns the color for decorative text (e.g., per-pane title bar, default
// status bar text color in minimal theme)
- (NSColor *)terminalWindowDecorationTextColorForBackgroundColor:(nullable NSColor *)backgroundColor
                                             effectiveAppearance:(NSAppearance *)effectiveAppearance
                                                        tabStyle:(id<PSMTabStyle>)tabStyle
                                                   mainAndActive:(BOOL)mainAndActive;

// Returns the background color for decorative views (e.g., per-pane title bar,
// default status bar background)
- (NSColor *)backgroundColorForDecorativeSubviewsInSessionWithTabColor:(NSColor *)tabColor
                                                   effectiveAppearance:(NSAppearance *)effectiveAppearance
                                                sessionBackgroundColor:(NSColor *)sessionBackgroundColor
                                                      isFirstResponder:(BOOL)isFirstResponder
                                                           dimOnlyText:(BOOL)dimOnlyText
                                                 adjustedDimmingAmount:(CGFloat)adjustedDimmingAmount;

// Background color for fake title bar in minimal, shared status bar.
- (NSColor *)tabBarBackgroundColorForTabColor:(NSColor *)tabColor
                                        style:(id<PSMTabStyle>)tabStyle;

// Default background color for status bar. Accounts for shared vs non-shared.
- (nullable NSColor *)statusBarContainerBackgroundColorForTabColor:(NSColor *)tabColor
                                               effectiveAppearance:(NSAppearance *)effectiveAppearance
                                                          tabStyle:(id<PSMTabStyle>)tabStyle
                                            sessionBackgroundColor:(NSColor *)sessionBackgroundColor
                                                  isFirstResponder:(BOOL)isFirstResponder
                                                       dimOnlyText:(BOOL)dimOnlyText
                                             adjustedDimmingAmount:(CGFloat)adjustedDimmingAmount;


// Default text color for status bar.
- (nullable NSColor *)statusBarTextColorForEffectiveAppearance:(NSAppearance *)effectiveAppearance
                                                      colorMap:(iTermColorMap *)colorMap
                                                      tabStyle:(id<PSMTabStyle>)tabStyle
                                                 mainAndActive:(BOOL)mainAndActive;

@end

NS_ASSUME_NONNULL_END
