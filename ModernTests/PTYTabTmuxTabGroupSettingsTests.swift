//
//  PTYTabTmuxTabGroupSettingsTests.swift
//  ModernTests
//
//  Tab group membership of tmux tabs is saved in the @per_tab_settings session
//  option so it survives detach and reattach. These tests cover the per-tab
//  encoding: g= (group ID), gn= (name), gc= (color), gx= (collapsed).
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabTmuxTabGroupSettingsTests: XCTestCase {
    private func makeTab() -> PTYTab {
        let session = PTYSession(synthetic: false)!
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        return PTYTab(session: session, parentWindow: nil)!
    }

    private func base64(_ string: String) -> String {
        return Data(string.utf8).base64EncodedString()
    }

    func testUngroupedTabWithoutTitleHasNoSetting() {
        XCTAssertNil(makeTab().tmuxPerTabSetting())
    }

    func testGroupRoundTrips() throws {
        let original = makeTab()
        original.tabGroupID = "8C1F0E5A-2B7D-4E3A-9F11-0D6C2A7B5E44"
        original.tabGroupName = "web & api; a=b: c"
        original.tabGroupColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        original.tabGroupCollapsed = true

        let setting = try XCTUnwrap(original.tmuxPerTabSetting())
        XCTAssertFalse(setting.contains(";"), "Semicolon separates tabs in @per_tab_settings")

        let restored = makeTab()
        restored.setPerTabSettings(setting)
        XCTAssertEqual(restored.tabGroupID, original.tabGroupID)
        XCTAssertEqual(restored.tabGroupName, original.tabGroupName)
        XCTAssertTrue(restored.tabGroupCollapsed)
        XCTAssertEqual(restored.tmuxPerTabSetting(), setting)
    }

    func testGroupColorKeepsItsColorSpaceAcrossSaves() throws {
        let colors = [
            NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1),
            NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1),
            NSColor(displayP3Red: 0.9, green: 0.1, blue: 0.3, alpha: 1),
            // New groups get system colors, which have no color space of their own.
            NSColor.systemBlue,
        ]
        for color in colors {
            let original = makeTab()
            original.tabGroupID = "group-color"
            original.tabGroupColor = color
            var setting = try XCTUnwrap(original.tmuxPerTabSetting())
            // Saving the restored tab again must give the same value, so repeated
            // detach and reattach can't drift the color.
            for _ in 0..<3 {
                let restored = makeTab()
                restored.setPerTabSettings(setting)
                if color.type == .componentBased {
                    XCTAssertEqual(restored.tabGroupColor?.colorSpace, color.colorSpace)
                }
                let resaved = try XCTUnwrap(restored.tmuxPerTabSetting())
                XCTAssertEqual(resaved, setting)
                setting = resaved
            }
        }
    }

    func testTitleAndGroupRoundTripTogether() throws {
        let original = makeTab()
        original.setPerTabSettings("t=" + base64("my title"))
        original.tabGroupID = "group-1"
        original.tabGroupName = "Group"

        let setting = try XCTUnwrap(original.tmuxPerTabSetting())
        let restored = makeTab()
        restored.setPerTabSettings(setting)
        let parts = try XCTUnwrap(restored.tmuxPerTabSetting()).components(separatedBy: "&")
        XCTAssertTrue(parts.contains("t=" + base64("my title")))
        XCTAssertEqual(restored.tabGroupID, "group-1")
        XCTAssertEqual(restored.tabGroupName, "Group")
        XCTAssertFalse(restored.tabGroupCollapsed)
    }

    func testUnknownKeysAreIgnored() {
        let tab = makeTab()
        tab.setPerTabSettings("zz=whatever&g=\(base64("group-2"))&gn=\(base64("Two"))&qq")
        XCTAssertEqual(tab.tabGroupID, "group-2")
        XCTAssertEqual(tab.tabGroupName, "Two")
    }

    func testSettingWithoutGroupLeavesExistingGroupAlone() {
        // An older version rewrites @per_tab_settings without group keys. Applying
        // that must not ungroup a tab.
        let tab = makeTab()
        tab.tabGroupID = "group-3"
        tab.tabGroupName = "Three"
        tab.setPerTabSettings("t=" + base64("title"))
        XCTAssertEqual(tab.tabGroupID, "group-3")
        XCTAssertEqual(tab.tabGroupName, "Three")
    }
}
