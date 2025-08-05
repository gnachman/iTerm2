//
//  iTermURLBar.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Cocoa

@MainActor
struct URLSuggestion {
    // When accepted, this value goes in the URL bar.
    let url: String

    // Display string in table view
    let displayText: NSAttributedString

    // Shown in footer of completions window when this suggestion is highlighted
    let detail: String

    // Determines the icon
    let type: SuggestionType
    
    enum SuggestionType {
        case history
        case search
        case bookmark
        case completion
        case webSearch
        case navigation
    }
}

@MainActor
protocol iTermURLBarDelegate: AnyObject {
    func urlBarDidSubmitURL(url: String)
    func urlBarDidRequestSuggestions(query: String) async -> [URLSuggestion]
    func urlBarDidBeginEditing(string: String) -> String?
    func urlBarDidEndEditing()
}

@MainActor
@objc(iTermURLBar)
class iTermURLBar: NSView {
    private let guts = iTermURLBarGuts(frame: .zero)
    var delegate: iTermURLBarDelegate? {
        get {
            guts.delegate
        }
        set {
            guts.delegate = newValue
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        addSubview(guts)
        autoresizesSubviews = true
        guts.frame = bounds
        guts.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func resize(withOldSuperviewSize oldSize: CGSize) {
        super.resize(withOldSuperviewSize: oldSize)
        guts.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard guts.isTextFieldFocused, NSApp.isActive else { return }

        // build a rounded path just outside your view’s content
        let expand: CGFloat = 1
        let ringRect = bounds.insetBy(dx: -expand, dy: -expand)
        let path = NSBezierPath(roundedRect: ringRect,
                                xRadius: iTermURLBarGuts.cornerRadius + expand,
                                yRadius: iTermURLBarGuts.cornerRadius + expand)
        // stroke with the standard keyboard-focus color
        NSColor.keyboardFocusIndicatorColor.setStroke()

        // pick a sensible line width
        path.lineWidth = 4
        path.stroke()
    }

    @objc
    func focus() {
        guts.focus()
    }

    @objc
    func cleanup() {
        guts.cleanup()
    }

    var currentURL: String? {
        get {
            guts.currentURL
        }
        set {
            guts.currentURL = newValue
        }
    }

    var favicon: NSImage? {
        get {
            guts.favicon
        }
        set {
            guts.favicon = newValue
        }
    }
    var isLoading: Bool {
        get {
            guts.isLoading
        }
        set {
            guts.isLoading = newValue
        }
    }
}

@MainActor
@objc(iTermURLBarGuts)
class iTermURLBarGuts: NSView {
    fileprivate static let cornerRadius = CGFloat(8.0)

    // MARK: - Properties
    
    weak var delegate: iTermURLBarDelegate?
    
    // UI Components
    private(set) var textField: iTermURLTextField!
    private var textFieldBackground: NSView!
    private var faviconView: NSImageView?
    private var progressIndicator: NSProgressIndicator?
    
    // Suggestions
    private var completionsWindow: CompletionsWindow?
    private var currentSuggestionsTask: Task<Void, Never>?
    private var pendingQuery: String?
    
    // State
    private var _currentURL: String?
    private var _isLoading: Bool = false
    private var _favicon: NSImage?
    private var draggedURL: URL?
    fileprivate var isTextFieldFocused: Bool = false

    // Behavioral controls
    var showSuggestions: Bool = true
    var enableAutocompletion: Bool = true

    // Not sure why but the completions window's offset and width are both off by this amount
    private let fudge = -4.0

    // MARK: - Public Interface
    
    var currentURL: String? {
        get { _currentURL }
        set {
            _currentURL = newValue
            updateDisplay()
        }
    }
    
    
    var isLoading: Bool {
        get { _isLoading }
        set {
            _isLoading = newValue
            updateLoadingState()
        }
    }
    
    var favicon: NSImage? {
        get { _favicon }
        set {
            _favicon = newValue
            updateFavicon()
        }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    deinit {
        if let window = completionsWindow {
            DispatchQueue.main.async {
                iTermURLBarGuts.closeCompletions(window: window)
            }
        }
        currentSuggestionsTask?.cancel()
    }

    // MARK: - Setup
    private func setupUI() {
        // Configure this view's layer for the border
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        
        setupTextFieldBackground()
        setupTextField()
        setupIcons()
        setupTextFieldDelegate()
    }
    
    private func setupTextFieldBackground() {
        class URLBarTextFieldBackground: NSView { }
        textFieldBackground = URLBarTextFieldBackground()
        // This is just a container now - no styling needed
        addSubview(textFieldBackground)
    }
    
    private func setupTextField() {
        textField = iTermURLTextField(frame: .zero)
        textField.urlTextFieldDelegate = self
        textField.placeholderString = "Search or enter website name"
        textField.font = NSFont.systemFont(ofSize: 13)
        
        textFieldBackground.addSubview(textField)
    }
    
    private func setupIcons() {
        // Favicon view
        faviconView = NSImageView()
        faviconView?.imageScaling = .scaleProportionallyUpOrDown
        faviconView?.unregisterDraggedTypes()  // Clear default drag behavior
        faviconView?.setAccessibilityRole(.button)
        faviconView?.setAccessibilityLabel("Site icon - drag to copy URL")
        addSubview(faviconView!)
        
        // Progress indicator
        progressIndicator = NSProgressIndicator()
        progressIndicator?.style = .spinning
        progressIndicator?.controlSize = .small
        progressIndicator?.isHidden = true
        addSubview(progressIndicator!)
    }
    
    override func layout() {
        super.layout()
        layoutComponents()
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        layoutComponents()
    }
    
    private func layoutComponents() {
        let bounds = self.bounds
        let iconSize = NSSize(width: 16, height: 16)
        let iconY = (bounds.height - iconSize.height) / 2
        let inset: CGFloat = 8
        
        // Favicon on left (inside the URL bar)
        faviconView?.frame = NSRect(x: inset, y: iconY,
                                   width: iconSize.width, height: iconSize.height)
        
        // Progress indicator on right (inside the URL bar when visible)
        let progressX = bounds.width - iconSize.width - inset
        progressIndicator?.frame = NSRect(x: progressX, y: iconY,
                                         width: iconSize.width, height: iconSize.height)
        
        // Text field background - now just a container for positioning
        let textFieldX: CGFloat = inset + iconSize.width + 4 // After favicon + spacing
        let textFieldWidth: CGFloat
        if _isLoading && !(progressIndicator?.isHidden ?? true) {
            // When progress indicator is visible, shrink text field
            textFieldWidth = progressX - textFieldX - 4
        } else {
            // When no progress indicator, text field takes full width
            textFieldWidth = bounds.width - textFieldX - inset
        }
        
        textFieldBackground.frame = NSRect(x: textFieldX, y: 2,
                                          width: textFieldWidth, height: bounds.height - 8)
        
        // Text field fills the background container
        textField.frame = textFieldBackground.bounds
    }

    private func setupTextFieldDelegate() {
        textField.delegate = self
        textField.target = self
        textField.action = #selector(textFieldSubmitted)
        textField.onSpecialKey = { [weak self] key in
            return self?.handleSpecialKey(key) ?? false
        }
    }
    
    // MARK: - Public Methods
    
    @objc func focus() {
        if textField.isFirstResponder {
            // Already focused, select all text
            textField.selectText(nil)
        } else {
            // Not focused, focus it (which will select all automatically)
            textField.focus()
        }
    }
    
    @objc func cleanup() {
        closeCompletions()
        currentSuggestionsTask?.cancel()
    }
    
    func showSuggestions(_ suggestions: [URLSuggestion]) {
        guard showSuggestions, !suggestions.isEmpty else {
            hideSuggestions()
            return
        }
        
        // Convert to CompletionsWindow items
        let items = suggestions.map { suggestion in
            let kind: CompletionItem.Kind = {
                switch suggestion.type {
                case .history: return .history
                case .search: return .command
                case .bookmark: return .bookmark
                case .completion: return .aiSuggestion
                case .webSearch: return .webSearch
                case .navigation: return .navigation
                }
            }()
            
            return CompletionsWindow.Item(
                suggestion: suggestion.url,
                attributedString: suggestion.displayText,
                detail: NSAttributedString(string: suggestion.detail),
                kind: kind
            )
        }
        
        if completionsWindow == nil {
            createCompletionsWindow()
        }
        completionsWindow?.maxWidth = bounds.width
        if window != nil {
            completionsWindow?.updateOrigin(location: locationForCompletionsWindow)
        }
        completionsWindow?.switchMode(to: .completions(items: items))
    }
    
    func hideSuggestions() {
        closeCompletions()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // View was removed from window, clean up completions
            closeCompletions()
            currentSuggestionsTask?.cancel()
        }
    }
    
    override func removeFromSuperview() {
        closeCompletions()
        currentSuggestionsTask?.cancel()
        super.removeFromSuperview()
    }
    
    // MARK: - Private Methods
    
    private func updateDisplay() {
        // Update text field with current URL, but don't show full URL while editing
        if !textField.isFirstResponder {
            textField.stringValue = currentURL ?? ""
        }
    }
    
    
    private func updateLoadingState() {
        guard let progressIndicator = progressIndicator else { return }
        
        if isLoading {
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.isHidden = true
            progressIndicator.stopAnimation(nil)
        }
        
        // Trigger layout update to resize text field when progress indicator visibility changes
        needsLayout = true
    }
    
    private func updateFavicon() {
        guard let faviconView = faviconView else { return }
        faviconView.image = favicon
    }
    
    @objc private func textFieldSubmitted() {
        defer {
            delegate?.urlBarDidEndEditing()
        }
        // If there's a selected suggestion, use that instead of the text field content
        if let selectedItem = completionsWindow?.selectedItem {
            hideSuggestions()
            delegate?.urlBarDidSubmitURL(url: selectedItem.suggestion)
            return
        }
        
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        hideSuggestions()
        
        if !text.isEmpty {
            delegate?.urlBarDidSubmitURL(url: text)
        }
    }
    
    private func handleSpecialKey(_ key: iTermURLTextField.SpecialKey) -> Bool {
        switch key {
        case .up:
            completionsWindow?.up()
            return true
        case .down:
            completionsWindow?.down()
            return true
        case .tab:
            acceptCurrentSuggestion()
            return true
        case .escape:
            // Reset to current URL and hide suggestions
            if let currentURL = currentURL {
                textField.stringValue = currentURL
                textField.selectText(nil)
            }
            hideSuggestions()
            return true
        }
    }
    
    private func acceptCurrentSuggestion() {
        if let selectedItem = completionsWindow?.selectedItem {
            textField.stringValue = selectedItem.suggestion
            hideSuggestions()
            // Optionally submit immediately or just accept the suggestion
            delegate?.urlBarDidSubmitURL(url: selectedItem.suggestion)
        }
    }
    
    // MARK: - Drag and Drop
    
    override func mouseDown(with event: NSEvent) {
        // Check if mouse down is on the favicon
        let locationInView = convert(event.locationInWindow, from: nil)
        if let faviconView = faviconView,
           NSPointInRect(locationInView, faviconView.frame),
           let currentURL = currentURL,
           let url = URL(string: currentURL) {
            
            // Create a custom pasteboard item that includes both URL and string representations
            let pasteboardItem = NSPasteboardItem()
            
            // Add URL representation
            pasteboardItem.setDataProvider(self, forTypes: [.URL])
            
            // Add string representation (for terminal compatibility)
            pasteboardItem.setString(currentURL, forType: .string)
            
            // Add file URL if it's a file
            if url.isFileURL {
                pasteboardItem.setString(url.path, forType: .fileURL)
            }
            
            // Create dragging item with our custom pasteboard item
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            
            // Set the dragging image to the favicon or a default
            let dragImage = favicon ?? NSImage(systemSymbolName: SFSymbol.globe.rawValue, accessibilityDescription: nil) ?? NSImage()
            draggingItem.setDraggingFrame(faviconView.frame, contents: dragImage)
            
            // Store the URL for the data provider
            self.draggedURL = url
            
            // Begin the dragging session
            beginDraggingSession(with: [draggingItem], event: event, source: self)
            return
        }
        
        super.mouseDown(with: event)
    }

    private var locationForCompletionsWindow: NSRect {
        // Get text field position in screen coordinates
        var location = window!.convertToScreen(textField.convert(textField.bounds, to: nil))
        location.origin.x += fudge
        location.size.width -= fudge
        location.origin.y -= 7
        return location
    }

    private func createCompletionsWindow() {
        guard let window = self.window else { return }
        
        completionsWindow = CompletionsWindow(
            parent: window,
            location: locationForCompletionsWindow,
            mode: .indicator,
            placeholder: "Loading suggestions…",
            allowKey: false)
        completionsWindow?.alwaysUseMaxWidth = true
    }
    
    private func closeCompletions() {
        if let window = completionsWindow {
            Self.closeCompletions(window: window)
            completionsWindow = nil
        }
        pendingQuery = nil
    }

    private static func closeCompletions(window: NSWindow) {
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func handleTextChange(_ text: String) {
        // Cancel any existing suggestion task
        currentSuggestionsTask?.cancel()
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedText.isEmpty || !showSuggestions {
            hideSuggestions()
            return
        }
        
        // Store the query that triggered this request
        pendingQuery = trimmedText
        
        // Create completions window if needed
        if completionsWindow == nil {
            createCompletionsWindow()
        }
        
        // Start async task to fetch suggestions
        currentSuggestionsTask = Task { [weak self] in
            guard let self = self else { return }
            
            let suggestions = await delegate?.urlBarDidRequestSuggestions(query: trimmedText) ?? []

            // Check if task was cancelled
            if Task.isCancelled {
                return
            }
            
            // Check if the text field content has changed since we started
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                let currentText = self.textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Only apply suggestions if the text hasn't changed
                if currentText == trimmedText && self.pendingQuery == trimmedText {
                    self.showSuggestions(suggestions)
                }
            }
        }
    }
}

// MARK: - NSTextFieldDelegate

@MainActor
extension iTermURLBarGuts: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        handleTextChange(textField.stringValue)
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        isTextFieldFocused = false
        superview?.needsDisplay = true
        DLog("iTermURLBar: controlTextDidEndEditing")
        DLog("  setting shouldSelectAllOnFirstClick to true")
        DispatchQueue.main.async { [weak self] in
            if let textField = self?.textField, !textField.textFieldIsFirstResponder() {
                DLog("iTermURLBar: Hide suggstions")
                self?.hideSuggestions()
            } else {
                DLog("iTermURLBar: Not hiding suggestions because url text field is still first responder")
            }
        }
    }
}

@MainActor
extension iTermURLBarGuts: iTermURLTextFieldDelegate {
    func urlTextFieldDidBecomeFirstResponder(_ textField: iTermURLTextField) {
        isTextFieldFocused = true
        superview?.needsDisplay = true
        if let replacement = delegate?.urlBarDidBeginEditing(string: textField.stringValue) {
            textField.stringValue = replacement
        }
        handleTextChange(textField.stringValue)
    }
}

// MARK: - NSDraggingSource

@MainActor
extension iTermURLBarGuts: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.copy, .link]
        case .withinApplication:
            return [.copy, .link]
        @unknown default:
            return .copy
        }
    }
    
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // Provide visual feedback if needed
        faviconView?.alphaValue = 0.5
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Restore visual state
        faviconView?.alphaValue = 1.0
        draggedURL = nil
    }
}

// MARK: - NSPasteboardItemDataProvider

extension iTermURLBarGuts: NSPasteboardItemDataProvider {
    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                                provideDataForType type: NSPasteboard.PasteboardType) {
        MainActor.assumeIsolated {
            guard let url = draggedURL else { return }

            if type == .URL {
                pasteboard?.setData(url.dataRepresentation, forType: .URL)
            }
        }
    }
}
