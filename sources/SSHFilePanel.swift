//
//  SSHFilePanel.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

import Foundation
import Cocoa
import UniformTypeIdentifiers

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

@MainActor
protocol SSHFilePanelDelegate: AnyObject {
    // For save panels: This method is not sent. All urls are always disabled.
    // For open panels: Return `YES` to allow the `item` to be enabled in the panel.
    //   Delegate implementations should be fast to avoid stalling the UI.
    func panel(_ sender: SSHFilePanel, shouldEnable item: SSHFileDescriptor) -> Bool

    func panel(_ sender: SSHFilePanel, didChangeToDirectory: SSHFileDescriptor?)
    func panel(_ sender: SSHFilePanel, userEnteredFilename: String, confirmed: Bool) -> String?

    // Save panel: Sent once by the save panel when the user clicks the Save button. The user is
    // intending to save a file at `item`. Return `YES` if the `url` is a valid location to save to.
    // Throw an error if the item is not valid. It can include recovery options. If a recovery
    // option is selected by the user,  the panel will attempt to close again.
    //  Note: An item at `item` may not physically exist yet, unless the user decided to overwrite
    // an existing item.
    // Open panel: Sent once for each selected item when the user chooses the Open button. Return
    // Throw an error with a user-displayable message for why the `url` is not valid for opening.
    // If a recovery option is provided by the error, and recovery succeeded, the panel will attempt
    // to close again.
    // Note: Implement this delegate method instead of  `panel:shouldEnableURL:` if the processing
    // of the selected item takes a long time.
    func panel(_ sender: SSHFilePanel, validate item: SSHFileDescriptor) throws

}

class SSHMainContentView: iTermLayerBackedSolidColorView { }

@available(macOS 11, *)
class SSHFilePanel: NSWindowController {
    static let connectedHostsDidChangeNotification = Notification.Name("SSHFilePanelConnectedHostsDidChange")

    private var splitViewController: NSSplitViewController!
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
    private var newFolderButton: NSButton!
    private var systemPanelButton: NSButton!
    private var sidebar: SSHFilePanelSidebar!
    var completionHandler: ((NSApplication.ModalResponse) -> Void)?
    private var navigationHistory: [SSHFileDescriptor] = []
    private var historyIndex: Int = -1
    private var ignoreSidebarChange = 0
    private(set) var selectedFiles: [SSHFileDescriptor] = []
    private var lastPath = [SSHIdentity: String]()
    private var initialized = false
    var isSavePanel = false
    var defaultFilename: String?
    var allowsOtherFileTypes = false
    var systemPanelCallback: (() -> Void)?
    var showsHiddenFiles = false
    var saveAsTextField: NSTextField!
    private var saveAsLabel: NSTextField!
    private var newFolderNameTextField: NSTextField!
    private var newFolderSheet: NSPanel!
    private var uiInitialized = false

    private enum Mode {
        case regular
        case search(Int, Cancellation)
    }
    private var mode = Mode.regular {
        didSet {
            switch (oldValue, mode) {
            case (.regular, .regular): return
            case (.search, .search): return
            case (.regular, .search): didEnterSearchMode()
            case (.search(_, let cancellation), .regular): didExitSearchMode(cancellation)
            }
        }
    }
    private var nextSearchGeneration = 0
    var canChooseDirectories = false
    var canChooseFiles = true
    var canCreateDirectories = false
    var isSelectable: ((RemoteFile) -> Bool)?
    var includeLocalhost = true
    var allowedContentTypes = [UTType]()
    var preferredSSHIdentity: SSHIdentity?
    var initialDirectory: URL?  // Only used if preferredSSHIdentity is nonnil and is available
    var accessoryView: NSView?
    weak var delegate: SSHFilePanelDelegate?

    var allowsMultipleSelection = true {
        didSet {
            if uiInitialized {
                fileList.allowsMultipleSelection = allowsMultipleSelection
            }
        }
    }

    // MARK: - Data Properties

    private var prepared = false
    weak var dataSource: SSHFilePanelDataSource? {
        didSet {
            if dataSource != nil {
                dataSourceDidChange()
            }
        }
    }

    var currentEndpoint: SSHEndpoint?
    var currentPath: SSHFileDescriptor? {
        didSet {
            updateSavePanelEnabled()
        }
    }

    // MARK: - Constants
    private let minimumWindowWidth: CGFloat = 550
    private let minimumSidebarWidth: CGFloat = 180
    private let maximumSidebarWidth: CGFloat = 300

