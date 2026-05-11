//
//  AILiveDriver.swift
//  iTerm2 AI live harness
//
//  Drives a single round-trip through AITermController against a real
//  vendor API. NOT a unit test. Intended to be invoked only from
//  AILiveHarness, which itself only runs when ITERM2_AI_LIVE=1.
//
//  Captures raw HTTP traffic via iTermAIClient.liveObserver. Each
//  round-trip is written as a JSON file under
//      ${TMPDIR}/iterm2-ai-live-logs/<test_method>/
//  and attached to the test's xcresult. Default lifetime is
//  .deleteOnSuccess so passing runs leave no xcresult attachments;
//  set ITERM2_AI_LIVE_LOG=1 to keep them on success too.
//
//  Authorization headers and key-bearing query parameters are redacted
//  before serialization. Request and response bodies are written
//  verbatim (parsed as JSON when possible for readability).
//

import XCTest
@testable import iTerm2SharedARC

struct AILiveRunResult {
    var finalText: String
    var streamedChunks: [String]
    var attachments: [LLM.Message.Attachment]
    var functionsInvoked: [String]
    var elapsed: TimeInterval
}

enum AILiveError: Error, CustomStringConvertible {
    case modelNotFound(String)
    case invalidApiKey
    case providerFailure(String)
    case noResponseReceived
    case unexpectedRegistrationRequest

    var description: String {
        switch self {
        case .modelNotFound(let name): return "model not found in AIMetadata: \(name)"
        case .invalidApiKey: return "API key was nil or empty"
        case .providerFailure(let s): return "provider failure: \(s)"
        case .noResponseReceived: return "no response received before timeout"
        case .unexpectedRegistrationRequest:
            return "controller asked for registration; live harness must not hit the keychain or UI"
        }
    }
}

struct AILiveFunctionSpec<T: Codable> {
    var decl: ChatGPTFunctionDeclaration
    var implementation: LLM.Function<T>.Impl
}

final class AILiveDriver: NSObject, AITermControllerDelegate {
    private let controller: AITermController
    private let streamingRequested: Bool
    private let expectation: XCTestExpectation
    private let modelName: String
    private let scenarioTag: String
    private let logDir: URL
    private weak var test: XCTestCase?
    private var captureSeq = 0

    private var streamedChunks: [String] = []
    private var attachments: [LLM.Message.Attachment] = []
    private var functionsInvoked: [String] = []
    private var assembled = ""
    private var capturedError: Error?
    private var done = false
    private let startTime = Date()

    private init(controller: AITermController,
                 streamingRequested: Bool,
                 modelName: String,
                 scenarioTag: String,
                 logDir: URL,
                 test: XCTestCase,
                 expectation: XCTestExpectation) {
        self.controller = controller
        self.streamingRequested = streamingRequested
        self.modelName = modelName
        self.scenarioTag = scenarioTag
        self.logDir = logDir
        self.test = test
        self.expectation = expectation
        super.init()
        controller.delegate = self
    }

    static func run<T: Codable>(modelName: String,
                                apiKey: String,
                                messages: [LLM.Message],
                                streaming: Bool,
                                thinking: Bool? = nil,
                                function: AILiveFunctionSpec<T>? = nil,
                                hostedTools: HostedTools = HostedTools(),
                                scenarioTag: String = "unspec",
                                timeout: TimeInterval = 120,
                                test: XCTestCase) throws -> AILiveRunResult {
        guard let model = AIMetadata.instance.models.first(where: { $0.name == modelName }) else {
            throw AILiveError.modelNotFound(modelName)
        }
        return try run(model: model,
                       apiKey: apiKey,
                       messages: messages,
                       streaming: streaming,
                       thinking: thinking,
                       function: function,
                       hostedTools: hostedTools,
                       scenarioTag: scenarioTag,
                       timeout: timeout,
                       test: test)
    }

