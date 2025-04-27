//
//  iTermASCIIString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

class iTermASCIIString: NSObject, iTermString {
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

    func mutableClone() -> any iTermMutableStringProtocol & iTermString {
        return _mutableClone()
    }

    func clone() -> any iTermString {
        return self
    }

    func string(withExternalAttributes eaIndex: (any iTermExternalAttributeIndexReading)?, startingFrom offset: Int) -> any iTermString {
        return _string(withExternalAttributes: eaIndex, startingFrom: offset)
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
}
