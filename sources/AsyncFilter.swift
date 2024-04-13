//
//  AsyncFilter.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/30/21.
//

import Foundation

protocol HexAddressFormatting {
    var hexAddress: String { get }
}

extension HexAddressFormatting {
    var hexAddress: String {
        return String(format: "%p", unsafeBitCast(self, to: Int.self))
    }
}

class FilteringUpdater: HexAddressFormatting {
    var accept: ((Int32, Bool) -> (Void))? = nil
    private let lineBuffer: LineBuffer
    private let count: Int32
    private var context: FindContext
    private var stopAt: LineBufferPosition
    private let width: Int32
    private let mode: iTermFindMode
    let query: String
    private var lastY = Int32(-1)
    private var lastPosition: LineBufferPosition? = nil

    // If count is zero then ignore this. Otherwise only consider these
    // absolute line numbers in lineBuffer, calculated at the current width and
    // cumulativeOverflow.
    private var absLineRange: Range<Int64>
    private var cumulativeOverflow: Int64

    // ResultRange is used for search results but because it doesn't use
    // absolute line numbers it's fragile. This is an absolute line
    // number-based alternative. It's used when refining results to avoid having
    // to search the entire buffer.
    struct AbsResultRange {
        var absPosition: Int64
        var length: Int32

        init(_ resultRange: ResultRange, offset: Int64) {
            absPosition = Int64(resultRange.position) + offset
            length = resultRange.length
        }

        func resultRange(offset: Int64) -> ResultRange? {
            if absPosition < offset {
                return nil
            }
            return ResultRange(position: Int32(absPosition - offset), length: length)
        }
    }

    // Lines that have matched. Does not include temporary matches.
    private(set) var acceptedLines = [AbsResultRange]()

    private static func stopPosition(lineBuffer: LineBuffer,
                                     absLineRange: Range<Int64>,
                                     cumulativeOverflow: Int64,
                                     width: Int32) -> LineBufferPosition {
        if absLineRange.count == 0 {
            return lineBuffer.lastPosition()
        }
        let stopCoord = VT100GridCoord(x: 0,
                                       y: Int32(absLineRange.upperBound - cumulativeOverflow))
        let result = lineBuffer.position(forCoordinate: stopCoord,
                                   width: width,
                                   offset: 0) ?? lineBuffer.lastPosition()
        if result.yOffset > 0 {
            if result.compare(lineBuffer.lastPosition()) == .orderedDescending {
                return lineBuffer.lastPosition()
            }
            DLog("Got a yoffset")
        }
        return result
    }

    init(query: String,
         lineBuffer: LineBuffer,
         count: Int32,
         width: Int32,
         mode: iTermFindMode,
         absLineRange: Range<Int64>,
         cumulativeOverflow: Int64) {
        self.lineBuffer = lineBuffer
        self.count = count
        self.width = Int32(width)
        self.mode = mode
        self.query = query
        self.absLineRange = absLineRange
        self.cumulativeOverflow = cumulativeOverflow
        context = FindContext()
        stopAt = FilteringUpdater.stopPosition(lineBuffer: lineBuffer,
                                               absLineRange: absLineRange,
                                               cumulativeOverflow: cumulativeOverflow,
                                               width: width)
        DLog("\(hexAddress): FilteringUpdater: Initialize with query=\(query) absLineRange=\(absLineRange)")
        if absLineRange.count == 0 {
            begin(at: lineBuffer.firstPosition())
        } else {
            let startCoord = VT100GridCoord(x: 0,
                                            y: Int32(absLineRange.lowerBound - cumulativeOverflow))
            let startPosition = lineBuffer.position(forCoordinate: startCoord, 
                                                    width: width,
                                                    offset: 0) ?? lineBuffer.firstPosition()
            begin(at: startPosition)
        }
    }

    func updateMetadata(absLineRange: Range<Int64>, cumulativeOverflow: Int64) {
        self.cumulativeOverflow = cumulativeOverflow
        self.absLineRange = absLineRange
        if absLineRange.count > 0 {
            stopAt = computedStopAt
        }
    }

