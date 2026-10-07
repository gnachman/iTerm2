//
//  AccessibilitySelectionReplacementTests.swift
//  ModernTests
//
//  Voice Control corrects a word by selecting it through accessibility and
//  then inserting the new text with no replacement range, expecting the
//  insertion to replace the selection. A terminal can only do that by
//  backspacing, so it works only when the selection ends at the cursor and
//  a full-screen app isn't running.
//

import XCTest
@testable import iTerm2SharedARC

final class AccessibilitySelectionReplacementTests: XCTestCase {
    private let world = VT100GridAbsCoordRangeMake(27, 100, 32, 100)
    private let cursorAfterWorld = VT100GridAbsCoordMake(32, 100)

    private func decision(accessibilityRange: VT100GridAbsCoordRange? = nil,
                          selection: VT100GridAbsCoordRange? = nil,
                          cursor: VT100GridAbsCoord? = nil,
                          softAlternateScreenMode: Bool = false) -> iTermAccessibilitySelectionReplacementDecision {
        let zero = VT100GridAbsCoordRangeMake(0, 0, 0, 0)
        return iTermAccessibilitySelectionReplacement.decision(
            accessibilityRange: accessibilityRange ?? zero,
            hasAccessibilityRange: accessibilityRange != nil,
            selection: selection ?? zero,
            hasSelection: selection != nil,
            cursor: cursor ?? cursorAfterWorld,
            softAlternateScreenMode: softAlternateScreenMode)
    }

    func testNoAccessibilitySelectionInsertsNormally() {
        XCTAssertEqual(decision(), .insertNormally)
    }

    func testOrdinarySelectionInsertsNormally() {
        XCTAssertEqual(decision(selection: world), .insertNormally)
    }

    func testAccessibilitySelectionEndingAtCursorIsReplaced() {
        XCTAssertEqual(decision(accessibilityRange: world, selection: world), .replace)
    }

    func testAccessibilitySelectionNotEndingAtCursorIsDropped() {
        XCTAssertEqual(decision(accessibilityRange: world,
                                selection: world,
                                cursor: VT100GridAbsCoordMake(40, 100)),
                       .drop)
    }

    func testAccessibilitySelectionInSoftAlternateScreenModeIsDropped() {
        XCTAssertEqual(decision(accessibilityRange: world,
                                selection: world,
                                softAlternateScreenMode: true),
                       .drop)
    }

    func testSelectionChangedSinceAccessibilitySetItInsertsNormally() {
        XCTAssertEqual(decision(accessibilityRange: world,
                                selection: VT100GridAbsCoordRangeMake(20, 100, 32, 100)),
                       .insertNormally)
    }

    func testSelectionClearedSinceAccessibilitySetItInsertsNormally() {
        XCTAssertEqual(decision(accessibilityRange: world), .insertNormally)
    }
}
