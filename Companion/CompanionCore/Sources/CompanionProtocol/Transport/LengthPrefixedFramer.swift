//
//  LengthPrefixedFramer.swift
//  CompanionCore
//
//  A small helper for transports that ride a raw byte stream (e.g. TCP). It
//  turns a stream of bytes into discrete frames using a 4-byte big-endian
//  length prefix. Transports that already deliver discrete datagrams (e.g. a
//  CloudKit record per message) do not need this.
//

import Foundation

public struct LengthPrefixedFramer {
    /// Frames larger than this are rejected. Generous relative to a Noise
    /// transport message (which is itself capped at 65535 bytes); the
    /// application layer is responsible for chunking anything bigger.
    public static let defaultMaximumFrameSize = 16 * 1024 * 1024

    public let maximumFrameSize: Int
    private var buffer = Data()

    public init(maximumFrameSize: Int = LengthPrefixedFramer.defaultMaximumFrameSize) {
        self.maximumFrameSize = maximumFrameSize
    }

    /// Encode one frame for the wire: a 4-byte big-endian length followed by
    /// the payload.
    public static func encode(_ frame: Data) -> Data {
        var out = Data(capacity: frame.count + 4)
        var length = UInt32(frame.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(frame)
        return out
    }

    /// Feed freshly received bytes and pull out any complete frames. Remaining
    /// partial bytes are retained for the next call. Throws on an oversized
    /// frame.
    public mutating func push(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var frames = [Data]()
        while true {
            guard buffer.count >= 4 else { break }
            let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            if Int(length) > maximumFrameSize {
                throw TransportError.frameTooLarge(size: Int(length),
                                                   maximum: maximumFrameSize)
            }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            let frame = buffer.subdata(in: 4..<total)
            frames.append(frame)
            buffer.removeSubrange(0..<total)
        }
        return frames
    }
}
