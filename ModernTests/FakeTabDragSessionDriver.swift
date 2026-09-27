//
//  FakeTabDragSessionDriver.swift
//  iTerm2XCTests
//
//  A stand-in for the AppKit services a tab drag uses, so drag tests can run a
//  whole drag without the window server.
//

import AppKit
@testable import iTerm2SharedARC

/// Simulates what AppKit does for a tab drag, without asking it to do any of it.
///
/// A real `-beginDraggingSessionWithItems:event:source:` does not run the drag
/// inline: it arms an NSCoreDragManager run-loop observer, and the drag starts
/// the next time anything pumps the run loop. In a test process that observer
/// outlives the test that armed it and detonates inside some later test, which
/// then blocks forever in AppKit's modal drag-tracking loop waiting for a
/// mouse-up nobody will post. This driver records the session instead of
/// starting one, and drives pointer updates on demand, synchronously.
final class FakeTabDragSessionDriver: NSObject, PSMTabDragSessionDriver {
    // What the assistant asked for, for tests that want to assert on the session.
    private(set) var startedSessionCount = 0
    private(set) var lastDraggingItems: [NSDraggingItem] = []
    private(set) var lastEvent: NSEvent?
    private(set) weak var lastTabBar: PSMTabBarControl?

    /// Whether the assistant currently wants pointer updates. The real driver
    /// has a running CVDisplayLink exactly while this is true.
    private(set) var isTrackingMouse = false
    private(set) var stopMouseTrackingCount = 0

    /// Where the fake pointer is. The assistant reads this from
    /// `-displayLinkDidFire`.
    var currentMouseLocation: NSPoint = .zero

    private var handler: (() -> Void)?

    // MARK: - PSMTabDragSessionDriver

    func startDragSession(with items: [NSDraggingItem],
                          event: NSEvent,
                          inTabBar control: PSMTabBarControl) {
        startedSessionCount += 1
        lastDraggingItems = items
        lastEvent = event
        lastTabBar = control
    }

    func startMouseTracking(handler: @escaping () -> Void) {
        self.handler = handler
        isTrackingMouse = true
    }

    func stopMouseTracking() {
        stopMouseTrackingCount += 1
        isTrackingMouse = false
        handler = nil
    }

    // MARK: - Simulation

    /// Deliver one pointer update, the way a CVDisplayLink tick would during a
    /// live drag. Synchronous and run-loop-free, so a test can step a drag
    /// deterministically. Does nothing when tracking is not running, matching
    /// the real driver.
    func simulateMouseMove(to screenPoint: NSPoint) {
        currentMouseLocation = screenPoint
        handler?()
    }

    /// Drag the pointer along a path, one update per point.
    func simulateMouseDrag(through screenPoints: [NSPoint]) {
        for point in screenPoints {
            simulateMouseMove(to: point)
        }
    }
}
