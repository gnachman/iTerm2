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

    private struct RelayReply: Decodable {
        var ok: Bool?
        var error: String?
    }

    static func send(title: String, body: String) async throws {
        guard let token = CompanionPushRegistry.deviceTokenHex,
              let secret = CompanionPushRegistry.relaySecretHex else {
            throw SendError(message: "No paired phone is registered for notifications.")
        }
        // Route through the consent plugin: it is the companion's only outbound
        // HTTP path, so the push goes the same way as the relay socket.
        guard case .success(let plugin) = CompanionPlugin.instance() else {
            throw SendError(message: "The companion plugin is not installed.")
        }
        let bodyJSON = String(decoding: try JSONEncoder().encode(PushRequest(token: token,
                                                                             secret: secret,
                                                                             title: title,
                                                                             body: body)),
                              as: UTF8.self)
        let response = try await plugin.client.request(method: "POST",
                                                       url: CompanionPushRelay.pushURL.absoluteString,
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
        DLog("Companion push: delivered “\(title)” via relay")
    }
}
