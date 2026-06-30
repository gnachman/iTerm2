//
//  PSMTabBarControl.m
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import "PSMTabBarControl.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSBezierPath+iTerm.h"
#import "PSMTabBarCell.h"
#import "PSMOverflowPopUpButton.h"
#import "PSMRolloverButton.h"
#import "PSMTabStyle.h"
#import "PSMYosemiteTabStyle.h"
#import "PSMTabDragAssistant.h"
#import "PSMTabDragWindow.h"
#import "PSMTabGroupChipView.h"
#import "PTYTask.h"
#import "NSColor+PSM.h"
#import "NSWindow+PSM.h"
#import <QuartzCore/QuartzCore.h>
#import <os/signpost.h>

#if PSM_DEBUG_DRAG_PERFORMANCE
static os_log_t PSMTabBarLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.iterm2.tabbar", "drawing");
    });
    return log;
}
#endif

NSString *const kPSMModifierChangedNotification = @"kPSMModifierChangedNotification";
NSString *const kPSMTabModifierKey = @"TabModifier";
NSString *const PSMTabDragDidEndNotification = @"PSMTabDragDidEndNotification";
NSString *const PSMTabDragDidBeginNotification = @"PSMTabDragDidBeginNotification";
const CGFloat kSPMTabBarCellInternalXMargin = 6;
const CGFloat PSMTabBarProgressBarHeight = 2;

const CGFloat kPSMTabBarCellPadding = 4;
const CGFloat kPSMTabBarCellIconPadding = 4;
// fixed size objects
const CGFloat kPSMMinimumTitleWidth = 30;
const CGFloat kPSMTabBarIndicatorWidth = 16.0;
const CGFloat kPSMTabBarIconWidth = 16.0;
const CGFloat kPSMHideAnimationSteps = 2.0;
const CGSize PSMTabBarGraphicSize = { 16.0, 16.0 };
const CGFloat PSMTabBarGraphicMargin = 2;

// Value used in _currentStep to indicate that resizing operation is not in progress
const NSInteger kPSMIsNotBeingResized = -1;

// Value used in _currentStep when a resizing operation has just been started
const NSInteger kPSMStartResizeAnimation = 0;

PSMTabBarControlOptionKey PSMTabBarControlOptionColoredSelectedTabOutlineStrength = @"PSMTabBarControlOptionColoredSelectedTabOutlineStrength";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalStyleBackgroundColorDifference =
    @"PSMTabBarControlOptionMinimalStyleBackgroundColorDifference";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalBackgroundAlphaValue =
    @"PSMTabBarControlOptionMinimalBackgroundAlphaValue";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalTextLegibilityAdjustment =
    @"PSMTabBarControlOptionMinimalTextLegibilityAdjustment";
PSMTabBarControlOptionKey PSMTabBarControlOptionColoredMinimalOutlineStrength =
    @"PSMTabBarControlOptionColoredMinimalOutlineStrength";
PSMTabBarControlOptionKey PSMTabBarControlOptionColoredUnselectedTabTextProminence = @"PSMTabBarControlOptionColoredUnselectedTabTextProminence";
PSMTabBarControlOptionKey PSMTabBarControlOptionDimmingAmount = @"PSMTabBarControlOptionDimmingAmount";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab = @"PSMTabBarControlOptionMinimalStyleTreatLeftInsetAsPartOfFirstTab";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimumSpaceForLabel =
    @"PSMTabBarControlOptionMinimumSpaceForLabel";
PSMTabBarControlOptionKey PSMTabBarControlOptionHighVisibility = @"PSMTabBarControlOptionHighVisibility";
PSMTabBarControlOptionKey PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar =
    @"PSMTabBarControlOptionColoredDrawBottomLineForHorizontalTabBar";
PSMTabBarControlOptionKey PSMTabBarControlOptionFontSizeOverride =
    @"PSMTabBarControlOptionFontSizeOverride";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence = @"PSMTabBarControlOptionMinimalSelectedTabUnderlineProminence";
PSMTabBarControlOptionKey PSMTabBarControlOptionDragEdgeHeight = @"PSMTabBarControlOptionDragEdgeHeight";
PSMTabBarControlOptionKey PSMTabBarControlOptionAttachedToTitleBar = @"PSMTabBarControlOptionAttachedToTitleBar";
PSMTabBarControlOptionKey PSMTabBarControlOptionHTMLTabTitles = @"PSMTabBarControlOptionHTMLTabTitles";
PSMTabBarControlOptionKey PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha = @"PSMTabBarControlOptionMinimalNonSelectedColoredTabAlpha";
PSMTabBarControlOptionKey PSMTabBarControlOptionTextColor = @"PSMTabBarControlOptionTextColor";
PSMTabBarControlOptionKey PSMTabBarControlOptionLightModeInactiveTabDarkness = @" PSMTabBarControlOptionLightModeInactiveTabDarkness";
PSMTabBarControlOptionKey PSMTabBarControlOptionDarkModeInactiveTabDarkness = @" PSMTabBarControlOptionDarkModeInactiveTabDarkness";
PSMTabBarControlOptionKey PSMTabBarControlOptionPUAFontProvider = @"PSMTabBarControlOptionPUAFontProvider";

@interface PSMToolTip: NSObject
@property (nonatomic, readonly) NSRect rect;
@property (nonatomic, weak, readonly) id owner;
@property (nonatomic, copy, readonly) NSData *data;
@property (nonatomic, strong) NSNumber *tag;

+ (instancetype)toolTipWithRect:(NSRect)rect owner:(id)owner userData:(NSData *)data tag:(NSNumber *)tag;
@end

@implementation PSMToolTip

+ (instancetype)toolTipWithRect:(NSRect)rect owner:(id)owner userData:(NSData *)data tag:(NSNumber *)tag {
    return [[[self alloc] initWithRect:rect owner:owner userData:data tag:tag] autorelease];
}

- (instancetype)initWithRect:(NSRect)rect owner:(id)owner userData:(NSData *)data tag:(NSNumber *)tag {
    self = [super init];
    if (self) {
        _rect = rect;
        _owner = owner;
        _data = [data copy];
        _tag = [tag retain];
    }
    return self;
}

- (void)dealloc {
    [_data release];
    [_tag release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p rect=%@ owner=%@ tag=%@>",
            NSStringFromClass([self class]), self, NSStringFromRect(_rect), _owner, _tag];
}
- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[PSMToolTip class]]) {
        return NO;
    }
    PSMToolTip *other = object;
    if (!NSEqualRects(self.rect, other.rect)) {
        return NO;
    }
    if (self.owner != other.owner && ![self.owner isEqual:other.owner]) {
        return NO;
    }
    if (self.data != other.data && ![self.data isEqual:other.data]) {
        return NO;
    }
    // Don't compare tags because we might not know what they are yet.
    return YES;
}

@end

@interface PSMTabBarControl ()<PSMTabBarControlProtocol, NSMenuItemValidation, NSViewToolTipOwner>
- (void)removeTabProgressBarForCell:(PSMTabBarCell *)cell;
// Hit-test a group chip (chips are invisible to -cellForPoint:).
- (PSMTabBarCell *)chipForPoint:(NSPoint)point;
@end

@implementation PSMTabBarControl {
    // control basics
    NSMutableArray<PSMTabBarCell *> *_cells; // the cells that draw the tabs
    NSButton *_overflowPopUpButton; // for too many tabs
    PSMRolloverButton *_addTabButton;

    // drawing style
    NSTimer *_animationTimer;
    float _animationDelta;
    // One-shot: the next horizontal layout is a collapse/expand and should run
    // the dedicated collapse animator (below). Set by a collapse/expand toggle
    // and consumed by -reallyUpdate:. A scrollable bar otherwise never animates
    // width, and a non-scrollable bar's default animation is the width-only
    // -_animateCells, so this scopes the collapse animator to collapse/expand.
    BOOL _collapseExpandPending;

    // Collapse/expand animation. This is a dedicated frame interpolator (not the
    // width-only _animateCells): it interpolates each cell's width from a start
    // to a target array and re-lays-out via -_setupCells: each frame so the bar
    // stays contiguous with correct cross-axis, scroll, and chip height. While it
    // runs, -_setupCells: lays out collapsed members with their (shrinking) width
    // instead of zeroing them, so they animate rather than snap.
    NSTimer *_collapseAnimTimer;
    NSArray<NSNumber *> *_collapseStartWidths;
    NSArray<NSNumber *> *_collapseTargetWidths;
    CGFloat _collapseAnimT;         // 0..1 progress
    BOOL _collapseAnimating;        // a collapse/expand slide is running
    NSSize _collapseAnimBounds;     // bar size at slide start; a change cancels it
    // Vertical variant: a vertical bar can't slide via -_setupCells: (the style's
    // -adjustedCellRect: normalizes every row to a uniform height), so the frames
    // are set directly. The start/target arrays above then hold HEIGHTS, and these
    // hold the shared cell x/width (all vertical rows share them).
    BOOL _collapseVertical;
    CGFloat _collapseVerticalCellX;
    CGFloat _collapseVerticalCellWidth;
    CGFloat _collapseVerticalGap;   // divider gap: slot advance minus drawn height

    // Horizontal row count (1 or 2) from the most recent layout, used to detect
    // when the two-row tab bar needs the window to recompute the bar height.
    NSInteger _lastLaidOutHorizontalRowCount;

    // vertical tab resizing
    BOOL _resizing;

    // How far the tab bar is scrolled along its scroll axis (y for a vertical bar, x for a horizontal
    // one), in points. 0 means the first tab is at the leading edge. Only meaningful when the
    // scrollable tab bar is enabled; otherwise tabs that don't fit go into the overflow menu.
    CGFloat _scrollOffset;

    // End of the last layout walk along the scroll axis (leading margin + total tab extent), cached by
    // reallyUpdate: so maximumScrollOffset works with variable-width horizontal cells.
    CGFloat _scrollContentExtent;

    // When set, reallyUpdate: scrolls the selected tab into view after each layout. Set when a tab is
    // added or selected (its title, hence width, may settle over several layouts) and cleared when the
    // user scrolls manually.
    BOOL _keepSelectedTabInView;
    // Guards against reallyUpdate: -> scrollSelectedTabIntoView -> update: -> reallyUpdate: recursion.
    BOOL _adjustingScrollForSelection;


    // animation for hide/show
    int _currentStep;
    BOOL _isHidden;
    BOOL _hideIndicators;
    NSView *partnerView; // gets resized when hide/show
    BOOL _awakenedFromNib;
    int _tabBarWidth;

    // drag and drop
    NSEvent *_lastMouseDownEvent; // keep this for dragging reference
    NSEvent *_lastMiddleMouseDownEvent;
    BOOL _haveInitialDragLocation;
    NSPoint _initialDragLocation;
    BOOL _didDrag;
    BOOL _closeClicked;

    // iTerm2 additions
    NSUInteger _modifier;
    BOOL _hasCloseButton;
    BOOL _needsUpdateAnimate;
    BOOL _needsUpdate;
    NSInteger _preDragSelectedTabIndex;  // or NSNotFound
    NSMapTable<PSMTabBarCell *, NSView *> *_tabProgressBars;
    NSMutableArray<PSMToolTip *> *_tooltips;
    NSInteger _toolTipCoalescing;
}

#pragma mark -
#pragma mark Characteristics

+ (NSBundle *)bundle {
    static NSBundle *bundle = nil;
    if (!bundle) bundle = [NSBundle bundleForClass:[PSMTabBarControl class]];
    return bundle;
}

+ (BOOL)isAnyDragInProgress {
    return [[PSMTabDragAssistant sharedDragAssistant] isDragging];
}

// Available width for cells in a single physical row (never doubled).
- (CGFloat)singleRowAvailableCellWidthWithOverflow:(BOOL)withOverflow {
    const CGFloat rightMargin = [_style rightMarginForTabBarControlWithOverflow:withOverflow
                                                                   addTabButton:self.showAddTabButton];
    const CGFloat leftMargin = [_style leftMarginForTabBarControl];
    return [self frame].size.width - leftMargin - rightMargin;
}

- (NSInteger)horizontalRowCount {
    if (![iTermAdvancedSettingsModel twoRowTabBar] ||
        _orientation != PSMTabBarHorizontalOrientation) {
        return 1;
    }
    const NSInteger cellCount = (NSInteger)_cells.count;
    if (cellCount <= 1) {
        return 1;
    }
    // How many cells fit on a single row at minimum width? If they all fit, stay
    // on one row; only spill onto a second row once they would overflow.
    const CGFloat available = [self singleRowAvailableCellWidthWithOverflow:NO];
    const CGFloat minW = self.cellMinWidth;
    const CGFloat spacing = _style.intercellSpacing;
    // During early setup the frame width can be ~0. Report a single row until it
    // has a real width, so we don't briefly force double height / content-view
    // placement and then correct on the next layout.
    if (minW <= 0 || available < minW) {
        return 1;
    }
    NSInteger capacity = (NSInteger)floor((available + spacing) / (minW + spacing));
    capacity = MAX(1, capacity);
    return (cellCount > capacity) ? 2 : 1;
}

// Cache each cell's isFirstInHorizontalRow/isLastInHorizontalRow flags in a single
// O(n) pass (called once per layout) so styles that draw per-cell separators can
// read them in O(1) rather than doing an O(n) neighbor lookup per cell.
//
// In single-row (or vertical) mode these mean first/last cell overall — matching
// the original separator behavior so the default single-row look is unchanged. In
// two-row mode they are relative to the cell's physical row (same frame origin.y),
// using only visible (non-overflow) cells.
- (void)updateHorizontalRowBoundaryFlags {
    const BOOL twoRow = (_orientation == PSMTabBarHorizontalOrientation) && ([self horizontalRowCount] == 2);
    if (!twoRow) {
        PSMTabBarCell *const first = _cells.firstObject;
        PSMTabBarCell *const last = _cells.lastObject;
        for (PSMTabBarCell *cell in _cells) {
            cell.isFirstInHorizontalRow = (cell == first);
            cell.isLastInHorizontalRow = (cell == last);
        }
        return;
    }
    NSMutableArray<PSMTabBarCell *> *visible = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        cell.isFirstInHorizontalRow = NO;
        cell.isLastInHorizontalRow = NO;
        if (![cell isInOverflowMenu]) {
            [visible addObject:cell];
        }
    }
    const NSInteger n = (NSInteger)visible.count;
    for (NSInteger i = 0; i < n; i++) {
        PSMTabBarCell *const cell = visible[i];
        PSMTabBarCell *const prev = (i > 0) ? visible[i - 1] : nil;
        PSMTabBarCell *const next = (i + 1 < n) ? visible[i + 1] : nil;
        cell.isFirstInHorizontalRow = (prev == nil) || fabs(NSMinY(prev.frame) - NSMinY(cell.frame)) > 0.5;
        cell.isLastInHorizontalRow = (next == nil) || fabs(NSMinY(next.frame) - NSMinY(cell.frame)) > 0.5;
    }
}

// --- Two-row vertical geometry ---
// Two rows are laid out as: [top inset][row content][gap][row content][bottom].
// Modeling them this way (one small gap + one reduced bottom margin) instead of
// stacking two full single-row bands avoids doubling the bottom inset, which in
// the default theme left too much space between the rows and below the second row.
// These are shared by the cell layout, the add button, the styles' track drawing,
// and the window's desired-height calc so every consumer agrees.

// Small vertical gap between the two rows.
- (CGFloat)twoRowInterRowGap {
    return 1.0;
}

// Margin below the last row. Reduced from the single-row bottom inset so two rows
// aren't overly tall (a no-op where the inset is already small, e.g. minimal).
- (CGFloat)twoRowBottomInset {
    return MIN(self.insets.bottom, 2.0);
}

// Content height of one physical row, derived from the control's current height so
// it always matches whatever -desiredTabBarHeight produced.
- (CGFloat)twoRowContentHeight {
    const CGFloat usable = self.height - self.insets.top - [self twoRowInterRowGap] - [self twoRowBottomInset];
    return MAX(1.0, usable / 2.0);
}

// Vertical distance between the tops of the two rows.
- (CGFloat)twoRowStride {
    return [self twoRowContentHeight] + [self twoRowInterRowGap];
}

// The total two-row bar height for a given single-row height, using the shared
// [top inset][row][gap][row][bottom] model. This is the single source of truth for
// the two-row height; -twoRowContentHeight/-twoRowStride derive the per-row geometry
// back from self.height once it has been set to this value.
- (CGFloat)twoRowHeightForSingleRowHeight:(CGFloat)singleRowHeight {
    const CGFloat content = MAX(1.0, singleRowHeight - self.insets.top - self.insets.bottom);
    return self.insets.top + content * 2.0 + [self twoRowInterRowGap] + [self twoRowBottomInset];
}

// The real physical width available to cells on one row. In two-row mode the
// per-row widths are derived from this in cellWidthsForHorizontalArrangement…:.
- (float)availableCellWidthWithOverflow:(BOOL)withOverflow {
    return [self singleRowAvailableCellWidthWithOverflow:withOverflow];
}

- (NSRect)genericCellRectWithOverflow:(BOOL)withOverflow {
    NSRect aRect = [self frame];
    aRect.origin.x = [_style leftMarginForTabBarControl];
    aRect.origin.y = self.insets.top;
    aRect.size.width = [self availableCellWidthWithOverflow:withOverflow];
    if (_orientation == PSMTabBarHorizontalOrientation) {
        aRect.size.height = self.height - self.insets.top - self.insets.bottom;
    } else {
        aRect.size.height = self.height;
    }
    return aRect;
}

#pragma mark -
#pragma mark Constructor/destructor

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization
        _cells = [[NSMutableArray alloc] initWithCapacity:10];
        _animationTimer = nil;
        const CGFloat defaultHeight = 24;
        _height = defaultHeight;

        // default config
        _currentStep = kPSMIsNotBeingResized;
        _orientation = PSMTabBarHorizontalOrientation;
        _useOverflowMenu = YES;
        _allowsBackgroundTabClosing = YES;
        _allowsResizing = YES;
        _cellMinWidth = 100;
        _cellMaxWidth = 280;
        _cellOptimumWidth = 130;
        _scrollableTabWidth = 120;
        // Normal (single-row) state, so the first layout doesn't register a
        // 0 -> 1 "row count changed" transition and dispatch a spurious refresh.
        _lastLaidOutHorizontalRowCount = 1;
        _pinnedTabWidth = [iTermAdvancedSettingsModel pinnedTabWidth];
        _minimumTabDragDistance = 10;
        _hasCloseButton = YES;
        _tabLocation = PSMTab_TopTab;
        if (@available(macOS 26, *)) {
            if (![iTermAdvancedSettingsModel useSequoiaStyleTabs]) {
                _style = [[PSMTahoeTabStyle alloc] init];
            } else {
                _style = [[PSMYosemiteTabStyle alloc] init];
            }
        } else {
            _style = [[PSMYosemiteTabStyle alloc] init];
        }
        _preDragSelectedTabIndex = NSNotFound;
        _tabProgressBars = [[NSMapTable strongToStrongObjectsMapTable] retain];

        // the overflow button/menu
        [self setupButtons];

        [self registerForDraggedTypes:[NSArray arrayWithObjects:@"com.iterm2.psm.controlitem", nil]];

        // resize
        [self setPostsFrameChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(frameDidChange:) name:NSViewFrameDidChangeNotification object:self];

        // window status
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidBecomeKeyNotification object:[self window]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowStatusDidChange:) name:NSWindowDidResignKeyNotification object:[self window]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidMove:) name:NSWindowDidMoveNotification object:[self window]];

        // modifier for changing tabs changed (iTerm2 addon)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(modifierChanged:)
                                                     name:kPSMModifierChangedNotification
                                                   object:nil];
        _tooltips = [[NSMutableArray alloc] init];
    }
    [self setTarget:self];
    return self;
}

- (void)setupButtons {
    if (@available(macOS 26, *)) {
        if (![iTermAdvancedSettingsModel useSequoiaStyleTabs]) {
            NSRect overflowButtonRect = [_style frameForOverflowButtonWithAddTabButton:self.showAddTabButton
                                                                         enclosureSize:self.frame.size
                                                                        standardHeight:self.height];
            [_overflowPopUpButton autorelease];
            [_overflowPopUpButton removeFromSuperview];
            _overflowPopUpButton = [[self.style makeOverflowButtonWithFrame:overflowButtonRect] retain];
            if (_overflowPopUpButton) {
                // configure
                [_overflowPopUpButton setAutoresizingMask:NSViewNotSizable|NSViewMinXMargin];
                _overflowPopUpButton.accessibilityLabel = @"More tabs";
            }

            // new tab button
            NSRect addTabButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControlWithOverflow:YES
                                                                                                              addTabButton:self.showAddTabButton],
                                                 3,
                                                 23,
                                                 22);
            [_addTabButton autorelease];
            [_addTabButton removeFromSuperview];
            _addTabButton = [[_style makeAddTabButtonWithFrame:addTabButtonRect] retain];
            if (_showAddTabButton) {
                [_addTabButton setHidden:NO];
            } else {
                [_addTabButton setHidden:YES];
            }
            [_addTabButton setNeedsDisplay:YES];
            _addTabButton.action = @selector(addTab:);
            _addTabButton.target = self;
            return;
        }
    }
    NSRect overflowButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControlWithOverflow:YES
                                                                                                        addTabButton:self.showAddTabButton] + 1,
                                           0,
                                           [_style rightMarginForTabBarControlWithOverflow:YES
                                                                              addTabButton:self.showAddTabButton] - 1,
                                           [self frame].size.height);
    [_overflowPopUpButton autorelease];
    [_overflowPopUpButton removeFromSuperview];
    _overflowPopUpButton = [[PSMOverflowPopUpButton alloc] initWithFrame:overflowButtonRect pullsDown:YES];
    if (_overflowPopUpButton) {
        // configure
        [_overflowPopUpButton setAutoresizingMask:NSViewNotSizable|NSViewMinXMargin];
        _overflowPopUpButton.accessibilityLabel = @"More tabs";
    }

    NSRect addTabButtonRect = NSMakeRect([self frame].size.width - [_style rightMarginForTabBarControlWithOverflow:YES
                                                                                                      addTabButton:self.showAddTabButton],
                                         3,
                                         23,
                                         22);
    [_addTabButton removeFromSuperview];
    [_addTabButton autorelease];
    _addTabButton = [[PSMRolloverButton alloc] initWithFrame:addTabButtonRect];
    if (_addTabButton) {
        NSImage *newButtonImage = [_style addTabButtonImage];
        if (newButtonImage) {
            [_addTabButton setUsualImage:newButtonImage];
        }
        newButtonImage = [_style addTabButtonPressedImage];
        if (newButtonImage) {
            [_addTabButton setAlternateImage:newButtonImage];
        }
        newButtonImage = [_style addTabButtonRolloverImage];
        if (newButtonImage) {
            [_addTabButton setRolloverImage:newButtonImage];
        }
        [_addTabButton setTitle:@""];
        [_addTabButton setImagePosition:NSImageOnly];
        [_addTabButton setButtonType:NSButtonTypeMomentaryChange];
        [_addTabButton setBordered:NO];
        [_addTabButton setBezelStyle:NSBezelStyleShadowlessSquare];
        if (_showAddTabButton){
            [_addTabButton setHidden:NO];
        } else {
            [_addTabButton setHidden:YES];
        }
        [_addTabButton setNeedsDisplay:YES];
        _addTabButton.action = @selector(addTab:);
        _addTabButton.target = self;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];


    // Remove bindings.
    NSArray *temp = [[_cells copy] autorelease];
    for (PSMTabBarCell *cell in temp) {
        [cell retain];
        [self removeTabForCell:cell];
        cell.controlView = nil;
        [cell release];
    }

    for (NSView *progressBar in _tabProgressBars.objectEnumerator) {
        [progressBar removeFromSuperview];
    }
    [_tabProgressBars release];
    [_overflowPopUpButton release];
    [_cells release];
    [_tabView release];
    [_addTabButton release];
    [partnerView release];
    [_lastMouseDownEvent release];
    [_lastMiddleMouseDownEvent release];
    [_style release];
    [_tooltips release];
    _tooltips = nil;
    [_collapseAnimTimer invalidate];
    [_collapseStartWidths release];
    [_collapseTargetWidths release];

    [self unregisterDraggedTypes];

    [super dealloc];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [super viewWillMoveToWindow:newWindow];
    if (!newWindow) {
        // The repeating animation timers retain self (target:self). When the view
        // is detached (window closing), stop them so the last strong reference is
        // dropped and -dealloc can run, rather than the timer continuing to fire
        // -_animateCollapse:/-_animateCells: against a tearing-down tabView.
        [self cancelCollapseAnimation];
        if (_animationTimer) {
            [_animationTimer invalidate];
            _animationTimer = nil;
        }
    }
}

- (void)setHeight:(CGFloat)height {
    _height = height;
}

- (void)awakeFromNib
{
    // build cells from existing tab view items
    NSArray *existingItems = [_tabView tabViewItems];
    for (NSTabViewItem *item in existingItems) {
        if (![[self representedTabViewItems] containsObject:item]) {
            [self addTabViewItem:item];
        }
    }
}

- (void)sanityCheckFailedWithCallsite:(NSString *)callsite reason:(NSString *)reason {
    ILog(@"Sanity check failed from %@ for reason %@. Cells=%@. tabView.tabViewItems=%@ stack:\n%@",
         callsite,
         reason,
         self.cells,
         self.tabView.tabViewItems,
         [NSThread callStackSymbols]);
}

- (void)sanityCheck:(NSString *)callsite {
    [self sanityCheck:callsite force:NO];
}

- (void)sanityCheck:(NSString *)callsite force:(BOOL)force {
    if (!force && [[PSMTabDragAssistant sharedDragAssistant] isDragging]) {
        ILog(@"Skip sanity check during drag from callsite %@", callsite);
        return;
    }
    // Compare only tab cells to the tab view; chip cells are not tabs.
    NSMutableArray<PSMTabBarCell *> *tabCells = [NSMutableArray array];
    for (PSMTabBarCell *cell in self.cells) {
        if (![cell isTabGroupChip]) {
            [tabCells addObject:cell];
        }
    }
    if (self.tabView.tabViewItems.count != tabCells.count) {
        [self sanityCheckFailedWithCallsite:callsite reason:@"count mismatch"];
    } else {
        for (NSInteger i = 0; i < tabCells.count; i++) {
            NSTabViewItem *tabViewItem = self.tabView.tabViewItems[i];
            PSMTabBarCell *cell = tabCells[i];
            if (cell.representedObject != tabViewItem) {
                [self sanityCheckFailedWithCallsite:callsite reason:@"cells[i].representedObject != tabView.tabViewItems[i].representedObject"];
            }
        }
        DLog(@"Sanity check passed. cells=%@. tabView.tabViewITems=%@", self.cells, self.tabView.tabViewItems);
    }
}

#pragma mark -
#pragma mark Accessors

- (NSMutableArray *)cells
{
    return _cells;
}

- (NSEvent *)lastMouseDownEvent
{
    return _lastMouseDownEvent;
}

- (void)setLastMouseDownEvent:(NSEvent *)event
{
    [event retain];
    [_lastMouseDownEvent release];
    _lastMouseDownEvent = event;
}

- (NSEvent *)lastMiddleMouseDownEvent
{
    return _lastMiddleMouseDownEvent;
}

