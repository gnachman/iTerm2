//
//  MultipartMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 6/2/25.
//

import AppKit

class CodeAttachmentTextView: AutoSizingTextView {}
class StatusUpdateTextView: AutoSizingTextView {}

class MultipartMessageCellView: MessageCellView {
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

    // Backing model for one laid-out subpart. Captures the rendered views
    // and the geometry helpers that layout() and cellHeight need.
    private struct LaidOutSubpart {
        enum Kind {
            case regular(textView: AutoSizingTextView)
            case statusUpdate(textView: AutoSizingTextView)
            case codeAttachment(container: NSView,
                                header: NSView,
                                textView: AutoSizingTextView)
            case fileAttachment(view: FileAttachmentSubpartView)
        }
        let kind: Kind
    }

    private var subparts: [LaidOutSubpart] = []
    private var bubbleSubviews: [NSView] = []  // direct children of bubbleView
    private var copyButtonsForCodeViews: [(button: NSButton, textView: NSTextView)] = []

    private var backgroundColorPair: (NSColor, NSColor)?
    private var isUserMessage: Bool = false
    private var drawsBubbleChrome: Bool = true

    private var textViews: [NSTextView] {
        subparts.flatMap { sp -> [NSTextView] in
            switch sp.kind {
            case .regular(let tv): return [tv]
            case .statusUpdate(let tv): return [tv]
            case .codeAttachment(_, _, let tv): return [tv]
            case .fileAttachment: return []
            }
        }
    }

    static let bubbleInsetTop: CGFloat = 8
    static let bubbleInsetBottom: CGFloat = 8
    static let bubbleInsetHorizontal: CGFloat = 12
    static let subpartSpacing: CGFloat = 8
    static let bubbleEdgePadding: CGFloat = 40
    static let timestampGap: CGFloat = 6
    static let minBubbleContentWidth: CGFloat = 200
    // Insets that text views apply inside their own bounds (lineFragmentPadding +
    // textContainerInset.width). For the regular text view both are 0; code/status
    // use 8pt of lineFragmentPadding on each side and 8pt vertical inset.
    static let regularTextSidePadding: CGFloat = 0
    static let codeTextSidePadding: CGFloat = 8
    static let codeTextVerticalPadding: CGFloat = 8
    static let codeBlockHeaderHeight: CGFloat = 32
    static let codeBlockBorder: CGFloat = 1
    static let fileAttachmentHeight: CGFloat = 32

    override func setupViews() {
        super.setupViews()
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 8
    }

