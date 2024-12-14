//
//  ExpandingTextField.swift
//  iTerm2
//
//  Created by George Nachman on 12/14/24.
//

import AppKit

import AppKit

@objc(iTermExpandingTextField)
class ExpandingTextField: NSTextField {
    private let toggleExpandedButton = NSButton()
    private var popover = NSPopover()
    private let textView = KeyDownObservableTextView()
    private var isExpanded = false
    private let scrollView = NSScrollView()

    @objc var rightInset = CGFloat(0) {
        didSet {
            updateButtonFrame()
        }
    }

    override var isEnabled: Bool {
        didSet {
            toggleExpandedButton.isHidden = !isEnabled
            if !isEnabled {
                popover.performClose(nil)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initCommon()
    }

    @MainActor required init?(coder: NSCoder) {
        super.init(coder: coder)
        initCommon()
    }

    private static func setImage(button: NSButton, expand: Bool) {
        if expand {
            if #available(macOS 11, *) {
                button.image = NSImage(systemSymbolName: "rectangle.expand.vertical", accessibilityDescription: "Expand")
                button.imagePosition = .imageOnly
            } else {
                button.title = "⇳"
            }
        } else {
            if #available(macOS 11, *) {
                button.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Expand")
                button.imagePosition = .imageOnly
            } else {
                button.title = "×"
            }
        }
    }

    private func initCommon() {
        // Configure toggle button
        toggleExpandedButton.frame = NSRect(x: bounds.width - 22, y: 0, width: 22, height: bounds.height)

        ExpandingTextField.setImage(button: toggleExpandedButton, expand: true)
        toggleExpandedButton.isBordered = false
        addSubview(toggleExpandedButton)


        toggleExpandedButton.bezelStyle = .regularSquare
        toggleExpandedButton.target = self
        toggleExpandedButton.action = #selector(toggle(_:))
        toggleExpandedButton.sizeToFit()
        addSubview(toggleExpandedButton)

        // Configure popover and text view
        textView.isEditable = true
        textView.isRichText = false
        textView.font = font
        textView.string = stringValue
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.delegate = self
        textView.observer = { [weak self] event in
            if event.characters == "\n" {
                self?.popover.performClose(nil)
                return false
            }
            return true
        }
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.frame = NSRect(x: 0, y: 0, width: 300, height: 150)
    }

    @objc private func toggle(_ sender: Any) {
        if isExpanded {
            popover.performClose(sender)
        } else {
            expand()
        }
    }

    private func collapse() {
        if !isExpanded {
            return
        }
        stringValue = textView.string
        isExpanded = false
        ExpandingTextField.setImage(button: toggleExpandedButton, expand: true)
    }

    private func expand() {
        if isExpanded {
            return
        }
        scrollView.documentView = textView
        textView.string = stringValue
        textView.delegate = self
        let popoverWidth = bounds.width
        popover = NSPopover()
        let popoverViewController = NSViewController()
        popoverViewController.view = scrollView
        popover.contentViewController = popoverViewController
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController?.view.frame.size.width = popoverWidth
        popover.show(relativeTo: toggleExpandedButton.bounds,
                     of: toggleExpandedButton,
                     preferredEdge: .maxY)
        isExpanded = true
        ExpandingTextField.setImage(button: toggleExpandedButton, expand: false)
    }

    private func updateButtonFrame() {
        let buttonWidth: CGFloat = 22
        toggleExpandedButton.frame = NSRect(x: bounds.width - buttonWidth - rightInset,
                                            y: 0,
                                            width: buttonWidth,
                                            height: bounds.height)
    }
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateButtonFrame()
    }

    override func layout() {
        super.layout()
        // Ensure button is always properly aligned
        resizeSubviews(withOldSize: bounds.size)
    }
}

extension ExpandingTextField: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        collapse()
    }
    func popoverDidClose(_ notification: Notification) {
        collapse()
    }
}

extension ExpandingTextField: NSTextViewDelegate {
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        guard isExpanded else {
            return
        }
        // Copy textView's content to the text field
        let newValue = textView.string
        if newValue != stringValue {
            stringValue = newValue

            if let delegate {
                delegate.controlTextDidChange?(Notification(name: .init("NSControlTextDidChangeNotification"), object: self))
            }
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString string: String?) -> Bool {
        guard isExpanded else {
            return true
        }
        // Disallow line breaks
        if let string = string, string.contains("\n") {
            return false
        }
        return true
    }
}

class KeyDownObservableTextView: NSTextView {
    var observer: ((NSEvent) -> (Bool))?
    override func keyDown(with event: NSEvent) {
        if observer?(event) ?? true {
            super.keyDown(with: event)
        }
    }
}
