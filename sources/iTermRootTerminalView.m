//
//  iTermRootTerminalView.m
//  iTerm2
//
//  Created by George Nachman on 7/3/15.
//
//

#import "iTermRootTerminalView.h"

#import "DebugLogging.h"

#import "NSEvent+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "PTYTabView.h"
#import "PTYWindow.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDragHandleView.h"
#import "iTermFakeWindowTitleLabel.h"
#import "iTermGenericStatusBarContainer.h"
#import "iTermImageView.h"
#import "iTermPreferences.h"
#import "iTermWindowSizeView.h"
#import "iTermStandardWindowButtonsView.h"
#import "iTermStatusBarViewController.h"
#import "iTermStoplightHotbox.h"
#import "iTermTabBarControlView.h"
#import "iTermToolbeltView.h"
#import "iTermWindowShortcutLabelTitlebarAccessoryViewController.h"
#import "NSAppearance+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "NSWindow+iTerm.h"
#import "PTYTabView.h"

static const CGFloat iTermWindowBorderRadius = 12;

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
@property(nonatomic, strong) iTermDragHandleView *leftTabBarDragHandle;

@end

NS_CLASS_AVAILABLE_MAC(10_14)
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
            if (@available(macOS 10.16, *)) {
                state = NSVisualEffectStateFollowsWindowActiveState;
            }
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
        if (@available(macOS 10.16, *)) {
            return;
        }
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
    NSNumber *_windowNumber;
    NSTextField *_windowNumberLabel;
    iTermFakeWindowTitleLabel *_windowTitleLabel;
    iTermTabBarBacking *_tabBarBacking NS_AVAILABLE_MAC(10_14);
    iTermGenericStatusBarContainer *_statusBarContainer;
    NSDictionary *_desiredToolbeltProportions;
    iTermWindowSizeView *_windowSizeView NS_AVAILABLE_MAC(10_14);

    iTermLayerBackedSolidColorView *_titleBackgroundView NS_AVAILABLE_MAC(10_14);
    
    NSImageView *_topLeftCornerHalfRoundImageView NS_AVAILABLE_MAC(10_14);
    NSImageView *_topRightCornerHalfRoundImageView NS_AVAILABLE_MAC(10_14);
    NSImageView *_bottomLeftCornerHalfRoundImageView NS_AVAILABLE_MAC(10_14);
    NSImageView *_bottomRightCornerHalfRoundImageView NS_AVAILABLE_MAC(10_14);

    NSImageView *_topLeftCornerFullRoundImageView NS_AVAILABLE_MAC(10_14);
    NSImageView *_topRightCornerFullRoundImageView NS_AVAILABLE_MAC(10_14);
    NSImageView *_bottomLeftCornerFullRoundImageView NS_AVAILABLE_MAC(10_14);
    NSImageView *_bottomRightCornerFullRoundImageView NS_AVAILABLE_MAC(10_14);

    NSView *_leftBorderView NS_AVAILABLE_MAC(10_14);
    NSView *_rightBorderView NS_AVAILABLE_MAC(10_14);
    NSView *_topBorderView NS_AVAILABLE_MAC(10_14);
    NSView *_bottomBorderView NS_AVAILABLE_MAC(10_14);
    
    iTermImageView *_backgroundImage NS_AVAILABLE_MAC(10_14);
    NSView *_workaroundView;  // 10.14 only. See issue 8701.
    iTermLayerBackedSolidColorView *_notchMask NS_AVAILABLE_MAC(12_0);
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
        if (@available(macOS 10.16, *)) {
            _windowNumberLabel.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
        }
        _windowNumberLabel.alphaValue = 0.75;
        _windowNumberLabel.hidden = YES;
        _windowNumberLabel.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);
        [self addSubview:_windowNumberLabel];

        _windowTitleLabel = [iTermFakeWindowTitleLabel newLabelStyledTextField];
        if (@available(macOS 10.16, *)) {
            _windowTitleLabel.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
        }
        _windowTitleLabel.alphaValue = 1;
        _windowTitleLabel.alignment = NSTextAlignmentCenter;
        _windowTitleLabel.hidden = YES;
        _windowTitleLabel.autoresizingMask = (NSViewMinYMargin | NSViewWidthSizable);
        [self addSubview:_windowTitleLabel];
        
        NSColor *borderColor = [NSColor colorWithWhite:0.5 alpha:0.75];
        {
            static NSImage *gTopLeftCornerHalfImage;
            static NSImage *gTopRightCornerHalfImage;
            static NSImage *gBottomLeftCornerHalfImage;
            static NSImage *gBottomRightCornerHalfImage;

            static NSImage *gTopLeftCornerFullImage;
            static NSImage *gTopRightCornerFullImage;
            static NSImage *gBottomLeftCornerFullImage;
            static NSImage *gBottomRightCornerFullImage;

            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSString *halfName = @"WindowCorner";
                if (@available(macOS 10.16, *)) {
                    halfName = @"WindowCorner_BigSur";
                }
                if ([iTermAdvancedSettingsModel squareWindowCorners]) {
                    halfName = @"WindowCorner_Square";
                }
                gTopLeftCornerHalfImage = [[NSImage it_imageNamed:halfName forClass:self.class] it_verticallyFlippedImage];
                gTopRightCornerHalfImage = [gTopLeftCornerHalfImage it_horizontallyFlippedImage];
                gBottomLeftCornerHalfImage = [NSImage it_imageNamed:halfName forClass:self.class];
                gBottomRightCornerHalfImage = [gBottomLeftCornerHalfImage it_horizontallyFlippedImage];

                NSString *fullName = @"WindowCornerFull";
                if (@available(macOS 10.16, *)) {
                    fullName = @"WindowCornerFull_BigSur";
                }
                if ([iTermAdvancedSettingsModel squareWindowCorners]) {
                    fullName = @"WindowCornerFull_Square";
                }
                gTopLeftCornerFullImage = [[NSImage it_imageNamed:fullName forClass:self.class] it_verticallyFlippedImage];
                gTopRightCornerFullImage = [gTopLeftCornerFullImage it_horizontallyFlippedImage];
                gBottomLeftCornerFullImage = [NSImage it_imageNamed:fullName forClass:self.class];
                gBottomRightCornerFullImage = [gBottomLeftCornerFullImage it_horizontallyFlippedImage];
            });
            // Half
            NSImage *topLeftCornerHalfImage = gTopLeftCornerHalfImage;
            NSImage *topRightCornerHalfImage = gTopRightCornerHalfImage;
            NSImage *bottomLeftCornerHalfImage = gBottomLeftCornerHalfImage;
            NSImage *bottomRightCornerHalfImage = gBottomRightCornerHalfImage;

            _topLeftCornerHalfRoundImageView = [NSImageView imageViewWithImage:topLeftCornerHalfImage];
            _topLeftCornerHalfRoundImageView.autoresizingMask = NSViewMinYMargin | NSViewMaxXMargin;
            _topLeftCornerHalfRoundImageView.alphaValue = 0.75;

            _topRightCornerHalfRoundImageView = [NSImageView imageViewWithImage:topRightCornerHalfImage];
            _topRightCornerHalfRoundImageView.alphaValue = 0.75;
            _topRightCornerHalfRoundImageView.autoresizingMask = NSViewMinYMargin | NSViewMinXMargin;

            _bottomLeftCornerHalfRoundImageView = [NSImageView imageViewWithImage:bottomLeftCornerHalfImage];
            _bottomLeftCornerHalfRoundImageView.alphaValue = 0.75;
            _bottomLeftCornerHalfRoundImageView.autoresizingMask = NSViewMaxYMargin | NSViewMaxXMargin;

            _bottomRightCornerHalfRoundImageView = [NSImageView imageViewWithImage:bottomRightCornerHalfImage];
            _bottomRightCornerHalfRoundImageView.alphaValue = 0.75;
            _bottomRightCornerHalfRoundImageView.autoresizingMask = NSViewMaxYMargin | NSViewMinXMargin;

            _topLeftCornerHalfRoundImageView.hidden = YES;
            _topRightCornerHalfRoundImageView.hidden = YES;
            _bottomLeftCornerHalfRoundImageView.hidden = YES;
            _bottomRightCornerHalfRoundImageView.hidden = YES;

            [self addSubview:_topLeftCornerHalfRoundImageView];
            [self addSubview:_topRightCornerHalfRoundImageView];
            [self addSubview:_bottomLeftCornerHalfRoundImageView];
            [self addSubview:_bottomRightCornerHalfRoundImageView];

            // Full

            NSImage *topLeftCornerFullImage = gTopLeftCornerFullImage;
            NSImage *topRightCornerFullImage = gTopRightCornerFullImage;
            NSImage *bottomLeftCornerFullImage = gBottomLeftCornerFullImage;
            NSImage *bottomRightCornerFullImage = gBottomRightCornerFullImage;

            _topLeftCornerFullRoundImageView = [NSImageView imageViewWithImage:topLeftCornerFullImage];
            _topLeftCornerFullRoundImageView.autoresizingMask = NSViewMinYMargin | NSViewMaxXMargin;
            _topLeftCornerFullRoundImageView.alphaValue = 0.75;

            _topRightCornerFullRoundImageView = [NSImageView imageViewWithImage:topRightCornerFullImage];
            _topRightCornerFullRoundImageView.alphaValue = 0.75;
            _topRightCornerFullRoundImageView.autoresizingMask = NSViewMinYMargin | NSViewMinXMargin;

            _bottomLeftCornerFullRoundImageView = [NSImageView imageViewWithImage:bottomLeftCornerFullImage];
            _bottomLeftCornerFullRoundImageView.alphaValue = 0.75;
            _bottomLeftCornerFullRoundImageView.autoresizingMask = NSViewMaxYMargin | NSViewMaxXMargin;

            _bottomRightCornerFullRoundImageView = [NSImageView imageViewWithImage:bottomRightCornerFullImage];
            _bottomRightCornerFullRoundImageView.alphaValue = 0.75;
            _bottomRightCornerFullRoundImageView.autoresizingMask = NSViewMaxYMargin | NSViewMinXMargin;

            _topLeftCornerFullRoundImageView.hidden = YES;
            _topRightCornerFullRoundImageView.hidden = YES;
            _bottomLeftCornerFullRoundImageView.hidden = YES;
            _bottomRightCornerFullRoundImageView.hidden = YES;

            [self addSubview:_topLeftCornerFullRoundImageView];
            [self addSubview:_topRightCornerFullRoundImageView];
            [self addSubview:_bottomLeftCornerFullRoundImageView];
            [self addSubview:_bottomRightCornerFullRoundImageView];
        }
        {
            _leftBorderView = [[NSView alloc] init];
            _leftBorderView.wantsLayer = YES;
            _leftBorderView.layer.backgroundColor = borderColor.CGColor;
            _leftBorderView.autoresizingMask = NSViewMaxXMargin | NSViewHeightSizable;

            _rightBorderView = [[NSView alloc] init];
            _rightBorderView.wantsLayer = YES;
            _rightBorderView.layer.backgroundColor = borderColor.CGColor;
            _rightBorderView.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;

            _topBorderView = [[NSView alloc] init];
            _topBorderView.wantsLayer = YES;
            _topBorderView.layer.backgroundColor = borderColor.CGColor;
            _topBorderView.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;

            _bottomBorderView = [[NSView alloc] init];
            _bottomBorderView.wantsLayer = YES;
            _bottomBorderView.layer.backgroundColor = borderColor.CGColor;
            _bottomBorderView.autoresizingMask = NSViewMaxYMargin | NSViewWidthSizable;

            [self addSubview:_leftBorderView];
            [self addSubview:_rightBorderView];
            [self addSubview:_topBorderView];
            [self addSubview:_bottomBorderView];
        }


        if (@available(macOS 10.15, *)) {} else {
            // 10.14 only
            _workaroundView = [[SolidColorView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1) color:[NSColor clearColor]];
            [self addSubview:_workaroundView];
        }
        if (@available(macOS 12.0, *)) {
            _notchMask = [[iTermLayerBackedSolidColorView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0) color:[NSColor blackColor]];
            _notchMask.hidden = YES;
            [self addSubview:_notchMask];
        }
    }
    return self;
}

