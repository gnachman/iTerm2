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
}
