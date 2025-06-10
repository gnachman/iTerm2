//
//  SSHFolderDialog.swift
//  iTerm2
//
//  Created by George Nachman on 6/9/25.
//

import Cocoa

class SSHFolderDialog: NSObject {

    // MARK: - Properties

    private let alert: NSAlert
    private let textField: SSHFolderDialogTextField
    private var completionsWindow: CompletionsWindow?
    private var currentCompletionTask: Task<Void, Never>?
    private var textFieldDelegate: TextFieldDelegate?
    private var pendingCompletionText: String?
    private let hostname: String

    // Callbacks
    private let completionsProvider: (String) async -> [String]
    private let onNavigate: (String) -> Void

    // MARK: - Initialization

    init(currentPath: String?,
         hostname: String,
         completionsProvider: @escaping (String) async -> [String],
         onNavigate: @escaping (String) -> Void) {

        self.completionsProvider = completionsProvider
        self.onNavigate = onNavigate
        self.hostname = hostname

        // Initialize alert
        self.alert = NSAlert()
        alert.messageText = "Go to the folder:"
        alert.informativeText = "Type a pathname or select from the pop-up menu"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        // Initialize text field
        self.textField = SSHFolderDialogTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = currentPath ?? ""
        textField.placeholderString = "Enter path (e.g., /usr/local/bin)"

        super.init()

        setupUI()
    }

    // MARK: - Public Methods

    @discardableResult
    func runModal() -> Bool {
        // Set the text field as first responder
        DispatchQueue.main.async { [weak self] in
            _ = self?.textField.becomeFirstResponder()
            self?.textField.selectText(nil)
        }

        let response = alert.runModal()

        // Clean up
        closeCompletions()
        currentCompletionTask?.cancel()

        if response == .alertFirstButtonReturn {
            let enteredPath = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !enteredPath.isEmpty {
                onNavigate(enteredPath)
                return true
            }
        }

        return false
    }

    // MARK: - Private Methods

    private func setupUI() {
        // Create container view for text field with proper margins
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        containerView.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: 300),
            textField.heightAnchor.constraint(equalToConstant: 24)
        ])
        alert.accessoryView = containerView

        // Set up text field delegate
        textFieldDelegate = TextFieldDelegate(
            onTextChange: { [weak self] text in
                self?.handleTextChange(text)
            },
            onReturn: { },
            onEscape: { }
        )
        textField.delegate = textFieldDelegate
    }

    private func handleTextChange(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            showCompletions(basePath: trimmedText)
        } else {
            closeCompletions()
        }
    }

    private func closeCompletions() {
        if let window = completionsWindow {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            completionsWindow = nil
        }
        pendingCompletionText = nil
    }

    // Accept the suggestion but don't update completions window
    private func provisionallyAcceptSuggestion() {
        if let baseSuggestion = completionsWindow?.selectedItem?.suggestion {
            let suggestion = String(baseSuggestion.removing(suffix: "/") + "/")
            textField.stringValue = suggestion
        }
    }

    private func acceptSuggestion() {
        if let baseSuggestion = completionsWindow?.selectedItem?.suggestion {
            let suggestion = String(baseSuggestion.removing(suffix: "/") + "/")
            textField.stringValue = suggestion
            handleTextChange(suggestion)
        }
    }

    private func showCompletions(basePath: String) {
        // Cancel any existing completion task
        currentCompletionTask?.cancel()

        // Store the text that triggered this completion request
        pendingCompletionText = basePath

        // Get text field position in window coordinates
        guard let textFieldSuperview = textField.superview else {
            return
        }

        let textFieldFrame = alert.window.convertToScreen(textFieldSuperview.convert(textField.bounds, to: nil))

        // Create or update completions window
        if completionsWindow == nil {
            completionsWindow = CompletionsWindow(
                parent: alert.window,
                location: textFieldFrame,
                mode: .indicator,
                placeholder: "Loading completions...",
                allowKey: false
            )
            textField.onSpecialKey = { [weak completionsWindow, weak self] key in
                switch key {
                case .up:
                    completionsWindow?.up()
                    self?.provisionallyAcceptSuggestion()
                case .down:
                    completionsWindow?.down()
                    self?.provisionallyAcceptSuggestion()
                case .tab:
                    self?.acceptSuggestion()
                }
                return true
            }
        }

        // Start async task to fetch completions
        currentCompletionTask = Task { [weak self] in
            let suggestions = await self?.completionsProvider(basePath) ?? []

            // Check if task was cancelled
            if Task.isCancelled {
                return
            }

            // Check if the text field content has changed since we started
            await MainActor.run { [weak self] in
                guard let self = self else { return }

                let currentText = self.textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

                // Only apply completions if the text hasn't changed
                if currentText == basePath && self.pendingCompletionText == basePath {
                    // Convert to CompletionsWindow items
                    let items = suggestions.map { path in
                        let isDirectory = path.hasSuffix("/")
                        let displayPath = path
                        let detail = "Folder on " + hostname

                        return CompletionsWindow.Item(
                            suggestion: path,
                            attributedString: NSAttributedString(string: displayPath),
                            detail: NSAttributedString(string: detail),
                            kind: isDirectory ? .folder : .file
                        )
                    }

                    // Update completions window
                    if !items.isEmpty {
                        self.completionsWindow?.switchMode(to: .completions(items: items))
                    } else {
                        self.closeCompletions()
                    }
                } else {
                    // Text changed while we were fetching, ignore these completions
                    // The new text should have already triggered a new completion request
                }
            }
        }
    }

    // MARK: - Text Field Delegate

    private class TextFieldDelegate: NSObject, NSTextFieldDelegate {
        let onTextChange: (String) -> Void
        let onReturn: () -> Void
        let onEscape: () -> Void

        init(onTextChange: @escaping (String) -> Void,
             onReturn: @escaping () -> Void,
             onEscape: @escaping () -> Void) {
            self.onTextChange = onTextChange
            self.onReturn = onReturn
            self.onEscape = onEscape
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            onTextChange(textField.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onReturn()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onEscape()
                return true
            }
            return false
        }
    }
}
