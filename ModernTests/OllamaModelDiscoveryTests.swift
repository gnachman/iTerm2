//
//  OllamaModelDiscoveryTests.swift
//  iTerm2 ModernTests
//
//  The pure parts of Ollama model discovery: deriving the /api/tags URL from
//  whatever endpoint the user configured, and parsing the installed-model list.
//

import XCTest
@testable import iTerm2SharedARC

final class OllamaModelDiscoveryTests: XCTestCase {

    // /api/tags is derived from scheme+host+port, regardless of the configured
    // path, so it works for both the native and OpenAI-compatible endpoints.
    func test_tagsURL_fromNativeEndpoint() {
        let url = OllamaModelDiscovery.tagsURL(fromEndpoint: "http://localhost:11434/api/chat")
        XCTAssertEqual(url?.absoluteString, "http://localhost:11434/api/tags")
    }

    func test_tagsURL_fromCompatEndpoint() {
        let url = OllamaModelDiscovery.tagsURL(fromEndpoint: "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:11434/api/tags")
    }

    func test_tagsURL_preservesCustomHostAndPort() {
        let url = OllamaModelDiscovery.tagsURL(fromEndpoint: "https://ollama.example.com:9999/api/chat")
        XCTAssertEqual(url?.absoluteString, "https://ollama.example.com:9999/api/tags")
    }

    // A server behind HTTP basic auth encodes credentials in the URL; the tags
    // request must keep them or it 401s while normal chat requests work.
    func test_tagsURL_preservesBasicAuthUserinfo() {
        let url = OllamaModelDiscovery.tagsURL(fromEndpoint: "http://user:pass@host:11434/api/chat")
        XCTAssertEqual(url?.absoluteString, "http://user:pass@host:11434/api/tags")
    }

    func test_tagsURL_invalidEndpoint_isNil() {
        XCTAssertNil(OllamaModelDiscovery.tagsURL(fromEndpoint: ""))
        XCTAssertNil(OllamaModelDiscovery.tagsURL(fromEndpoint: "not a url"))
    }

    // A scheme-less "host:port" endpoint (a common user input) must still resolve
    // for discovery, defaulting to http, instead of failing permanently.
    func test_tagsURL_defaultsMissingSchemeToHTTP() {
        XCTAssertEqual(OllamaModelDiscovery.tagsURL(fromEndpoint: "localhost:11434")?.absoluteString,
                       "http://localhost:11434/api/tags")
        XCTAssertEqual(OllamaModelDiscovery.tagsURL(fromEndpoint: "localhost:11434/api/chat")?.absoluteString,
                       "http://localhost:11434/api/tags")
    }

    func test_modelNames_parsesTagsResponse() {
        let body = Data("""
        {"models":[{"name":"qwen3.5:4b","size":1},{"name":"llama3.3:latest","size":2}]}
        """.utf8)
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: body),
                       ["qwen3.5:4b", "llama3.3:latest"])
    }

    // The dynamic-provider core: /api/tags maps to catalog models with features
    // and context windows straight from the server, no hand-typing.
    func test_models_mapsCapabilitiesAndContextWindow() {
        let body = Data("""
        {"models":[
          {"name":"qwen3.5:4b","capabilities":["vision","completion","tools","thinking"],"details":{"context_length":262144}},
          {"name":"llama3.3:latest","capabilities":["completion","tools"],"details":{"context_length":131072}}
        ]}
        """.utf8)
        let models = OllamaModelDiscovery.models(fromTagsResponse: body,
                                                 endpoint: "http://localhost:11434/api/chat")
        XCTAssertEqual(models.map { $0.name }, ["qwen3.5:4b", "llama3.3:latest"])

        let qwen = models[0]
        XCTAssertEqual(qwen.api, .llama)
        XCTAssertEqual(qwen.url, "http://localhost:11434/api/chat")
        XCTAssertEqual(qwen.vendor, .llama)
        XCTAssertEqual(qwen.contextWindowTokens, 262_144)
        XCTAssertTrue(qwen.features.isSuperset(of: [.streaming, .functionCalling, .configurableThinking, .vision]))

        let llama = models[1]
        XCTAssertEqual(llama.contextWindowTokens, 131_072)
        XCTAssertTrue(llama.features.contains(.functionCalling))
        XCTAssertFalse(llama.features.contains(.vision), "llama3.3 has no vision capability")
        XCTAssertFalse(llama.features.contains(.configurableThinking), "llama3.3 has no thinking capability")
    }

    func test_models_missingCapabilitiesAndDetails_usesSafeDefaults() {
        let models = OllamaModelDiscovery.models(fromTagsResponse: Data("{\"models\":[{\"name\":\"x\"}]}".utf8),
                                                 endpoint: "u")
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].features, [.streaming],
                       "no capabilities -> only streaming (which Ollama always supports)")
        XCTAssertEqual(models[0].contextWindowTokens, OllamaModelDiscovery.defaultContextWindow)
    }

    func test_models_garbage_isEmpty() {
        XCTAssertEqual(OllamaModelDiscovery.models(fromTagsResponse: Data("nope".utf8), endpoint: "u").count, 0)
    }

    // The cache needs to tell a FAILURE (unparseable/401 body) apart from a
    // reachable-but-empty server, or a transient failure wedges the picker empty.
    func test_modelsIfParseable_distinguishesFailureFromEmpty() {
        XCTAssertNil(OllamaModelDiscovery.modelsIfParseable(fromTagsResponse: Data("garbage".utf8), endpoint: "u"),
                     "unparseable body -> nil (failure)")
        XCTAssertEqual(OllamaModelDiscovery.modelsIfParseable(fromTagsResponse: Data("{\"models\":[]}".utf8), endpoint: "u")?.count, 0,
                       "reachable but empty server -> [] (success)")
    }

    // The discovery probe must carry the entry's custom auth headers (a
    // header-authenticated Ollama behind a proxy 401s /api/tags otherwise).
    func test_tagsRequest_appliesCustomHeaders() {
        let request = OllamaModelDiscovery.tagsRequest(
            fromEndpoint: "http://h:11434/api/chat",
            headers: [["name": "Authorization", "value": "Bearer tok"]],
            timeout: 5)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request?.url?.absoluteString, "http://h:11434/api/tags")
        XCTAssertEqual(request?.timeoutInterval, 5)
    }

    func test_tagsRequest_invalidURL_isNil() {
        XCTAssertNil(OllamaModelDiscovery.tagsRequest(fromEndpoint: "", headers: [], timeout: 5))
    }

    func test_modelNames_emptyOrGarbage_isEmpty() {
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: Data("{}".utf8)), [])
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: Data("not json".utf8)), [])
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: Data("{\"models\":[]}".utf8)), [])
    }
}
