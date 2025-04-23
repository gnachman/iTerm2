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

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        let global = NSRange(location: range.lowerBound + sourceRange.location,
                             length: sourceRange.length)
        base.hydrate(into: msca,
                     destinationIndex: destinationIndex,
                     sourceRange: global)
    }

    func hydrate(range nsRange: NSRange) -> ScreenCharArray {
        let global = NSRange(location: range.lowerBound + nsRange.location, length: nsRange.length)
        return base.hydrate(range: global)
    }

    func buildString(range nsRange: NSRange, builder: DeltaStringBuilder) {
        let global = NSRange(location: range.lowerBound + nsRange.location,
                             length: nsRange.length)
        base.buildString(range: global, builder: builder)
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
}
