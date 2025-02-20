import Cocoa

// MARK: - MessageRendition

struct MessageRendition {
    struct Button {
        var title: String
        var color: NSColor
        var identifier: String
    }
    var attributedString: NSAttributedString
    var buttons: [Button]
    var messageUniqueID: UUID
    var isUser: Bool
    var enableButtons: Bool
    var timestamp: String
    var isEditable: Bool
}

// MARK: - BubbleView and Other Views

@objc(iTermBubbleView)
class BubbleView: NSView {}

@objc(iTermTextLabelContainer)
class TextLabelContainer: NSView {}

class MessageTextView: NSTextView {}
class MessageTimestamp: NSTextField {}

// MARK: - MessageCellView

@objc
class MessageCellView: NSView {
    // The bubble
    private let bubbleView = BubbleView()

    // A vertical stack that holds the textLabel on top and any buttons beneath
    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = MessageCellView.stackViewSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // The text label
    private let textLabel: AutoSizingTextView = {
        let tv = AutoSizingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.textContainer?.widthTracksTextView = true
        tv.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let container: TextLabelContainer = {
        let container = TextLabelContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    private let timestamp: MessageTimestamp = {
        let textField = MessageTimestamp()
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.isBordered = false
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.alphaValue = 0.65
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.alignment = .right
        return textField
    }()

    private var editable: Bool = false
    private var rightClickMonitor: Any?

    // We store the button ID + message ID so we can fire a callback
    private var buttonIdentifiers: [NSButton: (identifier: String, messageUniqueID: UUID)] = [:]

    // Called when any button is clicked
    var buttonClicked: ((String, UUID) -> Void)?

    // Callback for the edit button.
    var editButtonClicked: ((UUID) -> Void)?

    // Bubble background colors
    private var backgroundColorPair: (NSColor, NSColor)?

    // store the messageUniqueID so that the edit button can pass it along.
    private var messageUniqueID: UUID?

    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    deinit {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private static let stackViewSpacing = 1.0

    private func setupViews() {
        // Setup bubble
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
    }

    // Update the bubble’s color if dark vs. light mode changes
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleColor()
    }

    private func updateBubbleColor() {
        guard let (lightColor, darkColor) = backgroundColorPair else { return }
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }

    /// Configure the cell with your `MessageRendition`.
    /// `maxBubbleWidth` is how wide you allow the bubble to grow.
    func configure(with rendition: MessageRendition,
                   tableViewWidth: CGFloat) {
        configure(with: rendition, maxBubbleWidth: tableViewWidth * 0.7)
    }

    private var customConstraints = [NSLayoutConstraint]()

    private func add(constraint: NSLayoutConstraint) {
        customConstraints.append(constraint)
        constraint.isActive = true
    }

    var textSelectable = true {
        didSet {
            textLabel.isSelectable = textSelectable
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if textSelectable {
            return super.hitTest(point)
        }
        return self
    }

    func configure(with rendition: MessageRendition,
                   maxBubbleWidth: CGFloat) {
        NSLayoutConstraint.deactivate(customConstraints)
        customConstraints = []

        // Ensure constraints are really gone by removing everything
        // from the view hierarchy.
        bubbleView.removeFromSuperview()
        contentStack.removeFromSuperview()
        textLabel.removeFromSuperview()
        container.removeFromSuperview()
        timestamp.removeFromSuperview()
        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        // Set up subviews aside from content stack, which is dynamic.
        addSubview(bubbleView)
        bubbleView.addSubview(contentStack)
        container.addSubview(textLabel)

        // Decide bubble color pair based on isUser
        backgroundColorPair = rendition.isUser
        ? (NSColor(fromHexString: "p3#448bf7")!, NSColor(fromHexString: "p3#4a93f5")!)
        : (NSColor(fromHexString: "p3#e9e9eb")!, NSColor(fromHexString: "p3#3b3b3d")!)
        updateBubbleColor()

        // Set text
        textLabel.textStorage?.setAttributedString(rendition.attributedString)

        // Let text wrap if it's wider than the bubble
        textLabel.textContainer?.widthTracksTextView = false
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - 16, height: .greatestFiniteMagnitude)
        textLabel.linkTextAttributes = [.foregroundColor: NSColor.textColor]

        add(constraint: container.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor, constant: -8.0))
        add(constraint: container.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 8.0))
        add(constraint: container.topAnchor.constraint(equalTo: textLabel.topAnchor, constant: -Self.topInset))
        add(constraint: container.bottomAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: Self.bottomInset))
        container.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        contentStack.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        contentStack.addArrangedSubview(container)

        // Timestamp
        timestamp.stringValue = rendition.timestamp
        if !rendition.timestamp.isEmpty {
            addSubview(timestamp)
            add(constraint: timestamp.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor))

