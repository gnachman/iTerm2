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

    // The discovery probe must validate headers the same way the chat path does
    // (AICustomHeaders): a bad RFC-7230 name or a control-char value is dropped, so
    // discovery and chat authenticate with the same set.
    func test_tagsRequest_validatesHeadersLikeChatPath() {
        let request = OllamaModelDiscovery.tagsRequest(
            fromEndpoint: "http://h/api/chat",
            headers: [
                ["name": "Authorization", "value": "Bearer ok"],
                ["name": "Bad Name", "value": "x"],          // space -> invalid name
                ["name": "X-Ctrl", "value": "line1\nline2"],  // control char -> invalid value
            ],
            timeout: 5)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer ok")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Bad Name"), "invalid header name must be dropped")
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-Ctrl"), "control-char value must be dropped")
    }

    // Server labels must distinguish scheme-less hosts (so two different servers
    // don't collide) and http vs https (distinct endpoints).
    func test_serverLabel_distinguishesHostsAndScheme() {
        XCTAssertEqual(OllamaModelDiscovery.serverLabel(forEndpoint: "localhost:11434"), "http://localhost:11434")
        XCTAssertEqual(OllamaModelDiscovery.serverLabel(forEndpoint: "10.0.0.5:11434"), "http://10.0.0.5:11434")
        XCTAssertNotEqual(OllamaModelDiscovery.serverLabel(forEndpoint: "localhost:11434"),
                          OllamaModelDiscovery.serverLabel(forEndpoint: "10.0.0.5:11434"))
        XCTAssertNotEqual(OllamaModelDiscovery.serverLabel(forEndpoint: "http://gpu1:11434"),
                          OllamaModelDiscovery.serverLabel(forEndpoint: "https://gpu1:11434"))
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

    // A single malformed entry (here: missing the required `name`) must not fail the
    // whole /api/tags round, which the cache would treat as a failed fetch and
    // eventually stop auto-retrying. The good entries still come through.
    func test_modelNames_skipsMalformedEntry() {
        let body = Data(#"{"models":[{"name":"good:7b"},{"details":{"context_length":4096}},{"name":"also-good:3b"}]}"#.utf8)
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: body),
                       ["good:7b", "also-good:3b"],
                       "a single entry missing name must be skipped, not poison the whole list")
    }

    // MARK: - /api/show enrichment (capabilities + real context window)

    // /api/tags lists models but not their capabilities/context window on a real
    // server, so discovery enriches from /api/show. Its capabilities live in a
    // top-level array and the context length in an architecture-prefixed model_info
    // key (e.g. "qwen3.context_length").
    func test_capabilitiesAndContext_fromShowResponse() {
        let body = Data("""
        {"capabilities":["completion","tools","vision","thinking"],
         "model_info":{"general.architecture":"qwen3","qwen3.context_length":262144,"qwen3.attention.head_count":40}}
        """.utf8)
        let (caps, ctx) = OllamaModelDiscovery.capabilitiesAndContext(fromShowResponse: body)
        XCTAssertEqual(caps, ["completion", "tools", "vision", "thinking"])
        XCTAssertEqual(ctx, 262_144)
    }

    func test_capabilitiesAndContext_missingFields_areNil() {
        let (caps, ctx) = OllamaModelDiscovery.capabilitiesAndContext(fromShowResponse: Data("{}".utf8))
        XCTAssertNil(caps, "no capabilities key -> nil (caller keeps the tags fallback)")
        XCTAssertNil(ctx, "no context_length key -> nil (caller keeps the default window)")

        let (garbageCaps, garbageCtx) = OllamaModelDiscovery.capabilitiesAndContext(fromShowResponse: Data("garbage".utf8))
        XCTAssertNil(garbageCaps)
        XCTAssertNil(garbageCtx)
    }

    // /api/show is derived from scheme+host+port exactly like /api/tags, so it
    // works regardless of the configured chat path and for scheme-less hosts.
    func test_showURL_derivedLikeTagsURL() {
        XCTAssertEqual(OllamaModelDiscovery.showURL(fromEndpoint: "http://localhost:11434/api/chat")?.absoluteString,
                       "http://localhost:11434/api/show")
        XCTAssertEqual(OllamaModelDiscovery.showURL(fromEndpoint: "https://ollama.example.com:9999/v1/chat/completions")?.absoluteString,
                       "https://ollama.example.com:9999/api/show")
        XCTAssertEqual(OllamaModelDiscovery.showURL(fromEndpoint: "localhost:11434")?.absoluteString,
                       "http://localhost:11434/api/show")
    }

    // The /api/show request POSTs the model name and carries the entry's custom
    // auth headers (a header-authenticated server 401s /api/show otherwise).
    func test_showRequest_postsModelAndAppliesHeaders() throws {
        let request = try XCTUnwrap(OllamaModelDiscovery.showRequest(
            fromEndpoint: "http://h:11434/api/chat",
            model: "qwen3.5:4b",
            headers: [["name": "Authorization", "value": "Bearer tok"]],
            timeout: 5))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://h:11434/api/show")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen3.5:4b")
    }

    func test_features_fromCapabilities() {
        XCTAssertEqual(OllamaModelDiscovery.features(fromCapabilities: []), [.streaming],
                       "Ollama always supports streaming")
        XCTAssertEqual(OllamaModelDiscovery.features(fromCapabilities: ["tools", "vision", "thinking"]),
                       [.streaming, .functionCalling, .vision, .configurableThinking])
        XCTAssertEqual(OllamaModelDiscovery.features(fromCapabilities: ["completion"]), [.streaming],
                       "completion-only maps to streaming only")
    }

    // MARK: - Regression tests for review findings (currently FAILING)

    // Finding: a present-but-empty "capabilities" array decodes to a NON-nil empty
    // Set, and fetchModels's enrichment treats a non-nil result as authoritative
    // (`if let caps { features = features(fromCapabilities: caps) }`,
    // OllamaModelDiscovery.swift:239), overwriting the tags-derived features with
    // streaming-only and dropping tools/vision for a model that /api/tags reported
    // as tool- or vision-capable. An empty array must be indistinguishable from
    // "unknown" (nil) so the caller keeps its fallback, exactly like an absent key.
    // /api/show is the authoritative per-model source, so distinguish a PRESENT
    // "capabilities": [] (authoritative empty: clear tools/vision) from an ABSENT
    // key (unknown: keep the tags-derived fallback). Treating present-but-empty as
    // "unknown" would leave a non-tool model falsely advertised as tool-capable.
    func test_capabilitiesAndContext_emptyCapabilitiesArray_isAuthoritativeEmpty() {
        let present = Data(#"{"capabilities":[],"model_info":{}}"#.utf8)
        let (caps, _) = OllamaModelDiscovery.capabilitiesAndContext(fromShowResponse: present)
        XCTAssertEqual(caps, [],
                       "a present-but-empty capabilities array is authoritative: clear features rather than keeping the tags-derived fallback")

        let absent = Data(#"{"model_info":{}}"#.utf8)
        let (absentCaps, _) = OllamaModelDiscovery.capabilitiesAndContext(fromShowResponse: absent)
        XCTAssertNil(absentCaps,
                     "an absent capabilities key is unknown: keep the tags-derived fallback")
    }

    // Finding: /api/show model_info can contain more than one "*.context_length"
    // key on a multimodal model (a vision/projector block plus the text model).
    // capabilitiesAndContext iterates the unordered dictionary and breaks on the
    // FIRST match (OllamaModelDiscovery.swift:297), so it can return the smaller
    // projector window instead of the real text-model window, undersizing num_ctx
    // and silently truncating prompts on some launches but not others. It should
    // select deterministically by the model's own general.architecture. Each
    // iteration uses a distinct decoy key name so a fresh dictionary layout is
    // exercised; a first-match implementation returns the small decoy for roughly
    // half of them.
    func test_capabilitiesAndContext_multipleContextLengthKeys_prefersArchitectureMatch() {
        for i in 0..<64 {
            let decoyKey = "vision\(i).context_length"
            let body = Data("""
            {"model_info":{"general.architecture":"qwen3","qwen3.context_length":262144,"\(decoyKey)":512}}
            """.utf8)
            let (_, ctx) = OllamaModelDiscovery.capabilitiesAndContext(fromShowResponse: body)
            XCTAssertEqual(ctx, 262_144,
                           "must select the context_length for the model's own architecture (qwen3), not whichever *.context_length key (\(decoyKey)) the unordered dictionary happens to iterate first")
        }
    }
}
