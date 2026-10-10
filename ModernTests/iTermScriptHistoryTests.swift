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
        entry.connectionDidOpen(withPIDs: nil)  // A
        entry.connectionDidOpen(withPIDs: nil)  // B

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
        entry.connectionDidOpen(withPIDs: nil)
        entry.connectionDidClose()
        XCTAssertFalse(entry.isRunning)

        entry.connectionDidOpen(withPIDs: nil)
        XCTAssertTrue(entry.isRunning)
        postReceivedMessage(for: entry)
        XCTAssertEqual(entry.callEntries.count, 1)
    }

    // Stopping for any other reason, like the API shutting down, forgets open
    // connections so a close that never arrives can't keep the entry alive.
    func testStoppingForgetsOpenConnections() {
        let entry = makeEntry(UUID().uuidString)
        entry.connectionDidOpen(withPIDs: nil)
        entry.connectionDidOpen(withPIDs: nil)
        entry.stopRunning()

        entry.connectionDidOpen(withPIDs: nil)
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

    // These pids are never signaled: nothing here posts the API shutdown
    // notification, which other objects in the test host also observe.

    func testAdHocEntryStopsObservingShutdownWhenItsConnectionCloses() {
        let entry = makeEntry(UUID().uuidString)
        entry.connectionDidOpen(withPIDs: [111])
        XCTAssertTrue(entry.observesAPIShutdown)

        entry.connectionDidClose()

        XCTAssertFalse(entry.observesAPIShutdown)
    }

    // A launched script can outlive its connection, for example while it waits
    // to reconnect, and must still be killed if the API shuts down.
    func testLaunchedEntryObservesShutdownUntilItsProcessExits() {
        let entry = makeEntry(UUID().uuidString)
        entry.trackProcess(111)
        entry.connectionDidOpen(withPIDs: [111])
        entry.connectionDidClose()

        XCTAssertFalse(entry.isRunning)
        XCTAssertTrue(entry.observesAPIShutdown)

        entry.processDidExit()
        XCTAssertFalse(entry.observesAPIShutdown)
    }

    // Clear Terminated is enabled only for finished entries, so the console
    // must hear when a stopped entry's process exits.
    func testProcessExitOfAStoppedEntryPostsDidChange() {
        let entry = makeEntry(UUID().uuidString)
        entry.trackProcess(111)
        entry.connectionDidOpen(withPIDs: [111])
        entry.connectionDidClose()
        XCTAssertFalse(entry.isFinished)

        let posted = expectation(forNotification: .iTermScriptHistoryEntryDidChange,
                                 object: entry)
        entry.processDidExit()

        wait(for: [posted], timeout: 0)
        XCTAssertTrue(entry.isFinished)
    }

    func testProcessExitStopsARunningEntry() {
        let entry = makeEntry(UUID().uuidString)
        entry.trackProcess(111)

        entry.processDidExit()

        XCTAssertFalse(entry.isRunning)
        XCTAssertFalse(entry.observesAPIShutdown)
    }

    func testReconnectingAdHocEntryTakesTheNewPIDs() {
        let entry = makeEntry(UUID().uuidString)
        entry.connectionDidOpen(withPIDs: [111])
        entry.connectionDidClose()

        entry.connectionDidOpen(withPIDs: [222])

        XCTAssertEqual(entry.onlyPid, 222)
    }

    func testReconnectingLaunchedEntryKeepsTheLaunchedPID() {
        let entry = makeEntry(UUID().uuidString)
        entry.trackProcess(111)
        entry.connectionDidOpen(withPIDs: [111])
        entry.connectionDidClose()

        entry.connectionDidOpen(withPIDs: [111, 1])

        XCTAssertEqual(entry.onlyPid, 111)
        entry.processDidExit()
    }

    private func addFinishedEntries(_ count: Int, to history: iTermScriptHistory) {
        for i in 0..<count {
            let entry = makeEntry("finished \(i)")
            history.addEntry(entry)
            entry.stopRunning()
        }
        // The cap is enforced when an entry is added.
        history.addEntry(makeEntry("trigger"))
    }

    // The built-in entries log iTerm2's own activity and have no process, so
    // an API shutdown must not stop them and the cap must not drop them.
    func testBuiltInEntriesNeverStop() {
        let global = iTermScriptHistoryEntry.global()
        XCTAssertFalse(global.observesAPIShutdown)

        global.stopRunning()

        XCTAssertTrue(global.isRunning)
        XCTAssertFalse(global.isFinished)
        let history = iTermScriptHistory()
        addFinishedEntries(201, to: history)
        XCTAssertTrue(history.entries.contains(global))
    }

    // A launched script can lose its connection and keep running; its entry
    // must keep collecting its output and be found again when it reconnects.
    func testLaunchedEntryWithLiveProcessIsNotRemoved() {
        let history = iTermScriptHistory()
        let launched = makeEntry(UUID().uuidString)
        history.addEntry(launched)
        launched.trackProcess(111)
        launched.connectionDidOpen(withPIDs: [111])
        launched.connectionDidClose()
        XCTAssertFalse(launched.isFinished)

        addFinishedEntries(201, to: history)
        XCTAssertTrue(history.entries.contains(launched))
        history.removeTerminatedEntries()
        XCTAssertTrue(history.entries.contains(launched))

        launched.processDidExit()
        XCTAssertTrue(launched.isFinished)
        history.removeTerminatedEntries()
        XCTAssertFalse(history.entries.contains(launched))
    }
}

