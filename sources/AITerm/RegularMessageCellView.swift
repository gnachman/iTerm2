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
    let bubbleView = BubbleView()

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

    private var buttons: [(button: NSButton, identifier: String, messageUniqueID: UUID)] = []
    private var separators: [NSView] = []
    private var bottomSpacer: NSView?

    var buttonClicked: ((String, UUID) -> Void)?

    private var backgroundColorPair: (NSColor, NSColor)?
    private var isUserMessage: Bool = false
    private var keepsButtonsEnabledAfterClick: Bool = false

    static let textHorizontalPadding: CGFloat = 8
    static let textVerticalPadding: CGFloat = 8
    static let separatorHeight: CGFloat = 1
    static let buttonHeight: CGFloat = 30
    static let buttonsBottomSpacer: CGFloat = 1
    static let bubbleEdgePadding: CGFloat = 8
    static let timestampGap: CGFloat = 8

    override func setupViews() {
        super.setupViews()
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
    }

    override var description: String {
        "<\(Self.self): \(it_addressString) editable=\(editable) text=\(textLabel.textStorage?.string ?? "(nil)")>"
    }

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
        configuredMaxBubbleWidth = maxBubbleWidth
        isUserMessage = rendition.isUser
        keepsButtonsEnabledAfterClick = regular.keepsButtonsEnabledAfterClick

        bubbleView.removeFromSuperview()
        textLabel.removeFromSuperview()
        timestamp.removeFromSuperview()
        for entry in buttons {
            entry.button.removeFromSuperview()
        }
        for sep in separators {
            sep.removeFromSuperview()
        }
        bottomSpacer?.removeFromSuperview()
        bottomSpacer = nil
        buttons.removeAll()
        separators.removeAll()

        addSubview(bubbleView)
        bubbleView.addSubview(textLabel)

        backgroundColorPair = backgroundColorPair(rendition)
        updateBubbleColor()

        textLabel.textStorage?.setAttributedString(regular.attributedString)
        textLabel.textContainer?.size = NSSize(width: maxBubbleWidth - Self.textHorizontalPadding * 2,
                                               height: .greatestFiniteMagnitude)
        textLabel.linkTextAttributes = [.foregroundColor: rendition.linkColor]

        timestamp.stringValue = rendition.timestamp
        if !rendition.timestamp.isEmpty {
            addSubview(timestamp)
        }

        for buttonRendition in regular.buttons {
            let separator = NSView()
            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor.gray.cgColor
            bubbleView.addSubview(separator)
            separators.append(separator)

            let button = NSButton(title: buttonRendition.title,
                                  target: self,
                                  action: #selector(buttonTapped(_:)))
            button.isBordered = false
            button.wantsLayer = true
            // Don't take first-responder status on click. NSScrollView
            // auto-scrolls to keep the focused responder visible, which
            // would shove a tapped button (often near the bottom of the
            // visible area, partly under the input view's contentInset)
            // up into the unobstructed region — visually jarring.
            button.refusesFirstResponder = true
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
                ])
            button.attributedTitle = attrTitle
            if !regular.enableButtons {
                button.isEnabled = false
            }
            bubbleView.addSubview(button)
            buttons.append((button, buttonRendition.identifier, rendition.messageUniqueID))
        }

        if !regular.buttons.isEmpty {
            let spacer = NSView()
            bubbleView.addSubview(spacer)
            bottomSpacer = spacer
        }

        messageUniqueID = rendition.messageUniqueID
        editable = rendition.isEditable
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let maxBubble = configuredMaxBubbleWidth
        guard maxBubble > 0 else { return }
        let textContentWidth = max(0, maxBubble - Self.textHorizontalPadding * 2)
        let textSize = textLabel.desiredSize(forContentWidth: textContentWidth)
        let textWidth = ceil(textSize.width)
        let textHeight = ceil(textSize.height)
        let bubbleWidth = min(maxBubble, textWidth + Self.textHorizontalPadding * 2)
        let containerHeight = textHeight + Self.textVerticalPadding * 2

        let buttonRowsHeight = CGFloat(buttons.count) * (Self.separatorHeight + Self.buttonHeight)
        let bottomSpacerHeight: CGFloat = buttons.isEmpty ? 0 : Self.buttonsBottomSpacer
        let bubbleHeight = containerHeight + buttonRowsHeight + bottomSpacerHeight

        let bubbleX = bubbleOriginX(bubbleWidth: bubbleWidth)
        let bubbleY = Self.bottomInset
        bubbleView.frame = NSRect(x: bubbleX,
                                  y: bubbleY,
                                  width: bubbleWidth,
                                  height: bubbleHeight)

        // Inside the bubble (NSView coords: y=0 at bottom). Container is
        // visually at the top, so its y is high.
        let containerY = bubbleHeight - containerHeight
        textLabel.frame = NSRect(x: Self.textHorizontalPadding,
                                 y: containerY + Self.textVerticalPadding,
                                 width: bubbleWidth - Self.textHorizontalPadding * 2,
                                 height: textHeight)

        // Stack separator + button rows below the container, top-down.
        var nextTop = containerY
        for i in 0..<buttons.count {
            let separator = separators[i]
            nextTop -= Self.separatorHeight
            separator.frame = NSRect(x: 0,
                                     y: nextTop,
                                     width: bubbleWidth,
                                     height: Self.separatorHeight)

            let button = buttons[i].button
            nextTop -= Self.buttonHeight
            button.frame = NSRect(x: 0,
                                  y: nextTop,
                                  width: bubbleWidth,
                                  height: Self.buttonHeight)
        }
        if let bottomSpacer {
            nextTop -= Self.buttonsBottomSpacer
            bottomSpacer.frame = NSRect(x: 0,
                                        y: nextTop,
                                        width: bubbleWidth,
                                        height: Self.buttonsBottomSpacer)
        }

        if timestamp.superview != nil {
            timestamp.sizeToFit()
            let ts = timestamp.frame.size
            let tsX: CGFloat
            if isUserMessage {
                tsX = bubbleX - Self.timestampGap - ts.width
            } else {
                tsX = bubbleX + bubbleWidth + Self.timestampGap
            }
            timestamp.frame = NSRect(x: tsX,
                                     y: bubbleY,
                                     width: ts.width,
                                     height: ts.height)
        }
    }

    func bubbleOriginX(bubbleWidth: CGFloat) -> CGFloat {
        if isUserMessage {
            return max(Self.bubbleEdgePadding,
                       bounds.maxX - Self.bubbleEdgePadding - bubbleWidth)
        }
        return Self.bubbleEdgePadding
    }

    func backgroundColorPair(_ rendition: MessageRendition) -> (NSColor, NSColor) {
        rendition.isUser
        ? (NSColor(fromHexString: "p3#448bf7")!, NSColor(fromHexString: "p3#4a93f5")!)
        : (NSColor(fromHexString: "p3#e9e9eb")!, NSColor(fromHexString: "p3#3b3b3d")!)
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        // Disable BEFORE invoking the click handler. Some handlers
        // (e.g. .offerLink's "Enable Orchestration" path) run an
        // NSAlert modally and then publish a system-message bubble,
        // which synchronously inserts a row and reloads the
        // previously-last row. That reload destroys this cell view and
        // replaces it with a fresh one whose buttons are enabled. If
        // we disabled after the click ran, we'd be disabling the
        // detached button instances; the visible (new) cell would
        // still have clickable buttons and a second click could
        // re-trigger the action (or, worse, take a different branch
        // that fights the first one — e.g. Enable Orchestration
        // followed by Link, which then asserts in setTerminalGuid).
        if !keepsButtonsEnabledAfterClick {
            for entry in buttons {
                entry.button.isEnabled = false
            }
        }
        if let entry = buttons.first(where: { $0.button === sender }) {
            buttonClicked?(entry.identifier, entry.messageUniqueID)
        }
    }

    override func copyMenuItemClicked(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textLabel.string, forType: .string)
    }

    static func cellHeight(for rendition: MessageRendition,
                           tableViewWidth: CGFloat) -> CGFloat {
        guard case .regular(let regular) = rendition.flavor else {
            return 0
        }
        let maxBubble = maxBubbleWidth(tableViewWidth: tableViewWidth)
        let textContentWidth = max(0, maxBubble - textHorizontalPadding * 2)
        let textHeight = ceil(measureText(regular.attributedString,
                                          contentWidth: textContentWidth))
        let containerHeight = textHeight + textVerticalPadding * 2
        let buttonRowsHeight = CGFloat(regular.buttons.count) *
            (separatorHeight + buttonHeight)
        let bottomSpacerHeight: CGFloat = regular.buttons.isEmpty ? 0 : buttonsBottomSpacer
        let bubbleHeight = containerHeight + buttonRowsHeight + bottomSpacerHeight
        return topInset + bubbleHeight + bottomInset
    }

    // Used by both layout() (via AutoSizingTextView.desiredSize) and the
    // static height helper. The static helper has no live AutoSizingTextView
    // so it builds an NSLayoutManager configured the same way.
    private static func measureText(_ attributedString: NSAttributedString,
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
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return bounding.maxY
    }
}
