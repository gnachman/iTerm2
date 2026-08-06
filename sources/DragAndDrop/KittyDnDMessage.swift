//
//  KittyDnDMessage.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  A KittyDnDMessage is one complete, reassembled OSC 72 message: the
//  colon-separated key/value metadata plus an optional payload. This is the pure
//  wire layer; it has no knowledge of the terminal, AppKit, or I/O.
//
//  Wire format:
//     OSC 72 ; <metadata> [ ; <payload> ] ST
//  where OSC = ESC ] and ST = ESC \.
//
//  The payload's encoding depends on the message type, so this type stores it
//  UNDECODED (`rawPayload`) and exposes it two ways:
//    - textPayload: plain UTF-8, for MIME lists (t=a/m/M/o), machine ids, and
//      error strings.
//    - dataPayload: base64-decoded bytes, for file/image data (t=r/p/k).
//  The caller decodes according to the message's `t=` type.
//

import Foundation

/// Parsing/serialization of the colon-separated `key=value` metadata section.
/// Factored out so both `KittyDnDMessage` and `KittyDnDChunkReassembler` share
/// exactly one implementation.
enum KittyDnDMetadata {
    static func parse(_ string: String) -> [String: String] {
        var result: [String: String] = [:]
        for token in string.components(separatedBy: ":") {
            guard let eq = token.firstIndex(of: "=") else {
                // Tolerate malformed tokens rather than rejecting the whole
                // message (forward compatibility).
                continue
            }
            let key = String(token[token.startIndex..<eq])
            let value = String(token[token.index(after: eq)...])
            if !key.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    /// Serialize with a deterministic key order: `t` first, then the remaining
    /// keys sorted ascending. Determinism lets tests assert exact bytes.
    ///
    /// Values are sanitized of CR/LF so the serialized output can never contain
    /// a 0x0a/0x0d byte regardless of what a value holds. This is the security
    /// invariant: a metadata value is only ever a number or an echoed MIME type
    /// (neither of which legitimately contains a newline), so stripping CR/LF is
    /// both safe and guarantees no control-input injection.
    static func serialize(_ metadata: [String: String]) -> String {
        var parts: [String] = []
        if let t = metadata["t"] {
            parts.append("t=\(sanitize(t))")
        }
        for key in metadata.keys.sorted() where key != "t" {
            parts.append("\(key)=\(sanitize(metadata[key]!))")
        }
        return parts.joined(separator: ":")
    }

    /// Remove CR/LF. Used for both metadata values and the (possibly plain-text)
    /// payload so a serialized OSC 72 message can never carry a newline.
    static func sanitize(_ value: String) -> String {
        guard value.utf8.contains(where: { $0 == 0x0a || $0 == 0x0d }) else {
            return value
        }
        return String(value.unicodeScalars.filter { $0 != "\n" && $0 != "\r" })
    }
}

struct KittyDnDMessage: Equatable {
    /// Raw metadata key/value pairs (values are strings, as on the wire).
    var metadata: [String: String]

    /// The undecoded payload text between the metadata and ST. `nil` means there
    /// was no payload section at all; an empty string means there was a payload
    /// section but it was empty (the protocol uses that as a completion signal
    /// for t=r). Decode via `textPayload` or `dataPayload`.
    var rawPayload: String?

    init(metadata: [String: String], rawPayload: String? = nil) {
        self.metadata = metadata
        self.rawPayload = rawPayload
    }

    /// Construct with a plain-text payload (MIME list, machine id, error string).
    init(metadata: [String: String], textPayload: String) {
        self.metadata = metadata
        self.rawPayload = textPayload
    }

    /// Construct with a binary payload; it is base64-encoded on the wire.
    init(metadata: [String: String], dataPayload: Data) {
        self.metadata = metadata
        self.rawPayload = dataPayload.base64EncodedString()
    }

    /// Parse the OSC 72 content, i.e. everything between `OSC 72 ;` and `ST`. The
    /// payload is kept undecoded, so this never fails; validity of a binary
    /// payload is checked lazily by `dataPayload`.
    init(oscContent: String) {
        if let semicolon = oscContent.firstIndex(of: ";") {
            self.metadata = KittyDnDMetadata.parse(String(oscContent[oscContent.startIndex..<semicolon]))
            self.rawPayload = String(oscContent[oscContent.index(after: semicolon)...])
        } else {
            self.metadata = KittyDnDMetadata.parse(oscContent)
            self.rawPayload = nil
        }
    }

    // MARK: - Typed accessors

    var type: String? {
        return metadata["t"]
    }

    func intValue(_ key: String) -> Int? {
        guard let string = metadata[key] else {
            return nil
        }
        return Int(string)
    }

    var isMoreChunk: Bool {
        return metadata["m"] == "1"
    }

    /// The payload interpreted as plain UTF-8 text (MIME lists, machine ids).
    var textPayload: String? {
        return rawPayload
    }

    /// The payload interpreted as base64-encoded bytes (file/image data). Returns
    /// nil if the payload is absent or not valid base64. Padding is optional per
    /// the spec ("base64 padding bytes ... may or may not be present"), but
    /// Data(base64Encoded:) requires it, so we re-pad first.
    var dataPayload: Data? {
        guard let rawPayload else {
            return nil
        }
        let remainder = rawPayload.utf8.count % 4
        // A length of exactly 1 more than a multiple of 4 is never valid base64.
        if remainder == 1 {
            return nil
        }
        let padded = remainder == 0 ? rawPayload
                                     : rawPayload + String(repeating: "=", count: 4 - remainder)
        return Data(base64Encoded: padded)
    }

    // MARK: - Serialization

    /// The OSC 72 content: `<metadata>[;<payload>]`, without the OSC/ST wrapper.
    func serializedContent() -> String {
        let meta = KittyDnDMetadata.serialize(metadata)
        guard let rawPayload else {
            return meta
        }
        return "\(meta);\(KittyDnDMetadata.sanitize(rawPayload))"
    }

    /// The full escape sequence including the OSC 72 introducer and ST.
    func serialized() -> String {
        return "\u{1b}]72;\(serializedContent())\u{1b}\\"
    }
}
