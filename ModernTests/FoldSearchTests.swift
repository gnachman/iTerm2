//
//  FoldSearchTests.swift
//  iTerm2XCTests
//
//  Created by George Nachman on 3/25/26.
//
//  Tests for FoldSearchResult, FoldSearchResultOwner, and FoldSearchEngine.

import XCTest
@testable import iTerm2SharedARC

// MARK: - FoldSearchResultOwner Tests

class FoldSearchResultOwnerTests: XCTestCase {

    func testInit() {
        let owner = FoldSearchResultOwner(absLine: 42)
        XCTAssertEqual(owner.absLine, 42)
        XCTAssertEqual(owner.numLines, 1)
    }

    func testAbsLineIsMutable() {
        let owner = FoldSearchResultOwner(absLine: 10)
        owner.absLine = 99
        XCTAssertEqual(owner.absLine, 99)
    }

    func testSearchResultIsVisibleAlwaysReturnsTrue() {
        let owner = FoldSearchResultOwner(absLine: 0)
        let mark = makeFoldMark(lines: ["test"])
        let result = FoldSearchResult(
            startX: 0, startY: 0, endX: 3, endY: 0,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        XCTAssertTrue(owner.searchResultIsVisible(result))
    }
}

// MARK: - FoldSearchResult Tests

class FoldSearchResultTests: XCTestCase {

    func testInitSetsAllProperties() {
        let owner = FoldSearchResultOwner(absLine: 100)
        let mark = makeFoldMark(lines: ["hello world"])
        let matchRange = NSRange(location: 2, length: 5)

        let result = FoldSearchResult(
            startX: 6, startY: 0, endX: 10, endY: 0,
            snippetText: "hello world", snippetMatchRange: matchRange,
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertEqual(result.startX, 6)
        XCTAssertEqual(result.startY, 0)
        XCTAssertEqual(result.endX, 10)
        XCTAssertEqual(result.endY, 0)
        XCTAssertEqual(result.snippetText, "hello world")
        XCTAssertEqual(result.snippetMatchRange, matchRange)
        XCTAssertTrue(result.foldMark === mark)
        XCTAssertEqual(result.searchWidth, 80)
        XCTAssertEqual(result.absLine, 100)
        XCTAssertEqual(result.numLines, 1)
    }

    func testFoldMarkIsWeakReference() {
        let owner = FoldSearchResultOwner(absLine: 0)
        var result: FoldSearchResult!
        autoreleasepool {
            let mark = makeFoldMark(lines: ["disposable"])
            result = FoldSearchResult(
                startX: 0, startY: 0, endX: 9, endY: 0,
                snippetText: "disposable", snippetMatchRange: NSRange(location: 0, length: 10),
                foldMark: mark, searchWidth: 80, owner: owner)
            XCTAssertNotNil(result.foldMark)
        }
        // FoldMark is an NSObject inside an autoreleasepool with no other strong
        // references, so ARC should have deallocated it.
        XCTAssertNil(result.foldMark, "foldMark should be nil after the sole strong reference is released")
    }

    // MARK: - isEqual

    func testEqualResultsAreEqual() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "different snippet", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertEqual(a, b)
    }

    func testDifferentStartXMakesNotEqual() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 99, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertNotEqual(a, b)
    }

