//
//  PSMTabBarControl.h
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "PSMCachedTitle.h"
#import "PSMProgressIndicator.h"
#import "PSMTabGroup.h"

NS_ASSUME_NONNULL_BEGIN

// Set to 1 to enable drag performance debugging (timestamp overlay and NSLog statements)
#define PSM_DEBUG_DRAG_PERFORMANCE 0

extern NSString *const kPSMModifierChangedNotification;
extern NSString *const kPSMTabModifierKey;  // Key for user info dict in modifier changed notification

extern NSString *const PSMTabDragDidEndNotification;
extern NSString *const PSMTabDragDidBeginNotification;

// internal cell border
extern const CGFloat kSPMTabBarCellInternalXMargin;

// padding between objects
extern const CGFloat kPSMTabBarCellPadding;
extern const CGFloat kPSMTabBarCellIconPadding;
// fixed size objects
extern const CGFloat kPSMMinimumTitleWidth;
extern const CGFloat kPSMTabBarIndicatorWidth;
extern const CGFloat kPSMTabBarIconWidth;
extern const CGFloat kPSMHideAnimationSteps;
extern const CGSize PSMTabBarGraphicSize;
extern const CGFloat PSMTabBarGraphicMargin;

// Value used in _currentStep to indicate that resizing operation is not in progress
extern const NSInteger kPSMIsNotBeingResized;

// Value used in _currentStep when a resizing operation has just been started
extern const NSInteger kPSMStartResizeAnimation;

@class PSMRolloverButton;
@class PSMTabBarCell;
@class PSMTabBarControl;
@protocol PSMTabStyle;

typedef NSString *PSMTabBarControlOptionKey NS_EXTENSIBLE_STRING_ENUM;
extern PSMTabBarControlOptionKey PSMTabBarControlOptionColoredSelectedTabOutlineStrength;  // NSNumber in 0-3
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalStyleBackgroundColorDifference;  // Number in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalBackgroundAlphaValue;  // Number in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalTextLegibilityAdjustment;  // Number >= 0
extern PSMTabBarControlOptionKey PSMTabBarControlOptionColoredMinimalOutlineStrength;  // Number in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionColoredUnselectedTabTextProminence;  // NSNumber in 0-0.5
extern PSMTabBarControlOptionKey PSMTabBarControlOptionDimmingAmount;  // Double in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab;  // Boolean
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimumSpaceForLabel;  // NSNumber CFGloat points
extern PSMTabBarControlOptionKey PSMTabBarControlOptionHighVisibility;  // NSNumber boolean
extern PSMTabBarControlOptionKey PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar;  // NSNumber boolean
extern PSMTabBarControlOptionKey PSMTabBarControlOptionFontSizeOverride;  // NSNumber double
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence;  // NSNumber double in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionDragEdgeHeight;  // NSNumber CGFloat
extern PSMTabBarControlOptionKey PSMTabBarControlOptionAttachedToTitleBar;  // NSNumber bool, 10.16+
extern PSMTabBarControlOptionKey PSMTabBarControlOptionHTMLTabTitles;  // NSNumber bool
extern PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha;  // NSNumber CGFloat in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionTextColor;  // NSColor
extern PSMTabBarControlOptionKey PSMTabBarControlOptionLightModeInactiveTabDarkness;  // NSNumber in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionDarkModeInactiveTabDarkness;  // NSNumber in 0-1
extern PSMTabBarControlOptionKey PSMTabBarControlOptionPUAFontProvider;  // id<PSMPUAFontProvider> for Private Use Area characters

