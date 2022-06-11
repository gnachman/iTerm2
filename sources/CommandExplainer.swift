//
//  CommandExplainer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/2/22.
//

import Foundation

@objc(iTermCommandExplainer)
class CommandExplainer: NSObject {
    @objc static let instance = CommandExplainer()
    // Tokens are used to prevent other apps from exploiting the iterm2 scheme to open URLs and also
    // to remember which window to attach the permission alert box to.
    private var tokens = [String: WeakBox<NSWindow>]()

    func newURL(for command: String, window: NSWindow?) -> URL {
        var components = URLComponents()
        components.scheme = "iterm2"
        components.path = "explain"
        components.queryItems = [URLQueryItem(name: "command", value: command),
                                 URLQueryItem(name: "token", value: makeToken(window))]
        return components.url!
    }

    @objc(explainWithURL:)
    func explain(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }
        guard components.scheme == "iterm2" else {
            return
        }
        guard components.host == nil else {
            return
        }
        guard components.path == "explain" else {
            return
        }
        guard let command = components.queryItems?.first(where: { item in
            item.name == "command"
        })?.value else {
            return
        }
        guard let token = components.queryItems?.first(where: { item in
            item.name == "token"
        })?.value else {
            return
        }
        guard let windowBox = tokens[token] else {
            return
        }
        tokens.removeValue(forKey: token)
        explainCommand(command, window: windowBox.value)
    }

    private func makeToken(_ window: NSWindow?) -> String {
        let token = UUID().uuidString
        tokens[token] = WeakBox(window)
        return token
    }

    private func explainCommand(_ command: String, window: NSWindow?) {
        guard let browserName = self.browserName, !browserName.isEmpty else {
            return
        }
        let components = NSURLComponents()
        components.host = "explainshell.com"
        components.scheme = "https"
        components.path = "/explain"
        components.queryItems = [URLQueryItem(name: "cmd", value: command)]
        guard let url = components.url else {
            return
        }
        let selection = iTermWarning.show(withTitle: "This will open \(url.absoluteString) in \(browserName).",
                                          actions: ["OK", "Cancel"],
                                          accessory: nil,
                                          identifier: "NoSyncExplainShell",
                                          silenceable: .kiTermWarningTypePermanentlySilenceable,
                                          heading: "Open ExplainShell?",
                                          window: window)
        if selection == .kiTermWarningSelection0 {
            NSWorkspace.shared.open(url)
        }
    }

    private var browserName: String? {
        let url = URL(string: "https://explainshell.com/explain?cmd=example")!
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return nil
        }
        guard let bundle = Bundle(url: appURL) else {
            return nil
        }
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return displayName
        }
        if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return bundleName
        }
        return appURL.deletingPathExtension().lastPathComponent
    }
}
