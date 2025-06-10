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
    func remoteFilePanelSSHEndpoints(for identity: SSHIdentity) -> [SSHEndpoint]

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

struct SSHFileDescriptor {
    let absolutePath: String
    let isDirectory: Bool
    let sshIdentity: SSHIdentity
}

class SSHMainContentView: iTermLayerBackedSolidColorView { }

@available(macOS 11, *)
class SSHFilePanel: NSWindowController {
    static let connectedHostsDidChangeNotification = Notification.Name("SSHFilePanelConnectedHostsDidChange")

    private var splitView: NSSplitView!
    private var mainContentView: SSHMainContentView!
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
    private var navigationHistory: [SSHFileDescriptor] = []
    private var historyIndex: Int = -1
    private var ignoreSidebarChange = 0
    private(set) var selectedFiles: [SSHFileDescriptor] = []
    private var lastPath = [SSHIdentity: String]()
    var canChooseDirectories = false
    var canChooseFiles = true
    private var initialized = false

    // MARK: - Data Properties
    weak var dataSource: SSHFilePanelDataSource? {
        didSet {
            if dataSource != nil {
                dataSourceDidChange()
            }
        }
    }

    private var currentEndpoint: SSHEndpoint?
    private var currentPath: SSHFileDescriptor?

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

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(connectedHostsDidChange(_:)),
                                               name: SSHFilePanel.connectedHostsDidChangeNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        setupWindow()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowState()
    }

    // MARK: - Notifications

    private func connectedHostsIncludingLocalhost() -> [SSHIdentity] {
        return (dataSource?.remoteFilePanelConnectedHosts() ?? []) + [SSHIdentity.localhost]
    }

    @objc func connectedHostsDidChange(_ notification: Notification) {
        let connectedHosts = connectedHostsIncludingLocalhost()
        if let currentIdentity = currentPath?.sshIdentity, !connectedHosts.contains(currentIdentity) {
            dataSourceDidChange()
        } else {
            sidebar.connectedHosts = connectedHosts
        }
        updateNavigationButtons()
    }

    // MARK: - Data Source Updates
    @MainActor
    private func dataSourceDidChange() {
        let connectedHosts = connectedHostsIncludingLocalhost()

        if let firstHost = connectedHosts.first {
            Task { @MainActor in
                await selectEndpoint(forIdentity: firstHost, initialPath: nil, withHistory: true)
            }
        } else {
            currentEndpoint = nil
            currentPath = nil
            updateViewsForCurrentPath()
        }

        sidebar.connectedHosts = connectedHosts
        initialized = true
    }

    private func defaultPathOptions(for sshIdentity: SSHIdentity) -> [String] {
        return [lastPath[sshIdentity],
                savedPath(for: sshIdentity),
                endpoint(for: sshIdentity)?.homeDirectory,
                "/"].compactMap { $0 }
    }

    private func defaultPath(for sshIdentity: SSHIdentity) -> String {
        return defaultPathOptions(for: sshIdentity).first!
    }

    @discardableResult
    private func selectEndpoint(forIdentity sshIdentity: SSHIdentity,
                                initialPath: String?,
                                withHistory: Bool) async -> Bool {
        currentEndpoint = endpoint(for: sshIdentity)
        if currentEndpoint != nil {
            sidebar.selectedIdentity = sshIdentity
            currentPath = SSHFileDescriptor(absolutePath: defaultPath(for: sshIdentity),
                                            isDirectory: true,
                                            sshIdentity: sshIdentity)
            defer {
                updateViewsForCurrentPath()
            }
            if withHistory {
                return await navigateToPathWithHistory(SSHFileDescriptor(
                    absolutePath: initialPath ?? defaultPath(for: sshIdentity),
                    isDirectory: true,
                    sshIdentity: sshIdentity))
            }
            return await navigateToPath(SSHFileDescriptor(
                absolutePath: initialPath ?? defaultPath(for: sshIdentity),
                isDirectory: true,
                sshIdentity: sshIdentity))
        } else {
            sidebar.selectedIdentity = nil
            currentPath = nil
            updateViewsForCurrentPath()
            return true
        }
    }

    private func endpoint(for identity: SSHIdentity) -> SSHEndpoint? {
        if identity == SSHIdentity.localhost {
            return LocalhostEndpoint.instance
        }
        return dataSource?.remoteFilePanelSSHEndpoints(for: identity).first
    }

    @MainActor
    private func updateViewsForCurrentPath() {
        locationButton.removeAllItems()
        guard let currentPath, let endpoint = self.endpoint(for: currentPath.sshIdentity) else {
            return
        }

        // Set up target/action for location button
        locationButton.set(path: currentPath.absolutePath, sshIdentity: currentPath.sshIdentity)
        fileList.set(path: currentPath.absolutePath, endpoint: endpoint)
    }

    @MainActor
    @discardableResult
    private func navigateToPath(_ path: SSHFileDescriptor) async -> Bool {
        guard let endpoint = self.endpoint(for: path.sshIdentity) else {
            return false
        }

        do {
            // Verify the path exists
            let _ = try await endpoint.stat(path.absolutePath)
            lastPath[path.sshIdentity] = path.absolutePath
            if path.sshIdentity != currentPath?.sshIdentity {
                ignoreSidebarChange += 1
                defer {
                    ignoreSidebarChange -= 1
                }
                return await selectEndpoint(forIdentity: path.sshIdentity,
                                            initialPath: path.absolutePath,
                                            withHistory: false)
            } else {
                currentPath = path
                updateViewsForCurrentPath()
                return true
            }
        } catch {
            print("Failed to navigate to path \(path): \(error)")
        }
        return false
    }

    // MARK: - UI Setup
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        setupSplitView(in: contentView)
        setupSidebar()
        setupMainContent()
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

        DispatchQueue.main.async { [weak self] in
            self?.fileList.takeFirstResponder()
        }
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
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(sidebar)
        sidebar.delegate = self
    }

    private func setupMainContent() {
        mainContentView = SSHMainContentView()
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.wantsLayer = true
        mainContentView.color = NSColor.controlBackgroundColor

        // Setup toolbar
        setupToolbar()
        
        // Create separator line
        let separatorLine = iTermLayerBackedSolidColorView()
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.wantsLayer = true
        separatorLine.color = NSColor.separatorColor

        let separatorLine2 = iTermLayerBackedSolidColorView()
        separatorLine2.translatesAutoresizingMaskIntoConstraints = false
        separatorLine2.wantsLayer = true
        separatorLine2.color = NSColor.separatorColor

        // Setup file table
        setupFileTable()
        
        // Setup buttons
        setupButtons()

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let spacer2 = NSView()
        spacer2.translatesAutoresizingMaskIntoConstraints = false

        let spacer3 = NSView()
        spacer3.translatesAutoresizingMaskIntoConstraints = false

        // Create main vertical stack
        let mainStackView = NSStackView(views: [spacer, toolbarView, separatorLine, fileList, separatorLine2, spacer2, buttonStackView, spacer3])
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.orientation = .vertical
        mainStackView.alignment = .leading
        mainStackView.distribution = .fill
        mainStackView.spacing = 0
        
        mainContentView.addSubview(mainStackView)
        splitView.addSubview(mainContentView)
        
        NSLayoutConstraint.activate([
            spacer.heightAnchor.constraint(equalToConstant: 9),

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

            spacer3.heightAnchor.constraint(equalToConstant: 8),

            buttonStackView.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),

            spacer2.heightAnchor.constraint(equalToConstant: 8),
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
            backButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 20),
            backButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 20),

            // Forward button - next to back button
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor),
            forwardButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 24),
            forwardButton.heightAnchor.constraint(equalToConstant: 20),

            // Location button - horizontally centered in toolbar (with priority)
            centerXConstraint,
            locationButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            locationButton.widthAnchor.constraint(equalToConstant: 208),

            // Search field - right aligned with margin
            searchField.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -20),
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
        fileList.canChooseDirectories = canChooseDirectories
        fileList.canChooseFiles = canChooseFiles

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
              let path = selectedItem.representedObject as? String,
              let currentIdentity = currentEndpoint?.sshIdentity else {
            return
        }

        Task {
            await navigateToPathWithHistory(SSHFileDescriptor(
                absolutePath: path,
                isDirectory: true,
                sshIdentity: currentIdentity))
        }
        locationButton.set(path: path, sshIdentity: locationButton.sshIdentity!)
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        // TODO: Implement search functionality
        print("Search changed to: \(sender.stringValue)")
    }

    @objc private func cancelButtonClicked(_ sender: Any) {
        saveWindowState()
        if let sheetParent = window?.sheetParent {
            // Sheet presentation
            sheetParent.endSheet(window!, returnCode: .cancel)
        } else if NSApp.modalWindow == window {
            // Modal presentation
            NSApp.stopModal(withCode: .cancel)
        } else {
            // Non-modal presentation
            window?.close()
        }
    }

    @objc private func openButtonClicked(_ sender: NSButton) {
        guard let currentIdentity = currentEndpoint?.sshIdentity else {
            cancelButtonClicked(self)
            return
        }
        let selection = fileList.selectedFiles
        if selection.count == 1 && selection[0].isDirectory && !canChooseDirectories {
            Task { @MainActor in
                await navigateToPathWithHistory(SSHFileDescriptor(
                    absolutePath: selection[0].file.absolutePath,
                    isDirectory: true,
                    sshIdentity: currentIdentity) )
            }
            return
        }

        guard let endpoint = currentEndpoint else {
            cancelButtonClicked(sender)
            return
        }
        saveWindowState()
        self.selectedFiles = selection.map {
            SSHFileDescriptor(absolutePath: $0.file.absolutePath,
                              isDirectory: $0.isDirectory,
                              sshIdentity: endpoint.sshIdentity)
        }
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
        saveWindowState()
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
            await navigateToPathWithHistory(SSHFileDescriptor(
                absolutePath: homePath,
                isDirectory: true,
                sshIdentity: endpoint.sshIdentity))
        }
    }

    @objc private func goUp() {
        let parentPath = (currentPath?.absolutePath as? NSString)?.deletingLastPathComponent ?? ""
        if let identity = currentPath?.sshIdentity,
           parentPath != currentPath?.absolutePath && !parentPath.isEmpty {
            Task {
                await navigateToPathWithHistory(SSHFileDescriptor(
                    absolutePath: parentPath,
                    isDirectory: true,
                    sshIdentity: identity))
            }
        }
    }

    @objc private func refresh() {
        // Refresh current directory
        Task {
            if let currentPath {
                await navigateToPath(currentPath)
            }
        }
    }

    // MARK: - Go to Folder Dialog

    private class Cache {
        private var dict = [String: Result<[RemoteFile], Error>]()
        var sort = FileSorting.byName

        func listFiles(path: String, endpoint: SSHEndpoint) async throws -> [RemoteFile] {
            if let cachedResult = dict[path] {
                switch cachedResult {
                    case .success(let files):
                    return files
                case .failure(let error):
                    throw error
                }
            }
            do {
                let result = try await endpoint.listFiles(path, sort: sort)
                dict[path] = .success(result)
                return result
            } catch {
                dict[path] = .failure(error)
                throw error
            }
        }
    }

    private func showGoToFolderDialog() {
        let cache = Cache()
        let identity = currentEndpoint?.sshIdentity ?? SSHIdentity.localhost
        let dialog = SSHFolderDialog(currentPath: currentPath?.absolutePath,
                                     hostname: identity.host,
                                     completionsProvider: { [weak self] basePath in
            return await self?.completions(basePath: basePath,
                                           sshIdentity: identity,
                                           cache: cache) ?? []
        },
                                     onNavigate: { [weak self] enteredPath in
            guard let self else {
                return
            }

            let expandedPath = self.expandPath(enteredPath)
            Task {
                await self.navigateToPathWithHistory(
                    SSHFileDescriptor(
                        absolutePath: expandedPath,
                        isDirectory: true,
                        sshIdentity: identity
                    )
                )
            }
        })

        dialog.runModal()
    }

    private func completions(basePath rawBasePath: String,
                             sshIdentity: SSHIdentity,
                             cache: SSHFilePanel.Cache) async -> [String]{
        guard let endpoint = endpoint(for: sshIdentity) else {
            return []
        }
        do {
            let basePath = expandPath(rawBasePath).lowercased()
            var listPath: any StringProtocol
            let requiredPrefix: String
            let siblings: [String]
            print("Complete \(basePath)")
            if basePath != "/", let stat = try? await endpoint.stat(basePath), stat.kind.isFolder {
                // Base path exists and is a folder. Suggest its children.
                listPath = basePath.removing(suffix: "/")
                requiredPrefix = basePath.removing(suffix: "/") + "/"

                let maybeSiblings = try? await cache.listFiles(path: basePath.deletingLastPathComponent, endpoint: endpoint)
                siblings = (maybeSiblings ?? []).filter { candidate in
                    return candidate.kind.isFolder && candidate.absolutePath.hasPrefix(basePath)
                }.map {
                    $0.absolutePath.lowercased()
                }
                print("Base path is a folder.")
            } else {
                // Base path does not exist or is not a folder. Suggest only children of the enclosing folder.
                siblings = []
                listPath = basePath.deletingLastPathComponent.removing(suffix: "/")
                requiredPrefix = basePath
                print("Base path is not a folder.")
            }
            if listPath.isEmpty {
                listPath = "/"
            }
            print("listPath=\(listPath), requiredPrefix=\(requiredPrefix), siblings=\(siblings)")
            let children = try await cache.listFiles(path: String(listPath), endpoint: endpoint).filter { candidate in
                return candidate.kind.isFolder && candidate.absolutePath.lowercased().hasPrefix(requiredPrefix)
            }.map {
                $0.absolutePath.lowercased()
            }
            print("children=\(children)")
            let result = (siblings + children).sorted(by: <)
            return result
        } catch {
            print(error)
            DLog("\(error)")
            return []
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
        if !expandedPath.hasPrefix("/"), let currentPath {
            expandedPath = (currentPath.absolutePath as NSString).appendingPathComponent(expandedPath)
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
        static let currentPathPrefix = "SSHFilePanel.currentPath."  // Append SSHIdentity.stringIdentifier to get a complete key
    }

    // MARK: - Save State
    func saveWindowState() {
        guard let window, initialized else {
            return
        }

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
        defaults.set(currentPath?.absolutePath, forKey: RestorationKeys.currentPathPrefix + (currentPath?.sshIdentity ?? SSHIdentity.localhost).stringIdentifier)
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
            self.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        } else {
            self.splitView.setPosition(sidebarWidth, ofDividerAt: 200)
        }
    }

    private func savedPath(for identity: SSHIdentity) -> String? {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: RestorationKeys.currentPathPrefix + identity.stringIdentifier)
    }
}

