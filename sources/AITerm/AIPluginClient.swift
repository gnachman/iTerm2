//
//  AIPluginClient.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

import CryptoKit
import JavaScriptCore

struct WebRequest: CustomDebugStringConvertible, Codable {
    var debugDescription: String {
        return "\(method) \(url)\n\(headers.debugDescription)\n\n\(body)"
    }
    var headers: [String: String]
    var method: String
    enum Body {
        case string(String)
        case bytes([UInt8])
    }
    var body: Body
    var url: String

    enum CodingKeys: String, CodingKey {
        case headers
        case method
        case body
        case url
    }

    init(headers: [String: String], method: String, body: Body, url: String) {
        self.headers = headers
        self.method = method
        self.body = body
        self.url = url
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        headers = try container.decode([String: String].self, forKey: .headers)
        method = try container.decode(String.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)

        if let stringValue = try? container.decode(String.self, forKey: .body) {
            body = .string(stringValue)
        } else if let byteArray = try? container.decode([UInt8].self, forKey: .body) {
            body = .bytes(byteArray)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .body, in: container, debugDescription: "Expected string or [UInt8] for body")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headers, forKey: .headers)
        try container.encode(method, forKey: .method)
        try container.encode(url, forKey: .url)

        switch body {
        case .string(let s):
            try container.encode(s, forKey: .body)
        case .bytes(let bytes):
            try container.encode(bytes, forKey: .body)
        }
    }
}

struct WebResponse: Codable {
    var data: String
    var error: String?
}

struct PluginError: Error, Equatable, CustomDebugStringConvertible {
    static let cancelled = PluginError(reason: "cancelled")

    var debugDescription: String {
        return "<PluginError \(reason)>"
    }
    var localizedDescription: String {
        reason
    }
    var reason: String
}


struct Plugin {
    static private var _instance = MutableAtomicObject<Result<Plugin, PluginError>?>(nil)
    private static let publicKeyB64 = "fYLUx58QwucuPJRYxBjp7M//uVM0vTfgUo7d6u4TQR8="

    static func instance() -> Result<Plugin, PluginError> {
        return _instance.mutableAccess { result in
            switch result {
            case .success(let plugin):
                return .success(plugin)
            case .failure, .none:
                break
            }
            let temp = load()
            result = temp
            return temp
        }
    }

    private static func load() -> Result<Plugin, PluginError> {
        do {
            return  Result<Plugin, PluginError>.success(try Plugin())
        } catch let error as PluginError {
            let temp = Result<Plugin, PluginError>.failure(error)
            DLog("\(error.reason)")
            return temp
        } catch {
            DLog("\(error.localizedDescription)")
            let temp = Result<Plugin, PluginError>.failure(PluginError(reason: error.localizedDescription))
            return temp
        }
    }
    static func reload() {
        _instance.mutableAccess { result in
            result = load()
        }
    }

    private let bundleID = "com.googlecode.iterm2.iTermAI"
    private let code: String
    init() throws {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw PluginError(reason: "Plugin not found")
        }
        let jsURL = bundleURL.appendingPathComponent("Contents/Resources/iTermAIPlugin.js")
        guard let codeData = try? Data(contentsOf: jsURL) else {
            throw PluginError(reason: "Plugin missing from app bundle or not readable")
        }
        guard let code = String(data: codeData, encoding: .utf8) else {
            throw PluginError(reason: "Plugin code not valid UTF-8")
        }
        let signatureURL = bundleURL.appendingPathComponent("Contents/Resources/iTermAIPlugin.sig")
        guard let signatureB64 = try? String(contentsOf: signatureURL) else {
            throw PluginError(reason: "Signature missing from app bundle or not readable")
        }
        guard let signatureData = Data(base64Encoded: signatureB64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PluginError(reason: "Signature of AI plugin is malformed")
        }
        try Plugin.checkSignature(message: codeData, signature: signatureData)
        self.code = code
    }

    private static func checkSignature(message: Data, signature: Data) throws {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKeyB64)!)
        guard publicKey.isValidSignature(signature, for: message) else {
            throw PluginError(reason: "The plugin's signature is invalid. Reinstall the plugin or upgrade iTerm2.")
        }
        DLog("Signature is good")
    }

    func version() throws -> Decimal {
        let string: String = try PluginClient.instance.call(code: code,
                                                            functionName: "version",
                                                            request: nil as Optional<String>,
                                                            async: false,
                                                            stream: nil)
        guard let decimal = Decimal(string: string) else {
            throw PluginError(reason: "Invalid version string: \(string)")
        }
        return decimal
    }

    func load(webRequest: WebRequest, stream: ((String) -> ())?) throws -> WebResponse {
        DLog("load \(webRequest)")
        return try PluginClient.instance.call(code: code,
                                              functionName: "request",
                                              request: webRequest,
                                              async: true,
                                              stream: stream)
    }

    func cancel() {
        PluginClient.instance.cancel()
    }
}

