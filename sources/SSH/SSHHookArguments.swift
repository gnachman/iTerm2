//
//  SSHHookArguments.swift
//  iTerm2SharedARC
//

import Foundation

// it2ssh reports its ssh arguments as base64 of bash's `printf %q` output. macOS's bash 3.2
// quotes a non-ASCII word as $'...' with raw lead bytes mixed among octal escapes, so the
// decoded bytes need not be valid UTF-8 even when every argument was. This decodes the
// shell quoting at the byte level and requotes the words as UTF-8 in a form that
// -componentsInShellCommand (which ParsedSSHArguments uses) splits back into the same words.
@objc(iTermSSHHookArguments)
class SSHHookArguments: NSObject {
    // Returns nil if the quoting is malformed or a word is not valid UTF-8.
    @objc(normalizedArgumentsFromData:)
    static func normalizedArguments(_ data: Data) -> String? {
        var decoder = ShellQuotedWordDecoder(Array(data))
        guard let words = decoder.decode() else {
            DLog("Malformed shell quoting in ssh arguments")
            return nil
        }
        var strings = [String]()
        for word in words {
            guard !word.contains(0), let string = String(data: Data(word), encoding: .utf8) else {
                DLog("ssh argument is not valid UTF-8")
                return nil
            }
            strings.append(string)
        }
        return quote(words: strings)
    }

