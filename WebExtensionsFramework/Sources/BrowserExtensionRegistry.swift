// BrowserExtensionRegistry.swift
// Registry for managing browser extensions

import Foundation

/// Errors that can occur during extension registry operations
public enum BrowserExtensionRegistryError: Error, LocalizedError {
    case extensionAlreadyExists(String)
    case extensionNotFound(String)
    case invalidExtensionPath(String)
    case manifestLoadError(String, Error)
    case contentScriptLoadError(String, Error)
    
    public var errorDescription: String? {
        switch self {
        case .extensionAlreadyExists(let path):
            return "Extension already exists at path: \(path)"
        case .extensionNotFound(let path):
            return "Extension not found at path: \(path)"
        case .invalidExtensionPath(let path):
            return "Invalid extension path: \(path)"
        case .manifestLoadError(let path, let error):
            return "Failed to load manifest at \(path): \(error.localizedDescription)"
        case .contentScriptLoadError(let path, let error):
            return "Failed to load content scripts at \(path): \(error.localizedDescription)"
        }
    }
}

/// Actor for managing a registry of browser extensions
@MainActor
public class BrowserExtensionRegistry {

    /// Notification posted when the registry changes
    public static let registryDidChangeNotification = Notification.Name("BrowserExtensionRegistryDidChange")
    
    /// Dictionary of extensions keyed by their path
    private var extensionsByPath: [String: BrowserExtension] = [:]
    
    /// Read-only collection of all registered extensions
    public var extensions: [BrowserExtension] {
        Array(extensionsByPath.values)
    }

    /// Read only collection of paths that have been added
    public var extensionPaths: Set<String> {
        Set(extensionsByPath.keys)
    }

    public init() {}
    
    /// Add an extension from the given path
    /// - Parameter extensionPath: Path to the extension directory
    /// - Throws: BrowserExtensionRegistryError if the extension cannot be added
    public func add(extensionPath: String) throws {
        // Check if extension already exists
        if extensionsByPath[extensionPath] != nil {
            throw BrowserExtensionRegistryError.extensionAlreadyExists(extensionPath)
        }
        
        // Validate path exists
        let extensionURL = URL(fileURLWithPath: extensionPath)
        guard FileManager.default.fileExists(atPath: extensionPath) else {
            throw BrowserExtensionRegistryError.invalidExtensionPath(extensionPath)
        }
        
        // Load manifest
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BrowserExtensionRegistryError.invalidExtensionPath("manifest.json not found")
        }
        
        // Load and validate manifest
        let manifest: ExtensionManifest
        do {
            let manifestData = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(ExtensionManifest.self, from: manifestData)
            
            // Validate manifest
            let validator = ManifestValidator()
            try validator.validate(manifest)
        } catch {
            throw BrowserExtensionRegistryError.manifestLoadError(extensionPath, error)
        }
        
        // Create BrowserExtension
        let browserExtension = BrowserExtension(manifest: manifest, baseURL: extensionURL)
        
        // Load content scripts
        do {
            try browserExtension.loadContentScripts()
        } catch {
            throw BrowserExtensionRegistryError.contentScriptLoadError(extensionPath, error)
        }

        // Store in registry
        extensionsByPath[extensionPath] = browserExtension
        
        NotificationCenter.default.post(
            name: Self.registryDidChangeNotification,
            object: self
        )
    }
    
    /// Remove an extension from the registry
    /// - Parameter extensionPath: Path to the extension directory to remove
    /// - Throws: BrowserExtensionRegistryError if the extension cannot be removed
    public func remove(extensionPath: String) throws {
        // Check if extension exists
        guard extensionsByPath[extensionPath] != nil else {
            throw BrowserExtensionRegistryError.extensionNotFound(extensionPath)
        }
        
        // Remove from registry
        extensionsByPath.removeValue(forKey: extensionPath)
        
        NotificationCenter.default.post(
            name: Self.registryDidChangeNotification,
            object: self
        )
    }
}
