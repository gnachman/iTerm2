//
//  iTermLegacyStyleString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermLegacyStyleString: iTermBaseString, iTermString {
    let line: [screen_char_t]
    private let eaIndex: iTermExternalAttributeIndexReading?
    private var stringCache = SubStringCache()

    @objc
    init(chars: UnsafePointer<screen_char_t>,
         count: Int,
         eaIndex: iTermExternalAttributeIndexReading?) {
        let buffer = UnsafeBufferPointer(start: chars, count: count)
        self.line = Array(buffer)
        self.eaIndex = eaIndex?.copy()
        super.init()
    }

    required init(line: [screen_char_t], eaIndex: iTermExternalAttributeIndexReading?) {
        self.line = line
        self.eaIndex = eaIndex
    }

    init(_ sca: ScreenCharArray) {
        let buffer = UnsafeBufferPointer(start: sca.line, count: Int(sca.length))
        line = Array(buffer)
        eaIndex = sca.eaIndex
    }

    var cellCount: Int { line.count }

    override var description: String {
        return "<iTermLegacyStyleString: cells=\(cellCount) ea=\(eaIndex?.description ?? "") value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash())>"
    }

    func usedLength(range: NSRange) -> Int32 {
        line.withUnsafeBufferPointer { ubp in
            return iTermUsedLength(chars: ubp.baseAddress!.advanced(by: range.location),
                                   count: Int32(range.length))
        }
    }

    func isEmpty(range: NSRange) -> Bool {
        if range.length == 0 {
            return true
        }
        return line.allSatisfy {
            ScreenCharIsNull($0)
        }
    }

    func deltaString(range: NSRange) -> DeltaString {
        return stringCache.string(for: range) {
            _deltaString(range: range)
        }
    }

    func character(at i: Int) -> screen_char_t {
        line[i]
    }

    func hydrate(range: NSRange) -> ScreenCharArray {
        return _hydrate(range: range)
    }

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        let destIndex = eaIndex != nil ? msca.eaIndexCreatingIfNeeded() : msca.eaIndex
        hydrate(into: msca.mutableLine,
                eaIndex: destIndex,
                offset: Int32(destinationIndex),
                range: sourceRange)
    }

    func hydrate(into buffer: UnsafeMutablePointer<screen_char_t>,
                 eaIndex: iTermExternalAttributeIndex?,
                 offset: Int32,
                 range: NSRange) {
        let start = range.location
        let length = range.length

        line.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!
                .advanced(by: start)
                .withMemoryRebound(to: screen_char_t.self, capacity: length) { src in
                    let dest = buffer.advanced(by: Int(offset))
                    dest.update(from: src, count: length)
                }
        }
        if let eaIndex {
            eaIndex.copy(from: self.eaIndex,
                         source: Int32(range.lowerBound),
                         destination: offset,
                         count: Int32(range.length))
        }
    }

    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        line.withUnsafeBufferPointer { ubp in
            builder.append(chars: ubp.baseAddress!.advanced(by: range.location),
                           count: CInt(range.length))
        }
    }

    @objc
    func externalAttributesIndex() -> (any iTermExternalAttributeIndexReading)? {
        return _externalAttributesIndex()
    }

    @objc
    var screenCharArray: ScreenCharArray { _screenCharArray }

    func mutableClone() -> any iTermMutableStringProtocol {
        return _mutableClone()
    }

    func clone() -> any iTermString {
        return self
    }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        return _hasEqual(range: range, to: chars)
    }

    func substring(range: NSRange) -> any iTermString {
        return _substring(range: range)
    }

    func externalAttribute(at index: Int) -> iTermExternalAttribute? {
        guard let eaIndex else {
            return nil
        }
        return eaIndex[index]
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
        if let lss = rhs as? iTermLegacyStyleString {
            return (line[lhsRange] == lss.line[rhsRange] &&
                    iTermExternalAttributeIndex.externalAttributeIndex(
                        eaIndex?.subAttributes(in: lhsNSRange),
                        isEqualToIndex: lss.eaIndex?.subAttributes(in: NSRange(rhsRange))))
        }
        return substring(range: lhsNSRange).screenCharArray.isEqual(to: rhs.substring(range: NSRange(rhsRange)).screenCharArray)
    }

    func stringBySettingRTL(in nsrange: NSRange,
                            rtlIndexes: IndexSet?) -> iTermString {
        let range = Range(nsrange)!
        let subEAIndex = nsrange == fullRange ? eaIndex : eaIndex?.subAttributes(in: nsrange)
        return iTermLegacyStyleString(line: line[range].enumerated().map { i, c in
            var temp = c
            if let rtlIndexes {
                temp.rtlStatus = rtlIndexes.contains(i) ? .RTL : .LTR
            } else {
                temp.rtlStatus = .unknown
            }
            return temp
        }, eaIndex: subEAIndex)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        var indexSet = IndexSet()
        let offset = newBaseIndex - nsrange.location
        for i in Range(nsrange)! {
            if ScreenCharIsDWC_RIGHT(line[i]) {
                indexSet.insert(i + offset)
            }
        }
        return indexSet
    }
    var mayContainDoubleWidthCharacter: Bool {
        true
    }
    func mayContainDoubleWidthCharacter(in nsrange: NSRange) -> Bool {
        true
    }
    func hasExternalAttributes(range: NSRange) -> Bool {
        if let eaIndex {
            return !eaIndex.isEmpty
        }
        return false
    }
    enum CodingKeys: Int32, TLVTag {
        case line
        case eaIndex
    }

    func efficientlyEncodedData(range: NSRange, type: UnsafeMutablePointer<Int32>) -> Data {
        type.pointee = iTermStringType.legacyStyleString.rawValue

        var tlvEncoder = EfficientTLVEncoder<CodingKeys>()
        tlvEncoder.put(tag: .line, value: Array(line[Range(range)!]))
        tlvEncoder.put(tag: .eaIndex, value: eaIndex?.subAttributes(in: range))
        return tlvEncoder.data
    }
}

extension iTermLegacyStyleString: EfficientDecodable, EfficientEncodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self {
        var tlvDecoder: EfficientTLVDecoder<CodingKeys> = decoder.tlvDecoder()
        var dict = try tlvDecoder.decodeAll(required: Set([.line, .eaIndex]))
        return Self(
            line: try Array<screen_char_t>.create(efficientDecoder: &(dict[.line]!)),
            eaIndex: try Optional<iTermExternalAttributeIndex>.create(efficientDecoder: &(dict[.eaIndex]!)))
    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        var type = Int32(0)
        let data = efficientlyEncodedData(range: fullRange, type: &type)
        encoder.putRawBytes(data)
    }
}

extension iTermExternalAttributeIndex: EfficientDecodable, EfficientEncodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self {
        let data = try Data.create(efficientDecoder: &decoder)
        if let value = iTermExternalAttributeIndex.fromData(data) {
            return value as! Self
        }
        throw EfficientDecoderError()
    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putRawBytes(data())
    }
}
