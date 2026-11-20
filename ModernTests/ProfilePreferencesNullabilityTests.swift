//
//  ProfilePreferencesNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of iTermProfilePreferences and iTermTuple
//  that the nullability sanitizer found false (unit N1 of
//  docs/swift-migration/nullability-triage.md). The Objective-C methods return
//  nil, or accept nil, by design; these tests pin what Swift sees.
//

import XCTest
@testable import iTerm2SharedARC

final class ProfilePreferencesNullabilityTests: XCTestCase {
    // Not a profile key: no computed value, no profile value and no default.
    private let missingKey = "NoSuchProfileKeyForNullabilityTests"

    // +objectForKey:inProfile: returns nil when neither a computed value, the
    // profile nor the defaults have the key. While the return was claimed
    // nonnull, Swift typed it Any and wrapped the nil, so this assertion failed.
    func testObjectForMissingKeyIsNil() {
        let value: Any? = iTermProfilePreferences.object(forKey: missingKey, inProfile: [:])
        XCTAssertNil(value)
    }

    func testObjectForPresentKeyIsTheProfileValue() {
        let value = iTermProfilePreferences.object(forKey: KEY_NAME, inProfile: [KEY_NAME: "N1"])
        XCTAssertEqual(value as? String, "N1")
    }

    // The tests below pass nil where the header used to claim nonnull, so they
    // only compile with the nullable claims. A nil profile reads like an empty
    // one: the profile's value is missing and the default is used.

    func testNilProfileReadsLikeAnEmptyProfile() {
        XCTAssertEqual(iTermProfilePreferences.bool(forKey: KEY_BLINKING_CURSOR, inProfile: nil),
                       iTermProfilePreferences.bool(forKey: KEY_BLINKING_CURSOR, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.int(forKey: KEY_COLUMNS, inProfile: nil),
                       iTermProfilePreferences.int(forKey: KEY_COLUMNS, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.integer(forKey: KEY_ROWS, inProfile: nil),
                       iTermProfilePreferences.integer(forKey: KEY_ROWS, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.unsignedInteger(forKey: KEY_TITLE_COMPONENTS, inProfile: nil),
                       iTermProfilePreferences.unsignedInteger(forKey: KEY_TITLE_COMPONENTS, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.float(forKey: KEY_TRANSPARENCY, inProfile: nil),
                       iTermProfilePreferences.float(forKey: KEY_TRANSPARENCY, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.double(forKey: KEY_HORIZONTAL_SPACING, inProfile: nil),
                       iTermProfilePreferences.double(forKey: KEY_HORIZONTAL_SPACING, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.string(forKey: KEY_NAME, inProfile: nil),
                       iTermProfilePreferences.string(forKey: KEY_NAME, inProfile: [:]))
        XCTAssertEqual(iTermProfilePreferences.object(forKey: KEY_COLUMNS, inProfile: nil) as? NSNumber,
                       iTermProfilePreferences.object(forKey: KEY_COLUMNS, inProfile: [:]) as? NSNumber)
        XCTAssertNotNil(iTermProfilePreferences.object(forKey: KEY_COLUMNS, inProfile: nil))
        XCTAssertNil(iTermProfilePreferences.object(forKey: missingKey, inProfile: nil))
    }

    func testNilProfileHasNoExplicitValue() {
        XCTAssertFalse(iTermProfilePreferences.valueIsExplicitlySet(forKey: KEY_NAME, inProfile: nil))
    }

    func testNilBindingValueHasNoExpressionAndNoOwner() {
        XCTAssertNil(iTermProfilePreferences.expression(forBindingValue: nil))
        XCTAssertFalse(iTermProfilePreferences.bindingValueIsPaletteOwned(nil))
    }

    func testTupleFromNilPlistValueIsEmpty() {
        let tuple = iTermTuple<NSString, NSString>.fromPlistValue(nil)
        XCTAssertNil(tuple.firstObject)
        XCTAssertNil(tuple.secondObject)
    }
}

// get_profile_property hands the value of +objectForKey:inProfile: to its
// completion block. While that method was claimed nonnull, a nil from it
// reached the block as NSNull (Swift bridges a nil wrapped in Any to NSNull),
// and the function must keep answering NSNull for a missing key.
final class GetProfilePropertyBuiltInFunctionTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUp() {
        super.setUp()
        fixture = TerminalWindowTestFixture()
        if !iTermBuiltInFunctions.sharedInstance().haveFunction(withName: "get_profile_property",
                                                                 namespace: "iterm2",
                                                                 arguments: ["key"]) {
            GetProfilePropertyBuiltInFunction.register()
        }
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    // The session comes from the scope, as when an expression in a session calls the function.
    private func call(key: String, session: PTYSession) -> (Any?, Error?) {
        let done = expectation(description: "get_profile_property")
        var result: (Any?, Error?) = (nil, nil)
        iTermBuiltInFunctions.sharedInstance().callFunction(withName: "get_profile_property",
                                                            namespace: "iterm2",
                                                            parameters: ["key": key],
                                                            scope: session.genericScope,
                                                            sideEffectsAllowed: true) { value, error in
            result = (value, error)
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
    }

    func testMissingKeyAnswersNSNull() {
        guard let session = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        let (value, error) = call(key: "NoSuchProfileKeyForNullabilityTests", session: session)
        XCTAssertNil(error)
        XCTAssertTrue(value is NSNull, "Got \(String(describing: value))")
    }

    func testPresentKeyAnswersItsValue() {
        guard let session = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        let (value, error) = call(key: KEY_NAME, session: session)
        XCTAssertNil(error)
        XCTAssertEqual(value as? String, session.profile?[KEY_NAME] as? String)
    }
}
