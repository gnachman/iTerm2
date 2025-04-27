//
//  iTermLegacyStyleString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermLegacyStyleString: NSObject, iTermString {
    private let line: [screen_char_t]
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

    var cellCount: Int { line.count }

    override var description: String {
        return "<iTermLegacyStyleString: cells=\(cellCount) value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash().d)>"
    }

    func usedLength(range: NSRange) -> Int32 {
        line.withUnsafeBufferPointer { ubp in
            return iTermUsedLength(chars: ubp.baseAddress!.advanced(by: range.location),
                                   count: Int32(range.length))
        }
    }

    func isEmpty(range: NSRange) -> Bool {
        return line.allSatisfy {
            !ScreenCharIsNull($0)
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
        line.withUnsafeBufferPointer { ptr in
            let sourcePointer = ptr.baseAddress!.advanced(by: sourceRange.location)
            msca.mutableLine.advanced(by: destinationIndex).update(from: sourcePointer, count: sourceRange.length)
        }
        if let eaIndex {
            msca.eaIndexCreatingIfNeeded().copy(from: eaIndex,
                                                source: Int32(sourceRange.location),
                                                destination: Int32(destinationIndex),
                                                count: Int32(sourceRange.length))
        } else {
            msca.eaIndex?.erase(in: VT100GridRange(location: Int32(destinationIndex),
                                                   length: Int32(sourceRange.length)))
        }
    }

    func hydrate(into buffer: UnsafeMutablePointer<screen_char_t>,
                 eaIndex: iTermExternalAttributeIndex?,
                 offset: Int32,
                 range: NSRange) {
        let start = range.location
        let length = range.length

        // TODO: Add extended attribute support
        line.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!
                .advanced(by: start)
                .withMemoryRebound(to: screen_char_t.self, capacity: length) { src in
                    buffer.update(from: src, count: length)
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
    func string(withExternalAttributes eaIndex: iTermExternalAttributeIndexReading?,
                startingFrom offset: Int) -> any iTermString {
        return _string(withExternalAttributes: eaIndex, startingFrom: offset)
    }

    @objc
    var screenCharArray: ScreenCharArray { _screenCharArray }

    func mutableClone() -> any iTermMutableStringProtocol & iTermString {
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
}
