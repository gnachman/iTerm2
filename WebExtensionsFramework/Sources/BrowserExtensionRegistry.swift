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
    case backgroundScriptLoadError(String, Error)

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
        case .backgroundScriptLoadError(let path, let error):
            return "Failed to load background scripts at \(path): \(error.localizedDescription)"
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
    
    /// Base directory containing all extensions
    private(set) public var baseDirectory: URL?

    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger
    
    /// Read-only collection of all registered extensions
    public var extensions: [BrowserExtension] {
        Array(extensionsByPath.values)
    }

    /// Read only collection of paths that have been added
    public var extensionPaths: Set<String> {
        Set(extensionsByPath.keys)
    }

    /// Initialize the registry
    /// - Parameters:
    ///   - baseDirectory: The base directory containing all extensions
    ///   - logger: Logger for debugging and error reporting
    public init(baseDirectory: URL?, logger: BrowserExtensionLogger) {
        self.baseDirectory = baseDirectory
        self.logger = logger
    }

    /// Change the base directory
    public func set(baseDirectory: URL?) {
        logger.info("Will set base directory to \(baseDirectory?.path ?? "(nil)"). Unloading all extensions.")
        self.baseDirectory = baseDirectory
        extensionsByPath.removeAll()
        NotificationCenter.default.post(
            name: Self.registryDidChangeNotification,
            object: self
        )
    }

    /// Add an extension from the given relative location
    /// - Parameter extensionLocation: Relative path to the extension directory within the base directory
    /// - Throws: BrowserExtensionRegistryError if the extension cannot be added
    public func add(extensionLocation: String) throws {
        guard let baseDirectory else {
            throw BrowserExtensionRegistryError.extensionNotFound("No base directory specified")
        }
        let extensionURL = baseDirectory.appendingPathComponent(extensionLocation)
        let extensionPath = extensionURL.path
        
        try logger.inContext("Add extension from location \(extensionLocation)") {
            // Check if extension already exists
            if extensionsByPath[extensionPath] != nil {
                logger.error("Extension already exists at path: \(extensionPath)")
                throw BrowserExtensionRegistryError.extensionAlreadyExists(extensionPath)
            }
            
            logger.info("Adding extension from location: \(extensionLocation) (full path: \(extensionPath))")
            
            // Validate path exists
            guard FileManager.default.fileExists(atPath: extensionPath) else {
                logger.error("Extension path does not exist: \(extensionPath)")
                throw BrowserExtensionRegistryError.invalidExtensionPath(extensionPath)
            }
            
            // Load manifest
            let manifestURL = extensionURL.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                logger.error("manifest.json not found at: \(manifestURL.path)")
                throw BrowserExtensionRegistryError.invalidExtensionPath("manifest.json not found")
            }
            
            // Load and validate manifest
            let manifest: ExtensionManifest
            do {
                logger.debug("Loading manifest from: \(manifestURL.path)")
                let manifestData = try Data(contentsOf: manifestURL)
                manifest = try JSONDecoder().decode(ExtensionManifest.self, from: manifestData)
                
                // Validate manifest
                logger.debug("Validating manifest")
                let validator = ManifestValidator(logger: logger)
                try validator.validate(manifest)
                logger.debug("Manifest validation successful")
            } catch {
                logger.error("Failed to load/validate manifest: \(error)")
                throw BrowserExtensionRegistryError.manifestLoadError(extensionPath, error)
            }
            
            // Create BrowserExtension
            let browserExtension = BrowserExtension(manifest: manifest, baseDirectory: baseDirectory, extensionLocation: extensionLocation, logger: logger)
            
            // Load content scripts
            do {
                try browserExtension.loadContentScripts()
            } catch {
                logger.error("Failed to load content scripts: \(error)")
                throw BrowserExtensionRegistryError.contentScriptLoadError(extensionPath, error)
            }

            do {
                try browserExtension.loadBackgroundScript()
            } catch {
                logger.error("Failed to load background scripts: \(error)")
                throw BrowserExtensionRegistryError.backgroundScriptLoadError(extensionPath, error)
            }
            // Store in registry
            extensionsByPath[extensionPath] = browserExtension
            logger.info("Successfully added extension with ID: \(browserExtension.id)")
            
            NotificationCenter.default.post(
                name: Self.registryDidChangeNotification,
                object: self
            )
        }
    }
    
    /// Remove an extension from the registry
    /// - Parameter extensionPath: Path to the extension directory to remove
    /// - Throws: BrowserExtensionRegistryError if the extension cannot be removed
    public func remove(extensionPath: String) throws {
        try logger.inContext("Remove extension from path \(extensionPath)") {
            // Check if extension exists
            guard let browserExtension = extensionsByPath[extensionPath] else {
                logger.error("Extension not found at path: \(extensionPath)")
                throw BrowserExtensionRegistryError.extensionNotFound(extensionPath)
            }
            
            logger.info("Removing extension with ID: \(browserExtension.id)")
            
            // Remove from registry
            extensionsByPath.removeValue(forKey: extensionPath)
            logger.info("Successfully removed extension from registry")
            
            NotificationCenter.default.post(
                name: Self.registryDidChangeNotification,
                object: self
            )
        }
    }

    public var allExtensions: [BrowserExtension] {
        return Array(extensionsByPath.values)
    }
}
