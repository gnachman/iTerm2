//
//  iTermModernSavePanel.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

import UniformTypeIdentifiers

@MainActor
private class SSHPanelButton: NSButton {
    weak var savePanel: NSSavePanel?
    weak var parentWindow: NSWindow?
    var handler: ((NSApplication.ModalResponse, iTermSavePanelItem?) -> Void)?
    weak var modernSavePanel: iTermModernSavePanel?
}

@objc
@MainActor
class iTermSavePanelItem: NSObject {
    @objc var filename: String
    @objc var host: SSHIdentity

    init(filename: String,
         host: SSHIdentity) {
        self.filename = filename
        self.host = host
    }

    @objc var displayName: String {
        "“\(filename.lastPathComponent)” on \(host.displayName)"
    }
    @objc var pathExtension: String {
        return filename.pathExtension
    }
    @objc func setPathExtension(_ ext: String) {
        let url = URL(fileURLWithPath: filename).deletingPathExtension().appendingPathExtension(ext)
        filename = url.path
    }

    @objc var directory: String {
        URL(fileURLWithPath: filename).deletingLastPathComponent().path
    }

    @objc func setLastPathComponent(_ value: String) {
        filename = URL(fileURLWithPath:filename).deletingLastPathComponent().appendingPathComponent(value).path
    }

    @objc func exists(_ completion: @escaping (Bool) -> ()) {
        Task {
            guard let endpoint = host.endpoint else {
                completion(false)
                return
            }
            do {
                _ = try await endpoint.stat(filename)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    @objc func revealInFinderIfLocal() {
        if host.isLocalhost {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filename)])
        }
    }

    @MainActor
    @objc func upload(data: Data) async throws {
        if host.isLocalhost {
            try data.write(to: URL(fileURLWithPath: filename))
            return
        }
        if let delegate = host.endpoint as? ConductorFileTransferDelegate {
            let transfer = ConductorFileTransfer(path: host.scpPath(filename: filename),
                                                 localPath: nil,
                                                 data: data,
                                                 delegate: delegate)
            transfer.upload()
        } else if let endpoint = host.endpoint {
            _ = try await endpoint.replace(filename, content: data)
        } else {
            iTermWarning.show(withTitle: "No ssh connection to \(host.displayName) is available to upload \(filename.lastPathComponent)",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Upload Failed",
                              window: nil)
        }
    }
}

@objc
@MainActor
protocol iTermModernSavePanelDelegate: AnyObject {
    // For save panels: This method is not sent. All urls are always disabled.
    // For open panels: Return `YES` to allow the `item` to be enabled in the panel.
    //   Delegate implementations should be fast to avoid stalling the UI.
    func panel(_ sender: iTermModernSavePanel, shouldEnable item: iTermSavePanelItem) -> Bool
    func panel(_ sender: iTermModernSavePanel, didChangeToDirectory: iTermSavePanelItem?)
    func panel(_ sender: iTermModernSavePanel, userEnteredFilename: String, confirmed: Bool) -> String?

    // `NSSavePanel`: Sent once by the save panel when the user clicks the Save button. The user is intending to save a file at `url`. Return `YES` if the `url` is a valid location to save to. Return `NO` and return by reference `outError` with a user displayable error message for why the `url` is not valid. If a recovery option is provided by the error, and recovery succeeded, the panel will attempt to close again.
    //  Note: An item at `url` may not physically exist yet, unless the user decided to overwrite an existing item.
    // `NSOpenPanel`: Sent once for each selected filename (or directory) when the user chooses the Open button. Return `YES` if the `url` is acceptable to open. Return `NO` and return by reference `outError` with a user displayable message for why the `url` is not valid for opening. If a recovery option is provided by the error, and recovery succeeded, the panel will attempt to close again.
    // Note: Implement this delegate method instead of  `panel:shouldEnableURL:` if the processing of the selected item takes a long time.
    func panel(_ sender: iTermModernSavePanel, validate item: iTermSavePanelItem) throws
}

