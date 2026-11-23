//
//  LifetimeWitnessTests.swift
//  ModernTests
//
//  Lifetime witness tests for sessions, tabs and windows
//  (docs/swift-migration/lifetimes.md, phase0.md section 8). Each test builds a
//  real terminal window with TerminalWindowTestFixture, closes something
//  through the same path the app uses, and checks that the objects that should
//  die do: weak references to them become nil, and the instance census
//  (InstanceCensus.swift) finds nothing of the tracked classes left over from
//  the scenario. A port that adds a retain cycle, or a longer-lived capture,
//  makes one of these fail.
//
//  Designed lifetimes. A closed session is not freed at once: -[PTYSession
//  terminate] makes the termination undoable (unless the session is a tmux
//  client, synthetic, restarting or the app is quitting), and
//  -makeTerminationUndoable keeps it for the profile's "Session Close Undo
//  Timeout" (KEY_UNDO_TIMEOUT, 5 seconds by default) in two places: a delayed
//  -hardStop, and the restorable session that iTermController keeps for Undo
//  Close. -hardStop removes it from both. Most tests here set the timeout to 0
//  so -hardStop runs on the next pass of the run loop; the "KeptForUndo" tests
//  use a timeout that never runs out during the test, check that the session
//  is alive by design, and then call -hardStop, which is what the delayed
//  perform calls when the timeout runs out.
//
//  Deferred work. Closing schedules work with dispatch_async and
//  -performSelector:afterDelay:, and the token executor runs on the mutation
//  queue. The tests run the main run loop until the objects are gone. The
//  bound on that only limits how long a failing test takes; nothing waits for
//  time to pass.
//
//  Autorelease pools. The scenario runs in an explicit pool, so an object
//  that the code under test returned autoreleased cannot outlive it in the
//  test method's own pool, which drains only after the test.
//
//  Thread of deallocation. concurrency.md section 6 asks that objects that
//  must be torn down on the main thread (views, window controllers, anything
//  touching AppKit) have it asserted. PTYSession, PTYTextView, PTYTab,
//  PseudoTerminal and the window are deallocated on the main thread in every
//  scenario here, and assertDeallocatedOnMainThread asserts it. VT100Screen,
//  VT100Terminal and the token executor are also deallocated on the main
//  thread today in every scenario here (observed with the census on
//  2026-11-20, including the scenario with output pending), but they do not
//  touch AppKit, so that is recorded here as a fact and not asserted.
//
//  Side effects of dealloc (lifetimes.md, "deinit side effects"). -[PTYSession
//  dealloc] posts PTYSessionDidDealloc with the session's guid
//  asynchronously on the main queue, and -[PTYTab dealloc] posts
//  iTermTabClosing with the tab synchronously on the main thread. The tests
//  assert each is posted once for the object that died.
//

import XCTest
@testable import iTerm2SharedARC

/// Weak references to named objects, to find out which are still alive.
final class LifetimeWitness {
    private final class Entry {
        let name: String
        weak var object: AnyObject?

        init(_ name: String, _ object: AnyObject) {
            self.name = name
            self.object = object
        }
    }

    private var entries = [Entry]()

    func watch(_ object: AnyObject?, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let object else {
            XCTFail("Nothing to watch for \(name)", file: file, line: line)
            return
        }
        entries.append(Entry(name, object))
    }

    /// Watches a session and the objects it owns whose lifetime a port of any
    /// of them could change: its screen, text view, terminal and token
    /// executor.
    func watch(session: PTYSession, _ name: String) {
        watch(session, name)
        watch(session.screen, "\(name).screen")
        watch(session.textview, "\(name).textview")
        session.screen.performBlock(joinedThreads: { terminal, mutableState, _ in
            watch(terminal, "\(name).terminal")
            watch(mutableState.tokenExecutor, "\(name).tokenExecutor")
        })
    }

    /// The names of the watched objects that are still alive.
    var survivors: [String] {
        return autoreleasepool {
            entries.filter { $0.object != nil }.map(\.name)
        }
    }

    func isAlive(_ name: String) -> Bool {
        return autoreleasepool {
            entries.contains { $0.name == name && $0.object != nil }
        }
    }
}

enum LifetimeWitnessSupport {
    static var windowClasses: [AnyClass] {
        return ["iTermWindow", "iTermCompactWindow", "iTermPanel", "iTermCompactPanel"].compactMap {
            NSClassFromString($0)
        }
    }

    /// The classes whose instances the census counts in these tests.
    static var sessionClasses: [AnyClass] {
        return [PTYSession.self, VT100Screen.self, PTYTextView.self, VT100Terminal.self, TokenExecutor.self]
    }

    static var allClasses: [AnyClass] {
        return sessionClasses + [PTYTab.self, PseudoTerminal.self] + windowClasses
    }

    /// Classes that touch AppKit and so must be deallocated on the main thread.
    static var mainThreadClasses: [AnyClass] {
        return [PTYSession.self, PTYTextView.self, PTYTab.self, PseudoTerminal.self] + windowClasses
    }

    /// The default profile with the given undo timeout, and with archiving
    /// off so that -hardStop writes nothing to disk.
    static func profile(undoTimeout: Int) -> [AnyHashable: Any] {
        guard var profile = ProfileModel.sharedInstance().defaultBookmark() else {
            it_fatalError("No default profile")
        }
        profile[KEY_UNDO_TIMEOUT] = undoTimeout
        profile[KEY_ARCHIVE] = false
        return profile
    }

