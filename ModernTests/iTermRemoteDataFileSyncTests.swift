//
//  iTermRemoteDataFileSyncTests.swift
//  iTerm2
//
//  Exercises iTermRemoteDataFileSync's internal mirror/signature seams against temporary
//  directories so we never touch the real Application Support folder.
//

import XCTest
@testable import iTerm2SharedARC

class iTermRemoteDataFileSyncTests: XCTestCase {
    private var roots: [String] = []

    override func tearDown() {
        // The signature cache is process-global; clear it so state doesn't leak between tests.
        iTermRemoteDataFileSync.resetSignatureCacheForTesting()
        for root in roots {
            try? FileManager.default.removeItem(atPath: root)
        }
        roots = []
        super.tearDown()
    }

    private func makeTempDir() -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("RemoteDataFileSyncTests-" + UUID().uuidString)
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        roots.append(path)
        return path
    }

    // The exact staging-temp framing mirror() creates and sweepStaleTempFiles matches: the distinctive
    // ".iterm2sync." namespace + a UUID + ".tmp". Kept in sync with iTermRemoteDataFileSync.tempPrefix /
    // tempSuffix (private there); if those change, update this.
    private func syncTemp() -> String {
        return ".iterm2sync." + UUID().uuidString + ".tmp"
    }

    private func write(_ contents: String, to base: String, name: String) {
        let path = (base as NSString).appendingPathComponent(name)
        try! contents.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    }

    private func writeDirectoryFixture(to base: String, name: String, innerContents: String) {
        let dir = (base as NSString).appendingPathComponent(name)
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        write(innerContents, to: dir, name: "TXT.rtf")
    }

    private func read(_ base: String, name: String) -> String? {
        let path = (base as NSString).appendingPathComponent(name)
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // Populate a base directory with one fixture per allowlisted name. notes.rtfd is a package
    // (directory), the rest are plain files.
    private func populateAllFixtures(in base: String, marker: String) {
        for name in iTermRemoteDataFileSync.allowlistNames {
            if (name as NSString).pathExtension == "rtfd" {
                writeDirectoryFixture(to: base, name: name, innerContents: "\(marker) \(name)")
            } else {
                write("\(marker) \(name)", to: base, name: name)
            }
        }
    }

    // A present but UNLISTABLE notes.rtfd (subpathsOfDirectory throws: a permission/IO error, a mount
    // hiccup, or a transient error) must DEFER the whole pass (signature "") exactly like an unreadable
    // file, NOT fabricate a concrete empty-package signature that differs from baseline and would fire a
    // spurious "which copy?" conflict or churn a push.
    func testUnlistableDirectoryDefersSignatureInsteadOfFabricatingEmptyPackage() {
        let base = makeTempDir()
        writeDirectoryFixture(to: base, name: "notes.rtfd", innerContents: "real note")
        // While readable, the package contributes a concrete, non-deferred signature.
        XCTAssertFalse(iTermRemoteDataFileSync.contentSignature(base: base).isEmpty)

        let packagePath = (base as NSString).appendingPathComponent("notes.rtfd")
        // Remove read/execute so opendir (and thus the directory listing) fails for the owner.
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: packagePath)
        defer {
            // Restore so tearDown can delete the tree.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: packagePath)
        }

        // Present (fileExists still succeeds via the parent) but unlistable => the whole signature defers.
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: base), "")
    }

    // A legitimately EMPTY but readable package must NOT be treated as unreadable: it contributes a
    // concrete (present-but-empty) signature distinct from the all-absent one. Guards against the fix
    // for the unlistable case over-reaching and deferring on every empty directory.
    func testEmptyButReadableDirectoryIsNotDeferred() {
        let base = makeTempDir()
        let packagePath = (base as NSString).appendingPathComponent("notes.rtfd")
        try! FileManager.default.createDirectory(atPath: packagePath, withIntermediateDirectories: true)
        let signature = iTermRemoteDataFileSync.contentSignature(base: base)
        XCTAssertFalse(signature.isEmpty)
        XCTAssertNotEqual(signature, iTermRemoteDataFileSync.allAbsentSignature())
    }

    // A symlinked allowlisted item can't be mirrored consistently: the signature follows the link and
    // hashes the TARGET's bytes, but mirror() copies the link verbatim, so the copy never matches - it
    // re-copies forever or stalls on a dangling link. So the whole pass must defer (signature "").
    func testSymlinkedTopLevelItemDefersSignature() {
        let base = makeTempDir()
        let target = makeTempDir()
        // Point at a REAL file so the link is not dangling: pre-fix, following it would have produced a
        // concrete (non-deferred) signature, so this pins the behavior change.
        write("real snippets", to: target, name: "snippets-target")
        let linkPath = (base as NSString).appendingPathComponent("snippets.plist")
        try! FileManager.default.createSymbolicLink(
            atPath: linkPath,
            withDestinationPath: (target as NSString).appendingPathComponent("snippets-target"))
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: base), "")
    }

    // A symlinked file INSIDE a package triggers the same mirror-vs-signature mismatch, so it defers too.
    func testSymlinkedFileInsidePackageDefersSignature() {
        let base = makeTempDir()
        let target = makeTempDir()
        write("attachment bytes", to: target, name: "att")
        let packagePath = (base as NSString).appendingPathComponent("notes.rtfd")
        try! FileManager.default.createDirectory(atPath: packagePath, withIntermediateDirectories: true)
        write("real", to: packagePath, name: "TXT.rtf")
        try! FileManager.default.createSymbolicLink(
            atPath: (packagePath as NSString).appendingPathComponent("attachment"),
            withDestinationPath: (target as NSString).appendingPathComponent("att"))
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: base), "")
    }

    // mirrorAll reports ONLY the items it actually changed, so the pull can refresh just those owners
    // (telling the notes view to reload on a snippets-only import would drop a large unsaved note).
    func testMirrorAllReportsOnlyChangedItems() {
        let source = makeTempDir()
        let destination = makeTempDir()
        // Identical notes.rtfd and graphic_colors.json on both sides; only snippets.plist differs.
        writeDirectoryFixture(to: source, name: "notes.rtfd", innerContents: "notes")
        writeDirectoryFixture(to: destination, name: "notes.rtfd", innerContents: "notes")
        write("same", to: source, name: "graphic_colors.json")
        write("same", to: destination, name: "graphic_colors.json")
        write("v2", to: source, name: "snippets.plist")
        write("v1", to: destination, name: "snippets.plist")

        let changed = NSMutableSet()
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: false, createDestination: true,
                                                        backupFolder: nil, changedItems: changed))

        XCTAssertEqual(changed, NSMutableSet(array: ["snippets.plist"]))
        XCTAssertFalse(changed.contains("notes.rtfd"))
        XCTAssertFalse(changed.contains("graphic_colors.json"))
    }

    // mirrorAll reports a deleted item (deleteMissing pull propagating a deletion) as changed too.
    func testMirrorAllReportsDeletedItemAsChanged() {
        let source = makeTempDir()
        let destination = makeTempDir()
        write("stale", to: destination, name: "snippets.plist")   // absent in source

        let changed = NSMutableSet()
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: true, createDestination: true,
                                                        backupFolder: nil, changedItems: changed))

        XCTAssertTrue(changed.contains("snippets.plist"))
    }

    // mirrorAll sweeps OLD orphaned ".<uuid>.tmp" staging files (left in the destination by a copy that
    // was interrupted between staging and the move) so they don't accumulate and upload forever, but
    // leaves a FRESH ".<uuid>.tmp" alone (it may be another machine mid-flight on a shared cloud folder).
    // Unrelated dotfiles and non-UUID .tmp files must also survive.
    func testMirrorAllSweepsOldOrphanTempButLeavesFreshAndDecoys() {
        let source = makeTempDir()
        let destination = makeTempDir()
        write("v1", to: source, name: "snippets.plist")

        let oldOrphan = syncTemp()                             // the exact form mirror() creates
        write("garbage", to: destination, name: oldOrphan)
        // Backdate its mtime well past the sweep's staleness threshold (7 days).
        let oldOrphanPath = (destination as NSString).appendingPathComponent(oldOrphan)
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 24 * 3600)],
                                               ofItemAtPath: oldOrphanPath)

        let freshTemp = syncTemp()                             // just created -> another machine mid-flight
        write("in-flight", to: destination, name: freshTemp)
        write("keep", to: destination, name: ".not-a-uuid.tmp")   // .tmp but middle isn't a UUID
        write("keep", to: destination, name: ".DS_Store")         // not a .tmp
        // A FOREIGN bare ".<uuid>.tmp" (another feature/tool at the shared App Support root) is old and
        // UUID-named, so the pre-namespace sweep would have deleted it; it must now survive.
        let foreignTemp = "." + UUID().uuidString + ".tmp"
        write("keep", to: destination, name: foreignTemp)
        let foreignTempPath = (destination as NSString).appendingPathComponent(foreignTemp)
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 24 * 3600)],
                                               ofItemAtPath: foreignTempPath)

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: false, createDestination: true))

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldOrphanPath), "old orphan should be swept")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: (destination as NSString).appendingPathComponent(freshTemp)), "fresh temp must survive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignTempPath),
                      "a foreign bare .<uuid>.tmp (not the iterm2sync namespace) must never be swept")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: (destination as NSString).appendingPathComponent(".not-a-uuid.tmp")))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: (destination as NSString).appendingPathComponent(".DS_Store")))
        XCTAssertEqual(read(destination, name: "snippets.plist"), "v1")
    }

    // Regression for the copyItem-inherits-source-mtime sweep bug: FileManager.copyItem copies the
    // source's modification date, so a temp staged from a file untouched for >7 days would inherit an
    // old mtime and be swept as a crash orphan mid-flight. mirror() restamps the temp to now to prevent
    // that. This pins both halves: an unstamped copy IS swept (why the restamp exists), a restamped one
    // survives even when its source is old.
    func testSweepDeletesUnstampedCopyTempButKeepsRestampedOne() {
        let source = makeTempDir()
        let destination = makeTempDir()
        write("payload", to: source, name: "snippets.plist")
        let sourceFile = (source as NSString).appendingPathComponent("snippets.plist")
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 24 * 3600)],
                                               ofItemAtPath: sourceFile)

        // copyItem inherits the source's OLD mtime; without a restamp the sweep treats it as an orphan.
        let unstamped = (destination as NSString).appendingPathComponent(syncTemp())
        try! FileManager.default.copyItem(atPath: sourceFile, toPath: unstamped)

        // The fix: restamp the copied temp to now, mirroring mirror(); an in-flight copy survives.
        let restamped = (destination as NSString).appendingPathComponent(syncTemp())
        try! FileManager.default.copyItem(atPath: sourceFile, toPath: restamped)
        try! FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: restamped)

        iTermRemoteDataFileSync.sweepStaleTempFiles(inBase: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: unstamped),
                       "a copyItem'd temp that inherited an old source mtime is swept (why mirror restamps)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restamped),
                      "a restamped in-flight temp survives even when copied from an old source")
    }

    // Pins the allowlist so that adding a synced file fails CI until -applyImportedRemoteDataFiles
    // (in iTermRemotePreferences) is updated with a reloader for it. Without that reload the new
    // file's in-memory owner would serve stale content and overwrite the freshly-imported file on the
    // next autosave. When you intentionally add/remove an allowlist entry, update both this set and
    // -applyImportedRemoteDataFiles.
    //
    // This test serves as a safety check: if you're adding a new synced file type, you MUST also
    // update iTermRemotePreferences to reload that file's in-memory state after sync, or data loss
    // will occur.
    func testAllowlistOwnersAreCovered() {
        XCTAssertEqual(Set(iTermRemoteDataFileSync.allowlistNames),
                       Set(["snippets.plist", "notes.rtfd", "graphic_colors.json", "graphic_icons.json"]))
    }

    // The @objc name constants that the ObjC owner-reload mapping (applyImportedRemoteDataFilesForItems)
    // keys off must each be a real allowlist entry, or a per-item reload would silently never fire.
    // Pins both membership and the literal values, so a rename/typo of a constant fails here.
    func testAllowlistNameConstantsMatchAllowlist() {
        let names = Set(iTermRemoteDataFileSync.allowlistNames)
        XCTAssertTrue(names.contains(iTermRemoteDataFileSync.snippetsPlistName))
        XCTAssertTrue(names.contains(iTermRemoteDataFileSync.notesPackageName))
        XCTAssertTrue(names.contains(iTermRemoteDataFileSync.graphicColorsName))
        XCTAssertTrue(names.contains(iTermRemoteDataFileSync.graphicIconsName))

        XCTAssertEqual(iTermRemoteDataFileSync.snippetsPlistName, "snippets.plist")
        XCTAssertEqual(iTermRemoteDataFileSync.notesPackageName, "notes.rtfd")
        XCTAssertEqual(iTermRemoteDataFileSync.graphicColorsName, "graphic_colors.json")
        XCTAssertEqual(iTermRemoteDataFileSync.graphicIconsName, "graphic_icons.json")
    }

    // An item whose destination already matches is neither backed up nor rewritten, so a push that
    // touched only one file doesn't churn fresh backups of the unchanged ones.
    func testIdenticalItemIsNotBackedUp() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        write("same", to: source, name: "snippets.plist")
        write("same", to: destination, name: "snippets.plist")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: false, createDestination: true,
                                                        backupFolder: backup))

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: (backup as NSString).appendingPathComponent("snippets.plist")))
        XCTAssertEqual(read(destination, name: "snippets.plist"), "same")
    }

    // A package that differs only by OS metadata (a Finder .DS_Store) must be treated as UNCHANGED,
    // matching the metadata-filtered content signature: no backup, no overwrite, and the destination's
    // .DS_Store survives. (The old FileManager.contentsEqual check would have called it "changed",
    // churning a backup and flipping the .DS_Store between machines.)
    func testMirrorSkipsPackageDifferingOnlyByOSMetadata() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        writeDirectoryFixture(to: source, name: "notes.rtfd", innerContents: "my notes")
        writeDirectoryFixture(to: destination, name: "notes.rtfd", innerContents: "my notes")
        let destinationNotes = (destination as NSString).appendingPathComponent("notes.rtfd")
        write("finder cruft", to: destinationNotes, name: ".DS_Store")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: false, createDestination: true,
                                                        backupFolder: backup))

        // Treated as unchanged: nothing backed up, and the destination's OS cruft is left in place.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: (backup as NSString).appendingPathComponent("notes.rtfd")))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: (destinationNotes as NSString).appendingPathComponent(".DS_Store")))
        XCTAssertEqual(read(destinationNotes, name: "TXT.rtf"), "my notes")
    }

    // A changed item is backed up before being overwritten, so the overwrite stays recoverable.
    func testChangedItemIsBackedUpBeforeOverwrite() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        write("new", to: source, name: "snippets.plist")
        write("old", to: destination, name: "snippets.plist")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: false, createDestination: true,
                                                        backupFolder: backup))

        XCTAssertEqual(read(destination, name: "snippets.plist"), "new")
        XCTAssertEqual(read(backup, name: "snippets.plist"), "old")
    }

    // Pins the quit "Lose Changes" / discard contract: replacing the local copy with the folder's
    // (mirror pull, deleteMissing: true) reverts an edited shared item to the folder's bytes AND
    // discards a brand-new local-only item (which a union would instead publish to the folder),
    // while backing the discarded item up so it stays recoverable.
    func testTakeFolderDiscardsLocalEditsAndLocalOnlyItems() {
        let folder = makeTempDir()
        let local = makeTempDir()
        let backup = makeTempDir()
        write("folder version", to: folder, name: "snippets.plist")     // shared item, folder's bytes
        write("my edit", to: local, name: "snippets.plist")             // shared item, locally edited
        write("brand new", to: local, name: "graphic_colors.json")      // local-only (folder lacks it)

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: folder, toBase: local,
                                                        deleteMissing: true, createDestination: false,
                                                        backupFolder: backup))

        // Edited shared item reverts to the folder's bytes.
        XCTAssertEqual(read(local, name: "snippets.plist"), "folder version")
        // Brand-new local-only item is discarded locally...
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: (local as NSString).appendingPathComponent("graphic_colors.json")))
        // ...but recoverable from the backup.
        XCTAssertEqual(read(backup, name: "graphic_colors.json"), "brand new")
    }

    // MARK: - Round trip

    func testRoundTrip() {
        let local = makeTempDir()
        let remote = makeTempDir()
        let local2 = makeTempDir()
        populateAllFixtures(in: local, marker: "original")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: local,
                                                        toBase: remote,
                                                        deleteMissing: true,
                                                        createDestination: true))
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: remote,
                                                        toBase: local2,
                                                        deleteMissing: true,
                                                        createDestination: true))

        for name in iTermRemoteDataFileSync.allowlistNames {
            if (name as NSString).pathExtension == "rtfd" {
                let dir = (local2 as NSString).appendingPathComponent(name)
                XCTAssertEqual(read(dir, name: "TXT.rtf"), "original \(name)")
            } else {
                XCTAssertEqual(read(local2, name: name), "original \(name)")
            }
        }
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: local),
                       iTermRemoteDataFileSync.contentSignature(base: local2))
    }

    // MARK: - Deletion semantics

    // deleteMissing: true is the baseline-driven delete-propagation path (steady-state "only the
    // folder moved", where the local copy provably matched the folder's last-synced set).
    func testMirrorDeletePropagatesRemovesStaleDestinationFile() {
        let source = makeTempDir()
        let destination = makeTempDir()
        // Destination has a file the source lacks.
        write("stale", to: destination, name: "graphic_colors.json")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source,
                                                        toBase: destination,
                                                        deleteMissing: true,
                                                        createDestination: true))

        let path = (destination as NSString).appendingPathComponent("graphic_colors.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // deleteMissing: false is the union pull used by first adoption / "Keep Remote" / "Use Settings
    // Folder's". An item the folder never had must NOT be deleted from the local copy. This is the
    // regression test for the data-loss bug where "keep the folder's snippets" wiped local notes.
    func testUnionPullDoesNotDeleteLocalOnlyItemsAbsentFromFolder() {
        let local = makeTempDir()
        let folder = makeTempDir()
        // Local has the full set; the folder only has snippets.
        populateAllFixtures(in: local, marker: "local")
        write("folder snippets", to: folder, name: "snippets.plist")

        // Pull the way first-adoption / "Keep Remote" does: union, no deletion.
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: folder,
                                                        toBase: local,
                                                        deleteMissing: false,
                                                        createDestination: false))

        // snippets.plist is taken from the folder...
        XCTAssertEqual(read(local, name: "snippets.plist"), "folder snippets")
        // ...but the local-only items the folder never had are preserved intact.
        XCTAssertEqual(read(local, name: "graphic_colors.json"), "local graphic_colors.json")
        XCTAssertEqual(read(local, name: "graphic_icons.json"), "local graphic_icons.json")
        let notesDir = (local as NSString).appendingPathComponent("notes.rtfd")
        XCTAssertEqual(read(notesDir, name: "TXT.rtf"), "local notes.rtfd")
    }

    // Regression for the disjoint first-sync data loss: machine has only notes, folder has only
    // snippets. The "Use This Mac's" push must union (deleteMissing: false), not mirror, so the
    // folder's snippets survive.
    func testFirstSyncDisjointSetsDoNotLoseRemoteOnlyItems() {
        let local = makeTempDir()
        let folderData = makeTempDir()
        writeDirectoryFixture(to: local, name: "notes.rtfd", innerContents: "my notes")
        write("folder snippets", to: folderData, name: "snippets.plist")

        // "Use This Mac's" pushes local -> folder as a union.
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: local,
                                                        toBase: folderData,
                                                        deleteMissing: false,
                                                        createDestination: true))

        // The folder keeps its snippets AND gains this Mac's notes.
        XCTAssertEqual(read(folderData, name: "snippets.plist"), "folder snippets")
        let notesDir = (folderData as NSString).appendingPathComponent("notes.rtfd")
        XCTAssertEqual(read(notesDir, name: "TXT.rtf"), "my notes")
    }

    // Regression for same-session data loss: after a "Use This Mac's" union push, a later local edit
    // must not delete the folder's disjoint items. The steady-state push is a union (deleteMissing:
    // false), which is what copyLocalToRemote now always does, so the folder's notes.rtfd survives.
    func testSteadyStateUnionPushPreservesFolderDisjointItems() {
        let local = makeTempDir()    // this Mac: snippets only
        let folder = makeTempDir()   // folder: notes.rtfd only
        write("mine", to: local, name: "snippets.plist")
        writeDirectoryFixture(to: folder, name: "notes.rtfd", innerContents: "their notes")

        // "Use This Mac's": union push.
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: local, toBase: folder,
                                                        deleteMissing: false, createDestination: true))
        // Same-session local edit, then the steady-state push (also a union now).
        write("mine v2", to: local, name: "snippets.plist")
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: local, toBase: folder,
                                                        deleteMissing: false, createDestination: true))

        // The folder's disjoint notes.rtfd survives, and its snippets are updated.
        let notesDir = (folder as NSString).appendingPathComponent("notes.rtfd")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir),
                      "folder's disjoint notes.rtfd must survive a steady-state push")
        XCTAssertEqual(read(folder, name: "snippets.plist"), "mine v2")
    }

    func testSignatureIgnoresOSMetadataInsidePackage() {
        let withCruft = makeTempDir()
        let clean = makeTempDir()
        writeDirectoryFixture(to: withCruft, name: "notes.rtfd", innerContents: "notes")
        writeDirectoryFixture(to: clean, name: "notes.rtfd", innerContents: "notes")
        // Drop a .DS_Store into one package; it must not change the signature.
        let cruftDir = (withCruft as NSString).appendingPathComponent("notes.rtfd")
        write("finder cruft", to: cruftDir, name: ".DS_Store")
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: withCruft),
                       iTermRemoteDataFileSync.contentSignature(base: clean))
    }

    // A non-dot file inside a known-cruft directory (e.g. .Spotlight-V100/store.db) must be ignored,
    // not just cruft at the package root.
    func testSignatureIgnoresFilesInsideCruftDirectory() {
        let withCruft = makeTempDir()
        let clean = makeTempDir()
        writeDirectoryFixture(to: withCruft, name: "notes.rtfd", innerContents: "notes")
        writeDirectoryFixture(to: clean, name: "notes.rtfd", innerContents: "notes")
        let cruftDir = ((withCruft as NSString).appendingPathComponent("notes.rtfd") as NSString)
            .appendingPathComponent(".Spotlight-V100")
        try! FileManager.default.createDirectory(atPath: cruftDir, withIntermediateDirectories: true)
        write("spotlight cruft", to: cruftDir, name: "store.db")
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: withCruft),
                       iTermRemoteDataFileSync.contentSignature(base: clean))
    }

    // A user-authored leading-dot entry inside an RTFD package (e.g. an attachment named ".env") is
    // NOT OS cruft, so it must affect the signature: otherwise a package differing only by it would
    // read as identical and the entry would silently never propagate. Regression for the narrowed
    // isOSMetadata (specific cruft names, not "any dot-prefixed component").
    func testSignatureDetectsUserDotFileInPackage() {
        let withDotFile = makeTempDir()
        let without = makeTempDir()
        writeDirectoryFixture(to: withDotFile, name: "notes.rtfd", innerContents: "notes")
        writeDirectoryFixture(to: without, name: "notes.rtfd", innerContents: "notes")
        let pkg = (withDotFile as NSString).appendingPathComponent("notes.rtfd")
        write("SECRET=1", to: pkg, name: ".env")
        XCTAssertNotEqual(iTermRemoteDataFileSync.contentSignature(base: withDotFile),
                          iTermRemoteDataFileSync.contentSignature(base: without))
    }

    // MARK: - Backups (never destroy a file without preserving it)

    // Overwriting an existing destination file must first stash the loser into the backup folder, so
    // a "wrong copy" conflict choice is recoverable.
    func testOverwriteBacksUpLoser() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        write("new", to: source, name: "snippets.plist")
        write("old", to: destination, name: "snippets.plist")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source,
                                                        toBase: destination,
                                                        deleteMissing: false,
                                                        createDestination: true,
                                                        backupFolder: backup))

        XCTAssertEqual(read(destination, name: "snippets.plist"), "new")
        XCTAssertEqual(read(backup, name: "snippets.plist"), "old")
    }

    // A propagated deletion must stash the file it removes, so a deletion synced from another machine
    // is recoverable.
    func testDeletePropagationBacksUpLoser() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        write("stale", to: destination, name: "graphic_colors.json")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source,
                                                        toBase: destination,
                                                        deleteMissing: true,
                                                        createDestination: true,
                                                        backupFolder: backup))

        let path = (destination as NSString).appendingPathComponent("graphic_colors.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(read(backup, name: "graphic_colors.json"), "stale")
    }

    // Package (directory) losers are backed up as whole subtrees, not just their top-level entry.
    func testPackageOverwriteBacksUpLoser() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        writeDirectoryFixture(to: source, name: "notes.rtfd", innerContents: "new notes")
        writeDirectoryFixture(to: destination, name: "notes.rtfd", innerContents: "old notes")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source,
                                                        toBase: destination,
                                                        deleteMissing: false,
                                                        createDestination: true,
                                                        backupFolder: backup))

        let destNotes = (destination as NSString).appendingPathComponent("notes.rtfd")
        XCTAssertEqual(read(destNotes, name: "TXT.rtf"), "new notes")
        let backupNotes = (backup as NSString).appendingPathComponent("notes.rtfd")
        XCTAssertEqual(read(backupNotes, name: "TXT.rtf"), "old notes")
    }

    // Writing a brand-new destination file (nothing to lose) creates no backup.
    func testNewFileDoesNotCreateBackup() {
        let source = makeTempDir()
        let destination = makeTempDir()
        let backup = makeTempDir()
        write("fresh", to: source, name: "snippets.plist")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source,
                                                        toBase: destination,
                                                        deleteMissing: false,
                                                        createDestination: true,
                                                        backupFolder: backup))

        XCTAssertEqual(read(destination, name: "snippets.plist"), "fresh")
        XCTAssertNil(read(backup, name: "snippets.plist"))
    }

    // MARK: - Push baseline invariant

    // Regression for the "stalled push" bug: writeDataFilesToRemoteFolder guards each steady-state
    // push with expectedRemoteSignature == baseline, then adopts a new baseline after a successful
    // push. The union push never deletes the folder's items, so when the folder holds an item local
    // lacks (e.g. the user deleted a file locally, which does not propagate), the post-push folder is
    // local UNION that item and its signature does NOT equal local's signature. Adopting local's
    // signature as the baseline would make the very next push's guard (folder != baseline) abort
    // forever. The fix adopts the folder's ACTUAL post-push signature, which by construction equals
    // the folder's current content, so the guard passes. This pins that invariant.
    func testUnionPushLeavesFolderSignatureDifferentFromLocalWhenFolderHasExtraItem() {
        let local = makeTempDir()
        let folderData = makeTempDir()
        // Local has only snippets; the folder additionally holds a graphic_colors.json local lacks.
        write("local snippets", to: local, name: "snippets.plist")
        write("stale snippets", to: folderData, name: "snippets.plist")
        write("folder only", to: folderData, name: "graphic_colors.json")

        // Union push (what copyLocalToRemote does): folder keeps its extra item.
        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: local, toBase: folderData,
                                                        deleteMissing: false, createDestination: true))

        let localSignature = iTermRemoteDataFileSync.contentSignature(base: local)
        let folderSignature = iTermRemoteDataFileSync.contentSignature(base: folderData)

        // The folder still holds graphic_colors.json, so its signature diverges from local's:
        // adopting local's signature as the baseline would stall every future push.
        XCTAssertNotEqual(folderSignature, localSignature)

        // The baseline the push path actually records is unionPushResultSignature (composed from the
        // LOCAL copy for pushed items plus the folder for extras, WITHOUT re-reading the whole folder).
        // Pin that it equals the folder's independently-computed post-push signature, so the next
        // push's divergence guard (folder == baseline) passes. This is the assertion that fails if the
        // fix is reverted to adopting localSignature; computing the two sides differently makes it
        // non-vacuous.
        let composedBaseline = iTermRemoteDataFileSync.unionPushResultSignature(sourceBase: local,
                                                                                destinationBase: folderData)
        XCTAssertEqual(composedBaseline, folderSignature)
        XCTAssertNotEqual(composedBaseline, localSignature)
        XCTAssertEqual(read(folderData, name: "graphic_colors.json"), "folder only")
        XCTAssertEqual(read(folderData, name: "snippets.plist"), "local snippets")
    }

    // unionPushResultSignature must also match the folder in the no-extras common case (folder ⊆
    // local), where it reads ONLY the local copy (no remote read at all for the baseline).
    func testUnionPushResultSignatureMatchesFolderWithNoExtras() {
        let local = makeTempDir()
        let folderData = makeTempDir()
        populateAllFixtures(in: local, marker: "local")
        write("stale", to: folderData, name: "snippets.plist")   // folder has only a subset, all shared

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: local, toBase: folderData,
                                                        deleteMissing: false, createDestination: true))

        // After the union push the folder equals local (it had no items local lacks), so the composed
        // baseline equals both the folder's signature and local's signature.
        let composed = iTermRemoteDataFileSync.unionPushResultSignature(sourceBase: local,
                                                                        destinationBase: folderData)
        XCTAssertEqual(composed, iTermRemoteDataFileSync.contentSignature(base: folderData))
        XCTAssertEqual(composed, iTermRemoteDataFileSync.contentSignature(base: local))
    }

    // A large file inside the package still produces a correct, stable, content-sensitive signature.
    // fileDigest memory-maps rather than slurps the whole file, so this exercises that path (and would
    // catch a truncated/wrong digest) without depending on how large the file is.
    func testSignatureOfLargeFileInPackageIsStableAndSensitive() {
        let a = makeTempDir()
        let b = makeTempDir()
        let big = String(repeating: "0123456789abcdef", count: 128 * 1024)   // ~2 MB
        writeDirectoryFixture(to: a, name: "notes.rtfd", innerContents: "x")
        writeDirectoryFixture(to: b, name: "notes.rtfd", innerContents: "x")
        let aNotes = (a as NSString).appendingPathComponent("notes.rtfd")
        let bNotes = (b as NSString).appendingPathComponent("notes.rtfd")
        write(big, to: aNotes, name: "attachment.bin")
        write(big, to: bNotes, name: "attachment.bin")

        let sig = iTermRemoteDataFileSync.contentSignature(base: a)
        XCTAssertFalse(sig.isEmpty)
        XCTAssertEqual(sig, iTermRemoteDataFileSync.contentSignature(base: a))            // stable
        XCTAssertEqual(sig, iTermRemoteDataFileSync.contentSignature(base: b))            // same bytes

        write(big + "!", to: bNotes, name: "attachment.bin")                              // one byte more
        XCTAssertNotEqual(sig, iTermRemoteDataFileSync.contentSignature(base: b))
    }

    // Package filenames are NFC-normalized before framing, so the same logical attachment name stored
    // in different Unicode normalization forms (NFC vs NFD, as different filesystems/cloud services do)
    // yields the SAME signature over byte-identical content, avoiding a spurious perpetual conflict.
    func testSignatureIsFilenameNormalizationIndependent() {
        let nfcBase = makeTempDir()
        let nfdBase = makeTempDir()
        writeDirectoryFixture(to: nfcBase, name: "notes.rtfd", innerContents: "note")
        writeDirectoryFixture(to: nfdBase, name: "notes.rtfd", innerContents: "note")
        // "café.txt": NFC (é as one scalar) vs NFD (e + combining acute accent).
        write("attachment", to: (nfcBase as NSString).appendingPathComponent("notes.rtfd"),
              name: "caf\u{00E9}.txt")
        write("attachment", to: (nfdBase as NSString).appendingPathComponent("notes.rtfd"),
              name: "cafe\u{0301}.txt")

        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: nfcBase),
                       iTermRemoteDataFileSync.contentSignature(base: nfdBase))
    }

    // MARK: - Signature

    func testSignatureStableAndSensitive() {
        let base = makeTempDir()
        write("hello", to: base, name: "snippets.plist")
        let first = iTermRemoteDataFileSync.contentSignature(base: base)
        let second = iTermRemoteDataFileSync.contentSignature(base: base)
        XCTAssertEqual(first, second)

        write("hello world", to: base, name: "snippets.plist")
        let third = iTermRemoteDataFileSync.contentSignature(base: base)
        XCTAssertNotEqual(first, third)
    }

    func testSignatureSensitiveToPresence() {
        let withFile = makeTempDir()
        let withoutFile = makeTempDir()
        write("x", to: withFile, name: "graphic_icons.json")
        XCTAssertNotEqual(iTermRemoteDataFileSync.contentSignature(base: withFile),
                          iTermRemoteDataFileSync.contentSignature(base: withoutFile))
    }

    // A present-but-empty package (e.g. an empty notes.rtfd) must hash differently from a missing
    // one, so its presence isn't invisible to reconcile.
    func testEmptyPackagePresenceAffectsSignature() {
        let withEmptyPackage = makeTempDir()
        let withoutPackage = makeTempDir()
        try! FileManager.default.createDirectory(
            atPath: (withEmptyPackage as NSString).appendingPathComponent("notes.rtfd"),
            withIntermediateDirectories: true)
        XCTAssertNotEqual(iTermRemoteDataFileSync.contentSignature(base: withEmptyPackage),
                          iTermRemoteDataFileSync.contentSignature(base: withoutPackage))
    }

    func testMissingOptionalFilesHandledGracefully() {
        let source = makeTempDir()
        let destination = makeTempDir()
        // Only one of the allowlisted files is present.
        write("only", to: source, name: "snippets.plist")

        XCTAssertTrue(iTermRemoteDataFileSync.mirrorAll(fromBase: source,
                                                        toBase: destination,
                                                        deleteMissing: true,
                                                        createDestination: true))

        XCTAssertEqual(read(destination, name: "snippets.plist"), "only")
        // The signature is well-defined even though most allowlisted files are absent.
        XCTAssertFalse(iTermRemoteDataFileSync.contentSignature(base: destination).isEmpty)
    }

    // MARK: - New Tests for Improvements

    // pruneBackups keeps the newest `keep` backup folders, deletes older ones, and leaves non-backup
    // entries (which don't parse as "<timestamp> <UUID>") alone.
    func testBackupPruningRespectsConfigurableLimit() {
        let backupRoot = makeTempDir()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"

        var names: [String] = []
        for i in 1...5 {
            let date = Date(timeIntervalSinceNow: Double(i * -3600))   // 1 hour apart, newest first
            let name = "\(formatter.string(from: date)) \(UUID().uuidString)"
            names.append(name)
            try! FileManager.default.createDirectory(
                atPath: (backupRoot as NSString).appendingPathComponent(name),
                withIntermediateDirectories: true)
        }
        // A non-backup entry that must survive pruning.
        write("finder cruft", to: backupRoot, name: ".DS_Store")

        iTermRemoteDataFileSync.pruneBackups(root: backupRoot, keep: 3)

        let remaining = Set(try! FileManager.default.contentsOfDirectory(atPath: backupRoot))
        // The 3 newest (chronologically-latest names sort last) survive; the 2 oldest are gone.
        let sortedNames = names.sorted()
        XCTAssertFalse(remaining.contains(sortedNames[0]))
        XCTAssertFalse(remaining.contains(sortedNames[1]))
        XCTAssertTrue(remaining.contains(sortedNames[2]))
        XCTAssertTrue(remaining.contains(sortedNames[3]))
        XCTAssertTrue(remaining.contains(sortedNames[4]))
        // Non-backup entry untouched.
        XCTAssertTrue(remaining.contains(".DS_Store"))
    }

    // Regression for the cache-path double-unlock crash: the first (miss) and second (hit) calls to
    // cachedContentSignature must both return the same non-empty signature without trapping. Uses the
    // *cached* entry point (localContentSignature's guts), not the lock-free contentSignature.
    func testCachedContentSignatureMissThenHit() {
        iTermRemoteDataFileSync.resetSignatureCacheForTesting()
        let base = makeTempDir()
        write("hello", to: base, name: "snippets.plist")

        let miss = iTermRemoteDataFileSync.cachedContentSignature(base: base)
        let hit = iTermRemoteDataFileSync.cachedContentSignature(base: base)

        XCTAssertFalse(miss.isEmpty)
        XCTAssertEqual(miss, hit)
        // Matches the uncached signature of the same content.
        XCTAssertEqual(miss, iTermRemoteDataFileSync.contentSignature(base: base))
    }

    // A same-size content rewrite that preserves mtime must still be detected by the stat-cached
    // signature: the stat token includes ctime + inode (+ nanosecond mtime), not just size + second
    // mtime, so an edit isn't masked by the cache and silently left unsynced for the session. The
    // rewrite is atomic, so the inode changes deterministically (no reliance on clock granularity).
    func testCachedSignatureDetectsSameSizeMtimePreservedRewrite() {
        iTermRemoteDataFileSync.resetSignatureCacheForTesting()
        let base = makeTempDir()
        write("AAAA", to: base, name: "snippets.plist")
        let path = (base as NSString).appendingPathComponent("snippets.plist")
        let originalMtime = (try! FileManager.default.attributesOfItem(atPath: path))[.modificationDate] as! Date

        let first = iTermRemoteDataFileSync.cachedContentSignature(base: base)
        XCTAssertFalse(first.isEmpty)

        // Rewrite to different content of the SAME byte length, then restore the original mtime.
        try! "BBBB".data(using: .utf8)!.write(to: URL(fileURLWithPath: path), options: .atomic)
        try! FileManager.default.setAttributes([.modificationDate: originalMtime], ofItemAtPath: path)

        let second = iTermRemoteDataFileSync.cachedContentSignature(base: base)
        XCTAssertNotEqual(first, second,
                          "a same-size, mtime-preserved rewrite must not be masked by the stat cache")
        XCTAssertEqual(second, iTermRemoteDataFileSync.contentSignature(base: base))
    }

    // The stat-cache is scoped to its base, so querying the cached signature for one base then a
    // different base returns each base's own signature - the single-slot cache never serves base A's
    // signature for base B.
    func testCachedSignatureIsScopedToBase() {
        iTermRemoteDataFileSync.resetSignatureCacheForTesting()
        let a = makeTempDir()
        let b = makeTempDir()
        write("alpha", to: a, name: "snippets.plist")
        write("beta", to: b, name: "snippets.plist")

        let sigA = iTermRemoteDataFileSync.cachedContentSignature(base: a)
        let sigB = iTermRemoteDataFileSync.cachedContentSignature(base: b)
        XCTAssertNotEqual(sigA, sigB)
        XCTAssertEqual(sigA, iTermRemoteDataFileSync.contentSignature(base: a))
        XCTAssertEqual(sigB, iTermRemoteDataFileSync.contentSignature(base: b))
        // Re-querying a after b populated the single slot still returns a's signature.
        XCTAssertEqual(sigA, iTermRemoteDataFileSync.cachedContentSignature(base: a))
    }

    // Hammer the cached path concurrently (the one that holds the Mutex) to catch a lock imbalance or
    // an exclusivity trap. Deterministic: no sleeps, just many concurrent reads of the same base.
    func testCachedContentSignatureThreadSafety() {
        iTermRemoteDataFileSync.resetSignatureCacheForTesting()
        let base = makeTempDir()
        write("initial", to: base, name: "snippets.plist")
        let expected = iTermRemoteDataFileSync.contentSignature(base: base)

        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let signature = iTermRemoteDataFileSync.cachedContentSignature(base: base)
            XCTAssertEqual(signature, expected)
        }
    }

    // Temp files must be cleaned up even when a copy fails. Force the failure by making the
    // destination file IMMUTABLE (chflags UF_IMMUTABLE) so replaceItem throws. Skip (rather than trap
    // the whole bundle) on filesystems that don't support setting the immutable flag, e.g. some CI
    // network/overlay temp dirs.
    func testTempFileCleanupOnError() throws {
        let source = makeTempDir()
        let destination = makeTempDir()
        write("content", to: source, name: "snippets.plist")

        let destFile = (destination as NSString).appendingPathComponent("snippets.plist")
        write("old", to: destination, name: "snippets.plist")
        do {
            try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: destFile)
        } catch {
            throw XCTSkip("Filesystem does not support the immutable flag: \(error)")
        }
        defer {
            // Always clear the flag so tearDown can remove the temp dir.
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: destFile)
        }

        let result = iTermRemoteDataFileSync.mirrorAll(fromBase: source, toBase: destination,
                                                        deleteMissing: false, createDestination: false)

        XCTAssertFalse(result, "Mirror should fail when the destination file is immutable")
        // Non-vacuous: the failed copy must not have partially applied, so the destination still holds
        // the original bytes (proving replaceItem was attempted and aborted, not skipped)...
        XCTAssertEqual(read(destination, name: "snippets.plist"), "old")
        // ...and it must leave no temp sibling behind.
        let contents = try FileManager.default.contentsOfDirectory(atPath: destination)
        let tempFiles = contents.filter { $0.hasPrefix(".") && $0.hasSuffix(".tmp") }
        XCTAssertEqual(tempFiles.count, 0, "No temp files should remain after an error")
    }

    // allAbsentSignature() lets a caller that already holds a readable remote signature decide
    // "does the folder hold any target?" by string comparison, instead of a second (unbounded)
    // fileExists probe that could hang the main thread on an offline mount. For that substitution to
    // be correct it MUST equal what contentSignature produces for a base with none of the allowlisted
    // items present. This pins the two together so the hand-rolled all-absent framing can't drift from
    // contentSignature's .absent framing.
    func testAllAbsentSignatureMatchesEmptyBaseSignature() {
        let empty = makeTempDir()
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: empty),
                       iTermRemoteDataFileSync.allAbsentSignature())
    }

    // A base that is missing entirely (never created) is also all-absent.
    func testAllAbsentSignatureMatchesNonexistentBaseSignature() {
        let missing = (makeTempDir() as NSString).appendingPathComponent("does-not-exist")
        XCTAssertEqual(iTermRemoteDataFileSync.contentSignature(base: missing),
                       iTermRemoteDataFileSync.allAbsentSignature())
    }

    // A base holding any allowlisted item must NOT match the all-absent signature, or the discard /
    // reconcile call sites that compare against it would mistake a populated folder for an empty one
    // and delete local data or skip a real conflict.
    func testAllAbsentSignatureDiffersFromPopulatedBase() {
        let populated = makeTempDir()
        populateAllFixtures(in: populated, marker: "m")
        XCTAssertNotEqual(iTermRemoteDataFileSync.contentSignature(base: populated),
                          iTermRemoteDataFileSync.allAbsentSignature())
    }
}

