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

    // A cache that does no real network or timer work by default, so tests are
    // deterministic and never touch the network. Individual tests override
    // `fetcher`/`retryScheduler` where they need to drive them.
    private func makeCache() -> OllamaModelCache {
        let cache = OllamaModelCache()
        cache.fetcher = { _, _, _, _ in }        // never completes -> no network
        cache.retryScheduler = { _, _ in }        // no real timers
        return cache
    }

    func test_update_thenRead_returnsModels() {
        let cache = makeCache()
        cache.update(endpoint: "e", models: models("e"))
        XCTAssertEqual(cache.models(forEndpoint: "e").map { $0.name }, ["qwen3.5:4b"])
    }

    func test_update_postsChangeNotificationWhenListChanges() {
        let cache = makeCache()
        expectation(forNotification: OllamaModelCache.didChangeNotification, object: nil)
        cache.update(endpoint: "e", models: models("e"))  // nil -> [model] is a change
        waitForExpectations(timeout: 1)
    }

    func test_update_sameModels_doesNotPost() {
        let cache = makeCache()
        cache.update(endpoint: "e", models: models("e"))
        // Scope to this endpoint's object: the notification carries the changed
        // endpoint, so a shared-cache change from another test can't trip this
        // inverted expectation.
        let inverted = expectation(forNotification: OllamaModelCache.didChangeNotification, object: "e")
        inverted.isInverted = true
        cache.update(endpoint: "e", models: models("e"))  // identical: no change, no post
        waitForExpectations(timeout: 0.3)
    }

    // A FAILED fetch must not wedge the picker empty: reads keep retrying (after a
    // short backoff), and a SUCCESS is re-fetched only after the TTL. This is the
    // launch-before-Ollama scenario.
    func test_failedFetch_retriesAfterBackoff_successRefreshesAfterTTL() {
        var now = Date()
        let cache = makeCache()
        cache.nowProvider = { now }

        XCTAssertTrue(cache.shouldRefresh(endpoint: "e"), "never fetched -> refresh")

        cache.update(endpoint: "e", result: nil)  // failure (server down)
        XCTAssertFalse(cache.shouldRefresh(endpoint: "e"), "within failure backoff")
        now = now.addingTimeInterval(6)
        XCTAssertTrue(cache.shouldRefresh(endpoint: "e"), "failed fetch must retry after the backoff")

        cache.update(endpoint: "e", result: models("e"))  // success
        XCTAssertFalse(cache.shouldRefresh(endpoint: "e"), "fresh success not re-fetched")
        now = now.addingTimeInterval(400)
        XCTAssertTrue(cache.shouldRefresh(endpoint: "e"), "stale success re-fetched after TTL")
    }

    // A transient failure after a good fetch keeps the last good models.
    func test_failure_keepsPreviousModels() {
        let cache = makeCache()
        cache.update(endpoint: "e", result: models("e"))
        cache.update(endpoint: "e", result: nil)
        XCTAssertEqual(cache.models(forEndpoint: "e").map { $0.name }, ["qwen3.5:4b"],
                       "a transient failure must not drop the last good models")
    }

    // An empty-but-reachable server is a success (cached, not retried until TTL),
    // distinct from a failure.
    func test_emptyServer_isSuccess_notImmediatelyRetried() {
        var now = Date()
        let cache = makeCache()
        cache.nowProvider = { now }
        cache.update(endpoint: "e", result: [])
        XCTAssertFalse(cache.shouldRefresh(endpoint: "e"), "empty-but-reachable is a success")
        now = now.addingTimeInterval(400)
        XCTAssertTrue(cache.shouldRefresh(endpoint: "e"), "re-fetched after TTL to catch newly pulled models")
    }

    // A failed fetch schedules a self-healing retry, bounded so a permanently-down
    // server isn't probed forever; a success resets the budget.
    func test_failedFetch_schedulesBoundedSelfHealingRetry() {
        let cache = makeCache()
        var scheduled = 0
        cache.retryScheduler = { _, _ in scheduled += 1 }  // record, don't run
        for _ in 0..<20 { cache.update(endpoint: "e", result: nil) }
        XCTAssertEqual(scheduled, cache.maxAutoRetries, "auto-retry must stop after the cap")

        cache.update(endpoint: "e", result: [])  // success resets the failure budget
        cache.update(endpoint: "e", result: nil)
        XCTAssertEqual(scheduled, cache.maxAutoRetries + 1, "a success re-arms the retry")
    }

    // A forced refresh runs alongside an in-flight background one, so two fetches
    // for one endpoint can be outstanding at once. If both fail (server down), that
    // is ONE failed round, not two: it must not double-count the failure budget nor
    // schedule two retries.
    func test_concurrentFailures_countAsOneRound() {
        let cache = makeCache()
        var scheduled = 0
        var completions: [([AIMetadata.Model]?) -> Void] = []
        cache.fetcher = { _, _, _, completion in completions.append(completion) }
        cache.retryScheduler = { _, _ in scheduled += 1 }

        cache.refresh(endpoint: "e")               // background, in flight
        cache.refresh(endpoint: "e", force: true)  // forced probe, also in flight
        XCTAssertEqual(completions.count, 2, "the forced refresh runs alongside the background one")

        completions[0](nil)  // first fails
        completions[1](nil)  // second fails
        XCTAssertEqual(scheduled, 1, "two concurrent failures are one round, not two retries")

        // And the budget is intact: it still takes maxAutoRetries more failed rounds
        // (each a single fetch) to hit the cap.
        for _ in 0..<(cache.maxAutoRetries * 2) { cache.update(endpoint: "e", result: nil) }
        XCTAssertEqual(scheduled, cache.maxAutoRetries, "the cap counts rounds, not raw concurrent failures")
    }

    // End to end: a failure at launch, then the server comes up, and the scheduled
    // retry repopulates the cache on its own (self-healing).
    func test_selfHeals_whenServerComesUp() {
        let cache = makeCache()
        var scheduledBlocks: [() -> Void] = []
        cache.retryScheduler = { _, block in scheduledBlocks.append(block) }
        var nextResult: [AIMetadata.Model]? = nil  // server down
        cache.fetcher = { _, _, _, completion in completion(nextResult) }

        cache.refresh(endpoint: "e")  // fails -> schedules a retry
        XCTAssertTrue(cache.models(forEndpoint: "e").isEmpty)
        XCTAssertEqual(scheduledBlocks.count, 1)

        nextResult = models("e")      // server came up
        scheduledBlocks[0]()          // the scheduled retry runs -> succeeds
        XCTAssertEqual(cache.models(forEndpoint: "e").map { $0.name }, ["qwen3.5:4b"],
                       "the picker should repopulate on its own once the server is up")
    }

    // A user-initiated (forced) refresh bypasses the in-flight coalescing so it
    // can't be swallowed behind a slow background refresh that then fails.
    func test_refresh_force_bypassesCoalescing() {
        let cache = makeCache()
        var fetchCount = 0
        cache.fetcher = { _, _, _, _ in fetchCount += 1 }  // never completes -> stays in-flight

        cache.refresh(endpoint: "e")
        XCTAssertEqual(fetchCount, 1)
        cache.refresh(endpoint: "e")  // coalesced behind the in-flight one
        XCTAssertEqual(fetchCount, 1)
        cache.refresh(endpoint: "e", force: true)
        XCTAssertEqual(fetchCount, 2, "forced refresh must issue even with one in flight")
    }

    // Persisted models restore synchronously (with capabilities), so a chat pinned
    // to a discovered tag resolves at launch instead of routing to the default
    // provider while /api/tags is fetched.
    func test_persistenceRoundTrip_restoresModelsSynchronously() {
        let endpoint = "http://persist-test:11434/api/chat"
        let source = makeCache()
        source.update(endpoint: endpoint, models: models(endpoint))

        let restored = makeCache()
        restored.restore(from: source.persistedRepresentation())

        let m = restored.models(forEndpoint: endpoint)
        XCTAssertEqual(m.map { $0.name }, ["qwen3.5:4b"])
        XCTAssertEqual(m.first?.url, endpoint)
        XCTAssertEqual(m.first?.contextWindowTokens, 262_144)
        XCTAssertTrue(m.first?.features.contains(.vision) ?? false, "capabilities survive persistence")
        XCTAssertTrue(m.first?.features.contains(.configurableThinking) ?? false)
    }

    // Persistence must track only currently-configured endpoints, so probing
    // unsaved URLs or deleting an entry doesn't grow the blob without bound.
    func test_endpointsPruned_keepsOnlyConfigured() {
        let representation: [String: Any] = [
            "http://a/api/chat": [["name": "m"]],
            "http://b/api/chat": [["name": "m"]],
            "http://gone/api/chat": [["name": "m"]],
        ]
        let pruned = OllamaModelCache.endpointsPruned(representation,
                                                      keeping: ["http://a/api/chat", "http://b/api/chat"])
        XCTAssertEqual(Set(pruned.keys), ["http://a/api/chat", "http://b/api/chat"],
                       "a since-removed endpoint must be dropped from persistence")
    }

    // The change notification carries the endpoint so observers can scope rebuilds.
    func test_update_notificationCarriesEndpoint() {
        let cache = makeCache()
        expectation(forNotification: OllamaModelCache.didChangeNotification, object: "ep1")
        cache.update(endpoint: "ep1", models: models("ep1"))
        waitForExpectations(timeout: 1)
    }

    // Two dynamic servers exposing the same tag must not collide: each must remain
    // reachable (its own url) with a distinct identity, while still sending the raw
    // tag on the wire.
    func test_twoDynamicServers_sameTag_disambiguatedByEndpoint() {
        let epA = "http://serverA:11434/api/chat"
        let epB = "http://serverB:11434/api/chat"
        let body = { (ep: String) in
            Data("{\"models\":[{\"name\":\"llama3.3\",\"capabilities\":[\"tools\"],\"details\":{\"context_length\":4096}}]}".utf8)
        }
        OllamaModelCache.shared.update(endpoint: epA, models: OllamaModelDiscovery.models(fromTagsResponse: body(epA), endpoint: epA))
        OllamaModelCache.shared.update(endpoint: epB, models: OllamaModelDiscovery.models(fromTagsResponse: body(epB), endpoint: epB))
        defer {
            OllamaModelCache.shared.update(endpoint: epA, models: [])
            OllamaModelCache.shared.update(endpoint: epB, models: [])
        }

        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([
            ["url": epA, "dynamicModels": true, "api": Int(iTermAIAPI.llama.rawValue)],
            ["url": epB, "dynamicModels": true, "api": Int(iTermAIAPI.llama.rawValue)],
        ], forKey: key)

        let models = LLMMetadata.manualModels()
        let llama = models.filter { ($0.wireModelName ?? $0.name) == "llama3.3" }
        XCTAssertEqual(llama.count, 2, "both servers' llama3.3 should be present")
        XCTAssertEqual(Set(llama.map { $0.name }).count, 2, "identities must be distinct (no ambiguous .first match)")
        XCTAssertEqual(Set(llama.map { $0.url }), [epA, epB], "each must keep its own endpoint")
        XCTAssertTrue(llama.allSatisfy { $0.effectiveModelName == "llama3.3" },
                      "each must still send the raw tag on the wire")
    }

    // A manual dynamic tag that collides with a BUILT-IN default-endpoint tag must
    // also be qualified. Otherwise (built-in Ollama local qwen3 + a remote manual
    // dynamic qwen3) there are two bare "qwen3" across the two merged lists, and
    // "manual wins" name resolution silently routes a message meant for the local
    // server to the remote one.
    func test_manualDynamicTag_collidingWithBuiltInDefault_isQualified() {
        let remote = "http://gpu2:11434/api/chat"
        let tag = "{\"models\":[{\"name\":\"qwen3\",\"capabilities\":[\"tools\"],\"details\":{\"context_length\":4096}}]}"
        // Built-in default endpoint has qwen3; remote manual dynamic entry also has qwen3.
        OllamaModelCache.shared.update(endpoint: LLMMetadata.defaultOllamaEndpoint,
                                       models: OllamaModelDiscovery.models(fromTagsResponse: Data(tag.utf8),
                                                                          endpoint: LLMMetadata.defaultOllamaEndpoint))
        OllamaModelCache.shared.update(endpoint: remote,
                                       models: OllamaModelDiscovery.models(fromTagsResponse: Data(tag.utf8), endpoint: remote))
        defer {
            OllamaModelCache.shared.update(endpoint: LLMMetadata.defaultOllamaEndpoint, models: [])
            OllamaModelCache.shared.update(endpoint: remote, models: [])
        }

        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([
            ["url": remote, "dynamicModels": true, "api": Int(iTermAIAPI.llama.rawValue)],
        ], forKey: key)

        // The built-in list keeps the clean local tag...
        XCTAssertTrue(LLMMetadata.discoveredOllamaModels().contains { $0.name == "qwen3" },
                      "the local built-in model keeps its clean tag")
        // ...but the remote manual model must NOT collide with it by bare name.
        let manual = LLMMetadata.manualModels()
        XCTAssertFalse(manual.contains { $0.name == "qwen3" },
                       "remote manual qwen3 must be qualified so it can't shadow the local built-in qwen3")
        let remoteModel = manual.first { $0.url == remote }
        XCTAssertNotNil(remoteModel)
        XCTAssertEqual(remoteModel?.effectiveModelName, "qwen3",
                       "the qualified remote model still sends the raw tag on the wire")
    }

    // The first-class Ollama vendor resolves its models from discovery at the
    // default endpoint, not a static catalog.
    func test_ollamaVendor_resolvesModelsFromDiscovery() {
        let endpoint = LLMMetadata.defaultOllamaEndpoint
        OllamaModelCache.shared.update(endpoint: endpoint, models: models(endpoint))
        defer { OllamaModelCache.shared.update(endpoint: endpoint, models: []) }

        let alternates = LLMMetadata.alternateModels(for: .llama)
        XCTAssertTrue(alternates.contains { $0.name == "qwen3.5:4b" },
                      "the Ollama vendor's models come from discovery")
        XCTAssertEqual(LLMMetadata.recommendedModel(for: .llama)?.name, alternates.first?.name,
                       "the default is the first discovered model")
    }

    // The regression: recommended-Ollama with EMPTY discovery must resolve to an
    // Ollama-vendored model (a placeholder), never fall through to a cloud default
    // (which would silently send a local-model message to e.g. OpenAI).
    func test_recommendedOllama_emptyDiscovery_staysOnOllama() {
        OllamaModelCache.shared.update(endpoint: LLMMetadata.defaultOllamaEndpoint, models: [])  // reachable, empty
        defer { OllamaModelCache.shared.update(endpoint: LLMMetadata.defaultOllamaEndpoint, models: []) }

        let savedRecommended = iTermPreferences.object(forKey: kPreferenceKeyUseRecommendedAIModel)
        let savedVendor = iTermPreferences.object(forKey: kPreferenceKeyAIVendor)
        defer {
            iTermPreferences.setObject(savedRecommended, forKey: kPreferenceKeyUseRecommendedAIModel)
            iTermPreferences.setObject(savedVendor, forKey: kPreferenceKeyAIVendor)
        }
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(Int(iTermAIVendor.llama.rawValue), forKey: kPreferenceKeyAIVendor)

        let model = LLMMetadata.model()
        XCTAssertEqual(model?.vendor, .llama,
                       "recommended Ollama with no discovered models must stay Ollama, not cross to a cloud vendor")
        XCTAssertEqual(model?.api, .llama)
    }

    // The default endpoint's discovered models are ALWAYS displayable (a chat can
    // pin the built-in Ollama vendor even when the global default is a different
    // vendor), so the default endpoint must be in the scoping set regardless of
    // whether Ollama is the recommended global default. Otherwise the ChatToolbar
    // observer drops a real discovery update for that chat's picker.
    func test_dynamicOllamaEndpoints_includesDefault_evenWhenNotRecommended() {
        let savedRecommended = iTermPreferences.object(forKey: kPreferenceKeyUseRecommendedAIModel)
        let savedVendor = iTermPreferences.object(forKey: kPreferenceKeyAIVendor)
        let key = kPreferenceKeyAIManualModelConfigurations
        let savedManual = iTermPreferences.object(forKey: key)
        defer {
            iTermPreferences.setObject(savedRecommended, forKey: kPreferenceKeyUseRecommendedAIModel)
            iTermPreferences.setObject(savedVendor, forKey: kPreferenceKeyAIVendor)
            iTermPreferences.setObject(savedManual, forKey: key)
        }
        // Global default is a non-Ollama recommended vendor and there are no manual
        // dynamic entries: the default endpoint must still be scoped in.
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(Int(iTermAIVendor.openAI.rawValue), forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setObject([], forKey: key)

        XCTAssertTrue(LLMMetadata.dynamicOllamaEndpoints().contains(LLMMetadata.defaultOllamaEndpoint),
                      "the default Ollama endpoint is always displayable and must be scoped in")
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

    // A dynamic entry that names ONE discovered model (the user picked it from the
    // editor popup) exposes just that model, not every tag. An empty selection
    // still means whole-server (backward compatible).
    func test_dynamicOllamaEntry_withSelectedModel_exposesOnlyThatModel() {
        let endpoint = "http://dyn-pick-test.local:11434/api/chat"
        let fixture = Data("""
        {"models":[{"name":"m1","capabilities":["tools"],"details":{"context_length":4096}},
                   {"name":"m2","capabilities":["vision"],"details":{"context_length":8192}}]}
        """.utf8)
        OllamaModelCache.shared.update(endpoint: endpoint,
                                       models: OllamaModelDiscovery.models(fromTagsResponse: fixture, endpoint: endpoint))
        defer { OllamaModelCache.shared.update(endpoint: endpoint, models: []) }

        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([[
            "url": endpoint,
            "dynamicModels": true,
            "dynamicSelectedModel": "m2",
            "api": Int(iTermAIAPI.llama.rawValue),
        ]], forKey: key)

        let models = LLMMetadata.manualModels()
        XCTAssertEqual(models.map { $0.name }, ["m2"],
                       "a dynamic entry with a chosen model must expose only that one")
        XCTAssertEqual(models.first?.effectiveModelName, "m2", "the chosen tag still goes on the wire")
        XCTAssertTrue(models.first?.features.contains(.vision) ?? false,
                      "the chosen model keeps its discovered capabilities")
    }

    // MARK: - Regular/Budget model selection for the Ollama vendor

    private func multiModelFixture() -> Data {
        Data("""
        {"models":[
          {"name":"alpha:1b","capabilities":["tools"],"details":{"context_length":4096}},
          {"name":"zeta:7b","capabilities":["tools","vision"],"details":{"context_length":8192}}
        ]}
        """.utf8)
    }

    // Seed the default endpoint with two models, make the Ollama vendor the
    // default, set the regular/economy prefs, run `body`, then restore everything.
    private func withOllamaVendorDefault(regular: String, economy: String, _ body: () -> Void) {
        let endpoint = LLMMetadata.defaultOllamaEndpoint
        OllamaModelCache.shared.update(
            endpoint: endpoint,
            models: OllamaModelDiscovery.models(fromTagsResponse: multiModelFixture(), endpoint: endpoint))

        let keys = [kPreferenceKeyUseRecommendedAIModel, kPreferenceKeyAIVendor,
                    kPreferenceKeyAIOllamaRegularModel, kPreferenceKeyAIOllamaEconomyModel]
        let saved = keys.map { iTermPreferences.object(forKey: $0) }
        defer {
            for (i, key) in keys.enumerated() { iTermPreferences.setObject(saved[i], forKey: key) }
            OllamaModelCache.shared.update(endpoint: endpoint, models: [])
        }
        iTermPreferences.setBool(true, forKey: kPreferenceKeyUseRecommendedAIModel)
        iTermPreferences.setObject(Int(iTermAIVendor.llama.rawValue), forKey: kPreferenceKeyAIVendor)
        iTermPreferences.setObject(regular, forKey: kPreferenceKeyAIOllamaRegularModel)
        iTermPreferences.setObject(economy, forKey: kPreferenceKeyAIOllamaEconomyModel)
        body()
    }

    func test_recommendedOllama_honorsChosenRegularModel() {
        withOllamaVendorDefault(regular: "zeta:7b", economy: "") {
            XCTAssertEqual(LLMMetadata.recommendedModel(for: .llama)?.name, "zeta:7b",
                           "the explicitly chosen regular model is the default")
        }
    }

    func test_recommendedOllama_unsetRegular_usesLexicographicFirst() {
        withOllamaVendorDefault(regular: "", economy: "") {
            XCTAssertEqual(LLMMetadata.recommendedModel(for: .llama)?.name, "alpha:1b",
                           "with no chosen regular model, the lexicographically-first tag is the default")
        }
    }

    func test_recommendedOllama_staleRegularChoice_fallsBackToFirst() {
        withOllamaVendorDefault(regular: "removed:99b", economy: "") {
            XCTAssertEqual(LLMMetadata.recommendedModel(for: .llama)?.name, "alpha:1b",
                           "a chosen model that is no longer installed falls back to the first tag")
        }
    }

    func test_ollamaVendorEconomyModel_chosenAndInstalled() {
        withOllamaVendorDefault(regular: "zeta:7b", economy: "alpha:1b") {
            XCTAssertTrue(LLMMetadata.isOllamaVendorDefault)
            XCTAssertEqual(LLMMetadata.ollamaVendorEconomyModel()?.name, "alpha:1b")
        }
    }

    func test_ollamaVendorEconomyModel_sameAsRegular_isNil() {
        withOllamaVendorDefault(regular: "zeta:7b", economy: "") {
            XCTAssertNil(LLMMetadata.ollamaVendorEconomyModel(),
                         "an empty budget pref means same-as-regular, i.e. no distinct economy model")
        }
    }

    func test_ollamaVendorEconomyModel_staleChoice_isNil() {
        withOllamaVendorDefault(regular: "zeta:7b", economy: "removed:99b") {
            XCTAssertNil(LLMMetadata.ollamaVendorEconomyModel(),
                         "a budget choice that is no longer installed resolves to nil")
        }
    }
}