    /// An undo timeout that does not run out while a test runs.
    static let longUndoTimeout = 3600

    private static var warmedUp = false

    /// Opens a window, closes a split pane and then the window, and waits
    /// for them to be freed, once per test process. Called from each witness
    /// class's class setUp, which XCTest does not count in any test's time.
    ///
    /// Why. The first time a test process does this, the closed session
    /// stays alive for one to two seconds on an idle machine while the main
    /// run loop keeps turning (measured on 2026-11-20: about 350 passes of
    /// the run loop, none longer than 0.3 seconds). Later times take a
    /// fraction of a second. The likely holder, found by reading and timing
    /// experiments and not proven by a retain trace (see the open question
    /// in docs/swift-migration/lifetimes.md): the completion block that
    /// -[PTYSession renderMetalFramesAndShowMetalView:] passes to
    /// -[iTermMetalDriver drawAsynchronouslyInView:completion:] reads
    /// _useMetal and _exited, so it retains the session, and the driver keeps
    /// it in a dispatch_group_notify until the frame completes; the first
    /// Metal frame in a process is slow. With GPU rendering turned off
    /// (kPreferenceKeyUseMetal) the first close freed the session in 0.016
    /// seconds, and with it on in 1.4 seconds. Under the load of a parallel
    /// suite run the first test took 13 seconds, over the 10 second ceiling
    /// of test-speed.md, so the one-time cost is paid here instead. No
    /// assertion is made here; the tests check the same lifetimes.
    static func warmUpOnce() {
        if warmedUp {
            return
        }
        warmedUp = true
        let witness = LifetimeWitness()
        var fixture: TerminalWindowTestFixture? = autoreleasepool {
            let fixture = TerminalWindowTestFixture(profile: profile(undoTimeout: 0))
            witness.watch(fixture.terminal, "terminal")
            if let first = fixture.terminal.currentSession() {
                let second = fixture.split(first, vertically: true)
                witness.watch(second, "session")
                fixture.terminal.close(second)
            }
            return fixture
        }
        // Outside the pool, which would otherwise keep the session alive.
        spin(until: { !witness.isAlive("session") })
        autoreleasepool {
            fixture?.close()
            fixture = nil
        }
        spin(until: { witness.survivors.isEmpty })
    }

    /// Closes a test's window if it is still open and stops each of its
    /// sessions at once with -hardStop, so that no delayed -hardStop (up to
    /// longUndoTimeout away) or restorable session for Undo Close outlives
    /// the test. -hardStop is safe here because the close terminated each
    /// session (undoably, since the fixture's sessions are neither synthetic
    /// nor tmux clients) just now and the run loop has not turned since, so the
    /// delayed -hardStop has not run; calling it a second time would
    /// over-release the session's view.
    static func closeAndStop(_ fixture: TerminalWindowTestFixture?) {
        autoreleasepool {
            guard let fixture, fixture.window.isVisible else {
                return
            }
            let sessions = (fixture.terminal.allSessions() ?? []).map { WeakSessionBox($0) }
            fixture.close()
            for box in sessions {
                box.session?.hardStop()
            }
        }
    }

    /// The same for a window whose fixture the test no longer holds.
    static func closeAndStop(_ terminal: PseudoTerminal?) {
        autoreleasepool {
            guard let terminal, let window = terminal.window, window.isVisible else {
                return
            }
            let sessions = (terminal.allSessions() ?? []).map { WeakSessionBox($0) }
            window.close()
            AutoresizingFloorAuditor.violationHandler = nil
            for box in sessions {
                box.session?.hardStop()
            }
        }
    }

    /// Runs the main run loop until `condition` holds. The deadline only
    /// stops a failing test from running on; nothing waits for time to pass.
    /// It is generous because the first session closed in a test process
    /// can stay alive for seconds waiting for its first Metal frames (see
    /// warmUpOnce), which took 11 seconds once under the thread sanitizer on
    /// a loaded machine.
    @discardableResult
    static func spin(until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 30)
        while !autoreleasepool(invoking: condition) {
            if Date() >= deadline {
                return false
            }
            autoreleasepool {
                _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }
        return true
    }

    /// Runs what is already queued on the main queue and the main run loop,
    /// then what that queued, twice over.
    static func drainMainQueue() {
        for _ in 0..<2 {
            var dispatched = false
            var performed = false
            DispatchQueue.main.async {
                dispatched = true
            }
            RunLoop.main.perform {
                performed = true
            }
            XCTAssertTrue(spin(until: { dispatched && performed }), "The main queue did not drain")
        }
    }

    /// Waits for every watched object to die and fails naming any that do
    /// not. Returns whether all died, so that a failing test can skip its
    /// remaining waits instead of running each to its deadline.
    @discardableResult
    static func assertAllFreed(_ witness: LifetimeWitness,
                               _ message: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) -> Bool {
        spin(until: { witness.survivors.isEmpty })
        let survivors = witness.survivors
        XCTAssertEqual(survivors, [], message, file: file, line: line)
        return survivors.isEmpty
    }

