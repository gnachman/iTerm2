// BrowserExtensionActiveManager.swift
// BrowserExtensionActiveManager.swift
// Manages active extensions and their runtime objects

import BrowserExtensionShared
import Foundation
import WebKit

/// Weak reference wrapper for holding weak references in collections
class WeakBox<T> {
    private weak var _value: AnyObject?
    var value: T? {
        _value as? T
    }
    init(_ value: T?) {
        _value = value as AnyObject?
    }
}

/// Per-webview state tracking
class WebViewState {
    weak var webView: BrowserExtensionWKWebView?

    /// Used to ensure we don't register handlers more than once per world.
    var contentWorldsWithHandlers: Set<String> = []

    init(webView: BrowserExtensionWKWebView) {
        self.webView = webView
    }
}

/// Runtime data for an active extension
@MainActor
public class ActiveExtension {
    /// The extension's static data and manifest
    public let browserExtension: BrowserExtension
    
    /// The content world for this extension's scripts
    public let contentWorld: WKContentWorld
    
    /// When this extension was activated
    public let activatedAt: Date
    
    internal init(browserExtension: BrowserExtension, contentWorld: WKContentWorld) {
        self.browserExtension = browserExtension
        self.contentWorld = contentWorld
        self.activatedAt = Date()
    }
}

/// Protocol for managing active extensions
@MainActor
public protocol BrowserExtensionActiveManagerProtocol {
    /// Activate an extension with its runtime objects
    /// - Parameter browserExtension: The extension to activate
    func activate(_ browserExtension: BrowserExtension) async

    /// Deactivate an extension and clean up its runtime objects
    /// - Parameter extensionId: The unique identifier for the extension
    func deactivate(_ extensionId: UUID) async
    
    /// Get an active extension by ID
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: The active extension if found
    func activeExtension(for extensionId: UUID) -> ActiveExtension?
    
    /// Get all active extensions
    /// - Returns: Dictionary of extension IDs to active extensions
    func allActiveExtensions() -> [UUID: ActiveExtension]
    
    /// Check if an extension is active
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: True if the extension is active
    func isActive(_ extensionId: UUID) -> Bool
    
    /// Deactivate all extensions
    func deactivateAll() async

    /// Register a webview to receive injection script updates
    /// - Parameter webView: The webview to register
    func registerWebView(_ webView: BrowserExtensionWKWebView) async throws
    
    /// Unregister a webview from injection script updates
    /// - Parameter webView: The webview to unregister
    func unregisterWebView(_ webView: BrowserExtensionWKWebView)
}

/// Manages active extensions and their runtime objects
@MainActor
public class BrowserExtensionActiveManager: BrowserExtensionActiveManagerProtocol, BrowserExtensionRouterDataSource {
    
    private var activeExtensions: [UUID: ActiveExtension] = [:]
    private var webViewStates: [ObjectIdentifier: WebViewState] = [:]
    private let injectionScriptGenerator: BrowserExtensionContentScriptInjectionGeneratorProtocol
    private let userScriptFactory: BrowserExtensionUserScriptFactoryProtocol
    private let backgroundService: BrowserExtensionBackgroundServiceProtocol
    private let network: BrowserExtensionNetwork
    private let router: BrowserExtensionRouter
    private let logger: BrowserExtensionLogger
    private let callbackHandler: BrowserExtensionSecureCallbackHandler

    public init(
        injectionScriptGenerator: BrowserExtensionContentScriptInjectionGeneratorProtocol,
        userScriptFactory: BrowserExtensionUserScriptFactoryProtocol,
        backgroundService: BrowserExtensionBackgroundServiceProtocol,
        network: BrowserExtensionNetwork,
        router: BrowserExtensionRouter,
        logger: BrowserExtensionLogger
    ) {
        self.injectionScriptGenerator = injectionScriptGenerator
        self.userScriptFactory = userScriptFactory
        self.backgroundService = backgroundService
        self.network = network
        self.router = router
        self.logger = logger
        callbackHandler = BrowserExtensionSecureCallbackHandler(
            logger: logger,
            function: .invokeCallback)
        // Set ourselves as the data source for the router
        router.dataSource = self
    }
    
