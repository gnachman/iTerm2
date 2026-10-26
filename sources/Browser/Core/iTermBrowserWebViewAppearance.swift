//
//  iTermBrowserWebViewAppearance.swift
//  iTerm2
//

import AppKit

// In the Minimal theme a session view takes a light or dark appearance from its
// background color, which for a browser session is the page's own background.
// A web view inheriting that appearance would render a page that supports both
// color schemes in its dark variant after visiting a dark page, and that page's
// dark background would keep the session dark: a feedback loop. So in the
// Minimal theme the web view follows the app's appearance instead.
@objc(iTermBrowserWebViewAppearance)
final class iTermBrowserWebViewAppearance: NSObject {
    @objc(updateWebView:minimalTheme:appAppearance:)
    static func update(webView: NSView?, minimalTheme: Bool, appAppearance: NSAppearance) {
        guard let webView else {
            return
        }
        // The app's appearance as is, so a high-contrast setting carries over.
        let desired: NSAppearance? = minimalTheme ? appAppearance : nil
        if webView.appearance?.name == desired?.name {
            return
        }
        DLog("Set browser web view appearance to \(desired?.name.rawValue ?? "inherited")")
        webView.appearance = desired
    }
}
