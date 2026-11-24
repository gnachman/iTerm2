//
//  TabBarOrderControllerTests.swift
//  ModernTests
//
//  What keeps a sorted tab bar current and steady: polling notices directory
//  changes, and nothing moves while the pointer is over the bar.
//

import XCTest
@testable import iTerm2SharedARC

final class TabBarOrderControllerTests: XCTestCase {
    private var controller: TabBarOrderController!
    private var tabs = [TabBarOrderLiveTab]()
    private var pointerInside = false
    private var updates = 0

    override func setUp() {
        super.setUp()
        controller = TabBarOrderController()
        controller.liveTabs = { [unowned self] in self.tabs }
        controller.pointerIsInside = { [unowned self] in self.pointerInside }
        controller.needsUpdate = { [unowned self] in self.updates += 1 }
    }

    override func tearDown() {
        controller.mode = .manual
        controller = nil
        super.tearDown()
    }

    private func live(_ key: Int,
                      directory: String? = "/a",
                      priority: Int = Int.max) -> TabBarOrderLiveTab {
        return TabBarOrderLiveTab(key: key,
                                  pinned: false,
                                  statusPriority: priority,
                                  snoozed: false,
                                  directory: directory,
                                  group: nil)
    }

    // Applies to the bar, as the window does.
    @discardableResult
    private func apply(useSnapshot: Bool = false) -> TabBarOrderResult {
        return controller.result(for: tabs, useSnapshot: useSnapshot, store: true)
    }

    private func sections(_ result: TabBarOrderResult) -> [String] {
        return result.sectionIdentifiers.map { ($0 as? String) ?? "" }
    }

    func testPollingNoticesADirectoryChange() {
        controller.mode = .workingDirectory
        tabs = [live(1), live(2, directory: "/b"), live(3)]
        apply()
        controller.poll()
        XCTAssertEqual(updates, 0, "nothing changed")
        tabs = [live(1), live(2, directory: "/b"), live(3, directory: "/b")]
        controller.poll()
        XCTAssertEqual(updates, 1)
    }

    func testNothingMovesWhileThePointerIsOverTheBar() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        XCTAssertEqual(apply().order, [0, 1])

        pointerInside = true
        tabs = [live(1, priority: 3), live(2, priority: 0)]
        controller.inputsDidChange()
        XCTAssertEqual(updates, 0, "waits for the pointer")
        XCTAssertTrue(controller.isHoldingBack)
        XCTAssertEqual(apply(useSnapshot: true).order, [0, 1], "tabs keep their places")

