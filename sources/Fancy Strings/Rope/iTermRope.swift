//
//  iTermRope.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermRope: NSObject {
    struct Segment {
        // No matter what `string` must be immutable. Although I prefer mutable fields in structs,
        // keeping this as a let makes it easier to prove that string is immutable (since clone()
        // is meant to return an immutable copy).
        let string: iTermString
        var cumulativeCellCount: Int

        init(string: iTermString, cumulativeCellCount: Int) {
            self.string = string.clone()
            self.cumulativeCellCount = cumulativeCellCount
        }
    }

    final class Guts: Cloning {
        var segments = [Segment]()
        var deletedHeadCellCount = 0
        var stringCache = SubStringCache()

        func clone() -> Guts {
            let result = Guts()
            result.segments = segments.map { segment in
                if let mut = segment.string as? iTermMutableStringProtocol {
                    return Segment(string: mut.clone(),
                                   cumulativeCellCount: segment.cumulativeCellCount)
                } else {
                    return segment
                }
            }
            result.deletedHeadCellCount = deletedHeadCellCount
            return result
        }
    }

    @CopyOnWrite var guts = Guts()

    override var description: String {
        let segmentStrings: [String] = guts.segments.enumerated().map { i, seg in
            "  Segment \(i) cumulativeCount=\(seg.cumulativeCellCount): \(seg.string)"
        }
        let header = "\(String(describing: type(of: self))): \(it_addressString) " +
                        "cells=\(cellCount) " +
                        "deletedCellCount=\(guts.deletedHeadCellCount) " +
        "value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash().d)"
        let array = [header] + segmentStrings
        let separator = segmentStrings.count == 1 ? " " : "\n"
        return "<" + array.joined(separator: separator) + ">"
    }

    override init() {
        super.init()
    }

    init(_ other: iTermRope) {
        guts = other.guts.clone()
        super.init()
    }

    init(_ string: iTermString) {
        super.init()
        guts.segments = [Segment(string: string.clone(), cumulativeCellCount: string.cellCount)]
    }

    init(_ strings: [iTermString]) {
        super.init()
        var segments = [Segment]()
        var count = 0
        for string in strings {
            count += string.cellCount
            segments.append(Segment(string: string, cumulativeCellCount: count))
        }
        guts.segments = segments
    }

    required init(guts: Guts) {
        self.guts = guts
    }
}

extension iTermRope: NSMutableCopying, NSCopying {
    func copy(with zone: NSZone? = nil) -> Any {
        return clone()
    }

    func mutableCopy(with zone: NSZone? = nil) -> Any {
        return mutableClone()
    }
}

@objc
extension iTermRope: iTermString {
    func isEqual(to string: iTermString) -> Bool {
        if cellCount != string.cellCount {
            return false
        }
        return isEqual(lhsRange: fullRange, toString: string, startingAtIndex: 0)
    }

    // This implements:
    // return self[lhsRange] == rhs[startIndex..<(startIndex+lhsRange.count)
    func isEqual(lhsRange: NSRange, toString rhs: iTermString, startingAtIndex startIndex: Int) -> Bool {
        if !Range(fullRange)!.contains(Range(lhsRange)!) {
            return false
        }
        if lhsRange.length > rhs.cellCount - startIndex {
            return false
        }
        var rhsIndex = startIndex
        for (i, substr, localRange) in segmentIterator(inRange: Range(lhsRange)!) {
            let global = globalSegmentRange(index: i)
            if !substr.isEqual(lhsRange: NSRange(localRange),
                               toString: rhs,
                               startingAtIndex: rhsIndex) {
                return false
            }
            rhsIndex += localRange.count
        }
        return true
    }


    func usedLength(range: NSRange) -> Int32 {
        // Find the last segment that is not all used
        var found = false
        var sum = Int32(0)
        enumerateSegmentsReversed(inRange: Range(range)!) { i, seg, localRange in
            if found {
                sum += Int32(localRange.count)
                return
            }
            let used = seg.usedLength(range: NSRange(localRange))
            if used > 0 {
                found = true
                sum += used
            }
        }
        return sum
    }

    func stringBySettingRTL(in range: NSRange,
                            rtlIndexes: IndexSet?) -> iTermString {
        let temp = Guts()
        var count = 0
        enumerateSegments(inRange: Range(range)!) { i, substring, localRange in
            count += localRange.count
            let globalRange = globalSegmentRange(index: i)
            var subset = rtlIndexes?[globalRange]
            subset?.shift(startingAt: 0, by: -globalRange.lowerBound)
            temp.segments.append(
                Segment(
                    string: substring.stringBySettingRTL(
                        in: NSRange(localRange),
                        rtlIndexes: subset),
                    cumulativeCellCount: count))
        }
        return Self(guts: temp)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        var result = IndexSet()
        var offset = 0
        enumerateSegments(inRange: Range(nsrange)!) { i, string, localRange in
            let segment = guts.segments[i]
            let part = string.doubleWidthIndexes(range: NSRange(localRange),
                                                 rebaseTo: offset)
            offset += localRange.count
            result.formUnion(part)
        }
        return result
    }

