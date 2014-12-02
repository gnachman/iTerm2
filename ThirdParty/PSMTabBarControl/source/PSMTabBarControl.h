//
//  PSMTabBarControl.h
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMProgressIndicator.h"

extern NSString *const kPSMModifierChangedNotification;
extern NSString *const kPSMTabModifierKey;  // Key for user info dict in modifier changed notification

#define PSMTabDragDidEndNotification @"PSMTabDragDidEndNotification"
#define PSMTabDragDidBeginNotification @"PSMTabDragDidBeginNotification"

#define kPSMTabBarControlHeight 22
// internal cell border
#define MARGIN_X        6
#define MARGIN_Y        3.5
// padding between objects
#define kPSMTabBarCellPadding 4
#define kPSMTabBarCellIconPadding 0
// fixed size objects
#define kPSMMinimumTitleWidth 30
#define kPSMTabBarIndicatorWidth 16.0
#define kPSMTabBarIconWidth 16.0
#define kPSMHideAnimationSteps 2.0

// Value used in _currentStep to indicate that resizing operation is not in progress
#define kPSMIsNotBeingResized -1

// Value used in _currentStep when a resizing operation has just been started
#define kPSMStartResizeAnimation 0

@class PSMOverflowPopUpButton;
@class PSMRolloverButton;
@class PSMTabBarCell;
@class PSMTabBarControl;

@protocol PSMTabStyle;

// Tab views controlled by the tab bar may expect this protocol to be conformed to by their delegate.
@protocol PSMTabViewDelegate<NSTabViewDelegate>
- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)index;
- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem;
- (NSDragOperation)tabView:(NSTabView *)tabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)sender;
- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender;
- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;
@end

// These methods are KVO-observed.
@protocol PSMTabBarControlRepresentedObjectIdentifierProtocol <NSObject>
@optional
- (BOOL)isProcessing;
- (void)setIsProcessing:(BOOL)processing;
- (NSImage *)icon;
- (void)setIcon:(NSImage *)icon;
- (int)objectCount;
- (void)setObjectCount:(int)objectCount;
@end

@protocol PSMTabBarControlDelegate <NSTabViewDelegate>
@optional
- (NSDragOperation)tabView:(NSTabView *)aTabView
    draggingEnteredTabBarForSender:(id<NSDraggingInfo>)tabView;
- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender;

//Standard NSTabView methods
- (BOOL)tabView:(NSTabView *)aTabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)aTabView didCloseTabViewItem:(NSTabViewItem *)tabViewItem;

//"Spring-loaded" tabs methods
- (NSArray *)allowedDraggedTypesForTabView:(NSTabView *)aTabView;
- (void)tabView:(NSTabView *)aTabView acceptedDraggingInfo:(id <NSDraggingInfo>)draggingInfo onTabViewItem:(NSTabViewItem *)tabViewItem;

//Contextual menu method
- (NSMenu *)tabView:(NSTabView *)aTabView menuForTabViewItem:(NSTabViewItem *)tabViewItem;

//Drag and drop methods
- (BOOL)tabView:(NSTabView *)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl;
- (BOOL)tabView:(NSTabView *)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl;
- (void)tabView:(NSTabView*)aTabView willDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl;
- (void)tabView:(NSTabView*)aTabView didDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl;

//Tear-off tabs methods
- (NSImage *)tabView:(NSTabView *)aTabView imageForTabViewItem:(NSTabViewItem *)tabViewItem offset:(NSSize *)offset styleMask:(unsigned int *)styleMask;
- (PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point;
- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem;

//Overflow menu validation
- (BOOL)tabView:(NSTabView *)aTabView validateOverflowMenuItem:(NSMenuItem *)menuItem forTabViewItem:(NSTabViewItem *)tabViewItem;

//tab bar hiding methods
- (void)tabView:(NSTabView *)aTabView tabBarDidHide:(PSMTabBarControl *)tabBarControl;
- (void)tabView:(NSTabView *)aTabView tabBarDidUnhide:(PSMTabBarControl *)tabBarControl;

//tooltips
- (NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)tabViewItem;

//accessibility
- (NSString *)accessibilityStringForTabView:(NSTabView *)aTabView objectCount:(int)objectCount;

- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int) index;
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView;

