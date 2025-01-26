//
//  SearchEngine.swift
//  iTerm2
//
//  Created by George Nachman on 10/17/24.
//

func _SELog(_ messageBlock: () -> String, file: String, line: Int, function: String) {
#if DEBUG_SEARCH_ENGINE
    print("\(file):\(line) \(function): \(messageBlock())")
#else
    guard gDebugLogging.boolValue else {
        return
    }
    let message = messageBlock()
    DebugLogImpl(file.cString(using: .utf8), Int32(line), function.cString(using: .utf8), message)
#endif
}

func SELog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
    _SELog(messageBlock, file: file, line: line, function: function)
}

// Describes what and how to search for a substring/regex in a session.
// This is the "builder" interface exposed to Objective C. SearchRequest is
// generally a better data type for the same purpose but it is Swift-only.
@objc(iTermSearchRequest)
class iTermSearchRequest: NSObject {
    private var query: String
    private var mode: iTermFindMode
    private var startCoord: VT100GridCoord
    private var offset: Int32
    private var options: FindOptions
    private var forceMainScreen: Bool
    private var startPosition: LineBufferPosition?
    private var absLineRange: Range<Int64>?
    private var maxQueueSize: Int?

    @objc
    init(query: String,
         mode: iTermFindMode,
         startCoord: VT100GridCoord,
         offset: Int32,
         options: FindOptions,
         forceMainScreen: Bool,
         startPosition: LineBufferPosition?) {
        self.query = query
        self.mode = mode
        self.startCoord = startCoord
        self.offset = offset
        self.options = options
        self.forceMainScreen = forceMainScreen
        self.startPosition = startPosition
    }

    func realize(dataSource: iTermSearchEngineDataSource) -> SearchRequest {
        let snapshot = dataSource.snapshot(forcingPrimaryGrid: forceMainScreen)
        let totalScrollbackOverflow = dataSource.totalScrollbackOverflow()
        let y = line(constraining: startCoord.y,
                     to: absLineRange,
                     overflow: totalScrollbackOverflow)
        let caseSensitivity: SearchRequest.CaseSensitivity = switch mode {
        case .caseInsensitiveRegex, .caseInsensitiveSubstring:
                .insensitive
        case .caseSensitiveRegex, .caseSensitiveSubstring:
                .sensitive
        case .smartCaseSensitivity:
            if query.rangeOfCharacter(from: .uppercaseLetters) != nil {
                .sensitive
            } else {
                .insensitive
            }
        @unknown default:
            it_fatalError()
        }

        let initialStart = {
            // startCoord could be out of bounds. Use a valid location for initialStart.
            let candidate = VT100GridAbsCoord(x: startCoord.x, y: totalScrollbackOverflow + Int64(y))
            guard snapshot.lineBuffer.position(forCoordinate: startCoord, width: snapshot.width(), offset: 0) != nil else {
                if startCoord.y < 0 {
                    DLog("Initial coordinate has negative y so use 0,0")
                    return VT100GridAbsCoord(x: 0, y: totalScrollbackOverflow)
                }
                DLog("Initial coordinate out of bounds so try to use penultimate.")
                var ok = ObjCBool(false)
                let lastCoord = snapshot.lineBuffer.coordinate(for: snapshot.lineBuffer.penultimatePosition(), width: snapshot.width(), extendsRight: false, ok: &ok)
                if (ok.boolValue) {
                    return VT100GridAbsCoordFromCoord(lastCoord, totalScrollbackOverflow)
                }
                DLog("Can't get coordinate of penultimate position so use the not-so-great initial coordinate")
                return candidate
            }
            return candidate
        }()

        let direction: SearchRequest.Direction = options.contains(.optBackwards) ? .backwards : .forwards
        let safeStartPosition: LineBufferPosition?

        // Ensure the start position we use is not before the actual start. This is a targeted hack
        // to fix a bug in tail search.
        if let startPosition, direction == .forwards, snapshot.lineBuffer.firstPosition().compare(startPosition) == .orderedDescending {
            safeStartPosition = snapshot.lineBuffer.firstPosition()
        } else {
            safeStartPosition = startPosition
        }
        return SearchRequest(
            absLineRange: absLineRange,
            direction: direction,
            regex: mode == .caseInsensitiveRegex || mode == .caseSensitiveRegex,
            query: query,
            caseSensitivity: caseSensitivity,
            wantMultipleResults: options.contains(.multipleResults),
            limitResultsToOnePerRawLine: options.contains(.oneResultPerRawLine),
            emptyQueryMatches: options.contains(.optEmptyQueryMatches),
            spanLines: options.contains(.optMultiLine),
            cumulativeOverflow: totalScrollbackOverflow,
            forceMainScreen: forceMainScreen,
            initialStart: initialStart,
            offset: offset,
            startPosition: safeStartPosition,
            maxQueueSize: maxQueueSize)
    }

    @nonobjc
    private func line(constraining y: Int32,
                      to absLineRange: Range<Int64>?,
                      overflow: Int64) -> Int32 {
        guard let absLineRange, !absLineRange.isEmpty, let closedRange = ClosedRange(absLineRange) else {
            return y
        }
        let proposed = closedRange.clamping(Int64(y) + overflow) - overflow
        return Int32(clamping: max(0, proposed))
    }

    @objc
    func setAbsLineRange(_ absLineRange: NSRange) {
        self.absLineRange = Range(absLineRange)
    }

    @objc
    func setMaxQueueSize(_ maxSize: Int) {
        self.maxQueueSize = maxSize
    }
}

