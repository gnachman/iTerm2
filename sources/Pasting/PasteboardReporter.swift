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
        alert.messageText = String(localized: "PasteboardReporter_ErrorUpdatingSettings", defaultValue: "Error Updating Settings", comment: "Alert title in failedToDeleteSecureSetting")
        alert.informativeText = String(format: String(localized: "PasteboardReporter_AnErrorOccurredWhileRemovingTheFile_FORMAT",
                                                      defaultValue: "An error occurred while removing the file that authorizes clipboard reporting: %1$@.\nAs long as this file exists, clipboard reporting could be enabled by programs running on this computer.",
                                                      comment: "Alert explanatory text in failedToDeleteSecureSetting"),
                                       error.localizedDescription)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "PasteboardReporter_RevealInFinder", defaultValue: "Reveal in Finder", comment: "Button title in failedToDeleteSecureSetting"))
        alert.runModal()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func doubleCheck() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "PasteboardReporter_ReallyEnableClipboardReporting", defaultValue: "Really Enable Clipboard Reporting?", comment: "Alert title in doubleCheck")
        alert.informativeText = String(localized: "PasteboardReporter_ReportingTheContentOfTheClipboardTo", defaultValue: "Reporting the content of the clipboard to apps running inside iTerm2 may expose sensitive information such as passwords. Think carefully before enabling this.", comment: "Alert explanatory text in doubleCheck")
        alert.alertStyle = .warning
        let button = alert.addButton(withTitle: String(localized: "COMMON_OK", defaultValue: "OK", comment: "Button that confirms enabling clipboard reporting"))
        button.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Button that cancels enabling clipboard reporting"))
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

