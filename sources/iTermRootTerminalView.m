//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"

#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "PTYTabView.h"
#import "PTYWindow.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDragHandleView.h"
#import "iTermPreferences.h"
#import "iTermStandardWindowButtonsView.h"
#import "iTermStoplightHotbox.h"
#import "iTermTabBarControlView.h"
#import "iTermToolbeltView.h"
#import "NSAppearance+iTerm.h"
#import "PTYTabView.h"

const CGFloat iTermStandardButtonsViewHeight = 25;
const CGFloat iTermStandardButtonsViewWidth = 69;
const CGFloat iTermStoplightHotboxWidth = iTermStandardButtonsViewWidth + 12;
const CGFloat iTermStoplightHotboxHeight = iTermStandardButtonsViewHeight + 8;
const CGFloat kDivisionViewHeight = 1;

static const CGFloat kMinimumToolbeltSizeInPoints = 100;
static const CGFloat kMinimumToolbeltSizeAsFractionOfWindow = 0.05;
static const CGFloat kMaximumToolbeltSizeAsFractionOfWindow = 0.5;

@interface iTermRootTerminalView()<
    iTermTabBarControlViewDelegate,
    iTermDragHandleViewDelegate,
    iTermStoplightHotboxDelegate>

@property(nonatomic, retain) PTYTabView *tabView;
@property(nonatomic, retain) iTermTabBarControlView *tabBarControl;
@property(nonatomic, retain) SolidColorView *divisionView;
@property(nonatomic, retain) iTermToolbeltView *toolbelt;
@property(nonatomic, retain) iTermDragHandleView *leftTabBarDragHandle;

@end

@implementation iTermRootTerminalView {
    BOOL _tabViewFrameReduced;
    BOOL _haveShownToolbelt;
    iTermStoplightHotbox *_stoplightHotbox;
    iTermStandardWindowButtonsView *_standardWindowButtonsView;
    NSMutableDictionary<NSNumber *, NSButton *> *_standardButtons;
}

- (instancetype)initWithFrame:(NSRect)frameRect
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate,PSMTabBarControlDelegate>)tabBarDelegate
                     delegate:(id<iTermRootTerminalViewDelegate, iTermToolbeltViewDelegate>)delegate {
    self = [super initWithFrame:frameRect color:color];
    if (self) {
        _delegate = delegate;

        self.autoresizesSubviews = YES;
        _leftTabBarPreferredWidth = [iTermPreferences doubleForKey:kPreferenceKeyLeftTabBarWidth];
        [self setLeftTabBarWidthFromPreferredWidth];

        // Create the tab view.
        self.tabView = [[[PTYTabView alloc] initWithFrame:self.bounds] autorelease];
        if (@available(macOS 10.14, *)) {
            self.tabView.drawsBackground = NO;
        } else {
            self.tabView.drawsBackground = !_useMetal;
        }
        _tabView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        _tabView.autoresizesSubviews = YES;
        _tabView.allowsTruncatedLabels = NO;
        _tabView.controlSize = NSControlSizeSmall;
        _tabView.tabViewType = NSNoTabsNoBorder;
        [self addSubview:_tabView];

        // Create the tab bar.
        NSRect tabBarFrame = self.bounds;
        tabBarFrame.size.height = _tabBarControl.height;
        self.tabBarControl = [[[iTermTabBarControlView alloc] initWithFrame:tabBarFrame] autorelease];
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
        
        int theModifier =
            [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]];
        [_tabBarControl setModifier:theModifier];
        _tabBarControl.insets = [self.delegate tabBarInsets];
        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_BottomTab:
                _tabBarControl.orientation = PSMTabBarHorizontalOrientation;
                [_tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
                break;

            case PSMTab_TopTab:
                _tabBarControl.orientation = PSMTabBarHorizontalOrientation;
                [_tabBarControl setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
                break;

            case PSMTab_LeftTab:
                _tabBarControl.orientation = PSMTabBarVerticalOrientation;
                _tabBarControl.autoresizingMask = (NSViewHeightSizable | NSViewMaxXMargin);
                break;
        }
        [self addSubview:_tabBarControl];
        _tabBarControl.tabView = _tabView;
        [_tabView setDelegate:_tabBarControl];
        _tabBarControl.delegate = tabBarDelegate;
        _tabBarControl.hideForSingleTab = NO;

        // Create the toolbelt with its current default size.
        _toolbeltWidth = [iTermPreferences floatForKey:kPreferenceKeyDefaultToolbeltWidth];
        [self constrainToolbeltWidth];

        self.toolbelt = [[[iTermToolbeltView alloc] initWithFrame:self.toolbeltFrame
                                                         delegate:(id)_delegate] autorelease];
        _toolbelt.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
        [self addSubview:_toolbelt];
        [self updateToolbelt];
    }
    return self;
}

