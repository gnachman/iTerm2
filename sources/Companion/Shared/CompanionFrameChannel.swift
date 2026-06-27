//
//  CompanionFrameChannel.swift
//  iTerm2
//
//  The Companion connection multiplexes two logical channels over one
//  Noise/relay link by tagging every application frame with a single leading
//  byte: control frames carry a JSON CompanionEnvelope, media frames carry a
//  CompanionMediaFrame. The tag rides inside the encrypted Noise payload (it is
//  prepended before the frame is handed to the transport), so the relay never
//  sees it. Noise chunking is orthogonal: it reassembles a whole frame before
//  delivery, so the tag is always the first byte of the reassembled frame.
//
//  This type is the single source of truth for that framing, shared by the Mac
//  host and the iOS app so both ends agree on the wire format.
//

import Foundation

enum CompanionFrameChannel: UInt8 {
    /// A JSON-encoded CompanionEnvelope (the existing request/reply + event
    /// control channel).
    case control = 0
    /// A binary CompanionMediaFrame (live video). Never base64.
    case media = 1

    /// Prepend this channel's tag to `payload`, producing the application frame
    /// to hand to the transport.
    func frame(_ payload: Data) -> Data {
        var data = Data(capacity: payload.count + 1)
        data.append(rawValue)
        data.append(payload)
        return data
    }

    /// Split a received application frame into its channel and payload. Returns
    /// nil when the frame is empty or carries a tag this build does not know (a
    /// future build's channel), so the receiver drops it rather than misrouting.
    static func split(_ frame: Data) -> (channel: CompanionFrameChannel, payload: Data)? {
        guard let first = frame.first,
              let channel = CompanionFrameChannel(rawValue: first) else {
            return nil
        }
        let payloadStart = frame.startIndex + 1
        return (channel, frame.subdata(in: payloadStart..<frame.endIndex))
    }
}
