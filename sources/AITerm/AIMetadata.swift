//
//  AIMetadata.swift
//  iTerm2
//
//  Created by George Nachman on 6/11/25.
//
//  ============================================================================
//  ADDING A NEW MODEL: checklist
//  ============================================================================
//
//  The model catalog is data-driven. Models are NOT declared here; they live in
//  OtherResources/ai-models.json and are loaded by AIModelCatalog. This struct
//  only maps that data and exposes it to the rest of the app.
//
//  1. Add an entry to `models` in OtherResources/ai-models.json. Order matters:
//     the first entry is the default model, and display order follows the file.
//     Set `vendor`, `api`, `url`, `contextWindowTokens`, `maxResponseTokens`,
//     and `features` (string-keyed; see AIModelCatalog for the legal values).
//     Optional flags default as noted:
//       - `recommended` (default false): the "latest" model for its vendor.
//         Keep exactly one per vendor.
//       - `supportsTemperature` (default true): set false if the model 400s
//         when a temperature is sent (e.g. Anthropic Opus 4.7+).
//       - `vectorStore` (default "disabled").
//       - `fixtureExempt` (default false): true for models that can't be
//         refusal-fixtured (local Llama, on-device Apple, models unreachable
//         for new keys, or models that block the refusal prompt at HTTP 400).
//         Anything in AILiveHarness.unreachableForNewKeys / refusalBlockedAtHTTP
//         MUST be marked fixtureExempt; the coverage test asserts they agree.
//       - `economyModel` (optional): the name of a cheaper same-vendor model to
//         prefer for high-frequency, low-stakes work (e.g. the orchestration
//         screen-watch poller). Must name another entry in this catalog. See
//         AIMetadata.economyModel(for:).
//  2. Bump the top-level `version` in ai-models.json so a shipped catalog can
//     supersede a stale downloaded cache.
//  3. Unless the model is `fixtureExempt`, capture a refusal fixture so the
//     live-harness regression suite covers this model's response shape:
//
//        # one model:
//        ITERM2_AI_LIVE_<VENDOR>_MODELS=<modelname> \
//            tools/run_ai_live.sh test_<vendor>_refusal
//
//        # all models for a vendor:
//        tools/run_ai_live.sh test_<vendor>_refusal
//
//     <vendor> is openai / anthropic / gemini / deepseek (lowercase).
//
//  4. `git add OtherResources/ai-models.json
//     ModernTests/Resources/SafetyRefusalFixtures/*` and commit together.
//
//  AIMetadataFixtureCoverageTest in ModernTests fails if step 3-4 is skipped,
//  so `make test` will catch a missed capture before the change ships.
//  ============================================================================

@objc(iTermAIModel)
class AIModel: NSObject {
    private(set) var model: AIMetadata.Model

    @objc(initWithModelName:url:legacy:)
    convenience init(modelName: String, url: String?, legacy: Bool) {
        let urlGuess: String
        let apiGuess: iTermAIAPI
        let featuresGuess: Set<AIMetadata.Model.Feature>
        let vendorGuess: iTermAIVendor?
        if modelName.contains("gemini") {
            urlGuess = "https://generativelanguage.googleapis.com/v1beta/models/{{MODEL}}"
            apiGuess = .gemini
            featuresGuess = [.functionCalling, .streaming]
            vendorGuess = .gemini
        } else if modelName.contains("deepseek") {
            urlGuess = "https://api.deepseek.com/chat/completions"
            apiGuess = .deepSeek
            featuresGuess = [.functionCalling, .streaming]
            vendorGuess = .deepSeek
        } else if modelName.contains("llama") {
            urlGuess = "http://localhost:11434/api/chat"
            apiGuess = .llama
            featuresGuess = [.streaming, .functionCalling]
            vendorGuess = .llama
        } else if modelName.contains("claude") {
            urlGuess = "https://api.anthropic.com/v1/messages"
            apiGuess = .anthropic
            featuresGuess = [.streaming, .functionCalling]
            vendorGuess = .anthropic
        } else if modelName.contains("gpt") || modelName.hasPrefix("o") {
            if legacy {
                urlGuess = "https://api.openai.com/v1/completions"
                apiGuess = .completions
                featuresGuess = []
            } else {
                urlGuess = "https://api.openai.com/v1/chat/completions"
                apiGuess = .chatCompletions
                featuresGuess = [.functionCalling, .hostedFileSearch, .hostedWebSearch, .streaming, .hostedCodeInterpreter]
            }
            vendorGuess = .openAI
        } else {
            apiGuess = .chatCompletions
            urlGuess = "about:empty"
            featuresGuess = []
            vendorGuess = nil
        }
        let justURL = if let url, !url.isEmpty {
            url
        } else {
            urlGuess
        }
        self.init(AIMetadata.Model(name: modelName,
                                   contextWindowTokens: 8_192,
                                   maxResponseTokens: 8_192,
                                   url: justURL,
                                   api: apiGuess,
                                   features: featuresGuess,
                                   vendor: vendorGuess))
    }