    /// Fails if any instance of a tracked class allocated since `mark` is still alive.
    static func assertCensusClean(since mark: InstanceCensus.Mark,
                                  classes: [AnyClass] = allClasses,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        let census = InstanceCensus.shared
        spin(until: { census.survivors(of: classes, since: mark).isEmpty })
        XCTAssertEqual(census.survivors(of: classes, since: mark), [:],
                       "Instances made during the scenario are still alive", file: file, line: line)
    }

    /// Asserts that every instance of an AppKit-touching class made since
    /// `mark` that has been deallocated was deallocated on the main thread.
    static func assertDeallocatedOnMainThread(since mark: InstanceCensus.Mark,
                                              file: StaticString = #filePath,
                                              line: UInt = #line) {
        for cls in mainThreadClasses {
            let threads = InstanceCensus.shared.deallocThreads(of: cls, since: mark)
            XCTAssertEqual(threads.other, 0, "\(cls) was deallocated off the main thread: \(threads)",
                           file: file, line: line)
        }
        // Every scenario frees at least one session, so the check above is not vacuous.
        XCTAssertGreaterThan(InstanceCensus.shared.deallocThreads(of: PTYSession.self, since: mark).main, 0,
                             "No session was seen to be deallocated", file: file, line: line)
    }

    /// Feeds output to a session the way the TaskNotifier thread does, from a
    /// queue other than main, and returns once it is queued for the token
    /// executor, which runs it on the mutation queue.
    static func queueOutput(_ session: PTYSession, bytes: Int) {
        let line = Array("The quick brown fox jumps over the lazy dog 0123456789\r\n".utf8)
        var data = [UInt8]()
        while data.count < bytes {
            data.append(contentsOf: line)
        }
        let reader = DispatchQueue(label: "LifetimeWitnessTests.reader")
        reader.sync {
            data.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { pointer in
                    session.threadedReadTask(pointer, length: Int32(buffer.count))
                }
            }
        }
    }

    /// Records the guids that PTYSessionDidDealloc, which -[PTYSession
    /// dealloc] posts asynchronously on the main queue, reports.
    final class DeallocNotificationRecorder {
        private(set) var guids = [String]()
        private var token: NSObjectProtocol?

        init() {
            token = NotificationCenter.default.addObserver(forName: NSNotification.Name(PTYSessionDidDealloc),
                                                           object: nil,
                                                           queue: nil) { [weak self] notification in
                if let guid = notification.object as? String {
                    self?.guids.append(guid)
                }
            }
        }

        deinit {
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}

// MARK: - Sessions

final class SessionLifetimeWitnessTests: XCTestCase {
    private typealias Support = LifetimeWitnessSupport

    override class func setUp() {
        super.setUp()
        LifetimeWitnessSupport.warmUpOnce()
    }
    private var fixture: TerminalWindowTestFixture?

    override func setUp() {
        super.setUp()
        InstanceCensus.shared.track(Support.allClasses)
    }

    private let kept = KeptSessions()

    override func tearDown() {
        kept.expire()
        Support.closeAndStop(fixture)
        fixture = nil
        super.tearDown()
    }

    private func makeFixture(undoTimeout: Int) -> TerminalWindowTestFixture {
        return autoreleasepool {
            let fixture = TerminalWindowTestFixture(profile: Support.profile(undoTimeout: undoTimeout))
            self.fixture = fixture
            return fixture
        }
    }

    // Closing one pane of a split goes through -[PseudoTerminal closeSession:],
    // which terminates the session because its tab has another.
    func testClosedSessionInSplitIsFreed() throws {
        let fixture = makeFixture(undoTimeout: 0)
        let witness = LifetimeWitness()
        let recorder = Support.DeallocNotificationRecorder()
        let mark = InstanceCensus.shared.mark()
        var guid = ""
        autoreleasepool {
            guard let first = fixture.terminal.currentSession() else {
                XCTFail("No session")
                return
            }
            let second = fixture.split(first, vertically: true)
            witness.watch(session: second, "session")
            guid = second.guid
            fixture.terminal.close(second)
        }
        guard Support.assertAllFreed(witness, "A closed session and what it owns must be freed") else {
            return
        }
        Support.assertCensusClean(since: mark, classes: Support.sessionClasses)
        Support.assertDeallocatedOnMainThread(since: mark)
        // -[PTYSession dealloc] posts PTYSessionDidDealloc on the next pass of the main queue.
        Support.spin(until: { recorder.guids.contains(guid) })
        XCTAssertEqual(recorder.guids.filter { $0 == guid }.count, 1)
    }

    // Output read from the job is still queued on the token executor when
    // the session closes: the executor is paused (-[iTermTokenExecutor
    // pause], as a paused side effect does) before the output is queued, the
    // test checks that tokens are pending, closes the session, and only then
    // unpauses. The Unpauser holds the executor weakly, so it keeps nothing
    // alive.
    func testSessionClosedWithPendingOutputIsFreed() throws {
        let fixture = makeFixture(undoTimeout: 0)
        let witness = LifetimeWitness()
        let mark = InstanceCensus.shared.mark()
        var unpauser: Unpauser?
        defer {
            unpauser?.unpause()
        }
        autoreleasepool {
            guard let first = fixture.terminal.currentSession() else {
                XCTFail("No session")
                return
            }
            let second = fixture.split(first, vertically: true)
            witness.watch(session: second, "session")
            // pause() must be called on the mutation queue, or on main in a joined block.
            second.screen.performBlock(joinedThreads: { _, mutableState, _ in
                unpauser = mutableState.tokenExecutor.pause()
            })
            Support.queueOutput(second, bytes: 256 * 1024)
            var pending = false
            var description = ""
            second.screen.performBlock(joinedThreads: { _, mutableState, _ in
                pending = mutableState.tokenExecutor.hasPendingWork
                description = mutableState.tokenExecutor.pendingWorkDescriptionForTesting
            })
            XCTAssertTrue(pending, "Output must be pending when the session closes: \(description)")
            fixture.terminal.close(second)
        }
        Support.drainMainQueue()
        unpauser?.unpause()
        unpauser = nil
        guard Support.assertAllFreed(witness, "A session closed with output pending must be freed") else {
            return
        }
        Support.assertCensusClean(since: mark, classes: Support.sessionClasses)
        Support.assertDeallocatedOnMainThread(since: mark)
    }

    // A closed session is kept for Undo Close until its undo timeout runs out,
    // by design (-makeTerminationUndoable), and is freed by -hardStop, which
    // the delayed perform calls when it does.
    func testSessionKeptForUndoIsFreedWhenUndoExpires() throws {
        let fixture = makeFixture(undoTimeout: Support.longUndoTimeout)
        let witness = LifetimeWitness()
        let mark = InstanceCensus.shared.mark()
        autoreleasepool {
            guard let first = fixture.terminal.currentSession() else {
                XCTFail("No session")
                return
            }
            let second = fixture.split(first, vertically: true)
            witness.watch(session: second, "session")
            fixture.terminal.close(second)
            kept.keep([WeakSessionBox(second)])
        }
        Support.drainMainQueue()
        XCTAssertTrue(witness.isAlive("session"), "A closed session must be kept while it can be undone")
        XCTAssertTrue(witness.isAlive("session.screen"))

        kept.expire()
        guard Support.assertAllFreed(witness, "A session whose undo timeout ran out must be freed") else {
            return
        }
        Support.assertCensusClean(since: mark, classes: Support.sessionClasses)
        Support.assertDeallocatedOnMainThread(since: mark)
    }
}

// MARK: - Tabs

final class TabLifetimeWitnessTests: XCTestCase {
    private typealias Support = LifetimeWitnessSupport

    override class func setUp() {
        super.setUp()
        LifetimeWitnessSupport.warmUpOnce()
    }
    private var fixture: TerminalWindowTestFixture?
    private var tabClosingToken: NSObjectProtocol?
    private let kept = KeptSessions()

    override func setUp() {
        super.setUp()
        InstanceCensus.shared.track(Support.allClasses)
    }

    override func tearDown() {
        if let tabClosingToken {
            NotificationCenter.default.removeObserver(tabClosingToken)
        }
        kept.expire()
        Support.closeAndStop(fixture)
        fixture = nil
        super.tearDown()
    }

    private func makeFixture(undoTimeout: Int) -> TerminalWindowTestFixture {
        return autoreleasepool {
            let fixture = TerminalWindowTestFixture(profile: Support.profile(undoTimeout: undoTimeout))
            self.fixture = fixture
            return fixture
        }
    }

    // -[PTYTab dealloc] posts iTermTabClosing with the dying tab as its
    // object. Records the addresses of the tabs it reports.
    private var closingTabs = [ObjectIdentifier]()

    private func recordTabClosing() {
        tabClosingToken = NotificationCenter.default.addObserver(forName: NSNotification.Name("iTermTabClosing"),
                                                                 object: nil,
                                                                 queue: nil) { [weak self] notification in
            XCTAssertTrue(Thread.isMainThread)
            if let object = notification.object as AnyObject? {
                self?.closingTabs.append(ObjectIdentifier(object))
            }
        }
    }

    private struct ClosedTab {
        var witness: LifetimeWitness
        var tabID: ObjectIdentifier
        var sessions: [WeakSessionBox]
        var mark: InstanceCensus.Mark
    }

    // Opens a window, adds a second tab (split if `splitIt`), and closes that
    // tab. The census mark is taken after the window's first tab exists,
    // since that one stays open.
    private func closeSecondTab(splitIt: Bool, undoTimeout: Int) -> ClosedTab {
        let fixture = makeFixture(undoTimeout: undoTimeout)
        let mark = InstanceCensus.shared.mark()
        let witness = LifetimeWitness()
        var tabID: ObjectIdentifier?
        var sessions = [WeakSessionBox]()
        autoreleasepool {
            let session = fixture.addTab()
            guard let tab = fixture.terminal.tabs().first(where: { $0.sessions().contains(session) }) else {
                XCTFail("No tab")
                return
            }
            witness.watch(tab, "tab")
            witness.watch(session: session, "session")
            if splitIt {
                witness.watch(session: fixture.split(session, vertically: false), "split")
            }
            tabID = ObjectIdentifier(tab)
            sessions = tab.sessions().map { WeakSessionBox($0) }
            fixture.terminal.close(tab)
        }
        return ClosedTab(witness: witness, tabID: tabID!, sessions: sessions, mark: mark)
    }

    private var tabClasses: [AnyClass] {
        return Support.sessionClasses + [PTYTab.self]
    }

    // Closing a tab goes through -[PseudoTerminal closeTab:] and -removeTab:,
    // which terminates its sessions and removes its tab view item.
    func testClosedTabIsFreedWithItsSession() throws {
        recordTabClosing()
        let closed = closeSecondTab(splitIt: false, undoTimeout: 0)
        guard Support.assertAllFreed(closed.witness, "A closed tab and its session must be freed") else {
            return
        }
        XCTAssertEqual(closingTabs.filter { $0 == closed.tabID }.count, 1,
                       "-[PTYTab dealloc] posts iTermTabClosing once")
        Support.assertCensusClean(since: closed.mark, classes: tabClasses)
        Support.assertDeallocatedOnMainThread(since: closed.mark)
        XCTAssertEqual(fixture?.terminal.numberOfTabs(), 1)
    }

    func testClosedTabWithSplitPanesIsFreedWithBothSessions() throws {
        recordTabClosing()
        let closed = closeSecondTab(splitIt: true, undoTimeout: 0)
        XCTAssertEqual(closed.sessions.count, 2)
        guard Support.assertAllFreed(closed.witness, "A closed tab and both of its sessions must be freed") else {
            return
        }
        XCTAssertEqual(closingTabs.filter { $0 == closed.tabID }.count, 1)
        Support.assertCensusClean(since: closed.mark, classes: tabClasses)
        Support.assertDeallocatedOnMainThread(since: closed.mark)
    }

    // The sessions of a closed tab are kept for Undo Close until their undo
    // timeout runs out, by design, and -hardStop frees them.
    func testClosedTabKeptForUndoIsFreedWhenUndoExpires() throws {
        recordTabClosing()
        let closed = closeSecondTab(splitIt: true, undoTimeout: Support.longUndoTimeout)
        kept.keep(closed.sessions)
        XCTAssertEqual(closed.sessions.count, 2)
        // The tab is not part of what Undo Close keeps: undoing makes a new
        // tab from the arrangement in the restorable session
        // (-[PseudoTerminal addTabWithArrangement:uniqueId:sessions:archives:predecessors:]).
        Support.spin(until: { !closed.witness.isAlive("tab") })
        XCTAssertFalse(closed.witness.isAlive("tab"), "A closed tab is freed while its sessions are kept for undo")
        XCTAssertTrue(closed.witness.isAlive("session"), "A closed tab's sessions must be kept while it can be undone")
        XCTAssertTrue(closed.witness.isAlive("split"))

        kept.expire()
        guard Support.assertAllFreed(closed.witness, "A closed tab whose undo timeout ran out must be freed with its sessions") else {
            return
        }
        XCTAssertEqual(closingTabs.filter { $0 == closed.tabID }.count, 1)
        Support.assertCensusClean(since: closed.mark, classes: tabClasses)
        Support.assertDeallocatedOnMainThread(since: closed.mark)
    }
}

private final class WeakSessionBox {
    weak var session: PTYSession?

    init(_ session: PTYSession) {
        self.session = session
    }
}

/// Closed sessions that a "KeptForUndo" test keeps for Undo Close. expire()
/// calls -hardStop on each, as the delayed perform would when the undo
/// timeout runs out, exactly once: the test calls it, and tearDown calls it
/// again in case a failed assertion ended the test first.
private final class KeptSessions {
    private var boxes = [WeakSessionBox]()

    func keep(_ boxes: [WeakSessionBox]) {
        self.boxes += boxes
    }

    func expire() {
        let toStop = boxes
        boxes = []
        autoreleasepool {
            for box in toStop {
                box.session?.hardStop()
            }
        }
    }
}

// MARK: - Windows

final class WindowLifetimeWitnessTests: XCTestCase {
    private typealias Support = LifetimeWitnessSupport
    private let kept = KeptSessions()
    // Weak, so that it cannot keep the window alive. Set when a test opens a
    // window, for tearDown to close it if a failure left it open.
    private weak var openedTerminal: PseudoTerminal?

    override func tearDown() {
        kept.expire()
        Support.closeAndStop(openedTerminal)
        super.tearDown()
    }

    override class func setUp() {
        super.setUp()
        LifetimeWitnessSupport.warmUpOnce()
    }

    override func setUp() {
        super.setUp()
        InstanceCensus.shared.track(Support.allClasses)
    }

    /// Opens a window with two tabs, the second split, watches all of it, and
    /// returns the fixture's sessions weakly.
    private func openWindow(undoTimeout: Int,
                            witness: LifetimeWitness,
                            close: (TerminalWindowTestFixture) -> Void) -> [WeakSessionBox] {
        return autoreleasepool {
            let fixture = TerminalWindowTestFixture(profile: Support.profile(undoTimeout: undoTimeout))
            openedTerminal = fixture.terminal
            witness.watch(fixture.terminal, "terminal")
            witness.watch(fixture.window, "window")
            guard let firstTab = fixture.terminal.currentTab(), let first = firstTab.activeSession else {
                XCTFail("No tab")
                return []
            }
            witness.watch(firstTab, "tab1")
            witness.watch(session: first, "tab1.session")
            let second = fixture.addTab()
            witness.watch(fixture.terminal.tabs().first(where: { $0.sessions().contains(second) }), "tab2")
            witness.watch(session: second, "tab2.session")
            witness.watch(session: fixture.split(second, vertically: true), "tab2.split")
            let sessions = (fixture.terminal.allSessions() ?? []).map { WeakSessionBox($0) }
            close(fixture)
            return sessions
        }
    }

    // Closing the window goes through -[NSWindow close] and -[PseudoTerminal
    // windowWillClose:], which terminates every session and removes the
    // window controller from iTermController.
    func testClosedWindowIsFreedWithItsTabsAndSessions() throws {
        let witness = LifetimeWitness()
        let mark = InstanceCensus.shared.mark()
        _ = openWindow(undoTimeout: 0, witness: witness) { $0.close() }
        guard Support.assertAllFreed(witness, "A closed window must be freed with its tabs and sessions") else {
            return
        }
        Support.assertCensusClean(since: mark)
        Support.assertDeallocatedOnMainThread(since: mark)
    }

    // Closing the only session of the only tab closes the tab, and closing the
    // last tab closes the window (-[PseudoTerminal removeTab:]).
    func testClosingTheLastSessionFreesTheWindow() throws {
        let witness = LifetimeWitness()
        let mark = InstanceCensus.shared.mark()
        autoreleasepool {
            let fixture = TerminalWindowTestFixture(profile: Support.profile(undoTimeout: 0))
            openedTerminal = fixture.terminal
            witness.watch(fixture.terminal, "terminal")
            witness.watch(fixture.window, "window")
            witness.watch(fixture.terminal.currentTab(), "tab")
            guard let session = fixture.terminal.currentSession() else {
                XCTFail("No session")
                return
            }
            witness.watch(session: session, "session")
            fixture.terminal.close(session)
        }
        guard Support.assertAllFreed(witness, "Closing the last session must free its window") else {
            return
        }
        Support.assertCensusClean(since: mark)
        Support.assertDeallocatedOnMainThread(since: mark)
    }

    // A closed window's sessions are kept for Undo Close until their undo
    // timeout runs out; Undo Close restores the window from its arrangement,
    // so the window, its controller and its tabs need not be kept.
    func testClosedWindowKeptForUndoIsFreedWhenUndoExpires() throws {
        let witness = LifetimeWitness()
        let mark = InstanceCensus.shared.mark()
        let sessions = openWindow(undoTimeout: Support.longUndoTimeout, witness: witness) { $0.close() }
        kept.keep(sessions)
        XCTAssertEqual(sessions.count, 3)
        // Undo Close of a window makes a new window from the arrangement in
        // the restorable session (-[iTermApplicationDelegate undoCloseSession:],
        // the kiTermRestorableSessionGroupWindow case), so
        // the closed window, its controller and its tabs are freed while the
        // sessions are kept. They do not all die in the same pass of the run
        // loop as the close.
        let windowObjects = ["terminal", "window", "tab1", "tab2"]
        Support.spin(until: { !windowObjects.contains(where: witness.isAlive) })
        XCTAssertEqual(windowObjects.filter(witness.isAlive), [],
                       "A closed window is freed while its sessions are kept for undo")
        for name in ["tab1.session", "tab2.session", "tab2.split"] {
            XCTAssertTrue(witness.isAlive(name), "\(name) must be kept while the close can be undone")
        }

        kept.expire()
        guard Support.assertAllFreed(witness, "A closed window whose undo timeout ran out must be freed") else {
            return
        }
        Support.assertCensusClean(since: mark)
        Support.assertDeallocatedOnMainThread(since: mark)
    }
}


// The shell integration installer a text view shows. PTYTextView keeps it in an ivar that the ARC
// category file (-installShellIntegration:) stores with strong semantics and the manual
// retain/release file (PTYTextView.m) must release. When the view leaves its window (as on a tab
// switch) the installer's panel is closed and the ivar cleared, but the installer is kept, so
// what it is still doing in the session goes on; it is released when the text view is. These
// check both halves. An extra release would message a zombie (the test plan sets NSZombieEnabled
// and the address sanitizer).
enum ShellIntegrationInstallerLifetimeSupport {
    static let nibName = "iTermShellIntegrationWindowController"
    static let ivarKey = "shellIntegrationInstallerWindow"

    static func makeTextView() -> PTYTextView {
        return PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }

    // A window that is never ordered onto the screen.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    // The text view's _shellIntegrationInstallerWindow ivar, read without changing it.
    static func installer(of textView: PTYTextView) -> iTermShellIntegrationWindowController? {
        return autoreleasepool {
            textView.value(forKey: ivarKey) as? iTermShellIntegrationWindowController
        }
    }

    static func moveOut(_ textView: PTYTextView) {
        autoreleasepool {
            textView.removeFromSuperview()
        }
    }

    static func move(_ textView: PTYTextView, to window: NSWindow) {
        autoreleasepool {
            textView.removeFromSuperview()
            window.contentView?.addSubview(textView)
        }
    }
}

// Through the real ARC store, -installShellIntegration:, which orders the panel front, so these
// are gated.
final class ShellIntegrationInstallerLifetimeWitnessTests: XCTestCase {
    private typealias Support = LifetimeWitnessSupport
    private typealias Installer = ShellIntegrationInstallerLifetimeSupport

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
    }

    // Runs the installer and watches it and its panel as "<name>" and "<name>.panel", holding
    // neither. The panel is read after -installShellIntegration: has loaded the nib.
    private func install(in textView: PTYTextView,
                         _ witness: LifetimeWitness,
                         _ name: String,
                         file: StaticString = #filePath,
                         line: UInt = #line) {
        autoreleasepool {
            textView.installShellIntegration(nil)
            let controller = Installer.installer(of: textView)
            witness.watch(controller, name, file: file, line: line)
            witness.watch(controller?.window, "\(name).panel", file: file, line: line)
        }
    }

    // Closes the installer's panel, as its Cancel button does, without touching the ivar.
    private func closeInstaller(of textView: PTYTextView) {
        autoreleasepool {
            Installer.installer(of: textView)?.close()
        }
    }

    func testLeavingTheWindowKeepsTheInstallerUntilDealloc() {
        let window = Installer.makeWindow()
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            window.contentView?.addSubview(textView)
            install(in: textView, witness, "installer")

            Installer.moveOut(textView)

            XCTAssertNil(Installer.installer(of: textView))
            XCTAssertTrue(witness.isAlive("installer"),
                          "The installer was freed when its view left the window")
        }

        Support.assertAllFreed(witness, "The installer outlived the text view")
    }

    func testDeallocFreesTheInstaller() {
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            install(in: textView, witness, "installer")
            closeInstaller(of: textView)
        }

        Support.assertAllFreed(witness, "The installer outlived the text view")
    }

    // The text view is deallocated while the installer's panel is still open. AppKit keeps a
    // window that is on screen alive, so the panel is freed only if -dealloc closes it.
    func testDeallocWithThePanelOpenFreesTheInstaller() {
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            install(in: textView, witness, "installer")
        }

        Support.assertAllFreed(witness, "The installer outlived the text view")
    }

    // Installing again replaces the installer (the ARC side releases the old one), and moving
    // between windows retires it each time. Every installer dies, and none is released twice.
    func testReinstallingAndMovingBetweenWindowsFreesEveryInstaller() {
        let firstWindow = Installer.makeWindow()
        let secondWindow = Installer.makeWindow()
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            firstWindow.contentView?.addSubview(textView)

            // Install, close the panel, and install again: the second replaces the first.
            install(in: textView, witness, "first")
            closeInstaller(of: textView)
            install(in: textView, witness, "second")
            XCTAssertTrue(Support.spin(until: { !witness.isAlive("first") }),
                          "The replaced installer outlived its replacement")

            // Move to another window, which closes and retires the installer, then install there.
            Installer.move(textView, to: secondWindow)
            XCTAssertNil(Installer.installer(of: textView))
            XCTAssertTrue(witness.isAlive("second"), "The installer was freed on leaving the window")
            install(in: textView, witness, "third")

            // Move back, which retires it too, and install once more.
            Installer.move(textView, to: firstWindow)
            XCTAssertNil(Installer.installer(of: textView))
            XCTAssertTrue(witness.isAlive("third"), "The installer was freed on moving back")
            install(in: textView, witness, "fourth")

            // Leave the window with the panel closed, then install outside any window and let
            // the view go with that installer still held.
            closeInstaller(of: textView)
            Installer.moveOut(textView)
            XCTAssertNil(Installer.installer(of: textView))
            install(in: textView, witness, "fifth")
            closeInstaller(of: textView)
        }

        Support.assertAllFreed(witness, "An installer outlived the text view")
    }
}

