//
//  CompanionPushSender.swift
//  iTerm2
//
//  Sends a push notification to the paired phone through the push relay
//  (Companion/PushRelay), presenting the phone-minted secret that authorizes
//  pushes to that device. The relay holds the APNs signing key and talks to
//  Apple.
//

import Foundation
import CompanionProtocol
import os

enum CompanionPushSender {
    struct SendError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct PushRequest: Encodable {
        var token: String
        var secret: String
        var title: String
        var body: String
    }

    private struct MutablePushRequest: Encodable {
        var token: String
        var secret: String
        var collapse: String
        /// One-time nonce the NSE echoes back over the relay so the mac can
        /// recognize its own solicited fetch (omitted when nil).
        var nonce: String?
    }

    private struct RelayReply: Decodable {
        var ok: Bool?
        var error: String?
    }

    /// Plaintext alert (the notify tool): the title/body are visible to Apple.
    static func send(title: String, body: String) async throws {
        let (token, secret) = try credentials()
        try await post(urls: CompanionPushRelay.pushURLs,
                       request: PushRequest(token: token, secret: secret, title: title, body: body),
                       label: "“\(title)”")
    }

    /// Content-free push that wakes the phone's Notification Service Extension,
    /// collapsed per chat by the opaque token (HMAC(roomSecret, chatID)). No
    /// content crosses the relay; the NSE fetches it over Noise. Used for the
    /// LEGACY per-chat push to revision-1 phones.
    static func sendMutable(collapse: String, nonce: String?) async throws {
        let (token, secret) = try credentials()
        try await post(urls: CompanionPushRelay.mutablePushURLs,
                       request: MutablePushRequest(token: token, secret: secret,
                                                   collapse: collapse, nonce: nonce),
                       label: "mutable (collapse \(collapse))")
    }

    /// Content-free "wakeup" for revision-2 phones: the same mutable push but with
    /// the fixed all-zeros sentinel collapse id, so it carries NO per-chat identity
    /// (the relay/Apple see one indistinguishable wakeup, and queued wakeups
    /// coalesce while the phone is offline). The NSE recognizes the sentinel and
    /// runs the unified syncSince fetch.
    static func sendWakeup(nonce: String?) async throws {
        let (token, secret) = try credentials()
        try await post(urls: CompanionPushRelay.mutablePushURLs,
                       request: MutablePushRequest(token: token, secret: secret,
                                                   collapse: CompanionPushWakeup.collapseSentinel,
                                                   nonce: nonce),
                       label: "wakeup")
    }

    /// Fire-and-forget a content-free push to the paired phone, choosing the
    /// format by the phone's known protocol revision: a contentless WAKEUP for
    /// revision >= 2 (one indistinguishable push; the NSE runs the unified
    /// syncSince), or the LEGACY per-chat collapse push for older phones. Handles
    /// the one-time nonce (mint, seal under the room secret, record only if the
    /// push went out) shared by the chat notifier and the alert bridge.
    ///
    /// `chatID` supplies the legacy collapse token; pass nil from the alert bridge
    /// (alerts only fire for revision >= 2, which never needs a collapse token).
    @MainActor
    static func dispatchPush(chatID: String?) {
        guard let roomSecret = CompanionMacIdentity.pairedRoomSecret() else {
            RLog("Companion push: no room secret; skipping push")
            return
        }
        let useWakeup = CompanionPushRegistry.supportsContentlessWakeup
        // The legacy path needs a per-chat collapse token; the wakeup never does.
        let collapse: String?
        if useWakeup {
            collapse = nil
        } else if let chatID {
            collapse = CompanionCollapseToken.make(roomSecret: roomSecret, chatID: chatID)
        } else {
            // A revision-1 phone with no chat context: nothing to collapse on, so
            // there is no legacy push to send (this is only reached if an alert
            // were ever dispatched to an old phone, which the gate prevents).
            RLog("Companion push: legacy phone with no chatID; nothing to send")
            return
        }
        let nonce = CompanionPushNonceRegistry.shared.mintNonce()
        let sealedNonce = try? CompanionPushNonceCrypto.seal(nonce: nonce, roomSecret: roomSecret)
        // Record BEFORE sending (synchronously, on the main actor) when the nonce
        // will ride out in the push. Recording after the send left a window where
        // the app could be suspended/terminated between send and record - common
        // when a push fires as the app backgrounds - so the nonce went out but was
        // never recorded, and the NSE's echo was then misclassified as an
        // unsolicited connection (spurious presence warning). A genuinely failed
        // send is undone below, so this still doesn't keep a slot for a push that
        // never went out.
        if sealedNonce != nil {
            CompanionPushNonceRegistry.shared.record(nonce)
        }
        Task {
            do {
                if useWakeup {
                    try await sendWakeup(nonce: sealedNonce)
                } else if let collapse {
                    try await sendMutable(collapse: collapse, nonce: sealedNonce)
                }
                RLog("Companion push: sent \(useWakeup ? "wakeup" : "legacy") push\(chatID.map { " (trigger chat \($0))" } ?? " (no chat context)")")
            } catch {
                // The push didn't go out, so free the slot we optimistically took.
                if sealedNonce != nil {
                    await MainActor.run { CompanionPushNonceRegistry.shared.unrecord(nonce) }
                }
                RLog("Companion push: push failed: \(error)")
            }
        }
    }