    static func run<T: Codable>(model: AIMetadata.Model,
                                apiKey: String,
                                messages: [LLM.Message],
                                streaming: Bool,
                                thinking: Bool? = nil,
                                function: AILiveFunctionSpec<T>? = nil,
                                hostedTools: HostedTools = HostedTools(),
                                scenarioTag: String = "unspec",
                                timeout: TimeInterval = 120,
                                test: XCTestCase) throws -> AILiveRunResult {
        // Retry once on transient HTTP failures (429 / 5xx). Vendor APIs occasionally
        // return RESOURCE_EXHAUSTED or 503 capacity errors that recover within a
        // few seconds; absorbing those here lets the harness be robust to vendor
        // weather without hiding real bugs (a permanent denial throws on attempt 2
        // just like attempt 1 would have).
        let maxAttempts = 2
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try runOnce(model: model,
                                   apiKey: apiKey,
                                   messages: messages,
                                   streaming: streaming,
                                   thinking: thinking,
                                   function: function,
                                   hostedTools: hostedTools,
                                   scenarioTag: scenarioTag,
                                   timeout: timeout,
                                   test: test)
            } catch let error {
                lastError = error
                if attempt < maxAttempts && shouldRetry(error: error) {
                    Thread.sleep(forTimeInterval: retryDelay(after: error))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? AILiveError.noResponseReceived
    }

    private static func runOnce<T: Codable>(model: AIMetadata.Model,
                                            apiKey: String,
                                            messages: [LLM.Message],
                                            streaming: Bool,
                                            thinking: Bool?,
                                            function: AILiveFunctionSpec<T>?,
                                            hostedTools: HostedTools,
                                            scenarioTag: String,
                                            timeout: TimeInterval,
                                            test: XCTestCase) throws -> AILiveRunResult {
        guard let registration = AITermController.Registration(apiKey: apiKey) else {
            throw AILiveError.invalidApiKey
        }
        let modelName = model.name
        let controller = AITermController(registration: registration)
        controller.providerOverride = LLMProvider(model: model)
        controller.hostedTools = hostedTools
        if model.features.contains(.configurableThinking), let thinking {
            controller.shouldThink = thinking
        }
        if let function {
            controller.define(function: function.decl,
                              arguments: T.self,
                              implementation: function.implementation)
        }
        let label = "live AI \(modelName) [stream=\(streaming)]"
        let exp = test.expectation(description: label)
        let logDir = makeLogDir(for: test)
        let driver = AILiveDriver(controller: controller,
                                  streamingRequested: streaming,
                                  modelName: modelName,
                                  scenarioTag: scenarioTag,
                                  logDir: logDir,
                                  test: test,
                                  expectation: exp)

        iTermAIClient.liveObserver = { [weak driver] capture in
            driver?.consume(capture: capture)
        }
        defer { iTermAIClient.liveObserver = nil }

        let effectiveStream = streaming && controller.supportsStreaming
        controller.request(messages: messages, stream: effectiveStream)
        test.wait(for: [exp], timeout: timeout)

        if !driver.done {
            controller.cancelOutstandingOperation()
        }
        if let err = driver.capturedError {
            throw err
        }
        guard driver.done else {
            throw AILiveError.noResponseReceived
        }
        return AILiveRunResult(finalText: driver.assembled,
                               streamedChunks: driver.streamedChunks,
                               attachments: driver.attachments,
                               functionsInvoked: driver.functionsInvoked,
                               elapsed: Date().timeIntervalSince(driver.startTime))
    }

    /// Decide whether a single-attempt failure is worth retrying. Match
    /// HTTP 429, the transient 5xx codes that real vendors return for
    /// short-lived capacity issues, and URLSession-level timeouts ("The
    /// request timed out") which premium reasoning models sometimes hit
    /// while thinking about a hard prompt. Skip retry if the error mentions
    /// billing or "limit: 0"; those indicate permanent denial and won't
    /// recover.
    ///
    /// TODO: This is fragile string-matching against formatted error
    /// messages. If iTermAIClient ever changes how it stringifies HTTP
    /// failures, retry stops working with no compile-time signal. Right
    /// model is to plumb a typed AIError carrying status code +
    /// transient/permanent classification through the iTermAIClient
    /// completion result, then key retry off that. Larger refactor than
    /// this iteration; flagging for future cleanup.
    private static func shouldRetry(error: Error) -> Bool {
        let text = "\(error)"
        let permanent = text.contains("limit: 0")
            || text.contains("billing details")
            || text.contains("not available to new users")
        if permanent { return false }
        return text.contains("status 429")
            || text.contains("status 500")
            || text.contains("status 502")
            || text.contains("status 503")
            || text.contains("status 504")
            || text.contains("RESOURCE_EXHAUSTED")
            || text.contains("UNAVAILABLE")
            || text.lowercased().contains("timed out")
            || text.lowercased().contains("timeout")
    }

    /// Modest backoff. Vendors typically recover within a few seconds for
    /// the transient-capacity case; longer waits would slow the suite for
    /// no real benefit since persistent failures throw on attempt 2 anyway.
    private static func retryDelay(after error: Error) -> TimeInterval {
        return 4.0
    }

    static func run(modelName: String,
                    apiKey: String,
                    messages: [LLM.Message],
                    streaming: Bool,
                    thinking: Bool? = nil,
                    hostedTools: HostedTools = HostedTools(),
                    scenarioTag: String = "unspec",
                    timeout: TimeInterval = 120,
                    test: XCTestCase) throws -> AILiveRunResult {
        let nilFunction: AILiveFunctionSpec<EmptyArgs>? = nil
        return try run(modelName: modelName,
                       apiKey: apiKey,
                       messages: messages,
                       streaming: streaming,
                       thinking: thinking,
                       function: nilFunction,
                       hostedTools: hostedTools,
                       scenarioTag: scenarioTag,
                       timeout: timeout,
                       test: test)
    }

    static func run(model: AIMetadata.Model,
                    apiKey: String,
                    messages: [LLM.Message],
                    streaming: Bool,
                    thinking: Bool? = nil,
                    hostedTools: HostedTools = HostedTools(),
                    scenarioTag: String = "unspec",
                    timeout: TimeInterval = 120,
                    test: XCTestCase) throws -> AILiveRunResult {
        let nilFunction: AILiveFunctionSpec<EmptyArgs>? = nil
        return try run(model: model,
                       apiKey: apiKey,
                       messages: messages,
                       streaming: streaming,
                       thinking: thinking,
                       function: nilFunction,
                       hostedTools: hostedTools,
                       scenarioTag: scenarioTag,
                       timeout: timeout,
                       test: test)
    }

    // MARK: - Capture

    private func consume(capture: iTermAIClient.LiveCapture) {
        captureSeq += 1
        let mode = streamingRequested ? "stream" : "noStream"
        let safeModel = AILiveDriver.sanitize(modelName)
        let safeScenario = AILiveDriver.sanitize(scenarioTag)
        let filename = String(format: "%03d_%@_%@_%@.json",
                              captureSeq, safeModel, safeScenario, mode)
        let url = logDir.appendingPathComponent(filename)
        let data = AILiveDriver.serialize(capture: capture)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("[live] failed to write capture log to \(url.path): \(error)")
        }
        if let test {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = filename
            let alwaysKeep = ProcessInfo.processInfo.environment["ITERM2_AI_LIVE_LOG"] == "1"
            attachment.lifetime = alwaysKeep ? .keepAlways : .deleteOnSuccess
            test.add(attachment)
        }

        // Refusal-scenario captures double up: also write to the project's
        // permanent fixtures directory so they can be committed and used as
        // input for offline parser tests. Filename is keyed by vendor + model +
        // mode (no sequence) since a refusal is always a single round-trip;
        // re-running for the same model overwrites the existing fixture.
        if scenarioTag.hasPrefix("refusal"),
           let projectRoot = AILiveDriver.projectRoot() {
            let fixturesDir = (projectRoot as NSString)
                .appendingPathComponent("ModernTests")
                + "/Resources/SafetyRefusalFixtures"
            try? FileManager.default.createDirectory(
                atPath: fixturesDir, withIntermediateDirectories: true)
            let vendor = AILiveDriver.guessVendor(modelName: modelName) ?? "unknown"
            let fixtureName = "\(vendor)_\(safeModel)_\(safeScenario)_\(mode).json"
            let fixtureURL = URL(fileURLWithPath: fixturesDir)
                .appendingPathComponent(fixtureName)
            do {
                try data.write(to: fixtureURL, options: .atomic)
                print("[live] saved refusal fixture: \(fixtureURL.path)")
            } catch {
                print("[live] failed to write refusal fixture \(fixtureURL.path): \(error)")
            }
        }
    }

