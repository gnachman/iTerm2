//
//  PSMTabBarPointerHoldTests.swift
//  ModernTests
//
//  A pointer over the tab bar holds tabs in place only while it's active:
//  it moved within PSMTabBarPointerHoldInterval, or a mouse button is down.
//  A resting pointer releases the bar so it doesn't show stale state. The
//  clock, hit test, pressed buttons, and idle timer are all injected, so
//  nothing here depends on real time.
//

import XCTest
@testable import iTerm2SharedARC

private final class PointerHoldDelegate: NSObject, PSMTabBarControlDelegate {
    var releases = 0

    func tabView(_ tabView: NSTabView, updateStateFor tabViewItem: NSTabViewItem) {
    }

    // Optional, but the bar calls it unconditionally when given a delegate.
    func tabViewShouldAllowDrag(onAddTabButton tabView: NSTabView) -> Bool {
        return false
    }

    func tabViewPointerDidReleaseTabBar(_ tabView: NSTabView) {
        releases += 1
    }
}

final class PSMTabBarPointerHoldTests: XCTestCase {
    private var window: NSWindow!
    private var control: PSMTabBarControl!
    private var tabView: NSTabView!
    private var delegate: PointerHoldDelegate!
    private var now: TimeInterval = 1000
    // Delays the idle check was scheduled with, in order.
    private var scheduled = [TimeInterval]()

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        control = PSMTabBarControl(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        control.style.tabBar = control
        control.orientation = .verticalOrientation
        window.contentView?.addSubview(control)
        tabView = NSTabView(frame: NSRect(x: 200, y: 0, width: 400, height: 400))
        window.contentView?.addSubview(tabView)
        control.tabView = tabView
        tabView.delegate = control
        delegate = PointerHoldDelegate()
        control.delegate = delegate

        now = 1000
        scheduled = []
        control.pointerIsInsideForTesting = NSNumber(value: true)
        control.pressedMouseButtonsForTesting = NSNumber(value: 0)
        control.pointerClockForTesting = { [unowned self] in self.now }
        control.pointerIdleTimerSchedulerForTesting = { [unowned self] delay in
            self.scheduled.append(delay)
        }
    }

    override func tearDown() {
        control.removeFromSuperview()
        delegate = nil
        tabView = nil
        control = nil
        window = nil
        super.tearDown()
    }

    func testAMovingPointerHoldsTabsUntilTheIntervalPasses() {
        XCTAssertFalse(control.pointerIsHoldingTabs, "it never moved")
        control.pointerDidMove()
        XCTAssertTrue(control.pointerIsHoldingTabs)
        now += PSMTabBarPointerHoldInterval - 0.1
        XCTAssertTrue(control.pointerIsHoldingTabs)
        now += 0.1
        XCTAssertFalse(control.pointerIsHoldingTabs, "it rested for the whole interval")
    }

    func testAPointerOutsideTheBarDoesNotHoldTabs() {
        control.pointerDidMove()
        control.pointerIsInsideForTesting = NSNumber(value: false)
        XCTAssertFalse(control.pointerIsHoldingTabs)
    }

    func testRestingReleasesTheBarOnceAfterTheLastMove() {
        control.pointerDidMove()
        XCTAssertEqual(scheduled, [PSMTabBarPointerHoldInterval])

        // Moving again doesn't schedule another check.
        now += 1
        control.pointerDidMove()
        XCTAssertEqual(scheduled.count, 1)

        // The first check finds it moved since and waits out the rest.
        now += 1
        control.pointerIdleTimerDidFire()
        XCTAssertEqual(delegate.releases, 0)
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(scheduled[1], 1, accuracy: 0.0001)

        now += 1
        control.pointerIdleTimerDidFire()
        XCTAssertEqual(delegate.releases, 1)
        XCTAssertEqual(scheduled.count, 2, "nothing more to check")
        XCTAssertFalse(control.pointerIsHoldingTabs)
    }

    // A slow click or a drag sends no mouseMoved:, and one that began outside
    // the bar sends the bar no events at all. A held button holds the bar
    // however long it lasts, and the release is still noticed.
    func testAHeldButtonHoldsTheBarUntilReleased() {
        control.pressedMouseButtonsForTesting = NSNumber(value: 1)
        XCTAssertTrue(control.pointerIsHoldingTabs)
        XCTAssertEqual(scheduled.count, 1, "asking arms the idle check")

        now += 10 * PSMTabBarPointerHoldInterval
        XCTAssertTrue(control.pointerIsHoldingTabs)
        control.pointerIdleTimerDidFire()
        XCTAssertEqual(delegate.releases, 0)
        XCTAssertEqual(scheduled.count, 2, "checks again while the button is down")

        control.pressedMouseButtonsForTesting = NSNumber(value: 0)
        now += PSMTabBarPointerHoldInterval
        control.pointerIdleTimerDidFire()
        XCTAssertEqual(delegate.releases, 1)
        XCTAssertFalse(control.pointerIsHoldingTabs)
    }

    // The pointer can stop being over the bar without an exit, as when it
    // goes onto the window's buttons. A button held down elsewhere then
    // must not keep the bar waiting.
    func testAButtonHeldOutsideTheBarDoesNotKeepItWaiting() {
        control.pointerDidMove()
        control.pointerIsInsideForTesting = NSNumber(value: false)
        control.pressedMouseButtonsForTesting = NSNumber(value: 1)
        XCTAssertFalse(control.pointerIsHoldingTabs)

        now += 0.5
        control.pointerIdleTimerDidFire()
        XCTAssertEqual(delegate.releases, 1)
        XCTAssertEqual(scheduled.count, 1, "not checked again")
    }

    func testLeavingTheWindowCancelsTheIdleCheck() {
        control.pointerDidMove()
        control.removeFromSuperview()
        XCTAssertFalse(control.pointerIsHoldingTabs)
        // A check that was already on its way finds nothing to do.
        now += PSMTabBarPointerHoldInterval
        control.pointerIdleTimerDidFire()
        XCTAssertEqual(delegate.releases, 0)
    }
}
