//
//  CompanionHEVCFraming.swift
//  iTerm2
//
//  Byte-level framing shared by the Mac HEVC encoder and the iOS decoder.
//
//  Two concerns:
//
//  1. Parameter sets (VPS/SPS/PPS). VideoToolbox carries these in the sample's
//     format description; we serialize them into one blob for
//     CompanionStreamConfig.codecExtradata, and the phone deserializes them back
//     into the array that CMVideoFormatDescriptionCreateFromHEVCParameterSets
//     wants. A simple length-prefixed container (not a real hvcC box) is enough
//     because both ends are ours.
//
//  2. Access units. VideoToolbox emits compressed samples in AVCC framing:
//     each NAL unit preceded by its length as a 4-byte big-endian integer. The
//     media payload carries the access unit in exactly this form; these helpers
//     build and split it (used for reconstruction on the phone and validation in
//     tests).
//

import Foundation

enum CompanionHEVCFraming {
    /// 4-byte big-endian NAL-unit length prefix, matching VideoToolbox's AVCC
    /// nalUnitHeaderLength.
    static let nalLengthSize = 4

    enum FramingError: Error, Equatable {
        case truncated
        case tooManyParameterSets
    }

    // MARK: Parameter sets

    /// Serialize parameter sets into one blob: a UInt16 count, then each set as a
    /// UInt32 length followed by its bytes (all big-endian).
    static func encodeParameterSets(_ sets: [Data]) -> Data {
        var data = Data()
        data.appendBigEndian(UInt16(truncatingIfNeeded: sets.count))
        for set in sets {
            data.appendBigEndian(UInt32(set.count))
            data.append(set)
        }
        return data
    }

    /// Inverse of `encodeParameterSets`. Throws `.truncated` if the buffer ends
    /// mid-record.
    static func decodeParameterSets(_ data: Data) throws -> [Data] {
        var cursor = data.startIndex
        func need(_ n: Int) throws {
            guard data.endIndex - cursor >= n else { throw FramingError.truncated }
        }
        try need(2)
        let count = Int(data.readBigEndianUInt16(at: cursor)); cursor += 2
        var sets = [Data]()
        sets.reserveCapacity(count)
        for _ in 0..<count {
            try need(4)
            let length = Int(data.readBigEndianUInt32(at: cursor)); cursor += 4
            try need(length)
            sets.append(data.subdata(in: cursor..<(cursor + length))); cursor += length
        }
        return sets
    }

    // MARK: Access units (AVCC)

    /// Build an AVCC access unit: each NAL unit prefixed with its 4-byte
    /// big-endian length.
    static func encodeAccessUnit(nalUnits: [Data]) -> Data {
        var data = Data()
        for nalu in nalUnits {
            data.appendBigEndian(UInt32(nalu.count))
            data.append(nalu)
        }
        return data
    }

    /// Split an AVCC access unit into its NAL units. Throws `.truncated` if a
    /// declared length overruns the buffer.
    static func decodeAccessUnit(_ data: Data) throws -> [Data] {
        var cursor = data.startIndex
        var nalUnits = [Data]()
        while cursor < data.endIndex {
            guard data.endIndex - cursor >= nalLengthSize else { throw FramingError.truncated }
            let length = Int(data.readBigEndianUInt32(at: cursor)); cursor += nalLengthSize
            guard data.endIndex - cursor >= length else { throw FramingError.truncated }
            nalUnits.append(data.subdata(in: cursor..<(cursor + length))); cursor += length
        }
        return nalUnits
    }
}

// Big-endian integer framing helpers live in Data+BigEndian.swift (shared).