- (void)dealloc {
    _tabBarControl.itermTabBarDelegate = nil;
    _tabBarControl.delegate = nil;
    _leftTabBarDragHandle.delegate = nil;
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
    return 6;
}

- (CGFloat)strideForWindowButtons {
    return 20;
}

- (NSEdgeInsets)insetsForStoplightHotbox {
    if (![self.delegate enableStoplightHotbox]) {
        NSEdgeInsets insets = NSEdgeInsetsZero;
        const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        insets.bottom = -[self.delegate rootTerminalViewStoplightButtonsOffset:self];
        switch (preferredStyle) {
            case TAB_STYLE_MINIMAL:
                insets.left = insets.right = MAX(0, -insets.bottom);
                break;
            case TAB_STYLE_COMPACT:
                insets.left = insets.right = 0;
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
    return [self retinaRoundRect:frame];
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
    NSRect rect = NSMakeRect(NSMaxX(standardButtonsFrame) + iTermRootTerminalViewWindowNumberLabelMargin,
                             myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset - shift,
                             iTermRootTerminalViewWindowNumberLabelWidth,
                             windowNumberHeight);
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
    CGFloat y;
    if (hasSubtitle) {
        y = [self retinaRound:myHeight - (tabBarHeight - fittingSize.height) / 2.0 - ceil(fittingSize.height)];
    } else {
        y = [self retinaRound:myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset];
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
    [self layoutSubviews];
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

- (void)updateTitleAndBorderViews NS_AVAILABLE_MAC(10_14) {
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
    } else {
        [_titleBackgroundView removeFromSuperview];
    }

    [self updateBorderViews];
}

- (void)updateBorderViews NS_AVAILABLE_MAC(10_14) {
    const BOOL haveLeft = self.delegate.haveLeftBorder;
    const BOOL haveTop = self.delegate.haveTopBorder;
    const BOOL haveRight = self.delegate.haveRightBorderRegardlessOfScrollBar;
    const BOOL haveBottom = self.delegate.haveBottomBorder;
    const BOOL fullThickness = self.effectiveAppearance.it_isDark || (self.window.backingScaleFactor <= 1);
    const CGFloat radius = iTermWindowBorderRadius;
    {
        const CGFloat top = self.bounds.size.height - radius;
        const CGFloat right = self.bounds.size.width - radius;
        const CGFloat bottom = 0;
        
        _topLeftCornerHalfRoundImageView.frame = NSMakeRect(0, top, radius, radius);
        _topRightCornerHalfRoundImageView.frame = NSMakeRect(right, top, radius, radius);
        _bottomLeftCornerHalfRoundImageView.frame = NSMakeRect(0, bottom, radius, radius);
        _bottomRightCornerHalfRoundImageView.frame = NSMakeRect(right, bottom, radius, radius);

        _topLeftCornerFullRoundImageView.frame = NSMakeRect(0, top, radius, radius);
        _topRightCornerFullRoundImageView.frame = NSMakeRect(right, top, radius, radius);
        _bottomLeftCornerFullRoundImageView.frame = NSMakeRect(0, bottom, radius, radius);
        _bottomRightCornerFullRoundImageView.frame = NSMakeRect(right, bottom, radius, radius);
    }
    
    {
        _leftBorderView.hidden = !haveLeft;
        _rightBorderView.hidden = !haveRight;
        _topBorderView.hidden = !haveTop;
        _bottomBorderView.hidden = !haveBottom;

        const CGFloat topInset = haveTop ? radius : 0;
        const CGFloat bottomInset = haveBottom ? radius : 0;
        const CGFloat leftInset = haveLeft ? radius : 0;
        const CGFloat rightInset = haveRight ? radius : 0;

        const CGFloat thickness = fullThickness ? 1 : 0.5;
        _leftBorderView.frame = NSMakeRect(0,
                                         bottomInset,
                                         thickness,
                                         self.bounds.size.height - topInset - bottomInset);
        
        _rightBorderView.frame = NSMakeRect(self.bounds.size.width - thickness,
                                          bottomInset,
                                          thickness,
                                          self.bounds.size.height - topInset - bottomInset);
        _bottomBorderView.frame = NSMakeRect(leftInset,
                                            0,
                                            self.bounds.size.width - leftInset - rightInset,
                                            thickness);
        
        _topBorderView.frame = NSMakeRect(leftInset,
                                         self.bounds.size.height - thickness,
                                         self.bounds.size.width - leftInset - rightInset,
                                         thickness);
    }

    _bottomLeftCornerHalfRoundImageView.hidden = !(haveLeft && haveBottom && !fullThickness);
    _bottomRightCornerHalfRoundImageView.hidden = !(haveRight && haveBottom && !fullThickness);
    _topLeftCornerHalfRoundImageView.hidden = !(haveLeft && haveTop && !fullThickness);
    _topRightCornerHalfRoundImageView.hidden = !(haveRight && haveTop && !fullThickness);

    _bottomLeftCornerFullRoundImageView.hidden = !(haveLeft && haveBottom && fullThickness);
    _bottomRightCornerFullRoundImageView.hidden = !(haveRight && haveBottom && fullThickness);
    _topLeftCornerFullRoundImageView.hidden = !(haveLeft && haveTop && fullThickness);
    _topRightCornerFullRoundImageView.hidden = !(haveRight && haveTop && fullThickness);
}

- (void)setUseMetal:(BOOL)useMetal {
    if (useMetal == _useMetal) {
        return;
    }
    _useMetal = useMetal;
    self.tabView.drawsBackground = NO;
    if (@available(macOS 10.15, *)) { } else {
        if (useMetal) {
            self.wantsLayer = YES;
            self.layer = [[CALayer alloc] init];
        } else {
            self.wantsLayer = NO;
            self.layer = nil;
        }
    }
    [self updateTitleAndBorderViews];

    [_divisionView removeFromSuperview];
    _divisionView = nil;

    [self updateDivisionViewAndWindowNumberLabel];
}

- (void)viewDidChangeEffectiveAppearance NS_AVAILABLE_MAC(10_14) {
    // This can be called from within -[NSWindow setStyleMask:]
    dispatch_async(dispatch_get_main_queue(), ^{
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
}

- (void)setSubtitle:(NSString *)subtitle {
    [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle
                             subtitle:subtitle
                                 icon:_windowTitleLabel.windowIcon];
}

- (void)setWindowTitleLabelToString:(NSString *)title subtitle:(NSString *)subtitle icon:(NSImage *)icon {
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
    DLog(@"Borrow tabbar control");
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
    DLog(@"Return tabbar control");
    assert(_tabBarControlOnLoan);
    _tabBarControlOnLoan = NO;
    [_tabBarBacking addSubview:tabBarControl];
    _tabBarControl.frame = _tabBarBacking.bounds;
    _tabBarControl = tabBarControl;
    [self.tabBarControl updateFlashing];
    _tabBarBacking.hidden = NO;
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
            Class theClass = _useMetal ? [iTermLayerBackedSolidColorView class] : [SolidColorView class];
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

    _windowNumberLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForWindowNumber];
    _windowTitleLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForTitle];
    if (_windowTitleLabel.windowIcon) {
        [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle
                                 subtitle:_windowTitleLabel.subtitle
                                     icon:_windowTitleLabel.windowIcon];
    }
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
    CGFloat width = floor(_toolbeltWidth);
    CGFloat top = [self topBorderInset] + [self notchInset];
    CGFloat bottom = [self bottomBorderInset];
    CGFloat right = [self rightBorderInset];
    NSRect toolbeltFrame = NSMakeRect(self.bounds.size.width - width - right,
                                      bottom,
                                      width,
                                      self.bounds.size.height - top - bottom);
    if ([self shouldLeaveEmptyAreaAtTop]) {
        toolbeltFrame.size.height -= _tabBarControl.height;
    }

    return [self tabViewFrameByShrinkingForFullScreenTabBar:toolbeltFrame
                                                     window:thisWindow];
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

- (CGFloat)tabviewWidth {
    assert([iTermPreferences intForKey:kPreferenceKeyTabPosition] != PSMTab_LeftTab ||
           ![self tabBarShouldBeVisible]);

    CGFloat width;
    if (self.shouldShowToolbelt && !_delegate.exitingLionFullscreen) {
        width = _delegate.window.frame.size.width - floor(self.toolbeltWidth);
    } else {
        width = _delegate.window.frame.size.width;
    }
    width -= [self leftBorderInset] + [self rightBorderInset];
    return width;
}

- (void)removeLeftTabBarDragHandle {
    [self.leftTabBarDragHandle removeFromSuperview];
    self.leftTabBarDragHandle = nil;
}

- (void)updateWindowNumberFont {
    if ([self tabBarShouldBeVisible]) {
        if (@available(macOS 10.16, *)) {
            _windowNumberLabel.font = [NSFont titleBarFontOfSize:[NSFont smallSystemFontSize]];
        } else {
            _windowNumberLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        }
    } else {
        if (@available(macOS 10.16, *)) {
            _windowNumberLabel.font = [NSFont titleBarFontOfSize:[NSFont systemFontSize]];
        } else {
            _windowNumberLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        }
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

- (CGFloat)leftBorderInset {
    return 0;
}

- (CGFloat)rightBorderInset {
    return 0;
}

- (CGFloat)bottomBorderInset {
    return 0;
}

- (CGFloat)topBorderInset {
    return 0;
}

- (CGFloat)notchInset {
    if (![_delegate fullScreen]) {
        return 0;
    }
    const CGFloat fakeHeight = [iTermAdvancedSettingsModel fakeNotchHeight];
    if (fakeHeight > 0) {
        return fakeHeight;
    }
    if (@available(macOS 12, *)) {
        // self.safeAreaInsets is all 0s on a notch Mac. Why the hell doesn't anything work right?
        const NSEdgeInsets safeAreaInsets = self.window.screen.safeAreaInsets;
        return safeAreaInsets.top;
    }
    return 0;
}

- (void)layoutSubviewsWithHiddenTabBarForWindow:(NSWindow *)thisWindow {
    if (!_tabBarControlOnLoan) {
        self.tabBarControl.hidden = YES;
    }
    if ([self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        [self layoutSubviewsTopTabBarVisible:NO forWindow:thisWindow];
        return;
    }

    [self removeLeftTabBarDragHandle];
    iTermDecorationHeights decorationHeights = {
        .bottom = [self bottomBorderInset],
        .top = (_delegate.divisionViewShouldBeVisible ? kDivisionViewHeight : 0) + [self notchInset]
    };
    decorationHeights.top += [self topBorderInset];
    if ([self shouldLeaveEmptyAreaAtTop]) {
        DLog(@"Add tabbar control height to decoration height to leave an empty area at the top.");
        decorationHeights.top += _tabBarControl.height;
    } else {
        DLog(@"Not leaving an empty area on top");
    }
    const NSRect frame = NSMakeRect([self leftBorderInset],
                                    decorationHeights.bottom,
                                    [self tabviewWidth],
                                    [[thisWindow contentView] frame].size.height - decorationHeights.top - decorationHeights.bottom);
    [self layoutStatusBar:&decorationHeights window:thisWindow frame:frame];
    NSRect tabViewFrame =
        NSMakeRect([self leftBorderInset],
                   decorationHeights.bottom,
                   [self tabviewWidth],
                   [[thisWindow contentView] frame].size.height - decorationHeights.top - decorationHeights.bottom);
    if ([self tabBarShouldBeVisibleEvenWhenOnLoan]) {
        tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:tabViewFrame
                                                                 window:thisWindow];
    }
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(tabViewFrame));
    [self.tabView setFrame:tabViewFrame];
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
    [self removeLeftTabBarDragHandle];
    iTermDecorationHeights decorationHeights = {
        .bottom = [self bottomBorderInset],
        .top = [self notchInset]
    };
    if (!_tabBarControlOnLoan) {
        if (!self.tabBarControl.flashing) {
            decorationHeights.top += _tabBarControl.height;
        }
    }
    if (![self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        decorationHeights.top += [self topBorderInset];
    }
    if (_delegate.divisionViewShouldBeVisible) {
        decorationHeights.top += kDivisionViewHeight;
    }
    const NSRect frame = NSMakeRect([self leftBorderInset],
                                    decorationHeights.bottom,
                                    [self tabviewWidth],
                                    [[thisWindow contentView] frame].size.height - decorationHeights.bottom - decorationHeights.top);
    iTermDecorationHeights temp = decorationHeights;
    [self layoutStatusBar:&temp window:thisWindow frame:frame];

    NSRect tabViewFrame = NSMakeRect([self leftBorderInset],
                                     temp.bottom,
                                     [self tabviewWidth],
                                     [[thisWindow contentView] frame].size.height - temp.bottom - temp.top);
    tabViewFrame = [self tabViewFrameByShrinkingForFullScreenTabBar:tabViewFrame
                                                             window:thisWindow];
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(tabViewFrame));
    [self.tabView setFrame:tabViewFrame];

    CGFloat tabBarOffset = 0;
    if (!_tabBarControlOnLoan && self.tabBarControl.flashing) {
        tabBarOffset = _tabBarControl.height;
    }
    NSRect tabBarFrame = NSMakeRect(tabViewFrame.origin.x,
                                    NSMaxY(frame) - tabBarOffset,
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
    assert(!_tabBarControlOnLoan);
    _tabBarBacking.frame = frame;
    self.tabBarControl.frame = _tabBarBacking.bounds;
}

- (void)layoutSubviewsWithVisibleBottomTabBarForWindow:(NSWindow *)thisWindow {
    assert(!_tabBarControlOnLoan);
    DLog(@"repositionWidgets - putting tabs at bottom");
    [self removeLeftTabBarDragHandle];
    // setup aRect to make room for the tabs at the bottom.
    NSRect tabBarFrame = NSMakeRect([self leftBorderInset],
                                    [self bottomBorderInset],
                                    [self tabviewWidth],
                                    _tabBarControl.height);
    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    iTermDecorationHeights decorationHeights = {
        .top = [self notchInset],
        .bottom = tabBarFrame.origin.y
    };
    decorationHeights.top += [self topBorderInset];
    if (_delegate.divisionViewShouldBeVisible) {
        decorationHeights.top += kDivisionViewHeight;
    }
    if (!self.tabBarControl.flashing) {
        decorationHeights.bottom += _tabBarControl.height;
    }
    NSRect frame = NSMakeRect(tabBarFrame.origin.x,
                              decorationHeights.bottom,
                              tabBarFrame.size.width,
                              [thisWindow.contentView frame].size.height - decorationHeights.top - decorationHeights.bottom);
    [self layoutStatusBar:&decorationHeights window:thisWindow frame:frame];
    NSRect tabViewFrame = NSMakeRect(tabBarFrame.origin.x,
                                     decorationHeights.bottom,
                                     tabBarFrame.size.width,
                                     [thisWindow.contentView frame].size.height - decorationHeights.top - decorationHeights.bottom);
    DLog(@"repositionWidgets - Set tab view frame to %@", NSStringFromRect(tabViewFrame));
    self.tabView.frame = [self tabViewFrameByShrinkingForFullScreenTabBar:tabViewFrame
                                                                   window:thisWindow];
    [self updateDivisionViewAndWindowNumberLabel];
}

- (NSRect)tabViewFrameByShrinkingForFullScreenTabBar:(NSRect)frame
                                              window:(NSWindow *)thisWindow {
    if (!thisWindow) {
        return frame;
    }
    if ((thisWindow.styleMask & NSWindowStyleMaskFullSizeContentView) != NSWindowStyleMaskFullSizeContentView) {
        return frame;
    }
    if (![self tabBarShouldBeVisible]) {
        return frame;
    }
    if (![self.delegate enteringLionFullscreen] &&
        !(thisWindow.styleMask & NSWindowStyleMaskFullScreen)) {
        return frame;
    }
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_TopTab:
            if (self.tabBarControl.flashing) {
                // Overlaps content
                return frame;
            }
            if (!_tabBarControlOnLoan && !self.tabBarControl.flashing) {
                // Already accounted for this before calling this function.
                return frame;
            }
            break;
        case PSMTab_LeftTab:
        case PSMTab_BottomTab:
            return frame;
    }
    NSRect tabViewFrame = frame;
    const CGFloat offset = _tabBarControl.height;
    tabViewFrame.size.height -= offset;
    return tabViewFrame;
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
    iTermDecorationHeights decorationHeights = {
        .top = [self notchInset],
        .bottom = 0
    };
    decorationHeights.bottom += [self bottomBorderInset];
    decorationHeights.top += [self topBorderInset];
    if (_delegate.divisionViewShouldBeVisible) {
        decorationHeights.top += kDivisionViewHeight;
    }
    NSRect tabBarFrame = NSMakeRect([self leftBorderInset],
                                    decorationHeights.bottom,
                                    _leftTabBarWidth,
                                    [thisWindow.contentView frame].size.height - decorationHeights.bottom - decorationHeights.top);
    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMaxXMargin)];

    // Can't have a left border.
    CGFloat widthAdjustment = [self rightBorderInset];
    CGFloat xOffset = 0;
    if (self.tabBarControl.flashing) {
        xOffset = -NSMaxX(tabBarFrame);
        widthAdjustment -= NSWidth(tabBarFrame);
    }
    if (self.shouldShowToolbelt) {
        widthAdjustment += floor(self.toolbeltWidth);
    }
    const NSRect frame = NSMakeRect(NSMaxX(tabBarFrame) + xOffset,
                                    decorationHeights.bottom,
                                    [thisWindow.contentView frame].size.width - NSWidth(tabBarFrame) - widthAdjustment,
                                    [thisWindow.contentView frame].size.height - decorationHeights.bottom - decorationHeights.top);
    [self layoutStatusBar:&decorationHeights window:thisWindow frame:frame];
    NSRect tabViewFrame = NSMakeRect(NSMaxX(tabBarFrame) + xOffset,
                                     decorationHeights.bottom,
                                     [thisWindow.contentView frame].size.width - NSWidth(tabBarFrame) - widthAdjustment,
                                     [thisWindow.contentView frame].size.height - decorationHeights.bottom - decorationHeights.top);
    self.tabView.frame = [self tabViewFrameByShrinkingForFullScreenTabBar:tabViewFrame
                                                                   window:thisWindow];
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

- (void)layoutWindowPaneDecorations {
    _windowNumberLabel.textColor = [_delegate rootTerminalViewTabBarTextColorForWindowNumber];
    _windowTitleLabel.textColor = [self.delegate rootTerminalViewTabBarTextColorForTitle];
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
    _standardWindowButtonsView.frame = [self frameForStandardWindowButtons];
    [self updateTitleAndBorderViews];
}

- (void)layoutSubviews {
    DLog(@"Before:\n%@", [self iterm_recursiveDescription]);
    [self.delegate rootTerminalViewWillLayoutSubviews];

    if (@available(macOS 10.15, *)) { } else {
        _workaroundView.frame = NSMakeRect(0, self.bounds.size.height - 1, 1, 1);
    }
    const BOOL showToolbeltInline = self.shouldShowToolbelt;
    NSWindow *thisWindow = _delegate.window;
    if (!_tabBarControlOnLoan) {
        self.tabBarControl.height = [_delegate rootTerminalViewHeightOfTabBar:self];
    }

    _backgroundImage.frame = self.bounds;
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
    if (@available(macOS 12.0, *)) {
        const CGFloat notchHeight = [self notchInset];
        _notchMask.hidden = (notchHeight == 0);
        _notchMask.frame = NSMakeRect(0, NSHeight(self.bounds) - notchHeight, NSWidth(self.bounds), notchHeight);
    }

    if (showToolbeltInline) {
        [self updateToolbeltFrameForWindow:thisWindow];
    }

    // Update the tab style.
    [self.tabBarControl setDisableTabClose:YES];
    if ([iTermPreferences boolForKey:kPreferenceKeyHideTabNumber]) {
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
    DLog(@"After:\n%@", [self iterm_recursiveDescription]);
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
    const CGFloat maximumWidth = MAX(1, contentWidth - [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2 - 10);
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

- (BOOL)iTermTabBarShouldHideBacking {
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle != TAB_STYLE_MINIMAL) {
        return YES;
    }
    BOOL isTop = NO;
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_BottomTab:
        case PSMTab_LeftTab:
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

// For the left-side tab bar.
- (CGFloat)dragHandleView:(iTermDragHandleView *)dragHandle didMoveBy:(CGFloat)delta {
    CGFloat originalValue = _leftTabBarPreferredWidth;
    _leftTabBarPreferredWidth = round([self leftTabBarWidthForPreferredWidth:_leftTabBarPreferredWidth + delta]);
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

- (BOOL)shouldRevealHotbox {
    if ([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagCommand) {
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

#pragma mark - iTermGenericStatusBarContainer

- (NSColor *)genericStatusBarContainerBackgroundColor {
    return [self.delegate rootTerminalViewTabBarBackgroundColorIgnoringTabColor:YES];
}

@end

BOOL PSMShouldExtendTransparencyIntoMinimalTabBar(void) {
    if (@available(macOS 10.16, *)) { } else {
        return NO;
    }
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
