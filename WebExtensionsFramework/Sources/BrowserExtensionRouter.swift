//
//  BrowserExtensionRouter.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/6/25.
//

import Foundation
import WebKit

/// Data source for providing content world information to the router
public protocol BrowserExtensionRouterDataSource: AnyObject {
    /// Get the content world for a given extension ID
    func contentWorld(for extensionId: String) async -> WKContentWorld?
}

/// Routes messages between different webviews.
/// The initial message is sent:
///     chrome.runtime.sendMessage -> chrome.runtime.onMessage.addListener
///     chrome.runtime.sendMessage -> chrome.runtime.onMessageExternal.addListener
///     chrome.tabs.sendMessage    -> chrome.runtime.onMessage.addListener
/// A listener may choose to send a reply, which goes to the sender's callback.
@MainActor
public class BrowserExtensionRouter {
    private let logger: BrowserExtensionLogger
    private let network: BrowserExtensionNetwork
    public weak var dataSource: BrowserExtensionRouterDataSource?

    class OutstandingRequest {
        weak var webView: BrowserExtensionWKWebView?
        var continuation: CheckedContinuation<Any?, Error>?

        init(webView: BrowserExtensionWKWebView,
             continuation: CheckedContinuation<Any?, Error>) {
            self.webView = webView
            self.continuation = continuation
        }
    }
    // requestId is the key
    private var outstandingRequests = [String: OutstandingRequest]()

    public init(network: BrowserExtensionNetwork,
                logger: BrowserExtensionLogger) {
        self.network = network
        self.logger = logger
    }

    public func sendReply(message: Any?,
                          requestId: String) {
        logger.debug("sendReply \(String(describing: message)) with request ID \(requestId)")
        if let outstandingRequest = outstandingRequests.removeValue(forKey: requestId) {
            outstandingRequest.continuation?.resume(with: .success(message))
        }
    }

