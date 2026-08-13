//
//  PSMTabGroupChipView.h
//  PSMTabBarControl
//
//  Metrics and basic drawing for the name+color "chip" that heads a
//  contiguous run of tabs sharing a tab group (Chrome/Firefox style).
//  Despite the historical name this is not a view: chips are first-class
//  cells (PSMTabBarCell with isTabGroupChip) and these class helpers supply
//  their size and default look. Styles that draw their own run decoration
//  (e.g. Tahoe) bypass the basic look entirely.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PSMTabGroupChipView : NSObject

// Width a horizontal chip cell wants for `name`, so the tab bar can size the
// cell during layout.
+ (CGFloat)preferredWidthForName:(NSString *)name;

// Height reserved for a vertical bar's chip cell.
+ (CGFloat)verticalChipHeight;

// Draw the basic chip (rounded pill + name) into `frame`. Used by
// PSMTabBarCell for styles without their own run decoration.
+ (void)drawChipInFrame:(NSRect)frame name:(NSString *)name color:(nullable NSColor *)color;

@end

NS_ASSUME_NONNULL_END