    private static func projectRoot() -> String? {
        let configPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("iterm2-ai-live.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let root = json["PROJECT_ROOT"], !root.isEmpty
        else {
            return nil
        }
        return root
    }

    private static func guessVendor(modelName: String) -> String? {
        if let model = AIMetadata.instance.models.first(where: { $0.name == modelName }) {
            switch model.vendor {
            case .openAI:    return "openai"
            case .anthropic: return "anthropic"
            case .gemini:    return "gemini"
            case .deepSeek:  return "deepseek"
            case .llama:     return "llama"
            case .none:      return nil
            @unknown default: return nil
            }
        }
        // Synthetic models created in the harness aren't in AIMetadata; fall
        // back to a name-prefix guess.
        let lower = modelName.lowercased()
        if lower.hasPrefix("gpt") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
            return "openai"
        }
        if lower.hasPrefix("claude") { return "anthropic" }
        if lower.hasPrefix("gemini") { return "gemini" }
        if lower.hasPrefix("deepseek") { return "deepseek" }
        return nil
    }

    private static let sensitiveHeaderHints = ["auth", "api-key", "api_key", "apikey", "x-goog-api-key", "token"]
    private static let sensitiveQueryHints = ["key", "token", "auth"]

    static func serialize(capture: iTermAIClient.LiveCapture) -> Data {
        var redactedHeaders = capture.request.headers
        for key in redactedHeaders.keys {
            let lower = key.lowercased()
            if sensitiveHeaderHints.contains(where: { lower.contains($0) }) {
                redactedHeaders[key] = "REDACTED"
            }
        }

        var redactedURL = capture.request.url
        if let comps = URLComponents(string: redactedURL) {
            var c = comps
            if let items = c.queryItems {
                c.queryItems = items.map { item in
                    let n = item.name.lowercased()
                    if sensitiveQueryHints.contains(where: { n.contains($0) }) {
                        return URLQueryItem(name: item.name, value: "REDACTED")
                    }
                    return item
                }
            }
            redactedURL = c.string ?? redactedURL
        }

        let bodyValue: Any = {
            switch capture.request.body {
            case .string(let s):
                if let data = s.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    return parsed
                }
                return s
            case .bytes(let b):
                return ["_bytes": b.count]
            }
        }()

