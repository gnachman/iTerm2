//
//  TerminalCommandMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/23/25.
//

class TerminalCommandCellContainer: NSView {}

class TerminalCommandMessageCellView: MessageCellView {
    private var url: URL?
    private let bubbleView: TerminalCommandCellContainer = {
        let view = TerminalCommandCellContainer()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        return view
    }()
    private let icon: NSImageView = {
        let image: NSImage = {
            if #available(macOS 11, *) {
                let image = NSImage(systemSymbolName: SFSymbol.desktopcomputer.rawValue,
                                    accessibilityDescription: "Command icon")!
                if #available(macOS 12, *) {
                    return image.withSymbolConfiguration(.init(paletteColors: [.white, .clear, .black]))!
                }
                return image
            }
            return NSImage.it_imageNamed("CommandIcon",
                                         for: TerminalCommandMessageCellView.self)!
        }()
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
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
        tv.textContainer?.widthTracksTextView = false
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
        textField.alignment = .right
        return textField
    }()
    private var clickRecognizer: NSClickGestureRecognizer!

    static let bubbleInset: CGFloat = 8
    static let bubbleEdgePadding: CGFloat = 8
    static let stackSpacing: CGFloat = 4
    static let iconSize: CGFloat = 40
    static let timestampGap: CGFloat = 8

    override func configure(with rendition: MessageRendition,
                            maxBubbleWidth: CGFloat) {
        guard case .command(let commandFlavor) = rendition.flavor else {
            it_fatalError()
        }
        configuredMaxBubbleWidth = maxBubbleWidth
        self.url = commandFlavor.url

        bubbleView.removeFromSuperview()
        timestamp.removeFromSuperview()

        addSubview(bubbleView)
        bubbleView.addSubview(icon)
        bubbleView.addSubview(textLabel)

        let attributedString = NSAttributedString(
            string: commandFlavor.command,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                   weight: .regular),
                .foregroundColor: NSColor.white
            ])
        textLabel.textStorage?.setAttributedString(attributedString)
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - Self.bubbleInset * 2,
                                               height: .greatestFiniteMagnitude)
        textLabel.linkTextAttributes = [.foregroundColor: NSColor.textColor]

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
        let textContentWidth = max(0, maxBubble - Self.bubbleInset * 2)
        let textSize = textLabel.desiredSize(forContentWidth: textContentWidth)
        let textWidth = ceil(textSize.width)
        let textHeight = ceil(textSize.height)
        let stackContentWidth = max(Self.iconSize, textWidth)
        let bubbleWidth = min(maxBubble, stackContentWidth + Self.bubbleInset * 2)
        let stackInnerWidth = bubbleWidth - Self.bubbleInset * 2
        let stackInnerHeight = Self.iconSize + Self.stackSpacing + textHeight
        let bubbleHeight = stackInnerHeight + Self.bubbleInset * 2

        // Right-aligned bubble.
        let bubbleX = max(Self.bubbleEdgePadding,
                          bounds.maxX - Self.bubbleEdgePadding - bubbleWidth)
        let bubbleY = Self.bottomInset
        bubbleView.frame = NSRect(x: bubbleX,
                                  y: bubbleY,
                                  width: bubbleWidth,
                                  height: bubbleHeight)

        // Inside bubble: icon at top-center, text below it.
        let iconX = Self.bubbleInset + floor((stackInnerWidth - Self.iconSize) / 2)
        let iconY = bubbleHeight - Self.bubbleInset - Self.iconSize
        icon.frame = NSRect(x: iconX,
                            y: iconY,
                            width: Self.iconSize,
                            height: Self.iconSize)

        let textX = Self.bubbleInset + floor((stackInnerWidth - textWidth) / 2)
        let textY = iconY - Self.stackSpacing - textHeight
        textLabel.frame = NSRect(x: textX,
                                 y: textY,
                                 width: textWidth,
                                 height: textHeight)

        if timestamp.superview != nil {
            timestamp.sizeToFit()
            let ts = timestamp.frame.size
            timestamp.frame = NSRect(x: bubbleX - Self.timestampGap - ts.width,
                                     y: bubbleY,
                                     width: ts.width,
                                     height: ts.height)
        }
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

    static func cellHeight(for rendition: MessageRendition,
                           tableViewWidth: CGFloat) -> CGFloat {
        guard case .command(let cmd) = rendition.flavor else {
            return 0
        }
        let maxBubble = maxBubbleWidth(tableViewWidth: tableViewWidth)
        let textContentWidth = max(0, maxBubble - bubbleInset * 2)
        let attributedString = NSAttributedString(
            string: cmd.command,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                   weight: .regular),
                .foregroundColor: NSColor.white
            ])
        let textHeight = ceil(measureMonospaceText(attributedString,
                                                   contentWidth: textContentWidth))
        let stackInnerHeight = iconSize + stackSpacing + textHeight
        let bubbleHeight = stackInnerHeight + bubbleInset * 2
        return topInset + bubbleHeight + bottomInset
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
}
