//
//  AILiveAttachmentMatrix.swift
//  iTerm2 AI live harness
//
//  96-cell attachment compatibility matrix (16 MIMEs x 6 vendor lanes).
//  Each cell is a live API call that bypasses LLMProvider.accepts(_:) and
//  feeds the per-vendor request builder a known fixture, then asserts the
//  outcome matches what we expect that vendor to do with that wire shape.
//
//  Purpose: this is the calibration layer. The unit tests in
//  AIRequestBuilderAttachmentTests pin our serializer's behavior; the
//  matrix pins what each vendor actually does with the bytes we send.
//  When a vendor changes (adds support, removes support, changes error
//  shape), some cell flips outcome and lights up a loud failure, telling
//  us to update either the table here or the gate in LLMProvider.swift.
//
//  Six lanes:
//
//    openaiChat       Synthesized gpt-4o-mini model overridden to
//                     api=.chatCompletions, vectorStoreConfig=.disabled.
//                     Production iTerm2 routes OpenAI through .responses
//                     so this lane is purely a calibration probe for the
//                     legacy chat-completions wire format on OpenAI's
//                     servers. The model name resolves; what changes is
//                     the URL and which request builder runs.
//    openaiResponses  Production gpt-4o-mini, api=.responses,
//                     vectorStoreConfig=.openAI. AILiveDriver bypasses
//                     MessagePrepPipeline, so non-PDF binaries take the
//                     inline input_file path (which OpenAI rejects for
//                     image MIMEs and probably other non-PDF binaries
//                     too). The production .fileID upload path is NOT
//                     exercised here; that needs a ChatAgent-driven test.
//    anthropic        claude-haiku-4-5. Exercises the AnthropicMessage
//                     content-block ladder: text / image / document /
//                     lossyString-fallback.
//    gemini           gemini-2.5-flash. inlineData with the attached
//                     MIME; Gemini accepts a wider list than other
//                     vendors (audio, video, heic).
//    deepseek         deepseek-v4-flash. Chat-completions-like; non-text
//                     binaries get wrapped in <iterm2:attachment> via
//                     lossyString.
//    llama            Local Ollama (llama4:latest, /api/chat). Runs only
//                     when LLAMA_API_KEY is set: a record run needs Ollama
//                     up; replay serves committed cassettes with no Ollama.
//
//  Skip semantics: a missing vendor API key skips the lane via
//  keyOrSkip. A failure within a cell fails the corresponding XCTest
//  method with a clear message naming the MIME and the lane.
//

import XCTest
@testable import iTerm2SharedARC

enum AttachmentExpectedOutcome {
    /// HTTP 2xx and the response contains one of the fixture's acceptance
    /// probes (case-insensitive). The vendor parsed the bytes well enough
    /// to surface their semantic content.
    case acceptsAndExtractsProbe
    /// HTTP 4xx returned by the vendor (status code embedded in the error
    /// message via "HTTP request failed with status N"). The serializer
    /// produced a request shape the vendor doesn't accept for that MIME.
    case rejectsAtHTTPLayer
    /// HTTP 2xx but the response does NOT contain the acceptance probe.
    /// Typically what happens when the serializer mangles binary bytes
    /// through lossyString and the vendor sees garbage text rather than
    /// a structured attachment. Useful to pin "didn't crash, but vendor
    /// can't use the content."
    case acceptsButGarbled
    /// The lane is not exercisable (e.g. Llama without live API wiring,
    /// or this MIME's fixture genuinely doesn't have a probe so we can't
    /// distinguish acceptance from garbling). Marked explicitly so the
    /// drift detector ignores it.
    case skipped(reason: String)
}

enum AttachmentLane: String, CaseIterable {
    case openaiChat
    case openaiResponses
    case anthropic
    case gemini
    case deepseek
    case llama

    var displayName: String {
        switch self {
        case .openaiChat:      return "openai/chat-completions"
        case .openaiResponses: return "openai/responses+VS"
        case .anthropic:       return "anthropic"
        case .gemini:          return "gemini"
        case .deepseek:        return "deepseek"
        case .llama:           return "llama"
        }
    }

    var keyVendor: String {
        switch self {
        case .openaiChat, .openaiResponses: return "openai"
        case .anthropic: return "anthropic"
        case .gemini:    return "gemini"
        case .deepseek:  return "deepseek"
        case .llama:     return "llama"
        }
    }

