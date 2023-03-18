//
//  ComplexCharRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/22.
//

import Foundation

private let UnicodeReplacementString = "\u{fffd}"

@objc(iTermComplexCharRegistry)
class ComplexCharRegistry: NSObject {
    @objc(sharedInstance) static let instance = ComplexCharRegistry()
    private let impl = ComplexCharRegistryImpl()
    private let mutex = Mutex()

    @objc var complexCharMap: [NSNumber: NSString] {
        return mutex.sync { impl.complexCharMap }
    }
    @objc var inverseComplexCharMap: [NSString: NSNumber] {
        return mutex.sync { impl.inverseComplexCharMap }
    }
    @objc var spacingCombiningMarkCodeNumbers: Set<NSNumber> {
        return mutex.sync { impl.spacingCombiningMarkCodeNumbers }
    }

    @objc var nextCode: Int {
        return mutex.sync { impl.nextCode }
    }

    @objc var peekNextCode: Int {
        return mutex.sync { impl.peekNextCode }
    }

    @objc var hasWrapped: Bool {
        return mutex.sync { impl.hasWrapped }
    }

    @objc(loadCharMap:spacingCombiningMarks:inverseMap:nextKey:hasWrapped:)
    func load(charMap: [NSNumber: NSString]?,
              spacingCombiningMarks: [NSNumber]?,
              inverseMap: [NSString: NSNumber]?,
              nextKey: Int,
              hasWrapped: Bool) {
        mutex.sync {
            impl.load(charMap: charMap,
                      spacingCombiningMarks: spacingCombiningMarks,
                      inverseMap: inverseMap,
                      nextKey: nextKey,
                      hasWrapped: hasWrapped)
        }
    }

    @objc func string(for code: Int) -> NSString? {
        return mutex.sync { impl.string(for: code) }
    }

    @objc func code(for string: NSString) -> NSNumber? {
        return mutex.sync { impl.code(for: string) }
    }

    @objc(appendCodePoint:to:)
    func append(codePoint: unichar, to code: Int) -> Int {
        return mutex.sync { impl.append(codePoint: codePoint, to: code) }
    }

    @objc
    func convertToGraphics(chars: UnsafeMutablePointer<screen_char_t>, count: Int) {
        mutex.sync { impl.convertToGraphics(chars: chars, count: count) }
    }

    @objc
    func codeIsSpacingCombiningMark(_ code: unichar) -> Bool {
        return mutex.sync { impl.codeIsSpacingCombiningMark(code) }
    }

    @objc
    func lazilyCreatedCode(for string: NSString,
                           isSpacingCombiningMark: iTermTriState) -> Int {
        return mutex.sync { impl.lazilyCreatedCode(for: string,
                                                      isSpacingCombiningMark: isSpacingCombiningMark) }
    }

    @objc
    func charToString(_ char: screen_char_t) -> NSString? {
        if char.image != 0 {
            return ""
        }
        return string(for: char.code, isComplex: char.complexChar != 0)
    }

    @objc(stringForCode:isComplex:)
    func string(for code: unichar, isComplex: Bool) -> NSString? {
        if isComplex {
            return mutex.sync { impl.string(for: Int(code)) }
        }
        let temp = code;
        return withUnsafePointer(to: temp) { codePointer in
            return NSString(characters: codePointer, length: 1)
        }
    }

    @objc(expandScreenChar:to:)
    func expand(screenChar: screen_char_t, to destination: UnsafeMutablePointer<unichar>) -> Int32 {
        if screenChar.code != UNICODE_REPLACEMENT_CHAR && screenChar.complexChar != 0 {
            return expand(string: string(for: Int(screenChar.code)), to: destination)
        }
        destination[0] = screenChar.code
        return 1
    }


    @objc
    func setComplexChar(in screenChar: UnsafeMutablePointer<screen_char_t>,
                        string: NSString,
                        normalization: iTermUnicodeNormalization,
                        isSpacingCombiningMark: Bool) {
        let normalizedString = string.normalized(normalization)
        if normalizedString.length == 1 && !isSpacingCombiningMark {
            screenChar[0].code = normalizedString.character(at: 0)
            return
        }
        let code = lazilyCreatedCode(for: normalizedString,
                                        isSpacingCombiningMark: iTermTriStateFromBool(isSpacingCombiningMark))
        screenChar[0].code = unichar(code)
        screenChar[0].complexChar = 1
    }

    // MARK:- Private

    private func expand(string: NSString?, to destination: UnsafeMutablePointer<unichar>) -> Int32 {
        guard let string = string else {
            return 0
        }
        string.getCharacters(destination)
        return Int32(string.length)
    }
}


private class ComplexCharRegistryImpl: NSObject {
    private(set) var complexCharMap = [NSNumber: NSString]()
    private(set) var inverseComplexCharMap = [NSString: NSNumber]()
    private(set) var spacingCombiningMarkCodeNumbers = Set<NSNumber>()
    private(set) var hasWrapped = false

