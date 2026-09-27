//
//  PSMTabGroupCollapsedDropTargetingTests.swift
//  iTerm2XCTests
//
//  Deterministic drag-targeting tests for dropping a single tab around a
//  COLLAPSED group. These drive the real -calculateDragAnimationForTabBar: target
//  computation over a hand-built mid-drag cell layout (chip + zero-width collapsed
//  members + drop slots) with an explicit mouse location, so the "which slot is
//  the drop target / is this a join" decisions are exercised without a live drag.
//
//  The model under test:
//    * cursor OVER the pill  -> join that group (collapsedGroupJoinTargetIdentifier
//      set), and the pill stays put (the drop gap is left where it was).
//    * cursor LEFT of the pill  -> a "drop before" slot opens just left of it, no join.
//    * cursor PAST (right of) the pill -> a "drop after" slot opens, no join.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupCollapsedDropTargetingTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var assistant: PSMTabDragAssistant!
    private var items: [NSTabViewItem] = []

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.wantsLayer = true
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 376, width: 800, height: 24))
        window.contentView?.addSubview(control)
        assistant = PSMTabDragAssistant.shared()
    }

    override func tearDown() {
        assistant.finishDrag()
        assistant = nil
        items = []
        control = nil
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

    // Layout: [tabA][ drop-before slot ][chip G][front slot*][m0 collapsed][end slot]
    //         [ dragged-tab origin slot ][ trailing slot ]
    // The dragged tab came from the RIGHT (its origin slot is to the right of the
    // group). Returns the important cells for assertions.
    private struct Layout {
        var tabA: PSMTabBarCell
        var beforeSlot: PSMTabBarCell
        var chip: PSMTabBarCell
        var frontSlot: PSMTabBarCell
        var m0: PSMTabBarCell
        var endSlot: PSMTabBarCell
        var originSlot: PSMTabBarCell
        var trailingSlot: PSMTabBarCell
        var dragged: PSMTabBarCell
    }

    private func buildRightApproachLayout() -> Layout {
        let tabA = tab(nil, collapsed: false, x: 0, w: 120)
        let beforeSlot = slot(x: 120)
        let chipCell = chip("G", x: 120, w: 60)
        let frontSlot = slot(x: 180, collapsedJoinDetector: true)
        let m0 = tab("G", collapsed: true, x: 180, w: 0)
        let endSlot = slot(x: 180)
        let originSlot = slot(x: 300, w: 120)   // where the dragged tab was, to the right
        let trailingSlot = slot(x: 420)
        control.cells().setArray([tabA, beforeSlot, chipCell, frontSlot, m0, endSlot, originSlot, trailingSlot])

        let dragged = tab(nil, collapsed: false, x: 300, w: 120)
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(control)
        assistant.setDestinationTabBar(control)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 120)
        return Layout(tabA: tabA, beforeSlot: beforeSlot, chip: chipCell, frontSlot: frontSlot,
                      m0: m0, endSlot: endSlot, originSlot: originSlot, trailingSlot: trailingSlot,
                      dragged: dragged)
    }

    private func targetIndex() -> Int {
        guard let t = assistant.targetCell() else { return -1 }
        return (control.cells() as! [PSMTabBarCell]).firstIndex { $0 === t } ?? -1
    }

    // Drive the drop-target computation at a fixed mouse position. The pill under
    // the cursor is only ACTED ON after two consecutive sightings (a one-tick stale
    // frame must not flash the join on the wrong pill), so a real hover -- and this
    // helper -- must tick at least twice for the join to commit. Two ticks at the
    // same position: the first arms the pill, the second confirms and applies it.
    private func drive(mouseX: CGFloat, initialTarget: PSMTabBarCell? = nil, ticks: Int = 2) {
        if let t = initialTarget { assistant.setTargetCell(t) }
        for _ in 0..<ticks {
            assistant.setCurrentMouseLoc(NSPoint(x: mouseX, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
    }

    // Settle the drop target at a fixed cursor x by ticking twice (the pill-under-
    // cursor debounce commits on the second consecutive sighting).
    private func settleAt(_ x: CGFloat) {
        for _ in 0..<2 {
            assistant.setCurrentMouseLoc(NSPoint(x: x, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
    }

    // Drive `ticks` animation frames at a FIXED along-axis x, with the cross-axis
    // (y) jittering ~1px each tick. A real mouse is never perfectly still, and the
    // drop target must depend only on the along-axis -- cross-axis jitter must not
    // perturb it. Returns the join-target gid observed on each tick.
    @discardableResult
    private func driveWithJitter(_ ticks: Int, mouseX: CGFloat) -> [String?] {
        var gids: [String?] = []
        for i in 0..<ticks {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1   // 19, 20, 21, 19, ... (~1px jitter)
            assistant.setCurrentMouseLoc(NSPoint(x: mouseX, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            gids.append(assistant.collapsedGroupJoinTargetIdentifier())
        }
        return gids
    }

    // Points in the chip's left third, center third, and right third.
    private func leftThird(_ chip: PSMTabBarCell) -> CGFloat { chip.frame.minX + chip.frame.width * 1.0 / 6.0 }
    private func center(_ chip: PSMTabBarCell) -> CGFloat { chip.frame.midX }
    private func rightThird(_ chip: PSMTabBarCell) -> CGFloat { chip.frame.minX + chip.frame.width * 5.0 / 6.0 }

    // Center third -> always a join.
    func testCenterThirdSetsJoinTarget() {
        let L = buildRightApproachLayout()
        drive(mouseX: center(L.chip), initialTarget: L.originSlot)
        XCTAssertEqual(assistant.collapsedGroupJoinTargetIdentifier(), "G",
                       "the center third of a pill must always mark its group as the join target")
    }

    // A pill flanked by a tab (left) and nothing (right): its edge thirds are NOT
    // "between" zones, so they join too (between-a-pill-and-a-tab is done over the
    // tab, not the pill).
    func testEdgeThirdsWithoutPillNeighborsJoin() {
        let L = buildRightApproachLayout()   // tab to the left, no pill on either side
        drive(mouseX: leftThird(L.chip), initialTarget: L.originSlot)
        XCTAssertEqual(assistant.collapsedGroupJoinTargetIdentifier(), "G",
                       "left third with a tab neighbor must join")
        drive(mouseX: rightThird(L.chip), initialTarget: L.originSlot)
        XCTAssertEqual(assistant.collapsedGroupJoinTargetIdentifier(), "G",
                       "right third with no pill neighbor must join")
    }

    // Center-third join, same window -> the pill stays put (the drop gap is left
    // where it was, not forced to the chip's left).
    func testJoinKeepsGapWhereItWas() {
        let L = buildRightApproachLayout()
        drive(mouseX: center(L.chip), initialTarget: L.originSlot)
        XCTAssertTrue(assistant.targetCell() === L.originSlot,
                      "joining must leave the drop gap where it was, not jump it to the chip's left")
    }

    // After joining, moving the cursor LEFT of the pill must open a "drop before"
    // slot adjacent to the group (regression: the hysteresis used to strand the gap
    // on the far side).
    func testMovingLeftOfPillOpensDropBeforeSlot() {
        let L = buildRightApproachLayout()
        drive(mouseX: center(L.chip), initialTarget: L.originSlot)
        drive(mouseX: L.chip.frame.minX - 5)   // just left of the pill
        XCTAssertNil(assistant.collapsedGroupJoinTargetIdentifier(),
                     "left of the pill is not a join")
        XCTAssertTrue(assistant.targetCell() === L.beforeSlot,
                      "left of the pill must target the drop-before slot adjacent to the group, got index \(targetIndex())")
    }

    // Cursor past (right of) the pill -> no join, drop-after slot.
    func testPastPillIsNotAJoin() {
        let L = buildRightApproachLayout()
        drive(mouseX: L.chip.frame.maxX + 5, initialTarget: L.originSlot)
        XCTAssertNil(assistant.collapsedGroupJoinTargetIdentifier(),
                     "right of the pill is a drop-after, not a join")
    }

    // A tab dragged from ANOTHER window over the pill joins and highlights, and the
    // hovered pill is anchored (target = the slot before it) so it can't pack/slide
    // out from under the cursor.
    func testCrossWindowJoinTargetsClosedFrontSlot() {
        let L = buildRightApproachLayout()
        let source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 800, height: 24))
        window.contentView?.addSubview(source)
        assistant.setSourceTabBar(source)   // cross-window: source != destination

        // Drive several ticks over the center (join zone). The join must hold, the
        // target must be the CLOSED front slot (no gap opens on or beside the pill),
        // and no "drop before" slot may open. (The pill-under-cursor debounce needs
        // two sightings to commit, so skip the first couple of acquisition ticks.)
        for i in 0..<10 {
            assistant.setCurrentMouseLoc(NSPoint(x: center(L.chip), y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
            guard i >= 2 else { continue }
            XCTAssertEqual(assistant.collapsedGroupJoinTargetIdentifier(), "G",
                           "hovering the pill from another window must still mark the join")
            XCTAssertTrue(assistant.targetCell() === L.frontSlot,
                          "cross-window join must target the front slot, got index \(targetIndex())")
            XCTAssertEqual(L.frontSlot.currentStep, 0,
                           "the front slot must stay closed so no gap opens")
            XCTAssertEqual(L.beforeSlot.currentStep, 0,
                           "no 'drop before' slot may open for a join")
        }
    }

    // A collapsed group's front slot must never open even when it is the drop
    // target via the positional fallback (the approach), so it can't flash open.
    func testCollapsedFrontSlotNeverOpensWhenTargeted() {
        let L = buildRightApproachLayout()
        assistant.setTargetCell(L.frontSlot)
        // Aim at the center (join zone) so the target computation keeps the front
        // slot targeted (same-window join freezes the current target).
        for _ in 0..<8 {
            assistant.setCurrentMouseLoc(NSPoint(x: center(L.chip), y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
            XCTAssertEqual(L.frontSlot.currentStep, 0,
                           "a collapsed group's front slot must never open (it would read as a gap beside the pill)")
        }
    }

    // Two adjacent collapsed groups A|B at 100-160 and 160-220. Group A's run:
    // chipA, front slot, member, then the between slot; then group B's run. Returns
    // the between slot and B's before-slot for assertions.
    private struct TwoGroups {
        var chipA: PSMTabBarCell
        var betweenSlot: PSMTabBarCell
        var chipB: PSMTabBarCell
        var frontB: PSMTabBarCell      // B's front slot
        var dragged: PSMTabBarCell
    }
    private func buildTwoAdjacentGroups() -> TwoGroups {
        let tabA = tab(nil, collapsed: false, x: 0, w: 100)
        let chipA = chip("A", x: 100, w: 60)
        let frontA = slot(x: 160, collapsedJoinDetector: true)
        let mA = tab("A", collapsed: true, x: 160, w: 0)
        let betweenSlot = slot(x: 160)                 // the drop-between position
        let chipB = chip("B", x: 160, w: 60)
        let frontB = slot(x: 220, collapsedJoinDetector: true)
        let mB = tab("B", collapsed: true, x: 220, w: 0)
        let endB = slot(x: 220)
        let originSlot = slot(x: 300, w: 120)
        control.cells().setArray([tabA, chipA, frontA, mA, betweenSlot, chipB, frontB, mB, endB, originSlot])

        let dragged = tab(nil, collapsed: false, x: 300, w: 120)
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(control)
        assistant.setDestinationTabBar(control)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 120)
        return TwoGroups(chipA: chipA, betweenSlot: betweenSlot,
                         chipB: chipB, frontB: frontB, dragged: dragged)
    }

    // The RIGHT third of A's pill (which has a PILL to its right) is a "drop
    // between" -- neither joins A nor joins B -- so a tab can land between two
    // adjacent groups.
    func testRightThirdWithPillNeighborIsBetween() {
        let G = buildTwoAdjacentGroups()
        settleAt(rightThird(G.chipA))

        XCTAssertNil(assistant.collapsedGroupJoinTargetIdentifier(),
                     "A's right third (pill to the right) must not join A")
        let joined = assistant.groupContainingDrop(of: G.dragged, inTabBar: control)
        XCTAssertNil(joined, "A's right third must land BETWEEN the groups, not join either (got \(joined ?? "nil"))")
    }

    // Mirror: the LEFT third of B's pill (which has a PILL to its left) is a "drop
    // between," not a join of B.
    func testLeftThirdWithPillNeighborIsBetween() {
        let G = buildTwoAdjacentGroups()
        settleAt(leftThird(G.chipB))

        XCTAssertNil(assistant.collapsedGroupJoinTargetIdentifier(),
                     "B's left third (pill to the left) must not join B")
        let joined = assistant.groupContainingDrop(of: G.dragged, inTabBar: control)
        XCTAssertNil(joined, "B's left third must land BETWEEN the groups, not join either (got \(joined ?? "nil"))")
    }

    // Anti-oscillation invariant: A's right third and B's left third (the two
    // "between" zones at a shared boundary) must resolve to the SAME slot, or the
    // layout thrashes as the cursor flips between the pills.
    func testBetweenZonesFromBothSidesTargetSameSlot() {
        let G = buildTwoAdjacentGroups()
        settleAt(rightThird(G.chipA))
        let fromLeftGroup = assistant.targetCell()
        settleAt(leftThird(G.chipB))
        let fromRightGroup = assistant.targetCell()
        XCTAssertNotNil(fromLeftGroup)
        XCTAssertTrue(fromLeftGroup === fromRightGroup,
                      "A's right third and B's left third must target the same between-slot (got \(targetIndex()))")
        XCTAssertTrue(fromLeftGroup === G.betweenSlot,
                      "the shared between-slot must be the slot after A's run")
    }

    // With a FIXED mouse in the between zone, the target must not oscillate. The
    // collapsed layout otherwise feeds back (opening the gap shoves a pill off the
    // cursor -> a different target -> the gap closes -> repeat). Hysteresis freezes
    // the target at a steady mouse, so it stays put across many ticks.
    func testSteadyMouseInBetweenZoneDoesNotOscillate() {
        let G = buildTwoAdjacentGroups()
        // B's left third: opening the between-gap shoves B right off the cursor,
        // which is exactly the feedback that looped in the field. The along-axis x
        // is fixed; the cross-axis y jitters (a real mouse is never perfectly
        // still), which must NOT perturb the target.
        let fixedX = leftThird(G.chipB)
        var targets: [Int] = []
        for i in 0..<15 {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: fixedX, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            targets.append(targetIndex())
        }
        let settled = Array(targets.dropFirst())
        XCTAssertTrue(settled.allSatisfy { $0 == settled.first },
                      "the drop target oscillated at a fixed along-axis x (y jitter): \(targets)")
    }

    // THE REPORTED BUG: cross-window center-join of a pill while the mouse jitters
    // on the cross-axis. The join must stay on THAT pill -- the layout must not keep
    // recomputing (defeating the hysteresis) and flip the join to the neighbor as it
    // packs. (My earlier hysteresis compared BOTH axes, so ~1px of y jitter defeated
    // it; the target must depend on the along-axis only.)
    func testCrossWindowCenterJoinStaysPutUnderCrossAxisJitter() {
        let G = buildTwoAdjacentGroups()
        let source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 800, height: 24))
        window.contentView?.addSubview(source)
        assistant.setSourceTabBar(source)   // cross-window

        // Center of the FIRST pill, along-axis fixed, y jittering.
        let gids = driveWithJitter(15, mouseX: center(G.chipA))
        let settled = Array(gids.dropFirst())
        XCTAssertTrue(settled.allSatisfy { $0 == "A" },
                      "center-join of the first pill must stay joined to A under y jitter, got \(gids)")
    }

    // Same, hovering the SECOND pill's center.
    func testCrossWindowCenterJoinSecondPillStaysPutUnderCrossAxisJitter() {
        let G = buildTwoAdjacentGroups()
        let source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 800, height: 24))
        window.contentView?.addSubview(source)
        assistant.setSourceTabBar(source)   // cross-window

        let gids = driveWithJitter(15, mouseX: center(G.chipB))
        let settled = Array(gids.dropFirst())
        XCTAssertTrue(settled.allSatisfy { $0 == "B" },
                      "center-join of the second pill must stay joined to B under y jitter, got \(gids)")
    }

    // The tab-group chip whose (drawn) frame contains the point, or nil.
    private func chipUnderCursor(_ x: CGFloat, _ y: CGFloat = 12) -> String? {
        for c in (control.cells() as! [PSMTabBarCell]) where c.isTabGroupChip {
            if NSPointInRect(NSPoint(x: x, y: y), c.frame) { return c.tabGroupIdentifier }
        }
        return nil
    }

    // Two adjacent pills A|B preceded by an OPEN approach slot (the gap the drag
    // opened coming in). Joining a pill closes every non-target slot, so this
    // approach slot collapses and packs both pills LEFT -- which can slide a
    // neighbor under a stationary cursor. Cross-window (source != destination) so
    // the join targets the closed front slot and the pack actually happens.
    private func buildPackApproachLayout() -> TwoGroups {
        let tabA = tab(nil, collapsed: false, x: 0, w: 100)
        let approach = slot(x: 100, w: 120)   // OPEN; will close and pack the pills left
        approach.currentStep = 7              // fully open in the 8-step (120px) table
        let chipA = chip("A", x: 220, w: 60)
        let frontA = slot(x: 280, collapsedJoinDetector: true)
        let mA = tab("A", collapsed: true, x: 280, w: 0)
        let betweenSlot = slot(x: 280)
        let chipB = chip("B", x: 280, w: 60)
        let frontB = slot(x: 340, collapsedJoinDetector: true)
        let mB = tab("B", collapsed: true, x: 340, w: 0)
        let endB = slot(x: 340)
        control.cells().setArray([tabA, approach, chipA, frontA, mA, betweenSlot, chipB, frontB, mB, endB])

        let dragged = tab(nil, collapsed: false, x: 500, w: 120)
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(control)
        assistant.setDestinationTabBar(control)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 120)
        return TwoGroups(chipA: chipA, betweenSlot: betweenSlot,
                         chipB: chipB, frontB: frontB, dragged: dragged)
    }

    // THE REPORTED BUG: "I dragged over the right pill and the LEFT one
    // highlighted." A cross-window join targets a pill's closed front slot, which
    // lets the approach slots collapse and packs the neighbor pill under a
    // stationary cursor -- and the steady-mouse hysteresis had frozen the join on
    // the pill that WAS under the cursor when it settled, so the highlight stuck to
    // a pill the cursor had left. The invariant: the join must never highlight a
    // pill the cursor is not over.
    func testHeldJoinReleasesWhenPackSlidesNeighborUnderCursor() {
        let G = buildPackApproachLayout()
        let source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 800, height: 24))
        window.contentView?.addSubview(source)
        assistant.setSourceTabBar(source)   // cross-window

        // Settle one tick over A's center to take the join on A, then FIX the
        // cursor there. As the approach slot collapses, B slides under it.
        assistant.setCurrentMouseLoc(NSPoint(x: G.chipA.frame.midX, y: 12))
        assistant.calculateDragAnimation(forTabBar: control)
        let fixedX = G.chipA.frame.midX

        var underCursor: [String?] = []
        var gids: [String?] = []
        for i in 0..<12 {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1   // ~1px cross-axis jitter
            assistant.setCurrentMouseLoc(NSPoint(x: fixedX, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            underCursor.append(chipUnderCursor(fixedX))
            gids.append(assistant.collapsedGroupJoinTargetIdentifier())
        }

        // Non-vacuous: the pack must actually slide B under the stationary cursor,
        // or this test proves nothing.
        XCTAssertTrue(underCursor.contains("B"),
                      "precondition: the pack should slide pill B under the fixed cursor; got \(underCursor)")

        // The BUG was a PERSISTENT stale highlight: the frozen join stuck on A for
        // the whole steady period while the pack had slid B under the cursor. The
        // switch off A is now delayed a few frames (the pill-under-cursor debounce
        // needs two consecutive sightings, plus a one-frame reposition lag -- all
        // imperceptible), so assert the CONVERGED state: by the tail the join has
        // left A and never points at a pill the cursor isn't over.
        let tail = gids.suffix(4)
        XCTAssertFalse(tail.contains("A"),
                       "the join stayed stuck on A after the pack slid B under the cursor: \(gids)")
        for i in (gids.count - 4)..<gids.count {
            if let g = gids[i], let u = underCursor[i] {
                XCTAssertEqual(g, u, "converged join must match the pill under the cursor (tick \(i)): under=\(underCursor) gids=\(gids)")
            }
        }
    }

    // THE REPORTED JITTER: dragging the cursor SLOWLY through the between zone (B's
    // left third) must not oscillate. Targeting the between slot opens a gap that
    // shoves B right; hit-testing B's LIVE frame then loses the cursor into the gap
    // and flips the target to the positional fallback, which closes the gap -- the
    // pill and target thrash every tick. The mouse is MOVING (~1px/tick), so the
    // steady-mouse freeze can't help; only hit-testing the pill's SETTLED position
    // keeps the zone stable.
    func testMovingMouseThroughBetweenZoneDoesNotOscillate() {
        let G = buildTwoAdjacentGroups()
        // B's left third (settled) is a between zone. Sweep the along-axis slowly
        // LEFT-ward while staying inside it, with the cross-axis jittering.
        let startX = leftThird(G.chipB) + 8   // near the right edge of B's left third
        var targets: [Int] = []
        var gids: [String?] = []
        for i in 0..<14 {
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: startX - CGFloat(i), y: y))  // ~1px/tick
            assistant.calculateDragAnimation(forTabBar: control)
            targets.append(targetIndex())
            gids.append(assistant.collapsedGroupJoinTargetIdentifier())
        }
        XCTAssertTrue(gids.allSatisfy { $0 == nil },
                      "the between zone must never mark a join while sweeping through it: \(gids)")
        // The target must not flip between the between-slot and the positional
        // fallback. Allow the first couple of ticks to lock in, then require one
        // stable slot for the rest of the slow sweep.
        let settled = Array(targets.dropFirst(2))
        XCTAssertTrue(settled.allSatisfy { $0 == settled.first },
                      "the drop target oscillated while dragging slowly through the between zone: \(targets)")
    }

    // A collapsed group that is the FIRST cell run, preceded by an OPEN leading
    // drop slot (the gap the drag opened at the front of the bar). Dropping into
    // that gap must land BEFORE the group, not join it.
    private func buildLeadingSlotBeforeFirstPill() -> (leadSlot: PSMTabBarCell, chipA: PSMTabBarCell, dragged: PSMTabBarCell) {
        let leadSlot = slot(x: 0, w: 120)   // OPEN leading drop slot before the first pill
        leadSlot.currentStep = 7
        leadSlot.frame = NSRect(x: 0, y: 0, width: 120, height: 24)   // force the open width (settled reads frame.width)
        let chipA = chip("A", x: 120, w: 60)
        let frontA = slot(x: 180, collapsedJoinDetector: true)
        let mA = tab("A", collapsed: true, x: 180, w: 0)
        let endA = slot(x: 180)
        let tabB = tab(nil, collapsed: false, x: 180, w: 120)   // a trailing real tab
        control.cells().setArray([leadSlot, chipA, frontA, mA, endA, tabB])

        let dragged = tab(nil, collapsed: false, x: 400, w: 120)
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(control)
        assistant.setDestinationTabBar(control)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 120)
        return (leadSlot, chipA, dragged)
    }

    // THE REPORTED REGRESSION: dragging into the gap before the FIRST collapsed
    // group joined it instead of dropping before it. Settled hit-testing pinned the
    // first pill to the leading margin (it absorbed the leading drop slot), so the
    // cursor in the "before" gap mapped onto the pill. The fix absorbs displacement
    // only back to a LEFT-adjacent pill; the first pill has none, so its live frame
    // is used and the gap to its left stays reachable.
    func testDraggingBeforeFirstCollapsedPillDoesNotJoinIt() {
        let L = buildLeadingSlotBeforeFirstPill()
        assistant.setTargetCell(L.leadSlot)
        // Cursor near the LEFT of the open leading gap -- well left of the pill's
        // drawn edge. (Absorbing the leading slot used to pin the pill to the margin
        // and map this gap onto the pill's left third -> a spurious join.)
        let gapX = L.leadSlot.frame.minX + 8
        assistant.setCurrentMouseLoc(NSPoint(x: gapX, y: 12))
        assistant.calculateDragAnimation(forTabBar: control)

        // The cursor is in the gap BEFORE the first pill, not over it, so no join is
        // marked. This is the assertion that distinguishes the fix: with the leading
        // slot absorbed, chipUnderMouse would be the pill and its left third would
        // set the join id to that group.
        XCTAssertNil(assistant.collapsedGroupJoinTargetIdentifier(),
                     "the gap before the first collapsed group must not mark a join")

        // End to end: with the front drop slot as the target (as a real drag has it
        // -- the cursor sits in the open leading gap), the drop resolves to BEFORE
        // the group. The first real cell after the slot is the pill's chip, which is
        // "outside" the group's bracket. (Forced here because the offscreen test
        // control's -cellForPoint: can't hit-test, so the live drag's target isn't
        // reproduced; the resolver logic under test is unaffected.)
        assistant.setTargetCell(L.leadSlot)
        let joined = assistant.groupContainingDrop(of: L.dragged, inTabBar: control)
        XCTAssertNil(joined, "dropping into the gap before the first collapsed group must not join it (got \(joined ?? "nil"))")
    }

    // A run of cells for one COLLAPSED group as it appears mid-drag: the chip, its
    // front join-detector slot, then (member, slot) pairs for each hidden member.
    private func collapsedRun(_ gid: String, members: Int, chipW: CGFloat) -> (cells: [PSMTabBarCell], chip: PSMTabBarCell) {
        var out: [PSMTabBarCell] = []
        let chipCell = chip(gid, x: 0, w: chipW)
        out.append(chipCell)
        out.append(slot(x: 0, collapsedJoinDetector: true))   // front-of-group join slot
        for _ in 0..<members {
            out.append(tab(gid, collapsed: true, x: 0, w: 0))  // hidden member
            out.append(slot(x: 0))                              // slot after the member
        }
        return (out, chipCell)
    }

    // Two adjacent MULTI-member collapsed groups flanked by real tabs, same-window
    // drag -- the shape from the field flicker log (a big group, then a small one,
    // between two ordinary tabs). Returns the two chips and the dragged cell.
    private func buildTwoAdjacentMultiMemberGroups(membersA: Int, membersB: Int, full: Bool = false) -> (chipA: PSMTabBarCell, chipB: PSMTabBarCell, dragged: PSMTabBarCell) {
        control.style = PSMYosemiteTabStyle()   // intercellSpacing 0: collapsed pills abut, as in the log
        // In a FULL bar the tabs overflow, so an opening drop slot SQUEEZES the real
        // tabs (their width shrinks) rather than growing the bar -- a displacement
        // the settled hit-test does not undo. dragBaseWidth engages the squeeze path.
        let tabW: CGFloat = full ? 380 : 156
        let tab1 = tab(nil, collapsed: false, x: 0, w: tabW); tab1.dragBaseWidth = tabW
        let phBeforeA = slot(x: 0)
        let (runA, chipA) = collapsedRun("A", members: membersA, chipW: 66)
        let (runB, chipB) = collapsedRun("B", members: membersB, chipW: 59)
        let tab2 = tab(nil, collapsed: false, x: 0, w: tabW); tab2.dragBaseWidth = tabW
        let trailing = slot(x: 0)
        control.cells().setArray([tab1, phBeforeA] + runA + runB + [tab2, trailing])

        let dragged = tab(nil, collapsed: false, x: 0, w: 156)
        assistant.setIsDragging(true)
        assistant.setSourceTabBar(control)      // same window
        assistant.setDestinationTabBar(control)
        assistant.setDraggedCell(dragged)
        assistant.startAnimation(with: .horizontalOrientation, width: 156)
        return (chipA, chipB, dragged)
    }

    // Two adjacent MULTI-member collapsed groups flanked by real tabs (the field
    // flicker's shape): at every fixed cursor position across the boundary region,
    // driving many jittered ticks must converge to ONE join decision -- never an
    // ongoing flip between the two pills. Covers both a roomy bar and a FULL bar
    // (where an opening slot squeezes the real tabs).
    func testMultiMemberTwoGroupJoinIsStableAcrossSweep() {
        for full in [false, true] {
            tearDown(); setUp()
            let G = buildTwoAdjacentMultiMemberGroups(membersA: 19, membersB: 3, full: full)
            // Settle so the layout packs.
            for _ in 0..<6 {
                assistant.setCurrentMouseLoc(NSPoint(x: G.chipA.frame.midX, y: 12))
                assistant.calculateDragAnimation(forTabBar: control)
            }
            var x = G.chipA.frame.minX + 4
            let end = G.chipB.frame.maxX - 4
            while x <= end {
                var gids: [String] = []
                for i in 0..<18 {
                    let y: CGFloat = 20 + CGFloat(i % 3) - 1   // cross-axis jitter
                    assistant.setCurrentMouseLoc(NSPoint(x: x, y: y))
                    assistant.calculateDragAnimation(forTabBar: control)
                    gids.append(assistant.collapsedGroupJoinTargetIdentifier() ?? "-")
                }
                let settled = Array(gids.dropFirst(6))   // allow convergence
                XCTAssertTrue(settled.allSatisfy { $0 == settled.first },
                              "join flickered at x=\(Int(x)) full=\(full): \(gids)")
                x += 4
            }
        }
    }

    // THE FIELD FLICKER, reproduced deterministically. The displayed (settled)
    // layout is stable, but the pill frames the hit-test reads get transiently
    // shifted by ~a pill width for a SINGLE tick (something repositions the run
    // between ticks), which flips the pill under a stationary cursor and blips the
    // join to the neighbor and back. Simulate that by shifting the chip frames for
    // one tick, and assert the pill-under-cursor debounce holds the join steady.
    func testTransientFrameShiftDoesNotBlipTheJoin() {
        let G = buildTwoAdjacentMultiMemberGroups(membersA: 19, membersB: 3)
        // Settle and commit the join to B (aim at B's center).
        for _ in 0..<6 {
            assistant.setCurrentMouseLoc(NSPoint(x: G.chipB.frame.midX, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        // A fixed cursor inside B's center third (packed) -- which also lands inside
        // A once the block is shoved right by A's width (a blip).
        let fixedX = G.chipB.frame.minX + 20
        let shift = G.chipA.frame.width   // A's width: the observed block shift
        var gids: [String] = []
        for i in 0..<18 {
            // Every 5th tick, transiently shove the two pills right (as the field
            // repositioning does) BEFORE the target is computed. calculateDragAnimation
            // repositions them back to packed within the tick.
            if i % 5 == 2 {
                G.chipA.frame = G.chipA.frame.offsetBy(dx: shift, dy: 0)
                G.chipB.frame = G.chipB.frame.offsetBy(dx: shift, dy: 0)
            }
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: fixedX, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            gids.append(assistant.collapsedGroupJoinTargetIdentifier() ?? "-")
        }
        // The join must stay on B; the one-tick shifts to A must be absorbed.
        XCTAssertTrue(gids.allSatisfy { $0 == "B" },
                      "a transient one-tick frame shift blipped the join off B: \(gids)")
    }

    // THE VISIBLE JITTER (from the screenshots): a drop slot opens to the LEFT of
    // both group chips for a single frame, shoving the run sideways, then snaps
    // back. Cause: a one-tick hit-test reading of NONE (the cursor momentarily over
    // no pill, from a transient frame) cleared the committed pill and recomputed a
    // POSITIONAL target -- a slot before the group -- which animated open. The
    // symmetric debounce must hold the committed join through a one-frame NONE, so
    // the join stays and NO slot-before-group opens.
    func testTransientNoPillReadingDoesNotOpenSlotBeforeGroup() {
        let G = buildTwoAdjacentMultiMemberGroups(membersA: 19, membersB: 3)
        // Settle and commit the join to B.
        for _ in 0..<6 {
            assistant.setCurrentMouseLoc(NSPoint(x: G.chipB.frame.midX, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        let fixedX = G.chipB.frame.midX
        // A far-left placeholder before the group run: if a positional target is ever
        // (wrongly) chosen on a NONE tick, a slot here opens (currentStep > 0). It
        // must never open while we hold a committed join.
        let cells = control.cells() as! [PSMTabBarCell]
        let firstChipIdx = cells.firstIndex { $0.isTabGroupChip }!
        let slotBeforeGroup = cells[..<firstChipIdx].last { $0.isPlaceholder }

        var gids: [String] = []
        for i in 0..<18 {
            // Every 5th tick, shove BOTH pills far right BEFORE the target is
            // computed, so the fixed cursor falls in the gap to their left -> the
            // raw hit-test reads NONE for that one tick (the transient the field hit).
            if i % 5 == 2 {
                let far = G.chipA.frame.width + G.chipB.frame.width + 40
                G.chipA.frame = G.chipA.frame.offsetBy(dx: far, dy: 0)
                G.chipB.frame = G.chipB.frame.offsetBy(dx: far, dy: 0)
            }
            let y: CGFloat = 20 + CGFloat(i % 3) - 1
            assistant.setCurrentMouseLoc(NSPoint(x: fixedX, y: y))
            assistant.calculateDragAnimation(forTabBar: control)
            gids.append(assistant.collapsedGroupJoinTargetIdentifier() ?? "-")
            if let s = slotBeforeGroup {
                XCTAssertEqual(s.currentStep, 0,
                    "a transient no-pill tick opened a slot before the group (tick \(i)): step=\(s.currentStep) gids=\(gids)")
            }
        }
        // The join must hold on B through the one-frame NONE readings.
        XCTAssertTrue(gids.allSatisfy { $0 == "B" },
                      "a transient no-pill reading dropped the join off B: \(gids)")
    }

    // THE ENTRY FLICKER: on the FIRST tick after the drag enters the bar, the chip
    // frames still hold their pre-drag positions (the first layout pass hasn't
    // repacked them yet), so the pill under a stationary cursor can be the WRONG one
    // for that one tick before the layout settles. Acting on it flashes the join on
    // the wrong pill. The debounce must not commit any pill until a second
    // consecutive sighting, so the first-tick stale reading yields NO join, and the
    // join then lands on the correct pill -- never a wrong-pill flash.
    func testEntryStaleFrameDoesNotFlashWrongPill() {
        let G = buildTwoAdjacentMultiMemberGroups(membersA: 19, membersB: 3)
        // First settle with the cursor OFF the pills (over the left tab) so the pills
        // get their real packed positions and NO pill is committed -- the state just
        // before the drag reaches the group.
        for _ in 0..<4 {
            assistant.setCurrentMouseLoc(NSPoint(x: 20, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
        }
        let fixedX = G.chipB.frame.minX + 20   // over B, real position
        // Seed the ENTRY condition: shove the run right by A's width so that on the
        // FIRST tick over B, the stale frames put A (not B) under the cursor --
        // exactly the stale-first-frame the log showed at drag entry.
        G.chipA.frame = G.chipA.frame.offsetBy(dx: G.chipA.frame.width, dy: 0)
        G.chipB.frame = G.chipB.frame.offsetBy(dx: G.chipA.frame.width, dy: 0)

        var gids: [String] = []
        for _ in 0..<8 {
            assistant.setCurrentMouseLoc(NSPoint(x: fixedX, y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
            gids.append(assistant.collapsedGroupJoinTargetIdentifier() ?? "-")
        }
        // The wrong pill (A) must NEVER be highlighted, at entry or after.
        XCTAssertFalse(gids.contains("A"),
                       "the entry stale frame flashed the join on the wrong pill A: \(gids)")
        // And it must converge to the correct pill (B).
        XCTAssertEqual(gids.last, "B", "the join must settle on the hovered pill B: \(gids)")
    }

    // The CENTER third always joins, even between two pills.
    func testCenterThirdJoinsBetweenTwoPills() {
        let G = buildTwoAdjacentGroups()
        settleAt(center(G.chipB))
        XCTAssertEqual(assistant.collapsedGroupJoinTargetIdentifier(), "B",
                       "B's center third must join B regardless of the adjacent group")
    }

    // A tab dragged from ANOTHER window onto the CENTER of the SECOND of two
    // adjacent collapsed groups joins B via its closed front slot -- no gap opens.
    func testCrossWindowCenterJoinOfSecondGroup() {
        let G = buildTwoAdjacentGroups()
        let source = PSMTabBarControl(frame: NSRect(x: 0, y: 340, width: 800, height: 24))
        window.contentView?.addSubview(source)
        assistant.setSourceTabBar(source)   // cross-window

        for i in 0..<10 {
            assistant.setCurrentMouseLoc(NSPoint(x: center(G.chipB), y: 12))
            assistant.calculateDragAnimation(forTabBar: control)
            guard i >= 2 else { continue }   // let the pill-under-cursor debounce commit
            XCTAssertEqual(assistant.collapsedGroupJoinTargetIdentifier(), "B",
                           "the center of B from another window must join B, not flip to A")
            XCTAssertTrue(assistant.targetCell() === G.frontB,
                          "join must target B's (closed) front slot, got index \(targetIndex())")
        }
    }

}
