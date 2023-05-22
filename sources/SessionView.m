#import "SessionView.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermBackgroundColorView.h"
#import "iTermDropDownFindViewController.h"
#import "iTermFindDriver.h"
#import "iTermFindPasteboard.h"
#import "iTermGenericStatusBarContainer.h"
#import "iTermImageView.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermMetalClipView.h"
#import "iTermMetalDeviceProvider.h"
#import "iTermPreferences.h"
#import "iTermSearchResultsMinimapView.h"
#import "iTermStatusBarContainerView.h"
#import "iTermStatusBarLayout.h"
#import "iTermStatusBarSearchFieldComponent.h"
#import "iTermStatusBarViewController.h"
#import "iTermTheme.h"
#import "iTermUnobtrusiveMessage.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSTimer+iTerm.h"
#import "NSView+iTerm.h"
#import "NSView+RecursiveDescription.h"
#import "MovePaneController.h"
#import "NSResponder+iTerm.h"
#import "PSMMinimalTabStyle.h"
#import "PSMTabDragAssistant.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "PTYWindow.h"
#import "SessionTitleView.h"
#import "SplitSelectionView.h"

#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>

static int nextViewId;

static const CGFloat iTermGetSessionViewTitleHeight(void) {
    return iTermGetStatusBarHeight() + 1;
}

// Last time any window was resized TODO(georgen):it would be better to track per window.
static NSDate* lastResizeDate_;

NSString *const SessionViewWasSelectedForInspectionNotification = @"SessionViewWasSelectedForInspectionNotification";

@interface iTermMTKView : MTKView
@end

@implementation iTermMTKView {
    NSTimer *_timer;
    NSTimeInterval _lastSetNeedsDisplay;
}

- (nonnull instancetype)initWithFrame:(CGRect)frameRect device:(nullable id<MTLDevice>)device {
    self = [super initWithFrame:frameRect device:device];
    if (self) {
        if (![iTermAdvancedSettingsModel hdrCursor]) {
            self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        }
        [self it_schedule];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)it_schedule {
    _timer = [NSTimer scheduledWeakTimerWithTimeInterval:[iTermAdvancedSettingsModel metalRedrawPeriod]
                                                  target:self
                                                selector:@selector(it_redrawPeriodically:)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)it_redrawPeriodically:(NSTimer *)timer {
    DLog(@"redrawPeriodically: timer fired");
    if (self.isHidden || self.alphaValue < 0.01 || self.bounds.size.width == 0 || self.bounds.size.height == 0) {
        DLog(@"Not visible %@", self);
        return;
    }
    if (round(1000 * timer.timeInterval) != round(1000 * [iTermAdvancedSettingsModel metalRedrawPeriod]))  {
        DLog(@"Recreate timer");
        [_timer invalidate];
        [self it_schedule];
    }
    if ([NSDate it_timeSinceBoot] - _lastSetNeedsDisplay < timer.timeInterval) {
        DLog(@"Redrew recently");
        return;
    }
    [self setNeedsDisplay:YES];
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    DLog(@"setNeedsDisplay:%@", @(needsDisplay));
    if (needsDisplay) {
        _lastSetNeedsDisplay = [NSDate it_timeSinceBoot];
    }
    [super setNeedsDisplay:needsDisplay];
}

- (void)viewDidMoveToWindow {
    self.colorspace = self.window.screen.colorSpace.CGColorSpace;
}

- (void)enclosingWindowDidMoveToScreen:(NSScreen *)screen {
    self.colorspace = self.window.screen.colorSpace.CGColorSpace;
}

- (void)setColorspace:(CGColorSpaceRef)colorspace {
    DLog(@"set colorspace of %@ to %@", self, colorspace);
    [super setColorspace:colorspace];
}
@end

@interface iTermHoverContainerView : NSView
@property (nonatomic, copy) NSString *url;
@end

@implementation iTermHoverContainerView {
    NSVisualEffectView *_vev NS_AVAILABLE_MAC(10_14);
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        const CGFloat radius = 4;
        _vev = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        _vev.wantsLayer = YES;
        _vev.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        _vev.material = NSVisualEffectMaterialSheet;
        _vev.state = NSVisualEffectStateActive;
        _vev.layer.cornerRadius = radius;
        _vev.layer.borderWidth = 1;
        _vev.layer.borderColor = [[self desiredBorderColor] CGColor];
        [self addSubview:_vev positioned:NSWindowBelow relativeTo:self.subviews.firstObject];
        _vev.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
        self.autoresizesSubviews = YES;
    }
    return self;
}

- (void)viewDidChangeEffectiveAppearance {
    _vev.layer.borderColor = [[self desiredBorderColor] CGColor];
}

- (NSColor *)desiredBorderColor {
    if ([self.effectiveAppearance it_isDark]) {
        return [NSColor colorWithWhite:0.9 alpha:0.25];
    } else {
        return [NSColor colorWithWhite:0 alpha:0.25];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
}

@end

@interface SessionView () <
    iTermAnnouncementDelegate,
    iTermFindDriverDelegate,
    iTermGenericStatusBarContainer,
    iTermLegacyViewDelegate,
    iTermSearchResultsMinimapViewDelegate,
    NSDraggingSource,
    PTYScrollerDelegate,
    SplitSelectionViewDelegate>
@property(nonatomic, strong) PTYScrollView *scrollview;
@end

@implementation SessionView {
    NSMutableArray *_announcements;
    BOOL _inDealloc;
    iTermAnnouncementViewController *_currentAnnouncement;

    BOOL _dim;
    BOOL _backgroundDimmed;

    // Saved size for unmaximizing.
    NSSize _savedSize;

    // When moving a pane, a view is put over all sessions to help the user
    // choose how to split the destination.
    SplitSelectionView *_splitSelectionView;

    BOOL _showTitle;
    BOOL _showBottomStatusBar;
    SessionTitleView *_title;

    iTermHoverContainerView *_hoverURLView;
    NSTextField *_hoverURLTextField;
    NSRect _urlAnchorFrame;

    BOOL _useMetal;
    iTermMetalClipView *_metalClipView;
    iTermDropDownFindViewController *_dropDownFindViewController;
    iTermFindDriver *_dropDownFindDriver;
    iTermFindDriver *_permanentStatusBarFindDriver;
    iTermFindDriver *_temporaryStatusBarFindDriver;
    iTermGenericStatusBarContainer *_genericStatusBarContainer;
    iTermImageView *_imageView NS_AVAILABLE_MAC(10_14);
    NSColor *_terminalBackgroundColor;

    // For macOS 10.14+ when subpixel AA is turned on and the scroller style is legacy, this draws
    // some blended default background color under the vertical scroller. In all other conditions
    // its frame is 0x0.
    iTermScrollerBackgroundColorView *_legacyScrollerBackgroundView;
    iTermUnobtrusiveMessage *_unobtrusiveMessage;
    iTermStatusBarFilterComponent *_temporaryFilterComponent;
}

+ (double)titleHeight {
    return iTermGetSessionViewTitleHeight();
}

+ (void)initialize {
    if (self == [SessionView self]) {
        lastResizeDate_ = [NSDate date];
    }
}

+ (void)windowDidResize {
    lastResizeDate_ = [NSDate date];
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[ iTermMovePaneDragType, @"com.iterm2.psm.controlitem" ]];
        lastResizeDate_ = [NSDate date];
        _announcements = [[NSMutableArray alloc] init];

        _imageView = [[iTermImageView alloc] init];
        _imageView.hidden = YES;
        _imageView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
        _imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_imageView];

        _backgroundColorView = [[iTermSessionBackgroundColorView alloc] init];
        _backgroundColorView.layer = [[CALayer alloc] init];
        _backgroundColorView.wantsLayer = YES;
        _backgroundColorView.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
        _backgroundColorView.layer.actions = @{@"backgroundColor": [NSNull null]};
        [self addSubview:_backgroundColorView];

        _legacyScrollerBackgroundView = [[iTermScrollerBackgroundColorView alloc] init];
        _legacyScrollerBackgroundView.layer = [[CALayer alloc] init];
        _legacyScrollerBackgroundView.wantsLayer = YES;
        _legacyScrollerBackgroundView.frame = NSMakeRect(0, 0, 0, 0);
        _legacyScrollerBackgroundView.layer.actions = @{@"backgroundColor": [NSNull null]};
        _legacyScrollerBackgroundView.hidden = YES;
        [self addSubview:_legacyScrollerBackgroundView];

        // Set up find view
        _dropDownFindViewController = [self newDropDownFindView];
        _dropDownFindDriver = [[iTermFindDriver alloc] initWithViewController:_dropDownFindViewController
                                                         filterViewController:_dropDownFindViewController];

        // Assign a globally unique view ID.
        _viewId = nextViewId++;

        // Allocate a scrollview
        NSRect aRect = self.frame;
        _scrollview = [[PTYScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                      0,
                                                                      aRect.size.width,
                                                                      aRect.size.height)
                                       hasVerticalScroller:NO];
        self.verticalScroller.ptyScrollerDelegate = self;
        [_scrollview setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        _metalClipView = [[iTermMetalClipView alloc] initWithFrame:_scrollview.contentView.frame];
        _metalClipView.metalView = _metalView;
        _scrollview.contentView = _metalClipView;
        _scrollview.drawsBackground = NO;

        _scrollview.contentView.copiesOnScroll = NO;
        // assign the main view
        [self addSubviewBelowFindView:_scrollview];

        if ([iTermAdvancedSettingsModel showLocationsInScrollbar]) {
            _searchResultsMinimap = [[iTermSearchResultsMinimapView alloc] init];
            _searchResultsMinimap.delegate = self;
            [self addSubviewBelowFindView:_searchResultsMinimap];
            iTermTuple<NSColor *, NSColor *> *(^tuple)(NSColor *) = ^iTermTuple<NSColor *, NSColor *> *(NSColor *color) {
                NSColor *saturated = [NSColor colorWithHue:color.hueComponent
                                                saturation:1
                                                brightness:1
                                                     alpha:1];
                return [iTermTuple tupleWithObject:saturated
                                         andObject:[saturated colorDimmedBy:0.2 towardsGrayLevel:1]];
            };
            // This order must match the iTermIntervalTreeObjectType enum.
            NSArray<iTermTuple<NSColor *, NSColor *> *> *colors = @[
                // Blue mark
                tuple([iTermTextDrawingHelper successMarkColor]),

                 // Yellow mark
                [iTermTuple tupleWithObject:[iTermTextDrawingHelper otherMarkColor]
                                  andObject:[[iTermTextDrawingHelper otherMarkColor] colorDimmedBy:0.2 towardsGrayLevel:1]],

                // Red mark
                tuple([iTermTextDrawingHelper errorMarkColor]),

                // Manually created mark or prompt without code
                [iTermTuple tupleWithObject:[NSColor colorWithWhite:0.5 alpha:1]
                                  andObject:[NSColor colorWithWhite:0.7 alpha:1]],

                // Annotation
                tuple([NSColor it_colorInDefaultColorSpaceWithRed:1 green:1 blue:0 alpha:1]),
            ];
            _marksMinimap = [[iTermIncrementalMinimapView alloc] initWithColors:colors];
            [self addSubviewBelowFindView:_marksMinimap];
        }

        [self installLegacyView];

#if ENABLE_LOW_POWER_GPU_DETECTION
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferredMetalDeviceDidChange:)
                                                     name:iTermMetalDeviceProviderPreferredDeviceDidChangeNotification
                                                   object:nil];
