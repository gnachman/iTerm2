//
//  IT2HostGrants.swift
//  iTerm2SharedARC
//
//  "Always Allow This Host" for it2 over ssh integration.
//
//  Each connection normally asks before a remote it2 may drive iTerm2. A host the user
//  has chosen to always allow gets a token: the HOST keeps the secret, in
//  ~/.iterm2/it2-grant ("id:secret", mode 0600), and the MAC keeps only its SHA-256,
//  keyed by the SSHIdentity it was minted for. On a later connection with no decision
//  yet, the Mac reads the file back and compares, and only asks when that fails.
//
//  Holding only a hash means the Mac stores nothing that would let anyone impersonate a
//  host, so the keychain buys nothing here, and it would actively hurt: its
//  code-signature check silently drops items for every rebuilt development build.
//
//  A grant is bound to its identity. The Mac only consults the record for the host it
//  connected to, so copying the file to another host grants nothing there.
//

import CryptoKit
import Foundation

/// One host the user chose to always allow.
struct IT2HostGrant: Codable, Equatable {
    /// SSHIdentity.stringIdentifier of the host.
    let host: String
    /// Random, also written to the host's file, so a file from a different grant cannot pass.
    let id: String
    /// Hex SHA-256 of the secret. The secret itself exists only on the host.
    let secretSHA256: String
    let granted: Date
}

enum IT2GrantToken {
    /// Where the host keeps its half, relative to the remote home directory.
    static let remoteRelativePath = ".iterm2/it2-grant"

    /// A fresh id and secret, both lowercase hex. Hex matters: they are embedded in a Python
    /// literal by remoteWriteStatements, and hex needs no escaping.
    static func mint() -> (id: String, secret: String) {
        let id = String.makeSecureHexString(byteCount: 16) ?? randomHexFallback(byteCount: 16)
        let secret = String.makeSecureHexString(byteCount: 32) ?? randomHexFallback(byteCount: 32)
        return (id, secret)
    }

    private static func randomHexFallback(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<byteCount).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }
            .joined()
    }

    static func sha256Hex(_ value: String) -> String {
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func fileContents(id: String, secret: String) -> String {
        return "\(id):\(secret)\n"
    }

    /// Whether the host's file matches `grant`. The id must match exactly and the secret must
    /// hash to the stored value; the hash comparison is constant-time.
    static func verify(fileContents: String, against grant: IT2HostGrant) -> Bool {
        let line = fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return false
        }
        guard String(parts[0]) == grant.id else {
            return false
        }
        return it2ConstantTimeEqual(sha256Hex(String(parts[1])), grant.secretSHA256)
    }

    /// Python that writes the host's half atomically and privately.
    ///
    /// The temporary is created IN ~/.iterm2, never /tmp: on a shared host /tmp is readable by
    /// every user and is not reliably writable. Created 0600 via mkstemp and moved into place
    /// with os.replace, so no other user can ever read it and a reader never sees half a token.
    static func remoteWriteStatements(id: String, secret: String) -> String {
        it_assert(isHex(id) && isHex(secret), "token must be hex to embed safely")
        return """
        import os, tempfile
        d = os.path.expanduser("~/.iterm2")
        os.makedirs(d, mode=0o700, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".it2-grant.")
        try:
            os.fchmod(fd, 0o600)
            os.write(fd, b"\(id):\(secret)\\n")
        finally:
            os.close(fd)
        os.replace(tmp, os.path.join(d, "it2-grant"))
        """
    }

    private static func isHex(_ value: String) -> Bool {
        return !value.isEmpty && value.unicodeScalars.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }
    }
}

/// Where the grant list is persisted. A protocol so tests use memory rather than the user's
/// real defaults.
protocol IT2HostGrantBacking: AnyObject {
    func loadGrantData() -> Data?
    func saveGrantData(_ data: Data?)
}

/// The real backing: a NoSync user default. NoSync because this is state, not configuration,
/// and a user who loads preferences from a shared folder must not be prompted to write settings
/// every time a host is granted.
final class IT2HostGrantUserDefaultsBacking: IT2HostGrantBacking {
    static let key = "NoSyncIT2HostGrants"

    func loadGrantData() -> Data? {
        return iTermUserDefaults.userDefaults().data(forKey: Self.key)
    }

    func saveGrantData(_ data: Data?) {
        iTermUserDefaults.userDefaults().set(data, forKey: Self.key)
    }
}

final class IT2HostGrantStore {
    static let shared = IT2HostGrantStore(backing: IT2HostGrantUserDefaultsBacking())

    private let backing: IT2HostGrantBacking

    init(backing: IT2HostGrantBacking) {
        self.backing = backing
    }

    var all: [IT2HostGrant] {
        guard let data = backing.loadGrantData() else {
            return []
        }
        // Corrupt or foreign data yields no grants rather than a crash or an invented one.
        return (try? JSONDecoder().decode([IT2HostGrant].self, from: data)) ?? []
    }

    func grant(forHost host: String) -> IT2HostGrant? {
        return all.first { $0.host == host }
    }

    /// Adds `grant`, replacing any existing record for the same host.
    func add(_ grant: IT2HostGrant) {
        save(all.filter { $0.host != grant.host } + [grant])
    }

    func remove(host: String) {
        save(all.filter { $0.host != host })
    }

    /// Stop always allowing `host`, and make live connections that were allowed ask again.
    ///
    /// Only a GRANTED decision is cleared. A connection the user explicitly denied stays denied:
    /// revoking a grant takes trust away, it must not turn a refusal back into a question.
    ///
    /// The host's own file is left in place. It needs a live connection to delete, which there
    /// may not be, and it is inert without the Mac's record; granting again overwrites it.
    @MainActor
    func revoke(host: String) {
        remove(host: host)
        for conductor in ConductorRegistry.instance.conductors(forStringIdentifier: host)
        where conductor.it2Authorized == true {
            conductor.it2Authorized = nil
        }
    }

    private func save(_ grants: [IT2HostGrant]) {
        if grants.isEmpty {
            backing.saveGrantData(nil)
            return
        }
        backing.saveGrantData(try? JSONEncoder().encode(grants))
    }
}

/// What the user's answer to the it2 authorization announcement means.
///
/// Kept apart from the announcement so the index mapping is tested: inserting a button shifts
/// every index after it, and a stale mapping would quietly turn Deny into something else. The
/// announcement's action array must list its buttons in this order.
@objc(iTermIT2AuthorizationOutcome)
final class IT2AuthorizationOutcome: NSObject {
    @objc static let allowIndex = 0
    @objc static let alwaysAllowThisHostIndex = 1
    @objc static let denyIndex = 2

    @objc let granted: Bool
    /// An explicit choice, cached for the connection. Closing (-1) or dismissing (-2) is not a
    /// choice, so the next command asks again.
    @objc let remember: Bool
    /// Also allow this host on every future connection.
    @objc let alwaysForHost: Bool

    @objc init(selection: Int) {
        alwaysForHost = (selection == Self.alwaysAllowThisHostIndex)
        granted = (selection == Self.allowIndex || alwaysForHost)
        remember = (granted || selection == Self.denyIndex)
        super.init()
    }
}
