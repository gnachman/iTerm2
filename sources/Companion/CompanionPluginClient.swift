//
//  CompanionPluginClient.swift
//  iTerm2
//
//  Runs the companion consent plugin's JavaScript in a single long-lived
//  JSContext and exposes its HTTP + WebSocket primitives as async Swift calls.
//  Unlike the AI plugin (a fresh context per one-shot request), the companion
//  WebSocket is stateful, so the context, its host functions, and the plugin
//  code are created once and reused; all context access is serialized on `q`,
//  and URLSession callbacks hop onto `q` before touching JS.
//
//  This is the app's ONLY outbound path for the companion feature: the plugin
//  JS (loaded and signature-verified by CompanionPlugin) calls the injected
//  host primitives here; nothing else in iTerm2 opens a companion connection.
//

import Foundation
import JavaScriptCore
import CompanionProtocol

// Thread-safe: every JSContext touch is serialized on `q`, and URLSession
// callbacks hop onto `q` before reaching JS.
final class CompanionPluginClient: NSObject, @unchecked Sendable {
    private let code: String
    private let q = DispatchQueue(label: "com.googlecode.iterm2.companion-plugin")
    private var _context: JSContext?

    // Native WebSocket state. Mutated only on `q` (host primitives run on `q`,
    // and URLSession callbacks hop to `q`).
    private var sockets: [String: URLSessionWebSocketTask] = [:]
    // All plugin egress (the WebSocket AND the one-shot HTTP requests) rides this
    // delegated session, so the redirect-refusal in the delegate below applies to
    // both. No companion endpoint legitimately returns a 3xx.
    private lazy var egressSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())

    init(code: String) {
        self.code = code
        super.init()
    }

    // MARK: Public API (the app calls these)

    struct WebResponse: Codable { var data: String; var error: String }

    /// One HTTP request through the plugin (the companion's only HTTP egress).
    func request(method: String, url: String, headers: [String: String], body: String) async throws -> WebResponse {
        let dict: [String: Any] = ["method": method, "url": url, "headers": headers, "body": body]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: dict), as: UTF8.self)
        let result = try await callPromise("request", [json])
        return try decode(result, as: WebResponse.self)
    }

    /// Open a WebSocket to `url`; returns the connection id once it is open.
    func wsOpen(url: String, headers: [String: String]) async throws -> String {
        let headersJSON = String(decoding: try JSONSerialization.data(withJSONObject: headers), as: UTF8.self)
        let result = try await callPromise("wsOpen", [url, headersJSON])
        struct Opened: Codable { var id: String }
        return try decode(result, as: Opened.self).id
    }

    enum Incoming { case text(String); case data(Data); case closed(code: Int, reason: String) }

    /// The next message on a connection (one per call), or a closed marker.
    func wsRecv(_ id: String) async throws -> Incoming {
        let result = try await callPromise("wsRecv", [id])
        struct Msg: Codable {
            struct Closed: Codable { var code: Int; var reason: String }
            var text: String?
            var binary: String?
            var closed: Closed?
        }
        let m = try decode(result, as: Msg.self)
        if let t = m.text { return .text(t) }
        if let b = m.binary, let d = Data(base64Encoded: b) { return .data(d) }
        if let c = m.closed { return .closed(code: c.code, reason: c.reason) }
        return .closed(code: 1006, reason: "malformed")
    }

    func wsSend(_ id: String, isBinary: Bool, data: String) {
        q.async { [weak self] in
            self?.context().objectForKeyedSubscript("wsSend")?.call(withArguments: [id, isBinary, data])
        }
    }

    func wsClose(_ id: String) {
        q.async { [weak self] in
            self?.context().objectForKeyedSubscript("wsClose")?.call(withArguments: [id])
        }
    }

    func wsPing(_ id: String) async -> Bool {
        guard let result = try? await callPromise("wsPing", [id]) else { return false }
        struct Pong: Codable { var ok: Bool }
        return (try? decode(result, as: Pong.self).ok) ?? false
    }

    func version() async throws -> String {
        let result = try await callValue("version", [])
        // version() returns a JSON string literal, e.g. "\"1.0\"".
        return (try? JSONDecoder().decode(String.self, from: Data((result.toString() ?? "").utf8)))
            ?? (result.toString() ?? "")
    }

    // MARK: JSContext

    /// Builds the context on first use (must be called on `q`).
    private func context() -> JSContext {
        dispatchPrecondition(condition: .onQueue(q))
        if let c = _context { return c }
        let c = JSContext()!
        c.exceptionHandler = { _, exception in
            RLog("Companion plugin JS exception: \(exception?.toString() ?? "(nil)")")
        }
        registerHostFunctions(c)
        c.evaluateScript(code)
        _context = c
        return c
    }

    private func registerHostFunctions(_ c: JSContext) {
        let log: @convention(block) (JSValue) -> Void = { msg in
            DLog("Companion plugin JS: \(msg.toString() ?? "(nil)")")
        }
        c.setObject(log, forKeyedSubscript: "log" as NSString)

        // HTTP: performHTTPRequest(method, url, headers, body, callback(data, error)).
        let http: @convention(block) (String, String, [String: String], Any, JSValue) -> Void = { [weak self] method, url, headers, body, cb in
            let bodyData: Data = (body as? String).map { Data($0.utf8) } ?? Data()
            self?.performHTTP(method: method, url: url, headers: headers, body: bodyData) { data, error in
                self?.q.async { cb.call(withArguments: [data as Any, error as Any]) }
            }
        }
        c.setObject(http, forKeyedSubscript: "performHTTPRequest" as NSString)

        // WebSocket host primitives. Called on `q` (from JS).
        let open: @convention(block) (String, String, String) -> Void = { [weak self] id, url, headersJSON in
            self?.hostWsOpen(id: id, url: url, headersJSON: headersJSON)
        }
        c.setObject(open, forKeyedSubscript: "hostWsOpen" as NSString)
        let send: @convention(block) (String, Bool, String) -> Void = { [weak self] id, isBinary, data in
            self?.hostWsSend(id: id, isBinary: isBinary, data: data)
        }
        c.setObject(send, forKeyedSubscript: "hostWsSend" as NSString)
        let close: @convention(block) (String) -> Void = { [weak self] id in
            self?.hostWsClose(id: id)
        }
        c.setObject(close, forKeyedSubscript: "hostWsClose" as NSString)
        let ping: @convention(block) (String, JSValue) -> Void = { [weak self] id, cb in
            self?.hostWsPing(id: id, cb: cb)
        }
        c.setObject(ping, forKeyedSubscript: "hostWsPing" as NSString)
    }

    /// Call a JS function that returns a Promise and await it.
    private func callPromise(_ function: String, _ args: [Any]) async throws -> JSValue {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSValue, Error>) in
            q.async { [weak self] in
                guard let self else { cont.resume(throwing: PluginError(reason: "plugin client gone")); return }
                let c = self.context()
                guard let f = c.objectForKeyedSubscript(function), !f.isUndefined,
                      let promise = f.call(withArguments: args) else {
                    cont.resume(throwing: PluginError(reason: "plugin function \(function) unavailable"))
                    return
                }
                var done = false
                let onResolve: @convention(block) (JSValue?) -> Void = { value in
                    if !done { done = true; cont.resume(returning: value ?? JSValue(undefinedIn: c)) }
                }
                let onReject: @convention(block) (JSValue?) -> Void = { value in
                    if !done { done = true; cont.resume(throwing: PluginError(reason: value?.toString() ?? "rejected")) }
                }
                promise.invokeMethod("then", withArguments: [JSValue(object: onResolve, in: c)!,
                                                              JSValue(object: onReject, in: c)!])
            }
        }
    }

    /// Call a synchronous JS function and return its raw value.
    private func callValue(_ function: String, _ args: [Any]) async throws -> JSValue {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSValue, Error>) in
            q.async { [weak self] in
                guard let self else { cont.resume(throwing: PluginError(reason: "plugin client gone")); return }
                let c = self.context()
                guard let f = c.objectForKeyedSubscript(function), !f.isUndefined,
                      let value = f.call(withArguments: args) else {
                    cont.resume(throwing: PluginError(reason: "plugin function \(function) unavailable"))
                    return
                }
                cont.resume(returning: value)
            }
        }
    }

    private func decode<T: Codable>(_ value: JSValue, as type: T.Type) throws -> T {
        guard let json = value.toString(), let data = json.data(using: .utf8) else {
            throw PluginError(reason: "plugin returned a non-string result")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Native WebSocket host (runs on `q`; URLSession callbacks hop to `q`)

    private func hostWsOpen(id: String, url: String, headersJSON: String) {
        guard let u = URL(string: url) else { callJS("_onClosed", [id, 1006, "bad url"]); return }
        var request = URLRequest(url: u)
        if let d = headersJSON.data(using: .utf8),
           let h = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] {
            for (k, v) in h { request.setValue(v, forHTTPHeaderField: k) }
        }
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        let task = egressSession.webSocketTask(with: request)
        task.taskDescription = id
        sockets[id] = task
        task.resume()
        receiveLoop(id: id, task: task)
    }

    private func receiveLoop(id: String, task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let s): self.callJS("_onMessage", [id, false, s])
                case .data(let d): self.callJS("_onMessage", [id, true, d.base64EncodedString()])
                @unknown default: break
                }
                self.receiveLoop(id: id, task: task)
            case .failure(let error):
                self.callJS("_onClosed", [id, 1006, error.localizedDescription])
            }
        }
    }

    private func hostWsSend(id: String, isBinary: Bool, data: String) {
        guard let task = sockets[id] else { return }
        if isBinary {
            task.send(.data(Data(base64Encoded: data) ?? Data())) { _ in }
        } else {
            task.send(.string(data)) { _ in }
        }
    }

    private func hostWsClose(id: String) {
        sockets[id]?.cancel(with: .goingAway, reason: nil)
        sockets[id] = nil
    }

    private func hostWsPing(id: String, cb: JSValue) {
        guard let task = sockets[id] else { q.async { cb.call(withArguments: [false]) }; return }
        task.sendPing { [weak self] error in
            self?.q.async { cb.call(withArguments: [error == nil]) }
        }
    }

    /// Invoke a JS callback by name on `q` (binds the context's queue).
    private func callJS(_ function: String, _ args: [Any]) {
        q.async { [weak self] in
            self?.context().objectForKeyedSubscript(function)?.call(withArguments: args)
        }
    }
}