#endif
        if (PTYScrollView.shouldDismember) {
            [self addSubviewBelowFindView:_scrollview.verticalScroller];
            _scrollview.verticalScroller.frame = [self frameForScroller];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scrollerStyleDidChange:)
                                                     name:@"NSPreferredScrollerStyleDidChangeNotification"
                                                   object:nil];
    }
    return self;
}

- (void)setImage:(iTermImageWrapper *)image {
    _imageView.image = image;
    [self updateImageAndBackgroundViewVisibility];
}

- (iTermImageWrapper *)image {
    if (_imageView.hidden) {
        return nil;
    }
    return _imageView.image;
}

- (void)setImageMode:(iTermBackgroundImageMode)imageMode {
    _imageMode = imageMode;
    _imageView.contentMode = imageMode;
}

- (void)setTerminalBackgroundColor:(NSColor *)color {
    if ([NSObject object:_terminalBackgroundColor isEqualToObject:color]) {
        return;
    }
    _terminalBackgroundColor = color;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _imageView.backgroundColor = color;
    _legacyScrollerBackgroundView.backgroundColor = color;
    _backgroundColorView.backgroundColor = color;

    DLog(@"setTerminalBackgroundColor:%@ %@\n%@", color, self.delegate, [NSThread callStackSymbols]);
    if (color && _metalView.alphaValue < 1) {
        DLog(@"setTerminalBackgroundColor: Set background color view hidden=%@ because metalview is not opaque", @(!iTermTextIsMonochrome()));
        _backgroundColorView.hidden = !iTermTextIsMonochrome();
        _legacyScrollerBackgroundView.hidden = iTermTextIsMonochrome();
    } else {
        DLog(@"setTerminalBackgroundColor: Set background color view hidden=YES because bg color (%@) is nil or metalView.alphaValue (%@) == 1",
             color, @(_metalView.alphaValue));
        _backgroundColorView.hidden = YES;
        _legacyScrollerBackgroundView.hidden = YES;
    }
    [self setNeedsDisplay:YES];
    [CATransaction commit];
    [self updateMinimapAlpha];
}

- (void)setTransparencyAlpha:(CGFloat)transparencyAlpha
                       blend:(CGFloat)blend {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _backgroundColorView.transparency = 1 - transparencyAlpha;
    _backgroundColorView.blend = blend;
    if (![iTermPreferences boolForKey:kPreferenceKeyPerPaneBackgroundImage]) {
        // This is unfortunate but because I can't use an imageview behind everything when
        // subpixel AA is enabled, I have to draw *something* behind the legacy scrollers.
        // NSImageView is not equipped to do the job.
        _legacyScrollerBackgroundView.transparency = 0;
        _legacyScrollerBackgroundView.blend = 0;
    } else {
        _legacyScrollerBackgroundView.transparency = 1 - transparencyAlpha;
        _legacyScrollerBackgroundView.blend = blend;
    }
    _imageView.transparency = 1 - transparencyAlpha;
    _imageView.blend = blend;
    [CATransaction commit];
}

- (NSRect)frameForScroller NS_AVAILABLE_MAC(10_14) {
    [_scrollview.verticalScroller sizeToFit];
    NSSize size = _scrollview.verticalScroller.frame.size;
    NSSize mySize = self.bounds.size;
    NSRect frame = NSMakeRect(mySize.width - size.width, 0, size.width, mySize.height);
    return frame;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _inDealloc = YES;
    if (self.verticalScroller.ptyScrollerDelegate == self) {
        self.verticalScroller.ptyScrollerDelegate = nil;
    }
    [_title removeFromSuperview];
    [self unregisterDraggedTypes];
    [_currentAnnouncement dismiss];
    while (self.trackingAreas.count) {
        [self removeTrackingArea:self.trackingAreas[0]];
    }
    _metalView.delegate = nil;
}

- (iTermDropDownFindViewController *)newDropDownFindView {
    NSString *nibName;
    if ([iTermAdvancedSettingsModel useOldStyleDropDownViews]) {
        nibName = @"FindView";
    } else {
        nibName = @"MinimalFindView";
    }

    iTermDropDownFindViewController *dropDownViewController =
        [[iTermDropDownFindViewController alloc] initWithNibName:nibName
                                                          bundle:[NSBundle bundleForClass:self.class]];
    [[dropDownViewController view] setHidden:YES];
    [super addSubview:dropDownViewController.view];
    [self updateDropDownFrame:dropDownViewController];
    return dropDownViewController;
}

- (void)findDriverInvalidateFrame {
    [self updateDropDownFrame:_dropDownFindViewController];
}

- (void)updateDropDownFrame:(iTermDropDownFindViewController *)dropDownViewController {
    NSRect aRect = [self frame];
    NSSize size = [dropDownViewController desiredSize];
    const NSPoint origin = NSMakePoint(aRect.size.width - size.width - 30,
                                       aRect.size.height - size.height);
    [dropDownViewController setOffsetFromTopRightOfSuperview:NSMakeSize(30, 0)];
    [dropDownViewController.view setFrame:NSMakeRect(origin.x, origin.y, size.width, size.height)];
}

- (BOOL)isDropDownSearchVisible {
    return _findDriverType == iTermSessionViewFindDriverDropDown && _dropDownFindDriver.isVisible;
}

- (void)takeFindDriverFrom:(SessionView *)donorView delegate:(id<iTermFindDriverDelegate>)delegate {
    DLog(@"Take find driver from %@, give it to %@ with delegate %@", donorView, self, delegate);
    if (_dropDownFindDriver.viewController.isViewLoaded) {
        [_dropDownFindDriver.viewController.view removeFromSuperview];
    }

    _findDriverType = donorView->_findDriverType;

    _dropDownFindViewController = donorView->_dropDownFindViewController;
    donorView->_dropDownFindViewController = nil;

    _dropDownFindDriver = donorView->_dropDownFindDriver;
    _temporaryStatusBarFindDriver = donorView->_temporaryStatusBarFindDriver;
    _permanentStatusBarFindDriver = donorView->_permanentStatusBarFindDriver;

    donorView->_dropDownFindDriver = nil;
    donorView->_temporaryStatusBarFindDriver = nil;
    donorView->_permanentStatusBarFindDriver = nil;

    [self setFindDriverDelegate:delegate];

    if (_dropDownFindDriver.viewController.isViewLoaded) {
        [self addSubview:_dropDownFindDriver.viewController.view];
    }
    [self updateFindDriver];
    [self updateFindViewFrame];
}

- (void)setFindDriverDelegate:(id<iTermFindDriverDelegate>)delegate {
    _dropDownFindDriver.delegate = delegate;
    _temporaryStatusBarFindDriver.delegate = delegate;
    _permanentStatusBarFindDriver.delegate = delegate;
}

- (id<iTermFindDriverDelegate>)findDriverDelegate {
    return _dropDownFindDriver.delegate;
}

- (BOOL)findViewHasKeyboardFocus {
    switch (_findDriverType) {
        case iTermSessionViewFindDriverDropDown:
            return !_dropDownFindDriver.isVisible;
        case iTermSessionViewFindDriverPermanentStatusBar:
            return NO;
        case iTermSessionViewFindDriverTemporaryStatusBar:
            return !_temporaryStatusBarFindDriver.isVisible;
    }
    assert(false);
    return YES;
}

- (BOOL)findViewIsHidden {
    switch (_findDriverType) {
        case iTermSessionViewFindDriverDropDown:
            return !_dropDownFindDriver.isVisible;
        case iTermSessionViewFindDriverPermanentStatusBar:
            return NO;
        case iTermSessionViewFindDriverTemporaryStatusBar:
            return self.delegate.sessionViewStatusBarViewController.temporaryLeftComponent == nil;
    }
    assert(false);
    return YES;
}

- (iTermFindDriver *)findDriver {
    switch (_findDriverType) {
        case iTermSessionViewFindDriverDropDown:
            return _dropDownFindDriver;
        case iTermSessionViewFindDriverPermanentStatusBar:
            return _permanentStatusBarFindDriver;
        case iTermSessionViewFindDriverTemporaryStatusBar:
            return _temporaryStatusBarFindDriver;
    }
    assert(false);
    return nil;
}

- (NSSize)internalDecorationSize {
    NSSize size = NSZeroSize;
    if (_showTitle) {
        size.height += _title.frame.size.height;
    }
    if (_showBottomStatusBar) {
        size.height += iTermGetStatusBarHeight();
    }
    return size;
}

