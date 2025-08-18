//
//  iTermOpenPanel.swift
//  iTerm2
//
//  Created by George Nachman on 6/8/25.
//

import UniformTypeIdentifiers

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
    @objc var defaultToLocalhost = false
    @objc private(set) var items: [iTermOpenPanelItem] = []
    static var panels = [iTermOpenPanel]()
    var isSelectable: ((RemoteFile) -> Bool)?

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

    // Fall back to system picker if there are no ssh integration sessions active
    @objc
    func beginWithFallback(_ handler: @escaping (NSApplication.ModalResponse, [URL]?) -> Void) {
        if ConductorRegistry.instance.isEmpty {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = allowedContentTypes
            panel.begin { [weak panel] response in
                if response == .OK {
                    handler(.OK, panel?.urls ?? [])
                } else {
                    handler(response, nil)
                }
            }
            return
        }
        begin { [weak self] response in
            if response == .OK {
                self?.loadURLs { urls in
                    handler(.OK, urls)
                }
            } else {
                handler(response, nil)
            }
        }
    }

    // Show the panel non-modally with a completion handler
    @objc
    func begin(_ handler: @escaping (NSApplication.ModalResponse) -> Void) {
        Self.panels.append(self)

        let sshFilePanel = SSHFilePanel()
        sshFilePanel.canChooseDirectories = canChooseDirectories
        sshFilePanel.canChooseFiles = canChooseFiles
        sshFilePanel.isSelectable = isSelectable
        sshFilePanel.includeLocalhost = includeLocalhost
        sshFilePanel.allowedContentTypes = allowedContentTypes
        sshFilePanel.allowsMultipleSelection = allowsMultipleSelection
        sshFilePanel.defaultToLocalhost = defaultToLocalhost
        
        sshFilePanel.dataSource = ConductorRegistry.instance

        // Present non-modally
        sshFilePanel.begin { [weak self] response in
            guard let self else { return }
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
    }

    @objc
    func beginSheetModal(for window: NSWindow,
                         completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        Self.panels.append(self)

        let sshFilePanel = SSHFilePanel()
        sshFilePanel.canChooseDirectories = canChooseDirectories
        sshFilePanel.canChooseFiles = canChooseFiles
        sshFilePanel.isSelectable = isSelectable
        sshFilePanel.includeLocalhost = includeLocalhost
        sshFilePanel.allowedContentTypes = allowedContentTypes
        sshFilePanel.allowsMultipleSelection = allowsMultipleSelection
        sshFilePanel.defaultToLocalhost = defaultToLocalhost

        sshFilePanel.dataSource = ConductorRegistry.instance

        sshFilePanel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
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
    }
}