    // Limiting the maxKey to 0xf000 allows users to downgrade to older versions (3.5.0beta5 and
    // earlier) that placed DWC_SKIP and friends in the private use area and didn't check for
    // complexChar when testing for those special characters.
    private let maxKey = 0xf000
    private var _nextCode = 1

    var nextCode: Int {
        while (true) {
            let candidate = _nextCode
            if _nextCode == maxKey {
                _nextCode = 0
                hasWrapped = true
            }
            _nextCode += 1
            if (!reserved(candidate)) {
                return candidate
            }
        }
    }

    var peekNextCode: Int {
        return _nextCode
    }

    override init() {
        ScreenCharGeneration.counter.advance()
        super.init()
    }

    func load(charMap: [NSNumber: NSString]?,
              spacingCombiningMarks: [NSNumber]?,
              inverseMap: [NSString: NSNumber]?,
              nextKey: Int,
              hasWrapped: Bool) {
        if let charMap = charMap {
            self.complexCharMap = charMap
        }
        if let spacingCombiningMarks = spacingCombiningMarks {
            for value in spacingCombiningMarks {
                self.spacingCombiningMarkCodeNumbers.insert(value)
            }
        }
        if let inverseMap = inverseMap {
            for (key, value) in inverseMap {
                if inverseComplexCharMap[key] == nil {
                    inverseComplexCharMap[key] = value
                }
            }
        }
        self._nextCode = nextKey
        self.hasWrapped = hasWrapped
    }

    func string(for code: Int) -> NSString? {
        if code == UNICODE_REPLACEMENT_CHAR {
            return UnicodeReplacementString as NSString
        }
        return complexCharMap[NSNumber(value: code)]
    }

    func code(for string: NSString) -> NSNumber? {
        return inverseComplexCharMap[string]
    }

    func append(codePoint: unichar, to code: Int) -> Int {
        if code == UNICODE_REPLACEMENT_CHAR {
            return code
        }
        guard let string = complexCharMap[NSNumber(value: code)] else {
            fatalError("No string for code \(code)")
        }
        if string.length >= kMaxParts {
            DLog("<<\(string)>> with code \(code) reached max length \(kMaxParts)")
            return code
        }
        return lazilyCreatedCode(for: string.it_string(byAppendingCharacter: codePoint)! as NSString,
                                    isSpacingCombiningMark: .other)
    }

    func convertToGraphics(chars: UnsafeMutablePointer<screen_char_t>, count: Int) {
        let table = GetASCIIToUnicodeBoxTable()
        for i in 0..<count {
            precondition(chars[i].complexChar == 0)
            let code = chars[i].code
            let unicode = table[Int(code)]
            chars[i].code = unicode
        }
    }

    func codeIsSpacingCombiningMark(_ code: unichar) -> Bool {
        return spacingCombiningMarkCodeNumbers.contains(NSNumber(value: code))
    }

    func lazilyCreatedCode(for string: NSString,
                           isSpacingCombiningMark: iTermTriState) -> Int {
        if let number = code(for: string) {
            return number.intValue
        }
        ScreenCharGeneration.counter.advance()
        let newCode = nextCode;
        let number = NSNumber(value: newCode)
        if hasWrapped {
            if let oldString = complexCharMap[number] {
                inverseComplexCharMap.removeValue(forKey: oldString)
                spacingCombiningMarkCodeNumbers.remove(number)
            }
        }
        switch isSpacingCombiningMark {
        case .true:
            spacingCombiningMarkCodeNumbers.insert(number)
        case .false:
            break
        case .other:
            if string.rangeOfCharacter(from: NSCharacterSet.spacingCombiningMarks(forUnicodeVersion: 12) as CharacterSet).location != NSNotFound {
                spacingCombiningMarkCodeNumbers.insert(number)
            }
        @unknown default:
            fatalError()
        }
        complexCharMap[number] = string
        inverseComplexCharMap[string] = number
        if iTermAdvancedSettingsModel.restoreWindowContents() {
            DispatchQueue.main.async {
                NSApp.invalidateRestorableState()
            }
        }
        return newCode
    }
    // MARK:- Private

    private func reserved(_ code: Int) -> Bool {
        return code >= iTermBoxDrawingCodeMin && code <= iTermBoxDrawingCodeMax;
    }
}

extension NSString {
    @objc
    func normalized(_ normalization: iTermUnicodeNormalization) -> NSString {
        switch normalization {
        case .none:
            return self
        case .NFC:
            return self.precomposedStringWithCanonicalMapping as NSString
        case .NFD:
            return self.decomposedStringWithCanonicalMapping as NSString
        case .hfsPlus:
            return self.precomposedStringWithHFSPlusMapping() as NSString
        @unknown default:
            return self
        }
    }
}

extension screen_char_t {
    var baseCharacter: UTF32Char {
        if image != 0 {
            return 0
        }
        if complexChar == 0 {
            return UTF32Char(code)
        }
        guard let string = ComplexCharRegistry.instance.charToString(self) else {
            return 0
        }
        return string.longCharacter(at: 0)
    }
}

