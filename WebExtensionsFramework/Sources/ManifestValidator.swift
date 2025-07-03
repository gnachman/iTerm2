// ManifestValidator.swift
// Validates WebExtensions manifest data

import Foundation

/// Errors that can occur during manifest validation
public enum ManifestValidationError: Error, Equatable {
    case invalidManifestVersion(Int)
}

/// Validates WebExtensions manifest data
public class ManifestValidator {
    
    public init() {}
    
    /// Validates a manifest and throws an error if invalid
    /// - Parameter manifest: The manifest to validate
    /// - Throws: ManifestValidationError if validation fails
    public func validate(_ manifest: ExtensionManifest) throws {
        try validateManifestVersion(manifest.manifestVersion)
    }
    
    // MARK: - Private validation methods
    
    private func validateManifestVersion(_ version: Int) throws {
        guard version == 3 else {
            throw ManifestValidationError.invalidManifestVersion(version)
        }
    }
}