- (void)dealloc {
    [_tabView release];

    _tabBarControl.itermTabBarDelegate = nil;
    _tabBarControl.delegate = nil;
    [_tabBarControl release];

    [_divisionView release];
    [_toolbelt release];
    _leftTabBarDragHandle.delegate = nil;
    [_leftTabBarDragHandle release];
    [_stoplightHotbox release];
    [_standardButtons release];
    [_standardWindowButtonsView release];

    [super dealloc];
}

- (CGFloat)leftInsetForWindowButtons {
    return 6;
}

- (CGFloat)strideForWindowButtons {
    return 20;
}

- (NSEdgeInsets)insetsForStoplightHotbox {
    if (![self.delegate enableStoplightHotbox]) {
        NSEdgeInsets insets = NSEdgeInsetsZero;
        insets.bottom = -[self.delegate rootTerminalViewStoplightButtonsOffset:self];
        return insets;
    }

    const CGFloat hotboxSideInset = (iTermStoplightHotboxWidth - iTermStandardButtonsViewWidth) / 2.0;
    const CGFloat hotboxVerticalInset = (iTermStoplightHotboxHeight - iTermStandardButtonsViewHeight) / 2.0;
    return NSEdgeInsetsMake(hotboxVerticalInset, hotboxSideInset, hotboxVerticalInset, hotboxSideInset);
}

- (NSRect)frameForStandardWindowButtons {
    CGFloat x = self.leftInsetForWindowButtons;
    const CGFloat stride = self.strideForWindowButtons;
    const NSEdgeInsets insets = [self insetsForStoplightHotbox];
    CGFloat height;
    if ([self.delegate enableStoplightHotbox]) {
        height = iTermStoplightHotboxHeight;
    } else {
        height = iTermStandardButtonsViewHeight;
    }
    NSRect frame = NSMakeRect(insets.left,
                              self.frame.size.height - height + insets.bottom + 1,
                              x + stride * self.numberOfWindowButtons,
                              iTermStandardButtonsViewHeight);
    return frame;
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
}

- (void)didChangeCompactness {
    id<PTYWindow> ptyWindow = self.window.ptyWindow;
    const BOOL needCustomButtons = (ptyWindow.isCompact &&
                                    !self.delegate.anyFullScreen &&
                                    !self.delegate.enteringLionFullscreen);
    if (!needCustomButtons) {
        [_standardWindowButtonsView removeFromSuperview];
        _standardWindowButtonsView = nil;
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
        x += stride;
        dispatch_async(dispatch_get_main_queue(), ^{
            [button setNeedsDisplay];
        });
    }
    [self layoutSubviews];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        NSBezierPath *path = [NSBezierPath bezierPath];
        static CGFloat inset = 0.5;
        const CGFloat left = inset;
        const CGFloat bottom = inset;
        const CGFloat top = self.frame.size.height - inset;
        const CGFloat right = self.frame.size.width - inset;

        const BOOL haveLeft = self.delegate.haveLeftBorder;
        const BOOL haveTop = self.delegate.haveTopBorder;
        const BOOL haveRight = self.delegate.haveRightBorder;
        const BOOL haveBottom = self.delegate.haveBottomBorder;

        if (haveLeft) {
            [path moveToPoint:NSMakePoint(left, bottom)];
            [path lineToPoint:NSMakePoint(left, top)];
        }
        if (haveTop) {
            [path moveToPoint:NSMakePoint(left, top)];
            [path lineToPoint:NSMakePoint(right, top)];
        }
        if (haveRight) {
            [path moveToPoint:NSMakePoint(right, top)];
            [path lineToPoint:NSMakePoint(right, bottom)];
        }
        if (haveBottom) {
            [path moveToPoint:NSMakePoint(right, bottom)];
            [path lineToPoint:NSMakePoint(left, bottom)];
        }
        [[NSColor colorWithWhite:0.5 alpha:1] set];
        [path stroke];

        return;
    }
    if (_useMetal) {
        return;
    } else {
        [super drawRect:dirtyRect];
    }
}