// The preferred way to specify what to search for.
struct SearchRequest: CustomDebugStringConvertible {
    var debugDescription: String {
        var parts = [String]()

        if let absLineRange {
            parts.append("absLineRange=\(absLineRange)")
        }
        parts.append("\(direction)")
        if regex {
            parts.append("regex=\(regex)")
        }
        parts.append("query=\(query)")
        if caseSensitivity != .smart {
            parts.append("\(caseSensitivity)")
        }
        if !wantMultipleResults {
            parts.append("wantMultipleResults=\(wantMultipleResults)")
        }
        if limitResultsToOnePerRawLine {
            parts.append("limitResultsToOnePerRawLine=\(limitResultsToOnePerRawLine)")
        }
        if emptyQueryMatches {
            parts.append("emptyQueryMatches=\(emptyQueryMatches)")
        }
        if spanLines {
            parts.append("spanLines=\(spanLines)")
        }
        parts.append("cumulativeOverflow=\(cumulativeOverflow)")
        if forceMainScreen {
            parts.append("forceMainScreen=\(forceMainScreen)")
        }
        parts.append("initialStart=\(initialStart)")
        if offset != 0 {
            parts.append("offset=\(offset)")
        }
        if let startPosition {
            parts.append("startPosition=\(startPosition)")
        }
        if let maxQueueSize {
            parts.append("maxQueueSize=\(maxQueueSize)")
        }
        return "<SearchRequest \(parts.joined(separator: " "))>"
    }

    enum Direction {
        case forwards
        case backwards
    }
    enum CaseSensitivity {
        case sensitive
        case insensitive
        case smart
    }

    // If given, only search the specified absolute line numbers.
    var absLineRange: Range<Int64>?

    // Searching backwards is generally useful because the user spends most of their time at the end of the buffer.
    var direction: Direction

    // Is query a regex? If not it is a substring.
    var regex: Bool

    // The text to search for. Might be a regex.
    var query: String

    // How to do case folding when searching
    var caseSensitivity: CaseSensitivity

    // Do we only want a single result? I'm not sure why this would ever be false. It's quite old.
    var wantMultipleResults: Bool

    // Only one result per wrapped line? Useful if you just want a yes/no for each line, such as filtering.
    var limitResultsToOnePerRawLine: Bool

    // If the query is empty, will every line match it?
    var emptyQueryMatches: Bool

    // Support queries with newlines?
    var spanLines: Bool

    var cumulativeOverflow: Int64

    // Search the main screen even if alt screen is showing?
    var forceMainScreen: Bool = false

    // Where to begin, assuming startPosition is not specified.
    var initialStart: VT100GridAbsCoord

    // Offset relative to initialStart.
    var offset = Int32(0)

    // If specified, overrides initialStart for where to begin.
    var startPosition: LineBufferPosition?

    // Limits the number of results outstanding. Useful to avoid blocking the main queue when doing so is slow.
    var maxQueueSize: Int?
}

