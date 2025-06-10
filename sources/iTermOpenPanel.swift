//
//  iTermOpenPanel.swift
//  iTerm2
//
//  Created by George Nachman on 6/8/25.
//

@objc
class iTermOpenPanelItem: NSObject {
    @objc var urlPromise: iTermRenegablePromise<NSURL>
    @objc var filename: String
    @objc var host: SSHIdentity
    @objc var progress: Progress
    @objc var cancellation: Cancellation

    init(urlPromise: iTermRenegablePromise<NSURL>,
         filename: String,
         host: SSHIdentity,
         progress: Progress,
         cancellation: Cancellation) {
        self.urlPromise = urlPromise
        self.filename = filename
        self.host = host
        self.progress = progress
        self.cancellation = cancellation
    }
}

@objc
class iTermOpenPanel: NSObject {
    @objc var canChooseDirectories = true
    @objc var canChooseFiles = true
    @objc let allowsMultipleSelection = true  // TODO
    @objc private(set) var items: [iTermOpenPanelItem] = []
    static var panels = [iTermOpenPanel]()

    func beginSheetModal(for window: NSWindow,
                         completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
        Self.panels.append(self)

        if #available(macOS 11, *) {
            let sshFilePanel = SSHFilePanel()
            sshFilePanel.dataSource = ConductorRegistry.instance
            sshFilePanel.canChooseDirectories = canChooseDirectories
            sshFilePanel.canChooseFiles = canChooseFiles

            sshFilePanel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .OK {
                    items = sshFilePanel.promiseItems().map { item in
                        iTermOpenPanelItem(urlPromise: item.promise,
                                           filename: item.filename,
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
        } else {
            let openPanel = NSOpenPanel()
            openPanel.allowsMultipleSelection = allowsMultipleSelection
            openPanel.canChooseDirectories = canChooseDirectories
            openPanel.canChooseFiles = canChooseFiles

            openPanel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .OK {
                    items = openPanel.urls.map { url in
                        let promise = iTermRenegablePromise<NSURL> { seal in
                            seal.fulfill(url as NSURL)
                        }
                        return iTermOpenPanelItem(urlPromise: promise,
                                                  filename: url.path,
                                                  host: SSHIdentity.localhost,
                                                  progress: Progress(),
                                                  cancellation: Cancellation())
                    }
                } else {
                    items = []
                }
                handler(response)
                Self.panels.remove(object: self)
            }
        }
    }
}
