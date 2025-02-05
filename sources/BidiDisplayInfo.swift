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


// Make a lookup table that maps source cell to display cell.
fileprivate func makeLookupTable(_ attributedString: NSAttributedString,
                                     deltas: UnsafePointer<Int32>,
                                 count: Int) -> ([Int32], IndexSet, Bool) {
    var rtlIndexes = IndexSet()

    // Create a CTLine from the attributed string
    let line = CTLineCreateWithAttributedString(attributedString)
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]

    // Source cell to range of positions
    var sourceCellToPositionRange = Array<ClosedRange<CGFloat>?>(repeating: nil, count: count)
    for run in runs {
        let isRTL = (run.status.contains(.rightToLeft))
        let stringIndices = run.stringIndices

        // Update rtlIndexes
        if isRTL {
            for stringIndex in run.stringRange {
                let sourceCell = Int(CellOffsetFromUTF16Offset(Int32(stringIndex), deltas))
                rtlIndexes.insert(sourceCell)
            }
        }

        // Update sourceCellToPositionRange
        let positions = run.positions
        for i in 0..<run.glyphCount {
            let stringIndex = stringIndices[i]
            let sourceCell = Int(CellOffsetFromUTF16Offset(Int32(stringIndex), deltas))
            if var existing = sourceCellToPositionRange[sourceCell] {
                existing.formUnion(positions[i].x...positions[i].x)
                sourceCellToPositionRange[sourceCell] = existing
            } else {
                sourceCellToPositionRange[sourceCell] = positions[i].x...positions[i].x
            }
        }
    }

    let cellPositionsBySourceCell = sourceCellToPositionRange.enumerated().map { (sourceCell: Int, positionRange: ClosedRange<CGFloat>?) -> CellPosition in
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

    var resolvedCellPositions = [ResolvedCellPosition]()
    resolvedCellPositions.reserveCapacity(cellPositionsBySourceCell.count)
    for cellPosition in cellPositionsBySourceCell {
        resolvedCellPositions.append(ResolvedCellPosition(previous: resolvedCellPositions.last,
                                                          current: cellPosition))
    }
    let sortedResolvedCellPositions = resolvedCellPositions.sorted()

    var lut = Array(Int32(0)..<Int32(count))
    for (visualIndex, resolvedCellPosition) in sortedResolvedCellPositions.enumerated() {
        lut[Int(resolvedCellPosition.sourceCell)] = Int32(visualIndex)
    }

    let firstStrongLTR = attributedString.string.rangeOfCharacter(from: NSCharacterSet.strongLTRCodePoints())
    let firstStrongRTL = attributedString.string.rangeOfCharacter(from: NSCharacterSet.strongRTLCodePoints())

    let paragraphIsRTL: Bool =
        if let firstStrongLTR, let firstStrongRTL {
            firstStrongLTR.lowerBound > firstStrongRTL.lowerBound
        } else if firstStrongRTL != nil {
            true
        } else {
            false
        }

    return (lut, rtlIndexes, paragraphIsRTL)
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

    private enum Keys: String {
        case lut = "lut"
        case rtlIndexes = "rtlIndexes"
        case paragraphIsRTL = "paragraphIsRTL"
    }

    @objc
    var dictionaryValue: [String: Any] {
        return [Keys.lut.rawValue: guts.lut.efficientlyEncodedForPlist(),
                Keys.rtlIndexes.rawValue: rtlIndexes.rangeView.map { NSValue(range: NSRange($0)) },
                Keys.paragraphIsRTL.rawValue: guts.paragraphIsRTL ]
    }

    @objc(initWithDictionary:)
    init?(_ dictionary: NSDictionary) {
        guard iTermAdvancedSettingsModel.bidi() else {
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
        let paragraphIsRTL: Bool =
            if let obj = dictionary[Keys.paragraphIsRTL.rawValue],
               let convertedParagraphIsRTL = obj as? Bool {
                convertedParagraphIsRTL
            } else {
                false
            }
        guts = BidiDisplayInfo(lut: lut,
                               rtlIndexes: indexes,
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
                     paragraphIsRTL: Bool) {
        self.lut = lut
        self.rtlIndexes = rtlIndexes
        self.paragraphIsRTL = paragraphIsRTL
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

        let attributedString = NSAttributedString(string: string)
        (lut, rtlIndexes, paragraphIsRTL) = makeLookupTable(attributedString,
                                                            deltas: deltas!,
                                                            count: Int(nonEmptyCount))
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
        if growth == 0 {
            self.lut = temp.lut
            self.rtlIndexes = temp.rtlIndexes
        } else {
            self.lut = Self.pad(lut: temp.lut, width: width, paragraphIsRTL: temp.paragraphIsRTL)
            self.rtlIndexes = temp.rtlIndexes
        }
    }

    // This assumes the base writing direction is RTL, since otherwise this would not be needed.
    init(basedOn base: BidiDisplayInfo, paddedTo width: Int32) {
        lut = Self.pad(lut: base.lut, width: width, paragraphIsRTL: base.paragraphIsRTL)
        rtlIndexes = base.rtlIndexes
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

        let sublut = lut[range]
        let sorted = sublut.sorted()

        // Create a compression map to remap `lut` values
        let compression = Dictionary(uniqueKeysWithValues: sorted.enumerated().map {
            ($1, Int32($0))
        })
        let fixed = sublut.map {
            compression[$0]!
        }
        return BidiDisplayInfo(lut: fixed, rtlIndexes: subIndexes, paragraphIsRTL: paragraphIsRTL)
    }

    func subInfo(range nsrange: NSRange, width: Int32) -> BidiDisplayInfo? {
        return subInfo(range: nsrange)?.padded(to: width)
    }

    func padded(to width: Int32) -> BidiDisplayInfo {
        guard width > lut.count else {
            return self
        }
        guard rtlIndexes.contains(0) else {
            return self
        }
        // It would be better to keep an index of strong ltr/rtl charactesr so that subinfos could
        // use the first strong character to define the justification for the wrapped line.
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
