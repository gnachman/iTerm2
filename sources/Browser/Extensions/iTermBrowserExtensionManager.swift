//
//  iTermBrowserExtensionManager.swift
//  iTerm2
//
//  Created by George Nachman on 7/14/25.
//

import Foundation
import WebKit
import WebExtensionsFramework

@MainActor
protocol iTermBrowserExtensionManagerProtocol {
    func addWebView(_ webView: WKWebView, contentManager: BrowserExtensionUserContentManager) async
    func removeWebView(_ webView: WKWebView)
}

@MainActor
@available(macOS 14, *)
class iTermBrowserExtensionManager {
    private let extensionRegistry: BrowserExtensionRegistry?
    private let activeExtensionManager: BrowserExtensionActiveManager
    private let userDefaultsObserver: iTermUserDefaultsObserver
    private let logger: iTermLogger

    init(logger: iTermLogger,
         persistentStorageDisallowed: Bool,
         user: iTermBrowserUser,
         hiddenContainer: NSView) {
        self.logger = logger
        userDefaultsObserver = iTermUserDefaultsObserver()
        extensionRegistry = BrowserExtensionRegistry(logger: logger)
        let backgroundService = BrowserExtensionBackgroundService(
            hiddenContainer: hiddenContainer,
            logger: logger,
            useEphemeralDataStore: persistentStorageDisallowed,
            urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: logger))
        let network = BrowserExtensionNetwork()
        let storageManager = BrowserExtensionStorageManager(logger: logger)
        let deps = BrowserExtensionActiveManager.Dependencies(
            injectionScriptGenerator: BrowserExtensionContentScriptInjectionGenerator(logger: logger),
            userScriptFactory: BrowserExtensionUserScriptFactory(),
            backgroundService: backgroundService,
            network: network,
            router: BrowserExtensionRouter(network: network, logger: logger),
            logger: logger,
            storageManager: storageManager)
        activeExtensionManager = BrowserExtensionActiveManager(dependencies: deps)

        // Advanced settings use a UD observer so to avoid winning a race and seeing an outdated
        // setting, wait a spin of the mainloop so it gets to run first.
        userDefaultsObserver.observeKey("BrowserExtensionPaths") { [weak self] in
            DispatchQueue.main.async {
                self?.updateLoaded()
            }
        }
        userDefaultsObserver.observeKey("ActiveBrowserExtensionPaths") { [weak self] in
            DispatchQueue.main.async {
                Task {
                    await self?.updateActivation()
                }
            }
        }

        Task { [weak self] in
            if let db = await BrowserDatabase.instance(for: user) {
                storageManager.storageProvider = iTermBrowserStorageProvider(
                    database: db)
            }
            self?.updateLoaded()
            await self?.updateActivation()
        }
    }
}

@MainActor
@available(macOS 14, *)
extension iTermBrowserExtensionManager: iTermBrowserExtensionManagerProtocol {
    func addWebView(_ webView: WKWebView, contentManager: BrowserExtensionUserContentManager) async {
        do {
            try await activeExtensionManager.registerWebView(
                webView,
                userContentManager: contentManager,
                role: .userFacing)
        } catch {
            logger.error("Failed to register webview: \(error)")
        }
    }

    func removeWebView(_ webView: WKWebView) {
        activeExtensionManager.unregisterWebView(webView)
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
        logger.debug("Currently loaded: \(Array(current).joined(separator: ";a"))")
        logger.debug("Desired: \(Array(desired).joined(separator: ";a"))")

        let toRemove = current.subtracting(desired)
        for path in toRemove {
            do {
                try extensionRegistry.remove(extensionPath: path)
            } catch {
                logger.debug("Failed to remove \(path): \(error)")
            }
        }

        let toAdd = desired.subtracting(current)
        for path in toAdd {
            do {
                try extensionRegistry.add(extensionPath: path)
            } catch {
                logger.debug("Failed to add \(path): \(error)")
            }
        }
    }

    private func updateActivation() async {
        let active = activeExtensionManager.allActiveExtensions()
        var pathToID = [String: UUID]()
        for (id, ext) in active {
            pathToID[ext.browserExtension.baseURL.path] = id
        }

        let currentPaths = Set(active.values.map { $0.browserExtension.baseURL.path })
        let desiredPaths = Self.desiredActivePaths()
        logger.debug("Current paths: \(currentPaths.joined(separator: "; "))")
        logger.debug("Desired paths: \(desiredPaths.joined(separator: "; "))")
        let pathsToRemove = currentPaths.subtracting(desiredPaths)
        for path in pathsToRemove {
            if let id = pathToID[path] {
                await activeExtensionManager.deactivate(id)
            }
        }

        let toAdd = desiredPaths.subtracting(currentPaths)
        logger.debug("Extension registry contains \(extensionRegistry!.extensions.map { "\($0.baseURL.path) with ID \($0.id)" }.joined(separator: "; "))")
        for path in toAdd {
            if let browserExtension = extensionRegistry?.extensions.first(where: { $0.baseURL.path == path }) {
                logger.info("Will activate \(browserExtension.id)")
                await activeExtensionManager.activate(browserExtension)
            } else {
                logger.error("Failed to find extension at \(path)")
            }
        }
    }
}

