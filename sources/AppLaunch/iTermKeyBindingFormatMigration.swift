//
//  iTermKeyBindingFormatMigration.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/4/26.
//

import Foundation

// Rewrites key bindings stored in the old three-part format ("0xchar-0xmods-0xkeycode") into the
// modern format where the answer doesn't depend on the machine. A nonzero keycode is always real,
// so those become four-part keys. Keycode 0 is ambiguous because older versions wrote 0 when the
// keycode was unknown: with a or A it becomes a four-part key, and with a character the A key can
// never type (such as Forward Delete or a numeric keypad key) it becomes a two-part key with no
// keycode. Any other keycode-0 key stays three-part, because whether to trust it depends on the
// enabled keyboard layouts, which can differ between machines sharing these settings and can
// change over time. iTermKeystroke reinterprets those each time it parses them.
//
// iTermKeystroke applies the same interpretation when parsing, so this isn't needed for
// correctness; it makes the stored data unambiguous where possible. It runs only once. Running
// every launch would modify settings loaded from a custom folder each time (so users who don't
// save changes back would be asked about it repeatedly) and would fight with an older version of
// iTerm2 sharing those settings. Three-part keys written after this runs are still read correctly.
@objc(iTermKeyBindingFormatMigration)
class iTermKeyBindingFormatMigration: NSObject {
    private static let globalKeyMapUserDefaultsKey = "GlobalKeyMap"
    private static let didMigrateUserDefaultsKey = "NoSyncDidMigrateKeyBindingFormat"

    @objc static func migrate() {
        let userDefaults = iTermUserDefaults.userDefaults()
        if userDefaults.bool(forKey: didMigrateUserDefaultsKey) {
            return
        }
        userDefaults.set(true, forKey: didMigrateUserDefaultsKey)
        migrateGlobalKeyMap()
        if let model = ProfileModel.sharedInstance() {
            migrateProfiles(in: model)
        }
    }

    /// Returns the migrated dictionary, or nil if it contains nothing to migrate.
    @objc(migratedKeyMappings:)
    static func migratedKeyMappings(_ keyMappings: [String: Any]?) -> [String: Any]? {
        guard let keyMappings else {
            return nil
        }
        var result = keyMappings
        var changed = false
        // Sort so that the outcome is deterministic if two old keys migrate to the same new key.
        for key in keyMappings.keys.sorted() {
            guard let modern = iTermKeystroke.modernSerialization(forThreePartKey: key),
                  modern != key,
                  let value = result.removeValue(forKey: key) else {
                continue
            }
            changed = true
            if result[modern] != nil {
                // A binding already uses the modern spelling. When both existed, the lookup
                // preferred it, so drop the old one.
                DLog("Drop key binding \(key) because \(modern) already exists")
                continue
            }
            DLog("Migrate key binding \(key) to \(modern)")
            result[modern] = value
        }
        return changed ? result : nil
    }

    private static func migrateGlobalKeyMap() {
        // When the user defaults key is absent the factory default is used. Don't write it.
        guard let globalKeyMap = iTermUserDefaults.userDefaults().object(forKey: globalKeyMapUserDefaultsKey) as? [String: Any],
              let migrated = migratedKeyMappings(globalKeyMap) else {
            return
        }
        RLog("Migrating global key map to the modern key binding format")
        iTermKeyMappings.setGlobalKeyMap(migrated)
    }

    private static func migrateProfiles(in model: ProfileModel) {
        var changed = false
        for profile in model.bookmarks() {
            // The dynamic profile manager regenerates a dynamic profile from its file, so only
            // rewritable ones (whose files the user allowed us to update) are migrated.
            if (profile[KEY_DYNAMIC_PROFILE] as? NSNumber)?.boolValue == true,
               !iTermProfilePreferences.bool(forKey: KEY_DYNAMIC_PROFILE_REWRITABLE, inProfile: profile) {
                continue
            }
            guard let migrated = migratedKeyMappings(profile[KEY_KEYBOARD_MAP] as? [String: Any]) else {
                continue
            }
            RLog("Migrating key bindings in profile \(profile[KEY_GUID] ?? "(no guid)") to the modern key binding format")
            model.setObject(migrated, forKey: KEY_KEYBOARD_MAP, inBookmark: profile)
            changed = true
        }
        if changed {
            model.flush()
        }
    }
}