    // Deliver a message from sendMessage to all webviews associated with a particular extension,
    // or, if none is given, the sender's extension. This returns the response, which comes
    // asynchronously.
    func publish(message: [String: Any],
                 requestId: String,  // Needed for recipient to respond
                 extensionId directedRecipient: String?,
                 sender: BrowserExtensionContext.MessageSender,
                 sendingWebView: BrowserExtensionWKWebView,
                 options: [String: Any]) async throws -> Any? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                outstandingRequests[requestId] = .init(webView: sendingWebView,
                                                       continuation: continuation)
                Task { @MainActor in
                    let destinationID = directedRecipient ?? sender.id
                    await reallyPublish(message: message,
                                        requestId: requestId,
                                        destinationID: destinationID,
                                        sender: sender,
                                        sendingWebView: sendingWebView,
                                        options: options)
                }
            }
        } catch {
            logger.error("Error publishing message \(message), requestId=\(requestId), extensionId=\(directedRecipient ?? "(self)"), sending webview=\(sendingWebView): \(error)")
            throw error
        }
    }

    private func reallyPublish(message: [String: Any],
                               requestId: String,
                               destinationID: String,
                               sender: BrowserExtensionContext.MessageSender,
                               sendingWebView: BrowserExtensionWKWebView,
                               options: [String: Any]) async {
        logger.debug("publish \(message) to extension \(destinationID) from \(sender)")

        let receiveNodes = network.nodes(for: destinationID)
        guard !receiveNodes.isEmpty else {
            logger.error("There are no webviews for extension \(destinationID) registered in the network. Throw noMessageReceiver")
            outstandingRequests.removeValue(forKey: requestId)?.continuation?.resume(throwing: BrowserExtensionError.noMessageReceiver)
            return
        }
        var anyKeepAlive = false
        var anyResponse = false
        var anyListenersInvoked = false
        for node in receiveNodes {
            guard let webview = node.webView else {
                continue
            }
            let isExternal = destinationID != sender.id
            logger.debug("Invoke listener in webview \(webview)")
            do {
                let messageJSON = try message.toJSONString()
                let senderJSON = try sender.toJSONString()
                let requestIdJSON = try requestId.toJSONString()
                
                let jsResult = try await webview.be_evaluateJavaScript(
                    "window.__EXT_invokeListener__(\(requestIdJSON), \(messageJSON), \(senderJSON), \(isExternal), false)",
                    in: nil,
                    in: node.world)
                logger.debug("JavaScript result: \(jsResult ?? "nil") type: \(type(of: jsResult))")
                guard let dict = jsResult as? [String: Any] else {
                    logger.error("Failed to cast JavaScript result to dictionary: \(jsResult ?? "nil")")
                    continue
                }
                let keepAlive = dict["keepAlive"]! as! Bool
                let responded = dict["responded"]! as! Bool
                let listenersInvoked = dict["listenersInvoked"]! as! Int
                anyKeepAlive ||= keepAlive
                anyResponse ||= responded
                anyListenersInvoked ||= (listenersInvoked > 0)
            } catch {
                logger.error("__EXT_invokeListener__ threw: \(error)")
            }
        }
        if !anyListenersInvoked {
            logger.error("No listener in the \(receiveNodes.count) webviews existed. Throw noMessageReceiver")
            outstandingRequests.removeValue(forKey: requestId)?.continuation?.resume(throwing: BrowserExtensionError.noMessageReceiver)
        } else if !anyKeepAlive && !anyResponse {
            outstandingRequests.removeValue(forKey: requestId)?.continuation?.resume(with: .success(nil))
        }
    }

    // Broadcast an event to all webviews for a specific extension (no reply expected)
    func broadcastEvent(functionName: String,
                       arguments jsonArgs: [String],
                       extensionId: String) async {
        logger.debug("Broadcasting event \(functionName) to extension \(extensionId)")

        let receiverNodes = network.nodes(for: extensionId)
        logger.debug("Found \(receiverNodes.count) webviews for extension \(extensionId)")
        guard !receiverNodes.isEmpty else {
            logger.error("No webviews for extension \(extensionId) to broadcast event to")
            return
        }

        for node in receiverNodes {
            guard let webView = node.webView else {
                continue
            }
            do {
                // Call the function with the provided arguments
                let script = "window.\(functionName)(\(jsonArgs.joined(separator: ", ")))"
                logger.debug("Execute:\n\(script)")
                _ = try await webView.be_evaluateJavaScript(script, in: nil, in: node.world)
                logger.debug("Successfully broadcasted \(functionName) to webview for extension \(extensionId)")
            } catch {
                logger.error("Failed to broadcast \(functionName) to webview for extension \(extensionId): \(error)")
            }
        }
    }

    func setStorageAreaAllowedInUntrustedContexts(allowed: Bool, in area: BrowserExtensionStorageArea, extensionId: UUID) async {
        for node in network.nodes(for: extensionId.uuidString) {
            guard let webView = node.webView else {
                continue
            }
            if !node.trusted {
                let flag = allowed ? "true" : "false"
                let token = node.setAccessLevelToken.asJSONFragment
                let areaName = switch area {
                case .session: "Session"
                case .local: "Local"
                case .sync: "Sync"
                case .managed: fatalError()
                }
                let script = "__ext_set\(areaName)Allowed(\(flag), \(token))"
                do {
                    _ = try await webView.be_evaluateJavaScript(script, in: nil, in: node.world)
                } catch {
                    logger.error("Failed to call __ext_setSessionAllowed in extension \(extensionId) world \(node.world.name ?? "(unnamed)"): \(error)")
                }
            }
        }
    }
}

infix operator ||= : AssignmentPrecedence

@discardableResult
func ||=(lhs: inout Bool, rhs: @autoclosure () -> Bool) -> Bool {
    if !lhs && rhs() {
        lhs = true
    }
    return lhs
}

extension Encodable {
    var asJSONObject: String {
        String(data: try! JSONSerialization.data(withJSONObject: self, options: []), encoding: .utf8)!
    }
    var asJSONFragment: String {
        String(data: try! JSONSerialization.data(withJSONObject: self, options: [.fragmentsAllowed]), encoding: .utf8)!
    }
    var asJSONObjectMaybe: String? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    func toJSONFragment() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: self, options: [.fragmentsAllowed])
        return String(data: data, encoding: .utf8)!
    }
}

