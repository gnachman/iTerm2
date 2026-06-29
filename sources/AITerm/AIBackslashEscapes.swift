//
//  AIBackslashEscapes.swift
//  iTerm2SharedARC
//

import Foundation

// Decoder for the small backslash-escape vocabulary the AI agent
// uses inside text-typing tools (insert_text_at_cursor on the
// session-bound side, send_text on the orchestration side). Lets
// the model drive control keys and special characters by typing
// e.g.  for Escape,  for Ctrl-D,  for Ctrl-C.
//
// Grammar:
//   \\        backslash
//   \n        LF (0x0A)
//   \r        CR (0x0D)
//   \t        TAB (0x09)
//   \uXXXX    Unicode scalar (4 hex digits, like JSON)
// Anything else after a backslash is an error so the agent gets
// loud feedback instead of silently sending the wrong bytes.
enum AIBackslashEscapeError: Error, CustomStringConvertible {
    case unknownEscape(String)
    case truncatedUnicodeEscape
    case invalidUnicodeScalar(String)
    case danglingBackslash

    var description: String {
        switch self {
        case .unknownEscape(let s):
            return "Unknown backslash escape \u{201C}\(s)\u{201D}. Recognized: \\\\, \\n, \\r, \\t, \\uXXXX."
        case .truncatedUnicodeEscape:
            return "Truncated \\uXXXX escape (needs exactly four hex digits)."
        case .invalidUnicodeScalar(let hex):
            return "\\u\(hex) is not a valid Unicode scalar."
        case .danglingBackslash:
            return "Text ends with an unescaped backslash."
        }
    }
}

func decodeAIBackslashEscapes(_ s: String) throws -> String {
    if !s.contains("\\") {
        return s
    }
    var out = ""
    out.reserveCapacity(s.count)
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c != "\\" {
            out.append(c)
            i = s.index(after: i)
            continue
        }
        let next = s.index(after: i)
        guard next < s.endIndex else {
            throw AIBackslashEscapeError.danglingBackslash
        }
        let escape = s[next]
        switch escape {
        case "\\":
            out.append("\\")
            i = s.index(after: next)
        case "n":
            out.append("\n")
            i = s.index(after: next)
        case "r":
            out.append("\r")
            i = s.index(after: next)
        case "t":
            out.append("\t")
            i = s.index(after: next)
        case "u":
            // Four hex digits, JSON-style. We deliberately don't
            // accept the Swift \u{XXXX} form: the agent is targeting
            // a wire string, not a Swift literal, so JSON's shape
            // (four hex digits, no braces) is the right idiom.
            //
            // Per RFC 8259 §7, characters outside the BMP are encoded as
            // a UTF-16 surrogate pair: a high surrogate (D800..DBFF)
            // followed by another \uXXXX low surrogate (DC00..DFFF).
            // Combine the pair into a single non-BMP scalar; reject
            // isolated surrogates as malformed.
            let hexStart = s.index(after: next)
            guard let hexEnd = s.index(hexStart, offsetBy: 4, limitedBy: s.endIndex) else {
                throw AIBackslashEscapeError.truncatedUnicodeEscape
            }
            let hex = String(s[hexStart..<hexEnd])
            guard hex.count == 4,
                  hex.allSatisfy({ $0.isHexDigit }),
                  let codeUnit = UInt32(hex, radix: 16) else {
                throw AIBackslashEscapeError.invalidUnicodeScalar(hex)
            }
            if (0xD800...0xDBFF).contains(codeUnit) {
                // High surrogate; require an immediately-following \uXXXX
                // low surrogate.
                let lowEscapeStart = hexEnd
                guard let lowBackslashEnd = s.index(lowEscapeStart, offsetBy: 2, limitedBy: s.endIndex),
                      s[lowEscapeStart] == "\\",
                      s[s.index(after: lowEscapeStart)] == "u" else {
                    throw AIBackslashEscapeError.invalidUnicodeScalar(hex)
                }
                let lowHexStart = lowBackslashEnd
                guard let lowHexEnd = s.index(lowHexStart, offsetBy: 4, limitedBy: s.endIndex) else {
                    throw AIBackslashEscapeError.truncatedUnicodeEscape
                }
                let lowHex = String(s[lowHexStart..<lowHexEnd])
                guard lowHex.count == 4,
                      lowHex.allSatisfy({ $0.isHexDigit }),
                      let lowUnit = UInt32(lowHex, radix: 16),
                      (0xDC00...0xDFFF).contains(lowUnit) else {
                    throw AIBackslashEscapeError.invalidUnicodeScalar(lowHex)
                }
                let combined = 0x10000 + ((codeUnit - 0xD800) << 10) + (lowUnit - 0xDC00)
                guard let scalar = Unicode.Scalar(combined) else {
                    throw AIBackslashEscapeError.invalidUnicodeScalar(hex + lowHex)
                }
                out.append(Character(scalar))
                i = lowHexEnd
            } else if (0xDC00...0xDFFF).contains(codeUnit) {
                throw AIBackslashEscapeError.invalidUnicodeScalar(hex)
            } else {
                guard let scalar = Unicode.Scalar(codeUnit) else {
                    throw AIBackslashEscapeError.invalidUnicodeScalar(hex)
                }
                out.append(Character(scalar))
                i = hexEnd
            }
        default:
            throw AIBackslashEscapeError.unknownEscape("\\\(escape)")
        }
    }
    return out
}
