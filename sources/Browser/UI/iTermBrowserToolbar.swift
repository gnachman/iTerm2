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
    private var indicatorsView: iTermBrowserIndicatorsView!
    private var menuButton: NSButton!
    var indicatorsHelper: iTermIndicatorsHelper?
    var sessionGuid: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButtons()
    }

    private func setupButtons() {
        backButton = HoverButton(symbolName: SFSymbol.chevronLeft.rawValue,
                                 accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(backTapped)
        setupLongPressForButton(backButton, action: #selector(showBackHistory))
        addSubview(backButton)

        forwardButton = HoverButton(symbolName: SFSymbol.chevronRight.rawValue,
                                    accessibilityDescription: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(forwardTapped)
        setupLongPressForButton(forwardButton, action: #selector(showForwardHistory))
        addSubview(forwardButton)

        reloadButton = HoverButton(symbolName: SFSymbol.arrowClockwise.rawValue,
                                   accessibilityDescription: "Reload")
        reloadButton.target = self
        reloadButton.action = #selector(reloadTapped)
        addSubview(reloadButton)
        
        stopButton = HoverButton(symbolName: SFSymbol.xmark.rawValue,
                                 accessibilityDescription: "Stop")
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.isHidden = true  // Initially hidden, shown during loading
        addSubview(stopButton)
        
        devNullIndicator = HoverButton(symbolName: SFSymbol.eyeSlash.rawValue,
                                       accessibilityDescription: "Dev Null Mode")
        devNullIndicator.target = self
        devNullIndicator.action = #selector(devNullIndicatorTapped)
        devNullIndicator.isHidden = true  // Initially hidden, shown only in /dev/null mode
        addSubview(devNullIndicator)
        
        urlBar = iTermURLBar()
        urlBar.delegate = self
        addSubview(urlBar)
        
        indicatorsView = iTermBrowserIndicatorsView()
        addSubview(indicatorsView)
        
        menuButton = HoverButton(symbolName: SFSymbol.line3Horizontal.rawValue,
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
        
        // Position indicators next to menu button - they can shrink but have a minimum size
        let totalAvailableSpace = rightHelper.x - leftHelper.x
        let minUrlBarWidth: CGFloat = 250.0
        let minIndicatorsWidth: CGFloat = 24.0
        let maxIndicatorsWidth: CGFloat = 120.0
        let spacing: CGFloat = 12.0
        
        var indicatorsWidth: CGFloat = 0

        // Check if we have space for URL bar + minimum indicators
        if totalAvailableSpace >= minUrlBarWidth + minIndicatorsWidth + spacing {
            // Calculate how much space we can give to indicators
            let spaceForIndicators = totalAvailableSpace - minUrlBarWidth - spacing
            indicatorsWidth = min(maxIndicatorsWidth, max(minIndicatorsWidth, spaceForIndicators * 0.3))
            
            // Position indicators
            rightHelper.x -= indicatorsWidth + spacing
            indicatorsView.frame = NSRect(x: rightHelper.x + spacing, y: 0, width: indicatorsWidth, height: bounds.height)
            indicatorsView.isHidden = false
        } else {
            // Not enough space, hide indicators
            indicatorsView.isHidden = true
        }
        
        // Now center URL bar in remaining space
        let remainingSpace = rightHelper.x - leftHelper.x
        let urlBarWidth = max(remainingSpace * 0.6, minUrlBarWidth)
        let urlBarX = leftHelper.x + (remainingSpace - urlBarWidth) / 2.0
        urlBar.frame = NSRect(x: urlBarX, y: 0, width: urlBarWidth, height: bounds.height)

        let verticalHelper = VerticalLayoutHelper(enclosureHeight: bounds.height)
        verticalHelper.centerInEnclosure(backButton)
        verticalHelper.centerInEnclosure(forwardButton)
        verticalHelper.centerInEnclosure(reloadButton)
        verticalHelper.centerInEnclosure(stopButton)
        verticalHelper.centerInEnclosure(menuButton)
        verticalHelper.centerInEnclosure(devNullIndicator)
        verticalHelper.centerInEnclosure(indicatorsView)
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

    func checkIndicatorsForUpdate() {
        indicatorsView.updateIndicators()
    }
    
    func configureIndicators(indicatorsHelper: iTermIndicatorsHelper, sessionGuid: String) {
        self.indicatorsHelper = indicatorsHelper
        self.sessionGuid = sessionGuid
        indicatorsView.configure(indicatorsHelper: indicatorsHelper, sessionGuid: sessionGuid)
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
                let readerModeIcon = isReaderModeActive ? SFSymbol.docTextFill.rawValue : SFSymbol.docText.rawValue
                let readerModeItem = NSMenuItem(title: readerModeTitle, action: #selector(readerModeMenuItemSelected), keyEquivalent: "")
                readerModeItem.target = self
                readerModeItem.image = NSImage(systemSymbolName: readerModeIcon, accessibilityDescription: nil)
                readerModeItem.isEnabled = currentURL != nil
                menu.addItem(readerModeItem)

                // Distraction Removal menu item
                let isDistractionRemovalActive = delegate?.browserToolbarIsDistractionRemovalActive() ?? false
                let distractionRemovalTitle = isDistractionRemovalActive ? "Exit Distraction Removal" : "Remove Distractions"
                let distractionRemovalIcon = isDistractionRemovalActive ? SFSymbol.target.rawValue : SFSymbol.scope.rawValue
                let distractionRemovalItem = NSMenuItem(title: distractionRemovalTitle, action: #selector(distractionRemovalMenuItemSelected), keyEquivalent: "")
                distractionRemovalItem.target = self
                distractionRemovalItem.image = NSImage(systemSymbolName: distractionRemovalIcon, accessibilityDescription: nil)
                distractionRemovalItem.isEnabled = currentURL != nil
                menu.addItem(distractionRemovalItem)

                menu.addItem(NSMenuItem.separator())

                let askAIItem = NSMenuItem(title: "Ask AI…", action: #selector(askAIMenuItemSelected), keyEquivalent: "")
                askAIItem.target = self
                askAIItem.image = NSImage(systemSymbolName: SFSymbol.sparkles.rawValue, accessibilityDescription: nil)
                menu.addItem(askAIItem)

            }

            if devNullIndicator.isHidden {
                let bookmarkTitle = isBookmarked ? "Remove Bookmark" : "Add Bookmark"
                let bookmarkIcon = isBookmarked ? SFSymbol.bookmarkFill.rawValue : SFSymbol.bookmark.rawValue
                let bookmarkItem = NSMenuItem(title: bookmarkTitle, action: #selector(bookmarkMenuItemSelected), keyEquivalent: "")
                bookmarkItem.target = self
                bookmarkItem.image = NSImage(systemSymbolName: bookmarkIcon, accessibilityDescription: nil)
                bookmarkItem.isEnabled = currentURL != nil
                menu.addItem(bookmarkItem)

                menu.addItem(NSMenuItem.separator())

                // Manage Bookmarks menu item
                let manageBookmarksItem = NSMenuItem(title: "Manage Bookmarks", action: #selector(manageBookmarksMenuItemSelected), keyEquivalent: "")
                manageBookmarksItem.target = self
                manageBookmarksItem.image = NSImage(systemSymbolName: SFSymbol.book.rawValue, accessibilityDescription: nil)
                menu.addItem(manageBookmarksItem)

                // History menu item
                let historyItem = NSMenuItem(title: "History", action: #selector(historyMenuItemSelected), keyEquivalent: "")
                historyItem.target = self
                historyItem.image = NSImage(systemSymbolName: SFSymbol.clock.rawValue, accessibilityDescription: nil)
                menu.addItem(historyItem)
            }

            menu.addItem(NSMenuItem.separator())

#if DEBUG
            // Debug Autofill menu item (debug builds only)
            let debugAutofillItem = NSMenuItem(title: "Debug Autofill Fields", action: #selector(debugAutofillMenuItemSelected), keyEquivalent: "")
            debugAutofillItem.target = self
            debugAutofillItem.image = NSImage(systemSymbolName: SFSymbol.magnifyingglassCircle.rawValue, accessibilityDescription: nil)
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
                    item.image = NSImage(systemSymbolName: SFSymbol.handRaised.rawValue, accessibilityDescription: nil)
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
                item.image = NSImage(systemSymbolName: SFSymbol.speakerSlash.rawValue, accessibilityDescription: nil)
                item.representedObject = currentURL
                item.target = self
                menu.addItem(item)
                menu.addItem(NSMenuItem.separator())
            }

            // Settings menu item
            let settingsItem = NSMenuItem(title: "Settings", action: #selector(settingsMenuItemSelected), keyEquivalent: "")
            settingsItem.target = self
            settingsItem.image = NSImage(systemSymbolName: SFSymbol.gearshape.rawValue, accessibilityDescription: nil)
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
        updateFavicon(SFSymbol.globe.nsimage)
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

