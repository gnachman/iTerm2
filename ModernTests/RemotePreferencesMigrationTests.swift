//
//  RemotePreferencesMigrationTests.swift
//  ModernTests
//
//  With “Load settings from a custom folder” on, quitting asks to copy settings
//  to the folder whenever local prefs differ from the folder's plist. One-time
//  migrations of synced keys (the alt-screen bidi rename, adding done and error
//  to a saved status priority list) change local prefs at every launch while
//  the folder keeps the old values, so quitting without touching anything
//  prompted every time. These cover reporting a migration's changes and
//  comparing local prefs against the folder's prefs with the migration applied.
//

import XCTest
@testable import iTerm2SharedARC

final class RemotePreferencesMigrationTests: XCTestCase {
    private let suite = "test.iterm2.remoteprefs.migration"
    private var observer: NSObjectProtocol?

    private func freshDefaults() -> UserDefaults {
        let ud = UserDefaults(suiteName: suite)!
        ud.removePersistentDomain(forName: suite)
        return ud
    }

    override func tearDown() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private struct Migration {
        var before: [String: Any]
        var after: [String: Any]
    }

    /// Loads `remote` into fresh defaults (as copying down the folder's prefs
    /// does), runs `migrate`, and returns the defaults plus the migrations it
    /// reported.
    private func runMigration(remote: [String: Any],
                              _ migrate: (UserDefaults) -> Void) -> (UserDefaults, [Migration]) {
        let ud = freshDefaults()
        for (key, value) in remote {
            ud.set(value, forKey: key)
        }
        var migrations = [Migration]()
        observer = NotificationCenter.default.addObserver(
            forName: .iTermUserDefaultsDidMigrateKeys,
            object: ud,
            queue: nil) { notification in
                let info = notification.userInfo ?? [:]
                migrations.append(Migration(
                    before: info[iTermUserDefaultsMigrationValuesBeforeKey] as? [String: Any] ?? [:],
                    after: info[iTermUserDefaultsMigrationValuesAfterKey] as? [String: Any] ?? [:]))
            }
        migrate(ud)
        return (ud, migrations)
    }

    private func local(_ ud: UserDefaults) -> [AnyHashable: Any] {
        return ud.persistentDomain(forName: suite) ?? [:]
    }

    private func differ(_ local: [AnyHashable: Any], _ remote: [AnyHashable: Any]) -> Bool {
        return iTermRemotePreferences.localPrefs(local,
                                                 differFromRemotePrefs: remote,
                                                 preservedKeys: [],
                                                 respectingDefaults: false)
    }

    private func applying(_ migrations: [Migration], to remote: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var result = remote
        for migration in migrations {
            result = iTermRemotePreferences.remotePrefs(result,
                                                        byApplyingMigrationFromValues: migration.before,
                                                        toValues: migration.after)
        }
        return result
    }

    // F-216: the folder holds AlternateScreenBidi=NO. The migration turns it
    // into DisableBidiInAlternateScreen=YES locally. Without accounting for the
    // migration, local differs from the folder and quitting prompts.
    func testAltScreenBidiMigrationIsNotALocalEdit() {
        let remote: [String: Any] = ["AlternateScreenBidi": false, "Bidi": true]
        let (ud, migrations) = runMigration(remote: remote) { ud in
            iTermAdvancedSettingsModel.migrateAlternateScreenBidiSetting(in: ud)
        }
        XCTAssertTrue(ud.bool(forKey: "DisableBidiInAlternateScreen"))
        XCTAssertTrue(differ(local(ud), remote),
                      "precondition: the migration changes synced keys relative to the folder")
        XCTAssertEqual(migrations.count, 1, "the migration must be reported")
        XCTAssertFalse(differ(local(ud), applying(migrations, to: remote)),
                       "a migration's own change must not count as a local edit")
    }

