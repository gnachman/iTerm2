//
//  iTermOpenPanel.swift
//  iTerm2
//
//  Created by George Nachman on 6/8/25.
//

import UniformTypeIdentifiers

@MainActor
private class SSHOpenPanelButton: NSButton {
    weak var openPanel: NSOpenPanel?
    weak var parentWindow: NSWindow?
    var handler: ((NSApplication.ModalResponse, [URL]?) -> Void)?
}

@objc
class iTermOpenPanelItem: NSObject {
    @objc var urlPromise: iTermRenegablePromise<NSURL>
    @objc var filename: String
    @objc var isDirectory: Bool
    @objc var host: SSHIdentity
    @objc var progress: Progress
    @objc var cancellation: Cancellation

    init(urlPromise: iTermRenegablePromise<NSURL>,
         filename: String,
         isDirectory: Bool,
         host: SSHIdentity,
         progress: Progress,
         cancellation: Cancellation) {
        self.urlPromise = urlPromise
        self.filename = filename
        self.isDirectory = isDirectory
        self.host = host
        self.progress = progress
        self.cancellation = cancellation
    }
}

@objc
@MainActor
class iTermOpenPanel: NSObject {
    @objc var canChooseDirectories = true
    @objc var canChooseFiles = true
    @objc var includeLocalhost = true
    @objc var allowsMultipleSelection = true
    @objc var allowedContentTypes = [UTType]()
    @objc var preferredSSHIdentity: SSHIdentity?
    @objc private(set) var items: [iTermOpenPanelItem] = []
    static var panels = [iTermOpenPanel]()
    var isSelectable: ((RemoteFile) -> Bool)?
    private var sshFilePanel: SSHFilePanel?
    private var _directoryURL: URL?
    @objc var directoryURL: URL? {
        get { return _directoryURL }
        set { _directoryURL = newValue }
    }
    @objc var accessoryView: NSView?
    @objc var showsHiddenFiles = false
    private var switchingPanels = false
    private var completionHandler: ((NSApplication.ModalResponse, [URL]?) -> Void)?