    /// Activate an extension with its runtime objects
    /// - Parameter browserExtension: The extension to activate
    public func activate(_ browserExtension: BrowserExtension) async {
        await logger.inContext("Activate extension \(browserExtension.id)") {
            let extensionId = browserExtension.id
            
            // Check if already active
            if activeExtensions[extensionId] != nil {
                logger.fatalError("Extension with ID \(extensionId) is already active")
            }
            
            logger.info("Activating extension with ID: \(extensionId)")
            
            // Create content world for this extension
            let worldName = "Extension-\(extensionId.uuidString)"
            let contentWorld = WKContentWorld.world(name: worldName)
            logger.debug("Created content world: \(worldName)")
            
            // Create active extension
            let activeExtension = ActiveExtension(browserExtension: browserExtension, contentWorld: contentWorld)
            activeExtensions[extensionId] = activeExtension
            
            // Register all existing webviews with the network for this extension
            for state in webViewStates.values {
                if let webView = state.webView {
                    network.add(webView: webView, browserExtension: browserExtension)
                }
            }
            
            // Update injection scripts in all registered webviews
            await updateInjectionScriptsInAllWebViews()
            logger.info("Successfully activated extension with ID: \(extensionId)")

            Task {
                // TODO: In real life we need to track the listeners that background scripts have requested execution for and only launch it unconditionally after install or activate.
                do {
                    try await backgroundService.startBackgroundScript(for: browserExtension)
                } catch {
                    logger.error("Failed to launch background service for \(browserExtension.baseURL.path): \(error)")
                }
            }
        }
    }
    
    /// Deactivate an extension and clean up its runtime objects
    /// - Parameter extensionId: The unique identifier for the extension
    public func deactivate(_ extensionId: UUID) async {
        await logger.inContext("Deactivate extension \(extensionId)") {
            logger.info("Deactivating extension with ID: \(extensionId)")
            activeExtensions.removeValue(forKey: extensionId)
            
            // Update injection scripts in all registered webviews
            await updateInjectionScriptsInAllWebViews()
            logger.info("Successfully deactivated extension with ID: \(extensionId)")
        }
    }
    
    /// Get an active extension by ID
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: The active extension if found
    public func activeExtension(for extensionId: UUID) -> ActiveExtension? {
        return activeExtensions[extensionId]
    }
    
    /// Get all active extensions
    /// - Returns: Dictionary of extension IDs to active extensions
    public func allActiveExtensions() -> [UUID: ActiveExtension] {
        return activeExtensions
    }
    
    /// Check if an extension is active
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: True if the extension is active
    public func isActive(_ extensionId: UUID) -> Bool {
        return activeExtensions[extensionId] != nil
    }
    
    /// Deactivate all extensions
    public func deactivateAll() async {
        activeExtensions.removeAll()
        
        // Update injection scripts in all registered webviews
        await updateInjectionScriptsInAllWebViews()
    }
    
    /// Register a webview to receive injection script updates
    /// - Parameter webView: The webview to register
    public func registerWebView(_ webView: BrowserExtensionWKWebView) async throws {
        await logger.inContext("Register webview \(webView)") {
            logger.debug("Registering webview \(webView) for injection script updates")
            
            // Clean up any deallocated webviews first
            cleanupDeallocatedWebViews()
            
            let id = ObjectIdentifier(webView)
            
            // Create or get webview state
            if webViewStates[id] == nil {
                webViewStates[id] = WebViewState(webView: webView)
            }
            
            // Register webview with network for each active extension
            for activeExtension in activeExtensions.values {
                network.add(webView: webView, browserExtension: activeExtension.browserExtension)
            }
            
            // Install current injection scripts
            logger.debug("About to update injection scripts for webview \(webView)")
            await updateInjectionScriptsInWebView(webView)
            logger.debug("Successfully registered webview with \(activeExtensions.count) active extension(s)")
        }
    }
    
