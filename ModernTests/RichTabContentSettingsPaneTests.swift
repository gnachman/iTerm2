//
//  RichTabContentSettingsPaneTests.swift
//  ModernTests
//
//  The “Show rich tab content” checkbox and the button that opens the tab
//  content editor are added to Settings > Profiles > Window in code. Loads
//  the Settings window without showing it.
//

import XCTest
@testable import iTerm2SharedARC

final class RichTabContentSettingsPaneTests: XCTestCase {
    private func windowPane() throws -> NSViewController {
        let panel = try XCTUnwrap(PreferencePanel.sharedInstance())
        _ = panel.window
        let profiles = try XCTUnwrap(panel.value(forKey: "_profilesViewController") as? NSViewController)
        _ = profiles.view
        return try XCTUnwrap(profiles.value(forKey: "_windowViewController") as? NSViewController)
    }

    private func subviews(of view: NSView) -> [NSView] {
        return view.subviews + view.subviews.flatMap { subviews(of: $0) }
    }

    // A control made in code doesn't get the action the xib gives the
    // others, so it has to be set, or clicking it saves nothing.
    func testCheckboxSavesItsSetting() throws {
        let pane = try windowPane()
        let checkbox = try XCTUnwrap(pane.value(forKey: "_showRichTabContent") as? NSButton)
        XCTAssertTrue(subviews(of: pane.view).contains(checkbox), "it's in the pane")
        XCTAssertTrue(checkbox.target === pane)
        XCTAssertEqual(checkbox.action, NSSelectorFromString("settingChanged:"))
    }

    func testButtonIsEnabledOnlyWhileTheCheckboxIsOn() throws {
        let pane = try windowPane()
        let checkbox = try XCTUnwrap(pane.value(forKey: "_showRichTabContent") as? NSButton)
        let button = try XCTUnwrap(pane.value(forKey: "_tabContentButton") as? NSButton)
        XCTAssertTrue(subviews(of: pane.view).contains(button), "it's in the pane")
        XCTAssertEqual(button.isEnabled, checkbox.state == .on)
    }

    // A Set Profile Setting trigger or Toggle Setting action changes only a
    // session's own profile, and a window's rich tab content follows a shared
    // profile, so offering this checkbox there would do nothing.
    func testNotOfferedToActions() throws {
        _ = try windowPane()
        XCTAssertFalse(ProfileBoolSettingCatalog.entries().contains { $0.key == KEY_SHOW_RICH_TAB_CONTENT })
    }

    // Side by side, the button's title sits on the checkbox's baseline.
    func testButtonIsBaselineAlignedWithTheCheckbox() throws {
        let pane = try windowPane()
        let checkbox = try XCTUnwrap(pane.value(forKey: "_showRichTabContent") as? NSButton)
        let button = try XCTUnwrap(pane.value(forKey: "_tabContentButton") as? NSButton)
        try XCTSkipUnless(button.frame.minX > checkbox.frame.maxX, "on two rows in this language")
        // Where the title is drawn. firstBaselineOffsetFromTop doesn't match
        // the drawing for a frame-based push button. This is the formula the
        // pane uses, so it guards the placement, not the formula.
        func baseline(_ button: NSButton) -> CGFloat {
            let titleRect = button.cell!.titleRect(forBounds: button.bounds)
            let top = button.isFlipped ? titleRect.minY : button.bounds.height - titleRect.maxY
            // The section isn't flipped.
            return button.frame.maxY - top - button.font!.ascender
        }
        XCTAssertEqual(baseline(button), baseline(checkbox), accuracy: 0.5)
    }

    // On whole points, so neither draws blurry.
    func testControlsAreOnWholePoints() throws {
        let pane = try windowPane()
        for key in ["_showRichTabContent", "_tabContentButton"] {
            let view = try XCTUnwrap(pane.value(forKey: key) as? NSView)
            XCTAssertEqual(view.frame.minX, view.frame.minX.rounded(), key)
            XCTAssertEqual(view.frame.minY, view.frame.minY.rounded(), key)
        }
    }

    // The button has room around its title, more than the snug fit
    // sizeToFit gives it.
    func testButtonHasRoomAroundItsTitle() throws {
        let pane = try windowPane()
        let button = try XCTUnwrap(pane.value(forKey: "_tabContentButton") as? NSButton)
        // Measured in the same place, since the pane's control metrics apply
        // only inside it.
        let snug = NSButton(title: button.title, target: nil, action: nil)
        button.superview?.addSubview(snug)
        defer { snug.removeFromSuperview() }
        snug.sizeToFit()
        XCTAssertGreaterThanOrEqual(button.frame.width, snug.frame.width + 16)
    }