fileprivate extension SearchRequest {
    var findOptions: FindOptions {
        var result: FindOptions = []
        switch direction {
        case .backwards:
            result.insert(.optBackwards)
        case .forwards:
            break
        }

        if wantMultipleResults {
            result.insert(.multipleResults)
        }

        if limitResultsToOnePerRawLine {
            result.insert(.oneResultPerRawLine)
        }

        if emptyQueryMatches {
            result.insert(.optEmptyQueryMatches)
        }

        if spanLines {
            result.insert(.optMultiLine)
        }
        return result
    }

    var findMode: iTermFindMode {
        switch caseSensitivity {
        case .insensitive:
            return regex ? .caseInsensitiveRegex : .caseInsensitiveSubstring
        case .sensitive:
            return regex ? .caseSensitiveRegex : .caseSensitiveSubstring
        case .smart:
            return .smartCaseSensitivity
        }
    }

    private func position(forAbsCoord absCoord: VT100GridAbsCoord,
                          width: Int32,
                          overflow: Int64,
                          lineBuffer: LineBuffer,
                          offset: Int32 = 0) -> LineBufferPosition? {
        var ok = ObjCBool(false)
        let coord = VT100GridCoordFromAbsCoord(absCoord, overflow, &ok)
        guard ok.boolValue else {
            return nil
        }
        return lineBuffer.position(forCoordinate: coord, width: width, offset: offset)
    }

    func wrappedStartPosition(width: Int32,
                              cumulativeOverflow: Int64,
                              lineBuffer: LineBuffer) -> LineBufferPosition {
        guard let absLineRange, !absLineRange.isEmpty else {
            switch direction {
            case .forwards:
                SELog("New start position is first position")
                return lineBuffer.firstPosition()
            case .backwards:
                SELog("New start position is penultimate position")
                return lineBuffer.lastPosition().predecessor()
            }
        }
        let (x, absY, offset): (Int32, Int64, Int32) = switch direction {
        case .forwards:
            // First position in range
            (0, absLineRange.lowerBound, 0)
        case .backwards:
            // Last position in range
            (0, absLineRange.upperBound, -1)
        }
        let y = Swift.max(0, Int32(clamping: absY - cumulativeOverflow))
        SELog("New start position is \(x), \(y)")
        let position = lineBuffer.position(forCoordinate: VT100GridCoord(x: x, y: y),
                                           width: width,
                                           offset: offset)
        if let position {
            return position
        }
        // You can definitely get here when searching backwards because absLineRange.upperBound isn't a valid line number.
        switch direction {
        case .forwards:
            SELog("New start position is first position")
            return lineBuffer.firstPosition()
        case .backwards:
            SELog("New start position is penultimate position")
            return lineBuffer.lastPosition().predecessor()
        }
    }

    func startPosition(lineBuffer: LineBuffer, width: Int32, overflow: Int64) -> LineBufferPosition? {
        var coord = initialStart.relativeClamped(overflow: overflow)
        if let absLineRange {
            let relativeLineRange = Int32(clamping: max(0, absLineRange.lowerBound - overflow))..<Int32(clamping: max(0, absLineRange.upperBound - overflow))
            if !relativeLineRange.isEmpty {
                coord.y = ClosedRange(relativeLineRange).clamping(coord.y)
            }
        }
        let searchForwards = direction == .forwards
        let cumulativeOverflow = overflow
        let direction: Int32 = searchForwards ? 1 : -1
        guard let startPos = lineBuffer.position(forCoordinate: coord, width: width, offset: offset * direction) else {
            // x,y wasn't a real position in the line buffer, probably a null after the end.
            if searchForwards {
                SELog("Search from first position")
                return lineBuffer.firstPosition()
            }
            SELog("Search from last position")
            return lineBuffer.lastPosition().predecessor()
        }
        SELog("Search from \(startPos)")
        // Make sure startPos is not at or after the last cell in the line buffer.
        var startPosCoordOk = ObjCBool(false);
        let startPosCoord = lineBuffer.coordinate(for: startPos,
                                                  width: width,
                                                  extendsRight: true,
                                                  ok: &startPosCoordOk)
        let lastValidPosition = lineBuffer.penultimatePosition()
        if !startPosCoordOk.boolValue {
            return lastValidPosition
        }

        var lastValidCoordOk = ObjCBool(false)
        let lastValidCoord = lineBuffer.coordinate(for: lastValidPosition,
                                                   width: width,
                                                   extendsRight: true,
                                                   ok: &lastValidCoordOk)
        let lastPositionCoord = if let absLineRange, !absLineRange.isEmpty {
            VT100GridCoord(x: width - 1,
                           y: Int32(clamping: Swift.max(0,
                                                        absLineRange.upperBound - 1 - cumulativeOverflow)))
        } else {
            lastValidCoord
        }
        if startPosCoord >= lastPositionCoord {
            return lastValidPosition
        }
        if lastValidCoordOk.boolValue && startPosCoord > lastValidCoord {
            return lastValidPosition
        }
        return startPos
    }

    func stopPosition(lineBuffer: LineBuffer,
                      width: Int32,
                      overflow: Int64,
                      hasWrapped: Bool = false) -> LineBufferPosition? {
        let initialStartRel = initialStart.relative(overflow: overflow)
        let initialStartPosition: LineBufferPosition? = if let initialStartRel {
            lineBuffer.position(forCoordinate: initialStartRel, width: width, offset: 0)
        } else {
            nil
        }
        var stopAt = hasWrapped ? initialStartPosition : nil
        guard let absLineRange, !absLineRange.isEmpty else {
            if let stopAt {
                return stopAt
            }
            if direction == .forwards {
                SELog("Continue searching to the end")
                return lineBuffer.lastPosition()
            }
            SELog("Continue searching until the start")
            return lineBuffer.firstPosition()
        }
        if let stopAt {
            return stopAt
        }

        // Handle non-empty absLineRange
        let y = switch direction {
        case .forwards:
            Swift.max(0, Int32(clamping: absLineRange.upperBound - overflow))
        case .backwards:
                        Swift.max(0, Int32(clamping: absLineRange.lowerBound - overflow))
        }
        stopAt = lineBuffer.position(forCoordinate: VT100GridCoord(x: 0, y: y),
                                     width: width,
                                     offset: 0)
        if let stopAt {
            return stopAt
        }
        switch direction {
        case .forwards:
            SELog("Continue searching until the end")
            return lineBuffer.penultimatePosition()
        case .backwards:
            SELog("Continue searching until the start");
            return lineBuffer.firstPosition()
        }
    }
}

// What SearchEngine produces as output.
struct SearchEngineOutput {
    // Ranges matching the query.
    var results: [SearchResult]

    // The range of lines searched, but it's a lie because it always starts or
    // ends at the start/end of the buffer.
    var lineRange: Range<Int64>

    // The actual range of coordinates searched. Could be invalid coords if finished.
    var coordRange: VT100GridAbsCoordRange

    // 0-1, how done are we?
    var progress: Double

    // Where the search actually stopped.
    var lastLocationSearched: LineBufferPosition?

    // Are we all done? Other fields may be unset/empty/invalid, or be valid.
    var finished: Bool
}


