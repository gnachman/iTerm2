//
//  SelectionPromise.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/15/22.
//

import AppKit
import UniformTypeIdentifiers

fileprivate protocol Destination {
    var length: Int { get }
    func appendSelectionContent(_ value: Any, newline: Bool)
}

extension NSMutableString: Destination {
    func appendSelectionContent(_ value: Any, newline: Bool) {
        let string = String(value as! NSString)
        append(string)
        if newline && !string.hasSuffix("\n") {
            append("\n")
        }
    }

}
extension NSMutableAttributedString: Destination {
    func appendSelectionContent(_ value: Any, newline: Bool) {
        let attributedString = value as! NSAttributedString
        append(attributedString)
        if newline && !attributedString.string.hasSuffix("\n") {
            iterm_appendString("\n")
        }
    }
}

class SelectionExtractorDelegate: NSObject, iTermSelectionDelegate {
    private var realDelegate: iTermSelectionDelegate?
    private let width: Int32

    init(_ delegate: iTermSelectionDelegate) {
        realDelegate = delegate
        width = delegate.selectionViewportWidth()
    }

    func selectionDidChange(_ selection: iTermSelection!) {
    }

    func liveSelectionDidEnd() {
    }

    func selectionAbsRangeForParenthetical(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange {
        return realDelegate!.selectionAbsRangeForParenthetical(at: coord)
    }

    func selectionAbsRangeForWord(at coord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange {
        return realDelegate!.selectionAbsRangeForWord(at: coord)
    }

    func selectionAbsRangeForSmartSelection(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange {
        return realDelegate!.selectionAbsRangeForSmartSelection(at: absCoord)
    }

    func selectionAbsRangeForWrappedLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange {
        return realDelegate!.selectionAbsRangeForWrappedLine(at: absCoord)
    }

    func selectionAbsRangeForLine(at absCoord: VT100GridAbsCoord) -> VT100GridAbsWindowedRange {
        return realDelegate!.selectionAbsRangeForLine(at: absCoord)
    }

    func selectionRangeOfTerminalNulls(onAbsoluteLine absLineNumber: Int64) -> VT100GridRange {
        return realDelegate!.selectionRangeOfTerminalNulls(onAbsoluteLine: absLineNumber)
    }

    func selectionPredecessor(of absCoord: VT100GridAbsCoord) -> VT100GridAbsCoord {
        return realDelegate!.selectionPredecessor(of: absCoord)
    }

    func selectionViewportWidth() -> Int32 {
        return width
    }

    func selectionTotalScrollbackOverflow() -> Int64 {
        return realDelegate!.selectionTotalScrollbackOverflow()
    }

    func selectionIndexes(onAbsoluteLine line: Int64, containingCharacter c: unichar, in range: NSRange) -> IndexSet! {
        return realDelegate!.selectionIndexes(onAbsoluteLine: line, containingCharacter: c, in: range)
    }


}
@objc(iTermSelectionExtractor)
class SelectionExtractor: NSObject {
    fileprivate let selection: iTermSelection
    fileprivate let snapshot: TerminalContentSnapshot
    fileprivate let options: iTermSelectionExtractorOptions
    private let maxBytes: Int32
    private let minimumLineNumber: Int32
    private var atomicExtractor = MutableAtomicObject<iTermTextExtractor?>(nil)
    private var _canceled = MutableAtomicObject<Bool>(false)
    private let selectionDelegate: SelectionExtractorDelegate
    fileprivate var canceled: Bool {
        return _canceled.value
    }
    @objc var progress: Progress?
    @objc var addTimestamps = false
    // Subclasses override to disable DECDHL dedup (e.g., Copy with
    // Control Sequences needs both top and bottom halves).
    var shouldDeduplicateDECDHL: Bool { true }

    // Does not include selected text on lines before |minimumLineNumber|.
    // Returns an NSAttributedString* if style is iTermCopyTextStyleAttributed, or an NSString* if not.
    @objc
    init?(selection: iTermSelection,
          snapshot: TerminalContentSnapshot?,
          options: iTermSelectionExtractorOptions,
          maxBytes: Int32,
         minimumLineNumber: Int32) {
        guard let snapshot = snapshot else {
            return nil
        }
        let selectionDelegate = SelectionExtractorDelegate(selection.delegate!)
        self.selectionDelegate = selectionDelegate

        self.selection = selection.copy() as! iTermSelection
        self.selection.delegate = selectionDelegate
        self.selection.endLive()
        
        self.snapshot = snapshot
        self.options = options
        self.maxBytes = maxBytes
        self.minimumLineNumber = minimumLineNumber
    }

    func withRelativeWindowedRange(_ range: VT100GridAbsWindowedRange, closure: (VT100GridWindowedRange) -> Void) -> Bool {
        if range.coordRange.start.y < snapshot.cumulativeOverflow || range.coordRange.start.y - snapshot.cumulativeOverflow > Int32.max {
            return false
        }
        if range.coordRange.end.y < snapshot.cumulativeOverflow || range.coordRange.end.y - snapshot.cumulativeOverflow > Int32.max {
            return false
        }
        let relative = VT100GridWindowedRangeFromAbsWindowedRange(range, snapshot.cumulativeOverflow)
        closure(relative)
        return true

    }

    private func weight(_ selection: iTermSelection) -> Double {
        return Double(selection.approximateNumberOfLines)
    }

    private func weight(_ range: VT100GridAbsWindowedRange) -> Double {
        return Double(range.coordRange.end.y - range.coordRange.start.y + 1)
    }

    fileprivate func extract(_ result: Destination,
                             attributeProvider: ((screen_char_t, iTermExternalAttribute, UnsafePointer<iTermImmutableMetadata>?) -> [AnyHashable: Any])?) {
        DLog("Begin extracting \(String(describing: selection.allSubSelections)) self=\(self)")
        var cap = maxBytes > 0 ? maxBytes : Int32.max
        var fractionSoFar = Double(0)
        let totalWeight = weight(selection)
        // DECDHL deduplication: track the previous sub-selection's last
        // line so we can skip the bottom half of a double-height pair
        // when it duplicates the top half. This handles box selections
        // where each line is a separate sub-selection.
        var prevSCA: ScreenCharArray?
        selection.enumerateSelectedAbsoluteRanges { [unowned self] absRange, stopPtr, eol in
            let subselectionWeight = weight(absRange) / totalWeight
            if _canceled.value {
                DLog("stop early")
                return
            }
            DLog("\(it_addressString) work on \(VT100GridAbsWindowedRangeDescription(absRange))")
            _ = withRelativeWindowedRange(absRange) { [unowned self] proposedRange in
                if proposedRange.coordRange.end.y < minimumLineNumber {
                    return
                }
                let range = VT100GridWindowedRangeMake(
                    VT100GridCoordRangeMake(proposedRange.coordRange.start.x,
                                            max(proposedRange.coordRange.start.y, minimumLineNumber),
                                            proposedRange.coordRange.end.x,
                                            proposedRange.coordRange.end.y),
                    proposedRange.columnWindow.location,
                    proposedRange.columnWindow.length)
                if maxBytes > 0 {
                    cap = maxBytes - Int32(result.length)
                    if cap <= 0 {
                        stopPtr?.pointee = ObjCBool(true)
                        return
                    }
                }
                let extractor = iTermTextExtractor(dataSource: snapshot)
                extractor.supportBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
                if let progress {
                    progress.transform = { localFraction in
                        fractionSoFar + localFraction * subselectionWeight
                    }
                    extractor.progress = progress
                }
                atomicExtractor.set(extractor)
                extractor.addTimestamps = addTimestamps
                // DECDHL deduplication: skip the bottom half when it
                // matches the preceding top half.
                if shouldDeduplicateDECDHL {
                    let lastLineY = range.coordRange.end.y
                    let lastSCA = snapshot.screenCharArray(forLine: lastLineY)
                    defer { prevSCA = lastSCA }
                    let firstSCA = (range.coordRange.start.y == lastLineY)
                        ? lastSCA
                        : snapshot.screenCharArray(forLine: range.coordRange.start.y)
                    if let prev = prevSCA, firstSCA.isDECDHLDuplicate(of: prev) {
                        return
                    }
                }

                let content = content(in: range,
                                      attributeProvider: attributeProvider,
                                      options: options,
                                      cappedAtSize: cap,
                                      extractor: extractor,
                                      deduplicateDECDHL: shouldDeduplicateDECDHL)
                atomicExtractor.set(nil)
                result.appendSelectionContent(content, newline: eol)
            }
            DLog("\(it_addressString) done with \(VT100GridAbsWindowedRangeDescription(absRange))")
            fractionSoFar += subselectionWeight
        }
        DLog("Finish extracting \(String(describing: selection.allSubSelections)). canceled=\(_canceled.value) self=\(self)")
    }

    fileprivate func content(in range: VT100GridWindowedRange,
                             attributeProvider: ((screen_char_t, iTermExternalAttribute, UnsafePointer<iTermImmutableMetadata>?) -> [AnyHashable: Any])?,
                             options: iTermSelectionExtractorOptions,
                             cappedAtSize cap: Int32,
                             extractor: iTermTextExtractor,
                             deduplicateDECDHL: Bool) -> Any {
        return extractor.content(in: range,
                                 attributeProvider: attributeProvider,
                                 nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                                 pad: false,
                                 includeLastNewline: options.contains(.copyLastNewline),
                                 trimTrailingWhitespace: options.contains(.trimWhitespace),
                                 cappedAtSize: cap,
                                 truncateTail: true,
                                 continuationChars: nil,
                                 coords: nil,
                                 deduplicateDECDHL: deduplicateDECDHL)
    }

    fileprivate func cancel() {
        DLog("cancel \(it_addressString)")
        _canceled.set(true)
        atomicExtractor.access { maybeExtractor in
            maybeExtractor?.stopAsSoonAsPossible = true
        }
    }
}

@objc(iTermStringSelectionExtractor)
class StringSelectionExtractor: SelectionExtractor {
    func extract() -> NSString {
        if !selection.hasSelection {
            return ""
        }

        let result = NSMutableString()
        super.extract(result, attributeProvider: nil)
        return result
    }
}

@objc(iTermSGRSelectionExtractor)
class SGRSelectionExtractor: StringSelectionExtractor {
    override var shouldDeduplicateDECDHL: Bool { false }
    override func extract() -> NSString {
        if !selection.hasSelection {
            return ""
        }
        let sgrAttribute = NSAttributedString.Key("iTermSGR")
        let lineAttrAttribute = NSAttributedString.Key("iTermLineAttribute")
        let attributeProvider = { (c: screen_char_t, ea: iTermExternalAttribute?, metadata: UnsafePointer<iTermImmutableMetadata>?) -> [AnyHashable: Any] in
            let codes = VT100Terminal.sgrCodes(forCharacter: c, externalAttributes: ea)!
            var attrs: [AnyHashable: Any] = [sgrAttribute: codes.array]
            if let metadata {
                let la = metadata.pointee.lineAttribute
                if la != .singleWidth {
                    attrs[lineAttrAttribute] = la.rawValue
                }
            }
            return attrs
        }
        let temp = NSMutableAttributedString()
        super.extract(temp, attributeProvider: attributeProvider)
        let result = NSMutableString()
        let sgr0 = "\u{1b}[0m"
        // Collect the DEC line attribute for each line in the output.
        // Lines are separated by \n in the attributed string.
        var lineAttributes = [iTermLineAttribute]()
        var currentLA: iTermLineAttribute = .singleWidth
        for i in 0..<temp.length {
            if let rawLA = temp.attribute(lineAttrAttribute, at: i, effectiveRange: nil) as? Int32,
               let la = iTermLineAttribute(rawValue: rawLA) {
                currentLA = la
            }
            if i == 0 {
                lineAttributes.append(currentLA)
            }
            if (temp.string as NSString).character(at: i) == unichar(Character("\n").asciiValue!) {
                // Next line starts after this newline
                if i + 1 < temp.length {
                    if let rawLA = temp.attribute(lineAttrAttribute, at: i + 1, effectiveRange: nil) as? Int32,
                       let la = iTermLineAttribute(rawValue: rawLA) {
                        lineAttributes.append(la)
                    } else {
                        lineAttributes.append(.singleWidth)
                    }
                }
            }
        }

        // Build the SGR output without DEC sequences.
        temp.enumerateAttribute(sgrAttribute,
                                in: NSMakeRange(0, temp.length),
                                options: []) { value, range, stop in
            let params = value as! [String]
            let code = "\u{1b}[" + params.joined(separator: ";") + "m"
            result.append(code)
            let swiftRange = Range(range, in: temp.string)!
            result.append(String(temp.string[swiftRange]))
        }
        result.append(sgr0)
        // Insert DEC line attribute sequences and SGR resets at newlines.
        // Process from end to start so insertions don't shift indices.
        let lines = (result as String).components(separatedBy: "\n")
        let rebuilt = NSMutableString()
        for (i, line) in lines.enumerated() {
            if i < lineAttributes.count {
                switch lineAttributes[i] {
                case .doubleWidth:
                    rebuilt.append("\u{1b}#6")
                case .doubleHeightTop:
                    rebuilt.append("\u{1b}#3")
                case .doubleHeightBottom:
                    rebuilt.append("\u{1b}#4")
                default:
                    break
                }
            }
            rebuilt.append(line)
            if i < lines.count - 1 {
                rebuilt.append(sgr0 + "\n")
            }
        }
        return rebuilt
    }
}

@objc(iTermAttributedStringSelectionExtractor)
class AttributedStringSelectionExtractor: SelectionExtractor {
    func extract(_ characterAttributesProvider: CharacterAttributesProvider) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if !selection.hasSelection {
            return result
        }

        let attributeProvider = { (c: screen_char_t, ea: iTermExternalAttribute, metadata: UnsafePointer<iTermImmutableMetadata>?) -> [AnyHashable: Any] in
            return characterAttributesProvider.attributes(c, externalAttributes: ea, metadata: metadata)
        }
        super.extract(result, attributeProvider: attributeProvider)
        return result
    }
}

extension iTermLocatedString: Destination {
    func appendSelectionContent(_ value: Any, newline: Bool) {
        let sub = value as! iTermLocatedString
        append(sub)
    }
}

class LocatedStringSelectionExtractor: SelectionExtractor {
    func extract() -> iTermLocatedString {
        let result = iTermLocatedString()
        if !selection.hasSelection {
            return result
        }

        super.extract(result, attributeProvider: nil)
        return result
    }

    fileprivate override func content(in range: VT100GridWindowedRange,
                                      attributeProvider: ((screen_char_t, iTermExternalAttribute, UnsafePointer<iTermImmutableMetadata>?) -> [AnyHashable : Any])?,
                                      options: iTermSelectionExtractorOptions,
                                      cappedAtSize cap: Int32,
                                      extractor: iTermTextExtractor,
                                      deduplicateDECDHL: Bool) -> Any {
        return extractor.locatedString(in: range,
                                       attributeProvider: attributeProvider,
                                       nullPolicy: .kiTermTextExtractorNullPolicyMidlineAsSpaceIgnoreTerminal,
                                       pad: false,
                                       includeLastNewline: options.contains(.copyLastNewline),
                                       trimTrailingWhitespace: options.contains(.trimWhitespace),
                                       cappedAtSize: cap,
                                       truncateTail: true,
                                       continuationChars: nil,
                                       deduplicateDECDHL: deduplicateDECDHL)
    }
}

@objc(iTermSelectionPromise)
class SelectionPromise: NSObject {
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.iterm2.selection")
        return queue
    }()

    @objc
    class func string(_ extractor: StringSelectionExtractor?,
                      allowEmpty: Bool) -> iTermRenegablePromise<NSString>? {
        guard let extractor = extractor else {
            return nil
        }

        return iTermRenegablePromise<NSString>.init { seal in
            Self.queue.async {
                let value = extractor.extract()
                if extractor.canceled {
                    seal.rejectWithDefaultError()
                    return
                }
                if value.length == 0 && !allowEmpty {
                    seal.rejectWithDefaultError()
                    return
                }
                seal.fulfill(value)
            }
        } renege: {
            extractor.cancel()
        }
    }

    @objc
    class func attributedString(_ extractor: AttributedStringSelectionExtractor?,
                                characterAttributesProvider: CharacterAttributesProvider,
                                allowEmpty: Bool) -> iTermRenegablePromise<NSAttributedString>? {
        guard let extractor = extractor else {
            return nil
        }

        return iTermRenegablePromise<NSAttributedString>.init { seal in
            Self.queue.async {
                let value = extractor.extract(characterAttributesProvider)
                if extractor.canceled {
                    seal.rejectWithDefaultError()
                    return
                }
                if value.length == 0 && !allowEmpty {
                    seal.rejectWithDefaultError()
                    return
                }
                seal.fulfill(value)
            }
        } renege: {
            extractor.cancel()
        }
    }
}

@objc(iTermAsyncSelectionProvider)
class AsyncSelectionProvider: NSObject, NSPasteboardWriting {
    @objc static var currentProvider: AsyncSelectionProvider? = nil

