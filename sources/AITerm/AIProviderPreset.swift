//
//  AIProviderPreset.swift
//  iTerm2
//
//  Created by George Nachman on 8/2/26.
//

// A ready-made starting point for a manually-configured AI model that points at
// a third-party, OpenAI-compatible gateway (OpenRouter, Ollama, z.ai, Qwen,
// MiniMax, ...). Unlike the per-model presets sourced from the catalog
// (AIMetadata.presetModels), a provider preset does NOT name a specific model:
// it fills in the endpoint URL, the API dialect, and the capability checkboxes,
// then leaves the model-name field for the user to type (guided by a
// placeholder). These hosts are intentionally kept out of ai-models.json because
// they are not first-party models: they carry no refusal fixture and never
// appear in the recommended-model pickers.
@objc(iTermAIProviderPreset)
class AIProviderPreset: NSObject {
    // Human-facing name shown in the editor's preset popup (e.g. "OpenRouter").
    @objc let name: String
    @objc let url: String
    @objc let api: iTermAIAPI
    @objc let contextWindowTokens: Int
    @objc let maxResponseTokens: Int
    @objc let functionCalling: Bool
    @objc let streaming: Bool
    // Suggested model name shown as placeholder text in the Model field so the
    // user knows the shape of a valid identifier for this host.
    @objc let placeholderModelName: String

    init(name: String,
         url: String,
         api: iTermAIAPI = .chatCompletions,
         contextWindowTokens: Int = 128_000,
         maxResponseTokens: Int = 16_384,
         functionCalling: Bool = true,
         streaming: Bool = true,
         placeholderModelName: String) {
        self.name = name
        self.url = url
        self.api = api
        self.contextWindowTokens = contextWindowTokens
        self.maxResponseTokens = maxResponseTokens
        self.functionCalling = functionCalling
        self.streaming = streaming
        self.placeholderModelName = placeholderModelName
    }
}

extension AIMetadata {
    // The OpenAI-compatible third-party gateways we offer as one-click starting
    // points. All of them speak the Chat Completions dialect, so the only thing
    // that varies per host is the endpoint URL and the example model name. The
    // user still supplies the model name and, at request time, the API key for
    // the resolved vendor (these all classify as .openAI).
    @objc(providerPresets) var providerPresets: [AIProviderPreset] {
        return [
            AIProviderPreset(
                name: "Ollama (OpenAI-compatible)",
                url: "http://localhost:11434/v1/chat/completions",
                placeholderModelName: "llama3.3"),
            AIProviderPreset(
                name: "OpenRouter",
                url: "https://openrouter.ai/api/v1/chat/completions",
                placeholderModelName: "openai/gpt-4o"),
            AIProviderPreset(
                name: "z.ai (GLM)",
                url: "https://api.z.ai/api/paas/v4/chat/completions",
                placeholderModelName: "glm-4.6"),
            AIProviderPreset(
                name: "Qwen (DashScope)",
                url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
                placeholderModelName: "qwen-plus"),
            AIProviderPreset(
                name: "MiniMax",
                url: "https://api.minimax.io/v1/text/chatcompletion_v2",
                placeholderModelName: "MiniMax-Text-01")
        ]
    }
}
