//
//  iTermEventTriggerParameterView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/1/26.
//

import AppKit

/// View for configuring event-specific trigger parameters
@objc(iTermEventTriggerParameterView)
class EventTriggerParameterView: NSView, NSTextFieldDelegate {

    // MARK: - Properties

    private var stackView: NSStackView!
    private var currentMatchType: iTermTriggerMatchType = .eventPromptDetected

    /// The current event parameters
    @objc var eventParams: [String: Any] {
        get {
            return collectParams()
        }
        set {
            applyParams(newValue)
        }
    }

    /// Callback when parameters change
    @objc var onParametersChanged: (() -> Void)?

    // UI elements for different event types
    private var exitCodeFilterPopup: NSPopUpButton?
    private var exitCodeTextField: NSTextField?
    private var timeoutTextField: NSTextField?
    private var thresholdTextField: NSTextField?
    private var sequenceIdTextField: NSTextField?
    private var directoryRegexTextField: NSTextField?
    private var hostRegexTextField: NSTextField?
    private var userRegexTextField: NSTextField?
    private var commandRegexTextField: NSTextField?
    private var notificationMessageRegexTextField: NSTextField?
    private var progressBarFilterPopup: NSPopUpButton?
    private var jobNameTextField: NSTextField?
    private var variableNameTextField: NSTextField?
    private var variableValueRegexTextField: NSTextField?

    // Completion support for the variable-name field. Mirrors the auto-
    // complete behavior of iTermFunctionCallTextFieldDelegate but for a bare
    // variable path (not an interpolated string).
    private let variablePathSource = iTermVariableHistory.pathSource(for: .session)
    private var isAutocompleting = false
    private var suppressAutocomplete = false

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Make sure we don't expand beyond our content
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    override var intrinsicContentSize: NSSize {
        return stackView.fittingSize
    }

    override var firstBaselineAnchor: NSLayoutYAxisAnchor {
        // Return the first baseline of the stackView, which will be the first row's baseline
        return stackView.firstBaselineAnchor
    }

    // MARK: - Public Methods

    /// Configure the view for a specific event type
    @objc func configure(forMatchType matchType: iTermTriggerMatchType) {
        currentMatchType = matchType

        // Clear existing views
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Reset UI element references
        exitCodeFilterPopup = nil
        exitCodeTextField = nil
        timeoutTextField = nil
        thresholdTextField = nil
        sequenceIdTextField = nil
        directoryRegexTextField = nil
        hostRegexTextField = nil
        userRegexTextField = nil
        commandRegexTextField = nil
        notificationMessageRegexTextField = nil
        progressBarFilterPopup = nil
        jobNameTextField = nil
        variableNameTextField = nil
        variableValueRegexTextField = nil

        // Add appropriate UI for this event type
        switch matchType {
        case .eventCommandFinished:
            addExitCodeFilterUI()
        case .eventDirectoryChanged:
            addDirectoryRegexUI()
        case .eventHostChanged:
            addHostRegexUI()
        case .eventUserChanged:
            addUserRegexUI()
        case .eventIdle, .eventActivityAfterIdle:
            addTimeoutUI()
        case .eventLongRunningCommand:
            addLongRunningCommandUI()
        case .eventCustomEscapeSequence:
            addSequenceIdUI()
        case .eventNotificationPosted:
            addNotificationMessageRegexUI()
        case .eventProgressBarChanged:
            addProgressBarFilterUI()
        case .eventJobStarted, .eventJobEnded:
            addJobNameUI()
        case .eventVariableChanged:
            addVariableChangedUI()
        default:
            // No parameters needed for other event types
            addNoParametersLabel()
        }

        // Tell the layout system our size changed
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    // MARK: - UI Construction

    private func addExitCodeFilterUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.ExitCode", defaultValue: "Exit Code:", comment: "Field label for the exit code filter selector"))

        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: [String(localized: "EventTrigger.ExitCodeFilter.Any", defaultValue: "Any", comment: "Exit code filter option: any exit code"), String(localized: "EventTrigger.ExitCodeFilter.Zero", defaultValue: "Zero (Success)", comment: "Exit code filter option: zero (success)"), String(localized: "EventTrigger.ExitCodeFilter.NonZero", defaultValue: "Non-Zero (Failure)", comment: "Exit code filter option: non-zero (failure)"), String(localized: "EventTrigger.ExitCodeFilter.Specific", defaultValue: "Specific Value…", comment: "Exit code filter option: a specific value")])
        popup.target = self
        popup.action = #selector(exitCodeFilterChanged(_:))
        exitCodeFilterPopup = popup

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = String(localized: "EventTrigger.Placeholder.ExitCode", defaultValue: "Exit code", comment: "Placeholder for the specific exit code input")
        textField.isHidden = true
        textField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        textField.delegate = self
        textField.formatter = iTermSaneNumberFormatter()
        exitCodeTextField = textField

