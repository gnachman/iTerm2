//
//  RangeArray.swift
//  iTerm2
//
//  Created by George Nachman on 10/29/24.
//
import CoreText

@objc(iTermRangeArray)
class RangeArray: NSObject {
    private let ranges: [Range<Int>]
    init(_ ranges: [Range<Int>]) {
        self.ranges = ranges
    }
    
    @objc
    var count: UInt {
        UInt(ranges.count)
    }
    
    @objc
    subscript(_ i: Int) -> NSRange {
        NSRange(ranges[i])
    }
}

extension CTRun {
    var glyphCount: Int {
        CTRunGetGlyphCount(self)
    }
    var wholeRange: CFRange {
        CFRange(location: 0, length: glyphCount)
    }

    var stringIndices: [CFIndex] {
        let count = glyphCount
        var values = Array<CFIndex>(repeating: 0, count: count)
        CTRunGetStringIndices(self, wholeRange, &values)
        return values
    }
    var positions: [CGPoint] {
        let count = glyphCount
        var values = Array<CGPoint>(repeating: .zero, count: count)
        CTRunGetPositions(self, wholeRange, &values)
        return values
    }
    var glyphs: [CGGlyph] {
        let count = glyphCount
        var values = Array<CGGlyph>(repeating: 0, count: count)
        CTRunGetGlyphs(self, wholeRange, &values)
        return values
    }
    // The font CoreText actually used for this run (post-substitution). Needed
    // to ask the font for a character's default (un-mirrored) glyph so we can
    // detect whether CoreText applied bidi mirroring (rule L4) to a glyph.
    var font: CTFont? {
        guard let attributes = CTRunGetAttributes(self) as? [String: Any],
              let font = attributes[kCTFontAttributeName as String] else {
            return nil
        }
        return (font as! CTFont)
    }
    var status: CTRunStatus {
        CTRunGetStatus(self)
    }
    var stringRange: Range<Int> {
        let cfrange = CTRunGetStringRange(self)
        return cfrange.location..<(cfrange.location + cfrange.length)
    }
}

extension ClosedRange where Bound == Int {
    init(_ cfrange: CFRange) {
        self = cfrange.location...(cfrange.location + cfrange.length)
    }
}

extension ClosedRange {
    mutating func formUnion(_ other: Self) {
        self = Swift.min(self.lowerBound, other.lowerBound)...Swift.max(self.upperBound, other.upperBound)
    }
}

struct CellPosition {
    var sourceCell: Int
    enum Position {
        case absolute(CGFloat)
        case leftOfPredecessor
        case rightOfPredecessor
    }
    var position: Position
}

struct ResolvedCellPosition: Comparable {
    var sourceCell: Int
    var base: CGFloat
    var infinitessimals: Int
    init(previous: ResolvedCellPosition?,
         current: CellPosition) {
        self.sourceCell = current.sourceCell
        if let previous {
            switch current.position {
            case .absolute(let value):
                self.base = value
                self.infinitessimals = 0
            case .leftOfPredecessor:
                self.base = previous.base
                self.infinitessimals = previous.infinitessimals - 1
            case .rightOfPredecessor:
                self.base = previous.base
                self.infinitessimals = previous.infinitessimals + 1
            }
        } else {
            switch current.position {
            case .absolute(let value):
                self.base = value
                self.infinitessimals = 0
            case .leftOfPredecessor:
                // The first character, which happens to be in a right-to-left run, was part of a
                // ligature it was not credited for. This must be the rightmost position.
                self.base = CGFloat.infinity
                self.infinitessimals = 0
            case .rightOfPredecessor:
                // The first character, which happens to be in a left-to-right run, was part of a
                // ligature it was not credited for. This must be the leftmost position.
                self.base = -CGFloat.infinity
                self.infinitessimals = 0
            }
        }
    }

    static func < (lhs: ResolvedCellPosition, rhs: ResolvedCellPosition) -> Bool {
        if lhs.base != rhs.base {
            return lhs.base < rhs.base
        } else {
            return lhs.infinitessimals < rhs.infinitessimals
        }
    }
}

