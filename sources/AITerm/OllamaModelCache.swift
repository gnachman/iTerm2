//
//  OllamaModelCache.swift
//  iTerm2
//
//  A synchronously-readable cache of the models installed on an Ollama server,
//  refreshed asynchronously from /api/tags. The dynamic Ollama provider reads it
//  to expand into per-model catalog entries (model resolution is synchronous, but
//  discovery is a network call), and posts a change notification so the model
//  pickers rebuild when a refresh brings in new models or capabilities.
//
//  Self-healing: a FAILED fetch (server down at launch, a 401 from an auth proxy)
//  is never cached as a successful empty result. It keeps the last good models,
//  and schedules a bounded one-shot retry after `failureRetryInterval` so the
//  picker repopulates on its own once the server comes up, without waiting for an
//  incidental read. A SUCCESSFUL result is re-fetched after `successTTL` so newly
//  pulled models appear, and on-read staleness also triggers a refresh.
//

import Foundation

@objc(iTermOllamaModelCache)
class OllamaModelCache: NSObject {
    @objc(iTermOllamaModelCacheDidChangeNotification)
    static let didChangeNotification = Notification.Name("iTermOllamaModelCacheDidChange")

    @objc static let shared = OllamaModelCache()

    private struct Entry {
        var models: [AIMetadata.Model] = []
        var haveSucceeded = false
        var lastAttempt: Date?
        var consecutiveFailures = 0
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    // How many fetches are outstanding per endpoint. A COUNT (not a set) because a
    // forced refresh deliberately runs alongside an in-flight background one, so an
    // endpoint can have two fetches at once; the failure bookkeeping runs only for
    // the last completion of a batch so concurrent failures count as one round.
    private var inFlightCount: [String: Int] = [:]

    private let networkTimeout: TimeInterval = 10
    private let successTTL: TimeInterval = 300
    private let failureRetryInterval: TimeInterval = 5
    // Stop the timer-driven retry loop after this many consecutive failures so a
    // permanently-down server isn't probed forever; read-driven recovery remains.
    let maxAutoRetries = 6

    // Disk persistence is enabled only after loadPersistedModels() runs (at app
    // launch), so tests that use the shared instance don't touch user defaults.
    private var persistenceEnabled = false
    private static let persistenceKey = "NoSyncOllamaDiscoveredModels"

    // Injectable for tests: the clock, the network fetch, and the retry timer.
    var nowProvider: () -> Date = { Date() }
    var fetcher: (String, [[String: String]], TimeInterval, @escaping ([AIMetadata.Model]?) -> Void) -> Void = {
        endpoint, headers, timeout, completion in
        OllamaModelDiscovery.fetchModels(fromEndpoint: endpoint, headers: headers,
                                         timeout: timeout, completion: completion)
    }
    var retryScheduler: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    func shouldRefresh(endpoint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldRefreshLocked(endpoint: endpoint)
    }

    private func shouldRefreshLocked(endpoint: String) -> Bool {
        guard let entry = cache[endpoint] else {
            return true
        }
        let elapsed = entry.lastAttempt.map { nowProvider().timeIntervalSince($0) } ?? .infinity
        return entry.haveSucceeded ? elapsed >= successTTL : elapsed >= failureRetryInterval
    }

    // The cached models for an endpoint. Kicks off a background refresh when
    // missing/stale; the pickers update via didChangeNotification when it lands.
    func models(forEndpoint endpoint: String, headers: [[String: String]] = []) -> [AIMetadata.Model] {
        lock.lock()
        let cached = cache[endpoint]?.models ?? []
        let refresh = shouldRefreshLocked(endpoint: endpoint)
        lock.unlock()
        if refresh {
            self.refresh(endpoint: endpoint, headers: headers)
        }
        return cached
    }

    // Kick off a background refresh. Coalesces concurrent refreshes of the same
    // endpoint UNLESS `force` (a user-initiated refresh must always issue, or it
    // could be dropped behind a slow background fetch that then fails). completion
    // runs on the main queue with (modelCount, failed) after the fetch resolves.
    @objc(refreshEndpoint:headers:force:completion:)
    func refresh(endpoint: String,
                 headers: [[String: String]] = [],
                 force: Bool = false,
                 completion: ((Int, Bool) -> Void)? = nil) {
        lock.lock()
        if !force && (inFlightCount[endpoint] ?? 0) > 0 {
            lock.unlock()
            return
        }
        inFlightCount[endpoint, default: 0] += 1
        lock.unlock()

        fetcher(endpoint, headers, networkTimeout) { [weak self] result in
            self?.update(endpoint: endpoint, result: result, headers: headers)
            completion?(result?.count ?? 0, result == nil)
        }
    }

    // ObjC convenience without a completion.
    @objc(refreshEndpoint:headers:)
    func refresh(endpoint: String, headers: [[String: String]]) {
        refresh(endpoint: endpoint, headers: headers, force: false, completion: nil)
    }

