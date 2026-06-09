//
//  TerminalCommandMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/23/25.
//

class TerminalCommandMessageCellView: MessageCellView {
    private var url: URL?
    private var commandText = ""
    private var outputText = ""
    private let textLabel: AutoSizingTextView = {
        let tv = AutoSizingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.textContainer?.widthTracksTextView = false
        return tv
    }()
    private let outputBlock = ChatCodeBlockView()
    private let timestamp: MessageTimestamp = {
        let textField = MessageTimestamp()
        textField.isEditable = false
        textField.isSelectable = false
        textField.drawsBackground = false
        textField.isBordered = false
        textField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.alphaValue = 0.65
        textField.alignment = .right
        return textField
    }()
    private var clickRecognizer: NSClickGestureRecognizer!

    static let bubbleEdgePadding: CGFloat = 40
    static let timestampGap: CGFloat = 6
    static let labelToOutputSpacing: CGFloat = 14

    override func configure(with rendition: MessageRendition,
                            maxBubbleWidth: CGFloat) {
        guard case .command(let commandFlavor) = rendition.flavor else {
            it_fatalError()
        }
        configuredMaxBubbleWidth = maxBubbleWidth
        self.url = commandFlavor.url
        self.commandText = commandFlavor.command
        self.outputText = commandFlavor.output

        textLabel.removeFromSuperview()
        outputBlock.removeFromSuperview()
        timestamp.removeFromSuperview()

        addSubview(textLabel)

        textLabel.textStorage?.setAttributedString(Self.attributedCommand(commandFlavor.command))
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth,
                                               height: .greatestFiniteMagnitude)
        textLabel.linkTextAttributes = [.foregroundColor: NSColor.textColor]

        if !commandFlavor.output.isEmpty {
            addSubview(outputBlock)
            outputBlock.configure(code: commandFlavor.output, title: "Output")
            outputBlock.setSelectable(textSelectable)
        }

        timestamp.stringValue = rendition.timestamp
        if !rendition.timestamp.isEmpty {
            addSubview(timestamp)
        }

        messageUniqueID = rendition.messageUniqueID
        editable = rendition.isEditable
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let maxBubble = configuredMaxBubbleWidth
        guard maxBubble > 0 else { return }
        let textSize = textLabel.desiredSize(forContentWidth: maxBubble)
        let textHeight = ceil(textSize.height)

        let contentX = Self.bubbleEdgePadding
        var y = Self.bottomInset

        var contentWidth = min(maxBubble, max(220, ceil(textSize.width)))
        if outputBlock.superview != nil {
            let outputSize = outputBlock.desiredSize(forContentWidth: maxBubble)
            contentWidth = max(contentWidth, outputSize.width)
            outputBlock.frame = NSRect(x: contentX,
                                       y: y,
                                       width: outputSize.width,
                                       height: outputSize.height)
            y += outputSize.height + Self.labelToOutputSpacing
        }

        textLabel.frame = NSRect(x: contentX,
                                 y: y,
                                 width: contentWidth,
                                 height: textHeight)

        if timestamp.superview != nil {
            timestamp.sizeToFit()
            let ts = timestamp.frame.size
            timestamp.frame = NSRect(x: contentX + contentWidth + Self.timestampGap,
                                     y: Self.bottomInset,
                                     width: ts.width,
                                     height: ts.height)
        }
    }

    @objc private func handleClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: self)
        if outputBlock.superview != nil && outputBlock.frame.contains(point) {
            return
        }
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    override func copyMenuItemClicked(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if outputText.isEmpty {
            pasteboard.setString(commandText, forType: .string)
        } else {
            pasteboard.setString("Ran \(commandText)\n\n\(outputText)", forType: .string)
        }
    }

    override func setupViews() {
        updateColors()
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        recognizer.isEnabled = true
        self.clickRecognizer = recognizer
        addGestureRecognizer(recognizer)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if textSelectable {
            return super.hitTest(point)
        }
        return self
    }

    override func updateColors() {
        outputBlock.updateColors()
    }

    private static func attributedCommand(_ command: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "Ran ",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        result.append(NSAttributedString(
            string: command,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                   weight: .regular),
                .foregroundColor: NSColor.textColor
            ]))
        return result
    }

    static func cellHeight(for rendition: MessageRendition,
                           tableViewWidth: CGFloat) -> CGFloat {
        guard case .command(let cmd) = rendition.flavor else {
            return 0
        }
        let maxBubble = maxBubbleWidth(tableViewWidth: tableViewWidth)
        let attributedString = attributedCommand(cmd.command)
        let textHeight = ceil(measureMonospaceText(attributedString,
                                                   contentWidth: maxBubble))
        let outputHeight: CGFloat
        if cmd.output.isEmpty {
            outputHeight = 0
        } else {
            outputHeight = measureCodeBlock(cmd.output, contentWidth: maxBubble)
                + labelToOutputSpacing
        }
        return topInset + textHeight + outputHeight + bottomInset
    }

    private static func measureMonospaceText(_ attributedString: NSAttributedString,
                                             contentWidth: CGFloat) -> CGFloat {
        if attributedString.length == 0 || contentWidth <= 0 {
            return 0
        }
        let storage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: contentWidth,
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let glyphRange = layoutManager.glyphRange(for: container)
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container).maxY
    }

    private static func measureCodeBlock(_ code: String,
                                         contentWidth: CGFloat) -> CGFloat {
        let innerWidth = max(0, contentWidth - ChatCodeBlockView.textHorizontalPadding * 2)
        let textHeight = measureMonospaceText(ChatCodeBlockView.attributedCodeString(code),
                                              contentWidth: innerWidth)
        let bodyHeight = max(ChatCodeBlockView.minimumHeight,
                             ceil(textHeight) + ChatCodeBlockView.textVerticalPadding * 2)
        return ChatCodeBlockView.headerHeight + bodyHeight
    }
}
