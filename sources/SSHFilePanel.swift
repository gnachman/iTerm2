//
//  SSHFilePanel.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

import Foundation
import Cocoa

// MARK: - Data Source Protocol

/// Protocol for providing data to the remote file panel
@MainActor
protocol SSHFilePanelDataSource: AnyObject {
    /// Get the SSH endpoint for a connected host. This provides access to the remote file system.
    func remoteFilePanelSSHEndpoint(for identity: SSHIdentity) -> SSHEndpoint?

    /// Gets a list of currently available SSH identities.
    func remoteFilePanelConnectedHosts() -> [SSHIdentity]
}

class SSHFilePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }
        if let delegate, let responder = delegate as? NSResponder, responder.performKeyEquivalent(with: event) {
            return true
        }
        return false
    }
}

@available(macOS 11, *)
class SSHFilePanel: NSWindowController {
    // MARK: - UI Components
    private var splitView: NSSplitView!
    private var mainContentView: NSView!
    private var toolbarView: NSView!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var locationButton: SSHFilePanelLocationButton!
    private var searchField: NSSearchField!
    private var fileList: SSHFilePanelFileList!
    private var buttonStackView: NSStackView!
    private var cancelButton: NSButton!
    private var openButton: NSButton!
    private let sidebar = SSHFilePanelSidebar()
    private var completionHandler: ((NSApplication.ModalResponse) -> Void)?
    private var navigationHistory: [String] = []
    private var historyIndex: Int = -1

    // MARK: - Data Properties
    weak var dataSource: SSHFilePanelDataSource? {
        didSet {
            if dataSource != nil {
                updateViews()
            }
        }
    }

    private var currentEndpoint: SSHEndpoint?
    private var currentPath: String = "/"

    // MARK: - Constants
    private let minimumWindowWidth: CGFloat = 550
    private let minimumSidebarWidth: CGFloat = 180
    private let maximumSidebarWidth: CGFloat = 300

    // MARK: - Initialization
    init() {
        let window = SSHFilePanelWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                                        styleMask: [.resizable, .fullSizeContentView],
                                        backing: .buffered,
                                        defer: false)
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.worksWhenModal = true
        window.becomesKeyOnlyIfNeeded = false
        super.init(window: window)

        window.delegate = self

        setupUI()
        setupWindow()

        window.makeFirstResponder(fileList.documentView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        setupWindow()
    }

    // MARK: - Data Source Updates
    @MainActor
    private func updateViews() {
        guard let dataSource = dataSource else { return }

        let connectedHosts = dataSource.remoteFilePanelConnectedHosts()

        // Use first available host for now
        if let firstHost = connectedHosts.first {
            currentEndpoint = dataSource.remoteFilePanelSSHEndpoint(for: firstHost)
            currentPath = currentEndpoint?.homeDirectory ?? "/"
            updateViewsForCurrentPath()
        }

        sidebar.connectedHosts = connectedHosts
    }

    @MainActor
    private func updateViewsForCurrentPath() {
        locationButton.removeAllItems()
        guard let endpoint = currentEndpoint else {
            return
        }

        // Set up target/action for location button
        locationButton.set(path: currentPath, sshIdentity: endpoint.sshIdentity)
        fileList.set(path: currentPath, endpoint: endpoint)
    }

    @MainActor
    private func navigateToPath(_ path: String) async {
        guard let endpoint = currentEndpoint else { return }

        do {
            // Verify the path exists
            let _ = try await endpoint.stat(path)
            currentPath = path
            updateViewsForCurrentPath()
        } catch {
            print("Failed to navigate to path \(path): \(error)")
        }
    }

    // MARK: - UI Setup
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        setupSplitView(in: contentView)
        setupSidebar()
        setupMainContent()

