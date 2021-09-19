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
    func update() -> Bool
}

class VerbatimUpdater: Updater {
    var accept: (() -> (Void))? = nil
    private var successor: Updater
    private var done = false

    init(_ successor: Updater) {
        self.successor = successor
    }

    var progress: Double {
        return 1
    }

    func update() -> Bool {
        if done {
            // Streaming new input after initial adopt() call.
            return successor.update()
        }
        accept?()
        done = true
        return false
    }
}

class FilteringUpdater: Updater {
    var accept: ((Int32, Bool) -> (Void))? = nil
    private let lineBuffer: LineBuffer
    private let count: Int32
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
         mode: iTermFindMode) {
        self.lineBuffer = lineBuffer
        self.count = count
        self.width = Int32(width)
        self.mode = mode
        self.query = query
        context = FindContext()
        stopAt = lineBuffer.lastPosition()
        begin(at: lineBuffer.firstPosition())
    }

    private func begin(at startPosition: LineBufferPosition) {
        context = FindContext()
        stopAt = lineBuffer.lastPosition()
        lineBuffer.prepareToSearch(for: query,
                                   startingAt: startPosition,
                                   options: [.multipleResults, .oneResultPerRawLine, .optEmptyQueryMatches],
                                   mode: mode,
                                   with: context)
    }

    var progress: Double {
        return min(1.0, Double(max(0, lastY)) / Double(count))
    }

    func update() -> Bool {
        if let lastPosition = lastPosition {
            DLog("Reset search at last position, set lastPosition to nil")
            begin(at: lastPosition)
            self.lastPosition = nil
        }
        guard context.status == .Searching || context.status == .Matched else {
            DLog("FilteringUpdater: finished, return false. Set lastPosition to end of buffer")
            self.lastPosition = lineBuffer.lastPosition()
            return false
        }
        DLog("FilteringUpdater: perform search")
        var needsToBackUp = false
        lineBuffer.findSubstring(context, stopAt: stopAt)
        switch context.status {
        case .Matched:
            DLog("FilteringUpdater: Matched")
            let positions = lineBuffer.convertPositions(context.results as! [ResultRange], withWidth: width)
            for range in positions {
                let temporary = range === positions.last && context.includesPartialLastLine
                accept?(range.yStart, temporary)
                if temporary {
                    needsToBackUp = true
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
        if needsToBackUp {
            // We know we searched the last line so prepare to search again from the beginning
            // of the last line next time.
            lastPosition = lineBuffer.positionForStartOfLastLine()
            DLog("Back up to start of last line")
            return false
        }
        DLog("status is \(context.status.rawValue)")
        switch context.status {
        case .NotFound:
            DLog("Set last position to end of buffer")
            lastPosition = lineBuffer.lastPosition()
            return false
        case .Matched, .Searching:
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
                externalAttributeIndex: iTermExternalAttributeIndex?,
                continuation: screen_char_t)

    @objc(filterDestinationAdoptLineBuffer:)
    func adopt(_ lineBuffer: LineBuffer)

    @objc(filterDestinationRemoveLastLine)
    func removeLastLine()
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
    private var filteringUpdater: FilteringUpdater
    private let destination: FilterDestination
    private var lastLineIsTemporary: Bool

    @objc(initWithQuery:lineBuffer:grid:mode:destination:cadence:refining:progress:)
    init(query: String,
         lineBuffer: LineBuffer,
         grid: VT100Grid,
         mode: iTermFindMode,
         destination: FilterDestination,
         cadence: TimeInterval,
         refining: AsyncFilter?,
         progress: ((Double) -> (Void))?) {
        lineBufferCopy = lineBuffer.newAppendOnlyCopy()
        lineBufferCopy.setMaxLines(-1)
        grid.appendLines(grid.numberOfLinesUsed(), to: lineBufferCopy)
        let numberOfLines = lineBufferCopy.numLines(withWidth: grid.size.width)
        let width = grid.size.width
        self.width = width
        self.cadence = cadence
        self.progress = progress
        self.query = query
        self.destination = destination
        self.filteringUpdater = FilteringUpdater(query: query,
                                                 lineBuffer: lineBufferCopy,
                                                 count: numberOfLines,
                                                 width: width,
                                                 mode: mode)

        if query.isEmpty {
            updater = VerbatimUpdater(filteringUpdater)
        } else {
            updater = filteringUpdater
        }
        lastLineIsTemporary = refining?.lastLineIsTemporary ?? false
        super.init()

        self.filteringUpdater.accept = { [weak self] (lineNumber: Int32, temporary: Bool) in
            self?.addFilterResult(lineNumber, temporary: temporary)
        }
        (updater as? VerbatimUpdater)?.accept = { [weak self] in
            self?.adoptVerbatim()
        }
    }

    private func addFilterResult(_ lineNumber: Int32, temporary: Bool) {
        DLog("AsyncFilter: append line \(lineNumber)")
        if lastLineIsTemporary {
            destination.removeLastLine()
        }
        lastLineIsTemporary = temporary
        let chars = lineBufferCopy.rawLine(atWrappedLine: lineNumber, width: width)
        let metadata = lineBufferCopy.metadataForRawLine(withWrappedLineNumber: lineNumber,
                                                         width: width)
        destination.append(chars.line,
                           count: chars.length,
                           externalAttributeIndex: iTermMetadataGetExternalAttributesIndex(metadata),
                           continuation: chars.continuation)
    }

    private func adoptVerbatim() {
        destination.adopt(lineBufferCopy)
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
            DLog("don't need an update")
            timer = nil
        } else {
            progress?(updater.progress)
        }
    }
}

extension AsyncFilter: ContentSubscriber {
    func deliver(_ array: ScreenCharArray, metadata: iTermMetadata) {
        lineBufferCopy.appendLine(array.line,
                                  length: array.length,
                                  partial: array.eol != EOL_HARD,
                                  width: width,
                                  metadata: metadata,
                                  continuation: array.continuation)
        if timer != nil {
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