fileprivate struct IntermediateLookupTable {
    var rtlIndexes = IndexSet()
    // Source cells whose character CoreText actually drew as its bidi-mirrored
    // counterpart (UBA rule L4). This is distinct from rtlIndexes: a bracket
    // that brackets an embedded left-to-right run is in an RTL run for
    // positioning yet must NOT be mirrored, and CoreText resolves that
    // correctly here. Driving mirroring off run direction instead reverses
    // brackets around English words inside Persian text.
    var mirroredIndexes = IndexSet()
    var sourceCellToPositionRange: Array<ClosedRange<CGFloat>?>
    var count: Int

    // `string` is what CoreText laid out (which may contain inserted isolate
    // controls when Latin runs are isolated). `cellForIndex` maps each UTF-16
    // index of `string` to a source cell, or -1 for an inserted control that
    // has no cell.
    init(line: CTLine, string: NSString, cellForIndex: [Int32], count: Int) {
        self.count = count
        // Guillemets keep their typed glyph instead of following bidi mirroring.
        // The Unicode algorithm mirrors « » (and ‹ ›) in a right-to-left run, so
        // «متن» renders »متن« with the marks pointing outward; CoreText and
        // TextEdit do this. Persian/Arabic readers expect the marks to hug the
        // text as typed («متن»), so we deliberately don't mirror them. Brackets
        // and parentheses still mirror, matching macOS. This is unconditional
        // (not tied to the Latin-islands setting); it only runs at all when
        // right-to-left support is enabled, so it's inert otherwise.
        func isGuillemet(_ c: unichar) -> Bool {
            return c == 0x00AB || c == 0x00BB || c == 0x2039 || c == 0x203A
        }
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        func cell(_ stringIndex: Int) -> Int {
            guard stringIndex >= 0 && stringIndex < cellForIndex.count else { return -1 }
            return Int(cellForIndex[stringIndex])
        }

        // Source cell to range of positions
        sourceCellToPositionRange = Array<ClosedRange<CGFloat>?>(repeating: nil, count: count)
        for run in runs {
            let isRTL = (run.status.contains(.rightToLeft))
            let stringIndices = run.stringIndices

            // Update rtlIndexes
            if isRTL {
                for stringIndex in run.stringRange {
                    let sourceCell = cell(stringIndex)
                    if sourceCell >= 0 { rtlIndexes.insert(sourceCell) }
                }
            }

            // Update sourceCellToPositionRange, and detect L4 mirroring.
            let positions = run.positions
            let glyphs = run.glyphs
            let font = run.font
            for i in 0..<run.glyphCount {
                let stringIndex = stringIndices[i]
                let sourceCell = cell(stringIndex)
                if sourceCell < 0 { continue }  // inserted isolate control: no cell
                // Only the cell's base character (its first UTF-16 unit) may
                // set the cell's position. A combining mark merged into a cell
                // is a zero-advance glyph positioned over its base's glyph, or
                // over a ligature that consumed the base, as in کاملاً where
                // the fathatan rides the lam-alef ligature. Crediting the
                // mark's x to the cell gave the alef's cell an absolute
                // position at/right of the ligature's origin, sorting it to the
                // wrong side of the lam. Ignored, the cell falls back to
                // leftOfPredecessor/rightOfPredecessor as ligature-consumed
                // cells are meant to.
                if stringIndex > 0 && cell(stringIndex - 1) == sourceCell { continue }
                if var existing = sourceCellToPositionRange[sourceCell] {
                    existing.formUnion(positions[i].x...positions[i].x)
                    sourceCellToPositionRange[sourceCell] = existing
                } else {
                    sourceCellToPositionRange[sourceCell] = positions[i].x...positions[i].x
                }

                // A character is mirrored iff it is bidi-mirrorable AND the
                // glyph CoreText chose differs from the font's default glyph
                // for that character. Comparing against the run's own font
                // (post-substitution) keeps the comparison valid.
                if let font,
                   stringIndex >= 0,
                   stringIndex < string.length {
                    let ch = string.character(at: stringIndex)
                    if iTermBidiMirroredCounterpart(ch) != ch {
                        var chars: [unichar] = [ch]
                        var defaultGlyphs = [CGGlyph](repeating: 0, count: 1)
                        CTFontGetGlyphsForCharacters(font, &chars, &defaultGlyphs, 1)
                        if glyphs[i] != defaultGlyphs[0] && !isGuillemet(ch) {
                            mirroredIndexes.insert(sourceCell)
                        }
                    }
                }
            }
        }
    }

    private var cellPositionsBySourceCell: [CellPosition] {
        return sourceCellToPositionRange.enumerated().map { (sourceCell: Int, positionRange: ClosedRange<CGFloat>?) -> CellPosition in
            if let positionRange {
                return CellPosition(sourceCell: sourceCell, position: .absolute(positionRange.lowerBound))
            } else {
                if rtlIndexes.contains(sourceCell) {
                    // This is a right-to-left character that contributed to a ligature. It should be placed left of the preceding character.
                    return CellPosition(sourceCell: sourceCell, position: .leftOfPredecessor)
                } else {
                    // This is a left-to-right character that contributed to a ligature. It should be placed right of the preceding character.
                    return CellPosition(sourceCell: sourceCell, position: .rightOfPredecessor)
                }
            }
        }
    }

    private var sortedResolvedCellPositions: [ResolvedCellPosition] {
        var resolvedCellPositions = [ResolvedCellPosition]()
        resolvedCellPositions.reserveCapacity(cellPositionsBySourceCell.count)
        for cellPosition in cellPositionsBySourceCell {
            resolvedCellPositions.append(ResolvedCellPosition(previous: resolvedCellPositions.last,
                                                              current: cellPosition))
        }
        return resolvedCellPositions.sorted()

    }

    var lut: [Int32] {
        var result = Array(Int32(0)..<Int32(count))
        for (visualIndex, resolvedCellPosition) in sortedResolvedCellPositions.enumerated() {
            result[Int(resolvedCellPosition.sourceCell)] = Int32(visualIndex)
        }
        return result
    }
}

// Wrap maximal runs of non-space ASCII text that contain a Latin letter in
// isolate controls (LRI…PDI) so CoreText lays them out as left-to-right
// islands: English words, file paths, and code keep their natural order and
// their surrounding brackets stay un-mirrored. Returns the isolated string and,
// per UTF-16 index of it, the source cell (-1 for an inserted control).
private let iTermLRI: unichar = 0x2066
private let iTermRLI: unichar = 0x2067
private let iTermFSI: unichar = 0x2068
private let iTermPDI: unichar = 0x2069

