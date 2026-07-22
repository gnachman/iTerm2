//
//  iTermUpgradeSafeKeychain.swift
//  iTerm2
//
//  A drop-in replacement for the three generic-password SecItem primitives
//  (copy / add / delete) that stores items in the macOS DATA-PROTECTION keychain
//  instead of the legacy login keychain, and transparently migrates any value
//  still living in the login keychain on first read.
//
//  Why this exists: login-keychain items are gated by an ACL that trusts only the
//  exact code signature that wrote them. After an app upgrade the running binary's
//  signature differs from the writer's, so every first read pops the "iTerm2 wants
//  to use your confidential information" confirmation prompt. Data-protection
//  keychain items are instead authorized by the app's keychain-access-group
//  entitlement, which is stable across any build the same team signs. So once an
//  item lives here, upgrades read it silently: no prompt, ever.
//
//  This helper deliberately speaks the raw (OSStatus, Data?) SecItem vocabulary
//  rather than a richer result type, so existing call sites (CompanionMacIdentity,
//  CompanionPushNonceRegistry, AITermControllerObjC) keep their own carefully
//  tuned interpretation of a read result (32-byte validation, absent-vs-unreadable,
//  hard-error caching policy) unchanged and only swap the storage layer underneath.
//
//  MIGRATION SAFETY (read path): the login-keychain copy is deleted (reaped) ONLY after
//  the data-protection copy is written AND read back byte-for-byte. If either half fails
//  the login copy is left intact and its value is still returned, so the worst case is
//  "keeps prompting like before" rather than "secret lost." The data-protection reads and
//  writes pin kSecAttrAccessGroup EXPLICITLY (read from our own entitlement, never
//  hardcoded, matched by suffix) so a later launch reads the SAME group the write used;
//  relying on the implicit default group previously caused a migrated item to read as
//  errSecItemNotFound on a subsequent launch.
//
//  WRITE SAFETY: `setGenericPassword` is update-or-insert (never delete-then-add), so a
//  transient write failure cannot destroy the prior value. On success it reaps any
//  lingering login-keychain copy so a rotate/clear erases the old secret. On failure it
//  falls back to the LOGIN keychain ONLY when the data-protection keychain can't serve a
//  stale value: always for errSecMissingEntitlement (an unsigned build - reads also miss
//  DP and consult login), and for a hard error (locked keychain) ONLY when DP has no item
//  for this account. If a hard error occurs while a STALE data-protection item exists, we
//  do NOT write to login - reads would hit the stale DP value and never consult login
//  (migration fires only on a DP miss), so the fresh value survives only in the caller's
//  in-memory cache for the session rather than being silently shadowed.
//
//  Clearing a secret must be an explicit `deleteGenericPassword`, NOT a write of empty
//  Data: an empty kSecValueData does not round-trip reliably. deleteGenericPassword
//  removes BOTH copies and returns false if a copy may survive, since a surviving login
//  copy would resurrect via migration on the next read.
//

import Foundation

enum iTermUpgradeSafeKeychain {
    // MARK: - Public SecItem-shaped surface