// Guards the corrupt-snippets.plist data-loss fix: now that snippets.plist is a synced file, a
// present-but-unparseable copy (bad bytes synced from another Mac, or a truncated local write) must
// NOT be classified as a legitimately-empty set. If it were, -init would load zero snippets and the
// next -save would replace the corrupt file with a VALID empty plist that the sync layer publishes
// fleet-wide, wiping every other machine's snippets. These exercise the pure classifier behind that
// guard (see iTermSnippetsModel +fileIsPresentButUnparseableWithFallbackPresent:fileExists:fileData:).
class iTermSnippetsUnparseableGuardTests: XCTestCase {
    private func classify(fallbackPresent: Bool, fileExists: Bool, data: Data?) -> Bool {
        return iTermSnippetsModel.fileIsPresentButUnparseable(withFallbackPresent: fallbackPresent,
                                                              fileExists: fileExists,
                                                              fileData: data)
    }

    private func plistData(_ object: Any) -> Data {
        return try! PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }

    // A user-defaults fallback is authoritative and shadows the disk file, so disk corruption is moot.
    func testFallbackPresentIsNeverUnparseable() {
        XCTAssertFalse(classify(fallbackPresent: true, fileExists: true, data: Data([0x00, 0x01, 0x02])))
        XCTAssertFalse(classify(fallbackPresent: true, fileExists: false, data: nil))
    }

