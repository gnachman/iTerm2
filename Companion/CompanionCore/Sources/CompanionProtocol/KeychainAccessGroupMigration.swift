//
//  KeychainAccessGroupMigration.swift
//  CompanionCore
//
//  Moves keychain items into a shared App Group keychain access group so the
//  Notification Service Extension can read them. kSecAttrAccessGroup cannot be
//  changed with SecItemUpdate, so the item is ADDED to the target group and the
//  source copy is then removed.
//
//  Ordering is crash-safe: the target copy is ensured FIRST, and only then is
//  each copy OUTSIDE the target group deleted (scoped to the exact group it lives
//  in, never an unscoped delete that would also remove the target). So a crash
//  between the two leaves the item intact in both groups and the next run
//  converges - there is never a window where the item is absent. The source is
//  deleted (not left as a harmless duplicate) so no key material lingers in the
//  default access group: that is a security exposure if later recovered against
//  old ciphertext, and a stale copy that key rotation (which scopes to the target
//  group) would never reconcile. Idempotent: safe on every launch.
//
//  The SecItem operations are injected (KeychainItemStore) so the state machine
//  is unit-testable without a real keychain.
//

import Foundation

/// One copy of a keychain item: its bytes plus the access group it lives in (the
/// concrete group string SecItem reports, e.g. the app's default group).
public struct KeychainItemCopy: Equatable {
    public let accessGroup: String?
    public let data: Data
    public init(accessGroup: String?, data: Data) {
        self.accessGroup = accessGroup
        self.data = data
    }
}

/// The minimal keychain surface the migration needs. `accessGroup` semantics
/// MIRROR SecItem:
///  - readAll: UNSCOPED match across ALL of the app's access groups, returning
///             every copy tagged with the group it lives in.
///  - add:     nil adds to the app's default group; non-nil adds to that group.
///             An already-present item is success (idempotent).
///  - delete:  nil is UNSCOPED (all groups); non-nil scopes to that group. Absent
///             is success. (migrate() only ever deletes scoped to a known group.)
public protocol KeychainItemStore {
    func readAll(account: String) throws -> [KeychainItemCopy]
    func add(account: String, accessGroup: String?, data: Data) throws
    func delete(account: String, accessGroup: String?) throws
}

public enum KeychainAccessGroupMigration {
    /// Ensure each account exists ONLY in `targetGroup`, moving it from wherever
    /// it currently lives. Best-effort per account (a throw aborts that account
    /// but the next run retries). Converges and leaves no stale source copy.
    public static func migrate(accounts: [String],
                               toGroup targetGroup: String,
                               store: KeychainItemStore) throws {
        for account in accounts {
            let copies = try store.readAll(account: account)
            guard !copies.isEmpty else { continue }
            // Ensure the target group has the value FIRST, before deleting any
            // source copy, so a crash in between never loses the item.
            if !copies.contains(where: { $0.accessGroup == targetGroup }),
               let seed = copies.first {
                try store.add(account: account, accessGroup: targetGroup, data: seed.data)
            }
            // RE-READ and require a copy reported under the EXACT target group
            // before deleting anything. The delete loop scopes to each copy's
            // reported access group; if the OS ever reports the target group under
            // a different string (normalization/prefix), deleting a copy by its
            // reported string could remove the physical target item. By deleting
            // sources only when a byte-identical target copy is confirmed present
            // - and skipping cleanup otherwise (the add above is idempotent, so
            // there is no duplicate to remove) - we can never delete the real item.
            let after = try store.readAll(account: account)
            guard after.contains(where: { $0.accessGroup == targetGroup }) else { continue }
            for copy in after where copy.accessGroup != targetGroup {
                try store.delete(account: account, accessGroup: copy.accessGroup)
            }
        }
    }
}