        row.addArrangedSubview(popup)
        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)
    }

    private func addJobNameUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.Job", defaultValue: "Job:", comment: "Field label for the job name input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = "claude"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        jobNameTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.JobName", defaultValue: "Process name to match in the foreground-job ancestry chain (case-insensitive)", comment: "Help text for the job name field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addVariableChangedUI() {
        // Variable name row (with completion).
        let nameRow = createRow(label: String(localized: "EventTrigger.Field.Variable", defaultValue: "Variable:", comment: "Field label for the variable name input"))

        let nameField = NSTextField()
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.placeholderString = "user.myVar"
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        nameField.delegate = self
        variableNameTextField = nameField

        nameRow.addArrangedSubview(nameField)
        stackView.addArrangedSubview(nameRow)

        let nameHelp = NSTextField(labelWithString: String(localized: "EventTrigger.Help.VariableName", defaultValue: "Name of the session variable to watch", comment: "Help text for the variable name field"))
        nameHelp.translatesAutoresizingMaskIntoConstraints = false
        nameHelp.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        nameHelp.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(nameHelp)

        // Value regex row.
        let valueRow = createRow(label: String(localized: "EventTrigger.Field.Value", defaultValue: "Value:", comment: "Field label for the variable value regex input"))

        let valueField = NSTextField()
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.placeholderString = ".*"
        valueField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        valueField.delegate = self
        variableValueRegexTextField = valueField

        valueRow.addArrangedSubview(valueField)
        stackView.addArrangedSubview(valueRow)

        let valueHelp = NSTextField(labelWithString: String(localized: "EventTrigger.Help.VariableValueRegex", defaultValue: "Regular expression the new value must match (leave blank to match any change)", comment: "Help text for the variable value regex field"))
        valueHelp.translatesAutoresizingMaskIntoConstraints = false
        valueHelp.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        valueHelp.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(valueHelp)
    }

    private func addDirectoryRegexUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.Directory", defaultValue: "Directory:", comment: "Field label for the directory regex input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        directoryRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.DirectoryRegex", defaultValue: "Regular expression to match the directory path", comment: "Help text for the directory path regex field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addTimeoutUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.Timeout", defaultValue: "Timeout:", comment: "Field label for the idle-timeout input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = "30"
        textField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        textField.delegate = self
        textField.formatter = iTermSaneNumberFormatter()
        timeoutTextField = textField

        let unitsLabel = NSTextField(labelWithString: String(localized: "EventTrigger.SecondsUnit", defaultValue: "seconds", comment: "Units label for a duration field, in seconds"))
        unitsLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(textField)
        row.addArrangedSubview(unitsLabel)
        stackView.addArrangedSubview(row)
    }

    private func addSequenceIdUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.SequenceId", defaultValue: "Sequence ID:", comment: "Field label for the custom escape sequence identifier input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        sequenceIdTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.SequenceIdRegex", defaultValue: "Regular expression to match the sequence identifier", comment: "Help text for the sequence identifier regex field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addNotificationMessageRegexUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.Message", defaultValue: "Message:", comment: "Field label for the notification message regex input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        notificationMessageRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.NotificationRegex", defaultValue: "Regular expression to match the notification message", comment: "Help text for the notification message regex field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addHostRegexUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.Host", defaultValue: "Host:", comment: "Field label for the host regex input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        hostRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.HostRegex", defaultValue: "Regular expression to match the hostname", comment: "Help text for the hostname regex field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addUserRegexUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.User", defaultValue: "User:", comment: "Field label for the user regex input"))

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        userRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.UserRegex", defaultValue: "Regular expression to match the username", comment: "Help text for the username regex field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addLongRunningCommandUI() {
        // Threshold row
        let thresholdRow = createRow(label: String(localized: "EventTrigger.Field.Threshold", defaultValue: "Threshold:", comment: "Field label for the long-running-command threshold input"))

        let thresholdField = NSTextField()
        thresholdField.translatesAutoresizingMaskIntoConstraints = false
        thresholdField.placeholderString = "60"
        thresholdField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        thresholdField.delegate = self
        thresholdField.formatter = iTermSaneNumberFormatter()
        thresholdTextField = thresholdField

        let unitsLabel = NSTextField(labelWithString: String(localized: "EventTrigger.SecondsUnit", defaultValue: "seconds", comment: "Units label for a duration field, in seconds"))
        unitsLabel.translatesAutoresizingMaskIntoConstraints = false

        thresholdRow.addArrangedSubview(thresholdField)
        thresholdRow.addArrangedSubview(unitsLabel)
        stackView.addArrangedSubview(thresholdRow)

        // Command regex row
        let commandRow = createRow(label: String(localized: "EventTrigger.Field.Command", defaultValue: "Command:", comment: "Field label for the command regex input"))

        let commandField = NSTextField()
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.placeholderString = ".*"
        commandField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        commandField.delegate = self
        commandRegexTextField = commandField

        commandRow.addArrangedSubview(commandField)
        stackView.addArrangedSubview(commandRow)

        let helpLabel = NSTextField(labelWithString: String(localized: "EventTrigger.Help.CommandRegex", defaultValue: "Regular expression to match the command line", comment: "Help text for the command regex field"))
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addProgressBarFilterUI() {
        let row = createRow(label: String(localized: "EventTrigger.Field.FireWhen", defaultValue: "Fire When:", comment: "Field label for the progress-bar trigger fire-when selector"))

        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: [String(localized: "EventTrigger.ProgressBarFilter.Either", defaultValue: "Appears or Disappears", comment: "Progress-bar trigger fire-when option: either appears or disappears"), String(localized: "EventTrigger.ProgressBarFilter.Appears", defaultValue: "Appears", comment: "Progress-bar trigger fire-when option: appears"), String(localized: "EventTrigger.ProgressBarFilter.Disappears", defaultValue: "Disappears", comment: "Progress-bar trigger fire-when option: disappears")])
        popup.target = self
        popup.action = #selector(progressBarFilterChanged(_:))
        progressBarFilterPopup = popup

        row.addArrangedSubview(popup)
        stackView.addArrangedSubview(row)
    }

    private func addNoParametersLabel() {
        let label = NSTextField(labelWithString: String(localized: "EventTrigger.NoParameters", defaultValue: "No additional parameters required.", comment: "Shown when an event trigger has no configurable parameters"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(label)
    }

    private func createRow(label: String) -> NSStackView {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 6

        let labelView = NSTextField(labelWithString: label)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        labelView.alignment = .right
        row.addArrangedSubview(labelView)

        return row
    }

    // MARK: - Actions

    @objc private func exitCodeFilterChanged(_ sender: NSPopUpButton) {
        let isSpecific = sender.indexOfSelectedItem == 3
        exitCodeTextField?.isHidden = !isSpecific
        onParametersChanged?()
    }

    @objc private func progressBarFilterChanged(_ sender: NSPopUpButton) {
        onParametersChanged?()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        // Filter non-digit characters from numeric fields
        if let textField = obj.object as? NSTextField {
            if textField === exitCodeTextField ||
               textField === timeoutTextField ||
               textField === thresholdTextField {
                let digitsOnly = textField.stringValue.filter { $0.isNumber }
                if digitsOnly != textField.stringValue {
                    textField.stringValue = digitsOnly
                }
            } else if textField === variableNameTextField,
                      let fieldEditor = obj.userInfo?["NSFieldEditor"] as? NSTextView {
                // Offer variable-name completions as the user types, but not
                // while deleting (it's disruptive to re-suggest on backspace).
                if !isAutocompleting && !suppressAutocomplete {
                    isAutocompleting = true
                    fieldEditor.complete(nil)
                    isAutocompleting = false
                }
                suppressAutocomplete = false
            }
        }
        onParametersChanged?()
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 completions words: [String],
                 forPartialWordRange charRange: NSRange,
                 indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        guard control === variableNameTextField else {
            return words
        }
        // Don't preselect; preselection causes pathological behavior when
        // typing a period.
        index.pointee = -1

        let full = textView.string as NSString
        // We can't sensibly complete in the middle of the value.
        guard NSMaxRange(charRange) == full.length else {
            return []
        }
        // pathSource wants the full path typed so far (including any leading
        // components like "user."), not just the partial word after the last
        // dot, which is what charRange covers.
        let typed = full.substring(to: NSMaxRange(charRange))
        let matches = variablePathSource(typed)
        let completions = matches.map { (path: String) -> String in
            (path as NSString).substring(from: charRange.location)
        }
        return completions.sorted()
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if control === variableNameTextField &&
            (commandSelector == #selector(NSResponder.deleteBackward(_:)) ||
             commandSelector == #selector(NSResponder.deleteForward(_:)) ||
             commandSelector == #selector(NSResponder.deleteWordBackward(_:)) ||
             commandSelector == #selector(NSResponder.deleteWordForward(_:))) {
            suppressAutocomplete = true
        }
        return false
    }

    // MARK: - Parameter Collection

    private func collectParams() -> [String: Any] {
        var params: [String: Any] = [:]

        switch currentMatchType {
        case .eventCommandFinished:
            if let popup = exitCodeFilterPopup {
                switch popup.indexOfSelectedItem {
                case 0:
                    params["exitCodeFilter"] = "*"
                case 1:
                    params["exitCodeFilter"] = "0"
                case 2:
                    params["exitCodeFilter"] = "!0"
                case 3:
                    params["exitCodeFilter"] = exitCodeTextField?.stringValue ?? "*"
                default:
                    params["exitCodeFilter"] = "*"
                }
            }

        case .eventIdle, .eventActivityAfterIdle:
            if let text = timeoutTextField?.stringValue, let timeout = Double(text) {
                params["timeout"] = NSNumber(value: timeout)
            } else {
                params["timeout"] = NSNumber(value: 30.0)
            }

        case .eventLongRunningCommand:
            if let text = thresholdTextField?.stringValue, let threshold = Double(text) {
                params["threshold"] = NSNumber(value: threshold)
            } else {
                params["threshold"] = NSNumber(value: 60.0)
            }
            let commandRegex = commandRegexTextField?.stringValue ?? ""
            if !commandRegex.isEmpty {
                params["commandRegex"] = commandRegex
            }

        case .eventCustomEscapeSequence:
            params["sequenceId"] = sequenceIdTextField?.stringValue ?? ""

        case .eventNotificationPosted:
            let regex = notificationMessageRegexTextField?.stringValue ?? ""
            if !regex.isEmpty {
                params["messageRegex"] = regex
            }

        case .eventDirectoryChanged:
            let regex = directoryRegexTextField?.stringValue ?? ""
            if !regex.isEmpty {
                params["directoryRegex"] = regex
            }

        case .eventHostChanged:
            let regex = hostRegexTextField?.stringValue ?? ""
            if !regex.isEmpty {
                params["hostRegex"] = regex
            }

        case .eventUserChanged:
            let regex = userRegexTextField?.stringValue ?? ""
            if !regex.isEmpty {
                params["userRegex"] = regex
            }

        case .eventProgressBarChanged:
            if let popup = progressBarFilterPopup {
                switch popup.indexOfSelectedItem {
                case 0:
                    params["progressBarFilter"] = "*"
                case 1:
                    params["progressBarFilter"] = "appeared"
                case 2:
                    params["progressBarFilter"] = "disappeared"
                default:
                    params["progressBarFilter"] = "*"
                }
            }

        case .eventJobStarted, .eventJobEnded:
            let jobName = jobNameTextField?.stringValue ?? ""
            if !jobName.isEmpty {
                params["jobName"] = jobName
            }

        case .eventVariableChanged:
            let variableName = variableNameTextField?.stringValue ?? ""
            if !variableName.isEmpty {
                params[kTriggerVariableNameKey] = variableName
            }
            let valueRegex = variableValueRegexTextField?.stringValue ?? ""
            if !valueRegex.isEmpty {
                params[kTriggerVariableValueRegexKey] = valueRegex
            }

        default:
            break
        }

        return params
    }

    private func applyParams(_ params: [String: Any]) {
        switch currentMatchType {
        case .eventCommandFinished:
            if let filter = params["exitCodeFilter"] as? String {
                switch filter {
                case "*", "":
                    exitCodeFilterPopup?.selectItem(at: 0)
                    exitCodeTextField?.isHidden = true
                case "0":
                    exitCodeFilterPopup?.selectItem(at: 1)
                    exitCodeTextField?.isHidden = true
                case "!0":
                    exitCodeFilterPopup?.selectItem(at: 2)
                    exitCodeTextField?.isHidden = true
                default:
                    exitCodeFilterPopup?.selectItem(at: 3)
                    exitCodeTextField?.stringValue = filter
                    exitCodeTextField?.isHidden = false
                }
            }

        case .eventIdle, .eventActivityAfterIdle:
            if let timeout = params["timeout"] as? NSNumber {
                timeoutTextField?.stringValue = "\(timeout.intValue)"
            }

        case .eventLongRunningCommand:
            if let threshold = params["threshold"] as? NSNumber {
                thresholdTextField?.stringValue = "\(threshold.intValue)"
            }
            if let regex = params["commandRegex"] as? String {
                commandRegexTextField?.stringValue = regex
            }

        case .eventCustomEscapeSequence:
            if let sequenceId = params["sequenceId"] as? String {
                sequenceIdTextField?.stringValue = sequenceId
            }

        case .eventNotificationPosted:
            if let regex = params["messageRegex"] as? String {
                notificationMessageRegexTextField?.stringValue = regex
            }

        case .eventDirectoryChanged:
            if let regex = params["directoryRegex"] as? String {
                directoryRegexTextField?.stringValue = regex
            }

        case .eventHostChanged:
            if let regex = params["hostRegex"] as? String {
                hostRegexTextField?.stringValue = regex
            }

        case .eventUserChanged:
            if let regex = params["userRegex"] as? String {
                userRegexTextField?.stringValue = regex
            }

        case .eventProgressBarChanged:
            if let filter = params["progressBarFilter"] as? String {
                switch filter {
                case "*", "":
                    progressBarFilterPopup?.selectItem(at: 0)
                case "appeared":
                    progressBarFilterPopup?.selectItem(at: 1)
                case "disappeared":
                    progressBarFilterPopup?.selectItem(at: 2)
                default:
                    progressBarFilterPopup?.selectItem(at: 0)
                }
            }

        case .eventJobStarted, .eventJobEnded:
            if let jobName = params["jobName"] as? String {
                jobNameTextField?.stringValue = jobName
            }

        case .eventVariableChanged:
            if let variableName = params[kTriggerVariableNameKey] as? String {
                variableNameTextField?.stringValue = variableName
            }
            if let valueRegex = params[kTriggerVariableValueRegexKey] as? String {
                variableValueRegexTextField?.stringValue = valueRegex
            }

        default:
            break
        }
    }
}

// MARK: - Event Type Display Names

@objc(iTermEventTriggerMatchTypeHelper)
class EventTriggerMatchTypeHelper: NSObject {

    /// Get a human-readable name for an event match type
    @objc static func displayName(for matchType: iTermTriggerMatchType) -> String {
        switch matchType {
        case .eventPromptDetected:
            return String(localized: "EventTrigger.Name.PromptDetected", defaultValue: "Prompt Detected", comment: "Display name for the Prompt Detected event trigger")
        case .eventCommandFinished:
            return String(localized: "EventTrigger.Name.CommandFinished", defaultValue: "Command Finished", comment: "Display name for the Command Finished event trigger")
        case .eventDirectoryChanged:
            return String(localized: "EventTrigger.Name.DirectoryChanged", defaultValue: "Directory Changed", comment: "Display name for the Directory Changed event trigger")
        case .eventHostChanged:
            return String(localized: "EventTrigger.Name.HostChanged", defaultValue: "Host Changed", comment: "Display name for the Host Changed event trigger")
        case .eventUserChanged:
            return String(localized: "EventTrigger.Name.UserChanged", defaultValue: "User Changed", comment: "Display name for the User Changed event trigger")
        case .eventIdle:
            return String(localized: "EventTrigger.Name.Idle", defaultValue: "Idle (Silence)", comment: "Display name for the Idle (Silence) event trigger")
        case .eventActivityAfterIdle:
            return String(localized: "EventTrigger.Name.ActivityAfterIdle", defaultValue: "Activity After Idle", comment: "Display name for the Activity After Idle event trigger")
        case .eventSessionEnded:
            return String(localized: "EventTrigger.Name.SessionEnded", defaultValue: "Session Ended", comment: "Display name for the Session Ended event trigger")
        case .eventBellReceived:
            return String(localized: "EventTrigger.Name.BellReceived", defaultValue: "Bell Received", comment: "Display name for the Bell Received event trigger")
        case .eventLongRunningCommand:
            return String(localized: "EventTrigger.Name.LongRunningCommand", defaultValue: "Long-Running Command", comment: "Display name for the Long-Running Command event trigger")
        case .eventCustomEscapeSequence:
            return String(localized: "EventTrigger.Name.CustomEscapeSequence", defaultValue: "Custom Escape Sequence", comment: "Display name for the Custom Escape Sequence event trigger")
        case .eventNotificationPosted:
            return String(localized: "EventTrigger.Name.NotificationPosted", defaultValue: "Notification Posted", comment: "Display name for the Notification Posted event trigger")
        case .eventProgressBarChanged:
            return String(localized: "EventTrigger.Name.ProgressBarChanged", defaultValue: "Progress Bar Changed", comment: "Display name for the Progress Bar Changed event trigger")
        case .eventJobStarted:
            return String(localized: "EventTrigger.Name.JobStarted", defaultValue: "Job Started", comment: "Display name for the Job Started event trigger")
        case .eventJobEnded:
            return String(localized: "EventTrigger.Name.JobEnded", defaultValue: "Job Ended", comment: "Display name for the Job Ended event trigger")
        case .eventVariableChanged:
            return String(localized: "EventTrigger.Name.VariableChanged", defaultValue: "Variable Changed", comment: "Display name for the Variable Changed event trigger")
        default:
            return String(localized: "EventTrigger.Name.Unknown", defaultValue: "Unknown Event", comment: "Display name for an unrecognized event trigger type")
        }
    }

    /// Get a description/help text for an event match type
    @objc static func helpText(for matchType: iTermTriggerMatchType) -> String {
        switch matchType {
        case .eventPromptDetected:
            return String(localized: "EventTrigger.Help.PromptDetected", defaultValue: "Fires when shell integration detects a new prompt.", comment: "Help text for the Prompt Detected event trigger")
        case .eventCommandFinished:
            return String(localized: "EventTrigger.Help.CommandFinished", defaultValue: "Fires when a command exits. Requires shell integration.", comment: "Help text for the Command Finished event trigger")
        case .eventDirectoryChanged:
            return String(localized: "EventTrigger.Help.DirectoryChanged", defaultValue: "Fires when the working directory changes.", comment: "Help text for the Directory Changed event trigger")
        case .eventHostChanged:
            return String(localized: "EventTrigger.Help.HostChanged", defaultValue: "Fires when connecting to a different host via SSH.", comment: "Help text for the Host Changed event trigger")
        case .eventUserChanged:
            return String(localized: "EventTrigger.Help.UserChanged", defaultValue: "Fires when the current user changes (su/sudo).", comment: "Help text for the User Changed event trigger")
        case .eventIdle:
            return String(localized: "EventTrigger.Help.Idle", defaultValue: "Fires when no output is received for the specified duration.", comment: "Help text for the Idle (Silence) event trigger")
        case .eventActivityAfterIdle:
            return String(localized: "EventTrigger.Help.ActivityAfterIdle", defaultValue: "Fires when output resumes after being idle.", comment: "Help text for the Activity After Idle event trigger")
        case .eventSessionEnded:
            return String(localized: "EventTrigger.Help.SessionEnded", defaultValue: "Fires when the session terminates.", comment: "Help text for the Session Ended event trigger")
        case .eventBellReceived:
            return String(localized: "EventTrigger.Help.BellReceived", defaultValue: "Fires when a terminal bell (\\a) is received.", comment: "Help text for the Bell Received event trigger; \\a denotes the bell control character")
        case .eventLongRunningCommand:
            return String(localized: "EventTrigger.Help.LongRunningCommand", defaultValue: "Fires when a command runs longer than the threshold.", comment: "Help text for the Long-Running Command event trigger")
        case .eventCustomEscapeSequence:
            return String(localized: "EventTrigger.Help.CustomEscapeSequence", defaultValue: "Fires when a specific OSC escape sequence is received.", comment: "Help text for the Custom Escape Sequence event trigger")
        case .eventNotificationPosted:
            return String(localized: "EventTrigger.Help.NotificationPosted", defaultValue: "Fires when a notification is posted by a control sequence (OSC 9).", comment: "Help text for the Notification Posted event trigger")
        case .eventProgressBarChanged:
            return String(localized: "EventTrigger.Help.ProgressBarChanged", defaultValue: "Fires when a progress bar appears or disappears.", comment: "Help text for the Progress Bar Changed event trigger")
        case .eventJobStarted:
            return String(localized: "EventTrigger.Help.JobStarted", defaultValue: "Fires when a process matching the job filter enters the foreground-job ancestry chain.", comment: "Help text for the Job Started event trigger")
        case .eventJobEnded:
            return String(localized: "EventTrigger.Help.JobEnded", defaultValue: "Fires when a process matching the job filter leaves the foreground-job ancestry chain.", comment: "Help text for the Job Ended event trigger")
        case .eventVariableChanged:
            return String(localized: "EventTrigger.Help.VariableChanged", defaultValue: "Fires when a session variable changes to a value matching the regex.", comment: "Help text for the Variable Changed event trigger")
        default:
            return ""
        }
    }

    /// Get all event match types
    @objc static var allEventTypes: [NSNumber] {
        return [
            NSNumber(value: iTermTriggerMatchType.eventPromptDetected.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventCommandFinished.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventDirectoryChanged.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventHostChanged.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventUserChanged.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventIdle.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventActivityAfterIdle.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventSessionEnded.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventBellReceived.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventLongRunningCommand.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventCustomEscapeSequence.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventNotificationPosted.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventProgressBarChanged.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventJobStarted.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventJobEnded.rawValue),
            NSNumber(value: iTermTriggerMatchType.eventVariableChanged.rawValue)
        ]
    }

    /// Get all event match types except session ended (for triggers that need a live session)
    @objc static var allEventTypesExceptSessionEnded: [NSNumber] {
        let sessionEndedValue = NSNumber(value: iTermTriggerMatchType.eventSessionEnded.rawValue)
        return allEventTypes.filter { $0 != sessionEndedValue }
    }

    /// Get the set of all event match types as NSSet<NSNumber *>
    @objc static var allEventTypesSet: Set<NSNumber> {
        return Set(allEventTypes)
    }

    /// Get the set of all event match types except session ended as NSSet<NSNumber *>
    @objc static var allEventTypesExceptSessionEndedSet: Set<NSNumber> {
        return Set(allEventTypesExceptSessionEnded)
    }
}
