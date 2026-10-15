//
//  OllamaLocalModelRoutingTests.swift
//  iTerm2 ModernTests
//
//  A chat pinned to the built-in Ollama vendor must never be routed to the
//  global default (possibly a cloud vendor) when no local model is available.
//  QA finding F-283.
//

import XCTest
@testable import iTerm2SharedARC

final class OllamaLocalModelRoutingTests: XCTestCase {
    private let endpoint = LLMMetadata.defaultOllamaEndpoint
    private var savedRecommended: Any?
    private var savedVendor: Any?
    private var savedRegularModel: Any?
    private var savedFetcher: ((String, [[String: String]], TimeInterval, @escaping ([AIMetadata.Model]?) -> Void) -> Void)?
    private var savedRetryScheduler: ((TimeInterval, @escaping () -> Void) -> Void)?
    private var restoreCacheEntry: (() -> Void)?

    override func setUp() {
        super.setUp()
        savedRecommended = iTermPreferences.object(forKey: kPreferenceKeyUseRecommendedAIModel)
        savedVendor = iTermPreferences.object(forKey: kPreferenceKeyAIVendor)
        savedRegularModel = iTermPreferences.object(forKey: kPreferenceKeyAIOllamaRegularModel)
        // The reported configuration: the global default is the recommended
        // OpenAI model.
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(Int(iTermAIVendor.openAI.rawValue), forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setObject(nil, forKey: kPreferenceKeyAIOllamaRegularModel)
        // Never reach a real Ollama server, and start from a completed, empty
        // discovery regardless of what the host app restored from user defaults.
        let cache = OllamaModelCache.shared
        savedFetcher = cache.fetcher
        savedRetryScheduler = cache.retryScheduler
        cache.fetcher = { _, _, _, _ in }
        cache.retryScheduler = { _, _ in }
        restoreCacheEntry = cache.replaceModelsForTesting([], endpoint: endpoint)
    }

    override func tearDown() {
        let cache = OllamaModelCache.shared
        restoreCacheEntry?()
        if let savedFetcher {
            cache.fetcher = savedFetcher
        }
        if let savedRetryScheduler {
            cache.retryScheduler = savedRetryScheduler
        }
        iTermPreferences.setObject(savedRecommended, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(savedVendor, forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setObject(savedRegularModel, forKey: kPreferenceKeyAIOllamaRegularModel)
        super.tearDown()
    }

    private func installLocalModel() {
        let body = Data("""
        {"models":[{"name":"qwen3.5:4b","capabilities":["tools"],"details":{"context_length":32768}}]}
        """.utf8)
        // tearDown's restore puts back the entry saved in setUp.
        _ = OllamaModelCache.shared.replaceModelsForTesting(
            OllamaModelDiscovery.models(fromTagsResponse: body, endpoint: endpoint),
            endpoint: endpoint)
    }

    // The reported bug: picking “Llama (Local)” with Ollama not running pins the
    // chat to the discovery placeholder. Routing must fail the turn instead of
    // returning a nil override, which means “use the global default” (OpenAI).
    func test_placeholder_noLocalModel_doesNotRouteToDefault() {
        let pinned = LLMMetadata.recommendedModel(for: .llama)?.name
        XCTAssertEqual(pinned, LLMMetadata.pendingOllamaModelName)
        XCTAssertEqual(LLMMetadata.model()?.vendor, .openAI, "precondition: the global default is a cloud vendor")

        switch AIConversation.pinnedProviderOverride(modelName: LLMMetadata.pendingOllamaModelName) {
        case .success(let provider):
            XCTFail("a local-model chat with no local model must not be sent; got override \(String(describing: provider?.model.name)) (nil means the cloud default)")
        case .failure(let error):
            XCTAssertFalse(error.message.isEmpty)
        }
        XCTAssertNotNil(LLMMetadata.unavailableLocalModelError(forPinnedModelNamed: LLMMetadata.pendingOllamaModelName))
    }

    // An Ollama tag that is no longer available (server cleared) must not fall
    // through to the cloud default either.
    func test_missingOllamaTag_doesNotRouteToDefault() {
        let name = "llama-f283-routing-test:1b"
        XCTAssertNil(LLMMetadata.model(named: name))
        guard case .failure = AIConversation.pinnedProviderOverride(modelName: name) else {
            XCTFail("an unavailable Ollama tag must not route to the global default")
            return
        }
    }

    // Once a local model is discovered, the placeholder pin resolves to it, so a
    // chat that picked Llama (Local) before Ollama started works afterward.
    func test_placeholder_withLocalModel_routesToLocalServer() {
        installLocalModel()
        let resolved = LLMMetadata.model(named: LLMMetadata.pendingOllamaModelName)
        XCTAssertEqual(resolved?.name, "qwen3.5:4b")
        XCTAssertEqual(resolved?.vendor, .llama)
        XCTAssertEqual(resolved?.url, endpoint)
        XCTAssertNil(LLMMetadata.unavailableLocalModelError(forPinnedModelNamed: LLMMetadata.pendingOllamaModelName))

        switch AIConversation.pinnedProviderOverride(modelName: LLMMetadata.pendingOllamaModelName) {
        case .success(let provider):
            XCTAssertEqual(provider?.model.vendor, .llama)
            XCTAssertEqual(provider?.model.url, endpoint)
        case .failure(let error):
            XCTFail("unexpected failure: \(error)")
        }
    }

    // A discovered tag still resolves directly.
    func test_discoveredTag_routesToLocalServer() {
        installLocalModel()
        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: "qwen3.5:4b") else {
            XCTFail("a discovered tag must resolve")
            return
        }
        XCTAssertEqual(provider?.model.vendor, .llama)
    }

    // Cloud and unclassifiable names keep their existing behavior.
    func test_nonOllamaNames_unchanged() {
        let cloud = AIMetadata.recommendedOpenAIModel.name
        guard case .success(let provider) = AIConversation.pinnedProviderOverride(modelName: cloud) else {
            XCTFail("a catalog model must resolve")
            return
        }
        XCTAssertEqual(provider?.model.name, cloud)
        XCTAssertNil(LLMMetadata.unavailableLocalModelError(forPinnedModelNamed: "some-retired-model"))
        guard case .success(nil) = AIConversation.pinnedProviderOverride(modelName: "some-retired-model") else {
            XCTFail("an unclassifiable retired model keeps falling back to the global default")
            return
        }
    }

    // Naming a chat sends its content, so it must go to the chat's own model,
    // not the global default.
    @MainActor
    func test_renamingConversation_usesChatModel() {
        let messages = [AITermController.Message(role: .user, content: "private question")]
        XCTAssertEqual(ChatAgent.renamingConversation(messages: messages, modelName: "qwen3.5:4b", modelVendor: .llama).model,
                       "qwen3.5:4b")
        XCTAssertNil(ChatAgent.renamingConversation(messages: messages, modelName: nil, modelVendor: nil).model)
    }

    // The icon prompt carries the chat's title, so it goes to the chat's model.
    func test_iconConversation_usesChatModel() {
        XCTAssertEqual(ChatIconGenerator.svgConversation(prompt: "draw", modelName: "qwen3.5:4b", modelVendor: .llama).model,
                       "qwen3.5:4b")
    }
}
