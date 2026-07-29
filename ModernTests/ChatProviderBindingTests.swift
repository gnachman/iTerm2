//
//  ChatProviderBindingTests.swift
//  iTerm2 ModernTests
//
//  Model-layer provider lock: a chat is bound to one provider (vendor) for
//  its whole life. The UI already locks its pickers, but turns can arrive
//  with no configuration (the phone) or with a configuration naming another
//  vendor's model, so ChatProviderBinding decides, per turn, which model to
//  use, whether to bind an unbound chat, or whether to reject the turn.
//

import XCTest
@testable import iTerm2SharedARC

final class ChatProviderBindingTests: XCTestCase {
    /// Fixed vendor table so the tests don't depend on the live AIMetadata
    /// catalog.
    private func vendor(_ name: String) -> iTermAIVendor? {
        switch name {
        case "gpt-5", "gpt-5-mini", "o3-pro": return .openAI
        case "claude-opus-4-8", "claude-haiku-4-5": return .anthropic
        case "gemini-3-pro": return .gemini
        case "mystery-model": return nil
        default: return nil
        }
    }

    private func evaluate(bound: String?,
                          turn: String?,
                          fallback: String? = "gpt-5") -> ChatProviderBinding.Verdict {
        ChatProviderBinding.evaluate(boundModelName: bound,
                                     turnModelName: turn,
                                     defaultModelName: fallback,
                                     vendor: vendor)
    }

    // MARK: First turn: the chat binds

    func testFirstTurn_bindsToTurnModel() {
        XCTAssertEqual(evaluate(bound: nil, turn: "claude-opus-4-8"),
                       .proceed(modelName: "claude-opus-4-8", bindChatTo: "claude-opus-4-8"))
    }

    func testFirstTurn_noTurnModel_bindsToDefault() {
        // A phone-originated first turn carries no configuration; the chat
        // must still bind (to the global default) so later turns are held to
        // one provider.
        XCTAssertEqual(evaluate(bound: nil, turn: nil, fallback: "gpt-5"),
                       .proceed(modelName: "gpt-5", bindChatTo: "gpt-5"))
    }

    func testFirstTurn_nothingResolvable_proceedsUnbound() {
        // No turn model and no default (no provider configured at all):
        // proceed and let the request fail with the normal "no model" error;
        // binding to nothing is meaningless.
        XCTAssertEqual(evaluate(bound: nil, turn: nil, fallback: nil),
                       .proceed(modelName: nil, bindChatTo: nil))
    }

    // MARK: Later turns: the binding is enforced

    func testNilConfigurationTurn_usesBoundModel() {
        // The phone sends configuration == nil. Today that silently runs on
        // the global default provider; the binding must supply the chat's
        // own model instead.
        XCTAssertEqual(evaluate(bound: "claude-opus-4-8", turn: nil),
                       .proceed(modelName: "claude-opus-4-8", bindChatTo: nil))
    }

    func testSameModelTurn_proceeds() {
        XCTAssertEqual(evaluate(bound: "gpt-5", turn: "gpt-5"),
                       .proceed(modelName: "gpt-5", bindChatTo: nil))
    }

    func testSameVendorModelSwitch_isAllowed() {
        // Switching models WITHIN the bound vendor is a model switch, not a
        // provider switch; the UI allows it and so does the model layer.
        XCTAssertEqual(evaluate(bound: "gpt-5", turn: "gpt-5-mini"),
                       .proceed(modelName: "gpt-5-mini", bindChatTo: nil))
    }

    func testCrossVendorTurn_isRejected() {
        guard case .reject(let reason) = evaluate(bound: "gpt-5", turn: "claude-opus-4-8") else {
            XCTFail("cross-vendor turn must be rejected")
            return
        }
        XCTAssertFalse(reason.isEmpty, "rejection must carry a user-facing reason")
    }

    func testCrossVendorTurn_theOtherDirection_isRejected() {
        guard case .reject = evaluate(bound: "claude-haiku-4-5", turn: "gemini-3-pro") else {
            XCTFail("cross-vendor turn must be rejected")
            return
        }
    }

    // MARK: Unclassifiable models: permissive, never brick a chat

    func testUnknownVendorTurnModel_proceeds() {
        // A manual/retired model whose vendor can't be classified must not
        // dead-end the chat; proceed with the named model.
        XCTAssertEqual(evaluate(bound: "gpt-5", turn: "mystery-model"),
                       .proceed(modelName: "mystery-model", bindChatTo: nil))
    }

    func testUnknownVendorBoundModel_proceeds() {
        XCTAssertEqual(evaluate(bound: "mystery-model", turn: "gpt-5"),
                       .proceed(modelName: "gpt-5", bindChatTo: nil))
    }
}
