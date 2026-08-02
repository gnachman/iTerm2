//
//  KittyDnDMessage.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  A KittyDnDMessage is one complete, reassembled OSC 72 message: the
//  colon-separated key/value metadata plus an optional decoded payload. This is
//  the pure wire layer; it has no knowledge of the terminal, AppKit, or I/O.
//
//  Wire format:
//     OSC 72 ; <metadata> [ ; <base64-payload> ] ST
//  where OSC = ESC ] and ST = ESC \.
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

    private static func sanitize(_ value: String) -> String {
        guard value.utf8.contains(where: { $0 == 0x0a || $0 == 0x0d }) else {
            return value
        }
        return String(value.unicodeScalars.filter { $0 != "\n" && $0 != "\r" })
    }
}

struct KittyDnDMessage: Equatable {
    /// Raw metadata key/value pairs (values are strings, as on the wire).
    var metadata: [String: String]

    /// Decoded payload bytes. `nil` means there was no payload section at all;
    /// an empty `Data` means there was a payload section but it was empty (the
    /// protocol uses that as a completion signal for `t=r`).
    var payload: Data?

    init(metadata: [String: String], payload: Data? = nil) {
        self.metadata = metadata
        self.payload = payload
    }

    /// Parse the OSC 72 content, i.e. everything between `OSC 72 ;` and `ST`.
    /// Returns nil only if a present payload section is not valid base64.
    init?(oscContent: String) {
        let metadataString: String
        let payloadString: String?
        if let semicolon = oscContent.firstIndex(of: ";") {
            metadataString = String(oscContent[oscContent.startIndex..<semicolon])
            payloadString = String(oscContent[oscContent.index(after: semicolon)...])
        } else {
            metadataString = oscContent
            payloadString = nil
        }

        if let payloadString {
            if payloadString.isEmpty {
                self.payload = Data()
            } else if let decoded = Data(base64Encoded: payloadString) {
                self.payload = decoded
            } else {
                return nil
            }
        } else {
            self.payload = nil
        }
        self.metadata = KittyDnDMetadata.parse(metadataString)
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

    // MARK: - Serialization

    /// The OSC 72 content: `<metadata>[;<base64>]`, without the OSC/ST wrapper.
    func serializedContent() -> String {
        let meta = KittyDnDMetadata.serialize(metadata)
        guard let payload else {
            return meta
        }
        return "\(meta);\(payload.base64EncodedString())"
    }

    /// The full escape sequence including the OSC 72 introducer and ST.
    func serialized() -> String {
        return "\u{1b}]72;\(serializedContent())\u{1b}\\"
    }
}
