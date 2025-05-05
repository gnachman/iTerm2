//
//  iTermLegacyMutableString.swift
//  iTerm2
//
//  Created by George Nachman on 4/21/25.
//

@objc
protocol iTermLegacyString: AnyObject, iTermString {
    var eaIndex: iTermExternalAttributeIndexReading? { get }
    var screenCharArray: ScreenCharArray { get }
}

@objc
class iTermLegacyMutableString: iTermBaseString {
    let sca: MutableScreenCharArray

    @objc
    init(width: Int) {
        sca = MutableScreenCharArray(data: Data(repeating: 0, count: MemoryLayout<screen_char_t>.stride * (width + 1)),
                                     includingContinuation: true,
                                     metadata: iTermImmutableMetadataDefault(),
                                     continuation: screen_char_t())
    }

    @objc
    convenience init(width: Int, character: screen_char_t) {
        self.init(width: width)
        sca.setCharacter(character, in: fullRange)
    }

   required init(_ msca: MutableScreenCharArray) {
        self.sca = msca
    }

    override var description: String {
        return "<iTermLegacyMutableString: \(it_addressString) sca=\(sca.description)>"
    }

    @objc(eaIndexCreatingIfNeeded:)
    func eaIndex(createIfNeeded: Bool) -> iTermExternalAttributeIndex? {
        if let eaIndex = sca.eaIndex {
            return eaIndex
        }
        if !createIfNeeded {
            return nil
        }
        let result = iTermExternalAttributeIndex()
        sca.setExternalAttributesIndex(result)
        return result
    }

    @objc(setMetadata:)
    func set(metadata: iTermMetadata) {
        sca.setMetadata(metadata)
    }

    @objc
    var mutableScreenCharArray: MutableScreenCharArray { sca }

    @objc(setDWCSkipAt:)
    func setDWCSkip(at i: Int) {
        ScreenCharSetDWC_SKIP(sca.mutableLine.advanced(by: i))
    }

    @objc(eraseCodeAt:)
    func eraseCode(at i: Int) {
        sca.mutableLine[i].code = 0
        sca.mutableLine[i].complexChar = 0
    }
}

func iTermUsedLength(chars: UnsafePointer<screen_char_t>, count: Int32) -> Int32 {
    if count == 0 {
        return 0
    }
    var lastNonEmptyIndex = Int(count - 1)
    while lastNonEmptyIndex >= 0 {
        if chars[lastNonEmptyIndex].code != 0 && !ScreenCharIsDWC_SKIP(chars[lastNonEmptyIndex]) {
            break
        }
        lastNonEmptyIndex -= 1
    }
    return Int32(lastNonEmptyIndex + 1)
}

@objc
extension iTermLegacyMutableString: iTermLegacyString {
    func isEqual(to string: any iTermString) -> Bool {
        if cellCount != string.cellCount {
            return false
        }
        return isEqual(lhsRange: fullRange, toString: string, startingAtIndex: 0)
    }

    // This implements:
    // return self[lhsRange] == rhs[startIndex..<(startIndex+lhsRange.count)
    func isEqual(lhsRange: NSRange, toString rhs: iTermString, startingAtIndex startIndex: Int) -> Bool {
        if cellCount < NSMaxRange(lhsRange) || rhs.cellCount < startIndex + lhsRange.length {
            return false
        }
        if lhsRange == fullRange && startIndex == 0 {
            return screenCharArray.isEqual(to: rhs.screenCharArray)
        }
        let lhsSub = substring(range: lhsRange)
        let rhsSub = rhs.substring(range: NSRange(location: startIndex,
                                                  length: lhsRange.length))
        return lhsSub.screenCharArray.isEqual(rhsSub.screenCharArray)
    }

    func externalAttribute(at index: Int) -> iTermExternalAttribute? {
        guard let eaIndex else {
            return nil
        }
        return eaIndex[index]
    }

