//
//  PromptMarkExcludedSubrangeTests.swift
//  iTerm2
//
//  Tests for VT100ScreenMark.kind and VT100ScreenMark.excludedSubranges
//  (PR 2). Drives the existing TerminalTestHarness with kind-aware
//  sendPromptStart and asserts on the recorded mark state.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptMarkExcludedSubrangeTests: XCTestCase {

    // MARK: - Group 4 — excluded subrange recording

    /// Test 28: a single initial A/B builds the primary mark with no excluded
    /// subranges (the common single-line-command case).
    func test_initialOnly_noExcludedSubranges() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()       // A
        harness.appendText("$ ")
        harness.sendCommandStart()      // B
        harness.appendText("echo hi")
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1)
        XCTAssertNil(marks[0].excludedSubranges,
                     "A single-line command should record no excluded subranges")
    }

    /// Test 29: one PS2 cycle (`A(s) > B`) appends exactly one excluded
    /// subrange covering the PS2 prefix.
    func test_oneSecondaryCycle_appendsOneExcludedSubrange() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // Primary prompt line: "$ " then user types "echo \" and presses Enter.
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()

        // PS2 line: the shell draws "> " bracketed by A;k=s … B.
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()  // closes the non-initial region
        harness.appendText("hi")
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.excludedSubranges?.count, 1,
                       "Expected one excluded subrange for the PS2 prefix")
        let range = mark.excludedSubranges!.first!.absRange
        XCTAssertEqual(range.start.x, 0, "PS2 prefix starts at column 0 of its row")
        XCTAssertEqual(range.end.x, 2, "PS2 prefix '> ' ends at column 2")
        XCTAssertEqual(range.start.y, range.end.y,
                       "PS2 prefix stays on a single row")
    }

    /// Test 30: two PS2 cycles append two excluded subranges in order.
    func test_twoSecondaryCycles_appendTwoExcludedSubranges() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()

        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.appendText("hi \\")
        harness.newline()

        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.appendText("there")
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.excludedSubranges?.count, 2)
    }

    /// Test 31: after the full A B (PS2)* C D cycle, the mark records the
    /// expected number of excluded subranges, holds the return code, and is
    /// still a single prompt mark.
    func test_fullMultiLineCycle_consolidatesIntoOneMark() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()

        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.appendText("hi")
        harness.newline()

        harness.sendCommandEnd()        // C — output begins
        harness.appendText("hi")
        harness.newline()
        harness.sendReturnCode(0)       // D;0
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1, "Multi-line command must produce exactly one mark")
        let mark = marks[0]
        XCTAssertTrue(mark.hasCode)
        XCTAssertEqual(mark.code, 0)
        XCTAssertEqual(mark.excludedSubranges?.count, 1,
                       "One PS2 line → one excluded subrange")
    }

    /// Test 32: a right-prompt (`A(r) … B`) on the primary row appends an
    /// excluded subrange covering the right-prompt columns. The user-typed
    /// `commandRange` should still begin at the primary B and not be
    /// disturbed by the right-prompt.
    func test_rightPromptOnPrimaryRow_appendsExcludedSubrange() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // Primary prompt at column 0.
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()       // command-read starts at (2, 0)
        // User hasn't typed anything yet. Shell draws right-prompt over to
        // the right side of the same row (real shells emit padding first,
        // but the harness doesn't bother with that).
        harness.appendText(String(repeating: " ", count: 60))   // pad to col 62
        harness.sendPromptStart(kind: .right)                    // A;k=r at (62, 0)
        harness.appendText("[13:42:01]")                          // right-prompt text (10 chars)
        harness.sendCommandStart()                                // B closes at (72, 0)
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.excludedSubranges?.count, 1)
        let range = mark.excludedSubranges!.first!.absRange
        XCTAssertEqual(range.start.x, 62)
        XCTAssertEqual(range.end.x, 72)
        XCTAssertEqual(range.start.y, range.end.y,
                       "Right-prompt stays on the primary row")
    }

    /// If the primary prompt mark has scrolled off (long PS2 sequence that
    /// pushed the originating A out of history before its closing B), the
    /// excluded subrange is dropped rather than crashing on the cast from a
    /// negative `long long` to `int` that would otherwise produce a wild
    /// markCache lookup.
    func test_promptMarkScrolledOff_excludedSubrangeDroppedGracefully() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()

        // Simulate the primary prompt scrolling off: bump
        // cumulativeScrollbackOverflow past lastPromptLine so the relative
        // coord becomes negative. The non-initial B's recording logic must
        // tolerate this without crashing.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.cumulativeScrollbackOverflow = mutableState.lastPromptLine + 100
        })

        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()  // would crash without the guard
        harness.sync()

        // No crash; we don't really care what excludedSubranges contains
        // here (it's dropped because the prompt mark is unreachable), only
        // that we got this far. Assert sanity.
        XCTAssertNotNil(harness.lastPromptMark,
                        "Original mark should still exist even if its abs line is now below overflow")
    }

    /// `.unknown` (a k= value the parser doesn't recognize) must ride the
    /// initial path at the receiver: a mark is created, the prompt-state
    /// machine transitions through B as if it were initial, and no excluded
    /// subrange is appended (.unknown is not a "mid-command" continuation).
    /// Regression: an earlier draft routed .unknown to the non-initial path,
    /// which hid the prompt entirely (no mark, no navigation).
    func test_unknownKind_routesAsInitial() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart(kind: .unknown)
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo hi")
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1,
                       ".unknown must create a mark (treated like .initial)")
        XCTAssertNil(marks[0].excludedSubranges,
                     ".unknown must not append an excluded subrange")
    }

    /// Test 34: a non-initial A with no preceding initial A is tolerated,
    /// no crash, no mark created, the pending range is dropped on B.
    func test_nonInitialA_withoutPriorInitial_isTolerated() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        // Send A(s) and B with no preceding A(i).
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.sync()

        // Either zero marks, or one stray mark with no excluded subranges.
        // The contract: no crash, and no excluded-subrange-without-owner.
        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 0,
                       "Non-initial A without a prior initial A should not create a mark")
    }

    // MARK: - Group 8 — fullCommand capture

    /// A single-line command (no PS2) yields firstLineOfCommand == fullCommand
    /// — there's no multi-line content to differ on and no excluded subranges
    /// to strip.
    func test_fullCommand_singleLine_matchesFirstLine() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo hi")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("hi")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.firstLineOfCommand, "echo hi")
        XCTAssertEqual(mark.fullCommand, "echo hi")
    }

    /// A multi-line PS2 cycle captures the full typed command in fullCommand
    /// with the PS2 prefix subtracted, joined across rows with \n.
    /// firstLineOfCommand stays single-line (just the row before the PS2).
    func test_fullCommand_multiLinePS2_subtractsPrefix() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()

        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.appendText("hi")
        harness.newline()

        harness.sendCommandEnd()
        harness.appendText("hi")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertEqual(mark.firstLineOfCommand, "echo \\",
                       "firstLineOfCommand stays first-row only (pre-PS2 truncation)")
        XCTAssertNotNil(mark.fullCommand)
        // fullCommand should contain both rows joined by a newline, with the
        // "> " PS2 prefix stripped. Concrete bytes depend on iTermTextExtractor's
        // padding behavior; assert structurally rather than literally.
        let full = mark.fullCommand!
        XCTAssertTrue(full.contains("echo \\"),
                      "fullCommand should include the first-row typed text")
        XCTAssertTrue(full.contains("hi"),
                      "fullCommand should include the post-PS2 typed text")
        XCTAssertFalse(full.contains("> "),
                       "fullCommand must subtract the PS2 prefix cells")
    }

    /// A right-prompt on the primary row (`A(r) ... B` mid-cycle) excludes its
    /// cells from fullCommand.
    func test_fullCommand_rightPromptOnPrimaryRow_subtracted() {
        let harness = TerminalTestHarness(width: 80, height: 24)

        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo hi   ")  // pad so right-prompt has room
        harness.sendPromptStart(kind: .right)
        harness.appendText("[date]")
        harness.sendCommandStart()
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("hi")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()

        let mark = onlyPromptMark(in: harness)
        XCTAssertNotNil(mark.fullCommand)
        XCTAssertTrue(mark.fullCommand!.contains("echo hi"))
        XCTAssertFalse(mark.fullCommand!.contains("[date]"),
                       "fullCommand must subtract the right-prompt cells")
        // firstLineOfCommand used to be extracted via -commandInRange: which
        // didn't know about excludedSubranges, so a right-prompt on the
        // primary row would leak into the single-line preview. The preview
        // is now derived from the cleaned fullCommand instead.
        XCTAssertNotNil(mark.firstLineOfCommand)
        XCTAssertFalse(mark.firstLineOfCommand!.contains("[date]"),
                       "firstLineOfCommand must also subtract the right-prompt cells")
    }

    // MARK: - Group 7 — serialization

    /// Test 51: an old-format dict (no kind, no excludedSubranges) loads
    /// with kind=.initial (when isPrompt=YES — pre-feature prompt marks
    /// were primary by construction) and nil excludedSubranges.
    func test_legacyDict_loadsAsInitialWithNoSubranges() {
        let dict: [AnyHashable: Any] = [
            "Is Prompt": true,
            "Command Range": rangeDict(VT100GridAbsCoordRangeMake(0, 0, 5, 0)),
            "Prompt Range": rangeDict(VT100GridAbsCoordRangeMake(0, 0, 2, 0)),
            "Output Start": coordDict(VT100GridAbsCoordMake(0, 1)),
        ]
        let mark = VT100ScreenMark(dictionary: dict)!
        XCTAssertEqual(mark.kind, .initial)
        XCTAssertNil(mark.excludedSubranges)
    }

    /// A bookmark-style mark (isPrompt=NO) with no kind in the dict loads
    /// with kind=.unknown — the field is not applicable to non-prompt marks.
    func test_legacyNonPromptDict_loadsAsUnknown() {
        let dict: [AnyHashable: Any] = [
            "Is Prompt": false,
        ]
        let mark = VT100ScreenMark(dictionary: dict)!
        XCTAssertEqual(mark.kind, .unknown)
    }

    /// Test 52: a default-state mark always writes a Prompt Kind key. The
    /// value is `.unknown` for marks not built via setPromptStartLine:
    /// (e.g. user bookmark marks). No subranges → no Excluded Subranges key.
    func test_defaultMark_serializationOmitsSubrangesKey() {
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        let dict = mark.dictionaryValue() as NSDictionary
        XCTAssertEqual(dict["Prompt Kind"] as? Int, Int(VT100PromptKind.unknown.rawValue),
                       "Default-init mark records kind=.unknown")
        XCTAssertNil(dict["Excluded Subranges"],
                     "Mark with no subranges must not write Excluded Subranges into its dict")
    }

    /// Test 53: round-trip a mark with two excluded subranges. Decoded RCs
    /// come back unbound (status `.unresolved`) — calling
    /// `bindUnresolvedResilientCoordinatesToDataSource:` lifts them to
    /// `.coord` bound against the supplied dataSource.
    func test_excludedSubranges_roundTripBitForBit() {
        let dataSource = FakeResilientDataSource(guid: "round-trip", width: 80, lines: 100)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        let r1 = ResilientCoordinateRange(dataSource: dataSource,
                                                absRange: VT100GridAbsCoordRangeMake(0, 1, 2, 1))
        let r2 = ResilientCoordinateRange(dataSource: dataSource,
                                                absRange: VT100GridAbsCoordRangeMake(0, 2, 2, 2))
        mark.appendExcludedSubrange(r1)
        mark.appendExcludedSubrange(r2)

        let dict = mark.dictionaryValue()
        let restored = VT100ScreenMark(dictionary: dict)!

        XCTAssertEqual(restored.excludedSubranges?.count, 2)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .unresolved,
                       "Decoded RCs are unbound until bind is called")
        restored.bindUnresolvedResilientCoordinates(to: dataSource)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .valid)
        let firstRange = restored.excludedSubranges![0].absRange
        let secondRange = restored.excludedSubranges![1].absRange
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(firstRange,
                                                   VT100GridAbsCoordRangeMake(0, 1, 2, 1)))
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(secondRange,
                                                   VT100GridAbsCoordRangeMake(0, 2, 2, 2)))
    }

    /// Two-pool invariant: a mark's doppelganger holds excludedSubranges
    /// as unbound RCs that get bound to the main pool via the holder
    /// protocol. We verify pool segregation by posting a resize
    /// notification against each pool's guid: only the main-pool post
    /// should affect the doppelganger's RCs.
    func test_doppelganger_excludedSubranges_useMainThreadPool() {
        let mutationDS = FakeResilientDataSource(guid: "mutation-pool", width: 80, lines: 200)
        let mainDS = FakeResilientDataSource(guid: "main-pool", width: 80, lines: 200)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: mutationDS,
            absRange: VT100GridAbsCoordRangeMake(0, 5, 2, 5)))
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: mutationDS,
            absRange: VT100GridAbsCoordRangeMake(0, 6, 2, 6)))

        // -copy invokes -copyWithZone: which produces a doppelganger whose
        // RCs are unbound (`.unresolvedCoord`). In production the tree's
        // add side effect calls bindUnresolvedResilientCoordinates(to:) on
        // the doppelganger with the main-pool dataSource; we simulate that
        // step here directly.
        let doppelganger = mark.copy() as! VT100ScreenMark
        XCTAssertEqual(doppelganger.excludedSubranges?.count, 2)
        XCTAssertEqual(doppelganger.excludedSubranges![0].start.status, .unresolved,
                       "Doppelganger RCs are unbound until the tree's add hook binds them")
        doppelganger.bindUnresolvedResilientCoordinates(to: mainDS)
        XCTAssertEqual(doppelganger.excludedSubranges![0].start.status, .valid)

        // A converter that pretends the coord cannot be reflowed — used to
        // assert that an unwanted resize would invalidate the RC if it were
        // dispatched to it.
        let invalidatingConverter: @convention(block) (VT100GridAbsCoord) -> VT100GridAbsCoord = { _ in
            VT100GridAbsCoordInvalid
        }

        // Post against the mutation pool — the doppelganger's RCs are not
        // registered with that guid, so this should be a no-op.
        RCResizeNotification.post(guid: "mutation-pool", converter: invalidatingConverter)
        XCTAssertEqual(doppelganger.excludedSubranges![0].start.status, .valid,
                       "Mutation-pool resize must not affect main-pool RCs on the doppelganger")

        // Post against the main pool — the doppelganger's RCs are bound to
        // mainDS, so this should invalidate them.
        RCResizeNotification.post(guid: "main-pool", converter: invalidatingConverter)
        XCTAssertEqual(doppelganger.excludedSubranges![0].start.status, .invalid)
        XCTAssertEqual(doppelganger.excludedSubranges![0].end.status, .invalid)
    }

    /// -copyWithZone: structurally clones excludedSubranges as unbound
    /// twins (no dataSource shared with the progenitor). Without a
    /// subsequent bind, the doppelganger's RCs report `.unresolved`.
    func test_doppelganger_unboundUntilBound() {
        let mutationDS = FakeResilientDataSource(guid: "mut-only", width: 80, lines: 200)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: mutationDS,
            absRange: VT100GridAbsCoordRangeMake(0, 5, 2, 5)))

        let doppelganger = mark.copy() as! VT100ScreenMark
        XCTAssertEqual(doppelganger.excludedSubranges?.count, 1,
                       "Doppelganger preserves the subrange structurally")
        XCTAssertEqual(doppelganger.excludedSubranges![0].start.status, .unresolved,
                       "Without a bind step, doppelganger RCs stay unbound")
    }

    /// Restoring a mark from a dict produces unbound RCs (status
    /// `.unresolved`). The mark itself is still constructed correctly;
    /// it's the caller's job to bind via the holder protocol.
    func test_excludedSubranges_decodeProducesUnboundRCs() {
        let dataSource = FakeResilientDataSource(guid: "no-ds", width: 80, lines: 100)
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: dataSource,
            absRange: VT100GridAbsCoordRangeMake(0, 1, 2, 1)))
        let dict = mark.dictionaryValue()
        let restored = VT100ScreenMark(dictionary: dict)!
        XCTAssertEqual(restored.excludedSubranges?.count, 1)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .unresolved,
                       "Decoded subranges are unbound until the holder is bound")
    }

    /// The production restore path is the graph-encoded one
    /// (`restoreFromGraphRecord:...`). Pin that a mark with excludedSubranges
    /// makes it through restore (unbound) and that binding via the holder
    /// protocol lifts the RCs to `.valid`.
    func test_excludedSubranges_surviveGraphEncodedRestore() {
        let savingDataSource = FakeResilientDataSource(guid: "save-graph", width: 80, lines: 200)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: savingDataSource,
            absRange: VT100GridAbsCoordRangeMake(0, 5, 2, 5)))
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: savingDataSource,
            absRange: VT100GridAbsCoordRangeMake(0, 6, 2, 6)))

        // Hand-build the graph-encoded shape the IntervalTree encoder
        // emits: { "objects": [ { "Interval": {"Location":..., "Length":...},
        //                         "Class": ..., "content": <mark dict> }, ... ] }
        let contentDict = mark.dictionaryValue() as NSDictionary
        let intervalDict: [String: Any] = ["Location": 0, "Length": 1]
        let entry: [String: Any] = [
            "Interval": intervalDict,
            "Class": "VT100ScreenMark",
            "content": contentDict,
        ]
        let graphDict: [String: Any] = ["objects": [entry]]

        // Restore into a fresh tree. Decoded marks come back with unbound
        // subranges; this test pins that they survive the round-trip and
        // are lifted to `.valid` by an explicit bind step (which in
        // production lives in fixUpDeserializedIntervalTree: for the
        // progenitor and EventuallyConsistentIntervalTree's add hook for
        // the doppelganger).
        let restoringDataSource = FakeResilientDataSource(guid: "restore-graph", width: 80, lines: 200)
        let tree = IntervalTree()
        let ok = tree.restore(fromGraphRecord: graphDict,
                              offset: 0,
                              largeContentProvider: nil)
        XCTAssertTrue(ok, "Graph restore must succeed")

        let restoredMarks = tree.mutableObjects.compactMap { $0 as? VT100ScreenMark }
        XCTAssertEqual(restoredMarks.count, 1)
        let restored = restoredMarks[0]
        XCTAssertEqual(restored.excludedSubranges?.count, 2)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .unresolved)
        restored.bindUnresolvedResilientCoordinates(to: restoringDataSource)
        let first = restored.excludedSubranges![0].absRange
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(first,
                                                   VT100GridAbsCoordRangeMake(0, 5, 2, 5)))
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .valid)
    }

    /// Round-trip a mark through serialization, then bind to a *new*
    /// dataSource whose `rcScrollbackOverflow` is higher than the saved
    /// abs-Y values. The subranges survive structurally (still in the
    /// array) but report `.scrolledOff` after bind, so consumers know
    /// not to use them.
    func test_excludedSubranges_truncationThroughRestoreIsGraceful() {
        let savingDataSource = FakeResilientDataSource(guid: "save", width: 80, lines: 1000)
        let mark = VT100ScreenMark()
        mark.isPrompt = true
        // Saved abs Y = 100, which the restoring dataSource will treat as scrolled off.
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            dataSource: savingDataSource,
            absRange: VT100GridAbsCoordRangeMake(0, 100, 2, 100)))
        let dict = mark.dictionaryValue()

        // New dataSource pretends history starts at abs Y = 500 — anything
        // below that has been truncated from the line buffer.
        let restoringDataSource = FakeResilientDataSource(guid: "restore", width: 80, lines: 200)
        restoringDataSource.rcScrollbackOverflow = 500

        let restored = VT100ScreenMark(dictionary: dict)!
        restored.bindUnresolvedResilientCoordinates(to: restoringDataSource)
        XCTAssertEqual(restored.excludedSubranges?.count, 1,
                       "Restored mark keeps its excludedSubrange array; status reports scrolledOff after bind")
        let rcRange = restored.excludedSubranges![0]
        XCTAssertEqual(rcRange.start.status, .scrolledOff,
                       "Restored coord below new overflow must report scrolledOff")
        XCTAssertEqual(rcRange.end.status, .scrolledOff)
        // absRange projects scrolled-off endpoints to VT100GridAbsCoordInvalid.
        XCTAssertEqual(rcRange.absRange.start.x, VT100GridAbsCoordInvalid.x)
        XCTAssertEqual(rcRange.absRange.end.x, VT100GridAbsCoordInvalid.x)
    }

    private func coordDict(_ coord: VT100GridAbsCoord) -> [String: Any] {
        return ["x": Int(coord.x), "y": Int(coord.y)]
    }

    private func rangeDict(_ range: VT100GridAbsCoordRange) -> [String: Any] {
        return ["start": coordDict(range.start), "end": coordDict(range.end)]
    }

    // MARK: - Group 8 — Codable wire format

    /// A `.coord` RC encodes its absolute coordinate. Decode returns an
    /// unbound RC (`.unresolvedCoord` under the hood); `bind(to:)` lifts
    /// it to `.coord` with the supplied dataSource.
    func test_codable_coordRC_roundTripsExact() {
        let saveDS = FakeResilientDataSource(guid: "save-coord", width: 80, lines: 100)
        let rc = ResilientCoordinate(dataSource: saveDS,
                                     absCoord: VT100GridAbsCoord(x: 7, y: 42))
        let dict = rc.dictionaryValue
        XCTAssertEqual(dict["kind"] as? String, "coord")

        let restored = ResilientCoordinate.from(dictionary: dict)!
        XCTAssertEqual(restored.status, .unresolved,
                       "Decoded RC starts unbound")
        let loadDS = FakeResilientDataSource(guid: "load-coord", width: 80, lines: 100)
        restored.bind(to: loadDS)
        XCTAssertEqual(restored.status, .valid)
        XCTAssertEqual(restored.coord.x, 7)
        XCTAssertEqual(restored.coord.y, 42)
    }

    /// A `.fold` RC encodes the fold mark's guid (not a flattened invalid
    /// coord) and a decoded fresh-context RC reports `.unresolved` until
    /// the resolution pass binds it.
    func test_codable_foldRC_encodesGuid_decodesAsUnresolved() {
        let saveDS = FakeResilientDataSource(guid: "save-fold", width: 80, lines: 100)
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let rc = ResilientCoordinate(dataSource: saveDS,
                                     enclosingFold: dopFoldMark,
                                     coord: VT100GridCoord(x: 3, y: 8))
        let dict = rc.dictionaryValue
        XCTAssertEqual(dict["kind"] as? String, "fold")
        XCTAssertEqual(dict["markGuid"] as? String, foldMark.guid,
                       "Encoded fold dict must carry the fold mark's guid for rejoin")

        let restored = ResilientCoordinate.from(dictionary: dict)!
        XCTAssertEqual(restored.status, .unresolved,
                       "Decoded fold RC starts .unresolved — needs resolveUnresolved to bind")
    }

    /// An unresolved-fold RC resolves to `.inFold` when the lookup finds
    /// a matching FoldMark by guid, after being bound to a dataSource.
    /// Mirrors the order `fixUpDeserializedIntervalTree:` uses: bind first,
    /// then resolveUnresolved.
    func test_codable_unresolvedFold_resolvesViaLookup() {
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let dict = ResilientCoordinate(dataSource: saveDS,
                                       enclosingFold: dopFoldMark,
                                       coord: VT100GridCoord(x: 3, y: 8)).dictionaryValue
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        let restored = ResilientCoordinate.from(dictionary: dict)!
        restored.bind(to: loadDS)

        let resolved = restored.resolveUnresolved(
            foldMarkLookup: { guid in (guid == foldMark.guid) ? dopFoldMark : nil },
            portholeMarkLookup: { _ in nil })
        XCTAssertTrue(resolved)
        XCTAssertEqual(restored.status, .inFold)
        XCTAssertEqual(restored.foldInfo?.mark.guid, foldMark.guid)
    }

    /// An unresolved-fold RC stays `.unresolved` if the lookup can't find
    /// the mark. Mirrors the "FoldMark didn't end up in the restored tree"
    /// case (e.g., it scrolled off and was dropped) — graceful degradation
    /// rather than misbinding.
    func test_codable_unresolvedFold_remainsWhenLookupMisses() {
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let dict = ResilientCoordinate(dataSource: saveDS,
                                       enclosingFold: dopFoldMark,
                                       coord: VT100GridCoord(x: 0, y: 0)).dictionaryValue
        let restored = ResilientCoordinate.from(dictionary: dict)!

        let resolved = restored.resolveUnresolved(
            foldMarkLookup: { _ in nil },
            portholeMarkLookup: { _ in nil })
        XCTAssertFalse(resolved)
        XCTAssertEqual(restored.status, .unresolved)
    }

    /// A `.porthole` RC dict (constructed directly — there's no public
    /// initializer for `.porthole` RCs since they're only entered via the
    /// linesDidShift handler) decodes as `.unresolved` and resolves to
    /// `.inPorthole` when the lookup finds the PortholeMark.
    func test_codable_unresolvedPorthole_resolvesViaLookup() {
        let portholeMark = PortholeMark("test-porthole-uid", width: 80)
        let dopPortholeMark = portholeMark.doppelganger() as! PortholeMark
        let dict: NSDictionary = [
            "kind": "porthole",
            "markGuid": portholeMark.guid,
            "innerX": 3,
            "innerY": 1,
        ]
        let restored = ResilientCoordinate.from(dictionary: dict)!
        XCTAssertEqual(restored.status, .unresolved)
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        restored.bind(to: loadDS)

        let resolved = restored.resolveUnresolved(
            foldMarkLookup: { _ in nil },
            portholeMarkLookup: { guid in (guid == portholeMark.guid) ? dopPortholeMark : nil })
        XCTAssertTrue(resolved)
        XCTAssertEqual(restored.status, .inPorthole)
    }

    /// A `.fold` RC whose WeakBox value has died at encode time emits
    /// `kind: "invalid"` rather than a stale guid that will never resolve.
    /// The decoded RC then reports `.invalid` status.
    func test_codable_foldRC_deadWeakBox_encodesAsInvalid() {
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let rc: ResilientCoordinate
        do {
            let foldMark = makeFoldMark()
            let dopFoldMark = foldMark.doppelganger() as! FoldMark
            rc = ResilientCoordinate(dataSource: saveDS,
                                     enclosingFold: dopFoldMark,
                                     coord: VT100GridCoord(x: 0, y: 0))
        }
        // foldMark and dopFoldMark go out of scope; rc's WeakBox value is nil.
        autoreleasepool { }

        let dict = rc.dictionaryValue
        XCTAssertEqual(dict["kind"] as? String, "invalid")
        let restored = ResilientCoordinate.from(dictionary: dict)!
        XCTAssertEqual(restored.status, .invalid)
    }

    /// `RCRange` round-trips through `dictionaryValue` / `rangeFromDictionary:`
    /// preserving its endpoints' kinds independently — e.g. a range whose
    /// start is `.coord` and end is `.unresolvedFold` keeps that asymmetry
    /// once the RCs are bound (the `.coord` side lifts to `.valid`, the
    /// fold side stays `.unresolved` pending mark lookup).
    func test_codable_RCRange_mixedEndpoints_roundTrip() {
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let rcRange = ResilientCoordinateRange(
            start: ResilientCoordinate(dataSource: saveDS,
                                       absCoord: VT100GridAbsCoord(x: 2, y: 5)),
            end: ResilientCoordinate(dataSource: saveDS,
                                     enclosingFold: dopFoldMark,
                                     coord: VT100GridCoord(x: 0, y: 0)))
        let dict = rcRange.dictionaryValue
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        let restored = ResilientCoordinateRange.from(dictionary: dict)!
        restored.bind(to: loadDS)

        XCTAssertEqual(restored.start.status, .valid)
        XCTAssertEqual(restored.start.coord.x, 2)
        XCTAssertEqual(restored.start.coord.y, 5)
        XCTAssertEqual(restored.end.status, .unresolved,
                       "Fold endpoint remains unresolved until a mark lookup pass binds it")
    }

    // MARK: - Group 9 — unboundCopy preserves Location structure

    /// A `.coord` becomes an `.unresolvedCoord` on unboundCopy. `bind(to:)`
    /// lifts it back to `.coord`.
    func test_unboundCopy_preservesCoordCase() {
        let originalDS = FakeResilientDataSource(guid: "orig", width: 80, lines: 100)
        let newDS = FakeResilientDataSource(guid: "new", width: 80, lines: 100)
        let copy = ResilientCoordinate(dataSource: originalDS,
                                       absCoord: VT100GridAbsCoord(x: 5, y: 10))
                        .unboundCopy()
        XCTAssertEqual(copy.status, .unresolved,
                       "unboundCopy produces an unbound twin until bind is called")
        copy.bind(to: newDS)
        XCTAssertEqual(copy.status, .valid)
        XCTAssertEqual(copy.coord.x, 5)
        XCTAssertEqual(copy.coord.y, 10)
    }

    /// `.fold` is preserved structurally by `unboundCopy` — the WeakBox is
    /// shared with the source (both pools point at the same doppelganger
    /// FoldMark anyway). After bind, the copy reports `.inFold` with the
    /// same fold mark guid.
    func test_unboundCopy_preservesFoldCase() {
        let originalDS = FakeResilientDataSource(guid: "orig", width: 80, lines: 100)
        let newDS = FakeResilientDataSource(guid: "new", width: 80, lines: 100)
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let copy = ResilientCoordinate(dataSource: originalDS,
                                       enclosingFold: dopFoldMark,
                                       coord: VT100GridCoord(x: 5, y: 10))
                        .unboundCopy()
        copy.bind(to: newDS)
        XCTAssertEqual(copy.status, .inFold,
                       "unboundCopy must preserve .fold (not flatten to invalid)")
        XCTAssertEqual(copy.foldInfo?.mark.guid, foldMark.guid)
    }

    // MARK: - Group 10 — End-to-end via TerminalTestHarness

    /// Drive a real OSC 133 PS2 cycle, snapshot the mark dictionary, and
    /// restore it into a fresh `VT100ScreenMark`. The restored subrange's
    /// abs coords match the original — the new wire format round-trips a
    /// `.coord` subrange exactly once the holder is bound to a dataSource.
    func test_endToEnd_PS2Cycle_serializesAndRestoresPreservingSubrange() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.appendText("hi")
        harness.sync()

        let mark = onlyPromptMark(in: harness) as! VT100ScreenMark
        XCTAssertEqual(mark.excludedSubranges?.count, 1)
        let originalRange = mark.excludedSubranges![0].absRange

        let dict = mark.dictionaryValue()
        let restoringDS = FakeResilientDataSource(guid: "restore", width: 80, lines: 100)
        let restored = VT100ScreenMark(dictionary: dict)!
        restored.bindUnresolvedResilientCoordinates(to: restoringDS)

        XCTAssertEqual(restored.excludedSubranges?.count, 1)
        XCTAssertTrue(VT100GridAbsCoordRangeEquals(restored.excludedSubranges![0].absRange,
                                                   originalRange))
        XCTAssertEqual(restored.kind, .initial)
    }

    /// Two-pool segregation: after a real PS2 cycle the progenitor and
    /// doppelganger of the prompt mark each carry their own `RCRange`
    /// instances (no shared pointer). This locks in the contract that
    /// `-copyWithZone:` rebuilds the doppelganger's subranges against the
    /// main-thread pool rather than aliasing the mutation-pool RCs.
    func test_doppelganger_holdsDifferentRCRangeInstances() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("echo \\")
        harness.newline()
        harness.sendPromptStart(kind: .secondary)
        harness.appendText("> ")
        harness.sendCommandStart()
        harness.sync()

        let mark = onlyPromptMark(in: harness) as! VT100ScreenMark
        let dop = mark.doppelganger() as! VT100ScreenMark

        XCTAssertEqual(mark.excludedSubranges?.count, 1)
        XCTAssertEqual(dop.excludedSubranges?.count, 1)
        XCTAssertFalse(mark.excludedSubranges![0] === dop.excludedSubranges![0],
                       "Progenitor and doppelganger must not share RCRange instances")
        XCTAssertFalse(mark.excludedSubranges![0].start === dop.excludedSubranges![0].start,
                       "Underlying RC instances must also not be shared")
    }

    // MARK: - Group 11 — Mark-level round-trip with fold binding

    /// Round-trip a mark whose excluded subrange has fold-bound endpoints.
    /// After decode the subrange reports `.unresolved`; after a bind +
    /// resolveUnresolved pass with a lookup that knows the FoldMark, it
    /// upgrades to `.inFold`. End-to-end check of the pipeline that
    /// `fixUpDeserializedIntervalTree:` orchestrates in production.
    func test_markDict_foldBoundSubrange_decodesUnresolvedThenResolves() {
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            start: ResilientCoordinate(dataSource: saveDS,
                                        enclosingFold: dopFoldMark,
                                        coord: VT100GridCoord(x: 0, y: 0)),
            end: ResilientCoordinate(dataSource: saveDS,
                                      enclosingFold: dopFoldMark,
                                      coord: VT100GridCoord(x: 5, y: 0))))
        let dict = mark.dictionaryValue()
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        let restored = VT100ScreenMark(dictionary: dict)!
        restored.bindUnresolvedResilientCoordinates(to: loadDS)

        XCTAssertEqual(restored.excludedSubranges?.count, 1)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .unresolved,
                       "Fold endpoints stay unresolved after bind until the mark lookup runs")

        let resolved = restored.excludedSubranges![0].resolveUnresolved(
            foldMarkLookup: { guid in (guid == foldMark.guid) ? dopFoldMark : nil },
            portholeMarkLookup: { _ in nil })
        XCTAssertTrue(resolved)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .inFold)
        XCTAssertEqual(restored.excludedSubranges![0].end.status, .inFold)
    }

    /// Mirror of the fold round-trip but with porthole-bound endpoints. The
    /// RC primitive has no public porthole init (portholes only enclose a
    /// coord via the linesDidShift handler), so the test stages a
    /// porthole-bound subrange by hand-rolling each endpoint's dict shape
    /// and assembling the range from the decoded RCs. After bind +
    /// resolveUnresolved with a porthole lookup, both endpoints report
    /// `.inPorthole`.
    func test_markDict_portholeBoundSubrange_decodesUnresolvedThenResolves() {
        let portholeMark = PortholeMark("test-porthole-uid", width: 80)
        let dopPortholeMark = portholeMark.doppelganger() as! PortholeMark
        let startDict: NSDictionary = [
            "kind": "porthole",
            "markGuid": portholeMark.guid,
            "innerX": 0, "innerY": 0,
        ]
        let endDict: NSDictionary = [
            "kind": "porthole",
            "markGuid": portholeMark.guid,
            "innerX": 5, "innerY": 0,
        ]
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let startRC = ResilientCoordinate.from(dictionary: startDict)!
        let endRC = ResilientCoordinate.from(dictionary: endDict)!
        startRC.bind(to: saveDS)
        endRC.bind(to: saveDS)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(start: startRC, end: endRC))

        let dict = mark.dictionaryValue()
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        let restored = VT100ScreenMark(dictionary: dict)!
        restored.bindUnresolvedResilientCoordinates(to: loadDS)

        XCTAssertEqual(restored.excludedSubranges?.count, 1)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .unresolved,
                       "Porthole endpoints stay unresolved after bind until the mark lookup runs")
        XCTAssertEqual(restored.excludedSubranges![0].end.status, .unresolved)

        let resolved = restored.excludedSubranges![0].resolveUnresolved(
            foldMarkLookup: { _ in nil },
            portholeMarkLookup: { guid in (guid == portholeMark.guid) ? dopPortholeMark : nil })
        XCTAssertTrue(resolved)
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .inPorthole)
        XCTAssertEqual(restored.excludedSubranges![0].end.status, .inPorthole)
    }

    /// Asymmetric round-trip: one endpoint is fold-bound, the other is a
    /// plain `.coord`. After bind + resolve, the fold side reaches
    /// `.inFold`, the coord side stays `.valid`.
    func test_markDict_mixedFoldAndCoordEndpoints_resolveIndependently() {
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)

        let mark = VT100ScreenMark()
        mark.isPrompt = true
        mark.appendExcludedSubrange(ResilientCoordinateRange(
            start: ResilientCoordinate(dataSource: saveDS,
                                       enclosingFold: dopFoldMark,
                                       coord: VT100GridCoord(x: 0, y: 0)),
            end: ResilientCoordinate(dataSource: saveDS,
                                     absCoord: VT100GridAbsCoord(x: 5, y: 0))))

        let dict = mark.dictionaryValue()
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        let restored = VT100ScreenMark(dictionary: dict)!
        restored.bindUnresolvedResilientCoordinates(to: loadDS)

        let range = restored.excludedSubranges![0]
        XCTAssertEqual(range.start.status, .unresolved,
                       "Fold endpoint awaits the fold-mark lookup")
        XCTAssertEqual(range.end.status, .valid,
                       "Plain-coord endpoint is bound and immediately valid")

        let resolved = range.resolveUnresolved(
            foldMarkLookup: { guid in (guid == foldMark.guid) ? dopFoldMark : nil },
            portholeMarkLookup: { _ in nil })
        XCTAssertTrue(resolved)
        XCTAssertEqual(range.start.status, .inFold)
        XCTAssertEqual(range.end.status, .valid,
                       "Plain-coord endpoint should still be valid after resolveUnresolved")
    }

    // MARK: - Group 12 — Progenitor / doppelganger fold-mark split

    /// After the progenitor/doppelganger split, RC's fold init accepts a
    /// PROGENITOR fold mark (previously it asserted isDoppelganger). The
    /// pool the RC belongs to determines which "side" the fold mark
    /// should be on; the RC primitive itself shouldn't constrain it.
    func test_init_acceptsProgenitorFoldMark() {
        let foldMark = makeFoldMark()
        XCTAssertFalse(foldMark.isDoppelganger,
                       "Test invariant: makeFoldMark() returns a progenitor")
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let rc = ResilientCoordinate(dataSource: saveDS,
                                     enclosingFold: foldMark,
                                     coord: VT100GridCoord(x: 0, y: 0))
        XCTAssertEqual(rc.status, .inFold)
        XCTAssertTrue(rc.foldInfo?.mark === foldMark,
                      "RC must hold the progenitor fold mark passed at init")
    }

    /// resolveUnresolved must accept a progenitor fold mark — the
    /// fixUpDeserializedIntervalTree: progenitor pass resolves
    /// .unresolvedFold endpoints to progenitor refs (so subsequent
    /// mutation-thread reads through the RC's WeakBox land on the
    /// progenitor, whose `entry` is safe to read on the mutation thread).
    func test_resolveUnresolved_acceptsProgenitorFoldMark() {
        let foldMark = makeFoldMark()
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)
        let dict = ResilientCoordinate(dataSource: saveDS,
                                       enclosingFold: foldMark,
                                       coord: VT100GridCoord(x: 3, y: 8)).dictionaryValue
        let restored = ResilientCoordinate.from(dictionary: dict)!
        let loadDS = FakeResilientDataSource(guid: "load", width: 80, lines: 100)
        restored.bind(to: loadDS)

        let resolved = restored.resolveUnresolved(
            foldMarkLookup: { guid in (guid == foldMark.guid) ? foldMark : nil },
            portholeMarkLookup: { _ in nil })
        XCTAssertTrue(resolved)
        XCTAssertEqual(restored.status, .inFold)
        XCTAssertTrue(restored.foldInfo?.mark === foldMark,
                      "Resolved RC must hold the progenitor fold mark the lookup returned")
    }

    /// When -copyWithZone produces the doppelganger holder, embedded
    /// .fold(progenitor) RCs must flip to .fold(doppelganger). Without
    /// this flip, the doppelganger holder would carry a progenitor fold
    /// ref — i.e. a pointer into the mutation tree being read from the
    /// main thread (which can race against `entry` writes on the
    /// mutation thread).
    func test_unboundCopy_foldMark_flipsProgenitorToDoppelganger() {
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let originalDS = FakeResilientDataSource(guid: "orig", width: 80, lines: 100)
        let newDS = FakeResilientDataSource(guid: "new", width: 80, lines: 100)

        // Source RC holds the progenitor fold mark (mutation-pool style).
        let source = ResilientCoordinate(dataSource: originalDS,
                                         enclosingFold: foldMark,
                                         coord: VT100GridCoord(x: 5, y: 10))
        XCTAssertTrue(source.foldInfo?.mark === foldMark)

        // unboundCopy must flip to the doppelganger fold mark.
        let copy = source.unboundCopy()
        copy.bind(to: newDS)
        XCTAssertEqual(copy.status, .inFold)
        XCTAssertTrue(copy.foldInfo?.mark === dopFoldMark,
                      "Doppelganger RC's fold mark must be the DOPPELGANGER fold mark, not the progenitor")
    }

    /// unboundCopy must be idempotent for the "fold mark is already a
    /// doppelganger" case (don't try to call .doppelganger on a
    /// doppelganger — iTermMark asserts !isDoppelganger in -doppelganger).
    func test_unboundCopy_foldMark_idempotentForAlreadyDoppelganger() {
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let originalDS = FakeResilientDataSource(guid: "orig", width: 80, lines: 100)
        let newDS = FakeResilientDataSource(guid: "new", width: 80, lines: 100)

        let source = ResilientCoordinate(dataSource: originalDS,
                                         enclosingFold: dopFoldMark,
                                         coord: VT100GridCoord(x: 5, y: 10))
        let copy = source.unboundCopy()
        copy.bind(to: newDS)
        XCTAssertEqual(copy.status, .inFold)
        XCTAssertTrue(copy.foldInfo?.mark === dopFoldMark,
                      "When the source already holds a doppelganger, unboundCopy must keep that doppelganger")
    }

    /// End-to-end: a mark whose subrange has fold-bound endpoints
    /// produces a progenitor mark with progenitor fold refs and a
    /// doppelganger mark with doppelganger fold refs after the full
    /// bind + resolveUnresolved sequence that
    /// fixUpDeserializedIntervalTree: orchestrates.
    func test_progenitorAndDoppelganger_foldResolution_pickRightSide() {
        let foldMark = makeFoldMark()
        let dopFoldMark = foldMark.doppelganger() as! FoldMark
        let saveDS = FakeResilientDataSource(guid: "save", width: 80, lines: 100)

        let source = VT100ScreenMark()
        source.isPrompt = true
        source.appendExcludedSubrange(ResilientCoordinateRange(
            start: ResilientCoordinate(dataSource: saveDS,
                                        enclosingFold: foldMark,
                                        coord: VT100GridCoord(x: 0, y: 0)),
            end: ResilientCoordinate(dataSource: saveDS,
                                      enclosingFold: foldMark,
                                      coord: VT100GridCoord(x: 5, y: 0))))

        // Round-trip via dict (mirrors graph restore — decoded RCs come
        // back as `.unresolvedFold` carrying just the guid).
        let dict = source.dictionaryValue()
        let restored = VT100ScreenMark(dictionary: dict)!

        // Progenitor pass: bind + resolve fold endpoints to PROGENITOR refs.
        let mutationDS = FakeResilientDataSource(guid: "mutation", width: 80, lines: 100)
        restored.bindUnresolvedResilientCoordinates(to: mutationDS)
        for rcRange in restored.excludedSubranges! {
            rcRange.resolveUnresolved(
                foldMarkLookup: { guid in (guid == foldMark.guid) ? foldMark : nil },
                portholeMarkLookup: { _ in nil })
        }
        XCTAssertEqual(restored.excludedSubranges![0].start.status, .inFold)
        XCTAssertTrue(restored.excludedSubranges![0].start.foldInfo?.mark === foldMark,
                      "Progenitor's RC must hold PROGENITOR fold mark")

        // Doppelganger pass: copy progenitor, bind to main DS, resolve to DOPPELGANGER refs.
        // (In production, the bind step is done by EventuallyConsistentIntervalTree's add hook;
        // the resolve step is done by fixUpDeserializedIntervalTree's doppelganger pass.)
        let dop = restored.copy() as! VT100ScreenMark
        let mainDS = FakeResilientDataSource(guid: "main", width: 80, lines: 100)
        dop.bindUnresolvedResilientCoordinates(to: mainDS)
        for rcRange in dop.excludedSubranges! {
            rcRange.resolveUnresolved(
                foldMarkLookup: { guid in (guid == foldMark.guid) ? dopFoldMark : nil },
                portholeMarkLookup: { _ in nil })
        }
        XCTAssertEqual(dop.excludedSubranges![0].start.status, .inFold,
                       "Doppelganger fold-bound RC must resolve to .inFold")
        XCTAssertTrue(dop.excludedSubranges![0].start.foldInfo?.mark === dopFoldMark,
                      "Doppelganger's RC must hold DOPPELGANGER fold mark, not progenitor")
    }

    // MARK: - Helpers

    private func onlyPromptMark(in harness: TerminalTestHarness,
                                file: StaticString = #file,
                                line: UInt = #line) -> any VT100ScreenMarkReading {
        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1, "Expected exactly one prompt mark", file: file, line: line)
        return marks.first!
    }

    private func makeFoldMark() -> FoldMark {
        return FoldMark(savedLines: nil,
                        savedITOs: [],
                        promptLength: 0,
                        imageCodes: Set<Int32>(),
                        width: 80)
    }
}

// MARK: - Test conveniences

/// Minimal ResilientCoordinateDataSource for tests that exercise the
/// serialization path. Has stable read-only values; doesn't post
/// notifications (the unit tests don't trigger resize/scroll).
@objc private class FakeResilientDataSource: NSObject, ResilientCoordinateDataSource {
    let rcGuid: String
    let rcWidth: Int32
    let rcNumberOfLines: Int32
    var rcScrollbackOverflow: Int64 = 0

    init(guid: String, width: Int32, lines: Int32) {
        self.rcGuid = guid
        self.rcWidth = width
        self.rcNumberOfLines = lines
        super.init()
    }
}

