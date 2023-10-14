//
//  CommandURLHandler.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/10/23.
//

import Cocoa

fileprivate enum CommandOption {
    case hostname(String)
    case username(String)
    case directory(String)
    case offerTab
    case offerCurrent

    var title: String {
        switch self {
        case let .hostname(hostname):
            return "Run on \(hostname) via ssh"
        case let .username(username):
            return "Run as \(username)"
        case let .directory(directory):
            return "Run in directory \(directory)"
        case .offerTab:
            return "Open in tab offered"
        case .offerCurrent:
            return "Run in current session offered"
        }
    }
    var isEnabled: Bool { true }
}

fileprivate enum CommandAction {
    case runInNewWindow
    case runInNewTab
    case runInCurrentTab
    case cancel
}

fileprivate class CommandOptionsView: NSView {
    private(set) var runOnSSH = false {
        didSet {
            usernameTextField?.isEnabled = runOnSSH
        }
    }
    private(set) var username = ""
    private(set) var action = CommandAction.cancel {
        didSet {
            username = usernameTextField.stringValue
            runOnSSH = runOnSSHToggle.state == .on
            directory = directoryTextField.stringValue
            command = commandTextField.textStorage?.string ?? ""
        }
    }
    private(set) var directory = ""
    private(set) var command: String
    private(set) var hostname = ""
    private var isUsernameEnabled = false
    private var offerTab = false
    private var offerCurrent = false
    private let options: [CommandOption]

    private var commandTextField: NSTextView!
    private var runOnSSHToggle: NSButton!
    private var usernameTextField: NSTextField!
    private var directoryTextField: NSTextField!
    private var cancelButton: NSButton!
    private var newWindowButton: NSButton!
    private var newTabButton: NSButton!
    private let buttonsContainerView = NSView()
    private let buttonsStackView = NSStackView()
    private let scrollView = NSScrollView()

    let stackView = NSStackView()

    init(
        command: String,
        options: [CommandOption]
    ) {
        self.command = command
        self.options = options

        // Extract username and directory values from options
        for option in options {
            switch option {
            case .hostname(let hostname):
                self.hostname = hostname
                runOnSSH = true
            case .username(let extractedUsername):
                username = extractedUsername
            case .directory(let extractedDirectory):
                directory = extractedDirectory
            case .offerTab:
                self.offerTab = true
            case .offerCurrent:
                self.offerCurrent = true
            }
        }

        super.init(frame: .zero)

        setupSubviews()
        setupConstraints()

        let attributedString = NSAttributedString(
            string: command,
            attributes: [ .foregroundColor: NSColor.textColor,
                          .font: NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)! ])
        commandTextField.textStorage?.append(attributedString)
        runOnSSHToggle.state = runOnSSH ? .on : .off
        usernameTextField.stringValue = username
        directoryTextField.stringValue = directory
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        commandTextField = NSTextView()
        commandTextField.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)
        commandTextField.isEditable = true
        commandTextField.isSelectable = true
        commandTextField.translatesAutoresizingMaskIntoConstraints = false
        commandTextField.textColor = NSColor.textColor

        scrollView.documentView = commandTextField
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(createHorizontalStackView(label: "Command:", view: scrollView))

        runOnSSHToggle = NSButton(checkboxWithTitle: "Run on \(hostname) via ssh", target: self, action: #selector(runOnSSHToggleValueChanged))
        usernameTextField = NSTextField()

        if runOnSSH {
            runOnSSHToggle.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(runOnSSHToggle)

            let usernameStackView = NSStackView()
            usernameStackView.orientation = .horizontal
            usernameStackView.spacing = 10
            usernameStackView.translatesAutoresizingMaskIntoConstraints = false

            usernameTextField.placeholderString = "Username"
            usernameTextField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            usernameTextField.translatesAutoresizingMaskIntoConstraints = false
            usernameStackView.addArrangedSubview(createHorizontalStackView(label: "Username:", view: usernameTextField))
            stackView.addArrangedSubview(usernameStackView)
        }

        directoryTextField = NSTextField()
        directoryTextField.placeholderString = "Directory"
        directoryTextField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        directoryTextField.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(createHorizontalStackView(label: "Directory:", view: directoryTextField))

        buttonsStackView.orientation = .horizontal
        buttonsStackView.spacing = 10
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelButtonClicked))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.keyEquivalent = "\01b"
        buttonsStackView.addArrangedSubview(cancelButton)

        newWindowButton = NSButton(title: "Run in New Window", target: self, action: #selector(newWindowButtonClicked))
        newWindowButton.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.addArrangedSubview(newWindowButton)

        if offerTab {
            newTabButton = NSButton(title: "Run in New Tab", target: self, action: #selector(newTabButtonClicked))
            newTabButton.translatesAutoresizingMaskIntoConstraints = false
            buttonsStackView.addArrangedSubview(newTabButton)
        }

        if offerCurrent {
            newTabButton = NSButton(title: "Run in Current Session", target: self, action: #selector(currentSessionButtonClicked))
            newTabButton.translatesAutoresizingMaskIntoConstraints = false
            buttonsStackView.addArrangedSubview(newTabButton)
        }

        (buttonsStackView.arrangedSubviews.last as? NSButton)?.keyEquivalent = "\r"

        buttonsContainerView.translatesAutoresizingMaskIntoConstraints = false
        buttonsContainerView.addSubview(buttonsStackView)

        stackView.addArrangedSubview(buttonsContainerView)

        // Add constraints to make the container view full width
        let containerConstraints = [
            buttonsContainerView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            buttonsContainerView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
        ]
        NSLayoutConstraint.activate(containerConstraints)

        // Add constraints to right-align the buttons stack view within the container view
        let buttonsConstraints = [
            buttonsStackView.trailingAnchor.constraint(equalTo: buttonsContainerView.trailingAnchor),
            buttonsStackView.topAnchor.constraint(equalTo: buttonsContainerView.topAnchor),
            buttonsStackView.bottomAnchor.constraint(equalTo: buttonsContainerView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(buttonsConstraints)
    }

    private func createHorizontalStackView(label: String, view: NSView) -> NSStackView {
        let horizontalStackView = NSStackView()
        horizontalStackView.orientation = .horizontal
        horizontalStackView.spacing = 10

        let labelView = createLabelView(label: label)
        labelView.setContentHuggingPriority(.defaultLow, for: .horizontal) // Set low content hugging priority for label
        horizontalStackView.addArrangedSubview(labelView)

        view.setContentHuggingPriority(.defaultHigh, for: .horizontal) // Set high content hugging priority for text field/checkbox
        horizontalStackView.addArrangedSubview(view)

        // Add constraints to align the label to the right and the text field/checkbox to the left
        let constraints = [
            labelView.firstBaselineAnchor.constraint(equalTo: view.firstBaselineAnchor),
            labelView.widthAnchor.constraint(greaterThanOrEqualToConstant: 100), // Set a minimum width for the label
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200) // Set a minimum width for the text field/checkbox
        ]
        NSLayoutConstraint.activate(constraints)

        return horizontalStackView
    }

    private func setupConstraints() {
        var constraints = [
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            commandTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            directoryTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            buttonsStackView.widthAnchor.constraint(equalTo: buttonsContainerView.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 50)
        ]
        if runOnSSH {
            constraints += [usernameTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
                            runOnSSHToggle.leadingAnchor.constraint(equalTo: commandTextField.leadingAnchor, constant: 0)]
        }



        NSLayoutConstraint.activate(constraints)
    }

    private func createLabelView(label: String) -> NSTextField {
        let labelView = NSTextField()
        labelView.alignment = .right
        labelView.stringValue = label
        labelView.isEditable = false
        labelView.isSelectable = false
        labelView.isBezeled = false
        labelView.drawsBackground = false
        labelView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        return labelView
    }

    @objc private func runOnSSHToggleValueChanged() {
        runOnSSH = runOnSSHToggle.state == .on
        isUsernameEnabled = runOnSSH
    }

    override func cancelOperation(_ sender: Any?) {
        cancelButtonClicked()
    }

    @objc private func cancelButtonClicked() {
        action = .cancel
        NSApp.stopModal()
    }

    @objc private func newWindowButtonClicked() {
        action = .runInNewWindow
        NSApp.stopModal()
    }

    @objc private func newTabButtonClicked() {
        action = .runInNewTab
        NSApp.stopModal()
    }

    @objc private func currentSessionButtonClicked() {
        action = .runInCurrentTab
        NSApp.stopModal()
    }
}


@objc(iTermCommandURLHandler)
class CommandURLHandler: NSObject {
    @objc static let openInWindow = "window"
    @objc static let openInTab = "tab"
    @objc static let cancel = "cancel"
    @objc static let runInCurrentTab = "current"

    @objc var action: String {
        switch _action {
        case .cancel:
            return Self.cancel
        case .runInNewTab:
            return Self.openInTab
        case .runInNewWindow:
            return Self.openInWindow
        case .runInCurrentTab:
            return Self.runInCurrentTab
        }
    }
    private var _action = CommandAction.cancel

    @objc var command: String
    @objc var hostname: String?
    @objc var username: String?
    @objc var directory: String?
    private let offerTab: Bool
    private let offerCurrent: Bool

    @objc
    init(command: String, hostname: String?, username: String?, directory: String?, offerTab: Bool) {
        self.command = command
        self.hostname = hostname
        self.username = username
        self.directory = directory
        self.offerTab = offerTab
        self.offerCurrent = offerTab
    }

    @objc
    func show() {
        let contentView = CommandOptionsView(
            command: command,
            options: [
                hostname.map { .hostname($0) },
                username.map { .username($0) },
                directory.map { .directory($0) },
                offerTab ? .offerTab : nil,
                offerCurrent ? .offerCurrent : nil
            ].compactMap { $0 })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView

        window.setContentSize(contentView.fittingSize)

        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.runModal(for: window)

        window.orderOut(nil)

        command = contentView.command
        if !contentView.runOnSSH {
            hostname = nil
            username = nil
        } else {
            username = contentView.username
            if username?.isEmpty ?? false {
                username = nil
            }
        }
        directory = contentView.directory
        _action = contentView.action
    }
}

