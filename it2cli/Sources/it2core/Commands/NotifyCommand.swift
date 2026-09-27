import ArgumentParser
import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

// MARK: - notify

/// Send a push notification to the paired companion device (iTerm2 Buddy).
///
/// Reaches the app over the API and invokes the `iterm2.send_companion_notification`
/// built-in function in app context, which routes the title/body through the
/// companion push relay to the phone.
struct Notify: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "notify",
        abstract: "Send a push notification to the paired companion device."
    )

    @Argument(help: "Short notification title, a few words.")
    var title: String

    @Argument(help: "Notification body, one or two sentences.")
    var body: String

    func run(_ ctx: IT2Context) throws {
        let client = try ctx.makeClient()
        defer { client.disconnect() }

        let invoke = ITMInvokeFunctionRequest()
        invoke.app = ITMInvokeFunctionRequest_App()
        invoke.invocation = "iterm2.send_companion_notification(title: \(jsonString(title)), body: \(jsonString(body)))"

        let request = ITMClientOriginatedMessage()
        request.id_p = client.nextId()
        request.invokeFunctionRequest = invoke

        let response = try client.send(request)
        guard response.submessageOneOfCase == .invokeFunctionResponse,
              let invokeResp = response.invokeFunctionResponse else {
            throw IT2Error.apiError("No invoke function response")
        }

        if invokeResp.dispositionOneOfCase == .error {
            let reason = invokeResp.error?.errorReason ?? "unknown"
            throw IT2Error.apiError("Notification failed: \(reason)")
        }

        ctx.out("Notification sent")
    }
}
