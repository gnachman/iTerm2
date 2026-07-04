//
//  AIModelCatalog.swift
//  iTerm2
//
//  Loads the AI model catalog from data rather than hardcoded constants.
//
//  The catalog ships as a signed JSON resource (OtherResources/ai-models.json)
//  and can be refreshed at runtime by AIModelCatalogUpdater, which downloads a
//  newer signed copy and writes it to Application Support. This lets new models
//  (and the per-vendor "recommended/latest" pointer) reach users without an app
//  update. A genuinely new wire protocol still requires a build; the updater's
//  manifest gate (an integer range against appCatalogCompatibilityVersion) is
//  how a future catalog can require a newer app before referencing a new
//  iTermAIAPI case.
//
//  Schema: a top-level { "version": Int, "models": [entry...] }. See
//  ai-models.json for the canonical example. Enum-valued fields (api, vendor,
//  features, vectorStore) are string keyed and mapped below; an entry whose
//  api or vendor the running app does not understand is skipped rather than
//  failing the whole decode.

import Foundation

struct AIModelCatalog {
    static let instance = AIModelCatalog()

    // Display order is preserved from the JSON. The first entry is the default
    // model (see AIMetadata.defaultModel).
    let models: [AIMetadata.Model]

    // The catalog's own version number, used by AIModelCatalogUpdater to decide
    // whether a downloaded catalog is newer than what's already loaded.
    let version: Int

    // The AI-catalog capability revision this build understands: a monotonic
    // integer, independent of the catalog's data `version` and of the app's
    // human-facing version string. Bump it ONLY for a change an older app could
    // not consume gracefully - typically a new iTermAIAPI serializer, a new
    // Model.Feature, or a new VectorStoreConfig value that alters how a model is
    // represented or selected. A purely additive, optional field that older apps
    // simply ignore when decoding (like economyModel) does NOT warrant a bump: a
    // server catalog that uses it should keep minimum_ai_version low so older
    // apps still adopt the catalog and just skip the optimization.
    //
    // The updater gates each candidate catalog in the manifest on an integer
    // [minimum_ai_version, maximum_ai_version] range against this value, so a
    // future server catalog that references a serializer this build lacks can
    // require a newer app WITHOUT parsing version strings (which don't order
    // sanely across nightly/beta/adhoc builds). Fail-safe decoding already drops
    // individual unrepresentable entries; this just avoids adopting a catalog
    // that a build couldn't usefully consume.
    static let appCatalogCompatibilityVersion = 1

    private static let resourceName = "ai-models"
    private static let resourceExtension = "json"

    // Cached, signature-verified catalog written by AIModelCatalogUpdater. The
    // updater verifies the RSA signature before writing, so a file present here
    // is trusted.
    static var cachedCatalogURL: URL? {
        guard let appSupport = FileManager.default.applicationSupportDirectory() else {
            return nil
        }
        return URL(fileURLWithPath: appSupport).appendingPathComponent("ai-models.json")
    }

    static var bundledCatalogURL: URL? {
        return Bundle(for: AIMetadata.self).url(forResource: resourceName,
                                                withExtension: resourceExtension)
    }

    // The bundled snapshot's models, independent of any downloaded cache. Used
    // as a vendor-scoped fallback (see AIMetadata.recommendedModel(for:)) so a
    // downloaded catalog that happens to drop a vendor still resolves to a
    // vendor-appropriate model instead of silently crossing vendors.
    static let bundledModels: [AIMetadata.Model] = load(at: bundledCatalogURL)?.models ?? []

    init() {
        // Load both sources and use whichever has the higher version. This way a
        // newer bundled snapshot (shipped by an app upgrade) wins over a stale
        // downloaded cache, and a newer downloaded cache wins over the bundle.
        let bundled = Self.load(at: Self.bundledCatalogURL)
        let cached = Self.load(at: Self.cachedCatalogURL)
        let chosen: Loaded?
        switch (bundled, cached) {
        case let (b?, c?): chosen = (c.version > b.version) ? c : b
        case let (b?, nil): chosen = b
        case let (nil, c?): chosen = c
        case (nil, nil): chosen = nil
        }
        if let chosen {
            DLog("Loaded \(chosen.models.count) AI models from catalog version \(chosen.version)")
            self.version = chosen.version
            self.models = chosen.models
        } else {
            it_assert(false, "Failed to load AI model catalog from cache or bundle")
            self.version = 0
            self.models = []
        }
    }

    private init(loaded: Loaded) {
        self.version = loaded.version
        self.models = loaded.models
    }

    // Bundle-only catalog: ignores any downloaded cache. Tests pin to this so a
    // machine that has fetched a newer server catalog at runtime doesn't fail
    // assertions about the shipped ai-models.json. Nil only if the bundled
    // resource is missing or unusable.
    static var bundledForTesting: AIModelCatalog? {
        guard let loaded = load(at: bundledCatalogURL) else {
            return nil
        }
        return AIModelCatalog(loaded: loaded)
    }

    // The per-vendor "latest/recommended" model within a set of catalog models:
    // the entry flagged recommended, else the first entry for that vendor.
    // Single source of truth shared by AIMetadata.recommendedModel(for:).
    static func recommendedModel(for vendor: iTermAIVendor,
                                 in models: [AIMetadata.Model]) -> AIMetadata.Model? {
        let vendorModels = models.filter { $0.vendor == vendor }
        return vendorModels.first(where: { $0.recommended }) ?? vendorModels.first
    }

