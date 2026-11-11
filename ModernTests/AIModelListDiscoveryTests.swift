//
//  AIModelListDiscoveryTests.swift
//  iTerm2 ModernTests
//
//  The pure parts of OpenAI-style model listing (GET /models): deriving the
//  listing URL from whatever endpoint the user configured, parsing the response,
//  and building an authenticated request.
//

import XCTest
@testable import iTerm2SharedARC

final class AIModelListDiscoveryTests: XCTestCase {

    private func modelsURL(_ endpoint: String) -> String? {
        return AIModelListDiscovery.modelsURL(fromEndpoint: endpoint)?.absoluteString
    }

    // MARK: - URL derivation

    func test_modelsURL_fromChatCompletionsEndpoint() {
        XCTAssertEqual(modelsURL("http://localhost:1234/v1/chat/completions"),
                       "http://localhost:1234/v1/models")
    }

    func test_modelsURL_fromAnthropicMessagesEndpoint() {
        XCTAssertEqual(modelsURL("http://10.20.20.100:8000/v1/messages"),
                       "http://10.20.20.100:8000/v1/models")
    }

    func test_modelsURL_fromLegacyCompletionsEndpoint() {
        XCTAssertEqual(modelsURL("http://localhost:8000/v1/completions"),
                       "http://localhost:8000/v1/models")
    }

    func test_modelsURL_fromResponsesEndpoint() {
        XCTAssertEqual(modelsURL("https://api.openai.com/v1/responses"),
                       "https://api.openai.com/v1/models")
    }

    // A base URL with or without a trailing slash (issue 11509: “/v1/”).
    func test_modelsURL_fromBaseURL() {
        XCTAssertEqual(modelsURL("http://10.20.20.100:8000/v1/"),
                       "http://10.20.20.100:8000/v1/models")
        XCTAssertEqual(modelsURL("http://10.20.20.100:8000/v1"),
                       "http://10.20.20.100:8000/v1/models")
    }

    // The listing URL itself, as pasted from vLLM or LM Studio docs, is used as-is
    // rather than getting a second /models.
    func test_modelsURL_fromModelsURL() {
        XCTAssertEqual(modelsURL("http://localhost:8000/v1/models"),
                       "http://localhost:8000/v1/models")
        XCTAssertEqual(modelsURL("http://localhost:8000/v1/models/"),
                       "http://localhost:8000/v1/models")
    }

    // A bare host gets the conventional /v1 prefix.
    func test_modelsURL_fromBareHost() {
        XCTAssertEqual(modelsURL("http://localhost:8000"), "http://localhost:8000/v1/models")
        XCTAssertEqual(modelsURL("http://localhost:8000/"), "http://localhost:8000/v1/models")
        XCTAssertEqual(modelsURL("localhost:8000"), "http://localhost:8000/v1/models")
    }

    // Gateways that don't put the API under /v1 keep their own prefix.
    func test_modelsURL_keepsNonV1Prefix() {
        XCTAssertEqual(modelsURL("https://openrouter.ai/api/v1/chat/completions"),
                       "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(modelsURL("https://api.z.ai/api/paas/v4/chat/completions"),
                       "https://api.z.ai/api/paas/v4/models")
        XCTAssertEqual(modelsURL("https://api.deepseek.com/chat/completions"),
                       "https://api.deepseek.com/models")
    }

    func test_modelsURL_preservesUserinfoAndIPv6() {
        XCTAssertEqual(modelsURL("http://user:pass@host:8000/v1/chat/completions"),
                       "http://user:pass@host:8000/v1/models")
        XCTAssertEqual(modelsURL("http://[::1]:8000/v1/chat/completions"),
                       "http://[::1]:8000/v1/models")
    }

    // The listing is a plain GET, so a query string (e.g. a version parameter)
    // stays with it.
    func test_modelsURL_keepsQuery() {
        XCTAssertEqual(modelsURL("https://host/v1/chat/completions?api-version=1"),
                       "https://host/v1/models?api-version=1")
    }

    // A URL with the model in its path names one model's endpoint, not a server
    // whose listing we can find.
    func test_modelsURL_modelTemplate_isNil() {
        XCTAssertNil(modelsURL("https://host/openai/deployments/{{MODEL}}/chat/completions"))
    }

    func test_modelsURL_invalidEndpoint_isNil() {
        XCTAssertNil(modelsURL(""))
        XCTAssertNil(modelsURL("not a url"))
    }

    // MARK: - Parsing

    func test_modelNames_parsesDataIDsInServerOrder() {
        let body = #"{"object":"list","data":[{"id":"b-model","object":"model"},{"id":"a-model","max_model_len":32768}]}"#
        XCTAssertEqual(AIModelListDiscovery.modelNames(fromModelsResponse: Data(body.utf8)),
                       ["b-model", "a-model"])
    }

