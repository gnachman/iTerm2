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
    // Source cells to draw bidi-mirrored (UBA rule L4): a mirrorable character
    // that CoreText resolved into a right-to-left run. See the loop below.
    var mirroredIndexes = IndexSet()
    var sourceCellToPositionRange: Array<ClosedRange<CGFloat>?>
    var count: Int

    // `string` is what CoreText laid out. `deltas` maps each UTF-16 index of
    // `string` to its source cell (a cumulative sum, since a wide character or
    // surrogate pair occupies more UTF-16 units than cells).
    init(line: CTLine, string: NSString, deltas: UnsafePointer<Int32>, count: Int) {
        self.count = count
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        func cell(_ stringIndex: Int) -> Int {
            guard stringIndex >= 0 && stringIndex < string.length else { return -1 }
            return Int(CellOffsetFromUTF16Offset(Int32(stringIndex), deltas))
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
            for i in 0..<run.glyphCount {
                let stringIndex = stringIndices[i]
                let sourceCell = cell(stringIndex)
                if sourceCell < 0 { continue }  // out of range (shouldn't happen)
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

                // UBA rule L4: a mirrorable character is drawn mirrored iff its
                // resolved bidi level is odd (right-to-left). A CTRun's direction
                // is exactly that level parity, so a mirrorable character in an
                // RTL run mirrors and one in an LTR run does not. This covers the
                // N0 bracket-pair cases for free: brackets around an embedded
                // left-to-right run (e.g. Persian «(English)») are resolved to an
                // even level by CoreText and land in an LTR run, so isRTL is false
                // and they are correctly left un-mirrored.
                if isRTL, stringIndex >= 0, stringIndex < string.length {
                    let ch = string.character(at: stringIndex)
                    if iTermBidiMirroredCounterpart(ch) != ch {
                        mirroredIndexes.insert(sourceCell)
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

// Empty cells hold code 0, which ScreenCharArrayToString stringifies to U+0000.
// A TUI (Claude Code / Ink) positions words with absolute-column moves (CHA,
// ESC[<n>G) and never writes real spaces, so the gaps between words are code-0
// holes. U+0000 is bidi class BN (Boundary Neutral); next to a number (EN) or a
// ZWNJ it perturbs the reorder so every following cell maps one visual column
// too far, and the line renders with spaces inside words. Treat holes as real
// spaces (bidi-neutral whitespace, one UTF-16 unit each so all cell/delta
// indices are unchanged), which is also how empty cells actually draw.
private func replacingNulWithSpace(_ s: NSString) -> NSString {
    let n = s.length
    guard n > 0 else { return s }
    var buf = [unichar](repeating: 0, count: n)
    s.getCharacters(&buf, range: NSRange(location: 0, length: n))
    var changed = false
    for i in 0..<n where buf[i] == 0 {
        buf[i] = 0x20
        changed = true
    }
    return changed ? NSString(characters: buf, length: n) : s
}

// Make a lookup table that maps source cell to display cell.
fileprivate func makeLookupTable(_ string: NSString,
                                 deltas: UnsafePointer<Int32>,
                                 count: Int) -> ([Int32], IndexSet, IndexSet, Bool) {
    let paragraphIsRTL: Bool =
        iTermAdvancedSettingsModel.detectParagraphDirection() &&
        detectedParagraphIsRTL(string)
    // Lay the CTLine out with the same base direction the line is justified
    // with, so justification and the neutrals' resolved positions agree.
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
                                               deltas: deltas,
                                               count: count)

    return (intermediate.lut, intermediate.rtlIndexes, intermediate.mirroredIndexes, paragraphIsRTL)
}

// A line lays out right-to-left when its first strong directional character is
// right-to-left, per the Unicode bidirectional algorithm (rules P2/P3). Walk
// scalars, not UTF-16 units: surrogate halves never form a scalar, so a UTF-16
// walk would ignore supplementary-plane strong-RTL scripts (Adlam, Hanifi
// Rohingya) and misdetect lines written in them.
fileprivate func detectedParagraphIsRTL(_ s: NSString) -> Bool {
    guard let ltr = NSCharacterSet.strongLTRCodePoints(),
          let rtl = NSCharacterSet.strongRTLCodePoints() else {
        return false
    }
    for scalar in (s as String).unicodeScalars {
        if rtl.contains(scalar) {
            return true
        }
        if ltr.contains(scalar) {
            return false
        }
    }
    return false
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

    // Canonical nil-safe single-column converters. Identity when there is no bidi
    // info or the column is outside the mapped cells (0..<numberOfCells), so
    // left-to-right lines and out-of-range columns pass through unchanged. Callers
    // in several files (accessibility, the Companion bridge) used to reimplement
    // this convention, which could (and did) drift from logicalForVisual /
    // visualForLogical, whose own out-of-range handling differs. Route everyone
    // through these instead.
    @objc(logicalColumnForVisualColumn:info:)
    static func logicalColumn(forVisualColumn visualX: Int32, info: BidiDisplayInfoObjc?) -> Int32 {
        guard let info, visualX >= 0, visualX < info.numberOfCells else { return visualX }
        return info.logicalForVisual(visualX)
    }

    @objc(visualColumnForLogicalColumn:info:)
    static func visualColumn(forLogicalColumn logicalX: Int32, info: BidiDisplayInfoObjc?) -> Int32 {
        guard let info, logicalX >= 0, logicalX < info.numberOfCells else { return logicalX }
        return info.visualForLogical(logicalX)
    }

    // Bounding visual column span [location, location + length) for a logical column
    // range [startX, endX). Identity span when there is no bidi info; a zero-width
    // range (a caret) still converts its single column so a caret rect lands at the
    // visual position on a right-to-left line.
    @objc(visualColumnSpanForLogicalStartX:endX:info:)
    static func visualColumnSpan(forLogicalStartX startX: Int32,
                                 endX: Int32,
                                 info: BidiDisplayInfoObjc?) -> VT100GridRange {
        guard let info else {
            return VT100GridRangeMake(startX, max(0, endX - startX))
        }
        if endX <= startX {
            return VT100GridRangeMake(visualColumn(forLogicalColumn: startX, info: info),
                                      max(0, endX - startX))
        }
        var lo = Int32.max
        var hi = Int32.min
        for logicalX in startX..<endX {
            let v = visualColumn(forLogicalColumn: logicalX, info: info)
            lo = min(lo, v)
            hi = max(hi, v)
        }
        return VT100GridRangeMake(lo, hi - lo + 1)
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

    // Source cells whose glyph must be drawn bidi-mirrored (UBA rule L4): a
    // mirrorable character CoreText resolved into a right-to-left run. A bracket
    // around an embedded LTR run resolves to an LTR run, so it is excluded.
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

    // The string CoreText should lay out. Empty cells (code 0) are replaced with
    // spaces; the replacement is length-preserving, so the caller's `deltas`
    // still map each UTF-16 index of the result to its source cell.
    fileprivate static func sanitized(_ s: NSString) -> NSString {
        return replacingNulWithSpace(s)
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

        let laidOut = Self.sanitized(string as NSString)
        (lut, rtlIndexes, mirroredIndexes, paragraphIsRTL) = makeLookupTable(laidOut,
                                                                            deltas: deltas!,
                                                                            count: Int(nonEmptyCount))
        if rtlIndexes.isEmpty {
            return nil
        }
    }

    init?(deltaString: DeltaString, usedCount: Int) {
        let laidOut = Self.sanitized(deltaString.unsafeString)
        (lut, rtlIndexes, mirroredIndexes, paragraphIsRTL) = makeLookupTable(laidOut,
                                                                            deltas: deltaString.deltas,
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
        // Justify by the line's paragraph direction, not by whether the first
        // CELL is right-to-left: a right-to-left line can open with a neutral or
        // a number (so cell 0 is not in rtlIndexes) yet must still right-justify.
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
