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
#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "NSAppearance+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PTYTabView.h"

const CGFloat iTermStandardButtonsViewHeight = 25;
const CGFloat iTermStandardButtonsViewWidth = 69;
const CGFloat iTermStoplightHotboxWidth = iTermStandardButtonsViewWidth + 28 + 24;
const CGFloat iTermStoplightHotboxHeight = iTermStandardButtonsViewHeight + 8;
const CGFloat kDivisionViewHeight = 1;

const NSInteger iTermRootTerminalViewWindowNumberLabelMargin = 6;
const NSInteger iTermRootTerminalViewWindowNumberLabelWidth = 40;

static const CGFloat kMinimumToolbeltSizeInPoints = 100;
static const CGFloat kMinimumToolbeltSizeAsFractionOfWindow = 0.05;
static const CGFloat kMaximumToolbeltSizeAsFractionOfWindow = 0.5;

@interface iTermRootTerminalView()<
    iTermTabBarControlViewDelegate,
    iTermDragHandleViewDelegate,
    iTermStoplightHotboxDelegate>

@property(nonatomic, strong) PTYTabView *tabView;
@property(nonatomic, strong) iTermTabBarControlView *tabBarControl;
@property(nonatomic, strong) SolidColorView *divisionView;
@property(nonatomic, strong) iTermToolbeltView *toolbelt;
@property(nonatomic, strong) iTermDragHandleView *leftTabBarDragHandle;

@end

@implementation iTermRootTerminalView {
    BOOL _tabViewFrameReduced;
    BOOL _haveShownToolbelt;
    iTermStoplightHotbox *_stoplightHotbox;
    iTermStandardWindowButtonsView *_standardWindowButtonsView;
    NSMutableDictionary<NSNumber *, NSButton *> *_standardButtons;
    NSString *_windowTitle;
    NSNumber *_windowNumber;
    NSTextField *_windowNumberLabel;
    NSTextField *_windowTitleLabel;
    NSVisualEffectView *_tabBarBacking NS_AVAILABLE_MAC(10_14);
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
        self.tabView = [[PTYTabView alloc] initWithFrame:self.bounds];
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

        if (@available(macOS 10.14, *)) {
            _tabBarBacking = [[NSVisualEffectView alloc] init];
            _tabBarBacking.autoresizesSubviews = YES;
            _tabBarBacking.blendingMode = NSVisualEffectBlendingModeWithinWindow;
            _tabBarBacking.material = NSVisualEffectMaterialTitlebar;
            _tabBarBacking.state = NSVisualEffectStateActive;
        }

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
        
        int theModifier =
            [iTermPreferences maskForModifierTag:[iTermPreferences intForKey:kPreferenceKeySwitchTabModifier]];
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
        }
        if (@available(macOS 10.14, *)) {
            [self addSubview:_tabBarBacking];
            [_tabBarBacking addSubview:_tabBarControl];
        } else {
            [self addSubview:_tabBarControl];
        }
        _tabBarControl.tabView = _tabView;
        [_tabView setDelegate:_tabBarControl];
        _tabBarControl.delegate = tabBarDelegate;
        _tabBarControl.hideForSingleTab = NO;

        // Create the toolbelt with its current default size.
        _toolbeltWidth = [iTermPreferences floatForKey:kPreferenceKeyDefaultToolbeltWidth];
        [self constrainToolbeltWidth];

        self.toolbelt = [[iTermToolbeltView alloc] initWithFrame:self.toolbeltFrame
                                                        delegate:(id)_delegate];
        _toolbelt.autoresizingMask = (NSViewMinXMargin | NSViewHeightSizable);
        [self addSubview:_toolbelt];
        [self updateToolbelt];

        _windowNumberLabel = [NSTextField newLabelStyledTextField];
        _windowNumberLabel.alphaValue = 0.75;
        _windowNumberLabel.hidden = YES;
        [self addSubview:_windowNumberLabel];

        _windowTitleLabel = [NSTextField newLabelStyledTextField];
        _windowTitleLabel.alignment = NSTextAlignmentCenter;
        _windowTitleLabel.hidden = YES;
        [self addSubview:_windowTitleLabel];
    }
    return self;
}

