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
            fatalError()
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

        return SearchRequest(
            absLineRange: absLineRange,
            direction: options.contains(.optBackwards) ? .backwards : .forwards,
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
            startPosition: startPosition,
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

    var absLineRange: Range<Int64>?
    var direction: Direction
    var regex: Bool
    var query: String
    var caseSensitivity: CaseSensitivity
    var wantMultipleResults: Bool
    var limitResultsToOnePerRawLine: Bool
    var emptyQueryMatches: Bool
    var spanLines: Bool
    var cumulativeOverflow: Int64
    var forceMainScreen: Bool = false
    var initialStart: VT100GridAbsCoord
    var offset = Int32(0)
    var startPosition: LineBufferPosition?
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
        // You shouldn't be able to get here
#if DEBUG
        fatalError("This shouldn't happen")
#else
        switch direction {
        case .forwards:
            SELog("New start position is first position")
            return lineBuffer.firstPosition()
        case .backwards:
            SELog("New start position is penultimate position")
            return lineBuffer.lastPosition().predecessor()
        }
#endif
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

struct SearchEngineOutput {
    var results: [SearchResult]
    var lineRange: Range<Int64>
    var coordRange: VT100GridAbsCoordRange
    var progress: Double
    var lastLocationSearched: LineBufferPosition?
    var finished: Bool
}

class ConditionVariable<T> {
    var value: T
    private let condition = NSCondition()

    init(_ value: T) {
        self.value = value
    }

    func wait<U>(test: (inout T) -> U?) -> U {
        condition.lock()
        defer {
            condition.unlock()
        }
        while true {
            if let result = test(&value) {
                return result
            }
            condition.wait()
        }
    }

    func mutate<U>(_ closure: (inout T) -> U) -> U {
        condition.lock()
        defer {
            condition.unlock()
        }
        let result = closure(&value)
        condition.signal()
        return result
    }

    func sync<U>(_ closure: (inout T) -> U) -> U {
        condition.lock()
        let result = closure(&value)
        condition.unlock()
        return result
    }
}

class ProducerConsumerQueue<T> {
    private let cond = ConditionVariable([T]())

    func produce(_ value: T) {
        cond.mutate { queue in
            queue.append(value)
        }
    }

    func blockingConsume() -> T {
        return cond.wait { queue in
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            return nil
        }
    }

    func tryConsume() -> T? {
        return cond.sync { queue in
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            return nil
        }
    }

    func peek() -> T? {
        cond.sync { queue in
            queue.first
        }
    }

    var count: Int {
        cond.sync { queue in
            queue.count
        }
    }
}

func stringAddress(_ object: Any?) -> String {
    guard let object else {
        return "(nil)"
    }
    let mirror = Mirror(reflecting: object)
    if mirror.displayStyle == .class {
        // Object is a class instance (reference type)
        let ptr = Unmanaged.passUnretained(object as AnyObject).toOpaque()
        return String(format: "%p", UInt(bitPattern: ptr))
    } else {
        return "[value type]]"
    }
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
    private var pauseCount = 0
    private var lastLocationSearched: LineBufferPosition?
    private var oversize = false

    enum State {
        case ready
        case searching
        case finished
        case canceled
    }

    private(set) var state = State.ready {
        didSet {
            SELog("State of \(stringAddress(self)) set to \(state) with query \(request.query) and direction \(request.direction)")
        }
    }

    var havePendingResults: Bool {
        return resultQueue.peek() != nil
    }

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

    private struct SearchInfo {
        var coordRange: VT100GridAbsCoordRange
        var lineRange: Range<Int64>
    }

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
            fatalError()
        }
    }

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
            fatalError()
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

    func resumeIfOversize() {
        if oversize, let maxQueueSize = request.maxQueueSize, resultQueue.count < maxQueueSize {
            DLog("Result queue no longer oversize")
            oversize = false
            scheduleNextSearchIfNeeded()
        }
    }

    func updateSnapshot(snapshot: TerminalContentSnapshot) {
        SELog("updateSnapshot")
        switch state {
        case .ready, .canceled:
            fatalError("Logic error")
        case .searching:
            break
        case .finished:
            return
        }
        self.snapshot = snapshot
        guard var positions = Positions(snapshot: snapshot, request: request, wrapped: positions.wrapped) else {
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
    func searchEngineWillPause(_ searchEngine: iTermSearchEngine)
}

// This is an Objective C interface meant to be used by classes that wish to be clients of the
// new API using search() and consume().
@objc
class iTermSearchEngine: NSObject, Pausable {
    @objc private(set) var lastLocationSearched: LineBufferPosition?
    @objc var automaticallySynchronize = true
    @objc var maxConsumeCount: Int = Int.max

    override var debugDescription: String {
        return "<iTermSearchEngine: \(it_addressString) delegate=\(stringAddress(delegate)) dataSource=\(stringAddress(dataSource)) query=\(String(describing: query)) mode=\(mode) options=\(options) operation=\(stringAddress(impl?.operation))"
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
    
    func drain() {
        SELog("drain: havePendingResults=\(havePendingResults), timer=\(String(describing: timer))")
        while havePendingResults, let timer {
            SELog("Fire timer")
            timer.fire()
            SELog("drain: havePendingResults=\(havePendingResults), timer=\(String(describing: timer))")
        }
    }
    
    func search(request: SearchRequest,
                snapshot: TerminalContentSnapshot) -> LineBufferPosition? {
        SELog("search request=\(request.debugDescription)")
        cancel()
        impl = SearchEngine()
        return impl?.beginSearch(snapshot: snapshot, request: request)
    }
    
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
    
    @objc
    func cancel() {
        if impl != nil {
            SELog("cancel")
        }
        impl?.cancel()
        impl = nil
    }
    
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
        guard let dataSource else {
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

extension VT100GridCoord: Comparable {
    public static func == (lhs: VT100GridCoord, rhs: VT100GridCoord) -> Bool {
        return VT100GridCoordEquals(lhs, rhs)
    }
    
    public static func < (lhs: VT100GridCoord, rhs: VT100GridCoord) -> Bool {
        return VT100GridCoordCompare(lhs, rhs) == .orderedAscending
    }
}

extension ClosedRange where Bound: Strideable, Bound.Stride: SignedInteger {
    init?(_ range: Range<Bound>) {
        if range.isEmpty {
            return nil
        }
        self = range.lowerBound...(range.upperBound.advanced(by: -1))
    }

    func clamping(_ value: Bound) -> Bound {
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

extension VT100GridCoord {
    func absolute(overflow: Int64) -> VT100GridAbsCoord {
        return VT100GridAbsCoordFromCoord(self, overflow)
    }
}

extension VT100GridAbsCoord {
    func relative(overflow: Int64) -> VT100GridCoord? {
        var ok = ObjCBool(false)
        let result = VT100GridCoordFromAbsCoord(self, overflow, &ok)
        if !ok.boolValue {
            return nil
        }
        return result
    }

    func relativeClamped(overflow: Int64) -> VT100GridCoord {
        if let coord = relative(overflow: overflow) {
            return coord
        }
        if y < overflow {
            return VT100GridCoord(x: 0, y: 0)
        }
        return VT100GridCoord(x: 0, y: Int32.max - 1)
    }
}

extension IndexSet {
    mutating func removeFirst() -> Element? {
        if let value = first {
            remove(value)
            return value
        }
        return nil
    }
}


@objc
extension iTermSearchEngine {
    private static func sca(_ string: String) -> ScreenCharArray {
        let size = string.utf16.count * 2
        var buffer = Array<screen_char_t>(repeating: screen_char_t(), count: size)
        var length = Int32(size)
        StringToScreenChars(string,
                            &buffer,
                            screen_char_t(),
                            screen_char_t(),
                            &length,
                            false,
                            nil,
                            nil,
                            .none,
                            9,
                            false)
        var eol = screen_char_t()
        eol.code = unichar(EOL_HARD)
        let sca = ScreenCharArray(line: buffer,
                                  length: length,
                                  continuation: eol)
        sca.makeSafe()
        return sca
    }


    fileprivate class Screen: NSObject, iTermSearchEngineDataSource {
        var syncDistributor: SyncDistributor? = SyncDistributor()

        var _totalScrollbackOverflow = Int64(0)
        var unlimitedScrollback = true

        func totalScrollbackOverflow() -> Int64 {
            return _totalScrollbackOverflow
        }


        func snapshot(forcingPrimaryGrid: Bool) -> TerminalContentSnapshot {
            return TerminalContentSnapshot(lineBuffer: buffer,
                                           grid: grid,
                                           cumulativeOverflow: totalScrollbackOverflow())
        }

        lazy var searchEngine = {
            iTermSearchEngine(dataSource: self, syncDistributor: syncDistributor)
        }()
        let buffer = LineBuffer()
        let grid = VT100Grid(size: VT100GridSize(width: 80, height: 1),
                             delegate: nil)!

        override init() {
            super.init()
            searchEngine.dataSource = self
        }

        func content(for range: SearchResult) -> String {
            let extractor = iTermTextExtractor(dataSource: self)
            let overflow = totalScrollbackOverflow()
            return extractor.content(in: VT100GridWindowedRange(
                coordRange: VT100GridCoordRange(
                    start: VT100GridCoord(
                        x: range.internalStartX,
                        y: Int32(clamping: range.internalAbsStartY - overflow)),
                    end: VT100GridCoord(
                        x: range.internalEndX + 1,
                        y: Int32(clamping: range.internalAbsEndY - overflow))),
                columnWindow: VT100GridRange(location: 0, length: 0)),
                                     attributeProvider: nil,
                                     nullPolicy: .kiTermTextExtractorNullPolicyFromLastToEnd,
                                     pad: false,
                                     includeLastNewline: false,
                                     trimTrailingWhitespace: false,
                                     cappedAtSize: Int32.max,
                                     truncateTail: false,
                                     continuationChars: nil,
                                     coords: nil) as! String
        }

        func moveCursor(to coord: VT100GridCoord) {
            grid.cursor = coord
        }

        func appendLn(_ string: String) {
            let sca = sca(string)
            var dropped = grid.appendChars(atCursor: sca.line,
                                           length: sca.length,
                                           scrollingInto: buffer,
                                           unlimitedScrollback: unlimitedScrollback,
                                           useScrollbackWithRegion: false,
                                           wraparound: true,
                                           ansi: false,
                                           insert: false,
                                           externalAttributeIndex: iTermExternalAttributeIndex())
            _totalScrollbackOverflow += Int64(dropped)

            grid.moveCursorToLeftMargin()
            dropped = grid.moveCursorDownOneLineScrolling(into: buffer,
                                                          unlimitedScrollback: unlimitedScrollback,
                                                          useScrollbackWithRegion: false,
                                                          willScroll: nil,
                                                          sentToLineBuffer: nil)
            _totalScrollbackOverflow += Int64(dropped)
        }
    }


    private static func appendTestNumbers(screen: Screen) {
        for i in 0..<10 {
            screen.appendLn("Test \(i)")
            screen.buffer.forceSeal()
        }
    }

    @nonobjc
    private static func performTestSearch(screen: Screen,
                                          request: SearchRequest) -> [SearchResult] {
        let snapshot = screen.snapshot(forcingPrimaryGrid: false)
        _ = screen.searchEngine.search(request: request,
                                       snapshot: snapshot)

        var results = [SearchResult]()
        var rangeSearched = VT100GridAbsCoordRange()
        var lineRange = NSRange()
        while true {
            var finished = ObjCBool(false)
            if let partialResults = screen.searchEngine.consume(rangeSearched: &rangeSearched,
                                                                lineRange: &lineRange,
                                                                finished: &finished,
                                                                block: true) {
                results.append(contentsOf: partialResults)
            }
            if finished.boolValue {
                break
            }
        }
        return results
    }

    @nonobjc
    private static func runTest(_ name: String, closure: () throws -> ()) {
        print("Begin \(name)")
        do {
            try closure()
        } catch {
            print("Failed: \(error)")
        }
    }

    @objc static func test() {
        runTest("testForwards") { testForwards() }
        runTest("testBackwards") { testBackwards() }
        runTest("testForwardsFromCursor") { testForwardsFromCursor() }
        runTest("testBackwardsFromCursor") { testBackwardsFromCursor() }
        runTest("testForwardsWithLineRange") { testForwardsWithLineRange() }
        runTest("testBackwardsWithLineRange") { testBackwardsWithLineRange() }
        runTest("testForwardsWithCursorOutOfBoundsAndLineRange") { testForwardsWithCursorOutOfBoundsAndLineRange() }
        runTest("testRegex") { testRegex() }
        runTest("testCaseSensitive") { testCaseSensitive() }
        runTest("testCaseSensitiveRegex") { testCaseSensitiveRegex() }
        runTest("testSingleResult") { testSingleResult() }
        runTest("testOnePerRawLine") { testOnePerRawLine() }
        runTest("testEmptyQueryMatches") { testEmptyQueryMatches() }
        runTest("testSpanLines") { testSpanLines() }
        runTest("testUpdateSnapshot") { testUpdateSnapshot() }
        runTest("testUpdateSnapshot2") { testUpdateSnapshot2() }
        abort()
    }

    private static func expectEquals(_ expected: [SearchResult], _ actual: [SearchResult]) {
        if (expected.count != actual.count) {
            print("Counts differ")
            print("Actual (count=\(actual.count)):")
            print(actual)
            print("")
            print("Expected (count=\(expected.count)):")
            print(expected)
            fatalError()
        }
        for i in 0..<expected.count {
            if !expected[i].isEqual(to: actual[i]) {
                print("Failed at index \(i)")
                print("Actual:")
                print(actual)
                print("")
                print("Expected:")
                print(expected)
                fatalError()
            }
        }
    }

    private static func testUpdateSnapshot2() {
        let screen = Screen()
        screen.unlimitedScrollback = false
        screen.buffer.setMaxLines(10)
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 9))
        let op = SearchOperation(snapshot: screen.snapshot(forcingPrimaryGrid: false),
                                 request: request,
                                 queue: DispatchQueue.global())!
        var results = [SearchResult]()
        op.searchOnce()
        results.append(contentsOf: op.blockingConsume().results)

        let popped = screen.buffer.popLastLine(withWidth: screen.width())
        SELog("Popped: \(String(describing: popped))")

        let unpauser = screen.syncDistributor?.pause()
        screen.moveCursor(to: VT100GridCoord(x: 0, y: 0))
        screen.appendLn("test a")
        screen.appendLn("test b")
        screen.appendLn("test c")
        unpauser?.unpause()

        while op.state == .searching {
            op.searchOnce()
        }

        while true {
            let next = op.blockingConsume()
            results.append(contentsOf: next.results)
            if next.finished {
                break
            }
        }

        let expected = [9, 7, 6, 5, 4, 3, 2, 11, 10].map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testUpdateSnapshot() {
        let screen = Screen()
        screen.unlimitedScrollback = false
        screen.buffer.setMaxLines(10)
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 9))
        let op = SearchOperation(snapshot: screen.snapshot(forcingPrimaryGrid: false),
                                 request: request,
                                 queue: DispatchQueue.global())!
        op.searchOnce()
        expectEquals([SearchResult(fromX: 0, y: 9, toX: 3, y: 9)],
                     op.blockingConsume().results)

        // Cause the first lines to be dropped
        let unpauser = screen.syncDistributor?.pause()
        for _ in 0..<5 {
            screen.appendLn("no match here")
        }
        unpauser?.unpause()

        SELog("Subsequent searches are on up-to-date snapshot")
        while op.state == .searching {
            op.searchOnce()
        }

        var results = [SearchResult]()
        while true {
            let next = op.blockingConsume()
            results.append(contentsOf: next.results)
            if next.finished {
                break
            }
        }

        let expected = (5...8).reversed().map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testSpanLines() {
        let screen = Screen()
        // Multiline search can't span blocks currently
        for i in 0..<10 {
            screen.appendLn("Test \(i)")
        }
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test 2\ntest 3",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: true,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = [SearchResult(fromX: 0, y: 2, toX: 5, y: 3)!]
        expectEquals(expected, results)
    }

    // Note that emptyQueryMatches only akes sense when limitResultsToOnePerRawLine
    // is also set.
    private static func testEmptyQueryMatches() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: true,
                                    emptyQueryMatches: true,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0..<10).map { y in
            SearchResult(fromX: 0, y: y, toX: 5, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testOnePerRawLine() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "t",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: true,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0..<10).map { y in
            SearchResult(fromX: 0, y: y, toX: 0, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testSingleResult() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "t",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: false,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = [0].map { y in
            SearchResult(fromX: 0, y: y, toX: 0, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testCaseSensitiveRegex() {
        let screen = Screen()
        for i in 0..<10 {
            if i == 5 || i == 6 {
                screen.appendLn("test \(i)")
            } else {
                screen.appendLn("Test \(i)")
            }
            screen.buffer.forceSeal()
        }

        let request = SearchRequest(direction: .forwards,
                                    regex: true,
                                    query: "[te][es][es]t",
                                    caseSensitivity: .sensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (5...6).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testCaseSensitive() {
        let screen = Screen()
        for i in 0..<10 {
            if i == 5 || i == 6 {
                screen.appendLn("test \(i)")
            } else {
                screen.appendLn("Test \(i)")
            }
            screen.buffer.forceSeal()
        }

        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .sensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (5...6).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testRegex() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: true,
                                    query: "t[es][es]t",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0...9).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwardsWithCursorOutOfBoundsAndLineRange() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(absLineRange: 3..<8,
                                    direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (3..<8).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testBackwardsWithLineRange() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(absLineRange: 3..<8,
                                    direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = ([5, 4, 3, 7, 6]).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwardsWithLineRange() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(absLineRange: 3..<8,
                                    direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (Array(5...7)+Array(3...4)).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwardsFromCursor() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (Array(5...9)+Array(0...4)).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testBackwardsFromCursor() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 5))
        let results = performTestSearch(screen: screen, request: request)

        let expected = (Array(6...9)+Array(0...5)).reversed().map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testForwards() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .forwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 0, y: 0))
        let results = performTestSearch(screen: screen, request: request)
        let expected = (0...9).map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }

    private static func testBackwards() {
        let screen = Screen()
        appendTestNumbers(screen: screen)
        let request = SearchRequest(direction: .backwards,
                                    regex: false,
                                    query: "test",
                                    caseSensitivity: .insensitive,
                                    wantMultipleResults: true,
                                    limitResultsToOnePerRawLine: false,
                                    emptyQueryMatches: false,
                                    spanLines: false,
                                    cumulativeOverflow: 0,
                                    initialStart: VT100GridAbsCoord(x: 5, y: 9))
        let results = performTestSearch(screen: screen, request: request)
        let expected = Array(0...9).reversed().map { y in
            SearchResult(fromX: 0, y: y, toX: 3, y: y)!
        }
        expectEquals(expected, results)
    }
}

extension iTermSearchEngine.Screen: iTermTextDataSource {
    func width() -> Int32 {
        return grid.size.width
    }

    func numberOfLines() -> Int32 {
        return buffer.numLines(withWidth: width()) + grid.size.height
    }

    func screenCharArray(forLine line: Int32) -> ScreenCharArray {
        let historyCount = buffer.numLines(withWidth: width())
        if line < historyCount {
            return buffer.screenCharArray(forLine: line, width: width(), paddedTo: width(), eligibleForDWC: false)
        }
        return screenCharArray(atScreenIndex: line - historyCount)
    }

    func screenCharArray(atScreenIndex index: Int32) -> ScreenCharArray {
        let chars = grid.screenChars(atLineNumber: index)!
        return ScreenCharArray(line: chars,
                               length: width(),
                               continuation: chars[Int(width())])
    }

    func externalAttributeIndex(forLine y: Int32) -> (any iTermExternalAttributeIndexReading)? {
        return nil
    }

    func fetchLine(_ line: Int32, block: (ScreenCharArray) -> Any?) -> Any? {
        block(screenCharArray(forLine: line))
    }

    func date(forLine line: Int32) -> Date? {
        return nil
    }

    func commandMark(at coord: VT100GridCoord, mustHaveCommand: Bool, range: UnsafeMutablePointer<VT100GridWindowedRange>?) -> (any VT100ScreenMarkReading)? {
        return nil
    }

    func metadata(onLine lineNumber: Int32) -> iTermImmutableMetadata {
        return iTermImmutableMetadataDefault()
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
        return MultiUnpauser(objects.compactMap({ $0.value?.pause() }))
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
        return "<SearchOperation: \(stringAddress(self)) \(paused)request=\(request.debugDescription) context=\(context.briefDescription)>"
    }
    func SELog(_ messageBlock: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
        _SELog({ "\(debugDescription): " + messageBlock() }, file: file, line: line, function: function)
    }
}

extension VT100GridAbsCoordRange {
    var description: String {
        VT100GridAbsCoordRangeDescription(self)
    }
}