// The same releases without putting anything on screen: the installer is built from its nib
// (whose panel is not visible at launch) and stored in the ivar with key-value coding, which for
// this class retains the new value and releases the old one, as the ARC store does. These run in
// the regular suite.
final class ShellIntegrationInstallerOffscreenLifetimeWitnessTests: XCTestCase {
    private typealias Support = LifetimeWitnessSupport
    private typealias Installer = ShellIntegrationInstallerLifetimeSupport

    private var visibleWindowsAtStart = 0

    private static var visibleWindowCount: Int {
        return NSApp.windows.filter(\.isVisible).count
    }

    override func setUp() {
        super.setUp()
        visibleWindowsAtStart = Self.visibleWindowCount
    }

    override func tearDown() {
        XCTAssertEqual(Self.visibleWindowCount, visibleWindowsAtStart, "A window was put on screen")
        super.tearDown()
    }

    // Builds an installer off screen, stores it in the text view's ivar, and watches it and its
    // panel as "<name>" and "<name>.panel", holding neither.
    @discardableResult
    private func store(in textView: PTYTextView,
                       _ witness: LifetimeWitness,
                       _ name: String,
                       delegate: iTermShellIntegrationWindowControllerDelegate? = nil,
                       configure: (iTermShellIntegrationWindowController) -> Void = { _ in },
                       file: StaticString = #filePath,
                       line: UInt = #line) -> WeakInstaller {
        let weakInstaller = WeakInstaller()
        autoreleasepool {
            let controller = iTermShellIntegrationWindowController(windowNibName: Installer.nibName)
            controller.delegate = delegate
            let panel = controller.window
            XCTAssertEqual(panel?.isVisible, false, file: file, line: line)
            configure(controller)
            textView.setValue(controller, forKey: Installer.ivarKey)
            witness.watch(controller, name, file: file, line: line)
            witness.watch(panel, "\(name).panel", file: file, line: line)
            weakInstaller.value = controller
        }
        XCTAssertTrue(witness.isAlive(name), "The ivar did not keep the installer", file: file, line: line)
        return weakInstaller
    }

