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
//  A FAILED fetch (server down at launch, a 401 from an auth proxy) is never
//  cached as a successful empty result: reads keep retrying (with a short
//  backoff) so the picker recovers on its own once the server comes up, instead
//  of wedging empty until a manual refresh or app restart. A SUCCESSFUL result is
//  re-fetched after a TTL so newly pulled models appear.
//

import Foundation

@objc(iTermOllamaModelCache)
class OllamaModelCache: NSObject {
    @objc(iTermOllamaModelCacheDidChangeNotification)
    static let didChangeNotification = Notification.Name("iTermOllamaModelCacheDidChange")

    @objc static let shared = OllamaModelCache()

    private struct Entry {
        // The last SUCCESSFUL result (may be empty for a reachable but empty
        // server). Empty and haveSucceeded=false is the never-succeeded state.
        var models: [AIMetadata.Model] = []
        var haveSucceeded = false
        // When the last fetch was ATTEMPTED (success or failure), for backoff/TTL.
        var lastAttempt: Date?
    }

    // Guards `cache` and `inFlight`. model resolution can run off the main thread
    // (request building), while refreshes complete on main, so both are locked.
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    // The URLRequest network timeout for a discovery fetch.
    private let networkTimeout: TimeInterval = 10
    // Re-fetch a SUCCESSFUL list after this long so newly pulled models appear.
    private let successTTL: TimeInterval = 300
    // Minimum spacing between retries after a FAILED fetch, so a down server
    // doesn't get hammered on every read.
    private let failureRetryInterval: TimeInterval = 5

    // Injectable clock so tests can exercise the TTL/backoff without waiting.
    var nowProvider: () -> Date = { Date() }

    // Whether a read should kick off a background refresh: never fetched, a prior
    // FAILURE past the retry backoff, or a SUCCESS past the TTL.
    func shouldRefresh(endpoint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldRefreshLocked(endpoint: endpoint)
    }

    private func shouldRefreshLocked(endpoint: String) -> Bool {
        guard let entry = cache[endpoint] else {
            return true  // never fetched
        }
        let elapsed = entry.lastAttempt.map { nowProvider().timeIntervalSince($0) } ?? .infinity
        return entry.haveSucceeded ? elapsed >= successTTL : elapsed >= failureRetryInterval
    }

    // The cached models for an endpoint. Kicks off a background refresh when the
    // entry is missing/stale; the pickers update via didChangeNotification when it
    // lands. `headers` are the entry's custom auth headers, applied to the probe.
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

    // Force a background refresh (e.g. the settings "refresh" affordance). Coalesces
    // concurrent refreshes of the same endpoint.
    @objc(refreshEndpoint:headers:)
    func refresh(endpoint: String, headers: [[String: String]] = []) {
        lock.lock()
        if inFlight.contains(endpoint) {
            lock.unlock()
            return
        }
        inFlight.insert(endpoint)
        lock.unlock()

        OllamaModelDiscovery.fetchModels(fromEndpoint: endpoint,
                                         headers: headers,
                                         timeout: networkTimeout) { [weak self] result in
            self?.update(endpoint: endpoint, result: result)
        }
    }

    // Record a fetch outcome. nil = failure: keep the previous models but stamp the
    // attempt time so the next read retries after the backoff. Non-nil = success:
    // replace the models and, if the list changed, post didChangeNotification.
    func update(endpoint: String, result: [AIMetadata.Model]?) {
        lock.lock()
        var entry = cache[endpoint] ?? Entry()
        entry.lastAttempt = nowProvider()
        var changed = false
        if let result {
            changed = !entry.haveSucceeded || entry.models != result
            entry.models = result
            entry.haveSucceeded = true
        }
        cache[endpoint] = entry
        inFlight.remove(endpoint)
        lock.unlock()

        if changed {
            if Thread.isMainThread {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                }
            }
        }
    }

    // Convenience for a known-successful result (tests, seeding).
    func update(endpoint: String, models: [AIMetadata.Model]) {
        update(endpoint: endpoint, result: models)
    }
}
