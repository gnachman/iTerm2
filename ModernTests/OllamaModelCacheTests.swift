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

    // A batch of concurrent fetches where at least one SUCCEEDS must not schedule
    // a self-healing failure retry just because a sibling (the last to drain)
    // failed. The success already refreshed the models and reset the failure
    // budget; the trailing failure re-incrementing consecutiveFailures and
    // arming a retry defeats "count concurrent failures as one round" and fires a
    // spurious /api/tags probe against a healthy endpoint.
    func test_batchWithOneSuccess_doesNotScheduleFailureRetry() {
        let cache = makeCache()
        var scheduled = 0
        var completions: [([AIMetadata.Model]?) -> Void] = []
        cache.fetcher = { _, _, _, completion in completions.append(completion) }
        cache.retryScheduler = { _, _ in scheduled += 1 }

        cache.refresh(endpoint: "e")               // background, in flight
        cache.refresh(endpoint: "e", force: true)  // forced probe, also in flight
        XCTAssertEqual(completions.count, 2, "the forced refresh runs alongside the background one")

        completions[0](models("e"))  // first fetch SUCCEEDS
        completions[1](nil)          // sibling fails, and is the last of the batch

        XCTAssertEqual(scheduled, 0,
                       "a batch that already succeeded must not schedule a failure retry")
        XCTAssertEqual(cache.models(forEndpoint: "e").map { $0.name }, ["qwen3.5:4b"],
                       "the successfully-fetched models must be retained")
    }

    // The completion contract: refresh's completion runs after the fetch
    // resolves. A non-forced refresh that coalesces behind an in-flight fetch
    // must still deliver its completion when that fetch lands, not silently drop
    // it (a caller that re-enables a control in the completion would hang).
    func test_coalescedRefresh_stillInvokesCompletion() {
        let cache = makeCache()
        var completions: [([AIMetadata.Model]?) -> Void] = []
        cache.fetcher = { _, _, _, completion in completions.append(completion) }

        cache.refresh(endpoint: "e")  // background, in flight (force = false)
        var called = false
        cache.refresh(endpoint: "e", force: false) { _, _ in called = true }
        XCTAssertEqual(completions.count, 1, "the coalesced refresh must not issue a second fetch")

        completions[0](models("e"))  // the in-flight fetch resolves
        XCTAssertTrue(called,
                      "the coalesced refresh's completion must run when the in-flight fetch resolves")
    }

    // restore() (launch-time seeding from persisted models) must not clobber a
    // FRESHER in-memory entry. If an early read already kicked off and landed a
    // live refresh, overwriting it with stale persisted data (and nil'ing
    // lastAttempt) briefly resolves pinned tags against removed/stale models.
    func test_restore_doesNotClobberFresherInMemoryEntry() {
        let cache = makeCache()
        cache.update(endpoint: "e", models: models("e"))  // fresh live discovery in memory

        let stale: [String: Any] = ["e": [["name": "stale-model", "ctx": 4096, "features": ["streaming"]]]]
        cache.restore(from: stale)

        XCTAssertEqual(cache.models(forEndpoint: "e").map { $0.name }, ["qwen3.5:4b"],
                       "restore must not overwrite a fresher in-memory entry with stale persisted data")
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

    // The persistence layer exists to resolve a pinned tag synchronously at
    // launch. An entry reached with an auth header must get that too: its cache
    // key is a bucket rather than a URL, so the snapshot has to carry the bare
    // endpoint separately or the restored models would take the bucket as their
    // URL (and pruning by URL would drop them entirely).
    func test_persistenceRoundTrip_headerBearingEntry() {
        let endpoint = "http://persist-auth:11434/api/chat"
        let auth = [["name": "Authorization", "value": "Bearer secret"]]
        let source = makeCache()
        source.fetcher = { endpoint, _, _, completion in completion(self.models(endpoint)) }
        source.refresh(endpoint: endpoint, headers: auth)

        let representation = source.persistedRepresentation()
        XCTAssertEqual(representation.count, 1)
        XCTAssertFalse(representation.keys.contains(endpoint),
                       "a header-bearing entry is keyed by its bucket, not the bare URL")

        let restored = makeCache()
        restored.restore(from: representation)
        let m = restored.models(forEndpoint: endpoint, headers: auth)
        XCTAssertEqual(m.map { $0.name }, ["qwen3.5:4b"],
                       "the authenticated view resolves synchronously after a restore")
        XCTAssertEqual(m.first?.url, endpoint,
                       "restored models carry the real endpoint, never the bucket key")
        XCTAssertFalse(m.first?.url.contains("\u{1}") ?? true)
        XCTAssertTrue(restored.models(forEndpoint: endpoint).isEmpty,
                      "and they are not visible to the header-less view")
    }

    // The persisted key must not spell out the headers. It is written to user
    // defaults, where an Authorization value in a KEY is unreachable by
    // tools/sanitize_iterm2_plist.py (it redacts values, never keys), and a
    // control character in a key makes the exported XML plist unparseable.
    func test_persistedKeys_carryNoCredentialAndStayXMLSafe() throws {
        let endpoint = "http://persist-auth:11434/api/chat"
        let secret = "Bearer sk-do-not-persist-me"
        let cache = makeCache()
        cache.fetcher = { endpoint, _, _, completion in completion(self.models(endpoint)) }
        cache.refresh(endpoint: endpoint,
                      headers: [["name": "Authorization", "value": secret]])

        let representation = cache.persistedRepresentation()
        let key = try XCTUnwrap(representation.keys.first)
        XCTAssertFalse(key.contains(secret), "the credential must not appear in a persisted key")
        XCTAssertFalse(key.contains("sk-do-not-persist-me"))
        XCTAssertFalse(key.contains("Authorization"))
        XCTAssertTrue(key.hasPrefix(endpoint + "|"), "the endpoint stays legible for pruning")
        XCTAssertFalse(key.unicodeScalars.contains { $0.value < 0x20 },
                       "a control character in a key makes the XML plist unparseable")
        // The whole snapshot has to survive plist serialization.
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: representation,
                                                            format: .xml,
                                                            options: 0))
    }

    // A blob written before buckets existed is keyed by the bare endpoint and
    // holds the model list directly. It must still restore.
    func test_restore_acceptsLegacyRepresentation() {
        let endpoint = "http://legacy:11434/api/chat"
        let legacy: [String: Any] = [endpoint: [["name": "qwen3.5:4b", "ctx": 4096]]]
        let cache = makeCache()
        cache.restore(from: legacy)

        let m = cache.models(forEndpoint: endpoint)
        XCTAssertEqual(m.map { $0.name }, ["qwen3.5:4b"])
        XCTAssertEqual(m.first?.url, endpoint)
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

    // serverLabel keeps only scheme://host:port, so two dynamic entries that
    // point at the SAME host:port by different paths (e.g. the native /api/chat
    // and the OpenAI-compatible /v1 URL of one server, or two proxy paths)
    // collapse to the same label. When they expose the same tag, the qualified
    // names collide -> two identical menu items, and first-match resolution
    // sends a chat pinned to the second entry to the first entry's url/headers.
    func test_twoDynamicServers_sameHostPort_differentPath_areDisambiguated() {
        let epA = "http://sharedbox:11434/api/chat"
        let epB = "http://sharedbox:11434/v1/chat/completions"
        let body = Data("{\"models\":[{\"name\":\"sharedtag:latest\",\"capabilities\":[\"tools\"],\"details\":{\"context_length\":4096}}]}".utf8)
        OllamaModelCache.shared.update(endpoint: epA, models: OllamaModelDiscovery.models(fromTagsResponse: body, endpoint: epA))
        OllamaModelCache.shared.update(endpoint: epB, models: OllamaModelDiscovery.models(fromTagsResponse: body, endpoint: epB))
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
        let matches = models.filter { ($0.wireModelName ?? $0.name) == "sharedtag:latest" }
        XCTAssertEqual(matches.count, 2, "both entries' shared tag should be present")
        XCTAssertEqual(Set(matches.map { $0.name }).count, 2,
                       "same host:port with a different path collapses to one serverLabel, so the disambiguated names collide and .first-match resolution routes to the wrong endpoint")
        XCTAssertEqual(Set(matches.map { $0.url }), [epA, epB], "each must keep its own endpoint")
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

    // A model the user added has to appear where they added it. A dynamic entry
    // on the default endpoint duplicates the built-in Ollama vendor, but it is
    // listed anyway: discarding it left a row in Manage AI Models that showed up
    // nowhere else. Each manual copy is qualified with its server so the
    // duplicate is distinguishable and cannot shadow the built-in one.
    func test_defaultEndpoint_wholeServerDynamicEntry_isListed() {
        let endpoint = LLMMetadata.defaultOllamaEndpoint
        OllamaModelCache.shared.update(endpoint: endpoint, models: models(endpoint))
        defer { OllamaModelCache.shared.update(endpoint: endpoint, models: []) }

        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([
            ["url": endpoint, "dynamicModels": true, "api": Int(iTermAIAPI.llama.rawValue)],
        ], forKey: key)

        let manual = LLMMetadata.manualModels()
        XCTAssertFalse(manual.isEmpty, "the entry the user added must be listed")
        XCTAssertTrue(manual.contains { $0.effectiveModelName == "qwen3.5:4b" },
                      "it expands to the server's tags and sends the raw tag on the wire")
        XCTAssertFalse(manual.contains { $0.name == "qwen3.5:4b" },
                       "each manual copy is qualified so it can't shadow the built-in one")
        XCTAssertTrue(LLMMetadata.discoveredOllamaModels().contains { $0.name == "qwen3.5:4b" },
                      "the built-in copy keeps the clean tag")
    }

    // An entry naming a SINGLE model is listed the same way.
    func test_defaultEndpoint_dynamicEntryNamingOneModel_isListed() {
        let endpoint = LLMMetadata.defaultOllamaEndpoint
        OllamaModelCache.shared.update(endpoint: endpoint, models: models(endpoint))
        defer { OllamaModelCache.shared.update(endpoint: endpoint, models: []) }

        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        iTermPreferences.setObject([
            ["url": endpoint,
             "dynamicModels": true,
             "dynamicSelectedModel": "qwen3.5:4b",
             "api": Int(iTermAIAPI.llama.rawValue)],
        ], forKey: key)

        let manual = LLMMetadata.manualModels()
        XCTAssertEqual(manual.count, 1, "the chosen model is listed")
        XCTAssertEqual(manual.first?.effectiveModelName, "qwen3.5:4b",
                       "it still sends the raw tag on the wire")
        XCTAssertFalse(manual.contains { $0.name == "qwen3.5:4b" },
                       "its display name is qualified so it can't shadow the built-in copy")
        XCTAssertTrue(LLMMetadata.discoveredOllamaModels().contains { $0.name == "qwen3.5:4b" },
                      "the built-in copy keeps the clean tag")
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

    // The configured-entry list carries headers, because the cache identifies a
    // bucket by endpoint AND headers: pruning by bare URL would drop a
    // header-bearing entry's persisted models.
    func test_dynamicOllamaConfigurations_carryHeaders() {
        let key = kPreferenceKeyAIManualModelConfigurations
        let saved = iTermPreferences.object(forKey: key)
        defer { iTermPreferences.setObject(saved, forKey: key) }
        let auth = [["name": "Authorization", "value": "Bearer secret"]]
        iTermPreferences.setObject([
            ["url": "http://gpu-box:11434/api/chat",
             "dynamicModels": true,
             "customHeaders": auth,
             "api": Int(iTermAIAPI.llama.rawValue)],
        ], forKey: key)

        let configurations = LLMMetadata.dynamicOllamaConfigurations()
        let entry = configurations.first { $0.url == "http://gpu-box:11434/api/chat" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.headers as NSArray?, auth as NSArray)
        XCTAssertTrue(configurations.contains { $0.url == LLMMetadata.defaultOllamaEndpoint && $0.headers.isEmpty },
                      "the built-in default endpoint is always configured, header-less")
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

        // The Settings default-model popup builds from settingsManualModels(), so a
        // dynamic entry must be surfaced there too (the regression: it was hidden).
        XCTAssertEqual(LLMMetadata.settingsManualModels().map { $0.name }, ["m2"],
                       "dynamic manual models must appear in the default-model popup")
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

    // A chat pinned to a DISCOVERED built-in Ollama tag must resolve through the
    // shared resolver, so request routing (AIConversation/ChatAgent) and the
    // provider-binding guard agree with the UI instead of falling through to the
    // global (possibly cloud) default and silently sending a local-model turn there.
    func test_modelNamed_resolvesDiscoveredOllamaTag() {
        let endpoint = LLMMetadata.defaultOllamaEndpoint
        OllamaModelCache.shared.update(endpoint: endpoint, models: models(endpoint))
        defer { OllamaModelCache.shared.update(endpoint: endpoint, models: []) }

        let resolved = LLMMetadata.model(named: "qwen3.5:4b")
        XCTAssertEqual(resolved?.name, "qwen3.5:4b",
                       "a discovered built-in Ollama tag must resolve, not fall through to the default")
        XCTAssertEqual(resolved?.vendor, .llama)
        XCTAssertEqual(ChatProviderBinding.vendor(forModelName: "qwen3.5:4b"), .llama,
                       "the provider-binding guard must classify a discovered local tag as the Ollama vendor")
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

    func test_recommendedOllama_staleRegularChoice_staysPending() {
        withOllamaVendorDefault(regular: "removed:99b", economy: "") {
            XCTAssertEqual(LLMMetadata.recommendedModel(for: .llama)?.name,
                           LLMMetadata.pendingOllamaModelName,
                           "an explicitly-chosen model that is transiently missing must NOT be replaced "
                           + "by a different tag; return the pending placeholder so a new chat waits for "
                           + "discovery instead of silently using a model the user didn't choose")
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

    // MARK: - Regression tests for review findings (currently FAILING)

    // Finding: a non-forced refresh that coalesces behind an in-flight fetch must
    // reflect THAT fetch's outcome, not a DIFFERENT concurrent fetch that merely
    // resolved first. Today `pendingCompletions` is drained by whichever fetcher
    // block runs first (OllamaModelCache.swift:140), so a coalesced caller can be
    // told `failed=true` by a forced probe even though the fetch it actually
    // waited on succeeded. A caller that shows "Could not reach server" or
    // re-enables a control on failure then reacts to the wrong outcome.
    func test_coalescedRefresh_reflectsCoalescedFetchOutcome_notAConcurrentForcedProbe() {
        let cache = makeCache()
        var completions: [([AIMetadata.Model]?) -> Void] = []
        cache.fetcher = { _, _, _, completion in completions.append(completion) }

        cache.refresh(endpoint: "e")  // background fetch A, in flight (force = false)
        var coalescedFailed: Bool?
        var coalescedCount: Int?
        cache.refresh(endpoint: "e", force: false) { count, failed in
            coalescedCount = count
            coalescedFailed = failed
        }
        XCTAssertEqual(completions.count, 1, "the coalesced non-forced refresh must not issue its own fetch")

        cache.refresh(endpoint: "e", force: true)  // forced probe B, also in flight
        XCTAssertEqual(completions.count, 2)

        completions[1](nil)          // the forced probe B fails FIRST
        completions[0](models("e"))  // fetch A (the one the caller coalesced behind) then SUCCEEDS

        XCTAssertEqual(coalescedFailed, false,
                       "the coalesced completion must reflect the fetch it coalesced behind (which succeeded), not the concurrent forced probe that failed first")
        XCTAssertEqual(coalescedCount, 1,
                       "the coalesced completion must report the model count of the fetch it coalesced behind")
    }

    // A FORCED probe's own completion must also reflect the batch, not just its own
    // fetch: if the probe fails first while a concurrent background fetch of the same
    // endpoint then succeeds, the probe must report success, so the settings panel
    // doesn't show "Could Not Reach Ollama" and roll the default vendor back to a
    // cloud provider while the healthy fetch is landing.
    func test_forcedProbe_failsButSiblingSucceeds_reportsBatchSuccess() {
        let cache = makeCache()
        var completions: [([AIMetadata.Model]?) -> Void] = []
        cache.fetcher = { _, _, _, completion in completions.append(completion) }

        cache.refresh(endpoint: "e")  // background fetch A, in flight
        var probeFailed: Bool?
        var probeCount: Int?
        cache.refresh(endpoint: "e", force: true) { count, failed in
            probeCount = count
            probeFailed = failed
        }
        XCTAssertEqual(completions.count, 2, "the forced probe must issue its own fetch")

        completions[1](nil)  // the forced probe B resolves FIRST, with a transient failure
        XCTAssertNil(probeFailed,
                     "the probe's completion must be deferred, not report failure, while a sibling fetch may still succeed")

        completions[0](models("e"))  // the background fetch A then succeeds (last of batch)
        XCTAssertEqual(probeFailed, false,
                       "a sibling success in the same batch must suppress the forced probe's failure/rollback")
        XCTAssertEqual(probeCount, 1,
                       "the probe reports the batch's resulting model count")
    }

    // Finding: a direct update() (the seeding/tests convenience) assumes it is
    // "its own round" with no in-flight fetch (comment at OllamaModelCache.swift:166).
    // If a fetch is actually outstanding, update() decrements that fetch's
    // inFlightCount and is mistaken for the last of its batch; the real fetch's
    // later completion is ALSO treated as last-of-batch, so a single failed
    // endpoint round is counted twice and arms two self-healing retries (a retry
    // storm at double the intended rate).
    func test_directUpdateDuringInFlightFetch_doesNotDoubleCountBatchFailures() {
        let cache = makeCache()
        var scheduled = 0
        var completions: [([AIMetadata.Model]?) -> Void] = []
        cache.fetcher = { _, _, _, completion in completions.append(completion) }
        cache.retryScheduler = { _, _ in scheduled += 1 }

        cache.refresh(endpoint: "e")              // one fetch in flight (inFlightCount == 1)
        cache.update(endpoint: "e", result: nil)  // a direct update lands while it is outstanding
        completions[0](nil)                        // the in-flight fetch then completes (also a failure)

        XCTAssertEqual(scheduled, 1,
                       "one endpoint's failed round must arm exactly one retry; a direct update overlapping an in-flight fetch must not be double-counted as two failed rounds")
    }

    // Headers are part of a bucket's identity. The built-in Ollama vendor fetches
    // the default endpoint with no headers; a manual dynamic entry can name the
    // SAME endpoint and carry an Authorization header for a local auth proxy.
    // Sharing one bucket let the header-less fetch, which 401s, satisfy the
    // authenticated caller by coalescing, so the entry expanded to zero models
    // depending on which fetch started first.
    func test_sameEndpointDifferentHeaders_doNotShareABucket() {
        let cache = makeCache()
        let auth = [["name": "Authorization", "value": "Bearer secret"]]
        // The server answers only when the credential is present.
        cache.fetcher = { endpoint, headers, _, completion in
            completion(headers.isEmpty ? nil : self.models(endpoint))
        }

        cache.refresh(endpoint: "e")                  // header-less: 401s
        cache.refresh(endpoint: "e", headers: auth)   // authenticated: succeeds

        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e", headers: auth), ["qwen3.5:4b"],
                       "the authenticated view must hold the models it fetched")
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), [],
                       "the header-less view must not borrow them")
    }

    // ...and the authenticated fetch must actually issue rather than coalescing
    // behind an in-flight header-less one that cannot satisfy it.
    func test_authenticatedRefresh_doesNotCoalesceBehindAHeaderLessFetch() {
        let cache = makeCache()
        let auth = [["name": "Authorization", "value": "Bearer secret"]]
        var seen: [[[String: String]]] = []
        var pending: [() -> Void] = []
        cache.fetcher = { endpoint, headers, _, completion in
            seen.append(headers)
            // Hold both fetches open so the second would coalesce if it could.
            pending.append { completion(headers.isEmpty ? nil : self.models(endpoint)) }
        }

        cache.refresh(endpoint: "e")                  // in flight, header-less
        cache.refresh(endpoint: "e", headers: auth)   // must issue its own fetch
        XCTAssertEqual(seen.count, 2, "the authenticated fetch must not be coalesced away")
        XCTAssertTrue(seen.contains { !$0.isEmpty }, "one of them carries the credential")

        for resolve in pending { resolve() }
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e", headers: auth), ["qwen3.5:4b"])
    }

    // Two equal header sets in a different order are the same configuration and
    // must share a bucket rather than each fetching.
    func test_headerOrderDoesNotSplitTheBucket() {
        let cache = makeCache()
        let a = [["name": "X-A", "value": "1"], ["name": "X-B", "value": "2"]]
        let b = [["name": "X-B", "value": "2"], ["name": "X-A", "value": "1"]]
        cache.fetcher = { endpoint, _, _, completion in completion(self.models(endpoint)) }

        cache.refresh(endpoint: "e", headers: a)
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e", headers: b), ["qwen3.5:4b"])
    }

    // A reachable server that momentarily returns {"models":[]} (mid-reload) must not
    // wipe a previously-populated cache and persist the emptiness for the success
    // TTL. The non-empty -> empty transition keeps the last good models and arms a
    // self-healing retry, like a fetch failure.
    func test_transientEmpty_keepsModelsAndArmsRetry() {
        let cache = makeCache()
        var scheduled = 0
        cache.retryScheduler = { _, _ in scheduled += 1 }
        var nextResult: [AIMetadata.Model]? = models("e")
        cache.fetcher = { _, _, _, completion in completion(nextResult) }

        cache.refresh(endpoint: "e")  // success -> populated
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), ["qwen3.5:4b"])

        nextResult = []               // server momentarily returns an empty list
        cache.refresh(endpoint: "e", force: true)
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), ["qwen3.5:4b"],
                       "a transient empty result must not wipe previously-discovered models")
        XCTAssertEqual(scheduled, 1,
                       "a non-empty -> empty transition must arm a self-healing retry")
    }

    // The refresh completion must report the EFFECTIVE (retained) count for a
    // suspicious-empty result, not the raw 0: otherwise the Refresh Models button
    // shows "Found 0 installed models" while the picker still lists the retained
    // ones. Keeping them is a soft failure, not a hard one, so failed is false.
    func test_suspiciousEmpty_completionReportsRetainedCount() {
        let cache = makeCache()
        cache.retryScheduler = { _, _ in }
        var nextResult: [AIMetadata.Model]? = models("e")
        cache.fetcher = { _, _, _, completion in completion(nextResult) }

        cache.refresh(endpoint: "e")  // success -> 1 model
        nextResult = []               // server momentarily returns empty
        var reportedCount = -1
        var reportedFailed = true
        cache.refresh(endpoint: "e", force: true) { count, failed in
            reportedCount = count
            reportedFailed = failed
        }
        XCTAssertEqual(reportedCount, 1,
                       "must report the retained model count, not the raw empty probe's 0")
        XCTAssertFalse(reportedFailed,
                       "retaining the last-good models is a soft failure, reported as not-failed to the caller")
    }

    // Escape hatch: a server the user genuinely emptied must not show stale models
    // forever. After maxSuspiciousEmpties consecutive empties, the cache accepts the
    // empty list and clears the retained models.
    func test_suspiciousEmpty_afterThreshold_acceptsEmpty() {
        let cache = makeCache()
        cache.retryScheduler = { _, _ in }
        var nextResult: [AIMetadata.Model]? = models("e")
        cache.fetcher = { _, _, _, completion in completion(nextResult) }

        cache.refresh(endpoint: "e")  // success -> 1 model
        nextResult = []
        // The first (maxSuspiciousEmpties - 1) empties retain the models...
        for _ in 0..<(cache.maxSuspiciousEmpties - 1) {
            cache.refresh(endpoint: "e", force: true)
            XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), ["qwen3.5:4b"],
                           "models retained while under the suspicious-empty threshold")
        }
        // ...the threshold-th empty accepts it and clears the entry.
        cache.refresh(endpoint: "e", force: true)
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), [],
                       "after maxSuspiciousEmpties empties the genuinely-empty server is accepted")
    }

    // The accept-empty escape hatch requires GENUINELY consecutive empties: a hard
    // failure (server down/401) interleaved between empties must reset the streak, so
    // a flapping server doesn't prematurely wipe the retained models.
    func test_suspiciousEmpty_hardFailureResetsStreak() {
        let cache = makeCache()
        cache.retryScheduler = { _, _ in }
        var nextResult: [AIMetadata.Model]? = models("e")
        cache.fetcher = { _, _, _, completion in completion(nextResult) }
        cache.refresh(endpoint: "e")  // success -> 1 model

        for _ in 0..<5 {
            nextResult = []
            cache.refresh(endpoint: "e", force: true)
            nextResult = nil
            cache.refresh(endpoint: "e", force: true)
        }
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), ["qwen3.5:4b"],
                       "empties broken up by hard failures are not consecutive and must not trip the accept-empty escape hatch")
    }

    // A down endpoint that previously succeeded (or was restored from persistence)
    // must become refreshable again within failureRetryInterval, not be gated by the
    // 300s success TTL: shouldRefresh keys on the CURRENT failure state.
    func test_shouldRefresh_currentlyFailingEndpoint_usesFailureInterval() {
        let cache = makeCache()
        var clock = Date(timeIntervalSince1970: 1_000)
        cache.nowProvider = { clock }
        cache.retryScheduler = { _, _ in }
        var nextResult: [AIMetadata.Model]? = models("e")
        cache.fetcher = { _, _, _, completion in completion(nextResult) }

        cache.refresh(endpoint: "e")            // success, haveSucceeded = true
        nextResult = nil
        cache.refresh(endpoint: "e", force: true)  // fails; consecutiveFailures > 0

        clock = clock.addingTimeInterval(10)    // 10s later: past failureRetryInterval (5s), well under successTTL
        XCTAssertTrue(cache.shouldRefresh(endpoint: "e"),
                      "a currently-failing endpoint must be refreshable within the failure interval, not gated by successTTL")
    }

    // A genuinely empty server (no prior models) still accepts the empty list, so a
    // fresh install with nothing pulled shows an empty picker rather than stalling.
    func test_firstEverEmpty_isAccepted() {
        let cache = makeCache()
        var scheduled = 0
        cache.retryScheduler = { _, _ in scheduled += 1 }
        cache.fetcher = { _, _, _, completion in completion([]) }

        cache.refresh(endpoint: "e")
        XCTAssertEqual(cache.cachedModelNames(forEndpoint: "e"), [],
                       "an empty result with no prior models is a genuine empty server")
        XCTAssertEqual(scheduled, 0,
                       "a genuine empty server is a success, not a failure, so no retry is armed")
    }
}
