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
    // Recognized chat-endpoint path suffixes. Discovery (/api/tags, /api/show) lives
    // at the SAME base as the chat path, so we strip one of these and keep any
    // leading prefix (e.g. a reverse proxy that serves Ollama under "/ollama"),
    // rather than discarding the whole path.
    private static let chatPathSuffixes = ["/api/chat", "/api/generate",
                                           "/v1/chat/completions", "/v1/completions"]

    // The base path of a configured chat endpoint: the path with a recognized chat
    // suffix removed, so "/ollama/api/chat" -> "/ollama" and "/api/chat" -> "".
    // Falls back to "" when no recognized suffix is present (bare host, or an
    // endpoint whose path we don't recognize), matching the historical behavior.
    private static func basePath(fromURLPath path: String) -> String {
        for suffix in chatPathSuffixes where path.hasSuffix(suffix) {
            return String(path.dropLast(suffix.count))
        }
        return ""
    }

    // Build a discovery URL (e.g. /api/tags, /api/show) for a configured chat
    // endpoint, keeping scheme/host/port/userinfo AND any leading path prefix.
    private static func discoveryURL(fromEndpoint endpoint: String, apiPath: String) -> URL? {
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
        components.path = basePath(fromURLPath: url.path) + apiPath
        return components.url
    }

    // The /api/tags URL for the server behind any configured Ollama endpoint. Works
    // whether the user pointed the model at /api/chat (native) or
    // /v1/chat/completions (OpenAI-compatible), and preserves a reverse-proxy prefix.
    @objc static func tagsURL(fromEndpoint endpoint: String) -> URL? {
        return discoveryURL(fromEndpoint: endpoint, apiPath: "/api/tags")
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

        // A wrapper whose init never throws, so decoding [FailableModel] consumes
        // every array element even when one is malformed. Used to decode `models`
        // leniently: a single bad entry (missing name, a proxy-wrapped shape) must
        // not fail the whole round, which the cache would treat as a failed fetch,
        // increment consecutiveFailures, and eventually stop auto-retrying.
        private struct FailableModel: Decodable {
            let model: Model?
            init(from decoder: Decoder) throws {
                model = try? Model(from: decoder)
            }
        }
        private enum CodingKeys: String, CodingKey {
            case models
        }
        init(from decoder: Decoder) throws {
            // A body that isn't {models: [...]} at all still throws here (a genuine
            // unparseable response), which the caller correctly treats as a failure;
            // only PER-ELEMENT errors are tolerated.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try container.decode([FailableModel].self, forKey: .models)
            models = raw.compactMap { $0.model }
        }
    }

    // Names of models whose /api/tags entry already carried BOTH capabilities and a
    // context_length, so a per-model /api/show probe would only re-derive what
    // modelsIfParseable already applied. Used to skip the probe (one HTTP round-trip
    // per model) on servers that fully describe models in /api/tags.
    private static func fullyDescribedModelNames(fromTagsResponse data: Data) -> Set<String> {
        guard let response = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return []
        }
        return Set(response.models
            .filter { $0.capabilities != nil && ($0.details?.context_length ?? 0) > 0 }
            .map { $0.name })
    }

    // The window to assume when neither /api/tags nor /api/show reports a context
    // length. Sized generously for modern Ollama models: num_ctx is still sized to
    // the prompt (Llama.computedNumCtx caps at this window but rounds to fit the
    // actual prompt), so this only RAISES the ceiling for large prompts rather than
    // wasting memory on small ones. The former 8192 silently capped genuinely large
    // models and rejected medium prompts they could handle.
    static let defaultContextWindow = 32_768

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
            // /api/tags does not carry per-model capabilities or context length on
            // most servers (those come from /api/show; fetchModels enriches with
            // them). Use them here only if a server does include them, else fall
            // back to streaming-only and the default window.
            let caps = Set(entry.capabilities ?? [])
            let contextWindow = entry.details?.context_length ?? defaultContextWindow
            return AIMetadata.Model(
                name: entry.name,
                contextWindowTokens: contextWindow,
                maxResponseTokens: contextWindow,
                url: endpoint,
                api: .llama,
                features: features(fromCapabilities: caps),
                vectorStoreConfig: .disabled,
                vendor: .llama)
        }
    }

    // Map an Ollama capability list to model features. Ollama always supports
    // streaming; the rest come from the server's per-model capability list
    // (reported by /api/show, and by /api/tags on servers that include it).
    static func features(fromCapabilities caps: Set<String>) -> Set<AIMetadata.Model.Feature> {
        var features: Set<AIMetadata.Model.Feature> = [.streaming]
        if caps.contains("tools") { features.insert(.functionCalling) }
        if caps.contains("thinking") { features.insert(.configurableThinking) }
        if caps.contains("vision") { features.insert(.vision) }
        return features
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
    //
    // /api/tags lists the installed models but NOT their capabilities or real
    // context window (those live on /api/show), so each discovered model is then
    // enriched with a per-model /api/show probe. A model whose /api/show probe
    // fails keeps the tags-derived fallback (streaming-only, default window) rather
    // than failing the whole discovery.
    static func fetchModels(fromEndpoint endpoint: String,
                            headers: [[String: String]],
                            timeout: TimeInterval,
                            completion: @escaping ([AIMetadata.Model]?) -> Void) {
        guard let request = tagsRequest(fromEndpoint: endpoint, headers: headers, timeout: timeout) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DLog("Ollama /api/tags fetch for \(endpoint) failed: \(error)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let data else {
                DLog("Ollama /api/tags fetch for \(endpoint) returned no data")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let base = Self.modelsIfParseable(fromTagsResponse: data, endpoint: endpoint) else {
                DLog("Ollama /api/tags fetch for \(endpoint) returned an unparseable body (\(data.count) bytes)")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if base.isEmpty {
                DispatchQueue.main.async { completion([]) }
                return
            }
            // Enrich each model with /api/show (capabilities + real context window),
            // EXCEPT models the server already fully described in /api/tags (both
            // capabilities and a context_length): modelsIfParseable already applied
            // those, so an /api/show probe would add nothing. Skipping them avoids one
            // HTTP round-trip per model on every refresh (a 20-model modern server
            // drops from 21 requests to 1).
            let complete = Self.fullyDescribedModelNames(fromTagsResponse: data)
            let group = DispatchGroup()
            var enriched = base
            let lock = NSLock()
            for (index, model) in base.enumerated() where !complete.contains(model.name) {
                group.enter()
                Self.fetchShow(fromEndpoint: endpoint, model: model.name,
                               headers: headers, timeout: timeout) { caps, contextWindow in
                    lock.lock()
                    // caps is nil when /api/show reported no usable capabilities (key
                    // absent OR empty array; normalized in capabilitiesAndContext), so
                    // only overwrite when it actually reported some: an unknown result
                    // keeps the tags-derived features (tools/vision) instead of
                    // dropping them to streaming-only.
                    if let caps {
                        enriched[index].features = Self.features(fromCapabilities: caps)
                    }
                    if let contextWindow, contextWindow > 0 {
                        enriched[index].contextWindowTokens = contextWindow
                        enriched[index].maxResponseTokens = contextWindow
                    }
                    lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) { completion(enriched) }
        }
        task.resume()
    }

    // The /api/show URL for an endpoint, derived like tagsURL (scheme/host/port,
    // preserving basic-auth userinfo AND any leading reverse-proxy path prefix).
    static func showURL(fromEndpoint endpoint: String) -> URL? {
        return discoveryURL(fromEndpoint: endpoint, apiPath: "/api/show")
    }

    // The POST /api/show request for one model, carrying the entry's custom auth
    // headers (same validation/normalization as the chat and tags paths).
    static func showRequest(fromEndpoint endpoint: String,
                            model: String,
                            headers: [[String: String]],
                            timeout: TimeInterval) -> URLRequest? {
        guard let url = showURL(fromEndpoint: endpoint) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in AICustomHeaders.merged(into: [:], customHeaders: headers) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model])
        return request
    }

    // Parse an /api/show body for a model's capabilities and real context window.
    // capabilities is a top-level array (["vision","tools","thinking",...]); the
    // context length is an architecture-prefixed key in model_info, e.g.
    // "qwen3.context_length". Either may be absent; the caller falls back.
    static func capabilitiesAndContext(fromShowResponse data: Data) -> (capabilities: Set<String>?, contextWindow: Int?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        // Distinguish ABSENT from PRESENT-but-empty: an absent capabilities key is
        // "unknown" (nil -> caller keeps the tags-derived fallback), but a present
        // "capabilities": [] is authoritative from the richer /api/show, so it
        // becomes an empty Set and the caller clears tools/vision. Keeping an empty
        // array as "unknown" would leave a non-tool model falsely tool-capable.
        let capabilities = (json["capabilities"] as? [String]).map { Set($0) }
        var contextWindow: Int?
        if let info = json["model_info"] as? [String: Any] {
            // A multimodal model reports more than one *.context_length key (a
            // vision/projector block plus the text model, e.g. "clip.vision..." and
            // "qwen3.context_length"). Dictionary iteration order is not
            // deterministic, so pick deterministically: prefer the key for the
            // model's own architecture (general.architecture), and otherwise take
            // the LARGEST TEXT-model window, excluding projector/vision blocks whose
            // context_length is the image encoder's, not the model's real window.
            // JSONSerialization yields NSNumber, so read every value as NSNumber.
            let architecture = info["general.architecture"] as? String
            if let architecture,
               let n = (info["\(architecture).context_length"] as? NSNumber)?.intValue {
                contextWindow = n
            } else {
                contextWindow = info
                    .filter { $0.key.hasSuffix(".context_length") && !Self.isProjectorInfoKey($0.key) }
                    .compactMap { ($0.value as? NSNumber)?.intValue }
                    .max()
            }
        }
        return (capabilities, contextWindow)
    }

    // Whether a model_info key belongs to a vision/projector block rather than the
    // text model, so its context_length isn't mistaken for the real window.
    private static func isProjectorInfoKey(_ key: String) -> Bool {
        return key.hasPrefix("clip.") || key.hasPrefix("mmproj") || key.contains(".vision.")
    }

    // Fetch one model's capabilities + context window from /api/show. The
    // completion runs on the URLSession queue with (nil, nil) on any failure so the
    // caller keeps the tags-derived fallback.
    private static func fetchShow(fromEndpoint endpoint: String,
                                  model: String,
                                  headers: [[String: String]],
                                  timeout: TimeInterval,
                                  completion: @escaping (Set<String>?, Int?) -> Void) {
        guard let request = showRequest(fromEndpoint: endpoint, model: model,
                                        headers: headers, timeout: timeout) else {
            completion(nil, nil)
            return
        }
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DLog("Ollama /api/show for \(model) at \(endpoint) failed: \(error)")
                completion(nil, nil)
                return
            }
            guard let data else {
                completion(nil, nil)
                return
            }
            let parsed = capabilitiesAndContext(fromShowResponse: data)
            completion(parsed.capabilities, parsed.contextWindow)
        }
        task.resume()
    }
}
