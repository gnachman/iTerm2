//
//  ProgramStatusTests.swift
//  ModernTests
//
//  The Program Status Protocol (OSC 7501): parsing and validating a report,
//  the per-id records, and how the records drive the tab status and the
//  progress bar.
//

import XCTest
@testable import iTerm2SharedARC

private func b64(_ text: String) -> String {
    return Data(text.utf8).base64EncodedString()
}

final class ProgramStatusReportParsingTests: XCTestCase {
    private func parse(_ body: String) -> ProgramStatusReport? {
        return ProgramStatusReport.parse(body)
    }

    func testMinimalReport() {
        let report = parse("state=working")
        XCTAssertEqual(report?.state, .working)
        XCTAssertEqual(report?.id, [])
        XCTAssertNil(report?.msg)
    }

    func testAllKeys() {
        let report = parse("state=blocked:kind=permission:app=terraform:progress=40:id=a/b:title=\(b64("Plan")):msg=\(b64("Apply?"))")
        XCTAssertEqual(report?.state, .blocked)
        XCTAssertEqual(report?.kind, .permission)
        XCTAssertEqual(report?.app, "terraform")
        XCTAssertEqual(report?.progress, 40)
        XCTAssertEqual(report?.id, ["a", "b"])
        XCTAssertEqual(report?.title, "Plan")
        XCTAssertEqual(report?.msg, "Apply?")
    }

    func testSpecExampleDecodes() {
        let report = parse("state=blocked:kind=permission:app=terraform:msg=QXBwbHkgMyB0byBhZGQsIDEgdG8gY2hhbmdlLCAwIHRvIGRlc3Ryb3k/")
        XCTAssertEqual(report?.msg, "Apply 3 to add, 1 to change, 0 to destroy?")
    }

    func testMissingOrUnknownStateIsIgnored() {
        XCTAssertNil(parse("msg=\(b64("hi"))"))
        XCTAssertNil(parse("state=sleeping"))
        XCTAssertNil(parse(""))
    }

    func testFeatureQuery() {
        XCTAssertTrue(ProgramStatusReport.isFeatureQuery("?"))
        XCTAssertFalse(ProgramStatusReport.isFeatureQuery("state=idle"))
        XCTAssertNil(parse("?"))
    }

    func testWhitespaceAroundKeysAndValuesIsRemoved() {
        XCTAssertEqual(parse(" state = done ")?.state, .done)
    }

    func testMalformedPairsAreSkipped() {
        // No =, empty key, uppercase key, and a value byte outside the set.
        let report = parse("bogus:=x:STATE=idle:app=has space:state=working")
        XCTAssertEqual(report?.state, .working)
        XCTAssertNil(report?.app)
    }

    func testUnknownKeysAreIgnored() {
        XCTAssertEqual(parse("state=idle:future=1")?.state, .idle)
    }

    func testLastRepeatedKeyWins() {
        XCTAssertEqual(parse("state=idle:state=error")?.state, .error)
    }

    func testPaddingIsOptional() {
        // "ab" encodes as YWI= with padding.
        XCTAssertEqual(parse("state=idle:msg=YWI")?.msg, "ab")
        XCTAssertEqual(parse("state=idle:msg=YWI=")?.msg, "ab")
    }

    func testBadBase64DiscardsReport() {
        XCTAssertNil(parse("state=idle:msg=Y"))
        XCTAssertNil(parse("state=idle:msg====="))
    }

    func testControlCharacterDiscardsReport() {
        XCTAssertNil(parse("state=idle:msg=\(b64("a\nb"))"))
        XCTAssertNil(parse("state=idle:title=\(b64("a\u{1b}b"))"))
        XCTAssertNil(parse("state=idle:msg=\(b64("a\u{85}b"))"))
    }

    func testInvalidUTF8DiscardsReport() {
        let bytes = Data([0xff, 0xfe])
        XCTAssertNil(parse("state=idle:msg=\(bytes.base64EncodedString())"))
    }

    func testMalformedIDIgnoresReport() {
        XCTAssertNil(parse("state=idle:id=a//b"))
        XCTAssertNil(parse("state=idle:id=/a"))
        XCTAssertNil(parse("state=idle:id=" + String(repeating: "x", count: 33)))
    }

    func testIDLimits() {
        let eight = Array(repeating: "a", count: 8).joined(separator: "/")
        XCTAssertEqual(parse("state=idle:id=\(eight)")?.id.count, 8)
        XCTAssertNil(parse("state=idle:id=\(eight)/a"))
        let long = Array(repeating: String(repeating: "x", count: 30), count: 5).joined(separator: "/")
        XCTAssertGreaterThan(long.utf8.count, 128)
        XCTAssertNil(parse("state=idle:id=\(long)"))
    }

    func testKindOnlyWithBlocked() {
        XCTAssertNil(parse("state=working:kind=permission")?.kind)
        XCTAssertEqual(parse("state=blocked:kind=auth")?.kind, .auth)
        XCTAssertNil(parse("state=blocked:kind=telepathy")?.kind)
        XCTAssertEqual(parse("state=blocked:kind=telepathy")?.state, .blocked)
    }

    func testProgressOnlyWithWorkingOrBlocked() {
        XCTAssertEqual(parse("state=working:progress=0")?.progress, 0)
        XCTAssertEqual(parse("state=blocked:progress=100")?.progress, 100)
        XCTAssertNil(parse("state=done:progress=50")?.progress)
        XCTAssertNil(parse("state=working:progress=101")?.progress)
        XCTAssertNil(parse("state=working:progress=-1")?.progress)
        XCTAssertNil(parse("state=working:progress=5.5")?.progress)
        XCTAssertNil(parse("state=working:progress=+5")?.progress)
        XCTAssertEqual(parse("state=working:progress=+5")?.state, .working)
    }

    func testAppOutsideCharacterSetIsAbsent() {
        XCTAssertNil(parse("state=idle:app=a/b")?.app)
        XCTAssertEqual(parse("state=idle:app=claude-code")?.app, "claude-code")
    }

    func testAppLimitDiscardsReport() {
        XCTAssertNil(parse("state=idle:app=" + String(repeating: "a", count: 33)))
    }

    func testKeyLimitDiscardsReport() {
        XCTAssertNil(parse("state=idle:" + String(repeating: "k", count: 17) + "=1"))
        XCTAssertNotNil(parse("state=idle:" + String(repeating: "k", count: 16) + "=1"))
    }

    func testMsgLimits() {
        let maxDecoded = String(repeating: "a", count: 2048)
        XCTAssertEqual(parse("state=idle:msg=\(b64(maxDecoded))")?.msg, maxDecoded)
        XCTAssertNil(parse("state=idle:msg=\(b64(maxDecoded + "a"))"))
    }

