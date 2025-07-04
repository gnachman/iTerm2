// BrowserExtensionInjectionScript.swift
// Generates injection user scripts that contain all active extensions with JavaScript-based routing

import Foundation
import WebKit

/// Protocol for generating injection user scripts for individual extensions
@MainActor
public protocol BrowserExtensionInjectionScriptGeneratorProtocol {
    /// Generate an injection user script for a single extension
    /// - Parameter activeExtension: The active extension to generate a script for
    /// - Returns: JavaScript source code for the extension's injection script
    func generateInjectionScript(for activeExtension: ActiveExtension) -> String
}

/// Generates injection user scripts that handle content script execution for individual extensions
@MainActor
public class BrowserExtensionInjectionScriptGenerator: BrowserExtensionInjectionScriptGeneratorProtocol {
    
    public init() {}
    
    /// Generate an injection user script for a single extension
    /// - Parameter activeExtension: The active extension to generate a script for
    /// - Returns: JavaScript source code for the extension's injection script
    public func generateInjectionScript(for activeExtension: ActiveExtension) -> String {
        let extensionId = activeExtension.browserExtension.id
        let contentScriptResources = activeExtension.browserExtension.contentScriptResources
        
        var extensionScripts: [[String: Any]] = []
        
        for resource in contentScriptResources {
            let scriptData: [String: Any] = [
                "id": extensionId.uuidString,
                "patterns": resource.config.matches,
                "runAt": resource.config.runAt?.rawValue ?? "document_end",
                "allFrames": resource.config.allFrames ?? false,
                "scripts": resource.jsContent
            ]
            extensionScripts.append(scriptData)
        }
        
        return generateInjectionScriptSource(for: extensionId.uuidString, scripts: extensionScripts)
    }
    
    /// Generate the JavaScript source code for a single extension's injection script
    /// - Parameters:
    ///   - extensionId: The ID of the extension
    ///   - scripts: Array of script data for this extension
    /// - Returns: JavaScript source code
    private func generateInjectionScriptSource(for extensionId: String, scripts: [[String: Any]]) -> String {
        let scriptsJSON = try! JSONSerialization.data(withJSONObject: scripts, options: .prettyPrinted)
        let scriptsJSONString = String(data: scriptsJSON, encoding: .utf8)!
        
        return """
        // WebExtensions Framework Injection Script for Extension: \(extensionId)
        // This script handles content script injection for a single extension in its isolated content world
        
        (function() {
            'use strict';
            
            const extensionScripts = \(scriptsJSONString);
            const extensionId = '\(extensionId)';
            
            console.log('Extension', extensionId, 'injection script loaded with', extensionScripts.length, 'content scripts');
            
            // URL pattern matching functions
            function matchesPattern(url, pattern) {
                if (pattern === '<all_urls>') {
                    return true;
                }
                
                // Convert extension pattern to regex
                // Basic implementation - would need full pattern matching for production
                const regexPattern = pattern
                    .replace(/\\*/g, '.*')
                    .replace(/\\./g, '\\\\.')
                    .replace(/\\?/g, '\\\\?');
                
                try {
                    const regex = new RegExp('^' + regexPattern + '$');
                    return regex.test(url);
                } catch (e) {
                    console.warn('Extension', extensionId, 'invalid pattern:', pattern, e);
                    return false;
                }
            }
            
            function matchesPatterns(url, patterns) {
                return patterns.some(pattern => matchesPattern(url, pattern));
            }
            
            function shouldExecuteScript(script, currentURL, currentTiming) {
                return matchesPatterns(currentURL, script.patterns) && 
                       script.runAt === currentTiming;
            }
            
            function executeScriptsAtTiming(timing) {
                const currentURL = window.location.href;
                console.log('Extension', extensionId, 'checking scripts for timing:', timing, 'URL:', currentURL);
                
                extensionScripts.forEach(script => {
                    if (shouldExecuteScript(script, currentURL, timing)) {
                        console.log('Extension', extensionId, 'executing script at', timing);
                        
                        script.scripts.forEach((scriptCode, index) => {
                            try {
                                // Execute the script in a function to provide some isolation
                                const scriptFunction = new Function(scriptCode);
                                scriptFunction();
                            } catch (error) {
                                console.error('Extension', extensionId, 'error executing script', index, ':', error);
                            }
                        });
                    }
                });
            }
            
            // Execute document_start scripts immediately if document is still loading
            if (document.readyState === 'loading') {
                executeScriptsAtTiming('document_start');
            }
            
            // Set up listeners for document_end and document_idle
            function onDOMContentLoaded() {
                executeScriptsAtTiming('document_end');
                
                // document_idle typically fires after DOMContentLoaded when the page is "idle"
                // For simplicity, we'll execute it shortly after document_end
                setTimeout(() => {
                    executeScriptsAtTiming('document_idle');
                }, 100);
            }
            
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', onDOMContentLoaded);
            } else {
                // Document already loaded, execute document_end/idle scripts immediately
                onDOMContentLoaded();
            }
            
        })();
        """
    }
}
