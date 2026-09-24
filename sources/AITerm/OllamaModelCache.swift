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

import CryptoKit
import Foundation

@objc(iTermOllamaModelCache)
class OllamaModelCache: NSObject {
    @objc(iTermOllamaModelCacheDidChangeNotification)
    static let didChangeNotification = Notification.Name("iTermOllamaModelCacheDidChange")

    @objc static let shared = OllamaModelCache()

    private struct Entry {
        // The bare endpoint this entry's models were fetched from. The dictionary
        // key is a bucket (endpoint plus a header digest), which is NOT a URL, so
        // anything that needs the real one reads it here.
        var endpoint: String = ""
        var models: [AIMetadata.Model] = []
        var haveSucceeded = false
        var lastAttempt: Date?
        var consecutiveFailures = 0
        // Consecutive suspicious-empty results (a reachable server returning [] after
        // it previously had models). Bounded so a genuinely-emptied server is
        // eventually accepted instead of showing stale models forever.
        var consecutiveEmpties = 0
    }

    // The aggregate result of the fetch batch an update() completed, used to resolve
    // coalesced completions (see refresh). `lastOfBatch` is true when this update
    // drained the final outstanding fetch for the endpoint; `succeeded`/`count`
    // describe the batch as a whole (any success wins), not just this one fetch.
    struct BatchOutcome {
        var lastOfBatch: Bool
        var succeeded: Bool
        var count: Int
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    // How many fetches are outstanding per endpoint. A COUNT (not a set) because a
    // forced refresh deliberately runs alongside an in-flight background one, so an
    // endpoint can have two fetches at once; the failure bookkeeping runs only for
    // the last completion of a batch so concurrent failures count as one round.
    private var inFlightCount: [String: Int] = [:]
    // Whether any fetch in the CURRENT batch has succeeded. A trailing failure in a
    // batch that already succeeded must not re-increment the failure count or arm a
    // retry (the endpoint is healthy). Cleared when the batch fully drains.
    private var batchHadSuccess: [String: Bool] = [:]
    // Completions for non-forced refreshes that coalesced behind an in-flight fetch.
    // They still expect to run when that fetch resolves (a caller may re-enable a
    // control in its completion), so they're delivered instead of dropped.
    private var pendingCompletions: [String: [(Int, Bool) -> Void]] = [:]

