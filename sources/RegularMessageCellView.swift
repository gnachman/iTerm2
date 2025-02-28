//
//  RegularMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/23/25.
//


@objc(iTermBubbleView) class BubbleView: NSView {}
@objc(iTermTextLabelContainer) class TextLabelContainer: NSView {}
class MessageTextView: NSTextView {}
class MessageTimestamp: NSTextField {}

@objc
class RegularMessageCellView: MessageCellView {
    // The bubble
    let bubbleView = BubbleView()

    // A vertical stack that holds the textLabel on top and any buttons beneath
    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = RegularMessageCellView.stackViewSpacing
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

    // We store the button ID + message ID so we can fire a callback
    private var buttonIdentifiers: [NSButton: (identifier: String, messageUniqueID: UUID)] = [:]

    // Called when any button is clicked
    var buttonClicked: ((String, UUID) -> Void)?

    // Bubble background colors
    private var backgroundColorPair: (NSColor, NSColor)?

    private static let stackViewSpacing = 1.0

    override func setupViews() {
        super.setupViews()
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
    }

    // Update the bubble’s color if dark vs. light mode changes
    override func updateColors() {
        updateBubbleColor()
    }

    private func updateBubbleColor() {
        guard let (lightColor, darkColor) = backgroundColorPair else { return }
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }

    override var textSelectable: Bool {
        didSet {
            textLabel.isSelectable = textSelectable
        }
    }

    override func configure(with rendition: MessageRendition,
                            maxBubbleWidth: CGFloat) {
        guard case .regular(let regular) = rendition.flavor else {
            it_fatalError()
        }
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
        backgroundColorPair = backgroundColorPair(rendition)
        updateBubbleColor()

        // Set text
        textLabel.textStorage?.setAttributedString(regular.attributedString)

        // Let text wrap if it's wider than the bubble
        textLabel.textContainer?.widthTracksTextView = false
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - 16, height: .greatestFiniteMagnitude)
        textLabel.linkTextAttributes = [.foregroundColor: rendition.linkColor]

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
        for buttonRendition in regular.buttons {
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

            if !regular.enableButtons {
                button.isEnabled = false
            }
        }

        if !regular.buttons.isEmpty {
            // Add bottom spacer
            let view = NSView()
            contentStack.addArrangedSubview(view)
            add(constraint: view.heightAnchor.constraint(equalToConstant: 1))
        }

        addHorizontalAlignmentConstraints(rendition)
        add(constraint: bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset))
        add(constraint: bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset))

        // Inset contentStack in bubbleView
        add(constraint: contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 0))
        add(constraint: contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 0))
        add(constraint: contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: 0))
        add(constraint: contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 0))

        // Finally cap the total width
        let widthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth)
        maxWidthConstraint = widthConstraint
        add(constraint: widthConstraint)

        messageUniqueID = rendition.messageUniqueID
        editable = rendition.isEditable
    }

    func addHorizontalAlignmentConstraints(_ rendition: MessageRendition) {
        if rendition.isUser {
            add(constraint: bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8))
            add(constraint: bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8))
        } else {
            add(constraint: bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8))
            add(constraint: bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8))
        }
    }

    func backgroundColorPair(_ rendition: MessageRendition) -> (NSColor, NSColor) {
        rendition.isUser
        ? (NSColor(fromHexString: "p3#448bf7")!, NSColor(fromHexString: "p3#4a93f5")!)
        : (NSColor(fromHexString: "p3#e9e9eb")!, NSColor(fromHexString: "p3#3b3b3d")!)
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        // Fire your callback with the button ID and the message ID
        if let (identifier, msgID) = buttonIdentifiers[sender] {
            buttonClicked?(identifier, msgID)
        }
        // Disable all buttons
        for case let button as NSButton in contentStack.arrangedSubviews where button !== textLabel {
            button.isEnabled = false
        }
    }

    override func copyMenuItemClicked(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textLabel.string, forType: .string)
    }
}