- (void)loadTemporaryStatusBarFindDriverWithStatusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    NSString *query = [[iTermFindPasteboard sharedInstance] stringValue] ?: @"";
    _findDriverType = iTermSessionViewFindDriverTemporaryStatusBar;
    NSDictionary *knobs = @{ iTermStatusBarPriorityKey: @(INFINITY),
                             iTermStatusBarSearchComponentIsTemporaryKey: @YES };
    NSDictionary *configuration = @{ iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
    iTermStatusBarSearchFieldComponent *component =
    [[iTermStatusBarSearchFieldComponent alloc] initWithConfiguration:configuration
                                                                scope:self.delegate.sessionViewScope];
    _temporaryStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:component.statusBarComponentSearchViewController
                                                               filterViewController:statusBarViewController.filterViewController];
    _temporaryStatusBarFindDriver.delegate = _dropDownFindDriver.delegate;
    _temporaryStatusBarFindDriver.findString = query;
    component.statusBarComponentSearchViewController.driver = _temporaryStatusBarFindDriver;
    statusBarViewController.temporaryLeftComponent = component;
    [_temporaryStatusBarFindDriver open];
}

- (iTermStatusBarFilterComponent *)temporaryFilterComponent {
    if (_temporaryFilterComponent) {
        return _temporaryFilterComponent;
    }
    NSDictionary *knobs = @{ iTermStatusBarPriorityKey: @(INFINITY),
                             iTermStatusBarFilterComponent.isTemporaryKey: @YES };
    NSDictionary *configuration = @{ iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
    iTermStatusBarFilterComponent *component =
    [[iTermStatusBarFilterComponent alloc] initWithConfiguration:configuration
                                                           scope:self.delegate.sessionViewScope];
    return component;
}

- (void)showFilter {
    DLog(@"showFilter");
    iTermStatusBarViewController *statusBarViewController = self.delegate.sessionViewStatusBarViewController;
    if (statusBarViewController) {
        iTermStatusBarFilterComponent *filterComponent = (iTermStatusBarFilterComponent *)[statusBarViewController.visibleComponents objectPassingTest:^BOOL(id<iTermStatusBarComponent> candidate, NSUInteger index, BOOL *stop) {
            return [candidate isKindOfClass:[iTermStatusBarFilterComponent class]];
        }];
        if (!filterComponent) {
            filterComponent = self.temporaryFilterComponent;
            statusBarViewController.temporaryRightComponent = filterComponent;
        }
        [filterComponent focus];
    } else {
        [self showFindUI];
        [self.findDriver setFilterHidden:NO];
    }
}

- (void)createFindDriverIfNeeded {
    switch (self.findDriverType) {
        case iTermSessionViewFindDriverDropDown:
            if (_dropDownFindDriver) {
                return;
            }
            _dropDownFindDriver = [[iTermFindDriver alloc] initWithViewController:_dropDownFindViewController
                                                             filterViewController:_dropDownFindViewController];
            break;
        case iTermSessionViewFindDriverPermanentStatusBar: {
            if (_permanentStatusBarFindDriver) {
                return;
            }
            iTermStatusBarViewController *statusBarViewController = [self.delegate sessionViewStatusBarViewController];
            if (!statusBarViewController) {
                DLog(@"No status bar VC from %@", self.delegate);
                return;
            }
            _permanentStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:statusBarViewController.searchViewController
                                                                       filterViewController:statusBarViewController.filterViewController];
            _permanentStatusBarFindDriver.delegate = self.findDriverDelegate;
            break;
        }
        case iTermSessionViewFindDriverTemporaryStatusBar:
            if (_temporaryStatusBarFindDriver) {
                return;
            }
            iTermStatusBarViewController *statusBarViewController = [self.delegate sessionViewStatusBarViewController];
            if (!statusBarViewController) {
                DLog(@"No status bar VC from %@", self.delegate);
                return;
            }
            _temporaryStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:statusBarViewController.temporaryLeftComponent.statusBarComponentSearchViewController
                                                                       filterViewController:statusBarViewController.filterViewController];
            _temporaryStatusBarFindDriver.delegate = _dropDownFindDriver.delegate;
            break;
    }
}

- (void)showFindUI {
    iTermStatusBarViewController *statusBarViewController = self.delegate.sessionViewStatusBarViewController;
    if (_findDriverType == iTermSessionViewFindDriverPermanentStatusBar) {
        statusBarViewController.mustShowSearchComponent = YES;
    } else if (self.findViewIsHidden) {
        if (statusBarViewController) {
            if (!statusBarViewController.temporaryLeftComponent) {
                [self loadTemporaryStatusBarFindDriverWithStatusBarViewController:statusBarViewController];
            }
        } else {
            _findDriverType = iTermSessionViewFindDriverDropDown;
            [_dropDownFindDriver open];
        }
    } else if (self.findDriver == nil) {
        assert(statusBarViewController);
        assert(statusBarViewController.temporaryLeftComponent);
        _temporaryStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:statusBarViewController.temporaryLeftComponent.statusBarComponentSearchViewController
                                                                   filterViewController:statusBarViewController.filterViewController];
        _temporaryStatusBarFindDriver.delegate = _dropDownFindDriver.delegate;
        [_temporaryStatusBarFindDriver open];
    }
    [self.findDriver makeVisible];
}

- (void)findViewDidHide {
    self.delegate.sessionViewStatusBarViewController.mustShowSearchComponent = NO;
    self.delegate.sessionViewStatusBarViewController.temporaryLeftComponent = nil;
}

- (BOOL)useMetal {
    return _useMetal;
}

- (void)setUseMetal:(BOOL)useMetal dataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    if (useMetal != _useMetal) {
        _useMetal = useMetal;
        DLog(@"setUseMetal:%@ dataSource:%@", @(useMetal), dataSource);
        if (useMetal) {
            [self installMetalViewWithDataSource:dataSource];
        } else {
            [self removeMetalView];
        }

        iTermMetalClipView *metalClipView = (iTermMetalClipView *)_scrollview.contentView;
        metalClipView.useMetal = useMetal;
        _legacyView.hidden = !useMetal;
        
        [self updateLayout];
        [self setNeedsDisplay:YES];
    }
}

- (void)preferredMetalDeviceDidChange:(NSNotification *)notification NS_AVAILABLE_MAC(10_11) {
    if (_metalView) {
        [self.delegate sessionViewRecreateMetalView];
    }
}

- (id<MTLDevice>)metalDevice {
    static id<MTLDevice> chosenDevice;
    static BOOL preferIntegrated;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferIntegrated = [iTermPreferences boolForKey:kPreferenceKeyPreferIntegratedGPU];
        if (preferIntegrated) {
            NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();

            id<MTLDevice> gpu = nil;

            for (id<MTLDevice> device in devices) {
                if (device.isLowPower) {
                    gpu = device;
                    break;
                }
            }

            if (!gpu) {
                gpu = MTLCreateSystemDefaultDevice();
            }
            // I'm intentionally leaking devices and gpu because I'm seeing crazy crashes where
            // metal occasionally thinks something is over-released. There's no reason to do that
            // dangerous dance here.
            chosenDevice = gpu;
        } else {
            static id<MTLDevice> device;
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                device = MTLCreateSystemDefaultDevice();
            });
            chosenDevice = device;
        }
    });
    return chosenDevice;
}

- (void)installLegacyView {
    assert(!_legacyView);
    _legacyView = [[iTermLegacyView alloc] init];
    _legacyView.delegate = self;
    // Image view and background color view go under it.
    [self insertSubview:_legacyView atIndex:2];
    _metalClipView.legacyView = _legacyView;
}

- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index {
    [super insertSubview:subview atIndex:index];
    [self sanityCheckSubviewOrder];
}

- (void)addSubview:(NSView *)view positioned:(NSWindowOrderingMode)place relativeTo:(NSView *)otherView {
    [super addSubview:view positioned:place relativeTo:otherView];
    [self sanityCheckSubviewOrder];
}

- (void)sanityCheckSubviewOrder {
    NSInteger l = [self.subviews indexOfObjectPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj == _legacyView;
    }];
    NSInteger s = [self.subviews indexOfObjectPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj == _scrollview;
    }];
    if (l != NSNotFound && s != NSNotFound && l > s)  {
        NSString *message = [NSString stringWithFormat:@"Wrong subview order.\n%@\n%@", [self subviews], [NSThread callStackSymbols]];
#if BETA
        ITCriticalError(NO, @"%@", message);
#else
        DLog(@"%@", message);
#endif
    }
}
- (void)installMetalViewWithDataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    if (_metalView) {
        [self removeMetalView];
    }
    // Allocate a new metal view
    _metalView = [[iTermMTKView alloc] initWithFrame:_scrollview.contentView.frame
                                              device:[self metalDevice]];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    if (iTermTextIsMonochrome()) {
        _metalView.layer.opaque = NO;
    } else {
        _metalView.layer.opaque = YES;
    }
#else
    _metalView.layer.opaque = YES;
#endif
    if ([iTermAdvancedSettingsModel hdrCursor]) {
        CAMetalLayer *metalLayer = [CAMetalLayer castFrom:_metalView.layer];
        assert(metalLayer);
        metalLayer.wantsExtendedDynamicRangeContent = YES;
        metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;
    }
    _metalView.colorspace = [[NSColorSpace it_defaultColorSpace] CGColorSpace];

    // Tell the clip view about it so it can ask the metalview to draw itself on scroll.
    _metalClipView.metalView = _metalView;

    // Image view and background color view go under it.
    [self insertSubview:_metalView atIndex:2];

    // Configure and hide the metal view. It will be shown by PTYSession after it has rendered its
    // first frame. Until then it's just a solid gray rectangle.
    _metalView.paused = YES;
    _metalView.enableSetNeedsDisplay = NO;
    _metalView.hidden = NO;
    _metalView.alphaValue = 0;

    // Start the metal driver going. It will receive delegate calls from MTKView that kick off
    // frame rendering.
    _driver = [[iTermMetalDriver alloc] initWithDevice:_metalView.device];
    _driver.dataSource = dataSource;
    [_driver mtkView:_metalView drawableSizeWillChange:_metalView.drawableSize];
    _metalView.delegate = _driver;
    [self metalViewVisibilityDidChange];
}