    func isEmpty(range: NSRange) -> Bool {
        return segmentIterator(inRange: Range(range)!).allSatisfy { (_, seg, localRange) in
            seg.isEmpty(range: NSRange(localRange))
        }
    }

    var cellCount: Int {
        let lastCum = guts.segments.last?.cumulativeCellCount ?? guts.deletedHeadCellCount
        return lastCum - guts.deletedHeadCellCount
    }

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        var o = 0
        enumerateSegments(inRange: Range(sourceRange)!) { i, seg, localRange in
            seg.hydrate(into: msca,
                        destinationIndex: destinationIndex + o,
                        sourceRange: NSRange(localRange))
            o += localRange.count
        }
    }

    func hydrate(range: NSRange) -> ScreenCharArray {
        return _hydrate(range: range)
    }

    func character(at index: Int) -> screen_char_t {
        return _character(at: index)
    }

    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        enumerateSegments(inRange: Range(range)!) { i, seg, segmentRange in
            seg.buildString(range: NSRange(segmentRange), builder: builder)
        }
    }

    func deltaString(range: NSRange) -> DeltaString {
        return guts.stringCache.string(for: range) {
            let builder = DeltaStringBuilder(count: CInt(cellCount))
            buildString(range: fullRange, builder: builder)
            return builder.build()
        }
    }

    func mutableClone() -> any iTermMutableStringProtocol {
        return iTermMutableRope(guts: guts)
    }

    func clone() -> iTermString {
        return iTermRope(guts: guts.clone())
    }

    func externalAttributesIndex() -> (any iTermExternalAttributeIndexReading)? {
        return _externalAttributesIndex()
    }

    var screenCharArray: ScreenCharArray {
        return _screenCharArray
    }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        return _hasEqual(range: range, to: chars)
    }

    func substring(range: NSRange) -> any iTermString {
        return _substring(range: range)
    }

    func externalAttribute(at index: Int) -> iTermExternalAttribute? {
        let segmentIndex = indexOfSegment(for: index)
        let segment = guts.segments[segmentIndex]
        let segmentStart = segment.cumulativeCellCount - segment.string.cellCount
        return segment.string.externalAttribute(at: index - segmentStart)
    }
}

extension iTermRope {
    func indexOfSegment(for globalIndex: Int) -> Int {
        if globalIndex <= guts.deletedHeadCellCount {
            return 0
        }
        var low = 0
        var high = guts.segments.count - 1
        while low < high {
            let mid = (low + high) / 2
            if guts.segments[mid].cumulativeCellCount <= globalIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    func globalSegmentRange(index i: Int) -> Range<Int> {
        let base = i > 0 ? guts.segments[i - 1].cumulativeCellCount : guts.deletedHeadCellCount
        return base..<guts.segments[i].cumulativeCellCount
    }

    func enumerateSegments(inRange range: Range<Int>,
                           closure: (Int, iTermString, Range<Int>) -> ()) {
        for (i, str, subrange) in segmentIterator(inRange: range) {
            closure(i, str, subrange)
        }
    }

    func enumerateSegmentsReversed(inRange range: Range<Int>, closure: (Int, iTermString, Range<Int>) -> ()) {
        let startIndex = indexOfSegment(for: range.lowerBound)
        let globalRange = (range.lowerBound + guts.deletedHeadCellCount)..<(range.upperBound + guts.deletedHeadCellCount)
        for i in (startIndex..<guts.segments.count).reversed() {
            let gsr = globalSegmentRange(index: i)
            if gsr.isEmpty {
                continue
            }
            guard let intersection = gsr.intersection(globalRange), intersection.count > 0 else {
                break
            }
            let localStart = intersection.lowerBound - gsr.lowerBound
            let localRange = localStart..<(localStart + intersection.count)
            it_assert((0..<guts.segments[i].string.cellCount).contains(range: localRange))
            closure(i, guts.segments[i].string, localRange)
        }
    }

    /// Iterator‐style version of `enumerateSegments(inRange:)`
    func segmentIterator(inRange range: Range<Int>) -> AnySequence<(Int, iTermString, Range<Int>)> {
        let startIndex = indexOfSegment(for: range.lowerBound)
        let globalRange = (range.lowerBound + guts.deletedHeadCellCount)..<(range.upperBound + guts.deletedHeadCellCount)
        return AnySequence { () -> AnyIterator<(Int, iTermString, Range<Int>)> in
            var i = startIndex
            return AnyIterator {
                while i < self.guts.segments.count {
                    let idx = i
                    defer {
                        i += 1
                    }
                    let gsr = self.globalSegmentRange(index: idx)
                    if gsr.isEmpty {
                        continue
                    }
                    guard let intersection = gsr.intersection(globalRange),
                          intersection.count > 0 else {
                        return nil
                    }
                    let localStart = intersection.lowerBound - gsr.lowerBound
                    let localRange = localStart ..< (localStart + intersection.count)
                    it_assert((0..<self.guts.segments[idx].string.cellCount).contains(range: localRange))
                    return (idx, self.guts.segments[idx].string, localRange)
                }
                return nil
            }
        }
    }

    // convenience for whole‐buffer iteration
    func segmentIterator() -> AnySequence<(Int, iTermString, Range<Int>)> {
        return segmentIterator(inRange: 0..<cellCount)
    }
}
