//
//  FlagAcrossWritesTests.swift
//  iTerm2
//
//  A flag emoji whose two regional indicators arrive in separate writes must end up as a
//  single two-column cell, the same as if it had arrived in one write.
//
//  iTermStringPreconverter converts " " + string on the parser thread, and the mutation
//  thread's fast path assumes anything the predecessor fixup absorbs is exactly buffer[0]
//  (plus its DWC_RIGHT). That assumption holds for combining marks and ZWJ sequences,
//  where the absorbed code points really do cluster with the prepended space. It fails for
//  regional indicators: UAX #29 GB12/GB13 pair indicators with each other, so a leading
//  indicator does NOT cluster with the space, and whether it pairs -- and therefore how
//  everything after it segments -- depends on the real predecessor.
//

import XCTest
@testable import iTerm2SharedARC

final class FlagAcrossWritesTests: XCTestCase {
    private var session = FakeSession()

    private func makeParser(unicodeVersion: Int = 9) -> VT100Parser {
        let p = VT100Parser()
        p.encoding = String.Encoding.utf8.rawValue
        p.update(VT100StringConversionConfig(ambiguousIsDoubleWidth: ObjCBool(false),
                                             normalization: .none,
                                             unicodeVersion: unicodeVersion,
                                             softAlternateScreenMode: ObjCBool(false)))
        return p
    }

    private var unicodeVersion = 9

