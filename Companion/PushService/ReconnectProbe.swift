//
//  ReconnectProbe.swift
//  iTerm2 Companion Push Service (Notification Service Extension)
//
//  Memory-spike + reconnect probe (docs/push.txt Verification gate 0).
//  Reconnects over the relay + Noise channel using the real shared credentials
//  (the Noise key + room secret from the App Group keychain group, the pairing
//  code from the App Group defaults - section 7), joining NON-displacing so it
//  yields to a foreground app. Logs os_proc_available_memory() across the
//  connect + handshake. No fetch yet: that arrives with the real NSE shell
//  (section 6), which replaces this probe.
//

import Foundation
import os
import Security
import CompanionProtocol
import CompanionNoise
import CompanionTransport

enum ReconnectProbe {
    private static let appGroup = "group.com.googlecode.iterm2.companion"
    private static let keychainService = "com.googlecode.iterm2.companion"
    private static let noiseAccount = "noise-static-private-key"
    private static let roomSecretAccount = "relay-room-secret"
    private static let log = Logger(subsystem: "com.googlecode.iterm2.companion.PushService",
                                    category: "spike")

    private enum ProbeError: Error { case noCreds, deadline }

    private struct Creds {
        let responderKey: Data
        let pairingID: String
        let relayOrigin: String?
        let noisePrivateKey: Data
        let roomSecret: Data?
    }

    static func run(deadline: Duration) async {
        logMem("start")
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await connectAndHandshake() }
                group.addTask {
                    try await Task.sleep(for: deadline)
                    throw ProbeError.deadline
                }
                // Wait for the first task to finish (connect success/failure or
                // the deadline), then cancel the other. CAVEAT: cancelAll() only
                // sets the cooperative cancel flag; it does NOT unblock a
                // connectAndHandshake() stuck in URLSessionWebSocketTask.receive()
                // (which ignores Swift cancellation). So on a mid-handshake stall
                // this still awaits the connect child until URLSession's own
                // timeout - run() is NOT hard-bounded by `deadline`. The production
                // NSE must hard-cancel the transport instead (docs/push.txt
                // section 6); tolerated here as throwaway measurement code.
                try await group.next()
                group.cancelAll()
            }
        } catch {
            log.error("probe failed: \(String(describing: error), privacy: .public)")
        }
        logMem("end")
    }

    private static func connectAndHandshake() async throws {
        guard let creds = loadCreds() else { throw ProbeError.noCreds }
        let code = PairingCode(responderStaticPublicKey: creds.responderKey,
                               pairingID: creds.pairingID,
                               relayOrigin: creds.relayOrigin)
        let identity = try NoiseKeyPair.from(privateKey: creds.noisePrivateKey)
        // Capture the optional secret by value; a closure returning nil is
        // equivalent to passing no provider (open-mode join), so we avoid a
        // nil-vs-closure ternary that crashes type inference.
        let roomSecret = creds.roomSecret
        let secretProvider: @Sendable () -> Data? = { roomSecret }
        let connector = CompanionTransports.connector(
            for: code,
            roomSecret: secretProvider,
            nonDisplacing: true)
        let transport = try await connector.connect(
            to: PairingRendezvous(pairingID: code.pairingID),
            timeout: 10)
        logMem("transport connected")
        let channel = try await NoiseHandshake.perform(
            role: .initiator,
            transport: transport,
            localKeyPair: identity,
            remoteStaticPublicKey: code.responderStaticPublicKey,
            prologue: code.handshakePrologue())
        logMem("handshake complete")
        await channel.close()
    }

    private static func loadCreds() -> Creds? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let responderKey = defaults.data(forKey: "PairedResponderStaticKey"),
              responderKey.count == 32,
              let pairingID = defaults.string(forKey: "PairedPairingID") else {
            log.error("no pairing code in App Group defaults")
            return nil
        }
        guard let noisePrivateKey = keychainData(account: noiseAccount) else {
            log.error("no Noise key in App Group keychain")
            return nil
        }
        return Creds(responderKey: responderKey,
                     pairingID: pairingID,
                     relayOrigin: defaults.string(forKey: "PairedRelayOrigin"),
                     noisePrivateKey: noisePrivateKey,
                     roomSecret: keychainData(account: roomSecretAccount))
    }

    /// Read a 32-byte item from the shared App Group keychain access group.
    private static func keychainData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: appGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else {
            return nil
        }
        return data
    }

    /// os_proc_available_memory() returns the bytes this process may still
    /// allocate before iOS jetsam-kills it: a direct read of headroom against
    /// the extension's hard ceiling.
    private static func logMem(_ label: String) {
        let available = os_proc_available_memory()
        let mb = Double(available) / (1024 * 1024)
        log.log("MEM[\(label, privacy: .public)] available=\(mb, privacy: .public) MB (\(available, privacy: .public) bytes)")
    }
}
