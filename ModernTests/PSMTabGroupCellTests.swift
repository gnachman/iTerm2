//
//  PSMTabGroupCellTests.swift
//  iTerm2XCTests
//
//  Unit tests for the window-free tab-group chip-cell helpers: chip-cell
//  normalization (one chip before each run) and the cell-index <-> tab-index
//  conversions the drag/drop code relies on.
//

import XCTest
@testable import iTerm2SharedARC

final class PSMTabGroupCellTests: XCTestCase {
    private var control: PSMTabBarControl!

    override func setUp() {
        super.setUp()
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    }

    override func tearDown() {
        control = nil
        super.tearDown()
    }

    private func tabCell(_ groupID: String?) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.tabGroupIdentifier = groupID
        return cell
    }

    private func chipCell(_ groupID: String) -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isTabGroupChip = true
        cell.tabGroupIdentifier = groupID
        return cell
    }

    private func placeholderCell() -> PSMTabBarCell {
        let cell = PSMTabBarCell(controlView: control)!
        cell.isPlaceholder = true
        return cell
    }

    // Render a cell list as tokens: "-" ungrouped tab, "A" grouped tab,
    // "chip:A" a chip, "ph" a placeholder, so a single equality assert
    // describes the structure.
    private func tokens(_ cells: [PSMTabBarCell]) -> [String] {
        return cells.map { cell in
            if cell.isPlaceholder {
                return "ph"
            }
            if cell.isTabGroupChip {
                return "chip:\(cell.tabGroupIdentifier ?? "")"
            }
            return cell.tabGroupIdentifier ?? "-"
        }
    }

    // MARK: - Normalization

    func testNoGroupsInsertsNoChips() {
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into:
                                            [tabCell(nil), tabCell(nil), tabCell(nil)],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["-", "-", "-"])
    }

    func testOneRunAtStart() {
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into:
                                            [tabCell("A"), tabCell("A"), tabCell(nil)],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["chip:A", "A", "A", "-"])
    }

    func testTwoRuns() {
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into:
                                            [tabCell(nil), tabCell("A"), tabCell("A"), tabCell(nil), tabCell("B")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["-", "chip:A", "A", "A", "-", "chip:B", "B"])
    }

    func testAdjacentDifferentGroupsEachGetChip() {
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into:
                                            [tabCell("A"), tabCell("B")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["chip:A", "A", "chip:B", "B"])
    }

    func testNonContiguousSameGroupGetsTwoChips() {
        // Documents current behavior; contiguity is enforced by the drop
        // logic, not here, so a split run yields a chip per run.
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into:
                                            [tabCell("A"), tabCell(nil), tabCell("A")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["chip:A", "A", "-", "chip:A", "A"])
    }

    func testStrayChipsInInputAreDropped() {
        let out = PSMTabBarControl.cellsByInsertingTabGroupChips(into:
                                            [chipCell("A"), tabCell("A"), tabCell("A")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["chip:A", "A", "A"])
    }

    // MARK: - Drag-time chip insertion (placeholders transparent)

    func testDragChipsPlaceholdersPassThroughUngrouped() {
        // A placeholder-laden ungrouped bar gets no chips.
        let out = PSMTabBarControl.cellsByInsertingDragChips(into:
                                            [placeholderCell(), tabCell(nil), placeholderCell(), tabCell(nil), placeholderCell()],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["ph", "-", "ph", "-", "ph"])
    }

    func testDragChipInsertedAfterPrecedingPlaceholder() {
        // The chip glues to its run's first tab, sitting just after that tab's
        // leading placeholder (the drop-before-group slot stays outside the group).
        let out = PSMTabBarControl.cellsByInsertingDragChips(into:
                                            [placeholderCell(), tabCell(nil), placeholderCell(), tabCell("A"), placeholderCell(), tabCell("A"), placeholderCell()],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["ph", "-", "ph", "chip:A", "A", "ph", "A", "ph"])
    }

    func testDragChipRunSurvivesSplittingPlaceholder() {
        // A group whose tabs are separated only by a placeholder (e.g. the gap
        // left by the dragged tab) stays a single run -> exactly one chip.
        let out = PSMTabBarControl.cellsByInsertingDragChips(into:
                                            [tabCell("A"), placeholderCell(), tabCell("A")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["chip:A", "A", "ph", "A"])
    }

    func testDragChipsStrayChipsDropped() {
        let out = PSMTabBarControl.cellsByInsertingDragChips(into:
                                            [chipCell("A"), placeholderCell(), tabCell("A"), tabCell("A")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["ph", "chip:A", "A", "A"])
    }

    func testDragChipsAdjacentGroupsAcrossPlaceholder() {
        // Two different groups separated by a placeholder each keep their chip.
        let out = PSMTabBarControl.cellsByInsertingDragChips(into:
                                            [tabCell("A"), placeholderCell(), tabCell("B")],
                                         controlView: control)
        XCTAssertEqual(tokens(out), ["chip:A", "A", "ph", "chip:B", "B"])
    }

    // MARK: - Index conversion

    func testCellIndexForTabIndexSkipsChips() {
        // tokens: [A(tab), chip:A, A(tab), -(tab)]  -> tab cells at 0,2,3
        let cells = [tabCell("A"), chipCell("A"), tabCell("A"), tabCell(nil)]
        XCTAssertEqual(PSMTabBarControl.cellIndex(forTabIndex: 0, in: cells), 0)
        XCTAssertEqual(PSMTabBarControl.cellIndex(forTabIndex: 1, in: cells), 2)
        XCTAssertEqual(PSMTabBarControl.cellIndex(forTabIndex: 2, in: cells), 3)
        // Past the last tab -> append position (cells.count).
        XCTAssertEqual(PSMTabBarControl.cellIndex(forTabIndex: 3, in: cells), 4)
    }

    func testTabIndexForCellIndexSkipsChips() {
        let cells = [tabCell("A"), chipCell("A"), tabCell("A"), tabCell(nil)]
        XCTAssertEqual(PSMTabBarControl.tabIndex(forCellIndex: 0, in: cells), 0)
        XCTAssertEqual(PSMTabBarControl.tabIndex(forCellIndex: 1, in: cells), NSNotFound)
        XCTAssertEqual(PSMTabBarControl.tabIndex(forCellIndex: 2, in: cells), 1)
        XCTAssertEqual(PSMTabBarControl.tabIndex(forCellIndex: 3, in: cells), 2)
        XCTAssertEqual(PSMTabBarControl.tabIndex(forCellIndex: 99, in: cells), NSNotFound)
    }

    // Round-trip: every tab cell's index maps to a cell index that maps back.
    func testIndexRoundTrip() {
        let cells = [chipCell("A"), tabCell("A"), tabCell("A"), tabCell(nil), chipCell("B"), tabCell("B")]
        for tabIndex in 0..<3 {
            let cellIndex = PSMTabBarControl.cellIndex(forTabIndex: tabIndex, in: cells)
            XCTAssertEqual(PSMTabBarControl.tabIndex(forCellIndex: cellIndex, in: cells), tabIndex)
        }
    }
}
