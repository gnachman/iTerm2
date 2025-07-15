// BrowserExtension.swift
// Represents a browser extension instance

// TODO: Add CSS content script support when needed

import Foundation

/// Represents a loaded content script resource
public struct ContentScriptResource {
    /// The original content script configuration from manifest
    public let config: ContentScript
    
    /// Loaded JavaScript content (from .js files)
    public let jsContent: [String]
}

/// Represents a loaded background script resource
public struct BackgroundScriptResource {
    /// The original background script configuration from manifest
    public let config: BackgroundScript
    
    /// Loaded JavaScript content (from service worker or scripts)
    public let jsContent: String
    
    /// Whether this is a service worker (true) or legacy background script (false)
    public let isServiceWorker: Bool
}

/// Errors that can occur during content script loading
public enum ContentScriptLoadingError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidContent(String)
    case ioError(String, Error)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Content script file not found: \(path)"
        case .invalidContent(let path):
            return "Invalid content in file: \(path)"
        case .ioError(let path, let error):
            return "IO error reading \(path): \(error.localizedDescription)"
        }
    }
}

/// Represents an instance of a browser extension
@MainActor
public class BrowserExtension {

    /// The extension's manifest
    public let manifest: ExtensionManifest
    
    /// Base URL for the extension's files
    public let baseURL: URL
    
    /// Unique identifier for this extension instance
    public let id: ExtensionID
    
    /// Loaded content script resources
    public var contentScriptResources: [ContentScriptResource] = []
    
    /// Loaded background script resource
    public var backgroundScriptResource: BackgroundScriptResource?
    
    /// Logger for debugging and error reporting
    private let logger: BrowserExtensionLogger

    var mockFilesystem = [String: String]()

    /// Initialize a browser extension
    /// - Parameters:
    ///   - manifest: The extension's manifest
    ///   - baseDirectory: Base directory containing extensions
    ///   - extensionLocation: Relative path to the extension directory
    ///   - logger: Logger for debugging and error reporting
    public init(manifest: ExtensionManifest, baseDirectory: URL, extensionLocation: String, logger: BrowserExtensionLogger) {
        self.manifest = manifest
        self.baseURL = baseDirectory.appendingPathComponent(extensionLocation)
        self.id = ExtensionID(baseDirectory: baseDirectory, extensionLocation: extensionLocation)
        self.logger = logger
    }
    
    /// Initialize a browser extension with a specific ID
    /// - Parameters:
    ///   - id: The extension's unique identifier
    ///   - manifest: The extension's manifest
    ///   - baseURL: Base URL for the extension's files
    ///   - logger: Logger for debugging and error reporting
    public init(id: ExtensionID, manifest: ExtensionManifest, baseURL: URL, logger: BrowserExtensionLogger) {
        self.manifest = manifest
        self.baseURL = baseURL
        self.id = id
        self.logger = logger
    }

    /// Load content scripts from the extension directory
    public func loadContentScripts() throws {
        try logger.inContext("Load content scripts for extension \(id)") {
            guard let contentScripts = manifest.contentScripts else {
                logger.debug("No content scripts defined in manifest")
                contentScriptResources = []
                return
            }
            
            logger.info("Loading \(contentScripts.count) content script(s)")
            var resources: [ContentScriptResource] = []
            
            for contentScript in contentScripts {
                let resource = try loadContentScriptResource(contentScript)
                resources.append(resource)
            }
            
            contentScriptResources = resources
            logger.info("Successfully loaded \(resources.count) content script resource(s)")
        }
    }
    
    /// Load background script from the extension directory
    public func loadBackgroundScript() throws {
        try logger.inContext("Load background script for extension \(id)") {
            guard let background = manifest.background else {
                logger.debug("No background script defined in manifest")
                backgroundScriptResource = nil
                return
            }
            
            logger.info("Loading background script")
            backgroundScriptResource = try loadBackgroundScriptResource(background)
            logger.info("Successfully loaded background script")
        }
    }
    
    /// Load a single content script resource (JS only for now)
    private func loadContentScriptResource(_ contentScript: ContentScript) throws -> ContentScriptResource {
        var jsContent: [String] = []
        
        // Load JavaScript files
        if let jsFiles = contentScript.js {
            logger.debug("Loading \(jsFiles.count) JavaScript file(s) for content script")
            for jsFile in jsFiles {
                logger.debug("Loading JavaScript file: \(jsFile)")
                let content = try loadFileContent(jsFile)
                jsContent.append(content)
            }
        }
        
        return ContentScriptResource(
            config: contentScript,
            jsContent: jsContent
        )
    }
    
    /// Load a single background script resource
    private func loadBackgroundScriptResource(_ background: BackgroundScript) throws -> BackgroundScriptResource {
        var jsContent: String = ""
        var isServiceWorker: Bool = false
        
        if let serviceWorker = background.serviceWorker {
            logger.debug("Loading service worker: \(serviceWorker)")
            jsContent = try loadFileContent(serviceWorker)
            isServiceWorker = true
        } else if let scripts = background.scripts {
            logger.debug("Loading \(scripts.count) legacy background script(s)")
            // Concatenate legacy background scripts
            var combinedScripts: [String] = []
            for script in scripts {
                logger.debug("Loading legacy background script: \(script)")
                let content = try loadFileContent(script)
                combinedScripts.append(content)
            }
            jsContent = combinedScripts.joined(separator: "\n\n")
            isServiceWorker = false
        }
        
        return BackgroundScriptResource(
            config: background,
            jsContent: jsContent,
            isServiceWorker: isServiceWorker
        )
    }
    
    /// Load content from a file relative to the extension's base URL
    private func loadFileContent(_ relativePath: String) throws -> String {
        if let content = mockFilesystem[relativePath] {
            return content
        }
        let fileURL = baseURL.appendingPathComponent(relativePath)
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            logger.debug("Successfully loaded file \(relativePath), size: \(content.count) characters")
            return content
        } catch CocoaError.fileReadNoSuchFile {
            logger.error("File not found: \(relativePath)")
            throw ContentScriptLoadingError.fileNotFound(relativePath)
        } catch {
            logger.error("IO error loading file \(relativePath): \(error)")
            throw ContentScriptLoadingError.ioError(relativePath, error)
        }
    }
    
    // MARK: - Testing Support
    
    /// Set background script resource for testing purposes only
    /// - Parameter resource: The background script resource to set
    internal func setBackgroundScriptResource(_ resource: BackgroundScriptResource?) {
        backgroundScriptResource = resource
    }
}
