//
//  TabContentEvaluatorTests.swift
//  ModernTests
//
//  The evaluator turns a profile's resolved rich tab content lines into the
//  evaluated lines a tab cell draws, and reports when they change.
//

import XCTest
@testable import iTerm2SharedARC

final class TabContentEvaluatorTests: XCTestCase {
    private var session: PTYSession!
    private var evaluator: TabContentEvaluator!
    private var changes = 0

    override func setUp() {
        super.setUp()
        session = PTYSession(synthetic: false)!
        changes = 0
        evaluator = TabContentEvaluator(scope: session.genericScope) { [weak self] in
            self?.changes += 1
        }
    }

    override func tearDown() {
        evaluator.invalidate()
        evaluator = nil
        session = nil
        super.tearDown()
    }

    private func line(_ id: String,
                      _ format: String,
                      size: TabContentLineSize = .small,
                      configure: (inout TabContentLineStyle) -> Void = { _ in }) -> ResolvedTabContentLine {
        var style = TabContentLineStyle.userAddedDefault
        style.text = format
        configure(&style)
        return ResolvedTabContentLine(slotIdentifier: id, size: size, format: format, style: style)
    }

    private func waitForTexts(_ expected: [String],
                              file: StaticString = #filePath,
                              line: UInt = #line) {
        // Often already there: update(lines:) publishes what it can at once.
        // A predicate expectation is polled, which can take seconds on a
        // loaded machine, so don't start one needlessly.
        guard evaluator.richLines.map(\.text) != expected else {
            return
        }
        let predicate = NSPredicate { [unowned self] _, _ in
            self.evaluator.richLines.map(\.text) == expected
        }
        let done = expectation(for: predicate, evaluatedWith: nil)
        // Generous, so a slow machine doesn't fail the test.
        wait(for: [done], timeout: 30)
        XCTAssertEqual(evaluator.richLines.map(\.text), expected, file: file, line: line)
    }

    func testEvaluatesEachLineInTheSessionScope() {
        session.genericScope.setValue("/tmp/project", forVariableNamed: iTermVariableKeySessionPath)
        evaluator.update(lines: [line("a", "plain"), line("b", "\\(path)")])
        waitForTexts(["plain", "/tmp/project"])
    }

