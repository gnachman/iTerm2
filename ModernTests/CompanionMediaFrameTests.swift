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

    func testWireLayoutIsBigEndian() throws {
        // Pin the byte layout so an independent decoder (the iOS app) can rely on
        // it. version=1, flags=keyframe(1), streamID, sequence, pts, payloadLen.
        let bytes = [UInt8](sample().encoded())
        XCTAssertEqual(bytes[0], 1)                       // version
        XCTAssertEqual(bytes[1], 1)                       // flags: keyframe
        XCTAssertEqual(Array(bytes[2..<6]), [0x01, 0x02, 0x03, 0x04])      // streamID
        XCTAssertEqual(Array(bytes[6..<10]), [0x0A, 0x0B, 0x0C, 0x0D])     // sequence
        XCTAssertEqual(Array(bytes[10..<18]),
                       [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])   // pts
        XCTAssertEqual(Array(bytes[18..<22]), [0x00, 0x00, 0x00, 0x04])    // payloadLen=4
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
