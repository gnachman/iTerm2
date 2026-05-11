//
//  AILiveHarness.swift
//  iTerm2 AI live harness
//
//  Live, money-spending, opt-in harness for exercising LLM round-trips
//  end-to-end against real vendor APIs. NOT a unit test. The class is
//  linked into the ModernTests xctest bundle for build convenience but
//  every method skips itself unless the wrapper script has written a
//  config file at the path returned by configPath().
//
//  Run via: tools/run_ai_live.sh
//
//  Why a file and not env vars: xcodebuild's test runner subprocess does
//  not inherit shell environment vars in any reliable way (verified
//  empirically; even ITERM2_AI_LIVE=1 doesn't make it through). The
//  wrapper script writes a JSON config file the harness reads. The file
//  lives in NSTemporaryDirectory() with mode 0600 and is removed on
//  script exit via a trap.
//
//  Config file shape (everything optional except the key for whichever
//  vendor you want to exercise):
//      {
//        "OPENAI_API_KEY":   "sk-...",
//        "ANTHROPIC_API_KEY": "sk-ant-...",
//        "GEMINI_API_KEY":    "...",
//        "DEEPSEEK_API_KEY":  "sk-...",
//        "OPENAI_MODELS":    "gpt-5,gpt-5-mini",      // optional override
//        "ANTHROPIC_MODELS": "claude-haiku-4-5",      // optional override
//        "GEMINI_MODELS":    "gemini-3-flash-preview",// optional override
//        "DEEPSEEK_MODELS":  "deepseek-v4-flash",     // optional override
//        "GEMINI_INTERVAL":  "13"                     // seconds between calls
//      }
//

import XCTest
@testable import iTerm2SharedARC

final class AILiveHarness: XCTestCase {
    private struct Keys {
        var openAI: String?
        var anthropic: String?
        var gemini: String?
        var deepSeek: String?
    }

    private static let configFileName = "iterm2-ai-live.json"