    init(_ model: AIMetadata.Model) {
        self.model = model
    }

    @objc
    static func modelFromSettings() -> AIModel? {
        guard let model = LLMMetadata.model() else {
            return nil
        }
        return AIModel(model)
    }

    @objc var name: String { model.name }
    @objc var contextWindowTokens: Int { model.contextWindowTokens }
    @objc var maxResponseTokens: Int { model.maxResponseTokens }
    @objc var url: String { model.url }
    @objc var api: iTermAIAPI { model.api }
    @objc var functionCallingFeatureEnabled: Bool { model.features.contains(.functionCalling) }
    @objc var streamingFeatureEnabled: Bool { model.features.contains(.streaming) }
    @objc var hostedFileSearchFeatureEnabled: Bool { model.features.contains(.hostedFileSearch) }
    @objc var hostedWebSearchFeatureEnabled: Bool { model.features.contains(.hostedWebSearch) }
    @objc var hostedCodeInterpreterFeatureEnabled: Bool { model.features.contains(.hostedCodeInterpreter) }

    @objc var vectorStoreConfig: AIMetadata.Model.VectorStoreConfig { model.vectorStoreConfig }
}

@objc
class AIMetadata: NSObject {
    @objc static let instance = AIMetadata()
    @objc static var defaultModel: AIModel { AIModel(instance.models[0]) }

    struct Model: Equatable {
        var name: String
        var contextWindowTokens: Int
        var maxResponseTokens: Int
        var url: String
        var api: iTermAIAPI
        enum Feature: Hashable, Equatable {
            case functionCalling // Supports tool/function calling.
            case streaming // Can stream response tokens.
            case hostedFileSearch // Can search over files provided to the API (e.g., OpenAI Assistants).
            case hostedWebSearch // Can perform web searches (e.g., via a built-in tool).
            case hostedCodeInterpreter
            case configurableThinking
        }
        var features: Set<Feature>

        @objc enum VectorStoreConfig: Int {
            case disabled = 0
            case openAI = 1
        }
        var vectorStoreConfig: VectorStoreConfig = .disabled
        var vendor: iTermAIVendor?

        // Some Anthropic generations (Opus 4.7 and later) deprecated the
        // `temperature` request parameter and return HTTP 400 if it is
        // present. Models that still accept it leave this true; models
        // that reject it set it false so the request builder omits the
        // field. Defaults to true so existing entries are unaffected.
        var supportsTemperature: Bool = true

        // True for the per-vendor "latest/recommended" model. Sourced from the
        // catalog; the recommended<Vendor>Model accessors select the flagged
        // entry for each vendor.
        var recommended: Bool = false

        // True for models that must not require a captured refusal fixture:
        // local Llama, on-device Apple, and vendor-deprecated/unreachable
        // models. See AIMetadataFixtureCoverageTest.
        var fixtureExempt: Bool = false

