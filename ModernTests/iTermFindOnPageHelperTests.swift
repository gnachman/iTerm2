//
//  iTermFindOnPageHelperTests.swift
//  iTerm2XCTests
//
//  Created by George Nachman on 2026-03-05.
//
//  Tests for iTermFindOnPageHelper, particularly bug #12716 where
//  removeSearchResultsInRange: incorrectly removes results that are
//  on the start line but BEFORE the start x-coordinate.

import XCTest
@testable import iTerm2SharedARC

class iTermFindOnPageHelperTests: XCTestCase {

    /// Test for bug #12716: When tail find searches from a mid-line position,
    /// results before that position on the same line should be preserved.
    ///
    /// The bug was in PTYTextView.m:4736 where VT100GridAbsCoordRange was converted
    /// to NSRange by discarding the x-coordinate. The fix adds a new method
    /// removeSearchResultsInCoordRange: that properly respects x-coordinates.
    ///
    /// This test verifies:
    /// 1. Adding results at (31, 12), (60, 12), and (5, 20)
    /// 2. Removing results in coord range (50, 12) to (2, 37)
    /// 3. Result at (31, 12) should be PRESERVED (it's before x=50 on line 12)
    /// 4. Result at (60, 12) should be removed (it's at/after x=50 on line 12)
    /// 5. Result at (5, 20) should be removed (it's on line 20, fully within range)
    func testRemoveSearchResultsInRange_ShouldNotRemoveResultsBeforeStartXOnStartLine() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()  // Initialize the search results container
        let width: Int32 = 80

        // Add a search result at position (31, 12) - "early" on line 12
        // This simulates finding "foo" at column 31 on line 12
        let result1 = SearchResult(fromX: 31, y: 12, toX: 33, y: 12)!
        helper.addSearchResult(result1, width: width)

        // Add a search result at position (60, 12) - "late" on line 12
        // This simulates finding "bar" at column 60 on line 12
        let result2 = SearchResult(fromX: 60, y: 12, toX: 62, y: 12)!
        helper.addSearchResult(result2, width: width)

        // Add a search result on line 20 - should definitely be removed
        let result3 = SearchResult(fromX: 5, y: 20, toX: 8, y: 20)!
        helper.addSearchResult(result3, width: width)

        // Verify all three results were added
        XCTAssertEqual(helper.searchResults.count, 3, "Should have 3 search results initially")

        // Simulate what happens when tail find reports having searched
        // from position (50, 12) to (2, 37).
        // The search started at x=50 on line 12, so results at x < 50 on
        // line 12 were never searched and should be preserved.
        let coordRange = VT100GridAbsCoordRange(
            start: VT100GridAbsCoord(x: 50, y: 12),
            end: VT100GridAbsCoord(x: 2, y: 37)
        )
        helper.removeSearchResults(with: coordRange)

        // Expected behavior:
        // - Result at (31, 12) should be PRESERVED (it's before x=50 on line 12)
        // - Result at (60, 12) should be removed (it's at/after x=50 on line 12)
        // - Result at (5, 20) should be removed (it's on line 20, fully within range)

        XCTAssertEqual(helper.searchResults.count, 1,
                       "Bug #12716: Result at (31, 12) should be preserved because it's before the search start x-coordinate of 50")

