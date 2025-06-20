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
    
    static func loadTemplate(named templateName: String, substitutions: [String: String] = [:]) -> String {
        guard let path = Bundle.main.path(forResource: templateName, ofType: "html"),
              let template = try? String(contentsOfFile: path) else {
            return generateFallbackHTML(templateName: templateName)
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
        
        // Replace all other {{KEY}} substitutions
        for (key, value) in substitutions {
            let placeholder = "{{\(key)}}"
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
    
    private static func generateFallbackHTML(templateName: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Error</title>
        </head>
        <body>
            <h1>Template Error</h1>
            <p>Could not load template: \(templateName).html</p>
        </body>
        </html>
        """
    }
}
