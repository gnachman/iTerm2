//
//  iTermCursorBlinkFadeAnimator.h
//  iTerm2
//
//  Drives a smooth cursor blink: instead of toggling abruptly the cursor runs a
//  cycle of visible dwell -> fade out -> hidden dwell -> fade in, easing each
//  fade. It is a self-contained clock (not tied to the global blink toggle) so
//  the fade durations, easing curves, and dwell times are all independent. It
//  is a sibling of iTermCursorSlideAnimator and is used by both the legacy and
//  Metal rendering paths.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

// Easing applied while fading toward the target.
typedef NS_ENUM(NSInteger, iTermCursorBlinkFadeCurve) {
    iTermCursorBlinkFadeCurveLinear = 0,
    iTermCursorBlinkFadeCurveEaseIn = 1,     // Slow start, fast finish.
    iTermCursorBlinkFadeCurveEaseOut = 2,    // Fast start, slow finish.
    iTermCursorBlinkFadeCurveEaseInOut = 3,  // Slow start and finish. Pick this
                                             // for both directions to get a
                                             // gentle "breathing" blink.
};

@interface iTermCursorBlinkFadeAnimator : NSObject

// Duration in seconds of each fade.
@property (nonatomic) CFTimeInterval fadeInDuration;
@property (nonatomic) CFTimeInterval fadeOutDuration;
// Easing for the fade-in and fade-out, respectively.
@property (nonatomic) iTermCursorBlinkFadeCurve fadeInCurve;
@property (nonatomic) iTermCursorBlinkFadeCurve fadeOutCurve;
// How long to hold fully visible (alpha 1) and fully hidden (alpha 0) between
// fades, in seconds.
@property (nonatomic) CFTimeInterval visibleDwellDuration;
@property (nonatomic) CFTimeInterval hiddenDwellDuration;

// YES if the cursor is currently blinking and therefore wants the drawing code
// to schedule another redraw (after timeUntilNextFrame seconds). NO when not
// blinking, so the caller can stop the redraw loop.
@property (nonatomic, readonly) BOOL wantsRedraw;

// Seconds until the next redraw is worthwhile, as of the last
// alphaForBlinking:atTime: call. 0 during a fade (animate every frame) and the
// remaining dwell time during a dwell (sleep until the next fade begins).
@property (nonatomic, readonly) CFTimeInterval timeUntilNextFrame;

// Returns the cursor alpha in [0, 1] for the current point in the blink cycle.
// When `blinking` is NO the cursor is solid (returns 1) and the cycle resets so
// it starts fresh (fully visible) the next time blinking resumes. `now` is a
// CACurrentMediaTime()-style timestamp; it is a parameter so this can be tested
// deterministically.
- (CGFloat)alphaForBlinking:(BOOL)blinking atTime:(CFTimeInterval)now;

// Returns the eased fraction in [0, 1] for the given curve at normalized
// progress t in [0, 1]. Shared by the animator and by UI that visualizes the
// curve, so the picture always matches the behavior.
+ (CGFloat)easedProgressForCurve:(iTermCursorBlinkFadeCurve)curve atProgress:(CGFloat)t;

// Forget cycle state so the next blinking sample starts fresh from fully
// visible. Call when configuration changes.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
