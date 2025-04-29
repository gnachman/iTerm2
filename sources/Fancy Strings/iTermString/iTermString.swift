//
//  iTermString.swift
//  StyleMap
//
//  Created by George Nachman on 4/6/25.
//

import Foundation

// MARK: - Data extension for iTermString

typealias StyleMap = SegmentMap<UnifiedCharacterStyle>

// MARK: — Protocol

@objc
protocol iTermString: AnyObject {
    var description: String { get }
    var cellCount: Int { get }
    func hydrate(range: NSRange) -> ScreenCharArray
    func character(at i: Int) -> screen_char_t
    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange)
    func buildString(range: NSRange, builder: DeltaStringBuilder)
    func deltaString(range: NSRange) -> DeltaString
    func mutableClone() -> iTermMutableStringProtocol
    // Returns an immutable instance
    func clone() -> iTermString
    func externalAttributesIndex() -> iTermExternalAttributeIndexReading?
    var screenCharArray: ScreenCharArray { get }
    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool
    func usedLength(range: NSRange) -> Int32
    func isEmpty(range: NSRange) -> Bool
    func substring(range: NSRange) -> iTermString
    func externalAttribute(at index: Int) -> iTermExternalAttribute?
    @objc(isEqualToString:)
    func isEqual(to string: iTermString) -> Bool

    // Within `lhsRange` of the receiver, is it equal to `string` starting at `startIndex` of `rhs`?
    func isEqual(lhsRange: NSRange, toString rhs: iTermString, startingAtIndex startIndex: Int) -> Bool
    func doubleWidthIndexes(range: NSRange,
                            rebaseTo newBaseIndex: Int) -> IndexSet
    // If rtlIndexes is nil, set RTL status to unknown for all characters.
    // Otherwise set all to ltr (if not in rtlIndexes) or rtl otherwise.
    func stringBySettingRTL(in: NSRange, rtlIndexes: IndexSet?) -> iTermString
}

extension iTermString {
    func mutableCloneSwift() -> iTermMutableStringProtocolSwift {
        return mutableClone() as! iTermMutableStringProtocolSwift
    }
    var _screenCharArray: ScreenCharArray {
        return hydrate(range: fullRange)
    }

    func _mutableClone() -> iTermMutableRope {
        let result = iTermMutableRope()
        result.append(string: self)
        return result
    }

    func _externalAttributesIndex() -> iTermExternalAttributeIndexReading? {
        return _screenCharArray.eaIndex
    }

    func _string(withExternalAttributes eaIndex: iTermExternalAttributeIndexReading?,
                 startingFrom offset: Int) -> any iTermString {
        let sca = _screenCharArray
        return iTermLegacyStyleString(chars: sca.line,
                                      count: Int(sca.length),
                                      eaIndex: sca.eaIndex)
    }

    func _hydrate(range: NSRange) -> ScreenCharArray {
        let msca = MutableScreenCharArray.emptyLine(ofLength: Int32(range.length))
        hydrate(into: msca, destinationIndex: 0, sourceRange: range)
        return msca
    }

    func _character(at off: Int) -> screen_char_t {
        let msca = MutableScreenCharArray.emptyLine(ofLength: 1)
        hydrate(into: msca,
                destinationIndex: 0,
                sourceRange: NSRange(location: off, length: 1))
        return msca.line[0]
    }

    func _deltaString(range: NSRange) -> DeltaString {
        let builder = DeltaStringBuilder(count: CInt(cellCount))
        buildString(range: range, builder: builder)
        return builder.build()
    }

    func _hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        let actual = hydrate(range: range)
        return memcmp(actual.line,
                      chars,
                      range.length * MemoryLayout<screen_char_t>.stride) == 0
    }

    func _substring(range: NSRange) -> iTermString {
        return iTermSubString(base: self, range: Range(range)!)
    }

    var isEmpty: Bool {
        return isEmpty(range: fullRange)
    }
}

extension iTermString {
    var fullRange: NSRange { NSRange(location: 0, length: cellCount) }
}
