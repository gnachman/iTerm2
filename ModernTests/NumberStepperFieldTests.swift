//
//  NumberStepperFieldTests.swift
//  ModernTests
//
//  A whole-number field with a stepper, for settings like how many lines a
//  tab content line can wrap to.
//

import XCTest
@testable import iTerm2SharedARC

final class NumberStepperFieldTests: XCTestCase {
    private var actions = 0

    @objc private func didChange(_ sender: Any?) {
        actions += 1
    }

    private func makeField() -> NumberStepperField {
        let field = NumberStepperField(range: 1...3)
        field.target = self
        field.action = #selector(didChange(_:))
        return field
    }

    func testValueShowsInTheFieldAndStepper() {
        let field = makeField()
        field.value = 2
        XCTAssertEqual(field.textField.integerValue, 2)
        XCTAssertEqual(field.stepper.integerValue, 2)
    }

    func testValueIsClamped() {
        let field = makeField()
        field.value = 9
        XCTAssertEqual(field.value, 3)
        field.value = 0
        XCTAssertEqual(field.value, 1)
    }

    func testStepperChangesTheValueAndSendsTheAction() {
        let field = makeField()
        field.value = 1
        field.stepper.integerValue = 2
        field.stepper.sendAction(field.stepper.action, to: field.stepper.target)
        XCTAssertEqual(field.value, 2)
        XCTAssertEqual(field.textField.integerValue, 2)
        XCTAssertEqual(actions, 1)
    }

    // Typing a number out of range takes the nearest one in range; anything
    // else puts back the value it had.
    func testTypingChangesTheValueAndSendsTheAction() {
        let field = makeField()
        field.value = 1
        field.textField.stringValue = "3"
        field.textField.sendAction(field.textField.action, to: field.textField.target)
        XCTAssertEqual(field.value, 3)
        XCTAssertEqual(field.stepper.integerValue, 3)
        XCTAssertEqual(actions, 1)

        field.textField.stringValue = "7"
        field.textField.sendAction(field.textField.action, to: field.textField.target)
        XCTAssertEqual(field.value, 3)
        XCTAssertEqual(field.textField.stringValue, "3")

        field.textField.stringValue = "lots"
        field.textField.sendAction(field.textField.action, to: field.textField.target)
        XCTAssertEqual(field.value, 3)
        XCTAssertEqual(field.textField.stringValue, "3")
        XCTAssertEqual(actions, 1, "no change, no action")
    }

    // A typed number counts when editing ends any way, not just with Return.
    func testEndingEditingCommitsTheTypedNumber() {
        XCTAssertEqual(makeField().textField.cell?.sendsActionOnEndEditing, true)
    }

    // A stepper click after typing starts from the typed number and sends the
    // action even though the stepper alone would have reached it too.
    func testStepperClickAfterTypingStartsFromTheTypedNumber() {
        let field = NumberStepperField(range: 1...20)
        field.target = self
        field.action = #selector(didChange(_:))
        field.value = 1
        field.textField.stringValue = "5"  // typed, not committed
        field.stepper.integerValue = 2  // the click: one up from 1
        field.stepper.sendAction(field.stepper.action, to: field.stepper.target)
        XCTAssertEqual(field.value, 6)
        XCTAssertEqual(actions, 1)

        field.textField.stringValue = "1"
        field.stepper.integerValue = 7  // one up from 6, with 1 typed
        field.stepper.sendAction(field.stepper.action, to: field.stepper.target)
        XCTAssertEqual(field.value, 2)
        XCTAssertEqual(actions, 2)
    }

    // Text that isn't a number is replaced with the value rather than
    // refused, which would keep the focus in the field.
    func testNoFormatterToRefuseInput() {
        XCTAssertNil(makeField().textField.formatter)
    }

    // A huge typed number is clamped before stepping, rather than
    // overflowing.
    func testStepperClickAfterTypingAHugeNumber() {
        let field = makeField()
        field.value = 2
        field.textField.stringValue = String(Int.max)
        field.stepper.integerValue = 3
        field.stepper.sendAction(field.stepper.action, to: field.stepper.target)
        XCTAssertEqual(field.value, 3)
        field.textField.stringValue = String(Int.min)
        field.stepper.integerValue = 2
        field.stepper.sendAction(field.stepper.action, to: field.stepper.target)
        XCTAssertEqual(field.value, 1)
    }

    func testDisabling() {
        let field = makeField()
        field.isEnabled = false
        XCTAssertFalse(field.textField.isEnabled)
        XCTAssertFalse(field.stepper.isEnabled)
    }
}
