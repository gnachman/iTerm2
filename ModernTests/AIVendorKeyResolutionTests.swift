//
//  AIVendorKeyResolutionTests.swift
//  iTerm2 ModernTests
//
//  Pure-unit tests for per-vendor API key resolution and manual-model vendor
//  classification. These cover the regressions where an OpenAI key could be
//  adopted for another vendor, a valid proxied key could be discarded, and the
//  Settings label could disagree with the runtime vendor classification.
//

import XCTest
@testable import iTerm2SharedARC

final class AIVendorKeyResolutionTests: XCTestCase {

    // MARK: - resolveAPIKey

    func testResolve_trustsVendorAccountKeyVerbatim() {
        // A proxy/gateway token that matches no canonical vendor prefix must
        // still be trusted when it lives in the vendor's own account.
        let result = AITermControllerObjC.resolveAPIKey(
            vendorAccountKey: "sk-or-v1-opaque-proxy-token",
            legacyKey: "sk-legacy-openai",
            vendorUsesLegacyAccount: false,
            vendorIsEffective: false)
        XCTAssertEqual(result,
                       .init(value: "sk-or-v1-opaque-proxy-token",
                             migrateLegacyToVendorAccount: false))
    }

    func testResolve_adoptsLegacyKeyOnlyForEffectiveVendor() {
        let result = AITermControllerObjC.resolveAPIKey(
            vendorAccountKey: nil,
            legacyKey: "sk-legacy-openai",
            vendorUsesLegacyAccount: false,
            vendorIsEffective: true)
        XCTAssertEqual(result,
                       .init(value: "sk-legacy-openai",
                             migrateLegacyToVendorAccount: true))
    }

    func testResolve_doesNotAdoptLegacyKeyForNonEffectiveVendor() {
        // This is the cross-contamination bug: an OpenAI legacy key must NOT be
        // handed to (e.g.) DeepSeek/Llama just because its text is ambiguous.
        let result = AITermControllerObjC.resolveAPIKey(
            vendorAccountKey: nil,
            legacyKey: "sk-legacy-openai",
            vendorUsesLegacyAccount: false,
            vendorIsEffective: false)
        XCTAssertEqual(result, .init(value: nil, migrateLegacyToVendorAccount: false))
    }

    func testResolve_ignoresEmptyLegacyKey() {
        let result = AITermControllerObjC.resolveAPIKey(
            vendorAccountKey: nil,
            legacyKey: "   ",
            vendorUsesLegacyAccount: false,
            vendorIsEffective: true)
        XCTAssertEqual(result, .init(value: nil, migrateLegacyToVendorAccount: false))
    }

    func testResolve_openAIUsesLegacyAccountDoesNotDoubleMigrate() {
        // When the vendor's account IS the legacy account (OpenAI), the stored
        // value already comes through vendorAccountKey; there is nothing to
        // migrate.
        let result = AITermControllerObjC.resolveAPIKey(
            vendorAccountKey: nil,
            legacyKey: nil,
            vendorUsesLegacyAccount: true,
            vendorIsEffective: true)
        XCTAssertEqual(result, .init(value: nil, migrateLegacyToVendorAccount: false))
    }

    // MARK: - vendor(forModelName:)

    func testVendorForModelName_recognizesRetiredModels() {
        XCTAssertEqual(LLMMetadata.vendor(forModelName: "claude-opus-4-1"), .anthropic)
        XCTAssertEqual(LLMMetadata.vendor(forModelName: "claude-sonnet-4-0"), .anthropic)
        XCTAssertEqual(LLMMetadata.vendor(forModelName: "gemini-3-pro-preview"), .gemini)
        XCTAssertEqual(LLMMetadata.vendor(forModelName: "gemini-2.0-flash"), .gemini)
        XCTAssertEqual(LLMMetadata.vendor(forModelName: "deepseek-chat"), .deepSeek)
        XCTAssertEqual(LLMMetadata.vendor(forModelName: "llama4:latest"), .llama)
    }

    func testVendorForModelName_returnsNilWhenNoVendorKeyword() {
        XCTAssertNil(LLMMetadata.vendor(forModelName: "gpt-5"))
        XCTAssertNil(LLMMetadata.vendor(forModelName: "my-local-model"))
    }

    // A retired model must resolve to a still-existing recommended model of the
    // SAME vendor, so a chat pinned to it does not silently switch providers.
    func testRetiredModelKeepsSameVendor() throws {
        for name in ["claude-sonnet-4-0", "gemini-3-pro-preview"] {
            guard AIMetadata.instance.models.first(where: { $0.name == name }) == nil else {
                XCTFail("\(name) is still present; update this retirement test")
                continue
            }
            let vendor = try XCTUnwrap(LLMMetadata.vendor(forModelName: name))
            let replacement = try XCTUnwrap(LLMMetadata.recommendedModel(for: vendor)
                                            ?? LLMMetadata.alternateModels(for: vendor).first,
                                            "No same-vendor replacement for \(name)")
            XCTAssertEqual(replacement.vendor, vendor)
        }
    }

    // MARK: - manual-model vendor classification (Settings label == runtime)

    func testManualVendor_localhostIsNotMisclassifiedAsLlama() {
        // The runtime resolver has no localhost=>Llama rule; the Settings UI now
        // routes through this same resolver so its label agrees with routing.
        let vendor = LLMMetadata.objcManualVendor(api: .chatCompletions,
                                                  url: "http://localhost:8080/v1",
                                                  modelName: "my-local-model")
        XCTAssertEqual(vendor, .openAI)
    }

    func testManualVendor_apiSelectsVendor() {
        XCTAssertEqual(LLMMetadata.objcManualVendor(api: .anthropic,
                                                    url: "",
                                                    modelName: "whatever"),
                       .anthropic)
        XCTAssertEqual(LLMMetadata.objcManualVendor(api: .gemini,
                                                    url: "",
                                                    modelName: "whatever"),
                       .gemini)
    }

    func testManualVendor_nameAndHostHeuristics() {
        XCTAssertEqual(LLMMetadata.objcManualVendor(api: .chatCompletions,
                                                    url: "https://example.com",
                                                    modelName: "claude-custom"),
                       .anthropic)
        XCTAssertEqual(LLMMetadata.objcManualVendor(api: .chatCompletions,
                                                    url: "https://api.anthropic.com/v1",
                                                    modelName: "custom"),
                       .anthropic)
        XCTAssertEqual(LLMMetadata.objcManualVendor(api: .chatCompletions,
                                                    url: "https://api.openai.com/v1",
                                                    modelName: "custom"),
                       .openAI)
    }
}