    private func loadURLs(_ closure: @escaping ([URL]) -> ()) {
        let group = DispatchGroup()
        var urls = [URL]()
        for item in items {
            group.enter()
            item.urlPromise.then { url in
                urls.append(url as URL)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            closure(urls)
        }
    }

    @objc(beginWithFallback:)
    func beginWithFallback(handler: @escaping (NSApplication.ModalResponse, [URL]?) -> Void) {
        completionHandler = handler
        beginWithFallback(window: nil, handler: handler)
    }

    // Always use system picker with SSH panel option
    @objc(beginWithFallbackWindow:handler:)
    func beginWithFallback(window: NSWindow?,
                           handler: @escaping (NSApplication.ModalResponse, [URL]?) -> Void) {
        completionHandler = handler
        if includeLocalhost || ConductorRegistry.instance.isEmpty {
            runSystem(window: window, handler: handler)
        } else {
            runSSH(window: window, handler: handler)
        }
    }

    private func runSSH(window: NSWindow?,
                        handler: @escaping (NSApplication.ModalResponse, [URL]?) -> Void) {
        let sshFilePanel = makePanel()

        if let window = window {
            sshFilePanel.beginSheetModal(for: window) { [weak self] response in
                if self?.switchingPanels == true {
                    return
                }
                self?.handleCompletion(sshFilePanel: sshFilePanel,
                                       response: response,
                                       handler: { modalResponse in
                    if modalResponse == .OK {
                        self?.loadURLs { urls in
                            handler(modalResponse, urls)
                        }
                    } else {
                        handler(modalResponse, nil)
                    }
                })
            }
        } else {
            sshFilePanel.begin { [weak self] response in
                self?.handleCompletion(sshFilePanel: sshFilePanel,
                                       response: response,
                                       handler: { [weak self] modalResponse in
                    if self?.switchingPanels == true {
                        return
                    }
                    if modalResponse == .OK {
                        self?.loadURLs { urls in
                            handler(modalResponse, urls)
                        }
                    } else {
                        handler(modalResponse, nil)
                    }
                })
            }
        }
    }

    private func makePanel() -> SSHFilePanel {
        let sshFilePanel = SSHFilePanel()
        self.sshFilePanel = sshFilePanel
        Self.panels.append(self)

        sshFilePanel.canChooseDirectories = canChooseDirectories
        sshFilePanel.canChooseFiles = canChooseFiles
        sshFilePanel.isSelectable = isSelectable
        sshFilePanel.includeLocalhost = includeLocalhost
        sshFilePanel.allowedContentTypes = allowedContentTypes
        sshFilePanel.allowsMultipleSelection = allowsMultipleSelection
        sshFilePanel.preferredSSHIdentity = preferredSSHIdentity
        sshFilePanel.initialDirectory = directoryURL
        sshFilePanel.accessoryView = accessoryView
        sshFilePanel.showsHiddenFiles = showsHiddenFiles
        
        // Set the callback to open system panel with SSH button
        sshFilePanel.systemPanelCallback = { [weak self, weak sshFilePanel] in
            guard let self = self, let sshFilePanel = sshFilePanel else { return }
            // Preserve the parent window relationship and completion handler
            let parentWindow = sshFilePanel.window?.sheetParent
            let completionHandler = self.completionHandler
            
            // Preserve the current directory if on localhost
            if let currentPath = sshFilePanel.currentPath,
               let currentIdentity = sshFilePanel.currentEndpoint?.sshIdentity,
               currentIdentity.isLocalhost {
                self._directoryURL = URL(fileURLWithPath: currentPath.absolutePath)
            }
            
            // Close the SSH panel first
            switchingPanels = true
            if let sheetParent = sshFilePanel.window?.sheetParent {
                sheetParent.endSheet(sshFilePanel.window!)
            } else if NSApp.modalWindow == sshFilePanel.window {
                NSApp.stopModal(withCode: .cancel)
                sshFilePanel.window?.orderOut(nil)
            } else {
                sshFilePanel.window?.orderOut(nil)
            }
            switchingPanels = false

            // Now open the system panel
            self.runSystem(window: parentWindow) { response, urls in
                if response == .OK {
                    self.items = (urls ?? []).map { url in
                        let promise = iTermRenegablePromise<NSURL> { seal in
                            seal.fulfill(url as NSURL)
                        }
                        return iTermOpenPanelItem(
                            urlPromise: promise,
                            filename: url.path,
                            isDirectory: url.hasDirectoryPath,
                            host: .localhost,
                            progress: Progress(),
                            cancellation: Cancellation())
                    }
                }
                completionHandler?(response, urls)
            }
        }

        sshFilePanel.dataSource = ConductorRegistry.instance
        return sshFilePanel
    }

    private func handleCompletion(sshFilePanel: SSHFilePanel,
                                  response: NSApplication.ModalResponse,
                                  handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if response == .OK {
            items = sshFilePanel.promiseItems().map { item in
                iTermOpenPanelItem(urlPromise: item.promise,
                                   filename: item.filename,
                                   isDirectory: item.isDirectory,
                                   host: item.host,
                                   progress: item.progress,
                                   cancellation: item.cancellation)
            }
        } else {
            items = []
        }
        handler(response)
        Self.panels.remove(object: self)
    }

    // Show the panel non-modally with a completion handler
    @objc(beginSSHWithWindow:handler:)
    func beginSSH(window: NSWindow?, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        runSSH(window: window) { response, urls in
            if response == .OK {
                self.items = (urls ?? []).map { url in
                    let promise = iTermRenegablePromise<NSURL>() { seal in
                        seal.fulfill(url as NSURL)
                    }
                    return iTermOpenPanelItem(
                        urlPromise: promise,
                        filename: url.path,
                        isDirectory: url.hasDirectoryPath,
                        host: .localhost,
                        progress: Progress(),
                        cancellation: Cancellation())
                }
            }
            handler(response)
        }
    }

    @objc
    func beginSheetModal(for window: NSWindow?,
                         completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        runSystem(window: window) { response, urls in
            if response == .OK {
                self.items = (urls ?? []).map { url in
                    let promise = iTermRenegablePromise<NSURL> { seal in
                        seal.fulfill(url as NSURL)
                    }
                    return iTermOpenPanelItem(
                        urlPromise: promise,
                        filename: url.path,
                        isDirectory: url.hasDirectoryPath,
                        host: .localhost,
                        progress: Progress(),
                        cancellation: Cancellation())
                }
            }
            handler(response)
        }
    }
    
    @objc private func openSSHPanelButtonClicked(_ sender: SSHOpenPanelButton) {
        guard let openPanel = sender.openPanel,
              let handler = sender.handler else {
            return
        }
        
        // Store the parent window before canceling
        let parentWindow = sender.parentWindow ?? openPanel.sheetParent
        
        // Preserve the current directory and settings from system panel
        preferredSSHIdentity = .localhost
        let directoryURL = openPanel.directoryURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        _directoryURL = directoryURL
        
        // Cancel the current open panel
        switchingPanels = true
        openPanel.cancel(nil)
        switchingPanels = false

        // Open SSH panel
        runSSH(window: parentWindow, handler: handler)
    }
}

// MARK: - Private Extension
@MainActor
private extension iTermOpenPanel {
    func createAccessoryViewWithSSHButton(userAccessory: NSView?,
                                          openPanel: NSOpenPanel,
                                          window: NSWindow?,
                                          handler: @escaping (NSApplication.ModalResponse, [URL]?) -> Void) -> NSView {
        let container = NSView()
        
        // Create SSH panel button
        let sshButton = SSHOpenPanelButton()
        sshButton.title = "Open SSH Panel..."
        sshButton.target = self
        sshButton.action = #selector(openSSHPanelButtonClicked(_:))
        sshButton.bezelStyle = .rounded
        sshButton.translatesAutoresizingMaskIntoConstraints = false
        sshButton.openPanel = openPanel
        sshButton.parentWindow = window
        sshButton.handler = handler

        container.addSubview(sshButton)
        
        // Add user's accessory view if provided
        if let userAccessory = userAccessory {
            userAccessory.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(userAccessory)
            
            // Layout constraints with centering and margins
            NSLayoutConstraint.activate([
                // Center SSH button horizontally with top margin
                sshButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                sshButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                
                // User accessory view below SSH button
                userAccessory.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                userAccessory.topAnchor.constraint(equalTo: sshButton.bottomAnchor, constant: 12),
                userAccessory.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                userAccessory.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
            ])
        } else {
            // Layout constraints for button only - centered with margins
            NSLayoutConstraint.activate([
                sshButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                sshButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                sshButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
            ])
        }
        
        return container
    }
    
