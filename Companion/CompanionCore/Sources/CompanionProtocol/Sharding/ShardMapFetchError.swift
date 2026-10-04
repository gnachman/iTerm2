//
//  ShardMapFetchError.swift
//  CompanionCore
//
//  Thrown when no source (the resolver or any mirror) produced a usable shard
//  map. Records every attempt so the failure can be explained in full: many
//  users debug their own networks, and "timed out" alone does not tell them
//  which server failed or how. The explanation is plain language, not error
//  codes.
//

import Foundation

public struct ShardMapFetchError: Error, LocalizedError, Sendable {
    public struct Attempt: Sendable {
        public let url: String
        public let error: Error
        /// How long the attempt ran before failing, when measured.
        public let duration: TimeInterval?
        /// Whether this source is a mirror rather than the primary. Recorded
        /// per attempt because the primary's attempt may be missing (a
        /// cancelled fetch is left out), so position cannot tell.
        public let isMirror: Bool

        public init(url: String, error: Error, duration: TimeInterval? = nil, isMirror: Bool = false) {
            self.url = url
            self.error = error
            self.duration = duration
            self.isMirror = isMirror
        }
    }

    /// One per source that failed, primary first.
    public let attempts: [Attempt]

    public init(attempts: [Attempt]) {
        self.attempts = attempts
    }

    /// True when every attempt failed in a way this network likely caused (no
    /// answer, or a reply that wasn't the list, as from a captive portal), so
    /// another network may help. False when a server answered with an HTTP
    /// error or an invalid list.
    public var isNetworkFailure: Bool {
        // An outdated mirror copy, or a source that was cut short, says nothing
        // about the network; the other sources' failures are the root cause.
        let decisive = attempts.map { Self.diagnosis($0.error, after: $0.duration).blame }
            .filter { $0 != .inconclusive }
        return !decisive.isEmpty && decisive.allSatisfy { $0 == .network }
    }

    /// One sentence naming every server tried and why each failed, primary
    /// first, then advice to try another network when every failure was in the
    /// network. It states what happened rather than guessing at a cause (a DNS
    /// failure and a timeout are different problems); details has the hints.
    public var summary: String {
        // "Its mirror" needs the primary named first; a mirror reported
        // without it must not pass for the primary.
        let namesPrimary = attempts.contains { !$0.isMirror }
        let clauses = attempts.map { attempt in
            let host = Self.host(attempt.url)
            let mirror = namesPrimary ? "its mirror \(host)" : "the mirror \(host)"
            let source = attempt.isMirror ? mirror : host
            return "\(source) because \(Self.diagnosis(attempt.error, after: attempt.duration).reason)"
        }
        let sentence = "Couldn’t get the list of relay servers from "
            + Self.joinedAsAlternatives(clauses, separator: ", or from ") + "."
        return withAdvice(sentence)
    }

    private func withAdvice(_ sentence: String) -> String {
        isNetworkFailure ? sentence + " Try another network or a VPN." : sentence
    }

    /// The summary when the whole fetch ran out of time before any source
    /// finished, so there is no per-source reason to give.
    public static func noAnswerSummary(urls: [String], within duration: TimeInterval) -> String {
        let sources = urls.enumerated().map { index, url in
            index == 0 ? host(url) : "its mirror \(host(url))"
        }
        // With no known source there is nothing to name.
        let from = sources.isEmpty ? "" : " from " + joinedAsAlternatives(sources, separator: " or from ")
        return "Couldn’t get the list of relay servers\(from) within \(seconds(duration))."
            + " Try another network or a VPN."
    }

    /// The details to go with noAnswerSummary: each host, and what no answer
    /// usually means.
    public static func noAnswerDetails(urls: [String], within duration: TimeInterval) -> String {
        urls.map { "\(host($0)): \(diagnosis(URLError(.timedOut), after: duration).explanation)" }
            .joined(separator: "\n\n")
    }

    /// A duration in whole seconds, rounded and never less than one: a wait of
    /// 0.4 seconds must not read as "0 seconds".
    static func seconds(_ duration: TimeInterval) -> String {
        let count = max(1, Int(duration.rounded()))
        return count == 1 ? "1 second" : "\(count) seconds"
    }