    private var computedStopAt: LineBufferPosition {
        FilteringUpdater.stopPosition(lineBuffer: lineBuffer,
                                               absLineRange: absLineRange,
                                               cumulativeOverflow: cumulativeOverflow,
                                               width: width)
    }

    private func begin(at startPosition: LineBufferPosition) {
        DLog("\(hexAddress): FilteringUpdater: begin(startPosition=\(startPosition.description)")
        context = FindContext()
        stopAt = computedStopAt
        lineBuffer.prepareToSearch(for: query,
                                   startingAt: startPosition,
                                   options: [.multipleResults, .oneResultPerRawLine, .optEmptyQueryMatches],
                                   mode: mode,
                                   with: context)
    }

    var progress: Double {
        return min(1.0, Double(max(0, lastY)) / Double(count))
    }

    func didAppendToLineBuffer() {
        if lastPosition != nil && ![.Searching, .Matched].contains(context.status) {
            // Ensure the next call to update() is able to continue searching even though the last
            // search did not return any results.

            DLog("\(hexAddress): didAppendToLineBuffer: set context status to .Searching")
            context.status = .Searching
        } else {
            DLog("\(hexAddress): didAppendToLineBuffer: no change to context status made")
        }
    }

    // Bring in matching results by using the saved ranges from an existing FilteringUpdater that
    // had a broader query. This is usually faster than starting from scratch.
    func catchUp(other: FilteringUpdater) {
        acceptedLines = other.acceptedLines
        lastPosition = other.lastPosition
        context = other.context.copy()
        stopAt = other.stopAt
        lastY = other.lastY

        let offset = lineBuffer.numberOfDroppedChars
        for absResultRange in acceptedLines {
            if let resultRange = absResultRange.resultRange(offset: offset),
               haveMatch(at: resultRange) {
                if let range = lineBuffer.convertPositions([resultRange], withWidth: width)?.first {
                    accept?(range.yStart, false)
                }
            }
        }
    }

    private func haveMatch(at resultRange: ResultRange) -> Bool {
        let context = FindContext()
        let start = lineBuffer.positionForStart(of: resultRange)
        lineBuffer.prepareToSearch(for: query,
                                   startingAt: start,
                                   options: [.oneResultPerRawLine, .optEmptyQueryMatches],
                                   mode: mode,
                                   with: context)
        lineBuffer.findSubstring(context, stopAt: start.advanced(by: resultRange.length))
        return context.status == .Matched
    }

    func update() -> Bool {
        DLog("\(hexAddress): FilteringUpdater: update")
        if let lastPosition {
            DLog("\(hexAddress): FilteringUpdater: update: has lastPosition")
            begin(at: lastPosition)
            self.lastPosition = nil
        }
        guard context.status == .Searching || context.status == .Matched else {
            DLog("\(hexAddress): FilteringUpdater: update: Finished last time. Set last position to \(computedStopAt.description)")
            self.lastPosition = computedStopAt
            return false
        }
        DLog("\(hexAddress): FilteringUpdater: update: perform search starting at \(lineBuffer.position(of: context, width: width).description), stopping at \(stopAt.description))")
        var needsToBackUp = false
        lineBuffer.findSubstring(context, stopAt: stopAt)
        switch context.status {
        case .Matched:
            DLog("\(hexAddress): FilteringUpdater: update: status == Matched")
            let resultRanges = context.results as! [ResultRange]
            let expandedResultRanges = NSMutableArray(array: [ResultRange]())
            let positions = lineBuffer.convertPositions(resultRanges,
                                                        expandedResultRanges: expandedResultRanges,
                                                        withWidth: width) ?? []
            let numberOfDroppedChars = lineBuffer.numberOfDroppedChars
            for (i, range) in positions.enumerated() {
                let temporary = range === positions.last && context.includesPartialLastLine
                DLog("\(hexAddress): FilteringUpdater: update: add \(range.description), temporary=\(temporary), position=\(Int64(resultRanges[i].position) + lineBuffer.numberOfDroppedChars)")
                accept?(range.yStart, temporary)
                if !temporary {
                    acceptedLines.append(AbsResultRange(expandedResultRanges[i] as! ResultRange,
                                                        offset: numberOfDroppedChars))
                }
                if temporary && !needsToBackUp {
                    DLog("\(hexAddress): FilteringUpdater: update: Set needsToBackUp to true")
                    needsToBackUp = true
                }
                lastY = range.yEnd
            }
            context.results.removeAllObjects()
        case .Searching, .NotFound:
            DLog("\(hexAddress): FilteringUpdater: update: status != Matched")
            break
        @unknown default:
            fatalError()
        }
        if needsToBackUp {
            // We know we searched the last line so prepare to search again from the beginning
            // of the last line next time.
            lastPosition = lineBuffer.positionForStartOfLastLine(before: computedStopAt)
            DLog("\(hexAddress): FilteringUpdater: update: Back up to \(String(describing: lastPosition))")
            return false
        }
        DLog("status is \(context.status.rawValue)")
        switch context.status {
        case .NotFound:
            DLog("\(hexAddress): FilteringUpdater: update: Move to end position of \(stopAt) and return false")
            DLog("Set last position to end of buffer")
            lastPosition = stopAt
            return false
        case .Matched, .Searching:
            DLog("\(hexAddress): FilteringUpdater: update: Return true to keep searching")
            return true
        @unknown default:
            fatalError()
        }
    }
}

