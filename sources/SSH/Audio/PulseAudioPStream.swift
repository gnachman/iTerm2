//
//  PulseAudioPStream.swift
//  iTerm2SharedARC
//
//  Incremental reassembler and serializer for PulseAudio's 20-byte big-endian
//  `pstream` wire framing (`src/pulsecore/pstream.c`), used by in-process SSH
//  audio (`Conductor+Audio.swift`) with SHM=0 and MEMFD=0.
//

import Foundation

enum PulsePStreamError: Error, Equatable {
    case frameTooLarge(UInt32)
    case unexpectedSHMFrame(UInt32)
}

struct PulsePStreamFrame: Equatable {
    static let descriptorSize = 20
    static let controlChannel: UInt32 = 0xFFFF_FFFF
    static let maxPayloadLength: UInt32 = 4 * 1024 * 1024
    static let shmFlagMask: UInt32 = 0xFF00_0000

    let channel: UInt32
    let offset: Int64
    let flags: UInt32
    let payload: Data

    var isControlPacket: Bool {
        channel == Self.controlChannel
    }

    func encode() -> Data {
        var out = Data(capacity: Self.descriptorSize + payload.count)
        Self.appendUInt32BE(&out, UInt32(payload.count))
        Self.appendUInt32BE(&out, channel)
        let uoff = UInt64(bitPattern: offset)
        Self.appendUInt32BE(&out, UInt32(truncatingIfNeeded: uoff >> 32))
        Self.appendUInt32BE(&out, UInt32(truncatingIfNeeded: uoff))
        Self.appendUInt32BE(&out, flags)
        out.append(payload)
        return out
    }

    static func controlPacket(_ payload: Data) -> PulsePStreamFrame {
        PulsePStreamFrame(channel: controlChannel, offset: 0, flags: 0, payload: payload)
    }

    static func audioBlock(channel: UInt32, payload: Data, offset: Int64 = 0, flags: UInt32 = 0) -> PulsePStreamFrame {
        PulsePStreamFrame(channel: channel, offset: offset, flags: flags, payload: payload)
    }

    private static func appendUInt32BE(_ data: inout Data, _ value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
}

/// Incremental byte-stream decoder for `PulsePStreamFrame` packets arriving across arbitrary
/// `%pulse <connid> data <base64>` chunks.
final class PulsePStreamReader {
    private var buffer = Data()
    private var readOffset = 0
    private let maxPayloadLength: UInt32

    init(maxPayloadLength: UInt32 = PulsePStreamFrame.maxPayloadLength) {
        self.maxPayloadLength = maxPayloadLength
    }

    var bufferedByteCount: Int {
        buffer.count - readOffset
    }

    func reset() {
        buffer.removeAll(keepingCapacity: false)
        readOffset = 0
    }

    func feed(_ data: Data) throws -> [PulsePStreamFrame] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var frames: [PulsePStreamFrame] = []
        while buffer.count - readOffset >= PulsePStreamFrame.descriptorSize {
            let length = readUInt32BE(at: readOffset)
            let channel = readUInt32BE(at: readOffset + 4)
            let offsetHi = readUInt32BE(at: readOffset + 8)
            let offsetLo = readUInt32BE(at: readOffset + 12)
            let flags = readUInt32BE(at: readOffset + 16)

            if (flags & PulsePStreamFrame.shmFlagMask) != 0 {
                reset()
                throw PulsePStreamError.unexpectedSHMFrame(flags)
            }
            if length > maxPayloadLength {
                reset()
                throw PulsePStreamError.frameTooLarge(length)
            }

            let totalNeeded = PulsePStreamFrame.descriptorSize + Int(length)
            guard buffer.count - readOffset >= totalNeeded else {
                break
            }

            let payloadStart = readOffset + PulsePStreamFrame.descriptorSize
            let payloadEnd = payloadStart + Int(length)
            let payload = Data(buffer[payloadStart..<payloadEnd])
            let combinedOffset = Int64(bitPattern: (UInt64(offsetHi) << 32) | UInt64(offsetLo))
            frames.append(PulsePStreamFrame(channel: channel,
                                            offset: combinedOffset,
                                            flags: flags,
                                            payload: payload))
            readOffset = payloadEnd
        }

        if readOffset > 0 {
            if readOffset == buffer.count {
                buffer.removeAll(keepingCapacity: true)
                readOffset = 0
            } else if readOffset >= 16384 {
                buffer.removeSubrange(0..<readOffset)
                readOffset = 0
            }
        }
        return frames
    }

    private func readUInt32BE(at index: Int) -> UInt32 {
        let b0 = UInt32(buffer[index]) << 24
        let b1 = UInt32(buffer[index + 1]) << 16
        let b2 = UInt32(buffer[index + 2]) << 8
        let b3 = UInt32(buffer[index + 3])
        return b0 | b1 | b2 | b3
    }
}
