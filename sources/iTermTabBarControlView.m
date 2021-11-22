//
//  iTermTabBarControlView.m
//  iTerm
//
//  Created by George Nachman on 5/29/14.
//
//

#import "iTermTabBarControlView.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWindow+iTerm.h"

@interface NSView (Private)
- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar;
@end

typedef NS_ENUM(NSInteger, iTermTabBarFlashState) {
    kFlashOff,
    kFlashHolding,  // Regular delay
    kFlashExtending,  // Staying on because cmd pressed
    kFlashFadingOut,
};

@interface iTermTabBarControlView ()
@property(nonatomic, assign) iTermTabBarFlashState flashState;
@end

@implementation iTermTabBarControlView {
    iTermDelayedPerform *_flashDelayedPerform;  // weak
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setTabsHaveCloseButtons:[iTermPreferences boolForKey:kPreferenceKeyTabsHaveCloseButton]];
        self.minimumTabDragDistance = [iTermAdvancedSettingsModel minimumTabDragDistance];
        // This used to depend on job but it's too difficult to do now that different sessions might
        // have different title formats.
        self.ignoreTrailingParentheticalsForSmartTruncation = YES;
        self.height = [iTermAdvancedSettingsModel defaultTabBarHeight];
        self.showAddTabButton = YES;
        self.selectsTabsOnMouseDown = [iTermAdvancedSettingsModel selectsTabsOnMouseDown];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
}

- (void)setCmdPressed:(BOOL)cmdPressed {
    if (cmdPressed == _cmdPressed) {
        return;
    }
    _cmdPressed = cmdPressed;
    DLog(@"Set cmdPressed=%d", (int)cmdPressed);
    switch (self.flashState) {
        case kFlashOff:
            break;

        case kFlashHolding:
            break;

        case kFlashExtending:
            if (!cmdPressed) {
                [self setFlashing:NO];
            }
            break;

        case kFlashFadingOut:
            break;
    }
}

- (BOOL)flashing {
    return self.flashState != kFlashOff;
}

- (void)cancelFadeOut {
    // Cancel fade out so a new timer can be started below, in case we were already holding or
    // fading in.
    DLog(@"Cancel fade out %@", _flashDelayedPerform);
    _flashDelayedPerform.canceled = YES;
    _flashDelayedPerform = nil;
}

- (void)setAlphaValue:(CGFloat)alphaValue animated:(BOOL)animated {
    if ([self.superview conformsToProtocol:@protocol(iTermTabBarControlViewContainer)]) {
        if (animated) {
            self.superview.animator.alphaValue = alphaValue;
        } else {
            self.superview.alphaValue = alphaValue;
        }
        [super setAlphaValue:1.0];
    } else {
        if (animated) {
            NSView *animator = self.animator;
            animator.alphaValue = alphaValue;
        } else {
            [self setAlphaValue:alphaValue];
        }
    }
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden || [self.itermTabBarDelegate iTermTabBarShouldHideBacking]) {
        if ([self.superview conformsToProtocol:@protocol(iTermTabBarControlViewContainer)]) {
            id<iTermTabBarControlViewContainer> container = (id<iTermTabBarControlViewContainer>)self.superview;
            [container tabBarControlViewWillHide:hidden];
        }
    }
    [super setHidden:hidden];
}

- (void)fadeIn {
    DLog(@"fade in");
    self.flashState = kFlashHolding;
    [_itermTabBarDelegate iTermTabBarWillBeginFlash];
    [self setAlphaValue:1.0 animated:NO];
}

- (void)scheduleFadeOutAfterDelay {
    DLog(@"schedule fade out after delay");
    // Schedule a fade out. This can be canceled.
    [self retain];
    __block BOOL aborted = NO;
    _flashDelayedPerform = [NSView animateWithDuration:[iTermAdvancedSettingsModel tabFlashAnimationDuration]
                                                 delay:[iTermAdvancedSettingsModel tabAutoShowHoldTime]
                                            animations:^{
                                                if (!_cmdPressed) {
                                                    DLog(@"delayed fade out running");
                                                    self.flashState = kFlashFadingOut;
                                                    [self setAlphaValue:0 animated:YES];
                                                } else {
                                                    DLog(@"delayed fade out aborted; extending");
                                                    self.flashState = kFlashExtending;
                                                    aborted = YES;
                                                }
                                            }
                                            completion:^(BOOL finished) {
                                                if (!aborted) {
                                                    DLog(@"delayed fade out completed");
                                                    if (finished && self.flashState == kFlashFadingOut) {
                                                        self.flashState = kFlashOff;
                                                        [_itermTabBarDelegate iTermTabBarDidFinishFlash];
                                                    }
                                                }
                                                if (_flashDelayedPerform.completed) {
                                                    _flashDelayedPerform = nil;
                                                }
                                                [self release];
                                            }];
    DLog(@"Schedule dp %@", _flashDelayedPerform);
}

