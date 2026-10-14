//
//  AIAutomaticCredentialHostTests.swift
//  iTerm2 ModernTests
//
//  Automatic used to send the stored key of whatever vendor a manual model
//  resolved to, and an OpenAI-compatible model at an unrecognized host
//  resolves to OpenAI. So the user's OpenAI key went to OpenRouter, z.ai, or a
//  company gateway. Automatic now sends a vendor's key only to that vendor's
//  own host; elsewhere the user chooses a key explicitly. Configurations saved
//  by older builds relied on the old behavior, so they keep sending the key
//  they sent.
//

import XCTest
@testable import iTerm2SharedARC

final class AIAutomaticCredentialHostTests: XCTestCase {
    private let openAIURL = "https://api.openai.com/v1/chat/completions"
    private let azureURL = "https://myco.openai.azure.com/openai/deployments/x/chat/completions"
    private let anthropicURL = "https://api.anthropic.com/v1/messages"
    private let geminiURL = "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}"
    private let deepSeekURL = "https://api.deepseek.com/chat/completions"
    private let openRouterURL = "https://openrouter.ai/api/v1/chat/completions"
    private let zaiURL = "https://api.z.ai/api/paas/v4/chat/completions"
    private let localURL = "http://localhost:1234/v1/chat/completions"

    // MARK: - Key decision: vendor × host × choice

    private func ownHosts(_ vendor: iTermAIVendor) -> [String] {
        switch vendor {
        case .openAI: return [openAIURL, azureURL]
        case .anthropic: return [anthropicURL]
        case .gemini: return [geminiURL]
        case .deepSeek: return [deepSeekURL]
        default: return []
        }
    }

    func testAutomaticSendsVendorKeyOnlyToThatVendorsHost() {
        let allURLs = [openAIURL, azureURL, anthropicURL, geminiURL, deepSeekURL, openRouterURL, zaiURL]
        for vendor in AIModelCredential.selectableVendors {
            for url in allURLs {
                let expected: AITermController.APIKeyPolicy =
                    ownHosts(vendor).contains(url) ? .vendorKey : .placeholder(.unrecognizedHost)
                XCTAssertEqual(AITermController.apiKeyPolicy(url: url,
                                                             api: .chatCompletions,
                                                             credential: .automatic,
                                                             keyVendor: vendor),
                               expected, "\(vendor) at \(url)")
            }
        }
    }

    // Host matching must survive capitals and a DNS root dot, or a typed URL
    // would lose its key.
    func testOwnHostMatchIsNormalized() {
        XCTAssertEqual(AITermController.apiKeyPolicy(url: "https://API.OPENAI.COM./v1/chat/completions",
                                                     api: .chatCompletions,
                                                     credential: .automatic,
                                                     keyVendor: .openAI),
                       .vendorKey)
    }

    // A look-alike host is not the vendor's.
    func testLookAlikeHostIsNotOwnHost() {
        for url in ["https://api.openai.com.evil.example/v1", "https://notapi.openai.co/v1",
                    "https://anthropic.com.example.net/v1/messages"] {
            for vendor in AIModelCredential.selectableVendors {
                XCTAssertEqual(AITermController.apiKeyPolicy(url: url,
                                                             api: .chatCompletions,
                                                             credential: .automatic,
                                                             keyVendor: vendor),
                               .placeholder(.unrecognizedHost), "\(vendor) at \(url)")
            }
        }
    }

    // Any Azure customer chooses the label of a VM's public DNS
    // name (<label>.<region>.cloudapp.azure.com), so a gateway there is a third
    // party. Only Azure's AI service endpoints are OpenAI's own host.
    func testGenericAzureHostIsNotOpenAIsHost() {
        for url in ["https://qagw.eastus.cloudapp.azure.com/v1/chat/completions",
                    "https://gw.westeurope.cloudapp.azure.com/v1/chat/completions",
                    "https://evil.azure.com/v1/chat/completions",
                    "https://myco.openai.azure.com.evil.example/v1/chat/completions",
                    "https://openai.azure.com.cloudapp.azure.com/v1/chat/completions",
                    "https://myco-openai.azure.com/v1/chat/completions",
                    "https://myco.notopenai.azure.com/v1/chat/completions"] {
            for vendor in AIModelCredential.selectableVendors {
                XCTAssertEqual(AITermController.apiKeyPolicy(url: url,
                                                             api: .chatCompletions,
                                                             credential: .automatic,
                                                             keyVendor: vendor),
                               .placeholder(.unrecognizedHost), "\(vendor) at \(url)")
            }
        }
    }

