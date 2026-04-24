import AppKit

// MARK: - Delegate

@objc(iTermSessionNoteViewDelegate)
protocol SessionNoteViewDelegate: AnyObject {
    func sessionNoteViewTextDidChange(_ view: SessionNoteView)
    func sessionNoteViewDidBecomeEmpty(_ view: SessionNoteView)
    func sessionNoteViewDidUpdateFrame(_ view: SessionNoteView)
    func sessionNoteFont() -> NSFont
}

// MARK: - Flipped Visual Effect View

private class FlippedVisualEffectView: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

// MARK: - Text View Subclass

private class SessionNoteTextView: NSTextView {
    var collapseHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 /* Return */ && event.modifierFlags.contains(.shift) {
            collapseHandler?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}

// MARK: - Session Note View

@objc(iTermSessionNoteView)
class SessionNoteView: NSView, NSTextViewDelegate {
    @objc weak var delegate: SessionNoteViewDelegate?
    @objc var hasContent: Bool { !model.text.isEmpty }

    private let model: SessionNoteModel
    private let textView: SessionNoteTextView
    private let scrollView: NSScrollView
    private let clipView: NSView
    private let backgroundView: NSVisualEffectView
    private let titleBar: NSView
    private let titleLabel: NSTextField
    private let collapseButton: NSButton

    private var expandedHeight: CGFloat
    private var isDragging = false
    private var dragOrigin = NSPoint.zero
    private var frameOriginAtDragStart = NSPoint.zero

    private var isAnimatingCollapse = false
    private var isResizing = false
    private var resizeLeft = false
    private var resizeRight = false
    private var resizeTop = false
    private var resizeBottom = false
    private var resizeDragOrigin = NSPoint.zero
    private var originalSize = NSSize.zero
    private var originalOrigin = NSPoint.zero

    private static let titleBarHeight: CGFloat = 28
    private static let minWidth: CGFloat = 150
    private static let minHeight: CGFloat = 80
    private static let dragAreaSize: CGFloat = 5
    private static let cornerRadius: CGFloat = 8

    @objc var isCollapsed: Bool {
        get { model.isCollapsed }
        set {
            guard newValue != model.isCollapsed else { return }
            if !newValue {
                // Expanding: save expanded frame before the model changes.
                // (expandedHeight was captured when we collapsed.)
            } else {
                // Collapsing: capture expanded frame into model before shrinking.
                model.noteFrame = frame
            }
            model.isCollapsed = newValue
            animateCollapseChange()
            delegate?.sessionNoteViewDidUpdateFrame(self)
        }
    }

    // MARK: - Init

