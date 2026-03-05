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
        let row = createRow(label: "Exit Code:")

        let popup = NSPopUpButton()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.addItems(withTitles: ["Any", "Zero (Success)", "Non-Zero (Failure)", "Specific Value…"])
        popup.target = self
        popup.action = #selector(exitCodeFilterChanged(_:))
        exitCodeFilterPopup = popup

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = "Exit code"
        textField.isHidden = true
        textField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        textField.delegate = self
        textField.formatter = iTermSaneNumberFormatter()
        exitCodeTextField = textField

        row.addArrangedSubview(popup)
        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)
    }

    private func addDirectoryRegexUI() {
        let row = createRow(label: "Directory:")

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        directoryRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: "Regular expression to match the directory path")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addTimeoutUI() {
        let row = createRow(label: "Timeout:")

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = "30"
        textField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        textField.delegate = self
        textField.formatter = iTermSaneNumberFormatter()
        timeoutTextField = textField

        let unitsLabel = NSTextField(labelWithString: "seconds")
        unitsLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(textField)
        row.addArrangedSubview(unitsLabel)
        stackView.addArrangedSubview(row)
    }

    private func addSequenceIdUI() {
        let row = createRow(label: "Sequence ID:")

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        sequenceIdTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: "Regular expression to match the sequence identifier")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addHostRegexUI() {
        let row = createRow(label: "Host:")

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        hostRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: "Regular expression to match the hostname")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addUserRegexUI() {
        let row = createRow(label: "User:")

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = ".*"
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        textField.delegate = self
        userRegexTextField = textField

        row.addArrangedSubview(textField)
        stackView.addArrangedSubview(row)

        let helpLabel = NSTextField(labelWithString: "Regular expression to match the username")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addLongRunningCommandUI() {
        // Threshold row
        let thresholdRow = createRow(label: "Threshold:")

        let thresholdField = NSTextField()
        thresholdField.translatesAutoresizingMaskIntoConstraints = false
        thresholdField.placeholderString = "60"
        thresholdField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        thresholdField.delegate = self
        thresholdField.formatter = iTermSaneNumberFormatter()
        thresholdTextField = thresholdField

        let unitsLabel = NSTextField(labelWithString: "seconds")
        unitsLabel.translatesAutoresizingMaskIntoConstraints = false

        thresholdRow.addArrangedSubview(thresholdField)
        thresholdRow.addArrangedSubview(unitsLabel)
        stackView.addArrangedSubview(thresholdRow)

        // Command regex row
        let commandRow = createRow(label: "Command:")

        let commandField = NSTextField()
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.placeholderString = ".*"
        commandField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        commandField.delegate = self
        commandRegexTextField = commandField

        commandRow.addArrangedSubview(commandField)
        stackView.addArrangedSubview(commandRow)

        let helpLabel = NSTextField(labelWithString: "Regular expression to match the command line")
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(helpLabel)
    }

    private func addNoParametersLabel() {
        let label = NSTextField(labelWithString: "No additional parameters required.")
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
            }
        }
        onParametersChanged?()
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
            return "Prompt Detected"
        case .eventCommandFinished:
            return "Command Finished"
        case .eventDirectoryChanged:
            return "Directory Changed"
        case .eventHostChanged:
            return "Host Changed"
        case .eventUserChanged:
            return "User Changed"
        case .eventIdle:
            return "Idle (Silence)"
        case .eventActivityAfterIdle:
            return "Activity After Idle"
        case .eventSessionEnded:
            return "Session Ended"
        case .eventBellReceived:
            return "Bell Received"
        case .eventLongRunningCommand:
            return "Long-Running Command"
        case .eventCustomEscapeSequence:
            return "Custom Escape Sequence"
        default:
            return "Unknown Event"
        }
    }

    /// Get a description/help text for an event match type
    @objc static func helpText(for matchType: iTermTriggerMatchType) -> String {
        switch matchType {
        case .eventPromptDetected:
            return "Fires when shell integration detects a new prompt."
        case .eventCommandFinished:
            return "Fires when a command exits. Requires shell integration."
        case .eventDirectoryChanged:
            return "Fires when the working directory changes."
        case .eventHostChanged:
            return "Fires when connecting to a different host via SSH."
        case .eventUserChanged:
            return "Fires when the current user changes (su/sudo)."
        case .eventIdle:
            return "Fires when no output is received for the specified duration."
        case .eventActivityAfterIdle:
            return "Fires when output resumes after being idle."
        case .eventSessionEnded:
            return "Fires when the session terminates."
        case .eventBellReceived:
            return "Fires when a terminal bell (\\a) is received."
        case .eventLongRunningCommand:
            return "Fires when a command runs longer than the threshold."
        case .eventCustomEscapeSequence:
            return "Fires when a specific OSC escape sequence is received."
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
            NSNumber(value: iTermTriggerMatchType.eventCustomEscapeSequence.rawValue)
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
