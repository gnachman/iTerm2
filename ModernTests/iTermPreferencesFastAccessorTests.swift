//
//  iTermPreferencesFastAccessorTests.swift
//  iTerm2 ModernTests
//
//  Covers the FastAccessors cache in iTermPreferences. These caches read a
//  preference once and then keep a cached copy that is refreshed by an observer.
//  The regression under test: an in-process write must update the cache
//  synchronously (in the same runloop turn) so a redraw kicked off by the write
//  does not read a stale value. The KVO-backed refresh is delivered
//  asynchronously, so before the synchronous refresh hook a live change (e.g.
//  dragging the dimming slider) lagged one step.
//
//  The first-use construction race itself is not deterministically testable, but
//  the synchronous-refresh-on-write path it depends on is.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermPreferencesFastAccessorTests: XCTestCase {

    // Each case primes the accessor (running its dispatch_once), writes a new
    // value, and asserts the accessor reflects it immediately -- no runloop spin,
    // which is what the async KVO refresh would require. The original value is
    // restored in every path.

    func testDoubleFastAccessorReflectsWriteSynchronously() {
        let original = iTermPreferences.double(forKey: kPreferenceKeyDimmingAmount)
        // Prime the cache.
        XCTAssertEqual(iTermPreferences.splitPaneDimmingAmount(), original, accuracy: 0.0001)
        defer { iTermPreferences.setDouble(original, forKey: kPreferenceKeyDimmingAmount) }

        let updated = original + 0.123
        iTermPreferences.setDouble(updated, forKey: kPreferenceKeyDimmingAmount)
        XCTAssertEqual(iTermPreferences.splitPaneDimmingAmount(), updated, accuracy: 0.0001)
    }

    func testIntFastAccessorReflectsWriteSynchronously() {
        let original = iTermPreferences.sideMargins()
        // Prime the cache (also asserts the accessor agrees with the raw read).
        XCTAssertEqual(Int(original), iTermPreferences.integer(forKey: kPreferenceKeySideMargins))
        defer { iTermPreferences.setInt(original, forKey: kPreferenceKeySideMargins) }

        let updated = original + 7
        iTermPreferences.setInt(updated, forKey: kPreferenceKeySideMargins)
        XCTAssertEqual(iTermPreferences.sideMargins(), updated)
    }

    func testBoolFastAccessorReflectsWriteSynchronously() {
        let original = iTermPreferences.perPaneBackgroundImage()
        // Prime the cache.
        XCTAssertEqual(original, iTermPreferences.bool(forKey: kPreferenceKeyPerPaneBackgroundImage))
        defer { iTermPreferences.setBool(original, forKey: kPreferenceKeyPerPaneBackgroundImage) }

        iTermPreferences.setBool(!original, forKey: kPreferenceKeyPerPaneBackgroundImage)
        XCTAssertEqual(iTermPreferences.perPaneBackgroundImage(), !original)
        iTermPreferences.setBool(original, forKey: kPreferenceKeyPerPaneBackgroundImage)
        XCTAssertEqual(iTermPreferences.perPaneBackgroundImage(), original)
    }
}
