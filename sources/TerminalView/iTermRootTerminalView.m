//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"

#import "DebugLogging.h"
#import "iTermLayoutCalculator.h"

#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSView+iTerm.h"
#import "NSWindow+iTerm.h"
#import "PTYTabView.h"
#import "PTYTabView.h"
#import "PTYWindow.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermApplication.h"
#import "iTermDragHandleView.h"
#import "iTermFakeWindowTitleLabel.h"
#import "iTermGenericStatusBarContainer.h"
#import "iTermImageView.h"
#import "iTermPreferences.h"
#import "iTermStandardWindowButtonsView.h"
#import "iTermStatusBarViewController.h"
#import "iTermStoplightHotbox.h"
#import "iTermTabBarControlView.h"
#import "iTermToolbeltView.h"
#import "iTermUserDefaults.h"
#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "iTermWindowSizeView.h"

const CGFloat iTermStandardButtonsViewHeight = 25;
const CGFloat iTermStandardButtonsViewWidth = 69;
const CGFloat iTermStoplightHotboxWidth = iTermStandardButtonsViewWidth + 28 + 24;
const CGFloat iTermStoplightHotboxHeight = iTermStandardButtonsViewHeight + 8;
const CGFloat kDivisionViewHeight = 1;

const NSInteger iTermRootTerminalViewWindowNumberLabelMargin = 6;
const NSInteger iTermRootTerminalViewWindowNumberLabelWidth = 40;
// Padding after the compact proxy icon when no window number follows it.
static const CGFloat iTermRootTerminalViewCompactProxyIconExtraPadding = 4;

static const CGFloat iTermWindowNameBesideTabsLeftMargin = 6;
// Wide enough to read as a separator on its own, so the name needs no rule or
// capsule to divide it from the first tab. A capsule here would read as a tab.
static const CGFloat iTermWindowNameBesideTabsRightMargin = 14;
// A long window name must not crowd out the tabs it sits beside, so it is
// truncated rather than allowed to grow without bound.
static const CGFloat iTermWindowNameBesideTabsMaximumWidth = 180;
// Below this the tail ellipsis leaves too few characters to identify a window,
// so showing nothing is more honest than showing “My…”.
static const CGFloat iTermWindowNameBesideTabsMinimumWidth = 44;
// Separates the name from the tab labels beside it by texture rather than
// color, which not every reader can distinguish.
static const CGFloat iTermWindowNameBesideTabsTracking = 0.25;
// Applied to the window number's color to sit the name just below the tab
// labels. The one place the name's weight is decided: the label's own
// alphaValue stays at 1 so this does not compound with it.
static const CGFloat iTermWindowNameBesideTabsAlpha = 0.55;

static const CGFloat kMinimumToolbeltSizeInPoints = 100;
static const CGFloat kMinimumToolbeltSizeAsFractionOfWindow = 0.05;
static const CGFloat kMaximumToolbeltSizeAsFractionOfWindow = 0.5;

static const CGFloat iTermCompactProxyIconSize = 16;
static const CGFloat iTermCompactProxyIconLeftMargin = 4;
static const CGFloat iTermCompactProxyIconRightMargin = 2;

typedef struct {
    CGFloat top;
    CGFloat bottom;
} iTermDecorationHeights;

@interface iTermRootTerminalView()<
    iTermTabBarControlViewDelegate,
    iTermDragHandleViewDelegate,
    iTermGenericStatusBarContainer,
    iTermStoplightHotboxDelegate>

@property(nonatomic, strong) PTYTabView *tabView;
@property(nonatomic, strong) iTermTabBarControlView *tabBarControl;
@property(nonatomic, strong) SolidColorView *divisionView;
@property(nonatomic, strong) iTermToolbeltView *toolbelt;
@property(nonatomic, strong) iTermDragHandleView *verticalTabBarDragHandle;

@end

@interface iTermTabBarBacking : NSView<iTermTabBarControlViewContainer>
@property (nonatomic) BOOL hidesWhenTabBarHidden;
@property (nonatomic, readonly) NSVisualEffectView *visualEffectView;
@end

@implementation iTermTabBarBacking

- (instancetype)init {
    self = [super initWithFrame:NSMakeRect(0, 0, 100, 100)];
    if (self) {
        [self addWindowColorView];

        _visualEffectView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        _visualEffectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSVisualEffectState state = NSVisualEffectStateActive;
        if (![iTermAdvancedSettingsModel allowTabbarInTitlebarAccessoryBigSur]) {
            state = NSVisualEffectStateFollowsWindowActiveState;
        }
        _visualEffectView.state = state;

        _visualEffectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        _visualEffectView.material = NSVisualEffectMaterialTitlebar;
        [self addSubview:_visualEffectView];

        self.autoresizesSubviews = YES;
    }
    return self;
}

- (void)addWindowColorView {
    if (![iTermAdvancedSettingsModel allowTabbarInTitlebarAccessoryBigSur]) {
        return;
    }
    NSView *windowColorView = [[NSView alloc] initWithFrame:self.bounds];
    windowColorView.wantsLayer = YES;
    windowColorView.layer = [[CALayer alloc] init];
    windowColorView.layer.backgroundColor = [[NSColor windowBackgroundColor] CGColor];
    windowColorView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:windowColorView];
}

- (void)tabBarControlViewWillHide:(BOOL)hidden {
    if (_hidesWhenTabBarHidden || !hidden) {
        [self setHidden:hidden];
    }
}

@end

@implementation iTermRootTerminalView {
    BOOL _tabViewFrameReduced;
    BOOL _haveShownToolbelt;
    iTermStoplightHotbox *_stoplightHotbox;
    iTermStandardWindowButtonsView *_standardWindowButtonsView;
    NSMutableDictionary<NSNumber *, NSButton *> *_standardButtons;
    NSString *_windowTitle;
    // Snapshot of the inputs last used to render _windowTitleLabel. It lets us
    // skip the expensive attributed-string build + alignment layout when nothing
    // that affects the rendered label has changed. The title is polled ~once per
    // second per visible session even while idle, so without this guard many
    // open windows burn CPU rebuilding an identical label (issue 12982).
    iTermWindowTitleLabelInputs *_lastRenderedWindowTitleLabelInputs;
    NSNumber *_windowNumber;
    NSTextField *_windowNumberLabel;
    NSTextField *_windowNameBesideTabsLabel;
    // Cached measurement; see -windowNameBesideTabsTextWidth.
    CGFloat _windowNameBesideTabsTextWidth;
    BOOL _windowNameBesideTabsTextWidthValid;
    iTermFakeWindowTitleLabel *_windowTitleLabel;
    iTermTabBarBacking *_tabBarBacking;
    iTermGenericStatusBarContainer *_statusBarContainer;
    NSDictionary *_desiredToolbeltProportions;
    iTermWindowSizeView *_windowSizeView;

    iTermLayerBackedSolidColorView *_titleBackgroundView;
    NSVisualEffectView *_titleBackgroundVEV;

    iTermWindowBorderView *_windowBorderView;
    BOOL _cornerRadiusDetectionFailed;

    iTermImageView *_backgroundImage;
    iTermLayerBackedSolidColorView *_notchMask;
    iTermCompactProxyIconView *_compactProxyIconView;
}

- (instancetype)initWithFrame:(NSRect)frameRect
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate,PSMTabBarControlDelegate>)tabBarDelegate
                     delegate:(id<iTermRootTerminalViewDelegate, iTermToolbeltViewDelegate>)delegate {
    self = [super initWithFrame:frameRect color:color];
    if (self) {
        _delegate = delegate;

        self.autoresizesSubviews = YES;
        _leftTabBarPreferredWidth = round([iTermPreferences doubleForKey:kPreferenceKeyLeftTabBarWidth]);
        [self setLeftTabBarWidthFromPreferredWidth];

        _backgroundImage = [[iTermImageView alloc] init];
        _backgroundImage.frame = self.bounds;
        _backgroundImage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _backgroundImage.hidden = YES;
        [self addSubview:_backgroundImage];

        // Create the tab view.
        self.tabView = [[PTYTabView alloc] initWithFrame:self.bounds];
        self.tabView.drawsBackground = NO;
        _tabView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        _tabView.autoresizesSubviews = YES;
        _tabView.allowsTruncatedLabels = NO;
        _tabView.controlSize = NSControlSizeSmall;
        _tabView.tabViewType = NSNoTabsNoBorder;
        _tabView.swipeHandler = delegate;
        [self addSubview:_tabView];

        // Create the tab bar.
        NSRect tabBarFrame = self.bounds;
        tabBarFrame.size.height = _tabBarControl.height;
        _tabBarBacking = [[iTermTabBarBacking alloc] init];
        _tabBarBacking.hidesWhenTabBarHidden = [delegate rootTerminalViewShouldHideTabBarBackingWhenTabBarIsHidden];
        _tabBarBacking.autoresizesSubviews = YES;

        self.tabBarControl = [[iTermTabBarControlView alloc] initWithFrame:tabBarFrame];
        self.tabBarControl.height = [delegate rootTerminalViewHeightOfTabBar:self];

        _tabBarControl.itermTabBarDelegate = self;

        NSRect stoplightFrame = NSMakeRect(0,
                                           0,
                                           iTermStoplightHotboxWidth,
                                           iTermStoplightHotboxHeight);
        _stoplightHotbox = [[iTermStoplightHotbox alloc] initWithFrame:stoplightFrame];
        [self addSubview:_stoplightHotbox];
        _stoplightHotbox.hidden = YES;
        _stoplightHotbox.delegate = self;
        
        NSUInteger theModifier =
            [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]];
        if (theModifier == NSUIntegerMax) {
            theModifier = 0;
        }
        [_tabBarControl setModifier:theModifier];
        _tabBarControl.insets = [self.delegate tabBarInsets];
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_BottomTab:
                _tabBarControl.orientation = PSMTabBarHorizontalOrientation;
                [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
                break;

            case PSMTab_TopTab:
                _tabBarControl.orientation = PSMTabBarHorizontalOrientation;
                [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
                break;

            case PSMTab_LeftTab:
                _tabBarControl.orientation = PSMTabBarVerticalOrientation;
                [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMaxXMargin)];
                break;

            case PSMTab_RightTab:
                _tabBarControl.orientation = PSMTabBarVerticalOrientation;
                [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMinXMargin)];
                break;
        }
        [self addSubview:_tabBarBacking];
        [_tabBarBacking addSubview:_tabBarControl];
        _tabBarControl.tabView = _tabView;
        [_tabView setDelegate:_tabBarControl];
        _tabBarControl.delegate = tabBarDelegate;
        _tabBarControl.hideForSingleTab = NO;

        // Create the toolbelt with its current default size.
        _toolbeltWidth = [iTermPreferences floatForKey:kPreferenceKeyDefaultToolbeltWidth];

        self.toolbelt = [[iTermToolbeltView alloc] initWithFrame:[self toolbeltFrameInWindow:nil]
                                                        delegate:(id)_delegate];
        // Wait until whoever is creating the window sets it to its proper size before laying out the toolbelt.
        // The hope is that the window controller will call updateToolbeltProportionsIfNeeded during this spin
        // of the runloop, but if not we'll get it next time 'round.
        [self setToolbeltProportions:[iTermToolbeltView savedProportions]];
        _toolbelt.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
        [self addSubview:_toolbelt];
        [self updateToolbeltForWindow:nil];

        _windowNumberLabel = [NSTextField newLabelStyledTextField];
        _windowNumberLabel.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
        _windowNumberLabel.alphaValue = 0.75;
        _windowNumberLabel.hidden = YES;
        _windowNumberLabel.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);
        [self addSubview:_windowNumberLabel];

        _windowNameBesideTabsLabel = [NSTextField newLabelStyledTextField];
        // Always the small size: this label only appears when the tab bar is
        // visible, which is when the window number label is small too.
        if (@available(macOS 10.16, *)) {
            _windowNameBesideTabsLabel.font = [NSFont titleBarFontOfSize:[NSFont smallSystemFontSize]];
        } else {
            _windowNameBesideTabsLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        }
        // Quietness is carried entirely by the text color, so that there is one
        // number to change rather than two that multiply.
        _windowNameBesideTabsLabel.alphaValue = 1;
        _windowNameBesideTabsLabel.hidden = YES;
        _windowNameBesideTabsLabel.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);
        [self addSubview:_windowNameBesideTabsLabel];

        _windowTitleLabel = [iTermFakeWindowTitleLabel newLabelStyledTextField];
        _windowTitleLabel.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
        _windowTitleLabel.alphaValue = 1;
        _windowTitleLabel.alignment = NSTextAlignmentCenter;
        _windowTitleLabel.hidden = YES;
        _windowTitleLabel.autoresizingMask = (NSViewMinYMargin | NSViewWidthSizable);
        [self addSubview:_windowTitleLabel];
        
        _windowBorderView = [[iTermWindowBorderView alloc] initWithFrame:self.bounds];
        _windowBorderView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _windowBorderView.cornerRadius =
            [iTermAdvancedSettingsModel squareWindowCorners] ? 0 : [iTermWindowCornerRadiusDetector fallbackCornerRadius];
        [self addSubview:_windowBorderView];

        _notchMask = [[iTermLayerBackedSolidColorView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0) color:[NSColor blackColor]];
        _notchMask.hidden = YES;
        [self addSubview:_notchMask];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(advancedSettingsDidChange:)
                                                     name:iTermAdvancedSettingsDidChange
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _tabBarControl.itermTabBarDelegate = nil;
    _verticalTabBarDragHandle.delegate = nil;
}

