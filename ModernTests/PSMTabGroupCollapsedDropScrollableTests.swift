//
//  PSMTabGroupCollapsedDropScrollableTests.swift
//  iTerm2XCTests
//
//  Integration-level drag tests for dropping a tab into a COLLAPSED group on a
//  SCROLLABLE tab bar. Unlike the unit-level PSMTabGroupCollapsedDropTargeting
//  tests -- which hand-build a STATIC cell layout and call the target computation
//  once -- these drive the REAL -calculateDragAnimationForTabBar: loop over many
//  ticks WITHOUT resetting the cell frames between ticks, so the cross-tick
//  feedback that produces the field "jitter" is live: the animation writes frames,
//  and the next tick reads them back and recomputes. The scrollable path (no
//  squeeze, scaled drop slots, auto-scroll) is exercised because the field bug only
//  reproduced on a scrollable bar.
//
//  The invariant under test is model-independent: once the mouse holds a fixed
//  along-axis position, the committed join, the drop target, and the multiset of
//  open drop-slot animation steps must all CONVERGE and stay constant -- no slot
//  may open then close, and the highlighted pill must be the one under the cursor.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupCollapsedDropScrollableTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var source: PSMTabBarControl!
    private var assistant: PSMTabDragAssistant!
    private var items: [NSTabViewItem] = []
    private var savedScrollable = false

    override func setUp() {
        super.setUp()
        savedScrollable = iTermPreferences.bool(forKey: kPreferenceKeyScrollableSideTabBar)
        iTermPreferences.setBool(true, forKey: kPreferenceKeyScrollableSideTabBar)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.wantsLayer = true
        // Match the field bar: ~591pt wide, scrollable.
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 591, height: 24))
        window.contentView?.addSubview(control)
        source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 591, height: 24))
        window.contentView?.addSubview(source)
        assistant = PSMTabDragAssistant.shared()
    }

    override func tearDown() {
        assistant.finishDrag()
        iTermPreferences.setBool(savedScrollable, forKey: kPreferenceKeyScrollableSideTabBar)
        assistant = nil
        items = []
        control = nil
        source = nil
        window = nil
        super.tearDown()
    }

    private func tab(_ groupID: String?, collapsed: Bool, x: CGFloat, w: CGFloat) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        cell.isCollapsedHidden = collapsed
        let item = NSTabViewItem(identifier: (groupID ?? "-") as NSString)
        items.append(item)
        cell.representedObject = item
        cell.frame = NSRect(x: x, y: 0, width: w, height: 24)
        if !collapsed { cell.dragBaseWidth = w }
        return cell
    }

    private func chip(_ groupID: String, x: CGFloat, w: CGFloat) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        cell.frame = NSRect(x: x, y: 0, width: w, height: 24)
        return cell
    }

    private func slot(x: CGFloat, w: CGFloat = 0, collapsedJoinDetector: Bool = false) -> PSMTabBarCell {
        let cell = PSMTabBarCell(placeholderWithFrame: NSRect(x: x, y: 0, width: w, height: 24),
                                 expanded: false, inControlView: control)!
        cell.isCollapsedGroupJoinSlot = collapsedJoinDetector
        return cell
    }

    // A collapsed group's mid-drag run: chip, front join-detector slot, then
    // (member, slot) pairs. All packed at `x` (members are zero-width).
    private func collapsedRun(_ gid: String, members: Int, chipW: CGFloat, x: CGFloat) -> (cells: [PSMTabBarCell], chip: PSMTabBarCell) {
        var out: [PSMTabBarCell] = []
        let chipCell = chip(gid, x: x, w: chipW)
        out.append(chipCell)
        out.append(slot(x: x + chipW, collapsedJoinDetector: true))
        for _ in 0..<members {
            out.append(tab(gid, collapsed: true, x: x + chipW, w: 0))
            out.append(slot(x: x + chipW))
        }
        return (out, chipCell)
    }

    // The field shape: [tab1][group A: 19 members][group B: 3 members][tab2], on a
    // scrollable bar, dragged in from ANOTHER window (so there is no origin slot).
    private struct Layout {
        var chipA: PSMTabBarCell
        var chipB: PSMTabBarCell
        var dragged: PSMTabBarCell
    }
    private func buildFieldLayout() -> Layout {
        control.style = PSMYosemiteTabStyle()   // Minimal/Yosemite: 0 intercell spacing, as in the field
        let tab1 = tab(nil, collapsed: false, x: 130, w: 156)
        let (runA, chipA) = collapsedRun("A", members: 19, chipW: 66, x: 286)
        let (runB, chipB) = collapsedRun("B", members: 3, chipW: 59, x: 352)
        let tab2 = tab(nil, collapsed: false, x: 411, w: 156)
        let trailing = slot(x: 567)
        control.cells().setArray([tab1] + runA + runB + [tab2, trailing])

        let dragged = tab(nil, collapsed: false, x: 0, w: 156)
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(source)        // cross-window
        assistant.setDestinationTabBar(control)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 156)
        return Layout(chipA: chipA, chipB: chipB, dragged: dragged)
    }

    // The multiset of open (step>0) placeholder animation steps this tick -- the
    // fingerprint of which drop slots are open and how far. Stable == no gap
    // opening/closing.
    private func openSlotSteps() -> [Int] {
        return (control.cells() as! [PSMTabBarCell])
            .filter { $0.isPlaceholder && $0.currentStep > 0 }
            .map { Int($0.currentStep) }
            .sorted()
    }

    private func targetIndex() -> Int {
        guard let t = assistant.targetCell() else { return -1 }
        return (control.cells() as! [PSMTabBarCell]).firstIndex { $0 === t } ?? -1
    }

    // THE JITTER as a model-independent invariant: dragging the cursor smoothly
    // toward and onto a collapsed pill must NOT make that pill slide away from the
    // cursor (a drop slot opening beside it) and snap back. Collapsed groups show
    // drop intent by HIGHLIGHTING, never by opening a gap that shoves the run. So
    // while sweeping onto B, B's origin must stay within a small tolerance of its
    // resting position -- it must never lurch right and return.
    func testCollapsedPillDoesNotRunAwayDuringApproach() {
        let L = buildFieldLayout()
        for _ in 0..<4 {
            assistant.setCurrentMouseLoc(NSPoint(x: 700, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        let bRest = L.chipB.frame.minX          // B's resting origin (slots closed)
        let bMid = L.chipB.frame.midX
        let start = L.chipA.frame.minX - 24

        var maxExcursion: CGFloat = 0
        var trace: [String] = []
        let steps = 12
        var script: [CGFloat] = []
        for i in 0...steps { script.append(start + (bMid - start) * CGFloat(i) / CGFloat(steps)) }
        for _ in 0..<10 { script.append(bMid) }
        for (i, mx) in script.enumerated() {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: mx, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            let excursion = abs(L.chipB.frame.minX - bRest)
            maxExcursion = max(maxExcursion, excursion)
            trace.append("t\(i) mx=\(Int(mx)) Bmin=\(Int(L.chipB.frame.minX)) excursion=\(Int(excursion))")
        }
        // Allow a few px of animation slack, but not a whole-slot lurch.
        XCTAssertLessThan(maxExcursion, 12,
            "collapsed pill B ran away from the approaching cursor (opened a slot beside it):\n\(trace.joined(separator: "\n"))")
    }

    // THE AFFORDANCE (regression the jitter fix removed): when the cursor SETTLES in
    // the between-two-groups zone (A's right third / B's left third), a drop slot
    // must OPEN between the pills so the user sees where the tab will land. During
    // the sweep it stays closed (the run-away test above); once settled it opens.
    func testBetweenTwoGroupsOpensSlotWhenSettled() {
        let L = buildFieldLayout()
        for _ in 0..<4 {
            assistant.setCurrentMouseLoc(NSPoint(x: 700, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        // B's left third (settled) is a between zone: [Bmin, Bmin + width/3).
        let betweenX = L.chipB.frame.minX + L.chipB.frame.width / 6.0
        // Settle there and hold; the between slot should animate open over a few
        // ticks and stay open.
        var steps: [[Int]] = []
        for i in 0..<12 {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: betweenX, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            steps.append(openSlotSteps())
        }
        // Not a join (between two groups joins neither).
        XCTAssertNil(assistant.collapsedGroupJoinTargetIdentifier(),
                     "the between zone must not mark a join")
        // A slot must be open by the time it settles, and stay open (stable tail).
        let tail = Array(steps.suffix(4))
        XCTAssertTrue(tail.allSatisfy { !$0.isEmpty },
                      "no drop slot opened when settled in the between-two-groups zone: \(steps)")
        XCTAssertTrue(tail.allSatisfy { $0 == tail.first },
                      "the between slot did not stabilize (opened/closed): \(steps)")
    }

    // The settled-gate opens the between slot on a steady mouse. A real held mouse
    // is not perfectly still -- it tremors sub-pixel. That tremor must NOT flip the
    // gate on and off (which would open/close the gap = jitter). Hold in the between
    // zone with realistic sub-pixel x tremor plus ~1px y jitter and assert the open
    // slot set is stable across the tail.
    func testBetweenSlotStableUnderHandTremor() {
        let L = buildFieldLayout()
        for _ in 0..<4 {
            assistant.setCurrentMouseLoc(NSPoint(x: 700, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        let anchorX = L.chipB.frame.minX + L.chipB.frame.width / 6.0
        // Sub-pixel x tremor (within the steady threshold) + 1px y jitter.
        let xTremor: [CGFloat] = [0, 0.3, -0.2, 0.1, -0.3, 0.2, -0.1, 0.3, -0.2, 0.1, 0, -0.3, 0.2, -0.1, 0.3, -0.2]
        var steps: [[Int]] = []
        for i in 0..<xTremor.count {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: anchorX + xTremor[i], y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            steps.append(openSlotSteps())
        }
        let tail = Array(steps.suffix(6))
        XCTAssertTrue(tail.allSatisfy { $0 == tail.first && !$0.isEmpty },
                      "hand tremor made the between slot open/close (jitter): \(steps)")
    }

    // THE STUTTER (reported): with the between gap open, SLOWLY moving the cursor
    // left within the between zone must not make the right pill stutter left (gap
    // closing a step) and back. Once open, the gap must hold steady while the cursor
    // stays in the zone -- the open depends on the target being the same between
    // slot, not on the mouse holding still. Assert the right pill's origin never
    // lurches back (no close-then-reopen) during the slow move.
    func testBetweenSlotStableUnderSlowMovement() {
        let L = buildFieldLayout()
        for _ in 0..<4 {
            assistant.setCurrentMouseLoc(NSPoint(x: 700, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        // Settle in B's left third (between zone) to open the gap.
        let startX = L.chipB.frame.minX + L.chipB.frame.width / 6.0
        for _ in 0..<8 {
            assistant.setCurrentMouseLoc(NSPoint(x: startX, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        // Now slowly move LEFT ~1.3px/tick, staying inside the between region (down
        // to A's right third), with cross-axis jitter. Record B's origin each tick.
        var bMins: [CGFloat] = []
        var x = startX
        for i in 0..<20 {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            x -= 1.3
            // Stop before leaving the between region into A's center.
            if x < L.chipA.frame.minX + L.chipA.frame.width * 2.0 / 3.0 { break }
            assistant.setCurrentMouseLoc(NSPoint(x: x, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            bMins.append(L.chipB.frame.minX)
        }
        // The gap must stay open: B's origin must not stutter (drop back toward its
        // resting position and return). Once settled it should be constant.
        XCTAssertGreaterThan(bMins.count, 4, "not enough in-zone samples: \(bMins)")
        let first = bMins.first!
        XCTAssertTrue(bMins.allSatisfy { abs($0 - first) < 2.0 },
                      "the right pill stuttered during slow movement in the between zone: \(bMins.map { Int($0) })")
    }

    // Window-coordinate minX of each group chip, by gid (chips are re-derived across
    // -draggingEnteredTabBar:, so identity is by gid, not object).
    private func chipMinXByGid() -> [String: CGFloat] {
        var out: [String: CGFloat] = [:]
        for c in (control.cells() as! [PSMTabBarCell]) where c.isTabGroupChip {
            if let gid = c.tabGroupIdentifier { out[gid] = c.frame.minX }
        }
        return out
    }

    // THE ENTRY FLASH, at the real drag-entry boundary. Earlier tests hand-built the
    // POST-entry cell array; the field jitter was a draw of the layout the REAL
    // -draggingEnteredTabBar: leaves before the animation walk runs (cells shoved a
    // pill-width sideways, snapping back next tick). This drives the real entry and
    // asserts the chip positions right after entry already equal the settled
    // positions -- i.e. the first drawable frame is not shifted.
    func testRealDragEntryLeavesSettledLayout() {
        control.style = PSMYosemiteTabStyle()
        // Pre-drag destination bar: tab1, collapsed group A (2 members), collapsed
        // group B (2 members), tab2 -- real cells, no placeholders yet.
        let tab1 = tab(nil, collapsed: false, x: 130, w: 156)
        let chipA = chip("A", x: 286, w: 66)
        let a0 = tab("A", collapsed: true, x: 352, w: 0)
        let a1 = tab("A", collapsed: true, x: 352, w: 0)
        let chipB = chip("B", x: 352, w: 59)
        let b0 = tab("B", collapsed: true, x: 411, w: 0)
        let b1 = tab("B", collapsed: true, x: 411, w: 0)
        let tab2 = tab(nil, collapsed: false, x: 411, w: 156)
        control.cells().setArray([tab1, chipA, a0, a1, chipB, b0, b1, tab2])

        // A cross-window drag in progress: dragged tab lives in the source bar.
        let dragged = PSMTabBarCell(controlView: source)!
        let dItem = NSTabViewItem(identifier: "dragged" as NSString)
        items.append(dItem)
        dragged.representedObject = dItem
        dragged.frame = NSRect(x: 0, y: 0, width: 156, height: 24)
        source.cells().setArray([dragged])
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(source)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 156)

        // Enter over group B's chip (a collapsed pill) -- the real entry path.
        let entryPoint = NSPoint(x: chipB.frame.midX, y: 12)
        assistant.draggingEnteredTabBar(control, at: entryPoint)

        // The chip positions the FIRST draw would show.
        let entry = chipMinXByGid()

        // Now let the animation fully settle at the same point.
        for _ in 0..<10 {
            assistant.setCurrentMouseLoc(entryPoint)
            assistant.calculateDragAnimation(forTabBar: control)
        }
        let settled = chipMinXByGid()

        XCTAssertFalse(entry.isEmpty, "no chips present after entry")
        for (gid, settledX) in settled {
            let entryX = entry[gid] ?? -9999
            XCTAssertEqual(entryX, settledX, accuracy: 8.0,
                "group \(gid) was shifted at drag entry (flash): entry=\(entry) settled=\(settled)")
        }
    }
}
