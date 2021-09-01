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

    init(accept: @escaping () -> (Void)) {
        self.accept = accept
    }

    var progress: Double {
        return 1
    }

    mutating func update() -> Bool {
        accept()
        return false
    }
}

struct FilteringUpdater: Updater {
    private let lineBuffer: LineBuffer
    private let count: Int32
    private let accept: (Int32) -> (Void)
    private let context = FindContext()
    private let stopAt: LineBufferPosition
    private let width: Int32

    private var lastY = Int32(-1)

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
        let startPosition = lineBuffer.firstPosition()
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

    @objc(initWithQuery:lineBuffer:grid:mode:destination:cadence:progress:)
    init(query: String,
         lineBuffer: LineBuffer,
         grid: VT100Grid,
         mode: iTermFindMode,
         destination: FilterDestination,
         cadence: TimeInterval,
         progress: ((Double) -> (Void))?) {
        let temp = lineBuffer.newAppendOnlyCopy()
        grid.appendLines(grid.numberOfLinesUsed(), to: temp)
        let numberOfLines = temp.numLines(withWidth: grid.size.width)
        let width = grid.size.width
        self.cadence = cadence
        self.progress = progress
        self.query = query
        if query.isEmpty {
            updater = VerbatimUpdater() {
                destination.adopt(temp)
            }
        } else {
            updater = FilteringUpdater(query: query,
                                       lineBuffer: temp,
                                       count: numberOfLines,
                                       width: width,
                                       mode: mode) { (lineNumber: Int32) in
                DLog("AsyncFilter: append line \(lineNumber)")
                var continuation = screen_char_t()
                let chars = temp.wrappedLine(at: lineNumber, width: width, continuation: &continuation)
                destination.append(chars.line, count: chars.length, continuation: chars.continuation)
            }
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