    private static func credentials() throws -> (token: String, secret: String) {
        guard let token = CompanionPushRegistry.deviceTokenHex,
              let secret = CompanionPushRegistry.relaySecretHex else {
            throw SendError(message: "No paired phone is registered for notifications.")
        }
        return (token, secret)
    }

    /// After a push had to fail over, the instance that delivered it is tried
    /// first until `until`, so a dead primary doesn't hold up every push by its
    /// timeout (15-30s). It is not renewed by later successes, so the usual order
    /// is retried every few minutes and traffic returns to the primary once it
    /// recovers.
    private struct Preference {
        var host: String
        var until: Date
    }
    private static let preference = OSAllocatedUnfairLock<Preference?>(initialState: nil)
    private static let preferenceDuration: TimeInterval = 5 * 60

    /// Tries each relay instance (see CompanionPushRelay.tryInOrder), stopping at
    /// the first that delivers.
    ///
    /// A transport error can happen after the relay already handed the push to
    /// APNs (e.g. a timeout waiting for its reply), so failing over can deliver a
    /// push twice. Mutable pushes collapse by id, so only a plaintext /push could
    /// show two alerts. That is accepted: the alternative, not failing over on a
    /// timeout, would lose pushes whenever a relay hangs.
    private static func post(urls: [URL], request: some Encodable, label: String) async throws {
        // Route through the consent plugin: it is the companion's only outbound
        // HTTP path, so the push goes the same way as the relay socket.
        guard case .success(let plugin) = CompanionPlugin.instance() else {
            throw SendError(message: "The companion plugin is not installed.")
        }
        let bodyJSON = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let preferredHost = preference.withLock { preference -> String? in
            guard let preference, preference.until > Date() else {
                return nil
            }
            return preference.host
        }
        var lastError: Error = SendError(message: "No push relay is configured.")
        let outcome = await CompanionPushRelay.tryInOrder(
            CompanionPushRelay.ordered(urls, preferringHost: preferredHost)) { url in
            let host = url.host ?? url.absoluteString
            let response: CompanionPluginClient.WebResponse
            do {
                response = try await plugin.client.request(method: "POST",
                                                           url: url.absoluteString,
                                                           headers: ["Content-Type": "application/json"],
                                                           body: bodyJSON)
            } catch {
                RLog("Companion push: relay \(host) request failed: \(error)")
                lastError = error
                if host == preferredHost {
                    preference.withLock { $0 = nil }
                }
                return .failed(status: nil, relayAnswered: false)
            }
            // The plugin reports a 2xx as an empty error; anything else carries
            // "HTTP <status>" (or a transport error), with the body in `data`.
            guard response.error.isEmpty else {
                let relayError = (try? JSONDecoder().decode(RelayReply.self, from: Data(response.data.utf8)))?.error
                let detail = relayError ?? response.data
                let reason = CompanionPluginHTTPError.decode(response.error).message
                RLog("Companion push: relay \(host) rejected send (\(reason)): \(detail)")
                lastError = SendError(message: "The push relay refused the notification (\(reason)): \(detail)")
                if host == preferredHost {
                    // It worked a moment ago but not now; go back to the usual order.
                    preference.withLock { $0 = nil }
                }
                return attemptResult(pluginError: response.error, body: response.data,
                                     onPreferredSecondary: host == preferredHost && host != primaryHost)
            }
            return .succeeded
        }
        guard let url = outcome.succeeded else {
            throw lastError
        }
        let host = url.host ?? url.absoluteString
        RLog("Companion push: delivered \(label) via relay \(host)")
        if outcome.failedOver && host != primaryHost {
            let until = Date().addingTimeInterval(preferenceDuration)
            preference.withLock { $0 = Preference(host: host, until: until) }
        } else if host == primaryHost {
            preference.withLock { $0 = nil }
        }
    }

