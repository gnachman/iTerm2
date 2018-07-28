// This view contains a session's scrollview.

#import "SessionView.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermAnnouncementViewController.h"
#import "iTermDropDownFindViewController.h"
#import "iTermFindDriver.h"
#import "iTermMetalClipView.h"
#import "iTermMetalDeviceProvider.h"
#import "iTermPreferences.h"
#import "iTermStatusBarSearchFieldComponent.h"
#import "iTermStatusBarViewController.h"
#import "NSView+iTerm.h"
#import "MovePaneController.h"
#import "NSResponder+iTerm.h"
#import "PSMTabDragAssistant.h"
#import "PTYScrollView.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PTYTextView.h"
#import "SessionTitleView.h"
#import "SplitSelectionView.h"

#import <MetalKit/MetalKit.h>

static int nextViewId;
// NOTE: This must equal iTermStatusBarHeight
static const double kTitleHeight = 22;

// Last time any window was resized TODO(georgen):it would be better to track per window.
static NSDate* lastResizeDate_;

@interface iTermHoverContainerView : NSView
@end

@implementation iTermHoverContainerView

- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSSize size = self.bounds.size;
    size.width -= 1.5;
    size.height -= 1.5;
    const CGFloat radius = 4;
    [path moveToPoint:NSMakePoint(0, 0)];
    [path lineToPoint:NSMakePoint(0, size.height)];
    [path lineToPoint:NSMakePoint(size.width - radius, size.height)];
    [path curveToPoint:NSMakePoint(size.width, size.height - radius)
         controlPoint1:NSMakePoint(size.width, size.height)
         controlPoint2:NSMakePoint(size.width, size.height)];
    [path lineToPoint:NSMakePoint(size.width, 0)];
    [path lineToPoint:NSMakePoint(0, 0)];

    [[NSColor darkGrayColor] setStroke];
    [[NSColor lightGrayColor] setFill];

    [path stroke];
    [path fill];
}

@end


@interface SessionView () <
    iTermAnnouncementDelegate,
    iTermFindDriverDelegate,
    NSDraggingSource,
    PTYScrollerDelegate>
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
    SessionTitleView *_title;

    NSView *_hoverURLView;
    NSTextField *_hoverURLTextField;

    BOOL _useMetal;
    iTermMetalClipView *_metalClipView;
    iTermDropDownFindViewController *_dropDownFindViewController;
    enum {
        iTermSessionViewFindDriverDropDown,
        iTermSessionViewFindDriverTemporaryStatusBar,
        iTermSessionViewFindDriverPermanentStatusBar
    } _findDriver;
    iTermFindDriver *_dropDownFindDriver;
    iTermFindDriver *_permanentStatusBarFindDriver;
    iTermFindDriver *_temporaryStatusBarFindDriver;
}

+ (double)titleHeight {
    return kTitleHeight;
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

        // Set up find view
        _dropDownFindViewController = [self newDropDownFindView];
        _dropDownFindDriver = [[iTermFindDriver alloc] initWithViewController:_dropDownFindViewController];

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

        if (@available(macOS 10.11, *)) {
            _metalClipView = [[iTermMetalClipView alloc] initWithFrame:_scrollview.contentView.frame];
            _metalClipView.metalView = _metalView;
            _scrollview.contentView = _metalClipView;
            _scrollview.drawsBackground = NO;
        }

        _scrollview.contentView.copiesOnScroll = NO;

        // assign the main view
        [self addSubviewBelowFindView:_scrollview];

#if ENABLE_LOW_POWER_GPU_DETECTION
        if (@available(macOS 10.11, *)) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(preferredMetalDeviceDidChange:)
                                                         name:iTermMetalDeviceProviderPreferredDeviceDidChangeNotification
                                                       object:nil];
        }
#endif
    }
    return self;
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
    iTermDropDownFindViewController *dropDownViewController =
        [[iTermDropDownFindViewController alloc] initWithNibName:@"FindView" bundle:nil];
    [[dropDownViewController view] setHidden:YES];
    [super addSubview:dropDownViewController.view];
    NSRect aRect = [self frame];
    NSSize size = [[dropDownViewController view] frame].size;
    [dropDownViewController setFrameOrigin:NSMakePoint(aRect.size.width - size.width - 30,
                                                       aRect.size.height - size.height)];
    return dropDownViewController;
}