    private struct Loaded {
        let version: Int
        let models: [AIMetadata.Model]
    }

    private static func load(at url: URL?) -> Loaded? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let catalog = try? JSONDecoder().decode(CatalogDTO.self, from: data) else {
            DLog("Failed to decode AI model catalog at \(url.path)")
            return nil
        }
        // Fail-safe: skip entries the running app can't represent, keep the rest.
        let models = catalog.models.compactMap { $0.toModel() }
        guard !models.isEmpty else {
            return nil
        }
        return Loaded(version: catalog.version, models: models)
    }

    // Validates candidate catalog data (post-signature-verification) before it
    // replaces the cache: it must decode, yield at least one usable model, and
    // satisfy the catalog invariants. Returns the catalog version on success, or
    // nil.
    //
    // The invariants match what AIModelCatalogTest enforces on the bundled
    // catalog, now applied at runtime to a downloaded (signed) one. This is
    // defense in depth against our own future data mistakes, not an attacker: a
    // cross-vendor or dangling economyModel pointer would make the screen-watch
    // poller build a wrong-host provider under the configured key (see
    // AIMetadata.economyModel(for:)), and two recommended entries for one vendor
    // would resolve nondeterministically. Checks run on the raw declared entries
    // (by name/vendor string) so the data contract holds regardless of which
    // entries this particular build can represent.
    static func validate(data: Data) -> Int? {
        guard let catalog = try? JSONDecoder().decode(CatalogDTO.self, from: data) else {
            return nil
        }
        guard catalog.models.contains(where: { $0.toModel() != nil }) else {
            return nil
        }
        let vendorByName = Dictionary(catalog.models.map { ($0.name, $0.vendor) },
                                      uniquingKeysWith: { first, _ in first })
        for dto in catalog.models {
            guard let economy = dto.economyModel else {
                continue
            }
            guard economy != dto.name,
                  let economyVendor = vendorByName[economy],
                  economyVendor == dto.vendor else {
                DLog("Rejecting AI catalog: invalid economyModel \(economy) on \(dto.name)")
                return nil
            }
        }
        var recommendedVendors = Set<String>()
        for dto in catalog.models where dto.recommended == true {
            guard recommendedVendors.insert(dto.vendor).inserted else {
                DLog("Rejecting AI catalog: multiple recommended models for vendor \(dto.vendor)")
                return nil
            }
        }
        return catalog.version
    }
}

private struct CatalogDTO: Decodable {
    var version: Int
    var models: [ModelDTO]
}

private struct ModelDTO: Decodable {
    var name: String
    var vendor: String
    var api: String
    var url: String
    var contextWindowTokens: Int
    var maxResponseTokens: Int
    var features: [String]
    var vectorStore: String?
    var supportsTemperature: Bool?
    var recommended: Bool?
    var fixtureExempt: Bool?
    var economyModel: String?

    func toModel() -> AIMetadata.Model? {
        guard let apiValue = ModelDTO.apiCase(from: api) else {
            DLog("Unknown api \(api) for model \(name); skipping")
            return nil
        }
        guard let vendorValue = ModelDTO.vendorCase(from: vendor) else {
            DLog("Unknown vendor \(vendor) for model \(name); skipping")
            return nil
        }
        let featureSet = Set(features.compactMap { ModelDTO.featureCase(from: $0) })
        return AIMetadata.Model(name: name,
                                contextWindowTokens: contextWindowTokens,
                                maxResponseTokens: maxResponseTokens,
                                url: url,
                                api: apiValue,
                                features: featureSet,
                                vectorStoreConfig: ModelDTO.vectorStoreCase(from: vectorStore),
                                vendor: vendorValue,
                                supportsTemperature: supportsTemperature ?? true,
                                recommended: recommended ?? false,
                                fixtureExempt: fixtureExempt ?? false,
                                economyModelName: economyModel)
    }

    private static func apiCase(from string: String) -> iTermAIAPI? {
        switch string {
        case "completions": return .completions
        case "chatCompletions": return .chatCompletions
        case "responses": return .responses
        case "gemini": return .gemini
        case "earlyO1": return .earlyO1
        case "llama": return .llama
        case "deepSeek": return .deepSeek
        case "anthropic": return .anthropic
        case "appleIntelligence": return .appleIntelligence
        default: return nil
        }
    }

    private static func vendorCase(from string: String) -> iTermAIVendor? {
        switch string {
        case "deepSeek": return .deepSeek
        case "gemini": return .gemini
        case "openAI": return .openAI
        case "llama": return .llama
        case "anthropic": return .anthropic
        case "apple": return .apple
        default: return nil
        }
    }

    private static func featureCase(from string: String) -> AIMetadata.Model.Feature? {
        switch string {
        case "functionCalling": return .functionCalling
        case "streaming": return .streaming
        case "hostedFileSearch": return .hostedFileSearch
        case "hostedWebSearch": return .hostedWebSearch
        case "hostedCodeInterpreter": return .hostedCodeInterpreter
        case "configurableThinking": return .configurableThinking
        default:
            DLog("Unknown feature \(string); ignoring")
            return nil
        }
    }

    private static func vectorStoreCase(from string: String?) -> AIMetadata.Model.VectorStoreConfig {
        switch string {
        case "openAI": return .openAI
        case "disabled", nil: return .disabled
        default:
            DLog("Unknown vectorStore \(string ?? "nil"); defaulting to disabled")
            return .disabled
        }
    }
}
