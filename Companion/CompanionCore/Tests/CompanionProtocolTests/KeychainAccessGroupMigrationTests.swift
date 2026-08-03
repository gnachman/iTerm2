//
//  KeychainAccessGroupMigrationTests.swift
//  CompanionCore
//
//  The access-group migration moves items into the target group: it must end
//  with the item ONLY in the target group (no stale source copy left behind),
//  must NEVER destroy the target copy, and must be idempotent and convergent from
//  a partially-migrated (both-groups) state. The fake keychain models real
//  SecItem semantics: readAll spans all of the app's access groups; a scoped
//  delete removes only that group; an unscoped (nil) delete removes every group.
//

import XCTest
@testable import CompanionProtocol

/// Models the keychain as account -> (group -> data), with the app's default
/// group as "". readAll spans all groups; a nil-group delete is unscoped.
private final class FakeKeychain: KeychainItemStore {
    static let defaultGroup = ""
    var items: [String: [String: Data]] = [:]

    func readAll(account: String) throws -> [KeychainItemCopy] {
        (items[account] ?? [:]).map { KeychainItemCopy(accessGroup: $0.key, data: $0.value) }
    }
    func add(account: String, accessGroup: String?, data: Data) throws {
        items[account, default: [:]][accessGroup ?? Self.defaultGroup] = data
    }
    func delete(account: String, accessGroup: String?) throws {
        if let group = accessGroup {
            items[account]?[group] = nil   // scoped: only that group
        } else {
            items[account] = nil           // unscoped: removes from EVERY group
        }
        if items[account]?.isEmpty == true { items[account] = nil }
    }
    func value(account: String, group: String) -> Data? { items[account]?[group] }
    func groups(account: String) -> Set<String> { Set((items[account] ?? [:]).keys) }
}

/// Models iOS reporting a physical access group under a DIFFERENT string than the
/// one passed to `add` (normalization/prefix). `reported[physical]` is what
/// readAll returns; delete maps a reported string back to its physical group.
private final class RemappingFakeKeychain: KeychainItemStore {
    var items: [String: [String: Data]] = [:]   // account -> physicalGroup -> data
    let reported: [String: String]               // physicalGroup -> reported string
    init(reported: [String: String]) { self.reported = reported }

    private func report(_ physical: String) -> String { reported[physical] ?? physical }
    private func physical(forReported r: String) -> String {
        reported.first(where: { $0.value == r })?.key ?? r
    }
    func readAll(account: String) throws -> [KeychainItemCopy] {
        (items[account] ?? [:]).map { KeychainItemCopy(accessGroup: report($0.key), data: $0.value) }
    }
    func add(account: String, accessGroup: String?, data: Data) throws {
        items[account, default: [:]][accessGroup ?? ""] = data
    }
    func delete(account: String, accessGroup: String?) throws {
        if let reportedGroup = accessGroup {
            items[account]?[physical(forReported: reportedGroup)] = nil
        } else {
            items[account] = nil
        }
        if items[account]?.isEmpty == true { items[account] = nil }
    }
    func physicalGroups(account: String) -> Set<String> { Set((items[account] ?? [:]).keys) }
}

final class KeychainAccessGroupMigrationTests: XCTestCase {
    private let group = "group.test"

    func testMovesDefaultIntoTargetAndDeletesSource() throws {
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: nil, data: Data([1, 2, 3]))   // default-group install
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.value(account: "k", group: group), Data([1, 2, 3]))
        XCTAssertNil(kc.value(account: "k", group: FakeKeychain.defaultGroup),
                     "the default-group source copy must be deleted, not left as key material")
        XCTAssertEqual(kc.groups(account: "k"), [group], "the item must live ONLY in the target group")
    }

    func testReMigrationKeepsOnlyTargetCopy() throws {
        // The original bug was a delete(nil) destroying the App Group copy on the
        // next launch; re-running must keep exactly the target copy and never
        // resurrect a source copy.
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: nil, data: Data([7]))
        for _ in 0..<3 {
            try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        }
        XCTAssertEqual(kc.value(account: "k", group: group), Data([7]),
                       "the App Group copy must survive repeated migrations")
        XCTAssertEqual(kc.groups(account: "k"), [group])
    }

    func testConvergesFromPartialBothGroupsState() throws {
        // Simulate a crash after add(target) but before delete(source): the item
        // is in BOTH groups. The next run must converge to target-only.
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: nil, data: Data([5]))      // source
        try kc.add(account: "k", accessGroup: group, data: Data([5]))    // already copied
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.groups(account: "k"), [group], "must converge to target-only")
        XCTAssertEqual(kc.value(account: "k", group: group), Data([5]))
    }

    func testIdempotentWhenAlreadyInTarget() throws {
        let kc = FakeKeychain()
        try kc.add(account: "k", accessGroup: group, data: Data([9]))   // already migrated
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.value(account: "k", group: group), Data([9]))
        XCTAssertEqual(kc.groups(account: "k"), [group])
    }

    func testNoOpWhenNothingToMigrate() throws {
        let kc = FakeKeychain()
        try KeychainAccessGroupMigration.migrate(accounts: ["absent"], toGroup: group, store: kc)
        XCTAssertNil(kc.value(account: "absent", group: group))
    }

    func testDoesNotDeleteWhenTargetIsReportedUnderADifferentString() throws {
        // The item physically lives in the target group, but the OS reports that
        // group under a different string ("S"). A delete-by-reported-string would
        // remove the real item. The migration must leave it intact instead.
        let kc = RemappingFakeKeychain(reported: [group: "S"])
        try kc.add(account: "k", accessGroup: group, data: Data([1]))   // physically in target
        try KeychainAccessGroupMigration.migrate(accounts: ["k"], toGroup: group, store: kc)
        XCTAssertEqual(kc.physicalGroups(account: "k"), [group],
                       "must not delete the real item when the OS reports the target group differently")
        XCTAssertEqual(kc.items["k"]?[group], Data([1]))
    }
}
