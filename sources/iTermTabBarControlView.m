//
//  iTermTabBarControlView.m
//  iTerm
//
//  Created by George Nachman on 5/29/14.
//
//

#import "iTermTabBarControlView.h"
#import "iTermAdvancedSettingsModel.h"
#import "DebugLogging.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"

typedef NS_ENUM(NSInteger, iTermTabBarFlashState) {
    kFlashOff,
    kFlashFadingIn,
    kFlashHolding,
    kFlashFadingOut,
};

static const NSTimeInterval kAnimationDuration = 0.25;
static const NSTimeInterval kFlashHoldTime = 1;

@interface iTermTabBarControlView ()
@property(nonatomic, assign) iTermTabBarFlashState flashState;
@end

@implementation iTermTabBarControlView {
    BOOL _showingBecauseCmdHeld;
    iTermDelayedPerform *_flashDelayedPerform;  // weak
    iTermDelayedPerform *_cmdPressedDelayedPerform;  // weak
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setTabsHaveCloseButtons:![iTermAdvancedSettingsModel eliminateCloseButtons]];
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
    if (cmdPressed) {
        _cmdPressedDelayedPerform =
                [self performBlock:^{
                    if (_cmdPressed) {
                        _showingBecauseCmdHeld = YES;
                        self.flashing = YES;
                    }
                    if (_cmdPressedDelayedPerform.completed) {
                        _cmdPressedDelayedPerform = nil;
                    }
                }
                        afterDelay:[_itermTabBarDelegate iTermTabBarCmdPressDuration]];
    } else {
        _cmdPressedDelayedPerform.canceled = YES;
        _cmdPressedDelayedPerform = nil;
        if (_showingBecauseCmdHeld) {
            self.flashing = NO;
            _showingBecauseCmdHeld = NO;
        }
    }
}

- (BOOL)flashing {
    return self.flashState != kFlashOff;
}

- (void)setFlashing:(BOOL)flashing {
    if (![_itermTabBarDelegate iTermTabBarShouldFlash]) {
        if (!flashing && self.flashState != kFlashOff) {
            // Quickly stop flash.
            self.alphaValue = 1;
            self.flashState = kFlashOff;
            _flashDelayedPerform.canceled = YES;
            _flashDelayedPerform = nil;
            [_itermTabBarDelegate iTermTabBarDidFinishFlash];
        }
        return;
    }

    if (flashing) {
        if (self.flashState == kFlashOff || self.flashState == kFlashFadingOut) {
            // Fade in.
            [self retain];
            [NSView animateWithDuration:kAnimationDuration
                             animations:^{
                                 self.flashState = kFlashFadingIn;
                                 [_itermTabBarDelegate iTermTabBarWillBeginFlash];
                                 [self.animator setAlphaValue:1];
                             }
                             completion:^(BOOL finished) {
                                 if (self.flashState == kFlashFadingIn) {
                                     self.flashState = kFlashHolding;
                                 }
                                 [self release];
                             }];
        }

        // Cancel fade out so a new timer can be started below, in case we were already holding or
        // fading in.
        DLog(@"Cancel dp %@", _flashDelayedPerform);
        _flashDelayedPerform.canceled = YES;
        _flashDelayedPerform = nil;

        if (!_showingBecauseCmdHeld) {
            // Schedule a fade out. This can be canceled.
            [self retain];
            _flashDelayedPerform = [NSView animateWithDuration:kAnimationDuration
                                                         delay:kFlashHoldTime
                                                    animations:^{
                                                        self.flashState = kFlashFadingOut;
                                                      [self.animator setAlphaValue:0];
                                                    }
                                                    completion:^(BOOL finished) {
                                                        if (finished && self.flashState == kFlashFadingOut) {
                                                            self.flashState = kFlashOff;
                                                            [_itermTabBarDelegate iTermTabBarDidFinishFlash];
                                                        }
                                                        if (_flashDelayedPerform.completed) {
                                                            _flashDelayedPerform = nil;
                                                        }
                                                        [self release];
                                                    }];
            DLog(@"Schedule dp %@", _flashDelayedPerform);
        }
    } else if (self.flashState == kFlashFadingIn || self.flashState == kFlashHolding) {
        // Fade out (in practice, it's because cmd was released).

        // If there is a delayed perform to fade out, cancel that so we don't try to fade out twice.
        _flashDelayedPerform.canceled = YES;
        _flashDelayedPerform = nil;

        [self retain];
        [NSView animateWithDuration:kAnimationDuration
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
}

- (void)updateFlashing {
    if ([self flashing] && ![_itermTabBarDelegate iTermTabBarShouldFlash]) {
        self.flashing = NO;
    }
}

#pragma mark - Private

- (void)setFlashState:(iTermTabBarFlashState)flashState {
    NSArray *names = @[ @"Off", @"FadeIn", @"Holding", @"FadeOut" ];
    DLog(@"Flash state -> %@", names[flashState]);
    _flashState = flashState;
}

@end
