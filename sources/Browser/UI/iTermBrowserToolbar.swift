//
//  iTermBrowserToolbar.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

@available(macOS 11.0, *)
@objc(iTermBrowserHistoryItem)
class iTermBrowserHistoryItem: NSObject {
    @objc let title: String
    @objc let url: String
    @objc let steps: Int  // Number of steps back/forward from current position
    
    @objc init(title: String, url: String, steps: Int) {
        self.title = title
        self.url = url
        self.steps = steps
    }
}

@available(macOS 11.0, *)
protocol iTermBrowserToolbarDelegate: AnyObject {
    func browserToolbarDidTapReload()
    func browserToolbarDidTapStop()
    func browserToolbarDidSubmitURL(_ url: String)
    func browserToolbarDidTapSettings()
    func browserToolbarDidTapHistory()
    func browserToolbarDidTapAddBookmark() async
    func browserToolbarDidTapManageBookmarks()
    func browserToolbarDidTapReaderMode()
    func browserToolbarIsReaderModeActive() -> Bool
    func browserToolbarDidTapDistractionRemoval()
    func browserToolbarIsDistractionRemovalActive() -> Bool
    func browserToolbarBackHistoryItems() -> [iTermBrowserHistoryItem]
    func browserToolbarForwardHistoryItems() -> [iTermBrowserHistoryItem]
    func browserToolbarDidSelectHistoryItem(steps: Int)
    func browserToolbarDidRequestSuggestions(_ query: String) async -> [URLSuggestion]
    func browserToolbarDidBeginEditingURL(string: String) -> String?
    func browserToolbarUserDidSubmitNavigationRequest()
    func browserToolbarCurrentURL() -> String?
    func browserToolbarIsCurrentURLBookmarked() async -> Bool
    func browserToolbarDidTapAskAI()
    func browserToolbarShouldOfferReaderMode() async -> Bool
    func browserToolbarDidTapDebugAutofill()
}