@objc
class iTermModernSavePanel: NSObject {
    @objc var includeLocalhost = true
    @objc private(set) var item: iTermSavePanelItem?
    static var panels = [iTermModernSavePanel]()
    @objc var defaultFilename: String?
    @objc var canCreateDirectories = true
    @objc var accessoryView: NSView?
    private var _directoryURL: URL?
    @objc var preferredSSHIdentity: SSHIdentity?
    @objc(extensionHidden) var isExtensionHidden = false
    @objc var allowedContentTypes = [UTType]()
    @objc var nameFieldStringValue = ""
    @objc weak var delegate: iTermModernSavePanelDelegate?
    @objc var requireLocalhost = false
    @objc var allowsOtherFileTypes = false
    @objc var showsHiddenFiles = false
    @objc var canSelectHiddenExtension = true
    private var completionHandler: ((NSApplication.ModalResponse, iTermSavePanelItem?) -> Void)?
}

@objc
extension iTermModernSavePanel {
    var directoryURL: URL? {
        return _directoryURL
    }
}

@objc
@MainActor
extension iTermModernSavePanel {
    @objc(beginWithFallback:)
    func beginWithFallback(handler: @escaping (NSApplication.ModalResponse, iTermSavePanelItem?) -> Void) {
        self.completionHandler = handler
        beginWithFallback(window: nil, handler: handler)
    }

    // Always use system picker with SSH panel option
    @objc(beginWithFallbackWindow:handler:)
    func beginWithFallback(window: NSWindow?,
                           handler: @escaping (NSApplication.ModalResponse, iTermSavePanelItem?) -> Void) {
        self.completionHandler = handler
        runSystem(window: window, handler: handler)
    }

    // Show the panel non-modally with a completion handler
    func begin(_ handler: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completionHandler = { response, _ in handler(response) }
        runSystem(window: nil) { [weak self] response, item in
            self?.item = item
            handler(response)
        }
    }