    var eaIndex: iTermExternalAttributeIndexReading? {
        eaIndex(createIfNeeded: false)
    }

    var cellCount: Int {
        Int(sca.length)
    }

    func usedLength(range: NSRange) -> Int32 {
        return iTermUsedLength(chars: sca.line.advanced(by: range.location),
                               count: Int32(range.length))
    }

    func stringBySettingRTL(in range: NSRange,
                            rtlIndexes: IndexSet?) -> any iTermString {
        let copy = sca.mutableSubArray(with: range)
        let line = copy.mutableLine
        for i in 0..<Int(copy.length) {
            if let rtlIndexes {
                line[i].rtlStatus = rtlIndexes.contains(i) ? .RTL : .LTR
            } else {
                line[i].rtlStatus = .unknown
            }
        }
        return Self(copy)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        var indexSet = IndexSet()
        let line = sca.line
        let offset = newBaseIndex - nsrange.location
        for i in Range(nsrange)! {
            if ScreenCharIsDWC_RIGHT(line[i]) {
                indexSet.insert(i + offset)
            }
        }
        return indexSet
    }

    func isEmpty(range: NSRange) -> Bool {
        let line = sca.line
        for i in Range(range)! {
            if !ScreenCharIsNull(line[i]) {
                return false
            }
        }
        return true
    }

    func hydrate(range: NSRange) -> ScreenCharArray {
        return sca.subArray(with: range)
    }

    func character(at i: Int) -> screen_char_t {
        sca.line[i]
    }

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        msca.copy(sourceRange, from: sca, destinationIndex: Int32(destinationIndex))
    }

    func hydrate(into buffer: UnsafeMutablePointer<screen_char_t>,
                 eaIndex: iTermExternalAttributeIndex?,
                 offset: Int32,
                 range: NSRange) {
        let start = range.location
        let length = range.length
        let src = sca.line.advanced(by: start)
        buffer.update(from: src, count: length)

        if let eaIndex {
            iTermImmutableMetadataGetExternalAttributesIndex(sca.metadata)?.copy(into: eaIndex)
        }
    }
    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        builder.append(chars: sca.line, count: sca.length)
    }

    func deltaString(range: NSRange) -> DeltaString {
        return _deltaString(range: range)
    }

    func mutableClone() -> any iTermMutableStringProtocol {
        let result = iTermLegacyMutableString(width: 0)
        result.append(string: self)
        return result
    }

    func clone() -> iTermString {
        return iTermLegacyStyleString(chars: sca.line, count: Int(sca.length), eaIndex: sca.eaIndex)
    }

    func externalAttributesIndex() -> iTermExternalAttributeIndexReading? {
        sca.eaIndex
    }

    var screenCharArray: ScreenCharArray {
        sca
    }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        return _hasEqual(range: range, to: chars)
    }

    func substring(range: NSRange) -> any iTermString {
        return _substring(range: range)
    }

    @objc func setRTLIndexes(_ indexSet: IndexSet) {
        let line = sca.mutableLine

        for (range, isMember) in indexSet.membership(in: 0..<cellCount) {
            let value = isMember ? RTLStatus.RTL : RTLStatus.LTR
            for i in range {
                line[i].rtlStatus = value
            }
        }
    }
    var mayContainDoubleWidthCharacter: Bool {
        return true
    }
    func mayContainDoubleWidthCharacter(in nsrange: NSRange) -> Bool {
        return true
    }
    func hasExternalAttributes(range: NSRange) -> Bool {
        if let eaIndex = sca.eaIndex {
            return !eaIndex.isEmpty
        }
        return false
    }
    enum CodingKeys: Int32, TLVTag {
        case line
        case eaIndex
        case metadata
        case continuation
    }

    func efficientlyEncodedData(range: NSRange, type: UnsafeMutablePointer<Int32>) -> Data {
        type.pointee = iTermStringType.legacyMutableString.rawValue

        var tlvEncoder = EfficientTLVEncoder<CodingKeys>()
        let subsca = sca.subArray(with: range)
        tlvEncoder.put(tag: .line, value: subsca.data)
        tlvEncoder.put(tag: .eaIndex, value: subsca.eaIndex)
        tlvEncoder.put(tag: .metadata, value: iTermImmutableMetadataEncodeToData(subsca.metadata))
        tlvEncoder.put(tag: .continuation, value: subsca.continuation)
        return tlvEncoder.data
    }
}

