//
//  NoiseHandshake.swift
//  CompanionCore
//
//  Drives the Noise_XK_25519_ChaChaPoly_BLAKE2s handshake to completion over a
//  MessageTransport and returns the resulting encrypted NoiseChannel.
//
//  XK message pattern:
//      <- s            (pre-message: initiator already knows responder's static)
//      -> e, es        (message 1, written by the initiator)
//      <- e, ee        (message 2, written by the responder)
//      -> s, se        (message 3, written by the initiator)
//
//  The phone is the initiator: it learned the responder's static public key
//  from the scanned QR code and presents its own static identity encrypted in
//  message 3. The mac is the responder.
//

import Foundation
import CNoise
import CompanionProtocol

public enum NoiseHandshake {
    /// Run the handshake to completion.
    ///
    /// - Parameters:
    ///   - role: initiator (phone) or responder (mac).
    ///   - transport: the underlying plaintext transport, already connected.
    ///   - localKeyPair: this peer's static identity. XK requires a static key
    ///     for both roles.
    ///   - remoteStaticPublicKey: the responder's static public key. Required
    ///     for the initiator (it comes from the QR code); ignored for the
    ///     responder, which learns the initiator's static during the handshake.
    ///   - prologue: optional data mixed into the handshake hash. Both peers
    ///     must supply identical prologue or the handshake fails. The companion
    ///     binds the pairing id here so a handshake cannot be replayed against a
    ///     different QR code.
    /// - Returns: an encrypted NoiseChannel wrapping `transport`.
    public static func perform(role: NoiseRole,
                               transport: MessageTransport,
                               localKeyPair: NoiseKeyPair,
                               remoteStaticPublicKey: Data?,
                               prologue: Data?) async throws -> NoiseChannel {
        NoiseRuntime.ensureInitialized()

        var handshake: OpaquePointer?
        let roleValue = (role == .initiator) ? CNoiseRoleInitiator : CNoiseRoleResponder
        try noiseCheck(
            noise_handshakestate_new_by_name(&handshake, NoiseProtocolName.xk, roleValue),
            "create handshake")

        do {
            try configure(handshake,
                          localKeyPair: localKeyPair,
                          remoteStaticPublicKey: remoteStaticPublicKey,
                          prologue: prologue)
            try noiseCheck(noise_handshakestate_start(handshake), "start handshake")
            return try await runLoop(handshake, transport: transport)
        } catch {
            noise_handshakestate_free(handshake)
            throw error
        }
    }

    private static func configure(_ handshake: OpaquePointer?,
                                  localKeyPair: NoiseKeyPair,
                                  remoteStaticPublicKey: Data?,
                                  prologue: Data?) throws {
        if let prologue {
            try prologue.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
                try noiseCheck(
                    noise_handshakestate_set_prologue(handshake, raw.baseAddress, prologue.count),
                    "set prologue")
            }
        }

        let localDH = noise_handshakestate_get_local_keypair_dh(handshake)
        try localKeyPair.privateKey.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            try noiseCheck(
                noise_dhstate_set_keypair_private(
                    localDH, raw.bindMemory(to: UInt8.self).baseAddress,
                    localKeyPair.privateKey.count),
                "set local keypair")
        }

        if noise_handshakestate_needs_remote_public_key(handshake) != 0 {
            guard let remoteStaticPublicKey else {
                throw NoiseError.missingRemoteKey
            }
            let remoteDH = noise_handshakestate_get_remote_public_key_dh(handshake)
            try remoteStaticPublicKey.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
                try noiseCheck(
                    noise_dhstate_set_public_key(
                        remoteDH, raw.bindMemory(to: UInt8.self).baseAddress,
                        remoteStaticPublicKey.count),
                    "set remote public key")
            }
        }
    }

    private static func runLoop(_ handshake: OpaquePointer?,
                                transport: MessageTransport) async throws -> NoiseChannel {
        while true {
            switch noise_handshakestate_get_action(handshake) {
            case CNoiseActionWriteMessage:
                try await transport.send(writeMessage(handshake))

            case CNoiseActionReadMessage:
                try readMessage(handshake, try await transport.receive())

            case CNoiseActionSplit:
                // Capture the transcript digest (h) before split frees the
                // handshake state; the SAS confirmation code derives from it.
                // BLAKE2s, so 32 bytes.
                var hashBytes = [UInt8](repeating: 0, count: 32)
                try noiseCheck(
                    noise_handshakestate_get_handshake_hash(handshake, &hashBytes, hashBytes.count),
                    "get handshake hash")
                var sendCipher: OpaquePointer?
                var receiveCipher: OpaquePointer?
                try noiseCheck(
                    noise_handshakestate_split(handshake, &sendCipher, &receiveCipher),
                    "split")
                noise_handshakestate_free(handshake)
                guard let sendCipher, let receiveCipher else {
                    throw NoiseError(code: -1001, operation: "split produced null cipher state")
                }
                return NoiseChannel(transport: transport,
                                    sendCipher: sendCipher,
                                    receiveCipher: receiveCipher,
                                    handshakeHash: Data(hashBytes))

            case CNoiseActionFailed:
                throw NoiseError(code: CNoiseActionFailed, operation: "handshake failed")

            case let action:
                throw NoiseError(code: action, operation: "unexpected handshake action")
            }
        }
    }

    private static func writeMessage(_ handshake: OpaquePointer?) throws -> Data {
        var scratch = [UInt8](repeating: 0, count: NoiseProtocolName.maxNoiseMessageSize)
        return try scratch.withUnsafeMutableBufferPointer { ptr in
            var message = NoiseBuffer()
            message.data = ptr.baseAddress
            message.size = 0
            message.max_size = ptr.count
            // No payload during the companion handshake; the application data
            // flows only after split.
            try noiseCheck(
                noise_handshakestate_write_message(handshake, &message, nil),
                "write handshake message")
            return Data(bytes: ptr.baseAddress!, count: message.size)
        }
    }

    private static func readMessage(_ handshake: OpaquePointer?, _ incoming: Data) throws {
        var bytes = [UInt8](incoming)
        try bytes.withUnsafeMutableBufferPointer { ptr in
            var message = NoiseBuffer()
            message.data = ptr.baseAddress
            message.size = ptr.count
            message.max_size = ptr.count
            try noiseCheck(
                noise_handshakestate_read_message(handshake, &message, nil),
                "read handshake message")
        }
    }
}