    /// Unregister a webview from injection script updates
    /// - Parameter webView: The webview to unregister
    public func unregisterWebView(_ webView: BrowserExtensionWKWebView) {
        logger.debug("Unregistering webview from injection script updates")
        let id = ObjectIdentifier(webView)
        webViewStates.removeValue(forKey: id)
        
        // Remove webview from network
        network.remove(webView: webView)
    }
    
    // MARK: - Private methods
    
    /// Clean up any deallocated webviews from the registry
    private func cleanupDeallocatedWebViews() {
        let originalKeys = Set(webViewStates.keys)
        webViewStates = webViewStates.compactMapValues { state in
            state.webView != nil ? state : nil
        }
        let remainingKeys = Set(webViewStates.keys)
        let deallocatedKeys = originalKeys.subtracting(remainingKeys)
        
        if !deallocatedKeys.isEmpty {
            logger.debug("Cleaned up \(deallocatedKeys.count) deallocated webview(s)")
        }
    }
    
    /// Update the injection scripts in all registered webviews
    private func updateInjectionScriptsInAllWebViews() async {
        // Clean up any deallocated webviews
        cleanupDeallocatedWebViews()
        
        // Update each webview
        for state in webViewStates.values {
            if let webView = state.webView {
                await updateInjectionScriptsInWebView(webView)
            }
        }
    }
    
    /// Update the injection scripts in a specific webview
    private func updateInjectionScriptsInWebView(_ webView: BrowserExtensionWKWebView) async {
        logger.debug("Updating injection scripts in webview \(webView) for \(activeExtensions.count) active extension(s)")
        
        // Remove all existing user scripts first
        logger.debug("Removing all user scripts from webview \(webView)")
        webView.be_configuration.be_userContentController.be_removeAllUserScripts()
        
        let webViewId = ObjectIdentifier(webView)
        
        // Get or create webview state
        guard let webViewState = webViewStates[webViewId] else {
            logger.error("WebView state not found for webview")
            return
        }
        
        // For each active extension, add message handlers and inject scripts
        for (extensionId, activeExtension) in activeExtensions {
            logger.debug("Installing scripts for extension: \(extensionId)")
            
            // Add message handlers for this extension's content world (if not already added for this webview)
            let contentWorldName = activeExtension.contentWorld.name ?? "unnamed"
            if !webViewState.contentWorldsWithHandlers.contains(contentWorldName) {
                addMessageHandlersToWebView(webView,
                                            contentWorld: activeExtension.contentWorld,
                                            for: activeExtension.browserExtension)
                webViewState.contentWorldsWithHandlers.insert(contentWorldName)
            }
            
            // Inject chrome.runtime APIs JavaScript for this extension
            await injectChromeAPIs(activeExtension.browserExtension,
                                   webView: webView,
                                   contentWorld: activeExtension.contentWorld)

            // Then inject content scripts
            let injectionScriptSource = injectionScriptGenerator.generateInjectionScript(for: activeExtension)
            
            let injectionUserScript = userScriptFactory.createUserScript(
                source: injectionScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: activeExtension.contentWorld
            )
            
            webView.be_configuration.be_userContentController.be_addUserScript(injectionUserScript)
        }
        
        logger.debug("Finished updating injection scripts in webview")
    }
    
