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
        let io = IT2IO(stdout: stdout, stderr: stderr)
        return IT2Embedded.run(arguments: arguments, io: io, channel: ObjCChannelAdapter(channel))
    }
}

/// Bridges the Objective-C channel to the internal Swift `APIChannel`.
private final class ObjCChannelAdapter: APIChannel {
    private let objc: IT2ObjCChannel
    init(_ objc: IT2ObjCChannel) { self.objc = objc }
    func send(_ request: ITMClientOriginatedMessage) throws { try objc.send(request) }
    func receiveMessage() throws -> ITMServerOriginatedMessage { try objc.receiveMessage() }
    func disconnect() { objc.disconnect() }
}
