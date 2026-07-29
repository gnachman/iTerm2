//
//  CompanionFrameChannelTests.swift
//  iTerm2 ModernTests
//
//  The media channel is multiplexed with the JSON control channel in a
//  backward-compatible way: control frames are bare JSON, media frames carry a
//  leading marker byte that JSON can never start with. These tests pin the
//  marker value (the Mac and iOS ends must agree), prove framing round-trips,
//  and prove the critical invariant that a real control envelope is never
//  misclassified as media.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionFrameChannelTests: XCTestCase {
    func testMarkerValueIsStable() {
        // Wire contract: must never change without a protocol bump.
        XCTAssertEqual(CompanionFrameChannel.mediaMarker, 0x01)
    }

    func testFrameMediaPrependsMarker() {
        let framed = CompanionFrameChannel.frameMedia(Data([0xAA, 0xBB]))
        XCTAssertEqual(framed, Data([0x01, 0xAA, 0xBB]))
    }

    func testClassifyMediaStripsMarker() throws {
        let framed = CompanionFrameChannel.frameMedia(Data([0xAA, 0xBB]))
        XCTAssertEqual(CompanionFrameChannel.classify(framed), .media(Data([0xAA, 0xBB])))
    }

    func testClassifyMediaEmptyPayload() {
        let framed = CompanionFrameChannel.frameMedia(Data())
        XCTAssertEqual(framed, Data([0x01]))
        XCTAssertEqual(CompanionFrameChannel.classify(framed), .media(Data()))
    }

    func testClassifyControlReturnsBytesVerbatim() {
        // Anything not starting with the marker is control, returned unchanged.
        let json = Data(#"{"requestID":1}"#.utf8)
        XCTAssertEqual(CompanionFrameChannel.classify(json), .control(json))
    }

    func testClassifyEmptyFrameReturnsNil() {
        XCTAssertNil(CompanionFrameChannel.classify(Data()))
    }

    func testClassifyMediaFromNonZeroBasedSlice() {
        // A sliced Data does not start at index 0; classify must index from
        // startIndex.
        var padded = Data([0xFF, 0xFF])
        padded.append(CompanionFrameChannel.frameMedia(Data([0x09])))
        let slice = padded.suffix(from: padded.startIndex + 2)
        XCTAssertNotEqual(slice.startIndex, 0)
        XCTAssertEqual(CompanionFrameChannel.classify(slice), .media(Data([0x09])))
    }

    func testRealControlEnvelopeIsNeverMisclassifiedAsMedia() throws {
        // The backward-compatibility invariant: an encoded CompanionEnvelope (the
        // exact bytes the control channel puts on the wire) must classify as
        // control, i.e. never begin with the media marker.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let envelopes: [ClientEnvelope] = [
            ClientEnvelope(requestID: 1, payload: .ping),
            ClientEnvelope(requestID: nil, payload: .hello(revision: 9, minimumPeer: 1)),
            ClientEnvelope(requestID: 42, payload: .streamAck(streamID: 1,
                                                              lastPTSMilliseconds: 0,
                                                              queueDepth: 0)),
        ]
        for envelope in envelopes {
            let data = try encoder.encode(envelope)
            XCTAssertEqual(data.first, UInt8(ascii: "{"))
            XCTAssertNotEqual(data.first, CompanionFrameChannel.mediaMarker)
            guard case .control(let bytes) = try XCTUnwrap(CompanionFrameChannel.classify(data)) else {
                return XCTFail("a real control envelope must classify as control")
            }
            XCTAssertEqual(bytes, data)
        }
    }
}
