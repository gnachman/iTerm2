//
//  AutoresizingFloorAuditorTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class AutoresizingFloorAuditorTests: XCTestCase {
    private let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))

    private func add(_ frame: NSRect, _ mask: NSView.AutoresizingMask, to parent: NSView? = nil, hidden: Bool = false) -> NSView {
        let view = NSView(frame: frame)
        view.autoresizingMask = mask
        view.isHidden = hidden
        (parent ?? root).addSubview(view)
        return view
    }

    private func violations() -> [String] {
        return AutoresizingFloorAuditor.violations(in: root, threshold: 1)
    }

    func testEmptyViewHasNoFloor() {
        XCTAssertEqual(violations(), [])
    }

    // A hidden view left with a zero frame and a flexible width: its fixed
    // right margin is the whole width.
    func testStaleHiddenViewWithFlexibleWidth() {
        _ = add(.zero, [.width], hidden: true)
        let result = violations()
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.hasPrefix("Width floor of 800.0") == true, result.description)
    }

    func testFlexibleHeight() {
        _ = add(NSRect(x: 0, y: 0, width: 800, height: 100), [.height])
        let result = violations()
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.hasPrefix("Height floor of 400.0") == true, result.description)
    }

    func testViewSpanningItsSuperviewHasNoFloor() {
        _ = add(root.bounds, [.width, .height])
        XCTAssertEqual(violations(), [])
    }

    func testFixedSizeViewHasNoFloor() {
        _ = add(NSRect(x: 100, y: 100, width: 10, height: 10), [])
        _ = add(NSRect(x: 100, y: 100, width: 10, height: 10), [.minXMargin, .maxYMargin])
        XCTAssertEqual(violations(), [])
    }

    // Flexible margins translate into proportional constraints.
    func testFlexibleMarginsHaveNoFloor() {
        _ = add(NSRect(x: 130, y: 0, width: 540, height: 20), [.minXMargin, .width, .maxXMargin])
        XCTAssertEqual(violations(), [])
    }

    func testOneFlexibleMarginCountsTheOther() {
        _ = add(NSRect(x: 0, y: 0, width: 550, height: 20), [.width, .minXMargin])
        let result = violations()
        XCTAssertTrue(result.first?.hasPrefix("Width floor of 250.0") == true, result.description)
    }

    // Floors add up through a chain of flexible views.
    func testNestedFloorsAddUp() {
        let outer = add(NSRect(x: 10, y: 0, width: 780, height: 500), [.width, .height])
        _ = add(NSRect(x: 20, y: 0, width: 740, height: 500), [.width, .height], to: outer)
        let result = violations()
        XCTAssertTrue(result.first?.hasPrefix("Width floor of 60.0") == true, result.description)
    }

    // A fixed-size view stops a floor from reaching further up.
    func testFixedSizeAncestorContainsAFloor() {
        let container = add(NSRect(x: 0, y: 0, width: 300, height: 300), [])
        _ = add(.zero, [.width, .height], to: container)
        XCTAssertEqual(violations(), [])
    }

    // A view wider than its superview has negative margins.
    func testOversizedViewHasNoFloor() {
        _ = add(NSRect(x: 0, y: 0, width: 1000, height: 20), [.width])
        XCTAssertEqual(violations(), [])
    }

    func testViewsThatUseConstraintsAreSkipped() {
        let view = add(.zero, [.width])
        view.translatesAutoresizingMaskIntoConstraints = false
        XCTAssertEqual(violations(), [])
    }

    func testCulpritIsNamed() {
        let container = add(NSRect(x: 0, y: 0, width: 800, height: 500), [.width, .height])
        _ = add(NSRect(x: 0, y: 0, width: 500, height: 20), [.width], to: container, hidden: true)
        let result = violations().first ?? ""
        XCTAssertTrue(result.contains("margins=300.0"), result)
        XCTAssertTrue(result.contains("hidden=true"), result)
    }

    // MARK: - Reporting

    private var reports = [String]()

    private func startRecording() {
        AutoresizingFloorAuditor.violationHandler = { [weak self] in self?.reports.append($0) }
        addTeardownBlock {
            AutoresizingFloorAuditor.violationHandler = nil
        }
    }

    // A floor that persists while the window resizes is the same problem, even
    // though its size and the frames involved change.
    func testPersistentFloorIsReportedOnceAcrossResizes() {
        startRecording()
        let stale = add(.zero, [.width], hidden: true)
        AutoresizingFloorAuditor.check(rootView: root)
        XCTAssertEqual(reports.count, 1)
        for width in [900, 1000, 1100, 700] as [CGFloat] {
            root.setFrameSize(NSSize(width: width, height: 500))
            stale.frame = .zero
            AutoresizingFloorAuditor.check(rootView: root)
        }
        XCTAssertEqual(reports.count, 1, reports.description)
    }

    func testFloorIsReportedAgainAfterItGoesAway() {
        startRecording()
        let stale = add(.zero, [.width], hidden: true)
        AutoresizingFloorAuditor.check(rootView: root)
        stale.frame = root.bounds
        AutoresizingFloorAuditor.check(rootView: root)
        stale.frame = .zero
        AutoresizingFloorAuditor.check(rootView: root)
        XCTAssertEqual(reports.count, 2, reports.description)
    }

    func testDifferentCulpritIsReportedSeparately() {
        startRecording()
        let first = add(.zero, [.width], hidden: true)
        AutoresizingFloorAuditor.check(rootView: root)
        first.frame = root.bounds
        _ = add(.zero, [.width], hidden: true)
        AutoresizingFloorAuditor.check(rootView: root)
        XCTAssertEqual(reports.count, 2, reports.description)
    }

    func testEachWindowIsTrackedSeparately() {
        startRecording()
        let otherRoot = NSView(frame: root.frame)
        _ = add(.zero, [.width], hidden: true)
        let other = NSView(frame: .zero)
        other.autoresizingMask = [.width]
        otherRoot.addSubview(other)
        AutoresizingFloorAuditor.check(rootView: root)
        AutoresizingFloorAuditor.check(rootView: otherRoot)
        AutoresizingFloorAuditor.check(rootView: root)
        XCTAssertEqual(reports.count, 2, reports.description)
    }
}
