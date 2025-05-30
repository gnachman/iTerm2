//
//  iTermUniformString.swift
//  iTerm2
//
//  Created by George Nachman on 4/22/25.
//

@objc
class iTermUniformString: iTermBaseString, iTermString {
    private let char: screen_char_t
    private let length: Int
    private var stringCache = SubStringCache()
    private let isDWCRight: Bool

    @objc(initWithCharacter:count:)
    required init(char: screen_char_t, length: Int) {
        self.char = char
        self.length = length
        isDWCRight = ScreenCharIsDWC_RIGHT(char)
    }

    override var description: String {
        return "<iTermUniformString: \(it_addressString) cells=\(cellCount) char=\(char)>"
    }

    var cellCount: Int { length }

    func deltaString(range: NSRange) -> DeltaString {
        return stringCache.string(for: range) {
            _deltaString(range: range)
        }
    }

    func character(at off: Int) -> screen_char_t {
        return char
    }

    func hydrate(range: NSRange) -> ScreenCharArray {
        return _hydrate(range: range)
    }

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        msca.setCharacter(char,
                          in: NSRange(location: destinationIndex,
                                      length: sourceRange.length))
    }

    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        builder.append(char: char, repeated: range.length)
    }

    func mutableClone() -> any iTermMutableStringProtocol {
        return _mutableClone()
    }

    func clone() -> any iTermString {
        return self
    }

    func externalAttributesIndex() -> (any iTermExternalAttributeIndexReading)? {
        return nil
    }

    var screenCharArray: ScreenCharArray {
        return _screenCharArray
    }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        for i in Range(range)! {
            if chars[i] != char {
                return false
            }
        }
        return true
    }

    func usedLength(range: NSRange) -> Int32 {
        if ScreenCharIsNull(char) {
            return 0
        }
        return min(Int32(length), Int32(range.length))
    }

    func isEmpty(range: NSRange) -> Bool {
        return range.length == 0 || ScreenCharIsNull(char)
    }

    func substring(range: NSRange) -> any iTermString {
        return iTermUniformString(char: char, length: range.length)
    }

    func externalAttribute(at index: Int) -> iTermExternalAttribute? {
        return nil
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
        if let us = rhs as? iTermUniformString {
            return char == us.char
        }
        let rhsRange = startIndex..<(startIndex + lhsNSRange.length)
        return substring(range: lhsNSRange).screenCharArray.isEqual(to: rhs.substring(range: NSRange(rhsRange)).screenCharArray)
    }

    func stringBySettingRTL(in nsrange: NSRange, rtlIndexes: IndexSet?) -> any iTermString {
        if let rtlIndexes {
            // Normally there should only be one value for my whole range.
            if let firstRange = rtlIndexes.rangeView.first {
                if firstRange.contains(0..<cellCount) {
                    // Every item in this string is RTL
                    var temp = char
                    temp.rtlStatus = .RTL
                    return iTermUniformString(char: temp, length: nsrange.length)
                } else {
                    let msca = self.screenCharArray.mutableReplacement()
                    let line = msca.mutableLine
                    for (range, isMember) in rtlIndexes.membership(in: Range(nsrange)!) {
                        for i in range {
                            line[i].rtlStatus = isMember ? .RTL : .LTR
                        }
                    }
                    return iTermLegacyStyleString(msca)
                }
            } else {
                // The index set is empty so it is uniformly left-to-right
                var temp = char
                temp.rtlStatus = .LTR
                return iTermUniformString(char: temp, length: nsrange.length)
            }
        } else if char.rtlStatus == .unknown && nsrange == fullRange {
            return self
        } else {
            var temp = char
            temp.rtlStatus = .unknown
            return iTermUniformString(char: temp, length: nsrange.length)
        }
    }

    func doubleWidthIndexes(range: NSRange, rebaseTo newBaseIndex: Int) -> IndexSet {
        if ScreenCharIsDWC_RIGHT(char) {
            return IndexSet(integersIn: Range(range)!.shifted(by: newBaseIndex - range.location))
        }
        return IndexSet()
    }
    var mayContainDoubleWidthCharacter: Bool {
        isDWCRight
    }
    func mayContainDoubleWidthCharacter(in nsrange: NSRange) -> Bool {
        isDWCRight
    }
    func hasExternalAttributes(range: NSRange) -> Bool {
        false
    }

    enum CodingKeys: Int32, TLVTag {
        case char
        case length
    }
    func efficientlyEncodedData(range: NSRange, type: UnsafeMutablePointer<Int32>) -> Data {
        type.pointee = iTermStringType.uniformString.rawValue

        var tlvEncoder = EfficientTLVEncoder<CodingKeys>()
        tlvEncoder.put(tag: .char, value: char)
        tlvEncoder.put(tag: .length, value: range.length)
        return tlvEncoder.data
    }
}

extension iTermUniformString: EfficientDecodable, EfficientEncodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self {
        var tlvDecoder: EfficientTLVDecoder<CodingKeys> = decoder.tlvDecoder()
        var dict = try tlvDecoder.decodeAll(required: Set([.char, .length]))
        return Self(char: try screen_char_t.create(efficientDecoder: &(dict[.char]!)),
                    length: try Int.create(efficientDecoder: &(dict[.length]!)))
    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        var type = Int32(0)
        let data = efficientlyEncodedData(range: fullRange, type: &type)
        encoder.putRawBytes(data)
    }
}

