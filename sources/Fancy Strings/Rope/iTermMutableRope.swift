//
//  iTermMutableRope.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermMutableRope: iTermRope {
    override func clone() -> any iTermString {
        return iTermRope(guts: guts.clone())
    }
}

// MARK: — Mutation APIs

@objc
extension iTermMutableRope: iTermMutableStringProtocol {
    func erase(defaultChar: screen_char_t) {
        if cellCount == 0 {
            return
        }
        let guts = Guts()
        guts.set(segments: [Segment(string: iTermUniformString(char: defaultChar, length: cellCount),
                                    cumulativeCellCount: cellCount)])
        self.guts = guts
    }

    @objc(deleteRange:)
    func objcDelete(range: NSRange) {
        delete(range: Range(range)!)
    }

    @objc
    func objcReplace(range: NSRange, with replacement: iTermString) {
        replace(range: Range(range)!, with: replacement)
    }

    @objc(appendString:)
    func append(string: iTermString) {
        if string.cellCount == 0 {
            return
        }
        if let rope = string as? iTermRope {
            guts.append(segments: rope.guts.segments,
                        mayHaveExternalAttribute: rope.guts.mayHaveExternalAttributes)
        } else {
            appendSegment(string)
        }
    }

    /// Delete N cells from front using indexOfSegment for binary search
    @objc
    func deleteFromStart(_ count: Int) {
        guard count > 0 else { precondition(count >= 0); return }
        guts.stringCache.clear()
        if count == cellCount {
            guts.set(segments: [])
            return
        }
        precondition(count < cellCount)
        let newDeleted = guts.deletedHeadCellCount + count
        let cutIndex = indexOfSegment(for: newDeleted)
        let prevCum = globalBase(segmentIndex: cutIndex)

        // Remove all segments entirely before cutIndex
        if cutIndex > 0 {
            guts.removeFirstSegments(cutIndex)
        }
        if let firstSeg = guts.segments.first {
            let offset = newDeleted - prevCum
            if offset > 0 && offset < firstSeg.string.cellCount {
                partition(segmentIndex: 0, atOffset: offset)
                guts.removeFirstSegments(1)
            }
        }
        guts.deletedHeadCellCount = newDeleted
    }

    /// Delete N cells from end using indexOfSegment for binary search
    @objc
    func deleteFromEnd(_ count: Int) {
        guard count > 0 else { precondition(count >= 0); return }
        if count == cellCount {
            guts.set(segments: [])
            return
        }
        precondition(count < cellCount)
        guts.stringCache.invalidate(range: (cellCount - count)..<cellCount)
        let remain = cellCount - count
        let globalCut = guts.deletedHeadCellCount + remain
        let cutIndex = indexOfSegment(for: globalCut)
        // Compute cumulative before that segment
        let prevCum = globalBase(segmentIndex: cutIndex)
        // Offset within that segment
        let offset = globalCut - prevCum
        var firstKeep = cutIndex
        if offset > 0 && offset < guts.segments[cutIndex].string.cellCount {
            partition(segmentIndex: cutIndex, atOffset: offset)
            firstKeep += 1
        }
        guts.removeSegments(fromIndex: firstKeep)
    }

    func resetRTLStatus() {
        let replacementSegments = guts.segments.map { segment in
            let modified: iTermString = segment.string.stringBySettingRTL(
                in: segment.string.fullRange,
                rtlIndexes: nil)
            return Segment(string: modified,
                           cumulativeCellCount: segment.cumulativeCellCount)
        }
        guts.set(segments: replacementSegments)
    }

    @objc func setRTLIndexes(_ indexSet: IndexSet) {
        var segments = guts.segments
        enumerateSegments(inRange: 0..<cellCount) { i, string, localRange in
            let globalRange = self.globalSegmentRange(index: i)
            var subset = indexSet[globalRange]
            subset.shift(startingAt: 0,
                         by: -globalRange.lowerBound)
            let modified = string.stringBySettingRTL(
                in: NSRange(localRange),
                rtlIndexes: subset)
            segments[i] = Segment(
                string: modified,
                cumulativeCellCount: guts.segments[i].cumulativeCellCount)
        }
        guts.setSegmentsWithoutSideEffects(segments)
        guts.stringCache.clear()
    }

