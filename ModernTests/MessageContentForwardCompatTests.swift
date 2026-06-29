//
//  MessageContentForwardCompatTests.swift
//  iTerm2 ModernTests
//
//  Message.init(from:) is the forward-compatibility boundary for chat-message
//  CONTENT. An UNKNOWN content case (a newer build added one) - at the top level
//  OR nested inside a known .clientLocal action - must degrade to .unsupported, so
//  one new message doesn't take a whole history batch down. But a CORRUPT body of
//  a KNOWN case must THROW (surface as broken) instead of being masked as
//  "unsupported", matching the CompanionEnvelope decoder's discriminator approach.
//

import XCTest
@testable import iTerm2SharedARC

final class MessageContentForwardCompatTests: XCTestCase {
    /// Decode a Message whose `content` field is the given JSON object. Other
    /// fields are filled with valid values so only the content path is exercised.
    private func decodeMessage(content: Any) throws -> Message {
        let obj: [String: Any] = [
            "chatID": "c",
            "author": "agent",
            "content": content,
            "sentDate": 0,
            "uniqueID": "550E8400-E29B-41D4-A716-446655440000",
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Message.self, from: data)
    }

    // MARK: top-level content

    func testKnownContentDecodesNormally() throws {
        // A single unlabeled associated value encodes under "_0".
        let m = try decodeMessage(content: ["markdown": ["_0": "hello"]])
        guard case .markdown("hello") = m.content else {
            return XCTFail("expected .markdown(\"hello\"), got \(m.content)")
        }
    }

    func testUnknownTopLevelContentDegradesToUnsupported() throws {
        let m = try decodeMessage(content: ["futureContent2026": [:]])
        guard case .unsupported = m.content else {
            return XCTFail("an unknown content case must degrade to .unsupported, got \(m.content)")
        }
    }

    func testCorruptKnownContentThrows() {
        // .markdown(String) with a non-string body is corrupt, not newer: surface
        // it (throw) rather than masking as .unsupported.
        XCTAssertThrowsError(try decodeMessage(content: ["markdown": ["_0": 123]])) { error in
            XCTAssertTrue(error is DecodingError,
                          "corrupt known content must throw a DecodingError, got \(error)")
        }
    }

    // MARK: nested ClientLocal.Action

    func testKnownClientLocalActionDecodes() throws {
        let m = try decodeMessage(
            content: ["clientLocal": ["_0": ["action": ["notice": ["_0": "hi"]]]]])
        guard case .clientLocal(let cl) = m.content, case .notice("hi") = cl.action else {
            return XCTFail("expected .clientLocal(.notice(\"hi\")), got \(m.content)")
        }
    }

    func testUnknownNestedActionDegradesToUnsupported() throws {
        // A newer ClientLocal.Action inside a known .clientLocal must degrade the
        // WHOLE content to .unsupported (not throw), so a history batch survives a
        // single new-affordance message from a newer Mac.
        let m = try decodeMessage(
            content: ["clientLocal": ["_0": ["action": ["futureAction2026": [:]]]]])
        guard case .unsupported = m.content else {
            return XCTFail("an unknown nested action must degrade to .unsupported, got \(m.content)")
        }
    }

    func testCorruptKnownNestedActionThrows() {
        // .notice(String) with a non-string body is corrupt: must throw.
        XCTAssertThrowsError(
            try decodeMessage(content: ["clientLocal": ["_0": ["action": ["notice": ["_0": 123]]]]])
        ) { error in
            XCTAssertTrue(error is DecodingError,
                          "corrupt known nested action must throw, got \(error)")
        }
    }

    // MARK: exhaustiveness of the known-key sets

    func testKnownContentKeysCoverEveryCase() {
        // The switch below is EXHAUSTIVE: a new Content case breaks the build here,
        // the prompt to add it to `knownContentKeys` (and to `declared`). The
        // set-equality then catches the two drifting apart.
        _ = { (c: Message.Content) -> String in
            switch c {
            case .plainText: return "plainText"
            case .markdown: return "markdown"
            case .explanationRequest: return "explanationRequest"
            case .explanationResponse: return "explanationResponse"
            case .remoteCommandRequest: return "remoteCommandRequest"
            case .watcherEvent: return "watcherEvent"
            case .remoteCommandResponse: return "remoteCommandResponse"
            case .selectSessionRequest: return "selectSessionRequest"
            case .clientLocal: return "clientLocal"
            case .renameChat: return "renameChat"
            case .append: return "append"
            case .appendAttachment: return "appendAttachment"
            case .commit: return "commit"
            case .userCommand: return "userCommand"
            case .setPermissions: return "setPermissions"
            case .vectorStoreCreated: return "vectorStoreCreated"
            case .terminalCommand: return "terminalCommand"
            case .multipart: return "multipart"
            case .unsupported: return "unsupported"
            }
        }
        let declared: Set<String> = [
            "plainText", "markdown", "explanationRequest", "explanationResponse",
            "remoteCommandRequest", "watcherEvent", "remoteCommandResponse",
            "selectSessionRequest", "clientLocal", "renameChat", "append",
            "appendAttachment", "commit", "userCommand", "setPermissions",
            "vectorStoreCreated", "terminalCommand", "multipart", "unsupported",
        ]
        XCTAssertEqual(declared, Message.Content.knownContentKeys)
    }

    func testKnownActionKeysCoverEveryCase() {
        _ = { (a: ClientLocal.Action) -> String in
            switch a {
            case .pickingSession: return "pickingSession"
            case .executingCommand: return "executingCommand"
            case .notice: return "notice"
            case .streamingChanged: return "streamingChanged"
            case .offerLink: return "offerLink"
            case .offerOrchestration: return "offerOrchestration"
            case .permissions: return "permissions"
            case .workgroupPermissionRequest: return "workgroupPermissionRequest"
            case .enableOrchestrationRequest: return "enableOrchestrationRequest"
            case .orchestrationPermissionGranted: return "orchestrationPermissionGranted"
            }
        }
        let declared: Set<String> = [
            "pickingSession", "executingCommand", "notice", "streamingChanged",
            "offerLink", "offerOrchestration", "permissions",
            "workgroupPermissionRequest", "enableOrchestrationRequest",
            "orchestrationPermissionGranted",
        ]
        XCTAssertEqual(declared, ClientLocal.Action.knownActionKeys)
    }
}
