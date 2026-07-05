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

@MainActor
final class AILiveHarness: XCTestCase {
    private struct Keys {
        var openAI: String?
        var anthropic: String?
        var gemini: String?
        var deepSeek: String?
    }

    nonisolated static let configFileName = ".iterm2-ai-live.json"

    /// The per-worktree config path: `<repo root>/.iterm2-ai-live.json`.
    ///
    /// Derived from the compiled source location (`#filePath`) so each git
    /// worktree reads its OWN config - a leftover config in one checkout can no
    /// longer silently drive the live harness in another (the failure mode the
    /// old hardcoded `/tmp` path had). run_tests.expect, running from the repo,
    /// can delete this exact file defensively. The file is gitignored so live API
    /// keys can never be committed; `git status --ignored` still surfaces a
    /// leftover, and setUpWithError logs loudly whenever it's active.
    ///
    /// The repo dir is not subject to the periodic `$TMPDIR` reaping that drove
    /// the original `/tmp` choice. A worktree's `.git` is a file (not a dir), so
    /// test for existence, not directory-ness.
    nonisolated static func configFilePath() -> String {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                return dir.appendingPathComponent(configFileName).path
            }
            dir = dir.deletingLastPathComponent()
        }
        // Fallback (not inside a repo): beside the harness's parent directory.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(configFileName).path
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.loadConfig() != nil,
                          "Live AI harness is opt-in. Run tools/run_ai_live.sh.")
        // Loud: this hits real vendor APIs and spends money. If you see this in a
        // plain test run, a stale config leaked in - delete configFilePath().
        print("⚠️ Live AI harness ACTIVE (real vendor APIs). Config: \(Self.configFilePath())")
        // Install the cassette interceptor + recorder for the whole test,
        // covering both AILiveDriver-based tests and the chat-queue tests
        // that drive ChatBroker/ChatAgent directly. No-op when no cassette
        // mode is configured (shared is nil), leaving the pure-live path
        // unchanged.
        AICassetteSession.shared?.install()
    }

    override func tearDownWithError() throws {
        AICassetteSession.shared?.uninstall()
    }

    /// Last config we successfully read off disk. The config file lives in
    /// NSTemporaryDirectory() and we've seen Xcode test environments rotate
    /// that directory mid-run (the file is present for the first test method
    /// invocation in a -only-testing batch and gone for later ones, even
    /// without any explicit cleanup running). Caching the first successful
    /// read keeps later setUpWithError calls from spuriously XCTSkip'ing the
    /// whole live suite. Process-local; doesn't persist across runs.
    private static var cachedConfig: [String: String]?

    private static func loadConfig() -> [String: String]? {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath())),
           let any = try? JSONSerialization.jsonObject(with: data),
           let json = any as? [String: String] {
            cachedConfig = json
            return json
        }
        return cachedConfig
    }

    private static func loadKeys() -> Keys {
        guard let json = loadConfig() else { return Keys() }
        return Keys(openAI: json["OPENAI_API_KEY"],
                    anthropic: json["ANTHROPIC_API_KEY"],
                    gemini: json["GEMINI_API_KEY"],
                    deepSeek: json["DEEPSEEK_API_KEY"])
    }

    // Models that AIMetadata still lists but that a freshly-minted vendor
    // API key cannot reach. Capture attempts return 404 ("no longer
    // available to new users", or "no longer available" once Google fully
    // retires a preview model) or 429 RESOURCE_EXHAUSTED on the first
    // call, so exercising them on a default sweep is pure noise. An
    // explicit ITERM2_AI_LIVE_<VENDOR>_MODELS override still lets you
    // target them deliberately if a grandfathered key works.
    // Models in this set must be marked fixtureExempt in ai-models.json;
    // AIMetadataFixtureCoverageTest asserts they agree.
    static let unreachableForNewKeys: Set<String> = [
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        // Retired by Google: returns 404 "no longer available" for all keys.
        "gemini-3-pro-preview",
    ]

    // Models that block the refusal-scenario prompt at the API layer instead
    // of returning a refusal response, so no refusal fixture can be captured
    // or parsed. gpt-5.5-pro routes the phishing prompt through OpenAI's
    // cyber_policy pre-filter and 400s ("Trusted Access for Cyber program"),
    // so there's nothing to parse. AIMetadataFixtureCoverageTest skips these
    // the same way it skips unreachableForNewKeys.
    static let refusalBlockedAtHTTP: Set<String> = [
        "gpt-5.5-pro",
    ]

    private static func models(forVendor vendor: String) -> [String] {
        if let raw = loadConfig()?["\(vendor.uppercased())_MODELS"], !raw.isEmpty {
            return splitModels(raw)
        }
        // Default: every model registered for this vendor in AIMetadata,
        // minus the ones a fresh API key can't reach.
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
            .filter { !Self.unreachableForNewKeys.contains($0) }
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

    private func metadataModel(_ name: String) throws -> AIMetadata.Model {
        guard let model = AIMetadata.instance.models.first(where: { $0.name == name }) else {
            throw XCTSkip("\(name) not in AIMetadata; skipping.")
        }
        return model
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

    func throttle(forVendor vendor: String) {
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

    /// Tiny PNG with the digit "42" rendered onto a white background, used by
    /// the imageDescribe scenario: vision-capable models OCR the digits, so we
    /// can assert the response contains "42" without depending on subjective
    /// image-describing. Loaded from the committed static fixture rather than
    /// rendered per run: NSImage.lockFocus encodes at the host's screen scale,
    /// so a runtime bitmap differs between a Retina dev machine and a headless
    /// CI runner, which breaks cassette matching. Regenerate with
    /// AILiveAttachmentFixtures.regenerateStaticProbeFixtures() (writes
    /// number.png via the same renderer).
    private static let imagePngBytes: Data = {
        (try? loadBinaryFixture("number.png")) ?? Data()
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

    // Load a committed binary fixture from the project's AttachmentFixtures
    // directory. Used by the media-probe tests, which carry a deterministic
    // probe word ("pinecone") spoken/shown in the media so we can assert the
    // model actually parsed it.
    private static func loadBinaryFixture(_ basename: String) throws -> Data {
        guard let root = loadConfig()?["PROJECT_ROOT"], !root.isEmpty else {
            throw AILiveError.providerFailure("PROJECT_ROOT missing from live config")
        }
        let path = (root as NSString).appendingPathComponent("ModernTests")
            + "/Resources/AttachmentFixtures/\(basename)"
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // Send a binary media fixture (audio or video) and assert the model
    // surfaces the deterministic probe word. The 96-cell matrix can't verify
    // these positively: its audio/video fixtures lack a deterministic probe,
    // and the OpenAI lanes use non-audio models that reject input_audio at the
    // schema layer. This is the only place proving the inline media path
    // round-trips end-to-end on a capable model.
    private func runMediaProbe(vendorLabel: String,
                               model: AIMetadata.Model,
                               apiKey: String,
                               fixtureBasename: String,
                               mimeType: String,
                               prompt: String,
                               scenarioTag: String) {
        let bytes: Data
        do {
            bytes = try Self.loadBinaryFixture(fixtureBasename)
        } catch {
            XCTFail("[\(vendorLabel)/\(model.name)/\(scenarioTag)] cannot load fixture \(fixtureBasename): \(error)")
            return
        }
        let attachment = LLM.Message.Attachment(
            inline: true,
            id: scenarioTag,
            type: .file(.init(name: fixtureBasename,
                              content: bytes,
                              mimeType: mimeType,
                              localPath: nil)))
        let messages = [LLM.Message(responseID: nil,
                                    role: .user,
                                    body: .multipart([
                                        .text(prompt),
                                        .attachment(attachment),
                                    ]))]
        do {
            let result = try AILiveDriver.run(model: model,
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: false,
                                              scenarioTag: scenarioTag,
                                              test: self)
            XCTAssertTrue(result.finalText.lowercased().contains("pinecone"),
                          "[\(vendorLabel)/\(model.name)/\(mimeType)] expected the probe 'pinecone'; got: \(result.finalText)")
            report(vendor: vendorLabel,
                   model: model.name,
                   scenario: "\(scenarioTag)/\(mimeType)",
                   streaming: false,
                   result: result)
        } catch {
            XCTFail("[\(vendorLabel)/\(model.name)/\(scenarioTag)/\(mimeType)] \(error)")
        }
    }

    private static let audioProbePrompt =
        "What is the magic word spoken in this audio? Reply with just the word."
    private static let videoProbePrompt =
        "What word is shown and spoken in this video? Reply with just the word."

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

    /// Parse the exact HTTP status code out of an error string like
    ///   "...HTTP request failed with status 400. ..."
    /// (or the AILiveError.providerFailure(...) wrapping thereof). Returns
    /// nil when no "status N" marker is present. Shared with the attachment
    /// matrix, which keys its accept/reject classification off the same code.
    static func httpStatusCode(inErrorText text: String) -> Int? {
        let marker = "status "
        guard let range = text.range(of: marker) else { return nil }
        var digits = ""
        for c in text[range.upperBound...] {
            if c.isNumber { digits.append(c) } else { break }
        }
        return Int(digits)
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
                // A refusal can arrive two ways. Most models refuse in-band:
                // HTTP 200 with the decline as the response body, handled
                // above. OpenAI's newest models (the gpt-5.5 family) instead
                // block this category at the API with an HTTP 400 ("flagged
                // for possible cybersecurity risk") before the model runs.
                // That 400 IS a valid refusal, so accept it. Key strictly on
                // the exact status code: only 400 counts. A 429 (rate limit),
                // 500, etc. are real failures, not refusals.
                if Self.httpStatusCode(inErrorText: "\(error)") == 400 {
                    print("[live] \(vendor)/\(model) refusal -> HTTP 400 "
                          + "policy block (valid refusal)")
                    continue
                }
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
    func test_openai_hostedCodeInterpreter() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runHostedCodeInterpreter(vendor: "openai", modelName: "gpt-4o-mini", apiKey: key)
    }
    func test_openai_imageDescribe() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runImageDescribe(vendor: "openai", modelName: "gpt-4o-mini", apiKey: key)
    }
    func test_openai_audioTranscribe_mp3() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runMediaProbe(vendorLabel: "openai",
                      model: Self.syntheticAudioModel,
                      apiKey: key,
                      fixtureBasename: "speech.mp3",
                      mimeType: "audio/mpeg",
                      prompt: Self.audioProbePrompt,
                      scenarioTag: "audioTranscribe")
    }
    func test_openai_audioTranscribe_wav() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runMediaProbe(vendorLabel: "openai",
                      model: Self.syntheticAudioModel,
                      apiKey: key,
                      fixtureBasename: "speech.wav",
                      mimeType: "audio/wav",
                      prompt: Self.audioProbePrompt,
                      scenarioTag: "audioTranscribe")
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

    /// Verify Anthropic prompt caching engages end-to-end against the
    /// real server. Issue two back-to-back requests with the same
    /// system prompt (large enough to exceed Anthropic's minimum
    /// cacheable size: Haiku is ≥2048 tokens), assert the first
    /// response shows cache_creation_input_tokens > 0, and the second
    /// reads the shared prefix back from cache.
    ///
    /// We attach two kinds of marker offline: a stable one on the system
    /// block (and last tool), and a ROLLING one on the last message of
    /// every request. The second call here changes only its last user
    /// message, so the shared system prefix is a cache_read while the
    /// new last message is a small fresh cache_creation (the rolling
    /// breakpoint, which the *next* turn would read). So we do NOT
    /// expect cache_creation back to zero on call 2; we expect the
    /// prefix read to dominate the small tail write.
    ///
    /// This is the only place where we can actually confirm the cache
    /// markers we attach offline are accepted by the server and counted
    /// toward the cached segment. Offline unit tests pin the wire shape
    /// and byte determinism; this pins the contract with the server.
    func test_anthropic_promptCaching_cacheReadAfterCacheCreation() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        let model = "claude-haiku-4-5"

        // Build a system prompt comfortably above Anthropic's minimum
        // cacheable size. Haiku's minimum is 2048 tokens (Sonnet/Opus
        // are 1024, but we test on Haiku for cost). Aim for ~4500
        // tokens to leave plenty of headroom; the marker is silently
        // ignored below threshold and the test would falsely fail.
        // Padded so the same string flies both times (cache key is
        // byte-exact); a per-test UUID guarantees we're not picking up
        // some other test's residual cache entry in the 5-minute
        // window. Plain English so it tokenizes predictably.
        let nonce = UUID().uuidString
        let padding = String(
            repeating: "This is throwaway filler text only here to push the system prompt over Anthropic's minimum cacheable size for Claude Haiku (~2048 tokens), so the cache_control marker actually engages on the server side. ",
            count: 96)
        let systemText = "Test fixture \(nonce). \(padding) End fixture."

        let firstUser = LLM.Message(
            role: .user,
            content: "Reply with the single word OK.")
        let firstMessages: [LLM.Message] = [
            LLM.Message(role: .system, content: systemText),
            firstUser,
        ]

        throttle(forVendor: "anthropic")
        let first = try AILiveDriver.run(modelName: model,
                                         apiKey: key,
                                         messages: firstMessages,
                                         streaming: false,
                                         scenarioTag: "promptCache_create",
                                         test: self)
        XCTAssertFalse(first.finalText.isEmpty,
                       "[anthropic/promptCache] empty response on first call")
        // Sanity: confirm the cache_control marker actually rode on
        // the wire. If this fails the bug is in the request builder
        // (offline tests should catch it too); if it passes but the
        // usage assertions below fail, the bug is "server didn't
        // engage" — usually a system-prompt size below the model's
        // minimum cacheable threshold.
        let firstBody = first.capturedRequestBodies.first ?? ""
        XCTAssertTrue(firstBody.contains("\"cache_control\""),
                      "[anthropic/promptCache] first request body missing "
                      + "cache_control marker; serializer regressed")
        let firstUsage = try parseUsage(from: first.capturedResponseBodies.first ?? "",
                                        label: "first call")
        XCTAssertGreaterThan(firstUsage.cacheCreation, 0,
                             "[anthropic/promptCache] first call did not register "
                             + "cache_creation_input_tokens; the cache_control marker "
                             + "was not accepted. usage=\(firstUsage)")
        XCTAssertEqual(firstUsage.cacheRead, 0,
                       "[anthropic/promptCache] first call should not have read from "
                       + "cache (unique nonce). usage=\(firstUsage)")

        // Same system, same nonce → cache key matches. Change only the
        // last user message to force a fresh request (different bytes
        // after the cacheable prefix).
        let secondMessages: [LLM.Message] = [
            LLM.Message(role: .system, content: systemText),
            LLM.Message(role: .user, content: "Reply with the single word HELLO."),
        ]
        throttle(forVendor: "anthropic")
        let second = try AILiveDriver.run(modelName: model,
                                          apiKey: key,
                                          messages: secondMessages,
                                          streaming: false,
                                          scenarioTag: "promptCache_read",
                                          test: self)
        XCTAssertFalse(second.finalText.isEmpty,
                       "[anthropic/promptCache] empty response on second call")
        let secondUsage = try parseUsage(from: second.capturedResponseBodies.first ?? "",
                                         label: "second call")
        XCTAssertGreaterThan(secondUsage.cacheRead, 0,
                             "[anthropic/promptCache] second call did not read from "
                             + "cache; markers did not actually cache the prefix. "
                             + "usage=\(secondUsage)")
        // The shared system prefix is read from cache; only the changed
        // last user message (the rolling breakpoint) is re-created, and
        // that tail is tiny next to the cached prefix. If the prefix
        // cache regressed we'd instead see a large cache_creation and a
        // small/zero cache_read, so require the read to dominate.
        XCTAssertGreaterThan(secondUsage.cacheRead, secondUsage.cacheCreation,
                             "[anthropic/promptCache] second call re-created more than it "
                             + "read; the shared prefix was not reused. usage=\(secondUsage)")
    }

    private struct AnthropicUsageSummary: CustomStringConvertible {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreation: Int
        let cacheRead: Int
        var description: String {
            "input=\(inputTokens) output=\(outputTokens) "
                + "cache_creation=\(cacheCreation) cache_read=\(cacheRead)"
        }
    }

    /// Pull the usage block out of a (non-streaming) Anthropic
    /// response body. Throws an XCT-style failure on the test if the
    /// shape isn't what we expect rather than silently treating
    /// missing fields as zero — a missing field is almost certainly a
    /// vendor API change worth surfacing.
    private func parseUsage(from body: String, label: String) throws -> AnthropicUsageSummary {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = obj["usage"] as? [String: Any] else {
            XCTFail("[anthropic/promptCache/\(label)] response body missing usage block; body=\(body.prefix(500))")
            throw AILiveError.providerFailure("response missing usage block on \(label)")
        }
        return AnthropicUsageSummary(
            inputTokens: (usage["input_tokens"] as? Int) ?? 0,
            outputTokens: (usage["output_tokens"] as? Int) ?? 0,
            cacheCreation: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
            cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0)
    }

    // Pins an Anthropic 400 reproduced in production by iTerm2's Cockpit
    // orchestrator. AIConversation must not let a tool_use / tool_result pair
    // get split by an intervening user-role message on the wire. The cockpit
    // surfaced this naturally because its async watcher fast-path can publish
    // a user-text status_update message BEFORE the .remoteCommandResponse for
    // a register_watch tool call lands in the chat DB. Persistence ends up
    // recording:
    //
    //     assistant(tool_use register_watch, id=X)
    //     user(text "<status_update reason=stateReached>...")
    //     user(tool_result for X)
    //
    // The wire dump captured against a real failing request (Console.app log
    // line containing "RESPONSE-ERROR: HTTP request failed with status 400")
    // shows exactly this ordering for the failing tool_use id. Anthropic's
    // adjacency rule sees the message immediately after the tool_use is a
    // plain-text user message (not a tool_result for that tool_use_id) and
    // 400s with:
    //
    //   "messages.N: tool_use ids were found without tool_result blocks
    //    immediately after: toolu_..."
    //
    // The upstream FunctionCallID wrapper fix (92c2c3f9b) is unrelated; both
    // halves of the pair carry the correct id. What's broken is message
    // ORDERING in AIConversation/AnthropicRequestBuilder's output. This test
    // pins that AIConversation handles the ordering itself — callers that
    // hand it a tool_use / tool_result pair with a stray user message in
    // between should still produce a wire request Anthropic accepts. Fix lives
    // in AIConversation (or AnthropicRequestBuilder.convertMessages): bring
    // the matching tool_result up to be immediately after the tool_use,
    // pushing the intervening user-text to AFTER the tool_result.
    //
    // Constraint: do NOT push this fix down to the caller (the cockpit). The
    // cockpit's persistence ordering may be racy, but it should be impossible
    // for any caller to construct an AIConversation.messages layout that
    // produces this 400. Make the conversation layer robust.
    func test_anthropic_userMessageBetweenToolUseAndToolResult_doesNotProduce400() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")

        let toolName = "register_watch"
        let decl = ChatGPTFunctionDeclaration(
            name: toolName,
            description: "Register an async watcher for a session reaching a state. Returns immediately.",
            parameters: JSONSchema(for: EmptyArgs(), descriptions: [:]))
        let spec = AILiveFunctionSpec<EmptyArgs>(
            decl: decl,
            implementation: { _, _, completion in
                try completion(.success("{\"watcherRegistered\":{}}"))
            })

        // ID and content mirror what the production cockpit emitted in the
        // failing wire body: a fast-path watcher fire whose status_update was
        // persisted between the .remoteCommandRequest and .remoteCommandResponse
        // for the same register_watch tool call.
        let toolID = "toolu_test_misorder_register_watch"
        let statusUpdateText = """
        <status_update reason="stateReached" watcher_id="2B27BE04-AB12-45A1-ABCE-7C887CCA5758" at="2026-05-12T23:40:12Z">
        Workgroup: Claude Code
        Role: Chat
        Reached state: idle
        Detail: Chat in Claude Code was already in state 'idle' at watch registration.
        </status_update>
        """

        let messages: [LLM.Message] = [
            LLM.Message(role: .user,
                        content: "Have the main agent fix the race condition."),
            // Assistant emits the tool_use.
            LLM.Message(responseID: nil,
                        role: .assistant,
                        body: .functionCall(
                            LLM.FunctionCall(
                                name: toolName,
                                arguments: "{\"target\":{\"role\":\"builtin.claudeCode.main\",\"workgroup_id\":\"wg-test\"},\"target_state\":\"idle\"}",
                                id: toolID),
                            id: .init(callID: toolID, itemID: toolID))),
            // The async watcher fire was persisted as a user-text message
            // BEFORE the tool_result for the same tool_use. This is the
            // ordering that triggered the production 400.
            LLM.Message(role: .user, content: statusUpdateText),
            // Tool_result for the register_watch tool_use above. Note the
            // matching tool_use_id (callID) — both halves agree on the id;
            // it's purely the adjacency that's broken.
            LLM.Message(responseID: nil,
                        role: .function,
                        body: .functionOutput(
                            name: toolName,
                            output: "{\"watcherRegistered\":{\"watcher_id\":\"2B27BE04-AB12-45A1-ABCE-7C887CCA5758\"}}",
                            id: .init(callID: toolID, itemID: toolID))),
            // New user follow-up that triggers the next request to Anthropic.
            LLM.Message(role: .user,
                        content: "Did the watch register successfully? Reply in one short sentence."),
        ]

        do {
            let result = try AILiveDriver.run(
                modelName: "claude-opus-4-6",
                apiKey: key,
                messages: messages,
                streaming: true,
                function: spec,
                scenarioTag: "userMessageBetweenToolUseAndToolResult",
                test: self)
            // Today this never runs: the driver surfaces the Anthropic 400 as
            // an AILiveError via the catch branch below. After the fix,
            // Anthropic accepts the layout (because AIConversation reordered
            // it to a valid one) and we get a non-empty reply.
            XCTAssertFalse(result.finalText.isEmpty,
                           "Anthropic returned empty text; expected a reply about the watch registration")
        } catch {
            XCTFail("[anthropic/userMessageBetweenToolUseAndToolResult] \(error) — AIConversation must guarantee tool_use is immediately followed by its matching tool_result on the wire, regardless of caller-supplied ordering. Fix at the conversation layer (AIConversation or AnthropicRequestBuilder.convertMessages), NOT at the caller.")
        }
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
    func test_gemini_audioTranscribe_mp3() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runMediaProbe(vendorLabel: "gemini",
                      model: try metadataModel("gemini-3-flash-preview"),
                      apiKey: key,
                      fixtureBasename: "speech.mp3",
                      mimeType: "audio/mpeg",
                      prompt: Self.audioProbePrompt,
                      scenarioTag: "audioTranscribe")
    }
    func test_gemini_audioTranscribe_wav() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runMediaProbe(vendorLabel: "gemini",
                      model: try metadataModel("gemini-3-flash-preview"),
                      apiKey: key,
                      fixtureBasename: "speech.wav",
                      mimeType: "audio/wav",
                      prompt: Self.audioProbePrompt,
                      scenarioTag: "audioTranscribe")
    }
    func test_gemini_videoDescribe() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runMediaProbe(vendorLabel: "gemini",
                      model: try metadataModel("gemini-3-flash-preview"),
                      apiKey: key,
                      fixtureBasename: "pinecone.mp4",
                      mimeType: "video/mp4",
                      prompt: Self.videoProbePrompt,
                      scenarioTag: "videoDescribe")
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

    // OpenAI audio input is chat-completions-only (the Responses API has no
    // audio input), and no audio model is in AIMetadata, so synthesize one
    // here to exercise the input_audio serialization against the real API.
    private static let syntheticAudioModel = AIMetadata.Model(
        name: "gpt-audio",
        contextWindowTokens: 128_000,
        maxResponseTokens: 16_384,
        url: "https://api.openai.com/v1/chat/completions",
        api: .chatCompletions,
        features: [.streaming],
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

    // MARK: - DeepSeek thinking + tool call (issue 12858 / 12707)
    //
    // Validates that DeepSeek v4 multi-turn tool calls succeed when thinking
    // mode is enabled. DeepSeek's API requires assistant-turn reasoning_content
    // to be echoed back on every subsequent request when tool calls are
    // involved, or it returns 400. The parser + request builder round-trip
    // this via LLM.Message.reasoningContent.
    //
    // Until the toolbar toggle gates DeepSeek thinking (a separate metadata
    // flip), this test uses a synthetic AIMetadata.Model with
    // .configurableThinking listed so AITermController propagates the flag.

    private static func deepseekV4ThinkingModel(named name: String) -> AIMetadata.Model {
        return AIMetadata.Model(
            name: name,
            contextWindowTokens: 1_000_000,
            maxResponseTokens: 384_000,
            url: "https://api.deepseek.com/chat/completions",
            api: .deepSeek,
            features: [.functionCalling, .streaming, .configurableThinking],
            vendor: .deepSeek)
    }

    private func runDeepSeekThinkingToolCall(modelName: String,
                                             apiKey: String,
                                             streaming: Bool) {
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
        throttle(forVendor: "deepseek")
        do {
            let result = try AILiveDriver.run(model: Self.deepseekV4ThinkingModel(named: modelName),
                                              apiKey: apiKey,
                                              messages: messages,
                                              streaming: streaming,
                                              thinking: true,
                                              function: spec,
                                              scenarioTag: "thinkingToolCall",
                                              test: self)
            XCTAssertTrue(result.functionsInvoked.contains(decl.name),
                          "[deepseek/\(modelName)] tool was never invoked; final text: \(result.finalText)")
            XCTAssertTrue(result.finalText.contains(token),
                          "[deepseek/\(modelName)] tool result not echoed; final text: \(result.finalText)")
            report(vendor: "deepseek-thinking",
                   model: modelName,
                   scenario: "thinkingToolCall",
                   streaming: streaming,
                   result: result)
        } catch {
            XCTFail("[deepseek/\(modelName)/thinkingToolCall/stream=\(streaming)] \(error)")
        }
    }

    func test_deepseek_thinking_toolCall_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runDeepSeekThinkingToolCall(modelName: "deepseek-v4-flash",
                                    apiKey: key,
                                    streaming: false)
    }

    func test_deepseek_thinking_toolCall_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runDeepSeekThinkingToolCall(modelName: "deepseek-v4-flash",
                                    apiKey: key,
                                    streaming: true)
    }

    // Regression anchor for the non-streaming reasoning drop: AITermController
    // must deliver the reasoning scalar to its delegate so persistence layers
    // (AIConversation, ChatAgent) can attach it to the assistant Message they
    // build. Before the fix, parseNonStreamingResponse handed only the text
    // body to offerChoice and the reasoning was lost on the floor; the next
    // user turn went out with no reasoning_content and DeepSeek 400'd.
    func test_deepseek_thinking_nonStreaming_deliversReasoningToDelegate() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        let prompt = "Think briefly about why ice floats on water and reply with one short sentence."
        let messages = [LLM.Message(role: .user, content: prompt)]
        throttle(forVendor: "deepseek")
        do {
            let result = try AILiveDriver.run(
                model: Self.deepseekV4ThinkingModel(named: "deepseek-v4-flash"),
                apiKey: key,
                messages: messages,
                streaming: false,
                thinking: true,
                scenarioTag: "nonStreamingDelivers",
                test: self)
            XCTAssertFalse(result.finalText.isEmpty,
                           "empty assistant text")
            let delivered = result.deliveredReasoning ?? ""
            XCTAssertFalse(delivered.isEmpty,
                           "non-streaming reasoning was not delivered via didReceiveReasoning; finalText=\(result.finalText)")
        } catch {
            XCTFail("[deepseek/nonStreamingDelivers] \(error)")
        }
    }

    // Drives two non-streaming, non-tool-call conversations in a row through
    // AIConversation. The first turn must populate conversation.messages.last
    // with reasoningContent — without that, the second turn round-trips no
    // reasoning_content and DeepSeek returns 400. This is the exact regression
    // the user pointed out is missing from the rest of the suite (the other
    // thinking tests go through AILiveDriver directly, which bypasses the
    // AIConversation accumulator entirely).
    func test_deepseek_thinking_nonStreaming_plainText_aiConversation_multiTurn() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        let provider = AILiveStaticRegistrationProvider(apiKey: key)
        // Production model entry — Phase 4 added .configurableThinking to it,
        // so AITermController.shouldThink propagation flows.
        let modelName = "deepseek-v4-flash"

        // Verify the wire request actually used the test's loaded key, not
        // whatever AITermControllerRegistrationHelper.instance pulled from
        // the keychain singleton. AIConversation.init eagerly seeds its
        // controller from the singleton and consults the registrationProvider
        // only as a fallback — so on a dev machine where DeepSeek is already
        // configured, the static provider above might never be touched. Hook
        // iTermAIClient.liveObserver to capture Authorization headers and
        // assert at end-of-test that every captured request matched
        // "Bearer <test key>". Without this guard the test could pass against
        // the wrong account and the divergence would be invisible.
        var capturedAuthorizationHeaders: [String] = []
        let priorObserver = iTermAIClient.liveObserver
        iTermAIClient.liveObserver = { capture in
            capturedAuthorizationHeaders.append(
                capture.request.headers["Authorization"]
                ?? capture.request.headers["authorization"]
                ?? "")
            priorObserver?(capture)
        }
        defer { iTermAIClient.liveObserver = priorObserver }
        let expectedAuthorization = "Bearer \(key)"

        var conv = AIConversation(registrationProvider: provider)
        conv.model = modelName
        conv.shouldThink = true
        conv.messages = [LLM.Message(role: .user,
                                     content: "Briefly explain why the sky is blue. Reply in one short sentence.")]

        let turn1Exp = expectation(description: "non-streaming AIConversation turn 1")
        var turn1Result: Result<AIConversation, Error>?
        conv.complete { result in
            turn1Result = result
            turn1Exp.fulfill()
        }
        wait(for: [turn1Exp], timeout: 60)
        guard case .success(var updated) = turn1Result else {
            XCTFail("turn 1 failed: \(String(describing: turn1Result))")
            return
        }
        // The bug: this assertion fails before the fix because AIConversation
        // never sets reasoningContent on the assistant Message it appends.
        XCTAssertNotNil(updated.messages.last?.reasoningContent,
                        "turn 1's persisted assistant Message must carry reasoningContent for round-trip")
        XCTAssertFalse(updated.messages.last?.reasoningContent?.isEmpty ?? true,
                       "reasoningContent must be non-empty")

        // Now drive turn 2 with the same conversation. Without the fix, the
        // assistant message has no reasoningContent and DeepSeek returns 400.
        updated.model = modelName
        updated.shouldThink = true
        updated.messages.append(LLM.Message(role: .user,
                                            content: "Was that explanation about Rayleigh scattering? Answer yes or no."))
        let turn2Exp = expectation(description: "non-streaming AIConversation turn 2")
        var turn2Result: Result<AIConversation, Error>?
        updated.complete { result in
            turn2Result = result
            turn2Exp.fulfill()
        }
        wait(for: [turn2Exp], timeout: 60)
        switch turn2Result {
        case .success(let final):
            XCTAssertFalse(final.messages.last?.body.content.isEmpty ?? true,
                           "turn 2 produced empty response")
        case .failure(let error):
            XCTFail("turn 2 failed (expected success after reasoning round-trip): \(error)")
        case .none:
            XCTFail("turn 2 completion never fired")
        }
        XCTAssertFalse(capturedAuthorizationHeaders.isEmpty,
                       "no outbound requests were observed; was iTermAIClient.liveObserver hooked?")
        for (i, auth) in capturedAuthorizationHeaders.enumerated() {
            XCTAssertEqual(auth, expectedAuthorization,
                           "request \(i) used the wrong API key — test would have passed against a stale singleton-resolved key from the keychain rather than the loadKeys() value")
        }
    }

    // Phase 4 anchor: when the user sets the toolbar thinking toggle, the
    // request to DeepSeek must go out with `thinking.type: "enabled"`. The
    // .configurableThinking feature flag on the production model is what
    // unlocks the propagation (AITerm.swift:439 gates shouldThink on it). Until
    // that flag is added in AIMetadata.swift, the user's preference is dropped
    // silently and the wire body has thinking.type: "disabled".
    func test_deepseek_thinking_userToggle_propagates() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        // Use the production model from AIMetadata — NOT the synthetic
        // .configurableThinking override the other deepseek thinking tests
        // use. The whole point of this test is that the production metadata
        // entry advertises .configurableThinking.
        let prompt = "Reply with exactly the single word: PINEAPPLE"
        let messages = [LLM.Message(role: .user, content: prompt)]
        throttle(forVendor: "deepseek")
        do {
            let result = try AILiveDriver.run(
                modelName: "deepseek-v4-flash",
                apiKey: key,
                messages: messages,
                streaming: false,
                thinking: true,
                scenarioTag: "userToggle",
                test: self)
            XCTAssertFalse(result.capturedRequestBodies.isEmpty,
                           "no captured request bodies")
            let body = result.capturedRequestBodies[0]
            // Parse the body as JSON and assert on thinking.type directly.
            // Substring matching against the raw string is fragile — any
            // future wire field whose value is the literal "enabled" or
            // "disabled" (or a user prompt that contains those words) would
            // make the test flip for the wrong reason.
            guard let data = body.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                XCTFail("captured request body wasn't valid JSON: \(body)")
                return
            }
            guard let thinking = json["thinking"] as? [String: Any] else {
                XCTFail("request body missing thinking field; body=\(body)")
                return
            }
            XCTAssertEqual(thinking["type"] as? String, "enabled",
                           "user toggle did not propagate to thinking.type=enabled; thinking=\(thinking)")
        } catch {
            XCTFail("[deepseek/userToggle] \(error)")
        }
    }

    // Symmetric counterpart: when the user hasn't enabled thinking
    // (shouldThink is nil — the default after the metadata flag was added),
    // the request must go out with thinking.type=disabled. Without this
    // assertion, a regression that always sends "enabled" regardless of the
    // toggle would pass the userToggle_propagates test but ship surprise
    // latency/cost to every DeepSeek v4 user who didn't opt in.
    func test_deepseek_thinking_userToggleOff_emitsDisabled() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        let prompt = "Reply with exactly the single word: BANANA"
        let messages = [LLM.Message(role: .user, content: prompt)]
        throttle(forVendor: "deepseek")
        do {
            let result = try AILiveDriver.run(
                modelName: "deepseek-v4-flash",
                apiKey: key,
                messages: messages,
                streaming: false,
                // thinking: nil means "no recorded user preference"; per the
                // policy at AITerm.swift gating + DeepSeek.swift builder
                // default, that maps to thinking.type=disabled on the wire.
                thinking: nil,
                scenarioTag: "userToggleOff",
                test: self)
            XCTAssertFalse(result.capturedRequestBodies.isEmpty,
                           "no captured request bodies")
            let body = result.capturedRequestBodies[0]
            guard let data = body.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                XCTFail("captured request body wasn't valid JSON: \(body)")
                return
            }
            guard let thinking = json["thinking"] as? [String: Any] else {
                XCTFail("request body missing thinking field; body=\(body)")
                return
            }
            XCTAssertEqual(thinking["type"] as? String, "disabled",
                           "unset toggle must produce thinking.type=disabled; thinking=\(thinking)")
        } catch {
            XCTFail("[deepseek/userToggleOff] \(error)")
        }
    }

    // Phase 2 anchor: an assistant turn whose reasoningContent is set must be
    // re-emittable on the wire so DeepSeek accepts the follow-up. Without the
    // request-builder change in Phase 2 the second turn 400s with
    // "The reasoning_content in the thinking mode must be passed back to the API."
    func test_deepseek_thinking_assistantTurn_roundTrips() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        let model = Self.deepseekV4ThinkingModel(named: "deepseek-v4-flash")

        let turn1 = [LLM.Message(role: .user,
                                 content: "Briefly explain why ice floats on water. Reply in one short sentence.")]
        throttle(forVendor: "deepseek")
        let r1: AILiveRunResult
        do {
            r1 = try AILiveDriver.run(
                model: model,
                apiKey: key,
                messages: turn1,
                streaming: true,
                thinking: true,
                scenarioTag: "thinkingRoundTrip1",
                test: self)
        } catch {
            XCTFail("[deepseek/thinkingRoundTrip] turn 1 failed: \(error)")
            return
        }
        XCTAssertFalse(r1.finalText.isEmpty, "turn 1 returned empty text")
        XCTAssertFalse(r1.reasoningText.isEmpty,
                       "turn 1 must surface reasoning so turn 2 has something to round-trip")

        var assistant = LLM.Message(role: .assistant, content: r1.finalText)
        assistant.reasoningContent = r1.reasoningText
        let turn2 = turn1 + [
            assistant,
            LLM.Message(role: .user,
                        content: "Was that explanation primarily about ice's density compared to liquid water? Reply yes or no.")
        ]
        throttle(forVendor: "deepseek")
        do {
            let r2 = try AILiveDriver.run(
                model: model,
                apiKey: key,
                messages: turn2,
                streaming: true,
                thinking: true,
                scenarioTag: "thinkingRoundTrip2",
                test: self)
            XCTAssertFalse(r2.finalText.isEmpty,
                           "turn 2 returned empty text; round-trip failed")
            report(vendor: "deepseek-thinking",
                   model: "deepseek-v4-flash",
                   scenario: "thinkingRoundTrip2",
                   streaming: true,
                   result: r2)
        } catch {
            XCTFail("[deepseek/thinkingRoundTrip] turn 2 failed: \(error)")
        }
    }

    // Phase 1 anchor: a streaming smoke call with thinking enabled must surface
    // reasoning content to the driver as a `.statusUpdate(.reasoningSummaryUpdate)`
    // attachment so iTerm2 can show it to the user. DeepSeek streams reasoning
    // via `delta.reasoning_content`; until the parser change lands the driver's
    // attachments array will be empty and the assertion fails. The test pairs
    // with offline parser coverage in AIParserCombiningTests.
    func test_deepseek_thinking_smoke_captures_reasoning() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        let prompt = "Think briefly about why the sky appears blue, then reply with a one-sentence answer."
        let messages = [LLM.Message(role: .user, content: prompt)]
        throttle(forVendor: "deepseek")
        do {
            let result = try AILiveDriver.run(
                model: Self.deepseekV4ThinkingModel(named: "deepseek-v4-flash"),
                apiKey: key,
                messages: messages,
                streaming: true,
                thinking: true,
                scenarioTag: "thinkingSmoke",
                test: self)
            XCTAssertFalse(result.finalText.isEmpty,
                           "[deepseek/deepseek-v4-flash] empty response")
            XCTAssertFalse(result.reasoningText.isEmpty,
                           "[deepseek/deepseek-v4-flash] no reasoning content captured; attachments=\(result.attachments)")
            report(vendor: "deepseek-thinking",
                   model: "deepseek-v4-flash",
                   scenario: "thinkingSmoke",
                   streaming: true,
                   result: result)
        } catch {
            XCTFail("[deepseek/deepseek-v4-flash/thinkingSmoke] \(error)")
        }
    }

    // Empirical check for the corner case the offline test
    // testDeepSeekRequestBuilder_reasoningOnlyAssistant_serializesEmptyContent
    // locks the wire shape for: a persisted assistant turn whose body is
    // empty (the post-harvest state of a streamed reasoning-only response)
    // but which still carries reasoning_content. The request builder emits
    // {"role":"assistant","content":"","reasoning_content":"..."} for that
    // turn. This test sends exactly that shape to DeepSeek's live API and
    // confirms it's accepted.
    //
    // First run (2026-05-12): DeepSeek accepted the shape and replied with
    // non-empty text in ~2s. The policy in DeepSeek.swift relies on that
    // empirical result. If this test ever starts failing, DeepSeek has
    // tightened its schema validation — the policy needs to flip to
    // `return nil` AND a higher layer must merge surrounding user turns to
    // avoid breaking alternation.
    func test_deepseek_thinking_reasoningOnlyAssistant_roundTrips() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        var assistant = LLM.Message(role: .assistant, body: .multipart([]))
        assistant.reasoningContent = "I considered the user's previous question and concluded ice floats on water because solid water is less dense than liquid water due to its open hydrogen-bonded crystal structure."
        let messages: [LLM.Message] = [
            LLM.Message(role: .user, content: "Briefly explain why ice floats on water. Reply in one short sentence."),
            assistant,
            LLM.Message(role: .user, content: "Was that explanation primarily about ice's density compared to liquid water? Reply yes or no."),
        ]
        throttle(forVendor: "deepseek")
        do {
            let result = try AILiveDriver.run(
                model: Self.deepseekV4ThinkingModel(named: "deepseek-v4-flash"),
                apiKey: key,
                messages: messages,
                streaming: false,
                thinking: true,
                scenarioTag: "reasoningOnlyRoundTrip",
                test: self)
            XCTAssertFalse(result.finalText.isEmpty,
                           "DeepSeek rejected the empty-content + reasoning_content assistant turn (or returned empty text); see captured request body. If this fails the offline policy needs to flip — see comment in DeepSeek.swift around the `content == nil && reasoning_content != nil` shim.")
            // Belt-and-suspenders: confirm the wire body actually carried the
            // shape we expect (content="" with reasoning_content alongside).
            // Without this, a future refactor could silently change the shape
            // and the test would still pass for the wrong reason.
            XCTAssertFalse(result.capturedRequestBodies.isEmpty,
                           "no request body captured")
            let body = result.capturedRequestBodies[0]
            guard let data = body.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let wireMessages = json["messages"] as? [[String: Any]] else {
                XCTFail("could not parse captured request body as JSON; got \(body)")
                return
            }
            XCTAssertEqual(wireMessages.count, 3,
                           "all three turns must survive on the wire to preserve alternation; got \(wireMessages)")
            XCTAssertEqual(wireMessages[1]["role"] as? String, "assistant")
            XCTAssertEqual(wireMessages[1]["content"] as? String, "",
                           "this test only exercises the empirical question for the content=\"\" shape; if the request builder no longer emits that, update or delete this test")
        } catch {
            XCTFail("[deepseek/reasoningOnlyRoundTrip] \(error) — DeepSeek may have rejected the empty-content + reasoning_content shape")
        }
    }

    // MARK: - Chat-reload (ChatAgent.load + AIChatToolCallRepair) round-trips
    //
    // These tests cover the prompt-rebuild path: a persisted [Message]
    // transcript (`remoteCommandRequest` / `remoteCommandResponse` etc.) is
    // replayed through `ChatAgent.aiMessagesForReloadingTranscript`, which
    // runs the same `MessageToPromptStateMachine.body(message:)` +
    // `AIChatToolCallRepair.repairingOrphanedToolResults` pipeline that
    // production uses on chat reload, then a new user message is appended
    // and sent to the real vendor. The point is to fly the rebuilt prompt
    // and catch any vendor rejection that the offline repair tests can't
    // see. Two hazards on every vendor:
    //   - "paired" pins the well-formed reload path: a transcript that
    //     contains a remoteCommandRequest + matching remoteCommandResponse
    //     must still round-trip after rebuilding. Regression here means
    //     the reload path itself broke.
    //   - "orphan" pins the auto-approved-command shape (response without
    //     request) that the repair is designed to heal. For Anthropic /
    //     OpenAI Responses / OpenAI chat-completions / DeepSeek the
    //     transcript carries a real call id (id-based vendors); for Gemini
    //     it carries nil ids on both halves — that is exactly what
    //     Gemini.swift's deserializer produces, and the repair must NOT
    //     drop the nil-id functionOutput, it must synthesize an adjacent
    //     nil-id functionCall so Gemini's adjacency-based pairing accepts
    //     the request.
    //
    // The seam `ChatAgent.aiMessagesForReloadingTranscript(...)` exists
    // because instantiating a real ChatAgent here would require a
    // ChatBroker, which requires ChatDatabase.instance — that would write
    // the user's actual chat DB during a test run. The seam mirrors
    // `load(messages:)` line-for-line; keep them in sync if either moves.

    private enum ChatReloadScenario: String {
        case paired
        case orphan
        // Like `paired`, but the persisted transcript also has a final assistant
        // text reply after the tool round-trip. On reload the tool round-trip
        // folds into a single assistant transcript message, so the rebuilt
        // prompt contains two consecutive assistant turns (folded transcript +
        // reply). Vendors that require strictly alternating roles (Gemini 400s;
        // Anthropic is stricter than chat-completions) exercise the coalescing
        // pass in Gemini.swift / CompletionsAnthropic.swift.
        case pairedWithReply
    }

    private enum ChatReloadIDStyle {
        /// Real ids baked into both the request and the response. The two
        /// id fields are distinct because vendors differ on what they accept:
        /// OpenAI Responses requires the item id (FunctionCallID.itemID) to
        /// begin with "fc_" and the call id (FunctionCallID.callID) to begin
        /// with "call_". Anthropic / OpenAI chat-completions / DeepSeek
        /// don't distinguish, so for them callID and itemID are equal.
        case real(callID: String, itemID: String)
        /// Both inner FunctionCall.id and wrapper FunctionCallID nil;
        /// matches Gemini.swift (and the legacy OpenAI function_call path)
        /// deserialized shape. Pairing is by adjacency, not id.
        case nilID
    }

    /// Build a synthetic [Message] transcript shaped like a persisted chat.
    /// The tool name maps to `execute_command` so it can use the existing
    /// `RemoteCommand.ExecuteCommand` content; everything else is metadata
    /// the vendor only sees indirectly via the rebuilt prompt.
    private func makeChatReloadTranscript(scenario: ChatReloadScenario,
                                          toolName: String,
                                          idStyle: ChatReloadIDStyle) -> [Message] {
        let chatID = "live-chat-reload"
        let userQuestion = Message(
            chatID: chatID,
            author: .user,
            content: .plainText("Please run the diagnostic command.", context: nil),
            sentDate: Date(),
            uniqueID: UUID())

        let (innerID, wrapperID): (String?, LLM.Message.FunctionCallID?) = {
            switch idStyle {
            case .real(let callID, let itemID):
                // FunctionCall.id mirrors the call id (what chat-completions
                // and DeepSeek serializers key tool_calls off, and what
                // Anthropic serializes as the tool_use block id). The wrapper
                // FunctionCallID separately carries the call_id / item id
                // distinction OpenAI Responses requires.
                return (callID, LLM.Message.FunctionCallID(callID: callID, itemID: itemID))
            case .nilID:
                return (nil, nil)
            }
        }()
        let argsJSON = "{\"command\":\"uname -a\"}"
        let llmCall = LLM.Message(
            role: .assistant,
            body: .functionCall(
                LLM.FunctionCall(name: toolName,
                                 arguments: argsJSON,
                                 id: innerID,
                                 thoughtSignature: nil),
                id: wrapperID))
        let remoteCommand = RemoteCommand(
            llmMessage: llmCall,
            content: .executeCommand(.init(command: "uname -a")))
        let request = Message(
            chatID: chatID,
            author: .agent,
            content: .remoteCommandRequest(.classic(remoteCommand), safe: nil),
            sentDate: Date(),
            uniqueID: UUID())
        let response = Message(
            chatID: chatID,
            author: .user,
            content: .remoteCommandResponse(
                .success("Darwin host 25.4.0 arm64"),
                UUID(),
                toolName,
                wrapperID),
            sentDate: Date(),
            uniqueID: UUID())

        let assistantReply = Message(
            chatID: chatID,
            author: .agent,
            content: .markdown("The diagnostic reports Darwin on arm64."),
            sentDate: Date(),
            uniqueID: UUID())

        switch scenario {
        case .paired:
            return [userQuestion, request, response]
        case .orphan:
            // Auto-approved shape: the request was squelched (ChatClient.swift
            // .always branch historically), so only the response survives.
            return [userQuestion, response]
        case .pairedWithReply:
            // The tool round-trip folds into one assistant transcript message,
            // and the trailing assistant reply is a second assistant turn, so
            // the rebuilt prompt has two consecutive assistant turns.
            return [userQuestion, request, response, assistantReply]
        }
    }

    /// Drive one chat-reload round-trip against `model`. The transcript is
    /// rebuilt via the seam (so we reach `AIChatToolCallRepair` exactly the
    /// way `ChatAgent.load(messages:)` would), then a new user message is
    /// appended and the resulting prompt flies to the vendor. The vendor
    /// reply must be non-empty (vendor accepted the rebuilt prompt). For the
    /// orphan scenario we additionally inspect the captured Anthropic wire
    /// body and assert the synthesized tool_use block actually lands before
    /// the tool_result — that's the wire-level check the offline test
    /// `testOrphanRepair_serializesAsAnthropicToolUse` makes, but here run
    /// against the body the live driver actually transmitted.
    @MainActor
    private func runChatReloadOnce(vendorTag: String,
                                   model: AIMetadata.Model,
                                   apiKey: String,
                                   streaming: Bool,
                                   scenario: ChatReloadScenario,
                                   idStyle: ChatReloadIDStyle) {
        let toolName = "execute_command"
        let decl = ChatGPTFunctionDeclaration(
            name: toolName,
            description: "Run a shell command (stub for chat-reload tests).",
            parameters: JSONSchema(for: RemoteCommand.ExecuteCommand(),
                                   descriptions: ["command": "The command to run."]))
        let spec = AILiveFunctionSpec<RemoteCommand.ExecuteCommand>(
            decl: decl,
            implementation: { _, _, completion in
                try completion(.success("{\"ok\":true}"))
            })

        let transcript = makeChatReloadTranscript(
            scenario: scenario, toolName: toolName, idStyle: idStyle)
        let rebuilt = ChatAgent.aiMessagesForReloadingTranscript(transcript)
        // New user message that forces the rebuilt prompt to actually fly.
        let followUp = LLM.Message(role: .user,
                                   content: "In one short sentence, summarize what you learned from the previous command output.")
        let messages = rebuilt + [followUp]

        do {
            let result = try AILiveDriver.run(
                model: model,
                apiKey: apiKey,
                messages: messages,
                streaming: streaming,
                function: spec,
                scenarioTag: "chatReload_\(scenario.rawValue)",
                test: self)
            XCTAssertFalse(result.finalText.isEmpty,
                           "[\(vendorTag)/\(model.name)/chatReload_\(scenario.rawValue)] empty response; the vendor likely rejected the rebuilt prompt")
            if scenario == .orphan, model.vendor == .anthropic, case .real(let callID, _) = idStyle {
                assertAnthropicWireBodyHasPairedToolUse(
                    capturedBodies: result.capturedRequestBodies,
                    toolID: callID,
                    vendorTag: vendorTag,
                    model: model.name)
            }
            report(vendor: vendorTag,
                   model: model.name,
                   scenario: "chatReload_\(scenario.rawValue)",
                   streaming: streaming,
                   result: result)
        } catch {
            XCTFail("[\(vendorTag)/\(model.name)/chatReload_\(scenario.rawValue)/stream=\(streaming)] \(error)")
        }
    }

    /// Iterate every reachable model for `vendor`, skipping non-tool-calling
    /// ones, and run one chat-reload round-trip per model.
    @MainActor
    private func runChatReload(vendor: String,
                               apiKey: String,
                               streaming: Bool,
                               scenario: ChatReloadScenario,
                               idStyle: ChatReloadIDStyle) {
        for name in Self.models(forVendor: vendor) {
            guard let resolved = AIMetadata.instance.models.first(where: { $0.name == name }) else {
                XCTFail("[\(vendor)/\(name)] not found in AIMetadata"); continue
            }
            guard resolved.features.contains(.functionCalling) else { continue }
            throttle(forVendor: vendor)
            runChatReloadOnce(vendorTag: vendor,
                              model: resolved,
                              apiKey: apiKey,
                              streaming: streaming,
                              scenario: scenario,
                              idStyle: idStyle)
        }
    }

    /// OpenAI's chat-completions path is exercised via a synthetic model
    /// (see `runSyntheticToolCall`), so the chat-reload runner takes the
    /// model explicitly instead of iterating AIMetadata.
    @MainActor
    private func runChatReloadSynthetic(model: AIMetadata.Model,
                                        apiKey: String,
                                        streaming: Bool,
                                        scenario: ChatReloadScenario,
                                        idStyle: ChatReloadIDStyle) {
        throttle(forVendor: "openai")
        runChatReloadOnce(vendorTag: "openai-\(model.api)",
                          model: model,
                          apiKey: apiKey,
                          streaming: streaming,
                          scenario: scenario,
                          idStyle: idStyle)
    }

    /// Wire-level guarantee for the Anthropic orphan path: the captured
    /// outbound body must contain a `tool_use` block whose id matches the
    /// `tool_result`'s `tool_use_id`, and the `tool_use` must come before
    /// the `tool_result`. Pins exactly the regression the original bug
    /// produced (orphan tool_result with no preceding tool_use).
    private func assertAnthropicWireBodyHasPairedToolUse(capturedBodies: [String],
                                                         toolID: String,
                                                         vendorTag: String,
                                                         model: String) {
        guard let first = capturedBodies.first,
              let data = first.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wireMessages = json["messages"] as? [[String: Any]] else {
            XCTFail("[\(vendorTag)/\(model)/chatReload_orphan] could not parse captured Anthropic body")
            return
        }
        var toolUseIndexByID = [String: Int]()
        var toolResultIndexByID = [String: Int]()
        var blockIndex = 0
        for message in wireMessages {
            guard let blocks = message["content"] as? [[String: Any]] else { continue }
            for block in blocks {
                defer { blockIndex += 1 }
                switch block["type"] as? String {
                case "tool_use":
                    if let id = block["id"] as? String { toolUseIndexByID[id] = blockIndex }
                case "tool_result":
                    if let id = block["tool_use_id"] as? String { toolResultIndexByID[id] = blockIndex }
                default: break
                }
            }
        }
        guard let resultIdx = toolResultIndexByID[toolID] else {
            XCTFail("[\(vendorTag)/\(model)/chatReload_orphan] no tool_result with id \(toolID) on the wire")
            return
        }
        guard let useIdx = toolUseIndexByID[toolID] else {
            XCTFail("[\(vendorTag)/\(model)/chatReload_orphan] no paired tool_use on the wire; this is the original 400 regression")
            return
        }
        XCTAssertLessThan(useIdx, resultIdx,
                          "[\(vendorTag)/\(model)/chatReload_orphan] tool_use must come before its tool_result")
    }

    // MARK: chat-reload — orphan negative control
    //
    // The positive chatReload_orphan test proves a real vendor ACCEPTS a
    // repaired orphan. On its own that doesn't prove the repair is what made
    // it work: maybe the vendor never rejected the orphan in the first place,
    // or our fixture isn't a real orphan. This negative control closes that
    // gap by sending the SAME orphan transcript WITHOUT the repair pass
    // (ChatAgent.transcriptMessagesBeforeRepair, exactly what production
    // transmitted before the fix) and asserting the vendor rejects it with
    // HTTP 400. If a vendor ever stops rejecting un-repaired orphans, this
    // fails loudly so we know the positive test has gone vacuous. Id-based
    // vendors only (Anthropic, OpenAI Responses); Gemini pairs by adjacency
    // and 400s for a different reason, so it's out of scope here.

    @MainActor
    private func runOrphanNegativeControlOnce(vendorTag: String,
                                              model: AIMetadata.Model,
                                              apiKey: String,
                                              idStyle: ChatReloadIDStyle) {
        let toolName = "execute_command"
        let decl = ChatGPTFunctionDeclaration(
            name: toolName,
            description: "Run a shell command (stub for chat-reload tests).",
            parameters: JSONSchema(for: RemoteCommand.ExecuteCommand(),
                                   descriptions: ["command": "The command to run."]))
        let spec = AILiveFunctionSpec<RemoteCommand.ExecuteCommand>(
            decl: decl,
            implementation: { _, _, completion in try completion(.success("{\"ok\":true}")) })

        let transcript = makeChatReloadTranscript(
            scenario: .orphan, toolName: toolName, idStyle: idStyle)
        // The un-repaired prompt: the orphan tool_result with no preceding
        // tool_use, identical to the positive path except the repair is
        // skipped. This isolates the repair as the only variable.
        let unrepaired = ChatAgent.transcriptMessagesBeforeRepair(transcript)
        let followUp = LLM.Message(
            role: .user,
            content: "In one short sentence, summarize what you learned from the previous command output.")
        let messages = unrepaired + [followUp]

        do {
            _ = try AILiveDriver.run(
                model: model,
                apiKey: apiKey,
                messages: messages,
                streaming: false,
                function: spec,
                scenarioTag: "chatReload_orphan_negativeControl",
                test: self)
            XCTFail("[\(vendorTag)/\(model.name)] vendor ACCEPTED an un-repaired orphan tool_result. Either the vendor stopped enforcing tool_use/tool_result pairing or the fixture is no longer a real orphan; the positive chatReload_orphan test no longer proves the repair is necessary.")
        } catch {
            let status = Self.httpStatusCode(inErrorText: "\(error)")
            XCTAssertEqual(status, 400,
                           "[\(vendorTag)/\(model.name)] expected the un-repaired orphan to be rejected with HTTP 400 (tool pairing), got: \(error)")
        }
    }

    /// One representative tool-calling model is enough: pairing is enforced at
    /// the vendor API layer, not per model.
    @MainActor
    private func runOrphanNegativeControl(vendor: String,
                                          apiKey: String,
                                          idStyle: ChatReloadIDStyle) {
        for name in Self.models(forVendor: vendor) {
            guard let resolved = AIMetadata.instance.models.first(where: { $0.name == name }),
                  resolved.features.contains(.functionCalling) else { continue }
            throttle(forVendor: vendor)
            runOrphanNegativeControlOnce(vendorTag: vendor,
                                         model: resolved,
                                         apiKey: apiKey,
                                         idStyle: idStyle)
            return
        }
    }

    func test_anthropic_chatReload_orphanNegativeControl_rejected() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runOrphanNegativeControl(vendor: "anthropic", apiKey: key,
                                 idStyle: .real(callID: "toolu_negctl",
                                                itemID: "toolu_negctl"))
    }

    func test_openai_chatReload_orphanNegativeControl_rejected() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runOrphanNegativeControl(vendor: "openai", apiKey: key,
                                 idStyle: .real(callID: "call_negctl",
                                                itemID: "fc_negctl"))
    }

    // MARK: chat-reload — Anthropic

    func test_anthropic_chatReload_paired_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runChatReload(vendor: "anthropic", apiKey: key, streaming: false,
                      scenario: .paired,
                      idStyle: .real(callID: "toolu_test_chat_reload_paired",
                                     itemID: "toolu_test_chat_reload_paired"))
    }
    func test_anthropic_chatReload_paired_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runChatReload(vendor: "anthropic", apiKey: key, streaming: true,
                      scenario: .paired,
                      idStyle: .real(callID: "toolu_test_chat_reload_paired",
                                     itemID: "toolu_test_chat_reload_paired"))
    }
    func test_anthropic_chatReload_orphan_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runChatReload(vendor: "anthropic", apiKey: key, streaming: false,
                      scenario: .orphan,
                      idStyle: .real(callID: "toolu_test_chat_reload_orphan",
                                     itemID: "toolu_test_chat_reload_orphan"))
    }
    func test_anthropic_chatReload_orphan_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runChatReload(vendor: "anthropic", apiKey: key, streaming: true,
                      scenario: .orphan,
                      idStyle: .real(callID: "toolu_test_chat_reload_orphan",
                                     itemID: "toolu_test_chat_reload_orphan"))
    }

    // MARK: chat-reload — Gemini (decisive: nil-id pairing)

    func test_gemini_chatReload_paired_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runChatReload(vendor: "gemini", apiKey: key, streaming: false,
                      scenario: .paired, idStyle: .nilID)
    }
    func test_gemini_chatReload_paired_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runChatReload(vendor: "gemini", apiKey: key, streaming: true,
                      scenario: .paired, idStyle: .nilID)
    }
    func test_gemini_chatReload_orphan_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runChatReload(vendor: "gemini", apiKey: key, streaming: false,
                      scenario: .orphan, idStyle: .nilID)
    }
    func test_gemini_chatReload_orphan_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runChatReload(vendor: "gemini", apiKey: key, streaming: true,
                      scenario: .orphan, idStyle: .nilID)
    }

    // MARK: chat-reload — consecutive assistant turns (coalescing)
    //
    // A reloaded chat whose tool round-trip is followed by an assistant text
    // reply folds into two consecutive assistant turns. Gemini 400s on
    // non-alternating `model` turns and Anthropic is strict too, so these pin
    // the coalescing pass end to end against the real APIs.

    func test_anthropic_chatReload_pairedWithReply_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runChatReload(vendor: "anthropic", apiKey: key, streaming: false,
                      scenario: .pairedWithReply,
                      idStyle: .real(callID: "toolu_test_chat_reload_reply",
                                     itemID: "toolu_test_chat_reload_reply"))
    }
    func test_anthropic_chatReload_pairedWithReply_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().anthropic, vendor: "anthropic")
        runChatReload(vendor: "anthropic", apiKey: key, streaming: true,
                      scenario: .pairedWithReply,
                      idStyle: .real(callID: "toolu_test_chat_reload_reply",
                                     itemID: "toolu_test_chat_reload_reply"))
    }
    func test_gemini_chatReload_pairedWithReply_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runChatReload(vendor: "gemini", apiKey: key, streaming: false,
                      scenario: .pairedWithReply, idStyle: .nilID)
    }
    func test_gemini_chatReload_pairedWithReply_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().gemini, vendor: "gemini")
        runChatReload(vendor: "gemini", apiKey: key, streaming: true,
                      scenario: .pairedWithReply, idStyle: .nilID)
    }

    // MARK: chat-reload — OpenAI Responses

    func test_openai_chatReload_paired_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReload(vendor: "openai", apiKey: key, streaming: false,
                      scenario: .paired,
                      idStyle: .real(callID: "call_test_chat_reload_paired",
                                     itemID: "fc_test_chat_reload_paired"))
    }
    func test_openai_chatReload_paired_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReload(vendor: "openai", apiKey: key, streaming: true,
                      scenario: .paired,
                      idStyle: .real(callID: "call_test_chat_reload_paired",
                                     itemID: "fc_test_chat_reload_paired"))
    }
    func test_openai_chatReload_orphan_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReload(vendor: "openai", apiKey: key, streaming: false,
                      scenario: .orphan,
                      idStyle: .real(callID: "call_test_chat_reload_orphan",
                                     itemID: "fc_test_chat_reload_orphan"))
    }
    func test_openai_chatReload_orphan_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReload(vendor: "openai", apiKey: key, streaming: true,
                      scenario: .orphan,
                      idStyle: .real(callID: "call_test_chat_reload_orphan",
                                     itemID: "fc_test_chat_reload_orphan"))
    }

    // MARK: chat-reload — OpenAI chat-completions (synthetic model)

    func test_openai_chatCompletions_chatReload_paired_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReloadSynthetic(model: Self.syntheticChatCompletionsModel,
                               apiKey: key, streaming: false,
                               scenario: .paired,
                               idStyle: .real(callID: "call_test_chat_reload_paired",
                                              itemID: "call_test_chat_reload_paired"))
    }
    func test_openai_chatCompletions_chatReload_paired_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReloadSynthetic(model: Self.syntheticChatCompletionsModel,
                               apiKey: key, streaming: true,
                               scenario: .paired,
                               idStyle: .real(callID: "call_test_chat_reload_paired",
                                              itemID: "call_test_chat_reload_paired"))
    }
    func test_openai_chatCompletions_chatReload_orphan_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReloadSynthetic(model: Self.syntheticChatCompletionsModel,
                               apiKey: key, streaming: false,
                               scenario: .orphan,
                               idStyle: .real(callID: "call_test_chat_reload_orphan",
                                              itemID: "call_test_chat_reload_orphan"))
    }
    func test_openai_chatCompletions_chatReload_orphan_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        runChatReloadSynthetic(model: Self.syntheticChatCompletionsModel,
                               apiKey: key, streaming: true,
                               scenario: .orphan,
                               idStyle: .real(callID: "call_test_chat_reload_orphan",
                                              itemID: "call_test_chat_reload_orphan"))
    }

    // MARK: chat-reload — DeepSeek

    func test_deepseek_chatReload_paired_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runChatReload(vendor: "deepseek", apiKey: key, streaming: false,
                      scenario: .paired,
                      idStyle: .real(callID: "call_test_chat_reload_paired",
                                     itemID: "call_test_chat_reload_paired"))
    }
    func test_deepseek_chatReload_paired_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runChatReload(vendor: "deepseek", apiKey: key, streaming: true,
                      scenario: .paired,
                      idStyle: .real(callID: "call_test_chat_reload_paired",
                                     itemID: "call_test_chat_reload_paired"))
    }
    func test_deepseek_chatReload_orphan_nonStreaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runChatReload(vendor: "deepseek", apiKey: key, streaming: false,
                      scenario: .orphan,
                      idStyle: .real(callID: "call_test_chat_reload_orphan",
                                     itemID: "call_test_chat_reload_orphan"))
    }
    func test_deepseek_chatReload_orphan_streaming() throws {
        let key = try keyOrSkip(Self.loadKeys().deepSeek, vendor: "deepseek")
        runChatReload(vendor: "deepseek", apiKey: key, streaming: true,
                      scenario: .orphan,
                      idStyle: .real(callID: "call_test_chat_reload_orphan",
                                     itemID: "call_test_chat_reload_orphan"))
    }

    // MARK: encrypted-reasoning probe
    //
    // Design probe for the reasoning-persistence project: does the Responses
    // API return reasoning.encrypted_content when store:true? If yes, a
    // hybrid is possible (previous_response_id for live turns, locally
    // persisted blobs as the reload/expiry fallback). If no, store:false is
    // the only way to obtain the blobs and requests must run stateless.
    // The store:false leg doubles as the control: if IT returns no blob the
    // probe itself is broken and the test fails instead of reporting a
    // false "no".

    /// One raw Responses call (bypasses the builder, which doesn't emit
    /// store/include yet). Returns (reasoning items seen, of which with
    /// non-empty encrypted_content), or throws with the HTTP error body.
    private func probeEncryptedReasoning(apiKey: String,
                                         model: String,
                                         store: Bool) async throws -> (reasoningItems: Int, encrypted: Int) {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "input": [["role": "user",
                       "content": [["type": "input_text",
                                    "text": "What is 17*23? Reply with just the number."]]]],
            "reasoning": ["effort": "low"],
            "include": ["reasoning.encrypted_content"],
            "store": store,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw NSError(domain: "probe", code: status, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(status): \(String(data: data, encoding: .utf8) ?? "<binary>")"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [[String: Any]] else {
            throw NSError(domain: "probe", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "unparseable body: \(String(data: data, encoding: .utf8) ?? "<binary>")"])
        }
        let reasoning = output.filter { ($0["type"] as? String) == "reasoning" }
        let encrypted = reasoning.filter {
            if let content = $0["encrypted_content"] as? String { return !content.isEmpty }
            return false
        }
        return (reasoning.count, encrypted.count)
    }

    func test_openai_probe_encryptedReasoning_storeTrueVsFalse() async throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        let model = "gpt-5-mini"

        // Control: store:false must yield encrypted content, else the probe
        // itself is wrong (bad model choice, API drift) and no verdict can
        // be trusted.
        let control = try await probeEncryptedReasoning(apiKey: key, model: model, store: false)
        print("[probe] store:false -> reasoning items: \(control.reasoningItems), with encrypted_content: \(control.encrypted)")
        XCTAssertGreaterThan(control.reasoningItems, 0, "[probe] control returned no reasoning items at all; pick a reasoning model")
        XCTAssertGreaterThan(control.encrypted, 0, "[probe] store:false returned no encrypted_content; probe is invalid")

        // The question: does store:true also return the blobs?
        do {
            let hybrid = try await probeEncryptedReasoning(apiKey: key, model: model, store: true)
            print("[probe] store:true  -> reasoning items: \(hybrid.reasoningItems), with encrypted_content: \(hybrid.encrypted)")
            print("[probe] VERDICT: hybrid (store:true + encrypted_content) is \(hybrid.encrypted > 0 ? "POSSIBLE" : "NOT possible (no blob returned)")")
        } catch {
            print("[probe] store:true request REJECTED: \(error.localizedDescription)")
            print("[probe] VERDICT: hybrid is NOT possible (request rejected)")
        }
    }

    // MARK: reasoning replay after reload (API contract)
    //
    // Pins the API contract the reasoning-persistence design rests on, with
    // REAL blobs (a fabricated encrypted_content would be rejected outright):
    //   1. A live turn produces a reasoning item + function_call.
    //   2. Replaying [reasoning, function_call(id), output] statelessly (no
    //      previous_response_id) is accepted - the reload path for chats
    //      with persisted reasoning.
    //   3. Replaying the call with NO reasoning and NO item id is accepted -
    //      the best-effort path for pre-persistence chats.
    //   4. (Reported, not asserted) the call WITH its item id but WITHOUT
    //      its reasoning item - the shape that motivated the id strip.

    private func rawResponses(apiKey: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw NSError(domain: "probe", code: status, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(status): \(String(data: data, encoding: .utf8) ?? "<binary>")"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "probe", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "unparseable body"])
        }
        return json
    }

    func test_openai_reasoningReplay_afterReload() async throws {
        let key = try keyOrSkip(Self.loadKeys().openAI, vendor: "openai")
        let model = "gpt-5-mini"
        let toolDef: [String: Any] = [
            "type": "function", "name": "lookup",
            "description": "Look up a fact by key.",
            "parameters": ["type": "object",
                           "properties": ["key": ["type": "string"]],
                           "required": ["key"],
                           "additionalProperties": false],
            "strict": true,
        ]
        let userTurn: [String: Any] = [
            "role": "user",
            "content": [["type": "input_text",
                         "text": "Use the lookup tool to fetch the value for key answer, then tell me what it is."]]]

        // 1. Live turn: capture a real reasoning item and function_call.
        let first = try await rawResponses(apiKey: key, body: [
            "model": model, "input": [userTurn], "tools": [toolDef],
            "tool_choice": "required", "reasoning": ["effort": "low"],
            "include": ["reasoning.encrypted_content"], "store": true,
        ])
        let output = try XCTUnwrap(first["output"] as? [[String: Any]])
        let reasoning = try XCTUnwrap(output.first { ($0["type"] as? String) == "reasoning" },
                                      "setup turn produced no reasoning item")
        let call = try XCTUnwrap(output.first { ($0["type"] as? String) == "function_call" },
                                 "setup turn produced no function_call")
        let encrypted = try XCTUnwrap(reasoning["encrypted_content"] as? String,
                                      "setup turn returned no encrypted_content")
        let callID = try XCTUnwrap(call["call_id"] as? String)
        let itemID = try XCTUnwrap(call["id"] as? String)
        let callArguments = call["arguments"] as? String ?? "{}"
        let outputItem: [String: Any] = ["type": "function_call_output",
                                         "call_id": callID, "output": "{\"value\": \"42\"}"]
        let followUp: [String: Any] = [
            "role": "user",
            "content": [["type": "input_text",
                         "text": "In one short sentence, what did the tool return?"]]]

        func replay(includeReasoning: Bool, includeItemID: Bool) async throws -> [String: Any] {
            var fc: [String: Any] = ["type": "function_call", "call_id": callID,
                                     "name": "lookup", "arguments": callArguments]
            if includeItemID { fc["id"] = itemID }
            var input: [[String: Any]] = [userTurn]
            if includeReasoning {
                input.append(["type": "reasoning", "id": reasoning["id"] as? String ?? "",
                              "summary": [],
                              "encrypted_content": encrypted])
            }
            input.append(contentsOf: [fc, outputItem, followUp])
            return try await rawResponses(apiKey: key, body: [
                "model": model, "input": input, "tools": [toolDef],
                "reasoning": ["effort": "low"],
            ])
        }

        // 2. Full-fidelity replay (persisted reasoning): must be accepted.
        let full = try await replay(includeReasoning: true, includeItemID: true)
        XCTAssertEqual(full["status"] as? String, "completed",
                       "reasoning+id replay was not accepted")
        print("[reasoningReplay] full-fidelity replay accepted")

        // 3. Legacy replay (no reasoning persisted, item id stripped): must
        //    be accepted - this is the pre-persistence chat's path.
        let legacy = try await replay(includeReasoning: false, includeItemID: false)
        XCTAssertEqual(legacy["status"] as? String, "completed",
                       "legacy id-stripped replay was not accepted")
        print("[reasoningReplay] legacy id-stripped replay accepted")

        // 3b. Interleaved replay: a turn whose REAL output was
        //     [reasoning, message, function_call] must replay in that same
        //     order and be accepted. The encrypted payload binds the turn's
        //     structure: fabricating a text item inside a turn that had none
        //     is rejected ("function_call provided without its required
        //     reasoning item"), so this leg makes its own setup call that
        //     asks for a preamble and replays the REAL items verbatim -
        //     exactly what the production builder does with a multipart
        //     text+call turn.
        let preamblePrompt: [String: Any] = [
            "role": "user",
            "content": [["type": "input_text",
                         "text": "Briefly say you will look it up, then use the lookup tool to fetch the value for key answer."]]]
        let second = try await rawResponses(apiKey: key, body: [
            "model": model, "input": [preamblePrompt],
            "tools": [toolDef], "tool_choice": "auto",
            "reasoning": ["effort": "low"],
            "include": ["reasoning.encrypted_content"], "store": true,
        ])
        let output2 = try XCTUnwrap(second["output"] as? [[String: Any]])
        if let reasoning2 = output2.first(where: { ($0["type"] as? String) == "reasoning" }),
           let message2 = output2.first(where: { ($0["type"] as? String) == "message" }),
           let call2 = output2.first(where: { ($0["type"] as? String) == "function_call" }),
           let encrypted2 = reasoning2["encrypted_content"] as? String,
           let callID2 = call2["call_id"] as? String {
            let text2 = ((message2["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            let interleaved = try await rawResponses(apiKey: key, body: [
                "model": model,
                "input": [
                    preamblePrompt,
                    ["type": "reasoning", "id": reasoning2["id"] as? String ?? "",
                     "summary": [], "encrypted_content": encrypted2],
                    ["role": "assistant",
                     "content": [["type": "output_text", "text": text2]]],
                    ["type": "function_call", "id": call2["id"] as? String ?? "",
                     "call_id": callID2, "name": "lookup",
                     "arguments": call2["arguments"] as? String ?? "{}"],
                    ["type": "function_call_output", "call_id": callID2,
                     "output": "{\"value\": \"42\"}"],
                    followUp,
                ],
                "tools": [toolDef], "reasoning": ["effort": "low"],
            ])
            XCTAssertEqual(interleaved["status"] as? String, "completed",
                           "reasoning/text/function_call replay of a REAL mixed turn was not accepted")
            print("[reasoningReplay] interleaved text replay (real mixed turn) accepted")
        } else {
            // The model chose not to emit a preamble this run; the leg proves
            // nothing without a real mixed turn, so report and move on rather
            // than fabricate one (which the API rejects by design).
            print("[reasoningReplay] interleaved leg skipped: setup turn produced no text+call mix")
        }

        // 4. Negative control, reported only: the id WITHOUT its reasoning.
        do {
            _ = try await replay(includeReasoning: false, includeItemID: true)
            print("[reasoningReplay] NOTE: id-without-reasoning was ACCEPTED; the id strip is precautionary")
        } catch {
            print("[reasoningReplay] id-without-reasoning rejected as expected: \(error.localizedDescription)")
        }
    }
}