- (void)dealloc {
    _tabBarControl.itermTabBarDelegate = nil;
    _tabBarControl.delegate = nil;
    _leftTabBarDragHandle.delegate = nil;
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *view = [super hitTest:point];
    if (!_tabBarControlOnLoan && !_windowNumberLabel.hidden && view == _windowNumberLabel) {
        return _tabBarControl;
    } else if (!_windowTitleLabel.hidden && view == _windowTitleLabel) {
        return self;
    } else {
        return view;
    }
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
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
        insets.left = insets.right = 6;
        insets.bottom = -[self.delegate rootTerminalViewStoplightButtonsOffset:self];
        return insets;
    }

    const CGFloat hotboxSideInset = (iTermStoplightHotboxWidth - iTermStandardButtonsViewWidth) / 2.0;
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
                              iTermStandardButtonsViewWidth,
                              iTermStandardButtonsViewHeight);
    return frame;
}

- (NSRect)frameForWindowNumberLabel {
    if (_tabBarControlOnLoan) {
        return NSZeroRect;
    }
    [_windowNumberLabel sizeToFit];
    const NSRect standardButtonsFrame = [self frameForStandardWindowButtons];
    const CGFloat tabBarHeight = _tabBarControl.height;
    const CGFloat windowNumberHeight = _windowNumberLabel.frame.size.height;
    const CGFloat baselineOffset = -_windowNumberLabel.font.descender;
    const CGFloat capHeight = _windowNumberLabel.font.capHeight;
    const CGFloat myHeight = self.frame.size.height;
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    const CGFloat shift = (preferredStyle == TAB_STYLE_MINIMAL) ? 0 : 1;
    return NSMakeRect(NSMaxX(standardButtonsFrame) + iTermRootTerminalViewWindowNumberLabelMargin,
                      myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset - shift,
                      iTermRootTerminalViewWindowNumberLabelWidth,
                      windowNumberHeight);
}

- (NSRect)frameForWindowTitleLabel {
    if (_tabBarControlOnLoan) {
        return NSZeroRect;
    }
    const CGFloat tabBarHeight = _tabBarControl.height;
    const CGFloat baselineOffset = -_windowTitleLabel.font.descender;
    const CGFloat capHeight = _windowTitleLabel.font.capHeight;
    const CGFloat myHeight = self.frame.size.height;
    NSEdgeInsets insets = [self.delegate tabBarInsets];
    return NSMakeRect(insets.left,
                      myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset,
                      MAX(0, self.frame.size.width - insets.left - iTermRootTerminalViewWindowNumberLabelMargin),
                      _windowTitleLabel.frame.size.height);
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
        if ([_delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
            // Draw background color for fake title bar.
            [[_delegate rootTerminalViewTabBarBackgroundColor] set];
            const CGFloat height = [_delegate rootTerminalViewHeightOfTabBar:self];
            NSRectFill(NSMakeRect(0,
                                  self.frame.size.height - height,
                                  self.frame.size.width,
                                  height));
        }

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
    _divisionView = nil;

    [self updateDivisionViewAndWindowNumberLabel];
}

- (void)viewDidChangeEffectiveAppearance {
    [self.delegate rootTerminalViewDidChangeEffectiveAppearance];
}

- (void)windowTitleDidChangeTo:(NSString *)title {
    _windowTitle = [title copy];

    [self setWindowTitleLabelToString:_windowTitle icon:[self.delegate rootTerminalViewCurrentTabIcon]];
}

- (void)setWindowTitleLabelToString:(NSString *)title icon:(NSImage *)icon {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{ NSFontAttributeName: _windowTitleLabel.font,
                                  NSForegroundColorAttributeName: _windowTitleLabel.textColor,
                                  NSParagraphStyleAttributeName: paragraphStyle };
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:title
                                                                           attributes:attributes];
    if (icon) {
        NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
        textAttachment.image = icon;
        NSFont *font = _windowTitleLabel.font;
        const CGFloat lineHeight = ceilf(font.capHeight);
        textAttachment.bounds = NSMakeRect(0,
                                           - (icon.size.height - lineHeight) / 2.0,
                                           icon.size.width,
                                           icon.size.height);
        NSMutableAttributedString *iconAttributedString = [[NSAttributedString attributedStringWithAttachment:textAttachment] mutableCopy];
        [iconAttributedString addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, iconAttributedString.length)];
        [iconAttributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:attributes]];
        [iconAttributedString appendAttributedString:attributedString];
        _windowTitleLabel.attributedStringValue = iconAttributedString;
    } else {
        _windowTitleLabel.stringValue = title;
    }
}