    private func makeScreen() -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        let version = unicodeVersion
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let config = VT100MutableScreenConfiguration()
            config.unicodeVersion = version
            mutableState.setConfig(config)
            mutableState.terminalEnabled = true
            screen.destructivelySetScreenWidth(20, height: 4, mutableState: mutableState)
        })
        return screen
    }

    private static let fullWidthFlagsKey = "FullWidthFlags"
    private var savedFullWidthFlags: Any?

    override func setUp() {
        super.setUp()
        savedFullWidthFlags = iTermUserDefaults.userDefaults().object(forKey: Self.fullWidthFlagsKey)
    }

    override func tearDown() {
        if let v = savedFullWidthFlags {
            iTermUserDefaults.userDefaults().set(v, forKey: Self.fullWidthFlagsKey)
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: Self.fullWidthFlagsKey)
        }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        super.tearDown()
    }

    private func setFullWidthFlags(_ value: Bool) {
        iTermUserDefaults.userDefaults().set(value, forKey: Self.fullWidthFlagsKey)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        XCTAssertEqual(iTermAdvancedSettingsModel.fullWidthFlags(), value)
    }

    /// True if the cell at (x, 0) is a DWC_RIGHT spacer.
    private func isDWCRight(_ screen: VT100Screen, _ x: Int) -> Bool {
        var result = false
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let c = mutableState.currentGrid.character(at: VT100GridCoord(x: Int32(x), y: 0))
            result = ScreenCharIsDWC_RIGHT(c)
        })
        return result
    }

    /// Feed each string as its own VT100_STRING token, exactly as separate writes would,
    /// carrying the parser's preconverted data through to the mutation thread.
    private func append(_ pieces: [String], to screen: VT100Screen) {
        let parser = makeParser(unicodeVersion: unicodeVersion)
        for piece in pieces {
            var vector = CVector()
            CVectorCreate(&vector, 100)
            Array(piece.utf8).withUnsafeBufferPointer { buf in
                parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
            }
            _ = parser.addParsedTokens(to: &vector)
            for i in 0..<CVectorCount(&vector) {
                let token = CVectorGetObject(&vector, i) as! VT100Token
                switch token.type {
                case VT100_STRING:
                    screen.performBlock(joinedThreads: { _, mutableState, _ in
                        mutableState.appendString(atCursor: token.string ?? "",
                                                  preconvertedData: token.preconvertedStringData)
                    })
                case VT100_ASCIISTRING:
                    screen.performBlock(joinedThreads: { _, mutableState, _ in
                        mutableState.appendString(atCursor: token.stringForAsciiData())
                    })
                default:
                    continue
                }
            }
        }
    }

    /// Cells occupied on row 0, and the string in each non-spacer cell.
    private func row0(_ screen: VT100Screen) -> (cursorX: Int, cells: [String]) {
        var cursorX = 0
        var cells = [String]()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            let grid = mutableState.currentGrid
            cursorX = Int(grid.cursorX)
            for x in 0..<cursorX {
                let coord = VT100GridCoord(x: Int32(x), y: 0)
                cells.append(grid.stringOrKittyPlaceholderStringForCharacter(at: coord) ?? "")
            }
        })
        return (cursorX, cells)
    }

    /// Index-safe so a regression that shortens the row still reports each assertion
    /// instead of silently skipping it.
    private func cell(_ cells: [String], _ i: Int) -> String? {
        return i < cells.count ? cells[i] : nil
    }

    private let flagU = "\u{1F1FA}"
    private let flagS = "\u{1F1F8}"
    private let flagF = "\u{1F1EB}"
    private let flagR = "\u{1F1F7}"

    /// Baseline: one write. This already works and anchors what the split case must match.
    func testFlagInOneWrite() {
        let screen = makeScreen()
        append([flagU + flagS], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 2, "a flag occupies two columns")
        XCTAssertEqual(cells.first, flagU + flagS)
    }

    /// printf '\U0001F1FA'; printf '\U0001F1F8' -- two writes, so two tokens. Each is only
    /// two UTF-16 units, below kMinPreconvertStringLength, so this goes down the slow path
    /// and is a guard rather than a reproduction of the fast-path bug.
    func testFlagSplitAcrossTwoWrites() {
        let screen = makeScreen()
        append([flagU, flagS], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 2, "a flag split across two writes still occupies two columns")
        XCTAssertEqual(cells.first, flagU + flagS)
    }

    /// The minimal case that reaches the preconverted fast path: a token is only
    /// preconverted at kMinPreconvertStringLength (4 UTF-16 units) or more, so a lone
    /// trailing indicator is too short and a two-indicator token is the shortest that
    /// exercises it. U then SF must give the flag US and a lone F.
    func testTwoIndicatorTokenAfterLoneIndicator() {
        let screen = makeScreen()
        append([flagU, flagS + flagF], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 4, "a flag plus a lone indicator occupies four columns")
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(cell(cells, 0), flagU + flagS)
        XCTAssertEqual(cell(cells, 2), flagF)
    }

    /// The predecessor absorbs only part of the token's first cluster: predecessor U plus
    /// token SFR means firstChar is SF, so U+S becomes a flag and F must then pair with R.
    func testIndicatorRunSplitAcrossWrites() {
        let screen = makeScreen()
        append([flagU, flagS + flagF + flagR], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 4, "two flags occupy four columns")
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(cell(cells, 0), flagU + flagS)
        XCTAssertEqual(cell(cells, 2), flagF + flagR)
    }

    /// A trailing odd indicator stands alone rather than merging with the next write.
    func testCompleteFlagThenIndicatorDoesNotMerge() {
        let screen = makeScreen()
        append([flagU + flagS, flagF], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 4)
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(cell(cells, 0), flagU + flagS)
        XCTAssertEqual(cell(cells, 2), flagF)
    }

    /// The invariant the preconverter's comment relies on really does hold for combining
    /// marks, so the fix must not disturb them.
    func testCombiningMarkAcrossWritesStillMerges() {
        let screen = makeScreen()
        append(["e", "\u{0301}"], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 1, "e + combining acute is one cell")
        XCTAssertEqual(cells.first, "e\u{0301}")
    }

    // MARK: A narrow predecessor that widens on merge

    /// When a lone indicator is narrow -- which it is whenever iTermIsFlagCharacter says no,
    /// i.e. fullWidthFlags off or Unicode 8 -- the predecessor cell has no DWC_RIGHT after it
    /// on the grid yet. Completing the flag widens that cell to two columns, so its second
    /// cell still has to be written. Under the default settings a lone indicator is already
    /// double-width, which masks the case.
    private func assertSplitFlagIsTwoColumns(file: StaticString = #filePath, line: UInt = #line) {
        let screen = makeScreen()
        append([flagU, flagS], to: screen)
        let (cursorX, cells) = row0(screen)
        XCTAssertEqual(cursorX, 2, "a flag is two columns even when the first half landed narrow",
                       file: file, line: line)
        XCTAssertEqual(cells.first, flagU + flagS, file: file, line: line)
        XCTAssertTrue(isDWCRight(screen, 1),
                      "the flag's right half must be a DWC_RIGHT", file: file, line: line)
    }

    func testSplitFlagWithFullWidthFlagsOff() {
        setFullWidthFlags(false)
        assertSplitFlagIsTwoColumns()
    }

    func testSplitFlagWithUnicode8() {
        setFullWidthFlags(true)
        unicodeVersion = 8
        assertSplitFlagIsTwoColumns()
    }

    func testSplitFlagWithBothGatesOff() {
        setFullWidthFlags(false)
        unicodeVersion = 8
        assertSplitFlagIsTwoColumns()
    }

    /// The same shape without any regional indicators, and the reason the fixed predicate
    /// matters beyond flags: a base that widens when the next write merges into it.
    ///
    /// This deliberately asserts nothing about how wide a VS16 sequence ought to be -- that
    /// is a policy question owned by the vs16Supported settings. It asserts only that the
    /// write boundary does not change the answer. Whatever width the one-write case
    /// produces, the two-write case must produce the same grid; before the fix the split
    /// case lost the second cell and left the cursor inside the character.
    func testWriteBoundaryDoesNotChangeResultForVS16() {
        let oneWrite = makeScreen()
        append(["\u{2764}\u{FE0F}"], to: oneWrite)
        let expected = row0(oneWrite)

        let twoWrites = makeScreen()
        append(["\u{2764}", "\u{FE0F}"], to: twoWrites)
        let actual = row0(twoWrites)

        XCTAssertEqual(actual.cursorX, expected.cursorX,
                       "a VS16 arriving in its own write must not change the cursor position")
        XCTAssertEqual(actual.cells, expected.cells)
        for x in 0..<expected.cursorX {
            XCTAssertEqual(isDWCRight(twoWrites, x), isDWCRight(oneWrite, x),
                           "cell \(x) spacer state must match the one-write case")
        }
    }

    // MARK: Predecessors that absorb more than a space does

    /// The prepended space is only a faithful stand-in for the predecessor when it absorbs
    /// the same prefix of the write. UAX #29 has three rules where a real predecessor
    /// absorbs more than a space: GB11 (emoji ZWJ sequences), GB6-GB8 (conjoining Hangul
    /// jamo) and GB12/GB13 (regional indicators). In each case the extra cluster stays in
    /// the preconverted buffer and gets written a second time after already being merged
    /// into the predecessor cell.

    /// Man, then ZWJ + woman + ZWJ + girl. Six UTF-16 units, so the tail is preconverted.
    func testZWJSequenceSplitAcrossWrites() {
        let oneWrite = makeScreen()
        append(["\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"], to: oneWrite)
        let expected = row0(oneWrite)

        let twoWrites = makeScreen()
        append(["\u{1F468}"], to: twoWrites)
        append(["\u{200D}\u{1F469}\u{200D}\u{1F467}"], to: twoWrites)
        let actual = row0(twoWrites)

        XCTAssertEqual(actual.cursorX, expected.cursorX,
                       "a ZWJ tail must merge into the predecessor, not be written twice")
        XCTAssertEqual(actual.cells, expected.cells)
    }

    /// Conjoining Hangul jamo: L, then V + T with a tail long enough to be preconverted.
    /// generate_nscharacterset.py deliberately excludes conjoining jamo from the own-cell
    /// set so these stay one cluster, which makes this a supported path.
    func testConjoiningJamoSplitAcrossWrites() {
        let oneWrite = makeScreen()
        append(["\u{1100}\u{1161}\u{11A8}ééé"], to: oneWrite)
        let expected = row0(oneWrite)

        let twoWrites = makeScreen()
        append(["\u{1100}"], to: twoWrites)
        append(["\u{1161}\u{11A8}ééé"], to: twoWrites)
        let actual = row0(twoWrites)

        XCTAssertEqual(actual.cursorX, expected.cursorX,
                       "a jamo tail must merge into the predecessor, not be written twice")
        XCTAssertEqual(actual.cells, expected.cells)
    }

    // MARK: Wrap boundary

    /// -coordinateBefore:movedBackOverDoubleWidth: returns the last cell of the *previous*
    /// line when the cursor is at column 0 after a soft wrap. Writing the predecessor's new
    /// right half there would put a DWC_RIGHT at column 0 whose left half is on the line
    /// above, which is not a representable grid state: iTerm2 uses DWC_SKIP + EOL_DWC when a
    /// double-width character does not fit. Anything that walks back over a DWC_RIGHT
    /// (selection, coordinateBefore:, reflow) would then see a spacer with no owner.
    private func assertNoOrphanedSpacer(_ screen: VT100Screen,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) {
        var height = 0
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            height = Int(mutableState.currentGrid.size.height)
        })
        for y in 0..<height {
            var isSpacer = false
            screen.performBlock(joinedThreads: { _, mutableState, _ in
                let c = mutableState.currentGrid.character(at: VT100GridCoord(x: 0, y: Int32(y)))
                isSpacer = ScreenCharIsDWC_RIGHT(c)
            })
            XCTAssertFalse(isSpacer,
                           "row \(y) column 0 is a DWC_RIGHT with no left half",
                           file: file, line: line)
        }
    }

    /// A compact description of the right margin and the line below it: enough to tell
    /// DWC_SKIP + EOL_DWC + wrapped character apart from a character left narrow in the
    /// last column.
    private func marginState(_ screen: VT100Screen) -> String {
        var out = ""
        screen.performBlock(joinedThreads: { _, ms, _ in
            let g = ms.currentGrid
            let w = Int(g.size.width)
            func describe(_ x: Int, _ y: Int) -> String {
                guard let line = g.screenChars(atLineNumber: Int32(y)) else { return "?" }
                let c = line[x]
                if ScreenCharIsDWC_SKIP(c) { return "SKIP" }
                if ScreenCharIsDWC_RIGHT(c) { return "DWCR" }
                let str = g.stringOrKittyPlaceholderStringForCharacter(at: VT100GridCoord(x: Int32(x), y: Int32(y))) ?? ""
                return "'\(str)'"
            }
            let eol = g.screenChars(atLineNumber: 0)?[w].code ?? 0
            out = "cursor=(\(g.cursorX),\(g.cursorY)) y0[\(w - 1)]=\(describe(w - 1, 0)) eol=\(eol) y1[0]=\(describe(0, 1)) y1[1]=\(describe(1, 1))"
        })
        return out
    }

    /// Before flags became one cluster they were two independent cells, so a flag at the
    /// right margin split across the wrap and each half rendered its lone-indicator
    /// fallback on a different row. Now it is a single double-width character, so it moves
    /// to the next line intact the way any wide character does.
    func testFlagAtMarginWrapsAsAUnit() {
        let screen = makeScreen()
        append([String(repeating: "a", count: 19) + flagU + flagS], to: screen)
        var cursor = (0, 0)
        var lastCellIsSkip = false
        var eol: unichar = 0
        var wrapped: String? = nil
        var spacerFollows = false
        screen.performBlock(joinedThreads: { _, ms, _ in
            let g = ms.currentGrid
            let w = Int(g.size.width)
            cursor = (Int(g.cursorX), Int(g.cursorY))
            lastCellIsSkip = ScreenCharIsDWC_SKIP(g.character(at: VT100GridCoord(x: Int32(w - 1), y: 0)))
            eol = g.screenChars(atLineNumber: 0)?[w].code ?? 0
            wrapped = g.stringOrKittyPlaceholderStringForCharacter(at: VT100GridCoord(x: 0, y: 1))
            spacerFollows = ScreenCharIsDWC_RIGHT(g.character(at: VT100GridCoord(x: 1, y: 1)))
        })
        XCTAssertTrue(lastCellIsSkip, "the last column holds a DWC_SKIP")
        XCTAssertEqual(eol, unichar(EOL_DWC), "the line is marked EOL_DWC")
        XCTAssertEqual(wrapped, flagU + flagS, "the whole flag moved to the next line")
        XCTAssertTrue(spacerFollows, "and it is still double-width there")
        XCTAssertEqual(cursor.0, 2)
        XCTAssertEqual(cursor.1, 1)
    }

    /// A character that widens by absorbing a later write, when it sits in the last column,
    /// must wrap onto the next line exactly as it would have if both halves had arrived in
    /// one write: DWC_SKIP in the last column, EOL_DWC on that line, and the two-cell
    /// character at the start of the next line.
    func testWidenedPredecessorAtMarginWrapsLikeOneWrite() {
        let oneWrite = makeScreen()
        append([String(repeating: "a", count: 19) + "\u{2764}\u{FE0F}"], to: oneWrite)
        let expected = marginState(oneWrite)

        let twoWrites = makeScreen()
        append([String(repeating: "a", count: 19)], to: twoWrites)
        append(["\u{2764}"], to: twoWrites)
        append(["\u{FE0F}"], to: twoWrites)
        XCTAssertEqual(marginState(twoWrites), expected)
    }

    /// The same for a flag whose first indicator landed narrow in the last column.
    func testSplitFlagAtMarginWrapsLikeOneWrite() {
        setFullWidthFlags(false)
        let oneWrite = makeScreen()
        append([String(repeating: "a", count: 19) + flagU + flagS], to: oneWrite)
        let expected = marginState(oneWrite)

        let twoWrites = makeScreen()
        append([String(repeating: "a", count: 19)], to: twoWrites)
        append([flagU], to: twoWrites)
        append([flagS], to: twoWrites)
        XCTAssertEqual(marginState(twoWrites), expected)
    }

    func testWidenedPredecessorAtWrapBoundaryLeavesNoOrphan() {
        let screen = makeScreen()
        append([String(repeating: "a", count: 19)], to: screen)
        append(["\u{2764}"], to: screen)
        append(["\u{FE0F}"], to: screen)
        assertNoOrphanedSpacer(screen)
    }

    func testSplitFlagAtWrapBoundaryLeavesNoOrphan() {
        setFullWidthFlags(false)
        let screen = makeScreen()
        append([String(repeating: "a", count: 19)], to: screen)
        append([flagU], to: screen)
        append([flagS], to: screen)
        assertNoOrphanedSpacer(screen)
    }

    /// Text written after the wrap boundary must not land on top of an orphaned spacer.
    func testWritingAfterWrapBoundaryMerge() {
        let screen = makeScreen()
        append([String(repeating: "a", count: 19)], to: screen)
        append(["\u{2764}"], to: screen)
        append(["\u{FE0F}"], to: screen)
        append(["XY"], to: screen)
        assertNoOrphanedSpacer(screen)
    }

    /// The rewind at the margin re-emits the merged character from a buffer built with the
    /// SGR state of the second write. It must keep the predecessor's own rendition, the way
    /// the in-place merge does, or a character whose halves arrive under different colors
    /// silently takes the later one.
    func testRewindAtMarginKeepsPredecessorRendition() {
        let screen = makeScreen()
        append([String(repeating: "a", count: 19)], to: screen)
        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.terminal?.setForegroundColor(1 /* red */, alternateSemantics: false)
        })
        append(["\u{2764}"], to: screen)
        let heartFg: UInt32 = {
            var v: UInt32 = 0
            screen.performBlock(joinedThreads: { _, ms, _ in
                v = ms.currentGrid.character(at: VT100GridCoord(x: 19, y: 0)).foregroundColor
            })
            return v
        }()
        XCTAssertEqual(heartFg, 1, "sanity: the heart was written in red")

        screen.performBlock(joinedThreads: { _, ms, _ in
            ms.terminal?.setForegroundColor(2 /* green */, alternateSemantics: false)
        })
        append(["\u{FE0F}"], to: screen)

        var wrapped = screen_char_t()
        var spacer = screen_char_t()
        screen.performBlock(joinedThreads: { _, ms, _ in
            wrapped = ms.currentGrid.character(at: VT100GridCoord(x: 0, y: 1))
            spacer = ms.currentGrid.character(at: VT100GridCoord(x: 1, y: 1))
        })
        XCTAssertEqual(wrapped.foregroundColor, 1,
                       "the merged character keeps the rendition it was written under")
        XCTAssertEqual(spacer.foregroundColor, 1, "its spacer matches")
    }

    // MARK: The preconverted fast path

    /// The equivalence above only exercised the slow path: its second write was one UTF-16
    /// unit, below kMinPreconvertStringLength. A tail of non-ASCII text keeps the write in
    /// one VT100_STRING token and pushes it over the threshold, so it is preconverted and
    /// the fast path's own predecessor fixup runs.
    func testWriteBoundaryDoesNotChangeResultForPreconvertedTail() {
        let oneWrite = makeScreen()
        append(["\u{2764}\u{FE0F}ééé"], to: oneWrite)
        let expected = row0(oneWrite)

        let twoWrites = makeScreen()
        append(["\u{2764}", "\u{FE0F}ééé"], to: twoWrites)
        let actual = row0(twoWrites)

        XCTAssertEqual(actual.cursorX, expected.cursorX,
                       "the preconverted fast path must not lose the widened cell")
        XCTAssertEqual(actual.cells, expected.cells)
    }

    func testWriteBoundaryDoesNotChangeResultForPreconvertedFlagTail() {
        setFullWidthFlags(false)
        let oneWrite = makeScreen()
        append([flagU + flagS + "ééé"], to: oneWrite)
        let expected = row0(oneWrite)

        let twoWrites = makeScreen()
        append([flagU, flagS + "ééé"], to: twoWrites)
        let actual = row0(twoWrites)

        XCTAssertEqual(actual.cursorX, expected.cursorX)
        XCTAssertEqual(actual.cells, expected.cells)
    }

    /// The same equivalence for a flag, across every combination of the width gates.
    func testWriteBoundaryDoesNotChangeResultForFlag() {
        for (flags, version) in [(true, 9), (false, 9), (true, 8), (false, 8)] {
            setFullWidthFlags(flags)
            unicodeVersion = version

            let oneWrite = makeScreen()
            append([flagU + flagS], to: oneWrite)
            let expected = row0(oneWrite)

            let twoWrites = makeScreen()
            append([flagU, flagS], to: twoWrites)
            let actual = row0(twoWrites)

            XCTAssertEqual(actual.cursorX, expected.cursorX,
                           "fullWidthFlags=\(flags) unicodeVersion=\(version)")
            XCTAssertEqual(actual.cells, expected.cells,
                           "fullWidthFlags=\(flags) unicodeVersion=\(version)")
        }
    }
}
