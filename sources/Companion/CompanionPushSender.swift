//
//  CompanionPushSender.swift
//  iTerm2
//
//  Sends a push notification to the paired phone through the relay Worker
//  (Companion/PushRelay), presenting the phone-minted secret that authorizes
//  pushes to that device. The relay holds the APNs signing key and talks to
//  Apple.
//

import Foundation
import CompanionProtocol

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
        try await post(url: CompanionPushRelay.pushURL,
                       request: PushRequest(token: token, secret: secret, title: title, body: body),
                       label: "“\(title)”")
    }

    /// Content-free push that wakes the phone's Notification Service Extension,
    /// collapsed per chat by the opaque token (HMAC(roomSecret, chatID)). No
    /// content crosses the relay; the NSE fetches it over Noise. Used for the
    /// LEGACY per-chat push to revision-1 phones.
    static func sendMutable(collapse: String, nonce: String?) async throws {
        let (token, secret) = try credentials()
        try await post(url: CompanionPushRelay.mutablePushURL,
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
        try await post(url: CompanionPushRelay.mutablePushURL,
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
                RLog("Companion push: sent \(useWakeup ? "wakeup" : "legacy") push")
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

    private static func post(url: URL, request: some Encodable, label: String) async throws {
        // Route through the consent plugin: it is the companion's only outbound
        // HTTP path, so the push goes the same way as the relay socket.
        guard case .success(let plugin) = CompanionPlugin.instance() else {
            throw SendError(message: "The companion plugin is not installed.")
        }
        let bodyJSON = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let response = try await plugin.client.request(method: "POST",
                                                       url: url.absoluteString,
                                                       headers: ["Content-Type": "application/json"],
                                                       body: bodyJSON)
        // The plugin reports a 2xx as an empty error; anything else carries
        // "HTTP <status>" (or a transport error), with the body in `data`.
        guard response.error.isEmpty else {
            let detail = (try? JSONDecoder().decode(RelayReply.self, from: Data(response.data.utf8)))?.error
                ?? response.data
            RLog("Companion push: relay rejected send (\(response.error)): \(detail)")
            throw SendError(message: "The push relay refused the notification (\(response.error)): \(detail)")
        }
        RLog("Companion push: delivered \(label) via relay")
    }
}
