//
//  ShardMapVersionFloorStoreTests.swift
//  CompanionCore
//
//  The UserDefaults-backed durable floor store both apps use (§6.4): it must
//  round-trip a version, stay monotonic (a lower write is ignored), keep resolvers
//  independent, and distinguish "never stored" from a stored 0. Runs against an
//  ephemeral suite so it touches no real defaults. See docs/companion-relay-design.md.
//

import XCTest
@testable import CompanionProtocol

final class ShardMapVersionFloorStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "shardfloor.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func store() -> UserDefaultsShardMapVersionFloorStore {
        UserDefaultsShardMapVersionFloorStore(defaults: defaults, keyPrefix: "floor.")
    }

    func testAbsentFloorIsNil() {
        XCTAssertNil(store().floor(forResolverURL: "https://r.example/"))
    }

    func testRoundTrips() {
        let s = store()
        s.setFloor(37, forResolverURL: "https://r.example/")
        XCTAssertEqual(s.floor(forResolverURL: "https://r.example/"), 37)
    }

    func testStoredZeroIsDistinctFromAbsent() {
        // A real published map can be version 0; a stored 0 must not read back as
        // "never stored" (nil), or the floor would be silently lost.
        let s = store()
        s.setFloor(0, forResolverURL: "https://r.example/")
        XCTAssertEqual(s.floor(forResolverURL: "https://r.example/"), 0)
    }

    func testIsMonotonic() {
        let s = store()
        s.setFloor(10, forResolverURL: "https://r.example/")
        s.setFloor(5, forResolverURL: "https://r.example/")    // lower: ignored
        XCTAssertEqual(s.floor(forResolverURL: "https://r.example/"), 10)
        s.setFloor(12, forResolverURL: "https://r.example/")   // higher: adopted
        XCTAssertEqual(s.floor(forResolverURL: "https://r.example/"), 12)
    }

    func testResolversAreIndependent() {
        let s = store()
        s.setFloor(3, forResolverURL: "https://a.example/")
        s.setFloor(9, forResolverURL: "https://b.example/")
        XCTAssertEqual(s.floor(forResolverURL: "https://a.example/"), 3)
        XCTAssertEqual(s.floor(forResolverURL: "https://b.example/"), 9)
    }

    func testPersistsAcrossStoreInstancesSameSuite() {
        // A new store instance over the same defaults (a relaunch) reads the floor.
        store().setFloor(21, forResolverURL: "https://r.example/")
        let reopened = UserDefaultsShardMapVersionFloorStore(defaults: defaults, keyPrefix: "floor.")
        XCTAssertEqual(reopened.floor(forResolverURL: "https://r.example/"), 21)
    }
}