    // An absent file is a legitimate empty / first-run state, not corruption.
    func testAbsentFileIsNotUnparseable() {
        XCTAssertFalse(classify(fallbackPresent: false, fileExists: false, data: nil))
    }

    // A well-formed snippets plist (with or without entries) is parseable.
    func testValidSnippetsPlistIsParseable() {
        let populated = plistData(["snippets": [["title": "t", "value": "v", "guid": "g"]]])
        XCTAssertFalse(classify(fallbackPresent: false, fileExists: true, data: populated))

        let empty = plistData(["snippets": [Any]()])
        XCTAssertFalse(classify(fallbackPresent: false, fileExists: true, data: empty))
    }

    // The corruption cases that MUST be caught: unreadable bytes, a dict lacking the snippets array,
    // a snippets value that is not an array, and a non-dictionary root. Each would otherwise map to an
    // empty in-memory set and risk the fleet-wide empty publish.
    func testCorruptOrStructurallyWrongFileIsUnparseable() {
        // Garbage bytes that are not a plist at all.
        XCTAssertTrue(classify(fallbackPresent: false, fileExists: true, data: Data([0xde, 0xad, 0xbe, 0xef])))
        // A present-but-empty file (e.g. a truncated write that created a zero-byte file).
        XCTAssertTrue(classify(fallbackPresent: false, fileExists: true, data: Data()))
        // A valid plist dict that lacks the snippets array.
        XCTAssertTrue(classify(fallbackPresent: false, fileExists: true, data: plistData(["other": "x"])))
        // A valid plist whose snippets value is the wrong type.
        XCTAssertTrue(classify(fallbackPresent: false, fileExists: true, data: plistData(["snippets": "not-an-array"])))
        // A valid plist whose root is an array, not a dictionary.
        XCTAssertTrue(classify(fallbackPresent: false, fileExists: true, data: plistData([1, 2, 3])))
    }
}