extension iTermLegacyMutableString: EfficientDecodable, EfficientEncodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self {
        var tlvDecoder: EfficientTLVDecoder<CodingKeys> = decoder.tlvDecoder()
        var dict = try tlvDecoder.decodeAll(required: Set([
            .line,
            .eaIndex,
            .metadata,
            .continuation]))

        let encodedMetadata = try Data.create(efficientDecoder: &(dict[.metadata]!))

        let msca = MutableScreenCharArray(
            data: try Data.create(efficientDecoder: &(dict[.line]!)),
            includingContinuation: true,
            metadata: iTermMetadataMakeImmutable(iTermMetadataDecodedFromData(encodedMetadata)),
            continuation: try screen_char_t.create(efficientDecoder: &(dict[.continuation]!)))
        return Self(msca)
    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        var type = Int32(0)
        let data = efficientlyEncodedData(range: fullRange, type: &type)
        encoder.putRawBytes(data)
    }
}


@objc
extension iTermLegacyMutableString: iTermMutableStringProtocol {
    @objc(deleteRange:)
    func objcDelete(range: NSRange) {
        sca.delete(range)
    }

    @objc func objcReplace(range: NSRange, with replacement: iTermString) {
        replace(range: Range(range)!, with: replacement)
    }

    @objc func append(string: iTermString) {
        sca.append(string.screenCharArray)
    }

    @objc func deleteFromStart(_ count: Int) {
        sca.delete(NSRange(location: 0, length: count))
    }

    func resetRTLStatus() {
        let line = sca.mutableLine
        for i in 0..<Int(sca.length) {
            line[i].rtlStatus = .unknown
        }
    }

    @objc func deleteFromEnd(_ count: Int) {
        sca.delete(NSRange(location: cellCount - count, length: count))
    }

    @objc(setExternalAttributes:)
    func set(externalAttributes source: iTermExternalAttributeIndexReading?) {
        if iTermImmutableMetadataGetExternalAttributesIndex(sca.metadata) == nil && source == nil {
            return
        }
        sca.setExternalAttributesIndex(source?.copy() as? iTermExternalAttributeIndex)
    }

    func erase(defaultChar: screen_char_t) {
        sca.setCharacter(defaultChar, in: fullRange)
    }

    @objc func setExternalAttributes(_ sourceIndex: iTermExternalAttributeIndexReading?,
                                     sourceRange: NSRange,
                                     destinationStartIndex: Int) {
        if let sourceIndex {
            let eaIndex = sca.eaIndexCreatingIfNeeded()
            eaIndex.copy(from: sourceIndex,
                         source: Int32(sourceRange.location),
                         destination: Int32(destinationStartIndex),
                         count: Int32(sourceRange.length))
        } else if let temp = sca.eaIndex {
            temp.setAttributes(nil,
                               at: Int32(destinationStartIndex),
                               count: Int32(sourceRange.length))
        }
    }
}

extension iTermLegacyMutableString: iTermMutableStringProtocolSwift {
    func delete(range: Range<Int>) {
        sca.delete(NSRange(range))
    }

    func replace(range: Range<Int>, with replacement: iTermString) {
        sca.delete(NSRange(range))
        sca.insert(replacement.screenCharArray, at: Int32(range.lowerBound))
    }

    func insert(_ string: iTermString, at index: Int) {
        sca.insert(string.screenCharArray, at: Int32(index))
    }
}
