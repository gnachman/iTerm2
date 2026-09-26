import Foundation

// MARK: - Which iTerm2 a tmux pane belongs to
//
// A program in a tmux pane inherits IT2_SUITE (or, over SSH integration, IT2_SOCK and IT2_NONCE)
// from the tmux server, which froze them when it started. They name whichever iTerm2 connection
// happened to start the server, which after a detach and a reattach from elsewhere, or an iTerm2
// relaunch, is not the one showing the pane and may not exist at all.
//
// So each tmux -CC controller publishes its own record on the server when it attaches
// (TmuxController's advertiseIT2Client in the app): a global user option named
// @it2_client_<hex of tmux client name> whose value is c_<hex of a JSON record>. The record holds
// {"suite": ...} for a local iTerm2 or {"sock": ..., "nonce": ...} over SSH integration. One option
// per attacher, so concurrent attachers never overwrite each other.
//
// This reads them back. A record counts only if its client is still attached in control mode, as
// reported by list-clients, so a record that was never removed (its iTerm2 crashed, its ssh
// connection dropped) is ignored rather than tried. Among the live ones the most recently attached
// comes first, which matches the app's rule that the last attacher owns the pane. The pane's own
// environment is the caller's fallback for a server nobody live has claimed.
//
// Everything comes from tmux formats and options, nothing from the host OS, so it works the same
// wherever tmux runs. The remote counterpart lives in it2.py (the shell-integration repo).

enum TmuxOwnership {
    static let optionPrefix = "@it2_client_"
    static let recordTag = "c_"
    /// Distinguishes list-clients lines from show-options lines in the combined output.
    static let clientLinePrefix = "IT2CLIENT"

    /// The records of the iTerm2 clients currently attached to the tmux server that
    /// `environment` says this process is inside, most recently attached first. Empty when not
    /// inside tmux, when the server cannot be asked, or when no attached client has advertised.
    static func advertisedRecords(environment: [String: String]) -> [[String: String]] {
        guard let tmux = environment["TMUX"], !tmux.isEmpty,
              let server = TmuxAddress.server(inTMUX: tmux) else {
            return []
        }
        guard let output = queryServer(socketPath: server.socketPath) else {
            return []
        }
        return records(inServerOutput: output)
    }

    /// Parse the combined output of
    /// `list-clients -F 'IT2CLIENT\t#{client_name}\t#{client_control_mode}\t#{client_created}'`
    /// and `show-options -g`. Split out so it can be tested without tmux.
    ///
    /// Anything that does not parse is skipped: a record is advisory, and a malformed one must
    /// not take down the lookup for the well-formed ones next to it.
    static func records(inServerOutput output: String) -> [[String: String]] {
        // Client name -> attach time, for attached control-mode clients only. A missing
        // client_control_mode (very old tmux prints nothing for an unknown format) is accepted;
        // only an explicit 0 rejects.
        var attachedAt = [String: Int]()
        var recordsByClient = [String: [String: String]]()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix(clientLinePrefix + "\t") {
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 4 else {
                    continue
                }
                let name = String(fields[1])
                if fields[2] == "0" {
                    continue
                }
                attachedAt[name] = Int(fields[3]) ?? 0
                continue
            }
            guard line.hasPrefix(optionPrefix) else {
                continue
            }
            // "@it2_client_<hex> <value>". show-options only quotes a value that needs it, and
            // ours never does, but strip quotes anyway in case that changes.
            guard let space = line.firstIndex(of: " ") else {
                continue
            }
            let optionName = line[line.startIndex..<space]
            var value = Substring(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            guard value.hasPrefix(recordTag),
                  let nameData = hexDecode(optionName.dropFirst(optionPrefix.count)),
                  let name = String(data: nameData, encoding: .utf8),
                  let recordData = hexDecode(value.dropFirst(recordTag.count)),
                  let json = try? JSONSerialization.jsonObject(with: recordData),
                  let record = json as? [String: String] else {
                continue
            }
            recordsByClient[name] = record
        }
        // Newest attach first; name as a tiebreaker so the order is deterministic.
        let ordered = attachedAt.keys.sorted { lhs, rhs in
            let l = attachedAt[lhs]!
            let r = attachedAt[rhs]!
            return l != r ? l > r : lhs < rhs
        }
        return ordered.compactMap { recordsByClient[$0] }
    }

    /// Lowercase or uppercase hex, even length, no separators. Nil for anything else.
    static func hexDecode<S: StringProtocol>(_ hex: S) -> Data? {
        let utf8 = Array(hex.utf8)
        guard utf8.count % 2 == 0 else {
            return nil
        }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
            default: return nil
            }
        }
        var data = Data(capacity: utf8.count / 2)
        var i = 0
        while i < utf8.count {
            guard let hi = nibble(utf8[i]), let lo = nibble(utf8[i + 1]) else {
                return nil
            }
            data.append(hi << 4 | lo)
            i += 2
        }
        return data
    }

    /// The tmux invocation, as argv after the socket. One process for both queries: tmux runs a
    /// `;`-separated command sequence in a single client. The format uses real tab characters,
    /// since tmux does not interpret backslash escapes in a format string.
    static func queryArguments(socketPath: String) -> [String] {
        let format = [clientLinePrefix, "#{client_name}", "#{client_control_mode}", "#{client_created}"]
            .joined(separator: "\t")
        return ["tmux", "-S", socketPath, "list-clients", "-F", format, ";", "show-options", "-g"]
    }

    /// Run the query and return its stdout, or nil if tmux cannot be run, fails, or does not
    /// answer promptly. A server that has stopped responding must not make every it2 call hang,
    /// so the read happens on another thread and the wait is bounded; on timeout the client is
    /// killed and the pane's own environment is a good enough answer.
    private static func queryServer(socketPath: String) -> String? {
        return runCapturingStdout(executable: "/usr/bin/env",
                                  arguments: queryArguments(socketPath: socketPath),
                                  timeout: 2)
    }

    /// Run a process and return its stdout if it exits 0 within `timeout` seconds. Internal so
    /// the timeout can be tested with a stand-in executable.
    static func runCapturingStdout(executable: String,
                                   arguments: [String],
                                   timeout: TimeInterval) -> String? {
        let process = Process()
        // Through env so the same tmux the pane was started by is found on $PATH, wherever it is
        // installed.
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        // The read blocks until the write end closes, which is when the child exits. It must not
        // block the thread that enforces the timeout, so it runs elsewhere and signals when done;
        // a large output therefore cannot fill the pipe and deadlock either.
        let output = OutputBox()
        let finishedReading = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            output.data = pipe.fileHandleForReading.readDataToEndOfFile()
            finishedReading.signal()
        }
        do {
            try process.run()
        } catch {
            // Unblock the reader: nothing will ever write to the pipe.
            try? pipe.fileHandleForWriting.close()
            return nil
        }
        // The parent's copy of the write end would otherwise keep the pipe open after the child
        // exits, and the reader would never see EOF.
        try? pipe.fileHandleForWriting.close()
        if finishedReading.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(decoding: output.data, as: UTF8.self)
    }

    /// Carries the reader's result across threads; the semaphore orders the write before the read.
    private final class OutputBox {
        var data = Data()
    }
}