fileprivate func isolateLatinRuns(_ s: NSString, deltas: UnsafePointer<Int32>) -> (NSString, [Int32]) {
    // Accented Latin letters (Müggelsee, café, Tegernsee, …). Latin-1 Supplement
    // and Latin Extended-A letters, minus the two math signs × and ÷.
    func isLatinExtendedLetter(_ c: unichar) -> Bool {
        if c == 0xD7 || c == 0xF7 { return false }
        return (c >= 0xC0 && c <= 0xFF) || (c >= 0x100 && c <= 0x17F)
    }
    func isLetter(_ c: unichar) -> Bool {
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || isLatinExtendedLetter(c)
    }
    // Island content: printable ASCII (no space), plus accented Latin letters so
    // a word like "Müggelsee" is not split at the ü. Guillemets count as island
    // content so «machine learning» keeps its marks on their typed sides: left
    // outside the island the UBA places them by direction run and the pair
    // shows up swapped (»machine learning«). A guillemet with no adjacent
    // Latin letters forms no island (hasLetter stays false), so Persian
    // «سلام دنیا» is unaffected.
    func isGuillemet(_ c: unichar) -> Bool { c == 0xAB || c == 0xBB || c == 0x2039 || c == 0x203A }
    func isIsland(_ c: unichar) -> Bool { (c > 0x20 && c < 0x7F) || isLatinExtendedLetter(c) || isGuillemet(c) }
    func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }
    func isAlnum(_ c: unichar) -> Bool { isLetter(c) || isDigit(c) }
    func isOpeningBracket(_ c: unichar) -> Bool { c == 0x28 || c == 0x5B || c == 0x7B }
    func isClosingBracket(_ c: unichar) -> Bool { c == 0x29 || c == 0x5D || c == 0x7D }
    // Whether a Latin letter lies ahead in the upcoming island run, spanning
    // symbols like "=" and interior spaces, before any non-island (Persian)
    // character. Lets "(ZWNJ = U+200C)" stay one island instead of splitting at
    // the "=" (which is island content but not alphanumeric), which would leave
    // the two halves to reorder against each other in an RTL line.
    func latinLetterAhead(_ start: Int) -> Bool {
        var m = start
        while m < s.length {
            let cm = s.character(at: m)
            if isLetter(cm) { return true }
            if isIsland(cm) || cm == 0x20 { m += 1 } else { return false }
        }
        return false
    }
    let n = s.length
    var out = [unichar]()
    var map = [Int32]()
    out.reserveCapacity(n + 8)
    map.reserveCapacity(n + 8)
    var i = 0
    while i < n {
        let c = s.character(at: i)
        if isIsland(c) {
            // Extend across island characters, and across interior spaces that
            // have island content on the far side, so a multi-word phrase like
            // "Tempelhofer Feld" or "Google Chrome" stays a single island. A
            // trailing space before non-island (e.g. Persian) content ends it.
            var j = i
            var hasLetter = false
            while j < n {
                let cj = s.character(at: j)
                if isIsland(cj) {
                    if isLetter(cj) { hasLetter = true }
                    j += 1
                } else if cj == 0x20 {
                    // Span an interior space when more Latin content follows, so a
                    // multi-word phrase ("Google Chrome", "Windows 11", "Berlin
                    // (capital)") stays a single island. Look through an opening
                    // bracket to what it introduces: a bracket that opens Latin
                    // content belongs to the phrase, but one that opens the next
                    // Persian phrase (as in "School of Hip Hop (فصل …") is left
                    // outside the island so it mirrors normally.
                    var k = j
                    while k < n && s.character(at: k) == 0x20 { k += 1 }
                    var probe = k
                    if probe < n && isOpeningBracket(s.character(at: probe)) { probe += 1 }
                    // Span the space toward more Latin content: the next token is
                    // alphanumeric, OR a Latin letter still lies ahead past a
                    // symbol like "=" ("ZWNJ = U+200C"). A bracket that opens
                    // Persian ("School … (فصل") has no Latin letter ahead, so it
                    // still ends the island and mirrors normally.
                    if (probe < n && isAlnum(s.character(at: probe))) || latinLetterAhead(k) {
                        j = k  // interior space before more Latin content: keep going
                    } else {
                        break  // island ends here
                    }
                } else {
                    break
                }
            }
            // If the run starts with an opening bracket whose partner is not in
            // this island, its content turns Persian ("(ZWNJ حاضر است)"), leave
            // that bracket in the RTL run so the pair mirrors together, and begin
            // the island after it. An all-Latin bracket ("(Berlin capital)")
            // keeps its partner inside and is unaffected.
            var start = i
            if isOpeningBracket(s.character(at: i)) {
                var matched = false
                var m = i + 1
                while m < j { if isClosingBracket(s.character(at: m)) { matched = true; break }; m += 1 }
                if !matched {
                    out.append(s.character(at: i)); map.append(CellOffsetFromUTF16Offset(Int32(i), deltas))
                    start = i + 1
                }
            }
            if hasLetter {
                out.append(iTermLRI); map.append(-1)
                for k in start..<j { out.append(s.character(at: k)); map.append(CellOffsetFromUTF16Offset(Int32(k), deltas)) }
                out.append(iTermPDI); map.append(-1)
            } else {
                for k in start..<j { out.append(s.character(at: k)); map.append(CellOffsetFromUTF16Offset(Int32(k), deltas)) }
            }
            i = j
        } else {
            out.append(c); map.append(CellOffsetFromUTF16Offset(Int32(i), deltas))
            i += 1
        }
    }
    return (NSString(characters: out, length: out.count), map)
}

