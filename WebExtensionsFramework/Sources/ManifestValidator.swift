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
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Initialize the validator
    /// - Parameter logger: Logger for debugging and error reporting
    public init(logger: BrowserExtensionLogger) {
        self.logger = logger
    }
    
    /// Validates a manifest and throws an error if invalid
    /// - Parameter manifest: The manifest to validate
    /// - Throws: ManifestValidationError if validation fails
    public func validate(_ manifest: ExtensionManifest) throws {
        try logger.inContext("Validate manifest") {
            logger.debug("Validating manifest version: \(manifest.manifestVersion)")
            try validateManifestVersion(manifest.manifestVersion)
            
            logger.debug("Validating background script configuration")
            try validateBackgroundScript(manifest.background)
            
            logger.debug("Manifest validation completed successfully")
        }
    }
    
    // MARK: - Private validation methods
    
    private func validateManifestVersion(_ version: Int) throws {
        guard version == 3 else {
            logger.error("Invalid manifest version: \(version), expected: 3")
            throw ManifestValidationError.invalidManifestVersion(version)
        }
    }
    
    private func validateBackgroundScript(_ background: BackgroundScript?) throws {
        guard let background = background else {
            logger.debug("No background script to validate")
            return // Background script is optional
        }
        
        // Validate that either service_worker or scripts is specified, but not both
        let hasServiceWorker = background.serviceWorker != nil
        let hasScripts = background.scripts != nil && !background.scripts!.isEmpty
        
        if !hasServiceWorker && !hasScripts {
            logger.error("Background script validation failed: neither service_worker nor scripts specified")
            throw ManifestValidationError.invalidBackgroundScript("Either 'service_worker' or 'scripts' must be specified")
        }
        
        if hasServiceWorker && hasScripts {
            logger.error("Background script validation failed: both service_worker and scripts specified")
            throw ManifestValidationError.backgroundScriptConflict("Cannot specify both 'service_worker' and 'scripts' fields")
        }
        
        // Validate service worker file extension
        if let serviceWorker = background.serviceWorker {
            logger.debug("Validating service worker: \(serviceWorker)")
            if !serviceWorker.hasSuffix(".js") {
                logger.error("Service worker validation failed: \(serviceWorker) is not a .js file")
                throw ManifestValidationError.invalidBackgroundScript("Service worker must be a .js file: \(serviceWorker)")
            }
        }
        
        // Validate scripts array
        if let scripts = background.scripts {
            logger.debug("Validating \(scripts.count) background script(s)")
            for script in scripts {
                if !script.hasSuffix(".js") {
                    logger.error("Background script validation failed: \(script) is not a .js file")
                    throw ManifestValidationError.invalidBackgroundScript("Background script must be a .js file: \(script)")
                }
            }
        }
        
        // Validate type field if present
        if let type = background.type {
            logger.debug("Validating background script type: \(type)")
            if type != "classic" && type != "module" {
                logger.error("Background script type validation failed: \(type) is not valid")
                throw ManifestValidationError.invalidBackgroundScript("Invalid background script type: \(type). Must be 'classic' or 'module'")
            }
        }
    }
}