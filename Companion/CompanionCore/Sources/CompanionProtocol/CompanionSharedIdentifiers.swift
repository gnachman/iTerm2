//
//  CompanionSharedIdentifiers.swift
//  CompanionCore
//
//  The single source of truth for the App Group, keychain, and pairing-code
//  identifiers that the app and the Notification Service Extension MUST agree
//  on byte-for-byte. The two are separate targets and the NSE cannot import the
//  app, so without this the names were retyped in both places: a rename on one
//  side would make the NSE read nil credentials and silently degrade to the
//  generic fallback (no compile or runtime error). Both link CompanionProtocol,
//  so both reference these.
//

import Foundation

public enum CompanionSharedIdentifiers {
    /// Shared App Group (container + keychain access group + UserDefaults suite).
    public static let appGroup = "group.com.googlecode.iterm2.companion"

    /// Keychain generic-password service for the phone's identity items.
    public static let keychainService = "com.googlecode.iterm2.companion"
    /// Keychain account for the Noise static private key (shared with the NSE).
    public static let noiseStaticPrivateKeyAccount = "noise-static-private-key"
    /// Keychain account for the relay room secret (shared with the NSE).
    public static let roomSecretAccount = "relay-room-secret"
    /// Keychain account for the stored pairing code (responder key, pairing id,
    /// relay origin) as a JSON blob (shared with the NSE). Kept in the keychain -
    /// not UserDefaults - so the pairing survives an app reinstall, which wipes
    /// UserDefaults but not the keychain.
    public static let pairingCodeAccount = "paired-code"

    /// LEGACY App Group UserDefaults keys for the stored pairing code, read once
    /// to migrate an existing pairing into the keychain (above). New writes go to
    /// the keychain; these are cleared on unpair.
    public static let pairedResponderKeyDefault = "PairedResponderStaticKey"
    public static let pairedPairingIDDefault = "PairedPairingID"
    public static let pairedRelayOriginDefault = "PairedRelayOrigin"
}
