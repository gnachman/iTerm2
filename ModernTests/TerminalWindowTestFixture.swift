//
//  TerminalWindowTestFixture.swift
//  ModernTests
//
//  Hosts a real terminal window (PseudoTerminal) in the test process with sessions that are set up
//  like ordinary ones but never launch a process. Pair it with MouseEventSynthesizer to drive views
//  with mouse events the way a user would, without a person at the keyboard.
//

import XCTest
@testable import iTerm2SharedARC

final class TerminalWindowTestFixture {
    let terminal: PseudoTerminal
    private let profile: [AnyHashable: Any]
    private var brokenConstraintRecorder: LayoutEngineTestSupport.BrokenConstraintRecorder?

    var window: NSWindow {
        guard let window = terminal.window else {
            it_fatalError("Terminal has no window")
        }
        return window
    }

    var mouse: MouseEventSynthesizer {
        return MouseEventSynthesizer(window: window)
    }

    /// Opens a window with one tab holding one session. With
    /// `engageLayoutEngine`, which defaults to the ITERM2_ENGAGE_LAYOUT_ENGINE
    /// environment variable, the window's layout engine is engaged, and
    /// closing the window fails the test if the engine enforces a minimum size
    /// or had to break constraints.
    init(windowType: iTermWindowType = .WINDOW_TYPE_NORMAL,
         engageLayoutEngine: Bool = LayoutEngineTestSupport.engageInEveryFixtureWindow) {
        guard let profile = ProfileModel.sharedInstance().defaultBookmark(),
              let terminal = PseudoTerminal(smartLayout: false,
                                            windowType: windowType,
                                            savedWindowType: windowType,
                                            percentage: iTermPercentage(width: 0, height: 0),
                                            screen: -1,
                                            profile: profile) else {
            it_fatalError("Could not create a terminal window")
        }
        self.profile = profile
        self.terminal = terminal
        // Development builds check every layout of a terminal window for a
        // stale frame that would become a minimum window size if the layout
        // engine were engaged. Fail whichever test produced one.
        AutoresizingFloorAuditor.violationHandler = { violation in
            XCTFail("Autoresizing floor: \(violation)")
        }
        iTermController.sharedInstance()?.addTerminalWindow(terminal)
        _ = addTab()
        window.makeKeyAndOrderFront(nil)
        if engageLayoutEngine {
            brokenConstraintRecorder = LayoutEngineTestSupport.BrokenConstraintRecorder()
            LayoutEngineTestSupport.engage(in: window)
        }
    }

    /// Closes the window. Call from tearDown.
    func close() {
        if let recorder = brokenConstraintRecorder {
            checkLayoutEngine(recorder)
            recorder.stop()
            brokenConstraintRecorder = nil
        }
        window.close()
        AutoresizingFloorAuditor.violationHandler = nil
    }

    private func checkLayoutEngine(_ recorder: LayoutEngineTestSupport.BrokenConstraintRecorder) {
        let minSize = LayoutEngineTestSupport.constrainedMinSize(of: window)
        let maximumHeight = max(40, LayoutEngineTestSupport.titleBarHeight(of: window) + 1)
        if minSize.width > 20 || minSize.height > maximumHeight {
            let culprits = window.contentView.map {
                AutoresizingFloorAuditor.violations(in: $0, threshold: 1).joined(separator: "\n")
            } ?? ""
            XCTFail("With the layout engine engaged the window cannot shrink below \(NSStringFromSize(minSize))\n\(culprits)")
        }
        if !recorder.constraints.isEmpty {
            XCTFail("With the layout engine engaged it broke constraints:\n" + recorder.constraints.joined(separator: "\n"))
        }
    }

    private func makeSession(profile: [AnyHashable: Any]? = nil) -> PTYSession {
        guard let session = PTYSession(synthetic: false) else {
            it_fatalError("Could not create a session")
        }
        session.profile = profile ?? self.profile
        return session
    }

    /// The default profile changed to open a browser instead of a terminal.
    var browserProfile: [AnyHashable: Any] {
        var result = profile
        result[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeBrowserValue
        return result
    }

    /// Adds a tab with one session and returns the session. Pass `profile` to
    /// use something other than the default profile, such as `browserProfile`.
    @discardableResult
    func addTab(profile: [AnyHashable: Any]? = nil) -> PTYSession {
        let session = makeSession(profile: profile)
        terminal.setupSession(session, with: nil)
        terminal.insert(session, at: Int32(terminal.numberOfTabs()))
        return session
    }

    /// Splits `target` and returns the new session, which goes after (right of or below) it.
    @discardableResult
    func split(_ target: PTYSession, vertically: Bool, profile: [AnyHashable: Any]? = nil) -> PTYSession {
        let session = makeSession(profile: profile)
        terminal.splitVertically(vertically,
                                 before: false,
                                 adding: session,
                                 targetSession: target,
                                 performSetup: true)
        return session
    }

    /// Adds a floating session to the current tab with the given frame in the tab's container.
    @discardableResult
    func addFloat(frame: NSRect) -> PTYSession {
        guard let tab = terminal.currentTab() else {
            it_fatalError("No tab")
        }
        let session = makeSession()
        terminal.setupSession(session, with: nil)
        tab.addFloatingSession(session, frame: frame)
        return session
    }

    /// The center of a view, in window coordinates.
    func center(of view: NSView) -> NSPoint {
        return view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }
}
