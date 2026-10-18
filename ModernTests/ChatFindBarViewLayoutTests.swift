//
//  ChatFindBarViewLayoutTests.swift
//  iTerm2
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

// The AI chat find bar must keep its search field usable when the bar is
// narrow (the inline chat, or a small chat window with its sidebar shown).
@MainActor
final class ChatFindBarViewLayoutTests: XCTestCase {
    private func layOut(width: CGFloat, query: String = "two") -> ChatFindBarView {
        let bar = ChatFindBarView(frame: NSRect(x: 0, y: 0, width: width, height: ChatFindBarView.barHeight))
        bar.query = query
        bar.updateResults(current: nil, total: 0)
        bar.layoutSubtreeIfNeeded()
        bar.layout()
        return bar
    }

    private func searchField(_ bar: ChatFindBarView) throws -> NSSearchField {
        return try XCTUnwrap(bar.subviews.compactMap { $0 as? NSSearchField }.first)
    }

    private func modePopup(_ bar: ChatFindBarView) throws -> NSPopUpButton {
        return try XCTUnwrap(bar.subviews.compactMap { $0 as? NSPopUpButton }.first)
    }

    private func assertVisibleControlsFitWithoutOverlap(_ bar: ChatFindBarView,
                                                        file: StaticString = #filePath,
                                                        line: UInt = #line) {
        let visible = bar.subviews.filter { !$0.isHidden && !($0 is NSVisualEffectView) }
        for view in visible {
            XCTAssertGreaterThanOrEqual(view.frame.minX, 0, "\(view)", file: file, line: line)
            XCTAssertLessThanOrEqual(view.frame.maxX, bar.bounds.maxX, "\(view)", file: file, line: line)
        }
        for (i, a) in visible.enumerated() {
            for b in visible[(i + 1)...] {
                XCTAssertFalse(a.frame.intersects(b.frame), "\(a) overlaps \(b)", file: file, line: line)
            }
        }
    }

    func testWideBarShowsEverything() throws {
        let bar = layOut(width: 800)
        XCTAssertFalse(try modePopup(bar).isHidden)
        XCTAssertGreaterThanOrEqual(try searchField(bar).frame.width, ChatFindBarView.minimumSearchFieldWidth)
        assertVisibleControlsFitWithoutOverlap(bar)
    }

    // The inline chat is 400pt wide.
    func testInlineChatWidthKeepsSearchFieldReadable() throws {
        let bar = layOut(width: 400)
        XCTAssertGreaterThanOrEqual(try searchField(bar).frame.width, ChatFindBarView.minimumSearchFieldWidth)
        assertVisibleControlsFitWithoutOverlap(bar)
    }

    // A minimum-size chat window with its sidebar shown leaves very little room.
    func testVeryNarrowBarKeepsSearchFieldAndChevrons() throws {
        let bar = layOut(width: 220)
        XCTAssertGreaterThanOrEqual(try searchField(bar).frame.width, 60)
        let buttons = bar.subviews.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }
        XCTAssertEqual(buttons.count, 3)
        for button in buttons {
            XCTAssertFalse(button.isHidden)
            XCTAssertGreaterThan(button.frame.width, 0)
        }
        assertVisibleControlsFitWithoutOverlap(bar)
    }

    // The chat window's content pane can't get narrower than this, so the find
    // bar it holds (inset by its side margins) keeps a readable search field
    // and both chevrons even with the sidebar shown at the window's minimum.
    func testMinimumChatContentWidthKeepsSearchFieldReadable() throws {
        let width = ChatSplitViewController.minimumContentWidth - ChatViewController.findBarSideMargin * 2
        let bar = layOut(width: width)
        XCTAssertGreaterThanOrEqual(try searchField(bar).frame.width, ChatFindBarView.minimumSearchFieldWidth)
        let buttons = bar.subviews.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }
        XCTAssertEqual(buttons.count, 3)
        for button in buttons {
            XCTAssertFalse(button.isHidden)
            XCTAssertGreaterThan(button.frame.width, 0)
        }
        assertVisibleControlsFitWithoutOverlap(bar)

        let item = NSSplitViewItem(viewController: NSViewController())
        ChatSplitViewController.configureContentItem(item)
        XCTAssertEqual(item.minimumThickness, ChatSplitViewController.minimumContentWidth)
    }

    // The popup must not come and go as the counter text changes while typing,
    // even when the counter is long (as in some languages).
    func testModePopupVisibilityDoesNotDependOnCounterText() throws {
        for width in stride(from: CGFloat(300), through: 800, by: 10) {
            let empty = layOut(width: width, query: "")
            let typed = layOut(width: width, query: "two")
            let longCounter = layOut(width: width, query: "two")
            longCounter.updateResults(current: 122, total: 4567)
            longCounter.layout()
            XCTAssertEqual(try modePopup(empty).isHidden, try modePopup(typed).isHidden, "width \(width)")
            XCTAssertEqual(try modePopup(empty).isHidden, try modePopup(longCounter).isHidden, "width \(width)")
        }
    }

    // When the popup is hidden the modes are still in the search field's menu.
    func testModesAreOfferedInSearchFieldMenu() throws {
        let bar = layOut(width: 400)
        XCTAssertTrue(try modePopup(bar).isHidden)
        let menu = try XCTUnwrap(try searchField(bar).searchMenuTemplate)
        XCTAssertEqual(menu.items.count, 4)
        XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.tag), [0])

        let item = menu.items[3]
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
        XCTAssertEqual(bar.mode, .caseInsensitiveRegex)
        let updated = try XCTUnwrap(try searchField(bar).searchMenuTemplate)
        XCTAssertEqual(updated.items.filter { $0.state == .on }.map(\.tag), [3])
    }
}
