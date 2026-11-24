//
//  PSMTabRichColorAppearanceTests.swift
//  ModernTests
//
//  A rich line can have a color for light bars and another for dark ones.
//  When a tab color fills the space behind the text, the tab color's
//  lightness picks which one, not the bar's.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabRichColorAppearanceTests: XCTestCase {
    private var control: PSMTabBarControl!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    private func cell(tabColor: NSColor?, selected: Bool, style: PSMTabStyle) -> PSMTabBarCell {
        control.style = style
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabColor = tabColor
        cell.state = selected ? .on : .off
        control.cells().setArray([cell])
        return cell
    }

    private func isDark(_ appearance: NSAppearance?) -> Bool? {
        return appearance.map { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    }

    // MARK: - Yosemite family: the tab color fills the cell

    func testAnUnselectedDarkTabColorOnALightBarUsesTheDarkValue() {
        let style = PSMYosemiteTabStyle()
        let c = cell(tabColor: NSColor(srgbRed: 0, green: 0, blue: 0.4, alpha: 1), selected: false, style: style)
        XCTAssertEqual(isDark(style.richLineColorAppearance(for: c)), true)
    }

    func testADarkTabColorOnALightBarUsesTheDarkValue() {
        let style = PSMYosemiteTabStyle()
        let c = cell(tabColor: NSColor(srgbRed: 0, green: 0, blue: 0.4, alpha: 1), selected: true, style: style)
        XCTAssertEqual(isDark(style.richLineColorAppearance(for: c)), true)
    }

    func testWithoutATabColorTheBarDecides() {
        let style = PSMMinimalTabStyle()
        let c = cell(tabColor: nil, selected: true, style: style)
        XCTAssertEqual(style.richLineColorAppearance(for: c)?.name, style.accessoryAppearance?.name)
    }

    // MARK: - Tahoe: only the selected tab is filled

    func testTahoeSelectedLightTabColorOnADarkBarUsesTheLightValue() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        let style = PSMTahoeDarkTabStyle()
        let c = cell(tabColor: .yellow, selected: true, style: style)
        XCTAssertEqual(isDark(style.richLineColorAppearance(for: c)), false)
    }

    // An unselected Tahoe tab shows its color as a border and a faint tint,
    // so its text is on the bar.
    func testTahoeUnselectedColoredTabUsesTheBar() throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Tahoe style needs macOS 26")
        }
        for style in [PSMTahoeTabStyle(), PSMTahoeDarkTabStyle(), PSMTahoeDarkHighContrastTabStyle(), PSMTahoeLightHighContrastTabStyle()] {
            let c = cell(tabColor: .yellow, selected: false, style: style)
            XCTAssertTrue(style.richLineColorAppearance(for: c) === style.accessoryAppearance, "\(style)")
        }
    }

    // MARK: - The decision from a text color

    func testTextColorDecidesOverAColor() {
        XCTAssertEqual(isDark(PSMTabRichContentRenderer.colorAppearance(contrastingWith: .black)), false)
        XCTAssertEqual(isDark(PSMTabRichContentRenderer.colorAppearance(contrastingWith: .white)), true)
        XCTAssertEqual(isDark(PSMTabRichContentRenderer.colorAppearance(contrastingWith: NSColor.white.withAlphaComponent(0.8))), true)
        XCTAssertEqual(isDark(PSMTabRichContentRenderer.colorAppearance(contrastingWith: NSColor(white: 0.1, alpha: 1))), false)
    }
}