        // Set sidebar width after UI is set up
        DispatchQueue.main.async {
            self.splitView.setPosition(200, ofDividerAt: 0)
        }
    }

    private func setupWindow() {
        window?.title = "Open"
        window?.center()
        window?.isRestorable = false
        window?.delegate = self

        // Set minimum window size - will be updated dynamically
        updateMinimumWindowSize()
        setupKeyboardShortcuts()
        restoreWindowState()
    }

    private func updateMinimumWindowSize() {
        guard let window = window else { return }

        // Calculate minimum width based on split view constraints
        let minSidebarWidth = minimumSidebarWidth
        let minMainContentWidth: CGFloat = 366 // From toolbar constraints
        let dividerWidth = splitView?.dividerThickness ?? 1

        let totalMinWidth = minSidebarWidth + minMainContentWidth + dividerWidth

        window.minSize = NSSize(width: totalMinWidth, height: 400)
    }

    private func setupSplitView(in contentView: NSView) {
        splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.dividerStyle = .thin
        splitView.isVertical = true
        splitView.delegate = self

        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(251), forSubviewAt: 0)
    }

    private func setupSidebar() {
        // Create sidebar container
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(sidebar)
    }

    private func setupMainContent() {
        mainContentView = NSView()
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.wantsLayer = true
        mainContentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        // Setup toolbar
        setupToolbar()
        
        // Create separator line
        let separatorLine = NSView()
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = NSColor.separatorColor.cgColor

        let separatorLine2 = NSView()
        separatorLine2.translatesAutoresizingMaskIntoConstraints = false
        separatorLine2.wantsLayer = true
        separatorLine2.layer?.backgroundColor = NSColor.separatorColor.cgColor

        // Setup file table
        setupFileTable()
        
        // Setup buttons
        setupButtons()
        
        // Create main vertical stack
        let mainStackView = NSStackView(views: [toolbarView, separatorLine, fileList, separatorLine2, buttonStackView])
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.orientation = .vertical
        mainStackView.alignment = .leading
        mainStackView.distribution = .fill
        mainStackView.spacing = 0
        
        mainContentView.addSubview(mainStackView)
        splitView.addSubview(mainContentView)
        
        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            mainStackView.topAnchor.constraint(equalTo: mainContentView.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor),
            
            // Toolbar height
            toolbarView.heightAnchor.constraint(equalToConstant: 44),
            
            // Separator line height
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
            separatorLine2.heightAnchor.constraint(equalToConstant: 1),

            // Button stack height
            buttonStackView.heightAnchor.constraint(equalToConstant: 44),
            
            // Make sure elements stretch to full width
            toolbarView.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
            fileList.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            fileList.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
            buttonStackView.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
        ])
    }

    private func setupToolbar() {
        // Create toolbar container view
        toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false

        // Create buttons
        backButton = NSButton()
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.bezelStyle = .texturedRounded
        backButton.image = NSImage.it_image(forSymbolName: "chevron.left",
                                            accessibilityDescription: "Back",
                                            fallbackImageName: "chevron.left",
                                            for: SSHFilePanel.self)
        backButton.isEnabled = false
        backButton.target = self
        backButton.action = #selector(backButtonClicked)

        forwardButton = NSButton()
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.bezelStyle = .texturedRounded
        forwardButton.image = NSImage.it_image(forSymbolName: "chevron.right",
                                               accessibilityDescription: "Forward",
                                               fallbackImageName: "chevron.right",
                                               for: SSHFilePanel.self)
        forwardButton.isEnabled = false
        forwardButton.target = self
        forwardButton.action = #selector(forwardButtonClicked)

        // Location button (popup style like in Finder)
        // Location button (popup style like in Finder)
        locationButton = SSHFilePanelLocationButton()
        locationButton.target = self
        locationButton.action = #selector(locationButtonChanged)
        locationButton.translatesAutoresizingMaskIntoConstraints = false

        // Search field
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)

        // Add all toolbar items to the toolbar view
        toolbarView.addSubview(backButton)
        toolbarView.addSubview(forwardButton)
        toolbarView.addSubview(locationButton)
        toolbarView.addSubview(searchField)

        // Position toolbar items with constraints
        let centerXConstraint = locationButton.centerXAnchor.constraint(equalTo: toolbarView.centerXAnchor)
        let minSpacingRightConstraint = searchField.leadingAnchor.constraint(greaterThanOrEqualTo: locationButton.trailingAnchor, constant: 20)
        let minSpacingLeftConstraint = locationButton.leadingAnchor.constraint(greaterThanOrEqualTo: forwardButton.trailingAnchor, constant: 20)

        // Search field width constraints with different priorities
        let searchFieldMinWidthConstraint = searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        let searchFieldMaxWidthConstraint = searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        let searchFieldPreferredWidthConstraint = searchField.widthAnchor.constraint(equalToConstant: 150)

        // Set priorities: spacing constraints are required, centering is preferred but can be broken
        centerXConstraint.priority = NSLayoutConstraint.Priority(999) // High but not required
        minSpacingRightConstraint.priority = NSLayoutConstraint.Priority.required
        minSpacingLeftConstraint.priority = NSLayoutConstraint.Priority.required

        // Search field width priorities - allow it to shrink when space is tight
        searchFieldMinWidthConstraint.priority = NSLayoutConstraint.Priority(750) // Can be broken
        searchFieldMaxWidthConstraint.priority = NSLayoutConstraint.Priority.required
        searchFieldPreferredWidthConstraint.priority = NSLayoutConstraint.Priority(800) // Preferred but breakable

        NSLayoutConstraint.activate([
            // Back button - left aligned with margin
            backButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 20),

            // Forward button - next to back button
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 24),
            forwardButton.heightAnchor.constraint(equalToConstant: 20),

            // Location button - horizontally centered in toolbar (with priority)
            centerXConstraint,
            locationButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            locationButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            locationButton.widthAnchor.constraint(lessThanOrEqualToConstant: 210),

            // Search field - right aligned with margin
            searchField.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            searchFieldMinWidthConstraint,
            searchFieldMaxWidthConstraint,
            searchFieldPreferredWidthConstraint,

            // Prevent overlap: minimum spacing constraints (required priority)
            minSpacingRightConstraint,
            minSpacingLeftConstraint
        ])

        // Set content compression resistance priorities
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        locationButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    private func setupFileTable() {
        fileList = SSHFilePanelFileList()
        fileList.translatesAutoresizingMaskIntoConstraints = false
        fileList.delegate = self
    }

    private func setupButtons() {
        cancelButton = NSButton()
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        cancelButton.keyEquivalentModifierMask = []
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked(_:))

        openButton = NSButton()
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.title = "Open"
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r" // Return
        openButton.isEnabled = false
        openButton.target = self
        openButton.action = #selector(openButtonClicked)

        // Create button stack with right alignment and proper spacing
        let spacerView = NSView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false

        let rightSpacer = NSView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false

        buttonStackView = NSStackView(views: [spacerView, cancelButton, openButton, rightSpacer])
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.distribution = .fill
        buttonStackView.spacing = 12

        NSLayoutConstraint.activate([
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            rightSpacer.widthAnchor.constraint(equalToConstant: 8)
        ])
    }

    // MARK: - Actions

    @objc private func locationButtonChanged(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let path = selectedItem.representedObject as? String else { return }

        Task {
            await navigateToPathWithHistory(path)
        }
        locationButton.set(path: path, sshIdentity: locationButton.sshIdentity!)
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        // TODO: Implement search functionality
        print("Search changed to: \(sender.stringValue)")
    }

    @objc private func cancelButtonClicked(_ sender: Any) {
        // Sheet presentation
        if let sheetParent = window?.sheetParent {
            sheetParent.endSheet(window!, returnCode: .cancel)
        }
        // Modal presentation
        else if NSApp.modalWindow == window {
            NSApp.stopModal(withCode: .cancel)
        }
        // Non-modal presentation
        else {
            window?.close()
        }
    }

    @objc private func openButtonClicked(_ sender: NSButton) {
        // Sheet presentation
        if let sheetParent = window?.sheetParent {
            sheetParent.endSheet(window!, returnCode: .OK)
        }
        // Modal presentation
        else if NSApp.modalWindow == window {
            NSApp.stopModal(withCode: .OK)
        }
        // Non-modal presentation
        else {
            completionHandler?(.OK)
            completionHandler = nil
            window?.close()
        }
    }

    // MARK: - Public Interface
    func runModal() -> NSApplication.ModalResponse {
        return NSApp.runModal(for: window!)
    }

    func beginSheetModal(for parentWindow: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        parentWindow.beginSheet(window!, completionHandler: handler)
    }
}