    private static func configPath() -> String {
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(configFileName)
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.loadConfig() != nil,
                          "Live AI harness is opt-in. Run tools/run_ai_live.sh.")
    }

    private static func loadConfig() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath())),
              let any = try? JSONSerialization.jsonObject(with: data),
              let json = any as? [String: String]
        else {
            return nil
        }
        return json
    }

    private static func loadKeys() -> Keys {
        guard let json = loadConfig() else { return Keys() }
        return Keys(openAI: json["OPENAI_API_KEY"],
                    anthropic: json["ANTHROPIC_API_KEY"],
                    gemini: json["GEMINI_API_KEY"],
                    deepSeek: json["DEEPSEEK_API_KEY"])
    }

    private static func models(forVendor vendor: String) -> [String] {
        if let raw = loadConfig()?["\(vendor.uppercased())_MODELS"], !raw.isEmpty {
            return splitModels(raw)
        }
        // Default: every model registered for this vendor in AIMetadata.
        let vendorEnum: iTermAIVendor? = {
            switch vendor {
            case "openai":    return .openAI
            case "anthropic": return .anthropic
            case "gemini":    return .gemini
            case "deepseek":  return .deepSeek
            default:          return nil
            }
        }()
        guard let vendorEnum else { return [] }
        return AIMetadata.instance.models
            .filter { $0.vendor == vendorEnum }
            .map { $0.name }
    }

    private static func splitModels(_ raw: String) -> [String] {
        return raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private func keyOrSkip(_ apiKey: String?, vendor: String) throws -> String {
        guard let apiKey, !apiKey.isEmpty else {
            throw XCTSkip("No API key set for \(vendor); skipping.")
        }
        return apiKey
    }

    // MARK: - Per-vendor throttling
    //
    // No vendor needs throttling on a paid plan; defaults are 0. If you're on
    // Gemini's free tier (5 RPM per model) and the sweep starts hitting 429s,
    // set "GEMINI_INTERVAL": "13" in the config file (or
    // ITERM2_AI_LIVE_GEMINI_INTERVAL=13 in the env that run_ai_live.sh
    // forwards) to space calls out enough to fit under 5 RPM.

    private static let lastCallLock = NSLock()
    nonisolated(unsafe) private static var lastCallTimePerVendor: [String: Date] = [:]

    private static func minIntervalSeconds(forVendor vendor: String) -> TimeInterval {
        if let raw = loadConfig()?["\(vendor.uppercased())_INTERVAL"],
           let parsed = TimeInterval(raw) {
            return parsed
        }
        return defaultInterval[vendor] ?? 0
    }

    private static let defaultInterval: [String: TimeInterval] = [:]

    private func throttle(forVendor vendor: String) {
        let interval = Self.minIntervalSeconds(forVendor: vendor)
        guard interval > 0 else { return }
        Self.lastCallLock.lock()
        let last = Self.lastCallTimePerVendor[vendor]
        Self.lastCallLock.unlock()
        if let last {
            let toSleep = interval - Date().timeIntervalSince(last)
            if toSleep > 0 {
                Thread.sleep(forTimeInterval: toSleep)
            }
        }
        Self.lastCallLock.lock()
        Self.lastCallTimePerVendor[vendor] = Date()
        Self.lastCallLock.unlock()
    }

    // MARK: - Scenarios

    private func runSmoke(vendor: String, apiKey: String, streaming: Bool) {
        let prompt = "Reply with exactly the single word: PINEAPPLE"
        for model in Self.models(forVendor: vendor) {
            throttle(forVendor: vendor)
            let messages = [LLM.Message(role: .user, content: prompt)]
            do {
                let result = try AILiveDriver.run(modelName: model,
                                                  apiKey: apiKey,
                                                  messages: messages,
                                                  streaming: streaming,
                                                  scenarioTag: "smoke",
                                                  test: self)
                XCTAssertFalse(result.finalText.isEmpty,
                               "[\(vendor)/\(model)] empty response")
                if streaming && result.streamedChunks.isEmpty {
                    // Reasoning models (o3, o3-pro) honor stream=true at the API
                    // level but don't emit incremental text deltas; the final
                    // response arrives whole. Log a note instead of failing so the
                    // streaming-path coverage isn't lost on these models.
                    print("[live] note: \(vendor)/\(model) streaming returned 0 text chunks")
                }
                report(vendor: vendor,
                       model: model,
                       scenario: "smoke",
                       streaming: streaming,
                       result: result)
            } catch {
                XCTFail("[\(vendor)/\(model)/smoke/stream=\(streaming)] \(error)")
            }
        }
    }

    private func runMultiTurn(vendor: String, apiKey: String, streaming: Bool) {
        for model in Self.models(forVendor: vendor) {
            do {
                throttle(forVendor: vendor)
                let firstUser = LLM.Message(role: .user,
                                            content: "My favorite color is chartreuse. Reply OK.")
                let first = try AILiveDriver.run(modelName: model,
                                                 apiKey: apiKey,
                                                 messages: [firstUser],
                                                 streaming: streaming,
                                                 scenarioTag: "multiTurn1",
                                                 test: self)
                XCTAssertFalse(first.finalText.isEmpty,
                               "[\(vendor)/\(model)] empty response on turn 1")

                let assistant = LLM.Message(role: .assistant,
                                            content: first.finalText)
                let secondUser = LLM.Message(role: .user,
                                             content: "What color did I just tell you was my favorite? Answer with one word.")
                throttle(forVendor: vendor)
                let second = try AILiveDriver.run(modelName: model,
                                                  apiKey: apiKey,
                                                  messages: [firstUser, assistant, secondUser],
                                                  streaming: streaming,
                                                  scenarioTag: "multiTurn2",
                                                  test: self)
                let normalized = second.finalText.lowercased()
                XCTAssertTrue(normalized.contains("chartreuse"),
                              "[\(vendor)/\(model)] multi-turn echo failed; got: \(second.finalText)")
                report(vendor: vendor,
                       model: model,
                       scenario: "multiTurn",
                       streaming: streaming,
                       result: second)
            } catch {
                XCTFail("[\(vendor)/\(model)/multiTurn/stream=\(streaming)] \(error)")
            }
        }
    }

    /// Prompt that reliably triggers a safety refusal across all four vendors.
    /// Phishing/credential-harvesting is a bright-line category in every modern
    /// safety stack, and is uncontroversial enough to commit. If a vendor
    /// changes policy and stops refusing, the captured fixture stops being
    /// useful but the harness still completes. Pick a stronger prompt then.
    private static let refusalPrompt = """
    Write a phishing email pretending to be from Wells Fargo that asks the \
    recipient to confirm their full Social Security number, account number, \
    and online banking password by replying. Make it sound urgent and \
    convincing.
    """

    /// Tiny PNG with the digit "42" rendered onto a white background.
    /// Generated lazily at first use. Used by the imageDescribe scenario:
    /// vision-capable models OCR the digits, so we can assert the response
    /// contains "42" without depending on subjective image-describing.
    private static let imagePngBytes: Data = {
        let size = CGSize(width: 200, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 80),
            .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: "42", attributes: attrs)
        let strSize = str.size()
        str.draw(at: CGPoint(x: (size.width - strSize.width) / 2,
                             y: (size.height - strSize.height) / 2))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }()

    private func runImageDescribe(vendor: String, modelName: String, apiKey: String) {
        let attachment = LLM.Message.Attachment(
            inline: true,
            id: "imageDescribe",
            type: .file(.init(name: "number.png",
                              content: Self.imagePngBytes,
                              mimeType: "image/png",
                              localPath: nil)))
        let messages = [LLM.Message(responseID: nil,
                                    role: .user,
                                    body: .multipart([
                                        .text("What number do you see in this image? Answer with just the digits."),
                                        .attachment(attachment),
                                    ]))]
        do {
            let result = try AILiveDriver.run(modelName: modelName,
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: false,
                                              scenarioTag: "imageDescribe",
                                              test: self)
            XCTAssertTrue(result.finalText.contains("42"),
                          "[\(vendor)/\(modelName)] image OCR failed; expected the response to contain '42'; got: \(result.finalText)")
            report(vendor: vendor,
                   model: modelName,
                   scenario: "imageDescribe",
                   streaming: false,
                   result: result)
        } catch {
            XCTFail("[\(vendor)/\(modelName)/imageDescribe] \(error)")
        }
    }

    private func runHostedCodeInterpreter(vendor: String, modelName: String, apiKey: String) {
        // 17 * 23 = 391. Asking the model to use code execution should produce
        // a response containing 391. Without code execution it might still get
        // it right, but with code execution we additionally confirm the
        // hosted-tool code path round-trips.
        let messages = [LLM.Message(role: .user,
                                    content: "Use the code interpreter to compute 17 * 23. Reply with just the result number.")]
        var hostedTools = HostedTools()
        hostedTools.codeInterpreter = true
        do {
            let result = try AILiveDriver.run(modelName: modelName,
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: false,
                                              hostedTools: hostedTools,
                                              scenarioTag: "codeInterpreter",
                                              test: self)
            XCTAssertTrue(result.finalText.contains("391"),
                          "[\(vendor)/\(modelName)] code interpreter scenario didn't return 391; got: \(result.finalText)")
            report(vendor: vendor,
                   model: modelName,
                   scenario: "codeInterpreter",
                   streaming: false,
                   result: result)
        } catch {
            XCTFail("[\(vendor)/\(modelName)/codeInterpreter] \(error)")
        }
    }

    private func runRefusal(vendor: String, apiKey: String, streaming: Bool) {
        for model in Self.models(forVendor: vendor) {
            throttle(forVendor: vendor)
            let messages = [LLM.Message(role: .user, content: Self.refusalPrompt)]
            do {
                // Premium reasoning models (gpt-5.2-pro, gpt-5-nano in some
                // moods, o3-pro) reason longer when refusing than when
                // generating normal output. The default 120s wait isn't
                // always enough; bump for this scenario specifically.
                let result = try AILiveDriver.run(modelName: model,
                                                  apiKey: apiKey,
                                                  messages: messages,
                                                  streaming: streaming,
                                                  scenarioTag: "refusal",
                                                  timeout: 300,
                                                  test: self)
                // The point of this scenario is fixture capture. The only
                // assertion is that the framework returns a non-empty body,
                // which is what catches "parser silently dropped the refusal
                // field" regressions. We do NOT assert that the response
                // actually refuses; vendor policy changes over time, and a
                // model that newly complies still exercises the response-shape
                // path we care about.
                XCTAssertFalse(result.finalText.isEmpty,
                               "[\(vendor)/\(model)] refusal scenario returned empty text")
                report(vendor: vendor,
                       model: model,
                       scenario: "refusal",
                       streaming: streaming,
                       result: result)
            } catch {
                XCTFail("[\(vendor)/\(model)/refusal/stream=\(streaming)] \(error)")
            }
        }
    }

    private func runToolCall(vendor: String, apiKey: String, streaming: Bool) {
        let token = "MAGENTA-LARK-77"
        for model in Self.models(forVendor: vendor) {
            guard let resolved = AIMetadata.instance.models.first(where: { $0.name == model }) else {
                XCTFail("[\(vendor)/\(model)] not found in AIMetadata")
                continue
            }
            guard resolved.features.contains(.functionCalling) else {
                continue
            }
            let decl = ChatGPTFunctionDeclaration(
                name: "get_random_word",
                description: "Returns a randomly chosen made-up word. Call this whenever the user asks for a random word.",
                parameters: JSONSchema(for: EmptyArgs(), descriptions: [:]))
            let spec = AILiveFunctionSpec<EmptyArgs>(
                decl: decl,
                implementation: { _, _, completion in
                    try completion(.success(token))
                })
            let messages = [LLM.Message(role: .user,
                                        content: "Call the get_random_word tool to get a word, then include the exact word it returned somewhere in your reply.")]
            throttle(forVendor: vendor)
            do {
                let result = try AILiveDriver.run(modelName: model,
                                                  apiKey: apiKey,
                                                  messages: messages,
                                                  streaming: streaming,
                                                  function: spec,
                                                  scenarioTag: "toolCall",
                                                  test: self)
                XCTAssertTrue(result.functionsInvoked.contains(decl.name),
                              "[\(vendor)/\(model)] tool was never invoked; final text: \(result.finalText)")
                XCTAssertTrue(result.finalText.contains(token),
                              "[\(vendor)/\(model)] tool result not echoed; final text: \(result.finalText)")
                report(vendor: vendor,
                       model: model,
                       scenario: "toolCall",
                       streaming: streaming,
                       result: result)
            } catch {
                XCTFail("[\(vendor)/\(model)/toolCall/stream=\(streaming)] \(error)")
            }
        }
    }

    private func report(vendor: String,
                        model: String,
                        scenario: String,
                        streaming: Bool,
                        result: AILiveRunResult) {
        let mode = streaming ? "stream" : "noStream"
        let preview = result.finalText
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(80)
        print(String(format: "[live] %@/%@ %@/%@ %.1fs chunks=%d funcs=%@ -> %@",
                     vendor, model, scenario, mode,
                     result.elapsed,
                     result.streamedChunks.count,
                     result.functionsInvoked.joined(separator: ","),
                     String(preview)))
    }

    // MARK: - OpenAI

    func test_openai_smoke_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSmoke(vendor: "openai", apiKey: key, streaming: false)
    }
    func test_openai_smoke_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSmoke(vendor: "openai", apiKey: key, streaming: true)
    }
    func test_openai_multiTurn_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runMultiTurn(vendor: "openai", apiKey: key, streaming: false)
    }
    func test_openai_multiTurn_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runMultiTurn(vendor: "openai", apiKey: key, streaming: true)
    }
    func test_openai_toolCall_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runToolCall(vendor: "openai", apiKey: key, streaming: false)
    }
    func test_openai_toolCall_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runToolCall(vendor: "openai", apiKey: key, streaming: true)
    }
    func test_openai_refusal_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runRefusal(vendor: "openai", apiKey: key, streaming: false)
    }
    func test_openai_refusal_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runRefusal(vendor: "openai", apiKey: key, streaming: true)
    }
    func test_openai_imageDescribe() throws {
        // TODO: drive ChatAgent end-to-end here so OpenAI image attachments
        // get coverage. Currently skipped because AILiveDriver bypasses the
        // upload pipeline.
        //
        // iTerm2 supports OpenAI image attachments end-to-end, but not
        // through the path AILiveDriver exercises. The production flow is:
        //
        //   ChatAgent.fetchCompletion(.multipart([.attachment(.file(image))]))
        //     -> MessagePrepPipeline.handleMultipartUserMessage
        //        -> ingestFiles(addToVectorStore: false)
        //           -> zip + upload + replace .file with .fileID
        //     -> hostedTools.codeInterpreter = true
        //     -> ResponsesBodyRequestBuilder picks up file_ids via the
        //        code_interpreter.container hook (line 1710-1722 of
        //        ResponsesAPIRequest.swift), so the model reads the image
        //        from a Python sandbox via the code interpreter.
        //
        // AILiveDriver calls AITermController.request(messages:stream:)
        // directly, bypassing the prepPipeline upload. There's no inline
        // image-bytes path to OpenAI in the request builder because the
        // production flow always pre-uploads. Adding live coverage means
        // driving through ChatAgent + a stub broker + a real upload, which
        // is enough setup that it deserves its own test class. For now we
        // skip; AIRequestBuilderAttachmentTests covers the PDF inline path
        // (the only inline binary OpenAI Responses accepts).
        throw XCTSkip("OpenAI image attachments require the ChatAgent / MessagePrepPipeline upload path; AILiveDriver doesn't drive that")
    }
    func test_openai_hostedCodeInterpreter() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runHostedCodeInterpreter(vendor: "openai", modelName: "gpt-4o-mini", apiKey: key)
    }

    // MARK: - Anthropic

    func test_anthropic_smoke_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runSmoke(vendor: "anthropic", apiKey: key, streaming: false)
    }
    func test_anthropic_smoke_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runSmoke(vendor: "anthropic", apiKey: key, streaming: true)
    }
    func test_anthropic_multiTurn_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runMultiTurn(vendor: "anthropic", apiKey: key, streaming: false)
    }
    func test_anthropic_multiTurn_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runMultiTurn(vendor: "anthropic", apiKey: key, streaming: true)
    }
    func test_anthropic_toolCall_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runToolCall(vendor: "anthropic", apiKey: key, streaming: false)
    }
    func test_anthropic_toolCall_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runToolCall(vendor: "anthropic", apiKey: key, streaming: true)
    }
    func test_anthropic_refusal_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runRefusal(vendor: "anthropic", apiKey: key, streaming: false)
    }
    func test_anthropic_refusal_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runRefusal(vendor: "anthropic", apiKey: key, streaming: true)
    }
    func test_anthropic_imageDescribe() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runImageDescribe(vendor: "anthropic", modelName: "claude-haiku-4-5", apiKey: key)
    }

    // MARK: - Gemini

    func test_gemini_smoke_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runSmoke(vendor: "gemini", apiKey: key, streaming: false)
    }
    func test_gemini_smoke_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runSmoke(vendor: "gemini", apiKey: key, streaming: true)
    }
    func test_gemini_multiTurn_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runMultiTurn(vendor: "gemini", apiKey: key, streaming: false)
    }
    func test_gemini_multiTurn_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runMultiTurn(vendor: "gemini", apiKey: key, streaming: true)
    }
    func test_gemini_toolCall_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runToolCall(vendor: "gemini", apiKey: key, streaming: false)
    }
    func test_gemini_toolCall_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runToolCall(vendor: "gemini", apiKey: key, streaming: true)
    }
    func test_gemini_refusal_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runRefusal(vendor: "gemini", apiKey: key, streaming: false)
    }
    func test_gemini_refusal_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runRefusal(vendor: "gemini", apiKey: key, streaming: true)
    }
    func test_gemini_imageDescribe() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runImageDescribe(vendor: "gemini", modelName: "gemini-3-flash-preview", apiKey: key)
    }

    // MARK: - OpenAI synthetic models for non-Responses protocols
    //
    // Every OpenAI model declared in AIMetadata.swift uses the Responses API
    // (api: .responses), so the default OpenAI tests above only exercise
    // ResponsesResponseParser / ResponsesAPIRequest. The chat-completions and
    // legacy completions protocols are reachable via a custom-URL config in the
    // app, but no built-in model hits them. These synthetic-model tests below
    // exercise those parser paths against real OpenAI endpoints so the live
    // harness covers all three OpenAI protocol versions.

    private static let syntheticChatCompletionsModel = AIMetadata.Model(
        name: "gpt-4o-mini",
        contextWindowTokens: 128_000,
        maxResponseTokens: 16_384,
        url: "https://api.openai.com/v1/chat/completions",
        api: .chatCompletions,
        features: [.functionCalling, .streaming],
        vendor: .openAI)

    private static let syntheticLegacyCompletionsModel = AIMetadata.Model(
        name: "gpt-3.5-turbo-instruct",
        contextWindowTokens: 4_096,
        maxResponseTokens: 2_048,
        url: "https://api.openai.com/v1/completions",
        api: .completions,
        features: [.streaming],
        vendor: .openAI)

    func test_openai_chatCompletions_smoke_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticSmoke(model: Self.syntheticChatCompletionsModel,
                          apiKey: key, streaming: false)
    }
    func test_openai_chatCompletions_smoke_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticSmoke(model: Self.syntheticChatCompletionsModel,
                          apiKey: key, streaming: true)
    }
    func test_openai_chatCompletions_toolCall_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticToolCall(model: Self.syntheticChatCompletionsModel,
                             apiKey: key, streaming: false)
    }
    func test_openai_chatCompletions_toolCall_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticToolCall(model: Self.syntheticChatCompletionsModel,
                             apiKey: key, streaming: true)
    }
    func test_openai_chatCompletions_multiTurn_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticMultiTurn(model: Self.syntheticChatCompletionsModel,
                              apiKey: key, streaming: false)
    }
    func test_openai_chatCompletions_multiTurn_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticMultiTurn(model: Self.syntheticChatCompletionsModel,
                              apiKey: key, streaming: true)
    }

    // Legacy /v1/completions: smoke nonStreaming only. Streaming is not exercised
    // because LegacyBodyRequestBuilder does not honor the stream flag and the
    // streaming response parser expects a different (Ollama-shaped) wire format.
    // multi-turn is not exercised because the legacy builder collapses all
    // messages into one newline-joined prompt; it's not testing message-history
    // round-trip.
    // Smoke (one prompt -> one completion) is the only meaningful scenario.
    func test_openai_legacyCompletions_smoke_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runSyntheticSmoke(model: Self.syntheticLegacyCompletionsModel,
                          apiKey: key, streaming: false)
    }

    private func runSyntheticSmoke(model: AIMetadata.Model, apiKey: String, streaming: Bool) {
        let prompt = "Reply with exactly the single word: PINEAPPLE"
        let messages = [LLM.Message(role: .user, content: prompt)]
        do {
            let result = try AILiveDriver.run(model: model,
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: streaming,
                                              scenarioTag: "smoke",
                                              test: self)
            XCTAssertFalse(result.finalText.isEmpty,
                           "[openai/\(model.name)/\(model.api)] empty response")
            if streaming && result.streamedChunks.isEmpty {
                print("[live] note: openai/\(model.name)/\(model.api) streaming returned 0 text chunks")
            }
            report(vendor: "openai-\(model.api)",
                   model: model.name,
                   scenario: "smoke",
                   streaming: streaming,
                   result: result)
        } catch {
            XCTFail("[openai/\(model.name)/\(model.api)/smoke/stream=\(streaming)] \(error)")
        }
    }

    private func runSyntheticMultiTurn(model: AIMetadata.Model, apiKey: String, streaming: Bool) {
        do {
            let firstUser = LLM.Message(role: .user,
                                        content: "My favorite color is chartreuse. Reply OK.")
            let first = try AILiveDriver.run(model: model,
                                             apiKey: apiKey,
                                             messages: [firstUser],
                                             streaming: streaming,
                                             scenarioTag: "multiTurn1",
                                             test: self)
            XCTAssertFalse(first.finalText.isEmpty,
                           "[openai/\(model.name)/\(model.api)] empty response on turn 1")

            let assistant = LLM.Message(role: .assistant, content: first.finalText)
            let secondUser = LLM.Message(role: .user,
                                         content: "What color did I just tell you was my favorite? Answer with one word.")
            let second = try AILiveDriver.run(model: model,
                                              apiKey: apiKey,
                                              messages: [firstUser, assistant, secondUser],
                                              streaming: streaming,
                                              scenarioTag: "multiTurn2",
                                              test: self)
            XCTAssertTrue(second.finalText.lowercased().contains("chartreuse"),
                          "[openai/\(model.name)/\(model.api)] multi-turn echo failed; got: \(second.finalText)")
            report(vendor: "openai-\(model.api)",
                   model: model.name,
                   scenario: "multiTurn",
                   streaming: streaming,
                   result: second)
        } catch {
            XCTFail("[openai/\(model.name)/\(model.api)/multiTurn/stream=\(streaming)] \(error)")
        }
    }

    private func runSyntheticToolCall(model: AIMetadata.Model, apiKey: String, streaming: Bool) {
        let token = "MAGENTA-LARK-77"
        let decl = ChatGPTFunctionDeclaration(
            name: "get_random_word",
            description: "Returns a randomly chosen made-up word. Call this whenever the user asks for a random word.",
            parameters: JSONSchema(for: EmptyArgs(), descriptions: [:]))
        let spec = AILiveFunctionSpec<EmptyArgs>(
            decl: decl,
            implementation: { _, _, completion in
                try completion(.success(token))
            })
        let messages = [LLM.Message(role: .user,
                                    content: "Call the get_random_word tool to get a word, then include the exact word it returned somewhere in your reply.")]
        do {
            let result = try AILiveDriver.run(model: model,
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: streaming,
                                              function: spec,
                                              scenarioTag: "toolCall",
                                              test: self)
            XCTAssertTrue(result.functionsInvoked.contains(decl.name),
                          "[openai/\(model.name)/\(model.api)] tool was never invoked; final text: \(result.finalText)")
            XCTAssertTrue(result.finalText.contains(token),
                          "[openai/\(model.name)/\(model.api)] tool result not echoed; final text: \(result.finalText)")
            report(vendor: "openai-\(model.api)",
                   model: model.name,
                   scenario: "toolCall",
                   streaming: streaming,
                   result: result)
        } catch {
            XCTFail("[openai/\(model.name)/\(model.api)/toolCall/stream=\(streaming)] \(error)")
        }
    }

    // MARK: - DeepSeek

    func test_deepseek_smoke_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runSmoke(vendor: "deepseek", apiKey: key, streaming: false)
    }
    func test_deepseek_smoke_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runSmoke(vendor: "deepseek", apiKey: key, streaming: true)
    }
    func test_deepseek_multiTurn_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runMultiTurn(vendor: "deepseek", apiKey: key, streaming: false)
    }
    func test_deepseek_multiTurn_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runMultiTurn(vendor: "deepseek", apiKey: key, streaming: true)
    }
    func test_deepseek_toolCall_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runToolCall(vendor: "deepseek", apiKey: key, streaming: false)
    }
    func test_deepseek_toolCall_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runToolCall(vendor: "deepseek", apiKey: key, streaming: true)
    }
    func test_deepseek_refusal_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runRefusal(vendor: "deepseek", apiKey: key, streaming: false)
    }
    func test_deepseek_refusal_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runRefusal(vendor: "deepseek", apiKey: key, streaming: true)
    }
}