    /// Add message handlers to a specific content world for an extension
    private func addMessageHandlersToWebView(_ webView: BrowserExtensionWKWebView,
                                             contentWorld: WKContentWorld,
                                             for browserExtension: BrowserExtension) {
        logger.debug("Registering message handlers for content world: \(contentWorld.name ?? "unnamed")")
        
        // Add message handler for chrome.runtime.* native calls to this content world
        webView.be_configuration.be_userContentController.be_add(
            BrowserExtensionAPIRequestMessageHandler(
                callbackHandler: callbackHandler,
                dispatcher: BrowserExtensionDispatcher(),
                logger: logger,
                contextProvider: { [weak self, weak webView] in
                    guard let self, let webView else {
                        return nil
                    }
                    // TODO: Determine the tab and frame ID.
                    return self.context(for: webView, browserExtension: browserExtension, tab: nil, frameId: nil)
                }
            ),
            name: "requestBrowserExtension",
            contentWorld: contentWorld
        )

        // Add message handler for onMessage listeners to this content world
        webView.be_configuration.be_userContentController.be_add(
            BrowserExtensionListenerResponseHandler(
                router: router,
                logger: logger
            ),
            name: "listenerResponseBrowserExtension",
            contentWorld: contentWorld
        )
    }
    
    /// This is called when JS makes an API call (e.g.,
    /// chrome.runtime.sendMessage) so that the dispatcher can attach the
    /// sender's context when it calls the handler.
    private func context(for webView: BrowserExtensionWKWebView,
                         browserExtension: BrowserExtension,
                         tab: BrowserExtensionContext.MessageSender.Tab?,
                         frameId: Int?) -> BrowserExtensionContext {
        return BrowserExtensionContext(
            logger: logger,
            router: router,
            webView: webView,
            browserExtension: browserExtension,
            tab: tab,
            frameId: frameId
        )
    }
    
    /// Inject chrome.runtime APIs JavaScript for a specific extension
    private func injectChromeAPIs(_ browserExtension: BrowserExtension,
                                  webView: BrowserExtensionWKWebView,
                                  contentWorld: WKContentWorld) async {
        // Generate the JavaScript API code
        let injectionScript = generatedAPIJavascript(.init(extensionId: browserExtension.id.uuidString))

        logger.debug("Injecting Chrome APIs for extension \(browserExtension.id) into webview \(webView) in content world: \(contentWorld.name ?? "unnamed")")
        
        // Create and add the user script for this extension's content world
        let userScript = userScriptFactory.createUserScript(
            source: injectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: contentWorld
        )
        
        webView.be_configuration.be_userContentController.be_addUserScript(userScript)
        logger.debug("Added Chrome API user script to webview \(webView) in content world: \(contentWorld.name ?? "unnamed")")
    }
    
    // MARK: - Test Support Methods
    
    /// Inject chrome.runtime APIs for testing (bypasses normal activation flow)
    /// - Parameters:
    ///   - webView: The webview to inject APIs into
    ///   - browserExtension: The extension to inject APIs for
    ///   - contentWorld: The content world to inject into
    internal func injectRuntimeAPIsForTesting(into webView: BrowserExtensionWKWebView,
                                              for browserExtension: BrowserExtension,
                                              contentWorld: WKContentWorld) async {
        logger.info("Injecting chrome.runtime APIs for testing")
        addMessageHandlersToWebView(webView, contentWorld: contentWorld, for: browserExtension)

        await injectChromeAPIs(browserExtension, webView: webView, contentWorld: contentWorld)
    }
    
    /// Inject only the JavaScript part for testing (without registering handlers)
    internal func injectJavaScriptOnlyForTesting(into webView: BrowserExtensionWKWebView,
                                                 for browserExtension: BrowserExtension,
                                                 contentWorld: WKContentWorld) async {
        logger.info("Injecting chrome.runtime JavaScript for testing")
        await injectChromeAPIs(browserExtension, webView: webView, contentWorld: contentWorld)
    }

    // MARK: - BrowserExtensionRouterDataSource
    
    /// Get the content world for a given extension ID
    public func contentWorld(for extensionId: String) async -> WKContentWorld? {
        logger.debug("ActiveManager asked for content world for extension: \(extensionId)")
        guard let extensionUUID = UUID(uuidString: extensionId),
              let activeExtension = activeExtensions[extensionUUID] else {
            logger.debug("No active extension found for ID: \(extensionId)")
            return nil
        }
        let contentWorld = activeExtension.contentWorld
        logger.debug("ActiveManager returning content world: \(contentWorld.name ?? "unnamed")")
        return contentWorld
    }
}