// MARK: - NSWindowDelegate
@available(macOS 11, *)
extension SSHFilePanel: NSWindowDelegate {
    func show(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completionHandler = completionHandler
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowState()

        // Handle non-modal completion
        if window?.sheetParent == nil && NSApp.modalWindow != window {
            completionHandler?(.cancel)
            completionHandler = nil
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // The split view delegate methods now handle most size constraints,
        // but we still enforce an absolute minimum to prevent any edge cases
        var newSize = frameSize

        if newSize.width < minimumWindowWidth {
            newSize.width = minimumWindowWidth
        }

        return newSize
    }
}

// MARK: - NSSplitViewDelegate

@available(macOS 11, *)
extension SSHFilePanel: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return minimumSidebarWidth
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Calculate max position based on minimum main content width
        let minMainContentWidth: CGFloat = 366
        let maxSidebarPosition = splitView.bounds.width - splitView.dividerThickness - minMainContentWidth

        return min(maximumSidebarWidth, maxSidebarPosition)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false // Don't allow collapsing either pane
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        // Let the split view handle resize automatically with our constraints
        splitView.adjustSubviews()

        // Update minimum window size when split view changes
        updateMinimumWindowSize()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        // Update minimum window size whenever subviews are resized
        updateMinimumWindowSize()
    }
}