// Make a lookup table that maps source cell to display cell.
fileprivate func makeLookupTable(_ string: NSString,
                                 cellForIndex: [Int32],
                                 count: Int) -> ([Int32], IndexSet, IndexSet, Bool) {
    let paragraphIsRTL: Bool =
        iTermAdvancedSettingsModel.detectParagraphDirection() &&
        detectedParagraphIsRTL(string)
    // The CTLine must be laid out with the SAME base direction the line is
    // justified with. Leaving it to CoreText's own first-strong detection
    // diverges on a line that opens LTR but is majority-RTL (a shell prompt
    // with pasted Persian): the line right-justifies by our rule while the
    // neutrals inside resolve against an LTR base, so a sentence-final period
    // detaches from its sentence and lands across the gap by the prompt's
    // clock.
    let paragraphStyle = NSMutableParagraphStyle()
    if iTermAdvancedSettingsModel.detectParagraphDirection() {
        paragraphStyle.baseWritingDirection = paragraphIsRTL ? .rightToLeft : .leftToRight
    } else {
        paragraphStyle.baseWritingDirection = .leftToRight
    }
    let attributedString = NSAttributedString(string: string as String,
                                              attributes: [.paragraphStyle: paragraphStyle])
    // Create a CTLine from the attributed string
    let line = CTLineCreateWithAttributedString(attributedString)
    let intermediate = IntermediateLookupTable(line: line,
                                               string: string,
                                               cellForIndex: cellForIndex,
                                               count: count)

    return (intermediate.lut, intermediate.rtlIndexes, intermediate.mirroredIndexes, paragraphIsRTL)
}

// A line lays out right-to-left when its first strong character is RTL, OR
// when its strong RTL characters outnumber the strong LTR ones. Either signal
// alone misfires: first-strong lays out «Berlin شهری بزرگ در آلمان», a
// Persian sentence that happens to open with an English word, left-to-right,
// and majority alone flips a Persian-syntax line that quotes a lot of English
// («کلمهٔ conversion rate و growth plan در گزارش آمد.») to left-to-right.
// The union gets both right, and an English sentence containing one Persian
// word («The word سلام means hello in Persian.») stays left-to-right instead
// of being right-justified into an unreadable order. Isolate control
// characters are skipped; the characters inside isolates count normally.
fileprivate func detectedParagraphIsRTL(_ s: NSString) -> Bool {
    guard let ltr = NSCharacterSet.strongLTRCodePoints(),
          let rtl = NSCharacterSet.strongRTLCodePoints() else {
        return false
    }
    var firstStrongIsRTL: Bool? = nil
    var ltrCount = 0
    var rtlCount = 0
    // A "word" is a maximal group of strong-RTL characters; a space or a
    // strong-LTR character ends it, while neutrals and marks (ZWNJ inside
    // دانش‌آموزان, combining marks) do not, so such a word counts once.
    var rtlWordCount = 0
    var inRTLWord = false
    // Walk scalars, not UTF-16 units: surrogate halves never form a scalar, so
    // a UTF-16 walk ignored supplementary-plane strong-RTL scripts (Adlam,
    // Hanifi Rohingya) and misdetected the direction of lines written in them.
    for scalar in (s as String).unicodeScalars {
        let c = scalar.value
        if c == UInt32(iTermLRI) || c == UInt32(iTermRLI) || c == UInt32(iTermFSI) || c == UInt32(iTermPDI) { continue }
        if rtl.contains(scalar) {
            rtlCount += 1
            if !inRTLWord { rtlWordCount += 1; inRTLWord = true }
            if firstStrongIsRTL == nil { firstStrongIsRTL = true }
        } else if ltr.contains(scalar) {
            ltrCount += 1
            inRTLWord = false
            if firstStrongIsRTL == nil { firstStrongIsRTL = false }
        } else if c == 0x20 {
            inRTLWord = false
        }
    }
    if firstStrongIsRTL == true || rtlCount > ltrCount {
        return true
    }
    // Optional user rule: a line with at least this many RTL words lays out
    // right-to-left even when it opens LTR and Latin holds the majority. At 1,
    // a shell prompt holding a pasted Persian word right-justifies like the
    // same text does in command output. Off (0) by default.
    let minimumWords = Int(iTermAdvancedSettingsModel.rtlParagraphMinimumWords())
    return minimumWords > 0 && rtlWordCount >= minimumWords
}

extension IndexSet {
    func mapRanges(_ transform: (Range<Int>) throws -> Range<Int>) rethrows -> IndexSet {
        var temp = IndexSet()
        for range in rangeView {
            let mapped = try transform(range)
            if !mapped.isEmpty {
                temp.insert(integersIn: mapped)
            }
        }
        return temp
    }

    func compactMapRanges(_ transform: (Range<Int>) throws -> Range<Int>?) rethrows -> IndexSet {
        var temp = IndexSet()
        for range in rangeView {
            if let mapped = try transform(range), !mapped.isEmpty {
                temp.insert(integersIn: mapped)
            }
        }
        return temp
    }
}
@objc(iTermBidiDisplayInfo)
class BidiDisplayInfoObjc: NSObject {
    private let guts: BidiDisplayInfo

