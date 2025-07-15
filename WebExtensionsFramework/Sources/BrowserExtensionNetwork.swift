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
    class Node {
        fileprivate(set) weak var webView: BrowserExtensionWKWebView?
        let world: WKContentWorld
        let extensionId: String
        let trusted: Bool
        var setAccessLevelToken: String

        init(webView: BrowserExtensionWKWebView,
             world: WKContentWorld,
             extensionId: String,
             trusted: Bool,
             setAccessLevelToken: String) {
            self.webView = webView
            self.world = world
            self.extensionId = extensionId
            self.trusted = trusted
            self.setAccessLevelToken = setAccessLevelToken
        }
    }
    private var nodes = [Node]()

    public init() {}

    public func add(webView: BrowserExtensionWKWebView,
                    world: WKContentWorld,
                    browserExtension: BrowserExtension,
                    trusted: Bool,
                    setAccessLevelToken: String) {
        nodes.removeAll {
            $0.webView == nil || ($0.webView === webView && $0.extensionId == browserExtension.id.stringValue)
        }
        nodes.append(.init(webView: webView,
                           world: world,
                           extensionId: browserExtension.id.stringValue,
                           trusted: trusted,
                           setAccessLevelToken: setAccessLevelToken))
    }

    public func remove(webView: BrowserExtensionWKWebView) {
        nodes.removeAll { $0.webView == nil || $0.webView === webView }
    }

    func nodes(for extensionId: String) -> [Node] {
        nodes.removeAll { $0.webView == nil }
        return nodes.filter {
            $0.extensionId == extensionId
        }
    }
}
