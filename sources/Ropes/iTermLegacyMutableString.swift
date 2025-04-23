//
//  iTermLegacyMutableString.swift
//  iTerm2
//
//  Created by George Nachman on 4/21/25.
//

@objc
class iTermLegacyMutableString: NSObject {
    let sca: MutableScreenCharArray

    @objc
    init(width: Int) {
        sca = MutableScreenCharArray(data: Data(repeating: 0, count: MemoryLayout<screen_char_t>.stride * (width + 1)),
                                     includingContinuation: true,
                                     metadata: iTermImmutableMetadataDefault(),
                                     continuation: screen_char_t())
    }

    @objc
    convenience init(width: Int, character: screen_char_t) {
        self.init(width: width)
        sca.setCharacter(character, in: fullRange)
    }

    override var description: String {
        return "<iTermLegacyMutableString: \(it_addressString) sca=\(sca.description)>"
    }

    @objc(eaIndexCreatingIfNeeded:)
    func eaIndex(createIfNeeded: Bool) -> iTermExternalAttributeIndex? {
        if let eaIndex = sca.eaIndex {
            return eaIndex
        }
        if !createIfNeeded {
            return nil
        }
        let result = iTermExternalAttributeIndex()
        sca.setExternalAttributesIndex(result)
        return result
    }

    @objc(setMetadata:)
    func set(metadata: iTermMetadata) {
        sca.setMetadata(metadata)
    }

    @objc
    var mutableScreenCharArray: MutableScreenCharArray { sca }

    @objc(setDWCSkipAt:)
    func setDWCSkip(at i: Int) {
        ScreenCharSetDWC_SKIP(sca.mutableLine.advanced(by: i))
    }

    @objc(eraseCodeAt:)
    func eraseCode(at i: Int) {
        sca.mutableLine[i].code = 0
        sca.mutableLine[i].complexChar = 0
    }
}

@objc
extension iTermLegacyMutableString: iTermString {
    func string(withExternalAttributes eaIndex: iTermExternalAttributeIndexReading?,
                startingFrom offset: Int) -> any iTermString {
        return _string(withExternalAttributes: eaIndex, startingFrom: offset)
    }

    var cellCount: Int {
        Int(sca.length)
    }

    func hydrate(range: NSRange) -> ScreenCharArray {
        return sca.subArray(with: range)
    }

    func character(at i: Int) -> screen_char_t {
        sca.line[i]
    }

    func hydrate(into msca: MutableScreenCharArray,
                 destinationIndex: Int,
                 sourceRange: NSRange) {
        msca.copy(sourceRange, from: sca, destinationIndex: Int32(destinationIndex))
    }
    
    func hydrate(into buffer: UnsafeMutablePointer<screen_char_t>,
                 eaIndex: iTermExternalAttributeIndex?,
                 offset: Int32,
                 range: NSRange) {
        let start = range.location
        let length = range.length
        let src = sca.line.advanced(by: start)
        buffer.update(from: src, count: length)

        if let eaIndex {
            iTermImmutableMetadataGetExternalAttributesIndex(sca.metadata)?.copy(into: eaIndex)
        }
    }
    func buildString(range: NSRange, builder: DeltaStringBuilder) {
        builder.append(chars: sca.line, count: sca.length)
    }

    func deltaString(range: NSRange) -> DeltaString {
        return _deltaString(range: range)
    }

    func mutableClone() -> any iTermMutableStringProtocol & iTermString {
        let result = iTermLegacyMutableString(width: 0)
        result.append(string: self)
        return result
    }

    func externalAttributesIndex() -> iTermExternalAttributeIndexReading? {
        sca.eaIndex
    }

    var screenCharArray: ScreenCharArray {
        sca
    }

    func hasEqual(range: NSRange, to chars: UnsafePointer<screen_char_t>) -> Bool {
        return _hasEqual(range: range, to: chars)
    }
}

@objc
extension iTermLegacyMutableString: iTermMutableStringProtocol {
    @objc(deleteRange:)
    func objcDelete(range: NSRange) {
        sca.delete(range)
    }

    @objc func objReplace(range: NSRange, with replacement: iTermString) {
        replace(range: Range(range)!, with: replacement)
    }

    @objc func append(string: iTermString) {
        sca.append(string.screenCharArray)
    }

    @objc func deleteFromStart(_ count: Int) {
        sca.delete(NSRange(location: 0, length: count))
    }

    @objc func deleteFromEnd(_ count: Int) {
        sca.delete(NSRange(location: cellCount - count, length: count))
    }

    @objc(setExternalAttributes:startingFromOffset:)
    func set(externalAttributes source: iTermExternalAttributeIndexReading?,
             offset: Int) {
        var dest = iTermImmutableMetadataGetExternalAttributesIndex(sca.metadata) as! iTermExternalAttributeIndex?
        if dest == nil && source == nil {
            return
        }
        if dest == nil {
            dest = iTermExternalAttributeIndex()
            sca.setExternalAttributesIndex(dest)
        }
        dest?.copy(from: source,
                   startOffset: Int32(offset))
    }

    func erase(defaultChar: screen_char_t) {
        sca.setCharacter(defaultChar, in: fullRange)
    }
}

extension iTermLegacyMutableString: iTermMutableStringProtocolSwift {
    func delete(range: Range<Int>) {
        sca.delete(NSRange(range))
    }

    func replace(range: Range<Int>, with replacement: iTermString) {
        sca.delete(NSRange(range))
        sca.insert(replacement.screenCharArray, at: Int32(range.lowerBound))
    }

    func insert(_ string: iTermString, at index: Int) {
        sca.insert(sca, at: Int32(index))
    }
}