    /// Data-protection-keychain analog of SecItemCopyMatching for a single generic
    /// password, with transparent one-time migration from the login keychain.
    ///
    /// Returns exactly what a SecItemCopyMatching against the data-protection
    /// keychain would return once migration has completed: `(errSecSuccess, data)`
    /// when present, `(errSecItemNotFound, nil)` when genuinely absent from both
    /// stores, or a hard error status (with nil data) otherwise. `accessible` is the
    /// kSecAttrAccessible value used when a migrated value is (re)written into the
    /// data-protection keychain, so the caller controls this-device-only vs
    /// transferable semantics per item family.
    static func copyGenericPassword(service: String,
                                    account: String,
                                    accessible: CFString) -> (OSStatus, Data?) {
        let (dpStatus, dpData) = dataProtectionCopy(service: service, account: account)
        switch planAfterDataProtectionRead(status: dpStatus) {
        case .useDataProtectionResult:
            if dpStatus != errSecSuccess {
                // Present-but-unreadable or another hard error: the item is neither
                // served nor migrated, and we deliberately do NOT fall through to the
                // login keychain (that would mask the error as absent). The happy
                // path (a clean read) is intentionally left unlogged to avoid noise.
                RLog("UpgradeSafeKeychain: data-protection read of '\(service)' / '\(account)' hard-errored (item not served, not migrated): \(describe(dpStatus))")
            }
            return (dpStatus, dpData)
        case .consultLegacy:
            // DLog the miss detail (status + resolved group) so it's available in a debug
            // log without churning the RLog ring on every unconfigured item. Surface only
            // errSecMissingEntitlement as RLog: expected on unsigned/dev builds, but on a
            // SIGNED build it means the entitlement is missing or wrong.
            DLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - data-protection read miss: \(describe(dpStatus)), accessGroup=\(accessGroup ?? "<nil>")")
            if dpStatus == errSecMissingEntitlement {
                RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - data-protection keychain unavailable (errSecMissingEntitlement); falling back to login keychain. Expected on unsigned/dev builds; on a signed build the entitlement is missing.")
            }
            break
        }
        let (legacyStatus, legacyData) = legacyCopy(service: service, account: account)
        switch planAfterLegacyRead(status: legacyStatus) {
        case .migrate:
            guard shouldMigrateLegacyValue(legacyData), let legacyValue = legacyData else {
                // A present-but-empty login-keychain item is a pre-migration "cleared"
                // tombstone. Nothing meaningful to migrate; reap it and report absent
                // (callers treat absent and "" identically), so it can't be re-read.
                RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' present-but-empty in login keychain (tombstone); reaping and reporting absent")
                reapLegacyReportingStatus(service: service, account: account)
                return (errSecItemNotFound, nil)
            }
            RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' found in login keychain (\(legacyValue.count) bytes); migrating to data-protection keychain")
            // Best-effort: even if the write half fails, we still hand the caller the
            // value we read from the legacy keychain, so nothing breaks; the migration is
            // retried on the next read.
            migrate(data: legacyValue,
                    service: service,
                    account: account,
                    accessible: accessible)
            return (errSecSuccess, legacyValue)
        case .reportAbsent:
            // Genuinely absent from both stores (an unconfigured item, or one already
            // cleared). DLog: this is the common case for any unconfigured item and would
            // otherwise churn the RLog ring on every launch.
            DLog("UpgradeSafeKeychain: '\(service)' / '\(account)' absent from both the data-protection and login keychains")
            return (errSecItemNotFound, nil)
        case .reportLegacyError:
            RLog("UpgradeSafeKeychain: login-keychain read of '\(service)' / '\(account)' failed, cannot migrate: \(describe(legacyStatus))")
            return (legacyStatus, nil)
        }
    }

