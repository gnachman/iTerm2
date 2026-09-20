import Foundation

/// Read metadata from an ordinary local tmux attachment without attaching a new client.
final class HarnessTmuxProbe {
    struct Client: Equatable {
        let executable: String
        let socketArguments: [String]
        let pid: Int32
    }
    struct Pane {
        let command: String
        let path: String
        let id: String
        let pid: Int32?
    }

    private struct Server: Hashable {
        let executable: String
        let arguments: [String]
    }
    private struct Cached {
        let text: String
        let date: Date
    }
    // Accessed on the main thread. All sidebars share one query per server every two seconds.
    private static var cache: [Server: Cached] = [:]
    private static var pending: [Server: [(String) -> Void]] = [:]

    static func socketArguments(_ arguments: [String]) -> [String]? {
        var result: [String] = []
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            if arg == "-S" || arg == "-L" {
                guard index + 1 < arguments.count else { return nil }
                result += [arg, arguments[index + 1]]
                index += 2
            } else if arg.hasPrefix("-S") || arg.hasPrefix("-L") {
                result += [String(arg.prefix(2)), String(arg.dropFirst(2))]
                index += 1
            } else if arg == "-f" {
                index += 2 // Never load the client's config into a probe.
            } else if arg.hasPrefix("-") {
                index += 1
            } else {
                break
            }
        }
        return result
    }

    static func read(_ client: Client, completion: @escaping (Pane?) -> Void) {
        let server = Server(executable: client.executable, arguments: client.socketArguments)
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.date) < 30 }
        if let cached = cache[server], now.timeIntervalSince(cached.date) < 2 {
            completion(parse(cached.text, clientPID: client.pid))
            return
        }
        let receive: (String) -> Void = { completion(parse($0, clientPID: client.pid)) }
        if pending[server] != nil {
            pending[server]?.append(receive)
            return
        }
        pending[server] = [receive]
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: client.executable)
            // -N prevents accidentally starting a server when the attachment has gone away.
            process.arguments = ["-N"] + client.socketArguments + ["list-clients", "-F",
                "#{client_pid}\u{1f}#{pane_id}\u{1f}#{pane_current_command}\u{1f}#{pane_current_path}\u{1f}#{pane_pid}"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "TMUX")
            process.environment = environment
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { finish(server, text: "") }
                return
            }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            finished.wait()
            timeout.cancel()
            let text = String(data: data, encoding: .utf8) ?? ""
            let result = process.terminationStatus == 0 ? text : ""
            DispatchQueue.main.async { finish(server, text: result) }
        }
    }

    private static func finish(_ server: Server, text: String) {
        cache[server] = Cached(text: text, date: Date())
        let callbacks = pending.removeValue(forKey: server) ?? []
        callbacks.forEach { $0(text) }
    }

    static func parse(_ text: String, clientPID: Int32) -> Pane? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, Int32(fields[0]) == clientPID else { continue }
            return Pane(command: String(fields[2]), path: String(fields[3]), id: String(fields[1]), pid: Int32(fields[4]))
        }
        return nil
    }
}