- (void)setLastMiddleMouseDownEvent:(NSEvent *)event
{
    [event retain];
    [_lastMiddleMouseDownEvent release];
    _lastMiddleMouseDownEvent = event;
}

- (void)setDelegate:(id<PSMTabBarControlDelegate>)object {
    _delegate = object;

    NSMutableArray *types = [NSMutableArray arrayWithObject:@"com.iterm2.psm.controlitem"];

    //Update the allowed drag types
    if ([[self delegate] respondsToSelector:@selector(allowedDraggedTypesForTabView:)]) {
        [types addObjectsFromArray:[[self delegate] allowedDraggedTypesForTabView:_tabView]];
    }
    [self unregisterDraggedTypes];
    [self registerForDraggedTypes:types];
    _addTabButton.allowDrags = [object tabViewShouldAllowDragOnAddTabButton:_tabView];
}

- (NSString *)styleName {
    return [_style name];
}

- (void)setStyle:(id <PSMTabStyle>)newStyle {
    [_style autorelease];
    _style = [newStyle retain];
    _style.tabBar = self;
    
    // restyle add tab button
    if (_addTabButton) {
        [self setupButtons];
    }

    [self update:_automaticallyAnimates];
    [self backgroundColorWillChange];
}

- (void)setOrientation:(PSMTabBarOrientation)value {
    PSMTabBarOrientation lastOrientation = _orientation;
    _orientation = value;

    if (_tabBarWidth < 10) {
        _tabBarWidth = 120;
    }

    if (lastOrientation != _orientation) {
        [self update];
    }
}

- (void)setDisableTabClose:(BOOL)value {
    _disableTabClose = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setHideForSingleTab:(BOOL)value {
    _hideForSingleTab = value;
    [self update];
}

- (void)setShowAddTabButton:(BOOL)value {
    _showAddTabButton = value;
    [self setNeedsUpdate:YES];
}

- (void)setCellMinWidth:(int)value {
    _cellMinWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setCellMaxWidth:(int)value {
    _cellMaxWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setCellOptimumWidth:(int)value {
    _cellOptimumWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setScrollableTabWidth:(int)value {
    _scrollableTabWidth = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setSizeCellsToFit:(BOOL)value {
    _sizeCellsToFit = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setStretchCellsToFit:(BOOL)value {
    _stretchCellsToFit = value;
    [self setNeedsUpdate:YES animate:YES];
}

- (void)setUseOverflowMenu:(BOOL)value {
    _useOverflowMenu = value;
    [self update];
}

- (PSMRolloverButton *)addTabButton {
    return _addTabButton;
}

- (void)setTabLocation:(int)value {
    _tabLocation = value;
    switch (value) {
        case PSMTab_TopTab:
        case PSMTab_BottomTab:
            [self setOrientation:PSMTabBarHorizontalOrientation];
            break;

        case PSMTab_LeftTab:
        case PSMTab_RightTab:
            [self setOrientation:PSMTabBarVerticalOrientation];
            break;
    }
}

- (void)setAllowsBackgroundTabClosing:(BOOL)value {
    _allowsBackgroundTabClosing = value;
    [self update];
}

- (BOOL)pointIsInEdgeDragArea:(NSPoint)point {
    const CGFloat edgeDragHeight = self.style.edgeDragHeight;
    if (edgeDragHeight <= 0) {
        return NO;
    }
    switch (_tabLocation) {
        case PSMTab_TopTab:
            return (point.y < edgeDragHeight);

        case PSMTab_BottomTab:
            return (point.y > self.bounds.size.height - edgeDragHeight);

        case PSMTab_LeftTab:
        case PSMTab_RightTab:
            break;
    }
    return NO;
}

- (BOOL)wantsMouseDownAtPoint:(NSPoint)point {
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        if ([self pointIsInEdgeDragArea:point]) {
            return NO;
        }
        if (point.x < self.insets.left) {
            return NO;
        }
        PSMTabBarCell *lastCell = _cells.lastObject;
        if (!lastCell) {
            return NO;
        }
        if (lastCell.isInOverflowMenu) {
            return YES;
        }
        const CGFloat maxX = NSMaxX(lastCell.frame);
        return point.x < maxX;
    } else {
        if (point.y < self.insets.top) {
            return NO;
        }
        PSMTabBarCell *lastCell = _cells.lastObject;
        if (!lastCell) {
            return NO;
        }
        if (lastCell.isInOverflowMenu) {
            return YES;
        }
        const CGFloat maxY = NSMaxY(lastCell.frame);
        return point.y < maxY;
    }
}

#pragma mark -
#pragma mark Functionality

// Returns the leading `length` characters of `title` for the smart-truncation
// heuristic, but first skips a leading run of decoration (whitespace, symbols,
// and punctuation). Some tab titles begin with an animated status glyph, most
// notably a Claude Code spinner such as “⠐ ”, “⠂ ”, or “✳ ” that ticks about
// once a second at an independent phase in each tab. Those glyphs are Unicode
// symbols, so if they were part of the prefix the count of unique prefixes
// would jitter as the spinners drift in and out of phase, flipping the whole
// tab bar between head and tail truncation. Keying off the stable text after
// the decoration keeps the direction steady. Enumerates by composed character
// sequence so a multi-scalar glyph (for example an emoji spinner) is treated as
// a unit rather than half-stripped. Falls back to the raw prefix when the title
// is entirely decoration.
static NSString *PSMSmartTruncationPrefix(NSString *title, NSInteger length) {
    static NSCharacterSet *content;  // the complement of the decoration set
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *decoration = [[NSMutableCharacterSet alloc] init];
        [decoration formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [decoration formUnionWithCharacterSet:[NSCharacterSet symbolCharacterSet]];
        [decoration formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
        content = [[decoration invertedSet] retain];
        [decoration release];
    });
    __block NSUInteger start = 0;
    [title enumerateSubstringsInRange:NSMakeRange(0, title.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if ([substring rangeOfCharacterFromSet:content].location != NSNotFound) {
            *stop = YES;
            return;
        }
        start = NSMaxRange(substringRange);
    }];
    const NSUInteger remaining = title.length - start;
    if (remaining == 0) {
        // Nothing but decoration; there is no stable text to key on so fall back
        // to the raw prefix.
        return [title substringToIndex:(NSUInteger)length];
    }
    return [title substringWithRange:NSMakeRange(start, MIN((NSUInteger)length, remaining))];
}

- (NSLineBreakMode)truncationStyle {
    if (_cells.count <= 1 || !self.smartTruncation) {
        return NSLineBreakByTruncatingTail;
    }
    NSCountedSet *prefixCounts = [[[NSCountedSet alloc] init] autorelease];
    NSCountedSet *suffixCounts = [[[NSCountedSet alloc] init] autorelease];
    NSCountedSet *suffixIgnoringParenthesizedPartCounts = [[[NSCountedSet alloc] init] autorelease];
    NSMutableSet *uniqueTitles = [NSMutableSet set];
    static NSInteger const kPrefixOrSuffixLength = 5;
    for (PSMTabBarCell *cell in _cells) {
        NSString *title = [cell title];
        if (title.length < kPrefixOrSuffixLength) {
            continue;
        }
        [uniqueTitles addObject:title];
        NSString *prefix = PSMSmartTruncationPrefix(title, kPrefixOrSuffixLength);
        NSString *suffix = [title substringFromIndex:(NSInteger)title.length - kPrefixOrSuffixLength];
        
        [prefixCounts addObject:prefix];
        [suffixCounts addObject:suffix];

        if (self.ignoreTrailingParentheticalsForSmartTruncation && [title hasSuffix:@")"]) {
            NSInteger openParen = [title rangeOfString:@" (" options:NSBackwardsSearch].location;
            if (openParen != NSNotFound && openParen > kPrefixOrSuffixLength) {
                suffix = [title substringWithRange:NSMakeRange(openParen - kPrefixOrSuffixLength, kPrefixOrSuffixLength)];
                [suffixIgnoringParenthesizedPartCounts addObject:suffix];
            }
        }
    }
    if (uniqueTitles.count == 0) {
        return NSLineBreakByTruncatingTail;
    }

    NSUInteger suffixCount = MAX(suffixCounts.count,
                                 suffixIgnoringParenthesizedPartCounts.count);
    if (prefixCounts.count >= suffixCount) {
        return NSLineBreakByTruncatingTail;
    } else {
        return NSLineBreakByTruncatingHead;
    }
}

- (void)addTabViewItem:(NSTabViewItem *)item atIndex:(NSUInteger)i {
    // create cell
    PSMTabBarCell *cell = [[PSMTabBarCell alloc] initWithControlView:self];
    cell.truncationStyle = [self truncationStyle];
    [cell setRepresentedObject:item];
    [cell setModifierString:[self _modifierString]];

    // add to collection
    [_cells insertObject:cell atIndex:i];

    // bind it up
    [self initializeStateForCell:cell];
    [self bindPropertiesForCell:cell andTabViewItem:item];
    [cell release];
}

- (void)addTabViewItem:(NSTabViewItem *)item {
    [self addTabViewItem:item atIndex:[_cells count]];
}

- (void)removeTabForCell:(PSMTabBarCell *)cell {
    // unbind
    [cell unbind:@"title"];

    // remove indicator
    if ([[self subviews] containsObject:[cell indicator]]) {
        [[cell indicator] setDelegate:nil];
        [[cell indicator] removeFromSuperview];
    }
    // remove tracking
    [[NSNotificationCenter defaultCenter] removeObserver:cell];

    [cell removeCloseButtonTrackingRectFrom:self];
    [cell removeCellTrackingRectFrom:self];
    [self removeAllToolTips];
    [self removeTabProgressBarForCell:cell];

    // pull from collection
    [_cells removeObject:cell];
}

- (BOOL)shouldShowCustomProgressBarForTabCell:(PSMTabBarCell *)cell {
    return NO;
}

- (NSView *)customProgressBarViewForTabCell:(PSMTabBarCell *)cell {
    return nil;
}

- (void)configureCustomProgressBarView:(NSView *)view forTabCell:(PSMTabBarCell *)cell {
}

- (void)removeTabProgressBarForCell:(PSMTabBarCell *)cell {
    NSView *progressBar = [_tabProgressBars objectForKey:cell];
    if (!progressBar) {
        return;
    }
    [progressBar removeFromSuperview];
    [_tabProgressBars removeObjectForKey:cell];
}

// The custom progress bars are repositioned only by -syncTabProgressBars (once
// per settled layout), not per animation frame, so during a collapse/expand slide
// they would sit at stale positions and then jump. Hide them for the duration; the
// slide ends with -update:NO, which re-runs -syncTabProgressBars and restores them
// at their final positions.
- (void)hideTabProgressBarsForCollapseAnimation {
    for (NSView *progressBar in _tabProgressBars.objectEnumerator.allObjects) {
        progressBar.hidden = YES;
    }
}

- (void)syncTabProgressBars {
    NSMutableSet<PSMTabBarCell *> *visibleCells = [NSMutableSet set];
    for (PSMTabBarCell *cell in _cells) {
        if (![self shouldShowCustomProgressBarForTabCell:cell]) {
            [self removeTabProgressBarForCell:cell];
            continue;
        }
        [visibleCells addObject:cell];
        NSView *progressBar = [_tabProgressBars objectForKey:cell];
        if (!progressBar) {
            progressBar = [self customProgressBarViewForTabCell:cell];
            if (!progressBar) {
                continue;
            }
            [_tabProgressBars setObject:progressBar forKey:cell];
        }
        progressBar.frame = [self.style progressBarRectForTabCell:cell];
        [self configureCustomProgressBarView:progressBar forTabCell:cell];
        if ([self.style respondsToSelector:@selector(progressBarClipPathForTabCell:)]) {
            NSBezierPath *clipPath = [self.style progressBarClipPathForTabCell:cell];
            if (clipPath) {
                // Convert the clip path from the tab bar's flipped coordinate
                // system to the progress bar layer's non-flipped coordinate system.
                const NSRect frame = progressBar.frame;
                NSAffineTransformStruct s = {
                    .m11 = 1,
                    .m12 = 0,
                    .m21 = 0,
                    .m22 = -1,
                    .tX = -frame.origin.x,
                    .tY = frame.size.height + frame.origin.y
                };
                NSAffineTransform *transform = [[NSAffineTransform alloc] init];
                [transform setTransformStruct:s];
                NSBezierPath *localPath = [transform transformBezierPath:clipPath];
                CAShapeLayer *mask = [CAShapeLayer layer];
                mask.path = [localPath iterm_CGPath];
                // Even-odd so a clip path with a nested subpath (e.g. the Tahoe
                // ring around the pill) punches out its interior. Harmless for
                // single-subpath clip paths, where it matches nonzero.
                mask.fillRule = kCAFillRuleEvenOdd;
                progressBar.wantsLayer = YES;
                progressBar.layer.mask = mask;
                [transform release];
            } else {
                progressBar.layer.mask = nil;
            }
        } else {
            progressBar.layer.mask = nil;
        }
        progressBar.hidden = NO;
        if (progressBar.superview != self) {
            [self addSubview:progressBar];
        }
        cell.indicator.hidden = YES;
        cell.indicator.animate = NO;
        [cell.indicator removeFromSuperview];
    }

    for (PSMTabBarCell *cell in _tabProgressBars.keyEnumerator.allObjects) {
        if (![visibleCells containsObject:cell]) {
            NSView *progressBar = [_tabProgressBars objectForKey:cell];
            [progressBar removeFromSuperview];
            [_tabProgressBars removeObjectForKey:cell];
        }
    }
}

- (void)dragDidFinish {
    _preDragSelectedTabIndex = NSNotFound;
}

// YES if `item`'s cell is currently hidden in the bar (overflowed or its group
// is collapsed), so it should not be chosen as the source window's selection.
- (BOOL)tabViewItemIsHiddenInBar:(NSTabViewItem *)item {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == item) {
            return ![self cellIsDrawnInBar:cell];
        }
    }
    return NO;
}

// YES if `cell` is actually drawn in the bar: not scrolled into the overflow
// menu and not hidden inside a collapsed group. The single owner of the
// "is this cell visible in the bar" test (the cell-level companion to
// -tabViewItemIsHiddenInBar:); route cell loops that mean "drawn"/"not drawn"
// (isLast, hit-test tracking rects, and similar) through it rather than
// re-spelling `!isInOverflowMenu && !isCollapsedHidden`, so a future addition to
// the definition of "drawn" lands everywhere. (Loops that additionally exclude
// chips or placeholders express a DIFFERENT concept -- a real drawable tab cell
// -- and intentionally do not funnel through here.)
- (BOOL)cellIsDrawnInBar:(PSMTabBarCell *)cell {
    return ![cell isInOverflowMenu] && ![cell isCollapsedHidden];
}

- (void)dragWillExitTabBar {
    const NSInteger count = self.tabView.tabViewItems.count;
    if (count <= 1) {
        _preDragSelectedTabIndex = NSNotFound;  // clear it on every exit, like the paths below
        return;
    }
    // Only move the selection if the tab that is leaving IS the selected one.
    // A group drag whose members don't include the active tab (the common case
    // of dragging a collapsed group while some other tab is active) must not
    // yank selection onto an arbitrary -- possibly collapsed/hidden -- neighbor.
    NSTabViewItem *selected = self.tabView.selectedTabViewItem;
    if (![[PSMTabDragAssistant sharedDragAssistant] isDraggingTabViewItem:selected]) {
        _preDragSelectedTabIndex = NSNotFound;
        return;
    }
    // Prefer the pre-drag selection if it's still a real, visible tab.
    if (_preDragSelectedTabIndex != NSNotFound && _preDragSelectedTabIndex >= 0 &&
        _preDragSelectedTabIndex < count) {
        NSTabViewItem *item = self.tabView.tabViewItems[_preDragSelectedTabIndex];
        if (![self tabViewItemIsHiddenInBar:item] &&
            ![[PSMTabDragAssistant sharedDragAssistant] isDraggingTabViewItem:item]) {
            [self.tabView selectTabViewItem:item];
            _preDragSelectedTabIndex = NSNotFound;
            return;
        }
    }
    // Otherwise pick the nearest visible tab that is neither leaving nor hidden.
    // If every remaining tab is hidden (all neighbors are collapsed members or in
    // the overflow menu), fall back to the nearest hidden non-leaving tab: leaving
    // the selection on the tab being torn out would let AppKit auto-select an
    // arbitrary neighbor after removal. When the fallback is a collapsed member the
    // drag-end heal (-expandTabGroupIfSelectedTabIsCollapsed via
    // -draggingDidBeginOrEnd:) expands its group and restores the invariant.
    const NSInteger currentIndex = [self.tabView indexOfTabViewItem:selected];
    if (currentIndex != NSNotFound) {
        NSTabViewItem *hiddenFallback = nil;  // nearest non-leaving tab, even if hidden
        for (NSInteger delta = 1; delta < count; delta++) {
            for (NSInteger sign = 1; sign >= -1; sign -= 2) {
                const NSInteger idx = currentIndex + sign * delta;
                if (idx < 0 || idx >= count) {
                    continue;
                }
                NSTabViewItem *item = self.tabView.tabViewItems[idx];
                if ([[PSMTabDragAssistant sharedDragAssistant] isDraggingTabViewItem:item]) {
                    continue;  // this one is leaving with the drag
                }
                if (![self tabViewItemIsHiddenInBar:item]) {
                    [self.tabView selectTabViewItem:item];
                    _preDragSelectedTabIndex = NSNotFound;
                    return;
                }
                if (!hiddenFallback) {
                    hiddenFallback = item;  // nearest hidden candidate, kept as last resort
                }
            }
        }
        if (hiddenFallback) {
            [self.tabView selectTabViewItem:hiddenFallback];
            _preDragSelectedTabIndex = NSNotFound;
            return;
        }
    }
    _preDragSelectedTabIndex = NSNotFound;
}

#pragma mark -
#pragma mark Hide/Show

- (void)hideTabBar:(BOOL)hide animate:(BOOL)animate {
    if (!_awakenedFromNib || (_isHidden && hide) || (!_isHidden && !hide) || (_currentStep != kPSMIsNotBeingResized)) {
        return;
    }

    [[self subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    _hideIndicators = YES;

    _isHidden = hide;
    _currentStep = 0;
    if (!animate)
        _currentStep = (int)kPSMHideAnimationSteps;

    float partnerOriginalSize, partnerOriginalOrigin, myOriginalSize, myOriginalOrigin, partnerTargetSize, partnerTargetOrigin, myTargetSize, myTargetOrigin;

    // target values for partner
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        // current (original) values
        myOriginalSize = [self frame].size.height;
        myOriginalOrigin = [self frame].origin.y;
        if (partnerView) {
            partnerOriginalSize = [partnerView frame].size.height;
            partnerOriginalOrigin = [partnerView frame].origin.y;
        } else {
            partnerOriginalSize = [[self window] frame].size.height;
            partnerOriginalOrigin = [[self window] frame].origin.y;
        }

        if (partnerView) {
            // above or below me?
            if ((myOriginalOrigin - 22) > partnerOriginalOrigin) {
                // partner is below me
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin + 21;
                    myTargetSize = myOriginalSize - 21;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize + 21;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin - 21;
                    myTargetSize = myOriginalSize + 21;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize - 21;
                }
            } else {
                // partner is above me
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = myOriginalSize - 21;
                    partnerTargetOrigin = partnerOriginalOrigin - 21;
                    partnerTargetSize = partnerOriginalSize + 21;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = myOriginalSize + 21;
                    partnerTargetOrigin = partnerOriginalOrigin + 21;
                    partnerTargetSize = partnerOriginalSize - 21;
                }
            }
        } else {
            // for window movement
            if (_isHidden) {
                // I'm shrinking
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = myOriginalSize - 21;
                partnerTargetOrigin = partnerOriginalOrigin + 21;
                partnerTargetSize = partnerOriginalSize - 21;
            } else {
                // I'm growing
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = myOriginalSize + 21;
                partnerTargetOrigin = partnerOriginalOrigin - 21;
                partnerTargetSize = partnerOriginalSize + 21;
            }
        }
    } else {
        // current (original) values
        myOriginalSize = [self frame].size.width;
        myOriginalOrigin = [self frame].origin.x;
        if (partnerView) {
            partnerOriginalSize = [partnerView frame].size.width;
            partnerOriginalOrigin = [partnerView frame].origin.x;
        } else {
            partnerOriginalSize = [[self window] frame].size.width;
            partnerOriginalOrigin = [[self window] frame].origin.x;
        }

        if (partnerView) {
            //to the left or right?
            if (myOriginalOrigin < partnerOriginalOrigin + partnerOriginalSize) {
                // partner is to the left
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = 1;
                    partnerTargetOrigin = partnerOriginalOrigin - myOriginalSize + 1;
                    partnerTargetSize = partnerOriginalSize + myOriginalSize - 1;
                    _tabBarWidth = myOriginalSize;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin;
                    myTargetSize = myOriginalSize + _tabBarWidth;
                    partnerTargetOrigin = partnerOriginalOrigin + _tabBarWidth;
                    partnerTargetSize = partnerOriginalSize - _tabBarWidth;
                }
            } else {
                // partner is to the right
                if (_isHidden) {
                    // I'm shrinking
                    myTargetOrigin = myOriginalOrigin + myOriginalSize;
                    myTargetSize = 1;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize + myOriginalSize;
                    _tabBarWidth = myOriginalSize;
                } else {
                    // I'm growing
                    myTargetOrigin = myOriginalOrigin - _tabBarWidth;
                    myTargetSize = myOriginalSize + _tabBarWidth;
                    partnerTargetOrigin = partnerOriginalOrigin;
                    partnerTargetSize = partnerOriginalSize - _tabBarWidth;
                }
            }
        } else {
            // for window movement
            if (_isHidden) {
                // I'm shrinking
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = 1;
                partnerTargetOrigin = partnerOriginalOrigin + myOriginalSize - 1;
                partnerTargetSize = partnerOriginalSize - myOriginalSize + 1;
                _tabBarWidth = myOriginalSize;
            } else {
                // I'm growing
                myTargetOrigin = myOriginalOrigin;
                myTargetSize = _tabBarWidth;
                partnerTargetOrigin = partnerOriginalOrigin - _tabBarWidth + 1;
                partnerTargetSize = partnerOriginalSize + _tabBarWidth - 1;
            }
        }
    }

    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:myOriginalOrigin], @"myOriginalOrigin", [NSNumber numberWithFloat:partnerOriginalOrigin], @"partnerOriginalOrigin", [NSNumber numberWithFloat:myOriginalSize], @"myOriginalSize", [NSNumber numberWithFloat:partnerOriginalSize], @"partnerOriginalSize", [NSNumber numberWithFloat:myTargetOrigin], @"myTargetOrigin", [NSNumber numberWithFloat:partnerTargetOrigin], @"partnerTargetOrigin", [NSNumber numberWithFloat:myTargetSize], @"myTargetSize", [NSNumber numberWithFloat:partnerTargetSize], @"partnerTargetSize", nil];
    [NSTimer scheduledTimerWithTimeInterval:(1.0/20.0) target:self selector:@selector(animateShowHide:) userInfo:userInfo repeats:YES];
}