@available(macOS 11.0, *)
@objc(iTermBrowserToolbar)
class iTermBrowserToolbar: NSView {
    weak var delegate: iTermBrowserToolbarDelegate?
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var stopButton: NSButton!
    private var urlBar: iTermURLBar!
    private var menuButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButtons()
        setupConstraints()
    }

    private func setupButtons() {
        backButton = NSButton()
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(backTapped)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        setupLongPressForButton(backButton, action: #selector(showBackHistory))
        addSubview(backButton)

        forwardButton = NSButton()
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        setupLongPressForButton(forwardButton, action: #selector(showForwardHistory))
        addSubview(forwardButton)

        reloadButton = NSButton()
        reloadButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reloadButton)
        
        stopButton = NSButton()
        stopButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop")
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.isHidden = true  // Initially hidden, shown during loading
        addSubview(stopButton)
        
        urlBar = iTermURLBar()
        urlBar.delegate = self
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlBar)
        
        menuButton = NSButton()
        menuButton.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Menu")
        menuButton.target = self
        menuButton.action = #selector(menuTapped)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            forwardButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 32),
            forwardButton.heightAnchor.constraint(equalToConstant: 32),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 8),
            reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 32),
            reloadButton.heightAnchor.constraint(equalToConstant: 32),
            
            // Stop button shares same position as reload button
            stopButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 8),
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 32),
            stopButton.heightAnchor.constraint(equalToConstant: 32),
            
            urlBar.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 12),
            urlBar.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlBar.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -12),
            urlBar.heightAnchor.constraint(equalToConstant: 28),
            
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 32),
            menuButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    func focusURLBar() {
        urlBar.focus()
    }
    
    @objc func cleanup() {
        urlBar.cleanup()
    }
    
    override func removeFromSuperview() {
        cleanup()
        super.removeFromSuperview()
    }

    @objc func backTapped() {
        delegate?.browserToolbarDidSelectHistoryItem(steps: -1)
    }

    @objc func forwardTapped() {
        delegate?.browserToolbarDidSelectHistoryItem(steps: 1)
    }

    @objc func reloadTapped() {
        delegate?.browserToolbarDidTapReload()
    }
    
    @objc private func stopTapped() {
        delegate?.browserToolbarDidTapStop()
    }
    
    // URL submission is now handled by iTermURLBar delegate
    
    @objc private func menuTapped() {
        showMainMenu()
    }
    
    private func showMainMenu() {
        let menu = NSMenu()
        
        // Add/Remove Bookmark menu item
        Task {
            let currentURL = delegate?.browserToolbarCurrentURL()
            let isBookmarked = await delegate?.browserToolbarIsCurrentURLBookmarked() ?? false
            let readerAvailable = (await delegate?.browserToolbarShouldOfferReaderMode() == true)
            await MainActor.run {
                if readerAvailable {
                    let askAIItem = NSMenuItem(title: "Ask AI…", action: #selector(askAIMenuItemSelected), keyEquivalent: "")
                    askAIItem.target = self
                    askAIItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
                    menu.addItem(askAIItem)

                    // Reader Mode menu item
                    let isReaderModeActive = delegate?.browserToolbarIsReaderModeActive() ?? false
                    let readerModeTitle = isReaderModeActive ? "Exit Reader Mode" : "Reader Mode"
                    let readerModeIcon = isReaderModeActive ? "doc.text.fill" : "doc.text"
                    let readerModeItem = NSMenuItem(title: readerModeTitle, action: #selector(readerModeMenuItemSelected), keyEquivalent: "")
                    readerModeItem.target = self
                    readerModeItem.image = NSImage(systemSymbolName: readerModeIcon, accessibilityDescription: nil)
                    readerModeItem.isEnabled = currentURL != nil
                    menu.addItem(readerModeItem)
                    
                    // Distraction Removal menu item
                    let isDistractionRemovalActive = delegate?.browserToolbarIsDistractionRemovalActive() ?? false
                    let distractionRemovalTitle = isDistractionRemovalActive ? "Exit Distraction Removal" : "Remove Distractions"
                    let distractionRemovalIcon = isDistractionRemovalActive ? "target.fill" : "target"
                    let distractionRemovalItem = NSMenuItem(title: distractionRemovalTitle, action: #selector(distractionRemovalMenuItemSelected), keyEquivalent: "")
                    distractionRemovalItem.target = self
                    distractionRemovalItem.image = NSImage(systemSymbolName: distractionRemovalIcon, accessibilityDescription: nil)
                    distractionRemovalItem.isEnabled = currentURL != nil
                    menu.addItem(distractionRemovalItem)
                }

                let bookmarkTitle = isBookmarked ? "Remove Bookmark" : "Add Bookmark"
                let bookmarkIcon = isBookmarked ? "bookmark.fill" : "bookmark"
                let bookmarkItem = NSMenuItem(title: bookmarkTitle, action: #selector(bookmarkMenuItemSelected), keyEquivalent: "")
                bookmarkItem.target = self
                bookmarkItem.image = NSImage(systemSymbolName: bookmarkIcon, accessibilityDescription: nil)
                bookmarkItem.isEnabled = currentURL != nil
                menu.addItem(bookmarkItem)
                
                menu.addItem(NSMenuItem.separator())

                // Manage Bookmarks menu item
                let manageBookmarksItem = NSMenuItem(title: "Manage Bookmarks", action: #selector(manageBookmarksMenuItemSelected), keyEquivalent: "")
                manageBookmarksItem.target = self
                manageBookmarksItem.image = NSImage(systemSymbolName: "book", accessibilityDescription: nil)
                menu.addItem(manageBookmarksItem)

                // History menu item
                let historyItem = NSMenuItem(title: "History", action: #selector(historyMenuItemSelected), keyEquivalent: "")
                historyItem.target = self
                historyItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
                menu.addItem(historyItem)

                menu.addItem(NSMenuItem.separator())

                #if DEBUG
                // Debug Autofill menu item (debug builds only)
                let debugAutofillItem = NSMenuItem(title: "Debug Autofill Fields", action: #selector(debugAutofillMenuItemSelected), keyEquivalent: "")
                debugAutofillItem.target = self
                debugAutofillItem.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: nil)
                menu.addItem(debugAutofillItem)
                #endif

                // Settings menu item
                let settingsItem = NSMenuItem(title: "Settings", action: #selector(settingsMenuItemSelected), keyEquivalent: "")
                settingsItem.target = self
                settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
                menu.addItem(settingsItem)


                // Position menu below the button
                let buttonFrame = menuButton.frame
                let menuLocation = NSPoint(x: buttonFrame.minX, y: buttonFrame.minY)
                menu.popUp(positioning: nil, at: menuLocation, in: self)
            }
        }
    }

    @objc private func askAIMenuItemSelected() {
        delegate?.browserToolbarDidTapAskAI()
    }

    @objc private func readerModeMenuItemSelected() {
        delegate?.browserToolbarDidTapReaderMode()
    }
    
    @objc private func distractionRemovalMenuItemSelected() {
        delegate?.browserToolbarDidTapDistractionRemoval()
    }
    
    @objc private func bookmarkMenuItemSelected() {
        Task {
            await delegate?.browserToolbarDidTapAddBookmark()
        }
    }
    
    @objc private func manageBookmarksMenuItemSelected() {
        delegate?.browserToolbarDidTapManageBookmarks()
    }
    
    @objc private func settingsMenuItemSelected() {
        delegate?.browserToolbarDidTapSettings()
    }
    
    #if DEBUG
    @objc private func debugAutofillMenuItemSelected() {
        delegate?.browserToolbarDidTapDebugAutofill()
    }
    #endif
    
    @objc private func historyMenuItemSelected() {
        delegate?.browserToolbarDidTapHistory()
    }
    
    // MARK: - Public Interface
    
    func updateURL(_ url: String?) {
        urlBar.currentURL = url
    }
    
    
    func updateFavicon(_ favicon: NSImage?) {
        urlBar.favicon = favicon
    }
    
    func setLoading(_ loading: Bool) {
        reloadButton.isHidden = loading
        stopButton.isHidden = !loading
        urlBar.isLoading = loading
    }
    
    func updateNavigationButtons(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }
    
    // MARK: - Long Press History
    
    private func setupLongPressForButton(_ button: NSButton, action: Selector) {
        let longPressGesture = NSPressGestureRecognizer(target: self, action: action)
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.allowableMovement = 10
        button.addGestureRecognizer(longPressGesture)
    }
    
    @objc private func showBackHistory(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let delegate = delegate else { return }
        let historyItems = delegate.browserToolbarBackHistoryItems()
        showHistoryMenu(for: backButton, items: historyItems)
    }
    
    @objc private func showForwardHistory(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let delegate = delegate else { return }
        let historyItems = delegate.browserToolbarForwardHistoryItems()
        showHistoryMenu(for: forwardButton, items: historyItems)
    }
    
    private func showHistoryMenu(for button: NSButton, items: [iTermBrowserHistoryItem]) {
        guard !items.isEmpty else { return }
        
        let menu = NSMenu()
        
        for item in items {
            let menuItem = NSMenuItem(title: item.title.isEmpty ? item.url : item.title, action: #selector(historyItemSelected(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item
            menuItem.toolTip = item.url
            menu.addItem(menuItem)
        }
        
        // Position menu below the button
        let buttonFrame = button.frame
        let menuLocation = NSPoint(x: buttonFrame.minX, y: buttonFrame.minY)
        menu.popUp(positioning: nil, at: menuLocation, in: self)
    }
    
    @objc private func historyItemSelected(_ menuItem: NSMenuItem) {
        guard let historyItem = menuItem.representedObject as? iTermBrowserHistoryItem else { return }
        delegate?.browserToolbarDidSelectHistoryItem(steps: historyItem.steps)
    }
}

// MARK: - iTermURLBarDelegate

@available(macOS 11.0, *)
extension iTermBrowserToolbar: iTermURLBarDelegate {
    func urlBar(_ urlBar: iTermURLBar, didSubmitURL url: String) {
        delegate?.browserToolbarDidSubmitURL(url)
    }
    
    func urlBar(_ urlBar: iTermURLBar, didRequestSuggestions query: String) async -> [URLSuggestion] {
        return await delegate?.browserToolbarDidRequestSuggestions(query) ?? []
    }
    
    func urlBarDidBeginEditing(_ urlBar: iTermURLBar, string: String) -> String? {
        return delegate?.browserToolbarDidBeginEditingURL(string: string)
    }
    
    func urlBarDidEndEditing(_ urlBar: iTermURLBar) {
        delegate?.browserToolbarUserDidSubmitNavigationRequest()
    }
}

