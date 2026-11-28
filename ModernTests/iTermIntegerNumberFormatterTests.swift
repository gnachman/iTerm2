//
//  iTermIntegerNumberFormatterTests.swift
//  ModernTests
//
//  Characterization tests for the two NSNumberFormatter subclasses declared
//  together: iTermIntegerNumberFormatter, which accepts a partial string
//  while editing only if it is empty or a whole C int, and
//  iTermSaneNumberFormatter, which accepts every partial string and edits a
//  number or a string as plain text. AppKit sends these methods through the
//  Objective-C runtime, so the tests send them through NSFormatter, which
//  dispatches by selector, with real and with nil out-parameters.
//
//  Neither override reads the formatter's locale: the integer check uses a
//  scanner with no locale, and -[NSNumber stringValue] does not use one. The
//  only locale-dependent path is the superclass's formatting of values that
//  are neither numbers nor strings, and the test of that path fixes the
//  locale.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermIntegerNumberFormatterTests: XCTestCase {
    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    private func ownMethodNames(_ cls: AnyClass) -> [String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return []
        }
        defer {
            free(methods)
        }
        return (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }.sorted()
    }

    // Sends isPartialStringValid:newEditingString:errorDescription: through
    // NSFormatter with out-parameters holding sentinels, and returns the
    // answer and what the out-parameters hold afterwards.
    private func partialStringCheck(_ formatter: Formatter,
                                    _ partial: String) -> (Bool, NSString?, NSString?) {
        var newString: NSString? = "untouched new string"
        var error: NSString? = "untouched error"
        let valid = formatter.isPartialStringValid(partial,
                                                   newEditingString: &newString,
                                                   errorDescription: &error)
        return (valid, newString, error)
    }

    private func isValid(_ formatter: Formatter, _ partial: String) -> Bool {
        let (valid, newString, error) = partialStringCheck(formatter, partial)
        XCTAssertEqual(newString, "untouched new string", "for \(partial)")
        XCTAssertEqual(error, "untouched error", "for \(partial)")
        return valid
    }

    // MARK: - The runtime interface

    func testClassesAreFoundByTheirRuntimeNames() throws {
        let integer: AnyClass = try XCTUnwrap(NSClassFromString("iTermIntegerNumberFormatter"))
        let sane: AnyClass = try XCTUnwrap(NSClassFromString("iTermSaneNumberFormatter"))
        XCTAssertTrue(integer.superclass() === NumberFormatter.self)
        XCTAssertTrue(sane.superclass() === NumberFormatter.self)
    }

    func testOverriddenSelectorsAndEncodings() throws {
        let integer: AnyClass = try XCTUnwrap(NSClassFromString("iTermIntegerNumberFormatter"))
        let sane: AnyClass = try XCTUnwrap(NSClassFromString("iTermSaneNumberFormatter"))
        let partial = "isPartialStringValid:newEditingString:errorDescription:"
        XCTAssertTrue(ownMethodNames(integer).contains(partial))
        XCTAssertTrue(ownMethodNames(sane).contains(partial))
        XCTAssertTrue(ownMethodNames(sane).contains("editingStringForObjectValue:"))
        XCTAssertFalse(ownMethodNames(integer).contains("editingStringForObjectValue:"))
        XCTAssertEqual(instanceMethodEncoding(integer, partial), "B40@0:8@16^@24^@32")
        XCTAssertEqual(instanceMethodEncoding(sane, partial), "B40@0:8@16^@24^@32")
        XCTAssertEqual(instanceMethodEncoding(sane, "editingStringForObjectValue:"), "@24@0:8@16")
    }

    // MARK: - iTermIntegerNumberFormatter

    func testIntegerFormatterAcceptsTheEmptyString() {
        XCTAssertTrue(isValid(iTermIntegerNumberFormatter(), ""))
    }

    func testIntegerFormatterAcceptsWholeIntegers() {
        let formatter = iTermIntegerNumberFormatter()
        for partial in ["0", "7", "123", "-5", "+3", "007", "-0"] {
            XCTAssertTrue(isValid(formatter, partial), partial)
        }
    }

    // The scanner skips whitespace before the number and counts whitespace
    // after it as the end.
    func testIntegerFormatterAcceptsSurroundingWhitespace() {
        let formatter = iTermIntegerNumberFormatter()
        for partial in [" 12", "12 ", "\t12\n", "  -4  "] {
            XCTAssertTrue(isValid(formatter, partial), partial)
        }
    }

    // A number too large for an int still scans, so it is accepted.
    func testIntegerFormatterAcceptsOutOfRangeIntegers() {
        let formatter = iTermIntegerNumberFormatter()
        for partial in ["2147483647", "2147483648", "-2147483649", "99999999999999999999999"] {
            XCTAssertTrue(isValid(formatter, partial), partial)
        }
    }

    // The scanner takes decimal digits from other scripts too.
    func testIntegerFormatterAcceptsDigitsFromOtherScripts() {
        let formatter = iTermIntegerNumberFormatter()
        for partial in ["١٢", "１２", "-١٢"] {
            XCTAssertTrue(isValid(formatter, partial), partial)
        }
    }

    func testIntegerFormatterRejectsEverythingElse() {
        let formatter = iTermIntegerNumberFormatter()
        for partial in ["-", "+", " ", "a", "12a", "a12", "1.5", "1,000", "1 2", "0x10", "1e3",
                        "12-"] {
            XCTAssertFalse(isValid(formatter, partial), partial)
        }
    }

    func testIntegerFormatterAcceptsNilOutParameters() {
        let formatter: Formatter = iTermIntegerNumberFormatter()
        XCTAssertTrue(formatter.isPartialStringValid("42", newEditingString: nil, errorDescription: nil))
        XCTAssertFalse(formatter.isPartialStringValid("4x", newEditingString: nil, errorDescription: nil))
        XCTAssertTrue(formatter.isPartialStringValid("", newEditingString: nil, errorDescription: nil))
    }

    // NSFormatter's range-based check, which a field editor sends, falls back
    // on the override.
    func testIntegerFormatterAnswersTheRangeBasedCheck() {
        let formatter: Formatter = iTermIntegerNumberFormatter()
        var good: NSString = "12"
        var bad: NSString = "1x"
        var range = NSRange(location: 2, length: 0)
        XCTAssertTrue(formatter.isPartialStringValid(&good,
                                                     proposedSelectedRange: &range,
                                                     originalString: "1",
                                                     originalSelectedRange: NSRange(location: 1, length: 0),
                                                     errorDescription: nil))
        XCTAssertFalse(formatter.isPartialStringValid(&bad,
                                                      proposedSelectedRange: &range,
                                                      originalString: "1",
                                                      originalSelectedRange: NSRange(location: 1, length: 0),
                                                      errorDescription: nil))
        XCTAssertEqual(good, "12")
        XCTAssertEqual(bad, "1x")
    }

    // The integer formatter adds nothing to editing strings.
    func testIntegerFormatterEditsLikeItsSuperclass() {
        let formatter = iTermIntegerNumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let plain = NumberFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 42)),
                       plain.editingString(for: NSNumber(value: 42)))
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 2.5)),
                       plain.editingString(for: NSNumber(value: 2.5)))
    }

    // MARK: - iTermSaneNumberFormatter

    func testSaneFormatterAcceptsEveryPartialString() {
        let formatter = iTermSaneNumberFormatter()
        for partial in ["", "12", "abc", "1.5", "-", " ", "١٢", "🎉"] {
            XCTAssertTrue(isValid(formatter, partial), partial)
        }
    }

    func testSaneFormatterAcceptsNilOutParameters() {
        let formatter: Formatter = iTermSaneNumberFormatter()
        XCTAssertTrue(formatter.isPartialStringValid("abc", newEditingString: nil, errorDescription: nil))
        XCTAssertTrue(formatter.isPartialStringValid("", newEditingString: nil, errorDescription: nil))
    }

    func testSaneFormatterAnswersTheRangeBasedCheck() {
        let formatter: Formatter = iTermSaneNumberFormatter()
        var partial: NSString = "x"
        var range = NSRange(location: 1, length: 0)
        var error: NSString? = "untouched"
        XCTAssertTrue(formatter.isPartialStringValid(&partial,
                                                     proposedSelectedRange: &range,
                                                     originalString: "",
                                                     originalSelectedRange: NSRange(location: 0, length: 0),
                                                     errorDescription: &error))
        XCTAssertEqual(partial, "x")
        XCTAssertEqual(error, "untouched")
    }

    func testSaneFormatterEditsNumbersAsTheirStringValue() {
        let formatter: Formatter = iTermSaneNumberFormatter()
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 42)), "42")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: -7)), "-7")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 2.5)), "2.5")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 1234567.25)), "1234567.25")
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: true)), "1")
        XCTAssertEqual(formatter.editingString(for: NSDecimalNumber(string: "3.14159")), "3.14159")
    }

    // A number's string value ignores the formatter's locale and style.
    func testSaneFormatterIgnoresLocaleAndStyleForNumbers() {
        let formatter = iTermSaneNumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        XCTAssertEqual(formatter.editingString(for: NSNumber(value: 1234567.25)), "1234567.25")
    }

    func testSaneFormatterEditsStringsAsThemselves() {
        let formatter: Formatter = iTermSaneNumberFormatter()
        XCTAssertEqual(formatter.editingString(for: "hello"), "hello")
        XCTAssertEqual(formatter.editingString(for: ""), "")
        XCTAssertEqual(formatter.editingString(for: NSMutableString(string: "mutable")), "mutable")
        XCTAssertEqual(formatter.editingString(for: "12abc"), "12abc")
    }

    // Anything else goes to NSNumberFormatter, whose answer depends on the
    // locale, so the locale is fixed.
    func testSaneFormatterLeavesOtherValuesToItsSuperclass() {
        let formatter = iTermSaneNumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let plain = NumberFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        let values: [Any] = [NSNull(), NSDate(timeIntervalSince1970: 0), NSArray(array: [1])]
        for value in values {
            XCTAssertEqual(formatter.editingString(for: value), plain.editingString(for: value),
                           "for \(value)")
        }
    }

    // Objective-C callers can pass nil; the superclass then answers.
    func testSaneFormatterLeavesNilToItsSuperclass() {
        let selector = NSSelectorFromString("editingStringForObjectValue:")
        let sane = iTermSaneNumberFormatter()
        let plain = NumberFormatter()
        let saneResult = sane.perform(selector, with: nil)?.takeUnretainedValue() as? String
        let plainResult = plain.perform(selector, with: nil)?.takeUnretainedValue() as? String
        XCTAssertEqual(saneResult, plainResult)
    }
}
