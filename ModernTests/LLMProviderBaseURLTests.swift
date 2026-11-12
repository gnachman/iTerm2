//
//  LLMProviderBaseURLTests.swift
//  iTerm2 ModernTests
//
//  A manual model's URL may be a base URL (“http://host:8000/v1”) instead of the
//  full endpoint. LLMProvider appends the API's standard endpoint path to a URL
//  whose path is empty, ends in a version segment, or ends in a well-known
//  gateway base (/anthropic, /openai), and sends every other URL exactly as typed.
//

import XCTest
@testable import iTerm2SharedARC

final class LLMProviderBaseURLTests: XCTestCase {

    private func requestURL(_ url: String, _ api: iTermAIAPI) -> String? {
        let model = AIMetadata.Model(name: "m",
                                     contextWindowTokens: 8192,
                                     maxResponseTokens: 1024,
                                     url: url,
                                     api: api,
                                     features: [],
                                     vectorStoreConfig: .disabled,
                                     vendor: nil)
        return LLMProvider(model: model).url(apiKey: "k", streaming: false).absoluteString
    }

    // MARK: - Base URLs get the API's endpoint

    // Issue 11509: vLLM serving the Anthropic API, configured with “/v1/”.
    func test_anthropic_versionBase() {
        XCTAssertEqual(requestURL("http://10.20.20.100:8000/v1/", .anthropic),
                       "http://10.20.20.100:8000/v1/messages")
        XCTAssertEqual(requestURL("http://10.20.20.100:8000/v1", .anthropic),
                       "http://10.20.20.100:8000/v1/messages")
    }

