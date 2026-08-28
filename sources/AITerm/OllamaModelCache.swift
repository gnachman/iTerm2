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
        // Kept so a self-healing retry re-authenticates the same way.
        var headers: [[String: String]] = []
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    private let networkTimeout: TimeInterval = 10
    private let successTTL: TimeInterval = 300
    private let failureRetryInterval: TimeInterval = 5
    // Stop the timer-driven retry loop after this many consecutive failures so a
    // permanently-down server isn't probed forever; read-driven recovery remains.
    let maxAutoRetries = 6

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
        if !force && inFlight.contains(endpoint) {
            lock.unlock()
            return
        }
        inFlight.insert(endpoint)
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
        var entry = cache[endpoint] ?? Entry()
        entry.lastAttempt = nowProvider()
        entry.headers = headers
        var changed = false
        var scheduleRetry = false
        if let result {
            changed = !entry.haveSucceeded || entry.models != result
            entry.models = result
            entry.haveSucceeded = true
            entry.consecutiveFailures = 0
        } else {
            entry.consecutiveFailures += 1
            scheduleRetry = entry.consecutiveFailures <= maxAutoRetries
        }
        cache[endpoint] = entry
        inFlight.remove(endpoint)
        lock.unlock()

        if scheduleRetry {
            retryScheduler(failureRetryInterval) { [weak self] in
                self?.refresh(endpoint: endpoint, headers: headers)
            }
        }
        if changed {
            postDidChange()
        }
    }

    // Convenience for a known-successful result (tests, seeding).
    func update(endpoint: String, models: [AIMetadata.Model]) {
        update(endpoint: endpoint, result: models)
    }

    private func postDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }
}
