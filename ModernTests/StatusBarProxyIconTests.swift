//
//  StatusBarProxyIconTests.swift
//  iTerm2 ModernTests
//
//  Covers the Current Directory status bar component's proxy icon: a plain click on the icon
//  must still reach the component (which opens its menu) even though the container has a click
//  gesture recognizer that delays mouse events, and a click must not be handled twice.
//

import XCTest
@testable import iTerm2SharedARC

/// Records clicks instead of opening the directory menu, which would start modal menu tracking.
private final class RecordingWorkingDirectoryComponent: iTermStatusBarWorkingDirectoryComponent {
    var clickCount = 0

    // The real icon is looked up in the bundle of `[self class]`, which for this subclass is the
    // test bundle, so supply one. It must be the same instance every time, as the container
    // compares icons by identity.
    private let icon = NSImage(size: NSSize(width: 12, height: 12))

    override func statusBarComponentIcon() -> NSImage? {
        return icon
    }

    override func statusBarComponentDidClick(with view: NSView) {
        clickCount += 1
    }

    override func statusBarComponentMouseDown(with view: NSView) {
        clickCount += 1
    }
}

final class StatusBarProxyIconTests: XCTestCase, iTermObject {
    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { nil }

    private var window: NSWindow!
    private var component: RecordingWorkingDirectoryComponent!
    private var container: iTermStatusBarContainerView!
    private var scope: iTermVariableScope!

