//
//  iTermCursorBlinkFadeAnimator.m
//  iTerm2
//

#import "iTermCursorBlinkFadeAnimator.h"

@implementation iTermCursorBlinkFadeAnimator {
    BOOL _active;                  // YES while a blink cycle is running.
    CFTimeInterval _cycleStartTime;  // When the current cycle began (fully visible).
    BOOL _wantsRedraw;
    CFTimeInterval _timeUntilNextFrame;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fadeInDuration = 0.2;
        _fadeOutDuration = 0.2;
        _fadeInCurve = iTermCursorBlinkFadeCurveEaseInOut;
        _fadeOutCurve = iTermCursorBlinkFadeCurveEaseInOut;
        _visibleDwellDuration = 0.3;
        _hiddenDwellDuration = 0.3;
    }
    return self;
}

- (BOOL)wantsRedraw {
    return _wantsRedraw;
}

- (CFTimeInterval)timeUntilNextFrame {
    return _timeUntilNextFrame;
}

- (void)reset {
    _active = NO;
    _wantsRedraw = NO;
    _timeUntilNextFrame = 0;
}

- (CGFloat)alphaForBlinking:(BOOL)blinking atTime:(CFTimeInterval)now {
    if (!blinking) {
        _active = NO;
        _wantsRedraw = NO;
        _timeUntilNextFrame = 0;
        return 1.0;
    }

    if (!_active) {
        // Blinking just started. The cursor is solid right now, so begin the
        // cycle at the start of the visible dwell.
        _active = YES;
        _cycleStartTime = now;
    }

    const CFTimeInterval visibleDwell = MAX(0, _visibleDwellDuration);
    const CFTimeInterval fadeOut = MAX(0, _fadeOutDuration);
    const CFTimeInterval hiddenDwell = MAX(0, _hiddenDwellDuration);
    const CFTimeInterval fadeIn = MAX(0, _fadeInDuration);
    const CFTimeInterval period = visibleDwell + fadeOut + hiddenDwell + fadeIn;

    if (period <= 0) {
        // No timings configured: stay solid and don't drive redraws.
        _wantsRedraw = NO;
        _timeUntilNextFrame = 0;
        return 1.0;
    }

    _wantsRedraw = YES;

    CFTimeInterval phase = fmod(now - _cycleStartTime, period);
    if (phase < 0) {
        phase += period;
    }

    // Cycle layout: [visible dwell][fade out][hidden dwell][fade in].
    const CFTimeInterval endVisibleDwell = visibleDwell;
    const CFTimeInterval endFadeOut = endVisibleDwell + fadeOut;
    const CFTimeInterval endHiddenDwell = endFadeOut + hiddenDwell;

    CGFloat alpha;
    if (phase < endVisibleDwell) {
        alpha = 1.0;
        _timeUntilNextFrame = endVisibleDwell - phase;  // Sleep until the fade-out begins.
    } else if (phase < endFadeOut) {
        const CGFloat t = (fadeOut > 0) ? (phase - endVisibleDwell) / fadeOut : 1.0;
        alpha = 1.0 - [iTermCursorBlinkFadeAnimator easedProgressForCurve:_fadeOutCurve atProgress:t];
        _timeUntilNextFrame = 0;  // Animate every frame.
    } else if (phase < endHiddenDwell) {
        alpha = 0.0;
        _timeUntilNextFrame = endHiddenDwell - phase;  // Sleep until the fade-in begins.
    } else {
        const CGFloat t = (fadeIn > 0) ? (phase - endHiddenDwell) / fadeIn : 1.0;
        alpha = [iTermCursorBlinkFadeAnimator easedProgressForCurve:_fadeInCurve atProgress:t];
        _timeUntilNextFrame = 0;  // Animate every frame.
    }
    return MAX(0.0, MIN(1.0, alpha));
}

+ (CGFloat)easedProgressForCurve:(iTermCursorBlinkFadeCurve)curve atProgress:(CGFloat)t {
    switch (curve) {
        case iTermCursorBlinkFadeCurveLinear:
            return t;
        case iTermCursorBlinkFadeCurveEaseIn:
            // Quadratic ease-in: slow start.
            return t * t;
        case iTermCursorBlinkFadeCurveEaseOut:
            // Quadratic ease-out: slow finish. Matches iTermCursorSlideAnimator.
            return 1.0 - (1.0 - t) * (1.0 - t);
        case iTermCursorBlinkFadeCurveEaseInOut: {
            // Quadratic ease-in-out: slow at both ends. Velocity is ~0 entering
            // and leaving each extreme, which is what makes the blink "breathe".
            if (t < 0.5) {
                return 2.0 * t * t;
            }
            const CGFloat u = -2.0 * t + 2.0;
            return 1.0 - u * u / 2.0;
        }
    }
    return t;
}

@end
