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
    var acceptedLines = [AbsResultRange]()

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

    // Copy state from another updater for refining search.
    // This allows the new updater to continue from where the previous one left off.
    func copyStateForRefining(from other: FilteringUpdater) {
        lastPosition = other.lastPosition
        context = other.context.copy()
        stopAt = other.stopAt
        lastY = other.lastY
        acceptedLines = other.acceptedLines
    }

    func haveMatch(at resultRange: ResultRange) -> Bool {
        let context = FindContext()
        let start = lineBuffer.positionForStart(of: resultRange)
        lineBuffer.prepareToSearch(for: query,
                                   startingAt: start,
                                   options: [],
                                   mode: mode,
                                   with: context)
        lineBuffer.findSubstring(context, stopAt: start.advanced(by: resultRange.length))
        return context.status == .Matched
    }

    // Used to determine if we need to back up to the start of the last line after doing a search.
    private struct BackupInfo {
        var lastLineStartCoord: VT100GridCoord
        private let lineBuffer: LineBuffer
        private let context: FindContext
        private let width: Int32

        init?(lineBuffer: LineBuffer,
              context: FindContext,
              width: Int32,
              computedStopAt: LineBufferPosition) {
            if !lineBuffer.isPartial() {
                return nil
            }
            self.lineBuffer = lineBuffer
            self.width = width
            self.context = context

            let startPosition = lineBuffer.position(of: context, width: width)
            let lastLineStartPosition = lineBuffer.positionForStartOfLastLine(before: computedStopAt)
            let lastLineStartCoord = lineBuffer.coordinate(for: lastLineStartPosition,
                                                           width: width,
                                                           extendsRight: false,
                                                           ok: nil)
            let startingCoord = lineBuffer.coordinate(for: startPosition,
                                                      width: width,
                                                      extendsRight: false,
                                                      ok: nil)
            let startedBeforeStartOfLastLine = startingCoord <= lastLineStartCoord
            if !startedBeforeStartOfLastLine {
                return nil
            }
            self.lastLineStartCoord = lastLineStartCoord
        }

        var shouldBackUp: Bool {
            let endingPosition = lineBuffer.position(of: context, width: width)
            let endingCoord = lineBuffer.coordinate(for: endingPosition,
                                                    width: width,
                                                    extendsRight: false,
                                                    ok: nil)
            let endedAfterStartOfLastLine = endingCoord > lastLineStartCoord
            return endedAfterStartOfLastLine
        }
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

        let backupInfo = BackupInfo(lineBuffer: lineBuffer,
                                    context: context,
                                    width: width,
                                    computedStopAt: computedStopAt)
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
                lastY = range.yEnd
            }
            context.results?.removeAllObjects()
        case .Searching, .NotFound:
            DLog("\(hexAddress): FilteringUpdater: update: status != Matched")
            break
        @unknown default:
            it_fatalError()
        }
        if backupInfo?.shouldBackUp == true {
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
            it_fatalError()
        }
    }
}

@objc(iTermFilterDestination)
protocol FilterDestination {
    @objc(filterDestinationAppendScreenCharArray:)
    func append(_ sca: ScreenCharArray)

    @objc(filterDestinationRemoveLastLine)
    func removeLastLine()
}

@objc(iTermAsyncFilter)
class AsyncFilter: NSObject {
    // MARK: - State Machine Types

    private typealias PendingDeliveries = FIFOQueue<(ScreenCharArray, iTermImmutableMetadata)>
    private typealias BoxedPendingDeliveries = Box<PendingDeliveries>

    /// Context for the catchUp phase when refining a previous filter.
    /// During catchUp, we verify that lines accepted by the previous filter
    /// still match the new (more restrictive) query.
    private struct CatchUpContext {
        /// Lines accepted by the previous filter that need to be re-verified.
        var entries: [FilteringUpdater.AbsResultRange]

        /// Current position in `entries` being processed.
        var index: Int

