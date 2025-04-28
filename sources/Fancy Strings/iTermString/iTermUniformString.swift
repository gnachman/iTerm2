//
//  iTermUniformString.swift
//  iTerm2
//
//  Created by George Nachman on 4/22/25.
//

@objc
class iTermUniformString: NSObject, iTermString {
    private let char: screen_char_t
    private var stringCache = SubStringCache()
    private let length: Int

    @objc(initWithCharacter:count:)
    init(char: screen_char_t, length: Int) {
        self.char = char
        self.length = length
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

    func string(withExternalAttributes eaIndex: (any iTermExternalAttributeIndexReading)?, startingFrom offset: Int) -> any iTermString {
        return _string(withExternalAttributes: eaIndex, startingFrom: offset)
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
        return ScreenCharIsNull(char)
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
                    // Sadly this is a mix :(
                    // I honestly don't know how this could happen in real life.
                    let complexRange = char.complexChar != 0 ? 0..<length : 0..<0
                    var styleMap = StyleMap()
                    for (range, isMember) in rtlIndexes.membership(in: Range(nsrange)!) {
                        var c = char
                        c.rtlStatus = isMember ? .RTL : .LTR
                        let ucs = UnifiedCharacterStyle(sct: c)
                        styleMap.append(count: range.count, payload: ucs)
                    }
                    return iTermNonASCIIString(
                        codes: Array(repeating: char.code, count: length),
                        complex: IndexSet(integersIn: complexRange),
                        styles: styleMap)
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
            return IndexSet(integersIn: Range(range)!)
        }
        return IndexSet()
    }
}