    // One malformed entry must not hide the rest.
    func test_modelNames_skipsMalformedEntries() {
        let body = #"{"data":[{"id":"good"},{"name":"no-id"},{"id":""},{"id":"also-good"}]}"#
        XCTAssertEqual(AIModelListDiscovery.modelNames(fromModelsResponse: Data(body.utf8)),
                       ["good", "also-good"])
    }

    func test_modelNames_unexpectedShape_isEmpty() {
        XCTAssertEqual(AIModelListDiscovery.modelNames(fromModelsResponse: Data(#"{"models":[]}"#.utf8)), [])
        XCTAssertEqual(AIModelListDiscovery.modelNames(fromModelsResponse: Data("<html>".utf8)), [])
    }

    // MARK: - Request

    func test_request_chatCompletions_sendsBearerKeyAndCustomHeaders() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "https://openrouter.ai/api/v1/chat/completions",
            api: .chatCompletions,
            apiKey: "sk-test",
            headers: [["name": "X-Extra", "value": "1"]],
            timeout: 5))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Extra"), "1")
        XCTAssertEqual(request.timeoutInterval, 5)
    }

    func test_request_anthropic_sendsAnthropicHeaders() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "https://api.anthropic.com/v1/messages",
            api: .anthropic,
            apiKey: "sk-ant",
            headers: [],
            timeout: 5))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // Anthropic pages its listing (20 by default), so ask for the maximum page or
    // the menu silently stops at 20.
    func test_request_anthropic_asksForFullPage() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "https://api.anthropic.com/v1/messages",
            api: .anthropic,
            apiKey: "sk-ant",
            headers: [],
            timeout: 5))
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models?limit=1000")
    }

    func test_request_anthropic_keepsExistingQuery() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "https://gateway.example.com/v1/messages?tenant=a",
            api: .anthropic,
            apiKey: nil,
            headers: [],
            timeout: 5))
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example.com/v1/models?tenant=a&limit=1000")
    }

    // A limit the user put in the URL wins.
    func test_request_anthropic_respectsUserLimit() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "https://gateway.example.com/v1/messages?limit=50",
            api: .anthropic,
            apiKey: nil,
            headers: [],
            timeout: 5))
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example.com/v1/models?limit=50")
    }

    func test_request_openAI_addsNoLimit() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "http://localhost:8000/v1/chat/completions",
            api: .chatCompletions,
            apiKey: nil,
            headers: [],
            timeout: 5))
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:8000/v1/models")
    }

    // With no key (a local endpoint, or API key: None), only custom headers go out,
    // so a token the user put there still authenticates.
    func test_request_noKey_sendsOnlyCustomHeaders() throws {
        let request = try XCTUnwrap(AIModelListDiscovery.modelsRequest(
            fromEndpoint: "http://10.20.20.100:8000/v1/",
            api: .anthropic,
            apiKey: nil,
            headers: [["name": "Authorization", "value": "Bearer local"]],
            timeout: 5))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
    }

    // MARK: - Error display

    // Error messages must not show a user:pass@ password or a query token.
    func test_displayString_stripsCredentialsAndQuery() {
        XCTAssertEqual(AIModelListDiscovery.displayString(forURL: "http://user:secret@host:8000/v1/models?limit=1000&token=t"),
                       "http://host:8000/v1/models")
        XCTAssertEqual(AIModelListDiscovery.displayString(forURL: "http://[::1]:8000/v1/models"),
                       "http://[::1]:8000/v1/models")
    }

    // A {{MODEL}} template is shown as typed, not percent-encoded, and its
    // credentials and query are still removed.
    func test_displayString_keepsTemplateReadable() {
        XCTAssertEqual(AIModelListDiscovery.displayString(forURL: "http://user:secret@127.0.0.1:8765/v1/models/{{MODEL}}:generate?token=abc"),
                       "http://127.0.0.1:8765/v1/models/{{MODEL}}:generate")
    }

    func test_displayString_unparseableIsUnchanged() {
        XCTAssertEqual(AIModelListDiscovery.displayString(forURL: "not a url"), "not a url")
    }

    // MARK: - Which lister

    func test_supportsAPI() {
        XCTAssertTrue(AIModelListDiscovery.supports(api: .chatCompletions))
        XCTAssertTrue(AIModelListDiscovery.supports(api: .responses))
        XCTAssertTrue(AIModelListDiscovery.supports(api: .anthropic))
        XCTAssertTrue(AIModelListDiscovery.supports(api: .deepSeek))
        XCTAssertTrue(AIModelListDiscovery.supports(api: .completions))
        XCTAssertTrue(AIModelListDiscovery.supports(api: .earlyO1))
        // Ollama's native API lists models at /api/tags instead.
        XCTAssertFalse(AIModelListDiscovery.supports(api: .llama))
        // Gemini's listing has a different shape and key-in-query auth.
        XCTAssertFalse(AIModelListDiscovery.supports(api: .gemini))
        XCTAssertFalse(AIModelListDiscovery.supports(api: .appleIntelligence))
    }
}
