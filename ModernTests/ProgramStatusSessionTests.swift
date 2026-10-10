//
//  ProgramStatusSessionTests.swift
//  ModernTests
//
//  The OSC 7501 wiring in PTYSession: which changes notify. A program's own
//  report notifies, record by record. A record shown again after the status
//  was cleared (at a prompt, or after a reset) is a status the user already
//  had, and a keypress that marks a result seen is the user acting, so
//  neither should notify, through either path.
//

import XCTest
@testable import iTerm2SharedARC

private final class NotificationSpySession: PTYSession {
    /// The status text at each change that reached the session-level
    /// notification step.
    var notified = [String?]()
    /// The description of each record notification.
    var recordNotifications = [String]()

    override func maybePostTabStatusNotification(withPreviousStatusText previousStatusText: String?) {
        notified.append(tabStatus?.statusText)
    }

    override func postProgramStatusNotification(withDescription description: String) {
        recordNotifications.append(description)
    }
}

final class ProgramStatusSessionTests: XCTestCase {
    private var savedPriorities = [StatusPriorityEntry]()

    override func setUp() {
        super.setUp()
        // Notify for every status, so a test sees whatever would notify.
        savedPriorities = StatusPrioritySettings.shared.entries
        StatusPrioritySettings.shared.restoreEntries(
            ["wait", "done", "error", "work", "idle"].map { StatusPriorityEntry(pattern: $0, notify: true) })
    }

    override func tearDown() {
        StatusPrioritySettings.shared.restoreEntries(savedPriorities)
        super.tearDown()
    }

    private func report(_ body: String) -> ProgramStatusReport {
        return ProgramStatusReport.parse(body)!
    }

    /// Lets work the session dispatched to the main queue run.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    func testReportNotifiesOnceThroughRecordPath() {
        let session = NotificationSpySession(synthetic: false)!
        session.screenReportProgramStatus(report("state=done"))
        XCTAssertEqual(session.recordNotifications.count, 1)
        // Not also through the session-level path.
        XCTAssertEqual(session.notified, [])
    }

    func testChildRecordNotificationNamesIt() {
        let session = NotificationSpySession(synthetic: false)!
        session.screenReportProgramStatus(report("state=blocked:id=eu:title=\(Data("EU West".utf8).base64EncodedString())"))
        XCTAssertEqual(session.recordNotifications.count, 1)
        XCTAssertTrue(session.recordNotifications[0].contains("EU West"), session.recordNotifications[0])
    }

    func testMessageOnlyChangeDoesNotNotify() {
        let session = NotificationSpySession(synthetic: false)!
        session.screenReportProgramStatus(report("state=working"))
        session.recordNotifications = []
        session.screenReportProgramStatus(report("state=working:msg=\(Data("step 2".utf8).base64EncodedString())"))
        XCTAssertEqual(session.recordNotifications, [])
    }

    func testSecondBlockedRecordIsNotSilent() {
        // The tab already says waiting, so the session-level path would see
        // no change; the record path still has news.
        let session = NotificationSpySession(synthetic: false)!
        session.screenReportProgramStatus(report("state=blocked:id=a"))
        XCTAssertEqual(session.recordNotifications.count, 1)
        session.screenReportProgramStatus(report("state=blocked:id=b"))
        // Rate-limited: held rather than dropped (see ProgramStatusNotifierTests).
        XCTAssertEqual(session.recordNotifications.count, 1)
        XCTAssertEqual(session.notified, [])
    }

    func testDoneShownAgainAfterPromptDoesNotNotify() {
        let session = NotificationSpySession(synthetic: false)!
        session.screenReportProgramStatus(report("state=done"))
        session.notified = []
        session.recordNotifications = []

        session.screenPromptDidStart(atLine: 0)
        drainMainQueue()

        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertEqual(session.notified, [])
        XCTAssertEqual(session.recordNotifications, [])
    }

    func testDoneShownAgainAfterResetDoesNotNotify() {
        let session = NotificationSpySession(synthetic: false)!
        session.screenReportProgramStatus(report("state=done"))
        session.recordNotifications = []

        // What a reset other than RIS does: clear the status, then let the
        // surviving records show again. Only the second step is in question.
        session.screenSetTabStatus(VT100TabStatusUpdate.clear)
        session.notified = []
        session.screenDidClearTabStatusForReset()

        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertEqual(session.notified, [])
        XCTAssertEqual(session.recordNotifications, [])
    }

    func testRecordWrittenAfterPromptStillNotifies() {
        let session = NotificationSpySession(synthetic: false)!
        session.screenPromptDidStart(atLine: 0)
        // A background job reports before the prompt's cleanup runs.
        session.screenReportProgramStatus(report("state=done:id=job"))
        drainMainQueue()

        XCTAssertEqual(session.tabStatus?.statusText, "done")
        XCTAssertEqual(session.recordNotifications.count, 1)
        XCTAssertEqual(session.notified, [])
    }

    /// A session whose screen reports to it, as a fully set-up session's does
    /// (a synthetic one is never wired up), so that a change made through the
    /// screen can reach the session's mode.
    private func sessionInCopyMode() -> PTYSession {
        let session = PTYSession(synthetic: false)!
        session.screen.delegate = session
        session.copyMode = true
        return session
    }

    // The bar changes because of what the program printed, so it must not do
    // what a user's change does and end copy mode.
    func testProgressFromReportKeepsCopyMode() throws {
        let session = sessionInCopyMode()
        try XCTSkipUnless(session.copyMode, "Copy mode is unavailable in this session")

        session.screenReportProgramStatus(report("state=working:progress=40"))
        session.screenReportProgramStatus(report("state=blocked"))
        session.screenReportProgramStatus(report("state=clear"))

        XCTAssertTrue(session.copyMode)
    }

    // The control for the test above: a change made the user's way does end
    // copy mode, so the test above is measuring something.
    func testUserMutationEndsCopyMode() throws {
        let session = sessionInCopyMode()
        try XCTSkipUnless(session.copyMode, "Copy mode is unavailable in this session")

        session.screen.mutateAsynchronously { _, _, _ in }

        XCTAssertFalse(session.copyMode)
    }

    // A reset the main thread has not heard about yet must stop a write the
    // records queued on the strength of the bar from before it.
    func testProgressWriteQueuedBeforeResetIsDropped() {
        let session = PTYSession(synthetic: false)!
        let screen = session.screen
        screen.delegate = session
        let before = VT100ScreenProgress(rawValue: VT100ScreenProgress.successBase.rawValue + 30)!
        // An OSC 9;4 bar the main thread knows about.
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.progress = before
        })
        XCTAssertEqual(screen.progress, before)

        // The mutation thread resets the bar. The main thread's copy still
        // shows the old bar until it next syncs, and the reset's own news has
        // not arrived.
        screen.mutateAsynchronouslyKeepingMode { _, mutableState, _ in
            mutableState.terminalDidReset()
        }

        // A blocked record pauses what it believes is showing.
        session.screenReportProgramStatus(ProgramStatusReport.parse("state=blocked")!)

        var after: VT100ScreenProgress?
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            after = mutableState.progress
        })
        XCTAssertEqual(after, .stopped)
    }
}
