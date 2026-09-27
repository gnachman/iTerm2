//
//  SendCompanionNotificationBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Bridges an app-context function call (used by `it2 notify`) to the companion
//  push path, so a plaintext push can be sent to the paired phone from the CLI.
//  Mirrors the gating of the orchestrator `notify` tool: the push only goes out
//  when a device is paired and authorized. There is no chat context here, so the
//  per-chat mute check does not apply.
//

import Foundation

@objc(iTermSendCompanionNotificationBuiltInFunction)
class SendCompanionNotificationBuiltInFunction: NSObject {
    private static let argTitle = "title"
    private static let argBody = "body"
}

extension SendCompanionNotificationBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.send-companion-notification",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    @objc(registerBuiltInFunction)
    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "send_companion_notification",
            arguments: [argTitle: NSString.self,
                        argBody: NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: [],
            sideEffectsPlaceholder: "[send_companion_notification]") { parameters, completion in
                guard let title = parameters[argTitle] as? String,
                      let body = parameters[argBody] as? String else {
                    completion(nil, error(message: "Missing required argument"))
                    return
                }
                Task { @MainActor in
                    guard CompanionPushRegistry.canNotify else {
                        completion(nil, error(message: unavailableReason()))
                        return
                    }
                    do {
                        try await CompanionPushSender.send(title: title, body: body)
                        completion(nil, nil)
                    } catch {
                        completion(nil, self.error(message: "Notification delivery failed: \(error.localizedDescription)"))
                    }
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    /// A user-facing explanation for why no push can be sent, distinguishing the
    /// common cases so the CLI user knows what to fix on their phone.
    @MainActor
    private static func unavailableReason() -> String {
        switch CompanionPushRegistry.authorization {
        case .denied:
            return "Notifications are turned off for iTerm2 Buddy. Enable them in iOS Settings on the paired phone."
        case .notDetermined:
            return "Notifications are not enabled on the paired phone yet."
        case .authorized:
            return "No paired companion device is registered for notifications."
        }
    }
}
