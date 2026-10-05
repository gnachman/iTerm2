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

    // `cellLines` must each contain exactly `width` + 1 cells.
    init(cellLines: [[screen_char_t]], width: Int) {
        for line in cellLines {
            it_assert(line.count == width + 1, "Line has \(line.count) cells but width is \(width)")
        }
        lines = cellLines
        gridWidth = Int32(width)
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
    private var wrappedLines: [[screen_char_t]] = []
    // The extractor only holds its data source weakly, so every data source handed to an extractor
    // is kept here until the test ends.
    private var retainedDataSources: [FakeTextDataSource] = []

    override func setUp() {
        super.setUp()
        let defaults = iTermUserDefaults.userDefaults()
        savedWordCharacters = defaults.object(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection)
        savedWordMode = defaults.object(forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode)
        wrappedLines = []
        retainedDataSources = []
    }

    override func tearDown() {
        iTermPreferences.setObject(savedWordCharacters, forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelection)
        iTermPreferences.setObject(savedWordMode, forKey: kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode)
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

    private func wrappedDataSource(width: Int) -> FakeTextDataSource {
        return FakeTextDataSource(cellLines: wrappedLines, width: width)
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
