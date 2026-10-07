//
//  AIModelCredentialTests.swift
//  iTerm2 ModernTests
//
//  A manual model used to authorize with whichever vendor key its name and URL
//  suggested, so a model named “gemini/gemma-4-31b-it” on an Open WebUI server
//  asked for a Gemini key (issue 13105). The model's credential now lets the
//  user choose. Automatic must keep behaving exactly as before.
//

import XCTest
@testable import iTerm2SharedARC

final class AIModelCredentialTests: XCTestCase {
    private let gatewayURL = "https://example.com/api/chat/completions"
    private let localURL = "http://localhost:1234/v1/chat/completions"

    // MARK: - Storage

    func testStoredValueRoundTrips() {
        let credentials: [AIModelCredential] = [.vendorKey(.openAI),
                                                .vendorKey(.anthropic),
                                                .vendorKey(.gemini),
                                                .vendorKey(.deepSeek),
                                                .modelKey,
                                                .none]
        for credential in credentials {
            XCTAssertEqual(AIModelCredential(storedValue: credential.storedValue), credential)
        }
    }

    // Absent is how every configuration saved before this setting looks.
    func testAutomaticIsNotStored() {
        XCTAssertNil(AIModelCredential.automatic.storedValue)
        XCTAssertEqual(AIModelCredential(storedValue: nil), .automatic)
    }

    func testUnrecognizedValuesReadAsAutomatic() {
        for value: Any in ["", "bogus", "vendor:", "vendor:x", "vendor:999", 7] {
            XCTAssertEqual(AIModelCredential(storedValue: value), .automatic, "\(value)")
        }
    }

    // Llama and Apple have no key the user can enter, so a hand-edited value
    // naming them must not leave the model unable to authorize.
    func testVendorWithoutEnterableKeyReadsAsAutomatic() {
        for vendor in [iTermAIVendor.llama, .apple] {
            XCTAssertEqual(AIModelCredential(storedValue: "vendor:\(vendor.rawValue)"), .automatic)
        }
    }

    // MARK: - Key policy

