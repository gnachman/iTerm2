//
//  iTermGenericStatusBarContainer.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermGenericStatusBarContainer.h"

#import "iTermNotificationCenter.h"
#import "iTermPreferences.h"
#import "NSView+iTerm.h"

@interface iTermStatusBarBacking : NSVisualEffectView
@end

@implementation iTermStatusBarBacking
@end

@implementation iTermGenericStatusBarContainer {
    iTermStatusBarBacking *_backing NS_AVAILABLE_MAC(10_14);
}

@synthesize statusBarViewController = _statusBarViewController;

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutStatusBar];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutStatusBar];
}

- (void)setStatusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    [_statusBarViewController.view removeFromSuperview];
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
                                   iTermStatusBarHeight);
    _backing.frame = rect;
    _statusBarViewController.view.frame = rect;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[self.delegate genericStatusBarContainerBackgroundColor] set];
    NSRectFill(dirtyRect);
}

- (void)updateBackingVisible {
    if (@available(macOS 10.14, *)) {
        switch ((iTermPreferencesTabStyle)[iTermPreferences intForKey:kPreferenceKeyTabStyle]) {
            case TAB_STYLE_MINIMAL:
                _backing.hidden = YES;
                break;

            case TAB_STYLE_DARK:
            case TAB_STYLE_LIGHT:
            case TAB_STYLE_AUTOMATIC:
            case TAB_STYLE_DARK_HIGH_CONTRAST:
            case TAB_STYLE_LIGHT_HIGH_CONTRAST:
                _backing.hidden = NO;
        }
    }
}

- (void)viewDidMoveToWindow {
    if (!_backing) {
        if (@available(macOS 10.14, *)) {
            _backing = [[iTermStatusBarBacking alloc] init];
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

@end