            if rendition.isUser {
                add(constraint: timestamp.rightAnchor.constraint(equalTo: bubbleView.leftAnchor, constant: -8))
            } else {
                add(constraint: timestamp.leftAnchor.constraint(equalTo: bubbleView.rightAnchor, constant: 8))
            }
        }

        buttonIdentifiers.removeAll()

        // Add new buttons (if any) under the text
        for buttonRendition in rendition.buttons {
            // Add a separator.
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.gray.cgColor
            contentStack.addArrangedSubview(view)
            add(constraint: view.heightAnchor.constraint(equalToConstant: 1))
            add(constraint: view.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 1.0))

            let button = NSButton(title: buttonRendition.title, target: self, action: #selector(buttonTapped(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isBordered = false
            button.wantsLayer = true

            // Single-line truncation if too wide
            if let cell = button.cell as? NSButtonCell {
                cell.usesSingleLineMode = true
                cell.lineBreakMode = .byTruncatingTail
                cell.wraps = false
            }

            let attrTitle = NSAttributedString(
                string: buttonRendition.title,
                attributes: [
                    .foregroundColor: buttonRendition.color,
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
                ]
            )
            button.attributedTitle = attrTitle

            // Store button ID + message ID for the callback
            buttonIdentifiers[button] = (buttonRendition.identifier, rendition.messageUniqueID)

            // Force a single-line height (30)
            add(constraint: button.heightAnchor.constraint(equalToConstant: 30))
            // Let the button expand horizontally, up to the bubble’s max
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            // Add it under the text label
            contentStack.addArrangedSubview(button)
            add(constraint: button.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 1.0))

            if !rendition.enableButtons {
                button.isEnabled = false
            }
        }

        if !rendition.buttons.isEmpty {
            // Add bottom spacer
            let view = NSView()
            contentStack.addArrangedSubview(view)
            add(constraint: view.heightAnchor.constraint(equalToConstant: 1))
        }

        if rendition.isUser {
            add(constraint: bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8))
            add(constraint: bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset))
            add(constraint: bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8))
            add(constraint: bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset))
        } else {
            add(constraint: bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8))
            add(constraint: bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset))
            add(constraint: bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8))
            add(constraint: bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset))
        }
        // Inset contentStack in bubbleView
        add(constraint: contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 0))
        add(constraint: contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 0))
        add(constraint: contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: 0))
        add(constraint: contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 0))

        // Finally cap the total width
        add(constraint: bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth))

        messageUniqueID = rendition.messageUniqueID
        editable = rendition.isEditable
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        // Fire your callback with the button ID and the message ID
        if let (identifier, msgID) = buttonIdentifiers[sender] {
            buttonClicked?(identifier, msgID)
        }
        // Disable all buttons
        for case let b as NSButton in contentStack.arrangedSubviews where b !== textLabel {
            b.isEnabled = false
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // Add a local monitor for right mouse down events.
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self = self else {
                    return event
                }
                let pointInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(pointInSelf) {
                    self.handleRightClick(event)
                    return nil
                }
                return event
            }
        } else if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
    }

    @objc private func handleRightClick(_ event: NSEvent) {
        guard editable else { return }
        let menu = NSMenu(title: "Context Menu")
        let editItem = NSMenuItem(title: "Edit", action: #selector(editMenuItemClicked(_:)), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyMenuItemClicked(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyMenuItemClicked(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textLabel.string, forType: .string)
    }
    @objc private func editMenuItemClicked(_ sender: Any) {
        if let id = messageUniqueID {
            editButtonClicked?(id)
        }
    }
}

// MARK: - DateCellView

class DateTextField: NSTextField {}

@objc
class DateCellView: NSView {
    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 8
    private let bubbleView = BubbleView()
    private let textField = {
        let tf = DateTextField()
        tf.isEditable = false
        tf.isSelectable = false
        tf.drawsBackground = false
        tf.isBordered = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.masksToBounds = false  // Allow subviews to be drawn outside the cell’s bounds.

        // Setup bubble
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)

        // Add the vertical stack inside the bubble
        bubbleView.addSubview(textField)
        updateBubbleColor()

        NSLayoutConstraint.activate([
            // textField inset within bubbleView
            bubbleView.leadingAnchor.constraint(equalTo: textField.leadingAnchor, constant: -8.0),
            bubbleView.trailingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8.0),
            bubbleView.topAnchor.constraint(equalTo: textField.topAnchor, constant: -Self.topInset),
            bubbleView.bottomAnchor.constraint(equalTo: textField.bottomAnchor, constant: Self.bottomInset),

            // bubbleView inset within cell and centered horizontally
            bubbleView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 0),
            bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset),
        ])
        bubbleView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleColor()
    }

    private func updateBubbleColor() {
        let (lightColor, darkColor) = (NSColor(fromHexString: "#e0e0e0")!,
                                       NSColor(fromHexString: "#505050")!)
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }

    func set(dateComponents components: DateComponents) {
        textField.stringValue = humanReadableDate(from: components)
    }

    private func humanReadableDate(from components: DateComponents) -> String {
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            return "Invalid date"
        }

        let now = Date()
        let today = calendar.startOfDay(for: now)
        let dateStart = calendar.startOfDay(for: date)

        let formatter = DateFormatter()
        formatter.locale = Locale.current

        let daysDifference = calendar.dateComponents([.day], from: dateStart, to: today).day ?? 0

        if daysDifference == 0 {
            return "Today"
        } else if daysDifference == 1 {
            return "Yesterday"
        } else if daysDifference > 1 && daysDifference < 7 {
            formatter.dateFormat = "EEEE" // Full weekday name
        } else if daysDifference >= 7 && calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "MMM d" // "Mon DD"
        } else {
            formatter.dateFormat = "MMM d, yyyy" // "Mon DD, YYYY"
        }

        return formatter.string(from: date)
    }
}
