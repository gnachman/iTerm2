//
//  ProfileReloadScopeTests.swift
//  ModernTests
//
//  The map from profile key to reload scope in ProfileReloadScope.swift is maintained by hand.
//  Only color keys can be misclassified (every other key gets the full reload), so these tests
//  check that every color key iTermProfilePreferences knows about has been classified by hand as
//  either in the colors scope or excluded from it, and that plans built from a profile diff pick
//  the colors-only path exactly when only colors changed.
//

import XCTest
@testable import iTerm2SharedARC

final class ProfileReloadScopeTests: XCTestCase {

    // MARK: - Table completeness

    func testEveryColorKeyIsClassified() {
        let colorKeys = Set(iTermProfilePreferences.allKeys().filter { iTermProfilePreferences.keyIsColor($0) })
        let classified = ProfileReloadScopes.colorsScopeKeys.union(ProfileReloadScopes.colorKeysExcludedFromColorsScope)
        let unclassified = colorKeys.subtracting(classified).sorted()
        XCTAssertTrue(unclassified.isEmpty,
                      "Color keys with no reload scope (add them to colorsScopeKeys or colorKeysExcludedFromColorsScope in ProfileReloadScope.swift): \(unclassified)")
        let unknown = classified.subtracting(colorKeys).sorted()
        XCTAssertTrue(unknown.isEmpty,
                      "ProfileReloadScope.swift classifies keys iTermProfilePreferences does not consider colors: \(unknown)")
    }

    func testExcludedColorKeysAreNotInColorsScope() {
        let overlap = ProfileReloadScopes.colorsScopeKeys.intersection(ProfileReloadScopes.colorKeysExcludedFromColorsScope).sorted()
        XCTAssertTrue(overlap.isEmpty, "Keys in more than one scope: \(overlap)")
        for key in ProfileReloadScopes.colorKeysExcludedFromColorsScope {
            XCTAssertEqual(ProfileReloadScopes.scope(forKey: key), .everything)
        }
    }

    func testColorsScopeContainsOnlyColorKeys() {
        for key in ProfileReloadScopes.colorsScopeKeys {
            XCTAssertTrue(iTermProfilePreferences.keyIsColor(key), "\(key) is in the colors scope but is not a color key")
        }
    }

    func testColorsScopeContainsAllVariantsOfEachColorKey() {
        for key in ProfileReloadScopes.colorsScopeKeys {
            let base = iTermProfilePreferences.baseColorKey(forKey: key)
            for variant in iTermProfilePreferences.colorVariantKeys(forBaseKey: base) {
                XCTAssertTrue(ProfileReloadScopes.colorsScopeKeys.contains(variant),
                              "\(variant) should be in the colors scope because \(key) is")
            }
        }
    }

    func testUnknownKeyGetsEverythingScope() {
        XCTAssertEqual(ProfileReloadScopes.scope(forKey: "Some Key Nobody Has Heard Of"), .everything)
    }

    func testSeparateColorsFlagNeedsFullReload() {
        // It changes how non-color settings resolve their light/dark variants, so it must not be
        // in the colors scope.
        XCTAssertEqual(ProfileReloadScopes.scope(forKey: KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE), .everything)
    }

    // MARK: - Plans

    private let red: [String: Any] = ["Red Component": 1.0, "Green Component": 0.0, "Blue Component": 0.0]
    private let blue: [String: Any] = ["Red Component": 0.0, "Green Component": 0.0, "Blue Component": 1.0]

    private func profile(_ overrides: [String: Any] = [:]) -> NSDictionary {
        var dict: [String: Any] = [
            KEY_GUID: "guid",
            KEY_NAME: "Name",
            KEY_CURSOR_COLOR: red,
            KEY_CURSOR_COLOR + COLORS_LIGHT_MODE_SUFFIX: red,
            KEY_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX: red,
            KEY_TRANSPARENCY: 0.0,
        ]
        for (key, value) in overrides {
            dict[key] = value
        }
        return dict as NSDictionary
    }

    func testCursorColorChangeReloadsOnlyColors() {
        // What OSC 12 writes: all three variants of the cursor color key.
        let new = profile([KEY_CURSOR_COLOR: blue,
                           KEY_CURSOR_COLOR + COLORS_LIGHT_MODE_SUFFIX: blue,
                           KEY_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX: blue])
        let plan = ProfileReloadPlan.plan(from: profile(), to: new)
        XCTAssertFalse(plan.reloadsEverything)
        XCTAssertEqual(plan.changedKeys, [KEY_CURSOR_COLOR,
                                          KEY_CURSOR_COLOR + COLORS_LIGHT_MODE_SUFFIX,
                                          KEY_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX])
    }

    func testNonColorChangeReloadsEverything() {
        let plan = ProfileReloadPlan.plan(from: profile(), to: profile([KEY_TRANSPARENCY: 0.5]))
        XCTAssertTrue(plan.reloadsEverything)
    }