- (void)stopFlashInstantly {
    DLog(@"stop flashing instantly");
    // Quickly stop flash.
    [self setAlphaValue:1.0 animated:NO];
    self.flashState = kFlashOff;
    _flashDelayedPerform.canceled = YES;
    _flashDelayedPerform = nil;
    [_itermTabBarDelegate iTermTabBarDidFinishFlash];
}

- (void)fadeOut {
    DLog(@"fade out");
    // If there is a delayed perform to fade out, cancel that so we don't try to fade out twice.
    _flashDelayedPerform.canceled = YES;
    _flashDelayedPerform = nil;

    [self retain];
    [NSView animateWithDuration:[iTermAdvancedSettingsModel tabFlashAnimationDuration]
                     animations:^{
                         self.flashState = kFlashFadingOut;
                         [self setAlphaValue:0 animated:YES];
                     }
                     completion:^(BOOL finished) {
                         if (finished && self.flashState == kFlashFadingOut) {
                             self.flashState = kFlashOff;
                             [_itermTabBarDelegate iTermTabBarDidFinishFlash];
                         }
                         [self release];
                     }];
}

- (void)setFlashing:(BOOL)flashing {
    flashing &= [_itermTabBarDelegate iTermTabBarShouldFlashAutomatically];
    DLog(@"Set flashing to %d", (int)flashing);
    if (flashing) {
        switch (self.flashState) {
            case kFlashOff:
            case kFlashFadingOut:
                [self fadeIn];
                [self cancelFadeOut];
                [self scheduleFadeOutAfterDelay];
                break;

            case kFlashHolding:
                // Restart the timer.
                [self cancelFadeOut];
                [self scheduleFadeOutAfterDelay];
                break;

            case kFlashExtending:
                break;
        }
    } else {
        switch (self.flashState) {
            case kFlashOff:
                break;

            case kFlashHolding:
            case kFlashExtending:
                [self fadeOut];
                break;

            case kFlashFadingOut:
                [self stopFlashInstantly];
                break;
        }
    }
}

- (void)updateFlashing {
    if ([self flashing] &&
        ![_itermTabBarDelegate iTermTabBarShouldFlashAutomatically]) {
        [self setFlashing:NO];
    }
}

- (void)setOrientation:(PSMTabBarOrientation)orientation {
    [super setOrientation:orientation];
    self.showAddTabButton = (orientation == PSMTabBarHorizontalOrientation);
}

#pragma mark - Private

- (void)setFlashState:(iTermTabBarFlashState)flashState {
    NSArray *names = @[ @"Off", @"FadeIn", @"Holding", @"Extending", @"FadeOut" ];
    DLog(@"%@ -> %@ from\n%@", names[self.flashState], names[flashState], [NSThread callStackSymbols]);
    _flashState = flashState;
}

#pragma mark - Window Dragging

- (BOOL)mouseDownCanMoveWindow {
    return [self.itermTabBarDelegate iTermTabBarCanDragWindow] ? NO : [super mouseDownCanMoveWindow];
}

- (NSRect)_opaqueRectForWindowMoveWhenInTitlebar {
    return [self.itermTabBarDelegate iTermTabBarCanDragWindow] ? self.bounds : [super _opaqueRectForWindowMoveWhenInTitlebar];
}

- (void)mouseDown:(NSEvent *)event {
    if (![self.itermTabBarDelegate iTermTabBarCanDragWindow]) {
        [super mouseDown:event];
        return;
    }

    NSView *superview = [self superview];
    NSPoint hitLocation = [[superview superview] convertPoint:[event locationInWindow]
                                                     fromView:nil];
    NSView *hitView = [superview hitTest:hitLocation];

    NSPoint pointInView = [self convertPoint:event.locationInWindow fromView:nil];
    const BOOL handleDrag = ([self.itermTabBarDelegate iTermTabBarCanDragWindow] &&
                             ![self wantsMouseDownAtPoint:pointInView] &&
                             hitView == self &&
                             ![self.itermTabBarDelegate iTermTabBarWindowIsFullScreen]);
    if (handleDrag) {
        [self.window makeKeyAndOrderFront:nil];
        [self.window performWindowDragWithEvent:event];
        return;
    }
    
    [super mouseDown:event];
}

- (BOOL)clickedInCell:(NSEvent *)event {
    const NSPoint clickPoint = [self convertPoint:event.locationInWindow
                                         fromView:nil];
    NSRect cellFrame;
    PSMTabBarCell *const cell = [self cellForPoint:clickPoint
                                         cellFrame:&cellFrame];
    return cell != nil;
}

- (void)mouseUp:(NSEvent *)event {
    if (event.clickCount == 2 &&
        [self.itermTabBarDelegate iTermTabBarCanDragWindow] &&
        ![self clickedInCell:event]) {
        [self.window it_titleBarDoubleClick];
        return;
    }
    [super mouseUp:event];
}

@end
