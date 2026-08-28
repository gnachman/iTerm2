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

    func test_modelNames_parsesTagsResponse() {
        let body = Data("""
        {"models":[{"name":"qwen3.5:4b","size":1},{"name":"llama3.3:latest","size":2}]}
        """.utf8)
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: body),
                       ["qwen3.5:4b", "llama3.3:latest"])
    }

    func test_modelNames_emptyOrGarbage_isEmpty() {
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: Data("{}".utf8)), [])
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: Data("not json".utf8)), [])
        XCTAssertEqual(OllamaModelDiscovery.modelNames(fromTagsResponse: Data("{\"models\":[]}".utf8)), [])
    }
}
