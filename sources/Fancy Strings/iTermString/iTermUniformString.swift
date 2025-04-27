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
}