    // MARK: - Initialization
    init() {
        let window = SSHFilePanelWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                                        styleMask: [.titled, .resizable, .fullSizeContentView],
                                        backing: .buffered,
                                        defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Hide traffic light buttons
        if #available(macOS 26, *) {
            window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
        }
        
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.worksWhenModal = true
        window.becomesKeyOnlyIfNeeded = false
        super.init(window: window)

        window.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

extension SSHFilePanel {
    private func prepareToShow() {
        setupUI()
        setupWindow()

        if isSavePanel {
            self.window?.makeFirstResponder(saveAsTextField)
        } else {
            self.window?.makeFirstResponder(fileList.documentView)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(connectedHostsDidChange(_:)),
                                               name: SSHFilePanel.connectedHostsDidChangeNotification,
                                               object: nil)
        uiInitialized = true
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
        return (dataSource?.remoteFilePanelConnectedHosts() ?? []) + (includeLocalhost ? [SSHIdentity.localhost] : [])
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
        DLog("dataSourceDidChange called, preferredSSHIdentity: \(String(describing: preferredSSHIdentity)), initialDirectory: \(String(describing: initialDirectory))")
        if !prepared {
            prepared = true
            prepareToShow()
        }
        let connectedHosts = connectedHostsIncludingLocalhost()
        let defaultHost = preferredSSHIdentity ?? connectedHosts.first
        if let defaultHost {
            DLog("Will select endpoint for host: \(defaultHost), initialPath: \(String(describing: initialDirectory?.path))")
            Task { @MainActor in
                await selectEndpoint(forIdentity: defaultHost,
                                     initialPath: initialDirectory?.path,
                                     withHistory: true)
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
        // If we have an explicit initialDirectory and it's for localhost, use it
        if sshIdentity == .localhost, let initialDir = initialDirectory {
            DLog("Using initialDirectory: \(initialDir.path)")
            return initialDir.path
        }
        let result = defaultPathOptions(for: sshIdentity).first!
        DLog("Using defaultPath: \(result) for \(sshIdentity)")
        return result
    }

    @discardableResult
    private func selectEndpoint(forIdentity sshIdentity: SSHIdentity,
                                initialPath: String?,
                                withHistory: Bool) async -> Bool {
        DLog("selectEndpoint called with sshIdentity: \(sshIdentity), initialPath: \(String(describing: initialPath)), withHistory: \(withHistory)")
        currentEndpoint = endpoint(for: sshIdentity)
        defer {
            delegate?.panel(self, didChangeToDirectory: currentPath)
        }
        if currentEndpoint != nil {
            // Prevent sidebar selection from triggering navigation
            ignoreSidebarChange += 1
            sidebar.selectedIdentity = sshIdentity
            ignoreSidebarChange -= 1
            // Use initialPath if provided, otherwise defaultPath
            let pathToUse = initialPath ?? defaultPath(for: sshIdentity)
            currentPath = SSHFileDescriptor(absolutePath: pathToUse,
                                            isDirectory: true,
                                            sshIdentity: sshIdentity)
            defer {
                updateViewsForCurrentPath()
            }
            if withHistory {
                return await navigateToPathWithHistory(SSHFileDescriptor(
                    absolutePath: pathToUse,
                    isDirectory: true,
                    sshIdentity: sshIdentity))
            }
            return await navigateToPath(SSHFileDescriptor(
                absolutePath: pathToUse,
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
        mode = .regular
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
            DLog("Failed to navigate to path \(path): \(error)")
        }
        return false
    }

    // MARK: - UI Setup
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }

        setupSplitViewController(in: contentView)
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
            if self?.isSavePanel == true {
                self?.window?.makeFirstResponder(self?.saveAsTextField)
            } else {
                self?.fileList.takeFirstResponder()
            }
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

    private func setupSplitViewController(in contentView: NSView) {
        // Create NSSplitViewController for all versions
        splitViewController = NSSplitViewController()
        splitViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure the split view
        splitView = splitViewController.splitView
        splitView.isVertical = true
        // Note: Cannot set delegate when using NSSplitViewController - it manages the split view
        // Min/max constraints are handled via NSSplitViewItem properties instead
        splitView.dividerStyle = .thin
        
        // Add split view controller to the window's content view
        contentView.addSubview(splitViewController.view)
        
        NSLayoutConstraint.activate([
            splitViewController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitViewController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitViewController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitViewController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func setupSidebar() {
        sidebar = SSHFilePanelSidebar(includeLocalhost: includeLocalhost)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.delegate = self
        
        // Create view controller for sidebar
        let sidebarViewController = NSViewController()
        sidebarViewController.view = sidebar
        
        // Create split view item with sidebar behavior
        // In macOS 26, this will automatically get the floating glass effect
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = minimumSidebarWidth
        sidebarItem.maximumThickness = maximumSidebarWidth
        sidebarItem.preferredThicknessFraction = 0.25
        sidebarItem.canCollapse = false  // Match the delegate behavior
        
        // Disable automatic safe area adjustment for sidebar so it extends to top
#if(MAC_OS_VERSION_26_0)
        if #available(macOS 26, *) {
            sidebarItem.automaticallyAdjustsSafeAreaInsets = false
        }
#endif
        splitViewController.addSplitViewItem(sidebarItem)
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

        // Create save panel UI if needed
        var saveAsContainer: NSView?
        if isSavePanel {
            saveAsContainer = setupSaveAsContainer()
        }

        // Create main vertical stack
        var views = [NSView]()
        views.append(spacer)
        if let saveAsContainer = saveAsContainer {
            views.append(saveAsContainer)
        }
        views.append(contentsOf: [toolbarView, separatorLine, fileList, separatorLine2] + makeAccessoryViews() + [spacer2, buttonStackView, spacer3])

        // A real NSStackView would randomly change its layout. I don't know why because auto layout is impossible to analyze, but this works so far.
        class SSHMainStackView: NSView { }
        let mainStackView = SSHMainStackView()
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        var previous: NSView?
        for view in views {
            defer {
                previous = view
            }
            mainStackView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
                view.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? mainStackView.topAnchor)
            ])
        }
        if let previous {
            NSLayoutConstraint.activate([
                previous.bottomAnchor.constraint(equalTo: mainStackView.bottomAnchor)
            ])
        }

        mainContentView.addSubview(mainStackView)

        // Create view controller for main content
        let mainViewController = NSViewController()
        mainViewController.view = mainContentView
        
        // Create content split view item
        let contentItem = NSSplitViewItem(viewController: mainViewController)
        contentItem.minimumThickness = 366  // Minimum main content width from toolbar constraints
        contentItem.canCollapse = false
        
        // Enable automatic safe area inset adjustment for macOS 26's floating sidebar
        // This property is new in macOS 26 and enables edge-to-edge content with the floating glass sidebar
        #if(MAC_OS_VERSION_26_0)
        if #available(macOS 26, *) {
            contentItem.automaticallyAdjustsSafeAreaInsets = true
        }
        #endif

        splitViewController.addSplitViewItem(contentItem)
        
        // For macOS 26, use safe area for horizontal anchors to respect the floating sidebar
        // Always use direct top anchor to extend content under the titlebar
        let leadingAnchor: NSLayoutXAxisAnchor
        let trailingAnchor: NSLayoutXAxisAnchor
        
        if #available(macOS 26, *) {
            // Use safe area for floating sidebar in macOS 26
            leadingAnchor = mainContentView.safeAreaLayoutGuide.leadingAnchor
            trailingAnchor = mainContentView.safeAreaLayoutGuide.trailingAnchor
        } else {
            // Use direct edges
            leadingAnchor = mainContentView.leadingAnchor
            trailingAnchor = mainContentView.trailingAnchor
        }
        
        NSLayoutConstraint.activate([
            spacer.heightAnchor.constraint(equalToConstant: 9),

            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
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

        // Additional constraints for save panel UI
        if let saveAsContainer = saveAsContainer {
            NSLayoutConstraint.activate([
                saveAsContainer.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
                saveAsContainer.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
                saveAsContainer.heightAnchor.constraint(equalToConstant: 44)
            ])
        }
    }

    private func setupSaveAsContainer() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Create "Save As:" label
        saveAsLabel = NSTextField(labelWithString: "Save As:")
        saveAsLabel.translatesAutoresizingMaskIntoConstraints = false
        saveAsLabel.alignment = .right
        saveAsLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        saveAsLabel.textColor = NSColor.secondaryLabelColor
        
        // Create editable text field
        saveAsTextField = NSTextField()
        saveAsTextField.translatesAutoresizingMaskIntoConstraints = false
        saveAsTextField.isEditable = true
        saveAsTextField.isBezeled = true
        saveAsTextField.bezelStyle = .roundedBezel
        saveAsTextField.focusRingType = .default
        saveAsTextField.placeholderString = "Enter filename"
        saveAsTextField.delegate = self

        // Pre-fill with default filename if provided
        if let defaultFilename = defaultFilename {
            saveAsTextField.stringValue = defaultFilename
        }
        
        container.addSubview(saveAsLabel)
        container.addSubview(saveAsTextField)
        
        NSLayoutConstraint.activate([
            // Center the text field horizontally
            saveAsTextField.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            saveAsTextField.widthAnchor.constraint(equalToConstant: 233),
            saveAsTextField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            // Place label to the left of text field
            saveAsLabel.trailingAnchor.constraint(equalTo: saveAsTextField.leadingAnchor, constant: -8),
            saveAsLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        return container
    }

    private func setupToolbar() {
        // Create toolbar container view
        toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false

        // Create buttons
        backButton = NSButton()
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.bezelStyle = .texturedRounded
        backButton.image = NSImage.it_image(forSymbolName: SFSymbol.chevronLeft.rawValue,
                                            accessibilityDescription: "Back",
                                            fallbackImageName: "chevron.left",
                                            for: SSHFilePanel.self)
        backButton.isEnabled = false
        backButton.target = self
        backButton.action = #selector(backButtonClicked)

        forwardButton = NSButton()
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.bezelStyle = .texturedRounded
        forwardButton.image = NSImage.it_image(forSymbolName: SFSymbol.chevronRight.rawValue,
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
        fileList.allowsMultipleSelection = allowsMultipleSelection

        // Ensure fileList doesn't collapse when accessory views are present
        fileList.setContentHuggingPriority(.defaultLow, for: .vertical)
        fileList.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        fileList.delegate = self
    }

    private func makeAccessoryViews() -> [NSView] {
        guard let accessoryView else {
            return []
        }

        let separatorLine = iTermLayerBackedSolidColorView()
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.wantsLayer = true
        separatorLine.color = NSColor.separatorColor

        return [accessoryView, separatorLine]
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
        openButton.title = isSavePanel ? "Save" : "Open"
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r" // Return
        openButton.isEnabled = false
        openButton.target = self
        openButton.action = #selector(openButtonClicked)

        // Create New Folder button (only if canCreateDirectories is true)
        if canCreateDirectories {
            newFolderButton = NSButton()
            newFolderButton.translatesAutoresizingMaskIntoConstraints = false
            newFolderButton.title = "New Folder"
            newFolderButton.bezelStyle = .rounded
            newFolderButton.target = self
            newFolderButton.action = #selector(newFolderButtonClicked)
        }

        // Create Use System Panel button
        systemPanelButton = NSButton()
        systemPanelButton.translatesAutoresizingMaskIntoConstraints = false
        systemPanelButton.title = "Use System Panel…"
        systemPanelButton.bezelStyle = .rounded
        systemPanelButton.target = self
        systemPanelButton.action = #selector(systemPanelButtonClicked)

        // Create button stack with right alignment and proper spacing
        let spacerView = NSView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false

        let rightSpacer = NSView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false

        var buttonViews: [NSView] = []
        if canCreateDirectories {
            // Add a left spacer for the New Folder button
            let leftSpacer = NSView()
            leftSpacer.translatesAutoresizingMaskIntoConstraints = false
            buttonViews.append(leftSpacer)
            buttonViews.append(newFolderButton)
        }
        
        let systemPanelSpacer = NSView()
        systemPanelSpacer.translatesAutoresizingMaskIntoConstraints = false
        buttonViews.append(systemPanelSpacer)
        buttonViews.append(systemPanelButton)
        buttonViews.append(contentsOf: [spacerView, cancelButton, openButton, rightSpacer])
        
        buttonStackView = NSStackView(views: buttonViews)
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.distribution = .fill
        buttonStackView.spacing = 12

        var constraints: [NSLayoutConstraint] = [
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            openButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            systemPanelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            rightSpacer.widthAnchor.constraint(equalToConstant: 8)
        ]
        
        let systemPanelSpacerIndex = canCreateDirectories ? 2 : 0
        constraints.append(buttonViews[systemPanelSpacerIndex].widthAnchor.constraint(equalToConstant: 11))
        
        if canCreateDirectories {
            constraints.append(contentsOf: [
                newFolderButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
                // Set left spacer width to 8 points (20 - 12 spacing = 8) for exact 20pt margin
                buttonViews[0].widthAnchor.constraint(equalToConstant: 8)
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Actions

    @objc private func newFolderButtonClicked(_ sender: NSButton) {
        showNewFolderSheet()
    }

    @objc private func systemPanelButtonClicked(_ sender: NSButton) {
        if let callback = systemPanelCallback {
            // The callback will handle closing the SSH panel
            willClose()
            callback()
        } else {
            // Fallback: Close SSH panel and open system panel directly
            willClose()
            if let sheetParent = window?.sheetParent {
                // Sheet presentation
                sheetParent.endSheet(window!, returnCode: .cancel)
            } else if NSApp.modalWindow == window {
                // Modal presentation
                NSApp.stopModal(withCode: .cancel)
                window?.orderOut(nil)
            } else {
                // Non-modal presentation
                window?.orderOut(nil)
            }
            // Fallback: Open system panel directly (without SSH button)
            let savePanel = isSavePanel ? NSSavePanel() : NSOpenPanel()
            
            // Copy settings from SSH panel
            if let openPanel = savePanel as? NSOpenPanel {
                openPanel.canChooseDirectories = canChooseDirectories
                openPanel.canChooseFiles = canChooseFiles
                openPanel.allowsMultipleSelection = allowsMultipleSelection
            }
            
            // Copy all the properties
            savePanel.canCreateDirectories = canCreateDirectories
            savePanel.allowsOtherFileTypes = allowsOtherFileTypes
            savePanel.showsHiddenFiles = showsHiddenFiles
            savePanel.allowedContentTypes = allowedContentTypes
            savePanel.accessoryView = accessoryView
            savePanel.isExtensionHidden = false
            savePanel.canSelectHiddenExtension = true
            
            // Set nameFieldStringValue for save panels
            if isSavePanel {
                savePanel.nameFieldStringValue = saveAsTextField?.stringValue ?? defaultFilename ?? ""
            }
            
            // Set directory URL to current directory if on localhost
            if let currentIdentity = currentEndpoint?.sshIdentity,
               currentIdentity.isLocalhost,
               let currentPath = currentPath {
                savePanel.directoryURL = URL(fileURLWithPath: currentPath.absolutePath)
            }
            
            // Present the system panel
            if let sheetParent = window?.sheetParent {
                savePanel.beginSheetModal(for: sheetParent) { [weak self] response in
                    self?.completionHandler?(response)
                }
            } else {
                savePanel.begin { [weak self] response in
                    self?.completionHandler?(response)
                }
            }
        }
    }

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

    private func didEnterSearchMode() {
        fileList.clear()
    }
    
    private func didExitSearchMode(_ cancellation: Cancellation) {
        cancellation.cancel()
        searchField.stringValue = ""
        fileList.clear()
        fileList.loadRootFiles()
        updateViewsForCurrentPath()
    }
    
    private func cancelCurrentSearch() {
        if case .search(_, let cancellation) = mode {
            cancellation.cancel()
        }
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        DLog("Search changed to: \(sender.stringValue)")
        cancelCurrentSearch()
        if sender.stringValue.isEmpty {
            mode = .regular
            return
        }
        let generation = nextSearchGeneration
        nextSearchGeneration += 1
        let cancellation = Cancellation()
        DLog("Begin search generation \(generation) for \(sender.stringValue)")
        mode = .search(generation, cancellation)
        fileList.clear()
        if let currentPath, let currentEndpoint {
            let baseDir = currentPath.absolutePath
            let sshIdentity = currentEndpoint.sshIdentity
            Task { @MainActor [weak self] in
                do {
                    let stream =  try await currentEndpoint.search(baseDir,
                                                                   query: sender.stringValue,
                                                                   cancellation: cancellation)
                    for try await remoteFile in stream {
                        self?.addSearchResult(sshIdentity, remoteFile: remoteFile, generation: generation)
                    }
                } catch {
                    DLog("\(error)")
                }
            }
        }
    }

    private func addSearchResult(_ sshIdentity: SSHIdentity, remoteFile: RemoteFile, generation: Int) {
        if generation + 1 != nextSearchGeneration {
            DLog("Discard out-of-date result \(remoteFile) for generation \(generation)")
            return
        }
        DLog("Add item \(remoteFile) for current generation \(generation)")
        fileList.addItem(sshIdentity: sshIdentity, file: remoteFile)
    }

    private func willClose() {
        saveWindowState()
        cancelCurrentSearch()
    }

    @objc private func cancelButtonClicked(_ sender: Any?) {
        willClose()
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

    @objc private func openButtonClicked(_ sender: NSButton?) {
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
        willClose()
        self.selectedFiles = selection.map {
            SSHFileDescriptor(absolutePath: $0.file.absolutePath,
                              isDirectory: $0.isDirectory,
                              sshIdentity: endpoint.sshIdentity)
        }
        if isSavePanel {
            if let delegate {
                let replacement = delegate.panel(self,
                                                 userEnteredFilename: saveAsTextField.stringValue,
                                                 confirmed: true)
                guard let replacement else {
                    cancelButtonClicked(nil)
                    return
                }
                saveAsTextField.stringValue = replacement
            }
            if allowedContentTypes.count == 1 {
                let ext = saveAsTextField.stringValue.pathExtension
                let fileType = UTType(filenameExtension: ext)
                let requiredType = allowedContentTypes[0]
                if !(fileType?.conforms(to: requiredType) ?? false) {
                    saveAsTextField.stringValue = saveAsTextField.stringValue.appendingPathExtension(for: requiredType)
                }
            }
            if let destinationDescriptor, let delegate {
                do {
                    try delegate.panel(self, validate: destinationDescriptor)
                } catch {
                    validationFailed(error as NSError)
                }
            }
            if let currentEndpoint, let destinationDescriptor {
                Task {
                    do {
                        _ = try await currentEndpoint.stat(destinationDescriptor.absolutePath)
                        end(returnCode: await presentFileExistsAlert(for: destinationDescriptor))
                    } catch {
                        end(returnCode: .OK)
                    }
                }
                return
            }
        }
        end(returnCode: .OK)
    }

    private func validationFailed(_ e: NSError) {
        if let description = e.userInfo[NSLocalizedDescriptionKey] as? String,
           let recoverySuggestion = e.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String,
           let recoveryOptions = e.userInfo[NSLocalizedRecoveryOptionsErrorKey] as? [String],
           let attempter = e.userInfo[NSRecoveryAttempterErrorKey] as? NSObject {

            let option = iTermWarning.show(withTitle: recoverySuggestion,
                                           actions: recoveryOptions,
                                           accessory: nil,
                                           identifier: nil,
                                           silenceable: .kiTermWarningTypePersistent,
                                           heading: description,
                                           window: window)
            let i = option.rawValue
            attempter.attemptRecovery(fromError: e,
                                      optionIndex: i,
                                      delegate: self,
                                      didRecoverSelector: #selector(SSHFilePanel.didRecover(recovered:context:)),
                                      contextInfo: nil)
            return
        }
        _ = iTermWarning.show(withTitle: e.localizedDescription,
                              actions: [ "OK" ],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Could not save file",
                              window: window)
        cancelButtonClicked(nil)
    }

    @objc private func didRecover(recovered: Bool, context: UnsafeMutableRawPointer?) {
        if recovered {
            openButtonClicked(openButton)
        } else {
            cancelButtonClicked(cancelButton)
        }
    }

    private func presentFileExistsAlert(for descriptor: SSHFileDescriptor) async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A file with the name “\(descriptor.absolutePath.lastPathComponent)” on \(descriptor.sshIdentity.displayName) already exists in this location. Do you want to replace it?"
        alert.informativeText = "Replacing it will overwrite its current contents."

        let replaceButton = alert.addButton(withTitle: "Replace")
        replaceButton.hasDestructiveAction = true

        alert.addButton(withTitle: "Cancel")

        if let window {
            return await alert.beginSheetModal(for: window)
        } else {
            return alert.runModal()
        }
    }

    private func end(returnCode: NSApplication.ModalResponse) {
        // Sheet presentation
        if let sheetParent = window?.sheetParent {
            sheetParent.endSheet(window!, returnCode: returnCode)
        }
        // Modal presentation
        else if NSApp.modalWindow == window {
            NSApp.stopModal(withCode: returnCode)
        }
        // Non-modal presentation
        else {
            completionHandler?(returnCode)
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

    func begin(_ completion: @escaping ((NSApplication.ModalResponse) -> Void)) {
        self.completionHandler = completion
        window?.makeKeyAndOrderFront(nil)
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
        let goToFolderItem = NSMenuItem(title: "Go to Folder…",
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

        // Toggle show hidden (Cmd+Shift+.)
        let toggleShowHiddenFilesItem = NSMenuItem(title: "Show Hidden Files",
                                    action: #selector(toggleShowHidenFiles),
                                    keyEquivalent: ".")
        toggleShowHiddenFilesItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(toggleShowHiddenFilesItem)

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
            DLog("Complete \(basePath)")
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
                DLog("Base path is a folder.")
            } else {
                // Base path does not exist or is not a folder. Suggest only children of the enclosing folder.
                siblings = []
                listPath = basePath.deletingLastPathComponent.removing(suffix: "/")
                requiredPrefix = basePath
                DLog("Base path is not a folder.")
            }
            if listPath.isEmpty {
                listPath = "/"
            }
            DLog("listPath=\(listPath), requiredPrefix=\(requiredPrefix), siblings=\(siblings)")
            let children = try await cache.listFiles(path: String(listPath), endpoint: endpoint).filter { candidate in
                return candidate.kind.isFolder && candidate.absolutePath.lowercased().hasPrefix(requiredPrefix)
            }.map {
                $0.absolutePath.lowercased()
            }
            DLog("children=\(children)")
            let result = (siblings + children).sorted(by: <)
            return result
        } catch {
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
    
    // MARK: - New Folder Sheet
    
    @MainActor
    private func showNewFolderSheet() {
        guard let currentPath = currentPath else { return }
        
        newFolderSheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                                 styleMask: [.titled, .closable],
                                 backing: .buffered,
                                 defer: false)
        newFolderSheet.title = ""
        newFolderSheet.isFloatingPanel = false
        
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        newFolderSheet.contentView = contentView
        
        // Create main title
        let mainTitle = NSTextField(labelWithString: "New Folder")
        mainTitle.translatesAutoresizingMaskIntoConstraints = false
        mainTitle.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        mainTitle.textColor = NSColor.labelColor
        mainTitle.alignment = .left
        
        // Create subtitle
        let subtitleLabel = NSTextField(labelWithString: "Name of new folder inside “\(currentPath.absolutePath.lastPathComponent)”:")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        
        // Create text field
        newFolderNameTextField = NSTextField()
        newFolderNameTextField.translatesAutoresizingMaskIntoConstraints = false
        newFolderNameTextField.stringValue = "untitled folder"
        newFolderNameTextField.isEditable = true
        newFolderNameTextField.isBezeled = true
        newFolderNameTextField.bezelStyle = .roundedBezel
        newFolderNameTextField.focusRingType = .default
        
        // Create buttons
        let cancelSheetButton = NSButton()
        cancelSheetButton.translatesAutoresizingMaskIntoConstraints = false
        cancelSheetButton.title = "Cancel"
        cancelSheetButton.bezelStyle = .rounded
        cancelSheetButton.keyEquivalent = "\u{1b}" // Escape
        
        let createButton = NSButton()
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.title = "Create"
        createButton.bezelStyle = .rounded
        createButton.keyEquivalent = "\r" // Return
        
        // Button actions
        cancelSheetButton.target = self
        cancelSheetButton.action = #selector(cancelNewFolderSheet(_:))
        
        createButton.target = self
        createButton.action = #selector(createNewFolder(_:))
        
        // Create button stack
        let buttonStack = NSStackView(views: [cancelSheetButton, createButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        
        // Add views to content view
        contentView.addSubview(mainTitle)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(newFolderNameTextField)
        contentView.addSubview(buttonStack)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            mainTitle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            subtitleLabel.topAnchor.constraint(equalTo: mainTitle.bottomAnchor, constant: 14),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            newFolderNameTextField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            newFolderNameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            newFolderNameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            buttonStack.topAnchor.constraint(equalTo: newFolderNameTextField.bottomAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -17),
            buttonStack.widthAnchor.constraint(equalToConstant: 180),
            
            cancelSheetButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            createButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
        
        // Show sheet
        window?.beginSheet(newFolderSheet) { _ in }
        
        // Make text field first responder and select all text
        DispatchQueue.main.async {
            self.newFolderSheet.makeFirstResponder(self.newFolderNameTextField)
            self.newFolderNameTextField.selectText(nil)
        }
    }
    
    @objc private func cancelNewFolderSheet(_ sender: NSButton) {
        if let sheet = sender.window {
            window?.endSheet(sheet)
        }
    }
    
    @objc private func createNewFolder(_ sender: NSButton) {
        guard let sheet = sender.window,
              let textField = newFolderNameTextField,
              let currentPath = currentPath,
              let endpoint = currentEndpoint else {
            return
        }
        
        let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty else { return }
        
        let newFolderPath = (currentPath.absolutePath as NSString).appendingPathComponent(folderName)
        
        Task { @MainActor in
            do {
                try await endpoint.mkdir(newFolderPath)
                window?.endSheet(sheet)
                // Refresh the current directory to show the new folder
                await navigateToPath(currentPath)
            } catch {
                // Show error alert
                let alert = NSAlert()
                alert.messageText = "Unable to create folder"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.beginSheetModal(for: sheet) { _ in }
            }
        }
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

        let sidebarWidth = defaults.double(forKey: RestorationKeys.sidebarWidth)
        if sidebarWidth > minimumSidebarWidth {
            // Only restore if it's a valid width
            DispatchQueue.main.async { [weak self] in
                self?.splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            }
        } else {
            // Set a reasonable default width
            DispatchQueue.main.async { [weak self] in
                self?.splitView.setPosition(200, ofDividerAt: 0)
            }
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
        DLog("Navigate to \(path)")
        // Save current path to history before navigating
        if historyIndex < navigationHistory.count - 1 {
            // Remove forward history if we're navigating to a new path
            navigationHistory.removeSubrange((historyIndex + 1)...)
        }

        navigationHistory.append(path)
        historyIndex = navigationHistory.count - 1

        DLog("History is now:\n\(navigationHistory)")
        DLog("Index is \(historyIndex)")

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
        DLog("Back button clicked")
        DLog("History is now:\n\(navigationHistory)")
        DLog("Index is \(historyIndex)")

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
        DLog("Forward button clicked")
        DLog("History is now:\n\(navigationHistory)")
        DLog("Index is \(historyIndex)")

        Task {
            await navigateToPath(nextPath)
            updateNavigationButtons()
        }
    }

    @objc private func toggleShowHidenFiles(_ sender: Any?) {
        showsHiddenFiles = !showsHiddenFiles
        updateViewsForCurrentPath()
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

    private func promise(file: SSHFileDescriptor,
                         progress: Progress?,
                         cancellation: Cancellation?) -> iTermRenegablePromise<NSURL> {
        return iTermRenegablePromise<NSURL> { seal in
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
            cancellation?.cancel()
        }
    }

    var destinationDescriptor: SSHFileDescriptor? {
        it_assert(isSavePanel, "Not a save panel")
        guard let currentPath else {
            return nil
        }
        return SSHFileDescriptor(absolutePath: currentPath.absolutePath.appending(pathComponent: saveAsTextField.stringValue),
                                 isDirectory: false,
                                 sshIdentity: currentPath.sshIdentity)
    }

    func promiseItems() -> [Item] {
        return selectedFiles.map { file in
            let cancellation = Cancellation()
            let progress = Progress()
            let promise = self.promise(file: file, progress: progress, cancellation: cancellation)
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
extension SSHFilePanelFileList.FileNode {
    var uttype: UTType? {
        if sshIdentity.isLocalhost {
            let url = URL(fileURLWithPath: file.absolutePath)
            return try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        }
        let ext = file.absolutePath.lastPathComponent.pathExtension
        if ext.isEmpty {
            return nil
        }
        return UTType(filenameExtension: ext)
    }
}

@available(macOS 11, *)
extension SSHFilePanel: SSHFilePanelFileListDelegate {
    func sshFilePanelListShouldShowHiddenFiles() -> Bool {
        return showsHiddenFiles
    }

    func sshFilePanelListURLPromise(for remoteFile: RemoteFile) -> iTermRenegablePromise<NSURL>? {
        guard let currentEndpoint else {
            return nil
        }
        return promise(file: SSHFileDescriptor(absolutePath: remoteFile.absolutePath,
                                               isDirectory: remoteFile.kind.isFolder,
                                               sshIdentity: currentEndpoint.sshIdentity),
                       progress: nil,
                       cancellation: nil)
    }
    
    func sshFilePanelItemIsSelectable(file: SSHFilePanelFileList.FileNode) -> Bool {
        if let isSelectable {
            return isSelectable(file.file)
        }
        if !isSavePanel, let delegate {
            let descriptor = SSHFileDescriptor(absolutePath: file.file.absolutePath,
                                               isDirectory: file.isDirectory,
                                               sshIdentity: file.sshIdentity)
            return delegate.panel(self, shouldEnable: descriptor)
        }
        if !allowedContentTypes.isEmpty {
            if file.isDirectory {
                return true
            }
            guard let type = file.uttype else {
                return false
            }
            return allowedContentTypes.anySatisfies { allowedType in
                return type.conforms(to: allowedType)
            }
        }
        return true
    }

    private func updateSavePanelEnabled() {
        if isSavePanel {
            openButton.isEnabled = currentPath != nil && !saveAsTextField.stringValue.isEmpty
        }
    }

    func sshFilePanelSelectionDidChange() {
        if isSavePanel {
            if let selection = fileList.selectedFiles.first, !selection.isDirectory {
                saveAsTextField.stringValue = selection.file.name
            }
            updateSavePanelEnabled()
        } else {
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
                    DLog("Creating directory: \(url)")
                    // For directories, create the directory structure
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                    // Optionally, recursively download directory contents
                    await downloadDirectoryContents(from: fullPath, to: url, using: endpoint)
                    DLog("Directory download completed")
                    completionHandler(nil)
                } else {
                    DLog("Downloading file: \(fullPath)")
                    // For files, download the file content (download entire file by passing nil chunk)
                    let data = try await endpoint.download(fullPath, chunk: nil, uniqueID: nil)
                    try data.write(to: url)
                    DLog("File download completed: \(data.count) bytes")
                    completionHandler(nil)
                }
            } catch {
                DLog("Download error: \(error)")
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
            DLog("Error downloading directory contents: \(error)")
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

extension SSHFilePanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateSavePanelEnabled()
    }
}