    func testAutomaticMatchesTheInference() {
        for url in [gatewayURL, localURL] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url, api: .chatCompletions, credential: .automatic),
                           AITermController.apiKeyPolicy(url: url, api: .chatCompletions))
        }
    }

    // The user asked for the key, so a local endpoint gets it too.
    func testChosenVendorKeyIsSentToLocalEndpoint() {
        XCTAssertEqual(AITermController.apiKeyPolicy(url: localURL, api: .chatCompletions, credential: .vendorKey(.openAI)),
                       .vendorKey)
    }

    func testNoneWithholdsKeyFromPublicEndpoint() {
        XCTAssertEqual(AITermController.apiKeyPolicy(url: gatewayURL, api: .chatCompletions, credential: .none),
                       .placeholder(.noKeySelected))
        XCTAssertTrue(AITermController.usesPlaceholderAPIKey(url: gatewayURL, api: .chatCompletions, credential: .none))
    }

    func testModelKeyIsNotAPlaceholder() {
        XCTAssertEqual(AITermController.apiKeyPolicy(url: gatewayURL, api: .chatCompletions, credential: .modelKey),
                       .modelKey)
        XCTAssertFalse(AITermController.usesPlaceholderAPIKey(url: gatewayURL, api: .chatCompletions, credential: .modelKey))
    }

    func testAppleIntelligenceIgnoresCredential() {
        for credential: AIModelCredential in [.automatic, .vendorKey(.openAI), .modelKey, .none] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: "", api: .appleIntelligence, credential: credential),
                           .placeholder(.onDevice))
        }
    }

    // MARK: - Which vendor's key

    func testKeyVendorFollowsChoice() {
        var model = gatewayModel(credential: .automatic)
        XCTAssertEqual(model.vendor, .gemini, "the name still drives the inferred vendor")
        XCTAssertEqual(model.keyVendor, .gemini)
        model.credential = .vendorKey(.openAI)
        XCTAssertEqual(model.keyVendor, .openAI)
        XCTAssertEqual(model.vendor, .gemini, "choosing a key must not change the request dialect")
    }

    // MARK: - Registration

    // The issue's scenario: only an OpenAI key, model named gemini/... Automatic
    // still wants the Gemini key, as before.
    func testAutomaticStillRequiresInferredVendorKey() {
        let controller = AITermController(registration: AITermController.Registration(apiKey: "sk-openai", vendor: .openAI))
        controller.providerOverride = LLMProvider(model: gatewayModel(credential: .automatic))
        XCTAssertNil(controller.registration)
        XCTAssertEqual(controller.requiredRegistrationVendor, .gemini)
    }

    func testChosenVendorKeyIsUsed() {
        let controller = AITermController(registration: AITermController.Registration(apiKey: "sk-openai", vendor: .openAI))
        controller.providerOverride = LLMProvider(model: gatewayModel(credential: .vendorKey(.openAI)))
        XCTAssertEqual(controller.registration?.apiKey, "sk-openai")
        XCTAssertEqual(controller.requiredRegistrationVendor, .openAI)
    }

    func testNoneSendsPlaceholder() {
        let controller = AITermController(registration: AITermController.Registration(apiKey: "sk-openai", vendor: .openAI))
        controller.providerOverride = LLMProvider(model: gatewayModel(credential: .none))
        XCTAssertEqual(controller.registration?.apiKey, AITermController.selfHostedPlaceholderAPIKey)
    }

    // A model key never falls back to a vendor's key.
    func testModelKeyWithoutStoredKeyHasNoRegistration() {
        let controller = AITermController(registration: AITermController.Registration(apiKey: "sk-openai", vendor: .openAI))
        var model = gatewayModel(credential: .modelKey)
        model.manualConfigurationID = nil
        controller.providerOverride = LLMProvider(model: model)
        XCTAssertNil(controller.registration)
    }

    // MARK: - Shared resolver

    // Only an OpenAI key is stored, as in the issue.
    private func openAIOnly(_ vendor: iTermAIVendor) -> AITermController.Registration? {
        return vendor == .openAI ? AITermController.Registration(apiKey: "sk-openai", vendor: .openAI) : nil
    }

    func testResolverUsesChosenVendorKey() {
        let registration = AITermController.resolvedRegistration(model: gatewayModel(credential: .vendorKey(.openAI)),
                                                                 fallbackVendor: .gemini,
                                                                 vendorRegistration: openAIOnly,
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, "sk-openai")
    }

    func testResolverAutomaticStillNeedsInferredKey() {
        XCTAssertNil(AITermController.resolvedRegistration(model: gatewayModel(credential: .automatic),
                                                           fallbackVendor: .gemini,
                                                           vendorRegistration: openAIOnly,
                                                           modelKey: { _ in nil }))
    }

    func testResolverNoneIsPlaceholder() {
        let registration = AITermController.resolvedRegistration(model: gatewayModel(credential: .none),
                                                                 fallbackVendor: .gemini,
                                                                 vendorRegistration: { _ in nil },
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, AITermController.selfHostedPlaceholderAPIKey)
    }

    func testResolverModelKey() {
        let model = gatewayModel(credential: .modelKey)
        XCTAssertEqual(AITermController.resolvedRegistration(model: model,
                                                             fallbackVendor: .gemini,
                                                             vendorRegistration: openAIOnly,
                                                             modelKey: { $0 == "test" ? "model-key" : nil })?.apiKey,
                       "model-key")
        XCTAssertNil(AITermController.resolvedRegistration(model: model,
                                                           fallbackVendor: .gemini,
                                                           vendorRegistration: openAIOnly,
                                                           modelKey: { _ in nil }),
                     "a missing model key must not fall back to a vendor's key")
    }

    // The App Review key answers locally, so it beats even a withheld key.
    func testResolverReviewKeyWins() {
        let review = AITermController.Registration(apiKey: AITermController.reviewPlaceholderAPIKey, vendor: .gemini)
        let registration = AITermController.resolvedRegistration(model: gatewayModel(credential: .none),
                                                                 fallbackVendor: .gemini,
                                                                 vendorRegistration: { _ in review },
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, AITermController.reviewPlaceholderAPIKey)
    }

    // The checks that run before a chat exists (Explain, Codecierge, the safety
    // classifier, Companion setup) resolve the default model this way.
    func testDefaultModelCredentialReachesPreflightChecks() {
        let configurationsKey = kPreferenceKeyAIManualModelConfigurations
        let savedConfigurations = iTermPreferences.object(forKey: configurationsKey)
        let savedUseRecommended = iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel)
        let savedModel = iTermPreferences.string(forKey: kPreferenceKeyAIModel)
        defer {
            iTermPreferences.setObject(savedConfigurations, forKey: configurationsKey)
            iTermPreferences.setBool(savedUseRecommended, forKey: kPreferenceKeyUseRecommendedAIModel)
            iTermPreferences.setString(savedModel, forKey: kPreferenceKeyAIModel)
        }
        let name = "gemini/gemma-4-31b-it"
        iTermPreferences.setBool(false, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setString(name, forKey: kPreferenceKeyAIModel)

        for (credential, expectedKey) in [(AIModelCredential.vendorKey(.openAI), "sk-openai"),
                                          (.none, AITermController.selfHostedPlaceholderAPIKey)] {
            iTermPreferences.setObject([
                ["id": "A", "name": name, "url": gatewayURL,
                 "api": Int(iTermAIAPI.chatCompletions.rawValue),
                 "credential": credential.storedValue!],
            ], forKey: configurationsKey)
            let model = LLMMetadata.model()
            XCTAssertEqual(model?.credential, credential)
            let registration = AITermController.resolvedRegistration(model: model,
                                                                     fallbackVendor: LLMMetadata.effectiveVendor,
                                                                     vendorRegistration: openAIOnly,
                                                                     modelKey: { _ in nil })
            XCTAssertEqual(registration?.apiKey, expectedKey, "\(credential)")
        }
        iTermPreferences.setObject([
            ["id": "A", "name": name, "url": gatewayURL,
             "api": Int(iTermAIAPI.chatCompletions.rawValue),
             "credential": AIModelCredential.vendorKey(.openAI).storedValue!],
        ], forKey: configurationsKey)
        XCTAssertEqual(AITermControllerRegistrationHelper.instance.defaultKeyVendor, .openAI,
                       "a missing key must be prompted for as the chosen vendor's")
    }

    // MARK: - Configuration

    func testManualModelReadsCredentialAndID() {
        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([
            ["id": "A", "name": "gemini/gemma-4-31b-it", "url": gatewayURL,
             "api": Int(iTermAIAPI.chatCompletions.rawValue),
             "credential": AIModelCredential.vendorKey(.openAI).storedValue!],
            ["id": "B", "name": "plain", "url": gatewayURL,
             "api": Int(iTermAIAPI.chatCompletions.rawValue)],
        ], forKey: key)
        let models = LLMMetadata.manualModels()
        let chosen = models.first { $0.name == "gemini/gemma-4-31b-it" }
        XCTAssertEqual(chosen?.credential, .vendorKey(.openAI))
        XCTAssertEqual(chosen?.manualConfigurationID, "A")
        XCTAssertEqual(chosen?.keyVendor, .openAI)
        XCTAssertEqual(models.first { $0.name == "plain" }?.credential, .automatic)
    }

    // MARK: - Test Connection and advice

    func testProbeUsesPlaceholderOnlyWhenCredentialWithholdsKey() {
        XCTAssertEqual(AIConnectionTester.unpromptedAPIKey(url: gatewayURL, api: .chatCompletions, credential: .none),
                       AITermController.selfHostedPlaceholderAPIKey)
        XCTAssertNil(AIConnectionTester.unpromptedAPIKey(url: localURL, api: .chatCompletions, credential: .vendorKey(.openAI)))
        XCTAssertNil(AIConnectionTester.unpromptedAPIKey(url: gatewayURL, api: .chatCompletions, credential: .modelKey))
    }

    func testAdviceFollowsCredential() {
        XCTAssertNotNil(AIWithheldKeyAdvice.hint(url: gatewayURL, api: .chatCompletions, credential: .none, customHeaders: []))
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: localURL, api: .chatCompletions, credential: .vendorKey(.openAI), customHeaders: []))
        XCTAssertNil(AIWithheldKeyAdvice.hint(url: gatewayURL, api: .chatCompletions, credential: .modelKey, customHeaders: []))
    }

    private func gatewayModel(credential: AIModelCredential) -> AIMetadata.Model {
        var model = AIMetadata.Model(name: "gemini/gemma-4-31b-it",
                                     contextWindowTokens: 8_192,
                                     maxResponseTokens: 8_192,
                                     url: gatewayURL,
                                     api: .chatCompletions,
                                     features: [],
                                     vectorStoreConfig: .disabled,
                                     vendor: LLMMetadata.objcManualVendor(api: .chatCompletions,
                                                                          url: gatewayURL,
                                                                          modelName: "gemini/gemma-4-31b-it"))
        model.credential = credential
        model.manualConfigurationID = "test"
        return model
    }
}
