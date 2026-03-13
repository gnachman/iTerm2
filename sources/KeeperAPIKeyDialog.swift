//
//  KeeperAPIKeyDialog.swift
//  iTerm2SharedARC
//
//  Presents the Keeper Security API Key alert (sheet or modal). Extracted so KeeperDataSource can achieve full unit test coverage by mocking the dialog.
//

import AppKit

/// Presents the API key alert UI. Called from keeperShowAPIKeyDialog in KeeperDataSource when test override is not set.
func keeperShowAPIKeyDialogUI(existingKey: String?, window: NSWindow?, completion: @escaping (KeeperAPIKeyPromptResult?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Keeper Security API Key"
    if let existing = existingKey, !existing.isEmpty {
        alert.informativeText = "An API key is already stored (protected by Touch ID, Face ID, or device passcode when available). To update it, enter a new key below and choose Update. To continue with the stored key, choose Use Existing."
        alert.addButton(withTitle: "Use Existing")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
    } else {
        alert.informativeText = "Enter your Keeper Commander API key. The key is stored in macOS Keychain and protected by Touch ID, Face ID, or device passcode when available. If you have stored a key before, enter or paste it again to use or update it."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
    }
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
    field.placeholderString = (existingKey?.isEmpty ?? true) ? "Enter Keeper Commander service API key" : "API Key"
    field.stringValue = existingKey ?? ""
    alert.accessoryView = field
    let sheetWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow
    if let window = sheetWindow, window.isVisible {
        alert.beginSheetModal(for: window) { response in
            let result: KeeperAPIKeyPromptResult?
            if response == .alertFirstButtonReturn {
                if existingKey != nil, !(existingKey?.isEmpty ?? true) {
                    result = .useExisting
                } else {
                    result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else if response == .alertSecondButtonReturn, existingKey != nil, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                result = .cancel
            }
            completion(result)
        }
    } else {
        let response = alert.runModal()
        let result: KeeperAPIKeyPromptResult?
        if response == .alertFirstButtonReturn {
            if existingKey != nil, !(existingKey?.isEmpty ?? true) {
                result = .useExisting
            } else {
                result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } else if response == .alertSecondButtonReturn, existingKey != nil, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = .useNew(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            result = .cancel
        }
        completion(result)
    }
}
