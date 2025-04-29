/// Yet another interval map. This uses runlength encoding and has fast append, delete from head, and delete from tail.
struct SegmentMap<Payload: Equatable>: Equatable {
    // MARK: - Nested Types

    struct Run: Equatable {
        var count: Int
        var payload: Payload
        var cumulativeCount: Int
    }

    struct Block: Equatable {
        var basePrimary: Int
        var runs: [Run]

        var lastRunCount: Int { runs.last?.cumulativeCount ?? 0 }
        var upperBound: Int { basePrimary + lastRunCount }
    }

    private(set) var blocks: [Block] = []
    var length: Int { blocks.last?.upperBound ?? 0 }

    init() {}

    private static func findBlock(forGlobalIndex index: Int, in blocks: [Block]) -> Int {
        var low = 0, high = blocks.count - 1
        while low < high {
            let mid = low + (high - low) / 2
            if blocks[mid].upperBound <= index {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func findBlock(forGlobalIndex index: Int) -> Int {
        Self.findBlock(forGlobalIndex: index, in: blocks)
    }

    private func findRun(in block: Block, forRelativeIndex index: Int) -> Int {
        var low = 0, high = block.runs.count - 1
        while low < high {
            let mid = low + (high - low) / 2
            if block.runs[mid].cumulativeCount <= index {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Returns the payload at a given global index.
    func get(index: Int) -> Payload {
        precondition(index >= 0 && index < length, "index out of bounds")
        let blockIdx = findBlock(forGlobalIndex: index)
        let block = blocks[blockIdx]
        let relativeIndex = index - block.basePrimary
        let runIdx = findRun(in: block, forRelativeIndex: relativeIndex)
        return block.runs[runIdx].payload
    }

    private func getRun(at index: Int) -> (payload: Payload, count: Int) {
        precondition(index >= 0 && index < length, "index out of bounds")
        let blockIdx = findBlock(forGlobalIndex: index)
        let block = blocks[blockIdx]
        let relativeIndex = index - block.basePrimary
        let runIdx = findRun(in: block, forRelativeIndex: relativeIndex)
        let run = block.runs[runIdx]
        let runStart = run.cumulativeCount - run.count
        let offsetInRun = relativeIndex - runStart
        return (run.payload, run.count - offsetInRun)
    }

    /// Returns an iterator over (payload, count) sub‑runs within the given global range.
    func runIterator(in globalRange: Range<Int>) -> AnyIterator<(payload: Payload, count: Int)> {
        var currentIndex = globalRange.lowerBound
        return AnyIterator { () -> (payload: Payload, count: Int)? in
            guard currentIndex < globalRange.upperBound else {
                return nil
            }
            let (payload, remainingInRun) = self.getRun(at: currentIndex)
            let remainingInRange = globalRange.upperBound - currentIndex
            let emitCount = Swift.min(remainingInRun, remainingInRange)
            let result = (payload: payload, count: emitCount)
            currentIndex += emitCount
            return result
        }
    }

    /// Deletes the last `deleteCount` elements.
    mutating func deleteFromEnd(count deleteCount: Int) {
        precondition(deleteCount >= 0 && deleteCount <= length, "delete count out of bounds")
        let newGlobal = length - deleteCount
        if newGlobal == 0 {
            blocks.removeAll()
            return
        }
        let blockIdx = Self.findBlock(forGlobalIndex: newGlobal - 1, in: blocks)
        blocks.removeSubrange((blockIdx + 1)..<blocks.count)
        var block = blocks[blockIdx]
        let relativeKeep = newGlobal - block.basePrimary
        if relativeKeep == block.lastRunCount {
            blocks[blockIdx] = block
            return
        }
        let runIdx = findRun(in: block, forRelativeIndex: relativeKeep - 1)
        let prevPrimary = runIdx == 0 ? 0 : block.runs[runIdx - 1].cumulativeCount
        var run = block.runs[runIdx]
        let keepInRun = relativeKeep - prevPrimary
        run.count = keepInRun
        run.cumulativeCount = prevPrimary + keepInRun
        block.runs[runIdx] = run
        block.runs.removeSubrange((runIdx + 1)..<block.runs.count)
        blocks[blockIdx] = block
    }

    /// Merges a new block into the last one if payloads match, or appends it.
    mutating func appendBlock(_ newBlock: Block) {
        if var lastBlock = blocks.popLast() {
            if let lastRun = lastBlock.runs.last,
               let firstNewRun = newBlock.runs.first,
               lastRun.payload == firstNewRun.payload
            {
                // merge first run
                var merged = lastRun
                merged.count += firstNewRun.count
                merged.cumulativeCount += firstNewRun.count
                lastBlock.runs[lastBlock.runs.count - 1] = merged

                // append the rest
                var currentPrimary = merged.cumulativeCount
                for run in newBlock.runs.dropFirst() {
                    var r = run
                    r.cumulativeCount = currentPrimary + run.count
                    currentPrimary = r.cumulativeCount
                    lastBlock.runs.append(r)
                }
                blocks.append(lastBlock)
            } else {
                blocks.append(lastBlock)
                blocks.append(newBlock)
            }
        } else {
            blocks.append(newBlock)
        }
    }

    /// Fast‑path: append another map’s blocks.
    mutating func append(other: SegmentMap<Payload>) {
        let primaryOffset = self.length
        for var block in other.blocks {
            block.basePrimary += primaryOffset
            appendBlock(block)
        }
    }

    mutating func append(count: Int, payload: Payload) {
        precondition(count >= 0, "count must be >= 0")
        if blocks.isEmpty {
            blocks.append(Block(basePrimary: 0, runs: []))
        }
        var lastBlock = blocks.removeLast()
        if let lastRun = lastBlock.runs.last, lastRun.payload == payload {
            var merged = lastRun
            merged.count += count
            merged.cumulativeCount += count
            lastBlock.runs[lastBlock.runs.count - 1] = merged
        } else {
            let prevPrimary = lastBlock.runs.last?.cumulativeCount ?? 0
            lastBlock.runs.append(
                Run(count: count, payload: payload, cumulativeCount: prevPrimary + count)
            )
        }
        blocks.append(lastBlock)
    }

    /// Returns a new map containing only the elements in `subrange`,
    /// re-indexed to start at zero.
    subscript(_ subrange: Range<Int>) -> SegmentMap<Payload> {
        precondition(
            subrange.lowerBound >= 0 && subrange.upperBound <= length,
            "range out of bounds"
        )
        if subrange.lowerBound == 0 && subrange.upperBound == length {
            return self
        }
        var slice = SegmentMap<Payload>()
        for (payload, count) in runIterator(in: subrange) {
            slice.append(count: count,
                         payload: payload)
        }
        return slice
    }
}

extension SegmentMap: Sequence {
    typealias Element = (payload: Payload, count: Int)

    func makeIterator() -> AnyIterator<Element> {
        return runIterator(in: 0..<length)
    }
}

extension SegmentMap {
    func map(_ transform: (Payload) -> Payload) -> SegmentMap<Payload> {
        var result = SegmentMap<Payload>()
        for (payload, count) in runIterator(in: 0..<length) {
            result.append(count: count, payload: transform(payload))
        }
        return result
    }

    func flatMap(_ transform: (Payload, Int, Int) -> ([(Payload, Int)])) -> SegmentMap<Payload> {
        var result = SegmentMap<Payload>()
        var i = 0
        for (payload, count) in runIterator(in: 0..<length) {
            let newSegments = transform(payload, count, i)
            i += count
            for (newPayload, newCount) in newSegments {
                result.append(count: newCount, payload: newPayload)
            }
        }
        return result
    }
}
