//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDragHandleView.h"
#import "iTermPreferences.h"
#import "iTermTabBarControlView.h"
#import "iTermToolbeltView.h"
#import "PTYTabView.h"

const CGFloat kHorizontalTabBarHeight = 22;
const CGFloat kDivisionViewHeight = 1;

static const CGFloat kDefaultToolbeltWidth = 250;
static const CGFloat kMinimumToolbeltSizeInPoints = 100;
static const CGFloat kMinimumToolbeltSizeAsFractionOfWindow = 0.05;
static const CGFloat kMaximumToolbeltSizeAsFractionOfWindow = 0.5;

@interface iTermRootTerminalView()<iTermTabBarControlViewDelegate, iTermDragHandleViewDelegate>

@property(nonatomic, retain) PTYTabView *tabView;
@property(nonatomic, retain) iTermTabBarControlView *tabBarControl;
@property(nonatomic, retain) SolidColorView *divisionView;
@property(nonatomic, retain) iTermToolbeltView *toolbelt;
@property(nonatomic, retain) iTermDragHandleView *leftTabBarDragHandle;
@end


@implementation iTermRootTerminalView {
    BOOL _tabViewFrameReduced;
}

- (instancetype)initWithFrame:(NSRect)frameRect
                        color:(NSColor *)color
               tabBarDelegate:(id<iTermTabBarControlViewDelegate,PSMTabBarControlDelegate>)tabBarDelegate
                     delegate:(id<iTermRootTerminalViewDelegate, iTermToolbeltViewDelegate>)delegate {
    self = [super initWithFrame:frameRect color:color];
    if (self) {
        _delegate = delegate;

        self.autoresizesSubviews = YES;
        _leftTabBarWidth = [iTermPreferences doubleForKey:kPreferenceKeyLeftTabBarWidth];
        // Create the tab view.
        self.tabView = [[[PTYTabView alloc] initWithFrame:self.bounds] autorelease];
        _tabView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        _tabView.autoresizesSubviews = YES;
        _tabView.allowsTruncatedLabels = NO;
        _tabView.controlSize = NSSmallControlSize;
        _tabView.tabViewType = NSNoTabsNoBorder;
        [self addSubview:_tabView];

        // Create the tab bar.
        NSRect tabBarFrame = self.bounds;
        tabBarFrame.size.height = kHorizontalTabBarHeight;
        self.tabBarControl = [[[iTermTabBarControlView alloc] initWithFrame:tabBarFrame] autorelease];
        _tabBarControl.itermTabBarDelegate = self;

        int theModifier =
            [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]];
        [_tabBarControl setModifier:theModifier];
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

        // Create the toolbelt
        // A decent default value.
        _toolbeltWidth = kDefaultToolbeltWidth;
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

    [super dealloc];
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
            _divisionView = [[SolidColorView alloc] initWithFrame:divisionViewFrame];
            _divisionView.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
            [self addSubview:_divisionView];
        }
        _divisionView.color = self.window.isKeyWindow
                ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.49 alpha:1]
                : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.65 alpha:1];
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
    return ([self.tabView numberOfTabViewItems] + numberOfAdditionalTabs > 1 ||
            ![iTermPreferences boolForKey:kPreferenceKeyHideTabBar]);
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
    BOOL hasScrollbar = self.scrollbarShouldBeVisible;
    NSWindow *thisWindow = _delegate.window;
    [thisWindow setShowsResizeIndicator:hasScrollbar];

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
                    heightAdjustment += kHorizontalTabBarHeight;
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

                heightAdjustment = self.tabBarControl.flashing ? kHorizontalTabBarHeight : 0;
                NSRect tabBarFrame = NSMakeRect(tabViewFrame.origin.x,
                                                NSMaxY(tabViewFrame) - heightAdjustment,
                                                tabViewFrame.size.width,
                                                kHorizontalTabBarHeight);

                [self updateDivisionView];
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
                                                kHorizontalTabBarHeight);
                self.tabBarControl.frame = tabBarFrame;
                self.tabBarControl.autoresizingMask = (NSViewWidthSizable | NSViewMaxYMargin);

                CGFloat heightAdjustment = self.tabBarControl.flashing ? 0 : tabBarFrame.origin.y + kHorizontalTabBarHeight;
                if (_delegate.haveTopBorder) {
                    heightAdjustment += 1;
                }
                if (_delegate.divisionViewShouldBeVisible) {
                    heightAdjustment += kDivisionViewHeight;
                }
                CGFloat y = tabBarFrame.origin.y;
                if (!self.tabBarControl.flashing) {
                    y += kHorizontalTabBarHeight;
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
                [self constrainLeftTabBarWidth];
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
    [self.tabBarControl setCellOptimumWidth:[iTermAdvancedSettingsModel optimumTabWidth]];
    self.tabBarControl.smartTruncation = [iTermAdvancedSettingsModel tabTitlesUseSmartTruncation];
    
    DLog(@"repositionWidgets - redraw view");
    // Note: this used to call setNeedsDisplay on each session in the current tab.
    [self setNeedsDisplay:YES];

    DLog(@"repositionWidgets - update tab bar");
    [self.tabBarControl updateFlashing];
    DLog(@"repositionWidgets - return.");
}

- (void)constrainLeftTabBarWidth {
    if (_leftTabBarWidth < 50) {
        _leftTabBarWidth = 50;
    }
    const CGFloat maxWidth = self.bounds.size.width / 3;
    if (_leftTabBarWidth > maxWidth) {
        _leftTabBarWidth = maxWidth;
    }
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

#pragma mark - iTermDragHandleViewDelegate

// For the left-side tab bar.
- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    CGFloat originalValue = _leftTabBarWidth;
    _leftTabBarWidth += delta;
    [self layoutSubviews];  // This may modify _leftTabBarWidth if it's too big or too small.
    [[NSUserDefaults standardUserDefaults] setDouble:_leftTabBarWidth
                                              forKey:kPreferenceKeyLeftTabBarWidth];
    return _leftTabBarWidth - originalValue;
}

- (void)dragHandleViewDidFinishMoving:(iTermDragHandleView *)dragHandle {
    [_delegate rootTerminalViewDidResizeContentArea];
}

@end
