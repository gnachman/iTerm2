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
// A tab-group chip cell: a first-class cell in the control's cell list
// that heads a contiguous run of same-group tabs. Like a placeholder it
// has no representedObject/tab (so it's inert to selection/close/drop),
// but unlike a placeholder it is persistent. Its group is tabGroupIdentifier;
// name/color come from the control's tabGroupDataSource at draw time.
@property(nonatomic, assign) BOOL isTabGroupChip;
@property(nonatomic, assign) int currentStep;
@property(nonatomic, copy) NSString *modifierString;
@property(nonatomic, retain) NSColor *tabColor;
// Identifier of the tab group this cell belongs to, or nil. The control
// uses runs of equal identifiers to place group chips; attributes come
// from the control's tabGroupDataSource, not from the cell. (No
// nullability specifier: this header has no NS_ASSUME_NONNULL region and
// annotating one pointer would force annotating them all.)
@property(nonatomic, copy) NSString *tabGroupIdentifier;
// For a drag drop-slot placeholder that sits just after a group's last member:
// the id of the group a tab dropped here should join (its "end of group" slot).
// nil on every non-slot cell and on slots that don't join a group.
@property(nonatomic, copy) NSString *joinsTabGroupIdentifier;
// The cell's width when drop-slot placeholders were distributed for the
// current drag; 0 outside a drag. The drag animation shrinks real tabs
// proportionally from this base when an expanding drop slot needs room in a
// full (stretch-to-fit) bar, so repeated ticks never compound the shrink.
@property(nonatomic, assign) CGFloat dragBaseWidth;
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
@property(nonatomic) PSMProgress progress;
@property(nonatomic) BOOL isProcessing;
@property(nonatomic, assign) BOOL isPinned;

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
- (void)updateIndicators;

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
