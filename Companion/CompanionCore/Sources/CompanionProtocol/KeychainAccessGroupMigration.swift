//
//  KeychainAccessGroupMigration.swift
//  CompanionCore
//
//  Copies keychain items into a shared App Group keychain access group so the
//  Notification Service Extension can read them. kSecAttrAccessGroup cannot be
//  changed with SecItemUpdate, so the item is ADDED to the target group.
//
//  It deliberately does NOT delete the source copy: a SecItemDelete (or
//  SecItemCopyMatching) whose query omits kSecAttrAccessGroup matches across
//  ALL of the app's access groups, including the target - so a "delete the old
//  one" step would destroy the copy we just added and brick the identity. A
//  leftover duplicate in the default group is harmless because callers read the
//  target group first; it is cleaned up on key rotation (delete-everywhere then
//  re-store). Idempotent: safe on every launch.
//
//  The SecItem operations are injected (KeychainItemStore) so the state machine
//  is unit-testable without a real keychain.
//

import Foundation

/// The minimal keychain surface the migration needs. The `accessGroup`
/// semantics MIRROR SecItem exactly, which is the whole point of this type:
///  - read:  nil is UNSCOPED (matches across all of the app's access groups,
///           returning the item wherever it lives); non-nil scopes to that group.
///  - add:   nil adds to the app's default group; non-nil adds to that group.
///           An already-present item is success (idempotent).
///  - delete: nil is UNSCOPED (deletes across ALL of the app's groups); non-nil
///           scopes to that group. Absent is success. (migrate() never deletes.)
public protocol KeychainItemStore {
    func read(account: String, accessGroup: String?) throws -> Data?
    func add(account: String, accessGroup: String?, data: Data) throws
    func delete(account: String, accessGroup: String?) throws
}

public enum KeychainAccessGroupMigration {
    /// Ensure each account exists in `targetGroup`, copying from wherever it
    /// currently lives. Best-effort per account (a throw aborts that account but
    /// the next run retries). Never deletes (see the file header).
    public static func migrate(accounts: [String],
                               toGroup targetGroup: String,
                               store: KeychainItemStore) throws {
        for account in accounts {
            // Scoped read: already in the target group? Nothing to do.
            if try store.read(account: account, accessGroup: targetGroup) != nil {
                continue
            }
            // Unscoped read finds the item wherever it lives (the default group
            // on a pre-migration install).
            guard let data = try store.read(account: account, accessGroup: nil) else {
                continue
            }
            try store.add(account: account, accessGroup: targetGroup, data: data)
        }
    }
}
