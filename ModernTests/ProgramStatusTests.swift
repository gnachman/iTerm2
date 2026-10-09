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

    func testUnchangedProgressIsNotResent() {
        send("state=working:progress=10")
        send("state=working:progress=10:msg=\(b64("still"))")
        XCTAssertEqual(progressSets.count, 1)
    }
}

final class ProgramStatusTerminalTests: XCTestCase {
    private func feed(_ harness: TerminalTestHarness, _ string: String) {
        harness.screen.inject(string.data(using: .utf8)!)
        harness.screen.performBlock(joinedThreads: { _, _, _ in })
    }

    func testReportReachesDelegate() {
        let harness = TerminalTestHarness()
        feed(harness, "\u{1b}]7501;state=working:app=brew\u{1b}\\")
        feed(harness, "\u{1b}]7501;state=done\u{07}")
        XCTAssertEqual(harness.delegate.programStatusReports.map(\.state), [.working, .done])
        XCTAssertEqual(harness.delegate.programStatusReports.first?.app, "brew")
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