- (void)setUseMetal:(BOOL)useMetal {
    _useMetal = useMetal;
    if (@available(macOS 10.14, *)) {
        self.tabView.drawsBackground = NO;
    } else {
        self.tabView.drawsBackground = !_useMetal;
    }

    [_divisionView removeFromSuperview];
    [_divisionView release];
    _divisionView = nil;

    [self updateDivisionView];
}

- (void)viewDidChangeEffectiveAppearance {
    [self.delegate rootTerminalViewDidChangeEffectiveAppearance];
}

#pragma mark - Division View

- (void)updateDivisionView {
    BOOL shouldBeVisible = _delegate.divisionViewShouldBeVisible;
    if (shouldBeVisible) {
        NSRect tabViewFrame = _tabView.frame;
        NSRect divisionViewFrame = NSMakeRect(0,
                                              NSMaxY(tabViewFrame),
                                              self.bounds.size.width,
                                              kDivisionViewHeight);
        if (!_divisionView) {
            Class theClass = _useMetal ? [iTermLayerBackedSolidColorView class] : [SolidColorView class];
            _divisionView = [[theClass alloc] initWithFrame:divisionViewFrame];
            _divisionView.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
            [self addSubview:_divisionView];
        }
        iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        switch ([self.effectiveAppearance it_tabStyle:preferredStyle]) {
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_MINIMAL:
                assert(NO);
                
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                _divisionView.color = self.window.isKeyWindow
                        ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.49 alpha:1]
                        : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.65 alpha:1];
                break;

            case TAB_STYLE_DARK:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
                _divisionView.color = self.window.isKeyWindow
                        ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.2 alpha:1]
                        : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.15 alpha:1];
                break;
        }

        _divisionView.frame = divisionViewFrame;
    } else if (_divisionView) {
        // Remove existing division
        [_divisionView removeFromSuperview];
        [_divisionView release];
        _divisionView = nil;
    }
}

#pragma mark - Toolbelt

- (void)updateToolbelt {
    _toolbelt.frame = [self toolbeltFrame];
    _toolbelt.hidden = ![self shouldShowToolbelt];
    [_delegate repositionWidgets];
    [_toolbelt relayoutAllTools];
}

- (void)constrainToolbeltWidth {
    CGFloat minSize = MIN(kMinimumToolbeltSizeInPoints,
                          self.frame.size.width * kMinimumToolbeltSizeAsFractionOfWindow);
    _toolbeltWidth = MAX(MIN(_toolbeltWidth,
                             self.frame.size.width * kMaximumToolbeltSizeAsFractionOfWindow),
                         minSize);
}

- (NSRect)toolbeltFrame {
    CGFloat width = floor(_toolbeltWidth);
    CGFloat top = [_delegate haveTopBorder] ? 1 : 0;
    CGFloat bottom = [_delegate haveBottomBorder] ? 1 : 0;
    CGFloat right = [_delegate haveRightBorder] ? 1 : 0;
    NSRect toolbeltFrame = NSMakeRect(self.bounds.size.width - width - right,
                                      bottom,
                                      width,
                                      self.bounds.size.height - top - bottom);
    return toolbeltFrame;
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
    if (shouldShowToolbelt) {
        [self constrainToolbeltWidth];
    }
}

- (void)updateToolbeltFrame {
    DLog(@"Set toolbelt frame to %@", NSStringFromRect([self toolbeltFrame]));
    [self constrainToolbeltWidth];
    [self.toolbelt setFrame:self.toolbeltFrame];
}

- (void)shutdown {
    [_toolbelt shutdown];
    [_toolbelt release];
    _toolbelt = nil;
    _delegate = nil;
}

- (BOOL)scrollbarShouldBeVisible {
    return ![iTermPreferences boolForKey:kPreferenceKeyHideScrollbar];
}

- (BOOL)tabBarShouldBeVisible {
    if (self.tabBarControl.flashing) {
        return YES;
    } else {
        return [self tabBarShouldBeVisibleWithAdditionalTabs:0];
    }
}

- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)numberOfAdditionalTabs {
    if ([_delegate anyFullScreen] &&
        ![iTermPreferences boolForKey:kPreferenceKeyShowFullscreenTabBar]) {
        return NO;
    }
    if ([_delegate tabBarAlwaysVisible]) {
        return YES;
    }
    return [self.tabView numberOfTabViewItems] + numberOfAdditionalTabs > 1;
}