- (BOOL)isDropDownSearchVisible {
    return _findDriver == iTermSessionViewFindDriverDropDown && _dropDownFindDriver.isVisible;
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
    switch (_findDriver) {
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

    switch (_findDriver) {
        case iTermSessionViewFindDriverDropDown:
            return !_dropDownFindDriver.isVisible;
        case iTermSessionViewFindDriverPermanentStatusBar:
            return NO;
        case iTermSessionViewFindDriverTemporaryStatusBar:
            return _title.statusBarViewController.temporaryLeftComponent == nil;
    }
    assert(false);
    return YES;
}

- (iTermFindDriver *)findDriver {
    switch (_findDriver) {
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

- (void)showFindUI {
    if (self.findViewIsHidden) {
        if (_title.statusBarViewController) {
            if (!_title.statusBarViewController.temporaryLeftComponent) {
                _findDriver = iTermSessionViewFindDriverTemporaryStatusBar;
                NSDictionary *knobs = @{ iTermStatusBarPriorityKey: @(INFINITY),
                                         iTermStatusBarSearchComponentIsTemporaryKey: @YES };
                NSDictionary *configuration = @{ iTermStatusBarComponentConfigurationKeyKnobValues: knobs};
                iTermStatusBarSearchFieldComponent *component =
                    [[iTermStatusBarSearchFieldComponent alloc] initWithConfiguration:configuration];
                _temporaryStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:component.statusBarComponentSearchViewController];
                _temporaryStatusBarFindDriver.delegate = _dropDownFindDriver.delegate;
                component.statusBarComponentSearchViewController.driver = _temporaryStatusBarFindDriver;
                _title.statusBarViewController.temporaryLeftComponent = component;
            }
        } else {
            _findDriver = iTermSessionViewFindDriverDropDown;
            [_temporaryStatusBarFindDriver open];
        }
    }
    [self.findDriver makeVisible];
}

- (void)findViewDidHide {
    _title.statusBarViewController.temporaryLeftComponent = nil;
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
    static BOOL preferIntegrated;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        preferIntegrated = [iTermPreferences boolForKey:kPreferenceKeyPreferIntegratedGPU];
    });
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
        return gpu;
    } else {
        static id<MTLDevice> device;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            device = MTLCreateSystemDefaultDevice();
        });
        return device;
    }
}

- (void)installMetalViewWithDataSource:(id<iTermMetalDriverDataSource>)dataSource NS_AVAILABLE_MAC(10_11) {
    if (_metalView) {
        [self removeMetalView];
    }
    // Allocate a new metal view
    _metalView = [[MTKView alloc] initWithFrame:_scrollview.contentView.frame
                                         device:[self metalDevice]];
#if ENABLE_TRANSPARENT_METAL_WINDOWS
    _metalView.layer.opaque = NO;
#else
    _metalView.layer.opaque = YES;
#endif
    _metalView.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    // There was a spike in crashes on 5/1. I'm removing this temporarily to see if it was the cause.
#if ENABLE_LOW_POWER_GPU_DETECTION
                                         device:[[iTermMetalDeviceProvider sharedInstance] preferredDevice]];
#endif
    // Tell the clip view about it so it can ask the metalview to draw itself on scroll.
    _metalClipView.metalView = _metalView;

    [self insertSubview:_metalView atIndex:0];

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
}

- (BOOL)drawFrameSynchronously {
    return [_driver drawSynchronouslyInView:_metalView];
}

- (void)removeMetalView NS_AVAILABLE_MAC(10_11) {
    _metalView.delegate = nil;
    [_metalView removeFromSuperview];
    _metalView = nil;
    _driver = nil;
    _metalClipView.useMetal = NO;
    _metalClipView.metalView = nil;
}

- (void)setMetalViewNeedsDisplayInTextViewRect:(NSRect)textViewRect NS_AVAILABLE_MAC(10_11) {
    if (_useMetal) {
        // TODO: Would be nice to draw only the rect, but I don't see a way to do that with MTKView
        // that doesn't involve doing something nutty like saving a copy of the drawable.
        [_metalView setNeedsDisplay:YES];
        [_scrollview setNeedsDisplay:YES];
    }
}

- (void)setNeedsDisplay:(BOOL)needsDisplay {
    [super setNeedsDisplay:needsDisplay];
    if (@available(macOS 10.11, *)) {
        if (needsDisplay) {
            [_metalView setNeedsDisplay:YES];
        }
    }
}