- (void)setWindowTitleIcon:(NSImage *)icon {
    [self setWindowTitleLabelToString:_windowTitle icon:icon];
}

- (iTermTabBarControlView *)borrowTabBarControl {
    assert(!_tabBarControlOnLoan);
    iTermTabBarControlView *view = _tabBarControl;
    _tabBarControlOnLoan = YES;
    if (@available(macOS 10.14, *)) {
        _tabBarBacking.hidden = YES;
    }
    return view;
}

- (void)returnTabBarControlView:(iTermTabBarControlView *)tabBarControl {
    assert(_tabBarControlOnLoan);
    _tabBarControlOnLoan = NO;
    if (@available(macOS 10.14, *)) {
        [_tabBarBacking addSubview:tabBarControl];
    } else {
        [self addSubview:tabBarControl];
    }
    _tabBarControl.frame = _tabBarBacking.bounds;
    _tabBarControl = tabBarControl;
    [self.tabBarControl updateFlashing];
    if (@available(macOS 10.14, *)) {
        _tabBarBacking.hidden = NO;
    }
}

- (void)windowNumberDidChangeTo:(NSNumber *)number {
    _windowNumber = number;
    BOOL deemphasized;
    _windowNumberLabel.stringValue = [iTermWindowShortcutLabelTitlebarAccessoryViewController stringForOrdinal:number.intValue deempahsized:&deemphasized];
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
        _divisionView = nil;
    }

    _windowNumberLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForWindowNumber];
    _windowTitleLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForTitle];
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
    _toolbelt = nil;
    _delegate = nil;
}

- (BOOL)scrollbarShouldBeVisible {
    return ![iTermPreferences boolForKey:kPreferenceKeyHideScrollbar];
}

- (BOOL)tabBarShouldBeVisible {
    if (_tabBarControlOnLoan) {
        return NO;
    }
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

- (void)updateWindowNumberFont {
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle == TAB_STYLE_MINIMAL) {
        _windowNumberLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    } else {
        _windowNumberLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    }
}

