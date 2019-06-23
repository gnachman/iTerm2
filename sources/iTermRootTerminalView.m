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
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "PTYTabView.h"
#import "PTYWindow.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermDragHandleView.h"
#import "iTermGenericStatusBarContainer.h"
#import "iTermPreferences.h"
#import "iTermStandardWindowButtonsView.h"
#import "iTermStatusBarViewController.h"
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

@interface iTermTabBarBacking : NSVisualEffectView<iTermTabBarControlViewContainer>
@property (nonatomic) BOOL hidesWhenTabBarHidden;
@end

@implementation iTermTabBarBacking

- (void)tabBarControlViewWillHide:(BOOL)hidden {
    if (_hidesWhenTabBarHidden || !hidden) {
        [self setHidden:hidden];
    }
}

@end

@interface iTermFakeWindowTitleLabel : NSTextField
@property (nonatomic, copy) NSString *windowTitle;
@property (nonatomic, strong) NSImage *windowIcon;
@end

@implementation iTermFakeWindowTitleLabel
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
            _tabBarBacking = [[iTermTabBarBacking alloc] init];
            _tabBarBacking.hidesWhenTabBarHidden = [delegate rootTerminalViewShouldHideTabBarBackingWhenTabBarIsHidden];
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
        _windowNumberLabel.alphaValue = 0.75;
        _windowNumberLabel.hidden = YES;
        _windowNumberLabel.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);
        [self addSubview:_windowNumberLabel];

        _windowTitleLabel = [iTermFakeWindowTitleLabel newLabelStyledTextField];
        _windowTitleLabel.alphaValue = 1;
        _windowTitleLabel.alignment = NSTextAlignmentCenter;
        _windowTitleLabel.hidden = YES;
        _windowTitleLabel.autoresizingMask = (NSViewMinYMargin | NSViewWidthSizable);
        [self addSubview:_windowTitleLabel];
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
    if (!_tabBarControlOnLoan && !_windowNumberLabel.hidden && view == _windowNumberLabel) {
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
            NSString *doubleClickAction = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleActionOnDoubleClick"];
            if ([doubleClickAction isEqualToString:@"Minimize"]) {
                [self.window performMiniaturize:nil];
                return;
            }
            if ([doubleClickAction isEqualToString:@"Maximize"]) {
                [self.window performZoom:nil];
                return;
            }
        }
    }
    [super mouseUp:event];
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
    if (_tabBarControlOnLoan) {
        return NSZeroRect;
    }
    const CGFloat tabBarHeight = _tabBarControl.height;
    const CGFloat baselineOffset = -_windowTitleLabel.font.descender;
    const CGFloat capHeight = _windowTitleLabel.font.capHeight;
    const CGFloat myHeight = self.frame.size.height;
    const NSEdgeInsets insets = [self.delegate tabBarInsets];
    const CGFloat sideInset = MAX(MAX(insets.left, insets.right), iTermRootTerminalViewWindowNumberLabelMargin);
    NSRect rect = NSMakeRect([self retinaRound:sideInset],
                             [self retinaRound:myHeight - tabBarHeight + (tabBarHeight - capHeight) / 2.0 - baselineOffset],
                             ceil(MAX(0, self.frame.size.width - sideInset * 2)),
                             ceil(_windowTitleLabel.frame.size.height));
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
        for (int i = 0; i < self.numberOfWindowButtons; i++) {
            [[self.window standardWindowButton:self.windowButtonTypes[i]] setHidden:NO];
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
        x += stride;
        dispatch_async(dispatch_get_main_queue(), ^{
            [button setNeedsDisplay];
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

- (void)drawRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        if ([_delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
            // Draw background color for fake title bar.
            NSColor *const backgroundColor = [_delegate rootTerminalViewTabBarBackgroundColor];
            const CGFloat height = [_delegate rootTerminalViewHeightOfTabBar:self];
            [backgroundColor set];
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
        const BOOL haveRight = self.delegate.haveRightBorderRegardlessOfScrollBar;
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
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:title ?: @""
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
        _windowTitleLabel.stringValue = title ?: @"";
    }
    _windowTitleLabel.windowTitle = title;
    _windowTitleLabel.windowIcon = icon;
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
        [_tabBarControl removeFromSuperview];
        // Fix size in case we just went from left-of to top-of since it's now going full-width.
        [self.tabBarControl setTabLocation:[iTermPreferences intForKey:kPreferenceKeyTabPosition]];
        const CGFloat desiredHeight = [self.delegate rootTerminalViewHeightOfTabBar:self];
        _tabBarControl.height = desiredHeight;
        _tabBarControl.frame = NSMakeRect(0, 0, _tabBarControl.frame.size.width, desiredHeight);
        _tabBarControl.hidden = NO;
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
            divisionViewFrame.origin.y += iTermStatusBarHeight;
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
                if (@available(macOS 10.14, *)) {
                    _divisionView.color = (self.window.isKeyWindow
                                           ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.70 alpha:1]
                                           : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.86 alpha:1]);
                } else {
                    _divisionView.color = (self.window.isKeyWindow
                                           ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.49 alpha:1]
                                           : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.65 alpha:1]);
                }
                break;

            case TAB_STYLE_DARK:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
                if (@available(macOS 10.14, *)) {
                    _divisionView.color = (self.window.isKeyWindow
                                           ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.1 alpha:1]
                                           : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.07 alpha:1]);
                } else {
                    _divisionView.color = (self.window.isKeyWindow
                                           ? [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.2 alpha:1]
                                           : [NSColor colorWithCalibratedHue:1 saturation:0 brightness:0.15 alpha:1]);
                }
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
        [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle icon:_windowTitleLabel.windowIcon];
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
    CGFloat top = [_delegate haveTopBorder] ? 1 : 0;
    CGFloat bottom = [_delegate haveBottomBorder] ? 1 : 0;
    CGFloat right = [_delegate haveRightBorder] ? 1 : 0;
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
        return NO;
    }
    return [self tabBarShouldBeVisibleEvenWhenOnLoan];
}

