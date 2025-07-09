import Foundation
import WebKit

/// Factory for creating configured WKWebViews for extension contexts
@MainActor
public class BrowserExtensionWebViewFactory {
    
    public enum WebViewType {
        case backgroundScript  // Service worker context - no DOM, no window interactions
        case popup            // Extension popup UI - interactive, can open windows
        case test             // Clean test environment
    }
    
    /// Configuration for creating extension WebViews
    public struct Configuration {
        public let extensionId: String
        public let logger: BrowserExtensionLogger
        public let urlSchemeHandler: BrowserExtensionURLSchemeHandler
        public let hiddenContainer: NSView
        public let useEphemeralDataStore: Bool
        
        public init(
            extensionId: String,
            logger: BrowserExtensionLogger,
            urlSchemeHandler: BrowserExtensionURLSchemeHandler,
            hiddenContainer: NSView,
            useEphemeralDataStore: Bool = false
        ) {
            self.extensionId = extensionId
            self.logger = logger
            self.urlSchemeHandler = urlSchemeHandler
            self.hiddenContainer = hiddenContainer
            self.useEphemeralDataStore = useEphemeralDataStore
        }
    }
    
    /// Create a configured WKWebView for the specified type
    public static func createWebView(
        type: WebViewType,
        configuration: Configuration
    ) throws -> WKWebView {
        let webViewConfiguration = try createWebViewConfiguration(
            type: type,
            configuration: configuration
        )
        
        let webView = WKWebView(frame: CGRect.zero, configuration: webViewConfiguration)
        
        // Background scripts and test webviews are hidden, popups are visible
        switch type {
        case .backgroundScript, .test:
            webView.isHidden = true
            // Add to hidden container (required for full functionality)
            configuration.hiddenContainer.addSubview(webView)
            webView.frame = configuration.hiddenContainer.bounds
        case .popup:
            webView.isHidden = false
            // Popup webviews will be added to visible UI later
        }
        
        return webView
    }
    
    private static func createWebViewConfiguration(
        type: WebViewType,
        configuration: Configuration
    ) throws -> WKWebViewConfiguration {
        let webViewConfiguration = WKWebViewConfiguration()
        
        // Each extension gets its own process pool for true isolation
        // This prevents cookie/cache/memory sharing between extensions
        webViewConfiguration.processPool = WKProcessPool()
        
        // Configure JavaScript window opening behavior based on type
        switch type {
        case .backgroundScript:
            // Background scripts should not open windows
            webViewConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
        case .popup:
            // Popups are interactive UI and may need to open windows
            webViewConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = true
        case .test:
            // Test environments should not open windows
            webViewConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        
        // Register custom URL scheme handler for isolated origins
        webViewConfiguration.setURLSchemeHandler(
            configuration.urlSchemeHandler,
            forURLScheme: BrowserExtensionURLSchemeHandler.scheme
        )
        
        // Set up data store
        try setupDataStore(webViewConfiguration, configuration: configuration)
        
        // Set up user scripts based on type
        try setupUserScripts(webViewConfiguration, type: type, configuration: configuration)
        
        return webViewConfiguration
    }
    
    private static func setupDataStore(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        if configuration.useEphemeralDataStore {
            // Each extension gets its own ephemeral data store for complete isolation
            webViewConfiguration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            configuration.logger.debug("Using ephemeral data store for extension: \(configuration.extensionId)")
        } else {
            // Create a persistent data store with extension-specific identifier
            // This ensures each extension has completely separate storage
            if #available(macOS 14.0, *) {
                webViewConfiguration.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: configuration.extensionId) ?? UUID())
                configuration.logger.debug("Using persistent data store for extension: \(configuration.extensionId)")
            } else {
                fatalError("Extension storage isolation requires macOS 14.0 or later")
            }
        }
    }
    
    private static func setupUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        type: WebViewType,
        configuration: Configuration
    ) throws {
        switch type {
        case .backgroundScript:
            try setupBackgroundScriptUserScripts(webViewConfiguration, configuration: configuration)
        case .popup:
            try setupPopupUserScripts(webViewConfiguration, configuration: configuration)
        case .test:
            try setupTestUserScripts(webViewConfiguration, configuration: configuration)
        }
    }
    
    private static func setupBackgroundScriptUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        // Background script setup is now handled by BrowserExtensionActiveManager
        // when the webview is registered with role .backgroundScript
    }
    
    private static func setupPopupUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        // Popups are interactive UI - they need access to DOM APIs
    }
    
    private static func setupTestUserScripts(
        _ webViewConfiguration: WKWebViewConfiguration,
        configuration: Configuration
    ) throws {
        // Test scripts need a clean environment without DOM nuke or console override
        // This allows tests to have full control over the environment
    }
}
