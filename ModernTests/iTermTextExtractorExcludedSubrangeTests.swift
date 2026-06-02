//
//  iTermTextExtractorExcludedSubrangeTests.swift
//  iTerm2
//
//  Direct tests for -[iTermTextExtractor contentInRange:excludingSubranges:].
//  The end-to-end production path is covered indirectly by
//  PromptMarkExcludedSubrangeTests.swift's Group 8 (fullCommand capture),
//  but those tests can only assert on the surfaced mark.fullCommand. The
//  cases below exercise the extractor method in isolation against a
//  controlled VT100Screen, so we can hit edge cases (unresolved RCs,
//  out-of-order subranges, soft wrap, etc.) that the receiver path can't
//  reach.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTextExtractorExcludedSubrangeTests: XCTestCase {

    // MARK: - Helpers

    /// Build a harness, write `text` starting at the cursor, and return the
    /// configured screen wrapped in an extractor.
    private func extractor(width: Int = 40, height: Int = 24, writing text: String = "") -> (TerminalTestHarness, iTermTextExtractor) {
        let h = TerminalTestHarness(width: width, height: height)
        if !text.isEmpty {
            h.appendText(text)
            h.sync()
        }
        let extractor = iTermTextExtractor(dataSource: h.screen)
        return (h, extractor)
    }

    /// A range covering rows [startY...endY] inclusive, columns 0..endX on
    /// the final row.
    private func range(startY: Int, endY: Int, endX: Int) -> VT100GridWindowedRange {
        return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, Int32(startY),
                                                                  Int32(endX), Int32(endY)),
                                          0, 0)
    }

    /// Convenience: build a single resilient excluded subrange against
    /// `ds` from (sx,sy) to (ex,ey).
    private func excluded(_ ds: FakeRCDataSource, _ sx: Int, _ sy: Int, _ ex: Int, _ ey: Int) -> ResilientCoordinateRange {
        return ResilientCoordinateRange(dataSource: ds,
                                        absRange: VT100GridAbsCoordRangeMake(Int32(sx), Int64(sy),
                                                                             Int32(ex), Int64(ey)))
    }

    // MARK: - Trivial paths

    func test_noExclusions_returnsTrimmedContent() {
        let (_, ext) = extractor(writing: "echo hello")
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 10),
                              excludingSubranges: nil)
        XCTAssertEqual(out, "echo hello")
    }

    func test_emptyExcludedSubranges_isNoOp() {
        let (_, ext) = extractor(writing: "echo hello")
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 10),
                              excludingSubranges: [])
        XCTAssertEqual(out, "echo hello")
    }

    func test_negativeStart_returnsNil() {
        let (_, ext) = extractor(writing: "echo hi")
        let badRange = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(-1, -1, 5, 0), 0, 0)
        XCTAssertNil(ext.content(in: badRange, excludingSubranges: nil))
    }

    func test_emptyResult_returnsNil() {
        // Range that exists but contains only whitespace → trim leaves "" → nil.
        let (_, ext) = extractor(writing: "      ")
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 6),
                              excludingSubranges: nil)
        XCTAssertNil(out)
    }

    // MARK: - Single-range exclusion

    func test_subrangeInMiddle_dropsMiddleCells() {
        let (h, ext) = extractor(writing: "abc[XX]def")
        let ds = FakeRCDataSource(matching: h)
        let ex = excluded(ds, 3, 0, 7, 0)  // covers "[XX]"
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 10),
                              excludingSubranges: [ex])
        XCTAssertEqual(out, "abcdef")
    }

    func test_subrangeCoversEntireRange_returnsNil() {
        let (h, ext) = extractor(writing: "echo hi")
        let ds = FakeRCDataSource(matching: h)
        let ex = excluded(ds, 0, 0, 7, 0)
        XCTAssertNil(ext.content(in: range(startY: 0, endY: 0, endX: 7),
                                 excludingSubranges: [ex]))
    }

    func test_subrangeAtRangeStart_dropsLeadingCells() {
        let (h, ext) = extractor(writing: "PS>real")
        let ds = FakeRCDataSource(matching: h)
        let ex = excluded(ds, 0, 0, 3, 0)
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 7),
                              excludingSubranges: [ex])
        XCTAssertEqual(out, "real")
    }

    func test_subrangeAtRangeEnd_dropsTrailingCells() {
        let (h, ext) = extractor(writing: "real PROMPT")
        let ds = FakeRCDataSource(matching: h)
        // Exclude "PROMPT" at columns 5..11.
        let ex = excluded(ds, 5, 0, 11, 0)
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 11),
                              excludingSubranges: [ex])
        // Trim removes trailing whitespace.
        XCTAssertEqual(out, "real")
    }

    // MARK: - Multiple ranges, ordering invariants

    func test_outOfOrderSubranges_sortedInternally() {
        let (h, ext) = extractor(writing: "AA**BB##CC")
        let ds = FakeRCDataSource(matching: h)
        // Pass the later one first to force the internal sort.
        let later  = excluded(ds, 6, 0, 8, 0)   // "##"
        let earlier = excluded(ds, 2, 0, 4, 0)  // "**"
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 10),
                              excludingSubranges: [later, earlier])
        XCTAssertEqual(out, "AABBCC")
    }

    func test_twoSubrangesSameRow_bothDropped() {
        let (h, ext) = extractor(writing: "AA**BB##CC")
        let ds = FakeRCDataSource(matching: h)
        let s1 = excluded(ds, 2, 0, 4, 0)
        let s2 = excluded(ds, 6, 0, 8, 0)
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 10),
                              excludingSubranges: [s1, s2])
        XCTAssertEqual(out, "AABBCC")
    }

    // MARK: - Unresolvable / out-of-range subranges

    func test_unresolvedSubrange_silentlySkipped() {
        let (h, ext) = extractor(writing: "echo hi")
        // An RC constructed via initUnboundWithAbsCoord: stays .unresolved
        // until bind(to:) is called. The method must drop it without
        // crashing rather than treating it as the (-1,-1) projection.
        let unresolvedStart = ResilientCoordinate(unboundAbsCoord: VT100GridAbsCoordMake(0, 0))
        let unresolvedEnd   = ResilientCoordinate(unboundAbsCoord: VT100GridAbsCoordMake(7, 0))
        let rc = ResilientCoordinateRange(start: unresolvedStart, end: unresolvedEnd)
        XCTAssertEqual(rc.start.status, .unresolved)
        _ = h  // keep harness alive while we use the extractor
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 7),
                              excludingSubranges: [rc])
        XCTAssertEqual(out, "echo hi",
                       "Unresolved RC must not exclude any cells")
    }

    func test_subrangeFullyAfterRange_noFalsePositive() {
        let (h, ext) = extractor(writing: "echo hi")
        let ds = FakeRCDataSource(matching: h)
        // Exclusion on row 5, far past anything written.
        let far = excluded(ds, 0, 5, 10, 5)
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 7),
                              excludingSubranges: [far])
        XCTAssertEqual(out, "echo hi")
    }

    // MARK: - Half-open boundary

    func test_subrangeEndIsExclusive() {
        // "ab|cd|ef" — exclude columns [2, 4), i.e. just "cd".
        // The cell at column 4 ('e') must be preserved (end is exclusive).
        let (h, ext) = extractor(writing: "abcdef")
        let ds = FakeRCDataSource(matching: h)
        let ex = excluded(ds, 2, 0, 4, 0)
        let out = ext.content(in: range(startY: 0, endY: 0, endX: 6),
                              excludingSubranges: [ex])
        XCTAssertEqual(out, "abef")
    }

    // MARK: - EOL handling

    func test_hardEOL_insertsNewline() {
        let h = TerminalTestHarness(width: 40, height: 24)
        h.appendText("first")
        h.newline()
        h.appendText("second")
        h.sync()
        let ext = iTermTextExtractor(dataSource: h.screen)
        let out = ext.content(in: range(startY: 0, endY: 1, endX: 6),
                              excludingSubranges: nil)
        XCTAssertEqual(out, "first\nsecond")
    }

    func test_softWrap_joinedAsSingleLine() {
        // Write 50 chars into a 40-wide screen so the line soft-wraps.
        let line = String(repeating: "x", count: 50)
        let h = TerminalTestHarness(width: 40, height: 24)
        h.appendText(line)
        h.sync()
        let ext = iTermTextExtractor(dataSource: h.screen)
        let out = ext.content(in: range(startY: 0, endY: 1, endX: 10),
                              excludingSubranges: nil)
        // Soft wrap must not introduce a newline in the rebuilt logical line.
        XCTAssertEqual(out, line)
        XCTAssertFalse(out!.contains("\n"))
    }

    // MARK: - PS2-style integration shape

    func test_ps2Shape_subtractsPrefixOnContinuationRow() {
        // Row 0: "echo \" (typed input)
        // Row 1: "> hi"  (PS2 prefix "> " + typed "hi")
        // Exclude "> " on row 1 → expect "echo \\\nhi"
        let h = TerminalTestHarness(width: 40, height: 24)
        h.appendText("echo \\")
        h.newline()
        h.appendText("> hi")
        h.sync()
        let ext = iTermTextExtractor(dataSource: h.screen)
        let ds = FakeRCDataSource(matching: h)
        let ps2 = excluded(ds, 0, 1, 2, 1)
        let out = ext.content(in: range(startY: 0, endY: 1, endX: 4),
                              excludingSubranges: [ps2])
        XCTAssertEqual(out, "echo \\\nhi")
    }
}

/// Minimal ResilientCoordinateDataSource. RCs built against it report
/// status `.valid` (since the location is `.coord`) and project absolute
/// coords through unchanged because rcScrollbackOverflow stays at 0,
/// matching the test harness's freshly-built screen.
@objc private class FakeRCDataSource: NSObject, ResilientCoordinateDataSource {
    let rcGuid: String
    let rcWidth: Int32
    let rcNumberOfLines: Int32
    var rcScrollbackOverflow: Int64 = 0

    init(guid: String = "extractor-test", width: Int32 = 40, lines: Int32 = 200) {
        self.rcGuid = guid
        self.rcWidth = width
        self.rcNumberOfLines = lines
        super.init()
    }

    convenience init(matching harness: TerminalTestHarness) {
        self.init(width: Int32(harness.screen.width()),
                  lines: Int32(harness.screen.height()) + 200)
    }
}
