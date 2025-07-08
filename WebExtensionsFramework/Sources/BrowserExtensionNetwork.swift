//
//  BrowserExtensionNetwork.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/7/25.
//

import Foundation
import WebKit

/// A collection of objects that can communicate with each other.
public class BrowserExtensionNetwork {
    private class Node {
        weak var webView: BrowserExtensionWKWebView?
        var extensionId: String
        init(webView: BrowserExtensionWKWebView, extensionId: String) {
            self.webView = webView
            self.extensionId = extensionId
        }
    }
    private var nodes = [Node]()

    public init() {}

    public func add(webView: BrowserExtensionWKWebView, browserExtension: BrowserExtension) {
        nodes.removeAll {
            $0.webView == nil || ($0.webView === webView && $0.extensionId == browserExtension.id.uuidString)
        }
        nodes.append(.init(webView: webView, extensionId: browserExtension.id.uuidString))
    }

    public func remove(webView: BrowserExtensionWKWebView) {
        nodes.removeAll { $0.webView == nil || $0.webView === webView }
    }

    public func webViews(for extensionId: String) -> [BrowserExtensionWKWebView] {
        nodes.removeAll { $0.webView == nil }
        return nodes.compactMap {
            if $0.extensionId == extensionId {
                return $0.webView
            }
            return nil
        }
    }
}
