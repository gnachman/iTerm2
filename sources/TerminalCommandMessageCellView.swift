//
//  TerminalCommandMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/23/25.
//

class TerminalCommandCellContainer: NSView {}

class TerminalCommandMessageCellView: MessageCellView {
    private var url: URL?
    private let bubbleView = {
        let view = TerminalCommandCellContainer()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        return view
    }()
    private let icon: NSImageView = {
        let image = {
            if #available(macOS 11, *) {
                let image = NSImage.init(systemSymbolName: "desktopcomputer", accessibilityDescription: "Command icon")!
                if #available(macOS 12, *) {
                    return image.withSymbolConfiguration(.init(paletteColors: [.white, .clear, .black]))!
                } else {
                    return image
                }
            } else {
                return NSImage.it_imageNamed("CommandIcon",
                                             for: TerminalCommandMessageCellView.self)!
            }
        }()
        let view = NSImageView(image: image)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }()
    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
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
    private var clickRecognizer: NSClickGestureRecognizer!

    override func configure(with rendition: MessageRendition, maxBubbleWidth: CGFloat) {
        guard case .command(let commandFlavor) = rendition.flavor else {
            it_fatalError()
        }
        NSLayoutConstraint.deactivate(customConstraints)
        customConstraints = []
        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        timestamp.removeFromSuperview()
        bubbleView.removeFromSuperview()

        self.url = commandFlavor.url

        addSubview(bubbleView)
        bubbleView.addSubview(contentStack)
        contentStack.addArrangedSubview(icon)
        contentStack.addArrangedSubview(textLabel)
        let attributedString = NSAttributedString(
            string: commandFlavor.command,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                   weight: .regular),
                .foregroundColor: NSColor.white
            ])
        textLabel.textStorage?.setAttributedString(attributedString)
        textLabel.textContainer?.widthTracksTextView = false
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - 16,
                                               height: .greatestFiniteMagnitude)
        textLabel.linkTextAttributes = [.foregroundColor: NSColor.textColor]

        add(constraint: icon.widthAnchor.constraint(equalToConstant: 40))
        add(constraint: icon.heightAnchor.constraint(equalToConstant: 40))
        timestamp.stringValue = rendition.timestamp
        if !rendition.timestamp.isEmpty {
            addSubview(timestamp)
            add(constraint: timestamp.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor))

            add(constraint: timestamp.rightAnchor.constraint(equalTo: bubbleView.leftAnchor,
                                                             constant: -8))
        }
        add(constraint: bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8))
        add(constraint: bubbleView.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset))
        add(constraint: bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8))
        add(constraint: bubbleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomInset))

        // Inset contentStack in container
        add(constraint: contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8))
        add(constraint: contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8))
        add(constraint: contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8))
        add(constraint: contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8))

        // Finally cap the total width
        let widthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth)
        maxWidthConstraint = widthConstraint
        add(constraint: widthConstraint)

        messageUniqueID = rendition.messageUniqueID
        editable = rendition.isEditable
    }

    @objc private func handleClick(_ sender: Any) {
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    override func copyMenuItemClicked(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textLabel.string, forType: .string)
    }

    override func setupViews() {
        updateColors()
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        recognizer.isEnabled = true
        self.clickRecognizer = recognizer
        addGestureRecognizer(recognizer)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func updateColors() {
        let (lightColor, darkColor) = (NSColor(fromHexString: "p3#448bf7")!,
                                       NSColor(fromHexString: "p3#4a93f5")!)
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }
}
