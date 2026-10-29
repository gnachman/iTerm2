//
//  ComplexCharRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/22.
//

import Foundation

private let UnicodeReplacementString = "\u{fffd}"

private extension NSString {
    var containsSpacingCombiningMark: Bool {
        return iTermStringContainsSpacingCombiningMark(self as CFString)
    }
}

@objc(iTermComplexCharRegistry)
class ComplexCharRegistry: NSObject {
    @objc(sharedInstance) static let instance = ComplexCharRegistry()
    private let impl: ComplexCharRegistryImpl
    private let mutex = Mutex()
    // Returns a string's hash. Injectable so tests can make hashes collide.
    private let stringHash: (NSString) -> Int

    // Limiting the maxKey to 0xf000 allows users to downgrade to older versions (3.5.0beta5 and
    // earlier) that placed DWC_SKIP and friends in the private use area and didn't check for
    // complexChar when testing for those special characters. Tests use a small one to wrap.
    init(hash: @escaping (NSString) -> Int = { $0.hash }, maxKey: unichar = unichar(0xf000)) {
        stringHash = hash
        impl = ComplexCharRegistryImpl(maxKey: maxKey, hash: hash)
        super.init()
    }

    override convenience init() {
        self.init(hash: { $0.hash })
    }

    // These are for saving the registry with the window state. Each copies the registry's storage
    // while holding the lock, which is cheap (Swift collections are copied on write), and builds
    // the NSNumber-keyed form after releasing it, so lookups don't wait while it's built.
    @objc var complexCharMap: [NSNumber: NSString] {
        let stringsByCode = mutex.sync { impl.stringsByCode }
        return Dictionary(uniqueKeysWithValues: stringsByCode.map { (NSNumber(value: $0.key), $0.value) })
    }
    @objc var inverseComplexCharMap: [NSString: NSNumber] {
        let entriesByHash = mutex.sync { impl.entriesByHash }
        var result = [NSString: NSNumber]()
        for bucket in entriesByHash.values {
            for entry in bucket {
                result[entry.string] = NSNumber(value: entry.code)
            }
        }
        return result
    }
    @objc var spacingCombiningMarkCodeNumbers: Set<NSNumber> {
        let codes = mutex.sync { impl.spacingCombiningMarkCodes }
        return Set(codes.map { NSNumber(value: $0) })
    }

    @objc var nextCode: unichar {
        return mutex.sync { impl.nextCode }
    }

    @objc var peekNextCode: unichar {
        return mutex.sync { impl.peekNextCode }
    }

    @objc var hasWrapped: Bool {
        return mutex.sync { impl.hasWrapped }
    }

    @objc(loadCharMap:spacingCombiningMarks:inverseMap:nextKey:hasWrapped:)
    func load(charMap: [NSNumber: NSString]?,
              spacingCombiningMarks: [NSNumber]?,
              inverseMap: [NSString: NSNumber]?,
              nextKey: unichar,
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
        return lookUpCode(for: string, hash: stringHash(string)).map { NSNumber(value: $0) }
    }

    // Any thread. Finds the code for a string that already has one, holding the lock only to fetch
    // the entries with the string's hash: the string is hashed before taking it and compared after
    // releasing it. Sessions printing complex characters at once contended for this lock, and
    // hashing and comparing NSStrings took most of the time it was held. A code found this way can
    // be given to another string (after the codes wrap) as soon as the lock is released, just as one
    // looked up while holding it could be.
    private func lookUpCode(for string: NSString, hash: Int) -> unichar? {
        let candidates = mutex.sync { impl.entries(hash: hash) }
        return candidates.first { $0.string.isEqual(string) }?.code
    }

    @objc(appendCodePoint:to:)
    func append(codePoint: unichar, to code: unichar) -> unichar {
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
                           isSpacingCombiningMark: iTermTriState) -> unichar {
        let hash = stringHash(string)
        if let code = lookUpCode(for: string, hash: hash) {
            return code
        }
        // Not registered yet (or registered since the lookup, which this checks again).
        return mutex.sync { impl.lazilyCreatedCode(for: string,
                                                      hash: hash,
                                                      isSpacingCombiningMark: isSpacingCombiningMark) }
    }

