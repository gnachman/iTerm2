//
//  FoldMark.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/19/24.
//

import Foundation

@objc(iTermFoldMarkReading)
protocol FoldMarkReading: AnyObject, iTermMarkProtocol {
    var savedLines: [ScreenCharArray]? { get }
    var savedITOs: [SavedIntervalTreeObject]? { get }
    var contentString: String { get }
}

@objc(iTermSavedIntervalTreeObject)
class SavedIntervalTreeObject: NSObject {
    @objc var object: IntervalTreeObject
    
    struct ReflowableCoordinate {
        // Number of hard EOLs to skip
        var verticalAdvance: Int32
        // Number of cells after the last hard EOL to walk across to find the coordinate
        var horizontalAdvance: Int32

        private enum Keys: String {
            case v = "v"
            case h = "h"
        }

        init(horizontalAdvance: Int32, verticalAdvance: Int32) {
            self.verticalAdvance = verticalAdvance
            self.horizontalAdvance = horizontalAdvance
        }

        init?(dictionaryValue: [AnyHashable: Any]) {
            guard let v = dictionaryValue[Keys.v.rawValue] as? Int32,
                  let h = dictionaryValue[Keys.h.rawValue] as? Int32 else {
                return nil
            }
            verticalAdvance = v
            horizontalAdvance = h
        }

        var dictionaryValue: [AnyHashable: Any] {
            return [ Keys.v.rawValue: verticalAdvance,
                     Keys.h.rawValue: horizontalAdvance ]
        }

        struct PreprocessedState {
            var hardNewlineCounts: [Int32]
            var cellOffsets: [Int32]
        }

        // Preprocessing step to calculate hard newline counts and cell offsets
        static func preprocess(lines: [ScreenCharArray], width: Int32) -> PreprocessedState {
            var hardNewlineCounts = [Int32]()
            var cellOffsets = [Int32]()

            var hardNewlineCount: Int32 = 0
            var cellCountAfterLastHardNewline: Int32 = 0

            for line in lines {
                hardNewlineCounts.append(hardNewlineCount)
                cellOffsets.append(cellCountAfterLastHardNewline)

                switch line.eol {
                case EOL_HARD:
                    hardNewlineCount += 1
                    cellCountAfterLastHardNewline = 0
                case EOL_SOFT, EOL_DWC:
                    cellCountAfterLastHardNewline += width - (line.eol == EOL_DWC ? 1 : 0)
                default:
                    cellCountAfterLastHardNewline += width
                }
            }

            return PreprocessedState(hardNewlineCounts: hardNewlineCounts, cellOffsets: cellOffsets)
        }

        // Function to convert x, y into reflowable coordinates
        init(x: Int32, y: Int, preprocessedState: PreprocessedState) {
            let hardNewlineCount = preprocessedState.hardNewlineCounts[y]
            var cellCountAfterLastHardNewline = preprocessedState.cellOffsets[y]

            cellCountAfterLastHardNewline += x
            horizontalAdvance = cellCountAfterLastHardNewline
            verticalAdvance = hardNewlineCount
        }
    }

    var start: ReflowableCoordinate
    var end: ReflowableCoordinate

    // Consider the following screen lines:
    //   abc+
    //   def+
    //   gh
    //   ijk+  // Interval starts at j
    //   lm
    //   nop+
    //   qrs+
    //   tu    // Interval ends at t (including t)
    // We can represent this as
    //   lineOffset=1          // Interval begins after the hard newline after `h`
    //   cellOffset=1          // Interval begins one cell after `i`
    //   verticalAdvance=1     // Interval ends on the line after `m`
    //   horizontalAdvance=7   // Include 7 chars at the line starting with n: nopqrst

    private enum Keys: String {
        case object = "object"
        case start = "start"
        case end = "end"
    }

    init?(dictionaryValue: [AnyHashable : Any]) {
        guard let itoDict = dictionaryValue[Keys.object.rawValue] as? [AnyHashable: Any],
              let object = iTermMark.intervalTreeObjectWithDictionary(withTypeInformation: itoDict) else {
            return nil
        }
        self.object = object
        guard let startDict = dictionaryValue[Keys.start.rawValue] as? [AnyHashable: Any],
              let start = ReflowableCoordinate(dictionaryValue: startDict),
              let endDict = dictionaryValue[Keys.end.rawValue] as? [AnyHashable: Any],
              let end = ReflowableCoordinate(dictionaryValue: endDict) else {
            return nil
        }
        self.start = start
        self.end = end
    }

    var dictionaryValue: [String: Any] {
        return [Keys.object.rawValue: object.dictionaryValueWithTypeInformation(),
                Keys.start.rawValue: start.dictionaryValue,
                Keys.end.rawValue: end.dictionaryValue]
    }