- (void)animateShowHide:(NSTimer *)timer
{
    // moves the frame of the tab bar and window (or partner view) linearly to hide or show the tab bar
    NSRect myFrame = [self frame];
    NSDictionary *userInfo = [timer userInfo];
    float myCurrentOrigin = ([[userInfo objectForKey:@"myOriginalOrigin"] floatValue] + (([[userInfo objectForKey:@"myTargetOrigin"] floatValue] - [[userInfo objectForKey:@"myOriginalOrigin"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));
    float myCurrentSize = ([[userInfo objectForKey:@"myOriginalSize"] floatValue] + (([[userInfo objectForKey:@"myTargetSize"] floatValue] - [[userInfo objectForKey:@"myOriginalSize"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));
    float partnerCurrentOrigin = ([[userInfo objectForKey:@"partnerOriginalOrigin"] floatValue] + (([[userInfo objectForKey:@"partnerTargetOrigin"] floatValue] - [[userInfo objectForKey:@"partnerOriginalOrigin"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));
    float partnerCurrentSize = ([[userInfo objectForKey:@"partnerOriginalSize"] floatValue] + (([[userInfo objectForKey:@"partnerTargetSize"] floatValue] - [[userInfo objectForKey:@"partnerOriginalSize"] floatValue]) * (_currentStep/kPSMHideAnimationSteps)));

    NSRect myNewFrame;
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        myNewFrame = NSMakeRect(myFrame.origin.x, myCurrentOrigin, myFrame.size.width, myCurrentSize);
    } else {
        myNewFrame = NSMakeRect(myCurrentOrigin, myFrame.origin.y, myCurrentSize, myFrame.size.height);
    }

    if (partnerView) {
        // resize self and view
        NSRect resizeRect;
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            resizeRect = NSMakeRect([partnerView frame].origin.x, partnerCurrentOrigin, [partnerView frame].size.width, partnerCurrentSize);
        } else {
            resizeRect = NSMakeRect(partnerCurrentOrigin, [partnerView frame].origin.y, partnerCurrentSize, [partnerView frame].size.height);
        }
        [partnerView setFrame:resizeRect];
        [partnerView setNeedsDisplay:YES];
        [self setFrame:myNewFrame];
    } else {
        // resize self and window
        NSRect resizeRect;
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            resizeRect = NSMakeRect([[self window] frame].origin.x, partnerCurrentOrigin, [[self window] frame].size.width, partnerCurrentSize);
        } else {
            resizeRect = NSMakeRect(partnerCurrentOrigin, [[self window] frame].origin.y, partnerCurrentSize, [[self window] frame].size.height);
        }
        [[self window] setFrame:resizeRect display:YES];
        [self setFrame:myNewFrame];
    }

    // next
    _currentStep++;
    if (_currentStep == kPSMHideAnimationSteps + 1) {
        _currentStep = kPSMIsNotBeingResized;
        [self viewDidEndLiveResize];
        _hideIndicators = NO;
        [self update];

        // send the delegate messages
        if (_isHidden) {
            if ([[self delegate] respondsToSelector:@selector(tabView:tabBarDidHide:)]) {
                [[self delegate] tabView:[self tabView] tabBarDidHide:self];
            }
        } else {
            if ([[self delegate] respondsToSelector:@selector(tabView:tabBarDidUnhide:)]) {
                [[self delegate] tabView:[self tabView] tabBarDidUnhide:self];
            }
        }

        [timer invalidate];
    }
    [[self window] display];
}

- (BOOL)isTabBarHidden
{
    return _isHidden;
}

- (id)partnerView
{
    return partnerView;
}

- (void)setPartnerView:(id)view
{
    [partnerView release];
    [view retain];
    partnerView = view;
}

- (void)backgroundColorWillChange {
    _overflowPopUpButton.appearance = _style.accessoryAppearance;
    _addTabButton.appearance = _style.accessoryAppearance;
}

#pragma mark -
#pragma mark Drawing

- (BOOL)isFlipped
{
    return YES;
}

// In sonoma, rect can be larger than the bounds and filling can cause other views to be drawn over. WTF
- (void)drawRect:(NSRect)insaneRect {
#if PSM_DEBUG_DRAG_PERFORMANCE
    static int drawCount = 0;
    static CFAbsoluteTime lastDrawTime = 0;

    os_signpost_interval_begin(PSMTabBarLog(), OS_SIGNPOST_ID_EXCLUSIVE, "drawRect", "");
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
#endif

    const NSRect rect = NSIntersectionRect(self.bounds, insaneRect);
    for (PSMTabBarCell *cell in [self cells]) {
        [cell setIsLast:NO];
    }
    // The cell's isLast property is read ONLY by the cmd-9 "last tab" number badge
    // (the right-edge divider computes its own `cell == cells.lastObject` locally),
    // and cmd-9 always selects the last LOGICAL tab. So mark the last non-chip cell
    // even if it is overflowed or collapsed: the draw loop skips a non-drawn cell,
    // so the badge simply is not painted then (matching the pre-group behavior).
    // Targeting the last DRAWN cell instead would paint "9" on a tab cmd-9 does not
    // select (or on a trailing group chip, which draws no badge, hiding the hint).
    PSMTabBarCell *lastTab = nil;
    for (PSMTabBarCell *cell in [self cells]) {
        if (![cell isTabGroupChip]) {
            lastTab = cell;
        }
    }
    [lastTab setIsLast:YES];

    // A scrollable bar's cells run from the leading edge (under the window decorations -- stoplights,
    // window number, shortcut indicator -- when scrolled there) to the trailing edge (the right margin
    // where the add-tab button is pinned, on a horizontal bar). Clip the cell drawing to that region
    // and repaint the bar background in the excluded strips, so scrolled cells neither show under the
    // decorations nor draw over the button, and the strips still read as bar background. This is a pure
    // drawing clip -- no clipsToBounds (which forces layer backing and makes the bar render opaque) and
    // no background fill of our own that would break the bar's transparency.
    const BOOL scrollable = [self tabBarIsScrollable];
    const BOOL vertical = [self isVerticalOrientation];
    const BOOL horizontalFlag = (_orientation == PSMTabBarHorizontalOrientation);
    const CGFloat width = self.bounds.size.width;
    const CGFloat height = self.bounds.size.height;
    const CGFloat fullLength = vertical ? height : width;
    const CGFloat leadingMargin = scrollable ? [self scrollLeadingMargin] : 0;
    const CGFloat maximumOffset = scrollable ? [self maximumScrollOffset] : 0;
    // Drag auto-scroll (revealing a drop slot past the viewport) shifts cells
    // left without touching _scrollOffset, so include it in the clip logic or
    // the shifted leading cells draw under the window decorations.
    const CGFloat dragNudge = scrollable ? [[PSMTabDragAssistant sharedDragAssistant] dragScrollNudgeForTabBar:self] : 0;
    const CGFloat effectiveOffset = _scrollOffset + dragNudge;
    const BOOL cutOffDecorationBand = (scrollable && effectiveOffset > 0 && leadingMargin > 0);
    // Only clip when tabs actually overflow the bar; with everything visible there is nothing to clip.
    const BOOL needClip = (scrollable && (maximumOffset > 0 || dragNudge > 0));
    const CGFloat leadingClip = cutOffDecorationBand ? leadingMargin : 0;
    // The viewport clip stops at the last tab. A group's enclosing pill extends a
    // little past its tabs, so widen the trailing edge by that outset (into the
    // add-button margin, which has room) or the last group's outline is clipped.
    const CGFloat trailingClip = scrollable ? ([self scrollViewportLength] + [self effectiveTabGroupRunOutset]) : fullLength;

    // Paint the bar background in the leading decoration band and the trailing add-button margin, and
    // the tabs in the region between. Each strip goes through the style's own tab-bar drawing (clipped
    // to the strip, with no cells in the margins), so shaped/style-specific backgrounds come out right.
    // The three clips are disjoint, so the background is drawn once everywhere (transparency-safe) and
    // cells appear only between the margins.
    if (cutOffDecorationBand) {
        [self drawScrollMarginBackgroundClippedTo:(vertical ? NSMakeRect(0, 0, width, leadingMargin)
                                                            : NSMakeRect(0, 0, leadingMargin, height))];
    }
    if (needClip && trailingClip < fullLength) {
        [self drawScrollMarginBackgroundClippedTo:(vertical ? NSMakeRect(0, trailingClip, width, fullLength - trailingClip)
                                                            : NSMakeRect(trailingClip, 0, fullLength - trailingClip, height))];
    }

    if (needClip) {
        [NSGraphicsContext saveGraphicsState];
        const NSRect clip = vertical ? NSMakeRect(0, leadingClip, width, trailingClip - leadingClip)
                                     : NSMakeRect(leadingClip, 0, trailingClip - leadingClip, height);
        NSRectClip(clip);
    }
    [_style drawTabBar:self
                inRect:self.bounds
              clipRect:rect
            horizontal:horizontalFlag
          withOverflow:_lainOutWithOverflow];
    if (needClip) {
        [NSGraphicsContext restoreGraphicsState];
    }

#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    drawCount++;

    // Log every 10th draw during drag, or if it takes > 1ms
    BOOL isDragging = [[PSMTabDragAssistant sharedDragAssistant] isDragging];
    if (isDragging) {
        double elapsed = (end - start) * 1000;
        double sinceLast = lastDrawTime > 0 ? (start - lastDrawTime) * 1000 : 0;
        if (drawCount % 10 == 0 || elapsed > 1.0) {
            NSLog(@"[PSMTabBar] drawRect #%d took %.2fms (%.1fms since last draw, %d cells)",
                  drawCount, elapsed, sinceLast, (int)[[self cells] count]);
        }
    }
    lastDrawTime = start;

    os_signpost_interval_end(PSMTabBarLog(), OS_SIGNPOST_ID_EXCLUSIVE, "drawRect", "");
#endif
}

- (void)moveTabAtIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destIndex
{
    NSTabViewItem *theItem = [_tabView tabViewItemAtIndex:sourceIndex];
    BOOL reselect = ([_tabView selectedTabViewItem] == theItem);

    id<NSTabViewDelegate> tempDelegate = [_tabView delegate];
    [_tabView setDelegate:nil];
    [theItem retain];
    [_tabView removeTabViewItem:theItem];
    [_tabView insertTabViewItem:theItem atIndex:destIndex];
    [theItem release];

    // sourceIndex/destIndex are tab-view indices. Strip chip cells so the
    // _cells move uses those indices directly (cell index == tab index in a
    // pure tab-cell list), then re-derive chips from the new order.
    [self removeAllTabGroupChipCells];
    id cell = [_cells objectAtIndex:sourceIndex];
    [cell retain];
    [_cells removeObjectAtIndex:sourceIndex];
    [_cells insertObject:cell atIndex:destIndex];
    [cell release];
    [self normalizeTabGroupChipCells];

    [_tabView setDelegate:tempDelegate];

    if (reselect) {
        [_tabView selectTabViewItem:theItem];
    }

    [self update:YES];
}

- (void)update {
    [self update:NO];
}

// Lay out immediately, canceling any in-flight width animation. -update:NO alone
// still takes the animated branch while _animationTimer is running (e.g. right
// after a membership change animates in a chip), which defers frame-setting to
// the timer. Use this when a caller needs final frames before the next draw.
- (void)updateWithoutAnimation {
    if (_animationTimer) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    // Explicit "I need final frames now" (drag, restore, invariant enforcement):
    // stop any collapse/expand slide so -update:NO settles to final frames.
    [self cancelCollapseAnimation];
    [self update:NO];
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self syncTabProgressBars];
}

#pragma mark - Scrollable tab bar

// When this is on, tabs that don't fit stay in the bar and scrolling moves through them instead of the
// extras going into the overflow menu. Applies to whichever orientation is in use; the scroll axis is
// chosen from _orientation.
- (BOOL)tabBarIsScrollable {
    return [iTermPreferences boolForKey:kPreferenceKeyScrollableSideTabBar];
}

- (BOOL)isVerticalOrientation {
    return _orientation == PSMTabBarVerticalOrientation;
}

// Scroll position along the scroll axis (y for a vertical bar, x for a horizontal one), in points.
- (CGFloat)scrollOffset {
    return _scrollOffset;
}

// The inset before the first tab -- top for a vertical bar, left for a horizontal one. This is the
// band the window decorations (stoplights, window number, shortcut indicator) sit in.
- (CGFloat)scrollLeadingMargin {
    return ([self isVerticalOrientation]
            ? [[self style] topMarginForTabBarControl]
            : [[self style] leftMarginForTabBarControl]);
}

// Length of the scrollable tab region along the scroll axis. For a horizontal bar this stops at the
// right margin, where the add-tab button is pinned, so the last tab can scroll fully into the area to
// its left rather than under the button.
- (CGFloat)scrollViewportLength {
    if ([self isVerticalOrientation]) {
        return [self frame].size.height;
    }
    const CGFloat rightMargin = [_style rightMarginForTabBarControlWithOverflow:NO
                                                                    addTabButton:self.showAddTabButton];
    return [self frame].size.width - rightMargin;
}

// Height of one vertical cell. Every cell in a vertical bar is the same height. (Horizontal cells have
// variable widths, so there is no equivalent.)
- (CGFloat)verticalCellHeight {
    return [self genericCellRectWithOverflow:_showAddTabButton].size.height;
}

// How far you can scroll before the last tab reaches the trailing edge; 0 when everything fits.
// _scrollContentExtent is the end of the layout walk, cached by reallyUpdate:.
- (CGFloat)maximumScrollOffset {
    return MAX(0, _scrollContentExtent - [self scrollViewportLength]);
}

- (void)clampScrollOffset {
    _scrollOffset = MAX(0, MIN([self maximumScrollOffset], _scrollOffset));
}

// YES if any part of the frame reaches before the leading margin (under the decorations) or past the
// trailing edge, along the scroll axis.
- (BOOL)frameIsOutsideScrollRegion:(NSRect)frame {
    const CGFloat leading = [self scrollLeadingMargin];
    const CGFloat trailing = [self scrollViewportLength];
    if ([self isVerticalOrientation]) {
        return NSMinY(frame) < leading || NSMaxY(frame) > trailing;
    }
    return NSMinX(frame) < leading || NSMaxX(frame) > trailing;
}

// Paints the bar's own background (and chrome, but no cells) into a scroll-margin strip by asking the
// style to draw the whole tab bar clipped to the strip with an empty cell clip rect. Going through the
// style keeps its background exactly right -- Tahoe's rounded bar excludes the add-button gap, the top
// line spans, etc. -- rather than a hand-rolled fill that would draw a background where the style
// deliberately leaves none.
- (void)drawScrollMarginBackgroundClippedTo:(NSRect)clipRect {
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(clipRect);
    [_style drawTabBar:self
                inRect:self.bounds
              clipRect:NSZeroRect
            horizontal:(_orientation == PSMTabBarHorizontalOrientation)
          withOverflow:_lainOutWithOverflow];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)scrollWheel:(NSEvent *)event {
    if (![self tabBarIsScrollable] || [self maximumScrollOffset] <= 0) {
        // Not scrollable, or everything fits: let the event go on to whatever is behind us.
        [super scrollWheel:event];
        return;
    }
    CGFloat delta;
    CGFloat lineStep;
    if ([self isVerticalOrientation]) {
        // The view is flipped, so scrolling content down means decreasing the offset.
        delta = event.scrollingDeltaY;
        lineStep = [self verticalCellHeight];
    } else {
        // A horizontal bar scrolls on a trackpad horizontal swipe or a shift+vertical wheel. A plain
        // vertical wheel is left for whatever is behind us.
        if (event.scrollingDeltaX != 0) {
            delta = event.scrollingDeltaX;
        } else if ((event.modifierFlags & NSEventModifierFlagShift) && event.scrollingDeltaY != 0) {
            delta = event.scrollingDeltaY;
        } else {
            [super scrollWheel:event];
            return;
        }
        lineStep = _cellOptimumWidth;
    }
    // Precise deltas (trackpad, Magic Mouse) are already in points. Line-based deltas (a notched
    // wheel) are in lines, so scale them to about one tab per line.
    if (!event.hasPreciseScrollingDeltas) {
        delta *= lineStep;
    }
    const CGFloat clamped = MAX(0, MIN([self maximumScrollOffset], _scrollOffset - delta));
    if (clamped == _scrollOffset) {
        return;
    }
    _scrollOffset = clamped;
    // Manual scrolling takes over from the auto-scroll-to-selected behavior.
    _keepSelectedTabInView = NO;
    [self update:NO];
    // Cells moved under a stationary cursor, so tracking areas didn't fire. Re-sync hover/highlight
    // state to the cells now under the mouse.
    [self updateTrackingAreas];
}

// Keeps the active tab on screen -- e.g. after cmd-shift-[ walks past the leading edge, or when a tab
// is selected from somewhere other than the bar. Reads the cell's current (scrolled) frame so it works
// for either orientation and any cell size.
- (void)scrollSelectedTabIntoView {
    if (![self tabBarIsScrollable]) {
        return;
    }
    const NSInteger index = [_cells indexOfObjectPassingTest:^BOOL(PSMTabBarCell *cell, NSUInteger i, BOOL *stop) {
        return [[cell representedObject] isEqualTo:[self->_tabView selectedTabViewItem]];
    }];
    if (index == NSNotFound) {
        return;
    }
    const BOOL vertical = [self isVerticalOrientation];
    const NSRect frame = [[_cells objectAtIndex:index] frame];
    // The on-screen leading edge is (contentPos - offset), so contentPos = frame's leading edge + offset.
    const CGFloat contentPos = (vertical ? NSMinY(frame) : NSMinX(frame)) + _scrollOffset;
    const CGFloat cellLength = (vertical ? NSHeight(frame) : NSWidth(frame));
    const CGFloat leadingMargin = [self scrollLeadingMargin];
    const CGFloat viewportLength = [self scrollViewportLength];

    CGFloat offset = _scrollOffset;
    // The region not hidden by the window decorations is [leadingMargin, viewportLength]. Bring the
    // whole cell into it so an activated tab ends up fully visible rather than tucked under them.
    if (contentPos - offset < leadingMargin) {
        offset = contentPos - leadingMargin;
    } else if ((contentPos + cellLength) - offset > viewportLength) {
        offset = (contentPos + cellLength) - viewportLength;
    } else {
        return;
    }
    offset = MAX(0, MIN([self maximumScrollOffset], offset));
    if (offset == _scrollOffset) {
        return;
    }
    _scrollOffset = offset;
    [self update:NO];
    // Cells moved under a stationary cursor, so tracking areas didn't fire. Re-sync hover/highlight.
    [self updateTrackingAreas];
}

// Per-cell accessory subviews (the activity spinner, custom download progress bars) draw on top of
// drawRect:, so the drawRect clip cannot cover them. A clipping container is not an option here:
// clipsToBounds forces layer backing, which makes the bar render opaque over a transparent window. So
// instead, after every layout pass has positioned its subviews, hide any accessory whose final frame
// reaches above the decoration band or below the bottom edge. Runs last so nothing added or moved
// after _setupCells can leak one out of the scrollable region.
- (void)hideAccessoriesOutsideScrollRegion {
    if (![self tabBarIsScrollable]) {
        return;
    }
    for (PSMTabBarCell *cell in _cells) {
        NSView *indicator = [cell indicator];
        if (indicator.superview == self && [self frameIsOutsideScrollRegion:indicator.frame]) {
            [indicator removeFromSuperview];
        }
    }
    for (NSView *progressBar in _tabProgressBars.objectEnumerator) {
        if (progressBar.superview == self && !progressBar.isHidden &&
            [self frameIsOutsideScrollRegion:progressBar.frame]) {
            progressBar.hidden = YES;
        }
    }
}

- (void)update:(BOOL)animate {
    // This method handles all of the cell layout, and is called when something changes to require
    // the refresh.  This method is not called during drag and drop. See the PSMTabDragAssistant's
    // calculateDragAnimationForTabBar: method, which does layout in that case.

    // Make sure all of our tabs are accounted for before updating. Count
    // only tab cells; chip cells are extra cells with no tab view item.
    NSUInteger tabCellCount = 0;
    for (PSMTabBarCell *cell in _cells) {
        if (![cell isTabGroupChip]) {
            tabCellCount++;
        }
    }
    if ((NSUInteger)[_tabView numberOfTabViewItems] != tabCellCount) {
        // The pending collapse/expand flag is consumed only inside -reallyUpdate:,
        // which this early return skips. Clear it here or it would survive to the
        // next ordinary relayout (a title/activity refresh) and spuriously launch a
        // collapse slide from unrelated frame state.
        _collapseExpandPending = NO;
        return;
    }

    // Hide or show? These do nothing if already in the desired state.
    if ((_hideForSingleTab) && ([_cells count] <= 1)) {
        [self hideTabBar:YES animate:YES];
    } else {
        [self hideTabBar:NO animate:YES];
    }

    [self coalesceToolTipUpdates:^{
        [self reallyUpdate:animate];
    }];
}

- (void)coalesceToolTipUpdates:(void (^)(void))block {
    NSArray<PSMToolTip *> *before = [[_tooltips copy] autorelease];
    _toolTipCoalescing += 1;
    block();
    _toolTipCoalescing -= 1;
    if (_toolTipCoalescing > 0) {
        return;
    }
    if ([_tooltips isEqual:before]) {
        // Copy old objects back so we can have the tags set.
        [_tooltips removeAllObjects];
        [_tooltips addObjectsFromArray:before];
        return;
    }
    [super removeAllToolTips];
    [_tooltips enumerateObjectsUsingBlock:^(PSMToolTip * _Nonnull tip, NSUInteger idx, BOOL * _Nonnull stop) {
        const NSToolTipTag tag = [super addToolTipRect:tip.rect owner:tip.owner userData:tip.data];
        tip.tag = @(tag);
    }];
}

- (void)removeAllToolTips {
    [_tooltips removeAllObjects];
    if (!_toolTipCoalescing) {
        [super removeAllToolTips];
    }
}

- (NSToolTipTag)addToolTipRect:(NSRect)rect owner:(id)owner userData:(nullable void *)data {
    NSNumber *tagNumber = nil;
    if (!_toolTipCoalescing) {
        const NSToolTipTag tag = [super addToolTipRect:rect owner:owner userData:data];
        tagNumber = @(tag);
    }
    [_tooltips addObject:[PSMToolTip toolTipWithRect:rect owner:owner userData:data tag:tagNumber]];
    return tagNumber.integerValue;
}

- (void)removeToolTip:(NSToolTipTag)tag {
    NSUInteger index = [_tooltips indexOfObjectPassingTest:^BOOL(PSMToolTip * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.tag != nil && obj.tag.integerValue == tag;
    }];
    if (index != NSNotFound) {
        [_tooltips removeObjectAtIndex:index];
    }

    if (!_toolTipCoalescing) {
        [super removeToolTip:tag];
    }
}

- (void)reallyUpdate:(BOOL)animateFlag {
    [self _removeCellTrackingRects];

    NSLineBreakMode truncationStyle = [self truncationStyle];

    // Update cells' settings in case they changed.
    for (PSMTabBarCell *cell in _cells) {
        cell.truncationStyle = truncationStyle;
        cell.hasCloseButton = _hasCloseButton;
        [cell updateForStyle];
        cell.isCloseButtonSuppressed = [self disableTabClose];
        // Remove highlight if cursor is no longer in cell. Could happen if
        // cell moves because of added/removed tab. Tracking rects aren't smart
        // enough to handle this.
        [cell updateHighlight];
        [cell updateIndicators];
    }

    // If the number of rows changed (two-row tab bar crossing the single-row
    // capacity), the bar's height must change. Tab adds don't otherwise re-fit
    // the window when the bar is already visible, so ask the delegate to
    // recompute the height. Deferred to avoid reentrant layout.
    //
    // Only relevant when the feature is on: horizontalRowCount is always 1
    // otherwise, so gating here keeps the first layout of every window from
    // firing a full window-chrome rebuild for the 100% of users who have the
    // setting off. (_lastLaidOutHorizontalRowCount is also seeded to 1 in init.)
    const NSInteger currentRowCount = [self horizontalRowCount];
    if ([iTermAdvancedSettingsModel twoRowTabBar] &&
        currentRowCount != _lastLaidOutHorizontalRowCount) {
        _lastLaidOutHorizontalRowCount = currentRowCount;
        // Adopt the delegate's final desired height synchronously so the cell
        // layout below uses the correct per-row height instead of dividing the
        // still-single-row height across two rows (which draws both at half height
        // for one frame). Using the delegate's value — rather than a proportional
        // guess — matches the real two-row height so there's no overshoot; the view
        // frame and window fit catch up via the async callback.
        if ([_delegate respondsToSelector:@selector(tabViewDesiredTabBarHeight:)]) {
            const CGFloat target = [_delegate tabViewDesiredTabBarHeight:_tabView];
            if (target > 0) {
                self.height = target;
            }
        }
        if ([_delegate respondsToSelector:@selector(tabViewDidChangeDesiredHeight:)]) {
            NSTabView *tabView = _tabView;
            id<PSMTabBarControlDelegate> delegate = _delegate;
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate tabViewDidChangeDesiredHeight:tabView];
            });
        }
    }

    // Calculate number of cells to fit in the control and cell widths.
    const NSInteger cellCount = [_cells count];
    // The width animation in -_animateCells: only knows how to slide cells along a
    // single row, so it can't run in two-row mode. (The collapse/expand animator
    // above is fine: it lays out every frame via -_setupCells:, which wraps rows.)
    // An -_animateCells: run already in flight when we cross into two rows would
    // otherwise keep going via the _animationTimer clause below and never lay out
    // the second row, so cancel it here.
    const BOOL singleRow = ([self horizontalRowCount] == 1);
    if (!singleRow && _animationTimer != nil) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    // A collapse/expand toggle -- or a chip cell being inserted/removed -- asks
    // (once) for the dedicated collapse animator, which lays out every frame via
    // -_setupCells: (correct per-frame positions, unlike -_animateCells:) and
    // handles both scrollable and non-scrollable horizontal bars.
    const BOOL collapseExpand = _collapseExpandPending;
    _collapseExpandPending = NO;
    if (_collapseAnimating && !collapseExpand) {
        if ((NSInteger)_cells.count == (NSInteger)_collapseStartWidths.count &&
            NSEqualSizes(self.bounds.size, _collapseAnimBounds)) {
            // An incidental relayout arrived mid-slide with the SAME cell set and
            // the SAME bar size -- e.g. a revealed member's session refreshing its
            // title/activity fires a plain -update. Keep the slide going: re-apply
            // the current frame so nothing snaps. Explicit snaps (drag, restore,
            // invariant) come via -updateWithoutAnimation, which cancels the slide
            // first, so they don't reach here. (This is why expand -- which reveals
            // tabs -- used to jump to its final frame while collapse never did.)
            [self layoutCollapseAnimationFrame];
            return;
        }
        // The cell set changed (tab added/removed/reordered) or the bar's size
        // changed (window resize, fullscreen, toolbelt): the slide's captured
        // start/target widths no longer fit, so cancel and let the layout below
        // settle to the new geometry.
        [self cancelCollapseAnimation];
    }
    if ([self orientation] == PSMTabBarHorizontalOrientation) {
        if ([self tabBarIsScrollable]) {
            [self layoutScrollableHorizontalTabsWithCellCount:cellCount animate:collapseExpand];
        } else if (collapseExpand && cellCount > 0) {
            // Animate toward the POST-toggle arrangement. _lainOutWithOverflow
            // still holds the PRE-toggle overflow state (it is only written when a
            // layout completes, see finishUpdateWithRegularWidths:), and the two
            // overflow variants differ (withOverflow reserves a wider right margin
            // and drops tail cells). Reusing the cached flag would slide toward the
            // wrong widths while the settle lands on the other variant, snapping
            // tail tabs into the overflow menu at the end. Pick the variant the
            // settle will choose.
            [self startCollapseAnimationWithTargetWidths:[self settledHorizontalCellWidths]];
            return;
        } else if (singleRow && (animateFlag || _animationTimer != nil) && cellCount > 0) {
            // Animate only on horizontal tab bars.
            if (_animationTimer) {
                [_animationTimer invalidate];
            }

            _animationDelta = 0.0f;
            _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                               target:self
                                                             selector:@selector(_animateCells:)
                                                             userInfo:[self cellWidthsForHorizontalArrangementWithOverflow:_lainOutWithOverflow]
                                                              repeats:YES];
            return;
        } else {
            [self finishUpdateWithRegularWidths:[self cellWidthsForHorizontalArrangementWithOverflow:NO]
                             widthsWithOverflow:[self cellWidthsForHorizontalArrangementWithOverflow:YES]];
        }
    } else {
        // Vertical orientation
        if (collapseExpand && cellCount > 0) {
            [self startVerticalCollapseAnimation];
            return;
        }
        CGFloat currentOrigin = [[self style] topMarginForTabBarControl];
        NSRect cellRect = [self genericCellRectWithOverflow:(NO || _showAddTabButton)];
        const CGFloat tabHeight = cellRect.size.height;
        NSMutableArray *newOrigins = [NSMutableArray arrayWithCapacity:cellCount];

        if ([self tabBarIsScrollable]) {
            // Give every cell an origin, shifted up by the scroll offset. Cells above or below the
            // visible rect just get off-screen frames and are clipped when drawn (see the drawRect:
            // clip), so nothing lands in the overflow menu -- the scroll wheel reaches them instead.
            // Group chip cells are short; everything else uses the tab height.
            CGFloat totalHeight = 0;
            for (PSMTabBarCell *cell in _cells) {
                if (cell.isCollapsedHidden) {
                    continue;  // hidden by a collapsed group: no height
                }
                totalHeight += cell.isTabGroupChip ? [self heightOfTabGroupChipCell:cell] : tabHeight;
            }
            _scrollContentExtent = [[self style] topMarginForTabBarControl] + totalHeight;
            [self clampScrollOffset];
            currentOrigin -= _scrollOffset;
            for (int i = 0; i < cellCount; ++i) {
                [newOrigins addObject:@(currentOrigin)];
                if (_cells[i].isCollapsedHidden) {
                    continue;  // zero height: keep this origin but don't advance
                }
                currentOrigin += _cells[i].isTabGroupChip ? [self heightOfTabGroupChipCell:_cells[i]] : tabHeight;
            }
        } else {
            for (int i = 0; i < cellCount; ++i) {
                if (_cells[i].isCollapsedHidden) {
                    // Zero height, index-aligned origin, never breaks the walk.
                    [newOrigins addObject:@(currentOrigin)];
                    continue;
                }
                const CGFloat h = _cells[i].isTabGroupChip ? [self heightOfTabGroupChipCell:_cells[i]] : tabHeight;
                if (currentOrigin + h <= [self frame].size.height) {
                    [newOrigins addObject:@(currentOrigin)];
                    currentOrigin += h;
                } else {
                    // Out of room; the rest go into overflow. Reclaim a drawn
                    // cell-height for the bottom-pinned overflow button. A trailing
                    // collapsed member has zero height, so removing it frees no
                    // vertical space (the last visible cell would still end at
                    // currentOrigin and overlap the overflow control): pop past any
                    // trailing collapsed members to the last real origin.
                    if ([newOrigins count] > 0 && [self frame].size.height - currentOrigin < h) {
                        while (newOrigins.count > 0 &&
                               _cells[newOrigins.count - 1].isCollapsedHidden) {
                            [newOrigins removeLastObject];
                        }
                        if (newOrigins.count > 0) {
                            [newOrigins removeLastObject];
                        }
                    }
                    break;
                }
            }
        }
        [self finishUpdateWithRegularWidths:newOrigins widthsWithOverflow:newOrigins];
    }

    [self syncTabProgressBars];
    [self hideAccessoriesOutsideScrollRegion];
    if (_keepSelectedTabInView && !_adjustingScrollForSelection) {
        // Re-check after each layout so a tab whose width settles asynchronously ends up fully visible.
        _adjustingScrollForSelection = YES;
        [self scrollSelectedTabIntoView];
        _adjustingScrollForSelection = NO;
    }
    [self setNeedsDisplay:YES];
}

+ (NSArray<PSMTabBarCell *> *)cellsByInsertingTabGroupChipsInto:(NSArray<PSMTabBarCell *> *)tabCells
                                                   controlView:(PSMTabBarControl *)controlView {
    // On a placeholder-free cell list the drag variant's placeholder branch
    // never fires, so the two entry points share one implementation and the
    // chip-minting rules cannot drift between the normalized and mid-drag
    // worlds.
    return [self cellsByInsertingDragChipsInto:tabCells controlView:controlView];
}

+ (NSArray<PSMTabBarCell *> *)cellsByInsertingDragChipsInto:(NSArray<PSMTabBarCell *> *)cells
                                                controlView:(PSMTabBarControl *)controlView {
    NSMutableArray<PSMTabBarCell *> *result = [NSMutableArray array];
    NSString *runID = nil;
    for (PSMTabBarCell *cell in cells) {
        if ([cell isTabGroupChip]) {
            // Stray chip from a prior pass: drop it, we re-derive below.
            continue;
        }
        if ([cell isPlaceholder]) {
            // Placeholders are transparent to run detection so a group split
            // only by placeholders (e.g. the dragged tab's gap) stays one run.
            // Exception: the dragged member's drop-slot placeholder carries its
            // group id, so it anchors the run (and its chip) at that slot rather
            // than letting the chip jump past it to the next real member.
            NSString *pgid = [cell tabGroupIdentifier];
            if (pgid.length > 0 && ![pgid isEqualToString:runID]) {
                PSMTabBarCell *chip = [[[PSMTabBarCell alloc] initWithControlView:controlView] autorelease];
                [chip setIsTabGroupChip:YES];
                [chip setTabGroupIdentifier:pgid];
                [result addObject:chip];
                runID = pgid;
            }
            [result addObject:cell];
            continue;
        }
        NSString *gid = [cell tabGroupIdentifier];
        const BOOL grouped = (gid.length > 0);
        if (grouped && ![gid isEqualToString:runID]) {
            PSMTabBarCell *chip = [[[PSMTabBarCell alloc] initWithControlView:controlView] autorelease];
            [chip setIsTabGroupChip:YES];
            [chip setTabGroupIdentifier:gid];
            [result addObject:chip];
        }
        runID = grouped ? gid : nil;
        [result addObject:cell];
    }
    return result;
}

+ (NSInteger)cellIndexForTabIndex:(NSInteger)tabIndex inCells:(NSArray<PSMTabBarCell *> *)cells {
    NSInteger tab = -1;
    for (NSInteger i = 0; i < (NSInteger)cells.count; i++) {
        if ([cells[i] isTabGroupChip]) {
            continue;
        }
        tab++;
        if (tab == tabIndex) {
            return i;
        }
    }
    return (NSInteger)cells.count;
}

+ (NSInteger)tabIndexForCellIndex:(NSInteger)cellIndex inCells:(NSArray<PSMTabBarCell *> *)cells {
    if (cellIndex < 0 || cellIndex >= (NSInteger)cells.count) {
        return NSNotFound;
    }
    if ([cells[cellIndex] isTabGroupChip]) {
        return NSNotFound;
    }
    NSInteger tab = -1;
    for (NSInteger i = 0; i <= cellIndex; i++) {
        if (![cells[i] isTabGroupChip]) {
            tab++;
        }
    }
    return tab;
}

// Lays out a horizontal bar in scrollable mode. If the tabs at their natural widths overflow the bar,
// give every cell its natural width and scroll (no overflow menu, no width animation). If they fit,
// fall back to the normal fit layout so the bar looks exactly as it does without scrolling.
- (void)layoutScrollableHorizontalTabsWithCellCount:(NSInteger)cellCount
                                            animate:(BOOL)animate {
    if (_animationTimer && !animate) {
        // A width animation from a prior state would fight the scroll layout,
        // unless we are the ones starting a collapse/expand animation now.
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    NSArray<NSNumber *> *widths = [self naturalHorizontalCellWidths];
    const CGFloat spacing = _style.intercellSpacing;
    CGFloat sum = 0;
    for (NSNumber *w in widths) {
        sum += w.doubleValue;
    }
    // Collapsed members contribute 0 width (naturalHorizontalCellWidths) and no
    // intercell spacing, so count only non-collapsed cells for the spacing budget.
    const NSInteger visibleCellCount = [self numberOfCellsContributingIntercellSpacing];
    const CGFloat totalTabWidth = sum + spacing * MAX(0, (CGFloat)(visibleCellCount - 1));
    NSArray<NSNumber *> *targetWidths;
    NSArray<NSNumber *> *overflowWidths;
    if (cellCount > 0 && totalTabWidth > [self availableCellWidthWithOverflow:NO]) {
        // Overflows: natural widths + scroll.
        _scrollContentExtent = [[self style] leftMarginForTabBarControl] + totalTabWidth;
        [self clampScrollOffset];
        targetWidths = widths;
        overflowWidths = widths;
    } else {
        // Everything fits: keep the normal look (stretch/optimal), no scroll.
        _scrollContentExtent = 0;
        [self clampScrollOffset];
        targetWidths = [self cellWidthsForHorizontalArrangementWithOverflow:NO];
        overflowWidths = [self cellWidthsForHorizontalArrangementWithOverflow:YES];
    }
    if (animate && cellCount > 0) {
        [self startCollapseAnimationWithTargetWidths:targetWidths];
    } else {
        [self finishUpdateWithRegularWidths:targetWidths widthsWithOverflow:overflowWidths];
    }
}

// Begin (or retarget) the collapse/expand width animation. Interpolates each
// cell's width from its current value to `targetWidths` and re-lays-out via
// -_setupCells: each frame, so scroll, chip height, cross-axis, and contiguity
// stay correct. Chip cells snap to their target width immediately: a group chip
// is a label, not a tab, and tweening its width oversizes the colored area
// beside the name mid-slide. The single target array (which already reflects the
// post-change fit/stretch layout) makes the group shrink and the survivors grow
// in one pass rather than two.
- (void)startCollapseAnimationWithTargetWidths:(NSArray<NSNumber *> *)targetWidths {
    // Cancel any width animation from the other animator so they don't fight.
    if (_animationTimer) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    NSMutableArray<NSNumber *> *start = [NSMutableArray arrayWithCapacity:_cells.count];
    for (NSInteger i = 0; i < (NSInteger)_cells.count; i++) {
        [start addObject:@(NSWidth(_cells[i].frame))];
    }
    NSMutableArray<NSNumber *> *target = [[targetWidths mutableCopy] autorelease];
    // The caller's width array is an index-aligned PREFIX of _cells: on a
    // non-scrollable bar that overflows it stops at the fit boundary (the tail
    // goes to the "..." menu). The remap below and the per-frame interpolation
    // index it by full _cells position, so pad it to _cells.count to avoid an
    // out-of-range access. A cell past the boundary is not shown, so its
    // interpolation target is 0; the settled layout is recomputed fresh at
    // -finishCollapseAnimation (via -update:NO), which maps the tail back into
    // the overflow menu.
    while ((NSInteger)target.count < (NSInteger)_cells.count) {
        [target addObject:@0];
    }

    // The chip tweens its width like any other cell: its start is its current
    // frame (the WIDE collapsed width when expanding, the NARROW expanded width
    // when collapsing) and its target is the settled width the caller supplied
    // (narrow when expanding, wide when collapsing). So a chip gradually shrinks as
    // its members grow out of it (expand) and gradually grows as they shrink in
    // (collapse), with the group's total width continuous at both endpoints -- no
    // solid-chip snap, and no delta remap that would also wrongly resize sibling
    // groups the whole-bar relayout happens to be shrinking. Mid-slide the chip is
    // wider than its name needs, so the group-color band between the name and the
    // first tab is briefly wider; it narrows to its settled size as the slide ends.

    // MRR: retain-on-assign (copy), releasing any previous arrays first. The
    // settled layout is recomputed fresh by -finishCollapseAnimation (via
    // -update:NO), so there is nothing else to stash here.
    [_collapseStartWidths release];
    _collapseStartWidths = [start copy];
    [_collapseTargetWidths release];
    _collapseTargetWidths = [target copy];
    _collapseAnimT = 0.0;
    _collapseAnimating = YES;
    _collapseAnimBounds = self.bounds.size;
    if (_collapseAnimTimer) {
        [_collapseAnimTimer invalidate];
    }
    [self hideTabProgressBarsForCollapseAnimation];
    // Lay out the first (t=0) frame immediately so nothing blinks, then tick.
    [self layoutCollapseAnimationFrame];
    _collapseAnimTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                          target:self
                                                        selector:@selector(_animateCollapse:)
                                                      userInfo:nil
                                                       repeats:YES];
}

// Smoothstep ease so the slide starts and ends gently.
static CGFloat PSMCollapseEase(CGFloat t) {
    if (t <= 0) {
        return 0;
    }
    if (t >= 1) {
        return 1;
    }
    return t * t * (3.0 - 2.0 * t);
}

- (void)layoutCollapseAnimationFrame {
    if (_collapseVertical) {
        [self layoutVerticalCollapseFrame];
        return;
    }
    const CGFloat eased = PSMCollapseEase(_collapseAnimT);
    NSMutableArray<NSNumber *> *widths = [NSMutableArray arrayWithCapacity:_cells.count];
    for (NSInteger i = 0; i < (NSInteger)_cells.count; i++) {
        // Interpolate every cell (including the chip) from its current width to
        // the target. The chip's start width is its current frame -- collapsed
        // (wide, with the count+chevron room) when expanding, expanded (narrow)
        // when collapsing -- so the slide begins at the true starting size and no
        // neighbor jumps: expand shrinks the chip as members grow, collapse widens
        // it as members shrink, both monotonic.
        const CGFloat a = (i < (NSInteger)_collapseStartWidths.count) ? _collapseStartWidths[i].doubleValue : 0;
        const CGFloat b = (i < (NSInteger)_collapseTargetWidths.count) ? _collapseTargetWidths[i].doubleValue : 0;
        [widths addObject:@(a + (b - a) * eased)];
    }
    if ([self tabBarIsScrollable]) {
        // The interpolated widths differ from the settled extent that
        // -layoutScrollableHorizontalTabs... clamped to before the slide, so keep
        // the scroll geometry valid each frame (mirrors the vertical path); a bar
        // scrolled to the right would otherwise gap or jump mid-slide.
        CGFloat sum = 0;
        NSInteger laidOut = 0;
        for (NSInteger i = 0; i < (NSInteger)_cells.count; i++) {
            const CGFloat w = widths[i].doubleValue;
            sum += w;
            // A collapsed member with a zero interpolated width is not laid out
            // (no cell, no intercell spacing); everything else advances.
            if (!(_cells[i].isCollapsedHidden && w <= 0)) {
                laidOut++;
            }
        }
        const CGFloat spacing = _style.intercellSpacing;
        _scrollContentExtent = [[self style] leftMarginForTabBarControl] + sum +
                               spacing * MAX(0, (CGFloat)(laidOut - 1));
        [self clampScrollOffset];
    }
    // The interpolated width > 0 keeps a collapsing member laid out (not zeroed)
    // by -_setupCells: so it slides shut/open.
    [self _setupCells:widths];
    [self setNeedsDisplay:YES];
}

- (void)_animateCollapse:(NSTimer *)timer {
    // A drag lays the bar out itself (the drag assistant inserts placeholder
    // cells and sets frames); if a drag started mid-slide, keeping the timer
    // running would re-set every frame each tick and fight it. Stop the slide as
    // soon as a drag is in progress. This covers both the source bar and a
    // drop-target bar, without settling (the drag's own layout takes over).
    if ([[PSMTabDragAssistant sharedDragAssistant] isDragging]) {
        [self cancelCollapseAnimation];
        return;
    }
    // ~0.18s total (1/60s per tick).
    _collapseAnimT += (1.0 / 60.0) / 0.18;
    if (_collapseAnimT >= 1.0) {
        [self finishCollapseAnimation];
        return;
    }
    [self layoutCollapseAnimationFrame];
}

// Vertical collapse/expand. A vertical bar's cells are a uniform-width column
// stacked by origin; only the member heights change. -adjustedCellRect: would
// clobber a partial height, so the frames are set directly here (no tracking
// rects -- a full layout at -finish restores them). No chip-width delta exists
// (the vertical chip is always one tab row tall), so this is a straight height
// interpolation with no first-member remap.
- (void)startVerticalCollapseAnimation {
    if (_animationTimer) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    const CGFloat tabHeight = [self verticalCellHeight];  // full slot advance for a tab
    // Reference geometry from a settled, visible tab: shared x/width (all vertical
    // rows share them) plus the DRAWN height, which -adjustedCellRect: makes
    // shorter than the slot advance. That difference is the inter-cell divider gap
    // the settled layout leaves; matching it keeps static cells perfectly still
    // and makes the finish seam-free.
    CGFloat refX = 0;
    CGFloat refW = NSWidth(self.frame);
    CGFloat refDrawnH = tabHeight;
    const NSRect refCell = [PSMTabBarControl firstFullSizeTabCellFrameInCells:_cells];
    if (!NSIsEmptyRect(refCell)) {
        refX = NSMinX(refCell);
        refW = NSWidth(refCell);
        refDrawnH = NSHeight(refCell);
    }
    _collapseVerticalGap = MAX(0.0, tabHeight - refDrawnH);
    // Interpolate SLOT advances (not drawn heights): a visible cell's slot is its
    // full advance, a collapsed member's is 0. Start is keyed on whether the cell
    // is currently visible, target on its post-change collapsed state -- so a
    // STATIC cell (visible before and after) has start == target and does not move
    // or resize while another group animates. The drawn height each frame is the
    // slot minus the divider gap.
    NSMutableArray<NSNumber *> *start = [NSMutableArray arrayWithCapacity:_cells.count];
    NSMutableArray<NSNumber *> *target = [NSMutableArray arrayWithCapacity:_cells.count];
    for (PSMTabBarCell *cell in _cells) {
        const CGFloat fullSlot = cell.isTabGroupChip ? [self heightOfTabGroupChipCell:cell] : tabHeight;
        [start addObject:@((NSHeight(cell.frame) > 0) ? fullSlot : 0.0)];
        [target addObject:@(cell.isCollapsedHidden ? 0.0 : fullSlot)];
    }
    [_collapseStartWidths release];
    _collapseStartWidths = [start copy];
    [_collapseTargetWidths release];
    _collapseTargetWidths = [target copy];
    _collapseVerticalCellX = refX;
    _collapseVerticalCellWidth = refW;
    _collapseVertical = YES;
    _collapseAnimT = 0.0;
    _collapseAnimating = YES;
    _collapseAnimBounds = self.bounds.size;
    if (_collapseAnimTimer) {
        [_collapseAnimTimer invalidate];
    }
    [self hideTabProgressBarsForCollapseAnimation];
    [self layoutCollapseAnimationFrame];
    _collapseAnimTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                          target:self
                                                        selector:@selector(_animateCollapse:)
                                                          userInfo:nil
                                                         repeats:YES];
}