- (BOOL)tabBarShouldBeVisibleEvenWhenOnLoan {
    if (self.tabBarControl.flashing) {
        return YES;
    } else {
        return [self tabBarShouldBeVisibleWithAdditionalTabs:0];
    }
}

- (BOOL)tabBarShouldBeVisibleWithAdditionalTabs:(int)numberOfAdditionalTabs {
    if (([_delegate anyFullScreen] || [_delegate enteringLionFullscreen]) &&
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
    if ([self tabBarShouldBeVisible]) {
        _windowNumberLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    } else {
        _windowNumberLabel.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
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
        }
    }
}

- (BOOL)shouldLeaveEmptyAreaAtTop {
    return (_tabBarControlOnLoan &&
            [self tabBarShouldBeVisibleWithAdditionalTabs:0] &&
            [self.delegate rootTerminalViewShouldLeaveEmptyAreaAtTop]);
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
        .bottom = [_delegate haveBottomBorder] ? 1 : 0,
        .top = _delegate.divisionViewShouldBeVisible ? kDivisionViewHeight : 0
    };
    if ([_delegate haveTopBorder]) {
        decorationHeights.top++;
    }
    if ([self shouldLeaveEmptyAreaAtTop]) {
        decorationHeights.top += _tabBarControl.height;
    }
    const NSRect frame = NSMakeRect([_delegate haveLeftBorder] ? 1 : 0,
                                    decorationHeights.bottom,
                                    [self tabviewWidth],
                                    [[thisWindow contentView] frame].size.height - decorationHeights.top - decorationHeights.bottom);
    [self layoutStatusBar:&decorationHeights window:thisWindow frame:frame];
    NSRect tabViewFrame =
        NSMakeRect([_delegate haveLeftBorder] ? 1 : 0,
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
        .bottom = _delegate.haveBottomBorder ? 1 : 0,
        .top = 0
    };
    if (!_tabBarControlOnLoan) {
        if (!self.tabBarControl.flashing) {
            decorationHeights.top += _tabBarControl.height;
        }
    }
    if (_delegate.haveTopBorder && ![self.delegate rootTerminalViewShouldDrawWindowTitleInPlaceOfTabBar]) {
        decorationHeights.top += 1;
    }
    if (_delegate.divisionViewShouldBeVisible) {
        decorationHeights.top += kDivisionViewHeight;
    }
    const NSRect frame = NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
                                    decorationHeights.bottom,
                                    [self tabviewWidth],
                                    [[thisWindow contentView] frame].size.height - decorationHeights.bottom - decorationHeights.top);
    iTermDecorationHeights temp = decorationHeights;
    [self layoutStatusBar:&temp window:thisWindow frame:frame];

    NSRect tabViewFrame = NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
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
    iTermDecorationHeights decorationHeights = {
        .top = 0,
        .bottom = tabBarFrame.origin.y
    };
    if (_delegate.haveTopBorder) {
        decorationHeights.top += 1;
    }
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
    if (@available(macOS 10.14, *)) {} else {
        return frame;
    }
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
    iTermDecorationHeights decorationHeights = {
        .top = 0,
        .bottom = 0
    };
    if (_delegate.haveBottomBorder) {
        decorationHeights.bottom += 1;
    }
    if (_delegate.haveTopBorder) {
        decorationHeights.top += 1;
    }
    if (_delegate.divisionViewShouldBeVisible) {
        decorationHeights.top += kDivisionViewHeight;
    }
    NSRect tabBarFrame = NSMakeRect(_delegate.haveLeftBorder ? 1 : 0,
                                    decorationHeights.bottom,
                                    [self tabviewWidth],
                                    [thisWindow.contentView frame].size.height - decorationHeights.bottom - decorationHeights.top);
    self.tabBarControl.insets = [self.delegate tabBarInsets];
    [self setTabBarFrame:tabBarFrame];
    [self setTabBarControlAutoresizingMask:(NSViewHeightSizable | NSViewMaxXMargin)];

    CGFloat widthAdjustment = 0;
    // Can't have a left border.
    if (_delegate.haveRightBorder) {
        widthAdjustment += 1;
    }
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
        [self setWindowTitleLabelToString:_windowTitleLabel.windowTitle icon:_windowTitleLabel.windowIcon];
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
}

