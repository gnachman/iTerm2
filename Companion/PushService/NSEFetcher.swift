//
//  NSEFetcher.swift
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

import Foundation
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
    private let pairingCodeAccount = CompanionSharedIdentifiers.pairingCodeAccount

    private var channel: NoiseChannel?
    private var transport: MessageTransport?

    init(appGroup: String) {
        self.appGroup = appGroup
    }

    func fetch(collapseToken token: String,
               sinceSeq: Int64,
               limit: Int,
               sealedNonce: String?) async throws -> PushFetchCoordinator<NSEMessagesSince.Preview>.Reply {
        guard let creds = loadCreds() else {
            NSELog.log("no shared credentials; cannot reconnect")
            throw FetchError.noCreds
        }
        let roomSecret = creds.roomSecret
        // Open the sealed nonce with the room secret so we can echo the plaintext
        // back; nil if no nonce came in the push or it fails to open (e.g. the
        // room secret was rotated) - the mac then warns, which is correct.
        let nonce = (sealedNonce.flatMap { sealed in
            roomSecret.flatMap { CompanionPushNonceCrypto.open(sealed, roomSecret: $0) }
        })
        NSELog.log("fetch: connecting non-displacing (since=\(sinceSeq), limit=\(limit), nonce=\(nonce == nil ? "no" : "yes"))")
        let secretProvider: @Sendable () -> Data? = { roomSecret }
        let connector = CompanionTransports.connector(for: creds.code,
                                                      roomSecret: secretProvider,
                                                      nonDisplacing: true)
        let transport = try await connector.connect(
            to: PairingRendezvous(pairingID: creds.code.pairingID),
            timeout: 10)
        self.transport = transport
        NSELog.log("fetch: transport connected; starting handshake")
        let channel = try await NoiseHandshake.perform(
            role: .initiator,
            transport: transport,
            localKeyPair: creds.identity,
            remoteStaticPublicKey: creds.code.responderStaticPublicKey,
            prologue: creds.code.handshakePrologue())
        self.channel = channel
        NSELog.log("fetch: handshake complete; sending request")

        let requestID: UInt64 = 1
        try await channel.send(NSEMessagesSince.encodeRequest(
            requestID: requestID, collapseToken: token, seq: sinceSeq, limit: limit, nonce: nonce))

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
                NSELog.log("fetch: reply with \(reply.previews.count) preview(s), maxSeq=\(reply.maxSeq), reset=\(reply.reset)")
                return .init(chatName: reply.chatName,
                             previews: reply.previews,
                             maxSeq: reply.maxSeq,
                             truncated: reply.truncated,
                             reset: reply.reset)
            case let .error(rid) where rid == nil || rid == requestID:
                NSELog.log("fetch: host returned an error reply; failing fast")
                throw FetchError.hostError
            default:
                NSELog.log("fetch: skipping unrelated frame")
                continue
            }
        }
    }

    /// Hard-cancel: closing the channel/transport unblocks a stalled receive().
    func cancel() async {
        NSELog.log("fetch: hard-cancel (deadline or displaced)")
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
        // The pairing code now lives in the App Group keychain (a JSON blob), so
        // it survives an app reinstall; the Noise key + room secret are there too.
        guard let codeData = keychainData(account: pairingCodeAccount),
              let code = try? JSONDecoder().decode(PairingCode.self, from: codeData),
              let noisePrivateKey = keychainData(account: noiseAccount, expectedLength: 32),
              let identity = try? NoiseKeyPair.from(privateKey: noisePrivateKey) else {
            return nil
        }
        return Creds(code: code, identity: identity,
                     roomSecret: keychainData(account: roomSecretAccount, expectedLength: 32))
    }

    /// Read an item from the shared App Group keychain access group. When
    /// `expectedLength` is non-nil the item must be exactly that many bytes (used
    /// for the 32-byte keys); nil allows a variable-length blob (the pairing code).
    private func keychainData(account: String, expectedLength: Int? = nil) -> Data? {
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
              let data = item as? Data else {
            return nil
        }
        if let expectedLength, data.count != expectedLength { return nil }
        return data
    }
}