        // Optional catalog name of a cheaper same-vendor model to prefer for
        // high-frequency, low-stakes work where the primary model would be
        // overkill (e.g. the orchestration screen-watch poller judging whether a
        // condition has been met). nil means "no cheaper alternative; use this
        // model." See AIMetadata.economyModel(for:).
        var economyModelName: String? = nil
    }

    // The per-vendor "latest/recommended" model is the catalog entry flagged
    // recommended for that vendor, falling back to the first entry of that
    // vendor if none is flagged.
    private static func recommendedModel(for vendor: iTermAIVendor) -> Model {
        if let model = firstModel(from: instance.models, vendor: vendor) {
            return model
        }
        // The active catalog (which may be a downloaded one) has no entry for
        // this vendor. Fall back to the bundled snapshot, which always ships one
        // per shipped vendor, rather than crossing vendors. Crossing vendors
        // here would be a latent footgun: recommendedAppleModel backs the
        // on-device safety classifier (AISafetyClassifierBackend), so handing it
        // a cloud model would silently attempt a network request instead of
        // failing closed.
        if let model = firstModel(from: AIModelCatalog.bundledModels, vendor: vendor) {
            return model
        }
        // Unreachable: every shipped vendor is present in the bundled snapshot.
        it_assert(false, "No AI model for vendor \(vendor.rawValue) in catalog or bundle")
        return instance.models[0]
    }

    private static func firstModel(from models: [Model], vendor: iTermAIVendor) -> Model? {
        return AIModelCatalog.recommendedModel(for: vendor, in: models)
    }

    // The cheaper same-vendor model to prefer for high-frequency, low-stakes
    // work (e.g. the orchestration screen-watch poller), or nil if `model` has no
    // economy alternative. Resolves `model`'s economyModelName to a catalog
    // entry. If `model` carries no pointer (it may have come from settings in
    // manual mode, which doesn't populate the field), fall back to the catalog
    // entry of the same name, so a manually-selected catalog model still gets its
    // economy variant. Returns nil if the pointer names a model absent from the
    // catalog.
    //
    // The returned model PRESERVES `model`'s transport (url and api, and hence
    // which host the API key is sent to); only the model identity and its size
    // limits change. This is load-bearing for security: a manual-mode user may
    // point a catalog-named model at a custom base URL (corporate proxy /
    // gateway), and resolving to the economy entry's own public endpoint would
    // bypass that proxy and leak the configured API key to the public vendor
    // host. Same-vendor guarantees the economy model speaks the same protocol.
    static func economyModel(for model: Model) -> Model? {
        return economyModel(for: model, in: instance.models)
    }

    // Testable core: resolves within an explicit model list (tests pin to the
    // bundled catalog; production passes the active catalog via the overload
    // above).
    static func economyModel(for model: Model, in models: [Model]) -> Model? {
        let economyName = model.economyModelName
            ?? models.first(where: { $0.name == model.name })?.economyModelName
        guard let economyName,
              var economy = models.first(where: { $0.name == economyName }) else {
            return nil
        }
        economy.url = model.url
        economy.api = model.api
        return economy
    }

    static var recommendedOpenAIModel: Model {
        return recommendedModel(for: .openAI)
    }

    static var recommendedDeepSeekModel: Model {
        return recommendedModel(for: .deepSeek)
    }

    static var recommendedGeminiModel: Model {
        return recommendedModel(for: .gemini)
    }

    static var recommendedLlamaModel: Model {
        return recommendedModel(for: .llama)
    }

    static var recommendedAnthropicModel: Model {
        return recommendedModel(for: .anthropic)
    }

    static var recommendedAppleModel: Model {
        return recommendedModel(for: .apple)
    }

