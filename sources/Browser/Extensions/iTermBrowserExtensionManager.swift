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
protocol iTermBrowserExtensionManagerDelegate: AnyObject {
    func extensionManagerDidUpdateExtensions(_ manager: iTermBrowserExtensionManagerProtocol)
}

@MainActor
protocol iTermBrowserExtensionManagerProtocol: AnyObject {
    func addWebView(_ webView: WKWebView, contentManager: BrowserExtensionUserContentManager) async
    func removeWebView(_ webView: WKWebView)
    var availableExtensions: [BrowserExtension] { get }
    func extensionEnabled(id: ExtensionID) -> Bool
    func set(id: ExtensionID, enabled: Bool)
    var extensionsDirectory: URL? { get }
    var delegate: iTermBrowserExtensionManagerDelegate? { get set }
}

@MainActor
@available(macOS 14, *)
class iTermBrowserExtensionManager {
    private let extensionRegistry: BrowserExtensionRegistry
    private let activeExtensionManager: BrowserExtensionActiveManager
    private let logger: iTermLogger
    private let profileObserver: iTermProfilePreferenceObserver
    private let profileMutator: iTermProfilePreferenceMutator
    private let scevents: SCEvents
    private let scDelegate = ListenerDelegate()
    weak var delegate: iTermBrowserExtensionManagerDelegate?

    init(logger: iTermLogger,
         persistentStorageDisallowed: Bool,
         user: iTermBrowserUser,
         hiddenContainer: NSView,
         profileObserver: iTermProfilePreferenceObserver,
         profileMutator: iTermProfilePreferenceMutator) {
        self.logger = logger
        self.profileObserver = profileObserver
        self.profileMutator = profileMutator
        let baseDirectoryPath: String? = profileObserver.value(KEY_BROWSER_EXTENSIONS_ROOT)
        extensionRegistry = BrowserExtensionRegistry(
            baseDirectory: nil,
            logger: logger)
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
        scevents = SCEvents()
        scevents._notificationLatency = 1.0
        scevents._delegate = scDelegate
        scDelegate.callback = { [weak self] event in
            Task {
                self?.updateLoaded()
                await self?.updateActivation()
                self?.refreshSettings()
            }
        }

        Task { [weak self] in
            if let db = await BrowserDatabase.instance(for: user) {
                storageManager.storageProvider = iTermBrowserStorageProvider(
                    database: db)
            }
            self?.root = self?.extensionsDirectory
            self?.updateLoaded()
            await self?.updateActivation()

            profileObserver.observeString(key: KEY_BROWSER_EXTENSIONS_ROOT) { [weak self] _, newValue in
                self?.root = newValue.map { URL(fileURLWithPath: $0) }
            }
            profileObserver.observeStringArray(key: KEY_BROWSER_EXTENSION_ACTIVE_IDS) { [weak self] _, _ in
                Task {
                    await self?.updateActivation()
                    self?.refreshSettings()
                }
            }
        }
    }

    @objc
    class ListenerDelegate: NSObject, SCEventListenerProtocol {
        var callback: ((SCEvent) -> ())?
        func pathWatcher(_ pathWatcher: SCEvents!, eventOccurred event: SCEvent!) {
            callback?(event)
        }
    }

}

@MainActor
@available(macOS 14, *)
extension iTermBrowserExtensionManager: iTermBrowserExtensionManagerProtocol {
    private var root: URL? {
        set {
            scevents.stopWatchingPaths()
            extensionRegistry.set(baseDirectory: newValue)
            Task {
                updateLoaded()
                await updateActivation()
                refreshSettings()
            }
            if let newValue {
                scevents.startWatchingPaths([newValue.path])
            }
        }
        get {
            extensionRegistry.baseDirectory
        }
    }
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

    var availableExtensions: [BrowserExtension] {
        return extensionRegistry.allExtensions
    }

    func extensionEnabled(id: ExtensionID) -> Bool {
        return activeExtensionManager.isActive(id)
    }

    func set(id: ExtensionID, enabled: Bool) {
        var ids: [String] = profileObserver.value(KEY_BROWSER_EXTENSION_ACTIVE_IDS) ?? []
        let idString = id.stringValue
        
        if enabled {
            // Add to active list if not already there
            if !ids.contains(idString) {
                ids.append(idString)
            }
        } else {
            // Remove from active list if present
            if let index = ids.firstIndex(of: idString) {
                ids.remove(at: index)
            }
        }
        
        profileMutator.set(key: KEY_BROWSER_EXTENSION_ACTIVE_IDS, value: ids)
    }

    var extensionsDirectory: URL? {
        let baseDirectoryPath: String? = profileObserver.value(KEY_BROWSER_EXTENSIONS_ROOT)
        return baseDirectoryPath.map { URL(fileURLWithPath: $0) }
    }

    private func directoryNames(in directoryPath: String) -> [String] {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: directoryPath) else {
            return []
        }
        var directories = [String]()
        for item in items {
            let fullPath = (directoryPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    directories.append(item)
                }
            }
        }
        return directories
    }

    private func desiredLoadPaths() -> Set<String> {
        guard let base = extensionRegistry.baseDirectory?.path else {
            return Set()
        }
        return Set(directoryNames(in: base))
    }

    private func desiredIDs() -> Set<ExtensionID> {
        let ids: [String]? = profileObserver.value(KEY_BROWSER_EXTENSION_ACTIVE_IDS)
        if let ids {
            return Set(ids.map { ExtensionID(stringValue: $0) })
        }
        return Set()
    }

    private func updateLoaded() {
        let current = extensionRegistry.extensionPaths
        let desired = desiredLoadPaths()
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
                try extensionRegistry.add(extensionLocation: path)
            } catch {
                logger.debug("Failed to add \(path): \(error)")
            }
        }
    }

    private func updateActivation() async {
        let active = activeExtensionManager.allActiveExtensions()

        let currentIDs = Set(active.values.map { $0.browserExtension.id })
        let desiredIDs = desiredIDs()
        logger.debug("Current IDs: \(Array(currentIDs.map { $0.stringValue }).sorted().joined(separator: "; "))")
        logger.debug("Desired IDs: \(Array(desiredIDs.map { $0.stringValue }).sorted().joined(separator: "; "))")
        let idsToRemove = currentIDs.subtracting(desiredIDs)
        for id in idsToRemove {
            await activeExtensionManager.deactivate(id)
        }

        let toAdd = desiredIDs.subtracting(currentIDs)
        logger.debug("Extension registry contains \(extensionRegistry.extensions.map { "\($0.baseURL.path) with ID \($0.id)" }.joined(separator: "; "))")
        for id in toAdd {
            if let browserExtension = extensionRegistry.extensions.first(where: { $0.id == id }) {
                logger.info("Will activate \(browserExtension.id)")
                await activeExtensionManager.activate(browserExtension)
            } else {
                logger.error("Failed to find extension with id \(id.stringValue)")
            }
        }
    }

    private func refreshSettings() {
        delegate?.extensionManagerDidUpdateExtensions(self)
    }
}

