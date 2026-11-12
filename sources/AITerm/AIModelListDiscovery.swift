//
//  AIModelListDiscovery.swift
//  iTerm2
//
//  OpenAI-compatible servers (vLLM, LM Studio, llama.cpp, LiteLLM, hosted
//  gateways) and Anthropic-compatible ones list their models at GET <base>/models
//  as {"data":[{"id":...}]}. The manual model editor's Fetch Models button uses
//  this for every API except Ollama's native one (which uses /api/tags; see
//  OllamaModelDiscovery) and Gemini. The URL derivation, parsing, and request
//  building are pure and unit-tested; the fetch is a thin URLSession wrapper.
//

import Foundation

@objc(iTermAIModelListDiscovery)
class AIModelListDiscovery: NSObject {
    // Endpoint path suffixes for the APIs this lister serves. The listing lives at
    // the same base, so one of these is replaced by /models and any prefix (/v1,
    // /api/v1, /api/paas/v4) is kept.
    private static let endpointSuffixes = ["/chat/completions", "/completions",
                                           "/messages", "/responses"]

    @objc(supportsAPI:)
    static func supports(api: iTermAIAPI) -> Bool {
        switch api {
        case .chatCompletions, .completions, .responses, .earlyO1, .deepSeek, .anthropic:
            return true
        case .llama, .gemini, .appleIntelligence:
            return false
        @unknown default:
            return false
        }
    }

    // The path of the listing for an endpoint path. A base URL is first
    // completed to the endpoint chat would post to (LLMProvider's rule, so the
    // two agree), and then a recognized suffix is swapped for /models. A path
    // that already is the listing (“/v1/models”, pasted from server docs) is
    // kept. Any other path is taken as a base the listing lives under.
    private static func modelsPath(fromURLPath rawPath: String, api: iTermAIAPI) -> String {
        var path = LLMProvider.endpointPath(forBasePath: rawPath, api: api) ?? rawPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        // Already the listing URL (pasted from a server's docs).
        if path.hasSuffix("/models") {
            return path
        }
        for suffix in endpointSuffixes where path.hasSuffix(suffix) {
            return String(path.dropLast(suffix.count)) + "/models"
        }
        return path + "/models"
    }

    // nil for an endpoint that can't be parsed, and for one with the model in its
    // path, which names a single model rather than a server we can list.
    static func modelsURL(fromEndpoint endpoint: String, api: iTermAIAPI) -> URL? {
        if endpoint.contains("{{MODEL}}") {
            return nil
        }
        return OllamaModelDiscovery.discoveryURL(fromEndpoint: endpoint) {
            modelsPath(fromURLPath: $0, api: api)
        }
    }

    private struct ModelsResponse: Decodable {
        // Never throws, so one malformed element doesn't fail the whole list.
        struct FailableModel: Decodable {
            let id: String?
            private enum CodingKeys: String, CodingKey {
                case id
            }
            init(from decoder: Decoder) throws {
                id = try? decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
            }
        }
        var data: [FailableModel]

        var ids: [String] {
            return data.compactMap { $0.id }.filter { !$0.isEmpty }
        }
    }

    // Model ids from a /models body, in server order. Empty for a body that isn't
    // the expected shape, so callers report “no models” rather than crash.
    static func modelNames(fromModelsResponse data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        return response.ids
    }