@objc(iTermFilterDestination)
protocol FilterDestination {
    @objc(filterDestinationAppendCharacters:count:externalAttributeIndex:continuation:)
    func append(_ characters: UnsafePointer<screen_char_t>,
                count: Int32,
                externalAttributeIndex: iTermExternalAttributeIndexReading?,
                continuation: screen_char_t)

    @objc(filterDestinationRemoveLastLine)
    func removeLastLine()
}

@objc(iTermAsyncFilter)
class AsyncFilter: NSObject {
    private var timer: Timer? = nil
    private let progress: ((Double) -> (Void))?
    private let cadence: TimeInterval
    private let query: String
    private var updater: FilteringUpdater
    private var started = false
    private let lineBufferCopy: LineBuffer
    private let width: Int32
    private let destination: FilterDestination
    private var lastLineIsTemporary: Bool
    // There's a race between line buffers updating and getting content notifications at the time
    // the line buffer is first copied. We keep track of the line buffer's generation at that time
    // so we can ignore any content notifications for changes that were already present. This avoids
    // duplicate lines of output.
    private let initialLineBufferGeneration: Int64
    private var refiningUpdater: FilteringUpdater?

    @objc(initWithQuery:lineBuffer:grid:mode:destination:cadence:refining:absLineRange:cumulativeOverflow:progress:)
    init(query: String,
         lineBuffer: LineBuffer,
         grid: VT100Grid,
         mode: iTermFindMode,
         destination: FilterDestination,
         cadence: TimeInterval,
         refining: AsyncFilter?,
         absLineRange: NSRange,
         cumulativeOverflow: Int64,
         progress: ((Double) -> (Void))?) {
        if let refining {
            initialLineBufferGeneration = refining.initialLineBufferGeneration
        } else {
            initialLineBufferGeneration = lineBuffer.generation
        }
        lineBufferCopy = lineBuffer.copy()
        lineBufferCopy.setMaxLines(-1)
        grid.appendLines(grid.numberOfLinesUsed(), to: lineBufferCopy, makeCursorLineSoft: true)
        let numberOfLines = lineBufferCopy.numLines(withWidth: grid.size.width)
        let width = grid.size.width
        self.width = width
        self.cadence = cadence
        self.progress = progress
        self.query = query
        self.destination = destination
        updater = FilteringUpdater(query: query,
                                   lineBuffer: lineBufferCopy,
                                   count: numberOfLines,
                                   width: width,
                                   mode: mode,
                                   absLineRange: Range(absLineRange)!,
                                   cumulativeOverflow: cumulativeOverflow)

        lastLineIsTemporary = refining?.lastLineIsTemporary ?? false
        super.init()

        DLog("\(it_addressString): AsyncFilter: Initialize with updater \(updater.hexAddress), initial generation=\(initialLineBufferGeneration)")
        updater.accept = { [weak self] (lineNumber: Int32, temporary: Bool) in
            self?.addFilterResult(lineNumber, temporary: temporary)
        }
        refiningUpdater = refining?.updater
    }

