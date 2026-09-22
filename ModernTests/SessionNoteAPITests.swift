import XCTest

@testable import iTerm2SharedARC

final class SessionNoteAPITests: XCTestCase {
    func testParseAcceptsPartialPatch() {
        let update = SessionNoteAPIUpdate.parse([
            "text": "next: run tests",
            "visible": true,
        ])

        XCTAssertEqual(update?.text, "next: run tests")
        XCTAssertEqual(update?.visible, true)
        XCTAssertNil(update?.collapsed)
    }

    func testParseRejectsEmptyObject() {
        XCTAssertNil(SessionNoteAPIUpdate.parse([:]))
    }

    func testParseRejectsUnknownKey() {
        XCTAssertNil(SessionNoteAPIUpdate.parse(["title": "wrong"]))
    }

    func testParseRejectsWrongTextType() {
        XCTAssertNil(SessionNoteAPIUpdate.parse(["text": 1]))
    }

    func testParseRejectsNumericBooleanValues() {
        XCTAssertNil(SessionNoteAPIUpdate.parse(["visible": 0]))
        XCTAssertNil(SessionNoteAPIUpdate.parse(["visible": 1]))
    }

    func testParseRejectsNull() {
        XCTAssertNil(SessionNoteAPIUpdate.parse(["collapsed": NSNull()]))
    }
}
