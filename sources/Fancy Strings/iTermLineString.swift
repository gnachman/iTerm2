//
//  iTermLineString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
protocol iTermLineStringReading {
    var description: String { get }
    var content: any iTermString { get }
    var eol: Int32 { get }
    var metadata: iTermLineStringMetadata { get }
    var continuation: screen_char_t { get }
    func ensureImmutableLegacy() -> iTermLegacyString
    var externalImmutableMetadata: iTermImmutableMetadata { get }
    var timestamp: TimeInterval { get }
    var rtlFound: Bool { get }
    var immutableEAIndex: iTermExternalAttributeIndexReading? { get }
    var dirty: Bool { get }
    var isEmpty: Bool { get }
    var usedLength: Int32 { get }
    func screenCharsData(withEOL: Bool) -> Data
    func screenCharArray(bidi: BidiDisplayInfoObjc?) -> ScreenCharArray
    func copy(withEOL eol: Int32) -> iTermLineStringReading
    var bidi: BidiDisplayInfoObjc? { get }
}

extension iTermLineStringReading {
    func _screenCharsData(withEOL: Bool) -> Data {
        let lms = ensureImmutableLegacy()
        if withEOL {
            if lms.screenCharArray.hasValidAppendedContinuationMark() {
                lms.screenCharArray.makeSafe()
                return lms.screenCharArray.data
            }
            let m = lms.screenCharArray.mutableCopy() as! MutableScreenCharArray
            m.ensureContinuationMarkAppended()
            return m.data
        } else {
            if lms.screenCharArray.dataSizeMatchesLength() {
                return lms.screenCharArray.data
            }
            let m = lms.screenCharArray.mutableCopy() as! MutableScreenCharArray
            m.ensureContinuationMarkNotAppended()
            return m.data
        }
    }

    func _screenCharArray(bidi: BidiDisplayInfoObjc?) -> ScreenCharArray {
        return ScreenCharArray(data: screenCharsData(withEOL: true),
                               includingContinuation: true,
                               continuation: continuation,
                               date: Date(timeIntervalSinceReferenceDate: timestamp),
                               externalAttributes: immutableEAIndex,
                               rtlFound: metadata.rtlFound.boolValue,
                               bidiInfo: bidi)
    }
}

func iTermUsedLength(eol: Int32, content: iTermString) -> Int32 {
    // Figure out the line length.
    if eol == EOL_SOFT {
        return Int32(content.cellCount)
    }
    if eol == EOL_DWC {
        return Int32(content.cellCount - 1)
    }
    return content.usedLength(range: content.fullRange)
}

class iTermLineString: NSObject, iTermLineStringReading {
    @objc private(set) var content: iTermString
    @objc let eol: Int32  // EOL_HARD, EOL_SOFT, EOL_DWC
    @objc let continuation: screen_char_t
    @objc let metadata: iTermLineStringMetadata
    private var _externalMetadata: iTermImmutableMetadata?
    @objc let dirty: Bool
    @objc let bidi: BidiDisplayInfoObjc?

    @objc
    init(content: iTermString,
         eol: Int32,
         continuation: screen_char_t,
         metadata: iTermLineStringMetadata,
         bidi: BidiDisplayInfoObjc?,
         dirty: Bool) {
        self.content = content
        self.eol = eol
        var c = continuation
        c.code = unichar(eol)
        self.continuation = c
        self.metadata = metadata
        self.bidi = bidi
        self.dirty = dirty

        super.init()
    }

    deinit {
        if let _externalMetadata {
            iTermImmutableMetadataRelease(_externalMetadata)
            self._externalMetadata = nil
        }
    }

    override var description: String {
        let eolString = switch Int32(eol) {
        case EOL_HARD: "hard"
        case EOL_SOFT: "soft"
        case EOL_DWC: "dwc"
        default: "UNKNOWN (bug)"
        }
        return "<iTermLineString: \(it_addressString) eol=\(eolString) timestamp=\(metadata.timestamp) rtl=\(metadata.rtlFound) bidi=\(bidi.d) content=\(content.description)>"
    }

    var timestamp: TimeInterval {
        externalImmutableMetadata.timestamp
    }

    var rtlFound: Bool {
        externalImmutableMetadata.rtlFound.boolValue
    }

    var immutableEAIndex: iTermExternalAttributeIndexReading? {
        iTermImmutableMetadataGetExternalAttributesIndex(externalImmutableMetadata)
    }

    var isEmpty: Bool {
        if eol == EOL_SOFT || eol == EOL_DWC {
            return false
        }
        return content.isEmpty
    }

    @objc
    var usedLength: Int32 {
        return iTermUsedLength(eol: eol, content: content)
    }