// SearchOperation has the low level logic of performing a search. It runs on a given dispatch
// queue and its methods are expected to be called on that queue only, except as noted.
fileprivate class SearchOperation: Pausable {
    private let queue: DispatchQueue
    private var snapshot: TerminalContentSnapshot
    private(set) var request: SearchRequest
    private var context = FindContext()
    private(set) var positions: Positions
    private let resultQueue = ProducerConsumerQueue<SearchEngineOutput>()
    // Search operations are paused when the main thread gets synced with the mutation thread.
    // First, clients will drain all pending results. Then updateSnapshot is called. Finally,
    // search operations are unpaused to operate on the newly updated snapshot. This ensures
    // that results seen by the main thread match the screen state they see at all times.
    // The downside is that draining can be slow if there are a lot of results.
    // Clients can limit the size of result queues to mitigate this problem, although doing so
    // reduces the throughput of searching.
    private var pauseCount = 0
    private var lastLocationSearched: LineBufferPosition?

    // When we've already collected too many results, this will be true. We
    // won't resume searching until the result queue is under the max size.
    private var oversize = false

    enum State {
        // Don't have a request yet.
        case ready
        // Actively finding results.
        case searching
        // Done finding results.
        case finished
        // Stopped before we could find all the results.
        case canceled
    }

    private(set) var state = State.ready {
        didSet {
            SELog("State of \(addressString(self)) set to \(state) with query \(request.query) and direction \(request.direction)")
        }
    }

    var havePendingResults: Bool {
        return resultQueue.peek() != nil
    }

    // Describes the range of positions to be searched.
    fileprivate struct Positions: CustomDebugStringConvertible {
        var debugDescription: String {
            return "<Positions: start=\(start), stop=\(stop), wrapped=\(wrapped)>"
        }
        var start: LineBufferPosition
        var stop: LineBufferPosition
        var wrapped = false

        init?(snapshot: TerminalContentSnapshot, request: SearchRequest, wrapped: Bool) {
            if wrapped {
                self.wrapped = true
                start = request.wrappedStartPosition(width: snapshot.width(),
                                                     cumulativeOverflow: snapshot.cumulativeOverflow,
                                                     lineBuffer: snapshot.lineBuffer)
                if let position = request.stopPosition(lineBuffer: snapshot.lineBuffer,
                                                       width: snapshot.width(),
                                                       overflow: snapshot.cumulativeOverflow,
                                                       hasWrapped: true) {
                    stop = position
                } else {
                    return nil
                }
            } else {
                let start = request.startPosition ?? request.startPosition(
                    lineBuffer: snapshot.lineBuffer,
                    width: snapshot.width(),
                    overflow: snapshot.cumulativeOverflow)
                let stop = request.stopPosition(lineBuffer: snapshot.lineBuffer,
                                                width: snapshot.width(),
                                                overflow: snapshot.cumulativeOverflow)
                guard let start, let stop else {
                    return nil
                }
                self.start = start
                self.stop = stop
            }
        }

        mutating func updateStopPosition(snapshot: TerminalContentSnapshot, request: SearchRequest) {
            if let position = request.stopPosition(lineBuffer: snapshot.lineBuffer,
                                                   width: snapshot.width(),
                                                   overflow: snapshot.cumulativeOverflow,
                                                   hasWrapped: wrapped) {
                stop = position
            } else {
                DLog("This shouldn't happen")
#if DEUG
                fatalError()
#endif
            }
        }
    }

    init?(snapshot: TerminalContentSnapshot,
          request: SearchRequest,
          queue: DispatchQueue) {
        guard let positions = Positions(snapshot: snapshot, request: request, wrapped: false) else {
            return nil
        }
        self.positions = positions
        self.queue = queue
        self.snapshot = snapshot
        self.request = request
        snapshot.lineBuffer.prepareToSearch(for: request.query,
                                            startingAt: positions.start,
                                            options: request.findOptions,
                                            mode: request.findMode,
                                            with: context)
        SELog("Begin search. positions=\(self.positions)")
    }

    // Returns (-1, -1) if the context's position doesn't exist.
    private func absCoord(context: FindContext,
                          lineBuffer: LineBuffer,
                          width: Int32,
                          overflow: Int64) -> VT100GridAbsCoord {
        let startPosition = lineBuffer.position(of: context, width: width)
        var ok = ObjCBool(false)
        let coord = lineBuffer.coordinate(for: startPosition, width: width, extendsRight: false, ok: &ok)
        guard ok.boolValue else {
            return VT100GridAbsCoordMake(-1, -1)
        }
        return VT100GridAbsCoordFromCoord(coord, overflow)
    }

    // Metadata about a search operation.
    private struct SearchInfo {
        var coordRange: VT100GridAbsCoordRange
        var lineRange: Range<Int64>
    }

    // Search a single LineBlock. Modifies context as a side effect.
    private func reallySearch() -> SearchInfo {
        let rangeSearchedStart = absCoord(context: context,
                                          lineBuffer: snapshot.lineBuffer,
                                          width: snapshot.width(),
                                          overflow: snapshot.cumulativeOverflow)
        SELog("Searching block \(context.absBlockNum). Position of context is \(snapshot.lineBuffer.position(of: context, width: snapshot.width())). Will stop at \(positions.stop)")

        snapshot.lineBuffer.findSubstring(context, stopAt: positions.stop)

        let rangeSearchedEnd = absCoord(context: context,
                                        lineBuffer: snapshot.lineBuffer,
                                        width: snapshot.width(),
                                        overflow: snapshot.cumulativeOverflow)
        SELog("Next block will be \(context.absBlockNum). Updated position of context is \(snapshot.lineBuffer.position(of: context, width: snapshot.width()))")

        return searchInfo(searched: VT100GridAbsCoordRange(start: rangeSearchedStart,
                                                           end: rangeSearchedEnd))
    }

    private func searchInfo(searched coordRange: VT100GridAbsCoordRange) -> SearchInfo {
        let overflow = snapshot.cumulativeOverflow
        let absBlockNum = context.absBlockNum
        let line = overflow + Int64(snapshot.lineBuffer.numberOfWrappedLines(withWidth: snapshot.width(),
                                                                             upToAbsoluteBlockNumber: absBlockNum))
        let lineRange = switch request.direction {
        case .forwards:
            overflow..<line
        case .backwards:
            line..<(overflow + Int64(snapshot.lineBuffer.numberOfWrappedLines(withWidth: snapshot.width())))
        }
        return SearchInfo(coordRange: coordRange,
                          lineRange: lineRange)
    }

    func search() {
        SELog("search called")
        if pauseCount > 0 {
            SELog("Paused. Do not search.")
            return
        }
        searchOnce()
        scheduleNextSearchIfNeeded()
    }

    private var queueTooBig: Bool {
        guard let maxQueueSize = request.maxQueueSize else {
            return false
        }
        return resultQueue.count > maxQueueSize
    }

    private func scheduleNextSearchIfNeeded() {
        if state == .searching && pauseCount == 0 {
            if queueTooBig {
                SELog("Queue too big")
                oversize = true
                return
            }
            SELog("Schedule next search")
            queue.async { [weak self] in
                self?.search()
            }
        } else {
            SELog("Declining to search again")
        }
    }

    func searchOnce() {
        SELog("search(): start with state=\(state)")
        switch state {
        case .ready:
            state = .searching
        case .searching:
            break
        case .finished, .canceled:
            return
        }

        // Keep the stop position up to date in case the start or end of the line buffer has changed.
        positions.updateStopPosition(snapshot: snapshot, request: request)
        let searchInfo = reallySearch()

        switch context.status {
        case .Matched:
            // found matches
            lastLocationSearched = snapshot.lineBuffer.position(of: context, width: snapshot.width())
            SELog("Found \(context.results?.count ?? 0) matches. Update lastLocationSearched to \(lastLocationSearched.debugDescriptionOrNil)")
            handleMatches(searchInfo: searchInfo)
            SELog("After handling matches queue has \(resultQueue.count) items")
        case .NotFound:
            // reached stop point
            SELog("Reached stopping point")
            if  !positions.wrapped {
                wrap()
            } else {
                finish()
            }
        case .Searching:
            lastLocationSearched = snapshot.lineBuffer.position(of: context, width: snapshot.width())
            SELog("No matches found but keep looking. Update lastLocationSearched to \(lastLocationSearched.debugDescriptionOrNil)")
            // keep looking
            break
        @unknown default:
            it_fatalError()
        }
    }

    // Called internally when search finishes. Ensures the clients know about
    // it by producing a "finished" item to the result queue.
    private func finish() {
        SELog("finish")
        switch state {
        case .canceled, .ready, .finished:
            SELog("Declining to finish from \(state)")
            return
        case .searching:
            state = .finished
            break
        }
        SELog("Set state to finished and emit finished output")
        resultQueue.produce(SearchEngineOutput(results: [],
                                               lineRange: 0..<0,
                                               coordRange: VT100GridAbsCoordRange(start: VT100GridAbsCoordInvalid, end: VT100GridAbsCoordInvalid),
                                               progress: 1.0,
                                               lastLocationSearched: lastLocationSearched,
                                               finished: true))
    }

    private func wrap() {
        SELog("wrap")
        precondition(!context.hasWrapped);
        precondition(!positions.wrapped)

        let updated = Positions(snapshot: snapshot, request: request, wrapped: true)
        SELog("Positions before=\(positions) after=\(String(describing: updated)). Position of context is \(snapshot.lineBuffer.position(of: context, width: snapshot.width()))")
        guard let updated else {
            SELog("This shouldn't happen")
            finish()
#if DEBUG
            it_fatalError()
#else
            return
#endif
        }
        self.positions = updated

        let tempFindContext = FindContext()
        snapshot.lineBuffer.prepareToSearch(for: request.query,
                                            startingAt: positions.start,
                                            options: context.options,
                                            mode: context.mode,
                                            with: tempFindContext)
        context.copy(from: tempFindContext)
        context.hasWrapped = true
        SELog("Updated position of context is \(snapshot.lineBuffer.position(of: context, width: snapshot.width()))")
    }

    func cancel() {
        SELog("cancel")
        switch state {
        case .ready, .searching:
            state = .canceled
        case .canceled, .finished:
            break
        }
    }

    // After pausing, searches will not be scheduled. Use the returned object to unpause.
    func pause() -> UnpauserProtocol? {
        SELog("pause")
        if state != .searching {
            SELog("pause returning nil because state is not searching")
            return nil
        }
        SELog("pausing operation")
        pauseCount += 1
        return SearchEngineUnpauser { [weak self] in
            self?.pauseCount -= 1
            self?.SELog("Unpause")
            self?.scheduleNextSearchIfNeeded()
        }
    }

    // Call this to allow searching to happen again after the max queue size was exceeded.
    func resumeIfOversize() {
        if oversize, let maxQueueSize = request.maxQueueSize, resultQueue.count < maxQueueSize {
            DLog("Result queue no longer oversize")
            oversize = false
            scheduleNextSearchIfNeeded()
        }
    }

    // Swap in a replacement snapshot to search. We do our best to continue from where we were.
    func updateSnapshot(snapshot: TerminalContentSnapshot) {
        SELog("updateSnapshot")
        switch state {
        case .ready, .canceled:
            it_fatalError("Logic error")
        case .searching:
            break
        case .finished:
            return
        }
        self.snapshot = snapshot
        guard let positions = Positions(snapshot: snapshot, request: request, wrapped: positions.wrapped) else {
            state = .canceled
            return
        }
        self.positions = positions
        SELog("Updated positions: \(positions)")

        if findContextHasPassedStop {
            // We finished early because the next stuff to be searched is gone.
            SELog("findContextHasPassedStop. nextPosition=\(snapshot.lineBuffer.position(of: context, width: snapshot.width())) stop=\(positions.stop)")
            if positions.wrapped {
                finish()
                return
            }
            wrap()
        } else if findContextBeforeStart {
            SELog("findContextBeforeStart. skip ahead to new start. next=\(snapshot.lineBuffer.position(of: context, width: snapshot.width())) start=\(positions.start)")
            // Stuff between the original start and the new start was deleted, and we were still
            // searching the deleted region. Skip ahead to the new start.
            let temp = FindContext()
            snapshot.lineBuffer.prepareToSearch(for: request.query,
                                                startingAt: positions.start,
                                                options: request.findOptions,
                                                mode: request.findMode,
                                                with: temp)
            context.copy(from: temp)
        }
        SELog("Positions is now \(positions), context=\(context.briefDescription)")
    }

    private var findContextHasPassedStop: Bool {
        let nextPosition = snapshot.lineBuffer.position(of: context, width: snapshot.width())

        switch request.direction {
        case .backwards:
            return nextPosition.absolutePosition < positions.stop.absolutePosition
        case .forwards:
            return nextPosition.absolutePosition >= positions.stop.absolutePosition
        }
    }

    private var findContextBeforeStart: Bool {
        let nextPosition = snapshot.lineBuffer.position(of: context, width: snapshot.width())

        switch request.direction {
        case .backwards:
            return nextPosition.absolutePosition >= positions.start.absolutePosition
        case .forwards:
            return nextPosition.absolutePosition < positions.start.absolutePosition
        }
    }

    // Safe to call on any thread
    func tryConsume() -> SearchEngineOutput? {
        return resultQueue.tryConsume()
    }

    // For tests
    func blockingConsume() -> SearchEngineOutput {
        return resultQueue.blockingConsume()
    }

    // Safe to call on any thread
    func peekOne() -> SearchEngineOutput? {
        return resultQueue.peek()
    }

    private var results: [ResultRange] {
        (context.results ?? []) as! [ResultRange]
    }

    // Take matches from the context and convert them into SearchResult objects and put them on the result queue.
    private func handleMatches(searchInfo: SearchInfo) {
        let allPositions = snapshot.lineBuffer.convertPositions(results,
                                                                withWidth: snapshot.width()) ?? []
        let searchResults = allPositions.compactMap { xyrange in
            let result = SearchResult.withCoordRange(xyrange.coordRange,
                                                     overflow: snapshot.cumulativeOverflow)
            //SELog("handleMatches converted \(xyrange) to \(String(describing: result)) with overflow of \(snapshot.cumulativeOverflow)")
            return result
        }
        SELog("handleMatches conveted \(allPositions.count) XYRanges to \(searchResults.count) SearchResults from \(String(describing: allPositions.first))->\(String(describing: searchResults.first)) to \(String(describing: allPositions.last))->\(String(describing: searchResults.last))")
        if !request.wantMultipleResults && !searchResults.isEmpty {
            context.reset()
            finish()
        }
        context.results?.removeAllObjects()
        resultQueue.produce(SearchEngineOutput(results: searchResults,
                                               lineRange: searchInfo.lineRange,
                                               coordRange: searchInfo.coordRange,
                                               progress: context.progress,
                                               finished: state == .finished))
    }
}

