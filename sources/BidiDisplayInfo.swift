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

// Make a lookup table that maps source column number to display column number.
fileprivate func makeLookupTable(_ attributedString: NSAttributedString,
                                 deltas: UnsafePointer<Int32>,
                                 count: Int) -> ([Int32], IndexSet) {
    var rtlIndexes = IndexSet()
    struct CharInfo {
        var stringIndex: Int32
        var positions: ClosedRange<CGFloat>
    }

    // Create a CTLine from the attributed string
    let line = CTLineCreateWithAttributedString(attributedString)
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]

    // Maps indexes in attributedString to display order.
    var lut = Array<Int32>(0..<Int32(count))

    var charInfos = [CharInfo]()
    for run in runs {
        let isRTL = (run.status == .rightToLeft)

        let stringIndices = run.stringIndices
        let positions = run.positions

        var currentRange: ClosedRange<CGFloat>?
        var lastStringIndex: Int32?

        // Process sorted indices using permutation
        let permutation = (0..<stringIndices.count).sorted {
            stringIndices[$0] < stringIndices[$1]
        }

        for index in permutation {
            let stringIndex = Int32(stringIndices[index])
            let position = positions[index].x

            if stringIndex == lastStringIndex {
                // Extend the current range if the string index matches
                currentRange?.formUnion(position...position)
            } else {
                // Push previous CharInfo and start a new one
                if let lastRange = currentRange, let lastIndex = lastStringIndex {
                    charInfos.append(CharInfo(stringIndex: lastIndex, positions: lastRange))
                }
                currentRange = position...position
                lastStringIndex = stringIndex
                if isRTL {
                    rtlIndexes.insert(Int(stringIndex))
                }
            }
        }
        // Push the last CharInfo
        if let lastRange = currentRange, let lastIndex = lastStringIndex {
            charInfos.append(CharInfo(stringIndex: lastIndex, positions: lastRange))
        }
    }

    // Sort CharInfos by the lower bound of their position ranges
    charInfos.sort { $0.positions.lowerBound < $1.positions.lowerBound }

    // Update the lookup table
    for (i, char) in charInfos.enumerated() {
        lut[Int(CellOffsetFromUTF16Offset(char.stringIndex, deltas))] = Int32(i)
    }

    return (lut, rtlIndexes)
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
#warning("TODO: Deal with embedded nulls")
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
    @objc var rtlIndexes: IndexSet { guts.rtlIndexes }
    // Length of the `lut`. Also equals the number of non-empty sequential cells counting from the first.
    @objc var numberOfCells: Int32 { Int32(guts.lut.count) }

    private enum Keys: String {
        case lut = "lut"
        case rtlIndexes = "rtlIndexes"
    }

    var dictionaryValue: [String: Any] {
        return [Keys.lut.rawValue: guts.lut.map { NSNumber(value: $0) },
                Keys.rtlIndexes.rawValue: rtlIndexes.rangeView.map { NSValue(range: NSRange($0)) }]
    }

    @objc(initWithDictionary:)
    init?(_ dictionary: NSDictionary) {
        guard let lutObj = dictionary[Keys.lut.rawValue], let lutArray = lutObj as? Array<NSNumber> else {
            return nil
        }
        guard let indexesObj = dictionary[Keys.rtlIndexes.rawValue], let indexesArray = indexesObj as? Array<NSValue> else {
            return nil
        }
        let lut = lutArray.map { Int32($0.intValue) }
        let indexes = IndexSet(ranges: indexesArray.compactMap { Range($0.rangeValue) })
        guts = BidiDisplayInfo(lut: lut,
                               rtlIndexes: indexes)
    }

    @objc(initWithScreenCharArray:)
    init?(_ sca: ScreenCharArray) {
        if let guts = BidiDisplayInfo(sca) {
            self.guts = guts
        } else {
            return nil
        }
    }

    private init(_ guts: BidiDisplayInfo) {
        self.guts = guts
    }

    // If bidiInfo is nil, annotate all cells as LTR
    // Returns whether any changes were made
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
}

struct BidiDisplayInfo: CustomDebugStringConvertible, Equatable {
    // Maps a source column to a display column
    fileprivate let lut: [Int32]

    // Indexes into the screen char array that created this object which have right-to-left
    // direction. Adjacent RTL indexes will be drawn right-to-left.
    fileprivate let rtlIndexes: IndexSet

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

        return "lut=[\(lutString)] rleIndexes=[\(indexesString)] length=\(lut.count)"
    }

    fileprivate init(lut: [Int32],
                     rtlIndexes: IndexSet) {
        self.lut = lut
        self.rtlIndexes = rtlIndexes
    }

    // Fails if no RTL was found
    init?(_ sca: ScreenCharArray) {
        let length = Int32(sca.length)
        let emptyCount = Int32(sca.numberOfTrailingEmptyCells)
        let nonEmptyCount = length - emptyCount

        var buffer: UnsafeMutablePointer<unichar>?
        var deltas: UnsafeMutablePointer<Int32>?
        let string = ScreenCharArrayToString(sca.line, 0, nonEmptyCount, &buffer, &deltas)!

        let attributedString = NSAttributedString(string: string)
        (lut, rtlIndexes) = makeLookupTable(attributedString,
                                            deltas: deltas!,
                                            count: Int(nonEmptyCount))
        free(deltas)
        free(buffer)
        if rtlIndexes.isEmpty {
            return nil
        }
    }

    func subInfo(range nsrange: NSRange) -> BidiDisplayInfo? {
        let range = Range(nsrange)!.clamped(to: 0..<lut.count)

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
        return BidiDisplayInfo(lut: fixed, rtlIndexes: subIndexes)
    }
}

extension ScreenCharArray {
    var numberOfTrailingEmptyCells: Int {
        var count = 0
        let length = Int(self.length)
        let line = self.line
        while count < length && line[Int(length - count - 1)].code == 0 {
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