- (void)layoutVerticalCollapseFrame {
    const CGFloat eased = PSMCollapseEase(_collapseAnimT);
    const NSInteger n = _cells.count;
    NSMutableArray<NSNumber *> *slots = [NSMutableArray arrayWithCapacity:n];
    CGFloat total = 0;
    for (NSInteger i = 0; i < n; i++) {
        const CGFloat a = (i < (NSInteger)_collapseStartWidths.count) ? _collapseStartWidths[i].doubleValue : 0;
        const CGFloat b = (i < (NSInteger)_collapseTargetWidths.count) ? _collapseTargetWidths[i].doubleValue : 0;
        const CGFloat slot = a + (b - a) * eased;
        [slots addObject:@(slot)];
        total += slot;
    }
    // Track the interpolated content height so the scroll offset stays valid as
    // the column grows/shrinks under a scrolled vertical bar.
    _scrollContentExtent = [[self style] topMarginForTabBarControl] + total;
    [self clampScrollOffset];
    CGFloat origin = [[self style] topMarginForTabBarControl] - _scrollOffset;
    for (NSInteger i = 0; i < n; i++) {
        const CGFloat slot = slots[i].doubleValue;
        // Advance by the full slot (matching the settled layout), but draw the
        // cell one divider-gap shorter, so the settled frames are reproduced
        // exactly at the end and static cells never move.
        const CGFloat drawnH = MAX(0.0, slot - _collapseVerticalGap);
        [_cells[i] setFrame:NSMakeRect(_collapseVerticalCellX, origin, _collapseVerticalCellWidth, drawnH)];
        origin += slot;
    }
    [self setNeedsDisplay:YES];
}

- (BOOL)collapseAnimating {
    return _collapseAnimating;
}

// Stop the collapse/expand slide immediately WITHOUT settling the layout. The
// caller is expected to lay out right after (e.g. -updateWithoutAnimation snaps
// to final frames). Safe to call when no animation is running.
- (void)cancelCollapseAnimation {
    [_collapseAnimTimer invalidate];
    _collapseAnimTimer = nil;
    _collapseAnimating = NO;
    _collapseVertical = NO;
    [_collapseStartWidths release];
    _collapseStartWidths = nil;
    [_collapseTargetWidths release];
    _collapseTargetWidths = nil;
}

- (void)finishCollapseAnimation {
    // Same teardown as -cancelCollapseAnimation (one owner of the release/reset of
    // the collapse-animation state), then settle. Reuse it so a future field added
    // to that state is torn down in one place, not two.
    [self cancelCollapseAnimation];
    // Settle to the true final layout with a fresh non-animated relayout. This
    // recomputes the settled widths -- including BOTH the fit and with-overflow
    // variants for a non-scrollable bar, so the last tab can't overlap the
    // overflow chevron when an expand pushes the bar into overflow -- and the
    // scroll geometry for a scrollable bar. With _collapseAnimating now NO,
    // -_setupCells: zeroes collapsed members again. (The horizontal slide set
    // frames via -_setupCells:, the vertical directly; either way this re-lays
    // out from the settled state.)
    [self update:NO];
    [self setNeedsDisplay:YES];
}

// Widths for a horizontal bar in scrollable mode. Pinned cells get the pinned width. For the rest, the
// scrollable tab width governs the size: when uneven tab widths are allowed (sizeCellsToFit) each cell
// gets its natural (content) width, clamped to [scrollableTabWidth, cellMaxWidth]; otherwise every cell
// gets the uniform scrollableTabWidth. This is a separate setting from the non-scrollable bar's optimum
// width, so a scrollable bar can use narrower tabs. Always _cells.count entries, so nothing overflows.
// Whether any first-class group chip cell is present. When true, a
// horizontal bar uses the natural-width (scrollable) layout rather than
// shrink-to-fit, so chip cells slot into the per-cell width array without
// threading through the fit-distribution math.
- (BOOL)hasTabGroupChipCells {
    for (PSMTabBarCell *cell in _cells) {
        if (cell.isTabGroupChip) {
            return YES;
        }
    }
    return NO;
}

- (CGFloat)effectiveTabGroupRunOutset {
    if (![self hasTabGroupChipCells]) {
        return 0;
    }
    if (![_style respondsToSelector:@selector(tabGroupRunOutset)]) {
        return 0;
    }
    return [_style tabGroupRunOutset];
}

// Measured chip sizes keyed by style class + group name. The measurement
// (Core Text sizing) runs inside layout passes that ask for each chip's size
// several times per update; the size depends only on the style and the name,
// so cache it. A rename produces a different key, so nothing to invalidate.
static NSCache<NSString *, NSNumber *> *PSMChipSizeCache(void) {
    static NSCache<NSString *, NSNumber *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 512;
    });
    return cache;
}

// One scanner for the contiguous run of same-group members after the chip at
// `chipIndex` -- collapse detection, chip-width sizing, chip enumeration, and the
// collapse animator all call this so the "skip placeholders, break on a chip or a
// different group id" traversal stays in lockstep. `firstMember` is -1 when there
// are none.
typedef struct {
    NSInteger firstMember;
    NSInteger memberCount;
    BOOL allCollapsed;   // every member is collapsed-hidden
    BOOL anyCollapsed;   // at least one member is collapsed-hidden
    BOOL anySized;       // at least one member has a nonzero-width frame (mid-slide)
} PSMTabGroupRun;

- (PSMTabGroupRun)tabGroupRunAfterChipAtIndex:(NSInteger)chipIndex {
    PSMTabGroupRun run = { -1, 0, YES, NO, NO };
    if (chipIndex < 0 || chipIndex >= (NSInteger)_cells.count) {
        return run;
    }
    PSMTabBarCell *chip = _cells[chipIndex];
    NSString *gid = chip.tabGroupIdentifier;
    if (![chip isTabGroupChip] || gid.length == 0) {
        return run;
    }
    for (NSInteger j = chipIndex + 1; j < (NSInteger)_cells.count; j++) {
        PSMTabBarCell *c = _cells[j];
        if (c.isPlaceholder) {
            continue;
        }
        if (c.isTabGroupChip || ![c.tabGroupIdentifier isEqualToString:gid]) {
            break;
        }
        if (run.firstMember < 0) {
            run.firstMember = j;
        }
        run.memberCount++;
        if (c.isCollapsedHidden) {
            run.anyCollapsed = YES;
        } else {
            run.allCollapsed = NO;
        }
        if (NSWidth(c.frame) > 0) {
            run.anySized = YES;
        }
    }
    return run;
}

// YES if `chip` heads a fully collapsed run (all its members are hidden), and
// fills in the member count. Mirrors -enumerateCollapsedTabGroupChipsWithBlock:
// for the layout paths that need to size a chip before drawing.
// Width of a horizontal group-chip cell at `index` (its name, via the data
// source). A collapsed chip is wider: it also shows a member-count badge and a
// chevron. Index-based so the layout loops, which already have the index in hand,
// don't pay an -indexOfObject: rescan (which made each width pass O(cells^2)).
- (CGFloat)widthOfTabGroupChipCellAtIndex:(NSInteger)index {
    PSMTabBarCell *cell = _cells[index];
    const PSMTabGroupRun run = [self tabGroupRunAfterChipAtIndex:index];
    return [self widthOfTabGroupChipCellForIdentifier:cell.tabGroupIdentifier
                                            collapsed:(run.memberCount > 0 && run.allCollapsed)
                                          memberCount:run.memberCount];
}

// Chip width from explicit group state, so a SYNTHESIZED chip (a drag chip that
// is not in _cells, and so cannot be found by index) can still be sized at its
// COLLAPSED width -- the collapsed chip reserves member-count badge + chevron room
// and is wider than the name-only expanded chip, so sizing it name-only makes the
// dragged group jump wider on drop.
- (CGFloat)widthOfTabGroupChipCellForIdentifier:(NSString *)identifier
                                      collapsed:(BOOL)collapsed
                                    memberCount:(NSInteger)memberCount {
    id<PSMTabGroup> group = [self.tabGroupDataSource tabGroupWithIdentifier:identifier];
    NSString *name = group ? group.name : @"";
    if (collapsed && memberCount > 0) {
        return [self collapsedChipCellWidthForGroupName:name memberCount:memberCount];
    }
    return [self chipCellWidthForGroupName:name];
}

- (CGFloat)widthOfTabGroupChipCell:(PSMTabBarCell *)cell {
    const NSInteger idx = [_cells indexOfObject:cell];
    if (idx == NSNotFound) {
        id<PSMTabGroup> group = [self.tabGroupDataSource tabGroupWithIdentifier:cell.tabGroupIdentifier];
        return [self chipCellWidthForGroupName:(group ? group.name : @"")];
    }
    return [self widthOfTabGroupChipCellAtIndex:idx];
}

// Width of a collapsed group-chip cell, in this bar's style.
- (CGFloat)collapsedChipCellWidthForGroupName:(NSString *)name memberCount:(NSInteger)count {
    name = name ?: @"";
    NSString *key = [NSString stringWithFormat:@"WC:%@:%ld:%@",
                     [(NSObject *)self.style class], (long)count, name];
    NSNumber *cached = [PSMChipSizeCache() objectForKey:key];
    if (cached) {
        return cached.doubleValue;
    }
    CGFloat width;
    if ([self.style respondsToSelector:@selector(tabGroupCollapsedChipCellWidthForName:memberCount:)]) {
        width = [self.style tabGroupCollapsedChipCellWidthForName:name memberCount:count];
    } else {
        // Fallback: the name-only width (the count/chevron may crowd, but the
        // basic styles don't draw a collapsed chip anyway).
        width = [self chipCellWidthForGroupName:name];
    }
    [PSMChipSizeCache() setObject:@(width) forKey:key];
    return width;
}

// Width of a chip cell for a group with the given name, in this bar's style.
// Split from -widthOfTabGroupChipCell: so a drag can size an INCOMING group's
// chip (whose definition rides tabs in another window and is unknown to this
// bar's data source).
- (CGFloat)chipCellWidthForGroupName:(NSString *)name {
    name = name ?: @"";
    NSString *key = [NSString stringWithFormat:@"W:%@:%@", [(NSObject *)self.style class], name];
    NSNumber *cached = [PSMChipSizeCache() objectForKey:key];
    if (cached) {
        return cached.doubleValue;
    }
    // A style that draws its own run decoration (e.g. Tahoe) reserves extra
    // width for the name capsule plus the colored area between it and the first
    // tab; others use the basic chip width.
    CGFloat width;
    if ([self.style respondsToSelector:@selector(tabGroupChipCellWidthForName:)]) {
        width = [self.style tabGroupChipCellWidthForName:name];
    } else {
        width = [PSMTabGroupChipView preferredWidthForName:name];
    }
    [PSMChipSizeCache() setObject:@(width) forKey:key];
    return width;
}

// The width `tabCount` incoming tabs (plus a group chip of `chipWidth`, 0 for
// a single tab) would occupy once dropped into this horizontal bar. Used to
// size the drop-slot preview: a unit dragged from a wide window must open a
// slot at THIS bar's on-drop size, not the size it had at home.
- (CGFloat)expectedDropExtentForIncomingTabCount:(NSInteger)tabCount
                                       chipWidth:(CGFloat)chipWidth {
    if (tabCount <= 0 || _orientation != PSMTabBarHorizontalOrientation) {
        return 0;
    }
    CGFloat perTab;
    if ([self tabBarIsScrollable]) {
        // Scrollable bars give every tab the uniform scrollable width (the
        // fit-to-content variant still clamps to at least this).
        perTab = _scrollableTabWidth;
    } else {
        NSInteger existing = 0;
        for (PSMTabBarCell *cell in _cells) {
            // A collapsed-hidden member contributes 0 width and 0 intercell
            // spacing to the real layout (like every other width builder), so it
            // must not count here or the reserved spacing and per-tab denominator
            // inflate and the drop slot comes out narrower than the settled size.
            if (![cell isTabGroupChip] && ![cell isPlaceholder] && ![cell isCollapsedHidden]) {
                existing++;
            }
        }
        const CGFloat spacing = _style.intercellSpacing;
        const CGFloat available = MAX(0, [self availableCellWidthWithOverflow:NO] - chipWidth -
                                      spacing * (CGFloat)(existing + tabCount));
        perTab = available / (CGFloat)MAX((NSInteger)1, existing + tabCount);
        if (!self.stretchCellsToFit) {
            perTab = MIN(perTab, _cellOptimumWidth);
        }
        perTab = MAX(_cellMinWidth, perTab);
    }
    return chipWidth + perTab * (CGFloat)tabCount;
}

