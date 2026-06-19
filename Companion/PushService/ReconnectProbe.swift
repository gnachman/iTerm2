//
//  ReconnectProbe.swift
//  iTerm2 Companion Push Service (Notification Service Extension)
//
//  TEMPORARY memory-spike (docs/push.txt Verification gate 0). Reconnects over
//  the relay + Noise channel using credentials the app exported to the shared
//  App Group container, logging os_proc_available_memory() before and after so
//  we can see how much of the NSE's ~24 MB budget the connect + Noise handshake
//  consume. No fetch yet: the message payload is bounded to a few KB by design
//  (Mac-side strip + truncate), so the connect/handshake floor is the unknown.
//  Remove with the rest of the spike scaffolding.
//

import Foundation
import os
import CompanionProtocol
import CompanionNoise
import CompanionTransport

enum ReconnectProbe {
    private static let appGroup = "group.com.googlecode.iterm2.companion"
    private static let fileName = "spike-creds.json"
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
            roomSecret: secretProvider)
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
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup) else {
            log.error("no App Group container")
            return nil
        }
        let url = container.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rkB64 = obj["responderStaticPublicKey"] as? String,
              let responderKey = Data(base64Encoded: rkB64),
              let pairingID = obj["pairingID"] as? String,
              let pkB64 = obj["noisePrivateKey"] as? String,
              let noisePrivateKey = Data(base64Encoded: pkB64) else {
            log.error("no/invalid spike creds in container")
            return nil
        }
        let relayOrigin = obj["relayOrigin"] as? String
        let roomSecret = (obj["roomSecret"] as? String).flatMap { Data(base64Encoded: $0) }
        return Creds(responderKey: responderKey,
                     pairingID: pairingID,
                     relayOrigin: relayOrigin,
                     noisePrivateKey: noisePrivateKey,
                     roomSecret: roomSecret)
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
