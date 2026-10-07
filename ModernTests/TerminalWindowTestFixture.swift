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

    var window: NSWindow {
        guard let window = terminal.window else {
            it_fatalError("Terminal has no window")
        }
        return window
    }

    var mouse: MouseEventSynthesizer {
        return MouseEventSynthesizer(window: window)
    }

    /// Opens a window with one tab holding one session.
    init() {
        guard let profile = ProfileModel.sharedInstance().defaultBookmark(),
              let terminal = PseudoTerminal(smartLayout: false,
                                            windowType: .WINDOW_TYPE_NORMAL,
                                            savedWindowType: .WINDOW_TYPE_NORMAL,
                                            percentage: iTermPercentage(width: 0, height: 0),
                                            screen: -1,
                                            profile: profile) else {
            it_fatalError("Could not create a terminal window")
        }
        self.profile = profile
        self.terminal = terminal
        iTermController.sharedInstance()?.addTerminalWindow(terminal)
        _ = addTab()
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window. Call from tearDown.
    func close() {
        window.close()
    }

    private func makeSession() -> PTYSession {
        guard let session = PTYSession(synthetic: false) else {
            it_fatalError("Could not create a session")
        }
        session.profile = profile
        return session
    }

    /// Adds a tab with one session and returns the session.
    @discardableResult
    func addTab() -> PTYSession {
        let session = makeSession()
        terminal.setupSession(session, with: nil)
        terminal.insert(session, at: Int32(terminal.numberOfTabs()))
        return session
    }

    /// Splits `target` and returns the new session, which goes after (right of or below) it.
    @discardableResult
    func split(_ target: PTYSession, vertically: Bool) -> PTYSession {
        let session = makeSession()
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
