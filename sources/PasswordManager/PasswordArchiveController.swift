//
//  PasswordArchiveController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/12/26.
//

import AppKit
import LocalAuthentication
import UniformTypeIdentifiers

// The user-facing flows for exporting and importing saved passwords: from the password manager
// window, from a .iterm2passwords file opened in Finder, and as part of Export/Import All Settings
// and Data.
@objc(iTermPasswordArchiveController)
class PasswordArchiveController: NSObject {
    private static var contentType: UTType? {
        UTType(filenameExtension: PasswordArchive.fileExtension)
    }

    // MARK: - Password manager window

    @objc(exportPasswordsForBrowser:window:)
    static func exportPasswords(browser: Bool, window: NSWindow?) {
        let scope = PasswordArchiveScope(browser: browser)
        guard scope.keychainIsActive else {
            return
        }
        authenticate(reason: String(localized: "PasswordArchive.ExportAuthReason", defaultValue: "export saved passwords", comment: "Completes the system prompt “iTerm2 is trying to …” shown before exporting passwords")) { ok in
            guard ok else {
                return
            }
            exportPasswordsAfterAuthentication(scope: scope, window: window)
        }
    }

    private static func exportPasswordsAfterAuthentication(scope: PasswordArchiveScope, window: NSWindow?) {
        let entries: [PasswordArchiveEntry]
        do {
            entries = try PasswordArchiveExporter.entries(scopes: [scope], store: KeychainPasswordArchiveStore())
        } catch {
            showError(error, heading: exportProblemHeading, window: window)
            return
        }
        if entries.isEmpty {
            showMessage(String(localized: "PasswordArchive.NothingToExport", defaultValue: "There are no saved passwords to export.", comment: "Shown when the user exports passwords but none are saved"),
                        heading: String(localized: "PasswordArchive.ExportHeading", defaultValue: "Export Passwords", comment: "Heading of dialogs about exporting passwords"),
                        window: window)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType].compactMap { $0 }
        savePanel.nameFieldStringValue = String(localized: "PasswordArchive.DefaultFileName", defaultValue: "iTerm2 Passwords.iterm2passwords", comment: "Default file name when exporting passwords. Keep the .iterm2passwords extension.")
        savePanel.title = String(localized: "PasswordArchive.ExportPanelTitle", defaultValue: "Export Passwords", comment: "Title of the save panel for exporting passwords")
        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }
        guard let passphrase = promptForNewPassphrase(window: window) else {
            return
        }
        do {
            try PasswordArchive.write(entries, to: url, passphrase: passphrase)
        } catch {
            showError(error, heading: exportProblemHeading, window: window)
        }
    }

    @objc(importPasswordsWithWindow:completion:)
    static func importPasswords(window: NSWindow?, completion: (() -> ())?) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [contentType].compactMap { $0 }
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return
        }
        importPasswords(from: url, window: window, completion: completion)
    }

    // Also used when a .iterm2passwords file is opened from Finder.
    @objc(importPasswordsFromURL:window:completion:)
    static func importPasswords(from url: URL, window: NSWindow?, completion: (() -> ())?) {
        guard check(url, window: window) else {
            return
        }
        let scopes = Set(PasswordArchiveScope.usingKeychain)
        if scopes.isEmpty {
            // Don't make the user authenticate and type a passphrase only to import nothing.
            showMessage(String(localized: "PasswordArchive.NoKeychainScope", defaultValue: "Passwords can be imported only into the macOS Keychain password manager. To import them, open the password manager, choose macOS Keychain from its gear menu, and then open this file again.", comment: "Shown when the user opens a passwords file while neither the terminal nor the browser password manager uses the Keychain"),
                        heading: importProblemHeading,
                        window: window)
            return
        }
        authenticate(reason: String(localized: "PasswordArchive.ImportAuthReason", defaultValue: "import saved passwords", comment: "Completes the system prompt “iTerm2 is trying to …” shown before importing passwords")) { ok in
            guard ok else {
                return
            }
            guard let entries = decrypt(url: url, detail: nil, window: window) else {
                return
            }
            if let summary = apply(entries, scopes: scopes, window: window) {
                showSummary(summary, window: window)
            }
            completion?()
        }
    }

    // MARK: - Export/Import All Settings and Data

    // The checkbox for the export save panel's accessory view, or nil if no passwords can be
    // exported. Off by default and never remembered, because what it exports is so sensitive.
    static func makeIncludePasswordsCheckbox() -> NSButton? {
        if PasswordArchiveScope.usingKeychain.isEmpty {
            return nil
        }
        let checkbox = NSButton(checkboxWithTitle: String(localized: "PasswordArchive.IncludePasswordsCheckbox", defaultValue: "Include saved passwords (encrypted with a passphrase)", comment: "Checkbox in the Export All Settings and Data save panel"),
                                target: nil,
                                action: nil)
        checkbox.state = .off
        return checkbox
    }

    // Authenticates, reads the exportable passwords, and asks for a passphrase. The completion
    // receives nil if the user cancelled or something failed (and was reported).
    static func preparePasswordsForSettingsExport(window: NSWindow?,
                                                  completion: @escaping ((entries: [PasswordArchiveEntry], passphrase: String)?) -> ()) {
        authenticate(reason: String(localized: "PasswordArchive.ExportAuthReason", defaultValue: "export saved passwords", comment: "Completes the system prompt “iTerm2 is trying to …” shown before exporting passwords")) { ok in
            guard ok else {
                completion(nil)
                return
            }
            do {
                let entries = try PasswordArchiveExporter.entries(scopes: PasswordArchiveScope.usingKeychain,
                                                                  store: KeychainPasswordArchiveStore())
                guard let passphrase = promptForNewPassphrase(window: window) else {
                    completion(nil)
                    return
                }
                completion((entries, passphrase))
            } catch {
                showError(error, heading: exportProblemHeading, window: window)
                completion(nil)
            }
        }
    }

    // Called synchronously while importing settings. Authenticates like the other import paths:
    // the passphrase only proves the user may read the file, and the import reads and replaces
    // saved passwords. Failing or cancelling either step skips the passwords but not the other
    // settings.
    static func importPasswordsDuringSettingsImport(from url: URL) {
        guard check(url, window: nil) else {
            return
        }
        guard authenticateSynchronously(reason: String(localized: "PasswordArchive.ImportAuthReason", defaultValue: "import saved passwords", comment: "Completes the system prompt “iTerm2 is trying to …” shown before importing passwords")) else {
            return
        }
        let detail = String(localized: "PasswordArchive.SettingsImportDetail", defaultValue: "This export includes saved passwords. Enter the passphrase that was used to export them, or cancel to import everything else without them.", comment: "Shown when importing settings that contain an encrypted password export")
        guard let entries = decrypt(url: url, detail: detail, window: nil) else {
            return
        }
        // Import every scope in the file, whatever this Mac uses now. The export holds only scopes
        // that used the Keychain on the Mac that made it, and the settings imported next will
        // select the Keychain for them.
        if let summary = apply(entries, scopes: Set(PasswordArchiveScope.allCases), window: nil) {
            showSummary(summary, window: nil)
        }
    }

    // MARK: - Shared steps

    private static var exportProblemHeading: String {
        String(localized: "PasswordArchive.ExportProblemHeading", defaultValue: "Problem Exporting Passwords", comment: "Heading of the alert shown when exporting passwords fails")
    }

    private static var importProblemHeading: String {
        String(localized: "PasswordArchive.ImportProblemHeading", defaultValue: "Problem Importing Passwords", comment: "Heading of the alert shown when importing passwords fails")
    }

    // Always asks, even when the password manager is open or doesn't require authentication,
    // because an export hands every password to whoever chooses the passphrase.
    private static func authenticate(reason: String, completion: @escaping (Bool) -> ()) {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthentication
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            RLog("Can't evaluate \(policy): \(error?.localizedDescription ?? "(nil)")")
            if error?.code == LAError.passcodeNotSet.rawValue {
                // With no login password there is no secret to check, and anyone at this Mac can
                // already read the unlocked login keychain. The file's passphrase still protects
                // the export.
                completion(true)
                return
            }
            let reason = error?.localizedDescription ?? ""
            showMessage(String(localized: "PasswordArchive.AuthUnavailable", defaultValue: "iTerm2 can’t export or import passwords because macOS couldn’t confirm your identity. \(reason)", comment: "Shown when macOS can't authenticate the user before a password import or export. The placeholder is the system's reason."),
                        heading: String(localized: "PasswordArchive.AuthFailedHeading", defaultValue: "Authentication Failed", comment: "Heading of the alert shown when the user can't be authenticated before a password import or export"),
                        window: nil)
            completion(false)
            return
        }
        iTermApplication.shared().localAuthenticationDialogOpen = true
        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            RLog("Password archive authentication success=\(success) error=\(String(describing: error))")
            DispatchQueue.main.async {
                iTermApplication.shared().localAuthenticationDialogOpen = false
                completion(success)
            }
        }
    }

    // For callers that can't continue asynchronously. Runs the main run loop until the system
    // prompt is answered.
    private static func authenticateSynchronously(reason: String) -> Bool {
        var result: Bool?
        authenticate(reason: reason) { ok in
            result = ok
        }
        while result == nil {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
        return result!
    }

    // Asks for a passphrase twice. Returns nil if the user cancels.
    private static func promptForNewPassphrase(window: NSWindow?) -> String? {
        var detail = String(localized: "PasswordArchive.NewPassphraseDetail", defaultValue: "The exported passwords will be encrypted. You will need this passphrase to import them.", comment: "Explanation under the prompt for a passphrase when exporting passwords")
        while true {
            let alert = ModalPasswordAlert(String(localized: "PasswordArchive.NewPassphrasePrompt", defaultValue: "Choose a passphrase", comment: "Prompt for the passphrase that will encrypt exported passwords"))
            alert.detail = detail
            alert.showConfirmationField = true
            alert.remotelyAnswerable = false
            guard let passphrase = alert.run(window: window) else {
                return nil
            }
            if passphrase.isEmpty {
                detail = String(localized: "PasswordArchive.EmptyPassphrase", defaultValue: "The passphrase can’t be empty.", comment: "Shown when the user enters an empty passphrase for exported passwords")
            } else if passphrase != alert.confirmation {
                detail = String(localized: "PasswordArchive.PassphraseMismatch", defaultValue: "The passphrases don’t match. Try again.", comment: "Shown when the two passphrases typed for exported passwords differ")
            } else {
                return passphrase
            }
        }
    }

    // Reports and returns false if the file isn't a passwords file, before any prompts.
    private static func check(_ url: URL, window: NSWindow?) -> Bool {
        do {
            try PasswordArchive.check(url)
            return true
        } catch {
            showError(error, heading: importProblemHeading, window: window)
            return false
        }
    }

    // Asks for the passphrase until the file decrypts. Returns nil if the user cancels or the file
    // can't be read (which is reported).
    private static func decrypt(url: URL, detail initialDetail: String?, window: NSWindow?) -> [PasswordArchiveEntry]? {
        var detail = initialDetail
        while true {
            let alert = ModalPasswordAlert(String(localized: "PasswordArchive.PassphrasePrompt", defaultValue: "Enter the passphrase for the passwords file", comment: "Prompt for the passphrase when importing exported passwords"))
            alert.detail = detail
            alert.remotelyAnswerable = false
            guard let passphrase = alert.run(window: window) else {
                return nil
            }
            do {
                return try PasswordArchive.read(from: url, passphrase: passphrase)
            } catch PasswordArchiveError.wrongPassphraseOrDamaged {
                // Keep the initial explanation, which may say what Cancel does.
                detail = [PasswordArchiveError.wrongPassphraseOrDamaged.localizedDescription,
                          initialDetail].compactMap { $0 }.joined(separator: "\n\n")
            } catch {
                showError(error, heading: importProblemHeading, window: window)
                return nil
            }
        }
    }

    // Returns nil if the import failed (which is reported).
    // Entries for scopes not in `scopes` are counted as not imported.
    private static func apply(_ entries: [PasswordArchiveEntry],
                              scopes: Set<PasswordArchiveScope>,
                              window: NSWindow?) -> PasswordArchiveImporter.Summary? {
        let importer = PasswordArchiveImporter(store: KeychainPasswordArchiveStore(),
                                               scopesUsingKeychain: scopes)
        defer {
            // Even a failed or canceled import may have changed some entries.
            NotificationCenter.default.post(name: NSNotification.Name(kPasswordManagersShouldReloadData), object: nil)
        }
        do {
            return try importer.run(entries) { entry in
                askAboutConflict(entry, window: window)
            }
        } catch {
            showError(error, heading: importProblemHeading, window: window)
            return nil
        }
    }

    private static func askAboutConflict(_ entry: PasswordArchiveEntry,
                                         window: NSWindow?) -> PasswordArchiveImporter.ConflictDecision {
        let title: String
        if entry.userName.isEmpty {
            title = String(localized: "PasswordArchive.ConflictNoUser", defaultValue: "A saved password for “\(entry.accountName)” already exists. Replace it with the imported one?", comment: "Asked when an imported password matches a saved one that has no user name; the placeholder is the account name")
        } else {
            title = String(localized: "PasswordArchive.Conflict", defaultValue: "A saved password for “\(entry.accountName)” with user name “\(entry.userName)” already exists. Replace it with the imported one?", comment: "Asked when an imported password matches a saved one; the placeholders are the account name and the user name")
        }
        let decisions: [PasswordArchiveImporter.ConflictDecision] = [.replace, .skip, .alwaysReplace, .neverReplace, .cancel]
        let selection = iTermWarning.show(
            withTitle: title,
            actions: [String(localized: "PasswordArchive.ReplaceAction", defaultValue: "Replace", comment: "Button that replaces a saved password with an imported one"),
                      String(localized: "PasswordArchive.DontReplaceAction", defaultValue: "Don’t Replace", comment: "Button that keeps a saved password instead of the imported one"),
                      String(localized: "PasswordArchive.AlwaysReplaceAction", defaultValue: "Always Replace", comment: "Button that replaces this and every later conflicting password during an import"),
                      String(localized: "PasswordArchive.NeverReplaceAction", defaultValue: "Never Replace", comment: "Button that keeps this and every later conflicting saved password during an import"),
                      iTermLocalizedCancel()],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: String(localized: "PasswordArchive.ConflictHeading", defaultValue: "Password Already Saved", comment: "Heading of the dialog asked when an imported password matches a saved one"),
            window: window)
        let index = Int(selection.rawValue)
        return decisions.indices.contains(index) ? decisions[index] : .cancel
    }

    private static func showSummary(_ summary: PasswordArchiveImporter.Summary, window: NSWindow?) {
        var counts = String(localized: "PasswordArchive.Summary", defaultValue: "Added: \(summary.added)\nReplaced: \(summary.replaced)\nKept existing: \(summary.skipped)", comment: "Summary after importing passwords. Each line is a label and a count.")
        if summary.unchanged > 0 {
            counts += "\n" + String(localized: "PasswordArchive.SummaryUnchanged", defaultValue: "Already saved: \(summary.unchanged)", comment: "Line in the password import summary: a label and the number of imported entries whose password was already saved unchanged")
        }
        if summary.notImported > 0 {
            counts += "\n" + String(localized: "PasswordArchive.SummaryNotImported", defaultValue: "Not imported because that password manager doesn’t use the Keychain: \(summary.notImported)", comment: "Line in the password import summary: a label and the number of entries skipped because the terminal or browser password manager is set to something other than the Keychain")
        }
        let message: String
        if let failure = summary.failure {
            message = String(localized: "PasswordArchive.SummaryFailed", defaultValue: "The import stopped because of an error. Passwords imported before the error were kept.\n\n\(failure)", comment: "Shown above the import summary when importing passwords failed partway through. The placeholder is the error message.") + "\n\n" + counts
            showMessage(message, heading: importProblemHeading, window: window)
            return
        }
        if summary.cancelled {
            message = String(localized: "PasswordArchive.SummaryCancelled", defaultValue: "The import was canceled. Passwords imported before canceling were kept.", comment: "Shown above the import summary when the user canceled partway through") + "\n\n" + counts
        } else {
            message = counts
        }
        showMessage(message,
                    heading: String(localized: "PasswordArchive.ImportCompleteHeading", defaultValue: "Passwords Imported", comment: "Heading of the alert shown after importing passwords"),
                    window: window)
    }

    private static func showError(_ error: Error, heading: String, window: NSWindow?) {
        showMessage(error.localizedDescription, heading: heading, window: window)
    }

    private static func showMessage(_ message: String, heading: String, window: NSWindow?) {
        _ = iTermWarning.show(withTitle: message,
                              actions: [iTermLocalizedOK()],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: heading,
                              window: window)
    }
}