- (void)layoutSubviews {
    DLog(@"layoutSubviews");

    const BOOL showToolbeltInline = self.shouldShowToolbelt;
    NSWindow *thisWindow = _delegate.window;
    if (!_tabBarControlOnLoan) {
        self.tabBarControl.height = [_delegate rootTerminalViewHeightOfTabBar:self];
    }

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
    DLog(@"repositionWidgets - return.");
}

- (CGFloat)leftTabBarWidthForPreferredWidth:(CGFloat)preferredWidth contentWidth:(CGFloat)contentWidth {
    const CGFloat minimumWidth = 50;
    const CGFloat maximumWidth = round(contentWidth / 3);
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
    const CGFloat maximumWidth = round(self.bounds.size.width / 2);
    _leftTabBarWidth = MAX(MIN(maximumWidth, _leftTabBarPreferredWidth), minimumWidth);
}

#pragma mark - Status Bar Layout

- (NSRect)frameForStatusBarInContainingFrame:(NSRect)containingFrame {
    switch ([iTermPreferences boolForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            return NSMakeRect(NSMinX(containingFrame),
                              NSMaxY(containingFrame) - iTermStatusBarHeight,
                              NSWidth(containingFrame),
                              iTermStatusBarHeight);

        case iTermStatusBarPositionBottom:
            return NSMakeRect(NSMinX(containingFrame),
                              NSMinY(containingFrame),
                              NSWidth(containingFrame),
                              iTermStatusBarHeight);
    }
    return NSZeroRect;
}

- (NSAutoresizingMaskOptions)statusBarContainerAutoresizingMask {
    switch ([iTermPreferences boolForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            return NSViewWidthSizable | NSViewMinYMargin;

        case iTermStatusBarPositionBottom:
            return NSViewWidthSizable | NSViewMaxYMargin;
    }

    return NSViewWidthSizable | NSViewMinYMargin;
}

- (void)updateDecorationHeightsForStatusBar:(iTermDecorationHeights *)decorationHeights {
    switch ([iTermPreferences boolForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop: {
            decorationHeights->top += iTermStatusBarHeight;
            break;
        }
        case iTermStatusBarPositionBottom:
            decorationHeights->bottom += iTermStatusBarHeight;
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
    if (@available(macOS 10.14, *)) {} else {
        return YES;
    }
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (preferredStyle != TAB_STYLE_MINIMAL) {
        return YES;
    }
    switch ([iTermPreferences intForKey:kPreferenceKeyTabPosition]) {
        case PSMTab_BottomTab:
        case PSMTab_LeftTab:
            return YES;

        case PSMTab_TopTab:
            break;
    }
    if ([_delegate lionFullScreen] || [_delegate enteringLionFullscreen]) {
        return NO;
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

- (BOOL)stoplightHotboxMouseEnter {
    if ([[NSApp currentEvent] it_modifierFlags] & NSEventModifierFlagCommand) {
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
    return [self.delegate rootTerminalViewTabBarBackgroundColor];
}

@end
