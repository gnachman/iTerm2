//
//  WindowArrangementNamePrompt.swift
//  iTerm2
//

import AppKit

/// What the user chose in a WindowArrangementNamePrompt.
@objc(iTermWindowArrangementNamePromptResult)
class WindowArrangementNamePromptResult: NSObject {
    /// The name entered, with newlines turned into spaces.
    @objc let name: String
    /// Whether the user chose to save to a file instead of under the name. The
    /// caller shows the save panel, which Swift can't call.
    @objc let wantsExport: Bool
    /// The Spaces checkbox's state, or true when it was not offered.
    @objc let remembersSpaces: Bool

    init(name: String, wantsExport: Bool, remembersSpaces: Bool) {
        self.name = name
        self.wantsExport = wantsExport
        self.remembersSpaces = remembersSpaces
    }
}

/// Asks for the name of a window arrangement being saved, optionally offering to
/// save it to a file instead and whether its windows should reopen on the
/// desktops (Spaces) they are on now.
@objc(iTermWindowArrangementNamePrompt)
class WindowArrangementNamePrompt: NSObject {
    /// The last choice of the Spaces checkbox. A remembered choice, not a setting.
    private static let remembersSpacesKey = "NoSyncSaveArrangementRemembersSpaces"  // Localization unneeded

    /// Shows the prompt modally. Returns nil if the user cancelled.
    @objc(showWithPrompt:defaultName:offerExport:offerSpaces:)
    static func show(prompt: String,
                     defaultName: String,
                     offerExport: Bool,
                     offerSpaces: Bool) -> WindowArrangementNamePromptResult? {
        var actions = [iTermLocalizedOK()]
        var localOnlyLabels = [String]()
        if offerExport {
            let saveToFile = String(localized: "WindowArrangements.SaveToFileButton",
                                    defaultValue: "Save to File with Contents…",
                                    comment: "Button to save a window arrangement to a file including its contents.")
            actions.append(saveToFile)
            // Opens a save panel on the Mac.
            localOnlyLabels.append(saveToFile)
        }
        actions.append(iTermLocalizedCancel())

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = defaultName

        let checkbox: NSButton?
        if offerSpaces && iTermWindowSpace.isAvailable {
            let button = NSButton(checkboxWithTitle: String(localized: "WindowArrangements.RemembersSpacesCheckbox",
                                                            defaultValue: "Reopen windows on the desktops they’re on now",
                                                            comment: "Checkbox when saving a window arrangement. When on, restoring the arrangement moves each window back to the desktop (macOS Space) it was on when saved; when off, windows open on the current desktop."),
                                  target: nil,
                                  action: nil)
            let userDefaults = iTermUserDefaults.userDefaults()
            let remembers = userDefaults.object(forKey: remembersSpacesKey) == nil || userDefaults.bool(forKey: remembersSpacesKey)
            button.state = remembers ? .on : .off
            checkbox = button
        } else {
            checkbox = nil
        }

        let warning = iTermWarning()
        warning.heading = prompt
        warning.title = ""
        warning.actionLabels = actions
        warning.notOfferedRemotelyLabels = localOnlyLabels.isEmpty ? nil : localOnlyLabels
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent
        warning.accessory = checkbox.map { accessory(input: input, checkbox: $0) } ?? input
        warning.remoteInputs = [.textInput(withIdentifier: "name",  // Localization unneeded
                                           label: nil,
                                           textField: input)]
        warning.remoteCheckbox = checkbox
        warning.initialFirstResponder = input
        let selection = warning.runModal()

        let remembersSpaces = checkbox.map { $0.state == .on } ?? true
        let okSelection = iTermWarningSelection.kiTermWarningSelection0
        let exportSelection: iTermWarningSelection? = offerExport ? .kiTermWarningSelection1 : nil
        guard selection == okSelection || selection == exportSelection else {
            return nil
        }
        if checkbox != nil {
            iTermUserDefaults.userDefaults().set(remembersSpaces, forKey: remembersSpacesKey)
        }
        input.validateEditing()
        return WindowArrangementNamePromptResult(name: input.stringValue.replacingOccurrences(of: "\n", with: " "),
                                                 wantsExport: selection != okSelection,
                                                 remembersSpaces: remembersSpaces)
    }

    /// The name field above the checkbox. iTermWarning sizes its accessory from
    /// the view's frame, and a stack view laid out by constraints has none until
    /// it is in a window, so it goes in a container with a real frame.
    private static func accessory(input: NSTextField, checkbox: NSButton) -> NSView {
        let stack = NSStackView(views: [input, checkbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        input.translatesAutoresizingMaskIntoConstraints = false
        input.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.layoutSubtreeIfNeeded()
        let container = NSView(frame: NSRect(origin: .zero, size: stack.fittingSize))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