// Height reserved for a group chip cell on a vertical bar (style-aware, like
// -widthOfTabGroupChipCell: for horizontal).
- (CGFloat)heightOfTabGroupChipCell:(PSMTabBarCell *)cell {
    // A style that draws its own run decoration renders the chip as a one-row
    // header band, so on a vertical bar it should be exactly as tall as a normal
    // tab row. Using the style's name-based height (sized for the horizontal
    // name capsule) would make the header dwarf the tabs.
    if ([self.style respondsToSelector:@selector(usesExternalTabGroupDecoration)] &&
        [self.style usesExternalTabGroupDecoration]) {
        return [self verticalCellHeight];
    }
    id<PSMTabGroup> group = [self.tabGroupDataSource tabGroupWithIdentifier:cell.tabGroupIdentifier];
    NSString *name = group ? group.name : @"";
    NSString *key = [NSString stringWithFormat:@"H:%@:%@", [(NSObject *)self.style class], name];
    NSNumber *cached = [PSMChipSizeCache() objectForKey:key];
    if (cached) {
        return cached.doubleValue;
    }
    CGFloat height;
    if ([self.style respondsToSelector:@selector(tabGroupChipCellHeightForName:)]) {
        height = [self.style tabGroupChipCellHeightForName:name];
    } else {
        height = [PSMTabGroupChipView verticalChipHeight];
    }
    [PSMChipSizeCache() setObject:@(height) forKey:key];
    return height;
}

- (NSArray<NSNumber *> *)naturalHorizontalCellWidths {
    const BOOL uniform = !self.sizeCellsToFit;
    const CGFloat scrollableWidth = _scrollableTabWidth;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray arrayWithCapacity:_cells.count];
    for (NSInteger cellIdx = 0; cellIdx < (NSInteger)_cells.count; cellIdx++) {
        PSMTabBarCell *cell = _cells[cellIdx];
        CGFloat width;
        if (cell.isCollapsedHidden) {
            width = 0;  // hidden by a collapsed group; keeps index alignment
        } else if (cell.isTabGroupChip) {
            width = [self widthOfTabGroupChipCellAtIndex:cellIdx];
        } else if (cell.isPinned) {
            width = _pinnedTabWidth;
        } else if (uniform) {
            width = scrollableWidth;
        } else {
            width = MAX(scrollableWidth, MIN((CGFloat)_cellMaxWidth, [cell desiredWidthOfCell]));
        }
        [widths addObject:@(width)];
    }
    return widths;
}

// Tab widths may vary. Calculate the widths and see if this will work. Only allow sizes to
// vary if all tabs fit in the allotted space.

- (NSUInteger)numberOfPinnedCells {
    NSUInteger count = 0;
    for (PSMTabBarCell *cell in _cells) {
        if (cell.isPinned) {
            count++;
        }
    }
    return count;
}

// The number of cells that occupy space in the bar: everything EXCEPT
// collapsed-hidden members, which get zero width and no intercell spacing. The
// single owner of the spacing-budget count (N such cells have N-1 gaps); every
// horizontal width builder must use this rather than the raw cell count, or a
// phantom gap per collapsed member inflates the total and can flip a bar that
// really fits into scroll mode / inflate _scrollContentExtent.
- (NSInteger)numberOfCellsContributingIntercellSpacing {
    NSInteger count = 0;
    for (PSMTabBarCell *cell in _cells) {
        if (!cell.isCollapsedHidden) {
            count++;
        }
    }
    return count;
}

- (CGFloat)totalPinnedSpaceForPinnedCount:(NSUInteger)pinnedCount unpinnedCount:(NSUInteger)unpinnedCount {
    if (pinnedCount == 0) {
        return 0;
    }
    const CGFloat spacing = _style.intercellSpacing;
    // Width of pinned tabs themselves
    const CGFloat pinnedWidth = pinnedCount * _pinnedTabWidth;
    // Spacing between pinned tabs
    CGFloat pinnedSpacing = (pinnedCount - 1) * spacing;
    // Spacing between pinned and unpinned groups
    if (unpinnedCount > 0) {
        pinnedSpacing += spacing;
    }
    return pinnedWidth + pinnedSpacing;
}

- (NSArray<NSNumber *> *)variableCellWidthsWithOverflow:(BOOL)withOverflow {
    const CGFloat availableWidth = [self availableCellWidthWithOverflow:withOverflow];
    CGFloat totalDesiredWidth = 0.0;
    NSMutableArray *desiredWidths = [NSMutableArray array];
    for (NSInteger cellIdx = 0; cellIdx < (NSInteger)_cells.count; cellIdx++) {
        PSMTabBarCell *cell = _cells[cellIdx];
        CGFloat width;
        if (cell.isCollapsedHidden) {
            width = 0;  // hidden by a collapsed group; keeps index alignment
        } else if (cell.isTabGroupChip) {
            width = [self widthOfTabGroupChipCellAtIndex:cellIdx];
        } else if (cell.isPinned) {
            width = _pinnedTabWidth;
        } else {
            width = MAX(_cellMinWidth, MIN([cell desiredWidthOfCell], _cellMaxWidth));
        }
        [desiredWidths addObject:@(width)];
        totalDesiredWidth += width;
        if (totalDesiredWidth > availableWidth) {
            // Stop this expensive calculation as soon as it fails.
            break;
        }
    }

    // If all cells get their "desired" width, do they fit?
    if (totalDesiredWidth <= availableWidth) {
        return desiredWidths;
    } else {
        return nil;
    }
}

- (BOOL)shouldUseOptimalWidthWithOverflow:(BOOL)withOverflow {
    const CGFloat availableWidth = [self availableCellWidthWithOverflow:withOverflow];
    const NSUInteger pinnedCount = [self numberOfPinnedCells];
    const NSUInteger unpinnedCount = _cells.count - pinnedCount;
    const CGFloat pinnedSpace = [self totalPinnedSpaceForPinnedCount:pinnedCount unpinnedCount:unpinnedCount];
    const CGFloat unpinnedAvailable = availableWidth - pinnedSpace;
    BOOL canFitAllCellsOptimally = (self.cellOptimumWidth * unpinnedCount <= unpinnedAvailable);
    return !self.stretchCellsToFit && canFitAllCellsOptimally;
}

// Fit/stretch layout when group chip cells are present. Chip (and pinned)
// cells keep their fixed width; the remaining space is shared among the
// tab cells, which stretch to fill when stretchCellsToFit is on. Kept
// separate from the pinned-centric path below so the (well-tested)
// no-chips case is untouched. Returns a contiguous prefix; anything that
// doesn't fit goes to the overflow menu.
- (NSArray<NSNumber *> *)cellWidthsForHorizontalArrangementWithChipsWithOverflow:(BOOL)withOverflow {
    // Honor fit-to-content exactly like the no-chips path below: when every
    // cell (chips at their fixed width) fits at its desired width, use those.
    // Creating a group must not silently switch the bar to uniform widths.
    if (self.sizeCellsToFit) {
        NSArray<NSNumber *> *widths = [self variableCellWidthsWithOverflow:withOverflow];
        if (widths) {
            return widths;
        }
    }
    const CGFloat available = [self availableCellWidthWithOverflow:withOverflow];
    const CGFloat spacing = _style.intercellSpacing;
    // Collapsed members are hidden: they get no width and no intercell spacing,
    // so count only non-collapsed cells for the spacing budget.
    const NSInteger visibleCellCount = [self numberOfCellsContributingIntercellSpacing];
    const CGFloat totalSpacing = spacing * MAX(0, (CGFloat)(visibleCellCount - 1));

    CGFloat reserved = 0;  // fixed width for chip + pinned cells
    NSInteger tabCount = 0;
    for (NSInteger cellIdx = 0; cellIdx < (NSInteger)_cells.count; cellIdx++) {
        PSMTabBarCell *cell = _cells[cellIdx];
        if (cell.isCollapsedHidden) {
            continue;  // hidden by a collapsed group: no reserved width, not a tab
        }
        if (cell.isTabGroupChip) {
            reserved += [self widthOfTabGroupChipCellAtIndex:cellIdx];
        } else if (cell.isPinned) {
            reserved += _pinnedTabWidth;
        } else {
            tabCount++;
        }
    }

    CGFloat perTab = 0;
    if (tabCount > 0) {
        perTab = MAX(0, available - reserved - totalSpacing) / (CGFloat)tabCount;
        if (!self.stretchCellsToFit) {
            // Match the no-chips path: when not stretching, cells grow to their
            // optimum but no further. When stretching, they fill the bar with no
            // upper cap (the non-chip path's computeCellFramesInContainerOfWidth
            // has no cellMaxWidth cap either).
            perTab = MIN(perTab, self.cellOptimumWidth);
        }
        perTab = MAX(self.cellMinWidth, perTab);
    }

    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    CGFloat used = 0;
    // Whether a non-collapsed cell has been emitted yet. Used (instead of
    // result.count) to decide the leading intercell gap so a collapsed cell at
    // the front reserves no phantom leading spacing.
    BOOL emittedVisible = NO;
    // perTab is chosen so the tab cells fill `available` exactly, so the running
    // sum lands right at `available` for the last cell. Allow a sub-point
    // tolerance so floating-point rounding across the per-tab divisions doesn't
    // spuriously push the last tab into the overflow menu, which would leave a
    // full tab-width of empty space on the right.
    const CGFloat fitTolerance = 0.5;
    for (NSInteger cellIdx = 0; cellIdx < (NSInteger)_cells.count; cellIdx++) {
        PSMTabBarCell *cell = _cells[cellIdx];
        if (cell.isCollapsedHidden) {
            // Keep the index-aligned prefix contract: emit a zero-width entry
            // with no spacing and never break here, so a collapsed member in the
            // middle of the bar doesn't misalign later cells' frames.
            [result addObject:@(0)];
            continue;
        }
        CGFloat width;
        if (cell.isTabGroupChip) {
            width = [self widthOfTabGroupChipCellAtIndex:cellIdx];
        } else if (cell.isPinned) {
            width = _pinnedTabWidth;
        } else {
            width = perTab;
        }
        const CGFloat need = width + (emittedVisible ? spacing : 0);
        if (emittedVisible && used + need > available + fitTolerance) {
            break;  // out of room; the rest overflow
        }
        [result addObject:@(width)];
        used += need;
        emittedVisible = YES;
    }
    return result;
}

// The single owner of the overflow-variant choice: YES if a settled layout with
// these no-overflow widths must fall back to the with-overflow variant (some
// cells did not fit, so the array is shorter than _cells, or the add-tab button
// needs reserved room). Shared by -finishUpdateWithRegularWidths: (which settles)
// and -settledHorizontalCellWidths (which targets the collapse animation at that
// same settled layout) so the rule is written once; if the two derived it
// independently, a future change to one would make the slide land on a different
// variant than the settle, popping tail tabs into/out of the overflow menu.
- (BOOL)shouldUseOverflowVariantForRegularWidths:(NSArray *)regularWidths {
    return _showAddTabButton || regularWidths.count < _cells.count;
}

// The horizontal cell widths the next settled layout will adopt: the same choice
// finishUpdateWithRegularWidths: makes between the no-overflow and with-overflow
// variants. Used to target the collapse animation at the correct post-toggle
// arrangement instead of the stale _lainOutWithOverflow flag.
- (NSArray<NSNumber *> *)settledHorizontalCellWidths {
    NSArray<NSNumber *> *regularWidths = [self cellWidthsForHorizontalArrangementWithOverflow:NO];
    if ([self shouldUseOverflowVariantForRegularWidths:regularWidths]) {
        return [self cellWidthsForHorizontalArrangementWithOverflow:YES];
    }
    return regularWidths;
}

// Width the cell area needs for every cell to be laid out at its minimum with
// none dropped. Mirrors the three branches of the width builder below -- chips,
// pinned, plain -- so the two must be edited together or the reservation this
// feeds will disagree with the layout it is meant to predict.
//
// Uneven (sizeCellsToFit) and optimum sizing deliberately have no branch here.
// -variableCellWidthsWithOverflow: returns nil unless every cell fits at its
// desired width, and desired is already at least cellMinWidth;
// -shouldUseOptimalWidthWithOverflow: is only true when optimum already fits.
// Neither can overflow a bar that this expression says fits, so the overflow
// threshold is a cellMinWidth question in every branch.
- (CGFloat)minimumCellAreaWidth {
    const CGFloat spacing = _style.intercellSpacing;
    const CGFloat minWidth = self.cellMinWidth;

    if ([self hasTabGroupChipCells]) {
        // Collapsed members are hidden: no width and no intercell spacing, which
        // is exactly why a raw tab count overstates what the tabs need.
        const NSInteger visibleCellCount = [self numberOfCellsContributingIntercellSpacing];
        CGFloat reserved = 0;
        NSInteger tabCount = 0;
        for (NSInteger i = 0; i < (NSInteger)_cells.count; i++) {
            PSMTabBarCell *cell = _cells[i];
            if (cell.isCollapsedHidden) {
                continue;
            }
            if (cell.isTabGroupChip) {
                reserved += [self widthOfTabGroupChipCellAtIndex:i];
            } else if (cell.isPinned) {
                reserved += _pinnedTabWidth;
            } else {
                tabCount++;
            }
        }
        return reserved + (CGFloat)tabCount * minWidth + spacing * MAX(0.0, (CGFloat)visibleCellCount - 1.0);
    }

    // Floor at one cell: _cells is briefly empty during teardown, and a zero
    // minimum would hand a caller the entire bar for a frame.
    const NSUInteger cellCount = MAX((NSUInteger)1, _cells.count);
    const NSUInteger pinnedCount = [self numberOfPinnedCells];
    if (pinnedCount > 0) {
        const NSUInteger unpinnedCount = cellCount - pinnedCount;
        return ([self totalPinnedSpaceForPinnedCount:pinnedCount unpinnedCount:unpinnedCount] +
                (CGFloat)unpinnedCount * minWidth +
                spacing * MAX(0.0, (CGFloat)unpinnedCount - 1.0));
    }
    return (CGFloat)cellCount * minWidth + spacing * MAX(0.0, (CGFloat)cellCount - 1.0);
}

- (CGFloat)maximumLeftInsetFittingAllCellsMinimallyForWidth:(CGFloat)width {
    // -availableCellWidthWithOverflow: is frame width less both margins, so the
    // largest inset that still fits is whatever remains once the margins and the
    // cells' own minimum are taken out. Asking for the no-overflow right margin
    // is the point: this answers whether the bar fits *without* degrading.
    //
    // The left margin is not simply insets.left: Yosemite returns it unchanged
    // but Tahoe returns it plus 2. Subtracting self.insets.left leaves only that
    // per-style constant, which is what a caller about to choose a new inset
    // needs. Do not simplify either half away -- alone, one reads a stale inset
    // and the other silently drops the style's own padding.
    const CGFloat stylePadding = [_style leftMarginForTabBarControl] - self.insets.left;
    const CGFloat rightMargin = [_style rightMarginForTabBarControlWithOverflow:NO
                                                                   addTabButton:self.showAddTabButton];
    return width - stylePadding - rightMargin - [self minimumCellAreaWidth];
}

- (NSArray<NSNumber *> *)cellWidthsForHorizontalArrangementWithOverflow:(BOOL)withOverflow {
    if ([self hasTabGroupChipCells]) {
        return [self cellWidthsForHorizontalArrangementWithChipsWithOverflow:withOverflow];
    }
    const NSUInteger cellCount = _cells.count;
    const CGFloat availableWidth = [self availableCellWidthWithOverflow:withOverflow];
    const CGFloat intercellSpacing = _style.intercellSpacing;
    const NSUInteger pinnedCount = [self numberOfPinnedCells];
    const NSUInteger unpinnedCount = cellCount - pinnedCount;

    // Two-row mode: distribute cells across two rows, each stretched to fill a
    // single physical row's width. This deliberately overrides the size-to-fit
    // and optimal-width paths so tabs get as much room as possible.
    if ([self horizontalRowCount] == 2) {
        // Row 1 leaves the left inset clear for the traffic lights and the window
        // shortcut label (compact/minimal windows), which both live on the first
        // row. Lower rows have no such chrome, so they reclaim that inset and start
        // flush-left. For normal windows insets.left is ~0, so row1Width == row2Width.
        const CGFloat lowerRowExtra = MAX(0, self.insets.left);
        const CGFloat row1Width = availableWidth;
        const CGFloat row2Width = availableWidth + lowerRowExtra;
        const CGFloat layoutWidth = row1Width + row2Width;

        if (pinnedCount == 0) {
            // Even split of all cells across the two rows.
            NSInteger visibleCount = (NSInteger)cellCount;
            while (visibleCount > 0 &&
                   _cellMinWidth * visibleCount + intercellSpacing * MAX(0, visibleCount - 1) > layoutWidth) {
                visibleCount--;
            }
            if (visibleCount <= 0) {
                return [NSArray array];
            }
            const NSInteger row1Count = (visibleCount + 1) / 2;
            const NSInteger row2Count = visibleCount - row1Count;
            NSMutableArray<NSNumber *> *result = [NSMutableArray array];
            [self computeCellFramesInContainerOfWidth:row1Width
                                 numberOfVisibleCells:row1Count
                                     intercellSpacing:intercellSpacing
                                                scale:2.0
                                               frames:result];
            [self computeCellFramesInContainerOfWidth:row2Width
                                 numberOfVisibleCells:row2Count
                                     intercellSpacing:intercellSpacing
                                                scale:2.0
                                               frames:result];
            return result;
        }

        // Pinned cells present: keep them at their fixed width and on the first
        // row (they sort to the front of _cells); only the unpinned cells are
        // stretched, split across row 1 (in the space left after the pinned tabs)
        // and row 2 (the full row width). _setupCells: mirrors this split.
        const CGFloat pinnedSpace = [self totalPinnedSpaceForPinnedCount:pinnedCount
                                                           unpinnedCount:unpinnedCount];
        const CGFloat row1UnpinnedWidth = MAX(0, row1Width - pinnedSpace);
        const CGFloat row2UnpinnedWidth = row2Width;
        const CGFloat unpinnedBudget = row1UnpinnedWidth + row2UnpinnedWidth;
        NSInteger visibleUnpinned = (NSInteger)unpinnedCount;
        while (visibleUnpinned > 0 &&
               _cellMinWidth * visibleUnpinned + intercellSpacing * MAX(0, visibleUnpinned - 1) > unpinnedBudget) {
            visibleUnpinned--;
        }
        const NSInteger row1Unpinned = (visibleUnpinned + 1) / 2;
        const NSInteger row2Unpinned = visibleUnpinned - row1Unpinned;
        NSMutableArray<NSNumber *> *unpinnedWidths = [NSMutableArray array];
        [self computeCellFramesInContainerOfWidth:row1UnpinnedWidth
                             numberOfVisibleCells:row1Unpinned
                                 intercellSpacing:intercellSpacing
                                            scale:2.0
                                           frames:unpinnedWidths];
        [self computeCellFramesInContainerOfWidth:row2UnpinnedWidth
                             numberOfVisibleCells:row2Unpinned
                                 intercellSpacing:intercellSpacing
                                            scale:2.0
                                           frames:unpinnedWidths];

        // Map widths back onto _cells order: pinned -> fixed, unpinned -> next
        // stretched width (row-1 widths first, then row-2, matching the split).
        // Pinned cells all live on row 1; stop once they no longer fit its width so
        // they overflow into the menu instead of running off the right edge.
        NSMutableArray<NSNumber *> *result = [NSMutableArray array];
        NSUInteger unpinnedTaken = 0;
        CGFloat pinnedUsed = 0;
        for (PSMTabBarCell *cell in _cells) {
            if (cell.isPinned) {
                const CGFloat needed = _pinnedTabWidth + (result.count > 0 ? intercellSpacing : 0);
                if (pinnedUsed + needed > row1Width) {
                    break;  // No room for this pinned tab on row 1.
                }
                pinnedUsed += needed;
                [result addObject:@((CGFloat)_pinnedTabWidth)];
            } else {
                if (unpinnedTaken >= unpinnedWidths.count) {
                    break;  // Remaining unpinned tabs overflow.
                }
                [result addObject:unpinnedWidths[unpinnedTaken++]];
            }
        }
        return result;
    }

    if (self.sizeCellsToFit) {
        NSArray<NSNumber *> *widths = [self variableCellWidthsWithOverflow:withOverflow];
        if (widths) {
            return widths;
        }
    }

    if (pinnedCount == 0) {
        // No pinned cells (normal single-row path)
        NSMutableArray<NSNumber *> *newWidths = [NSMutableArray array];
        if ([self shouldUseOptimalWidthWithOverflow:withOverflow]) {
            for (int i = 0; i < cellCount; i++) {
                [newWidths addObject:@(_cellOptimumWidth)];
            }
        } else {
            const BOOL canFitAllCellsMinimally = (self.cellMinWidth * cellCount + intercellSpacing * MAX(0, (cellCount - 1)) <= availableWidth);
            NSInteger numberOfVisibleCells;
            if (canFitAllCellsMinimally) {
                numberOfVisibleCells = cellCount;
            } else {
                numberOfVisibleCells = availableWidth / _cellMinWidth;
                while (numberOfVisibleCells >= 0 && numberOfVisibleCells * _cellMinWidth + intercellSpacing > availableWidth) {
                    numberOfVisibleCells -= 1;
                }
            }
            [self computeCellFramesInContainerOfWidth:availableWidth
                                 numberOfVisibleCells:numberOfVisibleCells
                                     intercellSpacing:intercellSpacing
                                                scale:2.0
                                               frames:newWidths];
        }
        return newWidths;
    }

    // There are pinned cells. Give them fixed width and distribute remaining space to unpinned.
    const CGFloat pinnedSpaceWithSpacing = [self totalPinnedSpaceForPinnedCount:pinnedCount unpinnedCount:unpinnedCount];
    const CGFloat unpinnedContainerWidth = MAX(0, availableWidth - pinnedSpaceWithSpacing);

    NSMutableArray<NSNumber *> *unpinnedWidths = [NSMutableArray array];
    NSInteger numberOfVisibleUnpinned = 0;

    if (unpinnedCount > 0 && unpinnedContainerWidth > 0) {
        if ([self shouldUseOptimalWidthWithOverflow:withOverflow]) {
            numberOfVisibleUnpinned = unpinnedCount;
            for (NSUInteger i = 0; i < unpinnedCount; i++) {
                [unpinnedWidths addObject:@(_cellOptimumWidth)];
            }
        } else {
            const BOOL canFitAllUnpinned = (self.cellMinWidth * unpinnedCount +
                intercellSpacing * MAX(0, (NSInteger)(unpinnedCount - 1)) <= unpinnedContainerWidth);
            if (canFitAllUnpinned) {
                numberOfVisibleUnpinned = unpinnedCount;
            } else {
                numberOfVisibleUnpinned = unpinnedContainerWidth / _cellMinWidth;
                while (numberOfVisibleUnpinned >= 0 &&
                       numberOfVisibleUnpinned * _cellMinWidth + intercellSpacing > unpinnedContainerWidth) {
                    numberOfVisibleUnpinned -= 1;
                }
                numberOfVisibleUnpinned = MAX(0, numberOfVisibleUnpinned);
            }
            if (numberOfVisibleUnpinned > 0) {
                [self computeCellFramesInContainerOfWidth:unpinnedContainerWidth
                                     numberOfVisibleCells:numberOfVisibleUnpinned
                                         intercellSpacing:intercellSpacing
                                                    scale:2.0
                                                   frames:unpinnedWidths];
            }
        }
    }

    // Build the result array.  _setupCells: maps result[i] to _cells[i], so the
    // array must be a contiguous prefix of _cells.  Once any cell doesn't fit we
    // must stop; everything after that goes to the overflow menu.
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    NSUInteger unpinnedIndex = 0;
    CGFloat usedWidth = 0;
    for (PSMTabBarCell *cell in _cells) {
        if (cell.isPinned) {
            CGFloat needed = _pinnedTabWidth + (result.count > 0 ? intercellSpacing : 0);
            if (usedWidth + needed > availableWidth) {
                break;  // No room for this pinned tab; stop here.
            }
            [result addObject:@((CGFloat)_pinnedTabWidth)];
            usedWidth += needed;
        } else {
            if (unpinnedIndex >= (NSUInteger)numberOfVisibleUnpinned || unpinnedIndex >= unpinnedWidths.count) {
                break;  // No room for more unpinned tabs.
            }
            [result addObject:unpinnedWidths[unpinnedIndex]];
            unpinnedIndex++;
        }
    }
    return result;
}

- (void)computeCellFramesInContainerOfWidth:(CGFloat)containerWidth
                       numberOfVisibleCells:(NSInteger)n
                           intercellSpacing:(CGFloat)intercellSpacing
                                      scale:(CGFloat)scale
                                     frames:(NSMutableArray<NSNumber *> *)outWidths {
    if (n <= 0) {
        return;
    }

    // Work in whole device pixels.
    const NSInteger totalPx = llround(containerWidth * scale);
    const NSInteger gapPx = llround(intercellSpacing * scale);

    const NSInteger totalGapsPx = (n - 1) * gapPx;
    const NSInteger contentPx = MAX(0, totalPx - totalGapsPx);

    // Base width for each button and leftover pixels to distribute.
    NSInteger basePx = contentPx / n;
    NSInteger remPx = contentPx % n;

    for (NSInteger i = 0; i < n; i++) {
        NSInteger wPx = basePx + (i < remPx ? 1 : 0);

        CGFloat w = ((CGFloat)wPx) / scale;

        [outWidths addObject:@(w)];
    }
}

- (void)removeCell:(PSMTabBarCell *)cell {
    [cell removeCloseButtonTrackingRectFrom:self];
    [cell removeCellTrackingRectFrom:self];
    [self removeTabProgressBarForCell:cell];
    [[self cells] removeObject:cell];
}

- (void)_removeCellTrackingRects {
    // size all cells appropriately and create tracking rects
    // nuke old tracking rects
    int i, cellCount = [_cells count];

    for (i = 0; i < cellCount; i++) {
        id cell = [_cells objectAtIndex:i];
        [cell removeCloseButtonTrackingRectFrom:self];
        [cell removeCellTrackingRectFrom:self];
    }

    //remove all tooltip rects
    [self removeAllToolTips];
}

- (void)_animateCells:(NSTimer *)timer {
    NSArray *targetWidths = [timer userInfo];
    int i, numberOfVisibleCells = [targetWidths count];
    float totalChange = 0.0f;
    BOOL updated = NO;

    if ([_cells count] > 0) {
        //compare our target widths with the current widths and move towards the target
        for (i = 0; i < [_cells count]; i++) {
            PSMTabBarCell *currentCell = [_cells objectAtIndex:i];
            NSRect cellFrame = [currentCell frame];
            cellFrame.origin.x += totalChange;

            if (i < numberOfVisibleCells) {
                float target = [[targetWidths objectAtIndex:i] floatValue];

                if (currentCell.isPinned) {
                    // Pinned cells snap to target width immediately - no gradual animation.
                    totalChange += target - cellFrame.size.width;
                    cellFrame.size.width = target;
                    [currentCell setFrame:cellFrame];
                } else if (fabs(cellFrame.size.width - target) < _animationDelta) {
                    cellFrame.size.width = target;
                    totalChange += cellFrame.size.width - target;
                    [currentCell setFrame:cellFrame];
                } else if (cellFrame.size.width > target) {
                    cellFrame.size.width -= _animationDelta;
                    totalChange -= _animationDelta;
                    updated = YES;
                } else if (cellFrame.size.width < target) {
                    cellFrame.size.width += _animationDelta;
                    totalChange += _animationDelta;
                    [currentCell setFrame:cellFrame];
                    updated = YES;
                }
            }

            [currentCell setFrame:cellFrame];
        }

        _animationDelta += 4.0f;
    }

    if (!updated) {
        [self finishUpdateWithRegularWidths:targetWidths
                         widthsWithOverflow:targetWidths];
        [timer invalidate];
        _animationTimer = nil;
    }

    [self setNeedsDisplay:YES];
}

