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
    public let id: UUID
    
    /// Loaded content script resources
    public private(set) var contentScriptResources: [ContentScriptResource] = []
    
    /// Loaded background script resource
    public private(set) var backgroundScriptResource: BackgroundScriptResource?
    
    /// Initialize a browser extension
    /// - Parameters:
    ///   - manifest: The extension's manifest
    ///   - baseURL: Base URL for the extension's files
    public init(manifest: ExtensionManifest, baseURL: URL) {
        self.manifest = manifest
        self.baseURL = baseURL
        self.id = UUID()
    }

    /// Load content scripts from the extension directory
    public func loadContentScripts() throws {
        guard let contentScripts = manifest.contentScripts else {
            contentScriptResources = []
            return
        }
        
        var resources: [ContentScriptResource] = []
        
        for contentScript in contentScripts {
            let resource = try loadContentScriptResource(contentScript)
            resources.append(resource)
        }
        
        contentScriptResources = resources
    }
    
    /// Load background script from the extension directory
    public func loadBackgroundScript() throws {
        guard let background = manifest.background else {
            backgroundScriptResource = nil
            return
        }
        
        backgroundScriptResource = try loadBackgroundScriptResource(background)
    }
    
    /// Load a single content script resource (JS only for now)
    private func loadContentScriptResource(_ contentScript: ContentScript) throws -> ContentScriptResource {
        var jsContent: [String] = []
        
        // Load JavaScript files
        if let jsFiles = contentScript.js {
            for jsFile in jsFiles {
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
            jsContent = try loadFileContent(serviceWorker)
            isServiceWorker = true
        } else if let scripts = background.scripts {
            // Concatenate legacy background scripts
            var combinedScripts: [String] = []
            for script in scripts {
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
        let fileURL = baseURL.appendingPathComponent(relativePath)
        
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return content
        } catch CocoaError.fileReadNoSuchFile {
            throw ContentScriptLoadingError.fileNotFound(relativePath)
        } catch {
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