// MARK: - Navigation History Support

@available(macOS 11, *)
extension SSHFilePanel {

    @discardableResult
    func navigateToPathWithHistory(_ path: SSHFileDescriptor) async -> Bool {
        print("Navigate to \(path)")
        // Save current path to history before navigating
        if historyIndex < navigationHistory.count - 1 {
            // Remove forward history if we're navigating to a new path
            navigationHistory.removeSubrange((historyIndex + 1)...)
        }

        navigationHistory.append(path)
        historyIndex = navigationHistory.count - 1

        print("History is now:\n\(navigationHistory)")
        print("Index is \(historyIndex)")

        // Navigate to new path
        let succeeded = await navigateToPath(path)

        // Update button states
        updateNavigationButtons()

        return succeeded
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = canGoBack()
        forwardButton.isEnabled = canGoForward()
    }

    private func backPath() -> SSHFileDescriptor? {
        while historyIndex > 0 {
            historyIndex -= 1
            let candidate = navigationHistory[historyIndex]
            if self.endpoint(for: candidate.sshIdentity) != nil {
                return candidate
            }
        }
        return nil
    }

    private func canGoBack() -> Bool {
        let saved = historyIndex
        defer {
            historyIndex = saved
        }
        return backPath() != nil
    }

    private func canGoForward() -> Bool {
        let saved = historyIndex
        defer {
            historyIndex = saved
        }
        let path = forwardPath()
        return path != nil
    }

