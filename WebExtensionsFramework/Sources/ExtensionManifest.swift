// ExtensionManifest.swift
// WebExtensions Manifest V3 data structure

// TODO:
// 1. Deal with comments in manifests
// 2. Implement all remaining fields
// 3. Handle localizable properties (https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Internationalization#internationalizing_manifest.json)

import Foundation

/// When to inject content scripts
public enum ContentScriptRunAt: String, Codable {
    case documentStart = "document_start"
    case documentEnd = "document_end"
    case documentIdle = "document_idle"
}

/// Script execution context
public enum ContentScriptWorld: String, Codable {
    case isolated = "ISOLATED"
    case main = "MAIN"
}

/// Represents a background script configuration
/// Reference: Documentation/manifest-fields/background.md
public struct BackgroundScript: Codable {
    /// Service worker script file (Manifest V3 preferred approach)
    public let serviceWorker: String?
    
    /// Background script files (Manifest V2 compatibility)
    public let scripts: [String]?
    
    /// Whether the background script is persistent (deprecated in V3)
    public let persistent: Bool?
    
    /// Background script type for module loading
    public let type: String?
    
    enum CodingKeys: String, CodingKey {
        case serviceWorker = "service_worker"
        case scripts
        case persistent
        case type
    }
}

/// Represents a content script configuration
/// Reference: Documentation/manifest-fields/content_scripts.md
public struct ContentScript: Codable {
    /// URL patterns where scripts will be injected (required)
    public let matches: [String]
    
    /// JavaScript files to inject
    public let js: [String]?
    
    /// CSS files to inject
    public let css: [String]?
    
    /// When to inject scripts
    public let runAt: ContentScriptRunAt?
    
    /// Whether to inject into all frames
    public let allFrames: Bool?
    
    /// Script execution context
    public let world: ContentScriptWorld?
    
    /// URL patterns to exclude
    public let excludeMatches: [String]?
    
    /// Glob patterns to include
    public let includeGlobs: [String]?
    
    /// Glob patterns to exclude
    public let excludeGlobs: [String]?
    
    /// Whether to inject into about:blank pages
    public let matchAboutBlank: Bool?
    
    /// Whether to inject into opaque origins
    public let matchOriginAsFallback: Bool?
    
    enum CodingKeys: String, CodingKey {
        case matches
        case js
        case css
        case runAt = "run_at"
        case allFrames = "all_frames"
        case world
        case excludeMatches = "exclude_matches"
        case includeGlobs = "include_globs"
        case excludeGlobs = "exclude_globs"
        case matchAboutBlank = "match_about_blank"
        case matchOriginAsFallback = "match_origin_as_fallback"
    }
}

/// Represents a WebExtensions manifest.json file
/// Specification: manifest-v3-spec.md
public struct ExtensionManifest: Codable {
    
    /// Specifies the version of manifest.json used by this extension
    /// Reference: Documentation/manifest-fields/manifest_version.md
    public var manifestVersion: Int
    
    /// Name of the extension
    /// Reference: Documentation/manifest-fields/name.md
    public var name: String
    
    /// Version of the extension
    /// Reference: Documentation/manifest-fields/version.md
    public var version: String
    
    /// Short description of the extension
    /// Reference: Documentation/manifest-fields/description.md
    public var description: String?
    
    /// Content scripts to inject into web pages
    /// Reference: Documentation/manifest-fields/content_scripts.md
    public var contentScripts: [ContentScript]?
    
    /// Background script configuration
    /// Reference: Documentation/manifest-fields/background.md
    public var background: BackgroundScript?
    
    /// Permissions required by the extension
    /// Reference: Documentation/manifest-fields/permissions.md
    public var permissions: [String]?
    
    /// Host permissions required by the extension
    /// Reference: Documentation/manifest-fields/host_permissions.md
    public var hostPermissions: [String]?
    
    /// Optional permissions that can be requested at runtime
    /// Reference: Documentation/manifest-fields/optional_permissions.md
    public var optionalPermissions: [String]?
    
    /// Optional host permissions that can be requested at runtime
    /// Reference: Documentation/manifest-fields/optional_host_permissions.md
    public var optionalHostPermissions: [String]?
    
    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name
        case version
        case description
        case contentScripts = "content_scripts"
        case background
        case permissions
        case hostPermissions = "host_permissions"
        case optionalPermissions = "optional_permissions"
        case optionalHostPermissions = "optional_host_permissions"
    }
}