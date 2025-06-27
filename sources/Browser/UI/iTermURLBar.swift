//
//  iTermURLBar.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

import Cocoa

@available(macOS 11.0, *)
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

@available(macOS 11.0, *)
protocol iTermURLBarDelegate: AnyObject {
    func urlBar(_ urlBar: iTermURLBar, didSubmitURL url: String)
    func urlBar(_ urlBar: iTermURLBar, didRequestSuggestions query: String) async -> [URLSuggestion]
    func urlBarDidBeginEditing(_ urlBar: iTermURLBar, string: String) -> String?
    func urlBarDidEndEditing(_ urlBar: iTermURLBar)
}

@available(macOS 11.0, *)
@objc(iTermURLBar)
class iTermURLBar: NSView {
    
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
    
    // Behavioral controls
    var showSuggestions: Bool = true
    var enableAutocompletion: Bool = true

    // Not sure why but the completions window's offset and width are both off by this amount
    private let fudge = 16.0

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
        closeCompletions()
        currentSuggestionsTask?.cancel()
    }

    // MARK: - Setup
    
    private func setupUI() {
        setupTextFieldBackground()
        setupTextField()
        setupIcons()
        setupConstraints()
        setupTextFieldDelegate()
    }
    
    private func setupTextFieldBackground() {
        class URLBarTextFieldBackground: NSView { }
        textFieldBackground = URLBarTextFieldBackground()
        textFieldBackground.translatesAutoresizingMaskIntoConstraints = false
        textFieldBackground.wantsLayer = true
        textFieldBackground.layer?.cornerRadius = 8
        textFieldBackground.layer?.borderWidth = 1
        textFieldBackground.layer?.borderColor = NSColor.separatorColor.cgColor
        textFieldBackground.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        addSubview(textFieldBackground)
    }
    
    private func setupTextField() {
        textField = iTermURLTextField(frame: .zero)
        textField.urlTextFieldDelegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = "Search or enter website name"
        textField.font = NSFont.systemFont(ofSize: 13)
        
        textFieldBackground.addSubview(textField)
    }
    
    private func setupIcons() {
        // Favicon view
        faviconView = NSImageView()
        faviconView?.translatesAutoresizingMaskIntoConstraints = false
        faviconView?.imageScaling = .scaleProportionallyUpOrDown
        addSubview(faviconView!)
        
        // Progress indicator
        progressIndicator = NSProgressIndicator()
        progressIndicator?.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator?.style = .spinning
        progressIndicator?.controlSize = .small
        progressIndicator?.isHidden = true
        addSubview(progressIndicator!)
    }
    
    private func setupConstraints() {
        guard let faviconView = faviconView,
              let progressIndicator = progressIndicator else { return }
        let inset = 8.0
        NSLayoutConstraint.activate([
            // Favicon view (left side)
            faviconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 16),
            faviconView.heightAnchor.constraint(equalToConstant: 16),

            // Progress indicator (right side)
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),

            // Text field background (center, with margins for icons)
            textFieldBackground.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 8),
            textFieldBackground.trailingAnchor.constraint(equalTo: progressIndicator.leadingAnchor, constant: -8),
            textFieldBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            textFieldBackground.heightAnchor.constraint(equalToConstant: 28),

            textField.leadingAnchor.constraint(
                equalTo: textFieldBackground.leadingAnchor,
                constant: inset
            ),
            textField.trailingAnchor.constraint(
                equalTo: textFieldBackground.trailingAnchor,
                constant: -inset
            ),
            textField.centerYAnchor.constraint(equalTo: textFieldBackground.centerYAnchor,
                                               constant: 2),
            textField.heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        // Make the textField grow along with the text view until it can't
        let textWidthConstraint = textField.widthAnchor.constraint(
            equalTo: textField.textView.widthAnchor,
            constant: textField.textView.textContainerInset.width * 2
        )
        textWidthConstraint.priority = .defaultLow
        textWidthConstraint.isActive = true

        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        completionsWindow?.maxWidth = textField.bounds.width + fudge
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
    }
    
    private func updateFavicon() {
        guard let faviconView = faviconView else { return }
        faviconView.image = favicon
    }
    
    @objc private func textFieldSubmitted() {
        defer {
            delegate?.urlBarDidEndEditing(self)
        }
        // If there's a selected suggestion, use that instead of the text field content
        if let selectedItem = completionsWindow?.selectedItem {
            hideSuggestions()
            delegate?.urlBar(self, didSubmitURL: selectedItem.suggestion)
            return
        }
        
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        hideSuggestions()
        
        if !text.isEmpty {
            delegate?.urlBar(self, didSubmitURL: text)
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
            delegate?.urlBar(self, didSubmitURL: selectedItem.suggestion)
        }
    }

    private var locationForCompletionsWindow: NSRect {
        // Get text field position in screen coordinates
        var location = window!.convertToScreen(textField.convert(textField.bounds, to: nil))
        location.origin.x += fudge
        location.size.width -= fudge
        return location
    }

    private func createCompletionsWindow() {
        guard let window = self.window else { return }
        
        completionsWindow = CompletionsWindow(
            parent: window,
            location: locationForCompletionsWindow,
            mode: .indicator,
            placeholder: "Loading suggestions…",
            allowKey: false
        )
    }
    
    private func closeCompletions() {
        if let window = completionsWindow {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
            completionsWindow = nil
        }
        pendingQuery = nil
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
            
            let suggestions = await delegate?.urlBar(self, didRequestSuggestions: trimmedText) ?? []
            
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

@available(macOS 11.0, *)
extension iTermURLBar: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        handleTextChange(textField.stringValue)
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        NSLog("iTermURLBar: controlTextDidEndEditing")
        NSLog("  setting shouldSelectAllOnFirstClick to true")
        DispatchQueue.main.async { [weak self] in
            if let textField = self?.textField, !textField.textFieldIsFirstResponder() {
                NSLog("iTermURLBar: Hide suggstions")
                self?.hideSuggestions()
            } else {
                NSLog("iTermURLBar: Not hiding suggestions because url text field is still first responder")
            }
        }
    }
}

@available(macOS 11.0, *)
extension iTermURLBar: iTermURLTextFieldDelegate {
    func urlTextFieldDidBecomeFirstResponder(_ textField: iTermURLTextField) {
        if let replacement = delegate?.urlBarDidBeginEditing(self, string: textField.stringValue) {
            textField.stringValue = replacement
        }
        handleTextChange(textField.stringValue)
    }
}