        // Verify the preserved result is the one at (31, 12)
        if helper.searchResults.count > 0 {
            let remainingResult = helper.searchResults.firstObject!
            XCTAssertEqual(remainingResult.internalStartX, 31,
                           "The preserved result should be at x=31")
            XCTAssertEqual(remainingResult.internalAbsStartY, 12,
                           "The preserved result should be on line 12")
        }
    }

    /// Test that results entirely within the removed range are correctly removed.
    /// This is a sanity check that the basic removal functionality works.
    func testRemoveSearchResultsInRange_RemovesResultsEntirelyWithinRange() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()  // Initialize the search results container
        let width: Int32 = 80

        // Add results on different lines
        let result1 = SearchResult(fromX: 10, y: 5, toX: 15, y: 5)!
        helper.addSearchResult(result1, width: width)

        let result2 = SearchResult(fromX: 10, y: 10, toX: 15, y: 10)!
        helper.addSearchResult(result2, width: width)

        let result3 = SearchResult(fromX: 10, y: 15, toX: 15, y: 15)!
        helper.addSearchResult(result3, width: width)

        let result4 = SearchResult(fromX: 10, y: 20, toX: 15, y: 20)!
        helper.addSearchResult(result4, width: width)

        XCTAssertEqual(helper.searchResults.count, 4)

        // Remove results on lines 10-14 using coord range (covers entire lines)
        let coordRange = VT100GridAbsCoordRange(
            start: VT100GridAbsCoord(x: 0, y: 10),
            end: VT100GridAbsCoord(x: 79, y: 14)
        )
        helper.removeSearchResults(with: coordRange)

        // Results on lines 5, 15, and 20 should remain, result on line 10 should be removed
        XCTAssertEqual(helper.searchResults.count, 3,
                       "Should have 3 results after removing line 10")
    }

    /// Test that results outside the removed range are preserved.
    func testRemoveSearchResultsInRange_PreservesResultsOutsideRange() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()  // Initialize the search results container
        let width: Int32 = 80

        // Add results outside the range we'll remove
        let result1 = SearchResult(fromX: 10, y: 5, toX: 15, y: 5)!
        helper.addSearchResult(result1, width: width)

        let result2 = SearchResult(fromX: 10, y: 30, toX: 15, y: 30)!
        helper.addSearchResult(result2, width: width)

        XCTAssertEqual(helper.searchResults.count, 2)

        // Remove results on lines 10-19 using coord range
        let coordRange = VT100GridAbsCoordRange(
            start: VT100GridAbsCoord(x: 0, y: 10),
            end: VT100GridAbsCoord(x: 79, y: 19)
        )
        helper.removeSearchResults(with: coordRange)

        // Both results should remain (line 5 and line 30 are outside the range)
        XCTAssertEqual(helper.searchResults.count, 2,
                       "Results outside the range should be preserved")
    }

    /// Additional test for bug #12716: Test with a multi-line search result that
    /// starts before the removal range's start x-coordinate.
    func testRemoveSearchResultsInRange_MultiLineResultStartingBeforeStartX() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()  // Initialize the search results container
        let width: Int32 = 80

        // Add a multi-line result that spans from (20, 12) to (10, 13)
        // This result starts at x=20 on line 12, before a hypothetical
        // search start of x=50 on line 12
        let multiLineResult = SearchResult(fromX: 20, y: 12, toX: 10, y: 13)!
        helper.addSearchResult(multiLineResult, width: width)

        // Add a result that should be removed (at x=60 on line 12)
        let laterResult = SearchResult(fromX: 60, y: 12, toX: 65, y: 12)!
        helper.addSearchResult(laterResult, width: width)

        XCTAssertEqual(helper.searchResults.count, 2)

        // Remove results in coord range starting at (50, 12)
        // The multi-line result starting at (20, 12) should be preserved
        // because its start x-coordinate is before x=50
        let coordRange = VT100GridAbsCoordRange(
            start: VT100GridAbsCoord(x: 50, y: 12),
            end: VT100GridAbsCoord(x: 79, y: 20)
        )
        helper.removeSearchResults(with: coordRange)

        // Result at (20, 12) should be preserved, result at (60, 12) should be removed
        XCTAssertEqual(helper.searchResults.count, 1,
                       "Bug #12716: Multi-line result starting at x=20 should be preserved")
    }
    // MARK: - Internal results mixed with external (porthole) results

    /// Mirrors the field trace in which a porthole at line 654 had eleven
    /// matches and the two matches in the grid at lines 1689 and 1690 were
    /// silently dropped from the result set, so the find bar never showed them.
    func testInternalResultsSurviveWhenPortholeResultsArePresent() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let width: Int32 = 194

        let owner = FakeExternalSearchResultOwner(absLine: 654, numLines: 10)
        for i in 0..<11 {
            let external = SearchResult(fromExternal: FakeExternalSearchResult(owner), index: Int64(i))!
            helper.addSearchResult(external, width: width)
        }
        XCTAssertEqual(helper.searchResults.count, 11)

        helper.addSearchResult(SearchResult(fromX: 20, y: 1690, toX: 29, y: 1690)!, width: width)
        helper.addSearchResult(SearchResult(fromX: 20, y: 1689, toX: 29, y: 1689)!, width: width)

        XCTAssertEqual(helper.searchResults.count, 13,
                       "Grid results must not be treated as duplicates of porthole results")
    }

    /// compare: must be antisymmetric across the internal/external boundary or the
    /// sorted result set misfiles and deduplicates results.
    func testCompareInternalAgainstExternalIsAntisymmetric() throws {
        let owner = FakeExternalSearchResultOwner(absLine: 654, numLines: 10)
        let external = SearchResult(fromExternal: FakeExternalSearchResult(owner), index: 0)!
        let internalResult = SearchResult(fromX: 20, y: 1690, toX: 29, y: 1690)!

        XCTAssertEqual(external.compare(internalResult), .orderedAscending)
        XCTAssertEqual(internalResult.compare(external), .orderedDescending)
    }

    // MARK: - Porthole results must respect the selected-command line range

    /// Clicking a command sets absLineRange so only that command is searched.
    /// The engine filters grid results by that range but porthole results are
    /// added unfiltered, so a porthole far outside the command can still be
    /// selected.
    func testExternalResultsOutsideAbsLineRangeAreNotAdded() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let width: Int32 = 194
        helper.absLineRange = NSRange(location: 1403, length: 290)

        let outsideOwner = FakeExternalSearchResultOwner(absLine: 654, numLines: 10)
        let insideOwner = FakeExternalSearchResultOwner(absLine: 1500, numLines: 10)
        helper.addExternalResults([FakeExternalSearchResult(outsideOwner),
                                   FakeExternalSearchResult(insideOwner)],
                                  width: width)

        XCTAssertEqual(helper.searchResults.count, 1,
                       "Only the porthole inside the selected command should contribute results")
        XCTAssertEqual(helper.searchResults.array.first?.externalAbsY, 1500)
    }

    // MARK: - Find next/previous with porthole results

    /// Runs a search whose results are one porthole result (if portholeLine is
    /// given) plus grid results on gridLines. The engine is inert, so the grid
    /// results stand in for what it would have found. Lets the helper select
    /// the first result in the given direction, then presses find next or
    /// find previous once. Returns the helper and the delegate so the caller
    /// can inspect what was selected.
    private func searchThenAdvance(forward: Bool,
                                   portholeLine: Int64?,
                                   portholeVisible: Bool = true,
                                   gridLines: [Int64],
                                   beforeAdvancing: (iTermFindOnPageHelper) -> Void = { _ in }) -> (iTermFindOnPageHelper, FakeFindOnPageHelperDelegate) {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let width: Int32 = 80
        let numberOfLines: Int32 = 400
        let engine = iTermSearchEngine(dataSource: nil, syncDistributor: nil)
        let delegate = FakeFindOnPageHelperDelegate(frame: .zero)
        delegate.helper = helper
        delegate.portholeOwner = portholeLine.map {
            FakeExternalSearchResultOwner(absLine: $0, numLines: 10, visible: portholeVisible)
        }
        helper.delegate = delegate

        func search() {
            helper.find("query",
                        forwardDirection: forward,
                        mode: .caseInsensitiveSubstring,
                        withOffset: 1,
                        searchEngine: engine,
                        numberOfLines: numberOfLines,
                        totalScrollbackOverflow: 0,
                        scrollToFirstResult: true,
                        force: false,
                        extendResultsAcrossSoftBoundaries: false)
        }
        func settle() {
            var progress = 0.0
            var range = NSRange(location: 0, length: 0)
            _ = helper.continueFind(&progress,
                                    rangeOut: &range,
                                    width: width,
                                    numberOfLines: numberOfLines,
                                    overflowAdjustment: 0)
        }

        // A new search: the delegate adds the porthole result and the grid
        // results stand in for the engine's.
        search()
        for line in gridLines {
            helper.addSearchResult(SearchResult(fromX: 0, y: line, toX: 4, y: line)!, width: width)
        }
        settle()
        delegate.wrapCount = 0
        beforeAdvancing(helper)

        // Find next or previous with the same query.
        search()
        settle()

        // The helper's delegate is unretained and the helper notifies it from
        // a block queued on the main queue, so detach the fake before it can
        // be freed out from under that block.
        helper.delegate = nil
        return (helper, delegate)
    }

    /// With the porthole result selected, find next must move on to the grid
    /// result below it instead of wrapping back to the porthole.
    func testFindNextAdvancesFromPortholeResultToGridResult() throws {
        let (helper, delegate) = searchThenAdvance(forward: true, portholeLine: 100, gridLines: [150]) { helper in
            XCTAssertEqual(helper.findCursor.type, .external, "Precondition: the porthole result is selected first")
        }
        let selected = try XCTUnwrap(helper.selectedResult)
        XCTAssertFalse(selected.isExternal, "Find next stayed on the porthole result")
        XCTAssertEqual(selected.internalAbsStartY, 150)
        XCTAssertEqual(delegate.wrapCount, 0, "There is a result after the cursor so no wrap is needed")
    }

    /// With the porthole result selected, find previous must move on to the
    /// grid result above it instead of wrapping back to the porthole.
    func testFindPreviousAdvancesFromPortholeResultToGridResult() throws {
        let (helper, delegate) = searchThenAdvance(forward: false, portholeLine: 100, gridLines: [50]) { helper in
            XCTAssertEqual(helper.findCursor.type, .external, "Precondition: the porthole result is selected first")
        }
        let selected = try XCTUnwrap(helper.selectedResult)
        XCTAssertFalse(selected.isExternal, "Find previous stayed on the porthole result")
        XCTAssertEqual(selected.internalAbsStartY, 50)
        XCTAssertEqual(delegate.wrapCount, 0, "There is a result before the cursor so no wrap is needed")
    }

    /// If the selected porthole result is removed (its line was invalidated or
    /// a command was selected that excludes it), find next must still advance
    /// from where it was rather than wrapping around.
    func testFindNextAfterSelectedPortholeResultIsRemovedAdvancesToGridResult() throws {
        let (helper, delegate) = searchThenAdvance(forward: true, portholeLine: 100, gridLines: [150]) { helper in
            XCTAssertEqual(helper.findCursor.type, .external, "Precondition: the porthole result is selected first")
            helper.removeSearchResults(in: NSRange(location: 100, length: 1))
            XCTAssertEqual(helper.searchResults.count, 1, "Precondition: only the grid result remains")
        }
        let selected = try XCTUnwrap(helper.selectedResult)
        XCTAssertFalse(selected.isExternal)
        XCTAssertEqual(selected.internalAbsStartY, 150)
        XCTAssertEqual(delegate.wrapCount, 0, "The grid result is after the removed cursor so no wrap is needed")
    }

    /// Removing the selected result must also drop it as the selected result,
    /// so the count shows no position and the object is not kept alive.
    func testSelectedResultIsDroppedWhenItsResultIsRemoved() throws {
        _ = searchThenAdvance(forward: true, portholeLine: 100, gridLines: [150]) { helper in
            XCTAssertTrue(helper.selectedResult?.isExternal ?? false, "Precondition: the porthole result is selected first")
            helper.removeSearchResults(in: NSRange(location: 100, length: 1))
            XCTAssertEqual(helper.currentIndex, 0)
            XCTAssertNil(helper.selectedResult)
        }
    }

    /// A porthole can be truncated so that some of its matches are not
    /// visible. Find next from a grid result must skip those, not just find
    /// next from a porthole result.
    func testFindNextFromGridResultSkipsHiddenPortholeResult() throws {
        let (helper, delegate) = searchThenAdvance(forward: true,
                                                   portholeLine: 100,
                                                   portholeVisible: false,
                                                   gridLines: [50, 150]) { helper in
            XCTAssertEqual(helper.findCursor.type, .coord, "Precondition: the grid result on line 50 is selected first")
        }
        let selected = try XCTUnwrap(helper.selectedResult)
        XCTAssertFalse(selected.isExternal, "Find next selected a porthole result that is not visible")
        XCTAssertEqual(selected.internalAbsStartY, 150)
        XCTAssertEqual(delegate.wrapCount, 0)
    }

    // MARK: - Removing a line that holds several porthole results

    /// A porthole with several matches puts several results on one line. When
    /// that line is invalidated every one of them must go, or the find bar
    /// keeps counting results that no longer exist.
    func testRemovingLineRemovesAllPortholeResultsOnIt() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let width: Int32 = 80
        let owner = FakeExternalSearchResultOwner(absLine: 100, numLines: 10)
        for i in 0..<3 {
            helper.addSearchResult(SearchResult(fromExternal: FakeExternalSearchResult(owner), index: Int64(i))!,
                                   width: width)
        }
        helper.addSearchResult(SearchResult(fromX: 0, y: 50, toX: 4, y: 50)!, width: width)
        XCTAssertEqual(helper.searchResults.count, 4)

        helper.removeSearchResults(in: NSRange(location: 100, length: 1))

        XCTAssertEqual(helper.searchResults.count, 1)
        let remaining = try XCTUnwrap(helper.searchResults.array.first)
        XCTAssertFalse(remaining.isExternal)
        XCTAssertEqual(remaining.internalAbsStartY, 50)
    }

    // MARK: - Tail find and porthole results

    /// After each find, the tail find re-searches the screen and replaces the
    /// results in the range it covered. It only searches terminal text, so it
    /// must leave porthole results in that range alone or they vanish after
    /// the first Find Next.
    func testRemovingResultsInSearchedRangeKeepsPortholeResults() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let width: Int32 = 80
        let owner = FakeExternalSearchResultOwner(absLine: 100, numLines: 10)
        helper.addSearchResult(SearchResult(fromExternal: FakeExternalSearchResult(owner), index: 0)!, width: width)
        helper.addSearchResult(SearchResult(fromX: 0, y: 95, toX: 4, y: 95)!, width: width)
        helper.addSearchResult(SearchResult(fromX: 0, y: 105, toX: 4, y: 105)!, width: width)
        XCTAssertEqual(helper.searchResults.count, 3)

        helper.removeSearchResults(with: VT100GridAbsCoordRangeMake(0, 90, 80, 110))

        XCTAssertEqual(helper.searchResults.count, 1, "Only the grid results are replaced by the tail find")
        XCTAssertTrue(helper.searchResults.array.first?.isExternal ?? false)
    }

    // MARK: - Portholes that appear during a search

    /// A porthole rendered while a search is active takes part in it.
    func testContainerAppearingDuringSearchIsSearched() throws {
        let (helper, delegate) = makeSearchingHelper()
        XCTAssertEqual(helper.searchResults.count, 1, "Precondition: one grid result")

        delegate.portholeOwner = FakeExternalSearchResultOwner(absLine: 100, numLines: 10)
        helper.externalContainersDidChange()

        XCTAssertEqual(helper.searchResults.count, 2)
        XCTAssertTrue(helper.searchResults.array.contains { $0.isExternal })
        helper.delegate = nil
    }

    /// Without an active search there is nothing to search a new porthole for.
    func testContainerAppearingWithoutSearchIsNotSearched() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let delegate = FakeFindOnPageHelperDelegate(frame: .zero)
        delegate.helper = helper
        delegate.portholeOwner = FakeExternalSearchResultOwner(absLine: 100, numLines: 10)
        helper.delegate = delegate

        helper.externalContainersDidChange()

        XCTAssertEqual(delegate.externalSearchCount, 0)
        XCTAssertEqual(helper.searchResults.count, 0)
        helper.delegate = nil
    }

    /// A helper with an active search for “query” that found one grid result on line 50.
    private func makeSearchingHelper() -> (iTermFindOnPageHelper, FakeFindOnPageHelperDelegate) {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        let delegate = FakeFindOnPageHelperDelegate(frame: .zero)
        delegate.helper = helper
        helper.delegate = delegate
        helper.find("query",
                    forwardDirection: true,
                    mode: .caseInsensitiveSubstring,
                    withOffset: 1,
                    searchEngine: iTermSearchEngine(dataSource: nil, syncDistributor: nil),
                    numberOfLines: 400,
                    totalScrollbackOverflow: 0,
                    scrollToFirstResult: false,
                    force: false,
                    extendResultsAcrossSoftBoundaries: false)
        helper.addSearchResult(SearchResult(fromX: 0, y: 50, toX: 4, y: 50)!, width: 80)
        return (helper, delegate)
    }

    // MARK: - Hidden portholes

    /// A hidden porthole reports line -1. Its results must not be added even
    /// when no command is selected: a negative line is not a valid location.
    func testHiddenPortholeResultsAreNotAdded() throws {
        let helper = iTermFindOnPageHelper()
        helper.clearHighlights()
        XCTAssertEqual(helper.absLineRange.length, 0, "Precondition: no command is selected")
        let hidden = FakeExternalSearchResultOwner(absLine: -1, numLines: 10)
        helper.addExternalResults([FakeExternalSearchResult(hidden)], width: 80)
        XCTAssertEqual(helper.searchResults.count, 0)
        XCTAssertFalse(helper.absLineIsInSelectedCommand(-1))
    }
}