- (void)advancedSettingsDidChange:(NSNotification *)notification {
    [self updateBorderViews];
    [self updateWindowNameBesideTabs];
}

- (void)setDelegate:(id<iTermRootTerminalViewDelegate>)delegate {
    _delegate = delegate;
    _tabView.swipeHandler = delegate;
}

- (void)invalidateAutomaticTabBarBackingHiding {
    _tabBarBacking.hidesWhenTabBarHidden = [self.delegate rootTerminalViewShouldHideTabBarBackingWhenTabBarIsHidden];
    if (_tabBarControl.isHidden) {
        _tabBarBacking.hidden = _tabBarBacking.hidesWhenTabBarHidden;
    }
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *view = [super hitTest:point];
    if (!_tabBarControlOnLoan && !_windowNumberLabel.hidden && view == _windowNumberLabel && !_tabBarControl.isHidden) {
        return _tabBarControl;
    } else if (!_tabBarControlOnLoan && !_windowNameBesideTabsLabel.hidden && view == _windowNameBesideTabsLabel && !_tabBarControl.isHidden) {
        // Same as the window number: the name is painted over the strip, so
        // clicks belong to the tab bar underneath it.
        return _tabBarControl;
    } else if (!_windowTitleLabel.hidden && view == _windowTitleLabel) {
        return self;
    } else {
        return view;
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (!_windowTitleLabel.hidden && event.clickCount == 2) {
        const NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        const CGFloat titleBarHeight = _tabBarControl.height;
        NSRect rect = NSMakeRect(0, self.bounds.size.height - titleBarHeight, self.bounds.size.width, titleBarHeight);
        if (NSPointInRect(point, rect)) {
            [self.window it_titleBarDoubleClick];
        }
    }
    [super mouseUp:event];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (_windowTitleLabel.hidden) {
        return nil;
    }
    return [_tabBarControl menuForEvent:event];
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (CGFloat)leftInsetForWindowButtons {
    if (@available(macOS 26, *)) {
        const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        switch (preferredStyle) {
            case TAB_STYLE_MINIMAL:
                return 2.5;
            case TAB_STYLE_COMPACT:
                return 6 + 3;
            case TAB_STYLE_DARK:
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                break;
        }
    }
    return 6;
}

- (CGFloat)widthForStandardButtonsView {
    if (@available(macOS 26, *)) {
        const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        switch (preferredStyle) {
            case TAB_STYLE_COMPACT:
                return iTermStandardButtonsViewWidth + 3;
            case TAB_STYLE_MINIMAL:
            case TAB_STYLE_DARK:
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                break;
        }
    }
    return iTermStandardButtonsViewWidth;
}

- (CGFloat)strideForWindowButtons {
    if (@available(macOS 26, *)) {
        const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        switch (preferredStyle) {
            case TAB_STYLE_MINIMAL:
                return 23;
            case TAB_STYLE_COMPACT:
            case TAB_STYLE_DARK:
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                break;
        }
    }
    return 20;
}

- (NSEdgeInsets)insetsForStoplightHotbox {
    if (![self.delegate enableStoplightHotbox]) {
        NSEdgeInsets insets = NSEdgeInsetsZero;
        const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        insets.bottom = -[self.delegate rootTerminalViewStoplightButtonsOffset:self];
        switch (preferredStyle) {
            case TAB_STYLE_MINIMAL:
                if (@available(macOS 26, *)) {
                    // Use fixed value on macOS 26 regardless of tab bar height.
                    // This matches the default tab bar height of 38: (38-25)/2 = 6.5
                    insets.left = insets.right = 6.5;
                } else {
                    insets.left = insets.right = MAX(0, -insets.bottom);
                }
                break;
            case TAB_STYLE_COMPACT:
                if (@available(macOS 26, *)) {
                    insets.left = insets.right = 3;
                } else {
                    insets.left = insets.right = 0;
                }
                break;
            case TAB_STYLE_DARK:
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                insets.left = insets.right = 0;
                break;
        }

        insets.left = [self retinaRound:insets.left];
        insets.top = [self retinaRound:insets.top];
        insets.bottom = [self retinaRound:insets.bottom];
        insets.right = [self retinaRound:insets.right];

        return insets;
    }

    const CGFloat hotboxSideInset = (iTermStoplightHotboxWidth - [self widthForStandardButtonsView]) / 2.0;
    const CGFloat hotboxVerticalInset = (iTermStoplightHotboxHeight - iTermStandardButtonsViewHeight) / 2.0;
    return NSEdgeInsetsMake(hotboxVerticalInset, hotboxSideInset, hotboxVerticalInset, hotboxSideInset);
}

- (NSRect)frameForStandardWindowButtons {
    const NSEdgeInsets insets = [self insetsForStoplightHotbox];
    CGFloat height;
    if ([self.delegate enableStoplightHotbox]) {
        height = iTermStoplightHotboxHeight;
    } else {
        height = iTermStandardButtonsViewHeight;
    }
    NSRect frame = NSMakeRect(insets.left,
                              self.frame.size.height - height + insets.bottom + 1,
                              [self widthForStandardButtonsView],
                              iTermStandardButtonsViewHeight);
    return [self retinaRoundRect:frame];
}

// Vertical origin that centers a label's cap height on the tab bar strip, where
// the window number and the window name sit side by side.
- (CGFloat)tabBarStripLabelOriginYForFont:(NSFont *)font {
    const PSMTabPosition tabPosition = [iTermPreferences intForKey:kPreferenceKeyTabPosition];
    const CGFloat tabBarHeight = (tabPosition == PSMTab_LeftTab || tabPosition == PSMTab_RightTab) ? 26.0 : _tabBarControl.height;
    const CGFloat baselineOffset = -font.descender;
    const CGFloat capHeight = font.capHeight;
    const CGFloat myHeight = self.frame.size.height;
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    CGFloat shift = (preferredStyle == TAB_STYLE_MINIMAL) ? 0 : 1;
    if (@available(macOS 26, *)) {
        if (preferredStyle == TAB_STYLE_MINIMAL) {
            shift = 1;  // Move down by 3 points on macOS 26 for minimal theme
        }
    }
    return myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset - shift;
}

- (NSRect)frameForWindowNumberLabel {
    if (_tabBarControlOnLoan) {
        return NSZeroRect;
    }
    [_windowNumberLabel sizeToFit];
    const NSRect standardButtonsFrame = [self frameForStandardWindowButtons];
    const CGFloat windowNumberHeight = _windowNumberLabel.frame.size.height;
    NSRect rect = NSMakeRect(NSMaxX(standardButtonsFrame) + [self compactProxyIconWidthIncludingMargin] + iTermRootTerminalViewWindowNumberLabelMargin,
                             [self tabBarStripLabelOriginYForFont:_windowNumberLabel.font],
                             iTermRootTerminalViewWindowNumberLabelWidth,
                             windowNumberHeight);
    return [self retinaRoundRect:rect];
}

// Width the tab bar's left inset reserves before the window name: the stoplight
// buttons, the proxy icon, and either the window number's box or the padding
// that stands in for it when the number is hidden.
//
// -tabBarInsetsForCompactWindow and the name's own frame must both come from
// here. They are not interchangeable with the real button frame: this reserves
// -compactTabBarStoplightButtonsWidth (75 by default) where
// NSMaxX(-frameForStandardWindowButtons) is 69, and 95 again with the stoplight
// hotbox enabled. Positioning the label from the button frame drew it left of
// the gap actually reserved for it.
- (CGFloat)widthOfDecorationsBeforeWindowNameBesideTabs {
    CGFloat stoplightButtonsWidth = MAX(0, [iTermAdvancedSettingsModel compactTabBarStoplightButtonsWidth]);
    if (@available(macOS 26, *)) {
        stoplightButtonsWidth += 3;
    }
    const CGFloat proxyIconWidth = [self compactProxyIconWidthIncludingMargin];
    const CGFloat afterProxyIcon =
        ([self.delegate rootTerminalViewWindowNumberLabelShouldBeVisible]
         ? (iTermRootTerminalViewWindowNumberLabelMargin * 2 + iTermRootTerminalViewWindowNumberLabelWidth)
         : (proxyIconWidth > 0 ? iTermRootTerminalViewCompactProxyIconExtraPadding : 0));
    return stoplightButtonsWidth + proxyIconWidth + afterProxyIcon;
}

// X origin of the window name: after the stoplight buttons, the proxy icon and
// the window number, which together read as the window's identity.
- (CGFloat)leadingEdgeForWindowNameBesideTabs {
    return ([self widthOfDecorationsBeforeWindowNameBesideTabs] +
            iTermWindowNameBesideTabsLeftMargin);
}

// The per-tab minimum pushed into the tab bar, which is what decides when the
// bar can no longer fit every tab. Kept in one place because the window name's
// reservation used to derive it independently and the two picked different
// advanced settings, so the name took space the tabs needed. The reservation now
// asks the tab bar instead, which is why this has a single caller.
- (int)tabBarCellMinWidth {
    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabNumber]) {
        return [iTermAdvancedSettingsModel minCompactTabWidth];
    }
    return [iTermAdvancedSettingsModel minTabWidth];
}

// A tab is somewhere to go and the window name is only context for the tabs, so
// the name gives up its space rather than crowd the tabs out of the bar.
//
// The tab bar owns the rule for what fits -- collapsed group chips, pinned tabs,
// its own margins and the overflow chevron all change the answer -- so ask it
// rather than re-deriving it here. The estimate this replaced omitted the bar's
// left margin, counted tab view items rather than cells (overstating what the
// tabs need whenever a group is collapsed to a chip), and hardcoded the right
// margin at whatever the style happened to return.
- (CGFloat)allowanceForWindowNameBesideTabs {
    // The tab bar's frame is not assigned until after the insets are, so its own
    // width is a pass stale here. The strip minus the toolbelt is what the
    // layout calculator starts from.
    //
    // Not -_toolbelt.frame: that is not resized until -updateToolbeltFrameForWindow
    // later in the same pass, so during a live toolbelt drag it lags the width the
    // tab bar is sized against by the drag delta and the name over-reserves, which
    // near the overflow boundary squeezes a cell under its minimum for that frame.
    // -constrainToolbeltWidth has not run yet either, so take the clamp it is about
    // to apply rather than the raw ivar: this is the value the layout inputs floor.
    const CGFloat toolbeltWidth = ([self shouldShowToolbelt]
                                   ? floor([self maximumToolbeltWidthForViewWidth:NSWidth(self.frame)])
                                   : 0);
    const CGFloat stripWidth = NSWidth(self.frame) - toolbeltWidth;
    // -tabBarInsetsForCompactWindow reserves this after the name, so it is space
    // the tabs never get either. Ignoring it let a large setting crowd the tabs,
    // which is the one thing this allowance exists to prevent.
    const CGFloat extraSpace = MAX(0, [iTermAdvancedSettingsModel extraSpaceBeforeCompactTopTabBar]);
    const CGFloat maximumInset = [self.tabBarControl maximumLeftInsetFittingAllCellsMinimallyForWidth:stripWidth];
    return (maximumInset -
            [self leadingEdgeForWindowNameBesideTabs] -
            iTermWindowNameBesideTabsRightMargin -
            extraSpace);
}

