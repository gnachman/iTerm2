//
//  TabBarOrderControllerTests.swift
//  ModernTests
//
//  What keeps a sorted tab bar steady: the prompt section waits for a state
//  to hold, and nothing moves while the pointer is over the bar.
//

import XCTest
@testable import iTerm2SharedARC

final class TabBarOrderControllerTests: XCTestCase {
    private var controller: TabBarOrderController!
    private var time: TimeInterval = 1000
    private var tabs = [TabBarOrderLiveTab]()
    private var pointerInside = false
    private var updates = 0

    override func setUp() {
        super.setUp()
        controller = TabBarOrderController()
        controller.now = { [unowned self] in self.time }
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
                      atPrompt: Bool = false,
                      priority: Int = Int.max) -> TabBarOrderLiveTab {
        return TabBarOrderLiveTab(key: key,
                                  pinned: false,
                                  statusPriority: priority,
                                  snoozed: false,
                                  directory: directory,
                                  atPrompt: atPrompt,
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

    func testATabJoinsThePromptSectionOnlyAfterItHasBeenThereAWhile() {
        controller.mode = .workingDirectory
        tabs = [live(1), live(2, directory: "/b")]
        XCTAssertEqual(apply().order, [0, 1])

        tabs = [live(1, atPrompt: true), live(2, directory: "/b")]
        XCTAssertEqual(apply().order, [0, 1], "not yet")
        time += 0.5
        XCTAssertEqual(apply().order, [0, 1], "still not")
        time += 0.6
        let result = apply()
        XCTAssertEqual(result.order, [1, 0])
        XCTAssertEqual(sections(result)[0], TabBarOrder.promptSectionIdentifier)
    }

    func testABriefChangeIsIgnored() {
        controller.mode = .workingDirectory
        tabs = [live(1, atPrompt: true)]
        apply()
        tabs = [live(1, atPrompt: false)]
        time += 0.3
        apply()
        tabs = [live(1, atPrompt: true)]
        time += 0.3
        apply()
        tabs = [live(1, atPrompt: false)]
        time += 0.8
        XCTAssertEqual(sections(apply())[0], TabBarOrder.promptSectionIdentifier,
                       "the last change started 0.8 seconds ago")
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

    func testPollingWaitsForThePromptStateToHold() {
        controller.mode = .workingDirectory
        tabs = [live(1), live(2, directory: "/b")]
        apply()
        tabs = [live(1, atPrompt: true), live(2, directory: "/b")]
        controller.poll()
        XCTAssertEqual(updates, 0)
        time += 1.1
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

    // The Status order doesn't track prompts, so switching to the directory
    // order places tabs at a prompt at once rather than holding them.
    func testSwitchingToTheDirectoryOrderPlacesPromptTabsAtOnce() {
        controller.mode = .status
        tabs = [TabBarOrderLiveTab(key: 1, pinned: false, statusPriority: Int.max, snoozed: false,
                                   directory: nil, atPrompt: false, group: nil)]
        apply()
        controller.mode = .workingDirectory
        tabs = [live(1, atPrompt: true)]
        XCTAssertEqual(sections(apply())[0], TabBarOrder.promptSectionIdentifier)
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

    func testManualOrderIgnoresChanges() {
        tabs = [live(1)]
        controller.inputsDidChange()
        XCTAssertEqual(updates, 0)
    }

    func testANewTabIsPlacedByItsCurrentState() {
        controller.mode = .workingDirectory
        tabs = [live(1)]
        apply()
        tabs = [live(1), live(2, atPrompt: true)]
        let result = apply()
        XCTAssertEqual(sections(result)[1], TabBarOrder.promptSectionIdentifier,
                       "no earlier state to hold")
    }
}
