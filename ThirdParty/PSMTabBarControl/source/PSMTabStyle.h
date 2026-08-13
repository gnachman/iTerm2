//
//  PSMTabStyle.h
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

/* 
Protocol to be observed by all style delegate objects.  These objects handle the drawing responsibilities for PSMTabBarCell; once the control has been assigned a style, the background and cells draw consistent with that style.  Design pattern and implementation by David Smith, Seth Willits, and Chris Forsythe, all touch up and errors by John P. :-)
*/

#import "PSMTabBarCell.h"
#import "PSMTabBarControl.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PSMTabStyle <NSObject>

@property(nonatomic, weak, nullable) PSMTabBarControl *tabBar;
@property(nonatomic, readonly, nullable) NSAppearance *accessoryAppearance NS_AVAILABLE_MAC(10_14);
@property(nonatomic, readonly) CGFloat edgeDragHeight;
@property(nonatomic, readonly) BOOL supportsMultiLineLabels;
@property(nonatomic, readonly) CGFloat intercellSpacing;

// identity
- (NSString *)name;

// control specific parameters
- (float)leftMarginForTabBarControl;
- (float)rightMarginForTabBarControlWithOverflow:(BOOL)withOverflow
                                    addTabButton:(BOOL)withAddTabButton;
- (float)topMarginForTabBarControl;

// add tab button
- (nullable NSImage *)addTabButtonImage;
- (nullable NSImage *)addTabButtonPressedImage;
- (nullable NSImage *)addTabButtonRolloverImage;

// cell specific parameters
- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)orientation;
- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)indicatorRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)progressBarRectForTabCell:(PSMTabBarCell *)cell;
@optional
- (nullable NSBezierPath *)progressBarClipPathForTabCell:(PSMTabBarCell *)cell;
// YES if this style draws whole-run tab-group decoration itself (in
// -drawTabBar:), in which case the group chip CELL draws nothing. Styles that
// return NO keep the basic per-cell chip.
- (BOOL)usesExternalTabGroupDecoration;
// Width to reserve for the group chip cell (the name capsule plus the colored
// area between it and the first tab). Defaults to the basic chip width.
- (CGFloat)tabGroupChipCellWidthForName:(NSString *)name;
// Height to reserve for the group chip cell on a vertical bar (the name capsule
// plus the colored area between it and the first tab). Defaults to the basic
// vertical chip height.
- (CGFloat)tabGroupChipCellHeightForName:(NSString *)name;
// Draw the decoration for whole tab-group runs (the name capsule and the
// enclosing colored pill around the group's tabs) in -drawTabBar:, since the
// enclosing pill spans multiple cells.
- (void)drawTabGroupRunDecorationsForTabBar:(PSMTabBarControl *)bar clipRect:(NSRect)clipRect;
// How far the enclosing group-run pill extends past the tab cells it wraps.
// The scrollable-bar viewport clip stops at the last tab, so it must widen by
// this much or the last group's outline is clipped. Defaults to 0.
- (CGFloat)tabGroupRunOutset;
@required
- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell;
- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell;
- (float)desiredWidthOfTabCell:(PSMTabBarCell *)cell;

// cell values
- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell;
- (PSMCachedTitleInputs *)cachedTitleInputsForTabCell:(PSMTabBarCell *)cell;
- (nullable PSMCachedTitleInputs *)cachedSubtitleInputsForTabCell:(PSMTabBarCell *)cell;

// drawing
- (void)drawTabCell:(PSMTabBarCell *)cell highlightAmount:(CGFloat)highlightAmount;
- (void)drawBackgroundInRect:(NSRect)rect color:(nullable NSColor*)color horizontal:(BOOL)horizontal;
- (void)drawTabBar:(PSMTabBarControl *)bar
            inRect:(NSRect)rect
          clipRect:(NSRect)clipRect
        horizontal:(BOOL)horizontal
      withOverflow:(BOOL)withOverflow;

- (NSColor *)accessoryFillColor;
- (NSColor *)accessoryStrokeColor;
- (void)fillPath:(NSBezierPath*)path;
- (NSColor *)accessoryTextColor;

// Should light-tinted controls be used?
- (BOOL)useLightControls;

- (NSColor *)textColorDefaultSelected:(BOOL)selected
                      backgroundColor:(nullable NSColor *)backgroundColor
                   windowIsMainAndAppIsActive:(BOOL)mainAndActive;
- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount;
- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar;
- (NSColor *)textColorForCell:(PSMTabBarCell *)cell;
- (NSRect)adjustedCellRect:(NSRect)rect generic:(NSRect)generic;
- (NSRect)dirtyFrameForCell:(PSMTabBarCell *)cell;
- (NSRect)frameForAddTabButtonWithCellWidths:(nullable NSArray<NSNumber *> *)widths
                                      height:(CGFloat)height;
- (nullable PSMRolloverButton *)makeAddTabButtonWithFrame:(NSRect)frame;
- (NSRect)frameForOverflowButtonWithAddTabButton:(BOOL)showAddTabButton
                                   enclosureSize:(NSSize)enclosureSize
                                  standardHeight:(CGFloat)standardHeight;
- (NSButton *)makeOverflowButtonWithFrame:(NSRect)frame;

@property (nonatomic, readonly) NSSize addTabButtonSize;
@property (nonatomic, readonly) CGFloat tabBarHeight;
@property (nonatomic) PSMTabBarOrientation orientation;

@end

@interface PSMTabBarControl (StyleAccessors)

- (NSMutableArray *)cells;
- (void)sanityCheck:(NSString *)callsite;
- (void)sanityCheck:(NSString *)callsite force:(BOOL)force;

@end

NS_ASSUME_NONNULL_END
