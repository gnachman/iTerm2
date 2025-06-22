//
//  iTermBrowserErrorHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/18/25.
//

import Foundation
@preconcurrency import WebKit

@available(macOS 11.0, *)
@objc(iTermBrowserErrorHandler)
class iTermBrowserErrorHandler: NSObject, iTermBrowserPageHandler {
    private var pendingErrorHTML: String?
    
    static let errorURL = URL(string: "iterm2-about:error")!
    
    // MARK: - Public Interface
    
    func generateErrorPageHTML(for error: Error, failedURL: URL?) -> String {
        let (title, message) = errorTitleAndMessage(for: error)
        return generateErrorHTML(title: title, message: message, originalURL: failedURL?.absoluteString)
    }
    
    func setPendingErrorHTML(_ html: String) {
        pendingErrorHTML = html
    }
    
    func consumePendingErrorHTML() -> String? {
        let html = pendingErrorHTML
        pendingErrorHTML = nil
        return html
    }
    
    func hasPendingError() -> Bool {
        return pendingErrorHTML != nil
    }
    
    func clearPendingError() {
        pendingErrorHTML = nil
    }
    
    // MARK: - iTermBrowserPageHandler Protocol
    
    func injectJavaScript(into webView: WKWebView) {
        // Error pages don't need JavaScript injection
    }
    
    func resetState() {
        clearPendingError()
    }

    func start(urlSchemeTask: WKURLSchemeTask, url: URL) {
        // Serve our error page HTML
        let htmlToServe = consumePendingErrorHTML() ?? generateErrorPageHTML(
            for: NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "Page Not Available"]),
            failedURL: nil
        )

        guard let data = htmlToServe.data(using: .utf8) else {
            urlSchemeTask.didFailWithError(NSError(domain: "iTermBrowserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HTML"]))
            return
        }

        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    // MARK: - Error Page Generation
    
    private func generateErrorHTML(title: String, message: String, originalURL: String?) -> String {
        let urlDisplay = originalURL ?? ""
        let urlDisplayHTML = urlDisplay.isEmpty ? "" : "<div class=\"error-url\">\(urlDisplay)</div>"
        
        let substitutions = [
            "TITLE": title,
            "MESSAGE": message,
            "URL_DISPLAY": urlDisplayHTML,
            "ORIGINAL_URL": originalURL ?? ""
        ]
        
        return iTermBrowserTemplateLoader.loadTemplate(named: "error-page",
                                                       type: "html",
                                                       substitutions: substitutions)
    }
    
    private func errorTitleAndMessage(for error: Error) -> (title: String, message: String) {
        let nsError = error as NSError
        
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return ("No Internet Connection", "Your computer appears to be offline. Check your internet connection and try again.")
            
        case NSURLErrorCannotFindHost:
            return ("Server Not Found", "iTerm2 can’t find the server. Check that the web address is correct and try again.")

        case NSURLErrorTimedOut:
            return ("The Connection Timed Out", "The server didn’t respond in time. The site may be temporarily unavailable or overloaded.")

        case NSURLErrorCannotConnectToHost:
            return ("Can’t Connect to Server", "iTerm2 can’t establish a secure connection to the server. The server may be down or unreachable.")

        case NSURLErrorNetworkConnectionLost:
            return ("Network Connection Lost", "The network connection was lost. Check your internet connection and try again.")
            
        case NSURLErrorDNSLookupFailed:
            return ("Server Not Found", "The server’s DNS address could not be found. Check that the web address is correct.")

        case NSURLErrorHTTPTooManyRedirects:
            return ("Too Many Redirects", "iTerm2 can’t open the page because the server redirected too many times.")

        case NSURLErrorResourceUnavailable:
            return ("Page Unavailable", "The requested page is currently unavailable. Try again later.")
            
        case NSURLErrorNotConnectedToInternet:
            return ("No Internet Connection", "Your computer is not connected to the internet. Check your connection and try again.")
            
        case NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed:
            return ("Secure Connection Failed", "iTerm2 can’t verify the identity of the website. The connection may not be secure.")

        default:
            return ("Page Can’t Be Loaded", "An error occurred while loading this page. \(error.localizedDescription)")
        }
    }
}