    func testTitleLimits() {
        let maxDecoded = String(repeating: "a", count: 192)
        XCTAssertEqual(parse("state=idle:title=\(b64(maxDecoded))")?.title, maxDecoded)
        XCTAssertNil(parse("state=idle:title=\(b64(maxDecoded + "a"))"))
    }

    func testEarlierPairOverLimitDiscardsEvenIfReplaced() {
        let tooLong = b64(String(repeating: "a", count: 2100))
        XCTAssertNil(parse("state=idle:msg=\(tooLong):msg=\(b64("ok"))"))
    }

    func testWholeSequenceLimit() {
        let padding = String(repeating: "x", count: 4096)
        XCTAssertNil(parse("state=idle:pad=\(padding)"))
    }

    func testBadTextDiscardsEvenWhenOtherwiseUnused() {
        // A clear does not show msg, but undecodable text still discards it.
        XCTAssertNil(parse("state=clear:msg=Y"))
    }
}

final class ProgramStatusRecordsTests: XCTestCase {
    private func report(_ body: String) -> ProgramStatusReport {
        return ProgramStatusReport.parse(body)!
    }

    func testReportReplacesRecordCompletely() {
        var records = ProgramStatusRecords()
        records.apply(report("state=working:app=brew:msg=\(b64("one"))"))
        records.apply(report("state=done"))
        XCTAssertEqual(records.mostUrgent?.state, .done)
        XCTAssertNil(records.mostUrgent?.app)
        XCTAssertNil(records.mostUrgent?.msg)
    }

    func testMostUrgentWins() {
        var records = ProgramStatusRecords()
        records.apply(report("state=working"))
        records.apply(report("state=blocked:id=eu"))
        records.apply(report("state=done:id=us"))
        XCTAssertEqual(records.mostUrgent?.id, ["eu"])
    }

    func testTieGoesToMostRecent() {
        var records = ProgramStatusRecords()
        records.apply(report("state=working:id=a"))
        records.apply(report("state=working:id=b"))
        XCTAssertEqual(records.mostUrgent?.id, ["b"])
        records.apply(report("state=working:id=a"))
        XCTAssertEqual(records.mostUrgent?.id, ["a"])
    }

    func testAppIsInheritedFromNearestAncestor() {
        var records = ProgramStatusRecords()
        records.apply(report("state=working:app=deploy"))
        records.apply(report("state=working:id=build:app=cargo"))
        records.apply(report("state=blocked:id=build/test/unit"))
        XCTAssertEqual(records.mostUrgent?.app, "cargo")
        records.apply(report("state=clear:id=build"))
        records.apply(report("state=blocked:id=x/y"))
        XCTAssertEqual(records.mostUrgent?.app, "deploy")
    }

    func testClearRemovesSubtree() {
        var records = ProgramStatusRecords()
        records.apply(report("state=working"))
        records.apply(report("state=working:id=a"))
        records.apply(report("state=working:id=a/b"))
        records.apply(report("state=working:id=ab"))
        records.apply(report("state=clear:id=a"))
        XCTAssertEqual(Set(records.records.keys), ["", "ab"])
    }

    func testClearWithNoIDRemovesEverything() {
        var records = ProgramStatusRecords()
        records.apply(report("state=working"))
        records.apply(report("state=working:id=a"))
        records.apply(report("state=clear"))
        XCTAssertTrue(records.isEmpty)
    }

    func testEvictsLeastRecentlyUpdated() {
        var records = ProgramStatusRecords(capacity: 3)
        records.apply(report("state=working:id=a"))
        records.apply(report("state=working:id=b"))
        records.apply(report("state=working:id=c"))
        records.apply(report("state=working:id=a"))
        records.apply(report("state=working:id=d"))
        XCTAssertEqual(Set(records.records.keys), ["a", "c", "d"])
    }

    func testUpdatingExistingRecordAtCapacityEvictsNothing() {
        var records = ProgramStatusRecords(capacity: 2)
        records.apply(report("state=working:id=a"))
        records.apply(report("state=working:id=b"))
        records.apply(report("state=done:id=a"))
        XCTAssertEqual(Set(records.records.keys), ["a", "b"])
    }
}

final class ProgramStatusControllerTests: XCTestCase {
    private var controller: ProgramStatusController!
    private var updates = [VT100TabStatusUpdate]()
    private var screenProgress = VT100ScreenProgress.stopped
    private var progressSets = [VT100ScreenProgress]()

    override func setUp() {
        super.setUp()
        updates = []
        progressSets = []
        screenProgress = .stopped
        controller = ProgramStatusController(
            applyStatus: { [unowned self] update in
                updates.append(update)
            },
            currentProgress: { [unowned self] in
                screenProgress
            },
            setProgress: { [unowned self] progress in
                progressSets.append(progress)
                screenProgress = progress
            })
    }

    private func send(_ body: String) {
        controller.handle(ProgramStatusReport.parse(body)!)
    }

    private func progress(_ base: VT100ScreenProgress, _ percentage: Int) -> VT100ScreenProgress {
        return VT100ScreenProgress(rawValue: base.rawValue + percentage)!
    }

    func testStatusFieldsForEachState() {
        let expected: [(String, String)] = [("idle", "idle"),
                                            ("working", "working"),
                                            ("blocked", "waiting"),
                                            ("done", "done"),
                                            ("error", "error")]
        for (state, status) in expected {
            send("state=\(state)")
            XCTAssertEqual(updates.last?.statusPresence, .set)
            XCTAssertEqual(updates.last?.status, status)
            XCTAssertEqual(updates.last?.indicatorPresence, .set)
            XCTAssertEqual(updates.last?.detailPresence, .cleared)
        }
    }

    func testMessageBecomesDetail() {
        send("state=working:msg=\(b64("Installing updates"))")
        XCTAssertEqual(updates.last?.detail, "Installing updates")
    }

    func testKindDescribesBlockWithoutMessage() {
        send("state=blocked:kind=auth")
        XCTAssertEqual(updates.last?.detail, "Waiting for login")
    }

    func testChildTitlePrefixesDetail() {
        send("state=blocked:id=eu:title=\(b64("EU West")):msg=\(b64("Approve?"))")
        XCTAssertEqual(updates.last?.detail, "EU West: Approve?")
    }

    func testRootTitleIsNotShown() {
        send("state=working:title=\(b64("Root")):msg=\(b64("Busy"))")
        XCTAssertEqual(updates.last?.detail, "Busy")
    }

    func testKeypressTurnsOnlyRecordIdleKeepingMessage() {
        send("state=done:msg=\(b64("Deployed"))")
        controller.userDidPressKey()
        XCTAssertEqual(updates.last?.status, "idle")
        XCTAssertEqual(updates.last?.detail, "Deployed")
        // Idle ends with the command like any other idle record.
        updates = []
        controller.commandDidEnd()
        XCTAssertTrue(updates.isEmpty)
    }

