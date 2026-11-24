//
//  WindowSpaceRestorer.swift
//  iTerm2
//

import AppKit

/// Moves restored windows back to their Spaces, and asks the user to add
/// desktops when an arrangement uses more than a display has.
///
/// Windows restored together, such as all the windows of one arrangement, are
/// collected and handled on the next turn of the runloop. By then each has been
/// ordered in at its saved frame, so ordering it in can't undo the move, and one
/// alert covers every window whose desktop is missing.
///
/// macOS has no API for adding a desktop, so the alert asks the user to add them
/// in Mission Control and then press Continue.
class WindowSpaceRestorer {
    static let shared = WindowSpaceRestorer()

    private struct Request {
        weak var window: NSWindow?
        var value: [String: Any]
    }

    private var pending = [Request]()
    private var flushScheduled = false
    private var showingAlert = false

    func enqueue(_ window: NSWindow, value: [String: Any]) {
        pending.append(Request(window: window, value: value))
        scheduleFlush()
    }

    private func scheduleFlush() {
        if flushScheduled {
            return
        }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        // The alert runs a modal loop, which also runs main-queue blocks. Leave
        // windows restored meanwhile for when it is gone, so alerts don't nest.
        if showingAlert {
            return
        }
        let requests = pending.filter { $0.window != nil }
        pending.removeAll()
        var missing = moveWindowsWhoseDesktopsExist(requests)
        showingAlert = true
        while !missing.isEmpty {
            switch askToAddDesktops(for: missing) {
            case .continue:
                missing = moveWindowsWhoseDesktopsExist(missing)
            case .openMissionControl:
                openMissionControl()
            case .skip:
                DLog("User skipped moving \(missing.count) windows to missing desktops")
                missing.removeAll()
            }
        }
        showingAlert = false
        if !pending.isEmpty {
            scheduleFlush()
        }
    }

    /// Moves every window whose desktop exists or can't be had by adding
    /// desktops, and returns the rest.
    private func moveWindowsWhoseDesktopsExist(_ requests: [Request]) -> [Request] {
        let desktops = iTermWindowSpace.desktops() ?? []
        var missing = [Request]()
        for request in requests {
            guard let window = request.window else {
                continue
            }
            if iTermWindowSpace.missingDesktop(forArrangementValue: request.value, among: desktops) != nil {
                missing.append(request)
            } else {
                iTermWindowSpace.move(window, toSpaceFromArrangementValue: request.value)
            }
        }
        return missing
    }

    private enum Choice {
        case `continue`
        case openMissionControl
        case skip
    }

    private func askToAddDesktops(for requests: [Request]) -> Choice {
        let desktops = iTermWindowSpace.desktops() ?? []
        // The highest desktop needed on each display, in the order first seen.
        var highest = [String: Int]()
        var displays = [String]()
        for request in requests {
            guard let missing = iTermWindowSpace.missingDesktop(forArrangementValue: request.value,
                                                                among: desktops) else {
                continue
            }
            if highest[missing.displayIdentifier] == nil {
                displays.append(missing.displayIdentifier)
            }
            highest[missing.displayIdentifier] = max(highest[missing.displayIdentifier] ?? 0, missing.index)
        }
        let lines = displays.map { display -> String in
            let number = (highest[display] ?? 0) + 1
            if let name = iTermWindowSpace.displayName(forIdentifier: display) {
                return String(localized: "WindowSpaceRestorer.AddDesktopsOnDisplay",
                              defaultValue: "Add desktops to “\(name)” until there is a Desktop \(number).",
                              comment: "One line of the alert shown when a restored window arrangement uses desktops (macOS Spaces) that don’t exist. The first placeholder is a display’s name; the second is the number Mission Control shows in a desktop’s name, as in “Desktop 4”.")
            }
            return String(localized: "WindowSpaceRestorer.AddDesktops",
                          defaultValue: "Add desktops until there is a Desktop \(number).",
                          comment: "One line of the alert shown when a restored window arrangement uses desktops (macOS Spaces) that don’t exist. The placeholder is the number Mission Control shows in a desktop’s name, as in “Desktop 4”.")
        }
        let explanation = String(localized: "WindowSpaceRestorer.MissingDesktopsBody",
                                 defaultValue: "This arrangement puts some windows on desktops that don’t exist now, and iTerm2 can’t add desktops itself. Add them in Mission Control, then click Continue.",
                                 comment: "Body of the alert shown when a restored window arrangement uses desktops (macOS Spaces) that don’t exist. Lines saying which desktops to add follow it.")

        let continueLabel = String(localized: "WindowSpaceRestorer.ContinueButton",
                                   defaultValue: "Continue",
                                   comment: "Button in the missing-desktops alert: check again and move windows to the desktops that now exist.")
        let openMissionControlLabel = String(localized: "WindowSpaceRestorer.OpenMissionControlButton",
                                             defaultValue: "Open Mission Control",
                                             comment: "Button in the missing-desktops alert that opens macOS Mission Control, where the user can add desktops.")
        let skipLabel = String(localized: "WindowSpaceRestorer.SkipButton",
                               defaultValue: "Skip",
                               comment: "Button in the missing-desktops alert: leave the windows on the current desktop.")

        let warning = iTermWarning()
        warning.heading = String(localized: "WindowSpaceRestorer.MissingDesktopsHeading",
                                 defaultValue: "Add Desktops?",
                                 comment: "Heading of the alert shown when a restored window arrangement uses desktops (macOS Spaces) that don’t exist.")
        warning.title = ([explanation] + lines).joined(separator: "\n\n")
        warning.actionLabels = [continueLabel, openMissionControlLabel, skipLabel]
        // Mission Control opens on the Mac, not the phone.
        warning.notOfferedRemotelyLabels = [openMissionControlLabel]
        warning.cancelLabel = skipLabel
        warning.warningType = .kiTermWarningTypePersistent
        switch warning.runModal() {
        case .kiTermWarningSelection0:
            return .continue
        case .kiTermWarningSelection1:
            return .openMissionControl
        default:
            return .skip
        }
    }

    private func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")  // Localization unneeded
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                DLog("Failed to open Mission Control: \(error)")
            }
        }
    }
}
