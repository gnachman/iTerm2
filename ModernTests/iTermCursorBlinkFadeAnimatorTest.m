//
//  iTermCursorBlinkFadeAnimatorTest.m
//  ModernTests
//

#import <XCTest/XCTest.h>

#import "iTermCursorBlinkFadeAnimator.h"
#import "iTermCursorBlinkFadePreset.h"

@interface iTermCursorBlinkFadeAnimatorTest : XCTestCase
@end

@implementation iTermCursorBlinkFadeAnimatorTest {
    iTermCursorBlinkFadeAnimator *_animator;
}

- (void)setUp {
    // Cycle: 1s visible dwell, 1s fade out, 1s hidden dwell, 1s fade in. Period 4s.
    _animator = [[iTermCursorBlinkFadeAnimator alloc] init];
    _animator.visibleDwellDuration = 1.0;
    _animator.fadeOutDuration = 1.0;
    _animator.hiddenDwellDuration = 1.0;
    _animator.fadeInDuration = 1.0;
    _animator.fadeInCurve = iTermCursorBlinkFadeCurveLinear;
    _animator.fadeOutCurve = iTermCursorBlinkFadeCurveLinear;
}

// When not blinking the cursor is solid and nothing wants a redraw.
- (void)testNotBlinkingIsSolid {
    XCTAssertEqual([_animator alphaForBlinking:NO atTime:100.0], 1.0);
    XCTAssertFalse(_animator.wantsRedraw);
}

// Walk through one cycle starting at t=10 and verify each phase.
- (void)testFullCycle {
    // Cycle begins now (cursor was solid).
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:10.0], 1.0, 0.0001);
    XCTAssertTrue(_animator.wantsRedraw);

    // Visible dwell [10, 11): solid, sleeping until the fade-out.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:10.5], 1.0, 0.0001);
    XCTAssertEqualWithAccuracy(_animator.timeUntilNextFrame, 0.5, 0.0001);

    // Fade out [11, 12): linear 1 -> 0, animating every frame.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:11.0], 1.0, 0.0001);
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:11.25], 0.75, 0.0001);
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:11.5], 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(_animator.timeUntilNextFrame, 0.0, 0.0001);

    // Hidden dwell [12, 13): fully hidden, sleeping until the fade-in.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:12.0], 0.0, 0.0001);
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:12.25], 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(_animator.timeUntilNextFrame, 0.75, 0.0001);

    // Fade in [13, 14): linear 0 -> 1.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:13.5], 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(_animator.timeUntilNextFrame, 0.0, 0.0001);

    // Back to visible dwell next period (t=14 == start of next cycle).
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:14.0], 1.0, 0.0001);
}

// Stopping and restarting blinking resets the cycle to fully visible.
- (void)testStopResetsCycle {
    [_animator alphaForBlinking:YES atTime:0.0];
    // Advance into the fade-out.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:1.5], 0.5, 0.0001);
    // Stop blinking (e.g. cursor moved): solid.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:NO atTime:1.6], 1.0, 0.0001);
    // Resume much later: the cycle restarts at the visible dwell, not mid-fade.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:50.0], 1.0, 0.0001);
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:50.5], 1.0, 0.0001);
    // Fade-out begins one visible-dwell after resuming.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:51.5], 0.5, 0.0001);
}

// Zero dwell makes it a continuous fade in/out with no hold.
- (void)testZeroDwell {
    _animator.visibleDwellDuration = 0.0;
    _animator.hiddenDwellDuration = 0.0;
    // Period is now 2s (1s fade out + 1s fade in).
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:0.0], 1.0, 0.0001);
    // Immediately into fade-out.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:0.5], 0.5, 0.0001);
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:1.0], 0.0, 0.0001);
    // Then fade-in.
    XCTAssertEqualWithAccuracy([_animator alphaForBlinking:YES atTime:1.5], 0.5, 0.0001);
}

// Ease-in-out is slow at both ends: symmetric about the midpoint of a fade.
- (void)testEaseInOutCurve {
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseInOut atProgress:0.0], 0.0, 0.0001);
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseInOut atProgress:0.25], 0.125, 0.0001);
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseInOut atProgress:0.5], 0.5, 0.0001);
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseInOut atProgress:0.75], 0.875, 0.0001);
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseInOut atProgress:1.0], 1.0, 0.0001);
}

// The basic curve definitions.
- (void)testCurveDefinitions {
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveLinear atProgress:0.5], 0.5, 0.0001);
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseIn atProgress:0.5], 0.25, 0.0001);
    XCTAssertEqualWithAccuracy([iTermCursorBlinkFadeAnimator easedProgressForCurve:iTermCursorBlinkFadeCurveEaseOut atProgress:0.5], 0.75, 0.0001);
}

// Presets are in the tag order the popup expects, and out-of-range tags are nil.
- (void)testPresets {
    NSArray<iTermCursorBlinkFadePreset *> *presets = [iTermCursorBlinkFadePreset presets];
    XCTAssertEqual(presets.count, 5u);
    XCTAssertEqualObjects([iTermCursorBlinkFadePreset presetWithTag:0].name, @"Breathing");
    XCTAssertEqualObjects([iTermCursorBlinkFadePreset presetWithTag:1].name, @"Linear");
    XCTAssertEqualObjects([iTermCursorBlinkFadePreset presetWithTag:4].name, @"Subtle");
    XCTAssertNil([iTermCursorBlinkFadePreset presetWithTag:-1]);
    XCTAssertNil([iTermCursorBlinkFadePreset presetWithTag:5]);
    // The Slow preset has a longer fade-out than fade-in.
    iTermCursorBlinkFadePreset *slow = [iTermCursorBlinkFadePreset presetWithTag:3];
    XCTAssertEqualObjects(slow.name, @"Slow");
    XCTAssertLessThan(slow.fadeInDuration, slow.fadeOutDuration);
}

// A preset matches its own values and rejects a perturbed one (used to decide
// whether the popup shows a preset or "Custom").
- (void)testPresetMatching {
    iTermCursorBlinkFadePreset *p = [iTermCursorBlinkFadePreset presetWithTag:0];
    XCTAssertTrue([p matchesFadeInDuration:p.fadeInDuration
                          fadeOutDuration:p.fadeOutDuration
                              fadeInCurve:p.fadeInCurve
                             fadeOutCurve:p.fadeOutCurve
                             visibleDwell:p.visibleDwell
                              hiddenDwell:p.hiddenDwell]);
    // A different duration is not a match.
    XCTAssertFalse([p matchesFadeInDuration:p.fadeInDuration + 0.1
                            fadeOutDuration:p.fadeOutDuration
                                fadeInCurve:p.fadeInCurve
                               fadeOutCurve:p.fadeOutCurve
                               visibleDwell:p.visibleDwell
                                hiddenDwell:p.hiddenDwell]);
    // A different curve is not a match.
    XCTAssertFalse([p matchesFadeInDuration:p.fadeInDuration
                            fadeOutDuration:p.fadeOutDuration
                                fadeInCurve:iTermCursorBlinkFadeCurveLinear
                               fadeOutCurve:p.fadeOutCurve
                               visibleDwell:p.visibleDwell
                                hiddenDwell:p.hiddenDwell]);
}

@end