    override func updateColors() {
        updateBubbleColor()
        for sp in subparts {
            switch sp.kind {
            case .codeAttachment(let container, let header, let textView):
                updateCodeBlockContainerColors(container)
                updateCodeBlockHeaderColors(header)
                updateCodeTextViewColors(textView)
            case .statusUpdate(let textView):
                updateStatusUpdateTextViewColors(textView)
            case .regular, .fileAttachment:
                break
            }
        }
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
            for tv in textViews { tv.isSelectable = textSelectable }
        }
    }

    override func configure(with rendition: MessageRendition,
                            maxBubbleWidth: CGFloat) {
        guard case .multipart(let subpartContainers) = rendition.flavor else {
            it_fatalError()
        }
        configuredMaxBubbleWidth = maxBubbleWidth
        isUserMessage = rendition.isUser
        drawsBubbleChrome = rendition.isUser

        // Tear down previous state.
        bubbleView.removeFromSuperview()
        timestamp.removeFromSuperview()
        for view in bubbleSubviews {
            view.removeFromSuperview()
        }
        bubbleSubviews.removeAll()
        subparts.removeAll()
        copyButtonsForCodeViews.removeAll()

        addSubview(bubbleView)
        backgroundColorPair = backgroundColorPair(rendition)
        updateBubbleColor()

        for sp in subpartContainers {
            switch sp.kind {
            case .regular:
                let tv = makeRegularTextView(for: sp, rendition: rendition)
                bubbleView.addSubview(tv)
                bubbleSubviews.append(tv)
                subparts.append(LaidOutSubpart(kind: .regular(textView: tv)))
            case .statusUpdate:
                let tv = makeStatusUpdateTextView(for: sp)
                bubbleView.addSubview(tv)
                bubbleSubviews.append(tv)
                subparts.append(LaidOutSubpart(kind: .statusUpdate(textView: tv)))
            case .codeAttachment:
                let tv = makeCodeAttachmentTextView(for: sp)
                let header = makeCodeBlockHeader(for: tv)
                let container = makeCodeBlockContainer(header: header, textView: tv)
                bubbleView.addSubview(container)
                bubbleSubviews.append(container)
                subparts.append(LaidOutSubpart(kind: .codeAttachment(container: container,
                                                                     header: header,
                                                                     textView: tv)))
            case .fileAttachment(id: let id, name: let name, file: let file):
                let view = FileAttachmentSubpartView(icon: sp.icon!,
                                                     filename: sp.attributedString,
                                                     id: id,
                                                     name: name,
                                                     file: file)
                bubbleView.addSubview(view)
                bubbleSubviews.append(view)
                subparts.append(LaidOutSubpart(kind: .fileAttachment(view: view)))
            }
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
        // Bubble width is set to the cap; subparts wrap to fit. (Status
        // updates voluntarily stay narrower via per-subpart insets.)
        let bubbleWidth = max(Self.minBubbleContentWidth, min(maxBubble, maxBubble))
        let stackInnerWidth = bubbleWidth - Self.bubbleInsetHorizontal * 2

        // Pre-measure each subpart's intrinsic height for the chosen content
        // width so we can size the bubble before placing children.
        var subpartHeights: [CGFloat] = []
        subpartHeights.reserveCapacity(subparts.count)
        for sp in subparts {
            subpartHeights.append(measuredHeight(for: sp, contentWidth: stackInnerWidth))
        }
        var subpartsTotalHeight: CGFloat = 0
        for (i, h) in subpartHeights.enumerated() {
            subpartsTotalHeight += h
            if i < subpartHeights.count - 1 {
                subpartsTotalHeight += Self.subpartSpacing
            }
        }
        let bubbleHeight = subpartsTotalHeight + Self.bubbleInsetTop + Self.bubbleInsetBottom

        let bubbleX = bubbleOriginX(bubbleWidth: bubbleWidth)
        let bubbleY = Self.bottomInset
        bubbleView.frame = NSRect(x: bubbleX,
                                  y: bubbleY,
                                  width: bubbleWidth,
                                  height: bubbleHeight)

        // Stack subparts top-down inside bubble.
        var nextTop = bubbleHeight - Self.bubbleInsetTop
        for (i, sp) in subparts.enumerated() {
            let h = subpartHeights[i]
            nextTop -= h
            layoutSubpart(sp,
                          height: h,
                          y: nextTop,
                          contentX: Self.bubbleInsetHorizontal,
                          contentWidth: stackInnerWidth)
            if i < subparts.count - 1 {
                nextTop -= Self.subpartSpacing
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
            timestamp.frame = NSRect(x: tsX, y: bubbleY, width: ts.width, height: ts.height)
        }
    }

    private func layoutSubpart(_ sp: LaidOutSubpart,
                               height: CGFloat,
                               y: CGFloat,
                               contentX: CGFloat,
                               contentWidth: CGFloat) {
        switch sp.kind {
        case .regular(let tv):
            tv.frame = NSRect(x: contentX, y: y, width: contentWidth, height: height)
            tv.textContainer?.size = NSSize(width: contentWidth - Self.regularTextSidePadding * 2,
                                            height: .greatestFiniteMagnitude)
        case .statusUpdate(let tv):
            tv.frame = NSRect(x: contentX, y: y, width: contentWidth, height: height)
            tv.textContainer?.size = NSSize(width: max(0, contentWidth - Self.regularTextSidePadding * 2),
                                            height: .greatestFiniteMagnitude)
        case .codeAttachment(let container, let header, let textView):
            container.frame = NSRect(x: contentX, y: y, width: contentWidth, height: height)
            // Header sits at the top of the container; text view fills the rest.
            let headerY = container.bounds.height - Self.codeBlockHeaderHeight
            header.frame = NSRect(x: 0,
                                  y: headerY,
                                  width: container.bounds.width,
                                  height: Self.codeBlockHeaderHeight)
            layoutCodeBlockHeader(header)
            textView.frame = NSRect(x: 0,
                                    y: 0,
                                    width: container.bounds.width,
                                    height: max(0, container.bounds.height - Self.codeBlockHeaderHeight))
            textView.textContainer?.size = NSSize(width: max(0, container.bounds.width - Self.codeTextSidePadding * 2),
                                                  height: .greatestFiniteMagnitude)
        case .fileAttachment(let view):
            view.frame = NSRect(x: contentX, y: y, width: contentWidth, height: height)
        }
    }

    private func measuredHeight(for sp: LaidOutSubpart, contentWidth: CGFloat) -> CGFloat {
        switch sp.kind {
        case .regular(let tv):
            return ceil(tv.desiredSize(forContentWidth: contentWidth).height)
        case .statusUpdate(let tv):
            return ceil(tv.desiredSize(forContentWidth: contentWidth).height)
        case .codeAttachment(_, _, let tv):
            // layoutSubpart shrinks the text container by codeTextSidePadding*2
            // on top of the container's own lineFragmentPadding. Measure at
            // the same effective width or the bubble ends up shorter than the
            // rendered glyphs and the bottom of long code blocks gets clipped.
            let inner = max(0, contentWidth - Self.codeTextSidePadding * 2)
            let textHeight = ceil(tv.desiredSize(forContentWidth: inner).height)
            return Self.codeBlockHeaderHeight + textHeight
        case .fileAttachment:
            return Self.fileAttachmentHeight
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

    // MARK: - Subpart factories

    private func makeRegularTextView(for sp: MessageRendition.SubpartContainer,
                                     rendition: MessageRendition) -> AutoSizingTextView {
        let tv = AutoSizingTextView()
        tv.isEditable = false
        tv.isSelectable = textSelectable
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.textContainer?.widthTracksTextView = false
        tv.linkTextAttributes = [.foregroundColor: rendition.linkColor]
        tv.textStorage?.setAttributedString(sp.attributedString)
        return tv
    }

    private func makeStatusUpdateTextView(for sp: MessageRendition.SubpartContainer) -> AutoSizingTextView {
        let tv = StatusUpdateTextView()
        tv.isEditable = false
        tv.isSelectable = textSelectable
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.lineFragmentPadding = Self.regularTextSidePadding
        tv.textContainerInset = .zero
        tv.textContainer?.widthTracksTextView = false
        tv.wantsLayer = true
        tv.layer?.cornerRadius = 6
        tv.layer?.borderWidth = 0
        updateStatusUpdateTextViewColors(tv)
        tv.textStorage?.setAttributedString(sp.attributedString)
        return tv
    }

    private func makeCodeAttachmentTextView(for sp: MessageRendition.SubpartContainer) -> AutoSizingTextView {
        let tv = CodeAttachmentTextView()
        tv.isEditable = false
        tv.isSelectable = textSelectable
        tv.drawsBackground = true
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.lineFragmentPadding = Self.codeTextSidePadding
        tv.textContainerInset = NSSize(width: 0, height: Self.codeTextVerticalPadding)
        tv.textContainer?.widthTracksTextView = false
        tv.wantsLayer = true
        tv.layer?.borderWidth = 0
        updateCodeTextViewColors(tv)
        tv.textStorage?.setAttributedString(sp.attributedString)
        return tv
    }

    private func makeCodeBlockHeader(for textView: NSTextView) -> NSView {
        let header = NSView()
        header.wantsLayer = true
        updateCodeBlockHeaderColors(header)

        let titleLabel = NSTextField(labelWithString: "Code Interpreter")
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        titleLabel.textColor = effectiveAppearance.it_isDark ? .white : .black
        titleLabel.identifier = NSUserInterfaceItemIdentifier("codeBlockTitle")
        header.addSubview(titleLabel)

        let copyButton = NSButton()
        // Same reason as in RegularMessageCellView: prevent NSScrollView's
        // focus-tracking auto-scroll on click.
        copyButton.refusesFirstResponder = true
        copyButton.title = "Copy"
        if #available(macOS 15, *) {
            copyButton.image = NSImage.it_image(forSymbolName: SFSymbol.documentOnDocument.rawValue,
                                                accessibilityDescription: "Copy",
                                                fallbackImageName: "document.on.document",
                                                for: MultipartMessageCellView.self)
        } else {
            copyButton.image = NSImage.it_image(forSymbolName: SFSymbol.docOnDoc.rawValue,
                                                accessibilityDescription: "Copy",
                                                fallbackImageName: "document.on.document",
                                                for: MultipartMessageCellView.self)
        }
        copyButton.imagePosition = .imageLeading
        copyButton.bezelStyle = .smallSquare
        copyButton.isBordered = false
        copyButton.controlSize = .small
        copyButton.target = self
        copyButton.action = #selector(copyCodeButtonClicked(_:))
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor.clear.cgColor
        copyButton.identifier = NSUserInterfaceItemIdentifier("codeBlockCopy")
        header.addSubview(copyButton)
        copyButtonsForCodeViews.append((copyButton, textView))
        return header
    }

    private func layoutCodeBlockHeader(_ header: NSView) {
        // Title (left), copy button (right). Header height is fixed.
        let title = header.subviews.first(where: { $0.identifier?.rawValue == "codeBlockTitle" }) as? NSTextField
        let copy = header.subviews.first(where: { $0.identifier?.rawValue == "codeBlockCopy" }) as? NSButton
        if let title {
            title.sizeToFit()
            let size = title.frame.size
            let y = floor((header.bounds.height - size.height) / 2)
            title.frame = NSRect(x: 8, y: y, width: size.width, height: size.height)
        }
        if let copy {
            copy.sizeToFit()
            let size = copy.frame.size
            let y = floor((header.bounds.height - size.height) / 2)
            copy.frame = NSRect(x: header.bounds.width - 8 - size.width,
                                y: y,
                                width: size.width,
                                height: size.height)
        }
    }

    private func makeCodeBlockContainer(header: NSView, textView: NSTextView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.borderWidth = 1.0
        container.addSubview(header)
        container.addSubview(textView)
        updateCodeBlockContainerColors(container)
        return container
    }

    private func updateCodeBlockContainerColors(_ container: NSView) {
        if effectiveAppearance.it_isDark {
            container.layer?.borderColor = NSColor(white: 0.2, alpha: 1.0).cgColor
        } else {
            container.layer?.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
        }
    }

    private func updateCodeBlockHeaderColors(_ headerView: NSView) {
        if effectiveAppearance.it_isDark {
            headerView.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1.0).cgColor
        } else {
            headerView.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1.0).cgColor
        }
    }

    private func updateCodeTextViewColors(_ textView: NSTextView) {
        if effectiveAppearance.it_isDark {
            textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
            textView.layer?.borderColor = NSColor(white: 0.2, alpha: 1.0).cgColor
        } else {
            textView.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
            textView.layer?.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
        }
    }

    private func updateStatusUpdateTextViewColors(_ textView: NSTextView) {
        if effectiveAppearance.it_isDark {
            textView.backgroundColor = NSColor(white: 0.14, alpha: 1.0)
            textView.layer?.borderColor = NSColor(white: 0.32, alpha: 1.0).cgColor
        } else {
            textView.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
            textView.layer?.borderColor = NSColor(white: 0.8, alpha: 1.0).cgColor
        }
    }

    @objc private func copyCodeButtonClicked(_ sender: NSButton) {
        guard let entry = copyButtonsForCodeViews.first(where: { $0.button === sender }) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.textView.string, forType: .string)
    }

    override func copyMenuItemClicked(_ sender: Any) {
        let allText = textViews.map { $0.string }.joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(allText, forType: .string)
    }

    override func forkMenuItemClicked(_ sender: Any) {
        it_fatalError("Subclass must implement this")
    }

    // MARK: - Static height

    static func cellHeight(for rendition: MessageRendition,
                           tableViewWidth: CGFloat) -> CGFloat {
        guard case .multipart(let subpartContainers) = rendition.flavor else {
            return 0
        }
        let maxBubble = maxBubbleWidth(tableViewWidth: tableViewWidth)
        let bubbleWidth = max(minBubbleContentWidth, min(maxBubble, maxBubble))
        let stackInnerWidth = bubbleWidth - bubbleInsetHorizontal * 2

        var subpartsTotalHeight: CGFloat = 0
        for (i, sp) in subpartContainers.enumerated() {
            subpartsTotalHeight += staticSubpartHeight(for: sp,
                                                       contentWidth: stackInnerWidth,
                                                       linkColor: rendition.linkColor)
            if i < subpartContainers.count - 1 {
                subpartsTotalHeight += subpartSpacing
            }
        }
        let bubbleHeight = subpartsTotalHeight + bubbleInsetTop + bubbleInsetBottom
        return topInset + bubbleHeight + bottomInset
    }

    private static func staticSubpartHeight(for sp: MessageRendition.SubpartContainer,
                                            contentWidth: CGFloat,
                                            linkColor: NSColor) -> CGFloat {
        switch sp.kind {
        case .regular:
            return ceil(measureText(sp.attributedString,
                                    contentWidth: contentWidth,
                                    lineFragmentPadding: regularTextSidePadding,
                                    verticalInset: 0))
        case .statusUpdate:
            return ceil(measureText(sp.attributedString,
                                    contentWidth: contentWidth,
                                    lineFragmentPadding: regularTextSidePadding,
                                    verticalInset: 0))
        case .codeAttachment:
            let inner = max(0, contentWidth - codeTextSidePadding * 2)
            let textHeight = ceil(measureText(sp.attributedString,
                                              contentWidth: inner,
                                              lineFragmentPadding: codeTextSidePadding,
                                              verticalInset: codeTextVerticalPadding))
            return codeBlockHeaderHeight + textHeight
        case .fileAttachment:
            return fileAttachmentHeight
        }
    }

    private static func measureText(_ attributedString: NSAttributedString,
                                    contentWidth: CGFloat,
                                    lineFragmentPadding: CGFloat,
                                    verticalInset: CGFloat) -> CGFloat {
        if attributedString.length == 0 || contentWidth <= 0 {
            return 0
        }
        let storage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: max(0, contentWidth),
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = lineFragmentPadding
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let glyphRange = layoutManager.glyphRange(for: container)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return bounding.maxY + verticalInset * 2
    }
}