// iTerm add-on
- (void)setTabColor:(NSColor *)aColor forTabViewItem:(NSTabViewItem *) tabViewItem;
- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem;
- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView;
- (void)setModifier:(int)mask;
- (void)fillPath:(NSBezierPath*)path;
- (void)closeTab:(id)identifier;
- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;

@end

typedef enum {
    PSMTabBarHorizontalOrientation,
    PSMTabBarVerticalOrientation
} PSMTabBarOrientation;

enum {
    PSMTab_SelectedMask                 = 1 << 1,
    PSMTab_LeftIsSelectedMask       = 1 << 2,
    PSMTab_RightIsSelectedMask          = 1 << 3,
    PSMTab_PositionLeftMask     = 1 << 4,
    PSMTab_PositionMiddleMask       = 1 << 5,
    PSMTab_PositionRightMask        = 1 << 6,
    PSMTab_PositionSingleMask       = 1 << 7
};

enum {
    PSMTab_TopTab           = 0,
    PSMTab_BottomTab        = 1,
    PSMTab_LeftTab          = 2,
};

// This view provides a control interface to manage a regular NSTabView.  It looks and works like
// the tabbed browsing interface of many popular browsers.
@interface PSMTabBarControl : NSControl<
  NSDraggingSource,
  PSMProgressIndicatorDelegate,
  PSMTabViewDelegate> 

// control characteristics
+ (NSBundle *)bundle;

// control configuration
- (PSMTabBarOrientation)orientation;
- (void)setOrientation:(PSMTabBarOrientation)value;
- (BOOL)disableTabClose;
- (void)setDisableTabClose:(BOOL)value;
- (id<PSMTabStyle>)style;
- (void)setStyle:(id <PSMTabStyle>)newStyle;
- (BOOL)hideForSingleTab;
- (void)setHideForSingleTab:(BOOL)value;
- (BOOL)showAddTabButton;
- (void)setShowAddTabButton:(BOOL)value;
- (int)cellMinWidth;
- (void)setCellMinWidth:(int)value;
- (int)cellMaxWidth;
- (void)setCellMaxWidth:(int)value;
- (int)cellOptimumWidth;
- (void)setCellOptimumWidth:(int)value;
- (BOOL)sizeCellsToFit;
- (void)setSizeCellsToFit:(BOOL)value;
- (BOOL)useOverflowMenu;
- (void)setUseOverflowMenu:(BOOL)value;
- (BOOL)allowsBackgroundTabClosing;
- (void)setAllowsBackgroundTabClosing:(BOOL)value;
- (BOOL)allowsResizing;
- (void)setAllowsResizing:(BOOL)value;
- (BOOL)selectsTabsOnMouseDown;
- (void)setSelectsTabsOnMouseDown:(BOOL)value;
- (BOOL)automaticallyAnimates;
- (void)setAutomaticallyAnimates:(BOOL)value;
- (int)tabLocation;
- (void)setTabLocation:(int)value;
- (void)changeIdentifier:(id)newIdentifier atIndex:(int)theIndex;
- (void)moveTabAtIndex:(NSInteger)i1 toIndex:(NSInteger)i2;

// accessors
- (NSTabView *)tabView;
- (void)setTabView:(NSTabView *)view;
- (id<PSMTabBarControlDelegate>)delegate;
- (void)setDelegate:(id<PSMTabBarControlDelegate>)object;
- (id)partnerView;
- (void)setPartnerView:(id)view;

// the buttons
- (PSMRolloverButton *)addTabButton;
- (PSMOverflowPopUpButton *)overflowPopUpButton;

// tab information
- (NSMutableArray *)representedTabViewItems;
- (int)numberOfVisibleTabs;

// special effects
- (void)hideTabBar:(BOOL)hide animate:(BOOL)animate;
- (BOOL)isTabBarHidden;

// internal bindings methods also used by the tab drag assistant
- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item;
- (void)disconnectItem:(NSObjectController*)item fromCell:(PSMTabBarCell*)cell;
- (void)removeTabForCell:(PSMTabBarCell *)cell;

// iTerm add-ons
- (void)setTabColor:(NSColor *)aColor forTabViewItem:(NSTabViewItem *) tabViewItem;
- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem;
- (void)setModifier:(int)mask;
- (NSString*)_modifierString;
- (void)fillPath:(NSBezierPath*)path;
- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;

@end
