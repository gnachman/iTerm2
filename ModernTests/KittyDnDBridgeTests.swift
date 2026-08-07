//
//  KittyDnDBridgeTests.swift
//  iTerm2 ModernTests
//
//  Phase 4 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. Exercises the ObjC-facing bridge end to end:
//  inbound OSC 72 content -> controller -> report bytes written back.
//
//  Together with KittyDnDParsingTests (raw bytes -> parser -> terminal ->
//  screenDidReceiveKittyDragAndDrop) this covers the full inbound + report chain;
//  the bridge is what PTYSession drives from that delegate callback.
//

import XCTest
import AppKit
@testable import iTerm2SharedARC

@MainActor
final class KittyDnDBridgeTests: XCTestCase {
    // A localhost session (no conductor), with no view (drag-out not exercised).
    private final class FakeDataSource: NSObject, KittyDnDBridgeDataSource {
        var kittyDnDConductor: Conductor? { nil }
        var kittyDnDView: NSView? { nil }
        func kittyDnDDragDidBegin() {}
    }

    private let dataSource = FakeDataSource()

    private func makeBridge(_ reports: @escaping (String) -> Void) -> KittyDnDBridge {
        return KittyDnDBridge(dataSource: dataSource, report: { data in
            reports(String(data: data, encoding: .utf8) ?? "")
        })
    }

    func testQueryRoundTrip() {
        var reports: [String] = []
        let bridge = makeBridge { reports.append($0) }
        bridge.handleInboundSequence("t=q:i=9")
        XCTAssertEqual(reports.count, 1)
        // The reply is a well-formed OSC 72 sequence echoing the query id.
        let reply = reports[0]
        XCTAssertTrue(reply.hasPrefix("\u{1b}]72;"))
        XCTAssertTrue(reply.hasSuffix("\u{1b}\\"))
        XCTAssertTrue(reply.contains("t=q"))
        XCTAssertTrue(reply.contains("i=9"))
    }

    func testAnnounceProducesNoReport() {
        var reports: [String] = []
        let bridge = makeBridge { reports.append($0) }
        bridge.handleInboundSequence("t=a;text/plain text/uri-list")
        XCTAssertTrue(reports.isEmpty)
    }

    // Report bytes must never contain a raw newline (the security invariant),
    // even when the controller answers a query.
    func testReportsContainNoNewlines() {
        var reports: [String] = []
        let bridge = makeBridge { reports.append($0) }
        bridge.handleInboundSequence("t=q")
        for report in reports {
            XCTAssertFalse(report.utf8.contains(0x0a))
            XCTAssertFalse(report.utf8.contains(0x0d))
        }
    }
}
