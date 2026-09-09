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
        var url = URL(string: endpoint)
        // A scheme-less "host:port[/path]" parses with scheme="host" and host=nil
        // (e.g. "localhost:11434"), which would fail discovery permanently. Default
        // a missing scheme to http:// so a bare host:port endpoint is usable.
        if url?.host == nil, !endpoint.contains("://") {
            url = URL(string: "http://" + endpoint)
        }
        guard let url,
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
        // Validate/normalize exactly like the chat path (AICustomHeaders.merged:
        // RFC-7230 name check, control-char value rejection, field-log breadcrumbs)
        // so discovery and chat authenticate with the SAME header set.
        for (name, value) in AICustomHeaders.merged(into: [:], customHeaders: headers) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    // A human-readable label for the server behind an endpoint, used to name a
    // dynamic provider entry. Normalizes a missing scheme the same way tagsURL
    // does and INCLUDES the scheme, so scheme-less hosts don't all collapse to one
    // label and http/https to the same host stay distinct. e.g.
    // "localhost:11434" -> "http://localhost:11434".
    @objc(serverLabelForEndpoint:)
    static func serverLabel(forEndpoint endpoint: String) -> String {
        guard let url = tagsURL(fromEndpoint: endpoint),
              let scheme = url.scheme,
              let host = url.host else {
            return endpoint
        }
        let hostPort = url.port.map { "\(host):\($0)" } ?? host
        return "\(scheme)://\(hostPort)"
    }

    // Fetch the installed model names. The completion runs on the main queue with
    // (names, errorMessage): names is empty and errorMessage is non-nil on any
    // failure (bad URL, network error, unparseable body, or an empty list).
    @objc static func fetchModelNames(fromEndpoint endpoint: String,
                                      headers: [[String: String]],
                                      timeout: TimeInterval,
                                      completion: @escaping ([String], String?) -> Void) {
        guard let request = tagsRequest(fromEndpoint: endpoint, headers: headers, timeout: timeout) else {
            DispatchQueue.main.async {
                completion([], String(localized: "Ollama.Discovery.BadURL",
                                      defaultValue: "Could not derive an /api/tags URL from “\(endpoint)”.",
                                      comment: "Error shown when the Ollama server URL can't be turned into a model-listing URL; %@ is the URL the user entered"))
            }
            return
        }
        let host = request.url?.host ?? String(localized: "Ollama.Discovery.GenericServer",
                                               defaultValue: "the server",
                                               comment: "Fallback name for the Ollama server when its hostname is unknown, inserted into a “Could not reach …” error")
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            let (names, message): ([String], String?) = {
                if let error {
                    return ([], String(localized: "Ollama.Discovery.Unreachable",
                                       defaultValue: "Could not reach Ollama at \(host): \(error.localizedDescription)",
                                       comment: "Error shown when the Ollama server can't be reached; first %@ is the host, second %@ is the underlying network error"))
                }
                guard let data else {
                    return ([], String(localized: "Ollama.Discovery.NoResponse",
                                       defaultValue: "Ollama returned no response.",
                                       comment: "Error shown when the Ollama server returned no data"))
                }
                let names = modelNames(fromTagsResponse: data)
                return (names, names.isEmpty ? String(localized: "Ollama.Discovery.NoModels",
                                                      defaultValue: "No installed models were found on the Ollama server.",
                                                      comment: "Error shown when the Ollama server reports zero installed models") : nil)
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
                if let error {
                    DLog("Ollama /api/tags fetch for \(endpoint) failed: \(error)")
                    return nil
                }
                guard let data else {
                    DLog("Ollama /api/tags fetch for \(endpoint) returned no data")
                    return nil
                }
                let models = Self.modelsIfParseable(fromTagsResponse: data, endpoint: endpoint)
                if models == nil {
                    DLog("Ollama /api/tags fetch for \(endpoint) returned an unparseable body (\(data.count) bytes)")
                }
                return models
            }()
            DispatchQueue.main.async { completion(resolved) }
        }
        task.resume()
    }
}