        let responseObject: Any = {
            guard let response = capture.response else {
                return NSNull()
            }
            var dict: [String: Any] = [:]
            if let parsed = try? JSONSerialization.jsonObject(with: Data(response.data.utf8)) {
                dict["body"] = parsed
            } else {
                dict["body"] = response.data
            }
            if let err = response.error, !err.isEmpty {
                dict["error"] = err
            }
            return dict
        }()

        var top: [String: Any] = [
            "request": [
                "method": capture.request.method,
                "url": redactedURL,
                "headers": redactedHeaders,
                "body": bodyValue,
            ],
            "streaming": capture.streaming,
            "streamChunks": capture.streamChunks,
            "response": responseObject,
            "elapsedMs": Int(capture.elapsed * 1000),
        ]
        if let err = capture.error {
            top["pluginError"] = err.reason
        }

        do {
            return try JSONSerialization.data(withJSONObject: top,
                                              options: [.prettyPrinted, .sortedKeys])
        } catch {
            let fallback = "Failed to serialize live capture: \(error)\n"
            return Data(fallback.utf8)
        }
    }

    private static func makeLogDir(for test: XCTestCase) -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iterm2-ai-live-logs")
            .appendingPathComponent(sanitize(test.name))
        try? FileManager.default.createDirectory(at: base,
                                                 withIntermediateDirectories: true)
        return base
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    // MARK: - Lifecycle

    private func finish() {
        guard !done else { return }
        done = true
        expectation.fulfill()
    }

    func aitermControllerWillSendRequest(_ sender: AITermController) {}

    func aitermController(_ sender: AITermController, offerChoice choice: String) {
        if assembled.isEmpty {
            assembled = choice
        }
        finish()
    }

    func aitermController(_ sender: AITermController, didStreamUpdate update: String?) {
        if let update {
            streamedChunks.append(update)
            assembled.append(update)
        } else {
            finish()
        }
    }

    func aitermController(_ sender: AITermController,
                          didStreamAttachment attachment: LLM.Message.Attachment) {
        attachments.append(attachment)
    }

    func aitermController(_ sender: AITermController, didFailWithError error: Error) {
        capturedError = AILiveError.providerFailure(error.localizedDescription)
        finish()
    }

    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ()) {
        capturedError = AILiveError.unexpectedRegistrationRequest
        finish()
    }

    func aitermController(_ sender: AITermController,
                          didCreateVectorStore id: String,
                          withName name: String) {}

    func aitermController(_ sender: AITermController,
                          didFailToCreateVectorStoreWithError error: Error) {
        capturedError = AILiveError.providerFailure(error.localizedDescription)
        finish()
    }

    func aitermController(_ sender: AITermController, didUploadFileWithID id: String) {}

    func aitermController(_ sender: AITermController, didFailToUploadFileWithError error: Error) {
        capturedError = AILiveError.providerFailure(error.localizedDescription)
        finish()
    }

    func aitermControllerDidAddFilesToVectorStore(_ sender: AITermController) {}

    func aitermControllerDidFailToAddFilesToVectorStore(_ sender: AITermController, error: Error) {
        capturedError = AILiveError.providerFailure(error.localizedDescription)
        finish()
    }

    func aitermController(_ sender: AITermController, willInvokeFunction function: any LLM.AnyFunction) {
        functionsInvoked.append(function.decl.name)
    }

    func aitermControllerDidCancelOutstandingRequest(_ sender: AITermController) {
        capturedError = AILiveError.providerFailure("request cancelled")
        finish()
    }
}

struct EmptyArgs: Codable {}