    @objc
    static func from(objects: [IntervalTreeObject],
                     startLine: Int64,
                     screenCharArrays: [ScreenCharArray],
                     width: Int32) -> [SavedIntervalTreeObject] {
        let ps = ReflowableCoordinate.preprocess(lines: screenCharArrays, width: width)
        return objects.compactMap {
            SavedIntervalTreeObject(intervalTreeObject: $0,
                                    line: startLine,
                                    screenCharArrays: screenCharArrays,
                                    width: width,
                                    preprocessedState: ps)
        }
    }

    init?(intervalTreeObject: IntervalTreeObject,
          line: Int64,
          screenCharArrays: [ScreenCharArray],
          width: Int32,
          preprocessedState: ReflowableCoordinate.PreprocessedState) {
        guard let interval = intervalTreeObject.entry?.interval else {
            return nil
        }
        self.object = intervalTreeObject

        let absCoordRange = interval.absCoordRange(forWidth: width)
        start = ReflowableCoordinate(x: absCoordRange.start.x,
                                     y: Int(absCoordRange.start.y - line),
                                     preprocessedState: preprocessedState)
        end = ReflowableCoordinate(x: absCoordRange.end.x,
                                   y: Int(absCoordRange.end.y - line),
                                   preprocessedState: preprocessedState)
    }

    private func absLineForVerticalAdvance(baseLine: Int64,
                                           rc: ReflowableCoordinate,
                                           extractor: iTermTextExtractor) -> Int64 {
        var sum = Int64(baseLine)
        for _ in 0..<rc.verticalAdvance {
            let n = extractor.rowCountForRawLineEncompassing(withAbsY: sum)
            sum += Int64(n)
        }
        return sum
    }

    private func horizontalAdvanceToScreenCoord(startY: Int64,
                                                rc: ReflowableCoordinate,
                                                extractor: iTermTextExtractor,
                                                open: Bool) -> VT100GridAbsCoord {
        var y = startY
        var remaining = rc.horizontalAdvance
        while true {
            let length = extractor.cellCountInWrappedLine(withAbsY: y)
            guard length <= remaining else {
                break
            }
            if open && remaining == length {
                // Let the half-open end of the interval extend past the last cell.
                break
            }
            remaining -= length
            y += 1
        }
        return VT100GridAbsCoord(x: remaining, y: y)
    }

    private func absCoord(_ rc: ReflowableCoordinate,
                          baseLine: Int64,
                          extractor: iTermTextExtractor,
                          open: Bool) -> VT100GridAbsCoord {
        // Find the y with the raw line we want.
        let startY = absLineForVerticalAdvance(baseLine: baseLine,
                                               rc: rc,
                                               extractor: extractor)
        return horizontalAdvanceToScreenCoord(startY: startY,
                                              rc: rc,
                                              extractor: extractor,
                                              open: open)
    }

    @objc
    func absCoordRange(baseLine: Int64,
                       extractor: iTermTextExtractor) -> VT100GridAbsCoordRange {
        return VT100GridAbsCoordRange(start: absCoord(start,
                                                      baseLine: baseLine,
                                                      extractor: extractor,
                                                      open: false),
                                      end: absCoord(end,
                                                    baseLine: baseLine,
                                                    extractor: extractor,
                                                    open: true))
    }
}

@objc(iTermFoldMark)
class FoldMark: iTermMark, FoldMarkReading {
    let savedLines: [ScreenCharArray]?
    let savedITOs: [SavedIntervalTreeObject]?
    private let promptLength: Int

    private static let savedLinesKey = "saved lines"
    private static let savedITOsKey = "saved ITOs"
    private static let promptLengthKey = "prompt length"

    @objc(initWithLines:savedITOs:promptLength:)
    init(savedLines: [ScreenCharArray]?,
         savedITOs: [SavedIntervalTreeObject],
         promptLength: Int) {
        self.savedLines = savedLines
        self.savedITOs = savedITOs
        self.promptLength = promptLength
        super.init()
    }

    required init!(dictionary dict: [AnyHashable : Any]!) {
        savedLines = (dict[Self.savedLinesKey] as? [[AnyHashable: Any]])?.compactMap { dict -> ScreenCharArray? in
            ScreenCharArray(dictionary: dict)
        }
        savedITOs = (dict[Self.savedITOsKey] as? [[AnyHashable: Any]])?.compactMap({ dict -> SavedIntervalTreeObject? in
            SavedIntervalTreeObject(dictionaryValue: dict)
        })
        promptLength = (dict[Self.promptLengthKey] as? Int) ?? 0
        super.init(dictionary: dict)
    }

    override func dictionaryValue() -> [AnyHashable : Any]! {
        let unsafeDict: [String: Any?] = [ Self.savedLinesKey: savedLines?.map { $0.dictionaryValue },
                                           Self.savedITOsKey: savedITOs?.map { $0.dictionaryValue },
                                           Self.promptLengthKey: promptLength ]
        return unsafeDict.filter { element in
            element.value != nil
        } as [AnyHashable : Any]
    }

    var contentString: String {
        (savedLines ?? []).dropFirst(promptLength).map {
            $0.stringValueIncludingNewline
        }.joined(separator: "")
    }
}
