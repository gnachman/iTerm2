//
//  iTermRope.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermRope: iTermBaseString {
    struct Segment {
        // No matter what `string` must be immutable. Although I prefer mutable fields in structs,
        // keeping this as a let makes it easier to prove that string is immutable (since clone()
        // is meant to return an immutable copy).
        let string: iTermString
        var cumulativeCellCount: Int
        lazy var mayHaveExternalAttributes: Bool = {
            if let rope = string as? iTermRope {
                return rope.guts.mayHaveExternalAttributes
            }
            return string.hasExternalAttributes(range: string.fullRange)
        }()
        init(string: iTermString, cumulativeCellCount: Int) {
            self.string = string.clone()
            self.cumulativeCellCount = cumulativeCellCount
        }
    }

    final class Guts: Cloning {
        private(set) var segments = [Segment]()
        var deletedHeadCellCount = 0
        var stringCache = SubStringCache()
        var mayHaveExternalAttributes = false

        func clone() -> Guts {
            let result = Guts()
            result.segments = segments
            result.deletedHeadCellCount = deletedHeadCellCount
            result.mayHaveExternalAttributes = mayHaveExternalAttributes
            return result
        }

        func set(segments: [Segment]) {
            self.segments = segments
            deletedHeadCellCount = 0
            stringCache.clear()
            updateMayHaveExternalAttributes()
        }

        func updateMayHaveExternalAttributes() {
            for i in 0..<segments.count {
                if segments[i].mayHaveExternalAttributes {
                    mayHaveExternalAttributes = true
                    return
                }
            }
            mayHaveExternalAttributes = false
        }

        func setSegmentsWithoutSideEffects(_ segments: [Segment]) {
            self.segments = segments
        }

        func removeFirstSegments(_ count: Int) {
            self.segments.removeFirst(count)
            deletedHeadCellCount = 0
            stringCache.clear()
        }

        func removeSegments(fromIndex: Int) {
            stringCache.clear()
            segments.removeSubrange(fromIndex...)
        }

        func removeSegmentsSubrange(_ subrange: Range<Int>) {
            if subrange.lowerBound == 0 {
                deletedHeadCellCount = 0
            }
            segments.removeSubrange(subrange)
            stringCache.clear()
        }

        func replaceSegments(subrange range: ClosedRange<Int>, replacement: [Segment]) {
            segments.replaceSubrange(range, with: replacement)
            if range.lowerBound == 0 {
                deletedHeadCellCount = 0
            }
            stringCache.clear()
            mayHaveExternalAttributes = mayHaveExternalAttributes || replacement.anySatisfies {
                $0.string.hasExternalAttributes(range: $0.string.fullRange)
            }
        }

        func insert(segment: Segment, at i: Int) {
            if i == 0 {
                it_assert(deletedHeadCellCount == 0)
            }
            segments.insert(segment, at: i)
            let start = i > 0 ? segments[i - 1].cumulativeCellCount : 0
            let end = segments.last?.cumulativeCellCount ?? 0
            stringCache.invalidate(range: start..<end)
            mayHaveExternalAttributes = mayHaveExternalAttributes || segments[i].mayHaveExternalAttributes
        }

        func append(segment: Segment) {
            segments.append(segment)
            mayHaveExternalAttributes = mayHaveExternalAttributes || segments[segments.count - 1].mayHaveExternalAttributes
        }

        func append(segments: [Segment], mayHaveExternalAttribute: Bool) {
            let i = self.segments.count
            self.segments.append(contentsOf: segments)
            mayHaveExternalAttributes = mayHaveExternalAttributes || mayHaveExternalAttribute
            rebuildCellCounts(fromSegmentIndex: i)
        }

        func set(segment: Segment, at i: Int) {
            segments[i] = segment
            stringCache.invalidate(range: cellRangeForSegment(from: i))
            mayHaveExternalAttributes = mayHaveExternalAttributes || segments[i].mayHaveExternalAttributes
        }

        private func cellRangeForSegment(at i: Int) -> Range<Int> {
            let start = i > 0 ? segments[i - 1].cumulativeCellCount : 0
            let end = segments[i].cumulativeCellCount
            return start..<end
        }

        private func cellRangeForSegment(from i: Int) -> Range<Int> {
            let start = i > 0 ? segments[i - 1].cumulativeCellCount : 0
            let end = segments.last?.cumulativeCellCount ?? 0
            return start..<end
        }

        func rebuildCellCounts(fromSegmentIndex firstSegmentIndex: Int) {
            if firstSegmentIndex == 0 {
                deletedHeadCellCount = 0
                var cum = deletedHeadCellCount
                for i in 0..<segments.count {
                    cum += segments[i].string.cellCount
                    segments[i].cumulativeCellCount = cum
                }
            } else {
                var cum = segments[firstSegmentIndex - 1].cumulativeCellCount
                for i in firstSegmentIndex..<segments.count {
                    cum += segments[i].string.cellCount
                    segments[i].cumulativeCellCount = cum
                }
            }
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
        if string.cellCount > 0 {
            guts.set(segments: [Segment(string: string.clone(), cumulativeCellCount: string.cellCount)])
        }
    }

    init(_ strings: [iTermString]) {
        super.init()
        var segments = [Segment]()
        var count = 0
        for string in strings {
            let cellCount = string.cellCount
            if cellCount == 0 {
                continue
            }
            count += cellCount
            segments.append(Segment(string: string, cumulativeCellCount: count))
        }
        guts.set(segments: segments)
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
        if range.location == 0 && range.length == cellCount {
            // Fast path when measuring the whole rope.
            var used = cellCount
            let segments = guts.segments
            for i in (0..<segments.count).reversed() {
                let segmentCount: Int
                let segmentUsed: Int
                if i == 0 {
                    let deleted = guts.deletedHeadCellCount
                    segmentCount = segments[i].string.cellCount - deleted
                    segmentUsed = Int(segments[i].string.usedLength(range: NSRange(location: deleted, length: segmentCount)))
                } else {
                    segmentCount = segments[i].string.cellCount
                    segmentUsed = Int(segments[i].string.usedLength(range: NSRange(location: 0, length: segmentCount)))
                }
                let unusedInSegment = segmentCount - segmentUsed
                if unusedInSegment > 0 {
                    // Whole segment is empty. Keep looking
                    used -= unusedInSegment
                }
                if unusedInSegment < segmentCount {
                    break
                }
            }
            return Int32(used)
        }

        // Find the last segment that is not all used
        var found = false
        var sum = Int32(0)

        for (_, seg, localRange) in segmentIterator(inRange: Range(range)!).reversed() {
            if found {
                sum += Int32(localRange.count)
                continue
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
        var segments = [Segment]()
        enumerateSegments(inRange: Range(range)!) { i, substring, localRange in
            count += localRange.count
            let globalRange = globalSegmentRange(index: i)
            var subset = rtlIndexes?[globalRange]
            subset?.shift(startingAt: 0, by: -globalRange.lowerBound)
            segments.append(
                Segment(
                    string: substring.stringBySettingRTL(
                        in: NSRange(localRange),
                        rtlIndexes: subset),
                    cumulativeCellCount: count))
        }
        temp.set(segments: segments)
        return Self(guts: temp)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        var result = IndexSet()
        var offset = 0
        enumerateSegments(inRange: Range(nsrange)!) { i, string, localRange in
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
        it_assert(fullRange.contains(sourceRange), "Source range \(sourceRange) out of bounds in rope of length \(cellCount)")
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
            buildString(range: range, builder: builder)
            return builder.build()
        }
    }

    func mutableClone() -> any iTermMutableStringProtocol {
        return iTermMutableRope(guts: guts)
    }

    // Mutable subclasses must override this!
    func clone() -> iTermString {
        return self
    }

    func externalAttributesIndex() -> (any iTermExternalAttributeIndexReading)? {
        if !guts.mayHaveExternalAttributes {
            return nil
        }
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
    var mayContainDoubleWidthCharacter: Bool {
        // Avoid setting up a segment iterator
        return guts.segments.anySatisfies { segment in
            segment.string.mayContainDoubleWidthCharacter
        }
    }
    func mayContainDoubleWidthCharacter(in nsrange: NSRange) -> Bool {
        for (_, string, localRange) in segmentIterator(inRange: Range(nsrange)!) {
            if string.mayContainDoubleWidthCharacter(in: NSRange(localRange)) {
                return true
            }
        }
        return false
    }
    func hasExternalAttributes(range: NSRange) -> Bool {
        for (_, string, localRange) in segmentIterator(inRange: Range(range)!) {
            if string.hasExternalAttributes(range: NSRange(localRange)) {
                return true
            }
        }
        return false
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