// Tab views controlled by the tab bar may expect this protocol to be conformed to by their delegate.
@protocol PSMTabViewDelegate<NSTabViewDelegate>
- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)index;
- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem;
- (NSDragOperation)tabView:(NSTabView *)tabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)sender;
- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)sender;
- (nullable NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;
@end

// These methods are KVO-observed.
@protocol PSMTabBarControlRepresentedObjectIdentifierProtocol<NSObject>
@optional
- (BOOL)isProcessing;
- (void)setIsProcessing:(BOOL)processing;
- (nullable NSImage *)icon;
- (void)setIcon:(nullable NSImage *)icon;
- (int)objectCount;
- (void)setObjectCount:(int)objectCount;
- (nullable NSImage *)psmTabGraphic;
- (nullable NSColor *)psmTabStatusSubtitleColor;
@end

@protocol PSMTabBarControlDelegate<NSTabViewDelegate>
// Set object count, icon, etc.
- (void)tabView:(NSTabView *)tabView updateStateForTabViewItem:(NSTabViewItem *)tabViewItem;
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
- (nullable NSMenu *)tabView:(NSTabView *)aTabView menuForTabViewItem:(NSTabViewItem *)tabViewItem;
// Contextual menu for a right-click on a tab group's chip (checked with
// -respondsToSelector:, like the other methods here).
- (nullable NSMenu *)tabView:(NSTabView *)aTabView menuForTabGroup:(NSString *)tabGroupIdentifier;
// A single click on a tab group's chip: toggle the group's collapsed state
// (checked with -respondsToSelector:).
- (void)tabView:(NSTabView *)aTabView toggleCollapseOfTabGroup:(NSString *)tabGroupIdentifier;

//Drag and drop methods
- (BOOL)tabView:(NSTabView *)aTabView shouldDragTabViewItem:(NSTabViewItem *)tabViewItem fromTabBar:(PSMTabBarControl *)tabBarControl;
- (BOOL)tabView:(NSTabView *)aTabView shouldDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(nullable PSMTabBarControl *)tabBarControl moveSourceWindow:(nullable BOOL *)moveSourceWindow;
- (void)tabView:(NSTabView*)aTabView willDropTabViewItem:(NSTabViewItem *)tabViewItem inTabBar:(PSMTabBarControl *)tabBarControl;
// `groupID` is the tab group whose bracket the drop landed inside (the tab
// should join it), or nil when it landed outside every group. Passed
// explicitly so the delegate never has to read drop context back out of the
// shared drag assistant.
- (void)tabView:(NSTabView*)aTabView
    didDropTabViewItem:(NSTabViewItem *)tabViewItem
              inTabBar:(PSMTabBarControl *)tabBarControl
    joiningGroupWithID:(nullable NSString *)groupID;
// A whole tab group was dropped onto `destTabBar` (this window's or another's)
// during a chip drag. `members` are the group's member tabs in order; insert them
// before `anchor` (or at the end if nil), carrying the group's definition. The
// delegate must move the whole block, not resolve per-tab membership.
- (void)tabView:(NSTabView*)aTabView
    dropGroupWithID:(NSString *)groupID
            members:(NSArray<NSTabViewItem *> *)members
           inTabBar:(PSMTabBarControl *)destTabBar
  beforeTabViewItem:(nullable NSTabViewItem *)anchor;
// A whole tab group was dropped outside any tab bar: tear it off into a new
// window positioned at `screenPoint` (top-left), carrying the group's definition.
- (void)tabView:(NSTabView*)aTabView
    tearOffGroupWithID:(NSString *)groupID
               members:(NSArray<NSTabViewItem *> *)members
         atScreenPoint:(NSPoint)screenPoint;

//Tear-off tabs methods
- (nullable NSImage *)tabView:(NSTabView *)aTabView imageForTabViewItem:(NSTabViewItem *)tabViewItem styleMask:(NSWindowStyleMask *)styleMask;
- (nullable PSMTabBarControl *)tabView:(NSTabView *)aTabView newTabBarForDraggedTabViewItem:(NSTabViewItem *)tabViewItem atPoint:(NSPoint)point;
- (void)tabView:(NSTabView *)aTabView closeWindowForLastTabViewItem:(NSTabViewItem *)tabViewItem;
- (BOOL)tabViewDragShouldExitWindow:(NSTabView *)tabView;

//Overflow menu validation
- (BOOL)tabView:(NSTabView *)aTabView validateOverflowMenuItem:(NSMenuItem *)menuItem forTabViewItem:(NSTabViewItem *)tabViewItem;

//tab bar hiding methods
- (void)tabView:(NSTabView *)aTabView tabBarDidHide:(PSMTabBarControl *)tabBarControl;
- (void)tabView:(NSTabView *)aTabView tabBarDidUnhide:(PSMTabBarControl *)tabBarControl;

//tooltips
- (nullable NSString *)tabView:(NSTabView *)aTabView toolTipForTabViewItem:(NSTabViewItem *)tabViewItem;

//accessibility
- (NSString *)accessibilityStringForTabView:(NSTabView *)aTabView objectCount:(int)objectCount;

- (void)tabView:(NSTabView *)tabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willAddTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int) index;
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView;