    @objc
    func ensureImmutableLegacy() -> iTermLegacyString {
        if let lms = content as? iTermLegacyString {
            return lms
        }
        let replacement = iTermLegacyMutableString(width: 0)
        replacement.append(string: content)
        content = replacement
        return replacement
    }

    @objc
    var externalImmutableMetadata: iTermImmutableMetadata {
        if let _externalMetadata {
            return _externalMetadata
        }
        _externalMetadata = iTermImmutableMetadataDefault()
        iTermImmutableMetadataInit(&_externalMetadata!,
                                   metadata.timestamp,
                                   metadata.rtlFound.boolValue,
                                   content.externalAttributesIndex() as? iTermExternalAttributeIndex)
        return _externalMetadata!
    }

    func screenCharsData(withEOL: Bool) -> Data {
        return _screenCharsData(withEOL: withEOL)
    }

    func screenCharArray(bidi: BidiDisplayInfoObjc?) -> ScreenCharArray {
        return _screenCharArray(bidi: bidi)
    }

    func copy(withEOL eol: Int32) -> iTermLineStringReading {
        return iTermLineString(content: content,
                               eol: eol,
                               continuation: continuation,
                               metadata: metadata,
                               bidi: bidi,
                               dirty: dirty)
    }
}

class iTermMutableLineString: NSObject, iTermLineStringReading {
    private var _content: iTermMutableStringProtocolSwift
    @objc var eol: Int32 { // EOL_HARD, EOL_SOFT, EOL_DWC
        didSet {
            continuation.code = UInt16(eol)
        }
    }
    @objc var dirty = false
    @objc var continuation: screen_char_t
    @objc var metadata: iTermLineStringMetadata
    @objc var bidi: BidiDisplayInfoObjc?
    private var _lineInfo = VT100LineInfo()

    var content: iTermString { _content }
    @objc var mutableContent: iTermMutableStringProtocol {
        invalidate()
        return _content
    }
    @objc var lineInfo: VT100LineInfo {
        _lineInfo.setTimestamp(timestamp)
        _lineInfo.setRTLFound(rtlFound)
        _lineInfo.setExternalAttributeIndex(eaIndex)
        return _lineInfo
    }
    override var description: String {
        let eolString = switch Int32(eol) {
        case EOL_HARD: "hard"
        case EOL_SOFT: "soft"
        case EOL_DWC: "dwc"
        default: "UNKNOWN (bug)"
        }
        return "<iTermMutableLineString: \(it_addressString) eol=\(eolString) timestamp=\(metadata.timestamp) rtl=\(metadata.rtlFound) content=\(content.description)>"
    }
    @objc
    var timestamp: TimeInterval {
        get {
            metadata.timestamp
        }
        set {
            invalidate()
            metadata.timestamp = newValue
        }
    }

    @objc
    var rtlFound: Bool {
        get {
            metadata.rtlFound.boolValue
        }
        set {
            invalidate()
            metadata.rtlFound = ObjCBool(newValue)
        }
    }

    @objc
    var eaIndex: iTermExternalAttributeIndex? {
        let sca = content.hydrate(range: content.fullRange)
        return sca.eaIndex
    }

    @objc
    var hasExternalAttributes: Bool {
        return content.hasExternalAttributes(range: content.fullRange)
    }

    var immutableEAIndex: (any iTermExternalAttributeIndexReading)? {
        eaIndex
    }

    @objc
    var screenCharsData: Data {
        let lms = ensureLegacy()
        return lms.screenCharArray.data
    }

    @objc
    var mutableScreenCharsData: NSMutableData {
        invalidate()
        let lms = ensureLegacy()
        return lms.screenCharArray.mutableLineData()
    }

    @objc
    var usedLength: Int32 {
        return iTermUsedLength(eol: eol, content: _content)
    }

    @objc
    var isEmpty: Bool {
        if eol == EOL_SOFT || eol == EOL_DWC {
            return false
        }
        return _content.isEmpty
    }

    private var _externalMetadata: iTermMetadata?
    @objc
    var externalMetadata: iTermMetadata {
        if let _externalMetadata {
            return _externalMetadata
        }
        _externalMetadata = iTermMetadataDefault()
        iTermMetadataInit(&_externalMetadata!,
                          timestamp,
                          rtlFound,
                          content.externalAttributesIndex() as? iTermExternalAttributeIndex)
        return _externalMetadata!
    }

    @objc
    var externalImmutableMetadata: iTermImmutableMetadata {
        return iTermMetadataMakeImmutable(externalMetadata)
    }

    init(source: iTermMutableLineString) {
        _content = source._content.mutableCloneSwift()
        eol = source.eol
        dirty = source.dirty
        continuation = source.continuation
        metadata = source.metadata
    }

