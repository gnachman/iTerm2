//
//  BrowserExtensionTemplateLoader.swift
//  WebExtensionsFramework
//

import Foundation

@available(macOS 11.0, *)
public class BrowserExtensionTemplateLoader {
    public static func load(template templateName: String, substitutions: [String: String] = [:]) -> String {
        let nsString = templateName as NSString
        let base = nsString.deletingPathExtension
        let ext = nsString.pathExtension
        return loadTemplate(named: base, type: ext, substitutions: substitutions)
    }

    public static func loadTemplate(named templateName: String,
                                    type: String,
                                    substitutions: [String: String] = [:]) -> String {
        // For SPM, try to find the resources by looking in the project directory
        // This handles both runtime and testing scenarios
        var resourcePath: String?
        
        // Strategy 1: Look for the resources in bundle
        var resourceBundle: Bundle?
        for bundle in Bundle.allBundles {
            if bundle.path(forResource: "dom-nuke", ofType: "js", inDirectory: "Resources/JavaScript") != nil {
                resourceBundle = bundle
                break
            }
        }
        
        // Strategy 2: Direct file path lookup (for development/testing)
        if resourceBundle == nil {
            // Find the project root by looking for Package.swift
            var currentDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
            while currentDir.path != "/" {
                let packageSwiftPath = currentDir.appendingPathComponent("Package.swift")
                if FileManager.default.fileExists(atPath: packageSwiftPath.path) {
                    let resourcesPath = currentDir.appendingPathComponent("Resources/JavaScript/\(templateName).\(type)")
                    if FileManager.default.fileExists(atPath: resourcesPath.path) {
                        resourcePath = resourcesPath.path
                        break
                    }
                }
                currentDir = currentDir.deletingLastPathComponent()
            }
        }
        
        // If we found a bundle, use it
        if let bundle = resourceBundle {
            var bundlePath: String?
            bundlePath = bundle.path(forResource: templateName, ofType: type, inDirectory: "Resources/JavaScript")
            if bundlePath == nil {
                bundlePath = bundle.path(forResource: templateName, ofType: type, inDirectory: "JavaScript")
            }
            if bundlePath == nil {
                bundlePath = bundle.path(forResource: templateName, ofType: type)
            }
            resourcePath = bundlePath
        }
        
        // Debug: Print resource information (simplified) - Remove this for production
        // print("Resource loaded: \(templateName).\(type) from \(resourcePath ?? "nil")")
        
        // Load the template from the discovered resource path
        guard let finalPath = resourcePath,
              let template = try? String(contentsOfFile: finalPath) else {
            // Debug: List all resources in bundle
            if let bundle = resourceBundle, let bundleResourcePath = bundle.resourcePath {
                print("Resources in bundle:")
                let contents = try? FileManager.default.contentsOfDirectory(atPath: bundleResourcePath)
                print(contents ?? [])
            }
            fatalError("Failed to load template: \(templateName).\(type)")
        }
        
        return performSubstitutions(template: template, substitutions: substitutions, resourceBundle: resourceBundle)
    }
    
    private static func performSubstitutions(template: String, substitutions: [String: String], resourceBundle: Bundle? = nil) -> String {
        var result = template
        
        // Handle {{INCLUDE:filename}} patterns
        let includePattern = "\\{\\{INCLUDE:([^}]+)\\}\\}"
        let regex = try! NSRegularExpression(pattern: includePattern)
        let range = NSRange(location: 0, length: result.utf16.count)
        
        // Find all include matches and replace them
        let matches = regex.matches(in: result, range: range).reversed() // Reverse to avoid index issues
        for match in matches {
            if let filenameRange = Range(match.range(at: 1), in: result) {
                let filename = String(result[filenameRange])
                
                // Extract name and extension from filename
                let components = filename.split(separator: ".")
                if components.count >= 2 {
                    let name = String(components.dropLast().joined(separator: "."))
                    let ext = String(components.last!)
                    
                    // Load the included file using the same approach
                    var includeContent: String?
                    
                    // Try bundle first
                    if let bundle = resourceBundle {
                        var includePath = bundle.path(forResource: name, ofType: ext, inDirectory: "Resources/JavaScript")
                        if includePath == nil {
                            includePath = bundle.path(forResource: name, ofType: ext, inDirectory: "JavaScript")
                        }
                        if let path = includePath {
                            includeContent = try? String(contentsOfFile: path)
                        }
                    }
                    
                    // Try direct file path
                    if includeContent == nil {
                        var currentDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
                        while currentDir.path != "/" {
                            let packageSwiftPath = currentDir.appendingPathComponent("Package.swift")
                            if FileManager.default.fileExists(atPath: packageSwiftPath.path) {
                                let resourcesPath = currentDir.appendingPathComponent("Resources/JavaScript/\(name).\(ext)")
                                if FileManager.default.fileExists(atPath: resourcesPath.path) {
                                    includeContent = try? String(contentsOfFile: resourcesPath.path)
                                    break
                                }
                            }
                            currentDir = currentDir.deletingLastPathComponent()
                        }
                    }
                    
                    if let content = includeContent {
                        let fullRange = Range(match.range(at: 0), in: result)!
                        result.replaceSubrange(fullRange, with: content)
                    }
                }
            }
        }
        
        // Replace all {{KEY}} substitutions
        for (key, value) in substitutions {
            let placeholder = "{{\(key)}}"
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
}