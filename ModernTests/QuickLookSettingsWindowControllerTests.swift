//
//  QuickLookSettingsWindowControllerTests.swift
//  ModernTests
//
//  The Quick Look settings sheet opened by Settings > Pointer > Configure….
//

import XCTest
@testable import iTerm2SharedARC

final class QuickLookSettingsWindowControllerTests: XCTestCase {
    private let keys = [kPreferenceKeyQuickLookUsesBrowserEngine,
                        kPreferenceKeyQuickLookHoverDelay,
                        kPreferenceKeyQuickLookHoverAutoCloseDelay,
                        kPreferenceKeyQuickLookHoverDomainAllowlist,
                        kPreferenceKeyQuickLookHoverIncludesPlainTextURLs]
    private var saved = [String: Any]()

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = iTermPreferences.object(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            iTermPreferences.setObject(saved[key], forKey: key)
        }
        super.tearDown()
    }

    func testSecondsParseWithTheLocaleDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        let american = Locale(identifier: "en_US")
        XCTAssertEqual(iTermQuickLookSettingsWindowController.seconds(from: "0,75", locale: german), 0.75)
        XCTAssertEqual(iTermQuickLookSettingsWindowController.seconds(from: "0.75", locale: german), 0.75,
                       "a period works in every locale")
        XCTAssertEqual(iTermQuickLookSettingsWindowController.seconds(from: " 2 ", locale: german), 2)
        XCTAssertEqual(iTermQuickLookSettingsWindowController.seconds(from: "1.5", locale: american), 1.5)
        XCTAssertNil(iTermQuickLookSettingsWindowController.seconds(from: "", locale: german))
        XCTAssertNil(iTermQuickLookSettingsWindowController.seconds(from: "abc", locale: american))
        XCTAssertEqual(iTermQuickLookSettingsWindowController.string(fromSeconds: 0.75, locale: german), "0,75")
    }

    func testPluginNote() {
        XCTAssertNil(iTermQuickLookSettingsWindowController.pluginNote(browserEngineOn: false,
                                                                       browserProfilesOn: false,
                                                                       pluginAvailable: { XCTFail("not asked"); return false }),
                     "no note while the setting is off, and no plugin check")
        XCTAssertNotNil(iTermQuickLookSettingsWindowController.pluginNote(browserEngineOn: true,
                                                                          browserProfilesOn: false,
                                                                          pluginAvailable: { true }))
        XCTAssertNotNil(iTermQuickLookSettingsWindowController.pluginNote(browserEngineOn: true,
                                                                          browserProfilesOn: true,
                                                                          pluginAvailable: { false }))
        XCTAssertNil(iTermQuickLookSettingsWindowController.pluginNote(browserEngineOn: true,
                                                                       browserProfilesOn: true,
                                                                       pluginAvailable: { true }))
    }

    // The old text field saved a string. Its entries carry over, normalized and without duplicates.
    func testSavedDomainsNormalizeAndAcceptTheOldStringFormat() {
        iTermPreferences.setObject("*.github.com, https://linear.app/x\nGitHub.com .", forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        XCTAssertEqual(iTermQuickLookDomainAllowlist.savedDomains(), ["github.com", "linear.app"])

        iTermPreferences.setObject(["example.org", "EXAMPLE.org."], forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        XCTAssertEqual(iTermQuickLookDomainAllowlist.savedDomains(), ["example.org"])
    }

    func testLoadsTheCurrentSettings() {
        iTermPreferences.setDouble(0.5, forKey: kPreferenceKeyQuickLookHoverDelay)
        iTermPreferences.setDouble(2, forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyQuickLookHoverIncludesPlainTextURLs)
        let sheet = iTermQuickLookSettingsWindowController()

        XCTAssertEqual(iTermQuickLookSettingsWindowController.seconds(from: sheet.hoverDelayField.stringValue, locale: .current), 0.5)
        XCTAssertEqual(iTermQuickLookSettingsWindowController.seconds(from: sheet.autoCloseDelayField.stringValue, locale: .current), 2)
        XCTAssertEqual(sheet.neverCloseCheckbox.state, .off)
        XCTAssertTrue(sheet.autoCloseDelayField.isEnabled)
        XCTAssertEqual(sheet.plainTextCheckbox.state, .on)
    }

    func testNeverStoresZeroAndUncheckingRestoresTheDefault() {
        iTermPreferences.setDouble(3, forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay)
        let sheet = iTermQuickLookSettingsWindowController()

        sheet.neverCloseCheckbox.performClick(nil)
        XCTAssertEqual(iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay), 0)
        XCTAssertFalse(sheet.autoCloseDelayField.isEnabled, "no delay to edit while it never closes")

        sheet.neverCloseCheckbox.performClick(nil)
        XCTAssertEqual(iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverAutoCloseDelay), 1.5)
        XCTAssertTrue(sheet.autoCloseDelayField.isEnabled)
    }

    func testTypingSecondsStoresTheParsedValue() {
        let sheet = iTermQuickLookSettingsWindowController()
        sheet.hoverDelayField.stringValue = "1.25"
        sheet.hoverDelayField.sendAction(sheet.hoverDelayField.action, to: sheet.hoverDelayField.target)
        XCTAssertEqual(iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverDelay), 1.25)

        sheet.hoverDelayField.stringValue = "-4"
        sheet.hoverDelayField.sendAction(sheet.hoverDelayField.action, to: sheet.hoverDelayField.target)
        XCTAssertEqual(iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverDelay), 0, "negative is stored as 0")

        sheet.hoverDelayField.stringValue = "soon"
        sheet.hoverDelayField.sendAction(sheet.hoverDelayField.action, to: sheet.hoverDelayField.target)
        XCTAssertEqual(iTermPreferences.double(forKey: kPreferenceKeyQuickLookHoverDelay), 0, "text that isn't a number changes nothing")
    }

    // Edits in the table save the list as an array of normalized domains.
    func testEditingTheTableSavesNormalizedDomains() {
        iTermPreferences.setObject(["github.com"], forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        let sheet = iTermQuickLookSettingsWindowController()
        guard let crud = sheet.crudController else {
            XCTFail("no table")
            return
        }

        sheet.crudTextFieldDidChange(crud, row: 0, column: 0, newValue: "https://Linear.app/team")
        XCTAssertEqual(iTermPreferences.object(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist) as? [String], ["linear.app"])

        sheet.crudState = ["a.example", "b.example"]
        sheet.crudTextFieldDidChange(crud, row: 1, column: 0, newValue: "A.example")
        XCTAssertEqual(iTermPreferences.object(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist) as? [String], ["a.example"],
                       "editing a row into a duplicate removes it")
    }
}