    func runSystem(window: NSWindow?,
                   handler: @escaping (NSApplication.ModalResponse, [URL]?) -> Void) {
        Self.panels.append(self)
        let openPanel = NSOpenPanel()
        
        // Copy settings
        openPanel.canChooseDirectories = canChooseDirectories
        openPanel.canChooseFiles = canChooseFiles
        openPanel.allowsMultipleSelection = allowsMultipleSelection
        openPanel.allowedContentTypes = allowedContentTypes
        openPanel.showsHiddenFiles = showsHiddenFiles
        
        if let directoryURL = directoryURL {
            openPanel.directoryURL = directoryURL
        }
        
        // Add SSH panel button if SSH connections are available
        let shouldShowSSHButton = !ConductorRegistry.instance.isEmpty && includeLocalhost
        if shouldShowSSHButton {
            openPanel.accessoryView = createAccessoryViewWithSSHButton(userAccessory: accessoryView,
                                                                       openPanel: openPanel,
                                                                       window: window,
                                                                       handler: handler)
            // Try to expand the accessory view by default
            openPanel.isAccessoryViewDisclosed = true
        } else {
            openPanel.accessoryView = accessoryView
        }
        
        let responseHandler = { [weak self] (response: NSApplication.ModalResponse) in
            guard let self else { return }
            if switchingPanels {
                return
            }
            if response == .OK {
                handler(response, openPanel.urls)
            } else {
                handler(response, nil)
            }
            Self.panels.remove(object: self)
        }
        
        if let window {
            openPanel.beginSheetModal(for: window, completionHandler: responseHandler)
        } else {
            openPanel.begin(completionHandler: responseHandler)
        }
    }
}
