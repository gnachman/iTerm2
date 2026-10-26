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
    /// True only for the standalone `it2` binary, where a `monitor` command may install
    /// a process-global SIGINT handler that exits the process on Ctrl+C. False when the
    /// command tree is embedded in iTerm2: a remote Ctrl+C arrives as a channel
    /// disconnect that makes `receiveMessage()` throw and unwinds the streaming loop, so
    /// installing a process-global SIGINT->exit(0) would take the whole app down.
    let installsSignalHandlers: Bool
    /// True when the command tree runs embedded in iTerm2 on behalf of a REMOTE it2 over SSH
    /// integration (its stdout streams back to the remote host). Commands that mint or export
    /// durable local credentials, or otherwise escape the per-session, revocable API grant the
    /// ssh authorization prompt implies, are refused in this mode (see runParsedCommand and
    /// RemoteForbiddenCommand). False for the standalone binary running locally on the Mac.
    let isRemote: Bool
    /// Which machine this invocation is running on, for tmux pane addressing: nil on the Mac,
    /// otherwise the clientUniqueID of the SSH-integration conductor carrying this invocation.
    ///
    /// Supplied by the host in `IT2Embedded.run`, never parsed from arguments, so a remote caller
    /// cannot name a connection other than the one it arrived on. A pane address ($TMUX) only
    /// means anything within one machine, so this is what lets a remote `tmux -CC` resolve its own
    /// panes without a local server being able to answer for them. See TmuxPaneLocator in the app.
    let originIdentifier: String?
    /// The iTerm2 session this invocation arrived over, for a remote call, or nil locally.
    ///
    /// Host-supplied and never from arguments, like originIdentifier: a remote controls its own
    /// argv, so a value taken from there would let it name any session. See
    /// APIClient.originSessionID for why a remote call needs this at all.
    let originSessionID: String?
    /// The invocation's standard input, read to EOF on first use. For the standalone binary that
    /// is the process's stdin; embedded in iTerm2 it is whatever the remote it2 sent, which is
    /// how a hook's JSON payload reaches `handle-agent-hook`.
    let stdin: () -> Data
    /// The invocation's environment. For the standalone binary that is the process's; embedded in
    /// iTerm2 it is the allowlisted subset the remote it2 forwarded. Commands read this rather
    /// than `ProcessInfo`, which in-process would be iTerm2's own environment.
    let environment: [String: String]
}

extension IT2Context {
    /// Set by a test to observe the context a run was given. The alternative is asserting
    /// through a command's side effects, which cannot distinguish "the value never arrived"
    /// from "the command ignored it" -- and the first is the failure mode that matters here.
    static var captureForTesting: ((IT2Context) -> Void)?

    /// Serialize to pretty-printed JSON and write it to stdout.
    func printJSON(_ object: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            out(str)
        }
    }

    /// Confirm a destructive action, throwing `IT2Error.cancelled` when the user declines
    /// (unless `force` bypasses the prompt entirely). Centralizes the decline contract shared
    /// by the quit/close commands so it cannot drift between them.
    func confirmOrThrow(_ prompt: String, force: Bool) throws {
        if !force && !confirm(prompt) {
            throw IT2Error.cancelled
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
        makeClient: {
            let client = try APIClient.connect()
            // So a command with no explicit target can tell which session it is running in,
            // rather than falling back to whatever the user is looking at.
            client.callerEnvironment = ProcessInfo.processInfo.environment
            return client
        },
        installsSignalHandlers: true,
        isRemote: false,
        originIdentifier: nil,
        originSessionID: nil,
        stdin: {
            // Only read when asked, and only when something is piped in: reading a tty would
            // block waiting for the user.
            if isatty(FileHandle.standardInput.fileDescriptor) != 0 {
                return Data()
            }
            return FileHandle.standardInput.readDataToEndOfFile()
        },
        environment: ProcessInfo.processInfo.environment
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
