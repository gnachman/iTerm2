//
//  LLMProvider.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

struct LLMProvider {
    var model: AIMetadata.Model

    // The model's endpoint. Everything here that reads model.url goes through
    // this, so the request URL and the vendor host checks below can never be
    // parsed two different ways.
    private var parsedModelURL: URL? {
        return Self.parseModelURL(model.url)
    }

    // Parse a configured model URL. A scheme-less “host:port[/path]” parses with
    // the host as its scheme and no host (or not at all, for an IP address), so
    // text with no “://” and no host is taken as http://. Shared with model
    // discovery (OllamaModelDiscovery.discoveryURL), so the server Fetch Models
    // lists is the one chat posts to.
    static func parseModelURL(_ string: String) -> URL? {
        let url = URL(string: string)
        if url?.host == nil, !string.contains("://") {
            return URL(string: "http://" + string)
        }
        return url
    }

    func url(apiKey: String, streaming: Bool) -> URL {
        switch model.api {
        case .gemini:
            let url = parsedModelURL ?? URL(string: "about:empty")!
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return URL(string: "about:empty")!
            }
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            components.path = String(components.path.removing(suffix: ":streamGenerateContent"))
            components.path = String(components.path.removing(suffix: ":generateContent"))
            components.path = components.path.replacingOccurrences(of: "{{MODEL}}", with: model.name)
            if streaming {
                components.path += ":streamGenerateContent"
                components.queryItems?.append(URLQueryItem(name: "alt", value: "sse"))
            } else {
                components.path += ":generateContent"
            }
            return components.url ?? URL(string: "about:empty")!
        default:
            guard let url = parsedModelURL else {
                return URL(string: "about:empty")!
            }
            return Self.endpoint(forBaseURL: url, rawURL: model.url, api: model.api) ?? url
        }
    }

    // The standard endpoint path each API posts to, appended to a base URL.
    private static func endpointPath(for api: iTermAIAPI) -> String? {
        switch api {
        case .chatCompletions, .earlyO1, .deepSeek:
            return "/chat/completions"
        case .completions:
            return "/completions"
        case .responses:
            return "/responses"
        case .anthropic:
            return "/messages"
        case .llama:
            return "/api/chat"
        case .gemini, .appleIntelligence:
            return nil
        @unknown default:
            return nil
        }
    }

    // The last path segment of the base URL that gateways publish for each API
    // family, and what the vendor's SDK appends to it before the endpoint path.
    // Anthropic-compatible gateways document an ANTHROPIC_BASE_URL ending in
    // /anthropic (https://api.z.ai/api/anthropic), to which the Anthropic SDK
    // appends /v1/messages. OpenAI-compatible ones may end in /openai (Gemini's
    // https://generativelanguage.googleapis.com/v1beta/openai/), which already
    // includes the version.
    private static func gatewayBase(for api: iTermAIAPI) -> (segment: String, prefix: String)? {
        switch api {
        case .chatCompletions, .completions, .responses, .earlyO1, .deepSeek:
            return ("openai", "")
        case .anthropic:
            return ("anthropic", "/v1")
        case .llama, .gemini, .appleIntelligence:
            return nil
        @unknown default:
            return nil
        }
    }

    // “v1”, “v4”, and prerelease versions like “v1beta”, “v2alpha”, “v1beta2”.
    private static func isVersionSegment(_ segment: Substring) -> Bool {
        return segment.range(of: #"^v[0-9]+((alpha|beta)[0-9]*)?$"#, options: .regularExpression) != nil
    }

    // A manual model's URL may be a base URL instead of the full endpoint. When
    // its path is empty, ends in a version segment (“/v1”, “/api/paas/v4/”,
    // “/v1beta”), or ends in the API family's gateway base (“/anthropic”,
    // “/openai”), return the path with the API's endpoint path appended; a bare
    // host gets the conventional /v1 first. Returns nil for every other path,
    // which is sent exactly as typed, so an endpoint with a path we don't
    // recognize (MiniMax's /v1/text/chatcompletion_v2, an Azure deployment, a
    // proxy) is never touched. Ollama's native API lives at the server root and
    // its /v1 is the OpenAI-compatible shim, so only a bare Ollama host is
    // completed. The one definition of a base URL: Fetch Models
    // (AIModelListDiscovery) uses it too, so it lists beside the endpoint chat
    // posts to.
    static func endpointPath(forBasePath rawPath: String, api: iTermAIAPI) -> String? {
        guard let endpointPath = endpointPath(for: api) else {
            return nil
        }
        var path = rawPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.isEmpty {
            return (api == .llama ? "" : "/v1") + endpointPath
        }
        guard api != .llama, let last = path.split(separator: "/").last else {
            return nil
        }
        if isVersionSegment(last) {
            return path + endpointPath
        }
        if let gateway = gatewayBase(for: api), last == gateway.segment {
            return path + gateway.prefix + endpointPath
        }
        return nil
    }

    // The request URL for a base URL (see endpointPath(forBasePath:api:)), or nil
    // to send the URL as typed. A {{MODEL}} template is always sent as typed.
    static func endpoint(forBaseURL url: URL, rawURL: String, api: iTermAIAPI) -> URL? {
        guard !rawURL.contains("{{MODEL}}"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = endpointPath(forBasePath: components.percentEncodedPath, api: api) else {
            return nil
        }
        components.percentEncodedPath = path
        return components.url
    }

    func createVectorStoreURL(apiKey: String) -> URL? {
        switch model.vectorStoreConfig {
        case .disabled:
            return nil
        case .openAI:
            return URL(string: "https://api.openai.com/v1/vector_stores")
        }
    }

    func uploadURL() -> URL? {
        switch model.vectorStoreConfig {
        case .disabled:
            return nil
        case .openAI:
            return URL(string: "https://api.openai.com/v1/files")
        }
    }

    func addFileToVectorStoreURL(apiKey: String, vectorStoreID: String) -> URL? {
        switch model.vectorStoreConfig {
        case .disabled:
            return nil
        case .openAI:
            return URL(string: "https://api.openai.com/v1/vector_stores/\(vectorStoreID)/file_batches")
        }
    }

    var urlIsValid: Bool {
        return url(apiKey: "placeholder", streaming: false).scheme != "about"
    }

    var displayName: String {
        let placeholderURL = url(apiKey: "placeholder", streaming: false)
        if LLMMetadata.hostIsOpenAIAPI(url: placeholderURL) {
            return "OpenAI"
        }
        if LLMMetadata.hostIsGoogleAIAPI(url: placeholderURL) {
            return "Google"
        }
        if LLMMetadata.hostIsAzureAIAPI(url: placeholderURL) {
            return "Azure"
        }
        if LLMMetadata.hostIsDeepSeekAIAPI(url: placeholderURL) {
            return "Deep Seek"
        }
        if LLMMetadata.hostIsAnthropicAIAPI(url: placeholderURL) {
            return "Anthropic"
        }
        if LLMMetadata.hostIsXAIAIAPI(url: placeholderURL) {
            return "Grok"
        }
        // The .llama API type is Ollama's native /api/chat dialect regardless of
        // which model (llama, qwen, ...) is served, so name it for the runner, not
        // the model family. This is what error prefixes ("Error from Ollama") use.
        if model.api == .llama {
            return "Ollama"
        }
        if model.name.contains("llama") {
            return "Llama"
        }
        // A self-hosted server or gateway: its host name says more than
        // “Unknown Platform” (for example, in “Error from <host>: …”).
        if let host = parsedModelURL?.host, !host.isEmpty {
            return host
        }

        return String(localized: "LLMProvider.UnknownPlatform", defaultValue: "Unknown Platform", comment: "Display name for an unrecognized AI provider")
    }

    var dynamicModelsSupported: Bool {
        if LLMMetadata.hostIsAzureAIAPI(url: url(apiKey: "placeholder", streaming: false)) {
            return false
        }
        switch model.api {
        case .gemini:
            return false
        default:
            return true
        }
    }

    var functionsSupported: Bool {
        // Ollama's native /api/chat (api == .llama) supports tool calls WHILE
        // streaming as of Ollama's May 2025 release, so streaming no longer
        // disqualifies function calling; gate purely on the advertised capability.
        return model.features.contains(.functionCalling)
    }

    var supportsStreaming: Bool {
        return model.features.contains(.streaming)
    }

    var supportsPreviousResponseID: Bool {
        // Zero Data Retention orgs cannot retain responses server-side, so
        // previous_response_id is rejected (unsupported_parameter) and delta
        // mode is impossible. Force full stateless replay instead. Global
        // because ZDR is an org-wide property; see kPreferenceKeyAIZeroDataRetention.
        if iTermPreferences.bool(forKey: kPreferenceKeyAIZeroDataRetention) {
            return false
        }
        return model.api == .responses
    }

    func shouldSendAttachmentInline(mimeType: String) -> Bool {
        return MIMETypeIsTextual(mimeType)
    }

    func shouldUploadFile(mimeType: String) -> Bool {
        if MIMETypeIsTextual(mimeType) {
            return false
        }
        // Images/audio/video are consumed inline (vision / audio content
        // blocks), never ingested into a vector store. A vector store is
        // text retrieval and can't "see" an image, so uploading one there is
        // useless. Excluding them here keeps an image attachment on the
        // inline input_image path even when an OpenAI vector store is
        // configured.
        if mimeType.hasPrefix("image/") || mimeType.hasPrefix("audio/") || mimeType.hasPrefix("video/") {
            return false
        }
        if LLMMetadata.hostIsOpenAIAPI(url: parsedModelURL) &&
            (model.api == .responses) &&
            model.vectorStoreConfig != .disabled {
            return true
        }
        return false
    }

    func fileTypeIsSupported(extension ext: String) -> Bool {
        // Unknown extensions fall back to application/octet-stream, not
        // text/plain. Text-only vendors' accepts(mimeType:) allowlist
        // then rejects them at the gate instead of letting an unknown
        // binary slip through and get base64-wrapped as lossy text. Users
        // with a genuinely text-like unknown extension (.yaml, .toml,
        // ...) will see "unsupported file" and can either rename the
        // file or paste its contents inline; that's a strictly safer
        // default than silently shipping bytes that may render as
        // garbage in the LLM's input.
        let mime = extensionToMime[ext] ?? "application/octet-stream"
        return accepts(mimeType: mime)
    }

    func accepts(mimeType: String) -> Bool {
        // Capability is gated at the MODALITY + serializer level, not per
        // image/audio sub-format and not per model. The principle, chosen
        // deliberately: err toward allowing an attachment whenever this
        // vendor's request format can carry it as a typed content block, and
        // let the backend reject an unsupported sub-format or a non-capable
        // model with a clean HTTP error that surfaces in the chat. We do NOT
        // try to predict which specific model supports vision/audio, so a
        // newer model than we know about (or a custom one pointed at a known
        // host) works automatically. The only things still refused here are
        // opaque binaries with no typed representation; those fall back to
        // path insertion / the vector-store upload path rather than being
        // base64-mangled into a text block.

        // Textual content (including image/svg+xml, which is XML text) is
        // always acceptable: it inlines as a text block on any vendor.
        if MIMETypeIsTextual(mimeType) {
            return true
        }
        if mimeType == "application/pdf" {
            return supportsPDFAttachments
        }
        if mimeType.hasPrefix("image/") {
            return supportsInlineImageBlock
        }
        if mimeType.hasPrefix("audio/") {
            return acceptsInlineAudio(mimeType: mimeType)
        }
        if mimeType.hasPrefix("video/") {
            return supportsInlineVideoBlock
        }
        // Vector-store-backed providers can ingest arbitrary other binaries
        // by uploading them and referencing by file ID.
        return shouldUploadFile(mimeType: mimeType)
    }

    var supportsPDFAttachments: Bool {
        let url = parsedModelURL
        if LLMMetadata.hostIsOpenAIAPI(url: url) {
            return true
        }
        if LLMMetadata.hostIsAnthropicAIAPI(url: url) {
            return true
        }
        if LLMMetadata.hostIsGoogleAIAPI(url: url) {
            return true
        }
        // api.x.ai chat completions rejects an inline file part with
        // HTTP 400 and points at /v1/responses. Images stay on
        // supportsInlineImageBlock.
        return false
    }

    // Whether this vendor's request serializer can carry an inline image
    // content block for any image/* MIME. We send the bytes with their real
    // media type and let the vendor reject sub-formats it doesn't accept
    // (e.g. Anthropic 400s on image/heic). This is
    // serializer capability, not model capability: every current chat model
    // on these hosts is multimodal, and an unknown future one inherits
    // support here for free. Image-shaped MIMEs that are really text
    // (image/svg+xml) are handled by the textual branch of accepts() first.
    var supportsInlineImageBlock: Bool {
        // Native Ollama can carry images (message.images[]), but capability is
        // model-specific for a local runner and can't be inferred from the host,
        // so gate it on the model's declared Vision feature (the manual editor
        // checkbox). The cloud hosts stay serializer-capability gated.
        if model.api == .llama {
            return model.features.contains(.vision)
        }
        let url = parsedModelURL
        return LLMMetadata.hostIsAnthropicAIAPI(url: url)
            || LLMMetadata.hostIsGoogleAIAPI(url: url)
            || LLMMetadata.hostIsOpenAIAPI(url: url)
            || LLMMetadata.hostIsXAIAIAPI(url: url)
    }

    // Gemini accepts video via inlineData; no other wired vendor takes video.
    var supportsInlineVideoBlock: Bool {
        LLMMetadata.hostIsGoogleAIAPI(url: parsedModelURL)
    }

    // Audio is the one modality we still gate by sub-format. Unlike images
    // (where we can always emit a well-formed image block and let the vendor
    // reject the sub-format), OpenAI's input_audio block has a closed
    // {wav, mp3} format enum, so the serializer can only represent those two
    // and there is no well-formed request to send for, say, audio/ogg.
    // Gemini's inlineData passes the MIME through, so it takes any audio/*.
    // OpenAI audio is also chat-completions-only: the Responses API has no
    // audio input, so it is gated on the protocol too.
    func acceptsInlineAudio(mimeType: String) -> Bool {
        let url = parsedModelURL
        if LLMMetadata.hostIsGoogleAIAPI(url: url) {
            return true
        }
        if LLMMetadata.hostIsOpenAIAPI(url: url) && model.api == .chatCompletions {
            return Self.openAIInputAudioMimeTypes.contains(mimeType)
        }
        return false
    }

    // MIME types representable by OpenAI's chat-completions input_audio block,
    // whose format field is a closed enum of "wav" / "mp3".
    static let openAIInputAudioMimeTypes: Set<String> = [
        "audio/wav", "audio/x-wav", "audio/mpeg", "audio/mp3"
    ]

    func shouldInlineBase64EncodedFile(mimeType: String) -> Bool {
        if shouldUploadFile(mimeType: mimeType) {
            return false
        }
        // On OpenAI Responses with a vector store configured, the non-textual
        // attachments that should be sent inline (rather than uploaded to the
        // store) are PDFs (input_file) and images (input_image vision).
        // Marking them inline here, combined with excluding them from
        // shouldUploadFile above, makes the prep pipeline re-add them as
        // inline .file subparts so the serializer emits the typed block.
        if LLMMetadata.hostIsOpenAIAPI(url: parsedModelURL) &&
            (model.api == .responses) &&
            model.vectorStoreConfig != .disabled {
            return mimeType == "application/pdf" || mimeType.hasPrefix("image/")
        }
        return false
    }

    var supportsHostedWebSearch: Bool {
        return model.features.contains(.hostedWebSearch)
    }

    func maxTokens(functions: [LLM.AnyFunction],
                   messages: [LLM.Message]) -> Int {
        let encodedFunctions = {
            if functions.isEmpty || !functionsSupported {
                return ""
            }
            guard let data = try? JSONEncoder().encode(functions.map { $0.decl }) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }()
        let query = messages.compactMap { $0.body.content }.joined(separator: "\n")
        let naiveLimit = Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit)) - AIMetadata.instance.tokens(in: query) - AIMetadata.instance.tokens(in: encodedFunctions)
        return min(model.maxResponseTokens, naiveLimit)
    }

    func requestIsTooLarge(body: String) -> Bool {
        return AIMetadata.instance.tokens(in: body) >= Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit))
    }

    func responseParser() -> LLMResponseParser {
        switch model.api {
        case .chatCompletions, .earlyO1:
            return LLMModernResponseParser()
        case .responses:
            return ResponsesResponseParser()
        case .completions:
            return LLMLegacyResponseParser()
        case .gemini:
            return LLMGeminiResponseParser()
        case .llama:
            return LlamaResponseParser()
        case .deepSeek:
            return DeepSeekResponseParser()
        case .anthropic:
            return AnthropicResponseParser()
        case .appleIntelligence:
            // On-device; AITermController handles the response directly and
            // never parses HTTP data for this provider.
            it_fatalError("Apple Intelligence does not parse HTTP responses")
        @unknown default:
            it_fatalError()
        }
    }

    func streamingResponseParser(stream: Bool) -> LLMStreamingResponseParser? {
        it_assert(stream)
        switch model.api {
        case .chatCompletions, .earlyO1:
            return LLMModernStreamingResponseParser()

        case .responses:
            return ResponsesResponseStreamingParser()

        case .completions:
            return LLMLegacyStreamingResponseParser()

        case .llama:
            return LlamaStreamingResponseParser()

        case .gemini:
            return LLMGeminiStreamingResponseParser()

        case .deepSeek:
            return DeepSeekStreamingResponseParser()

        case .anthropic:
            return AnthropicStreamingResponseParser()

        case .appleIntelligence:
            // On-device and non-streaming; never reached.
            return nil

        @unknown default:
            return nil
        }
    }
}


func MIMETypeIsTextual(_ mimeType: String) -> Bool {
    if mimeType.hasPrefix("text/") {
        return true
    }
    if mimeType == "application/json" {
        return true
    }
    if mimeType == "application/javascript" {
        return true
    }
    if mimeType == "application/ecmascript" {
        return true
    }
    if mimeType.hasSuffix("+xml") {
        return true
    }
    if mimeType == "application/xml" {
        return true
    }
    if mimeType == "message/rfc822" {
        return true
    }
    if mimeType == "application/x-sql" {
        return true
    }
    if mimeType.starts(with: "application/x-tex") {
        return true
    }
    return false
}
