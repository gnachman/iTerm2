//
//  ReconnectProbe.swift  (defines NSEFetcher)
//  iTerm2 Companion Push Service (Notification Service Extension)
//
//  NSEFetcher: the NSE's one network operation. Reads the shared credentials
//  (Noise key + room secret from the App Group keychain group, pairing code
//  from the App Group defaults), reconnects to the Mac NON-displacing over the
//  relay + Noise channel, sends the slim messagesSince request, and returns the
//  reply for PushFetchCoordinator. It holds the channel/transport so the shell
//  can HARD-cancel on its deadline (URLSession's receive ignores cooperative
//  cancellation). Package-only: no chat-model types.
//
//  (Filename kept from the memory-spike probe to avoid a project-file churn; the
//  type is NSEFetcher.)
//

import Foundation
import os
import Security
import CompanionProtocol
import CompanionNoise
import CompanionTransport

actor NSEFetcher {
    enum FetchError: Error { case noCreds, hostError }

    // Shared identifiers come from CompanionProtocol so they can't drift from
    // the app's PhoneIdentity / AppModel.
    private let appGroup: String
    private let keychainService = CompanionSharedIdentifiers.keychainService
    private let noiseAccount = CompanionSharedIdentifiers.noiseStaticPrivateKeyAccount
    private let roomSecretAccount = CompanionSharedIdentifiers.roomSecretAccount
    private static let log = Logger(subsystem: "com.googlecode.iterm2.companion.PushService",
                                    category: "nse")

    private var channel: NoiseChannel?
    private var transport: MessageTransport?

    init(appGroup: String) {
        self.appGroup = appGroup
    }

    func fetch(collapseToken token: String,
               sinceSeq: Int64,
               limit: Int) async throws -> PushFetchCoordinator<NSEMessagesSince.Preview>.Reply {
        guard let creds = loadCreds() else {
            Self.log.error("no shared credentials; cannot reconnect")
            throw FetchError.noCreds
        }
        let roomSecret = creds.roomSecret
        let secretProvider: @Sendable () -> Data? = { roomSecret }
        let connector = CompanionTransports.connector(for: creds.code,
                                                      roomSecret: secretProvider,
                                                      nonDisplacing: true)
        let transport = try await connector.connect(
            to: PairingRendezvous(pairingID: creds.code.pairingID),
            timeout: 10)
        self.transport = transport
        let channel = try await NoiseHandshake.perform(
            role: .initiator,
            transport: transport,
            localKeyPair: creds.identity,
            remoteStaticPublicKey: creds.code.responderStaticPublicKey,
            prologue: creds.code.handshakePrologue())
        self.channel = channel

        let requestID: UInt64 = 1
        try await channel.send(NSEMessagesSince.encodeRequest(
            requestID: requestID, collapseToken: token, seq: sinceSeq, limit: limit))

        // Read frames until our reply arrives. A correlated error reply fails
        // FAST (the host signals transient startup races as .error and does not
        // close the channel, so without this we'd block until the deadline).
        // Unsolicited frames (deliveries / typing) are skipped. receive() throws
        // when the channel is closed (deadline hard-cancel, or the app displaced
        // us), surfacing as a fetch failure -> fallback.
        while true {
            let frame = try await channel.receive()
            guard let outcome = try? NSEMessagesSince.decodeReply(frame) else { continue }
            switch outcome {
            case let .messages(rid, reply) where rid == nil || rid == requestID:
                return .init(chatName: reply.chatName,
                             previews: reply.previews,
                             maxSeq: reply.maxSeq,
                             truncated: reply.truncated)
            case let .error(rid) where rid == nil || rid == requestID:
                throw FetchError.hostError
            default:
                continue
            }
        }
    }

    /// Hard-cancel: closing the channel/transport unblocks a stalled receive().
    func cancel() async {
        await channel?.close()
        await transport?.close()
    }

    /// Normal teardown after a completed fetch.
    func close() async {
        await channel?.close()
    }

    // MARK: Credentials (App Group)

    private struct Creds {
        let code: PairingCode
        let identity: NoiseKeyPair
        let roomSecret: Data?
    }

    private func loadCreds() -> Creds? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let responderKey = defaults.data(forKey: CompanionSharedIdentifiers.pairedResponderKeyDefault),
              responderKey.count == 32,
              let pairingID = defaults.string(forKey: CompanionSharedIdentifiers.pairedPairingIDDefault),
              let noisePrivateKey = keychainData(account: noiseAccount),
              let identity = try? NoiseKeyPair.from(privateKey: noisePrivateKey) else {
            return nil
        }
        let code = PairingCode(responderStaticPublicKey: responderKey,
                               pairingID: pairingID,
                               relayOrigin: defaults.string(forKey: CompanionSharedIdentifiers.pairedRelayOriginDefault))
        return Creds(code: code, identity: identity, roomSecret: keychainData(account: roomSecretAccount))
    }

    /// Read a 32-byte item from the shared App Group keychain access group.
    private func keychainData(account: String) -> Data? {
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
}