    /// AIMetadata.Model to drive for this lane. Most lanes look up the
    /// canonical model; openaiChat synthesizes a model with the URL/api
    /// overridden so we exercise the chat-completions request builder.
    func resolveModel() throws -> AIMetadata.Model {
        switch self {
        case .openaiChat:
            // gpt-4o-mini overridden to chat-completions. The model name
            // and feature set match the real model; only the URL and api
            // field are swapped so the chatCompletions builder runs.
            guard let base = AIMetadata.instance.models.first(where: { $0.name == "gpt-4o-mini" }) else {
                throw AttachmentMatrixError.modelMissing("gpt-4o-mini")
            }
            var m = base
            m.url = "https://api.openai.com/v1/chat/completions"
            m.api = .chatCompletions
            m.vectorStoreConfig = .disabled
            return m
        case .openaiResponses:
            return try lookup("gpt-4o-mini")
        case .anthropic:
            return try lookup("claude-haiku-4-5")
        case .gemini:
            return try lookup("gemini-2.5-flash")
        case .deepseek:
            return try lookup("deepseek-v4-flash")
        case .llama:
            // Local Ollama, url http://localhost:11434/api/chat. Pinned to
            // llama3.3:latest: the multimodal llama4 (67GB) does not fit in
            // 64GB RAM and is unusably slow, and llama3.3 is the llama-family
            // model in AIMetadata that fits. It is text-only, so the lane
            // covers the text cells; the binary/image cells stay skipped (see
            // the matrix). The lane only runs when LLAMA_API_KEY is set (see
            // keyOrSkipForLane): a record run needs Ollama up; replay serves a
            // committed cassette and never reaches the network.
            return try lookup("llama3.3:latest")
        }
    }

    private func lookup(_ name: String) throws -> AIMetadata.Model {
        guard let m = AIMetadata.instance.models.first(where: { $0.name == name }) else {
            throw AttachmentMatrixError.modelMissing(name)
        }
        return m
    }
}

enum AttachmentMatrixError: Error, CustomStringConvertible {
    case modelMissing(String)
    case lanePermanentlySkipped(String)

    var description: String {
        switch self {
        case .modelMissing(let n): return "model \(n) not in AIMetadata"
        case .lanePermanentlySkipped(let r): return r
        }
    }
}

