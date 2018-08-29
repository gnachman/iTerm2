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

CGFloat iTermTabBarControlViewDefaultHeight = 24;

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
        [self setTabsHaveCloseButtons:![iTermAdvancedSettingsModel eliminateCloseButtons]];
        self.minimumTabDragDistance = [iTermAdvancedSettingsModel minimumTabDragDistance];
        // This used to depend on job but it's too difficult to do now that different sessions might
        // have different title formats.
        self.ignoreTrailingParentheticalsForSmartTruncation = YES;
        self.height = iTermTabBarControlViewDefaultHeight;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor windowBackgroundColor] set];
    NSRectFill(dirtyRect);

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

- (void)fadeIn {
    DLog(@"fade in");
    self.flashState = kFlashHolding;
    [_itermTabBarDelegate iTermTabBarWillBeginFlash];
    self.alphaValue = 1;
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
                                                    [self.animator setAlphaValue:0];
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
    self.alphaValue = 1;
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
                         [self.animator setAlphaValue:0];
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
        [self trackClickForWindowMove:event];
        return;
    }
    
    [super mouseDown:event];
}

- (void)trackClickForWindowMove:(NSEvent*)event {
    NSWindow *window = self.window;
    NSPoint origin = [window frame].origin;
    NSPoint lastPointInScreenCoords = [NSEvent mouseLocation];
    const NSEventMask eventMask = (NSEventMaskLeftMouseDown |
                                   NSEventMaskLeftMouseDragged |
                                   NSEventMaskLeftMouseUp);
    event = [NSApp nextEventMatchingMask:eventMask
                               untilDate:[NSDate distantFuture]
                                  inMode:NSEventTrackingRunLoopMode
                                 dequeue:YES];
    while (event && event.type != NSEventTypeLeftMouseUp) {
        @autoreleasepool {
            NSPoint currentPointInScreenCoords = [NSEvent mouseLocation];
            
            origin.x += currentPointInScreenCoords.x - lastPointInScreenCoords.x;
            origin.y += currentPointInScreenCoords.y - lastPointInScreenCoords.y;
            lastPointInScreenCoords = currentPointInScreenCoords;
            
            [window setFrameOrigin:origin];
            
            event = [NSApp nextEventMatchingMask:eventMask
                                       untilDate:[NSDate distantFuture]
                                          inMode:NSEventTrackingRunLoopMode
                                         dequeue:YES];
        }
    }
}

@end
