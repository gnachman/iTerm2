//
//  JSONArraySplice.swift
//  iTerm2
//
//  Inserts pre-serialized elements into a JSON array inside an already-serialized
//  JSON object, at the BYTE level, without parsing and re-emitting the object.
//
//  The blob send path uses this so a per-vendor request builder can keep owning
//  its body shape (Option A: reuse the builder) while the chat's frozen history is
//  spliced in VERBATIM. Verbatim matters because Anthropic's prompt cache is a
//  byte-prefix match: re-serializing via JSONSerialization could reorder keys and
//  break the cached prefix. The builder serializes the envelope + the new turn as
//  usual, then hands its output here to have the stored history bytes dropped into
//  its message array.
//
//  `object` is our own builder's JSONEncoder output (compact, well-formed), and
//  the array key ("messages" / "contents" / "input") is a top-level key whose
//  value follows it, so the first `"key":` occurrence is the real one.
//

import Foundation

enum JSONArraySplice {
    /// Insert `elementsInner` (the inner bytes of a JSON array: its elements joined
    /// by commas, WITHOUT the surrounding brackets, e.g. `{"a":1},{"b":2}`) into the
    /// array at top-level `key` of `object`, positioned after the first `afterCount`
    /// elements already in that array. Every other byte is preserved verbatim.
    /// Returns nil if the structure is not as expected (the caller falls back).
    static func insert(_ elementsInner: Data,
                       intoArrayKey key: String,
                       of object: Data,
                       afterCount: Int) -> Data? {
        guard !elementsInner.isEmpty else { return object }
        let bytes = [UInt8](object)
        let keyPattern = [UInt8]("\"\(key)\":".utf8)
        guard let keyStart = firstIndex(of: keyPattern, in: bytes) else { return nil }
        let open = keyStart + keyPattern.count
        guard open < bytes.count, bytes[open] == UInt8(ascii: "[") else { return nil }
        guard let insertion = insertionPoint(in: bytes, openBracketAt: open, afterCount: afterCount) else {
            return nil
        }
        let inner = [UInt8](elementsInner)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count + inner.count + 1)
        out.append(contentsOf: bytes[0..<insertion.offset])
        switch insertion.kind {
        case .emptyArray:
            out.append(contentsOf: inner)                        // []  -> [INNER]
        case .beforeElement:
            out.append(contentsOf: inner)                        // insert BEFORE an element:
            out.append(UInt8(ascii: ","))                        //   -> INNER,element
        case .atEnd:
            out.append(UInt8(ascii: ","))                        // insert after the last element:
            out.append(contentsOf: inner)                        //   -> lastElement,INNER  (before ])
        }
        out.append(contentsOf: bytes[insertion.offset..<bytes.count])
        return Data(out)
    }

    private enum InsertKind { case emptyArray, beforeElement, atEnd }
    private struct Insertion { var offset: Int; var kind: InsertKind }

    /// Where to drop the history into the array whose `[` is at `openBracketAt`.
    private static func insertionPoint(in bytes: [UInt8], openBracketAt open: Int, afterCount: Int) -> Insertion? {
        var i = open + 1
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") {
            return Insertion(offset: i, kind: .emptyArray)       // "[]" -> insert before ']'
        }
        if afterCount == 0 {
            return Insertion(offset: i, kind: .beforeElement)    // before the first element
        }
        // Walk the array counting top-level commas (element boundaries), string- and
        // depth-aware, until we have passed `afterCount` elements or hit the array's
        // closing ']'.
        var passed = 0
        var depth = 0
        var inString = false
        var escaped = false
        while i < bytes.count {
            let c = bytes[i]
            if inString {
                if escaped { escaped = false }
                else if c == UInt8(ascii: "\\") { escaped = true }
                else if c == UInt8(ascii: "\"") { inString = false }
                i += 1
                continue
            }
            switch c {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
            case UInt8(ascii: "]"):
                if depth == 0 {
                    return Insertion(offset: i, kind: .atEnd)     // fewer than afterCount elements: append at end
                }
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 0 {
                    passed += 1
                    if passed == afterCount {
                        return Insertion(offset: i + 1, kind: .beforeElement)  // start of element `afterCount`
                    }
                }
            default:
                break
            }
            i += 1
        }
        return nil  // malformed / no closing bracket
    }

    private static func firstIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        for start in 0...(bytes.count - pattern.count) {
            var matched = true
            for j in 0..<pattern.count where bytes[start + j] != pattern[j] {
                matched = false
                break
            }
            if matched { return start }
        }
        return nil
    }
}
