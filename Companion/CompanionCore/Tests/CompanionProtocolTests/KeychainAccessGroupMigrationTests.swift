//
//  KeychainAccessGroupMigrationTests.swift
//  CompanionCore
//
//  The access-group migration copies items into the target group, is idempotent,
//  and - critically - NEVER destroys the target copy. The fake keychain models
//  real SecItem semantics: an unscoped (nil) read/delete spans ALL of the app's
//  access groups. A migration that deleted with a nil group would wipe the copy
//  it just added; these tests would catch that.
//

import XCTest
@testable import CompanionProtocol

/// Models the keychain as account -> (group -> data), with the app's default
/// group as "". nil access group is UNSCOPED (spans all groups), as SecItem does.
private final class FakeKeychain: KeychainItemStore {
    static let defaultGroup = ""
    var items: [String: [String: Data]] = [:]

    func read(account: String, accessGroup: String?) throws -> Data? {
        let byGroup = items[account] ?? [:]
        if let group = accessGroup { return byGroup[group] }
        return byGroup[Self.defaultGroup] ?? byGroup.values.first   // unscoped: any group
    }
    func add(account: String, accessGroup: String?, data: Data) throws {
        items[account, default: [:]][accessGroup ?? Self.defaultGroup] = data
    }
    func delete(account: String, accessGroup: String?) throws {
        if let group = accessGroup {
            items[account]?[group] = nil
        } else {
            items[account] = nil   // unscoped: removes from EVERY group
        }
    }
    func value(account: String, group: String) -> Data? { items[account]?[group] }
}

final class KeychainAccessGroupMigrationTests: XCTestCase {
    private let group = "group.test"

    func testCopiesDefaultIntoTargetGroup() throws {
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: nil, data: Data([1, 2, 3]))   // default-group install
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.value(account: "k", group: group), Data([1, 2, 3]))
    }

    func testReMigrationKeepsTargetCopy() throws {
        // The reported bug: on the launch after creds are in the App Group, the
        // "already migrated" cleanup did delete(nil), which (spanning all groups)
        // destroyed the App Group copy. Re-running must NOT lose it.
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: nil, data: Data([7]))
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.value(account: "k", group: group), Data([7]),
                       "the App Group copy must survive repeated migrations")
    }

    func testIdempotentWhenAlreadyInTarget() throws {
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: group, data: Data([9]))   // already migrated
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.value(account: "k", group: group), Data([9]))
    }

    func testNoOpWhenNothingToMigrate() throws {
        let kc = FakeKeychain()
        try KeychainAccessGroupMigration.migrate(accounts: ["absent"], toGroup: group, store: kc)
        XCTAssertNil(kc.value(account: "absent", group: group))
    }
}