    @objc
    func charToKittyPlaceholder(_ char: screen_char_t) -> NSString? {
        if char.image == 0 || char.virtualPlaceholder == 0 {
            return ""
        }
        return string(for: char.code, isComplex: char.complexChar != 0)
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

    @objc(baseCharacterForComplexCode:)
    func baseCharacter(complexCode code: unichar) -> UTF32Char {
        mutex.sync {
            impl.string(for: Int(code))?.firstCharacter() ?? 0
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
        screenChar[0].code = code
        screenChar[0].complexChar = 1
    }

    // MARK:- Private

    private func expand(string: NSString?, to destination: UnsafeMutablePointer<unichar>) -> Int32 {
        guard let string = string else {
            return 0
        }
        // Every ExpandScreenChar caller sizes its destination for at most kMaxParts unichars
        // per cell; some pass a fixed stack buffer of exactly kMaxParts (e.g.
        // iTermTextExtractor) and ScreenCharArrayToString allocates lineLength * kMaxParts.
        // A stored complex-char string longer than kMaxParts should be impossible, but if one
        // ever slips through, getCharacters would write past the destination and corrupt
        // memory (heap overflow in ScreenCharArrayToString, stack smash in the extractor). So
        // clamp to the contract, trimming a trailing high surrogate so we never emit half a
        // surrogate pair.
        let maxParts = Int(kMaxParts)
        var count = string.length
        if count > maxParts {
            DLog("Complex char string <<\(string)>> exceeds kMaxParts=\(maxParts); clamping on expand")
            count = maxParts
            if UTF16.isLeadSurrogate(string.character(at: count - 1)) {
                count -= 1
            }
        }
        string.getCharacters(destination, range: NSRange(location: 0, length: count))
        return Int32(count)
    }
}


private class ComplexCharRegistryImpl: NSObject {
    struct Entry {
        let string: NSString
        let code: unichar
    }

    // Codes are stored as unichar rather than NSNumber, so lookups don't box and unbox them. The
    // maps keyed by NSNumber that saving uses are built when asked for, outside the lock.
    private(set) var stringsByCode = [unichar: NSString]()
    // Strings with codes, by their hash. A bucket almost always has one entry.
    private(set) var entriesByHash = [Int: [Entry]]()
    private(set) var spacingCombiningMarkCodes = Set<unichar>()
    private(set) var hasWrapped = false

    private let maxKey: unichar
    private let hashString: (NSString) -> Int
    private var _nextCode = unichar(1)

    var nextCode: unichar {
        while (true) {
            if _nextCode >= maxKey {
                _nextCode = 0
                hasWrapped = true
            }
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

    var peekNextCode: unichar {
        return _nextCode
    }

    init(maxKey: unichar, hash: @escaping (NSString) -> Int) {
        self.maxKey = maxKey
        hashString = hash
        ScreenCharGeneration.counter.advance()
        super.init()
    }

    func load(charMap: [NSNumber: NSString]?,
              spacingCombiningMarks: [NSNumber]?,
              inverseMap: [NSString: NSNumber]?,
              nextKey: unichar,
              hasWrapped: Bool) {
        if let charMap = charMap {
            stringsByCode = [:]
            for (number, string) in charMap {
                if let code = UInt16(exactly: number.intValue) {
                    stringsByCode[code] = string
                }
            }
        }
        if let spacingCombiningMarks = spacingCombiningMarks {
            for value in spacingCombiningMarks {
                if let code = UInt16(exactly: value.intValue) {
                    spacingCombiningMarkCodes.insert(code)
                }
            }
        }
        if let inverseMap = inverseMap {
            for (string, number) in inverseMap {
                guard let code = UInt16(exactly: number.intValue) else {
                    continue
                }
                let h = hashString(string)
                if !(entriesByHash[h] ?? []).contains(where: { $0.string.isEqual(string) }) {
                    entriesByHash[h, default: []].append(Entry(string: string, code: code))
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
        guard let key = UInt16(exactly: code) else {
            return nil
        }
        return stringsByCode[key]
    }

    func entries(hash: Int) -> [Entry] {
        return entriesByHash[hash] ?? []
    }

    func append(codePoint: unichar, to code: unichar) -> unichar {
        if code == UNICODE_REPLACEMENT_CHAR {
            return code
        }
        guard let string = stringsByCode[code] else {
            iTermFatalError("No string for code \(code)")
        }
        if string.length >= kMaxParts {
            DLog("<<\(string)>> with code \(code) reached max length \(kMaxParts)")
            return code
        }
        let appended = string.it_string(byAppendingCharacter: codePoint) as NSString
        return lazilyCreatedCode(for: appended, hash: hashString(appended), isSpacingCombiningMark: .other)
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
        return spacingCombiningMarkCodes.contains(code)
    }

    // `stringHash` is hashString(string), computed by the caller.
    func lazilyCreatedCode(for string: NSString,
                           hash stringHash: Int,
                           isSpacingCombiningMark: iTermTriState) -> unichar {
        if let entry = entriesByHash[stringHash]?.first(where: { $0.string.isEqual(string) }) {
            return entry.code
        }
        ScreenCharGeneration.counter.advance()
        let newCode = nextCode
        if hasWrapped, let oldString = stringsByCode[newCode] {
            // The oldest code is reused: the string that had it loses it.
            let oldHash = hashString(oldString)
            entriesByHash[oldHash]?.removeAll { $0.code == newCode }
            if entriesByHash[oldHash]?.isEmpty == true {
                entriesByHash.removeValue(forKey: oldHash)
            }
            spacingCombiningMarkCodes.remove(newCode)
        }
        switch isSpacingCombiningMark {
        case .true:
            spacingCombiningMarkCodes.insert(newCode)
        case .false:
            break
        case .other:
            if string.containsSpacingCombiningMark {
                spacingCombiningMarkCodes.insert(newCode)
            }
        @unknown default:
            it_fatalError()
        }
        // Copied, so a mutable string the caller changes later can't change the registry.
        let stored = string.copy() as! NSString
        stringsByCode[newCode] = stored
        entriesByHash[stringHash, default: []].append(Entry(string: stored, code: newCode))
        if iTermAdvancedSettingsModel.restoreWindowContents() {
            DispatchQueue.main.async {
                NSApp.invalidateRestorableState()
            }
        }
        return newCode
    }
    // MARK:- Private

    private func reserved(_ code: unichar) -> Bool {
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

