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
        XCTAssertEqual(models.count, 53,
                       "Unexpected catalog size; update this test if you intentionally changed ai-models.json")
    }

    func testDefaultIsFirstEntry() throws {
        let models = try bundledModels()
        XCTAssertEqual(models.first?.name, "gpt-6-astra")
    }

    func testRecommendedModelPerVendor() throws {
        let models = try bundledModels()
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .openAI, in: models)?.name, "gpt-6-astra")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .gemini, in: models)?.name, "gemini-3.8-flash")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .deepSeek, in: models)?.name, "deepseek-flash")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .anthropic, in: models)?.name, "claude-opus-5-5")
        // Ollama models are discovered from the local server, not the catalog.
        XCTAssertNil(AIModelCatalog.recommendedModel(for: .llama, in: models))
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .apple, in: models)?.name, "apple-on-device")
        XCTAssertEqual(AIModelCatalog.recommendedModel(for: .xAI, in: models)?.name, "grok-4.7")
    }

    func testAlternateModelsFilterByVendor() throws {
        let models = try bundledModels()
        let anthropic = models.filter { $0.vendor == .anthropic }
        XCTAssertEqual(anthropic.count, 12)
        XCTAssertTrue(anthropic.allSatisfy { $0.vendor == .anthropic })
        XCTAssertTrue(models.filter { $0.vendor == .gemini }.allSatisfy { $0.vendor == .gemini })
        XCTAssertTrue(models.filter { $0.vendor == .openAI }.allSatisfy { $0.vendor == .openAI })
    }

    func testFieldsMapCorrectly() throws {
        let models = try bundledModels()
        guard let opus = models.first(where: { $0.name == "claude-opus-5-5" }) else {
            XCTFail("claude-opus-5-5 missing from catalog")
            return
        }
        // Opus 5.5 rejects the temperature parameter.
        XCTAssertFalse(opus.supportsTemperature)
        XCTAssertEqual(opus.api, .anthropic)
        XCTAssertEqual(opus.vendor, .anthropic)
        XCTAssertEqual(opus.contextWindowTokens, 1_000_000)
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

        guard let grok = models.first(where: { $0.name == "grok-4.7" }) else {
            XCTFail("grok-4.7 missing from catalog")
            return
        }
        XCTAssertEqual(grok.api, .chatCompletions)
        XCTAssertEqual(grok.vendor, .xAI)
        XCTAssertEqual(grok.url, "https://api.x.ai/v1/chat/completions")
        XCTAssertEqual(grok.contextWindowTokens, 500_000)
        XCTAssertEqual(grok.maxResponseTokens, 128_000)
        XCTAssertTrue(grok.features.contains(.functionCalling))
        XCTAssertTrue(grok.features.contains(.streaming))
        XCTAssertTrue(grok.recommended)
        XCTAssertEqual(grok.economyModelName, "grok-4.3")
        XCTAssertEqual(grok.reasoningEfforts, [.low, .medium, .high, .xhigh])

        guard let grok43 = models.first(where: { $0.name == "grok-4.3" }) else {
            XCTFail("grok-4.3 missing from catalog")
            return
        }
        XCTAssertEqual(grok43.vendor, .xAI)
        XCTAssertEqual(grok43.api, .chatCompletions)
        XCTAssertEqual(grok43.contextWindowTokens, 1_000_000)
        XCTAssertEqual(grok43.maxResponseTokens, 128_000)
        XCTAssertFalse(grok43.recommended)
        XCTAssertEqual(grok43.reasoningEfforts, [.none, .low, .medium, .high, .xhigh])
    }

    func testGrokNameGuessUsesChatCompletions() {
        let guessed = AIModel(modelName: "grok-custom", url: nil, legacy: false)
        XCTAssertEqual(guessed.model.vendor, .xAI)
        XCTAssertEqual(guessed.model.api, .chatCompletions)
        XCTAssertEqual(guessed.model.url, "https://api.x.ai/v1/chat/completions")
        XCTAssertTrue(guessed.model.features.contains(.functionCalling))
        XCTAssertTrue(guessed.model.features.contains(.streaming))
        XCTAssertEqual(AIMetadata.instance.api(for: "grok-name-guess", fallback: .completions),
                       .chatCompletions)
    }

    // Reasoning effort and service tier are per-model catalog data (OpenAI
    // Responses models). The chat toolbar's reasoning-effort and service-tier
    // pickers depend on these decoding from ai-models.json; a model that omits
    // them must fall back to empty (feature hidden) rather than crash.
    func testReasoningEffortAndServiceTierDecode() throws {
        let models = try bundledModels()
        guard let gpt55 = models.first(where: { $0.name == "gpt-5.5" }) else {
            XCTFail("gpt-5.5 missing from catalog")
            return
        }
        XCTAssertEqual(gpt55.thinkingOffEffort, .none)
        XCTAssertEqual(gpt55.reasoningEfforts, [.none, .low, .medium, .high, .xhigh])
        XCTAssertEqual(gpt55.serviceTiers, [.auto, .default, .priority, .flex])
        XCTAssertTrue(gpt55.supports(reasoningEffort: .xhigh))
        XCTAssertFalse(gpt55.supports(reasoningEffort: .minimal))
        XCTAssertTrue(gpt55.supports(serviceTier: .priority))

        // gpt-5.5-pro overrides thinkingOnEffort to .high.
        if let pro = models.first(where: { $0.name == "gpt-5.5-pro" }) {
            XCTAssertEqual(pro.thinkingOffEffort, .medium)
            XCTAssertEqual(pro.thinkingOnEffort, .high)
            XCTAssertEqual(pro.reasoningEfforts, [.medium, .high, .xhigh])
        }

        // A non-reasoning model exposes no efforts/tiers and keeps struct defaults.
        if let gpt4o = models.first(where: { $0.name == "gpt-4o" }) {
            XCTAssertTrue(gpt4o.reasoningEfforts.isEmpty)
            XCTAssertTrue(gpt4o.serviceTiers.isEmpty)
            XCTAssertEqual(gpt4o.thinkingOffEffort, .low)
            XCTAssertEqual(gpt4o.thinkingOnEffort, .medium)
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
        // Transport (and auth) is preserved from the caller's model.
        XCTAssertEqual(economy?.url, opus.url)
        XCTAssertEqual(economy?.api, opus.api)
    }

    func testEconomyModelPreservesCustomEndpoint() throws {
        let models = try bundledModels()
        // A pointer-carrying model at a corporate proxy (production never builds
        // one, since manual models carry no pointer; this guards the copy): the
        // economy swap must keep that endpoint/api so the API key is not sent to
        // the public vendor host.
        let proxied = AIMetadata.Model(name: "claude-opus-4-8",
                                       contextWindowTokens: 200_000,
                                       maxResponseTokens: 128_000,
                                       url: "https://proxy.internal.example/v1/messages",
                                       api: .anthropic,
                                       features: [],
                                       vendor: .anthropic)
        var pointed = proxied
        pointed.economyModelName = "claude-haiku-4-5"
        let economy = AIMetadata.economyModel(for: pointed, in: models)
        XCTAssertEqual(economy?.name, "claude-haiku-4-5")
        XCTAssertEqual(economy?.url, "https://proxy.internal.example/v1/messages",
                       "economy model must not bypass the user's custom base URL")
        XCTAssertEqual(economy?.api, .anthropic)
    }

    // QA finding F-006: a pointer-carrying model (built by hand here; manual
    // models carry no pointer since F-125) at a gateway that authenticates with a
    // custom header or a chosen key must keep that auth on its economy variant,
    // or the safety check and screen-watch poller get a 401.
    func testEconomyModelPreservesManualModelAuth() throws {
        let models = try bundledModels()
        let headers = [["name": "X-Gateway-Token", "value": "secret"]]
        var gateway = AIMetadata.Model(name: "claude-opus-4-8",
                                       contextWindowTokens: 200_000,
                                       maxResponseTokens: 128_000,
                                       url: "https://gateway.internal.example/v1/messages",
                                       api: .anthropic,
                                       features: [],
                                       vendor: .anthropic)
        gateway.customHeaders = headers
        gateway.credential = .modelKey
        gateway.manualConfigurationID = "manual-config-1"
        gateway.economyModelName = "claude-haiku-4-5"

        let economy = try XCTUnwrap(AIMetadata.economyModel(for: gateway, in: models))
        XCTAssertEqual(economy.name, "claude-haiku-4-5")
        XCTAssertEqual(economy.customHeaders, headers)
        XCTAssertEqual(economy.credential, .modelKey)
        XCTAssertEqual(economy.manualConfigurationID, "manual-config-1")
        XCTAssertEqual(economy.vendor, gateway.vendor)
    }

    func testEconomyModelPreservesChosenVendorKeyAndNoKey() throws {
        let models = try bundledModels()
        var gateway = AIMetadata.Model(name: "claude-opus-4-8",
                                       contextWindowTokens: 200_000,
                                       maxResponseTokens: 128_000,
                                       url: "http://localhost:4000/v1/messages",
                                       api: .anthropic,
                                       features: [],
                                       vendor: .anthropic)
        gateway.economyModelName = "claude-haiku-4-5"
        gateway.credential = .vendorKey(.openAI)
        let chosen = try XCTUnwrap(AIMetadata.economyModel(for: gateway, in: models))
        XCTAssertEqual(chosen.credential, .vendorKey(.openAI))
        XCTAssertEqual(chosen.keyVendor, .openAI)

        // Resolve the key the way AITermController.registration does: the
        // stored registration is offered only for a vendor it is valid for.
        // The user chose to send the OpenAI key to this local endpoint, so the
        // economy request must carry it rather than the local placeholder.
        let stored = AITermController.Registration(apiKey: "openai-key", vendor: .openAI)
        let registration = AITermController.resolvedRegistration(
            model: chosen,
            fallbackVendor: .anthropic,
            vendorRegistration: { vendor in
                guard let stored, stored.isValid(for: vendor) else {
                    return nil
                }
                return stored
            },
            modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, "openai-key")

        gateway.credential = .none
        XCTAssertEqual(AIMetadata.economyModel(for: gateway, in: models)?.credential, AIModelCredential.none)

        // With automatic credentials the vendor picks the key, so it must match
        // the configured model's, even when that differs from the catalog's
        // (e.g. a chat-completions gateway whose vendor fell back to OpenAI).
        gateway.credential = .automatic
        gateway.api = .chatCompletions
        gateway.vendor = .openAI
        let economy = AIMetadata.economyModel(for: gateway, in: models)
        XCTAssertEqual(economy?.vendor, .openAI)
        XCTAssertEqual(economy?.keyVendor, .openAI)
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

    // QA finding F-125: a manual model carries no economy pointer, and its
    // endpoint may serve only the configured model. Asking it for the catalog
    // twin's economy model (gpt-6-luna) gets rejected, so the safety check
    // fails closed on every command. With no designated economy model the
    // economy request must stay on the manual model itself, which a nil
    // result does (callers fall back to the configured chat model).
    func testManualModelSharingCatalogNameHasNoEconomyModel() throws {
        let models = try bundledModels()
        let twin = try XCTUnwrap(models.first(where: { $0.name == "gpt-5.4-mini" }))
        XCTAssertEqual(twin.economyModelName, "gpt-6-luna")
        var manual = AIMetadata.Model(name: "gpt-5.4-mini",
                                      contextWindowTokens: 8_192,
                                      maxResponseTokens: 8_192,
                                      url: "http://127.0.0.1:8080/v1/chat/completions",
                                      api: .chatCompletions,
                                      features: [],
                                      vendor: .openAI)
        manual.customHeaders = [["name": "Authorization", "value": "Bearer tok"]]
        manual.credential = .none
        manual.manualConfigurationID = "manual-config-1"
        XCTAssertNil(manual.economyModelName)
        XCTAssertNil(AIMetadata.economyModel(for: manual, in: models))

        // Same for a manual model at the vendor's own endpoint with no
        // configuration ID (as the legacy single manual model is built).
        let legacyLike = AIMetadata.Model(name: "claude-opus-4-8",
                                          contextWindowTokens: 200_000,
                                          maxResponseTokens: 128_000,
                                          url: "https://api.anthropic.com/v1/messages",
                                          api: .anthropic,
                                          features: [],
                                          vendor: .anthropic)
        XCTAssertNil(AIMetadata.economyModel(for: legacyLike, in: models))
    }

    func testCatalogModelStillGetsEconomyModel() throws {
        let models = try bundledModels()
        let mini = try XCTUnwrap(models.first(where: { $0.name == "gpt-5.4-mini" }))
        let economy = try XCTUnwrap(AIMetadata.economyModel(for: mini, in: models))
        XCTAssertEqual(economy.name, "gpt-6-luna")
        XCTAssertEqual(economy.url, mini.url)
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
