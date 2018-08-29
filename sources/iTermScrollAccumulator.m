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


@implementation iTermScrollAccumulator {
    CGFloat _accumulatedDeltaY;
    BOOL _shouldAccumulate;
    CGFloat _lineHeight;
}

- (CGFloat)deltaYForEvent:(NSEvent *)event lineHeight:(CGFloat)lineHeight {
    _lineHeight = lineHeight;
    switch (event.type) {
        case NSEventTypeScrollWheel: {
            CGFloat result;
            result = [self accumulatedDeltaYForScrollEvent:event];
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
    
    // Deltas will be accumulated into _accumulatedDeltaY.
    // If it is large (>1), return its integer part. This enables quick scroll, which feels like natural trackpad.
    // If `delta * _accumulatedDeltaY < 0`, it means turnaround. Round delta to turn around quickly (fabs 0.5 is enough to move).
    // If it is not large enough, return 0 and keep accumulating.
    if (absAccumulatedDelta > 1) {
        roundDelta = RoundTowardZero(_accumulatedDeltaY);
        _accumulatedDeltaY -= roundDelta;
    } else if (delta * _accumulatedDeltaY < 0) {
        roundDelta = round(delta);
    } else {
        roundDelta = 0;
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
