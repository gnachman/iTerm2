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
        var request = URLRequest(url: CompanionPushRelay.pushURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(PushRequest(token: token,
                                                                secret: secret,
                                                                title: title,
                                                                body: body))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SendError(message: "The push relay returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(RelayReply.self, from: data))?.error
                ?? String(data: data, encoding: .utf8)
                ?? ""
            DLog("Companion push: relay rejected send (\(http.statusCode)): \(detail)")
            throw SendError(message: "The push relay refused the notification (\(http.statusCode)): \(detail)")
        }
        DLog("Companion push: delivered “\(title)” via relay")
    }
}