    func test_chatCompletions_versionBase() {
        XCTAssertEqual(requestURL("http://localhost:8000/v1", .chatCompletions),
                       "http://localhost:8000/v1/chat/completions")
        XCTAssertEqual(requestURL("https://openrouter.ai/api/v1", .chatCompletions),
                       "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(requestURL("https://api.z.ai/api/paas/v4/", .chatCompletions),
                       "https://api.z.ai/api/paas/v4/chat/completions")
        XCTAssertEqual(requestURL("https://dashscope-intl.aliyuncs.com/compatible-mode/v1", .chatCompletions),
                       "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    func test_otherOpenAIStyleAPIs_versionBase() {
        XCTAssertEqual(requestURL("http://localhost:8000/v1", .completions),
                       "http://localhost:8000/v1/completions")
        XCTAssertEqual(requestURL("http://localhost:8000/v1", .responses),
                       "http://localhost:8000/v1/responses")
        XCTAssertEqual(requestURL("http://localhost:8000/v1", .earlyO1),
                       "http://localhost:8000/v1/chat/completions")
        XCTAssertEqual(requestURL("http://localhost:8000/v1", .deepSeek),
                       "http://localhost:8000/v1/chat/completions")
    }

    // A bare host is a base too. OpenAI- and Anthropic-style servers
    // conventionally live under /v1.
    func test_bareHost() {
        XCTAssertEqual(requestURL("http://localhost:8000", .chatCompletions),
                       "http://localhost:8000/v1/chat/completions")
        XCTAssertEqual(requestURL("http://localhost:8000/", .anthropic),
                       "http://localhost:8000/v1/messages")
        XCTAssertEqual(requestURL("https://api.deepseek.com", .deepSeek),
                       "https://api.deepseek.com/v1/chat/completions")
    }

    // Ollama's native API lives at the server root.
    func test_ollama_bareHost() {
        XCTAssertEqual(requestURL("http://localhost:11434", .llama),
                       "http://localhost:11434/api/chat")
        XCTAssertEqual(requestURL("http://localhost:11434/", .llama),
                       "http://localhost:11434/api/chat")
    }

    // Anthropic-compatible gateways publish an ANTHROPIC_BASE_URL ending in
    // /anthropic, to which the Anthropic SDK appends /v1/messages.
    func test_anthropic_gatewayBase() {
        XCTAssertEqual(requestURL("https://api.z.ai/api/anthropic", .anthropic),
                       "https://api.z.ai/api/anthropic/v1/messages")
        XCTAssertEqual(requestURL("https://api.moonshot.ai/anthropic", .anthropic),
                       "https://api.moonshot.ai/anthropic/v1/messages")
        XCTAssertEqual(requestURL("https://api.deepseek.com/anthropic/", .anthropic),
                       "https://api.deepseek.com/anthropic/v1/messages")
        XCTAssertEqual(requestURL("https://api.minimax.io/anthropic", .anthropic),
                       "https://api.minimax.io/anthropic/v1/messages")
    }

    // OpenAI-compatible bases ending in /openai, like Gemini's.
    func test_openAICompatible_openaiBase() {
        XCTAssertEqual(requestURL("https://generativelanguage.googleapis.com/v1beta/openai/", .chatCompletions),
                       "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        XCTAssertEqual(requestURL("https://host/openai", .responses),
                       "https://host/openai/responses")
    }

    // Prerelease version segments are bases too.
    func test_prereleaseVersionBase() {
        XCTAssertEqual(requestURL("https://host/v1beta", .chatCompletions),
                       "https://host/v1beta/chat/completions")
        XCTAssertEqual(requestURL("https://host/v2alpha/", .anthropic),
                       "https://host/v2alpha/messages")
        XCTAssertEqual(requestURL("https://host/v1beta2", .chatCompletions),
                       "https://host/v1beta2/chat/completions")
    }

    // A URL typed without a scheme is taken as http://, as Fetch Models does,
    // so a server it lists models from is also the one chat posts to.
    func test_schemelessURL() {
        XCTAssertEqual(requestURL("localhost:8000/v1", .chatCompletions),
                       "http://localhost:8000/v1/chat/completions")
        XCTAssertEqual(requestURL("localhost:8000", .anthropic),
                       "http://localhost:8000/v1/messages")
        XCTAssertEqual(requestURL("localhost:11434", .llama),
                       "http://localhost:11434/api/chat")
        XCTAssertEqual(requestURL("10.20.20.100:8000/v1/chat/completions", .chatCompletions),
                       "http://10.20.20.100:8000/v1/chat/completions")
    }

    // Query, userinfo, and IPv6 brackets survive.
    func test_baseKeepsOtherComponents() {
        XCTAssertEqual(requestURL("https://host/v1?api-version=1", .chatCompletions),
                       "https://host/v1/chat/completions?api-version=1")
        XCTAssertEqual(requestURL("http://user:pass@host:8000/v1", .chatCompletions),
                       "http://user:pass@host:8000/v1/chat/completions")
        XCTAssertEqual(requestURL("http://[::1]:8000/v1", .anthropic),
                       "http://[::1]:8000/v1/messages")
    }

    // MARK: - Everything else is sent as typed

    func test_fullEndpointsUnchanged() {
        for (url, api) in [("https://api.openai.com/v1/chat/completions", iTermAIAPI.chatCompletions),
                           ("https://api.openai.com/v1/responses", .responses),
                           ("https://api.anthropic.com/v1/messages", .anthropic),
                           ("https://api.deepseek.com/chat/completions", .deepSeek),
                           ("http://localhost:11434/api/chat", .llama),
                           ("http://localhost:1234/v1/chat/completions", .chatCompletions)] {
            XCTAssertEqual(requestURL(url, api), url, "\(url) \(api)")
        }
    }

    // Endpoints with paths we don't recognize must not be touched.
    func test_unrecognizedPathsUnchanged() {
        XCTAssertEqual(requestURL("https://api.minimax.io/v1/text/chatcompletion_v2", .chatCompletions),
                       "https://api.minimax.io/v1/text/chatcompletion_v2")
        XCTAssertEqual(requestURL("https://x.openai.azure.com/openai/deployments/gpt/chat/completions?api-version=2024-10-21", .chatCompletions),
                       "https://x.openai.azure.com/openai/deployments/gpt/chat/completions?api-version=2024-10-21")
        XCTAssertEqual(requestURL("https://proxy.example.com/llm", .chatCompletions),
                       "https://proxy.example.com/llm")
    }

    // For the Ollama API, /v1 is its OpenAI-compatible shim, not a base for the
    // native API, so it's left alone.
    func test_ollama_versionPathUnchanged() {
        XCTAssertEqual(requestURL("http://localhost:11434/v1", .llama),
                       "http://localhost:11434/v1")
    }

    // Words that only resemble a version are not bases.
    func test_nonVersionSegmentUnchanged() {
        XCTAssertEqual(requestURL("https://host/dev", .chatCompletions), "https://host/dev")
        XCTAssertEqual(requestURL("https://host/v1gamma", .chatCompletions), "https://host/v1gamma")
        XCTAssertEqual(requestURL("https://host/vbeta", .chatCompletions), "https://host/vbeta")
    }

    // A gateway suffix is a base only for its own API family.
    func test_gatewaySuffixForOtherAPIUnchanged() {
        XCTAssertEqual(requestURL("https://host/anthropic", .chatCompletions), "https://host/anthropic")
        XCTAssertEqual(requestURL("https://host/openai", .anthropic), "https://host/openai")
        XCTAssertEqual(requestURL("http://localhost:11434/openai", .llama), "http://localhost:11434/openai")
    }

    // Azure's resource paths start with /openai but aren't bases.
    func test_azureDeploymentBaseUnchanged() {
        XCTAssertEqual(requestURL("https://x.openai.azure.com/openai/deployments/gpt", .chatCompletions),
                       "https://x.openai.azure.com/openai/deployments/gpt")
    }

    func test_gemini_unchanged() {
        XCTAssertEqual(requestURL("https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}", .gemini),
                       "https://generativelanguage.googleapis.com/v1beta/models/m:generateContent?key=k")
    }
}
