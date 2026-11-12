//
//  iTermEventTapModeTests.m
//  ModernTests
//
//  Covers how keyboard event taps choose between being off, listen-only, and
//  filtering. A filtering tap makes every keystroke in every app wait for
//  iTerm2, so it must only be used while iTerm2 is active (when the keystrokes
//  are going to iTerm2 anyway). See issue 12645.
//

#import <XCTest/XCTest.h>

#import "iTermEventTap.h"
#import "iTermModifierRemapper.h"

@interface iTermEventTapModeTests : XCTestCase
@end

@implementation iTermEventTapModeTests

- (void)testNotAllowedIsOff {
    for (int i = 0; i < 8; i++) {
        XCTAssertEqual(iTermEventTapModeFor(NO, !!(i & 1), !!(i & 2), !!(i & 4)), iTermEventTapModeOff);
    }
}

- (void)testDelegateThatModifiesEventsFilters {
    for (int i = 0; i < 4; i++) {
        XCTAssertEqual(iTermEventTapModeFor(YES, YES, !!(i & 1), !!(i & 2)), iTermEventTapModeFilter);
    }
}

// Other apps must never wait for iTerm2 just so it can observe their keystrokes.
- (void)testObserversOnlyListenWhileInactive {
    XCTAssertEqual(iTermEventTapModeFor(YES, NO, YES, NO), iTermEventTapModeListenOnly);
}

// While active, observers must see events before the app does, which needs a filtering tap.
- (void)testObserversFilterWhileActive {
    XCTAssertEqual(iTermEventTapModeFor(YES, NO, YES, YES), iTermEventTapModeFilter);
}

- (void)testNoDelegateAndNoObserversIsOff {
    XCTAssertEqual(iTermEventTapModeFor(YES, NO, NO, NO), iTermEventTapModeOff);
    XCTAssertEqual(iTermEventTapModeFor(YES, NO, NO, YES), iTermEventTapModeOff);
}

// The shared taps install themselves as a no-op remapping delegate. That must
// not keep a tap installed when nobody is observing it.
- (void)testSharedKeyDownTapWithoutObserversIsOff {
    iTermKeyDownEventTap *tap = [iTermKeyDownEventTap sharedInstance];
    XCTAssertEqual(tap.weakObservers.count, 0);
    XCTAssertEqual(tap.desiredMode, iTermEventTapModeOff);
    XCTAssertFalse(tap.isEnabled);
}

- (void)testSharedFlagsChangedTapWithoutObserversOrRemapperIsOff {
    iTermFlagsChangedEventTap *tap = [iTermFlagsChangedEventTap sharedInstance];
    XCTAssertEqual(tap.weakObservers.count, 0);
    XCTAssertEqual(tap.desiredMode, iTermEventTapModeOff);
    XCTAssertFalse(tap.isEnabled);
}

// Without Input Monitoring, a listen-only request gets the same filtering tap a filter request
// does, so switching between them on activation must not rebuild the tap.
- (void)testListenOnlyWithoutListenAccessInstallsFilteringTap {
    XCTAssertTrue(iTermEventTapInstallsListenOnly(iTermEventTapModeListenOnly, YES));
    XCTAssertFalse(iTermEventTapInstallsListenOnly(iTermEventTapModeListenOnly, NO));
    XCTAssertFalse(iTermEventTapInstallsListenOnly(iTermEventTapModeFilter, YES));
    XCTAssertFalse(iTermEventTapInstallsListenOnly(iTermEventTapModeFilter, NO));
}

// A key that reached the system before the remapping taps existed (e.g., typed while iTerm2 was
// activating) must be remapped by the app.
- (void)testUnhandledEventFromBeforeTapsWereInstalledNeedsAppRemapping {
    XCTAssertTrue([iTermModifierRemapper eventTapMissedEventWithTimestamp:100
                                                        tapsInstalledTime:101
                                                             handledByTap:NO]);
}

// Once the tap has remapped an event, remapping it again in the app would undo a swap.
- (void)testHandledEventDoesNotNeedAppRemapping {
    XCTAssertFalse([iTermModifierRemapper eventTapMissedEventWithTimestamp:100
                                                         tapsInstalledTime:101
                                                              handledByTap:YES]);
    XCTAssertFalse([iTermModifierRemapper eventTapMissedEventWithTimestamp:102
                                                         tapsInstalledTime:101
                                                              handledByTap:YES]);
}

// The install time must advance each time the taps start remapping (every activation), and only
// then: a repeated begin while already remapping must not move it past keys that missed the taps.
- (void)testTapsInstalledTimeAdvancesOnlyWhenRemappingStarts {
    XCTAssertEqual([iTermModifierRemapper tapsInstalledTimeAfterPreviousTime:5
                                                                wasRemapping:NO
                                                                 isRemapping:YES
                                                                         now:10], 10);
    XCTAssertEqual([iTermModifierRemapper tapsInstalledTimeAfterPreviousTime:5
                                                                wasRemapping:YES
                                                                 isRemapping:YES
                                                                         now:10], 5);
    XCTAssertEqual([iTermModifierRemapper tapsInstalledTimeAfterPreviousTime:5
                                                                wasRemapping:NO
                                                                 isRemapping:NO
                                                                         now:10], 5);
}

// Events after installation that skipped the tap were synthesized past it (e.g., posted at the
// session level). They weren't remapped before this change either.
- (void)testUnhandledEventFromAfterTapsWereInstalledDoesNotNeedAppRemapping {
    XCTAssertFalse([iTermModifierRemapper eventTapMissedEventWithTimestamp:102
                                                         tapsInstalledTime:101
                                                              handledByTap:NO]);
}

@end