// See the discussion in SearchEngineOperation about pausing.
@objc(iTermSearchEngineUnpauser)
class SearchEngineUnpauser: NSObject, UnpauserProtocol {
    private var closure: (() -> ())?

    init(_ closure: @escaping () -> ()) {
        self.closure = closure
    }

    func unpause() {
        if let saved = closure {
            closure = nil
            saved()
        }
    }

    deinit {
        unpause()
    }
}

// A higher level API than SearchOperation that ensures it is called on the appropriate queue.
// This class is of dubious value. It could be used by a pure Swift client and it has a lot
// less historical cruft than iTermSearchEngine.
class SearchEngine: Pausable {
    fileprivate private(set) var operation: SearchOperation?
    private static let queue = DispatchQueue(label: "com.iterm2.search")
    private(set) var snapshot: TerminalContentSnapshot?

    var havePendingResults: Bool {
        return operation?.havePendingResults ?? false
    }

    func beginSearch(snapshot: TerminalContentSnapshot, request: SearchRequest) -> LineBufferPosition? {
        SELog("beginSearch request=\(request)")
        operation?.cancel()
        guard let operation = SearchOperation(snapshot: snapshot, request: request, queue: Self.queue) else {
            return nil
        }
        self.snapshot = snapshot
        self.operation = operation
        let position = operation.positions.start
        // Do the first search synchronously to ensure we are making progress. It will reschedule
        // itself onto the dispatch queue if needed.
        operation.search()
        return position
    }

