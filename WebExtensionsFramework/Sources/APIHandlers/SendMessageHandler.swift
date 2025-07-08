import Foundation
import BrowserExtensionShared

/// Handler for chrome.runtime.sendMessage API calls
class SendMessageHandler: SendMessageHandlerProtocol {
    func handle(request: SendMessageRequest,
                context: BrowserExtensionContext) async throws -> AnyJSONCodable {
        // Parse arguments based on sendMessage signature variations:
        // 1 arg:  sendMessage(message)
        // 2 args: sendMessage(message, options) OR sendMessage(extensionId, message)
        // 3 args: sendMessage(extensionId, message, options)

        let args = request.args
        guard !args.isEmpty else {
            throw BrowserExtensionError.internalError("sendMessage requires at least one argument")
        }

        var extensionId: String?
        var message: [String: Any]
        var options: [String: Any]?

        // Parse arguments based on count and types
        switch args.count {
        case 1:
            // sendMessage(message)
            guard let messageArg = args[0].value as? [String: Any] else {
                throw BrowserExtensionError.internalError("Message must be a JSON object")
            }
            message = messageArg

        case 2:
            // Need to determine if it's (extensionId, message) or (message, options)
            // If first arg is string, it's (extensionId, message)
            if let firstArgString = args[0].value as? String {
                // sendMessage(extensionId, message)
                extensionId = firstArgString
                guard let messageArg = args[1].value as? [String: Any] else {
                    throw BrowserExtensionError.internalError("Message must be a JSON object")
                }
                message = messageArg
            } else if let firstArgDict = args[0].value as? [String: Any],
                      let secondArgDict = args[1].value as? [String: Any] {
                // sendMessage(message, options)
                message = firstArgDict
                options = secondArgDict
            } else {
                throw BrowserExtensionError.internalError("Invalid argument types for sendMessage")
            }

        case 3:
            // sendMessage(extensionId, message, options)
            guard let extensionIdArg = args[0].value as? String,
                  let messageArg = args[1].value as? [String: Any],
                  let optionsArg = args[2].value as? [String: Any] else {
                throw BrowserExtensionError.internalError("Invalid argument types for sendMessage")
            }
            extensionId = extensionIdArg
            message = messageArg
            options = optionsArg

        default:
            throw BrowserExtensionError.internalError("Too many arguments for sendMessage")
        }

        guard let webView = context.webView else {
            throw BrowserExtensionError.noMessageReceiver
        }
        let messageSender = await BrowserExtensionContext.MessageSender(
            sender: context.browserExtension,
            senderWebview: webView,
            tab: context.tab,
            frameId: context.frameId)
        context.logger.info("Will publish \(message) to \(extensionId ?? "(nil)") from \(messageSender) with options \(options ?? [:])")
        let obj = try await context.router.publish(message: message,
                                                   requestId: request.requestId,
                                                   extensionId: extensionId,
                                                   sender: messageSender,
                                                   sendingWebView: webView,
                                                   options: options ?? [:])
        context.logger.debug("SendMessageHandler received from router: \(obj ?? "nil") type: \(type(of: obj))")
        let result = AnyJSONCodable(obj)
        context.logger.debug("SendMessageHandler returning AnyJSONCodable with value: \(result.value) type: \(type(of: result.value))")
        return result
    }
}

// TODO: Add message listener registry
// TODO: Add support for different response modes (single, multiple, etc.)
// TODO: Add support for extension-to-extension messaging
// TODO: Add support for content script messaging
// TODO: Add timeout handling for responses
// TODO: Add support for message options (e.g., includeTlsChannelId)
