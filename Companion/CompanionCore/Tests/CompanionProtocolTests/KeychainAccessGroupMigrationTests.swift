//
//  KeychainAccessGroupMigrationTests.swift
//  CompanionCore
//
//  The add-then-delete access-group migration: it moves items into the target
//  group, is idempotent, and is crash-safe (a crash after add / before delete
//  leaves the item readable, and the next run completes the move).
//

import XCTest
@testable import CompanionProtocol

private struct Slot: Hashable { let account: String; let group: String? }

private final class FakeKeychain: KeychainItemStore {
    var items: [Slot: Data] = [:]
    /// When set, throw on the delete of this (account, default-group) slot once,
    /// to simulate a crash after add / before delete.
    var failDefaultDeleteForAccount: String?

    func read(account: String, accessGroup: String?) throws -> Data? {
        items[Slot(account: account, group: accessGroup)]
    }
    func add(account: String, accessGroup: String?, data: Data) throws {
        items[Slot(account: account, group: accessGroup)] = data   // duplicate == overwrite == success
    }
    func delete(account: String, accessGroup: String?) throws {
        if accessGroup == nil, account == failDefaultDeleteForAccount {
            failDefaultDeleteForAccount = nil
            throw NSError(domain: "crash", code: 1)
        }
        items[Slot(account: account, group: accessGroup)] = nil
    }
}

final class KeychainAccessGroupMigrationTests: XCTestCase {
    private let group = "group.test"

    func testMovesItemFromDefaultToTarget() throws {
        let kc = FakeKeychain()
        kc.items[Slot(account: "k", group: nil)] = Data([1, 2, 3])

        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)

        XCTAssertEqual(kc.items[Slot(account: "k", group: group)], Data([1, 2, 3]))
        XCTAssertNil(kc.items[Slot(account: "k", group: nil)], "default-group copy removed")
    }

    func testIdempotent() throws {
        let kc = FakeKeychain()
        kc.items[Slot(account: "k", group: nil)] = Data([9])
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        // Second run is a no-op: still present in target, nothing in default.
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.items[Slot(account: "k", group: group)], Data([9]))
        XCTAssertNil(kc.items[Slot(account: "k", group: nil)])
    }

    func testNoOpWhenNothingToMigrate() throws {
        let kc = FakeKeychain()
        try KeychainAccessGroupMigration.migrate(accounts: ["absent"], toGroup: group, store: kc)
        XCTAssertTrue(kc.items.isEmpty)
    }

    func testCrashAfterAddBeforeDeleteIsRecoverable() throws {
        let kc = FakeKeychain()
        kc.items[Slot(account: "k", group: nil)] = Data([7])
        kc.failDefaultDeleteForAccount = "k"   // crash on the delete after add

        XCTAssertThrowsError(
            try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc))

        // Mid-crash state: readable in BOTH groups, never lost.
        XCTAssertEqual(kc.items[Slot(account: "k", group: group)], Data([7]))
        XCTAssertEqual(kc.items[Slot(account: "k", group: nil)], Data([7]))

        // Next run sees it in the target and finishes (removes the leftover).
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.items[Slot(account: "k", group: group)], Data([7]))
        XCTAssertNil(kc.items[Slot(account: "k", group: nil)])
    }
}