    func tryConsume() -> SearchEngineOutput? {
        return operation?.tryConsume()
    }

    // For tests
    func blockingConsume() -> SearchEngineOutput? {
        return operation?.blockingConsume()
    }

    func peekOne() -> SearchEngineOutput? {
        return operation?.peekOne()
    }

    func updateSnapshot(_ snapshot: TerminalContentSnapshot) {
        guard let operation else {
            return
        }
        self.snapshot = snapshot
        Self.queue.async {
            operation.updateSnapshot(snapshot: snapshot)
        }
    }

    func cancel() {
        if let operation = self.operation {
            Self.queue.async {
                operation.cancel()
            }
        }
    }

    func pause() -> UnpauserProtocol? {
        Self.queue.sync {
            return operation?.pause()
        }
    }

    func resumeIfOversize() {
        if let operation = self.operation {
            Self.queue.async {
                operation.resumeIfOversize()
            }
        }
    }
}

// Provides data for the search engine.
@objc
protocol iTermSearchEngineDataSource: AnyObject {
    func totalScrollbackOverflow() -> Int64

    @objc(snapshotForcingPrimaryGrid:)
    func snapshot(forcingPrimaryGrid: Bool) -> TerminalContentSnapshot

    @objc
    func width() -> Int32

    @objc
    var syncDistributor: SyncDistributor? { get }
}

// For performance it is useful to combine SearchEngineOutput objects. This holds their union.
struct GroupedSearchEngineOutput {
    var results: [SearchResult]
    var lineRange: Range<Int64>
    var coordRange: VT100GridAbsCoordRange
    var finished: Bool
    var lastLocationSearched: LineBufferPosition?

    init(_ output: SearchEngineOutput) {
        results = output.results
        lineRange = output.lineRange
        coordRange = output.coordRange
        finished = output.finished
        lastLocationSearched = output.lastLocationSearched
    }

    mutating func combine(with other: SearchEngineOutput) {
        if other.finished {
            finished = true
            return
        }
        results.append(contentsOf: other.results)
        lineRange = other.lineRange
        coordRange.end = other.coordRange.end
        lastLocationSearched = other.lastLocationSearched
    }
}

@objc
protocol iTermSearchEngineDelegate: AnyObject {
    // The engine is being paused because of sync distribution. Clients that
    // have not registered a timer should drain their queues here before the
    // snapshot gets updated. If you opt out of automatic synchronization then
    // it's optional to drain here. Just sync before calling updateSnapshot.
    func searchEngineWillPause(_ searchEngine: iTermSearchEngine)
}

// This is an Objective C interface meant to be used by classes that wish to be clients of the
// new API using search() and consume().
@objc
class iTermSearchEngine: NSObject, Pausable {
    @objc private(set) var lastLocationSearched: LineBufferPosition?
    // Set this to false *before setting the datasource* if you don't want this
    // engine added to the sync distributor.
    @objc var automaticallySynchronize = true
    @objc var maxConsumeCount: Int = Int.max