// iTerm add-on
- (void)setTabColor:(nullable NSColor *)aColor forTabViewItem:(NSTabViewItem *) tabViewItem;
- (nullable NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem;
- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabViewDoubleClickTabBar:(NSTabView *)tabView;
- (void)setModifier:(int)mask;
- (void)fillPath:(NSBezierPath*)path;
- (void)tabView:(NSTabView *)tabView closeTab:(id)identifier button:(int)button;
- (nullable NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;
- (nullable id)tabView:(PSMTabBarControl *)tabView valueOfOption:(PSMTabBarControlOptionKey)option;
- (void)tabViewDidClickAddTabButton:(PSMTabBarControl *)tabView;
- (BOOL)tabViewShouldDragWindow:(NSTabView *)tabView event:(NSEvent *)event;
- (BOOL)tabViewShouldAllowDragOnAddTabButton:(NSTabView *)tabView;
- (CGFloat)tabViewDesiredTabBarHeight:(NSTabView *)tabView;

@end

enum {
    PSMTab_SelectedMask = 1 << 1,
    PSMTab_LeftIsSelectedMask = 1 << 2,
    PSMTab_RightIsSelectedMask = 1 << 3,
    PSMTab_PositionLeftMask = 1 << 4,
    PSMTab_PositionMiddleMask = 1 << 5,
    PSMTab_PositionRightMask = 1 << 6,
    PSMTab_PositionSingleMask = 1 << 7
};

typedef NS_ENUM(int, PSMTabPosition) {
    PSMTab_TopTab = 0,
    PSMTab_BottomTab = 1,
    PSMTab_LeftTab = 2,
    PSMTab_RightTab = 3,
};

extern const CGFloat PSMTabBarProgressBarHeight;

// This view provides a control interface to manage a regular NSTabView.  It looks and works like
// the tabbed browsing interface of many popular browsers.
@interface PSMTabBarControl : NSControl<
  NSDraggingSource,
  NSAccessibilityGroup,
  PSMProgressIndicatorDelegate,
  PSMTabViewDelegate>

// control configuration
@property(nonatomic, assign) BOOL disableTabClose;
// Set transiently while capturing the plain-tab drag image so the bar-level run
// decoration (chip + enclosing outline) is left out of it. The live bar keeps
// its decoration during the drag so groups remain visible as drop targets.
@property(nonatomic, assign) BOOL suppressTabGroupRunDecoration;
// YES while a collapse/expand slide is running. A style can clip each cell's
// drawing to its frame during the slide so a shrinking member's title cannot
// overflow past the group outline.
@property(nonatomic, readonly) BOOL collapseAnimating;
@property(nonatomic, assign) PSMTabBarOrientation orientation;
@property(nonatomic, retain) id<PSMTabStyle> style;
@property(nonatomic, assign) BOOL hideForSingleTab;
@property(nonatomic, assign) BOOL showAddTabButton;
@property(nonatomic, assign) int cellMinWidth;
@property(nonatomic, assign) int cellMaxWidth;
@property(nonatomic, assign) int cellOptimumWidth;
// Tab width used when the bar is scrollable: the fixed width for equal-sized tabs, and the minimum
// width for uneven tabs. Distinct from cellOptimumWidth, which applies to the non-scrollable bar.
@property(nonatomic, assign) int scrollableTabWidth;
@property(nonatomic, assign) int pinnedTabWidth;
@property(nonatomic, assign) BOOL sizeCellsToFit;
@property(nonatomic, assign) BOOL stretchCellsToFit;
@property(nonatomic, assign) BOOL useOverflowMenu;
@property(nonatomic, assign) BOOL allowsBackgroundTabClosing;
@property(nonatomic, assign) BOOL allowsResizing;
@property(nonatomic, assign) BOOL selectsTabsOnMouseDown;
@property(nonatomic, assign) BOOL automaticallyAnimates;
@property(nonatomic, assign) int tabLocation;
@property(nonatomic, assign) int minimumTabDragDistance;
@property(nonatomic, readonly) BOOL lainOutWithOverflow;

// If off (the default) always ellipsize the ends of tab titles that don't fit.
// Of on, ellipsize the start if more tabs share a prefix than a suffix.
@property(nonatomic, assign) BOOL smartTruncation;

@property(nonatomic, retain, nullable) IBOutlet NSTabView *tabView;
@property(nonatomic, weak, nullable) id<PSMTabBarControlDelegate> delegate;
// Supplies tab-group definitions (name/color by identifier) for chip
// rendering. Owned by the window controller; held weakly here.
@property(nonatomic, weak, nullable) id<PSMTabGroupDataSource> tabGroupDataSource;
@property(nonatomic, retain, nullable) id partnerView;
@property(nonatomic, readonly, nullable) NSButton *overflowPopUpButton;
@property(nonatomic, assign) BOOL ignoreTrailingParentheticalsForSmartTruncation;

// control characteristics
+ (NSBundle *)bundle;
+ (BOOL)isAnyDragInProgress;

- (void)changeIdentifier:(nullable id)newIdentifier atIndex:(int)theIndex;
- (void)moveTabAtIndex:(NSInteger)i1 toIndex:(NSInteger)i2;

// the buttons
- (nullable PSMRolloverButton *)addTabButton;

// tab information
- (NSMutableArray *)representedTabViewItems;
- (int)numberOfVisibleTabs;

// special effects
- (void)hideTabBar:(BOOL)hide animate:(BOOL)animate;
- (BOOL)isTabBarHidden;

// internal bindings methods also used by the tab drag assistant
- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item;
- (void)removeTabForCell:(PSMTabBarCell *)cell;

// How far the scrollable tab bar is scrolled along its scroll axis (y for a vertical bar, x for a
// horizontal one), in points. 0 unless the scrollable tab bar is enabled and in use. The tab drag
// assistant reads this so it lays cells out at the same scrolled positions reallyUpdate: gives them.
@property(nonatomic, readonly) CGFloat scrollOffset;

// Length of the scrollable tab region along the scroll axis. For a horizontal bar this stops short of
// the pinned add-tab button on the right; a tab whose frame extends past this length is (partly) in the
// button margin. Styles read it to decide how to draw a tab that straddles that edge.
@property(nonatomic, readonly) CGFloat scrollViewportLength;

#pragma mark - iTerm add-ons

// Internal inset. Ensures nothing but background is drawn in this are.
@property(nonatomic, assign) NSEdgeInsets insets;
@property(nonatomic) CGFloat height;

- (void)setTabColor:(nullable NSColor *)aColor forTabViewItem:(NSTabViewItem *) tabViewItem;
- (nullable NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem;
// Push every tab's group membership at once: identifiers[i] is the group id
// (NSString) of the tab represented by tabViewItems[i], or NSNull for no
// group. Cells are matched by tab view item, never by position -- mid-drag
// the dragged tab's cell is a placeholder and absent, so positional pairing
// would shift every later tab's id. The control groups contiguous cells
// sharing an identifier into one run and draws that run's chip using
// attributes from tabGroupDataSource. Chips are re-derived and the bar
// relaid out at most once per call.
- (void)setTabGroupIdentifiers:(NSArray *)identifiers
               forTabViewItems:(NSArray<NSTabViewItem *> *)tabViewItems;

// Push per-tab collapsed state (parallel to setTabGroupIdentifiers:). A
// collapsed member stays in the cell list and the tab view but is hidden in the
// bar. `flags` are NSNumber booleans matched to `tabViewItems` by identity.
- (void)setTabGroupCollapsedFlags:(NSArray<NSNumber *> *)flags
                  forTabViewItems:(NSArray<NSTabViewItem *> *)tabViewItems;

// Enumerate each fully collapsed group's chip with its (derived) member count.
- (void)enumerateCollapsedTabGroupChipsWithBlock:(void (NS_NOESCAPE ^)(PSMTabBarCell *chip,
                                                                       NSInteger memberCount,
                                                                       NSString *groupID))block
    NS_SWIFT_NAME(enumerateCollapsedTabGroupChips(block:));

// Pure helpers for making group chips first-class cells (window-free, so
// they're unit-tested directly).
//
// Insert a chip cell before each contiguous run of tab cells that share a
// non-nil tabGroupIdentifier. `tabCells` must contain only tab cells (no
// chips); returns a new array of tab + chip cells.
+ (NSArray<PSMTabBarCell *> *)cellsByInsertingTabGroupChipsInto:(NSArray<PSMTabBarCell *> *)tabCells
                                                   controlView:(nullable PSMTabBarControl *)controlView
    NS_SWIFT_NAME(cellsByInsertingTabGroupChips(into:controlView:));
// Like cellsByInsertingTabGroupChipsInto:, but tolerates a cell list that
// already contains placeholder cells mid-drag: placeholders are copied through
// untouched and are transparent when detecting contiguous runs (a group split
// only by placeholders stays one run), and any stray chip cells are dropped and
// re-derived. Used to keep chips visible during a drag without disturbing the
// pure tab/placeholder index math the drag relies on.
+ (NSArray<PSMTabBarCell *> *)cellsByInsertingDragChipsInto:(NSArray<PSMTabBarCell *> *)cells
                                                controlView:(nullable PSMTabBarControl *)controlView
    NS_SWIFT_NAME(cellsByInsertingDragChips(into:controlView:));

// Enumerate each tab-group run for drawing: for every chip cell, the union
// rect of its run and the run's first tab cell. Placeholders are transparent
// to run detection (a group split only by drag placeholders stays one run);
// an "end of group" join slot past the last member is unioned in so the
// outline encloses the slot it drops into; the run ends at another chip, an
// overflowed cell, or a different group id. `rectForCell` maps a cell to the
// rect unioned for it (styles differ, e.g. Tahoe insets to the background
// rect); nil uses raw frames. Runs with no member tabs are skipped. This is
// the single authority for run detection so styles and drag code cannot
// drift.
- (void)enumerateTabGroupRunsWithRect:(NSRect (^ _Nullable)(PSMTabBarCell *cell))rectForCell
                                block:(void (NS_NOESCAPE ^)(PSMTabBarCell *chip,
                                                            NSRect tabsRect,
                                                            PSMTabBarCell *firstTab,
                                                            NSString *groupID))block
    NS_SWIFT_NAME(enumerateTabGroupRuns(rectForCell:block:));

// YES if the real cell immediately before `chip` (skipping placeholders) belongs
// to a group, so that group's right outset already covers the shared inter-group
// gap and `chip`'s group must NOT also outset its left edge. Computed over the
// cells directly (no NSArray->Swift bridge) so the draw path can call it per run
// per frame without allocating.
- (BOOL)cellPrecedingChipCoversInterGroupGap:(PSMTabBarCell *)chip
    NS_SWIFT_NAME(cellPrecedingChipCoversInterGroupGap(_:));

// The first real cell after `chip`'s run that is NOT a member of `groupID` (a
// chip, or a differently-grouped/ungrouped tab), skipping placeholders; nil if
// the run reaches the end. Used to clamp a vertical run's pill bottom. Computed
// over the cells directly (no NSArray->Swift bridge).
- (nullable PSMTabBarCell *)firstNonMemberCellAfterChip:(PSMTabBarCell *)chip
                                                groupID:(NSString *)groupID
    NS_SWIFT_NAME(firstNonMemberCell(afterChip:groupID:));

// Per-cell widths for a horizontal, non-scrollable bar (exposed for unit
// tests of the chip-aware layout).
- (nullable NSArray<NSNumber *> *)cellWidthsForHorizontalArrangementWithOverflow:(BOOL)withOverflow
    NS_SWIFT_NAME(cellWidths(forHorizontalArrangementWithOverflow:));

// Width of a chip cell for a group with the given name, in this bar's style
// (for sizing an incoming group's chip whose definition this bar's data
// source does not know).
- (CGFloat)chipCellWidthForGroupName:(NSString *)name;

// The width `tabCount` incoming tabs (plus a group chip of `chipWidth`, 0
// for a single tab) would occupy once dropped into this horizontal bar; 0
// for vertical bars. Sizes the drop-slot preview at the destination's
// on-drop size rather than the dragged unit's size in its source bar.
- (CGFloat)expectedDropExtentForIncomingTabCount:(NSInteger)tabCount
                                       chipWidth:(CGFloat)chipWidth;

// The style's tab-group run outset when any chip cell is present, else 0.
// The scrollable bar widens its trailing clip by this so a group's enclosing
// pill is not cut off; with no groups the clip stays exactly at the viewport.
- (CGFloat)effectiveTabGroupRunOutset;
// The frame of the first full-size real tab cell in `cells` (skips chips and
// zero-frame collapsed members), or NSZeroRect if there is none. Used to seed a
// chip's cross-axis from a settled tab. Class method so the drag assistant can
// pass its own synthesized cell array.
+ (NSRect)firstFullSizeTabCellFrameInCells:(NSArray<PSMTabBarCell *> *)cells;
// Width of a horizontal group-chip cell (its name, via the data source).
- (CGFloat)widthOfTabGroupChipCell:(PSMTabBarCell *)cell;
// Width of a horizontal group-chip cell from explicit state, for a synthesized
// chip (e.g. a drag chip not in the control's cells): a collapsed chip is wider
// (member-count badge + chevron).
- (CGFloat)widthOfTabGroupChipCellForIdentifier:(NSString *)identifier
                                      collapsed:(BOOL)collapsed
                                    memberCount:(NSInteger)memberCount;
// Height of a vertical group-chip cell (a one-row header band).
- (CGFloat)heightOfTabGroupChipCell:(PSMTabBarCell *)cell;
// Map an NSTabView index to the index of the corresponding tab cell in a
// cell list that includes chip cells (returns cells.count if past the end).
+ (NSInteger)cellIndexForTabIndex:(NSInteger)tabIndex inCells:(NSArray<PSMTabBarCell *> *)cells;
// Map a cell-list index back to its NSTabView index, skipping chip cells;
// NSNotFound if the cell at that index is itself a chip or out of range.
+ (NSInteger)tabIndexForCellIndex:(NSInteger)cellIndex inCells:(NSArray<PSMTabBarCell *> *)cells;

// Strip all chip cells from the cell list (leaving only tab cells) and
// re-derive one chip before each contiguous run. The drag assistant strips
// chips when a drag begins so its placeholder/index math runs in a pure
// tab-cell world, and re-normalizes when the drag ends.
- (void)removeAllTabGroupChipCells;
- (void)normalizeTabGroupChipCells;
- (void)update;
- (void)updateWithoutAnimation;
- (void)setIsPinned:(BOOL)pinned forTabViewItem:(NSTabViewItem *)tabViewItem;
- (BOOL)isPinnedForTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)setModifier:(NSUInteger)mask;
- (NSString*)_modifierString;
- (void)fillPath:(NSBezierPath*)path;
- (nullable NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender;

- (NSColor *)accessoryTextColor;

- (void)initializeStateForCell:(PSMTabBarCell *)cell;

- (void)setIsProcessing:(BOOL)isProcessing forTabWithIdentifier:(nullable id)identifier;
- (void)setProgress:(PSMProgress)progress forTabWithIdentifier:(nullable id)identifier;
- (BOOL)shouldShowCustomProgressBarForTabCell:(PSMTabBarCell *)cell;
- (nullable NSView *)customProgressBarViewForTabCell:(PSMTabBarCell *)cell;
- (void)configureCustomProgressBarView:(NSView *)view forTabCell:(PSMTabBarCell *)cell;
// YES if the tab is not drawn in the bar (scrolled into the overflow menu OR
// hidden inside a collapsed group), so a caller should fall back to the inline
// (in-session) progress bar. NO for an unknown identifier.
- (BOOL)tabIsHiddenInBarWithIdentifier:(nullable id)identifier;

// YES if `cell` is actually drawn in the bar: not in the overflow menu and not
// hidden inside a collapsed group. The single owner of the "is this cell visible
// in the bar" test; route cell loops that mean "drawn"/"not drawn" through it.
- (BOOL)cellIsDrawnInBar:(PSMTabBarCell *)cell;
- (void)setIcon:(nullable NSImage *)icon forTabWithIdentifier:(nullable id)identifier;
- (void)setObjectCount:(NSInteger)objectCount forTabWithIdentifier:(nullable id)identifier;
- (void)graphicDidChangeForTabWithIdentifier:(nullable id)identifier;

- (void)setTabsHaveCloseButtons:(BOOL)tabsHaveCloseButtons;

// Safely remove a cell.
- (void)removeCell:(PSMTabBarCell *)cell;

// Is there anything useful at this point or just background? Useful if you can
// drag the window by dragging the background.
- (BOOL)wantsMouseDownAtPoint:(NSPoint)point;
- (void)moveTabAtIndex:(NSInteger)sourceIndex
              toTabBar:(PSMTabBarControl *)destinationTabBar
               atIndex:(NSInteger)destinationIndex;
- (void)backgroundColorWillChange;
- (nullable id)cellForPoint:(NSPoint)point
                  cellFrame:(nullable NSRectPointer)outFrame;
- (void)dragWillExitTabBar;
- (void)dragDidFinish;
- (void)syncTabProgressBars;

@end

NS_ASSUME_NONNULL_END

BOOL PSMShouldExtendTransparencyIntoMinimalTabBar(void);