    @objc
    init(content: iTermMutableStringProtocol,
         eol: Int32,
         continuation: screen_char_t,
         metadata: iTermLineStringMetadata) {
        self._content = content as! (iTermMutableStringProtocolSwift)
        self.eol = eol
        self.continuation = continuation
        self.metadata = metadata

        super.init()
    }

    deinit {
        if let _externalMetadata {
            iTermMetadataRelease(_externalMetadata)
            self._externalMetadata = nil
        }
    }

    @objc(setExternalAttributes:)
    func set(externalAttributes eaIndex: iTermExternalAttributeIndexReading?) {
        invalidate()
        ensureLegacy().set(externalAttributes: eaIndex)
    }

    @objc
    func append(_ rhs: iTermLineStringReading) {
        _content.append(string: rhs.content)
        eol = rhs.eol
        metadata.timestamp = max(metadata.timestamp, rhs.metadata.timestamp)
        metadata.rtlFound = ObjCBool(metadata.rtlFound.boolValue || rhs.metadata.rtlFound.boolValue)
        continuation = rhs.continuation
        invalidate()
    }

    @objc
    func screenCharArray(range: NSRange) -> ScreenCharArray {
        return content.hydrate(range: range)
    }

    @objc
    func ensureLegacy() -> iTermLegacyMutableString {
        invalidate()
        if let lms = _content as? iTermLegacyMutableString {
            return lms
        }
        let replacement = iTermLegacyMutableString(width: 0)
        replacement.append(string: _content)
        _content = replacement
        return replacement
    }

    @objc
    func ensureImmutableLegacy() -> iTermLegacyString {
        if let lms = _content as? iTermLegacyString {
            return lms
        }
        let replacement = iTermLegacyMutableString(width: 0)
        replacement.append(string: _content)
        _content = replacement
        return replacement
    }

    @objc
    func erase(defaultChar: screen_char_t) {
        timestamp = 0
        rtlFound = false
        _content = iTermMutableRope(iTermUniformString(char: defaultChar,
                                                       length: _content.cellCount))
        eol = EOL_HARD
        continuation = defaultChar
        continuation.code = UInt16(EOL_HARD)
        invalidate()
    }

    @objc
    func mutableClone() -> iTermMutableLineString {
        return iTermMutableLineString(source: self)
    }

    @objc(setDWCSkip)
    func setDWCSkip() {
        let lms = ensureLegacy()
        let sca = lms.mutableScreenCharArray
        ScreenCharSetDWC_SKIP(sca.mutableLine.advanced(by: content.cellCount - 1))
        eol = EOL_DWC
    }

    @objc(eraseCharacterAt:)
    func eraseCharacterAt(_ i: Int32) {
        let lms = ensureLegacy()
        let sca = lms.mutableScreenCharArray
        let line = sca.mutableLine
        line[Int(i)].code = 0
        line[Int(i)].complexChar = 0
        line[Int(i)].image = 0
        invalidate()
    }

    @objc(lastCharacter)
    var lastCharacter: screen_char_t {
        let count = content.cellCount
        if count < 1 {
            return screen_char_t()
        }
        return content.character(at: count - 1)
    }

    @objc(eraseDWCRightAtIndex:currentDate:)
    func eraseDWCRight(at i: Int32, currentDate: TimeInterval) {
        let range = max(0, Int(i) - 1)..<(Int(i) + 1)
        _content.replace(range: range,
                         with: iTermUniformString(char: screen_char_t(),
                                                  length: range.count))
        dirty = true
        timestamp = currentDate
    }

    private func invalidate() {
        if let _externalMetadata {
            iTermMetadataRelease(_externalMetadata)
            self._externalMetadata = .none
        }
    }

    func screenCharsData(withEOL: Bool) -> Data {
        return _screenCharsData(withEOL: withEOL)
    }

    @objc(setContentSize:)
    func set(contentSize: Int) {
        let actual = _content.cellCount
        if actual == contentSize {
            return
        } else if actual < contentSize {
            _content.append(string: iTermUniformString(char: screen_char_t(), length: contentSize - actual))
        } else {
            _content.deleteFromEnd(actual - contentSize)
        }
    }

    func screenCharArray(bidi: BidiDisplayInfoObjc?) -> ScreenCharArray {
        return _screenCharArray(bidi: bidi)
    }

    func copy(withEOL eol: Int32) -> iTermLineStringReading {
        return iTermLineString(content: content,
                               eol: eol,
                               continuation: continuation,
                               metadata: metadata,
                               bidi: bidi,
                               dirty: dirty)
    }

    @objc(hasDWCRightAtIndex:)
    func hasDWCRight(at i: Int32) -> Bool {
        if !_content.mayContainDoubleWidthCharacter(in: NSRange(location: Int(i), length: 1)) {
            return false
        }
        return ScreenCharIsDWC_RIGHT(_content.character(at: Int(i)))
    }
}
