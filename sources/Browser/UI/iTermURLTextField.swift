//
//  iTermURLTextField.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Cocoa

@available(macOS 11.0, *)
protocol iTermURLTextFieldDelegate: AnyObject {
    func urlTextFieldDidBecomeFirstResponder(_ textField: iTermURLTextField)
}


@available(macOS 11.0, *)
class iTermURLTextField: NSScrollView {
    weak var urlTextFieldDelegate: iTermURLTextFieldDelegate?
    
    // MARK: - Properties
    
    /// Callback for handling special key events
    var onSpecialKey: ((SpecialKey) -> Bool)?
    
    enum SpecialKey {
        case up
        case down
        case tab
        case escape
    }
    
    // Text view and container
    private(set) var textView: iTermBrowserURLTextView!
    private var textContainer: NSTextContainer!
    private var layoutManager: NSLayoutManager!
    private var textStorage: NSTextStorage!
    
    // MARK: - NSTextField-like interface

    var isFirstResponder: Bool {
        return window?.firstResponder == textView
    }

    var stringValue: String {
        get {
            return textView.string
        }
        set {
            textView.string = newValue
            if window?.firstResponder == textView {
                notifyTextDidChange()
            }
            textView.invalidateIntrinsicContentSize()
        }
    }
    
    var placeholderString: String? {
        get { textView.it_placeholderString }
        set { textView.it_placeholderString = newValue }
    }
    
    var font: NSFont? {
        get { textView.font }
        set { textView.font = newValue }
    }
    
    var delegate: NSTextFieldDelegate? {
        get { _delegate }
        set { _delegate = newValue }
    }
    private weak var _delegate: NSTextFieldDelegate?
    
    var target: AnyObject?
    var action: Selector?
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
    }
    
    private func setupTextView() {
        // Create text system components
        textStorage = NSTextStorage()
        layoutManager = NSLayoutManager()
        textContainer = NSTextContainer()
        
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        // Configure text container for single-line behavior
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.containerSize = NSSize(width: 1000000, height: 1000000) // Very wide for horizontal scrolling
        
        // Create custom text view
        textView = iTermBrowserURLTextView(frame: bounds, textContainer: textContainer)
        textView.delegate = self
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor.textColor
        textView.willBecomeFirstResponder = { [weak self] in
            guard let self else {
                return
            }
            self.urlTextFieldDelegate?.urlTextFieldDidBecomeFirstResponder(self)
            textView.selectAll(nil)
            textView.scrollRangeToVisible(NSRange(location: textView?.textStorage?.length ?? 0,
                                                  length: 0))
            // Send NSTextField-compatible notification
            let notification = Notification(name: NSControl.textDidBeginEditingNotification, object: self)
            self.delegate?.controlTextDidBeginEditing?(notification)
        }
        textView.willResignFirstResponder = { [weak self] in
            let notification = Notification(name: NSControl.textDidEndEditingNotification, object: self)
            // This might change first responder
            self?.delegate?.controlTextDidEndEditing?(notification)
        }
        // Configure scroll view
        documentView = textView
        hasVerticalScroller = false
        hasHorizontalScroller = false
        borderType = .noBorder
        drawsBackground = false
        
        // Set up constraints to maintain single-line height
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
    }
    
    override func layout() {
        super.layout()
        textView.frame = bounds
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        textView.frame = bounds
    }
    
    private func notifyTextDidChange() {
        // Send NSTextField-compatible notification
        let notification = Notification(name: NSControl.textDidChangeNotification, object: self)
        delegate?.controlTextDidChange?(notification)
    }
    
    // MARK: - First Responder
    
    override var acceptsFirstResponder: Bool {
        return false  // The text view should be first responder, not the scroll view
    }
    
    // MARK: - Selection and editing
    
    func selectText(_ sender: Any?) {
        textView.selectAll(sender)
    }
    
    // Helper method to check if we're first responder
    func textFieldIsFirstResponder() -> Bool {
        return textView.window?.firstResponder == textView
    }
    
    // Focus the text view directly
    func focus() {
        window?.makeFirstResponder(textView)
    }
    
    // Override mouse handling to make text view first responder
    override func mouseDown(with event: NSEvent) {
        _ = window?.makeFirstResponder(textView)
        super.mouseDown(with: event)
    }
}

// MARK: - NSTextViewDelegate


@available(macOS 11.0, *)
extension iTermURLTextField: NSTextViewDelegate {
        func textDidChange(_ notification: Notification) {
        // Prevent line breaks - replace with spaces
        let text = textView.string
        if text.contains("\n") || text.contains("\r") {
            let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            textView.string = singleLine
            
            // Move cursor to end
            textView.selectedRange = NSRange(location: singleLine.count, length: 0)
        }
        
        notifyTextDidChange()
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if onSpecialKey?(.tab) == true {
                return true
            }
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if onSpecialKey?(.down) == true {
                return true
            }
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if onSpecialKey?(.up) == true {
                return true
            }
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Handle Enter key
            if let target = target, let action = action {
                _ = target.perform(action, with: self)
                return true
            }
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Handle Escape key
            if onSpecialKey?(.escape) == true {
                return true
            }
        }
        
        // Return false to allow normal processing
        return false
    }
}