    @objc private func backButtonClicked(_ sender: NSButton) {
        // Skip past dead endpoints
        guard let previousPath = backPath() else {
            return
        }
        print("Back button clicked")
        print("History is now:\n\(navigationHistory)")
        print("Index is \(historyIndex)")

        Task {
            await navigateToPath(previousPath)
            updateNavigationButtons()
        }
    }

    private func forwardPath() -> SSHFileDescriptor? {
        while historyIndex < navigationHistory.count - 1 {
            historyIndex += 1
            let candidate = navigationHistory[historyIndex]
            if self.endpoint(for: candidate.sshIdentity) != nil {
                return candidate
            }
        }
        return nil
    }

    @objc private func forwardButtonClicked(_ sender: NSButton) {
        // Skip past dead endpoints
        guard let nextPath = forwardPath() else {
            return
        }
        print("Forward button clicked")
        print("History is now:\n\(navigationHistory)")
        print("Index is \(historyIndex)")

        Task {
            await navigateToPath(nextPath)
            updateNavigationButtons()
        }
    }
}

@available(macOS 11, *)
extension SSHFilePanel {
    private func createFolderForTemporaryFile(name: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory

        // Create the temporary file/directory
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            DLog("Created temp file: \(tempDir.path)")
            let tempFileURL = tempDir.appendingPathComponent(name)
            return tempFileURL
        } catch {
            DLog("\(error)")
            return nil
        }
    }

    public struct iTermFilePanelError: LocalizedError, CustomStringConvertible, CustomNSError, Codable {
        public internal(set) var message: String

        public init(_ message: String) {
            self.message = message
        }

        public var errorDescription: String? {
            message
        }

        public var description: String {
            message
        }

        var localizedDescription: String {
            message
        }

        public static var errorDomain: String { "com.iterm2.file-panel" }
        public var errorCode: Int { 1 }
    }

    struct Item {
        var promise: iTermRenegablePromise<NSURL>
        var filename: String
        var isDirectory: Bool
        var host: SSHIdentity
        var progress: Progress
        var cancellation: Cancellation
    }

    func promiseItems() -> [Item] {
        return selectedFiles.map { file in
            let cancellation = Cancellation()
            let progress = Progress()
            let promise = iTermRenegablePromise<NSURL> { seal in
                if file.sshIdentity == SSHIdentity.localhost {
                    seal.fulfill(URL(fileURLWithPath: file.absolutePath) as NSURL)
                } else if let endpoint = self.endpoint(for: file.sshIdentity),
                          let tempFile = createFolderForTemporaryFile(name: file.absolutePath.lastPathComponent) {
                    Task { @MainActor in
                        do {
                            let remoteFile = try await endpoint.stat(file.absolutePath)
                            _ = try await endpoint.downloadChunked(
                                remoteFile: remoteFile,
                                progress: progress,
                                cancellation: cancellation,
                                destination: tempFile)
                            seal.fulfill(tempFile as NSURL)
                        } catch {
                            seal.reject(error)
                        }
                    }
                } else {
                    seal.reject(iTermFilePanelError("The connection to \(file.sshIdentity.displayName) was lost."))
                }
            } renege: {
                cancellation.cancel()
            }
            return Item(promise: promise,
                        filename: file.absolutePath,
                        isDirectory: file.isDirectory,
                        host: file.sshIdentity,
                        progress: progress,
                        cancellation: cancellation)
        }
    }

    func fetchSelectedFiles(_ completion: @escaping ([URL]) -> ()) {
        Task { @MainActor in
            var result = [URL]()
            for file in selectedFiles {
                if file.sshIdentity == SSHIdentity.localhost {
                    result.append(URL(fileURLWithPath: file.absolutePath))
                } else if let endpoint = self.endpoint(for: file.sshIdentity),
                          let tempFile = createFolderForTemporaryFile(name: file.absolutePath.lastPathComponent) {
                    do {
                        let data = try await endpoint.download(file.absolutePath, chunk: nil, uniqueID: nil)
                        try data.write(to: tempFile)
                        result.append(tempFile)
                    } catch {
                        DLog("\(error)")
                    }
                }
            }
            completion(result)
        }
    }
}

