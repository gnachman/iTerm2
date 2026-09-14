//
//  ChatViewControllerProviderAvailabilityTests.swift
//  iTerm2 ModernTests
//
//  The provider picker decides which vendors to offer via
//  ChatViewController.providerIsAvailable(_:alternateModels:apiKey:). The
//  built-in Ollama vendor is self-hosted and keyless, so it must stay
//  selectable even when discovery is empty (server down at launch, or before
//  the first /api/tags fetch lands) - the very window the self-healing cache
//  exists to cover. A cloud vendor, by contrast, needs both a model list and a
//  non-empty API key.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ChatViewControllerProviderAvailabilityTests: XCTestCase {

    private func model(_ name: String, vendor: iTermAIVendor) -> AIMetadata.Model {
        AIMetadata.Model(name: name,
                         contextWindowTokens: 8192,
                         maxResponseTokens: 8192,
                         url: "http://localhost:11434/api/chat",
                         api: .llama,
                         features: [.streaming],
                         vectorStoreConfig: .disabled,
                         vendor: vendor)
    }

    // The regression: with empty discovery the Ollama vendor must remain
    // available (keyless, self-hosted). The bug is that the empty-models guard
    // runs before the `.llama` keyless exemption, so it is dropped from the
    // picker exactly when the server is down at launch.
    func test_llama_withEmptyDiscovery_isStillAvailable() {
        XCTAssertTrue(
            ChatViewController.providerIsAvailable(.llama, alternateModels: [], apiKey: nil),
            "Ollama is keyless/self-hosted and must stay selectable even with no discovered models")
    }

    // With discovered models, Ollama is available regardless of key (it is
    // keyless).
    func test_llama_withDiscoveredModels_isAvailable() {
        XCTAssertTrue(
            ChatViewController.providerIsAvailable(.llama,
                                                   alternateModels: [model("qwen3", vendor: .llama)],
                                                   apiKey: nil))
    }

    // A cloud vendor needs BOTH a model list and a non-empty key: no key (or a
    // whitespace-only key) means unavailable; a real key makes it available.
    func test_cloudVendor_requiresModelsAndKey() {
        let gpt = model("gpt-4o", vendor: .openAI)
        XCTAssertFalse(
            ChatViewController.providerIsAvailable(.openAI, alternateModels: [gpt], apiKey: nil),
            "a cloud vendor with no API key is unavailable")
        XCTAssertFalse(
            ChatViewController.providerIsAvailable(.openAI, alternateModels: [gpt], apiKey: "   "),
            "a whitespace-only key is treated as no key")
        XCTAssertFalse(
            ChatViewController.providerIsAvailable(.openAI, alternateModels: [], apiKey: "sk-real"),
            "a cloud vendor with no models is unavailable")
        XCTAssertTrue(
            ChatViewController.providerIsAvailable(.openAI, alternateModels: [gpt], apiKey: "sk-real"),
            "a cloud vendor with models and a real key is available")
    }
}
