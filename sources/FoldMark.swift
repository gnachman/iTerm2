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
    var imageCodes: Set<Int32> { get }
}

@objc(iTermSavedIntervalTreeObject)
public class SavedIntervalTreeObject: NSObject {
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

    init(_ source: SavedIntervalTreeObject) {
        start = source.start
        end = source.end
        object = source.object
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
            sum += Int64(max(0, n))
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

// MARK: - FoldMarkContent

private let kFoldMarkSavedLinesKey = "saved lines"
private let kFoldMarkSavedITOsKey = "saved ITOs"

/// Protocol for fold mark content providers.
private protocol FoldMarkContentProtocol: AnyObject {
    var savedLines: [ScreenCharArray]? { get }
    var savedITOs: [SavedIntervalTreeObject]? { get }
    func largeDictionaryValue() -> [AnyHashable: Any]?
}

/// Holds fold mark content (savedLines and savedITOs). Immutable and shared between
/// progenitor and doppelganger FoldMarks.
private final class FoldMarkContent: FoldMarkContentProtocol {
    let savedLines: [ScreenCharArray]?
    let savedITOs: [SavedIntervalTreeObject]?

    init(savedLines: [ScreenCharArray]?, savedITOs: [SavedIntervalTreeObject]?) {
        self.savedLines = savedLines
        self.savedITOs = savedITOs
    }

    init(dictionary: [AnyHashable: Any]) {
        savedLines = (dictionary[kFoldMarkSavedLinesKey] as? [[AnyHashable: Any]])?.compactMap {
            ScreenCharArray(dictionary: $0)
        }
        savedITOs = (dictionary[kFoldMarkSavedITOsKey] as? [[AnyHashable: Any]])?.compactMap {
            SavedIntervalTreeObject(dictionaryValue: $0)
        }
    }

    func largeDictionaryValue() -> [AnyHashable: Any]? {
        var result: [AnyHashable: Any] = [:]
        if let lines = savedLines?.map({ $0.dictionaryValue }) {
            result[kFoldMarkSavedLinesKey] = lines
        }
        if let itos = savedITOs?.map({ $0.dictionaryValue }) {
            result[kFoldMarkSavedITOsKey] = itos
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - LazyFoldMarkContent

/// Defers loading until first access, using a provider to fetch data on demand.
/// Once loaded, content is immutable. Can be shared between progenitor and doppelganger.
private final class LazyFoldMarkContent: FoldMarkContentProtocol {
    private enum State {
        /// Content dictionary is available inline, just needs parsing.
        case inlineContent([AnyHashable: Any])
        /// Content must be fetched from database via provider.
        case deferred(provider: iTermLargeContentProvider, metadata: [AnyHashable: Any])
        /// Content has been loaded and parsed.
        case loaded(savedLines: [ScreenCharArray]?, savedITOs: [SavedIntervalTreeObject]?)
    }

    private var state: MutableAtomicObject<State>

    var savedLines: [ScreenCharArray]? {
        return load().savedLines
    }

    var savedITOs: [SavedIntervalTreeObject]? {
        return load().savedITOs
    }

    init(inlineContent: [AnyHashable: Any]?,
         provider: iTermLargeContentProvider?,
         metadata: [AnyHashable: Any]?) {
        if let inlineContent {
            self.state = .init(.inlineContent(inlineContent))
        } else if let provider, let metadata {
            self.state = .init(.deferred(provider: provider, metadata: metadata))
        } else {
            self.state = .init(.loaded(savedLines: nil, savedITOs: nil))
        }
    }

    func largeDictionaryValue() -> [AnyHashable: Any]? {
        let (lines, itos) = load()
        var result: [AnyHashable: Any] = [:]
        if let lines = lines?.map({ $0.dictionaryValue }) {
            result[kFoldMarkSavedLinesKey] = lines
        }
        if let itos = itos?.map({ $0.dictionaryValue }) {
            result[kFoldMarkSavedITOsKey] = itos
        }
        return result.isEmpty ? nil : result
    }

    private func load() -> (savedLines: [ScreenCharArray]?, savedITOs: [SavedIntervalTreeObject]?) {
        return state.mutableAccess { state in
            switch state {
            case .loaded(let savedLines, let savedITOs):
                return (savedLines, savedITOs)
            case .inlineContent(let content):
                let (lines, itos) = parse(content)
                state = .loaded(savedLines: lines, savedITOs: itos)
                return (lines, itos)
            case .deferred(let provider, let metadata):
                guard let content = provider.loadLargeContent(withMetadata: metadata) else {
                    state = .loaded(savedLines: nil, savedITOs: nil)
                    return (nil, nil)
                }
                let (lines, itos) = parse(content)
                state = .loaded(savedLines: lines, savedITOs: itos)
                return (lines, itos)
            }
        }
    }

    private func parse(_ content: [AnyHashable: Any]) -> (savedLines: [ScreenCharArray]?, savedITOs: [SavedIntervalTreeObject]?) {
        let savedLines = (content[kFoldMarkSavedLinesKey] as? [[AnyHashable: Any]])?.compactMap {
            ScreenCharArray(dictionary: $0)
        }
        let savedITOs = (content[kFoldMarkSavedITOsKey] as? [[AnyHashable: Any]])?.compactMap {
            SavedIntervalTreeObject(dictionaryValue: $0)
        }
        return (savedLines, savedITOs)
    }
}

// MARK: - FoldMark

@objc(iTermFoldMark)
class FoldMark: iTermMark, FoldMarkReading, iTermLargeContentObject, iTermWidthSavingMark {
    /// Content is shared between progenitor and doppelganger. It's immutable once created.
    private let content: FoldMarkContentProtocol
    private let promptLength: Int
    let imageCodes: Set<Int32>
    /// The screen width at the time the fold was created. Needed to convert
    /// coordinates within the fold when unfolding at a different width.
    /// Falls back to inferring from the longest saved line when not explicitly set
    /// (legacy data or lazy-loaded content that predates this field).
    private var _savedWidth: Int32
    var savedWidth: Int32 {
        if _savedWidth > 0 {
            return _savedWidth
        }
        let inferred = Self.inferWidth(from: savedLines)
        if inferred > 0 {
            _savedWidth = inferred
        }
        return inferred
    }

    /// Indicates this FoldMark is a doppelganger (mutation thread copy).
    /// When true, savedITOs returns doppelganger versions of the ITOs.
    private var _isDoppelganger = false

    /// Cached doppelganger ITOs, created lazily on first access when _isDoppelganger is true.
    private var _doppelgangerITOs: [SavedIntervalTreeObject]?

    /// Generation number for delta encoding. Returns 0 because savedLines is immutable,
    /// so the content never changes and should only be encoded once.
    @objc var generation: Int { 0 }

    private static let promptLengthKey = "prompt length"
    private static let imageCodesKey = "image codes"
    private static let savedWidthKey = "saved width"

    /// Infer the width from saved lines for legacy data that lacks an explicit savedWidth.
    /// The longest saved line gives the width.
    private static func inferWidth(from savedLines: [ScreenCharArray]?) -> Int32 {
        guard let savedLines, !savedLines.isEmpty else { return 0 }
        return Int32(savedLines.lazy.map { Int($0.length) }.max() ?? 0)
    }

    var savedLines: [ScreenCharArray]? { content.savedLines }

    var savedITOs: [SavedIntervalTreeObject]? {
        if _isDoppelganger {
            // Lazily create doppelganger ITOs on first access
            if _doppelgangerITOs == nil, let itos = content.savedITOs {
                _doppelgangerITOs = itos.map { ito in
                    let copy = SavedIntervalTreeObject(ito)
                    copy.object = ito.object.doppelganger()
                    return copy
                }
            }
            return _doppelgangerITOs
        }
        return content.savedITOs
    }

    // MARK: - iTermLargeContentObject

    @objc func smallDictionaryValue() -> [AnyHashable: Any] {
        var result: [AnyHashable: Any] = super.dictionaryValue()
        result[Self.promptLengthKey] = promptLength
        result[Self.imageCodesKey] = Array(imageCodes)
        result[Self.savedWidthKey] = NSNumber(value: savedWidth)
        return result
    }

    @objc func largeDictionaryValue() -> [AnyHashable: Any]? {
        return content.largeDictionaryValue()
    }

    // Lazy loading path. savedWidth may be absent in old data; it will be
    // inferred from the saved lines when they're loaded (returns 0 until then).
    @objc required init?(smallDictionary: [AnyHashable: Any],
                         largeContent: [AnyHashable: Any]?,
                         provider: iTermLargeContentProvider?,
                         metadata: [AnyHashable: Any]?) {
        self.promptLength = (smallDictionary[Self.promptLengthKey] as? Int) ?? 0
        self.imageCodes = Set((smallDictionary[Self.imageCodesKey] as? [Int32]) ?? [])
        self._savedWidth = (smallDictionary[Self.savedWidthKey] as? NSNumber)?.int32Value ?? 0
        self.content = LazyFoldMarkContent(inlineContent: largeContent,
                                           provider: provider,
                                           metadata: metadata)
        super.init(dictionary: smallDictionary)
    }

    // MARK: - Standard Initializers

    @objc(initWithLines:savedITOs:promptLength:imageCodes:width:)
    init(savedLines: [ScreenCharArray]?,
         savedITOs: [SavedIntervalTreeObject],
         promptLength: Int,
         imageCodes: Set<Int32>,
         width: Int32) {
        self.content = FoldMarkContent(savedLines: savedLines, savedITOs: savedITOs)
        self.promptLength = promptLength
        self.imageCodes = imageCodes
        self._savedWidth = width
        super.init()
    }

    /// Copy initializer - shares content with source (no loading triggered).
    init(_ source: FoldMark) {
        self.content = source.content
        self.promptLength = source.promptLength
        self.imageCodes = source.imageCodes
        self._savedWidth = source._savedWidth
        super.init()
    }

    // Non-graph path (archived sessions)
    required init?(dictionary dict: [AnyHashable : Any]) {
        let content = FoldMarkContent(dictionary: dict)
        self.content = content
        self.promptLength = (dict[Self.promptLengthKey] as? Int) ?? 0
        self.imageCodes = Set((dict[Self.imageCodesKey] as? [Int32]) ?? [])
        self._savedWidth = (dict[Self.savedWidthKey] as? NSNumber)?.int32Value ?? 0
        super.init(dictionary: dict)
    }

    override func dictionaryValue() -> [AnyHashable : Any] {
        var result: [AnyHashable: Any] = super.dictionaryValue()
        if let largeDict = content.largeDictionaryValue() {
            for (key, value) in largeDict {
                result[key] = value
            }
        }
        result[Self.promptLengthKey] = promptLength
        result[Self.imageCodesKey] = Array(imageCodes)
        result[Self.savedWidthKey] = NSNumber(value: savedWidth)
        return result
    }

    var contentString: String {
        (savedLines ?? []).dropFirst(promptLength).map {
            $0.stringValueIncludingNewline
        }.joined(separator: "")
    }

    @objc(foldedContentUsesImageWithCode:)
    func foldedContentUsesImage(code: Int32) -> Bool {
        return imageCodes.contains(code)
    }

    // Call after restoring state to ensure images that are in the fold (and
    // will therefore not have marks) do not get garbage collected.
    @objc(recursivelyClearProvisionalFlagForSavedImageMarks)
    func recursivelyClearProvisionalFlagForSavedImageMarks() {
        for code in imageCodes {
            ScreenCharClearProvisionalFlagForImageWithCode(code)
        }
    }

    // The default implementation serializes and deserializes. That causes
    // duplicate image marks to be created. That is a problem because the
    // lifecycle of the progenitor image mark is used to determine when to
    // release images. If we do not keep a strong reference to the image mark,
    // the image will be released even though we have a copy of the image mark.
    // So instead, we use cloning functionality that preserves references to
    // marks.
    override func copy(with zone: NSZone? = nil) -> Any {
        return FoldMark(self)
    }

    // Mark this as a doppelganger. When savedITOs is accessed, doppelganger
    // versions of the ITOs will be created lazily.
    override func becomeDoppelganger(withProgenitor progenitor: iTermMark) {
        super.becomeDoppelganger(withProgenitor: progenitor)
        _isDoppelganger = true
    }
}
