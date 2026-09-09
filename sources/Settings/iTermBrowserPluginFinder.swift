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
        panel.title = String(localized: "BrowserPluginFinder.Title", defaultValue: "Select \(allowedBundleName)", comment: "Open panel window title; the interpolation is the required bundle name")
        panel.prompt = String(localized: "BrowserPluginFinder.ChoosePrompt", defaultValue: "Choose", comment: "Open panel prompt button title")
        panel.message = String(localized: "BrowserPluginFinder.Message", defaultValue: "Select \(allowedBundleName).", comment: "Open panel message; the interpolation is the required bundle name")
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
                                     String(localized: "BrowserPluginFinder.MustSelect", defaultValue: "You must select \(allowedBundleName)", comment: "Error shown when the user selects the wrong bundle; the interpolation is the required bundle name")])
        }
    }
}