    // The key every per-endpoint dictionary above is stored under. Headers are
    // part of the identity because they change what /api/tags returns: an
    // authenticated server answers 401 without them. Two configurations can name
    // the SAME endpoint with different headers, most easily the built-in Ollama
    // vendor (which never sends headers) and a manual dynamic entry on the
    // default endpoint that carries an Authorization header. Sharing one bucket
    // let the header-less fetch satisfy the header-bearing caller by coalescing,
    // so the authenticated entry expanded to zero models depending on which
    // fetch happened to start first.
    //
    // A header-less fetch keys on the bare endpoint, so persisted entries, the
    // seeded cache, and every existing caller behave exactly as before.
    //
    // The headers are HASHED rather than spelled out, because this key is
    // persisted to user defaults: an Authorization value in a dictionary key
    // would put the credential in the prefs plist in the clear, where
    // tools/sanitize_iterm2_plist.py structurally cannot reach it (it redacts
    // values, never keys) and a debug-log breadcrumb would echo it. A hash keeps
    // bucket identity (equal header sets hash equally) while recovering nothing.
    // It also keeps the key ASCII: U+0001 is illegal in XML 1.0, so a raw digest
    // made `defaults export` output that Python's plistlib refuses to parse, and
    // the sanitizer runs on exactly that file.
    private static func bucket(_ endpoint: String, _ headers: [[String: String]]) -> String {
        guard !headers.isEmpty else {
            return endpoint
        }
        // Order-independent so two equal header sets share a bucket. U+0001
        // separates the fields before hashing: AICustomHeaders rejects control
        // characters in names and values, so it cannot be forged from a header.
        let digest = headers
            .map { "\($0["name"] ?? "")\u{1}\($0["value"] ?? "")" }
            .sorted()
            .joined(separator: "\u{1}")
        let hashed = SHA256.hash(data: Data(digest.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(endpoint)|\(hashed)"
    }

    private let networkTimeout: TimeInterval = 10
    private let successTTL: TimeInterval = 300
    private let failureRetryInterval: TimeInterval = 5
    // Stop the timer-driven retry loop after this many consecutive failures so a
    // permanently-down server isn't probed forever; read-driven recovery remains.
    let maxAutoRetries = 6
    // After this many consecutive suspicious-empty results (a reachable server that
    // keeps returning [] after it previously had models), accept the emptiness as
    // real (the user cleared the server) rather than retaining stale models forever.
    // Kept below maxAutoRetries so the decision lands before timer retries stop.
    let maxSuspiciousEmpties = 3

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

    func shouldRefresh(endpoint: String, headers: [[String: String]] = []) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldRefreshLocked(bucket: Self.bucket(endpoint, headers))
    }

    private func shouldRefreshLocked(bucket: String) -> Bool {
        guard let entry = cache[bucket] else {
            return true
        }
        let elapsed = entry.lastAttempt.map { nowProvider().timeIntervalSince($0) } ?? .infinity
        // Use the long success TTL only for a currently-HEALTHY endpoint. An endpoint
        // that is failing right now (consecutiveFailures > 0) uses the short failure
        // interval even though it succeeded before (or was restored from persistence
        // with haveSucceeded=true), so a server that comes back repopulates the picker
        // promptly instead of staying wedged until successTTL elapses.
        let healthy = entry.haveSucceeded && entry.consecutiveFailures == 0
        return elapsed >= (healthy ? successTTL : failureRetryInterval)
    }

    // The cached models for an endpoint. Kicks off a background refresh when
    // missing/stale; the pickers update via didChangeNotification when it lands.
    func models(forEndpoint endpoint: String, headers: [[String: String]] = []) -> [AIMetadata.Model] {
        let bucket = Self.bucket(endpoint, headers)
        lock.lock()
        let cached = cache[bucket]?.models ?? []
        let refresh = shouldRefreshLocked(bucket: bucket)
        lock.unlock()
        if refresh {
            self.refresh(endpoint: endpoint, headers: headers)
        }
        return cached
    }

    // The names of the currently-cached models for an endpoint, WITHOUT kicking off
    // a refresh. For the editor's discovered-models popup, which is populated after
    // an explicit Refresh (or from the persisted/seeded cache).
    @objc(cachedModelNamesForEndpoint:headers:)
    func cachedModelNames(forEndpoint endpoint: String,
                          headers: [[String: String]] = []) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return cache[Self.bucket(endpoint, headers)]?.models.map { $0.name } ?? []
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
        let bucket = Self.bucket(endpoint, headers)
        lock.lock()
        if !force && (inFlightCount[bucket] ?? 0) > 0 {
            // Coalesce behind the in-flight fetch, but don't drop this caller's
            // completion: run it when that fetch resolves. Only ever coalesces
            // behind a fetch with the SAME headers, since the bucket includes
            // them: a fetch that would 401 cannot stand in for an authenticated
            // one.
            if let completion {
                pendingCompletions[bucket, default: []].append(completion)
            }
            lock.unlock()
            return
        }
        inFlightCount[bucket, default: 0] += 1
        lock.unlock()

        fetcher(endpoint, headers, networkTimeout) { [weak self] result in
            guard let self else {
                // self gone: no cache update ran, so report the raw fetch result.
                completion?(result?.count ?? 0, result == nil)
                return
            }
            let outcome = self.update(endpoint: endpoint, result: result, headers: headers,
                                      countsAgainstInFlight: true)
            // This fetch failed but is NOT the last of its batch: a sibling fetch of
            // the same endpoint (e.g. a background refresh running alongside this
            // forced probe) may still succeed. Defer THIS caller's completion like a
            // coalesced one so it reports the batch's AGGREGATE outcome at
            // last-of-batch, instead of a premature failure that would e.g. roll the
            // default vendor back to a cloud provider while a healthy background fetch
            // is about to land. A fetch that itself succeeded, or that IS the last of
            // the batch, reports immediately below.
            if !outcome.lastOfBatch && !outcome.succeeded {
                if let completion {
                    self.lock.lock()
                    self.pendingCompletions[bucket, default: []].append(completion)
                    self.lock.unlock()
                }
                return
            }

            // Report the EFFECTIVE outcome, not the raw fetch. For a suspicious-empty
            // result (a reachable server that momentarily returns [] after previously
            // succeeding), update() RETAINS the last-good models and treats it as a
            // soft failure, so reporting the raw (0, notFailed) would say "Found 0"
            // while the picker still lists the retained models. `succeeded`/`count`
            // reflect what the cache actually holds now.
            let effectiveCount = outcome.succeeded ? outcome.count : 0
            completion?(effectiveCount, !outcome.succeeded)

            // Coalesced (non-forced) refreshes that parked behind an in-flight fetch
            // are resolved by the whole BATCH, not by whichever fetch finishes first:
            // a concurrent forced probe that fails must not report failure to a caller
            // that coalesced behind a background fetch about to succeed. Deliver only
            // when this completion drains the batch's last fetch, with the batch's
            // aggregate outcome. Synchronous (not main-async) so a caller re-enabling
            // a control sees it on the same turn the fetch resolves.
            guard outcome.lastOfBatch else {
                return
            }
            self.lock.lock()
            let coalesced = self.pendingCompletions.removeValue(forKey: bucket) ?? []
            self.lock.unlock()
            for pending in coalesced {
                pending(effectiveCount, !outcome.succeeded)
            }
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
    // countsAgainstInFlight: whether this update resolves a tracked fetch (the
    // refresh completion) and so owns one of the endpoint's inFlightCount
    // increments. Only the refresh path passes true. Every DIRECT caller (the
    // seeding convenience, tests) passes false: it owns no increment, so it must
    // not decrement one, and if a tracked fetch is currently in flight it defers the
    // per-round failure/retry bookkeeping to that fetch's completion rather than
    // forging its own last-of-batch event (which would double-count the round and
    // arm two self-healing retries).
    @discardableResult
    func update(endpoint: String,
                result: [AIMetadata.Model]?,
                headers: [[String: String]] = [],
                countsAgainstInFlight: Bool = false) -> BatchOutcome {
        // Same bucket the matching refresh() tracked this fetch under, so an
        // authenticated endpoint's bookkeeping and models never mix with the
        // header-less view of the same URL.
        let bucket = Self.bucket(endpoint, headers)
        lock.lock()
        // Decrement the in-flight count for this endpoint. Only the completion that
        // drains the last outstanding fetch does the per-round failure bookkeeping,
        // so two concurrent fetches (a background one plus a forced probe) that both
        // fail count as ONE failed round instead of two, keeping the self-healing
        // retry budget intact.
        var lastOfBatch: Bool
        var hadSuccess = false
        if countsAgainstInFlight {
            let outstanding = inFlightCount[bucket] ?? 0
            if outstanding > 0 {
                let remaining = outstanding - 1
                inFlightCount[bucket] = remaining == 0 ? nil : remaining
                lastOfBatch = (remaining == 0)
            } else {
                lastOfBatch = true
            }
            // Did an earlier fetch in this batch already succeed? If so, a trailing
            // failure must not re-increment the failure count or arm a retry.
            hadSuccess = batchHadSuccess[bucket] ?? false
        } else {
            // A direct update is its own single round ONLY when no tracked fetch is
            // outstanding; while a fetch is in flight it defers the round to that
            // fetch's completion (lastOfBatch=false), and it never touches the
            // fetch's inFlightCount/batchHadSuccess.
            lastOfBatch = (inFlightCount[bucket] ?? 0) == 0
        }

        var entry = cache[bucket] ?? Entry()
        entry.endpoint = endpoint
        entry.lastAttempt = nowProvider()
        var changed = false
        var scheduleRetry = false
        // A reachable server that momentarily returns an empty list (mid-reload)
        // must not wipe a previously-populated cache and persist the emptiness for
        // the full success TTL. Treat a non-empty -> empty transition as a soft
        // failure: keep the last good models and arm a bounded retry, exactly like a
        // fetch failure, so the picker repopulates on its own. (A first-ever empty,
        // i.e. no prior models, is still accepted as a genuine empty server.)
        let isSuspiciousEmpty = (result?.isEmpty ?? false) && entry.haveSucceeded && !entry.models.isEmpty
        // Escape hatch: after enough consecutive suspicious-empties, stop retaining
        // stale models and accept the empty list as the server's real (now-empty)
        // state - otherwise a server the user genuinely cleared would show deleted
        // models forever (persistence reloads them and every fetch is empty again).
        let acceptEmpty = isSuspiciousEmpty && (entry.consecutiveEmpties + 1) >= maxSuspiciousEmpties
        let suspiciousEmpty = isSuspiciousEmpty && !acceptEmpty
        if let result, !suspiciousEmpty {
            // Genuine success (non-empty), a first-ever empty, or a now-accepted empty.
            changed = !entry.haveSucceeded || entry.models != result
            entry.models = result
            entry.haveSucceeded = true
            entry.consecutiveFailures = 0
            entry.consecutiveEmpties = 0
            if countsAgainstInFlight && !lastOfBatch {
                batchHadSuccess[bucket] = true
            }
        } else if lastOfBatch && !hadSuccess {
            // Hard failure, or a not-yet-accepted suspicious empty: keep the last-good
            // models and arm a bounded retry.
            if suspiciousEmpty {
                entry.consecutiveEmpties += 1
            } else {
                // A hard failure (server down / 401) breaks the empty streak:
                // acceptEmpty must require GENUINELY consecutive empties, or empties
                // interleaved with failures on a flapping server would prematurely
                // wipe the retained models.
                entry.consecutiveEmpties = 0
            }
            entry.consecutiveFailures += 1
            scheduleRetry = entry.consecutiveFailures <= maxAutoRetries
        }
        // The batch is fully drained; clear its per-round success flag.
        if countsAgainstInFlight && lastOfBatch {
            batchHadSuccess[bucket] = nil
        }
        let failures = entry.consecutiveFailures
        let succeeded = (result != nil) || hadSuccess
        let finalCount = entry.models.count
        cache[bucket] = entry
        lock.unlock()

        if acceptEmpty {
            DLog("Ollama discovery for \(endpoint): accepted empty server after \(maxSuspiciousEmpties) empties; cleared cached models")
        } else if suspiciousEmpty {
            DLog("Ollama discovery for \(endpoint): empty result ignored, kept \(entry.models.count) cached model(s) (empties=\(entry.consecutiveEmpties)); scheduleRetry=\(scheduleRetry)")
        } else if let result {
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
        return BatchOutcome(lastOfBatch: lastOfBatch, succeeded: succeeded, count: finalCount)
    }

    // Convenience for a known-successful result (tests, seeding). Out-of-band: does
    // not participate in the in-flight/batch accounting of a concurrent live fetch.
    func update(endpoint: String, models: [AIMetadata.Model]) {
        update(endpoint: endpoint, result: models, countsAgainstInFlight: false)
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
        restore(from: Self.endpointsPruned(representation, keeping: Self.configuredBuckets()))
    }

    // Keep only the buckets in `configured`. Pure, so it's unit-testable.
    static func endpointsPruned(_ representation: [String: Any],
                                keeping configured: Set<String>) -> [String: Any] {
        return representation.filter { configured.contains($0.key) }
    }

    // The buckets the currently-configured dynamic entries fetch under. A
    // header-less entry's bucket is its bare URL, so a blob written before
    // buckets existed still matches.
    private static func configuredBuckets() -> Set<String> {
        return Set(LLMMetadata.dynamicOllamaConfigurations().map { bucket($0.url, $0.headers) })
    }

    // The serializable snapshot of the successfully-discovered models, keyed by
    // bucket. The bare endpoint travels in the value because the key may carry a
    // header digest and so cannot be used as a URL. Pure (no I/O) so it's
    // unit-testable.
    static let persistedEndpointKey = "endpoint"
    static let persistedModelsKey = "models"

    func persistedRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: Any] = [:]
        for (bucket, entry) in cache where entry.haveSucceeded {
            let endpoint = entry.endpoint.isEmpty ? bucket : entry.endpoint
            result[bucket] = [Self.persistedEndpointKey: endpoint,
                              Self.persistedModelsKey: entry.models.map { Self.dictionary(from: $0) }]
        }
        return result
    }

    // Seed the cache from a persisted snapshot. Entries are marked succeeded with
    // no lastAttempt, so shouldRefresh triggers a fresh fetch on the first read.
    func restore(from representation: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        for (bucket, value) in representation {
            // Seed only buckets with no in-memory entry: if an early read already
            // landed a live refresh, its fresh models must not be clobbered with the
            // (possibly stale) persisted set (which would also nil lastAttempt and
            // briefly resolve pinned tags against removed models).
            guard cache[bucket] == nil else { continue }
            let endpoint: String
            let dicts: [[String: Any]]
            if let wrapped = value as? [String: Any] {
                guard let url = wrapped[Self.persistedEndpointKey] as? String,
                      let models = wrapped[Self.persistedModelsKey] as? [[String: Any]] else {
                    continue
                }
                endpoint = url
                dicts = models
            } else if let legacy = value as? [[String: Any]] {
                // Blobs written before buckets existed are keyed by the bare
                // endpoint and hold the model list directly.
                endpoint = bucket
                dicts = legacy
            } else {
                continue
            }
            let models = dicts.compactMap { Self.model(from: $0, endpoint: endpoint) }
            cache[bucket] = Entry(endpoint: endpoint, models: models, haveSucceeded: true, lastAttempt: nil)
        }
    }

    private func persistIfEnabled() {
        guard persistenceEnabled else { return }
        // Persist only currently-configured endpoints: a "Refresh Models" probe of
        // an unsaved URL still seeds the in-memory cache, but it must not grow the
        // persisted blob unboundedly.
        let pruned = Self.endpointsPruned(persistedRepresentation(),
                                          keeping: Self.configuredBuckets())
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