    /// Update-or-insert a single generic password. Prefers the data-protection
    /// keychain; on success it also reaps any lingering login-keychain copy so a
    /// rotate/clear erases the old secret. If the data-protection keychain is
    /// unusable (errSecMissingEntitlement, e.g. an unsigned/dev build) the value is
    /// written to the login keychain instead so nothing is silently dropped. Returns
    /// errSecSuccess when the value was persisted somewhere, otherwise the failing
    /// status. NOT for clearing a value: pass through `deleteGenericPassword` for that
    /// (an empty write does not round-trip and can resurrect via migration).
    @discardableResult
    static func setGenericPassword(_ data: Data,
                                   service: String,
                                   account: String,
                                   accessible: CFString) -> OSStatus {
        let dpStatus = dataProtectionUpsert(data,
                                            service: service,
                                            account: account,
                                            accessible: accessible)
        switch dpStatus {
        case errSecSuccess:
            // Reap any lingering login-keychain copy so a rotate/clear erases the old
            // secret (and a later data-protection read miss can't fall back to a stale
            // value). reapLegacyReportingStatus targets the FILE keychain explicitly (see
            // legacyQuery) so it can't delete the data-protection copy we just wrote.
            // DLog, not RLog: this fires on every write, including per-push nonce saves,
            // which would otherwise churn the RLog ring. reapLegacyReportingStatus already
            // RLogs a genuinely unexpected delete error.
            let reapStatus = reapLegacyReportingStatus(service: service, account: account)
            DLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - wrote to data-protection keychain (accessGroup=\(accessGroup ?? "<nil>")); login reap: \(describe(reapStatus))")
            return errSecSuccess
        case errSecMissingEntitlement:
            // This build cannot use the data-protection keychain (no access group).
            // Persist to the login keychain so the value survives, exactly as before
            // this migration existed. Reads fall back to the login keychain too.
            RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - data-protection write unavailable (errSecMissingEntitlement); writing to the login keychain instead (expected on unsigned/dev builds)")
            return legacyUpsert(data, service: service, account: account, accessible: accessible)
        default:
            // A hard data-protection write error (e.g. errSecInteractionNotAllowed /
            // errSecAuthFailed when the keychain is locked or not yet first-unlocked).
            //
            // Falling back to the login keychain is safe ONLY when the data-protection
            // keychain has NO item for this account (a brand-new secret): a later read then
            // misses DP and migrates the login copy forward. But if a STALE data-protection
            // item already exists, a login write would be permanently shadowed - reads hit
            // the stale DP value and never consult login, because migration fires only on a
            // DP MISS. So fall back only when DP is confirmed empty here; otherwise surface
            // the error and let the caller's in-memory cache hold the fresh value for this
            // session (same as the both-writes-failed case).
            let (existingStatus, _) = dataProtectionCopy(service: service, account: account)
            if existingStatus == errSecItemNotFound {
                RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - data-protection write failed (\(describe(dpStatus))) and no data-protection item exists; falling back to the login keychain")
                return legacyUpsert(data, service: service, account: account, accessible: accessible)
            }
            RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - data-protection write failed (\(describe(dpStatus))) while a data-protection item is present (read \(describe(existingStatus))); NOT falling back to login, which would be shadowed by the stale value. The new value survives only in the caller's in-memory cache this session.")
            return dpStatus
        }
    }

    /// Remove the item from BOTH stores. Used for deliberate user actions (unpair,
    /// clear key) where fully erasing the secret matters; the legacy delete may prompt,
    /// but the user is present and acting intentionally. Returns true only if the item is
    /// genuinely gone from both stores; a false return means a copy may survive and the
    /// caller should treat the clear as not fully done (and can retry).
    ///
    /// ORDER MATTERS: the LOGIN copy is deleted FIRST, and the data-protection copy only
    /// if that succeeded. This guarantees we never reach the one dangerous state -
    /// (data-protection empty, login present) - where a later read misses DP, falls back
    /// to the surviving login copy, and MIGRATES a deliberately-cleared secret back into
    /// DP. In every failure state the item instead just reads as still-present (a clear
    /// that didn't take), which is retryable and never a silent resurrection.
    @discardableResult
    static func deleteGenericPassword(service: String, account: String) -> Bool {
        let legacyStatus = SecItemDelete(legacyQuery(service: service, account: account) as CFDictionary)
        let legacyOK = (legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound)
        guard legacyOK else {
            // Login delete failed (locked keychain, denied confirmation on the
            // code-signature-gated item, ...). Leave the data-protection copy in place so
            // the item keeps reading as present and cannot resurrect via migration; the
            // clear simply did not take and the caller should retry.
            RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - login-keychain delete FAILED: \(describe(legacyStatus)). Leaving the data-protection copy in place so the secret can't resurrect; clear did not fully take.")
            return false
        }
        let dpStatus = SecItemDelete(dataProtectionQuery(service: service, account: account) as CFDictionary)
        // errSecMissingEntitlement means this build has no data-protection keychain
        // (unsigned/dev): there is nothing to delete there and the login delete above
        // already removed the real copy, so treat it as gone - mirroring the read/write
        // paths which also treat errSecMissingEntitlement as "DP not in use here."
        let dpOK = (dpStatus == errSecSuccess
                    || dpStatus == errSecItemNotFound
                    || dpStatus == errSecMissingEntitlement)
        if !dpOK {
            RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - data-protection delete failed: \(describe(dpStatus)). A data-protection copy may survive; the item will still read as present (clear did not fully take).")
        }
        return dpOK
    }

