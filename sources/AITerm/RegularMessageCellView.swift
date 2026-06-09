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

final class ChatCodeBlockView: NSView {
    static let headerHeight: CGFloat = 34
    static let textHorizontalPadding: CGFloat = 16
    static let textVerticalPadding: CGFloat = 12
    static let minimumHeight: CGFloat = 44

    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let textView = AutoSizingTextView()
    private(set) var code = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        headerView.wantsLayer = true
        addSubview(headerView)

        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false
        headerView.addSubview(titleLabel)

        copyButton.refusesFirstResponder = true
        copyButton.title = ""
        if #available(macOS 15, *) {
            copyButton.image = NSImage.it_image(forSymbolName: SFSymbol.documentOnDocument.rawValue,
                                                accessibilityDescription: "Copy",
                                                fallbackImageName: "document.on.document",
                                                for: ChatCodeBlockView.self)
        } else {
            copyButton.image = NSImage.it_image(forSymbolName: SFSymbol.docOnDoc.rawValue,
                                                accessibilityDescription: "Copy",
                                                fallbackImageName: "document.on.document",
                                                for: ChatCodeBlockView.self)
        }
        copyButton.toolTip = "Copy code"
        copyButton.bezelStyle = .smallSquare
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.controlSize = .small
        copyButton.target = self
        copyButton.action = #selector(copyCode(_:))
        headerView.addSubview(copyButton)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = false
        addSubview(textView)

        updateColors()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func configure(code: String, title: String) {
        self.code = code
        titleLabel.stringValue = title
        textView.textStorage?.setAttributedString(Self.attributedCodeString(code))
    }

    func setSelectable(_ selectable: Bool) {
        textView.isSelectable = selectable
    }

    func desiredSize(forContentWidth width: CGFloat) -> NSSize {
        let innerWidth = max(0, width - Self.textHorizontalPadding * 2)
        let textSize = textView.desiredSize(forContentWidth: innerWidth)
        let textHeight = max(Self.minimumHeight,
                             ceil(textSize.height) + Self.textVerticalPadding * 2)
        return NSSize(width: width,
                      height: Self.headerHeight + textHeight)
    }

    override func layout() {
        super.layout()
        headerView.frame = NSRect(x: 0,
                                  y: bounds.height - Self.headerHeight,
                                  width: bounds.width,
                                  height: Self.headerHeight)

        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(x: Self.textHorizontalPadding,
                                  y: floor((Self.headerHeight - titleLabel.frame.height) / 2),
                                  width: min(titleLabel.frame.width,
                                             max(0, headerView.bounds.width - 72)),
                                  height: titleLabel.frame.height)

        copyButton.sizeToFit()
        let copySize = copyButton.frame.size
        copyButton.frame = NSRect(x: headerView.bounds.width - Self.textHorizontalPadding - copySize.width,
                                  y: floor((Self.headerHeight - copySize.height) / 2),
                                  width: copySize.width,
                                  height: copySize.height)

        textView.frame = NSRect(x: Self.textHorizontalPadding,
                                y: Self.textVerticalPadding,
                                width: max(0, bounds.width - Self.textHorizontalPadding * 2),
                                height: max(0,
                                            bounds.height - Self.headerHeight - Self.textVerticalPadding * 2))
    }

    func updateColors() {
        let dark = effectiveAppearance.it_isDark
        layer?.backgroundColor = (dark
                                  ? NSColor(fromHexString: "#181818")!
                                  : NSColor(fromHexString: "#f3f3f3")!).cgColor
        layer?.borderColor = (dark
                              ? NSColor(fromHexString: "#2f2f2f")!
                              : NSColor(fromHexString: "#dedede")!).cgColor
        headerView.layer?.backgroundColor = (dark
                                             ? NSColor(fromHexString: "#1f1f1f")!
                                             : NSColor(fromHexString: "#e9e9e9")!).cgColor
        titleLabel.textColor = dark ? NSColor(fromHexString: "#f3f3f3")! : NSColor(fromHexString: "#222222")!
        copyButton.contentTintColor = dark ? .white : .black
    }

    static func attributedCodeString(_ string: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.lineHeightMultiple = 1.15
        return NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)
                    ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                   weight: .regular),
                .foregroundColor: NSColor.it_dynamicColor(
                    forLightMode: NSColor(fromHexString: "#1f1f1f")!,
                    darkMode: NSColor(fromHexString: "#f6f6f6")!),
                .paragraphStyle: paragraphStyle
            ])
    }

    @objc private func copyCode(_ sender: NSButton) {
        NSPasteboard.general.declareTypes([.string], owner: NSApp)
        NSPasteboard.general.setString(code, forType: .string)
        let localPoint = NSPoint(x: sender.bounds.midX, y: sender.bounds.midY)
        let windowPoint = sender.convert(localPoint, to: nil)
        let screenPoint = window?.convertPoint(toScreen: windowPoint) ?? NSEvent.mouseLocation
        ToastWindowController.showToast(withMessage: "Copied",
                                        duration: 1,
                                        screenCoordinate: screenPoint,
                                        pointSize: 12)
    }
}

