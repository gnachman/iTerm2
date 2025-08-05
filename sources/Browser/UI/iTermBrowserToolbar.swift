//
//  iTermBrowserToolbar.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

@MainActor
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

@MainActor
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
    func browserToolbarPermissionsForCurrentSite() async -> ([BrowserPermissionType: BrowserPermissionDecision], String)?
    func browserToolbarResetPermission(for key: BrowserPermissionType, origin: String) async
    func browserToolbarUnmute(url: String)
    func browserToolbarIsCurrentPageMuted() -> Bool
#if DEBUG
    func browserToolbarDidTapDebugAutofill()
#endif
}

@MainActor
@objc(iTermBrowserToolbar)
class iTermBrowserToolbar: NSView {
    weak var delegate: iTermBrowserToolbarDelegate?
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var stopButton: NSButton!
    private var devNullIndicator: NSButton!
    private var urlBar: iTermURLBar!
    private var menuButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButtons()
    }

    private func setupButtons() {
        backButton = HoverButton(symbolName: "chevron.left",
                                 accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(backTapped)
        setupLongPressForButton(backButton, action: #selector(showBackHistory))
        addSubview(backButton)

        forwardButton = HoverButton(symbolName: "chevron.right",
                                    accessibilityDescription: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)
        setupLongPressForButton(forwardButton, action: #selector(showForwardHistory))
        addSubview(forwardButton)

        reloadButton = HoverButton(symbolName: "arrow.clockwise",
                                   accessibilityDescription: "Reload")
        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped)
        addSubview(reloadButton)
        
        stopButton = HoverButton(symbolName: "xmark",
                                 accessibilityDescription: "Stop")
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.isHidden = true  // Initially hidden, shown during loading
        addSubview(stopButton)
        
        devNullIndicator = HoverButton(symbolName: "eye.slash",
                                       accessibilityDescription: "Dev Null Mode")
        devNullIndicator.target = self
        devNullIndicator.action = #selector(devNullIndicatorTapped)
        devNullIndicator.isHidden = true  // Initially hidden, shown only in /dev/null mode
        addSubview(devNullIndicator)
        
        urlBar = iTermURLBar()
        urlBar.delegate = self
        addSubview(urlBar)
        
        menuButton = HoverButton(symbolName: "line.3.horizontal",
                                 accessibilityDescription: "Menu")
        menuButton.target = self
        menuButton.action = #selector(menuTapped)
        addSubview(menuButton)
    }

    override func layout() {
        super.layout()
        layoutButtons()
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        layoutButtons()
    }

    @MainActor
    struct HorizontalLayoutHelper {
        enum Direction {
            case ltr
            case rtl
        }
        var direction: Direction
        var x = CGFloat(0)
        var spacing: CGFloat = 0

        mutating func add(_ view: NSView, extraSpacing: CGFloat = 0.0) {
            if let button = view as? NSButton {
                button.sizeToFit()
            }
            var frame = view.frame
            switch direction {
            case .ltr:
                break
            case .rtl:
                x -= frame.width
            }
            frame.origin.x = x
            view.frame = frame
            switch direction {
            case .ltr:
                x += frame.width + spacing + extraSpacing
            case .rtl:
                x -= spacing + extraSpacing
            }
        }

        // Set the frame of view to be centered between minX and maxX. It will take fraction % of
        // the space. If the available space is less than preferredMinWidth, fraction is disregarded
        // and all the space is used.
        mutating func addProportional(_ view: NSView, minX: CGFloat, maxX: CGFloat, preferredMinWidth: CGFloat, fraction: CGFloat) {
            let available = maxX - minX
            var proposed = available * fraction
            if proposed < preferredMinWidth {
                proposed = min(preferredMinWidth, available)
            }
            let unused = available - proposed
            let padding = unused / 2.0
            var frame = view.frame
            frame.origin.x = minX + padding
            frame.size.width = proposed
            view.frame = frame
        }
    }

    @MainActor
    struct VerticalLayoutHelper {
        var enclosureHeight: CGFloat

        func centerInEnclosure(_ view: NSView, fixedHeight: CGFloat? = nil) {
            var frame = view.frame
            if let fixedHeight {
                frame.size.height = fixedHeight
            }
            frame.origin.y = (enclosureHeight - frame.height) / 2.0
            view.frame = frame
        }
    }

    private func layoutButtons() {
        var leftHelper = HorizontalLayoutHelper(direction: .ltr, x: 8, spacing: 0)

        leftHelper.add(backButton)
        leftHelper.add(forwardButton)
        leftHelper.add(reloadButton)
        leftHelper.x += 12.0

        var rightHelper = HorizontalLayoutHelper(direction: .rtl, x: bounds.maxX, spacing: 0)

        rightHelper.add(menuButton)
        if !devNullIndicator.isHidden {
            rightHelper.add(devNullIndicator)
        }
        rightHelper.x -= 12.0

        leftHelper.addProportional(urlBar, minX: leftHelper.x, maxX: rightHelper.x, preferredMinWidth: 250.0, fraction: 0.55)

        let verticalHelper = VerticalLayoutHelper(enclosureHeight: bounds.height)
        verticalHelper.centerInEnclosure(backButton)
        verticalHelper.centerInEnclosure(forwardButton)
        verticalHelper.centerInEnclosure(reloadButton)
        verticalHelper.centerInEnclosure(stopButton)
        verticalHelper.centerInEnclosure(menuButton)
        verticalHelper.centerInEnclosure(devNullIndicator)
        verticalHelper.centerInEnclosure(urlBar, fixedHeight: 28.0)
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
    
    @objc private func devNullIndicatorTapped() {
        showDevNullInfoPopover()
    }
    
    // URL submission is now handled by iTermURLBar delegate
    
    @objc private func menuTapped() {
        showMainMenu()
    }
    
    private func showMainMenu() {
        let menu = NSMenu()
        
        // Add/Remove Bookmark menu item
        Task { @MainActor in
            let currentURL = delegate?.browserToolbarCurrentURL()
            let isBookmarked = await delegate?.browserToolbarIsCurrentURLBookmarked() ?? false
            let readerAvailable = (await delegate?.browserToolbarShouldOfferReaderMode() == true)
            if readerAvailable {
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

                menu.addItem(NSMenuItem.separator())

                let askAIItem = NSMenuItem(title: "Ask AI…", action: #selector(askAIMenuItemSelected), keyEquivalent: "")
                askAIItem.target = self
                askAIItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
                menu.addItem(askAIItem)

            }

            if devNullIndicator.isHidden {
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
            }

            menu.addItem(NSMenuItem.separator())

#if DEBUG
            // Debug Autofill menu item (debug builds only)
            let debugAutofillItem = NSMenuItem(title: "Debug Autofill Fields", action: #selector(debugAutofillMenuItemSelected), keyEquivalent: "")
            debugAutofillItem.target = self
            debugAutofillItem.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: nil)
            menu.addItem(debugAutofillItem)
            menu.addItem(NSMenuItem.separator())
#endif

            // Site permissions
            let tuple = await delegate?.browserToolbarPermissionsForCurrentSite()
            if let tuple, !tuple.0.isEmpty {
                let (permissions, origin) = tuple
                let sortedPermissionTypes = permissions.keys.sorted { $0.displayName < $1.displayName }
                for key in sortedPermissionTypes {
                    let value = permissions[key]!
                    let item = NSMenuItem(title: "Reset " + key.displayName +  " Permission (" + value.displayName + ")",
                                          action: #selector(resetPermission(_:)),
                                          keyEquivalent: "")
                    item.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
                    item.representedObject = [key.rawValue, origin]
                    item.target = self
                    menu.addItem(item)
                }
                menu.addItem(NSMenuItem.separator())
            }

            if delegate?.browserToolbarIsCurrentPageMuted() == true {
                let item = NSMenuItem(title: "Unmute Current Page",
                                      action: #selector(unmute(_:)),
                                      keyEquivalent: "")
                item.image = NSImage(systemSymbolName: "speaker.slash", accessibilityDescription: nil)
                item.representedObject = currentURL
                item.target = self
                menu.addItem(item)
                menu.addItem(NSMenuItem.separator())
            }

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

    @objc private func unmute(_ sender: Any?) {
        if let delegate,
           let url = (sender as? NSMenuItem)?.representedObject as? String {
           delegate.browserToolbarUnmute(url: url)
        }
    }

    @objc private func resetPermission(_ sender: Any?) {
        if let delegate,
           let strings = (sender as? NSMenuItem)?.representedObject as? [String],
           strings.count == 2,
           let key = BrowserPermissionType(rawValue: strings[0]) {
            Task {
                await delegate.browserToolbarResetPermission(for: key,
                                                             origin: strings[1])
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
    
    func setDevNullMode(_ isDevNull: Bool) {
        devNullIndicator.isHidden = !isDevNull
    }
    
    private func showDevNullInfoPopover() {
        devNullIndicator.it_showInformativeMessage(withMarkdown: """
        ## /dev/null Mode
        
        Your browsing activity is not being saved. No history, bookmarks, or other data will be stored.
        
        This mode is set in the browser’s Profile under **Settings > Profile > Web > Privacy**.
        
        ## 🙈 🙉 🙊
        """)
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

@MainActor
extension iTermBrowserToolbar: iTermURLBarDelegate {
    func urlBarDidSubmitURL(url: String) {
        delegate?.browserToolbarDidSubmitURL(url)
    }
    
    func urlBarDidRequestSuggestions(query: String) async -> [URLSuggestion] {
        return await delegate?.browserToolbarDidRequestSuggestions(query) ?? []
    }
    
    func urlBarDidBeginEditing(string: String) -> String? {
        return delegate?.browserToolbarDidBeginEditingURL(string: string)
    }
    
    func urlBarDidEndEditing() {
        delegate?.browserToolbarUserDidSubmitNavigationRequest()
    }
}