    // Record a fetch outcome. nil = failure: keep the previous models, stamp the
    // attempt, and schedule a bounded self-healing retry. Non-nil = success:
    // replace the models, reset the failure count, and post the change
    // notification if the list changed.
    func update(endpoint: String, result: [AIMetadata.Model]?, headers: [[String: String]] = []) {
        lock.lock()
        // Decrement the in-flight count for this endpoint. Only the completion that
        // drains the last outstanding fetch does the per-round failure bookkeeping,
        // so two concurrent fetches (a background one plus a forced probe) that both
        // fail count as ONE failed round instead of two, keeping the self-healing
        // retry budget intact. A direct update() with no tracked fetch (tests,
        // seeding) has count 0 and is its own round.
        let outstanding = inFlightCount[endpoint] ?? 0
        let lastOfBatch: Bool
        if outstanding > 0 {
            let remaining = outstanding - 1
            if remaining == 0 {
                inFlightCount[endpoint] = nil
            } else {
                inFlightCount[endpoint] = remaining
            }
            lastOfBatch = (remaining == 0)
        } else {
            lastOfBatch = true
        }

        var entry = cache[endpoint] ?? Entry()
        entry.lastAttempt = nowProvider()
        var changed = false
        var scheduleRetry = false
        if let result {
            changed = !entry.haveSucceeded || entry.models != result
            entry.models = result
            entry.haveSucceeded = true
            entry.consecutiveFailures = 0
        } else if lastOfBatch {
            entry.consecutiveFailures += 1
            scheduleRetry = entry.consecutiveFailures <= maxAutoRetries
        }
        let failures = entry.consecutiveFailures
        cache[endpoint] = entry
        lock.unlock()

        if let result {
            DLog("Ollama discovery for \(endpoint): success, \(result.count) model(s), changed=\(changed)")
        } else {
            DLog("Ollama discovery for \(endpoint): FAILED (attempt \(failures)); scheduleRetry=\(scheduleRetry)")
        }
        if scheduleRetry {
            retryScheduler(failureRetryInterval) { [weak self] in
                self?.refresh(endpoint: endpoint, headers: headers)
            }
        }
        if changed {
            persistIfEnabled()
            postDidChange(endpoint: endpoint)
        }
    }

    // Convenience for a known-successful result (tests, seeding).
    func update(endpoint: String, models: [AIMetadata.Model]) {
        update(endpoint: endpoint, result: models)
    }

    // Posts the CHANGED endpoint as the notification `object` so observers can
    // ignore refreshes for endpoints they don't display (a toolbar bound to one
    // Ollama server shouldn't rebuild when a different server's list changes).
    // MARK: - Persistence
    //
    // The in-memory cache starts empty on launch and only populates after an async
    // /api/tags round-trip, so a chat pinned to a discovered tag would resolve to
    // nil (and silently route to the global default provider, possibly a cloud
    // vendor) during that window. Persisting the last-discovered models lets them
    // resolve SYNCHRONOUSLY at launch (possibly stale) while a fresh fetch updates.

    // Load persisted models into the cache and enable persistence on future
    // successful refreshes. Call once at app launch, before any dynamic-model
    // resolution. Seeded entries are treated as succeeded-but-stale so the first
    // read still kicks off a refresh.
    @objc func loadPersistedModels() {
        persistenceEnabled = true
        guard let representation = iTermUserDefaults.userDefaults().object(forKey: Self.persistenceKey) as? [String: Any] else {
            return
        }
        // Drop endpoints that are no longer configured (a since-deleted entry, or a
        // URL the user probed with "Refresh Models" but never saved), so the
        // persisted blob tracks only currently-configured servers.
        restore(from: Self.endpointsPruned(representation, keeping: LLMMetadata.dynamicOllamaEndpoints()))
    }

    // Keep only the endpoints in `configured`. Pure, so it's unit-testable.
    static func endpointsPruned(_ representation: [String: Any],
                                keeping configured: Set<String>) -> [String: Any] {
        return representation.filter { configured.contains($0.key) }
    }

    // The serializable snapshot of the successfully-discovered models, keyed by
    // endpoint. Pure (no I/O) so it's unit-testable.
    func persistedRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: Any] = [:]
        for (endpoint, entry) in cache where entry.haveSucceeded {
            result[endpoint] = entry.models.map { Self.dictionary(from: $0) }
        }
        return result
    }

    // Seed the cache from a persisted snapshot. Entries are marked succeeded with
    // no lastAttempt, so shouldRefresh triggers a fresh fetch on the first read.
    func restore(from representation: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        for (endpoint, value) in representation {
            guard let dicts = value as? [[String: Any]] else { continue }
            let models = dicts.compactMap { Self.model(from: $0, endpoint: endpoint) }
            cache[endpoint] = Entry(models: models, haveSucceeded: true, lastAttempt: nil)
        }
    }

    private func persistIfEnabled() {
        guard persistenceEnabled else { return }
        // Persist only currently-configured endpoints: a "Refresh Models" probe of
        // an unsaved URL still seeds the in-memory cache, but it must not grow the
        // persisted blob unboundedly.
        let pruned = Self.endpointsPruned(persistedRepresentation(),
                                          keeping: LLMMetadata.dynamicOllamaEndpoints())
        iTermUserDefaults.userDefaults().set(pruned, forKey: Self.persistenceKey)
    }

    private static let featureNames: [(AIMetadata.Model.Feature, String)] = [
        (.streaming, "streaming"),
        (.functionCalling, "functionCalling"),
        (.configurableThinking, "configurableThinking"),
        (.vision, "vision"),
    ]

    private static func dictionary(from model: AIMetadata.Model) -> [String: Any] {
        let features = featureNames.filter { model.features.contains($0.0) }.map { $0.1 }
        return ["name": model.name, "ctx": model.contextWindowTokens, "features": features]
    }

    private static func model(from dictionary: [String: Any], endpoint: String) -> AIMetadata.Model? {
        guard let name = dictionary["name"] as? String else { return nil }
        let ctx = dictionary["ctx"] as? Int ?? OllamaModelDiscovery.defaultContextWindow
        let names = Set(dictionary["features"] as? [String] ?? [])
        let features = Set(featureNames.filter { names.contains($0.1) }.map { $0.0 })
        return AIMetadata.Model(name: name, contextWindowTokens: ctx, maxResponseTokens: ctx,
                                url: endpoint, api: .llama, features: features,
                                vectorStoreConfig: .disabled, vendor: .llama)
    }

    private func postDidChange(endpoint: String) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: endpoint)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: endpoint)
            }
        }
    }
}
