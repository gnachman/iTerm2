//
//  iTermBrowserTemplateLoader.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation

@available(macOS 11.0, *)
@objc(iTermBrowserTemplateLoader)
class iTermBrowserTemplateLoader: NSObject {
    static func load(template templateName: String, substitutions: [String: String] = [:]) -> String {
        let base = templateName.deletingPathExtension
        let ext = templateName.pathExtension
        return loadTemplate(named: base, type: ext, substitutions: substitutions)
    }

    static func loadTemplate(named templateName: String,
                             type: String,
                             substitutions: [String: String] = [:]) -> String {
        guard let path = Bundle.main.path(forResource: templateName, ofType: type),
              let template = try? String(contentsOfFile: path) else {
            it_fatalError(templateName)
        }
        
        return performSubstitutions(template: template, substitutions: substitutions)
    }
    
    private static func performSubstitutions(template: String, substitutions: [String: String]) -> String {
        var result = template
        
        // Replace {{COMMON_CSS}} with the actual CSS content
        if result.contains("{{COMMON_CSS}}") {
            let commonCSS = iTermBrowserCSSLoader.loadCommonCSS()
            result = result.replacingOccurrences(of: "{{COMMON_CSS}}", with: commonCSS)
        }
        
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
                    
                    // Load the included file
                    if let includePath = Bundle.main.path(forResource: name, ofType: ext),
                       let includeContent = try? String(contentsOfFile: includePath) {
                        let fullRange = Range(match.range(at: 0), in: result)!
                        result.replaceSubrange(fullRange, with: includeContent)
                    } else {
                        it_fatalError("Could not load included file \(name).\(ext)")
                    }
                }
            }
        }
        
        // Replace all other {{KEY}} substitutions
        for (key, value) in substitutions {
            let placeholder = "{{\(key)}}"
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
}
