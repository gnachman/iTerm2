//
//  AppAttest.swift
//  CompanionCore
//
//  The device-side App Attest primitives the relay client needs, behind a
//  protocol so the orchestration (RelayAttestationClient) can be tested without
//  a real device. The concrete adapter wraps Apple's DCAppAttestService; it is
//  inert off a genuine device (isSupported == false), which the orchestration
//  treats as "cannot attest" and degrades accordingly. A small key store keeps
//  the attested key id alive between earning the admission ticket and signing
//  the verifier registration (the two steps of one pairing). See
//  docs/companion-relay-design.md.
//

import Foundation

/// The subset of DCAppAttestService the relay client uses. generateKey mints a
/// Secure Enclave key (local), attestKey produces the one-time attestation Apple
/// signs (a network round trip), and generateAssertion proves continued
/// possession of an attested key over a fresh challenge (local).
public protocol AppAttestService: Sendable {
    /// False on the simulator, older devices, or any build that cannot use App
    /// Attest. The client skips attestation entirely when false.
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// Persists the attested key id for a room between the ticket step (attestKey)
/// and the register step (generateAssertion), which must use the SAME key. Both
/// run in one short pairing flow, but persisting survives an app relaunch in
/// the middle.
public protocol AttestKeyStore: Sendable {
    func keyId(forRoom roomName: String) -> String?
    func setKeyId(_ keyId: String?, forRoom roomName: String)
}

/// UserDefaults-backed store. The key id is local device state, not a setting,
/// so it carries the NoSync prefix and never propagates to a shared prefs file.
public final class UserDefaultsAttestKeyStore: AttestKeyStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix = "NoSyncCompanionAttestKeyId."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func keyId(forRoom roomName: String) -> String? {
        defaults.string(forKey: prefix + roomName)
    }

    public func setKeyId(_ keyId: String?, forRoom roomName: String) {
        if let keyId {
            defaults.set(keyId, forKey: prefix + roomName)
        } else {
            defaults.removeObject(forKey: prefix + roomName)
        }
    }
}

#if canImport(DeviceCheck)
import DeviceCheck

/// The production adapter over Apple's shared App Attest service.
public struct DeviceCheckAppAttestService: AppAttestService {
    public init() {}

    private var service: DCAppAttestService { .shared }

    public var isSupported: Bool { service.isSupported }

    public func generateKey() async throws -> String {
        try await service.generateKey()
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.attestKey(keyId, clientDataHash: clientDataHash)
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}
#endif
