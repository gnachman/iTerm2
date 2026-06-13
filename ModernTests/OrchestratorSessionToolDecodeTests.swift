//
//  OrchestratorSessionToolDecodeTests.swift
//  iTerm2 ModernTests
//
//  Offline tests for OrchestratorDispatcher.buildRemoteCommand and
//  requiresSessionClaim — the two pure helpers that drive session_*
//  tool dispatch on the client side. buildRemoteCommand is the
//  24-arm switch that decodes the LLM's argument dict into the
//  correct RemoteCommand.Content prototype; a typo in any arm would
//  silently mis-decode one tool's args without a compiler error.
//  requiresSessionClaim is the read/write classification that gates
//  the per-session approval prompt; getting it wrong either bypasses
//  the gate for a write tool or prompts the user unnecessarily for
//  a read.
//
//  These tests don't need a broker, a listModel, a chat database, or
//  iTermController — buildRemoteCommand is a pure decode and
//  requiresSessionClaim is a pure classification. The dispatcher's
//  side-effecting paths (PTYSession dispatch, broker permission
//  prompt) are not covered here; manual driving and the live harness
//  cover those.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestratorSessionToolDecodeTests: XCTestCase {

    // MARK: - buildRemoteCommand

    // A tool with a typed argument decodes correctly and the resulting
    // RemoteCommand.Content carries the right prototype value.
    func testBuildRemoteCommand_executeCommand_decodesCommandField() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        let rc = try OrchestratorDispatcher.buildRemoteCommand(
            content: .executeCommand(.init()),
            prototypeDict: ["command": "ls -la"],
            llmMessage: llmMessage)
        guard case let .executeCommand(args) = rc.content else {
            XCTFail("Wrong content case: \(rc.content)")
            return
        }
        XCTAssertEqual(args.command, "ls -la")
    }

    // A tool with NO arguments decodes from an empty dict without
    // throwing. A regression in the 24-arm switch could easily break
    // the empty-prototype cases (IsAtPrompt, GetLastExitStatus, etc.).
    func testBuildRemoteCommand_isAtPrompt_decodesFromEmptyDict() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        let rc = try OrchestratorDispatcher.buildRemoteCommand(
            content: .isAtPrompt(.init()),
            prototypeDict: [:],
            llmMessage: llmMessage)
        guard case .isAtPrompt = rc.content else {
            XCTFail("Wrong content case: \(rc.content)")
            return
        }
    }

    // Coverage check: a tool with a single typed string field.
    func testBuildRemoteCommand_searchCommandHistory_decodesQueryField() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        let rc = try OrchestratorDispatcher.buildRemoteCommand(
            content: .searchCommandHistory(.init()),
            prototypeDict: ["query": "git rebase"],
            llmMessage: llmMessage)
        guard case let .searchCommandHistory(args) = rc.content else {
            XCTFail("Wrong content case: \(rc.content)")
            return
        }
        XCTAssertEqual(args.query, "git rebase")
    }

    // A tool with multiple fields decodes both.
    func testBuildRemoteCommand_createFile_decodesNameAndContent() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        let rc = try OrchestratorDispatcher.buildRemoteCommand(
            content: .createFile(.init()),
            prototypeDict: ["filename": "foo.txt",
                            "content": "hello\nworld"],
            llmMessage: llmMessage)
        guard case let .createFile(args) = rc.content else {
            XCTFail("Wrong content case: \(rc.content)")
            return
        }
        // CreateFile prototype is internal; just verify the case fired
        // and the args are non-default (default content is empty).
        // If CreateFile's fields change, this test will fail-to-compile
        // rather than silently mis-pass.
        let encoded = try JSONEncoder().encode(args)
        let dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(dict?["filename"] as? String, "foo.txt")
        XCTAssertEqual(dict?["content"] as? String, "hello\nworld")
    }

    // The dispatcher's session-tool path strips `session_guid` before
    // calling buildRemoteCommand — but if a future change forgets to
    // strip it, JSONDecoder's default ignore-unknown-keys behavior
    // means the prototype still decodes fine. Anchor that behavior
    // so a future move to a strict decoder doesn't silently break
    // every session_* tool.
    func testBuildRemoteCommand_ignoresExtraFields() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        let rc = try OrchestratorDispatcher.buildRemoteCommand(
            content: .executeCommand(.init()),
            prototypeDict: ["command": "echo hi",
                            "session_guid": "leftover-from-caller",
                            "unknown_future_field": 42],
            llmMessage: llmMessage)
        guard case let .executeCommand(args) = rc.content else {
            XCTFail("Wrong content case: \(rc.content)")
            return
        }
        XCTAssertEqual(args.command, "echo hi")
    }

    // Pin the round-trip: every RemoteCommand.Content case must be
    // decodable from its own encoded form via buildRemoteCommand.
    // If a future contributor adds a new case to RemoteCommand.Content
    // without adding an arm to the dispatcher's 24-arm switch, the
    // switch becomes non-exhaustive and the compiler fails. But if
    // they add an arm that decodes into the WRONG type — easy to do
    // because the case names are similar — only a test like this
    // catches it.
    func testBuildRemoteCommand_eachContentCase_decodesFromItsOwnEncodedDict() throws {
        let llmMessage = LLM.Message(role: .assistant, content: nil)
        for content in RemoteCommand.Content.allCases {
            // Encode the prototype, decode as a dict, feed back in.
            // Empty prototypes round-trip as {}.
            let prototypeJSON = try Self.encodePrototype(of: content)
            let dict = (try JSONSerialization.jsonObject(with: prototypeJSON)
                        as? [String: Any]) ?? [:]
            let rc: RemoteCommand
            do {
                rc = try OrchestratorDispatcher.buildRemoteCommand(
                    content: content,
                    prototypeDict: dict,
                    llmMessage: llmMessage)
            } catch {
                XCTFail("buildRemoteCommand threw for content=\(content): \(error)")
                continue
            }
            XCTAssertEqual(rc.content.functionName, content.functionName,
                           "buildRemoteCommand returned the wrong content case for \(content.functionName); 24-arm switch may have a copy-paste bug")
        }
    }

    // MARK: - requiresSessionClaim

    // Pin the read/write classification per category. A future
    // RemoteCommand.Content.PermissionCategory addition that doesn't
    // update requiresSessionClaim either silently bypasses the gate
    // (writes run without prompting) or silently nags the user (reads
    // prompt for permission). The switch in requiresSessionClaim has
    // both arms enumerated by case, so the compiler catches a missing
    // arm; this test catches a misclassification.
    func testRequiresSessionClaim_classifiesWriteCategoriesAsClaimRequired() {
        let writeCommands: [RemoteCommand.Content] = [
            .executeCommand(.init()),       // .runCommands
            .setClipboard(.init()),         // .writeToClipboard
            .insertTextAtCursor(.init()),   // .typeForYou
            .createFile(.init()),           // .writeToFilesystem
            .loadURL(.init()),              // .actInWebBrowser
        ]
        for cmd in writeCommands {
            XCTAssertTrue(
                OrchestratorDispatcher.requiresSessionClaim(cmd),
                "\(cmd.functionName) is a write tool; session_* dispatch must gate it")
        }
    }

    func testRequiresSessionClaim_classifiesReadCategoriesAsClaimFree() {
        let readCommands: [RemoteCommand.Content] = [
            .isAtPrompt(.init()),                  // .checkTerminalState
            .getCommandHistory(.init()),           // .viewHistory
            .getManPage(.init()),                  // .viewManpages
        ]
        for cmd in readCommands {
            XCTAssertFalse(
                OrchestratorDispatcher.requiresSessionClaim(cmd),
                "\(cmd.functionName) is a read tool; session_* dispatch must not prompt for it")
        }
    }

    // MARK: - Helpers

    // Encode the prototype value carried by a RemoteCommand.Content
    // case to JSON. The switch mirrors the case set so adding a new
    // case forces an update here, surfacing missing test coverage
    // for the new tool.
    private static func encodePrototype(of content: RemoteCommand.Content) throws -> Data {
        let encoder = JSONEncoder()
        switch content {
        case .isAtPrompt(let p):              return try encoder.encode(p)
        case .executeCommand(let p):          return try encoder.encode(p)
        case .getLastExitStatus(let p):       return try encoder.encode(p)
        case .getCommandHistory(let p):       return try encoder.encode(p)
        case .getLastCommand(let p):          return try encoder.encode(p)
        case .getCommandBeforeCursor(let p):  return try encoder.encode(p)
        case .searchCommandHistory(let p):    return try encoder.encode(p)
        case .getCommandOutput(let p):        return try encoder.encode(p)
        case .getTerminalSize(let p):         return try encoder.encode(p)
        case .getShellType(let p):            return try encoder.encode(p)
        case .detectSSHSession(let p):        return try encoder.encode(p)
        case .getRemoteHostname(let p):       return try encoder.encode(p)
        case .getUserIdentity(let p):         return try encoder.encode(p)
        case .getCurrentDirectory(let p):     return try encoder.encode(p)
        case .setClipboard(let p):            return try encoder.encode(p)
        case .insertTextAtCursor(let p):      return try encoder.encode(p)
        case .deleteCurrentLine(let p):       return try encoder.encode(p)
        case .getManPage(let p):              return try encoder.encode(p)
        case .createFile(let p):              return try encoder.encode(p)
        case .searchBrowser(let p):           return try encoder.encode(p)
        case .loadURL(let p):                 return try encoder.encode(p)
        case .webSearch(let p):               return try encoder.encode(p)
        case .getURL(let p):                  return try encoder.encode(p)
        case .readWebPage(let p):             return try encoder.encode(p)
        }
    }
}
