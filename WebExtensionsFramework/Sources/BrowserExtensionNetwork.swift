//
//  BrowserExtensionNetwork.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/7/25.
//

import Foundation
import WebKit

/// A collection of objects that can communicate with each other.
class BrowserExtensionNetwork {
    private class Node {
        weak var webView: WKWebView?
        var extensionId: String
        init(webView: WKWebView, extensionId: String) {
            self.webView = webView
            self.extensionId = extensionId
        }
    }
    private var nodes = [Node]()

    func add(webView: WKWebView, browserExtension: BrowserExtension) {
        nodes.removeAll { $0.webView == nil }
        nodes.append(.init(webView: webView, extensionId: browserExtension.id.uuidString))
    }

    func webViews(for extensionId: String) -> [WKWebView] {
        nodes.removeAll { $0.webView == nil }
        return nodes.compactMap {
            if $0.extensionId == extensionId {
                return $0.webView
            }
            return nil
        }
    }
}
