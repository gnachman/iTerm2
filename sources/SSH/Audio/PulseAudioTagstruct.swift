//
//  PulseAudioTagstruct.swift
//  iTerm2SharedARC
//
//  Memory-safe encoder and decoder for PulseAudio's binary `tagstruct` format
//  (`src/pulsecore/tagstruct.h`, `tagstruct.c`), supporting protocol v35.
//

import Foundation

enum PulseTag: UInt8 {
    case invalid = 0
    case string = 0x74        // 't'
    case stringNull = 0x4E    // 'N'
    case u32 = 0x4C           // 'L'
    case u8 = 0x42            // 'B'
    case u64 = 0x52           // 'R'
    case s64 = 0x72           // 'r'
    case sampleSpec = 0x61    // 'a'
    case arbitrary = 0x78     // 'x'
    case booleanTrue = 0x31   // '1'
    case booleanFalse = 0x30  // '0'
    case timeval = 0x54       // 'T'
    case usec = 0x55          // 'U'
    case channelMap = 0x6D    // 'm'
    case cvolume = 0x76       // 'v'
    case proplist = 0x50      // 'P'
    case volume = 0x56        // 'V'
    case formatInfo = 0x66    // 'f'
}

enum PulseTagstructError: Error, Equatable {
    case unexpectedEOF
    case unexpectedTag(expected: UInt8, actual: UInt8)
    case unterminatedString
    case invalidUTF8
    case lengthMismatch(expected: UInt32, actual: UInt32)
    case valueOutOfBounds(String)
}

enum PulseSampleFormat: UInt8, Equatable {
    case u8 = 0
    case alaw = 1
    case ulaw = 2
    case s16le = 3
    case s16be = 4
    case float32le = 5
    case float32be = 6
    case s32le = 7
    case s32be = 8
    case s24le = 9
    case s24be = 10
    case s24_32le = 11
    case s24_32be = 12

    var bytesPerSample: Int {
        switch self {
        case .u8, .alaw, .ulaw:
            return 1
        case .s16le, .s16be:
            return 2
        case .s24le, .s24be:
            return 3
        case .float32le, .float32be, .s32le, .s32be, .s24_32le, .s24_32be:
            return 4
        }
    }
}

struct PulseSampleSpec: Equatable {
    static let maxChannels: UInt8 = 32
    static let maxRate: UInt32 = 384_000

    var format: UInt8
    var channels: UInt8
    var rate: UInt32

    var parsedFormat: PulseSampleFormat? {
        PulseSampleFormat(rawValue: format)
    }

    var frameSize: Int {
        guard let fmt = parsedFormat, channels > 0 else { return 0 }
        return fmt.bytesPerSample * Int(channels)
    }

    var isValid: Bool {
        parsedFormat != nil && channels >= 1 && channels <= Self.maxChannels && rate >= 1 && rate <= Self.maxRate
    }

    func bytesToUsec(_ byteCount: Int) -> UInt64 {
        let fsize = frameSize
        guard fsize > 0, rate > 0, byteCount > 0 else { return 0 }
        let frames = UInt64(byteCount / fsize)
        return (frames * 1_000_000) / UInt64(rate)
    }

    static let defaultPlayback = PulseSampleSpec(format: PulseSampleFormat.s16le.rawValue, channels: 2, rate: 48_000)
    static let defaultCapture = PulseSampleSpec(format: PulseSampleFormat.s16le.rawValue, channels: 1, rate: 48_000)
}

struct PulseChannelMap: Equatable {
    var positions: [UInt8]

    var channels: UInt8 {
        UInt8(clamping: positions.count)
    }

    static func defaultMap(channels: UInt8) -> PulseChannelMap {
        switch channels {
        case 0:
            return PulseChannelMap(positions: [])
        case 1:
            return PulseChannelMap(positions: [0]) // PA_CHANNEL_POSITION_MONO
        case 2:
            return PulseChannelMap(positions: [1, 2]) // FRONT_LEFT, FRONT_RIGHT
        default:
            return PulseChannelMap(positions: (0..<channels).map { 12 + $0 }) // AUX0..AUXn
        }
    }
}

