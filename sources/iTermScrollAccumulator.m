//
//  iTermScrollAccumulator.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/24/18.
//
// Scroll wheels on macOS are a total shitshow. If you want to understand them read anything but
// the documentation, which is worthless. Here are some useful things which kind of hint at what
// might be going on:
//
// https://chromium.googlesource.com/chromium/blink/+/d40e271ac1613cea1a24eac3cca6efe173cd0696/Source/WebKit/chromium/src/mac/WebInputEventFactory.mm
// https://developer.apple.com/library/content/releasenotes/AppKit/RN-AppKitOlderNotes/

#import "iTermScrollAccumulator.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

// When scrolling ends if the magnitude of the accumulated value is more than 0 but less than this,
// return 1 or -1.
static const CGFloat iTermScrollAccumulatorRoundUpThreshold = 0.1;

@implementation iTermScrollAccumulator {
    CGFloat _accumulatedDeltaY;
    BOOL _shouldAccumulate;
    CGFloat _lineHeight;

    // 0: not initialized
    // 1: last direction was a positive delta
    // -1: last direction was a negative delta
    // Gets reset to 0 when scrolling ends
    NSInteger _lastDirection;
}

- (CGFloat)deltaYForEvent:(NSEvent *)event lineHeight:(CGFloat)lineHeight {
    _lineHeight = lineHeight;
    switch (event.type) {
        case NSEventTypeScrollWheel: {
            CGFloat result;
            result = [self accumulatedDeltaYForScrollEvent:event];
            if (event.phase == NSEventPhaseEnded) {
                _lastDirection = 0;
            } else if (result > 0) {
                _lastDirection = 1;
            } else if (result < 0) {
                _lastDirection = -1;
            }
            DLog(@"deltaYForEvent:%@ lineHeight:%@ -> %@. deltaY=%@ scrollingDeltaY=%@ Accumulator <- %@",
                 event, @(lineHeight), @(result), @(event.deltaY), @(event.scrollingDeltaY), @(_accumulatedDeltaY));
            return result;
        }

        default:
            return 0;
    }
}

// Get a delta Y out of the event with the most precision available and a consistent interpretation.
- (CGFloat)adjustedDeltaYForEvent:(NSEvent *)event {
    if (event.hasPreciseScrollingDeltas) {
        return event.scrollingDeltaY / _lineHeight;
    } else {
        return event.scrollingDeltaY;
    }
}

// Non-trackpad code path
- (CGFloat)accumulatedDeltaYForMouseWheelEvent:(NSEvent *)event {
    const CGFloat deltaY = [self adjustedDeltaYForEvent:event];
    const int roundDeltaY = round(deltaY);
    if (roundDeltaY == 0 && deltaY != 0) {
        return deltaY > 0 ? 1 : -1;
    } else {
        return roundDeltaY;
    }
}

- (BOOL)shouldBeginAccumulatingForEvent:(NSEvent *)event {
    return event.phase == NSEventPhaseBegan;
}

- (BOOL)shouldEndAccumulatingForEvent:(NSEvent *)event {
    const NSEventPhase phase = event.phase;
    return phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled;
}

- (CGFloat)accumulatedDeltaYForTrackpadEvent:(NSEvent *)event {
    if ([self shouldBeginAccumulatingForEvent:event]) {
        _accumulatedDeltaY = 0;
    }
    const CGFloat delta = [self adjustedDeltaYForEvent:event];
    _accumulatedDeltaY += delta;
    const CGFloat absAccumulatedDelta = fabs(_accumulatedDeltaY);
    int roundDelta;

    if (absAccumulatedDelta > 0.5) {
        // The rounded accumulated value will not be zero so consume it.
        roundDelta = round(_accumulatedDeltaY);
        _accumulatedDeltaY -= roundDelta;
    } else {
        // Even if the accumulated value is near 0, the delta might not be (e.g., if you just
        // changed directions) so return its rounded value. This will typically be 0, though.
        roundDelta = round(delta);
    }

    if ([self shouldEndAccumulatingForEvent:event]) {
        if (roundDelta == 0 && absAccumulatedDelta > iTermScrollAccumulatorRoundUpThreshold) {
            int proposedResult = _accumulatedDeltaY > 0 ? 1 : -1;

            // Don't allow this to reverse direction. You could be getting all positive
            // scrollingDeltaY's and have a negative accumulator (since an accumulator of
            // 0.51 would round to 1, we would output a movement of 1 and drop the
            // accumulator to -0.49). If you end in such a state. just stop instead of
            // outputting a value that scrolls once in the wrong direction.
            if (_lastDirection == 0 ||
                (proposedResult > 0) == (_lastDirection > 0)) {
                roundDelta = proposedResult;
            } else {
                roundDelta = 0;
            }
        }
    }
    return roundDelta;
}

- (CGFloat)accumulatedDeltaYForScrollEvent:(NSEvent *)event {
    if (event.phase == NSEventPhaseNone && event.momentumPhase == NSEventPhaseNone) {
        // Mouse wheel
        return [self accumulatedDeltaYForMouseWheelEvent:event];
    } else {
        // Something modern like a trackpad
        return [self accumulatedDeltaYForTrackpadEvent:event];
    }
}

- (void)reset {
    _accumulatedDeltaY = 0;
}

static CGFloat RoundTowardZero(CGFloat value) {
    if (value > 0) {
        return floor(value);
    } else {
        return ceil(value);
    }
}

- (CGFloat)legacyDeltaYForEvent:(NSEvent *)theEvent lineHeight:(CGFloat)lineHeight {
    CGFloat delta = theEvent.scrollingDeltaY;
    if (theEvent.hasPreciseScrollingDeltas) {
        delta /= lineHeight;
    }
    if ([iTermAdvancedSettingsModel sensitiveScrollWheel]) {
        if (delta > 0) {
            return ceil(delta);
        } else if (delta < 0) {
            return floor(delta);
        } else {
            return 0;
        }
    }
    _accumulatedDeltaY += delta;
    CGFloat amount = 0;
    if (fabs(_accumulatedDeltaY) >= 1) {
        amount = RoundTowardZero(_accumulatedDeltaY);
        _accumulatedDeltaY = _accumulatedDeltaY - amount;
    }
    return amount;
}

@end
