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

@available(macOS 11, *)
class SSHFilePanel: NSWindowController {
    // MARK: - UI Components
    private var splitView: NSSplitView!
    private var mainContentView: NSView!
    private var toolbarView: NSView!
    private var backButton: NSButton!
    private var forwardButton: NSButton!
    private var arrangeButton: NSPopUpButton!
    private var locationButton: SSHFilePanelLocationButton!
    private var searchField: NSSearchField!
    private var fileList: SSHFilePanelFileList!
    private var buttonStackView: NSStackView!
    private var cancelButton: NSButton!
    private var openButton: NSButton!
    private let sidebar = SSHFilePanelSidebar()

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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered,
                             defer: false)
        super.init(window: window)

        // Disable restoration completely for this window
        window.restorationClass = nil
        window.identifier = nil

        setupUI()
        setupWindow()
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
            updateLocationButton()
        }

        sidebar.connectedHosts = connectedHosts
    }

    @MainActor
    private func updateLocationButton() {
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
            updateLocationButton()
            // TODO: Update table view in step 2
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
        setupConstraints()

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

        // Additional restoration prevention
        window?.restorationClass = nil
        window?.identifier = nil

        // Set minimum window size - will be updated dynamically
        updateMinimumWindowSize()
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
        
        // Setup file table
        setupFileTable()
        
        // Setup buttons
        setupButtons()
        
        // Create main vertical stack
        let mainStackView = NSStackView(views: [toolbarView, separatorLine, fileList, buttonStackView])
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
    }

    private func setupButtons() {
        cancelButton = NSButton()
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)

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

    private func setupConstraints() {
        // Split view position will be set in windowDidLoad
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(251), forSubviewAt: 0)
    }

    // MARK: - Actions
    @objc private func backButtonClicked(_ sender: NSButton) {
        // TODO: Implement navigation back
        print("Back button clicked")
    }

    @objc private func forwardButtonClicked(_ sender: NSButton) {
        // TODO: Implement navigation forward
        print("Forward button clicked")
    }

    @objc private func viewModeChanged(_ sender: NSPopUpButton) {
        // View mode button removed for now
        print("View mode changed to: \(sender.selectedItem?.title ?? "")")
    }

    @objc private func locationButtonChanged(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let path = selectedItem.representedObject as? String else { return }

        Task {
            await navigateToPath(path)
        }
        locationButton.set(path: path, sshIdentity: locationButton.sshIdentity!)
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        // TODO: Implement search functionality
        print("Search changed to: \(sender.stringValue)")
    }

    @objc private func cancelButtonClicked(_ sender: NSButton) {
        if let sheetParent = window?.sheetParent {
            sheetParent.endSheet(window!, returnCode: .cancel)
        } else {
            NSApp.stopModal(withCode: .cancel)
        }
    }

    @objc private func openButtonClicked(_ sender: NSButton) {
        if let sheetParent = window?.sheetParent {
            sheetParent.endSheet(window!, returnCode: .OK)
        } else {
            NSApp.stopModal(withCode: .OK)
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
    func windowWillClose(_ notification: Notification) {
        if window?.sheetParent == nil {
            NSApp.stopModal()
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
