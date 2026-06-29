//
//  PromptMarkRangeFoldTests.swift
//  iTerm2
//
//  TDD tests for the migration of VT100ScreenMark.promptRange,
//  commandRange, and outputStart to ResilientCoordinate-backed storage.
//  Public interface stays as VT100GridAbsCoordRange / VT100GridAbsCoord
//  but the underlying coords self-update on fold / unfold / resize /
//  clear-to-end via the ResilientCoordinate notification pipeline.
//
//  Most "fold" / "unfold" / "doppelganger" cases are expected to FAIL
//  before the migration: the current implementation stores plain
//  abs-coord structs that never get rewritten when lines shift.
//

import XCTest
@testable import iTerm2SharedARC

final class PromptMarkRangeFoldTests: XCTestCase {

    // MARK: - Helpers

    /// Build a harness with a primary prompt that lives at a known
    /// absolute line, has a typed command, and has its output region
    /// recorded. Returns the mark and the absolute line where the
    /// prompt's `A` fired (== `promptRange.start.y`).
    ///
    /// Layout (height 24, width 80):
    ///   abs lines 0..promptLine-1 — filler ("filler N\n")
    ///   abs line promptLine        — "$ ls"     (A here, B after "$ ")
    ///   abs line promptLine + 1    — "out 1"    (C here = outputStart)
    ///   abs line promptLine + 2    — "out 2"
    ///   (cursor sits on line promptLine + 3 after D)
    private func makeMarkAt(promptLine: Int,
                            width: Int = 80,
                            height: Int = 24)
    -> (harness: TerminalTestHarness, mark: VT100ScreenMark) {
        let harness = TerminalTestHarness(width: width, height: height)
        for i in 0..<promptLine {
            harness.appendText("filler \(i)")
            harness.newline()
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("out 1")
        harness.newline()
        harness.appendText("out 2")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()

        let marks = harness.allScreenMarks().filter { $0.isPrompt }
        XCTAssertEqual(marks.count, 1, "Setup: expected exactly one prompt mark")
        return (harness, marks.first!)
    }

    /// Convenience: fold abs lines [start, end] inclusive. Mirrors the
    /// helper in ResilientCoordinateTests.
    @discardableResult
    private func fold(startLine: Int, endLine: Int,
                      screen: VT100Screen) -> NSRange {
        let range = NSRange(location: startLine, length: endLine - startLine)
        screen.foldAbsLineRange(range)
        screen.performBlock(joinedThreads: { _, _, _ in })
        return range
    }

    private func unfold(range: NSRange, screen: VT100Screen) {
        screen.removeFolds(in: range, completion: nil)
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    // MARK: - 1. Sentinel preservation (default values)

    /// A freshly-allocated VT100ScreenMark must report the existing
    /// (-1, -1, -1, -1) / (-1, -1) sentinels via the public getters.
    /// Consumers gate on `start.x >= 0`; if the migration's getter ever
    /// returns 0,0 for the unset state we'd silently break command
    /// detection everywhere.
    func test_sentinel_freshMark_returnsMinusOne() {
        let mark = VT100ScreenMark()
        XCTAssertEqual(mark.promptRange.start.x, -1)
        XCTAssertEqual(mark.promptRange.start.y, -1)
        XCTAssertEqual(mark.promptRange.end.x, -1)
        XCTAssertEqual(mark.promptRange.end.y, -1)

        XCTAssertEqual(mark.commandRange.start.x, -1)
        XCTAssertEqual(mark.commandRange.start.y, -1)
        XCTAssertEqual(mark.commandRange.end.x, -1)
        XCTAssertEqual(mark.commandRange.end.y, -1)

        XCTAssertEqual(mark.outputStart.x, -1)
        XCTAssertEqual(mark.outputStart.y, -1)
    }

    /// Setting the sentinel back through the setter must round-trip the
    /// sentinel — not get reinterpreted into a "real" coord. (Migration
    /// risk: if the setter builds an RC from (-1, -1) and the RC reports
    /// it as invalid, the getter must still return the sentinel.)
    func test_sentinel_explicitSet_roundTrips() {
        let mark = VT100ScreenMark()
        mark.promptRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1)
        mark.commandRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1)
        mark.outputStart = VT100GridAbsCoordMake(-1, -1)
        XCTAssertEqual(mark.promptRange.start.x, -1)
        XCTAssertEqual(mark.promptRange.start.y, -1)
        XCTAssertEqual(mark.commandRange.end.y, -1)
        XCTAssertEqual(mark.outputStart.x, -1)
    }

    // MARK: - 2. Setter / getter round-trip

    /// A value set via the public setter must come back unchanged via the
    /// public getter, with the mark not attached to any screen.
    func test_setter_getter_roundTrip_promptRange() {
        let mark = VT100ScreenMark()
        let r = VT100GridAbsCoordRangeMake(0, 5, 80, 5)
        mark.promptRange = r
        XCTAssertEqual(mark.promptRange.start.x, 0)
        XCTAssertEqual(mark.promptRange.start.y, 5)
        XCTAssertEqual(mark.promptRange.end.x, 80)
        XCTAssertEqual(mark.promptRange.end.y, 5)
    }

    func test_setter_getter_roundTrip_commandRange() {
        let mark = VT100ScreenMark()
        let r = VT100GridAbsCoordRangeMake(2, 5, 14, 5)
        mark.commandRange = r
        XCTAssertEqual(mark.commandRange.start.x, 2)
        XCTAssertEqual(mark.commandRange.start.y, 5)
        XCTAssertEqual(mark.commandRange.end.x, 14)
        XCTAssertEqual(mark.commandRange.end.y, 5)
    }

    func test_setter_getter_roundTrip_outputStart() {
        let mark = VT100ScreenMark()
        mark.outputStart = VT100GridAbsCoordMake(0, 6)
        XCTAssertEqual(mark.outputStart.x, 0)
        XCTAssertEqual(mark.outputStart.y, 6)
    }

    // MARK: - 3. Fold above mark shifts promptRange (NEW: was the bug)

