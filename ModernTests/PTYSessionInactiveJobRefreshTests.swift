//
//  PTYSessionInactiveJobRefreshTests.swift
//  ModernTests
//
//  A session that is not the active one in its tab refreshes its job from the process cache on
//  every display update instead of polling. When the cache has nothing for it, which is the
//  normal state for a cold cache and was the permanent state for a tmux pane, that must leave the
//  job ancestry alone rather than clearing it: GlobalJobMonitor cannot tell "cleared" from
//  "exited", and an empty ancestry fires the leader-only Exit Workgroup trigger.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class PTYSessionInactiveJobRefreshTests: XCTestCase {
    func testNoCachedProcessInfoLeavesTheAncestryAlone() {
        let session = PTYSession(synthetic: false)!
        session.genericScope.setValue("claude", forVariableNamed: iTermVariableKeySessionForegroundJobAncestors)

        // A synthetic session's task has no job and nothing registered with the process cache,
        // so the cache answers nil for it, exactly as it did for a tmux pane.
        session.refreshForegroundJobFromCacheIfAvailable()

        XCTAssertEqual(session.genericScope.value(forVariableName: iTermVariableKeySessionForegroundJobAncestors) as? String,
                       "claude")
    }
}
