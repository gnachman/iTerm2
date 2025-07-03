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
    /// - Throws: BrowserExtensionRegistryError if activation fails
    func activate(_ browserExtension: BrowserExtension) throws
    
    /// Deactivate an extension and clean up its runtime objects
    /// - Parameter extensionId: The unique identifier for the extension
    func deactivate(_ extensionId: String)
    
    /// Get an active extension by ID
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: The active extension if found
    func activeExtension(for extensionId: String) -> ActiveExtension?
    
    /// Get all active extensions
    /// - Returns: Dictionary of extension IDs to active extensions
    func allActiveExtensions() -> [String: ActiveExtension]
    
    /// Check if an extension is active
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: True if the extension is active
    func isActive(_ extensionId: String) -> Bool
    
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
    
    private var activeExtensions: [String: ActiveExtension] = [:]
    private var registeredWebViews: [ObjectIdentifier: WeakBox<BrowserExtensionWKWebView>] = [:]
    private let injectionScriptGenerator: BrowserExtensionInjectionScriptGeneratorProtocol
    private let userScriptFactory: BrowserExtensionUserScriptFactoryProtocol

    public init(
        injectionScriptGenerator: BrowserExtensionInjectionScriptGeneratorProtocol,
        userScriptFactory: BrowserExtensionUserScriptFactoryProtocol
    ) {
        self.injectionScriptGenerator = injectionScriptGenerator
        self.userScriptFactory = userScriptFactory
    }
    
    public convenience init() {
        self.init(
            injectionScriptGenerator: BrowserExtensionInjectionScriptGenerator(),
            userScriptFactory: BrowserExtensionUserScriptFactory()
        )
    }
    
    /// Activate an extension with its runtime objects
    /// - Parameter browserExtension: The extension to activate
    /// - Throws: BrowserExtensionRegistryError if activation fails
    public func activate(_ browserExtension: BrowserExtension) throws {
        let extensionId = browserExtension.id
        
        // Check if already active
        if activeExtensions[extensionId] != nil {
            throw BrowserExtensionRegistryError.extensionAlreadyExists(extensionId)
        }
        
        // Create content world for this extension
        let worldName = "Extension-\(extensionId)"
        let contentWorld = WKContentWorld.world(name: worldName)
        
        // Create active extension
        let activeExtension = ActiveExtension(browserExtension: browserExtension, contentWorld: contentWorld)
        activeExtensions[extensionId] = activeExtension
        
        // Update injection scripts in all registered webviews
        updateInjectionScriptsInAllWebViews()
    }
    
    /// Deactivate an extension and clean up its runtime objects
    /// - Parameter extensionId: The unique identifier for the extension
    public func deactivate(_ extensionId: String) {
        activeExtensions.removeValue(forKey: extensionId)
        
        // Update injection scripts in all registered webviews
        updateInjectionScriptsInAllWebViews()
    }
    
    /// Get an active extension by ID
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: The active extension if found
    public func activeExtension(for extensionId: String) -> ActiveExtension? {
        return activeExtensions[extensionId]
    }
    
    /// Get all active extensions
    /// - Returns: Dictionary of extension IDs to active extensions
    public func allActiveExtensions() -> [String: ActiveExtension] {
        return activeExtensions
    }
    
    /// Check if an extension is active
    /// - Parameter extensionId: The unique identifier for the extension
    /// - Returns: True if the extension is active
    public func isActive(_ extensionId: String) -> Bool {
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
        // Clean up any deallocated webviews first
        cleanupDeallocatedWebViews()
        
        let id = ObjectIdentifier(webView)
        registeredWebViews[id] = WeakBox(webView)
        
        // Install current injection scripts
        updateInjectionScriptsInWebView(webView)
    }
    
    /// Unregister a webview from injection script updates
    /// - Parameter webView: The webview to unregister
    public func unregisterWebView(_ webView: BrowserExtensionWKWebView) {
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
        // Remove all existing user scripts first
        webView.be_configuration.be_userContentController.be_removeAllUserScripts()
        
        // Generate and install a separate injection script for each active extension
        for (_, activeExtension) in activeExtensions {
            let injectionScriptSource = injectionScriptGenerator.generateInjectionScript(for: activeExtension)
            
            let injectionUserScript = userScriptFactory.createUserScript(
                source: injectionScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: activeExtension.contentWorld
            )
            
            webView.be_configuration.be_userContentController.be_addUserScript(injectionUserScript)
        }
    }
}