    func testJoinersAndTagsSurviveSanitizing() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let persian = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}"
        for text in [family, scotland, persian] {
            XCTAssertEqual(ProgramStatusController.sanitized(text), text)
        }
        // Direction controls are still removed.
        XCTAssertEqual(ProgramStatusController.sanitized("a\u{2066}b\u{200F}c\u{061C}d"), "abcd")
    }

    func testInvisibleFormattingIsRemoved() {
        send("state=working:msg=\(b64("a\u{202E}b\u{200B}c\u{2028}d"))")
        XCTAssertEqual(updates.last?.detail, "abcd")
    }

    func testClearingLastRecordClearsStatus() {
        send("state=working")
        send("state=clear")
        XCTAssertEqual(updates.last?.statusPresence, .cleared)
    }

    func testCommandEndKeepsOnlyFinishedRecords() {
        send("state=done:id=a")
        send("state=working:id=b")
        send("state=blocked:id=c")
        updates = []
        controller.commandDidEnd()
        XCTAssertEqual(updates.last?.status, "done")
    }

    func testCommandEndWithNothingLeftDoesNotTouchStatus() {
        // The caller already cleared the status; clearing it again would be
        // harmless but noisy.
        send("state=working")
        updates = []
        controller.commandDidEnd()
        XCTAssertTrue(updates.isEmpty)
    }

    func testKeypressDismissesFinishedRecords() {
        send("state=working")
        send("state=done:id=a")
        XCTAssertEqual(updates.last?.status, "done")
        controller.userDidPressKey()
        XCTAssertEqual(updates.last?.status, "working")
        controller.userDidPressKey()
        XCTAssertEqual(updates.last?.status, "working")
    }

    func testKeypressDoesNotOverwriteAnotherWriter() {
        send("state=done")
        controller.otherWriterDidSetStatus()
        updates = []
        controller.userDidPressKey()
        XCTAssertTrue(updates.isEmpty)
    }

    func testRemoveAllRecordsClearsShownStatus() {
        send("state=done")
        updates = []
        controller.removeAllRecords()
        XCTAssertEqual(updates.map(\.statusPresence), [.cleared])
        updates = []
        controller.commandDidEnd()
        XCTAssertTrue(updates.isEmpty)
    }

    func testRemoveAllRecordsLeavesAnotherWritersStatus() {
        send("state=done")
        controller.otherWriterDidSetStatus()
        updates = []
        controller.removeAllRecords()
        XCTAssertTrue(updates.isEmpty)
    }

    func testStatusWasClearedShowsRecordsAgain() {
        send("state=working")
        updates = []
        controller.statusWasCleared()
        XCTAssertEqual(updates.last?.status, "working")
    }

    func testRecordWrittenAfterPromptSurvivesPromptCleanup() {
        send("state=working:id=old")
        let mark = controller.serial
        send("state=working:id=new:msg=\(b64("background"))")
        updates = []
        controller.commandDidEnd(through: mark)
        XCTAssertEqual(updates.last?.detail, "background")
    }

    func testRewrittenRecordSurvivesPromptCleanup() {
        send("state=working")
        let mark = controller.serial
        send("state=working:msg=\(b64("again"))")
        updates = []
        controller.commandDidEnd(through: mark)
        XCTAssertEqual(updates.last?.detail, "again")
    }

    func testDismissedErrorDoesNotLeaveRedBar() {
        send("state=working")
        send("state=working:id=x:progress=50")
        send("state=error:id=x")
        XCTAssertEqual(progressSets.last, progress(.errorBase, 50))
        // The root record now wins, and it carries no progress.
        controller.userDidPressKey()
        XCTAssertEqual(progressSets.last, .stopped)
    }

    func testWorkingWithoutProgressAfterBlockRemovesRecordsBar() {
        send("state=working:progress=30")
        send("state=blocked:kind=permission")
        XCTAssertEqual(progressSets.last, progress(.warningBase, 30))
        // Each report replaces its record, and this one has no progress.
        send("state=working")
        XCTAssertEqual(progressSets.last, .stopped)
    }

    func testWorkingWithoutProgressRemovesEarlierPercentage() {
        send("state=working:progress=100")
        send("state=working")
        XCTAssertEqual(progressSets, [progress(.successBase, 100), .stopped])
    }

    func testClearingBlockGivesBorrowedBarBack() {
        screenProgress = progress(.successBase, 40)
        send("state=blocked")
        XCTAssertEqual(progressSets.last, progress(.warningBase, 40))
        send("state=clear")
        XCTAssertEqual(progressSets.last, progress(.successBase, 40))
    }

    func testIdleAfterBlockGivesBorrowedBarBack() {
        screenProgress = progress(.successBase, 40)
        send("state=blocked")
        send("state=idle")
        XCTAssertEqual(progressSets.last, progress(.successBase, 40))
    }

    func testDoneAfterBlockGivesPausedSpinnerBack() {
        screenProgress = .indeterminate
        send("state=blocked")
        XCTAssertEqual(progressSets.last, .pausedIndeterminate)
        send("state=done")
        XCTAssertEqual(progressSets.last, .indeterminate)
    }

    func testResetDoesNotBorrowStaleBar() {
        // A full reset stops the bar, then removes the records. In between,
        // the screen's progress as seen from the main thread can still show
        // the bar from before the reset.
        screenProgress = progress(.successBase, 40)
        send("state=blocked")
        progressSets = []
        controller.progressWasReset()
        controller.removeAllRecords()
        // Nothing put the old bar back: the reset's stopped bar stands.
        XCTAssertTrue(progressSets.isEmpty, "\(progressSets)")
    }

    func testWorkingAfterBlockGivesBorrowedBarBack() {
        // OSC 9;4 put this bar up; the records only paused it.
        screenProgress = progress(.successBase, 30)
        send("state=blocked")
        XCTAssertEqual(progressSets.last, progress(.warningBase, 30))
        send("state=working")
        XCTAssertEqual(progressSets.last, progress(.successBase, 30))
        // And it is no longer the records' to remove.
        progressSets = []
        send("state=done")
        XCTAssertTrue(progressSets.isEmpty)
    }

    func testResetPutsSurvivingRecordsBarBack() {
        send("state=working:progress=40")
        // A reset stops the bar without the controller's help.
        screenProgress = .stopped
        controller.progressWasReset()
        XCTAssertEqual(progressSets, [progress(.successBase, 40), progress(.successBase, 40)])
        // And a later report with the same percentage is not mistaken for
        // one that is already showing.
        controller.progressWasReset()
        send("state=working:progress=40")
        XCTAssertEqual(progressSets.count, 3)
    }

    func testResetWithNoRecordsLeavesBarAlone() {
        controller.progressWasReset()
        XCTAssertTrue(progressSets.isEmpty)
        XCTAssertTrue(updates.isEmpty)
    }

    func testKeypressReleasesBarEvenWhenAnotherWriterOwnsStatus() {
        send("state=working:progress=50")
        send("state=error")
        controller.otherWriterDidSetStatus()
        updates = []
        controller.userDidPressKey()
        XCTAssertTrue(updates.isEmpty)
        XCTAssertEqual(progressSets.last, .stopped)
    }

    // MARK: - Progress bar

    func testWorkingWithProgressSetsBar() {
        send("state=working:progress=40")
        XCTAssertEqual(progressSets, [progress(.successBase, 40)])
    }

    func testWorkingWithoutProgressLeavesBarAlone() {
        send("state=working")
        XCTAssertTrue(progressSets.isEmpty)
    }

    func testBlockedWithProgressShowsPaused() {
        send("state=blocked:progress=60")
        XCTAssertEqual(progressSets, [progress(.warningBase, 60)])
    }

    func testBlockedWithoutProgressPausesVisibleBar() {
        screenProgress = progress(.successBase, 30)
        send("state=blocked")
        XCTAssertEqual(progressSets, [progress(.warningBase, 30)])
    }

    func testBlockedWithoutProgressPausesSpinnerAndWorkingResumesIt() {
        screenProgress = .indeterminate
        send("state=blocked")
        XCTAssertEqual(progressSets, [.pausedIndeterminate])
        send("state=working")
        XCTAssertEqual(progressSets, [.pausedIndeterminate, .indeterminate])
    }

    func testBlockedWithoutProgressAndNoBarDoesNothing() {
        send("state=blocked")
        XCTAssertTrue(progressSets.isEmpty)
    }

    func testErrorTurnsOwnedBarRed() {
        send("state=working:progress=70")
        send("state=error")
        XCTAssertEqual(progressSets.last, progress(.errorBase, 70))
    }

    func testErrorLeavesForeignBarAlone() {
        screenProgress = progress(.successBase, 70)
        send("state=error")
        XCTAssertTrue(progressSets.isEmpty)
    }

    func testDoneRemovesOwnedBar() {
        send("state=working:progress=70")
        send("state=done")
        XCTAssertEqual(progressSets.last, .stopped)
    }

    func testDoneLeavesForeignBarAlone() {
        screenProgress = progress(.successBase, 70)
        send("state=done")
        XCTAssertTrue(progressSets.isEmpty)
    }

    func testProgressProtocolTakesOverBar() {
        send("state=working:progress=10")
        controller.progressProtocolDidReport()
        screenProgress = progress(.successBase, 50)
        send("state=done")
        XCTAssertEqual(progressSets, [progress(.successBase, 10)])
    }

    func testOwnedBarIsTrackedWithoutWaitingForScreen() {
        // The screen catches up with a change only after a sync, so the
        // controller must not rely on reading back what it just set.
        controller = ProgramStatusController(
            applyStatus: { _ in },
            currentProgress: { .stopped },
            setProgress: { [unowned self] progress in
                progressSets.append(progress)
            })
        send("state=working:progress=10")
        send("state=done")
        XCTAssertEqual(progressSets, [progress(.successBase, 10), .stopped])
    }

    func testCommandEndRemovesOwnedBar() {
        send("state=working:progress=10")
        controller.commandDidEnd()
        XCTAssertEqual(progressSets.last, .stopped)
    }

    // QA finding F-307: a batch sets the tab status once, for where the
    // records ended up.
    func testBatchSetsStatusOnce() {
        controller.handle((0..<5000).flatMap { _ in
            [ProgramStatusReport.parse("state=working:id=a")!, ProgramStatusReport.parse("state=blocked:id=a")!]
        })
        XCTAssertEqual(updates.map(\.status), ["waiting"])
    }

    func testUnchangedProgressIsNotResent() {
        send("state=working:progress=10")
        send("state=working:progress=10:msg=\(b64("still"))")
        XCTAssertEqual(progressSets.count, 1)
    }
}

