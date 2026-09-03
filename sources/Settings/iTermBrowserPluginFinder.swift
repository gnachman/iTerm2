//
//  iTermBrowserPluginFinder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/25.
//

import AppKit

@objc
class iTermBrowserPluginFinder: NSObject, NSOpenSavePanelDelegate {
    @objc static var instance: iTermBrowserPluginFinder?
    private let allowedBundleName = "iTermBrowserPlugin"

    @objc
    func openFindPanel(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.delegate = self
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = String(format: String(localized: "BrowserPluginFinder_Select_FORMAT", defaultValue: "Select %1$@", comment: "Title in openFindPanel"), allowedBundleName)
        panel.prompt = String(localized: "BrowserPluginFinder_Choose", defaultValue: "Choose", comment: "Text shown in openFindPanel: Choose")
        panel.message = String(format: String(localized: "BrowserPluginFinder_SelectMessage_FORMAT", defaultValue: "Select %1$@.", comment: "Formatted alert message in openFindPanel"), allowedBundleName)
        panel.allowedContentTypes = [.bundle, .application, .applicationBundle]
        panel.begin { response in
            if response == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - NSOpenSavePanelDelegate

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        guard url.pathExtension == "app" else {
            return false
        }
        return url.deletingPathExtension().lastPathComponent == allowedBundleName
    }

    func panel(_ sender: Any, validate url: URL) throws {
        let isCorrect = url.deletingPathExtension().lastPathComponent == allowedBundleName
        if !isCorrect {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey:
                                     "You must select \(allowedBundleName)"])
        }
    }
}