- (CGFloat)tabviewWidth {
    if ([self tabBarShouldBeVisible] &&
        [iTermPreferences intForKey:kPreferenceKeyTabPosition] == PSMTab_LeftTab)  {
        return _leftTabBarWidth;
    }

    CGFloat width;
    if (self.shouldShowToolbelt && !_delegate.exitingLionFullscreen) {
        width = _delegate.window.frame.size.width - floor(self.toolbeltWidth);
    } else {
        width = _delegate.window.frame.size.width;
    }
    if ([_delegate haveLeftBorder]) {
        --width;
    }
    if ([_delegate haveRightBorder]) {
        --width;
    }
    return width;
}

- (void)removeLeftTabBarDragHandle {
    [self.leftTabBarDragHandle removeFromSuperview];
    self.leftTabBarDragHandle = nil;
}

- (void)layoutSubviews {
    DLog(@"layoutSubviews");

    BOOL showToolbeltInline = self.shouldShowToolbelt;
    NSWindow *thisWindow = _delegate.window;
    self.tabBarControl.height = [_delegate rootTerminalViewHeightOfTabBar:self];

    if ([self.delegate enableStoplightHotbox]) {
        _stoplightHotbox.hidden = NO;
        _stoplightHotbox.alphaValue = 0;
        _standardWindowButtonsView.alphaValue = 0;
        [_stoplightHotbox setFrameOrigin:NSMakePoint(0, self.frame.size.height - _stoplightHotbox.frame.size.height)];
    } else {
        _stoplightHotbox.hidden = YES;
        _standardWindowButtonsView.alphaValue = 1;
    }
    _standardWindowButtonsView.frame = [self frameForStandardWindowButtons];

    // The tab view frame (calculated below) is based on the toolbelt's width. If the toolbelt is
    // too big for the current window size, you could end up with a negative-width tab view frame.
    [self constrainToolbeltWidth];
    _tabViewFrameReduced = NO;
    if (![self tabBarShouldBeVisible]) {
        // The tabBarControl should not be visible.
        [self removeLeftTabBarDragHandle];
        self.tabBarControl.hidden = YES;
        CGFloat yOrigin = [_delegate haveBottomBorder] ? 1 : 0;
        CGFloat heightAdjustment = _delegate.divisionViewShouldBeVisible ? kDivisionViewHeight : 0;
        if ([_delegate haveTopBorder]) {
            heightAdjustment++;
        }
        NSRect tabViewFrame =
            NSMakeRect([_delegate haveLeftBorder] ? 1 : 0,
                       yOrigin,
                       [self tabviewWidth],
                       [[thisWindow contentView] frame].size.height - yOrigin - heightAdjustment);
        DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(tabViewFrame));
        [self.tabView setFrame:tabViewFrame];
        [self updateDivisionView];

        // Even though it's not visible it needs an accurate number so we can compute the proper
        // window size when it appears.
        [self setLeftTabBarWidthFromPreferredWidth];
    } else {
        // The tabBar control is visible.
        DLog(@"repositionWidgets - tabs are visible. Adjusting window size...");
        self.tabBarControl.hidden = NO;
        [self.tabBarControl setTabLocation:[iTermPreferences intForKey:kPreferenceKeyTabPosition]];

        switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
            case PSMTab_TopTab: {
                // Place tabs at the top.
                // Add 1px border
                [self removeLeftTabBarDragHandle];
                CGFloat yOrigin = _delegate.haveBottomBorder ? 1 : 0;
                CGFloat heightAdjustment = 0;
                if (!self.tabBarControl.flashing) {
                    heightAdjustment += _tabBarControl.height;
                }
                if (_delegate.haveTopBorder) {
                    heightAdjustment += 1;
                }
                if (_delegate.divisionViewShouldBeVisible) {
                    heightAdjustment += kDivisionViewHeight;
                }

                NSRect tabViewFrame =
                    NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
                               yOrigin,
                               [self tabviewWidth],
                               [[thisWindow contentView] frame].size.height - yOrigin - heightAdjustment);
                DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(tabViewFrame));
                [self.tabView setFrame:tabViewFrame];

                heightAdjustment = self.tabBarControl.flashing ? _tabBarControl.height : 0;
                NSRect tabBarFrame = NSMakeRect(tabViewFrame.origin.x,
                                                NSMaxY(tabViewFrame) - heightAdjustment,
                                                tabViewFrame.size.width,
                                                _tabBarControl.height);

                [self updateDivisionView];
                self.tabBarControl.insets = [self.delegate tabBarInsets];
                self.tabBarControl.frame = tabBarFrame;
                self.tabBarControl.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
                break;
            }

            case PSMTab_BottomTab: {
                DLog(@"repositionWidgets - putting tabs at bottom");
                [self removeLeftTabBarDragHandle];
                // setup aRect to make room for the tabs at the bottom.
                NSRect tabBarFrame = NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
                                                _delegate.haveBottomBorder ? 1 : 0,
                                                [self tabviewWidth],
                                                _tabBarControl.height);
                self.tabBarControl.insets = [self.delegate tabBarInsets];
                self.tabBarControl.frame = tabBarFrame;
                self.tabBarControl.autoresizingMask = (NSViewWidthSizable | NSViewMaxYMargin);

                CGFloat heightAdjustment = self.tabBarControl.flashing ? 0 : tabBarFrame.origin.y + _tabBarControl.height;
                if (_delegate.haveTopBorder) {
                    heightAdjustment += 1;
                }
                if (_delegate.divisionViewShouldBeVisible) {
                    heightAdjustment += kDivisionViewHeight;
                }
                CGFloat y = tabBarFrame.origin.y;
                if (!self.tabBarControl.flashing) {
                    y += _tabBarControl.height;
                }
                NSRect tabViewFrame = NSMakeRect(tabBarFrame.origin.x,
                                                 y,
                                                 tabBarFrame.size.width,
                                                 [thisWindow.contentView frame].size.height - heightAdjustment);
                DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(tabViewFrame));
                self.tabView.frame = tabViewFrame;
                [self updateDivisionView];
                break;
            }

            case PSMTab_LeftTab: {
                [self setLeftTabBarWidthFromPreferredWidth];
                CGFloat heightAdjustment = 0;
                if (_delegate.haveBottomBorder) {
                    heightAdjustment += 1;
                }
                if (_delegate.haveTopBorder) {
                    heightAdjustment += 1;
                }
                if (_delegate.divisionViewShouldBeVisible) {
                    heightAdjustment += kDivisionViewHeight;
                }
                NSRect tabBarFrame = NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
                                                _delegate.haveBottomBorder ? 1 : 0,
                                                [self tabviewWidth],
                                                [thisWindow.contentView frame].size.height - heightAdjustment);
                self.tabBarControl.insets = [self.delegate tabBarInsets];
                self.tabBarControl.frame = tabBarFrame;
                self.tabBarControl.autoresizingMask = (NSViewHeightSizable | NSViewMaxXMargin);

                CGFloat widthAdjustment = 0;
                if (_delegate.haveLeftBorder) {
                    widthAdjustment += 1;
                }
                if (_delegate.haveRightBorder) {
                    widthAdjustment += 1;
                }
                CGFloat xOffset = 0;
                if (self.tabBarControl.flashing) {
                    xOffset = -NSMaxX(tabBarFrame);
                    widthAdjustment -= NSWidth(tabBarFrame);
                }
                NSRect tabViewFrame = NSMakeRect(NSMaxX(tabBarFrame) + xOffset,
                                                 NSMinY(tabBarFrame),
                                                 [thisWindow.contentView frame].size.width - NSWidth(tabBarFrame) - widthAdjustment,
                                                 NSHeight(tabBarFrame));
                if (showToolbeltInline) {
                    tabViewFrame.size.width -= self.toolbeltFrame.size.width;
                }
                self.tabView.frame = tabViewFrame;
                [self updateDivisionView];

                const CGFloat dragHandleWidth = 3;
                NSRect leftTabBarDragHandleFrame = NSMakeRect(NSMaxX(self.tabBarControl.frame) - dragHandleWidth,
                                                              0,
                                                              dragHandleWidth,
                                                              NSHeight(self.tabBarControl.frame));
                if (!self.leftTabBarDragHandle) {
                    self.leftTabBarDragHandle = [[[iTermDragHandleView alloc] initWithFrame:leftTabBarDragHandleFrame] autorelease];
                    self.leftTabBarDragHandle.delegate = self;
                    [self addSubview:self.leftTabBarDragHandle];
                } else {
                    self.leftTabBarDragHandle.frame = leftTabBarDragHandleFrame;
                }
            }
        }
    }

    if (showToolbeltInline) {
        [self updateToolbeltFrame];
    }

    // Update the tab style.
    [self.tabBarControl setDisableTabClose:[iTermPreferences boolForKey:kPreferenceKeyHideTabCloseButton]];
    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabCloseButton] &&
        [iTermPreferences boolForKey:kPreferenceKeyHideTabNumber]) {
        [self.tabBarControl setCellMinWidth:[iTermAdvancedSettingsModel minCompactTabWidth]];
    } else {
        [self.tabBarControl setCellMinWidth:[iTermAdvancedSettingsModel minTabWidth]];
    }
    [self.tabBarControl setSizeCellsToFit:[iTermAdvancedSettingsModel useUnevenTabs]];
    [self.tabBarControl setStretchCellsToFit:[iTermPreferences boolForKey:kPreferenceKeyStretchTabsToFillBar]];
    [self.tabBarControl setCellOptimumWidth:[iTermAdvancedSettingsModel optimumTabWidth]];
    self.tabBarControl.smartTruncation = [iTermAdvancedSettingsModel tabTitlesUseSmartTruncation];

    DLog(@"repositionWidgets - redraw view");
    // Note: this used to call setNeedsDisplay on each session in the current tab.
    [self setNeedsDisplay:YES];

    DLog(@"repositionWidgets - update tab bar");
    [self.tabBarControl updateFlashing];
    DLog(@"repositionWidgets - return.");
}

