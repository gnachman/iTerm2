//
//  AccessibilityDeletionDetectionTests.swift
//  ModernTests
//
//  Created by Claude on 3/14/26.
//

import XCTest
@testable import iTerm2SharedARC

// MARK: - GridCoordArray Tests

final class GridCoordArrayTests: XCTestCase {

    // MARK: - rangeOfIndices(xFrom:to:) Tests

    func testRangeOfIndicesEmptyArray() {
        let coords = GridCoordArray()
        let range = coords.rangeOfIndices(xFrom: 0, to: 5)
        XCTAssertEqual(range.location, NSNotFound)
        XCTAssertEqual(range.length, 0)
    }

    func testRangeOfIndicesNoMatch() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(10, 0))
        coords.append(coord:VT100GridCoordMake(11, 0))
        coords.append(coord:VT100GridCoordMake(12, 0))

        let range = coords.rangeOfIndices(xFrom: 0, to: 5)
        XCTAssertEqual(range.location, NSNotFound)
        XCTAssertEqual(range.length, 0)
    }

    func testRangeOfIndicesSingleMatch() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(0, 0))
        coords.append(coord:VT100GridCoordMake(1, 0))
        coords.append(coord:VT100GridCoordMake(2, 0))
        coords.append(coord:VT100GridCoordMake(3, 0))

        let range = coords.rangeOfIndices(xFrom: 1, to: 2)
        XCTAssertEqual(range.location, 1)
        XCTAssertEqual(range.length, 1)
    }

    func testRangeOfIndicesMultipleMatches() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(0, 0))
        coords.append(coord:VT100GridCoordMake(1, 0))
        coords.append(coord:VT100GridCoordMake(2, 0))
        coords.append(coord:VT100GridCoordMake(3, 0))
        coords.append(coord:VT100GridCoordMake(4, 0))

        let range = coords.rangeOfIndices(xFrom: 1, to: 4)
        XCTAssertEqual(range.location, 1)
        XCTAssertEqual(range.length, 3)
    }

    func testRangeOfIndicesEntireRange() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(0, 0))
        coords.append(coord:VT100GridCoordMake(1, 0))
        coords.append(coord:VT100GridCoordMake(2, 0))

        let range = coords.rangeOfIndices(xFrom: 0, to: 3)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, 3)
    }

    func testRangeOfIndicesWithSurrogatePair() {
        // Simulate a surrogate pair (emoji) taking 2 UTF-16 code units at position x=5
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(4, 0))  // index 0
        coords.append(coord:VT100GridCoordMake(5, 0))  // index 1 (high surrogate)
        coords.append(coord:VT100GridCoordMake(5, 0))  // index 2 (low surrogate, same x)
        coords.append(coord:VT100GridCoordMake(6, 0))  // index 3

        // Range for x=5 should include both surrogate indices
        let range = coords.rangeOfIndices(xFrom: 5, to: 6)
        XCTAssertEqual(range.location, 1)
        XCTAssertEqual(range.length, 2)
    }

    // MARK: - indexOfFirstCoord(xGreaterOrEqual:) Tests

    func testIndexOfFirstCoordEmptyArray() {
        let coords = GridCoordArray()
        let index = coords.indexOfFirstCoord(xGreaterOrEqual: 0)
        XCTAssertEqual(index, NSNotFound)
    }

    func testIndexOfFirstCoordNoMatch() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(0, 0))
        coords.append(coord:VT100GridCoordMake(1, 0))
        coords.append(coord:VT100GridCoordMake(2, 0))

        let index = coords.indexOfFirstCoord(xGreaterOrEqual: 10)
        XCTAssertEqual(index, NSNotFound)
    }

    func testIndexOfFirstCoordExactMatch() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(0, 0))
        coords.append(coord:VT100GridCoordMake(5, 0))
        coords.append(coord:VT100GridCoordMake(10, 0))

        let index = coords.indexOfFirstCoord(xGreaterOrEqual: 5)
        XCTAssertEqual(index, 1)
    }

    func testIndexOfFirstCoordGreaterMatch() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(0, 0))
        coords.append(coord:VT100GridCoordMake(5, 0))
        coords.append(coord:VT100GridCoordMake(10, 0))

        let index = coords.indexOfFirstCoord(xGreaterOrEqual: 3)
        XCTAssertEqual(index, 1)
    }

    func testIndexOfFirstCoordFirstElement() {
        let coords = GridCoordArray()
        coords.append(coord:VT100GridCoordMake(5, 0))
        coords.append(coord:VT100GridCoordMake(6, 0))
        coords.append(coord:VT100GridCoordMake(7, 0))

        let index = coords.indexOfFirstCoord(xGreaterOrEqual: 0)
        XCTAssertEqual(index, 0)
    }
}

