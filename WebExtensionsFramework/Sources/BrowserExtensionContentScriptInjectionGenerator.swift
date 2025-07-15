// BrowserExtensionInjectionScript.swift
// Generates injection user scripts that contain all active extensions with JavaScript-based routing

import Foundation
import WebKit
import BrowserExtensionShared

/// Protocol for generating injection user scripts for individual extensions
@MainActor
public protocol BrowserExtensionContentScriptInjectionGeneratorProtocol {
    /// Generate an injection user script for a single extension
    /// - Parameter activeExtension: The active extension to generate a script for
    /// - Returns: JavaScript source code for the extension's injection script
    func generateInjectionScript(for activeExtension: ActiveExtension) -> String
}

/// Generates injection user scripts that handle content script execution for individual extensions
@MainActor
public class BrowserExtensionContentScriptInjectionGenerator: BrowserExtensionContentScriptInjectionGeneratorProtocol {
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Initialize the injection script generator
    /// - Parameter logger: Logger for debugging and error reporting
    public init(logger: BrowserExtensionLogger) {
        self.logger = logger
    }
    
    /// Generate an injection user script for a single extension
    /// - Parameter activeExtension: The active extension to generate a script for
    /// - Returns: JavaScript source code for the extension's injection script
    public func generateInjectionScript(for activeExtension: ActiveExtension) -> String {
        return logger.inContext("Generate injection script for extension \(activeExtension.browserExtension.id)") {
            let extensionId = activeExtension.browserExtension.id
            let contentScriptResources = activeExtension.browserExtension.contentScriptResources
            
            logger.debug("Generating injection script for \(contentScriptResources.count) content script resource(s)")
            var extensionScripts: [[String: Any]] = []
            
            for resource in contentScriptResources {
                let scriptData: [String: Any] = [
                    "id": extensionId.stringValue,
                    "patterns": resource.config.matches,
                    "runAt": resource.config.runAt?.rawValue ?? "document_end",
                    "allFrames": resource.config.allFrames ?? false,
                    "scripts": resource.jsContent
                ]
                extensionScripts.append(scriptData)
            }
            
            let injectionScript = generateInjectionScriptSource(for: extensionId.stringValue, scripts: extensionScripts)
            logger.debug("Generated injection script with \(injectionScript.count) characters")
            return injectionScript
        }
    }
    
    /// Generate the JavaScript source code for a single extension's injection script
    /// - Parameters:
    ///   - extensionId: The ID of the extension
    ///   - scripts: Array of script data for this extension
    /// - Returns: JavaScript source code
    private func generateInjectionScriptSource(for extensionId: String, scripts: [[String: Any]]) -> String {
        let scriptsJSON = try! JSONSerialization.data(withJSONObject: scripts, options: .prettyPrinted)
        let scriptsJSONString = String(data: scriptsJSON, encoding: .utf8)!
        
        return BrowserExtensionTemplateLoader.loadTemplate(
            named: "content-script-injector",
            type: "js",
            substitutions: [
                "EXTENSION_ID": extensionId,
                "SCRIPTS_JSON": scriptsJSONString
            ]
        )
    }
}
