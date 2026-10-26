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
            windowController.didClose = {
                // Closing the window is how to turn it off. Stop now rather than when the
                // setting's change is noticed.
                iTermAdvancedSettingsModel.setShowSSHFlowControlMonitor(false)
                FlowControlMonitor.instance.hide()
            }
            self.windowController = windowController
        }
        windowController?.showWindow(nil)
        sample()
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        histories.removeAll()
        received.removeAll()
        connections.removeAll()
        let windowController = self.windowController
        self.windowController = nil
        windowController?.didClose = nil
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
        windowController?.update(session: session,
                                 connections: connections,
                                 received: session.flatMap { received[$0.guid] } ?? [],
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

    private static func reasonOff(_ conductor: Conductor) -> String? {
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
        if let parent = conductor.parent, parent.flowController == nil || parent.flowVersion < 2 {
            return "Off until the connection it is nested in runs flow control version 2."
        }
        if !Conductor.flowControlAvailable && !conductor.flowMayBeOn {
            return "Off: the “Pace output from remote hosts” advanced setting is off."
        }
        return "Off: the framer does not support flow control."
    }
}
