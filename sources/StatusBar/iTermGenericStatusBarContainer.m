//
//  iTermGenericStatusBarContainer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermGenericStatusBarContainer.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermPreferences.h"
#import "NSView+iTerm.h"

@interface iTermStatusBarBacking : NSVisualEffectView
@end

@implementation iTermStatusBarBacking
@end

@implementation iTermGenericStatusBarContainer {
    iTermStatusBarBacking *_backing;
}

@synthesize statusBarViewController = _statusBarViewController;

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        [self addFocusFollowsMouseTrackingArea];
    }
    return self;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutStatusBar];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutStatusBar];
}

- (void)setStatusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    if ([self containsDescendant:_statusBarViewController.view]) {
        [_statusBarViewController.view removeFromSuperview];
    }
    _statusBarViewController = statusBarViewController;
    if (statusBarViewController) {
        [self addSubview:statusBarViewController.view];
    }
    [self layoutStatusBar];
}

- (void)layoutStatusBar {
    const NSRect rect = NSMakeRect(0,
                                   0,
                                   self.frame.size.width,
                                   iTermGetStatusBarHeight());
    _backing.frame = rect;
    _statusBarViewController.view.frame = rect;
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    [[self.delegate genericStatusBarContainerBackgroundColor] set];
    NSRectFill(dirtyRect);
}

- (void)updateBackingVisible {
    switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
        case TAB_STYLE_MINIMAL:
            _backing.hidden = YES;
            break;

        case TAB_STYLE_DARK:
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            _backing.hidden = NO;
    }
}

- (BOOL)wantsDefaultClipping {
    return NO;
}

- (void)viewDidMoveToWindow {
    if (!_backing) {
        _backing = [[iTermStatusBarBacking alloc] init];
        _backing.wantsLayer = YES;
        _backing.layer.masksToBounds = NO;
        _backing.autoresizesSubviews = NO;
        _backing.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        _backing.material = NSVisualEffectMaterialTitlebar;
        _backing.state = NSVisualEffectStateActive;
        [self updateBackingVisible];
        [self insertSubview:_backing atIndex:0];
        __weak __typeof(self) weakSelf = self;
        [iTermPreferenceDidChangeNotification subscribe:self block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
            if ([notification.key isEqualToString:kPreferenceKeyTabStyle]) {
                [weakSelf updateBackingVisible];
            }
        }];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:self.window];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(redraw)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:self.window];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(redraw)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(redraw)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];
}

- (void)redraw {
    [self setNeedsDisplay:YES];
}

#pragma mark - Focus follows mouse

// The window's status bar is outside every pane, so it belongs to the session it shows.
- (id<PaneFocusFollowsMousePane>)it_focusFollowsMouseOwningPane {
    return [self.delegate genericStatusBarContainerFocusFollowsMousePane];
}

// No pane's tracking area covers the window's status bar, so focus follows mouse needs its own
// to notice the pointer moving onto or off of it.
- (void)addFocusFollowsMouseTrackingArea {
    const NSTrackingAreaOptions options = (NSTrackingMouseEnteredAndExited |
                                           NSTrackingMouseMoved |
                                           NSTrackingActiveAlways |
                                           NSTrackingEnabledDuringMouseDrag |
                                           NSTrackingInVisibleRect);
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:options
                                                         owner:self
                                                      userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event {
    DLog(@"mouseEntered %@", self);
    [[iTermPaneFocusFollowsMouse shared] pointerMoved];
}

- (void)mouseExited:(NSEvent *)event {
    DLog(@"mouseExited %@", self);
    [[iTermPaneFocusFollowsMouse shared] pointerMoved];
}

- (void)mouseMoved:(NSEvent *)event {
    iTermPaneFocusFollowsMouse *focusFollowsMouse = [iTermPaneFocusFollowsMouse shared];
    id<PaneFocusFollowsMousePane> pane = self.it_focusFollowsMouseOwningPane;
    if (pane && [focusFollowsMouse wantsPointerMovementFor:pane]) {
        // Moving onto the search field happens without an entered event.
        [focusFollowsMouse pointerMoved];
    }
}

@end
