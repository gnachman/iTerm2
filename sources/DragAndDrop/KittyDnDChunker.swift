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
/// Reassembly concatenates the raw base64 of every chunk and decodes once at the
/// end. This matches the protocol's "4096-byte limit applied post-encoding"
/// model, where a peer may split the base64 *stream* at arbitrary positions
/// (including inside a 4-character base64 group): those pieces are not
/// individually valid base64, but their concatenation is. Our own outbound
/// chunker splits on 3-byte-aligned boundaries, which is a special case that
/// works under either interpretation.
///
/// The final message is built by feeding the reassembled content back through
/// `KittyDnDMessage(oscContent:)`, so validation (including base64 correctness
/// and the nil-vs-empty-payload distinction) is identical to the single-message
/// path. A corrupt payload therefore yields nil (and a log line), never a
/// silently-empty payload.
final class KittyDnDChunkReassembler {
    private var accumulatedBase64 = ""
    private var pendingMetadata: [String: String]?
    private var sawPayloadSection = false

    /// Returns the completed message, or nil if more chunks are expected or the
    /// reassembled payload could not be decoded.
    func accept(_ oscContent: String) -> KittyDnDMessage? {
        let metadataString: String
        let payloadString: String
        let hasPayloadSection: Bool
        if let semicolon = oscContent.firstIndex(of: ";") {
            metadataString = String(oscContent[oscContent.startIndex..<semicolon])
            payloadString = String(oscContent[oscContent.index(after: semicolon)...])
            hasPayloadSection = true
        } else {
            metadataString = oscContent
            payloadString = ""
            hasPayloadSection = false
        }
        let metadata = KittyDnDMetadata.parse(metadataString)

        // The metadata of the whole logical message comes from the first chunk.
        if pendingMetadata == nil {
            pendingMetadata = metadata
        }
        accumulatedBase64 += payloadString
        sawPayloadSection = sawPayloadSection || hasPayloadSection

        if metadata["m"] == "1" {
            // More chunks to come.
            return nil
        }

        // Final chunk: rebuild the complete OSC content and parse it through the
        // same path as an unchunked message.
        var finalMetadata = pendingMetadata ?? metadata
        finalMetadata.removeValue(forKey: "m")
        let base64 = accumulatedBase64
        let hadPayloadSection = sawPayloadSection
        reset()

        var content = KittyDnDMetadata.serialize(finalMetadata)
        if hadPayloadSection {
            content += ";\(base64)"
        }
        guard let message = KittyDnDMessage(oscContent: content) else {
            DLog("Dropping Kitty DnD chunked message with undecodable payload")
            return nil
        }
        return message
    }

    private func reset() {
        accumulatedBase64 = ""
        pendingMetadata = nil
        sawPayloadSection = false
    }
}
