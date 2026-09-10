//
//  PSMTahoeTabStyleLabelTests.swift
//  ModernTests
//
//  A Tahoe tab draws its title inside a pill that is a few points shorter than
//  the cell, and the cell is shorter than the bar by the bar's vertical insets.
//  In a normal macOS 26 window (36pt bar, 8pt bottom inset) the pill is only
//  24pt tall, which cannot hold a title line plus a status subtitle line.
//  These tests pin the rule that the style only claims multi-line labels when
//  the cell is actually tall enough, and that when it is not, the subtitle is
//  drawn inline after the title (in its own status color) rather than as a
//  second, overlapping line.
//

import XCTest
@testable import iTerm2SharedARC

@available(macOS 26, *)
final class PSMTahoeTabStyleLabelTests: XCTestCase {
    private var control: PSMTabBarControl!
    private var style: PSMTahoeTabStyle!
    private var item: NSTabViewItem!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 600, height: 36))
        style = PSMTahoeTabStyle()
        control.style = style
        control.orientation = .horizontalOrientation
        item = NSTabViewItem(identifier: "Tab" as NSString)
    }

    override func tearDown() {
        control = nil
        style = nil
        item = nil
        super.tearDown()
    }

    private func cell(title: String, subtitle: String?) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.representedObject = item
        cell.stringValue = title
        cell.subtitleString = subtitle
        return cell
    }

    // The production layout for a normal macOS 26 window: the system tab bar
    // height with the insets PseudoTerminal applies (top 0, bottom 8).
    private func configureAsNormalWindowTopBar() {
        control.height = PSMTahoeTabStyle.horizontalTabBarHeight
        control.insets = NSEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)
    }

    private func configureAsTallBar() {
        control.height = 60
        control.insets = NSEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)
    }

    func testNormalWindowTopBarIsTooShortForTwoLines() {
        configureAsNormalWindowTopBar()
        XCTAssertFalse(style.supportsMultiLineLabels)
    }

    func testTallBarSupportsTwoLines() {
        configureAsTallBar()
        XCTAssertTrue(style.supportsMultiLineLabels)
    }

    // The status is drawn as its own run so it keeps its color; the title
    // string itself must not absorb it.
    func testShortBarLeavesTitleStringAlone() {
        configureAsNormalWindowTopBar()
        let inputs = style.cachedTitleInputs(forTabCell: cell(title: "Fix (claude)", subtitle: "working"))
        XCTAssertEqual(inputs.title, "Fix (claude)")
    }

    func testTallBarKeepsSubtitleSeparate() {
        configureAsTallBar()
        let inputs = style.cachedTitleInputs(forTabCell: cell(title: "Fix (claude)", subtitle: "working"))
        XCTAssertEqual(inputs.title, "Fix (claude)")
    }

    func testShortBarWithoutSubtitleLeavesTitleAlone() {
        configureAsNormalWindowTopBar()
        let inputs = style.cachedTitleInputs(forTabCell: cell(title: "Fix (claude)", subtitle: nil))
        XCTAssertEqual(inputs.title, "Fix (claude)")
    }

    // The title is nudged up to make room for a subtitle line. On a short bar
    // there is no second line, so the title must stay vertically centered.
    func testShortBarDoesNotOffsetTitleForSubtitle() {
        configureAsNormalWindowTopBar()
        let subtitle = cell(title: "Fix (claude)", subtitle: "working").cachedSubtitle
        XCTAssertFalse(style.willDrawSubtitle(subtitle))
    }

    func testTallBarOffsetsTitleForSubtitle() {
        configureAsTallBar()
        let subtitle = cell(title: "Fix (claude)", subtitle: "working").cachedSubtitle
        XCTAssertTrue(style.willDrawSubtitle(subtitle))
    }
}
