//
//  iTermSubString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

/// A lightweight “view” into an existing iTermString, masking off
/// a prefix or suffix by only exposing cells in `range`.
@objc
class iTermSubString: NSObject, iTermString {
    private let base: iTermString
    private let range: Range<Int>
    private lazy var stringCache = SubStringCache()

    init(base: iTermString, range: Range<Int>) {
        if let sub = base as? iTermSubString {
            // unwrap nested substring
            self.base = sub.base
            let offset = sub.range.lowerBound
            let lower = offset + range.lowerBound
            let upper = offset + range.upperBound
            self.range = lower..<upper
        } else {
            self.base = base
            self.range = range
        }
    }

    override var description: String {
        return "<iTermSubString: cells=\(cellCount) value=\(deltaString(range: fullRange).string)>"
    }

    func deltaString(range: NSRange) -> DeltaString {
        return stringCache.string(for: range) {
            _deltaString(range: range)
        }
    }

    var cellCount: Int { range.count }

    func character(at i: Int) -> screen_char_t {
        return base.character(at: range.lowerBound + i)
    }

    private func global(range nsRange: NSRange) -> NSRange {
        return NSRange(location: range.lowerBound + nsRange.location,
                       length: nsRange.length)
    }
    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        base.hydrate(into: msca,
                     destinationIndex: destinationIndex,
                     sourceRange: global(range: sourceRange))
    }

    func hydrate(range nsRange: NSRange) -> ScreenCharArray {
        return base.hydrate(range: global(range: nsRange))
    }

    func buildString(range nsRange: NSRange, builder: DeltaStringBuilder) {
        base.buildString(range: global(range: nsRange), builder: builder)
    }

    func mutableClone() -> any iTermMutableStringProtocol & iTermString {
        return _mutableClone()
    }

    func string(withExternalAttributes eaIndex: (any iTermExternalAttributeIndexReading)?, startingFrom offset: Int) -> any iTermString {
        return _string(withExternalAttributes: eaIndex, startingFrom: offset)
    }

    func externalAttributesIndex() -> (any iTermExternalAttributeIndexReading)? {
        return _externalAttributesIndex()
    }

    var screenCharArray: ScreenCharArray { _screenCharArray }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        return _hasEqual(range: range, to: chars)
    }

    func usedLength(range: NSRange) -> Int32 {
        return base.usedLength(range: global(range: range))
    }

    func isEmpty(range: NSRange) -> Bool {
        return base.isEmpty(range: global(range: range))
    }
}