- (void)finishUpdateWithRegularWidths:(NSArray *)regularWidths
                   widthsWithOverflow:(NSArray *)widthsWithOverflow {
    // Set up overflow menu.
    NSArray *newValues;
    if ([self shouldUseOverflowVariantForRegularWidths:regularWidths]) {
        newValues = widthsWithOverflow;
    } else {
        newValues = regularWidths;
    }
    NSMenu *overflowMenu = [self _setupCells:newValues];
    // Cell frames and overflow membership are now final; refresh the cached per-row
    // first/last flags styles read while drawing.
    [self updateHorizontalRowBoundaryFlags];

    _lainOutWithOverflow = (overflowMenu != nil || _showAddTabButton);
    if (overflowMenu) {
        [self _setupOverflowMenu:overflowMenu];
    }

    [_overflowPopUpButton setHidden:(overflowMenu == nil)];

    // Set up add tab button. A scrollable bar has no overflow menu. A vertical one has nowhere to put
    // the button (it would sit past the bottom), so hide it; a horizontal one keeps it pinned in the
    // right margin while the tabs scroll to its left.
    const BOOL scrollingOverflow = ([self tabBarIsScrollable] && [self maximumScrollOffset] > 0);
    const BOOL addTabButtonWouldBeOffscreen = (scrollingOverflow && [self isVerticalOrientation]);
    if (!overflowMenu && _showAddTabButton && !addTabButtonWouldBeOffscreen) {
        NSRect cellRect = [self genericCellRectWithOverflow:YES];
        cellRect.size = [_addTabButton frame].size;

        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            if ([self horizontalRowCount] == 2) {
                // Place the + at the end of the TOP row. Passing the full width
                // array would put styles that sum widths (Yosemite/Minimal) about
                // two rows past the right edge; Tahoe ignores the widths anyway.
                const NSInteger row1Count = [self twoRowFirstRowCountForVisibleCells:newValues.count];
                const NSUInteger clampedRow1Count = (NSUInteger)MAX((NSInteger)0, row1Count);
                NSArray<NSNumber *> *row1Widths =
                    [newValues subarrayWithRange:NSMakeRange(0, MIN(clampedRow1Count, newValues.count))];
                // One row's content height (the top row), matching _setupCells.
                cellRect = [self.style frameForAddTabButtonWithCellWidths:row1Widths height:[self twoRowContentHeight]];
                cellRect.origin.y = self.insets.top;
            } else {
                cellRect = [self.style frameForAddTabButtonWithCellWidths:newValues height:self.bounds.size.height];
            }
            if (scrollingOverflow && NSMaxX(cellRect) > self.bounds.size.width) {
                // The style placed the button after the last tab, which is now scrolled off the right
                // edge. Pull it back into the right margin. Styles that already pin it in-bounds (e.g.
                // Tahoe) are left exactly where they put it.
                cellRect.origin.x = self.bounds.size.width -
                    [_style rightMarginForTabBarControlWithOverflow:NO addTabButton:self.showAddTabButton];
            }
        } else {
            cellRect.origin.x = 0;
            cellRect.origin.y = [[newValues lastObject] floatValue];
        }

        [self _setupAddTabButton:cellRect];
    } else {
        [_addTabButton setHidden:YES];
    }
}

// The trailing intercell gap for cell `i` during a horizontal collapse slide.
// A collapsed member laid out with a nonzero interpolated width also injects a
// full intercell gap in the x-walk, but the SETTLED layout excludes collapsed
// members from both width and spacing. Unless the gap sheds in lockstep with the
// width, every survivor to the right of the group snaps left by
// (memberCount * intercellSpacing) at the end of the slide (2pt/member on Tahoe).
// Scale the gap by the member's presence (current width / expanded width) so it
// reaches 0 exactly when the width does. Non-animating or non-member cells get
// the full gap.
- (CGFloat)collapseTrailingSpacingForCellAtIndex:(NSInteger)i
                                interpolatedWidth:(CGFloat)w
                                 intercellSpacing:(CGFloat)intercellSpacing {
    if (!_collapseAnimating || _collapseVertical ||
        i < 0 || i >= (NSInteger)_cells.count || !_cells[i].isCollapsedHidden) {
        return intercellSpacing;
    }
    const CGFloat full = (i < (NSInteger)_collapseStartWidths.count &&
                          i < (NSInteger)_collapseTargetWidths.count)
        ? MAX(_collapseStartWidths[i].doubleValue, _collapseTargetWidths[i].doubleValue)
        : 0;
    if (full <= 0) {
        return 0;
    }
    return intercellSpacing * MIN(1.0, MAX(0.0, w / full));
}

// Number of visible cells that go on the first physical row in two-row mode.
// Pinned cells (front of _cells) all stay on row 1; the remaining unpinned cells
// are split evenly. Shared by width layout, cell placement, and add-button
// placement so they all agree on where row 1 ends.
- (NSInteger)twoRowFirstRowCountForVisibleCells:(NSInteger)numberOfVisibleCells {
    const NSInteger n = MIN(numberOfVisibleCells, (NSInteger)_cells.count);
    NSInteger visiblePinned = 0;
    for (NSInteger i = 0; i < n; i++) {
        if ([[_cells objectAtIndex:i] isPinned]) {
            visiblePinned++;
        }
    }
    const NSInteger visibleUnpinned = numberOfVisibleCells - visiblePinned;
    return visiblePinned + (visibleUnpinned + 1) / 2;
}

- (NSMenu *)_setupCells:(NSArray *)newValues {
    const int cellCount = [_cells count];
    const int numberOfVisibleCells = [newValues count];
    NSRect cellRect = [self genericCellRectWithOverflow:(_showAddTabButton || cellCount > numberOfVisibleCells)];
    const NSRect generic = cellRect;
    NSMenu *overflowMenu = nil;
    const CGFloat intercellSpacing = _style.intercellSpacing;

    // A scrolled horizontal bar starts its x-walk shifted left by the scroll offset, so every cell
    // lands at its scrolled on-screen position (the horizontal analogue of the vertical origins the
    // scrollable branch bakes the offset into). Vertical bars already have the offset in newValues.
    if ([self orientation] == PSMTabBarHorizontalOrientation &&
        [self tabBarIsScrollable] && [self maximumScrollOffset] > 0) {
        cellRect.origin.x -= _scrollOffset;
    }

    // Two-row layout state (horizontal bars only).
    const BOOL twoRow = ([self horizontalRowCount] == 2);
    // Two rows share the bar height as [top inset][row][gap][row][bottom]; see the
    // twoRow* helpers. Each row gets the same content height so the selected pill
    // (which styles inset inside the row) stays inset rather than poking past it.
    const CGFloat rowStride = twoRow ? [self twoRowStride] : generic.size.height;
    const CGFloat rowContentHeight = twoRow ? [self twoRowContentHeight] : generic.size.height;
    // Index boundary: cells [0, twoRowRow1Count) on row 1; rest on row 2. Pinned
    // cells (which sort to the front) always stay on row 1 at their fixed width;
    // only the unpinned cells are split evenly. This mirrors the width assignment
    // in cellWidthsForHorizontalArrangementWithOverflow:.
    const int twoRowRow1Count = twoRow ? (int)[self twoRowFirstRowCountForVisibleCells:numberOfVisibleCells] : 0;
    // Row 1 is inset for the traffic lights + shortcut label; lower rows have no
    // such chrome, so they start flush-left at the reclaimed edge. Matches the
    // per-row widths in cellWidthsForHorizontalArrangementWithOverflow:.
    const CGFloat lowerRowExtra = MAX(0, self.insets.left);
    const CGFloat lowerRowOriginX = generic.origin.x - lowerRowExtra;
    int currentRow = 0;
    // A modified generic rect that tells the style each cell is one row tall.
    NSRect rowGeneric = generic;
    if (twoRow) {
        rowGeneric.size.height = rowContentHeight;
    }

    // Set up cells with frames and rects
    const BOOL horizontalLayout = ([self orientation] == PSMTabBarHorizontalOrientation);
    for (int i = 0; i < cellCount; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];
        int tabState = 0;
        if (i < numberOfVisibleCells) {
            // A collapsed member is zeroed unless a slide is actively sizing it.
            // On a horizontal bar that shows up as a nonzero interpolated WIDTH in
            // newValues; on a vertical bar newValues holds ORIGINS (not sizes) and
            // there is no width-driven slide, so it always zeroes -- otherwise a
            // non-first collapsed member (origin > 0) would slip through and take a
            // full height.
            const BOOL animatingSize = (horizontalLayout &&
                                        [[newValues objectAtIndex:i] doubleValue] > 0);
            if (cell.isCollapsedHidden && !animatingSize) {
                // Hidden by a collapsed group: give it a zero-size frame, drop
                // its tracking rects and indicator, keep it out of the overflow
                // menu, and do NOT advance the x-origin (the `continue` skips the
                // intercell-gap advance below) so the bar closes up around it.
                // Keyed on the requested width, not a global flag, so ONLY the
                // group being animated (whose collapsed members get a nonzero
                // interpolated width) slides; every other collapsed group stays
                // fully zeroed and renders as its self-contained chip.
                [cell setFrame:NSMakeRect(cellRect.origin.x, cellRect.origin.y, 0, 0)];
                [cell removeCellTrackingRectFrom:self];
                [cell removeCloseButtonTrackingRectFrom:self];
                [[cell indicator] removeFromSuperview];
                [cell setIsInOverflowMenu:NO];
                continue;
            }
            // set cell frame
            if ([self orientation] == PSMTabBarHorizontalOrientation) {
                // Chip cells' width comes from the widths array like any
                // other cell; there is no separate gap to reserve now.
                const CGFloat width = [[newValues objectAtIndex:i] floatValue];
                // In two-row mode, switch to row 2 at the midpoint index. Lower
                // rows start at the reclaimed left edge (no traffic-light inset).
                if (twoRow && currentRow == 0 && i >= twoRowRow1Count) {
                    currentRow = 1;
                    cellRect.origin.x = lowerRowOriginX;
                }
                cellRect.size.width = width;
            } else {
                cellRect.size.width = [self frame].size.width;
                // Chip cells reserve their own (style-aware) height; tabs use the generic height.
                cellRect.size.height = cell.isTabGroupChip ? [self heightOfTabGroupChipCell:cell]
                                                           : generic.size.height;
                cellRect.origin.y = [[newValues objectAtIndex:i] floatValue];
                cellRect.origin.x = 0;
            }
            cellRect = [_style adjustedCellRect:cellRect generic:twoRow ? rowGeneric : generic];
            // In two-row mode override the y so row 2 cells sit below row 1,
            // regardless of what adjustedCellRect: set (e.g. Tahoe always
            // resets y to containerTopInset).
            if (twoRow && [self orientation] == PSMTabBarHorizontalOrientation) {
                cellRect.origin.y = generic.origin.y + currentRow * rowStride;
                // Constrain each cell to one row's content height. adjustedCellRect:
                // does this for Tahoe but not for Yosemite/Minimal (which keep the
                // full bar height), so set it explicitly or the rows overlap.
                cellRect.size.height = MAX(1.0, rowContentHeight - 1.0);
            }
            [cell setFrame:cellRect];

            // close button tracking rect
            if ([cell hasCloseButton] && !cell.isPinned &&
                ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] ||
                 [self allowsBackgroundTabClosing])) {
                    NSPoint mousePoint =
                    [self convertPoint:[[self window] pointFromScreenCoords:[NSEvent mouseLocation]]
                              fromView:nil];
                    NSRect closeRect = [cell closeButtonRectForFrame:cellRect];

                    // Add the tracking rect for the close button highlight.
                    [cell removeCloseButtonTrackingRectFrom:self];
                    [cell setCloseButtonTrackingRect:closeRect userData:nil assumeInside:NO view:self];

                    // highlight the close button if the currently selected tab has the mouse over it
                    // this will happen if the user clicks a close button in a tab and all the tabs are
                    // rearranged
                    if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] &&
                        [[NSApp currentEvent] type] != NSEventTypeLeftMouseDown &&
                        NSMouseInRect(mousePoint, closeRect, [self isFlipped])) {
                        [cell setCloseButtonOver:YES];
                    }
                } else {
                    [cell setCloseButtonOver:NO];
                }

            // Add entire-tab tracking rect.
            [cell removeCellTrackingRectFrom:self];
            [cell setCellTrackingRect:cellRect userData:nil assumeInside:NO view:self];
            [cell setEnabled:YES];

            //add the tooltip tracking rect
            [self addToolTipRect:cellRect owner:self userData:nil];

            // selected? set tab states...
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]]) {
                [cell setState:NSControlStateValueOn];
                tabState |= PSMTab_SelectedMask;
                // previous cell
                if (i > 0) {
                    [[_cells objectAtIndex:i-1] setTabState:([(PSMTabBarCell *)[_cells objectAtIndex:i-1] tabState] | PSMTab_RightIsSelectedMask)];
                }
                // next cell - see below
            } else {
                [cell setState:NSControlStateValueOff];
                // see if prev cell was selected
                if (i > 0) {
                    if ([[_cells objectAtIndex:i-1] state] == NSControlStateValueOn){
                        tabState |= PSMTab_LeftIsSelectedMask;
                    }
                }
            }
            // more tab states
            if (cellCount == 1) {
                tabState |= PSMTab_PositionLeftMask | PSMTab_PositionRightMask | PSMTab_PositionSingleMask;
            } else if (i == 0) {
                tabState |= PSMTab_PositionLeftMask;
            } else if (i-1 == cellCount) {
                tabState |= PSMTab_PositionRightMask;
            }
            [cell setTabState:tabState];
            [cell setIsInOverflowMenu:NO];

            // indicator (accessories outside the scroll region are hidden later by
            // hideAccessoriesOutsideScrollRegion)
            if (![[cell indicator] isHidden] && !_hideIndicators) {
                [[cell indicator] setFrame:[cell indicatorRectForFrame:cellRect]];
                if (![[self subviews] containsObject:[cell indicator]]) {
                    [self addSubview:[cell indicator]];
                    [[cell indicator] setAnimate:YES];
                }
            }

            // next...
            const CGFloat advanceWidth = [[newValues objectAtIndex:i] floatValue];
            cellRect.origin.x += advanceWidth +
                [self collapseTrailingSpacingForCellAtIndex:i
                                          interpolatedWidth:advanceWidth
                                           intercellSpacing:intercellSpacing];

        } else {
            if (cell.isTabGroupChip) {
                // A chip is not a tab: it gets no overflow menu item (its
                // member tabs each get their own) and must not become a
                // blank row whose action would select a nil tab view item.
                [cell setIsInOverflowMenu:YES];
                [[cell indicator] removeFromSuperview];
                continue;
            }
            if (cell.isCollapsedHidden) {
                // A collapsed member that fell past the visible prefix: hidden,
                // and never added to the overflow "..." menu (that would defeat
                // collapse).
                [cell setIsInOverflowMenu:YES];
                [[cell indicator] removeFromSuperview];
                continue;
            }
            // set up menu items
            NSMenuItem *menuItem;
            if (overflowMenu == nil) {
                overflowMenu = [[[NSMenu alloc] initWithTitle:@"TITLE"] autorelease];
                // A pull-down NSPopUpButton uses the item at index 0 as its
                // (hidden) label rather than showing it in the popped menu, so
                // insert a throwaway placeholder there to keep the first real
                // tab from being swallowed. Gate on the button's actual state
                // rather than the OS version: a macOS 26 special-case here used
                // to skip this on the false assumption that the Tahoe overflow
                // button was not a pull-down, which dropped the first overflowed
                // tab from the menu.
                if ([_overflowPopUpButton isKindOfClass:[NSPopUpButton class]] &&
                    [(NSPopUpButton *)_overflowPopUpButton pullsDown]) {
                    [overflowMenu insertItemWithTitle:@"FIRST" action:nil keyEquivalent:@"" atIndex:0];
                }
            }
            NSString *title = [[cell attributedStringValue] string] ?: @"";
            menuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(overflowMenuAction:) keyEquivalent:@""];
            [menuItem setTarget:self];
            [menuItem setRepresentedObject:[cell representedObject]];
            [cell setIsInOverflowMenu:YES];
            [[cell indicator] removeFromSuperview];
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]]) {
                [menuItem setState:NSControlStateValueOn];
            }

            if ([cell hasIcon]) {
                [menuItem setImage:(NSImage *)[(id)[[cell representedObject] identifier] icon]];
            }

            if ([cell count] > 0) {
                [menuItem setTitle:[[menuItem title] stringByAppendingFormat:@" (%d)", [cell count]]];
            }

            [overflowMenu addItem:menuItem];
            [menuItem release];
        }
    }

    return overflowMenu;
}

- (void)_setupOverflowMenu:(NSMenu *)overflowMenu {
    _overflowPopUpButton.frame = [_style frameForOverflowButtonWithAddTabButton:self.showAddTabButton
                                                                  enclosureSize:self.frame.size
                                                                 standardHeight:self.height];

    if (![[self subviews] containsObject:_overflowPopUpButton]) {
        [self addSubview:_overflowPopUpButton];
    }

    if (overflowMenu) {
        // Have a candidate for new overflow menu. Does it contain the same information as the current one?
        // If they're equal, we don't want to update the menu since this happens several times per second
        // while the user is visiting the menu. But reading it is fine.
        BOOL equal = YES;
        equal = [_overflowPopUpButton menu] && [[_overflowPopUpButton menu] numberOfItems ] == [overflowMenu numberOfItems];
        for (int i = 0; equal && i < [overflowMenu numberOfItems]; i++) {
            NSMenuItem *currentItem = [[_overflowPopUpButton menu] itemAtIndex:i];
            NSMenuItem *newItem = [overflowMenu itemAtIndex:i];
            if (([newItem state] != [currentItem state]) ||
                    ([[newItem title] compare:[currentItem title]] != NSOrderedSame) ||
                    ([newItem image] != [currentItem image])) {
                equal = NO;
            }
        }

        if (!equal) {
            [_overflowPopUpButton setMenu:overflowMenu];
        }
    }
}

- (void)_setupAddTabButton:(NSRect)frame {
    if (![[self subviews] containsObject:_addTabButton]) {
        [self addSubview:_addTabButton];
    }

    if ([_addTabButton isHidden] && _showAddTabButton) {
        [_addTabButton setHidden:NO];
    }

    NSImage *image = [_style addTabButtonImage];
    if (image) {
        [_addTabButton setImage:image];
    }
    [_addTabButton setFrame:frame];
    [_addTabButton setNeedsDisplay:YES];
}

#pragma mark -
#pragma mark Mouse Tracking

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (void)otherMouseDown:(NSEvent *)theEvent {
    if ([theEvent buttonNumber] == 2) {
        [self setLastMiddleMouseDownEvent:theEvent];
    }
}

- (void)mouseDown:(NSEvent *)theEvent {
    _didDrag = NO;

    // keep for dragging
    [self setLastMouseDownEvent:theEvent];
    // what cell?
    NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSRect frame = [self frame];

    const BOOL mouseIsOverVerticalResizeHandle = (_tabLocation == PSMTab_RightTab) ? (mousePt.x < 3) : (mousePt.x > frame.size.width - 3);
    if ([self orientation] == PSMTabBarVerticalOrientation && [self allowsResizing] && partnerView && mouseIsOverVerticalResizeHandle) {
        _resizing = YES;
    }

    NSRect cellFrame;
    PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
    if (cell) {
        BOOL overClose = NSMouseInRect(mousePt, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]);
        if (overClose &&
            cell.closeButtonVisible &&
            ([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]])) {
            [cell setCloseButtonOver:NO];
            [cell setCloseButtonPressed:YES];
            _closeClicked = YES;
        } else {
            [cell setCloseButtonPressed:NO];
            if ([theEvent clickCount] == 1) {
                const NSEventModifierFlags mask = NSEventModifierFlagOption;
                if (_selectsTabsOnMouseDown && (theEvent.modifierFlags & mask) == 0) {
                    if (cell.state != NSControlStateValueOn) {
                        _preDragSelectedTabIndex = [[self tabView] indexOfTabViewItem:self.tabView.selectedTabViewItem];
                    } else {
                        // Because we always want it to switch tabs, don't save
                        // the index if you're dragging the current tab.
                        _preDragSelectedTabIndex = NSNotFound;
                    }
                    [self tabClick:cell];
                }
            }
        }
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    if ([self lastMouseDownEvent] == nil) {
        if (!_addTabButton.allowDrags) {
            [super mouseDragged:theEvent];
        }
        return;
    }
    if (!_haveInitialDragLocation) {
        _initialDragLocation = [theEvent locationInWindow];
        _haveInitialDragLocation = YES;
        return;
    }

    NSPoint currentPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];

    if (_resizing) {
        NSRect frame = [self frame];
        float resizeAmount = [theEvent deltaX];
        if (_tabLocation == PSMTab_RightTab) {
            resizeAmount = -resizeAmount;
        }
        const BOOL shouldResize = (_tabLocation == PSMTab_RightTab) ?
            ((currentPoint.x < 0 && resizeAmount > 0) || (currentPoint.x > 0 && resizeAmount < 0)) :
            ((currentPoint.x > frame.size.width && resizeAmount > 0) || (currentPoint.x < frame.size.width && resizeAmount < 0));
        if (shouldResize) {
            [[NSCursor resizeLeftRightCursor] push];

            NSRect partnerFrame = [partnerView frame];

            //do some bounds checking
            if ((frame.size.width + resizeAmount > [self cellMinWidth]) && (frame.size.width + resizeAmount < [self cellMaxWidth])) {
                if (_tabLocation == PSMTab_RightTab) {
                    frame.origin.x -= resizeAmount;
                    frame.size.width += resizeAmount;
                    partnerFrame.size.width -= resizeAmount;
                } else {
                    frame.size.width += resizeAmount;
                    partnerFrame.size.width -= resizeAmount;
                    partnerFrame.origin.x += resizeAmount;
                }

                [self setFrame:frame];
                [partnerView setFrame:partnerFrame];
                [[self superview] setNeedsDisplay:YES];
            }
        }
        return;
    }

    NSRect cellFrame;
    NSPoint trackingStartPoint = [self convertPoint:_initialDragLocation fromView:nil];

    // A drag that begins on a group chip moves the whole group as a block through
    // the same drag machinery as a single tab (the group is the dragged unit).
    // Chips are invisible to -cellForPoint:, so dispatch this before the
    // single-tab path (which would find no cell under the chip) and before the
    // window-drag conversion below (a chip sits in the top edge strip that would
    // otherwise be read as "drag the window").
    PSMTabBarCell *chip = nil;
    if (!_didDrag && ![[PSMTabDragAssistant sharedDragAssistant] isDragging]) {
        chip = [self chipForPoint:trackingStartPoint];
        if (chip) {
            const CGFloat dx = currentPoint.x - trackingStartPoint.x;
            const CGFloat dy = currentPoint.y - trackingStartPoint.y;
            if (sqrt(dx * dx + dy * dy) >= self.minimumTabDragDistance) {
                NSArray<PSMTabBarCell *> *members = [self tabGroupMemberCellsForChip:chip];
                if (members.count > 0) {
                    _didDrag = YES;
                    [[PSMTabDragAssistant sharedDragAssistant] startDraggingGroupWithChip:chip
                                                                                 members:members
                                                                              fromTabBar:self
                                                                      withMouseDownEvent:[self lastMouseDownEvent]];
                }
            }
            return;
        }
    }

    if (!chip &&
        [self.delegate respondsToSelector:@selector(tabViewShouldDragWindow:event:)] &&
        [self.delegate tabViewShouldDragWindow:_tabView event:theEvent]) {
        [self.window makeKeyAndOrderFront:nil];
        [self.window performWindowDragWithEvent:theEvent];
        return;
    }

    PSMTabBarCell *cell = [self cellForPoint:trackingStartPoint cellFrame:&cellFrame];
    if (cell) {
        //check to see if the close button was the target in the clicked cell
        //highlight/unhighlight the close button as necessary
        NSRect iconRect = [cell closeButtonRectForFrame:cellFrame];

        if (_closeClicked && NSMouseInRect(trackingStartPoint, iconRect, [self isFlipped]) &&
                ([self allowsBackgroundTabClosing] || [[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]])) {
            [cell setCloseButtonPressed:NSMouseInRect(currentPoint, iconRect, [self isFlipped])];
            [self setNeedsDisplay:YES];
            return;
        }

        float dx = fabs(currentPoint.x - trackingStartPoint.x);
        float dy = fabs(currentPoint.y - trackingStartPoint.y);
        float distance = sqrt(dx * dx + dy * dy);

        if (distance >= self.minimumTabDragDistance && !_didDrag && ![[PSMTabDragAssistant sharedDragAssistant] isDragging] &&
                [[self delegate] respondsToSelector:@selector(tabView:shouldDragTabViewItem:fromTabBar:)] &&
                [[self delegate] tabView:_tabView shouldDragTabViewItem:[cell representedObject] fromTabBar:self]) {
            _didDrag = YES;
            ILog(@"Start dragging with mouse down event %@ in window %p with frame %@", [self lastMouseDownEvent], self.window, NSStringFromRect(self.window.frame));
            [[PSMTabDragAssistant sharedDragAssistant] startDraggingCell:cell fromTabBar:self withMouseDownEvent:[self lastMouseDownEvent]];
        }
    }
}

#pragma mark - Group (chip) drag

- (PSMTabBarCell *)chipForPoint:(NSPoint)point {
    for (PSMTabBarCell *cell in _cells) {
        if (![cell isTabGroupChip]) {
            continue;
        }
        // An overflowed chip keeps a stale on-bar frame; hit-testing it would let a
        // click near the right edge toggle a group that is not actually drawn there.
        // Only match chips that are drawn in the bar.
        if (![self cellIsDrawnInBar:cell]) {
            continue;
        }
        if (NSPointInRect(point, [cell frame])) {
            return cell;
        }
    }
    return nil;
}

// The contiguous member tab cells (same group id) that follow `chip`.
- (NSArray<PSMTabBarCell *> *)tabGroupMemberCellsForChip:(PSMTabBarCell *)chip {
    const NSInteger chipIdx = [_cells indexOfObject:chip];
    if (chipIdx == NSNotFound) {
        return @[];
    }
    NSString *gid = chip.tabGroupIdentifier;
    NSMutableArray<PSMTabBarCell *> *members = [NSMutableArray array];
    for (NSInteger j = chipIdx + 1; j < (NSInteger)_cells.count; j++) {
        PSMTabBarCell *c = _cells[j];
        if (c.isTabGroupChip || ![c.tabGroupIdentifier isEqualToString:gid]) {
            break;
        }
        [members addObject:c];
    }
    return members;
}