    private func addFilterResult(_ lineNumber: Int32, temporary: Bool) {
        DLog("\(it_addressString): AsyncFilter: addFilterResult on line \(lineNumber), temporary=\(temporary), lastLineIsTemporary=\(lastLineIsTemporary), text=\(lineBufferCopy.screenCharArray(forLine: lineNumber, width: width, paddedTo: -1, eligibleForDWC: false))")
        if lastLineIsTemporary {
            DLog("\(it_addressString): AsyncFilter: addFilterResult: Removing previous line before appending")
            destination.removeLastLine()
        }
        lastLineIsTemporary = temporary
        let chars = lineBufferCopy.rawLine(atWrappedLine: lineNumber, width: width)
        let metadata = lineBufferCopy.metadataForRawLine(withWrappedLineNumber: lineNumber,
                                                         width: width)
        destination.append(chars.line,
                           count: chars.length,
                           externalAttributeIndex: iTermImmutableMetadataGetExternalAttributesIndex(metadata),
                           continuation: chars.continuation)
    }

    @objc func start() {
        DLog("\(it_addressString): AsyncFilter: Start")
        precondition(!started)
        started = true
        progress?(0)
        if let refiningUpdater, query.range(of: refiningUpdater.query) != nil {
            DLog("\(it_addressString): Catch up")
            updater.catchUp(other: refiningUpdater)
        }
        self.refiningUpdater = nil
        timer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true, block: { [weak self] timer in
            self?.update()
        })

        update()
    }


    @objc func cancel() {
        DLog("\(it_addressString): AsyncFilter: Cancel")
        timer?.invalidate()
        timer = nil
    }

    /// `block` returns whether to keep going. Return true to continue or false to break.
    /// Returns true if it ran out of time, false if block returned false
    private func loopForDuration(_ duration: TimeInterval, block: () -> Bool) -> Bool {
        let startTime = NSDate.it_timeSinceBoot()
        DLog("\(it_addressString): AsyncFilter: begin timed updated")
        while NSDate.it_timeSinceBoot() - startTime < duration {
            if !block() {
                return false
            }
        }
        DLog("\(it_addressString): AsyncFilter: end timed updated")
        return true
    }

    private func update() {
        DLog("\(it_addressString): AsyncFilter: timer fired")
        DLog("AsyncFilter\(self): Timer fired")
        let needsUpdate = loopForDuration(0.01) {
            DLog("AsyncFilter: Update")
            return updater.update()
        }
        if !needsUpdate {
            progress?(1)
            timer?.invalidate()
            DLog("\(it_addressString): AsyncFilter: invalidates timer")
            DLog("don't need an update")
            timer = nil
        } else {
            DLog("\(it_addressString): AsyncFilter: keep timer")
            progress?(updater.progress)
        }
    }
}

extension AsyncFilter: ContentSubscriber {
    func deliver(_ array: ScreenCharArray, metadata: iTermImmutableMetadata, lineBufferGeneration: Int64) {
        if lineBufferGeneration <= initialLineBufferGeneration {
            DLog("\(it_addressString): AsyncFilter: deliver: ignore update to append \(array.debugStringValue) at generation \(lineBufferGeneration) <= initial generation of \(initialLineBufferGeneration)")
            return
        }
        lineBufferCopy.appendLine(array.line,
                                  length: array.length,
                                  partial: array.eol != EOL_HARD,
                                  width: width,
                                  metadata: metadata,
                                  continuation: array.continuation)
        updater.didAppendToLineBuffer()
        DLog("\(it_addressString): AsyncFilter: deliver: generation=\(lineBufferGeneration) append line to lineBuffer \(array.debugStringValue). Last position is now \(lineBufferCopy.lastPosition().description)")
        if timer != nil {
            return
        }
        while updater.update() { }
    }

    func updateMetadata(selectedCommandRange: NSRange, cumulativeOverflow: Int64) {
        DLog("\(it_addressString): AsyncFilter: updateMetadata: selectedCommandRange<-\(selectedCommandRange), cumulativeOverflow=\(cumulativeOverflow)")
        updater.updateMetadata(absLineRange: Range(selectedCommandRange)!,
                               cumulativeOverflow: cumulativeOverflow)
    }
}

