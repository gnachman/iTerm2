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
    /// content crosses the relay; the NSE fetches it over Noise.
    static func sendMutable(collapse: String) async throws {
        let (token, secret) = try credentials()
        try await post(url: CompanionPushRelay.mutablePushURL,
                       request: MutablePushRequest(token: token, secret: secret, collapse: collapse),
                       label: "mutable (collapse \(collapse))")
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
            DLog("Companion push: relay rejected send (\(response.error)): \(detail)")
            throw SendError(message: "The push relay refused the notification (\(response.error)): \(detail)")
        }
        DLog("Companion push: delivered \(label) via relay")
    }
}