    @objc func setExternalAttributes(_ sourceIndex: iTermExternalAttributeIndexReading?,
                                     sourceRange: NSRange,
                                     destinationStartIndex: Int) {
        var segments = guts.segments
        var o = 0
        enumerateSegments(inRange: destinationStartIndex..<(destinationStartIndex + sourceRange.length)) { i, string, localRange in
            let g = globalSegmentRange(index: i)
            let sourceStart = sourceRange.location + o
            let sourceRange = sourceStart..<(sourceStart + localRange.count)
            let newString = string._string(
                withExternalAttributes: sourceIndex,
                sourceRange: sourceRange,
                destinationStartIndex: g.lowerBound + localRange.lowerBound)
            segments[i] = Segment(
                    string: newString,
                    cumulativeCellCount: guts.segments[i].cumulativeCellCount)
            o += localRange.count
        }
        guts.setSegmentsWithoutSideEffects(segments)
        guts.stringCache.clear()
        guts.updateMayHaveExternalAttributes()
    }
}

extension iTermMutableRope {
    private func set(segments: [Segment]) {
        guts.set(segments: segments.filter { $0.string.cellCount > 0 })
    }
}

extension iTermMutableRope: iTermMutableStringProtocolSwift {
    /// Delete the given [cell‑index] range from the rope
    func delete(range: Range<Int>) {
        if range.count == 0 {
            return
        }
        // fast paths for prefix or suffix
        if range.lowerBound == 0 {
            deleteFromStart(range.count)
            return
        }
        if range.upperBound == cellCount {
            deleteFromEnd(range.count)
            return
        }

        guts.stringCache.clear()
        let globalStart = guts.deletedHeadCellCount + range.lowerBound
        let globalEnd = guts.deletedHeadCellCount + range.upperBound

        // split start segment
        let startIdx = indexOfSegment(for: globalStart)

        // Do end computations before partition invalidates segmentCellCounts.
        var endIdx = indexOfSegment(for: globalEnd)
        var endBase = globalBase(segmentIndex: endIdx)
        precondition(endIdx >= startIdx)

        var firstToRemove = startIdx
        let startBase = globalBase(segmentIndex: startIdx)
        let startOffset = globalStart - startBase
        let startSegCount = guts.segments[startIdx].string.cellCount

        if startOffset > 0 && startOffset < startSegCount {
            partition(segmentIndex: startIdx, atOffset: startOffset)
            firstToRemove += 1
            if startIdx == endIdx {
                endBase += startOffset
            }
            endIdx += 1
        }

        // split end segment (after split above, recompute index)
        let endOffset = globalEnd - endBase
        let endSegCount = guts.segments[endIdx].string.cellCount
        if endOffset > 0 && endOffset < endSegCount {
            partition(segmentIndex: endIdx, atOffset: endOffset)
            endIdx += 1
        }
        guts.removeSegmentsSubrange(firstToRemove..<endIdx)
        rebuildCellCounts(from: startIdx)
    }

    /// Replace the given range by deleting it, then inserting `replacement`
    func replace(range: Range<Int>, with replacement: iTermString) {
        if range == 0..<cellCount {
            guts.set(segments: [Segment(string: replacement, cumulativeCellCount: replacement.cellCount)])
            return
        }
        guts.stringCache.invalidate(range: range.lowerBound..<cellCount)
        let removeCount = range.count
        let insertCount = replacement.cellCount
        if removeCount == 0 {
            insert(replacement, at: range.lowerBound)
            return
        }
        if insertCount == 0 {
            delete(range: range)
            return
        }

        // General splice
        let segmentIndexRange = splitSegmentsForReplacement(range)
        let replacementSegments = buildReplacementSegments(from: replacement)
        replaceSegments(inRange: segmentIndexRange,
                        with: replacementSegments)
    }

    /// Splits the start and end segment boundaries so that the removal range
    /// aligns on segment boundaries. Returns the range of segments to remove.
    private func splitSegmentsForReplacement(_ range: Range<Int>) -> ClosedRange<Int> {
        let globalStart = guts.deletedHeadCellCount + range.lowerBound
        let globalEnd = guts.deletedHeadCellCount + range.upperBound

        // Split at start
        var startIdx = indexOfSegment(for: globalStart)
        let startBase = globalBase(segmentIndex: startIdx)
        let startOffset = globalStart - startBase
        if startOffset > 0 && startOffset < guts.segments[startIdx].string.cellCount {
            partition(segmentIndex: startIdx, atOffset: startOffset)
            startIdx += 1
        }

        // Split at end
        let endIdx = indexOfSegment(for: globalEnd - 1)
        let endBase = globalBase(segmentIndex: endIdx)
        let endOffset = globalEnd - endBase
        if endOffset > 0 && endOffset < guts.segments[endIdx].string.cellCount {
            partition(segmentIndex: endIdx, atOffset: endOffset)
        }

        // After splitting, recompute removal end index
        return startIdx...endIdx
    }

