//
//  iTermASCIIString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

class iTermASCIIString: iTermBaseString, iTermString {
    private let data: SubData
    private let styles: StyleMap
    private var stringCache = SubStringCache()

    @objc
    init(data: Data, style: screen_char_t, ea: iTermExternalAttribute?) {
        self.data = SubData(data: data, range: 0..<data.count)
        var styleMap = StyleMap()
        let ucs = UnifiedCharacterStyle(sct: style,
                                        underlineColor: (ea?.hasUnderlineColor ?? false) ? ea?.underlineColor : nil,
                                        blockIDs: ea?.blockIDList,
                                        controlCode: ea?.controlCodeNumber?.int32Value,
                                        url: ea?.url)
        styleMap.append(count: data.count, payload: ucs)
        self.styles = styleMap
    }

    init(data: SubData, styles: StyleMap) {
        self.data = data
        self.styles = styles
    }

    override var description: String {
        return "<iTermASCIIString: cells=\(cellCount) value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash().d)>"
    }

    var cellCount: Int { data.range.count }

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
        let iter = styles.runIterator(in: Range(sourceRange)!)
        var tuple = iter.next()
        while let (payload, count) = tuple {
            if let ea = payload.externalAttributes {
                let eaIndex = msca.eaIndexCreatingIfNeeded()
                eaIndex.setAttributes(ea, at: Int32(o), count: Int32(count))
            }
            for _ in 0..<count {
                var sc = payload.sct
                sc.complexChar = 0
                sc.code = UInt16(data[i])
                buffer[o] = sc
                o += 1
                i += 1
            }
            tuple = iter.next()
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
        let u = styles.get(index: index)
        return u.externalAttributes
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
            return data[lhsRange] == ascii.data[rhsRange] && styles[lhsRange] == ascii.styles[rhsRange]
        }
        return substring(range: lhsNSRange).screenCharArray.isEqual(to: rhs.substring(range: NSRange(rhsRange)).screenCharArray)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        return IndexSet()
    }

    func stringBySettingRTL(in nsrange: NSRange,
                            rtlIndexes: IndexSet?) -> iTermString {
        let modifiedStyles = styles.subrangeBySettingRTL(
            in: nsrange, rtlIndexes: rtlIndexes)
        guard let modifiedStyles else {
            return self
        }
        return iTermASCIIString(data: data[Range(nsrange)!],
                                styles: modifiedStyles)
    }
    var mayContainDoubleWidthCharacter: Bool {
        false
    }
    func mayContainDoubleWidthCharacter(in nsrange: NSRange) -> Bool {
        false
    }
    func hasExternalAttributes(range: NSRange) -> Bool {
        // TODO: I need to ge rid of stylemap and store a single iTermExternalAttributes here and then this can be more accurate
        true
    }
}

extension StyleMap {
    func subrangeBySettingRTL(in nsrange: NSRange,
                              rtlIndexes: IndexSet?) -> StyleMap? {
        let range = Range(nsrange)!
        let substyles = self[range]
        if rtlIndexes == nil &&
            substyles.allSatisfy({ $0.payload.sct.rtlStatus == .unknown }) {
            return nil
        }

        return substyles.flatMap { payload, count, i in
            if let rtlIndexes {
                var modified = Array<(UnifiedCharacterStyle, Int)>()
                var temp = payload
                for (range, isMember) in rtlIndexes.membership(in: Range(nsrange)!) {
                    temp.sct.rtlStatus = isMember ? .RTL : .LTR
                    let tuple = (temp, range.count)
                    modified.append(tuple)
                }
                return modified
            } else {
                var temp = payload
                temp.sct.rtlStatus = .unknown
                return [(temp, count)]
            }
        }
    }
}