- (void)removeMetalView NS_AVAILABLE_MAC(10_11) {
    _metalView.delegate = nil;
    [_metalView removeFromSuperview];
    _metalView = nil;
    _driver = nil;
    _metalClipView.useMetal = NO;
    _metalClipView.metalView = nil;
    [self metalViewVisibilityDidChange];
}

- (void)setMetalViewNeedsDisplayInTextViewRect:(NSRect)textViewRect NS_AVAILABLE_MAC(10_11) {
    if (_useMetal) {
        // TODO: Would be nice to draw only the rect, but I don't see a way to do that with MTKView
        // that doesn't involve doing something nutty like saving a copy of the drawable.
        [_metalView setNeedsDisplay:YES];
        [_scrollview setNeedsDisplay:YES];
    }

    // Legacy view is hidden when metal is enabled, but when temporarily disabling metal you can get
    // here while _useMetal is YES and _legacyView is also NOT hidden. Issue 9587.
    [_legacyView setNeedsDisplay:YES];
}

- (void)didChangeMetalViewAlpha {
    [self metalViewVisibilityDidChange];
}

- (void)metalViewVisibilityDidChange {
    [self updateImageAndBackgroundViewVisibility];
}

- (void)updateImageAndBackgroundViewVisibility {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_metalView.alphaValue == 0) {
        _imageView.hidden = (_imageView.image == nil);
        DLog(@"updateImageAndBackgroundViewVisibility: set backgroundColorView.hidden=%@ because metalView.alphaValue=0",
             @(!iTermTextIsMonochrome()));
        _backgroundColorView.hidden = !iTermTextIsMonochrome();
        _legacyScrollerBackgroundView.hidden = iTermTextIsMonochrome();
    } else {
        _imageView.hidden = YES;
        DLog(@"updateImageAndBackgroundViewVisibility: Set backgroundColorView.hidden=YES because metalView.alphaValue (%@) != 0", @(_metalView.alphaValue));
        _backgroundColorView.hidden = YES;
        _legacyScrollerBackgroundView.hidden = YES;
    }
    [self setNeedsDisplay:YES];
    [CATransaction commit];
}

- (NSColor *)it_backgroundColorOfEnclosingTerminalIfBackgroundColorViewHidden {
    if (_backgroundColorView.isHidden) {
        return [_backgroundColorView.backgroundColor colorWithAlphaComponent:[self.delegate sessionViewTransparencyAlpha]];
    }
    return nil;
}
- (void)tabColorDidChange {
    [_title updateBackgroundColor];
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    [_title updateBackgroundColor];
    if (needsDisplay) {
        [_metalView setNeedsDisplay:YES];
        [_title setNeedsDisplay:YES];
        [_genericStatusBarContainer setNeedsDisplay:YES];
    }
}

- (void)addSubviewBelowFindView:(NSView *)aView {
    if ([aView isKindOfClass:[PTYScrollView class]]) {
        NSIndexSet *indexes = [self.subviews indexesOfObjectsPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj isKindOfClass:[MTKView class]] || obj == _legacyView;
        }];
        if (indexes.count) {
            // Insert scrollview after metal view and legacy view
            const NSUInteger i = [indexes lastIndex];
            [self addSubview:aView positioned:NSWindowAbove relativeTo:self.subviews[i]];
            return;
        }
    }
    if ([aView isKindOfClass:[MTKView class]]) {
        NSInteger i = [self.subviews indexOfObjectPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj isKindOfClass:[PTYScrollView class]];
        }];
        if (i != NSNotFound) {
            // Insert metal view before scroll view
            [self addSubview:aView positioned:NSWindowBelow relativeTo:self.subviews[i]];
            return;
        }
    }
    if (_dropDownFindViewController.view && [self.subviews containsObject:_dropDownFindViewController.view]) {
        [self addSubview:aView positioned:NSWindowBelow relativeTo:[_dropDownFindViewController view]];
    } else {
        [super addSubview:aView];
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize {
    [self updateLayout];
    [self updateTrackingAreas];
}

- (NSRect)frameForLegacyScroller {
    if (!_scrollview.isLegacyScroller) {
        return NSZeroRect;
    }
    return [_scrollview.verticalScroller convertRect:_scrollview.verticalScroller.bounds
                                              toView:self];
}

- (void)scrollerStyleDidChange:(NSNotification *)notification {
    [self updateLayout];
}

- (void)updateLayout {
    DLog(@"PTYSession begin updateLayout. delegate=%@\n%@", _delegate, [NSThread callStackSymbols]);
    DLog(@"Before:\n%@", [self iterm_recursiveDescription]);
    if ([_delegate sessionViewShouldUpdateSubviewsFramesAutomatically]) {
        DLog(@"Automatically updating subview frames");
        if (self.showTitle) {
            [self updateTitleFrame];
        } else {
            [self updateScrollViewFrame];
            [self updateFindViewFrame];
        }
        if (self.showBottomStatusBar) {
            [self updateBottomStatusBarFrame];
        }
        if (self.composerHeight > 0) {
            [self.delegate sessionViewUpdateComposerFrame];
        }
    } else {
        DLog(@"Keep everything top aligned.");
        // Don't resize anything but do keep it all top-aligned.
        if (self.showTitle) {
            NSRect aRect = [self frame];
            CGFloat maxY = aRect.size.height;

            maxY -= _title.frame.size.height;
            [_title setFrame:NSMakeRect(0,
                                        maxY,
                                        _title.frame.size.width,
                                        _title.frame.size.height)];

            NSRect frame = _scrollview.frame;
            maxY -= frame.size.height;
            frame.origin.y = maxY;
            DLog(@"Tweaking y offset of scrollview for title bar");
            _scrollview.frame = frame;
            if (PTYScrollView.shouldDismember) {
                _scrollview.verticalScroller.frame = [self frameForScroller];
            }
        }
        if (_showBottomStatusBar) {
            _genericStatusBarContainer.frame = NSMakeRect(0,
                                                          0,
                                                          self.frame.size.width,
                                                          _genericStatusBarContainer.frame.size.height);
        }
        NSRect frame = _imageView.frame;
        frame.origin.x = 0;
        frame.origin.y = self.bounds.size.height - frame.size.height;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _imageView.frame = frame;
        _backgroundColorView.frame = frame;
        _legacyScrollerBackgroundView.frame = [self frameForLegacyScroller];
        [CATransaction commit];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _imageView.frame = self.bounds;
    _backgroundColorView.frame = self.bounds;
    _legacyScrollerBackgroundView.frame = [self frameForLegacyScroller];
    [CATransaction commit];

    if (_hoverURLView) {
        [_hoverURLTextField sizeToFit];

        const CGFloat horizontalPadding = 8;
        const CGFloat verticalPadding = 4;

        NSArray<NSValue *> *proposedFrames = [self framesForURLPreviewWithPadding:NSMakeSize(horizontalPadding, verticalPadding)];
        NSValue *bestFrameValue = [proposedFrames maxWithBlock:^NSComparisonResult(NSValue *obj1, NSValue *obj2) {
            const NSRect lhs = obj1.rectValue;
            const NSRect rhs = obj2.rectValue;

            const NSRect leftIntersection = NSIntersectionRect(lhs, self->_urlAnchorFrame);
            const NSRect rightIntersection = NSIntersectionRect(rhs, self->_urlAnchorFrame);

            const CGFloat leftArea = leftIntersection.size.width * leftIntersection.size.height;
            const CGFloat rightArea = rightIntersection.size.width * rightIntersection.size.height;

            return [@(rightArea) compare: @(leftArea)];
        }];
        _hoverURLView.frame = bestFrameValue.rectValue;

        NSRect frame = _hoverURLTextField.frame;
        frame.origin = NSMakePoint(horizontalPadding, verticalPadding);
        _hoverURLTextField.frame = frame;
    }
    [self updateAnnouncementFrame];

    if (_useMetal) {
        [self updateMetalViewFrame];
    }
    DLog(@"After:\n%@", [self iterm_recursiveDescription]);
}

- (NSArray<NSValue *> *)framesForURLPreviewWithPadding:(NSSize)padding {
    NSRect frame = _hoverURLTextField.bounds;
    frame.size.width += padding.width * 2;
    frame.size.height += padding.height * 2;

    const CGFloat minX = 4;
    const CGFloat minY = 4;
    const CGFloat maxX = NSWidth(self.bounds) - NSWidth(frame) - 4;
    const CGFloat maxY = NSHeight(self.bounds) - NSHeight(frame) - 4;
    return @[
        [NSValue valueWithRect:NSMakeRect(minX, minY, frame.size.width, frame.size.height)],
        [NSValue valueWithRect:NSMakeRect(maxX, minY, frame.size.width, frame.size.height)],
        [NSValue valueWithRect:NSMakeRect(minX, maxY, frame.size.width, frame.size.height)],
        [NSValue valueWithRect:NSMakeRect(maxX, maxY, frame.size.width, frame.size.height)],
    ];
}

- (void)updateLegacyViewFrame {
    NSRect rect = NSZeroRect;
    rect.origin.y = self.showBottomStatusBar ? iTermGetStatusBarHeight() : 0;
    rect.size.width = NSWidth(_scrollview.documentVisibleRect);
    rect.size.height = NSHeight(_scrollview.documentVisibleRect);
    _legacyView.frame = rect;
}
- (void)didBecomeVisible {
    [[self.delegate sessionViewStatusBarViewController] updateColors];
}

- (void)updateMetalViewFrame {
    DLog(@"update metalView frame");
    // The metal view looks awful while resizing because it insists on scaling
    // its contents. Just switch off the metal renderer until it catches up.
    [_delegate sessionViewNeedsMetalFrameUpdate];
}

- (void)reallyUpdateMetalViewFrame {
    _metalView.frame = self.bounds;
    [_driver mtkView:_metalView drawableSizeWillChange:_metalView.drawableSize];
}

- (NSRect)frameByInsettingForMetal:(NSRect)frame {
    return frame;
}

- (void)setDelegate:(id<iTermSessionViewDelegate>)delegate {
    _delegate = delegate;
    [_delegate sessionViewDimmingAmountDidChange:[self adjustedDimmingAmount]];
    [self updateLayout];
}

- (void)setMainResponder:(NSResponder *)responder {
    _dropDownFindViewController.nextResponder = responder;
}

- (void)_dimShadeToDimmingAmount:(float)newDimmingAmount {
    [_delegate sessionViewDimmingAmountDidChange:newDimmingAmount];
}

- (double)dimmedDimmingAmount {
    return [iTermPreferences floatForKey:kPreferenceKeyDimmingAmount];
}

- (double)adjustedDimmingAmount {
    int x = 0;
    if (_dim) {
        x++;
    }
    if (_backgroundDimmed) {
        x++;
    }
    double scale[] = { 0, 1.0, 1.5 };
    double amount = scale[x] * [self dimmedDimmingAmount];
    // Cap amount within reasonable bounds. Before 1.1, dimming amount was only changed by
    // twiddling the prefs file so it could have all kinds of crazy values.
    amount = MIN(0.9, amount);
    amount = MAX(0, amount);

    return amount;
}

- (void)updateDim {
    double amount = [self adjustedDimmingAmount];

    [self _dimShadeToDimmingAmount:amount];
    [_title setDimmingAmount:amount];
    iTermStatusBarViewController *statusBar = self.delegate.sessionViewStatusBarViewController;
    [statusBar updateColors];
}

- (void)updateColors {
    [_title updateTextColor];
}

- (void)setDimmed:(BOOL)isDimmed {
    if (isDimmed == _dim) {
        return;
    }
    if ([_delegate sessionViewIsVisible]) {
        _dim = isDimmed;
        [self updateDim];
    } else {
        _dim = isDimmed;
    }
}

- (void)setBackgroundDimmed:(BOOL)backgroundDimmed {
    BOOL orig = _backgroundDimmed;
    if ([iTermPreferences boolForKey:kPreferenceKeyDimBackgroundWindows]) {
        _backgroundDimmed = backgroundDimmed;
    } else {
        _backgroundDimmed = NO;
    }
    if (_backgroundDimmed != orig) {
        [self updateDim];
        [self setNeedsDisplay:YES];
    }
}

static const NSInteger SessionViewNumberOfTrackingAreas = 2;

typedef struct {
    NSRect rect;
    NSTrackingAreaOptions options;
} iTermTrackingAreaSpec;

// specs points at space for SessionViewNumberOfTrackingAreas values.
- (void)getDesiredTrackingRectFrames:(iTermTrackingAreaSpec *)specs {
    NSTrackingAreaOptions trackingOptions;
    trackingOptions = (NSTrackingMouseEnteredAndExited |
                       NSTrackingActiveAlways |
                       NSTrackingEnabledDuringMouseDrag);
    if ([self.delegate sessionViewCaresAboutMouseMovement]) {
        DLog(@"Track mouse moved events");
        trackingOptions |= NSTrackingMouseMoved;
    } else {
        DLog(@"Do not track mouse moved events");
    }
    const iTermTrackingAreaSpec value[SessionViewNumberOfTrackingAreas] = {
        {
            .rect = self.bounds,
            .options=trackingOptions
        },
        {
            .rect = [self offscreenCommandLineFrame],
            .options = NSTrackingActiveInActiveApp | NSTrackingMouseEnteredAndExited
        }
    };
    memmove(specs, value, sizeof(value));
}


// It's very expensive for PTYTextView to own its own tracking events because its frame changes
// constantly, plus it can miss mouse exit events and spurious mouse enter events (issue 3345).
// I believe it also caused hangs (issue 3974).
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if ([self window] && [self shouldUpdateTrackingAreas]) {
        while (self.trackingAreas.count) {
            [self removeTrackingArea:self.trackingAreas[0]];
        }

        iTermTrackingAreaSpec specs[SessionViewNumberOfTrackingAreas];
        [self getDesiredTrackingRectFrames:specs];
        for (NSInteger i = 0; i < SessionViewNumberOfTrackingAreas; i++) {
            NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:specs[i].rect
                                                                        options:specs[i].options
                                                                          owner:self
                                                                       userInfo:nil];
            [self addTrackingArea:trackingArea];
        }
    }
}