struct PulseCVolume: Equatable {
    static let norm: UInt32 = 0x0001_0000 // PA_VOLUME_NORM (65536)
    static let muted: UInt32 = 0

    var values: [UInt32]

    static func norm(channels: UInt8) -> PulseCVolume {
        PulseCVolume(values: Array(repeating: norm, count: Int(channels)))
    }
}

struct PulseTimeval: Equatable {
    var tvSec: UInt32
    var tvUsec: UInt32

    static let zero = PulseTimeval(tvSec: 0, tvUsec: 0)

    static func now() -> PulseTimeval {
        let interval = Date().timeIntervalSince1970
        let sec = UInt32(clamping: Int64(interval))
        let usec = UInt32(clamping: Int64((interval - Double(sec)) * 1_000_000))
        return PulseTimeval(tvSec: sec, tvUsec: usec)
    }
}

struct PulseProplist: Equatable {
    var entries: [String: Data]

    init(entries: [String: Data] = [:]) {
        self.entries = entries
    }

    init(strings: [String: String]) {
        var map: [String: Data] = [:]
        for (k, v) in strings {
            var d = Data(v.utf8)
            d.append(0)
            map[k] = d
        }
        self.entries = map
    }

    func string(forKey key: String) -> String? {
        guard let raw = entries[key] else { return nil }
        if let nulIndex = raw.firstIndex(of: 0) {
            return String(data: raw[raw.startIndex..<nulIndex], encoding: .utf8)
        }
        return String(data: raw, encoding: .utf8)
    }
}

struct PulseFormatInfo: Equatable {
    static let encodingPCM: UInt8 = 1

    var encoding: UInt8
    var proplist: PulseProplist

    static let defaultPCM = PulseFormatInfo(encoding: encodingPCM, proplist: PulseProplist())
}

struct PulseTagstructWriter {
    private(set) var data = Data()

    init(capacity: Int = 128) {
        data.reserveCapacity(capacity)
    }

    mutating func putString(_ value: String?) {
        guard let value else {
            data.append(PulseTag.stringNull.rawValue)
            return
        }
        data.append(PulseTag.string.rawValue)
        data.append(contentsOf: value.utf8)
        data.append(0)
    }

    mutating func putU32(_ value: UInt32) {
        data.append(PulseTag.u32.rawValue)
        appendRawU32(value)
    }

    mutating func putU8(_ value: UInt8) {
        data.append(PulseTag.u8.rawValue)
        data.append(value)
    }

    mutating func putU64(_ value: UInt64) {
        data.append(PulseTag.u64.rawValue)
        appendRawU64(value)
    }

    mutating func putS64(_ value: Int64) {
        data.append(PulseTag.s64.rawValue)
        appendRawU64(UInt64(bitPattern: value))
    }

    mutating func putBoolean(_ value: Bool) {
        data.append((value ? PulseTag.booleanTrue : PulseTag.booleanFalse).rawValue)
    }

    mutating func putArbitrary(_ bytes: Data) {
        data.append(PulseTag.arbitrary.rawValue)
        appendRawU32(UInt32(bytes.count))
        data.append(bytes)
    }

    mutating func putSampleSpec(_ spec: PulseSampleSpec) {
        data.append(PulseTag.sampleSpec.rawValue)
        data.append(spec.format)
        data.append(spec.channels)
        appendRawU32(spec.rate)
    }

    mutating func putTimeval(_ tv: PulseTimeval) {
        data.append(PulseTag.timeval.rawValue)
        appendRawU32(tv.tvSec)
        appendRawU32(tv.tvUsec)
    }

    mutating func putUsec(_ usec: UInt64) {
        data.append(PulseTag.usec.rawValue)
        appendRawU64(usec)
    }

    mutating func putChannelMap(_ map: PulseChannelMap) {
        data.append(PulseTag.channelMap.rawValue)
        let count = UInt8(clamping: map.positions.count)
        data.append(count)
        data.append(contentsOf: map.positions.prefix(Int(count)))
    }

