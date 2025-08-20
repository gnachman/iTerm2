//
//  iTermModernSavePanel.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

import UniformTypeIdentifiers

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
        beginWithFallback(window: nil, handler: handler)
    }

    // Fall back to system picker if there are no ssh integration sessions active
    @objc(beginWithFallbackWindow:handler:)
    func beginWithFallback(window: NSWindow?,
                           handler: @escaping (NSApplication.ModalResponse, iTermSavePanelItem?) -> Void) {
        if ConductorRegistry.instance.isEmpty || requireLocalhost {
            runSystem(window: window, handler: handler)
            return
        }
        if let window {
            beginSheetModal(for: window) { [weak self] response in
                handler(response, self?.item)
            }
        } else {
            begin { [weak self] response in
                handler(response, self?.item)
            }
        }
    }

    // Show the panel non-modally with a completion handler
    func begin(_ handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if requireLocalhost {
            runSystem(window: nil) { [weak self] response, item in
                self?.item = item
                handler(response)
            }
            return
        }
        let sshFilePanel = makePanel()

        // Present non-modally
        sshFilePanel.begin { [weak self] response in
            self?.handle(response, panel: sshFilePanel, handler: handler)
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
        if requireLocalhost {
            runSystem(window: window) { [weak self] response, item in
                self?.item = item
                handler(response)
            }
            return
        }
        let sshFilePanel = makePanel()
        sshFilePanel.beginSheetModal(for: window) { [weak self] response in
            self?.handle(response, panel: sshFilePanel, handler: handler)
        }
    }
}

@MainActor
private extension iTermModernSavePanel {
    func runSystem(window: NSWindow?,
                   handler: @escaping (NSApplication.ModalResponse, iTermSavePanelItem?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = defaultFilename ?? ""
        if preferredSSHIdentity == .localhost {
            savePanel.directoryURL = directoryURL
        }
        savePanel.isExtensionHidden = isExtensionHidden
        savePanel.allowedContentTypes = allowedContentTypes
        savePanel.nameFieldStringValue = nameFieldStringValue
        savePanel.accessoryView = accessoryView
        savePanel.allowsOtherFileTypes = allowsOtherFileTypes
        savePanel.showsHiddenFiles = showsHiddenFiles
        savePanel.canSelectHiddenExtension = canSelectHiddenExtension

        if delegate != nil {
            savePanel.delegate = self
        }

        // Present non-modally
        savePanel.begin { [weak self] response in
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
        sshFilePanel.accessoryView = accessoryView
        sshFilePanel.preferredSSHIdentity = preferredSSHIdentity
        sshFilePanel.initialDirectory = directoryURL
        sshFilePanel.allowedContentTypes = allowedContentTypes
        sshFilePanel.defaultFilename = nameFieldStringValue
        sshFilePanel.allowsOtherFileTypes = allowsOtherFileTypes
        sshFilePanel.showsHiddenFiles = showsHiddenFiles
        
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
