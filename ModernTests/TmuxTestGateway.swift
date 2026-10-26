//
//  TmuxTestGateway.swift
//  iTerm2 ModernTests
//
//  Test doubles for driving a real TmuxGateway without iTerm2's windows: a delegate whose methods
//  do nothing, and a gateway harness that records what the gateway writes and feeds it replies.
//

import XCTest
@testable import iTerm2SharedARC

/// A TmuxGatewayDelegate that does nothing. Subclasses override what they need.
class TmuxTestGatewayDelegate: NSObject, TmuxGatewayDelegate {
    func tmuxWrite(_ string: String!) {}
    func tmuxSessionChanged(_ sessionName: String!, sessionId: Int32) {}
    func tmuxController() -> TmuxController! { return nil }
    func tmuxUpdateLayout(forWindow windowId: Int32, layout: String!, visibleLayout: String!, zoomed: NSNumber!, only: Bool) -> Bool { return false }
    func tmuxWindowAdded(withId windowId: Int32) {}
    func tmuxWindowClosed(withId windowId: Int32) {}
    func tmuxWindowRenamed(withId windowId: Int32, to newName: String!) {}
    func tmuxHostDisconnected(_ dcsID: String!) {}
    func tmuxReadTask(_ data: Data!, windowPane wp: Int32, latency: NSNumber!) {}
    func tmuxSessionsChanged() {}
    func tmuxWindowsDidChange() {}
    func tmuxSession(_ sessionId: Int32, renamed newName: String!) {}
    func tmuxClientSize() -> VT100GridSize { return VT100GridSizeMake(120, 40) }
    func tmuxNumberOfLinesOfScrollbackHistory() -> Int { return 1000 }
    func tmuxSetSecureLogging(_ secureLogging: Bool) {}
    func tmuxPrintLine(_ line: String!) {}
    func tmuxGatewayWindow() -> (NSWindowController & iTermWindowController)! { return nil }
    func tmuxInitialCommandDidCompleteSuccessfully() {}
    func tmuxInitialCommandDidFailWithError(_ error: String!) {}
    func tmuxCannotSendCharacters(inSupplementaryPlanes string: String!, windowPane: Int32) {}
    func tmuxDidOpenInitialWindows() {}
    func tmuxDoubleAttach(forSessionGUID sessionGUID: String!) {}
    func tmuxOwningSessionGUID() -> String! { return "test" }
    func tmuxGatewayOriginIdentifier() -> String! { return nil }
    func tmuxGatewayIT2ClientRecord() -> [String: String]! { return nil }
    func tmuxGatewayShouldForceDetach() -> Bool { return false }
    func tmuxGatewayDidTimeOutDuringInitialization(_ duringInitialization: Bool) {}
    func tmuxActiveWindowPaneDidChange(inWindow windowID: Int32, toWindowPane paneID: Int32) {}
    func tmuxSessionWindowDidChange(to windowID: Int32) {}
    func tmuxWindowPaneDidPause(_ wp: Int32, notification: Bool) {}
    func tmuxSessionPasteDidChange(_ pasteBufferName: String!) {}
    func tmuxClientSessionChanged(_ clientName: String!) {}
    func tmuxClientDetached(_ clientName: String!) {}
    func tmuxServerMayOmitEndGuard(beforeExit mayOmit: Bool) {}

    /// The gateway's delegate is its PTYSession in the app, which panes ask for its SSH
    /// Integration connection, its job (see updateInferredTmuxHost), and its processes. Here there
    /// are none.
    @objc var conductor: Conductor? { return nil }
    @objc let genericScope = iTermVariableScope()
    @objc var sessionProcessInfoProvider: SessionProcessInfoProvider? { return nil }
}

/// A real TmuxGateway with no tmux behind it: records each command line it writes, and answers
/// them one at a time in order.
final class TmuxRecordingGateway: TmuxTestGatewayDelegate {
    private(set) var gateway: TmuxGateway!
    private(set) var written = [String]()
    private var replyNumber = 0

    override init() {
        super.init()
        gateway = TmuxGateway(delegate: self, dcsID: "test")
        gateway.minimumServerVersion = NSDecimalNumber(string: "3.2")
        gateway.newline = "\n"
        // Writing starts once tmux reports a session.
        feed(["%session-changed $1 s"])
    }

    override func tmuxWrite(_ string: String!) {
        written += string.split(separator: "\n").map(String.init)
    }

    /// Answer the oldest unanswered command.
    func reply(_ lines: [String] = [], error: Bool = false) {
        replyNumber += 1
        feed(["%begin 1 \(replyNumber) 1"] + lines + [(error ? "%error" : "%end") + " 1 \(replyNumber) 1"])
    }

    private func feed(_ lines: [String]) {
        for line in lines {
            let token = VT100Token()
            token.type = TMUX_LINE
            token.string = line
            token.savedData = Data(line.utf8)
            gateway.execute(token)
        }
    }
}