    // Only the key binding is stricter: a gateway on an Azure VM still speaks
    // Azure's request format (api-key header) when the user chooses a key.
    func testGenericAzureHostKeepsAzureRequestFormat() {
        let url = "https://qagw.eastus.cloudapp.azure.com/v1/chat/completions"
        XCTAssertTrue(LLMMetadata.hostIsAzureAIAPI(url: URL(string: url)))
        XCTAssertEqual(LLMAuthorizationProvider.credentialHeaderNames(url: url, api: .chatCompletions),
                       ["api-key"])
    }

    func testAzureAIServiceEndpointsAreOpenAIsHost() {
        for url in ["https://myco.openai.azure.com/openai/deployments/x/chat/completions",
                    "https://MyCo.OpenAI.Azure.com./openai/deployments/x/chat/completions",
                    "https://myco.cognitiveservices.azure.com/openai/deployments/x/chat/completions",
                    "https://myco.services.ai.azure.com/models/chat/completions"] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url,
                                                         api: .chatCompletions,
                                                         credential: .automatic,
                                                         keyVendor: .openAI),
                           .vendorKey, url)
        }
    }

    // An explicit choice is honored on any host.
    func testExplicitVendorKeyIsSentAnywhere() {
        for vendor in AIModelCredential.selectableVendors {
            for url in [openRouterURL, zaiURL, anthropicURL, localURL] {
                XCTAssertEqual(AITermController.apiKeyPolicy(url: url,
                                                             api: .chatCompletions,
                                                             credential: .vendorKey(vendor),
                                                             keyVendor: vendor),
                               .vendorKey, "\(vendor) at \(url)")
            }
        }
    }

    func testNoneAndModelKeyAreUnaffectedByHost() {
        for url in [openAIURL, openRouterURL] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url, api: .chatCompletions, credential: .none, keyVendor: .openAI),
                           .placeholder(.noKeySelected))
            XCTAssertEqual(AITermController.apiKeyPolicy(url: url, api: .chatCompletions, credential: .modelKey, keyVendor: .openAI),
                           .modelKey)
        }
    }

    // Local endpoints never got a key under Automatic, and still don't, for
    // the same reason as before.
    func testLocalEndpointStillWithheldAsLocal() {
        for vendor in AIModelCredential.selectableVendors + [.llama] {
            XCTAssertEqual(AITermController.apiKeyPolicy(url: localURL,
                                                         api: .chatCompletions,
                                                         credential: .automatic,
                                                         keyVendor: vendor),
                           .placeholder(.localEndpoint))
        }
    }

    // Ollama's key is a self-hosted server's own token with no public host to
    // tie it to, so it is still sent to a non-local Ollama server.
    func testLlamaKeyIsNotHostBound() {
        XCTAssertEqual(AITermController.apiKeyPolicy(url: "https://ollama.example.com/api/chat",
                                                     api: .llama,
                                                     credential: .automatic,
                                                     keyVendor: .llama),
                       .vendorKey)
    }

    // A model merely named like Llama at a gateway is not an Ollama server, so
    // Automatic sends it no key (in particular not the OpenAI key that can be
    // adopted into the Llama slot).
    func testLlamaNamedModelAtGatewayGetsNoKey() {
        let model = manualModel(name: "meta-llama/llama-3.3-70b-instruct", url: openRouterURL)
        XCTAssertEqual(model.vendor, .llama)
        XCTAssertEqual(AITermController.resolvedRegistration(model: model,
                                                             fallbackVendor: .openAI,
                                                             vendorRegistration: everyKey,
                                                             modelKey: { _ in nil })?.apiKey,
                       AITermController.selfHostedPlaceholderAPIKey)
    }

    // The built-in models live on their vendors' own hosts, so the default
    // (non-manual) configuration keeps sending its key.
    func testCatalogModelsKeepTheirKeys() {
        var checked = 0
        for model in AIModelCatalog.bundledModels {
            guard let vendor = model.keyVendor, AIModelCredential.selectableVendors.contains(vendor) else {
                continue
            }
            XCTAssertEqual(AITermController.apiKeyPolicy(url: model.url,
                                                         api: model.api,
                                                         credential: model.credential,
                                                         keyVendor: vendor),
                           .vendorKey, model.name)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - Model-name inference does not choose the key's destination

    private func manualModel(name: String, url: String, api: iTermAIAPI = .chatCompletions,
                             credential: AIModelCredential = .automatic) -> AIMetadata.Model {
        var model = AIMetadata.Model(name: name,
                                     contextWindowTokens: 8_192,
                                     maxResponseTokens: 8_192,
                                     url: url,
                                     api: api,
                                     features: [],
                                     vectorStoreConfig: .disabled,
                                     vendor: LLMMetadata.objcManualVendor(api: api, url: url, modelName: name))
        model.credential = credential
        return model
    }

    private func everyKey(_ vendor: iTermAIVendor) -> AITermController.Registration? {
        return AITermController.Registration(apiKey: "sk-\(vendor.rawValue)", vendor: vendor)
    }

    func testGPTNamedModelAtGatewayGetsNoOpenAIKey() {
        let model = manualModel(name: "gpt-4o", url: openRouterURL)
        XCTAssertEqual(model.vendor, .openAI, "the protocol is still inferred as OpenAI's")
        let registration = AITermController.resolvedRegistration(model: model,
                                                                 fallbackVendor: .openAI,
                                                                 vendorRegistration: everyKey,
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, AITermController.selfHostedPlaceholderAPIKey)
    }

    func testClaudeNamedModelAtGatewayGetsNoAnthropicKey() {
        let model = manualModel(name: "anthropic/claude-sonnet-4", url: openRouterURL)
        XCTAssertEqual(model.vendor, .anthropic)
        let registration = AITermController.resolvedRegistration(model: model,
                                                                 fallbackVendor: .openAI,
                                                                 vendorRegistration: everyKey,
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, AITermController.selfHostedPlaceholderAPIKey)
    }

    func testModelAtOwnHostGetsItsKey() {
        let model = manualModel(name: "gpt-4o", url: openAIURL)
        let registration = AITermController.resolvedRegistration(model: model,
                                                                 fallbackVendor: .openAI,
                                                                 vendorRegistration: everyKey,
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, "sk-\(iTermAIVendor.openAI.rawValue)")
    }

    func testExplicitOpenAIKeyAtGatewayIsSent() {
        let model = manualModel(name: "gpt-4o", url: openRouterURL, credential: .vendorKey(.openAI))
        let registration = AITermController.resolvedRegistration(model: model,
                                                                 fallbackVendor: .openAI,
                                                                 vendorRegistration: everyKey,
                                                                 modelKey: { _ in nil })
        XCTAssertEqual(registration?.apiKey, "sk-\(iTermAIVendor.openAI.rawValue)")
    }

    // The controller's own path agrees with the shared resolver.
    func testControllerSendsPlaceholderToGateway() {
        let controller = AITermController(registration: AITermController.Registration(apiKey: "sk-openai", vendor: .openAI))
        controller.providerOverride = LLMProvider(model: manualModel(name: "gpt-4o", url: openRouterURL))
        XCTAssertEqual(controller.registration?.apiKey, AITermController.selfHostedPlaceholderAPIKey)
    }

    // Test Connection probes with what a real request would send.
    func testProbeSendsNoKeyToGatewayUnderAutomatic() {
        XCTAssertEqual(AIConnectionTester.unpromptedAPIKey(url: openRouterURL, api: .chatCompletions,
                                                           credential: .automatic, keyVendor: .openAI),
                       AITermController.selfHostedPlaceholderAPIKey)
        XCTAssertNil(AIConnectionTester.unpromptedAPIKey(url: openAIURL, api: .chatCompletions,
                                                         credential: .automatic, keyVendor: .openAI))
    }

    // MARK: - Understandable error

    func testAdviceExplainsWithheldKeyAtGateway() {
        let advice = AIWithheldKeyAdvice.amended(message: "Error from Unknown Platform: HTTP request failed with status 401.",
                                                 statusText: "HTTP request failed with status 401.",
                                                 url: openRouterURL,
                                                 api: .chatCompletions,
                                                 credential: .automatic,
                                                 keyVendor: .openAI,
                                                 customHeaders: [])
        let hint = AIWithheldKeyAdvice.hint(url: openRouterURL,
                                            api: .chatCompletions,
                                            credential: .automatic,
                                            keyVendor: .openAI,
                                            customHeaders: [])
        XCTAssertNotNil(hint)
        XCTAssertTrue(advice.hasSuffix(hint!))
        // It must not be the local-endpoint advice, which says nothing about
        // choosing a key.
        XCTAssertNotEqual(hint, AIWithheldKeyAdvice.hint(url: localURL,
                                                         api: .chatCompletions,
                                                         credential: .automatic,
                                                         keyVendor: .openAI,
                                                         customHeaders: []))
    }

    // MARK: - Configurations saved by older builds

    private func configuration(_ name: String, _ url: String, api: iTermAIAPI = .chatCompletions,
                               credential: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["id": UUID().uuidString,
                                     "name": name,
                                     "url": url,
                                     "api": Int(api.rawValue)]
        result["credential"] = credential
        return result
    }

    private func readCredential(_ configuration: [String: Any]) -> AIModelCredential {
        return LLMMetadata.credential(configuration: configuration,
                                      api: iTermAIAPI(rawValue: UInt(configuration["api"] as! Int))!,
                                      url: configuration["url"] as! String,
                                      modelName: configuration["name"] as! String)
    }

    // No stored credential: saved by a build where Automatic sent the inferred
    // vendor's key to any non-local host. It keeps sending that key.
    func testOlderConfigurationKeepsFormerKey() {
        XCTAssertEqual(readCredential(configuration("gpt-4o", openRouterURL)), .vendorKey(.openAI))
        XCTAssertEqual(readCredential(configuration("anthropic/claude-sonnet-4", openRouterURL)), .vendorKey(.anthropic))
        XCTAssertEqual(readCredential(configuration("claude-sonnet-4", "https://proxy.example.com/v1/messages", api: .anthropic)),
                       .vendorKey(.anthropic))
        XCTAssertEqual(readCredential(configuration("gpt-4o", openAIURL)), .automatic, "already on its vendor's host")
        XCTAssertEqual(readCredential(configuration("qwen", localURL)), .automatic, "local endpoints never got a key")
        XCTAssertEqual(readCredential(configuration("llama3", "https://ollama.example.com/api/chat", api: .llama)),
                       .automatic, "Ollama keys are not host-bound")
    }

    // A stored choice, Automatic included, is taken as is.
    func testStoredChoiceIsKept() {
        XCTAssertEqual(readCredential(configuration("gpt-4o", openRouterURL, credential: "automatic")), .automatic)
        XCTAssertEqual(readCredential(configuration("gpt-4o", zaiURL, credential: "none")), .none)
        XCTAssertEqual(readCredential(configuration("gpt-4o", zaiURL, credential: "model")), .modelKey)
    }

    // End to end through the prefs the app reads, including a model added
    // after the upgrade (which stores Automatic) alongside an older one.
    func testManualModelsHonorOlderAndNewerConfigurations() {
        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([configuration("old", openRouterURL),
                                    configuration("new", openRouterURL, credential: AIModelCredential.automatic.storedValue)],
                                   forKey: key)
        let models = LLMMetadata.manualModels()
        let old = models.first { $0.name == "old" }
        let new = models.first { $0.name == "new" }
        XCTAssertEqual(old?.credential, .vendorKey(.openAI))
        XCTAssertEqual(new?.credential, .automatic)
        let resolve = { (model: AIMetadata.Model?) in
            AITermController.resolvedRegistration(model: model,
                                                  fallbackVendor: .openAI,
                                                  vendorRegistration: self.everyKey,
                                                  modelKey: { _ in nil })?.apiKey
        }
        XCTAssertEqual(resolve(old), "sk-\(iTermAIVendor.openAI.rawValue)")
        XCTAssertEqual(resolve(new), AITermController.selfHostedPlaceholderAPIKey)
    }

    // The Settings editor shows (and so saves) what an older configuration sends.
    func testEffectiveStoredValueForSettings() {
        XCTAssertEqual(LLMMetadata.effectiveCredentialStoredValue(configuration: configuration("gpt-4o", openRouterURL)),
                       AIModelCredential.vendorKey(.openAI).storedValue)
        XCTAssertEqual(LLMMetadata.effectiveCredentialStoredValue(configuration: configuration("gpt-4o", openAIURL)),
                       AIModelCredential.automatic.storedValue)
        XCTAssertEqual(LLMMetadata.effectiveCredentialStoredValue(configuration: configuration("gpt-4o", zaiURL, credential: "none")),
                       "none")
    }

    // The single legacy manual model (stored in separate prefs, from before
    // the list of models existed) can only have been set up by an older build,
    // so it keeps sending the key it always sent.
    func testLegacyManualModelKeepsFormerKey() {
        let keys = [kPreferenceKeyAIManualModelConfigurations, kPreferenceKeyUseRecommendedAIModel,
                    kPreferenceKeyAITermURL, kPreferenceKeyAIModel, kPreferenceKeyAITermAPI]
        let saved = keys.map { iTermPreferences.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                iTermPreferences.setObject(value, forKey: key)
            }
        }
        iTermPreferences.setObject([], forKey: kPreferenceKeyAIManualModelConfigurations)
        iTermPreferences.setBool(false, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setString(openRouterURL, forKey: kPreferenceKeyAITermURL)
        iTermPreferences.setString("gpt-4o", forKey: kPreferenceKeyAIModel)
        iTermPreferences.setUnsignedInteger(UInt(iTermAIAPI.chatCompletions.rawValue), forKey: kPreferenceKeyAITermAPI)

        let model = LLMMetadata.manualModels().first
        XCTAssertEqual(model?.url, openRouterURL)
        XCTAssertEqual(model?.credential, .vendorKey(.openAI))

        iTermPreferences.setString(openAIURL, forKey: kPreferenceKeyAITermURL)
        XCTAssertEqual(LLMMetadata.manualModels().first?.credential, .automatic)
    }
}