    @nonobjc
    func beginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse {
        return await withCheckedContinuation { continuation in
            beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    func beginSheetModal(for window: NSWindow,
                         completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completionHandler = { response, _ in handler(response) }
        runSystem(window: window) { [weak self] response, item in
            self?.item = item
            handler(response)
        }
    }
    
    @objc private func openSSHPanelButtonClicked(_ sender: SSHPanelButton) {
        guard let savePanel = sender.savePanel,
              let handler = self.completionHandler,
              let modernSavePanel = sender.modernSavePanel else {
            return
        }
        
        // Store the parent window before canceling
        let parentWindow = sender.parentWindow ?? savePanel.sheetParent
        
        // Preserve the current directory and filename from system panel
        modernSavePanel.preferredSSHIdentity = .localhost  // Always set to localhost when coming from system panel
        // Get the current directory from the system panel - use the current working directory if not set
        let directoryURL = savePanel.directoryURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        modernSavePanel._directoryURL = directoryURL
        if !savePanel.nameFieldStringValue.isEmpty {
            modernSavePanel.nameFieldStringValue = savePanel.nameFieldStringValue
        }
        
        // Cancel the current save panel
        savePanel.cancel(nil)
        
        // Open SSH panel
        let sshFilePanel = modernSavePanel.makePanel()
        
        if let window = parentWindow {
            sshFilePanel.beginSheetModal(for: window) { [weak modernSavePanel] response in
                modernSavePanel?.handle(response, panel: sshFilePanel, handler: { modalResponse in
                    handler(modalResponse, modernSavePanel?.item)
                })
            }
        } else {
            sshFilePanel.begin { [weak modernSavePanel] response in
                modernSavePanel?.handle(response, panel: sshFilePanel, handler: { modalResponse in
                    handler(modalResponse, modernSavePanel?.item)
                })
            }
        }
    }
}

@MainActor
private extension iTermModernSavePanel {
    func createAccessoryViewWithSSHButton(userAccessory: NSView?,
                                          savePanel: NSSavePanel,
                                          window: NSWindow?,
                                          handler: @escaping (NSApplication.ModalResponse, iTermSavePanelItem?) -> Void) -> NSView {
        let container = NSView()

        // Create SSH panel button
        let sshButton = SSHPanelButton()
        sshButton.title = "Open SSH Panel..."
        sshButton.target = self
        sshButton.action = #selector(openSSHPanelButtonClicked(_:))
        sshButton.bezelStyle = .rounded
        sshButton.translatesAutoresizingMaskIntoConstraints = false
        sshButton.savePanel = savePanel
        sshButton.parentWindow = window
        sshButton.handler = handler
        sshButton.modernSavePanel = self

        container.addSubview(sshButton)

        // Add user's accessory view if provided
        if let userAccessory = userAccessory {
            // Clean up from previous usage - removeFromSuperview will deactivate layout constraints
            userAccessory.removeFromSuperview()
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
                userAccessory.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
                userAccessory.heightAnchor.constraint(equalToConstant: userAccessory.frame.height)
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
                   handler: @escaping (NSApplication.ModalResponse, iTermSavePanelItem?) -> Void) {
        Self.panels.append(self)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = defaultFilename ?? ""
        if preferredSSHIdentity == .localhost {
            savePanel.directoryURL = directoryURL
        }
        savePanel.isExtensionHidden = isExtensionHidden
        savePanel.allowedContentTypes = allowedContentTypes
        savePanel.nameFieldStringValue = nameFieldStringValue
        
        // Add SSH panel button if SSH connections are available and not requireLocalhost
        let shouldShowSSHButton = !ConductorRegistry.instance.isEmpty && !requireLocalhost
        if shouldShowSSHButton {
            savePanel.accessoryView = createAccessoryViewWithSSHButton(userAccessory: accessoryView,
                                                                       savePanel: savePanel,
                                                                       window: window,
                                                                       handler: handler)
        } else {
            savePanel.accessoryView = accessoryView
        }
        
        savePanel.allowsOtherFileTypes = allowsOtherFileTypes
        savePanel.showsHiddenFiles = showsHiddenFiles
        savePanel.canSelectHiddenExtension = canSelectHiddenExtension

        if delegate != nil {
            savePanel.delegate = self
        }

        let responseHandler = { [weak self] (response: NSApplication.ModalResponse) in
            guard let self else { return }
            if response == .OK,
               let url = savePanel.url {
                item = iTermSavePanelItem(filename: url.path, host: SSHIdentity.localhost)
            } else {
                item = nil
            }
            let item: iTermSavePanelItem? = if let url = savePanel.url {
                iTermSavePanelItem(filename: url.path, host: .localhost)
            } else {
                nil
            }
            self.item = item
            handler(response, item)
            Self.panels.remove(object: self)
        }
        if let window {
            savePanel.beginSheetModal(for: window, completionHandler: responseHandler)
        } else {
            savePanel.begin(completionHandler: responseHandler)
        }
    }

    func makePanel() -> SSHFilePanel {
        Self.panels.append(self)

        let sshFilePanel = SSHFilePanel()
        sshFilePanel.canChooseDirectories = false
        sshFilePanel.canChooseFiles = true
        sshFilePanel.includeLocalhost = includeLocalhost
        sshFilePanel.isSavePanel = true
        sshFilePanel.defaultFilename = defaultFilename
        sshFilePanel.canCreateDirectories = canCreateDirectories

        // Reset accessory view layout properties if it was previously used in a system panel with SSH button
        if let accessoryView = accessoryView {
            accessoryView.removeFromSuperview()
        }
        sshFilePanel.accessoryView = accessoryView
        DLog("makePanel: setting preferredSSHIdentity: \(String(describing: preferredSSHIdentity)), initialDirectory: \(String(describing: directoryURL))")
        sshFilePanel.preferredSSHIdentity = preferredSSHIdentity
        sshFilePanel.initialDirectory = directoryURL
        sshFilePanel.allowedContentTypes = allowedContentTypes
        sshFilePanel.defaultFilename = nameFieldStringValue
        sshFilePanel.allowsOtherFileTypes = allowsOtherFileTypes
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
            
            // Preserve the filename for save panels
            if sshFilePanel.isSavePanel,
               let saveAsValue = sshFilePanel.saveAsTextField?.stringValue {
                self.nameFieldStringValue = saveAsValue
            }
            
            // Close the SSH panel first
            if let sheetParent = sshFilePanel.window?.sheetParent {
                sheetParent.endSheet(sshFilePanel.window!)
            } else if NSApp.modalWindow == sshFilePanel.window {
                NSApp.stopModal(withCode: .cancel)
                sshFilePanel.window?.orderOut(nil)
            } else {
                sshFilePanel.window?.orderOut(nil)
            }
            
            // Now open the system panel
            self.runSystem(window: parentWindow) { response, item in
                self.item = item
                completionHandler?(response, item)
            }
        }
        
        if delegate != nil {
            sshFilePanel.delegate = self
        }

        sshFilePanel.dataSource = ConductorRegistry.instance
        return sshFilePanel
    }

    func handle(_ response: NSApplication.ModalResponse,
                panel sshFilePanel: SSHFilePanel,
                handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if response == .OK,
           let descriptor = sshFilePanel.destinationDescriptor {
            item = iTermSavePanelItem(filename: descriptor.absolutePath,
                                      host: descriptor.sshIdentity)
        } else {
            item = nil
        }
        handler(response)
        Self.panels.remove(object: self)
    }
}

@objc
@MainActor
extension NSArray {
    @objc
    func writeTo(saveItem: iTermSavePanelItem) async throws {
        let data = try PropertyListSerialization.data(fromPropertyList: self as NSArray,
                                                        format: .binary,
                                                        options: 0)
        try await saveItem.upload(data: data)
    }
}

@objc
@MainActor
extension NSDictionary {
    @objc
    func writeTo(saveItem: iTermSavePanelItem) async throws {
        let data = try PropertyListSerialization.data(fromPropertyList: self as NSDictionary,
                                                        format: .binary,
                                                        options: 0)
        try await saveItem.upload(data: data)
    }
}

@MainActor
extension Data {
    func writeTo(saveItem: iTermSavePanelItem) async throws {
        try await (self as NSData).writeTo(saveItem: saveItem)
    }
}

@objc
@MainActor
extension NSData {
    @objc
    func writeTo(saveItem: iTermSavePanelItem) async throws {
        try await saveItem.upload(data: self as Data)
    }
}

@objc
@MainActor
extension NSString {
    @objc
    func writeTo(saveItem: iTermSavePanelItem) async throws {
        let data = (self as String).lossyData
        try await saveItem.upload(data: data)
    }
}

@MainActor
extension iTermModernSavePanel: SSHFilePanelDelegate {
    func panel(_ sender: SSHFilePanel, validate item: SSHFileDescriptor) throws {
        try delegate?.panel(self, validate: iTermSavePanelItem(filename: item.absolutePath,
                                                               host: item.sshIdentity))
    }
    
    func panel(_ sender: SSHFilePanel, shouldEnable item: SSHFileDescriptor) -> Bool {
        return delegate?.panel(self, shouldEnable: iTermSavePanelItem(filename: item.absolutePath,
                                                                      host: item.sshIdentity)) ?? true
    }

    func panel(_ sender: SSHFilePanel, didChangeToDirectory item: SSHFileDescriptor?) {
        if let item {
            delegate?.panel(self, didChangeToDirectory: iTermSavePanelItem(filename: item.absolutePath,
                                                                           host: item.sshIdentity))
        } else {
            delegate?.panel(self, didChangeToDirectory: nil)
        }
    }

    func panel(_ sender: SSHFilePanel, userEnteredFilename: String, confirmed: Bool) -> String? {
        return delegate?.panel(self,
                               userEnteredFilename: userEnteredFilename,
                               confirmed: confirmed)
    }
}

@MainActor
extension iTermModernSavePanel: NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        return delegate?.panel(self,
                               shouldEnable: .init(filename: url.path,
                                                   host: .localhost)) ?? true
    }

    func panel(_ sender: Any, didChangeToDirectoryURL url: URL?) {
        if let url {
            delegate?.panel(self, didChangeToDirectory: .init(filename: url.path,
                                                              host: .localhost))
        } else {
            delegate?.panel(self, didChangeToDirectory: nil)
        }
    }

    func panel(_ sender: Any,
               userEnteredFilename filename: String,
               confirmed okFlag: Bool) -> String? {
        let replacement = delegate?.panel(self, userEnteredFilename: filename, confirmed: okFlag)
        return replacement
    }

    func panel(_ sender: Any, validate url: URL) throws {
        try delegate?.panel(self,
                            validate: iTermSavePanelItem(filename: url.path,
                                                         host: .localhost))
    }
}

@objc
extension iTermModernSavePanel: iTermDirectoryURLSetting {
    func setDirectoryURL(_ url: URL!) {
        _directoryURL = directoryURL
    }
}