enum AttachmentMatrix {
    /// The 96 cells. Encoded with `expectations[lane]?[kind]`. If a cell
    /// is missing it defaults to `.acceptsButGarbled` (the catch-all for
    /// non-fatal lossyString fallback) — but every cell is enumerated
    /// explicitly below so a missing entry would be a coding error, not
    /// a quiet fallback.
    static let expectations: [AttachmentLane: [AILiveAttachmentKind: AttachmentExpectedOutcome]] = [

        // MARK: openaiChat (chat-completions request builder)
        //
        // The builder's .file path (CompletionsMessage.contentPart) now emits
        // image_url for image/*, input_audio for wav/mp3, file for PDF, and
        // wraps any other binary in <iterm2:attachment> via lossyString.
        // gpt-4o-mini has vision, so png/webp are read (probe matches);
        // heic/tiff aren't accepted image formats so the vendor 4xxs. The
        // model is not an audio model, so input_audio 4xxs.
        .openaiChat: [
            .textPlain:        .acceptsAndExtractsProbe,
            .textMarkdown:     .acceptsAndExtractsProbe,
            .applicationJSON:  .acceptsAndExtractsProbe,
            .applicationXML:   .acceptsAndExtractsProbe,
            .imageSVG:         .acceptsAndExtractsProbe,
            .yamlAsUnknown:    .acceptsAndExtractsProbe,
            .imagePNG:         .acceptsAndExtractsProbe,
            .imageWEBP:        .acceptsAndExtractsProbe,
            .imageHEIC:        .rejectsAtHTTPLayer,
            .imageTIFF:        .rejectsAtHTTPLayer,
            .applicationPDF:   .acceptsAndExtractsProbe,
            // input_audio sent to gpt-4o-mini, which is not an audio model:
            // OpenAI 4xxs rather than garbling. (An audio model would parse
            // it, but no audio-capable model is wired into this lane.)
            .audioMPEG:        .rejectsAtHTTPLayer,
            .videoMP4:         .skipped(reason: "scroll-browser mp4 fixture has no deterministic content probe; garbled vs. seen is indistinguishable"),
            .applicationDOCX:  .acceptsButGarbled,
            .applicationZIP:   .acceptsButGarbled,
            .applicationOctet: .skipped(reason: "no probe encoded in random bytes"),
        ],

        // MARK: openaiResponses (responses+VS)
        //
        // AILiveDriver bypasses MessagePrepPipeline. Images now serialize as
        // input_image (vision) with a base64 data URL, so png/webp are read
        // and the probe matches; heic/tiff aren't accepted image formats so
        // the vendor 4xxs. Non-image, non-PDF binaries still take the inline
        // input_file path, which OpenAI rejects for audio/video/zip/octet.
        .openaiResponses: [
            .textPlain:        .acceptsAndExtractsProbe,
            .textMarkdown:     .acceptsAndExtractsProbe,
            .applicationJSON:  .acceptsAndExtractsProbe,
            .applicationXML:   .acceptsAndExtractsProbe,
            .imageSVG:         .acceptsAndExtractsProbe,
            .yamlAsUnknown:    .acceptsAndExtractsProbe,
            .imagePNG:         .acceptsAndExtractsProbe,
            .imageWEBP:        .acceptsAndExtractsProbe,
            .imageHEIC:        .rejectsAtHTTPLayer,
            .imageTIFF:        .rejectsAtHTTPLayer,
            .applicationPDF:   .acceptsAndExtractsProbe,
            .audioMPEG:        .rejectsAtHTTPLayer,
            .videoMP4:         .rejectsAtHTTPLayer,
            // Empirically: OpenAI Responses ACCEPTS inline DOCX via
            // input_file (contradicting the TODO at
            // ResponsesAPIRequest.swift:1712 which claimed only image
            // MIMEs are rejected). DOCX comes back parsed with title
            // extraction working. Captured by the live matrix; if this
            // ever flips to 4xx, the TODO comment can be updated to
            // include DOCX and this cell back to .rejectsAtHTTPLayer.
            .applicationDOCX:  .acceptsAndExtractsProbe,
            .applicationZIP:   .rejectsAtHTTPLayer,
            .applicationOctet: .rejectsAtHTTPLayer,
        ],

        // MARK: anthropic
        //
        // AnthropicMessage serializer routes textual to .string, any image/*
        // to an .image block with its real media type, PDF to .document, and
        // everything else to lossyString. Anthropic accepts jpeg/png/gif/webp
        // images and 4xxs other image formats (heic/tiff) instead of garbling
        // them. Non-image, non-PDF binaries still become mangled text.
        .anthropic: [
            .textPlain:        .acceptsAndExtractsProbe,
            .textMarkdown:     .acceptsAndExtractsProbe,
            .applicationJSON:  .acceptsAndExtractsProbe,
            .applicationXML:   .acceptsAndExtractsProbe,
            .imageSVG:         .acceptsAndExtractsProbe,
            .yamlAsUnknown:    .acceptsAndExtractsProbe,
            .imagePNG:         .acceptsAndExtractsProbe,
            .imageWEBP:        .acceptsAndExtractsProbe,
            .imageHEIC:        .rejectsAtHTTPLayer,
            .imageTIFF:        .rejectsAtHTTPLayer,
            .applicationPDF:   .acceptsAndExtractsProbe,
            .audioMPEG:        .skipped(reason: "synth mp3 fixture has no deterministic content probe; garbled vs. heard is indistinguishable"),
            .videoMP4:         .skipped(reason: "scroll-browser mp4 fixture has no deterministic content probe; garbled vs. seen is indistinguishable"),
            .applicationDOCX:  .acceptsButGarbled,
            .applicationZIP:   .acceptsButGarbled,
            .applicationOctet: .acceptsButGarbled,
        ],

        // MARK: gemini
        //
        // Gemini.swift:170-173 wraps every binary as inlineData with the
        // attached MIME. Gemini's published acceptance list covers
        // images jpeg/png/webp/heic/heif, application/pdf, plus audio
        // and video. tiff/docx/zip/octet are outside that list; they
        // typically return 400 INVALID_ARGUMENT.
        .gemini: [
            .textPlain:        .acceptsAndExtractsProbe,
            .textMarkdown:     .acceptsAndExtractsProbe,
            .applicationJSON:  .acceptsAndExtractsProbe,
            .applicationXML:   .acceptsAndExtractsProbe,
            .imageSVG:         .acceptsAndExtractsProbe,
            .yamlAsUnknown:    .acceptsAndExtractsProbe,
            .imagePNG:         .acceptsAndExtractsProbe,
            .imageWEBP:        .acceptsAndExtractsProbe,
            .imageHEIC:        .acceptsAndExtractsProbe,
            .imageTIFF:        .rejectsAtHTTPLayer,
            .applicationPDF:   .acceptsAndExtractsProbe,
            // Gemini supports audio/video natively via inlineData. These
            // matrix fixtures (3s synth, scroll-browser screen capture) have
            // no deterministic content probe, so they stay skipped here; the
            // inlineData audio/video paths are positively verified against a
            // deterministic spoken/shown probe by test_gemini_audioTranscribe_*
            // and test_gemini_videoDescribe.
            .audioMPEG:        .skipped(reason: "no deterministic probe in this fixture; inlineData audio verified by test_gemini_audioTranscribe_{mp3,wav}"),
            .videoMP4:         .skipped(reason: "no deterministic probe in this fixture; inlineData video verified by test_gemini_videoDescribe"),
            .applicationDOCX:  .rejectsAtHTTPLayer,
            .applicationZIP:   .rejectsAtHTTPLayer,
            .applicationOctet: .rejectsAtHTTPLayer,
        ],

        // MARK: deepseek
        //
        // DeepSeek.swift:119-135 wraps binaries in <iterm2:attachment>
        // via lossyString. The vendor doesn't reject; it just sees
        // garbage text. Same shape as openaiChat.
        .deepseek: [
            .textPlain:        .acceptsAndExtractsProbe,
            .textMarkdown:     .acceptsAndExtractsProbe,
            .applicationJSON:  .acceptsAndExtractsProbe,
            .applicationXML:   .acceptsAndExtractsProbe,
            .imageSVG:         .acceptsAndExtractsProbe,
            .yamlAsUnknown:    .acceptsAndExtractsProbe,
            .imagePNG:         .acceptsButGarbled,
            .imageWEBP:        .acceptsButGarbled,
            .imageHEIC:        .acceptsButGarbled,
            .imageTIFF:        .acceptsButGarbled,
            .applicationPDF:   .acceptsButGarbled,
            .audioMPEG:        .skipped(reason: "synth mp3 fixture has no deterministic content probe; garbled vs. heard is indistinguishable"),
            .videoMP4:         .skipped(reason: "scroll-browser mp4 fixture has no deterministic content probe; garbled vs. seen is indistinguishable"),
            .applicationDOCX:  .acceptsButGarbled,
            .applicationZIP:   .acceptsButGarbled,
            .applicationOctet: .skipped(reason: "no probe encoded in random bytes"),
        ],

        // MARK: llama (local Ollama, llama3.3:latest — text cells only)
        //
        // Pinned to the text-only llama3.3 because the multimodal llama4 does
        // not fit in 64GB RAM. The lane therefore covers the text-shaped cells
        // (the model reads the text content and echoes the probe); the binary
        // and image cells are skipped here rather than recorded, since a
        // text-only model can't meaningfully process them and recording garbled
        // output adds no signal. If a vision model that fits in RAM is later
        // pinned (e.g. llava / llama3.2-vision), flip the image cells on and
        // record them. The text expectations are calibration placeholders: the
        // record run prints `[live] llama <kind>: expected=.. actual=..`;
        // reconcile any drift before committing the cassettes.
        .llama: [
            .textPlain:        .acceptsAndExtractsProbe,
            .textMarkdown:     .acceptsAndExtractsProbe,
            .applicationJSON:  .acceptsAndExtractsProbe,
            .applicationXML:   .acceptsAndExtractsProbe,
            .imageSVG:         .acceptsAndExtractsProbe,
            .yamlAsUnknown:    .acceptsAndExtractsProbe,
            .imagePNG:         .skipped(reason: "llama lane pinned to text-only llama3.3; image cells need a vision model that fits in RAM"),
            .imageWEBP:        .skipped(reason: "llama lane pinned to text-only llama3.3; image cells need a vision model that fits in RAM"),
            .imageHEIC:        .skipped(reason: "llama lane pinned to text-only llama3.3; image cells need a vision model that fits in RAM"),
            .imageTIFF:        .skipped(reason: "llama lane pinned to text-only llama3.3; image cells need a vision model that fits in RAM"),
            .applicationPDF:   .skipped(reason: "llama lane pinned to text-only llama3.3; binary cells not covered"),
            .audioMPEG:        .skipped(reason: "synth mp3 fixture has no deterministic content probe; garbled vs. heard is indistinguishable"),
            .videoMP4:         .skipped(reason: "scroll-browser mp4 fixture has no deterministic content probe; garbled vs. seen is indistinguishable"),
            .applicationDOCX:  .skipped(reason: "llama lane pinned to text-only llama3.3; binary cells not covered"),
            .applicationZIP:   .skipped(reason: "llama lane pinned to text-only llama3.3; binary cells not covered"),
            .applicationOctet: .skipped(reason: "no probe encoded in random bytes"),
        ],
    ]

    /// Resolve a cell's expected outcome. Crashes loudly if a cell is
    /// missing from the table — every (lane, kind) pair must be enumerated
    /// above so adding a new MIME or a new lane forces an explicit
    /// classification.
    static func expectedOutcome(lane: AttachmentLane,
                                kind: AILiveAttachmentKind) -> AttachmentExpectedOutcome {
        guard let cell = expectations[lane]?[kind] else {
            it_fatalError("Attachment matrix missing cell for \(lane.rawValue)/\(kind.rawValue). Add an explicit entry to AttachmentMatrix.expectations.")
        }
        return cell
    }
}
