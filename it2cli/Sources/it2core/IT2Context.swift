import Foundation

/// Execution environment handed to each command: where output goes, how to
/// prompt, and how to obtain an API client.
///
/// The standalone binary builds one backed by the process's stdio and a socket
/// client (`IT2Context.standalone`). When the command tree is embedded in
/// iTerm2 (so `it2` can work over SSH integration), each remote invocation
/// builds its own context backed by the ssh channel and an in-process client.
struct IT2Context {
    /// Write a line to standard output. A trailing newline is added.
    let out: (String) -> Void
    /// Write a line to standard error. A trailing newline is added.
    let err: (String) -> Void
    /// Prompt for confirmation; returns true to proceed. The caller decides
    /// what to do when the user declines.
    let confirm: (String) -> Bool
    /// Obtain an API client for this invocation.
    let makeClient: () throws -> APIClient
}

extension IT2Context {
    /// Serialize to pretty-printed JSON and write it to stdout.
    func printJSON(_ object: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            out(str)
        }
    }

    /// The context used by the standalone `it2` binary: real stdio plus a
    /// client connected over iTerm2's local unix domain socket.
    static let standalone = IT2Context(
        out: { line in FileHandle.standardOutput.write(Data((line + "\n").utf8)) },
        err: { line in FileHandle.standardError.write(Data((line + "\n").utf8)) },
        confirm: { prompt in
            FileHandle.standardError.write(Data("\(prompt) [y/N] ".utf8))
            if let line = Swift.readLine() {
                return line.lowercased().hasPrefix("y")
            }
            return false
        },
        makeClient: { try APIClient.connect() }
    )
}

/// Commands migrated to the explicit-context model. The driver prefers this
/// over `ParsableCommand.run()` when a command conforms, so commands can be
/// converted one at a time while the rest keep working via the default path.
protocol IT2Runnable {
    mutating func run(_ context: IT2Context) throws
}

/// Signals that a command wants to terminate with a specific process exit code,
/// carrying no message. Realized at the boundary: the standalone binary calls
/// Foundation.exit(code); the embedded host sends the code back to the remote
/// it2 over the ssh channel. Thrown by `IT2Context.exit(_:)`.
struct IT2Exit: Error {
    let code: Int32
}

extension IT2Context {
    /// Terminate the current command with `code`, analogous to exit(2). It
    /// unwinds via a thrown `IT2Exit` instead of killing the process, so it is
    /// safe when the command runs embedded in iTerm2 (a direct Foundation.exit
    /// would take down the whole app). Print any message via `err` first; this
    /// carries none. `defer` blocks on the way out still run.
    func exit(_ code: Int32) throws -> Never {
        throw IT2Exit(code: code)
    }
}
