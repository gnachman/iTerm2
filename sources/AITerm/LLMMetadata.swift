//
//  LLMMetadata.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

@objc(iTermLLMMetadata)
class LLMMetadata: NSObject {
    private enum ManualModelKey {
        static let identifier = "id"
        static let name = "name"
        static let url = "url"
        static let api = "api"
        static let contextWindowTokens = "contextWindowTokens"
        static let maxResponseTokens = "maxResponseTokens"
        static let hostedCodeInterpreter = "hostedCodeInterpreter"
        static let hostedFileSearch = "hostedFileSearch"
        static let hostedWebSearch = "hostedWebSearch"
        static let functionCalling = "functionCalling"
        static let streaming = "streaming"
        static let vectorStore = "vectorStore"
        static let supportsTemperature = "supportsTemperature"
        static let configurableThinking = "configurableThinking"
        static let vision = "vision"
        static let customHeaders = "customHeaders"
        // A dynamic Ollama provider: the entry stores only the endpoint (+ auth
        // headers), and its models are discovered live from /api/tags rather than
        // named/capability-checkboxed by hand.
        static let dynamicModels = "dynamicModels"
        // For a dynamic entry: the single discovered model the user chose from the
        // popup. Empty/absent means expose EVERY discovered model (whole-server).
        static let dynamicSelectedModel = "dynamicSelectedModel"
    }

    @objc(openAIModelIsLegacy:)
    static func openAIModelIsLegacy(model: String) -> Bool {
        // Check if any modern model identifier appears anywhere in the model name.
        // This handles OpenRouter-style names like "openai/gpt-4o" where the
        // provider prefix comes before the model name.
        for identifier in iTermAdvancedSettingsModel.aiModernModelPrefixes().components(separatedBy: " ") {
            if model.contains(identifier) {
                return false
            }
        }
        return true
    }

    @objc(hostIsOpenAIAPIForURL:)
    static func hostIsOpenAIAPI(url: URL?) -> Bool {
        return url?.host == "api.openai.com"
    }

    @objc(hostIsOpenGoogleAPIForURL:)
    static func hostIsGoogleAIAPI(url: URL?) -> Bool {
        return url?.host == "generativelanguage.googleapis.com"
    }

    @objc(hostIsAzureAPIForURL:)
    static func hostIsAzureAIAPI(url: URL?) -> Bool {
        return (url?.host ?? "").hasSuffix(".azure.com")
    }

    @objc(hostIsDeepSeekAIAPIForURL:)
    static func hostIsDeepSeekAIAPI(url: URL?) -> Bool {
        return (url?.host ?? "").hasSuffix(".deepseek.com")
    }

    @objc(hostIsAnthropicAIAPIForURL:)
    static func hostIsAnthropicAIAPI(url: URL?) -> Bool {
        return (url?.host ?? "").hasSuffix(".anthropic.com")
    }

