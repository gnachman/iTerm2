//
//  iTermLineString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
protocol iTermLineStringReading {
    var content: any iTermString { get }
    var eol: Int32 { get }
    var metadata: iTermLineStringMetadata { get }
    var continuation: screen_char_t { get }
}

class iTermLineString: NSObject, iTermLineStringReading {
    @objc let content: iTermString
    @objc let eol: Int32  // EOL_HARD, EOL_SOFT, EOL_DWC
    @objc let continuation: screen_char_t
    @objc let metadata: iTermLineStringMetadata

    @objc
    init(content: iTermMutableString,
         eol: Int32,
         continuation: screen_char_t,
         metadata: iTermLineStringMetadata) {
        self.content = content
        self.eol = eol
        self.continuation = continuation
        self.metadata = metadata

        super.init()
    }

    override var description: String {
        let eolString = switch Int32(eol) {
        case EOL_HARD: "hard"
        case EOL_SOFT: "soft"
        case EOL_DWC: "dwc"
        default: "UNKNOWN (bug)"
        }
        return "<iTermLineString: \(it_addressString) eol=\(eolString) timestamp=\(metadata.timestamp) rtl=\(metadata.rtlFound) content=\(content.description)>"
    }
}

class iTermMutableLineString: NSObject, iTermLineStringReading {
    private var _content: iTermMutableStringProtocol & iTermString
    @objc var eol: Int32 { // EOL_HARD, EOL_SOFT, EOL_DWC
        didSet {
            continuation.code = UInt16(eol)
        }
    }
    @objc var dirty = false
    @objc var continuation: screen_char_t
    @objc var metadata: iTermLineStringMetadata
    private var _lineInfo = VT100LineInfo()

    var content: iTermString { _content }
    @objc var mutableContent: iTermMutableStringProtocol { _content }
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
            metadata.timestamp = newValue
        }
    }

    @objc
    var rtlFound: Bool {
        get {
            metadata.rtlFound.boolValue
        }
        set {
            metadata.rtlFound = ObjCBool(newValue)
        }
    }

    @objc
    var eaIndex: iTermExternalAttributeIndex? {
        let sca = content.hydrate(range: content.fullRange)
        return sca.eaIndex
    }

    @objc
    var screenCharsData: Data {
        let lms = ensureLegacy()
        return lms.screenCharArray.data
    }

    @objc
    var mutableScreenCharsData: NSMutableData {
        let lms = ensureLegacy()
        return lms.screenCharArray.mutableLineData()
    }

    init(source: iTermMutableLineString) {
        _content = source._content.mutableClone()
        eol = source.eol
        dirty = source.dirty
        continuation = source.continuation
        metadata = source.metadata
    }

    @objc
    init(content: iTermMutableStringProtocol & iTermString,
         eol: Int32,
         continuation: screen_char_t,
         metadata: iTermLineStringMetadata) {
        self._content = content
        self.eol = eol
        self.continuation = continuation
        self.metadata = metadata

        super.init()
    }

    @objc(setExternalAttributes:)
    func set(externalAttributes eaIndex: iTermExternalAttributeIndexReading?) {
        _content.set(externalAttributes: eaIndex, offset: 0)
    }

    @objc
    func append(_ rhs: iTermLineStringReading) {
        _content.append(string: rhs.content)
        eol = rhs.eol
        metadata.timestamp = max(metadata.timestamp, rhs.metadata.timestamp)
        metadata.rtlFound = ObjCBool(metadata.rtlFound.boolValue || rhs.metadata.rtlFound.boolValue)
        continuation = rhs.continuation
    }

    @objc
    func screenCharArray(range: NSRange) -> ScreenCharArray {
        return content.hydrate(range: range)
    }

    @objc
    func ensureLegacy() -> iTermLegacyMutableString {
        if let lms = _content as? iTermLegacyMutableString {
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
        set(externalAttributes: nil)
        _content.erase(defaultChar: defaultChar)
        eol = EOL_HARD
        continuation = defaultChar
        continuation.code = UInt16(EOL_HARD)
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
    }

    @objc(eraseCharacterAt:)
    func eraseCharacterAt(_ i: Int32) {
        let lms = ensureLegacy()
        let sca = lms.mutableScreenCharArray
        let line = sca.mutableLine
        line[Int(i)].code = 0
        line[Int(i)].complexChar = 0
        line[Int(i)].image = 0
    }

    @objc(lastCharacter)
    var lastCharacter: screen_char_t {
        let count = content.cellCount
        if count < 1 {
            return screen_char_t()
        }
        return content.character(at: count - 1)
    }
}
