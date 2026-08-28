//
//  OllamaModelCacheTests.swift
//  iTerm2 ModernTests
//
//  The cache's synchronous read / async update contract and its change
//  notification (the network refresh is exercised live in AILiveOllamaTests).
//

import XCTest
@testable import iTerm2SharedARC

final class OllamaModelCacheTests: XCTestCase {
    private let fixture = Data("""
    {"models":[{"name":"qwen3.5:4b","capabilities":["vision","tools","thinking"],"details":{"context_length":262144}}]}
    """.utf8)

    private func models(_ endpoint: String) -> [AIMetadata.Model] {
        OllamaModelDiscovery.models(fromTagsResponse: fixture, endpoint: endpoint)
    }

    func test_update_thenRead_returnsModels() {
        let cache = OllamaModelCache()
        cache.update(endpoint: "e", models: models("e"))
        XCTAssertEqual(cache.models(forEndpoint: "e").map { $0.name }, ["qwen3.5:4b"])
    }

    func test_update_postsChangeNotificationWhenListChanges() {
        let cache = OllamaModelCache()
        expectation(forNotification: OllamaModelCache.didChangeNotification, object: nil)
        cache.update(endpoint: "e", models: models("e"))  // nil -> [model] is a change
        waitForExpectations(timeout: 1)
    }

    func test_update_sameModels_doesNotPost() {
        let cache = OllamaModelCache()
        cache.update(endpoint: "e", models: models("e"))
        let inverted = expectation(forNotification: OllamaModelCache.didChangeNotification, object: nil)
        inverted.isInverted = true
        cache.update(endpoint: "e", models: models("e"))  // identical: no change, no post
        waitForExpectations(timeout: 0.3)
    }

    // Integration: a dynamic Ollama manual entry expands (via the shared cache)
    // into one catalog model per discovered tag, with capabilities, so the
    // provider picker shows them without any per-model config.
    func test_dynamicOllamaEntry_expandsToDiscoveredModels() {
        let endpoint = "http://dyn-provider-test.local:11434/api/chat"
        let fixture = Data("""
        {"models":[{"name":"m1","capabilities":["tools"],"details":{"context_length":4096}},
                   {"name":"m2","capabilities":["vision"],"details":{"context_length":8192}}]}
        """.utf8)
        OllamaModelCache.shared.update(endpoint: endpoint,
                                       models: OllamaModelDiscovery.models(fromTagsResponse: fixture, endpoint: endpoint))

        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([[
            "url": endpoint,
            "dynamicModels": true,
            "api": Int(iTermAIAPI.llama.rawValue),
        ]], forKey: key)

        let models = LLMMetadata.manualModels()
        XCTAssertEqual(Set(models.map { $0.name }), ["m1", "m2"],
                       "dynamic entry did not expand to the discovered tags")
        let m1 = try? XCTUnwrap(models.first { $0.name == "m1" })
        XCTAssertEqual(m1?.api, .llama)
        XCTAssertTrue(m1?.features.contains(.functionCalling) ?? false)
    }
}
