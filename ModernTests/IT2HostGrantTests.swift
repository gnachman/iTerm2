//
//  IT2HostGrantTests.swift
//  iTerm2 ModernTests
//
//  "Always Allow This Host" for it2 over ssh integration (Phase 3d).
//
//  The host keeps the secret; the Mac keeps only its SHA-256. ~/.iterm2/it2-grant
//  on the host holds "id:secret". The Mac stores {host, id, hash, date}, keyed by
//  SSHIdentity, under a NoSync key. So the Mac holds nothing that would let anyone
//  impersonate a host, which is why the keychain is unnecessary (and would drop
//  grants on every rebuilt dev build through its code-signature check).
//
//  A grant is bound to the identity it was minted for: the Mac only consults the
//  record for the host it actually connected to, so copying the file elsewhere
//  grants nothing.
//

import XCTest
@testable import iTerm2SharedARC

private final class MemoryBacking: IT2HostGrantBacking {
    var data: Data?
    func loadGrantData() -> Data? { data }
    func saveGrantData(_ data: Data?) { self.data = data }
}

final class IT2HostGrantTests: XCTestCase {
    // MARK: - Token

    func testMintedTokensAreHexAndDistinct() {
        let a = IT2GrantToken.mint()
        let b = IT2GrantToken.mint()
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.secret, b.secret)
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        for value in [a.id, a.secret] {
            XCTAssertTrue(value.unicodeScalars.allSatisfy { hex.contains($0) },
                          "hex only, so it can be embedded in a Python literal safely: \(value)")
        }
        XCTAssertGreaterThanOrEqual(a.secret.count, 64, "at least 256 bits of secret")
    }

    func testFileContentsRoundTripThroughVerification() {
        let token = IT2GrantToken.mint()
        let grant = IT2HostGrant(host: "u@h", id: token.id,
                                 secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                 granted: Date())
        let contents = IT2GrantToken.fileContents(id: token.id, secret: token.secret)
        XCTAssertTrue(IT2GrantToken.verify(fileContents: contents, against: grant))
    }

    // The Mac must never hold the secret itself.
    func testTheStoredGrantDoesNotContainTheSecret() throws {
        let token = IT2GrantToken.mint()
        let grant = IT2HostGrant(host: "u@h", id: token.id,
                                 secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                 granted: Date())
        let encoded = String(decoding: try JSONEncoder().encode(grant), as: UTF8.self)
        XCTAssertFalse(encoded.contains(token.secret), "got \(encoded)")
    }

    func testWrongSecretFails() {
        let token = IT2GrantToken.mint()
        let grant = IT2HostGrant(host: "u@h", id: token.id,
                                 secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                 granted: Date())
        XCTAssertFalse(IT2GrantToken.verify(
            fileContents: IT2GrantToken.fileContents(id: token.id, secret: IT2GrantToken.mint().secret),
            against: grant))
    }

    // A file from a different grant on the same host (say, re-granted later) must not pass.
    func testWrongIdFails() {
        let token = IT2GrantToken.mint()
        let grant = IT2HostGrant(host: "u@h", id: token.id,
                                 secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                 granted: Date())
        XCTAssertFalse(IT2GrantToken.verify(
            fileContents: IT2GrantToken.fileContents(id: IT2GrantToken.mint().id, secret: token.secret),
            against: grant))
    }

    func testMalformedFilesFail() {
        let token = IT2GrantToken.mint()
        let grant = IT2HostGrant(host: "u@h", id: token.id,
                                 secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                 granted: Date())
        for junk in ["", "\n", token.id, ":", "\(token.id):", ":\(token.secret)",
                     "\(token.id):\(token.secret):extra"] {
            XCTAssertFalse(IT2GrantToken.verify(fileContents: junk, against: grant), "accepted \(junk)")
        }
    }

    // A trailing newline (how it is written) or CRLF from an editor is tolerated.
    func testTrailingWhitespaceIsTolerated() {
        let token = IT2GrantToken.mint()
        let grant = IT2HostGrant(host: "u@h", id: token.id,
                                 secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                                 granted: Date())
        XCTAssertTrue(IT2GrantToken.verify(fileContents: "\(token.id):\(token.secret)\r\n", against: grant))
    }

    // MARK: - Store

    func testStoreRoundTripsAndLooksUpByHost() {
        let backing = MemoryBacking()
        let store = IT2HostGrantStore(backing: backing)
        let grant = IT2HostGrant(host: "u@h", id: "1", secretSHA256: "aa", granted: Date(timeIntervalSince1970: 5))
        store.add(grant)
        XCTAssertEqual(IT2HostGrantStore(backing: backing).grant(forHost: "u@h"), grant,
                       "persisted, not just held in memory")
        XCTAssertNil(store.grant(forHost: "other@h"))
    }

    // Re-granting a host replaces its record rather than accumulating stale ones.
    func testAddingAgainReplacesThatHost() {
        let store = IT2HostGrantStore(backing: MemoryBacking())
        store.add(IT2HostGrant(host: "u@h", id: "1", secretSHA256: "aa", granted: Date()))
        store.add(IT2HostGrant(host: "u@h", id: "2", secretSHA256: "bb", granted: Date()))
        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.grant(forHost: "u@h")?.id, "2")
    }

    func testRemove() {
        let store = IT2HostGrantStore(backing: MemoryBacking())
        store.add(IT2HostGrant(host: "u@h", id: "1", secretSHA256: "aa", granted: Date()))
        store.add(IT2HostGrant(host: "v@h", id: "2", secretSHA256: "bb", granted: Date()))
        store.remove(host: "u@h")
        XCTAssertNil(store.grant(forHost: "u@h"))
        XCTAssertNotNil(store.grant(forHost: "v@h"))
    }

    // MARK: - Grants recorded before ssh config Include and Match were honored

    /// "web" reached as alice, which the config now resolves to web.example.com.
    private let webIdentity = SSHIdentity(host: "web", hostname: "web.example.com",
                                          username: "it2-test-alice", port: 22)

    private func store(withGrantFor host: String) -> IT2HostGrantStore {
        let store = IT2HostGrantStore(backing: MemoryBacking())
        store.add(IT2HostGrant(host: host, id: "1", secretSHA256: "aa", granted: Date()))
        return store
    }

    // Before, a HostName that only an Include or Match supplied was invisible, so the key used
    // the host as typed.
    func testFallsBackToTheHostAsTyped() {
        XCTAssertEqual(store(withGrantFor: "it2-test-alice@web").grant(for: webIdentity)?.id, "1")
    }

    // Before, a HostName kept its capitalization; now it is lowercased, as ssh does.
    func testFallsBackToADifferentlyCapitalizedHostname() {
        XCTAssertEqual(store(withGrantFor: "it2-test-alice@Web.Example.COM").grant(for: webIdentity)?.id, "1")
    }

    func testTheCurrentKeyWins() {
        let store = store(withGrantFor: "it2-test-alice@web")
        store.add(IT2HostGrant(host: webIdentity.stringIdentifier, id: "2", secretSHA256: "bb", granted: Date()))
        XCTAssertEqual(store.grant(for: webIdentity)?.id, "2")
    }

    // Another user, port, or host is a different grant. (No user, or port 22, can be the old
    // form of a user or port the config supplies; see testFallsBackPastAConfigSuppliedPortAndUser.)
    func testTheFallbackKeepsUserPortAndHost() {
        for host in ["it2-test-bob@web",
                     "IT2-TEST-ALICE@web",
                     "it2-test-alice@web port 2222",
                     "it2-test-alice@other",
                     "it2-test-alice@",
                     "other"] {
            XCTAssertNil(store(withGrantFor: host).grant(for: webIdentity), host)
        }
    }

    // Before, a Port or User the config supplied was ignored: the old key had no user and
    // port 22.
    func testFallsBackPastAConfigSuppliedPortAndUser() {
        let lima = SSHIdentity(host: "lima-a", hostname: "127.0.0.1", username: "it2-test-alice", port: 60022)
        XCTAssertEqual(store(withGrantFor: "lima-a").grant(for: lima)?.id, "1")
        XCTAssertEqual(store(withGrantFor: "127.0.0.1").grant(for: lima)?.id, "1")
        XCTAssertNil(store(withGrantFor: "lima-a port 60023").grant(for: lima))
        XCTAssertNil(store(withGrantFor: "it2-test-bob@lima-a").grant(for: lima))
    }

    // Two hosts that once had the same key: each is offered every candidate, its own first, so
    // the host can verify the one that is really its own.
    func testEveryCandidateIsOffered() {
        let store = IT2HostGrantStore(backing: MemoryBacking())
        let limaA = SSHIdentity(host: "lima-a", hostname: "127.0.0.1", username: nil, port: 60022)
        let limaB = SSHIdentity(host: "lima-b", hostname: "127.0.0.1", username: nil, port: 60023)
        store.add(IT2HostGrant(host: "127.0.0.1", id: "shared", secretSHA256: "aa", granted: Date()))
        store.add(IT2HostGrant(host: "lima-b", id: "b", secretSHA256: "bb", granted: Date()))
        store.add(IT2HostGrant(host: limaA.stringIdentifier, id: "a", secretSHA256: "cc", granted: Date()))
        XCTAssertEqual(store.grants(for: limaA).map(\.id), ["a", "shared"])
        XCTAssertEqual(store.grants(for: limaB).map(\.id), ["shared", "b"])
    }

    // After both hosts migrate, each has its own record and neither displaces the other.
    func testHostsSharingAHostNameKeepSeparateGrants() throws {
        let store = IT2HostGrantStore(backing: MemoryBacking())
        let limaA = SSHIdentity(host: "lima-a", hostname: "127.0.0.1", username: nil, port: 60022)
        let limaB = SSHIdentity(host: "lima-b", hostname: "127.0.0.1", username: nil, port: 60023)
        store.add(IT2HostGrant(host: "lima-a", id: "a", secretSHA256: "aa", granted: Date()))
        store.add(IT2HostGrant(host: "lima-b", id: "b", secretSHA256: "bb", granted: Date()))
        store.rekey(try XCTUnwrap(store.grant(for: limaA)), to: limaA.stringIdentifier)
        XCTAssertEqual(store.grant(for: limaB)?.id, "b", "lima-a's migration leaves lima-b's alone")
        store.rekey(try XCTUnwrap(store.grant(for: limaB)), to: limaB.stringIdentifier)
        XCTAssertEqual(store.grant(forHost: limaA.stringIdentifier)?.id, "a")
        XCTAssertEqual(store.grant(forHost: limaB.stringIdentifier)?.id, "b")
        XCTAssertEqual(store.all.count, 2)
    }

    func testRekeyMovesTheGrantToItsCurrentKey() throws {
        let store = store(withGrantFor: "it2-test-alice@web")
        let grant = try XCTUnwrap(store.grant(for: webIdentity))
        store.rekey(grant, to: webIdentity.stringIdentifier)
        XCTAssertEqual(store.all.map(\.host), [webIdentity.stringIdentifier])
        XCTAssertEqual(store.grant(forHost: webIdentity.stringIdentifier)?.id, "1")
        XCTAssertEqual(store.grant(forHost: webIdentity.stringIdentifier)?.secretSHA256, "aa")
    }

    // Corrupt or foreign data in the default must not crash or invent grants.
    func testCorruptStorageYieldsNoGrants() {
        let backing = MemoryBacking()
        backing.data = Data("not json".utf8)
        XCTAssertEqual(IT2HostGrantStore(backing: backing).all, [])
    }

    // MARK: - The remote write

    // Written with a temporary IN ~/.iterm2 and os.replace, never in /tmp: on a shared host /tmp is
    // readable by every user and may not be writable.
    func testRemoteWriteStaysInTheDotDirAndIsPrivate() {
        let script = IT2GrantToken.remoteWriteStatements(id: "ab", secret: "cd")
        XCTAssertTrue(script.contains("~/.iterm2/it2-grants"))
        XCTAssertTrue(script.contains("dir=d"), "the temporary must be created in ~/.iterm2: \(script)")
        XCTAssertFalse(script.contains("/tmp"))
        XCTAssertTrue(script.contains("0o600"), "the grant file must be private")
        XCTAssertTrue(script.contains("os.replace"), "atomic, so a reader never sees half a token")
        XCTAssertTrue(script.contains("ab:cd"))
    }

    /// Runs `statements` with python3 and HOME set to `home`.
    private func runPython(_ statements: String, home: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", statements]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func grant(_ token: (id: String, secret: String), host: String) -> IT2HostGrant {
        return IT2HostGrant(host: host, id: token.id, secretSHA256: IT2GrantToken.sha256Hex(token.secret),
                            granted: Date())
    }

    private func hostHalf(_ id: String, home: URL) -> String? {
        return try? String(contentsOf: home.appendingPathComponent(IT2GrantToken.remoteRelativePath(id: id)),
                           encoding: .utf8)
    }

    // Two grants that land on one remote account (another port, another Mac, another build of
    // iTerm2) each keep their half, so neither keeps asking again. Granting a host again
    // removes the half it replaces.
    func testGrantsOnOneAccountDoNotClobberEachOther() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("it2-grants-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let a = IT2GrantToken.mint()
        let b = IT2GrantToken.mint()
        try runPython(IT2GrantToken.remoteWriteStatements(id: a.id, secret: a.secret), home: home)
        try runPython(IT2GrantToken.remoteWriteStatements(id: b.id, secret: b.secret), home: home)
        XCTAssertTrue(IT2GrantToken.verify(fileContents: try XCTUnwrap(hostHalf(a.id, home: home)),
                                           against: grant(a, host: "h:22")))
        XCTAssertTrue(IT2GrantToken.verify(fileContents: try XCTUnwrap(hostHalf(b.id, home: home)),
                                           against: grant(b, host: "h:2222")))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: home.appendingPathComponent(IT2GrantToken.remoteRelativePath(id: a.id)).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let again = IT2GrantToken.mint()
        try runPython(IT2GrantToken.remoteWriteStatements(id: again.id, secret: again.secret, replacing: a.id),
                      home: home)
        XCTAssertNil(hostHalf(a.id, home: home), "the replaced half is gone")
        XCTAssertNotNil(hostHalf(again.id, home: home))
        XCTAssertNotNil(hostHalf(b.id, home: home), "another grant's half is untouched")
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: home.appendingPathComponent(IT2GrantToken.remoteDirectoryRelativePath).path)
        XCTAssertEqual(Set(leftovers), [again.id, b.id], "no temporaries left behind")
    }

    // MARK: - The announcement's answer

    // Pinned because inserting "Always Allow This Host" shifted Deny's index, and a stale mapping
    // would quietly have granted access on Deny.
    func testAnnouncementOutcomes() {
        let allow = IT2AuthorizationOutcome(selection: IT2AuthorizationOutcome.allowIndex)
        XCTAssertTrue(allow.granted); XCTAssertTrue(allow.remember); XCTAssertFalse(allow.alwaysForHost)

        let always = IT2AuthorizationOutcome(selection: IT2AuthorizationOutcome.alwaysAllowThisHostIndex)
        XCTAssertTrue(always.granted); XCTAssertTrue(always.remember); XCTAssertTrue(always.alwaysForHost)

        let deny = IT2AuthorizationOutcome(selection: IT2AuthorizationOutcome.denyIndex)
        XCTAssertFalse(deny.granted, "Deny must never grant")
        XCTAssertTrue(deny.remember, "but it is a decision, so it is cached")
        XCTAssertFalse(deny.alwaysForHost)
    }

    // Closing or dismissing is not a decision: deny this request, cache nothing.
    func testClosingIsNotADecision() {
        for selection in [-1, -2] {
            let outcome = IT2AuthorizationOutcome(selection: selection)
            XCTAssertFalse(outcome.granted)
            XCTAssertFalse(outcome.remember)
            XCTAssertFalse(outcome.alwaysForHost)
        }
    }

    func testIndicesAreDistinct() {
        XCTAssertEqual(Set([IT2AuthorizationOutcome.allowIndex,
                            IT2AuthorizationOutcome.alwaysAllowThisHostIndex,
                            IT2AuthorizationOutcome.denyIndex]).count, 3)
    }
}
