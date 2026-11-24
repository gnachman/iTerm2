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
@property(nonatomic, readonly, nullable) NSAppearance *accessoryAppearance;
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
// The path to stroke, `lineWidth` wide, to mark the tab a tab switcher has highlighted. It should
// follow the shape this style gives tabs and stay inside the cell. Without it the bar strokes the
// cell's rectangle.
- (nullable NSBezierPath *)previewOutlinePathForTabCell:(PSMTabBarCell *)cell lineWidth:(CGFloat)lineWidth;
// The shape per-cell accessory subviews (the progress bar, the activity indicator) must stay inside,
// in the bar's coordinates, or nil if there is none. They draw on top of -drawRect: and so never see
// the graphics clip this style sets for cells; the bar masks them to this instead. Note this is the
// accessory's clip, not the cell's: an accessory may be outset past its cell on purpose.
- (nullable NSBezierPath *)accessoryClipPathForTabBar:(PSMTabBarControl *)bar;
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
// How far the group pill for `chip` extends past the LEFT (leading) edge of the
// chip. Unlike -tabGroupRunOutset (a constant), this is 0 when the preceding
// cell already covers the shared inter-group gap. Used to size a group's drag
// image so its outline is captured without grabbing the neighbor group's outline.
// Defaults to 0.
- (CGFloat)tabGroupChipLeftOutsetForChip:(PSMTabBarCell *)chip bar:(PSMTabBarControl *)bar;
// Width to reserve for a COLLAPSED group's chip cell: the name capsule plus a
// member-count badge and a collapse chevron (a collapsed run has no visible
// member tabs, so the chip is the whole affordance). Defaults to the expanded
// name-only chip width when unimplemented. `nested` is YES for a sub-group's
// chip, which a style may draw inset inside its parent's outline.
- (CGFloat)tabGroupCollapsedChipCellWidthForName:(NSString *)name
                                     memberCount:(NSInteger)count
                                          nested:(BOOL)nested;
// Width a collapsed group's chip needs to show these rich content lines (see
// -[PSMTabBarControl richLinesForTabGroupIdentifier:]), padding included.
- (CGFloat)tabGroupCollapsedChipWidthForRichLines:(NSArray<PSMTabRichLine *> *)lines;
// Height a collapsed group's chip needs on a vertical bar to show these lines
// below its name, where headerHeight is an expanded group's header height.
- (CGFloat)tabGroupCollapsedChipHeightForRichLines:(NSArray<PSMTabRichLine *> *)lines
                                      headerHeight:(CGFloat)headerHeight;
// Whether a collapsed group's chip shows its members' rich content lines and
// so is sized like a tab. YES if not implemented.
- (BOOL)showsRichContentOnCollapsedTabGroupChips;
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

@optional
// Fills part of a section heading or the strip beside its indented tabs, for
// a style whose bar background doesn't match its unselected tabs. Leave it
// unimplemented to show the bar's background.
- (void)drawSectionBackgroundInRect:(NSRect)rect;
// Whether the guide line beside a section's tabs marks the selected one. NO
// for a style whose selected tab already stands out. YES if unimplemented.
- (BOOL)sectionGuideMarksSelectedTab;
// Room between the guide line beside a section's tabs and the tabs, for a
// style whose tabs would cover a line at their edge. 0 if unimplemented.
- (CGFloat)sectionGuideGap;
// The normal height of a group header row in a vertical bar, for styles whose
// tabBarHeight doesn't give it. Rows made taller for rich tab content don't
// make the header taller.
@property (nonatomic, readonly) CGFloat verticalTabGroupHeaderHeight;

// The point size the style draws tab titles at.
@property (nonatomic, readonly) CGFloat fontSize;

// How much of a tab's height the style spends on chrome, such as a background
// inset from the cell, beyond what rich tab content lines and their padding
// need. Tabs are made that much taller.
@property (nonatomic, readonly) CGFloat richContentChromeHeight;
@required
@property (nonatomic) PSMTabBarOrientation orientation;

@end

@interface PSMTabBarControl (StyleAccessors)

- (NSMutableArray *)cells;
- (void)sanityCheck:(NSString *)callsite;
- (void)sanityCheck:(NSString *)callsite force:(BOOL)force;

@end

NS_ASSUME_NONNULL_END