    // For showing normalized arguments in a banner: control characters, which the
    // quoting leaves raw, become visible.
    @objc(displayStringForNormalizedArguments:)
    static func displayString(_ normalized: String) -> String {
        var result = ""
        for scalar in normalized.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) && scalar.value < 0x100 {
                result += String(format: "\\x%02X", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func quote(words: [String]) -> String {
        return words.map { quote($0) }.joined(separator: " ")
    }

    // Backslash-escapes every character -componentsInShellCommand could treat specially.
    // It maps an escaped n, a, t, or r to a control character, so letters and digits are
    // never escaped; any other character after a backslash stands for itself. bash reads
    // the result the same way, which matters because a jump passes it to it2ssh.
    private static func quote(_ word: String) -> String {
        if word.isEmpty {
            return "''"
        }
        var result = ""
        for scalar in word.unicodeScalars {
            if scalar == "\n" {
                // bash removes a backslash-newline, so quote it. The jump script passes
                // these arguments to bash.
                result.append("'\n'")
                continue
            }
            if needsEscaping(scalar) {
                result.append("\\")
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    private static let safeASCII = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=@,+%")

    private static func needsEscaping(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            return !safeASCII.contains(scalar)
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar) ||
            CharacterSet.controlCharacters.contains(scalar) ||
            iswspace(wint_t(scalar.value)) != 0
    }
}

// Splits bytes into words following bash's quoting rules for the forms `printf %q` emits:
// backslash escapes, '...', "...", and $'...' (ANSI-C quoting).
private struct ShellQuotedWordDecoder {
    private let bytes: [UInt8]
    private var i = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    private static let backslash = UInt8(ascii: "\\")
    private static let singleQuote = UInt8(ascii: "'")
    private static let doubleQuote = UInt8(ascii: "\"")
    private static let dollar = UInt8(ascii: "$")
    private static let newline = UInt8(ascii: "\n")

    private static func isSeparator(_ c: UInt8) -> Bool {
        return c == UInt8(ascii: " ") || c == UInt8(ascii: "\t") || c == newline
    }

    mutating func decode() -> [[UInt8]]? {
        var words = [[UInt8]]()
        var current = [UInt8]()
        var inWord = false
        while i < bytes.count {
            let c = bytes[i]
            if Self.isSeparator(c) {
                if inWord {
                    words.append(current)
                    current = []
                    inWord = false
                }
                i += 1
                continue
            }
            if c == Self.backslash && i + 1 < bytes.count && bytes[i + 1] == Self.newline {
                // Line continuation.
                i += 2
                continue
            }
            inWord = true
            switch c {
            case Self.backslash:
                if i + 1 < bytes.count {
                    current.append(bytes[i + 1])
                    i += 2
                } else {
                    current.append(c)
                    i += 1
                }
            case Self.singleQuote:
                guard let end = bytes[(i + 1)...].firstIndex(of: Self.singleQuote) else {
                    return nil
                }
                current.append(contentsOf: bytes[(i + 1)..<end])
                i = end + 1
            case Self.doubleQuote:
                i += 1
                guard decodeDoubleQuoted(into: &current) else {
                    return nil
                }
            case Self.dollar where i + 1 < bytes.count && bytes[i + 1] == Self.singleQuote:
                i += 2
                guard decodeANSIC(into: &current) else {
                    return nil
                }
            default:
                current.append(c)
                i += 1
            }
        }
        if inWord {
            words.append(current)
        }
        return words
    }

    // On entry i is just past the opening quote. On success it is just past the closing one.
    private mutating func decodeDoubleQuoted(into current: inout [UInt8]) -> Bool {
        let escapable: Set<UInt8> = [UInt8(ascii: "$"), UInt8(ascii: "`"), Self.doubleQuote, Self.backslash, Self.newline]
        while i < bytes.count {
            let c = bytes[i]
            if c == Self.doubleQuote {
                i += 1
                return true
            }
            if c == Self.backslash && i + 1 < bytes.count && escapable.contains(bytes[i + 1]) {
                if bytes[i + 1] != Self.newline {
                    current.append(bytes[i + 1])
                }
                i += 2
                continue
            }
            current.append(c)
            i += 1
        }
        return false
    }

    // On entry i is just past $'. On success it is just past the closing quote.
    private mutating func decodeANSIC(into current: inout [UInt8]) -> Bool {
        while i < bytes.count {
            let c = bytes[i]
            if c == Self.singleQuote {
                i += 1
                return true
            }
            if c != Self.backslash || i + 1 >= bytes.count {
                current.append(c)
                i += 1
                continue
            }
            let e = bytes[i + 1]
            i += 2
            switch e {
            case UInt8(ascii: "a"): current.append(0x07)
            case UInt8(ascii: "b"): current.append(0x08)
            case UInt8(ascii: "e"), UInt8(ascii: "E"): current.append(0x1b)
            case UInt8(ascii: "f"): current.append(0x0c)
            case UInt8(ascii: "n"): current.append(0x0a)
            case UInt8(ascii: "r"): current.append(0x0d)
            case UInt8(ascii: "t"): current.append(0x09)
            case UInt8(ascii: "v"): current.append(0x0b)
            case Self.backslash, Self.singleQuote, Self.doubleQuote, UInt8(ascii: "?"):
                current.append(e)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = UInt32(e - UInt8(ascii: "0"))
                var digits = 1
                while digits < 3, i < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(bytes[i]) {
                    value = value * 8 + UInt32(bytes[i] - UInt8(ascii: "0"))
                    i += 1
                    digits += 1
                }
                current.append(UInt8(value & 0xff))
            case UInt8(ascii: "x"):
                if let value = scanHex(maxDigits: 2) {
                    current.append(UInt8(value))
                } else {
                    current.append(contentsOf: [Self.backslash, e])
                }
            case UInt8(ascii: "u"), UInt8(ascii: "U"):
                if let value = scanHex(maxDigits: e == UInt8(ascii: "u") ? 4 : 8),
                   let scalar = Unicode.Scalar(value) {
                    current.append(contentsOf: Array(String(Character(scalar)).utf8))
                } else {
                    current.append(contentsOf: [Self.backslash, e])
                }
            case UInt8(ascii: "c"):
                guard i < bytes.count else {
                    current.append(contentsOf: [Self.backslash, e])
                    break
                }
                current.append(bytes[i] & 0x1f)
                i += 1
            default:
                // bash keeps an unrecognized escape as written.
                current.append(contentsOf: [Self.backslash, e])
            }
        }
        return false
    }

    private mutating func scanHex(maxDigits: Int) -> UInt32? {
        var value: UInt32 = 0
        var digits = 0
        while digits < maxDigits, i < bytes.count, let digit = Self.hexValue(bytes[i]) {
            value = value * 16 + UInt32(digit)
            i += 1
            digits += 1
        }
        return digits > 0 ? value : nil
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
