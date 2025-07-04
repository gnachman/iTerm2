// BrowserExtensionActiveManager.swift
// BrowserExtensionActiveManager.swift
// Manages active extensions and their runtime objects

import Foundation
import WebKit

/// Weak reference wrapper for holding weak references in collections
private class WeakBox<T> {
    private weak var _value: AnyObject?
    var value: T? {
        _value as? T
    }
    init(_ value: T?) {
        _value = value as AnyObject?
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
    func activate(_ browserExtension: BrowserExtension)
    
    /// Deactivate an extension and clean up its runtime objects
    /// - Parameter extensionId: The unique identifier for the extension
    func deactivate(_ extensionId: UUID)
    
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
    func deactivateAll()
    
    /// Register a webview to receive injection script updates
    /// - Parameter webView: The webview to register
    func registerWebView(_ webView: BrowserExtensionWKWebView) throws
    
    /// Unregister a webview from injection script updates
    /// - Parameter webView: The webview to unregister
    func unregisterWebView(_ webView: BrowserExtensionWKWebView)
}

/// Manages active extensions and their runtime objects
@MainActor
public class BrowserExtensionActiveManager: BrowserExtensionActiveManagerProtocol {
    
    private var activeExtensions: [UUID: ActiveExtension] = [:]
    private var registeredWebViews: [ObjectIdentifier: WeakBox<BrowserExtensionWKWebView>] = [:]
    private let injectionScriptGenerator: BrowserExtensionInjectionScriptGeneratorProtocol
    private let userScriptFactory: BrowserExtensionUserScriptFactoryProtocol
    private let backgroundService: BrowserExtensionBackgroundServiceProtocol
    private let logger: BrowserExtensionLogger

    public init(
        injectionScriptGenerator: BrowserExtensionInjectionScriptGeneratorProtocol,
        userScriptFactory: BrowserExtensionUserScriptFactoryProtocol,
        backgroundService: BrowserExtensionBackgroundServiceProtocol,
        logger: BrowserExtensionLogger
    ) {
        self.injectionScriptGenerator = injectionScriptGenerator
        self.userScriptFactory = userScriptFactory
        self.backgroundService = backgroundService
        self.logger = logger
    }
    
    /// Activate an extension with its runtime objects
    /// - Parameter browserExtension: The extension to activate
    public func activate(_ browserExtension: BrowserExtension) {
        logger.inContext("Activate extension \(browserExtension.id)") {
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
            
            // Update injection scripts in all registered webviews
            updateInjectionScriptsInAllWebViews()
            logger.info("Successfully activated extension with ID: \(extensionId)")
        }
    }
    
    /// Deactivate an extension and clean up its runtime objects
    /// - Parameter extensionId: The unique identifier for the extension
    public func deactivate(_ extensionId: UUID) {
        logger.inContext("Deactivate extension \(extensionId)") {
            logger.info("Deactivating extension with ID: \(extensionId)")
            activeExtensions.removeValue(forKey: extensionId)
            
            // Update injection scripts in all registered webviews
            updateInjectionScriptsInAllWebViews()
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
    public func deactivateAll() {
        activeExtensions.removeAll()
        
        // Update injection scripts in all registered webviews
        updateInjectionScriptsInAllWebViews()
    }
    
    /// Register a webview to receive injection script updates
    /// - Parameter webView: The webview to register
    public func registerWebView(_ webView: BrowserExtensionWKWebView) throws {
        logger.inContext("Register webview") {
            logger.debug("Registering webview for injection script updates")
            
            // Clean up any deallocated webviews first
            cleanupDeallocatedWebViews()
            
            let id = ObjectIdentifier(webView)
            registeredWebViews[id] = WeakBox(webView)
            
            // Install current injection scripts
            updateInjectionScriptsInWebView(webView)
            logger.debug("Successfully registered webview with \(activeExtensions.count) active extension(s)")
        }
    }
    
    /// Unregister a webview from injection script updates
    /// - Parameter webView: The webview to unregister
    public func unregisterWebView(_ webView: BrowserExtensionWKWebView) {
        logger.debug("Unregistering webview from injection script updates")
        let id = ObjectIdentifier(webView)
        registeredWebViews.removeValue(forKey: id)
    }
    
    // MARK: - Private methods
    
    /// Clean up any deallocated webviews from the registry
    private func cleanupDeallocatedWebViews() {
        registeredWebViews = registeredWebViews.compactMapValues { box in
            box.value != nil ? box : nil
        }
    }
    
    /// Update the injection scripts in all registered webviews
    private func updateInjectionScriptsInAllWebViews() {
        // Clean up any deallocated webviews
        cleanupDeallocatedWebViews()
        
        // Update each webview
        for box in registeredWebViews.values {
            if let webView = box.value {
                updateInjectionScriptsInWebView(webView)
            }
        }
    }
    
    /// Update the injection scripts in a specific webview
    private func updateInjectionScriptsInWebView(_ webView: BrowserExtensionWKWebView) {
        logger.debug("Updating injection scripts in webview for \(activeExtensions.count) active extension(s)")
        
        // Remove all existing user scripts first
        webView.be_configuration.be_userContentController.be_removeAllUserScripts()
        
        // Generate and install a separate injection script for each active extension
        for (extensionId, activeExtension) in activeExtensions {
            logger.debug("Installing injection script for extension: \(extensionId)")
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
}
