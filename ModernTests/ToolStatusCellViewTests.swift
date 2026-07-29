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
                               statusColor: NSColor? = .systemRed,
                               dimmed: Bool = false,
                               showSeparator: Bool = false) {
        cell.configure(scope: iTermVariableScope(),
                       dotImage: NSImage(size: NSSize(width: 10, height: 10)),
                       peerLabel: "Peer",
                       shortcut: "⌥⇧⌘1",
                       statusText: "Working",
                       statusColor: statusColor,
                       detail: "Some detail text",
                       armed: true,
                       dimmed: dimmed,
                       showSeparator: showSeparator)
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

    // A snoozed row dims its text to 50% alpha; every text label is
    // affected so the whole entry reads as backgrounded.
    func test_dimmedConfigureDimsText() {
        let cell = makeCell()
        configureFull(cell, dimmed: true)
        XCTAssertEqual(cell.nameLabel.alphaValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(cell.peerLabel.alphaValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(cell.shortcutLabel.alphaValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(cell.statusLabel.alphaValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(cell.detailLabel.alphaValue, 0.5, accuracy: 0.001)
    }

    // The snooze glyph appears only on snoozed (dimmed) rows and never
    // leaks onto a later, un-snoozed occupant of a recycled cell.
    func test_snoozeIconTracksDimmed() {
        let cell = makeCell()
        configureFull(cell, dimmed: true)
        XCTAssertFalse(cell.snoozeIconView.isHidden)
        configureFull(cell, dimmed: false)
        XCTAssertTrue(cell.snoozeIconView.isHidden)
        configureFull(cell, dimmed: true)
        cell.clear()
        XCTAssertTrue(cell.snoozeIconView.isHidden)
    }

    // The snoozed-group divider shows only when requested, and never
    // leaks onto a later occupant of a recycled cell.
    func test_separatorShowsAndClears() {
        let cell = makeCell()
        configureFull(cell, showSeparator: true)
        XCTAssertFalse(cell.separatorView.isHidden)
        configureFull(cell, showSeparator: false)
        XCTAssertTrue(cell.separatorView.isHidden)
        configureFull(cell, showSeparator: true)
        cell.clear()
        XCTAssertTrue(cell.separatorView.isHidden)
    }

    // The dim state must not leak onto a later, un-snoozed occupant of a
    // recycled cell.
    func test_dimmedDoesNotSurviveReconfigure() {
        let cell = makeCell()
        configureFull(cell, dimmed: true)
        configureFull(cell, dimmed: false)
        XCTAssertEqual(cell.nameLabel.alphaValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(cell.statusLabel.alphaValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(cell.detailLabel.alphaValue, 1.0, accuracy: 0.001)
    }

    // clear() restores full opacity along with blanking content.
    func test_clearResetsTextAlpha() {
        let cell = makeCell()
        configureFull(cell, dimmed: true)
        cell.clear()
        XCTAssertEqual(cell.nameLabel.alphaValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(cell.statusLabel.alphaValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(cell.detailLabel.alphaValue, 1.0, accuracy: 0.001)
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

// Pins the workgroup-merge grouping rule: a session's workgroup
// *instance* is what collapses rows, not its individual peer port. A
// workgroup owns a main peer port plus a nested port per split host, so
// keying by port identity (the old behavior) split one workgroup across
// several rows and dropped port-less split/tab children entirely, which
// is why "merge workgroup statuses" appeared to do nothing.
final class ToolStatusMergeGroupingTests: XCTestCase {
    private func portIdentity() -> ObjectIdentifier {
        return ObjectIdentifier(NSObject())
    }

    // The core fix: two sessions in the same workgroup but different peer
    // ports (e.g. a root peer and a split host's nested-port peer) must
    // share a group key so they merge into one row.
    func test_sameWorkgroupDifferentPortsMerge() {
        let a = ToolStatus.groupKey(sessionID: "A",
                                    workgroupInstanceID: "WG1",
                                    peerPortIdentity: portIdentity())
        let b = ToolStatus.groupKey(sessionID: "B",
                                    workgroupInstanceID: "WG1",
                                    peerPortIdentity: portIdentity())
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, .workgroup("WG1"))
    }

    // A port-less workgroup member (split/tab child with no peers) still
    // merges into its workgroup's row.
    func test_portlessWorkgroupMemberMerges() {
        let peer = ToolStatus.groupKey(sessionID: "A",
                                       workgroupInstanceID: "WG1",
                                       peerPortIdentity: portIdentity())
        let splitChild = ToolStatus.groupKey(sessionID: "B",
                                             workgroupInstanceID: "WG1",
                                             peerPortIdentity: nil)
        XCTAssertEqual(peer, splitChild)
    }

    // Different workgroups stay distinct.
    func test_differentWorkgroupsDoNotMerge() {
        let a = ToolStatus.groupKey(sessionID: "A",
                                    workgroupInstanceID: "WG1",
                                    peerPortIdentity: nil)
        let b = ToolStatus.groupKey(sessionID: "B",
                                    workgroupInstanceID: "WG2",
                                    peerPortIdentity: nil)
        XCTAssertNotEqual(a, b)
    }

    // No workgroup but a shared peer port: fall back to port identity so
    // such peers still merge (preserves the prior behavior).
    func test_peerPortFallbackMergesWhenNoWorkgroup() {
        let port = portIdentity()
        let a = ToolStatus.groupKey(sessionID: "A",
                                    workgroupInstanceID: nil,
                                    peerPortIdentity: port)
        let b = ToolStatus.groupKey(sessionID: "B",
                                    workgroupInstanceID: nil,
                                    peerPortIdentity: port)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, .peerPort(port))
    }

    // No workgroup and no port: each session is its own row.
    func test_soloSessionsStayDistinct() {
        let a = ToolStatus.groupKey(sessionID: "A",
                                    workgroupInstanceID: nil,
                                    peerPortIdentity: nil)
        let b = ToolStatus.groupKey(sessionID: "B",
                                    workgroupInstanceID: nil,
                                    peerPortIdentity: nil)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, .solo("A"))
    }
}

// Pins the merged-row representative-preference rule, in particular that a
// snoozed member *loses* representation so a snoozed peer's stale status
// can't hide an active sibling. A workgroup reads as snoozed only when every
// member is snoozed.
final class ToolStatusMergeRepresentativeTests: XCTestCase {
    // A non-snoozed sibling represents the row over a snoozed member, even
    // when the snoozed member changed more recently.
    func test_nonSnoozedMemberWinsRowOverSnoozedMember() {
        // P is not snoozed but older; R is snoozed and fresher.
        let pPrefersOverR = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: false, candidateSnoozed: false, candidateLastChanged: 100, candidatePriority: 0, candidateSessionID: "P",
            currentVisible: false, currentSnoozed: true, currentLastChanged: 200, currentPriority: 0, currentSessionID: "R")
        XCTAssertTrue(pPrefersOverR, "A non-snoozed sibling must win the row over a snoozed member, regardless of recency")

        let rPrefersOverP = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: false, candidateSnoozed: true, candidateLastChanged: 200, candidatePriority: 0, candidateSessionID: "R",
            currentVisible: false, currentSnoozed: false, currentLastChanged: 100, currentPriority: 0, currentSessionID: "P")
        XCTAssertFalse(rPrefersOverP, "A snoozed member must not steal the row from a non-snoozed sibling")
    }

    // The currently visible switcher peer represents the row over a buried
    // sibling that changed more recently and outranks it on priority. This is
    // the chat/code-review case: a visible code-review peer holding a stable
    // "working" status must not lose the row to a chat peer that just flipped
    // to idle.
    func test_visiblePeerWinsRowOverFresherHigherPriorityBuriedSibling() {
        let visiblePrefers = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: true, candidateSnoozed: false, candidateLastChanged: 100, candidatePriority: 1, candidateSessionID: "review",
            currentVisible: false, currentSnoozed: false, currentLastChanged: 200, currentPriority: 0, currentSessionID: "chat")
        XCTAssertTrue(visiblePrefers, "The visible switcher peer must represent the row over a fresher, higher-priority buried sibling")

        let buriedYields = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: false, candidateSnoozed: false, candidateLastChanged: 200, candidatePriority: 0, candidateSessionID: "chat",
            currentVisible: true, currentSnoozed: false, currentLastChanged: 100, currentPriority: 1, currentSessionID: "review")
        XCTAssertFalse(buriedYields, "A buried sibling must not steal the row from the visible switcher peer")
    }

    // Visibility sits *below* snooze: a snoozed visible peer must yield the row
    // to a non-snoozed buried sibling so snooze can still surface a freshly
    // active member.
    func test_snoozedVisiblePeerYieldsToNonSnoozedBuriedSibling() {
        let nonSnoozedPrefers = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: false, candidateSnoozed: false, candidateLastChanged: 100, candidatePriority: 2, candidateSessionID: "buried",
            currentVisible: true, currentSnoozed: true, currentLastChanged: 200, currentPriority: 0, currentSessionID: "visible")
        XCTAssertTrue(nonSnoozedPrefers, "A non-snoozed buried sibling must win over a snoozed visible peer")
    }

    // With neither visible nor snoozed, recency still wins (unchanged fallback).
    func test_recencyWinsWhenNeitherVisibleNorSnoozed() {
        let fresherPrefers = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: false, candidateSnoozed: false, candidateLastChanged: 200, candidatePriority: 5, candidateSessionID: "A",
            currentVisible: false, currentSnoozed: false, currentLastChanged: 100, currentPriority: 0, currentSessionID: "B")
        XCTAssertTrue(fresherPrefers, "Freshest transition should represent the row when neither is visible or snoozed")
    }

    // Every member snoozed: snooze ties, so the tiebreakers (visible, recency,
    // then priority, then sessionID) decide and the group still renders snoozed.
    func test_bothSnoozedFallsBackToRecency() {
        let fresherPrefers = ToolStatus.mergeRepresentativePrefers(
            candidateVisible: false, candidateSnoozed: true, candidateLastChanged: 200, candidatePriority: 0, candidateSessionID: "A",
            currentVisible: false, currentSnoozed: true, currentLastChanged: 100, currentPriority: 0, currentSessionID: "B")
        XCTAssertTrue(fresherPrefers)
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
