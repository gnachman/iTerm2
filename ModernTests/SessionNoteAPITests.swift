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
        XCTAssertEqual(session.sessionNoteAPIDictionary as? [String: AnyHashable], [
            "text": "next action",
            "visible": false,
            "collapsed": true,
        ])
    }

    func testHidingPreservesTextAndCollapsedState() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "keep", "collapsed": true])!))
        let originalModel = session.sessionNoteModel

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": false])!))
        XCTAssertTrue(session.sessionNoteModel === originalModel)
        XCTAssertEqual(session.sessionNoteAPIDictionary as? [String: AnyHashable], [
            "text": "keep",
            "visible": false,
            "collapsed": true,
        ])
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

    func testRestorationHydratesNoteBeforeRestoringItsView() {
        let session = makeSession()
        let view = SessionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        session.view = view

        session.hydrateSessionNote(fromArrangement: [
            "text": "resume investigation",
            "collapsed": true,
            "frame": NSStringFromRect(NSRect(x: 20, y: 20, width: 300, height: 160)),
        ])
        session.didFinishRestoration()

        XCTAssertEqual(session.sessionNoteModel?.text, "resume investigation")
        XCTAssertEqual(session.sessionNoteModel?.isCollapsed, true)
        XCTAssertTrue(view.isSessionNoteVisible)
        XCTAssertEqual(session.sessionNoteAPIDictionary as? [String: AnyHashable], [
            "text": "resume investigation",
            "visible": true,
            "collapsed": true,
        ])
    }

    // MARK: - Visibility round-trip

    private func makeSessionWithView() -> (PTYSession, SessionView) {
        let session = makeSession()
        let view = SessionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        session.view = view
        return (session, view)
    }

    private func encodedArrangement(_ model: SessionNoteModel) -> NSDictionary {
        let adapter = iTermMutableDictionaryEncoderAdapter.encoder()
        model.encode(with: adapter)
        return adapter.mutableDictionary as NSDictionary
    }

    func testHiddenNoteDoesNotComeBackVisible() {
        let (session, view) = makeSessionWithView()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "notes", "visible": true])!))
        XCTAssertTrue(view.isSessionNoteVisible)
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": false])!))
        XCTAssertFalse(view.isSessionNoteVisible)
        let arrangement = encodedArrangement(session.sessionNoteModel!)

        let (restored, restoredView) = makeSessionWithView()
        restored.hydrateSessionNote(fromArrangement: arrangement)
        restored.didFinishRestoration()

        XCTAssertEqual(restored.sessionNoteModel?.text, "notes")
        XCTAssertFalse(restoredView.isSessionNoteVisible)
        XCTAssertEqual(restored.sessionNoteAPIDictionary["visible"] as? Bool, false)
    }

    func testVisibleNoteComesBackVisible() {
        let (session, view) = makeSessionWithView()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "notes", "visible": true, "collapsed": true])!))
        XCTAssertTrue(view.isSessionNoteVisible)
        let arrangement = encodedArrangement(session.sessionNoteModel!)

        let (restored, restoredView) = makeSessionWithView()
        restored.hydrateSessionNote(fromArrangement: arrangement)
        restored.didFinishRestoration()

        XCTAssertTrue(restoredView.isSessionNoteVisible)
        XCTAssertEqual(restored.sessionNoteAPIDictionary as? [String: AnyHashable], [
            "text": "notes",
            "visible": true,
            "collapsed": true,
        ])
    }

    func testNoteThatWasNeverShownDoesNotFloatOnRestore() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "toolbelt only"])!))
        let arrangement = encodedArrangement(session.sessionNoteModel!)

        let (restored, restoredView) = makeSessionWithView()
        restored.hydrateSessionNote(fromArrangement: arrangement)
        restored.didFinishRestoration()

        XCTAssertEqual(restored.sessionNoteModel?.text, "toolbelt only")
        XCTAssertFalse(restoredView.isSessionNoteVisible)
    }

    // The delta encoder reuses the previously encoded record whenever the generation has not moved,
    // so a visibility change that does not bump it would never reach saved state.
    func testVisibilityChangeBumpsGeneration() {
        let model = SessionNoteModel()
        model.text = "content"
        let generationBefore = model.generation

        model.isVisible = true

        XCTAssertGreaterThan(model.generation, generationBefore)
    }

    func testArrangementWithoutVisibleKeyRestoresShowing() {
        let model = SessionNoteModel.fromArrangement(["text": "written by an older build"])

        XCTAssertEqual(model?.isVisible, true)
    }

    // A restored model that restarted near zero could later reach the generation the record was
    // saved at, and the delta encoder would then reuse the stale record instead of the edits.
    func testRestoredModelResumesTheSavedGeneration() {
        let model = SessionNoteModel()
        model.text = "typed"
        model.isVisible = true
        model.isCollapsed = true
        model.noteFrame = NSRect(x: 1, y: 2, width: 300, height: 200)
        model.text = "typed more"
        model.text = "typed even more"
        let savedGeneration = model.generation

        let restored = SessionNoteModel.fromArrangement(encodedArrangement(model))!

        XCTAssertEqual(restored.generation, savedGeneration)
        XCTAssertEqual(restored.text, "typed even more")
        XCTAssertEqual(restored.isCollapsed, true)
        XCTAssertEqual(restored.noteFrame, NSRect(x: 1, y: 2, width: 300, height: 200))
    }

    func testRestoredModelIsNeverBehindTheSavedGeneration() {
        // A hand-edited or corrupt generation smaller than what restoring the properties already
        // reached must not wind the counter backwards.
        let restored = SessionNoteModel.fromArrangement([
            "text": "typed",
            "visible": true,
            "collapsed": true,
            "generation": 1,
        ])!

        XCTAssertGreaterThanOrEqual(restored.generation, 3)
    }

    func testHidingWithoutALiveViewRecordsTheNoteAsHidden() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "content"])!))

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": false])!))

        XCTAssertEqual(session.sessionNoteModel?.isVisible, false)
    }

    // MARK: - Model replacement

    func testReplacingTheModelNotifiesObservers() {
        let session = makeSession()
        var posted = 0
        let token = NotificationCenter.default.addObserver(
            forName: SessionNoteModel.modelDidChangeNotification,
            object: session,
            queue: nil) { _ in posted += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "created"])!))
        XCTAssertEqual(posted, 1)

        // A patch that keeps the same model must not claim a replacement.
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "revised"])!))
        XCTAssertEqual(posted, 1)

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": ""])!))
        XCTAssertNil(session.sessionNoteModel)
        XCTAssertEqual(posted, 2)
    }

    // The delta encoder reuses the saved record when the generation it is handed matches, so a
    // replacement model must never land on a generation the previous one already reached.
    func testReplacementModelStartsPastThePreviousGeneration() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "old"])!))
        let oldGeneration = session.sessionNoteModel!.generation

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": ""])!))
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "new"])!))

        XCTAssertGreaterThan(session.sessionNoteModel!.generation, oldGeneration)
    }

    // MARK: - Validator parity with the API pre-check

    func testHidingANoteWhoseTextWasClearedElsewhereSucceeds() {
        let session = makeSession()
        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["text": "temporary", "collapsed": true])!))
        // Stands in for the user clearing the text in the Notes toolbelt, which leaves a collapsed
        // model with no content behind. -[iTermAPIHelper setSessionNote] admits this patch, so
        // applying it must not report failure.
        session.sessionNoteModel?.text = ""

        XCTAssertTrue(session.applySessionNoteAPIUpdate(
            SessionNoteAPIUpdate.parse(["visible": false])!))

        XCTAssertNil(session.sessionNoteModel)
    }
}