class iTermAIClient {
    private let executionQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-execution")
    private let outputQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-output")
    static let instance = iTermAIClient()

    var available: Bool {
        return Plugin.instance().isSuccess
    }

    func version() throws -> Decimal {
        DLog("version")
        switch Plugin.instance() {
        case .success(let plugin):
            return try plugin.version()
        case .failure(let error):
            throw error
        }
    }

    private let requiredVersion = "1.1"

    // Runs on any queue. Throws a PluginError or does nothing.
    func validate() throws {
        DLog("validate")
        if (!iTermAdvancedSettingsModel.generativeAIAllowed()) {
            throw PluginError(reason: "Plugin not allowed by administator.")
        }
        switch Plugin.instance() {
        case .success(let plugin):
            guard let pluginVersion = try? plugin.version() else {
                throw PluginError(reason: "Unable to determine version of AI plugin. Reinstall it and upgrade iTerm2 if possible.")
            }

            guard pluginVersion == Decimal(string: requiredVersion) else {
                throw PluginError(reason: "Plugin has version \(pluginVersion) but iTerm2 expects \(requiredVersion). Upgrade one or both.")
            }
            return
        case .failure(let error):
            DLog("\(error)")
            throw error
        }
    }

    func validate(_ completion: @escaping (String?) -> ()) {
        executionQueue.async {
            do {
                try self.validate()
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error as PluginError {
                DispatchQueue.main.async {
                    completion(error.reason)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error.localizedDescription)
                }
            }
        }
    }