@available(macOS 11, *)
extension SSHFilePanel: SSHFilePanelFileListDelegate {
    func sshFilePanelSelectionDidChange() {
        if fileList.selectedFiles.isEmpty {
            openButton.isEnabled = false
        } else if fileList.selectedFiles.count == 1 {
            openButton.isEnabled = true
        } else {
            openButton.isEnabled = fileList.selectedFiles.allSatisfy { node in
                !node.isDirectory
            }
        }
    }

    func sshFilePanelList(didSelect file: SSHFilePanelFileList.FileNode) {
        if file.isDirectory {
            Task { @MainActor in
                await navigateToPathWithHistory(SSHFileDescriptor(
                    absolutePath: file.file.absolutePath,
                    isDirectory: true,
                    sshIdentity: file.sshIdentity))
            }
        } else if canChooseFiles {
            openButtonClicked(openButton)
        }
    }
    func sshFilePanelList(write node: SSHFilePanelFileList.FileNode,
                          endpoint: SSHEndpoint,
                          to url: URL,
                          completionHandler: @escaping ((any Error)?) -> Void) {
        // Download the file from the remote server
        Task { @MainActor in
            do {
                let fullPath = node.file.absolutePath
                if node.file.kind == .folder {
                    print("Creating directory: \(url)")
                    // For directories, create the directory structure
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                    // Optionally, recursively download directory contents
                    await downloadDirectoryContents(from: fullPath, to: url, using: endpoint)
                    print("Directory download completed")
                    completionHandler(nil)
                } else {
                    print("Downloading file: \(fullPath)")
                    // For files, download the file content (download entire file by passing nil chunk)
                    let data = try await endpoint.download(fullPath, chunk: nil, uniqueID: nil)
                    try data.write(to: url)
                    print("File download completed: \(data.count) bytes")
                    completionHandler(nil)
                }
            } catch {
                print("Download error: \(error)")
                completionHandler(error)
            }
        }
    }

