//
//  iTermSubString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

/// A lightweight “view” into an existing iTermString, masking off
/// a prefix or suffix by only exposing cells in `range`.
@objc
class iTermSubString: iTermBaseString, iTermString {
    private let base: iTermString
    private let range: Range<Int>
    private lazy var stringCache = SubStringCache()

    @objc(initWithBaseString:range:)
    convenience init(base: iTermString, range: NSRange) {
        self.init(base: base, range: Range(range)!)
    }

    init(base: iTermString, range: Range<Int>) {
        it_assert(base.fullRange.contains(range))
        if let sub = base as? iTermSubString {
            // unwrap nested substring
            self.base = sub.base
            let offset = sub.range.lowerBound
            let lower = offset + range.lowerBound
            let upper = offset + range.upperBound
            self.range = lower..<upper
        } else {
            // Make totally sure `base` is immutable!
            self.base = base.clone()
            self.range = range
        }
    }

    override var description: String {
        return "<iTermSubString: base=\(type(of: base)) @ \(((base as? NSObject)?.it_addressString).d) cells=\(cellCount) value=\(deltaString(range: fullRange).string.trimmingTrailingNulls.escapingControlCharactersAndBackslash().d)>"
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

    func mutableClone() -> any iTermMutableStringProtocol {
        return _mutableClone()
    }

    func clone() -> any iTermString {
        return self
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

    func substring(range: NSRange) -> any iTermString {
        return iTermSubString(base: base, range: Range(global(range: range))!)
    }

    func externalAttribute(at index: Int) -> iTermExternalAttribute? {
        return base.externalAttribute(at: global(range: NSRange(location: index, length: 1)).lowerBound)
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
        return base.isEqual(lhsRange: NSRange(location: lhsNSRange.location + self.range.lowerBound,
                                              length: lhsNSRange.length),
                            toString: rhs,
                            startingAtIndex: startIndex)
    }

    func stringBySettingRTL(in nsrange: NSRange, rtlIndexes: IndexSet?) -> any iTermString {
        let subrange = NSRange(location: self.range.lowerBound + nsrange.location,
                               length: nsrange.length)
        var shifted = rtlIndexes
        shifted?.shift(startingAt: 0, by: range.lowerBound)
        return base.stringBySettingRTL(in: subrange,
                                       rtlIndexes: shifted)
    }

    func doubleWidthIndexes(range nsrange: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet {
        return base.doubleWidthIndexes(range: NSRange(location: range.lowerBound + nsrange.location, length: nsrange.length), rebaseTo: newBaseIndex)
    }
}