        /// Number of characters dropped from the line buffer, used to convert
        /// absolute positions to relative positions for searching.
        var offset: Int64

        /// Lines from `entries` that have been verified to match the new query.
        var verified: [FilteringUpdater.AbsResultRange]

        /// Lines delivered while catchUp is in progress. These are queued and
        /// processed after catchUp completes to avoid interleaving. Boxed to
        /// avoid copy-on-write overhead when extracting from enum associated values.
        var pendingDeliveries: BoxedPendingDeliveries

        var isDone: Bool { index >= entries.count }

        mutating func nextEntry() -> FilteringUpdater.AbsResultRange? {
            guard index < entries.count else { return nil }
            let entry = entries[index]
            index += 1
            return entry
        }
    }

    private enum State: CustomStringConvertible {
        case idle
        case catchingUp(CatchUpContext)
        case drainingPendingDeliveries(BoxedPendingDeliveries)
        case searching
        case completed
        case cancelled

        var description: String {
            switch self {
            case .idle: return "idle"
            case .catchingUp: return "catchingUp"
            case .drainingPendingDeliveries: return "drainingPendingDeliveries"
            case .searching: return "searching"
            case .completed: return "completed"
            case .cancelled: return "cancelled"
            }
        }
    }

    // MARK: - Properties

    private var timer: Timer? = nil
    private let progress: ((Double) -> (Void))?
    private let cadence: TimeInterval
    private let query: String
    @objc let mode: iTermFindMode
    private var updater: FilteringUpdater
    private var state: State = .idle
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

    // MARK: - Test Support

    /// Called when the filter transitions to .completed state. For testing only.
    var onComplete: (() -> Void)?

    /// Synchronously process all pending work until completion. For testing only.
    /// This bypasses the timer and processes everything immediately.
    func syncProcessToCompletion() {
        while callUpdater() { }
    }

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
        self.mode = mode
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
        let sca = lineBufferCopy.rawLine(atWrappedLine: lineNumber, width: width)
        sca.makeSafe()
        destination.append(sca)
    }

    @objc func start() {
        guard case .idle = state else {
            it_fatalError("start() called in state \(state)")
        }
        DLog("\(it_addressString): AsyncFilter: Start")

        progress?(0)

        // Refinement optimization: if the new query contains the old query as a substring,
        // we only need to re-verify previously matched lines rather than searching from scratch.
        // This only works for literal searches - for regex, substring containment doesn't imply
        // the new pattern matches a subset of the old pattern's matches.
        let canRefine = !iTermFilterModeIsRegularExpression(mode) &&
                        refiningUpdater != nil &&
                        query.range(of: refiningUpdater!.query) != nil
        if canRefine, let refiningUpdater {
            DLog("\(it_addressString): Catch up")
            // If the refining filter's last line was temporary, remove it now.
            // We do this once at the start rather than in addFilterResult because
            // during catchUp the first line we add isn't necessarily a replacement
            // for the temporary line.
            if lastLineIsTemporary {
                DLog("\(it_addressString): Catch up: removing refining filter's temporary last line")
                destination.removeLastLine()
                lastLineIsTemporary = false
            }
            updater.copyStateForRefining(from: refiningUpdater)

            let context = CatchUpContext(
                entries: refiningUpdater.acceptedLines,
                index: 0,
                offset: lineBufferCopy.numberOfDroppedChars,
                verified: [],
                pendingDeliveries: Box(FIFOQueue())
            )
            state = .catchingUp(context)
        } else {
            state = .searching
        }
        self.refiningUpdater = nil

        timer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true) { [weak self] _ in
            self?.timerFired()
        }
        timerFired()
    }

    @objc func cancel() {
        DLog("\(it_addressString): AsyncFilter: Cancel, was \(state)")
        timer?.invalidate()
        timer = nil
        state = .cancelled
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

    private func timerFired() {
        switch state {
        case .idle, .completed, .cancelled:
            return
        case .catchingUp, .drainingPendingDeliveries, .searching:
            break
        }

        DLog("\(it_addressString): AsyncFilter: timer fired")
        let needsUpdate = loopForDuration(0.01) {
            return callUpdater()
        }

        if !needsUpdate {
            progress?(1)
            timer?.invalidate()
            DLog("\(it_addressString): AsyncFilter: invalidates timer")
            timer = nil
        } else {
            DLog("\(it_addressString): AsyncFilter: keep timer")
            progress?(updater.progress)
        }
    }
}

