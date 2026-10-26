//
//  FlowControlMonitor.swift
//  iTerm2SharedARC
//
//  While the showSSHFlowControlMonitor advanced setting is on, samples every SSH Integration
//  conductor's flow controller ten times a second, keeps the last minute of each, and shows the
//  current session's chain of connections in a window. Sampling only reads the controllers.
//

import AppKit

@objc(iTermFlowControlMonitor)
@MainActor
final class FlowControlMonitor: NSObject {
    @objc static let instance = FlowControlMonitor()

    /// What the window shows for one conductor.
    struct Connection {
        var guid: String
        var depth: Int32
        var name: String
        /// Why there is no controller; nil when there is one.
        var reasonOff: String?
        var flowVersion: Int
        var clockName: String?
        var history: FlowControlHistory
        /// Command round trips in the last minute, with flow control on or off.
        var roundTrips: [Conductor.RoundTrip]
    }

    private static let sampleInterval: TimeInterval = 0.1
    /// What the window shows now, for the current session, outermost first.
    private(set) var connections = [Connection]()
    var isWindowVisible: Bool {
        windowController?.window?.isVisible ?? false
    }
    var monitorView: NSView? {
        windowController?.window?.contentView
    }
    private var histories = [String: FlowControlHistory]()
    /// Per session, the bytes it had received, sampled, over the last minute.
    private var received = [String: [FlowControlHistory.Point]]()
    private var timer: Timer?
    private var windowController: FlowControlMonitorWindowController?
    private var observer: NSObjectProtocol?
    private var redrawPolicy = FlowControlMonitorRedrawPolicy()
    private var occlusionObserver: NSObjectProtocol?

    /// Call once at launch.
    @objc func start() {
        guard observer == nil else {
            return
        }
        observer = NotificationCenter.default.addObserver(forName: NSNotification.Name(iTermAdvancedSettingsDidChange),
                                                          object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated {
                FlowControlMonitor.instance.settingDidChange()
            }
        }
        settingDidChange()
    }

    private func settingDidChange() {
        if iTermAdvancedSettingsModel.showSSHFlowControlMonitor() {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        if timer == nil {
            let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { _ in
                MainActor.assumeIsolated {
                    FlowControlMonitor.instance.sample()
                }
            }
            // In the common modes, so the charts keep moving while a menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        if windowController == nil {
            let windowController = FlowControlMonitorWindowController()
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: windowController.window,
                queue: .main) { _ in
                    MainActor.assumeIsolated {
                        // Catch up at once when it can be seen again.
                        FlowControlMonitor.instance.redrawPolicy.invalidate()
                        FlowControlMonitor.instance.sample()
                    }
                }
            windowController.userDidClose = {
                // Closing the window is how to turn it off. Stop now rather than when the
                // setting's change is noticed.
                iTermAdvancedSettingsModel.setShowSSHFlowControlMonitor(false)
                FlowControlMonitor.instance.hide()
            }
            self.windowController = windowController
        }
        windowController?.showWindow(nil)
        redrawPolicy.invalidate()
        sample()
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        histories.removeAll()
        received.removeAll()
        connections.removeAll()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        occlusionObserver = nil
        let windowController = self.windowController
        self.windowController = nil
        windowController?.userDidClose = nil
        windowController?.close()
    }

    private func sample() {
        let now = Conductor.monotonicNow()
        var seen = Set<String>()
        var sessionsSeen = Set<String>()
        for session in iTermController.sharedInstance()?.allSessions() ?? [] {
            sessionsSeen.insert(session.guid)
            var totals = received[session.guid] ?? []
            totals.append(FlowControlHistory.Point(time: now, value: Double(session.screen.bytesReceived())))
            totals.removeAll { $0.time < now - 60 }
            received[session.guid] = totals
            for conductor in Self.chain(session.conductor) where !seen.contains(conductor.guid) {
                seen.insert(conductor.guid)
                var history = histories[conductor.guid] ?? FlowControlHistory()
                if let controller = conductor.flowController {
                    history.record(controller.snapshot(now: now), at: now)
                } else {
                    history.recordGap(at: now)
                }
                histories[conductor.guid] = history
            }
        }
        for guid in histories.keys where !seen.contains(guid) {
            histories.removeValue(forKey: guid)
        }
        for guid in received.keys where !sessionsSeen.contains(guid) {
            received.removeValue(forKey: guid)
        }
        let session = iTermController.sharedInstance()?.currentTerminal?.currentSession()
        let connections = Self.chain(session?.conductor).reversed().map { conductor in
            Connection(guid: conductor.guid,
                       depth: conductor.depth,
                       name: conductor.sshIdentity.compactDescription,
                       reasonOff: Self.reasonOff(conductor),
                       flowVersion: conductor.flowVersion,
                       clockName: conductor.flowClockName,
                       history: histories[conductor.guid] ?? FlowControlHistory(),
                       roundTrips: conductor.roundTrips)
        }
        self.connections = connections
        guard let windowController, let window = windowController.window else {
            return
        }
        let sessionReceived = session.flatMap { received[$0.guid] } ?? []
        let activity = FlowControlMonitorRedrawPolicy.Activity(sessionName: session?.name,
                                                               connections: connections,
                                                               received: sessionReceived)
        let visible = window.occlusionState.contains(.visible) && !window.isMiniaturized
        guard redrawPolicy.shouldRedraw(activity, visible: visible, now: now) else {
            return
        }
        windowController.update(session: session,
                                connections: connections,
                                received: sessionReceived,
                                now: now)
    }

    /// The conductor and those it is nested in, innermost first.
    private static func chain(_ innermost: Conductor?) -> [Conductor] {
        var result = [Conductor]()
        var current = innermost
        while let conductor = current {
            result.append(conductor)
            current = conductor.parent
        }
        return result
    }

    /// Why the conductor is not paced: what was decided when its flow control was last tried,
    /// not what the settings would decide now.
    static func reasonOff(_ conductor: Conductor) -> String? {
        // Localization unneeded: technical output in a debugging window.
        if conductor.flowController != nil {
            return nil
        }
        if !conductor.framing {
            return "Off: this connection has no framer."
        }
        if conductor.flowOnPending {
            return "Starting: waiting for the framer to answer “flow on”."
        }
        switch conductor.flowOffReason {
        case .settingOff:
            return "Off: the “Pace output from remote hosts” advanced setting was off when flow control was decided for this connection."
        case .nestedOffForTesting:
            return "Off: flow control for nested connections is turned off for testing."
        case .parentDoesNotFrame:
            return "Off: the connection it is nested in does not frame its output."
        case .waitingForParent:
            return "Off until the connection it is nested in runs flow control version 2."
        case .unsupported:
            return "Off: the framer does not support flow control."
        case .aborted:
            return "Off: “flow on” was aborted and not sent again."
        case nil:
            return "Off: flow control is not running on this connection."
        }
    }
}
