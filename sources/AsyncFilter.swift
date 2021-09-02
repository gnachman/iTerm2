//
//  AsyncFilter.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/30/21.
//

import Foundation

protocol Updater {
    // 0 to 1, how close to done we are.
    var progress: Double { get }

    // Returns false when there is nothing left to do
    mutating func update() -> Bool
}

struct VerbatimUpdater: Updater {
    let accept: () -> (Void)
    private var successor: Updater
    private var done = false

    init(_ successor: Updater, accept: @escaping () -> (Void)) {
        self.accept = accept
        self.successor = successor
    }

    var progress: Double {
        return 1
    }

    mutating func update() -> Bool {
        if done {
            // Streaming new input after initial adopt() call.
            return successor.update()
        }
        accept()
        done = true
        return false
    }
}

struct FilteringUpdater: Updater {
    private let lineBuffer: LineBuffer
    private let count: Int32
    private let accept: (Int32) -> (Void)
    private var context: FindContext
    private var stopAt: LineBufferPosition
    private let width: Int32
    private let mode: iTermFindMode
    private let query: String
    private var lastY = Int32(-1)
    private var lastPosition: LineBufferPosition? = nil

    init(query: String,
         lineBuffer: LineBuffer,
         count: Int32,
         width: Int32,
         mode: iTermFindMode,
         accept: @escaping (Int32) -> (Void)) {
        self.lineBuffer = lineBuffer
        self.count = count
        self.width = Int32(width)
        self.accept = accept
        self.mode = mode
        self.query = query
        context = FindContext()
        stopAt = lineBuffer.lastPosition()
        begin(at: lineBuffer.firstPosition())
    }

    private mutating func begin(at startPosition: LineBufferPosition) {
        context = FindContext()
        stopAt = lineBuffer.lastPosition()
        lineBuffer.prepareToSearch(for: query,
                                   startingAt: startPosition,
                                   options: [.multipleResults],
                                   mode: mode,
                                   with: context)
    }

    var progress: Double {
        return Double(max(0, lastY)) / Double(count)
    }

    mutating func update() -> Bool {
        if context.status == .NotFound, let lastPosition = lastPosition {
            begin(at: lastPosition)
        }
        guard context.status == .Searching || context.status == .Matched else {
            DLog("FilteringUpdater: finished, return false")
            return false
        }
        DLog("FilteringUpdater: perform search")
        lineBuffer.findSubstring(context, stopAt: stopAt)
        switch context.status {
        case .Matched:
            DLog("FilteringUpdater: Matched")  // TODO: Would be nice to limit search results to one per line
            let positions = lineBuffer.convertPositions(context.results as! [ResultRange], withWidth: width)
            for range in positions {
                if range.yStart == lastY {
                    continue
                }
                let start = range.yStart
                let end = max(start, range.yEnd)
                for y in start...end {
                    accept(y)
                }
                lastY = range.yEnd
            }
            context.results.removeAllObjects()
        case .Searching, .NotFound:
            DLog("FilteringUpdater: no results")
            break
        @unknown default:
            fatalError()
        }
        if context.status == .NotFound {
            lastPosition = lineBuffer.lastPosition()
            return false
        }
        return true
    }
}

@objc(iTermFilterDestination)
protocol FilterDestination {
    @objc(filterDestinationAppendCharacters:count:continuation:)
    func append(_ characters: UnsafePointer<screen_char_t>, count: Int32, continuation: screen_char_t)

    @objc(filterDestinationAdoptLineBuffer:)
    func adopt(_ lineBuffer: LineBuffer)
}

@objc(iTermAsyncFilter)
class AsyncFilter: NSObject {
    private var timer: Timer? = nil
    private let progress: ((Double) -> (Void))?
    private let cadence: TimeInterval
    private let query: String
    private var updater: Updater
    private var started = false
    private let lineBufferCopy: LineBuffer
    private let width: Int32
    private let filteringUpdater: FilteringUpdater
    private let destination: FilterDestination