    func testPerformMigrationsReportsAltScreenBidiMigration() {
        let remote: [String: Any] = ["AlternateScreenBidi": false]
        let (ud, migrations) = runMigration(remote: remote) { ud in
            iTermUserDefaults.performMigrations(in: ud)
        }
        XCTAssertFalse(differ(local(ud), applying(migrations, to: remote)))
    }

    // F-069: the folder holds a status priority list saved before done and
    // error existed, without the flag recording that they were added.
    func testStatusPriorityMigrationIsNotALocalEdit() throws {
        let saved = [StatusPriorityEntry(pattern: "wait"),
                     StatusPriorityEntry(pattern: "work"),
                     StatusPriorityEntry(pattern: "idle")]
        let remote: [String: Any] = ["StatusPriorityEntries": try JSONEncoder().encode(saved)]
        let (ud, migrations) = runMigration(remote: remote) { ud in
            StatusPrioritySettings.writeMigratedEntries(StatusPrioritySettings.addingDoneAndError(to: saved),
                                                        to: ud)
        }
        XCTAssertTrue(ud.bool(forKey: "StatusPriorityAddedDoneAndError"))
        XCTAssertTrue(differ(local(ud), remote),
                      "precondition: the migration changes synced keys relative to the folder")
        XCTAssertEqual(migrations.count, 1, "the migration must be reported")
        XCTAssertFalse(differ(local(ud), applying(migrations, to: remote)))
    }

    func testLegacyStatusPriorityMigrationIsNotALocalEdit() {
        let remote: [String: Any] = ["StatusPriorities": ["wait", "work", "idle"]]
        let (ud, migrations) = runMigration(remote: remote) { ud in
            let saved = ["wait", "work", "idle"].map { StatusPriorityEntry(pattern: $0) }
            StatusPrioritySettings.writeMigratedEntries(StatusPrioritySettings.addingDoneAndError(to: saved),
                                                        to: ud)
        }
        XCTAssertNil(ud.object(forKey: "StatusPriorities"))
        XCTAssertFalse(differ(local(ud), applying(migrations, to: remote)))
    }

    // A user's real change made after the migration still has to be copied.
    func testEditAfterMigrationIsStillALocalEdit() {
        let remote: [String: Any] = ["AlternateScreenBidi": false, "Bidi": true]
        let (ud, migrations) = runMigration(remote: remote) { ud in
            iTermAdvancedSettingsModel.migrateAlternateScreenBidiSetting(in: ud)
        }
        ud.set(false, forKey: "Bidi")
        XCTAssertTrue(differ(local(ud), applying(migrations, to: remote)))
    }

    // If a key's local value had already diverged from the folder before the
    // migration ran, the migrated value is still a real difference.
    func testMigrationOfAnAlreadyEditedKeyStaysALocalEdit() {
        let remote: [AnyHashable: Any] = ["AlternateScreenBidi": true]
        let migrated = iTermRemotePreferences.remotePrefs(remote,
                                                          byApplyingMigrationFromValues: ["AlternateScreenBidi": false],
                                                          toValues: ["DisableBidiInAlternateScreen": true])
        XCTAssertEqual(migrated["AlternateScreenBidi"] as? Bool, true,
                       "a folder value the migration did not start from must be kept")
        XCTAssertEqual(migrated["DisableBidiInAlternateScreen"] as? Bool, true,
                       "a key absent locally and in the folder before the migration takes the migrated value")
        XCTAssertTrue(differ(["DisableBidiInAlternateScreen": true], migrated))
    }

    func testUnchangedKeysAreNotReported() {
        let (_, migrations) = runMigration(remote: ["DisableBidiInAlternateScreen": true]) { ud in
            iTermUserDefaults.migrateKeys(["DisableBidiInAlternateScreen"], in: ud) {
                ud.set(true, forKey: "DisableBidiInAlternateScreen")
            }
        }
        XCTAssertTrue(migrations.isEmpty)
    }
}
