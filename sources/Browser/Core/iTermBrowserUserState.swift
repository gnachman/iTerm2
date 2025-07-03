//
//  iTermBrowserUserState.swift
//  iTerm2
//
//  Created by George Nachman on 7/3/25.
//

import WebExtensionsFramework
import WebKit

@MainActor
class iTermBrowserUserState {
    private static var _instances = [iTermBrowserUser: iTermBrowserUserState]()
    private let extensionRegistry: BrowserExtensionRegistry?
    private let activeExtensionManager: BrowserExtensionActiveManager?
    private let configuration: Configuration
    private let userDefaultsObserver: iTermUserDefaultsObserver

    struct Configuration: Equatable {
        var extensionsAllowed = true
    }

    init(_ configuration: Configuration) {
        self.configuration = configuration
        if #available(macOS 14, *) {
            if configuration.extensionsAllowed {
                extensionRegistry = BrowserExtensionRegistry()
                activeExtensionManager = BrowserExtensionActiveManager(
                    injectionScriptGenerator: BrowserExtensionInjectionScriptGenerator(),
                    userScriptFactory: BrowserExtensionUserScriptFactory())
            } else {
                extensionRegistry = nil
                activeExtensionManager = nil
            }
        } else {
            extensionRegistry = nil
            activeExtensionManager = nil
        }
        userDefaultsObserver = iTermUserDefaultsObserver()

        updateLoaded()
        updateActivation()

        // Advanced settings use a UD observer so to avoid winning a race and seeing an outdated
        // setting, wait a spin of the mainloop so it gets to run first.
        userDefaultsObserver.observeKey("BrowserExtensionPaths") { [weak self] in
            DispatchQueue.main.async {
                self?.updateLoaded()
            }
        }
        userDefaultsObserver.observeKey("ActiveBrowserExtensionPaths") { [weak self] in
            DispatchQueue.main.async {
                self?.updateActivation()
            }
        }
    }
}

extension iTermBrowserUserState {
    @MainActor
    static func instance(for user: iTermBrowserUser, configuration: Configuration) -> iTermBrowserUserState {
        if let existing = _instances[user], existing.configuration == configuration {
            return existing
        }
        let state = iTermBrowserUserState(configuration)
        _instances[user] = state
        return state
    }

    private static func desiredLoadPaths() -> Set<String> {
        guard let string = iTermAdvancedSettingsModel.browserExtensionPaths() else {
            return Set()
        }
        let paths = string.components(separatedBy: " ").filter { !$0.isEmpty }
        return Set(paths)
    }

    private static func desiredActivePaths() -> Set<String> {
        guard let string = iTermAdvancedSettingsModel.activeBrowserExtensionPaths() else {
            return Set()
        }
        let paths = string.components(separatedBy: " ").filter { !$0.isEmpty }
        return Set(paths)
    }

    private func updateLoaded() {
        guard let extensionRegistry else {
            return
        }
        let current = extensionRegistry.extensionPaths
        let desired = Self.desiredLoadPaths()
        DLog("Currently loaded: \(Array(current).joined(separator: ";a"))")
        DLog("Desired: \(Array(desired).joined(separator: ";a"))")

        let toRemove = current.subtracting(desired)
        for path in toRemove {
            do {
                try extensionRegistry.remove(extensionPath: path)
            } catch {
                DLog("Failed to remove \(path): \(error)")
            }
        }

        let toAdd = desired.subtracting(current)
        for path in toAdd {
            do {
                try extensionRegistry.add(extensionPath: path)
            } catch {
                DLog("Failed to add \(path): \(error)")
            }
        }
    }

    private func updateActivation() {
        guard let activeExtensionManager else {
            return
        }
        let active = activeExtensionManager.allActiveExtensions()
        var pathToID = [String: String]()
        for (id, ext) in active {
            pathToID[ext.browserExtension.baseURL.path] = id
        }

        let currentPaths = Set(active.keys)
        let desiredPaths = Self.desiredActivePaths()
        DLog("Current paths: \(currentPaths.joined(separator: "; "))")
        DLog("Desired paths: \(desiredPaths.joined(separator: "; "))")
        let pathsToRemove = currentPaths.subtracting(desiredPaths)
        for path in pathsToRemove {
            if let id = pathToID[path] {
                activeExtensionManager.deactivate(id)
            }
        }

        let toAdd = desiredPaths.subtracting(currentPaths)
        DLog("Extension registry contains \(extensionRegistry!.extensions.map { "\($0.baseURL.path) with ID \($0.id)" }.joined(separator: "; "))")
        for path in toAdd {
            if let browserExtension = extensionRegistry?.extensions.first(where: { $0.baseURL.path == path }) {
                do {
                    DLog("Will activate \(browserExtension.id)")
                    try activeExtensionManager.activate(browserExtension)
                } catch {
                    DLog("Failed to activate \(browserExtension.id)")
                }
            } else {
                DLog("Failed to find extension at \(path)")
            }
        }
    }

    public func registerWebView(_ webView: WKWebView) {
        do {
            try activeExtensionManager?.registerWebView(webView)
        } catch {
            DLog("Failed to register webview: \(error)")
        }
    }

    public func unregisterWebView(_ webView: WKWebView) {
        activeExtensionManager?.unregisterWebView(webView)
    }
}