// The width the name wants, measured from the string rather than read off the
// label. -fittingSize makes a text field lay itself out to answer, and this sits
// on -layoutSubviews' path, which runs on every resize and drag frame.
- (CGFloat)naturalWindowNameBesideTabsTextWidth {
    // Nothing can truncate against an unconstrained width, so this out-param is
    // always NO here and the caller compares against its own allowance instead.
    BOOL truncated = NO;
    const NSRect rect = [_windowNameBesideTabsLabel.stringValue
                            it_boundingRectWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
                                         attributes:[self windowNameBesideTabsMetricAttributes]
                                          truncated:&truncated];
    return ceil(NSWidth(rect));
}

- (CGFloat)measuredWindowNameBesideTabsTextWidth {
    if (_tabBarControlOnLoan || _windowNameBesideTabsLabel.stringValue.length == 0) {
        return 0;
    }
    const CGFloat allowance = MIN(iTermWindowNameBesideTabsMaximumWidth,
                                  [self allowanceForWindowNameBesideTabs]);
    const CGFloat natural = [self naturalWindowNameBesideTabsTextWidth];
    if (natural > allowance) {
        // The name cannot be shown in full: it is truncated, or hidden when the
        // allowance drops below the readable minimum. This fires only for a named
        // window whose name is actually being squeezed -- not on every layout
        // pass -- so it records the starving state for a field report of "the
        // window name beside the tabs has no room" without logging in the common
        // case. The tab count and strip width are the two inputs that starve it.
        RLog(@"windowNameBesideTabs squeezed: name=%@ natural=%.0f allowance=%.0f cells=%lu cellMinWidth=%d stripWidth=%.0f",
             _windowNameBesideTabsLabel.stringValue, natural, allowance,
             (unsigned long)self.tabBarControl.cells.count, self.tabBarControl.cellMinWidth,
             NSWidth(self.frame));
    }
    // The minimum gates truncation, not slack. Applying it to the space left
    // over hid a name that would have fitted whole: “A” in 30 points of slack
    // neither truncates nor takes anything the tabs need, so the reason to hide
    // it -- that the tail ellipsis leaves too little to identify a window by --
    // does not apply to it.
    if (natural > allowance && allowance < iTermWindowNameBesideTabsMinimumWidth) {
        return 0;
    }
    return MIN(allowance, natural);
}

// Drops the cached width so the next read measures again. Call whenever the text
// or the geometry the allowance depends on could have moved.
- (void)invalidateWindowNameBesideTabsTextWidth {
    _windowNameBesideTabsTextWidthValid = NO;
}

// Cached for the duration of a layout pass. One pass asks three times -- the
// hidden check in -layoutWindowPaneDecorations, the label's own frame, and the
// tab bar's inset via -windowNameBesideTabsWidthIncludingMargin -- and each read
// measures text and walks the whole allowance. -layoutSubviews runs on every
// resize and drag frame, so the repeat was not free.
- (CGFloat)windowNameBesideTabsTextWidth {
    if (!_windowNameBesideTabsTextWidthValid) {
        _windowNameBesideTabsTextWidth = [self measuredWindowNameBesideTabsTextWidth];
        _windowNameBesideTabsTextWidthValid = YES;
    }
    return _windowNameBesideTabsTextWidth;
}

- (CGFloat)windowNameBesideTabsWidthIncludingMargin {
    const CGFloat textWidth = [self windowNameBesideTabsTextWidth];
    if (textWidth == 0) {
        return 0;
    }
    return (iTermWindowNameBesideTabsLeftMargin +
            textWidth +
            iTermWindowNameBesideTabsRightMargin);
}

- (NSRect)frameForWindowNameBesideTabsLabel {
    const CGFloat textWidth = [self windowNameBesideTabsTextWidth];
    if (textWidth == 0) {
        return NSZeroRect;
    }
    [_windowNameBesideTabsLabel sizeToFit];
    NSRect rect = NSMakeRect([self leadingEdgeForWindowNameBesideTabs],
                             [self tabBarStripLabelOriginYForFont:_windowNameBesideTabsLabel.font],
                             textWidth,
                             _windowNameBesideTabsLabel.frame.size.height);
    return [self retinaRoundRect:rect];
}

- (NSRect)frameForWindowTitleLabel {
    return [self frameForWindowTitleLabel:_windowTitleLabel
                              hasSubtitle:_windowTitleLabel.subtitle.length > 0
                           getLeftAligned:nil];
}

- (NSRect)frameForWindowTitleLabel:(NSTextField *)textField
                       hasSubtitle:(BOOL)hasSubtitle
                    getLeftAligned:(BOOL *)leftAlignedPtr {
    if (_tabBarControlOnLoan) {
        return NSZeroRect;
    }
    const CGFloat tabBarHeight = _tabBarControl.height;
    const CGFloat baselineOffset = -textField.font.descender;
    const CGFloat capHeight = textField.font.capHeight;
    const CGFloat myHeight = self.frame.size.height;
    const NSEdgeInsets insets = [self.delegate tabBarInsets];

    // Prefer to center it, using the same inset on both sides. There's no need
    // to have an inset on the right otherwise so if the title doesn't fit then
    // left-align it and make it as wide as the available space.
    // This mirrors what NSWindow's title does.
    const CGFloat mostGenerousInset = MAX(MAX(insets.left, insets.right), iTermRootTerminalViewWindowNumberLabelMargin);
    const CGFloat containerWidth = NSWidth(self.frame) - ([self shouldShowToolbelt] ? NSWidth(_toolbelt.frame) : 0);
    const NSSize fittingSize = textField.fittingSize;
    const CGFloat desiredWidth = fittingSize.width;
    CGFloat leftInset = mostGenerousInset;
    CGFloat rightInset = mostGenerousInset;
    CGFloat proposedWidth = containerWidth - leftInset - rightInset;
    const CGFloat overage = desiredWidth - proposedWidth;
    if (overage > 0) {
        rightInset = MAX(4, rightInset - overage);
        if (leftAlignedPtr) {
            DLog(@"Use left alignment with text “%@” desiredWidth %@, proposedWidth %@, containerWidth %@",
                 textField.stringValue, @(desiredWidth), @(proposedWidth), @(containerWidth));
            *leftAlignedPtr = YES;
        }
    }
    if (@available(macOS 26, *)) {
        if (leftAlignedPtr && [iTermAdvancedSettingsModel leftAlignTitleBarMinimalTahoe]) {
            *leftAlignedPtr = YES;
        }
    }
    CGFloat y;
    if (hasSubtitle) {
        y = [self retinaRound:myHeight - (tabBarHeight - fittingSize.height) / 2.0 - ceil(fittingSize.height)];
    } else {
        y = [self retinaRound:myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset];
        if (@available(macOS 26, *)) {
            y -= 1.5;
        }
    }
    NSRect rect = NSMakeRect([self retinaRound:leftInset],
                             y,
                             ceil(MAX(0, containerWidth - leftInset - rightInset)),
                             ceil(fittingSize.height));
    return [self retinaRoundRect:rect];
}

- (NSWindowButton *)windowButtonTypes {
    static NSWindowButton buttons[] = {
        NSWindowCloseButton,
        NSWindowMiniaturizeButton,
        NSWindowZoomButton
    };
    return buttons;
}

- (NSInteger)numberOfWindowButtons {
    return 3;
}

- (void)viewDidMoveToWindow {
    if (!self.window) {
        return;
    }
    [self didChangeCompactness];
    for (int i = 0; i < self.numberOfWindowButtons; i++) {
        NSButton *button = _standardButtons[@(self.windowButtonTypes[i])];
        if (self.windowButtonTypes[i] == NSWindowZoomButton) {
            button.target = _standardWindowButtonsView;
            button.action = @selector(zoomButtonEvent);
        } else {
            button.target = self.window;
        }
    }
}

- (void)didChangeCompactness {
    id<PTYWindow> ptyWindow = self.window.ptyWindow;
    const BOOL needCustomButtons = (ptyWindow.isCompact && [self.delegate rootTerminalViewShouldDrawStoplightButtons]);
    if (!needCustomButtons) {
        [_standardWindowButtonsView removeFromSuperview];
        _standardWindowButtonsView = nil;
        [_compactProxyIconView removeFromSuperview];
        _compactProxyIconView = nil;
        if ([self.delegate rootTerminalViewShouldRevealStandardWindowButtons]) {
            for (int i = 0; i < self.numberOfWindowButtons; i++) {
                [[self.window standardWindowButton:self.windowButtonTypes[i]] setHidden:NO];
            }
        }
        return;
    }
    if (_standardWindowButtonsView) {
        return;
    }

    // This is a compact window that gets special handling for the stoplights buttons.
    CGFloat x = self.leftInsetForWindowButtons;
    const CGFloat stride = self.strideForWindowButtons;
    _standardWindowButtonsView = [[iTermStandardWindowButtonsView alloc] initWithFrame:[self frameForStandardWindowButtons]];
    _standardWindowButtonsView.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);
    [self addSubview:_standardWindowButtonsView];

    const NSUInteger styleMask = self.window.styleMask;
    _standardButtons = [[NSMutableDictionary alloc] init];
    for (int i = 0; i < self.numberOfWindowButtons; i++) {
        NSButton *button = [NSWindow standardWindowButton:self.windowButtonTypes[i]
                                             forStyleMask:styleMask];
        NSRect frame = button.frame;
        frame.origin.x = x;
        frame.origin.y = 4;
        button.frame = frame;

        [_standardWindowButtonsView addSubview:button];
        _standardButtons[@(self.windowButtonTypes[i])] = button;
        if (self.windowButtonTypes[i] == NSWindowZoomButton) {
            // 😠
            // In issue 8401 a user reported that option-clicking the zoom button doesn't work after
            // exiting full screen.
            //
            // A disassembly of -[NSWindow _setNeedsZoom:] shows that option-clicking only works if
            // -[NSWindow _lastLeftHit] == -[NSWindow standardWindowButton:2]. So for some reason,
            // Apple intended option+zoom to only work with their own zoom button.
            //
            // Chrome ran into the same thing here:
            // https://bugs.chromium.org/p/chromium/issues/detail?id=393808
            //
            // Worth reading for the mention of _evilHackToClearlastLeftHitInWindow.
            //
            // Their analysis is different than mine. I see that _lastLeftHit is actually MY button,
            // which is not what they saw. I suspect a different etiology.
            //
            // I don't recall why I implemented zoomButtonEvent: in the first place; I suspect it
            // was a less well-informed attempt to work around this issue when I added compact
            // windows originally. Since I can't use the "real" button for this window, this seems
            // like the only reasonable fix.
            //
            // Apologies to my future self for whatever bugs this introduces.
            button.target = _standardWindowButtonsView;
            button.action = @selector(zoomButtonEvent);
        }
        x += stride;
        dispatch_async(dispatch_get_main_queue(), ^{
            [button setNeedsDisplay:YES];
        });
    }

    [self createCompactProxyIconButtonIfNeeded];
    [self layoutSubviews];
}

- (BOOL)shouldShowCompactProxyIcon {
    return [iTermPreferences boolForKey:kPreferenceKeyEnableProxyIcon];
}

- (CGFloat)compactProxyIconWidthIncludingMargin {
    if ([self shouldShowCompactProxyIcon]) {
        return iTermCompactProxyIconLeftMargin + iTermCompactProxyIconSize + iTermCompactProxyIconRightMargin;
    }
    return 0;
}