    static var effectiveVendor: iTermAIVendor {
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) {
            DLog("Use \(String(describing: currentVendor?.rawValue))")
            return currentVendor ?? .openAI
        }
        if let model = model(), let vendor = model.vendor {
            DLog("Use \(vendor)")
            return vendor
        }
        DLog("Fall back to openai")
        return .openAI
    }

    static var currentVendor: iTermAIVendor? {
        iTermAIVendor(rawValue: iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor))
    }

    static var alternateModels: [AIMetadata.Model] {
        guard iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) else {
            return manualModels()
        }
        guard let currentVendor else {
            return []
        }
        return alternateModels(for: currentVendor)
    }

    static func alternateModels(for vendor: iTermAIVendor) -> [AIMetadata.Model] {
        switch vendor {
        case .openAI:
            return AIMetadata.alternateOpenAIModels
        case .deepSeek:
            return AIMetadata.alternateDeepSeekModels
        case .gemini:
            return AIMetadata.alternateGeminiModels
        case .llama:
            // Ollama is a dynamic vendor: its models are discovered from the
            // local server, not a static catalog.
            return discoveredOllamaModels()
        case .anthropic:
            return AIMetadata.alternateAnthropicModels
        case .apple:
            return AIMetadata.alternateAppleModels
        @unknown default:
            return []
        }
    }

    static func recommendedModel(for vendor: iTermAIVendor) -> AIMetadata.Model? {
        switch vendor {
        case .openAI:
            return AIMetadata.recommendedOpenAIModel
        case .deepSeek:
            return AIMetadata.recommendedDeepSeekModel
        case .gemini:
            return AIMetadata.recommendedGeminiModel
        case .llama:
            // The Ollama vendor's models are discovered from the local server, so
            // there is no sane automatic choice of a default. The user picks one
            // explicitly (the "Regular model" popup, stored in
            // kPreferenceKeyAIOllamaRegularModel).
            let discovered = discoveredOllamaModels()
            let chosen = iTermPreferences.string(forKey: kPreferenceKeyAIOllamaRegularModel) ?? ""
            if !chosen.isEmpty {
                // A model was explicitly chosen: honor it when installed. If it is
                // transiently missing from discovery (server restarting, the tag being
                // re-pulled, or /api/tags briefly returned a subset), return the
                // pending placeholder rather than silently substituting a DIFFERENT
                // discovered tag - a new chat should wait for discovery, not start on a
                // model the user didn't choose.
                return discovered.first(where: { $0.name == chosen }) ?? pendingOllamaModel()
            }
            // No explicit choice yet: fall back to the lexicographically-first
            // discovered tag for determinism, or the placeholder while discovery is
            // pending so the vendor never crosses to a cloud default.
            return discovered.sorted { $0.name < $1.name }.first ?? pendingOllamaModel()
        case .anthropic:
            return AIMetadata.recommendedAnthropicModel
        case .apple:
            return AIMetadata.recommendedAppleModel
        @unknown default:
            return nil
        }
    }

    static func manualModels() -> [AIMetadata.Model] {
        let configuredModels = manualConfiguredModels()
        if !configuredModels.isEmpty {
            return configuredModels
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) {
            return []
        }
        if let model = legacyManualModel() {
            return [model]
        }
        return []
    }

    // The RESOLVED manual models for the Settings default-model popup: a dynamic
    // Ollama entry is expanded to the discovered tag(s) it exposes, with the same
    // (disambiguated) names the chat picker uses. Because each name here is exactly
    // what resolves at request time, an item selected as the default always maps
    // back to a real model, so dynamic entries no longer need special-casing.
    @objc static func settingsManualModels() -> [AIModel] {
        return manualModels().map { AIModel($0) }
    }

    // Single source of truth for resolving a pinned/persisted model NAME to a model,
    // so the UI (ChatViewController), request routing (AIConversation.complete), and
    // capability gating (ChatAgent) never disagree about where a turn actually goes.
    // A manual/configured model wins over a built-in catalog entry of the same name
    // (a user proxying a known model reaches their own url/api), and discovered
    // built-in Ollama tags are included so a chat pinned to a LOCAL model routes to
    // the local server rather than silently falling through to the global (possibly
    // cloud) default.
    static func model(named name: String?) -> AIMetadata.Model? {
        guard let name, !name.isEmpty else {
            return nil
        }
        return manualModels().first { $0.name == name }
            ?? AIMetadata.instance.models.first { $0.name == name }
            ?? discoveredOllamaModels().first { $0.name == name }
    }

    static func model() -> AIMetadata.Model? {
        if iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel),
           let vendor = iTermAIVendor(rawValue: iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor)) {
            return recommendedModel(for: vendor)
        }
        let manualModels = manualModels()
        if let name = iTermPreferences.string(forKey: kPreferenceKeyAIModel),
           let model = manualModels.first(where: { $0.name == name }) {
            return model
        }
        if let model = manualModels.first {
            return model
        }
        return nil
    }

    // The economy model to prefer for high-frequency or low-stakes AI work
    // (the screen-watch poller, command safety checks): a cheaper same-vendor
    // model where the primary chat model would be overkill and too expensive to
    // run repeatedly. A user-designated economy model (toggled in Manual AI
    // Models) wins; otherwise the configured model's catalog economy variant
    // (AIMetadata.economyModel(for:)), which preserves the configured model's
    // url/api so a custom base URL is honored and the API key is not leaked to
    // the public vendor host. nil when there is no economy alternative (or AI is
    // unconfigured/unknown), leaving the caller on the configured chat model.
    static func economyModel() -> AIMetadata.Model? {
        // When the built-in Ollama vendor is the default, its own Budget picker wins.
        // This is checked BEFORE the designated economy model because a previously
        // designated economy model (kPreferenceKeyAIEconomyModelName) belongs to a
        // manual vendor configuration and survives the switch to Ollama (manualModels
        // returns configured models regardless of useRecommendedAIModel); consulting
        // it first would silently shadow the user's Budget pick. nil means "same as
        // regular" (empty Budget pref), handled by leaving the caller on the main
        // model.
        if isOllamaVendorDefault {
            return ollamaVendorEconomyModel()
        }
        // A user-designated economy model is a full manual model with its own
        // url/api/auth, so it is used verbatim.
        if let designated = userDesignatedEconomyModel() {
            return designated
        }
        guard let configured = model() else {
            return nil
        }
        return AIMetadata.economyModel(for: configured)
    }

    // The manual model the user marked as the economy model, if any, resolved to
    // a full model. nil if unset or no longer present among the manual models.
    private static func userDesignatedEconomyModel() -> AIMetadata.Model? {
        guard let name = iTermPreferences.string(forKey: kPreferenceKeyAIEconomyModelName),
              !name.isEmpty else {
            return nil
        }
        return manualModels().first { $0.name == name }
    }

    private static func manualConfiguredModels() -> [AIMetadata.Model] {
        guard let raw = iTermPreferences.object(forKey: kPreferenceKeyAIManualModelConfigurations) as? [[String: Any]] else {
            return []
        }
        let models = raw.flatMap { configuration -> [AIMetadata.Model] in
            // A dynamic Ollama entry expands into one model per installed tag,
            // discovered from the server (with capabilities), instead of a single
            // hand-configured model.
            if bool(configuration, key: ManualModelKey.dynamicModels) {
                // A manual dynamic entry pointing at the built-in default endpoint is
                // redundant with the built-in Ollama vendor (same server, same cache).
                // Skip it, or every local tag would list twice - a clean built-in copy
                // plus a server-qualified manual copy that routes identically. Compare
                // by derived tags URL so scheme/path variants of localhost still match.
                if let url = configuration[ManualModelKey.url] as? String,
                   let mine = OllamaModelDiscovery.tagsURL(fromEndpoint: url),
                   mine == OllamaModelDiscovery.tagsURL(fromEndpoint: defaultOllamaEndpoint) {
                    return []
                }
                return dynamicOllamaModels(configuration: configuration)
            }
            return manualModel(configuration: configuration).map { [$0] } ?? []
        }
        // Also disambiguate against the built-in default-endpoint models: those are
        // a SEPARATE list (ChatViewController.builtInModels) merged with these, so a
        // manual dynamic tag that collides with a built-in local tag would otherwise
        // stay bare and, under "manual wins" resolution, shadow the local model,
        // silently routing a local-meant message to the remote server.
        return disambiguateDynamicCollisions(models, builtInNames: builtInOllamaModelNames())
    }

    // The display names of the built-in default-endpoint Ollama models. Read from
    // the discovery cache (synchronous; kicks off a refresh if stale).
    private static func builtInOllamaModelNames() -> Set<String> {
        return Set(discoveredOllamaModels().map { $0.name })
    }

    // Two dynamic Ollama servers can expose the same tag (e.g. both have
    // "llama3.3"), producing models with identical `name` but different url/headers
    // that every name-based resolver would collapse to the first. Qualify the
    // DISPLAY name of each colliding dynamic model with its server so identities
    // are unique (pins/picker resolve to the right transport); effectiveModelName
    // still carries the raw tag for the wire. A dynamic model that doesn't collide
    // keeps its clean tag name. `builtInNames` seeds the collision count with the
    // built-in default-endpoint tags (a separate list these get merged with), so a
    // manual tag clashing only with a built-in one is qualified too; the built-in
    // model keeps its clean name (the local Ollama vendor is the unqualified one).
    private static func disambiguateDynamicCollisions(_ models: [AIMetadata.Model],
                                                      builtInNames: Set<String> = []) -> [AIMetadata.Model] {
        var nameCounts: [String: Int] = [:]
        for name in builtInNames {
            nameCounts[name, default: 0] += 1
        }
        for model in models {
            nameCounts[model.name, default: 0] += 1
        }
        // Pass 1: qualify each colliding dynamic model with its server label.
        let qualified = models.map { model -> AIMetadata.Model in
            // Only dynamic models carry wireModelName; only qualify on a real clash.
            guard model.wireModelName != nil, (nameCounts[model.name] ?? 0) > 1 else {
                return model
            }
            var m = model
            m.name = "\(model.effectiveModelName) (\(OllamaModelDiscovery.serverLabel(forEndpoint: model.url)))"
            return m
        }
        // Pass 2: the server label keeps only scheme://host:port, so two entries on
        // the SAME host:port by different paths (e.g. a server's /api/chat and /v1
        // URLs) still collapse to the same qualified name, and first-match resolution
        // would route a pin to the wrong endpoint. Re-qualify any still-duplicated
        // name with the full endpoint URL, and add an occurrence index if even the
        // URL repeats (same URL, different auth headers), so every identity is unique.
        var qualifiedCounts: [String: Int] = [:]
        for model in qualified {
            qualifiedCounts[model.name, default: 0] += 1
        }
        var urlOccurrences: [String: Int] = [:]
        return qualified.map { model in
            guard model.wireModelName != nil, (qualifiedCounts[model.name] ?? 0) > 1 else {
                return model
            }
            let occurrence = urlOccurrences[model.url, default: 0]
            urlOccurrences[model.url] = occurrence + 1
            var m = model
            m.name = occurrence == 0
                ? "\(model.effectiveModelName) (\(model.url))"
                : "\(model.effectiveModelName) (\(model.url) #\(occurrence + 1))"
            return m
        }
    }

    // Expand a dynamic Ollama provider entry into the models the cache discovered
    // for its endpoint. Empty until the first /api/tags fetch lands; the cache
    // posts OllamaModelCache.didChangeNotification when it does, so the pickers
    // rebuild. Each model inherits the entry's custom auth headers.
    // The built-in "Ollama" vendor discovers its models from this local endpoint.
    // A non-local server is configured as a manual dynamic entry instead.
    @objc static let defaultOllamaEndpoint = "http://localhost:11434/api/chat"

    // The models discovered at the default Ollama endpoint. Triggers a background
    // /api/tags fetch on first read; empty until it lands or if the server is down
    // (persistence restores the last-known set synchronously at launch).
    static func discoveredOllamaModels() -> [AIMetadata.Model] {
        return OllamaModelCache.shared.models(forEndpoint: defaultOllamaEndpoint)
    }

    // The discovered tag names at the default endpoint, sorted for a stable picker
    // order. ObjC-exposed so the preferences UI can populate the Regular/Budget
    // model popups.
    @objc static func discoveredOllamaModelNames() -> [String] {
        return discoveredOllamaModels().map { $0.name }.sorted()
    }

    // Whether the built-in Ollama vendor is the current default for new chats
    // (recommended-model mode with the Llama vendor). The Regular/Budget popups
    // apply only in this case.
    @objc static var isOllamaVendorDefault: Bool {
        return iTermPreferences.bool(forKey: kPreferenceKeyUseRecommendedAIModel) &&
            iTermAIVendor(rawValue: iTermPreferences.unsignedInteger(forKey: kPreferenceKeyAIVendor)) == .llama
    }

    // The user's chosen budget/economy model for the Ollama vendor, if set and
    // still installed. nil means "same as regular" (an empty pref) or the chosen
    // tag is gone; callers treat nil as "use the main model". See ScreenWatchPoller.
    static func ollamaVendorEconomyModel() -> AIMetadata.Model? {
        guard let chosen = iTermPreferences.string(forKey: kPreferenceKeyAIOllamaEconomyModel),
              !chosen.isEmpty else {
            return nil
        }
        return discoveredOllamaModels().first { $0.name == chosen }
    }

    // A stand-in shown while discovery is pending (or if the local server is down),
    // so the built-in Ollama vendor keeps its OWN vendor instead of the resolution
    // falling through to a cloud vendor (which would silently route a message meant
    // for local Ollama to, say, OpenAI). Replaced by a real model once /api/tags
    // lands (the change notification rebuilds the pickers). Its name is used as the
    // wire model only if a turn is sent during that window, where the local server
    // rejects it clearly rather than a cloud vendor accepting it.
    @objc static let pendingOllamaModelName = "Ollama (discovering models…)"
    static func pendingOllamaModel() -> AIMetadata.Model {
        return AIMetadata.Model(name: pendingOllamaModelName,
                                contextWindowTokens: OllamaModelDiscovery.defaultContextWindow,
                                maxResponseTokens: OllamaModelDiscovery.defaultContextWindow,
                                url: defaultOllamaEndpoint, api: .llama,
                                features: [.streaming], vectorStoreConfig: .disabled,
                                vendor: .llama)
    }

    // The endpoint URLs whose discovered models are currently in use: every
    // configured dynamic entry, plus the built-in default endpoint. The default is
    // ALWAYS included because ChatViewController.builtInModels always surfaces its
    // discovered models (a chat can pin the built-in Ollama vendor even when the
    // global default is a different vendor), so a discovery update for it is always
    // relevant. Used to scope the model-cache change notification and to prune
    // persistence to live endpoints (localhost is a single fixed endpoint, so
    // always persisting it is bounded and lets it resolve synchronously at launch).
    @objc static func dynamicOllamaEndpoints() -> Set<String> {
        var result = Set<String>([defaultOllamaEndpoint])
        if let raw = iTermPreferences.object(forKey: kPreferenceKeyAIManualModelConfigurations) as? [[String: Any]] {
            for configuration in raw where bool(configuration, key: ManualModelKey.dynamicModels) {
                if let url = configuration[ManualModelKey.url] as? String, !url.isEmpty {
                    result.insert(url)
                }
            }
        }
        return result
    }

    private static func dynamicOllamaModels(configuration: [String: Any]) -> [AIMetadata.Model] {
        guard let url = configuration[ManualModelKey.url] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let headers = (configuration[ManualModelKey.customHeaders] as? [[String: String]]) ?? []
        // Pass the headers so the discovery probe authenticates the same way the
        // chat requests do (a header-auth server would otherwise 401 /api/tags).
        let discovered = OllamaModelCache.shared.models(forEndpoint: url, headers: headers).map { model -> AIMetadata.Model in
            var m = model
            m.customHeaders = headers
            // Mark as dynamic and preserve the raw tag: if this tag collides with
            // another server's, disambiguateDynamicCollisions qualifies `name` but
            // effectiveModelName (this) still goes on the wire.
            m.wireModelName = model.name
            return m
        }
        // If the entry names a single discovered model (the user picked one in the
        // editor popup), expose just that one; empty/absent means whole-server (every
        // discovered tag). Kept backward compatible: pre-existing dynamic entries
        // have no selection and still expand to all.
        let selected = (configuration[ManualModelKey.dynamicSelectedModel] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selected.isEmpty else {
            return discovered
        }
        if let match = discovered.first(where: { $0.name == selected }) {
            return [match]
        }
        // Chosen but not yet in the cache (discovery pending or the tag was removed
        // from the server): construct a stand-in so the pinned selection still
        // resolves synchronously and stays on the Ollama vendor. Include vision and
        // function-calling optimistically: gating them off (streaming-only) would
        // silently DROP an attached image or a tool definition during this transient
        // window (supportsInlineImageBlock keys on .vision), answering as if the user
        // never attached it. If the model genuinely lacks them the request surfaces a
        // visible error, which is better than silent data loss; discovery repopulates
        // the real capabilities shortly.
        var fallback = AIMetadata.Model(name: selected,
                                        contextWindowTokens: OllamaModelDiscovery.defaultContextWindow,
                                        maxResponseTokens: OllamaModelDiscovery.defaultContextWindow,
                                        url: url, api: .llama,
                                        features: [.streaming, .vision, .functionCalling],
                                        vectorStoreConfig: .disabled, vendor: .llama)
        fallback.customHeaders = headers
        fallback.wireModelName = selected
        return [fallback]
    }

    private static func legacyManualModel() -> AIMetadata.Model? {
        var features = Set<AIMetadata.Model.Feature>()
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureFunctionCalling) {
            features.insert(.functionCalling)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureHostedWebSearch) {
            features.insert(.hostedWebSearch)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureHostedFileSearch) {
            features.insert(.hostedFileSearch)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureStreamingResponses) {
            features.insert(.streaming)
        }
        if iTermPreferences.bool(forKey: kPreferenceKeyAIFeatureHostedCodeInterpreter) {
            features.insert(.hostedCodeInterpreter)
        }
        let url = iTermPreferences.string(forKey: kPreferenceKeyAITermURL)
        guard let url, !url.isEmpty else {
            return nil
        }
        let name = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-4o-mini"
        let api = iTermAIAPI(rawValue: iTermPreferences.unsignedInteger(
            forKey: kPreferenceKeyAITermAPI)) ?? .chatCompletions

        var model = AIMetadata.Model(
            name: name,
            contextWindowTokens: iTermPreferences.integer(
                forKey: kPreferenceKeyAITokenLimit),
            maxResponseTokens: iTermPreferences.integer(
                forKey: kPreferenceKeyAIResponseTokenLimit),
            url: url,
            api: api,
            features: features,
            vectorStoreConfig: .init(rawValue: iTermPreferences.integer(forKey: kPreferenceKeyAIVectorStore)) ?? .disabled,
            vendor: manualVendor(api: api, url: url, modelName: name))
        // Custom headers used to be a single global setting. Now they are
        // per-model. The legacy single manual model inherits that former global
        // pref as its headers so users who configured headers before per-model
        // support keep sending them. Issue 12975.
        if iTermPreferences.bool(forKey: kPreferenceKeyAICustomHeadersEnabled),
           let headers = iTermPreferences.object(forKey: kPreferenceKeyAICustomHeaders) as? [[String: String]] {
            model.customHeaders = headers
        }
        return model
    }

    private static func manualModel(configuration: [String: Any]) -> AIMetadata.Model? {
        guard let name = configuration[ManualModelKey.name] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = configuration[ManualModelKey.url] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let api = iTermAIAPI(rawValue: unsignedInteger(configuration,
                                                       key: ManualModelKey.api,
                                                       fallback: UInt(iTermAIAPI.chatCompletions.rawValue))) ?? .chatCompletions
        var features = Set<AIMetadata.Model.Feature>()
        if bool(configuration, key: ManualModelKey.functionCalling) {
            features.insert(.functionCalling)
        }
        if bool(configuration, key: ManualModelKey.hostedWebSearch) {
            features.insert(.hostedWebSearch)
        }
        if bool(configuration, key: ManualModelKey.hostedFileSearch) {
            features.insert(.hostedFileSearch)
        }
        if bool(configuration, key: ManualModelKey.streaming) {
            features.insert(.streaming)
        }
        if bool(configuration, key: ManualModelKey.hostedCodeInterpreter) {
            features.insert(.hostedCodeInterpreter)
        }
        if bool(configuration, key: ManualModelKey.vision) {
            features.insert(.vision)
        }
        var model = AIMetadata.Model(
            name: name,
            contextWindowTokens: integer(configuration,
                                         key: ManualModelKey.contextWindowTokens,
                                         fallback: 8_192),
            maxResponseTokens: integer(configuration,
                                       key: ManualModelKey.maxResponseTokens,
                                       fallback: 8_192),
            url: url,
            api: api,
            features: features,
            vectorStoreConfig: .init(rawValue: integer(configuration,
                                                       key: ManualModelKey.vectorStore,
                                                       fallback: AIMetadata.Model.VectorStoreConfig.disabled.rawValue)) ?? .disabled,
            vendor: manualVendor(api: api, url: url, modelName: name))
        // A manual model that shares a built-in's name is almost always that
        // built-in behind a custom endpoint (proxy/gateway). Inherit the
        // catalog fields the manual config cannot express so a preset clone
        // keeps the built-in's behavior instead of silently reverting to
        // defaults:
        //   - supportsTemperature: an explicitly stored value wins; else the
        //     twin's value (heals an Opus 4.7+ clone that predates the field, so
        //     it stops sending a temperature the API 400s on), else true.
        //   - configurableThinking: driven by its own checkbox; when the config
        //     omits it (older entries) fall back to the twin so an existing
        //     clone of a reasoning model keeps its thinking toggle.
        //   - reasoning effort / service tier options: these have no UI in the
        //     manual editor, so without this a clone of a reasoning model
        //     (gpt-5.x, o-series, DeepSeek v4) loses its effort/tier pickers.
        let catalogTwin = AIMetadata.instance.models.first { $0.name == name }
        model.supportsTemperature = bool(configuration,
                                         key: ManualModelKey.supportsTemperature,
                                         fallback: catalogTwin?.supportsTemperature ?? true)
        let thinkingFallback = catalogTwin?.features.contains(.configurableThinking) ?? false
        if bool(configuration, key: ManualModelKey.configurableThinking, fallback: thinkingFallback) {
            model.features.insert(.configurableThinking)
        }
        if let catalogTwin {
            model.reasoningEfforts = catalogTwin.reasoningEfforts
            model.serviceTiers = catalogTwin.serviceTiers
            model.thinkingOffEffort = catalogTwin.thinkingOffEffort
            model.thinkingOnEffort = catalogTwin.thinkingOnEffort
        }
        if let headers = configuration[ManualModelKey.customHeaders] as? [[String: String]] {
            model.customHeaders = headers
        }
        return model
    }

    private static func bool(_ dictionary: [String: Any], key: String) -> Bool {
        return bool(dictionary, key: key, fallback: false)
    }

    private static func bool(_ dictionary: [String: Any], key: String, fallback: Bool) -> Bool {
        if let value = dictionary[key] as? Bool {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.boolValue
        }
        return fallback
    }

    private static func integer(_ dictionary: [String: Any], key: String, fallback: Int) -> Int {
        if let value = dictionary[key] as? Int {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.intValue
        }
        return fallback
    }

    private static func unsignedInteger(_ dictionary: [String: Any], key: String, fallback: UInt) -> UInt {
        if let value = dictionary[key] as? UInt {
            return value
        }
        if let value = dictionary[key] as? NSNumber {
            return value.uintValue
        }
        return fallback
    }

    // Single source of truth for classifying a manually-configured model's
    // vendor. The Settings UI (Objective-C) calls this so its label always
    // matches how the model is actually routed at request time.
    @objc(vendorForManualModelWithAPI:url:modelName:)
    static func objcManualVendor(api: iTermAIAPI, url: String, modelName: String) -> iTermAIVendor {
        return manualVendor(api: api, url: url, modelName: modelName) ?? .openAI
    }

    // Best-effort vendor from a model name alone (used both by manual-model
    // classification and to keep a chat on its original provider when the
    // pinned model has been retired from AIMetadata).
    static func vendor(forModelName modelName: String) -> iTermAIVendor? {
        let lowercased = modelName.lowercased()
        if lowercased.contains("claude") {
            return .anthropic
        }
        if lowercased.contains("gemini") {
            return .gemini
        }
        if lowercased.contains("deepseek") {
            return .deepSeek
        }
        if lowercased.contains("llama") {
            return .llama
        }
        return nil
    }

    private static func manualVendor(api: iTermAIAPI, url: String, modelName: String) -> iTermAIVendor? {
        switch api {
        case .anthropic:
            return .anthropic
        case .deepSeek:
            return .deepSeek
        case .gemini:
            return .gemini
        case .llama:
            return .llama
        case .appleIntelligence:
            return .apple
        case .chatCompletions, .completions, .responses, .earlyO1:
            break
        @unknown default:
            break
        }

        if let byName = vendor(forModelName: modelName) {
            return byName
        }

        let parsedURL = URL(string: url)
        if hostIsAnthropicAIAPI(url: parsedURL) {
            return .anthropic
        }
        if hostIsGoogleAIAPI(url: parsedURL) {
            return .gemini
        }
        if hostIsDeepSeekAIAPI(url: parsedURL) {
            return .deepSeek
        }
        if hostIsOpenAIAPI(url: parsedURL) || hostIsAzureAIAPI(url: parsedURL) {
            return .openAI
        }
        return .openAI
    }
}
