//
//  AINetworkErrorMessageTests.swift
//  iTerm2
//
//  A network failure was reported as “HTTP request failed with The request
//  timed out.” and, for a self-hosted model, prefixed “Error from Unknown
//  Platform”.
//

import XCTest
@testable import iTerm2SharedARC

private final class TimingOutURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
    }

    override func stopLoading() {}
}

final class AINetworkErrorMessageTests: XCTestCase {
    private static let pluginCode = """
    function request(json) {
        const req = JSON.parse(json);
        return new Promise(function(resolve) {
            performHTTPRequest(req.method, req.url, req.headers, req.body, function(body, error) {
                resolve(JSON.stringify({ data: body || "", error: error }));
            });
        });
    }
    """

    override func tearDown() {
        PluginClient.protocolClassesForTesting = nil
        iTermAIClient.pluginOverrideForTesting = nil
        super.tearDown()
    }

    func testNetworkErrorIsAReadableSentence() throws {
        PluginClient.protocolClassesForTesting = [TimingOutURLProtocol.self]
        iTermAIClient.pluginOverrideForTesting = Plugin(testingCode: Self.pluginCode)
        let client = iTermAIClient()
        let done = expectation(description: "completed")
        var error: String?
        _ = client.request(webRequest: WebRequest(headers: [:],
                                                   method: "POST",
                                                   body: .string("{}"),
                                                   url: "https://plugin-test.invalid/x"),
                           stream: nil) { result in
            if case .success(let response) = result {
                error = response.error
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        let expected = "HTTP request failed: \(URLError(.timedOut).localizedDescription)"
        XCTAssertEqual(error, expected)
    }

    private func provider(url: String, name: String, api: iTermAIAPI) -> LLMProvider {
        return LLMProvider(model: AIMetadata.Model(name: name,
                                                   contextWindowTokens: 8192,
                                                   maxResponseTokens: 64,
                                                   url: url,
                                                   api: api,
                                                   features: [],
                                                   vectorStoreConfig: .disabled,
                                                   vendor: .openAI))
    }

    func testSelfHostedProviderIsNamedByHost() {
        XCTAssertEqual(provider(url: "http://qagw:8081/v1/chat/completions",
                                name: "my-model",
                                api: .chatCompletions).displayName,
                       "qagw")
    }

    func testKnownProvidersKeepTheirNames() {
        XCTAssertEqual(provider(url: "https://api.openai.com/v1/chat/completions",
                                name: "gpt-4o",
                                api: .chatCompletions).displayName,
                       "OpenAI")
        XCTAssertEqual(provider(url: "http://localhost:11434/api/chat",
                                name: "qwen3",
                                api: .llama).displayName,
                       "Ollama")
    }
}