extension CompanionPluginClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        if let id = webSocketTask.taskDescription { callJS("_onOpen", [id]) }
    }
    // Refuse redirects on all plugin egress (HTTP and the WS upgrade): no relay
    // endpoint legitimately returns a 3xx, and following one would re-send the
    // request to a host the response names. nil = do not follow.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if let id = webSocketTask.taskDescription {
            callJS("_onClosed", [id, closeCode.rawValue, String(data: reason ?? Data(), encoding: .utf8) ?? ""])
        }
    }

    // MARK: HTTP (per-request, concurrency-safe; no shared task state)

    private func performHTTP(method: String, url: String, headers: [String: String], body: Data,
                             completion: @escaping (String?, String?) -> Void) {
        guard let u = URL(string: url) else { completion(nil, "invalid url"); return }
        var request = URLRequest(url: u)
        request.httpMethod = method
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue(CompanionUserAgent.value, forHTTPHeaderField: "User-Agent")
        if !body.isEmpty {
            request.httpBody = body
            request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        }
        egressSession.dataTask(with: request) { data, response, error in
            if let error {
                completion(String(data: data ?? Data(), encoding: .utf8) ?? "", error.localizedDescription)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            if (200..<300).contains(status) {
                completion(text, "")
            } else {
                completion(text, "HTTP \(status)")
            }
        }.resume()
    }
}