- (void)createCompactProxyIconButtonIfNeeded {
    [_compactProxyIconView removeFromSuperview];
    _compactProxyIconView = nil;

    if (![self shouldShowCompactProxyIcon]) {
        return;
    }

    const NSRect stoplightFrame = [self frameForStandardWindowButtons];
    // Stoplight buttons are 12pt tall at y=4 within the buttons view.
    const CGFloat buttonSize = 12;
    const CGFloat buttonYInView = 4;
    const CGFloat buttonCenterY = NSMinY(stoplightFrame) + buttonYInView + buttonSize / 2.0;
    const CGFloat y = buttonCenterY - iTermCompactProxyIconSize / 2.0 + 1;
    NSRect frame = NSMakeRect(NSMaxX(stoplightFrame) + iTermCompactProxyIconLeftMargin,
                              y,
                              iTermCompactProxyIconSize,
                              iTermCompactProxyIconSize);
    _compactProxyIconView = [[iTermCompactProxyIconView alloc] initWithFrame:frame];
    _compactProxyIconView.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);
    [self addSubview:_compactProxyIconView];
}

- (void)updateProxyIcon {
    if (!_compactProxyIconView) {
        return;
    }
    _compactProxyIconView.url = self.window.representedURL;
}

- (void)updateCompactProxyIconFrame {
    if (!_compactProxyIconView) {
        return;
    }
    const NSRect stoplightFrame = [self frameForStandardWindowButtons];
    const CGFloat buttonSize = 12;
    const CGFloat buttonYInView = 4;
    const CGFloat buttonCenterY = NSMinY(stoplightFrame) + buttonYInView + buttonSize / 2.0;
    const CGFloat y = buttonCenterY - iTermCompactProxyIconSize / 2.0 + 1;
    _compactProxyIconView.frame = NSMakeRect(NSMaxX(stoplightFrame) + iTermCompactProxyIconLeftMargin,
                                               y,
                                               iTermCompactProxyIconSize,
                                               iTermCompactProxyIconSize);
}

- (void)flagsChanged:(NSEvent *)event {
    if (_standardWindowButtonsView) {
        NSUInteger modifiers = ([NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask);
        BOOL optionKey = modifiers & NSEventModifierFlagOption ? YES : NO;
        
        [_standardWindowButtonsView setOptionModifier:optionKey];
    }
    [super flagsChanged:event];
}

- (NSRect)frameForTitleBackgroundView {
    const CGFloat height = [_delegate rootTerminalViewHeightOfTabBar:self];
    return NSMakeRect(0,
                      self.frame.size.height - height,
                      self.frame.size.width,
                      height);
}

- (void)drawRect:(NSRect)dirtyRect {
}

- (NSRect)frameForLeftBorderView {
    return NSMakeRect(0, 0, 1, self.bounds.size.height);
}

- (NSRect)frameForRightBorderView {
    return NSMakeRect(self.bounds.size.width - 1, 0, 1, self.bounds.size.height);
}

- (NSRect)frameForTopBorderView {
    return NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1);
}

- (NSRect)frameForBottomBorderView {
    return NSMakeRect(0, 0, self.bounds.size.width, 1);
}

- (void)updateTitleAndBorderViews {
    const BOOL wantsTitleBackgroundView = [_delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar];
    if (wantsTitleBackgroundView) {
        if (!_titleBackgroundView) {
            _titleBackgroundView = [[iTermLayerBackedSolidColorView alloc] initWithFrame:self.frameForTitleBackgroundView];
            _titleBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        }
        _titleBackgroundView.color = [_delegate rootTerminalViewTabBarBackgroundColorIgnoringTabColor:NO];
        _titleBackgroundView.frame = self.frameForTitleBackgroundView;
        if (_titleBackgroundView.superview != self) {
            [self insertSubview:_titleBackgroundView atIndex:1];
        }

        // The Compact tab style's selected backgroundColor is clearColor on
        // purpose: it expects an NSVisualEffectMaterialTitlebar view to be
        // visible beneath. With 2+ tabs that view is iTermTabBarBacking's VEV;
        // when the fake title bar replaces the tab bar we must provide our own.
        const BOOL wantsVEV = ([iTermPreferences intForKey:kPreferenceKeyTabStyle] == TAB_STYLE_COMPACT);
        if (wantsVEV) {
            if (!_titleBackgroundVEV) {
                _titleBackgroundVEV = [[NSVisualEffectView alloc] initWithFrame:self.frameForTitleBackgroundView];
                _titleBackgroundVEV.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
                NSVisualEffectState state = NSVisualEffectStateActive;
                if (![iTermAdvancedSettingsModel allowTabbarInTitlebarAccessoryBigSur]) {
                    state = NSVisualEffectStateFollowsWindowActiveState;
                }
                _titleBackgroundVEV.state = state;
                _titleBackgroundVEV.blendingMode = NSVisualEffectBlendingModeWithinWindow;
                _titleBackgroundVEV.material = NSVisualEffectMaterialTitlebar;
            }
            _titleBackgroundVEV.frame = self.frameForTitleBackgroundView;
            if (_titleBackgroundVEV.superview != self) {
                [self addSubview:_titleBackgroundVEV
                      positioned:NSWindowBelow
                      relativeTo:_titleBackgroundView];
            }
        } else {
            [_titleBackgroundVEV removeFromSuperview];
        }
    } else {
        [_titleBackgroundView removeFromSuperview];
        [_titleBackgroundVEV removeFromSuperview];
    }

    [self updateBorderViews];
    [self updateTextColors];
}

// A plain #rrggbb value carries no alpha and is drawn at 75% opacity for
// backward compatibility; a four-part #rrggbbaa value carries its own alpha.
// p3# works for either form. The optional alpha byte is split off here and the
// remaining #rrggbb is handed to colorFromHexString: so that shared parser
// (used by many callers) is not changed to accept alpha. Returns nil if unset
// or unparseable.
static NSColor *iTermWindowBorderColorFromSetting(NSString *setting) {
    if (setting.length == 0) {
        return nil;
    }
    NSString *prefix = @"";
    NSString *hex = setting;
    if ([hex hasPrefix:@"p3#"]) {
        prefix = @"p3#";
        hex = [hex substringFromIndex:3];
    } else if ([hex hasPrefix:@"#"]) {
        prefix = @"#";
        hex = [hex substringFromIndex:1];
    }
    CGFloat alpha = 0.75;
    if (hex.length == 8) {
        unsigned int a = 0;
        if (![[NSScanner scannerWithString:[hex substringFromIndex:6]] scanHexInt:&a]) {
            return nil;
        }
        alpha = a / 255.0;
        hex = [hex substringToIndex:6];
    }
    NSColor *color = [NSColor colorFromHexString:[prefix stringByAppendingString:hex]];
    if (color == nil) {
        return nil;
    }
    return [color colorWithAlphaComponent:alpha];
}

- (NSColor *)resolvedWindowBorderColor {
    NSColor *focused = iTermWindowBorderColorFromSetting([iTermAdvancedSettingsModel windowBorderColor]);
    NSColor *unfocused = iTermWindowBorderColorFromSetting([iTermAdvancedSettingsModel windowBorderColorUnfocused]);
    NSColor *base = self.window.isKeyWindow ? (focused ?: unfocused) : (unfocused ?: focused);
    if (base == nil) {
        return [NSColor colorWithWhite:0.5 alpha:0.75];
    }
    return base;
}

// Returns the window's outer corner radius (concentric with the system mask).
// The border is drawn fully inside the window, so updateBorderViews subtracts
// half the border width to get the stroke's centerline radius. Updated on
// cache miss by the early-return path in updateBorderViews.
- (CGFloat)resolvedWindowBorderCornerRadius {
    if ([iTermAdvancedSettingsModel squareWindowCorners]) {
        return 0;
    }
    NSWindow *window = self.window;
    NSNumber *cached = (window == nil) ? nil : [iTermWindowCornerRadiusDetector cachedCornerRadiusFor:window];
    if (cached == nil) {
        return [iTermWindowCornerRadiusDetector fallbackCornerRadius];
    }
    return MAX(0, cached.doubleValue);
}

- (void)updateBorderViews {
    NSWindow *window = self.window;

    // Hide the border until the detector has cached a radius for this window
    // state. Otherwise on a translucent window our own stroke is the only
    // opaque content in the corner of the captured frame and the SSE fit
    // converges on it instead of the system mask. If detection has already
    // failed once for this view, fall through to the static fallback.
    if (window != nil
        && ![iTermAdvancedSettingsModel squareWindowCorners]
        && !_cornerRadiusDetectionFailed
        && [iTermWindowCornerRadiusDetector cachedCornerRadiusFor:window] == nil) {
        _windowBorderView.hidden = YES;
        __weak __typeof(self) weakSelf = self;
        [iTermWindowCornerRadiusDetector detectCornerRadiusFor:window
                                                    completion:^(CGFloat radius, BOOL success) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) { return; }
            if (!success) {
                strongSelf->_cornerRadiusDetectionFailed = YES;
            }
            [strongSelf updateBorderViews];
        }];
        return;
    }

    _windowBorderView.hidden = NO;
    // The border view's autoresizing does not reliably track the root view (it
    // can be left at a stale size from an earlier window size), which would
    // stroke the heavy border as an inner rectangle inset from the real window
    // edge. layoutSubviews positions every other subview explicitly, so do the
    // same here and keep the border flush with the window bounds.
    _windowBorderView.frame = self.bounds;
    // Draw the stroke entirely inside the window so it has a uniform width on
    // edges and corners and does not depend on the system mask clipping its
    // outer half (which left the curved corners thinner than the straight
    // edges and dusted them with semi-transparent pixels). The centerline is
    // inset by half the border width, so its corner radius is the window's
    // outer radius minus that inset to keep the outer edge concentric with the
    // window corner.
    const CGFloat borderWidth = 1;
    _windowBorderView.borderWidth = borderWidth;
    _windowBorderView.outset = 0;
    _windowBorderView.cornerRadius = MAX(0, [self resolvedWindowBorderCornerRadius] - borderWidth / 2);
    _windowBorderView.haveLeftEdge = self.delegate.haveLeftBorder;
    _windowBorderView.haveTopEdge = self.delegate.haveTopBorder;
    _windowBorderView.haveRightEdge = self.delegate.haveRightBorderRegardlessOfScrollBar;
    _windowBorderView.haveBottomEdge = self.delegate.haveBottomBorder;
    _windowBorderView.borderColor = [self resolvedWindowBorderColor];
}

- (void)setUseMetal:(BOOL)useMetal {
    if (useMetal == _useMetal) {
        return;
    }
    _useMetal = useMetal;
    self.tabView.drawsBackground = NO;
    [self updateTitleAndBorderViews];

    [_divisionView removeFromSuperview];
    _divisionView = nil;

    [self updateDivisionViewAndWindowNumberLabel];
}

- (void)viewDidChangeEffectiveAppearance {
    RLog(@"iTermRootTerminalView viewDidChangeEffectiveAppearance -> %@ (window key=%@ main=%@ appActive=%@)",
         self.effectiveAppearance.name,
         @(self.window.isKeyWindow), @(self.window.isMainWindow), @(NSApp.isActive));
    // This can be called from within -[NSWindow setStyleMask:]
    dispatch_async(dispatch_get_main_queue(), ^{
        RLog(@"iTermRootTerminalView appearance-change block -> rootTerminalViewDidChangeEffectiveAppearance");
        [self.delegate rootTerminalViewDidChangeEffectiveAppearance];
    });
    [self updateBorderViews];
}

- (void)windowTitleDidChangeTo:(NSString *)title {
    _windowTitle = [title copy];

    [self setWindowTitleLabelToString:_windowTitle
                             subtitle:[self.delegate rootTerminalViewCurrentTabSubtitle]
                                 icon:[self.delegate rootTerminalViewCurrentTabIcon]];
    if (!_windowTitleLabel.hidden) {
        [self layoutWindowPaneDecorations];
    }
    [self updateWindowNameBesideTabs];
}

- (void)setSubtitle:(NSString *)subtitle {
    [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle
                             subtitle:subtitle
                                 icon:_windowTitleLabel.windowIcon];
}

// The attributes that decide how wide the name draws. Color and truncation do
// not change its metrics, so the measurement takes only these and the drawn
// string builds on them: the measured width and the drawn width are then one
// expression rather than two that have to agree.
- (NSDictionary *)windowNameBesideTabsMetricAttributes {
    return @{
        NSFontAttributeName: _windowNameBesideTabsLabel.font,
        NSKernAttributeName: @(iTermWindowNameBesideTabsTracking)
    };
}

