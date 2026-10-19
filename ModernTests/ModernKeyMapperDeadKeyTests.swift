//
//  ModernKeyMapperDeadKeyTests.swift
//  ModernTests
//
//  With kitty keyboard flags that report all keys as escape codes, a dead key
//  followed by a key it doesn't compose with (German dead ^ then <) makes
//  Cocoa insert the dead key's character and then the second key's text, both
//  while the second key is the current event. Both insertions were encoded as
//  the second key, so the application got that key twice and never saw the ^.
//  QA finding F-346.
//

import XCTest
import Carbon
@testable import iTerm2SharedARC

final class ModernKeyMapperDeadKeyTests: XCTestCase {
    // Disambiguate, report alternate keys, report all keys as escape codes.
    private let flags = VT100TerminalKeyReportingFlags(rawValue: 13)

    private func keyDown(_ characters: String,
                         ignoringModifiers: String,
                         keyCode: Int) -> NSEvent {
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: [],
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: characters,
                                charactersIgnoringModifiers: ignoringModifiers,
                                isARepeat: false,
                                keyCode: UInt16(keyCode))!
    }

    private var deadCircumflex: NSEvent {
        // Dead keys have no characters until the next key press.
        keyDown("", ignoringModifiers: "^", keyCode: kVK_ISO_Section)
    }

    // The unicode-key-code of a CSI u report: the digits after CSI.
    private func keyNumber(of report: String) -> UInt32? {
        guard report.hasPrefix("\u{1b}[") else {
            return nil
        }
        return UInt32(report.dropFirst(2).prefix { $0.isASCII && $0.isNumber })
    }

    private func makeMapper() -> ModernKeyMapper {
        let mapper = ModernKeyMapper()
        mapper.flags = flags
        return mapper
    }

    func testUncomposedDeadKeyIsReportedOnceAndSecondKeyOnce() {
        let less = keyDown("<", ignoringModifiers: "<", keyCode: kVK_ANSI_Grave)

        let baseline = makeMapper()
        baseline.keyMapperSetEvent(less)
        let lessAlone = baseline.transformedText(toInsert: "<", currentEvent: less)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(less)
        let first = mapper.transformedText(toInsert: "^", currentEvent: less)
        let second = mapper.transformedText(toInsert: "<", currentEvent: less)

        XCTAssertTrue(first.hasPrefix("\u{1b}[") && first.hasSuffix("u"), "not a CSI u report: \(first.debugDescription)")
        XCTAssertNotEqual(first, second, "the dead key's character was reported as the second key")
        XCTAssertEqual(second, lessAlone, "the second key's report changed")
    }

    func testOnlyFirstInsertionAfterDeadKeyIsTheDeadKey() {
        let less = keyDown("<", ignoringModifiers: "<", keyCode: kVK_ANSI_Grave)
        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(less)
        let first = mapper.transformedText(toInsert: "^", currentEvent: less)
        _ = mapper.transformedText(toInsert: "<", currentEvent: less)

        // A later ^ typed as text by the same key press is not the dead key.
        let again = mapper.transformedText(toInsert: "^", currentEvent: less)
        XCTAssertNotEqual(first, again)
    }

    // Real dead key events usually have empty charactersIgnoringModifiers, so
    // the dead key's character comes from the keyboard layout. The test uses
    // whatever the current layout types for the key so it doesn't depend on
    // the machine's input source.
    func testDeadKeyWithEmptyCharactersIsRecognizedFromLayout() throws {
        let dead = keyDown("", ignoringModifiers: "", keyCode: kVK_ISO_Section)
        guard let spacing = dead.characters(byApplyingModifiers: []), !spacing.isEmpty else { throw XCTSkip("no layout translation for the key") }
        let code = try XCTUnwrap(spacing.unicodeScalars.first?.value)
        try XCTSkipIf(spacing == "<", "layout types < on this key")
        let less = keyDown("<", ignoringModifiers: "<", keyCode: kVK_ANSI_Grave)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(dead)
        mapper.keyMapperSetEvent(less)
        let first = mapper.transformedText(toInsert: spacing, currentEvent: less)
        XCTAssertEqual(keyNumber(of: first), code,
                      "expected the dead key's report, got \(first.debugDescription)")
    }

    func testDeadKeyReportCarriesDeadKeyNumber() {
        let less = keyDown("<", ignoringModifiers: "<", keyCode: kVK_ANSI_Grave)
        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(less)
        let first = mapper.transformedText(toInsert: "^", currentEvent: less)
        let expected = deadCircumflex.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 94
        XCTAssertEqual(keyNumber(of: first), expected,
                      "expected the dead key's report, got \(first.debugDescription)")
    }

    // Text inserted without the key press that followed the dead key (for
    // example, by dictation) is not the dead key's character.
    func testInsertionWithoutFollowingKeyPressIsNotTheDeadKey() {
        let less = keyDown("<", ignoringModifiers: "<", keyCode: kVK_ANSI_Grave)
        let baseline = makeMapper()
        let expected = baseline.transformedText(toInsert: "^", currentEvent: nil)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(less)
        XCTAssertEqual(mapper.transformedText(toInsert: "^", currentEvent: nil), expected)
    }

    // Dead ^ then Shift-^ on a German layout inserts ^ and then °.
    func testDeadKeyThenShiftedSameKey() {
        let shifted = NSEvent.keyEvent(with: .keyDown,
                                       location: .zero,
                                       modifierFlags: [.shift],
                                       timestamp: 0,
                                       windowNumber: 0,
                                       context: nil,
                                       characters: "°",
                                       charactersIgnoringModifiers: "°",
                                       isARepeat: false,
                                       keyCode: UInt16(kVK_ISO_Section))!
        let baseline = makeMapper()
        baseline.keyMapperSetEvent(shifted)
        let shiftedAlone = baseline.transformedText(toInsert: "°", currentEvent: shifted)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(shifted)
        let first = mapper.transformedText(toInsert: "^", currentEvent: shifted)
        let second = mapper.transformedText(toInsert: "°", currentEvent: shifted)
        let expected = deadCircumflex.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value
        XCTAssertEqual(keyNumber(of: first), expected, first.debugDescription)
        XCTAssertFalse(first.contains(";2"), "the dead key was not shifted: \(first.debugDescription)")
        XCTAssertEqual(second, shiftedAlone)
    }

    // Dead key then space composes to the bare accent in one insertion. Like
    // other compositions it is reported as the key that was pressed.
    func testDeadKeyThenSpaceIsReportedAsSpace() {
        let space = keyDown(" ", ignoringModifiers: " ", keyCode: kVK_Space)
        let baseline = makeMapper()
        baseline.keyMapperSetEvent(space)
        let expected = baseline.transformedText(toInsert: "^", currentEvent: space)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(space)
        let report = mapper.transformedText(toInsert: "^", currentEvent: space)
        XCTAssertEqual(report, expected)
        XCTAssertEqual(keyNumber(of: report), 32)
    }

    // The dead key only applies to the key press right after it.
    func testDeadKeyDoesNotApplyToALaterKeyPress() {
        let less = keyDown("<", ignoringModifiers: "<", keyCode: kVK_ANSI_Grave)
        let a = keyDown("a", ignoringModifiers: "a", keyCode: kVK_ANSI_A)
        let baseline = makeMapper()
        baseline.keyMapperSetEvent(a)
        let expected = baseline.transformedText(toInsert: "^", currentEvent: a)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(less)  // Inserts nothing.
        mapper.keyMapperSetEvent(a)
        XCTAssertEqual(mapper.transformedText(toInsert: "^", currentEvent: a), expected)
    }

    func testComposedCharacterIsUnchanged() {
        let a = keyDown("a", ignoringModifiers: "a", keyCode: kVK_ANSI_A)

        let baseline = makeMapper()
        baseline.keyMapperSetEvent(a)
        let expected = baseline.transformedText(toInsert: "â", currentEvent: a)

        let mapper = makeMapper()
        mapper.keyMapperSetEvent(deadCircumflex)
        mapper.keyMapperSetEvent(a)
        XCTAssertEqual(mapper.transformedText(toInsert: "â", currentEvent: a), expected)
    }
}