    override var debugDescription: String {
        return "<iTermSearchEngine: \(it_addressString) delegate=\(addressString(delegate)) dataSource=\(addressString(dataSource)) query=\(String(describing: query)) mode=\(mode) options=\(options) operation=\(addressString(impl?.operation))"
    }
    // This is automatically set to the position where the most recent search began.
    // It is mutable because clients need a handy way to remember where to begin tail find,
    // and when a search completes that moves to the latest position in the buffer.
    @objc var lastStartPosition: LineBufferPosition? {
        didSet {
            SELog("Set last start position to \(lastStartPosition.debugDescriptionOrNil)")
        }
    }
    
    // lastPosition of the snapshot the last time a search was begun or updated.
    @objc var lastEndOfBufferPosition: LineBufferPosition?
    
    @objc var timer: Timer? {
        didSet {
            SELog("timer <- \(String(describing: timer))")
        }
    }
    
    @objc weak var delegate: iTermSearchEngineDelegate?

    private var impl: SearchEngine?

    // Hey! Something sneaky is happening here so pay attention.
    // We automatically add ourselves to the dataSource's sync distributor so we can
    // automatically pause and update the snapshot when it syncs.
    // That means you don't usually need to call updateSnapshot.
    // You can opt out of the behavior by returning nil from -syncDistributor.
    @objc weak var dataSource: iTermSearchEngineDataSource? {
        didSet {
            if automaticallySynchronize {
                dataSource?.syncDistributor?.addObject(self)
            }
        }
    }
    
    @objc private(set) var progress = Double(0)
    private var lastStart: LineBufferPosition?
    
    @objc
    var query: String? {
        impl?.operation?.request.query
    }
    
    @objc
    var hasRequest: Bool {
        impl?.operation != nil
    }
    
    @objc
    var mode: iTermFindMode {
        impl?.operation?.request.findMode ?? .smartCaseSensitivity
    }
    
    @objc
    var options: FindOptions {
        impl?.operation?.request.findOptions ?? []
    }
    
    @objc
    var havePendingResults: Bool {
        return impl?.havePendingResults ?? false
    }
    
    @objc
    init(dataSource: iTermSearchEngineDataSource?,
         syncDistributor: SyncDistributor?) {
        self.dataSource = dataSource
        super.init()
        syncDistributor?.addObject(self)
    }
    
    // Sneakily call the registered timer until the queue is empty.
    // Ensures that pending results are processed before the snapshot is updated.
    func drain() {
        SELog("drain: havePendingResults=\(havePendingResults), timer=\(String(describing: timer))")
        while havePendingResults, let timer {
            SELog("Fire timer")
            timer.fire()
            SELog("drain: havePendingResults=\(havePendingResults), timer=\(String(describing: timer))")
        }
    }
    
    // Begin a new search.
    func search(request: SearchRequest,
                snapshot: TerminalContentSnapshot) -> LineBufferPosition? {
        SELog("search request=\(request.debugDescription)")
        cancel()
        impl = SearchEngine()
        return impl?.beginSearch(snapshot: snapshot, request: request)
    }
    
    // Get search results, if there are any.
    @objc
    func consume(rangeSearched: UnsafeMutablePointer<VT100GridAbsCoordRange>?,
                 lineRange: UnsafeMutablePointer<NSRange>,
                 finished: UnsafeMutablePointer<ObjCBool>,
                 block: Bool) -> [SearchResult]? {
        SELog("consume called")
        var combined: GroupedSearchEngineOutput?
        finished.pointee = ObjCBool(false)
        
        while !finished.pointee.boolValue && (combined?.results.count ?? 0) < maxConsumeCount {
            SELog("Consuming block=\(block)")
            guard let output = (block ? impl?.blockingConsume() : impl?.tryConsume()) else {
                SELog("consume returned nil")
                break
            }
            SELog("Consumed:\n\(output)")
            progress = output.progress
            if output.finished {
                finished.pointee = ObjCBool(true)
                lastLocationSearched = output.lastLocationSearched
            }
            if combined == nil {
                combined = GroupedSearchEngineOutput(output)
                continue
            }
            combined?.combine(with: output)
        }
        
        guard let combined else {
            return nil
        }
        
        impl?.resumeIfOversize()
        
        rangeSearched?.pointee = combined.coordRange
        lineRange.pointee = NSRange(combined.lineRange)
        
        return combined.results
    }
    
    // Stop an ongoing search, if any.
    @objc
    func cancel() {
        if impl != nil {
            SELog("cancel")
        }
        impl?.cancel()
        impl = nil
    }
    
    // Start searching a new snapshot. Make sure to pause and drain before
    // calling this. If you use sync distribution with a registered timer, then
    // you get that for free.
    @objc
    func updateSnapshot() {
        guard let dataSource, let impl, let operation = impl.operation else {
            return
        }
        SELog("updateSnapshot")
        let snapshot = dataSource.snapshot(forcingPrimaryGrid: operation.request.forceMainScreen)
        impl.updateSnapshot(snapshot)
        lastEndOfBufferPosition = snapshot.lineBuffer.lastPosition()
    }
    
    // Wraps another unpauser and adds a side effect to it.
    class SideEffectPerformingUnpauser: UnpauserProtocol {
        private let unpauser: UnpauserProtocol
        private let sideEffect: () -> ()
        init(_ unpauser: UnpauserProtocol, sideEffect: @escaping () -> ()) {
            self.unpauser = unpauser
            self.sideEffect = sideEffect
        }
        
        func unpause() {
            unpauser.unpause()
            sideEffect()
        }
    }
    