// Rebuilds the label's styled text. The color lives here rather than in
// -textColor because the tracking forces an attributed string anyway.
- (void)applyWindowNameBesideTabsAttributes {
    NSString *name = _windowNameBesideTabsLabel.stringValue;
    if (name.length == 0) {
        return;
    }
    // An attributed string carries its own truncation, so the label's
    // lineBreakMode does not reach it.
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    // The delegate returns nil when it has no tab bar color to offer, and the
    // name must still be dimmed in that case: applying the alpha only inside a
    // nil check drew it at full strength, reading as a peer of the tab titles
    // rather than as context for them.
    NSColor *decorationColor = ([self.delegate rootTerminalViewTabBarTextColorForWindowNumber] ?:
                                [NSColor labelColor]);
    NSMutableDictionary *attributes = [[self windowNameBesideTabsMetricAttributes] mutableCopy];
    attributes[NSParagraphStyleAttributeName] = paragraphStyle;
    attributes[NSForegroundColorAttributeName] = [decorationColor colorWithAlphaComponent:iTermWindowNameBesideTabsAlpha];
    _windowNameBesideTabsLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:name
                                                                                      attributes:attributes];
}

// Returns YES if the name changed, meaning the tab bar insets are now stale.
- (BOOL)updateWindowNameBesideTabsText {
    NSString *name = [self.delegate rootTerminalViewWindowNameBesideTabs] ?: @"";
    if ([name isEqualToString:_windowNameBesideTabsLabel.stringValue]) {
        return NO;
    }
    _windowNameBesideTabsLabel.stringValue = name;
    _windowNameBesideTabsLabel.toolTip = name.length > 0 ? name : nil;
    [self applyWindowNameBesideTabsAttributes];
    [self invalidateWindowNameBesideTabsTextWidth];
    return YES;
}

- (void)updateWindowNameBesideTabs {
    // Called outside a layout pass, so nothing has invalidated the cache yet and
    // the width is needed both before and after the text changes.
    [self invalidateWindowNameBesideTabsTextWidth];
    const CGFloat widthBefore = [self windowNameBesideTabsWidthIncludingMargin];
    const BOOL textChanged = [self updateWindowNameBesideTabsText];
    const CGFloat widthAfter = [self windowNameBesideTabsWidthIncludingMargin];
    // The text alone is not enough to tell whether anything moved. Returning the
    // tab bar from loan leaves the same string in the label while it is still
    // latched hidden from when the width was forced to 0, so ask whether it can
    // be shown at all as well.
    const BOOL shouldBeHidden = (widthAfter == 0);
    if (!textChanged && shouldBeHidden == _windowNameBesideTabsLabel.isHidden) {
        return;
    }
    if (widthBefore == widthAfter && !shouldBeHidden && !_windowNameBesideTabsLabel.isHidden) {
        // The reservation is unchanged, so the tab bar's inset is still right and
        // only this label's own text moved. In Always mode the name follows the
        // session's presentation title, which ticks on every job and directory
        // change; a full layout pass -- tab bar, toolbelt, status bar, division
        // view, tab style -- for each of those is what this avoids.
        _windowNameBesideTabsLabel.frame = [self frameForWindowNameBesideTabsLabel];
        return;
    }
    // The name contributes to the tab bar's left inset, so the tabs have to be
    // laid out again, not just this label.
    [self layoutSubviews];
}

- (void)setWindowTitleLabelToString:(NSString *)title subtitle:(NSString *)subtitle icon:(NSImage *)icon {
    id<PSMPUAFontProvider> puaFontProvider = [self.delegate rootTerminalViewPUAFontProvider];
    _windowTitleLabel.puaFontProvider = puaFontProvider;

    // Short-circuit if nothing that affects the rendered label has changed. The
    // title is polled ~once per second per visible session even while idle, so
    // rebuilding an identical label scales CPU with the number of open windows
    // (issue 12982). The rendered result depends on the content (title/subtitle/
    // icon), the drawing attributes (text color, font, HTML parsing, and the PUA
    // fonts resolved from the terminal font), and the alignment, which is a
    // function of the available width (frame width, toolbelt width, tab bar
    // insets, whether the tab bar control is on loan, and the macOS 26 minimal
    // left-align setting). iTermWindowTitleLabelInputs captures all of these.
    BOOL leftAlignTitleBarMinimalTahoe = NO;
    if (@available(macOS 26, *)) {
        leftAlignTitleBarMinimalTahoe = [iTermAdvancedSettingsModel leftAlignTitleBarMinimalTahoe];
    }
    iTermWindowTitleLabelInputs *inputs =
        [[iTermWindowTitleLabelInputs alloc] initWithTitle:title
                                                  subtitle:subtitle
                                                      icon:icon
                                                 textColor:_windowTitleLabel.textColor
                                                      font:_windowTitleLabel.font
                                                     width:NSWidth(self.frame)
                                             toolbeltWidth:[self shouldShowToolbelt] ? NSWidth(_toolbelt.frame) : 0.0
                                                    insets:[self.delegate tabBarInsets]
                                       tabBarControlOnLoan:_tabBarControlOnLoan
                                                 parseHTML:[iTermPreferences boolForKey:kPreferenceKeyHTMLTabTitles]
                             leftAlignTitleBarMinimalTahoe:leftAlignTitleBarMinimalTahoe
                                   effectiveAppearanceName:self.effectiveAppearance.name
                                           puaFontProvider:puaFontProvider];
    if ([inputs isEqual:_lastRenderedWindowTitleLabelInputs]) {
        return;
    }
    _lastRenderedWindowTitleLabelInputs = inputs;

    [_windowTitleLabel setTitle:title subtitle:subtitle icon:icon alignmentProvider:
     ^NSTextAlignment(NSTextField * _Nonnull scratch) {
         BOOL leftAligned = NO;
         [self frameForWindowTitleLabel:scratch
                            hasSubtitle:subtitle.length > 0
                         getLeftAligned:&leftAligned];

         return leftAligned ? NSTextAlignmentLeft : NSTextAlignmentCenter;
    }];
}

- (void)setWindowTitleIcon:(NSImage *)icon {
    [self setWindowTitleLabelToString:_windowTitle
                             subtitle:[self.delegate rootTerminalViewCurrentTabSubtitle]
                                 icon:icon];
}

- (iTermTabBarControlView *)borrowTabBarControl {
    RLog(@"Borrow tabbar control");
    assert(!_tabBarControlOnLoan);
    iTermTabBarControlView *view = _tabBarControl;
    _tabBarControlOnLoan = YES;
    _tabBarBacking.hidden = YES;
    [_tabBarControl removeFromSuperview];
    // Fix size in case we just went from left-of to top-of since it's now going full-width.
    [self.tabBarControl setTabLocation:[iTermPreferences intForKey:kPreferenceKeyTabPosition]];
    const CGFloat desiredHeight = [self.delegate rootTerminalViewHeightOfTabBar:self];
    _tabBarControl.height = desiredHeight;
    _tabBarControl.frame = NSMakeRect(0, 0, _tabBarControl.frame.size.width, desiredHeight);
    _tabBarControl.hidden = NO;

    return view;
}

- (void)returnTabBarControlView:(iTermTabBarControlView *)tabBarControl {
    RLog(@"Return tabbar control");
    assert(_tabBarControlOnLoan);
    _tabBarControlOnLoan = NO;
    [_tabBarBacking addSubview:tabBarControl];
    _tabBarControl.frame = _tabBarBacking.bounds;
    _tabBarControl = tabBarControl;
    [self.tabBarControl updateFlashing];
    _tabBarBacking.hidden = NO;
    // While the bar was on loan the name was empty: the delegate reported none
    // and the width was forced to 0. The bar can come back before the delegate
    // will report one again -- -windowWillExitFullScreen returns it while the
    // window is still full screen -- so reading it here would read the same
    // nothing and the name would never return. Ask once the caller's layout has
    // settled instead, which covers full screen and any other borrow/return.
    // Deferred for the same reason as issue 12811: callers may be mid-layout.
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateWindowNameBesideTabs];
    });
}

- (void)windowNumberDidChangeTo:(NSNumber *)number {
    _windowNumber = number;
    BOOL deemphasized;
    _windowNumberLabel.stringValue = [iTermWindowShortcutLabelTitlebarAccessoryViewController stringForOrdinal:number.intValue deemphasized:&deemphasized];
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:YES];
    [_statusBarContainer setNeedsDisplay:YES];
    [_tabBarBacking setNeedsDisplay:YES];
    [_tabBarControl setNeedsDisplay:YES];
}

- (void)setToolbeltProportions:(NSDictionary *)proportions {
    _desiredToolbeltProportions = [proportions copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateToolbeltProportionsIfNeeded];
    });
}

- (void)updateToolbeltProportionsIfNeeded {
    if (_desiredToolbeltProportions) {
        [self.toolbelt setProportions:_desiredToolbeltProportions];
        _desiredToolbeltProportions = nil;
    }
}

- (void)setShowsWindowSize:(BOOL)showsWindowSize {
    if (!showsWindowSize) {
        // Hide
        [_windowSizeView removeFromSuperview];
        _windowSizeView = nil;
        return;
    }

    // Show
    if (_windowSizeView) {
        return;
    }
    _windowSizeView = [[iTermWindowSizeView alloc] initWithDetail:[self.delegate rootTerminalViewWindowSizeViewDetailString]];
    [self addSubview:_windowSizeView];
    NSRect myBounds = self.bounds;
    _windowSizeView.frame = NSMakeRect(NSMidX(myBounds), NSMidY(myBounds), 0, 0);
    _windowSizeView.autoresizingMask = (NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin);
    [_windowSizeView setWindowSize:[self.delegate rootTerminalViewCurrentSessionSize]];
}

- (void)windowDidResize {
    [_windowSizeView setWindowSize:[self.delegate rootTerminalViewCurrentSessionSize]];
}

- (void)setCurrentSessionAlpha:(CGFloat)alpha {
    _tabBarBacking.visualEffectView.hidden = PSMShouldExtendTransparencyIntoMinimalTabBar() && (alpha < 1);
}

#pragma mark - Division View

- (void)updateDivisionViewAndWindowNumberLabel {
    BOOL shouldBeVisible = _delegate.divisionViewShouldBeVisible;
    if (shouldBeVisible) {
        NSRect tabViewFrame = _tabView.frame;
        NSRect divisionViewFrame = NSMakeRect(0,
                                              NSMaxY(tabViewFrame),
                                              self.bounds.size.width,
                                              kDivisionViewHeight);
        if ([_delegate rootTerminalViewSharedStatusBarViewController] &&
            [iTermPreferences boolForKey:kPreferenceKeyStatusBarPosition] == iTermStatusBarPositionTop) {
            // Have a top status bar. Move the division view to sit above it.
            divisionViewFrame.origin.y += iTermGetStatusBarHeight();
        }
        if (!_divisionView) {
            Class theClass;
            if (@available(macOS 14.0, *)) {
                // There's a bug in Sonoma (first seen in 14.0 Beta (23A5301h) which I believe is beta 4)
                // where using a non-layer-backed division view caused all the other views to disappear, including those over it.
                // I don't remember why I fell back to a non-layer-backed view for non-metal. Probably bugs in old macOS versions.
                theClass = [iTermLayerBackedSolidColorView class];
            } else {
                theClass = _useMetal ? [iTermLayerBackedSolidColorView class] : [SolidColorView class];
            }
            _divisionView = [[theClass alloc] initWithFrame:divisionViewFrame];
            _divisionView.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
            [self addSubview:_divisionView];
        }
        iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        switch ([self.effectiveAppearance it_tabStyle:preferredStyle]) {
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_COMPACT:
            case TAB_STYLE_MINIMAL:
                assert(NO);
                
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                _divisionView.color = (self.window.isKeyWindow
                                       ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.70 alpha:1]
                                       : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.86 alpha:1]);
                break;

            case TAB_STYLE_DARK:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
                _divisionView.color = (self.window.isKeyWindow
                                       ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.1 alpha:1]
                                       : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.07 alpha:1]);
                break;
        }

        _divisionView.frame = divisionViewFrame;
    } else if (_divisionView) {
        // Remove existing division
        [_divisionView removeFromSuperview];
        _divisionView = nil;
    }
    [self updateTextColors];
    if (_windowTitleLabel.windowIcon) {
        [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle
                                 subtitle:_windowTitleLabel.subtitle
                                     icon:_windowTitleLabel.windowIcon];
    }
}

