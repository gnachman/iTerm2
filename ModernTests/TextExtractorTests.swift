//
//  TextExtractorTests.swift
//  ModernTests
//
//  Ported from iTermTextExtractorTest.m. Word selection through the preferences-driven entry
//  point, smart selection over double-width characters, whitespace trimming, capped content
//  extraction, tab fillers, wrapped-line ranges, the sorted-array search helper and the
//  first-line whitespace check. Word extraction with explicit parameters is covered by
//  iTermWordExtractorTest.swift and excluded subranges by iTermTextExtractorExcludedSubrangeTests.
//

import XCTest
@testable import iTerm2SharedARC

private let kTestUnicodeVersion = 9

// Runs `string` through StringToScreenChars and returns exactly the cells it produced (no
// continuation cell).
private func screenChars(for string: String) -> [screen_char_t] {
    let capacity = max((string as NSString).length * 2 + 2, 4)
    var buffer = [screen_char_t](repeating: screen_char_t(), count: capacity)
    var length = Int32(0)
    let fg = screen_char_t()
    let bg = screen_char_t()
    buffer.withUnsafeMutableBufferPointer { bufferPointer in
        StringToScreenChars(string,
                            bufferPointer.baseAddress,
                            fg,
                            bg,
                            &length,
                            false,
                            nil,
                            nil,
                            .none,
                            kTestUnicodeVersion,
                            false,
                            nil)
    }
    return Array(buffer.prefix(Int(length)))
}

private func cellString(_ cell: screen_char_t) -> String {
    var copy = cell
    return ScreenCharToStr(&copy) ?? ""
}

// A data source whose lines are fixed arrays of cells. Every line holds width + 1 cells; the last
// one is the continuation marker. The ScreenCharArrays are built once and kept alive for the life
// of the data source because the extractor caches the raw line pointer between calls.
private final class FakeTextDataSource: NSObject, iTermTextDataSource {
    private let lines: [[screen_char_t]]
    private let screenCharArrays: [ScreenCharArray]
    private let gridWidth: Int32
    private let gridHeight: Int32

    // `cellLines` must each contain exactly `width` + 1 cells. `height` is the number of rows of
    // the visible grid.
    init(cellLines: [[screen_char_t]], width: Int, height: Int = 24) {
        for line in cellLines {
            it_assert(line.count == width + 1, "Line has \(line.count) cells but width is \(width)")
        }
        lines = cellLines
        gridWidth = Int32(width)
        gridHeight = Int32(height)
        screenCharArrays = cellLines.map { cells in
            cells.withUnsafeBufferPointer { pointer in
                ScreenCharArray(copyOfLine: pointer.baseAddress!,
                                length: Int32(width),
                                continuation: cells[width])
            }
        }
        super.init()
    }

    // Like the legacy test, the grid is as wide as the first line and every line ends with a soft
    // continuation.
    convenience init(strings: [String]) {
        let cellLines = strings.map { screenChars(for: $0) }
        let width = cellLines.first?.count ?? 0
        self.init(cellLines: cellLines.map { FakeTextDataSource.padded($0, width: width, eol: EOL_SOFT) },
                  width: width)
    }

