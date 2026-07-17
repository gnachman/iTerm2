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
//  Wire layout (all multi-byte integers big-endian). Version 2 added generationId
//  and liveTop; version 1 omits both (offsets shift):
//
//      offset            size  field
//      0                 1     version
//      1                 1     flags
//      2                 4     streamID
//      6                 4     sequence
//      10                8     ptsMilliseconds
//      [v2 only] 18      4     generationId
//      [v2 only] 22      8     liveTop (signed)
//      18 (v1) / 30 (v2) 4     payloadLength
//      22 (v1) / 34 (v2) …     payload (payloadLength bytes)
//
//  generationId tells the phone which streamConfig geometry a frame was rendered
//  under (the control-priority outbox can deliver a new config ahead of leftover
//  older frames, so the frame must self-identify). liveTop is the absolute line
//  number of the top visible row at this frame; it changes every scroll, so it
//  rides the per-frame header rather than the config.
//

import Foundation

struct CompanionMediaFrame: Equatable {
    /// The current wire version this build emits (when the peer supports it).
    static let version: UInt8 = 2
    /// The pre-geometry version, still accepted on decode and emitted to a peer
    /// that does not advertise version-2 support.
    static let legacyVersion: UInt8 = 1
    /// Header size for each version.
    static let headerSizeV1 = 22
    static let headerSizeV2 = 34
    /// Size of the header this build emits by default (version 2).
    static let headerSize = headerSizeV2

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
    /// The streamConfig generation this frame was rendered under (0 for a v1
    /// frame, which carries no generation).
    var generationId: UInt32
    /// Absolute line number of the top visible row at this frame (0 for v1).
    var liveTop: Int64
    var payload: Data

    init(streamID: UInt32,
         sequence: UInt32,
         ptsMilliseconds: UInt64,
         flags: Flags,
         payload: Data,
         generationId: UInt32 = 0,
         liveTop: Int64 = 0) {
        self.streamID = streamID
        self.sequence = sequence
        self.ptsMilliseconds = ptsMilliseconds
        self.flags = flags
        self.generationId = generationId
        self.liveTop = liveTop
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

    /// Serialize to the wire layout for `version` (defaults to the current
    /// version). Emit `legacyVersion` to a peer that does not understand version 2;
    /// generationId/liveTop are simply omitted there.
    func encoded(version: UInt8 = CompanionMediaFrame.version) -> Data {
        let headerSize = version >= Self.version ? Self.headerSizeV2 : Self.headerSizeV1
        var data = Data(capacity: headerSize + payload.count)
        data.append(version)
        data.append(flags.rawValue)
        data.appendBigEndian(streamID)
        data.appendBigEndian(sequence)
        data.appendBigEndian(ptsMilliseconds)
        if version >= Self.version {
            data.appendBigEndian(generationId)
            data.appendBigEndian(UInt64(bitPattern: liveTop))
        }
        data.appendBigEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    /// Parse a frame from `data`, which must be exactly one frame (header plus its
    /// payload). Throws `DecodeError` on a short buffer, an unknown version, or a
    /// payload-length that disagrees with the trailing bytes. Both version 1 (no
    /// generation/liveTop) and version 2 are accepted.
    init(decoding data: Data) throws {
        // Index from the data's own startIndex: a Data slice need not be 0-based.
        let base = data.startIndex
        guard data.count >= 2 else { throw DecodeError.truncated }
        let version = data[base]
        let headerSize: Int
        switch version {
        case Self.legacyVersion: headerSize = Self.headerSizeV1
        case Self.version: headerSize = Self.headerSizeV2
        default: throw DecodeError.unsupportedVersion(version)
        }
        guard data.count >= headerSize else {
            throw DecodeError.truncated
        }
        let flags = Flags(rawValue: data[base + 1])
        let streamID = data.readBigEndianUInt32(at: base + 2)
        let sequence = data.readBigEndianUInt32(at: base + 6)
        let pts = data.readBigEndianUInt64(at: base + 10)
        var generationId: UInt32 = 0
        var liveTop: Int64 = 0
        var cursor = base + 18
        if version >= Self.version {
            generationId = data.readBigEndianUInt32(at: cursor)
            liveTop = Int64(bitPattern: data.readBigEndianUInt64(at: cursor + 4))
            cursor += 12
        }
        let declaredLength = data.readBigEndianUInt32(at: cursor)

        let payloadStart = base + headerSize
        let actualLength = data.endIndex - payloadStart
        guard Int(declaredLength) == actualLength else {
            throw DecodeError.payloadLengthMismatch(declared: declaredLength,
                                                    actual: actualLength)
        }
        self.init(streamID: streamID,
                  sequence: sequence,
                  ptsMilliseconds: pts,
                  flags: flags,
                  payload: data.subdata(in: payloadStart..<data.endIndex),
                  generationId: generationId,
                  liveTop: liveTop)
    }
}

// Big-endian integer framing helpers live in Data+BigEndian.swift (shared).
