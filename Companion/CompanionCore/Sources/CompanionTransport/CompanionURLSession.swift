//
//  CompanionURLSession.swift
//  CompanionCore
//
//  A URLSession that REFUSES HTTP redirects, used for every companion relay and
//  push request. None of those endpoints ever legitimately returns a 3xx (they
//  answer 200/4xx/JSON, or 101 for the WebSocket upgrade), and URLSession
//  follows redirects by default, re-sending the request, with its headers and
//  body, to a host the server names in Location. A malicious or compromised
//  relay could use that to redirect egress to an attacker. Refusing surfaces the
//  3xx to the caller as the final response instead of following it.
//

import Foundation

public enum CompanionURLSession {
    /// A shared no-redirect session for one-shot relay/push REST calls and the
    /// phone's relay WebSocket.
    public static let shared: URLSession = make()

    /// Build a no-redirect session over `configuration` (tests inject a stub
    /// protocol; production uses the default).
    public static func make(configuration: URLSessionConfiguration = .default) -> URLSession {
        URLSession(configuration: configuration,
                   delegate: NoRedirectSessionDelegate.shared,
                   delegateQueue: nil)
    }
}

/// Stateless task delegate whose only job is to decline every redirect. Shared
/// across sessions since it holds no per-session state.
final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectSessionDelegate()

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // nil = do not follow; the original 3xx becomes the task's response.
        completionHandler(nil)
    }
}
