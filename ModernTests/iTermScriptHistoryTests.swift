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

    func testStoppedEntryStopsLoggingAPITraffic() {
        let running = makeEntry(UUID().uuidString)
        let stopped = makeEntry(UUID().uuidString)
        stopped.stopRunning()

        for entry in [running, stopped] {
            NotificationCenter.default.post(name: NSNotification.Name(iTermAPIServerDidReceiveMessage),
                                            object: entry.identifier)
        }

        XCTAssertEqual(running.callEntries.count, 1)
        XCTAssertEqual(stopped.callEntries.count, 0)
    }

    // A connection that reuses a closed connection's key (it2 over SSH, or a
    // client reconnecting) resumes the old entry, which must log again.
    func testResumedEntryLogsAPITrafficAgain() {
        let entry = makeEntry(UUID().uuidString)
        entry.stopRunning()
        entry.resumeRunning()

        NotificationCenter.default.post(name: NSNotification.Name(iTermAPIServerDidReceiveMessage),
                                        object: entry.identifier)

        XCTAssertTrue(entry.isRunning)
        XCTAssertEqual(entry.callEntries.count, 1)
    }

    func testResumedEntryIsNotEvictedAsTerminated() {
        let history = iTermScriptHistory()
        let resumed = makeEntry("resumed")
        history.addEntry(resumed)
        resumed.stopRunning()
        resumed.resumeRunning()
        for i in 0..<250 {
            let entry = makeEntry("stopped \(i)")
            history.addEntry(entry)
            entry.stopRunning()
        }
        history.addEntry(makeEntry("trigger"))

        XCTAssertTrue(history.entries.contains(resumed))
    }

    func testResumingARunningEntryRegistersOnce() {
        let entry = makeEntry(UUID().uuidString)
        entry.resumeRunning()

        NotificationCenter.default.post(name: NSNotification.Name(iTermAPIServerDidReceiveMessage),
                                        object: entry.identifier)

        XCTAssertEqual(entry.callEntries.count, 1)
    }

    func testResumingClearsTerminatedByUser() {
        let entry = makeEntry(UUID().uuidString)
        entry.terminatedByUser = true
        entry.stopRunning()

        entry.resumeRunning()

        XCTAssertFalse(entry.terminatedByUser)
    }

    private func postReceivedMessage(for entry: iTermScriptHistoryEntry) {
        NotificationCenter.default.post(name: NSNotification.Name(iTermAPIServerDidReceiveMessage),
                                        object: entry.identifier)
    }

    func testEntryStaysRunningUntilItsLastConnectionCloses() {
        let history = iTermScriptHistory()
        let entry = makeEntry(UUID().uuidString)
        history.addEntry(entry)
        entry.connectionDidOpen()  // A
        entry.connectionDidOpen()  // B

        entry.connectionDidClose()  // A
        XCTAssertTrue(entry.isRunning)
        postReceivedMessage(for: entry)
        XCTAssertEqual(entry.callEntries.count, 1)
        for i in 0..<201 {
            let stopped = makeEntry("stopped \(i)")
            history.addEntry(stopped)
            stopped.stopRunning()
        }
        history.addEntry(makeEntry("trigger"))
        XCTAssertTrue(history.entries.contains(entry))

        entry.connectionDidClose()  // B
        XCTAssertFalse(entry.isRunning)
        postReceivedMessage(for: entry)
        XCTAssertEqual(entry.callEntries.count, 1)
    }

    func testConnectionOpeningOnAStoppedEntryResumesIt() {
        let entry = makeEntry(UUID().uuidString)
        entry.connectionDidOpen()
        entry.connectionDidClose()
        XCTAssertFalse(entry.isRunning)

        entry.connectionDidOpen()
        XCTAssertTrue(entry.isRunning)
        postReceivedMessage(for: entry)
        XCTAssertEqual(entry.callEntries.count, 1)
    }

    // Stopping for any other reason, like the API shutting down, forgets open
    // connections so a close that never arrives can't keep the entry alive.
    func testStoppingForgetsOpenConnections() {
        let entry = makeEntry(UUID().uuidString)
        entry.connectionDidOpen()
        entry.connectionDidOpen()
        entry.stopRunning()

        entry.connectionDidOpen()
        entry.connectionDidClose()
        XCTAssertFalse(entry.isRunning)
    }

    // An entry made outside connectionAccepted: (a launched script's) may see a
    // close without a matching open; that still stops it.
    func testCloseWithoutOpenStops() {
        let entry = makeEntry(UUID().uuidString)
        entry.connectionDidClose()
        XCTAssertFalse(entry.isRunning)
    }
}