    // Don't call this directly. It should be called by the sync distributor only.
    func pause() -> UnpauserProtocol? {
        guard let unpauser = impl?.pause() else {
            SELog("impl.pause returned nil")
            return nil
        }
        SELog("willPause delegate=\(String(describing: delegate))")
        delegate?.searchEngineWillPause(self)
        SELog("drain")
        drain()
        return SideEffectPerformingUnpauser(unpauser) { [weak self] in
            self?.SELog("unpause and update")
            self?.updateSnapshot()
        }
    }
}

// This extension is for backward compatibility with existing search code.
@objc
extension iTermSearchEngine {
    // This is the old, deprecated interface. Use search(_:) instead.
    @objc(setFindString:forwardDirection:mode:startingAtX:startingAtY:withOffset:multipleResults:absLineRange:forceMainScreen:startPosition:)
    func setFind(_ aString: String,
                 forwardDirection direction: Bool,
                 mode: iTermFindMode,
                 startingAtX x: Int32,
                 startingAtY startY: Int32,
                 withOffset offset: Int32,
                 multipleResults: Bool,
                 absLineRange: NSRange,
                 forceMainScreen: Bool,
                 startPosition: LineBufferPosition?) {
        SELog("setFindString:\(aString) direction:\(direction) mode:\(mode) starttingAtX:\(x) startingAtY:\(startY) withOffset:\(offset) multipleResults:\(multipleResults) absLineRange:\(absLineRange) forceMainScreen:\(forceMainScreen) startPosition:\(String(describing: startPosition))")
        guard dataSource != nil else {
            lastStartPosition = nil
            lastEndOfBufferPosition = nil
            return
        }

        var options = FindOptions()
        if !direction {
            options.insert(.optBackwards)
        }
        if multipleResults {
            options.insert(.multipleResults)
        }
        if aString.contains("\n") {
            options.insert(.optMultiLine)
        }

        let builder = iTermSearchRequest(query: aString,
                                         mode: mode,
                                         startCoord: VT100GridCoord(x: x, y: startY),
                                         offset: offset,
                                         options: options,
                                         forceMainScreen: forceMainScreen,
                                         startPosition: startPosition)
        if absLineRange.length > 0 {
            builder.setAbsLineRange(absLineRange)
        }

        return search(builder)
    }

    @objc
    func search(_ builder: iTermSearchRequest) {
        guard let dataSource else {
            return
        }
        let request = builder.realize(dataSource: dataSource)
        let snapshot = dataSource.snapshot(forcingPrimaryGrid: request.forceMainScreen)
        lastEndOfBufferPosition = snapshot.lineBuffer.lastPosition()
        lastStartPosition = search(request: request, snapshot: snapshot)
    }

    @objc
    func invalidateLastStartPosition() {
        lastStartPosition = nil
    }

    @objc(continueFindAllResults:rangeOut:absLineRange:rangeSearched:)
    func continueFindAllResults(_ results: NSMutableArray,
                                rangeOut: UnsafeMutablePointer<NSRange>,
                                absLineRange: NSRange,
                                rangeSearched: UnsafeMutablePointer<VT100GridAbsCoordRange>?) -> Bool {
        SELog("continueFindAllResults")
        guard let impl, dataSource != nil, impl.operation != nil else {
            return false
        }
        
        var finished = ObjCBool(false)
        let output = consume(rangeSearched: rangeSearched,
                             lineRange: rangeOut,
                             finished: &finished,
                             block: false)
        results.addObjects(from: output ?? [])
        SELog("results.count=\(results.count), rangeOut=\(rangeOut.pointee) rangeSearched=\(rangeSearched?.pointee.description ?? "(nil)")")
        return !finished.boolValue
    }
}

@objc(iTermUnpauser)
protocol UnpauserProtocol {
    func unpause()
}

@objc(iTermPausable)
protocol Pausable {
    func pause() -> UnpauserProtocol?
}

// The complexity of searching a changing line buffer is immense.
// In order to keep my head from exploding, at the cost of some performance, we will never search
// an out-of-date snapshot.
// To accomplish this, whenever the main thread syncs up with the mutation thread, all search
// activities must be paused.
// While they are paused, new state is copied from the mutation thread to the main thread including
// the line buffer and grid.
// Afterwards, search may resume. To ensure only current data is searched, unpausing is immediately
// followed by updating snapshots.
// This nicely parallelizes a previously synchronous operation while avoiding all data races.
// The goal of doing the CPU intensive work of searching off the main thread is accomplished.
@objc(iTermSyncDistributor)
class SyncDistributor: NSObject {
    private var objects: [WeakBox<Pausable>] = []

    @objc
    func addObject(_ object: Pausable) {
        if !objects.anySatisfies({$0.value === object}) {
            objects.append(WeakBox(object))
        }
    }

    private class MultiUnpauser: NSObject, UnpauserProtocol {
        private let unpausers: [UnpauserProtocol]

        init(_ unpausers: [UnpauserProtocol]) {
            self.unpausers = unpausers
        }

        func unpause() {
            for unpauser in unpausers {
                unpauser.unpause()
            }
        }
    }

    @objc
    func pause() -> UnpauserProtocol {
        objects.removeAll { box in
            box.value == nil
        }
        return MultiUnpauser(objects.compactMap({
            $0.value?.pause()
        }))
    }
}

extension iTermSearchEngine {
    static func SELog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
        _SELog(messageBlock, file: file, line: line, function: function)
    }
    func SELog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
        _SELog({ "\(debugDescription): " + messageBlock() }, file: file, line: line, function: function)
    }
}

extension SearchOperation: CustomDebugStringConvertible {
    var debugDescription: String {
        let paused = if pauseCount > 0 {
            "PAUSED "
        } else {
            ""
        }
        return "<SearchOperation: \(addressString(self)) \(paused)request=\(request.debugDescription) context=\(context.briefDescription)>"
    }
    func SELog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
        _SELog({ "\(debugDescription): " + messageBlock() }, file: file, line: line, function: function)
    }
}