- (void)otherMouseUp:(NSEvent *)theEvent
{
    // Middle click closes a tab, even if the click is not on the close button.
    if ([theEvent buttonNumber] == 2 && !_resizing) {
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        NSRect cellFrame;
        PSMTabBarCell *cell = [self cellForPoint:mousePt cellFrame:&cellFrame];
        NSRect mouseDownCellFrame;
        PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMiddleMouseDownEvent] locationInWindow] fromView:nil]
                                                cellFrame:&mouseDownCellFrame];
        if (cell && cell == mouseDownCell) {
            [self closeTabClick:cell button:theEvent.buttonNumber];
        }
    }
}

- (void)mouseUp:(NSEvent *)theEvent {
    _preDragSelectedTabIndex = NSNotFound;
    _haveInitialDragLocation = NO;
    if (_resizing) {
        _resizing = NO;
        [[NSCursor arrowCursor] set];
        return;
    }

    [self handleMouseUp:theEvent];

    _closeClicked = NO;
}

- (void)handleMouseUp:(NSEvent * _Nonnull)theEvent {
    const NSPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSRect cellFrame;
    PSMTabBarCell *const cell = [self cellForPoint:clickPoint cellFrame:&cellFrame];

    NSRect mouseDownCellFrame;
    PSMTabBarCell *mouseDownCell = [self cellForPoint:[self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil] cellFrame:&mouseDownCellFrame];
    const NSRect iconRect = [mouseDownCell closeButtonRectForFrame:mouseDownCellFrame];
    const BOOL clickedInCloseButton = NSMouseInRect(clickPoint, iconRect, [self isFlipped]);

    if (clickedInCloseButton &&
        cell.closeButtonVisible &&
        cell.hasCloseButton &&
        [mouseDownCell closeButtonPressed]) {
        // Clicked on close button
        [self closeTabClick:cell button:theEvent.buttonNumber];
        return;
    }

    if (cell == nil && [theEvent clickCount] == 2) {
        [self tabBarDoubleClick];
    }

    const BOOL mouseUpInSameCellAsMouseDown = NSMouseInRect(clickPoint, mouseDownCellFrame, [self isFlipped]);
    const NSPoint trackingStartPoint = [self convertPoint:[[self lastMouseDownEvent] locationInWindow] fromView:nil];
    const BOOL mouseDownWasInCloseButton = NSMouseInRect(trackingStartPoint, [cell closeButtonRectForFrame:cellFrame], [self isFlipped]);
    const BOOL closeButtonDoesNotInterfere = (!mouseDownWasInCloseButton ||
                                              [self disableTabClose] ||
                                              ![self allowsBackgroundTabClosing]);

    if (mouseUpInSameCellAsMouseDown && closeButtonDoesNotInterfere) {
        // Is a valid click on the tab.
        [mouseDownCell setCloseButtonPressed:NO];
        switch (theEvent.clickCount) {
            case 1:
                [self tabClick:cell];
                return;

            case 2:
                [self tabDoubleClick:cell];
                return;

            default:
                return;
        }
    }

    // A plain click on a group chip (no drag) toggles its collapsed state. Chips
    // are invisible to -cellForPoint:, so `cell` is nil here; resolve the chip at
    // both the down and up points so a click that starts on one chip and ends on
    // another does nothing. A chip DRAG (group move) sets _didDrag and is handled
    // elsewhere, so gate on !_didDrag -- the two are mutually exclusive.
    if (cell == nil && !_didDrag && theEvent.clickCount == 1) {
        PSMTabBarCell *downChip = [self chipForPoint:trackingStartPoint];
        PSMTabBarCell *upChip = [self chipForPoint:clickPoint];
        if (downChip != nil && downChip == upChip &&
            upChip.tabGroupIdentifier.length > 0 &&
            [[self delegate] respondsToSelector:@selector(tabView:toggleCollapseOfTabGroup:)]) {
            [[self delegate] tabView:_tabView toggleCollapseOfTabGroup:upChip.tabGroupIdentifier];
            return;
        }
    }

    // Weird cases we don't care about, like mouse down in one cell and mouse up in another.
    [mouseDownCell setCloseButtonPressed:NO];
    [self tabNothing:cell];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = nil;
    const NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSTabViewItem *item = [[self cellForPoint:point cellFrame:nil] representedObject];

    if (item && [[self delegate] respondsToSelector:@selector(tabView:menuForTabViewItem:)]) {
        menu = [[self delegate] tabView:_tabView menuForTabViewItem:item];
    }
    else if (!item) {
        // A right-click on a group chip (chips are invisible to -cellForPoint:)
        // gets the group's contextual menu.
        PSMTabBarCell *chip = [self chipForPoint:point];
        if (chip.tabGroupIdentifier.length > 0 &&
            [[self delegate] respondsToSelector:@selector(tabView:menuForTabGroup:)]) {
            menu = [[self delegate] tabView:_tabView menuForTabGroup:chip.tabGroupIdentifier];
        }
        // when the "LSUIElement hack" (issue #954) is enabled, the menu bar is inaccessible,
        // so show it as a context menu when right-clicking empty tabBar region
        if (!menu && [[[NSBundle mainBundle] infoDictionary] objectForKey:@"LSUIElement"]) {
            menu = [NSApp mainMenu];
        }
    }
    return menu;
}

- (void)resetCursorRects
{
    [super resetCursorRects];
    if ([self orientation] == PSMTabBarVerticalOrientation) {
        NSRect frame = [self frame];
        const CGFloat cursorX = (_tabLocation == PSMTab_RightTab) ? 0 : frame.size.width - 2;
        [self addCursorRect:NSMakeRect(cursorX, 0, 2, frame.size.height) cursor:[NSCursor resizeLeftRightCursor]];
    } else {
        const CGFloat edgeDragHeight = self.style.edgeDragHeight;
        if (edgeDragHeight == 0) {
            return;
        }
        switch (_tabLocation) {
            case PSMTab_TopTab:
                [self addCursorRect:NSMakeRect(0, 0, self.bounds.size.width, edgeDragHeight)
                             cursor:[NSCursor openHandCursor]];
                break;
            case PSMTab_BottomTab:
                [self addCursorRect:NSMakeRect(0,
                                               self.bounds.size.height - edgeDragHeight,
                                               self.bounds.size.width,
                                               edgeDragHeight)
                             cursor:[NSCursor openHandCursor]];
                break;

            case PSMTab_LeftTab:
            case PSMTab_RightTab:
                break;
        }
    }
}

#pragma mark -
#pragma mark Drag and Drop

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
    return YES;
}

#pragma mark NSDraggingSource

- (NSDraggingSession *)beginDraggingSessionWithItems:(NSArray<NSDraggingItem *> *)items event:(NSEvent *)event source:(id<NSDraggingSource>)source {
    ILog(@"Begin dragging tab bar control %p with event %@ source from\n%@",
         self, event, [NSThread callStackSymbols]);
    return [super beginDraggingSessionWithItems:items event:event source:source];
}

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session {
    return YES;
}

// File-level statics for tracking drag move frequency
#if PSM_DEBUG_DRAG_PERFORMANCE
static int gDragMoveCount = 0;
static CFAbsoluteTime gDragMoveLastTime = 0;
static CFAbsoluteTime gDragMoveFirstTime = 0;
#endif

- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint {
#if PSM_DEBUG_DRAG_PERFORMANCE
    // Reset drag move tracking
    gDragMoveCount = 0;
    gDragMoveLastTime = 0;
    gDragMoveFirstTime = 0;
    NSLog(@"[PSMTabBar] draggingSession:willBeginAtPoint: - drag session started");
#endif
    [[PSMTabDragAssistant sharedDragAssistant] draggingBeganAt:screenPoint];
}

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
#if PSM_DEBUG_DRAG_PERFORMANCE
    CFAbsoluteTime now = CACurrentMediaTime();
    gDragMoveCount++;

    if (gDragMoveFirstTime == 0) {
        gDragMoveFirstTime = now;
    }

    // Log every call to see actual frequency
    double sinceLast = gDragMoveLastTime > 0 ? (now - gDragMoveLastTime) * 1000 : 0;
    double elapsed = now - gDragMoveFirstTime;
    double avgFps = elapsed > 0 ? (gDragMoveCount / elapsed) : 0;

    // Log every 10th call, or first few calls
    NSLog(@"[PSMTabBar] draggingSession:movedToPoint: #%d, interval=%.1fms, avg=%.1f calls/sec",
          gDragMoveCount, sinceLast, avgFps);
    gDragMoveLastTime = now;
#endif

    [[PSMTabDragAssistant sharedDragAssistant] draggingMovedTo:screenPoint];
}

#pragma mark NSDraggingDestination

// [sender draggingLocation] is throttled and can be stale during tab drags
// (fresh and stale positions interleave, flapping the drop target between two
// spots); use the live mouse position instead, same workaround as
// SessionView's draggingUpdated:.
- (NSPoint)freshDragMouseLocation {
    return [self convertPoint:[self.window convertPointFromScreen:[NSEvent mouseLocation]]
                     fromView:nil];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound) {
        if ([[self delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:moveSourceWindow:)] &&
            ![[self delegate] tabView:[[sender draggingSource] tabView]
                shouldDropTabViewItem:[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject]
                             inTabBar:self
                     moveSourceWindow:nil]) {
            return NSDragOperationNone;
        }

        [[PSMTabDragAssistant sharedDragAssistant] draggingEnteredTabBar:self atPoint:[self freshDragMouseLocation]];
        return NSDragOperationMove;
    } else if ([[self delegate] respondsToSelector:@selector(tabView:draggingEnteredTabBarForSender:)]) {
        NSDragOperation op = [[self delegate] tabView:_tabView draggingEnteredTabBarForSender:sender];
        if (op != NSDragOperationNone) {
            [[PSMTabDragAssistant sharedDragAssistant] startAnimationWithOrientation:_orientation width:_cellOptimumWidth];
            [[PSMTabDragAssistant sharedDragAssistant] draggingEnteredTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        }
        return op;
    } else {
        return NSDragOperationNone;
    }
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    PSMTabBarCell *cell = [self cellForPoint:[self convertPoint:[sender draggingLocation] fromView:nil] cellFrame:nil];

    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound) {

        if ([[self delegate] respondsToSelector:@selector(tabView:shouldDropTabViewItem:inTabBar:moveSourceWindow:)] &&
            ![[self delegate] tabView:[[sender draggingSource] tabView]
                shouldDropTabViewItem:[[[PSMTabDragAssistant sharedDragAssistant] draggedCell] representedObject]
                             inTabBar:self
                     moveSourceWindow:nil]) {
            return NSDragOperationNone;
        }

        [[PSMTabDragAssistant sharedDragAssistant] draggingUpdatedInTabBar:self atPoint:[self freshDragMouseLocation]];
        return NSDragOperationMove;
    } else if ([[self delegate] respondsToSelector:@selector(tabView:shouldAcceptDragFromSender:)] &&
               [[self delegate] tabView:_tabView shouldAcceptDragFromSender:sender]) {
        [[PSMTabDragAssistant sharedDragAssistant] draggingUpdatedInTabBar:self atPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
        return NSDragOperationMove;
    } else if (cell) {
        //something that was accepted by the delegate was dragged on
        [_tabView selectTabViewItem:[cell representedObject]];
        return NSDragOperationCopy;
    }

    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
    [[PSMTabDragAssistant sharedDragAssistant] draggingExitedTabBar:self];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    // validate the drag operation only if there's a valid tab bar to drop into
    BOOL badType = [[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] == NSNotFound;
    if (badType && [[self delegate] respondsToSelector:@selector(tabView:shouldAcceptDragFromSender:)] &&
        ![[self delegate] tabView:_tabView shouldAcceptDragFromSender:sender]) {
        badType = YES;
    }
    return badType ||
           [[PSMTabDragAssistant sharedDragAssistant] destinationTabBar] != nil;
}

- (BOOL)_delegateAcceptsSender:(id <NSDraggingInfo>)sender {
    return [[self delegate] respondsToSelector:@selector(tabView:shouldAcceptDragFromSender:)] &&
           [[self delegate] tabView:_tabView shouldAcceptDragFromSender:sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    _haveInitialDragLocation = NO;
    if ([[[sender draggingPasteboard] types] indexOfObject:@"com.iterm2.psm.controlitem"] != NSNotFound ||
        [self _delegateAcceptsSender:sender]) {
        [[PSMTabDragAssistant sharedDragAssistant] performDragOperation:sender];
    } else if ([[self delegate] respondsToSelector:@selector(tabView:acceptedDraggingInfo:onTabViewItem:)]) {
        //forward the drop to the delegate
        [[self delegate] tabView:_tabView acceptedDraggingInfo:sender onTabViewItem:[[self cellForPoint:[self convertPoint:[sender draggingLocation] fromView:nil] cellFrame:nil] representedObject]];
    }
    return YES;
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)aPoint operation:(NSDragOperation)operation {
#if PSM_DEBUG_DRAG_PERFORMANCE
    // Log drag move summary
    CFAbsoluteTime elapsed = gDragMoveFirstTime > 0 ? (CACurrentMediaTime() - gDragMoveFirstTime) : 0;
    double avgFps = elapsed > 0 ? (gDragMoveCount / elapsed) : 0;
    NSLog(@"[PSMTabBar] draggingSession:endedAtPoint: - drag ended. Total moves: %d over %.2fs (avg %.1f calls/sec)",
          gDragMoveCount, elapsed, avgFps);
#endif

    _haveInitialDragLocation = NO;
    if (operation != NSDragOperationNone) {
        [self removeTabForCell:[[PSMTabDragAssistant sharedDragAssistant] draggedCell]];
        [[PSMTabDragAssistant sharedDragAssistant] finishDrag];
    } else {
        [[PSMTabDragAssistant sharedDragAssistant] draggedImageEndedAt:aPoint operation:operation];
    }
}

#pragma mark -
#pragma mark Actions

- (void)overflowMenuAction:(id)sender {
    [_tabView selectTabViewItem:[sender representedObject]];
    [self update];
}

- (void)closeTabClick:(id)sender button:(int)button {
    NSTabViewItem *item = [sender representedObject];
    [[sender retain] autorelease];
    [[item retain] autorelease];

    if ([[self delegate] respondsToSelector:@selector(tabView:shouldCloseTabViewItem:)]){
        if (![[self delegate] tabView:_tabView shouldCloseTabViewItem:item]){
            // fix mouse downed close button
            [sender setCloseButtonPressed:NO];
            return;
        }
    }

    if ([[self delegate] respondsToSelector:@selector(tabView:closeTab:button:)]) {
        [[self delegate] tabView:[self tabView] closeTab:[item identifier] button:button];
    }
}

- (void)tabClick:(id)sender {
    if ([sender representedObject]) {
        [_tabView selectTabViewItem:[sender representedObject]];
        [self update];
    }
}

- (void)tabDoubleClick:(id)sender {
    if ([[self delegate] respondsToSelector:@selector(tabView:doubleClickTabViewItem:)]) {
        [[self delegate] tabView:[self tabView] doubleClickTabViewItem:[sender representedObject]];
    }
}

- (void)tabBarDoubleClick {
    if ([[self delegate] respondsToSelector:@selector(tabViewDoubleClickTabBar:)]) {
        [[self delegate] tabViewDoubleClickTabBar:[self tabView]];
    }
}

- (void)addTab:(id)sender {
    if ([self.delegate respondsToSelector:@selector(tabViewDidClickAddTabButton:)]) {
        [self.delegate tabViewDidClickAddTabButton:self];
    }
}

- (void)tabNothing:(id)sender {
    [self update];  // takes care of highlighting based on state
}

- (BOOL)supportsMultiLineLabels {
    return [_style supportsMultiLineLabels];
}

- (void)frameDidChange:(NSNotification *)notification {
    //figure out if the new frame puts the control in the way of the resize widget
    NSRect resizeWidgetFrame = [[[self window] contentView] frame];
    resizeWidgetFrame.origin.x += resizeWidgetFrame.size.width - 22;
    resizeWidgetFrame.size.width = 22;
    resizeWidgetFrame.size.height = 22;

    [self update];
    // trying to address the drawing artifacts for the progress indicators - hackery follows
    // this one fixes the "blanking" effect when the control hides and shows itself
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:NO];
        [[cell indicator] setAnimate:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)viewWillStartLiveResize {
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:NO];
    }
    [self setNeedsDisplay:YES];
}

-(void)viewDidEndLiveResize {
    for (PSMTabBarCell *cell in _cells) {
        [[cell indicator] setAnimate:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    // Rebuild tracking areas for all visible cells based on their current frames.
    // This ensures tracking areas stay valid after view lifecycle events like
    // moving to a different window, display sleep/wake, etc.
    const NSPoint mousePoint = [self convertPoint:[[self window] pointFromScreenCoords:[NSEvent mouseLocation]]
                                         fromView:nil];

    for (PSMTabBarCell *cell in _cells) {
        if (![self cellIsDrawnInBar:cell]) {
            continue;
        }

        const NSRect cellFrame = [cell frame];

        // Rebuild cell tracking rect.
        [cell removeCellTrackingRectFrom:self];
        [cell setCellTrackingRect:cellFrame userData:nil assumeInside:NO view:self];

        // Update highlight state based on current mouse position.
        // This clears highlight if cursor is no longer in cell.
        [cell updateHighlight];
        if (NSMouseInRect(mousePoint, cellFrame, [self isFlipped])) {
            [cell setHighlighted:YES];
        }

        // Always remove close button tracking rect first.
        [cell removeCloseButtonTrackingRectFrom:self];

        // Rebuild close button tracking rect if applicable.
        if ([cell hasCloseButton] &&
            ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] ||
             [self allowsBackgroundTabClosing])) {
            const NSRect closeRect = [cell closeButtonRectForFrame:cellFrame];

            [cell setCloseButtonTrackingRect:closeRect userData:nil assumeInside:NO view:self];

            // Update close button highlight state for the selected tab only.
            if ([[cell representedObject] isEqualTo:[_tabView selectedTabViewItem]] &&
                [[NSApp currentEvent] type] != NSEventTypeLeftMouseDown &&
                NSMouseInRect(mousePoint, closeRect, [self isFlipped])) {
                [cell setCloseButtonOver:YES];
            } else {
                [cell setCloseButtonOver:NO];
            }
        } else {
            [cell setCloseButtonOver:NO];
        }
    }

    [self setNeedsDisplay:YES];
}

- (void)windowDidMove:(NSNotification *)aNotification {
    [self setNeedsDisplay:YES];
}

- (void)windowStatusDidChange:(NSNotification *)notification {
    // hide? must readjust things if I'm not supposed to be showing
    // this block of code only runs when the app launches
    if ([self hideForSingleTab] && ([_cells count] <= 1) && !_awakenedFromNib) {
        // must adjust frames now before display
        NSRect myFrame = [self frame];
        if ([self orientation] == PSMTabBarHorizontalOrientation) {
            if (partnerView) {
                NSRect partnerFrame = [partnerView frame];
                // above or below me?
                if (myFrame.origin.y - 22 > [partnerView frame].origin.y) {
                    // partner is below me
                    [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y + 21, myFrame.size.width, myFrame.size.height - 21)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x, partnerFrame.origin.y, partnerFrame.size.width, partnerFrame.size.height + 21)];
                } else {
                    // partner is above me
                    [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height - 21)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x, partnerFrame.origin.y - 21, partnerFrame.size.width, partnerFrame.size.height + 21)];
                }
                [partnerView setNeedsDisplay:YES];
                [self setNeedsDisplay:YES];
            } else {
                // for window movement
                NSRect windowFrame = [[self window] frame];
                [[self window] setFrame:NSMakeRect(windowFrame.origin.x, windowFrame.origin.y + 21, windowFrame.size.width, windowFrame.size.height - 21) display:YES];
                [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, myFrame.size.width, myFrame.size.height - 21)];
            }
        } else {
            if (partnerView) {
                NSRect partnerFrame = [partnerView frame];
                //to the left or right?
                if (myFrame.origin.x < [partnerView frame].origin.x){
                    // partner is to the left
                    [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, 1, myFrame.size.height)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x - myFrame.size.width + 1, partnerFrame.origin.y, partnerFrame.size.width + myFrame.size.width - 1, partnerFrame.size.height)];
                } else {
                    // partner to the right
                    [self setFrame:NSMakeRect(myFrame.origin.x + myFrame.size.width, myFrame.origin.y, 1, myFrame.size.height)];
                    [partnerView setFrame:NSMakeRect(partnerFrame.origin.x, partnerFrame.origin.y, partnerFrame.size.width + myFrame.size.width, partnerFrame.size.height)];
                }
                _tabBarWidth = myFrame.size.width;
                [partnerView setNeedsDisplay:YES];
                [self setNeedsDisplay:YES];
            } else {
                // for window movement
                NSRect windowFrame = [[self window] frame];
                [[self window] setFrame:NSMakeRect(windowFrame.origin.x + myFrame.size.width - 1, windowFrame.origin.y, windowFrame.size.width - myFrame.size.width + 1, windowFrame.size.height) display:YES];
                [self setFrame:NSMakeRect(myFrame.origin.x, myFrame.origin.y, 1, myFrame.size.height)];
            }
        }

        _isHidden = YES;

        if ([[self delegate] respondsToSelector:@selector(tabView:tabBarDidHide:)]) {
            [[self delegate] tabView:[self tabView] tabBarDidHide:self];
        }
    }

    [self setNeedsDisplay:YES];
     _awakenedFromNib = YES;
    [self update];
}

#pragma mark -
#pragma mark Menu Validation

- (BOOL)validateMenuItem:(NSMenuItem *)sender {
    return [[self delegate] respondsToSelector:@selector(tabView:validateOverflowMenuItem:forTabViewItem:)] ?
        [[self delegate] tabView:[self tabView] validateOverflowMenuItem:sender forTabViewItem:[sender representedObject]] : YES;
}

#pragma mark -
#pragma mark NSTabView Delegate

- (void)tabView:(NSTabView *)aTabView willAddTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willAddTabViewItem:)]){
        [[self delegate] tabView:aTabView willAddTabViewItem:tabViewItem];
    }
}

- (void)tabView:(NSTabView *)aTabView willInsertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)anIndex {
    if ([[self delegate] respondsToSelector:@selector(tabView:willInsertTabViewItem:atIndex:)]) {
        [[self delegate] tabView:aTabView willInsertTabViewItem:tabViewItem atIndex:anIndex];
    }
}

- (void)tabView:(NSTabView *)aTabView willRemoveTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willRemoveTabViewItem:)]) {
        [[self delegate] tabView:aTabView willRemoveTabViewItem:tabViewItem];
    }
}


- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    // here's a weird one - this message is sent before the "aDidChangeNumberOfTabViewItems"
    // message, thus I can end up updating when there are no cells, if no tabs were (yet) present
    if ([_cells count] > 0) {
        _keepSelectedTabInView = YES;
        [self update];
    }
    if ([[self delegate] respondsToSelector:@selector(tabView:didSelectTabViewItem:)]) {
        [[self delegate] tabView:aTabView didSelectTabViewItem:tabViewItem];
    }

    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}

- (void)tabView:(NSTabView *)tabView doubleClickTabViewItem:(NSTabViewItem *)tabViewItem {
}

- (BOOL)tabView:(NSTabView *)aTabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)]) {
        return (BOOL)[[self delegate] tabView:aTabView shouldSelectTabViewItem:tabViewItem];
    } else {
        return YES;
    }
}

- (void)tabView:(NSTabView *)aTabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([[self delegate] respondsToSelector:@selector(tabView:willSelectTabViewItem:)]) {
        [[self delegate] tabView:aTabView willSelectTabViewItem:tabViewItem];
    }
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)aTabView {
    // Reconcile in a pure tab-cell world: strip chip cells so the
    // representedObject matching and addTabViewItem:atIndex: (which uses
    // tabView indices) aren't thrown off by non-tab cells. Chips are
    // re-derived from the reconciled tab cells at the end.
    [self removeAllTabGroupChipCells];
    NSArray *tabItems = [_tabView tabViewItems];
    // go through cells, remove any whose representedObjects are not in [tabView tabViewItems]
    NSMutableArray *cellsToRemove = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        if (![tabItems containsObject:[cell representedObject]]) {
            [cellsToRemove addObject:cell];
        }
    }
    for (PSMTabBarCell *cell in cellsToRemove) {
        if ([[self delegate] respondsToSelector:@selector(tabView:didCloseTabViewItem:)]) {
            [[self delegate] tabView:aTabView didCloseTabViewItem:[cell representedObject]];
        }

        [self removeTabForCell:cell];
    }

    // go through tab view items, add cell for any not present
    NSMutableArray *cellItems = [self representedTabViewItems];
    int i = 0;
    for (NSTabViewItem *item in tabItems) {
        if (![cellItems containsObject:item]) {
            [self addTabViewItem:item atIndex:i];
        }
        i++;
    }

    // Re-derive chip cells now that the tab cells match the tab view.
    [self normalizeTabGroupChipCells];

    // A newly created tab is selected before its cell exists, and its title (hence width) may be set
    // asynchronously afterward. Flag it to be scrolled into view; reallyUpdate: re-checks each layout
    // until the tab settles, and manual scrolling releases the flag.
    _keepSelectedTabInView = YES;
    [self update];

    // pass along for other delegate responses
    if ([[self delegate] respondsToSelector:@selector(tabViewDidChangeNumberOfTabViewItems:)]) {
        [[self delegate] tabViewDidChangeNumberOfTabViewItems:aTabView];
    }
}

- (NSDragOperation)tabView:(NSTabView *)tabView draggingEnteredTabBarForSender:(id<NSDraggingInfo>)tagViewItem {
    return NSDragOperationNone;
}

- (BOOL)tabView:(NSTabView *)tabView shouldAcceptDragFromSender:(id<NSDraggingInfo>)tagViewItem {
    return NO;
}

- (NSTabViewItem *)tabView:(NSTabView *)tabView unknownObjectWasDropped:(id <NSDraggingInfo>)sender {
    return nil;
}

#pragma mark -
#pragma mark Tooltips

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)userData
{
    // Schedule updating the tooltip window's appearance after it's created
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateTooltipAppearance];
    });

    // A group chip has no tab view item, so the per-tab tooltip (Name/Profile/
    // Command) would read a nil session. Show the group's name instead, or no
    // tooltip if it is unnamed.
    PSMTabBarCell *chip = [self chipForPoint:point];
    if (chip) {
        id<PSMTabGroup> group = [self.tabGroupDataSource tabGroupWithIdentifier:chip.tabGroupIdentifier];
        return group.name.length > 0 ? group.name : @"";
    }

    if ([[self delegate] respondsToSelector:@selector(tabView:toolTipForTabViewItem:)]) {
        return [[self delegate] tabView:[self tabView] toolTipForTabViewItem:[[self cellForPoint:point cellFrame:nil] representedObject]];
    }
    return @"";
}

- (void)updateTooltipAppearance {
    NSAppearance *desiredAppearance = _style.accessoryAppearance;
    if (!desiredAppearance) {
        return;
    }

    // Tooltips just use the system light/dark mode, not that of the view that created them.
    // Since you generally only have one tooltip at a time, go find the one we assume is ours and
    // set its appearance properly.
    for (NSWindow *window in [NSApp windows]) {
        if ([[window className] isEqualToString:@"NSToolTipPanel"]) {
            window.appearance = desiredAppearance;
            break;
        }
    }
}