/// Stands in for a porthole that owns external search results.
private final class FakeExternalSearchResultOwner: ExternalSearchResultOwner {
    let absLine: Int64
    let numLines: Int32
    let visible: Bool

    init(absLine: Int64, numLines: Int32, visible: Bool = true) {
        self.absLine = absLine
        self.numLines = numLines
        self.visible = visible
    }

    func select(_ result: ExternalSearchResult) {}
    func searchResultIsVisible(_ result: ExternalSearchResult) -> Bool { visible }
    func remove(_ result: ExternalSearchResult) {}
}

private final class FakeExternalSearchResult: ExternalSearchResult {
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FakeExternalSearchResult else {
            return false
        }
        return other === self
    }
}

/// Minimal delegate: supplies one porthole result when asked to search
/// externally and counts wraparounds.
private final class FakeFindOnPageHelperDelegate: NSView, iTermFindOnPageHelperDelegate {
    weak var helper: iTermFindOnPageHelper?
    var portholeOwner: FakeExternalSearchResultOwner?
    var wrapCount = 0
    var externalSearchCount = 0

    func find(onPageSelect range: VT100GridCoordRange,
              logicalWindow: VT100GridRange,
              wrapped: Bool) {}

    func find(onPageSelectExternalResult result: ExternalSearchResult) -> VT100GridCoordRange {
        return VT100GridCoordRange(start: VT100GridCoord(x: 0, y: Int32(result.absLine)),
                                   end: VT100GridCoord(x: 0, y: Int32(result.absLine)))
    }

    func find(onPageDidWrapForwards directionIsForwards: Bool) {
        wrapCount += 1
    }

    func find(onPageRevealRange range: VT100GridCoordRange) {}
    func findOnPageFailed() {}
    func findOnPageOverflowAdjustment() -> Int64 { 0 }
    func findOnPageRangeOfVisibleLines() -> NSRange { NSRange(location: 0, length: 400) }
    func findOnPageLocationsDidChange() {}
    func findOnPageSelectedResultDidChange() {}

    func findOnPageHelperSearchExternally(for query: String, mode: iTermFindMode) {
        externalSearchCount += 1
        guard let helper, let portholeOwner else {
            return
        }
        helper.addExternalResults([FakeExternalSearchResult(portholeOwner)], width: 80)
    }

    func findOnPageHelperRemoveExternalHighlights() {}
    func findOnPageHelperRequestRedraw() {}
    func findOnPageHelperRemoveExternalHighlights(from externalSearchResult: ExternalSearchResult) {}
}
