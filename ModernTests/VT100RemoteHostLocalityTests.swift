//
//  VT100RemoteHostLocalityTests.swift
//  iTerm2
//
//  Covers the 3-state locality stamp on VT100RemoteHost: localhost-ness is
//  determined when the host is reported and frozen on the object, instead of
//  being recomputed by comparing the recorded hostname against the live local
//  hostname (which breaks when a network change renames the .local host).
//

import XCTest
@testable import iTerm2SharedARC

final class VT100RemoteHostLocalityTests: XCTestCase {
    // The same value the model's legacy fallback compares against.
    private var liveLocalName: String { Host.fullyQualifiedDomainName() }

    // A name guaranteed not to equal the live local hostname.
    private var foreignName: String { liveLocalName + ".not-this-machine.invalid" }

    // Explicit return types unwrap the bridged implicitly-unwrapped optional
    // initializers, so callers get a plain non-optional VT100RemoteHost.
    private func makeHost(_ user: String, _ host: String, _ locality: VT100RemoteHostLocality) -> VT100RemoteHost {
        return VT100RemoteHost(username: user, hostname: host, locality: locality)
    }

    private func makeHost(_ user: String, _ host: String) -> VT100RemoteHost {
        return VT100RemoteHost(username: user, hostname: host)
    }

    private func localhostHost() -> VT100RemoteHost {
        return VT100RemoteHost.localhost()
    }

    // MARK: - Legacy / unknown locality

    func testTwoArgInitIsUnknownLocality() {
        XCTAssertEqual(makeHost("me", foreignName).localityState, .unknown)
    }

    func testUnknownLocalityFallsBackToHostnameCompare() {
        // Unknown locality: behavior matches the legacy string compare.
        XCTAssertTrue(makeHost("me", liveLocalName).isLocalhost,
                      "unknown host whose name matches the live local name should read as localhost")
        XCTAssertFalse(makeHost("me", foreignName).isLocalhost,
                       "unknown host whose name differs should read as remote")
    }

    // MARK: - Known locality wins over the name

    func testKnownLocalhostIsLocalhostEvenWhenNameDrifted() {
        // The whole point: a stale .local name no longer matches gethostname(),
        // but the frozen bit still says localhost.
        let host = makeHost("me", foreignName, .localhost)
        XCTAssertTrue(host.isLocalhost)
        XCTAssertFalse(host.isRemoteHost)
    }

    func testKnownRemoteIsNotLocalhostEvenWhenNameMatches() {
        // SSH to a box that happens to share our local name: structurally remote.
        let host = makeHost("me", liveLocalName, .remote)
        XCTAssertFalse(host.isLocalhost)
        XCTAssertTrue(host.isRemoteHost)
    }

    func testLocalhostFactoryIsKnownLocalhost() {
        let host = localhostHost()
        XCTAssertEqual(host.localityState, .localhost)
        XCTAssertTrue(host.isLocalhost)
    }

    // MARK: - Equality: both-known-localhost ignores the hostname

    func testEqualityBothLocalhostIgnoresHostname() {
        let a = makeHost("me", "MacBook-Pro-2.local", .localhost)
        let b = makeHost("me", "MacBook-Pro-3.local", .localhost)
        XCTAssertTrue(a.isEqual(toRemoteHost: b),
                      "two known-localhost hosts with drifted names should be equal")
    }

    func testEqualityBothLocalhostStillRequiresSameUser() {
        let me = makeHost("me", "MacBook-Pro-2.local", .localhost)
        let root = makeHost("root", "MacBook-Pro-2.local", .localhost)
        XCTAssertFalse(me.isEqual(toRemoteHost: root),
                       "localhost as different users should not be equal")
    }

    func testEqualityFallsBackToHostnameWhenNotBothLocalhost() {
        let local = makeHost("me", "h1", .localhost)
        let unknown = makeHost("me", "h2", .unknown)
        XCTAssertFalse(local.isEqual(toRemoteHost: unknown),
                       "mixed locality must compare hostnames; different names are not equal")

        XCTAssertTrue(makeHost("me", "h1", .unknown).isEqual(toRemoteHost: makeHost("me", "h1", .unknown)))
    }

    // MARK: - Serialization round trips

    func testSerializationPreservesLocality() {
        for locality in [VT100RemoteHostLocality.localhost, .remote, .unknown] {
            let host = makeHost("me", "host", locality)
            let restored = VT100RemoteHost(dictionary: host.dictionaryValue())
            XCTAssertEqual(restored?.localityState, locality, "round trip lost locality \(locality.rawValue)")
        }
    }

    func testLegacyDictionaryWithoutLocalityIsUnknown() {
        // Simulate data written before the locality key existed.
        let legacy: [AnyHashable: Any] = ["Host name": "old.local", "User name": "me"]
        let restored = VT100RemoteHost(dictionary: legacy)
        XCTAssertEqual(restored?.localityState, .unknown)
    }

    // MARK: - Mapping the published isLocalhost variable to a locality

    func testLocalityForIsLocalhostVariableValue() {
        // Unset/unknown and non-numbers fall through to unknown (legacy compare).
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: nil), .unknown)
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: NSNull()), .unknown)
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: "true"), .unknown)
        // Booleans (as published by the session variable) map to known locality.
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: true), .localhost)
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: false), .remote)
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: NSNumber(value: true)), .localhost)
        XCTAssertEqual(VT100RemoteHost.locality(forIsLocalhostVariableValue: NSNumber(value: false)), .remote)
    }

    // MARK: - Doppelganger carries the bit
    //
    // doppelganger is produced via copyOfIntervalTreeObject, so this also
    // exercises that the copy carries the locality (the interval tree hands
    // out doppelgangers, and the equality/locality comparisons run on them).

    func testDoppelgangerPreservesLocality() {
        let host = makeHost("me", foreignName, .localhost)
        let dop: any VT100RemoteHostReading = host.doppelganger()
        XCTAssertEqual(dop.localityState, .localhost)
        XCTAssertTrue(dop.isLocalhost)
    }
}
