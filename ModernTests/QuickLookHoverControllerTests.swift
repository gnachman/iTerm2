//
//  QuickLookHoverControllerTests.swift
//  ModernTests
//
//  The Quick Look hover controller is a pure state machine: pointer, modifier and click inputs go in,
//  timers go through an injected scheduler, and open/close requests come out through a delegate.
//  These tests drive it with a fake scheduler so none of them depend on wall-clock time.
//

import XCTest
@testable import iTerm2SharedARC

private final class FakeScheduler: iTermQuickLookScheduling {
    final class Item: iTermQuickLookCancellable {
        let delay: TimeInterval
        let block: () -> Void
        var isCancelled = false
        var hasFired = false

        init(delay: TimeInterval, block: @escaping () -> Void) {
            self.delay = delay
            self.block = block
        }

        func cancel() {
            isCancelled = true
        }
    }

    private(set) var items = [Item]()

    var active: [Item] {
        return items.filter { !$0.isCancelled && !$0.hasFired }
    }

    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> iTermQuickLookCancellable {
        let item = Item(delay: delay, block: block)
        items.append(item)
        return item
    }

    // Runs every pending timer that was scheduled with exactly this delay.
    func fire(delay: TimeInterval) {
        for item in active where item.delay == delay {
            item.hasFired = true
            item.block()
        }
    }
}

private final class RecordingDelegate: iTermQuickLookHoverControllerDelegate {
    struct Open {
        let url: URL
        let linkRects: [NSRect]
        let point: NSPoint
    }

    var resolution: (url: URL?, linkRects: [NSRect]) = (nil, [])
    var defersCompletion = false
    var deferredCompletions = [(URL?, [NSRect]) -> Void]()
    var resolvedPoints = [NSPoint]()
    var opens = [Open]()
    var closeCount = 0
    var previewFrame: NSRect?
    // Runs inside hoverControllerOpenPreview, after the open is recorded.
    var onOpen: (() -> Void)?
    // When true, hoverControllerOpenPreview records the attempt but declines it.
    var declinesOpen = false

    func hoverControllerResolveLink(at point: NSPoint,
                                    completion: @escaping (URL?, [NSRect]) -> Void) {
        resolvedPoints.append(point)
        if defersCompletion {
            deferredCompletions.append(completion)
        } else {
            completion(resolution.url, resolution.linkRects)
        }
    }

    func hoverControllerOpenPreview(url: URL, linkRects: [NSRect], at point: NSPoint) -> Bool {
        opens.append(Open(url: url, linkRects: linkRects, point: point))
        onOpen?()
        return !declinesOpen
    }

    func hoverControllerClosePreview() {
        closeCount += 1
    }

    func hoverControllerPreviewFrame() -> NSRect? {
        return previewFrame
    }

    var cues = [URL]()
    var cueClearCount = 0

    func hoverControllerShowCue(url: URL, linkRects: [NSRect]) {
        cues.append(url)
    }

    func hoverControllerClearCue() {
        cueClearCount += 1
    }
}

final class QuickLookHoverControllerTests: XCTestCase {
    private var scheduler: FakeScheduler!
    private var delegate: RecordingDelegate!
    private var controller: iTermQuickLookHoverController!

    private let urlA = URL(string: "https://example.com/a")!
    private let urlB = URL(string: "https://example.org/b")!
    private let rectA = NSRect(x: 10, y: 10, width: 100, height: 16)
    private let rectB = NSRect(x: 10, y: 400, width: 100, height: 16)
    private let pointOnA = NSPoint(x: 20, y: 18)
    private let pointOnB = NSPoint(x: 20, y: 408)
    private let pointNowhere = NSPoint(x: 700, y: 700)
    private let pointInPreview = NSPoint(x: 250, y: 150)
    private let previewFrame = NSRect(x: 200, y: 100, width: 300, height: 200)

    override func setUp() {
        super.setUp()
        scheduler = FakeScheduler()
        delegate = RecordingDelegate()
        controller = iTermQuickLookHoverController(scheduler: scheduler)
        controller.delegate = delegate
        delegate.resolution = (urlA, [rectA])
        delegate.previewFrame = previewFrame
        configure()
    }