    /// Constructs an array of `Segment` from the replacement string,
    /// reusing segments if `replacement` is already a rope.
    private func buildReplacementSegments(from replacement: iTermString) -> [Segment] {
        return [Segment(string: replacement, cumulativeCellCount: replacement.cellCount)]
    }

    /// Performs the single array splice of old segments to new.
    private func replaceSegments(inRange range: ClosedRange<Int>,
                                with segmentsToInsert: [Segment]) {
        guts.replaceSegments(subrange: range, replacement: segmentsToInsert)
        guts.rebuildCellCounts(fromSegmentIndex: range.lowerBound)
    }

    @objc
    func insert(_ string: iTermString, at index: Int) {
        guts.stringCache.invalidate(range: index..<cellCount)
        if index == cellCount {
            append(string: string)
            return
        }
        let globalIndex = index + guts.deletedHeadCellCount
        let segIdx = indexOfSegment(for: globalIndex)
        let segStart = globalBase(segmentIndex: segIdx)
        let segEnd = guts.segments[segIdx].cumulativeCellCount
        let rebuildIndex: Int
        if globalIndex > segStart && globalIndex < segEnd {
            // split mid‑segment, then insert between
            let offset = globalIndex - segStart
            partition(segmentIndex: segIdx, atOffset: offset)
            guts.insert(segment: Segment(string: string, cumulativeCellCount: -1),
                        at: segIdx + 1)
            rebuildIndex = segIdx + 1
        } else {
            // boundary insert
            let insertIdx = insertionIndexOfSegment(for: globalIndex)
            guts.insert(segment: Segment(string: string, cumulativeCellCount: -1),
                        at: insertIdx)
            rebuildIndex = insertIdx
        }
        guts.rebuildCellCounts(fromSegmentIndex: rebuildIndex)
    }

    func sanityCheck() {
        it_assert(guts.deletedHeadCellCount >= 0)
        var last = guts.deletedHeadCellCount
        for segment in guts.segments {
            it_assert(segment.cumulativeCellCount >= 0)
            it_assert(segment.cumulativeCellCount > last)
            it_assert(segment.cumulativeCellCount - segment.string.cellCount == last)
            last = segment.cumulativeCellCount
        }
    }

}

// MARK: - Utilities

private extension iTermMutableRope {
    func globalBase(segmentIndex: Int) -> Int {
        return segmentIndex == 0
            ? guts.deletedHeadCellCount
            : guts.segments[segmentIndex - 1].cumulativeCellCount
    }

    func insertionIndexOfSegment(for globalIndex: Int) -> Int {
        var low = 0, high = guts.segments.count
        while low < high {
            let mid = (low + high) / 2
            let prefix = mid == 0 ? guts.deletedHeadCellCount : guts.segments[mid - 1].cumulativeCellCount
            if prefix < globalIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    func appendSegment(_ seg: iTermString) {
        let newCum = (guts.segments.last?.cumulativeCellCount ?? guts.deletedHeadCellCount) + seg.cellCount
        guts.append(segment: Segment(string: seg, cumulativeCellCount: newCum))
    }

    /// Split `segments[segmentIndex]` at `offset`, producing two substrings. Neither may be empty.
    private func partition(segmentIndex: Int, atOffset offset: Int) {
        let original = guts.segments[segmentIndex]
        precondition(offset > 0 && offset < original.string.cellCount)
        let prefix = iTermSubString(base: original.string, range: 0..<offset)
        let suffix = iTermSubString(base: original.string, range: offset..<original.string.cellCount)
        guts.set(segment: Segment(
            string: prefix,
            cumulativeCellCount: original.cumulativeCellCount
                - original.string.cellCount
                + prefix.cellCount
        ),
                 at: segmentIndex)

        guts.insert(segment: Segment(string: suffix, cumulativeCellCount: original.cumulativeCellCount),
                    at: segmentIndex + 1)
    }

    /// Recompute cumulative segmentCellCounts from `segments`
    func rebuildCellCounts(from index: Int = 0) {
        let firstSeg = indexOfSegment(for: index)
        guts.rebuildCellCounts(fromSegmentIndex: firstSeg)
    }
}