    // MARK: - Pure migration decisions (unit tested)

    enum DataProtectionReadPlan: Equatable {
        /// The data-protection keychain answered definitively (a value, or a hard
        /// error). Return its result verbatim; do not touch the legacy keychain.
        case useDataProtectionResult
        /// The data-protection keychain has no such item. Fall back to the legacy
        /// keychain, where a pre-migration value may still live.
        case consultLegacy
    }

    /// Given the data-protection read status, decide whether we already have an
    /// answer or must consult the legacy keychain. A genuine not-found sends us to
    /// legacy. So does errSecMissingEntitlement: it means this build cannot use the
    /// data-protection keychain at all (the keychain-access-groups entitlement is
    /// absent or unsigned, e.g. a misconfigured/ad-hoc build), so the login keychain
    /// is still the real store and we must fall back to it, degrading to the old
    /// (prompting) behavior rather than reporting every secret unreadable. A success
    /// is returned as-is, and any other hard error is surfaced rather than masked by
    /// a legacy read (so a locked keychain isn't wrongly reported as absent).
    static func planAfterDataProtectionRead(status: OSStatus) -> DataProtectionReadPlan {
        if status == errSecItemNotFound || status == errSecMissingEntitlement {
            return .consultLegacy
        }
        return .useDataProtectionResult
    }

    enum LegacyReadPlan: Equatable {
        /// The legacy keychain has the value: migrate it into the data-protection
        /// keychain and return it.
        case migrate
        /// Absent from the legacy keychain too: the item genuinely does not exist.
        case reportAbsent
        /// A hard error reading the legacy keychain: surface it; do not migrate.
        case reportLegacyError
    }

    /// Given the legacy read status (only consulted when the data-protection
    /// keychain had nothing), decide the outcome.
    static func planAfterLegacyRead(status: OSStatus) -> LegacyReadPlan {
        if status == errSecSuccess {
            return .migrate
        }
        if status == errSecItemNotFound {
            return .reportAbsent
        }
        return .reportLegacyError
    }

    /// Whether a value successfully read from the legacy keychain is worth migrating
    /// forward. A nil or empty value is a pre-migration "cleared" tombstone (or
    /// nothing) that must be reaped instead of migrated: an empty kSecValueData does
    /// not round-trip, so migrating it would never confirm readback and would re-run
    /// on every launch, and re-storing it could resurrect a key the user cleared.
    static func shouldMigrateLegacyValue(_ data: Data?) -> Bool {
        guard let data else { return false }
        return !data.isEmpty
    }

    // MARK: - Data-protection keychain I/O