- (void)addSubviewBelowFindView:(NSView *)aView {
    if ([aView isKindOfClass:[PTYScrollView class]]) {
        NSInteger i = [self.subviews indexOfObjectPassingTest:^BOOL(__kindof NSView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj isKindOfClass:[MTKView class]];
        }];
        if (i != NSNotFound) {
            // Insert scrollview after metal view
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
}

- (void)updateLayout {
    if ([_delegate sessionViewShouldUpdateSubviewsFramesAutomatically]) {
        if (self.showTitle) {
            [self updateTitleFrame];
        } else {
            [self updateScrollViewFrame];
            [self updateFindViewFrame];
        }
    } else {
        // Don't resize anything but do keep it all top-aligned.
        if (self.showTitle) {
            NSRect aRect = [self frame];
            CGFloat maxY = aRect.size.height;
            if (_showTitle) {
                maxY -= _title.frame.size.height;
                [_title setFrame:NSMakeRect(0,
                                            maxY,
                                            _title.frame.size.width,
                                            _title.frame.size.height)];
            }
            NSRect frame = _scrollview.frame;
            maxY -= frame.size.height;
            frame.origin.y = maxY;
            _scrollview.frame = frame;
        }
    }

    if (_hoverURLView) {
        [_hoverURLTextField sizeToFit];
        NSRect frame = _hoverURLTextField.bounds;
        const CGFloat horizontalPadding = 8;
        const CGFloat verticalPadding = 4;
        frame.size.width += horizontalPadding * 2;
        frame.size.height += verticalPadding * 2;
        _hoverURLView.frame = frame;

        frame = _hoverURLTextField.frame;
        frame.origin = NSMakePoint(horizontalPadding, verticalPadding);
        _hoverURLTextField.frame = frame;
    }

    if (_useMetal) {
        [self updateMetalViewFrame];
    }
}

- (void)updateMetalViewFrame {
    // The metal view looks awful while resizing because it insists on scaling
    // its contents. Just switch off the metal renderer until it catches up.
    [_delegate sessionViewNeedsMetalFrameUpdate];
}

- (void)reallyUpdateMetalViewFrame {
    [_delegate sessionViewHideMetalViewUntilNextFrame];
    _metalView.frame = [self frameByInsettingForMetal:_scrollview.contentView.frame];
    [_driver mtkView:_metalView drawableSizeWillChange:_metalView.drawableSize];
}

- (NSRect)frameByInsettingForMetal:(NSRect)frame {
    if (@available(macOS 10.14, *)) {
        return frame;
    } else {
        return NSInsetRect(frame, 1, [iTermAdvancedSettingsModel terminalVMargin]);
    }
}

- (void)setDelegate:(id<iTermSessionViewDelegate>)delegate {
    _delegate = delegate;
    [_delegate sessionViewDimmingAmountDidChange:[self adjustedDimmingAmount]];
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

// It's very expensive for PTYTextView to own its own tracking events because its frame changes
// constantly, plus it can miss mouse exit events and spurious mouse enter events (issue 3345).
// I believe it also caused hangs (issue 3974).
- (void)updateTrackingAreas {
    if ([self window]) {
        int trackingOptions;
        trackingOptions = (NSTrackingMouseEnteredAndExited |
                           NSTrackingActiveAlways |
                           NSTrackingEnabledDuringMouseDrag |
                           NSTrackingMouseMoved);
        while (self.trackingAreas.count) {
            [self removeTrackingArea:self.trackingAreas[0]];
        }
        NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                                    options:trackingOptions
                                                                      owner:self
                                                                   userInfo:nil];
        [self addTrackingArea:trackingArea];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent {
    [_delegate sessionViewMouseEntered:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent {
    [_delegate sessionViewMouseExited:theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent {
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
        // consistently when dragging the pane title bar, but it happens inconsitently
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
        [_dropDownFindViewController setFrameOrigin:NSMakePoint(frameSize.width - [findView frame].size.width - 30,
                                                                frameSize.height - [findView frame].size.height)];
    } else {
        [findView setFrameSize:NSMakeSize(290,
                                          [findView frame].size.height)];
        [_dropDownFindViewController setFrameOrigin:NSMakePoint(frameSize.width - [findView frame].size.width - 30,
                                                                frameSize.height - [findView frame].size.height)];
    }
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

- (void)createSplitSelectionView:(BOOL)cancelOnly move:(BOOL)move session:(id)session {
    _splitSelectionView = [[SplitSelectionView alloc] initAsCancelOnly:cancelOnly
                                                             withFrame:NSMakeRect(0,
                                                                                  0,
                                                                                  [self frame].size.width,
                                                                                  [self frame].size.height)
                                                               session:session
                                                              delegate:[MovePaneController sharedInstance]
                                                                  move:move];
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
            [self createSplitSelectionView:NO move:move session:session];
            break;

        case kSplitSelectionModeOff:
            [_splitSelectionView removeFromSuperview];
            _splitSelectionView = nil;
            break;

        case kSplitSelectionModeCancel:
            [self createSplitSelectionView:YES move:move session:session];
            break;
    }
}

- (void)drawBackgroundInRect:(NSRect)rect {
    [_delegate sessionViewDrawBackgroundImageInView:self
                                           viewRect:rect
                             blendDefaultBackground:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Fill in background color in the area around a scrollview if it's smaller
    // than the session view.
    // TODO(metal): This will be a performance issue. Use another view with a layer and background color.
    [super drawRect:dirtyRect];
    if (_useMetal && _metalView.alphaValue == 1) {
        [self drawAroundFrame:_metalView.frame dirtyRect:dirtyRect];
    } else {
        [self drawAroundFrame:self.scrollview.frame dirtyRect:dirtyRect];
    }
}

- (void)drawAroundFrame:(NSRect)svFrame dirtyRect:(NSRect)dirtyRect {
    // left
    if (svFrame.origin.x > 0) {
        [self drawBackgroundInRect:NSMakeRect(0, 0, svFrame.origin.x, self.frame.size.height)];
    }

    // right
    if (svFrame.size.width < self.frame.size.width) {
        double widthDiff = self.frame.size.width - svFrame.size.width;
        [self drawBackgroundInRect:NSMakeRect(self.frame.size.width - widthDiff,
                                              0,
                                              widthDiff,
                                              self.frame.size.height)];
    }
    // bottom
    if (svFrame.origin.y != 0) {
        [self drawBackgroundInRect:NSMakeRect(0, 0, self.frame.size.width, svFrame.origin.y)];
    }

    // top
    if (NSMaxY(svFrame) < self.frame.size.height) {
        [self drawBackgroundInRect:NSMakeRect(dirtyRect.origin.x,
                                              NSMaxY(svFrame),
                                              dirtyRect.size.width,
                                              self.frame.size.height - NSMaxY(svFrame))];
    }
}

- (NSRect)contentRect {
    if (_showTitle) {
        return NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height - kTitleHeight);
    } else {
        return self.frame;
    }
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

- (void)setHoverURL:(NSString *)url {
    if (_hoverURLView == nil) {
        if (url == nil) {
            return;
        }
        _hoverURLView = [[iTermHoverContainerView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        _hoverURLTextField = [[NSTextField alloc] initWithFrame:_hoverURLView.bounds];
        [_hoverURLTextField setDrawsBackground:NO];
        [_hoverURLTextField setBordered:NO];
        [_hoverURLTextField setEditable:NO];
        [_hoverURLTextField setSelectable:NO];
        [_hoverURLTextField setStringValue:url];
        [_hoverURLTextField setAlignment:NSTextAlignmentLeft];
        [_hoverURLTextField setAutoresizingMask:NSViewWidthSizable];
        [_hoverURLTextField setTextColor:[NSColor headerTextColor]];
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
        // _hoveurlView != nil && url != nil
        [_hoverURLTextField setStringValue:url];
    }

    [self updateLayout];
}

- (void)viewDidMoveToWindow {
    [_delegate sessionViewDidChangeWindow];
}

- (PTYScroller *)verticalScroller {
    return [PTYScroller castFrom:self.scrollview.verticalScroller];
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
    return [_delegate sessionViewPerformDragOperation:sender];
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
        frame.size.height -= kTitleHeight;
        _title = [[SessionTitleView alloc] initWithFrame:NSMakeRect(0,
                                                                    self.frame.size.height - kTitleHeight,
                                                                    self.frame.size.width,
                                                                    kTitleHeight)];
        [self invalidateStatusBar];
        if (adjustScrollView) {
            [_title setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        }
        _title.delegate = self;
        [_title setDimmingAmount:[self adjustedDimmingAmount]];
        [self addSubviewBelowFindView:_title];
    } else {
        frame.size.height += kTitleHeight;
        [_title removeFromSuperview];
        _title = nil;
    }
    if (adjustScrollView) {
        [scrollView setFrame:frame];
    } else {
        [self updateTitleFrame];
    }
    [self setTitle:[_delegate sessionViewTitle]];
    [self updateScrollViewFrame];
    [self invalidateStatusBar];
    return YES;
}

- (void)invalidateStatusBar {
    iTermStatusBarViewController *newVC = [self.delegate sessionViewStatusBarViewController];
    if (newVC != _title.statusBarViewController) {
        _title.statusBarViewController = newVC;
        if (newVC.searchViewController) {
            _findDriver = iTermSessionViewFindDriverPermanentStatusBar;
            _permanentStatusBarFindDriver = [[iTermFindDriver alloc] initWithViewController:newVC.searchViewController];
            _permanentStatusBarFindDriver.delegate = self.findDriverDelegate;
        } else if (newVC) {
            _findDriver = iTermSessionViewFindDriverTemporaryStatusBar;
        } else {
            _findDriver = iTermSessionViewFindDriverDropDown;
        }
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
    NSSize innerSize = NSMakeSize(cellSize.width * dim.width + [iTermAdvancedSettingsModel terminalMargin] * 2,
                                  cellSize.height * dim.height + [iTermAdvancedSettingsModel terminalVMargin] * 2);
    const BOOL hasScrollbar = [[self scrollview] hasVerticalScroller];
    NSSize size =
        [PTYScrollView frameSizeForContentSize:innerSize
                       horizontalScrollerClass:nil
                         verticalScrollerClass:(hasScrollbar ? [PTYScroller class] : nil)
                                    borderType:NSNoBorder
                                   controlSize:NSControlSizeRegular
                                 scrollerStyle:[[self scrollview] scrollerStyle]];

    if (_showTitle) {
        size.height += kTitleHeight;
    }
    DLog(@"Smallest such frame is %@", NSStringFromSize(size));
    return size;
}

- (NSSize)maximumPossibleScrollViewContentSize {
    NSSize size = self.frame.size;
    DLog(@"maximumPossibleScrollViewContentSize. size=%@", [NSValue valueWithSize:size]);
    if (_showTitle) {
        size.height -= kTitleHeight;
        DLog(@"maximumPossibleScrollViewContentSize: sub title height. size=%@", [NSValue valueWithSize:size]);
    }

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
    return contentSize;
}

- (void)updateTitleFrame {
    NSRect aRect = [self frame];
    if (_showTitle) {
        [_title setFrame:NSMakeRect(0,
                                    aRect.size.height - kTitleHeight,
                                    aRect.size.width,
                                    kTitleHeight)];
        NSViewController *viewController = [self.delegate sessionViewStatusBarViewController];
        
        [[viewController view] setNeedsLayout:YES];
    }
    [self updateScrollViewFrame];
    [self updateFindViewFrame];
}

- (void)updateFindViewFrame {
    NSRect aRect = self.frame;
    NSView *findView = _dropDownFindViewController.view;
    [_dropDownFindViewController setFrameOrigin:NSMakePoint(aRect.size.width - [findView frame].size.width - 30,
                                                            aRect.size.height - [findView frame].size.height)];
}

- (void)updateScrollViewFrame {
    CGFloat titleHeight = _showTitle ? _title.frame.size.height : 0;
    NSSize proposedSize = NSMakeSize(self.frame.size.width,
                                     self.frame.size.height - titleHeight);
    NSSize size = [_delegate sessionViewScrollViewWillResize:proposedSize];
    NSRect rect = NSMakeRect(0, proposedSize.height - size.height, size.width, size.height);
    [self scrollview].frame = rect;

    rect.origin = NSZeroPoint;
    rect.size.width = _scrollview.contentSize.width;
    rect.size.height = [_delegate sessionViewDesiredHeightOfDocumentView];
    [_scrollview.documentView setFrame:rect];
    if (_useMetal) {
        [self updateMetalViewFrame];
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

- (BOOL)sessionTitleViewIsFirstResponder {
    return [_delegate sessionViewTerminalIsFirstResponder];
}

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

- (void)addAnnouncement:(iTermAnnouncementViewController *)announcement {
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
        _currentAnnouncement.view.frame = initialRect;

        [_currentAnnouncement.view.animator setFrame:finalRect];

        _currentAnnouncement.view.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [_currentAnnouncement didBecomeVisible];
        [self addSubviewBelowFindView:_currentAnnouncement.view];
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

- (BOOL)continueFind:(double *)progress {
    return [self.delegate continueFind:progress];
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
    [self.delegate findViewControllerClearSearch];
    _title.statusBarViewController.temporaryLeftComponent = nil;
}

- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset {
    [self.delegate findString:aString
             forwardDirection:direction
                         mode:mode
                   withOffset:offset];
}

- (void)findViewControllerVisibilityDidChange:(id<iTermFindViewController>)sender {
    [self.delegate findViewControllerVisibilityDidChange:sender];
}

@end