    override func tearDown() {
        controller = nil
        delegate = nil
        scheduler = nil
        super.tearDown()
    }

    private func configure(mode: iTermQuickLookHoverMode = .hover,
                           delay: TimeInterval = 0.75,
                           autoCloseDelay: TimeInterval = 1.5,
                           allowlist: String = "") {
        controller.configure(mode: mode,
                             delay: delay,
                             autoCloseDelay: autoCloseDelay,
                             allowlistString: allowlist)
    }

    private func move(_ point: NSPoint,
                      command: Bool = false,
                      option: Bool = false,
                      active: Bool = true) {
        controller.pointerMoved(to: point,
                                commandDown: command,
                                optionDown: option,
                                windowActive: active)
    }

    private func openPreviewOnA() {
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
    }

    // MARK: - Gating

    func testOffModeNeverSchedules() {
        configure(mode: .off)
        move(pointOnA)
        move(pointOnA, command: true)
        XCTAssertTrue(scheduler.items.isEmpty)
    }

    func testHoverOpensAfterDelay() {
        move(pointOnA)
        XCTAssertEqual(scheduler.active.count, 1)
        XCTAssertEqual(scheduler.active.first?.delay, 0.75)
        XCTAssertTrue(delegate.opens.isEmpty)
        XCTAssertTrue(delegate.resolvedPoints.isEmpty)

        scheduler.fire(delay: 0.75)

        XCTAssertEqual(delegate.resolvedPoints, [pointOnA])
        XCTAssertEqual(delegate.opens.count, 1)
        XCTAssertEqual(delegate.opens.first?.url, urlA)
        XCTAssertEqual(delegate.opens.first?.linkRects, [rectA])
        XCTAssertEqual(delegate.opens.first?.point, pointOnA)
    }

    func testMoveRestartsDelay() {
        move(pointOnA)
        move(NSPoint(x: 30, y: 18))
        XCTAssertEqual(scheduler.items.count, 2)
        XCTAssertTrue(scheduler.items[0].isCancelled)
        XCTAssertFalse(scheduler.items[1].isCancelled)
        XCTAssertEqual(scheduler.active.count, 1)
    }

    func testCommandHoverRequiresCommand() {
        configure(mode: .commandHover)
        move(pointOnA)
        XCTAssertTrue(scheduler.items.isEmpty)
        move(pointOnA, command: true)
        XCTAssertEqual(scheduler.active.count, 1)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
    }

    func testCommandReleaseCancelsPending() {
        configure(mode: .commandHover)
        move(pointOnA, command: true)
        XCTAssertEqual(scheduler.active.count, 1)
        controller.modifiersChanged(commandDown: false, optionDown: false)
        XCTAssertTrue(scheduler.active.isEmpty)
        XCTAssertTrue(delegate.opens.isEmpty)
    }

