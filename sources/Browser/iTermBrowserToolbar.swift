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
@objc protocol iTermBrowserToolbarDelegate {
    func browserToolbarDidTapReload()
    func browserToolbarDidTapStop()
    func browserToolbarDidSubmitURL(_ url: String)
    func browserToolbarDidTapSettings()
    func browserToolbarBackHistoryItems() -> [iTermBrowserHistoryItem]
    func browserToolbarForwardHistoryItems() -> [iTermBrowserHistoryItem]
    func browserToolbarDidSelectHistoryItem(steps: Int)
}

@available(macOS 11.0, *)
@objc(iTermBrowserToolbar)
class iTermBrowserToolbar: NSView {
    weak var delegate: iTermBrowserToolbarDelegate?
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var reloadButton: NSButton!
    private var stopButton: NSButton!
    private var urlField: NSTextField!
    private var settingsButton: NSButton!

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
        
        urlField = NSTextField()
        urlField.placeholderString = "Enter URL"
        urlField.target = self
        urlField.action = #selector(urlFieldSubmitted)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlField)
        
        settingsButton = NSButton()
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.target = self
        settingsButton.action = #selector(settingsTapped)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsButton)
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
            
            urlField.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 12),
            urlField.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlField.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -12),
            urlField.heightAnchor.constraint(equalToConstant: 24),
            
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 32),
            settingsButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc private func backTapped() {
        delegate?.browserToolbarDidSelectHistoryItem(steps: -1)
    }

    @objc private func forwardTapped() {
        delegate?.browserToolbarDidSelectHistoryItem(steps: 1)
    }

    @objc private func reloadTapped() {
        delegate?.browserToolbarDidTapReload()
    }
    
    @objc private func stopTapped() {
        delegate?.browserToolbarDidTapStop()
    }
    
    @objc private func urlFieldSubmitted() {
        let urlString = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.isEmpty {
            delegate?.browserToolbarDidSubmitURL(urlString)
        }
    }
    
    @objc private func settingsTapped() {
        delegate?.browserToolbarDidTapSettings()
    }
    
    // MARK: - Public Interface
    
    func updateURL(_ url: String?) {
        urlField.stringValue = url ?? ""
    }
    
    func setLoading(_ loading: Bool) {
        reloadButton.isHidden = loading
        stopButton.isHidden = !loading
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

