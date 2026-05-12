//
//  MomentermLocalhostURLScanner.swift
//  iTerm2
//
//  Watches plain-text terminal output for `http(s)://localhost:PORT` URLs
//  and posts a notification when a new one shows up. The right-side browser
//  panel subscribes and auto-navigates so editing → save → refresh becomes
//  editing → save (the panel follows on its own).
//
//  Strict matching: only localhost / 127.0.0.1 / 0.0.0.0 are accepted so a
//  random URL printed in a man page or doc doesn't kidnap the panel.
//

import Foundation

@objc final class MomentermLocalhostURLScanner: NSObject {

    @objc static let shared = MomentermLocalhostURLScanner()

    /// userInfo["url"] = String, userInfo["sessionGUID"] = String
    @objc static let didDetectNotification = Notification.Name("MomentermLocalhostDidDetect")

    private static let regex: NSRegularExpression = {
        // Accept localhost, 127.0.0.1, 0.0.0.0, optionally followed by :PORT/path.
        // Cap path at 256 chars to avoid pathological lines.
        let pattern = #"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d{1,5})?(?:/[^\s'\"<>]{0,256})?"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private let queue = DispatchQueue(label: "com.momenterm.localhost-scanner")
    private var bufferBySession: [String: String] = [:]
    private var lastURLBySession: [String: String] = [:]
    private var debounceBySession: [String: DispatchWorkItem] = [:]
    private let bufferCap = 4096
    private let debounceInterval: DispatchTimeInterval = .milliseconds(200)

    private override init() { super.init() }

    // MARK: - Public

    /// Feed a chunk of plain-text screen output for the given session. Safe
    /// to call from PTYSession's main-queue delegate callback; processing is
    /// offloaded to the scanner's own serial queue.
    @objc func ingest(_ text: String, sessionGUID: String) {
        guard !text.isEmpty, !sessionGUID.isEmpty else { return }
        queue.async { [weak self] in self?.process(text: text, sessionGUID: sessionGUID) }
    }

    /// Forget per-session state. Called when a session is closed so memory
    /// doesn't grow unbounded.
    @objc func resetSession(_ sessionGUID: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.bufferBySession.removeValue(forKey: sessionGUID)
            self.lastURLBySession.removeValue(forKey: sessionGUID)
            self.debounceBySession[sessionGUID]?.cancel()
            self.debounceBySession.removeValue(forKey: sessionGUID)
        }
    }

    /// Last URL detected for the session, or nil. Useful when the panel
    /// becomes visible *after* the URL was emitted so we don't miss it.
    @objc func lastURL(forSession sessionGUID: String) -> String? {
        var result: String?
        queue.sync { result = lastURLBySession[sessionGUID] }
        return result
    }

    // MARK: - Implementation

    private func process(text: String, sessionGUID: String) {
        var buf = bufferBySession[sessionGUID, default: ""]
        buf.append(text)
        if buf.count > bufferCap {
            buf = String(buf.suffix(bufferCap))
        }
        bufferBySession[sessionGUID] = buf

        let nsBuf = buf as NSString
        let range = NSRange(location: 0, length: nsBuf.length)
        let matches = Self.regex.matches(in: buf, options: [], range: range)
        guard let last = matches.last else { return }
        let url = nsBuf.substring(with: last.range)

        if lastURLBySession[sessionGUID] == url { return }
        lastURLBySession[sessionGUID] = url

        debounceBySession[sessionGUID]?.cancel()
        let work = DispatchWorkItem {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: MomentermLocalhostURLScanner.didDetectNotification,
                    object: nil,
                    userInfo: ["url": url, "sessionGUID": sessionGUID])
            }
        }
        debounceBySession[sessionGUID] = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
