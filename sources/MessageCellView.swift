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
}

@objc(iTermBubbleView)
class BubbleView: NSView {}

@objc(iTermTextLabelContainer)
class TextLabelContainer: NSView {}

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
    private let textLabel: NSTextView = {
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

    private let timestamp: NSTextField = {
        let textField = NSTextField()
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

    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    private static let stackViewSpacing = 1.0

    private func setupViews() {
        // Setup bubble
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)

        // Add the vertical stack inside the bubble
        bubbleView.addSubview(contentStack)
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
                   tableViewWidth: CGFloat)
    {
        // Decide bubble color pair based on isUser
        backgroundColorPair = rendition.isUser
            ? (NSColor(fromHexString: "p3#448bf7")!, NSColor(fromHexString: "p3#4a93f5")!)
            : (NSColor(fromHexString: "p3#e9e9eb")!, NSColor(fromHexString: "p3#3b3b3d")!)
        updateBubbleColor()

        // Set text
        textLabel.textStorage?.setAttributedString(rendition.attributedString)
        // Let text wrap if it's wider than the bubble
        let maxBubbleWidth = tableViewWidth * 0.7
        textLabel.textContainer?.widthTracksTextView = false
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - 16, height: .greatestFiniteMagnitude)

        let container = TextLabelContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textLabel)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor, constant: -8.0),
            container.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 8.0),
            container.topAnchor.constraint(equalTo: textLabel.topAnchor, constant: -Self.topInset),
            container.bottomAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: Self.bottomInset),
        ])

        // Clear any old buttons
        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        contentStack.addArrangedSubview(container)


        // Timestamp
        timestamp.stringValue = rendition.timestamp
        addSubview(timestamp)
        NSLayoutConstraint.activate([
            timestamp.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            rendition.isUser ? timestamp.rightAnchor.constraint(equalTo: bubbleView.leftAnchor, constant: -8) : timestamp.leftAnchor.constraint(equalTo: bubbleView.rightAnchor, constant: 8)
        ])


        buttonIdentifiers.removeAll()

        // Add new buttons (if any) under the text
        for buttonRendition in rendition.buttons {
            // Add a separator.
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.gray.cgColor
            contentStack.addArrangedSubview(view)
            view.heightAnchor.constraint(equalToConstant: 1).isActive = true
            view.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 1.0).isActive = true

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
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            // Let the button expand horizontally, up to the bubble’s max
            // (If it’s bigger than the text, the stack—and thus bubble—will match the button’s width)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            // Add it under the text label
            contentStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: contentStack.widthAnchor, multiplier: 1.0).isActive = true

            if !rendition.enableButtons {
                button.isEnabled = false
            }
        }

        if !rendition.buttons.isEmpty {
            // Add bottom spacer
            let view = NSView()
            contentStack.addArrangedSubview(view)
            view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }

        // Now set the bubble’s alignment constraints
        // If user => right aligned, else => left aligned
        // *Important:* Pin both sides so it can expand up to `maxBubbleWidth`
        NSLayoutConstraint.deactivate(bubbleView.constraints) // remove old constraints if reusing the cell

        if rendition.isUser {
            NSLayoutConstraint.activate([
                bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
                bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth)
            ])
        } else {
            NSLayoutConstraint.activate([
                bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
                bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset),
                bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth)
            ])
        }
        // Inset contentStack in bubbleView
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 0),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 0),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: 0),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 0),
        ])

        // Finally cap the total width
        bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth).isActive = true

        // If you also need a bottom anchor or flexible row height, set that outside or in your tableView
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
/*
    static func height(for rendition: MessageRendition, tableViewWidth: CGFloat) -> CGFloat {
        // measure text
        let hPadding: CGFloat = 16
        let maxBubbleWidth = tableViewWidth * 0.7 - hPadding
        let textHeight = measuredTextHeight(for: rendition.attributedString, maxWidth: maxBubbleWidth)

        // base bubble vertical insets
        let baseHeight = topInset + textHeight + bottomInset

        // add buttons
        let spacingBetweenLabelAndButtons: CGFloat = rendition.buttons.isEmpty ? 0 : 8
        let buttonHeight: CGFloat = 30
        let totalButtonHeights = buttonHeight * CGFloat(rendition.buttons.count)
        // some spacing between each button
        let buttonSpacing = 8 * CGFloat(max(0, rendition.buttons.count - 1))

        return baseHeight + spacingBetweenLabelAndButtons + totalButtonHeights + buttonSpacing
    }

    private static func measuredTextHeight(for attributedString: NSAttributedString,
                                           maxWidth: CGFloat) -> CGFloat
    {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return ceil(usedRect.height)
    }
 */
}

@objc
class DateCellView: NSView {
    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 8
    private let bubbleView = BubbleView()
    private let textField = {
        let tf = NSTextField()
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
            return "Inalid date"
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
    }}