        controller.applyChangesHeldBackByPointer()
        XCTAssertEqual(updates, 0, "the pointer is still there")
        pointerInside = false
        controller.applyChangesHeldBackByPointer()
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(apply().order, [1, 0])
        XCTAssertFalse(controller.isHoldingBack)
    }

    // The pointer can leave without an exit, as when another window comes
    // up under it. The next change must not keep waiting for one.
    func testAChangeAfterAMissedExitApplies() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        apply()
        pointerInside = true
        tabs = [live(1, priority: 3), live(2, priority: 0)]
        controller.inputsDidChange()
        XCTAssertTrue(controller.isHoldingBack, "precondition")

        pointerInside = false
        controller.inputsDidChange()
        XCTAssertEqual(updates, 1)
        XCTAssertFalse(controller.isHoldingBack, "readers go by what tabs are now")
    }

    // A tab can change sections while the order and the sections stay the
    // same.
    func testPollingNoticesATabChangingSections() {
        controller.mode = .workingDirectory
        tabs = [live(1, directory: "/a"), live(2, directory: "/a"), live(3, directory: "/b")]
        apply()
        tabs = [live(1, directory: "/a"), live(2, directory: "/b"), live(3, directory: "/b")]
        controller.poll()
        XCTAssertEqual(updates, 1)
    }

    func testPollingIsSkippedWhileTheOrderIsntShown() {
        controller.mode = .workingDirectory
        var active = false
        controller.isActive = { active }
        tabs = [live(1, directory: "/a"), live(2, directory: "/b")]
        apply()
        tabs = [live(1, directory: "/b"), live(2, directory: "/b")]
        controller.poll()
        XCTAssertEqual(updates, 0)
        active = true
        controller.poll()
        XCTAssertEqual(updates, 1)
    }

    // After the bar stops showing the order, polling must notice when it can
    // again, even though nothing about the tabs changed.
    func testPollingAfterTheOrderWasDroppedAsksForAnUpdate() {
        controller.mode = .workingDirectory
        tabs = [live(1), live(2, directory: "/b")]
        apply()
        controller.poll()
        XCTAssertEqual(updates, 0, "precondition")
        controller.forgetApplied()
        controller.poll()
        XCTAssertEqual(updates, 1)
    }

    // While the bar wasn't shown nothing was frozen, so it shows what tabs
    // are now when it comes back, even under the pointer.
    func testAfterTheOrderWasDroppedTheSnapshotIsGone() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        apply()
        controller.forgetApplied()
        tabs = [live(1, priority: 3), live(2, priority: 0)]
        XCTAssertEqual(apply(useSnapshot: true).order, [1, 0])
    }

    // The pointer can leave without the bar hearing about it. A change that
    // waited for it still applies once it's gone.
    func testAChangeThatWaitedAppliesWhenThePointerLeavesWithoutAnExit() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        apply()
        pointerInside = true
        tabs = [live(1, priority: 3), live(2, priority: 0)]
        controller.inputsDidChange()
        XCTAssertTrue(controller.isHoldingBack, "precondition")

        let applied = expectation(description: "applied")
        controller.needsUpdate = { [unowned self] in
            self.updates += 1
            applied.fulfill()
        }
        pointerInside = false
        wait(for: [applied], timeout: 5)
        XCTAssertEqual(updates, 1)
        XCTAssertFalse(controller.isHoldingBack)
    }

    // The bar can be redrawn with the pointer over it before the window hears
    // of a change. It keeps the tabs where they were, and the change waits
    // for the pointer rather than being lost.
    func testApplyingUnderThePointerRemembersAChangeIsWaiting() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        apply()
        tabs = [live(1, priority: 3), live(2, priority: 0)]
        XCTAssertEqual(apply(useSnapshot: true).order, [0, 1])
        XCTAssertTrue(controller.isHoldingBack)
    }

    func testApplyingUnderThePointerWithNoChangeDoesntWait() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        apply()
        apply(useSnapshot: true)
        XCTAssertFalse(controller.isHoldingBack)
    }

    // Ordering by directory, a status change shows no differently, so
    // nothing waits.
    func testApplyingUnderThePointerIgnoresChangesTheOrderDoesntUse() {
        controller.mode = .workingDirectory
        tabs = [live(1, directory: "/a", priority: 3), live(2, directory: "/b", priority: 5)]
        apply()
        tabs = [live(1, directory: "/a", priority: 3), live(2, directory: "/b", priority: 0)]
        apply(useSnapshot: true)
        XCTAssertFalse(controller.isHoldingBack)
    }

    // A held priority is an index into the old list, so it would land
    // under the wrong heading. The edit is made in Settings, so the pointer
    // isn't over the bar even if the bar thinks so.
    func testEditingThePriorityListShowsTheTabsAsTheyAreNow() {
        controller.mode = .status
        tabs = [live(1, priority: 3), live(2, priority: 5)]
        apply()
        pointerInside = true
        tabs = [live(1, priority: 3), live(2, priority: 0)]
        controller.inputsDidChange()
        XCTAssertTrue(controller.isHoldingBack)

        controller.statusPrioritiesDidChange()
        XCTAssertEqual(updates, 1)
        XCTAssertFalse(controller.isHoldingBack)
        // The window goes by the snapshot while the pointer is inside.
        XCTAssertEqual(apply(useSnapshot: true).order, [1, 0], "the held priorities are gone")
    }

    func testEditingThePriorityListDoesNothingInOtherOrders() {
        controller.mode = .workingDirectory
        controller.statusPrioritiesDidChange()
        XCTAssertEqual(updates, 0)
    }

    func testManualOrderIgnoresChanges() {
        tabs = [live(1)]
        controller.inputsDidChange()
        XCTAssertEqual(updates, 0)
    }

}
