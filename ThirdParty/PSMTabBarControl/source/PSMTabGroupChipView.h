//
//  PSMTabGroupChipView.h
//  PSMTabBarControl
//
//  The little name+color "chip" drawn at the leading edge of a contiguous
//  run of tabs that share a tab group (Chrome/Firefox style). The control
//  owns and positions these as subviews so they track tab-bar scrolling
//  for free. Appearance is delegated to the current tab style so each
//  theme (Tahoe, Yosemite, Minimal, ...) can render it differently; a
//  basic built-in look is used when the style doesn't override.
//

#import <Cocoa/Cocoa.h>

@class PSMTabBarControl;

NS_ASSUME_NONNULL_BEGIN

@interface PSMTabGroupChipView : NSView

@property(nonatomic, copy) NSString *groupName;
@property(nonatomic, retain) NSColor *groupColor;
// True when the run this chip heads contains the selected tab; styles may
// use it to emphasize the active group.
@property(nonatomic, assign) BOOL selected;
// The control whose style draws the chip. Weak: the control owns the chip.
@property(nonatomic, weak, nullable) PSMTabBarControl *tabBarControl;

// Width this chip wants at the tab bar's height, so the control can
// reserve a leading gap for it before the run's first cell.
- (CGFloat)preferredWidth;

// Same width computed from a name alone, so the tab bar can reserve the
// gap during layout before the chip subview exists.
+ (CGFloat)preferredWidthForName:(NSString *)name;

// Height reserved above a vertical bar's run for its chip.
+ (CGFloat)verticalChipHeight;

// Draw the basic chip (rounded pill + name) into `frame`. Shared by the
// (legacy) overlay view and the first-class chip cell.
+ (void)drawChipInFrame:(NSRect)frame name:(NSString *)name color:(NSColor *)color;

@end

NS_ASSUME_NONNULL_END
