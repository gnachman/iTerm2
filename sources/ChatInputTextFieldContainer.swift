//
//  RoundedTextField.swift
//  iTerm2
//
//  Created by George Nachman on 2/19/25.
//

//
//  ChatInputTextFieldContainer.swift
//  Modified to use NSTextView with dynamic intrinsic content size
//

import Cocoa

fileprivate let extraHeight = CGFloat(12)
fileprivate let horizontalInset = CGFloat(6)

class ChatInputTextFieldContainer: NSView {
    private let scrollView: NSScrollView = {
        let sv = NSScrollView(frame: .zero)
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        return sv
    }()

    var maxHeight: CGFloat = 200.0

    let textView: ChatInputTextView = {
        let tv = ChatInputTextView(frame: .zero)
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return tv
    }()

    private let scrim = NSView()
    var placeholder: String? {
        get {
            textView.it_placeholderString
        }
        set {
            textView.it_placeholderString = newValue
        }
    }

    private var _enabled = true
    var isEnabled: Bool {
        get {
            _enabled
        }
        set {
            _enabled = newValue
            textView.isEditable = _enabled
            textView.isSelectable = _enabled
            textView.alphaValue = _enabled ? 1.0 : 0.8
        }
    }

    var stringValue: String {
        get {
            textView.string
        }
        set {
            textView.string = newValue
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        customizeAppearance()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange(_:)),
                                               name: NSText.didChangeNotification,
                                               object: textView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        customizeAppearance()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(textDidChange(_:)),
                                               name: NSText.didChangeNotification,
                                               object: textView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: textView.bounds.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        }
        // Calculate the full content height from the layout manager.
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            // Set the text view’s frame to the full used height.
            var frame = textView.frame
            frame.size.height = usedRect.height
            textView.frame = frame
        }
        // Invalidate intrinsic content size so container stays capped at maxHeight.
        invalidateIntrinsicContentSize()
    }

    private func customizeAppearance() {
        // Set an initial frame.
        frame = NSRect(x: 0, y: 0, width: 100, height: 100)

        // Configure background.
        let backgroundView = NSVisualEffectView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.blendingMode = .withinWindow
        backgroundView.material = .menu
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 10
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.borderWidth = 1
        backgroundView.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor

        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = effectiveAppearance.it_isDark ?
        NSColor(white: 0, alpha: 0.3).cgColor :
        NSColor(white: 1, alpha: 0.3).cgColor
        scrim.layer?.cornerRadius = 10
        scrim.layer?.masksToBounds = true

        addSubview(backgroundView)
        addSubview(scrim)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Add the text view inside the scroll view.
        textView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = textView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: extraHeight / 2),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -extraHeight / 2),

            textView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor)
        ])
    }

    @objc private func textDidChange(_ notification: Notification) {
        // Invalidate intrinsic content size when text changes.
        self.invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        scrim.layer?.backgroundColor = effectiveAppearance.it_isDark ?
        NSColor(white: 0, alpha: 0.3).cgColor :
        NSColor(white: 1, alpha: 0.3).cgColor
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let calculatedHeight = usedRect.height + extraHeight
        let height = min(calculatedHeight, maxHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}

class ChatInputTextView: PlaceholderTextView {
    var sendAction: Selector?
    weak var sendTarget: AnyObject?

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers, characters == "\r" else {
            super.keyDown(with: event)
            return
        }
        if event.modifierFlags.contains(.shift) {
            super.insertNewline(nil)
        } else {
            _ = delegate?.textView?(self, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            self.string = ""
            self.needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    override func paste(_ sender: Any?) {
        self.pasteAsPlainText(nil)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(performFindPanelAction(_:)) &&
            menuItem.tag == NSFindPanelAction.setFindString.rawValue {
            return selectedRanges.count > 0 || selectedRange.length > 0
        }
        return super.validateMenuItem(menuItem)
    }

    override func performFindPanelAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }
        if menuItem.tag == NSFindPanelAction.setFindString.rawValue {
            let string = (self.string as NSString).substring(with: selectedRange())
            guard !string.isEmpty else {
                return
            }
            iTermSetFindStringNotification(string: string).post()
        }
        super.performFindPanelAction(sender)
    }
}