    func testMixedChangeReloadsEverything() {
        let plan = ProfileReloadPlan.plan(from: profile(), to: profile([KEY_CURSOR_COLOR: blue, KEY_TRANSPARENCY: 0.5]))
        XCTAssertTrue(plan.reloadsEverything)
    }

    func testColorKeyRemovedReloadsOnlyColors() {
        // OSC 112 restoring a baseline with no value removes the key.
        let old = profile()
        let new = (old.mutableCopy() as! NSMutableDictionary)
        new.removeObject(forKey: KEY_CURSOR_COLOR)
        let plan = ProfileReloadPlan.plan(from: old, to: new)
        XCTAssertFalse(plan.reloadsEverything)
        XCTAssertEqual(plan.changedKeys, [KEY_CURSOR_COLOR])
    }

    func testGUIDChangeReloadsEverything() {
        let plan = ProfileReloadPlan.plan(from: profile(), to: profile([KEY_GUID: "other"]))
        XCTAssertTrue(plan.reloadsEverything)
    }

    func testBindingsChangeReloadsEverything() {
        // Clearing a palette binding alongside an OSC color write must still rebuild bindings.
        let plan = ProfileReloadPlan.plan(from: profile(), to: profile([KEY_CURSOR_COLOR: blue, KEY_BINDINGS: [:]]))
        XCTAssertTrue(plan.reloadsEverything)
    }

    func testNoChangeFallsBackToEverything() {
        // The caller decided a reload was needed; a plan must never reload nothing.
        let plan = ProfileReloadPlan.plan(from: profile(), to: profile())
        XCTAssertTrue(plan.reloadsEverything)
    }

    func testNilOldProfileFallsBackToEverything() {
        let plan = ProfileReloadPlan.plan(from: nil, to: profile())
        XCTAssertTrue(plan.reloadsEverything)
    }

    func testEverythingPlanReloadsEverything() {
        XCTAssertTrue(ProfileReloadPlan.everything.reloadsEverything)
    }

    // MARK: - Read recorder

    func testRecorderTracksReadsOutsideColorsSectionOnly() {
        let recorder = iTermProfileReadRecorder(profile: profile() as! [AnyHashable: Any])
        recorder.inColorsSection = true
        _ = recorder.object(forKey: KEY_CURSOR_COLOR)
        recorder.inColorsSection = false
        _ = recorder.object(forKey: KEY_NAME)
        XCTAssertTrue(recorder.colorsScopeKeysReadOutsideColorsSection.isEmpty)
        XCTAssertNil(recorder.firstLeakBacktrace)

        _ = recorder.object(forKey: KEY_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX)
        XCTAssertEqual(recorder.colorsScopeKeysReadOutsideColorsSection, [KEY_CURSOR_COLOR + COLORS_DARK_MODE_SUFFIX])
        XCTAssertNotNil(recorder.firstLeakBacktrace)
    }

    func testRecorderSubscriptIsARead() {
        let recorder = iTermProfileReadRecorder(profile: profile() as! [AnyHashable: Any])
        _ = recorder[KEY_CURSOR_COLOR]
        XCTAssertEqual(recorder.colorsScopeKeysReadOutsideColorsSection, [KEY_CURSOR_COLOR])
    }

    func testRecorderCopyEnumerationAndBridgingAreNotReads() {
        let recorder = iTermProfileReadRecorder(profile: profile() as! [AnyHashable: Any])
        _ = recorder.copy()
        _ = recorder.mutableCopy()
        _ = recorder.allKeys
        _ = recorder.allValues
        _ = recorder.description
        _ = recorder.count
        _ = recorder.hash
        XCTAssertTrue(recorder.isEqual(to: profile() as! [AnyHashable: Any]))
        XCTAssertTrue(recorder.isEqual(iTermProfileReadRecorder(profile: profile() as! [AnyHashable: Any])))
        XCTAssertFalse(recorder.isEqual(to: profile([KEY_CURSOR_COLOR: blue]) as! [AnyHashable: Any]))
        var enumerated = 0
        recorder.enumerateKeysAndObjects { _, _, _ in enumerated += 1 }
        XCTAssertEqual(enumerated, profile().count)
        // Note that Swift's for-in over an NSDictionary is not covered here: its iterator fetches
        // each value with objectForKey:, so it does count as reads.
        // Bridging to a Swift dictionary copies the whole profile. That is not a read, and reads
        // of the copy are invisible to the recorder.
        let bridged = recorder as NSDictionary as! [String: Any]
        _ = bridged[KEY_CURSOR_COLOR]
        XCTAssertTrue(recorder.colorsScopeKeysReadOutsideColorsSection.isEmpty)
        XCTAssertEqual(recorder.count, profile().count)
        XCTAssertEqual(bridged.count, profile().count)
    }
}
