//
//  StatusColorOverrideTests.swift
//  ModernTests
//
//  Each status priority entry can override the dot and text colors of the statuses it matches
//  (issue 13130). Overrides change only how a status is drawn, never what is stored for it.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class StatusColorOverrideTests: XCTestCase {
    private var savedEntries: [StatusPriorityEntry] = []

    override func setUp() {
        super.setUp()
        savedEntries = StatusPrioritySettings.shared.entries
    }

    override func tearDown() {
        StatusPrioritySettings.shared.restoreEntries(savedEntries)
        super.tearDown()
    }

    private func color(_ hex: UInt32) -> iTermSRGBColor {
        return iTermSRGBColor(r: Double((hex >> 16) & 0xff) / 255.0,
                              g: Double((hex >> 8) & 0xff) / 255.0,
                              b: Double(hex & 0xff) / 255.0)
    }

    private func status(text: String, dot: UInt32, textColor: UInt32) -> iTermSessionTabStatus {
        let status = iTermSessionTabStatus(sessionID: "test")
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = text
        update.indicatorPresence = .set
        update.indicator = color(dot)
        update.statusColorPresence = .set
        update.statusColor = color(textColor)
        _ = status.apply(update)
        return status
    }

    func testHexRoundTrip() {
        XCTAssertEqual(StatusPrioritySettings.srgbColor(hex: "#ff9500"), color(0xff9500))
        XCTAssertNil(StatusPrioritySettings.srgbColor(hex: "ff9500"))
        XCTAssertNil(StatusPrioritySettings.srgbColor(hex: "#ff95"))
        XCTAssertNil(StatusPrioritySettings.srgbColor(hex: "#gg9500"))
        let nsColor = NSColor(srgbRed: 1, green: 0x95 / 255.0, blue: 0, alpha: 1)
        XCTAssertEqual(StatusPrioritySettings.hexString(nsColor), "#ff9500")
        XCTAssertNil(StatusPrioritySettings.hexString(nil))
    }

    func testNoOverrideDrawsTheProgramsColors() {
        StatusPrioritySettings.shared.restoreEntries([StatusPriorityEntry(pattern: "work")])
        let status = status(text: "working", dot: 0xff9500, textColor: 0x888888)
        XCTAssertEqual(status.displayIndicatorColor, color(0xff9500))
        XCTAssertEqual(status.displayStatusTextColor, color(0x888888))
    }

    func testOverrideReplacesDisplayColorsButNotStoredOnes() {
        StatusPrioritySettings.shared.restoreEntries([
            StatusPriorityEntry(pattern: "wait", dotColor: "#ff0000", textColor: "#00ff00")
        ])
        let status = status(text: "Waiting", dot: 0x5f87ff, textColor: 0x5f87ff)
        XCTAssertEqual(status.displayIndicatorColor, color(0xff0000))
        XCTAssertEqual(status.displayStatusTextColor, color(0x00ff00))
        XCTAssertEqual(status.indicatorColor, color(0x5f87ff))
        XCTAssertEqual(status.statusTextColor, color(0x5f87ff))
    }

    func testDotAndTextAreIndependent() {
        StatusPrioritySettings.shared.restoreEntries([
            StatusPriorityEntry(pattern: "idle", dotColor: "#ffff00")
        ])
        let status = status(text: "idle", dot: 0x00d75f, textColor: 0x888888)
        XCTAssertEqual(status.displayIndicatorColor, color(0xffff00))
        XCTAssertEqual(status.displayStatusTextColor, color(0x888888))
    }

    // Only the first matching entry counts, the same entry that sets the
    // status’s priority.
    func testFirstMatchingEntryWinsEvenWithoutAColor() {
        StatusPrioritySettings.shared.restoreEntries([
            StatusPriorityEntry(pattern: "working"),
            StatusPriorityEntry(pattern: "work", dotColor: "#ff0000", textColor: "#ff0000")
        ])
        let status = status(text: "working", dot: 0xff9500, textColor: 0xff9500)
        XCTAssertEqual(status.displayIndicatorColor, color(0xff9500))
        XCTAssertEqual(status.displayStatusTextColor, color(0xff9500))
    }

    func testEmptyPatternMatchesNothing() {
        StatusPrioritySettings.shared.restoreEntries([
            StatusPriorityEntry(pattern: "", dotColor: "#ff0000")
        ])
        let status = status(text: "working", dot: 0xff9500, textColor: 0xff9500)
        XCTAssertEqual(status.displayIndicatorColor, color(0xff9500))
    }

    func testSettersSaveAndClear() {
        let settings = StatusPrioritySettings.shared
        settings.restoreEntries([StatusPriorityEntry(pattern: "work")])
        settings.setDotColor("#00ff00", at: 0)
        settings.setTextColor("#0000ff", at: 0)
        XCTAssertEqual(settings.dotColorOverride(for: "working"), color(0x00ff00))
        XCTAssertEqual(settings.textColorOverride(for: "working"), color(0x0000ff))
        settings.setDotColor(nil, at: 0)
        XCTAssertNil(settings.dotColorOverride(for: "working"))
        XCTAssertEqual(settings.textColorOverride(for: "working"), color(0x0000ff))
    }

    // Status text is always drawn, so a text override applies even when the
    // program (say, a trigger) sent only text. The dot is not invented.
    func testTextOverrideAppliesWhenTheProgramSentNoTextColor() {
        StatusPrioritySettings.shared.restoreEntries([
            StatusPriorityEntry(pattern: "wait", dotColor: "#00ff00", textColor: "#ff0000")
        ])
        let status = iTermSessionTabStatus(sessionID: "test")
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "Waiting"
        _ = status.apply(update)
        XCTAssertFalse(status.hasStatusTextColor)
        XCTAssertTrue(status.hasDisplayStatusTextColor)
        XCTAssertEqual(status.displayStatusTextColor, color(0xff0000))
        XCTAssertFalse(status.hasIndicator)
    }

    func testNoTextColorWithoutAnOverride() {
        StatusPrioritySettings.shared.restoreEntries([StatusPriorityEntry(pattern: "wait")])
        let status = iTermSessionTabStatus(sessionID: "test")
        let update = VT100TabStatusUpdate()
        update.statusPresence = .set
        update.status = "Waiting"
        _ = status.apply(update)
        XCTAssertFalse(status.hasDisplayStatusTextColor)
    }

    // A live color picker changes the color on every mouse move. The change
    // shows right away but is written to user defaults only once flushed.
    func testColorChangesShowAtOnceButSaveLater() throws {
        let settings = StatusPrioritySettings.shared
        settings.restoreEntries([StatusPriorityEntry(pattern: "work")])
        let key = "StatusPriorityEntries"

        let posted = expectation(forNotification: StatusPrioritySettings.colorsDidChangeNotification,
                                 object: settings)
        // Several changes in a row post once.
        posted.assertForOverFulfill = true
        settings.setDotColor("#010101", at: 0)
        settings.setDotColor("#00ff00", at: 0)
        XCTAssertEqual(settings.dotColorOverride(for: "working"), color(0x00ff00))

        func savedDotColor() throws -> String? {
            let data = try XCTUnwrap(iTermUserDefaults.userDefaults().data(forKey: key))
            return try JSONDecoder().decode([StatusPriorityEntry].self, from: data).first?.dotColor
        }
        XCTAssertNil(try savedDotColor())
        wait(for: [posted], timeout: 10)

        settings.flushPendingColorSave()
        XCTAssertEqual(try savedDotColor(), "#00ff00")
    }

    // Tabs redraw on displayColorsNotificationNames. Every edit that can
    // change which color a status is drawn in must post one of them, or a
    // tab keeps showing the old color until its status changes. Undo goes
    // through restoreEntries.
    func testEveryEditThatCanChangeColorsPostsADisplayColorsNotification() {
        let settings = StatusPrioritySettings.shared
        let colored = [StatusPriorityEntry(pattern: "wait", dotColor: "#ff0000"),
                       StatusPriorityEntry(pattern: "waiting", dotColor: "#00ff00")]
        let edits: [(String, () -> ())] = [
            ("dot color", { settings.setDotColor("#0000ff", at: 0) }),
            ("text color", { settings.setTextColor("#0000ff", at: 0) }),
            ("undo", { settings.restoreEntries([StatusPriorityEntry(pattern: "wait")]) }),
            ("delete", { settings.remove(at: IndexSet(integer: 0)) }),
            ("pattern", { settings.update("idle", at: 0) }),
            ("reorder", { settings.reorder(from: 1, to: 0) }),
        ]
        for (name, edit) in edits {
            settings.restoreEntries(colored)
            // Let a colors notification still queued from an earlier
            // iteration post before observing.
            let drained = XCTestExpectation(description: "drain \(name)")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 10)

            let anyPosted = XCTestExpectation(description: name)
            anyPosted.assertForOverFulfill = false
            let observers = StatusPrioritySettings.displayColorsNotificationNames.map {
                NotificationCenter.default.addObserver(forName: $0, object: settings, queue: nil) { _ in
                    anyPosted.fulfill()
                }
            }
            edit()
            wait(for: [anyPosted], timeout: 10)
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    // The well's cell starts out zero-sized and is resized by the table. The
    // well must end up centered in it, not in a corner.
    func testColorWellIsCenteredInItsCell() throws {
        StatusPrioritySettings.shared.restoreEntries([
            StatusPriorityEntry(pattern: "wait", dotColor: "#ff0000")
        ])
        let vc = StatusPriorityViewController()
        let view = vc.view
        let tableView = try XCTUnwrap(view.subviews.compactMap {
            ($0 as? NSScrollView)?.documentView as? NSTableView
        }.first)
        // Localization unneeded
        for identifier in ["DotColor", "TextColor"] {
            let column = try XCTUnwrap(tableView.tableColumns.first {
                $0.identifier.rawValue == identifier
            })
            let cell = try XCTUnwrap(tableView.delegate?.tableView?(tableView, viewFor: column, row: 0))
            cell.frame = NSRect(x: 0, y: 0, width: column.width, height: tableView.rowHeight)
            cell.layoutSubtreeIfNeeded()
            let well = try XCTUnwrap(cell.subviews.first)
            XCTAssertGreaterThan(well.frame.width, 0, identifier)
            XCTAssertEqual(well.frame.midX, cell.bounds.midX, accuracy: 0.5, identifier)
            XCTAssertEqual(well.frame.midY, cell.bounds.midY, accuracy: 0.5, identifier)
        }
    }

    // Lists saved before colors existed have no color keys and must still load.
    func testEntriesSavedWithoutColorsDecode() throws {
        let json = #"[{"pattern":"wait","notify":true},{"pattern":"idle","notify":false}]"#
        let entries = try JSONDecoder().decode([StatusPriorityEntry].self, from: Data(json.utf8))
        XCTAssertEqual(entries, [StatusPriorityEntry(pattern: "wait", notify: true),
                                 StatusPriorityEntry(pattern: "idle", notify: false)])
    }

    // An entry without colors encodes the same as before, so prefs shared with
    // an older version are not rewritten with new keys.
    func testEntryWithoutColorsEncodesNoColorKeys() throws {
        let data = try JSONEncoder().encode(StatusPriorityEntry(pattern: "wait"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["pattern", "notify"])
    }
}
