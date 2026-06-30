//
//  CompanionStreamMessagesTests.swift
//  iTerm2 ModernTests
//
//  Round-trip coverage for the live-stream control messages: every associated
//  value (codec lists, optional bitrate, binary codec extradata, geometry,
//  end reason) must survive encode/decode so the Mac host and iOS app agree.
//

import XCTest
@testable import iTerm2SharedARC

final class CompanionStreamMessagesTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d
    }
    private func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e
    }

    private func roundTripClient(_ payload: CompanionClientMessage) throws -> CompanionClientMessage {
        let data = try encoder().encode(ClientEnvelope(requestID: 1, payload: payload))
        return try decoder().decode(ClientEnvelope.self, from: data).payload
    }
    private func roundTripHost(_ payload: CompanionHostMessage) throws -> CompanionHostMessage {
        let data = try encoder().encode(HostEnvelope(requestID: nil, payload: payload))
        return try decoder().decode(HostEnvelope.self, from: data).payload
    }

    func testStartSessionStreamRoundTrip() throws {
        let params = CompanionStreamParams(supportedCodecs: [.hevc, .h264],
                                           maxFrameRate: 30,
                                           maxBitrate: 500_000)
        guard case let .startSessionStream(guid, decoded) =
                try roundTripClient(.startSessionStream(sessionGuid: "abc", params: params)) else {
            return XCTFail("expected .startSessionStream")
        }
        XCTAssertEqual(guid, "abc")
        XCTAssertEqual(decoded, params)
    }

    func testUpdateStreamParamsPreservesNilBitrate() throws {
        let params = CompanionStreamParams(supportedCodecs: [.hevc], maxFrameRate: 60, maxBitrate: nil)
        guard case let .updateStreamParams(streamID, decoded) =
                try roundTripClient(.updateStreamParams(streamID: 7, params: params)) else {
            return XCTFail("expected .updateStreamParams")
        }
        XCTAssertEqual(streamID, 7)
        XCTAssertNil(decoded.maxBitrate)
        XCTAssertEqual(decoded, params)
    }

    func testStreamAckRoundTrip() throws {
        guard case let .streamAck(streamID, pts, depth) =
                try roundTripClient(.streamAck(streamID: 3, lastPTSMilliseconds: 123456789, queueDepth: 4)) else {
            return XCTFail("expected .streamAck")
        }
        XCTAssertEqual(streamID, 3)
        XCTAssertEqual(pts, 123456789)
        XCTAssertEqual(depth, 4)
    }

    func testStreamStartedRoundTrip() throws {
        guard case let .streamStarted(started) =
                try roundTripHost(.streamStarted(CompanionStreamStarted(streamID: 9, codec: .hevc))) else {
            return XCTFail("expected .streamStarted")
        }
        XCTAssertEqual(started, CompanionStreamStarted(streamID: 9, codec: .hevc))
    }

    func testStreamConfigRoundTripPreservesExtradata() throws {
        let config = CompanionStreamConfig(streamID: 9, generationId: 2,
                                           codecExtradata: Data([0x01, 0x02, 0x03, 0xFF]),
                                           pixelWidth: 1280, pixelHeight: 720, scale: 2,
                                           columns: 120, rows: 40)
        guard case let .streamConfig(decoded) = try roundTripHost(.streamConfig(config)) else {
            return XCTFail("expected .streamConfig")
        }
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.codecExtradata, Data([0x01, 0x02, 0x03, 0xFF]))
        XCTAssertNil(decoded.cellGeometry, "geometry omitted stays nil")
    }

    func testStreamConfigRoundTripWithCellGeometry() throws {
        let geometry = CompanionCellGeometry(cellWidth: 14.5, cellHeight: 30, leftMargin: 0, topMargin: 0)
        let config = CompanionStreamConfig(streamID: 9, generationId: 2,
                                           codecExtradata: Data([0xAA]),
                                           pixelWidth: 1280, pixelHeight: 720, scale: 2,
                                           columns: 120, rows: 40,
                                           cellGeometry: geometry)
        guard case let .streamConfig(decoded) = try roundTripHost(.streamConfig(config)) else {
            return XCTFail("expected .streamConfig")
        }
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.cellGeometry, geometry)
    }

    func testStreamEndedRoundTrip() throws {
        guard case let .streamEnded(streamID, reason) =
                try roundTripHost(.streamEnded(streamID: 5, reason: .superseded)) else {
            return XCTFail("expected .streamEnded")
        }
        XCTAssertEqual(streamID, 5)
        XCTAssertEqual(reason, .superseded)
    }

    func testSelectionGestureRoundTrip() throws {
        let point = CompanionSelectionPoint(absLine: 9_000_000_000, column: 37)
        guard case let .selectionGesture(streamID, phase, mode, decoded) =
                try roundTripClient(.selectionGesture(streamID: 4, phase: .move,
                                                      mode: .word, point: point)) else {
            return XCTFail("expected .selectionGesture")
        }
        XCTAssertEqual(streamID, 4)
        XCTAssertEqual(phase, .move)
        XCTAssertEqual(mode, .word)
        XCTAssertEqual(decoded, point)
    }

    func testClearSelectionRoundTrip() throws {
        guard case let .clearSelection(streamID) =
                try roundTripClient(.clearSelection(streamID: 8)) else {
            return XCTFail("expected .clearSelection")
        }
        XCTAssertEqual(streamID, 8)
    }

    func testCopySelectionRoundTrip() throws {
        guard case let .copySelection(guid) =
                try roundTripClient(.copySelection(sessionGuid: "S-1")) else {
            return XCTFail("expected .copySelection")
        }
        XCTAssertEqual(guid, "S-1")
    }

    func testSelectionTextRoundTrip() throws {
        guard case let .selectionText(text) =
                try roundTripHost(.selectionText(text: "hello “world”")) else {
            return XCTFail("expected .selectionText")
        }
        XCTAssertEqual(text, "hello “world”")
    }
}