- (CGFloat)leftTabBarWidthForPreferredWidth:(CGFloat)preferredWidth contentWidth:(CGFloat)contentWidth {
    const CGFloat minimumWidth = 50;
    const CGFloat maximumWidth = contentWidth / 3;
    return MAX(MIN(maximumWidth, preferredWidth), minimumWidth);
}

- (CGFloat)leftTabBarWidthForPreferredWidth:(CGFloat)preferredWidth {
    return [self leftTabBarWidthForPreferredWidth:preferredWidth contentWidth:self.bounds.size.width];
}

- (void)setLeftTabBarWidthFromPreferredWidth {
    _leftTabBarWidth = [self leftTabBarWidthForPreferredWidth:_leftTabBarPreferredWidth];
}

- (void)willShowTabBar {
    const CGFloat minimumWidth = 50;
    // Given that the New window width (N) = Tab bar width (T) + Content Size (C)
    // Given that T < N/3 (by leftTabBarWidthForPreferredWidth):
    // T <= N / 3
    // T <= 1/3(T+C)
    // T <= T/3 + C/3
    // 2/3T <= C/3
    // T <= C/2
    const CGFloat maximumWidth = self.bounds.size.width / 2;
    _leftTabBarWidth = MAX(MIN(maximumWidth, _leftTabBarPreferredWidth), minimumWidth);
}

