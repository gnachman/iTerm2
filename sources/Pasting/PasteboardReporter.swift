//
//  PasteboardReporter.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/6/22.
//

import Foundation

@objc(iTermPasteboardReporterDelegate)
protocol PasteboardReporterDelegate: AnyObject {
    @objc func pasteboardReporterRequestPermission(_ sender: PasteboardReporter,
                                                   completion: @escaping (_ allowed: Bool, _ permanently: Bool) -> Void)
    @objc func pasteboardReporter(_ sender: PasteboardReporter, reportPasteboard: String)
}

// A helper to manage sharing clipboard contents, mostly to do with ensuring the sharing is authorized.
@objc(iTermPasteboardReporter)
class PasteboardReporter: NSObject {
    private static let userDefaultsKey = "NoSyncNeverAllowPaste"
    @objc var delegate: PasteboardReporterDelegate? = nil

    // The int values match tags in prefs.
    @objc(iTermPasteboardReporterConfiguration) enum Configuration: Int {
        case never = 0
        case always = 1
        case askEachTime = 2
    }

    @objc
    static func configuration() -> Configuration {
        if iTermUserDefaults.userDefaults().bool(forKey: Self.userDefaultsKey) {
            return .never
        }
        if SecureUserDefaults.instance.allowPaste.value {
            return .always
        }
        return .askEachTime
    }

    @objc
    static func setConfiguration(_ value: Int) {
        set(configuration: Configuration(rawValue: value)!)
    }

    static func set(configuration: Configuration) {
        switch configuration {
        case .never:
            if Self.removeAuth() {
                iTermUserDefaults.userDefaults().set(true, forKey: Self.userDefaultsKey)
            }

        case .always:
            guard doubleCheck() else {
                return
            }
            do {
                RLog("Set secure user default to true")
                try SecureUserDefaults.instance.allowPaste.set(true)
                DLog("Set user default to false")
                iTermUserDefaults.userDefaults().set(false, forKey: Self.userDefaultsKey)
            } catch {
                RLog("Failed to enable allowPaste: \(error.localizedDescription)")
            }

        case .askEachTime:
            guard Self.removeAuth() else {
                return
            }
            iTermUserDefaults.userDefaults().set(false, forKey: Self.userDefaultsKey)
        }
    }

    private static func removeAuth() -> Bool {
        do {
            try SecureUserDefaults.instance.allowPaste.set(nil)
            return true
        } catch {
            if !SecureUserDefaults.instance.allowPaste.value {
                return true
            }
            failedToDeleteSecureSetting(error)
            return false
        }
    }

    private static func failedToDeleteSecureSetting(_ error: Error) {
        guard let url = SecureUserDefaults.instance.allowPaste.url else {
            // App support doesn't exist, so no problem.
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "PasteboardReporter.ErrorUpdatingSettingsTitle", defaultValue: "Error Updating Settings", comment: "Title of the dialog shown when updating clipboard settings fails")
        alert.informativeText = String(localized: "PasteboardReporter.RemoveAuthFileErrorBody", defaultValue: "An error occurred while removing the file that authorizes clipboard reporting: \(error.localizedDescription).\nAs long as this file exists, clipboard reporting could be enabled by programs running on this computer.", comment: "Error body shown when the clipboard-reporting authorization file cannot be removed")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "PasteboardReporter.RevealInFinder", defaultValue: "Reveal in Finder", comment: "Button that reveals a file in Finder"))
        alert.runModal()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func doubleCheck() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "PasteboardReporter.ConfirmEnableTitle", defaultValue: "Really Enable Clipboard Reporting?", comment: "Title of the confirmation dialog for enabling clipboard reporting")
        alert.informativeText = String(localized: "PasteboardReporter.ConfirmEnableBody", defaultValue: "Reporting the content of the clipboard to apps running inside iTerm2 may expose sensitive information such as passwords. Think carefully before enabling this.", comment: "Warning body shown before enabling clipboard reporting")
        alert.alertStyle = .warning
        let button = alert.addButton(withTitle: iTermLocalizedOK())
        button.hasDestructiveAction = true
        alert.addButton(withTitle: iTermLocalizedCancel())
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc
    func handleRequest(pasteboard: String, completion: @escaping () -> ()) {
        switch Self.configuration() {
        case .never:
            DLog("Pasteboard reporting permanently disallowed")
            completion()
            return
        case .always:
            DLog("Pasteboard reporting permanently allowed")
            delegate?.pasteboardReporter(self, reportPasteboard: pasteboard)
            completion()
            return
        case .askEachTime:
            DLog("Requesting permission for pasteboard reporting")
            ask(pasteboard: pasteboard, completion: completion)
        }
    }

    private func ask(pasteboard: String, completion: @escaping () -> ()) {
        delegate?.pasteboardReporterRequestPermission(self) { [weak self] allowed, permanently in
            RLog("allowed=\(allowed) permanently=\(permanently)")
            if !allowed {
                if permanently {
                    Self.set(configuration: .never)
                }
                completion()
                return
            }

            // allowed
            if permanently {
                Self.set(configuration: .always)
            }
            if let self = self {
                RLog("Requesting pasteboard report be sent")
                self.delegate?.pasteboardReporter(self, reportPasteboard: pasteboard)
            }
            completion()
        }
    }
}