    mutating func putCVolume(_ cvolume: PulseCVolume) {
        data.append(PulseTag.cvolume.rawValue)
        let count = UInt8(clamping: cvolume.values.count)
        data.append(count)
        for val in cvolume.values.prefix(Int(count)) {
            appendRawU32(val)
        }
    }

    mutating func putVolume(_ volume: UInt32) {
        data.append(PulseTag.volume.rawValue)
        appendRawU32(volume)
    }

    mutating func putProplist(_ proplist: PulseProplist) {
        data.append(PulseTag.proplist.rawValue)
        for key in proplist.entries.keys.sorted() {
            guard let val = proplist.entries[key] else { continue }
            putString(key)
            putU32(UInt32(val.count))
            putArbitrary(val)
        }
        putString(nil)
    }

    mutating func putFormatInfo(_ info: PulseFormatInfo) {
        data.append(PulseTag.formatInfo.rawValue)
        putU8(info.encoding)
        putProplist(info.proplist)
    }

    private mutating func appendRawU32(_ value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private mutating func appendRawU64(_ value: UInt64) {
        appendRawU32(UInt32(truncatingIfNeeded: value >> 32))
        appendRawU32(UInt32(truncatingIfNeeded: value))
    }
}

struct PulseTagstructReader {
    static let maxTagSize: UInt32 = 64 * 1024

    private let bytes: [UInt8]
    private(set) var index: Int = 0

    init(data: Data) {
        self.bytes = [UInt8](data)
    }

    var isAtEnd: Bool {
        index >= bytes.count
    }

    func peekTag() -> UInt8? {
        guard index < bytes.count else { return nil }
        return bytes[index]
    }

    mutating func getString() throws -> String? {
        guard index < bytes.count else {
            throw PulseTagstructError.unexpectedEOF
        }
        let tag = bytes[index]
        if tag == PulseTag.stringNull.rawValue {
            index += 1
            return nil
        }
        guard tag == PulseTag.string.rawValue else {
            throw PulseTagstructError.unexpectedTag(expected: PulseTag.string.rawValue, actual: tag)
        }
        index += 1
        guard let nulPos = bytes[index..<bytes.count].firstIndex(of: 0) else {
            throw PulseTagstructError.unterminatedString
        }
        let slice = bytes[index..<nulPos]
        index = nulPos + 1
        guard let str = String(bytes: slice, encoding: .utf8) else {
            throw PulseTagstructError.invalidUTF8
        }
        return str
    }

    mutating func getU32() throws -> UInt32 {
        try expectTag(.u32)
        return try readRawU32()
    }

    mutating func getU8() throws -> UInt8 {
        try expectTag(.u8)
        return try readRawU8()
    }

    mutating func getU64() throws -> UInt64 {
        try expectTag(.u64)
        return try readRawU64()
    }

    mutating func getS64() throws -> Int64 {
        try expectTag(.s64)
        return Int64(bitPattern: try readRawU64())
    }

    mutating func getBoolean() throws -> Bool {
        guard index < bytes.count else {
            throw PulseTagstructError.unexpectedEOF
        }
        let tag = bytes[index]
        if tag == PulseTag.booleanTrue.rawValue {
            index += 1
            return true
        }
        if tag == PulseTag.booleanFalse.rawValue {
            index += 1
            return false
        }
        throw PulseTagstructError.unexpectedTag(expected: PulseTag.booleanTrue.rawValue, actual: tag)
    }

    mutating func getArbitrary(expectedLength: UInt32? = nil) throws -> Data {
        try expectTag(.arbitrary)
        let len = try readRawU32()
        if let expectedLength, len != expectedLength {
            throw PulseTagstructError.lengthMismatch(expected: expectedLength, actual: len)
        }
        guard len <= Self.maxTagSize else {
            throw PulseTagstructError.valueOutOfBounds("arbitrary length \(len)")
        }
        return try readRawBytes(Int(len))
    }

