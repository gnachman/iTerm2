//
//  iTermModernSavePanel.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

@objc
class iTermSavePanelItem: NSObject {
    @objc var filename: String
    @objc var host: SSHIdentity

    init(filename: String,
         host: SSHIdentity) {
        self.filename = filename
        self.host = host
    }
}

@objc
@MainActor
class iTermModernSavePanel: NSObject {
    @objc var includeLocalhost = true
    @objc private(set) var item: iTermSavePanelItem?
    static var panels = [iTermModernSavePanel]()
    @objc var defaultFilename: String?
    @objc var canCreateDirectories = true

    // Show the panel non-modally with a completion handler
    func begin(_ handler: @escaping (NSApplication.ModalResponse) -> Void) {
        Self.panels.append(self)

        if #available(macOS 11, *) {
            let sshFilePanel = SSHFilePanel()
            sshFilePanel.canChooseDirectories = false
            sshFilePanel.canChooseFiles = true
            sshFilePanel.includeLocalhost = includeLocalhost
            sshFilePanel.isSavePanel = true
            sshFilePanel.defaultFilename = defaultFilename
            sshFilePanel.canCreateDirectories = canCreateDirectories

            sshFilePanel.dataSource = ConductorRegistry.instance

            // Present non-modally
            sshFilePanel.begin { [weak self] response in
                guard let self else { return }
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
        } else {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = defaultFilename ?? ""

            // Present non-modally
            savePanel.begin { [weak self] response in
                guard let self else { return }
                if response == .OK,
                   let url = savePanel.url {
                    item = iTermSavePanelItem(filename: url.path, host: SSHIdentity.localhost)
                } else {
                    item = nil
                }
                handler(response)
                Self.panels.remove(object: self)
            }
        }
    }

    func beginSheetModal(for window: NSWindow) async -> NSApplication.ModalResponse {
        return await withCheckedContinuation { continuation in
            beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }

    func beginSheetModal(for window: NSWindow,
                         completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        Self.panels.append(self)

        if #available(macOS 11, *) {
            let sshFilePanel = SSHFilePanel()
            sshFilePanel.canChooseDirectories = false
            sshFilePanel.canChooseFiles = true
            sshFilePanel.includeLocalhost = includeLocalhost
            sshFilePanel.isSavePanel = true
            sshFilePanel.defaultFilename = defaultFilename
            sshFilePanel.canCreateDirectories = canCreateDirectories

            sshFilePanel.dataSource = ConductorRegistry.instance

            sshFilePanel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
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
        } else {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = defaultFilename ?? ""

            savePanel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .OK,
                   let url = savePanel.url {
                    item = iTermSavePanelItem(filename: url.path, host: SSHIdentity.localhost)
                } else {
                    item = nil
                }
                handler(response)
                Self.panels.remove(object: self)
            }
        }
    }
}
