//
//  KittyDnDChunker.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Outbound: split a payload into OSC 72 messages whose base64 payloads each fit
//  the 4096-byte limit, tagged with the m=1 (more) / m=0 (last) chunk flag.
//  Inbound: reassemble such a chunk sequence back into one KittyDnDMessage.
//

import Foundation

enum KittyDnDChunker {
    /// Maximum size, in bytes, of a chunk's base64-encoded payload.
    static let maxEncodedChunkSize = 4096

    /// Number of raw bytes whose base64 encoding is exactly `maxEncodedChunkSize`.
    /// base64 encodes 3 bytes as 4 characters, so 3072 raw bytes -> 4096 chars
    /// with no padding.
    static var maxRawChunkSize: Int {
        return maxEncodedChunkSize / 4 * 3
    }

    /// Split `payload` into base64 chunks, each at most `maxEncodedChunkSize`
    /// characters. Always returns at least one element (empty payload -> [""]).
    static func encodedChunks(for payload: Data,
                              maxRaw: Int = KittyDnDChunker.maxRawChunkSize) -> [String] {
        guard !payload.isEmpty else {
            return [""]
        }
        var chunks: [String] = []
        var offset = 0
        while offset < payload.count {
            let end = min(offset + maxRaw, payload.count)
            let slice = payload.subdata(in: offset..<end)
            chunks.append(slice.base64EncodedString())
            offset = end
        }
        return chunks
    }

    /// Build the sequence of OSC 72 messages for `payload`, carrying
    /// `baseMetadata` on every chunk plus the `m` more-flag. A single chunk is
    /// emitted with m=0 (final).
    static func messages(baseMetadata: [String: String],
                         payload: Data) -> [KittyDnDMessage] {
        let chunks = encodedChunks(for: payload)
        return chunks.enumerated().map { index, encoded in
            var metadata = baseMetadata
            let isLast = (index == chunks.count - 1)
            metadata["m"] = isLast ? "0" : "1"
            let data = Data(base64Encoded: encoded) ?? Data()
            return KittyDnDMessage(metadata: metadata, payload: data)
        }
    }
}

/// Reassembles a chunked OSC 72 payload. Feed it the raw OSC content of each
/// message in order; it returns nil while chunks are outstanding (m=1) and the
/// completed message when the final chunk (m=0 or absent) arrives.
///
/// Reassembly accumulates the raw base64 strings and decodes once at the end, so
/// it is robust even if a peer splits payloads on non-3-byte boundaries.
final class KittyDnDChunkReassembler {
    private var accumulatedBase64 = ""
    private var pendingMetadata: [String: String]?

    /// Returns the completed message, or nil if more chunks are expected.
    func accept(_ oscContent: String) -> KittyDnDMessage? {
        let metadataString: String
        let payloadString: String
        if let semicolon = oscContent.firstIndex(of: ";") {
            metadataString = String(oscContent[oscContent.startIndex..<semicolon])
            payloadString = String(oscContent[oscContent.index(after: semicolon)...])
        } else {
            metadataString = oscContent
            payloadString = ""
        }
        let metadata = KittyDnDMetadata.parse(metadataString)

        // The metadata of the whole logical message comes from the first chunk.
        if pendingMetadata == nil {
            pendingMetadata = metadata
        }
        accumulatedBase64 += payloadString

        if metadata["m"] == "1" {
            // More chunks to come.
            return nil
        }

        // Final chunk: assemble.
        var finalMetadata = pendingMetadata ?? metadata
        finalMetadata.removeValue(forKey: "m")
        let hadPayloadSection = oscContent.contains(";") || !accumulatedBase64.isEmpty
        let payload: Data?
        if hadPayloadSection {
            payload = Data(base64Encoded: accumulatedBase64) ?? Data()
        } else {
            payload = nil
        }
        reset()
        return KittyDnDMessage(metadata: finalMetadata, payload: payload)
    }

    private func reset() {
        accumulatedBase64 = ""
        pendingMetadata = nil
    }
}
