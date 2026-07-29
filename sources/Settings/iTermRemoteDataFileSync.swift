//
//  iTermRemoteDataFileSync.swift
//  iTerm2SharedARC
//
//  Mirrors a curated allowlist of user-config data files that live outside NSUserDefaults
//  (snippets, global notes, session-icon customizations) between Application Support and a
//  custom settings folder, so they ride along with the existing "Load settings from a custom
//  folder" sync. See iTermRemotePreferences for the hooks.
//
//  Deliberately excludes anything risky or machine-specific: dynamic profiles, scripts, secure
//  settings, the Python runtime, and all history/DB/cache/transient state. Sync is local-folder
//  only (a URL can host a single plist but not a file tree).
//

import Foundation
import os.lock

@objc(iTermRemoteDataFileSync)
class iTermRemoteDataFileSync: NSObject {
    // The two failure modes mirror() actually raises (both caught only to log). A file that exists
    // but can't be read is a separate UnreadableFile (thrown by fileDigest), because it's handled
    // differently (defer the sync rather than abort a copy).
    enum SyncError: LocalizedError {
        case backupFailed(itemName: String, underlying: Error)
        case copyFailed(itemName: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .backupFailed(let itemName, let error):
                return "Failed to backup \(itemName): \(error.localizedDescription)"
            case .copyFailed(let itemName, let error):
                return "Failed to copy \(itemName): \(error.localizedDescription)"
            }
        }
    }
    private enum Item {
        // A single file, e.g. "snippets.plist".
        case file(String)
        // A directory or package bundle copied as an opaque subtree, e.g. "notes.rtfd".
        case directory(String)

        var name: String {
            switch self {
            case .file(let name), .directory(let name):
                return name
            }
        }
    }

    // Allowlisted item names, exposed to ObjC so the per-item owner-reload mapping in
    // applyImportedRemoteDataFilesForItems: references these constants instead of duplicating the
    // string literals. A rename here becomes a compile error there, rather than silently breaking the
    // reload of that item after an import.
    @objc static let snippetsPlistName = "snippets.plist"
    @objc static let notesPackageName = "notes.rtfd"
    @objc static let graphicColorsName = "graphic_colors.json"
    @objc static let graphicIconsName = "graphic_icons.json"

    // The allowlist. Each name is relative to Application Support locally and to <folder>/Data
    // remotely. notes.rtfd is an RTFD package (a directory bundle), so it is a directory.
    private static let allowlist: [Item] = [
        .file(snippetsPlistName),
        .directory(notesPackageName),
        .file(graphicColorsName),
        .file(graphicIconsName)
    ]

    // The allowlist in a deterministic order for signature framing. Precomputed once rather than
    // sorting on every contentSignature call.
    private static let signatureOrderedAllowlist: [Item] = allowlist.sorted { $0.name < $1.name }

    // Subfolder of the custom settings folder that holds the synced data files. Keeps them clear
    // of the root-level <bundleIdentifier>.plist.
    private static let dataSubfolder = "Data"

    // Staging-temp name framing. mirror() writes an atomic staging file as a sibling of the destination
    // (same volume) named tempPrefix + <UUID> + tempSuffix, and sweepStaleTempFiles removes only orphans
    // matching THAT exact framing. The distinctive "iterm2sync" namespace (not a bare ".<uuid>.tmp")
    // matters because the LOCAL mirror base is the shared Application Support root: a future iTerm2
    // feature or third-party tool dropping its own ".<uuid>.tmp" there must never be swept - only temps
    // this code demonstrably created are.
    private static let tempPrefix = ".iterm2sync."
    private static let tempSuffix = ".tmp"

    // Local-only folder (under Application Support, never synced because it is not in the allowlist)
    // where a file is preserved before it is overwritten or deleted by a sync. A propagated deletion
    // or a "wrong copy" conflict choice is then always recoverable: we never destroy the only copy of
    // a data file. Each copy operation gets its own timestamped subfolder.
    private static let backupSubfolder = "Settings Sync Backups"

    // Cap on retained backup folders. These are last-resort recovery copies, so keeping the most
    // recent N bounds disk use without losing practical recoverability. Default is 50 folders which
    // typically uses ~5-50MB depending on file sizes. Can be overridden via user defaults.
    private static var maxBackupFolders: Int {
        // Use iTermUserDefaults (not UserDefaults.standard) so a custom user-defaults suite is
        // honored. The NoSync prefix keeps this local-only.
        let userValue = iTermUserDefaults.userDefaults().integer(forKey: "NoSyncRemoteDataFileSyncMaxBackups")
        return userValue > 0 ? userValue : 50
    }

    // The allowlisted names, exposed for tests and for the drift guard in applyImportedRemoteDataFiles.
    @objc static var allowlistNames: [String] {
        return allowlist.map { $0.name }
    }

    // MARK: - Public API

    // Copy allowlisted items from Application Support to <remoteFolder>/Data. Always a union (never
    // deletes a folder item the local copy lacks): the pushing machine cannot prove the folder still
    // matches what it last saw (another machine may have added items, or this push may follow a
    // "use this Mac's" union that left the local copy missing the folder's disjoint items), so
    // deleting folder-only items here would destroy another machine's data. Deletion propagation is
    // handled only by the baseline-gated pull, never by the push.
    //
    // Example: Machine A has snippets+notes, Machine B has only snippets. When B does "Use this Mac's",
    // it pushes snippets to folder but must NOT delete the folder's notes (from A), as that would
    // lose A's data. The union preserves both machines' disjoint items.
    //
    // Returns true on success, logs detailed errors on failure. This is an UNGUARDED forced push: the
    // divergence guard (compare the folder to the baseline; defer if another machine wrote it) lives in
    // the caller -[iTermRemotePreferences writeDataFilesToRemoteFolder:], which does it there so it can
    // tell a "folder moved under us" defer apart from a partial-write failure (a false return here). The
    // conflict-resolver and discard callers push forcibly by design.
    //
    // CONCURRENCY LIMITATION (accepted, inherent to lock-free folder sync): the caller's guard read and
    // this mirror write are separate filesystem operations, so two machines editing the same shared item
    // at nearly the same instant can BOTH pass the guard (each reads the folder as still == baseline) and
    // the last writer wins. The loser's edit survives only in its own local "Settings Sync Backups";
    // worse, the loser advanced its baseline to its own signature during the push, so its next launch
    // sees remote != baseline / local == baseline as "only remote moved" and pulls the winner's copy
    // with no conflict prompt. Truly simultaneous edits are therefore not covered by the "which copy?"
    // prompt (which catches the common case: edits separated by at least a launch). A stronger fix would
    // need an atomic exchange or a per-item version baseline; that is out of scope here.
    @objc(copyLocalToRemoteWithRemoteFolder:)
    static func copyLocalToRemote(remoteFolder: String) -> Bool {
        guard let localBase = appSupportBase(create: false) else {
            DLog("copyLocalToRemote failed: Application Support directory is unavailable")
            return false
        }
        let remoteBase = (remoteFolder as NSString).appendingPathComponent(dataSubfolder)
        return mirrorAll(fromBase: localBase, toBase: remoteBase, deleteMissing: false,
                         createDestination: true, backupFolder: makeBackupFolder())
    }

    // Copy allowlisted items from <remoteFolder>/Data to Application Support.
    //
    // deleteMissing controls what happens to a local item the folder lacks:
    //   - false (union): leave it alone. Use for first adoption / "Keep Remote" / "Use Settings
    //     Folder's", where the folder simply may never have had that item, so its absence is not a
    //     deletion and must not destroy local-only data.
    //   - true (mirror): delete it locally. Only safe when the caller has confirmed (via the
    //     baseline) that the local copy exactly matched the folder's last-synced set, so the item's
    //     absence is a real deletion to propagate.
    //
    // Example with deleteMissing=false: Folder has snippets, local has notes. After pull, local has
    // both (union). The folder's lack of notes doesn't delete local notes.
    // Example with deleteMissing=true: Last sync had snippets+notes, folder now only has snippets
    // (notes deleted on another machine). Pull deletes local notes to propagate the deletion.
    //
    // Returns true if the folder had a readable Data subtree and the mirror completed (NOT "something
    // was actually copied" - true even when every item was already identical and nothing changed);
    // false on a real failure or when there is no remote Data dir. Logs detailed errors on failure. If
    // changedItems is non-nil, the names of the allowlisted items actually replaced or deleted are added
    // to it, so the caller can refresh only those in-memory owners (an unchanged item's owner must not
    // be told to reload, or a view holding unsaved edits could re-read stale disk content).
    @objc(copyRemoteToLocalWithRemoteFolder:deleteMissing:changedItems:)
    static func copyRemoteToLocal(remoteFolder: String, deleteMissing: Bool, changedItems: NSMutableSet?) -> Bool {
        guard let localBase = appSupportBase(create: true) else {
            DLog("copyRemoteToLocal failed: Application Support directory is unavailable")
            return false
        }
        let remoteBase = (remoteFolder as NSString).appendingPathComponent(dataSubfolder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: remoteBase, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            // No remote data folder: nothing to pull. This is not an error in initial setup.
            DLog("copyRemoteToLocal: No remote data folder at \(remoteBase), nothing to pull")
            return false
        }
        return mirrorAll(fromBase: remoteBase, toBase: localBase, deleteMissing: deleteMissing,
                         createDestination: false, backupFolder: makeBackupFolder(),
                         changedItems: changedItems)
    }

    // Delete every allowlisted item from Application Support, backing each up first. Used by a "Lose
    // Changes"/discard when the folder's Data subtree is absent: "take the folder's copy" then means
    // the folder holds nothing, so the local items should be removed (copyRemoteToLocal can't mirror
    // from a missing Data dir). Returns true on success.
    @objc(deleteLocalTargets)
    static func deleteLocalTargets() -> Bool {
        guard let localBase = appSupportBase(create: false) else {
            return false
        }
        let backupFolder = makeBackupFolder()
        let fileManager = FileManager.default
        // Best-effort: attempt EVERY item rather than aborting on the first failure, so a discard
        // removes as much as it can. Return true only if every present item was actually removed; the
        // caller relies on that to decide whether the local state now matches the folder's all-absent
        // state (and thus whether it's safe to adopt the all-absent baseline).
        var allRemoved = true
        for item in allowlist {
            let path = (localBase as NSString).appendingPathComponent(item.name)
            guard fileManager.fileExists(atPath: path) else {
                continue
            }
            do {
                try backUp(itemAt: path, name: item.name, into: backupFolder)
                try fileManager.removeItem(atPath: path)
            } catch {
                DLog("deleteLocalTargets: failed to remove \(item.name): \(error)")
                allRemoved = false
            }
        }
        return allRemoved
    }

    // True if any allowlisted target already exists under <remoteFolder>/Data. Used by the
    // first-run overwrite guard before this install writes data files to a folder for the first time.
    @objc(remoteHasAnyTargetWithRemoteFolder:)
    static func remoteHasAnyTarget(remoteFolder: String) -> Bool {
        let remoteBase = (remoteFolder as NSString).appendingPathComponent(dataSubfolder)
        return baseHasAnyTarget(base: remoteBase)
    }

    // Bounded variant (see remoteContentSignature:timeoutSeconds:): a fileExists loop still blocks on an
    // offline mount, so bound the consent-gate probe at launch. Returns false on timeout (treated as "no
    // target": don't prompt on an unreachable folder; defer to a later launch).
    @objc(remoteHasAnyTargetWithRemoteFolder:timeoutSeconds:)
    static func remoteHasAnyTarget(remoteFolder: String, timeoutSeconds: Double) -> Bool {
        return withTimeout(false, timeoutSeconds: timeoutSeconds) {
            remoteHasAnyTarget(remoteFolder: remoteFolder)
        }
    }

    // Runs `work` on a background queue and returns its result, or `defaultValue` if it doesn't finish
    // within timeoutSeconds (<= 0 runs synchronously). Bounds a blocking remote read against an offline
    // mount hang without stalling the main thread; on timeout the background work is abandoned (it
    // unblocks when the mount eventually times out). `work` must be self-contained (no shared mutable
    // state) since it may run off-main.
    private static func withTimeout<T>(_ defaultValue: T,
                                       timeoutSeconds: Double,
                                       _ work: @escaping () -> T) -> T {
        if timeoutSeconds <= 0 {
            return work()
        }
        let semaphore = DispatchSemaphore(value: 0)
        // Box so the (possibly still-running) background closure and this function don't both touch a
        // captured var; on success the semaphore establishes happens-before for the read.
        let box = Box(defaultValue)
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = work()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            DLog("withTimeout: work timed out after \(timeoutSeconds)s; returning default")
            return defaultValue
        }
        return box.value
    }

    // True if any allowlisted target exists locally in Application Support. Used by the load-time
    // reconcile to tell "nothing to lose locally" from a real conflict.
    @objc(localHasAnyTarget)
    static func localHasAnyTarget() -> Bool {
        guard let base = appSupportBase(create: false) else {
            return false
        }
        return baseHasAnyTarget(base: base)
    }

    private static func baseHasAnyTarget(base: String) -> Bool {
        let fileManager = FileManager.default
        for item in allowlist {
            if fileManager.fileExists(atPath: (base as NSString).appendingPathComponent(item.name)) {
                return true
            }
        }
        return false
    }

    // Content signature (hex SHA-256) of the allowlisted items in Application Support. Sensitive to
    // both content and presence so callers can detect file-only changes. This is called on the main
    // thread on every debounced autosave, so it short-circuits via a cheap stat fingerprint and only
    // re-reads and re-hashes the files when a stat shows something changed.
    @objc(localContentSignature)
    static func localContentSignature() -> String {
        guard let base = appSupportBase(create: false) else {
            return ""
        }
        return cachedContentSignature(base: base)
    }

    // The stat-cached signature for an explicit base. Internal so tests can drive it with a temp
    // directory (localContentSignature reads the real Application Support). The lock is a Mutex (a
    // heap-allocated os_unfair_lock pointer), NOT a value-type static var passed by `&`: taking the
    // address of a global os_unfair_lock var holds a Swift exclusivity (modify) access for the whole
    // duration of the blocking lock call, which two contending threads can trap on. See Mutex.swift.
    static func cachedContentSignature(base: String) -> String {
        let statBefore = statSignature(base: base)

        // A hit requires the SAME base AND a non-nil stat (nil carries no content identity). Keying on
        // the base too is belt-and-suspenders against a different base whose stat string happens to
        // coincide (the seam is driven by tests with many temp bases): statToken already includes st_dev
        // and st_ino, so a collision across bases is not actually expected, but the base key makes it
        // impossible rather than merely unlikely.
        let hit: String? = localSignatureCacheMutex.sync { () -> String? in
            if let statBefore,
               base == localSignatureCacheBase,
               statBefore == localSignatureCacheStat,
               !localSignatureCacheContent.isEmpty {
                return localSignatureCacheContent
            }
            return nil
        }
        if let hit {
            return hit
        }

        let content = contentSignature(base: base)
        // Re-stat AFTER hashing and cache only if the stat was STABLE across the read (statBefore ==
        // statAfter, both non-nil). If a file changed in the window before OR after the read, the two
        // stats differ (or one is nil) and we leave a cache miss rather than caching a stat that
        // doesn't correspond to the bytes we hashed (which a later matching stat could then return for
        // the wrong content).
        let statAfter = statSignature(base: base)
        // Don't cache "" (a present-but-unreadable file): the caller should keep deferring until it
        // becomes readable, and a future readable state must not be masked by a cached empty result.
        if !content.isEmpty, let statBefore, let statAfter, statBefore == statAfter {
            localSignatureCacheMutex.sync {
                localSignatureCacheBase = base
                localSignatureCacheStat = statAfter
                localSignatureCacheContent = content
            }
        }
        return content
    }

    // Test-only: clear the process-global signature cache so tests don't leak state into each other.
    static func resetSignatureCacheForTesting() {
        localSignatureCacheMutex.sync {
            localSignatureCacheBase = ""
            localSignatureCacheStat = ""
            localSignatureCacheContent = ""
        }
    }

    // Content signature of the allowlisted items under <remoteFolder>/Data.
    @objc(remoteContentSignatureWithRemoteFolder:)
    static func remoteContentSignature(remoteFolder: String) -> String {
        return contentSignature(base: (remoteFolder as NSString).appendingPathComponent(dataSubfolder))
    }

    // The signature a folder (or local base) produces when it holds NONE of the allowlisted items.
    // Exactly what contentSignature returns for an empty/absent base, computed WITHOUT any filesystem
    // access so a caller that already holds a readable remote signature can decide "does the folder have
    // any target?" by string comparison instead of a second fileExists probe (which, unbounded, can hang
    // the main thread on an offline mount). Frames each item's .absent case the same way `append` does,
    // so it stays in lockstep with contentSignature.
    @objc(allAbsentSignature)
    static func allAbsentSignature() -> String {
        var blob = Data()
        for item in signatureOrderedAllowlist {
            appendFrame("ABSENT:\(item.name)", to: &blob)
        }
        return ((blob as NSData).it_sha256() as NSData).it_hexEncoded()
    }

    // Bounded variant of remoteContentSignature: computes the hash on a background queue and waits at
    // most timeoutSeconds. Returns "" on timeout, which every caller already treats as "unreadable ->
    // defer this pass to the next launch". This bounds the load-time reconcile and the quit/autosave
    // push against a hang when the custom folder is on an offline/slow SMB/NFS/iCloud mount: the
    // signature read is the FIRST remote access on each path, so a timeout here defers before any mirror
    // read/write is attempted. contentSignature is a pure function (no shared mutable state), so running
    // it off the main thread is safe; on timeout the background read is simply abandoned (it unblocks
    // when the mount eventually times out).
    @objc(remoteContentSignatureWithRemoteFolder:timeoutSeconds:)
    static func remoteContentSignature(remoteFolder: String, timeoutSeconds: Double) -> String {
        // "" on timeout is what every caller already treats as "unreadable -> defer this pass".
        return withTimeout("", timeoutSeconds: timeoutSeconds) {
            remoteContentSignature(remoteFolder: remoteFolder)
        }
    }

    // The baseline to record after a successful union push from Application Support to <remoteFolder>.
    // Composed WITHOUT a third full read of the (slow, possibly racing) remote subtree: a union push
    // leaves the folder equal to the local copy for every item local has, so those items are hashed
    // from the LOCAL copy; only an item the folder had that local lacks (a union extra the push left
    // alone) is read from the folder. This is race-free for the pushed items: it records exactly what
    // we pushed, so a concurrent foreign overwrite of a shared item is later detected as a real
    // divergence ("only remote moved") rather than silently baked into the baseline (which would let
    // the next push clobber it). Returns "" if a needed file is unreadable, like contentSignature.
    @objc(remoteBaselineAfterUnionPushWithRemoteFolder:)
    static func remoteBaselineAfterUnionPush(remoteFolder: String) -> String {
        guard let localBase = appSupportBase(create: false) else {
            return ""
        }
        let remoteBase = (remoteFolder as NSString).appendingPathComponent(dataSubfolder)
        return unionPushResultSignature(sourceBase: localBase, destinationBase: remoteBase)
    }

    // The signature of the union-push result: for each allowlisted item, hash the source copy if the
    // source has it (the push made the destination equal to it), else the destination copy (a union
    // extra), else absent. Internal so tests can drive it with temp dirs and assert it equals the
    // destination's actual post-push contentSignature.
    static func unionPushResultSignature(sourceBase: String, destinationBase: String) -> String {
        let fileManager = FileManager.default
        return framedSignature { item in
            let sourcePath = (sourceBase as NSString).appendingPathComponent(item.name)
            return fileManager.fileExists(atPath: sourcePath) ? sourceBase : destinationBase
        }
    }

    // MARK: - Copying

    private static func appSupportBase(create: Bool) -> String? {
        if create {
            return FileManager.default.applicationSupportDirectory()
        }
        return FileManager.default.applicationSupportDirectoryWithoutCreating()
    }

    // A timestamped folder under <AppSupport>/<backupSubfolder> into which a copy operation stashes
    // any file it is about to overwrite or delete, so no destruction is ever irreversible. Returns
    // nil only when Application Support is unavailable, in which case there is nothing local to lose.
    // Pruning is done on a serial queue to prevent concurrent deletion while another operation reads.
    // Built once; DateFormatter construction is expensive and makeBackupFolder runs on the sync path.
    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Format in UTC, not local time: pruneBackups relies on a lexicographic sort being
        // chronological, but a local-time string is NOT monotonic across a DST fall-back (the hour
        // repeats), so a backup written after the transition could sort before one written before it and
        // be evicted as the "older" copy once >maxBackupFolders exist. UTC has no such repeated hour.
        formatter.timeZone = TimeZone(identifier: "UTC")
        // Millisecond precision (not just seconds): two syncs in the same wall-clock second would
        // otherwise share a timestamp prefix and be ordered by their random trailing UUID, so
        // pruneBackups (a lexicographic sort) could evict the chronologically newer of the pair.
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss.SSS"
        return formatter
    }()

    // Returns a timestamped path for this sync's backups. It does NOT create the folder or prune here:
    // makeBackupFolder is called on every push/pull, but most steady-state syncs back up nothing (all
    // items identical), so pruning happens lazily in backUp() the first time a backup is actually
    // written, keeping no-op syncs off the filesystem.
    private static func makeBackupFolder() -> String? {
        guard let appSupport = FileManager.default.applicationSupportDirectory() else {
            return nil
        }
        let root = (appSupport as NSString).appendingPathComponent(backupSubfolder)
        let stamp = "\(backupTimestampFormatter.string(from: Date())) \(UUID().uuidString)"
        return (root as NSString).appendingPathComponent(stamp)
    }

    // Creates (and returns) a fresh timestamped backup folder for a caller OUTSIDE the mirror path to
    // stash a recovery copy into (e.g. ToolNotes preserving typed-but-unsaved global-note text it is
    // about to drop), so a discard is recoverable from the same "Settings Sync Backups" root the sync
    // uses. Prunes old backups like backUp() does. Returns nil if Application Support is unavailable.
    @objc(makeRecoveryBackupFolder)
    static func makeRecoveryBackupFolder() -> String? {
        guard let folder = makeBackupFolder() else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        } catch {
            DLog("makeRecoveryBackupFolder: \(error)")
            return nil
        }
        let root = (folder as NSString).deletingLastPathComponent
        let keep = maxBackupFolders
        backupQueue.async {
            pruneBackups(root: root, keep: keep)
        }
        return folder
    }

    // Delete all but the most recent `keep` backup folders so the backup directory doesn't grow
    // without bound. Folder names are timestamp-prefixed, so a lexicographic sort is chronological.
    // Internal (with an explicit `keep`) so tests can drive it against a temp directory.
    static func pruneBackups(root: String, keep: Int) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root) else {
            return
        }
        // Keep only real backup folders (named "yyyy-MM-dd HH-mm-ss.SSS <UUID>"). Validate the
        // trailing UUID rather than using a length heuristic, so an unrelated entry (.DS_Store, a
        // future rename) isn't misclassified as a backup and pruned.
        let backupFolders = entries.filter { entry in
            guard let last = entry.components(separatedBy: " ").last else {
                return false
            }
            return UUID(uuidString: last) != nil
        }.sorted()

        guard backupFolders.count > keep else {
            return
        }

        let foldersToDelete = backupFolders.prefix(backupFolders.count - keep)
        for name in foldersToDelete {
            let path = (root as NSString).appendingPathComponent(name)
            do {
                try fileManager.removeItem(atPath: path)
                DLog("Pruned old backup: \(name)")
            } catch {
                DLog("Failed to prune backup \(name): \(error)")
            }
        }
    }

    // Preserve the destination before it is overwritten or deleted. Copies it into backupFolder so a
    // wrong conflict choice or a propagated deletion is always recoverable. Throws if the copy fails:
    // we must never destroy the only copy of a file, so a backup failure aborts the destructive step
    // and leaves the destination intact for the next sync to retry. A nil backupFolder (tests, or
    // Application Support unavailable) means "no backup requested" and is a no-op.
    private static func backUp(itemAt path: String, name: String, into backupFolder: String?) throws {
        guard let backupFolder else {
            return
        }
        let fileManager = FileManager.default
        // The timestamped backup folder is unique per sync, so its non-existence means this is the
        // first item backed up this sync. Prune then (not on every no-op sync via makeBackupFolder).
        let isFirstBackupThisSync = !fileManager.fileExists(atPath: backupFolder)
        try fileManager.createDirectory(atPath: backupFolder, withIntermediateDirectories: true)
        if isFirstBackupThisSync {
            let root = (backupFolder as NSString).deletingLastPathComponent
            let keep = maxBackupFolders
            // Prune asynchronously: pruneBackups only deletes OLD backup folders (never this sync's
            // freshly-created UUID folder), so the caller doesn't depend on its result, and backUp
            // runs on the main thread on the push/quit path. async still serializes prunes on
            // backupQueue (avoiding the concurrent-deletion race the queue exists for) while keeping
            // the potentially large rm off the hot path.
            backupQueue.async {
                pruneBackups(root: root, keep: keep)
            }
        }
        let backupPath = (backupFolder as NSString).appendingPathComponent(name)
        try? fileManager.removeItem(atPath: backupPath)
        try fileManager.copyItem(atPath: path, toPath: backupPath)
    }

    // Copy every allowlisted item from sourceBase to destinationBase. Items present in the source
    // overwrite the destination. When deleteMissing is true, an item absent from the source is also
    // removed from the destination so deletions propagate; when false, the destination's copy is
    // left alone (union). Any item the destination already has is first preserved into backupFolder
    // (if non-nil) before it is overwritten or deleted, so nothing is destroyed irreversibly.
    // Internal so tests can drive it with temporary directories instead of the real Application
    // Support folder.
    static func mirrorAll(fromBase sourceBase: String,
                          toBase destinationBase: String,
                          deleteMissing: Bool,
                          createDestination: Bool,
                          backupFolder: String? = nil,
                          changedItems: NSMutableSet? = nil) -> Bool {
        do {
            if createDestination {
                try FileManager.default.createDirectory(atPath: destinationBase,
                                                        withIntermediateDirectories: true)
            }
            // Sweep orphaned ".<uuid>.tmp" staging files left in the destination by a mirror() that was
            // interrupted (crash/kill/power-loss) between copyItem and the move/replace. Nothing else
            // ever removes them, so on a cloud-backed folder they would accumulate (and upload) forever.
            // Safe to do here: sync runs on the main thread, so no other pass is mid-flight, and this
            // pass hasn't created its own temp yet.
            sweepStaleTempFiles(inBase: destinationBase)
            for item in allowlist {
                if try mirror(item: item, fromBase: sourceBase, toBase: destinationBase,
                              deleteMissing: deleteMissing, backupFolder: backupFolder) {
                    changedItems?.add(item.name)
                }
            }
            return true
        } catch let syncError as SyncError {
            DLog("mirrorAll failed: \(syncError.localizedDescription)")
            return false
        } catch {
            DLog("mirrorAll failed with unexpected error: \(error)")
            return false
        }
    }

    // Remove orphaned staging files (the exact tempPrefix + <UUID> + tempSuffix form mirror() creates)
    // left directly in `base` by an interrupted copy. Internal so a test can drive it. Only removes
    // entries matching that distinctive iterm2sync namespace AND whose middle parses as a UUID (so a
    // foreign dotfile - a bare ".<uuid>.tmp" from another feature/tool at the shared App Support root, or
    // any non-UUID .tmp - is never touched) AND that are demonstrably OLD: on a shared cloud folder,
    // ANOTHER machine may be mid-copyItem with a very fresh temp, and deleting it would break that
    // machine's in-flight replaceItem. A live copy's temp is always seconds-fresh, so an age threshold
    // safely distinguishes a real orphan from an in-flight one.
    static func sweepStaleTempFiles(inBase base: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: base) else {
            return
        }
        // A very generous threshold. The mtime is stamped when the copy STARTS (and may be stamped by
        // ANOTHER machine's clock on a shared cloud folder), so it must tolerate both a slow in-flight
        // copy and cross-machine clock skew. Sweeping is just garbage collection of crash-orphaned
        // temps, so there's no cost to waiting a week; that is far beyond any plausible single-item copy
        // AND beyond any sane clock skew (a machine off by a week would already be failing TLS, etc.).
        // A future or too-recent mtime (age below the threshold, including negative) is left alone.
        let staleAgeThreshold: TimeInterval = 7 * 24 * 60 * 60
        let now = Date()
        for entry in entries {
            guard entry.hasPrefix(tempPrefix), entry.hasSuffix(tempSuffix) else {
                continue
            }
            let middle = String(entry.dropFirst(tempPrefix.count).dropLast(tempSuffix.count))
            guard UUID(uuidString: middle) != nil else {
                continue
            }
            let path = (base as NSString).appendingPathComponent(entry)
            guard let mtime = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date else {
                // Can't determine age; don't risk deleting a fresh temp another machine is writing.
                continue
            }
            if now.timeIntervalSince(mtime) < staleAgeThreshold {
                // Too fresh: likely a live copy (possibly on another machine) mid-flight.
                continue
            }
            do {
                try fileManager.removeItem(atPath: path)
                DLog("Swept stale sync temp: \(entry)")
            } catch {
                DLog("Failed to sweep stale sync temp \(entry): \(error)")
            }
        }
    }

    // Returns true if this item was actually changed on the destination (copied or deleted).
    private static func mirror(item: Item,
                               fromBase sourceBase: String,
                               toBase destinationBase: String,
                               deleteMissing: Bool,
                               backupFolder: String?) throws -> Bool {
        let fileManager = FileManager.default
        let source = (sourceBase as NSString).appendingPathComponent(item.name)
        let destination = (destinationBase as NSString).appendingPathComponent(item.name)
        let sourceExists = fileManager.fileExists(atPath: source)
        let destinationExists = fileManager.fileExists(atPath: destination)

        if !sourceExists {
            if deleteMissing && destinationExists {
                // Stash the file we are about to delete; only remove it once the backup succeeded.
                do {
                    try backUp(itemAt: destination, name: item.name, into: backupFolder)
                    try fileManager.removeItem(atPath: destination)
                } catch {
                    throw SyncError.backupFailed(itemName: item.name, underlying: error)
                }
                return true
            }
            return false
        }

        if destinationExists {
            // Compare by the SAME metadata-filtered notion the signature uses (not a raw
            // FileManager.contentsEqual, which would call a package differing only by a stray
            // .DS_Store "changed"). Use `try`, NOT `try?`: itemContentDigest throws UnreadableFile for
            // a present-but-unreadable file (an iCloud/Dropbox dataless placeholder). Swallowing that
            // to nil would treat the item as changed and back-up-then-overwrite it, faulting in the
            // placeholder on the main thread and churning a pointless backup. Letting the throw
            // propagate makes mirrorAll fail so the caller DEFERS this pass, matching the deferral
            // philosophy used everywhere an unreadable file is encountered.
            let sourceDigest = try itemContentDigest(name: item.name, base: sourceBase)
            let destinationDigest = try itemContentDigest(name: item.name, base: destinationBase)
            if sourceDigest == destinationDigest {
                // Already identical: skip the backup and the write. This avoids stashing a fresh copy
                // of an unchanged item every time some other allowlisted file changes (e.g. a
                // steady-state push that only touched snippets shouldn't back up notes) and prevents OS
                // cruft from flip-flopping a package between machines.
                return false
            }
        }

        // Copy source over destination atomically via a temp sibling. If the destination already
        // exists it is preserved first, so a backup failure aborts before anything is overwritten.
        let destinationParent = (destination as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: destinationParent, withIntermediateDirectories: true)
        
        if destinationExists {
            do {
                try backUp(itemAt: destination, name: item.name, into: backupFolder)
            } catch {
                throw SyncError.backupFailed(itemName: item.name, underlying: error)
            }
        }
        
        let temp = (destinationParent as NSString).appendingPathComponent(tempPrefix + UUID().uuidString + tempSuffix)
        
        // Ensure temp file is cleaned up even if we fail
        defer {
            // Only remove if it still exists (successful operations move/replace it)
            if fileManager.fileExists(atPath: temp) {
                try? fileManager.removeItem(atPath: temp)
            }
        }
        
        do {
            try fileManager.copyItem(atPath: source, toPath: temp)
            // copyItem inherits the SOURCE's modification date, so a source untouched for a week would
            // give the temp a week-old mtime. sweepStaleTempFiles judges "crash orphan vs live in-flight
            // copy" by mtime age, so stamp the temp to NOW; otherwise another machine's sweep could
            // delete this temp mid-copy and fail our replace/move. Best-effort (the age check only needs
            // it to be recent).
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: temp)
            if destinationExists {
                _ = try fileManager.replaceItem(at: URL(fileURLWithPath: destination),
                                                withItemAt: URL(fileURLWithPath: temp),
                                                backupItemName: nil,
                                                resultingItemURL: nil)
            } else {
                try fileManager.moveItem(atPath: temp, toPath: destination)
            }
        } catch {
            throw SyncError.copyFailed(itemName: item.name, underlying: error)
        }
        return true
    }

    // MARK: - Signature

    // Thrown when a file exists but cannot be read (e.g. an iCloud/Dropbox dataless placeholder).
    // Hashing its bytes as empty would make the signature depend on download state and fire spurious
    // conflicts, so we instead bail and let the caller defer the sync to a later pass.
    private struct UnreadableFile: LocalizedError {
        let path: String
        var errorDescription: String? {
            return "File exists but cannot be read (may be downloading): \(path)"
        }
    }

    // Thrown when an allowlisted item (or a file inside a package) is a symbolic link. The signature
    // follows the link and hashes its TARGET's bytes, but mirror() copies the link VERBATIM (copyItem
    // preserves symlinks), so after a copy the destination is a link whose digest never matches the
    // source's target digest: it re-copies on every pass, or throws on a dangling/host-specific target
    // and stalls. We can't sync it correctly, so refuse: defer the pass (no data loss, no wrong copy)
    // and log. Exotic (macOS writes plain files into RTFDs, config items are regular files), but reachable
    // if a user symlinks their notes store or an attachment.
    private struct SymlinkedItem: LocalizedError {
        let path: String
        var errorDescription: String? {
            return "Refusing to sync a symlinked item (cannot be mirrored consistently): \(path)"
        }
    }

    // Whether the item at path is itself a symbolic link (does NOT follow the link, unlike
    // fileExists/attributesOfItem). URLResourceValues.isSymbolicLink reports on the item itself.
    private static func isSymbolicLink(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink ?? false
    }

    // Hex SHA-256 over the allowlisted items, framing each from the base returned by `baseFor`, or "" if
    // a present file is unreadable (callers treat "" as "cannot compute now; don't sync this pass").
    // Shared by contentSignature and unionPushResultSignature so the framing order and the hash tail
    // (which the baseline == folder push invariant depends on) can never diverge between them.
    //
    // ACCEPTED LIMITATION (all-or-nothing deferral): a SINGLE unreadable item (a dataless iCloud/Dropbox
    // placeholder that never materializes) makes the whole signature "", which defers the ENTIRE sync
    // pass - snippets/colors/icons included, not just the stuck file. This is the deliberate
    // never-clobber-undownloaded-content philosophy applied whole-set rather than per-item: it delays
    // (does not lose) the other items until the placeholder materializes (e.g. the user opens Notes, or
    // the file downloads), and each launch retries. A per-item design (skip the stuck item, sync the
    // rest, with a distinct "unreadable" frame so it isn't read as a deletion) would decouple them but
    // is a larger change to this core invariant; deferred.
    private static func framedSignature(baseFor: (Item) -> String) -> String {
        var blob = Data()
        do {
            for item in signatureOrderedAllowlist {
                try append(to: &blob, item: item.name, base: baseFor(item))
            }
        } catch {
            DLog("framedSignature: \(error)")
            return ""
        }
        return ((blob as NSData).it_sha256() as NSData).it_hexEncoded()
    }

    // Hex SHA-256 over the allowlisted items under base. Internal so tests can verify it.
    static func contentSignature(base: String) -> String {
        return framedSignature { _ in base }
    }

    // What an allowlisted item contributes to a signature: absent, a single file, or a directory with
    // its OS-metadata-filtered contents in deterministic order. Shared by the content hash and the
    // cheap stat fingerprint so the two walks can never diverge.
    private enum ItemState {
        case absent
        case file(fullPath: String)
        case directory(files: [(label: String, fullPath: String)])
        // A present directory whose contents could not be listed: enumerator(atPath:) returned nil
        // (opendir failed with EACCES/EIO/EMFILE, or a mount hiccup, or a transient error in the window
        // between the fileExists check and the enumerator call). Kept DISTINCT from an empty .directory
        // so the signature DEFERS (throws UnreadableFile, like an unreadable file) instead of fabricating
        // a concrete empty-package signature that differs from the baseline and fires a spurious conflict
        // prompt or churns a push. See append(to:item:base:) and statSignature.
        case unreadableDirectory(fullPath: String)
        // The item, or a file inside a package, is a symbolic link. mirror() can't copy it consistently
        // with how the signature hashes it, so the pass defers. See SymlinkedItem.
        case symlinked(fullPath: String)
    }

    private static func itemState(name: String, base: String) -> ItemState {
        let fileManager = FileManager.default
        let path = (base as NSString).appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .absent
        }
        if isSymbolicLink(path) {
            // The top-level item is a symlink (fileExists/isDirectory followed it to its target). Refuse.
            return .symlinked(fullPath: path)
        }
        if !isDirectory.boolValue {
            return .file(fullPath: path)
        }
        // Use subpathsOfDirectory (throwing), NOT enumerator(atPath:): the enumerator can return nil OR
        // a non-nil enumerator that silently yields nothing on a permission/IO error, which would be
        // indistinguishable from a legitimately empty package. subpathsOfDirectory THROWS on an
        // unreadable directory but returns [] for a real empty one, so the two are cleanly separated.
        let subpaths: [String]
        do {
            subpaths = try fileManager.subpathsOfDirectory(atPath: path)
        } catch {
            // Present but unlistable (EACCES/EIO, a mount hiccup, or a transient error in the window
            // between the fileExists check and this read). Do NOT fall through to an empty .directory
            // (that would frame a concrete non-empty "empty package" signature); defer this pass like an
            // unreadable file.
            return .unreadableDirectory(fullPath: path)
        }
        var relativePaths: [String] = []
        for relative in subpaths {
            if isOSMetadata(relative) {
                continue
            }
            let full = (path as NSString).appendingPathComponent(relative)
            if isSymbolicLink(full) {
                // A symlinked file inside the package: the same mirror-vs-signature mismatch as a
                // top-level symlink, so refuse the whole package rather than hashing the link target's
                // bytes (which copyItem won't reproduce).
                return .symlinked(fullPath: full)
            }
            var subIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: full, isDirectory: &subIsDirectory),
               !subIsDirectory.boolValue {
                relativePaths.append(relative)
            }
            // Note: only regular files contribute. Empty subdirectories are intentionally NOT recorded,
            // so a package structural change consisting ONLY of an added/removed empty dir does not
            // register as a change and won't sync. This is a deliberate simplification (RTFD packages
            // don't meaningfully use empty dirs); the signature is faithful to file content, not to the
            // full directory structure.
        }
        // Frame and sort by the NFC-normalized relative path, but open the file by its RAW on-disk
        // name. Different filesystems/cloud services return the same logical filename in different
        // Unicode normalization forms (APFS preserves, Dropbox tends to NFC, some SMB/NFS return NFD),
        // so an attachment with a non-ASCII name would otherwise frame to a different byte sequence on
        // each machine and make contentSignature over byte-identical content differ forever (a spurious
        // perpetual "which copy?" conflict). Only the filename framing needs this; the content digest
        // is already byte-based.
        let files = relativePaths
            .map { (raw: $0, normalized: $0.precomposedStringWithCanonicalMapping) }
            .sorted { $0.normalized < $1.normalized }
            .map { (label: "\(name)/\($0.normalized)",
                    fullPath: (path as NSString).appendingPathComponent($0.raw)) }
        return .directory(files: files)
    }

    // OS-injected metadata that the user never authored. Including it would make a package's signature
    // diverge between machines without any user edit. Matches only the SPECIFIC known-cruft names
    // (rather than "any dot-prefixed component"), so a genuine user-authored leading-dot entry inside
    // an RTFD package (e.g. an attachment named ".env") stays part of the signature and the copy, and
    // isn't silently invisible to sync. Checks every path component, so cruft nested in a cruft dir is
    // still skipped.
    private static func isOSMetadata(_ relativePath: String) -> Bool {
        return relativePath.components(separatedBy: "/").contains { isCruftComponent($0) }
    }

    private static func isCruftComponent(_ component: String) -> Bool {
        // Documented edge in the "equal signature => equal synced content" invariant: a cruft-NAMED
        // user file (e.g. an attachment literally named "._x", or one inside a cruft dir) is copied
        // opaquely by the FIRST full-package copyItem but excluded from every later digest, so a content
        // change confined to it won't re-propagate (two different trees hash the same). Unreachable in
        // practice - RTFD attachment names aren't cruft-prefixed - and preserving normal single-dot user
        // files like ".env" is the more important behavior (see testSignatureDetectsUserDotFileInPackage).
        if component == ".DS_Store" { return true }
        if component.hasPrefix("._") { return true }              // AppleDouble sidecar
        if component.hasPrefix(".Spotlight-") { return true }     // .Spotlight-V100
        if component.hasPrefix(".DocumentRevisions") { return true }
        if component == ".fseventsd" { return true }
        if component == ".Trashes" { return true }
        if component == ".TemporaryItems" { return true }
        if component == ".apdisk" { return true }
        return false
    }

    // Appends `data` length-prefixed so the concatenation of frames is unambiguous (injective): no
    // file's bytes can be mistaken for a following frame header. Each file contributes its own
    // fixed-length SHA-256 digest rather than its raw bytes, so the running blob stays small even for
    // a large package. (fileDigest still reads each file fully to hash it, one at a time.)
    private static func appendFrame(_ data: Data, to blob: inout Data) {
        var length = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &length) { blob.append(contentsOf: $0) }
        blob.append(data)
    }

    private static func appendFrame(_ string: String, to blob: inout Data) {
        appendFrame(Data(string.utf8), to: &blob)
    }

    private static func fileDigest(_ path: String) throws -> Data {
        // Memory-map (mappedIfSafe) rather than slurp the whole file into RAM: notes.rtfd can embed a
        // large pasted attachment, and localContentSignature runs on the main thread on every autosave
        // (stat-cache miss). Mapping lets the OS page the bytes in for hashing and evict them, bounding
        // peak memory instead of loading a multi-MB (or larger) attachment all at once. Semantics are
        // preserved: a present-but-unreadable file (dataless placeholder) still yields nil -> throw ->
        // defer, and the hash over the same bytes is identical to the slurped version.
        guard let data = try? NSData(contentsOfFile: path, options: .mappedIfSafe) else {
            throw UnreadableFile(path: path)
        }
        return data.it_sha256()
    }

    private static func append(to blob: inout Data, item name: String, base: String) throws {
        switch itemState(name: name, base: base) {
        case .absent:
            appendFrame("ABSENT:\(name)", to: &blob)
        case .file(let fullPath):
            appendFrame(name, to: &blob)
            appendFrame(try fileDigest(fullPath), to: &blob)
        case .directory(let files):
            // The DIR frame distinguishes a present-but-empty package (an empty notes.rtfd) from an
            // absent one.
            appendFrame("DIR:\(name)", to: &blob)
            for file in files {
                appendFrame(file.label, to: &blob)
                appendFrame(try fileDigest(file.fullPath), to: &blob)
            }
        case .unreadableDirectory(let fullPath):
            // Present but unlistable: bail exactly as fileDigest does for an unreadable file, so
            // framedSignature returns "" and the caller defers rather than acting on a fabricated
            // empty-package signature.
            throw UnreadableFile(path: fullPath)
        case .symlinked(let fullPath):
            // A symlinked item can't be mirrored consistently with how it's hashed; defer the pass.
            throw SymlinkedItem(path: fullPath)
        }
    }

    // Digest of a single item's signature-relevant (OS-metadata-filtered) content. Used by mirror()
    // to decide whether an item actually changed, matching how contentSignature judges equality.
    // Throws (via fileDigest) if a contained file is present but unreadable.
    static func itemContentDigest(name: String, base: String) throws -> Data {
        var blob = Data()
        try append(to: &blob, item: name, base: base)
        return (blob as NSData).it_sha256()
    }

    // MARK: - Stat fingerprint (cheap change detection)

    // A cheap fingerprint of the allowlisted items from stat metadata (path + size + mtime + ctime +
    // inode), with no byte reads. Used to short-circuit localContentSignature so a repeated call (e.g.
    // on every debounced autosave) doesn't re-read and re-hash unchanged files. Returns nil if ANY
    // present item's stat() failed: a failed stat carries no content identity, so caching or matching
    // on it could alias two different contents. nil forces a cache miss (never stored, never a hit).
    private static func statSignature(base: String) -> String? {
        var parts: [String] = []
        for item in signatureOrderedAllowlist {
            switch itemState(name: item.name, base: base) {
            case .absent:
                parts.append("ABSENT:\(item.name)")
            case .file(let fullPath):
                guard let token = statToken(fullPath) else {
                    return nil
                }
                parts.append("\(item.name):\(token)")
            case .directory(let files):
                parts.append("DIR:\(item.name)")
                for file in files {
                    guard let token = statToken(file.fullPath) else {
                        return nil
                    }
                    parts.append("\(file.label):\(token)")
                }
            case .unreadableDirectory:
                // No stable identity for an unlistable directory: force a cache miss (never stored,
                // never a hit), matching the failed-stat handling for files.
                return nil
            case .symlinked:
                // A symlinked item is refused (the pass will defer); force a cache miss so a stat token
                // isn't cached for it.
                return nil
            }
        }
        return parts.joined(separator: "\u{0}")
    }

    // Exposed for ToolNotes' overwrite-backup guard (and its test): the same cheap stat fingerprint this
    // layer uses for change detection, so the two can't drift. Returns nil if the file is absent/unstat-able.
    @objc(statTokenForFileAtPath:)
    static func statTokenForFile(atPath path: String) -> String? {
        return statToken(path)
    }

    private static func statToken(_ path: String) -> String? {
        var st = stat()
        guard stat(path, &st) == 0 else {
            return nil
        }
        // Include nanosecond mtime, ctime, and inode, not just size+second-mtime: a same-size content
        // rewrite that preserves mtime (rsync --times, a cloud agent restoring mtime, a same-tick edit
        // on a coarse-granularity FS) would otherwise produce an identical token and return a stale
        // cached signature, silently suppressing that session's push. ctime updates on any write even
        // when mtime is forced back (it can't be set arbitrarily), and inode changes on a replace.
        let mtime = "\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec)"
        let ctime = "\(st.st_ctimespec.tv_sec).\(st.st_ctimespec.tv_nsec)"
        // Include st_dev: inode numbers are only unique per DEVICE, so without it two files with the
        // same inode on different volumes would produce the same token.
        return "\(st.st_dev)/\(st.st_size)/\(mtime)/\(ctime)/\(st.st_ino)"
    }

    // Thread-safe cache for the local signature, guarded by a Mutex (heap-allocated os_unfair_lock;
    // see cachedContentSignature for why a value-type static var would be unsafe). Scoped to the base
    // it was computed for so a different base can't get a hit on a coinciding stat string.
    private static var localSignatureCacheBase = ""
    private static var localSignatureCacheStat = ""
    private static var localSignatureCacheContent = ""
    private static let localSignatureCacheMutex = Mutex()
    
    // Serial queue to coordinate backup operations and prevent concurrent pruning
    private static let backupQueue = DispatchQueue(label: "com.iterm2.RemoteDataFileSync.backup")
}