    @objc(initWithQuery:lineBuffer:grid:mode:destination:cadence:progress:)
    init(query: String,
         lineBuffer: LineBuffer,
         grid: VT100Grid,
         mode: iTermFindMode,
         destination: FilterDestination,
         cadence: TimeInterval,
         progress: ((Double) -> (Void))?) {
        let temp = lineBuffer.newAppendOnlyCopy()
        temp.setMaxLines(-1)
        lineBufferCopy = temp
        grid.appendLines(grid.numberOfLinesUsed(), to: temp)
        let numberOfLines = temp.numLines(withWidth: grid.size.width)
        let width = grid.size.width
        self.width = width
        self.cadence = cadence
        self.progress = progress
        self.query = query
        self.destination = destination
        filteringUpdater = FilteringUpdater(query: query,
                                                lineBuffer: temp,
                                                count: numberOfLines,
                                                width: width,
                                                mode: mode) { (lineNumber: Int32) in
            DLog("AsyncFilter: append line \(lineNumber)")
            let chars = temp.rawLine(atWrappedLine: lineNumber, width: width)
            destination.append(chars.line, count: chars.length, continuation: chars.continuation)
        }
        if query.isEmpty {
            updater = VerbatimUpdater(filteringUpdater) {
                destination.adopt(temp)
            }
        } else {
            updater = filteringUpdater
        }

        super.init()
    }

    @objc func start() {
        precondition(!started)
        started = true
        progress?(0)
        DLog("AsyncFilter\(self): Init")
        timer = Timer.scheduledTimer(withTimeInterval: cadence, repeats: true, block: { [weak self] timer in
            self?.update()
        })

        update()
    }


    @objc func cancel() {
        DLog("AsyncFilter\(self): Cancel")
        timer?.invalidate()
        timer = nil
    }

    @objc(canRefineWithQuery:) func canRefine(query: String) -> Bool {
        if timer != nil {
            return false
        }
        if !started {
            return false
        }
        return query.contains(self.query)
    }

    private func performVerbatimUpdate() {
    }

    /// `block` returns whether to keep going. Return true to continue or false to break.
    /// Returns true if it ran out of time, false if block returned false
    private func loopForDuration(_ duration: TimeInterval, block: () -> Bool) -> Bool {
        let startTime = NSDate.it_timeSinceBoot()
        while NSDate.it_timeSinceBoot() - startTime < duration {
            if !block() {
                return false
            }
        }
        return true
    }

    private func update() {
        DLog("AsyncFilter\(self): Timer fired")
        let needsUpdate = loopForDuration(0.01) {
            DLog("AsyncFilter: Update")
            return updater.update()
        }
        if !needsUpdate {
            progress?(1)
            timer?.invalidate()
            timer = nil
        } else {
            progress?(updater.progress)
        }
    }
}

extension AsyncFilter: ContentSubscriber {
    func deliver(_ array: ScreenCharArray) {
        lineBufferCopy.appendLine(array.line,
                                  length: array.length,
                                  partial: array.eol != EOL_HARD,
                                  width: width,
                                  timestamp: Date.timeIntervalSinceReferenceDate,
                                  continuation: array.continuation)
        if timer != nil {
            return
        }
        if array.eol != EOL_HARD {
            return
        }
        while updater.update() { }
    }
}

extension screen_char_t {
    static var zero = screen_char_t(code: 0,
                                    foregroundColor: UInt32(ALTSEM_DEFAULT),
                                    fgGreen: 0,
                                    fgBlue: 0,
                                    backgroundColor: UInt32(ALTSEM_DEFAULT),
                                    bgGreen: 0,
                                    bgBlue: 0,
                                    foregroundColorMode: ColorModeAlternate.rawValue,
                                    backgroundColorMode: ColorModeAlternate.rawValue,
                                    complexChar: 0,
                                    bold: 0,
                                    faint: 0,
                                    italic: 0,
                                    blink: 0,
                                    underline: 0,
                                    image: 0,
                                    strikethrough: 0,
                                    underlineStyle: VT100UnderlineStyle.single,
                                    unused: 0,
                                    urlCode: 0)
}