    func testLeavingTheWindowKeepsTheInstallerUntilDealloc() {
        let window = Installer.makeWindow()
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            window.contentView?.addSubview(textView)
            store(in: textView, witness, "installer")

            Installer.moveOut(textView)

            XCTAssertNil(Installer.installer(of: textView))
            XCTAssertTrue(witness.isAlive("installer"),
                          "The installer was freed when its view left the window")
        }

        Support.assertAllFreed(witness, "The installer outlived the text view")
    }

    func testDeallocFreesTheInstaller() {
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            store(in: textView, witness, "installer")
        }

        Support.assertAllFreed(witness, "The installer outlived the text view")
    }

    // Replacing the installer, retiring it on leaving a window more than once, and holding one at
    // dealloc: each is released exactly once.
    func testReplacingAndRetiringReleasesEachInstallerOnce() {
        let firstWindow = Installer.makeWindow()
        let secondWindow = Installer.makeWindow()
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            firstWindow.contentView?.addSubview(textView)

            store(in: textView, witness, "first")
            store(in: textView, witness, "second")
            XCTAssertTrue(Support.spin(until: { !witness.isAlive("first") }),
                          "The replaced installer outlived its replacement")

            Installer.move(textView, to: secondWindow)
            XCTAssertNil(Installer.installer(of: textView))
            store(in: textView, witness, "third")
            Installer.move(textView, to: firstWindow)
            XCTAssertNil(Installer.installer(of: textView))
            // Leaving with nothing held retires nothing.
            Installer.moveOut(textView)
            store(in: textView, witness, "fourth")
            XCTAssertTrue(witness.isAlive("second"), "A retired installer was freed early")
            XCTAssertTrue(witness.isAlive("third"), "A retired installer was freed early")
        }

        Support.assertAllFreed(witness, "An installer outlived the text view")
    }

    // An installer whose view left its window (as on a tab switch) finishes the step it was in:
    // the answer to a command it typed before still reaches it, through the session's expect.
    func testPendingWorkContinuesAfterLeavingTheWindow() {
        let window = Installer.makeWindow()
        let terminal = InstallerLifetimeFakeTerminal(testCase: self)
        let witness = LifetimeWitness()
        autoreleasepool {
            let textView = Installer.makeTextView()
            witness.watch(textView, "textView")
            window.contentView?.addSubview(textView)
            // The Internet-free install, then discovery, which asks for the shell and, for zsh,
            // where its dotfiles go.
            let installer = store(in: textView, witness, "installer", delegate: terminal) { controller in
                controller.shellIntegrationInstallerSendShellCommands(-1)
                controller.shellIntegrationInstallerSendShellCommands(0)
            }
            // Each step in a pool of its own, so nothing autoreleased keeps the installer alive.
            autoreleasepool {
                terminal.sync()
            }
            XCTAssertTrue(terminal.sentTexts.last?.contains("echo My shell is") ?? false, "\(terminal.sentTexts)")
            autoreleasepool {
                terminal.output("My shell is zsh -zsh or /bin/zsh, end")
                terminal.sync()
            }
            XCTAssertEqual(terminal.sentTexts.last, "echo My dotfiles go in ${ZDOTDIR:-$HOME}, end\n")

            Installer.moveOut(textView)
            autoreleasepool {
                terminal.output("My dotfiles go in /tmp/it2-dots, end")
                terminal.sync()
            }

            XCTAssertTrue(witness.isAlive("installer"),
                          "The installer was freed when its view left the window")
            XCTAssertEqual(installer.value?.dotdir, "/tmp/it2-dots",
                           "The installer did not finish discovery after its view left the window")
        }

        Support.assertAllFreed(witness, "The installer outlived the text view")
    }
}

