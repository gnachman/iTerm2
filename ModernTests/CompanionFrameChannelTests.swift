//
//  CompanionFrameChannelTests.swift
//  iTerm2 ModernTests
//
//  The 1-byte channel tag multiplexes JSON control frames and binary media
//  frames over the one Noise/relay connection. These tests pin the tag values
//  (the Mac and iOS ends must agree) and prove framing round-trips and that
//  unknown/empty frames are rejected rather than misrouted.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionFrameChannelTests: XCTestCase {
    func testTagValuesAreStable() {
        // The wire contract: these must never change without a version bump.
        XCTAssertEqual(CompanionFrameChannel.control.rawValue, 0)
        XCTAssertEqual(CompanionFrameChannel.media.rawValue, 1)
    }

    func testControlRoundTrip() throws {
        let payload = Data([0x10, 0x20, 0x30])
        let framed = CompanionFrameChannel.control.frame(payload)
        XCTAssertEqual(framed.first, 0)
        let split = try XCTUnwrap(CompanionFrameChannel.split(framed))
        XCTAssertEqual(split.channel, .control)
        XCTAssertEqual(split.payload, payload)
    }

    func testMediaRoundTrip() throws {
        let payload = Data([0xAA, 0xBB])
        let framed = CompanionFrameChannel.media.frame(payload)
        XCTAssertEqual(framed.first, 1)
        let split = try XCTUnwrap(CompanionFrameChannel.split(framed))
        XCTAssertEqual(split.channel, .media)
        XCTAssertEqual(split.payload, payload)
    }

    func testEmptyPayloadFramesToTagOnly() throws {
        let framed = CompanionFrameChannel.media.frame(Data())
        XCTAssertEqual(framed, Data([1]))
        let split = try XCTUnwrap(CompanionFrameChannel.split(framed))
        XCTAssertEqual(split.channel, .media)
        XCTAssertEqual(split.payload, Data())
    }

    func testSplitEmptyFrameReturnsNil() {
        XCTAssertNil(CompanionFrameChannel.split(Data()))
    }

    func testSplitUnknownTagReturnsNil() {
        // A future build's channel tag must drop, not misroute.
        XCTAssertNil(CompanionFrameChannel.split(Data([7, 0x01, 0x02])))
    }

    func testSplitFromNonZeroBasedSlice() throws {
        // A sliced Data does not start at index 0; split must index from startIndex.
        var padded = Data([0xFF, 0xFF])
        padded.append(CompanionFrameChannel.media.frame(Data([0x09])))
        let slice = padded.suffix(from: padded.startIndex + 2)
        XCTAssertNotEqual(slice.startIndex, 0)
        let split = try XCTUnwrap(CompanionFrameChannel.split(slice))
        XCTAssertEqual(split.channel, .media)
        XCTAssertEqual(split.payload, Data([0x09]))
    }
}
