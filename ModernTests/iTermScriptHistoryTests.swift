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

    func testAddingTheSameEntryTwiceKeepsOneCopy() {
        let history = iTermScriptHistory()
        let entry = makeEntry("entry")
        history.addEntry(entry)
        history.addEntry(entry)

        XCTAssertEqual(history.entries.filter { $0 === entry }.count, 1)
    }

    func testTerminatedEntriesAreCappedOldestFirst() {
        let history = iTermScriptHistory()
        let running = makeEntry("running")
        history.addEntry(running)
        var stopped = [iTermScriptHistoryEntry]()
        for i in 0..<250 {
            let entry = makeEntry("stopped \(i)")
            history.addEntry(entry)
            entry.stopRunning()
            stopped.append(entry)
        }
        // The limit is enforced when an entry is added.
        history.addEntry(makeEntry("trigger"))

        let terminated = history.entries.filter { !$0.isRunning }
        XCTAssertEqual(terminated.count, 200)
        XCTAssertTrue(history.entries.contains(running))
        XCTAssertFalse(history.entries.contains(stopped[49]))
        XCTAssertTrue(history.entries.contains(stopped[50]))
        XCTAssertTrue(history.entries.contains(stopped[249]))
    }
}
