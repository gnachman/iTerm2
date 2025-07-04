// ManifestValidator.swift
// Validates WebExtensions manifest data

import Foundation

/// Errors that can occur during manifest validation
public enum ManifestValidationError: Error, Equatable {
    case invalidManifestVersion(Int)
    case invalidBackgroundScript(String)
    case backgroundScriptConflict(String)
}

/// Validates WebExtensions manifest data
public class ManifestValidator {
    
    public init() {}
    
    /// Validates a manifest and throws an error if invalid
    /// - Parameter manifest: The manifest to validate
    /// - Throws: ManifestValidationError if validation fails
    public func validate(_ manifest: ExtensionManifest) throws {
        try validateManifestVersion(manifest.manifestVersion)
        try validateBackgroundScript(manifest.background)
    }
    
    // MARK: - Private validation methods
    
    private func validateManifestVersion(_ version: Int) throws {
        guard version == 3 else {
            throw ManifestValidationError.invalidManifestVersion(version)
        }
    }
    
    private func validateBackgroundScript(_ background: BackgroundScript?) throws {
        guard let background = background else {
            return // Background script is optional
        }
        
        // Validate that either service_worker or scripts is specified, but not both
        let hasServiceWorker = background.serviceWorker != nil
        let hasScripts = background.scripts != nil && !background.scripts!.isEmpty
        
        if !hasServiceWorker && !hasScripts {
            throw ManifestValidationError.invalidBackgroundScript("Either 'service_worker' or 'scripts' must be specified")
        }
        
        if hasServiceWorker && hasScripts {
            throw ManifestValidationError.backgroundScriptConflict("Cannot specify both 'service_worker' and 'scripts' fields")
        }
        
        // Validate service worker file extension
        if let serviceWorker = background.serviceWorker {
            if !serviceWorker.hasSuffix(".js") {
                throw ManifestValidationError.invalidBackgroundScript("Service worker must be a .js file: \(serviceWorker)")
            }
        }
        
        // Validate scripts array
        if let scripts = background.scripts {
            for script in scripts {
                if !script.hasSuffix(".js") {
                    throw ManifestValidationError.invalidBackgroundScript("Background script must be a .js file: \(script)")
                }
            }
        }
        
        // Validate type field if present
        if let type = background.type {
            if type != "classic" && type != "module" {
                throw ManifestValidationError.invalidBackgroundScript("Invalid background script type: \(type). Must be 'classic' or 'module'")
            }
        }
    }
}