@objc
class RegularMessageCellView: MessageCellView {
    let bubbleView = BubbleView()

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
    private var contentSegments: [ContentSegment] = []
    private var renderedString = ""

    var buttonClicked: ((String, UUID) -> Void)?

    private var backgroundColorPair: (NSColor, NSColor)?
    private var isUserMessage: Bool = false
    private var drawsBubbleChrome: Bool = true
    private var keepsButtonsEnabledAfterClick: Bool = false

    static let textHorizontalPadding: CGFloat = 12
    static let textVerticalPadding: CGFloat = 8
    static let separatorHeight: CGFloat = 1
    static let buttonHeight: CGFloat = 30
    static let buttonsBottomSpacer: CGFloat = 1
    static let inlineButtonHeight: CGFloat = 30
    static let inlineButtonSpacing: CGFloat = 8
    static let inlineButtonTopGap: CGFloat = 10
    static let inlineButtonHorizontalPadding: CGFloat = 30
    static let bubbleEdgePadding: CGFloat = 40
    static let timestampGap: CGFloat = 6
    static let contentSegmentSpacing: CGFloat = 12

    private enum ContentSegment {
        case text(AutoSizingTextView)
        case code(ChatCodeBlockView)

        var view: NSView {
            switch self {
            case .text(let textView):
                return textView
            case .code(let codeView):
                return codeView
            }
        }

        var string: String {
            switch self {
            case .text(let textView):
                return textView.string
            case .code(let codeView):
                return codeView.code
            }
        }

        func desiredSize(forContentWidth width: CGFloat) -> NSSize {
            switch self {
            case .text(let textView):
                return textView.desiredSize(forContentWidth: width)
            case .code(let codeView):
                return codeView.desiredSize(forContentWidth: width)
            }
        }

        func setSelectable(_ selectable: Bool) {
            switch self {
            case .text(let textView):
                textView.isSelectable = selectable
            case .code(let codeView):
                codeView.setSelectable(selectable)
            }
        }

        func updateColors() {
            switch self {
            case .text:
                break
            case .code(let codeView):
                codeView.updateColors()
            }
        }
    }

    override func setupViews() {
        super.setupViews()
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
    }

    override var description: String {
        "<\(Self.self): \(it_addressString) editable=\(editable) text=\(renderedString)>"
    }

    override func updateColors() {
        updateBubbleColor()
        contentSegments.forEach { $0.updateColors() }
    }

    private func updateBubbleColor() {
        guard drawsBubbleChrome else {
            bubbleView.layer?.backgroundColor = NSColor.clear.cgColor
            bubbleView.layer?.borderWidth = 0
            return
        }
        guard let (lightColor, darkColor) = backgroundColorPair else { return }
        bubbleView.layer?.backgroundColor = (effectiveAppearance.it_isDark ? darkColor : lightColor).cgColor
    }

    override var textSelectable: Bool {
        didSet {
            contentSegments.forEach { $0.setSelectable(textSelectable) }
        }
    }

