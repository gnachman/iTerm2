//
//  iTermMutableString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermMutableString: iTermRope {
}

// MARK: — Mutation APIs

@objc
extension iTermMutableString: iTermMutableStringProtocol {
    func erase(defaultChar: screen_char_t) {
        let array = Array(Array(repeating: defaultChar, count: cellCount))
        array.withUnsafeBytes { urbp in
            guts.segments = [Segment(string: iTermLegacyStyleString(chars: urbp.bindMemory(to: screen_char_t.self).baseAddress!,
                                                                    count: cellCount,
                                                                    eaIndex: nil),
                                     cumulativeCellCount: cellCount)]
        }
    }
    
    @objc(deleteRange:)
    func objcDelete(range: NSRange) {
        delete(range: Range(range)!)
    }

    @objc
    func objReplace(range: NSRange, with replacement: iTermString) {
        replace(range: Range(range)!, with: replacement)
    }

    @objc(appendString:)
    func append(string: iTermString) {
        appendSegment(string)
    }
    /// Delete N cells from front using indexOfSegment for binary search
    @objc
    func deleteFromStart(_ count: Int) {
        guard count > 0 else { precondition(count >= 0); return }
        guts.stringCache.clear()
        if count == cellCount {
            guts.segments = []
            guts.deletedHeadCellCount = 0
            return
        }
        precondition(count < cellCount)
        let newDeleted = guts.deletedHeadCellCount + count
        let cutIndex = indexOfSegment(for: newDeleted)
        let prevCum = globalBase(segmentIndex: cutIndex)

        // Remove all segments entirely before cutIndex
        if cutIndex > 0 {
            guts.segments.removeFirst(cutIndex)
        }
        if let firstSeg = guts.segments.first {
            let offset = newDeleted - prevCum
            if offset > 0 && offset < firstSeg.string.cellCount {
                partition(segmentIndex: 0, atOffset: offset)
                guts.segments.removeFirst()
            }
        }
        guts.deletedHeadCellCount = newDeleted
    }

    /// Delete N cells from end using indexOfSegment for binary search
    @objc
    func deleteFromEnd(_ count: Int) {
        guard count > 0 else { precondition(count >= 0); return }
        if count == cellCount {
            guts.stringCache.clear()
            guts.segments = []
            guts.deletedHeadCellCount = 0
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
        guts.segments.removeSubrange(firstKeep...)
    }
}

extension iTermMutableString: iTermMutableStringProtocolSwift {
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

        guts.segments.removeSubrange(firstToRemove..<endIdx)
        rebuildCellCounts(from: startIdx)
    }

    /// Replace the given range by deleting it, then inserting `replacement`
    func replace(range: Range<Int>, with replacement: iTermString) {
        guts.stringCache.invalidate(range: range.lowerBound..<cellCount)
        delete(range: range)
        guard replacement.cellCount > 0 else { return }
        insert(replacement, at: range.lowerBound)
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
            guts.segments.insert(Segment(string: string, cumulativeCellCount: -1), at: segIdx + 1)
            rebuildIndex = segIdx + 1
        } else {
            // boundary insert
            let insertIdx = insertionIndexOfSegment(for: globalIndex)
            guts.segments.insert(Segment(string: string, cumulativeCellCount: -1), at: insertIdx)
            rebuildIndex = insertIdx
        }
        rebuildCellCounts(fromSegmentIndex: rebuildIndex)
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

private extension iTermMutableString {
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
        guts.segments.append(Segment(string: seg, cumulativeCellCount: newCum))
    }

    /// Split `segments[segmentIndex]` at `offset`, producing two substrings. Neither may be empty.
    private func partition(segmentIndex: Int, atOffset offset: Int) {
        let original = guts.segments[segmentIndex]
        precondition(offset > 0 && offset < original.string.cellCount)
        let prefix = iTermSubString(base: original.string, range: 0..<offset)
        let suffix = iTermSubString(base: original.string, range: offset..<original.string.cellCount)
        guts.segments[segmentIndex] = Segment(
            string: prefix,
            cumulativeCellCount: original.cumulativeCellCount
                - original.string.cellCount
                + prefix.cellCount
        )
        guts.segments.insert(
            Segment(string: suffix, cumulativeCellCount: original.cumulativeCellCount),
            at: segmentIndex + 1
        )
    }

    /// Recompute cumulative segmentCellCounts from `segments`
    func rebuildCellCounts(from index: Int = 0) {
        let firstSeg = indexOfSegment(for: index)
        rebuildCellCounts(fromSegmentIndex: firstSeg)
    }

    func rebuildCellCounts(fromSegmentIndex firstSegmentIndex: Int) {
        if firstSegmentIndex == 0 {
            guts.deletedHeadCellCount = 0
            var cum = guts.deletedHeadCellCount
            for i in 0..<guts.segments.count {
                cum += guts.segments[i].string.cellCount
                guts.segments[i].cumulativeCellCount = cum
            }
        } else {
            var cum = guts.segments[firstSegmentIndex - 1].cumulativeCellCount
            for i in firstSegmentIndex..<guts.segments.count {
                cum += guts.segments[i].string.cellCount
                guts.segments[i].cumulativeCellCount = cum
            }
        }
    }
}
