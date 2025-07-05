//
//  iTermBrowserUserState.swift
//  iTerm2
//
//  Created by George Nachman on 7/3/25.
//

import WebExtensionsFramework
import WebKit

@objc
class iTermBrowserHiddenContainer: NSView {
    var superviewObserver: ((NSView?) -> ())?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        alphaValue = 0.0
    }
    
    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToSuperview() {
        superviewObserver?(superview)
    }

    override func viewDidMoveToWindow() {
        iTermLogger.instance.debug("Hidden container \(it_addressString) moved to window \(window?.description ?? "(nil)")")
    }
}

@MainActor
class iTermBrowserUserState {
    private static var _instances = [iTermBrowserUser: WeakBox<iTermBrowserUserState>]()
    private let extensionRegistry: BrowserExtensionRegistry?
    private let activeExtensionManager: BrowserExtensionActiveManager?
    private let configuration: Configuration
    private let userDefaultsObserver: iTermUserDefaultsObserver
    let hiddenContainer = iTermBrowserHiddenContainer()
    private let backgroundService: BrowserExtensionBackgroundService?
    let user: iTermBrowserUser
    private let logger = iTermLogger()

    struct Configuration: Equatable {
        var extensionsAllowed = true
        var persistentStorageDisallowed: Bool
    }

    init(_ configuration: Configuration, user: iTermBrowserUser) {
        self.user = user
        self.configuration = configuration
        if #available(macOS 14, *) {
            logger.loggerPrefix = "[Browser] "
            #if DEBUG
            logger.verbosityLevel = .debug
            #endif
            if configuration.extensionsAllowed {
                extensionRegistry = BrowserExtensionRegistry(logger: logger)
                let backgroundService = BrowserExtensionBackgroundService(
                    hiddenContainer: hiddenContainer,
                    logger: logger,
                    useEphemeralDataStore: configuration.persistentStorageDisallowed,
                    urlSchemeHandler: BrowserExtensionURLSchemeHandler(logger: logger))
                self.backgroundService = backgroundService
                activeExtensionManager = BrowserExtensionActiveManager(
                    injectionScriptGenerator: BrowserExtensionInjectionScriptGenerator(logger: logger),
                    userScriptFactory: BrowserExtensionUserScriptFactory(),
                    backgroundService: backgroundService,
                    logger: logger)
            } else {
                extensionRegistry = nil
                activeExtensionManager = nil
                backgroundService = nil
            }
        } else {
            extensionRegistry = nil
            activeExtensionManager = nil
            backgroundService = nil
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

    deinit {
        logger.info("User state for \(user) deallocated")
    }
}

extension iTermBrowserUserState {
    @MainActor
    static func instance(for user: iTermBrowserUser, configuration: Configuration) -> iTermBrowserUserState {
        if let existing = _instances[user]?.value, existing.configuration == configuration {
            return existing
        }
        let state = iTermBrowserUserState(configuration, user: user)
        _instances[user] = .init(state)
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

    private func updateActivation() {
        guard let activeExtensionManager else {
            return
        }
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
                activeExtensionManager.deactivate(id)
            }
        }

        let toAdd = desiredPaths.subtracting(currentPaths)
        logger.debug("Extension registry contains \(extensionRegistry!.extensions.map { "\($0.baseURL.path) with ID \($0.id)" }.joined(separator: "; "))")
        for path in toAdd {
            if let browserExtension = extensionRegistry?.extensions.first(where: { $0.baseURL.path == path }) {
                logger.info("Will activate \(browserExtension.id)")
                activeExtensionManager.activate(browserExtension)
            } else {
                logger.error("Failed to find extension at \(path)")
            }
        }
    }

    public func registerWebView(_ webView: WKWebView) {
        do {
            try activeExtensionManager?.registerWebView(webView)
        } catch {
            logger.error("Failed to register webview: \(error)")
        }
    }

    public func unregisterWebView(_ webView: WKWebView) {
        activeExtensionManager?.unregisterWebView(webView)
    }
}