// MARK: - Keyboard Shortcuts Extension
@available(macOS 11, *)
extension SSHFilePanel {

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.menu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Menu Setup
    func setupKeyboardShortcuts() {
        // Create a custom menu for the window to handle shortcuts
        let menu = NSMenu()

        // Go to Folder (Cmd+Shift+G)
        let goToFolderItem = NSMenuItem(title: "Go to Folder...",
                                       action: #selector(goToFolder),
                                       keyEquivalent: "g")
        goToFolderItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(goToFolderItem)

        // Go to Home (Cmd+Shift+H)
        let goToHomeItem = NSMenuItem(title: "Go to Home",
                                     action: #selector(goToHome),
                                     keyEquivalent: "h")
        goToHomeItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(goToHomeItem)

        // Go Up (Cmd+Up Arrow)
        let goUpItem = NSMenuItem(title: "Go Up",
                                 action: #selector(goUp),
                                 keyEquivalent: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
        goUpItem.keyEquivalentModifierMask = [.command]
        menu.addItem(goUpItem)

        // Navigate Back (Cmd+Left Arrow)
        let backItem = NSMenuItem(title: "Back",
                                 action: #selector(backButtonClicked),
                                 keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        backItem.keyEquivalentModifierMask = [.command]
        menu.addItem(backItem)

        // Navigate Forward (Cmd+Right Arrow)
        let forwardItem = NSMenuItem(title: "Forward",
                                    action: #selector(forwardButtonClicked),
                                    keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        forwardItem.keyEquivalentModifierMask = [.command]
        menu.addItem(forwardItem)

        // Refresh (Cmd+R)
        let refreshItem = NSMenuItem(title: "Refresh",
                                    action: #selector(refresh),
                                    keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = [.command]
        menu.addItem(refreshItem)

        window?.menu = menu
    }

    // MARK: - Keyboard Action Implementations

    @objc private func goToFolder() {
        showGoToFolderDialog()
    }

    @objc private func goToHome() {
        guard let endpoint = currentEndpoint else { return }
        let homePath = endpoint.homeDirectory ?? "/"
        Task {
            await navigateToPathWithHistory(homePath)
        }
    }

    @objc private func goUp() {
        let parentPath = (currentPath as NSString).deletingLastPathComponent
        if parentPath != currentPath && !parentPath.isEmpty {
            Task {
                await navigateToPathWithHistory(parentPath)
            }
        }
    }

    @objc private func refresh() {
        // Refresh current directory
        Task {
            await navigateToPath(currentPath)
        }
    }

    // MARK: - Go to Folder Dialog

    private func showGoToFolderDialog() {
        let alert = NSAlert()
        alert.messageText = "Go to the folder:"
        alert.informativeText = "Type a pathname or select from the pop-up menu"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = currentPath
        textField.placeholderString = "Enter path (e.g., /usr/local/bin)"

        // Create container view for text field with proper margins
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        containerView.addSubview(textField)

        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: 300),
            textField.heightAnchor.constraint(equalToConstant: 24)
        ])

        alert.accessoryView = containerView

        // Set the text field as first responder
        DispatchQueue.main.async {
            textField.becomeFirstResponder()
            textField.selectText(nil)
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let enteredPath = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !enteredPath.isEmpty {
                let expandedPath = expandPath(enteredPath)
                Task {
                    await navigateToPathWithHistory(expandedPath)
                }
            }
        }
    }

    private func expandPath(_ path: String) -> String {
        var expandedPath = path

        // Handle tilde expansion
        if expandedPath.hasPrefix("~") {
            if let endpoint = currentEndpoint {
                let homeDir = endpoint.homeDirectory ?? "/"
                if expandedPath == "~" {
                    expandedPath = homeDir
                } else if expandedPath.hasPrefix("~/") {
                    expandedPath = homeDir + String(expandedPath.dropFirst(1))
                }
            }
        }

        // Handle relative paths
        if !expandedPath.hasPrefix("/") {
            expandedPath = (currentPath as NSString).appendingPathComponent(expandedPath)
        }

        // Normalize path (handle .. and . components)
        expandedPath = (expandedPath as NSString).standardizingPath

        return expandedPath
    }
}

// MARK: - Window Restoration Extension
@available(macOS 11, *)
extension SSHFilePanel {

