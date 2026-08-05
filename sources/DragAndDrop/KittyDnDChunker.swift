//
//  KittyDnDChunker.swift
//  iTerm2SharedARC
//
//  Kitty drag-and-drop protocol (OSC 72). See docs/kitty-dnd-design.md.
//
//  Outbound: split a binary payload into OSC 72 messages whose base64 payloads
//  each fit the 4096-byte limit, tagged with the m=1 (more) / m=0 (last) chunk
//  flag. Inbound: reassemble such a chunk sequence back into one KittyDnDMessage.
//
//  Only binary (base64) payloads are chunked; plain-text payloads (MIME lists,
//  machine ids) are small and sent as a single message by the caller.
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

    /// Build the sequence of OSC 72 messages for a binary `payload`, carrying
    /// `baseMetadata` on every message.
    ///
    /// The protocol frames end-of-data as a final message with an EMPTY payload
    /// and m=0; every data-bearing message carries m=1. So this emits one m=1
    /// message per base64 chunk followed by a single empty m=0 terminator (for an
    /// empty payload, just the terminator).
    static func messages(baseMetadata: [String: String],
                         data payload: Data) -> [KittyDnDMessage] {
        var messages: [KittyDnDMessage] = []
        if !payload.isEmpty {
            for chunk in encodedChunks(for: payload) {
                var metadata = baseMetadata
                metadata["m"] = "1"
                messages.append(KittyDnDMessage(metadata: metadata, rawPayload: chunk))
            }
        }
        var terminator = baseMetadata
        terminator["m"] = "0"
        messages.append(KittyDnDMessage(metadata: terminator, rawPayload: ""))
        return messages
    }
}

/// Reassembles a chunked OSC 72 payload. Feed it the raw OSC content of each
/// message in order; it returns nil while chunks are outstanding (m=1) and the
/// completed message when the final chunk (m=0 or absent) arrives.
///
/// Reassembly concatenates the raw (undecoded) payload of every chunk. This
/// matches the protocol's "4096-byte limit applied post-encoding" model, where a
/// peer may split the base64 stream at arbitrary positions (including inside a
/// 4-character base64 group): those pieces are not individually valid base64, but
/// their concatenation is. Our own outbound chunker splits on 3-byte-aligned
/// boundaries, which is a special case that works under either interpretation.
/// Decoding is deferred to the caller (via dataPayload/textPayload), so a corrupt
/// payload surfaces as a nil dataPayload at the point of use rather than being
/// silently dropped here.
final class KittyDnDChunkReassembler {
    /// Cap on the reassembled size of a single logical message. Generous enough
    /// for uri-lists, thumbnails, and realistically draggable files, but finite so
    /// a peer that streams m=1 chunks forever (never terminating) cannot grow
    /// memory without bound. On breach the sequence is abandoned and its remaining
    /// chunks are drained.
    static let maxAccumulatedBytes = 512 * 1024 * 1024

    private var accumulatedPayload = ""
    private var accumulatedByteCount = 0
    private var pendingMetadata: [String: String]?
    private var sawPayloadSection = false
    // Draining the tail of an over-large sequence (discarding chunks until it
    // terminates), so its remainder is not misread as a new message.
    private var draining = false

    /// Returns the completed message, or nil if more chunks are expected.
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

        // A message that arrives mid-transfer whose `t=` DIFFERS from the pending
        // sequence's is a separate interleaved message, not a continuation chunk
        // (a continuation either omits `t` or repeats the sequence's own `t`). The
        // spec permits a query (t=q|Q) during a chunked transfer. Return it as its
        // own complete message without disturbing the pending sequence, so the
        // query is answered and the transfer still completes.
        if let pending = pendingMetadata, let t = metadata["t"], t != pending["t"] {
            let payload: String? = hasPayloadSection ? payloadString : nil
            return KittyDnDMessage(metadata: metadata, rawPayload: payload)
        }

        // Discard the remaining chunks of an over-large abandoned sequence until
        // it terminates (pendingMetadata is kept during the drain purely so the
        // interleave check above can still distinguish a query from a chunk).
        if draining {
            if metadata["m"] != "1" {
                reset()
            }
            return nil
        }

        // The metadata of the whole logical message comes from the first chunk.
        if pendingMetadata == nil {
            pendingMetadata = metadata
        }
        accumulatedPayload += payloadString
        accumulatedByteCount += payloadString.utf8.count
        sawPayloadSection = sawPayloadSection || hasPayloadSection

        if accumulatedByteCount > Self.maxAccumulatedBytes {
            // Abandon this sequence and free its buffer now. Keep the sequence
            // identity and drain the rest unless this chunk already terminated it.
            let terminated = metadata["m"] != "1"
            accumulatedPayload = ""
            accumulatedByteCount = 0
            sawPayloadSection = false
            if terminated {
                reset()
            } else {
                draining = true
            }
            return nil
        }

        if metadata["m"] == "1" {
            // More chunks to come.
            return nil
        }

        var finalMetadata = pendingMetadata ?? metadata
        finalMetadata.removeValue(forKey: "m")
        let payload: String? = sawPayloadSection ? accumulatedPayload : nil
        reset()
        return KittyDnDMessage(metadata: finalMetadata, rawPayload: payload)
    }

    private func reset() {
        accumulatedPayload = ""
        accumulatedByteCount = 0
        pendingMetadata = nil
        sawPayloadSection = false
        draining = false
    }
}
