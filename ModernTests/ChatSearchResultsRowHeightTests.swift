//
//  ChatSearchResultsRowHeightTests.swift
//  iTerm2
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

// Typing a query with matches into the AI Chats sidebar search field used to
// crash: the search results table's heightOfRow returned 0 (it measured a
// manually laid out cell's fittingSize), and NSTableView raises when a
// delegate returns a non-positive row height.
@MainActor
final class ChatSearchResultsRowHeightTests: XCTestCase {
    private final class FakeDataSource: ChatSearchResultsDataSource {
        var results: [ChatSearchResult]
        init(results: [ChatSearchResult]) {
            self.results = results
        }
        func chatSearchResultsIterator(query: String) -> AnySequence<ChatSearchResult> {
            return AnySequence(results)
        }
    }

    private func result(_ text: String, author: Participant) -> ChatSearchResult {
        return ChatSearchResult(chatID: "A",
                                message: Message(chatID: "A",
                                                 author: author,
                                                 content: .plainText(text, context: nil),
                                                 sentDate: Date(),
                                                 uniqueID: UUID()))
    }

    private func tableView(_ vc: ChatSearchResultsViewController) throws -> NSTableView {
        let scrollView = try XCTUnwrap(vc.view.subviews.compactMap { $0 as? NSScrollView }.first)
        return try XCTUnwrap(scrollView.documentView as? NSTableView)
    }

    private func makeController(width: CGFloat,
                                results: [ChatSearchResult]) -> (ChatSearchResultsViewController,
                                                                 FakeDataSource,
                                                                 NSWindow) {
        let vc = ChatSearchResultsViewController()
        let dataSource = FakeDataSource(results: results)
        vc.dataSource = dataSource
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        window.contentView = container
        container.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: container.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.layoutSubtreeIfNeeded()
        return (vc, dataSource, window)
    }

    // Each iterate() adds at least one result before its time budget runs
    // out, so one call per result drains the iterator regardless of speed.
    private static func drain(_ vc: ChatSearchResultsViewController, _ dataSource: FakeDataSource) {
        for _ in dataSource.results {
            vc.iterate()
        }
    }

    private func assertValid(_ height: CGFloat,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertTrue(height.isFinite, "height=\(height)", file: file, line: line)
        // A bubble holds at least one line of text plus its insets and padding.
        XCTAssertGreaterThanOrEqual(height, 32, "height=\(height)", file: file, line: line)
        XCTAssertLessThan(height, 10_000, "height=\(height)", file: file, line: line)
    }

    func testMatchingResultGetsValidHeightAndInsertsWithoutRaising() throws {
        for width in [CGFloat(200), 600] {
            let (vc, dataSource, window) = makeController(width: width,
                                                 results: [result("hello zebra secret", author: .user),
                                                           result("a zebra reply", author: .agent)])
            defer { window.close(); withExtendedLifetime(dataSource) {} }
            vc.query = "zebra"
            let error = ObjCTryImpl {
                Self.drain(vc, dataSource)
            }
            XCTAssertNil(error, "width=\(width): \(String(describing: error))")
            let table = try tableView(vc)
            XCTAssertEqual(table.numberOfRows, 2, "width=\(width)")
            for row in 0..<table.numberOfRows {
                assertValid(vc.tableView(table, heightOfRow: row))
            }
            vc.query = ""
        }
    }

    func testLongResultIsTallerThanShortResult() throws {
        // Under the 200 character snippet limit so it is shown whole, but long
        // enough to wrap onto several lines.
        let long = (0..<15).map { _ in "zebra words" }.joined(separator: " ")
        let (vc, dataSource, window) = makeController(width: 250,
                                             results: [result("zebra", author: .agent),
                                                       result(long, author: .agent)])
        defer { window.close(); withExtendedLifetime(dataSource) {} }
        vc.query = "zebra"
        XCTAssertNil(ObjCTryImpl { Self.drain(vc, dataSource) })
        let table = try tableView(vc)
        XCTAssertEqual(table.numberOfRows, 2)
        let short = vc.tableView(table, heightOfRow: 0)
        let tall = vc.tableView(table, heightOfRow: 1)
        assertValid(short)
        assertValid(tall)
        XCTAssertGreaterThan(tall, short)
        vc.query = ""
    }

    func testZeroWidthTableStillGetsValidHeight() throws {
        let (vc, dataSource, window) = makeController(width: 0,
                                             results: [result("hello zebra secret", author: .user)])
        defer { window.close(); withExtendedLifetime(dataSource) {} }
        // The bubble width comes from the column, so make the column empty too.
        let table = try tableView(vc)
        table.tableColumns[0].minWidth = 0
        table.tableColumns[0].width = 0
        vc.query = "zebra"
        XCTAssertNil(ObjCTryImpl { Self.drain(vc, dataSource) })
        XCTAssertEqual(table.tableColumns[0].width, 0)
        XCTAssertEqual(table.numberOfRows, 1)
        assertValid(vc.tableView(table, heightOfRow: 0))
        vc.query = ""
    }
}