    /// Fold 3 lines above the prompt mark. After the fold, the prompt's
    /// promptRange.start.y must shift up by the same delta the
    /// ResilientCoordinate machinery shifts other coords. This is the
    /// bug behind the stale-blue-box report.
    func test_fold_aboveMark_shiftsPromptRange() {
        let (harness, mark) = makeMarkAt(promptLine: 10)
        let yBefore = mark.promptRange.start.y
        XCTAssertEqual(yBefore, 10)

        // Fold abs lines 1..3 (a small range entirely above the prompt).
        let foldRange = fold(startLine: 1, endLine: 3, screen: harness.screen)
        // After foldAbsLineRange:NSRange(loc:1, len:2) the 3 lines 1, 2, 3
        // collapse to a 1-line fold marker. Net delta = -2.
        let expectedDelta: Int64 = -2

        let yAfter = mark.promptRange.start.y
        XCTAssertEqual(yAfter, yBefore + expectedDelta,
                       "promptRange.start.y should shift with fold above the mark")
        XCTAssertEqual(mark.promptRange.end.y, mark.promptRange.start.y,
                       "primary prompt is on one row; end.y should match start.y")
        XCTAssertEqual(mark.promptRange.start.x, 0)

        _ = foldRange // silence unused warning if assertions get edited
    }

    /// commandRange must shift on the same fold for the same reason. The
    /// expected delta is the same as for promptRange; we compute it by
    /// reading promptRange before/after as a baseline.
    func test_fold_aboveMark_shiftsCommandRange() {
        let (harness, mark) = makeMarkAt(promptLine: 10)
        let cStartBefore = mark.commandRange.start.y
        let cEndBefore = mark.commandRange.end.y
        let pStartBefore = mark.promptRange.start.y

        fold(startLine: 1, endLine: 3, screen: harness.screen)

        let pStartAfter = mark.promptRange.start.y
        let expectedDelta = pStartAfter - pStartBefore
        XCTAssertLessThan(expectedDelta, 0, "fold above the mark must produce a negative shift")

        XCTAssertEqual(mark.commandRange.start.y, cStartBefore + expectedDelta,
                       "commandRange.start.y should shift by the same delta as promptRange")
        XCTAssertEqual(mark.commandRange.end.y, cEndBefore + expectedDelta,
                       "commandRange.end.y should shift by the same delta as promptRange")
    }

    /// outputStart (single coord) must shift on the same fold.
    func test_fold_aboveMark_shiftsOutputStart() {
        let (harness, mark) = makeMarkAt(promptLine: 10)
        let oBefore = mark.outputStart.y
        XCTAssertEqual(oBefore, 11, "outputStart is the row after the prompt row")

        fold(startLine: 1, endLine: 3, screen: harness.screen)

        XCTAssertEqual(mark.outputStart.y, oBefore - 2,
                       "outputStart.y should shift on fold above mark")
        XCTAssertEqual(mark.outputStart.x, 0)
    }

    // MARK: - 4. Unfold restores

    /// Fold + unfold should leave promptRange / commandRange / outputStart
    /// pointing at the same absolute lines as before the fold.
    func test_unfold_restoresAllRanges() {
        let (harness, mark) = makeMarkAt(promptLine: 10)
        let pBefore = mark.promptRange
        let cBefore = mark.commandRange
        let oBefore = mark.outputStart

        let range = fold(startLine: 1, endLine: 3, screen: harness.screen)
        unfold(range: range, screen: harness.screen)

        XCTAssertEqual(mark.promptRange.start.y, pBefore.start.y,
                       "promptRange should return to its original abs line on unfold")
        XCTAssertEqual(mark.commandRange.start.y, cBefore.start.y,
                       "commandRange should return on unfold")
        XCTAssertEqual(mark.outputStart.y, oBefore.y,
                       "outputStart should return on unfold")
    }

    // MARK: - 5. Sentinel stays sentinel through a shift

    /// A mark whose ranges are all sentinel should NOT acquire real
    /// coords after a fold. Migration risk: if the setter eagerly
    /// constructs an RC for the sentinel, the RC's shift handler could
    /// turn (-1,-1) into something else.
    func test_sentinel_survivesFold() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        for _ in 0..<10 { harness.newline() }
        harness.sync()

        let mark = VT100ScreenMark()
        // Don't touch any of the three fields; they're at sentinel.

        fold(startLine: 1, endLine: 3, screen: harness.screen)