- (void)updateTextColors {
    _windowNumberLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForWindowNumber];
    // Shares the window number's treatment because it shares its strip: the
    // window name is context for the tabs, not a peer of the tab titles.
    [self applyWindowNameBesideTabsAttributes];
    _windowTitleLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForTitle];
}

#pragma mark - Toolbelt

- (void)updateToolbeltForWindow:(NSWindow *)thisWindow {
    _toolbelt.frame = [self toolbeltFrameInWindow:thisWindow];
    _toolbelt.hidden = ![self shouldShowToolbelt];
    [_delegate repositionWidgets];
    [_toolbelt relayoutAllTools];
}

- (void)constrainToolbeltWidth {
    _toolbeltWidth = [self maximumToolbeltWidthForViewWidth:self.frame.size.width];
}

- (CGFloat)maximumToolbeltWidthForViewWidth:(CGFloat)viewWidth {
    CGFloat minSize = MIN(kMinimumToolbeltSizeInPoints,
                          viewWidth * kMinimumToolbeltSizeAsFractionOfWindow);
    return MAX(MIN(_toolbeltWidth,
                   viewWidth * kMaximumToolbeltSizeAsFractionOfWindow),
               minSize);
}

- (NSRect)toolbeltFrameInWindow:(NSWindow *)thisWindow {
    // Use calculator for toolbelt frame calculation
    iTermLayoutInputs inputs = [self layoutInputsForWindow:thisWindow];
    return [iTermLayoutCalculator toolbeltFrameWithInputs:inputs];
}

- (void)setShouldShowToolbelt:(BOOL)shouldShowToolbelt {
    if (shouldShowToolbelt == _shouldShowToolbelt) {
        return;
    }
    if (shouldShowToolbelt && !_haveShownToolbelt) {
        _toolbeltWidth = [iTermPreferences floatForKey:kPreferenceKeyDefaultToolbeltWidth];
        _haveShownToolbelt = YES;
    }
    _shouldShowToolbelt = shouldShowToolbelt;
    _toolbelt.hidden = !shouldShowToolbelt;
}

- (void)updateToolbeltFrameForWindow:(NSWindow *)thisWindow {
    const NSRect toolbeltFrame = [self toolbeltFrameInWindow:thisWindow];
    DLog(@"Set toolbelt frame to %@", NSStringFromRect(toolbeltFrame));
    [self constrainToolbeltWidth];
    [self.toolbelt setFrame:toolbeltFrame];
}

- (void)shutdown {
    [_toolbelt shutdown];
    _toolbelt = nil;
    _delegate = nil;
}

- (BOOL)scrollbarShouldBeVisible {
    return ![iTermPreferences boolForKey:kPreferenceKeyHideScrollbar];
}

- (BOOL)tabBarShouldBeVisible {
    if (_tabBarControlOnLoan) {
        DLog(@"Tab bar should not be visible because it is on loan");
        return NO;
    }
    return [self tabBarShouldBeVisibleEvenWhenOnLoan];
}

- (BOOL)tabBarShouldBeVisibleEvenWhenOnLoan {
    if (self.tabBarControl.flashing) {
        DLog(@"Tabbar should be visible because it is flashing");
        return YES;
    } else {
        return [self tabBarShouldBeVisibleWithAdditionalTabs:0];
    }
}

- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)numberOfAdditionalTabs {
    if (([_delegate anyFullScreen] || [_delegate enteringLionFullscreen]) &&
        ![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
        DLog(@"Tabbar should not be visible because in full screen");
        return NO;
    }
    if ([_delegate tabBarAlwaysVisible]) {
        DLog(@"Tabbar should be visible because it is configured to always be visible");
        return YES;
    }
    const BOOL result = [self.tabView numberOfTabViewItems] + numberOfAdditionalTabs > 1;
    DLog(@"returning %@", @(result));
    return result;
}

- (void)removeVerticalTabBarDragHandle {
    [self.verticalTabBarDragHandle removeFromSuperview];
    self.verticalTabBarDragHandle = nil;
}

- (void)updateWindowNumberFont {
    if ([self tabBarShouldBeVisible]) {
        _windowNumberLabel.font = [NSFont titleBarFontOfSize:[NSFont smallSystemFontSize]];
    } else {
        _windowNumberLabel.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
    }
}

- (void)layoutSubviewsWithVisibleTabBarForWindow:(NSWindow *)thisWindow inlineToolbelt:(BOOL)showToolbeltInline {
    assert(!_tabBarControlOnLoan);
    // The tabBar control is visible.
    DLog(@"repositionWidgets - tabs are visible. Adjusting window size...");
    self.tabBarControl.hidden = NO;
    [self.tabBarControl setTabLocation:[iTermPreferences intForKey:kPreferenceKeyTabPosition]];

    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_TopTab: {
            // Place tabs at the top.
            // Add 1px border
            [self layoutSubviewsTopTabBarVisible:YES forWindow:thisWindow];
            break;
        }

        case PSMTab_BottomTab: {
            [self layoutSubviewsWithVisibleBottomTabBarForWindow:thisWindow];
            break;
        }

        case PSMTab_LeftTab: {
            [self layoutSubviewsWithVisibleLeftTabBarAndInlineToolbelt:showToolbeltInline forWindow:thisWindow];
            break;
        }

        case PSMTab_RightTab: {
            [self layoutSubviewsWithVisibleRightTabBarAndInlineToolbelt:showToolbeltInline forWindow:thisWindow];
            break;
        }
    }
}

- (BOOL)shouldLeaveEmptyAreaAtTop {
    if (!_tabBarControlOnLoan) {
        DLog(@"NO: Tabbar control not on loan");
        return NO;
    }
    if (![self tabBarShouldBeVisibleWithAdditionalTabs:0]) {
        DLog(@"NO: tabbar should not be visible");
        return NO;
    }
    if (![self.delegate rootTerminalViewShouldLeaveEmptyAreaAtTop]) {
        DLog(@"NO: delegate says not to leave an empty area on top");
        return NO;
    }
    DLog(@"YES");
    return YES;
}

- (CGFloat)notchInset {
    if (![_delegate fullScreen]) {
        return 0;
    }
    const BOOL wantToHideMenuBar = [iTermPreferences boolForKey:kPreferenceKeyHideMenuBarInFullscreen];
    if (!wantToHideMenuBar) {
        // No need to use a notch mask because the menu bar serves that purpose.
        return 0;
    }
    const CGFloat fakeHeight = [iTermAdvancedSettingsModel fakeNotchHeight];
    if (fakeHeight > 0) {
        return fakeHeight;
    }
    // self.safeAreaInsets is all 0s on a notch Mac. Why the hell doesn't anything work right?
    const NSEdgeInsets safeAreaInsets = self.window.screen.safeAreaInsets;
    return safeAreaInsets.top;
}

#pragma mark - Layout Calculator Integration

- (iTermLayoutInputs)layoutInputsForWindow:(NSWindow *)thisWindow {
    iTermLayoutInputs inputs = {0};

    // Content view dimensions - fall back to self.bounds if window is nil
    // (e.g., during initialization before window is set)
    NSRect contentFrame;
    if (thisWindow) {
        contentFrame = [[thisWindow contentView] frame];
    } else {
        contentFrame = self.bounds;
    }
    inputs.contentViewWidth = contentFrame.size.width;
    inputs.contentViewHeight = contentFrame.size.height;

    // Tab bar dimensions
    inputs.tabBarHeight = _tabBarControl.height;
    inputs.leftTabBarWidth = _leftTabBarWidth;

    // Toolbelt
    inputs.toolbeltWidth = floor(self.toolbeltWidth);
    inputs.shouldShowToolbelt = self.shouldShowToolbelt;

    // Status bar
    iTermStatusBarViewController *statusBarViewController = [_delegate rootTerminalViewSharedStatusBarViewController];
    inputs.statusBarHeight = statusBarViewController ? iTermGetStatusBarHeight() : 0;
    inputs.hasStatusBar = (statusBarViewController != nil);
    inputs.statusBarOnTop = ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition] == iTermStatusBarPositionTop);

    // Tab bar state
    inputs.tabBarVisible = [self tabBarShouldBeVisibleWithAdditionalTabs:0];
    inputs.tabBarOnLoan = _tabBarControlOnLoan;
    inputs.tabBarFlashing = _tabBarControl.flashing;
    inputs.tabBarShouldBeAccessory = [self tabBarShouldBeVisibleEvenWhenOnLoan];
    inputs.tabBarAccessoryOverlapsContent = [self.delegate rootTerminalViewFullScreenTabBarAccessoryOverlapsContent];

    // Fullscreen state
    inputs.enteringFullscreen = [self.delegate enteringLionFullscreen];
    inputs.inFullscreen = [self.delegate fullScreen] || [self.delegate lionFullScreen];

    // Tab position
    inputs.tabPosition = [iTermPreferences intForKey:kPreferenceKeyTabPosition];

    // Division view
    inputs.divisionViewVisible = self.delegate.divisionViewShouldBeVisible;
    inputs.divisionViewHeight = kDivisionViewHeight;

    // Notch inset
    inputs.notchInset = [self notchInset];

    // Transitional state
    inputs.shouldLeaveEmptyAreaAtTop = [self shouldLeaveEmptyAreaAtTop];

    // Title in tab bar
    inputs.drawWindowTitleInPlaceOfTabBar = [self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar];

    return inputs;
}

- (void)layoutSubviewsWithHiddenTabBarForWindow:(NSWindow *)thisWindow {
    if (!_tabBarControlOnLoan) {
        self.tabBarControl.hidden = YES;
    }
    if ([self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        [self layoutSubviewsTopTabBarVisible:NO forWindow:thisWindow];
        return;
    }

    [self removeVerticalTabBarDragHandle];

    // Build inputs and calculate layout using the calculator
    iTermLayoutInputs inputs = [self layoutInputsForWindow:thisWindow];
    inputs.tabBarVisible = NO;  // Force hidden for this method
    iTermLayoutOutputs outputs = [iTermLayoutCalculator calculateLayoutWithInputs:inputs];

    // Apply tab view frame
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(outputs.tabViewFrame));
    [self.tabView setFrame:outputs.tabViewFrame];

    // Layout status bar using calculator outputs
    [self layoutStatusBarWithOutputs:outputs window:thisWindow];

    [self updateDivisionViewAndWindowNumberLabel];

    // Even though it's not visible it needs an accurate number so we can compute the proper
    // window size when it appears.
    [self setLeftTabBarWidthFromPreferredWidth];

    if ([_delegate iTermTabBarWindowIsFullScreen]) {
        // When in full screen the insets must be reset even though the tab bar is not visible.
        self.tabBarControl.insets = [self.delegate tabBarInsets];
    }
}

- (void)layoutSubviewsTopTabBarVisible:(BOOL)topTabBarVisible forWindow:(NSWindow *)thisWindow {
    [self removeVerticalTabBarDragHandle];

    // Build inputs and calculate layout using the calculator
    iTermLayoutInputs inputs = [self layoutInputsForWindow:thisWindow];
    inputs.tabBarVisible = topTabBarVisible;
    inputs.tabPosition = kLayoutTabPositionTop;
    iTermLayoutOutputs outputs = [iTermLayoutCalculator calculateLayoutWithInputs:inputs];

    // Apply tab view frame
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(outputs.tabViewFrame));
    [self.tabView setFrame:outputs.tabViewFrame];

    // Layout status bar using calculator outputs
    [self layoutStatusBarWithOutputs:outputs window:thisWindow];

    [self updateDivisionViewAndWindowNumberLabel];

    if (!_tabBarControlOnLoan) {
        self.tabBarControl.insets = [self.delegate tabBarInsets];
        [self setTabBarFrame:outputs.tabBarFrame];
        [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    }
}