    override var description: String {
        "<iTermBidiDisplayInfo: \(self.it_addressString) \(guts.debugDescription)>"
    }
    @objc var lut: UnsafePointer<Int32> {
        guts.lut.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!
        }
    }
    private lazy var _inverseLUT: [Int32] = {
        let lut = guts.lut
        guard let max = lut.max() else {
            return []
        }
        var result = Array(0..<Int32(max + 1))
        for i in 0..<Int(numberOfCells) {
            result[Int(lut[i])] = Int32(i)
        }
        return result
    }()

    @objc var inverseLUT: UnsafePointer<Int32> {
        _inverseLUT.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!
        }
    }

    @objc var inverseLUTCount: Int32 {
        Int32(_inverseLUT.count)
    }

    @objc var rtlIndexes: IndexSet { guts.rtlIndexes }
    // Length of the `lut`. Also equals the number of non-empty sequential cells counting from the first. Does not include trailing spaces.
    @objc var numberOfCells: Int32 { Int32(guts.lut.count) }

    @objc var paragraphIsRTL: Bool { guts.paragraphIsRTL }

    // Whether the given source cell's glyph must be drawn bidi-mirrored (L4).
    @objc(mirrorsSourceCell:)
    func mirrorsSourceCell(_ cell: Int32) -> Bool {
        return guts.mirroredIndexes.contains(Int(cell))
    }


    private enum Keys: String {
        case lut = "lut"
        case rtlIndexes = "rtlIndexes"
        case mirroredIndexes = "mirroredIndexes"
        case paragraphIsRTL = "paragraphIsRTL"
    }

    @objc
    var dictionaryValue: [String: Any] {
        return [Keys.lut.rawValue: guts.lut.efficientlyEncodedForPlist(),
                Keys.rtlIndexes.rawValue: rtlIndexes.rangeView.map { NSValue(range: NSRange($0)) },
                Keys.mirroredIndexes.rawValue: guts.mirroredIndexes.rangeView.map { NSValue(range: NSRange($0)) },
                Keys.paragraphIsRTL.rawValue: guts.paragraphIsRTL ]
    }

    @objc(initWithDeltaString:usedCount:)
    init?(deltaString: DeltaString, usedCount: Int) {
        if let guts = BidiDisplayInfo(deltaString: deltaString, usedCount: usedCount) {
            self.guts = guts
        } else {
            return nil
        }
    }

    @objc(initWithDictionary:)
    init?(_ dictionary: NSDictionary) {
        guard iTermPreferences.bool(forKey: kPreferenceKeyBidi) else {
            return nil
        }
        guard let lutObj = dictionary[Keys.lut.rawValue],
              let encodedLUTArray = lutObj as? Array<Any>,
              let lut = Array<Int32>(efficientlyEncodedForPlist: encodedLUTArray) else {
            return nil
        }
        guard let indexesObj = dictionary[Keys.rtlIndexes.rawValue], let indexesArray = indexesObj as? Array<NSValue> else {
            return nil
        }
        let indexes = IndexSet(ranges: indexesArray.compactMap { Range($0.rangeValue) })
        let mirroredIndexes: IndexSet =
            if let obj = dictionary[Keys.mirroredIndexes.rawValue], let arr = obj as? Array<NSValue> {
                IndexSet(ranges: arr.compactMap { Range($0.rangeValue) })
            } else {
                IndexSet()
            }
        let paragraphIsRTL: Bool =
            if let obj = dictionary[Keys.paragraphIsRTL.rawValue],
               let convertedParagraphIsRTL = obj as? Bool {
                convertedParagraphIsRTL
            } else {
                false
            }
        guts = BidiDisplayInfo(lut: lut,
                               rtlIndexes: indexes,
                               mirroredIndexes: mirroredIndexes,
                               paragraphIsRTL: paragraphIsRTL)
    }

    @objc(initUnpaddedWithScreenCharArray:)
    init?(_ sca: ScreenCharArray) {
        if let guts = BidiDisplayInfo(sca) {
            self.guts = guts
        } else {
            return nil
        }
    }

    @objc(initWithScreenCharArray:paddedTo:)
    init?(_ sca: ScreenCharArray, paddedTo width: Int32) {
        if let guts = BidiDisplayInfo(sca, paddedTo: width) {
            self.guts = guts
        } else {
            return nil
        }
    }

    private init(_ guts: BidiDisplayInfo) {
        self.guts = guts
    }

    // Set the rtlStatus of each cell. This is useful because when rendering a single wrapped line,
    // we need to tell CoreText where RTL runs are since it doesn't have access to the entire
    // paragraph to properly determine embedding lvels.
    // If bidiInfo is nil, annotate all cells as LTR.
    // Returns whether any changes were made.
    @objc
    @discardableResult
    static func annotate(bidiInfo: BidiDisplayInfoObjc?, msca: MutableScreenCharArray) -> Bool {
        let line = msca.mutableLine;
        var changed = false
        for i in 0..<Int(msca.length) {
            let before = line[i].rtlStatus
            line[i].rtlStatus = (bidiInfo?.guts.rtlIndexes.contains(i) ?? false) ? RTLStatus.RTL : RTLStatus.LTR
            if line[i].rtlStatus != before {
                changed = true
            }
        }
        return changed
    }

    @objc(subInfoInRange:paddedToWidth:)
    func subInfo(range nsrange: NSRange, paddedTo width: Int32) -> BidiDisplayInfoObjc? {
        if let guts = guts.subInfo(range: nsrange, width: width) {
            return BidiDisplayInfoObjc(guts)
        } else {
            return nil
        }
    }

    @objc(subInfoInRange:)
    func subInfo(range nsrange: NSRange) -> BidiDisplayInfoObjc? {
        if let guts = guts.subInfo(range: nsrange) {
            return BidiDisplayInfoObjc(guts)
        } else {
            return nil
        }
    }

    @objc(isEqual:)
    override func isEqual(_ other: Any?) -> Bool {
        guard let other, let obj = other as? BidiDisplayInfoObjc else {
            return false
        }
        return guts == obj.guts
    }

    @objc
    func enumerateLogicalRanges(in visualNSRange: NSRange,
                                closure: (NSRange, Int32, UnsafeMutablePointer<ObjCBool>) -> ()) {
        enumerateLogicalRanges(in: visualNSRange, reversed: false, closure:closure)
    }

    // Like enumerateLogicalRanges(in:, closure:) but with the order of calls to `closure` reversed.
    @objc
    func enumerateLogicalRangesReverse(in visualNSRange: NSRange,
                                       closure: (NSRange, Int32, UnsafeMutablePointer<ObjCBool>) -> ()) {
        enumerateLogicalRanges(in: visualNSRange, reversed: true, closure:closure)
    }

    // Invokes `closure` with logical ranges within a visual range, but still in logical order.
    //
    // For example:
    //               012345678
    // Logical       abcDEFghi
    // Visual        ghiFEDabc
    // visualNSRange  ^^^^     1...4
    //
    // Then closure will be invoked with:
    //
    // Logical Range    Visual Start Index
    // 4...5 (EF)       3
    // 7...8 (hi)       1
    //
    // Or, if the reversed flag is true, the same calls are made in the reverse order (i.e., from
    // largest logical range to smallest). The visual order is not necessarily monotonic,
    // regardless of the `reversed` flag.
    private func enumerateLogicalRanges(in visualNSRange: NSRange,
                                        reversed: Bool,
                                        closure: (NSRange, Int32, UnsafeMutablePointer<ObjCBool>) -> ()) {
        guard let visualRange = Range<Int>(visualNSRange) else {
            return
        }

        let visualToLogical = guts.invertedLUT
        let sortedLogicalIndexes = visualRange.map { visualIndex in
            if visualIndex < visualToLogical.count {
                return Int(visualToLogical[visualIndex])
            }
            return visualIndex
        }.sorted()
        let logicalIndexes = reversed ? sortedLogicalIndexes.reversed() : sortedLogicalIndexes
        let logicalToVisual = guts.lut
        var stop = ObjCBool(false)
        for logicalRange in logicalIndexes.rangeIterator() {
            let visualStart = if logicalRange.lowerBound < logicalToVisual.count {
                logicalToVisual[logicalRange.lowerBound]
            } else {
                Int32(logicalRange.lowerBound)
            }
            closure(NSRange(logicalRange), visualStart, &stop)
            if stop.boolValue {
                return
            }
        }
    }

    @objc(logicalForVisual:)
    func logicalForVisual(_ visual: Int32) -> Int32 {
        if visual < 0 {
            return 0
        }
        if visual >= _inverseLUT.count {
            return visual
        }
        return _inverseLUT[Int(visual)]
    }

    @objc(visualForLogical:)
    func visualForLogical(_ logical: Int32) -> Int32 {
        if logical < 0 || logical >= numberOfCells {
            return logical
        }
        return guts.lut[Int(logical)]
    }

    @objc(visualRangeForLogicalRange:)
    func visualRange(for nsrange: NSRange) -> NSRange {
        guard let logicalRange = Range(nsrange) else {
            return nsrange
        }

        let visual = logicalRange.map { Int(visualForLogical(Int32($0))) }
        guard let min = visual.min(), let max = visual.max() else {
            return nsrange
        }
        return NSRange(min...max)
    }
}

