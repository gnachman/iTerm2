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

static CGFloat RoundTowardZero(CGFloat value) {
    if (value > 0) {
        return floor(value);
    } else {
        return ceil(value);
    }
}

static CGFloat RoundAwayFromZero(CGFloat value) {
    if (value > 0) {
        return ceil(value);
    } else  {
        return floor(value);
    }
}

@implementation iTermScrollAccumulator {
    CGFloat _accumulatedDelta;
    BOOL _shouldAccumulate;
    CGFloat _lineHeight;
}

- (instancetype)init {
    if (self = [super init]) {
        _isVertical = YES;
        _sensitivity = 1.0;
    }
    return self;
}

- (CGFloat)deltaForEvent:(NSEvent *)event increment:(CGFloat)increment {
    _lineHeight = increment;
    switch (event.type) {
        case NSEventTypeScrollWheel: {
            CGFloat result;
            const CGFloat accumulatedDelta = [self accumulatedDeltaForScrollEvent:event];
            const CGFloat sign = (accumulatedDelta > 0) ? 1 : -1;
            const CGFloat factor = MAX(0, [iTermAdvancedSettingsModel scrollWheelAcceleration]);
            result = pow(fabs(accumulatedDelta), factor) * sign;
            DLog(@"deltaForEvent:%@ lineHeight:%@ ^ accel:%@ -> %@. delta=%@ scrollingDelta=%@ Accumulator <- %@",
                 event, @(increment), @([iTermAdvancedSettingsModel scrollWheelAcceleration]), @(result), @([self delta:event]), @([self scrollingDelta:event]), @(_accumulatedDelta));
            return result;
        }
            
        default:
            return 0;
    }
}

// Get a delta Y out of the event with the most precision available and a consistent interpretation.
- (CGFloat)adjustedDeltaForEvent:(NSEvent *)event {
    DLog(@"scrollingDelta=%@ delta=%@ lineHeight=%@ hasPreciseScrollingDeltas=%@ fastTrackpad=%@ _lineHeight=%@",
         @([self scrollingDelta:event]),
         @([self delta:event]),
         @(_lineHeight),
         @(event.hasPreciseScrollingDeltas),
         @([iTermAdvancedSettingsModel fastTrackpad]),
         @(_lineHeight));
    if (event.hasPreciseScrollingDeltas) {
        if ([iTermAdvancedSettingsModel fastTrackpad]) {
            // This is based on what Terminal.app does. See issue 9427.
            return RoundAwayFromZero([self delta:event]);
        }
        return [self scrollingDelta:event] / _lineHeight;
    } else {
        return [self scrollingDelta:event];
    }
}

// Non-trackpad code path
- (CGFloat)accumulatedDeltaForMouseWheelEvent:(NSEvent *)event {
    const CGFloat delta = [self adjustedDeltaForEvent:event];
    if (_sensitivity == 1.0) {
        const int roundDelta = round(delta);
        if (roundDelta == 0 && delta != 0) {
            return delta > 0 ? 1 : -1;
        } else {
            return roundDelta;
        }
    }
    _accumulatedDelta += delta * _sensitivity;
    return [self takeWholePortionWithDelta:delta];
}

- (BOOL)shouldBeginAccumulatingForEvent:(NSEvent *)event {
    return event.phase == NSEventPhaseBegan;
}

- (BOOL)shouldEndAccumulatingForEvent:(NSEvent *)event {
    const NSEventPhase phase = event.phase;
    return phase == NSEventPhaseEnded || phase == NSEventPhaseCancelled;
}

- (CGFloat)accumulatedDeltaForTrackpadEvent:(NSEvent *)event {
    if ([self shouldBeginAccumulatingForEvent:event]) {
        _accumulatedDelta = 0;
    }
    const CGFloat delta = [self adjustedDeltaForEvent:event] * _sensitivity;
    _accumulatedDelta += delta;
    return [self takeWholePortionWithDelta:delta];
}

- (CGFloat)takeWholePortionWithDelta:(CGFloat)delta {
    const CGFloat absAccumulatedDelta = fabs(_accumulatedDelta);
    int roundDelta;
    
    // Deltas will be accumulated into _accumulatedDelta.
    // If it is large (>=1), return its integer part. This enables quick scroll, which feels like natural trackpad.
    // If `delta * _accumulatedDelta < 0`, it means turnaround. Round delta to turn around quickly (fabs 0.5 is enough to move).
    // If it is not large enough, return 0 and keep accumulating.
    if (absAccumulatedDelta >= 1) {
        roundDelta = RoundTowardZero(_accumulatedDelta);
        _accumulatedDelta -= roundDelta;
    } else if (delta * _accumulatedDelta < 0) {
        roundDelta = round(delta);
        _accumulatedDelta = 0;
    } else {
        roundDelta = 0;
    }
    return roundDelta;
}

- (CGFloat)accumulatedDeltaForScrollEvent:(NSEvent *)event {
    if (event.phase == NSEventPhaseNone && event.momentumPhase == NSEventPhaseNone) {
        // Mouse wheel
        return [self accumulatedDeltaForMouseWheelEvent:event];
    } else {
        // Something modern like a trackpad
        return [self accumulatedDeltaForTrackpadEvent:event];
    }
}

- (void)reset {
    _accumulatedDelta = 0;
}

- (CGFloat)legacyDeltaForEvent:(NSEvent *)theEvent increment:(CGFloat)increment {
    CGFloat delta = [self scrollingDelta:theEvent] * _sensitivity;
    if (theEvent.hasPreciseScrollingDeltas) {
        delta /= increment;
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
    _accumulatedDelta += delta;
    CGFloat amount = 0;
    if (fabs(_accumulatedDelta) >= 1) {
        amount = RoundTowardZero(_accumulatedDelta);
        _accumulatedDelta = _accumulatedDelta - amount;
    }
    return amount;
}

- (CGFloat)delta:(NSEvent *)event {
    if (self.isVertical) {
        return event.deltaY;
    } else {
        return event.deltaX;
    }
}

- (CGFloat)scrollingDelta:(NSEvent *)event {
    if (self.isVertical) {
        return event.scrollingDeltaY;
    } else {
        return event.scrollingDeltaX;
    }
}

@end