    /// The app's own keychain access group, read from OUR code signature's
    /// keychain-access-groups entitlement so it is never hardcoded (it resolves to the
    /// team-prefixed value, e.g. "TEAMID.com.googlecode.iterm2"). nil on a build with no
    /// such entitlement (unsigned/dev), where callers then omit the group and the
    /// data-protection write fails cleanly, falling back to the login keychain. Cached:
    /// the signature can't change while the process runs.
    static let accessGroup: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil),
              let groups = value as? [String],
              !groups.isEmpty else {
            return nil
        }
        // Match by SUFFIX, not array position: correct today (a single entry resolving to
        // "TEAMID.com.googlecode.iterm2"), but if a second access group is ever added
        // (e.g. a shared group for an XPC helper) or the OS reorders them, pinning
        // groups.first could silently target the wrong group and make stored secrets read
        // as errSecItemNotFound. Fall back to the first entry only if none matches.
        return groups.first(where: { $0.hasSuffix(".com.googlecode.iterm2") }) ?? groups.first
    }()

    private static func dataProtectionQuery(service: String, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Pin the access group EXPLICITLY rather than relying on the implicit default,
        // so writes and reads always target the same group across launches (relying on
        // the default group is the suspected cause of a migrated-but-unreadable item).
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func dataProtectionCopy(service: String, account: String) -> (OSStatus, Data?) {
        var query = dataProtectionQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    private static func dataProtectionUpsert(_ data: Data,
                                             service: String,
                                             account: String,
                                             accessible: CFString) -> OSStatus {
        return upsert(baseQuery: dataProtectionQuery(service: service, account: account),
                      data: data,
                      accessible: accessible)
    }

    // Update-then-add-then-update, never delete-then-add.
    //
    // 1. A transient failure (locked keychain, errSecInteractionNotAllowed at launch,
    //    disk pressure) must not destroy a value that is already stored, so we never
    //    delete first: SecItemUpdate an existing item, SecItemAdd a missing one.
    // 2. TOCTOU: two contexts that share the access group (e.g. the main app and the
    //    Notification Service Extension both persisting companion state) can both see
    //    the item missing, both SecItemAdd, and the loser gets errSecDuplicateItem.
    //    That is "someone else already inserted it," NOT a hard failure, so retry it as
    //    an update rather than letting setGenericPassword mistake it for a write error
    //    and spuriously fall back to the login keychain.
    // 3. NOTE: SecItemUpdate applies ONLY kSecValueData, so an already-stored item keeps
    //    its ORIGINAL accessibility; `accessible` takes effect solely on the SecItemAdd
    //    branch. Every (service, account) uses a stable `accessible` today. A future
    //    caller needing to TIGHTEN an existing item's accessibility must delete-then-add
    //    (or update kSecAttrAccessible explicitly); this path would report success while
    //    silently keeping the looser value.
    private static func upsert(baseQuery: [String: Any],
                               data: Data,
                               accessible: CFString) -> OSStatus {
        let attributesToUpdate = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate)
        if updateStatus != errSecItemNotFound {
            return updateStatus
        }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessible
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Lost the insert race; the item now exists, so update it.
            return SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate)
        }
        return addStatus
    }

    // MARK: - Legacy (login) keychain I/O

    private static func legacyQuery(service: String, account: String) -> [String: Any] {
        // kSecUseDataProtectionKeychain: false is REQUIRED, not optional. On an entitled
        // app, OMITTING it does not reliably mean "file keychain": SecItemCopyMatching
        // read the file item, but SecItemDelete/SecItemUpdate resolved to the DATA-
        // PROTECTION keychain instead, so the reap after a migrate deleted the copy we had
        // just written (readback-confirmed) rather than the old login copy - items with no
        // login fallback (the companion identity key, the push nonce) then vanished on the
        // next launch. Pinning false forces EVERY legacy op (read, delete, upsert) to the
        // file keychain, so it can never touch the data-protection copy.
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: false,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func legacyCopy(service: String, account: String) -> (OSStatus, Data?) {
        var query = legacyQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    // Login-keychain write fallback (used when the data-protection keychain is
    // unavailable). Same non-destructive, race-tolerant discipline as the data-protection
    // upsert (see `upsert`).
    private static func legacyUpsert(_ data: Data,
                                     service: String,
                                     account: String,
                                     accessible: CFString) -> OSStatus {
        return upsert(baseQuery: legacyQuery(service: service, account: account),
                      data: data,
                      accessible: accessible)
    }

#if ITERM_DEBUG
    // MARK: - Testing support (compiled out of release builds via ITERM_DEBUG)

    /// Delete EVERY generic-password item the app owns in its data-protection access
    /// group. Test-only: used to reset the data-protection keychain between migration
    /// tests. Scoped to our own access group, so it can only touch items this app wrote,
    /// never another app's. No-op (and returns nil count) when the build has no access
    /// group (unsigned/dev), since it can't have written anything there. This destructive
    /// routine is wrapped in ITERM_DEBUG so it physically does not exist in a release
    /// binary, not merely uncalled.
    @discardableResult
    static func purgeAllDataProtectionItemsForTesting() -> Int? {
        guard let accessGroup else {
            RLog("UpgradeSafeKeychain: purge requested but no access group (unsigned build); nothing to purge")
            return nil
        }
        // Count first (for the log), then delete the whole group in one call.
        var countQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let matchStatus = SecItemCopyMatching(countQuery as CFDictionary, &result)
        let count = (result as? [[String: Any]])?.count ?? 0
        countQuery.removeValue(forKey: kSecMatchLimit as String)
        countQuery.removeValue(forKey: kSecReturnAttributes as String)
        let deleteStatus = SecItemDelete(countQuery as CFDictionary)
        RLog("UpgradeSafeKeychain: PURGE of data-protection group '\(accessGroup)' - matched \(count) item(s) (\(describe(matchStatus))), delete \(describe(deleteStatus))")
        return count
    }
#endif

    // MARK: - Migration

    private static func migrate(data: Data,
                                service: String,
                                account: String,
                                accessible: CFString) {
        let writeStatus = dataProtectionUpsert(data,
                                               service: service,
                                               account: account,
                                               accessible: accessible)
        guard writeStatus == errSecSuccess else {
            // Keep the legacy copy: the value is still returned to the caller and the
            // migration retries next launch. This is the ad-hoc/dev-build case where
            // the signature carries no usable access group.
            RLog("UpgradeSafeKeychain: MIGRATION of '\(service)' / '\(account)' FAILED at the data-protection write: \(describe(writeStatus)). Login-keychain copy kept; will retry next read.")
            return
        }
        let (readbackStatus, readbackData) = dataProtectionCopy(service: service, account: account)
        guard readbackStatus == errSecSuccess, readbackData == data else {
            // Wrote but can't confirm it read back identically: do NOT reap, or we could
            // lose the only good copy. Log byte counts (never the bytes) so a size
            // mismatch is diagnosable.
            RLog("UpgradeSafeKeychain: MIGRATION of '\(service)' / '\(account)' wrote but readback did not confirm (status \(describe(readbackStatus)); \(readbackData?.count ?? -1) vs \(data.count) bytes). Login-keychain copy kept.")
            return
        }
        // The data-protection copy is written and confirmed readable, and it is pinned to
        // an EXPLICIT access group (logged) so a later launch reads the same group. Now
        // reap the code-signature-gated login copy: that delete is what actually stops
        // future upgrade prompts, and it also prevents a data-protection read miss from
        // later falling back to (and re-migrating) a stale value.
        let reapStatus = reapLegacyReportingStatus(service: service, account: account)
        // DIAGNOSTIC (temporary): report the ACTUAL reap status instead of an unconditional
        // "reaped." errSecItemNotFound = the login-keychain delete matched nothing (so the
        // login copy is NOT actually removed if the delete is being scoped to the app's
        // access group while the read searched all groups); -25244 = ownership-locked.
        RLog("UpgradeSafeKeychain: migrated '\(service)' / '\(account)' into the data-protection keychain (group \(accessGroup ?? "<none>"), readback confirmed); login reap: \(describe(reapStatus))")
    }

    // Delete a login-keychain copy after the data-protection copy is authoritative. Returns
    // the delete status. A missing item (errSecItemNotFound) or success is fine; anything
    // else is logged and non-fatal (a stale copy just means the upgrade prompt can recur).
    @discardableResult
    private static func reapLegacyReportingStatus(service: String, account: String) -> OSStatus {
        let status = SecItemDelete(legacyQuery(service: service, account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            RLog("UpgradeSafeKeychain: '\(service)' / '\(account)' - failed to reap login-keychain copy: \(describe(status)). A stale copy may remain and re-prompt.")
        }
        return status
    }

    /// Human-readable rendering of an OSStatus for logs (never includes secret data).
    private static func describe(_ status: OSStatus) -> String {
        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "unknown"
        return "OSStatus \(status) (\(message))"
    }
}