struct CollectionRangeIterator<C: Collection>: IteratorProtocol, Sequence where C.Element: BinaryInteger {
    private let collection: C
    private var currentIndex: C.Index

    init(collection: C) {
        self.collection = collection
        self.currentIndex = collection.startIndex
    }

    mutating func next() -> ClosedRange<C.Element>? {
        guard currentIndex < collection.endIndex else { return nil }

        let start = collection[currentIndex]
        var end = start
        collection.formIndex(after: &currentIndex)

        while currentIndex < collection.endIndex, collection[currentIndex] == end + 1 {
            end = collection[currentIndex]
            collection.formIndex(after: &currentIndex)
        }

        return start...end
    }
}

extension Collection where Element: BinaryInteger {
    func rangeIterator() -> CollectionRangeIterator<Self> {
        return CollectionRangeIterator(collection: self)
    }
}

fileprivate struct Chunk {
    var start: Int32
    var count: Int32
    var stride: Int32

    init(start: Int32,
         count: Int32,
         stride: Int32) {
        self.start = start
        self.count = count
        self.stride = stride
    }

    init?(_ value: Any) {
        if let i = value as? Int32 {
            start = i
            count = 1
            stride = 0
        } else if let a = value as? [Int32] {
            start = a[0]
            count = a[1]
            stride = a[2]
        } else {
            return nil
        }
    }

    func extend(_ value: Int32) -> Chunk? {
        if stride == 0 {
            if value == start + 1 {
                return Chunk(start: start, count: count + 1, stride: 1)
            } else if value == start - 1 {
                return Chunk(start: start, count: count + 1, stride: -1)
            } else {
                return nil
            }
        } else if value == start + count * stride {
            return Chunk(start: start, count: count + 1, stride: stride)
        } else {
            return nil
        }
    }

    var plistValues: [Any] {
        switch stride {
        case 0:
            return [start]
        case 1, -1:
            if count < 3 {
                return (0..<count).map { start + stride * $0 }
            }
            return [[start, count, stride]]
        default:
            it_fatalError()
        }
    }

    var decoded: [Int32] {
        if stride == 0 {
            return [start]
        }
        return (0..<count).map { start + stride * $0 }
    }
}