final class ProgramStatusTerminalTests: XCTestCase {
    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        harness.screen.inject(string.data(using: .utf8)!)
        harness.screen.waitForQueuedTokensForTesting()
    }

    func testReportReachesDelegate() {
        let harness = TerminalTestHarness()
        feed(harness, "\u{1b}]7501;state=working:app=brew\u{1b}\\")
        feed(harness, "\u{1b}]7501;state=done\u{07}")
        XCTAssertEqual(harness.delegate.programStatusReports.map(\.state), [.working, .done])
        XCTAssertEqual(harness.delegate.programStatusReports.first?.app, "brew")
    }

    private func flood(_ reports: [String], times: Int) -> String {
        let iteration = reports.map { "\u{1b}]7501;\($0)\u{07}" }.joined()
        return String(repeating: iteration, count: times)
    }

    /// Calls the terminal delegate method for each report inside one joined
    /// block, the way the parser would with nothing else in between, then
    /// lets the side effects run.
    private func report(_ harness: TerminalTestHarness, _ bodies: [String]) {
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for body in bodies {
                mutableState.terminalReportProgramStatus(ProgramStatusReport.parse(body)!)
            }
        })
        harness.sync()
    }

    // QA finding F-307: a program flipping one record between two states as
    // fast as it can write must not cost the main thread a side effect per
    // report. Reports for the same record with nothing else in between
    // collapse to the latest.
    func testReportsForOneRecordCollapseIntoOneDelivery() {
        let harness = TerminalTestHarness()
        report(harness, Array(repeating: ["state=working:id=a", "state=blocked:id=a"], count: 5000).flatMap { $0 })
        XCTAssertEqual(harness.delegate.programStatusDeliveries, 1)
        XCTAssertEqual(harness.delegate.programStatusReports.map(\.description),
                       ["<ProgramStatusReport state=blocked id=a>"])
    }

    // Reports for several records are delivered together, and each record's
    // reports collapse to its latest, so the batch stays as small as the
    // number of records however long the flood.
    func testReportsForSeveralRecordsAreDeliveredTogether() {
        let harness = TerminalTestHarness()
        report(harness, Array(repeating: ["state=working:id=a", "state=blocked:id=b"], count: 5000).flatMap { $0 })
        XCTAssertEqual(harness.delegate.programStatusDeliveries, 1)
        XCTAssertEqual(harness.delegate.programStatusReports.map(\.description),
                       ["<ProgramStatusReport state=working id=a>",
                        "<ProgramStatusReport state=blocked id=b>"])
    }

    // A clear is never folded into a report for the same record, or the other
    // way round, since a clear also removes the record's children.
    func testClearIsNotCollapsed() {
        let harness = TerminalTestHarness()
        report(harness, ["state=working:id=a",
                         "state=clear:id=a",
                         "state=working:id=a",
                         "state=blocked:id=a"])
        XCTAssertEqual(harness.delegate.programStatusEvents,
                       ["report working", "report clear", "report blocked"])
    }

    // Coalescing must not move a report past a side effect that came after
    // it, such as a full reset.
    func testCoalescedReportsKeepTheirPlaceAroundOtherSideEffects() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalReportProgramStatus(ProgramStatusReport.parse("state=working:id=a")!)
            mutableState.terminalReportProgramStatus(ProgramStatusReport.parse("state=blocked:id=a")!)
            mutableState.terminalRemoveProgramStatusRecords()
            mutableState.terminalReportProgramStatus(ProgramStatusReport.parse("state=done:id=a")!)
        })
        harness.sync()
        XCTAssertEqual(harness.delegate.programStatusEvents,
                       ["report blocked", "remove", "report done"])
    }

    // End to end through the parser, run synchronously in one joined block.
    func testFloodThroughParserIsCoalesced() {
        let harness = TerminalTestHarness()
        harness.feedEscapeSequence(Array(flood(["state=working:id=a", "state=blocked:id=a"], times: 5000).utf8))
        harness.sync()
        XCTAssertEqual(harness.delegate.programStatusDeliveries, 1)
        XCTAssertEqual(harness.delegate.programStatusReports.map(\.description),
                       ["<ProgramStatusReport state=blocked id=a>"])
    }

    // A report that arrives after its batch went to the main thread starts a
    // new one rather than being lost.
    func testReportAfterBatchWasTakenStartsANewBatch() {
        let harness = TerminalTestHarness()
        report(harness, ["state=working:id=a"])
        report(harness, ["state=blocked:id=a"])
        XCTAssertEqual(harness.delegate.programStatusDeliveries, 2)
        XCTAssertEqual(harness.delegate.programStatusEvents, ["report working", "report blocked"])
    }

    func testInvalidReportIsNotDelivered() {
        let harness = TerminalTestHarness()
        feed(harness, "\u{1b}]7501;state=bogus\u{1b}\\")
        XCTAssertTrue(harness.delegate.programStatusReports.isEmpty)
    }

    func testFullResetRemovesRecords() {
        let harness = TerminalTestHarness()
        feed(harness, "\u{1b}c")
        XCTAssertEqual(harness.delegate.removeProgramStatusRecordsCount, 1)
    }

    func testSoftResetKeepsRecords() {
        let harness = TerminalTestHarness()
        feed(harness, "\u{1b}[!p")
        XCTAssertEqual(harness.delegate.removeProgramStatusRecordsCount, 0)
    }

    func testFeatureQueryIsAnswered() {
        let harness = TerminalTestHarness()
        feed(harness, "\u{1b}]7501;?\u{1b}\\")
        let deadline = Date().addingTimeInterval(5)
        while harness.delegate.sentReports.isEmpty && Date() < deadline {
            harness.sync()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(harness.delegate.sentReports, [Data("\u{1b}]7501;?\u{1b}\\".utf8)])
        XCTAssertTrue(harness.delegate.programStatusReports.isEmpty)
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class ProgramStatusReportBatchTests: XCTestCase {
    private func report(_ body: String) -> ProgramStatusReport {
        return ProgramStatusReport.parse(body)!
    }

    private func contents(_ batch: ProgramStatusReportBatch) -> [String] {
        return batch.take().map(\.description)
    }

    func testTakenBatchAcceptsNothingMore() {
        let batch = ProgramStatusReportBatch(report: report("state=working"))
        XCTAssertEqual(batch.take().count, 1)
        XCTAssertFalse(batch.add(report("state=done")))
        XCTAssertEqual(batch.take(), [])
    }

    // A rewritten record moves to the end, where its last write was, so the
    // records come out written in the same order as without coalescing.
    func testLatestReportPerRecordWinsInOrderOfLastWrite() {
        let batch = ProgramStatusReportBatch(report: report("state=working:id=a"))
        XCTAssertTrue(batch.add(report("state=working:id=b")))
        XCTAssertTrue(batch.add(report("state=blocked:id=a")))
        XCTAssertTrue(batch.add(report("state=working:id=c")))
        XCTAssertEqual(contents(batch), ["<ProgramStatusReport state=working id=b>",
                                         "<ProgramStatusReport state=blocked id=a>",
                                         "<ProgramStatusReport state=working id=c>"])
    }

    // A clear may remove other records too, so nothing is moved across it.
    func testClearIsABarrier() {
        let batch = ProgramStatusReportBatch(report: report("state=working:id=a/b"))
        XCTAssertTrue(batch.add(report("state=clear:id=a")))
        XCTAssertTrue(batch.add(report("state=working:id=a/b")))
        XCTAssertTrue(batch.add(report("state=blocked:id=a/b")))
        XCTAssertTrue(batch.add(report("state=clear:id=a")))
        XCTAssertEqual(contents(batch), ["<ProgramStatusReport state=working id=a/b>",
                                         "<ProgramStatusReport state=clear id=a>",
                                         "<ProgramStatusReport state=blocked id=a/b>",
                                         "<ProgramStatusReport state=clear id=a>"])
    }

    func testRepeatedClearsFold() {
        let batch = ProgramStatusReportBatch(report: report("state=clear:id=a"))
        for _ in 0..<10000 {
            XCTAssertTrue(batch.add(report("state=clear:id=a")))
        }
        XCTAssertEqual(batch.storageCount, 1)
    }

    func testRootClearDropsEverythingBefore() {
        let batch = ProgramStatusReportBatch(report: report("state=working:id=a"))
        XCTAssertTrue(batch.add(report("state=clear:id=b")))
        XCTAssertTrue(batch.add(report("state=working:id=b")))
        XCTAssertTrue(batch.add(report("state=clear")))
        XCTAssertTrue(batch.add(report("state=working:id=c")))
        XCTAssertEqual(contents(batch), ["<ProgramStatusReport state=clear>",
                                         "<ProgramStatusReport state=working id=c>"])
    }

    // Applying what the batch hands over must leave the records exactly as
    // applying every report would, for any mix of reports, clears and
    // evictions.
    func testBatchMatchesApplyingEveryReport() {
        var rng = SplitMix64(seed: 7501)
        let keys = ["", "a", "b", "a/x", "a/y", "c"]
        let states = ["idle", "working", "done", "blocked", "error", "clear", "clear"]
        func randomReport() -> ProgramStatusReport {
            let key = keys[Int(rng.next() % UInt64(keys.count))]
            let state = states[Int(rng.next() % UInt64(states.count))]
            let msg = "m\(rng.next() % 4)"
            return report("state=\(state)" + (key.isEmpty ? "" : ":id=\(key)") + ":msg=\(Data(msg.utf8).base64EncodedString())")
        }
        struct Snapshot: Equatable {
            var key: String
            var state: ProgramStatusReport.State
            var msg: String?
        }
        func snapshot(_ records: ProgramStatusRecords) -> [Snapshot] {
            return records.records.values
                .sorted { $0.serial < $1.serial }
                .map { Snapshot(key: $0.id.joined(separator: "/"), state: $0.state, msg: $0.msg) }
        }
        for iteration in 0..<2000 {
            var base = ProgramStatusRecords(capacity: 3)
            for _ in 0..<Int(rng.next() % 6) {
                base.apply(randomReport())
            }
            let reports = (0..<(1 + Int(rng.next() % 60))).map { _ in randomReport() }

            var sequential = base
            reports.forEach { sequential.apply($0) }

            let batch = ProgramStatusReportBatch(report: reports[0])
            for report in reports.dropFirst() {
                XCTAssertTrue(batch.add(report))
            }
            var batched = base
            batch.take().forEach { batched.apply($0) }

            XCTAssertEqual(snapshot(sequential), snapshot(batched), "iteration \(iteration): \(reports)")
        }
    }

    // A controller handed the coalesced batch announces the same records, in
    // the same states, as one handed every report, including when records
    // are evicted.
    func testBatchAnnouncesTheSameAsEveryReport() {
        var rng = SplitMix64(seed: 21337)
        let keys = ["", "a", "b", "a/x", "c", "d"]
        let states = ["idle", "working", "done", "blocked", "error", "clear"]
        func randomReport() -> ProgramStatusReport {
            let key = keys[Int(rng.next() % UInt64(keys.count))]
            let state = states[Int(rng.next() % UInt64(states.count))]
            return report("state=\(state)" + (key.isEmpty ? "" : ":id=\(key)"))
        }
        func makeController(_ announced: @escaping (ProgramStatusDisplayRecord) -> Void) -> ProgramStatusController {
            return ProgramStatusController(applyStatus: { _ in },
                                           currentProgress: { .stopped },
                                           setProgress: { _ in },
                                           recordsDidChange: {},
                                           recordDidChangeState: announced,
                                           capacity: 3)
        }
        for iteration in 0..<2000 {
            let prefix = (0..<Int(rng.next() % 6)).map { _ in randomReport() }
            let reports = (0..<(1 + Int(rng.next() % 40))).map { _ in randomReport() }
            var announcedRaw = [String]()
            var announcedBatched = [String]()
            let raw = makeController { announcedRaw.append("\($0.key)=\($0.statusText)") }
            let batched = makeController { announcedBatched.append("\($0.key)=\($0.statusText)") }
            raw.handle(prefix)
            batched.handle(prefix)
            announcedRaw = []
            announcedBatched = []

            raw.handle(reports)
            let batch = ProgramStatusReportBatch(report: reports[0])
            for report in reports.dropFirst() {
                XCTAssertTrue(batch.add(report))
            }
            batched.handle(batch.take())
            XCTAssertEqual(Set(announcedRaw), Set(announcedBatched), "iteration \(iteration): \(prefix) then \(reports)")
        }
    }

    // However long a flood across a few records, the batch holds one report
    // per record.
    func testFloodAcrossRecordsStaysSmall() {
        let batch = ProgramStatusReportBatch(report: report("state=working:id=a"))
        for i in 0..<10000 {
            XCTAssertTrue(batch.add(report("state=\(i % 2 == 0 ? "blocked" : "working"):id=\(["a", "b", "c"][i % 3])")))
        }
        // Slots of replaced reports are reclaimed as they pile up.
        XCTAssertLessThanOrEqual(batch.storageCount, 2 * 3 + 1)
        XCTAssertEqual(batch.take().count, 3)
    }
}

final class ProgramStatusNotifierTests: XCTestCase {
    private var time: TimeInterval = 100
    private var scheduled = [(at: TimeInterval, block: () -> Void)]()
    private var posted = [String]()
    private var notifier: ProgramStatusNotifier!

    override func setUp() {
        super.setUp()
        time = 100
        scheduled = []
        posted = []
        notifier = ProgramStatusNotifier(
            interval: 3,
            now: { [unowned self] in time },
            schedule: { [unowned self] delay, block in
                scheduled.append((time + delay, block))
            },
            post: { [unowned self] text in
                posted.append(text)
            })
    }

    /// Advances the clock and runs whatever came due.
    private func advance(to newTime: TimeInterval) {
        time = newTime
        let due = scheduled.filter { $0.at <= newTime }
        scheduled.removeAll { $0.at <= newTime }
        due.forEach { $0.block() }
    }

    private func notify(_ key: String, _ text: String) {
        notifier.notify(key: key, description: text)
    }

    func testFirstPostsImmediately() {
        notify("a", "a1")
        XCTAssertEqual(posted, ["a1"])
    }

    func testNewerStateOfTheSameRecordReplacesTheOlder() {
        notify("a", "a1")
        advance(to: 101)
        notify("b", "b1")
        notify("b", "b2")
        XCTAssertEqual(posted, ["a1"])
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.at, 103)
        advance(to: 103)
        XCTAssertEqual(posted, ["a1", "b2"])
    }

    func testDifferentRecordsInOneIntervalAreAllShown() {
        // A goes to waiting, then B to waiting, then C to done, inside one
        // interval. B still needs the user, so it must not be lost behind C.
        notify("a", "A is waiting")
        advance(to: 101)
        notify("b", "B is waiting")
        notify("c", "C is done")
        advance(to: 103)
        XCTAssertEqual(posted, ["A is waiting", "B is waiting\nC is done"])
    }

    func testHeldNotificationForAStateTheRecordLeftIsDropped() {
        // Root blocked posts; task a blocked is held; then a goes back to
        // working (the user answered elsewhere), which does not notify.
        notify("", "Status changed to waiting")
        advance(to: 101)
        notify("a", "a changed to waiting")
        advance(to: 101.5)
        notifier.retainPending(forKeys: [""])
        advance(to: 103)
        XCTAssertEqual(posted, ["Status changed to waiting"])
    }

    func testRetainKeepsWhatStillNotifies() {
        notify("a", "a1")
        advance(to: 101)
        notify("b", "b1")
        notify("c", "c1")
        notifier.retainPending(forKeys: ["c"])
        advance(to: 103)
        XCTAssertEqual(posted, ["a1", "c1"])
    }

    func testAfterQuietIntervalPostsImmediately() {
        notify("a", "a1")
        advance(to: 104)
        notify("a", "a2")
        XCTAssertEqual(posted, ["a1", "a2"])
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testHeldPostRestartsTheInterval() {
        notify("a", "a1")
        advance(to: 101)
        notify("b", "b1")
        advance(to: 103)
        XCTAssertEqual(posted, ["a1", "b1"])
        advance(to: 104)
        notify("c", "c1")
        // Only one second since "b1" went out.
        XCTAssertEqual(posted, ["a1", "b1"])
        advance(to: 106)
        XCTAssertEqual(posted, ["a1", "b1", "c1"])
    }

    // QA finding F-326: emptying the held notifications must not leave a
    // second timer for the same deadline once something is held again, or
    // both timers post within moments of each other.
    func testDroppingHeldThenHoldingAgainKeepsOneTimer() {
        notify("a", "a waiting 1")
        advance(to: 101)
        notify("a", "a waiting 2")
        notifier.retainPending(forKeys: [])
        advance(to: 101.5)
        notify("a", "a waiting 3")
        XCTAssertEqual(scheduled.count, 1)

        // Run the due timers one at a time with a notify between, as the
        // main queue interleaves them with batches of reports.
        time = 103
        while let index = scheduled.firstIndex(where: { $0.at <= time }) {
            let entry = scheduled.remove(at: index)
            entry.block()
            notify("a", "a waiting again")
        }
        XCTAssertEqual(posted, ["a waiting 1", "a waiting 3"])
    }

    // QA finding F-326: a flood that repeatedly holds and drops a record's
    // notification never posts twice within the interval.
    func testFloodOfHoldAndDropRespectsTheInterval() {
        var postTimes = [TimeInterval]()
        notifier = ProgramStatusNotifier(
            interval: 3,
            now: { [unowned self] in time },
            schedule: { [unowned self] delay, block in
                scheduled.append((time + delay, block))
            },
            post: { [unowned self] _ in
                postTimes.append(time)
            })
        var step = 0
        while time < 110 {
            time += 0.01
            // Timers come due between batches, one at a time.
            while let index = scheduled.firstIndex(where: { $0.at <= time }) {
                let entry = scheduled.remove(at: index)
                entry.block()
                notify("a", "a changed to waiting")
            }
            // Each batch leaves a waiting (notify) or working
            // (its held notification is dropped).
            if step % 2 == 0 {
                notify("a", "a changed to waiting")
            } else {
                notifier.retainPending(forKeys: [])
            }
            step += 1
        }
        // Notifications keep coming about every interval through the flood.
        XCTAssertGreaterThanOrEqual(postTimes.count, 3)
        XCTAssertGreaterThanOrEqual(postTimes.last ?? 0, 106)
        for (earlier, later) in zip(postTimes, postTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 3 - 1e-9)
        }
    }
}

final class ProgramStatusDisplayRecordTests: XCTestCase {
    private var changes = 0
    private var entered = [ProgramStatusDisplayRecord]()
    private var controller: ProgramStatusController!

    override func setUp() {
        super.setUp()
        changes = 0
        entered = []
        controller = ProgramStatusController(
            applyStatus: { _ in },
            currentProgress: { .stopped },
            setProgress: { _ in },
            recordsDidChange: { [unowned self] in changes += 1 },
            recordDidChangeState: { [unowned self] in entered.append($0) })
    }

    private func send(_ body: String) {
        controller.handle(ProgramStatusReport.parse(body)!)
    }

    private func send(_ bodies: [String]) {
        controller.handle(bodies.map { ProgramStatusReport.parse($0)! })
    }

    // QA finding F-307: many reports handled together change the records once
    // and announce each record that changed once, in its final state.
    func testBatchAnnouncesOncePerRecord() {
        send((0..<5000).flatMap { _ in ["state=working:id=a", "state=blocked:id=b"] })
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(entered.map(\.key), ["a", "b"])
        XCTAssertEqual(entered.map(\.statusText), ["working", "waiting"])
    }

    // New records interleaved with clears of another must not make handling
    // a batch quadratic. Correctness only; a quadratic version would take
    // minutes here.
    func testBatchOfNewRecordsAndClearsIsHandled() {
        send((0..<50000).flatMap { ["state=working:id=n\($0)", "state=clear:id=z"] })
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(controller.displayRecords.count, ProgramStatusRecords.defaultCapacity)
        XCTAssertEqual(entered.count, ProgramStatusRecords.defaultCapacity)
    }

    func testStatePassedThroughWithinBatchIsNotAnnounced() {
        send("state=working")
        entered = []
        send(["state=blocked", "state=working"])
        XCTAssertEqual(entered, [])
        XCTAssertEqual(controller.displayRecords.map(\.statusText), ["working"])
    }

    func testFinalStateOfBatchIsAnnounced() {
        send("state=working")
        entered = []
        send(["state=blocked", "state=working", "state=done"])
        XCTAssertEqual(entered.map(\.statusText), ["done"])
    }

    func testRecordRecreatedWithinBatchIsAnnounced() {
        send("state=blocked:id=a")
        entered = []
        send(["state=clear:id=a", "state=blocked:id=a"])
        XCTAssertEqual(entered.map(\.statusText), ["waiting"])
    }

    func testRecordRemovedWithinBatchIsNotAnnounced() {
        send(["state=blocked:id=a", "state=clear:id=a"])
        XCTAssertEqual(entered, [])
        XCTAssertEqual(changes, 0)
    }

    func testStateChangesAreReportedButMessageChangesAreNot() {
        send("state=working")
        send("state=working:msg=\(b64("more"))")
        send("state=blocked")
        XCTAssertEqual(entered.map(\.statusText), ["working", "waiting"])
        XCTAssertEqual(changes, 3)
    }

    func testClearIsNotAStateButIsAChange() {
        send("state=working")
        send("state=clear")
        XCTAssertEqual(entered.count, 1)
        XCTAssertEqual(changes, 2)
        XCTAssertTrue(controller.displayRecords.isEmpty)
    }

    func testKeypressChangesRecordsWithoutReportingAState() {
        send("state=done")
        entered = []
        changes = 0
        controller.userDidPressKey()
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(entered.isEmpty)
        XCTAssertEqual(controller.displayRecords.map(\.statusText), ["idle"])
    }

    func testNothingChangedReportsNothing() {
        send("state=working")
        changes = 0
        controller.userDidPressKey()
        controller.commandDidEnd(through: controller.serial)
        // The working record ended with the command, so that one is a change.
        XCTAssertEqual(changes, 1)
        changes = 0
        controller.commandDidEnd(through: controller.serial)
        XCTAssertEqual(changes, 0)
    }

    func testLabels() {
        send("state=working:app=deploy")
        send("state=working:id=build:title=\(b64("Build"))")
        send("state=blocked:id=build/test")
        send("state=done:id=lint")
        let byStatus = Dictionary(grouping: controller.displayRecords, by: { $0.label ?? "" })
        XCTAssertEqual(Set(byStatus.keys), ["deploy", "Build", "Build \u{203A} test", "lint"])
        let root = controller.displayRecords.first { $0.isRoot }
        XCTAssertEqual(root?.label, "deploy")
    }

    // The Session Status tool hides a session row's detail only while the
    // records' status is the one showing; another writer's message has no
    // child row to carry it.
    func testIsShowingStatusTracksWhoSetTheStatus() {
        XCTAssertFalse(controller.isShowingStatus)
        send("state=working:id=a")
        send("state=blocked:id=b")
        XCTAssertTrue(controller.isShowingStatus)
        controller.otherWriterDidSetStatus()
        XCTAssertFalse(controller.isShowingStatus)
        send("state=working:id=a")
        XCTAssertTrue(controller.isShowingStatus)
    }

    func testChildInheritsAppButIsLabeledByPath() {
        send("state=working:id=a:app=cargo")
        XCTAssertEqual(controller.displayRecords.first?.label, "a")
    }
}

final class ToolStatusChildRowTests: XCTestCase {
    private func child(_ label: String, _ status: String, at time: TimeInterval) -> ToolStatus.ChildRow {
        return ToolStatus.ChildRow(sessionID: "s",
                                   recordKey: label,
                                   label: label,
                                   statusText: status,
                                   indicatorColor: nil,
                                   statusTextColor: nil,
                                   progress: nil,
                                   detail: nil,
                                   updatedAt: time)
    }

    private let priorities = ["waiting": 0, "done": 1, "working": 2, "idle": 3]

    private func split(_ rows: [ToolStatus.ChildRow], limit: Int = ToolStatus.maximumChildRows) -> (shown: [String], hidden: [String]) {
        let result = ToolStatus.childRows(rows, limit: limit, priority: { self.priorities[$0] ?? 9 })
        return (result.shown.map(\.label), result.hidden.map(\.label))
    }

    func testOrderedByPriorityThenMostRecent() {
        let rows = [child("a", "working", at: 1),
                    child("b", "waiting", at: 1),
                    child("c", "working", at: 5),
                    child("d", "done", at: 2)]
        XCTAssertEqual(split(rows).shown, ["b", "d", "c", "a"])
    }

    func testSnoozedPeersChildrenSinkWhateverTheirPriority() {
        var waiting = child("snoozed", "waiting", at: 9)
        waiting.snoozed = true
        let rows = [waiting, child("a", "idle", at: 1), child("b", "working", at: 1)]
        XCTAssertEqual(split(rows).shown, ["b", "a", "snoozed"])
    }

    func testCapIsFour() {
        XCTAssertEqual(ToolStatus.maximumChildRows, 4)
        let rows = (0..<6).map { child("r\($0)", "working", at: TimeInterval($0)) }
        let result = split(rows)
        XCTAssertEqual(result.shown, ["r5", "r4", "r3", "r2"])
        XCTAssertEqual(result.hidden, ["r1", "r0"])
    }

    func testProgressShowsAfterStatus() {
        var row = child("a", "working", at: 0)
        row.progress = 40
        let text = ToolStatus.childStatusText(row)
        XCTAssertTrue(text.hasPrefix("working"), text)
        XCTAssertTrue(text.contains("40"), text)
    }
}

final class ToolStatusChildSelectionTests: XCTestCase {
    private typealias Key = ToolStatus.ChildKey
    private let euWest = ToolStatus.ChildKey(sessionID: "peer1", recordKey: "eu-west")
    private let usEast = ToolStatus.ChildKey(sessionID: "peer1", recordKey: "us-east")
    private let review = ToolStatus.ChildKey(sessionID: "peer2", recordKey: "")

    /// A merged workgroup row with children from two peers, after an
    /// unrelated session's row.
    private var mergedRows: [ToolStatus.SelectableRow] {
        return [.session(matchesActive: false),
                .session(matchesActive: true),
                .child(euWest),
                .child(review),
                .child(usEast)]
    }

    private func select(_ rows: [ToolStatus.SelectableRow], active: String?, clicked: Key? = nil) -> Int? {
        return ToolStatus.rowToSelect(rows, activeSessionID: active, clickedChild: clicked)
    }

    func testNavigatingToAPeerSelectsItsChild() {
        XCTAssertEqual(select(mergedRows, active: "peer2"), 3)
    }

    func testNavigatingSelectsTheActivePeersMostUrgentChild() {
        XCTAssertEqual(select(mergedRows, active: "peer1"), 2)
    }

    func testClickedChildStaysSelectedWhileItsSessionIsActive() {
        XCTAssertEqual(select(mergedRows, active: "peer1", clicked: usEast), 4)
    }

    func testClickedChildLetsGoWhenAnotherSessionBecomesActive() {
        XCTAssertEqual(select(mergedRows, active: "peer2", clicked: usEast), 3)
    }

    func testActiveMemberWithoutChildrenSelectsTheWorkgroupRow() {
        XCTAssertEqual(select(mergedRows, active: "peer3"), 1)
    }

    func testChildrenAllFromOneSessionSelectTheSessionRow() {
        // Not merged: the session row already is the active session.
        let rows: [ToolStatus.SelectableRow] = [.session(matchesActive: true),
                                                .child(Key(sessionID: "s", recordKey: "eu-west")),
                                                .child(Key(sessionID: "s", recordKey: "us-east")),
                                                .more]
        XCTAssertEqual(select(rows, active: "s"), 0)
    }

    func testChildrenOfTheNextSessionAreNotConsidered() {
        let rows: [ToolStatus.SelectableRow] = [.session(matchesActive: true),
                                                .session(matchesActive: false),
                                                .child(Key(sessionID: "x", recordKey: "a")),
                                                .child(Key(sessionID: "s", recordKey: "b"))]
        XCTAssertEqual(select(rows, active: "s"), 0)
    }

    func testSiblingsWithTheSameTitleStayDistinct() {
        // ci/linux and ci/mac, both titled Build, read the same; the record
        // key still tells them apart.
        let linux = Key(sessionID: "s", recordKey: "ci/linux")
        let mac = Key(sessionID: "s", recordKey: "ci/mac")
        let rows: [ToolStatus.SelectableRow] = [.session(matchesActive: true), .child(linux), .child(mac)]
        XCTAssertEqual(select(rows, active: "s", clicked: mac), 2)
    }

    func testNoActiveSessionSelectsNothing() {
        XCTAssertNil(select(mergedRows.map { _ in .more }, active: "peer1"))
    }
}