#pragma mark -
#pragma mark IB Palette

- (NSSize)minimumFrameSizeFromKnobPosition:(int)position {
    return NSMakeSize(100.0, 22.0);
}

- (NSSize)maximumFrameSizeFromKnobPosition:(int)knobPosition {
    return NSMakeSize(10000.0, 22.0);
}

- (void)placeView:(NSRect)newFrame {
    // this is called any time the view is resized in IB
    [self setFrame:newFrame];
    [self update];
}

- (void)changeIdentifier:(id)newIdentifier atIndex:(int)theIndex {
    NSTabViewItem *tabViewItem = [_tabView tabViewItemAtIndex:theIndex];
    assert(tabViewItem);
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            [tabViewItem setIdentifier:newIdentifier];
            return;
        }
    }
    assert(false);
}

#pragma mark -
#pragma mark Convenience

- (PSMTabBarCell *)cellWithIdentifier:(id)identifier {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell.representedObject identifier] == identifier) {
            return cell;
        }
    }
    return nil;
}

- (void)setIsProcessing:(BOOL)isProcessing forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.isProcessing = isProcessing;
}

- (void)setProgress:(PSMProgress)progress forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.progress = progress;
    [self syncTabProgressBars];
}

- (BOOL)tabIsHiddenInBarWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    // "Hidden in bar" = not drawn: in the overflow menu OR inside a collapsed
    // group. Keying on isInOverflowMenu alone missed a horizontal collapsed member
    // (zero frame, isInOverflowMenu==NO), so its inline progress fallback never
    // fired. A missing cell is treated as drawn (returns NO), as before.
    return cell != nil && ![self cellIsDrawnInBar:cell];
}

- (void)graphicDidChangeForTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    [self setNeedsDisplayInRect:cell.frame];
}

- (void)setIcon:(NSImage *)icon forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.hasIcon = (icon != nil);
}

- (void)setObjectCount:(NSInteger)objectCount forTabWithIdentifier:(id)identifier {
    PSMTabBarCell *cell = [self cellWithIdentifier:identifier];
    cell.count = objectCount;
}

- (void)initializeStateForCell:(PSMTabBarCell *)cell {
    [[cell indicator] setHidden:YES];
    [cell setHasIcon:NO];
    [cell setCount:0];
}

- (void)bindPropertiesForCell:(PSMTabBarCell *)cell andTabViewItem:(NSTabViewItem *)item {
    // bind my string value to the label on the represented tab
    // cell.title <- item.label
    [cell bind:@"title" toObject:item withKeyPath:@"label" options:nil];
    [_delegate tabView:_tabView updateStateForTabViewItem:item];
}

- (NSMutableArray *)representedTabViewItems {
    NSMutableArray *temp = [NSMutableArray arrayWithCapacity:[_cells count]];
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject]) {
            [temp addObject:[cell representedObject]];
        }
    }
    return temp;
}

- (id)cellForPoint:(NSPoint)point
         cellFrame:(NSRectPointer)outFrame {
    if ([self orientation] == PSMTabBarHorizontalOrientation &&
        !NSPointInRect(point, [self genericCellRectWithOverflow:_lainOutWithOverflow])) {
        return nil;
    }

    int i, cnt = [_cells count];
    for (i = 0; i < cnt; i++) {
        PSMTabBarCell *cell = [_cells objectAtIndex:i];

        // Chip cells are not tabs: they're not clickable, draggable, or a
        // drop target, so hit-testing skips them (a click over a chip is
        // treated as "no cell", e.g. so it doesn't suppress window drag).
        // Collapsed members are hidden (zero frame) and must not be hit either.
        if ([cell isTabGroupChip] || [cell isCollapsedHidden]) {
            continue;
        }
        if (NSPointInRect(point, [cell frame])) {
            if (outFrame) {
                *outFrame = [cell frame];
            }
            return cell;
        }
    }
    return nil;
}

// The last visible tab-or-placeholder cell. Chip cells are not tabs: callers
// use this as a drop target or selection anchor, so a chip (which represents
// no tab view item) must never be returned. Placeholders do count -- during a
// drag the trailing placeholder is the “past the end” drop slot.
- (PSMTabBarCell *)lastVisibleTab
{
    PSMTabBarCell *last = nil;
    for (PSMTabBarCell *cell in _cells) {
        if ([cell isInOverflowMenu]) {
            break;
        }
        if ([cell isTabGroupChip] || [cell isCollapsedHidden]) {
            continue;
        }
        last = cell;
    }
    return last;
}

// Number of visible tab cells. Chip cells are excluded: a window whose sole
// tab is in a one-tab group still has exactly one tab (the solitary-tab
// window-drag conversion keys off this).
- (int)numberOfVisibleTabs
{
    int count = 0;
    for (PSMTabBarCell *cell in _cells) {
        if ([cell isInOverflowMenu]) {
            break;
        }
        // A collapsed member is hidden in the bar but is still a real tab: this
        // count is the structural tab count (it drives the drag's one-placeholder-
        // per-tab distribution and the solitary-tab window-drag gate), NOT the
        // number drawn, so collapsed members must be counted. Only chips (which
        // are not tabs) are excluded.
        if (![cell isTabGroupChip]) {
            count++;
        }
    }
    return count;
}

#pragma mark -
#pragma mark Accessibility

- (NSString*)accessibilityRole {
    return NSAccessibilityTabGroupRole;
}

- (NSArray*)accessibilityChildren {
    NSMutableArray *childElements = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        if ([cell isInOverflowMenu]) {
            break;
        }
        if ([cell isTabGroupChip] || [cell isCollapsedHidden]) {
            // Chips represent no tab; collapsed members are off-screen. Either
            // one published here would create a phantom or invisible AX tab.
            // (Collapsed members remain in -accessibilityTabs, the full logical
            // list, exactly like overflowed tabs.)
            continue;
        }
        [childElements addObject:cell.element];
    }
    if (![_overflowPopUpButton isHidden]) {
        [childElements addObject:_overflowPopUpButton];
    }
    if (![_addTabButton isHidden]) {
        [childElements addObject:_addTabButton];
    }
    return childElements;
}

- (NSArray*)accessibilityTabs {
    NSMutableArray *tabElements = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        if ([cell isTabGroupChip]) {
            continue;
        }
        [tabElements addObject:cell.element];
    }
    return tabElements;
}

- (id)accessibilityHitTest:(NSPoint)point {
    for (id child in self.accessibilityChildren) {
        if (NSPointInRect(point, [child accessibilityFrame])) {
            return [child accessibilityHitTest:point];
        }
    }
    return self;
}

#pragma mark - iTerm Add On

- (void)setTabColor:(NSColor *)aColor forTabViewItem:(NSTabViewItem *)tabViewItem {
    BOOL updated = NO;

    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            if ([cell tabColor] != aColor) {
                updated = YES;
                [cell setTabColor:aColor];
            }
        }
    }

    if (updated) {
        [self update: NO];
    }
}

- (NSColor*)tabColorForTabViewItem:(NSTabViewItem*)tabViewItem {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            return [cell tabColor];
        }
    }
    return nil;
}

- (void)setTabGroupIdentifiers:(NSArray *)identifiers
               forTabViewItems:(NSArray<NSTabViewItem *> *)tabViewItems {
    // Match strictly by tab view item: a cell whose item is not listed (or a
    // tab whose cell is absent, e.g. the dragged tab mid-drag) is left alone.
    // Re-derive chips and relayout at most once, however many memberships
    // changed.
    NSMapTable *gidByItem = [NSMapTable mapTableWithKeyOptions:(NSMapTableObjectPointerPersonality |
                                                                NSMapTableStrongMemory)
                                                  valueOptions:NSMapTableStrongMemory];
    const NSUInteger count = MIN(identifiers.count, tabViewItems.count);
    for (NSUInteger i = 0; i < count; i++) {
        [gidByItem setObject:identifiers[i] forKey:tabViewItems[i]];
    }
    BOOL changed = NO;
    for (PSMTabBarCell *cell in _cells) {
        if ([cell isTabGroupChip] || [cell isPlaceholder]) {
            continue;
        }
        id item = [cell representedObject];
        id value = item ? [gidByItem objectForKey:item] : nil;
        if (!value) {
            continue;
        }
        NSString *gid = [value isKindOfClass:[NSString class]] ? value : nil;
        if (cell.tabGroupIdentifier != gid &&
            ![cell.tabGroupIdentifier isEqualToString:gid]) {
            RLog(@"tabGroup: cell %p group %@ -> %@",
                 cell, cell.tabGroupIdentifier, gid);
            cell.tabGroupIdentifier = gid;
            changed = YES;
        }
    }
    if (changed) {
        const NSUInteger cellCountBefore = _cells.count;
        [self normalizeTabGroupChipCells];
        if (_cells.count != cellCountBefore) {
            // A chip cell was inserted or removed. Route the relayout through the
            // dedicated collapse animator, which lays out every frame via
            // -_setupCells: so the new/removed chip is positioned correctly
            // throughout and its width tweens in lockstep with the other tabs
            // shrinking/growing. -_animateCells: (the default width animator) shifts
            // origins by accumulated width delta and never repositions a freshly
            // inserted cell, so the chip sits at its seed position for the whole
            // slide and snaps into place only at the end (space opens, then the chip
            // pops in).
            _collapseExpandPending = YES;
        }
        [self update:YES];
    }
}

- (void)setTabGroupCollapsedFlags:(NSArray<NSNumber *> *)flags
                  forTabViewItems:(NSArray<NSTabViewItem *> *)tabViewItems {
    // Mirror -setTabGroupIdentifiers:forTabViewItems:: match strictly by tab
    // view item and relayout at most once. Collapse doesn't change chip
    // derivation (that depends only on tabGroupIdentifier), so no re-normalize.
    NSMapTable *flagByItem = [NSMapTable mapTableWithKeyOptions:(NSMapTableObjectPointerPersonality |
                                                                NSMapTableStrongMemory)
                                                   valueOptions:NSMapTableStrongMemory];
    const NSUInteger count = MIN(flags.count, tabViewItems.count);
    for (NSUInteger i = 0; i < count; i++) {
        [flagByItem setObject:flags[i] forKey:tabViewItems[i]];
    }
    BOOL changed = NO;
    for (PSMTabBarCell *cell in _cells) {
        if ([cell isTabGroupChip] || [cell isPlaceholder]) {
            continue;
        }
        id item = [cell representedObject];
        NSNumber *value = item ? [flagByItem objectForKey:item] : nil;
        if (!value) {
            continue;
        }
        const BOOL collapsed = value.boolValue;
        if (cell.isCollapsedHidden != collapsed) {
            cell.isCollapsedHidden = collapsed;
            changed = YES;
        }
    }
    if (changed) {
        // Ask the next horizontal layout to run the dedicated collapse animator.
        // A non-animated caller snaps right after (via -updateWithoutAnimation),
        // cancelling it.
        _collapseExpandPending = YES;
        [self update:YES];
    }
}

// Enumerate each FULLY collapsed tab group: a chip whose following same-group
// members all exist and are all collapsed-hidden. The member count is derived
// from _cells (the members are still there), so no data-source round trip is
// needed. Used by the styles to draw the self-contained collapsed chip.
- (void)enumerateCollapsedTabGroupChipsWithBlock:(void (NS_NOESCAPE ^)(PSMTabBarCell *chip,
                                                                       NSInteger memberCount,
                                                                       NSString *gid))block {
    for (NSInteger i = 0; i < (NSInteger)_cells.count; i++) {
        PSMTabBarCell *chip = _cells[i];
        if (![chip isTabGroupChip] || chip.tabGroupIdentifier.length == 0) {
            continue;
        }
        // A chip that fell past the fit boundary is marked in-overflow but keeps a
        // stale on-bar frame (its members keep zero-width frames). Drawing its
        // collapsed pill there would ghost near the right edge over the last visible
        // tab and the "..." chevron; the expanded-run enumerator already excludes
        // overflowed groups (its member scan breaks on isInOverflowMenu). Skip a
        // chip that is not drawn in the bar.
        if (![self cellIsDrawnInBar:chip]) {
            continue;
        }
        const PSMTabGroupRun run = [self tabGroupRunAfterChipAtIndex:i];
        // Skip a group whose members are mid-collapse-slide (any still has a
        // width): the run enumeration draws its enclosing outline, and the
        // self-contained chip only takes over once the slide settles and its
        // members are zeroed. Other, settled collapsed groups still draw here.
        if (run.memberCount > 0 && run.allCollapsed && !run.anySized) {
            block(chip, run.memberCount, chip.tabGroupIdentifier);
        }
    }
}

// Like NSUnionRect, but a zero-WIDTH rect still contributes its x-position.
// NSUnionRect treats any zero-width/height rect as empty and returns the other
// operand, so unioning two zero-width member rects yields NSZeroRect -- collapsing
// the run's origin to (0,0). During a collapse/expand slide members really are
// zero-width for a frame, so use this to keep the run anchored at their x.
static NSRect PSMRunUnionRect(NSRect a, NSRect b) {
    const CGFloat minX = MIN(NSMinX(a), NSMinX(b));
    const CGFloat maxX = MAX(NSMaxX(a), NSMaxX(b));
    const CGFloat minY = MIN(NSMinY(a), NSMinY(b));
    const CGFloat maxY = MAX(NSMaxY(a), NSMaxY(b));
    return NSMakeRect(minX, minY, maxX - minX, maxY - minY);
}

- (void)enumerateTabGroupRunsWithRect:(NSRect (^)(PSMTabBarCell *))rectForCell
                                block:(void (NS_NOESCAPE ^)(PSMTabBarCell *,
                                                            NSRect,
                                                            PSMTabBarCell *,
                                                            NSString *))block {
    NSArray<PSMTabBarCell *> *cells = [self cells];
    NSRect (^rect)(PSMTabBarCell *) = rectForCell ?: ^NSRect(PSMTabBarCell *c) {
        return c.frame;
    };
    for (NSInteger i = 0; i < (NSInteger)cells.count; i++) {
        PSMTabBarCell *chip = cells[i];
        NSString *gid = chip.tabGroupIdentifier;
        if (![chip isTabGroupChip] || gid.length == 0) {
            continue;
        }
        NSRect tabsRect = NSZeroRect;
        PSMTabBarCell *firstTab = nil;
        BOOL any = NO;
        for (NSInteger j = i + 1; j < (NSInteger)cells.count; j++) {
            PSMTabBarCell *c = cells[j];
            // A collapsed member is hidden (zero frame): skip it so it never
            // enters the run's rect. A fully-collapsed run then leaves any==NO,
            // so no enclosing pill is drawn (the collapsed chip draws its own).
            // Exception: while a collapse slide runs, a collapsed member still has
            // a (shrinking) width, so keep it in the run and the outline encloses
            // it as it slides shut -- matching expand's growing outline.
            if (c.isCollapsedHidden && NSWidth(c.frame) <= 0) {
                continue;
            }
            // A drag interleaves placeholder cells between real ones; they're
            // transparent to the run, so skip (not break) so the run still
            // spans the group's members and grows to enclose the open drop
            // slot when a tab is dragged into the group. Two slot kinds are
            // unioned explicitly: an "end of group" join slot past the last
            // member, and the dragged member's OWN slot (it carries the
            // group's id; dropping there keeps membership, so the outline
            // must keep enclosing it rather than snapping down at drag start
            // and shrinking only as the slot collapses).
            if (c.isPlaceholder) {
                if ([c.tabGroupIdentifier isEqualToString:gid]) {
                    // The dragged member's own slot counts as part of the run
                    // (it can even BE the run, e.g. the first or sole member
                    // is being dragged and no real member precedes it).
                    tabsRect = any ? NSUnionRect(tabsRect, rect(c)) : rect(c);
                    any = YES;
                } else if (any && [c.joinsTabGroupIdentifier isEqualToString:gid]) {
                    tabsRect = NSUnionRect(tabsRect, rect(c));
                }
                continue;
            }
            if (c.isTabGroupChip || c.isInOverflowMenu ||
                ![c.tabGroupIdentifier isEqualToString:gid]) {
                break;
            }
            tabsRect = any ? PSMRunUnionRect(tabsRect, rect(c)) : rect(c);
            if (!firstTab) {
                firstTab = c;
            }
            any = YES;
        }
        if (any) {
            block(chip, tabsRect, firstTab, gid);
        }
    }
}

- (BOOL)cellPrecedingChipCoversInterGroupGap:(PSMTabBarCell *)chip {
    const NSInteger idx = [_cells indexOfObject:chip];
    if (idx == NSNotFound) {
        return NO;
    }
    for (NSInteger j = idx - 1; j >= 0; j--) {
        PSMTabBarCell *c = _cells[j];
        if (c.isPlaceholder) {
            continue;
        }
        // Previous real cell: a grouped tab -- or a (zero-frame) collapsed member
        // of the group before this one -- already outsets its right edge into the
        // shared gap. A plain (ungrouped) tab or a chip does not cover the gap.
        return !c.isTabGroupChip && c.tabGroupIdentifier.length > 0;
    }
    return NO;  // chip is first in the bar: outset normally
}

// The frame of the first full-size real tab cell in `cells`: skips chips and
// collapsed (zero-frame) members, requiring a nonzero width and height. Used to
// seed a chip's cross-axis and a vertical slide's reference geometry from a
// settled tab (every tab shares the bar's cell size). NSZeroRect if there is none
// (a bar of only collapsed groups). Shared so the "what is a valid reference cell"
// rule lives in one place.
+ (NSRect)firstFullSizeTabCellFrameInCells:(NSArray<PSMTabBarCell *> *)cells {
    for (PSMTabBarCell *c in cells) {
        if (![c isTabGroupChip] && ![c isCollapsedHidden] &&
            NSWidth(c.frame) > 0 && NSHeight(c.frame) > 0) {
            return c.frame;
        }
    }
    return NSZeroRect;
}

- (PSMTabBarCell *)firstNonMemberCellAfterChip:(PSMTabBarCell *)chip
                                       groupID:(NSString *)groupID {
    const NSInteger idx = [_cells indexOfObject:chip];
    if (idx == NSNotFound) {
        return nil;
    }
    for (NSInteger k = idx + 1; k < (NSInteger)_cells.count; k++) {
        PSMTabBarCell *c = _cells[k];
        if (c.isPlaceholder) {
            continue;
        }
        if (c.isTabGroupChip || ![c.tabGroupIdentifier isEqualToString:groupID]) {
            return c;
        }
    }
    return nil;
}

// Rebuild _cells so exactly one chip cell precedes each contiguous run of
// same-group tabs, derived from the tab cells' tabGroupIdentifier. Call
// after any change to the tab set, order, or membership. Idempotent.
- (void)normalizeTabGroupChipCells {
    NSMutableArray<PSMTabBarCell *> *tabCells = [NSMutableArray array];
    for (PSMTabBarCell *cell in _cells) {
        if (![cell isTabGroupChip]) {
            [tabCells addObject:cell];
        }
    }
    NSArray<PSMTabBarCell *> *normalized =
        [PSMTabBarControl cellsByInsertingTabGroupChipsInto:tabCells controlView:self];
    if ([normalized isEqualToArray:_cells]) {
        return;
    }
    [_cells setArray:normalized];
    // Seed each freshly created chip with a valid frame from its run's first tab
    // (correct height/position), placed just before it. cellsByInserting... makes
    // chips with a zero frame, and an animated relayout only tweaks width, so a
    // draw before the next full layout would otherwise show the chip collapsed to
    // zero height, blinking it.
    const BOOL horizontal = (_orientation == PSMTabBarHorizontalOrientation);
    // A COLLAPSED group's first member is a zero-frame cell, so seeding a chip
    // from it would give the chip a zero cross-axis (height on a horizontal bar)
    // and draw it shifted/degenerate. Take the cross-axis from any real-size cell
    // instead (every tab shares the bar's cell size).
    NSRect reference = [PSMTabBarControl firstFullSizeTabCellFrameInCells:_cells];
    if (NSIsEmptyRect(reference)) {
        // Every real cell is collapsed (a bar of only collapsed groups). Use the
        // standard cell rect for the cross-axis.
        reference = [self genericCellRectWithOverflow:_showAddTabButton];
    }
    for (NSInteger i = 0; i < (NSInteger)_cells.count; i++) {
        PSMTabBarCell *chip = _cells[i];
        if (![chip isTabGroupChip]) {
            continue;
        }
        for (NSInteger j = i + 1; j < (NSInteger)_cells.count; j++) {
            if ([_cells[j] isTabGroupChip]) {
                continue;
            }
            NSRect frame = [_cells[j] frame];
            if (horizontal) {
                frame.origin.y = reference.origin.y;
                frame.size.height = reference.size.height;
                // The chip index `i` is already in hand; use the index-based query
                // so this synchronous seeding pass stays O(cells) instead of the
                // O(cells^2) an -indexOfObject: rescan per chip would reintroduce.
                frame.size.width = [self widthOfTabGroupChipCellAtIndex:i];
            } else {
                frame.origin.x = reference.origin.x;
                frame.size.width = reference.size.width;
                frame.size.height = [self heightOfTabGroupChipCell:chip];
            }
            [chip setFrame:frame];
            break;
        }
    }
}

// Remove every chip cell from _cells (leaving only tab cells), used before
// tab<->cell index reconciliation runs.
- (void)removeAllTabGroupChipCells {
    NSIndexSet *chipIndexes = [_cells indexesOfObjectsPassingTest:^BOOL(PSMTabBarCell *cell, NSUInteger idx, BOOL *stop) {
        return [cell isTabGroupChip];
    }];
    if (chipIndexes.count > 0) {
        [_cells removeObjectsAtIndexes:chipIndexes];
    }
}

- (void)setIsPinned:(BOOL)pinned forTabViewItem:(NSTabViewItem *)tabViewItem {
    BOOL updated = NO;

    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            if ([cell isPinned] != pinned) {
                updated = YES;
                [cell setIsPinned:pinned];
            }
        }
    }

    if (updated) {
        [self update:YES];
    }
}

- (BOOL)isPinnedForTabViewItem:(NSTabViewItem *)tabViewItem {
    for (PSMTabBarCell *cell in _cells) {
        if ([cell representedObject] == tabViewItem) {
            return [cell isPinned];
        }
    }
    return NO;
}

- (void)modifierChanged:(NSNotification *)aNotification {
    NSUInteger mask = ([[[aNotification userInfo] objectForKey:kPSMTabModifierKey] unsignedIntegerValue]);
    if (mask == NSUIntegerMax) {
        mask = 0;
    }
    [self setModifier:mask];
}

- (NSString*)_modifierString {
    NSString *str = @"";
    if (_modifier & NSEventModifierFlagCommand) {
        str = [NSString stringWithFormat:@"⌘%@", str];
    }
    if (_modifier & NSEventModifierFlagShift) {
        str = [NSString stringWithFormat:@"⇧%@", str];
    }
    if (_modifier & NSEventModifierFlagOption) {
        str = [NSString stringWithFormat:@"⌥%@", str];
    }
    if (_modifier & NSEventModifierFlagControl) {
        str = [NSString stringWithFormat:@"^%@", str];
    }
    return str;
}

- (void)setModifier:(NSUInteger)mask {
    _modifier = mask;
    NSString *str = [self _modifierString];

    for (PSMTabBarCell *cell in _cells) {
        [cell setModifierString:str];
    }
    [self setNeedsDisplay:YES];
}

- (void)fillPath:(NSBezierPath*)path {
  [_style fillPath:path];
}

- (NSColor *)accessoryTextColor {
    return [_style accessoryTextColor] ?: [NSColor blackColor];
}

- (void)setTabsHaveCloseButtons:(BOOL)tabsHaveCloseButtons {
    _hasCloseButton = tabsHaveCloseButtons;

    for (PSMTabBarCell *cell in _cells) {
        [cell setHasCloseButton:tabsHaveCloseButtons];
    }
}

- (void)moveTabAtIndex:(NSInteger)sourceIndex toTabBar:(PSMTabBarControl *)destinationTabBar atIndex:(NSInteger)destinationIndex {
    assert(destinationTabBar != self);
    // sourceIndex/destinationIndex are tab indices. Chip cells make _cells no
    // longer 1:1 with tabs, so strip them from both bars, do the move in
    // pure tab-index space, then re-derive the chips.
    [self removeAllTabGroupChipCells];
    [destinationTabBar removeAllTabGroupChipCells];
    PSMTabBarCell *movingCell = _cells[sourceIndex];
    [destinationTabBar.cells insertObject:movingCell atIndex:destinationIndex];
    [movingCell setControlView:destinationTabBar];

    // Remove the tracking rects and bindings registered on the old tab.
    [movingCell removeCloseButtonTrackingRectFrom:self];
    [movingCell removeCellTrackingRectFrom:self];
    [self removeTabForCell:movingCell];

    if ([self.delegate respondsToSelector:@selector(tabView:willDropTabViewItem:inTabBar:)]) {
        [self.delegate tabView:self.tabView
           willDropTabViewItem:movingCell.representedObject
                      inTabBar:destinationTabBar];
    }

    [self.tabView removeTabViewItem:[movingCell representedObject]];
    [[destinationTabBar tabView] insertTabViewItem:[movingCell representedObject] atIndex:destinationIndex];

    // Rebind the cell to the new control.
    [destinationTabBar initializeStateForCell:movingCell];
    [destinationTabBar bindPropertiesForCell:movingCell andTabViewItem:[movingCell representedObject]];

    // Select the newly moved item in the destination tab view.
    [[destinationTabBar tabView] selectTabViewItem:[movingCell representedObject]];

    if ([self.delegate respondsToSelector:@selector(tabView:didDropTabViewItem:inTabBar:joiningGroupWithID:)]) {
        [self.delegate tabView:self.tabView
            didDropTabViewItem:movingCell.representedObject
                      inTabBar:destinationTabBar
            joiningGroupWithID:nil];
    }
    if ([self.tabView numberOfTabViewItems] == 0 &&
        [self.delegate respondsToSelector:@selector(tabView:closeWindowForLastTabViewItem:)]) {
        [self.delegate tabView:self.tabView closeWindowForLastTabViewItem:[movingCell representedObject]];
    }
    // Re-derive chip cells now that both bars' tab runs have settled.
    [self normalizeTabGroupChipCells];
    [self update];
    [destinationTabBar normalizeTabGroupChipCells];
    [destinationTabBar update];
}

- (void)setNeedsUpdate:(BOOL)needsUpdate {
    [self setNeedsUpdate:needsUpdate animate:NO];
}

- (void)setNeedsUpdate:(BOOL)needsUpdate animate:(BOOL)animate {
    _needsUpdateAnimate = _needsUpdateAnimate && animate;
    if (_needsUpdate == needsUpdate) {
        return;
    }
    if (!needsUpdate) {
        _needsUpdate = NO;
        return;
    }
    _needsUpdate = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateIfNeeded];
    });
}

- (void)updateIfNeeded {
    if (!_needsUpdate) {
        return;
    }
    [self setNeedsUpdate:_needsUpdateAnimate];
    [self update];
}


#pragma mark - NSDraggingSource

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    switch (context) {
        case NSDraggingContextWithinApplication:
            return NSDragOperationEvery;

        case NSDraggingContextOutsideApplication:
        default:
            return NSDragOperationNone;
    }
}

#pragma mark - PSMProgressIndicatorDelegate

- (void)progressIndicatorNeedsUpdate {
    [self setNeedsUpdate:YES];
}

@end
