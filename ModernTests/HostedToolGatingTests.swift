//
//  HostedToolGatingTests.swift
//  iTerm2 ModernTests
//
//  Hosted-tool enablement (web search, code interpreter, file search) must
//  key off the model the turn will ACTUALLY run on - the chat's bound model
//  as resolved by the provider binding - not the global default model.
//  Before the provider lock, a configuration-less turn ran on the global
//  default so the two agreed; now a phone turn can run on a bound model of a
//  different vendor, and gating on the default could attach a hosted tool
//  (code_interpreter) to a model that rejects it.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class HostedToolGatingTests: XCTestCase {
    private func configuration(webSearch: Bool = false,
                               vectorStoreIDs: [String] = []) -> Message.Configuration {
        Message.Configuration(hostedWebSearchEnabled: webSearch,
                              vectorStoreIDs: vectorStoreIDs,
                              shouldThink: false,
                              reasoningEffort: nil,
                              serviceTier: nil)
    }

    // MARK: Feature gating is pure over the turn model's features

    func testCodeInterpreter_followsTurnModelFeatures() {
        // The reachable regression: codeInterpreter was set unconditionally
        // from the GLOBAL DEFAULT's features. The pure helper has no access
        // to the default; it must follow the features it is given.
        XCTAssertTrue(ChatAgent.hostedTools(features: [.hostedCodeInterpreter],
                                            configuration: nil).codeInterpreter)
        XCTAssertFalse(ChatAgent.hostedTools(features: [],
                                             configuration: nil).codeInterpreter)
    }

    func testWebSearch_requiresFeatureAndConfiguration() {
        XCTAssertTrue(ChatAgent.hostedTools(features: [.hostedWebSearch],
                                            configuration: configuration(webSearch: true)).webSearch)
        XCTAssertFalse(ChatAgent.hostedTools(features: [.hostedWebSearch],
                                             configuration: configuration(webSearch: false)).webSearch)
        XCTAssertFalse(ChatAgent.hostedTools(features: [],
                                             configuration: configuration(webSearch: true)).webSearch,
                       "a model without the feature must not get web search")
        XCTAssertFalse(ChatAgent.hostedTools(features: [.hostedWebSearch],
                                             configuration: nil).webSearch,
                       "a turn with no configuration (the phone) requests no web search")
    }

    func testFileSearch_requiresFeatureAndVectorStores() {
        let ids = ["vs_1"]
        XCTAssertEqual(ChatAgent.hostedTools(features: [.hostedFileSearch],
                                             configuration: configuration(vectorStoreIDs: ids))
                        .fileSearch?.vectorstoreIDs, ids)
        XCTAssertNil(ChatAgent.hostedTools(features: [.hostedFileSearch],
                                           configuration: configuration()).fileSearch,
                     "no vector stores -> no file search")
        XCTAssertNil(ChatAgent.hostedTools(features: [],
                                           configuration: configuration(vectorStoreIDs: ids)).fileSearch,
                     "a model without the feature must not get file search")
        XCTAssertNil(ChatAgent.hostedTools(features: [.hostedFileSearch],
                                           configuration: nil).fileSearch)
    }

    // MARK: Turn-model resolution mirrors request routing

    func testResolvedModel_findsCatalogModelByName() throws {
        XCTAssertEqual(ChatAgent.resolvedModel(named: "gpt-5")?.name, "gpt-5")
    }

    func testResolvedModel_unknownNameReturnsNil() {
        XCTAssertNil(ChatAgent.resolvedModel(named: "no-such-model-xyz"),
                     "unknown names fall back to the global default at the call site, not here")
    }

    func testResolvedModel_nilNameReturnsNil() {
        XCTAssertNil(ChatAgent.resolvedModel(named: nil))
    }
}
