//
//  BashWordSplitter.swift
//  iTerm2SharedARC
//
//  Splits a string into words the way bash would, for the arguments it2ssh sends. it2ssh quotes
//  each of its arguments with bash's `printf %q`, and on macOS's bash 3.2 that writes newlines,
//  tabs, other control characters and every non-ASCII character as ANSI-C quoting, $'…' with
//  octal escapes. NSString's componentsInShellCommand does not know that form, so such an
//  argument arrived mangled; this does.
//
//  Covers what %q produces and what a person would type: whitespace between words, backslash
//  escapes, '…', "…" and $'…'. Not expansions, globs, operators or comments: those have no meaning
//  in an argument list that has already been quoted.
//

import Foundation

enum BashWordSplitter {
    static func words(_ string: String) -> [String] {
        let bytes = Array(string.utf8)
        var words = [String]()
        var current = [UInt8]()
        var inWord = false
        var i = 0

        func finishWord() {
            if inWord {
                words.append(String(decoding: current, as: UTF8.self))
            }
            current = []
            inWord = false
        }

        while i < bytes.count {
            let c = bytes[i]
            switch c {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"):
                finishWord()
                i += 1
            case UInt8(ascii: "\\"):
                inWord = true
                if i + 1 < bytes.count {
                    // A backslash-newline joins lines; anything else is taken literally.
                    if bytes[i + 1] != UInt8(ascii: "\n") {
                        current.append(bytes[i + 1])
                    }
                    i += 2
                } else {
                    i += 1
                }
            case UInt8(ascii: "'"):
                inWord = true
                i += 1
                while i < bytes.count && bytes[i] != UInt8(ascii: "'") {
                    current.append(bytes[i])
                    i += 1
                }
                i += 1
            case UInt8(ascii: "\""):
                inWord = true
                i += 1
                while i < bytes.count && bytes[i] != UInt8(ascii: "\"") {
                    if bytes[i] == UInt8(ascii: "\\"), i + 1 < bytes.count,
                       [UInt8(ascii: "\\"), UInt8(ascii: "\""), UInt8(ascii: "$"),
                        UInt8(ascii: "`"), UInt8(ascii: "\n")].contains(bytes[i + 1]) {
                        if bytes[i + 1] != UInt8(ascii: "\n") {
                            current.append(bytes[i + 1])
                        }
                        i += 2
                        continue
                    }
                    current.append(bytes[i])
                    i += 1
                }
                i += 1
            case UInt8(ascii: "$") where i + 1 < bytes.count && bytes[i + 1] == UInt8(ascii: "'"):
                inWord = true
                i = ansiC(bytes, from: i + 2, into: &current)
            default:
                inWord = true
                current.append(c)
                i += 1
            }
        }
        finishWord()
        return words
    }

    /// Decodes the body of $'…' starting at `start`, appending to `out`. Returns the index after
    /// the closing quote.
    private static func ansiC(_ bytes: [UInt8], from start: Int, into out: inout [UInt8]) -> Int {
        var i = start
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "'") {
                return i + 1
            }
            guard c == UInt8(ascii: "\\"), i + 1 < bytes.count else {
                out.append(c)
                i += 1
                continue
            }
            let e = bytes[i + 1]
            i += 2
            switch e {
            case UInt8(ascii: "a"): out.append(0x07)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "e"), UInt8(ascii: "E"): out.append(0x1b)
            case UInt8(ascii: "f"): out.append(0x0c)
            case UInt8(ascii: "n"): out.append(0x0a)
            case UInt8(ascii: "r"): out.append(0x0d)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "v"): out.append(0x0b)
            case UInt8(ascii: "\\"), UInt8(ascii: "'"), UInt8(ascii: "\""), UInt8(ascii: "?"):
                out.append(e)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                // Up to three octal digits, the first already read.
                var value = Int(e - UInt8(ascii: "0"))
                var digits = 1
                while digits < 3, i < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(bytes[i]) {
                    value = value * 8 + Int(bytes[i] - UInt8(ascii: "0"))
                    i += 1
                    digits += 1
                }
                out.append(UInt8(truncatingIfNeeded: value))
            case UInt8(ascii: "x"):
                let (value, next) = hex(bytes, from: i, maxDigits: 2)
                if let value {
                    out.append(UInt8(truncatingIfNeeded: value))
                    i = next
                } else {
                    out.append(contentsOf: [UInt8(ascii: "\\"), e])
                }
            case UInt8(ascii: "u"), UInt8(ascii: "U"):
                let (value, next) = hex(bytes, from: i, maxDigits: e == UInt8(ascii: "u") ? 4 : 8)
                if let value, let scalar = Unicode.Scalar(UInt32(value)) {
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                    i = next
                } else {
                    out.append(contentsOf: [UInt8(ascii: "\\"), e])
                }
            case UInt8(ascii: "c") where i < bytes.count:
                out.append(bytes[i] & 0x1f)
                i += 1
            default:
                // Unknown escapes keep their backslash, as bash does.
                out.append(contentsOf: [UInt8(ascii: "\\"), e])
            }
        }
        return i
    }

    private static func hex(_ bytes: [UInt8], from start: Int, maxDigits: Int) -> (Int?, Int) {
        var value = 0
        var i = start
        while i < bytes.count, i - start < maxDigits, let digit = hexDigit(bytes[i]) {
            value = value * 16 + digit
            i += 1
        }
        return i == start ? (nil, start) : (value, i)
    }

    private static func hexDigit(_ c: UInt8) -> Int? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(c - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(c - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(c - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }
}
