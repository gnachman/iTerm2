//
//  TerminalWindowAutoLayoutFloorTests.swift
//  ModernTests
//
//  Once any constraint engages the layout engine in a terminal window, AppKit
//  translates every view's autoresizing mask into required constraints. On an
//  axis where a view's size is flexible, its fixed margins become a minimum
//  size for its superview. A hidden view with a stale frame then becomes a
//  window minimum the user cannot resize below. Issue 13118.
//
//  Each test runs a scenario twice, in a window without the engine and in one
//  where it is engaged from the start. Both windows then shrink to a small size
//  and grow back. The engaged window must reach the small size, enforce no
//  meaningful minimum, break no constraints, and end up laid out exactly like
//  the other one.
//

import WebKit
import XCTest
@testable import iTerm2SharedARC

final class TerminalWindowAutoLayoutFloorTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture!
    private var engineForced = false
    private var windowType = iTermWindowType.WINDOW_TYPE_NORMAL
    // Some window types keep their own size, such as a maximized window.
    private var expectsToReachSmallSize = true

    // With the engine engaged the window should shrink as freely as it does
    // without it. Only the title bar's height remains.
    private let maximumFloor = NSSize(width: 20, height: 40)
    private let largeSize = NSSize(width: 900, height: 650)
    private let smallSize = NSSize(width: 200, height: 150)
    private var recorder: LayoutEngineTestSupport.BrokenConstraintRecorder!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        recorder = LayoutEngineTestSupport.BrokenConstraintRecorder()
    }

    override func tearDown() {
        fixture?.close()
        fixture = nil
        recorder?.stop()
        recorder = nil
        super.tearDown()
    }

    private var window: NSWindow {
        return fixture.window
    }

    private func resize(to size: NSSize) {
        var frame = window.frame
        frame.size = size
        window.setFrame(frame, display: true)
    }

    // Runs the run loop until `condition` holds. The deadline only keeps a
    // broken test from hanging; nothing waits for time to pass.
    @discardableResult
    private func spin(until condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 15)
        while !condition() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return condition()
    }

    // Runs the work already queued on the main queue and run loop, then the
    // work that queued, so layout deferred with dispatch_async or
    // -performSelector:afterDelay:0 has happened.
    private func drainMainQueue() {
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

    // Lets deferred layout finish. SessionView resizes its Metal view only
    // after a resize settles, so also wait for those to catch up.
    private func settle() {
        drainMainQueue()
        window.layoutIfNeeded()
        func metalViewsCaughtUp() -> Bool {
            var result = true
            func visit(_ view: NSView) {
                if view is iTermMTKView, !view.isHiddenOrHasHiddenAncestor, let superview = view.superview,
                   !NSEqualRects(view.frame, superview.bounds) {
                    result = false
                }
                view.subviews.forEach(visit)
            }
            if let contentView = window.contentView {
                visit(contentView)
            }
            return result
        }
        spin(until: metalViewsCaughtUp)
    }

    // MARK: - Measuring

    private func constrainedMinSize() -> NSSize {
        return LayoutEngineTestSupport.constrainedMinSize(of: window)
    }

    private func engineEngaged() -> Bool {
        return LayoutEngineTestSupport.engineEngaged(in: window)
    }

    // The floor a view's subviews impose on it. On a flexible axis, a
    // subview's margins that are not themselves flexible, plus the subview's
    // own floor, become a minimum size for the superview.
    private func autoresizingFloor(of view: NSView, report: (NSView, NSSize) -> Void) -> NSSize {
        var result = NSSize.zero
        for sub in view.subviews where sub.translatesAutoresizingMaskIntoConstraints {
            let inner = autoresizingFloor(of: sub, report: report)
            let mask = sub.autoresizingMask
            let f = sub.frame
            let b = view.bounds
            var floor = NSSize.zero
            if mask.contains(.width) {
                floor.width = (mask.contains(.minXMargin) ? 0 : f.minX) +
                    (mask.contains(.maxXMargin) ? 0 : b.maxX - f.maxX) + inner.width
            }
            if mask.contains(.height) {
                floor.height = (mask.contains(.minYMargin) ? 0 : f.minY) +
                    (mask.contains(.maxYMargin) ? 0 : b.maxY - f.maxY) + inner.height
            }
            report(sub, floor)
            result.width = max(result.width, floor.width)
            result.height = max(result.height, floor.height)
        }
        return result
    }

    // Names the views whose margins impose a floor, to explain a failure.
    private func offenders() -> String {
        guard let frameView = window.contentView?.superview else {
            return ""
        }
        var lines: [String] = []
        _ = autoresizingFloor(of: frameView, report: { view, floor in
            if floor.width > maximumFloor.width || floor.height > maximumFloor.height {
                lines.append("\(type(of: view)) floor=\(NSStringFromSize(floor)) frame=\(NSStringFromRect(view.frame)) hidden=\(view.isHiddenOrHasHiddenAncestor)")
            }
        })
        return lines.joined(separator: "\n")
    }

    // Every visible view's frame, keyed by its path from the content view.
    // Siblings are numbered within their class so that the probe, which only
    // one of the two windows has, does not shift the others. Hidden views are
    // left out because what matters here is what the user sees; a hidden view
    // that imposes a floor is caught by the minimum-size check. The insides of
    // AppKit's controls and of WebKit's views are left out: they belong to
    // AppKit and WebKit, which lay them out lazily or asynchronously.
    private func frames() -> [String: NSRect] {
        var result = [String: NSRect]()
        func visit(_ view: NSView, path: String) {
            if !view.isHiddenOrHasHiddenAncestor {
                result[path] = view.frame
            }
            if view is WKWebView || view is NSControl {
                return
            }
            var counts = [String: Int]()
            for sub in view.subviews where sub.identifier != LayoutEngineTestSupport.engagingViewIdentifier {
                let name = String(describing: type(of: sub))
                let index = counts[name, default: 0]
                counts[name] = index + 1
                visit(sub, path: "\(path)/\(name)[\(index)]")
            }
        }
        if let contentView = window.contentView {
            visit(contentView, path: "")
        }
        return result
    }

    // MARK: - Running scenarios

    private struct Outcome {
        var minSize: NSSize
        // The title bar and anything AppKit puts in it, such as a tab bar
        // accessory. The window cannot be shorter than this with or without
        // the engine.
        var titleBarHeight: CGFloat
        var offenders: String
        var reachedSmall: NSSize
        var frames: [String: NSRect]
        var brokenConstraints: [String]
        var paneTilingProblems: [String]
    }

    // Problems with how panes fill their split views: each visible pane must
    // span the split view across its axis, and along it the panes must abut
    // with one divider between neighbors and no space left over.
    private func paneTilingProblems() -> [String] {
        var problems = [String]()
        func visit(_ view: NSView) {
            if let split = view as? PTYSplitView, !split.isHiddenOrHasHiddenAncestor {
                let along: (NSRect) -> (CGFloat, CGFloat) = { split.isVertical ? ($0.minX, $0.width) : ($0.minY, $0.height) }
                let across: (NSRect) -> (CGFloat, CGFloat) = { split.isVertical ? ($0.minY, $0.height) : ($0.minX, $0.width) }
                let panes = split.subviews.filter { !$0.isHidden }.sorted { along($0.frame).0 < along($1.frame).0 }
                var expectedStart: CGFloat = 0
                for pane in panes {
                    let (start, length) = along(pane.frame)
                    let (crossStart, crossLength) = across(pane.frame)
                    if abs(start - expectedStart) > 0.5 || abs(crossStart) > 0.5 || abs(crossLength - across(split.bounds).1) > 0.5 {
                        problems.append("\(type(of: pane)) \(NSStringFromRect(pane.frame)) in split \(NSStringFromRect(split.bounds))")
                    }
                    expectedStart = start + length + split.dividerThickness
                }
                if let last = panes.last, abs(along(last.frame).0 + along(last.frame).1 - along(split.bounds).1) > 0.5 {
                    problems.append("Panes do not fill split \(NSStringFromRect(split.bounds)); last is \(NSStringFromRect(last.frame))")
                }
            }
            view.subviews.forEach(visit)
        }
        if let contentView = window.contentView {
            visit(contentView)
        }
        return problems
    }

    // The path of the pane of a split view that contains `path`, which may be
    // `path` itself. A pane is a session or a nested split whose parent is a
    // split view.
    private func enclosingPane(of path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        var result: String?
        for i in components.indices where i > 0 {
            let isPane = components[i].hasPrefix("SessionView[") || components[i].hasPrefix("PTYSplitView[")
            if isPane && components[i - 1].hasPrefix("PTYSplitView[") {
                result = "/" + components[0...i].joined(separator: "/")
            }
        }
        return result
    }

    // Opens a window, optionally engages the engine, runs the scenario, then
    // shrinks the window to the small size and grows it back.
    private func run(engine: Bool, _ scenario: () throws -> Void) rethrows -> Outcome {
        fixture = TerminalWindowTestFixture(windowType: windowType, engageLayoutEngine: false)
        resize(to: largeSize)
        engineForced = engine
        recorder.reset()
        if engine {
            LayoutEngineTestSupport.engage(in: window)
        }
        try scenario()
        resize(to: largeSize)
        settle()
        let minSize = constrainedMinSize()
        let offenders = offenders()
        resize(to: smallSize)
        settle()
        let reachedSmall = window.frame.size
        resize(to: largeSize)
        settle()
        // A page squeezed to nothing along the way may have stalled. Now that
        // every pane has room, let them all finish so the comparison does not
        // depend on when loading happened to end.
        waitForPagesToLoad(in: browserSessions(), allowingSqueezedPanes: false)
        if !engine {
            // However late it happens, nothing in a scenario should engage
            // the engine on its own.
            XCTAssertFalse(engineEngaged(), "Something engaged the layout engine in a window that was meant to have it off")
        }
        let outcome = Outcome(minSize: minSize,
                              titleBarHeight: LayoutEngineTestSupport.titleBarHeight(of: window),
                              offenders: offenders,
                              reachedSmall: reachedSmall,
                              frames: frames(),
                              brokenConstraints: recorder.constraints,
                              paneTilingProblems: paneTilingProblems())
        fixture.close()
        fixture = nil
        return outcome
    }

    // `describe` is evaluated after the scenario has run, so it can report
    // what the scenario did.
    private func assertEngineIsHarmless(_ describe: @autoclosure () -> String,
                                        file: StaticString = #filePath,
                                        line: UInt = #line,
                                        _ scenario: () throws -> Void) rethrows {
        let off = try run(engine: false, scenario)
        let on = try run(engine: true, scenario)
        let context = describe()
        if expectsToReachSmallSize {
            XCTAssertEqual(off.reachedSmall, smallSize,
                           "\(context): without the engine the window did not reach \(NSStringFromSize(smallSize))",
                           file: file, line: line)
        }
        XCTAssertEqual(on.reachedSmall, off.reachedSmall,
                       "\(context): with the engine the window could not shrink as far",
                       file: file, line: line)
        XCTAssertLessThanOrEqual(on.minSize.width, maximumFloor.width,
                                 "\(context): min \(NSStringFromSize(on.minSize))\n\(on.offenders)",
                                 file: file, line: line)
        XCTAssertLessThanOrEqual(on.minSize.height, max(maximumFloor.height, on.titleBarHeight + 1),
                                 "\(context): min \(NSStringFromSize(on.minSize))\n\(on.offenders)",
                                 file: file, line: line)
        XCTAssertEqual(on.brokenConstraints, [],
                       "\(context): the layout engine broke constraints",
                       file: file, line: line)
        var mismatches: [String] = []
        for (path, frame) in on.frames.sorted(by: { $0.key < $1.key }) {
            guard let expected = off.frames[path] else {
                continue
            }
            // A zero-area view draws nothing wherever it is.
            if (frame.width == 0 || frame.height == 0) && (expected.width == 0 || expected.height == 0) {
                continue
            }
            // Panes are resized proportionally with minimum sizes, so their
            // sizes after a drastic shrink depend on the sequence of resizes,
            // and the engine adds a pass. A pane may differ as long as the
            // panes still tile their split view (checked below), and a view
            // inside a pane may differ only as much as the pane does.
            var slack = NSSize(width: 1, height: 1)
            if let pane = enclosingPane(of: path), let paneOn = on.frames[pane], let paneOff = off.frames[pane] {
                if pane == path {
                    continue
                }
                slack.width += abs(paneOn.width - paneOff.width)
                slack.height += abs(paneOn.height - paneOff.height)
            }
            if abs(frame.minX - expected.minX) > slack.width || abs(frame.minY - expected.minY) > slack.height ||
                abs(frame.width - expected.width) > slack.width || abs(frame.height - expected.height) > slack.height {
                mismatches.append("\(path): \(NSStringFromRect(frame)) expected \(NSStringFromRect(expected))")
            }
        }
        XCTAssertEqual(on.paneTilingProblems, [],
                       "\(context): with the engine, panes do not tile their split views",
                       file: file, line: line)
        XCTAssertEqual(mismatches.count, 0,
                       "\(context): after shrinking and growing back, the layout differs from a window without the engine:\n" +
                       mismatches.prefix(20).joined(separator: "\n"),
                       file: file, line: line)
    }

    // Sets preferences for the rest of the test, restoring them afterward.
    private func setPreferences(_ values: [String: Any]) {
        let ud = iTermUserDefaults.userDefaults()
        for (key, value) in values {
            let saved = ud.object(forKey: key)
            addTeardownBlock {
                if let saved {
                    ud.set(saved, forKey: key)
                } else {
                    ud.removeObject(forKey: key)
                }
            }
            ud.set(value, forKey: key)
        }
    }

    private func setTabStyle(_ style: iTermPreferencesTabStyle, position: Int32 = 0) {
        setPreferences([kPreferenceKeyTabStyle: Int(style.rawValue),
                        kPreferenceKeyTabPosition: Int(position),
                        kPreferenceKeyHideTabBar: true])
    }

    private var currentSession: PTYSession {
        guard let session = fixture.terminal.currentSession() else {
            it_fatalError("No session")
        }
        return session
    }

    // MARK: - Terminal windows

    func testOneTab() {
        assertEngineIsHarmless("one tab") {
            resize(to: NSSize(width: 1300, height: 900))
        }
    }

    func testTwoTabs() {
        assertEngineIsHarmless("two tabs") {
            fixture.addTab()
            resize(to: NSSize(width: 1300, height: 900))
        }
    }

    func testBackToOneTab() {
        assertEngineIsHarmless("back to one tab") {
            fixture.addTab()
            resize(to: NSSize(width: 1300, height: 900))
            fixture.terminal.close(fixture.terminal.currentTab())
        }
    }

    func testToolbeltShown() {
        assertEngineIsHarmless("toolbelt shown") {
            fixture.terminal.toggleToolbeltVisibility(nil)
        }
    }

    func testToolbeltShownThenHidden() {
        assertEngineIsHarmless("toolbelt hidden after growing") {
            fixture.terminal.toggleToolbeltVisibility(nil)
            resize(to: NSSize(width: 1300, height: 900))
            fixture.terminal.toggleToolbeltVisibility(nil)
        }
    }

    func testVerticalSplits() {
        assertEngineIsHarmless("four vertical panes") {
            var target = currentSession
            for _ in 0..<3 {
                target = fixture.split(target, vertically: true)
            }
        }
    }

    // NSSplitView makes its subviews fixed-size whenever it resizes, but a tool
    // added after that keeps whatever mask the toolbelt gave it.
    func testToolAddedToVisibleToolbelt() throws {
        guard let tool = iTermToolbeltView.allTools().compactMap({ $0 as? String }).first(where: {
            !iTermToolbeltView.shouldShowTool($0, profileType: .terminal)
        }) else {
            throw XCTSkip("Every tool is already shown")
        }
        addTeardownBlock {
            if iTermToolbeltView.shouldShowTool(tool, profileType: .terminal) {
                iTermToolbeltView.toggleShouldShowTool(tool)
            }
        }
        assertEngineIsHarmless("tool \(tool) added to a visible toolbelt") {
            fixture.terminal.toggleToolbeltVisibility(nil)
            if !iTermToolbeltView.shouldShowTool(tool, profileType: .terminal) {
                iTermToolbeltView.toggleShouldShowTool(tool)
            }
        }
    }

    func testStatusBar() {
        assertEngineIsHarmless("status bar on") {
            currentSession.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: true])
        }
    }

    // The window-level status bar container is hidden with a zero frame when
    // the current session stops having a status bar.
    func testStatusBarTurnedOff() {
        assertEngineIsHarmless("status bar turned off") {
            currentSession.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: true])
            currentSession.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: false])
            resize(to: NSSize(width: 1300, height: 900))
        }
    }

    // With one tab these themes draw the window title in place of the tab
    // bar, and the hidden bar's backing stays visible.
    func testCompactThemeOneTab() {
        setTabStyle(.TAB_STYLE_COMPACT)
        assertEngineIsHarmless("compact, one tab") {
            resize(to: NSSize(width: 1300, height: 900))
        }
    }

    func testCompactThemeBackToOneTab() {
        setTabStyle(.TAB_STYLE_COMPACT)
        assertEngineIsHarmless("compact, back to one tab") {
            fixture.addTab()
            resize(to: NSSize(width: 1300, height: 900))
            fixture.terminal.close(fixture.terminal.currentTab())
        }
    }

    func testMinimalThemeOneTab() {
        setTabStyle(.TAB_STYLE_MINIMAL)
        assertEngineIsHarmless("minimal, one tab") {}
    }

    // A side tab bar's backing is height-sizable, so a stale frame inside it
    // reaches the window while the bar is hidden.
    func testLeftTabBarOneTab() {
        setTabStyle(.TAB_STYLE_AUTOMATIC, position: 2)  // TAB_POSITION_LEFT
        assertEngineIsHarmless("left tab bar, one tab") {}
    }

    func testLeftTabBarTwoTabsWithToolbelt() {
        setTabStyle(.TAB_STYLE_AUTOMATIC, position: 2)  // TAB_POSITION_LEFT
        assertEngineIsHarmless("left tab bar, two tabs, toolbelt") {
            fixture.addTab()
            fixture.terminal.toggleToolbeltVisibility(nil)
        }
    }

    // MARK: - Browser sessions

    // Browser sessions have engaged the layout engine before, which turns every
    // stale frame in the window into a floor. They share windows with
    // terminals, so check a browser split pane and a browser tab.

    private func browserProfileWithLocalPage() throws -> [AnyHashable: Any] {
        let page = FileManager.default.temporaryDirectory.appendingPathComponent("TerminalWindowAutoLayoutFloorTests.html")
        let body = String(repeating: "lorem ipsum ", count: 2000)
        try "<html><body><form><input type=text value=x><select><option>a</option></select><textarea>t</textarea></form><p>\(body)</p></body></html>"
            .write(to: page, atomically: true, encoding: .utf8)
        var profile = fixture.browserProfile
        profile[KEY_INITIAL_URL] = page.absoluteString
        return profile
    }

    // The web view showing the page, as opposed to the hidden ones that run
    // extensions.
    private func pageWebView(in session: PTYSession) -> WKWebView? {
        guard let browserView = session.view?.subviews.first(where: { $0 is iTermBrowserView }) else {
            return nil
        }
        // A pane can be squeezed to nothing, so a zero-area web view counts.
        var candidates = [WKWebView]()
        func visit(_ view: NSView) {
            if let webView = view as? WKWebView, !webView.isHiddenOrHasHiddenAncestor {
                candidates.append(webView)
            }
            view.subviews.forEach(visit)
        }
        visit(browserView)
        return candidates.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    private func urlBars(in session: PTYSession) -> [iTermURLBar] {
        var result = [iTermURLBar]()
        func visit(_ view: NSView) {
            if let urlBar = view as? iTermURLBar {
                result.append(urlBar)
            }
            view.subviews.forEach(visit)
        }
        if let sessionView = session.view {
            visit(sessionView)
        }
        return result
    }

    // Starts the browser the way -startProgram: would and waits for its page
    // to finish loading, or only for its web view if the pane has no room. A
    // window without the probe must not have the engine engaged then; -run
    // also checks that it still does not at the end.
    private func becomeBrowser(_ session: PTYSession) {
        session.becomeBrowser(configuration: WKWebViewConfiguration(), restorableState: nil)
        // SessionView installs the browser view asynchronously and only then
        // gives the web view its size.
        XCTAssertTrue(spin(until: { pageWebView(in: session) != nil }), "The browser view was not installed")
        settle()
        waitForPagesToLoad(in: [session], allowingSqueezedPanes: true)
        if !engineForced {
            XCTAssertFalse(engineEngaged(), "A browser session engaged the layout engine")
        }
    }

    // Whether the page in `session` has finished loading as far as the user
    // can see.
    private func pageFinishedLoading(in session: PTYSession) -> Bool {
        guard let webView = pageWebView(in: session) else {
            return false
        }
        // Before its first navigation starts, a web view already reports the
        // URL, no loading, and full progress, so also require that a
        // navigation has committed.
        guard webView.backForwardList.currentItem != nil,
              !webView.isLoading,
              webView.estimatedProgress >= 1 else {
            return false
        }
        // The URL bar shows a spinner until the navigation delegate hears
        // that the load finished, which can come after the web view says so,
        // and the spinner changes the URL bar's layout.
        return MainActor.assumeIsolated {
            !urlBars(in: session).contains { $0.isLoading }
        }
    }

    // Waits for the pages in these browser sessions to finish loading. WebKit
    // does not finish loading into a web view with no area, which happens
    // when a pane is squeezed to nothing, so with `allowingSqueezedPanes`
    // such a page is not waited for.
    private func waitForPagesToLoad(in sessions: [PTYSession], allowingSqueezedPanes: Bool) {
        let loaded = spin(until: {
            sessions.allSatisfy { session in
                if allowingSqueezedPanes, let webView = pageWebView(in: session),
                   webView.bounds.width == 0 || webView.bounds.height == 0 {
                    return true
                }
                return pageFinishedLoading(in: session)
            }
        })
        if loaded {
            settle()
            return
        }
        var webViews = [String]()
        func visit(_ view: NSView) {
            if let webView = view as? WKWebView {
                webViews.append("\(NSStringFromRect(webView.frame)) hidden=\(webView.isHiddenOrHasHiddenAncestor) url=\(webView.url?.absoluteString ?? "nil") loading=\(webView.isLoading) progress=\(webView.estimatedProgress)")
            }
            view.subviews.forEach(visit)
        }
        for session in sessions {
            session.view.map(visit)
        }
        XCTFail("A browser did not finish loading its page. Web views:\n" + webViews.joined(separator: "\n"))
    }

    // Every browser session in the window, in any tab.
    private func browserSessions() -> [PTYSession] {
        return fixture.terminal.tabs().flatMap { tab in
            tab.sessions().filter { $0.view?.subviews.contains(where: { $0 is iTermBrowserView }) == true }
        }
    }

    func testBrowserSplitPane() throws {
        try XCTSkipUnless(iTermBrowserGateway.browserAllowed(checkIfNo: true), "Browser plugin not installed")
        try assertEngineIsHarmless("browser split pane") {
            let browser = fixture.split(currentSession, vertically: true, profile: try browserProfileWithLocalPage())
            becomeBrowser(browser)
            resize(to: NSSize(width: 1300, height: 900))
        }
    }

    func testBrowserTabWithToolbelt() throws {
        try XCTSkipUnless(iTermBrowserGateway.browserAllowed(checkIfNo: true), "Browser plugin not installed")
        try assertEngineIsHarmless("browser tab with toolbelt") {
            let browser = fixture.addTab(profile: try browserProfileWithLocalPage())
            becomeBrowser(browser)
            fixture.terminal.toggleToolbeltVisibility(nil)
            if !engineForced {
                XCTAssertFalse(engineEngaged(), "The toolbelt in a browser tab engaged the layout engine")
            }
        }
    }

    // MARK: - Development setting

#if DEBUG
    // Development builds have an advanced setting that engages the engine in
    // every new terminal window, for trying the window out by hand.
    func testDevelopmentSettingEngagesTheEngine() {
        let saved = iTermAdvancedSettingsModel.engageLayoutEngineInTerminalWindows()
        iTermAdvancedSettingsModel.setEngageLayoutEngineInTerminalWindows(true)
        addTeardownBlock {
            iTermAdvancedSettingsModel.setEngageLayoutEngineInTerminalWindows(saved)
        }
        fixture = TerminalWindowTestFixture(engageLayoutEngine: false)
        resize(to: largeSize)
        settle()
        XCTAssertTrue(engineEngaged(), "The setting did not engage the layout engine")
        resize(to: smallSize)
        settle()
        XCTAssertEqual(window.frame.size, smallSize)
        XCTAssertEqual(recorder.constraints, [])
    }
#endif

    // MARK: - Window types

    func testMaximizedWindow() {
        windowType = .WINDOW_TYPE_MAXIMIZED
        expectsToReachSmallSize = false
        assertEngineIsHarmless("maximized window") {
            fixture.addTab()
        }
    }

    func testNoTitleBarWindow() {
        windowType = .WINDOW_TYPE_NO_TITLE_BAR
        assertEngineIsHarmless("window without a title bar") {
            fixture.addTab()
            fixture.terminal.toggleToolbeltVisibility(nil)
        }
    }

    func testCompactWindow() {
        windowType = .WINDOW_TYPE_COMPACT
        assertEngineIsHarmless("compact window") {
            fixture.addTab()
        }
    }

    // MARK: - More configurations

    func testBottomTabBarWithStatusBarAtBottom() {
        setTabStyle(.TAB_STYLE_AUTOMATIC, position: 1)  // TAB_POSITION_BOTTOM
        setPreferences([kPreferenceKeyStatusBarPosition: 1])  // iTermStatusBarPositionBottom
        assertEngineIsHarmless("bottom tab bar, status bar at bottom") {
            fixture.addTab()
            currentSession.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: true])
        }
    }

    func testPaneTitlesAndHorizontalSplits() {
        setPreferences([kPreferenceKeyShowPaneTitles: true])
        assertEngineIsHarmless("pane titles, horizontal splits") {
            let below = fixture.split(currentSession, vertically: false)
            _ = fixture.split(below, vertically: true)
        }
    }

    func testFloatingPane() {
        assertEngineIsHarmless("floating pane") {
            fixture.addFloat(frame: NSRect(x: 60, y: 60, width: 300, height: 200))
        }
    }

    func testFindBarShownAndClosed() {
        assertEngineIsHarmless("find bar shown and closed") {
            currentSession.showFindPanel()
            settle()
            currentSession.view?.findDriver?.close()
        }
    }

    func testFindBarLeftOpen() {
        assertEngineIsHarmless("find bar left open") {
            currentSession.showFindPanel()
        }
    }

    func testComposerOpenAndClosed() {
        assertEngineIsHarmless("composer opened and closed") {
            currentSession.openComposer(with: "", escaping: .none)
            settle()
            _ = currentSession.closeComposer()
        }
    }

    func testAnnouncement() {
        assertEngineIsHarmless("announcement") {
            guard let announcement = iTermAnnouncementViewController.announcement(withTitle: "Test",
                                                                                 style: .kiTermAnnouncementViewStyleWarning,
                                                                                 withActions: ["OK"],
                                                                                 completion: { _ in }) else {
                it_fatalError("No announcement")
            }
            currentSession.queueAnnouncement(announcement, identifier: "TerminalWindowAutoLayoutFloorTests")
        }
    }

    func testMinimalThemeWithToolbeltAndStatusBar() {
        setTabStyle(.TAB_STYLE_MINIMAL)
        assertEngineIsHarmless("minimal, toolbelt, status bar") {
            fixture.terminal.toggleToolbeltVisibility(nil)
            currentSession.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: true])
        }
    }

    // MARK: - Random sequences

    // A reproducible random sequence of the things people do to windows. Each
    // seed picks a tab style and position and then a sequence of actions. The
    // engaged window is checked after every step as well as at the end. Set
    // ITERM2_LAYOUT_SEEDS (comma-separated) to run particular seeds, for
    // example to reproduce a failure.
    func testRandomSequences() throws {
        let seeds: [UInt64]
        if let value = ProcessInfo.processInfo.environment["ITERM2_LAYOUT_SEEDS"] {
            seeds = value.split(separator: ",").compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        } else {
            seeds = [1, 2, 3, 4, 5, 6]
        }
        let browserAllowed = iTermBrowserGateway.browserAllowed(checkIfNo: true)
        for seed in seeds {
            var rng = FloorTestSeededGenerator(seed: seed)
            let styles: [iTermPreferencesTabStyle] = [.TAB_STYLE_AUTOMATIC, .TAB_STYLE_MINIMAL, .TAB_STYLE_COMPACT]
            let style = styles[Int(rng.next() % UInt64(styles.count))]
            let position = Int32(rng.next() % 4)
            setTabStyle(style, position: position)
            var history = ["seed \(seed): style \(style.rawValue), tab position \(position)"]
            let steps = 20
            try assertEngineIsHarmless("random sequence: " + history.joined(separator: " | ")) {
                // Each run replays the same sequence.
                var rng = FloorTestSeededGenerator(seed: seed)
                _ = rng.next()
                _ = rng.next()
                var steps = steps
                if !engineForced {
                    history = [history[0]]
                }
                while steps > 0 {
                    steps -= 1
                    let action = try randomAction(&rng, browserAllowed: browserAllowed)
                    if !engineForced {
                        history.append(action)
                    }
                    settle()
                    if engineForced {
                        let minSize = constrainedMinSize()
                        let maximumHeight = max(maximumFloor.height, LayoutEngineTestSupport.titleBarHeight(of: window) + 1)
                        if minSize.width > maximumFloor.width || minSize.height > maximumHeight || !recorder.constraints.isEmpty {
                            XCTFail("After \(history.count - 1) steps, min \(NSStringFromSize(minSize)), broken constraints \(recorder.constraints)\n\(offenders())\nHistory:\n" + history.joined(separator: "\n"))
                            return
                        }
                    }
                }
            }
        }
    }

    private func randomAction(_ rng: inout FloorTestSeededGenerator, browserAllowed: Bool) throws -> String {
        let terminal = fixture.terminal
        let sessionCount = terminal.currentTab()?.sessions().count ?? 1
        switch rng.next() % 14 {
        case 0:
            fixture.addTab()
            return "add tab"
        case 1:
            if terminal.numberOfTabs() > 1 {
                terminal.close(terminal.currentTab())
                return "close tab"
            }
            return "close tab (skipped, last tab)"
        case 2, 3:
            if sessionCount < 4 {
                let vertically = rng.next() % 2 == 0
                _ = fixture.split(currentSession, vertically: vertically)
                return "split \(vertically ? "vertically" : "horizontally")"
            }
            return "split (skipped, enough panes)"
        case 4:
            fixture.addFloat(frame: NSRect(x: 40 + CGFloat(rng.next() % 100), y: 40, width: 250, height: 150))
            return "add floating pane"
        case 5:
            terminal.toggleToolbeltVisibility(nil)
            return "toggle toolbelt"
        case 6:
            let on = rng.next() % 2 == 0
            currentSession.setSessionSpecificProfileValues([KEY_SHOW_STATUS_BAR: on])
            return "status bar \(on ? "on" : "off")"
        case 7:
            currentSession.showFindPanel()
            return "show find"
        case 8:
            currentSession.view?.findDriver?.close()
            return "close find"
        case 9:
            if rng.next() % 2 == 0 {
                currentSession.openComposer(with: "", escaping: .none)
                return "open composer"
            }
            _ = currentSession.closeComposer()
            return "close composer"
        case 10, 11:
            let size = NSSize(width: 300 + CGFloat(rng.next() % 1100), height: 200 + CGFloat(rng.next() % 800))
            resize(to: size)
            return "resize to \(NSStringFromSize(size))"
        case 12:
            if terminal.numberOfTabs() > 1 {
                terminal.nextTab(nil)
                return "next tab"
            }
            return "next tab (skipped, one tab)"
        default:
            if browserAllowed && sessionCount < 4 {
                let browser = fixture.split(currentSession, vertically: true, profile: try browserProfileWithLocalPage())
                becomeBrowser(browser)
                return "add browser split pane"
            }
            return "add browser split pane (skipped)"
        }
    }
}

// SplitMix64, so a seed always produces the same sequence.
private struct FloorTestSeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
