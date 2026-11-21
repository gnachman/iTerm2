//
//  PreferencePanelNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of PreferencePanel.h and
//  iTermPreferencesBaseViewController.h that the nullability sanitizer found
//  false (unit N2 of docs/swift-migration/nullability-triage.md). The
//  Objective-C methods return nil, or accept nil, by design; these tests pin
//  what Swift sees.
//

import XCTest
@testable import iTerm2SharedARC

final class PreferencePanelNullabilityTests: XCTestCase {
    // Not a preference key, so iTermPreferences has no default for it.
    private let keyWithoutDefault = "NoSuchPreferenceKeyForNullabilityTests"

    // -[iTermPreferencesBaseViewController defaultValueForKey:] returns the
    // lookup +[iTermPreferences defaultObjectForKey:], which is nil for a key
    // without a default. While the claim was nonnull, Swift held that nil as a
    // non-optional Any and this assertion saw a value.
    func testDefaultValueForKeyWithoutADefaultIsNil() {
        let viewController = iTermPreferencesBaseViewController(nibName: nil, bundle: nil)
        XCTAssertNil(viewController.defaultValue(forKey: keyWithoutDefault))
    }

    func testDefaultValueForKeyWithADefaultIsTheDefault() {
        let viewController = iTermPreferencesBaseViewController(nibName: nil, bundle: nil)
        let value = viewController.defaultValue(forKey: kPreferenceKeyQuitWhenAllWindowsClosed)
        XCTAssertEqual(value as? NSNumber,
                       iTermPreferences.defaultObject(forKey: kPreferenceKeyQuitWhenAllWindowsClosed) as? NSNumber)
        XCTAssertNotNil(value)
    }

    // -[iTermPrefsPanelDelegate responderWillBecomeFirstResponder:] receives nil
    // from -[iTermPrefsPanel makeFirstResponder:nil], an ordinary AppKit call.
    // PreferencePanel, the only conformer, tests for nil and does nothing.
    func testResponderWillBecomeFirstResponderAcceptsNil() throws {
        let panel = PreferencePanel(profileModel: ProfileModel.sharedInstance(),
                                    editCurrentSessionMode: false)
        let delegate = try XCTUnwrap((panel as AnyObject) as? iTermPrefsPanelDelegate)
        delegate.responderWillBecomeFirstResponder(nil)
        XCTAssertFalse(panel.isWindowLoaded)
    }
}