extension AsyncFilter: ContentSubscriber {
    func deliver(_ array: ScreenCharArray, metadata: iTermImmutableMetadata, lineBufferGeneration: Int64) {
        switch state {
        case .idle, .cancelled:
            return

        case .catchingUp(let context):
            DLog("\(it_addressString): AsyncFilter: deliver: queuing delivery during catchUp, generation=\(lineBufferGeneration)")
            context.pendingDeliveries.value.enqueue((array, metadata))

        case .drainingPendingDeliveries(let pending):
            pending.value.enqueue((array, metadata))

        case .searching, .completed:
            // In .completed state, we still process new content as it arrives.
            // The filter keeps running until cancelled.
            appendToLineBuffer(array, metadata: metadata)
            DLog("\(it_addressString): AsyncFilter: deliver: append line. Last position is now \(lineBufferCopy.lastPosition().description)")
            ensureTimerRunning()
        }
    }

    private func ensureTimerRunning() {
        if timer != nil {
            return
        }
        state = .searching
        timer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true) { [weak self] _ in
            self?.timerFired()
        }
        timerFired()
    }

    private func appendToLineBuffer(_ array: ScreenCharArray, metadata: iTermImmutableMetadata) {
        lineBufferCopy.appendLine(array.line,
                                  length: array.length,
                                  partial: array.eol != EOL_HARD,
                                  width: width,
                                  metadata: metadata,
                                  continuation: array.continuation)
        updater.didAppendToLineBuffer()
    }

    private func callUpdater() -> Bool {
        if lastLineIsTemporary {
            DLog("\(it_addressString): AsyncFilter: callUpdater: Removing previous line before updating")
            destination.removeLastLine()
            lastLineIsTemporary = false
        }

        switch state {
        case .idle, .cancelled:
            return false

        case .catchingUp(var context):
            if let absResultRange = context.nextEntry() {
                // Process one catchUp entry
                if let resultRange = absResultRange.resultRange(offset: context.offset),
                   updater.haveMatch(at: resultRange) {
                    context.verified.append(absResultRange)
                    if let range = lineBufferCopy.convertPositions([resultRange], withWidth: width)?.first {
                        addFilterResult(range.yStart, temporary: false)
                    }
                }
                state = .catchingUp(context)
                return true
            } else {
                // CatchUp complete - update acceptedLines with verified matches
                updater.acceptedLines = context.verified

                // Transition to next state
                if context.pendingDeliveries.value.isEmpty {
                    state = .searching
                } else {
                    state = .drainingPendingDeliveries(context.pendingDeliveries)
                }
                return callUpdater()
            }

        case .drainingPendingDeliveries(let pending):
            if let (array, metadata) = pending.value.dequeue() {
                appendToLineBuffer(array, metadata: metadata)
                if pending.value.isEmpty {
                    state = .searching
                }
                return true
            }
            state = .searching
            return callUpdater()

        case .searching:
            let moreWork = updater.update()
            if !moreWork {
                state = .completed
                onComplete?()
            }
            return moreWork

        case .completed:
            // Already completed - no more work to do
            return false
        }
    }

    func updateMetadata(selectedCommandRange: NSRange, cumulativeOverflow: Int64) {
        DLog("\(it_addressString): AsyncFilter: updateMetadata: selectedCommandRange<-\(selectedCommandRange), cumulativeOverflow=\(cumulativeOverflow)")
        updater.updateMetadata(absLineRange: Range(selectedCommandRange)!,
                               cumulativeOverflow: cumulativeOverflow)
    }
}

