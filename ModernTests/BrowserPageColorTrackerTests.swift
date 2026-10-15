//
//  BrowserPageColorTrackerTests.swift
//  ModernTests
//
//  QA finding F-039: in the minimal theme a browser tab's tint lagged one page load
//  behind. The page color was read only once, in didFinish, but WebKit updates
//  underPageBackgroundColor after the load finishes (on a later rendering update), so
//  didFinish still saw the previous page's color and the new page's color was never
//  delivered until the next load. The tracker forwards observed color changes once the
//  load has settled, while still ignoring the transient values WebKit reports during load.
//

import XCTest
@testable import iTerm2SharedARC

final class BrowserPageColorTrackerTests: XCTestCase {
    private let white = NSColor.white
    private let black = NSColor.black

    // The reported bug: didFinish sees the previous page's (white) color, and the new
    // page's black color arrives only after didFinish. It must be forwarded.
    func testColorArrivingAfterFinishIsForwarded() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        XCTAssertEqual(tracker.navigationDidSettle(currentColor: white), white)
        tracker.navigationDidStart()
        // Stale value at didFinish (the previous page's color) is a repeat, so it is not
        // forwarded and doesn't hold up the real color in the session's rate limiter.
        XCTAssertNil(tracker.navigationDidSettle(currentColor: white))
        // WebKit then reports the new page's real color.
        XCTAssertEqual(tracker.observedColorDidChange(black, isLoading: false), black)
    }

    // Values WebKit reports while a page is loading are transient (e.g. its light
    // default before the page is parsed) and must not flip the tint.
    func testChangesDuringLoadAreIgnored() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        XCTAssertNil(tracker.observedColorDidChange(white, isLoading: true))
        XCTAssertNil(tracker.observedColorDidChange(black, isLoading: true))
        XCTAssertEqual(tracker.navigationDidSettle(currentColor: black), black)
    }

    // Before any page has finished loading, the web view's color is WebKit's default
    // and must not be forwarded.
    func testNothingForwardedBeforeFirstLoadSettles() {
        var tracker = iTermBrowserPageColorTracker()
        XCTAssertNil(tracker.observedColorDidChange(white, isLoading: false))
    }

    // A new navigation suppresses forwarding again until it settles.
    func testNewNavigationSuppressesForwardingUntilSettled() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        _ = tracker.navigationDidSettle(currentColor: white)
        XCTAssertEqual(tracker.observedColorDidChange(black, isLoading: false), black)
        tracker.navigationDidStart()
        XCTAssertNil(tracker.observedColorDidChange(white, isLoading: false))
    }

    // A page that changes its own background after loading (e.g. a script toggling a
    // dark mode) is followed.
    func testLaterChangesOnSettledPageAreForwarded() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        _ = tracker.navigationDidSettle(currentColor: white)
        XCTAssertEqual(tracker.observedColorDidChange(black, isLoading: false), black)
        XCTAssertEqual(tracker.observedColorDidChange(white, isLoading: false), white)
    }

    // A nil observed color carries no information and is not forwarded.
    func testNilObservedColorIsIgnored() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        _ = tracker.navigationDidSettle(currentColor: white)
        XCTAssertNil(tracker.observedColorDidChange(nil, isLoading: false))
    }

    // A failed load (for example a link that turned into a download) leaves the current
    // page in place, so changes to its color must be followed again.
    func testFailedNavigationResumesForwarding() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        _ = tracker.navigationDidSettle(currentColor: white)
        tracker.navigationDidStart()
        tracker.navigationDidFail()
        XCTAssertEqual(tracker.observedColorDidChange(black, isLoading: false), black)
    }

    // A late failure of a superseded navigation must not let transient values from the
    // newer, still-loading navigation through.
    func testLateFailureOfSupersededNavigationDoesNotForwardDuringLoad() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        _ = tracker.navigationDidSettle(currentColor: black)
        tracker.navigationDidStart()  // A
        tracker.navigationDidStart()  // B supersedes A
        tracker.navigationDidFail()   // A's cancellation arrives late
        XCTAssertNil(tracker.observedColorDidChange(white, isLoading: true))
        XCTAssertEqual(tracker.navigationDidSettle(currentColor: white), white)
    }

    // A color equal to the one already forwarded is not forwarded again.
    func testRepeatedColorIsNotForwarded() {
        var tracker = iTermBrowserPageColorTracker()
        tracker.navigationDidStart()
        XCTAssertEqual(tracker.navigationDidSettle(currentColor: black), black)
        XCTAssertNil(tracker.observedColorDidChange(black, isLoading: false))
    }
}