// Drives the Script Console with the notifications iTermAPIServer posts. Uses
// the shared console and history, with a unique key per test.
final class iTermScriptConsoleConnectionTests: XCTestCase {
    private let key = UUID().uuidString

    override func setUp() {
        super.setUp()
        _ = iTermScriptConsole.sharedInstance()
    }

    private func post(_ name: String, userInfo: [String: Any]? = nil) {
        NotificationCenter.default.post(name: NSNotification.Name(name),
                                        object: key,
                                        userInfo: userInfo)
    }

    private func accept(pids: [Int]) {
        post(iTermAPIServerConnectionAccepted, userInfo: ["reason": "test", "job": "test", "pids": pids])
    }

    private var entry: iTermScriptHistoryEntry? {
        return iTermScriptHistory.sharedInstance().entry(withIdentifier: key)
    }

    func testRejectedRequestDoesNotDisturbAnOpenConnectionsEntry() throws {
        accept(pids: [111])
        let entry = try XCTUnwrap(self.entry)

        post(iTermAPIServerConnectionRejected, userInfo: ["reason": "bad cookie", "pids": [222]])

        XCTAssertTrue(entry.isRunning)
        XCTAssertEqual(entry.onlyPid, 111)
        post(iTermAPIServerDidReceiveMessage)
        XCTAssertEqual(entry.callEntries.count, 1)
        post(iTermAPIServerConnectionClosed)
        XCTAssertFalse(entry.isRunning)
    }

    func testRejectedRequestWithANewKeyMakesAStoppedEntry() throws {
        post(iTermAPIServerConnectionRejected, userInfo: ["reason": "bad cookie", "pids": [222]])

        let entry = try XCTUnwrap(self.entry)
        XCTAssertFalse(entry.isRunning)
        XCTAssertEqual(entry.onlyPid, 222)
    }

    func testEntryStopsWhenTheLastOfTwoConnectionsCloses() throws {
        accept(pids: [111])
        accept(pids: [111])
        let entry = try XCTUnwrap(self.entry)

        post(iTermAPIServerConnectionClosed)
        XCTAssertTrue(entry.isRunning)

        post(iTermAPIServerConnectionClosed)
        XCTAssertFalse(entry.isRunning)
    }

    func testReacceptedKeyResumesTheEntryWithTheNewPIDs() throws {
        accept(pids: [111])
        post(iTermAPIServerConnectionClosed)
        let entry = try XCTUnwrap(self.entry)

        accept(pids: [222])

        XCTAssertTrue(entry.isRunning)
        XCTAssertEqual(entry.onlyPid, 222)
        post(iTermAPIServerDidReceiveMessage)
        XCTAssertEqual(entry.callEntries.count, 1)
        post(iTermAPIServerConnectionClosed)
    }
}
