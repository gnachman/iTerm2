//
//  AppSwitchingPreventionDetector.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/3/24.
//

import Foundation

@objc(iTermAppSwitchingPreventionDetectorDelegate)
protocol AppSwitchingPreventionDetectorDelegate: AnyObject {
    func appSwitchingPreventionDetectorDidDetectFailure()
}

@objc(iTermAppSwitchingPreventionDetector)
class AppSwitchingPreventionDetector: NSObject {
    var timeout = TimeInterval(3.0)
    @objc weak var delegate: AppSwitchingPreventionDetectorDelegate?

    private enum State {
        case ground
        case pending(command: String)
        case waiting
    }
    private var state = State.ground {
        didSet {
            DLog("state set to \(state)")
        }
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil,
                                               queue: nil) { [weak self] _ in
            self?.applicationDidResignActive()
        }
    }

    @objc(didExecuteCommand:)
    func didExecute(command: String) {
        DLog("didExecute \(command)")
        if !IsSecureEventInputEnabled() {
            DLog("sei off")
            return
        }
        switch state {
        case .ground:
            if isValidOpenCommand(command) {
                state = .pending(command: command)
            }
        case .pending:
            if isValidOpenCommand(command) {
                state = .pending(command: command)
            } else {
                state = .ground
            }
        case .waiting:
            break
        }
    }

    @objc
    func commandDidFinish(status: Int) {
        DLog("commandDidFinish status=\(status)")
        switch state {
        case .ground:
            break
        case .pending:
            if IsSecureEventInputEnabled() {
                startTimer()
                state = .waiting
            } else {
                state = .ground
            }
        case .waiting:
            state = .ground
        }
    }

    private func isValidOpenCommand(_ command: String) -> Bool {
        let parts = (command as NSString).componentsInShellCommand() ?? []
        if parts.first != "open" {
            return false
        }
        // You could catch broken invocations with a fancier algorithm here.
        return parts.count > 1
    }

    private func startTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.timerDidFire()
        }
    }

    private func timerDidFire() {
        DLog("timer fired")
        switch state {
        case .ground, .pending:
            return
        case .waiting:
            state = .ground
            if IsSecureEventInputEnabled() {
                showWarning()
            }
        }
    }

    private func applicationDidResignActive() {
        state = .ground
    }

    private func showWarning() {
        DLog("show warning")
        delegate?.appSwitchingPreventionDetectorDidDetectFailure()
    }
}
