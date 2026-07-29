import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the modulemap
#endif

// Objective-C-facing bridge so the app can drive the embedded it2 command tree
// WITHOUT a Swift `import it2core`. A Swift import would force the importing
// target to resolve it2core's whole transitive module graph (ProtobufRuntime,
// Yams/CYaml, ArgumentParser); consuming the generated it2core-Swift.h from
// Objective-C avoids that entirely.

/// The app implements this to dispatch API messages to the local iTerm2 API
/// server (an in-process route to iTermAPIServer). Mirrors the internal
/// `APIChannel`, but Objective-C-compatible.
@objc(IT2Channel)
public protocol IT2ObjCChannel {
    /// Send a request. The caller assigns `id_p`; the channel only transports.
    func send(_ request: ITMClientOriginatedMessage) throws
    /// Block until the next server message is available and return it.
    func receiveMessage() throws -> ITMServerOriginatedMessage
    func disconnect()
}

/// The single source of truth for the disconnect-error contract between the in-process it2
/// channel's PRODUCER (iTermInProcessIt2.m, which raises the NSError) and its CONSUMER
/// (ObjCChannelAdapter below, which maps it to an exit code). Both ends reference these
/// constants -- exposed to Objective-C via the generated it2core-Swift.h -- so renaming the
/// domain or changing a code updates both and they cannot drift.
@objc(IT2ChannelDisconnect)
public final class IT2ChannelDisconnect: NSObject {
    /// NSError domain the in-process channel raises from receiveMessage() on disconnect.
    @objc public static let domain = "com.googlecode.iterm2.it2"
    /// Client cancel (remote Ctrl+C): unwinds to a clean exit 0.
    @objc public static let cancelCode = 1
    /// Server abort / response parse failure: surfaced as an error (not success).
    @objc public static let abortCode = 2
}

@objc(IT2Runner)
public final class IT2Runner: NSObject {
    /// Parse and run `arguments` (excluding the executable name), routing output
    /// to the blocks and dispatching API messages through `channel`. Returns the
    /// process-style exit code. Never touches real process stdio and never
    /// terminates the process, which is what makes it safe to call inside iTerm2.
    // The ObjC selector deliberately uses stdoutHandler:/stderrHandler: rather than
    // stdout:/stderr:. In an Objective-C translation unit <stdio.h> #defines
    // stdout -> __stdoutp and stderr -> __stderrp, so an ObjC call site written as
    // `[IT2Runner runArguments:... stdout:... stderr:...]` is preprocessed into the
    // selector runArguments:__stdoutp:__stderrp:channel:. Swift's @objc(...) string is
    // NOT preprocessed, so a stdout:/stderr: selector here would never match the
    // preprocessed ObjC call site and would crash with an unrecognized selector at
    // runtime. Keep the Swift parameter labels as stdout/stderr for natural Swift use.
    @objc(runArguments:stdoutHandler:stderrHandler:channel:)
    public static func run(_ arguments: [String],
                           stdout: @escaping (String) -> Void,
                           stderr: @escaping (String) -> Void,
                           channel: IT2ObjCChannel) -> Int32 {
        // There is no interactive prompt back to the remote it2.py, so a confirm-gated
        // command (e.g. `it2 app quit`) cannot ask. Rather than silently auto-decline and
        // print a bare "Aborted!", explain and point at --force, then decline.
        let io = IT2IO(stdout: stdout, stderr: stderr, confirm: { prompt in
            stderr("\(prompt) Cannot prompt for confirmation over SSH integration; re-run with --force.")
            return false
        })
        return IT2Embedded.run(arguments: arguments, io: io, channel: ObjCChannelAdapter(channel))
    }
}

/// Bridges the Objective-C channel to the internal Swift `APIChannel`.
private final class ObjCChannelAdapter: APIChannel {
    // The in-process host channel throws an NSError in this domain from receiveMessage()
    // when it disconnects. The code distinguishes a client cancel from a server-side
    // failure; the contract is IT2ChannelDisconnect, shared with iTermInProcessIt2.m.
    private let objc: IT2ObjCChannel
    init(_ objc: IT2ObjCChannel) { self.objc = objc }
    func send(_ request: ITMClientOriginatedMessage) throws { try objc.send(request) }
    func receiveMessage() throws -> ITMServerOriginatedMessage {
        do {
            return try objc.receiveMessage()
        } catch let error as NSError where error.domain == IT2ChannelDisconnect.domain {
            if error.code == IT2ChannelDisconnect.cancelCode {
                // Streaming command cancelled (e.g. monitor --follow stopped with a remote
                // Ctrl+C): unwind to a clean exit 0 with no stderr, matching the standalone
                // binary's SIGINT->exit(0).
                throw IT2Exit(code: 0)
            }
            // Server aborted the connection (API disabled / server stop) or a response
            // frame failed to parse: a genuine failure. Surface it as an error (exit 2)
            // rather than silently reporting the command as success.
            throw IT2Error.connectionError(error.localizedDescription)
        }
    }
    func disconnect() { objc.disconnect() }
}