    func testCarriesStyleToTheRichLine() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        evaluator.update(lines: [line("a", "x", size: .large) { style in
            style.bold = true
            style.italic = true
            style.color = red
            style.secondary = false
            style.truncation = .middle
            style.collapsesWhenEmpty = false
        }])
        waitForTexts(["x"])
        let rich = evaluator.richLines[0]
        XCTAssertEqual(rich.scale, TabContentLineSize.large.scale)
        XCTAssertTrue(rich.bold)
        XCTAssertTrue(rich.italic)
        XCTAssertEqual(rich.color, red)
        XCTAssertFalse(rich.secondary)
        XCTAssertEqual(rich.lineBreakMode, .byTruncatingMiddle)
        XCTAssertFalse(rich.collapsesWhenEmpty)
    }

    func testVariableChangeUpdatesLineAndReportsChange() {
        session.genericScope.setValue("/one", forVariableNamed: iTermVariableKeySessionPath)
        evaluator.update(lines: [line("a", "\\(path)")])
        waitForTexts(["/one"])
        let before = changes
        session.genericScope.setValue("/two", forVariableNamed: iTermVariableKeySessionPath)
        waitForTexts(["/two"])
        XCTAssertGreaterThan(changes, before)
    }

    // Changing the configuration replaces the lines, dropping slots that are
    // no longer in it.
    func testUpdateReplacesLines() {
        evaluator.update(lines: [line("a", "first"), line("b", "second")])
        waitForTexts(["first", "second"])
        evaluator.update(lines: [line("b", "changed")])
        waitForTexts(["changed"])
    }

    func testUpdateReportsChange() {
        evaluator.update(lines: [line("a", "first")])
        waitForTexts(["first"])
        let before = changes
        evaluator.update(lines: [line("a", "first") { $0.bold = true }])
        XCTAssertGreaterThan(changes, before, "a style-only change must still redraw the tab")
    }

    // Lets anything already queued on the main queue run, such as the
    // evaluator's coalesced refresh.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                drained.fulfill()
            }
        }
        wait(for: [drained], timeout: 5)
    }

    // Reloading a profile rebuilds the lines. When nothing visible changed,
    // the tab bar shouldn't relayout.
    func testUpdateWithSameLinesDoesNotReportChange() {
        session.genericScope.setValue("/one", forVariableNamed: iTermVariableKeySessionPath)
        evaluator.update(lines: [line("a", "\\(path)"), line("b", "x")])
        waitForTexts(["/one", "x"])
        drainMainQueue()
        let before = changes
        evaluator.update(lines: [line("a", "\\(path)"), line("b", "x")])
        drainMainQueue()
        XCTAssertEqual(changes, before)
    }

    // A line with several segments that depend on one variable reports one
    // change, not one per segment.
    func testSegmentsChangingTogetherReportOnce() {
        session.genericScope.setValue("/one", forVariableNamed: iTermVariableKeySessionPath)
        evaluator.update(lines: [line("a", "\\(path) \\(path) \\(path)")])
        waitForTexts(["/one /one /one"])
        drainMainQueue()
        let before = changes
        session.genericScope.setValue("/two", forVariableNamed: iTermVariableKeySessionPath)
        waitForTexts(["/two /two /two"])
        drainMainQueue()
        XCTAssertEqual(changes, before + 1)
    }

    // Tab styles ask for the lines whenever they measure or draw a tab, so
    // they're built once per change, not per call.
    func testRichLinesAreReusedUntilSomethingChanges() {
        evaluator.update(lines: [line("a", "x")])
        waitForTexts(["x"])
        XCTAssertTrue(evaluator.richLines[0] === evaluator.richLines[0])
    }

    // A line is drawn on a single line, so a value with newlines is
    // flattened rather than showing only its first line.
    func testNewlinesAreFlattened() {
        session.genericScope.setValue("one\ntwo", forVariableNamed: "user.multiline")
        evaluator.update(lines: [line("a", "\\(user.multiline)")])
        waitForTexts(["one two"])
    }

    // A collapsed group combines jobs and statuses separately from the rest
    // of the line, so the evaluator keeps each segment's value.
    func testSnapshotKeepsSegments() {
        session.genericScope.setValue("/p", forVariableNamed: iTermVariableKeySessionPath)
        evaluator.update(lines: [line("a", "in \\(path)!")])
        waitForTexts(["in /p!"])
        let values = evaluator.snapshot.lines[0].values
        XCTAssertEqual(values.map(\.kind), [.literal, .other, .literal])
        XCTAssertEqual(values.map(\.text), ["in ", "/p", "!"])
    }

    // A program's status detail is a session variable, so the Status Detail
    // line can show it, and it goes away with the status.
    func testStatusDetailIsASessionVariable() {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "Working"
        update.detailPresence = .set
        update.detail = "Reading files\nthen writing"
        session.perform(NSSelectorFromString("screenSetTabStatus:"), with: update)
        XCTAssertEqual(session.genericScope.value(forVariableName: "statusDetail") as? String,
                       "Reading files\nthen writing")
        session.perform(NSSelectorFromString("clearTabStatus"))
        XCTAssertNil(session.genericScope.value(forVariableName: "statusDetail"))
    }

    // The color a program gives its status text is a session variable, as
    // #rrggbb, so an HTML line can show the status in it. It goes away with
    // the status, and is absent when the program gave no color.
    func testStatusColorIsASessionVariable() {
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "Working"
        update.statusColorPresence = .set
        update.statusColor = iTermSRGBColor(r: 1, g: 0.5, b: 0)
        session.perform(NSSelectorFromString("screenSetTabStatus:"), with: update)
        XCTAssertEqual((session.genericScope.value(forVariableName: "statusColor") as? String)?.lowercased(), "#ff8000")
        session.perform(NSSelectorFromString("clearTabStatus"))
        XCTAssertNil(session.genericScope.value(forVariableName: "statusColor"))

        let uncolored = VT100TabStatusUpdate()
        uncolored.statusPresence = .set
        uncolored.status = "Working"
        session.perform(NSSelectorFromString("screenSetTabStatus:"), with: uncolored)
        XCTAssertNil(session.genericScope.value(forVariableName: "statusColor"))
    }

    // A program can report detail without status text. Clearing the status
    // must clear that too, or the Status Detail line shows it forever.
    func testClearingRemovesADetailThatHasNoStatusText() {
        let update = VT100TabStatusUpdate()
        update.detailPresence = .set
        update.detail = "Reading files"
        session.perform(NSSelectorFromString("screenSetTabStatus:"), with: update)
        XCTAssertEqual(session.genericScope.value(forVariableName: "statusDetail") as? String, "Reading files")
        session.perform(NSSelectorFromString("clearTabStatus"))
        XCTAssertNil(session.genericScope.value(forVariableName: "statusDetail"))
        XCTAssertNil(session.tabStatus?.detailText)
    }
}