- (BOOL)shouldUpdateTrackingAreas {
    iTermTrackingAreaSpec specs[SessionViewNumberOfTrackingAreas];
    if (self.trackingAreas.count != SessionViewNumberOfTrackingAreas) {
        DLog(@"Must initialize tracking areas");
        return YES;
    }
    [self getDesiredTrackingRectFrames:specs];
    for (NSInteger i = 0; i < SessionViewNumberOfTrackingAreas; i++) {
        NSTrackingArea *area = self.trackingAreas[i];
        if (!NSEqualRects(area.rect, specs[i].rect)) {
            DLog(@"Found unequal rect");
            return YES;
        }
        if (area.options != specs[i].options) {
            DLog(@"Found unequal options");
            return YES;
        }
    }
    DLog(@"Existing tracking areas are just fine");
    return NO;
}

- (NSRect)offscreenCommandLineFrame {
    return [self.delegate sessionViewOffscreenCommandLineFrameForView:self];
}

- (void)mouseEntered:(NSEvent *)theEvent {
    DLog(@"enter %@", theEvent.trackingArea);
    [_delegate sessionViewMouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent {
    DLog(@"exit %@", theEvent.trackingArea);
    [_delegate sessionViewMouseExited:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
    DLog(@"Mouse moved");
    [_delegate sessionViewMouseMoved:theEvent];
}

- (void)rightMouseDown:(NSEvent*)event {
    if (!_splitSelectionView) {
        static int inme;
        if (inme) {
            // Avoid infinite recursion. Not quite sure why this happens, but a call
            // to -[PTYTextView rightMouseDown:] will sometimes (after a
            // few steps through the OS) bring you back here. It happens when randomly touching
            // a bunch of fingers on the trackpad.
            return;
        }
        ++inme;
        [_delegate sessionViewRightMouseDown:event];
        --inme;
    }
}


- (void)mouseDown:(NSEvent*)event {
    static int inme;
    if (inme) {
        // Avoid infinite recursion. Not quite sure why this happens, but a call
        // to [_title mouseDown:] or [super mouseDown:] will sometimes (after a
        // few steps through the OS) bring you back here. It only happens
        // consistently when dragging the pane title bar, but it happens inconsistently
        // with clicks in the title bar too.
        return;
    }
    ++inme;
    // A click on the very top of the screen while in full screen mode may not be
    // in any subview!
    NSPoint p = [NSEvent mouseLocation];
    NSPoint pointInSessionView;
    NSRect windowRect = [self.window convertRectFromScreen:NSMakeRect(p.x, p.y, 0, 0)];
    pointInSessionView = [self convertRect:windowRect fromView:nil].origin;
    DLog(@"Point in screen coords=%@, point in window coords=%@, point in session view=%@",
         NSStringFromPoint(p),
         NSStringFromPoint(windowRect.origin),
         NSStringFromPoint(pointInSessionView));
    if (_title && NSPointInRect(pointInSessionView, [_title frame])) {
        [_title mouseDown:event];
        --inme;
        return;
    }
    if (_splitSelectionView) {
        [_splitSelectionView mouseDown:event];
    } else if (NSPointInRect(pointInSessionView, [[self scrollview] frame]) &&
               [_delegate sessionViewShouldForwardMouseDownToSuper:event]) {
        [super mouseDown:event];
    }
    --inme;
}

- (void)setFrameSize:(NSSize)frameSize {
    [self updateAnnouncementFrame];
    [super setFrameSize:frameSize];
    NSView *findView = _dropDownFindViewController.view;
    if (frameSize.width < 340) {
        [findView setFrameSize:NSMakeSize(MAX(150, frameSize.width - 50),
                                          [findView frame].size.height)];
    } else {
        [findView setFrameSize:NSMakeSize(290,
                                          [findView frame].size.height)];
    }
    [self updateFindViewFrame];
}

+ (NSDate *)lastResizeDate {
    return lastResizeDate_;
}

// This is called as part of the live resizing protocol when you let up the mouse button.
- (void)viewDidEndLiveResize {
    lastResizeDate_ = [NSDate date];
}

- (void)saveFrameSize {
    _savedSize = [self frame].size;
}

- (void)restoreFrameSize {
    [self setFrameSize:_savedSize];
}

- (void)createSplitSelectionViewWithMode:(SplitSelectionViewMode)mode session:(id)session {
    id<SplitSelectionViewDelegate> delegate;
    switch (mode) {
        case SplitSelectionViewModeTargetSwap:
        case SplitSelectionViewModeTargetMove:
        case SplitSelectionViewModeSourceSwap:
        case SplitSelectionViewModeSourceMove:
            delegate = [MovePaneController sharedInstance];
            break;
        case SplitSelectionViewModeInspect:
            delegate = self;
            break;
    }
    _splitSelectionView = [[SplitSelectionView alloc] initWithMode:mode
                                                         withFrame:NSMakeRect(0,
                                                                              0,
                                                                              [self frame].size.width,
                                                                              [self frame].size.height)
                                                           session:session
                                                          delegate:delegate];
    _splitSelectionView.wantsLayer = [iTermPreferences boolForKey:kPreferenceKeyUseMetal];
    [_splitSelectionView setFrameOrigin:NSMakePoint(0, 0)];
    [_splitSelectionView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    [self addSubviewBelowFindView:_splitSelectionView];
}

- (void)setSplitSelectionMode:(SplitSelectionMode)mode move:(BOOL)move session:(id)session {
    switch (mode) {
        case kSplitSelectionModeOn:
            if (_splitSelectionView) {
                return;
            }
            if (move) {
                [self createSplitSelectionViewWithMode:SplitSelectionViewModeTargetMove session:session];
            } else {
                [self createSplitSelectionViewWithMode:SplitSelectionViewModeTargetSwap session:session];
            }
            break;

        case kSplitSelectionModeOff:
            [_splitSelectionView removeFromSuperview];
            _splitSelectionView = nil;
            break;

        case kSplitSelectionModeCancel:
            if (move) {
                [self createSplitSelectionViewWithMode:SplitSelectionViewModeSourceMove session:session];
            } else {
                [self createSplitSelectionViewWithMode:SplitSelectionViewModeSourceSwap session:session];
            }
            break;

        case kSplitSelectionModeInspect:
            [self createSplitSelectionViewWithMode:SplitSelectionViewModeInspect session:session];
            break;
    }
}

- (NSColor *)backgroundColorForDecorativeSubviews {
    return [[iTermTheme sharedInstance] backgroundColorForDecorativeSubviewsInSessionWithTabColor:self.tabColor
                                                                              effectiveAppearance:self.effectiveAppearance
                                                                           sessionBackgroundColor:[_delegate sessionViewBackgroundColor]
                                                                                 isFirstResponder:[_delegate sessionViewTerminalIsFirstResponder]
                                                                                      dimOnlyText:[_delegate sessionViewShouldDimOnlyText]
                                                                            adjustedDimmingAmount:[self adjustedDimmingAmount]
                                                                                transparencyAlpha:[self.delegate sessionViewTransparencyAlpha]];
}

- (NSEdgeInsets)extraMargins {
    NSEdgeInsets insets = NSEdgeInsetsZero;
    if (_showTitle) {
        insets.top = iTermGetSessionViewTitleHeight();
    }
    if (self.showBottomStatusBar) {
        insets.bottom = iTermGetStatusBarHeight();
    }
    return insets;
}

- (NSRect)insetRect:(NSRect)rect flipped:(BOOL)flipped includeBottomStatusBar:(BOOL)includeBottomStatusBar {
    CGFloat topInset = self.extraMargins.top;
    CGFloat bottomInset = 0;

    // Most callers don't inset for per-pane status bars because not all panes
    // might have status bars and this function is used to compute the window's
    // inset.
    if (includeBottomStatusBar) {
        bottomInset = self.extraMargins.bottom;
    }
    if (flipped) {
        CGFloat temp;
        temp = topInset;
        topInset = bottomInset;
        bottomInset = temp;
    }
    NSRect frame = rect;
    frame.origin.y += bottomInset;
    frame.size.height -= (topInset + bottomInset);
    return frame;
}

- (NSRect)contentRect {
    return [self insetRect:self.frame
                   flipped:NO
    includeBottomStatusBar:![iTermPreferences boolForKey:kPreferenceKeySeparateStatusBarsPerPane]];
}

- (void)createSplitSelectionView {
    NSRect frame = self.frame;
    _splitSelectionView = [[SplitSelectionView alloc] initWithFrame:NSMakeRect(0,
                                                                               0,
                                                                               frame.size.width,
                                                                               frame.size.height)];
    _splitSelectionView.wantsLayer = [iTermPreferences boolForKey:kPreferenceKeyUseMetal];
    [self addSubviewBelowFindView:_splitSelectionView];
    [[self window] orderFront:nil];
}

- (SplitSessionHalf)removeSplitSelectionView {
    SplitSessionHalf half = [_splitSelectionView half];
    [_splitSelectionView removeFromSuperview];
    _splitSelectionView = nil;
    return half;
}

- (BOOL)hasHoverURL {
    return _hoverURLView != nil;
}

- (BOOL)setHoverURL:(NSString *)url anchorFrame:(NSRect)anchorFrame {
    if ([NSObject object:url isEqualToObject:_hoverURLView.url]) {
        if (!NSEqualRects(anchorFrame, _urlAnchorFrame)) {
            _urlAnchorFrame = anchorFrame;
            [self updateLayout];
        }
        return NO;
    }
    if (_hoverURLView == nil) {
        _hoverURLView = [[iTermHoverContainerView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _hoverURLView.url = url;
        _hoverURLTextField = [[NSTextField alloc] initWithFrame:_hoverURLView.bounds];
        [_hoverURLTextField setDrawsBackground:NO];
        [_hoverURLTextField setBordered:NO];
        [_hoverURLTextField setEditable:NO];
        [_hoverURLTextField setSelectable:NO];
        [_hoverURLTextField setStringValue:url];
        [_hoverURLTextField setAlignment:NSTextAlignmentLeft];
        [_hoverURLTextField setAutoresizingMask:NSViewWidthSizable];
        [_hoverURLTextField setTextColor:[NSColor textColor]];
        _hoverURLTextField.autoresizingMask = NSViewNotSizable;
        [_hoverURLView addSubview:_hoverURLTextField];
        _hoverURLView.frame = _hoverURLTextField.bounds;
        [super addSubview:_hoverURLView];
        [_delegate sessionViewDidChangeHoverURLVisible:YES];
    } else if (url == nil) {
        [_hoverURLView removeFromSuperview];
        _hoverURLView = nil;
        _hoverURLTextField = nil;
        [_delegate sessionViewDidChangeHoverURLVisible:NO];
    } else {
        // _hoverurlView != nil && url != nil
        _hoverURLView.url = url;
        [_hoverURLTextField setStringValue:url];
    }

    [self updateLayout];
    return YES;
}

- (void)viewDidMoveToWindow {
    [_delegate sessionViewDidChangeWindow];
}

- (PTYScroller *)verticalScroller {
    return [PTYScroller castFrom:self.scrollview.verticalScroller];
}

- (void)setSuppressLegacyDrawing:(BOOL)suppressLegacyDrawing {
    _legacyView.hidden = suppressLegacyDrawing;
}

#pragma mark NSDraggingSource protocol

- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
    [[NSCursor closedHandCursor] set];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    const BOOL isLocal = (context == NSDraggingContextWithinApplication);
    return (isLocal ? NSDragOperationMove : NSDragOperationNone);
}

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session {
    return YES;
}

- (void)draggingSession:(NSDraggingSession *)session
           endedAtPoint:(NSPoint)aPoint
              operation:(NSDragOperation)operation {
    if (![[MovePaneController sharedInstance] dragFailed]) {
        [[MovePaneController sharedInstance] dropInSession:nil half:kNoHalf atPoint:aPoint];
    }
}

#pragma mark NSDraggingDestination protocol

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender {
    return [_delegate sessionViewDraggingEntered:sender];
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    [_delegate sessionViewDraggingExited:sender];
    [_splitSelectionView removeFromSuperview];
    _splitSelectionView = nil;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    if ([_delegate sessionViewShouldSplitSelectionAfterDragUpdate:sender]) {
        NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
        [_splitSelectionView updateAtPoint:point];
    }
    return NSDragOperationMove;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    DLog(@"performDragOperation: %@", sender);
    BOOL result = [_delegate sessionViewPerformDragOperation:sender];
    [_delegate sessionViewDraggingExited:sender];
    return result;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)wantsPeriodicDraggingUpdates {
    return YES;
}

- (BOOL)showTitle {
    return _showTitle;
}

- (BOOL)setShowTitle:(BOOL)value adjustScrollView:(BOOL)adjustScrollView {
    if (value == _showTitle) {
        return NO;
    }
    _showTitle = value;
    PTYScrollView *scrollView = [self scrollview];
    NSRect frame = [scrollView frame];
    if (_showTitle) {
        DLog(@"Adjust frame to make make room for title bar");
        frame.size.height -= iTermGetSessionViewTitleHeight();
        _title = [[SessionTitleView alloc] initWithFrame:NSMakeRect(0,
                                                                    self.frame.size.height - iTermGetSessionViewTitleHeight(),
                                                                    self.frame.size.width,
                                                                    iTermGetSessionViewTitleHeight())];
        [self invalidateStatusBar];
        if (adjustScrollView) {
            [_title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        }
        _title.delegate = self;
        [_title setDimmingAmount:[self adjustedDimmingAmount]];
        [self addSubviewBelowFindView:_title];
    } else {
        DLog(@"Adjust frame to eliminate title bar");
        frame.size.height += iTermGetSessionViewTitleHeight();
        [_title removeFromSuperview];
        _title = nil;
    }
    if (adjustScrollView) {
        DLog(@"Tweaking scrollview for titlebar");
        [scrollView setFrame:frame];
        if (PTYScrollView.shouldDismember) {
            _scrollview.verticalScroller.frame = [self frameForScroller];
        }
    } else {
        [self updateTitleFrame];
    }
    [self setTitle:[_delegate sessionViewTitle]];
    [self updateScrollViewFrame];
    [self invalidateStatusBar];
    [self updateAnnouncementFrame];
    [self updateLayout];
    return YES;
}

- (BOOL)statusBarIsInPaneTitleBar {
    return _title.statusBarViewController != nil;
}

- (BOOL)showBottomStatusBar {
    return _showBottomStatusBar;
}

- (BOOL)setShowBottomStatusBar:(BOOL)value adjustScrollView:(BOOL)adjustScrollView {
    if (value == _showBottomStatusBar) {
        return NO;
    }
    _showBottomStatusBar = value;
    
    PTYScrollView *scrollView = [self scrollview];
    NSRect frame = [scrollView frame];
    if (_showBottomStatusBar) {
        DLog(@"Adjust frame to make room for status bar");
        iTermStatusBarViewController *statusBar = self.delegate.sessionViewStatusBarViewController;
        _title.statusBarViewController = nil;
        frame.size.height -= iTermGetStatusBarHeight();
        _genericStatusBarContainer = [[iTermGenericStatusBarContainer alloc] initWithFrame:NSMakeRect(0,
                                                                                                      0,
                                                                                                      self.frame.size.width,
                                                                                                      iTermGetStatusBarHeight())];
        _genericStatusBarContainer.statusBarViewController = statusBar;
        _genericStatusBarContainer.delegate = self;
        [self invalidateStatusBar];
        if (adjustScrollView) {
            [_genericStatusBarContainer setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        }
        [self addSubviewBelowFindView:_genericStatusBarContainer];
    } else {
        DLog(@"Adjust frame to eliminate status bar");
        [_genericStatusBarContainer removeFromSuperview];
        _genericStatusBarContainer = nil;
        frame.size.height += iTermGetStatusBarHeight();
    }
    if (adjustScrollView) {
        [scrollView setFrame:frame];
    } else {
        [self updateBottomStatusBarFrame];
    }
    [self updateScrollViewFrame];
    [self invalidateStatusBar];
    return YES;
}

- (void)invalidateStatusBar {
    iTermStatusBarViewController *newVC = nil;
    if ([_delegate sessionViewUseSeparateStatusBarsPerPane]) {
        newVC = [self.delegate sessionViewStatusBarViewController];
    }
    switch ((iTermStatusBarPosition)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            if (newVC != _title.statusBarViewController) {
                _title.statusBarViewController = newVC;
            }
            break;
            
        case iTermStatusBarPositionBottom:
            if (newVC != _genericStatusBarContainer.statusBarViewController) {
                _genericStatusBarContainer.statusBarViewController = newVC;
            }
            break;
    }
    [self updateFindDriver];
}

- (void)updateFindDriver {
    iTermStatusBarViewController *statusBarViewController = [self.delegate sessionViewStatusBarViewController];
    if (statusBarViewController.searchViewController && statusBarViewController.temporaryLeftComponent == nil) {
        _findDriverType = iTermSessionViewFindDriverPermanentStatusBar;
        _permanentStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:statusBarViewController.searchViewController
                                                                   filterViewController:statusBarViewController.filterViewController];
        _permanentStatusBarFindDriver.delegate = self.findDriverDelegate;
    } else if (statusBarViewController) {
        _findDriverType = iTermSessionViewFindDriverTemporaryStatusBar;
    } else {
        _findDriverType = iTermSessionViewFindDriverDropDown;
    }
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    _title.ordinal = ordinal;
}

- (NSSize)compactFrame {
    NSSize cellSize = [_delegate sessionViewCellSize];
    VT100GridSize gridSize = [_delegate sessionViewGridSize];
    DLog(@"Compute smallest frame that contains a grid of size %@ with cell size %@",
         VT100GridSizeDescription(gridSize), NSStringFromSize(cellSize));

    NSSize dim = NSMakeSize(gridSize.width, gridSize.height);
    NSSize innerSize = NSMakeSize(cellSize.width * dim.width + [iTermPreferences intForKey:kPreferenceKeySideMargins] * 2,
                                  cellSize.height * dim.height + [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins] * 2);
    const BOOL hasScrollbar = [[self scrollview] hasVerticalScroller];
    NSSize size =
        [PTYScrollView frameSizeForContentSize:innerSize
                       horizontalScrollerClass:nil
                         verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                                    borderType:NSNoBorder
                                   controlSize:NSControlSizeRegular
                                 scrollerStyle:[[self scrollview] scrollerStyle]];

    if (_showTitle) {
        size.height += iTermGetSessionViewTitleHeight();
    }
    if (_showBottomStatusBar) {
        size.height += iTermGetStatusBarHeight();
    }
    DLog(@"Smallest such frame is %@", NSStringFromSize(size));
    return size;
}

- (NSSize)maximumPossibleScrollViewContentSize {
    NSSize size = self.frame.size;
    DLog(@"maximumPossibleScrollViewContentSize. size=%@", [NSValue valueWithSize:size]);
    if (_showTitle) {
        size.height -= iTermGetSessionViewTitleHeight();
        DLog(@"maximumPossibleScrollViewContentSize: sub title height. size=%@", [NSValue valueWithSize:size]);
    }
    if (_showBottomStatusBar) {
        size.height -= iTermGetStatusBarHeight();
        DLog(@"maximumPossibleScrollViewContentSize: sub bottom status bar height. size=%@", NSStringFromSize(size));
    }
    DLog(@"maximumPossibleScrollViewContentSize: size=%@", NSStringFromSize(size));
    Class verticalScrollerClass = [[[self scrollview] verticalScroller] class];
    if (![[self scrollview] hasVerticalScroller]) {
        verticalScrollerClass = nil;
    }
    NSSize contentSize =
            [NSScrollView contentSizeForFrameSize:size
                          horizontalScrollerClass:nil
                            verticalScrollerClass:verticalScrollerClass
                                       borderType:[[self scrollview] borderType]
                                      controlSize:NSControlSizeRegular
                                    scrollerStyle:[[[self scrollview] verticalScroller] scrollerStyle]];
    DLog(@"contentSize=%@", NSStringFromSize(contentSize));
    return contentSize;
}

- (void)updateTitleFrame {
    DLog(@"Update title frame");
    NSRect aRect = [self frame];
    if (_showTitle) {
        [_title setFrame:NSMakeRect(0,
                                    aRect.size.height - iTermGetSessionViewTitleHeight(),
                                    aRect.size.width,
                                    iTermGetSessionViewTitleHeight())];
        NSViewController *viewController = [self.delegate sessionViewStatusBarViewController];
        
        [[viewController view] setNeedsLayout:YES];
    }
    [self updateScrollViewFrame];
    [self updateFindViewFrame];
}

- (void)updateBottomStatusBarFrame {
    NSRect aRect = [self frame];
    if (_showBottomStatusBar) {
        _genericStatusBarContainer.frame = NSMakeRect(0,
                                               0,
                                               aRect.size.width,
                                               iTermGetStatusBarHeight());
        
        [_genericStatusBarContainer.statusBarViewController.view setNeedsLayout:YES];
    }
    [self updateScrollViewFrame];
    [self updateFindViewFrame];
}

- (void)updateFindViewFrame {
    DLog(@"update findview frame");
    [_dropDownFindViewController setOffsetFromTopRightOfSuperview:NSMakeSize(30, 0)];
}

- (void)updateScrollViewFrame {
    DLog(@"update scrollview frame");
    CGFloat titleHeight = _showTitle ? _title.frame.size.height : 0;
    CGFloat reservedSpaceOnBottom = _showBottomStatusBar ? iTermGetStatusBarHeight() : 0;
    NSSize proposedSize = NSMakeSize(self.frame.size.width,
                                     self.frame.size.height - titleHeight - reservedSpaceOnBottom);
    NSSize size = [_delegate sessionViewScrollViewWillResize:proposedSize];
    NSRect rect = NSMakeRect(0,
                             reservedSpaceOnBottom + proposedSize.height - size.height,
                             size.width,
                             size.height);
    DLog(@"titleHeight=%@ bottomStatusBarHeight=%@ proposedSize=%@ size=%@ rect=%@",
         @(titleHeight), @(reservedSpaceOnBottom), NSStringFromSize(proposedSize), NSStringFromSize(size),
         NSStringFromRect(rect));
    [self scrollview].frame = rect;
    DLog(@"Scrollview frame is now %@", NSStringFromRect(self.scrollview.frame));
    if (PTYScrollView.shouldDismember) {
        _scrollview.verticalScroller.frame = [self frameForScroller];
    }
    rect.origin = NSZeroPoint;
    rect.size.width = _scrollview.contentSize.width;
    rect.size.height = [_delegate sessionViewDesiredHeightOfDocumentView];
    [_scrollview.documentView setFrame:rect];
    if (_useMetal) {
        [self updateMetalViewFrame];
    }
    [self updateLegacyViewFrame];
    [self updateMinimapFrameAnimated:NO];
    [_delegate sessionViewScrollViewDidResize];
    DLog(@"Returning");
}

- (void)updateMinimapFrameAnimated:(BOOL)animated {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    NSRect frame = [self convertRect:_scrollview.verticalScroller.bounds
                            fromView:_scrollview.verticalScroller];
    PTYScroller *scroller = [PTYScroller castFrom:self.scrollview.verticalScroller];
    if (scroller.ptyScrollerState == PTYScrollerStateOverlayVisibleNarrow) {
        frame.size.width = 11;
        frame.origin.x += 5;
    }
    frame = NSInsetRect(frame, 0, 2);
    if (@available(macOS 10.15, *)) {
        if ([[NSApp effectiveAppearance] it_isDark]) {
            // Avoid overlapping the border on the right. It looks ugly
            // when the window's dark because the part that overlaps the
            // border is extra bright.
            frame.size.width -= 1;
        }
    }
    if (animated) {
        [NSView animateWithDuration:5.0 / 60.0
                         animations:^{
            [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:@"easeOut"]];
            _searchResultsMinimap.animator.frame = frame;
            _marksMinimap.animator.frame = frame;
        }
                         completion:nil];
    } else {
        _searchResultsMinimap.frame = frame;
        _marksMinimap.frame = frame;
    }
}

- (void)setTitle:(NSString *)title {
    if (!title) {
        title = @"";
    }
    _title.title = title;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@:%p frame:%@ size:%@>", [self class], self,
            [NSValue valueWithRect:[self frame]], VT100GridSizeDescription([_delegate sessionViewGridSize])];
}

#pragma mark SessionTitleViewDelegate

- (NSColor *)tabColor {
    return [_delegate sessionViewTabColor];
}

- (NSMenu *)menu {
    return [_delegate sessionViewContextMenu];
}

- (void)close {
    [_delegate sessionViewConfirmAndClose];
}

- (void)beginDrag {
    [_delegate sessionViewBeginDrag];
}

- (void)doubleClickOnTitleView {
    [_delegate sessionViewDoubleClickOnTitleBar];
}

- (void)sessionTitleViewBecomeFirstResponder {
    [_delegate sessionViewBecomeFirstResponder];
}

- (NSColor *)sessionTitleViewBackgroundColor {
    if (!_showBottomStatusBar && _title.statusBarViewController) {
        NSColor *color = _title.statusBarViewController.layout.advancedConfiguration.backgroundColor;
        if (color) {
            return color;
        }
    }
    return [self backgroundColorForDecorativeSubviews];
}

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement {
    DLog(@"Add announcement %@ to %@", announcement.title, self.delegate);
    [_announcements addObject:announcement];
    announcement.delegate = self;
    if (!_currentAnnouncement) {
        [self showNextAnnouncement];
    }
}

- (void)updateAnnouncementFrame {
    // Set the width
    NSRect rect = _currentAnnouncement.view.frame;
    rect.size.width = self.frame.size.width;
    _currentAnnouncement.view.frame = rect;

    // Make it change its height
    [(iTermAnnouncementView *)_currentAnnouncement.view sizeToFit];

    // Fix the origin
    rect = _currentAnnouncement.view.frame;
    rect.origin.y = self.frame.size.height - _currentAnnouncement.view.frame.size.height;
    if (_showTitle) {
        rect.origin.y -= iTermGetSessionViewTitleHeight();
    }
    _currentAnnouncement.view.frame = rect;
}

- (iTermAnnouncementViewController *)nextAnnouncement {
    iTermAnnouncementViewController *possibleAnnouncement = nil;
    while (_announcements.count) {
        possibleAnnouncement = _announcements[0];
        [_announcements removeObjectAtIndex:0];
        if (possibleAnnouncement.shouldBecomeVisible) {
            return possibleAnnouncement;
        }
    }
    return nil;
}

- (void)showNextAnnouncement {
    _currentAnnouncement = nil;
    if (_announcements.count) {
        iTermAnnouncementViewController *possibleAnnouncement = [self nextAnnouncement];
        if (!possibleAnnouncement) {
            return;
        }
        _currentAnnouncement = possibleAnnouncement;
        [self updateAnnouncementFrame];

        // Animate in
        NSRect finalRect = NSMakeRect(0,
                                      self.frame.size.height - _currentAnnouncement.view.frame.size.height,
                                      self.frame.size.width,
                                      _currentAnnouncement.view.frame.size.height);

        NSRect initialRect = finalRect;
        initialRect.origin.y += finalRect.size.height;
        _title.hidden = YES;
        _currentAnnouncement.view.frame = initialRect;

        [_currentAnnouncement.view.animator setFrame:finalRect];

        _currentAnnouncement.view.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [_currentAnnouncement didBecomeVisible];
        [self addSubviewBelowFindView:_currentAnnouncement.view];
    } else {
        _title.hidden = NO;
    }
    [self.delegate sessionViewAnnouncementDidChange:self];
}

#pragma mark - iTermAnnouncementDelegate

- (void)announcementWillDismiss:(iTermAnnouncementViewController *)announcement {
    [_announcements removeObject:announcement];
    if (announcement == _currentAnnouncement) {
        NSRect rect = announcement.view.frame;
        rect.origin.y += rect.size.height;
        [NSView animateWithDuration:0.25
                         animations:^{
                             [announcement.view.animator setFrame:rect];
                         }
                         completion:^(BOOL finished) {
                             [announcement.view removeFromSuperview];
                         }];

        if (!_inDealloc) {
            [self performSelector:@selector(showNextAnnouncement)
                       withObject:nil
                       afterDelay:[[NSAnimationContext currentContext] duration]];
        }
    }
}

#pragma mark - PTYScrollerDelegate

- (void)userScrollDidChange:(BOOL)userScroll {
    [self.delegate sessionViewUserScrollDidChange:userScroll];
}

- (void)viewDidChangeEffectiveAppearance {
    [self updateMinimapAlpha];
    [self.delegate sessionViewDidChangeEffectiveAppearance];
}

- (void)updateMinimapAlpha {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    PTYScroller *scroller = [PTYScroller castFrom:self.scrollview.verticalScroller];
    if (scroller) {
        [self ptyScrollerDidTransitionToState:scroller.ptyScrollerState];
    }
}

- (void)ptyScrollerDidTransitionToState:(PTYScrollerState)state {
    if (![iTermAdvancedSettingsModel showLocationsInScrollbar]) {
        return;
    }
    const CGFloat maxAlpha = _scrollview.verticalScroller.effectiveAppearance.it_isDark ? 0.5 : 0.75;
    switch (state) {
        case PTYScrollerStateLegacy:
            _searchResultsMinimap.alphaValue = maxAlpha;
            _marksMinimap.alphaValue = maxAlpha;
            [self updateMinimapFrameAnimated:YES];
            break;
        case PTYScrollerStateOverlayHidden: {
            [NSView animateWithDuration:5.0 / 60
                             animations:^{
                [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:@"easeOut"]];
                _searchResultsMinimap.animator.alphaValue = 0;
                _marksMinimap.animator.alphaValue = 0;
            }
                             completion:nil];
            break;
        }
        case PTYScrollerStateOverlayVisibleWide:
        case PTYScrollerStateOverlayVisibleNarrow: {
            _searchResultsMinimap.alphaValue = maxAlpha;
            _marksMinimap.alphaValue = maxAlpha;
            [self updateMinimapFrameAnimated:YES];
            break;
        }
    }
}

#pragma mark - iTermFindDriverDelegate

- (BOOL)canSearch {
    return [self.delegate canSearch];
}

- (void)resetFindCursor {
    [self.delegate resetFindCursor];
}

- (BOOL)findInProgress {
    return [self.delegate findInProgress];
}

- (BOOL)continueFind:(double *)progress range:(NSRange *)rangePtr {
    return [self.delegate continueFind:progress range:rangePtr];
}

- (BOOL)growSelectionLeft {
    return [self.delegate growSelectionLeft];
}

- (void)growSelectionRight {
    [self.delegate growSelectionRight];
}

- (NSString *)selectedText {
    return [self.delegate selectedText];
}

- (NSString *)unpaddedSelectedText {
    return [self.delegate unpaddedSelectedText];
}

- (void)copySelection {
    [self.delegate copySelection];
}

- (void)pasteString:(NSString *)string {
    [self.delegate pasteString:string];
}

- (void)findViewControllerMakeDocumentFirstResponder {
    [self.delegate findViewControllerMakeDocumentFirstResponder];
}

- (void)findViewControllerClearSearch {
    DLog(@"begin delegate=%@", self.delegate);
    [self.delegate findViewControllerClearSearch];
    self.delegate.sessionViewStatusBarViewController.temporaryLeftComponent = nil;
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset
scrollToFirstResult:(BOOL)scrollToFirstResult {
    DLog(@"begin self=%@ aString=%@", self, aString);
    [self.delegate findString:aString
             forwardDirection:direction
                         mode:mode
                   withOffset:offset
          scrollToFirstResult:scrollToFirstResult];
}

- (void)findDriverFilterVisibilityDidChange:(BOOL)visible {
    [self.delegate findDriverFilterVisibilityDidChange:visible];
}

- (void)findDriverSetFilter:(NSString *)filter withSideEffects:(BOOL)withSideEffects {
    [self.delegate findDriverSetFilter:filter withSideEffects:withSideEffects];
}

- (void)findViewControllerVisibilityDidChange:(id<iTermFindViewController>)sender {
    [self.delegate findViewControllerVisibilityDidChange:sender];
}

- (void)findViewControllerDidCeaseToBeMandatory:(id<iTermFindViewController>)sender {
    [self.delegate findViewControllerDidCeaseToBeMandatory:sender];
}

- (NSInteger)findDriverCurrentIndex {
    return [self.delegate findDriverCurrentIndex];
}

- (NSInteger)findDriverNumberOfSearchResults {
    return [self.delegate findDriverNumberOfSearchResults];
}

- (void)showUnobtrusiveMessage:(NSString *)message {
    [self showUnobtrusiveMessage:message duration:1];
}

- (void)showUnobtrusiveMessage:(NSString *)message duration:(NSTimeInterval)duration {
    if (_unobtrusiveMessage) {
        return;
    }
    _unobtrusiveMessage = [[iTermUnobtrusiveMessage alloc] initWithMessage:message];
    _unobtrusiveMessage.duration = duration;
    [self addSubviewBelowFindView:_unobtrusiveMessage];
    [_unobtrusiveMessage animateFromTopRightWithCompletion:^{
        [self->_unobtrusiveMessage removeFromSuperview];
        self->_unobtrusiveMessage = nil;
    }];
}

#pragma mark - iTermGenericStatusBarContainer

- (NSColor *)genericStatusBarContainerBackgroundColor {
    return [self backgroundColorForDecorativeSubviews];
}

- (NSScrollView *)ptyScrollerScrollView NS_AVAILABLE_MAC(10_14) {
    return _scrollview;
}

#pragma mark - SplitSelectionViewDelegate

- (void)didSelectDestinationSession:(PTYSession *)session half:(SplitSessionHalf)half {
    [[NSNotificationCenter defaultCenter] postNotificationName:SessionViewWasSelectedForInspectionNotification object:self];
}

#pragma mark - iTermSearchResultsMinimapViewDelegate

- (NSIndexSet *)searchResultsMinimapViewLocations:(iTermSearchResultsMinimapView *)view NS_AVAILABLE_MAC(10_14) {
    return [self.searchResultsMinimapViewDelegate searchResultsMinimapViewLocations:view];
}

- (NSRange)searchResultsMinimapViewRangeOfVisibleLines:(iTermSearchResultsMinimapView *)view NS_AVAILABLE_MAC(10_14) {
    return [self.searchResultsMinimapViewDelegate searchResultsMinimapViewRangeOfVisibleLines:view];
}

#pragma mark - iTermLegacyViewDelegate

- (void)legacyView:(iTermLegacyView *)legacyView drawRect:(NSRect)dirtyRect {
    [self.delegate legacyView:legacyView drawRect:dirtyRect];
}

@end
