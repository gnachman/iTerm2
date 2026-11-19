//
//  PTYTabAttentionCandidateTests.swift
//  ModernTests
//
//  A collapsed tab group ranks its members by -[PTYTab attentionCandidate] and
//  then draws the winner's -icon. The two must describe the same thing, or the
//  chip can pick a member for an icon it isn't showing.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYTabAttentionCandidateTests: XCTestCase {
    // From PTYTabDelegate.h.
    private let newOutputState: UInt = 1 << 2

    private var savedShowNewOutput = false
    private var tabViewItems = [NSTabViewItem]()

    override func setUp() {
        super.setUp()
        savedShowNewOutput = iTermPreferences.bool(forKey: kPreferenceKeyShowNewOutputIndicator)
    }

    override func tearDown() {
        iTermPreferences.setBool(savedShowNewOutput, forKey: kPreferenceKeyShowNewOutputIndicator)
        tabViewItems.removeAll()
        super.tearDown()
    }

    private func makeTab() -> PTYTab {
        let session = PTYSession(synthetic: false)!
        session.view = SessionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let tab = PTYTab(session: session, parentWindow: nil)!
        let item = NSTabViewItem(identifier: tab)
        tabViewItems.append(item)
        tab.tabViewItem = item
        return tab
    }

    // -setState:reset: is private to PTYTab. It is how new output reaches a
    // background tab.
    private func setState(_ tab: PTYTab, set: UInt, reset: UInt) {
        typealias SetState = @convention(c) (AnyObject, Selector, UInt, UInt) -> Void
        let selector = NSSelectorFromString("setState:reset:")
        let imp = tab.method(for: selector)
        unsafeBitCast(imp, to: SetState.self)(tab, selector, set, reset)
    }

    func testBellIsReportedWithItsIcon() {
        let tab = makeTab()
        tab.setBell(true)
        XCTAssertNotNil(tab.icon)
        XCTAssertEqual(tab.attentionCandidate.kind, .bell)
    }

    func testNoIndicatorMeansNoIcon() {
        let tab = makeTab()
        XCTAssertNil(tab.icon)
        XCTAssertEqual(tab.attentionCandidate.kind, TabIconKind.none)
    }

    // Turning off the new-output indicator doesn't redraw tabs that already show
    // it, so the tab keeps its new-output icon. The candidate has to keep
    // describing that icon; otherwise a collapsed chip would rank the tab as
    // showing nothing while the expanded tab still shows new output.
    func testCandidateDescribesTheIconShownAfterPreferenceChanges() {
        iTermPreferences.setBool(true, forKey: kPreferenceKeyShowNewOutputIndicator)
        let tab = makeTab()
        setState(tab, set: newOutputState, reset: 0)
        XCTAssertNotNil(tab.icon)
        XCTAssertEqual(tab.attentionCandidate.kind, .newOutput)

        iTermPreferences.setBool(false, forKey: kPreferenceKeyShowNewOutputIndicator)
        XCTAssertNotNil(tab.icon, "precondition: changing the preference does not update existing icons")
        XCTAssertEqual(tab.attentionCandidate.kind, .newOutput)
    }
}
