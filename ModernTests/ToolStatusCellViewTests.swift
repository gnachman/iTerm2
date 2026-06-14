//
//  ToolStatusCellViewTests.swift
//  ModernTests
//
//  Created by George Nachman on 6/11/26.
//

import XCTest
@testable import iTerm2SharedARC

// Pins the blank-state contract behind the Session Status blank-row
// fix: clear() is the single authority on what blank looks like, and
// configure() is self-clearing so a recycled cell (or the manually
// reused measuring cell) can never show a previous occupant's content.
final class ToolStatusCellViewTests: XCTestCase {
    private func makeCell() -> ToolStatusCellView {
        return ToolStatusCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
    }

    private func configureFull(_ cell: ToolStatusCellView,
                               statusColor: NSColor? = .systemRed) {
        cell.configure(scope: iTermVariableScope(),
                       dotImage: NSImage(size: NSSize(width: 10, height: 10)),
                       peerLabel: "Peer",
                       shortcut: "⌥⇧⌘1",
                       statusText: "Working",
                       statusColor: statusColor,
                       detail: "Some detail text",
                       armed: true)
    }

    private func assertConditionalFieldsBlank(_ cell: ToolStatusCellView,
                                              file: StaticString = #filePath,
                                              line: UInt = #line) {
        XCTAssertNil(cell.dotView.image, file: file, line: line)
        XCTAssertTrue(cell.dotView.isHidden, file: file, line: line)
        XCTAssertEqual(cell.peerLabel.stringValue, "", file: file, line: line)
        XCTAssertTrue(cell.peerLabel.isHidden, file: file, line: line)
        XCTAssertEqual(cell.shortcutLabel.stringValue, "", file: file, line: line)
        XCTAssertTrue(cell.shortcutLabel.isHidden, file: file, line: line)
        XCTAssertEqual(cell.statusLabel.stringValue, "", file: file, line: line)
        XCTAssertTrue(cell.statusLabel.isHidden, file: file, line: line)
        XCTAssertEqual(cell.detailLabel.stringValue, "", file: file, line: line)
        XCTAssertTrue(cell.detailLabel.isHidden, file: file, line: line)
    }

    // clear() blanks every field, including the unconditional ones.
    func test_clearBlanksEveryField() {
        let cell = makeCell()
        configureFull(cell)
        cell.clear()
        assertConditionalFieldsBlank(cell)
        XCTAssertTrue(cell.bellView.isHidden)
        XCTAssertEqual(cell.nameLabel.stringValue, "")
    }

    // configure() is self-clearing: nothing from a previous
    // configuration survives a reconfigure with empty content. This is
    // the recycled-cell / measuring-cell stale-content bug.
    func test_configureIsSelfClearing() {
        let cell = makeCell()
        configureFull(cell)
        cell.configure(scope: iTermVariableScope(),
                       dotImage: nil,
                       peerLabel: nil,
                       shortcut: nil,
                       statusText: nil,
                       statusColor: nil,
                       detail: nil,
                       armed: false)
        assertConditionalFieldsBlank(cell)
        XCTAssertTrue(cell.bellView.isHidden)
    }

    // A custom status color must not leak onto a later occupant whose
    // status text has no explicit color.
    func test_staleStatusColorDoesNotSurvive() {
        let cell = makeCell()
        configureFull(cell, statusColor: .systemRed)
        XCTAssertEqual(cell.statusLabel.textColor, .systemRed)
        cell.configure(scope: iTermVariableScope(),
                       dotImage: nil,
                       peerLabel: nil,
                       shortcut: nil,
                       statusText: "Idle",
                       statusColor: nil,
                       detail: nil,
                       armed: false)
        XCTAssertEqual(cell.statusLabel.textColor, .secondaryLabelColor)
        XCTAssertFalse(cell.statusLabel.isHidden)
    }

    // iTermSwiftyStringTextField.clear() empties the field and stops
    // the interpolated-string evaluator, so a recycled field's old
    // observer cannot repopulate it.
    func test_swiftyFieldClearEmptiesField() {
        let field = iTermSwiftyStringTextField(labelWithString: "")
        field.set(interpolatedString: "literal text", scope: iTermVariableScope())
        XCTAssertEqual(field.stringValue, "literal text")
        field.clear()
        XCTAssertEqual(field.stringValue, "")
    }
}

// Pins ToolStatus's per-reload session-resolution memo contract:
// hits are memoized within a reload cycle, and every reload entry
// point — including the bell armed/disarmed notification, which has
// no accompanying topology notification — drops the memo so a session
// that exited in between renders blank instead of from the stale hit.
final class ToolStatusSessionMemoTests: XCTestCase {
    func test_notifyArmedDidChangeDropsSessionMemo() {
        let tool = ToolStatus(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        // Make a session resolvable: a workgroup leader is reachable
        // through the lookup's registry pass even with no windows.
        let leader = PTYSession(synthetic: false)!
        let wg = WGFix.wgRootOnly()
        iTermWorkgroupModel.instance.add(wg)
        defer { iTermWorkgroupModel.instance.remove(uniqueIdentifier: wg.uniqueIdentifier) }
        XCTAssertTrue(
            iTermWorkgroupController.instance.enter(
                workgroupUniqueIdentifier: wg.uniqueIdentifier,
                on: leader,
                spawner: FakeWorkgroupSpawner()))
        XCTAssertTrue(tool.resolveSessionForReload(guid: leader.guid) === leader)
        // The session becomes unreachable, but the memo still returns
        // the stale hit: that is the documented bounded staleness.
        iTermWorkgroupController.instance.exit(on: leader)
        XCTAssertTrue(tool.resolveSessionForReload(guid: leader.guid) === leader)
        // Arming/disarming the bell reloads rows, so it must drop the
        // memo like every other reload entry point.
        NotificationCenter.default.post(
            name: NotifyOnStatusChangeController.armedDidChangeNotification,
            object: nil)
        XCTAssertNil(tool.resolveSessionForReload(guid: leader.guid),
                     "The armed-state reload must not render from a stale session hit")
    }
}