    // MARK: - Window Restoration State Keys
    private struct RestorationKeys {
        static let windowFrame = "SSHFilePanel.windowFrame"
        static let sidebarWidth = "SSHFilePanel.sidebarWidth"
        static let currentPath = "SSHFilePanel.currentPath"
        static let sshIdentity = "SSHFilePanel.sshIdentity"
    }

    // MARK: - Save State
    func saveWindowState() {
        guard let window = window else { return }

        let defaults = UserDefaults.standard

        // Save window frame
        let frameString = NSStringFromRect(window.frame)
        defaults.set(frameString, forKey: RestorationKeys.windowFrame)

        // Save sidebar width
        if splitView.subviews.count > 0 {
            let sidebarWidth = splitView.subviews[0].frame.width
            defaults.set(sidebarWidth, forKey: RestorationKeys.sidebarWidth)
        }

        // Save current path and SSH identity
        defaults.set(currentPath, forKey: RestorationKeys.currentPath)
        if let identity = currentEndpoint?.sshIdentity {
            if let identityData = try? JSONEncoder().encode(identity) {
                defaults.set(identityData, forKey: RestorationKeys.sshIdentity)
            }
        }

        defaults.synchronize()
    }

    // MARK: - Restore State
    private func restoreWindowState() {
        let defaults = UserDefaults.standard

        // Restore window frame
        if let frameString = defaults.string(forKey: RestorationKeys.windowFrame) {
            let frame = NSRectFromString(frameString)
            if !frame.isEmpty {
                // Ensure frame is on screen
                let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
                if visibleFrame.intersects(frame) {
                    window?.setFrame(frame, display: false)
                }
            }
        }

        // Restore sidebar width
        let sidebarWidth = defaults.double(forKey: RestorationKeys.sidebarWidth)
        if sidebarWidth > 0 {
            DispatchQueue.main.async {
                self.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            }
        }

        // Restore current path (will be used when data source is set)
        if let restoredPath = defaults.string(forKey: RestorationKeys.currentPath) {
            currentPath = restoredPath
        }
    }
}

// MARK: - Navigation History Support

@available(macOS 11, *)
extension SSHFilePanel {

    func navigateToPathWithHistory(_ path: String) async {
        // Save current path to history before navigating
        if historyIndex < navigationHistory.count - 1 {
            // Remove forward history if we're navigating to a new path
            navigationHistory.removeSubrange((historyIndex + 1)...)
        }

        navigationHistory.append(currentPath)
        historyIndex = navigationHistory.count - 1

        // Navigate to new path
        await navigateToPath(path)

        // Update button states
        updateNavigationButtons()
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = historyIndex > 0
        forwardButton.isEnabled = historyIndex < navigationHistory.count - 1
    }

    @objc private func backButtonClicked(_ sender: NSButton) {
        guard historyIndex > 0 else { return }

        historyIndex -= 1
        let previousPath = navigationHistory[historyIndex]

        Task {
            await navigateToPath(previousPath)
            updateNavigationButtons()
        }
    }

    @objc private func forwardButtonClicked(_ sender: NSButton) {
        guard historyIndex < navigationHistory.count - 1 else { return }

        historyIndex += 1
        let nextPath = navigationHistory[historyIndex]

        Task {
            await navigateToPath(nextPath)
            updateNavigationButtons()
        }
    }
}

@available(macOS 11, *)
extension SSHFilePanel: SSHFilePanelFileListDelegate {
    func sshFilePanelList(didSelect file: SSHFilePanelFileList.FileNode) {
        if file.isDirectory {
            Task { @MainActor in
                await navigateToPathWithHistory(file.file.absolutePath)
            }
        }
    }
}
