//
//  iTermASCIIString.swift
//  iTerm2
//
//  Created by George Nachman on 4/21/25.
//

class iTermASCIIString: iTermBaseString, iTermString {
    private let data: SubData
    private let style: screen_char_t
    private let ea: iTermExternalAttribute?
    private let count: Int
    private var stringCache = SubStringCache()

    @objc
    required init(data: Data, style: screen_char_t, ea: iTermExternalAttribute?) {
        self.data = SubData(data: data, range: 0..<data.count)
        self.count = data.count
        self.style = style
        self.ea = ea
    }

    init(subdata: SubData, style: screen_char_t, ea: iTermExternalAttribute?) {
        self.data = subdata
        self.count = data.count
        self.style = style
        self.ea = ea
    }

    override var description: String {
        return "<iTermASCIIString: cells=\(cellCount) value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash()) \(ea?.description ?? "")>"
    }

    var cellCount: Int {
        count
    }

    func deltaString(range: NSRange) -> DeltaString {
        return stringCache.string(for: range) {
            _deltaString(range: range)
        }
    }

    func character(at off: Int) -> screen_char_t {
        return _character(at: off)
    }

    func hydrate(range: NSRange) -> ScreenCharArray {
        return _hydrate(range: range)
    }

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        var o = destinationIndex
        var i = sourceRange.location
        let buffer = msca.mutableLine
        let count = sourceRange.length
        if let ea {
            let eaIndex = msca.eaIndexCreatingIfNeeded()
            eaIndex.setAttributes(ea, at: Int32(o), count: Int32(count))
        }
        for _ in 0..<count {
            var sc = style
            sc.complexChar = 0
            sc.code = UInt16(data[i])
            buffer[o] = sc
            o += 1
            i += 1
        }
    }

    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        let sub = data[range.location..<range.location + range.length]
        builder.append(ascii: sub)
    }

    func mutableClone() -> any iTermMutableStringProtocol {
        return _mutableClone()
    }

    func clone() -> any iTermString {
        return self
    }

    func externalAttributesIndex() -> (any iTermExternalAttributeIndexReading)? {
        return _externalAttributesIndex()
    }

    var screenCharArray: ScreenCharArray {
        return _screenCharArray
    }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        return _hasEqual(range: range, to: chars)
    }

    func usedLength(range: NSRange) -> Int32 {
        min(Int32(data.range.count), Int32(range.length))
    }

    func isEmpty(range: NSRange) -> Bool {
        return range.length == 0
    }

    func substring(range: NSRange) -> any iTermString {
        return _substring(range: range)
    }

    func externalAttribute(at index: Int) -> iTermExternalAttribute? {
        return ea
    }

    func isEqual(to string: any iTermString) -> Bool {
        if cellCount != string.cellCount {
            return false
        }
        return isEqual(lhsRange: fullRange, toString: string, startingAtIndex: 0)
    }

    // This implements:
    // return self[lhsRange] == rhs[startIndex..<(startIndex+lhsRange.count)
    func isEqual(lhsRange lhsNSRange: NSRange, toString rhs: iTermString, startingAtIndex startIndex: Int) -> Bool {
        if cellCount < NSMaxRange(lhsNSRange) || rhs.cellCount < startIndex + lhsNSRange.length {
            return false
        }
        let lhsRange = Range(lhsNSRange)!
        let rhsRange = startIndex..<(startIndex + lhsNSRange.length)
        if let ascii = rhs as? iTermASCIIString {
            return (data[lhsRange] == ascii.data[rhsRange] &&
                    style == ascii.style &&
                    iTermExternalAttribute.externalAttribute(ea, isEqualTo: ascii.ea))
        }
        return substring(range: lhsNSRange).screenCharArray.isEqual(to: rhs.substring(range: NSRange(rhsRange)).screenCharArray)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        return IndexSet()
    }

    func stringBySettingRTL(in nsrange: NSRange,
                            rtlIndexes: IndexSet?) -> iTermString {
        if rtlIndexes == nil && style.rtlStatus == .unknown {
            return self
        }
        if let rtlIndexes, rtlIndexes.isEmpty && style.rtlStatus == .LTR {
            return self
        }
        var substrings = [iTermASCIIString]()
        if let rtlIndexes {
            for (range, rtl) in rtlIndexes.membership(in: Range(nsrange)!) {
                var style = self.style
                style.rtlStatus = rtl ? .RTL : .LTR
                substrings.append(iTermASCIIString(subdata: data[range], style: style, ea: ea))
            }
            return iTermRope(substrings)
        } else {
            var style = self.style
            style.rtlStatus = .unknown
            return iTermASCIIString(subdata: data, style: style, ea: ea)
        }
    }

    var mayContainDoubleWidthCharacter: Bool {
        false
    }
    func mayContainDoubleWidthCharacter(in nsrange: NSRange) -> Bool {
        false
    }
    func hasExternalAttributes(range: NSRange) -> Bool {
        return ea != nil
    }

    enum CodingKeys: Int32, TLVTag {
        case data
        case style
        case ea
    }

    func efficientlyEncodedData(range: NSRange, type: UnsafeMutablePointer<Int32>) -> Data {
        type.pointee = iTermStringType.asciiString.rawValue

        var tlvEncoder = EfficientTLVEncoder<CodingKeys>()
        tlvEncoder.put(tag: .data, value: data.data.subdata(in: Range(range)!))
        tlvEncoder.put(tag: .style, value: style)
        tlvEncoder.put(tag: .ea, value: ea)
        return tlvEncoder.data
    }
}

extension iTermASCIIString: EfficientDecodable, EfficientEncodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self {
        var tlvDecoder: EfficientTLVDecoder<CodingKeys> = decoder.tlvDecoder()
        var dict = try tlvDecoder.decodeAll(required: Set([.data, .style, .ea]))
        return Self(data: try Data.create(efficientDecoder: &(dict[.data]!)),
                    style: try screen_char_t.create(efficientDecoder: &(dict[.style]!)),
                    ea: try iTermExternalAttribute?.create(efficientDecoder: &(dict[.ea]!)))
    }
    
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        var type = Int32(0)
        let data = efficientlyEncodedData(range: fullRange, type: &type)
        encoder.putRawBytes(data)
    }
}

extension iTermExternalAttribute: EfficientEncodable, EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self {
        let data = try decoder.getRawBytes()
        guard let obj = Self.fromData(data) else {
            throw EfficientDecoderError()
        }
        return obj
    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putRawBytes(data())
    }
}

extension screen_char_t: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putScalar(self)
    }
}

extension Optional: EfficientEncodable, EfficientDecodable where Wrapped: EfficientEncodable & EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Optional<Wrapped> {
        let flag: UInt8 = try decoder.getScalar()
        if flag == 0 {
            return .none
        }
        let obj = try Wrapped.create(efficientDecoder: &decoder)
        return .some(obj)
    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        switch self {
        case .none:
            encoder.putScalar(UInt8(0))
        case .some(let obj):
            encoder.putScalar(UInt8(1))
            obj.encodeEfficiently(encoder: &encoder)
        }
    }
}