    mutating func getSampleSpec() throws -> PulseSampleSpec {
        try expectTag(.sampleSpec)
        let format = try readRawU8()
        let channels = try readRawU8()
        let rate = try readRawU32()
        guard channels <= PulseSampleSpec.maxChannels else {
            throw PulseTagstructError.valueOutOfBounds("sample_spec channels \(channels)")
        }
        return PulseSampleSpec(format: format, channels: channels, rate: rate)
    }

    mutating func getTimeval() throws -> PulseTimeval {
        try expectTag(.timeval)
        let sec = try readRawU32()
        let usec = try readRawU32()
        return PulseTimeval(tvSec: sec, tvUsec: usec)
    }

    mutating func getUsec() throws -> UInt64 {
        try expectTag(.usec)
        return try readRawU64()
    }

    mutating func getChannelMap() throws -> PulseChannelMap {
        try expectTag(.channelMap)
        let channels = try readRawU8()
        guard channels <= PulseSampleSpec.maxChannels else {
            throw PulseTagstructError.valueOutOfBounds("channel_map channels \(channels)")
        }
        var positions: [UInt8] = []
        positions.reserveCapacity(Int(channels))
        for _ in 0..<channels {
            positions.append(try readRawU8())
        }
        return PulseChannelMap(positions: positions)
    }

    mutating func getCVolume() throws -> PulseCVolume {
        try expectTag(.cvolume)
        let channels = try readRawU8()
        guard channels <= PulseSampleSpec.maxChannels else {
            throw PulseTagstructError.valueOutOfBounds("cvolume channels \(channels)")
        }
        var values: [UInt32] = []
        values.reserveCapacity(Int(channels))
        for _ in 0..<channels {
            values.append(try readRawU32())
        }
        return PulseCVolume(values: values)
    }

    mutating func getVolume() throws -> UInt32 {
        try expectTag(.volume)
        return try readRawU32()
    }

    mutating func getProplist() throws -> PulseProplist {
        try expectTag(.proplist)
        var entries: [String: Data] = [:]
        while true {
            guard let key = try getString() else {
                break
            }
            guard !key.isEmpty else {
                throw PulseTagstructError.valueOutOfBounds("empty proplist key")
            }
            let len = try getU32()
            guard len <= Self.maxTagSize else {
                throw PulseTagstructError.valueOutOfBounds("proplist value length \(len)")
            }
            let val = try getArbitrary(expectedLength: len)
            entries[key] = val
        }
        return PulseProplist(entries: entries)
    }

    mutating func getFormatInfo() throws -> PulseFormatInfo {
        try expectTag(.formatInfo)
        let encoding = try getU8()
        let proplist = try getProplist()
        return PulseFormatInfo(encoding: encoding, proplist: proplist)
    }

    private mutating func expectTag(_ expected: PulseTag) throws {
        guard index < bytes.count else {
            throw PulseTagstructError.unexpectedEOF
        }
        let actual = bytes[index]
        guard actual == expected.rawValue else {
            throw PulseTagstructError.unexpectedTag(expected: expected.rawValue, actual: actual)
        }
        index += 1
    }

    private mutating func readRawU8() throws -> UInt8 {
        guard index < bytes.count else {
            throw PulseTagstructError.unexpectedEOF
        }
        defer { index += 1 }
        return bytes[index]
    }

    private mutating func readRawU32() throws -> UInt32 {
        guard index + 4 <= bytes.count else {
            throw PulseTagstructError.unexpectedEOF
        }
        let b0 = UInt32(bytes[index]) << 24
        let b1 = UInt32(bytes[index + 1]) << 16
        let b2 = UInt32(bytes[index + 2]) << 8
        let b3 = UInt32(bytes[index + 3])
        index += 4
        return b0 | b1 | b2 | b3
    }

    private mutating func readRawU64() throws -> UInt64 {
        let hi = UInt64(try readRawU32())
        let lo = UInt64(try readRawU32())
        return (hi << 32) | lo
    }

    private mutating func readRawBytes(_ count: Int) throws -> Data {
        guard count >= 0, index + count <= bytes.count else {
            throw PulseTagstructError.unexpectedEOF
        }
        let sub = Data(bytes[index..<(index + count)])
        index += count
        return sub
    }
}