    static func host(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    /// "a", "a, or from b", "a, from b, or from c".
    static func joinedAsAlternatives(_ items: [String], separator: String) -> String {
        guard items.count > 2 else {
            return items.joined(separator: separator)
        }
        return items.dropLast().joined(separator: ", from ") + separator + items.last!
    }

    /// For each server tried, its host name and what went wrong in plain words,
    /// one paragraph per server. Deliberately free of error domains and codes:
    /// it says which step failed and what that usually means.
    public var details: String {
        attempts.map { attempt in
            "\(Self.host(attempt.url)): \(Self.diagnosis(attempt.error, after: attempt.duration).explanation)"
        }.joined(separator: "\n\n")
    }

    /// The summary alone, so it fits wherever an error is shown as one line
    /// of text; details is there for callers with room for it.
    public var errorDescription: String? {
        summary
    }

    /// Who a failure points at, for deciding whether to advise another network.
    enum Blame {
        /// This network likely caused it (no answer, or a reply that wasn't
        /// the list, as from a captive portal).
        case network
        /// A server answered with an error or an invalid list, or the request
        /// itself was at fault.
        case notNetwork
        /// Says nothing either way (an outdated copy, a source cut short).
        case inconclusive
    }

    /// Everything said about one failure. Kept in one table so the summary,
    /// the details, and the advice cannot drift apart.
    struct Diagnosis {
        /// Why the attempt failed, as a clause that follows "because".
        let reason: String
        /// What happened, and what it usually means. Deliberately free of
        /// error domains and codes.
        let explanation: String
        let blame: Blame
    }

    static func diagnosis(_ error: Error, after duration: TimeInterval?) -> Diagnosis {
        switch error {
        case let urlError as URLError:
            return diagnosis(urlError, after: duration)
        case let loaderError as ShardMapLoaderError:
            return diagnosis(loaderError, after: duration)
        case is ShardMap.ValidationError:
            return .init(reason: "its server list was incomplete or inconsistent",
                         explanation: "The server sent a server list that was incomplete or inconsistent.",
                         blame: .notNetwork)
        default:
            return .init(reason: "of an error (“\(String(describing: error))”)",
                         explanation: String(describing: error),
                         blame: .notNetwork)
        }
    }

    private static func diagnosis(_ error: ShardMapLoaderError, after duration: TimeInterval?) -> Diagnosis {
        switch error {
        case .httpStatus(let status):
            let answer = "(HTTP \(status), \(HTTPURLResponse.localizedString(forStatusCode: status)))"
            return .init(reason: "it answered with an error \(answer)",
                         explanation: "The server answered with an error \(answer).",
                         blame: .notNetwork)
        case .malformedMap:
            return .init(reason: "its reply wasn’t the server list",
                         explanation: "The server answered, but not with the server list. "
                             + "A captive portal (such as a Wi-Fi sign-in page) or a filtering proxy may have replaced the response.",
                         blame: .network)
        case .badResponse:
            return .init(reason: "its reply wasn’t an ordinary web response",
                         explanation: "The reply wasn’t an ordinary web response.",
                         blame: .network)
        case .invalidResolverURL(let url):
            return .init(reason: "its address isn’t valid",
                         explanation: "“\(url)” isn’t a valid address.",
                         blame: .notNetwork)
        case .requestFailed(let message):
            return .init(reason: "of an error (“\(message)”)",
                         explanation: message,
                         blame: .notNetwork)
        case let .outdatedMap(served, latestSeen):
            return .init(reason: "its copy is out of date",
                         explanation: "This copy of the server list is out of date (version \(served); "
                             + "this device has already seen version \(latestSeen)). "
                             + "It may not have caught up with a recent change yet.",
                         blame: .inconclusive)
        case .cutShort:
            let waited = duration.map { " after \(seconds($0))" } ?? ""
            return .init(reason: "it wasn’t given enough time to respond",
                         explanation: "Time ran out\(waited), before this server had a fair chance to answer. "
                             + "This says little about whether it can be reached.",
                         blame: .inconclusive)
        }
    }

    private static func diagnosis(_ error: URLError, after duration: TimeInterval?) -> Diagnosis {
        switch error.code {
        case .timedOut:
            let waited = duration.map { "No response after \(seconds($0))." } ?? "No response."
            return .init(reason: duration.map { "it didn’t respond within \(seconds($0))" } ?? "it didn’t respond",
                         explanation: waited + " The request went out but nothing came back, "
                             + "which usually means a firewall or filter on this network is silently dropping the traffic.",
                         blame: .network)
        case .cancelled:
            return .init(reason: "the request was cancelled",
                         explanation: "The request was cancelled before it finished.",
                         blame: .notNetwork)
        case .cannotFindHost, .dnsLookupFailed:
            return .init(reason: "its address couldn’t be looked up",
                         explanation: "Couldn’t look up the server’s address. "
                             + "This network’s DNS may be blocking the name or failing to resolve it.",
                         blame: .network)
        case .cannotConnectToHost:
            return .init(reason: "the connection was refused",
                         explanation: "The address was found, but the app couldn’t connect to it. "
                             + "The connection was refused or blocked.",
                         blame: .network)
        case .networkConnectionLost:
            return .init(reason: "the connection dropped",
                         explanation: "The connection dropped partway through.",
                         blame: .network)
        case .notConnectedToInternet:
            return .init(reason: "this device isn’t connected to the internet",
                         explanation: "This device isn’t connected to the internet.",
                         blame: .network)
        case .secureConnectionFailed:
            return .init(reason: "a secure connection couldn’t be set up",
                         explanation: "Couldn’t set up a secure connection. "
                             + "Something on this network may be interfering with encrypted traffic.",
                         blame: .network)
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return .init(reason: "its security certificate wasn’t trusted",
                         explanation: "The server’s security certificate wasn’t trusted. "
                             + "A captive portal, proxy, or filter may be intercepting the connection.",
                         blame: .network)
        case .dataNotAllowed:
            return .init(reason: "cellular data is turned off",
                         explanation: "Cellular data is turned off for this app or device.",
                         blame: .network)
        case .internationalRoamingOff:
            return .init(reason: "data roaming is turned off",
                         explanation: "Data roaming is turned off.",
                         blame: .network)
        default:
            // URLSession's own text is readable; Apple's fallback text for an
            // error without one only repeats the code, so it isn't used.
            let text = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
            return .init(reason: text.map { "of an error (“\($0)”)" } ?? "the request failed",
                         explanation: text ?? "The request failed.",
                         blame: .network)
        }
    }
}
