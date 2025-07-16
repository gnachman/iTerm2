import Foundation
import BrowserExtensionShared

/// Handler for chrome.runtime.sendMessage API calls
@MainActor
class RuntimeSendMessageHandler: RuntimeSendMessageHandlerProtocol {
    
    /// sendMessage requires no permissions
    var requiredPermissions: [BrowserExtensionAPIPermission] { [] }

    private func decodedOptions(_ obj: Any) -> [String: Any]? {
        guard let string = obj as? String else {
            return nil
        }
        if string == "null" || string == "undefined" {
            return [:]
        }
        if let string = obj as? String,
           let data = string.data(using: .utf8),
           let anyCodable = try? JSONDecoder().decode(AnyJSONCodable.self, from: data),
           let result = anyCodable.value as? [String: Any] {
            if Set(result.keys).subtracting(Set(["includeTlsChannelId"])).isEmpty {
                // It contains only valid options keys
                return result
            } else {
                // Contains non-options keys
                return nil
            }
        }
        return nil
    }

    private func decodedString(_ obj: Any) -> String? {
        if let encodedString = obj as? String,
           let encodedData = encodedString.data(using: .utf8),
           let decodedString = try? JSONDecoder().decode(String.self, from: encodedData) {
            return decodedString
        }
        return nil
    }

    struct SendMessageArguments {
        var extensionId: String?
        var message: String
        var options: [String: Any] = [:]
    }

    private func parsedArguments(_ args: [AnyJSONCodable]) throws -> SendMessageArguments {
        // MDN says:
        // Depending on the arguments it is given, this API is sometimes ambiguous. The following rules are used:
        //
        // if one argument is given, it is the message to send, and the message will be sent internally.
        //
        // if two arguments are given:
        //
        // the arguments are interpreted as (message, options), and the message is sent internally, if the second argument is any of the following:
        //
        // a valid options object (meaning, it is an object which contains only the properties of options that the browser supports)
        // null
        // undefined
        // otherwise, the arguments are interpreted as (extensionId, message). The message will be sent to the extension identified by extensionId.
        //
        // if three arguments are given, the arguments are interpreted as (extensionId, message, options). The message will be sent to the extension identified by extensionId.


        // Parse arguments based on count and types
        switch args.count {
        case 1:
            // sendMessage(message)
            guard let messageArg = args[0].value as? String else {
                throw BrowserExtensionError.internalError("Message must be an encoded JSON object")
            }
            return SendMessageArguments(message: messageArg)

        case 2:
            if let messageArg = args[0].value as? String,
               let possibleOptionsDict = decodedOptions(args[1].value) {
                return SendMessageArguments(message: messageArg, options: possibleOptionsDict)
            } else if let extensionIdArg = decodedString(args[0].value),
                      let messageArg = args[1].value as? String {
                return SendMessageArguments(extensionId: extensionIdArg, message: messageArg)
            } else {
                throw BrowserExtensionError.internalError("Invalid argument types for sendMessage")
            }

        case 3:
            // sendMessage(extensionId, message, options)
            guard let extensionIdArg = decodedString(args[0].value),
                  let messageArg = args[1].value as? String,
                  let optionsArg = decodedOptions(args[2].value) else {
                throw BrowserExtensionError.internalError("Invalid argument types for sendMessage")
            }
            return SendMessageArguments(extensionId: extensionIdArg,
                                        message: messageArg,
                                        options: optionsArg)

        default:
            throw BrowserExtensionError.internalError("Too many arguments for sendMessage")
        }
    }

    func handle(request: RuntimeSendMessageRequest,
                context: BrowserExtensionContext) async throws -> AnyJSONCodable {
        // Parse arguments based on sendMessage signature variations:
        // 1 arg:  sendMessage(message)
        // 2 args: sendMessage(message, options) OR sendMessage(extensionId, message)
        // 3 args: sendMessage(extensionId, message, options)

        let args = request.args
        guard !args.isEmpty else {
            throw BrowserExtensionError.internalError("sendMessage requires at least one argument")
        }

        let arguments = try parsedArguments(args)

        guard let webView = context.webView else {
            context.logger.error("Context has no webView. Throw noMessageReceiver")
            throw BrowserExtensionError.noMessageReceiver
        }
        let messageSender = await BrowserExtensionContext.MessageSender(
            sender: context.browserExtension,
            senderWebview: webView,
            tab: context.tab,
            frameId: context.frameId,
            role: context.role)
        context.logger.info("Will publish \(arguments.message) to \(arguments.extensionId ?? "(nil)") from \(messageSender) with options \(arguments.options)")
        let obj = try await context.router.publish(message: arguments.message,
                                                   requestId: request.requestId,
                                                   extensionId: arguments.extensionId,
                                                   sender: messageSender,
                                                   sendingWebView: webView,
                                                   options: arguments.options)
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