    func testOptionBlocksCommandHover() {
        configure(mode: .commandHover)
        move(pointOnA, command: true, option: true)
        XCTAssertTrue(scheduler.items.isEmpty)

        move(pointOnA, command: true)
        XCTAssertEqual(scheduler.active.count, 1)
        controller.modifiersChanged(commandDown: true, optionDown: true)
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testCommandReleaseDoesNotCancelPendingInHoverMode() {
        move(pointOnA, command: true)
        controller.modifiersChanged(commandDown: false, optionDown: false)
        XCTAssertEqual(scheduler.active.count, 1)
    }

    func testInactiveWindowDoesNotSchedule() {
        move(pointOnA, active: false)
        XCTAssertTrue(scheduler.items.isEmpty)
    }

    func testMoveInInactiveWindowCancelsPending() {
        move(pointOnA)
        move(pointOnA, active: false)
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testDeactivationCancelsPending() {
        move(pointOnA)
        controller.deactivated()
        XCTAssertTrue(scheduler.active.isEmpty)
        XCTAssertEqual(delegate.closeCount, 0)
    }

    func testKeyPressCancelsPending() {
        move(pointOnA)
        controller.keyDown()
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testMouseDownCancelsPending() {
        move(pointOnA)
        controller.mouseDown()
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testScrollCancelsPending() {
        move(pointOnA)
        controller.scrolled()
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    // MARK: - Resolution filtering

    func testAllowlistBlocksOtherHosts() {
        configure(allowlist: "linear.app")
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.resolvedPoints.count, 1)
        XCTAssertTrue(delegate.opens.isEmpty)

        delegate.resolution = (URL(string: "https://www.linear.app/t/RD-1")!, [rectA])
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
    }

    func testNonWebURLIgnored() {
        for string in ["file:///tmp/x", "ftp://example.com/x", "ssh://example.com"] {
            delegate.resolution = (URL(string: string)!, [rectA])
            move(pointOnA)
            scheduler.fire(delay: 0.75)
        }
        XCTAssertTrue(delegate.opens.isEmpty)
    }

    func testNoLinkAtPointIgnored() {
        delegate.resolution = (nil, [])
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertTrue(delegate.opens.isEmpty)
    }

    func testPointOutsideLinkRectsIgnored() {
        delegate.resolution = (urlA, [rectB])
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertTrue(delegate.opens.isEmpty)
    }

    func testStaleResolutionIgnored() {
        delegate.defersCompletion = true
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.deferredCompletions.count, 1)

        move(NSPoint(x: 30, y: 18))
        delegate.deferredCompletions[0](urlA, [rectA])
        XCTAssertTrue(delegate.opens.isEmpty)

        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.deferredCompletions.count, 2)
        delegate.deferredCompletions[1](urlA, [rectA])
        XCTAssertEqual(delegate.opens.count, 1)
    }

    func testResolutionCompletingAfterCancelIsIgnored() {
        delegate.defersCompletion = true
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        controller.keyDown()
        delegate.deferredCompletions[0](urlA, [rectA])
        XCTAssertTrue(delegate.opens.isEmpty)
    }

    // MARK: - Auto-close

    func testAutoCloseStartsWhenLeavingLinkAndPreview() {
        openPreviewOnA()
        move(pointNowhere)
        XCTAssertEqual(scheduler.active.filter { $0.delay == 1.5 }.count, 1)
        XCTAssertEqual(delegate.closeCount, 0)

        scheduler.fire(delay: 1.5)

        XCTAssertEqual(delegate.closeCount, 1)
    }

    func testMovesInsideLinkOrPreviewDoNotStartAutoClose() {
        openPreviewOnA()
        move(NSPoint(x: 30, y: 18))
        move(pointInPreview)
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testAutoCloseStartedOnlyOncePerExit() {
        openPreviewOnA()
        move(pointNowhere)
        move(NSPoint(x: 701, y: 700))
        XCTAssertEqual(scheduler.items.filter { $0.delay == 1.5 }.count, 1)
        XCTAssertFalse(scheduler.items.first { $0.delay == 1.5 }!.isCancelled)
    }

    func testReenteringPreviewCancelsAutoClose() {
        openPreviewOnA()
        move(pointNowhere)
        move(pointInPreview)
        XCTAssertTrue(scheduler.active.isEmpty)
        scheduler.fire(delay: 1.5)
        XCTAssertEqual(delegate.closeCount, 0)
    }

    func testReenteringLinkCancelsAutoClose() {
        openPreviewOnA()
        move(pointNowhere)
        move(pointOnA)
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testNeverAutoClose() {
        for never in [0.0, -1.0] {
            configure(autoCloseDelay: never)
            let before = scheduler.items.count
            openPreviewOnA()
            move(pointNowhere)
            XCTAssertTrue(scheduler.items[before...].allSatisfy { $0.delay == 0.75 })
            scheduler.fire(delay: 0.75)
            XCTAssertEqual(delegate.closeCount, 0)
            controller.previewClosed()
            delegate.opens.removeAll()
        }
    }

    func testClickInPreviewDisablesAutoClose() {
        openPreviewOnA()
        controller.previewClicked()
        move(pointNowhere)
        XCTAssertTrue(scheduler.items.filter { $0.delay == 1.5 }.isEmpty)
    }

    func testClickInPreviewCancelsPendingAutoClose() {
        openPreviewOnA()
        move(pointNowhere)
        controller.previewClicked()
        scheduler.fire(delay: 1.5)
        XCTAssertEqual(delegate.closeCount, 0)
    }

    func testAutoCloseResetsToIdle() {
        openPreviewOnA()
        move(pointNowhere)
        scheduler.fire(delay: 1.5)
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 2)
    }

    // MARK: - Replacing and closing

    func testDifferentLinkReplacesPreview() {
        openPreviewOnA()
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        scheduler.fire(delay: 0.75)

        XCTAssertEqual(delegate.opens.count, 2)
        XCTAssertEqual(delegate.opens.last?.url, urlB)
        XCTAssertEqual(delegate.opens.last?.linkRects, [rectB])
        XCTAssertEqual(delegate.closeCount, 0)
        XCTAssertTrue(scheduler.active.isEmpty, "auto-close should be cancelled once the pointer is on the new link")
    }

    func testReplacementUsesNewLinkRectsForAutoClose() {
        openPreviewOnA()
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        scheduler.fire(delay: 0.75)
        move(pointOnA)
        XCTAssertEqual(scheduler.active.filter { $0.delay == 1.5 }.count, 1)
    }

    func testSameLinkDoesNotReopen() {
        openPreviewOnA()
        let secondOccurrence = NSRect(x: 650, y: 690, width: 100, height: 20)
        XCTAssertTrue(secondOccurrence.contains(pointNowhere))
        delegate.resolution = (urlA, [rectA, secondOccurrence])
        move(pointNowhere)
        XCTAssertEqual(scheduler.active.filter { $0.delay == 1.5 }.count, 1)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.resolvedPoints.last, pointNowhere)
        XCTAssertEqual(delegate.opens.count, 1)
        XCTAssertTrue(scheduler.active.isEmpty, "resting on another occurrence of the open link cancels auto-close")

        move(NSPoint(x: 720, y: 700))
        XCTAssertTrue(scheduler.active.filter { $0.delay == 1.5 }.isEmpty,
                      "the new occurrence counts as the link, so moving on it does not start auto-close")
    }

    func testCloseReportedWhileReplacingKeepsNewPreviewOpen() {
        openPreviewOnA()
        delegate.onOpen = { [unowned self] in
            self.controller.previewClosed()
        }
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 2)

        delegate.onOpen = nil
        move(pointNowhere)
        XCTAssertEqual(scheduler.active.filter { $0.delay == 1.5 }.count, 1,
                       "the replacement preview is still open, so leaving it starts auto-close")
    }

    // The host declines while the user has a force-press preview open. Nothing opened, so nothing
    // may auto-close, and resting on the link again tries again.
    func testDeclinedOpenLeavesControllerIdle() {
        delegate.declinesOpen = true
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)

        move(pointNowhere)
        XCTAssertTrue(scheduler.active.filter { $0.delay == 1.5 }.isEmpty,
                      "no hover preview is open, so there is nothing to auto-close")
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.closeCount, 0)

