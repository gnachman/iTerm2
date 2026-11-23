import XCTest
@testable import iTerm2SharedARC

final class SessionViewTests: XCTestCase {
    private let dismemberScrollViewKey = "DismemberScrollView"
    private var savedDismemberScrollView: Any?

    override func setUp() {
        super.setUp()
        savedDismemberScrollView = iTermUserDefaults.userDefaults().object(forKey: dismemberScrollViewKey)
    }

    override func tearDown() {
        let defaults = iTermUserDefaults.userDefaults()
        if let savedDismemberScrollView {
            defaults.set(savedDismemberScrollView, forKey: dismemberScrollViewKey)
        } else {
            defaults.removeObject(forKey: dismemberScrollViewKey)
        }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        super.tearDown()
    }

    func testScrollerRemainsContainedWithoutLegacyPreference() throws {
        iTermUserDefaults.userDefaults().removeObject(forKey: dismemberScrollViewKey)
        try assertScrollerRemainsContained()
    }

    func testScrollerRemainsContainedWithLegacyPreferenceEnabled() throws {
        iTermUserDefaults.userDefaults().set(true, forKey: dismemberScrollViewKey)
        try assertScrollerRemainsContained()
    }

    private func assertScrollerRemainsContained(file: StaticString = #filePath,
                                                line: UInt = #line) throws {
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        let sessionView = SessionView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let scrollView = try XCTUnwrap(sessionView.scrollview, file: file, line: line)
        let scroller = try XCTUnwrap(scrollView.verticalScroller, file: file, line: line)
        XCTAssertTrue(scroller.isDescendant(of: scrollView), file: file, line: line)

        for style: NSScroller.Style in [.legacy, .overlay, .legacy] {
            scrollView.scrollerStyle = style
            scrollView.tile()
            XCTAssertTrue(scrollView.verticalScroller === scroller, file: file, line: line)
            XCTAssertTrue(scroller.isDescendant(of: scrollView), file: file, line: line)
            XCTAssertEqual(scroller.scrollerStyle, style, file: file, line: line)
        }
    }

    // MARK: - NSView (iTerm) methods SessionView relies on

    private func views(_ count: Int) -> [NSView] {
        return (0..<count).map { _ in NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1)) }
    }

    func testInsertSubviewAtIndex() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let v = views(4)
        // With no subviews the index is ignored.
        parent.it_insertSubview(v[0], at: 5)
        XCTAssertEqual(parent.subviews, [v[0]])
        parent.it_insertSubview(v[1], at: 0)
        XCTAssertEqual(parent.subviews, [v[1], v[0]])
        parent.it_insertSubview(v[2], at: 1)
        XCTAssertEqual(parent.subviews, [v[1], v[2], v[0]])
        parent.it_insertSubview(v[3], at: 3)
        XCTAssertEqual(parent.subviews, [v[1], v[2], v[0], v[3]])
    }

    func testSessionViewInsertSubviewAtIndex() {
        let sessionView = SessionView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let before = sessionView.subviews
        XCTAssertFalse(before.isEmpty)
        let first = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        sessionView.it_insertSubview(first, at: 0)
        XCTAssertEqual(sessionView.subviews, [first] + before)
        let last = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        sessionView.it_insertSubview(last, at: sessionView.subviews.count)
        XCTAssertEqual(sessionView.subviews, [first] + before + [last])
    }

    func testSnapshotHasTheViewsSize() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 12, height: 7))
        let image = try XCTUnwrap(view.it_snapshot())
        XCTAssertEqual(image.size, NSSize(width: 12, height: 7))
        XCTAssertEqual(image.representations.count, 1)
    }

    func testAnimateWithDurationRunsAnimationsAtOnceAndRestoresTheDuration() {
        let context = NSAnimationContext.current
        let savedDuration = context.duration
        var durationInsideAnimations: TimeInterval = -1
        NSView.it_animate(withDuration: 0.5, animations: {
            durationInsideAnimations = context.duration
        }, completion: nil)
        XCTAssertEqual(durationInsideAnimations, 0.5)
        XCTAssertEqual(context.duration, savedDuration)
    }

    func testAnimateCallsItsCompletionOnTheMainQueue() {
        // A zero duration schedules the completion with no delay, so
        // waiting for it only drains the main queue.
        let completed = expectation(description: "completion")
        NSView.it_animate(withDuration: 0, animations: {}, completion: { finished in
            XCTAssertTrue(finished)
            XCTAssertTrue(Thread.isMainThread)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 30)
    }

    func testAnimateWithZeroDurationKeepsTheContextDuration() {
        let context = NSAnimationContext.current
        let savedDuration = context.duration
        var durationInsideAnimations: TimeInterval = -1
        NSView.it_animate(withDuration: 0, animations: {
            durationInsideAnimations = context.duration
        }, completion: nil)
        XCTAssertEqual(durationInsideAnimations, savedDuration)
        XCTAssertEqual(context.duration, savedDuration)
    }
}