// Guards ToolNotes' overwrite backup guard: it must detect a FOREIGN rewrite of notes.rtfd that lands
// in the SAME coarse mtime tick (common on the 1-2s-resolution synced/network folders this feature
// targets) so it backs up the on-disk copy before clobbering it. A plain mtime compare would miss that;
// the richer stat token (dev/size/mtime.ns/ctime.ns/inode) must not.
class iTermToolNotesStatTokenTests: XCTestCase {
    private var dir: String = ""

    override func setUp() {
        super.setUp()
        dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("ToolNotesStatTokenTests-" + UUID().uuidString)
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dir)
        super.tearDown()
    }

    func testAbsentFileHasNilToken() {
        let missing = (dir as NSString).appendingPathComponent("nope")
        XCTAssertNil(iTermRemoteDataFileSync.statTokenForFile(atPath: missing))
    }

    func testStatTokenDetectsSameMtimeForeignRewrite() {
        let path = (dir as NSString).appendingPathComponent("notes.rtfd")
        let fixedMtime = Date(timeIntervalSince1970: 1_600_000_000)

        try! "AAAA".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        try! FileManager.default.setAttributes([.modificationDate: fixedMtime], ofItemAtPath: path)
        let token1 = iTermRemoteDataFileSync.statTokenForFile(atPath: path)
        XCTAssertNotNil(token1)

        // A foreign rewrite: different content/size, but forced back to the SAME mtime tick.
        try! "BBBBBBBB".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        try! FileManager.default.setAttributes([.modificationDate: fixedMtime], ofItemAtPath: path)
        let token2 = iTermRemoteDataFileSync.statTokenForFile(atPath: path)
        XCTAssertNotNil(token2)

        // A plain mtime compare would call these equal and SKIP the recovery backup, clobbering the
        // foreign copy. The richer token (size + ctime, which can't be forced back) must differ.
        XCTAssertNotEqual(token1, token2)
    }

    // The token is stable when nothing changed, so an unedited note doesn't spuriously back up on every
    // write attempt.
    func testStatTokenStableWhenUnchanged() {
        let path = (dir as NSString).appendingPathComponent("notes.rtfd")
        try! "hello".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(iTermRemoteDataFileSync.statTokenForFile(atPath: path), iTermRemoteDataFileSync.statTokenForFile(atPath: path))
    }
}
