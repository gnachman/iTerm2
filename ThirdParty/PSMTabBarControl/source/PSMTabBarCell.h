//
//  PSMTabBarCell.h
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMTabBarControl.h"
#import "PSMProgressIndicator.h"

@class PSMTabBarControl;
@protocol PSMTabStyle;

@protocol PSMTabBarControlProtocol <NSObject>
- (void)tabClick:(id)sender;
// 0=left, 1=right, 2=middle
- (void)closeTabClick:(id)sender button:(int)button;
- (id<PSMTabStyle>)style;
- (void)update:(BOOL)animate;
- (BOOL)automaticallyAnimates;
- (PSMTabBarOrientation)orientation;
- (id<PSMTabBarControlDelegate>)delegate;
- (NSTabView *)tabView;
- (BOOL)supportsMultiLineLabels;
@end

@interface PSMTabBarCell : NSActionCell <NSCoding>
// Is this the last cell? Only valid while drawing.
@property(nonatomic, assign) BOOL isLast;
@property(nonatomic, assign) BOOL isCloseButtonSuppressed;
@property(nonatomic, readonly) BOOL closeButtonVisible;
@property(nonatomic, assign) int tabState;
@property(nonatomic, assign) NSRect frame;
@property(nonatomic, assign) BOOL isInOverflowMenu;
@property(nonatomic, assign) BOOL closeButtonPressed;
@property(nonatomic, assign) BOOL closeButtonOver;
@property(nonatomic, assign) BOOL hasCloseButton;
@property(nonatomic, assign) BOOL hasIcon;
@property(nonatomic, assign) int count;
@property(nonatomic, assign) BOOL isPlaceholder;
@property(nonatomic, assign) int currentStep;
@property(nonatomic, copy) NSString *modifierString;
@property(nonatomic, retain) NSColor *tabColor;
@property(nonatomic, readonly) PSMProgressIndicator *indicator;
@property(nonatomic, readonly) PSMCachedTitle *cachedTitle;
@property(nonatomic, readonly) PSMCachedTitle *cachedSubtitle;
@property(nonatomic, readonly) NSSize stringSize;
@property(nonatomic, readonly) float width;
@property(nonatomic, readonly) float minimumWidthOfCell;
@property(nonatomic, readonly) float desiredWidthOfCell;
@property(nonatomic, readonly) id<PSMTabStyle> style;
@property(nonatomic, assign) NSLineBreakMode truncationStyle;  // How to truncate title.
@property(nonatomic, readonly) NSAccessibilityElement *element;
@property(nonatomic, copy) NSString *subtitleString;
@property(nonatomic, readonly) CGFloat highlightAmount;

// creation/destruction
- (id)initWithControlView:(PSMTabBarControl *)controlView;
- (id)initPlaceholderWithFrame:(NSRect)frame expanded:(BOOL)value inControlView:(PSMTabBarControl *)controlView;

// accessors
- (void)setStringValue:(NSString *)aString;

// component attributes
- (NSRect)indicatorRectForFrame:(NSRect)cellFrame;
- (NSRect)closeButtonRectForFrame:(NSRect)cellFrame;

// drawing
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (void)drawPostHocDecorationsOnSelectedCell:(PSMTabBarCell *)cell
                               tabBarControl:(PSMTabBarControl *)bar;

// drag support
- (NSImage *)dragImage;

// iTerm additions
- (void)updateForStyle;
- (void)updateHighlight;

- (void)removeCloseButtonTrackingRectFrom:(NSView *)view;
- (void)removeCellTrackingRectFrom:(NSView *)view;

- (void)setCellTrackingRect:(NSRect)rect
                   userData:(NSDictionary *)data
               assumeInside:(BOOL)flag
                       view:(NSView *)view;

- (void)setCloseButtonTrackingRect:(NSRect)rect
                          userData:(NSDictionary *)data
                      assumeInside:(BOOL)flag
                              view:(NSView *)view;

@end
