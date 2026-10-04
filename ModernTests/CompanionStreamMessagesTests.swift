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

    func testSendKeyTextRoundTrip() throws {
        let event = CompanionKeyEvent(key: .text("ls -la\n"))
        guard case let .sendKey(guid, decoded) =
                try roundTripClient(.sendKey(sessionGuid: "S-1", event: event)) else {
            return XCTFail("expected .sendKey")
        }
        XCTAssertEqual(guid, "S-1")
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.key, .text("ls -la\n"))
        XCTAssertTrue(decoded.modifiers.isEmpty)
    }

    func testSendKeySpecialWithModifiersRoundTrip() throws {
        let event = CompanionKeyEvent(key: .special(.left),
                                      modifiers: CompanionKeyModifiers(control: false,
                                                                       shift: true,
                                                                       leftOption: false,
                                                                       rightOption: true))
        guard case let .sendKey(guid, decoded) =
                try roundTripClient(.sendKey(sessionGuid: "S-2", event: event)) else {
            return XCTFail("expected .sendKey")
        }
        XCTAssertEqual(guid, "S-2")
        XCTAssertEqual(decoded.key, .special(.left))
        XCTAssertTrue(decoded.modifiers.rightOption)
        XCTAssertTrue(decoded.modifiers.shift)
        XCTAssertFalse(decoded.modifiers.control)
        XCTAssertFalse(decoded.modifiers.leftOption)
    }

    // A host predating firstAbsLine/totalLines omits those keys. Synthesized
    // Decodable would throw keyNotFound (dropping the config -> black view); the
    // custom decoder must fall back to 0 so the stream still configures.
    func testStreamConfigDecodesWithoutHistoryExtentKeys() throws {
        let json = """
        {"streamID":7,"generationId":1,"codecExtradata":"",
         "pixelWidth":800,"pixelHeight":500,"scale":2.0,"columns":80,"rows":25}
        """
        let config = try decoder().decode(CompanionStreamConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.streamID, 7)
        XCTAssertEqual(config.columns, 80)
        XCTAssertEqual(config.rows, 25)
        XCTAssertEqual(config.firstAbsLine, 0)
        XCTAssertEqual(config.totalLines, 0)
        XCTAssertNil(config.cellGeometry)
        // A host predating the resize feature omits canResize; it decodes as nil.
        XCTAssertNil(config.canResize)
        // A host predating alt-screen awareness omits these; they decode as false, so
        // the phone shows scrollback and never sends wheel input, exactly as before.
        XCTAssertFalse(config.altScreen)
        XCTAssertFalse(config.scrollWheelReporting)
    }

    func testStreamConfigRoundTripsHistoryExtent() throws {
        let original = CompanionStreamConfig(streamID: 7, generationId: 3, codecExtradata: Data([1, 2]),
                                             pixelWidth: 800, pixelHeight: 500, scale: 2, columns: 80, rows: 25,
                                             firstAbsLine: 1234, totalLines: 5678, canResize: false)
        let data = try encoder().encode(original)
        let decoded = try decoder().decode(CompanionStreamConfig.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.canResize, false)
    }

    // The host hello carries aiAvailable (revision 13+). Both truth values must
    // survive a round trip so the phone can read the mac's real AI state.
    func testHostHelloRoundTripsAIAvailable() throws {
        for value in [true, false] {
            guard case let .hello(revision, minimumPeer, wants, aiAvailable, _) =
                    try roundTripHost(.hello(revision: 13, minimumPeer: 11,
                                             wantsNotificationPermission: true,
                                             aiAvailable: value,
                                             macStatus: nil)) else {
                return XCTFail("expected .hello")
            }
            XCTAssertEqual(revision, 13)
            XCTAssertEqual(minimumPeer, 11)
            XCTAssertEqual(wants, true)
            XCTAssertEqual(aiAvailable, value)
        }
    }

    // The unsolicited aiAvailabilityChanged event round-trips both truth values so
    // a connected phone can flip its chat surfaces live when the mac toggles AI.
    func testAIAvailabilityChangedRoundTrip() throws {
        for value in [true, false] {
            guard case let .aiAvailabilityChanged(available) =
                    try roundTripHost(.aiAvailabilityChanged(available: value)) else {
                return XCTFail("expected .aiAvailabilityChanged")
            }
            XCTAssertEqual(available, value)
        }
    }

    // A pre-13 mac omits aiAvailable (and wantsNotificationPermission). Synthesized
    // Decodable decodes an absent optional as nil rather than throwing, and the
    // phone reads nil as "AI available" (a pre-13 mac only ever paired with AI on).
    // This is the backward-compatibility contract that keeps existing users
    // unaffected.
    func testLegacyHostHelloDecodesWithoutAIAvailable() throws {
        let json = """
        {"payload":{"hello":{"revision":11,"minimumPeer":11}}}
        """
        let decoded = try decoder().decode(HostEnvelope.self, from: Data(json.utf8)).payload
        guard case let .hello(revision, minimumPeer, wants, aiAvailable, macStatus) = decoded else {
            return XCTFail("expected .hello")
        }
        XCTAssertEqual(revision, 11)
        XCTAssertEqual(minimumPeer, 11)
        XCTAssertNil(wants)
        XCTAssertNil(aiAvailable, "an absent aiAvailable decodes as nil (read as available)")
        XCTAssertNil(macStatus, "an absent macStatus decodes as nil (read as not blocked, no alerts)")
    }

    // MARK: Mac status (revision 14)

    private func sampleAlert(id: String = "A1") -> CompanionModalAlert {
        return CompanionModalAlert(
            id: id,
            heading: "Enable Command Safety Checking?",
            body: "Body text",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: true),
                      .init(title: "Delete", isCancel: false, isDestructive: true, rememberable: false),
                      .init(title: "Cancel", isCancel: true, isDestructive: false, rememberable: false)],
            suppressionLabel: "Remember my choice",
            hasAccessory: true,
            isAppModal: true)
    }

    // The host hello carries the mac's status so the phone knows it before it
    // sends the requests that would time out against a blocked mac.
    func testHostHelloRoundTripsMacStatus() throws {
        let status = CompanionMacStatus(modalAlerts: [sampleAlert()], mainBlocked: true)
        guard case let .hello(_, _, _, _, macStatus) =
                try roundTripHost(.hello(revision: 14, minimumPeer: 11,
                                         wantsNotificationPermission: nil,
                                         aiAvailable: true,
                                         macStatus: status)) else {
            return XCTFail("expected .hello")
        }
        XCTAssertEqual(macStatus, status)
    }

    func testMacStatusChangedRoundTrip() throws {
        for status in [CompanionMacStatus(modalAlerts: [], mainBlocked: false),
                       CompanionMacStatus(modalAlerts: [], mainBlocked: true),
                       CompanionMacStatus(modalAlerts: [sampleAlert(id: "A1"), sampleAlert(id: "A2")],
                                          mainBlocked: true)] {
            guard case let .macStatusChanged(decoded) = try roundTripHost(.macStatusChanged(status: status)) else {
                return XCTFail("expected .macStatusChanged")
            }
            XCTAssertEqual(decoded, status)
        }
    }

    func testModalAlertAnswerRejectedRoundTrip() throws {
        guard case let .modalAlertAnswerRejected(alertID) =
                try roundTripHost(.modalAlertAnswerRejected(alertID: "A1")) else {
            return XCTFail("expected .modalAlertAnswerRejected")
        }
        XCTAssertEqual(alertID, "A1")
    }

    func testAnswerModalAlertRoundTrip() throws {
        let data = try encoder().encode(ClientEnvelope(
            requestID: nil, payload: .answerModalAlert(alertID: "A1", buttonIndex: 2, suppress: true,
                                                       inputs: ["spaces": "8"])))
        guard case let .answerModalAlert(alertID, buttonIndex, suppress, inputs) =
                try decoder().decode(ClientEnvelope.self, from: data).payload else {
            return XCTFail("expected .answerModalAlert")
        }
        XCTAssertEqual(alertID, "A1")
        XCTAssertEqual(buttonIndex, 2)
        XCTAssertTrue(suppress)
        XCTAssertEqual(inputs, ["spaces": "8"])
    }

    // An answer to an alert that asks for nothing carries no inputs, and one
    // sent without the field at all still decodes.
    func testAnswerModalAlertWithoutInputs() throws {
        let json = """
        {"payload":{"answerModalAlert":{"alertID":"A1","buttonIndex":0,"suppress":false}}}
        """
        guard case let .answerModalAlert(_, _, _, inputs) =
                try decoder().decode(ClientEnvelope.self, from: Data(json.utf8)).payload else {
            return XCTFail("expected .answerModalAlert")
        }
        XCTAssertNil(inputs)
    }

    // The values an alert asks for travel with it, and survive a mac that sends
    // a kind this phone has not heard of.
    func testModalAlertInputsRoundTripAndTolerateUnknownFields() throws {
        var alert = sampleAlert()
        alert.inputs = [
            .init(id: "name", label: nil, kind: CompanionModalAlert.Input.textKind, value: ""),
            .init(id: "spaces", label: "Tab size in spaces:", kind: CompanionModalAlert.Input.integerKind,
                  value: "4", minimum: 0, maximum: 100),
        ]
        let status = CompanionMacStatus(modalAlerts: [alert], mainBlocked: false)
        guard case let .macStatusChanged(decoded) = try roundTripHost(.macStatusChanged(status: status)) else {
            return XCTFail("expected .macStatusChanged")
        }
        XCTAssertEqual(decoded, status)

        let json = """
        {"modalAlerts":[{"id":"A1","inputs":[{"id":"x","kind":"slider","future":1}]}]}
        """
        let future = try decoder().decode(CompanionMacStatus.self, from: Data(json.utf8))
        XCTAssertEqual(future.modalAlerts.first?.inputs,
                       [.init(id: "x", label: nil, kind: "slider", value: "")])
    }

    // A status from a future mac that drops or adds fields must still decode,
    // with safe defaults, rather than taking the whole hello down with it: an
    // alert with no flags is a plain app-modal alert, a button with no flags is
    // an ordinary button, and a status with no fields is "nothing to report".
    func testMacStatusDecodesWithMissingFields() throws {
        let json = """
        {"modalAlerts":[{"id":"A1","buttons":[{"title":"OK","futureFlag":true}],"futureField":1}]}
        """
        let status = try decoder().decode(CompanionMacStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.mainBlocked)
        XCTAssertEqual(status.modalAlerts, [CompanionModalAlert(
            id: "A1", heading: "", body: "",
            buttons: [.init(title: "OK", isCancel: false, isDestructive: false, rememberable: false)],
            suppressionLabel: nil, hasAccessory: false, isAppModal: true)])

        let empty = try decoder().decode(CompanionMacStatus.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, CompanionMacStatus(modalAlerts: [], mainBlocked: false))
    }
}