    @objc(copyPromise:type:)
    static func copy(_ promise: iTermRenegablePromise<AnyObject>,
                     type: NSPasteboard.PasteboardType) {
        let provider = AsyncSelectionProvider(promise, type: type)
        Self.currentProvider?.cancel()
        Self.currentProvider = provider
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([provider])
    }

    private let promise: iTermRenegablePromise<AnyObject>
    private let pasteboardType: NSPasteboard.PasteboardType

    private init(_ promise: iTermRenegablePromise<AnyObject>,
                 type: NSPasteboard.PasteboardType) {
        self.promise = promise
        self.pasteboardType = type
    }

    @objc func cancel() {
        promise.renege()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [pasteboardType]
    }

    func pasteboardPropertyList(forType pasteboardType: NSPasteboard.PasteboardType) -> Any? {
        DLog("Blocking on value")
        let or = promise.wait()
        let result = or.maybeFirst
        if let obj = result as? NSObject {
            if let attributedString = obj as? NSAttributedString {
                if let data = try? attributedString.data(from: NSRange(from: 0, to: attributedString.length),
                                                         documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                    DLog("Return data from attributed string \(attributedString)")
                    return data
                }
            }
            let length = (result as? Destination)?.length ?? -1
            DLog("Return result of length \(length), type \(NSStringFromClass(type(of: obj)))")
            return result
        }
        DLog("error \(or.maybeSecond?.description ?? "(nil)")")
        return nil
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType,
                        pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        return .promised
    }
}

func withRelativeWindowedRange(_ range: VT100GridAbsWindowedRange,
                               cumulativeOverflow: Int64,
                               closure: (VT100GridWindowedRange) -> Void) -> Bool {
    if range.coordRange.start.y < cumulativeOverflow || range.coordRange.start.y - cumulativeOverflow > Int32.max {
        return false
    }
    if range.coordRange.end.y < cumulativeOverflow || range.coordRange.end.y - cumulativeOverflow > Int32.max {
        return false
    }
    let relative = VT100GridWindowedRangeFromAbsWindowedRange(range, cumulativeOverflow)
    closure(relative)
    return true

}