    static var alternateOpenAIModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .openAI
        }
    }

    static var alternateDeepSeekModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .deepSeek
        }
    }

    static var alternateGeminiModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .gemini
        }
    }

    static var alternateLlamaModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .llama
        }
    }

    static var alternateAnthropicModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .anthropic
        }
    }

    static var alternateAppleModels: [Model] {
        return AIMetadata.instance.models.filter { candidate in
            candidate.vendor == .apple
        }
    }

    // The model catalog is data-driven: entries come from ai-models.json (a
    // signed resource that AIModelCatalogUpdater can refresh at runtime). The
    // JSON preserves display order and the first entry is the default model.
    //
    // Llama supports function calling only without streaming. We don't expose a
    // "streamingFunctionCalling" feature, so tools are silently omitted while
    // streaming. To find the places that implement this, search for
    // #llama-streaming-functions.
    let models: [Model] = AIModelCatalog.instance.models

    @objc(enumerateModels:) func enumerateModels(_ closure: (String, Int, String?) -> ()) {
        for model in models {
            // Apple Intelligence is an on-device classifier-only backend, not a
            // general chat model. Keep it in `models` so the safety classifier
            // can resolve it by name, but never surface it in the model picker.
            if model.vendor == .apple {
                continue
            }
            closure(model.name, model.contextWindowTokens, model.url)
        }
    }

    @objc(contextWindowTokensForModelName:) func objc_contextWindowTokens(modelName: String) -> NSNumber? {
        if let model = models.first(where: { $0.name == modelName}) {
            return NSNumber(value: model.contextWindowTokens)
        }
        return nil
    }

    @objc(responseTokenLimitForModelName:)
    func objc_responseTokenLimit(modelName: String) -> NSNumber? {
        if let model = models.first(where: { $0.name == modelName}) {
            return NSNumber(value: model.maxResponseTokens)
        }
        return nil
    }

    @objc(apiForModel:fallback:)
    func api(for model: String, fallback: iTermAIAPI) -> iTermAIAPI {
        if let modelIndex = models.firstIndex(where: { $0.name == model }) {
            return models[modelIndex].api
        }
        if model.contains("gpt") {
            return .responses
        }
        if model.contains("gemini") {
            return .gemini
        }
        if model.contains("deepseek") {
            return .completions
        }
        if model.contains("llama") {
            return .completions
        }
        if model.contains("claude") {
            return .anthropic
        }
        return fallback
    }

    @objc(urlForModelName:)
    func objc_url(modelName: String) -> String? {
        return models.first(where: { $0.name == modelName })?.url
    }

    func maxResponseTokens(modelName: String) -> Int? {
        guard let model = models.first(where: { $0.name == modelName}) else {
            return nil
        }
        return model.maxResponseTokens
    }

    func tokens(in string: String) -> Int {
        return string.utf8.count / 2
    }


    @objc(modelHasDefaults:)
    func modelHasDefaults(_ model: String) -> Bool {
        return models.contains {
            $0.name == model
        }
    }
    @objc(modelSupportsHostedCodeInterpreter:)
    func modelSupportsHostedCodeInterpreter(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.hostedCodeInterpreter)
    }

    @objc(modelSupportsHostedFileSearch:)
    func modelSupportsHostedFileSearch(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.hostedFileSearch)
    }

    @objc(vectorStoreForModel:)
    func vectorStore(for model: String) -> Int {
        guard let obj = models.first(where: { $0.name == model }) else {
            return Model.VectorStoreConfig.disabled.rawValue
        }
        return obj.vectorStoreConfig.rawValue
    }

    @objc(modelSupportsHostedWebSearch:)
    func modelSupportsHostedWebSearch(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.hostedWebSearch)
    }

    @objc(modelSupportsFunctionCalling:)
    func modelSupportsFunctionCalling(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.functionCalling)
    }

    @objc(modelSupportsStreamingResponses:)
    func modelSupportsStreamingResponses(_ model: String) -> Bool {
        guard let obj = models.first(where: { $0.name == model }) else {
            return false
        }
        return obj.features.contains(.streaming)
    }
}
