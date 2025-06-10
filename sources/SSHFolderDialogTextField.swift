//
//  SSHFolderDialogTextField.swift
//  iTerm2
//
//  Created by George Nachman on 6/9/25.
//

import Cocoa

class SSHFolderDialogTextField: NSTextField {

    // MARK: - Properties

    /// Callback for handling special key events
    var onSpecialKey: ((SpecialKey) -> Bool)?

    enum SpecialKey {
        case up
        case down
        case tab
    }

    // MARK: - Field Editor

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Set ourselves as the field editor's delegate to intercept commands
            if let fieldEditor = self.currentEditor() as? NSTextView {
                fieldEditor.delegate = self
            }
        }
        return result
    }
}

// MARK: - NSTextViewDelegate

extension SSHFolderDialogTextField: NSTextViewDelegate {

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if onSpecialKey?(.tab) == true {
                return true
            }
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if onSpecialKey?(.down) == true {
                return true
            }
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if onSpecialKey?(.up) == true {
                return true
            }
        }
        // Return false to allow normal processing
        return false
    }
}
