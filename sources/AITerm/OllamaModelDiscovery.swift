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
        components.path = "/api/tags"
        return components.url
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            var name: String
        }
        var models: [Model]
    }

    // Model names from an /api/tags body, in server order. Empty for a body that
    // isn't the expected shape (so callers surface "no models" rather than crash).
    @objc static func modelNames(fromTagsResponse data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            return []
        }
        return response.models.map { $0.name }
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