- (void)layoutSubviewsWithHiddenTabBarForWindow:(NSWindow *)thisWindow {
    if ([self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        [self layoutSubviewsTopTabBarVisible:NO forWindow:thisWindow];
        return;
    }

    [self removeLeftTabBarDragHandle];
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
    [self updateDivisionViewAndWindowNumberLabel];

    // Even though it's not visible it needs an accurate number so we can compute the proper
    // window size when it appears.
    [self setLeftTabBarWidthFromPreferredWidth];
}

- (void)layoutSubviewsTopTabBarVisible:(BOOL)topTabBarVisible forWindow:(NSWindow *)thisWindow {
    [self removeLeftTabBarDragHandle];
    CGFloat yOrigin = _delegate.haveBottomBorder ? 1 : 0;
    CGFloat heightAdjustment = 0;
    if (!_tabBarControlOnLoan) {
        if (!self.tabBarControl.flashing) {
            heightAdjustment += _tabBarControl.height;
        }
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

    if (_tabBarControlOnLoan) {
        heightAdjustment = 0;
    } else {
        heightAdjustment = self.tabBarControl.flashing ? _tabBarControl.height : 0;
    }
    NSRect tabBarFrame = NSMakeRect(tabViewFrame.origin.x,
                                    NSMaxY(tabViewFrame) - heightAdjustment,
                                    tabViewFrame.size.width,
                                    _tabBarControl.height);

    [self updateDivisionViewAndWindowNumberLabel];
    if (!_tabBarControlOnLoan) {
        self.tabBarControl.insets = [self.delegate tabBarInsets];
        [self setTabBarFrame:tabBarFrame];
        [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    }
}

- (void)setTabBarFrame:(NSRect)frame {
    if (@available(macOS 10.14, *)) {
        assert(!_tabBarControlOnLoan);
        _tabBarBacking.frame = frame;
        self.tabBarControl.frame = _tabBarBacking.bounds;
    } else {
        self.tabBarControl.frame = frame;
    }
}

- (void)layoutSubviewsWithVisibleBottomTabBarForWindow:(NSWindow *)thisWindow {
    assert(!_tabBarControlOnLoan);
    DLog(@"repositionWidgets - putting tabs at bottom");
    [self removeLeftTabBarDragHandle];
    // setup aRect to make room for the tabs at the bottom.
    NSRect tabBarFrame = NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
                                    _delegate.haveBottomBorder ? 1 : 0,
                                    [self tabviewWidth],
                                    _tabBarControl.height);
    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];

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
    [self updateDivisionViewAndWindowNumberLabel];
}

- (void)setTabBarControlAutoresizingMask:(NSAutoresizingMaskOptions)mask {
    if (@available(macOS 10.14, *)) {
        if (_tabBarBacking) {
            _tabBarBacking.autoresizingMask = mask;
            _tabBarControl.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            return;
        }
    }

    _tabBarControl.autoresizingMask = mask;
}

- (void)layoutSubviewsWithVisibleLeftTabBarAndInlineToolbelt:(BOOL)showToolbeltInline forWindow:(NSWindow *)thisWindow {
    assert(!_tabBarControlOnLoan);
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
    [self setTabBarFrame:tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMaxXMargin)];

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
    [self updateDivisionViewAndWindowNumberLabel];

    const CGFloat dragHandleWidth = 3;
    NSRect leftTabBarDragHandleFrame = NSMakeRect(NSMaxX(self.tabBarControl.frame) - dragHandleWidth,
                                                  0,
                                                  dragHandleWidth,
                                                  NSHeight(self.tabBarControl.frame));
    if (!self.leftTabBarDragHandle) {
        self.leftTabBarDragHandle = [[iTermDragHandleView alloc] initWithFrame:leftTabBarDragHandleFrame];
        self.leftTabBarDragHandle.delegate = self;
        [self addSubview:self.leftTabBarDragHandle];
    } else {
        self.leftTabBarDragHandle.frame = leftTabBarDragHandleFrame;
    }
}

- (void)layoutSubviews {
    DLog(@"layoutSubviews");

    BOOL showToolbeltInline = self.shouldShowToolbelt;
    NSWindow *thisWindow = _delegate.window;
    if (!_tabBarControlOnLoan) {
        self.tabBarControl.height = [_delegate rootTerminalViewHeightOfTabBar:self];
    }

    _windowNumberLabel.textColor = [_delegate rootTerminalViewTabBarTextColorForWindowNumber];
    _windowTitleLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForTitle];
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
    _standardWindowButtonsView.frame = [self frameForStandardWindowButtons];

    // The tab view frame (calculated below) is based on the toolbelt's width. If the toolbelt is
    // too big for the current window size, you could end up with a negative-width tab view frame.
    [self constrainToolbeltWidth];
    _tabViewFrameReduced = NO;
    if (![self tabBarShouldBeVisible]) {
        // The tabBarControl should not be visible.
        if (!_tabBarControlOnLoan) {
            self.tabBarControl.hidden = YES;
        }
        [self layoutSubviewsWithHiddenTabBarForWindow:thisWindow];
    } else {
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
    if (!_tabBarControlOnLoan) {
        [self.tabBarControl updateFlashing];
    }
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
                         self->_stoplightHotbox.animator.alphaValue = 0;
                         self->_standardWindowButtonsView.animator.alphaValue = 0;
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
                         self->_stoplightHotbox.animator.alphaValue = 1;
                         self->_standardWindowButtonsView.animator.alphaValue = 1;
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