        XCTAssertEqual(mark.promptRange.start.y, -1)
        XCTAssertEqual(mark.commandRange.start.y, -1)
        XCTAssertEqual(mark.outputStart.y, -1)
    }

    // MARK: - 6. Width resize keeps working (post-migration RC handles it)

    /// Today the bespoke handler in VT100ScreenMutableState+Resizing.m
    /// rewrites promptRange / commandRange on width change. After the
    /// migration that handler is deleted; this test verifies the
    /// ResilientCoordinate resize converter takes over.
    func test_widthResize_promptAndCommandSurvive() {
        let (harness, mark) = makeMarkAt(promptLine: 5, width: 80)
        let pBefore = mark.promptRange
        let cBefore = mark.commandRange

        // Shrink the width but keep enough room that nothing wraps.
        harness.screen.size = VT100GridSizeMake(40, 24)
        harness.sync()

        // The prompt is on its own row; no wrap. Y should be unchanged.
        XCTAssertEqual(mark.promptRange.start.y, pBefore.start.y,
                       "promptRange.start.y should be stable across a no-wrap resize")
        XCTAssertEqual(mark.commandRange.start.y, cBefore.start.y,
                       "commandRange.start.y should be stable across a no-wrap resize")
    }

    // MARK: - 7. Doppelganger pool sees the shift

    /// The doppelganger (main-thread visible copy) of a mark must
    /// observe the same shifted ranges as the progenitor (mutation-thread
    /// side). If the migration only updates one pool's RC, this test
    /// catches that.
    func test_doppelganger_seesFoldShift() {
        let (harness, progenitor) = makeMarkAt(promptLine: 10)
        let doppelganger = progenitor.doppelganger()

        fold(startLine: 1, endLine: 3, screen: harness.screen)

        XCTAssertEqual(progenitor.promptRange.start.y, 8,
                       "progenitor must observe the shift")
        XCTAssertEqual(doppelganger.promptRange.start.y, 8,
                       "doppelganger must observe the same shift via its own pool's RC")
        XCTAssertEqual(doppelganger.commandRange.start.y, 8)
        XCTAssertEqual(doppelganger.outputStart.y, 9)
    }

    // MARK: - 8. Serialization round-trip preserves abs coords

    /// dictionaryValue / initWithDictionary must preserve abs coords
    /// across encode/decode. (RC-backed storage resolves to abs on
    /// write; init from dict builds an unbound RC; before the mark is
    /// inserted into a tree the unbound RC's resolved value is the abs
    /// that came from the dict.)
    func test_serialization_roundTripsAbsCoords() {
        let mark = VT100ScreenMark()
        mark.promptRange = VT100GridAbsCoordRangeMake(0, 7, 80, 7)
        mark.commandRange = VT100GridAbsCoordRangeMake(2, 7, 14, 7)
        mark.outputStart = VT100GridAbsCoordMake(0, 8)

        let dict = mark.dictionaryValue() ?? [:]
        let restored = VT100ScreenMark(dictionary: dict)

        XCTAssertEqual(restored?.promptRange.start.y, 7)
        XCTAssertEqual(restored?.promptRange.end.x, 80)
        XCTAssertEqual(restored?.commandRange.start.x, 2)
        XCTAssertEqual(restored?.commandRange.end.x, 14)
        XCTAssertEqual(restored?.outputStart.y, 8)
    }

    // MARK: - 9. Back-compat: legacy abs-coord encoding still decodes

    /// Old saved sessions encoded promptRange / commandRange / outputStart
    /// as plain abs-coord NSDictionary blobs under the legacy keys. The
    /// new build no longer writes those keys, but the decoder must still
    /// accept them so pre-migration saved sessions load correctly.
    func test_serialization_decodesLegacyAbsCoordOnly() {
        // Take a fresh dict (RC-format keys) and substitute the legacy
        // abs-coord shape for the three migrated fields, mirroring what a
        // pre-feature saved session would have looked like on disk.
        let donor = VT100ScreenMark()
        donor.promptRange = VT100GridAbsCoordRangeMake(0, 7, 80, 7)
        donor.commandRange = VT100GridAbsCoordRangeMake(2, 7, 14, 7)
        donor.outputStart = VT100GridAbsCoordMake(0, 8)
        var dict = donor.dictionaryValue() ?? [:]
        dict.removeValue(forKey: "Prompt Range RC")
        dict.removeValue(forKey: "Command Range RC")
        dict.removeValue(forKey: "Output Start RC")
        // Construct the legacy on-disk shape directly. The key constants
        // ("x", "absY", "start", "end") match NSDictionary+iTerm.m, which
        // is where the legacy encoder used to live.
        func absCoord(_ x: Int32, _ y: Int64) -> [String: Any] {
            return ["x": x, "absY": y]
        }
        func absRange(_ x0: Int32, _ y0: Int64, _ x1: Int32, _ y1: Int64) -> [String: Any] {
            return ["start": absCoord(x0, y0), "end": absCoord(x1, y1)]
        }
        dict["Prompt Range"] = absRange(0, 7, 80, 7)
        dict["Command Range"] = absRange(2, 7, 14, 7)
        dict["Output Start"] = absCoord(0, 8)

        let restored = VT100ScreenMark(dictionary: dict)

        XCTAssertEqual(restored?.promptRange.start.y, 7,
                       "Legacy abs-coord encoding must still decode")
        XCTAssertEqual(restored?.commandRange.start.x, 2)
        XCTAssertEqual(restored?.commandRange.end.x, 14)
        XCTAssertEqual(restored?.outputStart.y, 8)
    }

    // MARK: - Progenitor/doppelganger agreement when fold contains the coord

    /// When a fold contains a mark's outputStart, BOTH the progenitor's
    /// outputStart and the doppelganger's outputStart should report
    /// "this is inside a fold" (sentinel via the getter).
    ///
    /// Bug: the mutation-thread linesShifted post inside
    /// `replaceRange:withLines:...` runs BEFORE the caller has assigned
    /// `createdFoldMark`, so `markProvider()` returns nil and the
    /// userInfo carries no mark. The .fold case in RC.linesDidShift then
    /// skips the entering-fold branch and shifts the coord up by delta
    /// instead, leaving the progenitor at a wrong-but-valid abs while
    /// the doppelganger (notified via PTYSession's main-thread repost
    /// AFTER createdFoldMark is set) correctly enters .fold.
    func test_foldContainingOutputStart_progenitorAndDoppelgangerAgree() {
        let (harness, mark) = makeMarkAt(promptLine: 10)
        let doppelganger = mark.doppelganger()

        // Fold lines 11..12 — covers outputStart (which sat at y=11 from
        // the makeMarkAt setup) and the first output row.
        fold(startLine: 11, endLine: 12, screen: harness.screen)

        XCTAssertEqual(mark.outputStart.x, -1,
                       "progenitor outputStart must enter the fold (returns sentinel)")
        XCTAssertEqual(mark.outputStart.y, -1,
                       "progenitor outputStart must enter the fold (returns sentinel)")
        XCTAssertEqual(doppelganger.outputStart.x, mark.outputStart.x,
                       "progenitor and doppelganger must agree on outputStart")
        XCTAssertEqual(doppelganger.outputStart.y, mark.outputStart.y,
                       "progenitor and doppelganger must agree on outputStart")
    }

    // MARK: - Exclusive-endpoint regression

    /// commandRange / promptRange use exclusive end coords: a command
    /// that fills the last column has end.x == width. ResilientCoordinate
    /// reports status `.invalid` for `coord.x >= rcWidth`, which would
    /// otherwise collapse the whole range to the (-1, -1) sentinel after
    /// binding. The getters must tolerate the exclusive end and return
    /// the abs range intact.
    func test_endXAtWidth_doesNotCollapseToSentinel() {
        let width: Int32 = 80
        let (harness, mark) = makeMarkAt(promptLine: 5, width: Int(width))
        // Replace the mark's commandRange with one whose end.x equals
        // the terminal width (the documented exclusive-endpoint case).
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.mutableIntervalTree().mutate(mark) { obj in
                guard let m = obj as? VT100ScreenMark else { return }
                m.commandRange = VT100GridAbsCoordRangeMake(0, 5, width, 5)
                m.promptRange = VT100GridAbsCoordRangeMake(0, 5, width, 5)
            }
        })
        harness.sync()

        XCTAssertEqual(mark.commandRange.start.x, 0,
                       "commandRange with end.x == width must not collapse to sentinel")
        XCTAssertEqual(mark.commandRange.end.x, width,
                       "exclusive end at column == width must round-trip intact")
        XCTAssertEqual(mark.promptRange.end.x, width,
                       "promptRange with end.x == width must also round-trip intact")
    }

    /// New encode writes only the RC-format keys (full fidelity). The
    /// legacy abs-coord keys are accepted on decode for pre-feature
    /// saved sessions but no longer written — they collapsed
    /// fold/porthole references to (-1, -1) via the getter, which would
    /// silently drop data if read by an older build.
    func test_serialization_writesRCKeysOnly() {
        let mark = VT100ScreenMark()
        mark.promptRange = VT100GridAbsCoordRangeMake(0, 7, 80, 7)
        mark.commandRange = VT100GridAbsCoordRangeMake(2, 7, 14, 7)
        mark.outputStart = VT100GridAbsCoordMake(0, 8)

        let dict = mark.dictionaryValue() ?? [:]
        XCTAssertNotNil(dict["Prompt Range RC"], "new RC promptRange key written")
        XCTAssertNotNil(dict["Command Range RC"], "new RC commandRange key written")
        XCTAssertNotNil(dict["Output Start RC"], "new RC outputStart key written")
        XCTAssertNil(dict["Prompt Range"], "legacy promptRange key no longer written")
        XCTAssertNil(dict["Command Range"], "legacy commandRange key no longer written")
        XCTAssertNil(dict["Output Start"], "legacy outputStart key no longer written")
    }

    // MARK: - Saved-tree (alt-screen) resize

    /// Helper: pull the mark whose abs y matches `expectedY` out of
    /// whichever interval tree currently has it. After a swap, a mark
    /// may live in either the primary or saved tree depending on the
    /// active grid. Returns nil if the mark has been removed entirely.
    private func findScreenMark(matching guid: String,
                                in harness: TerminalTestHarness) -> VT100ScreenMark? {
        var result: VT100ScreenMark?
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.guid == guid {
                    result = m
                    return
                }
            }
            let saved = mutableState.mutableSavedIntervalTree()
            for obj in saved.allObjects() {
                if let m = obj as? VT100ScreenMark, m.guid == guid {
                    result = m
                    return
                }
            }
        })
        return result
    }

    /// Build a harness where a prompt mark is created INSIDE alt
    /// screen mode, then the user switches back to primary so the alt
    /// mark moves to the saved tree (its abs coords reference content
    /// in the alt screen's linebuffer, NOT the primary linebuffer).
    /// This is the regression-prone shape: the resize broadcast's
    /// converter is built against self.linebuffer (primary), which
    /// can't resolve saved-tree marks whose content lives in
    /// altScreenLineBuffer.
    private func makeMarkInSavedTree(promptLine: Int,
                                     width: Int = 60,
                                     height: Int = 12)
    -> (harness: TerminalTestHarness, guid: String) {
        let harness = TerminalTestHarness(width: width, height: height)
        // Enter alt mode FIRST. Subsequent text + OSC 133 lands in the
        // alt grid; the mark is created against alt-screen content.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        for i in 0..<promptLine {
            harness.appendText("alt fill \(i)")
            harness.newline()
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("out 1")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()
        // Grab the mark's guid while it's still in the active tree.
        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt {
                    guid = m.guid
                    return
                }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: failed to create prompt mark in alt mode")
        // Switch back to primary; the alt mark moves to the saved tree
        // via swapOnscreenIntervalTreeObjects.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()
        return (harness, guid)
    }

    /// Width SHRINK with the mark in the saved tree (alt-screen
    /// content). The broadcast's primary-linebuffer converter can't
    /// resolve the mark's alt-screen coords; without a saved-tree DS
    /// the mark's RCs invalidate and the getters return sentinel.
    func test_savedTree_altMarkSurvivesWidthShrink() {
        let (harness, guid) = makeMarkInSavedTree(promptLine: 3, width: 60, height: 12)

        harness.screen.size = VT100GridSizeMake(30, 12)
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared after width shrink while in saved tree")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.x, 0,
                                    "promptRange must survive a width shrink while the mark sits in the saved tree")
        XCTAssertGreaterThanOrEqual(after.commandRange.start.x, 0,
                                    "commandRange must survive a width shrink while the mark sits in the saved tree")
        XCTAssertGreaterThanOrEqual(after.outputStart.x, 0,
                                    "outputStart must survive a width shrink while the mark sits in the saved tree")
    }

    /// Width GROW with the mark in the saved tree (alt-screen content).
    func test_savedTree_altMarkSurvivesWidthGrow() {
        let (harness, guid) = makeMarkInSavedTree(promptLine: 3, width: 40, height: 12)

        harness.screen.size = VT100GridSizeMake(80, 12)
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared after width grow while in saved tree")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.x, 0)
        XCTAssertGreaterThanOrEqual(after.commandRange.start.x, 0)
        XCTAssertGreaterThanOrEqual(after.outputStart.x, 0)
    }

    /// Resize WHILE STILL IN ALT MODE (mark created in primary first
    /// and then user enters alt). The original primary mark is now in
    /// the saved tree, and resize happens with currentGrid == altGrid.
    /// updateAlternateScreenIntervalTreeForNewSize is NOT called in
    /// that branch, so the saved-tree mark has no bespoke repair path
    /// — only the proper RC-pool split fixes this.
    func test_savedTree_resizeInAltMode_primaryMarkSurvives() {
        let (harness, mark) = makeMarkAt(promptLine: 4, width: 60, height: 12)
        let guid = mark.guid

        // Enter alt mode; primary mark moves to saved tree.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        // Resize WHILE in alt mode. wasShowingAltScreen branch runs;
        // updateAlternateScreenIntervalTreeForNewSize is NOT invoked.
        harness.screen.size = VT100GridSizeMake(30, 12)
        harness.sync()

        // Swap back so we can inspect the mark from the primary tree.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared during resize-in-alt")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.x, 0,
                                    "primary-origin mark must survive a resize that happens while in alt mode")
        XCTAssertGreaterThanOrEqual(after.commandRange.start.x, 0)
        XCTAssertGreaterThanOrEqual(after.outputStart.x, 0)
    }

    /// Round-trip: alt-screen mark → switch to primary (now in saved
    /// tree) → resize → switch back to alt (mark migrates back to
    /// active tree). The migration through swapOnscreenIntervalTreeObjects
    /// must preserve the mark's coords.
    func test_savedTree_roundTripThroughAlt_marksReturnIntact() {
        let (harness, guid) = makeMarkInSavedTree(promptLine: 3, width: 60, height: 12)

        harness.screen.size = VT100GridSizeMake(30, 12)
        harness.sync()

        // Swap back to alt; mark migrates back to the active tree.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared after alt round-trip")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.x, 0,
                                    "promptRange must come back valid after the alt round-trip")
        XCTAssertGreaterThanOrEqual(after.commandRange.start.x, 0)
        XCTAssertGreaterThanOrEqual(after.outputStart.x, 0)
    }

    /// commandRange.end.x == width across a saved-tree resize. The
    /// exclusive-endpoint case (already covered for primary-tree marks
    /// in test_endXAtWidth_doesNotCollapseToSentinel) must hold when
    /// the mark lives in the saved tree too.
    func test_savedTree_endXAtWidth_resize_doesNotCollapse() {
        let (harness, guid) = makeMarkInSavedTree(promptLine: 3, width: 40, height: 12)

        // Force commandRange end.x to the OLD terminal width so that
        // the post-resize reflow has to deal with an exclusive endpoint
        // sitting right at the original right margin.
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let saved = mutableState.mutableSavedIntervalTree() as? EventuallyConsistentIntervalTree else { return }
            for obj in saved.allObjects() {
                guard let m = obj as? VT100ScreenMark, m.guid == guid else { continue }
                saved.mutate(m) { mutableObj in
                    guard let mm = mutableObj as? VT100ScreenMark else { return }
                    let y = mm.promptRange.start.y
                    mm.commandRange = VT100GridAbsCoordRangeMake(2, y, 40, y)
                }
                break
            }
        })
        harness.sync()

        harness.screen.size = VT100GridSizeMake(20, 12)
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared during saved-tree end.x-at-width resize")
            return
        }
        XCTAssertGreaterThanOrEqual(after.commandRange.start.x, 0,
                                    "commandRange must survive saved-tree resize with end.x at width")
    }

    // MARK: - Lock-in tests for existing behavior

    /// A primary mark must keep its coords intact across a swap into
    /// the saved tree and back. Locks in the current `swap` semantics
    /// before the saved-tree DS split.
    func test_lockin_primaryMark_swapRoundTrip_coordsIntact() {
        let (harness, mark) = makeMarkAt(promptLine: 4, width: 60, height: 12)
        let guid = mark.guid
        let pBefore = mark.promptRange
        let cBefore = mark.commandRange
        let oBefore = mark.outputStart

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        // Mark now lives in the saved tree. Read via findScreenMark to
        // pull from whichever tree it's in.
        guard let inAlt = findScreenMark(matching: guid, in: harness) else {
            XCTFail("primary mark lost during swap to alt")
            return
        }
        XCTAssertEqual(inAlt.promptRange.start.y, pBefore.start.y,
                       "swap to alt must not alter promptRange")
        XCTAssertEqual(inAlt.commandRange.start.y, cBefore.start.y,
                       "swap to alt must not alter commandRange")
        XCTAssertEqual(inAlt.outputStart.y, oBefore.y,
                       "swap to alt must not alter outputStart")

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("primary mark lost during swap back")
            return
        }
        XCTAssertEqual(after.promptRange.start.y, pBefore.start.y,
                       "swap round-trip must restore promptRange")
        XCTAssertEqual(after.promptRange.start.x, pBefore.start.x)
        XCTAssertEqual(after.promptRange.end.x, pBefore.end.x)
        XCTAssertEqual(after.commandRange.start.y, cBefore.start.y,
                       "swap round-trip must restore commandRange")
        XCTAssertEqual(after.outputStart.y, oBefore.y,
                       "swap round-trip must restore outputStart")
    }

    /// Progenitor and doppelganger must agree on coords AFTER a swap.
    /// Locks in that swap doesn't desync the two pools.
    func test_lockin_swap_doppelgangerAgrees() {
        let (harness, mark) = makeMarkAt(promptLine: 4, width: 60, height: 12)
        let dop = mark.doppelganger()

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()

        XCTAssertEqual(mark.promptRange.start.y, dop.promptRange.start.y,
                       "progenitor and doppelganger must agree on promptRange post-swap")
        XCTAssertEqual(mark.commandRange.start.y, dop.commandRange.start.y,
                       "progenitor and doppelganger must agree on commandRange post-swap")
        XCTAssertEqual(mark.outputStart.y, dop.outputStart.y,
                       "progenitor and doppelganger must agree on outputStart post-swap")
    }

    /// A primary-origin mark sitting in the saved tree must survive a
    /// resize while still in alt mode. Locks in the
    /// previously-confirmed case: primary content is in self.linebuffer,
    /// which the resize broadcast's converter can resolve.
    func test_lockin_primaryMarkInSavedTree_resizeInAlt_coordsValid() {
        let (harness, mark) = makeMarkAt(promptLine: 4, width: 60, height: 12)
        let guid = mark.guid

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        harness.screen.size = VT100GridSizeMake(30, 12)
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("primary mark lost during resize in alt")
            return
        }
        // The mark survived; coords should be valid abs (not sentinel).
        XCTAssertGreaterThanOrEqual(after.promptRange.start.x, 0)
        XCTAssertGreaterThanOrEqual(after.promptRange.start.y, 0)
        XCTAssertGreaterThanOrEqual(after.commandRange.start.x, 0)
        XCTAssertGreaterThanOrEqual(after.outputStart.x, 0)
        XCTAssertGreaterThanOrEqual(after.outputStart.y, 0)
    }

    /// Width resize on a primary-tree mark with commandRange.end.x set
    /// to the original width. Locks in that the exclusive endpoint
    /// passes through the RC resize converter without collapsing to
    /// sentinel. Distinct from the static round-trip test: this one
    /// drives an actual resize.
    func test_lockin_primaryMark_endXAtWidth_acrossResize() {
        let oldWidth: Int32 = 80
        let (harness, mark) = makeMarkAt(promptLine: 4,
                                          width: Int(oldWidth),
                                          height: 12)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.mutableIntervalTree().mutate(mark) { obj in
                guard let m = obj as? VT100ScreenMark else { return }
                m.commandRange = VT100GridAbsCoordRangeMake(2,
                                                             mark.promptRange.start.y,
                                                             oldWidth,
                                                             mark.promptRange.start.y)
            }
        })
        harness.sync()
        XCTAssertEqual(mark.commandRange.end.x, oldWidth,
                       "setup: commandRange.end.x should be at the old width")

        harness.screen.size = VT100GridSizeMake(40, 12)
        harness.sync()

        XCTAssertGreaterThanOrEqual(mark.commandRange.start.x, 0,
                                    "primary mark with end.x at width must survive resize")
        XCTAssertGreaterThanOrEqual(mark.commandRange.end.x, 0,
                                    "primary mark commandRange.end.x must not collapse on resize")
    }

    /// Primary mark with output spanning multiple rows: after width
    /// resize, outputStart must still be a valid coord (not sentinel)
    /// and still point at content within the addressable buffer.
    func test_lockin_primaryMark_multiRowOutput_resizeStaysValid() {
        let harness = TerminalTestHarness(width: 80, height: 24)
        for i in 0..<3 {
            harness.appendText("filler \(i)")
            harness.newline()
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        for j in 0..<6 {
            harness.appendText("output row \(j)")
            harness.newline()
        }
        harness.sendReturnCode(0)
        harness.sync()
        guard let mark = harness.allScreenMarks().filter({ $0.isPrompt }).first else {
            XCTFail("setup: missing prompt mark")
            return
        }
        let oBefore = mark.outputStart
        XCTAssertGreaterThanOrEqual(oBefore.x, 0)

        harness.screen.size = VT100GridSizeMake(40, 24)
        harness.sync()

        XCTAssertGreaterThanOrEqual(mark.outputStart.x, 0,
                                    "multi-row output must keep a valid outputStart through resize")
        XCTAssertGreaterThanOrEqual(mark.outputStart.y, 0)
    }

    /// Long primary-tree prompt that gets force-wrapped by a narrow
    /// resize. The linebuffer-based RC converter (NOT the deleted
    /// start.x/width hack) must keep promptRange within bounds and
    /// non-inverted. Mirror of the saved-tree wrap test but ON THE
    /// PRIMARY TREE so we lock in current correct behavior.
    func test_lockin_primaryMark_promptWrap_resizeCorrect() {
        let harness = TerminalTestHarness(width: 80, height: 12)
        for i in 0..<3 {
            harness.appendText("filler \(i)")
            harness.newline()
        }
        harness.sendPromptStart()
        harness.appendText(String(repeating: "P", count: 60))
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("o")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()
        guard let mark = harness.allScreenMarks().filter({ $0.isPrompt }).first else {
            XCTFail("setup: missing prompt mark")
            return
        }

        harness.screen.size = VT100GridSizeMake(20, 12)
        harness.sync()

        let pr = mark.promptRange
        XCTAssertGreaterThanOrEqual(pr.start.x, 0)
        XCTAssertLessThanOrEqual(pr.end.x, 20)
        XCTAssertLessThanOrEqual(pr.start.x, 20)
        let startBeforeEnd = pr.start.y < pr.end.y ||
                             (pr.start.y == pr.end.y && pr.start.x <= pr.end.x)
        XCTAssertTrue(startBeforeEnd,
                      "primary prompt range wrap must not be inverted")
    }

    /// Fold and then swap: a mark with a fold above it goes into alt
    /// mode (mark moves to saved tree). The fold relationship was
    /// expressed via the abs coord shift, NOT via .fold location (the
    /// mark wasn't inside the fold). Locks in that the shifted coord
    /// stays correct through the swap.
    func test_lockin_foldAboveMark_thenSwap_coordsStillShifted() {
        let (harness, mark) = makeMarkAt(promptLine: 10, width: 60, height: 24)
        let pBefore = mark.promptRange.start.y
        let guid = mark.guid

        fold(startLine: 1, endLine: 3, screen: harness.screen)
        let pAfterFold = mark.promptRange.start.y
        XCTAssertLessThan(pAfterFold, pBefore,
                          "setup: fold above must have shifted promptRange up")

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        guard let inSaved = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared on swap-after-fold")
            return
        }
        XCTAssertEqual(inSaved.promptRange.start.y, pAfterFold,
                       "swap must preserve the post-fold abs y")
    }

    /// Sentinel semantics survive the swap: a mark whose
    /// outputStart was never set still reports the (-1, -1) sentinel
    /// after a swap round-trip.
    func test_lockin_sentinel_survivesSwap() {
        let harness = TerminalTestHarness(width: 60, height: 12)
        harness.appendText("hello")
        harness.newline()
        harness.sendPromptStart()
        harness.appendText("$ ")
        // No sendCommandStart / sendCommandEnd / sendReturnCode: leave
        // outputStart at sentinel.
        harness.sync()
        guard let mark = harness.allScreenMarks().filter({ $0.isPrompt }).first else {
            XCTFail("setup: missing prompt mark")
            return
        }
        XCTAssertEqual(mark.outputStart.x, -1,
                       "setup: outputStart should still be sentinel")

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()

        XCTAssertEqual(mark.outputStart.x, -1,
                       "sentinel outputStart must survive swap round-trip")
        XCTAssertEqual(mark.outputStart.y, -1)
    }

    /// Fold WHILE in alt mode with a primary-origin mark in the saved
    /// tree. Locks in current behavior: folds on the alt screen affect
    /// alt content; the primary-origin saved-tree mark's coords are
    /// not in the alt-fold range, so they shouldn't change. (If they
    /// DO change, the fix is breaking unrelated state.)
    func test_lockin_foldInAlt_doesNotAffectSavedTreePrimaryMark() {
        let (harness, mark) = makeMarkAt(promptLine: 4, width: 60, height: 12)
        let pBefore = mark.promptRange.start.y
        let cBefore = mark.commandRange.start.y
        let oBefore = mark.outputStart.y
        let guid = mark.guid

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()

        // Fold lines that don't overlap the primary mark's abs range.
        // After entering alt, the alt grid's content occupies a
        // different abs range, and the saved-tree primary mark's abs
        // coords were captured pre-swap.
        // Use a fold range far below the primary mark to ensure it
        // doesn't shift the mark.
        fold(startLine: 30, endLine: 32, screen: harness.screen)

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("primary mark lost during alt fold")
            return
        }
        XCTAssertEqual(after.promptRange.start.y, pBefore,
                       "fold below mark in alt must not shift promptRange")
        XCTAssertEqual(after.commandRange.start.y, cBefore,
                       "fold below mark in alt must not shift commandRange")
        XCTAssertEqual(after.outputStart.y, oBefore,
                       "fold below mark in alt must not shift outputStart")
    }

    /// Long primary-tree prompt that the deleted DWC-hack arithmetic
    /// (`start.y += start.x / width`) was trying to approximate. After
    /// a width-narrowing resize the prompt range must remain within
    /// bounds and the start/end relationship must be preserved. Real
    /// linebuffer-based reflow handles wrapping; the hack often
    /// produced inverted or out-of-bounds ranges.
    func test_savedTree_promptWrap_resizeReflowIsCorrect() {
        let harness = TerminalTestHarness(width: 80, height: 12)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        for i in 0..<3 {
            harness.appendText("alt fill \(i)")
            harness.newline()
        }
        harness.sendPromptStart()
        // A long primary-prompt segment that fills most of a row, so
        // narrowing the width forces it to wrap and the start.x/width
        // arithmetic would mis-place the end.
        harness.appendText(String(repeating: "P", count: 60))
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("o")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()

        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt {
                    guid = m.guid
                    return
                }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: missing prompt mark")

        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()

        harness.screen.size = VT100GridSizeMake(20, 12)
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark disappeared after wrap-inducing resize")
            return
        }
        let pr = after.promptRange
        XCTAssertGreaterThanOrEqual(pr.start.x, 0,
                                    "wrapped prompt range must not collapse to sentinel")
        XCTAssertLessThanOrEqual(pr.end.x, 20,
                                 "wrapped end.x must not exceed the new width")
        XCTAssertLessThanOrEqual(pr.start.x, 20,
                                 "wrapped start.x must not exceed the new width")
        // start must not be after end in tree order.
        let startBeforeEnd = pr.start.y < pr.end.y ||
                             (pr.start.y == pr.end.y && pr.start.x <= pr.end.x)
        XCTAssertTrue(startBeforeEnd,
                      "wrapped prompt range must not be inverted (start after end)")
    }

    /// Build a saved-tree mark whose alt content includes rows wide
    /// enough that a width-narrowing resize forces them to wrap,
    /// driving `numLinesDroppedFromTop > 0` inside
    /// `updateAlternateScreenIntervalTreeForNewSize`. The mark itself
    /// sits at a row that survives the drop.
    private func makeWrappingMarkInSavedTree(width: Int,
                                              height: Int,
                                              fillRows: Int,
                                              promptLine: Int)
    -> (harness: TerminalTestHarness, guid: String) {
        precondition(promptLine >= fillRows)
        let harness = TerminalTestHarness(width: width, height: height)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        // Wide rows (full screen width) that will wrap to 2 rows each
        // after the narrowing resize, so the alt-linebuffer reflow
        // overflows the height and drops lines from the top.
        for i in 0..<fillRows {
            harness.appendText(String(repeating: "\(i % 10)", count: width))
        }
        // Pad with empty rows up to the prompt line.
        for _ in fillRows..<promptLine {
            harness.newline()
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("o")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()
        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt {
                    guid = m.guid
                    return
                }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: missing prompt mark")
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showPrimaryBuffer()
        })
        harness.sync()
        return (harness, guid)
    }

    /// Bug A: when the alt linebuffer reflow drops lines from the top
    /// (`numLinesDroppedFromTop > 0`), the saved-tree resize converter
    /// must subtract that delta from the result so the RC coord stays
    /// consistent with the mark's interval (which DOES subtract it at
    /// `updateSavedIntervalTreeWithWidth` line ~1090). Without the
    /// subtraction the RC overshoots, fails the saved-tree DS's bounds
    /// check (`coord.y >= numberOfLines + overflow`), and every range
    /// reverts to `(-1, -1)`.
    /// YES path (resize WHILE showing the alt grid) with a height shrink
    /// that drops lines from the reflowed alt buffer. Locks in the
    /// invariant that an alt-origin screen mark's RC-backed promptRange
    /// stays consistent with the mark's interval-derived row, matching
    /// the NO-path invariant covered by
    /// test_savedTree_resize_droppedLines_rangesStayValid. The YES path
    /// rebinds the extracted-but-not-yet-readded marks' RCs to the
    /// saved-tree pool around the broadcast so the alt-linebuffer
    /// converter (with the `dropped` argument derived from
    /// altScreenLineBuffer.numLinesWithWidth − newHeight) actually
    /// reaches them.
    func test_savedTree_resizeInAltYES_droppedLines_rcMatchesInterval() {
        let width = 80
        let harness = TerminalTestHarness(width: width, height: 12)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        // Wide rows that wrap on narrowing so the alt reflow overflows the
        // shrunk height and drops lines from the top.
        for i in 0..<3 {
            harness.appendText(String(repeating: "\(i % 10)", count: width))
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("o")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()
        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt { guid = m.guid; return }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: missing prompt mark in alt")

        // Resize in alt: narrow AND shrink height so the alt reflow drops
        // lines from the top (YES path, dropped > 0).
        harness.screen.size = VT100GridSizeMake(40, 6)
        harness.sync()

        var promptStartY: Int64 = .min
        var intervalAbsStartY: Int64 = .max
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                guard let m = obj as? VT100ScreenMark, m.guid == guid else { continue }
                let cr = mutableState.coordRange(for: m.entry!.interval)
                intervalAbsStartY = Int64(cr.start.y) + mutableState.cumulativeScrollbackOverflow
                promptStartY = m.promptRange.start.y
                return
            }
        })
        XCTAssertEqual(promptStartY, intervalAbsStartY,
                       "promptRange.start.y (\(promptStartY)) must match the mark's interval row (\(intervalAbsStartY)) after a drop-inducing resize while showing alt")
    }

    func test_savedTree_resize_droppedLines_rangesStayValid() {
        // width 80, height 12, fillRows 3 (each 80 chars wraps to 2 at
        // width 40) plus prompt at row 3 + 2 more rows of content.
        // Width 80 -> 40 at height 6 -> dropped > 0.
        let (harness, guid) = makeWrappingMarkInSavedTree(width: 80,
                                                          height: 12,
                                                          fillRows: 3,
                                                          promptLine: 3)

        harness.screen.size = VT100GridSizeMake(40, 6)
        harness.sync()

        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark must survive a resize that drops lines from the top")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.y, 0,
                                    "promptRange must NOT revert to sentinel when lines drop from top")
        XCTAssertGreaterThanOrEqual(after.commandRange.start.y, 0,
                                    "commandRange must NOT revert to sentinel when lines drop from top")
        XCTAssertGreaterThanOrEqual(after.outputStart.y, 0,
                                    "outputStart must NOT revert to sentinel when lines drop from top")
    }

    /// Bug B: in the wasShowingAltScreen=YES resize path the swap is
    /// triggered by `prepareToResizeInAlternateScreenMode`, INSIDE the
    /// same `reallySetSize:` joined block as the saved-tree broadcast.
    /// The swap rebinds doppelganger RCs via `addSideEffect:`, which
    /// is deferred until the joined block ends. The broadcast then
    /// fires synchronously, before the side effect runs, so the
    /// doppelganger is still bound to its old pool and never sees the
    /// converter. After the dust settles the doppelganger's RC keeps
    /// the pre-resize value while the progenitor's reflows; the two
    /// must agree.
    /// Bug B: when the prepareToResize swap moves marks from saved
    /// tree → primary tree (the saved→primary direction), the swap
    /// rebinds the progenitor synchronously and queues the
    /// doppelganger rebind via `addSideEffect:`. The saved-tree
    /// broadcast then posts inside the same joined block, BEFORE the
    /// doppelganger side effect fires. Net: doppelganger still
    /// observes the saved-tree pool when the broadcast posts, so it
    /// gets the converter update; progenitor has been rebound to the
    /// primary pool, so it does NOT. After the joined block ends, the
    /// two end up with mismatched coords.
    func test_savedTree_resizeInAltYES_doppelgangerMatchesProgenitor() {
        // Create the mark in PRIMARY (normal mode), wide enough to
        // force a non-identity reflow at 80→40.
        let harness = TerminalTestHarness(width: 80, height: 12)
        for i in 0..<3 {
            harness.appendText(String(repeating: "\(i)", count: 80))
            harness.newline()
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("o")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()
        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt { guid = m.guid; return }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: missing prompt mark in primary")
        // Switch to alt — showAltBuffer's swap moves the mark
        // primary → saved tree. Sync so that swap's deferred
        // doppelganger rebind fires (mark's doppelganger is now bound
        // to the saved-tree-main pool, consistent with progenitor).
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        // Now resize while still in alt. The prepareToResize swap will
        // move the mark back saved → primary; the saved-tree broadcast
        // fires in the same joined block before the doppelganger
        // rebind side effect runs.
        harness.screen.size = VT100GridSizeMake(40, 12)
        harness.sync()

        var progY: Int64 = .min
        var dopY: Int64 = .min
        var foundInPrimary = false
        var foundInSaved = false
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.guid == guid {
                    foundInPrimary = true
                    progY = m.promptRange.start.y
                    let dop: any VT100ScreenMarkReading = m.doppelganger()
                    dopY = dop.promptRange.start.y
                    return
                }
            }
            for obj in mutableState.mutableSavedIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.guid == guid {
                    foundInSaved = true
                    progY = m.promptRange.start.y
                    let dop: any VT100ScreenMarkReading = m.doppelganger()
                    dopY = dop.promptRange.start.y
                    return
                }
            }
        })
        XCTAssertTrue(foundInPrimary || foundInSaved,
                      "setup: mark must exist in some tree post-resize")
        XCTAssertEqual(dopY, progY,
                       "doppelganger promptRange.start.y (\(dopY)) must match progenitor (\(progY)) after resize-in-alt (foundInPrimary=\(foundInPrimary), foundInSaved=\(foundInSaved))")
    }

    /// Row-zero clamp edge case (NO path). When the mark's reflowed
    /// row lands within the dropped region (raw.y < dropped), the
    /// interval reflow clamps to row 0 (see
    /// updateSavedIntervalTreeWithWidth's newRange.y < 0 clamp). The
    /// broadcast converter must clamp the same way instead of
    /// returning VT100GridAbsCoordInvalid — otherwise the RC reverts
    /// to sentinel while the interval is at row 0, the exact
    /// interval/RC divergence the saved-tree refactor exists to
    /// close. Repro shape: fillRows=5, width 80→20, height 12→4.
    func test_savedTree_resize_rowZeroEdge_clampsRatherThanSentinel() {
        let (harness, guid) = makeWrappingMarkInSavedTree(width: 80,
                                                          height: 12,
                                                          fillRows: 5,
                                                          promptLine: 5)
        harness.screen.size = VT100GridSizeMake(20, 4)
        harness.sync()
        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("mark must survive the row-zero-edge drop resize")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.y, 0,
                                    "promptRange must clamp to row 0 instead of going to sentinel")
        XCTAssertGreaterThanOrEqual(after.commandRange.start.y, 0,
                                    "commandRange must clamp to row 0 instead of going to sentinel")
        XCTAssertGreaterThanOrEqual(after.outputStart.y, 0,
                                    "outputStart must clamp to row 0 instead of going to sentinel")
    }

    /// Row-zero clamp edge case (YES path). Same shape as the NO-path
    /// test above but the resize happens while still in alt mode, so
    /// the converter runs via the prepareToResize-extracted-marks
    /// rebind dance instead of updateAlternateScreenIntervalTreeForNewSize.
    func test_savedTree_resizeInAltYES_rowZeroEdge_clampsRatherThanSentinel() {
        let width = 80
        let harness = TerminalTestHarness(width: width, height: 12)
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.showAltBuffer()
        })
        harness.sync()
        for i in 0..<5 {
            harness.appendText(String(repeating: "\(i % 10)", count: width))
        }
        harness.sendPromptStart()
        harness.appendText("$ ")
        harness.sendCommandStart()
        harness.appendText("ls")
        harness.newline()
        harness.sendCommandEnd()
        harness.appendText("o")
        harness.newline()
        harness.sendReturnCode(0)
        harness.sync()
        var guid = ""
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            for obj in mutableState.mutableIntervalTree().allObjects() {
                if let m = obj as? VT100ScreenMark, m.isPrompt { guid = m.guid; return }
            }
        })
        XCTAssertFalse(guid.isEmpty, "setup: missing prompt mark")
        harness.screen.size = VT100GridSizeMake(20, 4)
        harness.sync()
        guard let after = findScreenMark(matching: guid, in: harness) else {
            XCTFail("YES path: mark must survive the row-zero-edge drop resize")
            return
        }
        XCTAssertGreaterThanOrEqual(after.promptRange.start.y, 0,
                                    "YES path: promptRange must clamp to row 0 instead of going to sentinel")
        XCTAssertGreaterThanOrEqual(after.commandRange.start.y, 0,
                                    "YES path: commandRange must clamp to row 0 instead of going to sentinel")
        XCTAssertGreaterThanOrEqual(after.outputStart.y, 0,
                                    "YES path: outputStart must clamp to row 0 instead of going to sentinel")
    }
}