    private func downloadDirectoryContents(from remotePath: String, to localURL: URL, using endpoint: SSHEndpoint) async {
        do {
            let files = try await endpoint.listFiles(remotePath, sort: .byName)
            for file in files {
                let remoteFilePath = (remotePath as NSString).appendingPathComponent(file.name)
                let localFileURL = localURL.appendingPathComponent(file.name)

                if file.kind == .folder {
                    try FileManager.default.createDirectory(at: localFileURL, withIntermediateDirectories: true, attributes: nil)
                    await downloadDirectoryContents(from: remoteFilePath, to: localFileURL, using: endpoint)
                } else {
                    if let data = try? await endpoint.download(remoteFilePath, chunk: nil, uniqueID: nil) {
                        try? data.write(to: localFileURL)
                    }
                }
            }
        } catch {
            print("Error downloading directory contents: \(error)")
        }
    }

}

@available(macOS 11, *)
extension SSHFilePanel: SSHFilePanelSidebarDelegate {
    func sidebarDidSelectHost(_ sidebar: SSHFilePanelSidebar, host sshIdentity: SSHIdentity) {
        if ignoreSidebarChange > 0 {
            return
        }
        let options = defaultPathOptions(for: sshIdentity)
        Task { @MainActor in
            for option in options {
                let descriptor = SSHFileDescriptor(
                    absolutePath: option,
                    isDirectory: true,
                    sshIdentity: sshIdentity)
                if await navigateToPathWithHistory(descriptor) {
                    return
                }
            }
        }
    }

    func sidebarDidSelectFavorite(_ sidebar: SSHFilePanelSidebar, host: SSHIdentity, path: String) {
        if ignoreSidebarChange > 0 {
            return
        }
        if endpoint(for: host) != nil {
            let descriptor = SSHFileDescriptor(
                absolutePath: path,
                isDirectory: true,
                sshIdentity: host)
            Task { @MainActor in
                await navigateToPathWithHistory(descriptor)
            }
        }
    }

    func shortPath(sshIdentity: SSHIdentity, absolutePath: String) -> String? {
        guard let home = endpoint(for: sshIdentity)?.homeDirectory else {
            return nil
        }
        guard absolutePath.hasPrefix(home + "/") else {
            return nil
        }
        return "~" + absolutePath.removingPrefix(home)
    }

    func sidebarHostIsValid(_ sidebar: SSHFilePanelSidebar, host: SSHIdentity) -> Bool {
        return endpoint(for: host) != nil
    }
}