    func testDifferentStartYMakesNotEqual() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 1, startY: 99, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertNotEqual(a, b)
    }

    func testDifferentEndXMakesNotEqual() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 1, startY: 2, endX: 99, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertNotEqual(a, b)
    }

    func testDifferentEndYMakesNotEqual() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 99,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertNotEqual(a, b)
    }

    func testDifferentOwnerMakesNotEqual() {
        let owner1 = FoldSearchResultOwner(absLine: 50)
        let owner2 = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner1)
        let b = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner2)

        XCTAssertNotEqual(a, b)
    }

    func testIsNotEqualToNonFoldSearchResult() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let result = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertFalse(result.isEqual("not a search result"))
        XCTAssertFalse(result.isEqual(nil))
    }

    // MARK: - hash

    func testEqualResultsHaveSameHash() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 1, startY: 2, endX: 3, endY: 4,
            snippetText: "other", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        XCTAssertEqual(a.hash, b.hash)
    }

    func testDifferentCoordinatesProduceDifferentHashes() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let a = FoldSearchResult(
            startX: 0, startY: 0, endX: 5, endY: 0,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)
        let b = FoldSearchResult(
            startX: 10, startY: 5, endX: 20, endY: 10,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        // Hash collisions are theoretically possible but extremely unlikely for these values.
        XCTAssertNotEqual(a.hash, b.hash)
    }

    // MARK: - internalSearchResult

    func testInternalSearchResultSingleLine() {
        let owner = FoldSearchResultOwner(absLine: 100)
        let mark = makeFoldMark(lines: ["test"])

        let foldResult = FoldSearchResult(
            startX: 5, startY: 0, endX: 8, endY: 0,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        let internal_ = foldResult.internalSearchResult(foldAbsLine: 100)
        XCTAssertEqual(internal_.internalStartX, 5)
        XCTAssertEqual(internal_.internalEndX, 8)
        XCTAssertEqual(internal_.internalAbsStartY, 100)
        XCTAssertEqual(internal_.internalAbsEndY, 100)
    }

    func testInternalSearchResultMultiLine() {
        let owner = FoldSearchResultOwner(absLine: 200)
        let mark = makeFoldMark(lines: ["line1", "line2", "line3"])

        let foldResult = FoldSearchResult(
            startX: 2, startY: 1, endX: 4, endY: 2,
            snippetText: "ne2\nline3", snippetMatchRange: NSRange(location: 0, length: 5),
            foldMark: mark, searchWidth: 80, owner: owner)

        let internal_ = foldResult.internalSearchResult(foldAbsLine: 200)
        XCTAssertEqual(internal_.internalStartX, 2)
        XCTAssertEqual(internal_.internalEndX, 4)
        XCTAssertEqual(internal_.internalAbsStartY, 201)  // 200 + 1
        XCTAssertEqual(internal_.internalAbsEndY, 202)    // 200 + 2
    }

    func testInternalSearchResultWithLargeAbsLine() {
        let owner = FoldSearchResultOwner(absLine: 1_000_000)
        let mark = makeFoldMark(lines: ["test"])

        let foldResult = FoldSearchResult(
            startX: 0, startY: 3, endX: 10, endY: 5,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        let internal_ = foldResult.internalSearchResult(foldAbsLine: 1_000_000)
        XCTAssertEqual(internal_.internalAbsStartY, 1_000_003)
        XCTAssertEqual(internal_.internalAbsEndY, 1_000_005)
    }

    func testInternalSearchResultAtFoldStart() {
        let owner = FoldSearchResultOwner(absLine: 50)
        let mark = makeFoldMark(lines: ["test"])

        let foldResult = FoldSearchResult(
            startX: 0, startY: 0, endX: 3, endY: 0,
            snippetText: "test", snippetMatchRange: NSRange(location: 0, length: 4),
            foldMark: mark, searchWidth: 80, owner: owner)

        let internal_ = foldResult.internalSearchResult(foldAbsLine: 50)
        XCTAssertEqual(internal_.internalStartX, 0)
        XCTAssertEqual(internal_.internalAbsStartY, 50)
        XCTAssertEqual(internal_.internalEndX, 3)
        XCTAssertEqual(internal_.internalAbsEndY, 50)
    }
}

// MARK: - FoldSearchEngine Tests

class FoldSearchEngineTests: XCTestCase {
    private let width: Int32 = 80

    // Helper to search with the results/finished API and collect all results.
    private func searchCollectingResults(
        engine: FoldSearchEngine,
        query: String,
        mode: iTermFindMode,
        marks: [FoldMarkReading],
        absLines: [NSNumber],
        timeout: TimeInterval = 5
    ) -> [ExternalSearchResult] {
        var allResults = [ExternalSearchResult]()
        let finished = expectation(description: "search finished")

        engine.search(
            query: query,
            mode: mode,
            foldMarks: marks,
            absLines: absLines,
            width: width,
            results: { results in
                allResults.append(contentsOf: results)
            },
            finished: {
                finished.fulfill()
            })

        waitForExpectations(timeout: timeout)
        return allResults
    }

    func testSearchFindsSimpleMatch() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["hello world"])

        let results = searchCollectingResults(
            engine: engine, query: "world", mode: .smartCaseSensitivity,
            marks: [mark], absLines: [NSNumber(value: 100)])

        XCTAssertEqual(results.count, 1)
        if let result = results.first as? FoldSearchResult {
            XCTAssertEqual(result.startX, 6)
            XCTAssertEqual(result.endX, 10)
            XCTAssertEqual(result.startY, 0)
            XCTAssertEqual(result.endY, 0)
            XCTAssertTrue(result.snippetText.contains("world"))
        } else {
            XCTFail("Expected FoldSearchResult")
        }
    }

    func testSearchFindsNoMatchForMissingQuery() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["hello world"])

        let results = searchCollectingResults(
            engine: engine, query: "xyz_not_found", mode: .smartCaseSensitivity,
            marks: [mark], absLines: [NSNumber(value: 100)], timeout: 2)

        XCTAssertEqual(results.count, 0)
    }

    func testSearchFindsMultipleMatchesInOneFold() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["foo bar foo baz foo"])

        let results = searchCollectingResults(
            engine: engine, query: "foo", mode: .smartCaseSensitivity,
            marks: [mark], absLines: [NSNumber(value: 0)])

        XCTAssertEqual(results.count, 3)
    }

    func testSearchAcrossMultipleFolds() {
        let engine = FoldSearchEngine()
        let mark1 = makeFoldMark(lines: ["alpha beta"])
        let mark2 = makeFoldMark(lines: ["gamma delta"])
        let mark3 = makeFoldMark(lines: ["no hits here"])

        let results = searchCollectingResults(
            engine: engine, query: "a", mode: .caseSensitiveSubstring,
            marks: [mark1, mark2, mark3],
            absLines: [NSNumber(value: 10), NSNumber(value: 20), NSNumber(value: 30)])

        // "alpha beta": a(0), a(4), a(9) → 3
        // "gamma delta": a(1), a(4), a(10) → 3
        // "no hits here" → 0
        XCTAssertEqual(results.count, 6)
    }

    func testSearchSkipsFoldsWithNoSavedLines() {
        let engine = FoldSearchEngine()
        let emptyMark = makeFoldMark(lines: [])
        let goodMark = makeFoldMark(lines: ["findme"])

        let results = searchCollectingResults(
            engine: engine, query: "findme", mode: .smartCaseSensitivity,
            marks: [emptyMark, goodMark],
            absLines: [NSNumber(value: 10), NSNumber(value: 20)])

        XCTAssertEqual(results.count, 1)
        if let result = results.first as? FoldSearchResult {
            XCTAssertEqual(result.absLine, 20)
        }
    }

    func testCancelStopsSearch() {
        let engine = FoldSearchEngine()
        var marks = [FoldMarkReading]()
        var absLines = [NSNumber]()
        for i in 0..<1000 {
            let lines = (0..<10).map { j in "searchable content fold \(i) line \(j) with extra padding text" }
            marks.append(makeFoldMark(lines: lines))
            absLines.append(NSNumber(value: i * 100))
        }

        var resultCallCount = 0
        let finished = expectation(description: "may or may not finish")
        finished.isInverted = true

        engine.search(
            query: "searchable",
            mode: .smartCaseSensitivity,
            foldMarks: marks,
            absLines: absLines,
            width: width,
            results: { _ in resultCallCount += 1 },
            finished: { finished.fulfill() })

        engine.cancel()

        waitForExpectations(timeout: 1)
        XCTAssertLessThan(resultCallCount, 1000)
    }

    func testNewSearchCancelsPrevious() {
        let engine = FoldSearchEngine()

        var marks = [FoldMarkReading]()
        var absLines = [NSNumber]()
        for i in 0..<500 {
            let lines = (0..<10).map { j in "hello world fold \(i) line \(j) with padding" }
            marks.append(makeFoldMark(lines: lines))
            absLines.append(NSNumber(value: i * 100))
        }

        var firstCallCount = 0
        engine.search(
            query: "hello",
            mode: .smartCaseSensitivity,
            foldMarks: marks,
            absLines: absLines,
            width: width,
            results: { _ in firstCallCount += 1 },
            finished: {})

        let singleMark = makeFoldMark(lines: ["world"])
        let results = searchCollectingResults(
            engine: engine, query: "world", mode: .smartCaseSensitivity,
            marks: [singleMark], absLines: [NSNumber(value: 0)])

        XCTAssertEqual(results.count, 1)
        XCTAssertLessThan(firstCallCount, 500)
    }

    func testSearchWithCaseInsensitiveMode() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["Hello WORLD hello"])

        let results = searchCollectingResults(
            engine: engine, query: "hello", mode: .caseInsensitiveSubstring,
            marks: [mark], absLines: [NSNumber(value: 0)])

        XCTAssertEqual(results.count, 2)
    }

    func testSearchWithCaseSensitiveMode() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["Hello WORLD hello"])

        let results = searchCollectingResults(
            engine: engine, query: "hello", mode: .caseSensitiveSubstring,
            marks: [mark], absLines: [NSNumber(value: 0)])

        XCTAssertEqual(results.count, 1)
    }

    func testSearchResultOwnerIsPerFold() {
        let engine = FoldSearchEngine()
        let mark1 = makeFoldMark(lines: ["findme"])
        let mark2 = makeFoldMark(lines: ["findme"])

        let results = searchCollectingResults(
            engine: engine, query: "findme", mode: .smartCaseSensitivity,
            marks: [mark1, mark2],
            absLines: [NSNumber(value: 10), NSNumber(value: 20)])

        let absLines = Set(results.map { $0.absLine })
        XCTAssertEqual(absLines.count, 2)
        XCTAssertTrue(absLines.contains(10))
        XCTAssertTrue(absLines.contains(20))
    }

    func testSnippetContainsMatchText() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["this is a test of the snippet extraction"])

        let results = searchCollectingResults(
            engine: engine, query: "snippet", mode: .smartCaseSensitivity,
            marks: [mark], absLines: [NSNumber(value: 0)])

        if let result = results.first as? FoldSearchResult {
            XCTAssertTrue(result.snippetText.contains("snippet"))
            let nsSnippet = result.snippetText as NSString
            let matched = nsSnippet.substring(with: result.snippetMatchRange)
            XCTAssertEqual(matched, "snippet",
                           "snippetMatchRange should exactly cover the query within the snippet")
        } else {
            XCTFail("Expected FoldSearchResult")
        }
    }

    func testSearchResultCoordinates() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["0123456789match rest"])

        let results = searchCollectingResults(
            engine: engine, query: "match", mode: .smartCaseSensitivity,
            marks: [mark], absLines: [NSNumber(value: 50)])

        XCTAssertEqual(results.count, 1)
        if let result = results.first as? FoldSearchResult {
            XCTAssertEqual(result.startX, 10)
            XCTAssertEqual(result.endX, 14)
            XCTAssertEqual(result.startY, 0)
            XCTAssertEqual(result.endY, 0)
            XCTAssertEqual(result.absLine, 50)
        }
    }

    func testFinishedCalledEvenWithNoResults() {
        let engine = FoldSearchEngine()
        let mark = makeFoldMark(lines: ["no match here"])

        let finished = expectation(description: "finished called")
        engine.search(
            query: "xyz",
            mode: .smartCaseSensitivity,
            foldMarks: [mark],
            absLines: [NSNumber(value: 0)],
            width: width,
            results: { _ in XCTFail("Should not have results") },
            finished: { finished.fulfill() })

        waitForExpectations(timeout: 5)
    }
}

// MARK: - Helpers

/// Create a FoldMark with the given lines of text as its saved content.
private func makeFoldMark(lines: [String]) -> FoldMark {
    let scas: [ScreenCharArray]? = lines.isEmpty ? nil : lines.map { line in
        screenCharArrayForTest(line, eol: EOL_HARD)
    }
    return FoldMark(savedLines: scas, savedITOs: [], promptLength: 0, imageCodes: [], width: 80)
}

/// Create a ScreenCharArray from a string for testing purposes.
private func screenCharArrayForTest(_ string: String, eol: Int32) -> ScreenCharArray {
    return ScreenCharArray.create(
        string: string,
        predecessor: nil,
        foreground: screen_char_t.defaultForeground,
        background: screen_char_t.defaultBackground,
        continuation: screen_char_t.defaultForeground.with(code: unichar(eol)),
        metadata: iTermMetadataDefault(),
        ambiguousIsDoubleWidth: false,
        normalization: .none,
        unicodeVersion: 9
    ).sca
}
