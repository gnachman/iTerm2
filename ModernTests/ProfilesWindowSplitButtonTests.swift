//
//  ProfilesWindowSplitButtonTests.swift
//  ModernTests
//
//  The Profiles window’s Split Horizontally / Split Vertically buttons became
//  icon-only with no tooltip, and VoiceOver read the SF Symbol names instead of
//  what the buttons do (QA F-227).
//

import AppKit
import XCTest

final class ProfilesWindowSplitButtonTests: XCTestCase {
    private func button(withAction name: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.action == NSSelectorFromString(name) {
            return button
        }
        for subview in view.subviews {
            if let found = button(withAction: name, in: subview) {
                return found
            }
        }
        return nil
    }

    func testSplitButtonsHaveTooltipsAndAccessibilityLabels() throws {
        let controllerClass = try XCTUnwrap(NSClassFromString("iTermProfilesWindowController") as? NSWindowController.Type)
        let controller = controllerClass.init(windowNibName: "ProfilesWindow")
        defer {
            controller.close()
        }
        let contentView = try XCTUnwrap(controller.window?.contentView)

        let horizontal = try XCTUnwrap(button(withAction: "openBookmarkInHorizontalPane:", in: contentView))
        let vertical = try XCTUnwrap(button(withAction: "openBookmarkInVerticalPane:", in: contentView))

        XCTAssertEqual(horizontal.toolTip, "Split Horizontally")
        XCTAssertEqual(horizontal.accessibilityLabel(), "Split Horizontally")
        XCTAssertEqual(vertical.toolTip, "Split Vertically")
        XCTAssertEqual(vertical.accessibilityLabel(), "Split Vertically")
    }

    func testSplitButtonStringsAreTranslated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        let keys = ["ProfilesWindow.SplitHorizontally",
                    "ProfilesWindow.SplitVertically",
                    "ProfilesWindow.SplitHorizontallyInNewWindow",
                    "ProfilesWindow.SplitVerticallyInNewWindow"]
        for key in keys {
            let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
            for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(key) \(language)")
            }
        }
    }
}
