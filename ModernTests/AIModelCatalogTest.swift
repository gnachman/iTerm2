//
//  AIModelCatalogTest.swift
//  iTerm2 ModernTests
//
//  Verifies the data-driven AI model catalog (ai-models.json) decodes and that
//  AIMetadata surfaces it the way the rest of the app expects. This guards
//  against a silently-empty or misdecoded catalog, which would otherwise make
//  AIMetadataFixtureCoverageTest pass vacuously.
//
//  These assertions pin to the BUNDLED (shipped) ai-models.json via
//  AIModelCatalog.bundledForTesting, NOT AIMetadata.instance. AIMetadata.instance
//  loads whichever of {bundled, downloaded-cache} has the higher version, so a
//  dev machine that has launched iTerm2 and fetched a newer server catalog would
//  otherwise fail these assertions with an unchanged repo, breaking `make test`.
//

import XCTest
@testable import iTerm2SharedARC

final class AIModelCatalogTest: XCTestCase {
    private func bundledModels() throws -> [AIMetadata.Model] {
        let catalog = try XCTUnwrap(AIModelCatalog.bundledForTesting,
                                    "bundled ai-models.json failed to load")
        return catalog.models
    }

    func testCatalogDecodesAndIsNonEmpty() throws {
        let models = try bundledModels()
        XCTAssertFalse(models.isEmpty,
                       "AI model catalog decoded to zero models")
        XCTAssertEqual(models.count, 42,
                       "Unexpected catalog size; update this test if you intentionally changed ai-models.json")
    }

    func testDefaultIsFirstEntry() throws {
        let models = try bundledModels()
        XCTAssertEqual(models.first?.name, "gpt-5.5")
    }