- (void)setTabBarFrame:(NSRect)frame {
    assert(!_tabBarControlOnLoan);
    _tabBarBacking.frame = frame;
    self.tabBarControl.frame = _tabBarBacking.bounds;
}

- (void)layoutSubviewsWithVisibleBottomTabBarForWindow:(NSWindow *)thisWindow {
    assert(!_tabBarControlOnLoan);
    DLog(@"repositionWidgets - putting tabs at bottom");
    [self removeVerticalTabBarDragHandle];

    // Build inputs and calculate layout using the calculator
    iTermLayoutInputs inputs = [self layoutInputsForWindow:thisWindow];
    inputs.tabBarVisible = YES;
    inputs.tabPosition = kLayoutTabPositionBottom;
    iTermLayoutOutputs outputs = [iTermLayoutCalculator calculateLayoutWithInputs:inputs];

    // Apply tab bar frame and settings
    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:outputs.tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];

    // Apply tab view frame
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(outputs.tabViewFrame));
    self.tabView.frame = outputs.tabViewFrame;

    // Layout status bar using calculator outputs
    [self layoutStatusBarWithOutputs:outputs window:thisWindow];

    [self updateDivisionViewAndWindowNumberLabel];
}

- (void)setTabBarControlAutoresizingMask:(NSAutoresizingMaskOptions)mask {
    if (_tabBarBacking) {
        _tabBarBacking.autoresizingMask = mask;
        _tabBarControl.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        return;
    }

    _tabBarControl.autoresizingMask = mask;
}

- (void)layoutSubviewsWithVisibleLeftTabBarAndInlineToolbelt:(BOOL)showToolbeltInline forWindow:(NSWindow *)thisWindow {
    assert(!_tabBarControlOnLoan);
    [self setLeftTabBarWidthFromPreferredWidth];

    // Build inputs and calculate layout using the calculator
    iTermLayoutInputs inputs = [self layoutInputsForWindow:thisWindow];
    inputs.tabBarVisible = YES;
    inputs.tabPosition = kLayoutTabPositionLeft;
    iTermLayoutOutputs outputs = [iTermLayoutCalculator calculateLayoutWithInputs:inputs];

    // Apply tab bar frame and settings
    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:outputs.tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMaxXMargin)];

    // Apply tab view frame
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(outputs.tabViewFrame));
    self.tabView.frame = outputs.tabViewFrame;

    // Layout status bar using calculator outputs
    [self layoutStatusBarWithOutputs:outputs window:thisWindow];

    [self updateDivisionViewAndWindowNumberLabel];

    // Handle left tab bar drag handle
    [self updateLeftTabBarDragHandleForTabBarFrame:outputs.tabBarFrame];
}

- (void)layoutSubviewsWithVisibleRightTabBarAndInlineToolbelt:(BOOL)showToolbeltInline forWindow:(NSWindow *)thisWindow {
    assert(!_tabBarControlOnLoan);
    [self setLeftTabBarWidthFromPreferredWidth];

    iTermLayoutInputs inputs = [self layoutInputsForWindow:thisWindow];
    inputs.tabBarVisible = YES;
    inputs.tabPosition = kLayoutTabPositionRight;
    iTermLayoutOutputs outputs = [iTermLayoutCalculator calculateLayoutWithInputs:inputs];

    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:outputs.tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMinXMargin)];

    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(outputs.tabViewFrame));
    self.tabView.frame = outputs.tabViewFrame;

    [self layoutStatusBarWithOutputs:outputs window:thisWindow];

    [self updateDivisionViewAndWindowNumberLabel];

    [self updateRightTabBarDragHandleForTabBarFrame:outputs.tabBarFrame];
}

- (void)updateLeftTabBarDragHandleForTabBarFrame:(CGRect)tabBarFrame {
    if (CGRectIsEmpty(tabBarFrame)) {
        [self removeVerticalTabBarDragHandle];
        return;
    }

    const CGFloat dragHandleWidth = 3;
    NSRect leftTabBarDragHandleFrame = NSMakeRect(NSMaxX(tabBarFrame) - dragHandleWidth,
                                                  0,
                                                  dragHandleWidth,
                                                  NSHeight(tabBarFrame));
    if (!self.verticalTabBarDragHandle) {
        self.verticalTabBarDragHandle = [[iTermDragHandleView alloc] initWithFrame:leftTabBarDragHandleFrame];
        self.verticalTabBarDragHandle.delegate = self;
        [self addSubview:self.verticalTabBarDragHandle];
    } else {
        self.verticalTabBarDragHandle.frame = leftTabBarDragHandleFrame;
    }
}

- (void)updateRightTabBarDragHandleForTabBarFrame:(CGRect)tabBarFrame {
    if (CGRectIsEmpty(tabBarFrame)) {
        [self removeVerticalTabBarDragHandle];
        return;
    }

    const CGFloat dragHandleWidth = 3;
    NSRect rightTabBarDragHandleFrame = NSMakeRect(NSMinX(tabBarFrame),
                                                   0,
                                                   dragHandleWidth,
                                                   NSHeight(tabBarFrame));
    if (!self.verticalTabBarDragHandle) {
        self.verticalTabBarDragHandle = [[iTermDragHandleView alloc] initWithFrame:rightTabBarDragHandleFrame];
        self.verticalTabBarDragHandle.delegate = self;
        [self addSubview:self.verticalTabBarDragHandle];
    } else {
        self.verticalTabBarDragHandle.frame = rightTabBarDragHandleFrame;
    }
}

- (void)layoutWindowPaneDecorations {
    // Must precede the tab bar insets, which reserve room for whatever this
    // leaves in the label.
    [self updateWindowNameBesideTabsText];
    [self updateTextColors];
    if (_windowTitleLabel.windowIcon) {
        [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle
                                 subtitle:_windowTitleLabel.subtitle
                                     icon:_windowTitleLabel.windowIcon];
    }

    [self updateWindowNumberFont];

    if ([self.delegate enableStoplightHotbox]) {
        _stoplightHotbox.hidden = NO;
        _stoplightHotbox.alphaValue = 0;
        _standardWindowButtonsView.alphaValue = 0;
        [_stoplightHotbox setFrameOrigin:NSMakePoint(0, self.frame.size.height - _stoplightHotbox.frame.size.height)];
        if (_windowNumberLabel.superview != _stoplightHotbox) {
            [_stoplightHotbox addSubview:_windowNumberLabel];
        }
    } else {
        _stoplightHotbox.hidden = YES;
        _standardWindowButtonsView.alphaValue = 1;
        if (_windowNumberLabel.superview != self) {
            [self addSubview:_windowNumberLabel];
        }
        [_windowNumberLabel sizeToFit];
        _windowNumberLabel.frame = [self frameForWindowNumberLabel];
    }
    const BOOL hideWindowTitleLabel = ![self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar];
    if (!hideWindowTitleLabel) {
        if (_windowTitleLabel.superview != self) {
            [self addSubview:_windowTitleLabel];
        }
        _windowTitleLabel.frame = [self frameForWindowTitleLabel];
    }
    _windowTitleLabel.hidden = hideWindowTitleLabel;
    self.window.movableByWindowBackground = !hideWindowTitleLabel;
    _windowNumberLabel.hidden = ![self.delegate rootTerminalViewWindowNumberLabelShouldBeVisible];

    // The delegate returns nil unless the tab bar is visible, so this and the
    // title taking the tab bar's place are mutually exclusive.
    const BOOL hideWindowNameBesideTabs = ([self windowNameBesideTabsTextWidth] == 0);
    if (!hideWindowNameBesideTabs) {
        if (_windowNameBesideTabsLabel.superview != self) {
            [self addSubview:_windowNameBesideTabsLabel];
        }
        _windowNameBesideTabsLabel.frame = [self frameForWindowNameBesideTabsLabel];
    }
    _windowNameBesideTabsLabel.hidden = hideWindowNameBesideTabs;

    _standardWindowButtonsView.frame = [self frameForStandardWindowButtons];
    if (_standardWindowButtonsView && !_compactProxyIconView && [self shouldShowCompactProxyIcon]) {
        [self createCompactProxyIconButtonIfNeeded];
        [self updateProxyIcon];
    }
    [self updateCompactProxyIconFrame];
    // The proxy icon lives next to the stoplight buttons and must appear and
    // disappear in lockstep with them (e.g., when the stoplight hotbox hides
    // the buttons in the minimal theme). Messaging a nil proxy icon is a no-op.
    _compactProxyIconView.alphaValue = _standardWindowButtonsView.alphaValue;
    [self updateTitleAndBorderViews];
}

- (void)layoutSubviews {
    DLog(@"Before:\n%@", [self iterm_recursiveDescription]);
    [self.delegate rootTerminalViewWillLayoutSubviews];
    // Everything the window name's width depends on -- our frame, the toolbelt,
    // the tab bar's settings -- may have moved since the last pass.
    [self invalidateWindowNameBesideTabsTextWidth];

    const BOOL showToolbeltInline = self.shouldShowToolbelt;
    NSWindow *thisWindow = _delegate.window;
    if (!_tabBarControlOnLoan) {
        [self.tabBarControl updateHeightWithDefault:[_delegate rootTerminalViewHeightOfTabBar:self]];
    }

    // Update the tab style. This must precede everything below that asks the tab
    // bar what fits: -layoutWindowPaneDecorations and the tab bar inset both
    // derive the space reserved for the window name from these values, so
    // pushing them afterwards would size the reservation against the previous
    // pass's settings and leave it a pass behind on every preference change.
    // Each setter assigns its ivar synchronously and only schedules the relayout,
    // so moving them earlier changes what the reservation reads, not when the
    // tab bar lays out.
    [self.tabBarControl setDisableTabClose:!iTermAdvancedSettingsModel.tabCloseButtonsAlwaysVisible];
    [self.tabBarControl setCellMinWidth:[self tabBarCellMinWidth]];
    [self.tabBarControl setSizeCellsToFit:[iTermAdvancedSettingsModel useUnevenTabs]];
    [self.tabBarControl setStretchCellsToFit:[iTermPreferences boolForKey:kPreferenceKeyStretchTabsToFillBar]];
    [self.tabBarControl setCellOptimumWidth:[iTermAdvancedSettingsModel optimumTabWidth]];
    [self.tabBarControl setScrollableTabWidth:[iTermAdvancedSettingsModel scrollableTabWidth]];
    [self.tabBarControl setPinnedTabWidth:[iTermAdvancedSettingsModel pinnedTabWidth]];
    self.tabBarControl.smartTruncation = [iTermAdvancedSettingsModel tabTitlesUseSmartTruncation];

    _backgroundImage.frame = self.bounds;
    _windowBorderView.frame = self.bounds;
    [self layoutWindowPaneDecorations];

    // The tab view frame (calculated below) is based on the toolbelt's width. If the toolbelt is
    // too big for the current window size, you could end up with a negative-width tab view frame.
    if (_shouldShowToolbelt) {
        [self constrainToolbeltWidth];
    }
    _tabViewFrameReduced = NO;
    if (![self tabBarShouldBeVisible]) {
        [self layoutSubviewsWithHiddenTabBarForWindow:thisWindow];
    } else {
        [self layoutSubviewsWithVisibleTabBarForWindow:thisWindow inlineToolbelt:showToolbeltInline];
    }
    const CGFloat notchHeight = [self notchInset];
    _notchMask.hidden = (notchHeight == 0);
    _notchMask.frame = NSMakeRect(0, NSHeight(self.bounds) - notchHeight, NSWidth(self.bounds), notchHeight);

    if (showToolbeltInline) {
        [self updateToolbeltFrameForWindow:thisWindow];
    }

    DLog(@"repositionWidgets - redraw view");
    // Note: this used to call setNeedsDisplay on each session in the current tab.
    [self setNeedsDisplay:YES];

    DLog(@"repositionWidgets - update tab bar");
    if (!_tabBarControlOnLoan) {
        [self.tabBarControl updateFlashing];
    }
    DLog(@"After:\n%@", [self iterm_recursiveDescription]);
    [self.delegate rootTerminalViewDidLayoutSubviews];
}

- (CGFloat)minimumTabBarWidth {
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_DARK:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return 50;
        case TAB_STYLE_MINIMAL:
        case TAB_STYLE_COMPACT:
            return 114;
    }
    assert(NO);
}

