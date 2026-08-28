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

    // Map an /api/tags body to catalog models for the given chat endpoint. This is
    // the heart of the dynamic provider: the model list AND each model's
    // capabilities/context window come from the server, so nothing is hand-typed.
    // `endpoint` is the native /api/chat URL the resolved models will POST to.
    static func models(fromTagsResponse data: Data, endpoint: String) -> [AIMetadata.Model] {
        guard let response = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return []
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

    // Fetch the installed model names. The completion runs on the main queue with
    // (names, errorMessage): names is empty and errorMessage is non-nil on any
    // failure (bad URL, network error, unparseable body, or an empty list).
    @objc static func fetchModelNames(fromEndpoint endpoint: String,
                                      timeout: TimeInterval,
                                      completion: @escaping ([String], String?) -> Void) {
        guard let url = tagsURL(fromEndpoint: endpoint) else {
            DispatchQueue.main.async { completion([], "Could not derive an /api/tags URL from “\(endpoint)”.") }
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            let (names, message): ([String], String?) = {
                if let error {
                    return ([], "Could not reach Ollama at \(url.host ?? "the server"): \(error.localizedDescription)")
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
}
