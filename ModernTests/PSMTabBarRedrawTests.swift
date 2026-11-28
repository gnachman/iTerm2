//
//  PSMTabBarRedrawTests.swift
//  ModernTests
//
//  A change that shows only in one tab must not lay out and redraw the whole tab bar, because
//  programs that animate their titles make it frequent.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabBarRedrawTests: XCTestCase {
    private var savedTabPosition = Int32(0)
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        savedTabPosition = iTermPreferences.int(forKey: kPreferenceKeyTabPosition)
        iTermPreferences.setInt(2 /* PSMTab_LeftTab */, forKey: kPreferenceKeyTabPosition)
        fixture = TerminalWindowTestFixture()
        _ = fixture.addTab()
        _ = fixture.addTab()
    }

    override func tearDown() {
        fixture.close()
        fixture = nil
        iTermPreferences.setInt(savedTabPosition, forKey: kPreferenceKeyTabPosition)
        super.tearDown()
    }

    private func findTabBar(in view: NSView) -> PSMTabBarControl? {
        if let bar = view as? PSMTabBarControl {
            return bar
        }
        return view.subviews.lazy.compactMap { self.findTabBar(in: $0) }.first
    }

    private func tabBar() throws -> PSMTabBarControl {
        let frameView = try XCTUnwrap(fixture.window.contentView?.superview)
        let bar = try XCTUnwrap(findTabBar(in: frameView))
        fixture.window.layoutIfNeeded()
        return bar
    }

    // PSMTabBarControl's conformance is private.
    private func layoutDependsOnContents(of cell: PSMTabBarCell, in bar: PSMTabBarControl) throws -> Bool {
        return try XCTUnwrap(bar as Any as? PSMTabBarControlProtocol).layoutDepends(onContentsOf: cell)
    }

    func testContentsOfAVisibleTabDoNotAffectLayoutOfAVerticalBar() throws {
        let bar = try tabBar()
        let cells = try XCTUnwrap(bar.cells() as? [PSMTabBarCell])
        XCTAssertEqual(cells.count, 3)
        for cell in cells {
            XCTAssertFalse(try layoutDependsOnContents(of: cell, in: bar))
        }
    }

    func testContentsOfATabShownElsewhereAffectLayout() throws {
        let bar = try tabBar()
        let cell = try XCTUnwrap((bar.cells() as? [PSMTabBarCell])?.last)

        cell.isInOverflowMenu = true
        XCTAssertTrue(try layoutDependsOnContents(of: cell, in: bar))
        cell.isInOverflowMenu = false

        cell.isCollapsedHidden = true
        XCTAssertTrue(try layoutDependsOnContents(of: cell, in: bar))
        cell.isCollapsedHidden = false

        cell.frame = .zero
        XCTAssertTrue(try layoutDependsOnContents(of: cell, in: bar))
    }
}
