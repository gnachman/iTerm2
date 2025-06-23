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
        
        // Replace all other {{KEY}} substitutions
        for (key, value) in substitutions {
            let placeholder = "{{\(key)}}"
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
}