    override func setUp() {
        super.setUp()
        scope = iTermVariableScope()
        scope.add(iTermVariables(context: [], owner: self), toScopeNamed: nil)
        component = RecordingWorkingDirectoryComponent(configuration: [:], scope: scope)
        container = iTermStatusBarContainerView(component: component)
        container.frame = NSRect(x: 0, y: 0, width: 200, height: iTermGetStatusBarHeight())
        container.layoutSubviews()
        window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 40),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(container)
    }

    override func tearDown() {
        window.close()
        window = nil
        container = nil
        component = nil
        scope = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func mouseEvent(_ type: NSEvent.EventType, at pointInContainer: NSPoint) -> NSEvent {
        let pointInWindow = container.convert(pointInContainer, to: nil)
        return NSEvent.mouseEvent(with: type,
                                  location: pointInWindow,
                                  modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber,
                                  context: nil,
                                  eventNumber: 0,
                                  clickCount: 1,
                                  pressure: type == .leftMouseUp ? 0 : 1)!
    }

    private var iconCenter: NSPoint {
        let frame = container.iconImageView!.frame
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private var textPoint: NSPoint {
        let iconFrame = container.iconImageView!.frame
        return NSPoint(x: iconFrame.maxX + 40, y: container.bounds.midY)
    }

    private var clickRecognizer: NSClickGestureRecognizer? {
        return container.gestureRecognizers.compactMap { $0 as? NSClickGestureRecognizer }.first
    }

    // Asks the container, as the click recognizer's delegate, whether the recognizer may try to
    // recognize a mouse-down at `point`. Synthetic events sent through NSWindow do not drive
    // gesture recognizers in a test, so this exercises the decision directly.
    private func recognizerMayAttempt(_ type: NSEvent.EventType = .leftMouseDown,
                                      at point: NSPoint) -> Bool? {
        guard let recognizer = clickRecognizer,
              let delegate = recognizer.delegate,
              delegate === container else {
            return nil
        }
        return container.gestureRecognizer(recognizer,
                                            shouldAttemptToRecognizeWith: mouseEvent(type, at: point))
    }

    // MARK: - Tests

    func testIconIsProxyIcon() {
        XCTAssertTrue(container.iconImageView is iTermStatusBarProxyIconImageView)
    }

    // F-213: the container's click recognizer delays mouse events and, when it recognized a
    // click on the icon, swallowed them, so the icon never saw its click and nothing happened.
    func testClickRecognizerLeavesProxyIconClicksToTheIcon() {
        XCTAssertEqual(recognizerMayAttempt(at: iconCenter), false,
                       "The click recognizer must not take clicks that land on the proxy icon")
    }

    func testClickRecognizerStillHandlesClicksOnText() {
        XCTAssertFalse(NSPointInRect(textPoint, container.iconImageView!.frame))
        XCTAssertEqual(recognizerMayAttempt(at: textPoint), true)
    }

    // The decision is made where the mouse went down and holds for the rest of the gesture, so
    // one press-and-release is never split between the icon and the recognizer (which could
    // open the menu twice).
    func testGestureBeganOnIconStaysWithIconWhenReleasedOverText() {
        XCTAssertEqual(recognizerMayAttempt(.leftMouseDown, at: iconCenter), false)
        XCTAssertEqual(recognizerMayAttempt(.leftMouseDragged, at: textPoint), false)
        XCTAssertEqual(recognizerMayAttempt(.leftMouseUp, at: textPoint), false)
    }

    func testGestureBeganOnTextStaysWithRecognizerWhenReleasedOverIcon() {
        XCTAssertEqual(recognizerMayAttempt(.leftMouseDown, at: textPoint), true)
        XCTAssertEqual(recognizerMayAttempt(.leftMouseUp, at: iconCenter), true)
    }

    func testEachGestureIsDecidedAfresh() {
        XCTAssertEqual(recognizerMayAttempt(.leftMouseDown, at: iconCenter), false)
        XCTAssertEqual(recognizerMayAttempt(.leftMouseUp, at: iconCenter), false)
        XCTAssertEqual(recognizerMayAttempt(.leftMouseDown, at: textPoint), true)
        XCTAssertEqual(recognizerMayAttempt(.leftMouseUp, at: textPoint), true)
    }

    // These drive the icon directly (they don't involve the recognizer): once the icon has the
    // mouse-down and mouse-up, a click without a drag must reach the component (which opens the
    // directory menu) exactly once.
    func testPlainClickOnProxyIconReachesComponentOnce() {
        let icon = container.iconImageView!
        icon.mouseDown(with: mouseEvent(.leftMouseDown, at: iconCenter))
        icon.mouseUp(with: mouseEvent(.leftMouseUp, at: iconCenter))
        XCTAssertEqual(component.clickCount, 1)
    }

    func testSmallMovementOnProxyIconIsStillAClick() {
        let icon = container.iconImageView!
        icon.mouseDown(with: mouseEvent(.leftMouseDown, at: iconCenter))
        let nudged = NSPoint(x: iconCenter.x + 1, y: iconCenter.y + 1)
        icon.mouseDragged(with: mouseEvent(.leftMouseDragged, at: nudged))
        icon.mouseUp(with: mouseEvent(.leftMouseUp, at: nudged))
        XCTAssertEqual(component.clickCount, 1)
    }

    // MARK: - Click vs. drag classification

    func testMovementBelowThresholdIsClick() {
        XCTAssertFalse(iTermStatusBarProxyIconImageView.movementIsDrag(from: .zero, to: .zero))
        XCTAssertFalse(iTermStatusBarProxyIconImageView.movementIsDrag(from: NSPoint(x: 5, y: 5),
                                                                       to: NSPoint(x: 8, y: 5)))
        XCTAssertFalse(iTermStatusBarProxyIconImageView.movementIsDrag(from: NSPoint(x: 5, y: 5),
                                                                       to: NSPoint(x: 7, y: 7)))
    }

    func testMovementAtOrBeyondThresholdIsDrag() {
        XCTAssertTrue(iTermStatusBarProxyIconImageView.movementIsDrag(from: .zero,
                                                                      to: NSPoint(x: 4, y: 0)))
        XCTAssertTrue(iTermStatusBarProxyIconImageView.movementIsDrag(from: NSPoint(x: 5, y: 5),
                                                                      to: NSPoint(x: 8, y: 8)))
        XCTAssertTrue(iTermStatusBarProxyIconImageView.movementIsDrag(from: .zero,
                                                                      to: NSPoint(x: 0, y: -10)))
    }

    // MARK: - Whether a directory is offered for dragging (F-214)

    private func makeTemporaryDirectory() throws -> String {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("ProxyIcon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: path)
        }
        return path
    }

    func testExistingLocalDirectoryIsDraggable() throws {
        let path = try makeTemporaryDirectory()
        let url = iTermStatusBarProxyIconImageView.directoryURL(forPath: path, isLocal: true)
        XCTAssertEqual(url, URL(fileURLWithPath: path, isDirectory: true))
    }

    func testDeletedDirectoryIsNotDraggable() throws {
        let path = try makeTemporaryDirectory()
        try FileManager.default.removeItem(atPath: path)
        XCTAssertNil(iTermStatusBarProxyIconImageView.directoryURL(forPath: path, isLocal: true))
    }

    func testRemoteDirectoryIsNotDraggable() throws {
        let path = try makeTemporaryDirectory()
        XCTAssertNil(iTermStatusBarProxyIconImageView.directoryURL(forPath: path, isLocal: false))
    }

    func testRegularFileIsNotDraggable() throws {
        let dir = try makeTemporaryDirectory()
        let file = (dir as NSString).appendingPathComponent("file.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: file, contents: Data()))
        XCTAssertNil(iTermStatusBarProxyIconImageView.directoryURL(forPath: file, isLocal: true))
    }

    func testEmptyOrMissingPathIsNotDraggable() {
        XCTAssertNil(iTermStatusBarProxyIconImageView.directoryURL(forPath: nil, isLocal: true))
        XCTAssertNil(iTermStatusBarProxyIconImageView.directoryURL(forPath: "", isLocal: true))
    }

    // The bug: the icon cached its URL when the path changed, so after the current directory was
    // deleted (with no cd since) it could still be dragged. The check must happen when the drag
    // starts.
    func testProxyIconRechecksExistenceWhenDragStarts() throws {
        let path = try makeTemporaryDirectory()
        scope.setValue(NSNumber(value: true), forVariableNamed: iTermVariableKeySessionIsLocalhost)
        scope.setValue(path, forVariableNamed: iTermVariableKeySessionPath)
        container.layoutSubviews()
        let icon = try XCTUnwrap(container.iconImageView as? iTermStatusBarProxyIconImageView)

        XCTAssertEqual(icon.urlForDrag(), URL(fileURLWithPath: path, isDirectory: true))

        // Nothing else happens between the deletion and the drag: no cd, no relayout.
        try FileManager.default.removeItem(atPath: path)

        XCTAssertNil(icon.urlForDrag(), "A deleted directory must not be offered for dragging")
    }

    func testProxyIconIsNotDraggableForRemoteSession() throws {
        let path = try makeTemporaryDirectory()
        scope.setValue(NSNumber(value: false), forVariableNamed: iTermVariableKeySessionIsLocalhost)
        scope.setValue(path, forVariableNamed: iTermVariableKeySessionPath)
        let icon = try XCTUnwrap(container.iconImageView as? iTermStatusBarProxyIconImageView)
        XCTAssertNil(icon.urlForDrag())
    }
}
