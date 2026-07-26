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
}
