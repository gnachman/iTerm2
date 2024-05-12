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
    case runSilently
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
            command = textView.textStorage?.string ?? ""
        }
    }
    private(set) var directory = ""
    private(set) var command: String
    private(set) var hostname = ""
    private var isUsernameEnabled = false
    private var offerTab = false
    private var offerCurrent = false
    private let options: [CommandOption]

    private var textView: NSTextView!
    private var runOnSSHToggle: NSButton!
    private var usernameTextField: NSTextField!
    private var directoryTextField: NSTextField!
    private var cancelButton: NSButton!
    private var newWindowButton: NSButton!
    private var newTabButton: NSButton!
    private let buttonsContainerView = NSView()
    private let buttonsStackView = NSStackView()
    private let scrollView = NSScrollView()
    private let finish: () -> ()

    let stackView = NSStackView()

    init(
        command: String,
        options: [CommandOption],
        completion: @escaping () -> ()
    ) {
        self.command = command
        self.options = options
        self.finish = completion

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
        textView.textStorage?.append(attributedString)
        runOnSSHToggle.state = runOnSSH ? .on : .off
        usernameTextField.stringValue = username
        directoryTextField.stringValue = directory
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)

        layoutTextview()
    }

    private func layoutTextview() {
        let containerWidth = scrollView.documentVisibleRect.width
        textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let textBounds = textView.layoutManager?.usedRect(for: textView.textContainer!)
        let desiredHeight = textBounds?.height ?? 0

        textView.frame = CGRect(x: 0, y: 0, width: containerWidth, height: max(desiredHeight, 50))
    }

    override func layoutSubtreeIfNeeded() {
        super.layoutSubtreeIfNeeded()
        layoutTextview()
    }

    private func addHorizontalStackView(_ horizontalStackView: NSStackView) {
        stackView.addArrangedSubview(horizontalStackView)
        NSLayoutConstraint.activate([
            horizontalStackView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            horizontalStackView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
        ])
    }

    private func setupSubviews() {
        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        textView.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.drawsBackground = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        
        addHorizontalStackView(createHorizontalStackView(label: "Command:",
                                                         view: scrollView,
                                                         firstBaselineAnchor: scrollView.centerYAnchor))

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
            usernameStackView.addArrangedSubview(createHorizontalStackView(label: "Username:",
                                                                           view: usernameTextField,
                                                                           firstBaselineAnchor: usernameTextField.firstBaselineAnchor))
            addHorizontalStackView(usernameStackView)
        }

        directoryTextField = NSTextField()
        directoryTextField.placeholderString = "Directory"
        directoryTextField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        directoryTextField.translatesAutoresizingMaskIntoConstraints = false
        addHorizontalStackView(createHorizontalStackView(label: "Directory:",
                                                         view: directoryTextField,
                                                         firstBaselineAnchor: directoryTextField.firstBaselineAnchor))

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

        // Constrain right-hand side views to have same leading edge.
        let hsvs = stackView.arrangedSubviews.compactMap { view -> NSStackView? in
            guard let hsv = view as? NSStackView else {
                return nil
            }
            if hsv.arrangedSubviews.count != 2 {
                return nil
            }
            return hsv
        }
        if let firstHSV = hsvs.first, hsvs.count > 1 {
            NSLayoutConstraint.activate(hsvs[1...].map { hsv in
                hsv.arrangedSubviews[1].leadingAnchor.constraint(equalTo: firstHSV.arrangedSubviews[1].leadingAnchor)
            })
        }
    }

    private func createHorizontalStackView(label: String, view: NSView, firstBaselineAnchor: NSLayoutYAxisAnchor) -> NSStackView {
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
            labelView.firstBaselineAnchor.constraint(equalTo: firstBaselineAnchor),
            labelView.widthAnchor.constraint(greaterThanOrEqualToConstant: 100), // Set a minimum width for the label
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 200), // Set a minimum width for the text field/checkbox
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
            directoryTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            buttonsStackView.widthAnchor.constraint(equalTo: buttonsContainerView.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 50)
        ]
        if runOnSSH {
            constraints += [usernameTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
                            runOnSSHToggle.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 0)]
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
        finish()
    }

    @objc private func newWindowButtonClicked() {
        action = .runInNewWindow
        finish()
    }

    @objc private func newTabButtonClicked() {
        action = .runInNewTab
        finish()
    }

    @objc private func currentSessionButtonClicked() {
        action = .runInCurrentTab
        finish()
    }
}


@objc(iTermCommandURLHandler)
class CommandURLHandler: NSObject {
    @objc static let openInWindow = "window"
    @objc static let openInTab = "tab"
    @objc static let cancel = "cancel"
    @objc static let runInCurrentTab = "current"
    @objc static let runSilently = "silent"

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
        case .runSilently:
            return Self.runSilently
        }
    }
    private var _action = CommandAction.cancel

    @objc var command: String
    @objc var hostname: String?
    @objc var username: String?
    @objc var directory: String?
    private let offerTab: Bool
    private let offerCurrent: Bool
    private var completion: ((CommandURLHandler) -> ())?
    private var window: NSWindow?
    private var contentView: CommandOptionsView?
    private static var instances = [CommandURLHandler]()

    @objc
    init(command: String, hostname: String?, username: String?, directory: String?, offerTab: Bool, silent: Bool) {
        self.command = command
        self.hostname = hostname
        self.username = username
        self.directory = directory
        self.offerTab = offerTab
        self.offerCurrent = offerTab
        if silent {
            _action = .runSilently
        }
    }

    @objc
    func show(completion: ((CommandURLHandler) -> ())?) {
        if _action == .runSilently {
            var parts = ["Run command", "“" + self.command + "”"]
            if let username {
                parts.append("as \(username)")
            }
            if let hostname, !hostname.isEmpty {
                parts.append("on \(hostname)")
            }
            if let directory {
                parts.append("in \(directory)")
            }
            let selection = iTermWarning.show(withTitle: parts.joined(separator: " ") + "?\nIt will run silently in the background.",
                                              actions: [ "OK", "Cancel"],
                                              accessory: nil,
                                              identifier: "NoSyncRunCommand_\(self.command)",
                                              silenceable: .kiTermWarningTypePermanentlySilenceable,
                                              heading: "Run Command?",
                                              window: nil)
            if selection == .kiTermWarningSelection0 {
                _action = .runSilently
            } else {
                _action = .cancel
            }
            completion?(self)
            return
        }
        Self.instances.append(self)
        let contentView = CommandOptionsView(
            command: command,
            options: [
                hostname.map { .hostname($0) },
                username.map { .username($0) },
                directory.map { .directory($0) },
                offerTab ? .offerTab : nil,
                offerCurrent ? .offerCurrent : nil
            ].compactMap { $0 }) { [weak self] in
                self?.finish()
            }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.title = "Run Command from URL"
        window.setContentSize(contentView.fittingSize)

        window.center()
        window.makeKeyAndOrderFront(nil)
        self.completion = completion
        self.window = window
        self.contentView = contentView
    }

    func finish() {
        defer {
            Self.instances.removeAll { $0 === self }
        }
        guard let window, let contentView, let completion else {
            return
        }
        defer {
            self.window = nil
            self.contentView = nil
            self.completion = nil
        }
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
        completion(self)
    }
}

class CommandOptionsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
