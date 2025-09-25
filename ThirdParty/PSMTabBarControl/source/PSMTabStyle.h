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

@protocol PSMTabStyle <NSObject>

@property(nonatomic, weak) PSMTabBarControl *tabBar;
@property(nonatomic, readonly) NSAppearance *accessoryAppearance NS_AVAILABLE_MAC(10_14);
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
- (NSImage *)addTabButtonImage;
- (NSImage *)addTabButtonPressedImage;
- (NSImage *)addTabButtonRolloverImage;

// cell specific parameters
- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)orientation;
- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)indicatorRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell;
- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell;
- (float)desiredWidthOfTabCell:(PSMTabBarCell *)cell;

// cell values
- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell;
- (PSMCachedTitleInputs *)cachedTitleInputsForTabCell:(PSMTabBarCell *)cell;
- (PSMCachedTitleInputs *)cachedSubtitleInputsForTabCell:(PSMTabBarCell *)cell;

// drawing
- (void)drawTabCell:(PSMTabBarCell *)cell highlightAmount:(CGFloat)highlightAmount;
- (void)drawBackgroundInRect:(NSRect)rect color:(NSColor*)color horizontal:(BOOL)horizontal;
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
                      backgroundColor:(NSColor *)backgroundColor
                   windowIsMainAndAppIsActive:(BOOL)mainAndActive;
- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount;
- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar;
- (NSColor *)textColorForCell:(PSMTabBarCell *)cell;
- (NSRect)adjustedCellRect:(NSRect)rect generic:(NSRect)generic;
- (NSRect)dirtyFrameForCell:(PSMTabBarCell *)cell;
- (NSRect)frameForAddTabButtonWithCellWidths:(NSArray<NSNumber *> *)widths
                                      height:(CGFloat)height;
- (PSMRolloverButton *)makeAddTabButtonWithFrame:(NSRect)frame;
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
