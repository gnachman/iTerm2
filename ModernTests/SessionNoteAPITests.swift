import XCTest

@testable import iTerm2SharedARC

final class SessionNoteAPITests: XCTestCase {
    private func makeSession() -> PTYSession {
        PTYSession(synthetic: false)!
    }

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

    func testEmptySessionHasCanonicalSnapshot() {
        let session = makeSession()

        XCTAssertEqual(session.sessionNoteAPIDictionary["text"] as? String, "")
        XCTAssertEqual(session.sessionNoteAPIDictionary["visible"] as? Bool, false)
        XCTAssertEqual(session.sessionNoteAPIDictionary["collapsed"] as? Bool, false)
    }

    func testTextCreatesHiddenNote() {
        let session = makeSession()

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "next action"])!))
        XCTAssertEqual(session.sessionNoteModel?.text, "next action")
        XCTAssertEqual(session.sessionNoteAPIDictionary["visible"] as? Bool, false)
        XCTAssertEqual(session.sessionNoteAPIDictionary["collapsed"] as? Bool, false)
    }

    func testCollapsedPatchPreservesText() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "next action"])!))
        let originalModel = session.sessionNoteModel

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["collapsed": true])!))
        XCTAssertTrue(session.sessionNoteModel === originalModel)
        XCTAssertEqual(session.sessionNoteModel?.text, "next action")
        XCTAssertEqual(session.sessionNoteModel?.isCollapsed, true)
    }

    func testTextPatchPreservesCollapsedState() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "first", "collapsed": true])!))
        let originalModel = session.sessionNoteModel

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "revised"])!))
        XCTAssertTrue(session.sessionNoteModel === originalModel)
        XCTAssertEqual(session.sessionNoteModel?.text, "revised")
        XCTAssertEqual(session.sessionNoteModel?.isCollapsed, true)
    }

    func testEmptyTextClearsCollapsedModelToCanonicalEmptyState() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "temporary", "collapsed": true])!))

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": ""])!))
        XCTAssertNil(session.sessionNoteModel)
        XCTAssertEqual(session.sessionNoteAPIDictionary["text"] as? String, "")
        XCTAssertEqual(session.sessionNoteAPIDictionary["visible"] as? Bool, false)
        XCTAssertEqual(session.sessionNoteAPIDictionary["collapsed"] as? Bool, false)
    }

    func testRejectsVisibleOrCollapsedEmptyNoteWithoutMutation() {
        let session = makeSession()

        XCTAssertFalse(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": true])!))
        XCTAssertFalse(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["collapsed": true])!))
        XCTAssertNil(session.sessionNoteModel)
    }

    func testRejectsClearAndVisibleWithoutMutatingEstablishedModel() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "keep", "collapsed": true])!))
        let originalModel = session.sessionNoteModel

        XCTAssertFalse(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "", "visible": true])!))
        XCTAssertTrue(session.sessionNoteModel === originalModel)
        XCTAssertEqual(session.sessionNoteModel?.text, "keep")
        XCTAssertEqual(session.sessionNoteModel?.isCollapsed, true)
    }

    func testRejectsClearAndCollapsedWithoutMutatingEstablishedModel() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "keep"])!))
        let originalModel = session.sessionNoteModel

        XCTAssertFalse(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "", "collapsed": true])!))
        XCTAssertTrue(session.sessionNoteModel === originalModel)
        XCTAssertEqual(session.sessionNoteModel?.text, "keep")
        XCTAssertEqual(session.sessionNoteModel?.isCollapsed, false)
    }

    func testRejectsVisibleWithoutLiveViewAtomically() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "keep", "collapsed": true])!))
        let originalModel = session.sessionNoteModel

        XCTAssertFalse(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse([
                "text": "replacement",
                "visible": true,
                "collapsed": false,
            ])!))
        XCTAssertTrue(session.sessionNoteModel === originalModel)
        XCTAssertEqual(session.sessionNoteModel?.text, "keep")
        XCTAssertEqual(session.sessionNoteModel?.isCollapsed, true)
    }
}
