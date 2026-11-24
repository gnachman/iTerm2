//
//  CategoriesDataStructuresNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of categories, data structures and key
//  mappings that the nullability sanitizer found false (unit N11 of
//  docs/swift-migration/nullability-triage.md). The Objective-C code accepts
//  or produces nil by design; these tests pin what Swift sees. A test that
//  passes nil only compiles because the position is now optional.
//

import XCTest
@testable import iTerm2SharedARC

final class ColorCategoryNullabilityTests: XCTestCase {
    // A tmux tab color is read from an arrangement and can be missing. A nil
    // string is not a color.
    func testColorFromNilHexStringIsNil() {
        XCTAssertNil(NSColor(fromHexString: nil))
        XCTAssertNil(NSColor(fromHexString: nil, allowingAlpha: true))
    }

    // The default background color can be missing from the color map. Blending
    // with nil leaves the color as it was.
    func testBlendingWithNilReturnsTheReceiver() {
        let red = NSColor.red
        XCTAssertTrue(red.blended(with: nil, weight: 0.5) === red)
    }
}

final class StringCategoryNullabilityTests: XCTestCase {
    // iTermObjectIsEqualToString stands in for -isEqualToString: where the argument can be nil:
    // nil never equals anything, nil included, as the message itself answered.
    func testObjectIsEqualToStringWithNil() {
        XCTAssertFalse(iTermObjectIsEqualToString(nil, nil))
        XCTAssertFalse(iTermObjectIsEqualToString("a", nil))
        XCTAssertFalse(iTermObjectIsEqualToString(nil, "a"))
        XCTAssertTrue(iTermObjectIsEqualToString("a", "a"))
        XCTAssertFalse(iTermObjectIsEqualToString("a", "b"))
    }

    // An empty string has no first composed character. While the return was
    // claimed nonnull, Swift read the nil as an empty string, and this
    // assertion failed.
    func testFirstComposedCharacterOfEmptyStringIsNil() {
        var rest: NSString?
        XCTAssertNil(("" as NSString).firstComposedCharacter(&rest))
        XCTAssertEqual(rest, "")
    }

    func testFirstComposedCharacterOfNonEmptyString() {
        var rest: NSString?
        XCTAssertEqual(("ab" as NSString).firstComposedCharacter(&rest), "a")
        XCTAssertEqual(rest, "b")
    }

    // An empty string decodes to no data (+dataWithBase64EncodedString:
    // returns nil), and -initWithData:nil encoding: gives an empty string,
    // not nil. Unit nullability-baseline-guards passes empty data instead of
    // nil and pins that result.
    func testDecodingBase64ThatYieldsNoDataGivesAnEmptyString() {
        let decoded = ("" as NSString).byBase64DecodingString(withEncoding: String.Encoding.utf8.rawValue)
        XCTAssertEqual(decoded, "")
    }
}

final class IntervalTreeNullabilityTests: XCTestCase {
    // Restoring state saved without an interval tree passes nil. Nothing is
    // restored, and the graph form reports that it found no graph.
    func testRestoringFromNilAddsNothing() {
        let tree = IntervalTree()
        tree.restore(from: nil)
        XCTAssertEqual(tree.count, 0)
        XCTAssertFalse(tree.restore(fromGraphRecord: nil, offset: 0, largeContentProvider: nil))
        XCTAssertEqual(tree.count, 0)
    }
}

final class KeyMappingsNullabilityTests: XCTestCase {
    private func keystrokeA() -> iTermKeystroke {
        return iTermKeystroke(virtualKeyCode: 0,
                              hasKeyCode: true,
                              modifierFlags: [],
                              character: 0x61,
                              modifiedCharacter: 0x61)
    }

    // A profile without a key map has none. While the return was claimed
    // nonnull, Swift read the nil as an empty dictionary, and this assertion
    // failed.
    func testKeyMappingsForProfileWithoutKeyMapIsNil() {
        XCTAssertNil(iTermKeyMappings.keyMappings(forProfile: [:]))
    }

    // Looking up a keystroke in a missing key map finds nothing.
    func testLookingUpInNilKeyMappingsFindsNothing() {
        let keystroke = keystrokeA()
        XCTAssertNil(keystroke.key(inBindingDictionary: nil))
        XCTAssertNil(keystroke.value(inBindingDictionary: nil))
        XCTAssertNil(iTermKeyMappings.localAction(for: keystroke, keyMappings: nil))
    }
}
