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

import Foundation

@objc(iTermOllamaModelCache)
class OllamaModelCache: NSObject {
    @objc(iTermOllamaModelCacheDidChangeNotification)
    static let didChangeNotification = Notification.Name("iTermOllamaModelCacheDidChange")

    @objc static let shared = OllamaModelCache()

    // Guards `cache` and `inFlight`. model resolution can run off the main thread
    // (request building), while refreshes complete on main, so both are locked.
    private let lock = NSLock()
    private var cache: [String: [AIMetadata.Model]] = [:]
    private var inFlight: Set<String> = []

    // How long a fetched list is trusted before models(forEndpoint:) kicks off a
    // background refresh on the next read.
    private let refreshTimeout: TimeInterval = 10

    // The cached models for an endpoint. If nothing is cached yet, returns [] and
    // kicks off a background refresh; the pickers update via didChangeNotification
    // when it lands.
    func models(forEndpoint endpoint: String) -> [AIMetadata.Model] {
        lock.lock()
        let cached = cache[endpoint]
        lock.unlock()
        if cached == nil {
            refresh(endpoint: endpoint)
        }
        return cached ?? []
    }

    // Force a background refresh (e.g. the settings "refresh" affordance). Coalesces
    // concurrent refreshes of the same endpoint.
    func refresh(endpoint: String) {
        lock.lock()
        if inFlight.contains(endpoint) {
            lock.unlock()
            return
        }
        inFlight.insert(endpoint)
        lock.unlock()

        OllamaModelDiscovery.fetchModels(fromEndpoint: endpoint, timeout: refreshTimeout) { [weak self] models in
            self?.update(endpoint: endpoint, models: models)
        }
    }

    // Replace the cached models for an endpoint and, if the list actually changed,
    // post didChangeNotification so pickers rebuild. Internal so tests can seed the
    // cache without a live server.
    func update(endpoint: String, models: [AIMetadata.Model]) {
        lock.lock()
        let changed = cache[endpoint] != models
        cache[endpoint] = models
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
}
