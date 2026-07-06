//
//  CompanionFrameChannel.swift
//  iTerm2
//
//  The Companion connection multiplexes a JSON control channel and a binary
//  media channel (live video) over the one Noise/relay link, in a
//  backward-compatible way.
//
//  Control frames are sent verbatim as JSON, exactly as they always were: a JSON
//  object never begins with the media marker byte, so a peer that predates the
//  media channel still exchanges control frames byte-for-byte and the version
//  handshake (the very first frame) keeps working across app versions. Media
//  frames are distinguished by a single leading marker byte and only ever flow
//  to a peer that asked to start a stream, so an older peer never sees one.
//
//  The marker rides inside the encrypted Noise payload, so the relay never sees
//  it. Noise chunking is orthogonal: it reassembles a whole frame before
//  delivery, so the marker is always the first byte of the reassembled frame.
//
//  This type is the single source of truth for that framing, shared by the Mac
//  host and the iOS app.
//

import Foundation

enum CompanionFrameChannel {
    /// A byte no JSON document can begin with. A serialized CompanionEnvelope is
    /// a JSON object, so it starts with `{` (0x7B); JSON may also begin with
    /// `[`, `"`, a digit, `-`, `t`/`f`/`n`, or whitespace (0x20/0x09/0x0A/0x0D),
    /// but never 0x01. Marking media with 0x01 is therefore unambiguous.
    static let mediaMarker: UInt8 = 0x01

    /// A received application frame, classified by channel.
    enum Inbound: Equatable {
        /// Bare JSON envelope bytes (the control channel).
        case control(Data)
        /// A media payload with the marker stripped (a CompanionMediaFrame's
        /// encoded bytes).
        case media(Data)
    }

    /// Wrap a media payload for the transport by prepending the marker byte.
    static func frameMedia(_ payload: Data) -> Data {
        var data = Data(capacity: payload.count + 1)
        data.append(mediaMarker)
        data.append(payload)
        return data
    }

    /// Classify a received application frame. Control frames are returned
    /// verbatim (no wrapping was applied when sending); media frames have the
    /// marker stripped. Returns nil for an empty frame (nothing to route).
    static func classify(_ frame: Data) -> Inbound? {
        guard let first = frame.first else { return nil }
        guard first == mediaMarker else {
            return .control(frame)
        }
        let payloadStart = frame.startIndex + 1
        return .media(frame.subdata(in: payloadStart..<frame.endIndex))
    }
}