#pragma mark - iTermTabBarControlViewDelegate

- (BOOL)iTermTabBarShouldFlashAutomatically {
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
    return[ _delegate iTermTabBarCanDragWindow];
}

#pragma mark - iTermDragHandleViewDelegate

// For the left-side tab bar.
- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    CGFloat originalValue = _leftTabBarPreferredWidth;
    _leftTabBarPreferredWidth = [self leftTabBarWidthForPreferredWidth:_leftTabBarPreferredWidth + delta];
    [self layoutSubviews];  // This may modify _leftTabBarWidth if it's too big or too small.
    [[NSUserDefaults standardUserDefaults] setDouble:_leftTabBarPreferredWidth
                                              forKey:kPreferenceKeyLeftTabBarWidth];
    return _leftTabBarPreferredWidth - originalValue;
}

- (void)dragHandleViewDidFinishMoving:(iTermDragHandleView *)dragHandle {
    [_delegate rootTerminalViewDidResizeContentArea];
}

#pragma mark - iTermStoplightHotboxDelegate

- (void)stoplightHotboxMouseExit {
    [NSView animateWithDuration:0.25
                     animations:^{
                         _stoplightHotbox.animator.alphaValue = 0;
                         _standardWindowButtonsView.animator.alphaValue = 0;
                     }
                     completion:^(BOOL finished) {
                         if (!finished) {
                             return;
                         }
                     }];
}

- (BOOL)stoplightHotboxMouseEnter {
    if ([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagCommand) {
        return NO;
    }
    [_stoplightHotbox setNeedsDisplay:YES];
    _stoplightHotbox.alphaValue = 0;
    _standardWindowButtonsView.alphaValue = 0;
    [NSView animateWithDuration:0.25
                     animations:^{
                         _stoplightHotbox.animator.alphaValue = 1;
                         _standardWindowButtonsView.animator.alphaValue = 1;
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

@end
