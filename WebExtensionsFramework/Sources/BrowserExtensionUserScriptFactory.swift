// BrowserExtensionUserScriptFactory.swift
// Factory for creating WKUserScript objects for content script injection

import Foundation
import WebKit

/// Protocol for creating user scripts for content script injection
@MainActor
public protocol BrowserExtensionUserScriptFactoryProtocol {
    /// Create a WKUserScript with the specified parameters
    /// - Parameters:
    ///   - source: The JavaScript source code to inject
    ///   - injectionTime: When to inject the script
    ///   - forMainFrameOnly: Whether to inject only in the main frame
    ///   - contentWorld: The content world to inject into
    /// - Returns: A configured WKUserScript instance
    func createUserScript(
        source: String,
        injectionTime: WKUserScriptInjectionTime,
        forMainFrameOnly: Bool,
        in contentWorld: WKContentWorld
    ) -> WKUserScript
}

/// Default implementation of user script factory using real WKUserScript
@MainActor
public class BrowserExtensionUserScriptFactory: BrowserExtensionUserScriptFactoryProtocol {
    
    public init() {}
    
    public func createUserScript(
        source: String,
        injectionTime: WKUserScriptInjectionTime,
        forMainFrameOnly: Bool,
        in contentWorld: WKContentWorld
    ) -> WKUserScript {
        return WKUserScript(
            source: source,
            injectionTime: injectionTime,
            forMainFrameOnly: forMainFrameOnly,
            in: contentWorld
        )
    }
}