    static func padded(_ cells: [screen_char_t], width: Int, eol: Int32) -> [screen_char_t] {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: width + 1)
        for (i, cell) in cells.prefix(width).enumerated() {
            buffer[i] = cell
        }
        buffer[width].code = unichar(eol)
        return buffer
    }

    func cells(atLine line: Int) -> [screen_char_t] {
        return lines[line]
    }

    // MARK: - iTermTextDataSource

    func width() -> Int32 {
        return gridWidth
    }

    func height() -> Int32 {
        return gridHeight
    }

    func numberOfLines() -> Int32 {
        return Int32(lines.count)
    }

    func totalScrollbackOverflow() -> Int64 {
        return 0
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        guard line >= 0, Int(line) < screenCharArrays.count else {
            return ScreenCharArray.emptyLine(ofLength: gridWidth)
        }
        return screenCharArrays[Int(line)]
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        return screenCharArray(forLine: index)
    }

    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? {
        return nil
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        return block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? {
        return Date()
    }

    func commandMark(at coord: VT100GridCoord,
                     mustHaveCommand: Bool,
                     range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? {
        return nil
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        return iTermImmutableMetadataDefault()
    }

    func isFirstLine(ofBlock lineNumber: Int32) -> Bool {
        return false
    }
}

final class TextExtractorTests: XCTestCase {
    private var savedWordCharacters: Any?
    private var savedWordMode: Any?
    private var savedWordRegex: Any?
    private var wrappedLines: [[screen_char_t]] = []
    // The extractor only holds its data source weakly, so every data source handed to an extractor
    // is kept here until the test ends.
    private var retainedDataSources: [FakeTextDataSource] = []

    override func setUp() {
        super.setUp()
        let defaults = iTermUserDefaults.userDefaults()
        savedWordCharacters = defaults.object(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection)
        savedWordMode = defaults.object(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode)
        savedWordRegex = defaults.object(forKey: kPreferenceKeyWordSelectionRegexPattern)
        wrappedLines = []
        retainedDataSources = []
    }

    override func tearDown() {
        iTermPreferences.setObject(savedWordCharacters, forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection)
        iTermPreferences.setObject(savedWordMode, forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode)
        iTermPreferences.setObject(savedWordRegex, forKey: kPreferenceKeyWordSelectionRegexPattern)
        retainedDataSources = []
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeExtractor(for dataSource: FakeTextDataSource) -> iTermTextExtractor {
        retainedDataSources.append(dataSource)
        return iTermTextExtractor(dataSource: dataSource)
    }

    private func makeExtractor(strings: [String]) -> iTermTextExtractor {
        return makeExtractor(for: FakeTextDataSource(strings: strings))
    }

    private func pinWordCharacters(_ characters: String) {
        iTermPreferences.setString(characters, forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection)
        iTermPreferences.setUnsignedInteger(iTermSelectionWordMode.characterList.rawValue,
                                            forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode)
    }

    private func string(for range: VT100GridWindowedRange, in dataSource: FakeTextDataSource) -> String {
        var result = ""
        let width = Int(dataSource.width())
        var x = Int(range.coordRange.start.x)
        var y = Int(range.coordRange.start.y)
        while y <= Int(range.coordRange.end.y) {
            let cells = dataSource.cells(atLine: y)
            let xLimit = (y == Int(range.coordRange.end.y)) ? Int(range.coordRange.end.x) : width
            while x < xLimit {
                let cell = cells[x]
                if cell.code != unichar(DWC_RIGHT) && cell.code != unichar(DWC_SKIP) {
                    result += cellString(cell)
                }
                x += 1
            }
            y += 1
        }
        return result
    }

    // Double-clicks each cell of `line` in turn and checks the selected word. `expected` has one
    // entry per cell.
    private func checkWordSelection(line: String,
                                    wordForEachCell expected: [String],
                                    extraWordCharacters: String,
                                    file: StaticString = #filePath,
                                    fileLine: UInt = #line) {
        pinWordCharacters(extraWordCharacters)
        let dataSource = FakeTextDataSource(strings: [line])
        XCTAssertEqual(Int(dataSource.width()), expected.count, "Expected one word per cell", file: file, line: fileLine)
        let extractor = makeExtractor(for: dataSource)
        for (i, expectedWord) in expected.enumerated() {
            let range = extractor.rangeForWord(at: VT100GridCoord(x: Int32(i), y: 0),
                                               maximumLength: kReasonableMaximumWordLength)
            let actual = string(for: range, in: dataSource)
            XCTAssertEqual(actual,
                           expectedWord,
                           "For click at \(i) got a range of \(VT100GridWindowedRangeDescription(range)) giving “\(actual)”, while I expected “\(expectedWord)”",
                           file: file,
                           line: fileLine)
        }
    }

    private func content(of extractor: iTermTextExtractor,
                         range: VT100GridWindowedRange,
                         nullPolicy: iTermTextExtractorNullPolicy,
                         cappedAtSize: Int32,
                         truncateTail: Bool,
                         coords: GridCoordArray? = nil) -> String? {
        return extractor.content(in: range,
                                 attributeProvider: nil,
                                 nullPolicy: nullPolicy,
                                 pad: false,
                                 includeLastNewline: false,
                                 trimTrailingWhitespace: false,
                                 cappedAtSize: cappedAtSize,
                                 truncateTail: truncateTail,
                                 continuationChars: nil,
                                 coords: coords,
                                 deduplicateDECDHL: false) as? String
    }

    // Lines of "abc", then "***" repeated until at least `starLength` characters, then "xyz".
    private func starsDataSource(starLength: Int) -> FakeTextDataSource {
        var strings = ["abc"]
        var length = 0
        while length < starLength {
            strings.append("***")
            length += 3
        }
        strings.append("xyz")
        return FakeTextDataSource(strings: strings)
    }

    private func wholeRange(of dataSource: FakeTextDataSource, endX: Int32 = 3) -> VT100GridWindowedRange {
        return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, endX, dataSource.numberOfLines()), 0, 0)
    }

    private func appendWrappedLine(_ line: String, width: Int, eol: Int32) {
        wrappedLines.append(FakeTextDataSource.padded(screenChars(for: line), width: width, eol: eol))
    }

    private func wrappedDataSource(width: Int, height: Int = 24) -> FakeTextDataSource {
        return FakeTextDataSource(cellLines: wrappedLines, width: width, height: height)
    }

    private func assertRange(_ actual: VT100GridAbsCoordRange,
                             equals expected: VT100GridAbsCoordRange,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertEqual(actual.start.x, expected.start.x, "start.x", file: file, line: line)
        XCTAssertEqual(actual.start.y, expected.start.y, "start.y", file: file, line: line)
        XCTAssertEqual(actual.end.x, expected.end.x, "end.x", file: file, line: line)
        XCTAssertEqual(actual.end.y, expected.end.y, "end.y", file: file, line: line)
    }

    private func assertCoordRange(_ actual: VT100GridCoordRange,
                                  startX: Int32, startY: Int32, endX: Int32, endY: Int32,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        XCTAssertEqual(actual.start.x, startX, "start.x", file: file, line: line)
        XCTAssertEqual(actual.start.y, startY, "start.y", file: file, line: line)
        XCTAssertEqual(actual.end.x, endX, "end.x", file: file, line: line)
        XCTAssertEqual(actual.end.y, endY, "end.y", file: file, line: line)
    }

    // MARK: - Word selection through the preference

    func testASCIIWordSelection() {
        let line = "word 123   abc/def afl-cio !@-"
        let words = ["word", "word", "word", "word",
                     " ",
                     "123", "123", "123",
                     "   ", "   ", "   ",
                     "abc", "abc", "abc",
                     "/",
                     "def", "def", "def",
                     " ",
                     "afl-cio", "afl-cio", "afl-cio", "afl-cio", "afl-cio", "afl-cio", "afl-cio",
                     " ",
                     "!", "@", "-"]
        checkWordSelection(line: line, wordForEachCell: words, extraWordCharacters: "-")
    }

    func testChineseWordSelection() {
        let line = "翻真的翻"
        let words = ["翻",
                     "翻",  // double-width extension
                     "真的",
                     "真的",  // double-width extension
                     "真的",
                     "真的",  // double-width extension
                     "翻",
                     "翻"]  // double-width extension
        checkWordSelection(line: line, wordForEachCell: words, extraWordCharacters: "-")
    }

    func testChineseWithWhitelistedCharacters() {
        let line = "真的-真的"
        let words = Array(repeating: "真的-真的", count: 9)
        checkWordSelection(line: line, wordForEachCell: words, extraWordCharacters: "-")
    }

    // The legacy test expected 𦍌 and 次 to be separate words. Word selection now hands CJK runs to
    // ICU for segmentation, which keeps this (dictionary-unknown) pair together, so this checks
    // what must hold regardless of segmentation: a surrogate pair is never split and a
    // double-width placeholder cell selects the same word as the cell to its left.
    func testSurrogatePairWordSelection() {
        pinWordCharacters("-")
        let dataSource = FakeTextDataSource(strings: ["𦍌次"])
        XCTAssertEqual(dataSource.width(), 4)
        let extractor = makeExtractor(for: dataSource)
        var words: [String] = []
        for x in 0..<4 {
            let range = extractor.rangeForWord(at: VT100GridCoord(x: Int32(x), y: 0),
                                               maximumLength: kReasonableMaximumWordLength)
            let word = string(for: range, in: dataSource)
            XCTAssertTrue(word.hasPrefix("𦍌") || word == "次", "Click at \(x) gave “\(word)”")
            XCTAssertFalse(word.utf16.contains { UTF16.isLeadSurrogate($0) } && !word.contains("𦍌"),
                           "Click at \(x) split the surrogate pair: “\(word)”")
            words.append(word)
        }
        XCTAssertEqual(words[0], words[1], "DWC_RIGHT cell of 𦍌 should select the same word")
        XCTAssertEqual(words[2], words[3], "DWC_RIGHT cell of 次 should select the same word")
    }

    // MARK: - Smart selection

    func testSmartSelectionRulesPlistParseable() throws {
        let rules = try XCTUnwrap(SmartSelectionController.defaultRules())
        XCTAssertGreaterThan(rules.count, 0, "No default smart selection rules")
    }

    // Ensures double-width characters are handled properly.
    func testDoubleWidthCharacterSmartSelection() throws {
        let dataSource = FakeTextDataSource(strings: ["blah 页页的翻真的很不方便.txt blah"])
        let extractor = makeExtractor(for: dataSource)
        let rule: [String: Any] = [kRegexKey: "\\S+", kPrecisionKey: kVeryHighPrecision]

        // The header calls `range` unused, but the method still writes through it, so pass storage.
        var range = VT100GridWindowedRange()
        let match = try XCTUnwrap(extractor.smartSelection(at: VT100GridCoord(x: 10, y: 0),
                                                           withRules: [rule],
                                                           actionRequired: false,
                                                           range: &range,
                                                           ignoringNewlines: false))
        XCTAssertEqual(match.startX, 5)
        XCTAssertEqual(match.endX, 29)
        XCTAssertEqual(match.absStartY, 0)
        XCTAssertEqual(match.absEndY, 0)
    }

    // Smart selection rules can come from hand-edited, dynamic, or imported profiles. A rule with
    // no regex (or one that isn't a string) passed nil to RegexKitLite, which threw “The regular
    // expression argument is NULL.” Such rules must be skipped.
    func testSmartSelectionSkipsRuleWithoutRegex() throws {
        let dataSource = FakeTextDataSource(strings: ["blah foo bar"])
        let extractor = makeExtractor(for: dataSource)
        let rules: [[String: Any]] = [
            [kPrecisionKey: kVeryHighPrecision],
            [kRegexKey: 42, kPrecisionKey: kVeryHighPrecision],
            [kRegexKey: "f\\S+", kPrecisionKey: kVeryHighPrecision],
        ]
        var range = VT100GridWindowedRange()
        var match: SmartMatch?
        XCTAssertNoThrow(try ObjCTry {
            match = extractor.smartSelection(at: VT100GridCoord(x: 6, y: 0),
                                             withRules: rules,
                                             actionRequired: false,
                                             range: &range,
                                             ignoringNewlines: false)
        })
        XCTAssertEqual(match?.startX, 5)
        XCTAssertEqual(match?.endX, 8)
    }

    // The header declares the `range` out-parameter `_Nullable` and comments it as “unused”
    // (sources/ContentAnalysis/iTermTextExtractor.h, annotation added in f8b9ef965), but
    // -smartSelectionAt:withRules:actionRequired:range:ignoringNewlines: writes through it on every
    // path, so passing nil dereferences NULL. Every production caller passes a stack address, so the
    // wrong annotation is a latent hazard rather than a user-facing bug. These two tests pin down the
    // actual contract: `range` is populated even when no rule matches.
    func testSmartSelectionWithNoMatchingRuleFallsBackToWordRange() {
        pinWordCharacters("")
        let dataSource = FakeTextDataSource(strings: ["blah foo bar"])
        let extractor = makeExtractor(for: dataSource)

        var range = VT100GridWindowedRange()
        let match = extractor.smartSelection(at: VT100GridCoord(x: 6, y: 0),
                                             withRules: [],
                                             actionRequired: false,
                                             range: &range,
                                             ignoringNewlines: false)
        XCTAssertNil(match)
        XCTAssertEqual(string(for: range, in: dataSource), "foo")
    }

    func testSmartSelectionWithNoMatchingRuleAndActionRequiredReportsInvalidRange() {
        let dataSource = FakeTextDataSource(strings: ["blah foo bar"])
        let extractor = makeExtractor(for: dataSource)

        // Seed the range so the test can tell that the method wrote to it.
        var range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(1, 2, 3, 4), 5, 6)
        let match = extractor.smartSelection(at: VT100GridCoord(x: 6, y: 0),
                                             withRules: [],
                                             actionRequired: true,
                                             range: &range,
                                             ignoringNewlines: false)
        XCTAssertNil(match)
        XCTAssertEqual(range.coordRange.start.x, -1)
        XCTAssertEqual(range.coordRange.start.y, -1)
        XCTAssertEqual(range.coordRange.end.x, -1)
        XCTAssertEqual(range.coordRange.end.y, -1)
        XCTAssertEqual(range.columnWindow.location, -1)
        XCTAssertEqual(range.columnWindow.length, -1)
    }

    // MARK: - rangeByTrimmingWhitespaceFromRange

    func testRangeByTrimmingWhitespace_TrimBothEnds() {
        let extractor = makeExtractor(strings: ["  foo  "])
        let actual = extractor.rangeByTrimmingWhitespace(from: VT100GridAbsCoordRangeMake(0, 0, 7, 0))
        assertRange(actual, equals: VT100GridAbsCoordRangeMake(2, 0, 5, 0))
    }

    func testRangeByTrimmingWhitespace_TrimLeft() {
        let extractor = makeExtractor(strings: ["  foo"])
        let actual = extractor.rangeByTrimmingWhitespace(from: VT100GridAbsCoordRangeMake(0, 0, 5, 0))
        assertRange(actual, equals: VT100GridAbsCoordRangeMake(2, 0, 5, 0))
    }

    func testRangeByTrimmingWhitespace_TrimRight() {
        let extractor = makeExtractor(strings: ["foo  "])
        let actual = extractor.rangeByTrimmingWhitespace(from: VT100GridAbsCoordRangeMake(0, 0, 5, 0))
        assertRange(actual, equals: VT100GridAbsCoordRangeMake(0, 0, 3, 0))
    }

    func testRangeByTrimmingWhitespace_NothingToTrim() {
        let extractor = makeExtractor(strings: ["foo"])
        let actual = extractor.rangeByTrimmingWhitespace(from: VT100GridAbsCoordRangeMake(0, 0, 3, 0))
        assertRange(actual, equals: VT100GridAbsCoordRangeMake(0, 0, 3, 0))
    }

    func testRangeByTrimmingWhitespace_MultiLine() {
        let extractor = makeExtractor(strings: ["  fooba", "123456 ", "       "])
        let actual = extractor.rangeByTrimmingWhitespace(from: VT100GridAbsCoordRangeMake(0, 0, 7, 2))
        assertRange(actual, equals: VT100GridAbsCoordRangeMake(2, 0, 6, 1))
    }

    // MARK: - contentInRange

    func testContentInRange_TruncateHeadSearchingBackwards_Huge() {
        let dataSource = starsDataSource(starLength: 1024 * 200)
        let extractor = makeExtractor(for: dataSource)
        let coords = GridCoordArray()
        // Extract the whole range but keep only the last 3 bytes.
        let actual = content(of: extractor,
                             range: wholeRange(of: dataSource),
                             nullPolicy: .kiTermTextExtractorNullPolicyFromLastToEnd,
                             cappedAtSize: 3,
                             truncateTail: false,
                             coords: coords)
        XCTAssertEqual(actual, "xyz")
        XCTAssertEqual(coords.count, 3)
    }

    func testContentInRange_TruncateHeadSearchingBackwards_NotHuge() {
        let dataSource = starsDataSource(starLength: 5)
        let extractor = makeExtractor(for: dataSource)
        let coords = GridCoordArray()
        let actual = content(of: extractor,
                             range: wholeRange(of: dataSource),
                             nullPolicy: .kiTermTextExtractorNullPolicyFromLastToEnd,
                             cappedAtSize: 3,
                             truncateTail: false,
                             coords: coords)
        XCTAssertEqual(actual, "xyz")
        XCTAssertEqual(coords.count, 3)
    }

    func testContentInRange_TruncateHead() {
        let dataSource = starsDataSource(starLength: 1024 * 200)
        let extractor = makeExtractor(for: dataSource)
        let actual = content(of: extractor,
                             range: wholeRange(of: dataSource),
                             nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                             cappedAtSize: 3,
                             truncateTail: false)
        XCTAssertEqual(actual, "xyz")
    }

    func testContentInRange_TruncateTail() {
        let dataSource = starsDataSource(starLength: 1024 * 200)
        let extractor = makeExtractor(for: dataSource)
        let actual = content(of: extractor,
                             range: wholeRange(of: dataSource),
                             nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                             cappedAtSize: 3,
                             truncateTail: true)
        XCTAssertEqual(actual, "abc")
    }

    // Replaces the cells at `indexes` with tab fillers. StringToScreenChars strips private-range
    // codes, so the fillers have to be poked in afterwards.
    private func tabFillerDataSource(line: String, fillerIndexes: [Int]) -> FakeTextDataSource {
        var cells = screenChars(for: line)
        for index in fillerIndexes {
            cells[index].code = unichar(TAB_FILLER)
        }
        let width = cells.count
        return FakeTextDataSource(cellLines: [FakeTextDataSource.padded(cells, width: width, eol: EOL_SOFT)],
                                  width: width)
    }

    func testContentInRange_RemoveTabFillers() {
        let dataSource = tabFillerDataSource(line: "a\u{f001}\u{f001}\tb", fillerIndexes: [1, 2])
        let extractor = makeExtractor(for: dataSource)
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 5, 1), 0, 0)
        let actual = content(of: extractor,
                             range: range,
                             nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                             cappedAtSize: -1,
                             truncateTail: false)
        XCTAssertEqual(actual, "a\tb")
    }

    func testContentInRange_ConvertOrphanTabFillersToSpaces() {
        let dataSource = tabFillerDataSource(line: "ab\u{f001}\u{f001}c", fillerIndexes: [2, 3])
        let extractor = makeExtractor(for: dataSource)
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 5, 1), 0, 0)
        let actual = content(of: extractor,
                             range: range,
                             nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                             cappedAtSize: -1,
                             truncateTail: false)
        XCTAssertEqual(actual, "ab  c")
    }

    // MARK: - wrappedLocatedStringAt

    func testWrappedStringBeforeCoordHasOneCoordPerCharacter() {
        // cell        0     0     12345
        let dataSource = FakeTextDataSource(strings: ["\u{2716}\u{fe0e} https://example.com/"])
        let extractor = makeExtractor(for: dataSource)
        let prefix = extractor.wrappedLocatedString(at: VT100GridCoord(x: 5, y: 0),
                                                    forward: false,
                                                    respectHardNewlines: true,
                                                    maxChars: 4096,
                                                    continuationChars: NSMutableIndexSet(),
                                                    convertNullsToSpace: false)
        XCTAssertEqual(prefix.string, "\u{2716}\u{fe0e} htt")
        XCTAssertEqual(prefix.gridCoords.count, (prefix.string as NSString).length)
        let expectedX: [Int32] = [0, 0, 1, 2, 3, 4]
        for (i, x) in expectedX.enumerated() {
            let coord = prefix.gridCoords.coord(at: i)
            XCTAssertEqual(coord.x, x, "coord \(i)")
            XCTAssertEqual(coord.y, 0, "coord \(i)")
        }
    }

    // MARK: - rangeForWrappedLineEncompassing

    func testRangeForWrappedLine_MaxChars() {
        for i in 0..<10 {
            appendWrappedLine("1234567890", width: 10, eol: i < 9 ? EOL_SOFT : EOL_HARD)
        }
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 5),
                                                              respectContinuations: false,
                                                              maxChars: 20)
        assertCoordRange(range.coordRange, startX: 0, startY: 2, endX: 10, endY: 8)
    }

    func testRangeForWrappedLine_EOL_DWC() {
        appendWrappedLine("asdf", width: 30, eol: EOL_HARD)
        let dwcLine = "111111111111111111111111111中" + String(utf16CodeUnits: [unichar(DWC_RIGHT), unichar(DWC_SKIP)], count: 2)
        appendWrappedLine(dwcLine, width: 30, eol: EOL_DWC)
        appendWrappedLine("文", width: 30, eol: EOL_HARD)

        let extractor = makeExtractor(for: wrappedDataSource(width: 30))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 1),
                                                              respectContinuations: false,
                                                              maxChars: 1000)
        assertCoordRange(range.coordRange, startX: 0, startY: 1, endX: 30, endY: 2)
    }

    func testRangeForWrappedLine_EOL_SOFT() {
        appendWrappedLine("asdf", width: 30, eol: EOL_HARD)
        appendWrappedLine("111111111111111111111111111xyz", width: 30, eol: EOL_SOFT)
        appendWrappedLine("hello world", width: 30, eol: EOL_HARD)

        let extractor = makeExtractor(for: wrappedDataSource(width: 30))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 1),
                                                              respectContinuations: false,
                                                              maxChars: 1000)
        assertCoordRange(range.coordRange, startX: 0, startY: 1, endX: 30, endY: 2)
    }

    func testRangeForWrappedLine_EOL_HARD() {
        appendWrappedLine("asdf", width: 30, eol: EOL_HARD)
        appendWrappedLine("111111111111111111111111111xyz", width: 30, eol: EOL_HARD)
        appendWrappedLine("hello world", width: 30, eol: EOL_HARD)

        let extractor = makeExtractor(for: wrappedDataSource(width: 30))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 1),
                                                              respectContinuations: false,
                                                              maxChars: 1000)
        assertCoordRange(range.coordRange, startX: 0, startY: 1, endX: 30, endY: 1)
    }

    // A negative maxChars means no limit.
    func testRangeForWrappedLine_NegativeMaxCharsIsUnlimited() {
        for i in 0..<10 {
            appendWrappedLine("1234567890", width: 10, eol: i < 9 ? EOL_SOFT : EOL_HARD)
        }
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 5),
                                    respectContinuations: false,
                                    maxChars: -1)
        assertCoordRange(range.coordRange, startX: 0, startY: 0, endX: 10, endY: 9)
    }

    // INT_MAX is as large a limit as there is. Adding the width to it used to
    // overflow int, wrap negative, and stop at the row of the coordinate.
    // See docs/swift-migration/integer-findings.md section 4.9.
    func testRangeForWrappedLine_IntMaxMaxCharsIsUnlimited() {
        for i in 0..<10 {
            appendWrappedLine("1234567890", width: 10, eol: i < 9 ? EOL_SOFT : EOL_HARD)
        }
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 5),
                                    respectContinuations: false,
                                    maxChars: Int32.max)
        assertCoordRange(range.coordRange, startX: 0, startY: 0, endX: 10, endY: 9)
    }

    // A limit just below the overflow still adds the width without wrapping.
    func testRangeForWrappedLine_LargeMaxCharsIsUnlimited() {
        for i in 0..<10 {
            appendWrappedLine("1234567890", width: 10, eol: i < 9 ? EOL_SOFT : EOL_HARD)
        }
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        let range = extractor.range(forWrappedLineEncompassing: VT100GridCoord(x: 5, y: 5),
                                    respectContinuations: false,
                                    maxChars: Int32.max - 10)
        assertCoordRange(range.coordRange, startX: 0, startY: 0, endX: 10, endY: 9)
    }

    // MARK: - locatedStringForWrappedLineEncompassing

    // iTermTextExtractor adopts iTermWordExtractorDataSource in its class
    // extension, so Swift sees the conformance only at run time.
    private func wordDataSource(_ extractor: iTermTextExtractor) -> iTermWordExtractorDataSource {
        guard let dataSource = (extractor as AnyObject) as? iTermWordExtractorDataSource else {
            it_fatalError("iTermTextExtractor does not conform to iTermWordExtractorDataSource")
        }
        return dataSource
    }

    // The located string spans every row of a wrapped line shorter than the
    // bound, not only the row of the coordinate. It used to ask for maxChars
    // INT_MAX, which overflowed and gave one row.
    func testLocatedStringForWrappedLineSpansEveryRow() {
        appendWrappedLine("before", width: 10, eol: EOL_HARD)
        appendWrappedLine("abcdefghij", width: 10, eol: EOL_SOFT)
        appendWrappedLine("klmnopqrst", width: 10, eol: EOL_SOFT)
        appendWrappedLine("uvwxyz", width: 10, eol: EOL_HARD)
        appendWrappedLine("after", width: 10, eol: EOL_HARD)
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        var targetOffset = Int32(-1)
        let located = wordDataSource(extractor).locatedString(forWrappedLineEncompassing: VT100GridCoord(x: 3, y: 2),
                                              targetOffset: &targetOffset)
        XCTAssertEqual(located.string, "abcdefghijklmnopqrstuvwxyz")
        XCTAssertEqual(targetOffset, 13)
        XCTAssertEqual(located.gridCoords.count, 26)
        XCTAssertEqual(located.gridCoords.coord(at: 0).y, 1)
        XCTAssertEqual(located.gridCoords.coord(at: 25).y, 3)
    }

    func testLocatedStringForUnwrappedLineIsThatRow() {
        appendWrappedLine("before", width: 10, eol: EOL_HARD)
        appendWrappedLine("middle", width: 10, eol: EOL_HARD)
        appendWrappedLine("after", width: 10, eol: EOL_HARD)
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        var targetOffset = Int32(-1)
        let located = wordDataSource(extractor).locatedString(forWrappedLineEncompassing: VT100GridCoord(x: 2, y: 1),
                                              targetOffset: &targetOffset)
        XCTAssertEqual(located.string, "middle")
        XCTAssertEqual(targetOffset, 2)
    }

    // Word selection in regular expression mode matches against the located
    // string, so a click on the second row of a soft-wrapped line finds a
    // match that starts on the first.
    func testRegexWordSelectionCrossesSoftWrap() {
        appendWrappedLine("see http://ex", width: 13, eol: EOL_SOFT)
        appendWrappedLine("ample.com/x", width: 13, eol: EOL_HARD)
        let extractor = makeExtractor(for: wrappedDataSource(width: 13))
        let range = extractor.rangeForWord(at: VT100GridCoord(x: 2, y: 1),
                                           maximumLength: kReasonableMaximumWordLength,
                                           big: false,
                                           additionalWordCharacters: nil,
                                           regexPatterns: ["https?://[^ ]+"])
        // "http://example.com/x": from column 4 of row 0 to the end of "x" on row 1.
        assertCoordRange(range.coordRange, startX: 4, startY: 0, endX: 11, endY: 1)
    }

    // MARK: - Bound on the regex word path

    // A hard-wrapped "before" row, then `rows` rows of one soft-wrapped line with every cell
    // holding a letter, then a hard-wrapped "after" row. The wrapped line occupies rows 1 through
    // `rows`. The letter changes from row to row so that a misplaced window shows in the text.
    private func appendLongWrappedLine(rows: Int, width: Int) {
        appendWrappedLine("before", width: width, eol: EOL_HARD)
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        for i in 0..<rows {
            let row = String(repeating: letters[i % letters.count], count: width)
            appendWrappedLine(row, width: width, eol: i < rows - 1 ? EOL_SOFT : EOL_HARD)
        }
        appendWrappedLine("after", width: width, eol: EOL_HARD)
    }

    // Asserts that the located string for a click at `click` covers exactly the full rows
    // `firstRow` through `lastRow` and that the target offset points at the click.
    private func assertLocatedWindow(dataSource: FakeTextDataSource,
                                     click: VT100GridCoord,
                                     firstRow: Int32,
                                     lastRow: Int32,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        let width = dataSource.width()
        let extractor = makeExtractor(for: dataSource)
        var targetOffset = Int32(-1)
        let located = wordDataSource(extractor).locatedString(forWrappedLineEncompassing: click,
                                                              targetOffset: &targetOffset)
        let rows = lastRow - firstRow + 1
        XCTAssertEqual(located.length, Int(rows * width), "length", file: file, line: line)
        XCTAssertEqual(located.gridCoords.count, Int(rows * width), "coordinate count", file: file, line: line)
        guard located.gridCoords.count > 0 else {
            return
        }
        let first = located.gridCoords.coord(at: 0)
        let last = located.gridCoords.coord(at: located.gridCoords.count - 1)
        XCTAssertEqual(first.x, 0, "first x", file: file, line: line)
        XCTAssertEqual(first.y, firstRow, "first row", file: file, line: line)
        XCTAssertEqual(last.x, width - 1, "last x", file: file, line: line)
        XCTAssertEqual(last.y, lastRow, "last row", file: file, line: line)
        XCTAssertEqual(targetOffset, (click.y - firstRow) * width + click.x, "target offset", file: file, line: line)
    }

    // An 80x24 grid allows max(20, 2 * 24) = 48 rows: 23 before the clicked row and 24 after it.
    // The wrapped line is rows 1 through 500.
    func testLocatedStringForLongWrappedLineIsWindowAroundClickInMiddle() {
        appendLongWrappedLine(rows: 500, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 250),
                            firstRow: 227,
                            lastRow: 274)
    }

    // Near the start of the wrapped line there are only 2 rows before the click, so the rows
    // unused before it go after it: still 48 rows in all.
    func testLocatedStringForLongWrappedLineIsWindowAroundClickNearStart() {
        appendLongWrappedLine(rows: 500, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 3),
                            firstRow: 1,
                            lastRow: 48)
    }

    // Near the end of the wrapped line there are only 2 rows after the click, so the rows unused
    // after it go before it.
    func testLocatedStringForLongWrappedLineIsWindowAroundClickNearEnd() {
        appendLongWrappedLine(rows: 500, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 498),
                            firstRow: 453,
                            lastRow: 500)
    }

    // A screen 5 rows high still gets the minimum of 20 rows: 9 before the click and 10 after.
    func testLocatedStringForLongWrappedLineOnSmallScreenUsesMinimumBound() {
        appendLongWrappedLine(rows: 500, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 5),
                            click: VT100GridCoord(x: 7, y: 250),
                            firstRow: 241,
                            lastRow: 260)
    }

    // A wrapped line no longer than the bound is taken whole, as before.
    func testLocatedStringForWrappedLineShorterThanBoundIsWhole() {
        appendLongWrappedLine(rows: 48, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 20),
                            firstRow: 1,
                            lastRow: 48)
    }

    // One row more than the bound loses one row, from the side with more to spare.
    func testLocatedStringForWrappedLineOneRowOverBound() {
        appendLongWrappedLine(rows: 49, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 2),
                            firstRow: 1,
                            lastRow: 48)
    }

    // A match that would run past the window is cut at the window: every cell of the wrapped line
    // matches, and the selection is the 48 rows around the click.
    func testRegexWordSelectionIsCutAtWindow() {
        appendLongWrappedLine(rows: 500, width: 80)
        let extractor = makeExtractor(for: wrappedDataSource(width: 80, height: 24))
        let range = extractor.rangeForWord(at: VT100GridCoord(x: 7, y: 250),
                                           maximumLength: kLongMaximumWordLength,
                                           big: false,
                                           additionalWordCharacters: nil,
                                           regexPatterns: ["[a-z]+"])
        // The end is exclusive: the end of a full row is column 0 of the next one.
        assertCoordRange(range.coordRange, startX: 0, startY: 227, endX: 0, endY: 275)
    }

    // A click on the first row of a long wrapped line gets the row and the 47 after it.
    func testLocatedStringForLongWrappedLineClickOnFirstRow() {
        appendLongWrappedLine(rows: 500, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 1),
                            firstRow: 1,
                            lastRow: 48)
    }

    // A click on the last row of a long wrapped line gets the row and the 47 before it.
    func testLocatedStringForLongWrappedLineClickOnLastRow() {
        appendLongWrappedLine(rows: 500, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 500),
                            firstRow: 453,
                            lastRow: 500)
    }

    // A wrapped line of 47 rows, one fewer than the bound, is taken whole.
    func testLocatedStringForWrappedLineOneRowUnderBoundIsWhole() {
        appendLongWrappedLine(rows: 47, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 30),
                            firstRow: 1,
                            lastRow: 47)
    }

    // A line that does not wrap is just its row.
    func testLocatedStringForOneRowLineIsThatRow() {
        appendLongWrappedLine(rows: 1, width: 80)
        assertLocatedWindow(dataSource: wrappedDataSource(width: 80, height: 24),
                            click: VT100GridCoord(x: 7, y: 1),
                            firstRow: 1,
                            lastRow: 1)
    }

    // MARK: - Clicks on null cells in regular expression mode

    // Rows 0 to 2 are one soft-wrapped line whose last row is "end" followed by null cells;
    // row 3 is a separate line.
    private func appendWrappedLineEndingInNulls() {
        appendWrappedLine("foo barbaz", width: 10, eol: EOL_SOFT)
        appendWrappedLine("qux quuxab", width: 10, eol: EOL_SOFT)
        appendWrappedLine("end", width: 10, eol: EOL_HARD)
        appendWrappedLine("next", width: 10, eol: EOL_HARD)
    }

    private func useRegexWordMode(_ pattern: String) {
        iTermPreferences.setUnsignedInteger(iTermSelectionWordMode.regularExpression.rawValue,
                                            forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode)
        iTermPreferences.setString(pattern, forKey: kPreferenceKeyWordSelectionRegexPattern)
    }

    // A double-click on the null cells after "end" selects the run of nulls on the clicked row,
    // as it does in character mode, and not a word from a row above.
    func testRegexWordSelectionOnNullCellSelectsTheNullRun() {
        appendWrappedLineEndingInNulls()
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        let regexRange = extractor.rangeForWord(at: VT100GridCoord(x: 6, y: 2),
                                                maximumLength: kLongMaximumWordLength,
                                                big: false,
                                                additionalWordCharacters: nil,
                                                regexPatterns: ["[a-z]+"])
        let characterRange = extractor.rangeForWord(at: VT100GridCoord(x: 6, y: 2),
                                                    maximumLength: kLongMaximumWordLength,
                                                    big: false,
                                                    additionalWordCharacters: nil,
                                                    regexPatterns: nil)
        assertCoordRange(regexRange.coordRange,
                         startX: characterRange.coordRange.start.x,
                         startY: characterRange.coordRange.start.y,
                         endX: characterRange.coordRange.end.x,
                         endY: characterRange.coordRange.end.y)
        XCTAssertEqual(regexRange.coordRange.start.y, 2)
        XCTAssertEqual(regexRange.coordRange.start.x, 3)
    }

    // The preference-driven entry point, used by Look Up and Autocomplete, behaves the same: a
    // click on blank space never yields a word from another row.
    func testPreferenceRegexWordAtNullCellStaysOnClickedRow() {
        appendWrappedLineEndingInNulls()
        useRegexWordMode("[a-z]+")
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        for x in Int32(3)..<Int32(10) {
            let range = extractor.rangeForWord(at: VT100GridCoord(x: x, y: 2),
                                               maximumLength: kReasonableMaximumWordLength)
            XCTAssertEqual(range.coordRange.start.y, 2, "click at \(x): \(VT100GridWindowedRangeDescription(range))")
            XCTAssertEqual(range.coordRange.start.x, 3, "click at \(x): \(VT100GridWindowedRangeDescription(range))")
        }
    }

    // If the clicked cell is not in the located string, the target offset is the first
    // character of the clicked row, as it was when the located string held only that row.
    func testLocatedStringTargetForUnrecordedClickIsStartOfClickedRow() {
        appendWrappedLineEndingInNulls()
        let extractor = makeExtractor(for: wrappedDataSource(width: 10))
        var targetOffset = Int32(-1)
        let located = wordDataSource(extractor).locatedString(forWrappedLineEncompassing: VT100GridCoord(x: 6, y: 2),
                                                              targetOffset: &targetOffset)
        XCTAssertEqual(located.string, "foo barbazqux quuxabend")
        XCTAssertEqual(targetOffset, 20)
    }

    // MARK: - Copy-mode word movement in regular expression mode

    // Moves the copy-mode cursor one word in `direction` from `coord`, as iTermCopyModeState does.
    private func copyModeWordMove(from coord: VT100GridCoord,
                                  direction: PTYTextViewSelectionExtensionDirection,
                                  extractor: iTermTextExtractor,
                                  dataSource: FakeTextDataSource) -> VT100GridCoord {
        let helper = iTermLogicalMovementHelper(textExtractor: extractor,
                                                selection: iTermSelection(),
                                                cursorCoordinate: VT100GridAbsCoordMake(0, Int64(dataSource.numberOfLines() - 1)),
                                                width: dataSource.width(),
                                                numberOfLines: Int64(dataSource.numberOfLines()),
                                                totalScrollbackOverflow: 0)
        let trivial = VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRangeMake(coord.x, Int64(coord.y), coord.x, Int64(coord.y)), 0, 0)
        let range = helper.absRange(byExtending: trivial,
                                    endpoint: .start,
                                    direction: direction,
                                    extractor: extractor,
                                    unit: .word)
        return VT100GridCoordMake(range.coordRange.start.x, Int32(range.coordRange.start.y))
    }

    private func isBefore(_ a: VT100GridCoord, _ b: VT100GridCoord) -> Bool {
        return a.y < b.y || (a.y == b.y && a.x < b.x)
    }

    // Forward word movement makes progress on every step until it stops, and reaches the line
    // after the wrapped line. It used to cycle through the wrapped line forever.
    func testCopyModeForwardWordInRegexModeAlwaysAdvances() {
        appendWrappedLineEndingInNulls()
        useRegexWordMode("[a-z]+")
        let dataSource = wrappedDataSource(width: 10)
        let extractor = makeExtractor(for: dataSource)
        var coord = VT100GridCoordMake(0, 0)
        var visited: [String] = []
        let maximumSteps = 40
        for _ in 0..<maximumSteps {
            let next = copyModeWordMove(from: coord, direction: .right, extractor: extractor, dataSource: dataSource)
            if VT100GridCoordEquals(next, coord) {
                break
            }
            visited.append(VT100GridCoordDescription(next))
            XCTAssertTrue(isBefore(coord, next), "moved backward: \(visited.joined(separator: " "))")
            if !isBefore(coord, next) {
                return
            }
            coord = next
        }
        XCTAssertLessThan(visited.count, maximumSteps, "did not stop: \(visited.joined(separator: " "))")
        XCTAssertEqual(coord.y, 3, "path: \(visited.joined(separator: " "))")
    }

    // Backward word movement from the last line makes progress on every step and reaches the
    // start of the wrapped line.
    func testCopyModeBackwardWordInRegexModeAlwaysAdvances() {
        appendWrappedLineEndingInNulls()
        useRegexWordMode("[a-z]+")
        let dataSource = wrappedDataSource(width: 10)
        let extractor = makeExtractor(for: dataSource)
        var coord = VT100GridCoordMake(3, 3)
        var visited: [String] = []
        let maximumSteps = 40
        for _ in 0..<maximumSteps {
            let next = copyModeWordMove(from: coord, direction: .left, extractor: extractor, dataSource: dataSource)
            if VT100GridCoordEquals(next, coord) {
                break
            }
            visited.append(VT100GridCoordDescription(next))
            XCTAssertTrue(isBefore(next, coord), "moved forward: \(visited.joined(separator: " "))")
            if !isBefore(next, coord) {
                return
            }
            coord = next
        }
        XCTAssertLessThan(visited.count, maximumSteps, "did not stop: \(visited.joined(separator: " "))")
        XCTAssertEqual(coord.x, 0, "path: \(visited.joined(separator: " "))")
        XCTAssertEqual(coord.y, 0, "path: \(visited.joined(separator: " "))")
    }

    // The work done for one click is bounded by the window, not by the length of the wrapped
    // line: for a wrapped line of 5,000 rows the located string has at most 48 rows of text.
    func testLocatedStringForVeryLongWrappedLineIsBounded() {
        appendLongWrappedLine(rows: 5000, width: 80)
        let extractor = makeExtractor(for: wrappedDataSource(width: 80, height: 24))
        var targetOffset = Int32(-1)
        let located = wordDataSource(extractor).locatedString(forWrappedLineEncompassing: VT100GridCoord(x: 7, y: 2500),
                                                              targetOffset: &targetOffset)
        XCTAssertGreaterThan(located.length, 0)
        XCTAssertLessThanOrEqual(located.length, 48 * 80)
    }

    // MARK: - indexInSortedArray

    private var searchExtractor: iTermTextExtractor {
        return makeExtractor(strings: ["x"])
    }

    func testBinarySearch_ExactMatch() {
        let actual = searchExtractor.index(inSortedArray: [10, 20, 30], withValueLessThanOrEqualTo: 20, searchingBackwardFrom: 2)
        XCTAssertEqual(actual, 1)
    }

    func testBinarySearch_ExactMatchWithMultipleEqualValues() {
        let actual = searchExtractor.index(inSortedArray: [10, 20, 20, 30], withValueLessThanOrEqualTo: 20, searchingBackwardFrom: 3)
        XCTAssertEqual(actual, 2)
    }

    func testBinarySearch_BetweenValues() {
        let actual = searchExtractor.index(inSortedArray: [10, 20, 30], withValueLessThanOrEqualTo: 25, searchingBackwardFrom: 2)
        XCTAssertEqual(actual, 1)
    }

    func testBinarySearch_AtEnd() {
        let actual = searchExtractor.index(inSortedArray: [10, 20, 30], withValueLessThanOrEqualTo: 40, searchingBackwardFrom: 2)
        XCTAssertEqual(actual, 2)
    }

    func testBinarySearch_AtStart() {
        let actual = searchExtractor.index(inSortedArray: [10, 20, 30], withValueLessThanOrEqualTo: 5, searchingBackwardFrom: 2)
        XCTAssertEqual(actual, 0)
    }

    func testBinarySearch_RespectsStartLocation() {
        let actual = searchExtractor.index(inSortedArray: [10, 20, 30], withValueLessThanOrEqualTo: 40, searchingBackwardFrom: 1)
        XCTAssertEqual(actual, 1)
    }

    // MARK: - haveNonWhitespaceInFirstLineOfRange

    private func haveNonWhitespaceInFirstLine() -> Bool {
        let dataSource = wrappedDataSource(width: 30)
        let extractor = makeExtractor(for: dataSource)
        let range = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(0, 0, 0, dataSource.numberOfLines()), 0, 0)
        return extractor.haveNonWhitespace(inFirstLineOf: range)
    }

    func testHaveNonWhitespaceInFirstLineOfRange_OneLineOfWhitespace() {
        // U+2003 is an em space.
        appendWrappedLine("  \t \u{2003} ", width: 30, eol: EOL_HARD)
        XCTAssertFalse(haveNonWhitespaceInFirstLine())
    }

    func testHaveNonWhitespaceInFirstLineOfRange_NonWhitespaceOnSecondLine() {
        appendWrappedLine("  \t \u{2003} ", width: 30, eol: EOL_HARD)
        appendWrappedLine("x", width: 30, eol: EOL_HARD)
        XCTAssertFalse(haveNonWhitespaceInFirstLine())
    }

    func testHaveNonWhitespaceInFirstLineOfRange_NonWhitespaceOnFirstLine() {
        appendWrappedLine("  \tx \u{2003} ", width: 30, eol: EOL_HARD)
        appendWrappedLine("x", width: 30, eol: EOL_HARD)
        XCTAssertTrue(haveNonWhitespaceInFirstLine())
    }

    func testHaveNonWhitespaceInFirstLineOfRange_ComplexNonWhitespaceOnFirstLine() {
        appendWrappedLine("  \t😀 \u{2003} ", width: 30, eol: EOL_HARD)
        appendWrappedLine("x", width: 30, eol: EOL_HARD)
        XCTAssertTrue(haveNonWhitespaceInFirstLine())
    }
}