    override func configure(with rendition: MessageRendition,
                            maxBubbleWidth: CGFloat) {
        guard case .regular(let regular) = rendition.flavor else {
            it_fatalError()
        }
        configuredMaxBubbleWidth = maxBubbleWidth
        isUserMessage = rendition.isUser
        drawsBubbleChrome = shouldDrawBubbleChrome(for: rendition)
        keepsButtonsEnabledAfterClick = regular.keepsButtonsEnabledAfterClick

        bubbleView.removeFromSuperview()
        for segment in contentSegments {
            segment.view.removeFromSuperview()
        }
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
        contentSegments.removeAll()

        addSubview(bubbleView)
        renderedString = regular.attributedString.string
        contentSegments = Self.makeContentSegments(from: regular.attributedString,
                                                   linkColor: rendition.linkColor)
        for segment in contentSegments {
            bubbleView.addSubview(segment.view)
            segment.setSelectable(textSelectable)
        }

        backgroundColorPair = backgroundColorPair(rendition)
        updateBubbleColor()

        timestamp.stringValue = rendition.timestamp
        if !rendition.timestamp.isEmpty {
            addSubview(timestamp)
        }

        for buttonRendition in regular.buttons {
            if drawsBubbleChrome {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
                bubbleView.addSubview(separator)
                separators.append(separator)
            }

            let button = NSButton(title: buttonRendition.title,
                                  target: self,
                                  action: #selector(buttonTapped(_:)))
            button.wantsLayer = true
            if drawsBubbleChrome {
                button.isBordered = false
            } else {
                button.isBordered = false
                button.controlSize = .small
                button.layer?.cornerRadius = Self.inlineButtonHeight / 2
                button.layer?.masksToBounds = true
                button.layer?.backgroundColor = inlineButtonBackgroundColor(buttonRendition).cgColor
            }
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
                    .foregroundColor: buttonTitleColor(buttonRendition),
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
            if drawsBubbleChrome {
                bubbleView.addSubview(spacer)
            }
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
        let segmentSizes = contentSegments.map {
            $0.desiredSize(forContentWidth: textContentWidth)
        }
        let contentMetrics = Self.contentMetrics(fromSegmentSizes: segmentSizes)
        let contentTextWidth = ceil(contentMetrics.width)
        let inlineButtonWidths = buttons.map { Self.inlineButtonWidth(for: $0.button.title) }
        let inlineButtonsWidth = Self.inlineButtonsWidth(inlineButtonWidths)
        let contentWidth = max(contentTextWidth, inlineButtonsWidth)
        let bubbleWidth = min(maxBubble, contentWidth + Self.textHorizontalPadding * 2)
        let actualContentWidth = max(0, bubbleWidth - Self.textHorizontalPadding * 2)
        let actualSegmentSizes = contentSegments.map {
            $0.desiredSize(forContentWidth: actualContentWidth)
        }
        let actualContentMetrics = Self.contentMetrics(fromSegmentSizes: actualSegmentSizes)
        let containerHeight = ceil(actualContentMetrics.height) + Self.textVerticalPadding * 2

        let buttonRowsHeight: CGFloat
        let bottomSpacerHeight: CGFloat
        if drawsBubbleChrome {
            buttonRowsHeight = CGFloat(buttons.count) * (Self.separatorHeight + Self.buttonHeight)
            bottomSpacerHeight = buttons.isEmpty ? 0 : Self.buttonsBottomSpacer
        } else if buttons.isEmpty {
            buttonRowsHeight = 0
            bottomSpacerHeight = 0
        } else {
            buttonRowsHeight = Self.inlineButtonTopGap + Self.inlineButtonHeight
            bottomSpacerHeight = 0
        }
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
        var segmentTop = bubbleHeight - Self.textVerticalPadding
        for (index, segment) in contentSegments.enumerated() {
            let segmentSize = actualSegmentSizes[index]
            segmentTop -= ceil(segmentSize.height)
            segment.view.frame = NSRect(x: Self.textHorizontalPadding,
                                        y: segmentTop,
                                        width: actualContentWidth,
                                        height: ceil(segmentSize.height))
            segmentTop -= Self.contentSegmentSpacing
        }

        if drawsBubbleChrome {
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
        } else {
            bottomSpacer?.frame = .zero
            var x = Self.textHorizontalPadding
            for i in 0..<buttons.count {
                let button = buttons[i].button
                let width = inlineButtonWidths[i]
                button.frame = NSRect(x: x,
                                      y: 0,
                                      width: width,
                                      height: Self.inlineButtonHeight)
                x += width + Self.inlineButtonSpacing
            }
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
        ? (NSColor(fromHexString: "p3#303033")!, NSColor(fromHexString: "p3#303033")!)
        : (NSColor(fromHexString: "p3#e9e9eb")!, NSColor(fromHexString: "p3#3b3b3d")!)
    }

    func shouldDrawBubbleChrome(for rendition: MessageRendition) -> Bool {
        return rendition.isUser
    }

    private static func inlineButtonWidth(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(max(72, textWidth + inlineButtonHorizontalPadding))
    }

    private static func inlineButtonsWidth(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else {
            return 0
        }
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * inlineButtonSpacing
    }

    private func buttonTitleColor(_ button: MessageRendition.Regular.Button) -> NSColor {
        if drawsBubbleChrome {
            return button.color
        }
        return button.destructive ? .secondaryLabelColor : .white
    }

    private func inlineButtonBackgroundColor(_ button: MessageRendition.Regular.Button) -> NSColor {
        if button.destructive {
            return effectiveAppearance.it_isDark
                ? NSColor(white: 0.18, alpha: 1.0)
                : NSColor(white: 0.88, alpha: 1.0)
        }
        return NSColor.controlAccentColor
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
        pasteboard.setString(renderedString, forType: .string)
    }

    static func cellHeight(for rendition: MessageRendition,
                           tableViewWidth: CGFloat) -> CGFloat {
        guard case .regular(let regular) = rendition.flavor else {
            return 0
        }
        let maxBubble = maxBubbleWidth(tableViewWidth: tableViewWidth)
        let textContentWidth = max(0, maxBubble - textHorizontalPadding * 2)
        let contentMetrics = measuredContentMetrics(for: regular.attributedString,
                                                    contentWidth: textContentWidth)
        let containerHeight = ceil(contentMetrics.height) + textVerticalPadding * 2
        let drawsBubbleChrome = rendition.isUser
        let buttonRowsHeight: CGFloat
        let bottomSpacerHeight: CGFloat
        if drawsBubbleChrome {
            buttonRowsHeight = CGFloat(regular.buttons.count) *
                (separatorHeight + buttonHeight)
            bottomSpacerHeight = regular.buttons.isEmpty ? 0 : buttonsBottomSpacer
        } else if regular.buttons.isEmpty {
            buttonRowsHeight = 0
            bottomSpacerHeight = 0
        } else {
            buttonRowsHeight = inlineButtonTopGap + inlineButtonHeight
            bottomSpacerHeight = 0
        }
        let bubbleHeight = containerHeight + buttonRowsHeight + bottomSpacerHeight
        return topInset + bubbleHeight + bottomInset
    }

    private static func makeContentSegments(from attributedString: NSAttributedString,
                                            linkColor: NSColor) -> [ContentSegment] {
        var segments = [ContentSegment]()
        let codeRanges = mergedCodeBlockRanges(in: attributedString)
        var cursor = 0

        func appendText(range: NSRange) {
            guard range.length > 0 else {
                return
            }
            let substring = attributedString.string.substring(nsrange: range)
            guard !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let textView = makeTextView()
            textView.linkTextAttributes = [.foregroundColor: linkColor]
            textView.textStorage?.setAttributedString(attributedString.attributedSubstring(from: range))
            segments.append(.text(textView))
        }

        for codeRange in codeRanges {
            appendText(range: NSRange(location: cursor,
                                      length: codeRange.location - cursor))
            let rawCode = attributedString.string.substring(nsrange: codeRange)
            let code = trimmedCodeBlockText(rawCode)
            let codeView = ChatCodeBlockView()
            codeView.configure(code: code, title: codeBlockTitle(for: code))
            segments.append(.code(codeView))
            cursor = NSMaxRange(codeRange)
        }

        appendText(range: NSRange(location: cursor,
                                  length: attributedString.length - cursor))

        if segments.isEmpty {
            let textView = makeTextView()
            textView.linkTextAttributes = [.foregroundColor: linkColor]
            textView.textStorage?.setAttributedString(attributedString)
            segments.append(.text(textView))
        }
        return segments
    }

    private static func makeTextView() -> AutoSizingTextView {
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
    }

    private static func contentMetrics(fromSegmentSizes sizes: [NSSize]) -> NSSize {
        guard !sizes.isEmpty else {
            return .zero
        }
        let width = sizes.map { ceil($0.width) }.max() ?? 0
        let height = sizes.map { ceil($0.height) }.reduce(0, +)
            + CGFloat(max(0, sizes.count - 1)) * contentSegmentSpacing
        return NSSize(width: width, height: height)
    }

    private static func measuredContentMetrics(for attributedString: NSAttributedString,
                                               contentWidth: CGFloat) -> NSSize {
        let codeRanges = mergedCodeBlockRanges(in: attributedString)
        var cursor = 0
        var sizes = [NSSize]()

        func appendText(range: NSRange) {
            guard range.length > 0 else {
                return
            }
            let substring = attributedString.string.substring(nsrange: range)
            guard !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let attr = attributedString.attributedSubstring(from: range)
            sizes.append(measureAttributedString(attr, contentWidth: contentWidth))
        }

        for codeRange in codeRanges {
            appendText(range: NSRange(location: cursor,
                                      length: codeRange.location - cursor))
            let rawCode = attributedString.string.substring(nsrange: codeRange)
            let code = trimmedCodeBlockText(rawCode)
            sizes.append(measureCodeBlock(code, contentWidth: contentWidth))
            cursor = NSMaxRange(codeRange)
        }
        appendText(range: NSRange(location: cursor,
                                  length: attributedString.length - cursor))
        return contentMetrics(fromSegmentSizes: sizes)
    }

    private static func measureCodeBlock(_ code: String,
                                         contentWidth: CGFloat) -> NSSize {
        let innerWidth = max(0, contentWidth - ChatCodeBlockView.textHorizontalPadding * 2)
        let textHeight = measureText(ChatCodeBlockView.attributedCodeString(code),
                                     contentWidth: innerWidth)
        let bodyHeight = max(ChatCodeBlockView.minimumHeight,
                             ceil(textHeight) + ChatCodeBlockView.textVerticalPadding * 2)
        return NSSize(width: contentWidth,
                      height: ChatCodeBlockView.headerHeight + bodyHeight)
    }

    private static func mergedCodeBlockRanges(in attributedString: NSAttributedString) -> [NSRange] {
        var ranges = [NSRange]()
        let wholeRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(
            NSAttributedString.Key.swiftyMarkdownLineStyle,
            in: wholeRange,
            options: []) { value, range, _ in
                guard value as? String == "codeblock" else {
                    return
                }
                if let previous = ranges.last {
                    let betweenRange = NSRange(location: NSMaxRange(previous),
                                               length: range.location - NSMaxRange(previous))
                    let between = attributedString.string.substring(nsrange: betweenRange)
                    if between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ranges.removeLast()
                        ranges.append(NSRange(location: previous.location,
                                              length: NSMaxRange(range) - previous.location))
                        return
                    }
                }
                ranges.append(range)
            }
        return ranges
    }

    private static func trimmedCodeBlockText(_ string: String) -> String {
        var result = string
        while result.first?.isNewline == true {
            result.removeFirst()
        }
        while result.last?.isNewline == true {
            result.removeLast()
        }
        return result
    }

    private static func codeBlockTitle(for code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? ""
        if firstLine.hasPrefix("total ") ||
            firstLine.range(of: #"^[dl-][rwx-]{9}"#, options: .regularExpression) != nil {
            return "Text"
        }

        let shellCommands: Set<String> = [
            "awk", "cat", "chmod", "cp", "curl", "dig", "du", "echo", "egrep",
            "find", "free", "grep", "head", "ls", "make", "mkdir", "mv", "ps",
            "pwd", "rm", "sed", "scutil", "sort", "tail", "top", "traceroute",
            "vm_stat", "vmstat", "which"
        ]
        let commandName = firstLine
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" || $0 == ";" })
            .first
            .map(String.init) ?? ""
        if shellCommands.contains(commandName) ||
            firstLine.contains(" && ") ||
            firstLine.contains(" | ") {
            return "Bash"
        }
        return trimmed.contains("\n") ? "Text" : "Code"
    }

    // Used by both layout() (via AutoSizingTextView.desiredSize) and the
    // static height helper. The static helper has no live AutoSizingTextView
    // so it builds an NSLayoutManager configured the same way.
    private static func measureText(_ attributedString: NSAttributedString,
                                    contentWidth: CGFloat) -> CGFloat {
        return measureAttributedString(attributedString,
                                       contentWidth: contentWidth).height
    }

    private static func measureAttributedString(_ attributedString: NSAttributedString,
                                                contentWidth: CGFloat) -> NSSize {
        if attributedString.length == 0 || contentWidth <= 0 {
            return .zero
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
        let used = layoutManager.usedRect(for: container)
        return NSSize(width: ceil(max(used.maxX, bounding.maxX)),
                      height: ceil(bounding.maxY))
    }
}
