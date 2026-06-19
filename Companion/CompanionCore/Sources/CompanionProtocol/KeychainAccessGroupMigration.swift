//
//  KeychainAccessGroupMigration.swift
//  CompanionCore
//
//  Moves keychain items from the app's default access group into a shared App
//  Group keychain access group so the Notification Service Extension can read
//  them. kSecAttrAccessGroup cannot be changed with SecItemUpdate, so the move
//  is add-to-new-then-delete-old, made crash-safe by that ordering: a crash
//  after the add but before the delete leaves the item readable in BOTH groups
//  rather than bricking it, and the next run sees it in the target and finishes
//  (deleting the leftover). Idempotent: safe to run on every launch.
//
//  The SecItem operations are injected (KeychainItemStore) so the state machine
//  is unit-testable without a real keychain.
//

import Foundation

/// The minimal keychain surface the migration needs. `accessGroup` nil means
/// the app's default group (the items' pre-migration home).
public protocol KeychainItemStore {
    func read(account: String, accessGroup: String?) throws -> Data?
    /// Add the item to `accessGroup`. An already-present item is success (not an
    /// error), so a retried migration is idempotent.
    func add(account: String, accessGroup: String?, data: Data) throws
    /// Delete the item from `accessGroup`. Absent is success.
    func delete(account: String, accessGroup: String?) throws
}

public enum KeychainAccessGroupMigration {
    /// Move each account from the default group into `targetGroup`. Best-effort
    /// per account (a throw aborts that account but the next run retries).
    public static func migrate(accounts: [String],
                               toGroup targetGroup: String,
                               store: KeychainItemStore) throws {
        for account in accounts {
            if try store.read(account: account, accessGroup: targetGroup) != nil {
                // Already in the target. Delete any leftover default-group copy
                // (handles a prior crash after add / before delete). Idempotent.
                try store.delete(account: account, accessGroup: nil)
                continue
            }
            guard let data = try store.read(account: account, accessGroup: nil) else {
                // Nothing to migrate: never created, or already moved + cleaned.
                continue
            }
            // Add BEFORE delete: a crash here leaves the item readable in both
            // groups, never neither.
            try store.add(account: account, accessGroup: targetGroup, data: data)
            try store.delete(account: account, accessGroup: nil)
        }
    }
}