private final class WeakInstaller {
    weak var value: iTermShellIntegrationWindowController?
}

// The session side of the installer, as far as discovery needs it: what the installer types, and
// the session's expect, copied from dry to wet as PTYSession does on a sync.
private final class InstallerLifetimeFakeTerminal: NSObject, iTermShellIntegrationWindowControllerDelegate {
    private let dryExpect = iTermExpect(dry: true)
    private var wetExpect: iTermExpect?
    private(set) var sentTexts = [String]()
    private let testCase: XCTestCase

    init(testCase: XCTestCase) {
        self.testCase = testCase
    }

    func shellIntegrationWindowControllerSendText(_ text: String) {
        sentTexts.append(text)
    }

    func shellIntegrationWindowControllerStopSendingText() {
    }

    func shellIntegrationExpect() -> iTermExpect {
        return dryExpect
    }

    // Adding an expectation to the wet copy dispatches its willExpect (which types the command)
    // to the main queue, so drain the main queue afterwards.
    func sync() {
        if dryExpect.dirty {
            dryExpect.resetDirty()
            wetExpect = (dryExpect.copy() as! iTermExpect)
        }
        let drained = XCTestExpectation(description: "Main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        testCase.wait(for: [drained], timeout: 10)
    }

    // The shell prints a line, checked against the current wet copy.
    func output(_ line: String) {
        guard let wetExpect else {
            return
        }
        for expectation in wetExpect.expectations {
            guard let regex = try? NSRegularExpression(pattern: expectation.regex),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }
            let captures = (0..<match.numberOfRanges).map { i -> String in
                guard let range = Range(match.range(at: i), in: line) else {
                    return ""
                }
                return String(line[range])
            }
            expectation.didMatch(withCaptureGroups: captures) { closure in
                closure()
            }
        }
    }
}
