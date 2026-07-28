//
//  iTermScriptHistoryTests.swift
//  iTerm2 ModernTests
//
//  Removing terminated (non-running) entries from the Script Console history
//  leaves running entries and persistent pseudo-entries untouched.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermScriptHistoryTests: XCTestCase {
    private func makeEntry(_ name: String) -> iTermScriptHistoryEntry {
        return iTermScriptHistoryEntry(name: name,
                                       fullPath: nil,
                                       identifier: name,
                                       relaunch: nil)
    }

    func testRemoveTerminatedEntriesKeepsRunningAndPersistent() {
        let history = iTermScriptHistory()
        // Fresh history already contains the persistent global entry, which is
        // always "running" and must survive.
        let persistentCount = history.entries.count

        let running = makeEntry("running")
        let stopped = makeEntry("stopped")
        history.addEntry(running)
        history.addEntry(stopped)
        stopped.stopRunning()

        history.removeTerminatedEntries()

        XCTAssertTrue(history.entries.contains(running))
        XCTAssertFalse(history.entries.contains(stopped))
        XCTAssertEqual(history.entries.count, persistentCount + 1)
    }

    func testRemoveTerminatedEntriesIsNoOpWhenNothingTerminated() {
        let history = iTermScriptHistory()
        let running = makeEntry("running")
        history.addEntry(running)
        let before = history.entries.count

        history.removeTerminatedEntries()

        XCTAssertEqual(history.entries.count, before)
        XCTAssertTrue(history.entries.contains(running))
    }

    func testRemoveHistoryEntryRemovesOnlyThatEntry() {
        let history = iTermScriptHistory()
        let a = makeEntry("a")
        let b = makeEntry("b")
        history.addEntry(a)
        history.addEntry(b)

        history.removeEntry(a)

        XCTAssertFalse(history.entries.contains(a))
        XCTAssertTrue(history.entries.contains(b))
    }
}
