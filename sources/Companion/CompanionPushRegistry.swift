//
//  CompanionPushRegistry.swift
//  iTerm2
//
//  Holds the paired phone's push capability, reported over the companion
//  protocol on every connection: notification-permission state, the APNs
//  device token, and the phone-minted secret the relay requires (see
//  Companion/PushRelay). The orchestrator's notify tool keys off canNotify,
//  and everything here is destroyed with the rest of the pairing state on
//  unpair.
//

import Foundation

enum CompanionPushRegistry {
    private static let tokenKey = "NoSyncCompanionPushToken"
    private static let secretKey = "NoSyncCompanionPushRelaySecret"
    private static let sandboxKey = "NoSyncCompanionPushTokenSandbox"
    private static let authorizationKey = "NoSyncCompanionPushAuthorization"

    /// The paired phone's APNs device token as lowercase hex, or nil when no
    /// device has registered.
    static var deviceTokenHex: String? {
        iTermUserDefaults.userDefaults().string(forKey: tokenKey)
    }

    /// The phone-minted relay secret as lowercase hex; presented to the push
    /// relay with each send so only the paired Mac can notify this phone.
    static var relaySecretHex: String? {
        iTermUserDefaults.userDefaults().string(forKey: secretKey)
    }

    /// True when the token came from a development (sandbox) build, which
    /// must be sent through APNs' sandbox environment.
    static var sandbox: Bool {
        iTermUserDefaults.userDefaults().bool(forKey: sandboxKey)
    }

    /// The phone's notification-permission state as of its last report (the
    /// user can change it in iOS Settings between connections).
    static var authorization: CompanionPushAuthorization {
        guard let raw = iTermUserDefaults.userDefaults().string(forKey: authorizationKey),
              let value = CompanionPushAuthorization(rawValue: raw) else {
            return .notDetermined
        }
        return value
    }

    /// True when a notification could actually be delivered right now.
    static var canNotify: Bool {
        authorization == .authorized && deviceTokenHex != nil && relaySecretHex != nil
    }

    /// True when a companion device is paired, whether or not it is
    /// connected right now. Push-related prompt guidance keys off this so
    /// users without a companion device never see it.
    static var devicePaired: Bool {
        iTermUserDefaults.userDefaults()
            .string(forKey: CompanionPairingController.pairedPIDKey) != nil
    }

    /// True when asking for permission could possibly succeed: iOS only ever
    /// shows the prompt while the state is notDetermined; after a decline,
    /// only the Settings app can change it. Gating the request tool on this
    /// keeps the model from badgering a user who already said no.
    static var canPromptForPermission: Bool {
        phoneIsConnected && authorization == .notDetermined
    }

    // Whether a companion phone is connected right now. Mirrors the pairing
    // controller's bridge (main actor) behind a lock so the tool-registration
    // path, which is not actor-isolated, can read it.
    private static let connectionLock = NSLock()
    private static var connectionFlag = false

    static var phoneIsConnected: Bool {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return connectionFlag
    }

    static func setPhoneConnected(_ connected: Bool) {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        connectionFlag = connected
    }

    /// Apply a pushStatus report from the phone.
    static func update(authorization: CompanionPushAuthorization,
                       token: Data?,
                       relaySecret: Data?,
                       sandbox: Bool) {
        let defaults = iTermUserDefaults.userDefaults()
        defaults.set(authorization.rawValue, forKey: authorizationKey)
        defaults.set(sandbox, forKey: sandboxKey)
        if let token {
            defaults.set(token.map { String(format: "%02x", $0) }.joined(), forKey: tokenKey)
        }
        if let relaySecret {
            defaults.set(relaySecret.map { String(format: "%02x", $0) }.joined(), forKey: secretKey)
        }
        DLog("Companion push: status \(authorization.rawValue), token \(token != nil ? "present" : "absent"), secret \(relaySecret != nil ? "present" : "absent"), sandbox \(sandbox); canNotify=\(canNotify)")
    }

    static func clear() {
        let defaults = iTermUserDefaults.userDefaults()
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: secretKey)
        defaults.removeObject(forKey: sandboxKey)
        defaults.removeObject(forKey: authorizationKey)
        DLog("Companion push: cleared device registration")
    }
}