- (CGFloat)leftTabBarWidthForPreferredWidth:(CGFloat)preferredWidth contentWidth:(CGFloat)contentWidth {
    const CGFloat minimumWidth = [self minimumTabBarWidth];
    const CGFloat maximumWidth = MAX(1, contentWidth - [iTermPreferences sideMargins] * 2 - 10);
    return MAX(MIN(maximumWidth, preferredWidth), minimumWidth);
}

- (CGFloat)leftTabBarWidthForPreferredWidth:(CGFloat)preferredWidth {
    return [self leftTabBarWidthForPreferredWidth:preferredWidth contentWidth:self.bounds.size.width];
}

- (void)setLeftTabBarWidthFromPreferredWidth {
    _leftTabBarWidth = [self leftTabBarWidthForPreferredWidth:_leftTabBarPreferredWidth];
}

- (void)willShowTabBar {
    _leftTabBarWidth = [self leftTabBarWidthForPreferredWidth:_leftTabBarPreferredWidth
                                                 contentWidth:self.bounds.size.width];
}

#pragma mark - Status Bar Layout

- (NSRect)frameForStatusBarInContainingFrame:(NSRect)containingFrame {
    switch ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            return NSMakeRect(NSMinX(containingFrame),
                              NSMaxY(containingFrame) - iTermGetStatusBarHeight(),
                              NSWidth(containingFrame),
                              iTermGetStatusBarHeight());

        case iTermStatusBarPositionBottom:
            return NSMakeRect(NSMinX(containingFrame),
                              NSMinY(containingFrame),
                              NSWidth(containingFrame),
                              iTermGetStatusBarHeight());
    }
    return NSZeroRect;
}

- (NSAutoresizingMaskOptions)statusBarContainerAutoresizingMask {
    switch ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            return NSViewWidthSizable | NSViewMinYMargin;

        case iTermStatusBarPositionBottom:
            return NSViewWidthSizable | NSViewMaxYMargin;
    }

    return NSViewWidthSizable | NSViewMinYMargin;
}

- (void)updateDecorationHeightsForStatusBar:(iTermDecorationHeights *)decorationHeights {
    switch ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop: {
            decorationHeights->top += iTermGetStatusBarHeight();
            break;
        }
        case iTermStatusBarPositionBottom:
            decorationHeights->bottom += iTermGetStatusBarHeight();
            break;
    }
}

- (void)layoutIfStatusBarChanged {
    iTermStatusBarViewController *statusBarViewController = [_delegate rootTerminalViewSharedStatusBarViewController];
    if (statusBarViewController != _statusBarViewController ||
        _statusBarViewController.view != statusBarViewController.view ||
        statusBarViewController.view.superview != _statusBarContainer) {
        [self layoutSubviews];
    }
}

- (void)layoutStatusBar:(iTermDecorationHeights *)decorationHeights
                 window:(NSWindow *)thisWindow
                  frame:(NSRect)containingFrame {
    iTermStatusBarViewController *statusBarViewController = [_delegate rootTerminalViewSharedStatusBarViewController];
    NSRect statusBarFrame = [self frameForStatusBarInContainingFrame:containingFrame];
    if (statusBarViewController) {
        [self updateDecorationHeightsForStatusBar:decorationHeights];
    }
    if (_statusBarViewController.view != statusBarViewController.view ||
        _statusBarViewController.view.superview != _statusBarContainer) {
        if (!_statusBarContainer) {
            _statusBarContainer = [[iTermGenericStatusBarContainer alloc] initWithFrame:statusBarFrame];
            _statusBarContainer.autoresizesSubviews = YES;
            _statusBarContainer.delegate = self;
            NSInteger index = [self.subviews indexOfObject:_stoplightHotbox];
            if (index == NSNotFound) {
                [self addSubview:_statusBarContainer];
            } else {
                [self insertSubview:_statusBarContainer atIndex:index];
            }
        }
        if (_statusBarViewController.view.superview == _statusBarContainer) {
            [_statusBarViewController.view removeFromSuperview];
        }
        if (statusBarViewController.view.superview != _statusBarContainer) {
            [_statusBarContainer addSubview:statusBarViewController.view];
            statusBarViewController.view.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            statusBarViewController.view.frame = _statusBarContainer.bounds;
        }
    }
    _statusBarContainer.autoresizingMask = [self statusBarContainerAutoresizingMask];
    _statusBarContainer.hidden = (statusBarViewController == nil);
    _statusBarViewController = statusBarViewController;
    _statusBarContainer.frame = statusBarFrame;
}

/// Layout status bar using pre-calculated outputs from iTermLayoutCalculator.
/// This is the new path that uses the calculator outputs directly.
- (void)layoutStatusBarWithOutputs:(iTermLayoutOutputs)outputs
                            window:(NSWindow *)thisWindow {
    iTermStatusBarViewController *statusBarViewController = [_delegate rootTerminalViewSharedStatusBarViewController];
    NSRect statusBarFrame = outputs.statusBarFrame;

    if (_statusBarViewController.view != statusBarViewController.view ||
        _statusBarViewController.view.superview != _statusBarContainer) {
        if (!_statusBarContainer) {
            _statusBarContainer = [[iTermGenericStatusBarContainer alloc] initWithFrame:statusBarFrame];
            _statusBarContainer.autoresizesSubviews = YES;
            _statusBarContainer.delegate = self;
            NSInteger index = [self.subviews indexOfObject:_stoplightHotbox];
            if (index == NSNotFound) {
                [self addSubview:_statusBarContainer];
            } else {
                [self insertSubview:_statusBarContainer atIndex:index];
            }
        }
        if (_statusBarViewController.view.superview == _statusBarContainer) {
            [_statusBarViewController.view removeFromSuperview];
        }
        if (statusBarViewController.view.superview != _statusBarContainer) {
            [_statusBarContainer addSubview:statusBarViewController.view];
            statusBarViewController.view.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            statusBarViewController.view.frame = _statusBarContainer.bounds;
        }
    }
    _statusBarContainer.autoresizingMask = [self statusBarContainerAutoresizingMask];
    _statusBarContainer.hidden = (statusBarViewController == nil);
    _statusBarViewController = statusBarViewController;
    _statusBarContainer.frame = statusBarFrame;
}

#pragma mark - iTermTabBarControlViewDelegate

- (BOOL)iTermTabBarShouldFlashAutomatically {
    if (_tabBarControlOnLoan) {
        return NO;
    }
    return [_delegate iTermTabBarShouldFlashAutomatically];
}

- (void)iTermTabBarWillBeginFlash {
    [_delegate iTermTabBarWillBeginFlash];
}

- (void)iTermTabBarDidFinishFlash {
    [_delegate iTermTabBarDidFinishFlash];
}

- (BOOL)iTermTabBarWindowIsFullScreen {
    return [_delegate iTermTabBarWindowIsFullScreen];
}

- (BOOL)iTermTabBarCanDragWindow {
    return [_delegate iTermTabBarCanDragWindow];
}

- (void)iTermTabBarDidUpdateProgressBars {
    if ([_delegate respondsToSelector:@selector(iTermTabBarDidUpdateProgressBars)]) {
        [_delegate iTermTabBarDidUpdateProgressBars];
    }
}

- (BOOL)iTermTabBarShouldHideBacking {
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle != TAB_STYLE_MINIMAL) {
        return YES;
    }
    BOOL isTop = NO;
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_BottomTab:
        case PSMTab_LeftTab:
        case PSMTab_RightTab:
            return YES;

        case PSMTab_TopTab:
            isTop = YES;
            break;
    }
    if ([_delegate lionFullScreen] || [_delegate enteringLionFullscreen]) {
        if (isTop) {
            if ([iTermPreferences boolForKey:kPreferenceKeyFlashTabBarInFullscreen]) {
                return YES;
            }
            if (![self tabBarShouldBeVisible] && !_tabBarControlOnLoan) {
                // Code path taken big Big Sur workaround for issue #9199
                return YES;
            }
        } else {
            return NO;
        }
    }

    return YES;
}

#pragma mark - iTermDragHandleViewDelegate

// For the left-side or right-side tab bar.
- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    CGFloat originalValue = _leftTabBarPreferredWidth;
    const BOOL isRight = ([iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_RightTab);
    const CGFloat signedDelta = isRight ? -delta : delta;
    _leftTabBarPreferredWidth = round([self leftTabBarWidthForPreferredWidth:_leftTabBarPreferredWidth + signedDelta]);
    [self layoutSubviews];  // This may modify _leftTabBarWidth if it's too big or too small.
    [[iTermUserDefaults userDefaults] setDouble:_leftTabBarPreferredWidth
                                              forKey:kPreferenceKeyLeftTabBarWidth];
    // Return the handle's actual movement in window coordinates. For the
    // right-side tab bar the handle is on the bar's left edge, so it moves
    // opposite to the width change.
    const CGFloat widthChange = _leftTabBarPreferredWidth - originalValue;
    return isRight ? -widthChange : widthChange;
}

- (void)dragHandleViewDidFinishMoving:(iTermDragHandleView *)dragHandle {
    [_delegate rootTerminalViewDidResizeContentArea];
}

#pragma mark - iTermStoplightHotboxDelegate

- (void)stoplightHotboxMouseExit {
    [NSView animateWithDuration:0.25
                     animations:^{
                         self->_stoplightHotbox.animator.alphaValue = 0;
                         self->_standardWindowButtonsView.animator.alphaValue = 0;
                         self->_compactProxyIconView.animator.alphaValue = 0;
                     }
                     completion:^(BOOL finished) {
                         if (!finished) {
                             return;
                         }
                     }];
}

- (BOOL)shouldRevealHotbox {
    if ([[iTermApplication sharedApplication] it_modifierFlags] & NSEventModifierFlagCommand) {
        return NO;
    }
    if (!self.window.isKeyWindow) {
        return YES;
    }
    if (!NSApp.isActive) {
        return YES;
    }
    NSView *firstResponder = [NSView castFrom:self.window.firstResponder];
    if (!firstResponder) {
        return YES;
    }
    const NSRect firstResponderFrame = [firstResponder convertRect:firstResponder.bounds toView:nil];
    const NSRect hotboxFrame = [_stoplightHotbox convertRect:_stoplightHotbox.bounds toView:nil];
    if (!NSIntersectsRect(firstResponderFrame, hotboxFrame)) {
        return YES;
    }
    if (![firstResponder respondsToSelector:@selector(delegate)]) {
        return YES;
    }
    id delegate = [(id)firstResponder delegate];
    if (![delegate conformsToProtocol:@protocol(iTermHotboxSuppressing)]) {
        return YES;
    }
    id<iTermHotboxSuppressing> suppressing = delegate;
    return ![suppressing supressesHotbox];
}

- (BOOL)stoplightHotboxMouseEnter {
    if (![self shouldRevealHotbox]) {
        return NO;
    }

    [_stoplightHotbox setNeedsDisplay:YES];
    _stoplightHotbox.alphaValue = 0;
    _standardWindowButtonsView.alphaValue = 0;
    _compactProxyIconView.alphaValue = 0;
    [NSView animateWithDuration:0.25
                     animations:^{
                         self->_stoplightHotbox.animator.alphaValue = 1;
                         self->_standardWindowButtonsView.animator.alphaValue = 1;
                         self->_compactProxyIconView.animator.alphaValue = 1;
                     }
                     completion:nil];
    return YES;
}

- (NSColor *)stoplightHotboxColor {
    return [NSColor windowBackgroundColor];
}

- (NSColor *)stoplightHotboxOutlineColor {
    return [NSColor grayColor];
}

- (BOOL)stoplightHotboxCanDrag {
    return ([self.delegate iTermTabBarCanDragWindow] &&
            ![self.delegate iTermTabBarWindowIsFullScreen]);
}

#pragma mark - iTermGenericStatusBarContainer

- (NSColor *)genericStatusBarContainerBackgroundColor {
    return [self.delegate rootTerminalViewTabBarBackgroundColorIgnoringTabColor:YES];
}

@end

BOOL PSMShouldExtendTransparencyIntoMinimalTabBar(void) {
    switch ([iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
            return YES;

        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return NO;
    }
    return NO;
}
