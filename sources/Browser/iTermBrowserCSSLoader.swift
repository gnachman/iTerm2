//
//  iTermBrowserCSSLoader.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation

@available(macOS 11.0, *)
@objc(iTermBrowserCSSLoader)
class iTermBrowserCSSLoader: NSObject {
    
    static func loadCommonCSS() -> String {
        guard let path = Bundle.main.path(forResource: "iterm-browser-common", ofType: "css"),
              let cssContent = try? String(contentsOfFile: path) else {
            // Fallback: return basic styles if file can't be loaded
            return """
            :root {
                --bg-color: #ffffff;
                --text-color: #1d1d1f;
                --button-bg: #007aff;
                --button-text: #ffffff;
            }
            @media (prefers-color-scheme: dark) {
                :root {
                    --bg-color: #1c1c1e;
                    --text-color: #ffffff;
                    --button-bg: #0a84ff;
                }
            }
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; background-color: var(--bg-color); color: var(--text-color); padding: 40px 20px; }
            """
        }
        
        return cssContent
    }
}
