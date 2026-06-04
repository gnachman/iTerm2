//
//  OrchestrationPayloadTests.swift
//  iTerm2 ModernTests
//
//  Offline tests for the wire format that ferries orchestration tool
//  calls between the agent and the app-side OrchestratorClient. The
//  agent publishes Message.Content.remoteCommandRequest(.external(...))
//  and parks the LLM completion under the message's uniqueID; the
//  client receives the request, runs the dispatcher, and publishes
//  .remoteCommandResponse carrying the same requestID. The two halves
//  of that round-trip rely on RemoteCommandPayload (a discriminated
//  Codable enum that round-trips both classic AITerm RemoteCommand
//  payloads and the new external orchestration payloads), and on the
//  fact that an existing chat database written before this branch
//  decodes its .classic rows without a discriminator field.
//
//  These tests pin both invariants. They do not exercise the
//  parking/wiring inside ChatAgent or OrchestratorClient — those are
//  integration-level concerns covered by the manual test plan and
//  AILiveHarness end-to-end tests.
//

import XCTest
@testable import iTerm2SharedARC

final class OrchestrationPayloadTests: XCTestCase {

    // MARK: - RemoteCommandPayload Codable

    // .external payload round-trips through Codable with every field
    // intact. Failure here means the agent and the client will see
    // mismatched data: the agent publishes one shape, the client
    // decodes another, the LLM never gets a tool_result.
    func testExternalPayload_codableRoundTrip() throws {
        let llmMessage = LLM.Message(
            role: .assistant,
            content: nil,
            functionCallID: LLM.Message.FunctionCallID(
                callID: "call_abc123",
                itemID: "msg_xyz"),
            function_call: LLM.FunctionCall(name: "send_text",
                                            arguments: "{\"text\":\"hi\"}",
                                            id: "call_abc123"))
        let external = ExternalRemoteCommand(
            llmMessage: llmMessage,
            name: "send_text",
            argsJSON: "{\"session_guid\":\"E8CCAA84-DE9C-4175-8A63-12015D3686CD\",\"text\":\"hi\"}",
            markdownDescription: "Typing into **Code Review** in **foo**: “hi”")
        let payload = RemoteCommandPayload.external(external)

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(RemoteCommandPayload.self, from: encoded)

        guard case let .external(decodedExt) = decoded else {
            XCTFail("Expected .external arm, got .classic")
            return
        }
        XCTAssertEqual(decodedExt.name, external.name)
        XCTAssertEqual(decodedExt.argsJSON, external.argsJSON)
        XCTAssertEqual(decodedExt.markdownDescription, external.markdownDescription)
        XCTAssertEqual(decodedExt.kind, "external",
                       "discriminator must be the literal string \"external\" so future RemoteCommandPayload decoders route correctly")
        XCTAssertEqual(decodedExt.llmMessage.function_call?.name, "send_text")
        XCTAssertEqual(decodedExt.llmMessage.functionCallID?.callID, "call_abc123")
        XCTAssertEqual(decodedExt.llmMessage.functionCallID?.itemID, "msg_xyz")
    }

    // .classic payload round-trips through the same enum. Failure here
    // breaks every AITerm tool call.
    func testClassicPayload_codableRoundTrip() throws {
        let llmMessage = LLM.Message(role: .assistant,
                                     content: "running ls")
        let remoteCommand = RemoteCommand(
            llmMessage: llmMessage,
            content: .executeCommand(.init(command: "ls -la")))
        let payload = RemoteCommandPayload.classic(remoteCommand)

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(RemoteCommandPayload.self, from: encoded)

        guard case let .classic(decodedRC) = decoded else {
            XCTFail("Expected .classic arm, got .external")
            return
        }
        guard case let .executeCommand(args) = decodedRC.content else {
            XCTFail("Wrong content case")
            return
        }
        XCTAssertEqual(args.command, "ls -la")
    }