    func reload(_ completion: @escaping () -> ()) {
        executionQueue.async {
            do {
                Plugin.reload()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // Live-traffic observer hook used exclusively by the AI live test
    // harness (AILiveDriver) to capture raw wire data for fixture
    // generation. Always compiled in (no #if guard) so test code in
    // ModernTests can reference these symbols regardless of which
    // configuration the test target is built under. The runtime cost in
    // release is one optional read per request: nothing in the shipping
    // app sets liveObserver, so the conditional capture path is dead code
    // the optimizer can elide.
    //
    // Concurrency model: get/set of the slot itself is locked so
    // concurrent tests installing/removing observers cannot tear the
    // closure word. The harness still pins `parallel-testing-enabled NO`
    // because two harness tests sharing one observer slot would clobber
    // each other's captures even if the assignment were atomic. Per-call
    // mutation of the captured LiveCapture IS safe: streamChunks is
    // written from the plugin's executionQueue inside plugin.load, and
    // the response/error/elapsed fields are written on the main queue
    // inside emit; the DispatchQueue.main.async barrier orders the
    // executionQueue writes before main-queue reads.
    struct LiveCapture {
        var request: WebRequest
        var streaming: Bool
        var streamChunks: [String]
        var response: WebResponse?
        var error: PluginError?
        var elapsed: TimeInterval
    }

    private final class LiveCaptureBox {
        var capture: LiveCapture
        init(_ c: LiveCapture) { self.capture = c }
    }

    private static let _liveObserver = MutableAtomicObject<((LiveCapture) -> Void)?>(nil)
    static var liveObserver: ((LiveCapture) -> Void)? {
        get { _liveObserver.value }
        set { _liveObserver.set(newValue) }
    }

    // What a cassette replay hands back in place of a live round-trip:
    // the stream chunks to re-emit (empty for non-streaming) and the final
    // outcome as either a response body or an error reason.
    struct ReplayDelivery {
        var streamChunks: [String]
        var response: WebResponse?
        var errorReason: String?
    }

    // Replay hook used exclusively by the AI live test harness
    // (AICassetteSession) to serve recorded vendor responses without
    // spending money on the network. Same compile-in rationale as
    // liveObserver: always present so test code can install it regardless
    // of build configuration; nothing in the shipping app sets it, so the
    // branch below is one optional read per request in release.
    //
    // Returning nil means "no cassette, proceed live". Returning a delivery
    // short-circuits the plugin entirely and replays the recorded outcome.
    private static let _requestInterceptor =
        MutableAtomicObject<((WebRequest, Bool) -> ReplayDelivery?)?>(nil)
    static var requestInterceptor: ((WebRequest, Bool) -> ReplayDelivery?)? {
        get { _requestInterceptor.value }
        set { _requestInterceptor.set(newValue) }
    }

    // Recording hook used by the cassette harness to persist the outcome of
    // a live (non-replayed) round-trip. Separate from liveObserver so that
    // test paths which don't run through AILiveDriver (e.g. the ChatBroker /
    // ChatAgent queue tests, which never set liveObserver) still get their
    // traffic recorded. Fired once per completed live request with the final
    // capture. Like the other hooks, nothing in the shipping app sets it.
    private static let _responseRecorder = MutableAtomicObject<((LiveCapture) -> Void)?>(nil)
    static var responseRecorder: ((LiveCapture) -> Void)? {
        get { _responseRecorder.value }
        set { _responseRecorder.set(newValue) }
    }

    func request(webRequest: WebRequest,
                 stream: ((String) -> ())?,
                 completion: @escaping (Result<WebResponse, PluginError>) -> ()) -> Cancellation {
        let cancellation = Cancellation()
        let observer = Self.liveObserver
        let recorder = Self.responseRecorder
        // Build the capture if anything wants it: the observer (AILiveDriver
        // result extraction) or the recorder (cassette persistence). Either
        // alone is enough, so chat-queue tests, which set only the recorder,
        // still accumulate stream chunks and a final response.
        let captureBox: LiveCaptureBox? = (observer != nil || recorder != nil)
            ? LiveCaptureBox(LiveCapture(request: webRequest,
                                         streaming: stream != nil,
                                         streamChunks: [],
                                         response: nil,
                                         error: nil,
                                         elapsed: 0))
            : nil
        // Cassette replay: if the harness installed an interceptor and it
        // has a recording for this request, replay it instead of touching
        // the plugin/network. We still drive the streaming closure and the
        // liveObserver so downstream parsers and the driver see the same
        // sequence of events they would on a live call.
        if let interceptor = Self.requestInterceptor,
           let delivery = interceptor(webRequest, stream != nil) {
            let result: Result<WebResponse, PluginError>
            if let errorReason = delivery.errorReason {
                result = .failure(PluginError(reason: errorReason))
            } else if let response = delivery.response {
                result = .success(response)
            } else {
                result = .failure(PluginError(reason: "Cassette delivery had neither response nor error"))
            }
            executionQueue.async {
                if cancellation.canceled {
                    DispatchQueue.main.async { completion(.failure(.cancelled)) }
                    return
                }
                if let stream {
                    for chunk in delivery.streamChunks { stream(chunk) }
                }
                DispatchQueue.main.async {
                    if let observer, let captureBox {
                        captureBox.capture.streamChunks = delivery.streamChunks
                        switch result {
                        case .success(let r): captureBox.capture.response = r
                        case .failure(let e): captureBox.capture.error = e
                        }
                        observer(captureBox.capture)
                    }
                    completion(result)
                }
            }
            return cancellation
        }
        // Stable per-call ID so the disk wire log can correlate the
        // request, every streamed chunk, and the final response /
        // error across interleaved concurrent calls. The cost of
        // generating it when logging is off is one UUID per call,
        // which is negligible next to the round-trip itself.
        let callID = UUID()
        let wireLogger = AIChatWireLogger.instance
        wireLogger.logRequest(callID: callID, request: webRequest)
        let startTime = Date()
        let emit: (Result<WebResponse, PluginError>) -> Void = { result in
            let elapsed = Date().timeIntervalSince(startTime)
            switch result {
            case .success(let r):
                wireLogger.logSuccess(callID: callID, response: r, elapsed: elapsed)
            case .failure(let e):
                wireLogger.logFailure(callID: callID, error: e, elapsed: elapsed)
            }
            DispatchQueue.main.async {
                if let captureBox {
                    switch result {
                    case .success(let r): captureBox.capture.response = r
                    case .failure(let e): captureBox.capture.error = e
                    }
                    captureBox.capture.elapsed = elapsed
                    observer?(captureBox.capture)
                    recorder?(captureBox.capture)
                }
                completion(result)
            }
        }
        executionQueue.async {
            switch Plugin.instance() {
            case .success(let plugin):
                do {
                    if cancellation.canceled {
                        throw PluginError.cancelled
                    }
                    cancellation.impl = {
                        plugin.cancel()
                    }
                    let wrappedStream: ((String) -> ())? = stream.map { downstream in
                        return { chunk in
                            wireLogger.logStreamChunk(callID: callID, chunk: chunk)
                            captureBox?.capture.streamChunks.append(chunk)
                            downstream(chunk)
                        }
                    }
                    let response = try plugin.load(webRequest: webRequest, stream: wrappedStream)
                    emit(.success(response))
                } catch let error as PluginError {
                    emit(.failure(error))
                } catch {
                    emit(.failure(PluginError(reason: "Unexpected exception: \(error.localizedDescription)")))
                }
            case .failure(let error):
                emit(.failure(error))
            }
        }
        return cancellation
    }
}