// MARK: - Accessibility Deletion Detection Tests

final class AccessibilityDeletionDetectionTests: XCTestCase {

    /// Helper to create a located string with characters at sequential x positions
    private func makeLocatedString(_ text: String, startX: Int32 = 0, y: Int32 = 0) -> iTermLocatedString {
        let result = iTermLocatedString()
        var x = startX
        for char in text {
            result.appendString(String(char), at: VT100GridCoordMake(x, y))
            x += 1
        }
        return result
    }

    /// Helper to create a located string with explicit coordinates for each character
    private func makeLocatedString(_ chars: [(String, Int32)], y: Int32 = 0) -> iTermLocatedString {
        let result = iTermLocatedString()
        for (char, x) in chars {
            result.appendString(char, at: VT100GridCoordMake(x, y))
        }
        return result
    }

    // MARK: - Backspace (Cursor moved left) Tests

    func testBackspaceSingleCharacter() {
        // Old: "hello" with cursor at column 6 (1-based, after all 5 chars)
        // New: "hell" with cursor at column 5 (1-based, after 4 chars)
        // Deleted: "o" at grid position 4
        // Grid positions: h=0, e=1, l=2, l=3, o=4
        let oldString = makeLocatedString("hello")
        let newString = makeLocatedString("hell")

        let deleted = detectDeletion(oldCursorX: 6, newCursorX: 5,
                                      oldString: oldString, newString: newString)
        XCTAssertEqual(deleted, "o")
    }

    func testBackspaceMultipleCharacters() {
        // Word delete: "hello world" -> "hello " (deleted "world")
        // Old cursor at column 12 (after 11 chars), new cursor at column 7 (after 6 chars)
        // Grid: h=0, e=1, l=2, l=3, o=4, space=5, w=6, o=7, r=8, l=9, d=10
        let oldString = makeLocatedString("hello world")
        let newString = makeLocatedString("hello ")

        let deleted = detectDeletion(oldCursorX: 12, newCursorX: 7,
                                      oldString: oldString, newString: newString)
        XCTAssertEqual(deleted, "world")
    }

    func testBackspaceToBeginningOfLine() {
        // Ctrl+U: delete entire line
        // Old: "hello" with cursor at column 6 (after all chars)
        // New: "" with cursor at column 1 (at beginning)
        let oldString = makeLocatedString("hello")
        let newString = iTermLocatedString()

        let deleted = detectDeletion(oldCursorX: 6, newCursorX: 1,
                                      oldString: oldString, newString: newString)
        XCTAssertEqual(deleted, "hello")
    }

    func testNoDeletionWhenContentUnchanged() {
        // Cursor moved left but content is same (e.g., arrow key)
        let oldString = makeLocatedString("hello")
        let newString = makeLocatedString("hello")

        let deleted = detectDeletion(oldCursorX: 6, newCursorX: 5,
                                      oldString: oldString, newString: newString)
        // Content at grid position 4 is 'o' in both - strings are equal, no deletion
        XCTAssertNil(deleted)
    }

    // MARK: - Forward Delete (Cursor stayed) Tests

    func testForwardDeleteSingleCharacter() {
        // Forward delete: "hello" -> "hllo" (deleted 'e' at grid x=1)
        // Cursor is at column 2 (1-based), which is grid x=1, before 'e'
        // After delete, cursor stays at column 2, now before first 'l'
        let oldString = makeLocatedString("hello")
        let newString = makeLocatedString("hllo")

        let deleted = detectDeletion(oldCursorX: 2, newCursorX: 2,
                                      oldString: oldString, newString: newString)
        XCTAssertEqual(deleted, "e")
    }

    func testKillToEndOfLine() {
        // Ctrl+K: "hello world" -> "hello" (deleted " world")
        // Cursor is at column 6 (1-based), which is grid x=5 (the space)
        // Kill-to-end deletes from cursor to end, returns trimmed result "world"
        let oldString = makeLocatedString("hello world")
        let newString = makeLocatedString("hello")

        let deleted = detectDeletion(oldCursorX: 6, newCursorX: 6,
                                      oldString: oldString, newString: newString)
        XCTAssertEqual(deleted, "world")
    }

