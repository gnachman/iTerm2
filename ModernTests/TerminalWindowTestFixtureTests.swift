//
//  TerminalWindowTestFixtureTests.swift
//  ModernTests
//
//  Checks that the window fixture and the mouse event synthesizer behave like the real thing, so
//  later tests built on them can be trusted.
//

import XCTest
@testable import iTerm2SharedARC

private final class MouseRecordingView: NSView {
    struct Record: Equatable {
        var type: NSEvent.EventType
        var location: NSPoint
        var modifiers: NSEvent.ModifierFlags
        var clickCount: Int

        static func == (lhs: Record, rhs: Record) -> Bool {
            return lhs.type == rhs.type &&
                lhs.location == rhs.location &&
                lhs.modifiers == rhs.modifiers &&
                lhs.clickCount == rhs.clickCount
        }
    }
    var records = [Record]()

    private func record(_ event: NSEvent) {
        records.append(Record(type: event.type,
                              location: convert(event.locationInWindow, from: nil),
                              modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                              clickCount: event.clickCount))
    }

    override func mouseDown(with event: NSEvent) { record(event) }
    override func mouseDragged(with event: NSEvent) { record(event) }
    override func mouseUp(with event: NSEvent) { record(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class TerminalWindowTestFixtureTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        fixture = TerminalWindowTestFixture()
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    func testOpensWindowWithOneSession() {
        let sessions = fixture.terminal.allSessions() ?? []
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions.first?.view?.window === fixture.window)
    }

    func testSplitAddsSecondPaneToTheSameTab() {
        guard let first = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let tab = fixture.terminal.currentTab()
        XCTAssertEqual(tab?.sessions()?.count, 2)
        XCTAssertTrue(second.view?.window === fixture.window)
        guard let firstFrame = first.view?.frame, let secondFrame = second.view?.frame else {
            XCTFail("Missing views")
            return
        }
        XCTAssertFalse(firstFrame.intersects(secondFrame), "split panes must tile")
    }

    func testClickingAPaneMakesItActive() {
        guard let first = fixture.terminal.currentSession() else {
            XCTFail("No session")
            return
        }
        let second = fixture.split(first, vertically: true)
        let tab = fixture.terminal.currentTab()
        tab?.setActiveSession(second)
        XCTAssertTrue(tab?.activeSession === second)

        guard let textView = first.textview else {
            XCTFail("No text view")
            return
        }
        fixture.mouse.click(at: fixture.center(of: textView))
        XCTAssertTrue(tab?.activeSession === first, "a click in a pane must make it the active session")
    }

    func testDragIsRoutedToTheViewThatTookTheMouseDown() {
        guard let contentView = fixture.window.contentView else {
            XCTFail("No content view")
            return
        }
        let recorder = MouseRecordingView(frame: NSRect(x: 20, y: 20, width: 100, height: 100))
        contentView.addSubview(recorder)
        defer { recorder.removeFromSuperview() }

        let start = recorder.convert(NSPoint(x: 50, y: 50), to: nil)
        // The drag ends outside the view; AppKit must still deliver it to the view that took the
        // mouse-down.
        let end = recorder.convert(NSPoint(x: 250, y: 50), to: nil)
        fixture.mouse.drag(from: start, to: end, steps: 4, modifiers: [.control])

        XCTAssertEqual(recorder.records.map(\.type),
                       [.leftMouseDown, .leftMouseDragged, .leftMouseDragged, .leftMouseDragged,
                        .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(recorder.records.first?.location, NSPoint(x: 50, y: 50))
        XCTAssertEqual(recorder.records.last?.location, NSPoint(x: 250, y: 50))
        XCTAssertEqual(recorder.records.map(\.location.x), [50, 100, 150, 200, 250, 250])
        XCTAssertTrue(recorder.records.allSatisfy { $0.modifiers == [.control] })
    }

    func testDoubleClickCarriesClickCount() {
        guard let contentView = fixture.window.contentView else {
            XCTFail("No content view")
            return
        }
        let recorder = MouseRecordingView(frame: NSRect(x: 20, y: 20, width: 100, height: 100))
        contentView.addSubview(recorder)
        defer { recorder.removeFromSuperview() }

        fixture.mouse.doubleClick(at: recorder.convert(NSPoint(x: 10, y: 10), to: nil))
        XCTAssertEqual(recorder.records.map(\.clickCount), [1, 1, 2, 2])
    }
}

/// Test hosts run with AppKit's automatic window animations turned off, by the launch argument
/// `-NSAutomaticWindowAnimationsEnabled NO` in ModernTests.xctestplan. With them on, ordering a
/// window in or out starts a zoom animation (an NSAnimation subclass) that occupies a
/// user-interactive dispatch thread in -[NSAnimation _runBlocking] until it has received enough
/// display frames to finish. Long runs piled up 80 such threads, the dispatch pool's limit, always
/// with the screen locked (that a locked screen stops the frames is inferred); after that, work
/// sent to global queues and XPC replies stopped being delivered, so tests with unbounded waits
/// hung. Not gated on ITERM2_ONSCREEN_TESTS: it must run in every suite run.
final class TestHostWindowAnimationTests: XCTestCase {
    private static let defaultsKey = "NSAutomaticWindowAnimationsEnabled"

    func testAutomaticWindowAnimationsAreOffInTheTestHost() {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        XCTAssertNotNil(arguments[Self.defaultsKey],
                        "the test host must be launched with -\(Self.defaultsKey) NO (see ModernTests.xctestplan)")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: Self.defaultsKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.defaultsKey))
    }

    /// Opens and closes a terminal window and, after each, runs the main run loop briefly while
    /// looking at every thread's stack. AppKit starts a window's order-in or order-out animation
    /// when the run loop next runs, and by day the animation then occupies a dispatch thread in
    /// -[NSAnimation _runBlocking] for a few tenths of a second, so with animations on this sees
    /// it. With them off no thread ever enters that method, so the test passes however slow the
    /// machine is. A very slow machine could miss an animation that is on (a false pass), never
    /// report one that is off. The short real-time window is a declared exception to the rule
    /// against timing in tests (test-speed.md section 4).
    func testOpeningAndClosingWindowsStartsNoBlockingAnimation() throws {
        // A macOS update that renames the method must not fail every gate; the defaults test
        // above still guards the launch argument.
        guard let range = Self.runBlockingAddressRange() else {
            throw XCTSkip("-[NSAnimation _runBlocking] was not found: AppKit changed and this test needs updating")
        }
        let fixture = TerminalWindowTestFixture(engageLayoutEngine: false)
        var parked = Self.mostThreadsInRangeWhileRunningTheRunLoop(range)
        fixture.close()
        parked = max(parked, Self.mostThreadsInRangeWhileRunningTheRunLoop(range))
        XCTAssertEqual(parked, 0,
                       "\(parked) thread(s) were inside -[NSAnimation _runBlocking] after a window was ordered in or out: " +
                       "AppKit window animations are on in the test host")
    }

    /// Runs the main run loop for up to 0.15 seconds, checking after each pass, and returns how
    /// many threads had a frame in `range` the first time any did, or 0 if none ever did.
    private static func mostThreadsInRangeWhileRunningTheRunLoop(_ range: Range<UInt>) -> Int {
        let deadline = Date(timeIntervalSinceNow: 0.15)
        repeat {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            let count = threadsWithAReturnAddress(in: range)
            if count > 0 {
                return count
            }
        } while Date() < deadline
        return 0
    }

    // MARK: - Helpers

    /// The addresses of -[NSAnimation _runBlocking]'s code: from its implementation up to the next
    /// method of NSAnimation in memory (or 4 KB if it is the last). The selector is looked up,
    /// never called.
    private static func runBlockingAddressRange() -> Range<UInt>? {
        let selector = NSSelectorFromString("_runBlocking")
        guard let method = class_getInstanceMethod(NSAnimation.self, selector) else {
            return nil
        }
        let start = stripped(UInt(bitPattern: unsafeBitCast(method_getImplementation(method), to: Int.self)))
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(NSAnimation.self, &count) else {
            return nil
        }
        defer { free(methods) }
        var end = start + 4096
        for i in 0..<Int(count) {
            let address = stripped(UInt(bitPattern: unsafeBitCast(method_getImplementation(methods[i]), to: Int.self)))
            if address > start && address < end {
                end = address
            }
        }
        return start..<end
    }

    /// Removes pointer authentication bits from a code address. Assumes user-space addresses fit
    /// in 47 bits, as they do on macOS for arm64 and x86_64 (MACH_VM_MAX_ADDRESS is below 2^47),
    /// so every bit above them is a signature bit or zero.
    private static func stripped(_ address: UInt) -> UInt {
        return address & 0x0000_7FFF_FFFF_FFFF
    }

    /// How many threads of this process, other than the calling one, have a frame whose return
    /// address (or program counter) is in `range`. Stacks are walked by frame pointer and read
    /// with mach_vm_read_overwrite, so a stack that changes during the walk cannot fault.
    private static func threadsWithAReturnAddress(in range: Range<UInt>) -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else {
            XCTFail("task_threads failed")
            return 0
        }
        let me = mach_thread_self()
        defer {
            mach_port_deallocate(mach_task_self_, me)
            for i in 0..<Int(threadCount) {
                mach_port_deallocate(mach_task_self_, threads[i])
            }
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }
        var result = 0
        for i in 0..<Int(threadCount) where threads[i] != me {
            if codeAddresses(of: threads[i]).contains(where: { range.contains(stripped($0)) }) {
                result += 1
            }
        }
        return result
    }

