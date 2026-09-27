//
//  RemoteHostCacheTests.swift
//  iTerm2
//
//  Integration tests for the -lastRemoteHost cache added for issue #12992.
//
//  The cache lives on the *mutable* state (VT100ScreenMutableState). The
//  read-only snapshot recomputes every sync, so it is always correct; these
//  tests therefore read -lastRemoteHost on the mutable state (inside
//  performBlock joinedThreads:), which is the value the mutation-thread
//  consumers (addMarksForPathsInRange:, path sniffing, directory tracking) see.
//
//  Each test warms the cache to a specific value, performs a mutation that
//  re-homes/removes the VT100RemoteHost mark, and asserts the cache reflects the
//  new truth. Without the invalidation hooks these regress to a stale host.
//

import XCTest
@testable import iTerm2SharedARC

final class RemoteHostCacheTests: XCTestCase {

    // Reads -lastRemoteHost.hostname on the mutable state. Reading it also warms
    // the cache (populates _cachedLastRemoteHost / sets the valid flag), which is
    // exactly what we want between mutations.
    private func mutableHost(_ h: TerminalTestHarness) -> String? {
        var name: String? = nil
        h.screen.performBlock(joinedThreads: { _, mutableState, _ in
            name = mutableState.lastRemoteHost?.hostname
        })
        return name
    }

    // MARK: - Baseline

    func test_lastRemoteHost_returnsMostRecentHost() {
        let h = TerminalTestHarness(width: 80, height: 24)
        h.appendText("hello"); h.newline()
        h.sendRemoteHost(user: "u", host: "hostA")
        h.sync()
        XCTAssertEqual(mutableHost(h), "hostA")
    }

    // Adding a newer host must supersede the cached one (setRemoteHost: invalidates).
    func test_lastRemoteHost_newHostSupersedesCached() {
        let h = TerminalTestHarness(width: 80, height: 24)
        h.sendRemoteHost(user: "u", host: "hostA")
        h.sync()
        XCTAssertEqual(mutableHost(h), "hostA")   // warm cache = A
        h.appendText("work"); h.newline()
        h.sendRemoteHost(user: "u", host: "hostB")
        h.sync()
        XCTAssertEqual(mutableHost(h), "hostB",
                       "a newly added host must supersede the cached one")
    }

    // MARK: - Alt-screen swap (moveNotesOnScreenFrom:/removeNotesOnScreenFrom:)

    // On host B with M_B on screen, entering the alt buffer moves M_B into the
    // saved tree; -lastRemoteHost then recomputes to nil against the primary tree
    // and caches it. Returning to the primary buffer re-homes M_B, which must
    // invalidate the cache. Without the swap-path invalidation, -lastRemoteHost
    // keeps returning nil after showPrimaryBuffer.
    func test_lastRemoteHost_survivesAltScreenSwap() {
        let h = TerminalTestHarness(width: 80, height: 24)
        h.appendText("hello"); h.newline()
        h.sendRemoteHost(user: "u", host: "hostB")   // M_B on screen, primary tree
        h.sync()
        XCTAssertEqual(mutableHost(h), "hostB")       // warm cache = B

        h.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        // While in alt, M_B is in the saved tree; recompute caches nil.
        XCTAssertNil(mutableHost(h),
                     "sanity: on-screen host mark should be swapped out of the primary tree")

        h.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        XCTAssertEqual(mutableHost(h), "hostB",
                       "host must survive an alt-screen round trip")
    }

    // MARK: - Fold / unfold (addSavedIntervalTreeObjects:baseLine:)

    // Folding the region containing M_B removes it (entry niled) so a read while
    // folded correctly recomputes to nil and caches it. Unfolding re-adds M_B via
    // -addSavedIntervalTreeObjects:baseLine:, which must invalidate the cache.
    // Without that invalidation, -lastRemoteHost keeps returning the stale nil.
    func test_lastRemoteHost_survivesFoldUnfold() {
        let h = TerminalTestHarness(width: 80, height: 24)
        h.appendText("line 0"); h.newline()
        h.appendText("line 1"); h.newline()
        h.sendRemoteHost(user: "u", host: "hostB")   // M_B at abs line 2 (on screen)
        h.appendText("after host"); h.newline()
        h.sync()
        XCTAssertEqual(mutableHost(h), "hostB")

        // Fold abs lines 1..3 (inclusive) — foldAbsLineRange: treats the range
        // end inclusively of NSMaxRange, so NSRange(loc:1, len:2) covers lines
        // 1, 2, 3. Either way this covers the host mark's line (abs line 2).
        let foldRange = NSRange(location: 1, length: 2)
        h.screen.foldAbsLineRange(foldRange)
        h.screen.performBlock(joinedThreads: { _, _, _ in })
        XCTAssertNil(mutableHost(h),
                     "sanity: folding the host mark's line should remove it from the tree")

        h.screen.removeFolds(in: foldRange, completion: nil)
        h.screen.performBlock(joinedThreads: { _, _, _ in })
        XCTAssertEqual(mutableHost(h), "hostB",
                       "host must be observed again after unfold re-adds its mark")
    }
}