    @objc init(frame: NSRect, model: SessionNoteModel) {
        self.model = model
        self.expandedHeight = frame.size.height

        clipView = NSView()
        clipView.wantsLayer = true
        clipView.autoresizingMask = []
        clipView.layer?.cornerRadius = Self.cornerRadius
        clipView.layer?.masksToBounds = true

        backgroundView = FlippedVisualEffectView()
        backgroundView.material = .sheet
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.autoresizingMask = []

        titleBar = NSView()
        titleBar.wantsLayer = true
        titleBar.autoresizingMask = []

        titleLabel = NSTextField(labelWithString: "Session Note")
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false

        collapseButton = NSButton()
        collapseButton.bezelStyle = .inline
        collapseButton.isBordered = false
        collapseButton.image = NSImage(systemSymbolName: "chevron.down",
                                       accessibilityDescription: "Collapse")
        collapseButton.imagePosition = .imageOnly
        collapseButton.setButtonType(.momentaryPushIn)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = []

        let contentSize = scrollView.contentSize
        textView = SessionNoteTextView(
            frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        )
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.drawsBackground = false
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        scrollView.documentView = textView

        super.init(frame: frame)

        autoresizingMask = []
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 6

        // Outer view (shadow) → clipView (masksToBounds) → backgroundView + content.
        addSubview(clipView)
        clipView.addSubview(backgroundView)
        backgroundView.addSubview(scrollView)
        backgroundView.addSubview(titleBar)
        titleBar.addSubview(titleLabel)
        titleBar.addSubview(collapseButton)

        collapseButton.target = self
        collapseButton.action = #selector(toggleCollapse)

        textView.delegate = self
        textView.collapseHandler = { [weak self] in
            self?.isCollapsed = true
        }
        textView.string = model.text

        if model.isCollapsed {
            // frame was initialized from model.noteFrame (the expanded frame).
            // Shrink to title bar, keeping top edge fixed (non-flipped: top = origin.y + height).
            let topEdge = frame.origin.y + frame.size.height
            scrollView.isHidden = true
            self.frame = NSRect(x: frame.origin.x,
                                y: topEdge - Self.titleBarHeight,
                                width: frame.size.width,
                                height: Self.titleBarHeight)
        }

        layoutSubviewsManually()
        updateCollapseButtonImage()
        updateTitleLabel()
        updateBorder()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontNotificationReceived(_:)),
            name: .PTYTextViewWillChangeFont,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelTextDidChange(_:)),
            name: SessionNoteModel.textDidChangeNotification,
            object: model
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    private func updateBorder() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            clipView.layer?.borderWidth = 1
            clipView.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        } else {
            clipView.layer?.borderWidth = 0
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviewsManually()
    }

    private func layoutSubviewsManually() {
        let bounds = self.bounds

        clipView.frame = bounds
        backgroundView.frame = clipView.bounds

        // backgroundView is flipped: y=0 is top.
        titleBar.frame = NSRect(x: 0, y: 0,
                                width: bounds.width, height: Self.titleBarHeight)

        let textX: CGFloat = 8  // scrollView.x (4) + textContainerInset.width (4)
        let maxLabelWidth = bounds.width - textX - 30
        let labelSize = titleLabel.sizeThatFits(NSSize(width: maxLabelWidth, height: Self.titleBarHeight))
        titleLabel.frame = NSRect(x: textX, y: (Self.titleBarHeight - labelSize.height) / 2,
                                  width: min(labelSize.width, maxLabelWidth), height: labelSize.height)

        let buttonSize: CGFloat = 20
        collapseButton.frame = NSRect(x: bounds.width - buttonSize - 8,
                                      y: (Self.titleBarHeight - buttonSize) / 2,
                                      width: buttonSize, height: buttonSize)

        // During collapse/expand animation, leave the scrollView in place
        // and let backgroundView's clipping handle visibility.
        if !isAnimatingCollapse && !model.isCollapsed {
            layoutScrollView()
        }
    }

    private func layoutScrollView() {
        let bounds = self.bounds
        // backgroundView is flipped: scrollView sits below the title bar.
        let scrollFrame = NSRect(x: 6,
                                 y: Self.titleBarHeight + 4,
                                 width: bounds.width - 12,
                                 height: bounds.height - Self.titleBarHeight - 8)
        scrollView.frame = scrollFrame
        let contentWidth = scrollView.contentSize.width
        textView.textContainer?.containerSize = NSSize(width: contentWidth,
                                                       height: CGFloat.greatestFiniteMagnitude)
    }

    // MARK: - Public

    @objc func focus() {
        window?.makeFirstResponder(textView)
    }

    @objc func updateFont(_ font: NSFont) {
        textView.font = font
        textView.textColor = .textColor
        if let textStorage = textView.textStorage, textStorage.length > 0 {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttribute(.font, value: font, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        }
    }

    private func updateTitleLabel() {
        if model.isCollapsed, let firstLine = model.text.components(separatedBy: .newlines).first, !firstLine.isEmpty {
            titleLabel.stringValue = firstLine
        } else {
            titleLabel.stringValue = "Session Note"
        }
    }

    // MARK: - Collapse

    @objc private func toggleCollapse() {
        isCollapsed = !isCollapsed
    }

    private func animateCollapseChange() {
        // Non-flipped coords: origin is bottom-left.
        // Keep top edge (origin.y + height) fixed throughout.
        let topEdge = frame.origin.y + frame.size.height
        let startFrame = frame

        isAnimatingCollapse = true

        if model.isCollapsed {
            expandedHeight = frame.size.height
            let endFrame = NSRect(x: frame.origin.x,
                                  y: topEdge - Self.titleBarHeight,
                                  width: frame.size.width,
                                  height: Self.titleBarHeight)
            animateFrame(from: startFrame, to: endFrame) {
                self.isAnimatingCollapse = false
                self.scrollView.isHidden = true
            }
        } else {
            // Position scrollView at its expanded size before animating,
            // so it's revealed as the view grows. backgroundView is flipped.
            scrollView.isHidden = false
            scrollView.frame = NSRect(x: 6, y: Self.titleBarHeight + 4,
                                      width: frame.size.width - 12,
                                      height: expandedHeight - Self.titleBarHeight - 8)
            let endFrame = NSRect(x: frame.origin.x,
                                  y: topEdge - expandedHeight,
                                  width: frame.size.width,
                                  height: expandedHeight)
            animateFrame(from: startFrame, to: endFrame) {
                self.isAnimatingCollapse = false
                self.layoutSubviewsManually()
            }
        }
        updateCollapseButtonImage()
        updateTitleLabel()
    }

    private func animateFrame(from startFrame: NSRect, to endFrame: NSRect,
                              duration: TimeInterval = 0.2,
                              completion: @escaping () -> Void) {
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = CACurrentMediaTime() - startTime
            let t = CGFloat(min(elapsed / duration, 1.0))
            let eased = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t

            self.frame = NSRect(
                x: startFrame.origin.x + (endFrame.origin.x - startFrame.origin.x) * eased,
                y: startFrame.origin.y + (endFrame.origin.y - startFrame.origin.y) * eased,
                width: startFrame.size.width + (endFrame.size.width - startFrame.size.width) * eased,
                height: startFrame.size.height + (endFrame.size.height - startFrame.size.height) * eased
            )
            self.layoutSubviewsManually()

            if t >= 1.0 {
                timer.invalidate()
                completion()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateCollapseButtonImage() {
        let name = model.isCollapsed ? "chevron.right" : "chevron.down"
        collapseButton.image = NSImage(systemSymbolName: name,
                                       accessibilityDescription: model.isCollapsed ? "Expand" : "Collapse")
    }

    // MARK: - Drag (Title Bar) and Resize

    private func beginResize(left: Bool, right: Bool, top: Bool, bottom: Bool, event: NSEvent) {
        isResizing = true
        resizeLeft = left
        resizeRight = right
        resizeTop = top
        resizeBottom = bottom
        resizeDragOrigin = event.locationInWindow
        originalSize = frame.size
        originalOrigin = frame.origin
    }

    override func mouseDown(with event: NSEvent) {
        let pointInSelf = convert(event.locationInWindow, from: nil)

        for region in resizeRegions() {
            if NSPointInRect(pointInSelf, region.rect) {
                beginResize(left: region.left, right: region.right,
                            top: region.top, bottom: region.bottom, event: event)
                return
            }
        }

        let titleBarFrame = NSRect(x: 0, y: bounds.height - Self.titleBarHeight,
                                   width: bounds.width, height: Self.titleBarHeight)
        if NSPointInRect(pointInSelf, titleBarFrame) {
            isDragging = true
            dragOrigin = event.locationInWindow
            frameOriginAtDragStart = frame.origin
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow

        if isDragging {
            let dx = point.x - dragOrigin.x
            let dy = point.y - dragOrigin.y
            var newOrigin = NSPoint(x: frameOriginAtDragStart.x + dx,
                                   y: frameOriginAtDragStart.y + dy)
            if let sv = superview {
                newOrigin.x = max(0, min(newOrigin.x, sv.bounds.width - frame.width))
                newOrigin.y = max(0, min(newOrigin.y, sv.bounds.height - frame.height))
            }
            setFrameOrigin(newOrigin)
        }

        if isResizing, let sv = superview {
            let dx = point.x - resizeDragOrigin.x
            let dy = point.y - resizeDragOrigin.y

            var newWidth = originalSize.width
            if resizeRight {
                newWidth = originalSize.width + dx
            } else if resizeLeft {
                newWidth = originalSize.width - dx
            }
            newWidth = max(Self.minWidth, ceil(newWidth))

            var newHeight = originalSize.height
            if resizeBottom {
                newHeight = originalSize.height - dy
                newHeight = max(Self.minHeight, ceil(newHeight))
            } else if resizeTop {
                newHeight = originalSize.height + dy
                newHeight = max(Self.minHeight, ceil(newHeight))
            }

            let originalRight = originalOrigin.x + originalSize.width
            let originalTop = originalOrigin.y + originalSize.height

            var newX = resizeLeft ? (originalRight - newWidth) : originalOrigin.x
            var newY = resizeBottom ? (originalTop - newHeight) : originalOrigin.y

            // Constrain to superview bounds, keeping the anchored edge fixed.
            if newX < 0 {
                newX = 0
                if resizeLeft { newWidth = originalRight }
            }
            if newY < 0 {
                newY = 0
                if resizeBottom { newHeight = originalTop }
            }
            if newX + newWidth > sv.bounds.width {
                newWidth = sv.bounds.width - newX
            }
            if newY + newHeight > sv.bounds.height {
                newHeight = sv.bounds.height - newY
            }

            frame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
            layoutSubviewsManually()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging || isResizing {
            isDragging = false
            isResizing = false
            resizeLeft = false
            resizeRight = false
            resizeTop = false
            resizeBottom = false
            syncModelFrame()
            delegate?.sessionNoteViewDidUpdateFrame(self)
        }
    }

    /// Keep model.noteFrame as the expanded frame, even when collapsed.
    @objc func syncModelFrame() {
        if model.isCollapsed {
            // Non-flipped: the collapsed view's top edge is origin.y + titleBarHeight.
            // Reconstruct the expanded frame keeping the same top edge.
            let topEdge = frame.origin.y + frame.size.height
            model.noteFrame = NSRect(x: frame.origin.x,
                                     y: topEdge - expandedHeight,
                                     width: frame.size.width,
                                     height: expandedHeight)
        } else {
            model.noteFrame = frame
        }
    }

    // MARK: - Resize Handles

    private struct ResizeRegion {
        let rect: NSRect
        let left: Bool
        let right: Bool
        let top: Bool
        let bottom: Bool
        let cursor: NSCursor
    }

    private func resizeRegions() -> [ResizeRegion] {
        let d = Self.dragAreaSize
        let w = bounds.width
        let h = bounds.height

        if model.isCollapsed {
            // Horizontal resize only when collapsed.
            return [
                ResizeRegion(rect: NSRect(x: 0, y: 0, width: d, height: h),
                             left: true, right: false, top: false, bottom: false, cursor: .resizeLeftRight),
                ResizeRegion(rect: NSRect(x: w - d, y: 0, width: d, height: h),
                             left: false, right: true, top: false, bottom: false, cursor: .resizeLeftRight),
            ]
        }

        let nwse = iTermMouseCursor(of: .northwestSoutheastArrow) ?? .arrow
        let nesw = iTermMouseCursor(of: .northeastSouthwestArrow) ?? .arrow

        return [
            ResizeRegion(rect: NSRect(x: 0, y: 0, width: d, height: d),
                         left: true, right: false, top: false, bottom: true, cursor: nesw),
            ResizeRegion(rect: NSRect(x: w - d, y: 0, width: d, height: d),
                         left: false, right: true, top: false, bottom: true, cursor: nwse),
            ResizeRegion(rect: NSRect(x: 0, y: h - d, width: d, height: d),
                         left: true, right: false, top: true, bottom: false, cursor: nwse),
            ResizeRegion(rect: NSRect(x: w - d, y: h - d, width: d, height: d),
                         left: false, right: true, top: true, bottom: false, cursor: nesw),
            ResizeRegion(rect: NSRect(x: 0, y: d, width: d, height: h - 2 * d),
                         left: true, right: false, top: false, bottom: false, cursor: .resizeLeftRight),
            ResizeRegion(rect: NSRect(x: w - d, y: d, width: d, height: h - 2 * d),
                         left: false, right: true, top: false, bottom: false, cursor: .resizeLeftRight),
            ResizeRegion(rect: NSRect(x: d, y: 0, width: w - 2 * d, height: d),
                         left: false, right: false, top: false, bottom: true, cursor: .resizeUpDown),
            ResizeRegion(rect: NSRect(x: d, y: h - d, width: w - 2 * d, height: d),
                         left: false, right: false, top: true, bottom: false, cursor: .resizeUpDown),
        ]
    }

    override func resetCursorRects() {
        // Arrow cursor over the title bar (between resize edges).
        let d = Self.dragAreaSize
        let titleBarRect = NSRect(x: d, y: bounds.height - Self.titleBarHeight,
                                  width: bounds.width - 2 * d, height: Self.titleBarHeight)
        addCursorRect(titleBarRect, cursor: .arrow)

        for region in resizeRegions() {
            addCursorRect(region.rect, cursor: region.cursor)
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        model.text = textView.string
        delegate?.sessionNoteViewTextDidChange(self)
    }

    func textDidEndEditing(_ notification: Notification) {
        if model.text.isEmpty {
            delegate?.sessionNoteViewDidBecomeEmpty(self)
        }
    }

    // MARK: - Font Notification

    @objc private func fontNotificationReceived(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let font = self.delegate?.sessionNoteFont() else {
                return
            }
            self.updateFont(font)
        }
    }

    // MARK: - External Model Change

    @objc private func modelTextDidChange(_ notification: Notification) {
        if textView.string != model.text {
            textView.string = model.text
        }
    }

    // MARK: - Key Handling

    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(superview)
    }
}