    private static func codeAddresses(of thread: thread_act_t) -> [UInt] {
        var addresses = [UInt]()
        var framePointer: UInt
#if arch(arm64)
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &state) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &stateCount)
            }
        }
        guard status == KERN_SUCCESS else {
            return []
        }
        addresses.append(UInt(state.__pc))
        addresses.append(UInt(state.__lr))
        framePointer = UInt(state.__fp)
#elseif arch(x86_64)
        var state = x86_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &state) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(thread, thread_state_flavor_t(x86_THREAD_STATE64), $0, &stateCount)
            }
        }
        guard status == KERN_SUCCESS else {
            return []
        }
        addresses.append(UInt(state.__rip))
        framePointer = UInt(state.__rbp)
#endif
        // A frame record is the caller's frame pointer followed by the return address.
        var record: (UInt, UInt) = (0, 0)
        for _ in 0..<512 {
            guard framePointer != 0, framePointer % UInt(MemoryLayout<UInt>.alignment) == 0 else {
                break
            }
            var size: mach_vm_size_t = 0
            let read = withUnsafeMutablePointer(to: &record) { pointer in
                mach_vm_read_overwrite(mach_task_self_,
                                       mach_vm_address_t(framePointer),
                                       mach_vm_size_t(MemoryLayout<(UInt, UInt)>.size),
                                       mach_vm_address_t(UInt(bitPattern: pointer)),
                                       &size)
            }
            guard read == KERN_SUCCESS, record.1 != 0 else {
                break
            }
            addresses.append(record.1)
            // Stacks grow down, so each caller's frame is above its callee's.
            guard record.0 > framePointer else {
                break
            }
            framePointer = record.0
        }
        return addresses
    }
}