extension Array where Element == Int32 {
    init?(efficientlyEncodedForPlist array: [Any]) {
        let chunks = array.compactMap { Chunk($0) }
        if chunks.count < array.count {
            // Bad chunk found
            return nil
        }
        self = chunks.flatMap { $0.decoded }
    }

    func efficientlyEncodedForPlist() -> [Any] {
        let chunks = reduce(into: [Chunk]()) { partialResult, value in
            if let last = partialResult.last, let extended = last.extend(value) {
                partialResult[partialResult.count - 1] = extended
                return
            }
            partialResult.append(Chunk(start: value, count: 1, stride: 0))
        }
        return chunks.flatMap { $0.plistValues }
    }
}

struct BidiDisplayInfo: CustomDebugStringConvertible, Equatable {
    // Maps a source column to a display column
    fileprivate let lut: [Int32]

    // Indexes into the screen char array that created this object which have right-to-left
    // direction. Adjacent RTL indexes will be drawn right-to-left.
    fileprivate let rtlIndexes: IndexSet

    // Source cells whose glyph must be drawn bidi-mirrored (UBA rule L4).
    // Computed from CoreText's actual per-character resolution, not from run
    // direction, so brackets around embedded LTR runs are correctly excluded.
    fileprivate let mirroredIndexes: IndexSet

    // Base writing direction. Determines how the paragraph should be justified.
    fileprivate let paragraphIsRTL: Bool

