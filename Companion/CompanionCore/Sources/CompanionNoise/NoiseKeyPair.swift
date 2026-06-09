//
//  NoiseKeyPair.swift
//  CompanionCore
//
//  An X25519 static keypair, used as a peer's long-term Noise identity. The
//  phone persists its keypair (private key in the Keychain) so it presents a
//  stable identity across pairings; the mac persists its keypair so the public
//  key it advertises in the QR code stays constant.
//

import Foundation
import CNoise

public struct NoiseKeyPair: Equatable, Sendable {
    /// 32-byte X25519 private key.
    public let privateKey: Data
    /// 32-byte X25519 public key, derived from the private key.
    public let publicKey: Data

    public init(privateKey: Data, publicKey: Data) {
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    /// Generate a fresh random keypair.
    public static func generate() throws -> NoiseKeyPair {
        try withCurve25519State { (dh: OpaquePointer?) -> Void in
            try noiseCheck(noise_dhstate_generate_keypair(dh), "generate keypair")
        }
    }

    /// Reconstruct a keypair (including the derived public key) from a stored
    /// private key.
    public static func from(privateKey: Data) throws -> NoiseKeyPair {
        try withCurve25519State { (dh: OpaquePointer?) -> Void in
            try privateKey.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
                try noiseCheck(
                    noise_dhstate_set_keypair_private(
                        dh, raw.bindMemory(to: UInt8.self).baseAddress, privateKey.count),
                    "set keypair private")
            }
        }
    }

    /// Create a fresh curve25519 NoiseDHState, run `configure` on it, then
    /// export its keypair. The state is always freed.
    private static func withCurve25519State(
        _ configure: (OpaquePointer?) throws -> Void
    ) throws -> NoiseKeyPair {
        NoiseRuntime.ensureInitialized()
        var dh: OpaquePointer?
        try noiseCheck(noise_dhstate_new_by_name(&dh, "25519"), "create curve25519 dhstate")
        defer { noise_dhstate_free(dh) }
        try configure(dh)

        let privLen = noise_dhstate_get_private_key_length(dh)
        let pubLen = noise_dhstate_get_public_key_length(dh)
        var priv = [UInt8](repeating: 0, count: privLen)
        var pub = [UInt8](repeating: 0, count: pubLen)
        try noiseCheck(
            noise_dhstate_get_keypair(dh, &priv, privLen, &pub, pubLen),
            "export keypair")
        return NoiseKeyPair(privateKey: Data(priv), publicKey: Data(pub))
    }
}
