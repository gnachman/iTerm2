//
//  PTYTaskProcessInfoPIDTests.swift
//  ModernTests
//
//  Which pid a task looks up process info under. A tmux pane session's task never forks anything
//  itself; the only pid it has is the pane pid tmux reported. The async fetch has always used
//  that one, but the cached fast path used the task's own pid, which for a pane is nothing, so
//  the inactive-pane poll got nil back and cleared the pane's job ancestry on every tick: a
//  spurious "claude ended" that tore down the workgroup.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class PTYTaskProcessInfoPIDTests: XCTestCase {
    func testTmuxPanePIDWinsForProcessInfoLookups() {
        let task = PTYTask()!
        XCTAssertEqual(task.processInfoPID, task.pid, "without a pane pid, the task's own pid")

        task.tmuxClientProcessID = 4242
        XCTAssertEqual(task.processInfoPID, 4242, "a pane pid replaces the task's own pid")

        task.tmuxClientProcessID = nil
        XCTAssertEqual(task.processInfoPID, task.pid, "clearing the pane pid goes back to the task's own")
    }

    // The cached lookup and the async fetch must agree on the pid, or the poll path and the event
    // path describe two different processes for the same session.
    func testCachedLookupUsesTheSamePIDAsTheFetch() {
        let task = PTYTask()!
        task.tmuxClientProcessID = NSNumber(value: getpid())
        defer { task.tmuxClientProcessID = nil }
        // The lookups are the SessionProcessInfoProvider conformance, declared in a category
        // header Swift cannot see, so go through the protocol. The fetch asks the process cache
        // for an immediate update when it has nothing yet, so by the time it completes the cache
        // holds this pid.
        let provider = (task as AnyObject) as! SessionProcessInfoProvider
        let fetched = expectation(description: "fetched")
        var fetchedInfo: iTermProcessInfo?
        provider.fetchProcessInfoForCurrentJob { info in
            fetchedInfo = info
            fetched.fulfill()
        }
        wait(for: [fetched], timeout: 10)
        let cached = provider.cachedProcessInfoIfAvailable()
        XCTAssertEqual(cached?.processID, fetchedInfo?.processID,
                       "cached: \(String(describing: cached)) fetched: \(String(describing: fetchedInfo))")
    }
}