    // Anthropic pages its listing at 20 models by default, which would silently
    // truncate the menu, so ask for its maximum page (1000) unless the user's URL
    // already sets a limit. OpenAI-style servers return everything in one page.
    private static func listingURL(_ url: URL, api: iTermAIAPI) -> URL? {
        guard api == .anthropic else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "limit" }) {
            items.append(URLQueryItem(name: "limit", value: "1000"))
        }
        components.queryItems = items
        return components.url
    }

    // The GET /models request. `apiKey` goes in whatever header the API carries
    // its credential in (exactly as a chat request would), and is nil when the
    // configuration withholds the key. Custom headers are merged last, like the
    // chat path, so a token the user configured there wins.
    static func modelsRequest(fromEndpoint endpoint: String,
                              api: iTermAIAPI,
                              apiKey: String?,
                              headers: [[String: String]],
                              timeout: TimeInterval) -> URLRequest? {
        guard let url = modelsURL(fromEndpoint: endpoint, api: api).flatMap({ listingURL($0, api: api) }) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        var fields = [String: String]()
        if let apiKey {
            let model = AIMetadata.Model(name: "",
                                         contextWindowTokens: 0,
                                         maxResponseTokens: 0,
                                         url: endpoint,
                                         api: api,
                                         features: [],
                                         vectorStoreConfig: .disabled,
                                         vendor: nil)
            fields = LLMAuthorizationProvider(provider: LLMProvider(model: model), apiKey: apiKey).headers
        } else if api == .anthropic {
            // Not a credential: Anthropic-compatible servers may require it on
            // every request.
            fields["anthropic-version"] = "2023-06-01"
        }
        for (name, value) in AICustomHeaders.merged(into: fields, customHeaders: headers) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    // The key a chat request for this editor configuration would send, without
    // prompting for one: nil when the configuration withholds it (a local or
    // unrecognized host, or API key: None), when it uses its own key and none is
    // typed, or when no key is stored. Fetch Models never prompts, since a missing
    // key is fine for the many servers whose listing is public.
    @objc(apiKeyForURL:api:modelName:credential:modelAPIKey:)
    static func apiKey(url: String,
                       api: iTermAIAPI,
                       modelName: String,
                       credential storedCredential: String?,
                       modelAPIKey: String?) -> String? {
        let credential = AIModelCredential(storedValue: storedCredential)
        let keyVendor: iTermAIVendor
        if case .vendorKey(let chosen) = credential {
            keyVendor = chosen
        } else {
            keyVendor = LLMMetadata.objcManualVendor(api: api, url: url, modelName: modelName)
        }
        if AITermController.usesPlaceholderAPIKey(url: url, api: api, credential: credential, keyVendor: keyVendor) {
            return nil
        }
        let key: String?
        if credential == .modelKey {
            key = modelAPIKey
        } else {
            key = AITermControllerObjC.apiKey(for: keyVendor)
        }
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != AITermController.reviewPlaceholderAPIKey else {
            return nil
        }
        return trimmed
    }

    // A URL for error messages, without userinfo (a user:pass@ password) or a
    // query (which may carry a token), so neither ends up on screen or in a
    // screenshot attached to a bug report. Scheme, host, port, and path stay so
    // the user can see which listing was tried. Text that doesn't parse as a URL
    // is returned unchanged. The result is percent-decoded so a {{MODEL}}
    // template reads as typed.
    static func displayString(forURL urlString: String) -> String {
        // Text with characters URLComponents rejects on some macOS versions (the
        // braces of {{MODEL}}) is parsed encoded, so its credentials are still
        // removed. The decode below undoes the extra encoding.
        let parsed = URLComponents(string: urlString) ??
            urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { URLComponents(string: $0) }
        guard var components = parsed, components.host != nil else {
            return urlString
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        guard let string = components.string else {
            return urlString
        }
        return string.removingPercentEncoding ?? string
    }

    // Fetch the model ids. The completion runs on the main queue with
    // (names, errorMessage): names is empty and errorMessage is non-nil on any
    // failure (bad URL, network error, HTTP error, unparseable body, or an empty
    // list).
    @objc(fetchModelNamesFromEndpoint:api:apiKey:headers:timeout:completion:)
    static func fetchModelNames(fromEndpoint endpoint: String,
                                api: iTermAIAPI,
                                apiKey: String?,
                                headers: [[String: String]],
                                timeout: TimeInterval,
                                completion: @escaping ([String], String?) -> Void) {
        guard let request = modelsRequest(fromEndpoint: endpoint,
                                          api: api,
                                          apiKey: apiKey,
                                          headers: headers,
                                          timeout: timeout),
              let requestURL = request.url?.absoluteString else {
            DispatchQueue.main.async {
                completion([], String(localized: "AIModelList.BadURL",
                                      defaultValue: "Could not work out where “\(displayString(forURL: endpoint))” lists its models.",
                                      comment: "Error shown by Fetch Models in the AI model editor when the server URL can't be turned into a model-listing URL; %@ is the URL the user entered"))
            }
            return
        }
        let shownURL = displayString(forURL: requestURL)
        let task = OllamaModelDiscovery.proxiedDataTask(with: request) { data, response, error in
            let (names, message): ([String], String?) = {
                if let error {
                    return ([], String(localized: "AIModelList.Unreachable",
                                       defaultValue: "Could not reach \(shownURL) to list its models: \(error.localizedDescription)",
                                       comment: "Error shown by Fetch Models in the AI model editor when the server can't be reached; first %@ is the model-listing URL, second %@ is the underlying network error"))
                }
                if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                    return ([], String(localized: "AIModelList.HTTPError",
                                       defaultValue: "\(shownURL) returned HTTP status \(status). The server may not support listing models, or may need authentication.",
                                       comment: "Error shown by Fetch Models in the AI model editor when the server answers with an HTTP error; first placeholder is the model-listing URL, second is the numeric HTTP status code"))
                }
                let names = data.map { modelNames(fromModelsResponse: $0) } ?? []
                return (names, names.isEmpty ? String(localized: "AIModelList.NoModels",
                                                      defaultValue: "\(shownURL) did not list any models.",
                                                      comment: "Error shown by Fetch Models in the AI model editor when the server's model list is empty or unreadable; %@ is the model-listing URL") : nil)
            }()
            DispatchQueue.main.async { completion(names, message) }
        }
        task.resume()
    }
}
