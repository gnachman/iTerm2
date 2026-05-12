//
//  MomentermLocalLLMDetector.swift
//  iTerm2
//
//  Detects locally running LLM backends (Ollama, LM Studio) and lists their models.
//

import Foundation

struct MomentermLocalLLMStatus {
    let backend: MomentermLocalLLMBackend
    let endpoint: URL?
    let models: [String]

    static let unavailable = MomentermLocalLLMStatus(backend: .none, endpoint: nil, models: [])
    var isAvailable: Bool { backend != .none }
}

@objc final class MomentermLocalLLMDetector: NSObject {

    private static let cacheTTL: TimeInterval = 300  // 5 min
    private static let requestTimeout: TimeInterval = 1.5

    private static var cachedStatus: MomentermLocalLLMStatus?
    private static var cachedAt: Date?
    private static let cacheQueue = DispatchQueue(label: "com.momenterm.localllm.cache")

    /// Probes Ollama first, then LM Studio. Returns first one that responds within timeout.
    /// Completion called on the main queue.
    static func detect(forceRefresh: Bool = false, completion: @escaping (MomentermLocalLLMStatus) -> Void) {
        if !forceRefresh, let cached = cachedValue() {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = probeOllama() ?? probeLMStudio() ?? .unavailable
            storeCache(result)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Synchronous cache read for cases where the UI just needs the last-known status.
    static func cachedValue() -> MomentermLocalLLMStatus? {
        cacheQueue.sync {
            guard let status = cachedStatus, let at = cachedAt else { return nil }
            return Date().timeIntervalSince(at) < cacheTTL ? status : nil
        }
    }

    private static func storeCache(_ status: MomentermLocalLLMStatus) {
        cacheQueue.sync {
            cachedStatus = status
            cachedAt = Date()
        }
    }

    // MARK: - Backend probes

    private static func probeOllama() -> MomentermLocalLLMStatus? {
        guard let url = URL(string: "http://localhost:11434/api/tags"),
              let data = fetch(url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["models"] as? [[String: Any]] else { return nil }
        let names = arr.compactMap { $0["name"] as? String }.sorted()
        return MomentermLocalLLMStatus(
            backend: .ollama,
            endpoint: URL(string: "http://localhost:11434"),
            models: names)
    }

    private static func probeLMStudio() -> MomentermLocalLLMStatus? {
        guard let url = URL(string: "http://localhost:1234/v1/models"),
              let data = fetch(url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else { return nil }
        let names = arr.compactMap { $0["id"] as? String }.sorted()
        return MomentermLocalLLMStatus(
            backend: .lmStudio,
            endpoint: URL(string: "http://localhost:1234"),
            models: names)
    }

    // MARK: - Synchronous HTTP (bounded by timeout)

    private static func fetch(_ url: URL) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + requestTimeout + 0.5)
        if result == nil { task.cancel() }
        return result
    }
}
