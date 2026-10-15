//
//  PasteWithTabsWarningTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class PasteWithTabsWarningTests: XCTestCase {
    /// T-75: the number-of-spaces field must be the warning's initial first
    /// responder, so typing a number without clicking reaches it.
    func testNumberOfSpacesFieldIsInitialFirstResponder() throws {
        let accessory = iTermNumberOfSpacesAccessoryViewController()
        let warning = try XCTUnwrap(iTermPasteHelper.pasteWithTabsWarning(withAccessoryController: accessory))
        let field = try XCTUnwrap(accessory.textField)
        XCTAssertTrue(field.isEditable)
        XCTAssertTrue(field.isDescendant(of: accessory.view))
        XCTAssertTrue(warning.initialFirstResponder === field)
        XCTAssertTrue(warning.accessory === accessory.view)
    }
}