    func testNoChangeNoDeletion() {
        // Same content, same cursor position
        let oldString = makeLocatedString("hello")
        let newString = makeLocatedString("hello")

        let deleted = detectDeletion(oldCursorX: 3, newCursorX: 3,
                                      oldString: oldString, newString: newString)
        XCTAssertNil(deleted)
    }

    // MARK: - Surrogate Pair Tests

    func testBackspaceEmoji() {
        // Emoji like 😀 uses 2 UTF-16 code units but occupies 1 cell
        // Grid: a=0, 😀=1, b=2
        // Old: "a😀b" with cursor at column 4 (after 'b', 1-based)
        // New: "ab" with cursor at column 3 (after 'b' which shifted)
        // But in new string, 'b' is now at grid x=1
        let oldChars: [(String, Int32)] = [("a", 0), ("😀", 1), ("b", 2)]
        let newChars: [(String, Int32)] = [("a", 0), ("b", 1)]
        let oldString = makeLocatedString(oldChars)
        let newString = makeLocatedString(newChars)

        // Cursor was at column 3 (after emoji, before 'b'), moved to column 2 (after 'a')
        let deleted = detectDeletion(oldCursorX: 3, newCursorX: 2,
                                      oldString: oldString, newString: newString)
        XCTAssertEqual(deleted, "😀")
    }

    // MARK: - Edge Cases

    func testCursorMovedRightNoDeletion() {
        // Cursor moved right (not deletion, just navigation)
        let oldString = makeLocatedString("hello")
        let newString = makeLocatedString("hello")

        let deleted = detectDeletion(oldCursorX: 3, newCursorX: 4,
                                      oldString: oldString, newString: newString)
        XCTAssertNil(deleted)
    }

    func testEmptyStrings() {
        let oldString = iTermLocatedString()
        let newString = iTermLocatedString()

        let deleted = detectDeletion(oldCursorX: 0, newCursorX: 0,
                                      oldString: oldString, newString: newString)
        XCTAssertNil(deleted)
    }

    // MARK: - Helper

    /// Mimics the deletion detection logic from PTYTextView.swift
    private func detectDeletion(oldCursorX: Int32, newCursorX: Int32,
                                 oldString: iTermLocatedString,
                                 newString: iTermLocatedString) -> String? {
        let oldGridX = oldCursorX - 1
        let newGridX = newCursorX - 1

        let oldCoords = oldString.gridCoords
        let oldText = oldString.string
        let newCoords = newString.gridCoords
        let newText = newString.string

        if newCursorX < oldCursorX {
            // Case A: Cursor moved left (backspace, word-delete, Ctrl+U)
            let oldRange = oldCoords.rangeOfIndices(xFrom: newGridX, to: oldGridX)
            if oldRange.location != NSNotFound && oldRange.length > 0 {
                let oldSub = (oldText as NSString).substring(with: oldRange)
                let newRange = newCoords.rangeOfIndices(xFrom: newGridX, to: oldGridX)
                let newSub = (newRange.location != NSNotFound && newRange.length > 0)
                    ? (newText as NSString).substring(with: newRange)
                    : ""
                if oldSub != newSub {
                    return oldSub
                }
            }
        } else if newCursorX == oldCursorX && oldText != newText {
            // Case B: Cursor stayed, line content changed
            let oldStartIdx = oldCoords.indexOfFirstCoord(xGreaterOrEqual: newGridX)
            let newStartIdx = newCoords.indexOfFirstCoord(xGreaterOrEqual: newGridX)

            let oldAfter = (oldStartIdx != NSNotFound)
                ? (oldText as NSString).substring(from: oldStartIdx)
                : ""
            let newAfter = (newStartIdx != NSNotFound)
                ? (newText as NSString).substring(from: newStartIdx)
                : ""

            let whitespace = CharacterSet.whitespaces
            let oldTrimmed = oldAfter.trimmingCharacters(in: whitespace)
            let newTrimmed = newAfter.trimmingCharacters(in: whitespace)

            if !oldTrimmed.isEmpty && newTrimmed.isEmpty {
                return oldTrimmed
            } else if !oldTrimmed.isEmpty && !oldAfter.hasPrefix(newAfter) {
                if oldStartIdx != NSNotFound && oldStartIdx < oldText.count {
                    let cursorCoord = oldCoords.coord(at: oldStartIdx)
                    let charRange = oldCoords.rangeOfIndices(xFrom: cursorCoord.x, to: cursorCoord.x + 1)
                    if charRange.location != NSNotFound && charRange.length > 0 {
                        return (oldText as NSString).substring(with: charRange)
                    }
                }
            }
        }

        return nil
    }
}
