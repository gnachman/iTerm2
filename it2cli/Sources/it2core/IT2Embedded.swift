import Foundation

/// Output/interaction sinks the host supplies when running the it2 command tree
/// in-process (e.g. embedded in iTerm2, streaming over an SSH-integration channel).
public struct IT2IO {
    public var stdout: (String) -> Void
    public var stderr: (String) -> Void
    public var confirm: (String) -> Bool

    public init(stdout: @escaping (String) -> Void,
                stderr: @escaping (String) -> Void,
                confirm: @escaping (String) -> Bool = { _ in false }) {
        self.stdout = stdout
        self.stderr = stderr
        self.confirm = confirm
    }
}

/// Entry point for running the it2 command tree in-process instead of as the
/// standalone binary.
///
/// The host supplies the I/O sinks and an `APIChannel` that dispatches requests
/// to the local iTerm2 API server. Returns the process-style exit code (0 on
/// success, `IT2Error.exitCode`, an `IT2Exit` code, or an ArgumentParser exit
/// code). Nothing is written to the real process stdio and the process is never
/// terminated, which is what makes it safe to call inside iTerm2.
public enum IT2Embedded {
    public static func run(arguments: [String], io: IT2IO, channel: APIChannel) -> Int32 {
        let context = IT2Context(
            out: io.stdout,
            err: io.stderr,
            confirm: io.confirm,
            makeClient: { APIClient(channel: channel) },
            installsSignalHandlers: false,
            isRemote: true
        )
        return runToExitCode(arguments, context)
    }
}