    var debugDescription: String {
        struct RLE: CustomDebugStringConvertible {
            var debugDescription: String {
                switch stride {
                case .unknown:
                    "\(start)"
                case .ltr:
                    ">\(start)...\(end)>"
                case .rtl:
                    "<\(end)...\(start)<"
                }
            }
            var start: Int32
            enum Stride {
                case unknown
                case ltr
                case rtl
            }
            var stride: Stride
            var end: Int32
        }
        let rles = lut.reduce(into: Array<RLE>()) { partialResult, value in
            if let last = partialResult.last {
                var replacement = last
                switch last.stride {
                case .unknown:
                    if value == last.start + 1 {
                        replacement.stride = .ltr
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else if value == last.start - 1 {
                        replacement.stride = .rtl
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else {
                        partialResult.append(RLE(start: value, stride: .unknown, end: value))
                    }
                case .ltr:
                    if value == last.end + 1 {
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else {
                        partialResult.append(RLE(start: value, stride: .unknown, end: value))
                    }
                case .rtl:
                    if value == last.end - 1 {
                        replacement.end = value
                        partialResult[partialResult.count - 1] = replacement
                    } else {
                        partialResult.append(RLE(start: value, stride: .unknown, end: value))
                    }
                }
            } else {
                partialResult.append(RLE(start: value, stride: .unknown, end: value))
            }
        }
        let lutString = rles.map { $0.debugDescription }.joined(separator: " ")
        let indexesString = rtlIndexes.rangeView.map { range in
            if range.lowerBound == range.upperBound - 1 {
                return "\(range.lowerBound)"
            }
            return "\(range.lowerBound)…\(range.upperBound - 1)"
        }.joined(separator: ", ")

        return "lut=[\(lutString)] rleIndexes=[\(indexesString)] length=\(lut.count) paragraphIsRTL=\(paragraphIsRTL)"
    }

    fileprivate init(lut: [Int32],
                     rtlIndexes: IndexSet,
                     mirroredIndexes: IndexSet = IndexSet(),
                     paragraphIsRTL: Bool) {
        self.lut = lut
        self.rtlIndexes = rtlIndexes
        self.mirroredIndexes = mirroredIndexes
        self.paragraphIsRTL = paragraphIsRTL
    }

    // Builds the string CoreText should lay out and a per-UTF-16-index map to
    // source cells. With Latin-run isolation on, the string gains isolate
    // controls (mapping to cell -1); otherwise it is the input with an identity
    // cell map.
    fileprivate static func mappedString(_ s: NSString,
                                         deltas: UnsafePointer<Int32>) -> (NSString, [Int32]) {
        if iTermAdvancedSettingsModel.isolateLatinRunsInRTL() {
            return isolateLatinRuns(s, deltas: deltas)
        }
        var map = [Int32]()
        map.reserveCapacity(s.length)
        for k in 0..<s.length {
            map.append(CellOffsetFromUTF16Offset(Int32(k), deltas))
        }
        return (s, map)
    }

    // Fails if no RTL was found
    init?(_ sca: ScreenCharArray) {
        let length = Int32(sca.length)
        let emptyCount = Int32(sca.numberOfTrailingEmptyCells(spaceIsEmpty: false))
        let nonEmptyCount = length - emptyCount

        var buffer: UnsafeMutablePointer<unichar>?
        var deltas: UnsafeMutablePointer<Int32>?
        let string = ScreenCharArrayToString(sca.line, 0, nonEmptyCount, &buffer, &deltas)!
        defer {
            free(deltas)
            free(buffer)
        }

        let (laidOut, cellForIndex) = Self.mappedString(string as NSString, deltas: deltas!)
        (lut, rtlIndexes, mirroredIndexes, paragraphIsRTL) = makeLookupTable(laidOut,
                                                                            cellForIndex: cellForIndex,
                                                                            count: Int(nonEmptyCount))
        if rtlIndexes.isEmpty {
            return nil
        }
    }

    init?(deltaString: DeltaString, usedCount: Int) {
        let (laidOut, cellForIndex) = Self.mappedString(deltaString.unsafeString, deltas: deltaString.deltas)
        (lut, rtlIndexes, mirroredIndexes, paragraphIsRTL) = makeLookupTable(laidOut,
                                                                            cellForIndex: cellForIndex,
                                                                            count: usedCount)
        if rtlIndexes.isEmpty {
            return nil
        }
    }
    private static func pad(lut: [Int32], width: Int32, paragraphIsRTL: Bool) -> [Int32] {
        let baseLength = Int32(lut.count)
        precondition(width > baseLength)
        let growth = width - baseLength
        if paragraphIsRTL {
            return lut.map { $0 + growth } + Array(0..<growth).reversed()
        }
        return lut.map { $0 } + Array((width - growth)..<width)
    }

    // Fails if no RTL was found
    init?(_ sca: ScreenCharArray, paddedTo width: Int32) {
        guard let temp = BidiDisplayInfo(sca) else {
            return nil
        }
        let growth = width - Int32(temp.lut.count)
        self.paragraphIsRTL = temp.paragraphIsRTL
        // Padding only appends cells at the edge; existing source-cell indices
        // (which mirroredIndexes keys on) are unchanged, so carry it verbatim.
        self.mirroredIndexes = temp.mirroredIndexes
        if growth == 0 || !iTermAdvancedSettingsModel.rightJustifyRTLLines() {
            self.lut = temp.lut
            self.rtlIndexes = temp.rtlIndexes
        } else {
            self.lut = Self.pad(lut: temp.lut, width: width, paragraphIsRTL: temp.paragraphIsRTL)
            self.rtlIndexes = temp.rtlIndexes
        }
    }

    // This assumes the base writing direction is RTL, since otherwise this would not be needed.
    init(basedOn base: BidiDisplayInfo, paddedTo width: Int32) {
        lut = iTermAdvancedSettingsModel.rightJustifyRTLLines() ? Self.pad(lut: base.lut, width: width, paragraphIsRTL: base.paragraphIsRTL) : base.lut
        rtlIndexes = base.rtlIndexes
        mirroredIndexes = base.mirroredIndexes
        paragraphIsRTL = base.paragraphIsRTL
    }

    func subInfo(range nsrange: NSRange) -> BidiDisplayInfo? {
        let range = Range(nsrange)!.clamped(to: 0..<lut.count)
        if range == 0..<lut.count {
            return self
        }

        var subIndexes = IndexSet()
        for rtlRange in rtlIndexes.rangeView(of: range) {
            let shifted = rtlRange.shifted(by: -nsrange.location)
            subIndexes.insert(integersIn: shifted)
        }
        if subIndexes.isEmpty {
            return nil
        }

        var subMirrored = IndexSet()
        for mirroredRange in mirroredIndexes.rangeView(of: range) {
            subMirrored.insert(integersIn: mirroredRange.shifted(by: -nsrange.location))
        }

        let sublut = lut[range]
        let sorted = sublut.sorted()

        // Create a compression map to remap `lut` values
        let compression = Dictionary(uniqueKeysWithValues: sorted.enumerated().map {
            ($1, Int32($0))
        })
        let fixed = sublut.map {
            compression[$0]!
        }
        return BidiDisplayInfo(lut: fixed, rtlIndexes: subIndexes, mirroredIndexes: subMirrored, paragraphIsRTL: paragraphIsRTL)
    }

    func subInfo(range nsrange: NSRange, width: Int32) -> BidiDisplayInfo? {
        return subInfo(range: nsrange)?.padded(to: width)
    }

    func padded(to width: Int32) -> BidiDisplayInfo {
        guard width > lut.count else {
            return self
        }
        // Justify by the line's detected paragraph direction. The old guard
        // (first CELL is RTL) predates the majority and minimum-RTL-words
        // rules: a line those rules turn right-to-left can open with a Latin
        // cell («The word سلام means hello»), which then reordered RTL but
        // stayed glued to the left margin instead of right-justifying.
        guard paragraphIsRTL else {
            return self
        }
        return BidiDisplayInfo(basedOn: self, paddedTo: width)
    }

    var invertedLUT: [Int32] {
        var result = Array<Int32>(repeating: 0, count: lut.count)
        for (index, value) in lut.enumerated() {
            result[Int(value)] = Int32(index)
        }
        return result
    }
}

extension ScreenCharArray {
    func numberOfTrailingEmptyCells(spaceIsEmpty: Bool) -> Int {
        var count = 0
        let length = Int(self.length)
        let line = self.line
        let emptyCodes = spaceIsEmpty ? Set([unichar(0), unichar(32)]) : Set([unichar(0)])
        while count < length && emptyCodes.contains(line[Int(length - count - 1)].code) {
            count += 1
        }
        return count
    }
}

extension Range where Bound: Comparable {
    func intersection(_ other: Range<Bound>) -> Range<Bound>? {
        let lowerBound = Swift.max(self.lowerBound, other.lowerBound)
        let upperBound = Swift.min(self.upperBound, other.upperBound)

        return lowerBound < upperBound ? lowerBound..<upperBound : nil
    }
}
