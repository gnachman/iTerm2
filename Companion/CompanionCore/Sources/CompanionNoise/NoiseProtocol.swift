//
//  NoiseProtocol.swift
//  CompanionCore
//
//  Identifiers and roles for the companion's Noise handshake. The full
//  Noise_XK_25519_ChaChaPoly_BLAKE2s handshake and the encrypted NoiseChannel
//  (a MessageTransport that wraps another MessageTransport) are added on top of
//  these in this target.
//

import Foundation
import CompanionProtocol

public enum NoiseRole {
    /// The phone, which scans the QR code and opens the connection.
    case initiator
    /// The mac, which displays the QR code and waits for a connection.
    case responder
}

public enum NoiseProtocolName {
    /// The handshake pattern and crypto suite carried in the pairing code's
    /// `proto` field. Must match PairingCode.supportedProtocol.
    public static let xk = PairingCode.supportedProtocol

    /// Noise transport messages are capped at this many bytes (handshake and
    /// transport). The application layer chunks anything larger before it
    /// reaches the NoiseChannel.
    public static let maxNoiseMessageSize = 65535
}
