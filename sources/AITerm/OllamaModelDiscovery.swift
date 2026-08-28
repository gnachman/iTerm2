//
//  OllamaModelDiscovery.swift
//  iTerm2
//
//  Ollama exposes the models installed on a server at GET /api/tags. The manual
//  model editor uses this to let the user pick an installed model instead of
//  typing an exact tag. The URL-derivation and response-parsing are pure and
//  unit-tested; the fetch is a thin URLSession wrapper.
//

import Foundation

@objc(iTermOllamaModelDiscovery)
class OllamaModelDiscovery: NSObject {
    // The /api/tags URL for the server behind any configured Ollama endpoint,
    // keeping only scheme/host/port so it works whether the user pointed the
    // model at /api/chat (native) or /v1/chat/completions (OpenAI-compatible).
    @objc static func tagsURL(fromEndpoint endpoint: String) -> URL? {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme,
              let host = url.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        // Preserve basic-auth userinfo (user:pass@) so a server behind HTTP auth
        // is reachable for discovery, not just for chat requests.
        components.user = url.user
        components.password = url.password
        components.path = "/api/tags"
        return components.url
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            var name: String
            // Newer Ollama reports per-model capabilities and the real context
            // window right in /api/tags, so one call gives the whole picture.
            // Optional for older servers / unexpected shapes.
            var capabilities: [String]?
            var details: Details?
            struct Details: Decodable {
                var context_length: Int?
            }
        }
        var models: [Model]
    }

    // A conservative context window when the server doesn't report one.
    static let defaultContextWindow = 8_192

    // Model names from an /api/tags body, in server order. Empty for a body that
    // isn't the expected shape (so callers surface "no models" rather than crash).
    @objc static func modelNames(fromTagsResponse data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return []
        }
        return response.models.map { $0.name }
    }

    // Map an /api/tags body to catalog models for the given chat endpoint, or nil
    // if the body isn't a parseable /api/tags response (a network error page, a
    // proxy 401, garbage). Distinct from an empty [] (a reachable server with no
    // models), which the cache must not confuse with a failure.
    static func modelsIfParseable(fromTagsResponse data: Data, endpoint: String) -> [AIMetadata.Model]? {
        guard let response = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return nil
        }
        return response.models.map { entry in
            let caps = Set(entry.capabilities ?? [])
            // Ollama always supports streaming; the rest come from the server's
            // per-model capability list.
            var features: Set<AIMetadata.Model.Feature> = [.streaming]
            if caps.contains("tools") { features.insert(.functionCalling) }
            if caps.contains("thinking") { features.insert(.configurableThinking) }
            if caps.contains("vision") { features.insert(.vision) }
            let contextWindow = entry.details?.context_length ?? defaultContextWindow
            return AIMetadata.Model(
                name: entry.name,
                contextWindowTokens: contextWindow,
                maxResponseTokens: contextWindow,
                url: endpoint,
                api: .llama,
                features: features,
                vectorStoreConfig: .disabled,
                vendor: .llama)
        }
    }

    // Non-optional convenience: [] for both a failure and an empty server. Kept
    // for callers that don't need to tell the two apart.
    static func models(fromTagsResponse data: Data, endpoint: String) -> [AIMetadata.Model] {
        return modelsIfParseable(fromTagsResponse: data, endpoint: endpoint) ?? []
    }

    // The /api/tags request for an endpoint, carrying the entry's custom auth
    // headers (a header-authenticated Ollama behind a reverse proxy needs the
    // same token the chat path sends, or the probe 401s). Headers are
    // [{"name":..,"value":..}] like the manual-model config stores.
    static func tagsRequest(fromEndpoint endpoint: String,
                            headers: [[String: String]],
                            timeout: TimeInterval) -> URLRequest? {
        guard let url = tagsURL(fromEndpoint: endpoint) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        for header in headers {
            if let name = header["name"], let value = header["value"], !name.isEmpty {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        return request
    }

    // Fetch the installed model names. The completion runs on the main queue with
    // (names, errorMessage): names is empty and errorMessage is non-nil on any
    // failure (bad URL, network error, unparseable body, or an empty list).
    @objc static func fetchModelNames(fromEndpoint endpoint: String,
                                      headers: [[String: String]],
                                      timeout: TimeInterval,
                                      completion: @escaping ([String], String?) -> Void) {
        guard let request = tagsRequest(fromEndpoint: endpoint, headers: headers, timeout: timeout) else {
            DispatchQueue.main.async { completion([], "Could not derive an /api/tags URL from “\(endpoint)”.") }
            return
        }
        let host = request.url?.host ?? "the server"
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            let (names, message): ([String], String?) = {
                if let error {
                    return ([], "Could not reach Ollama at \(host): \(error.localizedDescription)")
                }
                guard let data else {
                    return ([], "Ollama returned no response.")
                }
                let names = modelNames(fromTagsResponse: data)
                return (names, names.isEmpty ? "No installed models were found on the Ollama server." : nil)
            }()
            DispatchQueue.main.async { completion(names, message) }
        }
        task.resume()
    }

    // Fetch the installed models mapped to capability-aware catalog models. The
    // completion runs on the main queue with nil on FAILURE (bad URL, network
    // error, unparseable/401 body) and a (possibly empty) array on SUCCESS, so the
    // cache can retry a failure without wedging an empty list. Carries the entry's
    // custom auth headers.
    static func fetchModels(fromEndpoint endpoint: String,
                            headers: [[String: String]],
                            timeout: TimeInterval,
                            completion: @escaping ([AIMetadata.Model]?) -> Void) {
        guard let request = tagsRequest(fromEndpoint: endpoint, headers: headers, timeout: timeout) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            let resolved: [AIMetadata.Model]? = {
                if error != nil { return nil }
                guard let data else { return nil }
                return Self.modelsIfParseable(fromTagsResponse: data, endpoint: endpoint)
            }()
            DispatchQueue.main.async { completion(resolved) }
        }
        task.resume()
    }
}