    // Pre-branch chat databases hold .classic payloads encoded as a
    // bare RemoteCommand with no `kind` discriminator. The new
    // RemoteCommandPayload decoder must fall back to .classic when
    // `kind` is absent, or every existing chat with a tool-call
    // history becomes unloadable.
    //
    // The JSON shape comes from a real RemoteCommand encode (the
    // legacy form is exactly the bare RemoteCommand JSON, with no
    // wrapper). Verifying via `kind` absent in the encoded output
    // pins the invariant that a future change to add a wrapper
    // would surface here.
    func testClassicPayload_legacyShape_hasNoDiscriminatorAndDecodes() throws {
        let llmMessage = LLM.Message(role: .assistant, content: "running ls")
        let remoteCommand = RemoteCommand(
            llmMessage: llmMessage,
            content: .executeCommand(.init(command: "ls -la")))
        // Encode as a bare RemoteCommand — exactly what a pre-branch
        // build wrote to disk.
        let bareData = try JSONEncoder().encode(remoteCommand)
        let bareDict = (try JSONSerialization.jsonObject(with: bareData)
                        as? [String: Any]) ?? [:]
        XCTAssertNil(bareDict["kind"],
                     "Bare RemoteCommand JSON must not carry a `kind` key; a regression that adds one would route this through the .external arm and break legacy chats")

        // The bare RemoteCommand JSON must decode as RemoteCommandPayload.classic.
        let decoded = try JSONDecoder().decode(RemoteCommandPayload.self, from: bareData)
        guard case let .classic(decodedRC) = decoded else {
            XCTFail("Bare RemoteCommand JSON must decode as .classic; got .external")
            return
        }
        guard case let .executeCommand(args) = decodedRC.content else {
            XCTFail("Wrong content case")
            return
        }
        XCTAssertEqual(args.command, "ls -la")
    }

    // The encoded form of .external must carry the discriminator the
    // decoder needs. A regression that drops the `kind` field (e.g. a
    // custom encoder that forgets to emit it) would silently
    // re-encode external payloads in a shape the decoder falls back
    // to .classic for, and every orchestration tool call would
    // misdecode on the next launch.
    func testExternalPayload_encodedFormCarriesDiscriminator() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        let payload = RemoteCommandPayload.external(ExternalRemoteCommand(
            llmMessage: llmMessage,
            name: "list_workgroups",
            argsJSON: "{}",
            markdownDescription: "Looking up workgroups"))
        let data = try JSONEncoder().encode(payload)
        let dict = (try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]) ?? [:]
        XCTAssertEqual(dict["kind"] as? String, "external",
                       ".external payloads must encode `kind: \"external\"` so the decoder routes them correctly")
    }

    // MARK: - Message-level round-trip

    // The .remoteCommandRequest case carries a payload + safe flag. A
    // failure here would mean orchestration tool history fails to
    // load from the chat DB on next launch — a chat that exchanged
    // tool calls would become unopenable.
    func testRemoteCommandRequestMessage_external_roundTrip() throws {
        let llmMessage = LLM.Message(role: .assistant,
                                     content: nil,
                                     function_call: LLM.FunctionCall(
                                        name: "list_workgroups",
                                        arguments: "{}",
                                        id: "call_42"))
        let payload = RemoteCommandPayload.external(ExternalRemoteCommand(
            llmMessage: llmMessage,
            name: "list_workgroups",
            argsJSON: "{}",
            markdownDescription: "Looking up workgroups"))
        let originalID = UUID()
        let message = Message(
            chatID: "chat-1",
            author: .agent,
            content: .remoteCommandRequest(payload, safe: nil),
            sentDate: Date(timeIntervalSince1970: 1_700_000_000),
            uniqueID: originalID)

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.uniqueID, originalID,
                       "uniqueID is the parking key; round-trip must preserve it")
        guard case let .remoteCommandRequest(decodedPayload, _) = decoded.content else {
            XCTFail("Wrong content arm after round-trip")
            return
        }
        guard case let .external(ext) = decodedPayload else {
            XCTFail("Lost the .external discriminator across Message Codable")
            return
        }
        XCTAssertEqual(ext.name, "list_workgroups")
    }

    // The .remoteCommandResponse case is what closes the loop. Its
    // embedded UUID must match the parking key; the function call ID
    // must survive so providers that need it (Anthropic, Responses)
    // can match the tool_use up.
    func testRemoteCommandResponseMessage_carriesRequestIDAndFCID() throws {
        let requestID = UUID()
        let functionCallID = LLM.Message.FunctionCallID(
            callID: "call_abc", itemID: "item_def")
        let message = Message(
            chatID: "chat-1",
            author: .user,
            content: .remoteCommandResponse(
                .success("ok"),
                requestID,
                "send_text",
                functionCallID),
            sentDate: Date(timeIntervalSince1970: 1_700_000_000),
            uniqueID: UUID())

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        guard case let .remoteCommandResponse(result, decodedRequestID, name, fcID) = decoded.content else {
            XCTFail("Wrong content arm after round-trip")
            return
        }
        XCTAssertEqual(decodedRequestID, requestID,
                       "requestID is the lookup key in pendingRemoteCommands; must survive Codable")
        XCTAssertEqual(name, "send_text")
        XCTAssertEqual(fcID?.callID, "call_abc")
        XCTAssertEqual(fcID?.itemID, "item_def")
        guard case let .success(output) = result else {
            XCTFail("Expected success result")
            return
        }
        XCTAssertEqual(output, "ok")
    }
}