    // The new row goes right under the window title field, not below the
    // section's bottom padding.
    func testRowIsCloseUnderTheWindowTitle() throws {
        let pane = try windowPane()
        let checkbox = try XCTUnwrap(pane.value(forKey: "_showRichTabContent") as? NSButton)
        let button = try XCTUnwrap(pane.value(forKey: "_tabContentButton") as? NSButton)
        let title = try XCTUnwrap(pane.value(forKey: "_customWindowTitle") as? NSView)
        // The section isn't flipped, so higher on screen is a larger y.
        let rowTop = max(checkbox.frame.maxY, button.frame.maxY)
        let gap = title.frame.minY - rowTop
        XCTAssertGreaterThanOrEqual(gap, 4)
        XCTAssertLessThanOrEqual(gap, 12)
    }

    // The whole row can be scrolled into view: it's inside the scroll view's
    // document view, which Settings may make before the row is added.
    func testRowCanBeScrolledIntoView() throws {
        let pane = try windowPane()
        let button = try XCTUnwrap(pane.value(forKey: "_tabContentButton") as? NSButton)
        let checkbox = try XCTUnwrap(pane.value(forKey: "_showRichTabContent") as? NSButton)
        let document = try XCTUnwrap(pane.view.enclosingScrollView?.documentView, "the Window pane scrolls")
        // Only vertically: the document is narrower than the pane by the
        // scroller's width, which has nothing to do with the row.
        for view in [checkbox, button, pane.view] {
            let frame = view.convert(view.bounds, to: document)
            XCTAssertGreaterThanOrEqual(frame.minY, document.bounds.minY, "\(frame) in \(document.bounds)")
            XCTAssertLessThanOrEqual(frame.maxY, document.bounds.maxY, "\(frame) in \(document.bounds)")
        }
    }

    // Selecting a browser profile and then a terminal profile lays the pane
    // out again from a saved copy of its frames. The row has to be part of
    // that copy, or it ends up on top of the window title field.
    func testRowKeepsItsPlaceAfterSwitchingProfileType() throws {
        let panel = try XCTUnwrap(PreferencePanel.sharedInstance())
        _ = panel.window
        let profiles = try XCTUnwrap(panel.value(forKey: "_profilesViewController") as? NSViewController)
        _ = profiles.view
        let pane = try XCTUnwrap(profiles.value(forKey: "_windowViewController") as? iTermPreferencesBaseViewController)
        let tabView = try XCTUnwrap(profiles.value(forKey: "_tabView") as? NSTabView)
        let item = try XCTUnwrap(tabView.tabViewItems.first { $0.view.map { pane.view.isDescendant(of: $0) } ?? false })
        let checkbox = try XCTUnwrap(pane.value(forKey: "_showRichTabContent") as? NSButton)
        let button = try XCTUnwrap(pane.value(forKey: "_tabContentButton") as? NSButton)
        let title = try XCTUnwrap(pane.value(forKey: "_customWindowTitle") as? NSView)
        let section = try XCTUnwrap(pane.value(forKey: "_settingsForNewWindows") as? NSView)
        let hidden = iTermAdvancedSettingsModel.browserProfiles()
        func layOut(browser: Bool) {
            _ = pane.setVisibility(forTerminalEnclosures: !browser,
                                   browserEnclosures: browser,
                                   hiddenModeEnclosures: hidden,
                                   sharedProfilesEnclosures: true,
                                   tabViewItem: item)
        }
        func check(_ label: String) {
            let rowTop = max(checkbox.frame.maxY, button.frame.maxY)
            let gap = title.frame.minY - rowTop
            XCTAssertGreaterThanOrEqual(gap, 4, label)
            XCTAssertLessThanOrEqual(gap, 12, label)
            XCTAssertGreaterThanOrEqual(min(checkbox.frame.minY, button.frame.minY), 0, label)
            XCTAssertLessThanOrEqual(title.frame.maxY, section.bounds.maxY, label)
        }
        layOut(browser: false)
        check("terminal")
        layOut(browser: true)
        check("browser")
        layOut(browser: false)
        check("terminal again")
    }
}
