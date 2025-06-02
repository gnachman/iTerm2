//
//  MultipartMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 6/2/25.
//

class CodeAttachmentTextView: AutoSizingTextView {}
class StatusUpdateTextView: AutoSizingTextView {}

class MultipartMessageCellView: MessageCellView {
    // The bubble
    let bubbleView = BubbleView()

    // A vertical stack that holds all subparts
    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading // Align to leading edge, not center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
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

    // Bubble background colors
    private var backgroundColorPair: (NSColor, NSColor)?

    // Store all created text views for text selection control
    private var textViews: [NSTextView] = []

    override func setupViews() {
        super.setupViews()
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
    }

    override func updateColors() {
        updateBubbleColor()

        // Update attachment colors
        for textView in textViews {
            if textView.drawsBackground {
                updateTextViewColors(textView)
            }
        }
    }

    private func updateBubbleColor() {
        guard let (lightColor, darkColor) = backgroundColorPair else { return }
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }

    override var textSelectable: Bool {
        didSet {
            for textView in textViews {
                textView.isSelectable = textSelectable
            }
        }
    }

    override func configure(with rendition: MessageRendition,
                            maxBubbleWidth: CGFloat) {
        guard case .multipart(let subparts) = rendition.flavor else {
            it_fatalError()
        }

        // Clear previous state
        NSLayoutConstraint.deactivate(customConstraints)
        customConstraints = []
        textViews = []

        // Remove all subviews
        bubbleView.removeFromSuperview()
        contentStack.removeFromSuperview()
        timestamp.removeFromSuperview()

        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        // Set up base structure
        addSubview(bubbleView)
        bubbleView.addSubview(contentStack)

        // Configure bubble color
        backgroundColorPair = backgroundColorPair(rendition)
        updateBubbleColor()

        // Create subpart views
        for (index, subpart) in subparts.enumerated() {
            switch subpart.kind {
            case .regular:
                let textView = createRegularTextView(for: subpart, maxBubbleWidth: maxBubbleWidth, rendition: rendition)
                let container = createTextContainer(for: textView, isCodeAttachment: false, isStatusUpdate: false)
                contentStack.addArrangedSubview(container)
                textViews.append(textView)

            case .codeAttachment:
                let textView = createCodeAttachmentTextView(for: subpart, maxBubbleWidth: maxBubbleWidth, rendition: rendition)
                let container = createTextContainer(for: textView, isCodeAttachment: true, isStatusUpdate: false)
                contentStack.addArrangedSubview(container)
                textViews.append(textView)
            case .statusUpdate:
                let textView = createStatusUpdateTextView(for: subpart, maxBubbleWidth: maxBubbleWidth, rendition: rendition)
                let container = createTextContainer(for: textView, isCodeAttachment: true, isStatusUpdate: true)
                contentStack.addArrangedSubview(container)
                textViews.append(textView)
            }

            // Add spacing between subparts (except after the last one)
            if index < subparts.count - 1 {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                contentStack.addArrangedSubview(spacer)
                add(constraint: spacer.heightAnchor.constraint(equalToConstant: 8))
            }
        }

        // Set up timestamp
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

        // Set up bubble constraints
        addHorizontalAlignmentConstraints(rendition)
        add(constraint: bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset))
        add(constraint: bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset))

        // Content stack constraints
        add(constraint: contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: Self.topInset))
        add(constraint: contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8))
        add(constraint: contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8))
        add(constraint: contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -Self.bottomInset))

        // Width constraint - let the bubble expand based on content but cap at max
        let widthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth)
        widthConstraint.priority = NSLayoutConstraint.Priority(999) // High but not required
        maxWidthConstraint = widthConstraint
        add(constraint: widthConstraint)

        // Ensure minimum width so short code attachments don't make the whole bubble too narrow
        let minWidthConstraint = bubbleView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        add(constraint: minWidthConstraint)

        // Store message info
        messageUniqueID = rendition.messageUniqueID
        editable = rendition.isEditable
    }

    private func createRegularTextView(for subpart: MessageRendition.SubpartContainer,
                                     maxBubbleWidth: CGFloat,
                                     rendition: MessageRendition) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.isEditable = false
        textView.isSelectable = textSelectable
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: maxBubbleWidth - 32, height: .greatestFiniteMagnitude)
        textView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal) // Don't hug horizontally - expand to fill
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.linkTextAttributes = [.foregroundColor: rendition.linkColor]

        textView.textStorage?.setAttributedString(subpart.attributedString)

        return textView
    }

    private func createStatusUpdateTextView(for subpart: MessageRendition.SubpartContainer,
                                            maxBubbleWidth: CGFloat,
                                            rendition: MessageRendition) -> AutoSizingTextView {
        let textView = StatusUpdateTextView()
        textView.isEditable = false
        textView.isSelectable = textSelectable
        textView.drawsBackground = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: maxBubbleWidth - 48, height: .greatestFiniteMagnitude)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical) // Required - don't compress!
        textView.setContentHuggingPriority(.required, for: .vertical) // Required - hug the content!
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 6
        textView.layer?.borderWidth = 1.0

        textView.backgroundColor = NSColor(fromHexString: "#ffffc0")!
        textView.layer?.borderColor = NSColor.gray.cgColor

        // Use the attributed string as-is without modifying the font
        textView.textStorage?.setAttributedString(subpart.attributedString)

        return textView
    }

    private func createCodeAttachmentTextView(for subpart: MessageRendition.SubpartContainer,
                                            maxBubbleWidth: CGFloat,
                                            rendition: MessageRendition) -> AutoSizingTextView {
        let textView = CodeAttachmentTextView()
        textView.isEditable = false
        textView.isSelectable = textSelectable
        textView.drawsBackground = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: maxBubbleWidth - 48, height: .greatestFiniteMagnitude)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical) // Required - don't compress!
        textView.setContentHuggingPriority(.required, for: .vertical) // Required - hug the content!
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 6
        textView.layer?.borderWidth = 1.0

        // Set code-specific styling
        updateTextViewColors(textView)

        // Use the attributed string as-is without modifying the font
        textView.textStorage?.setAttributedString(subpart.attributedString)

        return textView
    }

    private func createTextContainer(for textView: NSTextView, isCodeAttachment: Bool, isStatusUpdate: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textView)

        if isStatusUpdate {
            // Center status updates horizontally
            add(constraint: textView.centerXAnchor.constraint(equalTo: container.centerXAnchor))
            add(constraint: textView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16))
            add(constraint: textView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16))
        } else if isCodeAttachment {
            // Indent code attachments
            add(constraint: textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16))
            add(constraint: textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0))
        } else {
            // Regular text has no extra indentation and should fill the width
            add(constraint: textView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0))
            add(constraint: textView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0))

            // For regular text, also add a width constraint to ensure it expands
            add(constraint: textView.widthAnchor.constraint(equalTo: container.widthAnchor))
        }

        add(constraint: textView.topAnchor.constraint(equalTo: container.topAnchor))
        add(constraint: textView.bottomAnchor.constraint(equalTo: container.bottomAnchor))

        container.setContentCompressionResistancePriority(.required, for: .vertical) // Don't compress containers either

        return container
    }

    private func updateTextViewColors(_ textView: NSTextView) {
        if textView is CodeAttachmentTextView {
            if effectiveAppearance.it_isDark {
                textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
                textView.layer?.borderColor = NSColor(white: 0.2, alpha: 1.0).cgColor
            } else {
                textView.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
                textView.layer?.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
            }
        }
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

    override func copyMenuItemClicked(_ sender: Any) {
        // Combine all text from all subparts
        let allText = textViews.map { $0.string }.joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(allText, forType: .string)
    }
}
