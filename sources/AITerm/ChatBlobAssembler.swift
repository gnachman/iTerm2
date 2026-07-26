//
//  ChatBlobAssembler.swift
//  iTerm2
//
//  Reconstructs a chat's outgoing wire message array by STITCHING its stored
//  per-round blobs, the read side of the blob redesign (ChatBlobCapture is the
//  write side). Each blob's payload is a JSON array of one round's request-shape
//  wire messages, frozen under the chat's protocol; stitching is simply
//  concatenating those arrays in order. By the compositionality proof in
//  ChatBlobWireEncoderTests (convert(r1+r2) == convert(r1)+convert(r2)), the
//  stitched array equals what the live per-vendor builder would produce for the
//  whole conversation, so replay is byte-faithful without re-running the fragile
//  reconstruction pipeline.
//
//  Stitching is done at the JSON level (concatenate arrays of message objects),
//  NOT by decoding into the typed wire structs: some are encode-only (e.g.
//  CompletionsMessage emits role "tool" but cannot decode it). The envelope
//  (system, tools, the volatile per-turn context) and protocol-specific cache
//  markers are NOT added here; they are applied by the per-protocol request
//  builder around this array at send time, exactly as they were excluded at capture.
//

import Foundation

enum ChatBlobAssemblerError: Error, CustomStringConvertible {
    /// A blob's stored payload was not a JSON array of wire messages (corruption
    /// or a truncated write). The caller must fall back to codec reconstruction
    /// rather than send a holed conversation.
    case corruptPayload(blobID: UUID)

    var description: String {
        switch self {
        case .corruptPayload(let blobID):
            return "ChatBlob \(blobID) payload is not a JSON array of wire messages"
        }
    }
}

enum ChatBlobAssembler {
    /// Concatenate the wire-message arrays of `blobs` (in the given order) into one
    /// array, at the JSON level. Throws `corruptPayload` if any payload is not a
    /// JSON array so the caller can fall back rather than splice a holed history.
    ///
    /// The caller is responsible for the higher-level integrity checks that decide
    /// whether the blob path is safe at all: that every stored row decoded (a
    /// decoded-count vs row-count match, so an unreadable future-protocol blob
    /// doesn't silently shorten the history) and that the chat's protocol is one
    /// this build supports. This function only merges the payloads it is handed.
    static func stitch(_ blobs: [ChatBlob]) throws -> [Any] {
        var merged: [Any] = []
        for blob in blobs {
            // `try?` folds a JSON parse failure (invalid bytes) and a valid-but-
            // non-array payload into one corruptPayload signal, so a corrupt or
            // truncated blob always routes the caller to the fallback rather than
            // leaking a raw JSONSerialization error.
            guard let array = (try? JSONSerialization.jsonObject(with: blob.payload)) as? [Any] else {
                throw ChatBlobAssemblerError.corruptPayload(blobID: blob.blobID)
            }
            merged.append(contentsOf: array)
        }
        return merged
    }

    /// Byte-level stitch: concatenate the VERBATIM inner bytes of each blob's
    /// payload array into one JSON array, without parsing and re-serializing the
    /// message objects. This is what the actual send path uses, because Anthropic's
    /// prompt cache is a byte-prefix match: the frozen history bytes must be
    /// identical turn over turn, which a JSONSerialization round-trip (which may
    /// reorder keys) would not guarantee. Each payload is validated as a JSON array
    /// first (corrupt -> throw -> caller falls back); only its inner bytes (between
    /// the outer brackets) are spliced, so the emitted history is exactly the bytes
    /// that were captured.
    static func stitchBytes(_ blobs: [ChatBlob]) throws -> Data {
        var result = Data([0x5B])  // [
        result.append(try stitchInner(blobs))
        result.append(0x5D)  // ]
        return result
    }

    /// The verbatim inner element bytes (the messages joined by commas, WITHOUT the
    /// surrounding brackets) of a chat's blobs. This is what a per-vendor builder
    /// splices into its own message array via JSONArraySplice, so the history is
    /// reproduced byte-for-byte. Empty when there are no blobs. Throws on a corrupt
    /// payload (caller falls back).
    static func stitchInner(_ blobs: [ChatBlob]) throws -> Data {
        var result = Data()
        var wroteAny = false
        for blob in blobs {
            guard (try? JSONSerialization.jsonObject(with: blob.payload)) is [Any] else {
                throw ChatBlobAssemblerError.corruptPayload(blobID: blob.blobID)
            }
            let inner = innerBytes(ofJSONArray: blob.payload)
            if inner.isEmpty { continue }
            if wroteAny { result.append(0x2C) }  // ,
            result.append(inner)
            wroteAny = true
        }
        return result
    }

    /// The bytes of a compact JSON array between its outer `[` and `]` (empty for
    /// `[]`). The payloads are JSONEncoder output (compact, no surrounding
    /// whitespace), so the first byte is `[` and the last is `]`; this trims those.
    private static func innerBytes(ofJSONArray data: Data) -> Data {
        guard data.count > 2 else { return Data() }  // "[]" or shorter -> empty
        return data.subdata(in: (data.startIndex + 1)..<(data.endIndex - 1))
    }

    /// The safety gate for blob-native replay. Returns the stitched wire history
    /// for `chatID` ONLY if the blob path is provably safe; otherwise nil, so the
    /// caller falls back to codec reconstruction. Returning nil (rather than
    /// throwing) makes "fall back" the natural default for every not-safe case:
    ///
    /// - the chat has no blobs (legacy / never captured) -> migrate via the codec;
    /// - a stored row failed to decode, so `blobs(inChat:)` is SHORTER than the row
    ///   count (a blob written under a protocol this build can't read, e.g. a newer
    ///   iTerm2) -> splicing the survivors would send a HOLED conversation;
    /// - any blob's protocol is not `expectedProtocol` (a protocol switch that has
    ///   not been re-frozen) -> the frozen bytes are not replayable under the turn's
    ///   protocol;
    /// - a payload is corrupt.
    ///
    /// `expectedProtocol` is the protocol the current turn will be sent under; the
    /// blobs must match it to be spliceable.
    static func stitchedHistoryIfSafe(chatID: String,
                                      expectedProtocol: iTermAIAPI,
                                      database: ChatDatabase) -> [Any]? {
        let rowCount = database.blobCount(inChat: chatID)
        guard rowCount > 0 else {
            return nil  // legacy / blobless: caller reconstructs via the codec
        }
        let blobs = database.blobs(inChat: chatID)
        guard blobs.count == rowCount else {
            RLog("ChatBlobAssembler: chat \(chatID) has \(rowCount) blob rows but only \(blobs.count) decoded (unreadable protocol?); refusing blob replay to avoid a holed history")
            return nil
        }
        guard blobs.allSatisfy({ $0.blobProtocol == expectedProtocol }) else {
            RLog("ChatBlobAssembler: chat \(chatID) blobs are not all protocol \(expectedProtocol.rawValue); refusing blob replay (needs a re-freeze)")
            return nil
        }
        guard let stitched = try? stitch(blobs) else {
            RLog("ChatBlobAssembler: chat \(chatID) has a corrupt blob payload; refusing blob replay")
            return nil
        }
        return stitched
    }
}