        delegate.declinesOpen = false
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 2, "the same link is not treated as already open")
    }

    func testDeclinedReplacementKeepsEarlierPreview() {
        openPreviewOnA()
        delegate.declinesOpen = true
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 2)

        move(pointOnA)
        XCTAssertTrue(scheduler.active.filter { $0.delay == 1.5 }.isEmpty,
                      "A is still the open preview, so resting on A does not start auto-close")
        move(pointNowhere)
        XCTAssertEqual(scheduler.active.filter { $0.delay == 1.5 }.count, 1)
    }

    func testRestingOutsideOnNonLinkKeepsPreview() {
        openPreviewOnA()
        delegate.resolution = (nil, [])
        move(pointNowhere)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
        XCTAssertEqual(delegate.closeCount, 0)
    }

    func testMovingBackIntoPreviewCancelsPendingReplacement() {
        openPreviewOnA()
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        move(pointInPreview)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
    }

    func testPreviewClosedResetsToIdle() {
        openPreviewOnA()
        move(pointNowhere)
        controller.previewClosed()
        XCTAssertTrue(scheduler.active.isEmpty)
        XCTAssertEqual(delegate.closeCount, 0, "the user already closed it")

        move(pointOnA)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 2)
    }

    func testPreviewClosedIgnoresInFlightResolution() {
        delegate.defersCompletion = true
        move(pointOnA)
        scheduler.fire(delay: 0.75)
        controller.previewClosed()
        delegate.deferredCompletions[0](urlA, [rectA])
        XCTAssertTrue(delegate.opens.isEmpty)
    }

    func testDeactivationClosesHoverPreview() {
        openPreviewOnA()
        controller.deactivated()
        XCTAssertEqual(delegate.closeCount, 1)
        XCTAssertTrue(scheduler.active.isEmpty)
    }

    func testDeactivationDoesNotCloseClickedPreview() {
        openPreviewOnA()
        controller.previewClicked()
        controller.deactivated()
        XCTAssertEqual(delegate.closeCount, 0)
    }

    func testDeactivationCancelsPendingAutoClose() {
        openPreviewOnA()
        move(pointNowhere)
        controller.deactivated()
        XCTAssertTrue(scheduler.active.isEmpty)
        XCTAssertEqual(delegate.closeCount, 1)
    }

    func testReopeningAfterReplacementClearsClickedFlag() {
        openPreviewOnA()
        controller.previewClicked()
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        scheduler.fire(delay: 0.75)
        move(pointNowhere)
        XCTAssertEqual(scheduler.items.filter { $0.delay == 1.5 && !$0.isCancelled }.count, 1)
    }

    // Hover previews OSC 8 hyperlinks always, and plain-text URLs only when the user opts in.
    func testHoverPreviewsOnlyHyperlinksUnlessPlainTextURLsAreIncluded() {
        XCTAssertTrue(iTermQuickLookHoverAdapter.shouldHoverPreview(isOSC8: true, includesPlainTextURLs: false))
        XCTAssertTrue(iTermQuickLookHoverAdapter.shouldHoverPreview(isOSC8: true, includesPlainTextURLs: true))
        XCTAssertFalse(iTermQuickLookHoverAdapter.shouldHoverPreview(isOSC8: false, includesPlainTextURLs: false))
        XCTAssertTrue(iTermQuickLookHoverAdapter.shouldHoverPreview(isOSC8: false, includesPlainTextURLs: true))
    }

    // MARK: - Cue

    private func showCueOnA() {
        controller.cueSettleDelay = 0.1
        move(pointOnA)
        scheduler.fire(delay: 0.1)
        XCTAssertEqual(delegate.cues, [urlA])
    }

    func testCueShowsAfterSettleAndOpenReusesTheResolution() {
        controller.cueSettleDelay = 0.1
        move(pointOnA)
        XCTAssertEqual(scheduler.active.map(\.delay).sorted(), [0.1, 0.75])
        scheduler.fire(delay: 0.1)
        XCTAssertEqual(delegate.cues, [urlA])
        XCTAssertTrue(delegate.opens.isEmpty)

        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
        XCTAssertEqual(delegate.resolvedPoints, [pointOnA], "the open reuses the cue's resolution")
        XCTAssertEqual(delegate.cues, [urlA])
        XCTAssertEqual(delegate.cueClearCount, 0, "the cue may stay while the preview is open")
    }

    func testMovingWithinTheLinkKeepsTheCueWithoutResolvingAgain() {
        showCueOnA()
        let onA2 = NSPoint(x: 30, y: 18)
        move(onA2)
        XCTAssertEqual(delegate.cueClearCount, 0)
        XCTAssertEqual(scheduler.active.map(\.delay), [0.75])
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.first?.point, onA2)
        XCTAssertEqual(delegate.resolvedPoints, [pointOnA])
    }

    func testCueClearsWhenThePointerLeavesTheLink() {
        showCueOnA()
        move(pointNowhere)
        XCTAssertEqual(delegate.cueClearCount, 1)
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.cueClearCount, 1)
    }

    func testCueClearsOnClickKeyScrollAndDeactivation() {
        let cancels: [(iTermQuickLookHoverController) -> Void] = [
            { $0.mouseDown() },
            { $0.keyDown() },
            { $0.scrolled() },
            { $0.deactivated() },
        ]
        for (i, cancel) in cancels.enumerated() {
            showCueOnA()
            delegate.cues = []
            cancel(controller)
            XCTAssertEqual(delegate.cueClearCount, i + 1)
            scheduler.fire(delay: 0.75)
            XCTAssertTrue(delegate.opens.isEmpty)
        }
    }

    private func openPreviewWithCueOnA() {
        showCueOnA()
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
    }

    func testCueStaysWhileThePreviewIsOpen() {
        openPreviewWithCueOnA()
        move(pointInPreview)
        move(pointNowhere)
        move(pointOnA, active: false)
        controller.mouseDown()
        controller.keyDown()
        controller.scrolled()
        XCTAssertEqual(delegate.cueClearCount, 0, "the cue marks the open preview's link until it closes")
        XCTAssertEqual(delegate.cues, [urlA])
    }

    func testCueClearsWhenThePreviewCloses() {
        openPreviewWithCueOnA()
        move(pointInPreview)
        controller.previewClosed()
        XCTAssertEqual(delegate.cueClearCount, 1)

        move(pointNowhere)
        XCTAssertEqual(delegate.cueClearCount, 1)
    }

    func testCueClearsWhenAutoCloseCloses() {
        openPreviewWithCueOnA()
        move(pointInPreview)
        move(pointNowhere)
        XCTAssertEqual(delegate.cueClearCount, 0)
        scheduler.fire(delay: 1.5)
        XCTAssertEqual(delegate.closeCount, 1)
        XCTAssertEqual(delegate.cueClearCount, 1)
    }

    func testCueClearsWhenDeactivatedWhileOpen() {
        openPreviewWithCueOnA()
        controller.deactivated()
        XCTAssertEqual(delegate.closeCount, 1)
        XCTAssertEqual(delegate.cueClearCount, 1)
    }

    func testCueMovesToTheLinkThatReplacesThePreview() {
        openPreviewWithCueOnA()
        delegate.resolution = (urlB, [rectB])
        move(pointOnB)
        XCTAssertEqual(delegate.cueClearCount, 0, "the open preview keeps its cue until replaced")
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.last?.url, urlB)
        XCTAssertEqual(delegate.cues, [urlA, urlB])
        XCTAssertEqual(delegate.cueClearCount, 0)

        move(pointNowhere)
        XCTAssertEqual(delegate.cueClearCount, 0)
        controller.previewClosed()
        XCTAssertEqual(delegate.cueClearCount, 1)
    }

    func testNoCueInCommandHoverOrOffOrWhenTurnedOff() {
        configure(mode: .commandHover)
        controller.cueSettleDelay = 0.1
        move(pointOnA, command: true)
        XCTAssertEqual(scheduler.active.map(\.delay), [0.75])
        scheduler.fire(delay: 0.75)
        XCTAssertEqual(delegate.opens.count, 1)
        XCTAssertTrue(delegate.cues.isEmpty)

        controller.previewClosed()
        configure(mode: .off)
        move(pointOnA)
        XCTAssertTrue(scheduler.active.isEmpty)

        configure(mode: .hover)
        controller.cueSettleDelay = nil
        move(pointOnA)
        XCTAssertEqual(scheduler.active.map(\.delay), [0.75])
        scheduler.fire(delay: 0.75)
        XCTAssertTrue(delegate.cues.isEmpty)
    }

    func testNoCueForLinksThatWouldNotPreview() {
        configure(allowlist: "example.org")
        controller.cueSettleDelay = 0.1
        move(pointOnA)
        scheduler.fire(delay: 0.1)
        XCTAssertTrue(delegate.cues.isEmpty)

        delegate.resolution = (nil, [])
        move(NSPoint(x: 30, y: 18))
        scheduler.fire(delay: 0.1)
        XCTAssertTrue(delegate.cues.isEmpty)
    }

    func testStaleCueResolutionIsDropped() {
        controller.cueSettleDelay = 0.1
        delegate.defersCompletion = true
        move(pointOnA)
        scheduler.fire(delay: 0.1)
        move(pointNowhere)
        delegate.deferredCompletions.first?(urlA, [rectA])
        XCTAssertTrue(delegate.cues.isEmpty)
    }
}