    func testRecommendedModelPerVendor() throws {
        let models = try bundledModels()
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .openAI, in: models)?.name, "gpt-5.5")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .gemini, in: models)?.name, "gemini-3.5-flash")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .deepSeek, in: models)?.name, "deepseek-v4-flash")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .anthropic, in: models)?.name, "claude-opus-4-8")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .llama, in: models)?.name, "llama4:latest")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .apple, in: models)?.name, "apple-on-device")
    }

    func testAlternateModelsFilterByVendor() throws {
        let models = try bundledModels()
        let anthropic = models.filter { $0.vendor == .anthropic }
        XCTAssertEqual(anthropic.count, 7)
        XCTAssertTrue(anthropic.allSatisfy { $0.vendor == .anthropic })
        XCTAssertTrue(models.filter { $0.vendor == .gemini }.allSatisfy { $0.vendor == .gemini })
        XCTAssertTrue(models.filter { $0.vendor == .openAI }.allSatisfy { $0.vendor == .openAI })
    }

    func testFieldsMapCorrectly() throws {
        let models = try bundledModels()
        guard let opus = models.first(where: { $0.name == "claude-opus-4-8" }) else {
            XCTFail("claude-opus-4-8 missing from catalog")
            return
        }
        // Opus 4.8 rejects the temperature parameter.
        XCTAssertFalse(opus.supportsTemperature)
        XCTAssertEqual(opus.api, .anthropic)
        XCTAssertEqual(opus.vendor, .anthropic)
        XCTAssertEqual(opus.contextWindowTokens, 200_000)
        XCTAssertEqual(opus.maxResponseTokens, 128_000)
        XCTAssertTrue(opus.features.contains(.functionCalling))
        XCTAssertTrue(opus.features.contains(.streaming))
        XCTAssertTrue(opus.recommended)

        // A model that still accepts temperature defaults to true.
        if let sonnet = models.first(where: { $0.name == "claude-sonnet-4-6" }) {
            XCTAssertTrue(sonnet.supportsTemperature)
        }

        // gpt-5 opts into the OpenAI vector store; gpt-5.5 does not.
        if let gpt5 = models.first(where: { $0.name == "gpt-5" }) {
            XCTAssertEqual(gpt5.vectorStoreConfig, .openAI)
        }
        if let gpt55 = models.first(where: { $0.name == "gpt-5.5" }) {
            XCTAssertEqual(gpt55.vectorStoreConfig, .disabled)
        }
    }

    func testEconomyModelResolves() throws {
        let models = try bundledModels()
        guard let opus = models.first(where: { $0.name == "claude-opus-4-8" }) else {
            XCTFail("claude-opus-4-8 missing from catalog")
            return
        }
        XCTAssertEqual(opus.economyModelName, "claude-haiku-4-5")
        let economy = AIMetadata.economyModel(for: opus, in: models)
        XCTAssertEqual(economy?.name, "claude-haiku-4-5")
        // Transport is preserved from the caller's model.
        XCTAssertEqual(economy?.url, opus.url)
        XCTAssertEqual(economy?.api, opus.api)
    }

    func testEconomyModelPreservesCustomEndpoint() throws {
        let models = try bundledModels()
        // A manual-mode user who points claude-opus-4-8 at a corporate proxy: the
        // economy swap must keep that endpoint/api so the API key is not sent to
        // the public vendor host.
        let proxied = AIMetadata.Model(name: "claude-opus-4-8",
                                       contextWindowTokens: 200_000,
                                       maxResponseTokens: 128_000,
                                       url: "https://proxy.internal.example/v1/messages",
                                       api: .anthropic,
                                       features: [],
                                       vendor: .anthropic)
        let economy = AIMetadata.economyModel(for: proxied, in: models)
        XCTAssertEqual(economy?.name, "claude-haiku-4-5")
        XCTAssertEqual(economy?.url, "https://proxy.internal.example/v1/messages",
                       "economy model must not bypass the user's custom base URL")
        XCTAssertEqual(economy?.api, .anthropic)
    }

    func testEveryEconomyPointerIsValid() throws {
        let models = try bundledModels()
        let names = Set(models.map { $0.name })
        for model in models {
            guard let economyName = model.economyModelName else { continue }
            XCTAssertTrue(names.contains(economyName),
                          "\(model.name) economyModel \(economyName) is not in the catalog")
            XCTAssertNotEqual(economyName, model.name,
                              "\(model.name) economyModel points at itself")
            let economy = models.first(where: { $0.name == economyName })
            XCTAssertEqual(economy?.vendor, model.vendor,
                           "\(model.name) economyModel \(economyName) is a different vendor")
        }
    }

    func testEconomyModelFallsBackToCatalogEntryByName() throws {
        let models = try bundledModels()
        // A model built without the pointer (as settings/manual mode produces)
        // still resolves via the same-name catalog entry.
        let manualLikeOpus = AIMetadata.Model(name: "claude-opus-4-8",
                                              contextWindowTokens: 200_000,
                                              maxResponseTokens: 128_000,
                                              url: "https://example.com",
                                              api: .anthropic,
                                              features: [],
                                              vendor: .anthropic)
        XCTAssertNil(manualLikeOpus.economyModelName)
        XCTAssertEqual(AIMetadata.economyModel(for: manualLikeOpus, in: models)?.name,
                       "claude-haiku-4-5")
    }

    func testModelWithoutEconomyReturnsNil() throws {
        let models = try bundledModels()
        guard let haiku = models.first(where: { $0.name == "claude-haiku-4-5" }) else {
            XCTFail("claude-haiku-4-5 missing from catalog")
            return
        }
        XCTAssertNil(haiku.economyModelName)
        XCTAssertNil(AIMetadata.economyModel(for: haiku, in: models))
    }

    // MARK: - Downloaded-catalog validation (defense in depth)

    private func catalogData(_ models: [[String: Any]], version: Int = 9) -> Data {
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: ["version": version, "models": models])
    }

    private func modelDict(_ name: String,
                           vendor: String = "anthropic",
                           extra: [String: Any] = [:]) -> [String: Any] {
        var m: [String: Any] = ["name": name,
                                "vendor": vendor,
                                "api": vendor,
                                "url": "https://example.com",
                                "contextWindowTokens": 1000,
                                "maxResponseTokens": 1000,
                                "features": []]
        m.merge(extra) { _, new in new }
        return m
    }

    func testValidateAcceptsBundledCatalog() throws {
        let url = try XCTUnwrap(AIModelCatalog.bundledCatalogURL)
        let data = try Data(contentsOf: url)
        XCTAssertNotNil(AIModelCatalog.validate(data: data),
                        "the bundled catalog must satisfy validate()'s invariants")
    }

    func testValidateAcceptsWellFormedCatalog() {
        XCTAssertEqual(
            AIModelCatalog.validate(data: catalogData([modelDict("a"), modelDict("b")], version: 9)),
            9)
    }

    func testValidateRejectsCrossVendorEconomyPointer() {
        XCTAssertNil(AIModelCatalog.validate(data: catalogData([
            modelDict("a", extra: ["economyModel": "g"]),
            modelDict("g", vendor: "gemini"),
        ])))
    }

    func testValidateRejectsDanglingEconomyPointer() {
        XCTAssertNil(AIModelCatalog.validate(data: catalogData([
            modelDict("a", extra: ["economyModel": "missing"]),
        ])))
    }

    func testValidateRejectsSelfEconomyPointer() {
        XCTAssertNil(AIModelCatalog.validate(data: catalogData([
            modelDict("a", extra: ["economyModel": "a"]),
        ])))
    }

    func testValidateRejectsDuplicateRecommendedPerVendor() {
        XCTAssertNil(AIModelCatalog.validate(data: catalogData([
            modelDict("a", extra: ["recommended": true]),
            modelDict("b", extra: ["recommended": true]),
        ])))
        // Same names but different vendors is fine.
        XCTAssertNotNil(AIModelCatalog.validate(data: catalogData([
            modelDict("a", vendor: "anthropic", extra: ["recommended": true]),
            modelDict("g", vendor: "gemini", extra: ["recommended": true]),
        ])))
    }

    func testGeminiUrlTemplatePreserved() throws {
        let models = try bundledModels()
        guard let gemini = models.first(where: { $0.vendor == .gemini }) else {
            XCTFail("no gemini model")
            return
        }
        XCTAssertTrue(gemini.url.contains("{{MODEL}}"),
                      "Gemini URL must keep the {{MODEL}} template for LLMProvider to substitute")
    }
}