    private static var primaryHost: String? { CompanionPushRelay.baseURLs.first?.host }

    /// How a failed relay response (the plugin's error string and the body)
    /// counts for failover. Judged by the body first: Cloudflare replaces an
    /// origin 5xx with its own page, so a relay's JSON only survives on a status
    /// Cloudflare passes through (the relay sends shared APNs rejections as 422
    /// for that reason).
    ///
    /// A relay's 403 "bad secret" is final too: it means the phone re-paired and
    /// this Mac's secret was revoked. Failing over would let the revoked Mac
    /// push through a relay the new secret hasn't reached yet. (The cost: if the
    /// phone re-paired via the other relay while this one was down, the new
    /// Mac's pushes fail here until replication catches this relay up, which it
    /// does as soon as it hears from its peer again.) "unknown device token"
    /// still fails over: the registration may simply not have arrived here.
    ///
    /// Except on a relay tried first only because of the failover preference
    /// (`onPreferredSecondary`): the phone registers with the primary first, so
    /// right after a re-pair the preferred relay is the one most likely to be
    /// behind. There "bad secret" moves on to the primary instead.
    static func attemptResult(pluginError: String,
                              body: String,
                              onPreferredSecondary: Bool = false) -> CompanionPushRelay.AttemptResult {
        let data = Data(body.utf8)
        if let relayError = (try? JSONDecoder().decode(RelayReply.self, from: data))?.error {
            if isSharedAPNsRejection(relayError) {
                return .rejected
            }
            if relayError == "bad secret" && httpStatus(pluginError: pluginError) == 403 {
                return onPreferredSecondary ? .failed(status: 403, relayAnswered: true) : .rejected
            }
        }
        return .failed(status: httpStatus(pluginError: pluginError),
                       relayAnswered: CompanionPushRelay.isRelayError(data))
    }

    /// Whether the relay's error is APNs rejecting the push itself (the relay
    /// reports it as "APNs <status>: <reason>"), e.g. 410 Unregistered,
    /// 400 BadDeviceToken, or 429 TooManyRequests. Every relay sends with the
    /// same key and topic, so another would get the same answer, and retrying a
    /// 429 elsewhere would double the rate that caused it. A 403 is excluded:
    /// that relay's key or provider token may be bad while another's is fine.
    ///
    /// Also excluded: 400 reasons that come from the relay's own APNS_TOPIC
    /// rather than the device, since another relay may be configured correctly.
    /// Mirrors isSharedApnsRejection in Companion/PushRelay/host/server.js.
    static func isSharedAPNsRejection(_ relayError: String) -> Bool {
        guard relayError.hasPrefix("APNs 4"), !relayError.hasPrefix("APNs 403") else {
            return false
        }
        struct Reason: Decodable {
            var reason: String
        }
        let detail = relayError.drop(while: { $0 != "{" })
        let reason = (try? JSONDecoder().decode(Reason.self, from: Data(detail.utf8)))?.reason
        return !relayConfigAPNsReasons.contains(reason ?? "")
    }

    private static let relayConfigAPNsReasons: Set<String> = [
        "BadTopic", "TopicDisallowed", "MissingTopic", "DeviceTokenNotForTopic",
    ]

    /// The status in the plugin's "HTTP <status>" error, or nil for a transport
    /// error (or anything unrecognized).
    static func httpStatus(pluginError: String) -> Int? {
        guard pluginError.hasPrefix("HTTP ") else {
            return nil
        }
        return Int(pluginError.dropFirst("HTTP ".count))
    }
}
