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

        // Update code block header colors
        updateCodeBlockHeaderColors()
    }

    private func updateCodeBlockHeaderColors() {
        // Find all code block headers and update their colors
        func updateHeadersInView(_ view: NSView) {
            for subview in view.subviews {
                // Check if this is a code block container
                if subview.subviews.count >= 2,
                   subview.subviews.contains(where: { $0 is CodeAttachmentTextView }) {
                    // Find the header view (the one that's not the text view)
                    if let headerView = subview.subviews.first(where: { !($0 is CodeAttachmentTextView) && $0.layer != nil }) {
                        updateCodeBlockHeaderColors(headerView)
                    }
                }
                updateHeadersInView(subview)
            }
        }
        updateHeadersInView(self)
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
                let container = createContainer(for: textView, isCodeAttachment: false, isStatusUpdate: false)
                contentStack.addArrangedSubview(container)
                textViews.append(textView)

            case .codeAttachment:
                let textView = createCodeAttachmentTextView(for: subpart, maxBubbleWidth: maxBubbleWidth, rendition: rendition)
                let container = createCodeBlockContainer(for: textView)

                // Create a wrapper view to handle the 16pt inset outside the container
                let wrapperView = NSView()
                wrapperView.translatesAutoresizingMaskIntoConstraints = false
                wrapperView.addSubview(container)

                // Position container with 16pt left inset within wrapper
                add(constraint: container.topAnchor.constraint(equalTo: wrapperView.topAnchor))
                add(constraint: container.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 0))
                add(constraint: container.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor))
                add(constraint: container.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor))

                contentStack.addArrangedSubview(wrapperView)
                textViews.append(textView)
            case .statusUpdate:
                let textView = createStatusUpdateTextView(for: subpart, maxBubbleWidth: maxBubbleWidth, rendition: rendition)
                let container = createContainer(for: textView, isCodeAttachment: true, isStatusUpdate: true)
                contentStack.addArrangedSubview(container)
                textViews.append(textView)
            case .fileAttachment(id: let id, name: let name, file: let file):
                let view = FileAttachmentSubpartView(icon: subpart.icon!,
                                                     filename: subpart.attributedString,
                                                     id: id,
                                                     name: name,
                                                     file: file)
                view.translatesAutoresizingMaskIntoConstraints = false
                let container = createContainer(for: view, isCodeAttachment: false, isStatusUpdate: false)
                contentStack.addArrangedSubview(container)
                break
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

    private func createFileAttachment(for subpart: MessageRendition.SubpartContainer,
                                      maxBubbleWidth: CGFloat,
                                      rendition: MessageRendition) -> AutoSizingTextView {
        return createRegularTextView(for: subpart, maxBubbleWidth: maxBubbleWidth, rendition: rendition)
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

        // Get the attributed string and modify text color for dark mode
        let attributedString = NSMutableAttributedString(attributedString: subpart.attributedString)
        if effectiveAppearance.it_isDark {
            // Force text color to black in dark mode for status updates
            attributedString.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: attributedString.length))
        }
        textView.textStorage?.setAttributedString(attributedString)

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
        // Remove corner radius here - it will be set in the container
        textView.layer?.borderWidth = 0 // Border will be handled by container

        // Set code-specific styling
        updateTextViewColors(textView)

        // Use the attributed string as-is without modifying the font
        textView.textStorage?.setAttributedString(subpart.attributedString)

        return textView
    }

    private func createCodeBlockHeader() -> NSView {
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        // Remove corner radius and border from header - container handles it now

        // Set header colors
        updateCodeBlockHeaderColors(headerView)

        // Create title label
        let titleLabel = NSTextField(labelWithString: "Code Interpreter")
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = effectiveAppearance.it_isDark ? NSColor.white : NSColor.black

        let copyButton = NSButton()
        copyButton.title = "Copy"
        copyButton.image = NSImage.it_image(forSymbolName: "document.on.document",
                                            accessibilityDescription: "Copy",
                                            fallbackImageName: "document.on.document",
                                            for: MultipartMessageCellView.self)
        copyButton.imagePosition = .imageLeading
        copyButton.bezelStyle = .smallSquare
        copyButton.isBordered = false
        copyButton.controlSize = .small
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = self
        copyButton.action = #selector(copyCodeButtonClicked(_:))

        // Remove background color from Copy button
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor.clear.cgColor

        headerView.addSubview(titleLabel)
        headerView.addSubview(copyButton)

        // Position title label in the left with padding
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // Position copy button in top-right with padding
            copyButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            copyButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 6),
            copyButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -6),
            headerView.heightAnchor.constraint(equalToConstant: 32)
        ])

        return headerView
    }

    @objc private func copyCodeButtonClicked(_ sender: NSButton) {
        // Find the associated text view by traversing the view hierarchy
        guard let headerView = sender.superview,
              let containerView = headerView.superview,
              let codeTextView = containerView.subviews.first(where: { $0 is CodeAttachmentTextView }) as? NSTextView else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeTextView.string, forType: .string)
    }

    private func createCodeBlockContainer(for textView: NSTextView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.borderWidth = 1.0

        // Create the header with copy button
        let headerView = createCodeBlockHeader()

        // Add header and text view to container
        container.addSubview(headerView)
        container.addSubview(textView)

        // Set container colors and border
        updateCodeBlockContainerColors(container)

        // Layout constraints - header and text view fill the container completely
        add(constraint: headerView.topAnchor.constraint(equalTo: container.topAnchor))
        add(constraint: headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor))
        add(constraint: headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor))

        add(constraint: textView.topAnchor.constraint(equalTo: headerView.bottomAnchor))
        add(constraint: textView.leadingAnchor.constraint(equalTo: container.leadingAnchor))
        add(constraint: textView.trailingAnchor.constraint(equalTo: container.trailingAnchor))
        add(constraint: textView.bottomAnchor.constraint(equalTo: container.bottomAnchor))

        container.setContentCompressionResistancePriority(.required, for: .vertical)

        return container
    }

    private func updateCodeBlockContainerColors(_ container: NSView) {
        if effectiveAppearance.it_isDark {
            container.layer?.borderColor = NSColor(white: 0.2, alpha: 1.0).cgColor
        } else {
            container.layer?.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
        }
    }

    private func createContainer(for view: NSView, isCodeAttachment: Bool, isStatusUpdate: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        if isStatusUpdate {
            // Center status updates horizontally
            add(constraint: view.centerXAnchor.constraint(equalTo: container.centerXAnchor))
            add(constraint: view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16))
            add(constraint: view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16))
        } else if isCodeAttachment {
            // Indent code attachments
            add(constraint: view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16))
            add(constraint: view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0))
        } else {
            // Regular text has no extra indentation and should fill the width
            add(constraint: view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0))
            add(constraint: view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0))

            // For regular text, also add a width constraint to ensure it expands
            add(constraint: view.widthAnchor.constraint(equalTo: container.widthAnchor))
        }

        add(constraint: view.topAnchor.constraint(equalTo: container.topAnchor))
        add(constraint: view.bottomAnchor.constraint(equalTo: container.bottomAnchor))

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
            textView.layer?.borderWidth = 1.0
        }
    }

    private func updateCodeBlockHeaderColors(_ headerView: NSView) {
        if effectiveAppearance.it_isDark {
            headerView.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1.0).cgColor
        } else {
            headerView.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1.0).cgColor
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
