//
//  AnnouncementViewLayoutTests.swift
//  ModernTests
//
//  An announcement's text sits between its icon and its buttons. In a narrow pane (e.g. a split
//  of a workgroup) the buttons left the text a sliver, so it wrapped a letter per line and was
//  cut off. When the text would be too narrow, the buttons go on a row of their own beneath it.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class AnnouncementViewLayoutTests: XCTestCase {
    private let title = "Close tmux windows after detaching?"

    private func makeView() -> iTermAnnouncementView {
        return iTermAnnouncementView(title: title,
                                     style: .kiTermAnnouncementViewStyleQuestion,
                                     actions: ["_Always", "_Never"],
                                     block: { _ in })
    }

    /// Sizes the view to `width` as SessionView does, then reports where the text and buttons are.
    private func layOut(_ view: iTermAnnouncementView, width: CGFloat) throws -> (view: iTermAnnouncementView, text: NSRect, buttons: [NSRect]) {
        view.frame = NSRect(x: 0, y: 0, width: width, height: view.frame.height)
        view.sizeToFit()
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        let views = all(view)
        let text = try XCTUnwrap(views.first { $0 is NSTextView })
        let buttons = views.compactMap { $0 as? NSButton }.filter { $0.action == NSSelectorFromString("buttonPressed:") }
        XCTAssertEqual(buttons.count, 2)
        return (view, view.convert(text.frame, from: text.superview),
                buttons.map { view.convert($0.frame, from: $0.superview) })
    }

    private func layOut(width: CGFloat) throws -> (view: iTermAnnouncementView, text: NSRect, buttons: [NSRect]) {
        return try layOut(makeView(), width: width)
    }

    private func assertLegible(_ layout: (view: iTermAnnouncementView, text: NSRect, buttons: [NSRect]),
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(layout.text.width, 150, "room for words, not letters", file: file, line: line)
        let attributes: [NSAttributedString.Key: Any] = [.font: iTermAnnouncementView.announcementFont()]
        let needed = (title as NSString).boundingRect(with: NSSize(width: layout.text.width, height: .greatestFiniteMagnitude),
                                                      options: [.usesLineFragmentOrigin],
                                                      attributes: attributes).height
        XCTAssertGreaterThanOrEqual(layout.text.height + 1, needed, "the whole title fits", file: file, line: line)
        for button in layout.buttons {
            XCTAssertFalse(button.intersects(layout.text), "a button covers the text", file: file, line: line)
            XCTAssertTrue(layout.view.bounds.contains(button), "a button is cut off: \(button)", file: file, line: line)
        }
        XCTAssertTrue(layout.view.bounds.contains(layout.text), file: file, line: line)
    }

    // The width of a pane in a three-way split.
    func testANarrowAnnouncementPutsItsButtonsBelowTheText() throws {
        let layout = try layOut(width: 290)
        assertLegible(layout)
        for button in layout.buttons {
            XCTAssertLessThan(button.maxY, layout.text.minY, "beneath the text")
        }
    }

    func testAWideAnnouncementKeepsOneRow() throws {
        let layout = try layOut(width: 1000)
        assertLegible(layout)
        for button in layout.buttons {
            XCTAssertGreaterThan(button.minX, layout.text.minX, "beside the text")
            XCTAssertEqual(button.midY, layout.text.midY, accuracy: 2)
        }
    }

    // Growing back out of a narrow pane goes back to one row.
    func testWideningRestoresOneRow() throws {
        let view = makeView()
        _ = try layOut(view, width: 290)
        let layout = try layOut(view, width: 1000)
        assertLegible(layout)
        for button in layout.buttons {
            XCTAssertEqual(button.midY, layout.text.midY, accuracy: 2)
        }
        XCTAssertEqual(view.frame.height, try layOut(width: 1000).view.frame.height)
    }
}
