//
//  iTermNonASCIIString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermNonASCIIString: iTermBaseString, iTermString {
    private let codes: SubArray<UInt16>
    private let complex: IndexSet
    let styles: StyleMap
    private var stringCache = SubStringCache()

    init(codes: [UInt16], complex: IndexSet, styles: StyleMap) {
        self.codes = SubArray(codes)
        self.complex = complex
        self.styles = styles
    }

    init(codes: SubArray<UInt16>, complex: IndexSet, styles: StyleMap) {
        self.codes = codes
        self.complex = complex
        self.styles = styles
    }

    override var description: String {
        return "<iTermNonASCIIString: cells=\(cellCount) value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash().d)>"
    }

    var cellCount: Int { codes.count }

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
        for run in styles.runIterator(in: Range(sourceRange)!) {
            var sc = run.payload.sct
            let count = run.count
            if let ea = run.payload.externalAttributes {
                let eaIndex = msca.eaIndexCreatingIfNeeded()
                eaIndex.setAttributes(ea,
                                      at: Int32(o),
                                      count: Int32(count))
            } else if let eaIndex = msca.eaIndex {
                eaIndex.erase(in: VT100GridRange(location: Int32(o),
                                                 length: Int32(count)))
            }
            for j in 0..<count {
                sc.code = codes[i + j]
                sc.complexChar = complex.contains(i + j) ? 1 : 0
                buffer[o + j] = sc
            }
            o += count
            i += count
        }
    }

    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        builder.append(codes: codes, complex: complex, range: range)
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
        var used = Int32(range.length)
        for i in Range(range)!.reversed() {
            if codes[i] == 0 && !complex.contains(i) {
                used -= 1
            } else {
                break
            }
        }
        return used
    }

    func isEmpty(range: NSRange) -> Bool {
        return usedLength(range: range) == 0
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
        if let nas = rhs as? iTermNonASCIIString {
            return (codes[lhsRange] == nas.codes[rhsRange] &&
                    complex[lhsRange] == nas.complex[rhsRange] &&
                    styles[lhsRange] == nas.styles[rhsRange])
        }
        return substring(range: lhsNSRange).screenCharArray.isEqual(to: rhs.substring(range: NSRange(rhsRange)).screenCharArray)
    }

    func stringBySettingRTL(in nsrange: NSRange,
                            rtlIndexes: IndexSet?) -> iTermString {
        let modifiedStyles = styles.subrangeBySettingRTL(
            in: nsrange, rtlIndexes: rtlIndexes)
        guard let modifiedStyles else {
            return self
        }
        let range = Range(nsrange)!
        return iTermNonASCIIString(codes: codes[range],
                                   complex: complex[range],
                                   styles: modifiedStyles)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        var indexSet = IndexSet()
        let offset = newBaseIndex - nsrange.location
        for i in Range(nsrange)! {
            if codes[i] == DWC_RIGHT && !complex.contains(i) {
                indexSet.insert(i + offset)
            }
        }
        return indexSet
    }

}
