//
//  CompanionMediaFrame.swift
//  iTerm2
//
//  One frame on the Companion media channel: a fixed binary header followed by a
//  codec access unit (an HEVC sample in AVCC framing, or a parameter-set blob).
//  Media rides the same Noise/relay connection as the JSON control channel but
//  bypasses JSON entirely, so video bytes are not base64-inflated. The channel a
//  frame belongs to is decided one layer below this (see the channel tag in
//  NoiseChannel); this type only concerns the media frame's own bytes.
//
//  Wire layout (all multi-byte integers big-endian):
//
//      offset  size  field
//      0       1     version
//      1       1     flags
//      2       4     streamID
//      6       4     sequence
//      10      8     ptsMilliseconds
//      18      4     payloadLength
//      22      …     payload (payloadLength bytes)
//

import Foundation

struct CompanionMediaFrame: Equatable {
    /// The only wire version this build emits and accepts.
    static let version: UInt8 = 1
    /// Size in bytes of the fixed header preceding the payload.
    static let headerSize = 22

    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8
        init(rawValue: UInt8) { self.rawValue = rawValue }

        /// This access unit is a keyframe (IDR); it can be decoded without prior
        /// frames. A late joiner or a decoder that lost sync resumes here.
        static let keyframe = Flags(rawValue: 1 << 0)
        /// A fresh stream configuration (parameter sets / geometry) was sent on
        /// the control channel immediately before this frame; the decoder must
        /// be reconfigured before decoding it.
        static let configChanged = Flags(rawValue: 1 << 1)
        /// The stream is ending; no more frames will follow for this streamID.
        static let endOfStream = Flags(rawValue: 1 << 2)
    }

    /// Identifies which stream this frame belongs to (a session may have one
    /// active stream; the id lets the receiver ignore frames from a stream it has
    /// torn down).
    var streamID: UInt32
    /// Monotonically increasing per stream, so the receiver can detect gaps.
    var sequence: UInt32
    /// Presentation timestamp in milliseconds from the host's monotonic capture
    /// clock. Gaps are real elapsed time (the stream is variable-frame-rate).
    var ptsMilliseconds: UInt64
    var flags: Flags
    var payload: Data

    init(streamID: UInt32,
         sequence: UInt32,
         ptsMilliseconds: UInt64,
         flags: Flags,
         payload: Data) {
        self.streamID = streamID
        self.sequence = sequence
        self.ptsMilliseconds = ptsMilliseconds
        self.flags = flags
        self.payload = payload
    }
}

extension CompanionMediaFrame {
    enum DecodeError: Error, Equatable {
        /// Fewer bytes than a header, or fewer than header + declared payload.
        case truncated
        /// A version this build does not understand.
        case unsupportedVersion(UInt8)
        /// The declared payload length does not match the bytes that follow.
        case payloadLengthMismatch(declared: UInt32, actual: Int)
    }

    /// Serialize to the wire layout documented above.
    func encoded() -> Data {
        var data = Data(capacity: Self.headerSize + payload.count)
        data.append(Self.version)
        data.append(flags.rawValue)
        data.appendBigEndian(streamID)
        data.appendBigEndian(sequence)
        data.appendBigEndian(ptsMilliseconds)
        data.appendBigEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    /// Parse a frame from `data`, which must be exactly one frame (header plus its
    /// payload). Throws `DecodeError` on a short buffer, an unknown version, or a
    /// payload-length that disagrees with the trailing bytes.
    init(decoding data: Data) throws {
        guard data.count >= Self.headerSize else {
            throw DecodeError.truncated
        }
        // Index from the data's own startIndex: a Data slice need not be 0-based.
        let base = data.startIndex
        let version = data[base]
        guard version == Self.version else {
            throw DecodeError.unsupportedVersion(version)
        }
        let flags = Flags(rawValue: data[base + 1])
        let streamID = data.readBigEndianUInt32(at: base + 2)
        let sequence = data.readBigEndianUInt32(at: base + 6)
        let pts = data.readBigEndianUInt64(at: base + 10)
        let declaredLength = data.readBigEndianUInt32(at: base + 18)

        let payloadStart = base + Self.headerSize
        let actualLength = data.endIndex - payloadStart
        guard Int(declaredLength) == actualLength else {
            throw DecodeError.payloadLengthMismatch(declared: declaredLength,
                                                    actual: actualLength)
        }
        self.init(streamID: streamID,
                  sequence: sequence,
                  ptsMilliseconds: pts,
                  flags: flags,
                  payload: data.subdata(in: payloadStart..<data.endIndex))
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendBigEndian(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    func readBigEndianUInt32(at index: Index) -> UInt32 {
        var result: UInt32 = 0
        for offset in 0..<4 {
            result = (result << 8) | UInt32(self[index + offset])
        }
        return result
    }

    func readBigEndianUInt64(at index: Index) -> UInt64 {
        var result: UInt64 = 0
        for offset in 0..<8 {
            result = (result << 8) | UInt64(self[index + offset])
        }
        return result
    }
}
