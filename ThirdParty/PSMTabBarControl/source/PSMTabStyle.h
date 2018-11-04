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

// identity
- (NSString *)name;

// control specific parameters
- (float)leftMarginForTabBarControl;
- (float)rightMarginForTabBarControl;
- (float)topMarginForTabBarControl;

// add tab button
- (NSImage *)addTabButtonImage;
- (NSImage *)addTabButtonPressedImage;
- (NSImage *)addTabButtonRolloverImage;

// cell specific parameters
- (NSRect)dragRectForTabCell:(PSMTabBarCell *)cell orientation:(PSMTabBarOrientation)orientation;
- (NSRect)closeButtonRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)iconRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)indicatorRectForTabCell:(PSMTabBarCell *)cell;
- (NSRect)objectCounterRectForTabCell:(PSMTabBarCell *)cell;
- (float)minimumWidthOfTabCell:(PSMTabBarCell *)cell;
- (float)desiredWidthOfTabCell:(PSMTabBarCell *)cell;

// cell values
- (NSAttributedString *)attributedObjectCountValueForTabCell:(PSMTabBarCell *)cell;
- (NSAttributedString *)attributedStringValueForTabCell:(PSMTabBarCell *)cell;

// drawing
- (void)drawTabCell:(PSMTabBarCell *)cell highlightAmount:(CGFloat)highlightAmount;
- (void)drawBackgroundInRect:(NSRect)rect color:(NSColor*)color horizontal:(BOOL)horizontal;
- (void)drawTabBar:(PSMTabBarControl *)bar inRect:(NSRect)rect clipRect:(NSRect)clipRect horizontal:(BOOL)horizontal;

- (NSColor *)accessoryFillColor;
- (NSColor *)accessoryStrokeColor;
- (void)fillPath:(NSBezierPath*)path;
- (NSColor *)accessoryTextColor;

// Should light-tinted controls be used?
- (BOOL)useLightControls;

- (NSColor *)verticalLineColorSelected:(BOOL)selected;
- (NSColor *)textColorDefaultSelected:(BOOL)selected;
- (NSColor *)backgroundColorSelected:(BOOL)selected highlightAmount:(CGFloat)highlightAmount;
- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar;
- (NSColor *)textColorForCell:(PSMTabBarCell *)cell;

@end

@interface PSMTabBarControl (StyleAccessors)

- (NSMutableArray *)cells;
- (void)sanityCheck:(NSString *)callsite;
- (void)sanityCheck:(NSString *)callsite force:(BOOL)force;

@end
