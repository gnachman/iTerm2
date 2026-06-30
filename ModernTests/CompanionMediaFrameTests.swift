//
//  CompanionMediaFrameTests.swift
//  iTerm2 ModernTests
//
//  The media-channel frame is a fixed binary header plus a codec access unit.
//  These tests pin the wire layout (so the Mac encoder and iOS decoder agree),
//  prove round-trip fidelity, and prove that malformed buffers are rejected
//  rather than silently mis-parsed.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionMediaFrameTests: XCTestCase {
    private func sample(payload: Data = Data([0xDE, 0xAD, 0xBE, 0xEF]),
                        flags: CompanionMediaFrame.Flags = .keyframe) -> CompanionMediaFrame {
        CompanionMediaFrame(streamID: 0x01020304,
                            sequence: 0x0A0B0C0D,
                            ptsMilliseconds: 0x0102_0304_0506_0708,
                            flags: flags,
                            payload: payload)
    }

    func testRoundTrip() throws {
        let frame = sample()
        let decoded = try CompanionMediaFrame(decoding: frame.encoded())
        XCTAssertEqual(decoded, frame)
    }

    func testRoundTripEmptyPayload() throws {
        let frame = sample(payload: Data(), flags: [])
        let encoded = frame.encoded()
        XCTAssertEqual(encoded.count, CompanionMediaFrame.headerSize)
        XCTAssertEqual(try CompanionMediaFrame(decoding: encoded), frame)
    }

    func testRoundTripCombinedFlags() throws {
        let frame = sample(flags: [.keyframe, .configChanged])
        let decoded = try CompanionMediaFrame(decoding: frame.encoded())
        XCTAssertEqual(decoded.flags, [.keyframe, .configChanged])
        XCTAssertEqual(decoded, frame)
    }

    func testWireLayoutVersion2IsBigEndian() throws {
        // Pin the v2 byte layout so an independent decoder (the iOS app) can rely
        // on it: version=2, flags, streamID, sequence, pts, generationId, liveTop,
        // payloadLen.
        let frame = CompanionMediaFrame(streamID: 0x01020304, sequence: 0x0A0B0C0D,
                                        ptsMilliseconds: 0x0102_0304_0506_0708,
                                        flags: .keyframe, payload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                                        generationId: 0x11223344, liveTop: 0x0506_0708_090A_0B0C)
        let bytes = [UInt8](frame.encoded())
        XCTAssertEqual(bytes[0], 2)                       // version
        XCTAssertEqual(bytes[1], 1)                       // flags: keyframe
        XCTAssertEqual(Array(bytes[2..<6]), [0x01, 0x02, 0x03, 0x04])      // streamID
        XCTAssertEqual(Array(bytes[6..<10]), [0x0A, 0x0B, 0x0C, 0x0D])     // sequence
        XCTAssertEqual(Array(bytes[10..<18]),
                       [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])   // pts
        XCTAssertEqual(Array(bytes[18..<22]), [0x11, 0x22, 0x33, 0x44])    // generationId
        XCTAssertEqual(Array(bytes[22..<30]),
                       [0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C])   // liveTop
        XCTAssertEqual(Array(bytes[30..<34]), [0x00, 0x00, 0x00, 0x04])    // payloadLen=4
    }

    func testGenerationAndLiveTopRoundTrip() throws {
        let frame = CompanionMediaFrame(streamID: 7, sequence: 3, ptsMilliseconds: 99,
                                        flags: [.keyframe, .configChanged],
                                        payload: Data([1, 2, 3]),
                                        generationId: 42, liveTop: 1_000_000)
        let decoded = try CompanionMediaFrame(decoding: frame.encoded())
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(decoded.generationId, 42)
        XCTAssertEqual(decoded.liveTop, 1_000_000)
    }

    func testLegacyVersion1RoundTripDropsGeometry() throws {
        // Emitting v1 (for an old peer) omits generationId/liveTop; they decode as
        // 0, but every other field survives, and the size is the v1 header.
        let frame = CompanionMediaFrame(streamID: 7, sequence: 3, ptsMilliseconds: 99,
                                        flags: .keyframe, payload: Data([1, 2, 3]),
                                        generationId: 42, liveTop: 5)
        let encoded = frame.encoded(version: CompanionMediaFrame.legacyVersion)
        XCTAssertEqual(encoded.count, CompanionMediaFrame.headerSizeV1 + 3)
        XCTAssertEqual(encoded[encoded.startIndex], 1)  // version byte
        let decoded = try CompanionMediaFrame(decoding: encoded)
        XCTAssertEqual(decoded.streamID, 7)
        XCTAssertEqual(decoded.payload, Data([1, 2, 3]))
        XCTAssertEqual(decoded.generationId, 0, "v1 carries no generation")
        XCTAssertEqual(decoded.liveTop, 0, "v1 carries no liveTop")
    }

    func testDecodeFromNonZeroBasedSlice() throws {
        // A Data produced by slicing does not start at index 0; the decoder must
        // index from startIndex, not 0.
        let encoded = sample().encoded()
        var padded = Data([0xFF, 0xFF, 0xFF])
        padded.append(encoded)
        let slice = padded.suffix(from: padded.startIndex + 3)
        XCTAssertNotEqual(slice.startIndex, 0)
        XCTAssertEqual(try CompanionMediaFrame(decoding: slice), sample())
    }

    func testTruncatedHeaderThrows() {
        let short = Data([1, 0, 0, 0])  // shorter than headerSize
        XCTAssertThrowsError(try CompanionMediaFrame(decoding: short)) { error in
            XCTAssertEqual(error as? CompanionMediaFrame.DecodeError, .truncated)
        }
    }

    func testUnsupportedVersionThrows() {
        var encoded = sample().encoded()
        encoded[encoded.startIndex] = 99  // bogus version
        XCTAssertThrowsError(try CompanionMediaFrame(decoding: encoded)) { error in
            XCTAssertEqual(error as? CompanionMediaFrame.DecodeError, .unsupportedVersion(99))
        }
    }

    func testPayloadLongerThanDeclaredThrows() {
        var encoded = sample().encoded()
        encoded.append(0x00)  // one extra trailing byte: actual > declared
        XCTAssertThrowsError(try CompanionMediaFrame(decoding: encoded)) { error in
            XCTAssertEqual(error as? CompanionMediaFrame.DecodeError,
                           .payloadLengthMismatch(declared: 4, actual: 5))
        }
    }

    func testPayloadShorterThanDeclaredThrows() {
        let encoded = sample().encoded().dropLast()  // actual < declared
        XCTAssertThrowsError(try CompanionMediaFrame(decoding: encoded)) { error in
            XCTAssertEqual(error as? CompanionMediaFrame.DecodeError,
                           .payloadLengthMismatch(declared: 4, actual: 3))
        }
    }
}
