//
//  CompanionPushRelay.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  Where the push relay (Companion/PushRelay) lives. The phone registers its
//  APNs token there ( /register ) and the Mac sends notifications through it
//  ( /push ).
//
//  There are several instances on different providers, for redundancy. The
//  phone registers with the first one that answers, and that instance passes
//  the registration on to the others (Companion/PushRelay/host/peer.js). The
//  Mac tries them in order, moving on when one is unreachable or doesn't know
//  the device yet. Failover lives in the clients rather than a load balancer so
//  nothing is billed per request.
//

import Foundation

enum CompanionPushRelay {
    /// In the order the phone and the Mac try them.
    static let baseURLs = [
        URL(string: "https://push.iterm2.com")!,
        URL(string: "https://push2.iterm2.com")!,
    ]

    static var registerURLs: [URL] { baseURLs.map { $0.appendingPathComponent("register") } }
    static var pushURLs: [URL] { baseURLs.map { $0.appendingPathComponent("push") } }
    /// Content-free push that wakes the Notification Service Extension.
    static var mutablePushURLs: [URL] { baseURLs.map { $0.appendingPathComponent("push/mutable") } }

    /// Whether a failed request should move on to the next instance. `status` is
    /// nil for a transport error. `relayAnswered` is whether the body is the
    /// relay's own error reply (see isRelayError) rather than a page from a
    /// proxy, WAF, or misrouted vhost in front of it. Only a status in
    /// `finalStatuses` from the relay itself is final. By default that's 400
    /// (the request itself is invalid: every instance runs the same code) and
    /// 429 (the Mac's per-device push limit, which failing over would dodge).
    /// The phone's registration passes just 400: its 429 is a per-IP limit
    /// each instance keeps separately (e.g. many phones behind one CGNAT), so
    /// another instance may well accept it. Anything else may be specific to
    /// that host.
    static let defaultFinalStatuses: Set<Int> = [400, 429]

    static func shouldTryNextInstance(afterStatus status: Int?,
                                      relayAnswered: Bool,
                                      finalStatuses: Set<Int> = defaultFinalStatuses) -> Bool {
        guard let status, relayAnswered else {
            return true
        }
        return !finalStatuses.contains(status)
    }

    /// Whether `body` is the relay's own error reply: JSON with an "error" string.
    static func isRelayError(_ body: Data) -> Bool {
        struct Reply: Decodable {
            var error: String
        }
        return (try? JSONDecoder().decode(Reply.self, from: body)) != nil
    }

    enum AttemptResult: Equatable {
        case succeeded
        /// `status` is nil for a transport error; see shouldTryNextInstance.
        case failed(status: Int?, relayAnswered: Bool)
        /// Failed in a way every instance would repeat, whatever the status.
        case rejected
    }

    struct Outcome: Equatable {
        /// The URL that succeeded, or nil if none did.
        var succeeded: URL?
        /// Whether an earlier URL failed and the next one was tried.
        var failedOver: Bool
    }

    /// Tries `urls` in order until one succeeds, moving past a failure only when
    /// shouldTryNextInstance allows it. Shared by the phone's registration and
    /// the Mac's pushes.
    static func tryInOrder(_ urls: [URL],
                           finalStatuses: Set<Int> = defaultFinalStatuses,
                           attempt: (URL) async -> AttemptResult) async -> Outcome {
        var failedOver = false
        for url in urls {
            switch await attempt(url) {
            case .succeeded:
                return Outcome(succeeded: url, failedOver: failedOver)
            case .failed(let status, let relayAnswered):
                guard shouldTryNextInstance(afterStatus: status, relayAnswered: relayAnswered,
                                            finalStatuses: finalStatuses) else {
                    return Outcome(succeeded: nil, failedOver: failedOver)
                }
                failedOver = true
            case .rejected:
                return Outcome(succeeded: nil, failedOver: failedOver)
            }
        }
        return Outcome(succeeded: nil, failedOver: failedOver)
    }

    /// `urls` with the one on `preferredHost` moved to the front, the rest in
    /// their usual order.
    static func ordered(_ urls: [URL], preferringHost preferredHost: String?) -> [URL] {
        guard let preferredHost,
              let index = urls.firstIndex(where: { $0.host == preferredHost }) else {
            return urls
        }
        var result = urls
        result.insert(result.remove(at: index), at: 0)
        return result
    }
}
